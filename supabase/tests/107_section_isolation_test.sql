-- اختبارات الترحيل 34: عزل الأقسام — كل قسم يطّلع على عمله وحده في قاعدة البيانات نفسها (RLS)، مع أساسيات العقود للربط،
-- والنماذج المسندة، وتشديد الكتابة. يُشغَّل بعد تطبيق 20261123000034_section_isolation.sql مرتين، وبعد اختبارات الترحيل 33.
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
-- العدّ الكامل (دون RLS) للمقارنة
create or replace function pg_temp.total(p_sql text) returns bigint language plpgsql security definer as $$
declare n bigint;
begin
  execute p_sql into n;
  return n;
end $$;
create or replace function pg_temp.upload(p_bucket text, p_name text) returns void language sql as $$
  insert into storage.objects (bucket_id, name, owner, owner_id, metadata)
  values (p_bucket, p_name, auth.uid(), auth.uid()::text, jsonb_build_object('size', 52000, 'mimetype', 'application/pdf'))
$$;
create or replace function pg_temp.epath(p_token text) returns text language sql security definer as $$
  select path from public.export_files where token = p_token
$$;
create or replace function pg_temp.sees_object(p_bucket text, p_name text) returns boolean language sql as $$
  select exists (select 1 from storage.objects where bucket_id = p_bucket and name = p_name)
$$;

update app_settings set value = 'false' where key in ('security.freeze', 'security.require_mfa_all');
update app_settings set value = jsonb_set(value, '{ideas_for_all}', 'true') where key = 'ui.features';
update profiles set locked_until = null where email like 'k.%@test.ly' or email like 'u.%@test.ly' or email like 'head%@test.ly';
create temp table ids (k text primary key, v uuid);
grant all on ids to authenticated;
create or replace function pg_temp.id(p_k text) returns uuid language sql as $$ select v from ids where k = p_k $$;
grant execute on all functions in schema pg_temp to authenticated, anon;

-- ---------------------------------------------------------------- بيانات: عقد للإشراف وعقد للترميم
delete from projects where assign_no in ('T34-M', 'T34-S', 'T34-R');
delete from unit_records where title like '% عزل الأقسام';
insert into projects (assign_no, name, owner, company, department) values ('T34-S', 'عقد عزل الإشراف', 'المالك', 'شركة الإشراف', 'supervision');
insert into projects (assign_no, name, owner, company, department) values ('T34-R', 'عقد عزل الترميم', 'المالك', 'شركة الترميم', 'restoration');
insert into ids select 's', id from projects where assign_no = 'T34-S';
insert into ids select 'r', id from projects where assign_no = 'T34-R';
insert into project_forms (project_id, form_key, status) values
  (pg_temp.id('s'), 'f01', 'done'), (pg_temp.id('s'), 'f20', 'wip'), (pg_temp.id('s'), 'f04', 'todo'), (pg_temp.id('s'), 'f05', 'todo'),
  (pg_temp.id('r'), 'f20', 'todo'), (pg_temp.id('r'), 'f06', 'todo'), (pg_temp.id('r'), 'f04', 'done')
on conflict do nothing;
insert into quality_notes (project_id, body) values (pg_temp.id('s'), 'ملاحظة جودة على عقد الإشراف'), (pg_temp.id('r'), 'ملاحظة جودة على عقد الترميم');
insert into unit_records (unit, kind, title, status) values
  ('heritage', 'heritage_building', 'مبنى عزل الأقسام', 'registered'),
  ('safety', 'safety_incident', 'حادث عزل الأقسام', 'open'),
  ('planning', 'plan', 'خطة عزل الأقسام', 'draft'),
  ('quality_assurance', 'qa_audit', 'تدقيق عزل الأقسام', 'planned'),
  ('technical', 'material_approval', 'مادة عزل الأقسام', 'under_review');

-- ---------------------------------------------------------------- نطاق كل دور
set role authenticated;
select pg_temp.as_user('k.staff@test.ly');
select pg_temp.check(public.my_sections() @> array['cycle', 'risks', 'swot', 'docs', 'supervision', 'heritage', 'planning_qa', 'safety', 'acceptance',
                                                   'chat', 'manual', 'print'] and not ('security' = any (public.my_sections())),
                     'موظفو مكتب المدير: كل الأقسام للمتابعة (عدا الأمن السيبراني)');
select pg_temp.check((select count(*) from projects) = pg_temp.total('select count(*) from projects where merged_into is null')
                     and (select count(*) from unit_records) = pg_temp.total('select count(*) from unit_records')
                     and (select count(*) from project_forms) = pg_temp.total('select count(*) from project_forms'),
                     'ويرون كل العقود والنماذج وسجلات الوحدات');

select pg_temp.as_user('k.headtech@test.ly');
select pg_temp.check(public.my_sections() = array['chat', 'docs', 'manual', 'print'], 'رئيس الشؤون الفنية: قسمه وحده والأدوات المشتركة');
select pg_temp.check((select count(*) from projects) = 0, 'ولا يرى تفاصيل أي عقد');
select pg_temp.check(jsonb_array_length(public.project_refs()) = pg_temp.total('select count(*) from projects where merged_into is null')
                     and not (public.project_refs() -> 0 ? 'contract_value') and (public.project_refs() -> 0 ? 'company'),
                     'بل أساسيات كل العقود للربط، دون القيم المالية');
select pg_temp.check((select bool_and(form_key in ('f20', 'f19')) and count(*) > 0 from project_forms)
                     and (select count(*) from project_forms where project_id = pg_temp.id('s')) = 1,
                     'ونماذجه المسندة وحدها (نطاق وطريقة عمل والمقايسة التقديرية) في كل العقود');
select pg_temp.check((select bool_and(unit = 'technical') and count(*) > 0 from unit_records), 'وسجلات وحدته (اعتماد المواد) وحدها');
select pg_temp.check((select count(*) from doc_items) = pg_temp.total('select count(*) from doc_items')
                     and (select count(*) from price_items) > 0 and (select count(*) from pm_plans) = pg_temp.total('select count(*) from pm_plans'),
                     'ويرى كل مستندات قسمه ولائحة الأسعار والبرامج الزمنية');
select pg_temp.check((select count(*) from contract_extracts) + (select count(*) from extract_payments) + (select count(*) from quality_notes)
                     + (select count(*) from swot_factors) + (select count(*) from pm_progress) + (select count(*) from site_reports)
                     + (select count(*) from contract_variations) = 0,
                     'ولا مالية العقود ولا SWOT ولا التقدم ولا تقارير الإشراف ولا ملاحظات الجودة');
select pg_temp.check((select count(*) from risks) = 0 and (select count(*) from risk_reviews) = 0, 'ولا سجل المخاطر');
select pg_temp.check((select count(*) > 0 and bool_and(department in ('قسم الشؤون الفنية', 'الشؤون الفنية', 'جميع الأقسام')) from swot_actions),
                     'وإجراءات خطة SWOT المسندة إلى قسمه وحدها');
select pg_temp.check((select count(*) from audit_log where actor is distinct from auth.uid()) = 0, 'وسجل أفعاله وحده من سجل التدقيق');
select pg_temp.check(public.doc_can_edit('letter', null) and public.doc_can_edit('boq', pg_temp.id('s')), 'ويكتب مستندات قسمه كما كان');

select pg_temp.as_user('k.headsup@test.ly');
select pg_temp.check(public.my_sections() = array['chat', 'manual', 'print', 'supervision'], 'رئيس الإشراف: الإشراف وحده');
select pg_temp.check((select bool_and(department = 'supervision') and count(*) > 0 from projects)
                     and exists (select 1 from projects where id = pg_temp.id('s'))
                     and not exists (select 1 from projects where id = pg_temp.id('r')),
                     'يرى تفاصيل العقود التي يشرف عليها قسمه وحدها');
select pg_temp.check((select count(*) from project_forms where project_id = pg_temp.id('s')) = 4
                     and (select count(*) from project_forms where project_id = pg_temp.id('r')) = 0,
                     'وكل نماذج عقوده، ولا شيء من نماذج غيرها');
select pg_temp.check((select count(*) from quality_notes where project_id = pg_temp.id('s')) = 1
                     and (select count(*) from quality_notes where project_id = pg_temp.id('r')) = 0, 'وملاحظات الجودة على عقوده وحدها');
select pg_temp.check((select count(*) from unit_records) = 0 and (select count(*) from price_items) = 0
                     and (select count(*) from swot_factors) = 0, 'ولا سجلات الوحدات ولا لائحة الأسعار ولا SWOT');
select pg_temp.check(not exists (select 1 from doc_items where project_id is null or project_id <> all (public.my_supervised())),
                     'ومن مستندات الشؤون الفنية ما يخص عقوده فقط');
select pg_temp.check(not public.doc_can_edit('letter', null), 'ولم يعد يكتب في مراسلات الشؤون الفنية من خارجها');
select from public.save_pm_progress(null, jsonb_build_object('project_id', pg_temp.id('s'), 'measured_on', current_date, 'planned', 0.2, 'actual', 0.1));
select pg_temp.check((select count(*) = 1 from pm_progress where project_id = pg_temp.id('s')), 'يسجّل قياس التقدم لعقد يشرف عليه');
select pg_temp.expect_error($$select public.save_pm_progress(null, jsonb_build_object('project_id', pg_temp.id('r'), 'measured_on', current_date, 'planned', 0.2, 'actual', 0.1))$$,
                            'ولا يسجّل على عقد قسم آخر ولو عرف رقمه');

select pg_temp.as_user('headrest@test.ly');
select pg_temp.check(public.my_sections() = array['chat', 'heritage', 'manual', 'print', 'supervision'], 'رئيس الترميم: الترميم والإشراف على عقود قسمه');
select pg_temp.check(exists (select 1 from projects where id = pg_temp.id('r')) and not exists (select 1 from projects where id = pg_temp.id('s'))
                     and (select bool_and(unit = 'heritage') and count(*) > 0 from unit_records), 'عقود الترميم وحدها وسجلات المباني التاريخية وحدها');

select pg_temp.as_user('k.qa@test.ly');
select pg_temp.check(public.my_sections() = array['chat', 'manual', 'planning_qa', 'print'], 'التخطيط وضمان الجودة: مكتبه وحده');
select pg_temp.check((select bool_and(unit in ('planning', 'quality_assurance', 'follow_up')) and count(*) >= 2 from unit_records)
                     and (select bool_and(form_key = 'f06') and count(*) > 0 from project_forms)
                     and (select count(*) from quality_notes) = pg_temp.total('select count(*) from quality_notes')
                     and (select count(*) from projects) = 0,
                     'وحداته الثلاث، ونموذج «تكليف مهندس متابعة» في كل العقود، وكل ملاحظات الجودة التي يكتبها');

select pg_temp.as_user('u.safety@test.ly');
select pg_temp.check(public.my_sections() = array['chat', 'cycle', 'manual', 'print', 'safety'], 'عضو وحدة السلامة بدور العقود: الدورة ووحدته');
select pg_temp.check((select bool_and(unit = 'safety') and count(*) > 0 from unit_records), 'ومن سجلات الوحدات سجلات وحدته وحدها');

select pg_temp.as_user('u.qc@test.ly');
select pg_temp.check((select count(*) from unit_records where unit = 'receiving') = 0
                     and (select count(*) from unit_records where unit = 'quality_control') = pg_temp.total($q$select count(*) from unit_records where unit = 'quality_control'$q$),
                     'عضو وحدة ضبط الجودة لا يرى وحدة الاستلام في القسم نفسه');

select pg_temp.as_user('k.contracts@test.ly');
select pg_temp.check(public.my_sections() = array['chat', 'cycle', 'manual', 'print'], 'مكتب العقود: الدورة المستندية');
select pg_temp.check((select count(*) from projects) = pg_temp.total('select count(*) from projects where merged_into is null')
                     and (select count(*) from contract_extracts) = pg_temp.total('select count(*) from contract_extracts')
                     and (select count(*) from unit_records) = 0 and (select count(*) from doc_items) = 0 and (select count(*) from price_items) = 0,
                     'كل العقود بماليتها، ولا الشؤون الفنية ولا الوحدات');

select pg_temp.as_user('auditor@test.ly', 'aal2');
select pg_temp.check(public.my_sections() = array['chat', 'manual', 'print', 'security'], 'CISO: الأمن السيبراني والأدوات المشتركة');
select pg_temp.check((select count(*) from projects) + (select count(*) from unit_records) + (select count(*) from doc_items)
                     + (select count(*) from risks) + (select count(*) from project_forms) = 0 and public.project_refs() = '[]'::jsonb,
                     'ولا يرى بيانات الأقسام');
select pg_temp.check((select count(*) from audit_log) = pg_temp.total('select count(*) from audit_log'), 'ويرى سجل التدقيق كاملاً');

-- ---------------------------------------------------------------- دوال القراءة بحدود القسم
select pg_temp.as_user('k.headtech@test.ly');
select pg_temp.check((select count(*) from public.finance_history(null, 2000)) = 0, 'سجل المالية لا يُقرأ من خارج العقود');
reset role;
insert into projects (assign_no, name, owner, company, department) values ('T34-M', 'عقد مدمج للعزل', 'المالك', 'شركة الدمج', 'supervision');
select from set_config('app.trusted', 'on', false);
update projects set merged_into = pg_temp.id('s'), merged_at = now() where assign_no = 'T34-M';
select from set_config('app.trusted', '', false);
set role authenticated;
select pg_temp.check((select count(*) from public.merged_sources(pg_temp.id('s'))) = 0, 'ولا العقود المدمجة في عقد لا يراه');
select pg_temp.as_user('k.headsup@test.ly');
select pg_temp.check((select count(*) from public.merged_sources(pg_temp.id('s'))) = 1, 'ويراها القسم المشرف على العقد');
select pg_temp.as_user('k.headtech@test.ly');
select pg_temp.check(public.pm_plan_preview(pg_temp.id('s'), 60) is not null, 'ومعاينة البرنامج الزمني لقسمه');
select pg_temp.as_user('k.headsup@test.ly');
select pg_temp.expect_error($$select public.pm_plan_preview(pg_temp.id('s'), 60)$$, 'معاينة البرنامج الزمني للشؤون الفنية وحدها');
select pg_temp.as_user('k.contracts@test.ly');
select pg_temp.check((select count(*) from public.finance_history(null, 2000) h where h ->> 'action' like 'finance.%')
                       = pg_temp.total($q$select count(*) from audit_log where action like 'finance.%' and project_id is not null$q$),
                     'ومكتب العقود يقرأ سجل المالية كاملاً');

-- ---------------------------------------------------------------- الأفكار
select pg_temp.as_user('k.headtech@test.ly');
insert into ids select 'idea_docs', public.submit_idea('فكرة لقسم الشؤون الفنية', 'تفصيل', 'feature', 'normal', 'docs', 60, 'المقايسات');
insert into ids select 'idea_gen', public.submit_idea('فكرة عامة من الشؤون الفنية', '', 'feature', 'normal');
select pg_temp.expect_error($$select public.submit_idea('فكرة لقسم آخر', '', 'feature', 'normal', 'cycle')$$, 'لا تُرسل فكرة إلى قسم لا يراه');
select pg_temp.as_user('k.headsup@test.ly');
select pg_temp.check(not exists (select 1 from ideas where id in (pg_temp.id('idea_docs'), pg_temp.id('idea_gen'))), 'أفكار قسم آخر وأفكار غيره العامة لا تظهر له');
select pg_temp.as_user('k.staff@test.ly');
select pg_temp.check((select count(*) = 2 from ideas where id in (pg_temp.id('idea_docs'), pg_temp.id('idea_gen'))), 'ومكتب المدير يرى الأفكار كلها');

-- ---------------------------------------------------------------- الترجمة الآلية للبرنامج المعتمد تعمل أياً كان من فتح المنظومة
reset role;
update pm_auto_runs set ran_at = now() - interval '2 hours';
set role authenticated;
select pg_temp.as_user('k.headtech@test.ly');
select pg_temp.check(public.pm_refresh_auto() >= 1, 'تحديث المخاطر الآلي يعمل من حساب قسم لا يرى المخاطر');
select pg_temp.expect_error($$select public.pm_sync_auto(pg_temp.id('s'))$$, 'ودالة الترجمة نفسها غير متاحة للمستخدمين');

-- ---------------------------------------------------------------- النسخ المحفوظة (رمز QR) بحسب قسم المصدر
select pg_temp.as_user('k.staff@test.ly');
select pg_temp.upload('exports', auth.uid() || '/Is34Docs0000000000001.pdf');
select from public.register_export_file('Is34Docs0000000000001', jsonb_build_object('title', 'سجل المقايسات', 'source', 'docs:boq', 'sha256', repeat('cd', 32)));
select pg_temp.upload('exports', auth.uid() || '/Is34Cycle000000000001.pdf');
select from public.register_export_file('Is34Cycle000000000001', jsonb_build_object('title', 'سجل العقود', 'source', 'cycle:contracts', 'sha256', repeat('ef', 32)));
select pg_temp.as_user('k.headtech@test.ly');
select pg_temp.check((public.open_export_file('Is34Docs0000000000001') ->> 'ok')::boolean
                     and pg_temp.sees_object('exports', pg_temp.epath('Is34Docs0000000000001'))
                     and not pg_temp.sees_object('exports', pg_temp.epath('Is34Cycle000000000001')),
                     'نسخة من قسمه تُفتح له، وملفها المخزّن يُقرأ');
select pg_temp.check(not (public.open_export_file('Is34Cycle000000000001') ->> 'ok')::boolean
                     and (public.open_export_file('Is34Cycle000000000001') ->> 'reason') = 'denied',
                     'ونسخة سجل العقود تُرفض له وتُسجَّل');
select pg_temp.as_user('k.contracts@test.ly');
select pg_temp.check((public.open_export_file('Is34Cycle000000000001') ->> 'ok')::boolean
                     and not (public.open_export_file('Is34Docs0000000000001') ->> 'ok')::boolean,
                     'ومكتب العقود عكسه');

-- ---------------------------------------------------------------- ملفات المستندات المخزّنة
select pg_temp.as_user('k.headtech@test.ly');
insert into ids select 'letter', (public.save_doc_item(null, jsonb_build_object(
  'kind', 'letter', 'project_id', pg_temp.id('r'), 'title', 'مراسلة عقد الترميم', 'direction', 'in', 'doc_date', current_date)) ->> 'item_id')::uuid;
insert into ids select 'rev', (select id from doc_revisions where item_id = pg_temp.id('letter') order by rev_no limit 1);
select pg_temp.upload('docs', 'doc/' || pg_temp.id('rev') || '/isolation34file.pdf');
reset role;
insert into doc_files (revision_id, path, name, mime, size_bytes) values
  (pg_temp.id('rev'), 'doc/' || pg_temp.id('rev') || '/isolation34file.pdf', 'مراسلة.pdf', 'application/pdf', 52000);
set role authenticated;
select pg_temp.as_user('k.headtech@test.ly');
select pg_temp.check(pg_temp.sees_object('docs', 'doc/' || pg_temp.id('rev') || '/isolation34file.pdf'), 'ملف المراسلة يقرؤه قسمها');
select pg_temp.as_user('headrest@test.ly');
select pg_temp.check(pg_temp.sees_object('docs', 'doc/' || pg_temp.id('rev') || '/isolation34file.pdf')
                     and exists (select 1 from doc_items where id = pg_temp.id('letter')), 'والقسم المشرف على العقد');
select pg_temp.as_user('k.headsup@test.ly');
select pg_temp.check(not pg_temp.sees_object('docs', 'doc/' || pg_temp.id('rev') || '/isolation34file.pdf')
                     and not exists (select 1 from doc_items where id = pg_temp.id('letter')), 'ولا يقرؤه قسم آخر');
select pg_temp.as_user('auditor@test.ly', 'aal2');
select pg_temp.check(not pg_temp.sees_object('docs', 'doc/' || pg_temp.id('rev') || '/isolation34file.pdf'), 'ولا CISO');
reset role;
insert into storage.objects (bucket_id, name, metadata) values ('docs', 'manual/isolation34-manual.pdf', '{"size": 1000}');
set role authenticated;
select pg_temp.check(pg_temp.sees_object('docs', 'manual/isolation34-manual.pdf'), 'ونسخة الدليل PDF يقرؤها الجميع');
select pg_temp.as_user('k.headsup@test.ly');
select pg_temp.check(pg_temp.sees_object('docs', 'manual/isolation34-manual.pdf'), 'ومنهم رئيس الإشراف');

-- ---------------------------------------------------------------- التنظيف
reset role;
delete from doc_files where path like '%isolation34file%';
delete from storage.objects where name like '%isolation34file%' or name like '%Is34%' or name like '%isolation34-manual%';
delete from export_files where token like 'Is34%';
delete from pm_progress where project_id in (pg_temp.id('s'), pg_temp.id('r'));
delete from ideas where id in (pg_temp.id('idea_docs'), pg_temp.id('idea_gen'));
select pg_temp.check(true, 'اكتملت اختبارات عزل الأقسام');
