-- اختبارات الترحيل 30: اعتماد المقايسة، وإعداد البرنامج الزمني من المقايسة المعتمدة (الشؤون الفنية) واعتماده، ومتابعته (الإشراف).
-- يُشغَّل بعد تطبيق 20261122000030_plans_supervision.sql مرتين، وبعد اختبارات الترحيل 29.
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
update profiles set locked_until = null where email like 'k.%@test.ly';
create temp table ids (k text primary key, v uuid);
grant all on ids to authenticated;
create or replace function pg_temp.id(p_k text) returns uuid language sql as $$ select v from ids where k = p_k $$;
create or replace function pg_temp.item(p_seq integer) returns uuid language sql security definer as $$
  select id from public.pm_items where project_id = (select v from ids where k = 'p') and price_seq = p_seq
$$;
create or replace function pg_temp.plan_end() returns integer language sql security definer as $$
  select max(i.planned_end) - pl.start_date from public.pm_items i join public.pm_plans pl on pl.project_id = i.project_id
   where i.project_id = (select v from ids where k = 'p') group by pl.start_date
$$;
grant execute on all functions in schema pg_temp to authenticated, anon;

-- ---------------------------------------------------------------- عقد للإشراف ومقايسته من الشؤون الفنية
set role authenticated;
select pg_temp.as_user('k.staff@test.ly');
insert into ids select 'p', public.save_project(null, '{"assign_no": "T-30", "name": "عقد اختبار البرنامج الزمني", "company": "شركة التنفيذ", "department": "supervision"}');
insert into ids select 'p2', public.save_project(null, '{"assign_no": "T-31", "name": "عقد بلا مقايسة", "company": "شركة أخرى", "department": "supervision"}');
insert into ids select 'p3', public.save_project(null, '{"assign_no": "T-32", "name": "عقد ثالث", "company": "شركة ثالثة", "department": "restoration"}');
insert into ids select 'i3', public.save_pm_item(null, jsonb_build_object('project_id', pg_temp.id('p3'), 'title', 'نشاط في عقد آخر',
  'planned_start', '2026-02-01', 'planned_end', '2026-02-20'));
select pg_temp.check((select status = 'draft' from pm_plans where project_id = pg_temp.id('p3'))
                     and (select duration_days is null and planned_end = '2026-02-20' from pm_items where id = pg_temp.id('i3')),
                     'أول بند ينشئ مسودة البرنامج، والبند بلا مدة يحتفظ بتاريخيه');

select pg_temp.as_user('k.headtech@test.ly');
insert into ids select 'b', public.save_boq(null, jsonb_build_object(
  'title', 'مقايسة عقد الاختبار', 'project_id', pg_temp.id('p'), 'lines', jsonb_build_array(
    jsonb_build_object('seq', (select seq from price_items where list_id = 'guide-2026' and chapter = 'buildings' and code = '1.1.1.1'), 'qty', 1000),
    jsonb_build_object('seq', (select seq from price_items where list_id = 'guide-2026' and chapter = 'buildings' and code = '1.2.1.1'), 'qty', 200),
    jsonb_build_object('seq', (select seq from price_items where list_id = 'guide-2026' and chapter = 'buildings' and code = '3.2.6.5'), 'qty', 40),
    jsonb_build_object('seq', (select seq from price_items where list_id = 'guide-2026' and chapter = 'buildings' and code = '7.2.2.1'), 'qty', 100),
    jsonb_build_object('desc', 'تنظيف نهائي للموقع', 'unit', 'مقطوعية', 'price', 2500, 'qty', 2))));
select pg_temp.check((select status = 'draft' and total = 124730 and line_count = 5 from boq_sheets where id = pg_temp.id('b')),
                     'المقايسة الجديدة مسودة، وإجماليها 124,730');

-- ---------------------------------------------------------------- اعتماد المقايسة
select pg_temp.as_user('k.staff@test.ly');
select pg_temp.expect_error($$select public.approve_boq(pg_temp.id('b'), true)$$, 'موظف مكتب المدير لا يعتمد المقايسة');
select pg_temp.as_user('k.headsup@test.ly');
select pg_temp.expect_error($$select public.approve_boq(pg_temp.id('b'), true)$$, 'رئيس الإشراف لا يعتمد المقايسة');
select pg_temp.as_user('k.headtech@test.ly');
select pg_temp.expect_error($$select public.pm_plan_generate(pg_temp.id('p'), '2026-01-01', 120)$$, 'لا توليد قبل اعتماد المقايسة');
insert into ids select 'b0', public.save_boq(null, '{"title": "مقايسة بلا عقد", "lines": [{"desc": "بند", "unit": "م2", "price": 1, "qty": 1}]}');
select pg_temp.expect_error($$select public.approve_boq(pg_temp.id('b0'), true)$$, 'لا اعتماد لمقايسة غير مربوطة بعقد');
select public.approve_boq(pg_temp.id('b'), true);
select pg_temp.check((select status = 'approved' and approved_by = pg_temp.uid('k.headtech@test.ly') and approved_at is not null
                        from boq_sheets where id = pg_temp.id('b')), 'رئيس الشؤون الفنية يعتمد المقايسة');
select pg_temp.check((select count(*) = 1 from pg_temp.alog() where action = 'boq.approve' and project_id = pg_temp.id('p')), 'الاعتماد مسجّل');
select pg_temp.expect_error($$select public.save_boq(pg_temp.id('b'), jsonb_build_object('title', 'تعديل', 'project_id', pg_temp.id('p')))$$,
                            'المقايسة المعتمدة لا تُعدَّل');
reset role;
select pg_temp.expect_error($$delete from boq_sheets where id = pg_temp.id('b')$$, 'ولا تُحذف حتى مباشرة');
set role authenticated;
select pg_temp.as_user('director.new@test.ly', 'aal2');
select pg_temp.expect_error($$select public.delete_boq(pg_temp.id('b'))$$, 'ولا يحذفها المدير قبل إعادة فتحها');

-- ---------------------------------------------------------------- التوليد: المراحل والمدد
select pg_temp.as_user('k.headsup@test.ly');
select pg_temp.expect_error($$select public.pm_plan_generate(pg_temp.id('p'), '2026-01-01', 120)$$, 'الإشراف لا يعدّ البرنامج الزمني');
select pg_temp.as_user('k.headtech@test.ly');
select pg_temp.expect_error($$select public.pm_plan_generate(pg_temp.id('p2'), '2026-01-01', 120)$$, 'لا توليد لعقد بلا مقايسة معتمدة');
select pg_temp.expect_error($$select public.pm_plan_generate(pg_temp.id('p'), '2026-01-01', 3)$$, 'المدة الإجمالية 7 أيام على الأقل');
select pg_temp.check((select (r ->> 'total_days')::int = 120 and (r ->> 'items')::int = 5 and jsonb_array_length(r -> 'phases') = 4
                             and (r -> 'phases' -> 0 ->> 'days')::int = 15 and (r -> 'phases' -> 0 ->> 'name') = 'الأعمال التمهيدية'
                             and (r -> 'phases' -> 0 -> 'items' -> 0 ->> 'days')::int = 13 and (r -> 'phases' -> 1 ->> 'days')::int = 72
                        from public.pm_plan_preview(pg_temp.id('p'), 120) r)
                     and (select count(*) = 0 from pm_items where project_id = pg_temp.id('p')),
                     'المعاينة تعرض المراحل والمدد المقترحة دون حفظ شيء');
select pg_temp.check((select r = '{"items": 5, "phases": 4, "total_days": 120}'::jsonb
                        from public.pm_plan_generate(pg_temp.id('p'), '2026-01-01', 120) r),
                     'التوليد: 4 مراحل و5 بنود في 120 يوماً');
select pg_temp.check((select array_agg(name order by sort) = array['الأعمال التمهيدية', 'الأعمال الخرسانية',
                              'أعمال تكسيات الحوائط والأرضيات والوزرات', 'بنود أخرى']
                        from pm_phases where project_id = pg_temp.id('p')),
                     'مرحلة لكل قسم من اللائحة بترتيبه، والبنود الحرة في «بنود أخرى»');
-- المرحلة = round(120 × نصيبها)، والبند = round(مدة المرحلة × √(قيمته ÷ أكبر بند في مرحلته))
select pg_temp.check((select array_agg(duration_days order by planned_start, sort) = array[13, 15, 72, 28, 5]
                        from pm_items where project_id = pg_temp.id('p')),
                     'المدد: 13 و15 (التمهيدية 15 يوماً) ثم 72 و28 و5');
select pg_temp.check((select planned_start = '2026-01-01' and planned_end = '2026-01-14' from pm_items where id = pg_temp.item(4))
                     and (select planned_start = '2026-01-16' and planned_end = '2026-03-29' from pm_items where id = pg_temp.item(201))
                     and (select planned_start = '2026-03-29' and planned_end = '2026-04-26' from pm_items where id = pg_temp.item(376)),
                     'البنود متوازية داخل المرحلة، والمراحل متتالية');
select pg_temp.check((select bool_and(source = 'boq' and boq_sheet_id = pg_temp.id('b') and weight is not null and progress = 0)
                        from pm_items where project_id = pg_temp.id('p')), 'بنود المقايسة بمصدرها ووزنها = الكمية × السعر');
select pg_temp.check((select title = 'أعمدة مربعة أو مستطيلة' and unit = 'م3' and qty = 40 and weight = 75230 from pm_items where id = pg_temp.item(201)),
                     'اسم البند وصفه الخاص، بوحدته وكميته');
select pg_temp.check((select status = 'draft' and start_date = '2026-01-01' from pm_plans where project_id = pg_temp.id('p')), 'البرنامج مسودة');
select pg_temp.expect_error($$select public.pm_plan_generate(pg_temp.id('p'), '2026-01-01', 120)$$, 'لا إعادة توليد دون الاستبدال');
select public.pm_plan_generate(pg_temp.id('p'), '2026-01-01', 120, true);
select pg_temp.check((select count(*) = 5 from pm_items where project_id = pg_temp.id('p'))
                     and (select count(*) = 4 from pm_phases where project_id = pg_temp.id('p')), 'الاستبدال لا يكرر البنود ولا المراحل');
select pg_temp.check((select count(*) = 2 from pg_temp.alog() where action = 'pm.plan_generate' and project_id = pg_temp.id('p')), 'التوليد مسجّل');

-- ---------------------------------------------------------------- البرنامج حي: المدد والإزاحة والتبعية والفاصل
select public.save_pm_item(pg_temp.item(19), '{"duration_days": 20}');
select pg_temp.check(pg_temp.plan_end() = 125
                     and (select planned_start = '2026-01-21' and planned_end = '2026-04-03' from pm_items where id = pg_temp.item(201)),
                     'تعديل مدة بند يزيح المراحل التالية والمدة الإجمالية (125 يوماً)');
select public.save_pm_item(pg_temp.item(376), '{"offset_days": 3}');
select pg_temp.check(pg_temp.plan_end() = 128 and (select planned_start = '2026-04-06' from pm_items where id = pg_temp.item(376)),
                     'الإزاحة داخل المرحلة');
insert into ids select 'x', public.save_pm_item(null, jsonb_build_object('project_id', pg_temp.id('p'), 'title', 'أعمال إضافية: سياج مؤقت للموقع',
  'source', 'extra', 'phase_id', (select phase_id from pm_items where id = pg_temp.item(201)), 'duration_days', 10,
  'depends_on', pg_temp.item(201), 'unit', 'م.ط', 'qty', 120));
select pg_temp.check((select planned_start = '2026-04-03' and planned_end = '2026-04-13' and source = 'extra' from pm_items where id = pg_temp.id('x'))
                     and pg_temp.plan_end() = 138,
                     'البند الإضافي يبدأ بعد البند الذي يتبعه، وتمتد مرحلته وما بعدها (138 يوماً)');
select pg_temp.expect_error($$select public.save_pm_item(pg_temp.item(201), jsonb_build_object('depends_on', pg_temp.id('x')))$$,
                            'لا يتبع البند بنداً لاحقاً له');
select pg_temp.expect_error($$select public.save_pm_item(pg_temp.item(201), jsonb_build_object('depends_on', pg_temp.item(201)))$$,
                            'ولا يتبع نفسه');
select pg_temp.expect_error($$select public.save_pm_item(pg_temp.item(201), jsonb_build_object('depends_on', pg_temp.id('i3')))$$,
                            'ولا بنداً من عقد آخر');
select public.save_pm_phase((select phase_id from pm_items where id = pg_temp.item(201)),
                            jsonb_build_object('name', 'الأعمال الخرسانية', 'lag_days', -2));
select pg_temp.check(pg_temp.plan_end() = 136, 'الفاصل السالب يداخل المرحلة مع سابقتها (136 يوماً)');
select pg_temp.expect_error($$select public.delete_pm_phase((select phase_id from pm_items where id = pg_temp.item(201)))$$, 'لا حذف لمرحلة فيها بنود');
insert into ids select 'ph', public.save_pm_phase(null, jsonb_build_object('project_id', pg_temp.id('p'), 'name', 'أعمال ختامية'));
select pg_temp.check((select sort = (select max(sort) from pm_phases where project_id = pg_temp.id('p')) from pm_phases where id = pg_temp.id('ph')),
                     'المرحلة الجديدة في آخر البرنامج');
select public.delete_pm_phase(pg_temp.id('ph'));
select pg_temp.check((select count(*) = 4 from pm_phases where project_id = pg_temp.id('p')), 'حذف المرحلة الفارغة');

-- ---------------------------------------------------------------- لا تكرار لبنود المقايسة المعتمدة
select pg_temp.expect_error($$select public.save_pm_item(null, jsonb_build_object('project_id', pg_temp.id('p'), 'title', 'أعمدة مربعة أو مستطيلة', 'duration_days', 5))$$,
                            'البند الإضافي لا يكرر وصف بند في المقايسة');
select pg_temp.expect_error($$select public.save_pm_item(null, jsonb_build_object('project_id', pg_temp.id('p'), 'title', 'خرسانة الأعمدة', 'price_seq', 201, 'duration_days', 5))$$,
                            'ولا رقمه في اللائحة');
select pg_temp.expect_error($$select public.save_pm_item(null, jsonb_build_object('project_id', pg_temp.id('p'), 'title', 'تنظيف  نهائي للموقع', 'duration_days', 5))$$,
                            'ولا البند الحر في المقايسة (بعد توحيد الكتابة)');
select pg_temp.expect_error($$select public.save_pm_item(null, jsonb_build_object('project_id', pg_temp.id('p'), 'title', 'بند', 'source', 'boq', 'duration_days', 5))$$,
                            'بنود المقايسة تأتي من التوليد وحده');

-- ---------------------------------------------------------------- لا متابعة قبل الاعتماد
select pg_temp.as_user('k.headsup@test.ly');
select pg_temp.expect_error($$select public.save_pm_item(pg_temp.item(201), '{"progress": 10}')$$, 'لا إنجاز قبل اعتماد البرنامج');
select pg_temp.expect_error($$select public.pm_plan_set_status(pg_temp.id('p'), 'approved')$$, 'الإشراف لا يعتمد البرنامج');
select pg_temp.as_user('k.staff@test.ly');
select pg_temp.expect_error($$select public.pm_plan_set_status(pg_temp.id('p'), 'approved')$$, 'ولا موظف مكتب المدير');
select pg_temp.as_user('k.contracts@test.ly');
select pg_temp.expect_error($$select public.save_pm_item(pg_temp.item(201), '{"duration_days": 60}')$$, 'مكتب العقود لا يعدّ البرنامج');

-- ---------------------------------------------------------------- الاعتماد والإحالة إلى الإشراف
select pg_temp.as_user('k.headtech@test.ly');
select public.pm_plan_set_status(pg_temp.id('p'), 'approved');
select pg_temp.check((select status = 'approved' and version = 1 and approved_by = pg_temp.uid('k.headtech@test.ly') from pm_plans where project_id = pg_temp.id('p')),
                     'رئيس الشؤون الفنية يعتمد البرنامج (الإصدار 1)');
select pg_temp.check((select count(*) >= 1 from pg_temp.notes() where user_id = pg_temp.uid('k.headsup@test.ly') and kind = 'plan' and project_id = pg_temp.id('p')),
                     'ويُشعَر رئيس القسم المشرف بالإحالة');
select pg_temp.expect_error($$select public.save_pm_item(pg_temp.item(201), '{"duration_days": 60}')$$, 'البرنامج المعتمد لا يُعدَّل');
select pg_temp.expect_error($$select public.delete_pm_item(pg_temp.id('x'))$$, 'ولا تُحذف بنوده');
select pg_temp.expect_error($$select public.pm_plan_generate(pg_temp.id('p'), '2026-01-01', 120, true)$$, 'ولا يُعاد توليده');
select pg_temp.expect_error($$select public.approve_boq(pg_temp.id('b'), false)$$, 'ولا تُعاد فتح مقايسته');
select pg_temp.expect_error($$select public.save_pm_phase((select phase_id from pm_items where id = pg_temp.item(201)), '{"name": "تعديل"}')$$, 'ولا مراحله');

-- ---------------------------------------------------------------- المتابعة
select pg_temp.as_user('k.headsup@test.ly');
select public.save_pm_item(pg_temp.item(201), '{"progress": 50, "actual_start": "2026-01-20", "notes": "تأخر توريد الحديد"}');
select pg_temp.check((select progress = 50 and actual_start = '2026-01-20' and duration_days = 72 from pm_items where id = pg_temp.item(201)),
                     'رئيس القسم المشرف يسجّل الإنجاز والتاريخ الفعلي');
select pg_temp.check((select count(*) = 1 from pg_temp.alog() where action = 'pm.item_progress' and project_id = pg_temp.id('p')), 'التحديث مسجّل كمتابعة');
select public.save_pm_item(pg_temp.id('x'), '{"not_applicable": true}');
select pg_temp.check((select not_applicable from pm_items where id = pg_temp.id('x')), 'وتحديد بند «لا ينطبق»');
select pg_temp.expect_error($$select public.save_pm_item(pg_temp.item(201), '{"duration_days": 60}')$$, 'والإشراف لا يغيّر المدد');
select pg_temp.expect_error($$select public.save_pm_item(pg_temp.item(201), '{"progress": 60, "actual_end": "2026-02-01"}')$$, 'النهاية الفعلية عند الاكتمال');
select pg_temp.as_user('k.staff@test.ly');
select public.save_pm_item(pg_temp.item(4), '{"progress": 100, "actual_start": "2026-01-02", "actual_end": "2026-01-15"}');
select pg_temp.check((select progress = 100 from pm_items where id = pg_temp.item(4)), 'ومكتب المدير يتابع');
select pg_temp.as_user('k.qa@test.ly');
select pg_temp.expect_error($$select public.save_pm_item(pg_temp.item(201), '{"progress": 55}')$$, 'التخطيط والجودة لا يسجّل الإنجاز');
select pg_temp.as_user('k.headtech@test.ly');
select pg_temp.expect_error($$select public.save_pm_item(pg_temp.item(201), '{"progress": 55}')$$, 'والشؤون الفنية لا تسجّل الإنجاز');

-- ---------------------------------------------------------------- المنح الدقيق
select pg_temp.as_user('director.new@test.ly', 'aal2');
select pg_temp.check(public.grant_scope_ok('pm:plan') and public.grant_scope_ok('pm:track') and public.grant_scope_ok('swot'), 'النطاقان الجديدان مقبولان');
select public.set_user_grants(pg_temp.uid('k.qa@test.ly'), array['pm:track']);
select pg_temp.as_user('k.qa@test.ly');
select public.save_pm_item(pg_temp.item(201), '{"progress": 55}');
select pg_temp.check((select progress = 55 from pm_items where id = pg_temp.item(201)), 'بالمنح «pm:track» يتابع غير المشرف');
select pg_temp.check(not public.can_prepare_plan(pg_temp.id('p')), 'والمتابعة لا تمنح الإعداد');
select pg_temp.as_user('director.new@test.ly', 'aal2');
select public.set_user_grants(pg_temp.uid('k.qa@test.ly'), array['pm:plan']);
select pg_temp.as_user('k.qa@test.ly');
select pg_temp.check(public.can_prepare_plan(pg_temp.id('p')) and not public.can_track_plan(pg_temp.id('p')) and not public.can_approve_plan(pg_temp.id('p')),
                     'والمنح «pm:plan» يمنح الإعداد دون المتابعة والاعتماد');
select pg_temp.as_user('director.new@test.ly', 'aal2');
select public.set_user_grants(pg_temp.uid('k.qa@test.ly'), array[]::text[]);

-- ---------------------------------------------------------------- إعادة الفتح
select pg_temp.as_user('k.headtech@test.ly');
select public.pm_plan_set_status(pg_temp.id('p'), 'draft');
select pg_temp.check((select status = 'draft' and version = 1 from pm_plans where project_id = pg_temp.id('p')), 'إعادة فتح البرنامج للتعديل');
select pg_temp.check((select progress = 55 from pm_items where id = pg_temp.item(201)), 'والإنجاز المسجل باقٍ');
select public.save_pm_item(pg_temp.item(201), '{"duration_days": 60}');
select pg_temp.check(pg_temp.plan_end() = 124, 'التعديل بعد إعادة الفتح يعيد الحساب (124 يوماً)');
select public.approve_boq(pg_temp.id('b'), false);
select pg_temp.check((select status = 'draft' from boq_sheets where id = pg_temp.id('b'))
                     and (select count(*) = 1 from pg_temp.alog() where action = 'boq.reopen'), 'وإعادة فتح المقايسة والبرنامج مسودة');
select public.approve_boq(pg_temp.id('b'), true);
select public.pm_plan_set_status(pg_temp.id('p'), 'approved');
select pg_temp.check((select status = 'approved' and version = 2 from pm_plans where project_id = pg_temp.id('p'))
                     and (select count(*) = 2 from pg_temp.alog() where action = 'pm.plan_approve' and project_id = pg_temp.id('p'))
                     and (select count(*) = 1 from pg_temp.alog() where action = 'pm.plan_reopen' and project_id = pg_temp.id('p')),
                     'الاعتماد الثاني بالإصدار 2، والاعتماد وإعادة الفتح مسجّلان');

-- ---------------------------------------------------------------- لا كتابة مباشرة، والقراءة للأعضاء
select pg_temp.expect_error($$insert into pm_plans (project_id, start_date) values (pg_temp.id('p2'), current_date)$$, 'لا كتابة مباشرة في البرامج');
select pg_temp.expect_error($$update pm_phases set lag_days = 5 where project_id = pg_temp.id('p')$$, 'ولا في المراحل');
select pg_temp.expect_error($$select public.pm_plan_recalc(pg_temp.id('p'))$$, 'ولا استدعاء لدوال الحساب الداخلية');
select pg_temp.expect_error($$select public.pm_plan_draft(pg_temp.id('p'))$$, 'ولا لدالة المسودة');
select pg_temp.as_user('auditor@test.ly', 'aal2');
select pg_temp.check((select count(*) = 1 from pm_plans where project_id = pg_temp.id('p')) and (select count(*) = 4 from pm_phases where project_id = pg_temp.id('p')),
                     'القراءة لكل الأعضاء');
select pg_temp.check((select (x ->> 'ok')::boolean from public.sec_posture() x where x ->> 'key' = 'direct_write'),
                     'فحص «الكتابة عبر الدوال المدققة فقط» سليم مع الجداول الجديدة');
select pg_temp.check((select value ->> 'done' = 'تم' and value ->> 'wip' = 'قيد التنفيذ' and value ->> 'todo' = 'لم يتم' and value ->> 'na' = 'لا ينطبق'
                        from app_settings where key = 'ui.status_labels'), 'أسماء الحالات: تم، قيد التنفيذ، لم يتم، لا ينطبق');

-- ---------------------------------------------------------------- الدمج
reset role;
set app.trusted = 'on';
update projects set merged_into = pg_temp.id('p2') where id = pg_temp.id('p');
select pg_temp.check((select count(*) = 1 from pm_plans where project_id = pg_temp.id('p2') and origin_project = pg_temp.id('p'))
                     and (select count(*) = 4 from pm_phases where project_id = pg_temp.id('p2') and origin_project = pg_temp.id('p')),
                     'البرنامج ومراحله تتبع العقد عند الدمج');
update projects set merged_into = null where id = pg_temp.id('p');
select pg_temp.check((select count(*) = 1 from pm_plans where project_id = pg_temp.id('p') and origin_project is null)
                     and (select count(*) = 4 from pm_phases where project_id = pg_temp.id('p') and origin_project is null), 'وتعود بفكّه');
set app.trusted = 'off';
