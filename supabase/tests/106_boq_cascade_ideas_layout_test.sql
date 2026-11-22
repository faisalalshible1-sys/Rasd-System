-- اختبارات الترحيل 33: حذف المقايسة يحذف بنودها من البرنامج الزمني ومتابعة الإشراف، والأفكار بالقسم والصفحة،
-- وتخصيص الواجهة الموسّع. يُشغَّل بعد تطبيق 20261122000033_boq_cascade_ideas_layout.sql مرتين، وبعد اختبارات الترحيل 32.
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
create or replace function pg_temp.alog() returns setof public.audit_log language sql security definer as $$
  select * from public.audit_log
$$;
create or replace function pg_temp.notes() returns setof public.notifications language sql security definer as $$
  select * from public.notifications
$$;
create or replace function pg_temp.uid(p_email text) returns uuid language sql security definer as $$
  select id from auth.users where email = p_email
$$;
grant execute on all functions in schema pg_temp to authenticated, anon;

update app_settings set value = 'false' where key in ('security.freeze', 'security.require_mfa_all');
update app_settings set value = jsonb_set(value, '{ideas_for_all}', 'true') where key = 'ui.features';
update profiles set locked_until = null where email like 'k.%@test.ly';
create temp table ids (k text primary key, v uuid);
grant all on ids to authenticated;
create or replace function pg_temp.id(p_k text) returns uuid language sql as $$ select v from ids where k = p_k $$;
create or replace function pg_temp.seq(p_code text) returns integer language sql security definer as $$
  select seq from public.price_items where list_id = 'guide-2026' and chapter = 'buildings' and code = p_code
$$;
create or replace function pg_temp.qitem(p_code text) returns uuid language sql security definer as $$
  select id from public.pm_items where project_id = (select v from ids where k = 'q') and price_seq = pg_temp.seq(p_code)
$$;
create or replace function pg_temp.qcount(p_sql text) returns integer language plpgsql security definer as $$
declare n integer;
begin
  execute p_sql into n;
  return n;
end $$;
grant execute on all functions in schema pg_temp to authenticated, anon;

-- ---------------------------------------------------------------- عقد بمقايستين معتمدتين وبرنامج معتمد عليه إنجاز
set role authenticated;
select pg_temp.as_user('k.staff@test.ly');
insert into ids select 'q', public.save_project(null, '{"assign_no": "T-33", "name": "عقد اختبار حذف المقايسة", "company": "شركة التنفيذ", "department": "supervision"}');

select pg_temp.as_user('k.headtech@test.ly');
insert into ids select 'b1', public.save_boq(null, jsonb_build_object(
  'title', 'المقايسة الأولى', 'project_id', pg_temp.id('q'), 'lines', jsonb_build_array(
    jsonb_build_object('seq', pg_temp.seq('1.1.1.1'), 'qty', 1000),
    jsonb_build_object('seq', pg_temp.seq('3.2.6.5'), 'qty', 40))));
insert into ids select 'b2', public.save_boq(null, jsonb_build_object(
  'title', 'المقايسة الثانية', 'project_id', pg_temp.id('q'), 'lines', jsonb_build_array(
    jsonb_build_object('seq', pg_temp.seq('7.2.2.1'), 'qty', 100),
    jsonb_build_object('desc', 'دهان نهائي للموقع', 'unit', 'مقطوعية', 'price', 2500, 'qty', 2))));
select public.approve_boq(pg_temp.id('b1'), true);
select public.approve_boq(pg_temp.id('b2'), true);
select from public.pm_plan_generate(pg_temp.id('q'), '2026-03-01', 60);
select pg_temp.check((select count(*) = 4 from pm_items where project_id = pg_temp.id('q'))
                     and (select count(*) = 4 from pm_phases where project_id = pg_temp.id('q')),
                     'البرنامج من المقايستين: 4 بنود في 4 مراحل');
select public.pm_plan_set_status(pg_temp.id('q'), 'approved');
select pg_temp.as_user('k.headsup@test.ly');
select from public.save_pm_item(pg_temp.qitem('3.2.6.5'), '{"progress": 30, "actual_start": "2026-03-10"}');

-- ---------------------------------------------------------------- لا حذف قبل إعادة الفتح
select pg_temp.as_user('k.headtech@test.ly');
select pg_temp.expect_error($$select public.delete_boq(pg_temp.id('b1'))$$, 'المقايسة المعتمدة لا تُحذف');
select pg_temp.expect_error($$select public.approve_boq(pg_temp.id('b1'), false)$$, 'ولا تُعاد فتحها والبرنامج المعتمد مبني عليها');
select public.pm_plan_set_status(pg_temp.id('q'), 'draft');
select public.approve_boq(pg_temp.id('b1'), false);
select pg_temp.as_user('k.contracts@test.ly');
select pg_temp.expect_error($$select public.delete_boq(pg_temp.id('b1'))$$, 'لا يحذفها غير من أعدّها أو المدير');

-- ---------------------------------------------------------------- الحذف يحذف بنودها من البرنامج والإشراف
select pg_temp.as_user('k.headtech@test.ly');
select pg_temp.check((select r = '{"items": 2, "tracked": 1, "phases": 2, "plans": 0}'::jsonb from public.delete_boq(pg_temp.id('b1')) r),
                     'حذف المقايسة الأولى: بنداها (أحدهما عليه إنجاز) ومرحلتاهما اللتان فرغتا');
select pg_temp.check((select count(*) = 0 from boq_sheets where id = pg_temp.id('b1'))
                     and (select count(*) = 0 from pm_items where project_id = pg_temp.id('q') and (boq_sheet_id is null or boq_sheet_id = pg_temp.id('b1'))),
                     'لا يبقى بند بلا مقايسته في البرنامج ولا في متابعة الإشراف');
select pg_temp.check((select count(*) = 2 from pm_items where project_id = pg_temp.id('q') and boq_sheet_id = pg_temp.id('b2'))
                     and (select array_agg(name order by sort) = array['أعمال تكسيات الحوائط والأرضيات والوزرات', 'بنود أخرى']
                            from pm_phases where project_id = pg_temp.id('q')),
                     'وتبقى بنود المقايسة الأخرى ومرحلتاها');
select pg_temp.check((select status = 'draft' from pm_plans where project_id = pg_temp.id('q'))
                     and (select min(planned_start) = '2026-03-01' from pm_items where project_id = pg_temp.id('q')),
                     'البرنامج باقٍ مسودة، ويُعاد حسابه فتبدأ أول مرحلة باقية ببدايته');
select pg_temp.check((select count(*) = 1 from pg_temp.alog()
                       where action = 'boq.delete' and project_id = pg_temp.id('q') and detail ->> 'title' = 'المقايسة الأولى'
                         and (detail ->> 'plan_items')::int = 2 and (detail ->> 'tracked_items')::int = 1 and detail ->> 'plan_removed' = 'false'),
                     'الحذف وأعداده في سجل التدقيق');

-- ---------------------------------------------------------------- حذف آخر مقايسة يحذف البرنامج المسودة كله
select public.approve_boq(pg_temp.id('b2'), false);
select pg_temp.as_user('director.new@test.ly', 'aal2');
select pg_temp.check((select r = '{"items": 2, "tracked": 0, "phases": 2, "plans": 1}'::jsonb from public.delete_boq(pg_temp.id('b2')) r),
                     'المدير يحذف المقايسة الثانية: بنداها ومرحلتاها والبرنامج المسودة');
select pg_temp.check((select count(*) = 0 from pm_items where project_id = pg_temp.id('q'))
                     and (select count(*) = 0 from pm_phases where project_id = pg_temp.id('q'))
                     and (select count(*) = 0 from pm_plans where project_id = pg_temp.id('q')),
                     'العقد بلا برنامج زمني بعدها');
select pg_temp.check((select count(*) = 1 from pg_temp.alog() where action = 'boq.delete' and detail ->> 'title' = 'المقايسة الثانية'
                         and detail ->> 'plan_removed' = 'true'), 'وسجل التدقيق يذكر حذف البرنامج');

-- ---------------------------------------------------------------- البرنامج المعتمد يمنع الحذف حتى لو صارت المقايسة مسودة
select pg_temp.as_user('k.headtech@test.ly');
insert into ids select 'b3', public.save_boq(null, jsonb_build_object(
  'title', 'المقايسة الثالثة', 'project_id', pg_temp.id('q'), 'lines', jsonb_build_array(
    jsonb_build_object('seq', pg_temp.seq('1.2.1.1'), 'qty', 200))));
select public.approve_boq(pg_temp.id('b3'), true);
select from public.pm_plan_generate(pg_temp.id('q'), '2026-04-01', 30);
select public.pm_plan_set_status(pg_temp.id('q'), 'approved');
reset role;
update boq_sheets set status = 'draft', approved_at = null, approved_by = null where id = pg_temp.id('b3');
set role authenticated;
select pg_temp.as_user('director.new@test.ly', 'aal2');
select pg_temp.expect_error($$select public.delete_boq(pg_temp.id('b3'))$$, 'لا حذف لمقايسة بُني عليها البرنامج المعتمد');
select pg_temp.check((select count(*) = 1 from pm_items where boq_sheet_id = pg_temp.id('b3')), 'وتبقى بنودها');

-- ---------------------------------------------------------------- لا يبقى بند بلا مقايسته حتى بالحذف المباشر
reset role;
update pm_plans set status = 'draft' where project_id = pg_temp.id('q');
delete from boq_sheets where id = pg_temp.id('b3');
select pg_temp.check((select count(*) = 0 from pm_items where project_id = pg_temp.id('q')), 'حذف المقايسة يحذف بنودها (on delete cascade)');

-- ---------------------------------------------------------------- تنظيف ما بقي من حذف سابق
set role authenticated;
select pg_temp.as_user('k.staff@test.ly');
insert into ids select 'o1', public.save_project(null, '{"assign_no": "T-34", "name": "عقد ببنود يتيمة وبند يدوي", "company": "شركة", "department": "supervision"}');
insert into ids select 'o2', public.save_project(null, '{"assign_no": "T-35", "name": "عقد ببند يتيم وحده", "company": "شركة", "department": "supervision"}');
insert into ids select 'o3', public.save_project(null, '{"assign_no": "T-36", "name": "عقد معتمد ببند يتيم", "company": "شركة", "department": "supervision"}');
reset role;
insert into pm_plans (project_id, start_date) values (pg_temp.id('o1'), '2026-01-01'), (pg_temp.id('o2'), '2026-01-01');
insert into pm_plans (project_id, start_date, status, version) values (pg_temp.id('o3'), '2026-01-01', 'approved', 1);
insert into pm_items (project_id, title, planned_start, planned_end, source) values
  (pg_temp.id('o1'), 'بند يتيم أول', '2026-01-01', '2026-01-10', 'boq'),
  (pg_temp.id('o1'), 'بند يتيم ثانٍ', '2026-01-01', '2026-01-10', 'boq'),
  (pg_temp.id('o1'), 'بند يدوي', '2026-01-01', '2026-01-20', 'manual'),
  (pg_temp.id('o2'), 'بند يتيم وحيد', '2026-01-01', '2026-01-10', 'boq'),
  (pg_temp.id('o3'), 'بند يتيم في برنامج معتمد', '2026-01-01', '2026-01-10', 'boq');
do $$ begin perform set_config('request.jwt.claim.sub', '', false); perform set_config('request.jwt.claims', '{}', false); end $$;
set client_min_messages = warning;
\ir ../migrations/20261122000033_boq_cascade_ideas_layout.sql
reset client_min_messages;
select pg_temp.check((select array_agg(title) = array['بند يدوي'] from pm_items where project_id = pg_temp.id('o1'))
                     and (select count(*) = 1 from pm_plans where project_id = pg_temp.id('o1')),
                     'التشغيل الثالث للترحيل ينظّف البنود اليتيمة ويُبقي البند اليدوي وبرنامجه');
select pg_temp.check((select count(*) = 0 from pm_items where project_id = pg_temp.id('o2'))
                     and (select count(*) = 0 from pm_plans where project_id = pg_temp.id('o2')),
                     'والبرنامج المسودة الذي فرغ يُحذف');
select pg_temp.check((select count(*) = 1 from pm_items where project_id = pg_temp.id('o3')), 'والبرنامج المعتمد لا يُمس');
select pg_temp.check((select count(*) = 2 from audit_log where action = 'pm.boq_orphans'
                         and project_id in (pg_temp.id('o1'), pg_temp.id('o2'))), 'والتنظيف مسجّل لكل عقد');

-- ---------------------------------------------------------------- الأفكار بالقسم والصفحة
set role authenticated;
select pg_temp.as_user('k.staff@test.ly');
insert into ids select 'i1', public.submit_idea('تحسين لوحة الإشراف', 'إضافة رسم للمستخلصات', 'feature', 'high', 'supervision', 72, 'لوحة الإشراف');
select pg_temp.check((select section = 'supervision' and page_id = 72 and page_label = 'لوحة الإشراف' and created_by = pg_temp.uid('k.staff@test.ly')
                        from ideas where id = pg_temp.id('i1')), 'الفكرة تُحفظ بقسمها وصفحتها');
insert into ids select 'i0', public.submit_idea(p_title => 'فكرة عامة للمنظومة', p_body => '', p_category => 'design', p_priority => 'low');
select pg_temp.check((select section is null and page_id is null and page_label = '' from ideas where id = pg_temp.id('i0')),
                     'والإرسال بالصيغة القديمة يبقى فكرة عامة');
insert into ids select 'i2', public.submit_idea('فكرة لقسم المقايسات', '', 'feature', 'normal', 'docs', null, 'تُهمل دون صفحة');
select pg_temp.check((select section = 'docs' and page_id is null and page_label = '' from ideas where id = pg_temp.id('i2')),
                     'فكرة للقسم كله دون صفحة');
select pg_temp.expect_error($$select public.submit_idea('فكرة', '', 'feature', 'normal', 'unknown')$$, 'قسم غير معروف');
select pg_temp.expect_error($$select public.submit_idea('فكرة', '', 'feature', 'normal', null, 72, 'صفحة')$$, 'صفحة دون قسم');
select pg_temp.expect_error($$select public.submit_idea('فكرة', '', 'feature', 'normal', 'docs', 5000, 'صفحة')$$, 'رقم صفحة غير صالح');
select pg_temp.check((select count(*) >= 1 from pg_temp.notes() where kind = 'idea' and title = 'فكرة جديدة: تحسين لوحة الإشراف'
                         and body like '%لوحة الإشراف%'), 'إشعار المدير يذكر الصفحة');
select pg_temp.check((select count(*) = 1 from pg_temp.alog() where action = 'idea.create' and detail ->> 'section' = 'supervision'
                         and detail ->> 'page' = 'لوحة الإشراف'), 'الإرسال مسجّل بقسمه وصفحته');
select pg_temp.expect_error($$select public.move_idea(pg_temp.id('i1'), 'docs', null, null)$$, 'نقل الأفكار للمدير وحده');

select pg_temp.as_user('director.new@test.ly', 'aal2');
select public.move_idea(pg_temp.id('i1'), 'docs', 66, 'مُعِدّ المقايسات');
select pg_temp.check((select section = 'docs' and page_id = 66 and page_label = 'مُعِدّ المقايسات' from ideas where id = pg_temp.id('i1')),
                     'المدير ينقل الفكرة إلى قسم وصفحة أخرى');
select pg_temp.check((select count(*) = 1 from pg_temp.alog() where action = 'idea.move' and detail -> 'from' ->> 'section' = 'supervision'
                         and detail -> 'to' ->> 'page' = 'مُعِدّ المقايسات'), 'النقل مسجّل من وإلى');
select public.move_idea(pg_temp.id('i1'), 'docs', 66, 'مُعِدّ المقايسات');
select pg_temp.check((select count(*) = 1 from pg_temp.alog() where action = 'idea.move'), 'النقل إلى المكان نفسه لا يُسجَّل');
select public.move_idea(pg_temp.id('i1'), null, null, null);
select pg_temp.check((select section is null and page_id is null and page_label = '' from ideas where id = pg_temp.id('i1')), 'وجعلها عامة');
select pg_temp.expect_error($$select public.move_idea(pg_temp.id('i1'), null, 72, 'لوحة')$$, 'ولا صفحة دون قسم');

-- ---------------------------------------------------------------- تخصيص الواجهة الموسّع
select public.set_setting('ui.layout', '{"groups": [{"key": "g1", "name": "الأقسام الهندسية"}, {"key": "g2", "name": "المكاتب المساندة"}],
  "hub_style": "icons", "section_order": ["supervision", "docs"],
  "sections": {"docs": {"name": "الفنية", "icon": "engineering", "color": "teal", "group": "g1"}, "safety": {"group": "g2", "hidden": true}},
  "pages": {"65": {"section": "supervision", "icon": "price_change", "label": "الأسعار"}, "72": {"icon": "dashboard"}},
  "page_order": {"supervision": [72, 65, 73]}}');
select pg_temp.check((select value -> 'groups' -> 1 ->> 'name' = 'المكاتب المساندة' and value ->> 'hub_style' = 'icons'
                             and value -> 'pages' -> '65' ->> 'section' = 'supervision'
                        from app_settings where key = 'ui.layout'), 'المدير يحفظ المجموعات ونمط العرض والأيقونات ونقل الصفحات');
select pg_temp.check((select count(*) >= 1 from pg_temp.alog() where action = 'setting.update' and detail ->> 'key' = 'ui.layout'), 'والحفظ مسجّل');
select pg_temp.expect_error($$select public.set_setting('ui.layout', '{"hub_style": "grid"}')$$, 'نمط عرض غير معروف');
select pg_temp.expect_error($$select public.set_setting('ui.layout', '{"groups": [{"key": "x1", "name": "مجموعة"}]}')$$, 'مفتاح مجموعة غير صالح');
select pg_temp.expect_error($$select public.set_setting('ui.layout', '{"groups": [{"key": "g1", "name": "أ"}, {"key": "g1", "name": "ب"}]}')$$, 'مجموعتان بمفتاح واحد');
select pg_temp.expect_error($$select public.set_setting('ui.layout', '{"groups": [{"key": "g1", "name": ""}]}')$$, 'مجموعة بلا اسم');
select pg_temp.expect_error($$select public.set_setting('ui.layout', '{"groups": "g1"}')$$, 'المجموعات قائمة');
select pg_temp.expect_error($$select public.set_setting('ui.layout', '{"sections": {"unknown": {"name": "قسم"}}}')$$, 'قسم غير معروف');
select pg_temp.expect_error($$select public.set_setting('ui.layout', '{"sections": {"docs": {"icon": "Bad Icon"}}}')$$, 'اسم أيقونة غير صالح');
select pg_temp.expect_error($$select public.set_setting('ui.layout', '{"sections": {"docs": {"group": "nogroup"}}}')$$, 'مجموعة غير صالحة');
select pg_temp.expect_error($$select public.set_setting('ui.layout', '{"pages": {"65": {"section": "security"}}}')$$, 'لا نقل إلى الأمن السيبراني');
select pg_temp.expect_error($$select public.set_setting('ui.layout', '{"pages": {"151": {"section": "docs"}}}')$$, 'ولا نقل صفحاته');
select pg_temp.expect_error($$select public.set_setting('ui.layout', '{"pages": {"65": {"section": "nowhere"}}}')$$, 'ولا إلى قسم غير معروف');
select pg_temp.check((select value ->> 'hub_style' = 'icons' from app_settings where key = 'ui.layout'), 'الرفض لا يغيّر المحفوظ');
select pg_temp.as_user('k.staff@test.ly');
select pg_temp.expect_error($$select public.set_setting('ui.layout', '{"hub_style": "cards"}')$$, 'التخصيص للمدير وحده');
select pg_temp.as_user('director.new@test.ly', 'aal2');
select public.set_setting('ui.layout', '{}');
select public.set_setting('ui.motion', '"full"');
select pg_temp.check((select value = '{}'::jsonb from app_settings where key = 'ui.layout'), 'والعودة إلى الافتراضي، وبقية الإعدادات تمر كما كانت');
reset role;
