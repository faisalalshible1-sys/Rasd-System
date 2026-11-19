-- اختبارات الترحيل 25: مركز الأمن السيبراني الموسّع (اللوحة، والفحص، والأنماط، والمصفوفة، والحوادث، وصلاحيات الطوارئ).
-- يُشغَّل بعد تطبيق 20261119000025_security_center.sql مرتين، وبعد اختبارات الترحيلين 23 و24.
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
create or replace function pg_temp.uid(p_email text) returns uuid language sql security definer as $$
  select id from public.profiles where email = p_email
$$;
grant execute on all functions in schema pg_temp to authenticated, anon;

update app_settings set value = 'false' where key in ('security.freeze', 'security.require_mfa_all');
create temp table ids (k text primary key, v uuid);
grant all on ids to authenticated;

-- بيانات للأنماط: حذف كثير في ساعة لمستخدم
insert into audit_log (actor, actor_name, action, project_label, detail, at)
select pg_temp.uid('k.staff@test.ly'), 'موظف', 'unit.delete', 'اختبار', '{}'::jsonb, now() - interval '10 minutes'
  from generate_series(1, 12);
insert into audit_log (actor, actor_name, action, project_label, detail, at)
select pg_temp.uid('k.contracts@test.ly'), 'عقود', 'export.file', 'الطباعة والتصدير', '{"rows": 100, "format": "xlsx"}'::jsonb, now() - interval '2 hours'
  from generate_series(1, 26);

-- ---------------------------------------------------------------- الوصول
set role authenticated;
select pg_temp.as_user('k.staff@test.ly');
select pg_temp.expect_error($$select public.sec_dashboard(30)$$, 'اللوحة لغير المسؤول مرفوضة');
select pg_temp.expect_error($$select public.sec_posture()$$, 'والفحص');
select pg_temp.expect_error($$select public.sec_access_matrix()$$, 'والمصفوفة');
select pg_temp.expect_error($$select public.sec_save_incident(null, '{"title": "اختبار"}')$$, 'والحوادث');
select pg_temp.expect_error($$select public.sec_freeze(true, 'اختبار')$$, 'والتجميد');
select pg_temp.check((select count(*) = 0 from security_incidents), 'ولا يقرأ سجل الحوادث');

-- ---------------------------------------------------------------- مسؤول الأمن
select pg_temp.as_user('auditor@test.ly', 'aal2');
select pg_temp.check((public.sec_dashboard(30) -> 'users' ->> 'total')::int >= 15
                     and (public.sec_dashboard(30) -> 'audit' ->> 'events')::int > 0
                     and jsonb_array_length(public.sec_dashboard(30) -> 'daily') >= 1
                     and jsonb_array_length(public.sec_dashboard(30) -> 'heatmap') >= 1
                     and (public.sec_dashboard(30) -> 'chat' ->> 'messages')::int >= 1
                     and (public.sec_dashboard(30) ->> 'viewer') = 'auditor',
  'اللوحة الشاملة: المستخدمون والتدقيق والسلسلة والخريطة والمراسلات');
select pg_temp.check((public.sec_dashboard(7) -> 'audit' ->> 'exports')::int >= 26, 'عدد الملفات المستخرجة');
select pg_temp.check((select count(*) >= 15 from public.sec_posture()), 'خمسة عشر فحصاً على الأقل');
select pg_temp.check((select (x ->> 'ok')::boolean from public.sec_posture() x where x ->> 'key' = 'rls'), 'كل الجداول محمية بمستوى الصفوف');
select pg_temp.check((select (x ->> 'ok')::boolean from public.sec_posture() x where x ->> 'key' = 'search_path'),
  'كل دوال المالك بمسار بحث ثابت');
select pg_temp.check((select (x ->> 'ok')::boolean from public.sec_posture() x where x ->> 'key' = 'anon_write'), 'لا كتابة لغير المسجّلين');
select pg_temp.check((select (x ->> 'ok')::boolean from public.sec_posture() x where x ->> 'key' = 'buckets'), 'الحاويات خاصة');
select pg_temp.check((select (x ->> 'ok')::boolean from public.sec_posture() x where x ->> 'key' = 'one_director'), 'مدير واحد');
select pg_temp.check(exists (select 1 from public.sec_anomalies(7) x where x ->> 'kind' = 'mass_delete' and x ->> 'user_id' = pg_temp.uid('k.staff@test.ly')::text),
  'كشف الحذف الكثير في ساعة');
select pg_temp.check(exists (select 1 from public.sec_anomalies(7) x where x ->> 'kind' = 'mass_export'), 'كشف التصدير الكثير في يوم');
select pg_temp.check(exists (select 1 from public.sec_anomalies(7) x where x ->> 'kind' = 'privilege'), 'تغييرات الصلاحيات تظهر');
select pg_temp.check((select (x ->> 'forms')::int >= 1 and jsonb_array_length(x -> 'grants') = 1
                        from public.sec_access_matrix() x where x ->> 'id' = pg_temp.uid('k.contracts@test.ly')::text),
  'المصفوفة: نماذج موظف العقود وصلاحيته الدقيقة');
select pg_temp.check((select (x ->> 'forms')::int = (x ->> 'forms_total')::int from public.sec_access_matrix() x
                       where x ->> 'id' = pg_temp.uid('director.new@test.ly')::text),
  'المدير يكتب في كل النماذج');
select pg_temp.check(jsonb_array_length(public.sec_data_activity(30) -> 'exports') >= 26
                     and jsonb_array_length(public.sec_data_activity(30) -> 'refs') >= 1
                     and jsonb_array_length(public.sec_data_activity(30) -> 'deletes') >= 12
                     and (public.sec_data_activity(30) -> 'export_formats' ->> 'xlsx')::int >= 26,
  'نشاط البيانات: التصدير والأرقام الإشارية والحذف');
select pg_temp.check((select count(*) = 12 from public.sec_audit_search(now() - interval '1 hour', null, pg_temp.uid('k.staff@test.ly'), 'unit.', null, 100)),
  'البحث في سجل التدقيق بالمستخدم والنوع والمدة');
select pg_temp.check((select count(*) >= 1 from public.sec_audit_search(null, null, null, null, 'تحقيق في تسريب', 50)), 'والبحث في التفاصيل');

-- الحوادث
select pg_temp.expect_error($$select public.sec_save_incident(null, '{"title": "اخ"}')$$, 'عنوان قصير');
select pg_temp.expect_error($$select public.sec_save_incident(null, '{"title": "حادثة", "severity": "extreme"}')$$, 'خطورة غير معروفة');
insert into ids select 'inc', public.sec_save_incident(null, jsonb_build_object('title', 'تصدير كثيف من حساب العقود', 'severity', 'high',
  'category', 'data', 'details', '26 ملفاً في ساعتين', 'user_id', pg_temp.uid('k.contracts@test.ly')));
select pg_temp.check((select status = 'open' and created_by = auth.uid() from security_incidents where id = (select v from ids where k = 'inc')),
  'تسجيل حادثة مفتوحة');
select pg_temp.check((select (x ->> 'ok')::boolean = false from public.sec_posture() x where x ->> 'key' = 'incidents'), 'الفحص يرى الحادثة العالية');
select public.sec_save_incident((select v from ids where k = 'inc'), '{"status": "closed", "actions": "تواصلنا مع الموظف؛ التصدير لتقرير شهري"}');
select pg_temp.check((select closed_at is not null from security_incidents where id = (select v from ids where k = 'inc'))
                     and (select count(*) = 2 from audit_log where action = 'security.incident_save'),
  'إغلاق الحادثة يسجّل وقت الإغلاق');
select pg_temp.expect_error($$select public.sec_delete_incident((select v from ids where k = 'inc'))$$, 'المسؤول لا يحذف الحوادث');

-- صلاحيات الطوارئ
select pg_temp.expect_error($$select public.sec_suspend_grants(pg_temp.uid('k.contracts@test.ly'), '')$$, 'التعليق بلا سبب');
select pg_temp.check(public.sec_suspend_grants(pg_temp.uid('k.contracts@test.ly'), 'حادثة تصدير') = 1, 'تعليق صلاحية واحدة');
select pg_temp.check(not exists (select 1 from user_grants where user_id = pg_temp.uid('k.contracts@test.ly'))
                     and exists (select 1 from audit_log where action = 'security.grants_suspend'),
  'المسؤول يعلّق الصلاحيات الدقيقة ويُسجَّل');
select public.sec_freeze(true, 'اشتباه باختراق حساب');
select pg_temp.check((select value = 'true'::jsonb from app_settings where key = 'security.freeze')
                     and exists (select 1 from audit_log where action = 'security.emergency_freeze'),
  'المسؤول يجمّد المنظومة فوراً');
select pg_temp.as_user('k.staff@test.ly');
select pg_temp.expect_error($$select public.save_unit_record(null, jsonb_build_object('kind','plan','title','خطة'))$$, 'التجميد يوقف الكتابة');
select pg_temp.as_user('auditor@test.ly', 'aal2');
select pg_temp.expect_error($$select public.sec_freeze(false, 'انتهى')$$, 'رفع التجميد ليس للمسؤول');
select pg_temp.as_user('director.new@test.ly', 'aal2');
select public.sec_freeze(false, 'تم التحقق؛ لا اختراق');
select pg_temp.check((select value = 'false'::jsonb from app_settings where key = 'security.freeze'), 'المدير يرفع التجميد');
select public.sec_delete_incident((select v from ids where k = 'inc'));
select pg_temp.check(not exists (select 1 from security_incidents) and exists (select 1 from audit_log where action = 'security.incident_delete'),
  'المدير يحذف الحادثة ويُسجَّل');
select pg_temp.check((public.sec_dashboard(30) ->> 'viewer') = 'director', 'المدير يرى اللوحة نفسها');

reset role;
select 'ALL 25 TESTS PASSED';
