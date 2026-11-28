-- اختبارات الترحيل 51: المراجعة المالية واعتماد الصرف وقيده الآلي وربط المحتجز وحارس «المدفوع»
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
create temp table e (k text primary key, v uuid);
grant all on e to authenticated;
create or replace function pg_temp.i(p_k text) returns uuid language sql as $$ select v from e where k = p_k $$;
create or replace function pg_temp.d(p_id uuid) returns public.fin_disbursements language sql security definer as $$ select * from public.fin_disbursements where id = p_id $$;
create or replace function pg_temp.x(p_id uuid) returns public.contract_extracts language sql security definer as $$ select * from public.contract_extracts where id = p_id $$;
create or replace function pg_temp.paysum(p_id uuid) returns numeric language sql security definer as $$ select coalesce(sum(amount), 0) from public.extract_payments where extract_id = p_id $$;

update app_settings set value = 'false' where key in ('security.freeze', 'security.require_mfa_all');
update profiles set locked_until = null where email in ('director.new@test.ly', 'u.qc@test.ly', 'k.qa@test.ly', 'k.staff@test.ly', 'pending@test.ly', 'k.contracts@test.ly');

select pg_temp.check((select count(*) = 1 from public.fin_gl_map where key = 'extract_payable'), 'تعيين مستحقات المقاولين الابتدائي');

-- إعداد: عقد ومستخلصات بيد موظف العقود
select pg_temp.as_user('k.staff@test.ly');
set role authenticated;
insert into e select 'p', public.save_project(null, '{"assign_no": "T51-P", "name": "عقد الصرف", "company": "شركة الصرف", "department": "supervision"}');
select pg_temp.as_user('k.contracts@test.ly');
insert into e select 'x1', public.save_extract(null, pg_temp.i('p'), null, 'ص-1', 'interim', null, null, '2026-11-01', 100000, 5000, 0, 0, 0, 0,
                                               'approved', '2026-11-05', 0, null, '', null, '', '{}');
insert into e select 'x2', public.save_extract(null, pg_temp.i('p'), null, 'ص-2', 'interim', null, null, null, 20000, 0, 0, 0, 0, 0,
                                               'submitted', null, 0, null, '', null, '', '{}');
insert into e select 'x3', public.save_extract(null, pg_temp.i('p'), null, 'ص-3', 'interim', null, null, null, 10000, 0, 0, 0, 0, 0,
                                               'approved', '2026-11-06', 0, null, '', null, '', '{}');

-- حارس «المدفوع»: لا من الدفعات المباشرة ولا من تعديل المستخلص لغير المدير
select pg_temp.expect_error($$select public.add_extract_payment(pg_temp.i('x1'), 100, date '2026-11-10', 'transfer', '', '')$$, 'الدفعة المباشرة لغير المدير');
select pg_temp.expect_error($$select public.save_extract(pg_temp.i('x1'), null, null, 'ص-1', 'interim', null, null, '2026-11-01', 100000, 5000, 0, 0, 0, 0,
                                                         'paid', '2026-11-05', 95000, '2026-11-10', '', null, '', '{}')$$, 'جعل المستخلص مدفوعاً من التعديل');
select pg_temp.expect_error($$select public.save_extract(null, pg_temp.i('p'), null, 'ص-9', 'interim', null, null, null, 1000, 0, 0, 0, 0, 0,
                                                         'approved', null, 500, '2026-11-10', '', null, '', '{}')$$, 'مستخلص جديد بمدفوع');

-- حسابات الصرف
reset role;
select pg_temp.as_user('director.new@test.ly', 'aal2');
set role authenticated;
select public.finance_perm_set(pg_temp.uid('k.staff@test.ly'), 'view', false);
select public.finance_perm_set(pg_temp.uid('k.staff@test.ly'), 'approve', false);
select public.finance_perm_set(pg_temp.uid('k.staff@test.ly'), 'edit', true);
insert into e select 'gl', public.fin_gl_account_save(null, '1130', 'خزينة الصرف', 'asset', pg_temp.gl('11'), true, true);
insert into e select 'ac', public.fin_account_save(null, 'خزينة الصرف', 'cash', 100000, true);
insert into e select 'au', public.fin_account_save(null, 'حساب غير مربوط', 'bank', 100000, true);
select public.fin_account_link(pg_temp.i('ac'), pg_temp.i('gl'));

-- الطلب
reset role;
select pg_temp.as_user('k.staff@test.ly');
set role authenticated;
select pg_temp.expect_error($$select public.fin_disb_request(pg_temp.i('x2'), 100, pg_temp.i('ac'), date '2026-11-10', 'transfer', '', '')$$, 'صرف مستخلص غير معتمد');
select pg_temp.expect_error($$select public.fin_disb_request(pg_temp.i('x1'), 0, pg_temp.i('ac'), date '2026-11-10', 'transfer', '', '')$$, 'مبلغ صفر');
select pg_temp.expect_error($$select public.fin_disb_request(pg_temp.i('x1'), 95000.001, pg_temp.i('ac'), date '2026-11-10', 'transfer', '', '')$$, 'فوق المتبقي');
select pg_temp.expect_error($$select public.fin_disb_request(pg_temp.i('x1'), 100, pg_temp.i('au'), date '2026-11-10', 'transfer', '', '')$$, 'حساب غير مربوط بالدليل');
select pg_temp.expect_error($$select public.fin_disb_request(pg_temp.i('x1'), 100, pg_temp.i('ac'), date '2026-11-10', 'visa', '', '')$$, 'طريقة دفع غير معروفة');
insert into e select 'd1', public.fin_disb_request(pg_temp.i('x1'), 40000, pg_temp.i('ac'), date '2026-11-10', 'transfer', 'ح-1', 'دفعة أولى');
select pg_temp.check((select status = 'requested' from pg_temp.d(pg_temp.i('d1'))), 'الطلب يبدأ «مطلوب»');
select pg_temp.expect_error($$select public.fin_disb_decide(pg_temp.i('d1'), true, '')$$, 'التحرير لا يعتمد الصرف');

-- المراجعة والمحتجز
select pg_temp.expect_error($$select public.fin_disb_review(pg_temp.i('d1'), true, '')$$, 'لا مراجعة قبل تسجيل المحتجز');
select pg_temp.expect_error($$select public.fin_guarantee_from_extract(pg_temp.i('x3'), 'جهة')$$, 'لا محتجز في المستخلص');
select pg_temp.expect_error($$select public.fin_guarantee_from_extract(pg_temp.i('x1'), '')$$, 'الجهة مطلوبة');
insert into e select 'g1', public.fin_guarantee_from_extract(pg_temp.i('x1'), 'شركة الصرف');
select pg_temp.check((select kind = 'retention' and amount = 5000 and extract_id = pg_temp.i('x1') and status = 'held' from public.fin_guarantees where id = pg_temp.i('g1')), 'المحتجز يُسجَّل ضماناً مرتبطاً بمبلغ الخصم');
select pg_temp.expect_error($$select public.fin_guarantee_from_extract(pg_temp.i('x1'), 'شركة الصرف')$$, 'لا تسجيل مكرر للمحتجز');
select public.fin_disb_review(pg_temp.i('d1'), true, 'سليم');
select pg_temp.check((select status = 'reviewed' and review_note = 'سليم' from pg_temp.d(pg_temp.i('d1'))), 'المراجعة المالية تنقل الطلب إلى «روجع»');
select pg_temp.expect_error($$select public.fin_disb_review(pg_temp.i('d1'), true, '')$$, 'لا مراجعة ثانية');

-- إلغاء وإعادة
insert into e select 'd2', public.fin_disb_request(pg_temp.i('x3'), 1000, pg_temp.i('ac'), date '2026-11-10', 'cash', '', '');
select public.fin_disb_cancel(pg_temp.i('d2'));
select pg_temp.check((select status = 'cancelled' from pg_temp.d(pg_temp.i('d2'))), 'الإلغاء قبل الاعتماد');
insert into e select 'd3', public.fin_disb_request(pg_temp.i('x3'), 1000, pg_temp.i('ac'), date '2026-11-10', 'cash', '', '');
select pg_temp.expect_error($$select public.fin_disb_review(pg_temp.i('d3'), false, '')$$, 'الإعادة تشترط سبباً');
select public.fin_disb_review(pg_temp.i('d3'), false, 'المرفقات ناقصة');
select pg_temp.check((select status = 'returned' from pg_temp.d(pg_temp.i('d3'))), 'الإعادة بسبب');
select pg_temp.check(public.fin_extract_remaining(pg_temp.i('x3')) = 10000, 'الملغى والمُعاد لا يحجزان من المتبقي');

-- الاعتماد
reset role;
select pg_temp.as_user('director.new@test.ly', 'aal2');
set role authenticated;
select pg_temp.check(public.fin_extract_remaining(pg_temp.i('x1')) = 55000, 'المتبقي = الصافي − طلب مفتوح');
select pg_temp.expect_error($$select public.fin_disb_decide(pg_temp.i('d3'), true, '')$$, 'لا اعتماد لطلب أُعيد');
select pg_temp.expect_error($$select public.fin_disb_decide(pg_temp.i('d1'), false, '')$$, 'الرفض يشترط سبباً');
select public.fin_disb_decide(pg_temp.i('d1'), true, 'موافق');
select pg_temp.check((select status = 'approved' and payment_id is not null and journal_id is not null from pg_temp.d(pg_temp.i('d1'))), 'الاعتماد يربط الدفعة والقيد');
select pg_temp.check(pg_temp.paysum(pg_temp.i('x1')) = 40000 and (select paid_amount = 40000 and status = 'approved' from pg_temp.x(pg_temp.i('x1'))), 'الدفعة سُجّلت والمستخلص لم يكتمل بعد');
select pg_temp.check(public.fin_account_balance(pg_temp.i('ac')) = 60000, 'الصرف المعتمد يخفّض رصيد الحساب');
select pg_temp.check((select j.source = 'disbursement' and j.status = 'posted' and
                      (select debit = 40000 from public.fin_journal_lines where journal_id = j.id and account_id = pg_temp.gl('2150')) and
                      (select credit = 40000 from public.fin_journal_lines where journal_id = j.id and account_id = pg_temp.i('gl'))
                      from public.fin_journals j where j.id = (select journal_id from pg_temp.d(pg_temp.i('d1')))), 'قيد الصرف: مدين المستحقات ودائن الخزينة');
select pg_temp.expect_error($$select public.fin_disb_decide(pg_temp.i('d1'), true, '')$$, 'لا اعتماد مرتين');

-- اكتمال الصافي فيصير مدفوعاً
reset role;
select pg_temp.as_user('k.staff@test.ly');
set role authenticated;
insert into e select 'd4', public.fin_disb_request(pg_temp.i('x1'), 55000, pg_temp.i('ac'), date '2026-11-12', 'cheque', 'ش-1', '');
select pg_temp.expect_error($$select public.fin_disb_request(pg_temp.i('x1'), 1, pg_temp.i('ac'), date '2026-11-12', 'cash', '', '')$$, 'الطلب المفتوح يحجز المتبقي كله');
select public.fin_disb_review(pg_temp.i('d4'), true, '');
reset role;
select pg_temp.as_user('director.new@test.ly', 'aal2');
set role authenticated;
select public.fin_disb_decide(pg_temp.i('d4'), true, '');
select pg_temp.check((select status = 'paid' and paid_amount = 95000 from pg_temp.x(pg_temp.i('x1'))), 'اكتمال الصافي يجعل المستخلص «مدفوعاً» عبر الدورة وحدها');
select pg_temp.check(public.fin_account_balance(pg_temp.i('ac')) = 5000, 'رصيد الحساب بعد الصرفين');
select pg_temp.expect_error($$select public.delete_extract_payment((select payment_id from pg_temp.d(pg_temp.i('d1'))))$$, 'دفعة صرف معتمد لا تُحذف');

-- رصيد لا يكفي
reset role;
select pg_temp.as_user('k.staff@test.ly');
set role authenticated;
insert into e select 'd5', public.fin_disb_request(pg_temp.i('x3'), 8000, pg_temp.i('ac'), date '2026-11-13', 'cash', '', '');
select public.fin_disb_review(pg_temp.i('d5'), true, '');
select pg_temp.expect_error($$select public.fin_disb_reverse(pg_temp.i('d4'), 'محاولة من المحرر')$$, 'التحرير لا يعكس الصرف');
reset role;
select pg_temp.as_user('director.new@test.ly', 'aal2');
set role authenticated;
select pg_temp.expect_error($$select public.fin_disb_decide(pg_temp.i('d5'), true, '')$$, 'الرصيد لا يكفي للصرف');
select public.fin_disb_decide(pg_temp.i('d5'), false, 'الرصيد غير كافٍ');
select pg_temp.check((select status = 'rejected' and decision_note = 'الرصيد غير كافٍ' from pg_temp.d(pg_temp.i('d5'))), 'رفض الصرف بسبب');

-- عكس الصرف
select pg_temp.expect_error($$select public.fin_disb_reverse(pg_temp.i('d4'), 'x')$$, 'سبب العكس قصير');
select public.fin_disb_reverse(pg_temp.i('d4'), 'صرف مكرر بالخطأ');
select pg_temp.check((select status = 'reversed' and reversal_journal is not null and payment_id is null from pg_temp.d(pg_temp.i('d4'))), 'عكس الصرف يربط قيد العكس');
select pg_temp.check((select status = 'approved' and paid_amount = 40000 from pg_temp.x(pg_temp.i('x1'))), 'عكس الصرف يعيد المستخلص «معتمداً» بمدفوعه السابق');
select pg_temp.check(public.fin_account_balance(pg_temp.i('ac')) = 60000, 'عكس الصرف يعيد الرصيد');
select pg_temp.check((select reversed_by is not null from public.fin_journals where id = (select journal_id from pg_temp.d(pg_temp.i('d4')))), 'قيد الصرف الأصلي معلَّم معكوساً');
select pg_temp.expect_error($$select public.fin_disb_reverse(pg_temp.i('d4'), 'مرة ثانية')$$, 'لا عكس مرتين');
select pg_temp.check((select sum(debit) = sum(credit) from public.fin_trial_balance(date '2020-01-01', date '2030-12-31')), 'ميزان المراجعة متوازن بعد القيود الجديدة');

-- المدير: دفعة تاريخية مباشرة تبقى ممكنة
select public.add_extract_payment(pg_temp.i('x3'), 500, date '2026-11-20', 'cash', 'تاريخي', '');
select pg_temp.check(pg_temp.paysum(pg_temp.i('x3')) = 500, 'دفعة المدير المباشرة للسجل التاريخي');

-- الصلاحيات والرؤية والتدقيق
select public.fin_gl_map_set('extract_payable', pg_temp.gl('2150'));
select pg_temp.expect_error($$select public.fin_gl_map_set('extract_payable', public.fin_gl_account_save(null, '5199', 'م', 'expense', null, true))$$, 'تعيين المستحقات لحساب مصروفات');
reset role;
select pg_temp.as_user('pending@test.ly');
set role authenticated;
select pg_temp.check((select count(*) from public.fin_disbursements) = 0, 'غير المخوَّل لا يرى طلبات الصرف');
select pg_temp.expect_error($$select public.fin_disb_request(pg_temp.i('x1'), 1, pg_temp.i('ac'), date '2026-11-10', 'cash', '', '')$$, 'غير المخوَّل لا يطلب');
reset role;
select pg_temp.as_user('director.new@test.ly', 'aal2');
set role authenticated;
select pg_temp.check((select count(distinct action) from public.audit_log where action in ('finance.disb_request', 'finance.disb_review', 'finance.disb_return', 'finance.disb_cancel',
                      'finance.disb_approve', 'finance.disb_reject', 'finance.disb_reverse')) = 7, 'كل إجراءات الصرف مسجّلة في سجل التدقيق');
reset role;
