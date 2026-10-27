-- اختبارات مدقق الأمن، والبيانات الكاملة للمستخدمين، وحذف المستخدم.
-- تُشغَّل بعد 20_platform_test.sql على القاعدة نفسها (حساب المدير مفعّل عليه التحقق بخطوتين).
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
create or replace function pg_temp.expect_no_change(p_sql text, p_label text) returns void language plpgsql as $$
declare n bigint;
begin
  begin
    execute p_sql;
    get diagnostics n = row_count;
  exception when others then
    raise notice 'PASS (رُفض كما يجب): % — %', p_label, sqlerrm;
    return;
  end;
  if n <> 0 then raise exception 'FAIL: % (تغيّر % صف)', p_label, n; end if;
  raise notice 'PASS (لم يتغير شيء): %', p_label;
end $$;
grant execute on all functions in schema pg_temp to authenticated, anon;

insert into auth.users (email, raw_user_meta_data) values
  ('auditor@test.ly', '{"full_name": "مدقق الأمن"}'),
  ('gone@test.ly',    '{"full_name": "موظف سيُحذف"}');
select count(*) as n_users from auth.users \gset

set role authenticated;

-- ---------------------------------------------------------------- منح دور مدقق الأمن
select pg_temp.as_user('director.new@test.ly', 'aal2');
select public.set_user_access((select id from profiles where email = 'auditor@test.ly'), 'security_auditor', null, true, 'مدقق الأمن');
select public.set_user_access((select id from profiles where email = 'gone@test.ly'), 'office_staff', null, true, null);
select pg_temp.check((select role::text = 'security_auditor' and active and department is null from profiles where email = 'auditor@test.ly'),
                     'المدير يمنح دور مدقق الأمن');

-- ---------------------------------------------------------------- التحقق بخطوتين إلزامي لمدقق الأمن
select pg_temp.as_user('auditor@test.ly', 'aal1');
select pg_temp.check(not public.is_member() and not public.can_audit(), 'مدقق الأمن لا يرى شيئاً قبل تفعيل التحقق بخطوتين');
select pg_temp.check((select count(*) = 0 from projects), 'المشاريع مخفية عن مدقق الأمن قبل التحقق');
select pg_temp.check((select count(*) = 1 from profiles), 'يرى ملفه فقط قبل التحقق (لتفعيله)');
select pg_temp.expect_error($$select public.security_overview()$$, 'مركز الأمان قبل التحقق');
reset role;
insert into auth.mfa_factors (user_id, status) select id, 'verified' from auth.users where email = 'auditor@test.ly';
set role authenticated;
select pg_temp.as_user('auditor@test.ly', 'aal1');
select pg_temp.check(not public.can_audit(), 'بعد تفعيل التحقق تُرفض الجلسة دون الرمز');

-- ---------------------------------------------------------------- اطلاع كامل للقراءة فقط
select pg_temp.as_user('auditor@test.ly', 'aal2');
select pg_temp.check(public.can_audit() and public.is_auditor() and not public.is_director(), 'مدقق الأمن بعد الرمز');
select pg_temp.check((select count(*) > 0 from projects), 'يطّلع على المشاريع');
select pg_temp.check((select count(*) from profiles) = :n_users, 'يرى كل الحسابات بما فيها المعلّقة والموقوفة');
select pg_temp.check((select count(*) > 0 from audit_log where project_id is null), 'يرى سجل التدقيق كاملاً (بما فيه عمليات المستخدمين والأمان)');
select pg_temp.check((select (o ->> 'viewer') = 'auditor' and (o ->> 'director_mfa')::boolean and (o ->> 'auditors')::int = 1
                        from public.security_overview() o), 'يفتح مركز الأمان');
select pg_temp.check((select count(*) > 0 from public.security_users()), 'يرى المستخدمين وحالة التحقق');
select pg_temp.check((select count(*) >= 0 from public.list_sessions()), 'يرى الجلسات');
select pg_temp.check((select count(*) >= 1 from public.login_history(50)), 'يرى سجل الدخول');
select pg_temp.check((select d -> 'profile' ->> 'email' = 'staff.new@test.ly' and d ? 'mfa' and d ? 'sessions' and d ? 'activity'
                        from public.user_details((select id from profiles where email = 'staff.new@test.ly')) d),
                     'يفتح البيانات الكاملة لمستخدم');
select pg_temp.expect_error($$select public.set_setting('security.freeze', 'true')$$, 'مدقق الأمن يغيّر الإعدادات');
select pg_temp.expect_error($$select public.set_user_access((select id from profiles where email = 'gone@test.ly'), 'contracts', null, true)$$, 'مدقق الأمن يغيّر الصلاحيات');
select pg_temp.expect_error($$select public.revoke_user_sessions((select id from profiles where email = 'gone@test.ly'))$$, 'مدقق الأمن يُخرج مستخدماً');
select pg_temp.expect_error($$select public.reset_user_mfa((select id from profiles where email = 'gone@test.ly'))$$, 'مدقق الأمن يلغي التحقق');
select pg_temp.expect_error($$select public.delete_user((select id from profiles where email = 'gone@test.ly'), 'gone@test.ly')$$, 'مدقق الأمن يحذف مستخدماً');
select pg_temp.expect_error($$select public.set_form_status((select id from projects where assign_no = '005'), 'f03', 'done')$$, 'مدقق الأمن يحدّث نموذجاً');
select pg_temp.expect_error($$insert into projects (name, owner, company, department) values ('x', 'y', 'z', 'supervision')$$, 'مدقق الأمن يضيف مشروعاً');
select pg_temp.expect_no_change($$update projects set notes = 'x' where assign_no = '005'$$, 'مدقق الأمن يعدّل مشروعاً');
select pg_temp.expect_error($$select public.admin_set_email((select id from profiles where email = 'gone@test.ly'), 'x@test.ly')$$, 'مدقق الأمن يغيّر بريد مستخدم');

-- الموظف العادي لا يرى البيانات الكاملة
select pg_temp.as_user('staff.new@test.ly');
select pg_temp.expect_error($$select public.user_details((select id from profiles where email = 'gone@test.ly'))$$, 'الموظف يفتح البيانات الكاملة');
select pg_temp.check((select count(*) = 0 from profiles where not active), 'الموظف لا يرى الحسابات غير المفعّلة');

-- ---------------------------------------------------------------- حذف مستخدم
-- الموظف الذي سيُحذف: ينشئ مشروعاً ويحدّث نموذجاً ويرفع طلب اعتماد
select pg_temp.as_user('gone@test.ly');
insert into projects (assign_no, name, owner, company, department) values ('900', 'مشروع موظف محذوف', 'المالك', 'الشركة', 'supervision');
select pg_temp.check(public.set_form_status((select id from projects where assign_no = '900'), 'f03', 'wip') = 'applied', 'الموظف يحدّث نموذجاً');
select pg_temp.check(public.set_form_status((select id from projects where assign_no = '900'), 'f13', 'done') = 'pending', 'الموظف يرفع طلب اعتماد');

select pg_temp.as_user('director.new@test.ly', 'aal2');
select pg_temp.check((select (d -> 'activity' ->> 'projects_created')::int = 1 and (d -> 'activity' ->> 'forms_updated')::int >= 1
                             and (d -> 'activity' -> 'requests' ->> 'pending')::int = 1 and jsonb_array_length(d -> 'history') >= 1
                        from public.user_details((select id from profiles where email = 'gone@test.ly')) d),
                     'البيانات الكاملة تعرض نشاط المستخدم وتاريخ حسابه');
select pg_temp.expect_error($$select public.delete_user(auth.uid(), 'director.new@test.ly')$$, 'المدير يحذف حسابه');
select pg_temp.expect_error($$select public.delete_user((select id from profiles where email = 'gone@test.ly'), 'wrong@test.ly')$$, 'الحذف ببريد تأكيد خاطئ');
select public.delete_user((select id from profiles where email = 'gone@test.ly'), ' GONE@test.ly ');
select pg_temp.check(not exists (select 1 from profiles where email = 'gone@test.ly'), 'حُذف ملف المستخدم');
reset role;
select pg_temp.check(not exists (select 1 from auth.users where email = 'gone@test.ly'), 'حُذف حساب الدخول');
set role authenticated;
select pg_temp.as_user('director.new@test.ly', 'aal2');
select pg_temp.check((select created_by is null and updated_by is null from projects where assign_no = '900'), 'المشروع باقٍ دون إشارة للمحذوف');
select pg_temp.check((select state::text = 'withdrawn' and requested_by is null from change_requests
                       where project_id = (select id from projects where assign_no = '900') and form_key = 'f13'), 'طلبه المعلّق سُحب');
select pg_temp.check(exists (select 1 from audit_log where action = 'user.delete' and detail ->> 'email' = 'gone@test.ly'
                                and (detail ->> 'withdrawn_requests')::int = 1), 'الحذف مسجّل في سجل التدقيق');
select pg_temp.check(exists (select 1 from audit_log where actor_name = 'موظف سيُحذف' and action like 'form.%'), 'اسمه باقٍ في سطوره القديمة بالسجل');

\echo 'USERS ADMIN TESTS PASSED'
