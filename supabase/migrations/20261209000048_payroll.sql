-- =====================================================================
-- الإصدار 3.1.0 (الترحيل 48): المرتبات والموظفون والحضور والمكافآت والسلف
--
--  fin_employees: سجل الموظفين المالي (الأساسي وتاريخ التعيين والحالة وأعلام التأمين والضريبة والقاعدة الإضافية).
--  fin_allowances / fin_emp_deductions: البدلات الثابتة وإسناد خصومات الدليل للموظف.
--  fin_attendance (يومي) و fin_attendance_month (شهري): للشهر ملخص يدوي يغلب اليومي إن وُجد.
--  fin_bonuses والسلف fin_loans (قسط ثابت بلا نسبة) وإعدادات fin_config (30 يوماً و42 ساعة أسبوعياً ومعامل الإضافي).
--  fin_payrolls / fin_payroll_lines: كشف شهري بلقطة لكل موظف: مسودة ← معتمد ← مقفل، ولا يُعدَّل إلا بتراجع مسجَّل بسبب.
--  النسب من finance_rates السارية آخر الشهر: لا تُطبَّق نسبة إلا بنطاق «الموظفون» (على الكل) أو «محدد» (على الموسومين)،
--  وبأساس راتبي (الأساسي أو الإجمالي)، وإلا فلا.
--  القراءة لمن له اطّلاع مالي، والتحرير بصلاحية التحرير، والاعتماد والقفل والتراجع بصلاحية الاعتماد، بدوال تسجّل في سجل التدقيق.
--  يُشغَّل بعد 20261208000047_finance_settings.sql، وإعادة تشغيله آمنة. التراجع: supabase/rollbacks/20261209000048_payroll_down.sql
-- =====================================================================
create table if not exists public.fin_employees (
  id         uuid primary key default gen_random_uuid(),
  full_name  text not null check (length(btrim(full_name)) between 1 and 120),
  job_title  text not null default '' check (length(job_title) <= 80),
  basic      numeric(18, 3) not null check (basic >= 0),
  hire_date  date not null,
  status     text not null default 'active' check (status in ('active', 'inactive')),
  profile_id uuid references public.profiles (id) on delete set null,
  insured    boolean not null default true,
  taxable    boolean not null default false,
  extra      boolean not null default false,
  note       text not null default '' check (length(note) <= 300),
  created_at timestamptz not null default now(),
  created_by uuid references public.profiles (id) on delete set null,
  updated_at timestamptz not null default now(),
  updated_by uuid references public.profiles (id) on delete set null
);
create unique index if not exists fin_employees_name_uidx on public.fin_employees (lower(btrim(full_name)));
create index if not exists fin_employees_profile_idx on public.fin_employees (profile_id);
create index if not exists fin_employees_created_by_idx on public.fin_employees (created_by);
create index if not exists fin_employees_updated_by_idx on public.fin_employees (updated_by);

create table if not exists public.fin_allowances (
  id          uuid primary key default gen_random_uuid(),
  employee_id uuid not null references public.fin_employees (id) on delete cascade,
  name        text not null check (length(btrim(name)) between 1 and 60),
  amount      numeric(18, 3) not null check (amount >= 0),
  active      boolean not null default true
);
create index if not exists fin_allowances_emp_idx on public.fin_allowances (employee_id);

create table if not exists public.fin_emp_deductions (
  employee_id  uuid not null references public.fin_employees (id) on delete cascade,
  deduction_id uuid not null references public.finance_deductions (id) on delete cascade,
  override     numeric(18, 4) check (override is null or override >= 0),
  primary key (employee_id, deduction_id)
);
create index if not exists fin_emp_deductions_ded_idx on public.fin_emp_deductions (deduction_id);

create table if not exists public.fin_attendance (
  employee_id    uuid not null references public.fin_employees (id) on delete cascade,
  day            date not null,
  status         text not null check (status in ('present', 'absent', 'leave', 'holiday')),
  overtime_hours numeric(6, 2) not null default 0 check (overtime_hours between 0 and 24),
  primary key (employee_id, day)
);

create table if not exists public.fin_attendance_month (
  employee_id    uuid not null references public.fin_employees (id) on delete cascade,
  period         date not null check (period = date_trunc('month', period)::date),
  absent_days    numeric(5, 2) not null default 0 check (absent_days between 0 and 31),
  leave_days     numeric(5, 2) not null default 0 check (leave_days between 0 and 31),
  overtime_hours numeric(7, 2) not null default 0 check (overtime_hours >= 0),
  note           text not null default '' check (length(note) <= 300),
  primary key (employee_id, period)
);

create table if not exists public.fin_bonuses (
  id          uuid primary key default gen_random_uuid(),
  employee_id uuid not null references public.fin_employees (id) on delete cascade,
  period      date not null check (period = date_trunc('month', period)::date),
  name        text not null check (length(btrim(name)) between 1 and 80),
  amount      numeric(18, 3) not null check (amount > 0),
  note        text not null default '' check (length(note) <= 300),
  created_by  uuid references public.profiles (id) on delete set null
);
create index if not exists fin_bonuses_emp_idx on public.fin_bonuses (employee_id, period);
create index if not exists fin_bonuses_created_by_idx on public.fin_bonuses (created_by);

create table if not exists public.fin_loans (
  id           uuid primary key default gen_random_uuid(),
  employee_id  uuid not null references public.fin_employees (id) on delete cascade,
  total        numeric(18, 3) not null check (total > 0),
  installments integer not null check (installments between 1 and 120),
  start_period date not null check (start_period = date_trunc('month', start_period)::date),
  status       text not null default 'active' check (status in ('active', 'closed')),
  note         text not null default '' check (length(note) <= 300),
  created_by   uuid references public.profiles (id) on delete set null
);
create index if not exists fin_loans_emp_idx on public.fin_loans (employee_id);
create index if not exists fin_loans_created_by_idx on public.fin_loans (created_by);

create table if not exists public.fin_config (
  key   text primary key check (key in ('days_in_month', 'weekly_hours', 'overtime_factor')),
  value numeric(10, 3) not null check (value > 0)
);
insert into public.fin_config (key, value) values ('days_in_month', 30), ('weekly_hours', 42), ('overtime_factor', 1.5)
on conflict (key) do nothing;

create table if not exists public.fin_payrolls (
  id          uuid primary key default gen_random_uuid(),
  period      date not null unique check (period = date_trunc('month', period)::date),
  status      text not null default 'draft' check (status in ('draft', 'approved', 'locked')),
  created_at  timestamptz not null default now(),
  created_by  uuid references public.profiles (id) on delete set null,
  approved_at timestamptz,
  approved_by uuid references public.profiles (id) on delete set null,
  locked_at   timestamptz,
  locked_by   uuid references public.profiles (id) on delete set null
);
create index if not exists fin_payrolls_created_by_idx on public.fin_payrolls (created_by);
create index if not exists fin_payrolls_approved_by_idx on public.fin_payrolls (approved_by);
create index if not exists fin_payrolls_locked_by_idx on public.fin_payrolls (locked_by);

create table if not exists public.fin_payroll_lines (
  id               uuid primary key default gen_random_uuid(),
  payroll_id       uuid not null references public.fin_payrolls (id) on delete cascade,
  employee_id      uuid not null references public.fin_employees (id) on delete restrict,
  employee_name    text not null,
  job_title        text not null default '',
  basic            numeric(18, 3) not null,
  allowances       numeric(18, 3) not null default 0,
  overtime_hours   numeric(7, 2) not null default 0,
  overtime_amount  numeric(18, 3) not null default 0,
  bonuses          numeric(18, 3) not null default 0,
  gross            numeric(18, 3) not null,
  absent_days      numeric(5, 2) not null default 0,
  absence          numeric(18, 3) not null default 0,
  insurance        numeric(18, 3) not null default 0,
  tax              numeric(18, 3) not null default 0,
  extra_rule       numeric(18, 3) not null default 0,
  other_deductions numeric(18, 3) not null default 0,
  other_detail     jsonb not null default '[]'::jsonb,
  loan             numeric(18, 3) not null default 0,
  net              numeric(18, 3) not null,
  unique (payroll_id, employee_id)
);
create index if not exists fin_payroll_lines_emp_idx on public.fin_payroll_lines (employee_id);

do $$
declare t text;
begin
  foreach t in array array['fin_employees', 'fin_allowances', 'fin_emp_deductions', 'fin_attendance', 'fin_attendance_month',
                           'fin_bonuses', 'fin_loans', 'fin_config', 'fin_payrolls', 'fin_payroll_lines'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('drop policy if exists %I on public.%I', t || '_read', t);
    execute format('create policy %I on public.%I for select to authenticated using ((select public.finance_can_view()))', t || '_read', t);
    execute format('revoke all on public.%I from anon', t);
    execute format('revoke insert, update, delete, truncate on public.%I from authenticated', t);
    execute format('grant select on public.%I to authenticated', t);
    execute format('grant all on public.%I to service_role', t);
  end loop;
end $$;

-- أدوات داخلية
create or replace function public.fin_need_edit()
returns void
language plpgsql stable security definer set search_path = public
as $$
begin
  if not public.finance_can_edit() then
    raise exception 'تعديل المرتبات لمن يملك صلاحية التحرير' using errcode = '42501';
  end if;
end $$;

create or replace function public.fin_cfg(p_key text)
returns numeric
language sql stable security definer set search_path = public
as $$ select value from public.fin_config where key = p_key $$;

-- هل الشهر مفتوح للتعديل (لا كشف معتمداً أو مقفلاً له)؟
create or replace function public.fin_period_open(p_period date)
returns boolean
language sql stable security definer set search_path = public
as $$ select not exists (select 1 from public.fin_payrolls where period = date_trunc('month', p_period)::date and status <> 'draft') $$;

create or replace function public.fin_assert_open(p_period date)
returns void
language plpgsql stable security definer set search_path = public
as $$
begin
  if not public.fin_period_open(p_period) then
    raise exception 'كشف هذا الشهر معتمد أو مقفل؛ أعد فتحه بتراجع مسجَّل بسبب قبل التعديل' using errcode = '23514';
  end if;
end $$;

-- الموظفون
create or replace function public.fin_employee_save(
  p_id uuid, p_name text, p_title text, p_basic numeric, p_hire date, p_status text,
  p_profile uuid default null, p_insured boolean default true, p_taxable boolean default false,
  p_extra boolean default false, p_note text default '')
returns uuid
language plpgsql security definer set search_path = public
as $$
declare
  v_id uuid := p_id;
  v_name text := btrim(coalesce(p_name, ''));
begin
  perform public.fin_need_edit();
  if length(v_name) not between 1 and 120 then raise exception 'اسم الموظف حتى 120 حرفاً' using errcode = '22023'; end if;
  if length(coalesce(p_title, '')) > 80 then raise exception 'المسمى حتى 80 حرفاً' using errcode = '22023'; end if;
  if p_basic is null or p_basic < 0 then raise exception 'الراتب الأساسي مبلغ غير سالب' using errcode = '22023'; end if;
  if p_hire is null then raise exception 'تاريخ التعيين مطلوب' using errcode = '22023'; end if;
  if p_status is null or p_status not in ('active', 'inactive') then raise exception 'حالة غير صالحة' using errcode = '22023'; end if;
  if length(coalesce(p_note, '')) > 300 then raise exception 'الملاحظة أطول من 300 حرف' using errcode = '22023'; end if;
  if exists (select 1 from public.fin_employees where lower(btrim(full_name)) = lower(v_name) and id is distinct from p_id) then
    raise exception 'يوجد موظف بهذا الاسم' using errcode = '23505';
  end if;
  if p_id is null then
    insert into public.fin_employees (full_name, job_title, basic, hire_date, status, profile_id, insured, taxable, extra, note, created_by, updated_by)
    values (v_name, coalesce(p_title, ''), p_basic, p_hire, p_status, p_profile, coalesce(p_insured, true), coalesce(p_taxable, false),
            coalesce(p_extra, false), coalesce(p_note, ''), auth.uid(), auth.uid())
    returning id into v_id;
  else
    if not exists (select 1 from public.fin_employees where id = p_id) then raise exception 'الموظف غير موجود' using errcode = 'P0002'; end if;
    update public.fin_employees set full_name = v_name, job_title = coalesce(p_title, ''), basic = p_basic, hire_date = p_hire,
           status = p_status, profile_id = p_profile, insured = coalesce(p_insured, true), taxable = coalesce(p_taxable, false),
           extra = coalesce(p_extra, false), note = coalesce(p_note, ''), updated_at = now(), updated_by = auth.uid()
     where id = p_id;
  end if;
  perform public.write_audit('finance.emp_save', null, null,
    jsonb_build_object('id', v_id, 'name', v_name, 'basic', p_basic, 'status', p_status, 'created', p_id is null), v_name);
  return v_id;
end $$;

create or replace function public.fin_employee_delete(p_id uuid)
returns void
language plpgsql security definer set search_path = public
as $$
declare e public.fin_employees;
begin
  perform public.fin_need_edit();
  select * into e from public.fin_employees where id = p_id;
  if not found then raise exception 'الموظف غير موجود' using errcode = 'P0002'; end if;
  if exists (select 1 from public.fin_payroll_lines where employee_id = p_id) then
    raise exception 'لا يُحذف موظف له كشوف؛ أوقفه بدل حذفه' using errcode = '23503';
  end if;
  delete from public.fin_employees where id = p_id;
  perform public.write_audit('finance.emp_delete', null, null, jsonb_build_object('id', p_id, 'name', e.full_name), e.full_name);
end $$;

create or replace function public.fin_allowance_save(p_id uuid, p_emp uuid, p_name text, p_amount numeric, p_active boolean default true)
returns uuid
language plpgsql security definer set search_path = public
as $$
declare v_id uuid := p_id; v_name text := btrim(coalesce(p_name, '')); v_emp text;
begin
  perform public.fin_need_edit();
  select full_name into v_emp from public.fin_employees where id = p_emp;
  if not found then raise exception 'الموظف غير موجود' using errcode = 'P0002'; end if;
  if length(v_name) not between 1 and 60 then raise exception 'اسم البدل حتى 60 حرفاً' using errcode = '22023'; end if;
  if p_amount is null or p_amount < 0 then raise exception 'مبلغ البدل غير سالب' using errcode = '22023'; end if;
  if p_id is null then
    insert into public.fin_allowances (employee_id, name, amount, active) values (p_emp, v_name, p_amount, coalesce(p_active, true)) returning id into v_id;
  else
    update public.fin_allowances set name = v_name, amount = p_amount, active = coalesce(p_active, true) where id = p_id and employee_id = p_emp;
    if not found then raise exception 'البدل غير موجود' using errcode = 'P0002'; end if;
  end if;
  perform public.write_audit('finance.allowance_save', null, null,
    jsonb_build_object('employee', v_emp, 'name', v_name, 'amount', p_amount, 'active', coalesce(p_active, true), 'created', p_id is null), v_emp);
  return v_id;
end $$;

create or replace function public.fin_allowance_delete(p_id uuid)
returns void
language plpgsql security definer set search_path = public
as $$
declare a public.fin_allowances; v_emp text;
begin
  perform public.fin_need_edit();
  select * into a from public.fin_allowances where id = p_id;
  if not found then raise exception 'البدل غير موجود' using errcode = 'P0002'; end if;
  select full_name into v_emp from public.fin_employees where id = a.employee_id;
  delete from public.fin_allowances where id = p_id;
  perform public.write_audit('finance.allowance_delete', null, null, jsonb_build_object('employee', v_emp, 'name', a.name, 'amount', a.amount), v_emp);
end $$;

-- إسناد خصم من الدليل لموظف (أو سحبه)، مع قيمة خاصة اختيارية
create or replace function public.fin_emp_deduction_set(p_emp uuid, p_ded uuid, p_on boolean, p_override numeric default null)
returns void
language plpgsql security definer set search_path = public
as $$
declare v_emp text; v_ded text;
begin
  perform public.fin_need_edit();
  select full_name into v_emp from public.fin_employees where id = p_emp;
  if not found then raise exception 'الموظف غير موجود' using errcode = 'P0002'; end if;
  select name into v_ded from public.finance_deductions where id = p_ded;
  if not found then raise exception 'الخصم غير موجود' using errcode = 'P0002'; end if;
  if p_override is not null and p_override < 0 then raise exception 'القيمة الخاصة غير سالبة' using errcode = '22023'; end if;
  if coalesce(p_on, false) then
    insert into public.fin_emp_deductions (employee_id, deduction_id, override) values (p_emp, p_ded, p_override)
    on conflict (employee_id, deduction_id) do update set override = excluded.override;
  else
    delete from public.fin_emp_deductions where employee_id = p_emp and deduction_id = p_ded;
  end if;
  perform public.write_audit('finance.empded_set', null, null,
    jsonb_build_object('employee', v_emp, 'deduction', v_ded, 'on', coalesce(p_on, false), 'override', p_override), v_emp);
end $$;

-- الحضور اليومي والشهري
create or replace function public.fin_attendance_set(p_emp uuid, p_day date, p_status text, p_ot numeric default 0)
returns void
language plpgsql security definer set search_path = public
as $$
declare v_emp text;
begin
  perform public.fin_need_edit();
  select full_name into v_emp from public.fin_employees where id = p_emp;
  if not found then raise exception 'الموظف غير موجود' using errcode = 'P0002'; end if;
  if p_day is null then raise exception 'اليوم مطلوب' using errcode = '22023'; end if;
  if p_status is null or p_status not in ('present', 'absent', 'leave', 'holiday') then raise exception 'حالة حضور غير صالحة' using errcode = '22023'; end if;
  if p_ot is null or p_ot < 0 or p_ot > 24 then raise exception 'الساعات الإضافية بين 0 و24' using errcode = '22023'; end if;
  perform public.fin_assert_open(p_day);
  insert into public.fin_attendance (employee_id, day, status, overtime_hours) values (p_emp, p_day, p_status, p_ot)
  on conflict (employee_id, day) do update set status = excluded.status, overtime_hours = excluded.overtime_hours;
  perform public.write_audit('finance.att_set', null, null,
    jsonb_build_object('employee', v_emp, 'day', p_day, 'status', p_status, 'overtime', p_ot), v_emp);
end $$;

create or replace function public.fin_attendance_clear(p_emp uuid, p_day date)
returns void
language plpgsql security definer set search_path = public
as $$
declare v_emp text;
begin
  perform public.fin_need_edit();
  select full_name into v_emp from public.fin_employees where id = p_emp;
  if not found then raise exception 'الموظف غير موجود' using errcode = 'P0002'; end if;
  perform public.fin_assert_open(p_day);
  delete from public.fin_attendance where employee_id = p_emp and day = p_day;
  perform public.write_audit('finance.att_clear', null, null, jsonb_build_object('employee', v_emp, 'day', p_day), v_emp);
end $$;

create or replace function public.fin_attendance_month_set(p_emp uuid, p_period date, p_absent numeric, p_leave numeric, p_ot numeric, p_note text default '')
returns void
language plpgsql security definer set search_path = public
as $$
declare v_emp text; v_p date := date_trunc('month', p_period)::date;
begin
  perform public.fin_need_edit();
  select full_name into v_emp from public.fin_employees where id = p_emp;
  if not found then raise exception 'الموظف غير موجود' using errcode = 'P0002'; end if;
  if p_period is null then raise exception 'الشهر مطلوب' using errcode = '22023'; end if;
  if p_absent is null or p_absent < 0 or p_absent > 31 or p_leave is null or p_leave < 0 or p_leave > 31 then
    raise exception 'الأيام بين 0 و31' using errcode = '22023';
  end if;
  if p_ot is null or p_ot < 0 then raise exception 'الساعات الإضافية غير سالبة' using errcode = '22023'; end if;
  if length(coalesce(p_note, '')) > 300 then raise exception 'الملاحظة أطول من 300 حرف' using errcode = '22023'; end if;
  perform public.fin_assert_open(v_p);
  insert into public.fin_attendance_month (employee_id, period, absent_days, leave_days, overtime_hours, note)
  values (p_emp, v_p, p_absent, p_leave, p_ot, coalesce(p_note, ''))
  on conflict (employee_id, period) do update set absent_days = excluded.absent_days, leave_days = excluded.leave_days,
         overtime_hours = excluded.overtime_hours, note = excluded.note;
  perform public.write_audit('finance.attm_set', null, null,
    jsonb_build_object('employee', v_emp, 'period', v_p, 'absent', p_absent, 'leave', p_leave, 'overtime', p_ot), v_emp);
end $$;

create or replace function public.fin_attendance_month_clear(p_emp uuid, p_period date)
returns void
language plpgsql security definer set search_path = public
as $$
declare v_emp text; v_p date := date_trunc('month', p_period)::date;
begin
  perform public.fin_need_edit();
  select full_name into v_emp from public.fin_employees where id = p_emp;
  if not found then raise exception 'الموظف غير موجود' using errcode = 'P0002'; end if;
  perform public.fin_assert_open(v_p);
  delete from public.fin_attendance_month where employee_id = p_emp and period = v_p;
  perform public.write_audit('finance.attm_clear', null, null, jsonb_build_object('employee', v_emp, 'period', v_p), v_emp);
end $$;

-- المكافآت
create or replace function public.fin_bonus_save(p_id uuid, p_emp uuid, p_period date, p_name text, p_amount numeric, p_note text default '')
returns uuid
language plpgsql security definer set search_path = public
as $$
declare v_id uuid := p_id; v_emp text; v_p date := date_trunc('month', p_period)::date; v_name text := btrim(coalesce(p_name, ''));
begin
  perform public.fin_need_edit();
  select full_name into v_emp from public.fin_employees where id = p_emp;
  if not found then raise exception 'الموظف غير موجود' using errcode = 'P0002'; end if;
  if p_period is null then raise exception 'الشهر مطلوب' using errcode = '22023'; end if;
  if length(v_name) not between 1 and 80 then raise exception 'اسم المكافأة حتى 80 حرفاً' using errcode = '22023'; end if;
  if p_amount is null or p_amount <= 0 then raise exception 'مبلغ المكافأة أكبر من صفر' using errcode = '22023'; end if;
  if length(coalesce(p_note, '')) > 300 then raise exception 'الملاحظة أطول من 300 حرف' using errcode = '22023'; end if;
  perform public.fin_assert_open(v_p);
  if p_id is null then
    insert into public.fin_bonuses (employee_id, period, name, amount, note, created_by) values (p_emp, v_p, v_name, p_amount, coalesce(p_note, ''), auth.uid())
    returning id into v_id;
  else
    update public.fin_bonuses set period = v_p, name = v_name, amount = p_amount, note = coalesce(p_note, '') where id = p_id and employee_id = p_emp;
    if not found then raise exception 'المكافأة غير موجودة' using errcode = 'P0002'; end if;
  end if;
  perform public.write_audit('finance.bonus_save', null, null,
    jsonb_build_object('employee', v_emp, 'name', v_name, 'amount', p_amount, 'period', v_p, 'created', p_id is null), v_emp);
  return v_id;
end $$;

create or replace function public.fin_bonus_delete(p_id uuid)
returns void
language plpgsql security definer set search_path = public
as $$
declare b public.fin_bonuses; v_emp text;
begin
  perform public.fin_need_edit();
  select * into b from public.fin_bonuses where id = p_id;
  if not found then raise exception 'المكافأة غير موجودة' using errcode = 'P0002'; end if;
  perform public.fin_assert_open(b.period);
  select full_name into v_emp from public.fin_employees where id = b.employee_id;
  delete from public.fin_bonuses where id = p_id;
  perform public.write_audit('finance.bonus_delete', null, null, jsonb_build_object('employee', v_emp, 'name', b.name, 'amount', b.amount, 'period', b.period), v_emp);
end $$;

-- السلف: قسط ثابت = الإجمالي ÷ العدد، وآخر قسط يأخذ الباقي
create or replace function public.fin_loan_save(p_id uuid, p_emp uuid, p_total numeric, p_count integer, p_start date, p_status text default 'active', p_note text default '')
returns uuid
language plpgsql security definer set search_path = public
as $$
declare v_id uuid := p_id; v_emp text; v_s date := date_trunc('month', p_start)::date;
begin
  perform public.fin_need_edit();
  select full_name into v_emp from public.fin_employees where id = p_emp;
  if not found then raise exception 'الموظف غير موجود' using errcode = 'P0002'; end if;
  if p_total is null or p_total <= 0 then raise exception 'مبلغ السلفة أكبر من صفر' using errcode = '22023'; end if;
  if p_count is null or p_count not between 1 and 120 then raise exception 'عدد الأقساط بين 1 و120' using errcode = '22023'; end if;
  if p_start is null then raise exception 'شهر بدء الخصم مطلوب' using errcode = '22023'; end if;
  if p_status is null or p_status not in ('active', 'closed') then raise exception 'حالة غير صالحة' using errcode = '22023'; end if;
  if length(coalesce(p_note, '')) > 300 then raise exception 'الملاحظة أطول من 300 حرف' using errcode = '22023'; end if;
  if p_id is null then
    insert into public.fin_loans (employee_id, total, installments, start_period, status, note, created_by)
    values (p_emp, p_total, p_count, v_s, p_status, coalesce(p_note, ''), auth.uid()) returning id into v_id;
  else
    if exists (select 1 from public.fin_payroll_lines l join public.fin_payrolls p on p.id = l.payroll_id
                where l.employee_id = p_emp and l.loan > 0 and p.status <> 'draft'
                  and p.period >= (select start_period from public.fin_loans where id = p_id)) then
      raise exception 'خُصم من هذه السلفة في كشف معتمد؛ لا تُعدَّل شروطها' using errcode = '23514';
    end if;
    update public.fin_loans set total = p_total, installments = p_count, start_period = v_s, status = p_status, note = coalesce(p_note, '')
     where id = p_id and employee_id = p_emp;
    if not found then raise exception 'السلفة غير موجودة' using errcode = 'P0002'; end if;
  end if;
  perform public.write_audit('finance.loan_save', null, null,
    jsonb_build_object('employee', v_emp, 'total', p_total, 'count', p_count, 'start', v_s, 'status', p_status, 'created', p_id is null), v_emp);
  return v_id;
end $$;

create or replace function public.fin_loan_delete(p_id uuid)
returns void
language plpgsql security definer set search_path = public
as $$
declare l public.fin_loans; v_emp text;
begin
  perform public.fin_need_edit();
  select * into l from public.fin_loans where id = p_id;
  if not found then raise exception 'السلفة غير موجودة' using errcode = 'P0002'; end if;
  if exists (select 1 from public.fin_payroll_lines x where x.employee_id = l.employee_id and x.loan > 0) then
    raise exception 'خُصم من هذه السلفة في كشوف؛ أغلقها بدل حذفها' using errcode = '23503';
  end if;
  select full_name into v_emp from public.fin_employees where id = l.employee_id;
  delete from public.fin_loans where id = p_id;
  perform public.write_audit('finance.loan_delete', null, null, jsonb_build_object('employee', v_emp, 'total', l.total), v_emp);
end $$;

create or replace function public.fin_config_set(p_key text, p_value numeric)
returns void
language plpgsql security definer set search_path = public
as $$
begin
  perform public.fin_need_edit();
  if p_key not in ('days_in_month', 'weekly_hours', 'overtime_factor') then raise exception 'إعداد غير معروف' using errcode = '22023'; end if;
  if p_value is null or p_value <= 0 or (p_key = 'days_in_month' and p_value > 31) or (p_key = 'weekly_hours' and p_value > 84)
     or (p_key = 'overtime_factor' and p_value > 5) then
    raise exception 'قيمة الإعداد غير صالحة' using errcode = '22023';
  end if;
  update public.fin_config set value = p_value where key = p_key;
  perform public.write_audit('finance.config_set', null, null, jsonb_build_object('key', p_key, 'value', p_value), p_key);
end $$;

-- النسبة الراتبية السارية آخر الشهر: يرجع (النسبة، الأساس، النطاق) أو لا شيء
create or replace function public.fin_rate_for(p_code text, p_period date)
returns table (percent numeric, basis text, scope text)
language sql stable security definer set search_path = public
as $$
  select r.percent, r.basis, r.scope from public.finance_rates r
   where r.code = p_code and r.active and r.scope in ('employees', 'selected') and r.basis in ('payroll_basic', 'payroll_gross')
     and r.effective_from <= (date_trunc('month', p_period) + interval '1 month - 1 day')::date
     and (r.effective_to is null or r.effective_to >= (date_trunc('month', p_period) + interval '1 month - 1 day')::date)
   order by r.effective_from desc limit 1
$$;

-- توليد كشف شهر (مسودة فقط): يحسب لقطة لكل موظف نشط عُيّن حتى آخر الشهر
create or replace function public.fin_payroll_generate(p_period date)
returns uuid
language plpgsql security definer set search_path = public
as $$
declare
  v_p date := date_trunc('month', p_period)::date;
  v_end date := (date_trunc('month', p_period) + interval '1 month - 1 day')::date;
  v_pid uuid;
  v_status text;
  v_dim numeric := public.fin_cfg('days_in_month');
  v_wh numeric := public.fin_cfg('weekly_hours');
  v_factor numeric := public.fin_cfg('overtime_factor');
  e record;
  d record;
  v_daily numeric; v_hourly numeric; v_allow numeric; v_abs numeric; v_ot numeric; v_otamt numeric; v_bon numeric;
  v_gross numeric; v_absamt numeric; v_ins numeric; v_tax numeric; v_ext numeric; v_oth numeric; v_det jsonb; v_loan numeric; v_net numeric;
  v_amt numeric; v_base numeric;
  r record; l record; v_idx integer; v_n integer := 0;
begin
  perform public.fin_need_edit();
  if p_period is null then raise exception 'الشهر مطلوب' using errcode = '22023'; end if;
  select id, status into v_pid, v_status from public.fin_payrolls where period = v_p;
  if v_pid is not null and v_status <> 'draft' then
    raise exception 'الكشف معتمد أو مقفل؛ أعد فتحه بتراجع مسجَّل بسبب' using errcode = '23514';
  end if;
  if v_pid is null then
    insert into public.fin_payrolls (period, created_by) values (v_p, auth.uid()) returning id into v_pid;
  else
    delete from public.fin_payroll_lines where payroll_id = v_pid;
  end if;
  for e in select * from public.fin_employees where status = 'active' and hire_date <= v_end order by full_name loop
    v_daily := e.basic / v_dim;
    v_hourly := v_daily / (v_wh / 6.0);
    select coalesce(sum(amount), 0) into v_allow from public.fin_allowances where employee_id = e.id and active;
    if exists (select 1 from public.fin_attendance_month where employee_id = e.id and period = v_p) then
      select absent_days, overtime_hours into v_abs, v_ot from public.fin_attendance_month where employee_id = e.id and period = v_p;
    else
      select coalesce(count(*) filter (where status = 'absent'), 0), coalesce(sum(overtime_hours), 0) into v_abs, v_ot
        from public.fin_attendance where employee_id = e.id and day between v_p and v_end;
    end if;
    v_otamt := round(v_ot * v_hourly * v_factor, 3);
    select coalesce(sum(amount), 0) into v_bon from public.fin_bonuses where employee_id = e.id and period = v_p;
    v_gross := round(e.basic + v_allow + v_otamt + v_bon, 3);
    v_absamt := round(v_abs * v_daily, 3);
    v_ins := 0; v_tax := 0; v_ext := 0;
    select * into r from public.fin_rate_for('insurance', v_p);
    if found and (r.scope = 'employees' or e.insured) then
      v_ins := round((case r.basis when 'payroll_basic' then e.basic else v_gross end) * r.percent / 100, 3);
    end if;
    select * into r from public.fin_rate_for('income_tax', v_p);
    if found and (r.scope = 'employees' or e.taxable) then
      v_tax := round((case r.basis when 'payroll_basic' then e.basic else v_gross end) * r.percent / 100, 3);
    end if;
    select * into r from public.fin_rate_for('extra_rule', v_p);
    if found and (r.scope = 'employees' or e.extra) then
      v_ext := round((case r.basis when 'payroll_basic' then e.basic else v_gross end) * r.percent / 100, 3);
    end if;
    v_oth := 0; v_det := '[]'::jsonb;
    for d in select fd.name, fd.kind, fd.basis, coalesce(x.override, fd.value) as val
               from public.fin_emp_deductions x join public.finance_deductions fd on fd.id = x.deduction_id
              where x.employee_id = e.id and fd.active and fd.applies_to in ('payroll', 'both') order by fd.name loop
      if d.kind = 'percent' then
        v_base := case d.basis when 'payroll_basic' then e.basic when 'payroll_gross' then v_gross else null end;
        continue when v_base is null;
        v_amt := round(v_base * d.val / 100, 3);
      else
        v_amt := round(d.val, 3);
      end if;
      v_oth := v_oth + v_amt;
      v_det := v_det || jsonb_build_array(jsonb_build_object('name', d.name, 'amount', v_amt));
    end loop;
    v_loan := 0;
    for l in select * from public.fin_loans where employee_id = e.id and status = 'active' and start_period <= v_p loop
      v_idx := (extract(year from v_p)::int * 12 + extract(month from v_p)::int) - (extract(year from l.start_period)::int * 12 + extract(month from l.start_period)::int);
      if v_idx < l.installments then
        v_amt := round(l.total / l.installments, 3);
        if v_idx = l.installments - 1 then v_amt := l.total - round(l.total / l.installments, 3) * (l.installments - 1); end if;
        v_loan := v_loan + v_amt;
      end if;
    end loop;
    v_net := round(v_gross - v_absamt - v_ins - v_tax - v_ext - v_oth - v_loan, 3);
    insert into public.fin_payroll_lines (payroll_id, employee_id, employee_name, job_title, basic, allowances, overtime_hours, overtime_amount,
           bonuses, gross, absent_days, absence, insurance, tax, extra_rule, other_deductions, other_detail, loan, net)
    values (v_pid, e.id, e.full_name, e.job_title, e.basic, v_allow, v_ot, v_otamt, v_bon, v_gross, v_abs, v_absamt, v_ins, v_tax, v_ext, v_oth, v_det, v_loan, v_net);
    v_n := v_n + 1;
  end loop;
  perform public.write_audit('finance.payroll_generate', null, null, jsonb_build_object('period', v_p, 'employees', v_n), to_char(v_p, 'YYYY-MM'));
  return v_pid;
end $$;

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

create or replace function public.fin_payroll_lock(p_period date)
returns void
language plpgsql security definer set search_path = public
as $$
declare p public.fin_payrolls; v_p date := date_trunc('month', p_period)::date;
begin
  if not public.finance_can_approve() then raise exception 'قفل الكشف لمن يملك صلاحية الاعتماد' using errcode = '42501'; end if;
  select * into p from public.fin_payrolls where period = v_p;
  if not found then raise exception 'لا كشف لهذا الشهر' using errcode = 'P0002'; end if;
  if p.status <> 'approved' then raise exception 'يُقفل الكشف المعتمد وحده' using errcode = '23514'; end if;
  update public.fin_payrolls set status = 'locked', locked_at = now(), locked_by = auth.uid() where id = p.id;
  perform public.write_audit('finance.payroll_lock', null, null, jsonb_build_object('period', v_p), to_char(v_p, 'YYYY-MM'));
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

create or replace function public.fin_payroll_delete(p_period date)
returns void
language plpgsql security definer set search_path = public
as $$
declare p public.fin_payrolls; v_p date := date_trunc('month', p_period)::date;
begin
  perform public.fin_need_edit();
  select * into p from public.fin_payrolls where period = v_p;
  if not found then raise exception 'لا كشف لهذا الشهر' using errcode = 'P0002'; end if;
  if p.status <> 'draft' then raise exception 'يُحذف كشف المسودة وحده' using errcode = '23514'; end if;
  delete from public.fin_payrolls where id = p.id;
  perform public.write_audit('finance.payroll_delete', null, null, jsonb_build_object('period', v_p), to_char(v_p, 'YYYY-MM'));
end $$;

do $$
declare f record;
begin
  for f in select p.oid::regprocedure as sig from pg_proc p
            where p.pronamespace = 'public'::regnamespace and p.proname like 'fin\_%' and p.proname not in ('fin_cfg', 'fin_rate_for', 'fin_period_open') loop
    execute format('revoke execute on function %s from public, anon', f.sig);
    execute format('grant execute on function %s to authenticated', f.sig);
  end loop;
end $$;
