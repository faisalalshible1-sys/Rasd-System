-- =====================================================================
-- خيار «لا ينطبق» للضمان الابتدائي ولتكليف المهندسين (مهندس السلامة)، وتصحيحات دمج الأعمال في العقود
-- مستقل عن الملفين 16 و17: يُطبَّق على قاعدة فيها 1–15 أو 1–17، ويمكن إعادة تشغيله دون ضرر.
--
--  1. projects.guarantee_initial_na: الضمان الابتدائي لا ينطبق على العقد (لا يُحسب ولا يدخل في المجاميع)
--     وإن انطبق فهو كما كان: النسبة × قيمة الأعمال المنفذة
--  2. set_guarantee_initial_na(): يحدّده من يختص بالبيانات المالية للعقد، ويُسجَّل في سجل التعديلات المالية
--  3. «مهندس لا ينطبق» = نموذج التكليف المقابل حالته «لا ينطبق» في الدورة المستندية:
--     - لا يُكلَّف مهندس من هذا النوع ما دامت الحالة «لا ينطبق»
--     - ولا تُسجَّل الحالة «لا ينطبق» وفي العقد مهندسون مكلّفون من هذا النوع
--     - الخانة النصية القديمة (eng_saf وغيرها) تُظهر «لا ينطبق» للتصدير وللنسخ السابقة
--  4. الدمج: العقد المستهدف يحتفظ بخياراته (الضمان الابتدائي)، وإن دُمج فيه عمل له مهندس مكلّف من نوع
--     مسجّل «لا ينطبق» في العقد عاد النموذج إلى «قيد الإنجاز» بدل أن يفشل الدمج أو يبقى متناقضاً
--  5. الدمج المتسلسل (دمج عقد فيه أعمال مدمجة): الدفعات اليدوية لا تُطرح مرتين عند فك الدمج
--  6. ملاحظات التقييم تعود مع العمل عند فك الدمج
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. الضمان الابتدائي: ينطبق / لا ينطبق
-- ---------------------------------------------------------------------
alter table public.projects add column if not exists guarantee_initial_na boolean not null default false;
comment on column public.projects.guarantee_initial_na is 'الضمان الابتدائي لا ينطبق على هذا العقد';

create or replace function public.projects_finance_calc()
returns trigger
language plpgsql security definer set search_path = public
as $$
begin
  if tg_op = 'UPDATE' and current_setting('app.trusted', true) is distinct from 'on' then
    new.value_source      := old.value_source;
    new.executed_source   := old.executed_source;
    new.variations_net    := old.variations_net;
    new.extracts_count    := old.extracts_count;
    new.extracts_gross    := old.extracts_gross;
    new.extracts_net      := old.extracts_net;
    new.extracts_paid     := old.extracts_paid;
    new.retention_held    := old.retention_held;
    new.advance_amount    := old.advance_amount;
    new.advance_paid_on   := old.advance_paid_on;
    new.advance_recovered := old.advance_recovered;
    if old.value_source = 'items' then
      new.contract_value := old.contract_value;
    end if;
    if old.executed_source <> 'manual' then
      new.executed_value := old.executed_value;
    end if;
  end if;
  if new.guarantee_initial_na then
    new.guarantee_initial := null;
  else
    new.guarantee_initial := round(new.executed_value * public.setting_num('finance.guarantee_initial_rate', 0.05), 3);
  end if;
  new.guarantee_final := round(new.executed_value * public.setting_num('finance.guarantee_final_rate', 0.02), 3);
  if tg_op = 'UPDATE' and new.extra is distinct from old.extra
     and current_setting('app.trusted', true) is distinct from 'on'
     and auth.uid() is not null and not public.is_director() then
    raise exception 'تُعدَّل الحقول الإضافية من صفحة المشروع' using errcode = '42501';
  end if;
  if tg_op = 'UPDATE' and (new.contract_no is distinct from old.contract_no or new.merged_into is distinct from old.merged_into)
     and current_setting('app.trusted', true) is distinct from 'on' and auth.uid() is not null then
    raise exception 'رقم العقد والدمج من صلاحية مكتب العقود عبر صفحة العقد' using errcode = '42501';
  end if;
  return new;
end;
$$;

-- ---------------------------------------------------------------------
-- 2. تحديد انطباق الضمان الابتدائي
-- ---------------------------------------------------------------------
create or replace function public.set_guarantee_initial_na(p_project uuid, p_na boolean)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  v_old    boolean;
  v_amount numeric;
begin
  if not public.can_edit_form(p_project, 'f01') then
    raise exception 'البيانات المالية للعقد يحدّثها من يختص بـ«أمر تعاقد»' using errcode = '42501';
  end if;
  if not public.writes_allowed() then
    raise exception 'المنظومة مجمّدة حالياً (قراءة فقط)' using errcode = '42501';
  end if;
  if p_na is null then
    raise exception 'حدّد هل ينطبق الضمان الابتدائي على العقد' using errcode = '22023';
  end if;
  select guarantee_initial_na, guarantee_initial into v_old, v_amount
    from public.projects where id = p_project and merged_into is null for update;
  if not found then
    raise exception 'العقد غير موجود' using errcode = '22023';
  end if;
  if v_old = p_na then
    return;
  end if;
  update public.projects set guarantee_initial_na = p_na where id = p_project
  returning guarantee_initial into v_amount;
  perform public.write_audit('finance.guarantee_initial', p_project, null,
    jsonb_build_object('na', p_na, 'amount', v_amount));
end;
$$;

-- ---------------------------------------------------------------------
-- 3. تكليف المهندسين: «لا ينطبق» هو حالة نموذج التكليف المقابل
-- ---------------------------------------------------------------------
create or replace function public.engineer_na(p_project uuid, p_kind text)
returns boolean
language sql stable security definer set search_path = public
as $$
  select exists (select 1 from public.project_forms f
                  where f.project_id = p_project and f.status = 'na'
                    and f.form_key = public.engineer_form(p_kind))
$$;

create or replace function public.sync_engineer_names(p_project uuid)
returns void
language plpgsql security definer set search_path = public
as $$
begin
  perform set_config('app.eng_sync', 'on', true);
  update public.projects p
     set eng_sup = coalesce((select string_agg(name, '، ' order by sort, created_at) from public.contract_engineers
                              where project_id = p.id and kind = 'sup'),
                            case when public.engineer_na(p.id, 'sup') then 'لا ينطبق' else '' end),
         eng_qty = coalesce((select string_agg(name, '، ' order by sort, created_at) from public.contract_engineers
                              where project_id = p.id and kind = 'qty'),
                            case when public.engineer_na(p.id, 'qty') then 'لا ينطبق' else '' end),
         eng_fol = coalesce((select string_agg(name, '، ' order by sort, created_at) from public.contract_engineers
                              where project_id = p.id and kind = 'fol'),
                            case when public.engineer_na(p.id, 'fol') then 'لا ينطبق' else '' end),
         eng_saf = coalesce((select string_agg(name, '، ' order by sort, created_at) from public.contract_engineers
                              where project_id = p.id and kind = 'saf'),
                            case when public.engineer_na(p.id, 'saf') then 'لا ينطبق' else '' end)
   where p.id = p_project;
  perform set_config('app.eng_sync', 'off', true);
end;
$$;

-- لا يُكلَّف مهندس من نوع مسجّل «لا ينطبق» في العقد. في الدمج وفكّه (app.trusted) يعود النموذج إلى «قيد الإنجاز»
create or replace function public.contract_engineers_na_guard()
returns trigger
language plpgsql security definer set search_path = public
as $$
declare
  f text;
begin
  if tg_op = 'UPDATE' and new.project_id = old.project_id and new.kind = old.kind then
    return new;
  end if;
  f := public.engineer_form(new.kind);
  if f is null or not public.engineer_na(new.project_id, new.kind) then
    return new;
  end if;
  if current_setting('app.trusted', true) = 'on' then
    update public.project_forms
       set status = 'wip', updated_at = now(), updated_by = auth.uid(), approved_by = null
     where project_id = new.project_id and form_key = f and status = 'na';
    perform public.write_audit('form.set', new.project_id, f,
      jsonb_build_object('from', 'na', 'to', 'wip', 'reason', 'دُمج في العقد عمل له تكليف قائم'));
    return new;
  end if;
  raise exception '«%» مسجّل «لا ينطبق» على هذا العقد. غيّر حالته أولاً ثم كلّف المهندس',
    (select name from public.form_defs where key = f) using errcode = '22023';
end;
$$;
drop trigger if exists contract_engineers_na_guard on public.contract_engineers;
create trigger contract_engineers_na_guard
  before insert or update of project_id, kind on public.contract_engineers
  for each row execute function public.contract_engineers_na_guard();

-- لا تُسجَّل «لا ينطبق» لنموذج تكليف وفي العقد مهندسون مكلّفون به. في الدمج تبقى حالة العقد كما هي
create or replace function public.project_forms_na_guard()
returns trigger
language plpgsql security definer set search_path = public
as $$
declare
  v_kind text;
begin
  if new.status <> 'na' or (tg_op = 'UPDATE' and old.status = 'na') then
    return new;
  end if;
  select substring(d.engineer_field from 5) into v_kind from public.form_defs d where d.key = new.form_key;
  if v_kind is null or public.engineer_form(v_kind) is distinct from new.form_key
     or not exists (select 1 from public.contract_engineers e where e.project_id = new.project_id and e.kind = v_kind) then
    return new;
  end if;
  if current_setting('app.trusted', true) = 'on' then
    if tg_op = 'UPDATE' then
      return old;
    end if;
    return null;
  end if;
  raise exception 'في العقد مهندسون مكلّفون في «%». ألغِ تكليفاتهم أولاً ثم سجّله «لا ينطبق»',
    (select name from public.form_defs where key = new.form_key) using errcode = '22023';
end;
$$;
drop trigger if exists project_forms_na_guard on public.project_forms;
create trigger project_forms_na_guard
  before insert or update of status on public.project_forms
  for each row execute function public.project_forms_na_guard();

-- الخانات النصية القديمة تتبع تغيّر «لا ينطبق»
create or replace function public.project_forms_engineer_sync()
returns trigger
language plpgsql security definer set search_path = public
as $$
declare
  v_kind text;
begin
  if not ((tg_op = 'INSERT' and new.status = 'na')
          or (tg_op = 'UPDATE' and (old.status = 'na') <> (new.status = 'na'))) then
    return null;
  end if;
  select substring(d.engineer_field from 5) into v_kind from public.form_defs d where d.key = new.form_key;
  if v_kind is not null and public.engineer_form(v_kind) = new.form_key then
    perform public.sync_engineer_names(new.project_id);
  end if;
  return null;
end;
$$;
drop trigger if exists project_forms_engineer_sync on public.project_forms;
create trigger project_forms_engineer_sync
  after insert or update of status on public.project_forms
  for each row execute function public.project_forms_engineer_sync();

-- العقود المسجّل فيها تكليف «لا ينطبق» الآن
do $$
declare
  r record;
begin
  for r in select distinct f.project_id
             from public.project_forms f join public.form_defs d on d.key = f.form_key
            where f.status = 'na' and d.engineer_field is not null loop
    perform public.sync_engineer_names(r.project_id);
  end loop;
end $$;

-- ---------------------------------------------------------------------
-- 4–6. الدمج وفكّه
-- ---------------------------------------------------------------------
alter table public.quality_notes
  add column if not exists origin_project uuid references public.projects(id) on delete set null;
create index if not exists quality_notes_origin_idx on public.quality_notes (origin_project);

-- الملاحظة الجديدة تُنسب إلى عقدها دائماً؛ الأصل يحدده الدمج وحده
create or replace function public.quality_notes_audit()
returns trigger
language plpgsql security definer set search_path = public
as $$
begin
  new.author := auth.uid();
  new.created_at := now();
  new.origin_project := null;
  return new;
end;
$$;

create or replace function public.merge_contracts(p_target uuid, p_sources uuid[])
returns integer
language plpgsql security definer set search_path = public
as $$
declare
  t      public.projects;
  s      public.projects;
  v_src  uuid;
  n      integer := 0;
  v_info jsonb := '[]'::jsonb;
  c1     numeric;
  c2     numeric;
  c3     numeric;
  cd     numeric;
begin
  select * into t from public.projects where id = p_target and merged_into is null for update;
  if not found then
    raise exception 'العقد المستهدف غير موجود' using errcode = '22023';
  end if;
  if not public.has_token(p_target, array['contracts']) then
    raise exception 'دمج الأعمال في العقود من صلاحية مكتب العقود' using errcode = '42501';
  end if;
  if coalesce(array_length(p_sources, 1), 0) = 0 then
    raise exception 'اختر الأعمال المراد دمجها' using errcode = '22023';
  end if;

  perform set_config('app.trusted', 'on', true);
  perform public.materialize_finance(p_target);
  foreach v_src in array p_sources loop
    if v_src = p_target then
      continue;
    end if;
    select * into s from public.projects where id = v_src and merged_into is null for update;
    if not found then
      raise exception 'أحد الأعمال المختارة غير موجود أو مدمج من قبل' using errcode = '22023';
    end if;
    if not public.has_token(v_src, array['contracts']) then
      raise exception 'دمج الأعمال في العقود من صلاحية مكتب العقود' using errcode = '42501';
    end if;
    perform public.materialize_finance(v_src);
    perform set_config('app.trusted', 'on', true);

    update public.contract_works set project_id = p_target, origin_project = coalesce(origin_project, v_src),
           sort = sort + (select coalesce(max(sort), 0) from public.contract_works where project_id = p_target)
     where project_id = v_src;
    update public.contract_engineers set project_id = p_target, origin_project = coalesce(origin_project, v_src),
           sort = sort + (select coalesce(max(sort), 0) from public.contract_engineers where project_id = p_target)
     where project_id = v_src;
    update public.contract_variations set project_id = p_target, origin_project = coalesce(origin_project, v_src)
     where project_id = v_src;
    update public.contract_extracts set project_id = p_target, origin_project = coalesce(origin_project, v_src),
           seq = seq + (select coalesce(max(seq), 0) from public.contract_extracts where project_id = p_target)
     where project_id = v_src;

    -- دمج متسلسل: الأعمال المدمجة سابقاً في المصدر تنتقل إلى العقد مباشرة، ودفعاتها اليدوية
    -- (المجموعة في صف المصدر) تُطرح من صف المصدر بعد نقلها، حتى لا تُطرح مرتين عند فك الدمج
    select sum(payment_first), sum(payment_second), sum(payment_final), sum(deductions)
      into c1, c2, c3, cd
      from public.projects where merged_into = v_src;
    update public.projects set merged_into = p_target where merged_into = v_src;

    insert into public.project_forms as pf (project_id, form_key, status, updated_at, updated_by, approved_by)
    select p_target, f.form_key, f.status, now(), auth.uid(), f.approved_by
      from public.project_forms f
     where f.project_id = v_src and f.status <> 'todo'
    on conflict (project_id, form_key) do update
       set status = excluded.status, updated_at = excluded.updated_at, updated_by = excluded.updated_by,
           approved_by = excluded.approved_by
     where pf.status = 'todo';

    update public.change_requests c set project_id = p_target
     where c.project_id = v_src and c.state = 'pending'
       and not exists (select 1 from public.change_requests x
                        where x.project_id = p_target and x.form_key = c.form_key and x.state = 'pending');
    update public.change_requests set state = 'withdrawn', decided_at = now(),
           decision_note = 'سُحب عند دمج العمل في عقد'
     where project_id = v_src and state = 'pending';

    update public.quality_notes set project_id = p_target, origin_project = coalesce(origin_project, v_src)
     where project_id = v_src;
    update public.notifications set project_id = p_target where project_id = v_src;

    -- الدفعات والخصومات المسجلة يدوياً تُجمع، وبقية القيم تُحسب من البنود والمستخلصات.
    -- خيار «الضمان الابتدائي لا ينطبق» يبقى للعقد المستهدف.
    update public.projects set
      payment_first  = case when payment_first is null and s.payment_first is null then null
                            else coalesce(payment_first, 0) + coalesce(s.payment_first, 0) end,
      payment_second = case when payment_second is null and s.payment_second is null then null
                            else coalesce(payment_second, 0) + coalesce(s.payment_second, 0) end,
      payment_final  = case when payment_final is null and s.payment_final is null then null
                            else coalesce(payment_final, 0) + coalesce(s.payment_final, 0) end,
      deductions     = case when deductions is null and s.deductions is null then null
                            else coalesce(deductions, 0) + coalesce(s.deductions, 0) end,
      contract_no    = coalesce(contract_no, s.contract_no)
     where id = p_target;

    update public.projects set merged_into = p_target, merged_at = now(),
      payment_first  = case when c1 is null then payment_first  else greatest(coalesce(payment_first, 0)  - c1, 0) end,
      payment_second = case when c2 is null then payment_second else greatest(coalesce(payment_second, 0) - c2, 0) end,
      payment_final  = case when c3 is null then payment_final  else greatest(coalesce(payment_final, 0)  - c3, 0) end,
      deductions     = case when cd is null then deductions     else greatest(coalesce(deductions, 0)     - cd, 0) end
     where id = v_src;
    perform public.write_audit('contract.merged_into', v_src, null,
      jsonb_build_object('target', p_target, 'target_label', public.project_label(p_target)));
    v_info := v_info || jsonb_build_object('id', s.id, 'assign_no', s.assign_no, 'contract_no', s.contract_no,
                                           'name', s.name, 'company', s.company);
    n := n + 1;
  end loop;
  perform public.sync_engineer_names(p_target);
  perform public.recalc_contract_finance(p_target);
  perform set_config('app.trusted', 'off', true);

  if n > 0 then
    update public.projects set updated_at = now(), updated_by = auth.uid() where id = p_target;
    perform public.write_audit('contract.merge', p_target, null, jsonb_build_object('sources', v_info, 'count', n));
  end if;
  return n;
end;
$$;

create or replace function public.unmerge_contract(p_source uuid)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  s public.projects;
  t uuid;
begin
  if not public.is_director() then
    raise exception 'فك الدمج من صلاحية مدير المكتب' using errcode = '42501';
  end if;
  select * into s from public.projects where id = p_source for update;
  if not found or s.merged_into is null then
    raise exception 'هذا العمل غير مدمج' using errcode = '22023';
  end if;
  t := s.merged_into;
  perform set_config('app.trusted', 'on', true);
  update public.contract_works set project_id = p_source where project_id = t and origin_project = p_source;
  update public.contract_engineers set project_id = p_source where project_id = t and origin_project = p_source;
  update public.contract_variations set project_id = p_source where project_id = t and origin_project = p_source;
  update public.contract_extracts set project_id = p_source where project_id = t and origin_project = p_source;
  update public.quality_notes set project_id = p_source, origin_project = null
   where project_id = t and origin_project = p_source;
  -- أرقام مستخلصات العمل العائد تبدأ من 1 من جديد
  update public.contract_extracts x set seq = r.n
    from (select id, row_number() over (order by seq, created_at) as n
            from public.contract_extracts where project_id = p_source) r
   where x.id = r.id and x.seq <> r.n;
  perform set_config('app.trusted', 'on', true);
  update public.projects set
    payment_first  = case when s.payment_first  is null then payment_first  else greatest(coalesce(payment_first, 0)  - s.payment_first, 0) end,
    payment_second = case when s.payment_second is null then payment_second else greatest(coalesce(payment_second, 0) - s.payment_second, 0) end,
    payment_final  = case when s.payment_final  is null then payment_final  else greatest(coalesce(payment_final, 0)  - s.payment_final, 0) end,
    deductions     = case when s.deductions     is null then deductions     else greatest(coalesce(deductions, 0)     - s.deductions, 0) end
   where id = t;
  update public.projects set merged_into = null, merged_at = null,
         contract_no = case when exists (select 1 from public.projects x where x.contract_no = s.contract_no
                                          and x.merged_into is null and x.id <> p_source) then null else contract_no end
   where id = p_source;
  perform public.sync_engineer_names(t);
  perform public.sync_engineer_names(p_source);
  perform public.recalc_contract_finance(t);
  perform public.recalc_contract_finance(p_source);
  perform set_config('app.trusted', 'off', true);
  perform public.write_audit('contract.unmerge', t, null,
    jsonb_build_object('source', p_source, 'source_label', public.project_label(p_source)));
end;
$$;

-- ---------------------------------------------------------------------
-- الصلاحيات
-- ---------------------------------------------------------------------
revoke execute on function
  public.contract_engineers_na_guard(), public.project_forms_na_guard(), public.project_forms_engineer_sync(),
  public.quality_notes_audit(), public.projects_finance_calc(), public.sync_engineer_names(uuid),
  public.engineer_na(uuid, text)
from public, anon, authenticated;

revoke execute on function
  public.set_guarantee_initial_na(uuid, boolean), public.merge_contracts(uuid, uuid[]), public.unmerge_contract(uuid)
from public, anon;
grant execute on function
  public.set_guarantee_initial_na(uuid, boolean), public.merge_contracts(uuid, uuid[]), public.unmerge_contract(uuid)
to authenticated;

notify pgrst, 'reload schema';

select 'تم: «لا ينطبق» للضمان الابتدائي ولتكليف المهندسين، وتصحيحات الدمج' as result;
