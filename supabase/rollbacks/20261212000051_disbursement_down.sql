-- التراجع عن الترحيل 51 (اعتماد الصرف). يُرفض إن وُجدت طلبات صرف أو ضمانات مربوطة بمستخلص حتى لا تضيع.
do $$
begin
  if to_regclass('public.fin_disbursements') is not null and exists (select 1 from public.fin_disbursements) then
    raise exception 'لا يُتراجع عن الترحيل 51: توجد طلبات صرف. المنظومة كما هي.';
  end if;
  if exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'fin_guarantees' and column_name = 'extract_id')
     and exists (select 1 from public.fin_guarantees where extract_id is not null) then
    raise exception 'لا يُتراجع عن الترحيل 51: توجد ضمانات محتجزة مربوطة بمستخلصات. المنظومة كما هي.';
  end if;
end $$;
drop trigger if exists contract_extracts_paid_guard on public.contract_extracts;
drop function if exists public.contract_extracts_paid_guard();
-- إعادة الدوال كما كانت قبل الترحيل 51
create or replace function public.fin_account_balance(p_id uuid)
returns numeric
language sql stable security definer set search_path = public
as $$
  select a.opening
       + coalesce((select sum(amount) from public.fin_transfers where to_id = a.id and status = 'posted'), 0)
       - coalesce((select sum(amount) from public.fin_transfers where from_id = a.id and status = 'posted'), 0)
    from public.fin_accounts a where a.id = p_id
$$;

create or replace function public.fin_gl_map_set(p_key text, p_gl uuid)
returns void
language plpgsql security definer set search_path = public
as $$
declare g public.fin_gl_accounts; v_type text;
begin
  perform public.fin_need_approve();
  if p_key is null or p_key not in ('payroll_expense', 'payroll_net', 'payroll_insurance', 'payroll_tax', 'payroll_other', 'payroll_loan') then
    raise exception 'مفتاح تعيين غير صالح' using errcode = '22023';
  end if;
  select * into g from public.fin_gl_accounts where id = p_gl;
  if not found then raise exception 'حساب الدليل غير موجود' using errcode = 'P0002'; end if;
  v_type := case p_key when 'payroll_expense' then 'expense' when 'payroll_loan' then 'asset' else 'liability' end;
  if g.type <> v_type or not g.postable or not g.active then
    raise exception 'هذا التعيين لحساب % فرعي مفعّل', case v_type when 'expense' then 'مصروفات' when 'asset' then 'أصول' else 'خصوم' end using errcode = '23514';
  end if;
  insert into public.fin_gl_map (key, account_id) values (p_key, p_gl) on conflict (key) do update set account_id = excluded.account_id;
  perform public.write_audit('finance.gl_map_set', null, null, jsonb_build_object('key', p_key, 'gl', g.code || ' ' || g.name), g.code);
end $$;

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

drop function if exists public.fin_disb_reverse(uuid, text);
drop function if exists public.fin_disb_decide(uuid, boolean, text);
drop function if exists public.fin_disb_cancel(uuid);
drop function if exists public.fin_disb_review(uuid, boolean, text);
drop function if exists public.fin_disb_request(uuid, numeric, uuid, date, text, text, text);
drop function if exists public.fin_guarantee_from_extract(uuid, text);
drop function if exists public.fin_extract_remaining(uuid, uuid);
drop table if exists public.fin_disbursements;
delete from public.fin_gl_map where key = 'extract_payable';
alter table public.fin_gl_map drop constraint if exists fin_gl_map_key_check;
alter table public.fin_gl_map add constraint fin_gl_map_key_check
  check (key in ('payroll_expense', 'payroll_net', 'payroll_insurance', 'payroll_tax', 'payroll_other', 'payroll_loan'));
delete from public.fin_gl_accounts a where a.code = '2150'
  and not exists (select 1 from public.fin_journal_lines l where l.account_id = a.id);
alter table public.fin_journals drop constraint if exists fin_journals_source_check;
alter table public.fin_journals add constraint fin_journals_source_check check (source in ('manual', 'payroll', 'payroll_reversal', 'transfer'));
drop index if exists public.fin_guarantees_extract_uq;
alter table public.fin_guarantees drop column if exists extract_id;
