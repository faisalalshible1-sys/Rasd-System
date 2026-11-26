-- اختبارات الترحيل 35: ملف العقد ومرفقاته — التصنيفات، وربط قرار التكليف بالمهندس، وأنواع الملفات وحجمها،
-- والإصدارات، ومن يرى ومن يكتب ومن يحذف، والملفات المخزّنة، والتراجع الآمن.
-- يُشغَّل بعد تطبيق 20261126000035_contract_files.sql مرتين ثم التراجع عنه وإعادته، وبعد اختبارات الترحيل 34.
-- رفض التراجع مع وجود مرفقات يُختبر في run_tests.sh بعد هذا الملف.
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
create or replace function pg_temp.upload(p_name text, p_mime text, p_size bigint default 52000) returns void language sql as $$
  insert into storage.objects (bucket_id, name, owner, owner_id, metadata)
  values ('docs', p_name, auth.uid(), auth.uid()::text, jsonb_build_object('size', p_size, 'mimetype', p_mime))
$$;
create or replace function pg_temp.sees_object(p_name text) returns boolean language sql as $$
  select exists (select 1 from storage.objects where bucket_id = 'docs' and name = p_name)
$$;

update app_settings set value = 'false' where key in ('security.freeze', 'security.require_mfa_all');
update profiles set locked_until = null where email like 'k.%@test.ly' or email like 'u.%@test.ly' or email like 'head%@test.ly';
create temp table ids (k text primary key, v uuid);
grant all on ids to authenticated;
create or replace function pg_temp.id(p_k text) returns uuid language sql as $$ select v from ids where k = p_k $$;
grant execute on all functions in schema pg_temp to authenticated, anon;

-- ---------------------------------------------------------------- بيانات: عقد للإشراف وعقد للترميم
delete from doc_items where kind = 'attachment';
delete from projects where assign_no in ('T35-S', 'T35-R');
insert into projects (assign_no, name, owner, company, department) values ('T35-S', 'عقد ملفات الإشراف', 'المالك', 'شركة أ', 'supervision');
insert into projects (assign_no, name, owner, company, department) values ('T35-R', 'عقد ملفات الترميم', 'المالك', 'شركة ب', 'restoration');
insert into ids select 's', id from projects where assign_no = 'T35-S';
insert into ids select 'r', id from projects where assign_no = 'T35-R';

with e as (insert into contract_engineers (project_id, kind, name, assign_no, assigned_on, sort)
           values (pg_temp.id('s'), 'sup', 'م. سالم المشرف', 'ت-35', current_date, 1) returning id)
insert into ids select 'eng', id from e;
with e as (insert into contract_engineers (project_id, kind, name, assign_no, assigned_on, sort)
           values (pg_temp.id('r'), 'sup', 'م. خالد الترميم', 'ت-36', current_date, 1) returning id)
insert into ids select 'eng_r', id from e;

set role authenticated;
select pg_temp.as_user('k.contracts@test.ly');

-- ---------------------------------------------------------------- الإضافة والتصنيف
insert into ids select 'att', (public.save_doc_item(null, jsonb_build_object(
  'kind', 'attachment', 'project_id', pg_temp.id('s'), 'category', 'contract', 'title', 'نسخة العقد الموقّعة',
  'ref_no', 'ع/35', 'doc_date', '2026-11-20', 'notes', 'النسخة الأصلية')) ->> 'item_id')::uuid;
insert into ids select 'rev1', (select id from doc_revisions where item_id = pg_temp.id('att') and rev_no = 1);
select pg_temp.check((select kind = 'attachment' and category = 'contract' and status = 'active' and doc_date = '2026-11-20'
                        and ref_no = 'ع/35' from doc_items where id = pg_temp.id('att'))
                     and pg_temp.id('rev1') is not null,
                     'مكتب العقود يضيف مرفقاً مصنّفاً بوصفه وتاريخه ورقمه، ومعه إصداره الأول');
select pg_temp.expect_error($$select public.save_doc_item(null, '{"kind":"attachment","category":"contract","title":"بلا عقد"}'::jsonb)$$,
                            'المرفق بلا عقد');
select pg_temp.expect_error(format($$select public.save_doc_item(null, jsonb_build_object('kind','attachment','project_id',%L,'category','invoice','title','تصنيف غريب'))$$, pg_temp.id('s')),
                            'تصنيف خارج التصنيفات التسعة');
select pg_temp.expect_error(format($$select public.save_doc_item(null, jsonb_build_object('kind','attachment','project_id',%L,'category','contract','title','x'))$$, pg_temp.id('s')),
                            'مرفق بلا وصف');

-- قرار التكليف مربوط بالمهندس نفسه
insert into ids select 'dec', (public.save_doc_item(null, jsonb_build_object(
  'kind', 'attachment', 'project_id', pg_temp.id('s'), 'category', 'assignment', 'title', 'قرار تكليف المهندس المشرف',
  'engineer_id', pg_temp.id('eng'))) ->> 'item_id')::uuid;
select pg_temp.check((select engineer_id = pg_temp.id('eng') from doc_items where id = pg_temp.id('dec')), 'قرار التكليف يُربط بالمهندس المكلَّف');
select pg_temp.expect_error(format($$select public.save_doc_item(null, jsonb_build_object('kind','attachment','project_id',%L,'category','assignment','title','قرار لمهندس عقد آخر','engineer_id',%L))$$,
                                   pg_temp.id('s'), pg_temp.id('eng_r')),
                            'ربط قرار التكليف بمهندس من عقد آخر');
insert into ids select 'drw', (public.save_doc_item(null, jsonb_build_object(
  'kind', 'attachment', 'project_id', pg_temp.id('s'), 'category', 'drawings', 'title', 'مخطط الموقع العام',
  'engineer_id', pg_temp.id('eng'))) ->> 'item_id')::uuid;
select pg_temp.check((select engineer_id is null from doc_items where id = pg_temp.id('drw')), 'ولا يُربط مهندس بغير قرارات التكليف');
reset role;
delete from contract_engineers where id = pg_temp.id('eng_r');
set role authenticated;

-- ---------------------------------------------------------------- أنواع الملفات وحجمها
select pg_temp.check(public.can_upload_doc_path('doc/' || pg_temp.id('rev1') || '/Abcdefgh12345678.dwg')
                     and public.can_upload_doc_path('doc/' || pg_temp.id('rev1') || '/Abcdefgh12345678.xlsx')
                     and public.can_upload_doc_path('doc/' || pg_temp.id('rev1') || '/Abcdefgh12345678.docx')
                     and public.can_upload_doc_path('doc/' || pg_temp.id('rev1') || '/Abcdefgh12345678.zip')
                     and public.can_upload_doc_path('doc/' || pg_temp.id('rev1') || '/Abcdefgh12345678.kmz'),
                     'المرفق يقبل DWG وExcel وWord والمضغوط وKMZ');
select pg_temp.check(not public.can_upload_doc_path('doc/' || pg_temp.id('rev1') || '/Abcdefgh12345678.exe')
                     and not public.can_upload_doc_path('doc/' || pg_temp.id('rev1') || '/Abcdefgh12345678.mp4'),
                     'ولا يقبل الملفات التنفيذية ولا الفيديو');
select pg_temp.upload('doc/' || pg_temp.id('rev1') || '/Contract35signed01.pdf', 'application/pdf');
select from public.add_doc_file('doc/' || pg_temp.id('rev1') || '/Contract35signed01.pdf', 'العقد.pdf');
select pg_temp.upload('doc/' || pg_temp.id('rev1') || '/Contract35drawing1.dwg', 'image/vnd.dwg', 31457280);
select from public.add_doc_file('doc/' || pg_temp.id('rev1') || '/Contract35drawing1.dwg', 'المخطط.dwg');
select pg_temp.upload('doc/' || pg_temp.id('rev1') || '/Contract35octet001.xlsx', 'application/octet-stream');
select from public.add_doc_file('doc/' || pg_temp.id('rev1') || '/Contract35octet001.xlsx', 'الكميات.xlsx');
select pg_temp.check((select count(*) = 3 and bool_and(mime = public.attachment_mime(substring(path from '\.([a-z0-9]+)$')))
                        and max(size_bytes) = 31457280 from doc_files where revision_id = pg_temp.id('rev1')),
                     'ملف PDF وملف DWG بحجم 30 ميغابايت وملف Excel، ونوع كل ملف من امتداده');
select pg_temp.upload('doc/' || pg_temp.id('rev1') || '/Contract35spoof001.docx', 'image/png');
select pg_temp.expect_error(format($$select public.add_doc_file(%L, 'خطاب.docx')$$, 'doc/' || pg_temp.id('rev1') || '/Contract35spoof001.docx'),
                            'نوع لا يطابق امتداده');
select pg_temp.upload('doc/' || pg_temp.id('rev1') || '/Contract35toobig01.pdf', 'application/pdf', 52428801);
select pg_temp.expect_error(format($$select public.add_doc_file(%L, 'كبير.pdf')$$, 'doc/' || pg_temp.id('rev1') || '/Contract35toobig01.pdf'),
                            'ملف أكبر من 50 ميغابايت');

-- ---------------------------------------------------------------- الاستبدال يصنع إصداراً ويحفظ السابق
insert into ids select 'rev2', public.save_doc_revision(null, pg_temp.id('att'), '{"rev_date":"2026-11-25","note":"نسخة معدلة بعد الملحق"}'::jsonb);
select pg_temp.upload('doc/' || pg_temp.id('rev2') || '/Contract35signed02.pdf', 'application/pdf');
select from public.add_doc_file('doc/' || pg_temp.id('rev2') || '/Contract35signed02.pdf', 'العقد المعدل.pdf');
select pg_temp.check((select count(*) = 2 from doc_revisions where item_id = pg_temp.id('att'))
                     and (select count(*) = 3 from doc_files where revision_id = pg_temp.id('rev1'))
                     and (select count(*) = 1 from doc_files where revision_id = pg_temp.id('rev2')),
                     'الإصدار الجديد له ملفه، وملفات الإصدار السابق باقية');
select pg_temp.expect_error(format($$select public.delete_doc_item(%L)$$, pg_temp.id('att')), 'مكتب العقود لا يحذف المرفق');

-- ---------------------------------------------------------------- من يرى ومن يكتب
select pg_temp.as_user('k.headsup@test.ly');
select pg_temp.check((select count(*) from doc_items where kind = 'attachment' and project_id = pg_temp.id('s')) = 3
                     and pg_temp.sees_object('doc/' || pg_temp.id('rev1') || '/Contract35drawing1.dwg'),
                     'القسم المشرف يرى ملف عقده ومرفقاته المخزّنة');
insert into ids select 'handover', (public.save_doc_item(null, jsonb_build_object(
  'kind', 'attachment', 'project_id', pg_temp.id('s'), 'category', 'handover', 'title', 'محضر تسليم الموقع')) ->> 'item_id')::uuid;
select pg_temp.check(pg_temp.id('handover') is not null, 'ويضيف إليه');
select pg_temp.expect_error(format($$select public.save_doc_item(null, jsonb_build_object('kind','attachment','project_id',%L,'category','other','title','مرفق لعقد غيره'))$$, pg_temp.id('r')),
                            'ولا يضيف إلى عقد قسم آخر');

select pg_temp.as_user('k.headtech@test.ly');
select pg_temp.check((select count(*) from doc_items where kind = 'attachment') = 0
                     and (select count(*) from doc_revisions where item_id = pg_temp.id('att')) = 0
                     and not pg_temp.sees_object('doc/' || pg_temp.id('rev1') || '/Contract35signed01.pdf')
                     and (select count(*) from doc_items where kind <> 'attachment') > 0,
                     'الشؤون الفنية ترى مستنداتها ولا ترى ملفات العقود ولا إصداراتها ولا ملفاتها');
select pg_temp.expect_error(format($$select public.save_doc_item(null, jsonb_build_object('kind','attachment','project_id',%L,'category','boq','title','مقايسة في ملف العقد'))$$, pg_temp.id('s')),
                            'ولا تضيف إلى ملف العقد');
-- مستندات الشؤون الفنية كما كانت: PDF وصور فقط
insert into ids select 'letter_rev', (public.save_doc_item(null, jsonb_build_object('kind', 'letter', 'title', 'مراسلة اختبار 35', 'direction', 'in')) ->> 'revision_id')::uuid;
select pg_temp.check(public.can_upload_doc_path('doc/' || pg_temp.id('letter_rev') || '/Letter35file0001.pdf')
                     and not public.can_upload_doc_path('doc/' || pg_temp.id('letter_rev') || '/Letter35file0001.docx'),
                     'والمراسلات تبقى PDF والصور كما كانت');

select pg_temp.as_user('headrest@test.ly');
select pg_temp.check((select count(*) from doc_items where kind = 'attachment') = 0, 'قسم الترميم لا يرى ملفات عقود الإشراف');

select pg_temp.as_user('auditor@test.ly', 'aal2');
select pg_temp.check((select count(*) from doc_items where kind = 'attachment') = 0, 'ولا CISO');

select pg_temp.as_user('k.staff@test.ly');
select pg_temp.check((select count(*) from doc_items where kind = 'attachment') = 4, 'ومكتب المدير يرى الملفات كلها');

-- ---------------------------------------------------------------- التجميد يمنع الإضافة
reset role;
update app_settings set value = 'true' where key = 'security.freeze';
set role authenticated;
select pg_temp.as_user('k.contracts@test.ly');
select pg_temp.expect_error(format($$select public.save_doc_item(null, jsonb_build_object('kind','attachment','project_id',%L,'category','other','title','أثناء التجميد'))$$, pg_temp.id('s')),
                            'لا إضافة أثناء تجميد الكتابة');
reset role;
update app_settings set value = 'false' where key = 'security.freeze';

-- ---------------------------------------------------------------- الحذف للمدير وحده ويبقى أثره
set role authenticated;
select pg_temp.as_user('director.new@test.ly', 'aal2');
create temp table del_paths as select public.delete_doc_item(pg_temp.id('att')) as paths;
select pg_temp.check((select array_length(paths, 1) = 4 from del_paths)
                     and not exists (select 1 from doc_items where id = pg_temp.id('att'))
                     and not exists (select 1 from doc_revisions where item_id = pg_temp.id('att'))
                     and exists (select 1 from audit_log where action = 'doc.delete' and detail ->> 'item_id' = pg_temp.id('att')::text),
                     'المدير يحذف المرفق بإصداراته وتعود مسارات ملفاته الأربعة، ويبقى الحذف في سجل التدقيق');

-- ---------------------------------------------------------------- التنظيف
reset role;
delete from doc_items where kind = 'attachment' or title = 'مراسلة اختبار 35';
delete from storage.objects where name like '%Contract35%' or name like '%Letter35%';
delete from projects where assign_no in ('T35-S', 'T35-R');
select pg_temp.check(true, 'اكتملت اختبارات ملف العقد');
