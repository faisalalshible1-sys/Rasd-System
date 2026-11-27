-- اختبارات الترحيل 39: الأصول والعُهد والإهلاك — نطاق مسؤول الأصول، وسياسات الإهلاك، وسجل الأصول، والإهلاك بالقسط
-- الثابت (مثالا الفصل 34)، والتسليم والإرجاع وتأكيد الموظف، والنقل والوضع، والاستبعاد بفصل المهام، والاستيراد، والقيود.
-- يُشغَّل بعد اختبارات الترحيل 38 (120) وعلى بياناتها، وبعد تطبيق 20261130000039_stores_assets.sql مرتين والتراجع عنه وإعادته.
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
create or replace function pg_temp.asset(p_id uuid) returns setof public.st_assets language sql security definer as $$ select * from public.st_assets where id = p_id $$;
create or replace function pg_temp.cust(p_id uuid) returns setof public.st_custody language sql security definer as $$ select * from public.st_custody where id = p_id $$;
create or replace function pg_temp.events(p_id uuid) returns text language sql security definer as $$
  select string_agg(kind, ',' order by id) from public.st_asset_events where asset_id = p_id
$$;
create or replace function pg_temp.cat(p_code text) returns uuid language sql security definer as $$ select id from public.st_categories where code = p_code $$;
create or replace function pg_temp.emp(p_no text) returns uuid language sql security definer as $$ select id from public.st_employees where emp_no = p_no $$;
create or replace function pg_temp.wh(p_code text) returns uuid language sql security definer as $$ select id from public.st_warehouses where code = p_code $$;
create or replace function pg_temp.loc(p_name text) returns uuid language sql security definer as $$ select id from public.st_locations where name = p_name $$;
create or replace function pg_temp.dep(p_name text) returns uuid language sql security definer as $$ select id from public.st_departments where name = p_name limit 1 $$;

update app_settings set value = 'false' where key in ('security.freeze', 'security.require_mfa_all');
update st_settings set value = 'true'::jsonb where key = 'separation';
update profiles set locked_until = null where email in ('director.new@test.ly', 'headrest@test.ly', 'u.qc@test.ly', 'u.heritage@test.ly',
                                                         'u.safety@test.ly', 'u.safetyhead@test.ly', 'pending@test.ly', 'k.staff@test.ly');
create temp table ids (k text primary key, v uuid);
grant all on ids to authenticated;
create or replace function pg_temp.id(p_k text) returns uuid language sql as $$ select v from ids where k = p_k $$;
grant execute on all functions in schema pg_temp to authenticated, anon;

-- ---------------------------------------------------------------- البذور والإهلاك
select pg_temp.check((select count(*) = 2 from st_asset_policies)
                     and (select life_months = 60 and salvage_pct = 0 from st_asset_policies where category_id = pg_temp.cat('OFE'))
                     and (select life_months = 120 and salvage_pct = 0 from st_asset_policies where category_id = pg_temp.cat('FUR')),
                     'سياستا الإهلاك المبدئيتان: الأجهزة المكتبية 60 شهراً والأثاث 120 شهراً بلا خردة');
select pg_temp.check(public.st_months_between('2026-01-15', '2026-11-26') = 10, 'الأشهر المنقضية: من 15 يناير إلى 26 نوفمبر عشرة أشهر');
select pg_temp.check(public.st_months_between('2026-01-15', '2026-11-14') = 9, 'لم يبلغ اليوم يوم البداية فيُنقص شهر');
select pg_temp.check(public.st_months_between('2026-01-31', '2026-02-28') = 0 and public.st_months_between('2026-01-15', '2026-02-15') = 1,
                     'الشهر الكامل من اليوم نفسه');
select pg_temp.check(public.st_months_between('2026-05-01', '2026-03-01') = 0, 'لا أشهر قبل بدء الاستخدام');
select pg_temp.check(public.st_accumulated(3600, 0, 'straight', 36, '2026-01-15', '2026-11-26') = 1000,
                     'مثال الحاسوب: 3,600 × 10 ÷ 36 = 1,000 متراكم، والدفترية 2,600');
select pg_temp.check(public.st_accumulated(1200, 120, 'straight', 120, '2024-03-01', '2026-11-26') = 288,
                     'مثال المكتب: (1,200 − 120) × 32 ÷ 120 = 288 متراكم، والدفترية 912');
select pg_temp.check(public.st_accumulated(1200, 120, 'straight', 12, '2024-03-01', '2026-11-26') = 1080,
                     'لا يتجاوز المتراكم التكلفة ناقص الخردة');
select pg_temp.check(public.st_accumulated(1000, 0, 'straight', 7, '2026-01-01', '2026-02-01') = 142.857,
                     'التقريب إلى ثلاث خانات: 1,000 ÷ 7 = 142.857');
select pg_temp.check(public.st_accumulated(5000, 0, 'none', null, '2020-01-01', '2026-11-26') = 0, 'بلا إهلاك: لا متراكم');

-- ---------------------------------------------------------------- نطاق مسؤول الأصول
set role authenticated;
select pg_temp.as_user('director.new@test.ly', 'aal2');
select public.set_user_grants(pg_temp.uid('headrest@test.ly'), array['stores:assets']);
select pg_temp.check((select count(*) = 1 from user_grants where scope = 'stores:assets'), 'المدير يمنح نطاق مسؤول الأصول');
select pg_temp.expect_error($q$select public.set_user_grants(pg_temp.uid('pending@test.ly'), array['stores:assets'])$q$,
                            'لا يُمنح حساب الموظف نطاقاً');

select pg_temp.as_user('headrest@test.ly');
select pg_temp.check(public.st_staff() and public.st_assets_sees() and public.st_can_assets() and not public.st_sees_all(),
                     'مسؤول الأصول من أهل القسم ويرى الأصول ويكتبها، ولا يرى المخزون كله');
select pg_temp.check('stores' = any (public.my_sections()), 'قسم المخازن ظاهر لمسؤول الأصول');
select pg_temp.check((select count(*) = 0 from st_docs) and (select count(*) = 0 from st_stock), 'ولا يقرأ مستندات المخزون وأرصدته');
select pg_temp.check((select count(*) >= 4 from st_employees) and (select count(*) >= 1 from st_items), 'ويقرأ الموظفين والأصناف لربطها بالأصول');
select pg_temp.expect_error($q$select public.st_save_asset_policy(pg_temp.cat('OFE'), '{"life_months": 48}'::jsonb)$q$,
                            'سياسات الإهلاك لمدير النظام في القسم أو المدير');

select pg_temp.as_user('u.safety@test.ly');
select pg_temp.check(not public.st_assets_sees() and not public.st_can_assets(), 'أمين المخزن لا يرى الأصول ولا يكتبها');

-- ---------------------------------------------------------------- سياسة الإهلاك
select pg_temp.as_user('u.heritage@test.ly');
select public.st_save_asset_policy(pg_temp.cat('OFE'), '{"dep_method": "straight", "life_months": 48, "salvage_pct": 10}'::jsonb);
select pg_temp.check((select life_months = 48 and salvage_pct = 10 and updated_by = pg_temp.uid('u.heritage@test.ly')
                        from st_asset_policies where category_id = pg_temp.cat('OFE')), 'مدير النظام يعدّل سياسة الأجهزة المكتبية');
select pg_temp.expect_error($q$select public.st_save_asset_policy(pg_temp.cat('PAP'), '{"life_months": 12}'::jsonb)$q$,
                            'لا سياسة إهلاك لتصنيف استهلاكي');
select pg_temp.expect_error($q$select public.st_save_asset_policy(pg_temp.cat('OFE'), '{"life_months": 0}'::jsonb)$q$, 'العمر من 1 إلى 600 شهر');
select pg_temp.expect_error($q$select public.st_save_asset_policy(pg_temp.cat('OFE'), '{"life_months": 48, "salvage_pct": 120}'::jsonb)$q$,
                            'نسبة الخردة حتى 100');

-- ---------------------------------------------------------------- تسجيل الأصول
select pg_temp.as_user('headrest@test.ly');
insert into ids select 'lap', public.st_save_asset(null, jsonb_build_object('name', 'حاسوب محمول', 'category_id', pg_temp.cat('OFE'),
  'manufacturer', 'Dell', 'model', 'Latitude 5440', 'serial_no', 'SN-LAP-001', 'purchase_date', '2026-01-10',
  'in_service_date', '2026-01-15', 'cost', 3600, 'life_months', 36, 'salvage', 0, 'supplier', 'مورد الحواسيب', 'condition', 'new'));
select pg_temp.check((select tag = 'OFE-A-0001' and status = 'available' and life_months = 36 and salvage = 0 and condition = 'new'
                        and in_service_date = '2026-01-15' from pg_temp.asset(pg_temp.id('lap'))), 'رقم الأصل تلقائياً OFE-A-0001، متاح، بعمره المحدد');
select pg_temp.check((select public.st_book_value(a, '2026-11-26') = 2600 from pg_temp.asset(pg_temp.id('lap')) a), 'القيمة الدفترية للحاسوب في 26 نوفمبر 2,600');
insert into ids select 'mon', public.st_save_asset(null, jsonb_build_object('name', 'شاشة 24 بوصة', 'category_id', pg_temp.cat('OFE'),
  'purchase_date', '2026-02-01', 'cost', 500));
select pg_temp.check((select tag = 'OFE-A-0002' and life_months = 48 and salvage = 50 from pg_temp.asset(pg_temp.id('mon'))),
                     'الأصل الجديد يأخذ سياسة تصنيفه: 48 شهراً وخردة 10% = 50');
insert into ids select 'desk', public.st_save_asset(null, jsonb_build_object('name', 'مكتب خشبي مع أدراج', 'category_id', pg_temp.cat('FUR'),
  'purchase_date', '2024-03-01', 'cost', 1200, 'salvage', 120, 'location_id', pg_temp.loc('غرفة 004'),
  'department_id', pg_temp.dep('الإدارة العامة'), 'tag', 'FUR-OLD-17'));
select pg_temp.check((select tag = 'FUR-OLD-17' and status = 'in_use' and life_months = 120 and public.st_book_value(a, '2026-11-26') = 912
                        from pg_temp.asset(pg_temp.id('desk')) a), 'أصل برقمه القديم في موقع: مستخدم، والدفترية 912');
insert into ids select 'chair', public.st_save_asset(null, jsonb_build_object('name', 'كرسي دوار', 'category_id', pg_temp.cat('FUR'),
  'cost', 300, 'warehouse_id', pg_temp.wh('MAIN')));
select pg_temp.check((select status = 'available' and warehouse_id = pg_temp.wh('MAIN') and location_id is not distinct from
                        (select location_id from st_warehouses where code = 'MAIN') from pg_temp.asset(pg_temp.id('chair'))),
                     'أصل في مخزن: متاح وموقعه موقع المخزن');
select pg_temp.expect_error($q$select public.st_save_asset(null, jsonb_build_object('name', 'ورق', 'category_id', pg_temp.cat('PAP'), 'cost', 10, 'life_months', 12))$q$,
                            'الأصول في تصنيفات الأصول وحدها');
select pg_temp.expect_error(format($q$select public.st_save_asset(null, jsonb_build_object('name', 'طابعة', 'category_id', pg_temp.cat('OFE'), 'cost', 900, 'purchase_date', %L))$q$,
                                   current_date + 3), 'تاريخ الشراء لا يكون في المستقبل');
select pg_temp.expect_error($q$select public.st_save_asset(null, jsonb_build_object('name', 'طابعة', 'category_id', pg_temp.cat('OFE'), 'cost', 900, 'salvage', 1000))$q$,
                            'الخردة لا تتجاوز التكلفة');
select pg_temp.expect_error($q$select public.st_save_asset(null, jsonb_build_object('name', 'حاسوب آخر', 'category_id', pg_temp.cat('OFE'), 'cost', 900, 'serial_no', 'sn-lap-001'))$q$,
                            'الرقم التسلسلي لا يتكرر');
select pg_temp.expect_error($q$select public.st_save_asset(null, jsonb_build_object('name', 'مكتب آخر', 'category_id', pg_temp.cat('FUR'), 'cost', 900, 'tag', 'fur-old-17'))$q$,
                            'رقم الأصل لا يتكرر');
select pg_temp.expect_error($q$select public.st_save_asset(null, jsonb_build_object('name', 'مكتب', 'category_id', pg_temp.cat('FUR'), 'cost', 900, 'tag', 'رقم عربي'))$q$,
                            'رقم الأصل بحروف لاتينية وأرقام');
select pg_temp.expect_error($q$select public.st_save_asset(null, jsonb_build_object('name', 'جهاز', 'category_id', pg_temp.cat('OFE'), 'cost', 900, 'dep_method', 'straight', 'life_months', null))$q$,
                            'القسط الثابت يحتاج عمراً');
-- التعديل لا يمس رقم الأصل إن لم يُرسل، ويسجّل ما تغير
select pg_temp.check(public.st_save_asset(pg_temp.id('mon'), jsonb_build_object('name', 'شاشة 24 بوصة', 'category_id', pg_temp.cat('OFE'),
  'purchase_date', '2026-02-01', 'cost', 520, 'model', 'P2423'))= pg_temp.id('mon'), 'حفظ تعديل الأصل');
select pg_temp.check((select tag = 'OFE-A-0002' and cost = 520 and model = 'P2423' and life_months = 48 and salvage = 50
                        from pg_temp.asset(pg_temp.id('mon'))), 'تعديل الأصل يحفظ رقمه وعمره وخردته');
select pg_temp.check(pg_temp.events(pg_temp.id('mon')) = 'create,update', 'سجل حياة الأصل: إنشاء ثم تعديل');

select pg_temp.as_user('u.safetyhead@test.ly');
select pg_temp.check((select count(*) = 4 from st_assets), 'المراجع يطّلع على الأصول');
select pg_temp.expect_error($q$select public.st_save_asset(null, jsonb_build_object('name', 'جهاز', 'category_id', pg_temp.cat('OFE'), 'cost', 1, 'life_months', 12))$q$,
                            'المراجع لا يسجّل أصولاً');
select pg_temp.as_user('u.safety@test.ly');
select pg_temp.check((select count(*) = 0 from st_assets) and (select count(*) = 0 from st_asset_events), 'أمين المخزن لا يقرأ الأصول');
select pg_temp.as_user('k.staff@test.ly');
select pg_temp.check((select count(*) = 0 from st_assets) and (select count(*) = 0 from st_custody), 'موظف المكتب لا يقرأ الأصول ولا العهد');

-- ---------------------------------------------------------------- تسليم العهدة وتأكيد الموظف
select pg_temp.as_user('headrest@test.ly');
insert into ids select 'c1', public.st_custody_out(pg_temp.id('lap'), jsonb_build_object('employee_id', pg_temp.emp('E-100'),
  'handed_on', '2026-02-01', 'accessories', 'شاحن وحقيبة', 'note', 'للعمل الميداني'));
select pg_temp.check((select custody_no = 'CU-2026-0001' and condition_out = 'new' and accessories_out = 'شاحن وحقيبة' and returned_on is null
                        from pg_temp.cust(pg_temp.id('c1'))), 'محضر العهدة CU-2026-0001 بحالته وملحقاته');
select pg_temp.check((select status = 'custody' and employee_id = pg_temp.emp('E-100') and warehouse_id is null
                        and department_id is not distinct from (select department_id from st_employees where emp_no = 'E-100')
                        from pg_temp.asset(pg_temp.id('lap'))), 'الأصل في عهدة الموظف وإدارته إدارة الموظف');
select pg_temp.expect_error(format($q$select public.st_custody_out(%L, jsonb_build_object('employee_id', pg_temp.emp('E-101')))$q$, pg_temp.id('lap')),
                            'لا عهدتان مفتوحتان للأصل');
select pg_temp.expect_error(format($q$select public.st_custody_out(%L, jsonb_build_object('employee_id', pg_temp.emp('E-101'), 'handed_on', %L))$q$,
                                   pg_temp.id('mon'), current_date + 1), 'تاريخ التسليم لا يكون في المستقبل');
select pg_temp.expect_error(format($q$select public.st_custody_out(%L, jsonb_build_object('employee_id', gen_random_uuid()))$q$, pg_temp.id('mon')),
                            'الموظف المستلم يجب أن يوجد');
select pg_temp.expect_error(format($q$select public.st_asset_status(%L, 'maintenance')$q$, pg_temp.id('lap')), 'لا يتغير وضع أصل في العهدة');
select pg_temp.expect_error(format($q$select public.st_asset_transfer(%L, jsonb_build_object('warehouse_id', pg_temp.wh('MAIN')))$q$, pg_temp.id('lap')),
                            'الأصل المسلَّم لا يُنقل إلى مخزن إلا بإرجاعه');
select public.st_asset_transfer(pg_temp.id('lap'), jsonb_build_object('location_id', pg_temp.loc('الطابق الأرضي'),
  'department_id', (select department_id from pg_temp.asset(pg_temp.id('lap'))), 'note', 'انتقل مكتب الموظف'));
select pg_temp.check((select status = 'custody' and location_id = pg_temp.loc('الطابق الأرضي') from pg_temp.asset(pg_temp.id('lap'))),
                     'نقل موقع الأصل المسلَّم يبقيه في عهدة موظفه');

select pg_temp.as_user('pending@test.ly');
select pg_temp.check(jsonb_array_length(public.st_my_custody()) = 1
                     and public.st_my_custody() -> 0 ->> 'tag' = 'OFE-A-0001'
                     and not (public.st_my_custody() -> 0 ? 'cost'), 'الموظف يرى عهدته برقمها ووصفها دون تكلفتها');
select pg_temp.check((select count(*) = 1 from st_custody) and (select count(*) = 0 from st_assets), 'ويقرأ سطر عهدته وحده لا سجل الأصول');
select pg_temp.expect_error(format($q$select public.st_confirm_custody(%L, 'return')$q$, pg_temp.id('c1')), 'لا يُؤكَّد إرجاع لم يُسجَّل');
select public.st_confirm_custody(pg_temp.id('c1'), 'receipt');
select pg_temp.check((select confirmed_at is not null and confirmed_by = pg_temp.uid('pending@test.ly') from pg_temp.cust(pg_temp.id('c1'))),
                     'الموظف يؤكد استلام عهدته');
select pg_temp.expect_error(format($q$select public.st_custody_out(%L, jsonb_build_object('employee_id', pg_temp.emp('E-100')))$q$, pg_temp.id('mon')),
                            'الموظف لا يسلّم عهداً');

-- ---------------------------------------------------------------- الإرجاع
select pg_temp.as_user('headrest@test.ly');
select pg_temp.expect_error(format($q$select public.st_custody_in(%L, jsonb_build_object('returned_on', '2026-01-20', 'condition', 'good'))$q$, pg_temp.id('c1')),
                            'الإرجاع لا يسبق التسليم');
select pg_temp.expect_error(format($q$select public.st_custody_in(%L, '{}'::jsonb)$q$, pg_temp.id('c1')), 'حالة الأصل عند الإرجاع مطلوبة');
select public.st_custody_in(pg_temp.id('c1'), jsonb_build_object('returned_on', '2026-10-01', 'condition', 'fair',
  'accessories', 'شاحن فقط', 'note', 'فُقدت الحقيبة', 'warehouse_id', pg_temp.wh('MAIN')));
select pg_temp.check((select returned_on = '2026-10-01' and condition_in = 'fair' and accessories_in = 'شاحن فقط' and received_by = pg_temp.uid('headrest@test.ly')
                        from pg_temp.cust(pg_temp.id('c1'))), 'محضر الإرجاع بحالته وملحقاته على العهدة نفسها');
select pg_temp.check((select status = 'available' and employee_id is null and condition = 'fair' and warehouse_id = pg_temp.wh('MAIN')
                        from pg_temp.asset(pg_temp.id('lap'))), 'الأصل عاد متاحاً إلى المخزن بحالته الجديدة');
select pg_temp.expect_error(format($q$select public.st_custody_in(%L, jsonb_build_object('condition', 'good'))$q$, pg_temp.id('c1')), 'لا يُرجَع مرتين');
select pg_temp.as_user('pending@test.ly');
select public.st_confirm_custody(pg_temp.id('c1'), 'return');
select pg_temp.check((select return_confirmed_at is not null from pg_temp.cust(pg_temp.id('c1'))), 'الموظف يؤكد إرجاع عهدته');
select pg_temp.check(public.st_my_custody() -> 0 ->> 'returned_on' = '2026-10-01', 'والعهدة المرجعة تبقى في سجله');

-- ---------------------------------------------------------------- الوضع والنقل
select pg_temp.as_user('headrest@test.ly');
select pg_temp.expect_error(format($q$select public.st_asset_status(%L, 'in_use')$q$, pg_temp.id('lap')), 'أصل في مخزن لا يكون «مستخدماً»');
select public.st_asset_status(pg_temp.id('lap'), 'maintenance', null, 'صيانة لوحة المفاتيح');
select pg_temp.expect_error(format($q$select public.st_custody_out(%L, jsonb_build_object('employee_id', pg_temp.emp('E-101')))$q$, pg_temp.id('lap')),
                            'لا يُسلَّم أصل تحت الصيانة');
select public.st_asset_transfer(pg_temp.id('lap'), jsonb_build_object('location_id', pg_temp.loc('غرفة 004')));
select pg_temp.check((select status = 'maintenance' and warehouse_id is null and location_id = pg_temp.loc('غرفة 004') from pg_temp.asset(pg_temp.id('lap'))),
                     'نقل الأصل تحت الصيانة يبقي وضعه');
select public.st_asset_status(pg_temp.id('lap'), 'in_use');
select pg_temp.expect_error(format($q$select public.st_asset_transfer(%L, jsonb_build_object('location_id', pg_temp.loc('غرفة 004')))$q$, pg_temp.id('lap')),
                            'النقل إلى المكان نفسه مرفوض');
select pg_temp.check(pg_temp.events(pg_temp.id('lap')) = 'create,custody_out,transfer,custody_in,status,transfer,status',
                     'سجل حياة الحاسوب بالترتيب');

-- ---------------------------------------------------------------- الاستبعاد بطلب واعتماد وفصل المهام
select public.st_asset_dispose_request(pg_temp.id('desk'), jsonb_build_object('kind', 'scrap', 'reason', 'تآكل الخشب وانكسار الأدراج'));
select pg_temp.check((select status = 'disposal' and disposal_kind = 'scrap' and disposal_requested_by = pg_temp.uid('headrest@test.ly')
                        from pg_temp.asset(pg_temp.id('desk'))), 'طلب استبعاد المكتب ينتظر الاعتماد');
select pg_temp.expect_error(format($q$select public.st_save_asset(%L, jsonb_build_object('name', 'مكتب', 'category_id', pg_temp.cat('FUR'), 'cost', 1200))$q$,
                                   pg_temp.id('desk')), 'لا يُعدَّل أصل بانتظار استبعاده');
select pg_temp.expect_error(format($q$select public.st_asset_dispose_decide(%L, true)$q$, pg_temp.id('desk')), 'مسؤول الأصول لا يعتمد الاستبعاد');
select pg_temp.as_user('u.qc@test.ly');
select pg_temp.expect_error(format($q$select public.st_asset_dispose_decide(%L, false, '')$q$, pg_temp.id('desk')), 'الرفض يحتاج سبباً');
select public.st_asset_dispose_decide(pg_temp.id('desk'), false, 'يُصلح بدل استبعاده');
select pg_temp.check((select status = 'in_use' and disposal_kind is null and disposal_requested_by is null and decision_note = 'يُصلح بدل استبعاده'
                        from pg_temp.asset(pg_temp.id('desk'))), 'رفض الاستبعاد يعيد الأصل إلى وضعه السابق');
select public.st_asset_dispose_request(pg_temp.id('desk'), jsonb_build_object('kind', 'sale', 'reason', 'بيع في مزاد الأثاث المستعمل', 'value', 150));
select pg_temp.expect_error(format($q$select public.st_asset_dispose_decide(%L, true)$q$, pg_temp.id('desk')), 'فصل المهام: مقدّم الطلب لا يعتمده');
select pg_temp.as_user('director.new@test.ly', 'aal2');
select public.st_asset_dispose_decide(pg_temp.id('desk'), true, 'معتمد');
select pg_temp.check((select status = 'disposed' and disposed_by = pg_temp.uid('director.new@test.ly') and disposal_date = current_date
                        and disposal_value = 150 and location_id is null from pg_temp.asset(pg_temp.id('desk'))), 'المدير يعتمد البيع، والأصل مستبعد');
select pg_temp.check((select (data ->> 'book_value')::numeric = (select public.st_book_value(a, current_date) from pg_temp.asset(pg_temp.id('desk')) a)
                        from st_asset_events where asset_id = pg_temp.id('desk') and kind = 'dispose'),
                     'حدث الاستبعاد يحفظ القيمة الدفترية يومه');
select pg_temp.expect_error(format($q$select public.st_asset_transfer(%L, jsonb_build_object('location_id', pg_temp.loc('غرفة 004')))$q$, pg_temp.id('desk')),
                            'المستبعد لا يُنقل');
select pg_temp.expect_error(format($q$select public.st_custody_out(%L, jsonb_build_object('employee_id', pg_temp.emp('E-101')))$q$, pg_temp.id('desk')),
                            'المستبعد لا يُسلَّم');
select pg_temp.expect_error(format($q$select public.st_delete_asset(%L)$q$, pg_temp.id('desk')), 'المستبعد لا يُحذف');
select pg_temp.expect_error(format($q$select public.st_asset_dispose_request(%L, jsonb_build_object('kind', 'scrap', 'reason', 'تجربة'))$q$, pg_temp.id('desk')),
                            'لا يُطلب استبعاد المستبعد');

-- ---------------------------------------------------------------- الحذف
select pg_temp.as_user('headrest@test.ly');
insert into ids select 'oops', public.st_save_asset(null, jsonb_build_object('name', 'أصل مكرر خطأً', 'category_id', pg_temp.cat('FUR'), 'cost', 1));
select public.st_delete_asset(pg_temp.id('oops'));
select pg_temp.check((select count(*) = 0 from pg_temp.asset(pg_temp.id('oops'))), 'حذف أصل سُجّل خطأً قبل أي عهدة');
select pg_temp.expect_error(format($q$select public.st_delete_asset(%L)$q$, pg_temp.id('lap')), 'أصل له عهد سابقة لا يُحذف');

-- ---------------------------------------------------------------- الاستيراد
select pg_temp.as_user('headrest@test.ly');
select pg_temp.expect_error($q$select public.st_import_assets(jsonb_build_array(
    jsonb_build_object('name', 'طاولة اجتماعات', 'category', 'FUR', 'cost', 2000),
    jsonb_build_object('name', 'ورق', 'category', 'PAP', 'cost', 1)))$q$, 'الصف 2: التصنيف الاستهلاكي يُرفض، ولا يُحفظ شيء من الملف');
select pg_temp.check((select count(*) = 0 from pg_temp.alog() where action = 'stores.assets_import')
                     and (select count(*) = 0 from st_assets where name = 'طاولة اجتماعات'), 'الاستيراد كله أو لا شيء');
select pg_temp.expect_error($q$select public.st_import_assets(jsonb_build_array(jsonb_build_object('name', 'جهاز', 'category', 'OFE', 'emp_no', 'E-999')))$q$,
                            'الرقم الوظيفي يجب أن يوجد');
select pg_temp.check(public.st_import_assets(jsonb_build_array(
    jsonb_build_object('name', 'طاولة اجتماعات', 'category', 'FUR', 'cost', 2000, 'purchase_date', '2025-06-01', 'location', 'B1'),
    jsonb_build_object('name', 'طابعة ليزر', 'category', 'الأجهزة المكتبية', 'cost', 1500, 'serial_no', 'PR-77', 'emp_no', 'E-101',
                       'department', 'الإدارة العامة'),
    jsonb_build_object('tag', 'OFE-A-0002', 'name', 'شاشة 24 بوصة', 'category', 'OFE', 'model', 'P2423H')))
  = '{"rows": 3, "inserted": 2, "updated": 1, "custody": 1}'::jsonb, 'استيراد ثلاثة صفوف: أصلان جديدان، وتحديث، وعهدة');
select pg_temp.check((select status = 'in_use' and location_id = (select id from st_locations where code = 'B1') and life_months = 120
                        from st_assets where name = 'طاولة اجتماعات'), 'الموقع برمزه، والعمر من سياسة التصنيف');
select pg_temp.check((select a.status = 'custody' and c.employee_id = pg_temp.emp('E-101') and c.note_out = 'من الاستيراد'
                        from st_assets a join st_custody c on c.asset_id = a.id and c.returned_on is null where a.serial_no = 'PR-77'),
                     'من له رقم وظيفي في الملف تُسجَّل عهدته');
select pg_temp.check((select model = 'P2423H' and cost = 520 from pg_temp.asset(pg_temp.id('mon'))), 'التحديث برقم الأصل لا يمس ما لم يُرسل');

-- ---------------------------------------------------------------- القيود على التهيئة
select pg_temp.as_user('u.heritage@test.ly');
select pg_temp.expect_error($q$select public.st_save_category(pg_temp.cat('OFE'), jsonb_build_object('code', 'OFE', 'name', 'الأجهزة المكتبية', 'kind', 'consumable'))$q$,
                            'تصنيف فيه أصول لا يتحول إلى استهلاكي');
select pg_temp.expect_error($q$select public.st_delete_setup('category', pg_temp.cat('FUR'))$q$, 'تصنيف فيه أصول لا يُحذف');
select pg_temp.expect_error($q$select public.st_delete_setup('location', pg_temp.loc('غرفة 004'))$q$, 'موقع فيه أصول لا يُحذف');
select pg_temp.expect_error($q$select public.st_delete_setup('employee', pg_temp.emp('E-100'))$q$, 'موظف له عهد لا يُحذف');
select pg_temp.expect_error(format($q$select public.st_delete_setup('warehouse', %L)$q$, pg_temp.wh('MAIN')), 'مخزن فيه أصول لا يُحذف');

-- ---------------------------------------------------------------- سلامة البيانات وسجل التدقيق
reset role;
select pg_temp.check((select bool_and((a.status = 'custody') = exists (select 1 from st_custody c where c.asset_id = a.id and c.returned_on is null
                                                                        and c.employee_id = a.employee_id)) from st_assets a),
                     'كل أصل في العهدة له محضر مفتوح باسم موظفه، ولا محضر مفتوح لغيره');
select pg_temp.check((select count(*) = 0 from st_custody c join st_assets a on a.id = c.asset_id where c.returned_on is null and a.status <> 'custody'),
                     'لا عهدة مفتوحة لأصل غير مسلَّم');
select pg_temp.check((select count(distinct action) = 10 from audit_log where action in ('stores.asset', 'stores.asset_transfer', 'stores.asset_status',
                        'stores.custody_out', 'stores.custody_in', 'stores.custody_confirm', 'stores.asset_dispose_request', 'stores.asset_dispose',
                        'stores.assets_import', 'stores.asset_policy')), 'إجراءات الأصول العشرة في سجل التدقيق');
select pg_temp.check((select count(*) = 2 from audit_log where action = 'stores.custody_confirm'), 'تأكيدا الموظف (الاستلام والإرجاع) في السجل');

-- ---------------------------------------------------------------- التجميد الطارئ
update app_settings set value = 'true' where key = 'security.freeze';
set role authenticated;
select pg_temp.as_user('headrest@test.ly');
select pg_temp.expect_error($q$select public.st_save_asset(null, jsonb_build_object('name', 'جهاز', 'category_id', pg_temp.cat('OFE'), 'cost', 1, 'life_months', 12))$q$,
                            'لا تسجيل أصول في وضع القراءة فقط');
reset role;
update app_settings set value = 'false' where key = 'security.freeze';
