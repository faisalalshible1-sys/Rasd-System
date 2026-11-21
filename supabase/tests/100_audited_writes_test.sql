-- اختبارات الترحيل 26: الكتابة عبر الدوال المدققة فقط (العقود، وملاحظات الجودة، وصلاحيات النماذج، والاسم، والإشعارات).
-- يُشغَّل بعد تطبيق 20261121000026_audited_writes.sql مرتين، وبعد اختبارات الترحيل 25.
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
-- قراءة سجل التدقيق بصلاحية المالك (القراءة فيه محصورة بسياسات)
create or replace function pg_temp.alog() returns setof public.audit_log language sql security definer as $$
  select * from public.audit_log
$$;
create or replace function pg_temp.proj(p_id uuid) returns public.projects language sql security definer as $$
  select * from public.projects where id = p_id
$$;
grant execute on all functions in schema pg_temp to authenticated, anon;

update app_settings set value = 'false' where key in ('security.freeze', 'security.require_mfa_all');
create temp table ids (k text primary key, v uuid);
grant all on ids to authenticated;

-- إشعار لموظف المكتب (للاختبار الأخير)
insert into notifications (user_id, kind, title)
select id, 'test', 'إشعار اختبار' from profiles where email = 'k.staff@test.ly';

set role authenticated;

-- ---------------------------------------------------------------- لا كتابة مباشرة
select pg_temp.as_user('k.staff@test.ly');
select pg_temp.expect_error($$insert into projects (name, department) values ('مباشر', 'supervision')$$, 'إنشاء عقد مباشرة');
select pg_temp.expect_error($$update projects set notes = 'مباشر' where true$$, 'تعديل عقد مباشرة');
select pg_temp.expect_error($$delete from projects where true$$, 'حذف عقد مباشرة');
select pg_temp.expect_error($$update form_defs set sensitive = true where key = 'f01'$$, 'تعديل صلاحيات نموذج مباشرة');
select pg_temp.expect_error($$update profiles set full_name = 'مباشر' where true$$, 'تعديل الاسم مباشرة');
select pg_temp.expect_error($$update notifications set read_at = now() where true$$, 'قراءة الإشعارات مباشرة');
select pg_temp.as_user('k.qa@test.ly');
select pg_temp.expect_error($$insert into quality_notes (project_id, body) select id, 'مباشر' from projects limit 1$$, 'ملاحظة جودة مباشرة');

-- ---------------------------------------------------------------- العقود
select pg_temp.as_user('k.staff@test.ly');
insert into ids select 'p', public.save_project(null, '{"assign_no": "T-26", "name": "عقد اختبار الترحيل 26", "owner": "الجهة", "company": "شركة الاختبار", "department": "supervision"}');
select pg_temp.check((select (pg_temp.proj(v)).name = 'عقد اختبار الترحيل 26' and (pg_temp.proj(v)).created_by = (select id from profiles where email = 'k.staff@test.ly')
                        from ids where k = 'p'), 'موظف المكتب ينشئ العقد عبر الدالة');
select pg_temp.check((select count(*) = 1 from pg_temp.alog() where action = 'project.create' and project_id = (select v from ids where k = 'p')),
                     'وإنشاؤه مسجّل في سجل التدقيق');
select pg_temp.check(public.save_project((select v from ids where k = 'p'), '{"notes": "ملاحظة على العقد", "owner": "جهة أخرى"}')
                       = (select v from ids where k = 'p'), 'التعديل يعيد معرّف العقد');
select pg_temp.check((select (pg_temp.proj(v)).notes = 'ملاحظة على العقد' and (pg_temp.proj(v)).owner = 'جهة أخرى' and (pg_temp.proj(v)).name = 'عقد اختبار الترحيل 26'
                        from ids where k = 'p'), 'التعديل يغيّر الحقول المرسلة وحدها');
select pg_temp.check((select count(*) = 1 from pg_temp.alog() where action = 'project.update' and project_id = (select v from ids where k = 'p')
                        and detail ? 'notes' and detail ? 'owner'), 'وتعديله مسجّل بالقيم السابقة والجديدة');
select pg_temp.expect_error($$select public.save_project((select v from ids where k = 'p'), '{"contract_no": "990"}')$$, 'رقم العقد له دالته');
select pg_temp.expect_error($$select public.save_project((select v from ids where k = 'p'), '{"merged_into": null}')$$, 'حقل غير مسموح');
select pg_temp.expect_error($$select public.save_project(null, '{"name": "عقد", "department": "supervision", "contract_value": 100}')$$,
                            'البيانات المالية لا تُدخل عند الإنشاء');
select pg_temp.expect_error($$select public.save_project(null, '{}')$$, 'بيانات فارغة');
select pg_temp.expect_error($$select public.delete_project((select v from ids where k = 'p'))$$, 'الحذف ليس لموظف المكتب');

select pg_temp.as_user('k.contracts@test.ly');
select pg_temp.expect_error($$select public.save_project((select v from ids where k = 'p'), '{"notes": "عقود"}')$$, 'مكتب العقود لا يعدّل بيانات العقد الأساسية');

-- ---------------------------------------------------------------- ملاحظات الجودة
select pg_temp.as_user('k.qa@test.ly');
insert into ids select 'n', public.add_quality_note((select v from ids where k = 'p'), '  ملاحظة تقييم  ');
select pg_temp.check((select count(*) = 1 from quality_notes q where q.id = (select v from ids where k = 'n') and q.body = 'ملاحظة تقييم'
                        and q.author = (select id from profiles where email = 'k.qa@test.ly')), 'مكتب الجودة يضيف ملاحظة باسمه');
select pg_temp.check((select count(*) = 1 from pg_temp.alog() where action = 'note.add' and project_id = (select v from ids where k = 'p')),
                     'والملاحظة مسجّلة');
select pg_temp.expect_error($$select public.add_quality_note((select v from ids where k = 'p'), '   ')$$, 'ملاحظة فارغة');
select pg_temp.as_user('k.staff@test.ly');
select pg_temp.expect_error($$select public.add_quality_note((select v from ids where k = 'p'), 'ملاحظة')$$, 'موظف المكتب لا يضيف ملاحظات الجودة');

-- ---------------------------------------------------------------- صلاحيات النماذج
select pg_temp.expect_error($$select public.set_form_rights('f01', true, null)$$, 'صلاحيات النماذج ليست لموظف المكتب');
select pg_temp.as_user('director.new@test.ly', 'aal2');
select public.set_form_rights('f01', true, null);
select pg_temp.check((select sensitive and responsible = array['office_staff', 'contracts'] from form_defs where key = 'f01'),
                     'المدير يغيّر الحساسية وتبقى قائمة المختصين');
select public.set_form_rights('f01', false, array['office_staff', 'contracts', 'head:technical']);
select pg_temp.check((select not sensitive and 'head:technical' = any (responsible) from form_defs where key = 'f01'), 'ويغيّر المختصين');
select pg_temp.check((select count(*) >= 2 from pg_temp.alog() where action = 'form_def.update' and form_key = 'f01'), 'وكل تغيير مسجّل');
select public.set_form_rights('f01', null, array['office_staff', 'contracts']);
select pg_temp.expect_error($$select public.set_form_rights('f01', null, array['Robert; drop'])$$, 'مختص غير صالح');
select pg_temp.expect_error($$select public.set_form_rights('zz', true, null)$$, 'نموذج غير موجود');

-- ---------------------------------------------------------------- حذف العقد
select public.delete_project((select v from ids where k = 'p'));
select pg_temp.check((select count(*) = 0 from projects where id = (select v from ids where k = 'p')), 'المدير يحذف العقد');
select pg_temp.check((select count(*) = 1 from pg_temp.alog() where action = 'project.delete' and project_id = (select v from ids where k = 'p')),
                     'والحذف مسجّل');
select pg_temp.expect_error($$select public.delete_project((select v from ids where k = 'p'))$$, 'عقد غير موجود');

-- ---------------------------------------------------------------- الاسم والإشعارات
select pg_temp.as_user('k.staff@test.ly');
select public.set_my_name('  موظف   المكتب  ك  ');
select pg_temp.check((select full_name = 'موظف المكتب ك' from profiles where email = 'k.staff@test.ly'), 'المستخدم يغيّر اسمه وتُضغط المسافات');
select pg_temp.check((select count(*) = 1 from pg_temp.alog() where action = 'user.rename' and detail ->> 'to' = 'موظف المكتب ك'), 'وتغيير الاسم مسجّل');
select public.set_my_name('موظف المكتب ك');
select pg_temp.check((select count(*) = 1 from pg_temp.alog() where action = 'user.rename' and detail ->> 'to' = 'موظف المكتب ك'), 'الاسم نفسه لا يُسجَّل مرتين');
select pg_temp.expect_error($$select public.set_my_name('ك')$$, 'اسم قصير');
select pg_temp.check(public.mark_notifications_read() >= 1, 'قراءة الإشعارات عبر الدالة');
select pg_temp.check(public.mark_notifications_read() = 0, 'ولا يبقى غير مقروء');

-- ---------------------------------------------------------------- الفحص الأمني
select pg_temp.as_user('auditor@test.ly', 'aal2');
select pg_temp.check((select (x ->> 'ok')::boolean and (x ->> 'count')::int = 0 from public.sec_posture() x where x ->> 'key' = 'direct_write'),
                     'فحص «الكتابة عبر الدوال المدققة فقط» سليم بصلاحيات الجداول والأعمدة');

reset role;
