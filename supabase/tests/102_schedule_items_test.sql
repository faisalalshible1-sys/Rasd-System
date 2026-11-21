-- اختبارات الترحيل 29: بنود الجدول الزمني لكل مشروع (الحفظ والصلاحيات والإنشاء من أعمال العقد والترتيب والدمج).
-- يُشغَّل بعد تطبيق 20261121000029_schedule_items.sql مرتين، وبعد اختبارات الترحيلين 27 و28.
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
update profiles set locked_until = null where email = 'k.qa@test.ly';
create temp table ids (k text primary key, v uuid);
grant all on ids to authenticated;

-- عقد جديد للإشراف بعملين، وبرنامجه الزمني
set role authenticated;
select pg_temp.as_user('k.staff@test.ly');
insert into ids select 'p', public.save_project(null, '{"assign_no": "T-29", "name": "عقد اختبار الجدول الزمني", "company": "شركة البنود", "department": "supervision"}');
insert into ids select 'w1', public.save_work(null, (select v from ids where k = 'p'), 'أعمال الحفر والردم', 'شركة البنود', '1', '');
insert into ids select 'w2', public.save_work(null, (select v from ids where k = 'p'), 'الأعمال الخرسانية', 'شركة البنود', '2', '');

select pg_temp.expect_error($$select public.pm_items_from_works((select v from ids where k = 'p'))$$, 'لا إنشاء من الأعمال قبل تواريخ البرنامج الزمني');
select public.save_project_schedule((select v from ids where k = 'p'), '{"start_date": "2026-01-01", "end_date": "2026-12-31"}');

-- ---------------------------------------------------------------- الإنشاء من أعمال العقد
select pg_temp.check(public.pm_items_from_works((select v from ids where k = 'p')) = 3, 'بند لكل عمل من أعمال العقد (والعمل الأول المنشأ مع العقد)');
select pg_temp.check(public.pm_items_from_works((select v from ids where k = 'p')) = 0, 'ولا يتكرر عند إعادة الإنشاء');
select pg_temp.check((select array_agg(title order by sort) = array['عقد اختبار الجدول الزمني', 'أعمال الحفر والردم', 'الأعمال الخرسانية']
                             and bool_and(planned_start = '2026-01-01' and planned_end = '2026-12-31' and progress = 0 and work_id is not null)
                        from pm_items where project_id = (select v from ids where k = 'p')),
                     'بأسماء الأعمال وترتيبها وتاريخي البرنامج الزمني للعقد');
select pg_temp.check((select count(*) = 1 from pg_temp.alog() where action = 'pm.items_from_works' and project_id = (select v from ids where k = 'p')
                        and (detail ->> 'items')::int = 3), 'الإنشاء مسجّل');

-- ---------------------------------------------------------------- الحفظ
insert into ids select 'i', public.save_pm_item(null, jsonb_build_object('project_id', (select v from ids where k = 'p'),
  'title', 'التشطيبات', 'code', '3', 'planned_start', '2026-06-01', 'planned_end', '2026-09-30', 'weight', 40));
select pg_temp.check((select title = 'التشطيبات' and weight = 40 and progress = 0
                             and sort > (select max(sort) from pm_items where project_id = (select v from ids where k = 'p') and id <> x.id)
                        from pm_items x where id = (select v from ids where k = 'i')), 'بند يدوي جديد في آخر القائمة');
select pg_temp.check((select count(*) = 1 from pg_temp.alog() where action = 'pm.item_add' and detail ->> 'title' = 'التشطيبات'), 'الإضافة مسجّلة');
select pg_temp.expect_error($$select public.save_pm_item(null, jsonb_build_object('project_id', (select v from ids where k = 'p'), 'title', 'بند',
  'planned_start', '2026-05-01', 'planned_end', '2026-04-01'))$$, 'النهاية المخططة قبل البداية');
select pg_temp.expect_error($$select public.save_pm_item(null, jsonb_build_object('project_id', (select v from ids where k = 'p'), 'title', 'بند'))$$,
                            'بند بلا تواريخ مخططة');
select pg_temp.expect_error($$select public.save_pm_item(null, jsonb_build_object('project_id', (select v from ids where k = 'p'), 'title', 'بند',
  'planned_start', '2026-01-01', 'planned_end', '2026-02-01', 'progress', 120))$$, 'نسبة إنجاز فوق 100');
select pg_temp.expect_error($$select public.save_pm_item(null, jsonb_build_object('project_id', (select v from ids where k = 'p'), 'title', 'بند',
  'planned_start', '2026-01-01', 'planned_end', '2026-02-01', 'weight', 0))$$, 'وزن صفري');
select pg_temp.expect_error($$select public.save_pm_item(null, jsonb_build_object('project_id', (select v from ids where k = 'p'), 'title', 'بند',
  'planned_start', '2026-01-01', 'planned_end', '2026-02-01', 'work_id', (select id from contract_works where project_id <> (select v from ids where k = 'p') limit 1)))$$,
  'عمل من عقد آخر');
select pg_temp.expect_error($$select public.save_pm_item(null, jsonb_build_object('project_id', (select v from ids where k = 'p'), 'title', 'بند',
  'planned_start', '2026-01-01', 'planned_end', '2026-02-01', 'progress', 50, 'actual_start', '2026-01-02', 'actual_end', '2026-01-20'))$$,
  'نهاية فعلية قبل اكتمال البند');
select pg_temp.expect_error($$insert into pm_items (project_id, title, planned_start, planned_end) values ((select v from ids where k = 'p'), 'مباشر', '2026-01-01', '2026-01-02')$$,
                            'لا كتابة مباشرة');

-- ---------------------------------------------------------------- تحديث الإنجاز لمن يحدّث سجل التقدم
select pg_temp.as_user('k.qa@test.ly');
select public.save_pm_item((select v from ids where k = 'i'), jsonb_build_object('title', 'التشطيبات', 'code', '3', 'planned_start', '2026-06-01',
  'planned_end', '2026-09-30', 'weight', 40, 'progress', 35.5, 'actual_start', '2026-06-03', 'notes', 'تأخر توريد البلاط'));
select pg_temp.check((select progress = 35.5 and actual_start = '2026-06-03' and notes = 'تأخر توريد البلاط' and updated_by = (select id from profiles where email = 'k.qa@test.ly')
                        from pm_items where id = (select v from ids where k = 'i')), 'مكتب التخطيط يحدّث الإنجاز والتاريخ الفعلي والملاحظات');
select pg_temp.check((select count(*) = 1 from pg_temp.alog() where action = 'pm.item_update' and detail -> 'changes' ? 'progress'), 'والتحديث مسجّل بالتغييرات');
select pg_temp.expect_error($$select public.save_pm_item((select v from ids where k = 'i'), jsonb_build_object('title', 'التشطيبات', 'code', '3',
  'planned_start', '2026-05-01', 'planned_end', '2026-09-30', 'weight', 40, 'progress', 40))$$, 'لكنه لا يغيّر التواريخ المخططة');
select pg_temp.expect_error($$select public.save_pm_item(null, jsonb_build_object('project_id', (select v from ids where k = 'p'), 'title', 'بند',
  'planned_start', '2026-01-01', 'planned_end', '2026-02-01'))$$, 'ولا يضيف بنوداً');
select pg_temp.expect_error($$select public.delete_pm_item((select v from ids where k = 'i'))$$, 'ولا يحذفها');

select pg_temp.as_user('k.headsup@test.ly');
select public.save_pm_item((select v from ids where k = 'i'), jsonb_build_object('title', 'التشطيبات النهائية', 'code', '3', 'planned_start', '2026-06-01',
  'planned_end', '2026-10-15', 'weight', 40, 'progress', 100, 'actual_start', '2026-06-03', 'actual_end', '2026-10-01'));
select pg_temp.check((select title = 'التشطيبات النهائية' and planned_end = '2026-10-15' and progress = 100 and actual_end = '2026-10-01'
                        from pm_items where id = (select v from ids where k = 'i')), 'رئيس القسم المشرف يعدّل بيانات البند ويكمله');
select pg_temp.as_user('k.headtech@test.ly');
select pg_temp.expect_error($$select public.save_pm_item(null, jsonb_build_object('project_id', (select v from ids where k = 'p'), 'title', 'بند',
  'planned_start', '2026-01-01', 'planned_end', '2026-02-01'))$$, 'رئيس قسم غير مشرف على العقد لا يضيف بنوداً');
select pg_temp.as_user('auditor@test.ly', 'aal2');
select pg_temp.expect_error($$select public.save_pm_item((select v from ids where k = 'i'), jsonb_build_object('title', 'التشطيبات النهائية', 'code', '3',
  'planned_start', '2026-06-01', 'planned_end', '2026-10-15', 'weight', 40, 'progress', 90))$$, 'مسؤول الأمن لا يحدّث الإنجاز');
select pg_temp.check((select count(*) = 4 from pm_items where project_id = (select v from ids where k = 'p')), 'لكنه يقرأ البنود');

-- ---------------------------------------------------------------- الترتيب والحذف
select pg_temp.as_user('k.staff@test.ly');
select public.reorder_pm_items((select v from ids where k = 'p'),
  (select array_agg(id order by sort desc) from pm_items where project_id = (select v from ids where k = 'p')));
select pg_temp.check((select array_agg(title order by sort) = array['التشطيبات النهائية', 'الأعمال الخرسانية', 'أعمال الحفر والردم', 'عقد اختبار الجدول الزمني']
                        from pm_items where project_id = (select v from ids where k = 'p')), 'الترتيب كما في القائمة المرسلة');
select pg_temp.expect_error($$select public.reorder_pm_items((select v from ids where k = 'p'), array[(select v from ids where k = 'i')])$$,
                            'قائمة ناقصة');
select public.delete_pm_item((select v from ids where k = 'i'));
select pg_temp.check((select count(*) = 3 from pm_items where project_id = (select v from ids where k = 'p'))
                     and (select count(*) = 1 from pg_temp.alog() where action = 'pm.item_delete' and detail ->> 'title' = 'التشطيبات النهائية'),
                     'الحذف مسجّل');
select pg_temp.as_user('auditor@test.ly', 'aal2');
select pg_temp.check((select (x ->> 'ok')::boolean from public.sec_posture() x where x ->> 'key' = 'direct_write'),
                     'فحص «الكتابة عبر الدوال المدققة فقط» سليم مع جدول البنود');

-- ---------------------------------------------------------------- الدمج (مباشرة في الجدول؛ دالتا الدمج والفك مختبرتان في 50_contracts)
reset role;
set app.trusted = 'on';
insert into ids select 'q', id from projects where merged_into is null and department = 'supervision' and id <> (select v from ids where k = 'p')
 order by assign_no limit 1;
update projects set merged_into = (select v from ids where k = 'q') where id = (select v from ids where k = 'p');
select pg_temp.check((select count(*) = 3 from pm_items where project_id = (select v from ids where k = 'q') and origin_project = (select v from ids where k = 'p')),
                     'البنود تتبع العقد عند الدمج');
update projects set merged_into = null where id = (select v from ids where k = 'p');
select pg_temp.check((select count(*) = 3 from pm_items where project_id = (select v from ids where k = 'p') and origin_project is null), 'وتعود بفكّه');
delete from projects where id = (select v from ids where k = 'p');
select pg_temp.check((select count(*) = 0 from pm_items where project_id = (select v from ids where k = 'p')), 'وتُحذف بحذف العقد');
