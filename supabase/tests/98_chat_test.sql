-- اختبارات الترحيل 24: المراسلات الداخلية (الخاصة والمجموعات والقنوات والمرفقات والقفل والبيانات الوصفية).
-- يُشغَّل بعد تطبيق 20261119000024_chat.sql مرتين، وبعد اختبارات الترحيل 23.
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
create or replace function pg_temp.upload(p_path text, p_size bigint default 1000, p_mime text default 'image/jpeg') returns void language plpgsql as $$
begin
  insert into storage.objects (bucket_id, name, owner, owner_id, metadata)
  values ('chat', p_path, auth.uid(), auth.uid()::text, jsonb_build_object('size', p_size, 'mimetype', p_mime));
end $$;
create or replace function pg_temp.unread(p_room uuid) returns int language sql as $$
  select (x ->> 'unread')::int from public.chat_my_rooms() x where (x ->> 'id')::uuid = p_room
$$;
create or replace function pg_temp.alog() returns setof public.audit_log language sql security definer as $$
  select * from public.audit_log
$$;
grant execute on all functions in schema pg_temp to authenticated, anon;

update app_settings set value = 'false' where key in ('security.freeze', 'security.require_mfa_all');
create temp table ids (k text primary key, v uuid);
create temp table mids (k text primary key, v bigint);
grant all on ids, mids to authenticated;

-- ---------------------------------------------------------------- البنية
select pg_temp.check((select count(*) = 1 from chat_rooms where kind = 'channel' and audience ->> 'all' = 'true'), 'القناة العامة موجودة');
select pg_temp.check((select public = false and file_size_limit = 52428800 and 'video/mp4' = any (allowed_mime_types)
                        from storage.buckets where id = 'chat'), 'حاوية المراسلات خاصة وتقبل الفيديو حتى 50 ميجابايت');
select pg_temp.check((select value ->> 'enabled' = 'true' from app_settings where key = 'chat.config'), 'إعدادات المراسلات');

-- ---------------------------------------------------------------- المحادثة الخاصة
set role authenticated;
select pg_temp.as_user('k.contracts@test.ly');
insert into ids select 'dm', public.chat_open_dm(pg_temp.uid('k.staff@test.ly'));
select pg_temp.check(public.chat_open_dm(pg_temp.uid('k.staff@test.ly')) = (select v from ids where k = 'dm'), 'فتح المحادثة مرة ثانية يعيدها نفسها');
select pg_temp.expect_error($$select public.chat_open_dm(auth.uid())$$, 'لا محادثة مع النفس');
select pg_temp.expect_error($$select public.chat_open_dm(pg_temp.uid('pending@test.ly'))$$, 'ولا مع حساب غير مفعّل');
insert into mids select 'm1', public.chat_send((select v from ids where k = 'dm'), 'سري للغاية: كمية الحديد 1250 طن');
select pg_temp.check((select count(*) = 1 from chat_messages where room_id = (select v from ids where k = 'dm')), 'المرسل يرى رسالته');
select pg_temp.expect_error($$select public.chat_send((select v from ids where k = 'dm'), '   ')$$, 'رسالة فارغة');
select pg_temp.expect_error($$insert into chat_messages (room_id, body) values ((select v from ids where k = 'dm'), 'x')$$, 'لا كتابة مباشرة');

select pg_temp.as_user('k.staff@test.ly');
select pg_temp.check(public.chat_open_dm(pg_temp.uid('k.contracts@test.ly')) = (select v from ids where k = 'dm'), 'الطرف الآخر يصل إلى المحادثة نفسها');
select pg_temp.check(pg_temp.unread((select v from ids where k = 'dm')) = 1, 'رسالة غير مقروءة واحدة');
insert into mids select 'm2', public.chat_send((select v from ids where k = 'dm'), 'تم الاستلام', null, (select v from mids where k = 'm1'));
select pg_temp.check((select reply_to = (select v from mids where k = 'm1') from chat_messages where id = (select v from mids where k = 'm2')),
  'الرد على رسالة');
select public.chat_mark_read((select v from ids where k = 'dm'));
select pg_temp.check(pg_temp.unread((select v from ids where k = 'dm')) = 0, 'القراءة تصفّر العداد');
select pg_temp.expect_error($$select public.chat_edit_message((select v from mids where k = 'm1'), 'تعديل')$$, 'لا يعدّل رسالة غيره');
select pg_temp.expect_error($$select public.chat_delete_message((select v from mids where k = 'm1'))$$, 'ولا يحذفها في محادثة خاصة');

select pg_temp.as_user('u.qc@test.ly');
select pg_temp.check((select count(*) = 0 from chat_messages where room_id = (select v from ids where k = 'dm'))
                     and (select count(*) = 0 from chat_rooms where id = (select v from ids where k = 'dm')),
  'شخص ثالث لا يرى المحادثة الخاصة');
select pg_temp.expect_error($$select public.chat_send((select v from ids where k = 'dm'), 'تطفل')$$, 'ولا يرسل فيها');
select pg_temp.check(not public.chat_can_upload_path((select v from ids where k = 'dm') || '/abcdefgh12.jpg'), 'ولا يرفع إليها');

select pg_temp.as_user('k.contracts@test.ly');
select public.chat_edit_message((select v from mids where k = 'm1'), 'سري للغاية: كمية الحديد 1300 طن');
select pg_temp.check((select edited_at is not null from chat_messages where id = (select v from mids where k = 'm1')), 'يعدّل رسالته');

-- المرفقات
select pg_temp.check(public.chat_can_upload_path((select v from ids where k = 'dm') || '/Video0001abcd.mp4'), 'عضو المحادثة يرفع إليها');
select pg_temp.check(not public.chat_can_upload_path((select v from ids where k = 'dm') || '/Video0001abcd.exe'), 'امتداد غير مسموح');
select pg_temp.upload((select v from ids where k = 'dm') || '/Video0001abcd.mp4', 5242880, 'video/mp4');
insert into mids select 'f1', public.chat_send((select v from ids where k = 'dm'), 'فيديو الموقع',
  jsonb_build_object('path', (select v from ids where k = 'dm') || '/Video0001abcd.mp4', 'name', 'موقع 990.mp4'));
select pg_temp.check((select kind = 'file' and file_size = 5242880 and file_mime = 'video/mp4' and file_name = 'موقع 990.mp4'
                        from chat_messages where id = (select v from mids where k = 'f1')),
  'النوع والحجم من الحاوية لا من التطبيق');
select pg_temp.expect_error($$select public.chat_send((select v from ids where k = 'dm'), '',
  jsonb_build_object('path', (select v from ids where k = 'dm') || '/Video0001abcd.mp4'))$$, 'لا يُعاد استخدام المرفق');
select pg_temp.expect_error($$select public.chat_send((select v from ids where k = 'dm'), '',
  jsonb_build_object('path', '00000000-0000-4000-8000-00000000c4a7/Image0009abcd.jpg'))$$, 'مسار من محادثة أخرى');
select pg_temp.expect_error($$select public.chat_send((select v from ids where k = 'dm'), '',
  jsonb_build_object('path', (select v from ids where k = 'dm') || '/Missing01abcd.jpg'))$$, 'مرفق لم يكتمل رفعه');
insert into mids select 'l1', public.chat_send((select v from ids where k = 'dm'), '',
  null, null, '{"type": "project", "id": "990", "label": "عقد 990 – مدرسة الصابري"}');
select pg_temp.check((select kind = 'link' and ref ->> 'label' like 'عقد 990%' from chat_messages where id = (select v from mids where k = 'l1')),
  'ربط عقد من المنظومة');
select pg_temp.expect_error($$select public.chat_send((select v from ids where k = 'dm'), '', null, null, '{"type": "x", "label": "y"}')$$,
  'نوع رابط غير معروف');

select pg_temp.as_user('u.qc@test.ly');
select pg_temp.check((select count(*) = 0 from storage.objects where bucket_id = 'chat'), 'غير العضو لا يقرأ ملفات المحادثة');
select pg_temp.as_user('k.staff@test.ly');
select pg_temp.check((select count(*) = 1 from storage.objects where bucket_id = 'chat'), 'العضو يقرأ ملفاتها');

-- ---------------------------------------------------------------- المجموعات
select pg_temp.as_user('k.contracts@test.ly');
select pg_temp.expect_error($$select public.chat_create_group('م', array[pg_temp.uid('k.staff@test.ly')])$$, 'اسم قصير');
select pg_temp.expect_error($$select public.chat_create_group('فريق', '{}')$$, 'مجموعة بلا أعضاء');
insert into ids select 'grp', public.chat_create_group('فريق عقد 990', array[pg_temp.uid('k.staff@test.ly'), pg_temp.uid('u.qc@test.ly'), auth.uid()]);
select pg_temp.check((select count(*) = 3 from chat_members where room_id = (select v from ids where k = 'grp') and explicit)
                     and (select role = 'owner' from chat_members where room_id = (select v from ids where k = 'grp') and user_id = auth.uid()),
  'ثلاثة أعضاء والمنشئ مالكها');
select pg_temp.check((select count(*) = 1 from chat_messages where room_id = (select v from ids where k = 'grp') and kind = 'system'),
  'رسالة نظام عند الإنشاء');
insert into mids select 'g1', public.chat_send((select v from ids where k = 'grp'), 'اجتماع الأحد 9 صباحاً');

select pg_temp.as_user('headsup@test.ly');
select pg_temp.check((select count(*) = 0 from chat_messages where room_id = (select v from ids where k = 'grp')), 'غير العضو لا يرى المجموعة');
select pg_temp.as_user('u.qc@test.ly');
insert into mids select 'g2', public.chat_send((select v from ids where k = 'grp'), 'سأحضر');
select pg_temp.expect_error($$select public.chat_set_members((select v from ids where k = 'grp'), array[pg_temp.uid('headsup@test.ly')], null)$$,
  'العضو العادي لا يضيف أعضاء');

select pg_temp.as_user('k.contracts@test.ly');
select public.chat_set_members((select v from ids where k = 'grp'), array[pg_temp.uid('headsup@test.ly')], array[pg_temp.uid('u.qc@test.ly')]);
select pg_temp.check((select count(*) = 1 from pg_temp.alog() where action = 'chat.members'), 'تعديل الأعضاء مسجّل');
select public.chat_set_member_role((select v from ids where k = 'grp'), pg_temp.uid('k.staff@test.ly'), 'admin');
select pg_temp.as_user('u.qc@test.ly');
select pg_temp.check((select count(*) = 0 from chat_messages where room_id = (select v from ids where k = 'grp')), 'المُزال يفقد الوصول');
select pg_temp.as_user('headsup@test.ly');
select pg_temp.check((select count(*) >= 3 from chat_messages where room_id = (select v from ids where k = 'grp')), 'المضاف يرى السجل');
select pg_temp.as_user('k.staff@test.ly');
select public.chat_delete_message((select v from mids where k = 'g2'));
select pg_temp.check((select deleted_at is not null and body = '' from chat_messages where id = (select v from mids where k = 'g2'))
                     and exists (select 1 from pg_temp.alog() where action = 'chat.message_delete'),
  'المشرف يحذف رسالة غيره ويُسجَّل ذلك');
select public.chat_update_room((select v from ids where k = 'grp'), '{"title": "فريق عقد 990 – الإشراف", "admins_only": false}');
select pg_temp.expect_error($$select public.chat_update_room((select v from ids where k = 'grp'), '{"audience": {"all": true}}')$$,
  'الجمهور للقنوات وحدها');
select pg_temp.as_user('k.contracts@test.ly');
select public.chat_leave((select v from ids where k = 'grp'));
select pg_temp.as_user('k.staff@test.ly');
select pg_temp.check((select user_id = pg_temp.uid('k.staff@test.ly') from chat_members
                       where room_id = (select v from ids where k = 'grp') and role = 'owner'),
  'مغادرة المالك تنقل الملكية إلى المشرف');
select pg_temp.as_user('k.contracts@test.ly');

-- ---------------------------------------------------------------- القنوات
select pg_temp.expect_error($$select public.chat_create_channel('قناة', '', '{"all": true}')$$, 'القنوات للمدير');
select pg_temp.as_user('director.new@test.ly', 'aal2');
select pg_temp.expect_error($$select public.chat_create_channel('قناة', '', '{}')$$, 'قناة بلا جمهور');
select pg_temp.expect_error($$select public.chat_create_channel('قناة', '', '{"everyone": true}')$$, 'مفتاح جمهور غير معروف');
insert into ids select 'ch', public.chat_create_channel('قسم الإشراف', 'تعليمات القسم', '{"departments": ["supervision"]}', true);
insert into mids select 'c1', public.chat_send((select v from ids where k = 'ch'), 'تسليم التقارير اليومية قبل الثانية ظهراً');
select pg_temp.as_user('headsup@test.ly');
select pg_temp.check((select count(*) = 2 from chat_messages where room_id = (select v from ids where k = 'ch')), 'رئيس الإشراف يدخل القناة تلقائياً');
select pg_temp.check(pg_temp.unread((select v from ids where k = 'ch')) = 1, 'ويرى غير المقروء');
select pg_temp.expect_error($$select public.chat_send((select v from ids where k = 'ch'), 'سؤال')$$, 'قناة إعلانات: الإرسال للمشرفين');
select pg_temp.as_user('k.contracts@test.ly');
select pg_temp.check((select count(*) = 0 from chat_messages where room_id = (select v from ids where k = 'ch')), 'من خارج القسم لا يراها');
select pg_temp.as_user('director.new@test.ly', 'aal2');
select public.chat_set_member_role((select v from ids where k = 'ch'), pg_temp.uid('headsup@test.ly'), 'admin');
select pg_temp.as_user('headsup@test.ly');
insert into mids select 'c2', public.chat_send((select v from ids where k = 'ch'), 'تم التعميم على المهندسين');
select pg_temp.check((select v from mids where k = 'c2') is not null, 'المشرف المعيّن يرسل في القناة');
select public.chat_set_pref((select v from ids where k = 'ch'), null, true);
select pg_temp.check(((select x from public.chat_my_rooms() x limit 1) ->> 'id')::uuid = (select v from ids where k = 'ch'), 'المثبّتة أولاً');

-- ---------------------------------------------------------------- القفل والبيانات الوصفية
select pg_temp.as_user('k.staff@test.ly');
select pg_temp.expect_error($$select public.chat_set_lock((select v from ids where k = 'dm'), true, 'اشتباه')$$, 'القفل لغير المسؤول مرفوض');
select pg_temp.as_user('auditor@test.ly', 'aal2');
select pg_temp.check((select count(*) = 0 from chat_messages where room_id = (select v from ids where k = 'dm')), 'مسؤول الأمن لا يقرأ نص المحادثات');
select pg_temp.expect_error($$select public.chat_set_lock((select v from ids where k = 'dm'), true, '')$$, 'القفل بلا سبب');
select public.chat_set_lock((select v from ids where k = 'dm'), true, 'تحقيق في تسريب');
select pg_temp.check((select count(*) = 1 from pg_temp.alog() where action = 'chat.lock' and detail ->> 'title' like '%↔%'), 'القفل مسجّل باسمي الطرفين');
select pg_temp.check((public.sec_chat_overview(30) -> 'totals' ->> 'messages')::int >= 6
                     and (public.sec_chat_overview(30) -> 'totals' ->> 'bytes')::bigint = 5242880
                     and (public.sec_chat_overview(30) -> 'totals' ->> 'locked')::int = 1,
  'البيانات الوصفية: عدد الرسائل وحجم المرفقات والمقفلة');
select pg_temp.check(public.sec_chat_overview(30)::text not like '%الحديد%' and public.sec_chat_overview(30)::text not like '%موقع 990.mp4%'
                     and (select string_agg(x::text, '') from public.sec_chat_room_log((select v from ids where k = 'dm')) x) not like '%الحديد%',
  'دون نص الرسائل أو أسماء الملفات');
select pg_temp.check((select count(*) >= 4 from public.sec_chat_room_log((select v from ids where k = 'dm')))
                     and (select bool_or((x ->> 'size')::bigint = 5242880) from public.sec_chat_room_log((select v from ids where k = 'dm')) x),
  'سجل وصفي لكل رسالة: المرسل والوقت والحجم');
select pg_temp.as_user('k.contracts@test.ly');
select pg_temp.expect_error($$select public.chat_send((select v from ids where k = 'dm'), 'هل وصلت؟')$$, 'المحادثة المقفلة لا تقبل رسائل');
select pg_temp.expect_error($$select public.sec_chat_overview(30)$$, 'البيانات الوصفية لغير المسؤول مرفوضة');
select pg_temp.as_user('auditor@test.ly', 'aal2');
select public.chat_set_lock((select v from ids where k = 'dm'), false);
select pg_temp.as_user('k.contracts@test.ly');
select public.chat_send((select v from ids where k = 'dm'), 'وصلت؟');

-- حذف المرسل لرسالته يعيد مسار المرفق
select pg_temp.check(public.chat_delete_message((select v from mids where k = 'f1')) like '%/Video0001abcd.mp4', 'حذف المرفق يعيد مساره');
select pg_temp.check((select file_path is null and deleted_at is not null from chat_messages where id = (select v from mids where k = 'f1')),
  'والرسالة تبقى أثراً بلا محتوى');

-- حد الإرسال
select pg_temp.expect_error($q$do $d$ begin for i in 1..45 loop perform public.chat_send('00000000-0000-4000-8000-00000000c4a7', 'رسالة ' || i); end loop; end $d$$q$,
  'أكثر من 40 رسالة في الدقيقة');

-- الإعدادات
select pg_temp.expect_error($$select public.set_setting('chat.config', '{"enabled": false}')$$, 'إعدادات المراسلات للمدير');
select pg_temp.as_user('director.new@test.ly', 'aal2');
select pg_temp.expect_error($$select public.set_setting('chat.config', '{"max_file_mb": 500}')$$, 'حجم أكبر من حد الحاوية');
select pg_temp.expect_error($$select public.set_setting('chat.config', '{"x": 1}')$$, 'مفتاح غير معروف');
select public.set_setting('chat.config', '{"enabled": true, "groups": false, "max_file_mb": 20, "edit_minutes": 30}');
select pg_temp.as_user('k.contracts@test.ly');
select pg_temp.expect_error($$select public.chat_create_group('فريق ثانٍ', array[pg_temp.uid('k.staff@test.ly')])$$, 'المجموعات موقوفة لغير المدير');
select pg_temp.as_user('director.new@test.ly', 'aal2');
select public.set_setting('chat.config', '{"enabled": true, "groups": true, "max_file_mb": 50, "edit_minutes": 60}');
select public.set_setting('ui.layout', '{}');
select pg_temp.check((select value = '{}'::jsonb from app_settings where key = 'ui.layout'), 'الإعدادات الأخرى تمر عبر السلسلة');

-- الحذف
select pg_temp.expect_error($$select public.chat_delete_room('00000000-0000-4000-8000-00000000c4a7')$$, 'القناة العامة لا تُحذف');
select pg_temp.check(coalesce(array_length(public.chat_delete_room((select v from ids where k = 'grp')), 1), 0) = 0
                     and not exists (select 1 from chat_rooms where id = (select v from ids where k = 'grp'))
                     and exists (select 1 from pg_temp.alog() where action = 'chat.room_delete'),
  'المدير يحذف المجموعة ويُسجَّل');

reset role;
select 'ALL 24 TESTS PASSED';
