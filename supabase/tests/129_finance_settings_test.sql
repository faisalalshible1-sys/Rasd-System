-- اختبارات الترحيل 47: نسب المالية والخصومات والصلاحيات
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

update app_settings set value = 'false' where key in ('security.freeze', 'security.require_mfa_all');
update profiles set locked_until = null where email in ('director.new@test.ly', 'u.qc@test.ly', 'k.qa@test.ly', 'k.staff@test.ly', 'pending@test.ly');
create or replace function pg_temp.uid(p_email text) returns uuid language sql security definer as $$ select id from auth.users where email = p_email $$;

-- الإصدارات الابتدائية
select pg_temp.check((select count(*) from public.finance_rates) = 3, 'ثلاث نسب ابتدائية');
select pg_temp.check((select percent = 3 and scope = 'contracts' and active from public.finance_rates where code = 'income_tax'), 'ضريبة الدخل 3% على العقود');
select pg_temp.check((select percent = 5 and scope = 'employees' from public.finance_rates where code = 'insurance'), 'التأمينات 5% على الموظفين');
select pg_temp.check((select percent = 3.75 and not active and scope = 'selected' from public.finance_rates where code = 'extra_rule'), 'القاعدة الإضافية 3.75% معطّلة بنطاق محدد');

-- المدير يعدّل نسبة بإصدار جديد
select pg_temp.as_user('director.new@test.ly', 'aal2');
set role authenticated;
select public.finance_rate_save('income_tax', 3.5, 'extract_net', 'contracts', date '2027-01-01', 'تعديل قانوني', true);
select pg_temp.check((select count(*) from public.finance_rates where code = 'income_tax') = 2, 'إصدار جديد لا تعديل القديم');
select pg_temp.check((select effective_to = date '2026-12-31' from public.finance_rates where code = 'income_tax' and effective_from = date '2026-01-01'), 'إغلاق الإصدار السابق');
select pg_temp.check((select percent = 3 from public.finance_rates where code = 'income_tax' and effective_from = date '2026-01-01'), 'الإصدار القديم باقٍ كما هو');
select pg_temp.expect_error($q$select public.finance_rate_save('income_tax', 4, 'extract_net', 'contracts', date '2027-01-01', 'مكرر')$q$, 'تاريخ لا يلي آخر إصدار');
select pg_temp.expect_error($q$select public.finance_rate_save('income_tax', 4, 'extract_net', 'contracts', date '2027-06-01', '')$q$, 'سبب فارغ');
select pg_temp.expect_error($q$select public.finance_rate_save('income_tax', 101, 'extract_net', 'contracts', date '2027-06-01', 'سبب')$q$, 'نسبة فوق 100');
select pg_temp.expect_error($q$select public.finance_rate_save('income_tax', 4, 'x', 'contracts', date '2027-06-01', 'سبب')$q$, 'أساس غير صالح');
select pg_temp.expect_error($q$select public.finance_rate_save('income_tax', 4, 'extract_net', 'all', date '2027-06-01', 'سبب')$q$, 'نطاق غير معرّف (لا تطبيق على الكل)');
select pg_temp.expect_error($q$select public.finance_rate_save('other', 4, 'extract_net', 'contracts', date '2027-06-01', 'سبب')$q$, 'نسبة غير معروفة');
select pg_temp.expect_error($q$insert into public.finance_rates (code, percent, basis, scope, effective_from) values ('insurance', 1, 'payroll_basic', 'employees', date '2030-01-01')$q$, 'لا كتابة مباشرة على النسب');

-- الخصومات
select public.finance_deduction_save(null, 'سلفة', 'fixed', 500, 'none', 'payroll', true, '');
select public.finance_deduction_save(null, 'خصم غياب', 'percent', 2, 'payroll_basic', 'payroll', true, '');
select pg_temp.check((select count(*) from public.finance_deductions) = 2, 'خصمان في الدليل');
select pg_temp.expect_error($q$select public.finance_deduction_save(null, ' سلفة ', 'fixed', 1, 'none', 'payroll')$q$, 'اسم مكرر');
select pg_temp.expect_error($q$select public.finance_deduction_save(null, 'نسبة بلا أساس', 'percent', 1, 'none', 'payroll')$q$, 'نسبة بلا أساس');
select pg_temp.expect_error($q$select public.finance_deduction_save(null, 'كبير', 'percent', 150, 'payroll_basic', 'payroll')$q$, 'نسبة فوق 100');
select pg_temp.expect_error($q$select public.finance_deduction_save(null, 'س', 'fixed', -1, 'none', 'payroll')$q$, 'قيمة سالبة');
select public.finance_deduction_save((select id from public.finance_deductions where name = 'سلفة'), 'سلفة', 'fixed', 700, 'none', 'both', false, 'عُدّل');
select pg_temp.check((select value = 700 and not active and applies_to = 'both' from public.finance_deductions where name = 'سلفة'), 'تعديل خصم');
select public.finance_deduction_delete((select id from public.finance_deductions where name = 'خصم غياب'));
select pg_temp.check((select count(*) from public.finance_deductions) = 1, 'حذف خصم');

-- الصلاحيات المالية
reset role;
select pg_temp.as_user('k.staff@test.ly');
set role authenticated;
select pg_temp.check((select count(*) from public.finance_rates) >= 4, 'موظف المكتب يطّلع على النسب');
select pg_temp.expect_error($q$select public.finance_rate_save('insurance', 6, 'payroll_basic', 'employees', date '2027-01-01', 'محاولة')$q$, 'موظف المكتب لا يعدّل دون صلاحية');
select pg_temp.expect_error($q$select public.finance_perm_set(pg_temp.uid('k.staff@test.ly'), 'edit', true)$q$, 'موظف المكتب لا يمنح الصلاحيات');
reset role;
select pg_temp.as_user('director.new@test.ly', 'aal2');
set role authenticated;
select public.finance_perm_set(pg_temp.uid('k.staff@test.ly'), 'edit', true);
select public.finance_perm_set(pg_temp.uid('u.qc@test.ly'), 'view', true);
select pg_temp.check((select count(*) from public.finance_permissions) = 2, 'منح صلاحيتين');
reset role;
select pg_temp.as_user('k.staff@test.ly');
set role authenticated;
select public.finance_rate_save('insurance', 6, 'payroll_basic', 'employees', date '2027-01-01', 'بصلاحية التحرير');
select pg_temp.check((select percent = 6 from public.finance_rates where code = 'insurance' and effective_to is null), 'التحرير بالصلاحية الممنوحة');
reset role;
select pg_temp.as_user('u.qc@test.ly');
set role authenticated;
select pg_temp.check((select count(*) from public.finance_rates) >= 5, 'صاحب صلاحية الاطّلاع يرى النسب');
select pg_temp.expect_error($q$select public.finance_deduction_save(null, 'لا', 'fixed', 1, 'none', 'payroll')$q$, 'الاطّلاع لا يحرّر');
reset role;
select pg_temp.as_user('pending@test.ly');
set role authenticated;
select pg_temp.check((select count(*) from public.finance_rates) = 0, 'غير المخوَّل لا يرى النسب');
reset role;
select pg_temp.as_user('director.new@test.ly', 'aal2');
set role authenticated;
select public.finance_perm_set(pg_temp.uid('u.qc@test.ly'), 'view', false);
select pg_temp.check((select count(*) from public.finance_permissions where perm = 'view') = 0, 'سحب صلاحية');
select pg_temp.expect_error($q$select public.finance_perm_set(pg_temp.uid('u.qc@test.ly'), 'x', true)$q$, 'صلاحية غير معروفة');
select pg_temp.check((select count(*) from public.audit_log where action like 'finance.%') >= 8, 'تسجيل في سجل التدقيق');
reset role;
