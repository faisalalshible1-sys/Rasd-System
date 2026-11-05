-- =====================================================================
--  توسيع المالية:
--    1. حالة «محال للصرف» للمستخلص (بين المعتمد والمدفوع) بتاريخ الإحالة ورقمها.
--    2. سجل دفعات لكل مستخلص: أكثر من دفعة بمبلغها وتاريخها وطريقتها ورقم الصك أو الحوالة؛
--       المدفوع وحالة «مدفوع» يُحسبان منها آلياً.
--    3. استقطاعات مخصصة يعرّفها مدير المكتب (الاسم والنسبة الافتراضية) وتدخل في الصافي والمجاميع.
--    4. نسب افتراضية للتأمين المحتجز والضرائب واسترداد الدفعة المقدمة.
--    5. الدفعة المقدمة لكل عقد، واستردادها من المستخلصات، ورصيدها المتبقي.
--  يُشغَّل بعد 20261105000011_finance_security.sql. إعادة تشغيله آمنة.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. المستخلص: محال للصرف، والاستقطاعات المخصصة
-- ---------------------------------------------------------------------
alter table public.contract_extracts
  add column if not exists referred_on       date,
  add column if not exists referral_no       text not null default '' check (length(referral_no) <= 60),
  add column if not exists custom_deductions jsonb not null default '{}' check (jsonb_typeof(custom_deductions) = 'object'),
  add column if not exists custom_total      numeric(16, 3) not null default 0 check (custom_total >= 0);

alter table public.contract_extracts drop constraint if exists contract_extracts_status_check;
alter table public.contract_extracts add constraint contract_extracts_status_check
  check (status in ('draft', 'submitted', 'approved', 'referred', 'paid', 'rejected'));

-- الصافي يشمل الاستقطاعات المخصصة (يُعاد إنشاء العمود المحسوب)
alter table public.contract_extracts drop constraint if exists contract_extracts_deductions;
alter table public.contract_extracts drop constraint if exists contract_extracts_paid;
alter table public.contract_extracts drop column if exists net_amount;
alter table public.contract_extracts add column net_amount numeric(16, 3) generated always as
  (gross_amount - retention - advance_recovery - penalties - taxes - other_deductions - custom_total) stored;
alter table public.contract_extracts add constraint contract_extracts_deductions check
  (retention + advance_recovery + penalties + taxes + other_deductions + custom_total <= gross_amount);
alter table public.contract_extracts add constraint contract_extracts_paid check
  (paid_amount <= gross_amount - retention - advance_recovery - penalties - taxes - other_deductions - custom_total);

-- ---------------------------------------------------------------------
-- 2. سجل دفعات المستخلص
-- ---------------------------------------------------------------------
create table if not exists public.extract_payments (
  id          uuid primary key default gen_random_uuid(),
  extract_id  uuid not null references public.contract_extracts (id) on delete cascade,
  project_id  uuid not null references public.projects (id) on delete cascade,
  amount      numeric(16, 3) not null check (amount > 0),
  paid_on     date not null,
  method      text not null default 'transfer' check (method in ('cheque', 'transfer', 'cash', 'other')),
  ref_no      text not null default '' check (length(ref_no) <= 60),
  notes       text not null default '' check (length(notes) <= 1000),
  created_at  timestamptz not null default now(),
  created_by  uuid references public.profiles (id) on delete set null
);
create index if not exists extract_payments_extract_idx on public.extract_payments (extract_id, paid_on);
create index if not exists extract_payments_project_idx on public.extract_payments (project_id, paid_on);

-- المدفوع وتاريخه وحالة «مدفوع» تتبع سجل الدفعات
create or replace function public.sync_extract_paid(p_extract uuid)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  v_sum numeric;
  v_day date;
  v_n   integer;
begin
  select coalesce(sum(amount), 0), max(paid_on), count(*) into v_sum, v_day, v_n
    from public.extract_payments where extract_id = p_extract;
  update public.contract_extracts x set
    paid_amount = round(v_sum, 3),
    paid_on     = v_day,
    status      = case
                    when v_n > 0 and x.net_amount > 0 and v_sum >= x.net_amount then 'paid'
                    when x.status = 'paid' and v_sum < x.net_amount then
                      case when x.referred_on is not null then 'referred' else 'approved' end
                    else x.status
                  end,
    updated_at  = now(),
    updated_by  = coalesce(auth.uid(), x.updated_by)
   where x.id = p_extract;
end;
$$;

create or replace function public.extract_payments_after()
returns trigger
language plpgsql security definer set search_path = public
as $$
begin
  if tg_op in ('UPDATE', 'DELETE') then
    perform public.sync_extract_paid(old.extract_id);
  end if;
  if tg_op = 'INSERT' or (tg_op = 'UPDATE' and new.extract_id is distinct from old.extract_id) then
    perform public.sync_extract_paid(new.extract_id);
  end if;
  return null;
end;
$$;
drop trigger if exists extract_payments_after on public.extract_payments;
create trigger extract_payments_after
  after insert or update or delete on public.extract_payments
  for each row execute function public.extract_payments_after();

-- الدفعات تتبع مستخلصها عند الدمج وفكّه
create or replace function public.contract_extracts_move_payments()
returns trigger
language plpgsql security definer set search_path = public
as $$
begin
  update public.extract_payments set project_id = new.project_id where extract_id = new.id and project_id <> new.project_id;
  return null;
end;
$$;
drop trigger if exists contract_extracts_move_payments on public.contract_extracts;
create trigger contract_extracts_move_payments
  after update of project_id on public.contract_extracts
  for each row execute function public.contract_extracts_move_payments();

-- ---------------------------------------------------------------------
-- 3. الدفعة المقدمة للعقد
-- ---------------------------------------------------------------------
alter table public.projects
  add column if not exists advance_amount    numeric(16, 3) check (advance_amount >= 0),
  add column if not exists advance_paid_on   date,
  add column if not exists advance_recovered numeric(16, 3) not null default 0;

-- ---------------------------------------------------------------------
-- 4. الحساب الآلي: «محال للصرف» يدخل في المنفذ، والمسترد من الدفعة المقدمة
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
  v_eg   numeric; v_en numeric; v_paid numeric; v_ret numeric; v_adv numeric;
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
         coalesce(sum(paid_amount), 0), coalesce(sum(retention), 0), coalesce(sum(advance_recovery), 0)
    into n_ext, v_eg, v_en, v_paid, v_ret, v_adv
    from public.contract_extracts where project_id = p_project and status in ('approved', 'referred', 'paid');

  perform set_config('app.trusted', 'on', true);
  perform set_config('app.recalc', 'on', true);
  update public.projects set
    value_source      = case when n_cv > 0 then 'items' else 'manual' end,
    contract_value    = case when n_cv > 0 then v_cv else contract_value end,
    executed_source   = case when n_ext > 0 then 'extracts' when n_ev > 0 then 'items' else 'manual' end,
    executed_value    = case when n_ext > 0 then v_eg when n_ev > 0 then v_ev else executed_value end,
    variations_net    = v_var,
    extracts_count    = n_ext,
    extracts_gross    = v_eg,
    extracts_net      = v_en,
    extracts_paid     = v_paid,
    retention_held    = v_ret,
    advance_recovered = v_adv
   where id = p_project
     and (value_source, contract_value, executed_source, executed_value, variations_net, extracts_count,
          extracts_gross, extracts_net, extracts_paid, retention_held, advance_recovered)
         is distinct from
         (case when n_cv > 0 then 'items' else 'manual' end,
          case when n_cv > 0 then v_cv else contract_value end,
          case when n_ext > 0 then 'extracts' when n_ev > 0 then 'items' else 'manual' end,
          case when n_ext > 0 then v_eg when n_ev > 0 then v_ev else executed_value end,
          v_var, n_ext, v_eg, v_en, v_paid, v_ret, v_adv);
  perform set_config('app.trusted', v_trusted, true);
  perform set_config('app.recalc', v_recalc, true);
end;
$$;

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

-- ---------------------------------------------------------------------
-- 5. حفظ المستخلص (الصيغة الموسعة)
-- ---------------------------------------------------------------------
create or replace function public.save_extract(
  p_id uuid, p_project uuid, p_work uuid, p_ref_no text, p_kind text, p_period_from date, p_period_to date,
  p_submitted_on date, p_gross numeric, p_retention numeric, p_advance numeric, p_penalties numeric,
  p_taxes numeric, p_other numeric, p_status text, p_approved_on date, p_paid_amount numeric, p_paid_on date,
  p_notes text, p_referred_on date, p_referral_no text, p_custom jsonb)
returns uuid
language plpgsql security definer set search_path = public
as $$
declare
  e         public.contract_extracts;
  p         public.projects;
  v_id      uuid := p_id;
  v_net     numeric;
  v_status  text := coalesce(nullif(p_status, ''), 'submitted');
  v_paid    numeric := round(coalesce(p_paid_amount, 0), 3);
  v_paidon  date := p_paid_on;
  v_custom  jsonb := '{}'::jsonb;
  v_ctotal  numeric := 0;
  v_ledger  integer := 0;
  v_advused numeric;
  k         text;
  val       jsonb;
begin
  if v_id is not null then
    select * into e from public.contract_extracts where id = v_id;
    if not found then
      raise exception 'المستخلص غير موجود' using errcode = '22023';
    end if;
    p_project := e.project_id;
    select count(*) into v_ledger from public.extract_payments where extract_id = v_id;
  end if;
  select * into p from public.projects where id = p_project and merged_into is null;
  if not found then
    raise exception 'العقد غير موجود' using errcode = '22023';
  end if;
  if not public.can_edit_finance(p_project) then
    raise exception 'المستخلصات يسجّلها من يختص بالبيانات المالية للعقد' using errcode = '42501';
  end if;
  if v_id is not null and e.status = 'paid' and not public.is_director() then
    raise exception 'المستخلص المدفوع لا يعدّله إلا مدير المكتب' using errcode = '42501';
  end if;
  if coalesce(p_kind, 'interim') not in ('interim', 'final')
     or v_status not in ('draft', 'submitted', 'approved', 'referred', 'paid', 'rejected') then
    raise exception 'نوع المستخلص أو حالته غير صحيحة' using errcode = '22023';
  end if;
  if p_gross is null or least(p_gross, coalesce(p_retention, 0), coalesce(p_advance, 0), coalesce(p_penalties, 0),
                              coalesce(p_taxes, 0), coalesce(p_other, 0), v_paid) < 0 then
    raise exception 'قيم المستخلص لا تكون سالبة، وقيمة الأعمال مطلوبة' using errcode = '22023';
  end if;
  -- الاستقطاعات المخصصة: مفاتيح بأحرف لاتينية صغيرة وقيم غير سالبة
  if p_custom is not null and jsonb_typeof(p_custom) <> 'object' then
    raise exception 'الاستقطاعات المخصصة بصيغة غير صحيحة' using errcode = '22023';
  end if;
  for k, val in select * from jsonb_each(coalesce(p_custom, '{}'::jsonb)) loop
    if k !~ '^[a-z][a-z0-9_]{1,29}$' or jsonb_typeof(val) <> 'number' or (val #>> '{}')::numeric < 0 then
      raise exception 'قيمة استقطاع مخصص غير صالحة: %', k using errcode = '22023';
    end if;
    if (val #>> '{}')::numeric > 0 then
      v_custom := v_custom || jsonb_build_object(k, round((val #>> '{}')::numeric, 3));
      v_ctotal := v_ctotal + round((val #>> '{}')::numeric, 3);
    end if;
  end loop;
  v_net := round(p_gross, 3) - round(coalesce(p_retention, 0), 3) - round(coalesce(p_advance, 0), 3)
           - round(coalesce(p_penalties, 0), 3) - round(coalesce(p_taxes, 0), 3) - round(coalesce(p_other, 0), 3) - v_ctotal;
  if v_net < 0 then
    raise exception 'الاستقطاعات أكبر من قيمة الأعمال في المستخلص' using errcode = '22023';
  end if;
  if p_work is not null and not exists (select 1 from public.contract_works where id = p_work and project_id = p_project) then
    raise exception 'البند المحدد ليس من بنود هذا العقد' using errcode = '22023';
  end if;
  -- استرداد الدفعة المقدمة لا يتجاوز رصيدها
  if coalesce(p.advance_amount, 0) > 0 and coalesce(p_advance, 0) > 0 then
    select coalesce(sum(advance_recovery), 0) into v_advused
      from public.contract_extracts
     where project_id = p_project and status <> 'rejected' and id is distinct from v_id;
    if v_advused + round(p_advance, 3) > p.advance_amount then
      raise exception 'استرداد الدفعة المقدمة يتجاوز رصيدها (المتبقي %)', round(p.advance_amount - v_advused, 3)
        using errcode = '22023';
    end if;
  end if;

  if v_ledger > 0 then
    -- المدفوع من سجل الدفعات
    select coalesce(sum(amount), 0), max(paid_on) into v_paid, v_paidon from public.extract_payments where extract_id = v_id;
    if v_paid > v_net then
      raise exception 'الدفعات المسجلة (%) أكبر من الصافي الجديد', v_paid using errcode = '22023';
    end if;
    if v_status = 'paid' and v_paid < v_net then
      raise exception 'سجّل الدفعات حتى يكتمل الصافي، أو اختر حالة أخرى' using errcode = '22023';
    end if;
    if v_status in ('draft', 'submitted', 'rejected') then
      raise exception 'للمستخلص دفعات مسجلة؛ احذفها قبل إرجاعه' using errcode = '22023';
    end if;
  else
    if v_status = 'paid' and v_paid = 0 then
      v_paid := v_net;
    end if;
    if v_paid > v_net then
      raise exception 'المدفوع أكبر من صافي المستخلص' using errcode = '22023';
    end if;
    if v_paid > 0 and v_status in ('draft', 'submitted', 'rejected') then
      raise exception 'لا يُسجَّل دفع لمستخلص غير معتمد' using errcode = '22023';
    end if;
    if v_status = 'paid' and v_paidon is null then
      v_paidon := current_date;
    end if;
  end if;
  if v_status in ('approved', 'referred') and v_net > 0 and v_paid >= v_net then
    v_status := 'paid';
  end if;

  if v_id is null then
    insert into public.contract_extracts (project_id, work_id, seq, ref_no, kind, period_from, period_to, submitted_on,
      gross_amount, retention, advance_recovery, penalties, taxes, other_deductions, custom_deductions, custom_total,
      status, approved_on, referred_on, referral_no, paid_amount, paid_on, notes, created_by, updated_by)
    values (p_project, p_work,
            (select coalesce(max(seq), 0) + 1 from public.contract_extracts where project_id = p_project),
            btrim(coalesce(p_ref_no, '')), coalesce(p_kind, 'interim'), p_period_from, p_period_to, p_submitted_on,
            round(p_gross, 3), round(coalesce(p_retention, 0), 3), round(coalesce(p_advance, 0), 3),
            round(coalesce(p_penalties, 0), 3), round(coalesce(p_taxes, 0), 3), round(coalesce(p_other, 0), 3),
            v_custom, v_ctotal,
            v_status,
            case when v_status in ('approved', 'referred', 'paid') then coalesce(p_approved_on, current_date) end,
            case when v_status = 'referred' then coalesce(p_referred_on, current_date)
                 when v_status = 'paid' then p_referred_on end,
            left(btrim(coalesce(p_referral_no, '')), 60),
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
      custom_deductions = v_custom, custom_total = v_ctotal,
      status = v_status,
      approved_on = case when v_status in ('approved', 'referred', 'paid') then coalesce(p_approved_on, e.approved_on, current_date) end,
      referred_on = case when v_status = 'referred' then coalesce(p_referred_on, e.referred_on, current_date)
                         when v_status = 'paid' then coalesce(p_referred_on, e.referred_on) end,
      referral_no = left(btrim(coalesce(p_referral_no, '')), 60),
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

-- الصيغة السابقة (للإصدار السابق من التطبيق): تحفظ حقول الإحالة والاستقطاعات المخصصة كما هي
create or replace function public.save_extract(
  p_id uuid, p_project uuid, p_work uuid, p_ref_no text, p_kind text, p_period_from date, p_period_to date,
  p_submitted_on date, p_gross numeric, p_retention numeric, p_advance numeric, p_penalties numeric,
  p_taxes numeric, p_other numeric, p_status text, p_approved_on date, p_paid_amount numeric, p_paid_on date,
  p_notes text)
returns uuid
language plpgsql security definer set search_path = public
as $$
declare
  e public.contract_extracts;
begin
  if p_id is not null then
    select * into e from public.contract_extracts where id = p_id;
  end if;
  return public.save_extract(p_id, p_project, p_work, p_ref_no, p_kind, p_period_from, p_period_to, p_submitted_on,
    p_gross, p_retention, p_advance, p_penalties, p_taxes, p_other, p_status, p_approved_on, p_paid_amount, p_paid_on,
    p_notes, e.referred_on, coalesce(e.referral_no, ''), coalesce(e.custom_deductions, '{}'::jsonb));
end;
$$;

-- ---------------------------------------------------------------------
-- 6. دفعات المستخلص
-- ---------------------------------------------------------------------
create or replace function public.add_extract_payment(
  p_extract uuid, p_amount numeric, p_paid_on date, p_method text, p_ref_no text, p_notes text)
returns uuid
language plpgsql security definer set search_path = public
as $$
declare
  e    public.contract_extracts;
  v_id uuid;
  v_n  integer;
  v_sum numeric;
begin
  select * into e from public.contract_extracts where id = p_extract;
  if not found then
    raise exception 'المستخلص غير موجود' using errcode = '22023';
  end if;
  if not public.can_edit_finance(e.project_id) then
    raise exception 'الدفعات يسجّلها من يختص بالبيانات المالية للعقد' using errcode = '42501';
  end if;
  if e.status not in ('approved', 'referred', 'paid') then
    raise exception 'تُسجَّل الدفعات للمستخلص المعتمد أو المحال للصرف' using errcode = '22023';
  end if;
  if coalesce(p_amount, 0) <= 0 then
    raise exception 'مبلغ الدفعة أكبر من صفر' using errcode = '22023';
  end if;
  if coalesce(p_method, 'transfer') not in ('cheque', 'transfer', 'cash', 'other') then
    raise exception 'طريقة الدفع غير معروفة' using errcode = '22023';
  end if;
  select count(*), coalesce(sum(amount), 0) into v_n, v_sum from public.extract_payments where extract_id = e.id;
  -- أول دفعة في السجل لمستخلص دُفع منه سابقاً: يُسجَّل ما سبق رصيداً افتتاحياً حتى لا يضيع
  if v_n = 0 and e.paid_amount > 0 then
    insert into public.extract_payments (extract_id, project_id, amount, paid_on, method, ref_no, notes, created_by)
    values (e.id, e.project_id, e.paid_amount, coalesce(e.paid_on, current_date), 'other', 'رصيد سابق',
            'ما سُجّل مدفوعاً قبل سجل الدفعات', auth.uid());
    v_sum := e.paid_amount;
  end if;
  if v_sum + round(p_amount, 3) > e.net_amount then
    raise exception 'الدفعة أكبر من المتبقي للصرف (%)', round(e.net_amount - v_sum, 3) using errcode = '22023';
  end if;
  insert into public.extract_payments (extract_id, project_id, amount, paid_on, method, ref_no, notes, created_by)
  values (e.id, e.project_id, round(p_amount, 3), coalesce(p_paid_on, current_date), coalesce(p_method, 'transfer'),
          left(btrim(coalesce(p_ref_no, '')), 60), left(coalesce(p_notes, ''), 1000), auth.uid())
  returning id into v_id;
  perform public.write_audit('finance.payment_add', e.project_id, null, jsonb_build_object(
    'extract_id', e.id, 'seq', e.seq, 'payment_id', v_id, 'amount', round(p_amount, 3),
    'method', coalesce(p_method, 'transfer'), 'ref_no', btrim(coalesce(p_ref_no, '')), 'paid_on', coalesce(p_paid_on, current_date)));
  return v_id;
end;
$$;

create or replace function public.delete_extract_payment(p_id uuid)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  pay public.extract_payments;
  e   public.contract_extracts;
begin
  select * into pay from public.extract_payments where id = p_id;
  if not found then
    raise exception 'الدفعة غير موجودة' using errcode = '22023';
  end if;
  select * into e from public.contract_extracts where id = pay.extract_id;
  if not public.can_edit_finance(e.project_id) then
    raise exception 'الدفعات يسجّلها من يختص بالبيانات المالية للعقد' using errcode = '42501';
  end if;
  if e.status = 'paid' and not public.is_director() then
    raise exception 'دفعات المستخلص المدفوع لا يحذفها إلا مدير المكتب' using errcode = '42501';
  end if;
  delete from public.extract_payments where id = p_id;
  perform public.write_audit('finance.payment_delete', e.project_id, null, jsonb_build_object(
    'extract_id', e.id, 'seq', e.seq, 'payment_id', pay.id, 'amount', pay.amount, 'ref_no', pay.ref_no, 'paid_on', pay.paid_on));
end;
$$;

-- ---------------------------------------------------------------------
-- 7. الدفعة المقدمة
-- ---------------------------------------------------------------------
create or replace function public.set_contract_advance(p_project uuid, p_amount numeric, p_paid_on date)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  p public.projects;
begin
  select * into p from public.projects where id = p_project and merged_into is null;
  if not found then
    raise exception 'العقد غير موجود' using errcode = '22023';
  end if;
  if not public.can_edit_finance(p_project) then
    raise exception 'الدفعة المقدمة يسجّلها من يختص بالبيانات المالية للعقد' using errcode = '42501';
  end if;
  if p_amount is not null and p_amount < 0 then
    raise exception 'قيمة الدفعة المقدمة لا تكون سالبة' using errcode = '22023';
  end if;
  if coalesce(p_amount, 0) < p.advance_recovered then
    raise exception 'الدفعة المقدمة أقل مما استُرد منها في المستخلصات (%)', p.advance_recovered using errcode = '22023';
  end if;
  if p.advance_amount is not distinct from round(p_amount, 3) and p.advance_paid_on is not distinct from p_paid_on then
    return;
  end if;
  perform set_config('app.trusted', 'on', true);
  update public.projects set advance_amount = round(p_amount, 3), advance_paid_on = p_paid_on where id = p_project;
  perform set_config('app.trusted', 'off', true);
  perform public.write_audit('finance.advance', p_project, null, jsonb_build_object(
    'amount', jsonb_build_object('from', p.advance_amount, 'to', round(p_amount, 3)),
    'paid_on', jsonb_build_object('from', p.advance_paid_on, 'to', p_paid_on)));
end;
$$;

-- ---------------------------------------------------------------------
-- 8. الإعدادات: النسب الافتراضية والاستقطاعات المخصصة
-- ---------------------------------------------------------------------
insert into public.app_settings (key, value) values
  ('finance.retention_rate', '0.1'),
  ('finance.tax_rate', '0'),
  ('finance.advance_recovery_rate', '0'),
  ('finance.deduction_types', '[]')
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
    when p_key in ('finance.guarantee_initial_rate', 'finance.guarantee_final_rate', 'finance.retention_rate', 'finance.tax_rate') then
      t = 'number' and (p_value #>> '{}')::numeric between 0 and 0.5
    when p_key = 'finance.advance_recovery_rate' then
      t = 'number' and (p_value #>> '{}')::numeric between 0 and 1
    when p_key = 'finance.deduction_types' then
      t = 'array' and jsonb_array_length(p_value) <= 12
      and coalesce((select bool_and(jsonb_typeof(x) = 'object'
                                    and jsonb_typeof(x -> 'key') = 'string' and (x ->> 'key') ~ '^[a-z][a-z0-9_]{1,29}$'
                                    and jsonb_typeof(x -> 'label') = 'string' and length(btrim(x ->> 'label')) between 2 and 40
                                    and (x -> 'rate' is null or jsonb_typeof(x -> 'rate') = 'null'
                                         or (jsonb_typeof(x -> 'rate') = 'number' and (x ->> 'rate')::numeric between 0 and 0.5)))
                      from jsonb_array_elements(p_value) x), true)
      and (select count(distinct x ->> 'key') = count(*) from jsonb_array_elements(p_value) x)
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

-- ---------------------------------------------------------------------
-- 9. ملخص مساعد Claude: الإحالة للصرف، والدفعات، والاستقطاعات المخصصة، والدفعة المقدمة
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
    'finance_defaults', jsonb_build_object('retention_rate', public.setting('finance.retention_rate'),
                                           'tax_rate', public.setting('finance.tax_rate'),
                                           'advance_recovery_rate', public.setting('finance.advance_recovery_rate'),
                                           'deduction_types', public.setting('finance.deduction_types')),
    'extract_statuses', jsonb_build_object('draft', 'مسودة', 'submitted', 'مقدَّم', 'approved', 'معتمد',
                                           'referred', 'محال للصرف', 'paid', 'مدفوع', 'rejected', 'مرفوض'),
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
               'advance', case when p.advance_amount is not null then jsonb_build_object(
                                 'amount', p.advance_amount, 'paid_on', p.advance_paid_on, 'recovered', p.advance_recovered,
                                 'remaining', p.advance_amount - p.advance_recovered) end,
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
                                    'kind', x.kind, 'status', x.status, 'submitted_on', x.submitted_on, 'approved_on', x.approved_on,
                                    'referred_on', x.referred_on, 'referral_no', nullif(x.referral_no, ''),
                                    'gross', x.gross_amount, 'retention', x.retention, 'advance_recovery', x.advance_recovery,
                                    'custom_deductions', nullif(x.custom_deductions, '{}'::jsonb),
                                    'deductions', x.gross_amount - x.net_amount - x.retention,
                                    'net', x.net_amount, 'paid', x.paid_amount, 'paid_on', x.paid_on,
                                    'payments', (select jsonb_agg(jsonb_build_object('amount', y.amount, 'paid_on', y.paid_on,
                                                                                    'method', y.method, 'ref', y.ref_no) order by y.paid_on)
                                                   from public.extract_payments y where y.extract_id = x.id))) order by x.seq)
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

-- ---------------------------------------------------------------------
-- 10. الحساب الأول، وسياسات الوصول والصلاحيات
-- ---------------------------------------------------------------------
do $$
declare
  r record;
begin
  for r in select id from public.projects loop
    perform public.recalc_contract_finance(r.id);
  end loop;
end $$;

alter table public.extract_payments enable row level security;
drop policy if exists extract_payments_read on public.extract_payments;
create policy extract_payments_read on public.extract_payments for select to authenticated using (public.is_member());
revoke all on public.extract_payments from anon;
revoke insert, update, delete, truncate on public.extract_payments from authenticated;
grant select on public.extract_payments to authenticated;
grant all on public.extract_payments to service_role;

revoke execute on function
  public.sync_extract_paid(uuid), public.extract_payments_after(), public.contract_extracts_move_payments()
from public, anon, authenticated;

revoke execute on function
  public.save_extract(uuid, uuid, uuid, text, text, date, date, date, numeric, numeric, numeric, numeric, numeric, numeric,
                      text, date, numeric, date, text, date, text, jsonb),
  public.save_extract(uuid, uuid, uuid, text, text, date, date, date, numeric, numeric, numeric, numeric, numeric, numeric,
                      text, date, numeric, date, text),
  public.add_extract_payment(uuid, numeric, date, text, text, text), public.delete_extract_payment(uuid),
  public.set_contract_advance(uuid, numeric, date), public.set_setting(text, jsonb), public.ai_context()
from public, anon;
grant execute on function
  public.save_extract(uuid, uuid, uuid, text, text, date, date, date, numeric, numeric, numeric, numeric, numeric, numeric,
                      text, date, numeric, date, text, date, text, jsonb),
  public.save_extract(uuid, uuid, uuid, text, text, date, date, date, numeric, numeric, numeric, numeric, numeric, numeric,
                      text, date, numeric, date, text),
  public.add_extract_payment(uuid, numeric, date, text, text, text), public.delete_extract_payment(uuid),
  public.set_contract_advance(uuid, numeric, date), public.set_setting(text, jsonb), public.ai_context()
to authenticated;

do $$
begin
  if not exists (select 1 from pg_publication_tables
                 where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'extract_payments') then
    alter publication supabase_realtime add table public.extract_payments;
  end if;
end $$;

notify pgrst, 'reload schema';

select 'تم: «محال للصرف»، وسجل الدفعات، والاستقطاعات المخصصة، والنسب الافتراضية، والدفعة المقدمة' as result;
