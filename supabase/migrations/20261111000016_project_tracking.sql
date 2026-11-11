-- =====================================================================
--  الإصدار السابع: «سجل المخاطر ومتابعة المشاريع – الإصدار 2.0»
--  يوسّع القسم الثاني ليصبح «المخاطر ومتابعة المشاريع» كما في الملف المعتمد:
--    1. البرنامج الزمني للعقد (النوع، الموقع، الاستشاري، الوضع التشغيلي، البداية والنهاية التعاقدية).
--    2. سجل التقدم الدوري (المخطط مقابل الفعلي) لحساب SPI والسرعة والتوقع.
--    3. سجل المخاطر الموسّع: القسم المختص، والأثر الزمني والمالي، والإجراء الاحتياطي، ومنفذ الإجراء،
--       ومراجعات المخاطر الدورية (التقييم الحالي ونسبة التنفيذ) ودورية المراجعة حسب المستوى.
--    4. سجلات المشاكل، والتأخيرات، والتغييرات، والدروس المستفادة، والتقييم الدوري للشركات.
--    5. التغيير المعتمد ذو الأثر المالي يُنشئ أمر تغيير في مالية العقد تلقائياً (لا يُحتسب مرتين).
--    6. القوائم والإعدادات (حدود SPI، أيام التنبيه، أوزان مؤشر أداء الشركات وجدول التقدير).
--  السجلات الجديدة تبدأ فارغة ومربوطة بالعقود الفعلية؛ ويُحدَّث الاثنا عشر خطراً الأولى بصيغة الإصدار 2.0
--  (ما لم يعدّلها أحد) ويُضاف خطران جديدان مع مراجعاتها.
--  القراءة لكل الأعضاء، والكتابة عبر دوال تتحقق من الصلاحية وتسجّل في سجل التدقيق.
--  يُشغَّل بعد 20261109000015_risks_swot.sql. إعادة تشغيله آمنة.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 0. أدوات عامة
-- ---------------------------------------------------------------------
-- عدد صحيح ضمن نطاق (أو فارغ)
create or replace function public.jint(p_data jsonb, p_key text, p_min integer, p_max integer, p_label text,
                                       p_required boolean default false)
returns integer
language plpgsql immutable set search_path = public
as $$
declare
  raw text := nullif(btrim(coalesce(p_data ->> p_key, '')), '');
  v   numeric;
begin
  if raw is null then
    if p_required then
      raise exception 'أدخل «%»', p_label using errcode = '22023';
    end if;
    return null;
  end if;
  begin
    v := raw::numeric;
  exception when others then
    raise exception '«%» يجب أن يكون رقماً', p_label using errcode = '22023';
  end;
  if v <> trunc(v) then
    raise exception '«%» يجب أن يكون رقماً صحيحاً', p_label using errcode = '22023';
  end if;
  if v < p_min or v > p_max then
    raise exception '«%» يجب أن يكون من % إلى %', p_label, p_min, p_max using errcode = '22023';
  end if;
  return v::integer;
end;
$$;

-- رقم عشري ضمن نطاق (أو فارغ)
create or replace function public.jnum(p_data jsonb, p_key text, p_min numeric, p_max numeric, p_label text,
                                       p_required boolean default false)
returns numeric
language plpgsql immutable set search_path = public
as $$
declare
  raw text := nullif(btrim(coalesce(p_data ->> p_key, '')), '');
  v   numeric;
begin
  if raw is null then
    if p_required then
      raise exception 'أدخل «%»', p_label using errcode = '22023';
    end if;
    return null;
  end if;
  begin
    v := raw::numeric;
  exception when others then
    raise exception '«%» يجب أن يكون رقماً', p_label using errcode = '22023';
  end;
  if v < p_min or v > p_max then
    raise exception '«%» خارج النطاق المسموح', p_label using errcode = '22023';
  end if;
  return v;
end;
$$;

-- قيمة من قائمة ثابتة
create or replace function public.jpick(p_data jsonb, p_key text, p_allowed text[], p_default text, p_label text)
returns text
language plpgsql immutable set search_path = public
as $$
declare
  v text := coalesce(nullif(btrim(coalesce(p_data ->> p_key, '')), ''), p_default);
begin
  if not (v = any (p_allowed)) then
    raise exception 'قيمة غير معروفة في «%»', p_label using errcode = '22023';
  end if;
  return v;
end;
$$;

create or replace function public.jbool(p_data jsonb, p_key text)
returns boolean
language sql immutable set search_path = public
as $$
  select coalesce(case when jsonb_typeof(p_data -> p_key) = 'boolean' then (p_data ->> p_key)::boolean
                       else lower(coalesce(p_data ->> p_key, '')) in ('true', '1', 'yes', 'نعم') end, false)
$$;

-- عقد قائم (غير مدموج) من حقل jsonb
create or replace function public.jproject(p_data jsonb, p_key text, p_required boolean)
returns uuid
language plpgsql stable security definer set search_path = public
as $$
declare
  raw text := nullif(btrim(coalesce(p_data ->> p_key, '')), '');
  v   uuid;
begin
  if raw is null then
    if p_required then
      raise exception 'اختر العقد' using errcode = '22023';
    end if;
    return null;
  end if;
  begin
    v := raw::uuid;
  exception when others then
    raise exception 'عقد غير صالح' using errcode = '22023';
  end;
  if not exists (select 1 from public.projects where id = v and merged_into is null) then
    raise exception 'العقد غير موجود أو مدموج في عقد آخر' using errcode = '22023';
  end if;
  return v;
end;
$$;

-- الرمز التالي في سجل (I01، D01، C01، L01...)
create or replace function public.pm_next_code(p_table text, p_prefix text)
returns text
language plpgsql security definer set search_path = public
as $$
declare
  n integer;
begin
  execute format('select coalesce(max(substring(code from 2)::integer), 0) from public.%I where code ~ %L',
                 p_table, '^' || p_prefix || '[0-9]+$') into n;
  return p_prefix || lpad((n + 1)::text, 2, '0');
end;
$$;

-- ---------------------------------------------------------------------
-- 1. الصلاحيات
-- ---------------------------------------------------------------------
-- سجلات المتابعة (التقدم، المشاكل، التأخيرات، التغييرات، الدروس، التقييمات): كل عضو عدا CISO
create or replace function public.can_edit_pm()
returns boolean
language sql stable security definer set search_path = public
as $$
  select public.can_edit_risks()
$$;

-- البرنامج الزمني للعقد: المدير وموظفو مكتبه ومكتب العقود ورئيس القسم المشرف على العقد
create or replace function public.can_edit_schedule(p_project uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
  select public.writes_allowed() and (
    coalesce(public.my_role()::text, '') in ('director', 'office_staff', 'contracts')
    or (coalesce(public.my_role()::text, '') = 'dept_head'
        and exists (select 1 from public.profiles me join public.projects p on p.id = p_project
                     where me.id = auth.uid() and me.department is not null and me.department = p.department)))
$$;

-- البت في طلب التغيير (اعتماد أو رفض): من يختص بمالية العقد، والمدير دائماً
create or replace function public.can_decide_change(p_project uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
  select public.is_director() or public.can_edit_finance(p_project)
$$;

-- اعتماد الدرس المستفاد وتطبيقه: المدير وموظفو مكتبه
create or replace function public.can_approve_lessons()
returns boolean
language sql stable security definer set search_path = public
as $$
  select public.writes_allowed() and coalesce(public.my_role()::text, '') in ('director', 'office_staff')
$$;

-- ---------------------------------------------------------------------
-- 2. البرنامج الزمني للعقد
-- ---------------------------------------------------------------------
create table if not exists public.pm_projects (
  project_id   uuid primary key references public.projects (id) on delete cascade,
  project_type text not null default '' check (length(project_type) <= 60),
  location     text not null default '' check (length(location) <= 120),
  consultant   text not null default '' check (length(consultant) <= 120),
  op_status    text not null default 'running'
               check (op_status in ('not_started', 'running', 'suspended', 'completed', 'prov_accepted', 'final_accepted')),
  start_date   date,
  end_date     date,
  notes        text not null default '' check (length(notes) <= 1000),
  updated_at   timestamptz not null default now(),
  updated_by   uuid references public.profiles (id) on delete set null,
  check (end_date is null or start_date is null or end_date >= start_date)
);
create index if not exists pm_projects_updated_by_idx on public.pm_projects (updated_by);

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
                                  updated_at, updated_by)
  values (p_project, public.jtext(p_data, 'project_type', 60, 'نوع المشروع'), public.jtext(p_data, 'location', 120, 'الموقع / القطاع'),
          public.jtext(p_data, 'consultant', 120, 'الاستشاري / جهة الإشراف'),
          public.jpick(p_data, 'op_status', array['not_started', 'running', 'suspended', 'completed', 'prov_accepted', 'final_accepted'],
                       'running', 'الوضع التشغيلي'),
          v_start, v_end, public.jtext(p_data, 'notes', 1000, 'ملاحظات'), now(), auth.uid())
  on conflict (project_id) do update set
    project_type = excluded.project_type, location = excluded.location, consultant = excluded.consultant,
    op_status = excluded.op_status, start_date = excluded.start_date, end_date = excluded.end_date, notes = excluded.notes,
    updated_at = excluded.updated_at, updated_by = excluded.updated_by
  returning * into new_row;
  v_ch := public.jsonb_changes(to_jsonb(old_row), to_jsonb(new_row), array['updated_at', 'updated_by', 'project_id']);
  if old_row.project_id is null or v_ch <> '{}'::jsonb then
    perform public.write_audit('pm.schedule', p_project, null, jsonb_build_object('changes', v_ch));
  end if;
end;
$$;

-- ---------------------------------------------------------------------
-- 3. سجل التقدم الدوري (المخطط مقابل الفعلي، تراكمي من بداية المشروع)
-- ---------------------------------------------------------------------
create table if not exists public.pm_progress (
  id             uuid primary key default gen_random_uuid(),
  project_id     uuid not null references public.projects (id) on delete cascade,
  origin_project uuid references public.projects (id) on delete set null,
  measured_on    date not null,
  planned        numeric(6, 4) not null check (planned between 0 and 1),
  actual         numeric(6, 4) not null check (actual between 0 and 1),
  works          text not null default '' check (length(works) <= 1000),
  obstacles      text not null default '' check (length(obstacles) <= 1000),
  prepared_by    text not null default '' check (length(prepared_by) <= 60),
  created_at     timestamptz not null default now(),
  created_by     uuid references public.profiles (id) on delete set null,
  updated_at     timestamptz not null default now(),
  updated_by     uuid references public.profiles (id) on delete set null,
  unique (project_id, measured_on)
);
create index if not exists pm_progress_origin_idx     on public.pm_progress (origin_project);
create index if not exists pm_progress_created_by_idx on public.pm_progress (created_by);
create index if not exists pm_progress_updated_by_idx on public.pm_progress (updated_by);

create or replace function public.save_pm_progress(p_id uuid, p_data jsonb)
returns uuid
language plpgsql security definer set search_path = public
as $$
declare
  old_row public.pm_progress;
  new_row public.pm_progress;
  v_proj  uuid;
  v_on    date := public.jdate(p_data, 'measured_on', 'تاريخ القياس');
  v_pl    numeric := public.jnum(p_data, 'planned', 0, 1, 'نسبة الإنجاز المخططة', true);
  v_ac    numeric := public.jnum(p_data, 'actual', 0, 1, 'نسبة الإنجاز الفعلية', true);
begin
  if not public.can_edit_pm() then
    raise exception 'لا تملك صلاحية تحديث سجل التقدم' using errcode = '42501';
  end if;
  if v_on is null then
    raise exception 'حدّد تاريخ القياس' using errcode = '22023';
  end if;
  if v_on > current_date + 1 then
    raise exception 'تاريخ القياس في المستقبل' using errcode = '22023';
  end if;
  if p_id is not null then
    select * into old_row from public.pm_progress where id = p_id for update;
    if not found then
      raise exception 'القياس غير موجود' using errcode = 'P0002';
    end if;
    v_proj := coalesce(public.jproject(p_data, 'project_id', false), old_row.project_id);
  else
    v_proj := public.jproject(p_data, 'project_id', true);
  end if;
  if exists (select 1 from public.pm_progress where project_id = v_proj and measured_on = v_on and id is distinct from p_id) then
    raise exception 'يوجد قياس لهذا العقد بالتاريخ نفسه؛ عدّله بدل إضافة قياس جديد' using errcode = '23505';
  end if;
  if p_id is null then
    insert into public.pm_progress (project_id, measured_on, planned, actual, works, obstacles, prepared_by, created_by, updated_by)
    values (v_proj, v_on, round(v_pl, 4), round(v_ac, 4), public.jtext(p_data, 'works', 1000, 'أهم الأعمال المنفذة'),
            public.jtext(p_data, 'obstacles', 1000, 'المعوقات'), public.jtext(p_data, 'prepared_by', 60, 'أعدّه'),
            auth.uid(), auth.uid())
    returning * into new_row;
    perform public.write_audit('pm.progress_add', v_proj, null,
      jsonb_build_object('measured_on', v_on, 'planned', new_row.planned, 'actual', new_row.actual));
  else
    update public.pm_progress set
      project_id = v_proj, measured_on = v_on, planned = round(v_pl, 4), actual = round(v_ac, 4),
      works = public.jtext(p_data, 'works', 1000, 'أهم الأعمال المنفذة'),
      obstacles = public.jtext(p_data, 'obstacles', 1000, 'المعوقات'),
      prepared_by = public.jtext(p_data, 'prepared_by', 60, 'أعدّه'),
      updated_at = now(), updated_by = auth.uid()
    where id = p_id
    returning * into new_row;
    perform public.write_audit('pm.progress_update', v_proj, null,
      jsonb_build_object('measured_on', v_on,
                         'changes', public.jsonb_changes(to_jsonb(old_row), to_jsonb(new_row), array['updated_at', 'updated_by'])));
  end if;
  return new_row.id;
end;
$$;

create or replace function public.delete_pm_progress(p_id uuid)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  r public.pm_progress;
begin
  if not public.is_director() then
    raise exception 'حذف القياسات من صلاحية مدير المكتب وحده' using errcode = '42501';
  end if;
  delete from public.pm_progress where id = p_id returning * into r;
  if not found then
    raise exception 'القياس غير موجود' using errcode = 'P0002';
  end if;
  perform public.write_audit('pm.progress_delete', r.project_id, null,
    jsonb_build_object('measured_on', r.measured_on, 'planned', r.planned, 'actual', r.actual));
end;
$$;

-- ---------------------------------------------------------------------
-- 4. سجل المخاطر الموسّع ومراجعاته الدورية
-- ---------------------------------------------------------------------
alter table public.risks
  add column if not exists department       text not null default '' check (length(department) <= 60),
  add column if not exists time_impact_days integer check (time_impact_days between 0 and 3650),
  add column if not exists cost_impact      numeric(16, 3) check (cost_impact >= 0),
  add column if not exists contingency      text not null default '' check (length(contingency) <= 600),
  add column if not exists executor         text not null default '' check (length(executor) <= 60),
  add column if not exists origin_project   uuid references public.projects (id) on delete set null;
create index if not exists risks_origin_idx on public.risks (origin_project);

-- حفظ خطر (جديد أو تعديل). الاحتمالية والتأثير «بعد المعالجة» هما المستهدفان في الإصدار 2.0.
create or replace function public.save_risk(p_id uuid, p_data jsonb)
returns uuid
language plpgsql security definer set search_path = public
as $$
declare
  old_row public.risks;
  new_row public.risks;
  v_code  text := upper(nullif(btrim(coalesce(p_data ->> 'code', '')), ''));
  v_proj  uuid;
  v_stat  text := coalesce(nullif(p_data ->> 'status', ''), 'open');
  v_resp  text := coalesce(p_data ->> 'response', '');
  v_rp    smallint := public.jscore(p_data, 'residual_probability', 5, 'الاحتمالية المستهدفة');
  v_ri    smallint := public.jscore(p_data, 'residual_impact', 5, 'التأثير المستهدف');
  v_closed date := public.jdate(p_data, 'closed_on', 'تاريخ الإغلاق');
  v_desc  text := public.jtext(p_data, 'description', 300, 'وصف الخطر');
  v_days  integer := public.jint(p_data, 'time_impact_days', 0, 3650, 'الأثر الزمني المقدر');
  v_cost  numeric := public.jnum(p_data, 'cost_impact', 0, 1e12, 'الأثر المالي المقدر');
  v_skip  text[] := array['updated_at', 'updated_by', 'score', 'residual_score'];
begin
  if not public.can_edit_risks() then
    raise exception 'لا تملك صلاحية تعديل سجل المخاطر' using errcode = '42501';
  end if;
  if jsonb_typeof(coalesce(p_data, 'null'::jsonb)) <> 'object' then
    raise exception 'بيانات الخطر غير صالحة' using errcode = '22023';
  end if;
  if length(v_desc) < 3 then
    raise exception 'اكتب وصف الخطر' using errcode = '22023';
  end if;
  if v_stat not in ('open', 'in_progress', 'on_hold', 'closed') then
    raise exception 'حالة خطر غير معروفة' using errcode = '22023';
  end if;
  if v_resp not in ('', 'avoid', 'mitigate', 'transfer', 'accept') then
    raise exception 'نوع استجابة غير معروف' using errcode = '22023';
  end if;
  if (v_rp is null) <> (v_ri is null) then
    raise exception 'حدّد الاحتمالية والتأثير المستهدفين معاً، أو اتركهما فارغين' using errcode = '22023';
  end if;
  if nullif(p_data ->> 'project_id', '') is not null then
    begin
      v_proj := (p_data ->> 'project_id')::uuid;
    exception when others then
      raise exception 'عقد غير صالح' using errcode = '22023';
    end;
    if not exists (select 1 from public.projects where id = v_proj) then
      raise exception 'العقد المرتبط غير موجود' using errcode = '22023';
    end if;
  end if;
  if v_code is not null and v_code !~ '^R[0-9]{2,4}$' then
    raise exception 'رمز الخطر بالصيغة R01' using errcode = '22023';
  end if;
  v_closed := case when v_stat = 'closed' then coalesce(v_closed, current_date) end;

  if p_id is not null then
    select * into old_row from public.risks where id = p_id for update;
    if not found then
      raise exception 'الخطر غير موجود' using errcode = 'P0002';
    end if;
    v_code := coalesce(v_code, old_row.code);
  elsif v_code is null then
    select 'R' || lpad((coalesce(max(substring(code from 2)::integer), 0) + 1)::text, 2, '0') into v_code
      from public.risks where code ~ '^R[0-9]+$';
  end if;
  if exists (select 1 from public.risks where code = v_code and id is distinct from p_id) then
    raise exception 'الرمز % مستخدم لخطر آخر', v_code using errcode = '23505';
  end if;

  if p_id is null then
    insert into public.risks (code, project_group, project_id, phase, category, description, cause, effect, probability, impact,
                              mitigation, response, owner, status, residual_probability, residual_impact, next_review,
                              registered_on, target_date, closed_on, early_warning, notes, department, time_impact_days,
                              cost_impact, contingency, executor, created_by, updated_by)
    values (v_code, public.jtext(p_data, 'project_group', 60, 'المشروع'), v_proj,
            public.jtext(p_data, 'phase', 40, 'المرحلة'), public.jtext(p_data, 'category', 40, 'التصنيف'), v_desc,
            public.jtext(p_data, 'cause', 500, 'السبب'), public.jtext(p_data, 'effect', 500, 'الأثر'),
            public.jscore(p_data, 'probability', 5, 'الاحتمالية', true), public.jscore(p_data, 'impact', 5, 'التأثير', true),
            public.jtext(p_data, 'mitigation', 600, 'الإجراء الوقائي'), v_resp, public.jtext(p_data, 'owner', 60, 'مالك الخطر'),
            v_stat, v_rp, v_ri, public.jdate(p_data, 'next_review', 'موعد المراجعة القادمة'),
            coalesce(public.jdate(p_data, 'registered_on', 'تاريخ التسجيل'), current_date),
            public.jdate(p_data, 'target_date', 'الموعد المستهدف'), v_closed,
            public.jtext(p_data, 'early_warning', 300, 'مؤشر الإنذار المبكر'), public.jtext(p_data, 'notes', 1000, 'الملاحظات'),
            public.jtext(p_data, 'department', 60, 'القسم المختص'), v_days, v_cost,
            public.jtext(p_data, 'contingency', 600, 'الإجراء الاحتياطي'), public.jtext(p_data, 'executor', 60, 'منفذ الإجراء'),
            auth.uid(), auth.uid())
    returning * into new_row;
    perform public.write_audit('risk.create', v_proj, null,
      jsonb_build_object('code', new_row.code, 'description', new_row.description, 'score', new_row.score), new_row.code);
  else
    update public.risks set
      code = v_code,
      project_group = public.jtext(p_data, 'project_group', 60, 'المشروع'),
      project_id = v_proj,
      phase = public.jtext(p_data, 'phase', 40, 'المرحلة'),
      category = public.jtext(p_data, 'category', 40, 'التصنيف'),
      description = v_desc,
      cause = public.jtext(p_data, 'cause', 500, 'السبب'),
      effect = public.jtext(p_data, 'effect', 500, 'الأثر'),
      probability = public.jscore(p_data, 'probability', 5, 'الاحتمالية', true),
      impact = public.jscore(p_data, 'impact', 5, 'التأثير', true),
      mitigation = public.jtext(p_data, 'mitigation', 600, 'الإجراء الوقائي'),
      response = v_resp,
      owner = public.jtext(p_data, 'owner', 60, 'مالك الخطر'),
      status = v_stat,
      residual_probability = v_rp,
      residual_impact = v_ri,
      next_review = public.jdate(p_data, 'next_review', 'موعد المراجعة القادمة'),
      registered_on = coalesce(public.jdate(p_data, 'registered_on', 'تاريخ التسجيل'), old_row.registered_on),
      target_date = public.jdate(p_data, 'target_date', 'الموعد المستهدف'),
      closed_on = v_closed,
      early_warning = public.jtext(p_data, 'early_warning', 300, 'مؤشر الإنذار المبكر'),
      notes = public.jtext(p_data, 'notes', 1000, 'الملاحظات'),
      department = case when p_data ? 'department' then public.jtext(p_data, 'department', 60, 'القسم المختص') else old_row.department end,
      time_impact_days = case when p_data ? 'time_impact_days' then v_days else old_row.time_impact_days end,
      cost_impact = case when p_data ? 'cost_impact' then v_cost else old_row.cost_impact end,
      contingency = case when p_data ? 'contingency' then public.jtext(p_data, 'contingency', 600, 'الإجراء الاحتياطي')
                         else old_row.contingency end,
      executor = case when p_data ? 'executor' then public.jtext(p_data, 'executor', 60, 'منفذ الإجراء') else old_row.executor end,
      updated_at = now(),
      updated_by = auth.uid()
    where id = p_id
    returning * into new_row;
    if public.jsonb_changes(to_jsonb(old_row), to_jsonb(new_row), v_skip) <> '{}'::jsonb then
      perform public.write_audit('risk.update', coalesce(v_proj, old_row.project_id), null,
        jsonb_build_object('code', new_row.code, 'changes', public.jsonb_changes(to_jsonb(old_row), to_jsonb(new_row), v_skip)),
        new_row.code);
    end if;
  end if;
  return new_row.id;
end;
$$;

-- مراجعات المخاطر (السجل التاريخي): كل مراجعة صف جديد بالتقييم الحالي ونسبة تنفيذ الإجراء الوقائي
create table if not exists public.risk_reviews (
  id            uuid primary key default gen_random_uuid(),
  risk_id       uuid not null references public.risks (id) on delete cascade,
  reviewed_on   date not null,
  probability   smallint not null check (probability between 1 and 5),
  impact        smallint not null check (impact between 1 and 5),
  score         smallint generated always as (probability * impact) stored,
  actions_done  text not null default '' check (length(actions_done) <= 600),
  progress      numeric(5, 4) check (progress between 0 and 1),
  reviewer      text not null default '' check (length(reviewer) <= 60),
  notes         text not null default '' check (length(notes) <= 1000),
  created_at    timestamptz not null default now(),
  created_by    uuid references public.profiles (id) on delete set null,
  updated_at    timestamptz not null default now(),
  updated_by    uuid references public.profiles (id) on delete set null
);
create index if not exists risk_reviews_risk_idx       on public.risk_reviews (risk_id, reviewed_on);
create index if not exists risk_reviews_created_by_idx on public.risk_reviews (created_by);
create index if not exists risk_reviews_updated_by_idx on public.risk_reviews (updated_by);

create or replace function public.save_risk_review(p_id uuid, p_risk uuid, p_data jsonb)
returns uuid
language plpgsql security definer set search_path = public
as $$
declare
  rk      public.risks;
  old_row public.risk_reviews;
  new_row public.risk_reviews;
  v_on    date := public.jdate(p_data, 'reviewed_on', 'تاريخ المراجعة');
  v_p     smallint := public.jscore(p_data, 'probability', 5, 'الاحتمالية الحالية', true);
  v_i     smallint := public.jscore(p_data, 'impact', 5, 'التأثير الحالي', true);
  v_pct   numeric := public.jnum(p_data, 'progress', 0, 1, 'نسبة تنفيذ الإجراء الوقائي');
begin
  if not public.can_edit_risks() then
    raise exception 'لا تملك صلاحية تسجيل مراجعات المخاطر' using errcode = '42501';
  end if;
  if p_id is not null then
    select * into old_row from public.risk_reviews where id = p_id for update;
    if not found then
      raise exception 'المراجعة غير موجودة' using errcode = 'P0002';
    end if;
    p_risk := old_row.risk_id;
  end if;
  select * into rk from public.risks where id = p_risk;
  if not found then
    raise exception 'الخطر غير موجود' using errcode = 'P0002';
  end if;
  v_on := coalesce(v_on, current_date);
  if v_on > current_date + 1 then
    raise exception 'تاريخ المراجعة في المستقبل' using errcode = '22023';
  end if;
  if p_id is null then
    insert into public.risk_reviews (risk_id, reviewed_on, probability, impact, actions_done, progress, reviewer, notes,
                                     created_by, updated_by)
    values (p_risk, v_on, v_p, v_i, public.jtext(p_data, 'actions_done', 600, 'الإجراءات المنفذة'), round(v_pct, 4),
            public.jtext(p_data, 'reviewer', 60, 'المراجِع'), public.jtext(p_data, 'notes', 1000, 'ملاحظات / قرارات'),
            auth.uid(), auth.uid())
    returning * into new_row;
    perform public.write_audit('risk.review', rk.project_id, null,
      jsonb_build_object('code', rk.code, 'reviewed_on', v_on, 'score', new_row.score, 'progress', new_row.progress), rk.code);
  else
    update public.risk_reviews set
      reviewed_on = v_on, probability = v_p, impact = v_i,
      actions_done = public.jtext(p_data, 'actions_done', 600, 'الإجراءات المنفذة'), progress = round(v_pct, 4),
      reviewer = public.jtext(p_data, 'reviewer', 60, 'المراجِع'), notes = public.jtext(p_data, 'notes', 1000, 'ملاحظات / قرارات'),
      updated_at = now(), updated_by = auth.uid()
    where id = p_id
    returning * into new_row;
    perform public.write_audit('risk.review_update', rk.project_id, null,
      jsonb_build_object('code', rk.code, 'reviewed_on', v_on,
                         'changes', public.jsonb_changes(to_jsonb(old_row), to_jsonb(new_row), array['updated_at', 'updated_by', 'score'])),
      rk.code);
  end if;
  return new_row.id;
end;
$$;

create or replace function public.delete_risk_review(p_id uuid)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  r  public.risk_reviews;
  rk public.risks;
begin
  if not public.is_director() then
    raise exception 'حذف المراجعات من صلاحية مدير المكتب وحده' using errcode = '42501';
  end if;
  delete from public.risk_reviews where id = p_id returning * into r;
  if not found then
    raise exception 'المراجعة غير موجودة' using errcode = 'P0002';
  end if;
  select * into rk from public.risks where id = r.risk_id;
  perform public.write_audit('risk.review_delete', rk.project_id, null,
    jsonb_build_object('code', rk.code, 'reviewed_on', r.reviewed_on, 'score', r.score), rk.code);
end;
$$;

-- ---------------------------------------------------------------------
-- 5. سجل المشاكل (حدث وقع فعلاً ويحتاج حلاً)
-- ---------------------------------------------------------------------
create table if not exists public.pm_issues (
  id               uuid primary key default gen_random_uuid(),
  code             text not null unique check (code ~ '^I[0-9]{2,4}$'),
  project_id       uuid not null references public.projects (id) on delete cascade,
  origin_project   uuid references public.projects (id) on delete set null,
  detected_on      date not null default current_date,
  description      text not null check (length(btrim(description)) between 3 and 400),
  category         text not null default '' check (length(category) <= 40),
  risk_id          uuid references public.risks (id) on delete set null,
  priority         text not null default 'medium' check (priority in ('high', 'medium', 'low')),
  party            text not null default 'contractor'
                   check (party in ('contractor', 'owner', 'consultant', 'utilities', 'force_majeure', 'other')),
  department       text not null default '' check (length(department) <= 60),
  action           text not null default '' check (length(action) <= 600),
  time_impact_days integer check (time_impact_days between 0 and 3650),
  cost_impact      numeric(16, 3) check (cost_impact >= 0),
  target_date      date,
  status           text not null default 'open' check (status in ('open', 'in_progress', 'closed')),
  closed_on        date,
  notes            text not null default '' check (length(notes) <= 1000),
  created_at       timestamptz not null default now(),
  created_by       uuid references public.profiles (id) on delete set null,
  updated_at       timestamptz not null default now(),
  updated_by       uuid references public.profiles (id) on delete set null,
  check ((status = 'closed') = (closed_on is not null))
);
create index if not exists pm_issues_project_idx    on public.pm_issues (project_id);
create index if not exists pm_issues_origin_idx     on public.pm_issues (origin_project);
create index if not exists pm_issues_risk_idx       on public.pm_issues (risk_id);
create index if not exists pm_issues_created_by_idx on public.pm_issues (created_by);
create index if not exists pm_issues_updated_by_idx on public.pm_issues (updated_by);

-- ---------------------------------------------------------------------
-- 6. سجل أحداث التأخير
-- ---------------------------------------------------------------------
create table if not exists public.pm_delays (
  id             uuid primary key default gen_random_uuid(),
  code           text not null unique check (code ~ '^D[0-9]{2,4}$'),
  project_id     uuid not null references public.projects (id) on delete cascade,
  origin_project uuid references public.projects (id) on delete set null,
  description    text not null check (length(btrim(description)) between 3 and 400),
  cause          text not null default '' check (length(cause) <= 60),
  sub_cause      text not null default '' check (length(sub_cause) <= 300),
  party          text not null default 'contractor'
                 check (party in ('contractor', 'owner', 'consultant', 'utilities', 'force_majeure', 'other')),
  delay_class    text not null default '' check (delay_class in ('', 'excusable_comp', 'excusable', 'non_excusable', 'concurrent')),
  critical       boolean not null default false,
  start_date     date not null,
  end_date       date,
  eot_requested  integer check (eot_requested between 0 and 3650),
  eot_approved   integer check (eot_approved between 0 and 3650),
  refs           text not null default '' check (length(refs) <= 120),
  notes          text not null default '' check (length(notes) <= 1000),
  created_at     timestamptz not null default now(),
  created_by     uuid references public.profiles (id) on delete set null,
  updated_at     timestamptz not null default now(),
  updated_by     uuid references public.profiles (id) on delete set null,
  check (end_date is null or end_date >= start_date)
);
create index if not exists pm_delays_project_idx    on public.pm_delays (project_id);
create index if not exists pm_delays_origin_idx     on public.pm_delays (origin_project);
create index if not exists pm_delays_created_by_idx on public.pm_delays (created_by);
create index if not exists pm_delays_updated_by_idx on public.pm_delays (updated_by);

-- ---------------------------------------------------------------------
-- 7. سجل التغييرات (الطلب ودراسته والبت فيه). المعتمد ذو الأثر المالي = أمر تغيير في مالية العقد.
-- ---------------------------------------------------------------------
create table if not exists public.pm_changes (
  id             uuid primary key default gen_random_uuid(),
  code           text not null unique check (code ~ '^C[0-9]{2,4}$'),
  project_id     uuid not null references public.projects (id) on delete cascade,
  origin_project uuid references public.projects (id) on delete set null,
  submitted_on   date not null default current_date,
  description    text not null check (length(btrim(description)) between 3 and 280),
  change_type    text not null default '' check (length(change_type) <= 60),
  source         text not null default 'owner' check (source in ('owner', 'consultant', 'contractor', 'site', 'external')),
  reason         text not null default '' check (length(reason) <= 80),
  cost_estimate  numeric(16, 3),
  cost_approved  numeric(16, 3),
  time_requested integer check (time_requested between 0 and 3650),
  time_approved  integer check (time_approved between 0 and 3650),
  status         text not null default 'submitted' check (status in ('submitted', 'under_study', 'approved', 'rejected')),
  decided_on     date,
  approval_ref   text not null default '' check (length(approval_ref) <= 60),
  refs           text not null default '' check (length(refs) <= 120),
  notes          text not null default '' check (length(notes) <= 1000),
  variation_id   uuid references public.contract_variations (id) on delete set null,
  created_at     timestamptz not null default now(),
  created_by     uuid references public.profiles (id) on delete set null,
  updated_at     timestamptz not null default now(),
  updated_by     uuid references public.profiles (id) on delete set null,
  check ((status in ('approved', 'rejected')) = (decided_on is not null))
);
create index if not exists pm_changes_project_idx    on public.pm_changes (project_id);
create index if not exists pm_changes_origin_idx     on public.pm_changes (origin_project);
create unique index if not exists pm_changes_variation_uq on public.pm_changes (variation_id) where variation_id is not null;
create index if not exists pm_changes_variation_idx on public.pm_changes (variation_id);
create index if not exists pm_changes_created_by_idx on public.pm_changes (created_by);
create index if not exists pm_changes_updated_by_idx on public.pm_changes (updated_by);

-- مزامنة أمر التغيير في مالية العقد مع التغيير: يُنشأ عند الاعتماد بأثر مالي، ويُحدَّث بتعديله، ويُحذف بإلغائه
create or replace function public.pm_sync_change_variation(p_change uuid)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  c     public.pm_changes;
  v_id  uuid;
  v_amt numeric;
  v_ttl text;
begin
  select * into c from public.pm_changes where id = p_change;
  if not found then
    return;
  end if;
  v_amt := coalesce(c.cost_approved, 0);
  perform set_config('app.pm_sync', 'on', true);
  if c.status = 'approved' and v_amt <> 0 then
    v_ttl := left(c.code || ' · ' || btrim(c.description), 300);
    if c.variation_id is not null and exists (select 1 from public.contract_variations where id = c.variation_id) then
      update public.contract_variations
         set project_id = c.project_id, ref_no = left(coalesce(nullif(c.approval_ref, ''), c.code), 40), title = v_ttl,
             kind = case when v_amt > 0 then 'add' else 'deduct' end, amount = round(abs(v_amt), 3), approved_on = c.decided_on,
             notes = 'من سجل التغييرات ' || c.code
       where id = c.variation_id;
    else
      insert into public.contract_variations (project_id, ref_no, title, kind, amount, approved_on, notes, created_by)
      values (c.project_id, left(coalesce(nullif(c.approval_ref, ''), c.code), 40), v_ttl,
              case when v_amt > 0 then 'add' else 'deduct' end, round(abs(v_amt), 3), c.decided_on,
              'من سجل التغييرات ' || c.code, auth.uid())
      returning id into v_id;
      update public.pm_changes set variation_id = v_id where id = c.id;
      perform public.write_audit('finance.variation_add', c.project_id, null, jsonb_build_object(
        'variation_id', v_id, 'title', v_ttl, 'kind', case when v_amt > 0 then 'add' else 'deduct' end,
        'amount', round(abs(v_amt), 3), 'ref_no', coalesce(nullif(c.approval_ref, ''), c.code), 'change', c.code));
    end if;
  elsif c.variation_id is not null then
    delete from public.contract_variations where id = c.variation_id;
    update public.pm_changes set variation_id = null where id = c.id;
    perform public.write_audit('finance.variation_delete', c.project_id, null, jsonb_build_object(
      'variation_id', c.variation_id, 'title', c.code || ' · ' || c.description, 'change', c.code));
  end if;
  perform set_config('app.pm_sync', 'off', true);
end;
$$;

-- أمر التغيير المرتبط بسجل التغييرات لا يُعدَّل ولا يُحذف من المالية مباشرة (عدا نقله مع دمج العقود)
create or replace function public.contract_variations_pm_guard()
returns trigger
language plpgsql security definer set search_path = public
as $$
declare
  v_code text;
begin
  if coalesce(current_setting('app.pm_sync', true), '') = 'on' then
    return case when tg_op = 'DELETE' then old else new end;
  end if;
  select code into v_code from public.pm_changes where variation_id = old.id;
  if v_code is null then
    return case when tg_op = 'DELETE' then old else new end;
  end if;
  if tg_op = 'DELETE' then
    if not exists (select 1 from public.projects where id = old.project_id) then
      return old; -- حذف العقد نفسه
    end if;
    raise exception 'أمر التغيير هذا من سجل التغييرات (%)؛ ألغِ اعتماده أو عدّله من هناك', v_code using errcode = 'P0001';
  end if;
  if (new.title, new.kind, new.amount, new.approved_on, new.ref_no, new.work_id, new.notes)
     is distinct from (old.title, old.kind, old.amount, old.approved_on, old.ref_no, old.work_id, old.notes) then
    raise exception 'أمر التغيير هذا من سجل التغييرات (%)؛ عدّله من هناك', v_code using errcode = 'P0001';
  end if;
  return new;
end;
$$;
drop trigger if exists contract_variations_pm_guard on public.contract_variations;
create trigger contract_variations_pm_guard
  before update or delete on public.contract_variations
  for each row execute function public.contract_variations_pm_guard();

-- ---------------------------------------------------------------------
-- 8. الدروس المستفادة
-- ---------------------------------------------------------------------
create table if not exists public.pm_lessons (
  id              uuid primary key default gen_random_uuid(),
  code            text not null unique check (code ~ '^L[0-9]{2,4}$'),
  project_id      uuid references public.projects (id) on delete set null, -- فارغ = عام على مستوى المحفظة
  origin_project  uuid references public.projects (id) on delete set null,
  documented_on   date not null default current_date,
  phase           text not null default '' check (length(phase) <= 40),
  domain          text not null default '' check (length(domain) <= 40),
  lesson_type     text not null default 'negative' check (lesson_type in ('positive', 'negative')),
  situation       text not null check (length(btrim(situation)) between 3 and 600),
  root_cause      text not null default '' check (length(root_cause) <= 600),
  effect          text not null default '' check (length(effect) <= 300),
  lesson          text not null check (length(btrim(lesson)) between 3 and 800),
  apply_mechanism text not null default '' check (length(apply_mechanism) <= 60),
  apply_party     text not null default '' check (length(apply_party) <= 60),
  refs            text not null default '' check (length(refs) <= 120),
  status          text not null default 'proposed' check (status in ('proposed', 'approved', 'applied')),
  applied_on      date,
  prepared_by     text not null default '' check (length(prepared_by) <= 60),
  created_at      timestamptz not null default now(),
  created_by      uuid references public.profiles (id) on delete set null,
  updated_at      timestamptz not null default now(),
  updated_by      uuid references public.profiles (id) on delete set null
);
create index if not exists pm_lessons_project_idx    on public.pm_lessons (project_id);
create index if not exists pm_lessons_origin_idx     on public.pm_lessons (origin_project);
create index if not exists pm_lessons_created_by_idx on public.pm_lessons (created_by);
create index if not exists pm_lessons_updated_by_idx on public.pm_lessons (updated_by);

-- ---------------------------------------------------------------------
-- 9. التقييم الميداني الدوري للشركات (6 معايير من 1 إلى 5)
-- ---------------------------------------------------------------------
create table if not exists public.pm_evaluations (
  id             uuid primary key default gen_random_uuid(),
  project_id     uuid not null references public.projects (id) on delete cascade,
  origin_project uuid references public.projects (id) on delete set null,
  company        text not null default '' check (length(company) <= 200),
  evaluated_on   date not null,
  quality        smallint check (quality between 1 and 5),
  safety         smallint check (safety between 1 and 5),
  schedule       smallint check (schedule between 1 and 5),
  resources      smallint check (resources between 1 and 5),
  cooperation    smallint check (cooperation between 1 and 5),
  documentation  smallint check (documentation between 1 and 5),
  evaluator      text not null default '' check (length(evaluator) <= 60),
  notes          text not null default '' check (length(notes) <= 1000),
  created_at     timestamptz not null default now(),
  created_by     uuid references public.profiles (id) on delete set null,
  updated_at     timestamptz not null default now(),
  updated_by     uuid references public.profiles (id) on delete set null,
  check (coalesce(quality, safety, schedule, resources, cooperation, documentation) is not null)
);
create index if not exists pm_evaluations_project_idx    on public.pm_evaluations (project_id, evaluated_on);
create index if not exists pm_evaluations_origin_idx     on public.pm_evaluations (origin_project);
create index if not exists pm_evaluations_created_by_idx on public.pm_evaluations (created_by);
create index if not exists pm_evaluations_updated_by_idx on public.pm_evaluations (updated_by);

-- ---------------------------------------------------------------------
-- 10. دوال الحفظ والحذف للسجلات
-- ---------------------------------------------------------------------
-- رمز السجل: يُقبل الرمز المرسل إن طابق الصيغة ولم يُستخدم، وإلا يُولَّد التالي
create or replace function public.pm_code(p_table text, p_prefix text, p_given text, p_old text, p_id uuid)
returns text
language plpgsql security definer set search_path = public
as $$
declare
  v text := upper(nullif(btrim(coalesce(p_given, '')), ''));
  taken boolean;
begin
  v := coalesce(v, p_old);
  if v is null then
    return public.pm_next_code(p_table, p_prefix);
  end if;
  if v !~ ('^' || p_prefix || '[0-9]{2,4}$') then
    raise exception 'الرمز بالصيغة %01', p_prefix using errcode = '22023';
  end if;
  execute format('select exists (select 1 from public.%I where code = $1 and id is distinct from $2)', p_table)
    into taken using v, p_id;
  if taken then
    raise exception 'الرمز % مستخدم لسجل آخر', v using errcode = '23505';
  end if;
  return v;
end;
$$;

-- المشاكل --------------------------------------------------------------
create or replace function public.save_pm_issue(p_id uuid, p_data jsonb)
returns uuid
language plpgsql security definer set search_path = public
as $$
declare
  old_row public.pm_issues;
  new_row public.pm_issues;
  v_proj  uuid;
  v_code  text;
  v_risk  uuid;
  v_stat  text := public.jpick(p_data, 'status', array['open', 'in_progress', 'closed'], 'open', 'الحالة');
  v_close date := public.jdate(p_data, 'closed_on', 'تاريخ الإغلاق');
  v_desc  text := public.jtext(p_data, 'description', 400, 'وصف المشكلة');
  v_skip  text[] := array['updated_at', 'updated_by'];
begin
  if not public.can_edit_pm() then
    raise exception 'لا تملك صلاحية تحديث سجل المشاكل' using errcode = '42501';
  end if;
  if jsonb_typeof(coalesce(p_data, 'null'::jsonb)) <> 'object' then
    raise exception 'بيانات غير صالحة' using errcode = '22023';
  end if;
  if length(v_desc) < 3 then
    raise exception 'اكتب وصف المشكلة' using errcode = '22023';
  end if;
  if p_id is not null then
    select * into old_row from public.pm_issues where id = p_id for update;
    if not found then
      raise exception 'المشكلة غير موجودة' using errcode = 'P0002';
    end if;
    v_proj := coalesce(public.jproject(p_data, 'project_id', false), old_row.project_id);
  else
    v_proj := public.jproject(p_data, 'project_id', true);
  end if;
  v_code := public.pm_code('pm_issues', 'I', p_data ->> 'code', old_row.code, p_id);
  if nullif(p_data ->> 'risk_id', '') is not null then
    begin
      v_risk := (p_data ->> 'risk_id')::uuid;
    exception when others then
      raise exception 'خطر غير صالح' using errcode = '22023';
    end;
    if not exists (select 1 from public.risks where id = v_risk) then
      raise exception 'الخطر المرتبط غير موجود' using errcode = '22023';
    end if;
  end if;
  v_close := case when v_stat = 'closed' then coalesce(v_close, current_date) end;
  if p_id is null then
    insert into public.pm_issues (code, project_id, detected_on, description, category, risk_id, priority, party, department, action,
                                  time_impact_days, cost_impact, target_date, status, closed_on, notes, created_by, updated_by)
    values (v_code, v_proj, coalesce(public.jdate(p_data, 'detected_on', 'تاريخ الرصد'), current_date), v_desc,
            public.jtext(p_data, 'category', 40, 'التصنيف'), v_risk,
            public.jpick(p_data, 'priority', array['high', 'medium', 'low'], 'medium', 'الأولوية'),
            public.jpick(p_data, 'party', array['contractor', 'owner', 'consultant', 'utilities', 'force_majeure', 'other'],
                         'contractor', 'الجهة المسؤولة'),
            public.jtext(p_data, 'department', 60, 'القسم المتابع'), public.jtext(p_data, 'action', 600, 'الإجراء'),
            public.jint(p_data, 'time_impact_days', 0, 3650, 'الأثر الزمني'), public.jnum(p_data, 'cost_impact', 0, 1e12, 'الأثر المالي'),
            public.jdate(p_data, 'target_date', 'الموعد المستهدف للحل'), v_stat, v_close, public.jtext(p_data, 'notes', 1000, 'ملاحظات'),
            auth.uid(), auth.uid())
    returning * into new_row;
    perform public.write_audit('pm.issue_create', v_proj, null,
      jsonb_build_object('code', v_code, 'description', v_desc, 'priority', new_row.priority), v_code);
  else
    update public.pm_issues set
      code = v_code, project_id = v_proj,
      detected_on = coalesce(public.jdate(p_data, 'detected_on', 'تاريخ الرصد'), old_row.detected_on),
      description = v_desc, category = public.jtext(p_data, 'category', 40, 'التصنيف'), risk_id = v_risk,
      priority = public.jpick(p_data, 'priority', array['high', 'medium', 'low'], 'medium', 'الأولوية'),
      party = public.jpick(p_data, 'party', array['contractor', 'owner', 'consultant', 'utilities', 'force_majeure', 'other'],
                           'contractor', 'الجهة المسؤولة'),
      department = public.jtext(p_data, 'department', 60, 'القسم المتابع'), action = public.jtext(p_data, 'action', 600, 'الإجراء'),
      time_impact_days = public.jint(p_data, 'time_impact_days', 0, 3650, 'الأثر الزمني'),
      cost_impact = public.jnum(p_data, 'cost_impact', 0, 1e12, 'الأثر المالي'),
      target_date = public.jdate(p_data, 'target_date', 'الموعد المستهدف للحل'),
      status = v_stat, closed_on = v_close, notes = public.jtext(p_data, 'notes', 1000, 'ملاحظات'),
      updated_at = now(), updated_by = auth.uid()
    where id = p_id
    returning * into new_row;
    if public.jsonb_changes(to_jsonb(old_row), to_jsonb(new_row), v_skip) <> '{}'::jsonb then
      perform public.write_audit('pm.issue_update', v_proj, null,
        jsonb_build_object('code', v_code, 'changes', public.jsonb_changes(to_jsonb(old_row), to_jsonb(new_row), v_skip)), v_code);
    end if;
  end if;
  return new_row.id;
end;
$$;

-- التأخيرات -------------------------------------------------------------
create or replace function public.save_pm_delay(p_id uuid, p_data jsonb)
returns uuid
language plpgsql security definer set search_path = public
as $$
declare
  old_row public.pm_delays;
  new_row public.pm_delays;
  v_proj  uuid;
  v_code  text;
  v_desc  text := public.jtext(p_data, 'description', 400, 'وصف حدث التأخير');
  v_start date := public.jdate(p_data, 'start_date', 'تاريخ بداية التأثير');
  v_end   date := public.jdate(p_data, 'end_date', 'تاريخ نهاية التأثير');
  v_skip  text[] := array['updated_at', 'updated_by'];
begin
  if not public.can_edit_pm() then
    raise exception 'لا تملك صلاحية تحديث سجل التأخيرات' using errcode = '42501';
  end if;
  if jsonb_typeof(coalesce(p_data, 'null'::jsonb)) <> 'object' then
    raise exception 'بيانات غير صالحة' using errcode = '22023';
  end if;
  if length(v_desc) < 3 then
    raise exception 'اكتب وصف حدث التأخير' using errcode = '22023';
  end if;
  if v_start is null then
    raise exception 'حدّد تاريخ بداية التأثير' using errcode = '22023';
  end if;
  if v_end is not null and v_end < v_start then
    raise exception 'تاريخ نهاية التأثير قبل بدايته' using errcode = '22023';
  end if;
  if p_id is not null then
    select * into old_row from public.pm_delays where id = p_id for update;
    if not found then
      raise exception 'حدث التأخير غير موجود' using errcode = 'P0002';
    end if;
    v_proj := coalesce(public.jproject(p_data, 'project_id', false), old_row.project_id);
  else
    v_proj := public.jproject(p_data, 'project_id', true);
  end if;
  v_code := public.pm_code('pm_delays', 'D', p_data ->> 'code', old_row.code, p_id);
  if p_id is null then
    insert into public.pm_delays (code, project_id, description, cause, sub_cause, party, delay_class, critical, start_date, end_date,
                                  eot_requested, eot_approved, refs, notes, created_by, updated_by)
    values (v_code, v_proj, v_desc, public.jtext(p_data, 'cause', 60, 'السبب الرئيسي'), public.jtext(p_data, 'sub_cause', 300, 'السبب الفرعي'),
            public.jpick(p_data, 'party', array['contractor', 'owner', 'consultant', 'utilities', 'force_majeure', 'other'],
                         'contractor', 'الجهة المسؤولة'),
            public.jpick(p_data, 'delay_class', array['', 'excusable_comp', 'excusable', 'non_excusable', 'concurrent'], '', 'التصنيف التعاقدي'),
            public.jbool(p_data, 'critical'), v_start, v_end,
            public.jint(p_data, 'eot_requested', 0, 3650, 'التمديد المطلوب'), public.jint(p_data, 'eot_approved', 0, 3650, 'التمديد المعتمد'),
            public.jtext(p_data, 'refs', 120, 'المرجع المرتبط'), public.jtext(p_data, 'notes', 1000, 'ملاحظات'), auth.uid(), auth.uid())
    returning * into new_row;
    perform public.write_audit('pm.delay_create', v_proj, null,
      jsonb_build_object('code', v_code, 'description', v_desc, 'party', new_row.party), v_code);
  else
    update public.pm_delays set
      code = v_code, project_id = v_proj, description = v_desc,
      cause = public.jtext(p_data, 'cause', 60, 'السبب الرئيسي'), sub_cause = public.jtext(p_data, 'sub_cause', 300, 'السبب الفرعي'),
      party = public.jpick(p_data, 'party', array['contractor', 'owner', 'consultant', 'utilities', 'force_majeure', 'other'],
                           'contractor', 'الجهة المسؤولة'),
      delay_class = public.jpick(p_data, 'delay_class', array['', 'excusable_comp', 'excusable', 'non_excusable', 'concurrent'], '', 'التصنيف التعاقدي'),
      critical = public.jbool(p_data, 'critical'), start_date = v_start, end_date = v_end,
      eot_requested = public.jint(p_data, 'eot_requested', 0, 3650, 'التمديد المطلوب'),
      eot_approved = public.jint(p_data, 'eot_approved', 0, 3650, 'التمديد المعتمد'),
      refs = public.jtext(p_data, 'refs', 120, 'المرجع المرتبط'), notes = public.jtext(p_data, 'notes', 1000, 'ملاحظات'),
      updated_at = now(), updated_by = auth.uid()
    where id = p_id
    returning * into new_row;
    if public.jsonb_changes(to_jsonb(old_row), to_jsonb(new_row), v_skip) <> '{}'::jsonb then
      perform public.write_audit('pm.delay_update', v_proj, null,
        jsonb_build_object('code', v_code, 'changes', public.jsonb_changes(to_jsonb(old_row), to_jsonb(new_row), v_skip)), v_code);
    end if;
  end if;
  return new_row.id;
end;
$$;

-- التغييرات --------------------------------------------------------------
create or replace function public.save_pm_change(p_id uuid, p_data jsonb)
returns uuid
language plpgsql security definer set search_path = public
as $$
declare
  old_row public.pm_changes;
  new_row public.pm_changes;
  v_proj  uuid;
  v_code  text;
  v_desc  text := public.jtext(p_data, 'description', 280, 'وصف التغيير');
  v_stat  text := public.jpick(p_data, 'status', array['submitted', 'under_study', 'approved', 'rejected'], 'submitted', 'الحالة');
  v_dec   date := public.jdate(p_data, 'decided_on', 'تاريخ البت');
  v_skip  text[] := array['updated_at', 'updated_by', 'variation_id'];
begin
  if not public.can_edit_pm() then
    raise exception 'لا تملك صلاحية تحديث سجل التغييرات' using errcode = '42501';
  end if;
  if jsonb_typeof(coalesce(p_data, 'null'::jsonb)) <> 'object' then
    raise exception 'بيانات غير صالحة' using errcode = '22023';
  end if;
  if length(v_desc) < 3 then
    raise exception 'اكتب وصف التغيير' using errcode = '22023';
  end if;
  if p_id is not null then
    select * into old_row from public.pm_changes where id = p_id for update;
    if not found then
      raise exception 'طلب التغيير غير موجود' using errcode = 'P0002';
    end if;
    v_proj := coalesce(public.jproject(p_data, 'project_id', false), old_row.project_id);
  else
    v_proj := public.jproject(p_data, 'project_id', true);
  end if;
  if (v_stat in ('approved', 'rejected') or old_row.status in ('approved', 'rejected'))
     and not (public.can_decide_change(v_proj) and (old_row.project_id is null or public.can_decide_change(old_row.project_id))) then
    raise exception 'البت في طلبات التغيير وتعديل المبتوت فيها لمن يختص بمالية العقد والمدير' using errcode = '42501';
  end if;
  v_code := public.pm_code('pm_changes', 'C', p_data ->> 'code', old_row.code, p_id);
  v_dec := case when v_stat in ('approved', 'rejected') then coalesce(v_dec, current_date) end;
  if p_id is null then
    insert into public.pm_changes (code, project_id, submitted_on, description, change_type, source, reason, cost_estimate, cost_approved,
                                   time_requested, time_approved, status, decided_on, approval_ref, refs, notes, created_by, updated_by)
    values (v_code, v_proj, coalesce(public.jdate(p_data, 'submitted_on', 'تاريخ التقديم'), current_date), v_desc,
            public.jtext(p_data, 'change_type', 60, 'نوع التغيير'),
            public.jpick(p_data, 'source', array['owner', 'consultant', 'contractor', 'site', 'external'], 'owner', 'مصدر التغيير'),
            public.jtext(p_data, 'reason', 80, 'سبب التغيير'),
            public.jnum(p_data, 'cost_estimate', -1e12, 1e12, 'الأثر المالي المقدر'),
            public.jnum(p_data, 'cost_approved', -1e12, 1e12, 'الأثر المالي المعتمد'),
            public.jint(p_data, 'time_requested', 0, 3650, 'الأثر الزمني المطلوب'),
            public.jint(p_data, 'time_approved', 0, 3650, 'الأثر الزمني المعتمد'),
            v_stat, v_dec, public.jtext(p_data, 'approval_ref', 60, 'مرجع الاعتماد'), public.jtext(p_data, 'refs', 120, 'المرجع المرتبط'),
            public.jtext(p_data, 'notes', 1000, 'ملاحظات'), auth.uid(), auth.uid())
    returning * into new_row;
    perform public.write_audit('pm.change_create', v_proj, null,
      jsonb_build_object('code', v_code, 'description', v_desc, 'status', v_stat, 'cost_approved', new_row.cost_approved), v_code);
  else
    update public.pm_changes set
      code = v_code, project_id = v_proj,
      submitted_on = coalesce(public.jdate(p_data, 'submitted_on', 'تاريخ التقديم'), old_row.submitted_on),
      description = v_desc, change_type = public.jtext(p_data, 'change_type', 60, 'نوع التغيير'),
      source = public.jpick(p_data, 'source', array['owner', 'consultant', 'contractor', 'site', 'external'], 'owner', 'مصدر التغيير'),
      reason = public.jtext(p_data, 'reason', 80, 'سبب التغيير'),
      cost_estimate = public.jnum(p_data, 'cost_estimate', -1e12, 1e12, 'الأثر المالي المقدر'),
      cost_approved = public.jnum(p_data, 'cost_approved', -1e12, 1e12, 'الأثر المالي المعتمد'),
      time_requested = public.jint(p_data, 'time_requested', 0, 3650, 'الأثر الزمني المطلوب'),
      time_approved = public.jint(p_data, 'time_approved', 0, 3650, 'الأثر الزمني المعتمد'),
      status = v_stat, decided_on = v_dec, approval_ref = public.jtext(p_data, 'approval_ref', 60, 'مرجع الاعتماد'),
      refs = public.jtext(p_data, 'refs', 120, 'المرجع المرتبط'), notes = public.jtext(p_data, 'notes', 1000, 'ملاحظات'),
      updated_at = now(), updated_by = auth.uid()
    where id = p_id
    returning * into new_row;
    if public.jsonb_changes(to_jsonb(old_row), to_jsonb(new_row), v_skip) <> '{}'::jsonb then
      perform public.write_audit('pm.change_update', v_proj, null,
        jsonb_build_object('code', v_code, 'changes', public.jsonb_changes(to_jsonb(old_row), to_jsonb(new_row), v_skip)), v_code);
    end if;
  end if;
  perform public.pm_sync_change_variation(new_row.id);
  return new_row.id;
end;
$$;

-- الدروس المستفادة ----------------------------------------------------------
create or replace function public.save_pm_lesson(p_id uuid, p_data jsonb)
returns uuid
language plpgsql security definer set search_path = public
as $$
declare
  old_row public.pm_lessons;
  new_row public.pm_lessons;
  v_proj  uuid := public.jproject(p_data, 'project_id', false);
  v_code  text;
  v_sit   text := public.jtext(p_data, 'situation', 600, 'الموقف');
  v_les   text := public.jtext(p_data, 'lesson', 800, 'الدرس المستفاد');
  v_stat  text := public.jpick(p_data, 'status', array['proposed', 'approved', 'applied'], 'proposed', 'حالة التطبيق');
  v_on    date := public.jdate(p_data, 'applied_on', 'تاريخ الاعتماد / التطبيق');
  v_skip  text[] := array['updated_at', 'updated_by'];
begin
  if not public.can_edit_pm() then
    raise exception 'لا تملك صلاحية تحديث الدروس المستفادة' using errcode = '42501';
  end if;
  if jsonb_typeof(coalesce(p_data, 'null'::jsonb)) <> 'object' then
    raise exception 'بيانات غير صالحة' using errcode = '22023';
  end if;
  if length(v_sit) < 3 or length(v_les) < 3 then
    raise exception 'اكتب الموقف والدرس المستفاد' using errcode = '22023';
  end if;
  if p_id is not null then
    select * into old_row from public.pm_lessons where id = p_id for update;
    if not found then
      raise exception 'الدرس غير موجود' using errcode = 'P0002';
    end if;
  end if;
  if (v_stat <> 'proposed' or coalesce(old_row.status, 'proposed') <> 'proposed') and not public.can_approve_lessons() then
    raise exception 'اعتماد الدروس وتطبيقها لمدير المكتب وفريق مكتبه' using errcode = '42501';
  end if;
  v_code := public.pm_code('pm_lessons', 'L', p_data ->> 'code', old_row.code, p_id);
  v_on := case when v_stat <> 'proposed' then coalesce(v_on, current_date) end;
  if p_id is null then
    insert into public.pm_lessons (code, project_id, documented_on, phase, domain, lesson_type, situation, root_cause, effect, lesson,
                                   apply_mechanism, apply_party, refs, status, applied_on, prepared_by, created_by, updated_by)
    values (v_code, v_proj, coalesce(public.jdate(p_data, 'documented_on', 'تاريخ التوثيق'), current_date),
            public.jtext(p_data, 'phase', 40, 'المرحلة'), public.jtext(p_data, 'domain', 40, 'المجال'),
            public.jpick(p_data, 'lesson_type', array['positive', 'negative'], 'negative', 'نوع الدرس'), v_sit,
            public.jtext(p_data, 'root_cause', 600, 'السبب الجذري'), public.jtext(p_data, 'effect', 300, 'الأثر'), v_les,
            public.jtext(p_data, 'apply_mechanism', 60, 'آلية التعميم'), public.jtext(p_data, 'apply_party', 60, 'الجهة المعنية بالتطبيق'),
            public.jtext(p_data, 'refs', 120, 'المرجع المرتبط'), v_stat, v_on, public.jtext(p_data, 'prepared_by', 60, 'أعدّه'),
            auth.uid(), auth.uid())
    returning * into new_row;
    perform public.write_audit('pm.lesson_create', v_proj, null, jsonb_build_object('code', v_code, 'lesson', v_les), v_code);
  else
    update public.pm_lessons set
      code = v_code, project_id = v_proj,
      documented_on = coalesce(public.jdate(p_data, 'documented_on', 'تاريخ التوثيق'), old_row.documented_on),
      phase = public.jtext(p_data, 'phase', 40, 'المرحلة'), domain = public.jtext(p_data, 'domain', 40, 'المجال'),
      lesson_type = public.jpick(p_data, 'lesson_type', array['positive', 'negative'], 'negative', 'نوع الدرس'),
      situation = v_sit, root_cause = public.jtext(p_data, 'root_cause', 600, 'السبب الجذري'),
      effect = public.jtext(p_data, 'effect', 300, 'الأثر'), lesson = v_les,
      apply_mechanism = public.jtext(p_data, 'apply_mechanism', 60, 'آلية التعميم'),
      apply_party = public.jtext(p_data, 'apply_party', 60, 'الجهة المعنية بالتطبيق'),
      refs = public.jtext(p_data, 'refs', 120, 'المرجع المرتبط'), status = v_stat, applied_on = v_on,
      prepared_by = public.jtext(p_data, 'prepared_by', 60, 'أعدّه'), updated_at = now(), updated_by = auth.uid()
    where id = p_id
    returning * into new_row;
    if public.jsonb_changes(to_jsonb(old_row), to_jsonb(new_row), v_skip) <> '{}'::jsonb then
      perform public.write_audit('pm.lesson_update', v_proj, null,
        jsonb_build_object('code', v_code, 'changes', public.jsonb_changes(to_jsonb(old_row), to_jsonb(new_row), v_skip)), v_code);
    end if;
  end if;
  return new_row.id;
end;
$$;

-- التقييم الدوري للشركات ---------------------------------------------------------
create or replace function public.save_pm_evaluation(p_id uuid, p_data jsonb)
returns uuid
language plpgsql security definer set search_path = public
as $$
declare
  old_row public.pm_evaluations;
  new_row public.pm_evaluations;
  v_proj  uuid;
  v_on    date := public.jdate(p_data, 'evaluated_on', 'تاريخ التقييم');
  v_co    text := public.jtext(p_data, 'company', 200, 'الشركة');
  v_q     smallint := public.jscore(p_data, 'quality', 5, 'جودة الأعمال');
  v_s     smallint := public.jscore(p_data, 'safety', 5, 'السلامة المهنية');
  v_sc    smallint := public.jscore(p_data, 'schedule', 5, 'الالتزام بالبرنامج الزمني');
  v_r     smallint := public.jscore(p_data, 'resources', 5, 'كفاءة الجهاز الفني والمعدات');
  v_c     smallint := public.jscore(p_data, 'cooperation', 5, 'الاستجابة والتعاون');
  v_d     smallint := public.jscore(p_data, 'documentation', 5, 'التوثيق والتقارير');
begin
  if not public.can_edit_pm() then
    raise exception 'لا تملك صلاحية تسجيل تقييم الشركات' using errcode = '42501';
  end if;
  if jsonb_typeof(coalesce(p_data, 'null'::jsonb)) <> 'object' then
    raise exception 'بيانات غير صالحة' using errcode = '22023';
  end if;
  if coalesce(v_q, v_s, v_sc, v_r, v_c, v_d) is null then
    raise exception 'قيّم معياراً واحداً على الأقل' using errcode = '22023';
  end if;
  v_on := coalesce(v_on, current_date);
  if p_id is not null then
    select * into old_row from public.pm_evaluations where id = p_id for update;
    if not found then
      raise exception 'التقييم غير موجود' using errcode = 'P0002';
    end if;
    v_proj := coalesce(public.jproject(p_data, 'project_id', false), old_row.project_id);
  else
    v_proj := public.jproject(p_data, 'project_id', true);
  end if;
  if v_co = '' then
    select btrim(company) into v_co from public.projects where id = v_proj;
  end if;
  if p_id is null then
    insert into public.pm_evaluations (project_id, company, evaluated_on, quality, safety, schedule, resources, cooperation, documentation,
                                       evaluator, notes, created_by, updated_by)
    values (v_proj, coalesce(v_co, ''), v_on, v_q, v_s, v_sc, v_r, v_c, v_d, public.jtext(p_data, 'evaluator', 60, 'المُقيِّم'),
            public.jtext(p_data, 'notes', 1000, 'ملاحظات وأدلة التقييم'), auth.uid(), auth.uid())
    returning * into new_row;
    perform public.write_audit('pm.evaluation_add', v_proj, null,
      jsonb_build_object('company', new_row.company, 'evaluated_on', v_on));
  else
    update public.pm_evaluations set
      project_id = v_proj, company = coalesce(v_co, ''), evaluated_on = v_on, quality = v_q, safety = v_s, schedule = v_sc,
      resources = v_r, cooperation = v_c, documentation = v_d, evaluator = public.jtext(p_data, 'evaluator', 60, 'المُقيِّم'),
      notes = public.jtext(p_data, 'notes', 1000, 'ملاحظات وأدلة التقييم'), updated_at = now(), updated_by = auth.uid()
    where id = p_id
    returning * into new_row;
    perform public.write_audit('pm.evaluation_update', v_proj, null,
      jsonb_build_object('company', new_row.company, 'evaluated_on', v_on,
                         'changes', public.jsonb_changes(to_jsonb(old_row), to_jsonb(new_row), array['updated_at', 'updated_by'])));
  end if;
  return new_row.id;
end;
$$;

-- حذف موحّد لسجلات المتابعة (مدير المكتب وحده)
create or replace function public.delete_pm_record(p_kind text, p_id uuid)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  v_table text := case p_kind when 'issue' then 'pm_issues' when 'delay' then 'pm_delays' when 'change' then 'pm_changes'
                              when 'lesson' then 'pm_lessons' when 'evaluation' then 'pm_evaluations' end;
  r       jsonb;
  v_var   uuid;
begin
  if v_table is null then
    raise exception 'نوع سجل غير معروف' using errcode = '22023';
  end if;
  if not public.is_director() then
    raise exception 'الحذف من صلاحية مدير المكتب وحده' using errcode = '42501';
  end if;
  execute format('select to_jsonb(t) from public.%I t where id = $1', v_table) into r using p_id;
  if r is null then
    raise exception 'السجل غير موجود' using errcode = 'P0002';
  end if;
  if p_kind = 'change' then
    v_var := nullif(r ->> 'variation_id', '')::uuid;
    if v_var is not null then
      perform set_config('app.pm_sync', 'on', true);
      delete from public.contract_variations where id = v_var;
      perform set_config('app.pm_sync', 'off', true);
      perform public.write_audit('finance.variation_delete', (r ->> 'project_id')::uuid, null, jsonb_build_object(
        'variation_id', v_var, 'title', (r ->> 'code') || ' · ' || (r ->> 'description'), 'change', r ->> 'code'));
    end if;
  end if;
  execute format('delete from public.%I where id = $1', v_table) using p_id;
  perform public.write_audit('pm.' || p_kind || '_delete', nullif(r ->> 'project_id', '')::uuid, null,
    r - array['created_at', 'created_by', 'updated_at', 'updated_by', 'origin_project'], coalesce(r ->> 'code', r ->> 'company'));
end;
$$;

-- ---------------------------------------------------------------------
-- 11. الإعدادات: pm.config (القوائم والحدود والأوزان)، وتوسيع risk.config (دورية المراجعة ومنفذو الإجراءات)
-- ---------------------------------------------------------------------
create or replace function public.pm_num_ok(p jsonb, k text, lo numeric, hi numeric)
returns boolean
language sql immutable set search_path = public
as $$
  select p -> k is null or jsonb_typeof(p -> k) = 'null'
      or (jsonb_typeof(p -> k) = 'number' and (p ->> k)::numeric between lo and hi)
$$;

do $$
begin
  if not exists (select 1 from pg_proc where proname = 'set_setting_v15' and pronamespace = 'public'::regnamespace) then
    alter function public.set_setting(text, jsonb) rename to set_setting_v15;
  end if;
end $$;

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

insert into public.app_settings (key, value) values
  ('pm.config', '{
     "project_types": ["طرق", "جسور", "مبانٍ عامة", "مدارس", "إسكان", "مرافق وشبكات", "ترميم مبانٍ تراثية", "فراغات عامة وأحياء", "مرافق صحية"],
     "departments": ["الإشراف والتنسيق", "الشؤون الفنية", "الترميم", "المطابقة والاستلام", "مكتب المدير"],
     "delay_causes": ["التمويل والمستخلصات", "التصميم والمخططات", "أوامر التغيير", "المقاول – الموارد والإدارة", "المواد والتوريد",
                      "الموقع وتسليمه", "المرافق والجهات الخدمية", "الاعتمادات والتصاريح", "الظروف الجوية", "مخلفات الحرب والأمن", "أخرى"],
     "change_types": ["أمر تغيير", "أعمال إضافية", "حذف أعمال", "تعديل تصميم", "تعديل مواصفات", "تمديد مدة"],
     "change_reasons": ["نقص أو خطأ في التصميم", "طلب الجهة المالكة", "ظروف موقع غير متوقعة", "تعارض مع مرافق قائمة",
                        "تحديث مواصفات أو معايير", "اقتراح توفير من المقاول", "متطلبات الحفاظ التراثي", "أخرى"],
     "lesson_apply": ["تعديل نموذج", "تعديل إجراء", "شرط تعاقدي", "تدريب", "معيار تأهيل", "أخرى"],
     "alert_days": 7, "spi_ahead": 1.05, "spi_ok": 0.95, "spi_warn": 0.85, "change_limit": 0.1, "change_decide_days": 21,
     "issue_days": 14, "stale_days": 10, "forecast_delay_alert": 30,
     "weights": {"schedule": 0.3, "delay": 0.15, "field": 0.4, "response": 0.15}, "spi_zero": 0.7, "delay_zero": 0.2,
     "grades": [{"min": 0, "name": "ضعيف", "rec": "تحتاج مراجعة قبل أي إسناد جديد"},
                {"min": 50, "name": "مقبول", "rec": "إسناد مشروط بخطة تحسين"},
                {"min": 65, "name": "جيد", "rec": "مؤهلة مع متابعة"},
                {"min": 75, "name": "جيد جداً", "rec": "مؤهلة"},
                {"min": 85, "name": "ممتاز", "rec": "مؤهلة ومفضّلة"}],
     "ref_date": null,
     "framework": {"version": "2.0", "issued": "2026-10", "status": "مسودة للاعتماد"}
   }'::jsonb)
on conflict (key) do nothing;

-- ترقية risk.config إلى الإصدار 2.0 (دون المساس بما خصّصه المدير)
do $$
declare
  cfg   jsonb := (select value from public.app_settings where key = 'risk.config');
  lv    jsonb;
  outl  jsonb := '[]'::jsonb;
  e     jsonb;
  n     integer;
  i     integer;
  v1_levels jsonb := '[{"name": "منخفض جداً", "min": 1, "action": "مراقبة"}, {"name": "منخفض", "min": 5, "action": "متابعة"}, {"name": "متوسط", "min": 9, "action": "خطة معالجة"}, {"name": "مرتفع", "min": 13, "action": "تصعيد إلى PMO"}, {"name": "مرتفع جداً", "min": 20, "action": "تصعيد عاجل"}]';
  v2_levels jsonb := '[{"name": "منخفض جداً", "min": 1, "action": "مراقبة – رئيس القسم المختص", "review_days": 90}, {"name": "منخفض", "min": 5, "action": "متابعة دورية – رئيس القسم المختص", "review_days": 60}, {"name": "متوسط", "min": 9, "action": "خطة معالجة – رئيس القسم المختص", "review_days": 30}, {"name": "مرتفع", "min": 13, "action": "تصعيد إلى مدير المكتب", "review_days": 14}, {"name": "مرتفع جداً", "min": 20, "action": "تصعيد عاجل إلى مدير المكتب ورفعه للجنة", "review_days": 7}]';
  by_name jsonb := '{"منخفض جداً": 90, "منخفض": 60, "متوسط": 30, "مرتفع": 14, "مرتفع جداً": 7}';
  ladder  integer[] := array[7, 14, 30, 60, 90, 120, 180];
  v1_cats jsonb := '["فني", "تعاقدي", "موقعي", "مالي", "سلامة", "توريد", "جودة", "تنسيق", "زمني", "بيئي", "قانوني", "حوكمة"]';
  v1_phases jsonb := '["التخطيط", "التصميم", "التعاقد", "التنفيذ", "الاستلام", "المتابعة"]';
  v1_projects jsonb := '["الطرق والجسور", "المباني العامة", "المرافق", "المدارس", "الجسور", "الإسكان", "الطرق", "المباني", "الأحياء", "متعدد المشاريع"]';
  v1_owners jsonb := '["مدير المشروع", "PMO", "الاستشاري", "المقاول", "العقود", "المالية", "المشتريات", "السلامة", "الجودة", "القانونية"]';
  x     text;
begin
  if cfg is null then
    return;
  end if;
  lv := cfg -> 'levels';
  if lv = v1_levels then
    cfg := jsonb_set(cfg, '{levels}', v2_levels);
  elsif jsonb_typeof(lv) = 'array' then
    n := jsonb_array_length(lv);
    for i in 0 .. n - 1 loop
      e := lv -> i;
      if not (e ? 'review_days') then
        e := e || jsonb_build_object('review_days', coalesce((by_name ->> (e ->> 'name'))::integer, ladder[least(n - i, 7)]));
      end if;
      outl := outl || jsonb_build_array(e);
    end loop;
    cfg := jsonb_set(cfg, '{levels}', outl);
  end if;
  if cfg -> 'categories' = v1_cats or cfg -> 'categories' is null then
    cfg := jsonb_set(cfg, '{categories}', v1_cats || '["مخلفات الحرب والأمن", "تراثي وترميم"]'::jsonb);
  else
    foreach x in array array['مخلفات الحرب والأمن', 'تراثي وترميم'] loop
      if not (cfg -> 'categories' ? x) then
        cfg := jsonb_set(cfg, '{categories}', (cfg -> 'categories') || to_jsonb(x));
      end if;
    end loop;
  end if;
  if cfg -> 'phases' = v1_phases or cfg -> 'phases' is null then
    cfg := jsonb_set(cfg, '{phases}', '["التخطيط", "التصميم", "التعاقد", "التنفيذ", "الاستلام", "فترة الضمان", "المتابعة"]'::jsonb);
  elsif not (cfg -> 'phases' ? 'فترة الضمان') then
    cfg := jsonb_set(cfg, '{phases}', (cfg -> 'phases') || '["فترة الضمان"]'::jsonb);
  end if;
  if cfg -> 'projects' = v1_projects or cfg -> 'projects' is null then
    cfg := jsonb_set(cfg, '{projects}', '["طرق", "جسور", "مبانٍ عامة", "مدارس", "إسكان", "مرافق وشبكات", "ترميم مبانٍ تراثية", "فراغات عامة وأحياء", "مرافق صحية", "متعدد المشاريع"]'::jsonb);
  end if;
  if cfg -> 'owners' = v1_owners or cfg -> 'owners' is null then
    cfg := jsonb_set(cfg, '{owners}', '["الإشراف والتنسيق", "الشؤون الفنية", "الترميم", "المطابقة والاستلام", "مكتب المدير"]'::jsonb);
  end if;
  if cfg -> 'executors' is null then
    cfg := cfg || jsonb_build_object('executors', '["المقاول", "الاستشاري", "الإشراف والتنسيق", "الشؤون الفنية", "الترميم", "المطابقة والاستلام", "مكتب المدير", "الشؤون المالية", "العقود والمشتريات", "الشؤون القانونية", "السلامة المهنية", "الجهات المختصة", "اللجنة"]'::jsonb);
  end if;
  update public.app_settings set value = cfg where key = 'risk.config' and value is distinct from cfg;
end $$;

-- ---------------------------------------------------------------------
-- 12. سجلات المتابعة تتبع العقد عند الدمج وتعود بفكّه
-- ---------------------------------------------------------------------
create or replace function public.pm_follow_merge()
returns trigger
language plpgsql security definer set search_path = public
as $$
declare
  t text;
begin
  if new.merged_into is not null and old.merged_into is null then
    foreach t in array array['risks', 'pm_issues', 'pm_delays', 'pm_changes', 'pm_lessons', 'pm_evaluations'] loop
      execute format('update public.%I set project_id = $1, origin_project = coalesce(origin_project, $2) where project_id = $2', t)
        using new.merged_into, new.id;
    end loop;
    update public.pm_progress p set project_id = new.merged_into, origin_project = coalesce(p.origin_project, new.id)
     where p.project_id = new.id
       and not exists (select 1 from public.pm_progress x where x.project_id = new.merged_into and x.measured_on = p.measured_on);
  elsif new.merged_into is null and old.merged_into is not null then
    foreach t in array array['risks', 'pm_issues', 'pm_delays', 'pm_changes', 'pm_lessons', 'pm_evaluations', 'pm_progress'] loop
      execute format('update public.%I set project_id = $1, origin_project = null where project_id = $2 and origin_project = $1', t)
        using new.id, old.merged_into;
    end loop;
  end if;
  return null;
end;
$$;
drop trigger if exists projects_pm_follow_merge on public.projects;
create trigger projects_pm_follow_merge
  after update of merged_into on public.projects
  for each row when (old.merged_into is distinct from new.merged_into)
  execute function public.pm_follow_merge();

-- ---------------------------------------------------------------------
-- 13. ملخص مساعد Claude: يضاف إليه البرنامج الزمني والتقدم ومراجعات المخاطر وسجلات المتابعة
-- ---------------------------------------------------------------------
do $$
begin
  if not exists (select 1 from pg_proc where proname = 'ai_context_v15' and pronamespace = 'public'::regnamespace) then
    alter function public.ai_context() rename to ai_context_v15;
  end if;
end $$;

create or replace function public.ai_context()
returns jsonb
language plpgsql stable security definer set search_path = public
as $$
declare
  base jsonb := public.ai_context_v15();
begin
  return base || jsonb_build_object(
    'pm_config', public.setting('pm.config'),
    'pm', jsonb_build_object(
      'schedules', coalesce((
        select jsonb_agg(jsonb_build_object('contract', public.project_label(s.project_id), 'type', s.project_type,
                                            'location', s.location, 'consultant', s.consultant, 'status', s.op_status,
                                            'start', s.start_date, 'end', s.end_date) order by s.start_date nulls last)
          from public.pm_projects s join public.projects p on p.id = s.project_id and p.merged_into is null), '[]'::jsonb),
      'latest_progress', coalesce((
        select jsonb_agg(jsonb_build_object('contract', public.project_label(x.project_id), 'date', x.measured_on,
                                            'planned', x.planned, 'actual', x.actual, 'obstacles', x.obstacles))
          from (select distinct on (project_id) * from public.pm_progress order by project_id, measured_on desc) x), '[]'::jsonb),
      'risk_reviews', coalesce((
        select jsonb_agg(jsonb_build_object('risk', r.code, 'date', v.reviewed_on, 'score', v.score, 'progress', v.progress,
                                            'actions', v.actions_done) order by r.code)
          from (select distinct on (risk_id) * from public.risk_reviews order by risk_id, reviewed_on desc, created_at desc) v
          join public.risks r on r.id = v.risk_id), '[]'::jsonb),
      'issues', coalesce((
        select jsonb_agg(jsonb_build_object('code', i.code, 'contract', public.project_label(i.project_id), 'description', i.description,
                                            'priority', i.priority, 'party', i.party, 'target', i.target_date, 'status', i.status)
                         order by i.code)
          from public.pm_issues i where i.status <> 'closed'), '[]'::jsonb),
      'delays', coalesce((
        select jsonb_agg(jsonb_build_object('code', d.code, 'contract', public.project_label(d.project_id), 'description', d.description,
                                            'cause', d.cause, 'party', d.party, 'class', d.delay_class, 'critical', d.critical,
                                            'start', d.start_date, 'end', d.end_date, 'eot_requested', d.eot_requested,
                                            'eot_approved', d.eot_approved) order by d.code)
          from public.pm_delays d), '[]'::jsonb),
      'changes', coalesce((
        select jsonb_agg(jsonb_build_object('code', c.code, 'contract', public.project_label(c.project_id), 'description', c.description,
                                            'type', c.change_type, 'source', c.source, 'status', c.status,
                                            'cost_estimate', c.cost_estimate, 'cost_approved', c.cost_approved,
                                            'time_approved', c.time_approved, 'decided_on', c.decided_on) order by c.code)
          from public.pm_changes c), '[]'::jsonb),
      'lessons', coalesce((
        select jsonb_agg(jsonb_build_object('code', l.code, 'lesson', l.lesson, 'type', l.lesson_type, 'status', l.status)
                         order by l.code)
          from public.pm_lessons l), '[]'::jsonb),
      'evaluations', coalesce((
        select jsonb_agg(jsonb_build_object('company', e.company, 'date', e.evaluated_on,
                                            'scores', jsonb_build_array(e.quality, e.safety, e.schedule, e.resources, e.cooperation,
                                                                        e.documentation)) order by e.evaluated_on desc)
          from public.pm_evaluations e), '[]'::jsonb)));
end;
$$;

-- ---------------------------------------------------------------------
-- 14. الصلاحيات والتحديث اللحظي
-- ---------------------------------------------------------------------
do $$
declare
  t text;
begin
  foreach t in array array['pm_projects', 'pm_progress', 'risk_reviews', 'pm_issues', 'pm_delays', 'pm_changes', 'pm_lessons',
                           'pm_evaluations'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('drop policy if exists %I on public.%I', t || '_read', t);
    execute format('create policy %I on public.%I for select to authenticated using ((select public.is_member()))', t || '_read', t);
    execute format('revoke all on public.%I from anon', t);
    execute format('revoke insert, update, delete, truncate on public.%I from authenticated', t);
    execute format('grant select on public.%I to authenticated', t);
    execute format('grant all on public.%I to service_role', t);
    if not exists (select 1 from pg_publication_tables
                   where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = t) then
      execute format('alter publication supabase_realtime add table public.%I', t);
    end if;
  end loop;
end $$;

revoke execute on function
  public.jint(jsonb, text, integer, integer, text, boolean), public.jnum(jsonb, text, numeric, numeric, text, boolean),
  public.jpick(jsonb, text, text[], text, text), public.jbool(jsonb, text), public.jproject(jsonb, text, boolean),
  public.pm_next_code(text, text), public.pm_code(text, text, text, text, uuid), public.pm_num_ok(jsonb, text, numeric, numeric),
  public.pm_sync_change_variation(uuid), public.contract_variations_pm_guard(), public.pm_follow_merge(),
  public.set_setting_v15(text, jsonb), public.ai_context_v15()
from public, anon, authenticated;

revoke execute on function
  public.can_edit_pm(), public.can_edit_schedule(uuid), public.can_decide_change(uuid), public.can_approve_lessons(),
  public.save_project_schedule(uuid, jsonb), public.save_pm_progress(uuid, jsonb), public.delete_pm_progress(uuid),
  public.save_risk(uuid, jsonb), public.save_risk_review(uuid, uuid, jsonb), public.delete_risk_review(uuid),
  public.save_pm_issue(uuid, jsonb), public.save_pm_delay(uuid, jsonb), public.save_pm_change(uuid, jsonb),
  public.save_pm_lesson(uuid, jsonb), public.save_pm_evaluation(uuid, jsonb), public.delete_pm_record(text, uuid),
  public.set_setting(text, jsonb), public.ai_context()
from public, anon;
grant execute on function
  public.can_edit_pm(), public.can_edit_schedule(uuid), public.can_decide_change(uuid), public.can_approve_lessons(),
  public.save_project_schedule(uuid, jsonb), public.save_pm_progress(uuid, jsonb), public.delete_pm_progress(uuid),
  public.save_risk(uuid, jsonb), public.save_risk_review(uuid, uuid, jsonb), public.delete_risk_review(uuid),
  public.save_pm_issue(uuid, jsonb), public.save_pm_delay(uuid, jsonb), public.save_pm_change(uuid, jsonb),
  public.save_pm_lesson(uuid, jsonb), public.save_pm_evaluation(uuid, jsonb), public.delete_pm_record(text, uuid),
  public.set_setting(text, jsonb), public.ai_context()
to authenticated;

-- ---------------------------------------------------------------------
-- 15. ترقية المخاطر الأولى إلى صيغة الإصدار 2.0 وإضافة الخطرين الجديدين ومراجعاتها
--     (يُحدَّث الخطر فقط إن بقي كما أُدرج أول مرة ولم يعدّله أحد)
-- ---------------------------------------------------------------------
drop table if exists pm_v2_risks;
drop table if exists pm_v1_desc;
create temporary table pm_v2_risks (code text, grp text, phase text, cat text, dept text, descr text, cause text, effect text,
  p smallint, i smallint, days integer, cost numeric, resp text, mitig text, cont text, owner text, exec text, status text,
  tp smallint, ti smallint, reg date, target date, closed date, warn text, notes text);
insert into pm_v2_risks values
  ('R01', 'جسور', 'التصميم', 'فني', 'الشؤون الفنية', 'قصور الدراسات الجيوتقنية لموقع الجسر', 'نقص الجسات في الدراسة الأصلية', 'إعادة تصميم الأساسات وأوامر تغيير', 4, 5, 45, 1500000, 'mitigate', 'استكمال الجسات التكميلية واعتماد التصميم المعدّل قبل صب الأساسات', 'تفعيل أمر تغيير واعتماد حل أساسات بديل', 'الشؤون الفنية', 'الاستشاري', 'in_progress', 2, 2, '2026-03-10', '2026-11-30', null, 'نتائج جسات تختلف عن الدراسة بأكثر من 20%', ''),
  ('R02', 'مرافق صحية', 'التعاقد', 'تعاقدي', 'الشؤون الفنية', 'تأخر ترسية عقد المركز الصحي', 'إجراءات اعتماد مطولة', 'تأخر البدء عن الموعد المخطط', 4, 4, 60, 0, 'mitigate', 'خطة مشتريات بمواعيد ملزمة ومتابعة أسبوعية للاعتمادات', 'طرح حزمة أعمال تمهيدية بعقد منفصل', 'الشؤون الفنية', 'العقود والمشتريات', 'open', 2, 3, '2026-10-15', '2026-11-25', null, 'تجاوز أي مرحلة اعتماد لمدتها المحددة بأكثر من أسبوع', ''),
  ('R03', 'مرافق وشبكات', 'التنفيذ', 'موقعي', 'الإشراف والتنسيق', 'مرافق مدفونة غير موثقة في مسارات الحفر', 'خرائط المرافق قديمة وغير محدثة', 'توقف الأعمال وأضرار بالشبكات القائمة', 4, 5, 50, 400000, 'mitigate', 'كشف تجريبي (حفر جسات) قبل الحفر في كل مقطع والتنسيق مع الجهات الخدمية', 'إيقاف المقطع وتحويل الطاقم لمقطع بديل وطلب تحويل المسار', 'الإشراف والتنسيق', 'المقاول', 'in_progress', 2, 4, '2026-06-01', '2026-12-15', null, 'اكتشاف أي خط غير موثق في مقطع سابق', ''),
  ('R04', 'مدارس', 'التنفيذ', 'مالي', 'مكتب المدير', 'تأخر صرف المستخلصات', 'تأخر إجراءات الصرف وشح السيولة', 'تعثر المقاول وتباطؤ وتيرة العمل', 4, 4, 30, 0, 'mitigate', 'متابعة السيولة ومواعيد صرف المستخلصات شهرياً مع اللجنة', 'إعادة جدولة الأعمال غير الحرجة', 'مكتب المدير', 'الشؤون المالية', 'in_progress', 2, 3, '2026-09-16', '2026-11-15', null, 'تجاوز مدة صرف المستخلص 30 يوماً', ''),
  ('R05', 'جسور', 'التنفيذ', 'سلامة', 'الإشراف والتنسيق', 'حادث عمل جسيم أثناء أعمال الرفع والصب', 'قصور إجراءات السلامة والتصاريح', 'إصابات وتوقف الموقع ومسؤولية قانونية', 3, 5, 20, 250000, 'mitigate', 'خطة سلامة معتمدة وتصاريح عمل للأعمال الخطرة وتفتيش أسبوعي', 'إيقاف النشاط والتحقيق وتفعيل خطة الطوارئ', 'الإشراف والتنسيق', 'السلامة المهنية', 'open', 2, 4, '2026-04-10', '2026-06-30', null, 'تكرار مخالفات السلامة في تقارير التفتيش', ''),
  ('R06', 'إسكان', 'التنفيذ', 'توريد', 'الإشراف والتنسيق', 'نقص مواد البناء (حديد التسليح)', 'اضطراب التوريد في السوق المحلي', 'تأخير الأعمال الإنشائية وارتفاع التكلفة', 4, 4, 40, 600000, 'mitigate', 'توريد مبكر للكميات الحرجة واعتماد موردين بديلين', 'إعادة ترتيب الأعمال واعتماد بدائل مكافئة', 'الإشراف والتنسيق', 'المقاول', 'in_progress', 3, 3, '2026-05-20', '2026-11-30', null, 'انخفاض مخزون الموقع عن احتياج أسبوعين', ''),
  ('R07', 'طرق', 'التنفيذ', 'جودة', 'المطابقة والاستلام', 'عدم مطابقة طبقات الرصف للمواصفات', 'قصور الاختبارات أثناء التنفيذ', 'إعادة العمل وتأخير الاستلام', 3, 4, 15, 300000, 'mitigate', 'نقاط فحص مشتركة واختبارات لكل طبقة قبل الطبقة التالية', 'إزالة وإعادة المقاطع غير المطابقة على حساب المقاول', 'المطابقة والاستلام', 'المقاول', 'in_progress', 2, 2, '2026-04-05', '2026-10-31', null, 'نتائج اختبار دمك أقل من المطلوب', ''),
  ('R08', 'مرافق وشبكات', 'التصميم', 'تنسيق', 'الشؤون الفنية', 'تعارض مخططات التخصصات (مياه – صرف – كهرباء)', 'غياب المراجعة التنسيقية بين التخصصات', 'أوامر تغيير وإعادة أعمال', 4, 4, 25, 350000, 'mitigate', 'مراجعة تنسيقية شاملة للمخططات قبل إصدارها للتنفيذ', 'حل التعارض في الموقع بقرار فني موثق', 'الشؤون الفنية', 'الاستشاري', 'open', 2, 2, '2026-09-01', '2026-11-20', null, 'ورود طلبات استيضاح متكررة من المقاول', ''),
  ('R09', 'ترميم مبانٍ تراثية', 'التنفيذ', 'زمني', 'الترميم', 'ضعف أداء المقاول في أعمال الترميم', 'نقص الموارد والعمالة الفنية المتخصصة', 'تجاوز المدة التعاقدية', 4, 4, 90, 0, 'mitigate', 'خطة تعافٍ أسبوعية ملزمة ومتابعة الموارد', 'سحب جزء من الأعمال وإسناده لمقاول آخر وفق العقد', 'الترميم', 'المقاول', 'in_progress', 2, 3, '2026-07-15', '2026-11-15', null, 'SPI أقل من 0.85 لقياسين متتاليين', ''),
  ('R10', 'طرق', 'التنفيذ', 'بيئي', 'الإشراف والتنسيق', 'السيول والأمطار الغزيرة', 'تصريف مؤقت غير كافٍ في الموقع', 'تلف الطبقات المنفذة وتأخير', 3, 4, 15, 200000, 'mitigate', 'حماية الموقع وتنفيذ تصريف مؤقت قبل موسم الأمطار', 'خطة طوارئ لضخ المياه وإصلاح التلف', 'الإشراف والتنسيق', 'المقاول', 'open', 2, 3, '2026-10-20', '2026-11-30', null, 'إنذارات الأرصاد بأمطار غزيرة', ''),
  ('R11', 'فراغات عامة وأحياء', 'التخطيط', 'قانوني', 'مكتب المدير', 'نزاعات ملكية على مسارات الأرصفة', 'عدم حسم حدود الملكيات', 'تعطيل تسليم أجزاء من الموقع', 3, 5, 45, 0, 'avoid', 'تدقيق الملكيات والتنسيق مع الجهات المختصة قبل التسليم', 'تعديل المسار مؤقتاً', 'مكتب المدير', 'الشؤون القانونية', 'closed', 2, 3, '2025-06-10', '2025-09-30', '2026-07-30', 'اعتراض رسمي من أي مالك', ''),
  ('R12', 'متعدد المشاريع', 'المتابعة', 'حوكمة', 'مكتب المدير', 'تقارير إنجاز غير دقيقة', 'ضعف التوثيق والاعتماد على تقارير المقاولين', 'قرارات وصرف مبني على بيانات غير دقيقة', 4, 5, 0, 0, 'mitigate', 'التحقق الميداني الشهري وتوحيد نماذج التقارير', 'تدقيق شامل للمستخلصات السابقة', 'مكتب المدير', 'الإشراف والتنسيق', 'in_progress', 2, 3, '2026-02-01', '2026-12-31', null, 'فرق أكثر من 5% بين نسبة المقاول والتحقق الميداني', ''),
  ('R13', 'إسكان', 'التنفيذ', 'مخلفات الحرب والأمن', 'الإشراف والتنسيق', 'العثور على مخلفات حرب أثناء أعمال الحفر', 'الموقع ضمن منطقة نزاع سابقة دون مسح كامل', 'توقف الأعمال وخطر على العاملين', 3, 5, 15, 0, 'avoid', 'مسح الموقع وتطهيره من الجهة المختصة قبل الحفر واعتماد إجراء إيقاف وإبلاغ', 'إيقاف فوري وإخلاء وإبلاغ الجهة المختصة', 'الإشراف والتنسيق', 'الجهات المختصة', 'in_progress', 1, 5, '2026-10-15', '2026-11-30', null, 'العثور على أي جسم مشبوه في الموقع أو المواقع المجاورة', ''),
  ('R14', 'ترميم مبانٍ تراثية', 'التصميم', 'تراثي وترميم', 'الترميم', 'تدهور إنشائي غير مكتشف في المبنى التراثي', 'غياب المسح الإنشائي التفصيلي قبل الطرح', 'أعمال تدعيم إضافية وأوامر تغيير وتأخير', 4, 4, 60, 650000, 'mitigate', 'مسح إنشائي وتوثيق تفصيلي واعتماد منهجية التدعيم', 'تدعيم مؤقت عاجل وإيقاف الأعمال في الجزء المتأثر', 'الترميم', 'الاستشاري', 'in_progress', 2, 3, '2026-06-25', '2026-12-15', null, 'ظهور تشققات جديدة أو اتساع القائمة', '');

create temporary table pm_v1_desc (code text, descr text);
insert into pm_v1_desc values
  ('R01', 'قصور الدراسات الجيوتقنية'), ('R02', 'تأخر الترسية'), ('R03', 'مرافق مدفونة غير موثقة'), ('R04', 'تأخر المستخلصات'),
  ('R05', 'حادث عمل جسيم'), ('R06', 'نقص مواد البناء'), ('R07', 'عدم مطابقة الرصف'), ('R08', 'تعارض المخططات'),
  ('R09', 'ضعف أداء المقاول'), ('R10', 'السيول والأمطار'), ('R11', 'نزاعات ملكية'), ('R12', 'تقارير إنجاز غير دقيقة');

update public.risks r set
  project_group = v.grp, phase = v.phase, category = v.cat, department = v.dept, description = v.descr, cause = v.cause,
  effect = v.effect, probability = v.p, impact = v.i, time_impact_days = v.days, cost_impact = v.cost, response = v.resp,
  mitigation = v.mitig, contingency = v.cont, owner = v.owner, executor = v.exec, status = v.status,
  residual_probability = v.tp, residual_impact = v.ti, registered_on = v.reg, target_date = v.target, closed_on = v.closed,
  next_review = null, early_warning = v.warn, notes = v.notes, updated_at = now()
from pm_v2_risks v join pm_v1_desc o on o.code = v.code
where r.code = v.code and r.created_by is null and r.updated_by is null and r.description in (o.descr, v.descr)
  and (r.description, r.department, r.cost_impact) is distinct from (v.descr, v.dept, v.cost);

-- الخطران الجديدان (برمزيهما إن كانا متاحين، وإلا بالرمز التالي)
do $$
declare
  v      record;
  v_code text;
begin
  for v in select * from pm_v2_risks t where t.code not in (select o.code from pm_v1_desc o) order by t.code loop
    if exists (select 1 from public.risks where description = v.descr) then
      continue;
    end if;
    v_code := v.code;
    if exists (select 1 from public.risks r where r.code = v_code) then
      select 'R' || lpad((coalesce(max(substring(r.code from 2)::integer), 0) + 1)::text, 2, '0') into v_code
        from public.risks r where r.code ~ '^R[0-9]+$';
    end if;
    insert into public.risks (code, project_group, phase, category, department, description, cause, effect, probability, impact,
                              time_impact_days, cost_impact, response, mitigation, contingency, owner, executor, status,
                              residual_probability, residual_impact, registered_on, target_date, closed_on, early_warning, notes)
    values (v_code, v.grp, v.phase, v.cat, v.dept, v.descr, v.cause, v.effect, v.p, v.i, v.days, v.cost, v.resp, v.mitig, v.cont,
            v.owner, v.exec, v.status, v.tp, v.ti, v.reg, v.target, v.closed, v.warn, v.notes);
  end loop;
end $$;

insert into public.risk_reviews (risk_id, reviewed_on, probability, impact, actions_done, progress, reviewer, notes)
select r.id, x.d::date, x.p, x.i, x.done, x.pct, x.rev, x.notes
from (values
  ('R01', '2026-07-05', 4, 5, 'بدء أعمال الجسات التكميلية', 0.3, 'الشؤون الفنية', ''),
  ('R03', '2026-07-25', 4, 5, 'كشف تجريبي في 40% من المسارات', 0.4, 'الإشراف والتنسيق', ''),
  ('R11', '2026-07-30', 1, 3, 'حسم النزاع وتسليم كامل الموقع واكتمال الأعمال', 1, 'مكتب المدير', ''),
  ('R01', '2026-08-20', 3, 4, 'استكمال الجسات واعتماد تعديل الأساسات (التغيير C09)', 0.8, 'الشؤون الفنية', ''),
  ('R06', '2026-08-28', 4, 4, 'التعاقد مع مورد بديل', 0.4, 'الإشراف والتنسيق', ''),
  ('R09', '2026-08-30', 4, 4, 'إنذار أول للمقاول وطلب خطة تعافٍ', 0.2, 'الترميم', ''),
  ('R07', '2026-09-10', 2, 4, 'تطبيق نقاط الفحص المشتركة لكل طبقة', 0.9, 'المطابقة والاستلام', ''),
  ('R04', '2026-09-20', 4, 4, 'مخاطبة اللجنة بشأن جدول السيولة', 0.3, 'مكتب المدير', ''),
  ('R12', '2026-09-25', 3, 5, 'بدء التحقق الميداني الشهري', 0.5, 'مكتب المدير', ''),
  ('R14', '2026-10-12', 4, 4, 'تنفيذ مسح إنشائي جزئي', 0.4, 'الترميم', ''),
  ('R01', '2026-10-15', 3, 4, 'متابعة تنفيذ الأساسات المعدّلة', 0.9, 'الشؤون الفنية', ''),
  ('R04', '2026-10-18', 3, 4, 'صرف جزئي للمستخلص رقم 4', 0.6, 'مكتب المدير', ''),
  ('R09', '2026-10-20', 5, 4, 'عدم الالتزام بخطة التعافي – يوصى بالتصعيد للجنة', 0.3, 'الترميم', ''),
  ('R12', '2026-10-20', 3, 5, 'توحيد نموذج التقرير الشهري', 0.6, 'مكتب المدير', ''),
  ('R14', '2026-10-22', 4, 4, 'منهجية التدعيم قيد الدراسة لدى الاستشاري', 0.5, 'الترميم', ''),
  ('R13', '2026-10-22', 3, 5, 'طلب مسح من الجهة المختصة لبقية الموقع', 0.3, 'الإشراف والتنسيق', ''),
  ('R03', '2026-10-25', 4, 5, 'اكتشاف خط رئيسي إضافي واستمرار الكشف', 0.6, 'الإشراف والتنسيق', ''),
  ('R06', '2026-10-27', 5, 4, 'استمرار نقص الحديد في السوق المحلي', 0.5, 'الإشراف والتنسيق', '')
) x(code, d, p, i, done, pct, rev, notes)
join pm_v2_risks v on v.code = x.code
join public.risks r on r.description = v.descr and r.created_by is null and r.updated_by is null
where not exists (select 1 from public.risk_reviews rr where rr.risk_id = r.id);

drop table if exists pm_v2_risks;
drop table if exists pm_v1_desc;
