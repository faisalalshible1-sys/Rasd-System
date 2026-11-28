-- اختبارات الترحيل 49: الضمانات والحسابات والتحويلات
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

select pg_temp.as_user('director.new@test.ly', 'aal2');
set role authenticated;
select public.finance_perm_set(pg_temp.uid('k.staff@test.ly'), 'edit', false);
select public.finance_perm_set(pg_temp.uid('k.staff@test.ly'), 'approve', false);

-- الضمانات
insert into e select 'g1', public.fin_guarantee_save(null, 'initial', null, 'شركة الأفق', 50000, date '2026-01-10', date '2027-01-10', 'LG-1', '');
insert into e select 'g2', public.fin_guarantee_save(null, 'deposit', (select id from public.projects limit 1), 'مقاول س', 8000.5, date '2026-02-01');
select pg_temp.expect_error($q$select public.fin_guarantee_save(null, 'x', null, 'ج', 1, date '2026-01-01')$q$, 'نوع ضمان غير صالح');
select pg_temp.expect_error($q$select public.fin_guarantee_save(null, 'final', null, 'ج', 0, date '2026-01-01')$q$, 'مبلغ صفر');
select pg_temp.expect_error($q$select public.fin_guarantee_save(null, 'final', null, 'ج', 5, date '2026-03-01', date '2026-02-01')$q$, 'انتهاء قبل الإصدار');
select pg_temp.expect_error($q$select public.fin_guarantee_save(null, 'final', gen_random_uuid(), 'ج', 5, date '2026-03-01')$q$, 'عقد غير موجود');
select pg_temp.expect_error($q$insert into public.fin_guarantees (kind, party, amount, issued_on) values ('initial', 'م', 1, current_date)$q$, 'لا كتابة مباشرة');
select public.fin_guarantee_save((select v from e where k = 'g1'), 'initial', null, 'شركة الأفق', 55000, date '2026-01-10', date '2027-01-10', 'LG-1', 'عُدّل');
select pg_temp.check((select amount = 55000 from public.fin_guarantees where id = (select v from e where k = 'g1')), 'تعديل ضمان محتجز');

-- دورة الاسترداد
select pg_temp.expect_error(format($q$select public.fin_guarantee_release_decide(%L, true)$q$, (select v from e where k = 'g1')), 'لا موافقة دون طلب');
select pg_temp.expect_error(format($q$select public.fin_guarantee_release_request(%L, 'x')$q$, (select v from e where k = 'g1')), 'سبب قصير');
select public.fin_guarantee_release_request((select v from e where k = 'g1'), 'انتهاء الضمان بعد الاستلام النهائي');
select pg_temp.check((select status = 'release_requested' from public.fin_guarantees where id = (select v from e where k = 'g1')), 'الطلب يجمّد الضمان');
select pg_temp.expect_error(format($q$select public.fin_guarantee_save(%L, 'initial', null, 'ج', 1, date '2026-01-10')$q$, (select v from e where k = 'g1')), 'لا تعديل بعد طلب الاسترداد');
select pg_temp.expect_error(format($q$select public.fin_guarantee_delete(%L)$q$, (select v from e where k = 'g1')), 'لا حذف بعد طلب الاسترداد');
select pg_temp.expect_error(format($q$select public.fin_guarantee_release_decide(%L, false, '')$q$, (select v from e where k = 'g1')), 'رفض بلا سبب');
select public.fin_guarantee_release_decide((select v from e where k = 'g1'), false, 'المستندات ناقصة');
select pg_temp.check((select status = 'held' and decision_note = 'المستندات ناقصة' from public.fin_guarantees where id = (select v from e where k = 'g1')), 'الرفض يعيده محتجزاً بسببه');
select public.fin_guarantee_release_request((select v from e where k = 'g1'), 'اكتملت المستندات');
select public.fin_guarantee_release_decide((select v from e where k = 'g1'), true, 'تمت المراجعة');
select pg_temp.check((select status = 'released' and released_by is not null from public.fin_guarantees where id = (select v from e where k = 'g1')), 'الاسترداد بموافقة');
select pg_temp.expect_error(format($q$select public.fin_guarantee_release_request(%L, 'مرة ثانية')$q$, (select v from e where k = 'g1')), 'لا طلب على مُسترد');

-- الحسابات والتحويلات
insert into e select 'a1', public.fin_account_save(null, 'الخزينة', 'cash', 10000, true);
insert into e select 'a2', public.fin_account_save(null, 'المصرف', 'bank', 0, true);
select pg_temp.expect_error($q$select public.fin_account_save(null, ' الخزينة ', 'cash', 1, true)$q$, 'اسم حساب مكرر');
select pg_temp.expect_error($q$select public.fin_account_save(null, 'س', 'x', 1, true)$q$, 'نوع حساب غير صالح');
select pg_temp.expect_error($q$select public.fin_account_save(null, 'س', 'cash', -1, true)$q$, 'افتتاحي سالب');
insert into e select 't1', public.fin_transfer_create((select v from e where k = 'a1'), (select v from e where k = 'a2'), 4000.25, date '2026-03-01', 'إيداع');
select pg_temp.expect_error(format($q$select public.fin_transfer_create(%L, %L, 1, date '2026-03-01')$q$, (select v from e where k = 'a1'), (select v from e where k = 'a1')), 'تحويل لنفس الحساب');
select pg_temp.expect_error(format($q$select public.fin_transfer_create(%L, %L, 0, date '2026-03-01')$q$, (select v from e where k = 'a1'), (select v from e where k = 'a2')), 'مبلغ تحويل صفر');
select pg_temp.check(public.fin_account_balance((select v from e where k = 'a1')) = 10000, 'المعلّق لا يغيّر الرصيد');
select public.fin_transfer_decide((select v from e where k = 't1'), true, '');
select pg_temp.check(public.fin_account_balance((select v from e where k = 'a1')) = 5999.75 and public.fin_account_balance((select v from e where k = 'a2')) = 4000.25, 'الترحيل يحرّك الرصيدين: 10000 − 4000.25 و0 + 4000.25');
select pg_temp.expect_error(format($q$select public.fin_transfer_decide(%L, true)$q$, (select v from e where k = 't1')), 'لا قرار على مرحَّل');
select pg_temp.expect_error(format($q$select public.fin_transfer_delete(%L)$q$, (select v from e where k = 't1')), 'لا حذف لمرحَّل');
insert into e select 't2', public.fin_transfer_create((select v from e where k = 'a2'), (select v from e where k = 'a1'), 9000, date '2026-03-02', 'يزيد عن الرصيد');
select pg_temp.expect_error(format($q$select public.fin_transfer_decide(%L, true)$q$, (select v from e where k = 't2')), 'التحويل فوق الرصيد');
select public.fin_transfer_decide((select v from e where k = 't2'), false, 'الرصيد لا يكفي');
select pg_temp.check((select status = 'rejected' from public.fin_transfers where id = (select v from e where k = 't2')), 'رفض التحويل بسبب');
insert into e select 't3', public.fin_transfer_create((select v from e where k = 'a1'), (select v from e where k = 'a2'), 1, date '2026-03-03');
select public.fin_transfer_delete((select v from e where k = 't3'));
select pg_temp.expect_error(format($q$select public.fin_account_save(%L, 'الخزينة', 'cash', 1, true)$q$, (select v from e where k = 'a1')), 'لا تعديل لافتتاحي حساب عليه ترحيل');
select pg_temp.expect_error(format($q$select public.fin_account_delete(%L)$q$, (select v from e where k = 'a1')), 'لا حذف لحساب عليه تحويلات');
select public.fin_account_save((select v from e where k = 'a2'), 'المصرف', 'bank', 0, false);
select pg_temp.expect_error(format($q$select public.fin_transfer_create(%L, %L, 1, date '2026-03-04')$q$, (select v from e where k = 'a1'), (select v from e where k = 'a2')), 'لا تحويل إلى حساب موقوف');
select public.fin_account_save((select v from e where k = 'a2'), 'المصرف', 'bank', 0, true);

-- الصلاحيات: التحرير لا يوافق، والاعتماد لا يحرّر، وغير المخوَّل لا يرى
reset role;
select pg_temp.as_user('director.new@test.ly', 'aal2');
set role authenticated;
select public.finance_perm_set(pg_temp.uid('k.staff@test.ly'), 'edit', true);
reset role;
select pg_temp.as_user('k.staff@test.ly');
set role authenticated;
insert into e select 'g3', public.fin_guarantee_save(null, 'final', null, 'جهة', 100, date '2026-05-01');
select public.fin_guarantee_release_request((select v from e where k = 'g3'), 'طلب من المحرر');
select pg_temp.expect_error(format($q$select public.fin_guarantee_release_decide(%L, true)$q$, (select v from e where k = 'g3')), 'التحرير لا يوافق على الاسترداد');
insert into e select 't4', public.fin_transfer_create((select v from e where k = 'a1'), (select v from e where k = 'a2'), 1, date '2026-05-02');
select pg_temp.expect_error(format($q$select public.fin_transfer_decide(%L, true)$q$, (select v from e where k = 't4')), 'التحرير لا يوافق على التحويل');
reset role;
select pg_temp.as_user('director.new@test.ly', 'aal2');
set role authenticated;
select public.finance_perm_set(pg_temp.uid('k.staff@test.ly'), 'edit', false);
reset role;
select pg_temp.as_user('k.staff@test.ly');
set role authenticated;
select pg_temp.check((select count(*) from public.fin_guarantees) >= 3, 'موظف المكتب يطّلع على الضمانات');
select pg_temp.expect_error($q$select public.fin_account_save(null, 'ممنوع', 'cash', 1, true)$q$, 'موظف المكتب لا يحرّر');
reset role;
select pg_temp.as_user('pending@test.ly');
set role authenticated;
select pg_temp.check((select count(*) from public.fin_guarantees) = 0 and (select count(*) from public.fin_accounts) = 0 and (select count(*) from public.fin_transfers) = 0,
                     'غير المخوَّل لا يرى الضمانات ولا الحسابات');
reset role;
select pg_temp.as_user('director.new@test.ly', 'aal2');
set role authenticated;
select pg_temp.check((select count(*) from public.audit_log where action in ('finance.guar_save', 'finance.guar_release_request', 'finance.guar_release_approve',
                      'finance.guar_release_reject', 'finance.acct_save', 'finance.transfer_create', 'finance.transfer_approve', 'finance.transfer_reject', 'finance.transfer_delete')) >= 12,
                     'تسجيل في سجل التدقيق');
reset role;
