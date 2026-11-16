-- اختبارات الترحيل 22: قسم الشؤون الفنية ونقل السجلات، والفيديو، وقوالب الطباعة، وسجل التصدير.
-- يُشغَّل بعد تطبيق 20261116000022_print_center.sql مرتين، وبعد اختبارات الترحيل 21 (يستعمل بياناتها).
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
create or replace function pg_temp.pid(p_no text) returns uuid language sql security definer as $$
  select id from public.projects where assign_no = p_no
$$;
create or replace function pg_temp.rec(p_title text) returns uuid language sql security definer as $$
  select id from public.unit_records where title = p_title order by created_at limit 1
$$;
create or replace function pg_temp.upload(p_path text, p_size bigint default 1000, p_mime text default 'application/pdf') returns void language plpgsql as $$
begin
  insert into storage.objects (bucket_id, name, owner, owner_id, metadata)
  values ('docs', p_path, auth.uid(), auth.uid()::text, jsonb_build_object('size', p_size, 'mimetype', p_mime));
end $$;
grant execute on all functions in schema pg_temp to authenticated, anon;

update app_settings set value = 'false' where key in ('security.freeze', 'security.require_mfa_all');
create temp table ids (k text primary key, v uuid);
grant all on ids to authenticated;

-- ---------------------------------------------------------------- البنية ونقل السجلات القائمة
select pg_temp.check((select string_agg(key || ':' || section, ',' order by sort) from org_units) =
  'heritage:heritage,planning:planning_qa,quality_assurance:planning_qa,follow_up:planning_qa,safety:safety,receiving:acceptance,quality_control:acceptance,technical:technical',
  'وحدة الشؤون الفنية الثامنة');
select pg_temp.check(public.unit_kind_spec('ncr') ->> 'unit' = 'quality_control' and public.unit_kind_spec('ncr') ->> 'parent' = 'qc_test'
                     and public.unit_kind_spec('material_approval') ->> 'unit' = 'technical'
                     and public.unit_kind_spec('qa_audit') ->> 'unit' = 'quality_assurance',
  'عدم المطابقة إلى ضبط الجودة، واعتماد المواد إلى الشؤون الفنية، والتدقيق باقٍ');
select pg_temp.check((select unit = 'quality_control' and parent_id is null from unit_records where title = 'غياب سجل معايرة الأجهزة'),
  'حالة عدم المطابقة القائمة انتقلت وفقدت ارتباطها بالتدقيق');
select pg_temp.check(not exists (select 1 from unit_records where kind = 'ncr' and unit <> 'quality_control')
                     and not exists (select 1 from unit_records where kind = 'material_approval' and unit <> 'technical'),
  'لا سجل باقٍ في وحدته القديمة');
select pg_temp.check((select 'video/mp4' = any(allowed_mime_types) and file_size_limit = 52428800 from storage.buckets where id = 'docs'),
  'الحاوية تقبل الفيديو حتى 50 ميجابايت');
select pg_temp.check((select proconfig is not null from pg_proc where proname = 'doc_kind_label'), 'مسار البحث ثابت لدالة تسمية المستندات');

-- ---------------------------------------------------------------- الصلاحيات بعد النقل
set role authenticated;
select pg_temp.as_user('k.headtech@test.ly');
select pg_temp.check(public.unit_can_edit('technical') and public.unit_is_head('technical') and not public.unit_can_edit('quality_control'),
  'رئيس الشؤون الفنية يكتب في وحدته ويرأسها، ولا يكتب في ضبط الجودة');
insert into ids select 'mat', public.save_unit_record(null, jsonb_build_object('kind', 'material_approval', 'project_id', pg_temp.pid('990'),
  'title', 'بلاط بورسلين 60×60', 'rec_date', '2026-11-16', 'due_date', '2026-11-23', 'owner_text', 'مصنع الجبل'));
select pg_temp.check((select unit = 'technical' and status = 'under_review' from unit_records where id = (select v from ids where k = 'mat')),
  'طلب اعتماد المادة يُسجَّل في الشؤون الفنية');

select pg_temp.as_user('u.qc@test.ly');
select pg_temp.expect_error($$select public.save_unit_record(null, jsonb_build_object('kind','material_approval','project_id',pg_temp.pid('990'),
  'title','حديد تسليح'))$$, 'ضبط الجودة لم يعد يكتب في اعتماد المواد');
insert into ids select 'ncr', public.save_unit_record(null, jsonb_build_object('kind', 'ncr',
  'parent_id', pg_temp.rec('مقاومة مكعبات الخرسانة 28 يوماً'), 'title', 'تعشيش في خرسانة العمود C3', 'level', 'major',
  'rec_date', '2026-11-16', 'due_date', '2026-11-25'));
select pg_temp.check((select unit = 'quality_control' and parent_id = pg_temp.rec('مقاومة مكعبات الخرسانة 28 يوماً')
                        and project_id = pg_temp.pid('990') from unit_records where id = (select v from ids where k = 'ncr')),
  'عضو ضبط الجودة يسجّل عدم المطابقة ويربطها بالاختبار فتأخذ عقده');
select pg_temp.expect_error($$select public.save_unit_record(null, jsonb_build_object('kind','ncr','title','عدم مطابقة',
  'parent_id', (select id from unit_records where kind = 'qa_audit' limit 1)))$$, 'لا تتبع عدم المطابقة تدقيقاً بعد الآن');

select pg_temp.as_user('k.qa@test.ly');
select pg_temp.check(public.unit_can_edit('quality_assurance') and not public.unit_can_edit('quality_control'),
  'مكتب التخطيط يبقى في أقسامه ولا يكتب في ضبط الجودة');
select pg_temp.expect_error($$select public.save_unit_record(null, '{"kind":"ncr","title":"عدم مطابقة من التخطيط"}')$$,
  'مكتب التخطيط لم يعد يسجّل عدم المطابقة');

-- ---------------------------------------------------------------- الفيديو
select pg_temp.as_user('u.qc@test.ly');
select pg_temp.check(public.can_upload_doc_path('unit/' || (select v from ids where k = 'ncr') || '/Video0001abcd.mp4'),
  'مسار الفيديو مقبول في سجلات الأقسام');
select pg_temp.upload('unit/' || (select v from ids where k = 'ncr') || '/Video0001abcd.mp4', 41943040, 'video/mp4');
insert into ids select 'vid', public.add_doc_file('unit/' || (select v from ids where k = 'ncr') || '/Video0001abcd.mp4', 'العمود C3.mp4');
select pg_temp.check((select mime = 'video/mp4' and size_bytes = 41943040 from doc_files where id = (select v from ids where k = 'vid')),
  'فيديو 40 ميجابايت يُرفق');
select pg_temp.upload('unit/' || (select v from ids where k = 'ncr') || '/Video0002abcd.mp4', 60000000, 'video/mp4');
select pg_temp.expect_error($$select public.add_doc_file('unit/' || (select v from ids where k = 'ncr') || '/Video0002abcd.mp4', 'كبير.mp4')$$,
  'فيديو أكبر من 50 ميجابايت');
select pg_temp.upload('unit/' || (select v from ids where k = 'ncr') || '/Image0003abcd.jpg', 25000000, 'image/jpeg');
select pg_temp.expect_error($$select public.add_doc_file('unit/' || (select v from ids where k = 'ncr') || '/Image0003abcd.jpg', 'صورة.jpg')$$,
  'الصورة تبقى حتى 20 ميجابايت');
reset role;
select pg_temp.check(not public.can_upload_doc_path('doc/' || (select r.id from doc_revisions r join doc_items i on i.id = r.item_id
                                                          where i.kind = 'boq' limit 1) || '/Video0004abcd.mp4'),
  'لا فيديو في المقايسات');
set role authenticated;

-- ---------------------------------------------------------------- قوالب الطباعة
select pg_temp.as_user('k.contracts@test.ly');
insert into ids select 'mine', public.save_print_template(null, 'قالبي للمستخلصات', '{"paper":"A4","orientation":"landscape"}', false, false);
select pg_temp.check((select owner_id = auth.uid() and not is_default from print_templates where id = (select v from ids where k = 'mine')),
  'قالب خاص بصاحبه');
select pg_temp.expect_error($$select public.save_print_template(null, 'قالب عام', '{}', true, false)$$, 'الموظف لا يحفظ قالباً عاماً');
select pg_temp.expect_error($$select public.save_print_template(null, 'أ', '{}', false, false)$$, 'اسم قصير');
select pg_temp.expect_error($$select public.save_print_template(null, 'قالب', '[1,2]', false, false)$$, 'إعدادات غير صالحة');

select pg_temp.as_user('k.staff@test.ly');
insert into ids select 'shared', public.save_print_template(null, 'القالب الرسمي للمكتب', '{"header":{"logo":"emblem"}}', true, true);
select pg_temp.check((select owner_id is null and is_default from print_templates where id = (select v from ids where k = 'shared')),
  'موظف مكتب المدير يحفظ القالب العام الافتراضي');
select pg_temp.check((select count(*) = 1 from print_templates), 'قالب الموظف الخاص لا يراه غيره');
select pg_temp.expect_error($$select public.save_print_template((select v from ids where k = 'mine'), 'تعديل', '{}', false, false)$$,
  'لا يعدّل قالب غيره الخاص');

select pg_temp.as_user('director.new@test.ly', 'aal2');
insert into ids select 'dflt', public.save_print_template(null, 'قالب التقارير الرسمية', '{}', true, true);
select pg_temp.check((select count(*) = 1 from print_templates where is_default) and
                     (select is_default from print_templates where id = (select v from ids where k = 'dflt')),
  'قالب افتراضي واحد فقط');

select pg_temp.as_user('k.contracts@test.ly');
select pg_temp.check((select count(*) = 3 from print_templates), 'الموظف يرى قالبه والقالبين العامين');
select pg_temp.expect_error($$select public.delete_print_template((select v from ids where k = 'shared'))$$, 'الموظف لا يحذف قالباً عاماً');
select pg_temp.expect_error($$select public.save_print_template((select v from ids where k = 'shared'), 'استيلاء', '{}', false, false)$$,
  'ولا يعدّله أو يحوّله إلى قالب خاص به');
select public.save_print_template((select v from ids where k = 'mine'), 'قالبي للمستخلصات 2', '{"paper":"A3"}', false, false);
select pg_temp.check((select name = 'قالبي للمستخلصات 2' and config ->> 'paper' = 'A3' from print_templates where id = (select v from ids where k = 'mine')),
  'صاحب القالب يعدّله');
select public.delete_print_template((select v from ids where k = 'mine'));
select pg_temp.as_user('k.staff@test.ly');
select public.delete_print_template((select v from ids where k = 'shared'));
select pg_temp.check((select count(*) = 1 from print_templates), 'الحذف لصاحبه وللقوالب العامة لمكتب المدير');
select pg_temp.check(not has_table_privilege('authenticated', 'public.print_templates', 'INSERT')
                     and not has_table_privilege('anon', 'public.print_templates', 'SELECT'),
  'الكتابة في القوالب عبر الدوال وحدها');

-- ---------------------------------------------------------------- سجل التصدير
select pg_temp.as_user('k.contracts@test.ly');
select public.log_export('file', 'unit:ncr', 'حالات عدم المطابقة', 'pdf', 12, 48000);
select public.log_export('media', 'media', 'وسائط عقد الوحدات', 'zip', 3, 9000000);
select pg_temp.expect_error($$select public.log_export('hack', 'x', 'y', 'pdf')$$, 'نوع تصدير غير معروف');
reset role;
select pg_temp.check((select count(*) = 1 from audit_log where action = 'export.file' and detail ->> 'format' = 'pdf' and (detail ->> 'rows')::int = 12)
                     and (select count(*) = 1 from audit_log where action = 'export.media'),
  'التصدير والتنزيل المجمّع مسجّلان في التدقيق');
select pg_temp.check((select count(*) >= 5 from audit_log where action like 'print.template_%'), 'حفظ القوالب وحذفها مسجّلان');

-- وضع القراءة فقط يوقف حفظ القوالب
update app_settings set value = 'true' where key = 'security.freeze';
set role authenticated;
select pg_temp.as_user('k.staff@test.ly');
select pg_temp.expect_error($$select public.save_print_template(null, 'قالب أثناء التجميد', '{}', false, false)$$, 'وضع القراءة فقط');
reset role;
update app_settings set value = 'false' where key = 'security.freeze';

select 'PRINT CENTER TESTS PASSED';
