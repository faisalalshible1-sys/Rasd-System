-- اختبارات الترحيل 17: «سجل المخاطر ومتابعة المشاريع» 2.3 و«تحليل SWOT» 2.1.
-- يُشغَّل بعد 90_project_tracking_test.sql وبعد تطبيق 20261112000017_registers_v23.sql مرتين.
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
create or replace function pg_temp.as_system() returns void language plpgsql security definer as $$
begin
  perform set_config('request.jwt.claim.sub', '', false);
  perform set_config('request.jwt.claims', '', false);
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
grant execute on all functions in schema pg_temp to authenticated, anon;

-- ---------------------------------------------------------------- الإعدادات
select pg_temp.check((select (value -> 'kpi_min_components')::int = 2 from public.app_settings where key = 'pm.config'),
                     'الحد الأدنى لمكونات التقييم = 2');
select pg_temp.check((select value -> 'project_types' ? 'إزالة الركام والمخلفات والهدم' and value -> 'project_types' ? 'توريد وتركيب'
                        and jsonb_array_length(value -> 'project_types') = 11
                        from public.app_settings where key = 'pm.config'), 'نوعا المشروع الجديدان مرة واحدة رغم التشغيل المكرر');
select pg_temp.check((select value #>> '{framework,version}' = '2.3' from public.app_settings where key = 'pm.config'), 'إصدار الإطار 2.3');

select pg_temp.as_user('director.new@test.ly', 'aal2');
select pg_temp.expect_error($$select public.set_setting('pm.config', (select value from public.app_settings where key = 'pm.config') || '{"kpi_min_components": 5}')$$,
                            'الحد الأدنى أكبر من 4');
select pg_temp.expect_error($$select public.set_setting('pm.config', (select value from public.app_settings where key = 'pm.config') || '{"kpi_min_components": 2.5}')$$,
                            'الحد الأدنى غير صحيح');
select public.set_setting('pm.config', (select value from public.app_settings where key = 'pm.config') || '{"kpi_min_components": 3}');
select pg_temp.check((select (value -> 'kpi_min_components')::int = 3 from public.app_settings where key = 'pm.config'), 'حفظ الحد الأدنى 3');
select public.set_setting('pm.config', (select value from public.app_settings where key = 'pm.config') || '{"kpi_min_components": 2}');
select pg_temp.as_system();

-- ---------------------------------------------------------------- SWOT 2.1
select pg_temp.check((select count(*) = 2 and bool_and(source = 'إفادة إدارة المكتب') and bool_and(department = 'قسم الإشراف والتنسيق')
                        from public.swot_factors where code in ('S11', 'S12')), 'العاملان S11 وS12');
select pg_temp.check((select rating = 3 and importance = 4 and urgency = 3 from public.swot_factors where code = 'S11'), 'تقييم S11 = 3');
select pg_temp.check((select rating = 4 and importance = 5 and urgency = 4 and priority = 20 from public.swot_factors where code = 'S12'), 'تقييم S12 = 4 وأولويته 20');
select pg_temp.check((select internal_factors = array['S11', 'S12', 'S02'] and external_factors = array['T07', 'T04'] and priority = 'high'
                        from public.swot_strategies where code = 'ST6'), 'الاستراتيجية ST6 بعواملها بالترتيب');
select pg_temp.check((select strategy_code = 'ST6' and factors = array['S11', 'S12', 'T07', 'T04'] and start_date = '2026-12-01'
                             and duration_months = 2 and status = 'not_started' and review_cycle = 'شهريًا'
                        from public.swot_actions where code = 'A22'), 'الإجراء A22');
select pg_temp.check((select count(*) = 1 from public.swot_strategies where code = 'ST6')
                     and (select count(*) = 1 from public.swot_actions where code = 'A22'), 'لا تكرار عند إعادة التشغيل');
select pg_temp.check((select value ->> 'version' = '2.1' from public.app_settings where key = 'swot.meta'), 'إصدار التحليل 2.1');

-- ---------------------------------------------------------------- العقود الفعلية: مطابقة رقم العقد
-- 001 = RBCS-006 (بلا برنامج زمني ولا قيمة)، 003 = RBCS-07 (له برنامج زمني وقيمة أدخلهما المستخدم)،
-- 004 و008 = رقم مكرر للعقد 9 (تُتجاوز المطابقة)
update public.projects set contract_no = 'RBCS-006' where assign_no = '001';
update public.projects set contract_no = 'RBCS-07' where assign_no = '003';
update public.projects set contract_no = 'RBCS-009' where assign_no = '004';
update public.projects set contract_no = 'rbcs-9' where assign_no = '008';
update public.pm_projects set display_name = '', location = '', start_date = null
 where project_id = pg_temp.pid('003');
\ir ../migrations/20261112000017_registers_v23.sql
\set QUIET 1

select pg_temp.check((select project_type = 'طرق' and location = 'الصابري ووسط البلاد' and op_status = 'completed'
                             and start_date = '2026-06-13' and end_date = '2026-08-12'
                             and display_name = 'إعادة تأهيل طريق وفتح مسارات – الصابري ووسط البلاد'
                        from public.pm_projects where project_id = pg_temp.pid('001')), 'البرنامج الزمني الفعلي لعقد RBCS-006');
select pg_temp.check((select contract_value = 4823885.75 from public.projects where assign_no = '001'), 'قيمة العقد الفارغة تُملأ');
select pg_temp.check((select project_type = 'طرق' and location = 'وسط البلاد' and start_date = '2026-06-15'
                             and display_name = 'توريد وتركيب حواجز نيوجيرسي ولافتات'
                        from public.pm_projects where project_id = pg_temp.pid('003')),
                     'العقد ذو البرنامج المُدخَل: يبقى النوع، وتُملأ الحقول الفارغة فقط');
select pg_temp.check((select contract_value = 1250000 from public.projects where assign_no = '003'), 'قيمة العقد المُدخلة لا تُستبدل');
select pg_temp.check((select count(*) = 0 from public.pm_projects where project_id in (pg_temp.pid('004'), pg_temp.pid('008'))),
                     'رقم العقد المكرر لا يُطابَق');
select pg_temp.check((select count(*) = 1 from public.pm_projects where project_id = pg_temp.pid('001')), 'لا تكرار للبرنامج الزمني');

-- ---------------------------------------------------------------- حفظ البرنامج الزمني مع الاسم المختصر
select pg_temp.as_user('director.new@test.ly', 'aal2');
select public.save_project_schedule(pg_temp.pid('001'),
  '{"project_type": "طرق", "op_status": "completed", "start_date": "2026-06-13", "end_date": "2026-08-12", "display_name": "طريق الصابري"}');
select pg_temp.check((select display_name = 'طريق الصابري' from public.pm_projects where project_id = pg_temp.pid('001')), 'حفظ الاسم المختصر');
select public.save_project_schedule(pg_temp.pid('001'),
  '{"project_type": "طرق", "op_status": "completed", "start_date": "2026-06-13", "end_date": "2026-08-12", "location": "الصابري"}');
select pg_temp.check((select display_name = 'طريق الصابري' and location = 'الصابري' from public.pm_projects where project_id = pg_temp.pid('001')),
                     'حفظ من إصدار أقدم (بلا اسم مختصر) لا يمحوه');
select pg_temp.expect_error($$select public.save_project_schedule(pg_temp.pid('001'), jsonb_build_object('display_name', repeat('س', 81)))$$,
                            'اسم مختصر أطول من 80 حرفاً');
select pg_temp.as_system();
