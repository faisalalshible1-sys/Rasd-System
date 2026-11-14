-- اختبارات الترحيل 20: المستندات الفنية (المقايسات، المراسلات، التصاميم) والتقارير اليومية للإشراف.
-- يُشغَّل بعد تطبيق 20261114000020_documents_supervision.sql مرتين.
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
-- محاكاة رفع ملف إلى الحاوية كما يفعل Supabase Storage (يخضع لسياسة الرفع)
create or replace function pg_temp.upload(p_path text, p_size bigint default 1000, p_mime text default 'application/pdf') returns void language plpgsql as $$
begin
  insert into storage.objects (bucket_id, name, owner, owner_id, metadata)
  values ('docs', p_path, auth.uid(), auth.uid()::text, jsonb_build_object('size', p_size, 'mimetype', p_mime));
end $$;
create or replace function pg_temp.j(p_text text) returns jsonb language sql as $$ select p_text::jsonb $$;
grant execute on all functions in schema pg_temp to authenticated, anon;

update app_settings set value = 'false' where key in ('security.freeze', 'security.require_mfa_all');
create temp table ids (k text primary key, v uuid);
grant all on ids to authenticated;

-- ---------------------------------------------------------------- البنية والحاوية
select pg_temp.check((select not public and file_size_limit = 20971520 and 'application/pdf' = any (allowed_mime_types)
                        from storage.buckets where id = 'docs'), 'حاوية docs خاصة بحد 20 ميجابايت');
select pg_temp.check((select count(*) = 3 from pg_policies where schemaname = 'storage' and policyname like 'docs_%'),
  'سياسات القراءة والرفع والحذف للحاوية');
select pg_temp.check((select bool_and(relrowsecurity) from pg_class where oid in
                        ('public.doc_items'::regclass, 'public.doc_revisions'::regclass, 'public.doc_files'::regclass, 'public.site_reports'::regclass)),
  'RLS مفعّل على الجداول الأربعة');
select pg_temp.check(not has_table_privilege('authenticated', 'public.doc_items', 'INSERT')
                     and not has_table_privilege('authenticated', 'public.site_reports', 'UPDATE')
                     and not has_table_privilege('anon', 'public.doc_files', 'SELECT'),
  'الكتابة عبر الدوال وحدها، ولا قراءة لغير المسجّلين');
select pg_temp.check((select count(*) = 4 from pg_publication_tables where pubname = 'supabase_realtime'
                        and tablename in ('doc_items', 'doc_revisions', 'doc_files', 'site_reports')), 'التحديث اللحظي');

-- ---------------------------------------------------------------- عقود الاختبار
set role authenticated;
select pg_temp.as_user('director.new@test.ly', 'aal2');
insert into projects (assign_no, name, owner, company, department) values ('980', 'عقد المستندات', 'المالك', 'شركة أ', 'supervision');
insert into projects (assign_no, name, owner, company, department) values ('981', 'عقد الترميم', 'المالك', 'شركة ب', 'restoration');
insert into projects (assign_no, name, owner, company, department) values ('982', 'عقد للدمج', 'المالك', 'شركة ج', 'supervision');

-- ---------------------------------------------------------------- المقايسات
select pg_temp.as_user('k.headtech@test.ly');
insert into ids select 'boq', (public.save_doc_item(null, jsonb_build_object(
  'kind', 'boq', 'project_id', pg_temp.pid('980'), 'title', 'مقايسة تقديرية – رصف', 'ref_no', 'BOQ-1', 'category', 'estimate',
  'amount', 125000.5, 'doc_date', '2026-11-01', 'rev_note', 'الإصدار الأول')) ->> 'item_id')::uuid;
select pg_temp.check((select count(*) = 1 and min(rev_no) = 1 and min(note) = 'الإصدار الأول' from doc_revisions
                       where item_id = (select v from ids where k = 'boq')), 'الإنشاء يُنشئ «الإصدار 1»');
select pg_temp.check((select amount = 125000.5 and status = 'draft' and direction is null from doc_items where id = (select v from ids where k = 'boq')),
  'القيمة والحالة الافتراضية');

select pg_temp.as_user('k.headsup@test.ly');
select pg_temp.expect_error($$select public.save_doc_item(null, '{"kind":"boq","title":"مقايسة","category":"estimate"}')$$,
  'رئيس الإشراف لا يضيف مقايسة');
select pg_temp.as_user('k.qa@test.ly');
select pg_temp.expect_error($$select public.save_doc_item((select v from ids where k = 'boq'), '{"title":"تعديل"}')$$,
  'مكتب التخطيط لا يعدّل المقايسة');
select pg_temp.as_user('auditor@test.ly', 'aal2');
select pg_temp.expect_error($$select public.save_doc_item(null, '{"kind":"letter","title":"مراسلة","direction":"in"}')$$,
  'CISO لا يضيف مراسلات');
select pg_temp.check((select count(*) >= 1 from doc_items), 'CISO يقرأ المستندات');

select pg_temp.as_user('k.contracts@test.ly');
select pg_temp.expect_error($$select public.save_doc_item(null, '{"kind":"boq","title":"مقايسة اختبار","category":"nonsense"}')$$, 'نوع مقايسة غير معروف');
select pg_temp.expect_error($$select public.save_doc_item(null, '{"kind":"boq","title":"مقايسة اختبار","amount":-5}')$$, 'قيمة سالبة');
select pg_temp.expect_error($$select public.save_doc_item(null, '{"kind":"plan","title":"x"}')$$, 'نوع مستند غير معروف');
insert into ids select 'boq_rev2', public.save_doc_revision(null, (select v from ids where k = 'boq'),
  '{"rev_date":"2026-11-10","note":"بعد ملاحظات المطابقة"}');
select pg_temp.check((select string_agg(rev_no::text, ',' order by rev_no) = '1,2' from doc_revisions where item_id = (select v from ids where k = 'boq')),
  'مكتب العقود يضيف «الإصدار 2»');

-- ---------------------------------------------------------------- الملفات والحاوية
select pg_temp.as_user('k.contracts@test.ly');
select pg_temp.upload('doc/' || (select v from ids where k = 'boq_rev2') || '/abcdef12345.pdf', 250000);
insert into ids select 'f1', public.add_doc_file('doc/' || (select v from ids where k = 'boq_rev2') || '/abcdef12345.pdf', 'مقايسة الإصدار 2.pdf');
select pg_temp.check((select mime = 'application/pdf' and size_bytes = 250000 and sort = 1 from doc_files where id = (select v from ids where k = 'f1')),
  'النوع والحجم من الحاوية نفسها');
select pg_temp.expect_error($$select pg_temp.upload('doc/' || (select v from ids where k = 'boq_rev2') || '/../x.pdf')$$, 'مسار غير صالح');
select pg_temp.expect_error($$select pg_temp.upload('doc/' || (select v from ids where k = 'boq_rev2') || '/abcdef12345.exe')$$, 'امتداد غير مسموح');
select pg_temp.expect_error($$select public.add_doc_file('doc/' || (select v from ids where k = 'boq_rev2') || '/notuploaded1.pdf', 'x.pdf')$$,
  'لا يُسجَّل ملف لم يُرفع');
select pg_temp.as_user('k.headsup@test.ly');
select pg_temp.expect_error($$select pg_temp.upload('doc/' || (select v from ids where k = 'boq_rev2') || '/zzzzzzzz9.pdf')$$,
  'لا يرفع ملفاً لمستند خارج صلاحيته');
select pg_temp.expect_error($$select public.delete_doc_file((select v from ids where k = 'f1'))$$, 'لا يزيل ملف غيره');
select pg_temp.check((select count(*) = 1 from storage.objects where bucket_id = 'docs'), 'كل الأعضاء يقرؤون ملفات الحاوية');
reset role;
select pg_temp.as_user('');
set role anon;
select pg_temp.check((select count(*) = 0 from storage.objects where bucket_id = 'docs'), 'الزائر لا يرى ملفات الحاوية');
reset role;
set role authenticated;

-- الحذف من الحاوية ممنوع ما دام الملف مسجلاً
select pg_temp.as_user('k.contracts@test.ly');
delete from storage.objects where bucket_id = 'docs' and name like 'doc/%abcdef12345.pdf';
select pg_temp.check((select count(*) = 1 from storage.objects where bucket_id = 'docs'), 'لا يُحذف ملف ما زال مرتبطاً بسجل');
select pg_temp.check(public.delete_doc_file((select v from ids where k = 'f1')) like 'doc/%abcdef12345.pdf', 'صاحب الملف يزيله خلال 24 ساعة');
delete from storage.objects where bucket_id = 'docs' and name like 'doc/%abcdef12345.pdf';
select pg_temp.check((select count(*) = 0 from storage.objects where bucket_id = 'docs'), 'ثم يُحذف من الحاوية');

-- ---------------------------------------------------------------- التصاميم ومسار التطوير
select pg_temp.as_user('headrest@test.ly');
insert into ids select 'design', (public.save_doc_item(null, jsonb_build_object(
  'kind', 'design', 'project_id', pg_temp.pid('981'), 'title', 'واجهة المبنى التراثي', 'category', 'heritage', 'party', 'الاستشاري')) ->> 'revision_id')::uuid;
select pg_temp.upload('doc/' || (select v from ids where k = 'design') || '/img00000001.jpg', 400000, 'image/jpeg');
select pg_temp.upload('doc/' || (select v from ids where k = 'design') || '/img00000002.png', 500000, 'image/png');
select public.add_doc_file('doc/' || (select v from ids where k = 'design') || '/img00000001.jpg', 'منظور 1.jpg', 1600, 900);
select public.add_doc_file('doc/' || (select v from ids where k = 'design') || '/img00000002.png', 'منظور 2.png', 1600, 900);
select pg_temp.check((select string_agg(sort::text || ':' || mime, ',' order by sort) = '1:image/jpeg,2:image/png'
                        from doc_files where revision_id = (select v from ids where k = 'design')), 'صور التصميم بترتيب رفعها');
select pg_temp.as_user('k.headsup@test.ly');
select pg_temp.expect_error($$select public.save_doc_revision(null, (select item_id from doc_revisions where id = (select v from ids where k = 'design')), '{}')$$,
  'رئيس الإشراف لا يضيف إصداراً لتصميم عقد لا يشرف عليه');
insert into ids select 'design_sup', (public.save_doc_item(null, jsonb_build_object(
  'kind', 'design', 'project_id', pg_temp.pid('980'), 'title', 'مخطط تنفيذي', 'category', 'structural')) ->> 'item_id')::uuid;
select pg_temp.check((select v from ids where k = 'design_sup') is not null, 'رئيس القسم المشرف يضيف تصميماً لعقده');

-- ---------------------------------------------------------------- المراسلات
select pg_temp.as_user('k.qa@test.ly');
insert into ids select 'letter_in', (public.save_doc_item(null, jsonb_build_object(
  'kind', 'letter', 'project_id', pg_temp.pid('980'), 'title', 'طلب تمديد مدة', 'direction', 'in', 'party', 'شركة أ',
  'ref_no', 'IN-15', 'due_date', '2026-11-20', 'category', 'contract')) ->> 'item_id')::uuid;
insert into ids select 'letter_out', (public.save_doc_item(null, jsonb_build_object(
  'kind', 'letter', 'title', 'رد على طلب التمديد', 'direction', 'out', 'party', 'شركة أ',
  'reply_to', (select v from ids where k = 'letter_in'), 'status', 'closed')) ->> 'item_id')::uuid;
select pg_temp.check((select reply_to = (select v from ids where k = 'letter_in') and project_id is null and status = 'closed'
                        from doc_items where id = (select v from ids where k = 'letter_out')), 'مراسلة عامة مرتبطة بالمراسلة الواردة');
select pg_temp.expect_error($$select public.save_doc_item(null, '{"kind":"letter","title":"x","direction":"in","reply_to":"00000000-0000-0000-0000-000000000000"}')$$,
  'ربط بمراسلة غير موجودة');
select pg_temp.expect_error($$select public.save_doc_item((select v from ids where k = 'letter_in'), jsonb_build_object('title', 'x', 'direction', 'in', 'reply_to', (select v from ids where k = 'letter_in')))$$,
  'لا تُربط المراسلة بنفسها');

-- ---------------------------------------------------------------- التقارير اليومية
select pg_temp.as_user('k.headsup@test.ly');
insert into ids select 'rep', public.save_site_report(null, jsonb_build_object(
  'project_id', pg_temp.pid('980'), 'report_date', current_date, 'weather', 'dust', 'temp_c', 31, 'workers', 24,
  'equipment', 'حفار، قلاب', 'works_done', 'حفر خندق الصرف بطول 40 م', 'issues', 'تأخر توريد المواسير', 'progress_pct', 35));
select pg_temp.check((select weather = 'dust' and workers = 24 and progress_pct = 35 and reviewed_at is null
                        from site_reports where id = (select v from ids where k = 'rep')), 'رئيس القسم المشرف يرفع تقرير عقده');
select pg_temp.expect_error($$select public.save_site_report(null, jsonb_build_object('project_id', pg_temp.pid('980'), 'report_date', current_date, 'works_done', 'تكرار'))$$,
  'تقرير واحد للعقد في اليوم');
select pg_temp.expect_error($$select public.save_site_report(null, jsonb_build_object('project_id', pg_temp.pid('981'), 'report_date', current_date, 'works_done', 'أعمال'))$$,
  'لا يرفع تقريراً لعقد قسم آخر');
select pg_temp.expect_error($$select public.save_site_report(null, jsonb_build_object('project_id', pg_temp.pid('980'), 'report_date', current_date + 5, 'works_done', 'أعمال'))$$,
  'لا تقرير ليوم لم يأتِ');
select pg_temp.expect_error($$select public.save_site_report(null, jsonb_build_object('project_id', pg_temp.pid('980'), 'report_date', current_date - 1, 'works_done', ''))$$,
  'الأعمال المنفذة إلزامية');
select pg_temp.expect_error($$select public.save_site_report(null, jsonb_build_object('project_id', pg_temp.pid('980'), 'report_date', current_date - 1, 'works_done', 'أعمال', 'weather', 'snowstorm'))$$,
  'قيمة طقس غير معروفة');
select pg_temp.upload('report/' || (select v from ids where k = 'rep') || '/photo0001.jpg', 300000, 'image/jpeg');
select public.add_doc_file('report/' || (select v from ids where k = 'rep') || '/photo0001.jpg', 'الموقع صباحاً.jpg', 1600, 1200);
select pg_temp.check((select count(*) = 1 from doc_files where report_id = (select v from ids where k = 'rep')), 'صورة التقرير');

select pg_temp.as_user('k.staff@test.ly');
select public.save_site_report(null, jsonb_build_object('project_id', pg_temp.pid('981'), 'report_date', current_date - 1, 'works_done', 'تنظيف الواجهة'));
select pg_temp.check((select count(*) = 1 from site_reports where project_id = pg_temp.pid('981')), 'موظف مكتب المدير يرفع تقرير أي عقد');
select pg_temp.expect_error($$select public.review_site_report((select v from ids where k = 'rep'), true, 'اطلعت')$$, 'الاطلاع للمدير وحده');
select pg_temp.expect_error($$select public.delete_site_report((select v from ids where k = 'rep'))$$, 'لا يحذف تقرير غيره');

select pg_temp.as_user('k.contracts@test.ly');
select pg_temp.expect_error($$select public.save_site_report(null, jsonb_build_object('project_id', pg_temp.pid('980'), 'report_date', current_date - 2, 'works_done', 'أعمال'))$$,
  'مكتب العقود لا يرفع التقارير اليومية');

select pg_temp.as_user('director.new@test.ly', 'aal2');
select public.review_site_report((select v from ids where k = 'rep'), true, 'اطلعت – يُتابع التوريد');
select pg_temp.check((select reviewed_at is not null and review_note = 'اطلعت – يُتابع التوريد' from site_reports where id = (select v from ids where k = 'rep')),
  'المدير يسجّل اطلاعه وملاحظته');
select pg_temp.check((public.docs_storage_usage() ->> 'files')::int = 3 and (public.docs_storage_usage() ->> 'docs_bytes')::bigint = 1200000,
  'مؤشر المساحة');

-- ---------------------------------------------------------------- الدمج وفكّه
select pg_temp.as_user('k.headsup@test.ly');
select public.save_site_report(null, jsonb_build_object('project_id', pg_temp.pid('982'), 'report_date', current_date - 3, 'works_done', 'أعمال العقد المدمج'));
select public.save_doc_item(null, jsonb_build_object('kind', 'letter', 'project_id', pg_temp.pid('982'), 'title', 'مراسلة العقد المدمج', 'direction', 'out'));
select pg_temp.as_user('director.new@test.ly', 'aal2');
select public.merge_contracts(pg_temp.pid('980'), array[pg_temp.pid('982')]);
select pg_temp.check((select count(*) = 2 from site_reports where project_id = pg_temp.pid('980'))
                     and (select count(*) = 1 from doc_items where title = 'مراسلة العقد المدمج' and project_id = pg_temp.pid('980')
                            and origin_project = pg_temp.pid('982')),
  'مستندات العقد وتقاريره تنتقل مع الدمج');
select public.unmerge_contract(pg_temp.pid('982'));
select pg_temp.check((select count(*) = 1 from site_reports where project_id = pg_temp.pid('982'))
                     and (select project_id = pg_temp.pid('982') and origin_project is null from doc_items where title = 'مراسلة العقد المدمج'),
  'وتعود مع فكّ الدمج');

-- ---------------------------------------------------------------- الحذف
select pg_temp.expect_error($$select public.delete_doc_revision((select id from doc_revisions where item_id = (select v from ids where k = 'design_sup')))$$,
  'لا يُحذف الإصدار الوحيد');
select public.save_doc_revision(null, (select item_id from doc_revisions where id = (select v from ids where k = 'design')),
  '{"note":"بعد ملاحظات اللجنة"}');
select pg_temp.check(cardinality(public.delete_doc_revision((select v from ids where k = 'design'))) = 2,
  'حذف إصدار يعيد مسارات صوره لحذفها من الحاوية');
select pg_temp.check((select string_agg(rev_no::text, ',') = '2' from doc_revisions
                       where item_id in (select id from doc_items where title = 'واجهة المبنى التراثي')),
  'يبقى الإصدار 2 برقمه');
select pg_temp.check(cardinality(public.delete_doc_item((select item_id from doc_revisions where id = (select v from ids where k = 'boq_rev2')))) = 0,
  'المدير يحذف المقايسة بإصداراتها');
select pg_temp.check(cardinality(public.delete_site_report((select v from ids where k = 'rep'))) = 1, 'حذف التقرير يعيد مسار صورته');
select pg_temp.check((select count(*) = 0 from doc_files where report_id = (select v from ids where k = 'rep')), 'وتُزال سجلات ملفاته');
select pg_temp.check(cardinality(public.docs_orphan_paths()) = 0, 'لا ملفات يتيمة أقدم من ساعة');
select pg_temp.check((select count(*) >= 10 from audit_log where action like 'doc.%' or action like 'report.%'), 'كل العمليات مسجّلة في التدقيق');

reset role;
select 'DOCUMENTS & SUPERVISION TESTS PASSED';
