-- اختبارات الترحيل 23: الاسم الجديد، والصلاحيات الدقيقة، والرقم الإشاري الموسّع، وتخصيص الواجهة.
-- يُشغَّل بعد تطبيق 20261119000023_rasd_grants_refs.sql مرتين، وبعد اختبارات الترحيلات 20–22 (يستعمل بياناتها).
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
create or replace function pg_temp.rec(p_title text) returns uuid language sql security definer as $$
  select id from public.unit_records where title = p_title order by created_at limit 1
$$;
create or replace function pg_temp.yyyy() returns text language sql as $$
  select to_char(now() at time zone 'Africa/Tripoli', 'YYYY')
$$;
grant execute on all functions in schema pg_temp to authenticated, anon;

update app_settings set value = 'false' where key in ('security.freeze', 'security.require_mfa_all');
create temp table ids (k text primary key, v uuid);
grant all on ids to authenticated;

-- ---------------------------------------------------------------- الاسم والبنية
select pg_temp.check((select value #>> '{}' = 'منظومة رصد' from app_settings where key = 'brand.app_title'),
  'اسم المنظومة صار «منظومة رصد»');
select pg_temp.check((select count(*) = 4 from ref_schemes where system), 'أربع صيغ أساسية للأرقام الإشارية');
select pg_temp.check((select value = '{}'::jsonb from app_settings where key = 'ui.layout'), 'إعداد تخصيص الواجهة موجود');
select pg_temp.check(exists (select 1 from pg_proc where proname = 'doc_can_edit_v22')
                     and exists (select 1 from pg_proc where proname = 'set_setting_v22'),
  'الدوال الأصلية محفوظة بأسمائها');
select pg_temp.check((select bool_and(proconfig is not null) from pg_proc
                       where pronamespace = 'public'::regnamespace
                         and proname in ('has_grant', 'set_user_grants', 'unit_kind_can_edit', 'next_ref', 'ref_format', 'save_ref_scheme')),
  'مسار البحث ثابت للدوال الجديدة');

-- ---------------------------------------------------------------- الصلاحيات الدقيقة: قبل المنح
set role authenticated;
select pg_temp.as_user('k.contracts@test.ly');
select pg_temp.check(not public.doc_can_edit('design', pg_temp.pid('990')) and not public.site_report_can_edit(pg_temp.pid('990'))
                     and not public.can_edit_form(pg_temp.pid('990'), 'f04') and not public.unit_kind_can_edit('ncr')
                     and not public.can_edit_swot(),
  'موظف العقود لا يكتب في التصاميم ولا تقارير الإشراف ولا النموذج f04 ولا عدم المطابقة ولا SWOT');
select pg_temp.check(public.can_edit_form(pg_temp.pid('990'), 'f01') and public.doc_can_edit('letter', pg_temp.pid('990')),
  'وصلاحياته الأصلية باقية');
select pg_temp.expect_error($$select public.set_user_grants(pg_temp.uid('k.contracts@test.ly'), array['swot'])$$,
  'غير المدير لا يمنح نفسه صلاحية');
select pg_temp.expect_error($$insert into user_grants (user_id, scope) values (auth.uid(), 'swot')$$, 'لا كتابة مباشرة في جدول الصلاحيات');

-- ---------------------------------------------------------------- المنح
select pg_temp.as_user('director.new@test.ly', 'aal2');
select pg_temp.expect_error($$select public.set_user_grants(pg_temp.uid('k.contracts@test.ly'), array['form:zz9'])$$, 'نموذج غير موجود');
select pg_temp.expect_error($$select public.set_user_grants(pg_temp.uid('k.contracts@test.ly'), array['unit:nothing'])$$, 'نوع سجل غير معروف');
select pg_temp.expect_error($$select public.set_user_grants(pg_temp.uid('k.contracts@test.ly'), array['admin'])$$, 'نطاق خارج القائمة');
select pg_temp.expect_error($$select public.set_user_grants(pg_temp.uid('auditor@test.ly'), array['swot'])$$, 'لا صلاحيات دقيقة لمسؤول الأمن');
select pg_temp.expect_error($$select public.set_user_grants(pg_temp.uid('director.new@test.ly'), array['swot'])$$, 'ولا للمدير');
select public.set_user_grants(pg_temp.uid('k.contracts@test.ly'),
  array['docs:design', 'supervision:reports', 'form:f04', 'unit:ncr', 'swot', 'swot', ' form:f04 ']);
select pg_temp.check((select count(*) = 5 from user_grants where user_id = pg_temp.uid('k.contracts@test.ly')),
  'خمس صلاحيات دقيقة دون تكرار');
select pg_temp.check((select count(*) = 1 from audit_log where action = 'user.grants'
                        and jsonb_array_length(detail -> 'added') = 5 and jsonb_array_length(detail -> 'removed') = 0),
  'المنح مسجّل في سجل التدقيق بما أُضيف');
select public.set_user_grants(pg_temp.uid('k.contracts@test.ly'),
  array['docs:design', 'supervision:reports', 'form:f04', 'unit:ncr', 'swot']);
select pg_temp.check((select count(*) = 1 from audit_log where action = 'user.grants'), 'إعادة الحفظ دون تغيير لا تُسجَّل');

-- ---------------------------------------------------------------- بعد المنح
select pg_temp.as_user('k.contracts@test.ly');
select pg_temp.check(public.doc_can_edit('design', pg_temp.pid('990')) and public.site_report_can_edit(pg_temp.pid('990'))
                     and public.can_edit_form(pg_temp.pid('990'), 'f04') and public.unit_kind_can_edit('ncr')
                     and public.can_edit_swot(),
  'بعد المنح يكتب في الخمسة بالضبط');
select pg_temp.check(not public.can_edit_form(pg_temp.pid('990'), 'f05') and not public.can_edit_form(pg_temp.pid('990'), 'f07')
                     and not public.unit_can_edit('quality_control') and not public.unit_kind_can_edit('qc_test')
                     and not public.unit_kind_can_edit('safety_incident'),
  'ولا يتعدّاها إلى ما لم يُمنح (f05 وf07، وباقي ضبط الجودة، والسلامة)');
insert into ids select 'ncr', public.save_unit_record(null, jsonb_build_object('kind', 'ncr',
  'parent_id', pg_temp.rec('مقاومة مكعبات الخرسانة 28 يوماً'), 'title', 'شروخ شعرية في البلاطة S2', 'level', 'minor',
  'rec_date', '2026-11-19'));
select pg_temp.check((select unit = 'quality_control' and created_by = auth.uid() from unit_records where id = (select v from ids where k = 'ncr')),
  'يسجّل حالة عدم مطابقة بالصلاحية الدقيقة');
select pg_temp.check(public.can_upload_doc_path('unit/' || (select v from ids where k = 'ncr') || '/abcdefgh12.pdf'),
  'ويرفع مرفقاتها');
select pg_temp.expect_error($$select public.save_unit_record(null, jsonb_build_object('kind','qc_test','project_id',pg_temp.pid('990'),
  'title','اختبار هبوط'))$$, 'ولا يسجّل اختبار جودة');
select public.save_unit_record((select v from ids where k = 'ncr'), jsonb_build_object('title', 'شروخ شعرية في البلاطة S2 - محدّث',
  'level', 'minor', 'rec_date', '2026-11-19'));
select pg_temp.check((select title like '%محدّث' from unit_records where id = (select v from ids where k = 'ncr')), 'ويعدّل ما سجّله');
select pg_temp.check((select count(*) = 5 from user_grants), 'يرى صلاحياته الدقيقة');

select pg_temp.as_user('u.qc@test.ly');
select pg_temp.check((select count(*) = 0 from user_grants), 'غيره لا يرى صلاحيات الآخرين');
select pg_temp.as_user('k.staff@test.ly');
select pg_temp.check((select count(*) = 5 from user_grants), 'موظف المكتب يراها');
select pg_temp.as_user('auditor@test.ly', 'aal2');
select pg_temp.check((select count(*) = 5 from user_grants), 'ومسؤول الأمن يراها');
select pg_temp.check(not public.has_grant('swot') and not public.can_edit_swot(), 'ومسؤول الأمن لا يكتب');

-- التجميد يوقف الصلاحية الدقيقة أيضاً
reset role;
update app_settings set value = 'true' where key = 'security.freeze';
set role authenticated;
select pg_temp.as_user('k.contracts@test.ly');
select pg_temp.check(not public.can_edit_form(pg_temp.pid('990'), 'f04') and not public.unit_kind_can_edit('ncr')
                     and not public.doc_can_edit('design', pg_temp.pid('990')) and not public.can_edit_swot(),
  'التجميد يوقف الصلاحيات الدقيقة');
reset role;
update app_settings set value = 'false' where key = 'security.freeze';
set role authenticated;

-- السحب
select pg_temp.as_user('director.new@test.ly', 'aal2');
select public.set_user_grants(pg_temp.uid('k.contracts@test.ly'), array['form:f04']);
select pg_temp.check((select jsonb_array_length(detail -> 'removed') = 4 from audit_log where action = 'user.grants'
                       order by id desc limit 1),
  'السحب مسجّل بما أُزيل');
select pg_temp.as_user('k.contracts@test.ly');
select pg_temp.check(public.can_edit_form(pg_temp.pid('990'), 'f04') and not public.unit_kind_can_edit('ncr')
                     and not public.can_edit_swot(),
  'بعد السحب يبقى ما تُرك فقط');

-- ---------------------------------------------------------------- الرقم الإشاري
select pg_temp.check((public.next_ref('print', '{"section": "cycle", "title": "تقرير العقود"}') ->> 'ref')
                       = 'م.ش.هـ/د.م/' || pg_temp.yyyy() || '/0001',
  'أول رقم للمطبوعات برمز القسم والسنة');
select pg_temp.check((public.next_ref('print', '{"section": "risks"}') ->> 'ref') = 'م.ش.هـ/م.م/' || pg_temp.yyyy() || '/0002',
  'التسلسل مشترك بين الأقسام ما لم يُفصل');
select pg_temp.check((public.next_ref('letter_out', '{}') ->> 'ref') = 'م.ش.هـ/ص/' || pg_temp.yyyy() || '/0001',
  'المراسلات الصادرة لها تسلسلها');
select pg_temp.check((select count(*) = 3 and bool_and(created_by = auth.uid()) from ref_log), 'كل رقم صدر محفوظ في السجل');
select pg_temp.expect_error($$select public.next_ref('nothing', '{}')$$, 'صيغة غير موجودة');
select pg_temp.expect_error($$select public.next_ref('print', '[1]')$$, 'سياق غير صالح');
select pg_temp.expect_error($$select public.save_ref_scheme('x_test', '{"name":"س","pattern":"{SEQ}"}')$$, 'غير المدير لا يبني الصيغ');
select pg_temp.expect_error($$insert into ref_counters values ('print', '2099', 1)$$, 'لا كتابة مباشرة في العدادات');

select pg_temp.as_user('director.new@test.ly', 'aal2');
select pg_temp.expect_error($$select public.save_ref_scheme('contract_mail', '{"name":"مراسلات العقود","pattern":"ع/{CODE}/{YY}"}')$$,
  'الصيغة بلا تسلسل مرفوضة');
select pg_temp.expect_error($$select public.save_ref_scheme('Bad Key', '{"name":"س","pattern":"{SEQ}"}')$$, 'مفتاح غير صالح');
select public.save_ref_scheme('contract_mail', jsonb_build_object('name', 'مراسلات العقود', 'pattern', 'ع/{CODE}/{YY}{MM}/{SEQ:3}',
  'reset', 'monthly', 'per_section', true, 'pad', 5, 'start_at', 7, 'codes', '{}'::jsonb));
select pg_temp.check((select count(*) = 1 from audit_log where action = 'ref.scheme_save' and detail ->> 'key' = 'contract_mail'
                        and (detail ->> 'created')::boolean),
  'إنشاء الصيغة مسجّل');
select pg_temp.check((public.next_ref('contract_mail', '{"code": "990/2026", "section": "cycle"}') ->> 'ref')
                       = 'ع/990-2026/' || to_char(now() at time zone 'Africa/Tripoli', 'YYMM') || '/007',
  'رمز يمرره المصدر، وشهر وسنة مختصرة، وثلاث خانات تبدأ من 7');
select pg_temp.check((public.next_ref('contract_mail', '{"code": "991", "section": "risks"}') ->> 'seq')::int = 7,
  'التسلسل مستقل لكل قسم عند فصله');
select pg_temp.check((public.next_ref('contract_mail', '{"code": "990", "section": "cycle"}') ->> 'seq')::int = 8,
  'ويتابع داخل القسم نفسه');
select pg_temp.check(public.ref_format('{DD}-{KIND}-{DEPT}-{SECTION}-{SEQ}', 5, 2, '2026-03-04 10:00+00',
                                       '{"kind": "ncr", "dept": "supervision"}', '{"ncr": "ع.م"}') = '04-ع.م-supervision---05',
  'رموز اليوم والنوع والقسم المشرف، وشرطة لما لا قيمة له');
select pg_temp.check(public.ref_format('{YYYY}/{SEQ:8}', 42, 4, '2026-12-31 23:30+00', '{}', '{}') = '2027/00000042',
  'السنة بتوقيت طرابلس، وثماني خانات');

-- ضبط العداد عند الانتقال من دفتر ورقي
select public.set_ref_counter('letter_out', 50);
select pg_temp.check((public.next_ref('letter_out', '{}') ->> 'ref') = 'م.ش.هـ/ص/' || pg_temp.yyyy() || '/0050', 'الرقم التالي بعد الضبط 50');
select pg_temp.expect_error($$select public.set_ref_counter('letter_out', 40)$$, 'لا رجوع إلى رقم صدر');
select pg_temp.check((select count(*) = 1 from audit_log where action = 'ref.counter_set'), 'ضبط العداد مسجّل');

-- الحذف والإيقاف
select pg_temp.expect_error($$select public.delete_ref_scheme('print')$$, 'الصيغ الأساسية لا تُحذف');
select pg_temp.expect_error($$select public.delete_ref_scheme('contract_mail')$$, 'صيغة صدرت بها أرقام لا تُحذف');
select public.save_ref_scheme('contract_mail', jsonb_build_object('name', 'مراسلات العقود', 'pattern', 'ع/{CODE}/{YY}{MM}/{SEQ:3}',
  'reset', 'monthly', 'per_section', true, 'active', false));
select pg_temp.expect_error($$select public.next_ref('contract_mail', '{}')$$, 'الصيغة الموقوفة لا تُصدر أرقاماً');
select public.save_ref_scheme('temp_scheme', '{"name": "مؤقتة", "pattern": "T-{SEQ}"}');
select public.delete_ref_scheme('temp_scheme');
select pg_temp.check(not exists (select 1 from ref_schemes where key = 'temp_scheme')
                     and exists (select 1 from audit_log where action = 'ref.scheme_delete'),
  'صيغة لم يصدر بها رقم تُحذف ويُسجَّل حذفها');

-- ---------------------------------------------------------------- تخصيص الواجهة
select public.set_setting('ui.layout', '{"sections": {"risks": {"name": "المخاطر والفرص", "desc": "سجل المخاطر"}},
  "section_order": ["cycle", "risks"], "pages": {"40": {"label": "سجل المخاطر"}}, "page_order": {"risks": [41, 40]}}');
select pg_temp.check((select value -> 'sections' -> 'risks' ->> 'name' = 'المخاطر والفرص' from app_settings where key = 'ui.layout'),
  'المدير يخصص أسماء الأقسام وترتيب الصفحات');
select pg_temp.check((select count(*) = 1 from audit_log where action = 'setting.update' and project_label = 'ui.layout'),
  'التخصيص مسجّل');
select pg_temp.expect_error($$select public.set_setting('ui.layout', '{"pages": {"x": {"label": "س"}}}')$$, 'رقم صفحة غير صالح');
select pg_temp.expect_error($$select public.set_setting('ui.layout', '[1]')$$, 'قيمة غير كائن');
select public.set_setting('brand.org_name', '"مكتب الشؤون الهندسية"');
select public.set_setting('ui.labels', '{"project": "عقد"}');
select pg_temp.check((select value = '{"project": "عقد"}'::jsonb from app_settings where key = 'ui.labels'),
  'باقي الإعدادات تمر إلى الدالة الأصلية');
select pg_temp.as_user('k.staff@test.ly');
select pg_temp.expect_error($$select public.set_setting('ui.layout', '{}')$$, 'غير المدير لا يخصص الواجهة');

reset role;
select 'ALL 23 TESTS PASSED';
