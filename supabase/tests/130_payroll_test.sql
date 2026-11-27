-- اختبارات الترحيل 48: المرتبات والموظفون والحضور والمكافآت والسلف
\set ON_ERROR_STOP 1
\set QUIET 1
\pset tuples_only on
\pset format unaligned

create or replace function pg_temp.as_user(p_email text, p_aal text default 'aal1') returns void language plpgsql security definer as $$
declare v uuid := (select id from auth.users where email = p_email);
begin
  perform set_config('request.jwt.claim.sub', coalesce(v::text, ''), false);
  perform set_config('request.jwt.claims', jsonb_build_object('sub', v, 'aal', p_aal, 'session_id', '00000000-0000-0000-0000-000000000001')::text, false);
end $$;
create or replace function pg_temp.expect_error(p_sql text, p_label text) returns void language plpgsql as $$
begin
  begin
    execute p_sql;
  exception when others then
    raise notice 'PASS (رُفض كما يجب): % — %', p_label, sqlerrm;
    return;
  end;
  raise exception 'FAIL: كان يجب رفض: %', p_label;
end $$;
create or replace function pg_temp.check(p_ok boolean, p_label text) returns void language plpgsql as $$
begin
  if not coalesce(p_ok, false) then raise exception 'FAIL: %', p_label; end if;
  raise notice 'PASS: %', p_label;
end $$;
create or replace function pg_temp.uid(p_email text) returns uuid language sql security definer as $$ select id from auth.users where email = p_email $$;

update app_settings set value = 'false' where key in ('security.freeze', 'security.require_mfa_all');
update profiles set locked_until = null where email in ('director.new@test.ly', 'u.qc@test.ly', 'k.qa@test.ly', 'k.staff@test.ly', 'pending@test.ly');
create temp table e (k text primary key, v uuid);
grant all on e to authenticated;

select pg_temp.check((select count(*) from public.fin_config) = 3, 'ثلاثة إعدادات ابتدائية');
select pg_temp.as_user('director.new@test.ly', 'aal2');
set role authenticated;

-- تنظيف صلاحيات خلّفها اختبار سابق في القاعدة نفسها
select public.finance_perm_set(pg_temp.uid('k.staff@test.ly'), 'edit', false);

-- الموظفون والبدلات
insert into e select 'a', public.fin_employee_save(null, 'أحمد', 'مهندس', 3000, date '2026-01-01', 'active', null, true, false, false, '');
insert into e select 'b', public.fin_employee_save(null, 'سالم', 'فني', 1500, date '2026-01-01', 'active', null, true, false, false, '');
select pg_temp.expect_error($q$select public.fin_employee_save(null, ' أحمد ', 'x', 1, date '2026-01-01', 'active')$q$, 'اسم مكرر');
select pg_temp.expect_error($q$select public.fin_employee_save(null, 'س', 'x', -1, date '2026-01-01', 'active')$q$, 'راتب سالب');
select pg_temp.expect_error($q$insert into public.fin_employees (full_name, basic, hire_date) values ('مباشر', 1, current_date)$q$, 'لا كتابة مباشرة');
select public.fin_allowance_save(null, (select v from e where k = 'a'), 'بدل سكن', 300, true);
select public.fin_allowance_save(null, (select v from e where k = 'a'), 'بدل موقوف', 999, false);

-- الحضور: يومي للموظف أ (يومان غياب و6 ساعات إضافية)، وشهري للموظف ب يغلب
select public.fin_attendance_set((select v from e where k = 'a'), date '2026-03-02', 'absent', 0);
select public.fin_attendance_set((select v from e where k = 'a'), date '2026-03-03', 'absent', 0);
select public.fin_attendance_set((select v from e where k = 'a'), date '2026-03-04', 'present', 4);
select public.fin_attendance_set((select v from e where k = 'a'), date '2026-03-05', 'present', 2);
select public.fin_attendance_set((select v from e where k = 'b'), date '2026-03-02', 'absent', 0);
select public.fin_attendance_month_set((select v from e where k = 'b'), date '2026-03-15', 1, 2, 3, '');
select pg_temp.expect_error(format($q$select public.fin_attendance_set(%L, date '2026-03-06', 'x', 0)$q$, (select v from e where k = 'a')), 'حالة حضور غير صالحة');
select pg_temp.expect_error(format($q$select public.fin_attendance_set(%L, date '2026-03-06', 'present', 25)$q$, (select v from e where k = 'a')), 'ساعات فوق 24');

-- مكافأة وسلفة وخصم وتأمينات
select public.fin_bonus_save(null, (select v from e where k = 'a'), date '2026-03-20', 'مكافأة إنجاز', 200, '');
select public.fin_loan_save(null, (select v from e where k = 'b'), 1000, 3, date '2026-03-31', 'active', '');
select public.finance_deduction_save(null, 'خصم صندوق', 'percent', 2, 'payroll_basic', 'payroll', true, '');
select public.finance_deduction_save(null, 'خصم ثابت', 'fixed', 50, 'none', 'payroll', true, '');
select public.fin_emp_deduction_set((select v from e where k = 'a'), (select id from public.finance_deductions where name = 'خصم صندوق'), true, null);
select public.fin_emp_deduction_set((select v from e where k = 'a'), (select id from public.finance_deductions where name = 'خصم ثابت'), true, 80);
-- التأمينات 5% على الراتب الأساسي لكل الموظفين (النسبة الابتدائية بنطاق الموظفين سارية في 2026)

-- شهر 2026-03: الكشف قبل سريان التأمينات الجديد (الابتدائي 5% بنطاق employees ساري من 2026-01-01)
insert into e select 'p', public.fin_payroll_generate(date '2026-03-10');
-- أ: الأساسي 3000، بدلات 300، إضافي 6 ساعات: الساعة = 3000/30/7 = 14.285714..، × 1.5 × 6 = 128.571
select pg_temp.check((select basic = 3000 and allowances = 300 and overtime_hours = 6 and overtime_amount = 128.571 and bonuses = 200 and gross = 3628.571
                        from public.fin_payroll_lines where employee_name = 'أحمد'), 'إجمالي أ: الأساسي + البدلات + الإضافي + المكافأة');
select pg_temp.check((select absent_days = 2 and absence = 200 from public.fin_payroll_lines where employee_name = 'أحمد'), 'خصم الغياب: يومان × (3000 ÷ 30)');
select pg_temp.check((select insurance = 150 from public.fin_payroll_lines where employee_name = 'أحمد'), 'التأمينات 5% من الأساسي');
select pg_temp.check((select tax = 0 and extra_rule = 0 from public.fin_payroll_lines where employee_name = 'أحمد'), 'الضريبة والقاعدة الإضافية لا تُطبَّق خارج نطاقها');
select pg_temp.check((select other_deductions = 140 from public.fin_payroll_lines where employee_name = 'أحمد'), 'خصومات الدليل: 2% من الأساسي (60) + ثابت بقيمة خاصة (80)');
select pg_temp.check((select net = 3138.571 from public.fin_payroll_lines where employee_name = 'أحمد'), 'صافي أ = 3628.571 − 200 − 150 − 140');
-- ب: الملخص الشهري يغلب اليومي: غياب يوم واحد و3 ساعات إضافية، وقسط السلفة الأول
select pg_temp.check((select absent_days = 1 and overtime_hours = 3 and absence = 50 and loan = 333.333 from public.fin_payroll_lines where employee_name = 'سالم'), 'ملخص شهري يغلب اليومي وقسط السلفة');
select pg_temp.check((select insurance = 75 and net = round(1500 + 3 * 1500.0/30/7 * 1.5 - 50 - 75 - 333.333, 3) from public.fin_payroll_lines where employee_name = 'سالم'), 'صافي ب');

-- إعادة التوليد تستبدل اللقطة ولا تضاعفها
select public.fin_payroll_generate(date '2026-03-01');
select pg_temp.check((select count(*) from public.fin_payroll_lines where payroll_id = (select v from e where k = 'p')) = 2, 'إعادة التوليد لا تضاعف الأسطر');

-- آخر قسط يأخذ الباقي: 1000 على 3 = 333.333 + 333.333 + 333.334
select public.fin_payroll_generate(date '2026-05-01');
select pg_temp.check((select loan = 333.334 from public.fin_payroll_lines l join public.fin_payrolls p on p.id = l.payroll_id where p.period = date '2026-05-01' and l.employee_name = 'سالم'), 'آخر قسط يأخذ الباقي');
select public.fin_payroll_generate(date '2026-06-01');
select pg_temp.check((select loan = 0 from public.fin_payroll_lines l join public.fin_payrolls p on p.id = l.payroll_id where p.period = date '2026-06-01' and l.employee_name = 'سالم'), 'لا قسط بعد انتهاء السلفة');
select public.fin_payroll_delete(date '2026-05-01');
select public.fin_payroll_delete(date '2026-06-01');

-- الاعتماد والقفل والتراجع
select public.fin_payroll_approve(date '2026-03-01');
select pg_temp.check((select status = 'approved' and approved_by is not null from public.fin_payrolls where period = date '2026-03-01'), 'اعتماد الكشف');
select pg_temp.expect_error($q$select public.fin_payroll_generate(date '2026-03-01')$q$, 'لا توليد على كشف معتمد');
select pg_temp.expect_error(format($q$select public.fin_bonus_save(null, %L, date '2026-03-01', 'متأخرة', 10)$q$, (select v from e where k = 'a')), 'لا مكافأة على شهر معتمد');
select pg_temp.expect_error(format($q$select public.fin_attendance_set(%L, date '2026-03-09', 'absent', 0)$q$, (select v from e where k = 'a')), 'لا حضور على شهر معتمد');
select pg_temp.expect_error($q$select public.fin_payroll_delete(date '2026-03-01')$q$, 'لا حذف لكشف معتمد');
select pg_temp.expect_error(format($q$select public.fin_employee_delete(%L)$q$, (select v from e where k = 'a')), 'لا حذف موظف له كشوف');
select pg_temp.expect_error(format($q$select public.fin_loan_save((select id from public.fin_loans limit 1), %L, 900, 3, date '2026-03-01', 'active')$q$, (select v from e where k = 'b')), 'لا تعديل سلفة خُصم منها في كشف معتمد');
select public.fin_payroll_lock(date '2026-03-01');
select pg_temp.expect_error($q$select public.fin_payroll_reopen(date '2026-03-01', '')$q$, 'تراجع بلا سبب');
select public.fin_payroll_reopen(date '2026-03-01', 'تصحيح الحضور');
select pg_temp.check((select status = 'draft' and locked_at is null from public.fin_payrolls where period = date '2026-03-01'), 'التراجع يعيد المسودة');

-- صافٍ سالب يمنع الاعتماد
select public.finance_deduction_save(null, 'خصم ضخم', 'fixed', 99999, 'none', 'payroll', true, '');
select public.fin_emp_deduction_set((select v from e where k = 'b'), (select id from public.finance_deductions where name = 'خصم ضخم'), true, null);
select public.fin_payroll_generate(date '2026-03-01');
select pg_temp.expect_error($q$select public.fin_payroll_approve(date '2026-03-01')$q$, 'لا اعتماد مع صافٍ سالب');
select public.fin_emp_deduction_set((select v from e where k = 'b'), (select id from public.finance_deductions where name = 'خصم ضخم'), false, null);
select public.fin_payroll_generate(date '2026-03-01');

-- القاعدة الإضافية بنطاق محدد: لا تُطبَّق إلا على الموسومين
reset role;
select pg_temp.as_user('director.new@test.ly', 'aal2');
set role authenticated;
select public.finance_rate_save('extra_rule', 3.75, 'payroll_basic', 'selected', date '2027-01-01', 'تفعيل');
select public.fin_employee_save((select v from e where k = 'a'), 'أحمد', 'مهندس', 3000, date '2026-01-01', 'active', null, true, false, true, '');
select public.fin_payroll_generate(date '2027-02-01');
select pg_temp.check((select extra_rule = 112.5 from public.fin_payroll_lines l join public.fin_payrolls p on p.id = l.payroll_id where p.period = date '2027-02-01' and l.employee_name = 'أحمد'), 'القاعدة الإضافية 3.75% على الموسوم: 3000 × 3.75%');
select pg_temp.check((select extra_rule = 0 from public.fin_payroll_lines l join public.fin_payrolls p on p.id = l.payroll_id where p.period = date '2027-02-01' and l.employee_name = 'سالم'), 'غير الموسوم بلا قاعدة إضافية');
select public.fin_payroll_delete(date '2027-02-01');

-- الصلاحيات
reset role;
select pg_temp.as_user('k.staff@test.ly');
set role authenticated;
select pg_temp.check((select count(*) from public.fin_employees) = 2, 'موظف المكتب يطّلع على الموظفين');
select pg_temp.expect_error(format($q$select public.fin_bonus_save(null, %L, date '2026-08-01', 'م', 5)$q$, (select v from e where k = 'a')), 'موظف المكتب لا يحرّر دون صلاحية');
reset role;
select pg_temp.as_user('director.new@test.ly', 'aal2');
set role authenticated;
select public.finance_perm_set(pg_temp.uid('k.staff@test.ly'), 'edit', true);
reset role;
select pg_temp.as_user('k.staff@test.ly');
set role authenticated;
select public.fin_bonus_save(null, (select v from e where k = 'a'), date '2026-08-01', 'م', 5);
select pg_temp.expect_error($q$select public.fin_payroll_approve(date '2026-03-01')$q$, 'التحرير لا يعتمد');
reset role;
select pg_temp.as_user('pending@test.ly');
set role authenticated;
select pg_temp.check((select count(*) from public.fin_payroll_lines) = 0 and (select count(*) from public.fin_employees) = 0, 'غير المخوَّل لا يرى الرواتب');
reset role;
select pg_temp.as_user('director.new@test.ly', 'aal2');
set role authenticated;
select pg_temp.check((select count(*) from public.audit_log where action like 'finance.%') >= 30, 'تسجيل في سجل التدقيق');
reset role;
