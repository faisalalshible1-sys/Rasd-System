-- اختبارات توسيع المالية: «محال للصرف»، وسجل الدفعات، والاستقطاعات المخصصة، والنسب الافتراضية، والدفعة المقدمة.
-- تُشغَّل بعد 60_finance_security_test.sql على القاعدة نفسها.
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
create or replace function pg_temp.pid(p_assign text) returns uuid language sql security definer as $$
  select id from public.projects where assign_no = p_assign
$$;
create or replace function pg_temp.fin(p_assign text) returns public.projects language sql security definer as $$
  select * from public.projects where assign_no = p_assign
$$;
create or replace function pg_temp.work_id(p_assign text, p_n integer default 1) returns uuid language sql security definer as $$
  select w.id from public.contract_works w where w.project_id = (select id from public.projects where assign_no = p_assign)
   order by w.sort, w.created_at offset p_n - 1 limit 1
$$;
create or replace function pg_temp.sessions_of(p_email text) returns bigint language sql security definer as $$
  select count(*) from auth.sessions s join auth.users u on u.id = s.user_id where u.email = p_email
$$;
create or replace function pg_temp.session_of(p_email text, p_ua text) returns uuid language sql security definer as $$
  select s.id from auth.sessions s join auth.users u on u.id = s.user_id where u.email = p_email and coalesce(s.user_agent, '') like p_ua limit 1
$$;
create or replace function pg_temp.director_notified(p_like text) returns boolean language sql security definer as $$
  select exists (select 1 from public.notifications n join public.profiles p on p.id = n.user_id where p.role = 'director' and n.title like p_like)
$$;
grant execute on all functions in schema pg_temp to authenticated, anon;


create or replace function pg_temp.x_of(p_ref text) returns public.contract_extracts language sql security definer as $$
  select * from public.contract_extracts where ref_no = p_ref
$$;
create or replace function pg_temp.pays_of(p_ref text) returns bigint language sql security definer as $$
  select count(*) from public.extract_payments y join public.contract_extracts x on x.id = y.extract_id where x.ref_no = p_ref
$$;
grant execute on all functions in schema pg_temp to authenticated, anon;

-- ---------------------------------------------------------------- الإعدادات
set role authenticated;
select pg_temp.as_user('director.new@test.ly', 'aal2');
select public.set_setting('finance.deduction_types', '[{"key": "stamp", "label": "دمغة", "rate": 0.005}, {"key": "social", "label": "ضمان اجتماعي", "rate": null}]');
select public.set_setting('finance.retention_rate', '0.1');
select public.set_setting('finance.advance_recovery_rate', '0.2');
select pg_temp.expect_error($$select public.set_setting('finance.deduction_types', '[{"key": "Stamp!", "label": "x"}]')$$, 'مفتاح استقطاع غير صالح');
select pg_temp.expect_error($$select public.set_setting('finance.deduction_types', '[{"key": "a1", "label": "أ"}, {"key": "a1", "label": "ب ب"}]')$$, 'مفتاح استقطاع مكرر');
select pg_temp.expect_error($$select public.set_setting('finance.tax_rate', '0.9')$$, 'نسبة ضريبة كبيرة');

-- ---------------------------------------------------------------- الدفعة المقدمة
select pg_temp.as_user('k.contracts@test.ly');
select public.set_contract_advance(pg_temp.pid('010'), 50000, '2026-10-01');
select pg_temp.check((select advance_amount = 50000 and advance_paid_on = '2026-10-01' and advance_recovered = 0 from pg_temp.fin('010')),
                     'تسجيل الدفعة المقدمة للعقد');
select pg_temp.expect_error($q$update projects set advance_amount = 1 where assign_no = '010'$q$, 'تعديل الدفعة المقدمة مباشرة');
select pg_temp.check((select advance_amount = 50000 from pg_temp.fin('010')), 'الدفعة المقدمة لا تُعدَّل مباشرة');

-- ---------------------------------------------------------------- مستخلص باستقطاعات مخصصة واسترداد دفعة مقدمة
select public.save_extract(null, pg_temp.pid('010'), null, 'ف-1', 'interim', null, null, '2026-10-20', 100000, 10000, 20000, 0, 0, 0,
                           'approved', '2026-10-25', 0, null, '', null, '', '{"stamp": 500, "social": 1500}');
select pg_temp.check((select custom_total = 2000 and net_amount = 68000 and (custom_deductions ->> 'stamp')::numeric = 500 from pg_temp.x_of('ف-1')),
                     'الاستقطاعات المخصصة تدخل في الصافي');
select pg_temp.check((select advance_recovered = 20000 and executed_value = 100000 from pg_temp.fin('010')), 'المسترد من الدفعة المقدمة');
select pg_temp.expect_error($$select public.save_extract(null, pg_temp.pid('010'), null, 'ف-x', 'interim', null, null, null, 100000, 0, 40000, 0, 0, 0,
                                                         'submitted', null, 0, null, '', null, '', '{}')$$, 'استرداد يتجاوز رصيد الدفعة المقدمة');
select pg_temp.expect_error($$select public.save_extract(null, pg_temp.pid('010'), null, 'ف-x', 'interim', null, null, null, 100, 0, 0, 0, 0, 0,
                                                         'submitted', null, 0, null, '', null, '', '{"Bad Key": 5}')$$, 'مفتاح استقطاع مخصص غير صالح');
select pg_temp.expect_error($$select public.set_contract_advance(pg_temp.pid('010'), 10000, null)$$, 'دفعة مقدمة أقل من المسترد');

-- ---------------------------------------------------------------- محال للصرف
select public.save_extract((select id from pg_temp.x_of('ف-1')), null, null, 'ف-1', 'interim', null, null, '2026-10-20', 100000, 10000, 20000, 0, 0, 0,
                           'referred', '2026-10-25', 0, null, '', null, 'إحالة 77/2026', '{"stamp": 500, "social": 1500}');
select pg_temp.check((select status = 'referred' and referred_on = current_date and referral_no = 'إحالة 77/2026' from pg_temp.x_of('ف-1'))
                     and (select extracts_count = 1 and executed_value = 100000 from pg_temp.fin('010')),
                     'الإحالة للصرف بتاريخها ورقمها، والمحال يدخل في المنفذ');

-- ---------------------------------------------------------------- سجل الدفعات
select public.add_extract_payment((select id from pg_temp.x_of('ف-1')), 30000, '2026-11-01', 'cheque', 'صك 1234', '');
select pg_temp.check((select paid_amount = 30000 and status = 'referred' and paid_on = '2026-11-01' from pg_temp.x_of('ف-1'))
                     and (select extracts_paid = 30000 from pg_temp.fin('010')), 'دفعة جزئية من السجل');
select pg_temp.expect_error($$select public.add_extract_payment((select id from pg_temp.x_of('ف-1')), 40000, null, 'transfer', '', '')$$,
                            'دفعة أكبر من المتبقي');
select pg_temp.expect_error($$select public.add_extract_payment((select id from pg_temp.x_of('ف-1')), 10, null, 'bitcoin', '', '')$$, 'طريقة دفع غير معروفة');
select pg_temp.expect_error($$select public.save_extract((select id from pg_temp.x_of('ف-1')), null, null, 'ف-1', 'interim', null, null, null, 100000, 10000, 20000, 0, 0, 0,
                                                         'paid', null, 0, null, '', null, '', '{"stamp": 500, "social": 1500}')$$,
                            '«مدفوع» قبل اكتمال الدفعات');
select public.add_extract_payment((select id from pg_temp.x_of('ف-1')), 38000, '2026-11-04', 'transfer', 'حوالة 9', 'الباقي');
select pg_temp.check((select paid_amount = 68000 and status = 'paid' and paid_on = '2026-11-04' from pg_temp.x_of('ف-1'))
                     and pg_temp.pays_of('ف-1') = 2, 'اكتمال الدفعات يجعل المستخلص مدفوعاً');
select pg_temp.expect_error($$select public.delete_extract_payment((select y.id from extract_payments y join contract_extracts x on x.id = y.extract_id
                                                                     where x.ref_no = 'ف-1' and y.ref_no = 'حوالة 9'))$$,
                            'مكتب العقود يحذف دفعة لمستخلص مدفوع');
select pg_temp.check(exists (select 1 from audit_log where action = 'finance.payment_add'), 'الدفعات في السجل المالي');

select pg_temp.as_user('director.new@test.ly', 'aal2');
select public.delete_extract_payment((select y.id from extract_payments y join contract_extracts x on x.id = y.extract_id
                                       where x.ref_no = 'ف-1' and y.ref_no = 'حوالة 9'));
select pg_temp.check((select paid_amount = 30000 and status = 'referred' from pg_temp.x_of('ف-1')), 'حذف دفعة يعيد المستخلص محالاً للصرف');

-- مستخلص دُفع قبل السجل: أول دفعة تسجّل ما سبق رصيداً افتتاحياً
select pg_temp.as_user('k.contracts@test.ly');
select public.save_extract(null, pg_temp.pid('011'), null, 'ف-2', 'interim', null, null, null, 50000, 0, 0, 0, 0, 0,
                           'approved', null, 20000, '2026-10-10', '', null, '', '{}');
select public.add_extract_payment((select id from pg_temp.x_of('ف-2')), 30000, '2026-11-02', 'transfer', 'ح-3', '');
select pg_temp.check((select paid_amount = 50000 and status = 'paid' from pg_temp.x_of('ف-2')) and pg_temp.pays_of('ف-2') = 2,
                     'الرصيد السابق لا يضيع عند بدء سجل الدفعات');

-- الصيغة السابقة تحفظ الإحالة والاستقطاعات المخصصة
select pg_temp.as_user('director.new@test.ly', 'aal2');
select public.save_extract((select id from pg_temp.x_of('ف-1')), null, null, 'ف-1', 'interim', null, null, null, 100000, 10000, 20000, 0, 0, 0,
                           'referred', null, 0, null, 'من النسخة السابقة');
select pg_temp.check((select custom_total = 2000 and referral_no = 'إحالة 77/2026' and notes = 'من النسخة السابقة' from pg_temp.x_of('ف-1')),
                     'الصيغة السابقة لحفظ المستخلص تبقي الحقول الجديدة');

-- الدمج ينقل الدفعات مع مستخلصاتها
select pg_temp.as_user('k.contracts@test.ly');
select public.merge_contracts(pg_temp.pid('010'), array[pg_temp.pid('011')]);
select pg_temp.check((select count(*) = 0 from extract_payments y where y.project_id = pg_temp.pid('011'))
                     and (select extracts_paid = 80000 from pg_temp.fin('010')), 'الدفعات تنتقل مع المستخلص عند الدمج');
select pg_temp.as_user('director.new@test.ly', 'aal2');
select public.unmerge_contract(pg_temp.pid('011'));
select pg_temp.check((select count(*) = 2 from extract_payments y where y.project_id = pg_temp.pid('011'))
                     and (select extracts_paid = 30000 from pg_temp.fin('010')), 'وتعود بفك الدمج');

-- ملخص المساعد
select pg_temp.check((select (c -> 'finance_defaults' ->> 'retention_rate') = '0.1' and (c -> 'extract_statuses') ? 'referred' from public.ai_context() c),
                     'ملخص Claude يشمل النسب الافتراضية والحالات');
select pg_temp.check((select bool_and(prosrc is not null) from pg_proc where proname = 'save_extract'), 'صيغتا حفظ المستخلص');
reset role;

\echo 'FINANCE V5 TESTS PASSED'
