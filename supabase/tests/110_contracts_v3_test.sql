-- اختبارات الترحيل 37: ضمانات العقد بنسب ثابتة لكل عقد وتصحيحها بنسخة احتياطية، و«لا ينطبق» للنهائي، وخصم التأمينات،
-- وأوامر التغيير (مسودة ← اعتماد أو رفض، والبنود، والسجل، ولا يدخل في القيمة إلا المعتمد)، ولجنة الاستلام برئيسها وأعضائها.
-- يُشغَّل بعد تطبيق 20261128000037_contracts_v3.sql مرتين، وبعد اختبارات الترحيل 36.
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
create or replace function pg_temp.fin(p_id uuid) returns setof public.projects language sql security definer as $$
  select * from public.projects where id = p_id
$$;
create or replace function pg_temp.vo(p_id uuid) returns setof public.contract_variations language sql security definer as $$
  select * from public.contract_variations where id = p_id
$$;
create or replace function pg_temp.events(p_id uuid) returns text language sql security definer as $$
  select string_agg(action, ',' order by at, id) from public.contract_variation_events where variation_id = p_id
$$;
create or replace function pg_temp.backup_count() returns bigint language sql security definer as $$
  select count(*) from backup.m37_projects_guarantees
$$;

update app_settings set value = 'false' where key in ('security.freeze', 'security.require_mfa_all');
update profiles set locked_until = null where email like 'k.%@test.ly' or email like 'u.%@test.ly' or email like 'head%@test.ly'
                                        or email in ('director.new@test.ly', 'staff.new@test.ly');
create temp table ids (k text primary key, v uuid);
grant all on ids to authenticated;
create or replace function pg_temp.id(p_k text) returns uuid language sql as $$ select v from ids where k = p_k $$;
grant execute on all functions in schema pg_temp to authenticated, anon;

delete from projects where assign_no in ('T37-P', 'T37-Q', 'T37-R', 'T37-S');

-- ---------------------------------------------------------------- تصحيح الضمانات في العقود القائمة
select pg_temp.check((select count(*) = 0 from projects where guarantee_initial_rate is distinct from 0.02 or guarantee_final_rate is distinct from 0.05),
                     'كل العقود القائمة: الابتدائي 2% والنهائي 5%');
select pg_temp.check(pg_temp.backup_count() = (select count(*) from projects), 'القيم السابقة لكل عقد في النسخة الاحتياطية');
select pg_temp.check((select bool_and(p.guarantee_final = round(p.executed_value * 0.05, 3)
                                      and (p.guarantee_initial_na or p.guarantee_initial = round(p.executed_value * 0.02, 3))
                                      and b.guarantee_final = round(b.executed_value * 0.02, 3))
                        from projects p join backup.m37_projects_guarantees b on b.project_id = p.id where p.executed_value is not null),
                     'المبلغان يُعاد حسابهما بالنسبتين الجديدتين على الأساس نفسه، والنسخة بالقديمتين');
-- كل تطبيق للترحيل يصحّح مرة واحدة (والتراجع يعيد القيم، فالتطبيق بعده يصحّح مرة أخرى)
select pg_temp.check((select bool_and(n = 1 + (select count(*) from pg_temp.alog() where action = 'setting.update'
                                                 and detail ->> 'source' = 'rollback_37' and detail ->> 'key' = 'finance.guarantee_initial_rate'))
                             and count(*) = (select count(*) from projects)
                        from (select project_id, count(*) n from pg_temp.alog()
                               where action = 'finance.guarantees' and detail ->> 'source' = 'migration_37' group by project_id) x),
                     'سطر في سجل التدقيق لكل عقد لكل تصحيح (لا يتكرر بإعادة الترحيل)');
select pg_temp.check((select (select value from app_settings where key = 'finance.guarantee_initial_rate') = '0.02'::jsonb
                         and (select value from app_settings where key = 'finance.guarantee_final_rate') = '0.05'::jsonb),
                     'النسبتان الافتراضيتان للعقود الجديدة 2% و5%');

-- ---------------------------------------------------------------- النسبة ثابتة لكل عقد
set role authenticated;
select pg_temp.as_user('k.staff@test.ly');
insert into ids select 'p', public.save_project(null, '{"assign_no": "T37-P", "name": "عقد الضمانات وأوامر التغيير", "company": "شركة أ", "department": "supervision"}');
insert into ids select 'q', public.save_project(null, '{"assign_no": "T37-Q", "name": "عقد آخر", "company": "شركة ب", "department": "restoration"}');
select pg_temp.as_user('director.new@test.ly', 'aal2');
select public.set_setting('finance.guarantee_final_rate', '0.1');
select pg_temp.check((select guarantee_final_rate = 0.05 from pg_temp.fin(pg_temp.id('p'))), 'تعديل الإعداد لا يغيّر نسبة عقد قائم');
select pg_temp.as_user('k.staff@test.ly');
insert into ids select 'r', public.save_project(null, '{"assign_no": "T37-R", "name": "عقد بعد تعديل الإعداد", "company": "شركة ج", "department": "supervision"}');
select pg_temp.check((select guarantee_final_rate = 0.1 and guarantee_initial_rate = 0.02 from pg_temp.fin(pg_temp.id('r'))),
                     'والعقد الجديد يأخذ النسبة السارية عند إنشائه');
select pg_temp.as_user('director.new@test.ly', 'aal2');
select public.set_setting('finance.guarantee_final_rate', '0.05');

select pg_temp.as_user('k.contracts@test.ly');
select public.set_contract_finance(pg_temp.id('p'), 1000000, 400000, null, null, null, null);
select pg_temp.check((select guarantee_initial = 8000 and guarantee_final = 20000 from pg_temp.fin(pg_temp.id('p'))),
                     'الابتدائي 2% والنهائي 5% من قيمة الأعمال المنفذة');
select public.set_contract_guarantees(pg_temp.id('p'), '{"final_na": true, "initial_rate": 0.03}');
select pg_temp.check((select guarantee_final is null and guarantee_final_na and guarantee_initial = 12000 from pg_temp.fin(pg_temp.id('p'))),
                     '«لا ينطبق» للضمان النهائي، ونسبة خاصة للابتدائي');
select pg_temp.check((select detail -> 'final_na' ->> 'to' = 'true' and (detail -> 'initial_rate' ->> 'to')::numeric = 0.03
                             and (detail -> 'final' ->> 'from')::numeric = 20000 and detail -> 'final' ->> 'to' is null
                        from pg_temp.alog() where action = 'finance.guarantees' and project_id = pg_temp.id('p') order by id desc limit 1),
                     'والتعديل في سجل التدقيق بقيمه قبل وبعد');
select public.set_contract_guarantees(pg_temp.id('p'), '{"final_na": true}');
select pg_temp.check((select count(*) = 1 from pg_temp.alog() where action = 'finance.guarantees' and project_id = pg_temp.id('p')),
                     'حفظ بلا تغيير لا يُسجَّل');
select pg_temp.expect_error($$select public.set_contract_guarantees(pg_temp.id('p'), '{"initial_rate": 0.7}')$$, 'نسبة فوق 50%');
select pg_temp.expect_error($$select public.set_contract_guarantees(pg_temp.id('p'), '{"initial_rate": "abc"}')$$, 'نسبة غير رقمية');
select pg_temp.as_user('k.headsup@test.ly');
select pg_temp.expect_error($$select public.set_contract_guarantees(pg_temp.id('p'), '{"final_na": false}')$$, 'رئيس الإشراف لا يحدّد الضمانات');
reset role;
select pg_temp.as_user('');
update projects set guarantee_final_rate = 0.4, retention_deduct = false where id = pg_temp.id('p');
select pg_temp.check((select guarantee_final_rate = 0.05 and retention_deduct from pg_temp.fin(pg_temp.id('p'))),
                     'الأعمدة الجديدة لا تُكتب مباشرة (من دالة الضمانات وحدها)');
set role authenticated;

-- ---------------------------------------------------------------- خصم التأمينات
select pg_temp.as_user('k.contracts@test.ly');
insert into ids select 'x1', public.save_extract(null, pg_temp.id('p'), null, 'م-1', 'interim', null, null, '2026-11-01', 100000, 5000, 0, 0, 0, 0,
                                                 'approved', '2026-11-05', 0, null, '', null, '', '{}');
select public.set_contract_guarantees(pg_temp.id('p'), '{"retention_deduct": false}');
select pg_temp.expect_error($$select public.save_extract(null, pg_temp.id('p'), null, 'م-2', 'interim', null, null, null, 50000, 2500, 0, 0, 0, 0,
                                                          'submitted', null, 0, null, '', null, '', '{}')$$,
                            'تأمين محتجز في مستخلص جديد والخصم معطّل');
insert into ids select 'x2', public.save_extract(null, pg_temp.id('p'), null, 'م-2', 'interim', null, null, null, 50000, 0, 0, 0, 0, 0,
                                                 'submitted', null, 0, null, '', null, '', '{}');
select pg_temp.check(public.save_extract(pg_temp.id('x1'), null, null, 'م-1', 'interim', null, null, '2026-11-01', 100000, 5000, 0, 0, 0, 0,
                           'approved', '2026-11-05', 0, null, 'مراجعة', null, '', '{}') = pg_temp.id('x1'), 'تعديل مستخلص بتأمينه السابق والخصم معطّل');
select pg_temp.check((select retention_held = 5000 from pg_temp.fin(pg_temp.id('p'))), 'المستخلص السابق يبقى بتأمينه ويُعدَّل');
select pg_temp.expect_error($$select public.save_extract(pg_temp.id('x1'), null, null, 'م-1', 'interim', null, null, '2026-11-01', 100000, 6000, 0, 0, 0, 0,
                                                          'approved', '2026-11-05', 0, null, '', null, '', '{}')$$,
                            'رفع التأمين في مستخلص قائم والخصم معطّل');
select pg_temp.check((select extracts_submitted = 150000 and extracts_gross = 100000 from pg_temp.fin(pg_temp.id('p'))),
                     'المستخلصات المقدمة (150,000) غير المعتمدة (100,000)');
select public.set_contract_guarantees(pg_temp.id('p'), '{"retention_deduct": true, "retention_rate": 0.05}');
select pg_temp.check((select retention_deduct and retention_rate = 0.05 from pg_temp.fin(pg_temp.id('p'))), 'وإعادة تفعيله بنسبة العقد');

-- ---------------------------------------------------------------- أوامر التغيير: مسودة ثم اعتماد
select pg_temp.as_user('k.headtech@test.ly');
insert into ids select 'b', public.save_boq(null, jsonb_build_object(
  'title', 'مقايسة العقد', 'project_id', pg_temp.id('p'),
  'lines', jsonb_build_array(
    jsonb_build_object('code', '1.1', 'desc', 'حفر خنادق', 'unit', 'م3', 'price', 35, 'qty', 240),
    jsonb_build_object('code', '2.1', 'desc', 'خرسانة مسلحة', 'unit', 'م3', 'price', 950, 'qty', 60))));
insert into ids select 'bq', public.save_boq(null, jsonb_build_object('title', 'مقايسة عقد آخر', 'project_id', pg_temp.id('q'),
  'lines', jsonb_build_array(jsonb_build_object('code', '1', 'desc', 'بند', 'unit', 'م2', 'price', 10, 'qty', 1))));
select pg_temp.as_user('k.contracts@test.ly');
insert into ids select 'v1', public.save_contract_variation(null, jsonb_build_object(
  'project_id', pg_temp.id('p'), 'title', 'زيادة كميات الحفر وإلغاء جزء من الخرسانة', 'ref_no', 'أ.ت-1',
  'items', jsonb_build_array(
    jsonb_build_object('direction', 'add', 'boq_sheet_id', pg_temp.id('b'), 'boq_line', 0, 'code', '1.1', 'description', 'حفر خنادق إضافي',
                       'unit', 'م3', 'qty', 100, 'unit_price', 35),
    jsonb_build_object('direction', 'add', 'description', 'بند جديد: عزل مائي', 'unit', 'م2', 'qty', 200, 'unit_price', 40),
    jsonb_build_object('direction', 'deduct', 'boq_sheet_id', pg_temp.id('b'), 'boq_line', 1, 'code', '2.1', 'description', 'إلغاء خرسانة',
                       'unit', 'م3', 'qty', 5, 'unit_price', 950))));
select pg_temp.check((select status = 'draft' and added_value = 3500 + 8000 and deducted_value = 4750 and kind = 'add' and amount = 6750
                        from pg_temp.vo(pg_temp.id('v1'))),
                     'أمر بزيادة 11,500 ونقص 4,750: مسودة صافيها 6,750');
select pg_temp.check((select count(*) = 3 from contract_variation_items where variation_id = pg_temp.id('v1')), 'وبنوده الثلاثة');
select pg_temp.check((select variations_net = 0 and variations_add = 0 from pg_temp.fin(pg_temp.id('p'))), 'المسودة لا تدخل في قيمة العقد');
select pg_temp.expect_error($$select public.save_contract_variation(null, jsonb_build_object('project_id', pg_temp.id('p'), 'title', 'بند من مقايسة عقد آخر',
  'items', jsonb_build_array(jsonb_build_object('direction', 'add', 'boq_sheet_id', pg_temp.id('bq'), 'boq_line', 0, 'description', 'بند', 'amount', 10))))$$,
  'بند من مقايسة عقد آخر');
select pg_temp.expect_error($$select public.save_contract_variation(null, jsonb_build_object('project_id', pg_temp.id('p'), 'title', 'سطر غير موجود',
  'items', jsonb_build_array(jsonb_build_object('direction', 'add', 'boq_sheet_id', pg_temp.id('b'), 'boq_line', 9, 'description', 'بند', 'amount', 10))))$$,
  'سطر خارج المقايسة');
select pg_temp.expect_error($$select public.save_contract_variation(null, jsonb_build_object('project_id', pg_temp.id('p'), 'title', 'بلا قيمة',
  'items', jsonb_build_array(jsonb_build_object('direction', 'add', 'description', 'بند بلا قيمة'))))$$, 'بند بلا قيمة');
select pg_temp.expect_error($$select public.save_contract_variation(null, jsonb_build_object('project_id', pg_temp.id('p'), 'title', 'أمر بلا قيمة'))$$,
  'أمر بلا بنود ولا قيمة');
select pg_temp.expect_error($$select public.save_variation(null, pg_temp.id('p'), null, '', 'الصيغة القديمة', 'add', 100, current_date, '')$$,
  'الصيغة القديمة (كانت تعتمد مباشرة) لم تعد متاحة');

-- تعديل المسودة، ثم البت
select pg_temp.check(public.save_contract_variation(pg_temp.id('v1'), jsonb_build_object(
  'title', 'زيادة كميات الحفر وإلغاء جزء من الخرسانة', 'ref_no', 'أ.ت-1', 'notes', 'بعد مراجعة الإشراف',
  'items', jsonb_build_array(
    jsonb_build_object('direction', 'add', 'boq_sheet_id', pg_temp.id('b'), 'boq_line', 0, 'code', '1.1', 'description', 'حفر خنادق إضافي',
                       'unit', 'م3', 'qty', 120, 'unit_price', 35),
    jsonb_build_object('direction', 'deduct', 'boq_sheet_id', pg_temp.id('b'), 'boq_line', 1, 'code', '2.1', 'description', 'إلغاء خرسانة',
                       'unit', 'م3', 'qty', 5, 'unit_price', 950)))) = pg_temp.id('v1'), 'تعديل المسودة');
select pg_temp.check((select added_value = 4200 and deducted_value = 4750 and kind = 'deduct' and amount = 550 from pg_temp.vo(pg_temp.id('v1'))),
                     'تعديل المسودة: نقص صافيه 550');
select pg_temp.expect_error($$select public.decide_variation(pg_temp.id('v1'), 'approve')$$, 'مكتب العقود لا يعتمد أوامر التغيير');
select pg_temp.as_user('k.staff@test.ly');
select pg_temp.expect_error($$select public.decide_variation(pg_temp.id('v1'), 'reject', '')$$, 'رفض بلا سبب');
select public.decide_variation(pg_temp.id('v1'), 'approve', 'معتمد', '2026-11-20');
select pg_temp.check((select status = 'approved' and approved_on = '2026-11-20' and decided_by = pg_temp.uid('k.staff@test.ly')
                        from pg_temp.vo(pg_temp.id('v1'))),
                     'موظف مكتب المدير يعتمده بتاريخ');
select pg_temp.check((select variations_add = 4200 and variations_deduct = 4750 and variations_net = -550 from pg_temp.fin(pg_temp.id('p'))),
                     'الاعتماد يحدّث القيمة المعدلة: زيادة 4,200 ونقص 4,750 منفصلان');
select pg_temp.as_user('k.contracts@test.ly');
select pg_temp.expect_error($$select public.save_contract_variation(pg_temp.id('v1'), '{"title": "تعديل بعد الاعتماد", "kind": "add", "amount": 1}')$$,
  'المعتمد لا يُعدَّل');
select pg_temp.expect_error($$select public.delete_variation(pg_temp.id('v1'))$$, 'المعتمد لا يحذفه غير المدير');
select pg_temp.as_user('k.staff@test.ly');
select pg_temp.expect_error($$select public.decide_variation(pg_temp.id('v1'), 'reopen', 'لمراجعته')$$, 'الإعادة إلى مسودة للمدير وحده');
select pg_temp.as_user('director.new@test.ly', 'aal2');
select pg_temp.expect_error($$select public.decide_variation(pg_temp.id('v1'), 'reopen', '')$$, 'إعادة بلا سبب');
select public.decide_variation(pg_temp.id('v1'), 'reopen', 'خطأ في كمية الخرسانة');
select pg_temp.check((select status = 'draft' and approved_on is null from pg_temp.vo(pg_temp.id('v1')))
                     and (select variations_net = 0 from pg_temp.fin(pg_temp.id('p'))),
                     'المدير يعيده مسودة فيخرج من قيمة العقد');
select public.decide_variation(pg_temp.id('v1'), 'approve');
select pg_temp.check(pg_temp.events(pg_temp.id('v1')) = 'create,update,approve,reopen,approve', 'سجل الأمر: إنشاء، تعديل، اعتماد، إعادة، اعتماد');
select pg_temp.check((select (snapshot -> 'items' -> 0 ->> 'qty')::numeric = 120 from contract_variation_events
                       where variation_id = pg_temp.id('v1') and action = 'update'),
                     'وكل حدث يحفظ صورة الأمر ببنوده');
select pg_temp.check((select string_agg(action, ',' order by id) = 'finance.variation_add,finance.variation_update,finance.variation_approve,finance.variation_reopen,finance.variation_approve'
                        from pg_temp.alog() where (detail ->> 'variation_id')::uuid = pg_temp.id('v1')),
                     'وفي سجل التدقيق');

-- أمر بلا بنود، ورفضه
select pg_temp.as_user('k.contracts@test.ly');
insert into ids select 'v2', public.save_contract_variation(null, jsonb_build_object('project_id', pg_temp.id('p'), 'title', 'أعمال إضافية للسياج',
  'kind', 'add', 'amount', 20000));
select pg_temp.as_user('k.staff@test.ly');
select public.decide_variation(pg_temp.id('v2'), 'reject', 'لا يوجد تكليف بها');
select pg_temp.check((select status = 'rejected' and decision_note = 'لا يوجد تكليف بها' and approved_on is null from pg_temp.vo(pg_temp.id('v2')))
                     and (select variations_add = 4200 from pg_temp.fin(pg_temp.id('p'))),
                     'المرفوض لا يدخل في القيمة');
select pg_temp.as_user('k.contracts@test.ly');
select public.delete_variation(pg_temp.id('v2'));
select pg_temp.check(not exists (select 1 from contract_variations where id = pg_temp.id('v2')), 'والمرفوض يُحذف');

-- أمر من سجل التغييرات: معتمد بقرار البت هناك، ولا يُبت فيه من المالية
reset role;
select pg_temp.as_user('');
insert into pm_changes (code, project_id, description, cost_approved, status, decided_on)
values ('C937', pg_temp.id('p'), 'تغيير من الموقع', 3000, 'approved', current_date);
select public.pm_sync_change_variation((select id from pm_changes where code = 'C937'));
set role authenticated;
select pg_temp.as_user('k.contracts@test.ly');
select pg_temp.check((select status = 'approved' and added_value = 3000 from contract_variations
                       where id = (select variation_id from pm_changes where code = 'C937')),
                     'أمر سجل التغييرات يُنشأ معتمداً');
select pg_temp.check((select variations_add = 7200 and variations_net = 7200 - 4750 from pg_temp.fin(pg_temp.id('p'))), 'ويدخل في القيمة');
select pg_temp.as_user('director.new@test.ly', 'aal2');
select pg_temp.expect_error($$select public.decide_variation((select variation_id from pm_changes where code = 'C937'), 'reopen', 'إعادة')$$,
  'أمر سجل التغييرات يُبت فيه من هناك');

-- ---------------------------------------------------------------- لجنة الاستلام الابتدائي
select pg_temp.as_user('k.contracts@test.ly');
select pg_temp.expect_error($$select public.save_committee(pg_temp.id('p'), 'initial', '{"chair": {"name": "م. سالم"}, "members": [{"name": "م. علي"}]}')$$,
  'مكتب العقود لا يشكّل اللجنة (نموذج التكليف لمكتب المدير)');
select pg_temp.as_user('k.staff@test.ly');
select pg_temp.expect_error($$select public.save_committee(pg_temp.id('p'), 'initial', '{"members": [{"name": "م. علي"}]}')$$, 'لجنة بلا رئيس');
select pg_temp.expect_error($$select public.save_committee(pg_temp.id('p'), 'initial', '{"chair": {"name": "م. سالم"}, "members": []}')$$, 'رئيس بلا أعضاء');
select pg_temp.expect_error($$select public.save_committee(pg_temp.id('p'), 'initial', '{"chair": {"name": "م. سالم"},
  "members": [{"name": "م. أحمد علي"}, {"name": "م.  احمد علي"}]}')$$, 'العضو نفسه مرتين (بالهمزة والمسافة)');
select pg_temp.expect_error($$select public.save_committee(pg_temp.id('p'), 'initial', '{"chair": {"name": "م. سالم"},
  "members": [{"name": "م. سالم", "title": "عضو"}]}')$$, 'الرئيس عضواً أيضاً');
select pg_temp.expect_error(format($$select public.save_committee(%L, 'initial', %L)$$, pg_temp.id('p'),
  jsonb_build_object('chair', jsonb_build_object('name', 'م. سالم', 'profile_id', pg_temp.uid('k.headacc@test.ly')),
                     'members', jsonb_build_array(jsonb_build_object('name', 'رئيس قسم المطابقة', 'profile_id', pg_temp.uid('k.headacc@test.ly'))))),
  'الموظف نفسه رئيساً وعضواً');
insert into ids select 'c1', public.save_committee(pg_temp.id('p'), 'initial', jsonb_build_object(
  'decision_no', 'ق-77/2026', 'decision_date', '2026-11-22',
  'chair', jsonb_build_object('name', 'م. سالم الفرجاني', 'title', 'رئيس قسم المطابقة والاستلام',
                              'profile_id', pg_temp.uid('k.headacc@test.ly')),
  'members', jsonb_build_array(jsonb_build_object('name', 'م. علي المسماري', 'title', 'مهندس مدني'),
                               jsonb_build_object('name', 'م. هدى العبيدي', 'title', 'ممثل الإشراف'))));
select pg_temp.check((select count(*) = 3 and count(*) filter (where role = 'chair') = 1 from contract_committee_members where committee_id = pg_temp.id('c1')),
                     'لجنة برئيس واحد وعضوين');
select pg_temp.check(public.save_committee(pg_temp.id('p'), 'initial', jsonb_build_object('decision_no', 'ق-77/2026',
  'chair', jsonb_build_object('name', 'م. علي المسماري', 'title', 'مهندس مدني'),
  'members', jsonb_build_array(jsonb_build_object('name', 'م. سالم الفرجاني', 'title', 'عضو')))) = pg_temp.id('c1'), 'إعادة تشكيل اللجنة');
select pg_temp.check((select string_agg(role || ':' || name, ',' order by sort) = 'chair:م. علي المسماري,member:م. سالم الفرجاني'
                        from contract_committee_members where committee_id = pg_temp.id('c1')),
                     'تغيير الرئيس يحل محله (لجنة واحدة من كل نوع للعقد)');
select pg_temp.check((select count(*) = 1 from contract_committees where project_id = pg_temp.id('p') and kind = 'initial'), 'ولا تُنشأ لجنة ثانية');
select pg_temp.check((select detail -> 'from' -> 'chair' ->> 'name' = 'م. سالم الفرجاني' and detail -> 'to' -> 'chair' ->> 'name' = 'م. علي المسماري'
                        from pg_temp.alog() where action = 'committee.save' and project_id = pg_temp.id('p') order by id desc limit 1),
                     'والتغيير في سجل التدقيق بالتشكيلين');
reset role;
select pg_temp.as_user('');
select pg_temp.expect_error($$insert into contract_committee_members (committee_id, role, name) values (pg_temp.id('c1'), 'chair', 'رئيس ثانٍ')$$,
  'رئيسان للجنة الواحدة (قيد في قاعدة البيانات)');
set role authenticated;

-- من يطّلع على اللجنة
select pg_temp.as_user('k.headacc@test.ly');
select pg_temp.check((select count(*) = 2 from contract_committee_members m join contract_committees c on c.id = m.committee_id
                       where c.project_id = pg_temp.id('p')),
                     'قسم المطابقة والاستلام يرى اللجنة');
select pg_temp.as_user('k.headtech@test.ly');
select pg_temp.check((select count(*) = 0 from contract_committees where project_id = pg_temp.id('p')), 'والشؤون الفنية لا تراها');
select pg_temp.check((select count(*) = 0 from contract_variation_items v join contract_variations x on x.id = v.variation_id
                       where x.project_id = pg_temp.id('p')),
                     'ولا ترى بنود أوامر التغيير (تتبع عزل المالية)');
select pg_temp.as_user('k.headsup@test.ly');
select pg_temp.check((select count(*) = 2 from contract_variation_items v join contract_variations x on x.id = v.variation_id
                       where x.project_id = pg_temp.id('p'))
                     and (select count(*) = 1 from contract_committees where project_id = pg_temp.id('p')),
                     'والقسم المشرف يرى بنود أوامر عقده ولجنته');

-- ---------------------------------------------------------------- الدمج: اللجنة تتبع العقد
select pg_temp.as_user('k.staff@test.ly');
insert into ids select 's', public.save_project(null, '{"assign_no": "T37-S", "name": "عقد يُدمج", "company": "شركة د", "department": "supervision"}');
select pg_temp.check(public.save_committee(pg_temp.id('s'), 'initial', '{"chair": {"name": "م. فاطمة"}, "members": [{"name": "م. خالد"}]}') is not null, 'لجنة العقد الذي سيُدمج');
select pg_temp.as_user('k.contracts@test.ly');
select pg_temp.check(public.merge_contracts(pg_temp.id('p'), array[pg_temp.id('s')]) = 1, 'دمج العقد');
select pg_temp.check((select count(*) = 2 and count(*) filter (where origin_project = pg_temp.id('s')) = 1
                        from contract_committees where project_id = pg_temp.id('p')),
                     'الدمج ينقل لجنة العقد المدموج بأصلها ويبقي لجنة العقد');
select pg_temp.as_user('director.new@test.ly', 'aal2');
select public.unmerge_contract(pg_temp.id('s'));
select pg_temp.check((select count(*) = 1 and bool_and(origin_project is null) from contract_committees where project_id = pg_temp.id('s'))
                     and (select count(*) = 1 from contract_committees where project_id = pg_temp.id('p')),
                     'وفك الدمج يعيدها');

select pg_temp.as_user('k.staff@test.ly');
select public.delete_committee(pg_temp.id('s'), 'initial');
select pg_temp.check(not exists (select 1 from contract_committees where project_id = pg_temp.id('s'))
                     and exists (select 1 from pg_temp.alog() where action = 'committee.delete' and project_id = pg_temp.id('s')),
                     'حذف اللجنة مسجّل');
reset role;
