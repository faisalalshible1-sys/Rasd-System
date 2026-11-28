-- الإصدار 3.4.0 — الترحيل 51: المراجعة المالية واعتماد الصرف وقيده الآلي وربط المحتجز.
--
-- اعتماد المستخلص ليس صرفاً. يمرّ الصرف بطلب (تحرير) ثم مراجعة مالية (تحرير) ثم اعتماد (صلاحية الاعتماد)،
-- وعند الاعتماد: تُسجَّل دفعة المستخلص (فيصير «مدفوعاً» إن اكتمل صافيه)، ويُخفَّض رصيد الحساب المالي، ويُنشأ قيد آلي
-- (مدين مستحقات المقاولين ودائن حساب الخزينة أو المصرف). ولا يتحول مستخلص إلى «مدفوع» أو يزداد مدفوعه من غير هذه الدورة
-- إلا بيد مدير المكتب (للسجلات التاريخية). المحتجز المخصوم في المستخلص يُسجَّل ضماناً محتجزاً مرتبطاً به قبل مراجعة صرفه.
-- لا تُمسّ بيانات قائمة ولا يُطبَّق شيء على عقد تلقائياً. يعمل الملف مرتين دون ضرر.

-- ---------------------------------------------------------------------
-- 1. ربط الضمان بالمستخلص، ومصدرا قيد جديدان، وحساب مستحقات المقاولين
-- ---------------------------------------------------------------------
alter table public.fin_guarantees add column if not exists extract_id uuid references public.contract_extracts (id) on delete set null;
create unique index if not exists fin_guarantees_extract_uq on public.fin_guarantees (extract_id) where extract_id is not null;

alter table public.fin_journals drop constraint if exists fin_journals_source_check;
alter table public.fin_journals add constraint fin_journals_source_check
  check (source in ('manual', 'payroll', 'payroll_reversal', 'transfer', 'disbursement', 'disbursement_reversal'));

insert into public.fin_gl_accounts (code, name, type, parent_id, postable)
select '2150', 'مستحقات المقاولين', 'liability', p.id, true
  from public.fin_gl_accounts p
 where p.code = '21'
   and not exists (select 1 from public.fin_gl_accounts x where x.code = '2150');

alter table public.fin_gl_map drop constraint if exists fin_gl_map_key_check;
alter table public.fin_gl_map add constraint fin_gl_map_key_check
  check (key in ('payroll_expense', 'payroll_net', 'payroll_insurance', 'payroll_tax', 'payroll_other', 'payroll_loan', 'extract_payable'));

insert into public.fin_gl_map (key, account_id)
select 'extract_payable', a.id from public.fin_gl_accounts a where a.code = '2150'
on conflict (key) do nothing;

create or replace function public.fin_gl_map_set(p_key text, p_gl uuid)
returns void
language plpgsql security definer set search_path = public
as $$
declare g public.fin_gl_accounts; v_type text;
begin
  perform public.fin_need_approve();
  if p_key is null or p_key not in ('payroll_expense', 'payroll_net', 'payroll_insurance', 'payroll_tax', 'payroll_other', 'payroll_loan', 'extract_payable') then
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

-- ---------------------------------------------------------------------
-- 2. طلبات الصرف
-- ---------------------------------------------------------------------
create table if not exists public.fin_disbursements (
  id               uuid primary key default gen_random_uuid(),
  extract_id       uuid not null references public.contract_extracts (id) on delete restrict,
  project_id       uuid not null references public.projects (id) on delete restrict,
  amount           numeric(16, 3) not null check (amount > 0),
  account_id       uuid not null references public.fin_accounts (id) on delete restrict,
  pay_date         date not null,
  method           text not null default 'transfer' check (method in ('cheque', 'transfer', 'cash', 'other')),
  ref_no           text not null default '' check (length(ref_no) <= 60),
  note             text not null default '' check (length(note) <= 300),
  status           text not null default 'requested' check (status in ('requested', 'reviewed', 'returned', 'approved', 'rejected', 'cancelled', 'reversed')),
  requested_by     uuid references public.profiles (id) on delete set null,
  requested_at     timestamptz not null default now(),
  reviewed_by      uuid references public.profiles (id) on delete set null,
  reviewed_at      timestamptz,
  review_note      text not null default '' check (length(review_note) <= 300),
  decided_by       uuid references public.profiles (id) on delete set null,
  decided_at       timestamptz,
  decision_note    text not null default '' check (length(decision_note) <= 300),
  payment_id       uuid references public.extract_payments (id) on delete set null,
  journal_id       uuid references public.fin_journals (id) on delete set null,
  reversal_journal uuid references public.fin_journals (id) on delete set null,
  reverse_reason   text not null default '' check (length(reverse_reason) <= 300)
);
create index if not exists fin_disbursements_extract_idx on public.fin_disbursements (extract_id);
create index if not exists fin_disbursements_account_idx on public.fin_disbursements (account_id, status);
create index if not exists fin_disbursements_status_idx on public.fin_disbursements (status, requested_at);
create index if not exists fin_disbursements_project_idx on public.fin_disbursements (project_id);
create index if not exists fin_disbursements_requested_by_idx on public.fin_disbursements (requested_by);
create index if not exists fin_disbursements_reviewed_by_idx on public.fin_disbursements (reviewed_by);
create index if not exists fin_disbursements_decided_by_idx on public.fin_disbursements (decided_by);
create index if not exists fin_disbursements_payment_idx on public.fin_disbursements (payment_id);
create index if not exists fin_disbursements_journal_idx on public.fin_disbursements (journal_id);
create index if not exists fin_disbursements_reversal_idx on public.fin_disbursements (reversal_journal);

alter table public.fin_disbursements enable row level security;
drop policy if exists fin_disbursements_read on public.fin_disbursements;
create policy fin_disbursements_read on public.fin_disbursements for select to authenticated using (public.finance_can_view());
revoke all on public.fin_disbursements from anon;
revoke insert, update, delete, truncate on public.fin_disbursements from authenticated;
grant select on public.fin_disbursements to authenticated;
grant all on public.fin_disbursements to service_role;

do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime')
     and not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'fin_disbursements') then
    alter publication supabase_realtime add table public.fin_disbursements;
  end if;
end $$;

-- رصيد الحساب المالي: الافتتاحي + الوارد − الصادر من التحويلات المرحَّلة − الصرف المعتمد
create or replace function public.fin_account_balance(p_id uuid)
returns numeric
language sql stable security definer set search_path = public
as $$
  select a.opening
       + coalesce((select sum(amount) from public.fin_transfers where to_id = a.id and status = 'posted'), 0)
       - coalesce((select sum(amount) from public.fin_transfers where from_id = a.id and status = 'posted'), 0)
       - coalesce((select sum(amount) from public.fin_disbursements where account_id = a.id and status = 'approved'), 0)
    from public.fin_accounts a where a.id = p_id
$$;

-- المتبقي للصرف من المستخلص: صافيه − المدفوع الفعلي − الطلبات المفتوحة (مستثنىً منها طلب بعينه)
create or replace function public.fin_extract_remaining(p_extract uuid, p_except uuid default null)
returns numeric
language plpgsql stable security definer set search_path = public
as $$
declare
  e public.contract_extracts; v_n integer; v_sum numeric; v_open numeric;
begin
  select * into e from public.contract_extracts where id = p_extract;
  if not found then return 0; end if;
  select count(*), coalesce(sum(amount), 0) into v_n, v_sum from public.extract_payments where extract_id = e.id;
  if v_n = 0 then v_sum := e.paid_amount; end if;
  select coalesce(sum(amount), 0) into v_open from public.fin_disbursements
   where extract_id = e.id and status in ('requested', 'reviewed') and id is distinct from p_except;
  return round(e.net_amount - v_sum - v_open, 3);
end $$;

-- ---------------------------------------------------------------------
-- 3. المحتجز: تسجيل ضمان محتجز مرتبط بالمستخلص (بيد المحرر، لا تلقائياً)
-- ---------------------------------------------------------------------
create or replace function public.fin_guarantee_from_extract(p_extract uuid, p_party text)
returns uuid
language plpgsql security definer set search_path = public
as $$
declare
  e public.contract_extracts; v_id uuid; v_party text := btrim(coalesce(p_party, ''));
begin
  perform public.fin_need_edit();
  select * into e from public.contract_extracts where id = p_extract;
  if not found then raise exception 'المستخلص غير موجود' using errcode = 'P0002'; end if;
  if e.retention <= 0 then raise exception 'لا محتجز في هذا المستخلص' using errcode = '23514'; end if;
  if exists (select 1 from public.fin_guarantees where extract_id = e.id) then
    raise exception 'المحتجز مسجَّل لهذا المستخلص' using errcode = '23505';
  end if;
  if length(v_party) not between 1 and 120 then raise exception 'الجهة حتى 120 حرفاً' using errcode = '22023'; end if;
  insert into public.fin_guarantees (kind, project_id, party, amount, issued_on, reference, note, extract_id, created_by)
  values ('retention', e.project_id, v_party, e.retention, coalesce(e.approved_on, e.submitted_on, current_date),
          left(coalesce(nullif(e.ref_no, ''), 'مستخلص ' || e.seq), 80), 'محتجز مخصوم من المستخلص رقم ' || e.seq, e.id, auth.uid())
  returning id into v_id;
  perform public.write_audit('finance.guar_save', e.project_id, null,
    jsonb_build_object('kind', 'retention', 'party', v_party, 'amount', e.retention, 'created', true, 'extract', e.seq), v_party);
  return v_id;
end $$;

-- ---------------------------------------------------------------------
-- 4. دورة الصرف
-- ---------------------------------------------------------------------
create or replace function public.fin_disb_request(
  p_extract uuid, p_amount numeric, p_account uuid, p_date date, p_method text, p_ref text, p_note text)
returns uuid
language plpgsql security definer set search_path = public
as $$
declare
  e public.contract_extracts; a public.fin_accounts; v_id uuid; v_amt numeric := round(coalesce(p_amount, 0), 3);
begin
  perform public.fin_need_edit();
  select * into e from public.contract_extracts where id = p_extract;
  if not found then raise exception 'المستخلص غير موجود' using errcode = 'P0002'; end if;
  if e.status not in ('approved', 'referred') then
    raise exception 'يُطلب الصرف للمستخلص المعتمد أو المحال للصرف وغير المدفوع' using errcode = '23514';
  end if;
  if v_amt <= 0 then raise exception 'مبلغ الصرف أكبر من صفر' using errcode = '22023'; end if;
  if p_date is null then raise exception 'تاريخ الصرف مطلوب' using errcode = '22023'; end if;
  if coalesce(p_method, 'transfer') not in ('cheque', 'transfer', 'cash', 'other') then raise exception 'طريقة الدفع غير معروفة' using errcode = '22023'; end if;
  if length(coalesce(p_ref, '')) > 60 or length(coalesce(p_note, '')) > 300 then raise exception 'نص أطول من المسموح' using errcode = '22023'; end if;
  select * into a from public.fin_accounts where id = p_account;
  if not found or not a.active then raise exception 'الحساب المالي غير موجود أو موقوف' using errcode = '23514'; end if;
  if a.gl_account_id is null then raise exception 'اربط الحساب المالي بدليل الحسابات قبل الصرف منه' using errcode = '23514'; end if;
  if v_amt > public.fin_extract_remaining(e.id) then
    raise exception 'المبلغ أكبر من المتبقي للصرف (%)', public.fin_extract_remaining(e.id) using errcode = '23514';
  end if;
  insert into public.fin_disbursements (extract_id, project_id, amount, account_id, pay_date, method, ref_no, note, requested_by)
  values (e.id, e.project_id, v_amt, a.id, p_date, coalesce(p_method, 'transfer'), left(btrim(coalesce(p_ref, '')), 60), left(btrim(coalesce(p_note, '')), 300), auth.uid())
  returning id into v_id;
  perform public.write_audit('finance.disb_request', e.project_id, null,
    jsonb_build_object('extract', e.seq, 'amount', v_amt, 'account', a.name), 'مستخلص ' || e.seq);
  return v_id;
end $$;

create or replace function public.fin_disb_review(p_id uuid, p_ok boolean, p_note text)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  d public.fin_disbursements; e public.contract_extracts; v_n text := btrim(coalesce(p_note, ''));
begin
  perform public.fin_need_edit();
  select * into d from public.fin_disbursements where id = p_id;
  if not found then raise exception 'طلب الصرف غير موجود' using errcode = 'P0002'; end if;
  if d.status <> 'requested' then raise exception 'تُراجَع الطلبات الجديدة وحدها' using errcode = '23514'; end if;
  if length(v_n) > 300 then raise exception 'الملاحظة حتى 300 حرف' using errcode = '22023'; end if;
  select * into e from public.contract_extracts where id = d.extract_id;
  if p_ok then
    if e.status not in ('approved', 'referred') then raise exception 'المستخلص لم يعد قابلاً للصرف' using errcode = '23514'; end if;
    if e.retention > 0 and not exists (select 1 from public.fin_guarantees where extract_id = e.id) then
      raise exception 'سجّل المحتجز المخصوم (%) ضماناً محتجزاً مرتبطاً بالمستخلص قبل المراجعة', e.retention using errcode = '23514';
    end if;
    update public.fin_disbursements set status = 'reviewed', reviewed_by = auth.uid(), reviewed_at = now(), review_note = v_n where id = p_id;
    perform public.write_audit('finance.disb_review', d.project_id, null, jsonb_build_object('extract', e.seq, 'amount', d.amount), 'مستخلص ' || e.seq);
  else
    if length(v_n) < 3 then raise exception 'سبب الإعادة مطلوب (3 إلى 300 حرف)' using errcode = '22023'; end if;
    update public.fin_disbursements set status = 'returned', reviewed_by = auth.uid(), reviewed_at = now(), review_note = v_n where id = p_id;
    perform public.write_audit('finance.disb_return', d.project_id, null, jsonb_build_object('extract', e.seq, 'amount', d.amount, 'note', v_n), 'مستخلص ' || e.seq);
  end if;
end $$;

create or replace function public.fin_disb_cancel(p_id uuid)
returns void
language plpgsql security definer set search_path = public
as $$
declare d public.fin_disbursements; e public.contract_extracts;
begin
  perform public.fin_need_edit();
  select * into d from public.fin_disbursements where id = p_id;
  if not found then raise exception 'طلب الصرف غير موجود' using errcode = 'P0002'; end if;
  if d.status not in ('requested', 'reviewed') then raise exception 'يُلغى الطلب قبل اعتماده أو إعادته' using errcode = '23514'; end if;
  select * into e from public.contract_extracts where id = d.extract_id;
  update public.fin_disbursements set status = 'cancelled' where id = p_id;
  perform public.write_audit('finance.disb_cancel', d.project_id, null, jsonb_build_object('extract', e.seq, 'amount', d.amount), 'مستخلص ' || e.seq);
end $$;

create or replace function public.fin_disb_decide(p_id uuid, p_approve boolean, p_note text)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  d public.fin_disbursements; e public.contract_extracts; a public.fin_accounts; v_n text := btrim(coalesce(p_note, ''));
  v_pay uuid; v_jr uuid; v_payable uuid; v_cnt integer; v_sum numeric;
begin
  perform public.fin_need_approve();
  select * into d from public.fin_disbursements where id = p_id;
  if not found then raise exception 'طلب الصرف غير موجود' using errcode = 'P0002'; end if;
  if d.status <> 'reviewed' then raise exception 'يُعتمد الصرف بعد مراجعته المالية' using errcode = '23514'; end if;
  if length(v_n) > 300 then raise exception 'الملاحظة حتى 300 حرف' using errcode = '22023'; end if;
  select * into e from public.contract_extracts where id = d.extract_id;
  if not p_approve then
    if length(v_n) < 3 then raise exception 'سبب الرفض مطلوب (3 إلى 300 حرف)' using errcode = '22023'; end if;
    update public.fin_disbursements set status = 'rejected', decided_by = auth.uid(), decided_at = now(), decision_note = v_n where id = p_id;
    perform public.write_audit('finance.disb_reject', d.project_id, null, jsonb_build_object('extract', e.seq, 'amount', d.amount, 'note', v_n), 'مستخلص ' || e.seq);
    return;
  end if;
  if e.status not in ('approved', 'referred') then raise exception 'المستخلص لم يعد قابلاً للصرف' using errcode = '23514'; end if;
  select * into a from public.fin_accounts where id = d.account_id;
  if not a.active or a.gl_account_id is null then raise exception 'الحساب المالي موقوف أو غير مربوط بالدليل' using errcode = '23514'; end if;
  select account_id into v_payable from public.fin_gl_map where key = 'extract_payable';
  if v_payable is null then raise exception 'عيّن حساب مستحقات المقاولين في دليل الحسابات قبل اعتماد الصرف' using errcode = '23514'; end if;
  if d.amount > public.fin_extract_remaining(e.id, d.id) then
    raise exception 'المبلغ أكبر من المتبقي للصرف (%)', public.fin_extract_remaining(e.id, d.id) using errcode = '23514';
  end if;
  if public.fin_account_balance(a.id) < d.amount then
    raise exception 'رصيد «%» لا يكفي لهذا الصرف', a.name using errcode = '23514';
  end if;
  perform set_config('app.disbursing', 'on', true);
  select count(*), coalesce(sum(amount), 0) into v_cnt, v_sum from public.extract_payments where extract_id = e.id;
  if v_cnt = 0 and e.paid_amount > 0 then
    insert into public.extract_payments (extract_id, project_id, amount, paid_on, method, ref_no, notes, created_by)
    values (e.id, e.project_id, e.paid_amount, coalesce(e.paid_on, current_date), 'other', 'رصيد سابق', 'ما سُجّل مدفوعاً قبل سجل الدفعات', auth.uid());
  end if;
  insert into public.extract_payments (extract_id, project_id, amount, paid_on, method, ref_no, notes, created_by)
  values (e.id, e.project_id, d.amount, d.pay_date, d.method, d.ref_no, left('اعتماد صرف: ' || d.note, 1000), auth.uid())
  returning id into v_pay;
  v_jr := public.fin_journal_auto('disbursement', d.id, d.pay_date, left('صرف مستخلص رقم ' || e.seq || ' من ' || a.name, 300),
    jsonb_build_array(jsonb_build_object('account', v_payable, 'debit', d.amount, 'credit', 0, 'memo', 'مستحقات المقاول — مستخلص ' || e.seq),
                      jsonb_build_object('account', a.gl_account_id, 'debit', 0, 'credit', d.amount, 'memo', 'من ' || a.name)));
  perform set_config('app.disbursing', '', true);
  update public.fin_disbursements set status = 'approved', decided_by = auth.uid(), decided_at = now(), decision_note = v_n,
         payment_id = v_pay, journal_id = v_jr where id = p_id;
  perform public.write_audit('finance.disb_approve', d.project_id, null,
    jsonb_build_object('extract', e.seq, 'amount', d.amount, 'account', a.name), 'مستخلص ' || e.seq);
end $$;

create or replace function public.fin_disb_reverse(p_id uuid, p_reason text)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  d public.fin_disbursements; e public.contract_extracts; v_lines jsonb; v_new uuid; v_r text := btrim(coalesce(p_reason, ''));
begin
  perform public.fin_need_approve();
  if length(v_r) < 3 or length(v_r) > 300 then raise exception 'سبب العكس مطلوب (3 إلى 300 حرف)' using errcode = '22023'; end if;
  select * into d from public.fin_disbursements where id = p_id;
  if not found then raise exception 'طلب الصرف غير موجود' using errcode = 'P0002'; end if;
  if d.status <> 'approved' then raise exception 'يُعكس الصرف المعتمد وحده' using errcode = '23514'; end if;
  select * into e from public.contract_extracts where id = d.extract_id;
  perform set_config('app.disbursing', 'on', true);
  if d.payment_id is not null then delete from public.extract_payments where id = d.payment_id; end if;
  select jsonb_agg(jsonb_build_object('account', account_id, 'debit', credit, 'credit', debit, 'memo', memo) order by line_no) into v_lines
    from public.fin_journal_lines where journal_id = d.journal_id;
  v_new := public.fin_journal_auto('disbursement_reversal', d.id, current_date, left('عكس صرف مستخلص رقم ' || e.seq || ': ' || v_r, 300), v_lines, d.journal_id);
  perform set_config('app.disbursing', '', true);
  update public.fin_journals set reversed_by = v_new, reverse_reason = v_r where id = d.journal_id;
  update public.fin_disbursements set status = 'reversed', reversal_journal = v_new, reverse_reason = v_r, payment_id = null where id = p_id;
  perform public.write_audit('finance.disb_reverse', d.project_id, null,
    jsonb_build_object('extract', e.seq, 'amount', d.amount, 'reason', v_r), 'مستخلص ' || e.seq);
end $$;

-- ---------------------------------------------------------------------
-- 5. حارس: لا «مدفوع» ولا زيادة في المدفوع خارج دورة الصرف (إلا بيد مدير المكتب للسجل التاريخي)
-- ---------------------------------------------------------------------
create or replace function public.contract_extracts_paid_guard()
returns trigger
language plpgsql security definer set search_path = public
as $$
begin
  if coalesce(current_setting('app.disbursing', true), '') = 'on' or auth.uid() is null or public.is_director() then
    return new;
  end if;
  if tg_op = 'INSERT' then
    if new.status = 'paid' or new.paid_amount > 0 then
      raise exception 'المدفوع يُسجَّل عبر دورة «اعتماد الصرف» في المالية (طلب ثم مراجعة ثم اعتماد)' using errcode = '42501';
    end if;
  elsif (new.status = 'paid' and old.status <> 'paid') or new.paid_amount > old.paid_amount then
    raise exception 'المدفوع يُسجَّل عبر دورة «اعتماد الصرف» في المالية (طلب ثم مراجعة ثم اعتماد)' using errcode = '42501';
  end if;
  return new;
end $$;
drop trigger if exists contract_extracts_paid_guard on public.contract_extracts;
create trigger contract_extracts_paid_guard
  before insert or update on public.contract_extracts
  for each row execute function public.contract_extracts_paid_guard();

-- الدفعات المباشرة: لمدير المكتب وحده (للسجل التاريخي)
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
  if not public.is_director() then
    raise exception 'الصرف يُطلب من «اعتماد الصرف» في المالية: طلب ثم مراجعة مالية ثم اعتماد' using errcode = '42501';
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
  if exists (select 1 from public.fin_disbursements where payment_id = p_id and status = 'approved') then
    raise exception 'دفعة صرف معتمد؛ تُعكس من «اعتماد الصرف» لا من حذف الدفعة' using errcode = '23514';
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
-- 6. الصلاحيات
-- ---------------------------------------------------------------------
revoke execute on function
  public.fin_extract_remaining(uuid, uuid), public.fin_guarantee_from_extract(uuid, text),
  public.fin_disb_request(uuid, numeric, uuid, date, text, text, text), public.fin_disb_review(uuid, boolean, text),
  public.fin_disb_cancel(uuid), public.fin_disb_decide(uuid, boolean, text), public.fin_disb_reverse(uuid, text),
  public.fin_gl_map_set(text, uuid), public.add_extract_payment(uuid, numeric, date, text, text, text), public.delete_extract_payment(uuid)
from public, anon;
grant execute on function
  public.fin_extract_remaining(uuid, uuid), public.fin_guarantee_from_extract(uuid, text),
  public.fin_disb_request(uuid, numeric, uuid, date, text, text, text), public.fin_disb_review(uuid, boolean, text),
  public.fin_disb_cancel(uuid), public.fin_disb_decide(uuid, boolean, text), public.fin_disb_reverse(uuid, text),
  public.fin_gl_map_set(text, uuid), public.add_extract_payment(uuid, numeric, date, text, text, text), public.delete_extract_payment(uuid)
to authenticated, service_role;
revoke execute on function public.contract_extracts_paid_guard() from public, anon, authenticated;
