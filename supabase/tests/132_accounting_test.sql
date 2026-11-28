-- اختبارات الترحيل 50: المحاسبة (الدليل والقيود المزدوجة والأستاذ وميزان المراجعة والقيود الآلية)
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
create or replace function pg_temp.gl(p_code text) returns uuid language sql security definer as $$ select id from public.fin_gl_accounts where code = p_code $$;

update app_settings set value = 'false' where key in ('security.freeze', 'security.require_mfa_all');
update profiles set locked_until = null where email in ('director.new@test.ly', 'u.qc@test.ly', 'k.qa@test.ly', 'k.staff@test.ly', 'pending@test.ly');
create temp table e (k text primary key, v uuid);
grant all on e to authenticated;

select pg_temp.check((select count(*) from public.fin_gl_accounts) >= 21 and (select count(*) from public.fin_gl_map) = 6, 'الدليل الابتدائي والتعيينات الستة');
select pg_temp.as_user('director.new@test.ly', 'aal2');
set role authenticated;
select public.finance_perm_set(pg_temp.uid('k.staff@test.ly'), 'edit', false);
select public.finance_perm_set(pg_temp.uid('k.staff@test.ly'), 'approve', false);

-- دليل الحسابات
insert into e select 'sub', public.fin_gl_account_save(null, '5130', 'مصروفات صيانة', 'expense', pg_temp.gl('5'), true, true);
select pg_temp.expect_error($q$select public.fin_gl_account_save(null, '5130', 'مكرر', 'expense', null, true)$q$, 'رمز مكرر');
select pg_temp.expect_error(format($q$select public.fin_gl_account_save(null, '5140', 'س', 'asset', %L, true)$q$, pg_temp.gl('5')), 'نوع يخالف نوع الأب');
select pg_temp.expect_error(format($q$select public.fin_gl_account_save(null, '51401', 'س', 'expense', %L, true)$q$, pg_temp.gl('5110')), 'الأب حساب فرعي');
select pg_temp.expect_error($q$select public.fin_gl_account_save(null, 'رمز عربي', 'س', 'expense', null, true)$q$, 'رمز غير صالح');
select pg_temp.expect_error($q$insert into public.fin_gl_accounts (code, name, type) values ('9', 'مباشر', 'asset')$q$, 'لا كتابة مباشرة');
select public.fin_gl_account_delete((select v from e where k = 'sub'));
select pg_temp.expect_error(format($q$select public.fin_gl_account_delete(%L)$q$, pg_temp.gl('2110')), 'حساب معيَّن لقيود آلية لا يُحذف');

-- قيد يدوي: مسودة ثم ترحيل
insert into e select 'j1', public.fin_journal_save(null, date '2027-04-01', 'رصيد افتتاحي', jsonb_build_array(
  jsonb_build_object('account', pg_temp.gl('1110'), 'debit', 10000, 'credit', 0),
  jsonb_build_object('account', pg_temp.gl('3100'), 'debit', 0, 'credit', 10000)));
select pg_temp.expect_error($q$select public.fin_journal_save(null, date '2027-04-01', 'س', jsonb_build_array(jsonb_build_object('account', null, 'debit', 1, 'credit', 0), jsonb_build_object('account', null, 'debit', 0, 'credit', 1)))$q$, 'سطر بلا حساب');
select pg_temp.expect_error(format($q$select public.fin_journal_save(null, date '2027-04-01', 'س', jsonb_build_array(jsonb_build_object('account', %L, 'debit', 1, 'credit', 1), jsonb_build_object('account', %L, 'debit', 0, 'credit', 1)))$q$, pg_temp.gl('1110'), pg_temp.gl('3100')), 'سطر بمدين ودائن معاً');
select pg_temp.expect_error(format($q$select public.fin_journal_save(null, date '2027-04-01', 'س', jsonb_build_array(jsonb_build_object('account', %L, 'debit', 1, 'credit', 0), jsonb_build_object('account', %L, 'debit', 0, 'credit', 1)))$q$, pg_temp.gl('1'), pg_temp.gl('3100')), 'قيد على حساب رئيسي');
select pg_temp.expect_error(format($q$select public.fin_journal_save(null, date '2027-04-01', 'س', jsonb_build_array(jsonb_build_object('account', %L, 'debit', 1, 'credit', 0)))$q$, pg_temp.gl('1110')), 'قيد بسطر واحد');
insert into e select 'bad', public.fin_journal_save(null, date '2027-04-02', 'غير متوازن', jsonb_build_array(
  jsonb_build_object('account', pg_temp.gl('1110'), 'debit', 100, 'credit', 0),
  jsonb_build_object('account', pg_temp.gl('3100'), 'debit', 0, 'credit', 99.999)));
select pg_temp.check((select entry_no is null and status = 'draft' from public.fin_journals where id = (select v from e where k = 'j1')), 'المسودة بلا رقم');
select pg_temp.expect_error(format($q$select public.fin_journal_post(%L)$q$, (select v from e where k = 'bad')), 'ترحيل قيد غير متوازن');
select public.fin_journal_delete((select v from e where k = 'bad'));
select public.fin_journal_post((select v from e where k = 'j1'));
select pg_temp.check((select entry_no is not null and status = 'posted' from public.fin_journals where id = (select v from e where k = 'j1')), 'الترحيل يعطي رقماً');
select pg_temp.expect_error(format($q$select public.fin_journal_post(%L)$q$, (select v from e where k = 'j1')), 'لا ترحيل مرتين');
select pg_temp.expect_error(format($q$select public.fin_journal_save(%L, date '2027-04-01', 'تعديل', jsonb_build_array(jsonb_build_object('account', %L, 'debit', 1, 'credit', 0), jsonb_build_object('account', %L, 'debit', 0, 'credit', 1)))$q$, (select v from e where k = 'j1'), pg_temp.gl('1110'), pg_temp.gl('3100')), 'لا تعديل لمرحَّل');
select pg_temp.expect_error(format($q$select public.fin_journal_delete(%L)$q$, (select v from e where k = 'j1')), 'لا حذف لمرحَّل');
reset role;
select pg_temp.expect_error(format($q$update public.fin_journal_lines set debit = 5 where journal_id = %L and line_no = 1$q$, (select v from e where k = 'j1')), 'المشغّل يمنع تعديل سطور مرحَّلة حتى بصلاحية عليا');
select pg_temp.expect_error(format($q$delete from public.fin_journals where id = %L$q$, (select v from e where k = 'j1')), 'المشغّل يمنع حذف قيد مرحَّل');
select pg_temp.as_user('director.new@test.ly', 'aal2');
set role authenticated;

-- ميزان المراجعة والعكس
select pg_temp.check((select debit = 10000 and credit = 0 and closing = 10000 from public.fin_trial_balance(date '2027-04-01', date '2027-04-30') where code = '1110'), 'الخزينة مدين 10000 وختامي 10000');
select pg_temp.check((select credit = 10000 and closing = 10000 from public.fin_trial_balance(date '2027-04-01', date '2027-04-30') where code = '3100'), 'الأرصدة الافتتاحية دائن بجانبها الطبيعي');
select pg_temp.check((select sum(debit) = sum(credit) from public.fin_trial_balance(date '2027-04-01', date '2027-04-30')), 'ميزان المراجعة متوازن');
select pg_temp.check((select opening = 10000 and debit = 0 and closing = 10000 from public.fin_trial_balance(date '2027-05-01', date '2027-05-31') where code = '1110'), 'رصيد افتتاحي لفترة لاحقة');
select pg_temp.expect_error(format($q$select public.fin_journal_reverse(%L, 'x')$q$, (select v from e where k = 'j1')), 'سبب العكس قصير');

-- الحسابات المالية والتحويلات: الربط شرط الترحيل
insert into e select 'ca', public.fin_account_save(null, 'خزينة المحاسبة', 'cash', 5000, true);
insert into e select 'cb', public.fin_account_save(null, 'مصرف المحاسبة', 'bank', 0, true);
select pg_temp.expect_error(format($q$select public.fin_account_link(%L, %L)$q$, (select v from e where k = 'ca'), pg_temp.gl('2110')), 'الربط بحساب أصل وحده');
select pg_temp.expect_error(format($q$select public.fin_account_link(%L, %L)$q$, (select v from e where k = 'ca'), pg_temp.gl('11')), 'الربط بحساب فرعي وحده');
insert into e select 't1', public.fin_transfer_create((select v from e where k = 'ca'), (select v from e where k = 'cb'), 1200.5, date '2027-04-10', 'إيداع');
select pg_temp.expect_error(format($q$select public.fin_transfer_decide(%L, true)$q$, (select v from e where k = 't1')), 'لا ترحيل لحساب غير مربوط');
select public.fin_account_link((select v from e where k = 'ca'), pg_temp.gl('1110'));
select pg_temp.expect_error(format($q$select public.fin_account_link(%L, %L)$q$, (select v from e where k = 'cb'), pg_temp.gl('1110')), 'حساب الدليل لحساب مالي واحد');
select public.fin_account_link((select v from e where k = 'cb'), pg_temp.gl('1120'));
select public.fin_transfer_decide((select v from e where k = 't1'), true);
select pg_temp.check((select count(*) = 1 and bool_and(status = 'posted') and min(source) = 'transfer' from public.fin_journals where source_id = (select v from e where k = 't1')), 'قيد آلي مرحَّل للتحويل');
select pg_temp.check((select debit = 1200.5 from public.fin_trial_balance(date '2027-04-01', date '2027-04-30') where code = '1120') and
                     (select credit = 1200.5 from public.fin_trial_balance(date '2027-04-01', date '2027-04-30') where code = '1110'), 'التحويل: مدين المستلِم ودائن المحوَّل منه');

-- قيد كشف المرتبات الآلي
insert into e select 'emp', public.fin_employee_save(null, 'موظف المحاسبة', 'مهندس', 3000, date '2026-01-01', 'active', null, true, false, false, '');
select public.fin_allowance_save(null, (select v from e where k = 'emp'), 'بدل', 300, true);
select public.fin_attendance_month_set((select v from e where k = 'emp'), date '2027-04-01', 2, 0, 0, '');
select public.fin_payroll_generate(date '2027-04-01');
select pg_temp.check((select count(*) = 0 from public.fin_journals where source = 'payroll'), 'التوليد لا يُنشئ قيداً');
select public.fin_payroll_approve(date '2027-04-01');
select pg_temp.check((select count(*) = 1 from public.fin_journals where source = 'payroll' and status = 'posted'), 'الاعتماد يُنشئ قيداً آلياً مرحَّلاً');
select pg_temp.check((select sum(l.debit) = sum(l.credit) and sum(l.debit) = (select sum(gross) - sum(absence) from public.fin_payroll_lines x join public.fin_payrolls p on p.id = x.payroll_id where p.period = date '2027-04-01')
                       from public.fin_journal_lines l join public.fin_journals j on j.id = l.journal_id where j.source = 'payroll'), 'قيد المرتبات متوازن ومدينه الإجمالي − الغياب');
select pg_temp.check((select l.credit = (select sum(net) from public.fin_payroll_lines x join public.fin_payrolls p on p.id = x.payroll_id where p.period = date '2027-04-01')
                       from public.fin_journal_lines l join public.fin_journals j on j.id = l.journal_id where j.source = 'payroll' and l.account_id = pg_temp.gl('2110')), 'دائن المرتبات المستحقة = الصافي');
select pg_temp.expect_error($q$select public.fin_journal_reverse((select id from public.fin_journals where source = 'payroll' limit 1), 'محاولة عكس آلي')$q$, 'القيد الآلي لا يُعكس يدوياً');
select public.fin_payroll_reopen(date '2027-04-01', 'تصحيح الحضور');
select pg_temp.check((select count(*) = 1 from public.fin_journals where source = 'payroll_reversal' and status = 'posted')
                 and (select count(*) = 1 from public.fin_journals where source = 'payroll' and reversed_by is not null), 'التراجع يعكس القيد الآلي');
select pg_temp.check((select coalesce(sum(debit), 0) = coalesce(sum(credit), 0) from public.fin_trial_balance(date '2027-04-01', current_date + 1) where code in ('5110', '2110', '2120', '2130', '2140', '1210')) and
                     (select coalesce(sum(closing), 0) = 0 from public.fin_trial_balance(date '2020-01-01', date '2030-12-31') where code in ('5110', '2110', '2120')), 'بعد العكس أرصدة المرتبات صفر');
select public.fin_payroll_approve(date '2027-04-01');
select pg_temp.check((select count(*) = 2 from public.fin_journals where source = 'payroll'), 'إعادة الاعتماد تُنشئ قيداً جديداً');

-- عكس قيد يدوي
select public.fin_journal_reverse((select v from e where k = 'j1'), 'خطأ في الإدخال');
select pg_temp.check((select reversed_by is not null and reverse_reason = 'خطأ في الإدخال' from public.fin_journals where id = (select v from e where k = 'j1')), 'القيد الأصلي معلَّم معكوساً بسببه');
select pg_temp.expect_error(format($q$select public.fin_journal_reverse(%L, 'مرة ثانية')$q$, (select v from e where k = 'j1')), 'لا عكس مرتين');
select pg_temp.expect_error(format($q$select public.fin_journal_reverse((select reversed_by from public.fin_journals where id = %L), 'عكس العكسي')$q$, (select v from e where k = 'j1')), 'القيد العكسي لا يُعكس');
select pg_temp.expect_error(format($q$select public.fin_gl_account_save(%L, '1110', 'الخزينة', 'asset', %L, true)$q$, pg_temp.gl('1110'), pg_temp.gl('12')), 'لا يُنقل حساب عليه قيود');

-- الصلاحيات: التحرير يحرّر ولا يرحّل، والاعتماد يرحّل ولا يحرّر، وغير المخوَّل لا يرى
reset role;
select pg_temp.as_user('director.new@test.ly', 'aal2');
set role authenticated;
select public.finance_perm_set(pg_temp.uid('k.staff@test.ly'), 'edit', true);
reset role;
select pg_temp.as_user('k.staff@test.ly');
set role authenticated;
insert into e select 'j2', public.fin_journal_save(null, date '2027-04-05', 'من المحرر', jsonb_build_array(
  jsonb_build_object('account', pg_temp.gl('1110'), 'debit', 5, 'credit', 0), jsonb_build_object('account', pg_temp.gl('4100'), 'debit', 0, 'credit', 5)));
select pg_temp.expect_error(format($q$select public.fin_journal_post(%L)$q$, (select v from e where k = 'j2')), 'التحرير لا يرحّل القيد');
select pg_temp.expect_error(format($q$select public.fin_gl_map_set('payroll_expense', %L)$q$, pg_temp.gl('5120')), 'التحرير لا يعيّن حسابات القيود الآلية');
reset role;
select pg_temp.as_user('director.new@test.ly', 'aal2');
set role authenticated;
select public.finance_perm_set(pg_temp.uid('k.staff@test.ly'), 'edit', false);
select public.fin_gl_map_set('payroll_expense', pg_temp.gl('5120'));
select pg_temp.expect_error(format($q$select public.fin_gl_map_set('payroll_net', %L)$q$, pg_temp.gl('5110')), 'تعيين المرتبات المستحقة لحساب خصوم وحده');
select public.fin_gl_map_set('payroll_expense', pg_temp.gl('5110'));
reset role;
select pg_temp.as_user('pending@test.ly');
set role authenticated;
select pg_temp.check((select count(*) from public.fin_journals) = 0 and (select count(*) from public.fin_gl_accounts) = 0 and (select count(*) from public.fin_trial_balance(date '2020-01-01', date '2030-01-01')) = 0,
                     'غير المخوَّل لا يرى الدليل ولا القيود ولا الميزان');
select pg_temp.expect_error($q$select public.fin_journal_auto('manual', null, current_date, 'x', '[]'::jsonb)$q$, 'الدالة الداخلية للقيود الآلية غير متاحة للمستخدم');
reset role;
select pg_temp.as_user('director.new@test.ly', 'aal2');
set role authenticated;
select pg_temp.check((select count(*) from public.audit_log where action in ('finance.gl_save', 'finance.gl_delete', 'finance.gl_link', 'finance.gl_map_set',
                      'finance.journal_save', 'finance.journal_delete', 'finance.journal_post', 'finance.journal_reverse')) >= 10, 'تسجيل في سجل التدقيق');
reset role;
