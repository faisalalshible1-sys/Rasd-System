-- اختبارات الترحيلين 27 و28: لائحة الأسعار الاسترشادية 2026 والبحث فيها ومُعِدّ المقايسات.
-- يُشغَّل بعد تطبيق 20261121000027_prices_boq.sql و20261121000028_price_list_2026.sql مرتين، وبعد اختبارات الترحيل 26.
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
grant execute on all functions in schema pg_temp to authenticated, anon;

update app_settings set value = 'false' where key in ('security.freeze', 'security.require_mfa_all');
create temp table ids (k text primary key, v uuid);
grant all on ids to authenticated;
insert into ids select 'p', id from projects where merged_into is null and department = 'supervision' order by assign_no limit 1;

-- ---------------------------------------------------------------- البيانات
select pg_temp.check((select count(*) = 3332 from price_items where list_id = 'guide-2026'), 'اللائحة 3332 صفاً');
select pg_temp.check((select count(*) = 2887 from price_items where list_id = 'guide-2026' and kind = 'item'), '2887 بنداً مسعّراً');
select pg_temp.check((select count(*) = 6 from (select distinct chapter from price_items where list_id = 'guide-2026') x)
                     and (select jsonb_array_length(chapters) = 6 from price_lists where id = 'guide-2026'), 'ستة فصول');
select pg_temp.check((select bool_and(unit <> '') from price_items where list_id = 'guide-2026' and kind = 'item'), 'لكل بند مسعّر وحدة');
select pg_temp.check((select count(*) = 32 from price_items where list_id = 'guide-2026' and unit_inferred), 'الوحدات المستنتجة معلّمة');
select pg_temp.check((select count(*) = 0 from price_items where list_id = 'guide-2026' and description like '%cid:%'), 'لا رموز بلا ترميز');
select pg_temp.check((select price = 6.5 and unit = 'م2' and section = 'أولاً:- الأعمال التمهيدية' and grp = 'أعمال النظافة'
                             and full_desc like 'تسوية المواقع العامة%— في حدود ± 0.250 م'
                        from price_items where list_id = 'guide-2026' and chapter = 'buildings' and code = '1.1.1.1'),
                     'البند 1.1.1.1: السعر والوحدة والقسم ومجموعة الأعمال والوصف الكامل بسياق البند الأم');
select pg_temp.check((select count(*) = 2 from price_items where list_id = 'guide-2026' and chapter = 'buildings' and code = '1.2.2'),
                     'تكرار 1.2.2 في المصدر محفوظ كما هو');
select pg_temp.check((select count(*) = 0 from price_items i where list_id = 'guide-2026' and parent_seq is not null
                        and not exists (select 1 from price_items p where p.list_id = i.list_id and p.seq = i.parent_seq and p.seq < i.seq)),
                     'البند الأم يسبق البند دائماً');
select pg_temp.check(public.price_norm('الخرسانة المسلّحة أ إ آ ى ٣') = 'الخرسانه المسلحه ا ا ا ي 3', 'توحيد الحروف والأرقام للبحث');

-- ---------------------------------------------------------------- البحث
set role authenticated;
select pg_temp.as_user('k.staff@test.ly');
select pg_temp.check((select count(*) = 3332 from price_items), 'الأعضاء يقرؤون اللائحة');
select pg_temp.check((select array_agg(code order by seq) = array['7.2.2', '7.2.2.1', '7.2.2.2']
                        from public.price_search('guide-2026', '7.2.2', 'buildings', 3)), 'البحث برقم البند يعيد البند وما تحته بالترتيب');
select pg_temp.check((select count(*) = 0 from public.price_search('guide-2026', '7.2.2', 'roads', 10)), 'وضمن الفصل المختار وحده');
select pg_temp.check((select count(*) >= 1 and bool_and(kind = 'item') from public.price_search('guide-2026', 'إنترلوك', null, 10)),
                     'البحث بكلمة بهمزة مختلفة');
select pg_temp.check((select bool_and(search_text like '%خرسانه%' and search_text like '%مسلحه%')
                        from public.price_search('guide-2026', 'الخرسانة المسلحة', null, 300)), 'كل الكلمات مطلوبة');
select pg_temp.check((select count(*) = 5 from public.price_search('guide-2026', 'رخام', null, 5)), 'حد النتائج');
select pg_temp.check((select count(*) = 0 from public.price_search('guide-2026', '  ', null, 5)), 'بحث فارغ');
select pg_temp.expect_error($$insert into price_items (list_id, seq, chapter, kind, description) values ('guide-2026', 99999, 'roads', 'note', 'x')$$,
                            'لا كتابة مباشرة في اللائحة');

-- ---------------------------------------------------------------- المقايسات
insert into ids select 's', public.save_boq(null, jsonb_build_object(
  'title', 'مقايسة اختبار', 'project_id', (select v from ids where k = 'p'), 'ref_no', 'BQ-1',
  'lines', jsonb_build_array(
    jsonb_build_object('seq', (select seq from price_items where list_id = 'guide-2026' and chapter = 'buildings' and code = '1.1.1.1'),
                       'qty', 100, 'notes', 'الموقع الأول', 'price', 1, 'desc', 'وصف مزوّر'),
    jsonb_build_object('desc', 'بند حر للاختبار', 'unit', 'مقطوعية', 'price', 250.5, 'qty', 2),
    jsonb_build_object('seq', (select seq from price_items where list_id = 'guide-2026' and chapter = 'buildings' and code = '7.2.2.1')))));
select pg_temp.check((select line_count = 3 and total = 1151 and list_id = 'guide-2026' and ref_no = 'BQ-1'
                        from boq_sheets where id = (select v from ids where k = 's')),
                     'موظف المكتب يحفظ مقايسة: الإجمالي = 100 × 6.5 + 2 × 250.5 + بند بلا كمية');
select pg_temp.check((select lines -> 0 ->> 'desc' like 'تسوية المواقع العامة%' and (lines -> 0 ->> 'price')::numeric = 6.5
                             and lines -> 0 ->> 'unit' = 'م2' and lines -> 0 ->> 'code' = '1.1.1.1' and lines -> 0 ->> 'notes' = 'الموقع الأول'
                             and lines -> 2 ->> 'qty' is null and lines -> 1 ->> 'unit' = 'مقطوعية'
                        from boq_sheets where id = (select v from ids where k = 's')),
                     'الوصف والوحدة والسعر من اللائحة لا من التطبيق، والبند الحر كما أُدخل');
select pg_temp.check((select count(*) = 1 from pg_temp.alog() where action = 'boq.create' and detail ->> 'title' = 'مقايسة اختبار'),
                     'إنشاء المقايسة مسجّل');
select public.save_boq((select v from ids where k = 's'), jsonb_build_object('title', 'مقايسة اختبار معدّلة', 'show_prices', false,
  'lines', jsonb_build_array(jsonb_build_object('desc', 'بند حر', 'unit', 'عدد', 'price', 10, 'qty', 3))));
select pg_temp.check((select title = 'مقايسة اختبار معدّلة' and not show_prices and line_count = 1 and total = 30
                             and project_id = (select v from ids where k = 'p')
                        from boq_sheets where id = (select v from ids where k = 's')), 'التعديل يستبدل البنود ويُبقي العقد');
select pg_temp.check((select count(*) = 1 from pg_temp.alog() where action = 'boq.update' and detail ->> 'title' = 'مقايسة اختبار معدّلة'),
                     'التعديل مسجّل');
select pg_temp.expect_error($$select public.save_boq(null, jsonb_build_object('title', 'x', 'lines', '[]'::jsonb))$$, 'عنوان قصير');
select pg_temp.expect_error($$select public.save_boq(null, jsonb_build_object('title', 'مقايسة', 'lines', jsonb_build_array(jsonb_build_object('seq', 1))))$$,
                            'العنوان ليس بنداً مسعّراً');
select pg_temp.expect_error($$select public.save_boq(null, jsonb_build_object('title', 'مقايسة', 'lines', jsonb_build_array(jsonb_build_object('qty', 1))))$$,
                            'بند حر بلا وصف');
select pg_temp.expect_error($$select public.save_boq(null, jsonb_build_object('title', 'مقايسة', 'lines', jsonb_build_array(jsonb_build_object('desc', 'بند', 'qty', -1))))$$,
                            'كمية سالبة');
select pg_temp.expect_error($$select public.save_boq(null, jsonb_build_object('title', 'مقايسة', 'list_id', 'none'))$$, 'لائحة غير موجودة');
select pg_temp.expect_error($$update boq_sheets set title = 'مباشر' where true$$, 'لا تعديل مباشر للمقايسات');

select pg_temp.as_user('k.headtech@test.ly');
insert into ids select 't', public.save_boq(null, '{"title": "مقايسة الشؤون الفنية"}');
select pg_temp.check((select count(*) = 1 from boq_sheets where id = (select v from ids where k = 't')), 'رئيس الشؤون الفنية يعدّ مقايسة');
select pg_temp.expect_error($$select public.delete_boq((select v from ids where k = 's'))$$, 'لا يحذف مقايسة غيره');
select public.delete_boq((select v from ids where k = 't'));
select pg_temp.check((select count(*) = 0 from boq_sheets where id = (select v from ids where k = 't')), 'ويحذف مقايسته');

select pg_temp.as_user('k.headsup@test.ly');
select pg_temp.expect_error($$select public.save_boq(null, '{"title": "مقايسة"}')$$, 'رئيس الإشراف لا يعدّ المقايسات');
select pg_temp.check((select count(*) >= 1 from boq_sheets), 'لكنه يقرؤها');
select pg_temp.as_user('auditor@test.ly', 'aal2');
select pg_temp.expect_error($$select public.save_boq(null, '{"title": "مقايسة"}')$$, 'مسؤول الأمن لا يعدّ المقايسات');
select pg_temp.check((select (x ->> 'ok')::boolean from public.sec_posture() x where x ->> 'key' = 'direct_write'),
                     'فحص «الكتابة عبر الدوال المدققة فقط» سليم مع الجداول الجديدة');

-- ---------------------------------------------------------------- الدمج (مباشرة في الجدول؛ دالتا الدمج والفك مختبرتان في 50_contracts)
reset role;
set app.trusted = 'on';
insert into ids select 'q', id from projects where merged_into is null and department = 'supervision' and id <> (select v from ids where k = 'p')
 order by assign_no limit 1;
update projects set merged_into = (select v from ids where k = 'q') where id = (select v from ids where k = 'p');
select pg_temp.check((select project_id = (select v from ids where k = 'q') and origin_project = (select v from ids where k = 'p')
                        from boq_sheets where id = (select v from ids where k = 's')), 'المقايسة تتبع العقد عند الدمج');
update projects set merged_into = null where id = (select v from ids where k = 'p');
select pg_temp.check((select project_id = (select v from ids where k = 'p') and origin_project is null
                        from boq_sheets where id = (select v from ids where k = 's')), 'وتعود بفكّه');

set role authenticated;
select pg_temp.as_user('director.new@test.ly', 'aal2');
select public.delete_boq((select v from ids where k = 's'));
select pg_temp.check((select count(*) = 1 from pg_temp.alog() where action = 'boq.delete' and detail ->> 'title' = 'مقايسة اختبار معدّلة'),
                     'المدير يحذف أي مقايسة والحذف مسجّل');
reset role;
