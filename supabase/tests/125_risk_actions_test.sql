-- اختبارات الترحيل 43: إجراءات الاستجابة للمخاطر (الحفظ والحالة والحذف والصلاحية والتدقيق) ومخاطر الأقسام الآلية
-- (المخازن والمشتريات والصيانة: الفتح والتحديث والإغلاق وإعادة الفتح) وتحديث الساعة. يُشغَّل بعد اختبارات 124
-- وعلى بياناتها، وبعد تطبيق 20261204000043_risk_actions_sections.sql مرتين والتراجع عنه وإعادته.
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
create or replace function pg_temp.rk(p_key text) returns public.risks language sql security definer as $$ select * from public.risks where auto_key = p_key $$;

update app_settings set value = 'false' where key in ('security.freeze', 'security.require_mfa_all');
update profiles set locked_until = null where email in ('director.new@test.ly', 'u.qc@test.ly', 'u.safety@test.ly', 'pending@test.ly', 'qa@test.ly');
create temp table ids (k text primary key, v uuid);
grant all on ids to authenticated;

-- خطر قائم للاختبار
insert into ids select 'risk', id from public.risks order by code limit 1;

-- 1) إجراءات الاستجابة
select pg_temp.as_user('director.new@test.ly', 'aal2');
set role authenticated;
insert into ids select 'act', public.risk_action_save(null, (select v from ids where k = 'risk'),
  '{"title":"إعادة جدولة التوريد","owner":"م. أحمد","due_date":"2026-12-20","note":"بالتنسيق مع المشتريات"}'::jsonb);
select pg_temp.check((select count(*) from public.risk_actions where id = (select v from ids where k = 'act') and status = 'open' and owner = 'م. أحمد') = 1,
  'حفظ إجراء استجابة جديد مفتوحاً');
select public.risk_action_save((select v from ids where k = 'act'), null, '{"title":"إعادة جدولة التوريد مع المورّد","owner":"م. أحمد"}'::jsonb);
select pg_temp.check((select title from public.risk_actions where id = (select v from ids where k = 'act')) = 'إعادة جدولة التوريد مع المورّد'
  and (select due_date from public.risk_actions where id = (select v from ids where k = 'act')) is null, 'تعديل الإجراء يستبدل حقوله');
select pg_temp.expect_error(format($q$select public.risk_action_save(null, %L, '{"title":"ا"}')$q$, (select v from ids where k = 'risk')), 'عنوان الإجراء أقصر من 3 أحرف');
select pg_temp.expect_error(format($q$select public.risk_action_save(null, %L, '{"title":"إجراء صالح","due_date":"غد"}')$q$, (select v from ids where k = 'risk')), 'موعد غير صالح');
select pg_temp.expect_error($q$select public.risk_action_save(null, gen_random_uuid(), '{"title":"إجراء صالح"}')$q$, 'خطر غير موجود');
select pg_temp.expect_error(format($q$select public.risk_action_status(%L, 'xx')$q$, (select v from ids where k = 'act')), 'حالة غير معروفة');
select pg_temp.expect_error(format($q$select public.risk_action_status(%L, 'cancelled')$q$, (select v from ids where k = 'act')), 'الإلغاء بلا سبب');
select public.risk_action_status((select v from ids where k = 'act'), 'done', 'تم التنفيذ');
select pg_temp.check((select status = 'done' and done_on = current_date and note = 'تم التنفيذ' from public.risk_actions where id = (select v from ids where k = 'act')),
  'إنجاز الإجراء يسجّل تاريخ اليوم');
select public.risk_action_status((select v from ids where k = 'act'), 'open');
select pg_temp.check((select status = 'open' and done_on is null from public.risk_actions where id = (select v from ids where k = 'act')), 'إعادة فتح الإجراء تمسح تاريخ الإنجاز');
select public.risk_action_status((select v from ids where k = 'act'), 'cancelled', 'لم تعد حاجة له');
select pg_temp.check((select status from public.risk_actions where id = (select v from ids where k = 'act')) = 'cancelled', 'إلغاء الإجراء بسبب');
select pg_temp.expect_error($q$insert into public.risk_actions (risk_id, title) select id, 'مباشر' from public.risks limit 1$q$, 'لا كتابة مباشرة على جدول الإجراءات');
reset role;

-- من لا يحرر سجل المخاطر لا يكتب
select pg_temp.as_user('pending@test.ly');
set role authenticated;
select pg_temp.expect_error(format($q$select public.risk_action_save(null, %L, '{"title":"إجراء مرفوض"}')$q$, (select v from ids where k = 'risk')), 'مستخدم معلّق لا يكتب إجراءً');
select pg_temp.expect_error(format($q$select public.risk_action_delete(%L)$q$, (select v from ids where k = 'act')), 'مستخدم معلّق لا يحذف إجراءً');
reset role;

select pg_temp.as_user('director.new@test.ly', 'aal2');
set role authenticated;
select public.risk_action_delete((select v from ids where k = 'act'));
select pg_temp.check((select count(*) from public.risk_actions where id = (select v from ids where k = 'act')) = 0, 'حذف الإجراء');
reset role;
select pg_temp.check((select count(*) from public.audit_log where action in ('risk.action_save', 'risk.action_status', 'risk.action_delete')) >= 6,
  'كل كتابة على الإجراءات مسجَّلة في سجل التدقيق');

-- حذف الخطر يحذف إجراءاته
insert into public.risks (code, description, probability, impact) values ('R998', 'خطر اختبار الإجراءات المتتالية', 2, 2);
insert into public.risk_actions (risk_id, title) select id, 'إجراء تابع' from public.risks where code = 'R998';
delete from public.risks where code = 'R998';
select pg_temp.check((select count(*) from public.risk_actions where title = 'إجراء تابع') = 0, 'حذف الخطر يحذف إجراءاته');

-- 2) مخاطر المخازن
insert into public.st_items (code, name, category_id, base_unit_id, min_qty, critical_qty)
  select 'RSK-0001', 'صنف اختبار المخاطر', (select id from public.st_categories limit 1), (select id from public.st_units limit 1), 10, 2;
insert into ids select 'item', id from public.st_items where code = 'RSK-0001';
select pg_temp.check((select count(*) from public.risk_section_wants() where k = 'st_item:' || (select v from ids where k = 'item')) = 1, 'نفاد صنف له حد أدنى يُطلب خطراً');
select public.risk_sync_sections();
select pg_temp.check((select probability = 5 and impact = 4 and status = 'open' and auto_active and category = 'مخزون' and department = 'المخازن'
                        from pg_temp.rk('st_item:' || (select v from ids where k = 'item'))), 'خطر النفاد: احتمالية 5 وتأثير 4 لصنف حرج');
select pg_temp.check((select count(*) from public.risks where auto_key = 'st_item:' || (select v from ids where k = 'item')) = 1, 'خطر واحد للصنف');
select public.risk_sync_sections();
select pg_temp.check((select count(*) from public.risks where auto_key = 'st_item:' || (select v from ids where k = 'item')) = 1, 'إعادة المزامنة لا تكرّر الخطر');

insert into public.st_stock (warehouse_id, item_id, on_hand) select (select id from public.st_warehouses limit 1), (select v from ids where k = 'item'), 5;
select public.risk_sync_sections();
select pg_temp.check((select probability = 4 from pg_temp.rk('st_item:' || (select v from ids where k = 'item'))), 'نزول المتاح دون الحد الأدنى بلا نفاد: احتمالية 4');
-- المستخدم يعدّل المالك والإجراء فلا يُمَسّان
update public.risks set owner = 'م. مدير المخازن الجديد', mitigation = 'طلب شراء عاجل' where auto_key = 'st_item:' || (select v from ids where k = 'item');
update public.st_stock set on_hand = 50 where item_id = (select v from ids where k = 'item');
select public.risk_sync_sections();
select pg_temp.check((select status = 'closed' and not auto_active and closed_on = current_date and notes like '%زال سببه%' and owner = 'م. مدير المخازن الجديد' and mitigation = 'طلب شراء عاجل'
                        from pg_temp.rk('st_item:' || (select v from ids where k = 'item'))), 'زوال السبب يغلق الخطر ولا يمس ما عدّله المستخدم');
update public.st_stock set on_hand = 0 where item_id = (select v from ids where k = 'item');
select public.risk_sync_sections();
select pg_temp.check((select status = 'open' and auto_active and closed_on is null and probability = 5 from pg_temp.rk('st_item:' || (select v from ids where k = 'item'))), 'عودة السبب تعيد فتح الخطر');
-- أغلقه المستخدم والسبب قائم: لا يُعاد فتحه
update public.risks set status = 'closed', closed_on = current_date where auto_key = 'st_item:' || (select v from ids where k = 'item');
select public.risk_sync_sections();
select pg_temp.check((select status = 'closed' and auto_active from pg_temp.rk('st_item:' || (select v from ids where k = 'item'))), 'ما أغلقه المستخدم والسبب قائم لا يُعاد فتحه');
update public.st_items set active = false where id = (select v from ids where k = 'item');
select public.risk_sync_sections();
select pg_temp.check((select not auto_active from pg_temp.rk('st_item:' || (select v from ids where k = 'item'))), 'تعطيل الصنف يُنهي سببه');

-- 3) مخاطر الصيانة
insert into public.mt_requests (req_no, title, priority, status, vendor, due_at)
  values ('MT-RSK-1', 'تسرب في سقف الممر', 'urgent', 'in_progress', 'مقاول خارجي', now() - interval '10 days');
insert into ids select 'mt', id from public.mt_requests where req_no = 'MT-RSK-1';
select public.risk_sync_sections();
select pg_temp.check((select probability = 5 and impact = 5 and category = 'صيانة' and time_impact_days >= 9 from pg_temp.rk('mt_req:' || (select v from ids where k = 'mt'))),
  'بلاغ عاجل متأخر 10 أيام: احتمالية 5 وتأثير 5');
update public.mt_requests set status = 'done', done_at = now() where id = (select v from ids where k = 'mt');
select public.risk_sync_sections();
select pg_temp.check((select status = 'closed' and not auto_active from pg_temp.rk('mt_req:' || (select v from ids where k = 'mt'))), 'إنجاز البلاغ يغلق خطره');
insert into public.mt_requests (req_no, title, priority, status, vendor, due_at)
  values ('MT-RSK-2', 'مفتاح إنارة', 'low', 'new', '', now() - interval '1 day');
select public.risk_sync_sections();
select pg_temp.check((select count(*) from public.risks where auto_key = 'mt_req:' || (select id from public.mt_requests where req_no = 'MT-RSK-2')) = 1
                     and (select probability = 4 and impact = 2 from pg_temp.rk('mt_req:' || (select id from public.mt_requests where req_no = 'MT-RSK-2'))),
  'بلاغ جديد منخفض متأخر يوماً: احتمالية 4 وتأثير 2');
delete from public.mt_requests where req_no in ('MT-RSK-1', 'MT-RSK-2');

-- 4) مخاطر المشتريات (على أمر قائم إن وُجد)
do $$
declare o public.pr_orders; k text;
begin
  select * into o from public.pr_orders where status in ('issued', 'partial') order by issued_at limit 1;
  if o.id is null then
    raise notice 'PASS: لا أمر شراء مفتوح في بيانات الاختبار، فتُتجاوز حالة المشتريات';
    return;
  end if;
  update public.pr_orders set expected_date = current_date - 20 where id = o.id;
  perform public.risk_sync_sections();
  k := 'pr_order:' || o.id;
  perform pg_temp.check((select probability = 5 and impact = 3 and category = 'توريد' and time_impact_days = 20 from public.risks where auto_key = k), 'أمر متأخر 20 يوماً: احتمالية 5 وتأثير 3');
  update public.pr_orders set expected_date = current_date + 5 where id = o.id;
  perform public.risk_sync_sections();
  perform pg_temp.check((select status = 'closed' and not auto_active from public.risks where auto_key = k), 'عودة الأمر داخل موعده تغلق الخطر');
  update public.pr_orders set expected_date = o.expected_date where id = o.id;
end $$;

-- 5) تحديث الساعة: يُنفَّذ مرة واحدة في الساعة، ولا يعمل لغير عضو
select pg_temp.as_user('director.new@test.ly', 'aal2');
set role authenticated;
select pg_temp.expect_error($q$select public.risk_sync_sections()$q$, 'المزامنة الداخلية غير متاحة للمستخدمين');
select pg_temp.expect_error($q$select * from public.risk_section_wants()$q$, 'دالة الأسباب غير متاحة للمستخدمين');
select pg_temp.check(public.risk_refresh_sections() >= 0, 'التحديث الأول يعمل');
select pg_temp.check(public.risk_refresh_sections() = 0, 'التحديث الثاني خلال ساعة لا يعمل شيئاً');
reset role;
select pg_temp.as_user('pending@test.ly');
set role authenticated;
select pg_temp.expect_error($q$select public.risk_refresh_sections()$q$, 'مستخدم معلّق لا يشغّل التحديث');
reset role;

-- تنظيف
delete from public.risks where auto_key ~ '^(st_item|pr_order|mt_req):';
delete from public.st_stock where item_id = (select v from ids where k = 'item');
delete from public.st_items where id = (select v from ids where k = 'item');
delete from public.risk_auto_runs;

-- يبقى إجراء واحد ليُرفض التراجع وفي السجل إجراءات
insert into public.risk_actions (risk_id, title) select v, 'إجراء باقٍ لاختبار رفض التراجع' from ids where k = 'risk';
