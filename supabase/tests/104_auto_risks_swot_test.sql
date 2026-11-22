-- اختبارات الترحيل 31: ترجمة تنفيذ البرنامج الزمني المعتمد إلى سجل المخاطر وتحليل SWOT.
-- يُشغَّل بعد تطبيق 20261122000031_auto_risks_swot.sql مرتين، وبعد اختبارات الترحيل 30 (العقد T-30 وبرنامجه المعتمد).
-- البرنامج: يبدأ 2026/01/01 وينتهي 2026/05/05، وأوزان بنوده 6,500 و9,250 و75,230 و28,750 و5,000 (والبند الإضافي «لا ينطبق»).
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
create or replace function pg_temp.p() returns uuid language sql security definer as $$
  select id from public.projects where assign_no = 'T-30' and merged_into is null
$$;
create or replace function pg_temp.item(p_seq integer) returns uuid language sql security definer as $$
  select id from public.pm_items where project_id = pg_temp.p() and price_seq = p_seq
$$;
create or replace function pg_temp.risk(p_seq integer) returns public.risks language sql security definer as $$
  select * from public.risks where auto_key = 'pm_item:' || pg_temp.item(p_seq)
$$;
create or replace function pg_temp.prisk() returns public.risks language sql security definer as $$
  select * from public.risks where auto_key = 'pm_plan:' || pg_temp.p()
$$;
create or replace function pg_temp.kinds() returns text language sql security definer as $$
  select coalesce(string_agg(kind, '' order by kind), '') from public.swot_factors where project_id = pg_temp.p() and auto_key is not null
$$;
create or replace function pg_temp.sync() returns jsonb language sql security definer as $$
  select public.pm_sync_auto(pg_temp.p())
$$;
create or replace function pg_temp.ref(p_date text, p_alert integer default 7) returns void language sql security definer as $$
  update public.app_settings set value = value || jsonb_build_object('ref_date', p_date, 'alert_days', p_alert) where key = 'pm.config'
$$;
grant execute on all functions in schema pg_temp to authenticated, anon;

update app_settings set value = 'false' where key in ('security.freeze', 'security.require_mfa_all');
update profiles set locked_until = null where email like 'k.%@test.ly';

-- ---------------------------------------------------------------- الترحيل يترجم البرامج المعتمدة القائمة
select pg_temp.check((select count(*) >= 4 from risks where project_id = pg_temp.p() and auto_key like 'pm_item:%' and status = 'open'),
                     'الترحيل سجّل مخاطر البنود المتجاوزة لنهاياتها');
select pg_temp.check((select code ~ '^R[0-9]{2,4}$' and category = 'زمني' and phase = 'التنفيذ' and department = 'الإشراف والتنسيق' and auto_active
                        from pg_temp.risk(201)), 'برمز سجل المخاطر وتصنيف «زمني» ومرحلة «التنفيذ» وقسم العقد');

-- ---------------------------------------------------------------- تاريخ إسناد 2026/02/19
-- الخرسانية: D = 60، E = 31، المخطط 51.67%، الفعلي 55% ← SPI 1.06 متقدم؛ والبند 1.2.1.1 انتهى 2026/01/21 عند 0% ← متجاوز 29 يوماً
select pg_temp.ref('2026-02-19');
select pg_temp.sync();
select pg_temp.check((select status = 'open' and probability = 5 and impact = 3 and time_impact_days = 29 and auto_active
                             and effect like '%تجاوز نهايته المخططة 2026/01/21 بـ29 يوماً%' and effect like '%7.4%%%'
                        from pg_temp.risk(19)),
                     'البند المتجاوز: الاحتمالية 5، والتأثير 3 (نصيبه 7.4%)، والأثر الزمني 29 يوماً');
select pg_temp.check((select status = 'closed' and closed_on is not null and not auto_active and notes like '%تعافى البند%' from pg_temp.risk(201))
                     and (select status = 'closed' and not auto_active from pg_temp.risk(376)),
                     'خطر البند الذي تعافى (والذي لم يحن موعده) يُغلق تلقائياً');
select pg_temp.check((select count(*) = 0 from risks where auto_key = 'pm_item:' || pg_temp.item(4) and auto_active), 'البند المنجز بلا خطر قائم');
-- الكلي: الفعلي 38.38% والمخطط 43.79% ← SPI 0.88 تأخر بسيط
select pg_temp.check((select status = 'open' and probability = 3 and effect like '%38.4%%%43.8%%%' from pg_temp.prisk()),
                     'خطر العقد: تأخر بسيط (الفعلي 38.4% مقابل 43.8%)');
select pg_temp.check(pg_temp.kinds() = 'W', 'وعامل ضعف في SWOT، وزال التهديد لأن الإنهاء المتوقع لا يتجاوز النهاية');
select pg_temp.check((select factor like 'تأخر تنفيذ «%' and impact like 'سلبي: متأخر بما يعادل % يوماً%' and importance = 4 and urgency = 3
                             and source = 'البرنامج الزمني' and code ~ '^W9[0-9]{2}$'
                        from swot_factors where auto_key = 'pm_plan:' || pg_temp.p() || ':W'),
                     'العامل بأثره السلبي بالأيام وأهميته 4 وإلحاحه 3');
select pg_temp.check((select count(*) >= 1 from pg_temp.alog() where action = 'risk.auto' and project_id = pg_temp.p() and (detail ->> 'closed')::int >= 3)
                     and (select count(*) >= 1 from pg_temp.alog() where action = 'swot.auto' and project_id = pg_temp.p()),
                     'الترجمة مسجّلة في سجل التدقيق');

-- ---------------------------------------------------------------- التحديث من الإشراف يترجم فوراً
set role authenticated;
select pg_temp.as_user('k.headsup@test.ly');
select public.save_pm_item(pg_temp.item(201), '{"progress": 40}');
select pg_temp.check((select status = 'open' and auto_active and closed_on is null and probability = 4 and impact = 5 from pg_temp.risk(201)),
                     'تأخر البند من جديد يعيد فتح خطره (حرج: الاحتمالية 4، ونصيبه 60.3% ← التأثير 5)');
select pg_temp.check((select probability = 4 from pg_temp.prisk()), 'وخطر العقد صار حرجاً');
select pg_temp.check((select importance = 5 and urgency = 5 from swot_factors where auto_key = 'pm_plan:' || pg_temp.p() || ':W'),
                     'وعامل الضعف صار بأهمية 5 وإلحاح 5');

-- إغلاق المستخدم لخطر ما زال بنده متأخراً يُحترم، وتعديله للإجراء لا يُمسّ
select pg_temp.as_user('k.headsup@test.ly');
select public.save_risk((pg_temp.risk(19)).id, jsonb_build_object(
  'description', (pg_temp.risk(19)).description, 'probability', 5, 'impact', 3, 'status', 'closed',
  'mitigation', 'تعزيز طاقم الحفر', 'owner', 'المهندس المشرف', 'category', 'زمني', 'phase', 'التنفيذ'));
select public.save_pm_item(pg_temp.item(201), '{"notes": "مراجعة"}');
select public.save_pm_item(pg_temp.item(201), '{"progress": 41}');
select pg_temp.check((select status = 'closed' and mitigation = 'تعزيز طاقم الحفر' and owner = 'المهندس المشرف' from pg_temp.risk(19)),
                     'الخطر الذي أغلقه المستخدم لا يُعاد فتحه، وإجراؤه ومالكه باقيان');

-- «لا ينطبق» يغلق خطر البند
reset role;
select pg_temp.ref('2026-03-25');
select pg_temp.sync();
select pg_temp.check((select status = 'open' and auto_active from pg_temp.risk(376)) is not true, 'الرخام لم يحن موعده في 2026/03/25');
set role authenticated;
select pg_temp.as_user('k.headsup@test.ly');
select pg_temp.check((select auto_active from pg_temp.risk(201)), 'الخرسانية متأخرة في 2026/03/25');
select public.save_pm_item(pg_temp.item(201), '{"not_applicable": true}');
select pg_temp.check((select status = 'closed' and not auto_active from pg_temp.risk(201)), 'بند «لا ينطبق» يُغلق خطره ويخرج من الحساب');
select public.save_pm_item(pg_temp.item(201), '{"not_applicable": false}');

-- ---------------------------------------------------------------- الاستراتيجية تحمي العامل الذي تستند إليه
reset role;
insert into swot_strategies (code, kind, strategy, internal_factors, external_factors)
select 'WT9', 'WT', 'خطة تعافٍ للعقود المتأخرة', array[code], '{}' from swot_factors where auto_key = 'pm_plan:' || pg_temp.p() || ':W';
select pg_temp.ref('2026-02-19');
set role authenticated;
select pg_temp.as_user('k.headsup@test.ly');
select public.save_pm_item(pg_temp.item(19), '{"progress": 100, "actual_start": "2026-01-01", "actual_end": "2026-01-25"}');
select public.save_pm_item(pg_temp.item(201), '{"progress": 80}');
-- الفعلي الكلي 60.88% مقابل 43.79% ← متقدم
select pg_temp.check((select status = 'closed' and not auto_active from pg_temp.risk(19))
                     and (select status = 'closed' and not auto_active from pg_temp.prisk()),
                     'تعافي البند والعقد يغلق خطريهما');
select pg_temp.check(pg_temp.kinds() = 'SW', 'العقد متقدم: عامل قوة، ويبقى عامل الضعف لأن استراتيجية تستند إليه');
select pg_temp.check((select impact like 'إيجابي: متقدم بما يعادل % يوماً%' from swot_factors where auto_key = 'pm_plan:' || pg_temp.p() || ':S'),
                     'بأثره الإيجابي بالأيام');
reset role;
delete from swot_strategies where code = 'WT9';
select pg_temp.sync();
select pg_temp.check(pg_temp.kinds() = 'S', 'وبعد حذف الاستراتيجية يُحذف عامل الضعف');

-- ---------------------------------------------------------------- الفرصة: إنهاء متوقع قبل الموعد بـ alert_days فأكثر
-- في 2026/05/01: كل البنود منجزة عدا البند الحر (من 04/30 إلى 05/05) عند 60% بعد يوم ← الإنهاء المتوقع 05/02، قبل النهاية بـ3 أيام،
-- والعقد ضمن المخطط (الفعلي 95.99% مقابل 96.79%، SPI 0.99) فلا عامل قوة
select pg_temp.ref('2026-05-01', 2);
set role authenticated;
select pg_temp.as_user('k.staff@test.ly');
select public.save_pm_item(pg_temp.item(201), '{"progress": 100}');
select public.save_pm_item(pg_temp.item(376), '{"progress": 100}');
select public.save_pm_item((select id from pm_items where project_id = pg_temp.p() and source = 'boq' and price_seq is null), '{"progress": 60}');
select pg_temp.check(pg_temp.kinds() = 'O', 'فرصة إنهاء قبل الموعد (3 أيام ≥ حد التنبيه 2)');
select pg_temp.check((select impact like 'إيجابي: إنهاء متوقع 2026/05/02 قبل نهاية البرنامج 2026/05/05 بـ3 يوماً%' from swot_factors where auto_key = 'pm_plan:' || pg_temp.p() || ':O'),
                     'بتاريخها وأيامها');
reset role;
select pg_temp.ref('2026-05-01', 7);
select pg_temp.sync();
select pg_temp.check(pg_temp.kinds() = '', 'وبحد التنبيه 7 أيام لا فرصة');

-- ---------------------------------------------------------------- إعادة فتح البرنامج تُوقف الترجمة
set role authenticated;
select pg_temp.as_user('k.headtech@test.ly');
select public.pm_plan_set_status(pg_temp.p(), 'draft');
select pg_temp.check((select count(*) = 0 from risks where project_id = pg_temp.p() and auto_key is not null and auto_active), 'إعادة فتح البرنامج تغلق مخاطره التلقائية');
select pg_temp.check(pg_temp.kinds() = '', 'وتحذف عوامله');
select public.pm_plan_set_status(pg_temp.p(), 'approved');

-- ---------------------------------------------------------------- التحديث الدوري والصلاحيات
reset role;
delete from pm_auto_runs;
select pg_temp.ref('');
set role authenticated;
select pg_temp.as_user('k.qa@test.ly');
select pg_temp.check(public.pm_refresh_auto() >= 1, 'التحديث الدوري يترجم البرامج المعتمدة');
select pg_temp.check(public.pm_refresh_auto() = 0, 'ومرة في الساعة على الأكثر');
select pg_temp.expect_error($$select public.pm_sync_auto(pg_temp.p())$$, 'لا استدعاء مباشر لدالة الترجمة');
select pg_temp.expect_error($$select * from public.pm_item_calcs(pg_temp.p())$$, 'ولا لدالة الحساب');
select pg_temp.expect_error($$update risks set auto_active = false where auto_key is not null$$, 'ولا كتابة مباشرة في المخاطر');
select pg_temp.expect_error($$select * from pm_auto_runs$$, 'ولا قراءة لجدول التشغيل');
set role anon;
select pg_temp.expect_error($$select public.pm_refresh_auto()$$, 'ولا للزائر');
reset role;
