-- التراجع عن الترحيل 50 (المحاسبة). يُرفض إن وُجدت قيود أو حسابات مالية مربوطة بالدليل حتى لا تضيع.
do $$
begin
  if to_regclass('public.fin_journals') is not null and (exists (select 1 from public.fin_journals)
     or exists (select 1 from public.fin_accounts where gl_account_id is not null)) then
    raise exception 'لا يُتراجع عن الترحيل 50: توجد قيود محاسبية أو حسابات مربوطة بالدليل. المنظومة كما هي.';
  end if;
end $$;
-- إعادة دوال الترحيلين 48 و49 كما كانت قبل قيود المحاسبة
create or replace function public.fin_payroll_approve(p_period date)
returns void
language plpgsql security definer set search_path = public
as $$
declare p public.fin_payrolls; v_p date := date_trunc('month', p_period)::date;
begin
  if not public.finance_can_approve() then raise exception 'اعتماد الكشف لمن يملك صلاحية الاعتماد' using errcode = '42501'; end if;
  select * into p from public.fin_payrolls where period = v_p;
  if not found then raise exception 'لا كشف لهذا الشهر' using errcode = 'P0002'; end if;
  if p.status <> 'draft' then raise exception 'الكشف ليس مسودة' using errcode = '23514'; end if;
  if not exists (select 1 from public.fin_payroll_lines where payroll_id = p.id) then raise exception 'الكشف بلا موظفين' using errcode = '23514'; end if;
  if exists (select 1 from public.fin_payroll_lines where payroll_id = p.id and net < 0) then
    raise exception 'في الكشف صافٍ سالب؛ راجع الخصومات قبل الاعتماد' using errcode = '23514';
  end if;
  update public.fin_payrolls set status = 'approved', approved_at = now(), approved_by = auth.uid() where id = p.id;
  perform public.write_audit('finance.payroll_approve', null, null,
    jsonb_build_object('period', v_p, 'net', (select sum(net) from public.fin_payroll_lines where payroll_id = p.id)), to_char(v_p, 'YYYY-MM'));
end $$;

create or replace function public.fin_payroll_reopen(p_period date, p_reason text)
returns void
language plpgsql security definer set search_path = public
as $$
declare p public.fin_payrolls; v_p date := date_trunc('month', p_period)::date;
begin
  if not public.finance_can_approve() then raise exception 'التراجع لمن يملك صلاحية الاعتماد' using errcode = '42501'; end if;
  if length(btrim(coalesce(p_reason, ''))) < 3 or length(p_reason) > 300 then raise exception 'سبب التراجع مطلوب (3 إلى 300 حرف)' using errcode = '22023'; end if;
  select * into p from public.fin_payrolls where period = v_p;
  if not found then raise exception 'لا كشف لهذا الشهر' using errcode = 'P0002'; end if;
  if p.status = 'draft' then raise exception 'الكشف مسودة أصلاً' using errcode = '23514'; end if;
  update public.fin_payrolls set status = 'draft', approved_at = null, approved_by = null, locked_at = null, locked_by = null where id = p.id;
  perform public.write_audit('finance.payroll_reopen', null, null,
    jsonb_build_object('period', v_p, 'from', p.status, 'reason', btrim(p_reason)), to_char(v_p, 'YYYY-MM'));
end $$;

create or replace function public.fin_transfer_decide(p_id uuid, p_approve boolean, p_note text default '')
returns void
language plpgsql security definer set search_path = public
as $$
declare x public.fin_transfers; f public.fin_accounts; t public.fin_accounts; v_n text := btrim(coalesce(p_note, ''));
begin
  perform public.fin_need_approve();
  if p_approve is null then raise exception 'حدّد الموافقة أو الرفض' using errcode = '22023'; end if;
  if length(v_n) > 300 then raise exception 'الملاحظة أطول من 300 حرف' using errcode = '22023'; end if;
  if not p_approve and length(v_n) < 3 then raise exception 'سبب الرفض مطلوب (3 أحرف فأكثر)' using errcode = '22023'; end if;
  select * into x from public.fin_transfers where id = p_id for update;
  if not found then raise exception 'التحويل غير موجود' using errcode = 'P0002'; end if;
  if x.status <> 'pending' then raise exception 'التحويل ليس معلّقاً' using errcode = '23514'; end if;
  select * into f from public.fin_accounts where id = x.from_id;
  select * into t from public.fin_accounts where id = x.to_id;
  if p_approve and public.fin_account_balance(x.from_id) < x.amount then
    raise exception 'رصيد «%» لا يكفي لهذا التحويل', f.name using errcode = '23514';
  end if;
  update public.fin_transfers set status = case when p_approve then 'posted' else 'rejected' end, decided_at = now(),
         decided_by = auth.uid(), decision_note = v_n where id = p_id;
  perform public.write_audit(case when p_approve then 'finance.transfer_approve' else 'finance.transfer_reject' end, null, null,
    jsonb_build_object('from', f.name, 'to', t.name, 'amount', x.amount, 'note', v_n), f.name || ' ← ' || t.name);
end $$;

drop table if exists public.fin_gl_map;
drop table if exists public.fin_journal_lines;
drop table if exists public.fin_journals;
alter table public.fin_accounts drop column if exists gl_account_id;
drop table if exists public.fin_gl_accounts;
drop sequence if exists public.fin_journal_seq;
drop function if exists public.fin_journal_guard();
drop function if exists public.fin_gl_debit_normal(text);
drop function if exists public.fin_gl_account_save(uuid, text, text, text, uuid, boolean, boolean);
drop function if exists public.fin_gl_account_delete(uuid);
drop function if exists public.fin_account_link(uuid, uuid);
drop function if exists public.fin_gl_map_set(text, uuid);
drop function if exists public.fin_journal_auto(text, uuid, date, text, jsonb, uuid);
drop function if exists public.fin_journal_save(uuid, date, text, jsonb);
drop function if exists public.fin_journal_delete(uuid);
drop function if exists public.fin_journal_post(uuid);
drop function if exists public.fin_journal_reverse(uuid, text);
drop function if exists public.fin_trial_balance(date, date);
