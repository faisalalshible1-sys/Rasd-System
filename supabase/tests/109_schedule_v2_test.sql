-- اختبارات الترحيل 36: البرنامج الزمني من المقايسة — المقايسة المستوردة، ومعدلات الإنتاجية بتاريخها، والتوليد بالإنتاجية،
-- والعلاقات الأربع وانتظارها و«لا يبدأ قبل»، والحساب الجديد يطابق القديم، وإصدارات البرنامج، والصلاحيات الدقيقة الخمس.
-- يُشغَّل بعد تطبيق 20261127000036_schedule_v2.sql مرتين، وبعد اختبارات الترحيل 35.
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
create or replace function pg_temp.uid(p_email text) returns uuid language sql security definer as $$ select id from auth.users where email = p_email $$;
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
create or replace function pg_temp.alog() returns setof public.audit_log language sql security definer as $$ select * from public.audit_log $$;

update app_settings set value = 'false' where key in ('security.freeze', 'security.require_mfa_all');
update profiles set locked_until = null where email like 'k.%@test.ly' or email like 'u.%@test.ly' or email like 'head%@test.ly';
create temp table ids (k text primary key, v uuid);
grant all on ids to authenticated;
create or replace function pg_temp.id(p_k text) returns uuid language sql as $$ select v from ids where k = p_k $$;
create or replace function pg_temp.item(p_title text) returns uuid language sql security definer as $$
  select id from public.pm_items where project_id = (select v from ids where k = 'p') and title = p_title
$$;
create or replace function pg_temp.dates(p_title text) returns text language sql security definer as $$
  select planned_start || '→' || planned_end from public.pm_items where project_id = (select v from ids where k = 'p') and title = p_title
$$;
grant execute on all functions in schema pg_temp to authenticated, anon;

delete from pm_rates;
delete from projects where assign_no in ('T36-P', 'T36-Q', 'T36-R');

-- ---------------------------------------------------------------- المقايسة المستوردة من ملف
set role authenticated;
select pg_temp.as_user('k.staff@test.ly');
insert into ids select 'p', public.save_project(null, '{"assign_no": "T36-P", "name": "عقد البرنامج من المقايسة", "company": "شركة أ", "department": "supervision"}');
insert into ids select 'q', public.save_project(null, '{"assign_no": "T36-Q", "name": "عقد آخر للبرنامج", "company": "شركة ب", "department": "restoration"}');
select pg_temp.as_user('k.headtech@test.ly');
insert into ids select 'b', public.save_boq(null, jsonb_build_object(
  'title', 'مقايسة مستوردة', 'project_id', pg_temp.id('p'), 'source', 'import', 'source_file', 'مقايسة المدرسة.xlsx',
  'lines', jsonb_build_array(
    jsonb_build_object('code', '1.1', 'desc', 'أعمال الحفر: حفر خنادق للأساسات', 'unit', 'م٣', 'price', 35, 'qty', 240),
    jsonb_build_object('code', '1.2', 'desc', 'ردم بالتربة المختارة', 'unit', 'م3', 'price', 22.5, 'qty', 180),
    jsonb_build_object('code', '2.1', 'desc', 'خرسانة مسلحة للقواعد', 'unit', 'م 3', 'price', 950, 'qty', 60),
    jsonb_build_object('code', '3.1', 'desc', 'تنظيف نهائي للموقع', 'unit', 'مقطوعية', 'price', 2500, 'qty', 1))));
select pg_temp.check((select source = 'import' and source_file = 'مقايسة المدرسة.xlsx' and line_count = 4 and total = 8400 + 4050 + 57000 + 2500
                        from boq_sheets where id = pg_temp.id('b')),
                     'المقايسة المستوردة تُحفظ بمصدرها واسم ملفها وبنودها الحرة');
select pg_temp.check((select detail ->> 'source' = 'import' and detail ->> 'file' = 'مقايسة المدرسة.xlsx' from pg_temp.alog()
                       where action = 'boq.create' and project_id = pg_temp.id('p') order by id desc limit 1),
                     'والاستيراد مسجّل في سجل التدقيق باسم الملف');
insert into ids select 'b2', public.save_boq(null, '{"title": "مقايسة من المُعِدّ", "lines": []}');
select pg_temp.check((select source = 'builder' and source_file = '' from boq_sheets where id = pg_temp.id('b2')), 'ومقايسة المُعِدّ مصدرها المُعِدّ');
select pg_temp.expect_error($$select public.save_boq(null, '{"title": "مصدر غريب", "source": "email"}')$$, 'مصدر غير معروف');

-- ---------------------------------------------------------------- معدلات الإنتاجية
select pg_temp.check(public.pm_unit_norm('م٣') = 'م3' and public.pm_unit_norm('م 3') = 'م3' and public.pm_unit_norm('م.ط') = 'مط'
                     and public.pm_text_norm('أعمال الحفرة') = 'اعمال الحفره', 'تطبيع الوحدة والنص للمطابقة');
select pg_temp.as_user('k.contracts@test.ly');
select pg_temp.expect_error($$select public.save_pm_rate('{"unit": "م3", "rate": 40}')$$, 'مكتب العقود لا يعتمد المعدلات');
select pg_temp.as_user('k.headtech@test.ly');
insert into ids select 'r1', public.save_pm_rate('{"unit": "م3", "rate": 30, "label": "أعمال ترابية عامة", "valid_from": "2026-01-01"}');
insert into ids select 'r2', public.save_pm_rate('{"unit": "م3", "keyword": "حفر", "rate": 50, "label": "حفر آلي", "valid_from": "2026-01-01"}');
insert into ids select 'r3', public.save_pm_rate('{"unit": "م3", "keyword": "خرسانه مسلحه", "rate": 12, "valid_from": "2026-01-01"}');
select pg_temp.expect_error($$select public.save_pm_rate('{"unit": "م3", "rate": 0}')$$, 'المعدل صفر');
select pg_temp.expect_error($$select public.save_pm_rate('{"unit": " ", "rate": 5}')$$, 'بلا وحدة');
reset role;
select pg_temp.check(public.pm_rate_for('م٣', 'أعمال الحفر: حفر خنادق للأساسات') = 50
                     and public.pm_rate_for('م3', 'ردم بالتربة المختارة') = 30
                     and public.pm_rate_for('م 3', 'خرسانة مسلحة للقواعد') = 12
                     and public.pm_rate_for('م2', 'حفر') is null,
                     'المعدل بالوحدة وأطول كلمة يحويها الوصف، أو المعدل العام للوحدة');
select pg_temp.check(public.pm_rate_days('م3', 'حفر خنادق', 240) = 5 and public.pm_rate_days('م3', 'ردم', 181) = 7
                     and public.pm_rate_days('م3', 'ردم', 0) is null and public.pm_rate_days('عدد', 'أبواب', 10) is null,
                     'المدة = ⌈الكمية ÷ المعدل⌉، ولا مدة دون كمية أو معدل');
set role authenticated;
-- إصدار جديد للمعدل: السابق يبقى في السجل، والمؤجل لا يسري قبل تاريخه
insert into ids select 'r4', public.save_pm_rate('{"unit": "م3", "keyword": "حفر", "rate": 60, "valid_from": "2026-06-01", "note": "معدات جديدة"}');
insert into ids select 'r5', public.save_pm_rate(jsonb_build_object('unit', 'م3', 'keyword', 'حفر', 'rate', 80, 'valid_from', (current_date + 30)::text));
reset role;
select pg_temp.check(public.pm_rate_for('م3', 'حفر') = 60 and (select count(*) = 3 from pm_rates where keyword = 'حفر'),
                     'الإصدار الساري هو الأحدث الذي بلغ تاريخه، والسابقة باقية في السجل');
select pg_temp.check((select detail ->> 'previous' = '50.000' and detail ->> 'rate' = '60.000' from pg_temp.alog()
                       where action = 'pm.rate_save' order by id desc offset 1 limit 1),
                     'وتعديل المعدل مسجّل بقيمته السابقة');
set role authenticated;
insert into ids select 'r6', public.save_pm_rate('{"unit": "م3", "keyword": "ردم", "rate": 45, "active": false, "valid_from": "2026-01-01"}');
reset role;
select pg_temp.check(public.pm_rate_for('م3', 'ردم') = 30, 'المعدل غير المفعّل لا يُستعمل');
set role authenticated;
select pg_temp.expect_error(format($$select public.delete_pm_rate(%L)$$, pg_temp.id('r6')), 'رئيس الشؤون الفنية لا يحذف قيداً');
select pg_temp.as_user('director.new@test.ly', 'aal2');
select from public.delete_pm_rate(pg_temp.id('r6'));
select pg_temp.check(not exists (select 1 from pm_rates where id = pg_temp.id('r6'))
                     and exists (select 1 from pg_temp.alog() where action = 'pm.rate_delete'), 'المدير يحذف قيداً خاطئاً ويبقى أثره');
select pg_temp.as_user('headrest@test.ly');
select pg_temp.check((select count(*) from pm_rates) = 0, 'قسم الترميم لا يقرأ المعدلات');
select pg_temp.as_user('k.headtech@test.ly');
select pg_temp.check((select count(*) from pm_rates) = 5, 'والشؤون الفنية تقرؤها');

-- ---------------------------------------------------------------- التوليد بالإنتاجية
select from public.approve_boq(pg_temp.id('b'), true);
select pg_temp.check((select (v -> 'by_rate')::int = 3 from (select public.pm_plan_preview(pg_temp.id('p'), 60) v) x),
                     'المعاينة: ثلاثة بنود مدتها بالإنتاجية والرابع بالقيمة');
select from public.pm_plan_generate(pg_temp.id('p'), '2026-03-01', 60);
select pg_temp.check((select duration_days = 4 from pm_items where project_id = pg_temp.id('p') and code = '1.1')
                     and (select duration_days = 6 from pm_items where project_id = pg_temp.id('p') and code = '1.2')
                     and (select duration_days = 5 from pm_items where project_id = pg_temp.id('p') and code = '2.1'),
                     'الحفر 240÷60=4 أيام، والردم ⌈180÷30⌉=6، والخرسانة 60÷12=5');

-- ---------------------------------------------------------------- الحساب الجديد يطابق القديم دون علاقات جديدة
reset role;
create or replace function pg_temp.recalc_old(p_project uuid) returns void language plpgsql as $$
declare
  v_start date; ph record; it record; v_pstart date; v_pend date; v_prev date; v_base date; v_s date; v_ends jsonb := '{}';
begin
  select start_date into v_start from public.pm_plans where project_id = p_project;
  for it in select i.id, i.duration_days, i.offset_days, i.depends_on, i.planned_end from public.pm_items i
             where i.project_id = p_project and i.phase_id is null order by i.sort, i.created_at loop
    if it.duration_days is null then v_ends := v_ends || jsonb_build_object(it.id::text, it.planned_end); continue; end if;
    v_base := greatest(v_start, coalesce((v_ends ->> it.depends_on::text)::date, v_start));
    v_s := v_base + it.offset_days;
    update public.pm_items set planned_start = v_s, planned_end = v_s + it.duration_days where id = it.id;
    v_ends := v_ends || jsonb_build_object(it.id::text, v_s + it.duration_days);
  end loop;
  for ph in select id, lag_days from public.pm_phases where project_id = p_project order by sort, created_at loop
    v_pstart := case when v_prev is null then v_start else greatest(v_start, v_prev + ph.lag_days) end;
    v_pend := v_pstart;
    for it in select i.id, i.duration_days, i.offset_days, i.depends_on, i.planned_end from public.pm_items i
               where i.project_id = p_project and i.phase_id = ph.id order by i.sort, i.created_at loop
      if it.duration_days is null then v_pend := greatest(v_pend, it.planned_end); v_ends := v_ends || jsonb_build_object(it.id::text, it.planned_end); continue; end if;
      v_base := greatest(v_pstart, coalesce((v_ends ->> it.depends_on::text)::date, v_pstart));
      v_s := v_base + it.offset_days;
      update public.pm_items set planned_start = v_s, planned_end = v_s + it.duration_days where id = it.id;
      v_ends := v_ends || jsonb_build_object(it.id::text, v_s + it.duration_days);
      v_pend := greatest(v_pend, v_s + it.duration_days);
    end loop;
    v_prev := v_pend;
  end loop;
end $$;
-- بنود إضافية بتبعيات وإزاحات وفاصل مرحلة كما تكتبها النسخة السابقة من التطبيق (depends_on)
set role authenticated;
select pg_temp.as_user('k.headtech@test.ly');
insert into ids select 'ph2', public.save_pm_phase(null, jsonb_build_object('project_id', pg_temp.id('p'), 'name', 'مرحلة التشطيبات', 'lag_days', 3));
insert into ids select 'x0', public.save_pm_item(null, jsonb_build_object('project_id', pg_temp.id('p'), 'title', 'نشاط خارج المراحل', 'duration_days', 5));
insert into ids select 'x1', public.save_pm_item(null, jsonb_build_object('project_id', pg_temp.id('p'), 'title', 'أعمال تحضيرية', 'duration_days', 3,
  'phase_id', pg_temp.id('ph2')));
insert into ids select 'x2', public.save_pm_item(null, jsonb_build_object('project_id', pg_temp.id('p'), 'title', 'تجهيز الموقع', 'duration_days', 4,
  'offset_days', 2, 'depends_on', pg_temp.id('x1'), 'phase_id', pg_temp.id('ph2')));
insert into ids select 'x3', public.save_pm_item(null, jsonb_build_object('project_id', pg_temp.id('p'), 'title', 'دهانات', 'duration_days', 6,
  'offset_days', 1, 'phase_id', pg_temp.id('ph2')));
reset role;
create temp table before_new as select id, planned_start, planned_end from pm_items where project_id = pg_temp.id('p');
select pg_temp.recalc_old(pg_temp.id('p'));
create temp table by_old as select id, planned_start, planned_end from pm_items where project_id = pg_temp.id('p');
select from public.pm_plan_recalc(pg_temp.id('p'));
select pg_temp.check((select count(*) = 0 from pm_items i join by_old o using (id)
                       where (i.planned_start, i.planned_end) is distinct from (o.planned_start, o.planned_end))
                     and (select count(*) = 0 from pm_items i join before_new b using (id)
                           where (i.planned_start, i.planned_end) is distinct from (b.planned_start, b.planned_end)),
                     'الحساب الجديد يعطي التواريخ نفسها للتبعيات والإزاحات وفواصل المراحل القديمة');

-- ---------------------------------------------------------------- العلاقات الأربع والانتظار و«لا يبدأ قبل»
set role authenticated;
select pg_temp.as_user('k.headtech@test.ly');
insert into ids select 'a', public.save_pm_item(null, jsonb_build_object('project_id', pg_temp.id('p'), 'title', 'نشاط أ', 'duration_days', 10));
insert into ids select 'bb', public.save_pm_item(null, jsonb_build_object('project_id', pg_temp.id('p'), 'title', 'نشاط ب', 'duration_days', 4));
-- نهاية←بداية بانتظار يومين: ب يبدأ بعد نهاية أ بيومين
insert into ids select 'l1', public.save_pm_link(null, jsonb_build_object('pred_id', pg_temp.id('a'), 'succ_id', pg_temp.id('bb'), 'kind', 'FS', 'lag_days', 2));
select pg_temp.check((select b.planned_start = a.planned_end + 2 from pm_items a, pm_items b where a.id = pg_temp.id('a') and b.id = pg_temp.id('bb')),
                     'نهاية←بداية: البداية = نهاية السابق + الانتظار');
select from public.save_pm_link(pg_temp.id('l1'), '{"kind": "SS", "lag_days": 3}');
select pg_temp.check((select b.planned_start = a.planned_start + 3 from pm_items a, pm_items b where a.id = pg_temp.id('a') and b.id = pg_temp.id('bb')),
                     'بداية←بداية: البداية = بداية السابق + الانتظار');
select from public.save_pm_link(pg_temp.id('l1'), '{"kind": "FF", "lag_days": 1}');
select pg_temp.check((select b.planned_end = a.planned_end + 1 from pm_items a, pm_items b where a.id = pg_temp.id('a') and b.id = pg_temp.id('bb')),
                     'نهاية←نهاية: النهاية = نهاية السابق + الانتظار');
select from public.save_pm_link(pg_temp.id('l1'), '{"kind": "SF", "lag_days": 6}');
select pg_temp.check((select b.planned_end = a.planned_start + 6 from pm_items a, pm_items b where a.id = pg_temp.id('a') and b.id = pg_temp.id('bb')),
                     'بداية←نهاية: النهاية = بداية السابق + الانتظار');
select from public.save_pm_link(pg_temp.id('l1'), '{"kind": "FS", "lag_days": -3}');
select pg_temp.check((select b.planned_start = a.planned_end - 3 from pm_items a, pm_items b where a.id = pg_temp.id('a') and b.id = pg_temp.id('bb')),
                     'والانتظار السالب تداخل');
select from public.save_pm_item(pg_temp.id('bb'), '{"start_not_before": "2027-01-10"}');
select pg_temp.check((select planned_start = '2027-01-10' and start_not_before = '2027-01-10' from pm_items where id = pg_temp.id('bb')),
                     '«لا يبدأ قبل» يؤخر البداية إليه');
select from public.save_pm_item(pg_temp.id('bb'), '{"start_not_before": null}');
select pg_temp.expect_error(format($$select public.save_pm_link(null, jsonb_build_object('pred_id', %L, 'succ_id', %L))$$, pg_temp.id('bb'), pg_temp.id('a')),
                            'السابق يأتي بعد التالي في الترتيب');
select pg_temp.expect_error(format($$select public.save_pm_link(null, jsonb_build_object('pred_id', %L, 'succ_id', %L))$$, pg_temp.id('a'), pg_temp.id('bb')),
                            'علاقة مكررة');
select pg_temp.expect_error(format($$select public.save_pm_link(%L, '{"kind": "XY"}')$$, pg_temp.id('l1')), 'نوع علاقة غير معروف');
insert into ids select 'qi', public.save_pm_item(null, jsonb_build_object('project_id', pg_temp.id('q'), 'title', 'نشاط في عقد آخر', 'duration_days', 3));
select pg_temp.expect_error(format($$select public.save_pm_link(null, jsonb_build_object('pred_id', %L, 'succ_id', %L))$$, pg_temp.id('a'), pg_temp.id('qi')),
                            'علاقة بين عقدين');
select pg_temp.check((select count(*) = 5 from pg_temp.alog() where action in ('pm.link_add', 'pm.link_update') and project_id = pg_temp.id('p')),
                     'العلاقات مسجّلة في سجل التدقيق');
-- حذف علاقة مُرحَّلة من «يتبع البند» يزيلها معها
select from public.delete_pm_link((select id from pm_item_links where pred_id = pg_temp.id('x1') and succ_id = pg_temp.id('x2')));
select pg_temp.check((select depends_on is null from pm_items where id = pg_temp.id('x2')), 'حذف العلاقة يزيل «يتبع البند» المقابلة');

-- ---------------------------------------------------------------- الصلاحيات الدقيقة
select pg_temp.as_user('director.new@test.ly', 'aal2');
select pg_temp.check(public.grant_scope_ok('docs:pm_view') and public.grant_scope_ok('docs:pm_add') and public.grant_scope_ok('docs:pm_duration')
                     and public.grant_scope_ok('docs:pm_dates') and public.grant_scope_ok('docs:pm_approve') and not public.grant_scope_ok('docs:pm_other'),
                     'نطاقات الصلاحيات الخمس مقبولة');
select from public.set_user_grants(pg_temp.uid('k.qa@test.ly'), array['docs:pm_duration']);
select pg_temp.as_user('k.qa@test.ly');
select pg_temp.check((select count(*) > 0 from pm_items where project_id = pg_temp.id('p')), 'أي صلاحية في البرنامج تُظهره');
select from public.save_pm_item(pg_temp.id('a'), '{"duration_days": 12}');
select pg_temp.check((select duration_days = 12 from pm_items where id = pg_temp.id('a')), '«تعديل المدد» يعدّل المدة');
select pg_temp.expect_error(format($$select public.save_pm_item(%L, '{"title": "اسم آخر"}')$$, pg_temp.id('a')), 'ولا يعدّل اسم النشاط');
select pg_temp.expect_error(format($$select public.save_pm_item(%L, '{"offset_days": 5}')$$, pg_temp.id('a')), 'ولا الإزاحة');
select pg_temp.expect_error(format($$select public.save_pm_link(%L, '{"lag_days": 0}')$$, pg_temp.id('l1')), 'ولا العلاقات');
select pg_temp.expect_error(format($$select public.save_pm_item(null, jsonb_build_object('project_id', %L, 'title', 'جديد', 'duration_days', 2))$$, pg_temp.id('p')),
                            'ولا يضيف نشاطاً');
select pg_temp.as_user('director.new@test.ly', 'aal2');
select from public.set_user_grants(pg_temp.uid('k.qa@test.ly'), array['docs:pm_dates']);
select pg_temp.as_user('k.qa@test.ly');
select from public.save_pm_link(pg_temp.id('l1'), '{"lag_days": 0}');
select from public.save_pm_item(pg_temp.id('a'), '{"offset_days": 1}');
select pg_temp.check((select offset_days = 1 from pm_items where id = pg_temp.id('a')), '«تعديل التواريخ» يعدّل الإزاحة والعلاقات');
select pg_temp.expect_error(format($$select public.save_pm_item(%L, '{"duration_days": 9}')$$, pg_temp.id('a')), 'ولا يعدّل المدة');
select pg_temp.as_user('director.new@test.ly', 'aal2');
select from public.set_user_grants(pg_temp.uid('k.qa@test.ly'), array['docs:pm_add']);
select pg_temp.as_user('k.qa@test.ly');
insert into ids select 'n', public.save_pm_item(null, jsonb_build_object('project_id', pg_temp.id('p'), 'title', 'نشاط من صلاحية الإضافة', 'duration_days', 2));
select from public.delete_pm_item(pg_temp.id('n'));
select pg_temp.check(not exists (select 1 from pm_items where id = pg_temp.id('n')), '«إضافة الأنشطة» يضيف ويحذف');
select pg_temp.expect_error(format($$select public.pm_plan_set_status(%L, 'approved')$$, pg_temp.id('p')), 'ولا يعتمد');
select pg_temp.expect_error($$select public.save_pm_rate('{"unit": "م2", "rate": 20}')$$, 'ولا يعتمد المعدلات');

-- ---------------------------------------------------------------- الاعتماد يحفظ الإصدار
select pg_temp.as_user('director.new@test.ly', 'aal2');
select from public.set_user_grants(pg_temp.uid('k.qa@test.ly'), array['docs:pm_approve']);
select pg_temp.as_user('k.qa@test.ly');
select from public.pm_plan_set_status(pg_temp.id('p'), 'approved');
select pg_temp.check((select v.version = 1 and v.source = 'approval' and jsonb_array_length(v.items) = (select count(*) from pm_items where project_id = pg_temp.id('p'))
                             and jsonb_array_length(v.links) >= 1 and v.approved_by = pg_temp.uid('k.qa@test.ly')
                        from pm_plan_versions v where v.project_id = pg_temp.id('p')),
                     '«اعتماد البرنامج» يعتمد، ويُحفظ الإصدار 1 بأنشطته وعلاقاته');
select pg_temp.as_user('k.headtech@test.ly');
select pg_temp.expect_error(format($$select public.save_pm_link(%L, '{"lag_days": 4}')$$, pg_temp.id('l1')), 'لا تعديل للعلاقات بعد الاعتماد');
select pg_temp.as_user('k.qa@test.ly');
select from public.pm_plan_set_status(pg_temp.id('p'), 'draft');
select pg_temp.as_user('k.headtech@test.ly');
select from public.save_pm_item(pg_temp.id('a'), '{"duration_days": 15}');
select pg_temp.as_user('director.new@test.ly', 'aal2');
select from public.pm_plan_set_status(pg_temp.id('p'), 'approved');
select pg_temp.check((select count(*) = 2 from pm_plan_versions where project_id = pg_temp.id('p'))
                     and (select (x ->> 'duration')::int = 12 from pm_plan_versions v, jsonb_array_elements(v.items) x
                           where v.project_id = pg_temp.id('p') and v.version = 1 and x ->> 'title' = 'نشاط أ')
                     and (select (x ->> 'duration')::int = 15 from pm_plan_versions v, jsonb_array_elements(v.items) x
                           where v.project_id = pg_temp.id('p') and v.version = 2 and x ->> 'title' = 'نشاط أ'),
                     'الإصدار الثاني محفوظ، والأول باقٍ كما اعتُمد');
select pg_temp.as_user('k.headsup@test.ly');
select pg_temp.check((select count(*) = 2 from pm_plan_versions where project_id = pg_temp.id('p'))
                     and (select count(*) >= 1 from pm_item_links l join pm_items i on i.id = l.succ_id where i.project_id = pg_temp.id('p')),
                     'القسم المشرف يرى الإصدارات والعلاقات');
select pg_temp.as_user('headrest@test.ly');
select pg_temp.check((select count(*) = 0 from pm_plan_versions where project_id = pg_temp.id('p'))
                     and (select count(*) = 0 from pm_item_links l where l.id = pg_temp.id('l1')),
                     'وقسم الترميم لا يراها');
select pg_temp.as_user('k.headsup@test.ly');
select pg_temp.expect_error($$insert into pm_plan_versions (project_id, version, start_date) values (gen_random_uuid(), 1, current_date)$$,
                            'لا كتابة مباشرة في الإصدارات');
select pg_temp.expect_error($$update pm_item_links set lag_days = 99$$, 'ولا تعديل مباشر للعلاقات');

-- ---------------------------------------------------------------- الإصدارات تتبع البرنامج عند الدمج وفكّه
reset role;
insert into projects (assign_no, name, owner, company, department) values ('T36-R', 'عقد يُدمج فيه', 'المالك', 'شركة ج', 'supervision');
insert into ids select 'r', id from projects where assign_no = 'T36-R';
set app.trusted = 'on';
update projects set merged_into = pg_temp.id('r') where id = pg_temp.id('p');
select pg_temp.check((select count(*) = 2 from pm_plan_versions where project_id = pg_temp.id('r') and origin_project = pg_temp.id('p')),
                     'الإصدارات تتبع البرنامج إلى العقد المدموج فيه');
update projects set merged_into = null where id = pg_temp.id('p');
select pg_temp.check((select count(*) = 2 from pm_plan_versions where project_id = pg_temp.id('p') and origin_project is null), 'وتعود بفكّ الدمج');
set app.trusted = 'off';

-- ---------------------------------------------------------------- التنظيف
delete from user_grants where user_id = pg_temp.uid('k.qa@test.ly');
delete from pm_rates;
select pg_temp.check(true, 'اكتملت اختبارات البرنامج الزمني من المقايسة');
