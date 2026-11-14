-- اختبارات الترحيل 21: أقسام الوحدات (الترميم والمباني التاريخية، التخطيط وضمان الجودة، السلامة المهنية، المطابقة والاستلام).
-- يُشغَّل بعد تطبيق 20261114000021_unit_sections.sql مرتين.
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
create or replace function pg_temp.uid(p_email text) returns uuid language sql security definer as $$
  select id from public.profiles where email = p_email
$$;
create or replace function pg_temp.upload(p_path text, p_size bigint default 1000, p_mime text default 'application/pdf') returns void language plpgsql as $$
begin
  insert into storage.objects (bucket_id, name, owner, owner_id, metadata)
  values ('docs', p_path, auth.uid(), auth.uid()::text, jsonb_build_object('size', p_size, 'mimetype', p_mime));
end $$;
grant execute on all functions in schema pg_temp to authenticated, anon;

update app_settings set value = 'false' where key in ('security.freeze', 'security.require_mfa_all');
update app_settings set value = 'true' where key = 'security.signups_open';
create temp table ids (k text primary key, v uuid);
grant all on ids to authenticated;

insert into auth.users (email, raw_user_meta_data) values
  ('u.safety@test.ly',     '{"full_name":"عضو السلامة"}'),
  ('u.safetyhead@test.ly', '{"full_name":"رئيس مكتب السلامة"}'),
  ('u.qc@test.ly',         '{"full_name":"عضو ضبط الجودة"}'),
  ('u.heritage@test.ly',   '{"full_name":"عضو المباني التاريخية"}');

-- ---------------------------------------------------------------- البنية
select pg_temp.check((select string_agg(key || ':' || section, ',' order by sort) from org_units) =
  'heritage:heritage,planning:planning_qa,quality_assurance:planning_qa,follow_up:planning_qa,safety:safety,receiving:acceptance,quality_control:acceptance',
  'الوحدات السبع في أقسامها الأربعة');
select pg_temp.check((select bool_and(relrowsecurity) from pg_class where oid in ('public.org_units'::regclass, 'public.unit_records'::regclass)),
  'RLS مفعّل على جدولي الوحدات');
select pg_temp.check(not has_table_privilege('authenticated', 'public.unit_records', 'INSERT')
                     and not has_table_privilege('authenticated', 'public.unit_records', 'UPDATE')
                     and not has_table_privilege('anon', 'public.unit_records', 'SELECT')
                     and not has_column_privilege('authenticated', 'public.profiles', 'unit', 'UPDATE'),
  'الكتابة عبر الدوال وحدها، ولا يغيّر المستخدم وحدته');
select pg_temp.check((select count(*) = 1 from pg_publication_tables where pubname = 'supabase_realtime' and tablename = 'unit_records'),
  'التحديث اللحظي لسجلات الوحدات');
select pg_temp.check((select count(*) = 13 from unnest(array['heritage_building', 'heritage_assessment', 'plan', 'qa_audit', 'ncr',
                        'followup_task', 'safety_inspection', 'safety_incident', 'safety_violation', 'handover', 'punch_item',
                        'qc_test', 'material_approval']) k where public.unit_kind_spec(k) is not null)
                     and public.unit_kind_spec('unknown') is null,
  'ثلاثة عشر نوعاً من السجلات');

-- ---------------------------------------------------------------- الحسابات والإسناد
-- الوحدة تُضاف فوق الدور؛ لاختبار أعضاء الوحدات نفعّلهم بدور «مكتب العقود» الذي لا يكتب في الوحدات بذاته.
set role authenticated;
select pg_temp.as_user('director.new@test.ly', 'aal2');
select public.set_user_access(pg_temp.uid('u.safety@test.ly'), 'contracts', null, true);
select public.set_user_access(pg_temp.uid('u.safetyhead@test.ly'), 'contracts', null, true);
select public.set_user_access(pg_temp.uid('u.qc@test.ly'), 'contracts', null, true);
select public.set_user_access(pg_temp.uid('u.heritage@test.ly'), 'contracts', null, true);
insert into projects (assign_no, name, owner, company, department) values ('990', 'عقد الوحدات', 'المالك', 'شركة د', 'supervision');
insert into projects (assign_no, name, owner, company, department) values ('991', 'عقد وحدات للدمج', 'المالك', 'شركة هـ', 'supervision');

select pg_temp.check(public.unit_can_edit('safety') and public.unit_is_head('heritage'), 'المدير يكتب في كل الوحدات ويرأسها');
select pg_temp.as_user('u.safety@test.ly');
select pg_temp.check(not public.unit_can_edit('safety'), 'قبل الإسناد: لا يكتب في وحدة السلامة');
select pg_temp.expect_error($$select public.set_user_unit(pg_temp.uid('u.safety@test.ly'), 'safety', false)$$, 'المستخدم لا يُسند نفسه');
select pg_temp.expect_error($$update profiles set unit = 'safety' where id = auth.uid()$$, 'ولا يغيّر وحدته مباشرة');

select pg_temp.as_user('k.staff@test.ly');
select pg_temp.expect_error($$select public.set_user_unit(pg_temp.uid('u.safety@test.ly'), 'safety', false)$$, 'موظف المكتب لا يُسند المستخدمين');

select pg_temp.as_user('director.new@test.ly', 'aal2');
select public.set_user_unit(pg_temp.uid('u.safety@test.ly'), 'safety', false);
select public.set_user_unit(pg_temp.uid('u.safetyhead@test.ly'), 'safety', true);
select public.set_user_unit(pg_temp.uid('u.qc@test.ly'), 'quality_control', false);
select public.set_user_unit(pg_temp.uid('u.heritage@test.ly'), 'heritage', false);
select pg_temp.expect_error($$select public.set_user_unit(pg_temp.uid('u.qc@test.ly'), 'nowhere', false)$$, 'وحدة غير موجودة');
select pg_temp.expect_error($$select public.set_user_unit(auth.uid(), 'safety', false)$$, 'حساب المدير لا يُسند إلى وحدة');
select pg_temp.check((select unit = 'safety' and unit_head from profiles where email = 'u.safetyhead@test.ly'), 'رئيس الوحدة');
select pg_temp.check((select count(*) = 4 from audit_log where action = 'user.unit'), 'الإسناد مسجّل في التدقيق');
select public.set_user_unit(pg_temp.uid('u.heritage@test.ly'), 'heritage', false);
select pg_temp.check((select count(*) = 4 from audit_log where action = 'user.unit'), 'إسناد بلا تغيير لا يُسجَّل');

-- ---------------------------------------------------------------- السلامة المهنية
select pg_temp.as_user('u.safety@test.ly');
select pg_temp.check(public.unit_can_edit('safety') and not public.unit_can_edit('quality_control') and not public.unit_is_head('safety'),
  'عضو السلامة يكتب في وحدته فقط وليس رئيسها');
select pg_temp.expect_error($$select public.save_unit_record(null, '{"kind":"safety_inspection","title":"جولة تفتيش أسبوعية"}')$$,
  'جولة التفتيش تحتاج عقداً');
insert into ids select 'insp', public.save_unit_record(null, jsonb_build_object(
  'kind', 'safety_inspection', 'project_id', pg_temp.pid('990'), 'title', 'جولة تفتيش أسبوعية', 'rec_date', '2026-11-10',
  'level', 'acceptable', 'owner_text', 'م. علي', 'data', jsonb_build_object('score', 72, 'ppe', 'نقص في الخوذ', 'empty', '   ')));
select pg_temp.check((select unit = 'safety' and status = 'open' and level = 'acceptable' and data = '{"ppe":"نقص في الخوذ","score":72}'::jsonb
                        and closed_at is null from unit_records where id = (select v from ids where k = 'insp')),
  'الحالة الافتراضية، والحقول الخاصة تُنظَّف من الفارغ');
insert into ids select 'viol', public.save_unit_record(null, jsonb_build_object(
  'kind', 'safety_violation', 'parent_id', (select v from ids where k = 'insp'), 'title', 'العمل على ارتفاع دون حزام',
  'level', 'high', 'rec_date', '2026-11-10', 'due_date', '2026-11-12'));
select pg_temp.check((select project_id = pg_temp.pid('990') and parent_id = (select v from ids where k = 'insp')
                        from unit_records where id = (select v from ids where k = 'viol')), 'المخالفة تأخذ عقد جولتها');
select pg_temp.expect_error($$select public.save_unit_record(null, jsonb_build_object('kind','safety_violation','project_id',pg_temp.pid('990'),
  'title','مخالفة','rec_date','2026-11-10','due_date','2026-11-09'))$$, 'الموعد قبل التاريخ');
select pg_temp.expect_error($$select public.save_unit_record(null, '{"kind":"safety_incident","title":"حادث","status":"lost"}')$$, 'حالة غير معروفة');
select pg_temp.expect_error($$select public.save_unit_record(null, '{"kind":"safety_incident","title":"حادث","data":{"Bad Key":"x"}}')$$, 'اسم حقل غير صالح');
select pg_temp.expect_error($$select public.save_unit_record(null, '{"kind":"safety_incident","title":"حادث","data":{"x":{"y":1}}}')$$, 'قيمة مركّبة في حقل');
select pg_temp.expect_error($$select public.save_unit_record(null, jsonb_build_object('kind','safety_incident','title','حادث','data',
  (select jsonb_object_agg('f' || i, i) from generate_series(1, 41) i)))$$, 'حقول أكثر من 40');
select pg_temp.expect_error($$select public.save_unit_record(null, '{"kind":"qc_test","title":"اختبار مكعبات"}')$$, 'عضو السلامة لا يكتب في ضبط الجودة');
select pg_temp.expect_error($$select public.save_unit_record(null, '{"kind":"rocket","title":"نوع مجهول"}')$$, 'نوع غير معروف');
insert into ids select 'inc', public.save_unit_record(null, '{"kind":"safety_incident","title":"انزلاق عامل","level":"minor"}');

-- الإغلاق يضبط تاريخه، وإعادة الفتح تمسحه
select public.save_unit_record((select v from ids where k = 'viol'), jsonb_build_object(
  'title', 'العمل على ارتفاع دون حزام', 'level', 'high', 'status', 'closed', 'rec_date', '2026-11-10', 'due_date', '2026-11-12'));
select pg_temp.check((select closed_at = current_date and kind = 'safety_violation' from unit_records where id = (select v from ids where k = 'viol')),
  'الإغلاق يسجّل تاريخه');
select public.save_unit_record((select v from ids where k = 'viol'), jsonb_build_object(
  'title', 'العمل على ارتفاع دون حزام', 'level', 'high', 'status', 'open', 'rec_date', '2026-11-10', 'due_date', '2026-11-12'));
select pg_temp.check((select closed_at is null from unit_records where id = (select v from ids where k = 'viol')), 'وإعادة الفتح تمسحه');
select pg_temp.check((select count(*) = 2 from audit_log where action = 'unit.update'
                       and detail ->> 'record_id' = (select v from ids where k = 'viol')::text), 'التعديلات مسجّلة');
select public.save_unit_record((select v from ids where k = 'viol'), jsonb_build_object(
  'title', 'العمل على ارتفاع دون حزام', 'level', 'high', 'status', 'open', 'rec_date', '2026-11-10', 'due_date', '2026-11-12'));
select pg_temp.check((select count(*) = 2 from audit_log where action = 'unit.update'
                       and detail ->> 'record_id' = (select v from ids where k = 'viol')::text), 'حفظ بلا تغيير لا يُسجَّل');

-- المرفقات
select pg_temp.upload('unit/' || (select v from ids where k = 'insp') || '/Abcdefgh1234.jpg', 250000, 'image/jpeg');
insert into ids select 'file', public.add_doc_file('unit/' || (select v from ids where k = 'insp') || '/Abcdefgh1234.jpg', 'موقع.jpg', 1600, 1200);
select pg_temp.check((select record_id = (select v from ids where k = 'insp') and mime = 'image/jpeg' and size_bytes = 250000
                        from doc_files where id = (select v from ids where k = 'file')), 'المرفق يُسجَّل للسجل بنوعه وحجمه من الحاوية');
select pg_temp.as_user('u.qc@test.ly');
select pg_temp.expect_error($$select pg_temp.upload('unit/' || (select v from ids where k = 'insp') || '/Zyxwvuts9876.pdf')$$,
  'عضو ضبط الجودة لا يرفع ملفاً لسجل السلامة');

-- الحذف: العضو لا يحذف سجل غيره، والرئيس يحذف
select pg_temp.as_user('u.safetyhead@test.ly');
insert into ids select 'inc2', public.save_unit_record(null, jsonb_build_object('kind', 'safety_incident', 'project_id', pg_temp.pid('990'),
  'title', 'حادث وشيك عند الرافعة', 'level', 'near_miss'));
select pg_temp.as_user('u.safety@test.ly');
select pg_temp.expect_error($$select public.delete_unit_record((select v from ids where k = 'inc2'))$$, 'العضو لا يحذف سجل غيره');
select pg_temp.check(cardinality(public.delete_unit_record((select v from ids where k = 'inc'))) = 0, 'العضو يحذف سجله خلال 24 ساعة');
select pg_temp.as_user('u.safetyhead@test.ly');
select pg_temp.check(public.unit_is_head('safety'), 'رئيس الوحدة');
select pg_temp.check(public.delete_doc_file((select v from ids where k = 'file')) like 'unit/%', 'رئيس الوحدة يزيل مرفق العضو');
select pg_temp.upload('unit/' || (select v from ids where k = 'viol') || '/Qwertyui5678.pdf');
select public.add_doc_file('unit/' || (select v from ids where k = 'viol') || '/Qwertyui5678.pdf', 'صورة المخالفة.pdf');
select pg_temp.check(cardinality(public.delete_unit_record((select v from ids where k = 'insp'))) = 1,
  'حذف الجولة يحذف مخالفاتها ويعيد مسارات ملفاتها');
select pg_temp.check((select count(*) = 0 from unit_records where id = (select v from ids where k = 'viol')), 'المخالفة حُذفت مع جولتها');

-- ---------------------------------------------------------------- المطابقة والاستلام
select pg_temp.as_user('k.headacc@test.ly');
select pg_temp.check(public.unit_can_edit('receiving') and public.unit_can_edit('quality_control') and public.unit_is_head('receiving')
                     and not public.unit_can_edit('safety'), 'رئيس المطابقة والاستلام يكتب في وحدتيه ويرأسهما');
insert into ids select 'hand', public.save_unit_record(null, jsonb_build_object('kind', 'handover', 'project_id', pg_temp.pid('990'),
  'title', 'الاستلام الابتدائي', 'level', 'initial', 'rec_date', '2026-12-01', 'data', jsonb_build_object('committee', 'لجنة 3')));
select pg_temp.check((select status = 'scheduled' from unit_records where id = (select v from ids where k = 'hand')), 'المحضر مجدول افتراضياً');
select pg_temp.expect_error($$select public.save_unit_record(null, '{"kind":"punch_item","title":"تشققات في اللياسة"}')$$,
  'بند الملاحظات يحتاج محضراً');
select pg_temp.expect_error($$select public.save_unit_record(null, jsonb_build_object('kind','punch_item','title','بند','parent_id',
  (select v from ids where k = 'hand'), 'level', 'high'))$$, 'تصنيف غير مسموح لبند الملاحظات');
insert into ids select 'punch', public.save_unit_record(null, jsonb_build_object('kind', 'punch_item', 'parent_id', (select v from ids where k = 'hand'),
  'title', 'تشققات في اللياسة', 'owner_text', 'المقاول', 'due_date', '2026-12-10', 'rec_date', '2026-12-01'));
select pg_temp.check((select project_id = pg_temp.pid('990') and level = '' from unit_records where id = (select v from ids where k = 'punch')),
  'البند يأخذ عقد المحضر');
select pg_temp.as_user('u.qc@test.ly');
insert into ids select 'test', public.save_unit_record(null, jsonb_build_object('kind', 'qc_test', 'project_id', pg_temp.pid('990'),
  'title', 'مقاومة مكعبات الخرسانة 28 يوماً', 'level', 'concrete', 'status', 'passed',
  'data', jsonb_build_object('result', 31.5, 'required', 25, 'unit', 'MPa')));
select pg_temp.check((select closed_at = current_date from unit_records where id = (select v from ids where k = 'test')), 'نتيجة الاختبار تغلقه');
select pg_temp.expect_error($$select public.save_unit_record(null, '{"kind":"punch_item","title":"بند","parent_id":"00000000-0000-0000-0000-000000000000"}')$$,
  'عضو ضبط الجودة لا يكتب في وحدة الاستلام');

-- ---------------------------------------------------------------- مكتب التخطيط وضمان الجودة
select pg_temp.as_user('k.qa@test.ly');
select pg_temp.check(public.unit_can_edit('planning') and public.unit_can_edit('quality_assurance') and public.unit_can_edit('follow_up')
                     and public.unit_is_head('follow_up') and not public.unit_can_edit('heritage'),
  'دور مكتب التخطيط يكتب في أقسامه الثلاثة');
insert into ids select 'plan', public.save_unit_record(null, '{"kind":"plan","title":"خطة الربع الأول 2027","level":"quarterly","progress":40,
  "rec_date":"2026-11-01","due_date":"2027-03-31","data":{"target":"إنجاز 6 عقود","kpi":"نسبة العقود المنجزة"}}');
select pg_temp.check((select progress = 40 and status = 'draft' from unit_records where id = (select v from ids where k = 'plan')), 'الخطة ونسبة إنجازها');
select pg_temp.expect_error($$select public.save_unit_record(null, '{"kind":"plan","title":"خطة","progress":140}')$$, 'نسبة أكبر من 100');
insert into ids select 'audit', public.save_unit_record(null, jsonb_build_object('kind', 'qa_audit', 'project_id', pg_temp.pid('990'),
  'title', 'تدقيق ملف الجودة للعقد', 'rec_date', '2026-11-05'));
select pg_temp.check((select level = '' from unit_records where id = (select v from ids where k = 'audit')), 'التدقيق بلا نتيجة حتى يكتمل');
insert into ids select 'ncr', public.save_unit_record(null, jsonb_build_object('kind', 'ncr', 'parent_id', (select v from ids where k = 'audit'),
  'title', 'غياب سجل معايرة الأجهزة', 'level', 'major', 'due_date', '2026-11-20', 'rec_date', '2026-11-05'));
select pg_temp.expect_error($$select public.save_unit_record(null, jsonb_build_object('kind','ncr','title','عدم مطابقة',
  'parent_id', (select v from ids where k = 'plan')))$$, 'لا تتبع عدم المطابقة خطة');
insert into ids select 'task', public.save_unit_record(null, '{"kind":"followup_task","title":"تسليم تقرير الإنجاز الشهري","level":"high",
  "owner_text":"قسم الإشراف والتنسيق","rec_date":"2026-11-01","due_date":"2026-11-05"}');
select public.save_unit_record((select v from ids where k = 'task'), '{"title":"تسليم تقرير الإنجاز الشهري","level":"high",
  "owner_text":"قسم الإشراف والتنسيق","rec_date":"2026-11-01","due_date":"2026-11-05","status":"done"}');
select pg_temp.check((select closed_at is not null from unit_records where id = (select v from ids where k = 'task')), 'إنجاز التكليف يسجّل تاريخه');
select pg_temp.as_user('k.headsup@test.ly');
select pg_temp.expect_error($$select public.save_unit_record(null, '{"kind":"followup_task","title":"تكليف"}')$$, 'رئيس الإشراف لا يكتب في المتابعة');
select pg_temp.check((select count(*) >= 3 from unit_records where unit in ('planning', 'quality_assurance', 'follow_up')), 'والجميع يطّلع على السجلات');

-- ---------------------------------------------------------------- الترميم والمباني التاريخية
select pg_temp.as_user('headrest@test.ly');
select pg_temp.check(public.unit_can_edit('heritage') and public.unit_is_head('heritage'), 'رئيس الترميم يرأس سجل المباني التاريخية');
insert into ids select 'bld', public.save_unit_record(null, jsonb_build_object('kind', 'heritage_building', 'title', 'مبنى البلدية القديم',
  'project_id', pg_temp.pid('991'), 'level', 'poor', 'data', jsonb_build_object('era', 'العهد الإيطالي', 'grade', 'وطني', 'area', 'وسط البلاد')));
select pg_temp.check((select status = 'registered' and level = 'poor' from unit_records where id = (select v from ids where k = 'bld')),
  'المبنى مسجّل بحالته الإنشائية');
select pg_temp.as_user('u.heritage@test.ly');
select pg_temp.expect_error($$select public.save_unit_record(null, '{"kind":"heritage_assessment","title":"تقييم"}')$$, 'التقييم يحتاج مبنى');
insert into ids select 'asm', public.save_unit_record(null, jsonb_build_object('kind', 'heritage_assessment', 'parent_id', (select v from ids where k = 'bld'),
  'title', 'تقييم الحالة بعد الأمطار', 'level', 'critical', 'rec_date', '2026-11-08'));
select pg_temp.check((select project_id = pg_temp.pid('991') from unit_records where id = (select v from ids where k = 'asm')), 'التقييم يأخذ عقد المبنى');
select pg_temp.expect_error($$select public.delete_unit_record((select v from ids where k = 'bld'))$$, 'العضو لا يحذف سجل رئيسه');

-- ---------------------------------------------------------------- اتباع الدمج
select pg_temp.as_user('director.new@test.ly', 'aal2');
select public.merge_contracts(pg_temp.pid('990'), array[pg_temp.pid('991')]);
select pg_temp.check((select count(*) = 2 from unit_records where project_id = pg_temp.pid('990') and origin_project = pg_temp.pid('991')),
  'سجلات العقد تنتقل مع الدمج');
select public.unmerge_contract(pg_temp.pid('991'));
select pg_temp.check((select count(*) = 2 from unit_records where project_id = pg_temp.pid('991') and origin_project is null),
  'وتعود مع فكّ الدمج');

-- ---------------------------------------------------------------- وضع القراءة فقط
reset role;
update app_settings set value = 'true' where key = 'security.freeze';
set role authenticated;
select pg_temp.as_user('u.heritage@test.ly');
select pg_temp.expect_error($$select public.save_unit_record(null, jsonb_build_object('kind','heritage_assessment','title','تقييم',
  'parent_id', (select v from ids where k = 'bld')))$$, 'وضع القراءة فقط يوقف الكتابة');
reset role;
update app_settings set value = 'false' where key = 'security.freeze';

-- ---------------------------------------------------------------- إلغاء الإسناد
set role authenticated;
select pg_temp.as_user('director.new@test.ly', 'aal2');
select public.set_user_unit(pg_temp.uid('u.safetyhead@test.ly'), null, true);
select pg_temp.check((select unit is null and not unit_head from profiles where email = 'u.safetyhead@test.ly'), 'إلغاء الإسناد يلغي الرئاسة');
select pg_temp.as_user('u.safetyhead@test.ly');
select pg_temp.check(not public.unit_can_edit('safety'), 'وبعده لا يكتب في الوحدة');
select pg_temp.check((select count(*) >= 10 from audit_log where action like 'unit.%'), 'عمليات السجلات مسجّلة في التدقيق');

reset role;
select 'UNIT SECTIONS TESTS PASSED';
