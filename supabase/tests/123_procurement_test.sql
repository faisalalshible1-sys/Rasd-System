-- اختبارات الترحيل 41: قسم المشتريات — نطاقات الصلاحيات وظهور القسم، وطلب الاحتياج (الحفظ والتقديم والرؤية)،
-- ومراجعة التوفر (المتاح والاكتفاء من المخزون وربط البنود الحرة)، واعتماد المدير وفصل المهام والرفض والإلغاء،
-- وعروض الأسعار والحد الأدنى واستثناء المدير، وأمر الشراء وإلغاؤه، والاستلام على دفعات (مستند استلام وأصول)،
-- والإعدادات، والقيود، وسجل التدقيق. يُشغَّل بعد اختبارات الترحيل 40 (122) وعلى بياناتها،
-- وبعد تطبيق 20261202000041_procurement.sql مرتين والتراجع عنه وإعادته.
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
create or replace function pg_temp.rq(p_id uuid) returns setof public.pr_requests language sql security definer as $$ select * from public.pr_requests where id = p_id $$;
create or replace function pg_temp.od(p_id uuid) returns setof public.pr_orders language sql security definer as $$ select * from public.pr_orders where id = p_id $$;
create or replace function pg_temp.events(p_id uuid) returns text language sql security definer as $$
  select string_agg(kind, ',' order by id) from public.pr_events where request_id = p_id
$$;
create or replace function pg_temp.item(p_name text) returns uuid language sql security definer as $$ select id from public.st_items where name = p_name $$;
create or replace function pg_temp.unit(p_name text) returns uuid language sql security definer as $$ select id from public.st_units where name = p_name $$;
create or replace function pg_temp.cat(p_code text) returns uuid language sql security definer as $$ select id from public.st_categories where code = p_code $$;
create or replace function pg_temp.wh(p_code text) returns uuid language sql security definer as $$ select id from public.st_warehouses where lower(code) = lower(p_code) $$;
create or replace function pg_temp.line(p_req uuid, p_no int) returns uuid language sql security definer as $$ select id from public.pr_request_lines where request_id = p_req and line_no = p_no $$;
create or replace function pg_temp.oline(p_order uuid, p_req_line uuid) returns uuid language sql security definer as $$ select id from public.pr_order_lines where order_id = p_order and line_id = p_req_line $$;
create or replace function pg_temp.av(p_item uuid) returns numeric language sql security definer as $$ select public.pr_available(p_item) $$;
create or replace function pg_temp.sup(p_name text) returns uuid language sql security definer as $$ select id from public.pr_suppliers where name = p_name $$;

update app_settings set value = 'false' where key in ('security.freeze', 'security.require_mfa_all');
update profiles set locked_until = null where email in ('director.new@test.ly', 'headrest@test.ly', 'u.qc@test.ly', 'u.heritage@test.ly', 'u.safety@test.ly',
                                                         'u.safetyhead@test.ly', 'pending@test.ly', 'k.qa@test.ly', 'staff.new@test.ly', 'auditor@test.ly');
create temp table ids (k text primary key, v uuid);
grant all on ids to authenticated;
create or replace function pg_temp.id(p_k text) returns uuid language sql as $$ select v from ids where k = p_k $$;
grant execute on all functions in schema pg_temp to authenticated, anon;

-- ---------------------------------------------------------------- البذور
select pg_temp.check((select count(*) = 4 from pr_settings), 'أربعة إعدادات مبدئية للمشتريات');
select pg_temp.check((select value = '3'::jsonb from pr_settings where key = 'min_quotes')
                     and (select value = '3'::jsonb from pr_settings where key = 'review_days')
                     and (select value = '3'::jsonb from pr_settings where key = 'approve_days')
                     and (select value = '3'::jsonb from pr_settings where key = 'grace_days'), 'الحد الأدنى للعروض ثلاثة، ومدد التنبيه ثلاثة أيام');
select pg_temp.check(public.grant_scope_ok('procurement:buyer') and public.grant_scope_ok('procurement:admin') and public.grant_scope_ok('procurement:audit')
                     and not public.grant_scope_ok('procurement:x'), 'نطاقات المشتريات الثلاثة تقبلها قاعدة البيانات');

-- أصناف المشتريات: ورق (استهلاكي له رصيد) وطابعة (أصل) وقلم، وموردون
reset role;
insert into ids select 'a4', pg_temp.item('ورق A4 80 غم');
insert into ids select 'pen', pg_temp.item('قلم حبر أزرق جاف');
select pg_temp.check((select pg_temp.av(pg_temp.id('a4')) >= 1 from (select 1) x) , 'للورق رصيد متاح من اختبارات المخازن');
set role authenticated;
select pg_temp.as_user('director.new@test.ly', 'aal2');
insert into ids select 'printer', public.st_save_item(null, jsonb_build_object('name', 'طابعة ليزر للمشتريات', 'category_id', pg_temp.cat('OFE'),
  'base_unit_id', pg_temp.unit('قطعة')));
select public.set_user_grants(pg_temp.uid('u.heritage@test.ly'), array['procurement:buyer']);
select public.set_user_grants(pg_temp.uid('k.qa@test.ly'), array['procurement:admin']);
select public.set_user_grants(pg_temp.uid('u.safetyhead@test.ly'), array['procurement:audit']);
select pg_temp.expect_error($q$select public.set_user_grants(pg_temp.uid('pending@test.ly'), array['procurement:nope'])$q$, 'نطاق مشتريات غير معروف يُرفض');
select pg_temp.check((select 'procurement' = any (public.my_sections())), 'المدير يرى قسم المشتريات');
select pg_temp.as_user('pending@test.ly');
select pg_temp.check((select 'procurement' = any (public.my_sections())), 'وكل حساب فعّال يرى قسم المشتريات ليرفع طلباته');
select pg_temp.as_user('auditor@test.ly', 'aal2');
select pg_temp.check((select not ('procurement' = any (public.my_sections()))), 'ولا يراه مسؤول الأمن');
select pg_temp.expect_error($q$select public.pr_save_request(null, '{"title": "طلب", "lines": [{"name": "كراسي", "qty": 1}]}'::jsonb)$q$, 'مسؤول الأمن لا يرفع طلبات');

-- ---------------------------------------------------------------- الموردون والإعدادات
select pg_temp.as_user('k.qa@test.ly');
insert into ids select 's1', public.pr_save_supplier(null, '{"name": "شركة النور للتوريدات", "phone": "0910000001"}'::jsonb);
insert into ids select 's2', public.pr_save_supplier(null, '{"name": "مؤسسة الأفق", "email": "a@ofq.ly"}'::jsonb);
insert into ids select 's3', public.pr_save_supplier(null, '{"name": "مكتبة الصابري"}'::jsonb);
select pg_temp.expect_error($q$select public.pr_save_supplier(null, '{"name": "شركة النور للتوريدات"}'::jsonb)$q$, 'اسم المورد لا يتكرر');
select pg_temp.expect_error($q$select public.pr_save_supplier(null, '{"name": "ا"}'::jsonb)$q$, 'اسم المورد حرفان فأكثر');
select public.pr_save_settings('{"grace_days": 5}'::jsonb);
select pg_temp.check((select value = '5'::jsonb from pr_settings where key = 'grace_days'), 'مدير النظام في المشتريات يعدّل الإعدادات');
select public.pr_save_settings('{"grace_days": 3}'::jsonb);
select pg_temp.expect_error($q$select public.pr_save_settings('{"min_quotes": 0}'::jsonb)$q$, 'الحد الأدنى للعروض من 1 إلى 10');
select pg_temp.expect_error($q$select public.pr_save_settings('{"review_days": 2.5}'::jsonb)$q$, 'المدد أعداد صحيحة');
select pg_temp.expect_error($q$select public.pr_save_settings('{"x": 1}'::jsonb)$q$, 'إعداد غير معروف');
select pg_temp.as_user('u.heritage@test.ly');
select pg_temp.expect_error($q$select public.pr_save_supplier(null, '{"name": "مورد من مسؤول المشتريات"}'::jsonb)$q$, 'مسؤول المشتريات لا يدير الموردين');
select pg_temp.expect_error($q$select public.pr_save_settings('{"grace_days": 4}'::jsonb)$q$, 'ولا الإعدادات');
select pg_temp.check((select count(*) = 3 from pr_suppliers), 'يقرأ أهل القسم الموردين');
select pg_temp.as_user('pending@test.ly');
select pg_temp.check((select count(*) = 0 from pr_suppliers), 'ومن ليس من أهل القسم لا يرى الموردين');

-- ---------------------------------------------------------------- طلب الاحتياج: الحفظ
select pg_temp.as_user('pending@test.ly');
select pg_temp.expect_error($q$select public.pr_save_request(null, '{"title": "ط", "lines": [{"name": "كراسي", "qty": 1}]}'::jsonb)$q$, 'العنوان 3 أحرف فأكثر');
select pg_temp.expect_error($q$select public.pr_save_request(null, '{"title": "طلب بلا بنود", "lines": []}'::jsonb)$q$, 'بند واحد على الأقل');
select pg_temp.expect_error($q$select public.pr_save_request(null, '{"title": "كمية سالبة", "lines": [{"name": "كراسي", "qty": -1}]}'::jsonb)$q$, 'الكمية موجبة');
select pg_temp.expect_error($q$select public.pr_save_request(null, '{"title": "بند بلا وصف", "lines": [{"qty": 1}]}'::jsonb)$q$, 'بند حر بلا وصف');
select pg_temp.expect_error($q$select public.pr_save_request(null, '{"title": "صنف مجهول", "lines": [{"item_id": "00000000-0000-0000-0000-000000000009", "qty": 1}]}'::jsonb)$q$, 'صنف غير موجود');
select pg_temp.expect_error($q$select public.pr_save_request(null, '{"title": "أولوية", "priority": "x", "lines": [{"name": "كراسي", "qty": 1}]}'::jsonb)$q$, 'أولوية غير معروفة');
select pg_temp.expect_error(format($q$select public.pr_save_request(null, jsonb_build_object('title', 'وحدة غير معرّفة', 'lines', jsonb_build_array(
  jsonb_build_object('item_id', %L, 'unit_id', %L, 'qty', 1))))$q$, pg_temp.id('pen'), pg_temp.unit('لتر')), 'وحدة غير معرّفة للصنف');
-- ورق: المتاح + 10، وطابعتان، وبند حر
select pg_temp.as_user('pending@test.ly');
insert into ids select 'r1', public.pr_save_request(null, jsonb_build_object('title', 'احتياج إدارة التقنية', 'reason', 'تجديد الأجهزة', 'priority', 'high',
  'needed_by', (current_date + 20)::text, 'lines', jsonb_build_array(
    jsonb_build_object('item_id', pg_temp.id('a4'), 'qty', (select pg_temp.av(pg_temp.id('a4')) + 10)),
    jsonb_build_object('item_id', pg_temp.id('printer'), 'qty', 2),
    jsonb_build_object('name', 'أقلام سبورة', 'unit_name', 'علبة', 'qty', 4))));
select pg_temp.check((select req_no ~ '^PR-[0-9]{4}-[0-9]{4}$' and status = 'draft' and priority = 'high' and requester_id = pg_temp.uid('pending@test.ly')
                        from pg_temp.rq(pg_temp.id('r1'))), 'الطلب مسودة برقم PR-سنة-تسلسل باسم صاحبه');
select pg_temp.check((select count(*) = 3 and count(*) filter (where item_id is null) = 1 from pr_request_lines where request_id = pg_temp.id('r1')), 'ثلاثة بنود منها حرّ واحد');
select public.pr_save_request(pg_temp.id('r1'), jsonb_build_object('title', 'احتياج إدارة التقنية', 'reason', 'تجديد الأجهزة الحاسوبية', 'priority', 'high',
  'lines', jsonb_build_array(
    jsonb_build_object('item_id', pg_temp.id('a4'), 'qty', (select pg_temp.av(pg_temp.id('a4')) + 10)),
    jsonb_build_object('item_id', pg_temp.id('printer'), 'qty', 2),
    jsonb_build_object('name', 'أقلام سبورة', 'unit_name', 'علبة', 'qty', 4))));
select pg_temp.check((select reason = 'تجديد الأجهزة الحاسوبية' from pg_temp.rq(pg_temp.id('r1'))), 'تعديل المسودة');
select pg_temp.as_user('u.qc@test.ly');
select pg_temp.expect_error(format($q$select public.pr_save_request(%L, '{"title": "تعديل غيرِ صاحبه", "lines": [{"name": "كراسي", "qty": 1}]}'::jsonb)$q$, pg_temp.id('r1')), 'لا يعدّل الطلب غير صاحبه');
select pg_temp.expect_error(format($q$select public.pr_submit(%L)$q$, pg_temp.id('r1')), 'ولا يقدّمه');
select pg_temp.as_user('k.qa@test.ly');
select pg_temp.check((select count(*) = 0 from pr_requests), 'المسودة لا يراها غير صاحبها حتى أهل القسم');
select pg_temp.as_user('pending@test.ly');
select public.pr_submit(pg_temp.id('r1'));
select pg_temp.check((select status = 'submitted' and submitted_at is not null from pg_temp.rq(pg_temp.id('r1'))), 'تقديم الطلب');
select pg_temp.expect_error(format($q$select public.pr_submit(%L)$q$, pg_temp.id('r1')), 'لا يُقدَّم الطلب مرتين');
select pg_temp.expect_error(format($q$select public.pr_save_request(%L, '{"title": "بعد التقديم", "lines": [{"name": "كراسي", "qty": 1}]}'::jsonb)$q$, pg_temp.id('r1')), 'لا يُعدَّل بعد التقديم');
select pg_temp.as_user('k.qa@test.ly');
select pg_temp.check((select count(*) = 1 from pr_requests), 'أهل القسم يرون الطلبات المقدَّمة');
reset role;
select pg_temp.check((select count(*) >= 1 from notifications where kind = 'procurement' and title like 'طلب احتياج جديد%'
                        and user_id = pg_temp.uid('u.qc@test.ly')), 'إشعار مدير المخازن بطلب جديد');
set role authenticated;

-- ---------------------------------------------------------------- مراجعة التوفر
select pg_temp.as_user('u.heritage@test.ly');
select pg_temp.expect_error(format($q$select public.pr_review(%L, '{}'::jsonb)$q$, pg_temp.id('r1')), 'مسؤول المشتريات لا يراجع التوفر');
select pg_temp.as_user('pending@test.ly');
select pg_temp.expect_error(format($q$select public.pr_review(%L, '{}'::jsonb)$q$, pg_temp.id('r1')), 'ولا صاحب الطلب');
select pg_temp.as_user('u.qc@test.ly');
select pg_temp.expect_error(format($q$select public.pr_review(%L, jsonb_build_object('lines', jsonb_build_array(jsonb_build_object('line_id', %L, 'stock_qty', 100000000))))$q$,
  pg_temp.id('r1'), pg_temp.line(pg_temp.id('r1'), 1)), 'المُلبّى من المخزون لا يتجاوز المطلوب');
select pg_temp.expect_error(format($q$select public.pr_review(%L, jsonb_build_object('lines', jsonb_build_array(jsonb_build_object('line_id', %L, 'stock_qty', %s))))$q$,
  pg_temp.id('r1'), pg_temp.line(pg_temp.id('r1'), 1), (select pg_temp.av(pg_temp.id('a4')) + 1)), 'ولا يتجاوز المتاح فعلاً في المخزون');
select pg_temp.expect_error(format($q$select public.pr_review(%L, jsonb_build_object('lines', jsonb_build_array(jsonb_build_object('line_id', %L, 'stock_qty', 1))))$q$,
  pg_temp.id('r1'), pg_temp.line(pg_temp.id('r1'), 3)), 'بند حر لا يُلبّى من المخزون قبل ربطه بصنف');
select pg_temp.expect_error(format($q$select public.pr_review(%L, jsonb_build_object('lines', jsonb_build_array(jsonb_build_object('line_id', %L, 'stock_qty', 1))))$q$,
  pg_temp.id('r1'), '00000000-0000-0000-0000-000000000009'::uuid), 'بند غير تابع للطلب');
select pg_temp.check((select status = 'submitted' from pg_temp.rq(pg_temp.id('r1'))), 'الرفض لم يغيّر حالة الطلب');
-- يلبّي كل المتاح من الورق، ويربط بند الأقلام بصنف القلم
select public.pr_review(pg_temp.id('r1'), jsonb_build_object('note', 'المتاح من الورق يُصرف', 'lines', jsonb_build_array(
  jsonb_build_object('line_id', pg_temp.line(pg_temp.id('r1'), 1), 'stock_qty', (select pg_temp.av(pg_temp.id('a4')))),
  jsonb_build_object('line_id', pg_temp.line(pg_temp.id('r1'), 3), 'item_id', pg_temp.id('pen')))));
select pg_temp.check((select status = 'reviewed' and reviewed_by = pg_temp.uid('u.qc@test.ly') and review_note = 'المتاح من الورق يُصرف'
                        from pg_temp.rq(pg_temp.id('r1'))), 'مراجعة التوفر: الطلب «مراجَع» باسم المراجع وملاحظته');
select pg_temp.check((select stock_qty = (select pg_temp.av(pg_temp.id('a4'))) and qty - stock_qty = 10 from pr_request_lines where id = pg_temp.line(pg_temp.id('r1'), 1)),
                     'يبقى للشراء عشر رزم من الورق');
select pg_temp.check((select item_id = pg_temp.id('pen') and unit_id = (select base_unit_id from st_items where id = pg_temp.id('pen')) and unit_name = '' from pr_request_lines where id = pg_temp.line(pg_temp.id('r1'), 3)),
                     'البند الحر رُبط بصنف ووحدته الأساسية');
select public.pr_review(pg_temp.id('r1'), '{}'::jsonb);
select pg_temp.check((select status = 'reviewed' from pg_temp.rq(pg_temp.id('r1'))), 'تجوز إعادة المراجعة قبل الاعتماد');
-- طلب يكتفي من المخزون كله
select pg_temp.as_user('pending@test.ly');
insert into ids select 'r2', public.pr_save_request(null, jsonb_build_object('title', 'ورقتان من المخزون', 'lines', jsonb_build_array(
  jsonb_build_object('item_id', pg_temp.id('a4'), 'qty', 1))));
select public.pr_submit(pg_temp.id('r2'));
select pg_temp.as_user('u.qc@test.ly');
select pg_temp.check(public.pr_review(pg_temp.id('r2'), jsonb_build_object('lines', jsonb_build_array(
  jsonb_build_object('line_id', pg_temp.line(pg_temp.id('r2'), 1), 'stock_qty', 1)))) = 'fulfilled', 'تلبية الطلب كله من المخزون ← «مكتفى من المخزون»');
select pg_temp.check((select status = 'fulfilled' and closed_at is not null from pg_temp.rq(pg_temp.id('r2'))), 'ويُغلق دون اعتماد ولا شراء');
select pg_temp.as_user('director.new@test.ly', 'aal2');
select pg_temp.expect_error(format($q$select public.pr_decide(%L, true)$q$, pg_temp.id('r2')), 'لا يُعتمد طلب مكتفى من المخزون');

-- ---------------------------------------------------------------- الاعتماد وفصل المهام والرفض والإلغاء
select pg_temp.as_user('u.qc@test.ly');
select pg_temp.expect_error(format($q$select public.pr_decide(%L, true)$q$, pg_temp.id('r1')), 'مدير المخازن لا يعتمد الشراء');
select pg_temp.as_user('u.heritage@test.ly');
select pg_temp.expect_error(format($q$select public.pr_decide(%L, true)$q$, pg_temp.id('r1')), 'ولا مسؤول المشتريات');
-- طلب راجعه المدير نفسه: لا يعتمده (فصل المهام)
select pg_temp.as_user('pending@test.ly');
insert into ids select 'r3', public.pr_save_request(null, jsonb_build_object('title', 'طلب راجعه المدير', 'lines', jsonb_build_array(
  jsonb_build_object('name', 'ستائر', 'unit_name', 'قطعة', 'qty', 3))));
select public.pr_submit(pg_temp.id('r3'));
select pg_temp.as_user('director.new@test.ly', 'aal2');
select public.pr_review(pg_temp.id('r3'), '{}'::jsonb);
select pg_temp.expect_error(format($q$select public.pr_decide(%L, true)$q$, pg_temp.id('r3')), 'فصل المهام: من راجع الطلب لا يعتمده');
select pg_temp.expect_error(format($q$select public.pr_reject(%L, '')$q$, pg_temp.id('r3')), 'الرفض يحتاج سبباً');
select public.pr_reject(pg_temp.id('r3'), 'لا حاجة إليها الآن');
select pg_temp.check((select status = 'rejected' and decision_note = 'لا حاجة إليها الآن' and closed_at is not null from pg_temp.rq(pg_temp.id('r3'))), 'رفض الطلب بسبب');
select pg_temp.expect_error(format($q$select public.pr_decide(%L, true)$q$, pg_temp.id('r3')), 'لا يُعتمد طلب مرفوض');
select pg_temp.as_user('pending@test.ly');
select pg_temp.check((select count(*) >= 1 from notifications where user_id = pg_temp.uid('pending@test.ly') and kind = 'procurement' and title like 'رُفض طلبك%'), 'إشعار صاحب الطلب بالرفض');
-- إلغاء صاحب الطلب قبل مراجعته
insert into ids select 'r4', public.pr_save_request(null, jsonb_build_object('title', 'طلب سيُلغى', 'lines', jsonb_build_array(jsonb_build_object('name', 'مناديل', 'qty', 10))));
select public.pr_cancel(pg_temp.id('r4'), 'لم تعد الحاجة قائمة');
select pg_temp.check((select status = 'cancelled' from pg_temp.rq(pg_temp.id('r4'))), 'صاحب الطلب يلغي مسودته');
-- مدير يعتمد بعد مراجعة غيره
select pg_temp.as_user('director.new@test.ly', 'aal2');
select public.pr_decide(pg_temp.id('r1'), true, 'موافق');
select pg_temp.check((select status = 'approved' and decided_by = pg_temp.uid('director.new@test.ly') from pg_temp.rq(pg_temp.id('r1'))), 'المدير يعتمد الطلب بعد مراجعة مدير المخازن');
select pg_temp.expect_error(format($q$select public.pr_decide(%L, true)$q$, pg_temp.id('r1')), 'لا يُعتمد الطلب مرتين');
select pg_temp.expect_error(format($q$select public.pr_review(%L, '{}'::jsonb)$q$, pg_temp.id('r1')), 'لا تُراجَع الطلبات بعد اعتمادها');
select pg_temp.as_user('pending@test.ly');
select pg_temp.expect_error(format($q$select public.pr_cancel(%L)$q$, pg_temp.id('r1')), 'صاحب الطلب لا يلغيه بعد اعتماده');

-- ---------------------------------------------------------------- عروض الأسعار وأمر الشراء
select pg_temp.as_user('pending@test.ly');
select pg_temp.expect_error(format($q$select public.pr_save_quote(%L, jsonb_build_object('supplier_id', %L, 'total', 100))$q$, pg_temp.id('r1'), pg_temp.id('s1')), 'صاحب الطلب لا يسجّل عروضاً');
select pg_temp.as_user('u.heritage@test.ly');
select pg_temp.expect_error(format($q$select public.pr_save_quote(%L, jsonb_build_object('supplier_id', %L, 'total', -5))$q$, pg_temp.id('r1'), pg_temp.id('s1')), 'إجمالي العرض غير سالب');
select pg_temp.expect_error(format($q$select public.pr_save_quote(%L, jsonb_build_object('supplier_id', %L, 'total', 100, 'delivery_days', 800))$q$, pg_temp.id('r1'), pg_temp.id('s1')), 'مدة التوريد حتى 730 يوماً');
select pg_temp.expect_error(format($q$select public.pr_save_quote(%L, jsonb_build_object('supplier_id', %L, 'total', 100))$q$, pg_temp.id('r1'), '00000000-0000-0000-0000-000000000009'), 'مورد غير موجود');
select public.pr_save_quote(pg_temp.id('r1'), jsonb_build_object('supplier_id', pg_temp.id('s1'), 'total', 3500, 'delivery_days', 10, 'valid_until', (current_date + 30)::text));
select public.pr_save_quote(pg_temp.id('r1'), jsonb_build_object('supplier_id', pg_temp.id('s2'), 'total', 3300, 'delivery_days', 14));
select pg_temp.check((select count(*) = 2 from pr_quotes where request_id = pg_temp.id('r1')), 'عرضان مسجَّلان');
select public.pr_save_quote(pg_temp.id('r1'), jsonb_build_object('supplier_id', pg_temp.id('s2'), 'total', 3250, 'delivery_days', 14));
select pg_temp.check((select count(*) = 2 and min(total) = 3250 from pr_quotes where request_id = pg_temp.id('r1')), 'إعادة تسجيل عرض المورد نفسه تحدّثه ولا تكرّره');
insert into ids select 'q1', (select id from pr_quotes where request_id = pg_temp.id('r1') and supplier_id = pg_temp.id('s1'));
insert into ids select 'q2', (select id from pr_quotes where request_id = pg_temp.id('r1') and supplier_id = pg_temp.id('s2'));
-- العروض أقل من الحد الأدنى (3)
select pg_temp.expect_error(format($q$select public.pr_issue_order(%L, jsonb_build_object('quote_id', %L, 'warehouse_id', %L, 'lines', '[]'::jsonb))$q$,
  pg_temp.id('r1'), pg_temp.id('q2'), pg_temp.wh('main')), 'عرضان أقل من الحد الأدنى: لا أمر بلا استثناء');
select pg_temp.expect_error(format($q$select public.pr_issue_order(%L, jsonb_build_object('quote_id', %L, 'warehouse_id', %L, 'waiver_note', 'استعجال الحاجة'))$q$,
  pg_temp.id('r1'), pg_temp.id('q2'), pg_temp.wh('main')), 'الاستثناء للمدير وحده');
select public.pr_save_quote(pg_temp.id('r1'), jsonb_build_object('supplier_id', pg_temp.id('s3'), 'total', 3400));
insert into ids select 'q3', (select id from pr_quotes where request_id = pg_temp.id('r1') and supplier_id = pg_temp.id('s3'));
select public.pr_delete_quote(pg_temp.id('q3'));
select pg_temp.check((select count(*) = 2 from pr_quotes where request_id = pg_temp.id('r1')), 'حذف عرض قبل الأمر');
select public.pr_save_quote(pg_temp.id('r1'), jsonb_build_object('supplier_id', pg_temp.id('s3'), 'total', 3400));
insert into ids select 'q3b', (select id from pr_quotes where request_id = pg_temp.id('r1') and supplier_id = pg_temp.id('s3'));
select pg_temp.expect_error(format($q$select public.pr_issue_order(%L, jsonb_build_object('quote_id', %L, 'warehouse_id', null))$q$, pg_temp.id('r1'), pg_temp.id('q2')), 'مخزن الاستلام مطلوب');
select pg_temp.expect_error(format($q$select public.pr_issue_order(%L, jsonb_build_object('quote_id', %L, 'warehouse_id', %L, 'expected_date', (current_date - 3)::text))$q$,
  pg_temp.id('r1'), pg_temp.id('q2'), pg_temp.wh('main')), 'تاريخ التوريد المتوقع ليس في الماضي');
select pg_temp.expect_error(format($q$select public.pr_issue_order(%L, jsonb_build_object('quote_id', %L, 'warehouse_id', %L))$q$,
  pg_temp.id('r1'), pg_temp.id('r1'), pg_temp.wh('main')), 'اختيار عرض لا يتبع الطلب');
-- أسعار الوحدات: ورق 20، طابعة 1500، قلم 3  ←  10×20 + 2×1500 + 4×3 = 200 + 3000 + 12 = 3212
insert into ids select 'o1', public.pr_issue_order(pg_temp.id('r1'), jsonb_build_object('quote_id', pg_temp.id('q2'), 'warehouse_id', pg_temp.wh('main'),
  'expected_date', (current_date + 7)::text, 'lines', jsonb_build_array(
    jsonb_build_object('line_id', pg_temp.line(pg_temp.id('r1'), 1), 'unit_price', 20),
    jsonb_build_object('line_id', pg_temp.line(pg_temp.id('r1'), 2), 'unit_price', 1500),
    jsonb_build_object('line_id', pg_temp.line(pg_temp.id('r1'), 3), 'unit_price', 3))));
select pg_temp.check((select po_no ~ '^PO-[0-9]{4}-[0-9]{4}$' and status = 'issued' and total = 3212 and supplier_id = pg_temp.id('s2') and waiver_note = ''
                        from pg_temp.od(pg_temp.id('o1'))), 'أمر الشراء برقم PO وإجمالي 200 + 3,000 + 12 = 3,212 دون استثناء');
select pg_temp.check((select status = 'ordered' from pg_temp.rq(pg_temp.id('r1'))), 'الطلب «مأمور»');
select pg_temp.check((select count(*) = 3 and sum(qty) = 16 from pr_order_lines where order_id = pg_temp.id('o1')), 'ثلاثة بنود بكمية 10 + 2 + 4 للشراء');
select pg_temp.check((select selected from pr_quotes where id = pg_temp.id('q2')) and (select count(*) = 1 from pr_quotes where request_id = pg_temp.id('r1') and selected),
                     'العرض الفائز وحده مختار');
select pg_temp.expect_error(format($q$select public.pr_issue_order(%L, jsonb_build_object('quote_id', %L, 'warehouse_id', %L))$q$,
  pg_temp.id('r1'), pg_temp.id('q2'), pg_temp.wh('main')), 'لا أمر ثانٍ لطلب مأمور');
select pg_temp.expect_error(format($q$select public.pr_delete_quote(%L)$q$, pg_temp.id('q2')), 'لا يُحذف عرض بُني عليه أمر');
select pg_temp.as_user('pending@test.ly');
select pg_temp.check((select count(*) = 1 from pr_orders where request_id = pg_temp.id('r1')) and (select count(*) = 3 from pr_order_lines),
                     'صاحب الطلب يرى أمر طلبه وبنوده');
select pg_temp.check((select count(*) = 0 from pr_quotes), 'ولا يرى العروض');

-- ---------------------------------------------------------------- الاستلام على دفعات
select pg_temp.as_user('u.heritage@test.ly');
select pg_temp.expect_error(format($q$select public.pr_receive(%L, jsonb_build_object('lines', jsonb_build_array(jsonb_build_object('line_id', %L, 'qty', 1))))$q$,
  pg_temp.id('o1'), pg_temp.oline(pg_temp.id('o1'), pg_temp.line(pg_temp.id('r1'), 1))), 'مسؤول المشتريات بلا صلاحية مخزن لا يستلم للمخزون');
select pg_temp.as_user('pending@test.ly');
select pg_temp.expect_error(format($q$select public.pr_receive(%L, jsonb_build_object('lines', jsonb_build_array(jsonb_build_object('line_id', %L, 'qty', 1))))$q$,
  pg_temp.id('o1'), pg_temp.oline(pg_temp.id('o1'), pg_temp.line(pg_temp.id('r1'), 1))), 'ولا صاحب الطلب');
select pg_temp.as_user('u.qc@test.ly');
select pg_temp.expect_error(format($q$select public.pr_receive(%L, '{"lines": []}'::jsonb)$q$, pg_temp.id('o1')), 'حدّد الكميات المستلَمة');
select pg_temp.expect_error(format($q$select public.pr_receive(%L, jsonb_build_object('lines', jsonb_build_array(jsonb_build_object('line_id', %L, 'qty', 11))))$q$,
  pg_temp.id('o1'), pg_temp.oline(pg_temp.id('o1'), pg_temp.line(pg_temp.id('r1'), 1))), 'لا يُستلم أكثر من الكمية');
select pg_temp.expect_error(format($q$select public.pr_receive(%L, jsonb_build_object('lines', jsonb_build_array(jsonb_build_object('line_id', %L, 'qty', 1.5))))$q$,
  pg_temp.id('o1'), pg_temp.oline(pg_temp.id('o1'), pg_temp.line(pg_temp.id('r1'), 2))), 'كميات الأصول أعداد صحيحة');
-- الدفعة الأولى: 4 رزم ورق وطابعة واحدة
select public.pr_receive(pg_temp.id('o1'), jsonb_build_object('invoice_no', 'INV-77', 'note', 'الدفعة الأولى', 'lines', jsonb_build_array(
  jsonb_build_object('line_id', pg_temp.oline(pg_temp.id('o1'), pg_temp.line(pg_temp.id('r1'), 1)), 'qty', 4),
  jsonb_build_object('line_id', pg_temp.oline(pg_temp.id('o1'), pg_temp.line(pg_temp.id('r1'), 2)), 'qty', 1))));
select pg_temp.check((select status = 'partial' from pg_temp.od(pg_temp.id('o1'))) and (select status = 'partial' from pg_temp.rq(pg_temp.id('r1'))),
                     'استلام جزئي: الأمر والطلب «مستلَم جزئياً»');
select pg_temp.check((select count(*) = 1 and bool_and(cost = 1500 and supplier = 'مؤسسة الأفق' and invoice_no = 'INV-77' and warehouse_id = pg_temp.wh('main'))
                        from st_assets where item_id = pg_temp.id('printer')), 'أصل مسجَّل بتكلفة الوحدة من الأمر ومورده وفاتورته ومخزنه');
select pg_temp.check((select count(*) = 1 and bool_and(d.status = 'draft' and d.ref_no = (select po_no from pg_temp.od(pg_temp.id('o1'))) and d.party = 'مؤسسة الأفق')
                        from st_docs d where d.kind = 'receipt' and d.ref_no like 'PO-%'), 'مستند استلام (مسودة) في المخازن برقم الأمر ومورده');
select pg_temp.check((select l.qty = 4 from st_doc_lines l join st_docs d on d.id = l.doc_id where d.ref_no like 'PO-%' limit 1), 'ببند الورق: 4 رزم');
select pg_temp.check((select sum(received) = 5 from pr_order_lines where order_id = pg_temp.id('o1')), 'المستلَم 4 + 1');
select pg_temp.expect_error(format($q$select public.pr_cancel_order(%L, 'سبب')$q$, pg_temp.id('o1')), 'لا يُلغى أمر بدأ استلامه');
-- الدفعة الأخيرة
select public.pr_receive(pg_temp.id('o1'), jsonb_build_object('lines', jsonb_build_array(
  jsonb_build_object('line_id', pg_temp.oline(pg_temp.id('o1'), pg_temp.line(pg_temp.id('r1'), 1)), 'qty', 6),
  jsonb_build_object('line_id', pg_temp.oline(pg_temp.id('o1'), pg_temp.line(pg_temp.id('r1'), 2)), 'qty', 1),
  jsonb_build_object('line_id', pg_temp.oline(pg_temp.id('o1'), pg_temp.line(pg_temp.id('r1'), 3)), 'qty', 4))));
select pg_temp.check((select status = 'received' and closed_at is not null from pg_temp.od(pg_temp.id('o1')))
                     and (select status = 'received' and closed_at is not null from pg_temp.rq(pg_temp.id('r1'))), 'اكتمل الاستلام: الأمر والطلب «مستلَم»');
select pg_temp.check((select count(*) = 2 from st_assets where item_id = pg_temp.id('printer')), 'أصلان للطابعتين');
select pg_temp.check((select count(*) = 2 from st_docs where kind = 'receipt' and ref_no like 'PO-%'), 'ومستندا استلام للدفعتين');
select pg_temp.check((select count(*) = 2 from pr_receipts where order_id = pg_temp.id('o1')) and (select cardinality(asset_ids) = 1 from pr_receipts
                        where order_id = pg_temp.id('o1') order by received_at limit 1), 'سجل الاستلام لكل دفعة بأصوله ومستنده');
select pg_temp.expect_error(format($q$select public.pr_receive(%L, jsonb_build_object('lines', jsonb_build_array(jsonb_build_object('line_id', %L, 'qty', 1))))$q$,
  pg_temp.id('o1'), pg_temp.oline(pg_temp.id('o1'), pg_temp.line(pg_temp.id('r1'), 1))), 'لا يُستلم أمر مغلق');
select pg_temp.check((select pg_temp.events(pg_temp.id('r1')) like 'create%submit%review%approve%quote%order%receive%receive'),
                     'سجل أحداث الطلب بمساره كله');

-- ---------------------------------------------------------------- استثناء المدير وإلغاء الأمر
select pg_temp.as_user('pending@test.ly');
insert into ids select 'r5', public.pr_save_request(null, jsonb_build_object('title', 'مصابيح للمقر', 'lines', jsonb_build_array(
  jsonb_build_object('item_id', pg_temp.id('pen'), 'qty', 20))));
select public.pr_submit(pg_temp.id('r5'));
select pg_temp.as_user('u.qc@test.ly');
select public.pr_review(pg_temp.id('r5'), '{}'::jsonb);
select pg_temp.as_user('director.new@test.ly', 'aal2');
select public.pr_decide(pg_temp.id('r5'), true);
select pg_temp.as_user('u.heritage@test.ly');
select public.pr_save_quote(pg_temp.id('r5'), jsonb_build_object('supplier_id', pg_temp.id('s1'), 'total', 60));
insert into ids select 'q5', (select id from pr_quotes where request_id = pg_temp.id('r5'));
select pg_temp.as_user('director.new@test.ly', 'aal2');
select pg_temp.expect_error(format($q$select public.pr_issue_order(%L, jsonb_build_object('quote_id', %L, 'warehouse_id', %L, 'waiver_note', 'ق'))$q$,
  pg_temp.id('r5'), pg_temp.id('q5'), pg_temp.wh('main')), 'سبب الاستثناء خمسة أحرف فأكثر');
insert into ids select 'o5', public.pr_issue_order(pg_temp.id('r5'), jsonb_build_object('quote_id', pg_temp.id('q5'), 'warehouse_id', pg_temp.wh('main'),
  'waiver_note', 'مورد وحيد للصنف', 'lines', jsonb_build_array(jsonb_build_object('line_id', pg_temp.line(pg_temp.id('r5'), 1), 'unit_price', 3))));
select pg_temp.check((select waiver_note = 'مورد وحيد للصنف' and total = 60 from pg_temp.od(pg_temp.id('o5'))), 'المدير يستثني الحد الأدنى للعروض بسبب مكتوب');
select pg_temp.as_user('u.heritage@test.ly');
select pg_temp.expect_error(format($q$select public.pr_cancel_order(%L, '')$q$, pg_temp.id('o5')), 'إلغاء الأمر يحتاج سبباً');
select public.pr_cancel_order(pg_temp.id('o5'), 'تغيّر المورد');
select pg_temp.check((select status = 'cancelled' from pg_temp.od(pg_temp.id('o5'))) and (select status = 'approved' from pg_temp.rq(pg_temp.id('r5')))
                     and (select not selected from pr_quotes where id = pg_temp.id('q5')), 'إلغاء الأمر قبل الاستلام: يعود الطلب «معتمداً» ويُحرَّر العرض');
select pg_temp.as_user('director.new@test.ly', 'aal2');
insert into ids select 'o5b', public.pr_issue_order(pg_temp.id('r5'), jsonb_build_object('quote_id', pg_temp.id('q5'), 'warehouse_id', pg_temp.wh('main'),
  'waiver_note', 'مورد وحيد للصنف', 'lines', jsonb_build_array(jsonb_build_object('line_id', pg_temp.line(pg_temp.id('r5'), 1), 'unit_price', 3))));
select pg_temp.check((select count(*) = 2 and count(*) filter (where status = 'cancelled') = 1 from pr_orders where request_id = pg_temp.id('r5')), 'أمر جديد بعد إلغاء الأول');
select pg_temp.as_user('pending@test.ly');
select pg_temp.expect_error(format($q$select public.pr_cancel(%L)$q$, pg_temp.id('r5')), 'صاحب الطلب لا يلغي طلباً مأموراً');
select pg_temp.as_user('director.new@test.ly', 'aal2');
select pg_temp.expect_error(format($q$select public.pr_cancel(%L)$q$, pg_temp.id('r5')), 'ولا يُلغى طلب بأمر قائم (يُلغى الأمر أولاً)');

-- ---------------------------------------------------------------- التعليقات والرؤية
select pg_temp.as_user('pending@test.ly');
select public.pr_comment(pg_temp.id('r5'), 'متى يصل؟');
select pg_temp.expect_error(format($q$select public.pr_comment(%L, '')$q$, pg_temp.id('r5')), 'التعليق فارغ');
select pg_temp.as_user('k.qa@test.ly');
select pg_temp.check((select count(*) >= 3 from pr_requests), 'مدير النظام في المشتريات يرى كل الطلبات');
select pg_temp.as_user('u.safetyhead@test.ly');
select pg_temp.check((select count(*) >= 3 from pr_requests) and (select count(*) >= 1 from pr_orders), 'المراجع يطّلع');
select pg_temp.expect_error(format($q$select public.pr_save_quote(%L, jsonb_build_object('supplier_id', %L, 'total', 1))$q$, pg_temp.id('r5'), pg_temp.id('s2')), 'المراجع لا يكتب');
select pg_temp.as_user('u.safety@test.ly');
select pg_temp.check((select count(*) = 0 from pr_requests), 'ومن لا صلة له بالقسم لا يرى طلبات غيره');
select pg_temp.expect_error(format($q$select public.pr_comment(%L, 'تعليق')$q$, pg_temp.id('r5')), 'ولا يعلّق عليها');

-- ---------------------------------------------------------------- بيانات الاختيار
select pg_temp.as_user('pending@test.ly');
select pg_temp.check((select jsonb_array_length(public.pr_lookups() -> 'items') >= 3 and (public.pr_lookups() -> 'items' -> 0 -> 'available') = 'null'::jsonb
                        and jsonb_array_length(public.pr_lookups() -> 'warehouses') = 0), 'مقدّم الطلب يرى الأصناف دون الأرصدة ولا المخازن');
select pg_temp.as_user('u.qc@test.ly');
select pg_temp.check((select jsonb_array_length(public.pr_lookups() -> 'warehouses') >= 1 and (public.pr_lookups() -> 'items' -> 0 ->> 'available') is not null), 'والمراجع يرى المتاح والمخازن');

-- ---------------------------------------------------------------- لا كتابة مباشرة
select pg_temp.as_user('pending@test.ly');
select pg_temp.expect_error($q$insert into pr_requests (req_no, title) values ('PR-X', 'طلب مباشر')$q$, 'لا إدراج مباشر في الطلبات');
select pg_temp.expect_error(format($q$update pr_requests set status = 'received' where id = %L$q$, pg_temp.id('r5')), 'لا تحديث مباشر');
select pg_temp.expect_error($q$delete from pr_events$q$, 'لا حذف من سجل الأحداث');
select pg_temp.as_user('director.new@test.ly', 'aal2');
select pg_temp.expect_error($q$update pr_orders set status = 'received'$q$, 'ولا للمدير في الأوامر');
select pg_temp.expect_error($q$update pr_order_lines set received = qty$q$, 'ولا في بنود الأوامر');

-- ---------------------------------------------------------------- التجميد الطارئ
reset role;
update app_settings set value = 'true' where key = 'security.freeze';
set role authenticated;
select pg_temp.as_user('pending@test.ly');
select pg_temp.expect_error($q$select public.pr_save_request(null, '{"title": "وقت التجميد", "lines": [{"name": "كراسي", "qty": 1}]}'::jsonb)$q$, 'لا طلبات في وضع القراءة فقط');
select pg_temp.as_user('u.heritage@test.ly');
select pg_temp.expect_error(format($q$select public.pr_save_quote(%L, jsonb_build_object('supplier_id', %L, 'total', 1))$q$, pg_temp.id('r5'), pg_temp.id('s2')), 'ولا عروض');
select pg_temp.as_user('director.new@test.ly', 'aal2');
select public.pr_comment(pg_temp.id('r5'), 'المدير يعمل في وضع القراءة فقط');
reset role;
update app_settings set value = 'false' where key = 'security.freeze';

-- ---------------------------------------------------------------- سلامة البيانات وسجل التدقيق
select pg_temp.check((select count(*) = 0 from pr_orders o join pr_requests r on r.id = o.request_id where o.status <> 'cancelled' and r.status not in ('ordered', 'partial', 'received')),
                     'كل أمر قائم طلبه مأمور أو مستلَم');
select pg_temp.check((select count(*) = 0 from pr_order_lines where received > qty), 'لا استلام فوق الكمية');
select pg_temp.check((select count(*) = 0 from pr_requests where status in ('approved', 'ordered', 'partial', 'received') and decided_by is null), 'كل طلب معتمد له معتمِد');
select pg_temp.check((select count(distinct action) >= 13 from audit_log where action in ('procurement.request', 'procurement.submit', 'procurement.review',
                        'procurement.reject', 'procurement.decide', 'procurement.cancel', 'procurement.supplier', 'procurement.quote', 'procurement.quote_delete',
                        'procurement.order', 'procurement.order_cancel', 'procurement.receive', 'procurement.settings', 'procurement.comment')),
                     'إجراءات المشتريات في سجل التدقيق');
