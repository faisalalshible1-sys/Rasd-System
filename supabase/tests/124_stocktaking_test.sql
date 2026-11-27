-- اختبارات الترحيل 42: الجرد الدوري بالتسوية — البدء والعدّ والتقديم وقرار مدير المخازن (الاعتماد والإعادة)،
-- وفصل المهام، وتولّد تسوية معتمدة بالفروق الحقيقية وترحيلها، والرؤية، وسجل التدقيق. يُشغَّل بعد اختبارات الترحيل 41 (123)
-- وعلى بياناتها، وبعد تطبيق 20261203000042_stocktaking.sql مرتين والتراجع عنه وإعادته.
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
create or replace function pg_temp.wh(p_code text) returns uuid language sql security definer as $$ select id from public.st_warehouses where lower(code) = lower(p_code) $$;
create or replace function pg_temp.cat(p_code text) returns uuid language sql security definer as $$ select id from public.st_categories where code = p_code $$;
create or replace function pg_temp.unit(p_name text) returns uuid language sql security definer as $$ select id from public.st_units where name = p_name $$;
create or replace function pg_temp.cnt(p_id uuid) returns setof public.st_counts language sql security definer as $$ select * from public.st_counts where id = p_id $$;
-- بنود غير ذات صلاحية لها رصيد متاح في المخزن (للخسارة والزيادة)
create or replace function pg_temp.pick(p_count uuid, p_n int) returns uuid language sql security definer as $$
  select cl.item_id from public.st_count_lines cl join public.st_items i on i.id = cl.item_id
    join public.st_stock s on s.item_id = cl.item_id and s.warehouse_id = (select warehouse_id from public.st_counts where id = p_count)
   where cl.count_id = p_count and not i.tracks_expiry and s.on_hand - s.reserved >= 1
   order by i.name offset p_n limit 1
$$;
-- يكتب لكل البنود كمياتها الدفترية (عدّ مطابق)، ثم يعدّل ما يلزم
create or replace function pg_temp.all_as_system(p_count uuid) returns jsonb language sql security definer as $$
  select coalesce(jsonb_agg(jsonb_build_object('item_id', item_id, 'counted_qty', system_qty)), '[]'::jsonb)
    from public.st_count_lines where count_id = p_count
$$;
create or replace function pg_temp.onhand(p_wh uuid, p_item uuid) returns numeric language sql security definer as $$
  select coalesce((select on_hand from public.st_stock where warehouse_id = p_wh and item_id = p_item), 0)
$$;
create or replace function pg_temp.reserved(p_wh uuid, p_item uuid) returns numeric language sql security definer as $$
  select coalesce((select reserved from public.st_stock where warehouse_id = p_wh and item_id = p_item), 0)
$$;

update app_settings set value = 'false' where key in ('security.freeze', 'security.require_mfa_all');
update profiles set locked_until = null where email in ('director.new@test.ly', 'headrest@test.ly', 'u.qc@test.ly', 'u.heritage@test.ly', 'u.safety@test.ly',
                                                         'u.safetyhead@test.ly', 'pending@test.ly', 'k.qa@test.ly', 'staff.new@test.ly', 'auditor@test.ly', 'qa@test.ly');
create temp table ids (k text primary key, v uuid);
grant all on ids to authenticated;
create temp table nums (k text primary key, v numeric);
grant all on nums to authenticated;
create or replace function pg_temp.num(p_k text) returns numeric language sql as $$ select v from nums where k = p_k $$;
create or replace function pg_temp.id(p_k text) returns uuid language sql as $$ select v from ids where k = p_k $$;
grant execute on all functions in schema pg_temp to authenticated, anon;
set role authenticated;

-- ---------------------------------------------------------------- الصلاحيات والأصناف
select pg_temp.as_user('director.new@test.ly', 'aal2');
select public.set_user_grants(pg_temp.uid('u.qc@test.ly'), array['stores:manager']);
select public.set_user_grants(pg_temp.uid('u.safety@test.ly'), array['stores:keeper:' || pg_temp.wh('main')]);
select public.set_user_grants(pg_temp.uid('qa@test.ly'), array['stores:keeper:' || pg_temp.wh('SUB1')]);
insert into ids select 'extra', public.st_save_item(null, jsonb_build_object('name', 'خرطوشة حبر للجرد', 'category_id', pg_temp.cat('OFE'),
  'base_unit_id', pg_temp.unit('قطعة')));
select pg_temp.check((select count(*) = 0 from st_stock where item_id = pg_temp.id('extra')), 'الصنف الجديد بلا رصيد');

-- ---------------------------------------------------------------- البدء
select pg_temp.as_user('pending@test.ly');
select pg_temp.expect_error(format($q$select public.st_count_start(jsonb_build_object('warehouse_id', %L))$q$, pg_temp.wh('main')), 'الموظف لا يبدأ جرداً');
select pg_temp.as_user('qa@test.ly');
select pg_temp.expect_error(format($q$select public.st_count_start(jsonb_build_object('warehouse_id', %L))$q$, pg_temp.wh('main')), 'أمين مخزن آخر لا يجرد مخزناً ليس مخزنه');
select pg_temp.as_user('u.safety@test.ly');
select pg_temp.expect_error($q$select public.st_count_start('{"warehouse_id": "00000000-0000-0000-0000-000000000009"}'::jsonb)$q$, 'مخزن غير موجود');
select pg_temp.expect_error($q$select public.st_count_start('{}'::jsonb)$q$, 'اختر المخزن');
insert into ids select 'c1', public.st_count_start(jsonb_build_object('warehouse_id', pg_temp.wh('main'), 'note', 'جرد نهاية العام'));
select pg_temp.check((select count_no ~ '^CN-[0-9]{4}-0001$' and status = 'open' and blind and created_by = pg_temp.uid('u.safety@test.ly')
                        from pg_temp.cnt(pg_temp.id('c1'))), 'جلسة بالرقم CN-سنة-0001 مفتوحة، والعدّ الأعمى مبدئياً');
select pg_temp.check((select count(*) > 0 from st_count_lines where count_id = pg_temp.id('c1'))
                     and (select count(*) = (select count(*) from st_stock s join st_items i on i.id = s.item_id
                                              where s.warehouse_id = pg_temp.wh('main') and s.on_hand > 0 and i.active)
                            from st_count_lines where count_id = pg_temp.id('c1')), 'بنود الجلسة هي الأصناف الفعالة ذات الرصيد في المخزن');
select pg_temp.check((select bool_and(counted_qty is null) from st_count_lines where count_id = pg_temp.id('c1')), 'لا معدود عند البدء');
select pg_temp.check((select bool_and(system_qty = pg_temp.onhand(pg_temp.wh('main'), item_id)) from st_count_lines where count_id = pg_temp.id('c1')),
  'الرصيد الدفتري يُلتقط عند البدء');
select pg_temp.expect_error(format($q$select public.st_count_start(jsonb_build_object('warehouse_id', %L))$q$, pg_temp.wh('main')), 'جلسة قائمة واحدة لكل مخزن');
select pg_temp.as_user('qa@test.ly');
select pg_temp.check((select count(*) = 0 from st_counts), 'أمين مخزن آخر لا يرى جلسات مخزن غيره');
select pg_temp.as_user('pending@test.ly');
select pg_temp.check((select count(*) = 0 from st_counts) and (select count(*) = 0 from st_count_lines), 'ولا الموظف');
select pg_temp.expect_error($q$insert into st_counts (count_no, warehouse_id) values ('X', (select id from st_warehouses limit 1))$q$, 'لا كتابة مباشرة على الجلسات');

-- ---------------------------------------------------------------- العدّ
select pg_temp.as_user('u.safety@test.ly');
select pg_temp.expect_error(format($q$select public.st_count_submit(%L)$q$, pg_temp.id('c1')), 'لا تقديم قبل عدّ كل البنود');
select pg_temp.expect_error(format($q$select public.st_count_save(%L, '[{"item_id": "00000000-0000-0000-0000-000000000009", "counted_qty": 1}]')$q$, pg_temp.id('c1')), 'صنف غير موجود');
select pg_temp.expect_error(format($q$select public.st_count_save(%L, jsonb_build_array(jsonb_build_object('item_id', %L, 'counted_qty', -1)))$q$,
  pg_temp.id('c1'), pg_temp.pick(pg_temp.id('c1'), 0)), 'الكمية المعدودة غير سالبة');
select pg_temp.expect_error(format($q$select public.st_count_save(%L, '[]')$q$, pg_temp.id('c1')), 'لا بنود للحفظ');
select public.st_count_save(pg_temp.id('c1'), pg_temp.all_as_system(pg_temp.id('c1')));
-- نقص بقطعة في بند، وزيادة بقطعتين في آخر، وصنف جديد وُجد بثلاث
insert into ids select 'loss', pg_temp.pick(pg_temp.id('c1'), 0);
insert into ids select 'gain', pg_temp.pick(pg_temp.id('c1'), 1);
select pg_temp.check(pg_temp.id('loss') is not null and pg_temp.id('gain') is not null and pg_temp.id('loss') <> pg_temp.id('gain'), 'بندان صالحان للنقص والزيادة');
insert into nums select 'loss_on', pg_temp.onhand(pg_temp.wh('main'), pg_temp.id('loss'));
insert into nums select 'gain_on', pg_temp.onhand(pg_temp.wh('main'), pg_temp.id('gain'));
select public.st_count_save(pg_temp.id('c1'), jsonb_build_array(
  jsonb_build_object('item_id', pg_temp.id('loss'), 'counted_qty', (select system_qty - 1 from st_count_lines where count_id = pg_temp.id('c1') and item_id = pg_temp.id('loss')), 'note', 'تالف'),
  jsonb_build_object('item_id', pg_temp.id('gain'), 'counted_qty', (select system_qty + 2 from st_count_lines where count_id = pg_temp.id('c1') and item_id = pg_temp.id('gain'))),
  jsonb_build_object('item_id', pg_temp.id('extra'), 'counted_qty', 3)));
select pg_temp.check((select system_qty = 0 and counted_qty = 3 from st_count_lines where count_id = pg_temp.id('c1') and item_id = pg_temp.id('extra')),
  'الصنف الذي لا رصيد له يُضاف بدفتري صفر ومعدود 3');
select pg_temp.check((select bool_and(counted_qty is not null) from st_count_lines where count_id = pg_temp.id('c1')), 'كل البنود معدودة');

-- ---------------------------------------------------------------- التقديم والقرار
select pg_temp.expect_error(format($q$select public.st_count_approve(%L)$q$, pg_temp.id('c1')), 'لا يُعتمد ما لم يُقدَّم');
select public.st_count_submit(pg_temp.id('c1'));
select pg_temp.check((select status = 'submitted' and submitted_by = pg_temp.uid('u.safety@test.ly') from pg_temp.cnt(pg_temp.id('c1'))), 'قُدّمت الجلسة');
select pg_temp.expect_error(format($q$select public.st_count_save(%L, '[{"item_id": "%s", "counted_qty": 5}]')$q$, pg_temp.id('c1'), pg_temp.id('loss')), 'لا عدّ بعد التقديم');
select pg_temp.expect_error(format($q$select public.st_count_approve(%L)$q$, pg_temp.id('c1')), 'الأمين لا يعتمد جرده');
select pg_temp.expect_error(format($q$select public.st_count_return(%L, 'إعادة')$q$, pg_temp.id('c1')), 'ولا يعيده');
select pg_temp.as_user('u.qc@test.ly');
select pg_temp.expect_error(format($q$select public.st_count_return(%L, 'x')$q$, pg_temp.id('c1')), 'سبب الإعادة 3 أحرف فأكثر');
select public.st_count_return(pg_temp.id('c1'), 'أعد عدّ بند الورق');
select pg_temp.check((select status = 'open' and decision_note = 'أعد عدّ بند الورق' and decided_by = pg_temp.uid('u.qc@test.ly') from pg_temp.cnt(pg_temp.id('c1'))), 'أُعيدت الجلسة للعدّ بسبب');
select pg_temp.as_user('u.safety@test.ly');
select public.st_count_submit(pg_temp.id('c1'));
select pg_temp.as_user('u.qc@test.ly');
insert into ids select 'd1', public.st_count_approve(pg_temp.id('c1'), 'اعتُمد');
select pg_temp.check((select status = 'closed' and adjust_doc_id = pg_temp.id('d1') and decided_by = pg_temp.uid('u.qc@test.ly') from pg_temp.cnt(pg_temp.id('c1'))), 'أُغلقت الجلسة ورُبطت بالتسوية');
select pg_temp.check((select kind = 'adjust' and status = 'approved' and warehouse_id = pg_temp.wh('main') and ref_no = (select count_no from pg_temp.cnt(pg_temp.id('c1')))
                        and approved_by = pg_temp.uid('u.qc@test.ly') from st_docs where id = pg_temp.id('d1')), 'التسوية AD معتمدة بالمخزن نفسه ومرجعها رقم الجلسة');
select pg_temp.check((select count(*) = 3 from st_doc_lines where doc_id = pg_temp.id('d1')), 'بالفروق وحدها: ثلاثة بنود لا غير');
select pg_temp.check((select qty = -1 from st_doc_lines where doc_id = pg_temp.id('d1') and item_id = pg_temp.id('loss'))
                     and (select qty = 2 from st_doc_lines where doc_id = pg_temp.id('d1') and item_id = pg_temp.id('gain'))
                     and (select qty = 3 from st_doc_lines where doc_id = pg_temp.id('d1') and item_id = pg_temp.id('extra')), 'الفروق: -1 و+2 و+3');
select pg_temp.check((select variance = -1 from st_count_lines where count_id = pg_temp.id('c1') and item_id = pg_temp.id('loss'))
                     and (select variance = 0 from st_count_lines cl where count_id = pg_temp.id('c1') and item_id not in (pg_temp.id('loss'), pg_temp.id('gain'), pg_temp.id('extra')) limit 1),
  'الفرق مسجَّل في بنود الجلسة (والمطابق صفر)');
select pg_temp.check(pg_temp.onhand(pg_temp.wh('main'), pg_temp.id('loss')) = pg_temp.num('loss_on') - 0 + 0 - 0 and pg_temp.reserved(pg_temp.wh('main'), pg_temp.id('loss')) >= 1,
  'قبل الترحيل: الرصيد كما هو والنقص محجوز');
select pg_temp.expect_error(format($q$select public.st_count_approve(%L)$q$, pg_temp.id('c1')), 'لا يُعتمد ما أُغلق');

-- ---------------------------------------------------------------- الترحيل بالإجراء المعتاد
select pg_temp.as_user('u.safety@test.ly');
select public.st_doc_action(pg_temp.id('d1'), 'post');
select pg_temp.check(pg_temp.onhand(pg_temp.wh('main'), pg_temp.id('loss')) = (select counted_qty from st_count_lines where count_id = pg_temp.id('c1') and item_id = pg_temp.id('loss'))
                     and pg_temp.onhand(pg_temp.wh('main'), pg_temp.id('gain')) = (select counted_qty from st_count_lines where count_id = pg_temp.id('c1') and item_id = pg_temp.id('gain'))
                     and pg_temp.onhand(pg_temp.wh('main'), pg_temp.id('extra')) = 3, 'بعد الترحيل: الرصيد يطابق المعدود في الأصناف الثلاثة');
select pg_temp.check(pg_temp.onhand(pg_temp.wh('main'), pg_temp.id('loss')) = pg_temp.num('loss_on') - 1
                     and pg_temp.onhand(pg_temp.wh('main'), pg_temp.id('gain')) = pg_temp.num('gain_on') + 2, 'النقص قطعة والزيادة قطعتان فعلاً');
select pg_temp.check(pg_temp.reserved(pg_temp.wh('main'), pg_temp.id('loss')) = 0 or pg_temp.reserved(pg_temp.wh('main'), pg_temp.id('loss')) < 1, 'انحلّ الحجز بالترحيل');
select pg_temp.check((select count(*) = 3 from st_moves where doc_id = pg_temp.id('d1')), 'ثلاث حركات في بطاقات الأصناف');

-- ---------------------------------------------------------------- جرد مطابق وفصل المهام
select pg_temp.as_user('u.qc@test.ly');
insert into ids select 'c2', public.st_count_start(jsonb_build_object('warehouse_id', pg_temp.wh('main'), 'blind', false));
select pg_temp.check((select not blind and count_no ~ '-0002$' from pg_temp.cnt(pg_temp.id('c2'))), 'الجلسة الثانية بالتسلسل 0002 وبدفتري ظاهر');
select public.st_count_save(pg_temp.id('c2'), pg_temp.all_as_system(pg_temp.id('c2')));
select public.st_count_submit(pg_temp.id('c2'));
select pg_temp.expect_error(format($q$select public.st_count_approve(%L)$q$, pg_temp.id('c2')), 'فصل المهام: لا يعتمد الجرد من أنشأه وقدّمه');
select pg_temp.as_user('director.new@test.ly', 'aal2');
select public.st_count_approve(pg_temp.id('c2'));
select pg_temp.check((select status = 'closed' and adjust_doc_id is null from pg_temp.cnt(pg_temp.id('c2'))), 'جرد مطابق: يُغلق بلا مستند تسوية');
select pg_temp.check((select count(*) = 1 from st_docs where kind = 'adjust' and ref_no like 'CN-%'), 'لم تُولَّد تسوية للجرد المطابق');

-- ---------------------------------------------------------------- التقييد بتصنيف، والإلغاء
select pg_temp.as_user('u.safety@test.ly');
insert into ids select 'c3', public.st_count_start(jsonb_build_object('warehouse_id', pg_temp.wh('main'),
  'category_id', (select category_id from st_items where id = pg_temp.id('loss'))));
select pg_temp.check((select bool_and(i.category_id = (select category_id from st_items where id = pg_temp.id('loss')))
                        from st_count_lines cl join st_items i on i.id = cl.item_id where cl.count_id = pg_temp.id('c3')), 'جلسة لتصنيف: بنودها منه وحده');
select pg_temp.expect_error(format($q$select public.st_count_save(%L, jsonb_build_array(jsonb_build_object('item_id', %L, 'counted_qty', 1)))$q$,
  pg_temp.id('c3'), (select id from st_items where category_id <> (select category_id from st_items where id = pg_temp.id('loss')) limit 1)), 'صنف من خارج التصنيف لا يُضاف');
select public.st_count_cancel(pg_temp.id('c3'));
select pg_temp.check((select status = 'cancelled' from pg_temp.cnt(pg_temp.id('c3'))), 'أُلغيت الجلسة المفتوحة');
select pg_temp.expect_error(format($q$select public.st_count_cancel(%L)$q$, pg_temp.id('c3')), 'لا تُلغى المنتهية');
insert into ids select 'c4', public.st_count_start(jsonb_build_object('warehouse_id', pg_temp.wh('main')));
select public.st_count_save(pg_temp.id('c4'), pg_temp.all_as_system(pg_temp.id('c4')));
select public.st_count_submit(pg_temp.id('c4'));
select pg_temp.expect_error(format($q$select public.st_count_cancel(%L)$q$, pg_temp.id('c4')), 'إلغاء المقدَّمة بسبب مكتوب');
select public.st_count_cancel(pg_temp.id('c4'), 'بدأت بالخطأ');
select pg_temp.check((select status = 'cancelled' and decision_note = 'بدأت بالخطأ' from pg_temp.cnt(pg_temp.id('c4'))), 'أُلغيت الجلسة المقدَّمة بسببها');
select pg_temp.as_user('director.new@test.ly', 'aal2');
insert into ids select 'empty', public.st_save_warehouse(null, jsonb_build_object('code', 'EMP1', 'name', 'مخزن فارغ للجرد', 'kind', 'sub', 'parent_id', pg_temp.wh('main')));
select pg_temp.expect_error(format($q$select public.st_count_start(jsonb_build_object('warehouse_id', %L))$q$, pg_temp.id('empty')), 'مخزن بلا أرصدة لا يُجرد');

-- ---------------------------------------------------------------- التدقيق
reset role;
select pg_temp.check((select count(distinct action) = 6 from audit_log where action in
  ('stores.count_start', 'stores.count_save', 'stores.count_submit', 'stores.count_return', 'stores.count_approve', 'stores.count_cancel')),
  'كل إجراءات الجرد الستة في سجل التدقيق');
select pg_temp.check((select detail ->> 'doc' = pg_temp.id('d1')::text and (detail ->> 'gains')::int = 2 and (detail ->> 'losses')::int = 1
                        from audit_log where action = 'stores.count_approve' and detail ->> 'id' = pg_temp.id('c1')::text), 'تدقيق الاعتماد يذكر التسوية وعدد الزيادات والنقص');
