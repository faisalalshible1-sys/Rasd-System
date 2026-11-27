-- =====================================================================
-- الإصدار 3.0.0 (الترحيل 47): المالية والمرتبات — النسب والخصومات والصلاحيات
--
--  finance_rates: نسب مالية بإصدارات (ضريبة الدخل، التأمينات، قاعدة الإضافة) بتاريخ سريان وسبب وسجل كامل؛
--    التغيير يضيف إصداراً جديداً ويغلق السابق ولا يعدّل القديم. لكل نسبة أساس احتساب ونطاق تطبيق صريحان،
--    ولا تُطبَّق نسبة تلقائياً على كل العقود دون نطاق محدد.
--  finance_deductions: دليل الخصومات (اسم، نوع نسبة/ثابت، قيمة، أساس، مجال).
--  finance_permissions: صلاحيات المالية المستقلة (اطّلاع/تحرير/اعتماد) تمنحها المدير فوق الأدوار القائمة.
--  القراءة لمن له اطّلاع مالي، والكتابة بدوال تسجّل في سجل التدقيق، ولا كتابة مباشرة.
--  يُشغَّل بعد 20261207000046_budget.sql، وإعادة تشغيله آمنة. التراجع: supabase/rollbacks/20261208000047_finance_settings_down.sql
-- =====================================================================
create table if not exists public.finance_rates (
  id             uuid primary key default gen_random_uuid(),
  code           text not null check (code in ('income_tax', 'insurance', 'extra_rule')),
  percent        numeric(7, 4) not null check (percent >= 0 and percent <= 100),
  basis          text not null check (basis in ('extract_gross', 'extract_net', 'contract_value', 'payroll_basic', 'payroll_gross')),
  scope          text not null check (scope in ('contracts', 'employees', 'selected')),
  active         boolean not null default true,
  effective_from date not null,
  effective_to   date,
  reason         text not null default '' check (length(reason) <= 300),
  created_at     timestamptz not null default now(),
  created_by     uuid references public.profiles (id) on delete set null,
  check (effective_to is null or effective_to >= effective_from)
);
create unique index if not exists finance_rates_ver_uidx on public.finance_rates (code, effective_from);
create index if not exists finance_rates_created_by_idx on public.finance_rates (created_by);

create table if not exists public.finance_deductions (
  id         uuid primary key default gen_random_uuid(),
  name       text not null check (length(btrim(name)) between 1 and 80),
  kind       text not null check (kind in ('percent', 'fixed')),
  value      numeric(18, 4) not null check (value >= 0),
  basis      text not null default 'payroll_gross' check (basis in ('extract_gross', 'extract_net', 'contract_value', 'payroll_basic', 'payroll_gross', 'none')),
  applies_to text not null default 'payroll' check (applies_to in ('payroll', 'contracts', 'both')),
  active     boolean not null default true,
  note       text not null default '' check (length(note) <= 300),
  created_at timestamptz not null default now(),
  created_by uuid references public.profiles (id) on delete set null,
  updated_at timestamptz not null default now(),
  updated_by uuid references public.profiles (id) on delete set null,
  check (kind <> 'percent' or value <= 100)
);
create unique index if not exists finance_deductions_name_uidx on public.finance_deductions (lower(btrim(name)));
create index if not exists finance_deductions_created_by_idx on public.finance_deductions (created_by);
create index if not exists finance_deductions_updated_by_idx on public.finance_deductions (updated_by);

create table if not exists public.finance_permissions (
  user_id    uuid not null references public.profiles (id) on delete cascade,
  perm       text not null check (perm in ('view', 'edit', 'approve')),
  granted_at timestamptz not null default now(),
  granted_by uuid references public.profiles (id) on delete set null,
  primary key (user_id, perm)
);
create index if not exists finance_permissions_granted_by_idx on public.finance_permissions (granted_by);

-- الصلاحيات
create or replace function public.finance_has(p_perm text)
returns boolean
language sql stable security definer set search_path = public
as $$
  select coalesce(public.my_role()::text = 'director', false)
      or exists (select 1 from public.finance_permissions where user_id = auth.uid() and perm = p_perm)
$$;

create or replace function public.finance_can_view()
returns boolean
language sql stable security definer set search_path = public
as $$
  select coalesce(public.my_role()::text in ('director', 'office_staff'), false)
      or exists (select 1 from public.finance_permissions where user_id = auth.uid())
$$;

create or replace function public.finance_can_edit()
returns boolean
language sql stable security definer set search_path = public
as $$ select public.finance_has('edit') and public.writes_allowed() $$;

create or replace function public.finance_can_approve()
returns boolean
language sql stable security definer set search_path = public
as $$ select public.finance_has('approve') and public.writes_allowed() $$;

alter table public.finance_rates enable row level security;
alter table public.finance_deductions enable row level security;
alter table public.finance_permissions enable row level security;
drop policy if exists finance_rates_read on public.finance_rates;
create policy finance_rates_read on public.finance_rates for select to authenticated using ((select public.finance_can_view()));
drop policy if exists finance_deductions_read on public.finance_deductions;
create policy finance_deductions_read on public.finance_deductions for select to authenticated using ((select public.finance_can_view()));
drop policy if exists finance_permissions_read on public.finance_permissions;
create policy finance_permissions_read on public.finance_permissions for select to authenticated
  using ((select public.my_role()::text = 'director') or user_id = (select auth.uid()));

revoke all on public.finance_rates, public.finance_deductions, public.finance_permissions from anon;
revoke insert, update, delete, truncate on public.finance_rates, public.finance_deductions, public.finance_permissions from authenticated;
grant select on public.finance_rates, public.finance_deductions, public.finance_permissions to authenticated;
grant all on public.finance_rates, public.finance_deductions, public.finance_permissions to service_role;

-- حفظ نسبة بإصدار جديد
create or replace function public.finance_rate_save(
  p_code text, p_percent numeric, p_basis text, p_scope text, p_from date, p_reason text, p_active boolean default true)
returns uuid
language plpgsql security definer set search_path = public
as $$
declare
  v_id uuid;
  v_last date;
begin
  if not public.finance_can_edit() then
    raise exception 'تعديل النسب المالية لمن يملك صلاحية التحرير' using errcode = '42501';
  end if;
  if p_code not in ('income_tax', 'insurance', 'extra_rule') then
    raise exception 'نسبة غير معروفة' using errcode = '22023';
  end if;
  if p_percent is null or p_percent < 0 or p_percent > 100 then
    raise exception 'النسبة بين 0 و100' using errcode = '22023';
  end if;
  if p_basis is null or p_basis not in ('extract_gross', 'extract_net', 'contract_value', 'payroll_basic', 'payroll_gross') then
    raise exception 'أساس الاحتساب غير صالح' using errcode = '22023';
  end if;
  if p_scope is null or p_scope not in ('contracts', 'employees', 'selected') then
    raise exception 'نطاق التطبيق غير صالح' using errcode = '22023';
  end if;
  if p_from is null then
    raise exception 'تاريخ السريان مطلوب' using errcode = '22023';
  end if;
  if length(btrim(coalesce(p_reason, ''))) < 3 or length(p_reason) > 300 then
    raise exception 'سبب التغيير مطلوب (3 إلى 300 حرف)' using errcode = '22023';
  end if;
  select max(effective_from) into v_last from public.finance_rates where code = p_code;
  if v_last is not null and p_from <= v_last then
    raise exception 'تاريخ السريان يجب أن يلي آخر إصدار (%)', v_last using errcode = '23514';
  end if;
  update public.finance_rates set effective_to = p_from - 1 where code = p_code and effective_to is null;
  insert into public.finance_rates (code, percent, basis, scope, active, effective_from, reason, created_by)
  values (p_code, p_percent, p_basis, p_scope, coalesce(p_active, true), p_from, btrim(p_reason), auth.uid())
  returning id into v_id;
  perform public.write_audit('finance.rate_save', null, null,
    jsonb_build_object('code', p_code, 'percent', p_percent, 'basis', p_basis, 'scope', p_scope, 'from', p_from, 'active', coalesce(p_active, true), 'reason', btrim(p_reason)), p_code);
  return v_id;
end;
$$;

create or replace function public.finance_deduction_save(
  p_id uuid, p_name text, p_kind text, p_value numeric, p_basis text, p_applies text, p_active boolean default true, p_note text default '')
returns uuid
language plpgsql security definer set search_path = public
as $$
declare
  v_id uuid := p_id;
  v_name text := btrim(coalesce(p_name, ''));
begin
  if not public.finance_can_edit() then
    raise exception 'تعديل الخصومات لمن يملك صلاحية التحرير' using errcode = '42501';
  end if;
  if length(v_name) not between 1 and 80 then
    raise exception 'اسم الخصم حتى 80 حرفاً' using errcode = '22023';
  end if;
  if p_kind is null or p_kind not in ('percent', 'fixed') then
    raise exception 'نوع الخصم نسبة أو ثابت' using errcode = '22023';
  end if;
  if p_value is null or p_value < 0 or (p_kind = 'percent' and p_value > 100) then
    raise exception 'قيمة الخصم غير صالحة' using errcode = '22023';
  end if;
  if p_basis is null or p_basis not in ('extract_gross', 'extract_net', 'contract_value', 'payroll_basic', 'payroll_gross', 'none') then
    raise exception 'أساس الخصم غير صالح' using errcode = '22023';
  end if;
  if p_kind = 'percent' and p_basis = 'none' then
    raise exception 'خصم النسبة يحتاج أساساً يُحسب عليه' using errcode = '22023';
  end if;
  if p_applies is null or p_applies not in ('payroll', 'contracts', 'both') then
    raise exception 'مجال الخصم غير صالح' using errcode = '22023';
  end if;
  if length(coalesce(p_note, '')) > 300 then
    raise exception 'الملاحظة أطول من 300 حرف' using errcode = '22023';
  end if;
  if exists (select 1 from public.finance_deductions where lower(btrim(name)) = lower(v_name) and id is distinct from p_id) then
    raise exception 'يوجد خصم بهذا الاسم' using errcode = '23505';
  end if;
  if p_id is null then
    insert into public.finance_deductions (name, kind, value, basis, applies_to, active, note, created_by, updated_by)
    values (v_name, p_kind, p_value, p_basis, p_applies, coalesce(p_active, true), coalesce(p_note, ''), auth.uid(), auth.uid())
    returning id into v_id;
  else
    if not exists (select 1 from public.finance_deductions where id = p_id) then
      raise exception 'الخصم غير موجود' using errcode = 'P0002';
    end if;
    update public.finance_deductions set name = v_name, kind = p_kind, value = p_value, basis = p_basis,
           applies_to = p_applies, active = coalesce(p_active, true), note = coalesce(p_note, ''),
           updated_at = now(), updated_by = auth.uid()
     where id = p_id;
  end if;
  perform public.write_audit('finance.deduction_save', null, null,
    jsonb_build_object('id', v_id, 'name', v_name, 'kind', p_kind, 'value', p_value, 'basis', p_basis, 'applies', p_applies, 'active', coalesce(p_active, true), 'created', p_id is null), v_name);
  return v_id;
end;
$$;

create or replace function public.finance_deduction_delete(p_id uuid)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  d public.finance_deductions;
begin
  if not public.finance_can_edit() then
    raise exception 'تعديل الخصومات لمن يملك صلاحية التحرير' using errcode = '42501';
  end if;
  select * into d from public.finance_deductions where id = p_id;
  if not found then
    raise exception 'الخصم غير موجود' using errcode = 'P0002';
  end if;
  delete from public.finance_deductions where id = p_id;
  perform public.write_audit('finance.deduction_delete', null, null,
    jsonb_build_object('id', p_id, 'name', d.name, 'kind', d.kind, 'value', d.value), d.name);
end;
$$;

-- منح صلاحية مالية أو سحبها (المدير وحده)
create or replace function public.finance_perm_set(p_user uuid, p_perm text, p_on boolean)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  v_name text;
begin
  if not (coalesce(public.my_role()::text = 'director', false) and public.writes_allowed()) then
    raise exception 'منح الصلاحيات المالية للمدير وحده' using errcode = '42501';
  end if;
  if p_perm is null or p_perm not in ('view', 'edit', 'approve') then
    raise exception 'صلاحية غير معروفة' using errcode = '22023';
  end if;
  select coalesce(nullif(btrim(full_name), ''), email) into v_name from public.profiles where id = p_user;
  if not found then
    raise exception 'المستخدم غير موجود' using errcode = 'P0002';
  end if;
  if coalesce(p_on, false) then
    insert into public.finance_permissions (user_id, perm, granted_by) values (p_user, p_perm, auth.uid())
    on conflict (user_id, perm) do nothing;
  else
    delete from public.finance_permissions where user_id = p_user and perm = p_perm;
  end if;
  perform public.write_audit('finance.perm_set', null, null,
    jsonb_build_object('user', p_user, 'name', v_name, 'perm', p_perm, 'on', coalesce(p_on, false)), v_name);
end;
$$;

revoke execute on function public.finance_rate_save(text, numeric, text, text, date, text, boolean) from public, anon;
revoke execute on function public.finance_deduction_save(uuid, text, text, numeric, text, text, boolean, text) from public, anon;
revoke execute on function public.finance_deduction_delete(uuid) from public, anon;
revoke execute on function public.finance_perm_set(uuid, text, boolean) from public, anon;
grant execute on function public.finance_rate_save(text, numeric, text, text, date, text, boolean) to authenticated;
grant execute on function public.finance_deduction_save(uuid, text, text, numeric, text, text, boolean, text) to authenticated;
grant execute on function public.finance_deduction_delete(uuid) to authenticated;
grant execute on function public.finance_perm_set(uuid, text, boolean) to authenticated;

-- الإصدارات الابتدائية (تُدرج مرة واحدة فقط، ولا تُطبَّق خارج نطاقها المحدد)
insert into public.finance_rates (code, percent, basis, scope, active, effective_from, reason)
select 'income_tax', 3, 'extract_gross', 'contracts', true, date '2026-01-01', 'النسبة المعتمدة عند التأسيس'
where not exists (select 1 from public.finance_rates where code = 'income_tax');
insert into public.finance_rates (code, percent, basis, scope, active, effective_from, reason)
select 'insurance', 5, 'payroll_basic', 'employees', true, date '2026-01-01', 'النسبة المعتمدة عند التأسيس'
where not exists (select 1 from public.finance_rates where code = 'insurance');
insert into public.finance_rates (code, percent, basis, scope, active, effective_from, reason)
select 'extra_rule', 3.75, 'extract_gross', 'selected', false, date '2026-01-01', 'معطّلة حتى يحدد المدير النطاق والأساس'
where not exists (select 1 from public.finance_rates where code = 'extra_rule');
