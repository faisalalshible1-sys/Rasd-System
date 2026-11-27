-- =====================================================================
-- الإصدار 3.2.0 (الترحيل 49): الضمانات والتأمينات النقدية والتحويلات والاستردادات
--
--  fin_guarantees: سجل الضمانات (ابتدائي ونهائي ومحتجز وتأمين نقدي) بمبلغ وجهة وتاريخ إصدار وانتهاء، ويمكن ربطه بعقد.
--      الدورة: محتجز ← طلب استرداد (بسبب) ← استرداد بموافقة من يملك الاعتماد، أو رفض يعيده محتجزاً. لا ضمان يُسترد دون اعتماد.
--      لا مبلغ ولا نسبة تُطبَّق تلقائياً من العقود؛ المحرر هو من يسجّل ويؤكد.
--  fin_accounts: حسابات مالية (نقدية أو مصرفية) برصيد افتتاحي.
--  fin_transfers: تحويلات بين الحسابات: معلّق ← مرحَّل بموافقة من يملك الاعتماد (يُرفض إن زاد عن الرصيد) أو مرفوض.
--  الرصيد = الافتتاحي + المرحَّل وارداً − المرحَّل صادراً (fin_account_balance).
--  القراءة لمن له اطّلاع مالي، والتحرير بصلاحية التحرير، والموافقات بصلاحية الاعتماد، بدوال تسجّل في سجل التدقيق.
--  يُشغَّل بعد 20261209000048_payroll.sql، وإعادة تشغيله آمنة. التراجع: supabase/rollbacks/20261210000049_guarantees_down.sql
-- =====================================================================
create table if not exists public.fin_guarantees (
  id                   uuid primary key default gen_random_uuid(),
  kind                 text not null check (kind in ('initial', 'final', 'retention', 'deposit')),
  project_id           uuid references public.projects (id) on delete set null,
  party                text not null check (length(btrim(party)) between 1 and 120),
  amount               numeric(18, 3) not null check (amount > 0),
  issued_on            date not null,
  expires_on           date,
  reference            text not null default '' check (length(reference) <= 80),
  note                 text not null default '' check (length(note) <= 300),
  status               text not null default 'held' check (status in ('held', 'release_requested', 'released')),
  release_reason       text not null default '' check (length(release_reason) <= 300),
  release_requested_at timestamptz,
  release_requested_by uuid references public.profiles (id) on delete set null,
  released_at          timestamptz,
  released_by          uuid references public.profiles (id) on delete set null,
  decision_note        text not null default '' check (length(decision_note) <= 300),
  created_at           timestamptz not null default now(),
  created_by           uuid references public.profiles (id) on delete set null,
  check (expires_on is null or expires_on >= issued_on)
);
create index if not exists fin_guarantees_project_idx on public.fin_guarantees (project_id);
create index if not exists fin_guarantees_status_idx on public.fin_guarantees (status);
create index if not exists fin_guarantees_created_by_idx on public.fin_guarantees (created_by);
create index if not exists fin_guarantees_req_by_idx on public.fin_guarantees (release_requested_by);
create index if not exists fin_guarantees_rel_by_idx on public.fin_guarantees (released_by);

create table if not exists public.fin_accounts (
  id         uuid primary key default gen_random_uuid(),
  name       text not null check (length(btrim(name)) between 1 and 80),
  kind       text not null default 'bank' check (kind in ('cash', 'bank')),
  opening    numeric(18, 3) not null default 0 check (opening >= 0),
  active     boolean not null default true,
  created_at timestamptz not null default now(),
  created_by uuid references public.profiles (id) on delete set null
);
create unique index if not exists fin_accounts_name_uidx on public.fin_accounts (lower(btrim(name)));
create index if not exists fin_accounts_created_by_idx on public.fin_accounts (created_by);

create table if not exists public.fin_transfers (
  id            uuid primary key default gen_random_uuid(),
  from_id       uuid not null references public.fin_accounts (id) on delete restrict,
  to_id         uuid not null references public.fin_accounts (id) on delete restrict,
  amount        numeric(18, 3) not null check (amount > 0),
  on_date       date not null,
  note          text not null default '' check (length(note) <= 300),
  status        text not null default 'pending' check (status in ('pending', 'posted', 'rejected')),
  decision_note text not null default '' check (length(decision_note) <= 300),
  created_at    timestamptz not null default now(),
  created_by    uuid references public.profiles (id) on delete set null,
  decided_at    timestamptz,
  decided_by    uuid references public.profiles (id) on delete set null,
  check (from_id <> to_id)
);
create index if not exists fin_transfers_from_idx on public.fin_transfers (from_id);
create index if not exists fin_transfers_to_idx on public.fin_transfers (to_id);
create index if not exists fin_transfers_created_by_idx on public.fin_transfers (created_by);
create index if not exists fin_transfers_decided_by_idx on public.fin_transfers (decided_by);

do $$
declare t text;
begin
  foreach t in array array['fin_guarantees', 'fin_accounts', 'fin_transfers'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('drop policy if exists %I on public.%I', t || '_read', t);
    execute format('create policy %I on public.%I for select to authenticated using ((select public.finance_can_view()))', t || '_read', t);
    execute format('revoke all on public.%I from anon', t);
    execute format('revoke insert, update, delete, truncate on public.%I from authenticated', t);
    execute format('grant select on public.%I to authenticated', t);
    execute format('grant all on public.%I to service_role', t);
  end loop;
end $$;

create or replace function public.fin_need_approve()
returns void
language plpgsql stable security definer set search_path = public
as $$
begin
  if not public.finance_can_approve() then
    raise exception 'الموافقة لمن يملك صلاحية الاعتماد' using errcode = '42501';
  end if;
end $$;

-- رصيد حساب: الافتتاحي + المرحَّل وارداً − المرحَّل صادراً
create or replace function public.fin_account_balance(p_id uuid)
returns numeric
language sql stable security definer set search_path = public
as $$
  select a.opening
       + coalesce((select sum(amount) from public.fin_transfers where to_id = a.id and status = 'posted'), 0)
       - coalesce((select sum(amount) from public.fin_transfers where from_id = a.id and status = 'posted'), 0)
    from public.fin_accounts a where a.id = p_id
$$;

-- الضمانات
create or replace function public.fin_guarantee_save(
  p_id uuid, p_kind text, p_project uuid, p_party text, p_amount numeric, p_issued date,
  p_expires date default null, p_ref text default '', p_note text default '')
returns uuid
language plpgsql security definer set search_path = public
as $$
declare v_id uuid := p_id; v_party text := btrim(coalesce(p_party, '')); g public.fin_guarantees;
begin
  perform public.fin_need_edit();
  if p_kind is null or p_kind not in ('initial', 'final', 'retention', 'deposit') then raise exception 'نوع ضمان غير صالح' using errcode = '22023'; end if;
  if length(v_party) not between 1 and 120 then raise exception 'الجهة حتى 120 حرفاً' using errcode = '22023'; end if;
  if p_amount is null or p_amount <= 0 then raise exception 'مبلغ الضمان أكبر من صفر' using errcode = '22023'; end if;
  if p_issued is null then raise exception 'تاريخ الإصدار مطلوب' using errcode = '22023'; end if;
  if p_expires is not null and p_expires < p_issued then raise exception 'الانتهاء قبل الإصدار' using errcode = '22023'; end if;
  if length(coalesce(p_ref, '')) > 80 or length(coalesce(p_note, '')) > 300 then raise exception 'نص أطول من المسموح' using errcode = '22023'; end if;
  if p_project is not null and not exists (select 1 from public.projects where id = p_project) then
    raise exception 'العقد غير موجود' using errcode = 'P0002';
  end if;
  if p_id is null then
    insert into public.fin_guarantees (kind, project_id, party, amount, issued_on, expires_on, reference, note, created_by)
    values (p_kind, p_project, v_party, p_amount, p_issued, p_expires, coalesce(p_ref, ''), coalesce(p_note, ''), auth.uid())
    returning id into v_id;
  else
    select * into g from public.fin_guarantees where id = p_id;
    if not found then raise exception 'الضمان غير موجود' using errcode = 'P0002'; end if;
    if g.status <> 'held' then raise exception 'لا يُعدَّل ضمان طُلب استرداده أو استُرد' using errcode = '23514'; end if;
    update public.fin_guarantees set kind = p_kind, project_id = p_project, party = v_party, amount = p_amount, issued_on = p_issued,
           expires_on = p_expires, reference = coalesce(p_ref, ''), note = coalesce(p_note, '') where id = p_id;
  end if;
  perform public.write_audit('finance.guar_save', p_project, null,
    jsonb_build_object('kind', p_kind, 'party', v_party, 'amount', p_amount, 'created', p_id is null), v_party);
  return v_id;
end $$;

create or replace function public.fin_guarantee_delete(p_id uuid)
returns void
language plpgsql security definer set search_path = public
as $$
declare g public.fin_guarantees;
begin
  perform public.fin_need_edit();
  select * into g from public.fin_guarantees where id = p_id;
  if not found then raise exception 'الضمان غير موجود' using errcode = 'P0002'; end if;
  if g.status <> 'held' then raise exception 'لا يُحذف ضمان طُلب استرداده أو استُرد' using errcode = '23514'; end if;
  delete from public.fin_guarantees where id = p_id;
  perform public.write_audit('finance.guar_delete', g.project_id, null,
    jsonb_build_object('kind', g.kind, 'party', g.party, 'amount', g.amount), g.party);
end $$;

create or replace function public.fin_guarantee_release_request(p_id uuid, p_reason text)
returns void
language plpgsql security definer set search_path = public
as $$
declare g public.fin_guarantees; v_r text := btrim(coalesce(p_reason, ''));
begin
  perform public.fin_need_edit();
  if length(v_r) not between 3 and 300 then raise exception 'سبب الاسترداد من 3 إلى 300 حرف' using errcode = '22023'; end if;
  select * into g from public.fin_guarantees where id = p_id;
  if not found then raise exception 'الضمان غير موجود' using errcode = 'P0002'; end if;
  if g.status <> 'held' then raise exception 'يُطلب استرداد الضمان المحتجز وحده' using errcode = '23514'; end if;
  update public.fin_guarantees set status = 'release_requested', release_reason = v_r, release_requested_at = now(),
         release_requested_by = auth.uid(), decision_note = '' where id = p_id;
  perform public.write_audit('finance.guar_release_request', g.project_id, null,
    jsonb_build_object('kind', g.kind, 'party', g.party, 'amount', g.amount, 'reason', v_r), g.party);
end $$;

create or replace function public.fin_guarantee_release_decide(p_id uuid, p_approve boolean, p_note text default '')
returns void
language plpgsql security definer set search_path = public
as $$
declare g public.fin_guarantees; v_n text := btrim(coalesce(p_note, ''));
begin
  perform public.fin_need_approve();
  if p_approve is null then raise exception 'حدّد الموافقة أو الرفض' using errcode = '22023'; end if;
  if length(v_n) > 300 then raise exception 'الملاحظة أطول من 300 حرف' using errcode = '22023'; end if;
  if not p_approve and length(v_n) < 3 then raise exception 'سبب الرفض مطلوب (3 أحرف فأكثر)' using errcode = '22023'; end if;
  select * into g from public.fin_guarantees where id = p_id;
  if not found then raise exception 'الضمان غير موجود' using errcode = 'P0002'; end if;
  if g.status <> 'release_requested' then raise exception 'لا طلب استرداد معلّق لهذا الضمان' using errcode = '23514'; end if;
  if p_approve then
    update public.fin_guarantees set status = 'released', released_at = now(), released_by = auth.uid(), decision_note = v_n where id = p_id;
  else
    update public.fin_guarantees set status = 'held', decision_note = v_n where id = p_id;
  end if;
  perform public.write_audit(case when p_approve then 'finance.guar_release_approve' else 'finance.guar_release_reject' end, g.project_id, null,
    jsonb_build_object('kind', g.kind, 'party', g.party, 'amount', g.amount, 'note', v_n), g.party);
end $$;

-- الحسابات
create or replace function public.fin_account_save(p_id uuid, p_name text, p_kind text, p_opening numeric, p_active boolean default true)
returns uuid
language plpgsql security definer set search_path = public
as $$
declare v_id uuid := p_id; v_name text := btrim(coalesce(p_name, ''));
begin
  perform public.fin_need_edit();
  if length(v_name) not between 1 and 80 then raise exception 'اسم الحساب حتى 80 حرفاً' using errcode = '22023'; end if;
  if p_kind is null or p_kind not in ('cash', 'bank') then raise exception 'نوع حساب غير صالح' using errcode = '22023'; end if;
  if p_opening is null or p_opening < 0 then raise exception 'الرصيد الافتتاحي مبلغ غير سالب' using errcode = '22023'; end if;
  if exists (select 1 from public.fin_accounts where lower(btrim(name)) = lower(v_name) and id is distinct from p_id) then
    raise exception 'يوجد حساب بهذا الاسم' using errcode = '23505';
  end if;
  if p_id is null then
    insert into public.fin_accounts (name, kind, opening, active, created_by) values (v_name, p_kind, p_opening, coalesce(p_active, true), auth.uid())
    returning id into v_id;
  else
    if exists (select 1 from public.fin_transfers where (from_id = p_id or to_id = p_id) and status = 'posted')
       and p_opening is distinct from (select opening from public.fin_accounts where id = p_id) then
      raise exception 'لا يُعدَّل الرصيد الافتتاحي لحساب عليه تحويلات مرحَّلة' using errcode = '23514';
    end if;
    update public.fin_accounts set name = v_name, kind = p_kind, opening = p_opening, active = coalesce(p_active, true) where id = p_id;
    if not found then raise exception 'الحساب غير موجود' using errcode = 'P0002'; end if;
  end if;
  perform public.write_audit('finance.acct_save', null, null,
    jsonb_build_object('name', v_name, 'kind', p_kind, 'opening', p_opening, 'created', p_id is null), v_name);
  return v_id;
end $$;

create or replace function public.fin_account_delete(p_id uuid)
returns void
language plpgsql security definer set search_path = public
as $$
declare a public.fin_accounts;
begin
  perform public.fin_need_edit();
  select * into a from public.fin_accounts where id = p_id;
  if not found then raise exception 'الحساب غير موجود' using errcode = 'P0002'; end if;
  if exists (select 1 from public.fin_transfers where from_id = p_id or to_id = p_id) then
    raise exception 'عليه تحويلات؛ أوقفه بدل حذفه' using errcode = '23503';
  end if;
  delete from public.fin_accounts where id = p_id;
  perform public.write_audit('finance.acct_delete', null, null, jsonb_build_object('name', a.name), a.name);
end $$;

-- التحويلات
create or replace function public.fin_transfer_create(p_from uuid, p_to uuid, p_amount numeric, p_date date, p_note text default '')
returns uuid
language plpgsql security definer set search_path = public
as $$
declare v_id uuid; f public.fin_accounts; t public.fin_accounts;
begin
  perform public.fin_need_edit();
  if p_from is null or p_to is null or p_from = p_to then raise exception 'اختر حسابين مختلفين' using errcode = '22023'; end if;
  if p_amount is null or p_amount <= 0 then raise exception 'مبلغ التحويل أكبر من صفر' using errcode = '22023'; end if;
  if p_date is null then raise exception 'تاريخ التحويل مطلوب' using errcode = '22023'; end if;
  if length(coalesce(p_note, '')) > 300 then raise exception 'الملاحظة أطول من 300 حرف' using errcode = '22023'; end if;
  select * into f from public.fin_accounts where id = p_from;
  select * into t from public.fin_accounts where id = p_to;
  if f.id is null or t.id is null then raise exception 'الحساب غير موجود' using errcode = 'P0002'; end if;
  if not f.active or not t.active then raise exception 'لا تحويل من حساب موقوف أو إليه' using errcode = '23514'; end if;
  insert into public.fin_transfers (from_id, to_id, amount, on_date, note, created_by)
  values (p_from, p_to, p_amount, p_date, coalesce(p_note, ''), auth.uid()) returning id into v_id;
  perform public.write_audit('finance.transfer_create', null, null,
    jsonb_build_object('from', f.name, 'to', t.name, 'amount', p_amount, 'date', p_date), f.name || ' ← ' || t.name);
  return v_id;
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

create or replace function public.fin_transfer_delete(p_id uuid)
returns void
language plpgsql security definer set search_path = public
as $$
declare x public.fin_transfers; f text; t text;
begin
  perform public.fin_need_edit();
  select * into x from public.fin_transfers where id = p_id;
  if not found then raise exception 'التحويل غير موجود' using errcode = 'P0002'; end if;
  if x.status <> 'pending' then raise exception 'يُحذف التحويل المعلّق وحده' using errcode = '23514'; end if;
  select name into f from public.fin_accounts where id = x.from_id;
  select name into t from public.fin_accounts where id = x.to_id;
  delete from public.fin_transfers where id = p_id;
  perform public.write_audit('finance.transfer_delete', null, null,
    jsonb_build_object('from', f, 'to', t, 'amount', x.amount), f || ' ← ' || t);
end $$;

do $$
declare f record;
begin
  for f in select p.oid::regprocedure as sig from pg_proc p
            where p.pronamespace = 'public'::regnamespace
              and p.proname in ('fin_need_approve', 'fin_account_balance', 'fin_guarantee_save', 'fin_guarantee_delete',
                                'fin_guarantee_release_request', 'fin_guarantee_release_decide', 'fin_account_save',
                                'fin_account_delete', 'fin_transfer_create', 'fin_transfer_decide', 'fin_transfer_delete') loop
    execute format('revoke all on function %s from public, anon', f.sig);
    execute format('grant execute on function %s to authenticated, service_role', f.sig);
  end loop;
end $$;
