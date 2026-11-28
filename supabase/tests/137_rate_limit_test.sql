-- اختبارات الترحيل 55: تحديد معدل الإجراءات الحساسة
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
  begin execute p_sql; exception when others then raise notice 'PASS (رُفض كما يجب): % — %', p_label, sqlerrm; return; end;
  raise exception 'FAIL: كان يجب رفض: %', p_label;
end $$;
create or replace function pg_temp.check(p_ok boolean, p_label text) returns void language plpgsql as $$
begin
  if not coalesce(p_ok, false) then raise exception 'FAIL: %', p_label; end if;
  raise notice 'PASS: %', p_label;
end $$;

select pg_temp.check((select count(*) = 7 from pg_proc p where p.pronamespace = 'public'::regnamespace
                       and p.proname in ('fin_disb_decide', 'fin_disb_reverse', 'fin_guarantee_release_decide', 'fin_journal_reverse',
                                         'fin_payroll_approve', 'fin_transfer_decide', 'sec_freeze')
                       and pg_get_functiondef(p.oid) like '%perform public.sec_rate_hit(%'), 'الدوال السبع الحساسة محمية بتحديد المعدل');

-- الحد يعمل لكل مستخدم ولكل إجراء
select pg_temp.as_user('k.staff@test.ly');
set role authenticated;
select public.sec_rate_hit('test.rate', 3, 600);
select public.sec_rate_hit('test.rate', 3, 600);
select public.sec_rate_hit('test.rate', 3, 600);
select pg_temp.expect_error($q$select public.sec_rate_hit('test.rate', 3, 600)$q$, 'الطلب الرابع يتجاوز الحد');
select public.sec_rate_hit('test.other', 3, 600);
reset role;
select pg_temp.check(true, 'إجراء آخر لا يتأثر بحد غيره');
select pg_temp.as_user('director.new@test.ly', 'aal2');
set role authenticated;
select public.sec_rate_hit('test.rate', 3, 600);
reset role;
select pg_temp.check(true, 'مستخدم آخر لا يتأثر');

-- النداءات الداخلية (بلا مستخدم) لا تُحدّ
select set_config('request.jwt.claim.sub', '', false);
select set_config('request.jwt.claims', '{}', false);
select public.sec_rate_hit('test.rate', 1, 600);
select public.sec_rate_hit('test.rate', 1, 600);
select pg_temp.check(true, 'النداء الداخلي بلا مستخدم لا يُحدّ');

-- الجدول مغلق على الواجهة
select pg_temp.as_user('k.staff@test.ly');
set role authenticated;
select pg_temp.expect_error($q$select count(*) from public.sec_rate_hits$q$, 'الواجهة لا تقرأ جدول العدّاد');
reset role;
delete from public.sec_rate_hits where action like 'test.%';
