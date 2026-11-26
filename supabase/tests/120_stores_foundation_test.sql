-- اختبارات الترحيل 38: قسم المخازن — دور «موظف» وعزله، ونطاقات الصلاحيات، والتهيئة، وسجل الموظفين، والأصناف،
-- والمستندات (مسودة ← مقدَّم ← معتمد ← مرحَّل)، والحجز والاحتياطي الحرج، والصلاحية والصرف بالأقرب انتهاءً،
-- والتحويل والتسوية والعكس، والخدمة الذاتية للموظف، وسجل التدقيق.
-- يُشغَّل بعد تطبيق 20261129000038_stores_foundation.sql مرتين والتراجع عنه وإعادته، وبعد اختبارات الترحيل 37.
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
create or replace function pg_temp.uid(p_email text) returns uuid language sql security definer as $$ select id from auth.users where email = p_email $$;
create or replace function pg_temp.alog() returns setof public.audit_log language sql security definer as $$ select * from public.audit_log $$;
-- قراءة مباشرة دون سياسات للتحقق
create or replace function pg_temp.doc(p_id uuid) returns setof public.st_docs language sql security definer as $$ select * from public.st_docs where id = p_id $$;
create or replace function pg_temp.stock(p_wh uuid, p_item uuid) returns setof public.st_stock language sql security definer as $$
  select * from public.st_stock where warehouse_id = p_wh and item_id = p_item
$$;
create or replace function pg_temp.onhand(p_wh uuid, p_item uuid) returns numeric language sql security definer as $$
  select coalesce((select on_hand from public.st_stock where warehouse_id = p_wh and item_id = p_item), 0)
$$;
create or replace function pg_temp.reserved(p_wh uuid, p_item uuid) returns numeric language sql security definer as $$
  select coalesce((select reserved from public.st_stock where warehouse_id = p_wh and item_id = p_item), 0)
$$;
create or replace function pg_temp.batch(p_wh uuid, p_item uuid, p_exp date) returns numeric language sql security definer as $$
  select coalesce((select sum(qty) from public.st_batches where warehouse_id = p_wh and item_id = p_item and expiry_date = p_exp), 0)
$$;
create or replace function pg_temp.moves(p_doc uuid) returns bigint language sql security definer as $$
  select count(*) from public.st_moves where doc_id = p_doc
$$;
create or replace function pg_temp.item(p_id uuid) returns setof public.st_items language sql security definer as $$ select * from public.st_items where id = p_id $$;

update app_settings set value = 'false' where key in ('security.freeze', 'security.require_mfa_all');
update profiles set locked_until = null where email like 'k.%@test.ly' or email like 'u.%@test.ly' or email like 'head%@test.ly'
                                        or email in ('director.new@test.ly', 'staff.new@test.ly', 'qa@test.ly', 'pending@test.ly');
create temp table ids (k text primary key, v uuid);
grant all on ids to authenticated;
create or replace function pg_temp.id(p_k text) returns uuid language sql as $$ select v from ids where k = p_k $$;
grant execute on all functions in schema pg_temp to authenticated, anon;

-- ---------------------------------------------------------------- البذور
select pg_temp.check((select count(*) = 8 from st_categories) and (select count(*) = 7 from st_units),
                     'التصنيفات الثمانية والوحدات السبع مبدوءة');
select pg_temp.check((select string_agg(code, ',' order by sort) = 'STA,PAP,OFE,FUR,CLN,HOS,MNT,SAF' from st_categories),
                     'رموز التصنيفات بترتيب المستند');
select pg_temp.check((select value = 'true'::jsonb from st_settings where key = 'separation')
                     and (select value = '60'::jsonb from st_settings where key = 'expiry_days'),
                     'فصل المهام مفعّل والتنبيه قبل الانتهاء 60 يوماً');

-- ---------------------------------------------------------------- دور الموظف وعزله
set role authenticated;
select pg_temp.as_user('director.new@test.ly', 'aal2');
select public.set_user_access(pg_temp.uid('pending@test.ly'), 'employee', null, true, 'موظف الخدمة الذاتية');
select pg_temp.check((select role::text = 'employee' and active from profiles where email = 'pending@test.ly'), 'المدير يفعّل حساباً بدور «موظف»');
select pg_temp.expect_error($q$select public.set_user_grants(pg_temp.uid('pending@test.ly'), array['stores:audit'])$q$,
                            'لا تُمنح صلاحيات دقيقة لحساب الموظف');

select pg_temp.as_user('pending@test.ly');
select pg_temp.check(not public.is_member() and not public.writes_allowed(), 'الموظف ليس «عضواً» في بقية المنظومة ولا يكتب فيها');
select pg_temp.check(public.my_sections() = array['manual', 'stores'], 'أقسام الموظف: المخازن والدليل وحدهما');
select pg_temp.check(public.my_units() = '{}' and public.my_forms() = '{}', 'لا وحدات ولا نماذج للموظف');
select pg_temp.check((select count(*) = 1 from profiles), 'الموظف يرى حسابه وحده من الحسابات');
select pg_temp.check((select count(*) = 0 from projects) and (select count(*) = 0 from app_settings), 'لا عقود ولا إعدادات للموظف');
select pg_temp.expect_error($q$select public.next_ref('letter_out', '{}')$q$, 'الموظف لا يولّد أرقاماً إشارية');
select pg_temp.expect_error($q$select public.st_save_department(null, '{"name": "إدارة"}')$q$, 'الموظف لا يهيّئ المخازن');
select pg_temp.check(public.st_my_employee() is null, 'قبل ربطه بسجل موظف لا خدمة ذاتية');

-- ---------------------------------------------------------------- التهيئة وصلاحياتها
select pg_temp.as_user('k.staff@test.ly');
select pg_temp.check(not ('stores' = any (public.my_sections())), 'موظف مكتب المدير لا يرى المخازن تلقائياً');
select pg_temp.expect_error($q$select public.st_save_department(null, '{"name": "الإدارة العامة"}')$q$, 'التهيئة ليست لموظف المكتب');

select pg_temp.as_user('director.new@test.ly', 'aal2');
select pg_temp.check('stores' = any (public.my_sections()), 'المدير يرى المخازن');
select pg_temp.check(not public.grant_scope_ok('stores:keeper:00000000-0000-0000-0000-000000000000'), 'نطاق أمين لمخزن غير موجود مرفوض');
select pg_temp.check(public.grant_scope_ok('stores:admin') and public.grant_scope_ok('stores:manager') and public.grant_scope_ok('stores:audit'),
                     'نطاقات المخازن الثلاثة معروفة');
select public.set_user_grants(pg_temp.uid('u.heritage@test.ly'), array['stores:admin']);
select public.set_user_grants(pg_temp.uid('u.qc@test.ly'), array['stores:manager']);
select public.set_user_grants(pg_temp.uid('u.safetyhead@test.ly'), array['stores:audit']);

select pg_temp.as_user('u.heritage@test.ly');
select pg_temp.check('stores' = any (public.my_sections()) and public.st_staff() and public.st_sees_all(), 'مدير النظام في القسم يراه كله');
insert into ids select 'dep_gen', public.st_save_department(null, '{"name": "الإدارة العامة", "code": "GEN"}');
insert into ids select 'dep_it', public.st_save_department(null, jsonb_build_object('name', 'قسم تقنية المعلومات', 'parent_id', pg_temp.id('dep_gen')));
select pg_temp.expect_error($q$select public.st_save_department(null, '{"name": "الادارة العامة"}')$q$, 'إدارة بالاسم نفسه (بعد توحيد الهمزة) مرفوضة');
select pg_temp.expect_error(format($q$select public.st_save_department(%L, jsonb_build_object('name', 'الإدارة العامة', 'parent_id', %L))$q$,
                                   pg_temp.id('dep_gen'), pg_temp.id('dep_it')), 'لا دورة في شجرة الإدارات');

insert into ids select 'bld', public.st_save_location(null, '{"kind": "building", "name": "المبنى الرئيسي", "code": "B1"}');
insert into ids select 'flr', public.st_save_location(null, jsonb_build_object('kind', 'floor', 'name', 'الطابق الأرضي', 'parent_id', pg_temp.id('bld')));
insert into ids select 'room', public.st_save_location(null, jsonb_build_object('kind', 'room', 'name', 'غرفة 004', 'parent_id', pg_temp.id('flr')));
select pg_temp.expect_error(format($q$select public.st_save_location(null, jsonb_build_object('kind', 'floor', 'name', 'طابق', 'parent_id', %L))$q$,
                                   pg_temp.id('room')), 'الطابق يتبع مبنى');
select pg_temp.expect_error($q$select public.st_save_location(null, '{"kind": "room", "name": "غرفة دون مكان"}')$q$, 'الغرفة تحتاج موقعاً أعلى');

insert into ids select 'main', public.st_save_warehouse(null, jsonb_build_object('code', 'main', 'name', 'المخزن الرئيسي', 'kind', 'main', 'location_id', pg_temp.id('room')));
insert into ids select 'sub', public.st_save_warehouse(null, jsonb_build_object('code', 'SUB1', 'name', 'مخزن الطابق الأول', 'kind', 'sub', 'parent_id', pg_temp.id('main')));
select pg_temp.check((select code = 'MAIN' from st_warehouses where id = pg_temp.id('main')), 'رمز المخزن بحروف كبيرة');
select pg_temp.expect_error(format($q$select public.st_save_warehouse(null, jsonb_build_object('code', 'SUB2', 'name', 'فرعي من فرعي', 'kind', 'sub', 'parent_id', %L))$q$,
                                   pg_temp.id('sub')), 'المخزن الفرعي يتبع مخزناً رئيسياً');
select pg_temp.expect_error($q$select public.st_save_warehouse(null, '{"code": "مخزن", "name": "رمز عربي"}')$q$, 'رمز المخزن لاتيني');

insert into ids select 'unit_dz', public.st_save_unit(null, '{"name": "دزينة"}');
select pg_temp.expect_error($q$select public.st_save_unit(null, '{"name": "قطعه"}')$q$, 'وحدة مكررة بعد التوحيد (قطعة/قطعه)');
insert into ids select 'cat_it', public.st_save_category(null, '{"code": "ITC", "name": "مستلزمات الحاسوب", "kind": "consumable"}');
select pg_temp.expect_error($q$select public.st_save_category(null, '{"code": "x", "name": "رمز قصير"}')$q$, 'رمز التصنيف من حرفين على الأقل');
select public.st_set_settings('{"expiry_days": 30}');
select pg_temp.check((select value = '30'::jsonb from st_settings where key = 'expiry_days'), 'تعديل مدة التنبيه قبل الانتهاء');
select pg_temp.expect_error($q$select public.st_set_settings('{"expiry_days": 5}')$q$, 'مدة التنبيه من 7 إلى 365 يوماً');
select pg_temp.expect_error($q$select public.st_set_settings('{"other": true}')$q$, 'إعداد غير معروف مرفوض');

-- صلاحيات أمناء المخازن بعد إنشاء المخازن
select pg_temp.as_user('director.new@test.ly', 'aal2');
select public.set_user_grants(pg_temp.uid('u.safety@test.ly'), array['stores:keeper:' || pg_temp.id('main')]);
select public.set_user_grants(pg_temp.uid('qa@test.ly'), array['stores:keeper:' || pg_temp.id('sub')]);
select pg_temp.as_user('u.safety@test.ly');
select pg_temp.check(public.st_my_warehouses() = array[pg_temp.id('main')] and public.st_staff() and not public.st_sees_all(),
                     'أمين المخزن الرئيسي يتولى مخزنه وحده');
select pg_temp.expect_error($q$select public.st_set_settings('{"separation": false}')$q$, 'الإعدادات ليست لأمين المخزن');

-- ---------------------------------------------------------------- سجل الموظفين
select pg_temp.as_user('u.heritage@test.ly');
insert into ids select 'emp1', public.st_save_employee(null, jsonb_build_object('emp_no', 'E-100', 'full_name', 'سالم علي المبروك',
  'department_id', pg_temp.id('dep_it'), 'job_title', 'مبرمج', 'profile_id', pg_temp.uid('pending@test.ly')));
insert into ids select 'emp2', public.st_save_employee(null, jsonb_build_object('emp_no', 'E-101', 'full_name', 'فاطمة محمد', 'department_id', pg_temp.id('dep_gen')));
select pg_temp.expect_error($q$select public.st_save_employee(null, '{"emp_no": "e-100", "full_name": "رقم مكرر"}')$q$, 'الرقم الوظيفي لا يتكرر');
select pg_temp.expect_error(format($q$select public.st_save_employee(null, jsonb_build_object('emp_no', 'E-102', 'full_name', 'حساب مكرر', 'profile_id', %L))$q$,
                                   pg_temp.uid('pending@test.ly')), 'الحساب يُربط بموظف واحد');
select pg_temp.check((public.st_import_employees('[{"emp_no": "E-101", "full_name": "فاطمة محمد سالم", "job_title": "محاسبة"},
                                                 {"emp_no": "E-200", "full_name": "عمر الهادي", "department": "إدارة الخدمات العامة"},
                                                 {"emp_no": "E-201", "full_name": "نوري خليفة", "department": "GEN"}]')
                      = '{"rows": 3, "inserted": 2, "updated": 1, "departments": 1}'::jsonb), 'استيراد الموظفين: إضافة وتحديث وإنشاء إدارة');
select pg_temp.check((select full_name = 'فاطمة محمد سالم' and job_title = 'محاسبة' and department_id = pg_temp.id('dep_gen')
                        from st_employees where emp_no = 'E-101'), 'التحديث بالرقم الوظيفي يحفظ الإدارة إن لم تُذكر');
select pg_temp.expect_error($q$select public.st_import_employees('[{"emp_no": "", "full_name": "بلا رقم"}]')$q$, 'الاستيراد يحتاج الرقم الوظيفي');

select pg_temp.as_user('pending@test.ly');
select pg_temp.check(public.st_my_employee() = pg_temp.id('emp1'), 'الحساب المربوط يعرف سجله');
select pg_temp.check((select count(*) = 1 from st_employees), 'الموظف يرى سجله وحده من الموظفين');
select pg_temp.check((select count(*) = 0 from st_locations) and (select count(*) = 0 from st_settings), 'لا مواقع ولا إعدادات للموظف');
-- الموظف لا يرى من جداول المنظومة كلها إلا المسموح له
do $$
declare
  t   text;
  n   bigint;
  bad text := '';
begin
  for t in select c.relname from pg_class c join pg_namespace ns on ns.oid = c.relnamespace
            where ns.nspname = 'public' and c.relkind = 'r' order by 1 loop
    begin
      execute format('select count(*) from public.%I', t) into n;
    exception when insufficient_privilege then
      n := 0;
    end;
    if n > 0 and t not in ('profiles', 'notifications', 'app_releases', 'departments', 'form_defs', 'stages',
                           'st_departments', 'st_warehouses', 'st_categories', 'st_units', 'st_items', 'st_item_units',
                           'st_employees', 'st_docs', 'st_doc_lines') then
      bad := bad || ' ' || t;
    end if;
  end loop;
  perform pg_temp.check(bad = '', 'الموظف لا يرى أي جدول آخر في المنظومة' || bad);
end $$;

select pg_temp.as_user('k.staff@test.ly');
select pg_temp.check((select count(*) = 0 from st_employees) and (select count(*) = 0 from st_warehouses), 'موظف المكتب لا يرى سجل الموظفين ولا المخازن');

-- ---------------------------------------------------------------- الأصناف
select pg_temp.as_user('u.qc@test.ly');
insert into ids select 'u_ream', id from st_units where name = 'رزمة';
insert into ids select 'u_carton', id from st_units where name = 'كرتونة';
insert into ids select 'u_piece', id from st_units where name = 'قطعة';
insert into ids select 'u_box', id from st_units where name = 'علبة';
insert into ids select 'u_pack', id from st_units where name = 'عبوة';
insert into ids select 'a4', public.st_save_item(null, jsonb_build_object('name', 'ورق A4 80 غم', 'category_id', (select id from st_categories where code = 'PAP'),
  'base_unit_id', pg_temp.id('u_ream'), 'min_qty', 10, 'max_qty', 200, 'reorder_qty', 20, 'critical_qty', 5,
  'units', jsonb_build_array(jsonb_build_object('unit_id', pg_temp.id('u_carton'), 'factor', 5))));
insert into ids select 'pen', public.st_save_item(null, jsonb_build_object('name', 'قلم حبر أزرق', 'category_id', (select id from st_categories where code = 'STA'),
  'base_unit_id', pg_temp.id('u_piece'), 'barcode', '6281000000017',
  'units', jsonb_build_array(jsonb_build_object('unit_id', pg_temp.id('u_box'), 'factor', 12))));
insert into ids select 'dis', public.st_save_item(null, jsonb_build_object('name', 'مطهر أسطح', 'category_id', (select id from st_categories where code = 'CLN'),
  'base_unit_id', pg_temp.id('u_pack'), 'tracks_expiry', true));
select pg_temp.check((select code = 'PAP-0001' from pg_temp.item(pg_temp.id('a4'))) and (select code = 'CLN-0001' from pg_temp.item(pg_temp.id('dis'))),
                     'رمز الصنف تلقائي من رمز التصنيف وتسلسله');
select pg_temp.expect_error(format($q$select public.st_save_item(null, jsonb_build_object('name', 'باركود مكرر', 'category_id', %L, 'base_unit_id', %L, 'barcode', '6281000000017'))$q$,
                                   (select id from st_categories where code = 'STA'), pg_temp.id('u_piece')), 'الباركود لا يتكرر');
select pg_temp.expect_error(format($q$select public.st_save_item(null, jsonb_build_object('name', 'حدود خاطئة', 'category_id', %L, 'base_unit_id', %L, 'min_qty', 10, 'max_qty', 5))$q$,
                                   (select id from st_categories where code = 'STA'), pg_temp.id('u_piece')), 'الحد الأقصى لا يقل عن الأدنى');
select pg_temp.check((public.st_import_items('[{"code": "STA-9001", "name": "دباسة مكتبية", "category": "STA", "unit": "قطعة", "min_qty": 2},
                                              {"name": "مناديل ورقية", "category": "النظافة والخدمات", "unit": "رول"}]')
                      = '{"rows": 2, "inserted": 2, "updated": 0, "units": 1}'::jsonb), 'استيراد الأصناف وإنشاء الوحدة الناقصة');
select pg_temp.check((public.st_import_items('[{"code": "sta-9001", "name": "دباسة مكتبية كبيرة", "category": "STA", "unit": "قطعة", "min_qty": 3}]')
                      = '{"rows": 1, "inserted": 0, "updated": 1, "units": 0}'::jsonb), 'إعادة الاستيراد تحدّث بالرمز');
select pg_temp.expect_error($q$select public.st_import_items('[{"name": "صنف", "category": "غير موجود", "unit": "قطعة"}]')$q$, 'التصنيف يجب أن يوجد');

select pg_temp.as_user('u.safety@test.ly');
select pg_temp.expect_error(format($q$select public.st_save_item(null, jsonb_build_object('name', 'صنف', 'category_id', %L, 'base_unit_id', %L))$q$,
                                   (select id from st_categories where code = 'STA'), pg_temp.id('u_piece')), 'أمين المخزن لا ينشئ بطاقات الأصناف');

-- ---------------------------------------------------------------- أرصدة أول المدة: مسودة ← مقدَّم ← معتمد ← مرحَّل
insert into ids select 'ob', public.st_save_doc(null, jsonb_build_object('kind', 'opening', 'warehouse_id', pg_temp.id('main'), 'lines', jsonb_build_array(
  jsonb_build_object('item_id', pg_temp.id('a4'), 'unit_id', pg_temp.id('u_carton'), 'qty', 10),
  jsonb_build_object('item_id', pg_temp.id('pen'), 'qty', 100),
  jsonb_build_object('item_id', pg_temp.id('dis'), 'qty', 20, 'expiry_date', '2027-01-31', 'batch_no', 'L2'),
  jsonb_build_object('item_id', pg_temp.id('dis'), 'qty', 10, 'expiry_date', '2026-12-31', 'batch_no', 'L1'))));
select pg_temp.check((select doc_no ~ '^OB-\d{4}-0001$' and status = 'draft' from pg_temp.doc(pg_temp.id('ob'))), 'رقم أول المدة OB-السنة-0001 ومسودة');
select pg_temp.check((select base_qty = 50 and factor = 5 from st_doc_lines where doc_id = pg_temp.id('ob') and line_no = 1),
                     '10 كراتين = 50 رزمة بالوحدة الأساسية');
select pg_temp.expect_error(format($q$select public.st_save_doc(null, jsonb_build_object('kind', 'receipt', 'warehouse_id', %L, 'lines', jsonb_build_array(jsonb_build_object('item_id', %L, 'qty', 5))))$q$,
                                   pg_temp.id('main'), pg_temp.id('dis')), 'الداخل من صنف بصلاحية يحتاج تاريخها');
select pg_temp.expect_error(format($q$select public.st_save_doc(null, jsonb_build_object('kind', 'receipt', 'warehouse_id', %L, 'lines', jsonb_build_array(jsonb_build_object('item_id', %L, 'qty', -5))))$q$,
                                   pg_temp.id('main'), pg_temp.id('pen')), 'لا كمية سالبة إلا في التسوية');
select pg_temp.expect_error(format($q$select public.st_save_doc(null, jsonb_build_object('kind', 'receipt', 'warehouse_id', %L, 'lines', jsonb_build_array(jsonb_build_object('item_id', %L, 'unit_id', %L, 'qty', 1))))$q$,
                                   pg_temp.id('main'), pg_temp.id('pen'), pg_temp.id('u_carton')), 'وحدة غير معرّفة للصنف مرفوضة');
select pg_temp.as_user('qa@test.ly');
select pg_temp.expect_error(format($q$select public.st_save_doc(null, jsonb_build_object('kind', 'receipt', 'warehouse_id', %L, 'lines', jsonb_build_array(jsonb_build_object('item_id', %L, 'qty', 1))))$q$,
                                   pg_temp.id('main'), pg_temp.id('pen')), 'أمين مخزن آخر لا يحرّك المخزن الرئيسي');
select pg_temp.check((select count(*) = 0 from st_docs where id = pg_temp.id('ob')), 'ولا يرى مستنداته');

select pg_temp.as_user('u.safety@test.ly');
select public.st_doc_action(pg_temp.id('ob'), 'submit');
select pg_temp.expect_error(format($q$select public.st_doc_action(%L, 'approve')$q$, pg_temp.id('ob')), 'أمين المخزن لا يعتمد');
select pg_temp.expect_error(format($q$select public.st_save_doc(%L, '{"warehouse_id": "%s", "lines": []}')$q$, pg_temp.id('ob'), pg_temp.id('main')), 'المقدَّم لا يُعدَّل');
select pg_temp.as_user('u.qc@test.ly');
select pg_temp.expect_error(format($q$select public.st_doc_action(%L, 'return')$q$, pg_temp.id('ob')), 'الإعادة تحتاج سبباً');
select public.st_doc_action(pg_temp.id('ob'), 'approve');
select pg_temp.check((select status = 'approved' and approved_by = pg_temp.uid('u.qc@test.ly') from pg_temp.doc(pg_temp.id('ob')))
                     and pg_temp.onhand(pg_temp.id('main'), pg_temp.id('a4')) = 0, 'الاعتماد لا يغيّر الرصيد');
select pg_temp.as_user('u.safety@test.ly');
select public.st_doc_action(pg_temp.id('ob'), 'post');
select pg_temp.check(pg_temp.onhand(pg_temp.id('main'), pg_temp.id('a4')) = 50 and pg_temp.onhand(pg_temp.id('main'), pg_temp.id('pen')) = 100
                     and pg_temp.onhand(pg_temp.id('main'), pg_temp.id('dis')) = 30, 'الترحيل يضيف الأرصدة بالوحدة الأساسية');
select pg_temp.check(pg_temp.batch(pg_temp.id('main'), pg_temp.id('dis'), '2026-12-31') = 10 and pg_temp.batch(pg_temp.id('main'), pg_temp.id('dis'), '2027-01-31') = 20,
                     'دفعتا الصلاحية مسجّلتان');
select pg_temp.check(pg_temp.moves(pg_temp.id('ob')) = 4 and (select balance_after = 30 from st_moves where doc_id = pg_temp.id('ob') order by id desc limit 1),
                     'سطر في دفتر الحركات لكل أثر بالرصيد بعده');
select pg_temp.expect_error(format($q$select public.st_doc_action(%L, 'cancel', 'خطأ')$q$, pg_temp.id('ob')), 'المرحَّل لا يُلغى');
select pg_temp.expect_error(format($q$select public.st_delete_doc(%L)$q$, pg_temp.id('ob')), 'المرحَّل لا يُحذف');

-- ---------------------------------------------------------------- فصل المهام
select pg_temp.as_user('u.qc@test.ly');
insert into ids select 'rc', public.st_save_doc(null, jsonb_build_object('kind', 'receipt', 'warehouse_id', pg_temp.id('main'), 'party', 'مورد القرطاسية', 'ref_no', 'INV-77',
  'lines', jsonb_build_array(jsonb_build_object('item_id', pg_temp.id('pen'), 'unit_id', pg_temp.id('u_box'), 'qty', 2))));
select public.st_doc_action(pg_temp.id('rc'), 'submit');
select pg_temp.expect_error(format($q$select public.st_doc_action(%L, 'approve')$q$, pg_temp.id('rc')), 'منشئ المستند لا يعتمده (فصل المهام)');
select pg_temp.as_user('director.new@test.ly', 'aal2');
select public.st_doc_action(pg_temp.id('rc'), 'approve');
select pg_temp.as_user('u.safety@test.ly');
select public.st_doc_action(pg_temp.id('rc'), 'post');
select pg_temp.check(pg_temp.onhand(pg_temp.id('main'), pg_temp.id('pen')) = 124 and (select doc_no ~ '^RC-' from pg_temp.doc(pg_temp.id('rc'))),
                     'الوارد: علبتان = 24 قلماً');

-- ---------------------------------------------------------------- الصرف: الحجز والمتاح والاحتياطي الحرج
insert into ids select 'is1', public.st_save_doc(null, jsonb_build_object('kind', 'issue', 'warehouse_id', pg_temp.id('main'), 'employee_id', pg_temp.id('emp1'),
  'lines', jsonb_build_array(jsonb_build_object('item_id', pg_temp.id('a4'), 'unit_id', pg_temp.id('u_carton'), 'qty', 2),
                             jsonb_build_object('item_id', pg_temp.id('pen'), 'unit_id', pg_temp.id('u_box'), 'qty', 1),
                             jsonb_build_object('item_id', pg_temp.id('dis'), 'qty', 15))));
select pg_temp.check((select department_id = pg_temp.id('dep_it') from pg_temp.doc(pg_temp.id('is1'))), 'إدارة المصروف له من سجله');
select public.st_doc_action(pg_temp.id('is1'), 'submit');
select pg_temp.as_user('u.qc@test.ly');
select public.st_doc_action(pg_temp.id('is1'), 'approve');
select pg_temp.check(pg_temp.reserved(pg_temp.id('main'), pg_temp.id('a4')) = 10 and pg_temp.reserved(pg_temp.id('main'), pg_temp.id('pen')) = 12
                     and pg_temp.reserved(pg_temp.id('main'), pg_temp.id('dis')) = 15 and pg_temp.onhand(pg_temp.id('main'), pg_temp.id('a4')) = 50,
                     'الاعتماد يحجز الخارج دون تغيير الفعلي');

select pg_temp.as_user('u.safety@test.ly');
insert into ids select 'is2', public.st_save_doc(null, jsonb_build_object('kind', 'issue', 'warehouse_id', pg_temp.id('main'), 'department_id', pg_temp.id('dep_gen'),
  'lines', jsonb_build_array(jsonb_build_object('item_id', pg_temp.id('a4'), 'qty', 41))));
select public.st_doc_action(pg_temp.id('is2'), 'submit');
select pg_temp.as_user('u.qc@test.ly');
select pg_temp.expect_error(format($q$select public.st_doc_action(%L, 'approve')$q$, pg_temp.id('is2')), 'لا صرف فوق المتاح (40 بعد الحجز)');
select public.st_doc_action(pg_temp.id('is2'), 'return', 'الكمية أكبر من المتاح');
select pg_temp.check((select status = 'draft' and decision_note = 'الكمية أكبر من المتاح' from pg_temp.doc(pg_temp.id('is2'))), 'الإعادة للتعديل بسببها');
select pg_temp.as_user('u.safety@test.ly');
select pg_temp.check(public.st_save_doc(pg_temp.id('is2'), jsonb_build_object('warehouse_id', pg_temp.id('main'), 'department_id', pg_temp.id('dep_gen'),
  'lines', jsonb_build_array(jsonb_build_object('item_id', pg_temp.id('a4'), 'qty', 38)))) = pg_temp.id('is2'), 'تعديل المسودة بعد إعادتها');
select public.st_doc_action(pg_temp.id('is2'), 'submit');
select pg_temp.as_user('u.qc@test.ly');
select pg_temp.expect_error(format($q$select public.st_doc_action(%L, 'approve')$q$, pg_temp.id('is2')), 'صرف يمس الاحتياطي الحرج (5) يحتاج استثناء');
select pg_temp.expect_error(format($q$select public.st_doc_action(%L, 'approve', '', true)$q$, pg_temp.id('is2')), 'الاستثناء يحتاج سبباً مكتوباً');
select public.st_doc_action(pg_temp.id('is2'), 'approve', 'طلب عاجل لامتحانات نهاية العام', true);
select pg_temp.check((select override_note = 'طلب عاجل لامتحانات نهاية العام' from pg_temp.doc(pg_temp.id('is2')))
                     and pg_temp.reserved(pg_temp.id('main'), pg_temp.id('a4')) = 48, 'الاستثناء بسببه والحجز 48');
select pg_temp.check((select detail -> 'override' -> 0 ->> 'critical' = '5.000' from pg_temp.alog()
                       where action = 'stores.doc_approve' and detail ->> 'id' = pg_temp.id('is2')::text), 'الاستثناء في سجل التدقيق');
select pg_temp.expect_error(format($q$select public.st_doc_action(%L, 'cancel')$q$, pg_temp.id('is2')), 'إلغاء المعتمد يحتاج سبباً');
select public.st_doc_action(pg_temp.id('is2'), 'cancel', 'أُجّل الطلب');
select pg_temp.check(pg_temp.reserved(pg_temp.id('main'), pg_temp.id('a4')) = 10 and (select status = 'cancelled' from pg_temp.doc(pg_temp.id('is2'))),
                     'إلغاء المعتمد يفك حجزه');

select pg_temp.as_user('u.safety@test.ly');
select public.st_doc_action(pg_temp.id('is1'), 'post');
select pg_temp.check(pg_temp.onhand(pg_temp.id('main'), pg_temp.id('a4')) = 40 and pg_temp.reserved(pg_temp.id('main'), pg_temp.id('a4')) = 0
                     and pg_temp.onhand(pg_temp.id('main'), pg_temp.id('pen')) = 112 and pg_temp.onhand(pg_temp.id('main'), pg_temp.id('dis')) = 15,
                     'ترحيل الصرف ينقص الفعلي ويفك الحجز');
select pg_temp.check(pg_temp.batch(pg_temp.id('main'), pg_temp.id('dis'), '2026-12-31') = 0 and pg_temp.batch(pg_temp.id('main'), pg_temp.id('dis'), '2027-01-31') = 15,
                     'الصرف من الأقرب انتهاءً أولاً (10 ثم 5)');
select pg_temp.check((select count(*) = 2 from st_moves m join st_doc_lines l on l.id = m.line_id where m.doc_id = pg_temp.id('is1') and l.item_id = pg_temp.id('dis')),
                     'حركتان للمطهر بدفعتيهما');

-- ---------------------------------------------------------------- الخدمة الذاتية للموظف
select pg_temp.as_user('pending@test.ly');
select pg_temp.check((select count(*) = 1 from st_docs) and (select count(*) = 3 from st_doc_lines), 'الموظف يرى ما صُرف له مرحَّلاً وحده ببنوده');
select pg_temp.check((select count(*) = 3 from st_items where id in (pg_temp.id('a4'), pg_temp.id('pen'), pg_temp.id('dis'))),
                     'ويقرأ أسماء الأصناف');
select pg_temp.check((select count(*) = 0 from st_stock) and (select count(*) = 0 from st_moves), 'ولا يرى الأرصدة ولا الحركات');
select public.st_confirm_receipt(pg_temp.id('is1'));
select public.st_confirm_receipt(pg_temp.id('is1'));
select pg_temp.check((select confirmed_by = pg_temp.uid('pending@test.ly') from pg_temp.doc(pg_temp.id('is1')))
                     and (select count(*) = 1 from pg_temp.alog() where action = 'stores.receipt_confirm'), 'تأكيد الاستلام مرة واحدة ومسجّل');
select pg_temp.expect_error(format($q$select public.st_confirm_receipt(%L)$q$, pg_temp.id('ob')), 'لا يؤكد مستنداً ليس له');

-- ---------------------------------------------------------------- التحويل والتسوية
select pg_temp.as_user('u.safety@test.ly');
insert into ids select 'tr', public.st_save_doc(null, jsonb_build_object('kind', 'transfer', 'warehouse_id', pg_temp.id('main'), 'to_warehouse_id', pg_temp.id('sub'),
  'lines', jsonb_build_array(jsonb_build_object('item_id', pg_temp.id('dis'), 'qty', 10), jsonb_build_object('item_id', pg_temp.id('a4'), 'qty', 5))));
select pg_temp.expect_error(format($q$select public.st_save_doc(null, jsonb_build_object('kind', 'transfer', 'warehouse_id', %L, 'to_warehouse_id', %L, 'lines', jsonb_build_array(jsonb_build_object('item_id', %L, 'qty', 1))))$q$,
                                   pg_temp.id('main'), pg_temp.id('main'), pg_temp.id('a4')), 'التحويل إلى المخزن نفسه مرفوض');
select public.st_doc_action(pg_temp.id('tr'), 'submit');
select pg_temp.as_user('u.qc@test.ly');
select public.st_doc_action(pg_temp.id('tr'), 'approve');
select pg_temp.as_user('u.safety@test.ly');
select public.st_doc_action(pg_temp.id('tr'), 'post');
select pg_temp.check(pg_temp.onhand(pg_temp.id('main'), pg_temp.id('dis')) = 5 and pg_temp.onhand(pg_temp.id('sub'), pg_temp.id('dis')) = 10
                     and pg_temp.batch(pg_temp.id('sub'), pg_temp.id('dis'), '2027-01-31') = 10 and pg_temp.onhand(pg_temp.id('sub'), pg_temp.id('a4')) = 5,
                     'التحويل ينقل الكمية بدفعتها');
select pg_temp.as_user('qa@test.ly');
select pg_temp.check((select count(*) = 1 from st_docs where id = pg_temp.id('tr')) and (select count(*) = 2 from st_stock)
                     and (select count(*) = 0 from st_stock where warehouse_id = pg_temp.id('main')), 'أمين الفرعي يرى التحويل إليه ورصيد مخزنه وحده');
insert into ids select 'is3', public.st_save_doc(null, jsonb_build_object('kind', 'issue', 'warehouse_id', pg_temp.id('sub'), 'employee_id', pg_temp.id('emp2'),
  'lines', jsonb_build_array(jsonb_build_object('item_id', pg_temp.id('dis'), 'qty', 6))));
select public.st_doc_action(pg_temp.id('is3'), 'submit');
select pg_temp.as_user('u.qc@test.ly');
select public.st_doc_action(pg_temp.id('is3'), 'approve');
select pg_temp.as_user('qa@test.ly');
select public.st_doc_action(pg_temp.id('is3'), 'post');

select pg_temp.as_user('u.safety@test.ly');
insert into ids select 'ad', public.st_save_doc(null, jsonb_build_object('kind', 'adjust', 'warehouse_id', pg_temp.id('main'), 'note', 'جرد مبدئي',
  'lines', jsonb_build_array(jsonb_build_object('item_id', pg_temp.id('pen'), 'qty', -2), jsonb_build_object('item_id', pg_temp.id('a4'), 'qty', 1))));
select pg_temp.expect_error(format($q$select public.st_save_doc(null, jsonb_build_object('kind', 'adjust', 'warehouse_id', %L, 'lines', jsonb_build_array(jsonb_build_object('item_id', %L, 'qty', 3))))$q$,
                                   pg_temp.id('main'), pg_temp.id('dis')), 'زيادة التسوية لصنف بصلاحية تحتاج تاريخها');
select public.st_doc_action(pg_temp.id('ad'), 'submit');
select pg_temp.as_user('u.qc@test.ly');
select public.st_doc_action(pg_temp.id('ad'), 'approve');
select pg_temp.as_user('u.safety@test.ly');
select public.st_doc_action(pg_temp.id('ad'), 'post');
select pg_temp.check(pg_temp.onhand(pg_temp.id('main'), pg_temp.id('pen')) = 110 and pg_temp.onhand(pg_temp.id('main'), pg_temp.id('a4')) = 36,
                     'التسوية بالنقص والزيادة');

-- ---------------------------------------------------------------- العكس
select pg_temp.as_user('u.safety@test.ly');
select pg_temp.expect_error(format($q$select public.st_reverse_doc(%L, 'خطأ في الكمية')$q$, pg_temp.id('is1')), 'العكس لمدير المخازن');
select pg_temp.as_user('u.qc@test.ly');
select pg_temp.expect_error(format($q$select public.st_reverse_doc(%L, 'لا')$q$, pg_temp.id('is1')), 'العكس يحتاج سبباً');
insert into ids select 'rv', public.st_reverse_doc(pg_temp.id('is1'), 'صُرف للموظف الخطأ');
select pg_temp.check((select doc_no ~ '^RV-' and kind = 'issue' and reverses_id = pg_temp.id('is1') and status = 'draft' from pg_temp.doc(pg_temp.id('rv'))),
                     'العكسي مسودة بأصلها ونوعه');
select pg_temp.expect_error(format($q$select public.st_reverse_doc(%L, 'مرة ثانية')$q$, pg_temp.id('is1')), 'عكسي واحد قائم لكل مستند');
select pg_temp.expect_error(format($q$select public.st_save_doc(%L, jsonb_build_object('warehouse_id', %L, 'lines', '[]'::jsonb))$q$,
                                   pg_temp.id('rv'), pg_temp.id('main')), 'بنود العكسي لا تُعدَّل');
select public.st_doc_action(pg_temp.id('rv'), 'submit');
select pg_temp.as_user('director.new@test.ly', 'aal2');
select public.st_doc_action(pg_temp.id('rv'), 'approve');
select pg_temp.as_user('u.safety@test.ly');
select public.st_doc_action(pg_temp.id('rv'), 'post');
select pg_temp.check(pg_temp.onhand(pg_temp.id('main'), pg_temp.id('a4')) = 46 and pg_temp.onhand(pg_temp.id('main'), pg_temp.id('pen')) = 122
                     and pg_temp.onhand(pg_temp.id('main'), pg_temp.id('dis')) = 20, 'العكس يعيد الكميات المصروفة');
select pg_temp.check(pg_temp.batch(pg_temp.id('main'), pg_temp.id('dis'), '2026-12-31') = 10 and pg_temp.batch(pg_temp.id('main'), pg_temp.id('dis'), '2027-01-31') = 10,
                     'ويعيدها إلى دفعاتها نفسها');
select pg_temp.as_user('u.qc@test.ly');
select pg_temp.expect_error(format($q$select public.st_reverse_doc(%L, 'عكس العكسي')$q$, pg_temp.id('rv')), 'لا يُعكس العكسي');
-- عكس التحويل بعد صرف جزء منه في الفرعي: المتاح هناك لا يكفي
insert into ids select 'rvt', public.st_reverse_doc(pg_temp.id('tr'), 'التحويل لم يكن مطلوباً');
select public.st_doc_action(pg_temp.id('rvt'), 'submit');
select pg_temp.as_user('director.new@test.ly', 'aal2');
select pg_temp.expect_error(format($q$select public.st_doc_action(%L, 'approve')$q$, pg_temp.id('rvt')), 'عكس تحويل صُرف منه مرفوض (المتاح 4 والمطلوب 10)');
select public.st_doc_action(pg_temp.id('rvt'), 'reject', 'يُعالج بتحويل جديد');
select pg_temp.check((select status = 'rejected' from pg_temp.doc(pg_temp.id('rvt'))), 'رفض العكسي بسببه');

-- ---------------------------------------------------------------- المسودات والحذف
select pg_temp.as_user('u.safety@test.ly');
insert into ids select 'dr', public.st_save_doc(null, jsonb_build_object('kind', 'receipt', 'warehouse_id', pg_temp.id('main'),
  'lines', jsonb_build_array(jsonb_build_object('item_id', pg_temp.id('pen'), 'qty', 1))));
select public.st_delete_doc(pg_temp.id('dr'));
select pg_temp.check((select count(*) = 0 from pg_temp.doc(pg_temp.id('dr'))) and (select count(*) = 1 from pg_temp.alog() where action = 'stores.doc_delete'),
                     'حذف المسودة التي لم تُقدَّم مع لقطتها في السجل');
select pg_temp.expect_error(format($q$select public.st_delete_doc(%L)$q$, pg_temp.id('is2')), 'لا يُحذف مستند قُدّم من قبل');

-- ---------------------------------------------------------------- المراجع والقيود على الأصناف والتهيئة
select pg_temp.as_user('u.safetyhead@test.ly');
select pg_temp.check((select count(*) >= 8 from st_docs) and (select count(*) >= 5 from st_stock), 'المراجع يطّلع على كل المستندات والأرصدة');
select pg_temp.expect_error(format($q$select public.st_save_doc(null, jsonb_build_object('kind', 'receipt', 'warehouse_id', %L, 'lines', jsonb_build_array(jsonb_build_object('item_id', %L, 'qty', 1))))$q$,
                                   pg_temp.id('main'), pg_temp.id('pen')), 'المراجع لا يحرّك المخزون');
select pg_temp.as_user('u.qc@test.ly');
select pg_temp.expect_error(format($q$select public.st_save_item(%L, jsonb_build_object('name', 'ورق A4 80 غم', 'category_id', (select id from st_categories where code = 'PAP'), 'base_unit_id', %L))$q$,
                                   pg_temp.id('a4'), pg_temp.id('u_piece')), 'لا تتغير الوحدة الأساسية لصنف له حركات');
select pg_temp.expect_error(format($q$select public.st_save_item(%L, jsonb_build_object('name', 'مطهر أسطح', 'category_id', (select id from st_categories where code = 'CLN'), 'base_unit_id', %L, 'tracks_expiry', false))$q$,
                                   pg_temp.id('dis'), pg_temp.id('u_pack')), 'لا يتغير تتبع الصلاحية لصنف له رصيد');
select pg_temp.expect_error(format($q$select public.st_save_item(%L, jsonb_build_object('name', 'قلم حبر أزرق', 'category_id', (select id from st_categories where code = 'STA'), 'base_unit_id', %L, 'barcode', '6281000000017', 'units', '[]'::jsonb))$q$,
                                   pg_temp.id('pen'), pg_temp.id('u_piece')), 'وحدة مستعملة في مستندات لا تُحذف من الصنف');
select pg_temp.check(public.st_save_item(pg_temp.id('pen'), jsonb_build_object('name', 'قلم حبر أزرق جاف', 'category_id', (select id from st_categories where code = 'STA'),
  'base_unit_id', pg_temp.id('u_piece'), 'barcode', '6281000000017', 'min_qty', 24, 'reorder_qty', 48,
  'units', jsonb_build_array(jsonb_build_object('unit_id', pg_temp.id('u_box'), 'factor', 12)))) = pg_temp.id('pen'), 'حفظ تعديل البطاقة');
select pg_temp.check((select name = 'قلم حبر أزرق جاف' and min_qty = 24 and code = 'STA-0001' from pg_temp.item(pg_temp.id('pen'))), 'تعديل البطاقة يحفظ رمزها');
select pg_temp.as_user('u.heritage@test.ly');
select pg_temp.expect_error(format($q$select public.st_delete_setup('warehouse', %L)$q$, pg_temp.id('main')), 'مخزن له مستندات لا يُحذف');
select pg_temp.expect_error(format($q$select public.st_delete_setup('unit', %L)$q$, pg_temp.id('u_box')), 'وحدة مستعملة لا تُحذف');
select pg_temp.expect_error(format($q$select public.st_save_warehouse(%L, jsonb_build_object('code', 'MAIN', 'name', 'المخزن الرئيسي', 'kind', 'main', 'active', false))$q$,
                                   pg_temp.id('main')), 'لا يُوقف مخزن فيه رصيد');
select public.st_delete_setup('unit', pg_temp.id('unit_dz'));
select pg_temp.check((select count(*) = 0 from st_units where id = pg_temp.id('unit_dz')), 'حذف وحدة غير مستعملة');

-- ---------------------------------------------------------------- سلامة الأرصدة وسجل التدقيق
reset role;
select pg_temp.check((select bool_and(s.on_hand = coalesce((select sum(m.qty) from st_moves m where m.warehouse_id = s.warehouse_id and m.item_id = s.item_id), 0))
                        from st_stock s), 'كل رصيد يساوي مجموع حركاته');
select pg_temp.check((select bool_and(s.on_hand = coalesce((select sum(b.qty) from st_batches b where b.warehouse_id = s.warehouse_id and b.item_id = s.item_id), 0))
                        from st_stock s join st_items i on i.id = s.item_id where i.tracks_expiry), 'رصيد الصنف ذي الصلاحية يساوي مجموع دفعاته');
select pg_temp.check((select bool_and(reserved = 0) from st_stock), 'لا حجز معلّق بعد الترحيل والإلغاء');
select pg_temp.check((select count(distinct action) >= 13 from audit_log where action like 'stores.%'), 'إجراءات القسم في سجل التدقيق');
select pg_temp.check((select count(*) = 4 from audit_log where action like 'stores.doc_%' and detail ->> 'id' = pg_temp.id('is1')::text),
                     'كل خطوة في مستند الصرف مسجّلة (حفظ وتقديم واعتماد وترحيل)');

-- ---------------------------------------------------------------- التجميد الطارئ
update app_settings set value = 'true' where key = 'security.freeze';
set role authenticated;
select pg_temp.as_user('u.safety@test.ly');
select pg_temp.expect_error(format($q$select public.st_save_doc(null, jsonb_build_object('kind', 'receipt', 'warehouse_id', %L, 'lines', jsonb_build_array(jsonb_build_object('item_id', %L, 'qty', 1))))$q$,
                                   pg_temp.id('main'), pg_temp.id('pen')), 'لا حركات في وضع القراءة فقط');
reset role;
update app_settings set value = 'false' where key = 'security.freeze';
