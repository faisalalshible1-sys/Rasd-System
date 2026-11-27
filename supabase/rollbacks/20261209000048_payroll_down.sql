-- التراجع عن الترحيل 48 (المرتبات). يُرفض إن وُجد موظفون أو كشوف حتى لا تضيع.
do $$
begin
  if to_regclass('public.fin_employees') is not null and (exists (select 1 from public.fin_employees) or exists (select 1 from public.fin_payrolls)) then
    raise exception 'لا يُتراجع عن الترحيل 48: توجد بيانات موظفين أو كشوف مسجَّلة. المنظومة كما هي.';
  end if;
end $$;
drop table if exists public.fin_payroll_lines;
drop table if exists public.fin_payrolls;
drop table if exists public.fin_config;
drop table if exists public.fin_loans;
drop table if exists public.fin_bonuses;
drop table if exists public.fin_attendance_month;
drop table if exists public.fin_attendance;
drop table if exists public.fin_emp_deductions;
drop table if exists public.fin_allowances;
drop table if exists public.fin_employees;
do $$
declare f record;
begin
  for f in select p.oid::regprocedure as sig from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname like 'fin\_%' loop
    execute format('drop function if exists %s', f.sig);
  end loop;
end $$;
