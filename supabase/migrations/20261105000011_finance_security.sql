-- =====================================================================
--  المالية الموسعة والأمان الموسع:
--    1. قيم البنود: لكل عمل في العقد قيمته التعاقدية والمنفذة.
--    2. أوامر التغيير: زيادة أو نقص على قيمة العقد، برقمها وتاريخ اعتمادها.
--    3. المستخلصات: رقم، فترة، قيمة الأعمال، الاستقطاعات (تأمين محتجز، استرداد دفعة
--       مقدمة، غرامات، ضرائب، أخرى)، الصافي، الحالة، المدفوع وتاريخه.
--    4. مجاميع العقد تُحسب آلياً من البنود والمستخلصات وأوامر التغيير، وكل تعديل مالي
--       يُسجَّل في سجل التدقيق.
--    5. سجل الأجهزة (توثيق الجهاز بموافقة المستخدم)، وقفل الدخول مؤقتاً، وحظر جهاز،
--       وإجراءات CISO الأمنية، والحركة الدقيقة للحسابات، والتنبيهات.
--    6. إعداد المظهر (ui.appearance)، وتوسيع ملخص مساعد Claude.
--  يُشغَّل بعد 20261102000010_contracts.sql. إعادة تشغيله آمنة.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. قيم البنود ومجاميع العقد
-- ---------------------------------------------------------------------
alter table public.contract_works
  add column if not exists contract_value numeric(16, 3) check (contract_value >= 0),
  add column if not exists executed_value numeric(16, 3) check (executed_value >= 0);

alter table public.projects
  add column if not exists value_source    text not null default 'manual',
  add column if not exists executed_source text not null default 'manual',
  add column if not exists variations_net  numeric(16, 3) not null default 0,
  add column if not exists extracts_count  integer not null default 0,
  add column if not exists extracts_gross  numeric(16, 3) not null default 0,
  add column if not exists extracts_net    numeric(16, 3) not null default 0,
  add column if not exists extracts_paid   numeric(16, 3) not null default 0,
  add column if not exists retention_held  numeric(16, 3) not null default 0;

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'projects_value_source_chk') then
    alter table public.projects add constraint projects_value_source_chk check (value_source in ('manual', 'items'));
  end if;
  if not exists (select 1 from pg_constraint where conname = 'projects_executed_source_chk') then
    alter table public.projects add constraint projects_executed_source_chk
      check (executed_source in ('manual', 'items', 'extracts'));
  end if;
end $$;

-- ---------------------------------------------------------------------
-- 2. أوامر التغيير
-- ---------------------------------------------------------------------
create table if not exists public.contract_variations (
  id             uuid primary key default gen_random_uuid(),
  project_id     uuid not null references public.projects (id) on delete cascade,
  origin_project uuid references public.projects (id) on delete set null,
  work_id        uuid references public.contract_works (id) on delete set null,
  ref_no         text not null default '' check (length(ref_no) <= 40),
  title          text not null check (length(btrim(title)) between 2 and 300),
  kind           text not null check (kind in ('add', 'deduct')),
  amount         numeric(16, 3) not null check (amount > 0),
  approved_on    date,
  notes          text not null default '' check (length(notes) <= 2000),
  created_at     timestamptz not null default now(),
  created_by     uuid references public.profiles (id) on delete set null
);
create index if not exists contract_variations_project_idx on public.contract_variations (project_id, approved_on);

-- ---------------------------------------------------------------------
-- 3. المستخلصات
-- ---------------------------------------------------------------------
create table if not exists public.contract_extracts (
  id               uuid primary key default gen_random_uuid(),
  project_id       uuid not null references public.projects (id) on delete cascade,
  origin_project   uuid references public.projects (id) on delete set null,
  work_id          uuid references public.contract_works (id) on delete set null,
  seq              integer not null default 0,
  ref_no           text not null default '' check (length(ref_no) <= 40),
  kind             text not null default 'interim' check (kind in ('interim', 'final')),
  period_from      date,
  period_to        date,
  submitted_on     date,
  gross_amount     numeric(16, 3) not null check (gross_amount >= 0),
  retention        numeric(16, 3) not null default 0 check (retention >= 0),
  advance_recovery numeric(16, 3) not null default 0 check (advance_recovery >= 0),
  penalties        numeric(16, 3) not null default 0 check (penalties >= 0),
  taxes            numeric(16, 3) not null default 0 check (taxes >= 0),
  other_deductions numeric(16, 3) not null default 0 check (other_deductions >= 0),
  net_amount       numeric(16, 3) generated always as
                     (gross_amount - retention - advance_recovery - penalties - taxes - other_deductions) stored,
  status           text not null default 'submitted' check (status in ('draft', 'submitted', 'approved', 'paid', 'rejected')),
  approved_on      date,
  paid_amount      numeric(16, 3) not null default 0 check (paid_amount >= 0),
  paid_on          date,
  notes            text not null default '' check (length(notes) <= 2000),
  created_at       timestamptz not null default now(),
  created_by       uuid references public.profiles (id) on delete set null,
  updated_at       timestamptz not null default now(),
  updated_by       uuid references public.profiles (id) on delete set null,
  constraint contract_extracts_deductions check
    (retention + advance_recovery + penalties + taxes + other_deductions <= gross_amount),
  constraint contract_extracts_paid check
    (paid_amount <= gross_amount - retention - advance_recovery - penalties - taxes - other_deductions),
  constraint contract_extracts_period check (period_from is null or period_to is null or period_from <= period_to)
);
create index if not exists contract_extracts_project_idx on public.contract_extracts (project_id, seq);

-- ---------------------------------------------------------------------
-- 4. الحساب الآلي لمجاميع العقد
--    القيمة التعاقدية: مجموع قيم البنود إن أُدخلت، وإلا القيمة اليدوية للعقد.
--    قيمة الأعمال المنفذة: مجموع المستخلصات المعتمدة والمدفوعة إن وُجدت، وإلا مجموع
--    المنفذ في البنود، وإلا القيمة اليدوية. والضمانان يتبعانها (5% و2%).
-- ---------------------------------------------------------------------
create or replace function public.recalc_contract_finance(p_project uuid)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  v_cv   numeric; n_cv integer;
  v_ev   numeric; n_ev integer;
  v_var  numeric;
  n_ext  integer;
  v_eg   numeric; v_en numeric; v_paid numeric; v_ret numeric;
  v_trusted text := coalesce(current_setting('app.trusted', true), '');
  v_recalc  text := coalesce(current_setting('app.recalc', true), '');
begin
  if p_project is null then
    return;
  end if;
  select sum(contract_value), count(contract_value), sum(executed_value), count(executed_value)
    into v_cv, n_cv, v_ev, n_ev
    from public.contract_works where project_id = p_project;
  select coalesce(sum(case when kind = 'add' then amount else -amount end), 0)
    into v_var from public.contract_variations where project_id = p_project;
  select count(*), coalesce(sum(gross_amount), 0), coalesce(sum(net_amount), 0),
         coalesce(sum(paid_amount), 0), coalesce(sum(retention), 0)
    into n_ext, v_eg, v_en, v_paid, v_ret
    from public.contract_extracts where project_id = p_project and status in ('approved', 'paid');

  -- حساب داخلي: لا يغيّر «آخر تحديث» ولا يكتب project.update (التعديل المالي نفسه يُسجَّل بـ finance.*)
  perform set_config('app.trusted', 'on', true);
  perform set_config('app.recalc', 'on', true);
  update public.projects set
    value_source    = case when n_cv > 0 then 'items' else 'manual' end,
    contract_value  = case when n_cv > 0 then v_cv else contract_value end,
    executed_source = case when n_ext > 0 then 'extracts' when n_ev > 0 then 'items' else 'manual' end,
    executed_value  = case when n_ext > 0 then v_eg when n_ev > 0 then v_ev else executed_value end,
    variations_net  = v_var,
    extracts_count  = n_ext,
    extracts_gross  = v_eg,
    extracts_net    = v_en,
    extracts_paid   = v_paid,
    retention_held  = v_ret
   where id = p_project
     and (value_source, contract_value, executed_source, executed_value, variations_net, extracts_count,
          extracts_gross, extracts_net, extracts_paid, retention_held)
         is distinct from
         (case when n_cv > 0 then 'items' else 'manual' end,
          case when n_cv > 0 then v_cv else contract_value end,
          case when n_ext > 0 then 'extracts' when n_ev > 0 then 'items' else 'manual' end,
          case when n_ext > 0 then v_eg when n_ev > 0 then v_ev else executed_value end,
          v_var, n_ext, v_eg, v_en, v_paid, v_ret);
  perform set_config('app.trusted', v_trusted, true);
  perform set_config('app.recalc', v_recalc, true);
end;
$$;

-- القيم المحسوبة لا تُعدَّل يدوياً: القيمة التعاقدية مع البنود، والمنفذ مع البنود أو المستخلصات
create or replace function public.projects_finance_calc()
returns trigger
language plpgsql security definer set search_path = public
as $$
begin
  if tg_op = 'UPDATE' and current_setting('app.trusted', true) is distinct from 'on' then
    new.value_source    := old.value_source;
    new.executed_source := old.executed_source;
    new.variations_net  := old.variations_net;
    new.extracts_count  := old.extracts_count;
    new.extracts_gross  := old.extracts_gross;
    new.extracts_net    := old.extracts_net;
    new.extracts_paid   := old.extracts_paid;
    new.retention_held  := old.retention_held;
    if old.value_source = 'items' then
      new.contract_value := old.contract_value;
    end if;
    if old.executed_source <> 'manual' then
      new.executed_value := old.executed_value;
    end if;
  end if;
  new.guarantee_initial := round(new.executed_value * public.setting_num('finance.guarantee_initial_rate', 0.05), 3);
  new.guarantee_final   := round(new.executed_value * public.setting_num('finance.guarantee_final_rate', 0.02), 3);
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

create or replace function public.finance_children_after()
returns trigger
language plpgsql security definer set search_path = public
as $$
begin
  if tg_op in ('UPDATE', 'DELETE') then
    perform public.recalc_contract_finance(old.project_id);
  end if;
  if tg_op = 'INSERT' or (tg_op = 'UPDATE' and new.project_id is distinct from old.project_id) then
    perform public.recalc_contract_finance(new.project_id);
  end if;
  return null;
end;
$$;

drop trigger if exists contract_works_finance on public.contract_works;
create trigger contract_works_finance
  after insert or delete or update of project_id, contract_value, executed_value on public.contract_works
  for each row execute function public.finance_children_after();
drop trigger if exists contract_variations_finance on public.contract_variations;
create trigger contract_variations_finance
  after insert or update or delete on public.contract_variations
  for each row execute function public.finance_children_after();
drop trigger if exists contract_extracts_finance on public.contract_extracts;
create trigger contract_extracts_finance
  after insert or update or delete on public.contract_extracts
  for each row execute function public.finance_children_after();

-- قيم العقد اليدوية تنتقل إلى بنده الأول قبل الدمج حتى لا تضيع ولا تتكرر
create or replace function public.materialize_finance(p_project uuid)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  p      public.projects;
  v_work uuid;
begin
  select * into p from public.projects where id = p_project;
  if not found or (p.contract_value is null and p.executed_value is null) then
    return;
  end if;
  select id into v_work from public.contract_works where project_id = p_project order by sort, created_at limit 1;
  if v_work is null then
    insert into public.contract_works (project_id, origin_project, title, company, ref_no, sort)
    values (p_project, p_project, coalesce(nullif(btrim(p.name), ''), 'العمل الأساسي'), p.company, coalesce(p.assign_no, ''), 1)
    returning id into v_work;
  end if;
  if p.value_source = 'manual' and p.contract_value is not null then
    update public.contract_works set contract_value = p.contract_value where id = v_work;
  end if;
  if p.executed_source = 'manual' and p.executed_value is not null then
    update public.contract_works set executed_value = p.executed_value where id = v_work;
  end if;
end;
$$;

-- ---------------------------------------------------------------------
-- 5. الصلاحيات المالية: من يختص بـ«أمر تعاقد» (افتراضياً مكتب العقود وموظفو مكتب المدير) والمدير
-- ---------------------------------------------------------------------
create or replace function public.can_edit_finance(p_project uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
  select public.can_edit_form(p_project, 'f01') and public.writes_allowed()
$$;

-- حفظ البيانات المالية اليدوية للعقد (تُستبدل آلياً بما تحسبه البنود والمستخلصات)
create or replace function public.set_contract_finance(
  p_project uuid, p_contract_value numeric, p_executed_value numeric, p_payment_first numeric,
  p_payment_second numeric, p_payment_final numeric, p_deductions numeric)
returns void
language plpgsql security definer set search_path = public
as $$
begin
  if not public.can_edit_form(p_project, 'f01') then
    raise exception 'البيانات المالية للعقد يحدّثها من يختص بـ«أمر تعاقد»' using errcode = '42501';
  end if;
  if not public.writes_allowed() then
    raise exception 'المنظومة مجمّدة حالياً (قراءة فقط)' using errcode = '42501';
  end if;
  if least(p_contract_value, p_executed_value, p_payment_first, p_payment_second, p_payment_final, p_deductions) < 0 then
    raise exception 'القيم المالية لا تكون سالبة' using errcode = '22023';
  end if;
  update public.projects
     set contract_value = p_contract_value,
         executed_value = p_executed_value,
         payment_first  = p_payment_first,
         payment_second = p_payment_second,
         payment_final  = p_payment_final,
         deductions     = p_deductions
   where id = p_project and merged_into is null;
  if not found then
    raise exception 'العقد غير موجود' using errcode = '22023';
  end if;
  perform public.recalc_contract_finance(p_project);
end;
$$;

-- قيم بند (عمل) في العقد
create or replace function public.set_work_values(p_work uuid, p_contract_value numeric, p_executed_value numeric)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  w public.contract_works;
begin
  select * into w from public.contract_works where id = p_work;
  if not found then
    raise exception 'البند غير موجود' using errcode = '22023';
  end if;
  if not public.can_edit_finance(w.project_id) then
    raise exception 'قيم البنود يحدّثها من يختص بالبيانات المالية للعقد' using errcode = '42501';
  end if;
  if coalesce(p_contract_value, 0) < 0 or coalesce(p_executed_value, 0) < 0 then
    raise exception 'القيم المالية لا تكون سالبة' using errcode = '22023';
  end if;
  if w.contract_value is not distinct from p_contract_value and w.executed_value is not distinct from p_executed_value then
    return;
  end if;
  update public.contract_works set contract_value = p_contract_value, executed_value = p_executed_value where id = p_work;
  perform public.write_audit('finance.work_values', w.project_id, null, jsonb_build_object(
    'work_id', w.id, 'title', coalesce(nullif(w.title, ''), w.company),
    'contract_value', jsonb_build_object('from', w.contract_value, 'to', p_contract_value),
    'executed_value', jsonb_build_object('from', w.executed_value, 'to', p_executed_value)));
end;
$$;

-- أمر تغيير
create or replace function public.save_variation(
  p_id uuid, p_project uuid, p_work uuid, p_ref_no text, p_title text, p_kind text, p_amount numeric,
  p_approved_on date, p_notes text)
returns uuid
language plpgsql security definer set search_path = public
as $$
declare
  v    public.contract_variations;
  v_id uuid := p_id;
begin
  if v_id is not null then
    select * into v from public.contract_variations where id = v_id;
    if not found then
      raise exception 'أمر التغيير غير موجود' using errcode = '22023';
    end if;
    p_project := v.project_id;
  end if;
  if not exists (select 1 from public.projects where id = p_project and merged_into is null) then
    raise exception 'العقد غير موجود' using errcode = '22023';
  end if;
  if not public.can_edit_finance(p_project) then
    raise exception 'أوامر التغيير يسجّلها من يختص بالبيانات المالية للعقد' using errcode = '42501';
  end if;
  if p_kind not in ('add', 'deduct') then
    raise exception 'نوع أمر التغيير زيادة أو نقص' using errcode = '22023';
  end if;
  if coalesce(p_amount, 0) <= 0 then
    raise exception 'قيمة أمر التغيير أكبر من صفر' using errcode = '22023';
  end if;
  if length(btrim(coalesce(p_title, ''))) < 2 then
    raise exception 'اكتب وصف أمر التغيير' using errcode = '22023';
  end if;
  if p_work is not null and not exists (select 1 from public.contract_works where id = p_work and project_id = p_project) then
    raise exception 'البند المحدد ليس من بنود هذا العقد' using errcode = '22023';
  end if;
  if v_id is null then
    insert into public.contract_variations (project_id, work_id, ref_no, title, kind, amount, approved_on, notes, created_by)
    values (p_project, p_work, btrim(coalesce(p_ref_no, '')), btrim(p_title), p_kind, round(p_amount, 3), p_approved_on,
            coalesce(p_notes, ''), auth.uid())
    returning id into v_id;
    perform public.write_audit('finance.variation_add', p_project, null, jsonb_build_object(
      'variation_id', v_id, 'title', btrim(p_title), 'kind', p_kind, 'amount', round(p_amount, 3), 'ref_no', btrim(coalesce(p_ref_no, ''))));
  else
    update public.contract_variations
       set work_id = p_work, ref_no = btrim(coalesce(p_ref_no, '')), title = btrim(p_title), kind = p_kind,
           amount = round(p_amount, 3), approved_on = p_approved_on, notes = coalesce(p_notes, '')
     where id = v_id;
    perform public.write_audit('finance.variation_update', p_project, null, jsonb_build_object(
      'variation_id', v_id, 'title', btrim(p_title),
      'kind', jsonb_build_object('from', v.kind, 'to', p_kind),
      'amount', jsonb_build_object('from', v.amount, 'to', round(p_amount, 3))));
  end if;
  return v_id;
end;
$$;

create or replace function public.delete_variation(p_id uuid)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  v public.contract_variations;
begin
  select * into v from public.contract_variations where id = p_id;
  if not found then
    raise exception 'أمر التغيير غير موجود' using errcode = '22023';
  end if;
  if not public.can_edit_finance(v.project_id) then
    raise exception 'أوامر التغيير يسجّلها من يختص بالبيانات المالية للعقد' using errcode = '42501';
  end if;
  if v.origin_project is not null and v.origin_project <> v.project_id then
    raise exception 'أمر التغيير هذا دُمج من عقد آخر؛ افصله بفك الدمج بدل حذفه' using errcode = 'P0001';
  end if;
  delete from public.contract_variations where id = p_id;
  perform public.write_audit('finance.variation_delete', v.project_id, null, jsonb_build_object(
    'variation_id', v.id, 'title', v.title, 'kind', v.kind, 'amount', v.amount));
end;
$$;

-- مستخلص
create or replace function public.save_extract(
  p_id uuid, p_project uuid, p_work uuid, p_ref_no text, p_kind text, p_period_from date, p_period_to date,
  p_submitted_on date, p_gross numeric, p_retention numeric, p_advance numeric, p_penalties numeric,
  p_taxes numeric, p_other numeric, p_status text, p_approved_on date, p_paid_amount numeric, p_paid_on date,
  p_notes text)
returns uuid
language plpgsql security definer set search_path = public
as $$
declare
  e        public.contract_extracts;
  v_id     uuid := p_id;
  v_net    numeric;
  v_status text := coalesce(nullif(p_status, ''), 'submitted');
  v_paid   numeric := round(coalesce(p_paid_amount, 0), 3);
  v_paidon date := p_paid_on;
begin
  if v_id is not null then
    select * into e from public.contract_extracts where id = v_id;
    if not found then
      raise exception 'المستخلص غير موجود' using errcode = '22023';
    end if;
    p_project := e.project_id;
  end if;
  if not exists (select 1 from public.projects where id = p_project and merged_into is null) then
    raise exception 'العقد غير موجود' using errcode = '22023';
  end if;
  if not public.can_edit_finance(p_project) then
    raise exception 'المستخلصات يسجّلها من يختص بالبيانات المالية للعقد' using errcode = '42501';
  end if;
  if v_id is not null and e.status = 'paid' and not public.is_director() then
    raise exception 'المستخلص المدفوع لا يعدّله إلا مدير المكتب' using errcode = '42501';
  end if;
  if coalesce(p_kind, 'interim') not in ('interim', 'final') or v_status not in ('draft', 'submitted', 'approved', 'paid', 'rejected') then
    raise exception 'نوع المستخلص أو حالته غير صحيحة' using errcode = '22023';
  end if;
  if p_gross is null or least(p_gross, coalesce(p_retention, 0), coalesce(p_advance, 0), coalesce(p_penalties, 0),
                              coalesce(p_taxes, 0), coalesce(p_other, 0), v_paid) < 0 then
    raise exception 'قيم المستخلص لا تكون سالبة، وقيمة الأعمال مطلوبة' using errcode = '22023';
  end if;
  v_net := round(p_gross, 3) - round(coalesce(p_retention, 0), 3) - round(coalesce(p_advance, 0), 3)
           - round(coalesce(p_penalties, 0), 3) - round(coalesce(p_taxes, 0), 3) - round(coalesce(p_other, 0), 3);
  if v_net < 0 then
    raise exception 'الاستقطاعات أكبر من قيمة الأعمال في المستخلص' using errcode = '22023';
  end if;
  if p_work is not null and not exists (select 1 from public.contract_works where id = p_work and project_id = p_project) then
    raise exception 'البند المحدد ليس من بنود هذا العقد' using errcode = '22023';
  end if;
  -- الاتساق: المدفوع لا يتجاوز الصافي، والمدفوع كاملاً حالته «مدفوع»
  if v_status = 'paid' and v_paid = 0 then
    v_paid := v_net;
  end if;
  if v_paid > v_net then
    raise exception 'المدفوع أكبر من صافي المستخلص' using errcode = '22023';
  end if;
  if v_paid > 0 and v_status in ('draft', 'submitted', 'rejected') then
    raise exception 'لا يُسجَّل دفع لمستخلص غير معتمد' using errcode = '22023';
  end if;
  if v_status = 'approved' and v_net > 0 and v_paid >= v_net then
    v_status := 'paid';
  end if;
  if v_status = 'paid' and v_paidon is null then
    v_paidon := current_date;
  end if;

  if v_id is null then
    insert into public.contract_extracts (project_id, work_id, seq, ref_no, kind, period_from, period_to, submitted_on,
      gross_amount, retention, advance_recovery, penalties, taxes, other_deductions, status, approved_on,
      paid_amount, paid_on, notes, created_by, updated_by)
    values (p_project, p_work,
            (select coalesce(max(seq), 0) + 1 from public.contract_extracts where project_id = p_project),
            btrim(coalesce(p_ref_no, '')), coalesce(p_kind, 'interim'), p_period_from, p_period_to, p_submitted_on,
            round(p_gross, 3), round(coalesce(p_retention, 0), 3), round(coalesce(p_advance, 0), 3),
            round(coalesce(p_penalties, 0), 3), round(coalesce(p_taxes, 0), 3), round(coalesce(p_other, 0), 3),
            v_status, case when v_status in ('approved', 'paid') then coalesce(p_approved_on, current_date) end,
            v_paid, v_paidon, coalesce(p_notes, ''), auth.uid(), auth.uid())
    returning id into v_id;
    perform public.write_audit('finance.extract_add', p_project, null, jsonb_build_object(
      'extract_id', v_id, 'seq', (select seq from public.contract_extracts where id = v_id), 'status', v_status,
      'gross', round(p_gross, 3), 'net', v_net, 'paid', v_paid));
  else
    update public.contract_extracts set
      work_id = p_work, ref_no = btrim(coalesce(p_ref_no, '')), kind = coalesce(p_kind, 'interim'),
      period_from = p_period_from, period_to = p_period_to, submitted_on = p_submitted_on,
      gross_amount = round(p_gross, 3), retention = round(coalesce(p_retention, 0), 3),
      advance_recovery = round(coalesce(p_advance, 0), 3), penalties = round(coalesce(p_penalties, 0), 3),
      taxes = round(coalesce(p_taxes, 0), 3), other_deductions = round(coalesce(p_other, 0), 3),
      status = v_status,
      approved_on = case when v_status in ('approved', 'paid') then coalesce(p_approved_on, e.approved_on, current_date) end,
      paid_amount = v_paid, paid_on = v_paidon, notes = coalesce(p_notes, ''),
      updated_at = now(), updated_by = auth.uid()
     where id = v_id;
    perform public.write_audit('finance.extract_update', p_project, null, jsonb_build_object(
      'extract_id', v_id, 'seq', e.seq,
      'status', jsonb_build_object('from', e.status, 'to', v_status),
      'gross', jsonb_build_object('from', e.gross_amount, 'to', round(p_gross, 3)),
      'net', jsonb_build_object('from', e.net_amount, 'to', v_net),
      'paid', jsonb_build_object('from', e.paid_amount, 'to', v_paid)));
  end if;
  return v_id;
end;
$$;

create or replace function public.delete_extract(p_id uuid)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  e public.contract_extracts;
begin
  select * into e from public.contract_extracts where id = p_id;
  if not found then
    raise exception 'المستخلص غير موجود' using errcode = '22023';
  end if;
  if not public.can_edit_finance(e.project_id) then
    raise exception 'المستخلصات يسجّلها من يختص بالبيانات المالية للعقد' using errcode = '42501';
  end if;
  if e.status = 'paid' and not public.is_director() then
    raise exception 'المستخلص المدفوع لا يحذفه إلا مدير المكتب' using errcode = '42501';
  end if;
  if e.origin_project is not null and e.origin_project <> e.project_id then
    raise exception 'هذا المستخلص دُمج من عقد آخر؛ افصله بفك الدمج بدل حذفه' using errcode = 'P0001';
  end if;
  delete from public.contract_extracts where id = p_id;
  perform public.write_audit('finance.extract_delete', e.project_id, null, jsonb_build_object(
    'extract_id', e.id, 'seq', e.seq, 'status', e.status, 'gross', e.gross_amount, 'net', e.net_amount, 'paid', e.paid_amount));
end;
$$;

-- سجل التعديلات المالية (للعقد أو للعقود كلها)
create or replace function public.finance_history(p_project uuid default null, p_limit integer default 300)
returns setof jsonb
language sql stable security definer set search_path = public
as $$
  select to_jsonb(a)
    from public.audit_log a
   where public.is_member()
     and (p_project is null or a.project_id = p_project)
     and (a.action like 'finance.%'
          or a.action in ('contract.merge', 'contract.unmerge')
          or (a.action = 'project.update' and a.detail ?| array['contract_value', 'executed_value', 'payment_first',
                                                                'payment_second', 'payment_final', 'deductions'])
          or (a.action = 'setting.update' and a.detail ->> 'key' like 'finance.%'))
     and (a.project_id is not null or public.can_audit() or a.action = 'setting.update')
   order by a.at desc
   limit least(greatest(coalesce(p_limit, 300), 1), 2000)
$$;

-- ---------------------------------------------------------------------
-- 6. الدمج وفكّه يشملان أوامر التغيير والمستخلصات، والقيم من البنود
-- ---------------------------------------------------------------------
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

    update public.quality_notes set project_id = p_target where project_id = v_src;
    update public.notifications set project_id = p_target where project_id = v_src;

    -- الدفعات والخصومات المسجلة يدوياً تُجمع، وبقية القيم تُحسب من البنود والمستخلصات
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

    update public.projects set merged_into = p_target, merged_at = now() where id = v_src;
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
-- 7. قفل الدخول مؤقتاً: الحساب المقفل لا يرى شيئاً حتى يُفك القفل أو تنتهي مدته
-- ---------------------------------------------------------------------
alter table public.profiles
  add column if not exists locked_until timestamptz,
  add column if not exists lock_reason  text not null default '',
  add column if not exists locked_by    uuid references public.profiles (id) on delete set null;

create or replace function public.is_member()
returns boolean
language sql stable security definer set search_path = public
as $$
  select exists (select 1 from public.profiles
                  where id = auth.uid() and active and role is not null
                    and (locked_until is null or locked_until <= now()))
     and public.mfa_ok()
$$;

create or replace function public.my_role()
returns public.app_role
language sql stable security definer set search_path = public
as $$
  select role from public.profiles
   where id = auth.uid() and active and (locked_until is null or locked_until <= now()) and public.mfa_ok()
$$;

create or replace function public.is_auditor()
returns boolean
language sql stable security definer set search_path = public
as $$
  select exists (select 1 from public.profiles
                  where id = auth.uid() and active and role::text = 'security_auditor'
                    and (locked_until is null or locked_until <= now()))
     and public.mfa_ok()
$$;

create or replace function public.has_token(p_project uuid, p_tokens text[])
returns boolean
language plpgsql stable security definer set search_path = public
as $$
declare
  me        public.profiles;
  proj_dept text;
begin
  if not public.mfa_ok() then return false; end if;
  select * into me from public.profiles
   where id = auth.uid() and active and role is not null and (locked_until is null or locked_until <= now());
  if not found then return false; end if;
  if me.role = 'director' then return true; end if;
  if public.setting_bool('security.freeze', false) then return false; end if;
  select department into proj_dept from public.projects where id = p_project;
  if not found then return false; end if;
  return case me.role
    when 'office_staff' then 'office_staff' = any (p_tokens)
    when 'contracts'    then 'contracts'    = any (p_tokens)
    when 'planning_qa'  then 'planning_qa'  = any (p_tokens)
    when 'dept_head'    then
         ('head:supervising' = any (p_tokens) and me.department = proj_dept)
      or ('head:technical'   = any (p_tokens) and me.department = 'technical')
      or ('head:acceptance'  = any (p_tokens) and me.department = 'acceptance')
    else false
  end;
end;
$$;

-- لا يمس CISO حساب المدير ولا حساب CISO آخر؛ والمدير لا يقفل نفسه
create or replace function public.security_target_ok(p_user uuid)
returns boolean
language plpgsql stable security definer set search_path = public
as $$
declare
  v_role text;
begin
  select role::text into v_role from public.profiles where id = p_user;
  if not found or p_user = auth.uid() then
    return false;
  end if;
  if v_role = 'director' then
    return false;
  end if;
  if v_role = 'security_auditor' and not public.is_director() then
    return false;
  end if;
  return public.can_audit();
end;
$$;

create or replace function public.lock_user(p_user uuid, p_minutes integer, p_reason text)
returns integer
language plpgsql security definer set search_path = public, auth
as $$
declare
  v_until timestamptz;
  n       integer := 0;
begin
  if not public.can_audit() then
    raise exception 'قفل الدخول من صلاحية مدير المكتب وCISO' using errcode = '42501';
  end if;
  if not public.security_target_ok(p_user) then
    raise exception 'لا يمكن قفل هذا الحساب' using errcode = '42501';
  end if;
  if length(btrim(coalesce(p_reason, ''))) < 3 then
    raise exception 'اكتب سبب القفل' using errcode = '22023';
  end if;
  if p_minutes is not null and p_minutes not between 5 and 43200 then
    raise exception 'مدة القفل من 5 دقائق إلى 30 يوماً، أو بلا مدة حتى يُفك يدوياً' using errcode = '22023';
  end if;
  v_until := case when p_minutes is null then 'infinity'::timestamptz else now() + make_interval(mins => p_minutes) end;
  perform set_config('app.trusted', 'on', true);
  update public.profiles set locked_until = v_until, lock_reason = left(btrim(p_reason), 300), locked_by = auth.uid()
   where id = p_user;
  perform set_config('app.trusted', 'off', true);
  if to_regclass('auth.sessions') is not null then
    execute 'with d as (delete from auth.sessions where user_id = $1 returning 1) select count(*) from d' into n using p_user;
  end if;
  perform public.write_audit('security.user_lock', null, null,
    jsonb_build_object('user_id', p_user, 'until', v_until, 'reason', btrim(p_reason), 'sessions', n), public.actor_name(p_user));
  if public.is_auditor() then
    perform public.notify_director('security', 'CISO قفل دخول ' || public.actor_name(p_user), btrim(p_reason));
  end if;
  return n;
end;
$$;

create or replace function public.unlock_user(p_user uuid)
returns void
language plpgsql security definer set search_path = public
as $$
begin
  if not public.can_audit() then
    raise exception 'فك القفل من صلاحية مدير المكتب وCISO' using errcode = '42501';
  end if;
  if not public.security_target_ok(p_user) then
    raise exception 'لا يمكن تعديل هذا الحساب' using errcode = '42501';
  end if;
  perform set_config('app.trusted', 'on', true);
  update public.profiles set locked_until = null, lock_reason = '', locked_by = null where id = p_user;
  perform set_config('app.trusted', 'off', true);
  perform public.write_audit('security.user_unlock', null, null, jsonb_build_object('user_id', p_user), public.actor_name(p_user));
end;
$$;

-- حالة حسابي (للتطبيق: هل الحساب مقفل؟)
create or replace function public.my_lock()
returns jsonb
language sql stable security definer set search_path = public
as $$
  select jsonb_build_object('locked', locked_until is not null and locked_until > now(),
                            'until', case when locked_until = 'infinity' then null else locked_until end,
                            'reason', lock_reason)
    from public.profiles where id = auth.uid()
$$;

-- إجراءات الجلسات: المدير وCISO (لا يمس CISO حساب المدير أو حساب CISO آخر)
create or replace function public.revoke_session(p_session uuid)
returns void
language plpgsql security definer set search_path = public, auth
as $$
declare
  v_user uuid;
begin
  if not public.can_audit() then
    raise exception 'إنهاء الجلسات من صلاحية مدير المكتب وCISO' using errcode = '42501';
  end if;
  execute 'select user_id from auth.sessions where id = $1' into v_user using p_session;
  if v_user is null then
    raise exception 'الجلسة غير موجودة أو منتهية' using errcode = '22023';
  end if;
  if v_user <> auth.uid() and not public.security_target_ok(v_user) then
    raise exception 'لا يمكن إنهاء جلسة هذا الحساب' using errcode = '42501';
  end if;
  execute 'delete from auth.sessions where id = $1' using p_session;
  perform public.write_audit('security.session_revoke', null, null,
    jsonb_build_object('session_id', p_session, 'user_id', v_user), public.actor_name(v_user));
end;
$$;

create or replace function public.revoke_user_sessions(p_user uuid)
returns integer
language plpgsql security definer set search_path = public, auth
as $$
declare
  n integer;
begin
  if not public.can_audit() then
    raise exception 'إنهاء الجلسات من صلاحية مدير المكتب وCISO' using errcode = '42501';
  end if;
  if p_user = auth.uid() then
    raise exception 'لإنهاء جلساتك الأخرى استخدم «تسجيل الخروج من الأجهزة الأخرى»' using errcode = 'P0001';
  end if;
  if not public.security_target_ok(p_user) then
    raise exception 'لا يمكن إخراج هذا الحساب' using errcode = '42501';
  end if;
  execute 'with d as (delete from auth.sessions where user_id = $1 returning 1) select count(*) from d' into n using p_user;
  perform public.write_audit('security.user_signout', null, null,
    jsonb_build_object('user_id', p_user, 'sessions', n), public.actor_name(p_user));
  return n;
end;
$$;

-- ---------------------------------------------------------------------
-- 8. سجل الأجهزة: كل جهاز يدخل منه الحساب، وتوثيقه بموافقة صاحبه، وحظره
-- ---------------------------------------------------------------------
create table if not exists public.user_devices (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references public.profiles (id) on delete cascade,
  device_key  text not null check (length(device_key) between 8 and 80),
  platform    text not null default '' check (length(platform) <= 30),
  label       text not null default '' check (length(label) <= 120),
  user_agent  text not null default '' check (length(user_agent) <= 500),
  ip          text not null default '' check (length(ip) <= 64),
  first_ip    text not null default '' check (length(first_ip) <= 64),
  app_version text not null default '' check (length(app_version) <= 30),
  trusted     boolean not null default false,
  first_seen  timestamptz not null default now(),
  last_seen   timestamptz not null default now(),
  last_login  timestamptz,
  sign_ins    integer not null default 0,
  opens       integer not null default 0,
  blocked_at  timestamptz,
  blocked_by  uuid references public.profiles (id) on delete set null,
  unique (user_id, device_key)
);
create index if not exists user_devices_seen_idx on public.user_devices (last_seen desc);

create or replace function public.request_header(p_name text)
returns text
language plpgsql stable security definer set search_path = public
as $$
declare
  h jsonb;
begin
  begin
    h := nullif(current_setting('request.headers', true), '')::jsonb;
  exception when others then
    return '';
  end;
  return coalesce(h ->> p_name, '');
end;
$$;

create or replace function public.register_device(
  p_device_key text, p_platform text, p_label text, p_app_version text, p_trusted boolean, p_event text)
returns jsonb
language plpgsql security definer set search_path = public
as $$
declare
  d      public.user_devices;
  v_ua   text := left(public.request_header('user-agent'), 500);
  v_ip   text := left(btrim(split_part(coalesce(nullif(public.request_header('x-forwarded-for'), ''),
                                               nullif(public.request_header('cf-connecting-ip'), ''),
                                               public.request_header('x-real-ip')), ',', 1)), 64);
  v_new  boolean := false;
  v_evt  text := coalesce(p_event, 'open');
begin
  if auth.uid() is null or not exists (select 1 from public.profiles where id = auth.uid()) then
    raise exception 'سجّل الدخول أولاً' using errcode = '42501';
  end if;
  if length(coalesce(p_device_key, '')) not between 8 and 80 then
    raise exception 'معرّف الجهاز غير صالح' using errcode = '22023';
  end if;
  if v_evt not in ('login', 'open', 'ping') then
    v_evt := 'open';
  end if;
  select * into d from public.user_devices where user_id = auth.uid() and device_key = p_device_key;
  if not found then
    insert into public.user_devices (user_id, device_key, platform, label, user_agent, ip, first_ip, app_version, trusted,
                                     last_login, sign_ins, opens)
    values (auth.uid(), p_device_key, left(coalesce(p_platform, ''), 30), left(coalesce(p_label, ''), 120), v_ua, v_ip, v_ip,
            left(coalesce(p_app_version, ''), 30), coalesce(p_trusted, false),
            case when v_evt = 'login' then now() end, case when v_evt = 'login' then 1 else 0 end, 1)
    returning * into d;
    v_new := true;
    perform public.write_audit('security.device_new', null, null, jsonb_build_object(
      'user_id', auth.uid(), 'device_id', d.id, 'platform', d.platform, 'label', d.label, 'ip', v_ip, 'trusted', d.trusted),
      public.actor_name(auth.uid()));
  else
    if p_trusted is not null and p_trusted <> d.trusted then
      perform public.write_audit(case when p_trusted then 'security.device_trust' else 'security.device_untrust' end,
        null, null, jsonb_build_object('user_id', auth.uid(), 'device_id', d.id, 'platform', d.platform, 'label', d.label),
        public.actor_name(auth.uid()));
    end if;
    if d.blocked_at is not null and v_evt = 'login' then
      perform public.write_audit('security.device_blocked_attempt', null, null, jsonb_build_object(
        'user_id', auth.uid(), 'device_id', d.id, 'platform', d.platform, 'label', d.label, 'ip', v_ip),
        public.actor_name(auth.uid()));
    end if;
    update public.user_devices set
      platform = left(coalesce(nullif(p_platform, ''), platform), 30),
      label = left(coalesce(nullif(p_label, ''), label), 120),
      user_agent = coalesce(nullif(v_ua, ''), user_agent),
      ip = coalesce(nullif(v_ip, ''), ip),
      app_version = left(coalesce(nullif(p_app_version, ''), app_version), 30),
      trusted = coalesce(p_trusted, trusted),
      last_seen = now(),
      last_login = case when v_evt = 'login' then now() else last_login end,
      sign_ins = sign_ins + case when v_evt = 'login' then 1 else 0 end,
      opens = opens + case when v_evt = 'open' then 1 else 0 end
     where id = d.id
     returning * into d;
  end if;
  return jsonb_build_object('device_id', d.id, 'new', v_new, 'trusted', d.trusted,
                            'status', case when d.blocked_at is not null then 'blocked' else 'ok' end,
                            'blocked', d.blocked_at is not null,
                            'locked', exists (select 1 from public.profiles where id = auth.uid() and locked_until > now()));
end;
$$;

-- أجهزتي (لصاحب الحساب): يرى أجهزته ويلغي توثيق أي منها
create or replace function public.my_devices()
returns setof public.user_devices
language sql stable security definer set search_path = public
as $$
  select * from public.user_devices where user_id = auth.uid() order by last_seen desc
$$;

create or replace function public.forget_my_device(p_device uuid)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  d public.user_devices;
begin
  select * into d from public.user_devices where id = p_device and user_id = auth.uid();
  if not found then
    raise exception 'الجهاز غير موجود' using errcode = '22023';
  end if;
  if d.trusted then
    update public.user_devices set trusted = false where id = d.id;
    perform public.write_audit('security.device_untrust', null, null, jsonb_build_object(
      'user_id', auth.uid(), 'device_id', d.id, 'platform', d.platform, 'label', d.label), public.actor_name(auth.uid()));
  end if;
end;
$$;

-- حظر جهاز: يُخرج الحساب من كل جلساته فوراً، ثم يدخل من أجهزته الأخرى، والمحظور يُرفض عند الدخول
create or replace function public.set_device_blocked(p_device uuid, p_blocked boolean)
returns integer
language plpgsql security definer set search_path = public, auth
as $$
declare
  d public.user_devices;
  n integer := 0;
begin
  if not public.can_audit() then
    raise exception 'حظر الأجهزة من صلاحية مدير المكتب وCISO' using errcode = '42501';
  end if;
  select * into d from public.user_devices where id = p_device;
  if not found then
    raise exception 'الجهاز غير موجود' using errcode = '22023';
  end if;
  if not public.security_target_ok(d.user_id) then
    raise exception 'لا يمكن حظر أجهزة هذا الحساب' using errcode = '42501';
  end if;
  update public.user_devices
     set blocked_at = case when p_blocked then now() end, blocked_by = case when p_blocked then auth.uid() end
   where id = p_device;
  if p_blocked and to_regclass('auth.sessions') is not null then
    execute 'with x as (delete from auth.sessions where user_id = $1 returning 1) select count(*) from x' into n using d.user_id;
  end if;
  perform public.write_audit(case when p_blocked then 'security.device_block' else 'security.device_unblock' end, null, null,
    jsonb_build_object('user_id', d.user_id, 'device_id', d.id, 'platform', d.platform, 'label', d.label, 'sessions', n),
    public.actor_name(d.user_id));
  if p_blocked and public.is_auditor() then
    perform public.notify_director('security', 'CISO حظر جهازاً لـ' || public.actor_name(d.user_id),
                                   coalesce(nullif(d.label, ''), d.platform));
  end if;
  return n;
end;
$$;

-- ---------------------------------------------------------------------
-- 9. مركز الأمان الموسع
-- ---------------------------------------------------------------------
create or replace function public.security_overview()
returns jsonb
language plpgsql stable security definer set search_path = public, auth
as $$
declare
  v_sessions integer := null;
  v_logins   integer := null;
  v_logins24 integer := null;
  v_director uuid := (select id from public.profiles where role = 'director' limit 1);
begin
  if not public.can_audit() then
    raise exception 'مركز الأمان لمدير المكتب وCISO' using errcode = '42501';
  end if;
  if to_regclass('auth.sessions') is not null then
    execute 'select count(*) from auth.sessions where coalesce(not_after, ''infinity'') > now()' into v_sessions;
  end if;
  if to_regclass('auth.audit_log_entries') is not null then
    execute $q$select count(*) filter (where created_at > now() - interval '7 days'),
                      count(*) filter (where created_at > now() - interval '1 day')
                 from auth.audit_log_entries
                where created_at > now() - interval '7 days' and payload ->> 'action' = 'login'$q$ into v_logins, v_logins24;
  end if;
  return jsonb_build_object(
    'viewer', case when public.is_director() then 'director' else 'auditor' end,
    'director_mfa', public.mfa_enrolled(v_director),
    'my_mfa', public.mfa_enrolled(auth.uid()),
    'current_aal', coalesce(auth.jwt() ->> 'aal', 'aal1'),
    'users_total', (select count(*) from public.profiles),
    'users_active', (select count(*) from public.profiles where active),
    'users_pending', (select count(*) from public.profiles where not active and role is null),
    'users_disabled', (select count(*) from public.profiles where not active and role is not null),
    'users_locked', (select count(*) from public.profiles where locked_until > now()),
    'users_mfa', (select count(*) from public.profiles p where p.active and public.mfa_enrolled(p.id)),
    'auditors', (select count(*) from public.profiles where active and role::text = 'security_auditor'),
    'sessions_active', v_sessions,
    'logins_7d', v_logins,
    'logins_24h', v_logins24,
    'devices_total', (select count(*) from public.user_devices),
    'devices_trusted', (select count(*) from public.user_devices where trusted and blocked_at is null),
    'devices_blocked', (select count(*) from public.user_devices where blocked_at is not null),
    'devices_new_7d', (select count(*) from public.user_devices where first_seen > now() - interval '7 days'),
    'devices_active_24h', (select count(*) from public.user_devices where last_seen > now() - interval '1 day'),
    'activations_30d', (select count(*) from public.audit_log where action = 'user.activate' and at > now() - interval '30 days'),
    'tables_without_rls', (select coalesce(jsonb_agg(c.relname order by c.relname), '[]'::jsonb)
                             from pg_class c join pg_namespace n on n.oid = c.relnamespace
                            where n.nspname = 'public' and c.relkind = 'r' and not c.relrowsecurity),
    'pending_requests', (select count(*) from public.change_requests where state = 'pending'),
    'security_events_7d', (select count(*) from public.audit_log
                            where at > now() - interval '7 days'
                              and (action like 'security.%' or action like 'user.%')));
end;
$$;

drop function if exists public.security_users();
create function public.security_users()
returns table (id uuid, full_name text, email text, role public.app_role, active boolean,
               mfa boolean, last_sign_in_at timestamptz, created_at timestamptz,
               locked_until timestamptz, lock_reason text, devices integer, sessions integer,
               activated_at timestamptz, activated_by_name text)
language plpgsql stable security definer set search_path = public, auth
as $$
begin
  if not public.can_audit() then
    raise exception 'مركز الأمان لمدير المكتب وCISO' using errcode = '42501';
  end if;
  return query
    select p.id, p.full_name, p.email, p.role, p.active, public.mfa_enrolled(p.id),
           (to_jsonb(u) ->> 'last_sign_in_at')::timestamptz, p.created_at,
           case when p.locked_until > now() then p.locked_until end, p.lock_reason,
           (select count(*)::integer from public.user_devices d where d.user_id = p.id),
           (select count(*)::integer from auth.sessions s where s.user_id = p.id and coalesce(s.not_after, 'infinity') > now()),
           p.activated_at, case when p.activated_by is not null then public.actor_name(p.activated_by) end
      from public.profiles p left join auth.users u on u.id = p.id
     order by p.active desc, p.created_at;
end;
$$;

create or replace function public.security_devices()
returns setof jsonb
language plpgsql stable security definer set search_path = public
as $$
begin
  if not public.can_audit() then
    raise exception 'مركز الأمان لمدير المكتب وCISO' using errcode = '42501';
  end if;
  return query
    select to_jsonb(d) || jsonb_build_object('name', public.actor_name(d.user_id), 'email', p.email, 'role', p.role,
                                             'blocked_by_name', case when d.blocked_by is not null then public.actor_name(d.blocked_by) end)
      from public.user_devices d join public.profiles p on p.id = d.user_id
     order by d.last_seen desc
     limit 1000;
end;
$$;

-- الحركة الدقيقة: الدخول والخروج من سجل المصادقة، وأحداث الأجهزة والأمان والحسابات من سجل التدقيق
create or replace function public.security_timeline(p_user uuid default null, p_days integer default 30, p_limit integer default 500)
returns setof jsonb
language plpgsql stable security definer set search_path = public, auth
as $$
declare
  v_days  integer := least(greatest(coalesce(p_days, 30), 1), 365);
  v_limit integer := least(greatest(coalesce(p_limit, 500), 1), 3000);
begin
  if not public.can_audit() then
    raise exception 'مركز الأمان لمدير المكتب وCISO' using errcode = '42501';
  end if;
  if to_regclass('auth.audit_log_entries') is not null then
    return query execute $q$
      select x from (
        select jsonb_build_object(
                 'at', e.created_at, 'source', 'auth', 'action', e.payload ->> 'action',
                 'user_id', e.payload ->> 'actor_id',
                 'name', case when (e.payload ->> 'actor_id') ~ '^[0-9a-f-]{36}$'
                              then public.actor_name((e.payload ->> 'actor_id')::uuid) end,
                 'email', e.payload ->> 'actor_username', 'ip', to_jsonb(e) ->> 'ip_address') as x, e.created_at as at
          from auth.audit_log_entries e
         where e.created_at > now() - make_interval(days => $1)
           and e.payload ->> 'action' in ('login', 'logout', 'user_signedup', 'user_recovery_requested', 'user_updated_password',
                                          'factor_in_progress', 'factor_unenrolled', 'mfa_code_login', 'token_revoked',
                                          'user_deleted', 'user_modified')
           and ($2 is null or e.payload ->> 'actor_id' = $2::text)
        union all
        select jsonb_build_object(
                 'at', a.at, 'source', 'app', 'action', a.action,
                 'user_id', coalesce(a.detail ->> 'user_id', a.actor::text),
                 'name', coalesce(nullif(a.project_label, ''), a.actor_name),
                 'actor', a.actor_name, 'detail', a.detail) as x, a.at
          from public.audit_log a
         where a.at > now() - make_interval(days => $1)
           and (a.action like 'security.%' or a.action like 'user.%')
           and ($2 is null or a.actor = $2 or a.detail ->> 'user_id' = $2::text)
      ) t
      order by t.at desc
      limit $3$q$ using v_days, p_user, v_limit;
  else
    return query
      select jsonb_build_object('at', a.at, 'source', 'app', 'action', a.action,
                                'user_id', coalesce(a.detail ->> 'user_id', a.actor::text),
                                'name', coalesce(nullif(a.project_label, ''), a.actor_name),
                                'actor', a.actor_name, 'detail', a.detail)
        from public.audit_log a
       where a.at > now() - make_interval(days => v_days)
         and (a.action like 'security.%' or a.action like 'user.%')
         and (p_user is null or a.actor = p_user or a.detail ->> 'user_id' = p_user::text)
       order by a.at desc
       limit v_limit;
  end if;
end;
$$;

-- تنبيهات أمنية محسوبة من البيانات
create or replace function public.security_alerts()
returns setof jsonb
language plpgsql stable security definer set search_path = public, auth
as $$
declare
  v_director uuid := (select id from public.profiles where role = 'director' limit 1);
begin
  if not public.can_audit() then
    raise exception 'مركز الأمان لمدير المكتب وCISO' using errcode = '42501';
  end if;
  -- المدير أو CISO بلا تحقق بخطوتين
  return query
    select jsonb_build_object('level', 'critical', 'kind', 'mfa_missing', 'user_id', p.id, 'at', null,
                              'title', 'حساب حساس بلا تحقق بخطوتين: ' || public.actor_name(p.id))
      from public.profiles p
     where p.active and p.role::text in ('director', 'security_auditor') and not public.mfa_enrolled(p.id);
  -- جهاز محظور ما زال يحاول الدخول
  return query
    select jsonb_build_object('level', 'critical', 'kind', 'blocked_device_active', 'user_id', d.user_id, 'at', d.last_seen,
                              'title', 'جهاز محظور حاول الدخول: ' || public.actor_name(d.user_id) || ' (' || d.platform || ')')
      from public.user_devices d
     where d.blocked_at is not null and d.last_seen > d.blocked_at;
  -- أجهزة جديدة خلال 7 أيام
  return query
    select jsonb_build_object('level', case when d.trusted then 'info' else 'warning' end, 'kind', 'new_device',
                              'user_id', d.user_id, 'at', d.first_seen,
                              'title', 'جهاز جديد لـ' || public.actor_name(d.user_id) || ': ' ||
                                       coalesce(nullif(d.label, ''), d.platform) || case when d.ip <> '' then ' · ' || d.ip else '' end)
      from public.user_devices d
     where d.first_seen > now() - interval '7 days';
  -- حسابات بجلسات كثيرة متزامنة
  if to_regclass('auth.sessions') is not null then
    return query execute $q$
      select jsonb_build_object('level', 'warning', 'kind', 'many_sessions', 'user_id', s.user_id, 'at', max(s.created_at),
                                'title', 'جلسات كثيرة متزامنة (' || count(*) || ') لـ' || public.actor_name(s.user_id))
        from auth.sessions s
       where coalesce(s.not_after, 'infinity') > now()
       group by s.user_id
      having count(*) > 3$q$;
  end if;
  -- دخول خارج ساعات العمل (22:00–05:00 بتوقيت طرابلس) خلال 7 أيام
  if to_regclass('auth.audit_log_entries') is not null then
    return query execute $q$
      select jsonb_build_object('level', 'info', 'kind', 'off_hours_login', 'user_id', e.payload ->> 'actor_id',
                                'at', e.created_at,
                                'title', 'دخول خارج ساعات العمل: ' || coalesce(case when (e.payload ->> 'actor_id') ~ '^[0-9a-f-]{36}$'
                                         then public.actor_name((e.payload ->> 'actor_id')::uuid) end, e.payload ->> 'actor_username', ''))
        from auth.audit_log_entries e
       where e.created_at > now() - interval '7 days' and e.payload ->> 'action' = 'login'
         and extract(hour from e.created_at at time zone 'Africa/Tripoli') not between 5 and 21
       order by e.created_at desc
       limit 50$q$;
  end if;
  -- حسابات مقفلة، وحسابات تنتظر التفعيل، وتفعيلات حديثة
  return query
    select jsonb_build_object('level', 'info', 'kind', 'locked', 'user_id', p.id, 'at', null,
                              'title', 'دخول مقفل: ' || public.actor_name(p.id) || case when p.lock_reason <> '' then ' — ' || p.lock_reason else '' end)
      from public.profiles p where p.locked_until > now();
  return query
    select jsonb_build_object('level', 'warning', 'kind', 'pending', 'user_id', p.id, 'at', p.created_at,
                              'title', 'حساب ينتظر التفعيل: ' || coalesce(nullif(p.full_name, ''), p.email))
      from public.profiles p where not p.active and p.role is null;
  return query
    select jsonb_build_object('level', 'info', 'kind', 'activated', 'user_id', a.detail ->> 'user_id', 'at', a.at,
                              'title', 'فُعّل حساب ' || a.project_label || ' بواسطة ' || a.actor_name)
      from public.audit_log a
     where a.action = 'user.activate' and a.at > now() - interval '7 days';
end;
$$;

create or replace function public.user_details(p_user uuid)
returns jsonb
language plpgsql stable security definer set search_path = public, auth
as $$
declare
  p        public.profiles;
  u        jsonb;
  v_mfa    jsonb := '[]'::jsonb;
  v_sess   jsonb := '[]'::jsonb;
  v_logins jsonb := '[]'::jsonb;
begin
  if not public.can_audit() then
    raise exception 'البيانات الكاملة للمستخدمين لمدير المكتب وCISO' using errcode = '42501';
  end if;
  select * into p from public.profiles where id = p_user;
  if not found then
    raise exception 'المستخدم غير موجود' using errcode = '22023';
  end if;
  select to_jsonb(x) into u from auth.users x where x.id = p_user;

  if to_regclass('auth.mfa_factors') is not null then
    execute $q$select coalesce(jsonb_agg(jsonb_build_object(
                 'id', f.id, 'type', to_jsonb(f) ->> 'factor_type', 'name', to_jsonb(f) ->> 'friendly_name',
                 'status', to_jsonb(f) ->> 'status', 'created_at', f.created_at, 'updated_at', f.updated_at,
                 'last_challenged_at', to_jsonb(f) -> 'last_challenged_at') order by f.created_at), '[]'::jsonb)
               from auth.mfa_factors f where f.user_id = $1$q$ into v_mfa using p_user;
  end if;
  if to_regclass('auth.sessions') is not null then
    execute $q$select coalesce(jsonb_agg(jsonb_build_object(
                 'id', s.id, 'created_at', s.created_at,
                 'updated_at', coalesce(to_jsonb(s) ->> 'refreshed_at', to_jsonb(s) ->> 'updated_at'),
                 'user_agent', to_jsonb(s) ->> 'user_agent', 'ip', to_jsonb(s) ->> 'ip', 'aal', to_jsonb(s) ->> 'aal',
                 'not_after', s.not_after) order by s.created_at desc), '[]'::jsonb)
               from auth.sessions s
              where s.user_id = $1 and coalesce(s.not_after, 'infinity') > now()$q$ into v_sess using p_user;
  end if;
  if to_regclass('auth.audit_log_entries') is not null then
    execute $q$select coalesce(jsonb_agg(x order by (x ->> 'at') desc), '[]'::jsonb) from (
                 select jsonb_build_object('at', e.created_at, 'action', e.payload ->> 'action',
                                           'ip', to_jsonb(e) ->> 'ip_address') as x
                   from auth.audit_log_entries e
                  where e.payload ->> 'actor_id' = $1::text
                  order by e.created_at desc
                  limit 60) t$q$ into v_logins using p_user;
  end if;

  return jsonb_build_object(
    'profile', to_jsonb(p) || jsonb_build_object(
        'activated_by_name', case when p.activated_by is not null then public.actor_name(p.activated_by) end,
        'locked', p.locked_until is not null and p.locked_until > now(),
        'locked_by_name', case when p.locked_by is not null then public.actor_name(p.locked_by) end,
        'department_name', (select d.name from public.departments d where d.key = p.department),
        'mfa_required', p.role::text in ('director', 'security_auditor')
                        or public.setting_bool('security.require_mfa_all', false),
        'can_act', public.security_target_ok(p.id)),
    'auth', case when u is null then null else jsonb_build_object(
        'email', u ->> 'email',
        'phone', nullif(u ->> 'phone', ''),
        'created_at', u -> 'created_at',
        'updated_at', u -> 'updated_at',
        'email_confirmed_at', u -> 'email_confirmed_at',
        'last_sign_in_at', u -> 'last_sign_in_at',
        'invited_at', u -> 'invited_at',
        'recovery_sent_at', u -> 'recovery_sent_at',
        'banned_until', u -> 'banned_until',
        'email_change', nullif(u ->> 'email_change', ''),
        'providers', coalesce(u -> 'raw_app_meta_data' -> 'providers', '[]'::jsonb),
        'signup_name', u -> 'raw_user_meta_data' ->> 'full_name',
        'is_sso_user', u -> 'is_sso_user') end,
    'mfa', v_mfa,
    'sessions', v_sess,
    'logins', v_logins,
    'devices', (select coalesce(jsonb_agg(to_jsonb(d) order by d.last_seen desc), '[]'::jsonb)
                  from public.user_devices d where d.user_id = p_user),
    'activity', jsonb_build_object(
        'audit_total', (select count(*) from public.audit_log where actor = p_user),
        'audit_30d', (select count(*) from public.audit_log where actor = p_user and at > now() - interval '30 days'),
        'last_action_at', (select max(at) from public.audit_log where actor = p_user),
        'forms_updated', (select count(*) from public.project_forms where updated_by = p_user),
        'projects_created', (select count(*) from public.projects where created_by = p_user),
        'requests', (select coalesce(jsonb_object_agg(state, n), '{}'::jsonb)
                       from (select state::text as state, count(*) as n from public.change_requests
                              where requested_by = p_user group by state) r),
        'ideas', (select count(*) from public.ideas where created_by = p_user),
        'quality_notes', (select count(*) from public.quality_notes where author = p_user)),
    'recent', (select coalesce(jsonb_agg(to_jsonb(a) order by a.at desc), '[]'::jsonb)
                 from (select * from public.audit_log where actor = p_user order by at desc limit 40) a),
    'history', (select coalesce(jsonb_agg(to_jsonb(a) order by a.at desc), '[]'::jsonb)
                  from (select * from public.audit_log
                         where detail ->> 'user_id' = p_user::text order by at desc limit 40) a));
end;
$$;

-- ---------------------------------------------------------------------
-- 10. الإعدادات: المظهر
-- ---------------------------------------------------------------------
insert into public.app_settings (key, value) values
  ('ui.appearance', '{}')
on conflict (key) do nothing;

create or replace function public.set_setting(p_key text, p_value jsonb)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  v_old jsonb;
  t     text := jsonb_typeof(p_value);
  ok    boolean;
begin
  if not public.is_director() then
    raise exception 'الإعدادات من صلاحية مدير المكتب وحده' using errcode = '42501';
  end if;
  ok := case
    when p_key in ('brand.app_title', 'brand.org_name', 'brand.org_parent') then
      t = 'string' and length(btrim(p_value #>> '{}')) between 2 and 120
    when p_key = 'brand.primary_color' then
      t = 'string' and (p_value #>> '{}') ~ '^#[0-9A-Fa-f]{6}$'
    when p_key = 'finance.currency' then
      t = 'string' and length(btrim(p_value #>> '{}')) between 1 and 12
    when p_key in ('finance.guarantee_initial_rate', 'finance.guarantee_final_rate') then
      t = 'number' and (p_value #>> '{}')::numeric between 0 and 0.5
    when p_key = 'security.idle_minutes' then
      t = 'number' and (p_value #>> '{}')::numeric between 0 and 480
    when p_key in ('security.require_mfa_director', 'security.require_mfa_all', 'security.freeze', 'security.signups_open',
                   'ai.enabled') then
      t = 'boolean'
    when p_key = 'ui.announcement' then
      t = 'object' and jsonb_typeof(p_value -> 'text') = 'string' and length(p_value ->> 'text') <= 500
      and coalesce(p_value ->> 'level', 'info') in ('info', 'warning', 'critical')
    when p_key = 'ui.status_labels' then
      t = 'object' and (select bool_and(jsonb_typeof(p_value -> k) = 'string' and length(btrim(p_value ->> k)) between 2 and 30)
                          from unnest(array['done', 'wip', 'todo', 'na']) k)
    when p_key = 'ui.features' then
      t = 'object' and (select bool_and(jsonb_typeof(v) = 'boolean') from jsonb_each(p_value) e(k, v))
    when p_key = 'ui.motion' then
      t = 'string' and (p_value #>> '{}') in ('full', 'reduced', 'off')
    when p_key = 'ui.nav' then
      t = 'object'
      and coalesce(jsonb_typeof(p_value -> 'hidden'), 'array') = 'array'
      and coalesce(jsonb_typeof(p_value -> 'order'), 'array') = 'array'
      and coalesce(jsonb_typeof(p_value -> 'labels'), 'object') = 'object'
      and coalesce((select bool_and(jsonb_typeof(v) = 'string' and length(v #>> '{}') <= 40)
                      from jsonb_each(coalesce(p_value -> 'labels', '{}')) e(k, v)), true)
      and length(p_value::text) <= 4000
    when p_key = 'ui.dashboard' then
      t = 'object' and jsonb_typeof(p_value -> 'sections') = 'array' and length(p_value::text) <= 4000
      and coalesce((select bool_and(jsonb_typeof(x -> 'key') = 'string' and jsonb_typeof(x -> 'on') = 'boolean')
                      from jsonb_array_elements(p_value -> 'sections') x), true)
    when p_key = 'ui.labels' then
      t = 'object' and length(p_value::text) <= 8000
      and coalesce((select bool_and(jsonb_typeof(v) = 'string' and length(v #>> '{}') between 1 and 60)
                      from jsonb_each(p_value) e(k, v)), true)
    when p_key = 'ui.appearance' then
      t = 'object' and length(p_value::text) <= 6000
      and coalesce(jsonb_typeof(p_value -> 'charts'), 'object') = 'object'
    when p_key = 'ai.model' then
      t = 'string' and (p_value #>> '{}') ~ '^[a-z0-9][a-z0-9.\-]{2,60}$'
    when p_key = 'ai.instructions' then
      t = 'string' and length(p_value #>> '{}') <= 4000
    else false
  end;
  if not coalesce(ok, false) then
    raise exception 'قيمة غير صالحة للإعداد %', p_key using errcode = '22023';
  end if;
  if p_key in ('security.require_mfa_director', 'security.require_mfa_all') and p_value = 'true'::jsonb
     and not public.mfa_enrolled(auth.uid()) then
    raise exception 'فعّل التحقق بخطوتين لحسابك أولاً' using errcode = 'P0001';
  end if;

  select value into v_old from public.app_settings where key = p_key;
  if v_old is not distinct from p_value then
    return;
  end if;
  insert into public.app_settings (key, value, updated_at, updated_by)
  values (p_key, p_value, now(), auth.uid())
  on conflict (key) do update set value = excluded.value, updated_at = excluded.updated_at, updated_by = excluded.updated_by;

  if p_key in ('finance.guarantee_initial_rate', 'finance.guarantee_final_rate') then
    perform set_config('app.recalc', 'on', true);
    perform set_config('app.trusted', 'on', true);
    update public.projects set executed_value = executed_value where executed_value is not null;
    perform set_config('app.trusted', 'off', true);
    perform set_config('app.recalc', 'off', true);
  end if;

  perform public.write_audit(case when p_key like 'security.%' then 'security.setting' else 'setting.update' end,
    null, null, jsonb_build_object('key', p_key, 'from', v_old, 'to', p_value), p_key);
end;
$$;

create or replace function public.public_settings()
returns jsonb
language sql stable security definer set search_path = public
as $$
  select coalesce(jsonb_object_agg(key, value), '{}'::jsonb)
  from public.app_settings
  where key like 'brand.%' or key in ('security.signups_open', 'security.idle_minutes',
                                       'security.require_mfa_all', 'security.require_mfa_director',
                                       'ui.motion', 'ui.appearance')
$$;

-- ---------------------------------------------------------------------
-- 11. ملخص مساعد Claude: المالية الكاملة والمعرّفات (لاقتراح التعديلات) وملخص الأمان
-- ---------------------------------------------------------------------
create or replace function public.ai_context()
returns jsonb
language plpgsql stable security definer set search_path = public
as $$
begin
  if not public.is_director() then
    raise exception 'مساعد Claude لمدير المكتب وحده' using errcode = '42501';
  end if;
  if not public.setting_bool('ai.enabled', true) then
    raise exception 'مساعد Claude متوقف من الإعدادات' using errcode = 'P0001';
  end if;
  return jsonb_build_object(
    'generated_at', now(),
    'org', public.setting('brand.org_name'),
    'currency', public.setting('finance.currency'),
    'guarantee_rates', jsonb_build_object('initial', public.setting('finance.guarantee_initial_rate'),
                                          'final', public.setting('finance.guarantee_final_rate'),
                                          'base', 'قيمة الأعمال المنفذة'),
    'stages', (select coalesce(jsonb_agg(name order by idx), '[]'::jsonb) from public.stages),
    'forms', (select coalesce(jsonb_agg(jsonb_build_object('key', key, 'name', name, 'stage', stage, 'sensitive', sensitive)
                                        order by sort), '[]'::jsonb) from public.form_defs where active),
    'departments', (select coalesce(jsonb_object_agg(key, name), '{}'::jsonb) from public.departments),
    'contracts', (select coalesce(jsonb_agg(c order by (c ->> 'sort')::int), '[]'::jsonb) from (
      select jsonb_strip_nulls(jsonb_build_object(
               'id', p.id, 'sort', p.sort_order, 'contract_no', p.contract_no, 'assign_no', p.assign_no, 'name', p.name,
               'owner', p.owner, 'company', p.company, 'department', p.department,
               'contract_value', p.contract_value, 'value_source', p.value_source,
               'variations_net', p.variations_net,
               'adjusted_value', coalesce(p.contract_value, 0) + p.variations_net,
               'executed_value', p.executed_value, 'executed_source', p.executed_source,
               'extracts', jsonb_build_object('count', p.extracts_count, 'gross', p.extracts_gross, 'net', p.extracts_net,
                                              'paid', p.extracts_paid, 'retention', p.retention_held),
               'legacy_payments', coalesce(p.payment_first, 0) + coalesce(p.payment_second, 0) + coalesce(p.payment_final, 0),
               'deductions', p.deductions, 'guarantee_initial', p.guarantee_initial, 'guarantee_final', p.guarantee_final,
               'progress_pct', v.pct, 'cycle', v.cycle_state, 'stage', v.current_stage, 'next_form', v.next_form_name,
               'works', (select jsonb_agg(jsonb_strip_nulls(jsonb_build_object('id', w.id, 'title', w.title, 'company', w.company,
                                            'ref', w.ref_no, 'contract_value', w.contract_value, 'executed_value', w.executed_value))
                                          order by w.sort)
                           from public.contract_works w where w.project_id = p.id),
               'engineers', (select jsonb_agg(jsonb_build_object('id', e.id, 'kind', e.kind, 'name', e.name, 'assign_no', e.assign_no)
                                              order by e.kind, e.sort)
                               from public.contract_engineers e where e.project_id = p.id),
               'variations', (select jsonb_agg(jsonb_build_object('id', x.id, 'ref', x.ref_no, 'title', x.title, 'kind', x.kind,
                                                                  'amount', x.amount, 'approved_on', x.approved_on) order by x.approved_on)
                                from public.contract_variations x where x.project_id = p.id),
               'extract_list', (select jsonb_agg(jsonb_strip_nulls(jsonb_build_object('id', x.id, 'seq', x.seq, 'ref', x.ref_no,
                                    'kind', x.kind, 'status', x.status, 'submitted_on', x.submitted_on, 'gross', x.gross_amount,
                                    'retention', x.retention, 'deductions', x.gross_amount - x.net_amount - x.retention,
                                    'net', x.net_amount, 'paid', x.paid_amount, 'paid_on', x.paid_on)) order by x.seq)
                                  from public.contract_extracts x where x.project_id = p.id),
               'notes', nullif(p.notes, ''))) as c
        from public.projects p
        left join public.v_project_progress v on v.project_id = p.id
       where p.merged_into is null
       order by p.sort_order
       limit 400) x),
    'pending_requests', (select coalesce(jsonb_agg(jsonb_build_object(
                            'contract', public.project_label(r.project_id), 'form', d.name,
                            'to', r.to_status, 'by', public.actor_name(r.requested_by), 'at', r.requested_at)
                            order by r.requested_at), '[]'::jsonb)
                           from public.change_requests r join public.form_defs d on d.key = r.form_key
                          where r.state = 'pending'),
    'recent_activity', (select coalesce(jsonb_agg(jsonb_build_object('at', a.at, 'who', a.actor_name, 'action', a.action,
                                                                     'contract', a.project_label, 'form', a.form_key)
                                                  order by a.at desc), '[]'::jsonb)
                          from (select * from public.audit_log order by at desc limit 60) a),
    'users', (select jsonb_build_object('active', count(*) filter (where active),
                                        'pending', count(*) filter (where not active and role is null),
                                        'locked', count(*) filter (where locked_until > now()))
                from public.profiles),
    'security', jsonb_build_object(
        'devices', (select count(*) from public.user_devices),
        'devices_new_7d', (select count(*) from public.user_devices where first_seen > now() - interval '7 days'),
        'devices_blocked', (select count(*) from public.user_devices where blocked_at is not null)),
    'ideas_open', (select count(*) from public.ideas where status in ('new', 'planned', 'in_progress')),
    'instructions', public.setting('ai.instructions'),
    'model', public.setting('ai.model'));
end;
$$;

-- تنفيذ المدير اقتراحاً من المساعد يُسجَّل (التعديل نفسه يُسجَّل بعمليته المعتادة)
create or replace function public.ai_action_log(p_name text, p_summary text)
returns void
language plpgsql security definer set search_path = public
as $$
begin
  if not public.is_director() then
    raise exception 'مساعد Claude لمدير المكتب وحده' using errcode = '42501';
  end if;
  perform public.write_audit('ai.action', null, null,
    jsonb_build_object('name', left(coalesce(p_name, ''), 60), 'summary', left(coalesce(p_summary, ''), 500)), 'مساعد Claude');
end;
$$;

-- ---------------------------------------------------------------------
-- 12. الحساب الأول للمجاميع (العقود الحالية)
-- ---------------------------------------------------------------------
do $$
declare
  r record;
begin
  for r in select id from public.projects loop
    perform public.recalc_contract_finance(r.id);
  end loop;
end $$;

-- ---------------------------------------------------------------------
-- 13. سياسات الوصول والصلاحيات
-- ---------------------------------------------------------------------
alter table public.contract_variations enable row level security;
alter table public.contract_extracts   enable row level security;
alter table public.user_devices        enable row level security;

drop policy if exists contract_variations_read on public.contract_variations;
create policy contract_variations_read on public.contract_variations for select to authenticated using (public.is_member());
drop policy if exists contract_extracts_read on public.contract_extracts;
create policy contract_extracts_read on public.contract_extracts for select to authenticated using (public.is_member());
drop policy if exists user_devices_read on public.user_devices;
create policy user_devices_read on public.user_devices for select to authenticated
  using (user_id = auth.uid() or public.can_audit());

revoke all on public.contract_variations, public.contract_extracts, public.user_devices from anon;
revoke insert, update, delete, truncate on public.contract_variations, public.contract_extracts, public.user_devices
  from authenticated;
grant select on public.contract_variations, public.contract_extracts, public.user_devices to authenticated;
grant all on public.contract_variations, public.contract_extracts, public.user_devices to service_role;

-- مجاميع العقد والقفل لا تُعدَّل مباشرة
revoke insert, update on public.projects from authenticated;
grant insert (assign_no, code, name, owner, company, department, notes, eng_sup, eng_qty, eng_fol, eng_saf, sort_order)
  on public.projects to authenticated;
grant update (assign_no, code, name, owner, company, department, notes, eng_sup, eng_qty, eng_fol, eng_saf, sort_order,
              contract_value, executed_value, payment_first, payment_second, payment_final, deductions)
  on public.projects to authenticated;

revoke execute on function
  public.recalc_contract_finance(uuid), public.finance_children_after(), public.materialize_finance(uuid),
  public.can_edit_finance(uuid), public.security_target_ok(uuid), public.request_header(text)
from public, anon, authenticated;

revoke execute on function
  public.set_contract_finance(uuid, numeric, numeric, numeric, numeric, numeric, numeric),
  public.set_work_values(uuid, numeric, numeric),
  public.save_variation(uuid, uuid, uuid, text, text, text, numeric, date, text), public.delete_variation(uuid),
  public.save_extract(uuid, uuid, uuid, text, text, date, date, date, numeric, numeric, numeric, numeric, numeric, numeric,
                      text, date, numeric, date, text),
  public.delete_extract(uuid), public.finance_history(uuid, integer),
  public.merge_contracts(uuid, uuid[]), public.unmerge_contract(uuid),
  public.lock_user(uuid, integer, text), public.unlock_user(uuid), public.my_lock(),
  public.revoke_session(uuid), public.revoke_user_sessions(uuid),
  public.register_device(text, text, text, text, boolean, text), public.set_device_blocked(uuid, boolean),
  public.my_devices(), public.forget_my_device(uuid),
  public.security_overview(), public.security_users(), public.security_devices(),
  public.security_timeline(uuid, integer, integer), public.security_alerts(), public.user_details(uuid),
  public.set_setting(text, jsonb), public.public_settings(), public.ai_context(), public.ai_action_log(text, text)
from public, anon;
grant execute on function
  public.set_contract_finance(uuid, numeric, numeric, numeric, numeric, numeric, numeric),
  public.set_work_values(uuid, numeric, numeric),
  public.save_variation(uuid, uuid, uuid, text, text, text, numeric, date, text), public.delete_variation(uuid),
  public.save_extract(uuid, uuid, uuid, text, text, date, date, date, numeric, numeric, numeric, numeric, numeric, numeric,
                      text, date, numeric, date, text),
  public.delete_extract(uuid), public.finance_history(uuid, integer),
  public.merge_contracts(uuid, uuid[]), public.unmerge_contract(uuid),
  public.lock_user(uuid, integer, text), public.unlock_user(uuid), public.my_lock(),
  public.revoke_session(uuid), public.revoke_user_sessions(uuid),
  public.register_device(text, text, text, text, boolean, text), public.set_device_blocked(uuid, boolean),
  public.my_devices(), public.forget_my_device(uuid),
  public.security_overview(), public.security_users(), public.security_devices(),
  public.security_timeline(uuid, integer, integer), public.security_alerts(), public.user_details(uuid),
  public.set_setting(text, jsonb), public.ai_context(), public.ai_action_log(text, text)
to authenticated;
grant execute on function public.public_settings() to anon, authenticated;

-- التحديث اللحظي
do $$
declare
  t text;
begin
  foreach t in array array['contract_variations', 'contract_extracts', 'user_devices'] loop
    if not exists (select 1 from pg_publication_tables
                   where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = t) then
      execute format('alter publication supabase_realtime add table public.%I', t);
    end if;
  end loop;
end $$;

notify pgrst, 'reload schema';

select 'تم: البنود بقيمها، والمستخلصات، وأوامر التغيير، والأجهزة، وقفل الدخول، ومركز الأمان الموسع' as result;
