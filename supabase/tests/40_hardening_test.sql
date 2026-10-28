-- اختبارات التحصين الأمني (20261028000009_security_hardening.sql).
-- تُشغَّل بعد 30_users_admin_test.sql على القاعدة نفسها.
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

-- ---------------------------------------------------------------- بنية التحصين
select pg_temp.check(
  (select bool_and(exists (select 1 from unnest(coalesce(p.proconfig, '{}')) c where c like 'search_path=%'))
     from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prokind = 'f'),
  'كل دوال المنظومة بمسار بحث ثابت');
select pg_temp.check(
  (select bool_and(not has_function_privilege('authenticated', p.oid, 'execute') and not has_function_privilege('anon', p.oid, 'execute'))
     from pg_proc p where p.pronamespace = 'public'::regnamespace
      and p.proname in ('actor_name', 'project_label', 'my_form_rights', 'can_edit_form', 'has_token', 'mfa_ok', 'is_auditor')),
  'الدوال الداخلية لا يستدعيها المستخدمون مباشرة');
select pg_temp.check(
  (select string_agg(p.proname, ',') = 'public_settings' from pg_proc p
    where p.pronamespace = 'public'::regnamespace and p.prosecdef and has_function_privilege('anon', p.oid, 'execute')),
  'الزائر قبل الدخول لا يستدعي إلا إعدادات الهوية العامة');
select pg_temp.check(
  (select bool_and(prosrc not like '%مدقق%') from pg_proc
    where pronamespace = 'public'::regnamespace and proname in ('security_overview', 'security_users', 'list_sessions', 'login_history', 'user_details')),
  'رسائل مركز الأمان باسم CISO');

-- ---------------------------------------------------------------- الاستدعاء المباشر مرفوض
set role authenticated;
select pg_temp.as_user('director.new@test.ly', 'aal2');
select pg_temp.expect_error($$select public.actor_name(auth.uid())$$, 'استدعاء actor_name مباشرة');
select pg_temp.expect_error($$select public.mfa_ok()$$, 'استدعاء mfa_ok مباشرة');
select pg_temp.expect_error($$select public.has_token((select id from projects limit 1), array['office_staff'])$$, 'استدعاء has_token مباشرة');
select pg_temp.expect_error($$select * from public.my_form_rights((select id from projects limit 1))$$, 'استدعاء my_form_rights مباشرة');

-- ---------------------------------------------------------------- المنظومة تعمل كما هي
select pg_temp.check(public.is_director() and public.can_audit(), 'دوال سياسات الوصول تعمل للمدير');
select pg_temp.check((select count(*) > 0 from projects), 'المدير يرى المشاريع');
select pg_temp.check((select count(*) > 0 from audit_log), 'سجل التدقيق يُقرأ');
select pg_temp.check((select (o ->> 'viewer') = 'director' from public.security_overview() o), 'مركز الأمان يعمل');
select pg_temp.check(public.set_form_status((select id from projects where assign_no = '005'), 'f03', 'wip') in ('applied', 'unchanged'),
                     'تحديث النماذج يعمل (يستدعي الدوال الداخلية من داخل المنظومة)');
select pg_temp.check(exists (select 1 from audit_log where actor_name is not null and actor_name <> '' and at > now() - interval '1 minute'),
                     'اسم المنفّذ يُكتب في السجل من داخل المنظومة');

select pg_temp.as_user('staff.new@test.ly', 'aal1');
select pg_temp.check(public.is_member(), 'دخول الموظف يعمل');
select pg_temp.check((select count(*) > 0 from projects), 'الموظف يرى المشاريع');
reset role;

-- ---------------------------------------------------------------- إشعار تغيير الدور
select pg_temp.check(not exists (select 1 from notifications where title like '%مدقق الأمن%'), 'لا يبقى إشعار بالاسم القديم');

\echo 'HARDENING TESTS PASSED'
