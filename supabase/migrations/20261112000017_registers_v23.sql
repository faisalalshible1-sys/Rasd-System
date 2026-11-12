-- =====================================================================
-- الإصدار 2.3 من «سجل المخاطر ومتابعة المشاريع» والإصدار 2.1 من «تحليل SWOT»
-- يُشغَّل بعد الملف 20261111000016_project_tracking.sql، ويمكن إعادة تشغيله دون ضرر.
--
--  1. الاسم المختصر للمشروع في لوحة العرض (pm_projects.display_name)
--  2. إعداد «الحد الأدنى لعدد مكونات التقييم» لإصدار الدرجة المركّبة للشركات (افتراضياً 2 من 4)
--  3. نوعا مشروع جديدان: «إزالة الركام والمخلفات والهدم» و«توريد وتركيب»
--  4. البرنامج الزمني الفعلي للعقود التسعة (النوع، الموقع، الوضع، التاريخان، الاسم المختصر) بمطابقة رقم العقد
--  5. قيمة العقد للعقود التي لم تُسجَّل قيمتها بعد
--  6. SWOT: العاملان S11 وS12 (عناصر الأمن، وعناصر السلامة والأمن الصناعي) والاستراتيجية ST6 والإجراء A22
--
-- لا يُستبدل أي شيء أدخله المستخدم: تُملأ الحقول الفارغة فقط، وتُضاف البنود إن لم تكن رموزها مستخدمة.
-- =====================================================================

do $$
begin
  if to_regclass('public.pm_projects') is null then
    raise exception 'شغّل الملف 20261111000016_project_tracking.sql أولاً ثم أعد تشغيل هذا الملف';
  end if;
end $$;

-- ---------------------------------------------------------------------
-- 1. الاسم المختصر للعرض
-- ---------------------------------------------------------------------
alter table public.pm_projects add column if not exists display_name text not null default '';
do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'pm_projects_display_name_len') then
    alter table public.pm_projects add constraint pm_projects_display_name_len check (length(display_name) <= 80);
  end if;
end $$;

-- حفظ البرنامج الزمني مع الاسم المختصر للعرض
create or replace function public.save_project_schedule(p_project uuid, p_data jsonb)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  old_row public.pm_projects;
  new_row public.pm_projects;
  v_start date := public.jdate(p_data, 'start_date', 'تاريخ البداية');
  v_end   date := public.jdate(p_data, 'end_date', 'تاريخ النهاية التعاقدي');
  v_ch    jsonb;
begin
  if not exists (select 1 from public.projects where id = p_project and merged_into is null) then
    raise exception 'العقد غير موجود' using errcode = '22023';
  end if;
  if not public.can_edit_schedule(p_project) then
    raise exception 'البرنامج الزمني يحدّثه مكتب المدير ومكتب العقود والقسم المشرف على العقد' using errcode = '42501';
  end if;
  if jsonb_typeof(coalesce(p_data, 'null'::jsonb)) <> 'object' then
    raise exception 'بيانات غير صالحة' using errcode = '22023';
  end if;
  if v_start is not null and v_end is not null and v_end < v_start then
    raise exception 'تاريخ النهاية التعاقدي قبل تاريخ البداية' using errcode = '22023';
  end if;
  select * into old_row from public.pm_projects where project_id = p_project for update;
  insert into public.pm_projects (project_id, project_type, location, consultant, op_status, start_date, end_date, notes,
                                  display_name, updated_at, updated_by)
  values (p_project, public.jtext(p_data, 'project_type', 60, 'نوع المشروع'), public.jtext(p_data, 'location', 120, 'الموقع / القطاع'),
          public.jtext(p_data, 'consultant', 120, 'الاستشاري / جهة الإشراف'),
          public.jpick(p_data, 'op_status', array['not_started', 'running', 'suspended', 'completed', 'prov_accepted', 'final_accepted'],
                       'running', 'الوضع التشغيلي'),
          v_start, v_end, public.jtext(p_data, 'notes', 1000, 'ملاحظات'),
          -- الإصدارات السابقة من التطبيق لا ترسل الاسم المختصر: يبقى كما هو
          case when p_data ? 'display_name' then public.jtext(p_data, 'display_name', 80, 'الاسم المختصر للعرض')
               else coalesce(old_row.display_name, '') end,
          now(), auth.uid())
  on conflict (project_id) do update set
    project_type = excluded.project_type, location = excluded.location, consultant = excluded.consultant,
    op_status = excluded.op_status, start_date = excluded.start_date, end_date = excluded.end_date, notes = excluded.notes,
    display_name = excluded.display_name,
    updated_at = excluded.updated_at, updated_by = excluded.updated_by
  returning * into new_row;
  v_ch := public.jsonb_changes(to_jsonb(old_row), to_jsonb(new_row), array['updated_at', 'updated_by', 'project_id']);
  if old_row.project_id is null or v_ch <> '{}'::jsonb then
    perform public.write_audit('pm.schedule', p_project, null, jsonb_build_object('changes', v_ch));
  end if;
end;
$$;

-- ---------------------------------------------------------------------
-- 2. الإعدادات: الحد الأدنى لمكونات التقييم (عدد صحيح من 1 إلى 4)
-- ---------------------------------------------------------------------
create or replace function public.set_setting(p_key text, p_value jsonb)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  v_old jsonb;
  ok    boolean;
begin
  if p_key = 'risk.config' then
    -- تحقق إضافي للإصدار 2.0: دورية المراجعة لكل مستوى، وقائمة منفذي الإجراءات
    if jsonb_typeof(p_value -> 'levels') = 'array'
       and not coalesce((select bool_and(public.pm_num_ok(x, 'review_days', 1, 365)) from jsonb_array_elements(p_value -> 'levels') x), true) then
      raise exception 'دورية المراجعة من 1 إلى 365 يوماً' using errcode = '22023';
    end if;
    if not public.valid_text_list(p_value -> 'executors', 40, 60) then
      raise exception 'قيمة غير صالحة للإعداد %', p_key using errcode = '22023';
    end if;
  end if;
  if p_key <> 'pm.config' then
    perform public.set_setting_v15(p_key, p_value);
    return;
  end if;

  if not public.is_director() then
    raise exception 'الإعدادات من صلاحية مدير المكتب وحده' using errcode = '42501';
  end if;
  ok := jsonb_typeof(p_value) = 'object' and length(p_value::text) <= 16000
    and public.valid_text_list(p_value -> 'project_types', 40, 60)
    and public.valid_text_list(p_value -> 'delay_causes', 40, 60)
    and public.valid_text_list(p_value -> 'change_types', 40, 60)
    and public.valid_text_list(p_value -> 'change_reasons', 40, 80)
    and public.valid_text_list(p_value -> 'lesson_apply', 40, 60)
    and public.valid_text_list(p_value -> 'departments', 20, 60)
    and public.pm_num_ok(p_value, 'spi_ahead', 0.5, 3) and public.pm_num_ok(p_value, 'spi_ok', 0.3, 2)
    and public.pm_num_ok(p_value, 'spi_warn', 0.1, 2) and public.pm_num_ok(p_value, 'spi_zero', 0, 0.99)
    and public.pm_num_ok(p_value, 'change_limit', 0, 1) and public.pm_num_ok(p_value, 'delay_zero', 0.01, 1)
    and public.pm_num_ok(p_value, 'change_decide_days', 1, 365) and public.pm_num_ok(p_value, 'issue_days', 1, 365)
    and public.pm_num_ok(p_value, 'stale_days', 1, 120) and public.pm_num_ok(p_value, 'forecast_delay_alert', 0, 3650)
    and public.pm_num_ok(p_value, 'alert_days', 0, 90)
    and public.pm_num_ok(p_value, 'kpi_min_components', 1, 4)
    and (p_value -> 'kpi_min_components' is null or jsonb_typeof(p_value -> 'kpi_min_components') = 'null'
         or (p_value ->> 'kpi_min_components')::numeric = trunc((p_value ->> 'kpi_min_components')::numeric))
    and (nullif(p_value ->> 'ref_date', '') is null or (p_value ->> 'ref_date') ~ '^\d{4}-\d{2}-\d{2}$')
    and coalesce((p_value ->> 'spi_warn')::numeric, 0.85) <= coalesce((p_value ->> 'spi_ok')::numeric, 0.95)
    and coalesce((p_value ->> 'spi_ok')::numeric, 0.95) <= coalesce((p_value ->> 'spi_ahead')::numeric, 1.05)
    and (p_value -> 'weights' is null or (
          jsonb_typeof(p_value -> 'weights') = 'object'
          and (select bool_and(k in ('schedule', 'delay', 'field', 'response') and jsonb_typeof(v) = 'number'
                               and (v #>> '{}')::numeric between 0 and 1)
                 from jsonb_each(p_value -> 'weights') e(k, v))
          and abs((select sum((v #>> '{}')::numeric) from jsonb_each(p_value -> 'weights') e(k, v)) - 1) < 0.001))
    and (p_value -> 'grades' is null or (
          jsonb_typeof(p_value -> 'grades') = 'array' and jsonb_array_length(p_value -> 'grades') between 2 and 8
          and coalesce((select bool_and(jsonb_typeof(x -> 'min') = 'number' and (x ->> 'min')::numeric between 0 and 100
                                        and jsonb_typeof(x -> 'name') = 'string' and length(btrim(x ->> 'name')) between 2 and 30
                                        and length(coalesce(x ->> 'rec', '')) <= 120)
                          from jsonb_array_elements(p_value -> 'grades') x), false)
          and (p_value -> 'grades' -> 0 ->> 'min')::numeric = 0
          and coalesce((select bool_and(a < b) from (
                 select (x ->> 'min')::numeric a, lead((x ->> 'min')::numeric) over (order by i) b
                   from jsonb_array_elements(p_value -> 'grades') with ordinality e(x, i)) s where b is not null), true)));
  if not coalesce(ok, false) then
    raise exception 'قيمة غير صالحة للإعداد %', p_key using errcode = '22023';
  end if;
  select value into v_old from public.app_settings where key = p_key;
  if v_old is not distinct from p_value then
    return;
  end if;
  insert into public.app_settings (key, value, updated_at, updated_by)
  values (p_key, p_value, now(), auth.uid())
  on conflict (key) do update set value = excluded.value, updated_at = excluded.updated_at, updated_by = excluded.updated_by;
  perform public.write_audit('setting.update', null, null, jsonb_build_object('key', p_key, 'from', v_old, 'to', p_value), p_key);
end;
$$;

-- ترقية pm.config دون المساس بما خصّصه المدير
do $$
declare
  cfg   jsonb := (select value from public.app_settings where key = 'pm.config');
  types jsonb;
  t     text;
begin
  if cfg is null or jsonb_typeof(cfg) <> 'object' then
    return;
  end if;
  types := case when jsonb_typeof(cfg -> 'project_types') = 'array' then cfg -> 'project_types' else '[]'::jsonb end;
  foreach t in array array['إزالة الركام والمخلفات والهدم', 'توريد وتركيب'] loop
    if not types ? t and jsonb_array_length(types) < 40 then
      types := types || to_jsonb(t);
    end if;
  end loop;
  cfg := jsonb_set(cfg, '{project_types}', types);
  if not cfg ? 'kpi_min_components' then
    cfg := cfg || '{"kpi_min_components": 2}'::jsonb;
  end if;
  if coalesce(cfg #>> '{framework,version}', '2.0') = '2.0' then
    cfg := jsonb_set(cfg, '{framework}',
                     coalesce(case when jsonb_typeof(cfg -> 'framework') = 'object' then cfg -> 'framework' end, '{}'::jsonb)
                     || '{"version": "2.3", "issued": "2026-11", "status": "مسودة للاعتماد"}'::jsonb);
  end if;
  update public.app_settings set value = cfg, updated_at = now()
   where key = 'pm.config' and value is distinct from cfg;
end $$;

-- ---------------------------------------------------------------------
-- 3. العقود الفعلية التسعة: البرنامج الزمني والاسم المختصر وقيمة العقد
--    المطابقة برقم العقد (RBCS-06 = RBCS-006)، وتُتجاوز أي مطابقة غير وحيدة.
-- ---------------------------------------------------------------------
create temp table if not exists pm_v23_contracts (
  n integer, project_type text, location text, op_status text, start_date date, end_date date, display_name text, contract_value numeric
);
truncate pm_v23_contracts;
insert into pm_v23_contracts values
  (6,  'طرق', 'الصابري ووسط البلاد', 'completed', '2026-06-13', '2026-08-12',
       'إعادة تأهيل طريق وفتح مسارات – الصابري ووسط البلاد', 4823885.75),
  (7,  'توريد وتركيب', 'وسط البلاد', 'completed', '2026-06-15', '2026-07-14',
       'توريد وتركيب حواجز نيوجيرسي ولافتات', 1210020),
  (8,  'مرافق وشبكات', 'الصابري ووسط البلاد', 'completed', '2026-06-20', '2026-10-19',
       'نقل مخلفات وإنارة ومعالجة مختنقات الصرف – وسط البلاد وأخريبيش والصابري', 10526856.6),
  (9,  'إزالة الركام والمخلفات والهدم', 'الصابري ووسط البلاد', 'completed', '2026-06-20', '2026-08-19',
       'إزالة ونقل مخلفات الهدم – القطاعات A – E', 7728628),
  (10, 'ترميم مبانٍ تراثية', 'وسط البلاد', 'completed', '2026-06-20', '2026-09-19',
       'هدم جزئي متحكم به وتنظيف محافظ – مقر القنصلية الإيطالية', 5738163),
  (11, 'إزالة الركام والمخلفات والهدم', 'الصابري ووسط البلاد', 'completed', '2026-06-20', '2026-08-19',
       'نقل الركام وأعمال غرف التفتيش والصرف – القطاعات A-C-E-F', 7846926),
  (12, 'إزالة الركام والمخلفات والهدم', 'الصابري ووسط البلاد', 'completed', '2026-06-20', '2026-07-19',
       'نقل وإزالة المخلفات والهدم – القطاعات A3 – A5', 943345),
  (13, 'مرافق وشبكات', 'الصابري ووسط البلاد', 'completed', '2026-06-23', '2026-09-22',
       'صيانة ورصف الطرق وتسليك خطوط المياه والصرف', 3149220),
  (16, 'إزالة الركام والمخلفات والهدم', 'الصابري ووسط البلاد', 'completed', '2026-07-28', '2026-10-27',
       'إزالة المخلفات ومعالجة طفح الصرف الصحي – المنطقة D', 6455628);

create temp table if not exists pm_v23_match (n integer, project_id uuid);
truncate pm_v23_match;
insert into pm_v23_match
select c.n, min(p.id::text)::uuid
  from pm_v23_contracts c
  join public.projects p
    on p.merged_into is null
   and p.contract_no ~* '^\s*RBCS'
   and nullif(regexp_replace(p.contract_no, '\D', '', 'g'), '')::integer = c.n
 group by c.n
having count(*) = 1;

insert into public.pm_projects (project_id, project_type, location, op_status, start_date, end_date, display_name)
select m.project_id, c.project_type, c.location, c.op_status, c.start_date, c.end_date, c.display_name
  from pm_v23_match m join pm_v23_contracts c using (n)
on conflict (project_id) do update set
  project_type = case when public.pm_projects.project_type = '' then excluded.project_type else public.pm_projects.project_type end,
  location     = case when public.pm_projects.location = '' then excluded.location else public.pm_projects.location end,
  start_date   = coalesce(public.pm_projects.start_date, excluded.start_date),
  end_date     = case when public.pm_projects.end_date is null
                       and (public.pm_projects.start_date is null or excluded.end_date >= public.pm_projects.start_date)
                      then excluded.end_date else public.pm_projects.end_date end,
  display_name = case when public.pm_projects.display_name = '' then excluded.display_name else public.pm_projects.display_name end;

do $$
declare
  r record;
begin
  for r in
    select m.project_id, c.contract_value
      from pm_v23_match m join pm_v23_contracts c using (n)
      join public.projects p on p.id = m.project_id
     where p.contract_value is null and p.value_source = 'manual'
  loop
    update public.projects set contract_value = r.contract_value where id = r.project_id;
    perform public.recalc_contract_finance(r.project_id);
  end loop;
end $$;

drop table if exists pm_v23_match;
drop table if exists pm_v23_contracts;

-- ---------------------------------------------------------------------
-- 4. تحليل SWOT – الإصدار 2.1: عناصر الأمن والسلامة في مواقع العمل
-- ---------------------------------------------------------------------
insert into public.swot_factors (code, kind, factor, impact, department, importance, urgency, evidence, source, rating, sort)
select v.code, 'S', v.factor, v.impact, 'قسم الإشراف والتنسيق', v.imp, v.urg, v.evidence, 'إفادة إدارة المكتب', v.rating,
       coalesce((select max(sort) from public.swot_factors), 0) + v.o
  from (values
    ('S11', 'تواجد عناصر أمن في مواقع العمل لتأمين المواقع وضبط الدخول والخروج وحماية المعدات والمواد',
     'تأمين المواقع والمعدات والمواد، وحماية المباني والعناصر التراثية من العبث والسرقة', 4::smallint, 3::smallint,
     'كشوف تكليف وتواجد عناصر الأمن بالمواقع وسجلات الدخول والخروج', 3::smallint, 1),
    ('S12', 'تواجد عناصر السلامة والأمن الصناعي في مواقع العمل لمتابعة تطبيق اشتراطات السلامة المهنية (معدات الوقاية، تأمين الحفريات والسقالات، اللافتات التحذيرية، تصاريح العمل)',
     'خفض الحوادث وإصابات العمل وتوقفات الأعمال، ودعم التعامل مع مخاطر المواقع المتضررة (يقابل التهديد T07)', 5::smallint, 4::smallint,
     'كشوف عناصر السلامة والأمن الصناعي، وتقارير التفتيش الدوري، وسجل الحوادث وتصاريح العمل', 4::smallint, 2)
  ) v(code, factor, impact, imp, urg, evidence, rating, o)
 where not exists (select 1 from public.swot_factors f where f.code = v.code)
   and not exists (select 1 from public.swot_factors f where f.kind = 'S' and f.factor = v.factor);

-- الاستراتيجية والإجراء يُضافان فقط إن أُضيف العاملان (أو كانا موجودين بالنص نفسه)
insert into public.swot_strategies (code, kind, strategy, internal_factors, external_factors, priority, lead_department, source, sort)
select 'ST6', 'ST',
       'توظيف عناصر الأمن والسلامة والأمن الصناعي المتواجدة في مواقع العمل لتطبيق خطة سلامة وتأمين موحدة لكل موقع، تحمي العاملين والمباني المتضررة والتراثية وتمنع تراجع السلامة تحت الضغط الزمني',
       array(select x from unnest(array['S11', 'S12', 'S02']) with ordinality u(x, i) where exists (select 1 from public.swot_factors f where f.code = x) order by i),
       array(select x from unnest(array['T07', 'T04']) with ordinality u(x, i) where exists (select 1 from public.swot_factors f where f.code = x) order by i),
       'high', 'قسم الإشراف والتنسيق', 'مقترح – للتحقق في ورشة العمل',
       coalesce((select max(sort) from public.swot_strategies), 0) + 1
 where not exists (select 1 from public.swot_strategies where code = 'ST6')
   and exists (select 1 from public.swot_factors where code = 'S11'
                 and factor = 'تواجد عناصر أمن في مواقع العمل لتأمين المواقع وضبط الدخول والخروج وحماية المعدات والمواد')
   and not exists (select 1 from public.swot_strategies where strategy like 'توظيف عناصر الأمن والسلامة والأمن الصناعي%');

insert into public.swot_actions (code, strategy_code, factors, action, output, department, owner, kpi, priority, start_date,
                                 duration_months, verification, review_cycle, status, progress, notes, source, sort)
select 'A22', 'ST6',
       array(select x from unnest(array['S11', 'S12', 'T07', 'T04']) with ordinality u(x, i) where exists (select 1 from public.swot_factors f where f.code = x) order by i),
       'إعداد واعتماد خطة السلامة والأمن الموحدة لمواقع العمل وتفعيل دور عناصر الأمن والسلامة والأمن الصناعي فيها (تقييم المخاطر قبل البدء، تصاريح العمل للأعمال الخطرة، جولات تفتيش أسبوعية، سجل الحوادث والحوادث الوشيكة، التوعية اليومية)',
       'خطة سلامة وأمن معتمدة، وسجل تفتيش وحوادث مفعّل لكل موقع',
       'قسم الإشراف والتنسيق',
       'رئيس قسم الإشراف والتنسيق بالتنسيق مع مسؤولي الأمن والسلامة بالمواقع',
       'تفتيش أسبوعي موثق لـ 100% من المواقع النشطة، وتسجيل 100% من الحوادث والحوادث الوشيكة خلال 24 ساعة',
       'high', '2026-12-01', 2, 'تقارير التفتيش الأسبوعية وسجل الحوادث وتصاريح العمل', 'شهريًا', 'not_started', 0, '',
       'مقترح – للتحقق في ورشة العمل',
       coalesce((select max(sort) from public.swot_actions), 0) + 1
 where not exists (select 1 from public.swot_actions where code = 'A22')
   and exists (select 1 from public.swot_strategies where code = 'ST6' and kind = 'ST'
                 and strategy like 'توظيف عناصر الأمن والسلامة والأمن الصناعي%');

-- رقم الإصدار في بيانات الوثيقة (إن كان ما يزال 2.0)
update public.app_settings
   set value = value || '{"version": "2.1", "issue_date": "2026-11-12"}'::jsonb, updated_at = now()
 where key = 'swot.meta' and jsonb_typeof(value) = 'object' and coalesce(value ->> 'version', '') = '2.0';
