-- اختبارات الإصدار الثاني: الإعدادات الحية، المراحل والنماذج، الحقول الإضافية، الأفكار، مركز الأمان.
-- تُشغَّل بعد 10_rules_test.sql على القاعدة نفسها (المدير: director.new@test.ly، الموظف: staff.new@test.ly).
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

set role authenticated;

-- ---------------------------------------------------------------- الإعدادات الحية
select pg_temp.as_user('director.new@test.ly');
select pg_temp.check((select count(*) >= 15 from app_settings), 'الإعدادات الافتراضية موجودة ويقرؤها المدير');
select public.set_setting('brand.app_title', '"منظومة الدورة المستندية"');
select pg_temp.check((select value = '"منظومة الدورة المستندية"'::jsonb from app_settings where key = 'brand.app_title'), 'المدير يغيّر عنوان التطبيق');
select pg_temp.check(exists (select 1 from audit_log where action = 'setting.update' and detail ->> 'key' = 'brand.app_title'), 'تغيير الإعداد مسجّل');
select pg_temp.expect_error($$select public.set_setting('brand.primary_color', '"red"')$$, 'لون بصيغة خاطئة');
select pg_temp.expect_error($$select public.set_setting('unknown.key', '1')$$, 'إعداد غير معروف');
select pg_temp.expect_error($$select public.set_setting('finance.guarantee_initial_rate', '2')$$, 'نسبة ضمان غير منطقية');
select pg_temp.expect_error($$select public.set_setting('security.require_mfa_director', 'true')$$, 'فرض التحقق بخطوتين قبل تفعيله لحساب المدير');
select public.set_setting('finance.guarantee_initial_rate', '0.1');
select pg_temp.check((select guarantee_initial = 125000 from projects where assign_no = '003'), 'تغيير نسبة الضمان يعيد حسابه في المشاريع');
select public.set_setting('finance.guarantee_initial_rate', '0.05');
select pg_temp.check((select guarantee_initial = 62500 and guarantee_final = 25000 from projects where assign_no = '003'), 'الضمانان بالنسبتين الافتراضيتين');
select public.set_setting('ui.announcement', '{"text": "صيانة مساء الخميس", "level": "warning"}');
select pg_temp.as_user('staff.new@test.ly');
select pg_temp.check((select value ->> 'text' = 'صيانة مساء الخميس' from app_settings where key = 'ui.announcement'), 'الموظف يقرأ الإعلان');
select pg_temp.expect_error($$select public.set_setting('brand.org_name', '"x y z"')$$, 'الموظف يغيّر الإعدادات');
select pg_temp.expect_error($$update public.app_settings set value = '1' where key = 'security.freeze'$$, 'تعديل جدول الإعدادات مباشرة');
reset role; set role anon;
select pg_temp.check(public.public_settings() ? 'brand.app_title' and not (public.public_settings() ? 'ui.announcement'), 'الزائر يرى الهوية فقط');
select pg_temp.expect_error($$select count(*) from public.app_settings$$, 'الزائر يقرأ جدول الإعدادات');
reset role; set role authenticated;

-- ---------------------------------------------------------------- المراحل والنماذج والأقسام
select pg_temp.as_user('director.new@test.ly');
select pg_temp.check(public.save_stage(null, 'فترة الضمان') = 5, 'المدير يضيف مرحلة');
select pg_temp.check(public.save_form_def(null, 'محضر انتهاء فترة الضمان', 5::smallint, false, '{office_staff}', true) = 'f20', 'المدير يضيف نموذجاً');
select pg_temp.check((select sort = 20 and stage = 5 from form_defs where key = 'f20'), 'النموذج الجديد آخر الترتيب في مرحلته');
select public.save_form_def('f20', 'محضر انتهاء الضمان', 0::smallint, false, '{office_staff}', true);
select pg_temp.check((select sort = 5 and name = 'محضر انتهاء الضمان' from form_defs where key = 'f20'), 'نقل النموذج إلى مرحلة أخرى يضعه آخرها');
select pg_temp.check((select sort = 6 from form_defs where key = 'f03') is false and (select sort = 4 from form_defs where key = 'f03'), 'بقية الترتيب متصل');
select public.reorder_forms(array['f20']);
select pg_temp.check((select sort = 1 from form_defs where key = 'f20') and (select sort = 2 from form_defs where key = 'f01'), 'إعادة الترتيب داخل المرحلة');
select pg_temp.check((select count(*) = 20 and max(sort) = 20 from form_defs), 'الترتيب متصل بعد كل تعديل');
select public.save_form_def('f20', 'محضر انتهاء الضمان', 0::smallint, false, '{office_staff}', false);
select pg_temp.check((select bool_and(required + na = 19) from v_project_progress), 'النموذج الموقوف لا يدخل في نسبة الإنجاز');
select public.delete_form_def('f20');
select pg_temp.expect_error($$select public.delete_form_def('f01')$$, 'حذف نموذج له حالات مسجّلة');
select public.delete_stage(5::smallint);
select pg_temp.check((select count(*) = 5 from stages), 'حذف المرحلة الأخيرة الفارغة');
select pg_temp.expect_error($$update public.form_defs set name = 'x' where key = 'f02'$$, 'تغيير اسم النموذج مباشرة');
select public.save_stage(0::smallint, 'التعاقد والترسية');
select pg_temp.check((select current_stage = 'التعاقد والترسية' from v_project_progress where project_id = (select id from projects where assign_no = '004')), 'اسم المرحلة الجديد يظهر في الإنجاز');
select public.save_stage(0::smallint, 'التعاقد');
select pg_temp.check(public.save_department(null, 'التخطيط العمراني', true) like 'dept%', 'المدير يضيف قسماً');
select public.save_form_def('f03', 'نموذج عقد أشغال عامة', 0::smallint, false, '{office_staff,contracts}', false);
select pg_temp.as_user('staff.new@test.ly');
select pg_temp.expect_error($$select public.set_form_status((select id from projects where assign_no='005'), 'f03', 'done')$$, 'تحديث نموذج موقوف');
select pg_temp.expect_error($$select public.save_stage(null, 'مرحلة')$$, 'الموظف يضيف مرحلة');
select pg_temp.expect_error($$select public.save_form_def(null, 'نموذج', 0::smallint, false, '{}', true)$$, 'الموظف يضيف نموذجاً');
select pg_temp.as_user('director.new@test.ly');
select public.save_form_def('f03', 'نموذج عقد أشغال عامة', 0::smallint, false, '{office_staff,contracts}', true);

-- ---------------------------------------------------------------- الحقول الإضافية
select pg_temp.check(public.save_custom_field(null, 'رقم العقد', 'text', '{}', 'بيانات العقد', '{office_staff,contracts}', true) = 'c1', 'حقل نصي');
select pg_temp.check(public.save_custom_field(null, 'تاريخ التوقيع', 'date', '{}', 'بيانات العقد', '{office_staff}', true) = 'c2', 'حقل تاريخ');
select pg_temp.check(public.save_custom_field(null, 'نوع العقد', 'select', '{مقاولة,توريد}', 'بيانات العقد', '{office_staff}', true) = 'c3', 'حقل قائمة');
select pg_temp.expect_error($$select public.save_custom_field(null, 'قائمة', 'select', '{أ}', '', '{}', true)$$, 'قائمة بخيار واحد');
select pg_temp.as_user('staff.new@test.ly');
select public.set_project_field((select id from projects where assign_no='003'), 'c1', '"ع-2026-14"');
select public.set_project_field((select id from projects where assign_no='003'), 'c2', '"2026-10-01"');
select public.set_project_field((select id from projects where assign_no='003'), 'c3', '"مقاولة"');
select pg_temp.check((select extra ->> 'c1' = 'ع-2026-14' and extra ->> 'c3' = 'مقاولة' from projects where assign_no='003'), 'الموظف يحفظ الحقول الإضافية');
select pg_temp.expect_error($$select public.set_project_field((select id from projects where assign_no='003'), 'c2', '"أمس"')$$, 'تاريخ غير صالح');
select pg_temp.expect_error($$select public.set_project_field((select id from projects where assign_no='003'), 'c3', '"إيجار"')$$, 'قيمة خارج القائمة');
select pg_temp.expect_error($$update public.projects set extra = '{}' where assign_no = '003'$$, 'تعديل الحقول الإضافية مباشرة');
select public.set_project_field((select id from projects where assign_no='003'), 'c2', null);
select pg_temp.check((select not (extra ? 'c2') from projects where assign_no='003'), 'مسح قيمة حقل');
select pg_temp.check(exists (select 1 from audit_log where action = 'project.field' and detail ->> 'key' = 'c1'), 'تعديل الحقل مسجّل');
select pg_temp.as_user('headsup@test.ly');
select pg_temp.expect_error($$select public.set_project_field((select id from projects where assign_no='003'), 'c1', '"x"')$$, 'رئيس الإشراف يعدّل حقلاً خارج اختصاصه');

-- ---------------------------------------------------------------- الأفكار
select pg_temp.as_user('staff.new@test.ly');
select public.submit_idea('تقرير شهري تلقائي', 'يُرسل للمدير أول كل شهر', 'feature', 'high');
select pg_temp.check((select count(*) = 1 from ideas), 'الموظف يرسل فكرة');
select pg_temp.expect_error($$select public.update_idea((select id from ideas limit 1), 'done', null, null)$$, 'الموظف يغيّر حالة الفكرة');
select pg_temp.as_user('director.new@test.ly');
select pg_temp.check(exists (select 1 from notifications where kind = 'idea'), 'وصل المدير إشعار بالفكرة');
select public.update_idea((select id from ideas limit 1), 'planned', null, 'ضمن التحديث القادم');
select public.set_setting('ui.features', '{"analysis": true, "export": true, "quality_notes": true, "ideas_for_all": false}');
select pg_temp.as_user('staff.new@test.ly');
select pg_temp.check(exists (select 1 from notifications where kind = 'idea'), 'وصل صاحب الفكرة إشعار بالقرار');
select pg_temp.expect_error($$select public.submit_idea('فكرة أخرى', '', 'other', 'low')$$, 'الأفكار مقصورة على المدير بالإعداد');
select pg_temp.as_user('director.new@test.ly');
select public.set_setting('ui.features', '{"analysis": true, "export": true, "quality_notes": true, "ideas_for_all": true}');

-- ---------------------------------------------------------------- تجميد المنظومة وإغلاق التسجيل
select public.set_setting('security.freeze', 'true');
select pg_temp.as_user('staff.new@test.ly');
select pg_temp.expect_error($$select public.set_form_status((select id from projects where assign_no='005'), 'f02', 'done')$$, 'تحديث نموذج أثناء التجميد');
select pg_temp.expect_no_change($q$update public.projects set notes = 'x' where assign_no = '005'$q$, 'تعديل مشروع أثناء التجميد');
select pg_temp.check((select count(*) > 0 from projects), 'القراءة متاحة أثناء التجميد');
select pg_temp.as_user('director.new@test.ly');
select pg_temp.check(public.set_form_status((select id from projects where assign_no='005'), 'f02', 'wip') = 'applied', 'المدير يعدّل أثناء التجميد');
select public.set_setting('security.freeze', 'false');
select public.set_setting('security.signups_open', 'false');
reset role;
select pg_temp.expect_error($$insert into auth.users (email) values ('late@test.ly')$$, 'التسجيل أثناء إغلاقه');
set role authenticated;
select pg_temp.as_user('director.new@test.ly');
select public.set_setting('security.signups_open', 'true');

-- ---------------------------------------------------------------- التحقق بخطوتين
reset role;
insert into auth.mfa_factors (user_id, status) select id, 'verified' from auth.users where email = 'staff.new@test.ly';
set role authenticated;
select pg_temp.as_user('staff.new@test.ly', 'aal1');
select pg_temp.check((select count(*) = 0 from projects), 'من فعّل التحقق بخطوتين لا يرى شيئاً قبل إدخال الرمز');
select pg_temp.as_user('staff.new@test.ly', 'aal2');
select pg_temp.check((select count(*) > 0 from projects), 'بعد إدخال الرمز يعود الوصول');
select pg_temp.as_user('director.new@test.ly');
select pg_temp.check((select mfa from public.security_users() where email = 'staff.new@test.ly'), 'مركز الأمان يعرض حالة التحقق بخطوتين');
select pg_temp.check(public.reset_user_mfa((select id from profiles where email = 'staff.new@test.ly')) = 1, 'المدير يلغي التحقق لموظف فقد هاتفه');
select pg_temp.as_user('staff.new@test.ly', 'aal1');
select pg_temp.check((select count(*) > 0 from projects), 'بعد الإلغاء يدخل الموظف بكلمة المرور');
reset role;
insert into auth.mfa_factors (user_id, status) select id, 'verified' from auth.users where email = 'director.new@test.ly';
set role authenticated;
select pg_temp.as_user('director.new@test.ly', 'aal1');
select pg_temp.expect_error($$select public.set_setting('security.require_mfa_all', 'true')$$, 'المدير دون رمز التحقق يفقد صلاحياته');
select pg_temp.as_user('director.new@test.ly', 'aal2');
select public.set_setting('security.require_mfa_all', 'true');
select pg_temp.as_user('headsup@test.ly');
select pg_temp.check((select count(*) = 0 from projects), 'عند إلزام الجميع لا يرى من لم يفعّل التحقق شيئاً');
select pg_temp.as_user('director.new@test.ly', 'aal2');
select public.set_setting('security.require_mfa_all', 'false');
select pg_temp.as_user('headsup@test.ly');
select pg_temp.check((select count(*) > 0 from projects), 'إلغاء الإلزام يعيد الوصول');
select pg_temp.as_user('director.new@test.ly', 'aal2');
select pg_temp.expect_error($$select public.reset_user_mfa(auth.uid())$$, 'المدير يلغي تحققه من التطبيق');

-- ---------------------------------------------------------------- الجلسات وسجل الدخول ونظرة الأمان
reset role;
insert into auth.sessions (user_id, user_agent, ip) select id, 'Mozilla/5.0 (Android)', '10.0.0.7' from auth.users where email = 'headsup@test.ly';
insert into auth.sessions (user_id, user_agent, ip) select id, 'Windows', '10.0.0.8' from auth.users where email = 'headsup@test.ly';
insert into auth.audit_log_entries (payload) select json_build_object('action', 'login', 'actor_id', id, 'actor_username', email) from auth.users where email = 'headsup@test.ly';
set role authenticated;
select pg_temp.as_user('director.new@test.ly', 'aal2');
select pg_temp.check((select count(*) = 2 from public.list_sessions()), 'المدير يرى الجلسات المفتوحة');
select pg_temp.check(public.revoke_user_sessions((select id from profiles where email = 'headsup@test.ly')) = 2, 'إخراج مستخدم من كل أجهزته');
select pg_temp.check((select count(*) = 0 from public.list_sessions()), 'لم تبقَ جلسات');
select pg_temp.check((select count(*) = 1 from public.login_history(50)), 'سجل الدخول');
select pg_temp.check((select (o ->> 'director_mfa')::boolean and o -> 'tables_without_rls' = '[]'::jsonb from public.security_overview() o),
                     'نظرة الأمان: تحقق المدير مفعّل وكل الجداول محمية');
select pg_temp.check((select e ? 'settings' and e ? 'forms' and e ? 'custom_fields' from public.export_config() e), 'تصدير الإعدادات');
select pg_temp.check(public.import_settings('{"brand.org_name": "مكتب الشؤون الهندسية", "security.require_mfa_all": true}') = 1, 'استعادة الإعدادات تتجاهل إعدادات التحقق');
select pg_temp.as_user('staff.new@test.ly');
select pg_temp.expect_error($$select public.security_overview()$$, 'الموظف يفتح مركز الأمان');
select pg_temp.expect_error($$select public.list_sessions()$$, 'الموظف يرى الجلسات');
select pg_temp.expect_error($$select public.revoke_user_sessions((select id from profiles where email = 'headsup@test.ly'))$$, 'الموظف يُخرج مستخدماً');

reset role;
select pg_temp.check((select count(*) = 0 from pg_class c join pg_namespace n on n.oid = c.relnamespace
                      where n.nspname = 'public' and c.relkind = 'r' and not c.relrowsecurity), 'كل جداول المنظومة محمية بسياسات الوصول');
\echo 'PLATFORM TESTS PASSED'
