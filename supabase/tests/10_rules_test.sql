-- اختبارات قواعد الصلاحيات ومسار الاعتماد. تُشغَّل على قاعدة اختبار محلية بعد ملف المحاكاة والمخطط والاستيراد.
-- أي إخفاق يوقف التنفيذ برسالة FAIL.
\set ON_ERROR_STOP 1
\set QUIET 1
\pset tuples_only on
\pset format unaligned

-- أدوات الاختبار
create or replace function pg_temp.as_user(p_email text) returns void language plpgsql security definer as $$
begin
  perform set_config('request.jwt.claim.sub', coalesce((select id::text from auth.users where email = p_email), ''), false);
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

-- المستخدمون (يسجلون أنفسهم من التطبيق)
insert into auth.users (email, raw_user_meta_data) values
  ('director@test.ly',  '{"full_name":"م. فيصل الشبلي"}'),
  ('staff@test.ly',     '{"full_name":"موظف مكتب المدير"}'),
  ('headsup@test.ly',   '{"full_name":"رئيس قسم الإشراف"}'),
  ('headtech@test.ly',  '{"full_name":"رئيس قسم الشؤون الفنية"}'),
  ('headrest@test.ly',  '{"full_name":"رئيس قسم الترميم"}'),
  ('contracts@test.ly', '{"full_name":"مكتب العقود"}'),
  ('qa@test.ly',        '{"full_name":"مكتب التخطيط وضمان الجودة"}'),
  ('pending@test.ly',   '{"full_name":"حساب جديد"}');

select pg_temp.check((select count(*) = 8 from public.profiles where not active and role is null), 'كل حساب جديد يُنشأ غير مفعّل وبلا دور');

-- الإعداد: منح دور المدير (من محرر SQL)
select public.claim_director('director@test.ly');
select pg_temp.expect_error($$select public.claim_director('staff@test.ly')$$, 'منح دور المدير مرة ثانية');

-- مشروع ترميم للاختبار
update public.projects set department = 'restoration' where assign_no = '017';

-- المدير يفعّل الحسابات
set role authenticated;
select pg_temp.as_user('director@test.ly');
select public.set_user_access((select id from profiles where email='staff@test.ly'),     'office_staff', null, true);
select public.set_user_access((select id from profiles where email='headsup@test.ly'),   'dept_head', 'supervision', true);
select public.set_user_access((select id from profiles where email='headtech@test.ly'),  'dept_head', 'technical', true);
select public.set_user_access((select id from profiles where email='headrest@test.ly'),  'dept_head', 'restoration', true);
select public.set_user_access((select id from profiles where email='contracts@test.ly'), 'contracts', null, true);
select public.set_user_access((select id from profiles where email='qa@test.ly'),        'planning_qa', null, true);
select pg_temp.expect_error($$select public.set_user_access((select id from profiles where email='pending@test.ly'), 'director', null, true)$$, 'منح دور المدير من التطبيق');
select pg_temp.expect_error($$select public.set_user_access(auth.uid(), 'office_staff', null, false)$$, 'المدير يعدّل حسابه بنفسه');
select pg_temp.expect_error($$select public.set_user_access((select id from profiles where email='pending@test.ly'), 'dept_head', null, true)$$, 'رئيس قسم بلا قسم');
select pg_temp.check((select count(*) = 7 from public.profiles where active), 'سبعة حسابات مفعّلة');

-- الحساب غير المفعّل لا يرى شيئاً
select pg_temp.as_user('pending@test.ly');
select pg_temp.check((select count(*) = 0 from public.projects), 'غير المفعّل لا يرى المشاريع');
select pg_temp.check((select count(*) = 1 from public.profiles), 'غير المفعّل يرى ملفه فقط');
select pg_temp.expect_error($$select public.set_form_status((select id from projects where assign_no='001'), 'f01', 'done')$$, 'غير المفعّل يحدّث نموذجاً');

-- الزائر غير المسجل
reset role; set role anon;
select pg_temp.expect_error($$select count(*) from public.projects$$, 'الزائر يقرأ المشاريع');
reset role; set role authenticated;

-- موظف مكتب المدير: نموذج غير حساس يُطبَّق مباشرة
select pg_temp.as_user('staff@test.ly');
select pg_temp.check(public.set_form_status((select id from projects where assign_no='001'), 'f01', 'done') = 'applied', 'موظف المكتب يحدّث «أمر تعاقد» مباشرة');
select pg_temp.check((select status = 'done' from project_forms where form_key='f01' and project_id=(select id from projects where assign_no='001')), 'الحالة محفوظة');
select pg_temp.check(public.set_form_status((select id from projects where assign_no='001'), 'f01', 'done') = 'unchanged', 'التحديث بالقيمة نفسها لا يُسجَّل');

-- نموذج حساس يرفع طلباً ولا يغيّر الحالة
select pg_temp.check(public.set_form_status((select id from projects where assign_no='001'), 'f13', 'done', 'الشهادة موقعة') = 'pending', 'موظف المكتب يطلب اعتماد «شهادة دفع مستخلص»');
select pg_temp.check(not exists (select 1 from project_forms where form_key='f13' and project_id=(select id from projects where assign_no='001') and status='done'), 'الحالة لم تتغير قبل الاعتماد');
select pg_temp.expect_error($$select public.set_form_status((select id from projects where assign_no='001'), 'f13', 'wip')$$, 'طلب ثانٍ للنموذج نفسه');

-- الكتابة المباشرة في الجداول ممنوعة
select pg_temp.expect_error($$insert into public.project_forms (project_id, form_key, status) values ((select id from projects where assign_no='002'), 'f18', 'done')$$, 'كتابة مباشرة في حالات النماذج');
select pg_temp.expect_no_change($q$update public.project_forms set status='done' where form_key='f04'$q$, 'تحديث مباشر لحالات النماذج لا يغيّر شيئاً');
select pg_temp.expect_error($$update public.profiles set role='director' where id=auth.uid()$$, 'الموظف يرفع دوره');
select pg_temp.expect_error($$insert into public.audit_log (action) values ('x')$$, 'كتابة في سجل التدقيق');
select pg_temp.expect_error($$select public.apply_form_status((select id from projects where assign_no='002'), 'f18', 'done', auth.uid(), null)$$, 'استدعاء الدالة الداخلية');
select pg_temp.expect_error($$select public.decide_request((select id from change_requests limit 1), true)$$, 'غير المدير يعتمد طلباً');
select pg_temp.expect_no_change($q$delete from public.projects where assign_no='016'$q$, 'الموظف لا يحذف مشروعاً');
select pg_temp.check(public.set_form_status((select id from projects where assign_no='017'), 'f03', 'wip') = 'applied', 'موظف المكتب يحدّث أي نموذج غير حساس');

-- رؤساء الأقسام حسب الاختصاص
select pg_temp.as_user('headsup@test.ly');
select pg_temp.check(public.set_form_status((select id from projects where assign_no='002'), 'f06', 'done') = 'applied', 'رئيس الإشراف يحدّث «تكليف مهندس متابعة» في مشروع قسمه');
select pg_temp.expect_error($$select public.set_form_status((select id from projects where assign_no='017'), 'f06', 'done')$$, 'رئيس الإشراف في مشروع ترميم');
select pg_temp.expect_error($$select public.set_form_status((select id from projects where assign_no='002'), 'f01', 'done')$$, 'رئيس الإشراف يحدّث «أمر تعاقد»');
select public.set_engineer((select id from projects where assign_no='002'), 'f06', 'م. اختبار المتابعة');
select pg_temp.check((select eng_fol = 'م. اختبار المتابعة' from projects where assign_no='002'), 'رئيس الإشراف يسند مهندس المتابعة');
select pg_temp.expect_error($$select public.set_engineer((select id from projects where assign_no='002'), 'f05', 'x')$$, 'رئيس الإشراف يسند مهندس الحصر');
select pg_temp.expect_no_change($q$update public.projects set name='x' where assign_no='002'$q$, 'رئيس القسم لا يعدّل بيانات المشروع');
select pg_temp.check(public.set_form_status((select id from projects where assign_no='002'), 'f10', 'done') = 'pending', 'رئيس الإشراف يطلب اعتماد «ورقة قياس أ»');

select pg_temp.as_user('headrest@test.ly');
select pg_temp.check(public.set_form_status((select id from projects where assign_no='017'), 'f06', 'wip') = 'applied', 'رئيس الترميم يحدّث مشروع الترميم');
select pg_temp.expect_error($$select public.set_form_status((select id from projects where assign_no='002'), 'f06', 'wip')$$, 'رئيس الترميم في مشروع إشراف');

select pg_temp.as_user('headtech@test.ly');
select pg_temp.check(public.set_form_status((select id from projects where assign_no='003'), 'f05', 'done') = 'applied', 'رئيس الشؤون الفنية يحدّث «تكليف مهندس حصر»');
select pg_temp.expect_error($$select public.set_form_status((select id from projects where assign_no='003'), 'f04', 'done')$$, 'رئيس الشؤون الفنية يحدّث «تكليف مهندس مشرف»');

-- مكتب العقود
select pg_temp.as_user('contracts@test.ly');
select pg_temp.check(public.set_form_status((select id from projects where assign_no='003'), 'f02', 'wip') = 'applied', 'مكتب العقود يحدّث «أمر عمل»');
select pg_temp.check(public.set_form_status((select id from projects where assign_no='003'), 'f18', 'done') = 'pending', 'مكتب العقود يطلب اعتماد «إقفال عقد»');
select pg_temp.expect_error($$select public.set_form_status((select id from projects where assign_no='003'), 'f08', 'done')$$, 'مكتب العقود يحدّث «محضر تسليم موقع»');
select public.withdraw_request((select id from change_requests where form_key='f18' and state='pending'));
select pg_temp.check((select state = 'withdrawn' from change_requests where form_key='f18'), 'مقدّم الطلب يسحب طلبه');
select pg_temp.check(public.set_form_status((select id from projects where assign_no='003'), 'f18', 'done') = 'pending', 'طلب جديد بعد السحب');

-- مكتب التخطيط وضمان الجودة
select pg_temp.as_user('qa@test.ly');
select pg_temp.expect_error($$select public.set_form_status((select id from projects where assign_no='003'), 'f02', 'done')$$, 'مكتب الجودة يحدّث نموذجاً');
insert into public.quality_notes (project_id, body) values ((select id from projects where assign_no='003'), 'تأخر أمر العمل عن الجدول');
select pg_temp.check((select count(*) = 1 from quality_notes), 'مكتب الجودة يسجّل ملاحظة');
select pg_temp.check((select count(*) = 17 from v_project_progress), 'مكتب الجودة يرى نسب الإنجاز');
select pg_temp.as_user('staff@test.ly');
select pg_temp.expect_error($$insert into public.quality_notes (project_id, body) values ((select id from projects where assign_no='003'), 'x')$$, 'موظف المكتب يسجّل ملاحظة جودة');
select pg_temp.expect_error($$select public.withdraw_request((select id from change_requests where form_key='f18' and state='pending'))$$, 'سحب طلب شخص آخر');

-- المدير: البتّ في الطلبات
select pg_temp.as_user('director@test.ly');
select pg_temp.check((select count(*) = 4 from notifications where kind='request'), 'وصل المدير إشعار بكل طلب');
select pg_temp.expect_error($$select public.decide_request((select id from change_requests where form_key='f18' and state='pending'), false, '')$$, 'رفض بلا سبب');
select public.decide_request((select id from change_requests where form_key='f18' and state='pending'), false, 'لم يُستكمل الاستلام النهائي');
select pg_temp.check((select state = 'rejected' from change_requests where form_key='f18' and decision_note <> ''), 'رُفض الطلب مع السبب');
select pg_temp.check(not exists (select 1 from project_forms where form_key='f18' and status='done'), 'الحالة لم تتغير بعد الرفض');
select public.decide_request((select id from change_requests where form_key='f13' and state='pending'), true);
select pg_temp.check((select status = 'done' and approved_by = auth.uid() and updated_by = (select id from profiles where email='staff@test.ly')
                      from project_forms where form_key='f13' and project_id=(select id from projects where assign_no='001')), 'الاعتماد يطبّق الحالة باسم مقدّم الطلب مع اعتماد المدير');
select pg_temp.expect_error($$select public.decide_request((select id from change_requests where form_key='f13'), true)$$, 'البتّ في طلب مرة ثانية');
-- المدير يعدّل نموذجاً عليه طلب معلّق: يُغلق الطلب
select pg_temp.check(public.set_form_status((select id from projects where assign_no='002'), 'f10', 'wip') = 'applied', 'المدير يحدّث نموذجاً حساساً مباشرة');
select pg_temp.check((select state = 'rejected' from change_requests where form_key='f10'), 'يُغلق الطلب المعلّق عند تعديل المدير المباشر');
-- صلاحيات النماذج
update public.form_defs set sensitive = false where key = 'f10';
select pg_temp.check((select not sensitive from form_defs where key='f10'), 'المدير يغيّر حساسية نموذج');
select pg_temp.expect_error($$update public.form_defs set name = 'x' where key = 'f10'$$, 'تغيير اسم النموذج');
-- الحذف وسجل التدقيق
delete from public.projects where assign_no = '016';
select pg_temp.check((select count(*) = 16 from projects), 'المدير يحذف مشروعاً');
select pg_temp.check(exists (select 1 from audit_log where action = 'project.delete' and project_label like '016%'), 'أثر الحذف باقٍ في السجل');
select pg_temp.expect_no_change($q$update public.audit_log set action = 'x'$q$, 'المدير لا يعدّل سجل التدقيق');
select pg_temp.expect_no_change($q$delete from public.audit_log$q$, 'المدير لا يحذف سجل التدقيق');
select pg_temp.check((select count(*) > 20 from audit_log), 'المدير يرى السجل الكامل');

-- الموظفون يرون سجل المشاريع فقط
select pg_temp.as_user('staff@test.ly');
select pg_temp.check((select count(*) = 0 from audit_log where project_id is null), 'الموظف لا يرى سجل إدارة المستخدمين');
select pg_temp.check((select count(*) >= 1 from notifications where kind = 'decision'), 'وصل الموظف إشعار القرار');
select pg_temp.check((select count(*) = 0 from notifications where kind = 'request'), 'الموظف لا يرى إشعارات المدير');

-- إيقاف مستخدم
select pg_temp.as_user('director@test.ly');
select public.set_user_access((select id from profiles where email='contracts@test.ly'), 'contracts', null, false);
select pg_temp.as_user('contracts@test.ly');
select pg_temp.check((select count(*) = 0 from projects), 'المستخدم الموقوف يفقد الوصول فوراً');

-- تغيير بريد الدخول
reset role;
insert into auth.identities (user_id, provider, identity_data)
select id, 'email', jsonb_build_object('email', email, 'sub', id::text) from auth.users where email = 'staff@test.ly';
set role authenticated;
select pg_temp.as_user('staff@test.ly');
select pg_temp.expect_error($$select public.admin_set_email((select id from profiles where email='headsup@test.ly'), 'x@test.ly')$$, 'غير المدير يغيّر بريد مستخدم');
select pg_temp.as_user('director@test.ly');
select pg_temp.expect_error($$select public.admin_set_email((select id from profiles where email='staff@test.ly'), 'بريد خطأ')$$, 'بريد بصيغة خاطئة');
select pg_temp.expect_error($$select public.admin_set_email((select id from profiles where email='staff@test.ly'), 'headsup@test.ly')$$, 'بريد مستخدم لحساب آخر');
select public.admin_set_email((select id from profiles where email='staff@test.ly'), ' Staff.New@Test.ly ');
reset role;
select pg_temp.check((select count(*) = 1 from auth.users where email = 'staff.new@test.ly'), 'تغيّر بريد الدخول في حسابات المصادقة');
select pg_temp.check((select identity_data->>'email' = 'staff.new@test.ly' from auth.identities where provider = 'email'), 'تغيّر البريد في هوية الدخول');
select pg_temp.check((select count(*) = 1 from public.profiles where email = 'staff.new@test.ly' and role = 'office_staff' and active), 'الملف بالبريد الجديد بنفس الدور');
select pg_temp.check(exists (select 1 from audit_log where action = 'user.email'), 'تغيير البريد مسجّل في السجل');
set role authenticated;
select pg_temp.as_user('director@test.ly');
select public.admin_set_email(auth.uid(), 'director.new@test.ly');
reset role;
select pg_temp.check((select role = 'director' from public.profiles where email = 'director.new@test.ly'), 'المدير يغيّر بريده ويبقى مديراً');

reset role;
select pg_temp.check((select count(*) = 1 from profiles where role = 'director'), 'مدير واحد فقط في المنظومة');
\echo 'ALL TESTS PASSED'
