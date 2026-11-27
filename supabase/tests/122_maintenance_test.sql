-- اختبارات الترحيل 40: قسم الصيانة — نطاقات الصلاحيات وظهور القسم لكل حساب فعّال، ورفع البلاغات (ومنها حساب الموظف)،
-- والفرز والإسناد، وتنفيذ الفني وإنجازه وتأكيد صاحب البلاغ وإعادة الفتح، والرفض والإلغاء والتعليق، وربط الأصول
-- (تحت الصيانة وعودته، والعهدة لا تُغيَّر)، والصيانة الدورية وتوليدها دون تكرار، والتنبيهات، والإعدادات، والفنيين، والقيود.
-- يُشغَّل بعد اختبارات الترحيل 39 (121) وعلى بياناتها، وبعد تطبيق 20261201000040_maintenance.sql مرتين والتراجع عنه وإعادته.
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
create or replace function pg_temp.rq(p_id uuid) returns setof public.mt_requests language sql security definer as $$ select * from public.mt_requests where id = p_id $$;
create or replace function pg_temp.pl(p_id uuid) returns setof public.mt_plans language sql security definer as $$ select * from public.mt_plans where id = p_id $$;
create or replace function pg_temp.events(p_id uuid) returns text language sql security definer as $$
  select string_agg(kind, ',' order by id) from public.mt_request_events where request_id = p_id
$$;
create or replace function pg_temp.asset(p_tag text) returns setof public.st_assets language sql security definer as $$ select * from public.st_assets where tag = p_tag $$;
create or replace function pg_temp.emp(p_no text) returns uuid language sql security definer as $$ select id from public.st_employees where emp_no = p_no $$;
create or replace function pg_temp.loc(p_name text) returns uuid language sql security definer as $$ select id from public.st_locations where name = p_name $$;
create or replace function pg_temp.cat(p_code text) returns uuid language sql security definer as $$ select id from public.st_categories where code = p_code $$;
create or replace function pg_temp.notes(p_email text, p_like text) returns bigint language sql security definer as $$
  select count(*) from public.notifications where user_id = (select id from auth.users where email = p_email) and kind = 'maintenance' and title like p_like
$$;
create or replace function pg_temp.occ(p_s date, p_u text, p_n int, p_k int) returns date language sql security definer as $$ select public.mt_occurrence(p_s, p_u, p_n, p_k) $$;
create or replace function pg_temp.near(p_a timestamptz, p_b timestamptz, p_hours numeric) returns boolean language sql as $$
  select abs(extract(epoch from (p_a - p_b)) - p_hours * 3600) < 2
$$;

update app_settings set value = 'false' where key in ('security.freeze', 'security.require_mfa_all');
update profiles set locked_until = null where email in ('director.new@test.ly', 'headrest@test.ly', 'u.qc@test.ly', 'u.heritage@test.ly', 'u.safety@test.ly',
                                                         'u.safetyhead@test.ly', 'pending@test.ly', 'k.qa@test.ly', 'staff.new@test.ly', 'auditor@test.ly');
create temp table ids (k text primary key, v uuid);
grant all on ids to authenticated;
create or replace function pg_temp.id(p_k text) returns uuid language sql as $$ select v from ids where k = p_k $$;
create temp table snap (who text, kind text, severity text, ref_kind text, ref_id uuid, since timestamptz);
grant all on snap to authenticated;
grant execute on all functions in schema pg_temp to authenticated, anon;

-- ---------------------------------------------------------------- البذور
select pg_temp.check((select count(*) = 8 from mt_settings), 'ثمانية إعدادات مبدئية للصيانة');
select pg_temp.check((select (value ->> 'urgent')::int = 8 and (value ->> 'high')::int = 48 and (value ->> 'normal')::int = 120 and (value ->> 'low')::int = 240
                        from mt_settings where key = 'sla_hours'), 'مدد الإنجاز المبدئية: عاجل 8 وعالٍ 48 وعادي 120 ومنخفض 240 ساعة');
select pg_temp.check((select value = '4'::jsonb from mt_settings where key = 'assign_hours')
                     and (select value = '7'::jsonb from mt_settings where key = 'hold_days')
                     and (select value = '3'::jsonb from mt_settings where key = 'confirm_days')
                     and (select value = '24'::jsonb from mt_settings where key = 'soon_hours')
                     and (select value = '3'::jsonb from mt_settings where key = 'repeat_count')
                     and (select value = '90'::jsonb from mt_settings where key = 'repeat_days')
                     and (select value = '7'::jsonb from mt_settings where key = 'plan_lead_days'), 'حدود التنبيه المبدئية');
select pg_temp.check(public.mt_occurrence('2026-01-31', 'month', 1, 1) = '2026-02-28' and public.mt_occurrence('2026-01-31', 'month', 1, 2) = '2026-03-31',
                     'موعد الخطة يُحسب من تاريخ البدء فلا ينزلق نهاية الأشهر: 31 يناير ← 28 فبراير ← 31 مارس');
select pg_temp.check(public.mt_occurrence('2026-01-10', 'week', 2, 3) = '2026-02-21' and public.mt_occurrence('2026-01-10', 'day', 10, 2) = '2026-01-30'
                     and public.mt_occurrence('2024-02-29', 'year', 1, 1) = '2025-02-28', 'التكرار بالأيام والأسابيع والسنوات');

-- ---------------------------------------------------------------- نطاقات الصلاحيات
set role authenticated;
select pg_temp.as_user('director.new@test.ly', 'aal2');
select public.set_user_grants(pg_temp.uid('u.qc@test.ly'), array['stores:manager', 'maintenance:manager']);
select public.set_user_grants(pg_temp.uid('u.heritage@test.ly'), array['stores:admin', 'maintenance:admin']);
select public.set_user_grants(pg_temp.uid('u.safetyhead@test.ly'), array['stores:audit', 'maintenance:audit']);
select public.set_user_grants(pg_temp.uid('k.qa@test.ly'), array['maintenance:tech']);
select pg_temp.check((select count(*) = 4 from user_grants where scope like 'maintenance:%'), 'المدير يمنح نطاقات الصيانة الأربعة');
select pg_temp.expect_error($q$select public.set_user_grants(pg_temp.uid('headrest@test.ly'), array['maintenance:boss'])$q$, 'نطاق صيانة غير معروف');
select pg_temp.expect_error($q$select public.set_user_grants(pg_temp.uid('pending@test.ly'), array['maintenance:manager'])$q$, 'لا يُمنح حساب الموظف نطاقاً');
-- الفني بحساب: يُربط سجله بحسابه
select public.st_save_employee(pg_temp.emp('E-200'), jsonb_build_object('emp_no', 'E-200', 'full_name', 'عمر الهادي', 'profile_id', pg_temp.uid('k.qa@test.ly')));
select pg_temp.check((select profile_id = pg_temp.uid('k.qa@test.ly') from st_employees where emp_no = 'E-200'), 'سجل الفني مربوط بحسابه');

-- ---------------------------------------------------------------- ظهور القسم
select pg_temp.as_user('pending@test.ly');
select pg_temp.check(public.my_sections() = array['maintenance', 'manual', 'stores'], 'حساب الموظف: الصيانة والدليل والمخازن');
select pg_temp.check(public.mt_me_ok() and public.mt_can_report() and not public.mt_staff() and not public.mt_sees_all(), 'الموظف يرفع بلاغاته ولا يُعدّ من أهل القسم');
select pg_temp.as_user('u.safety@test.ly');
select pg_temp.check('maintenance' = any (public.my_sections()) and public.mt_can_report() and not public.mt_staff(), 'أي عضو يرى القسم ويرفع بلاغاً دون أن يكون من أهله');
select pg_temp.as_user('auditor@test.ly');
select pg_temp.check(not ('maintenance' = any (public.my_sections())) and not public.mt_me_ok(), 'مسؤول الأمن لا يرى القسم ولا يرفع بلاغاً');
select pg_temp.expect_error($q$select public.mt_report('{"title": "بلاغ من مسؤول الأمن"}'::jsonb)$q$, 'مسؤول الأمن لا يرفع بلاغاً');
select pg_temp.check(public.mt_lookups() = '{}'::jsonb, 'ولا قوائم له');
select pg_temp.as_user('u.qc@test.ly');
select pg_temp.check(public.mt_staff() and public.mt_sees_all() and public.mt_can_manage() and not public.mt_can_admin(), 'مدير الصيانة: يرى ويدير ولا يضبط الإعدادات');
select pg_temp.as_user('u.heritage@test.ly');
select pg_temp.check(public.mt_can_manage() and public.mt_can_admin(), 'مدير النظام في القسم: يدير ويضبط');
select pg_temp.as_user('u.safetyhead@test.ly');
select pg_temp.check(public.mt_sees_all() and not public.mt_can_manage() and not public.mt_can_admin(), 'المراجع: يرى فقط');
select pg_temp.as_user('k.qa@test.ly');
select pg_temp.check(public.mt_staff() and not public.mt_sees_all() and not public.mt_can_manage() and public.mt_is_assignee(pg_temp.emp('E-200'))
                     and not public.mt_is_assignee(pg_temp.emp('E-201')), 'الفني: من أهل القسم يرى بلاغاته المسنَدة وحدها');

-- ---------------------------------------------------------------- رفع البلاغات
select pg_temp.as_user('pending@test.ly');
insert into ids select 'r1', public.mt_report(jsonb_build_object('title', 'عطل في إنارة غرفة 004', 'description', 'المصباح الرئيسي لا يعمل منذ أمس',
  'category', 'electrical', 'location_id', pg_temp.loc('غرفة 004'), 'place_note', 'بجوار النافذة'));
select pg_temp.check((select req_no ~ '^MR-[0-9]{4}-0001$' and status = 'new' and priority = 'normal' and category = 'electrical'
                        and reporter_id = pg_temp.uid('pending@test.ly') and reporter_name = 'سالم علي المبروك' and source = 'report'
                        and pg_temp.near(due_at, reported_at, 120) from pg_temp.rq(pg_temp.id('r1'))),
                     'حساب الموظف يرفع بلاغاً برقم MR-سنة-0001، جديد، ومدة الإنجاز 120 ساعة، واسمه من سجل الموظف');
select pg_temp.check((select count(*) = 1 from mt_requests) and (select count(*) = 1 from mt_request_events), 'يرى بلاغه وحدثه وحدهما');
select pg_temp.check((select count(*) = 0 from mt_plans) and (select count(*) = 0 from mt_settings) and (select count(*) = 0 from mt_technicians),
                     'ولا يقرأ الخطط ولا الإعدادات ولا الفنيين');
select pg_temp.check((select jsonb_array_length(public.mt_lookups() -> 'locations') >= 3 and public.mt_lookups() -> 'technicians' = '[]'::jsonb
                             and public.mt_lookups() -> 'assets' = '[]'::jsonb), 'قوائم المواقع له، والفنيون والأصول لأهل القسم وحدهم');
insert into ids select 'r2', public.mt_report(jsonb_build_object('title', 'الحاسوب لا يعمل', 'category', 'it', 'priority', 'high', 'asset_tag', 'ofe-a-0001'));
select pg_temp.check((select asset_tag = 'OFE-A-0001' and asset_name = 'حاسوب محمول' and asset_id is not null and pg_temp.near(due_at, reported_at, 48)
                        from pg_temp.rq(pg_temp.id('r2'))), 'البلاغ يُربط بالأصل من رقمه بلا كشف بياناته، والعالي 48 ساعة');
select pg_temp.expect_error($q$select public.mt_report('{"title": "عطل", "asset_tag": "NOPE-1"}'::jsonb)$q$, 'رقم أصل غير مسجل');
select pg_temp.expect_error(format($q$select public.mt_report(jsonb_build_object('title', 'عطل ما', 'asset_id', %L))$q$, (select id from pg_temp.asset('OFE-A-0001') a)),
                            'لا يُربط الأصل بمعرّفه لغير أهل القسم');
select pg_temp.expect_error($q$select public.mt_report('{"title": "ab"}'::jsonb)$q$, 'عنوان البلاغ 3 أحرف فأكثر');
select pg_temp.expect_error($q$select public.mt_report('{"title": "عطل ما", "category": "magic"}'::jsonb)$q$, 'تصنيف غير معروف');
select pg_temp.expect_error($q$select public.mt_report('{"title": "عطل ما", "priority": "now"}'::jsonb)$q$, 'أولوية غير معروفة');
select pg_temp.expect_error($q$select public.mt_report('{"title": "عطل ما", "location_id": "00000000-0000-0000-0000-000000000000"}'::jsonb)$q$, 'موقع غير موجود');
select pg_temp.expect_error($q$select public.mt_report('[]'::jsonb)$q$, 'بيانات البلاغ كائن');

select pg_temp.as_user('u.safety@test.ly');
insert into ids select 'r3', public.mt_report(jsonb_build_object('title', 'تسرب مياه في الممر', 'category', 'plumbing', 'priority', 'urgent',
  'location_id', pg_temp.loc('الطابق الأرضي'), 'phone', '0912345678'));
select pg_temp.check((select pg_temp.near(due_at, reported_at, 8) and reporter_phone = '0912345678' from pg_temp.rq(pg_temp.id('r3'))), 'العاجل 8 ساعات ورقم الهاتف المكتوب');
select pg_temp.check((select count(*) = 1 from mt_requests) and (select id = pg_temp.id('r3') from mt_requests), 'لا يرى بلاغات غيره');
reset role;
select pg_temp.check(pg_temp.notes('director.new@test.ly', 'بلاغ صيانة عاجل%') = 1 and pg_temp.notes('u.qc@test.ly', 'بلاغ صيانة عاجل%') = 1
                     and pg_temp.notes('u.heritage@test.ly', 'بلاغ صيانة عاجل%') = 1 and pg_temp.notes('pending@test.ly', '%') = 0,
                     'البلاغ العاجل يُشعر المدير ومديري الصيانة');
select pg_temp.check(pg_temp.notes('u.qc@test.ly', 'بلاغ صيانة عالي الأولوية%') = 1, 'والعالي الأولوية كذلك، والعادي لا إشعار له');
set role authenticated;

-- ---------------------------------------------------------------- الفنيون والإسناد
select pg_temp.as_user('u.qc@test.ly');
select pg_temp.check((select count(*) = 3 from mt_requests), 'مدير الصيانة يرى كل البلاغات');
select pg_temp.check(public.mt_lookups() -> 'technicians' = '[]'::jsonb and jsonb_array_length(public.mt_lookups() -> 'assets') >= 3
                     and public.mt_lookups() -> 'employees' = '[]'::jsonb, 'قوائمه: الأصول والفنيون، ولا قائمة موظفين');
select pg_temp.expect_error($q$select public.mt_save_technician(pg_temp.emp('E-200'), '{"trade": "electrical"}'::jsonb)$q$, 'قائمة الفنيين لمدير النظام أو المدير');
select pg_temp.expect_error(format($q$select public.mt_assign(%L, jsonb_build_object('assignee_id', %L))$q$, pg_temp.id('r1'), pg_temp.emp('E-200')),
                            'لا إسناد لموظف ليس فنياً');
select pg_temp.as_user('u.heritage@test.ly');
select pg_temp.check(jsonb_array_length(public.mt_lookups() -> 'employees') >= 4, 'مدير النظام يرى الموظفين ليختار الفنيين');
select public.mt_save_technician(pg_temp.emp('E-200'), '{"trade": "electrical", "note": "كهربائي المقر"}'::jsonb);
select public.mt_save_technician(pg_temp.emp('E-201'), '{"trade": "general"}'::jsonb);
select public.mt_save_technician(pg_temp.emp('E-101'), '{"trade": "it"}'::jsonb);
select pg_temp.check((select count(*) = 3 and count(*) filter (where active) = 3 from mt_technicians), 'ثلاثة فنيين فعّالين');
select pg_temp.expect_error($q$select public.mt_save_technician(pg_temp.emp('E-200'), '{"trade": "magic"}'::jsonb)$q$, 'تخصص غير معروف');
select pg_temp.expect_error($q$select public.mt_save_technician('00000000-0000-0000-0000-000000000000', '{}'::jsonb)$q$, 'موظف غير موجود');
select public.mt_save_technician(pg_temp.emp('E-101'), '{"trade": "it", "active": false}'::jsonb);
select pg_temp.check((select not active from mt_technicians where employee_id = pg_temp.emp('E-101')), 'إيقاف فني بلا بلاغات مفتوحة');

select pg_temp.as_user('u.qc@test.ly');
select pg_temp.expect_error(format($q$select public.mt_assign(%L, '{}'::jsonb)$q$, pg_temp.id('r1')), 'الإسناد يحتاج فنياً أو جهة خارجية');
select pg_temp.expect_error(format($q$select public.mt_assign(%L, jsonb_build_object('assignee_id', %L))$q$, pg_temp.id('r1'), pg_temp.emp('E-101')),
                            'لا إسناد لفني موقوف');
select pg_temp.expect_error(format($q$select public.mt_assign(%L, jsonb_build_object('assignee_id', %L, 'priority', 'now'))$q$, pg_temp.id('r1'), pg_temp.emp('E-200')),
                            'أولوية الإسناد معروفة');
select public.mt_assign(pg_temp.id('r1'), jsonb_build_object('assignee_id', pg_temp.emp('E-200'), 'due_date', (current_date + 3)::text, 'note', 'الأولوية للغرفة'));
select pg_temp.check((select status = 'assigned' and assignee_id = pg_temp.emp('E-200') and assignee_name = 'عمر الهادي' and assigned_at is not null
                        and due_at = ((current_date + 4)::timestamp at time zone 'Africa/Tripoli') - interval '1 second'
                        from pg_temp.rq(pg_temp.id('r1'))), 'الإسناد لفني: مُسنَد، والموعد آخر يوم التاريخ المكتوب بتوقيت طرابلس');
select public.mt_assign(pg_temp.id('r3'), jsonb_build_object('vendor', 'شركة السباكة الحديثة'));
select pg_temp.check((select status = 'assigned' and assignee_id is null and vendor = 'شركة السباكة الحديثة' from pg_temp.rq(pg_temp.id('r3'))), 'الإسناد لجهة خارجية');
select public.mt_assign(pg_temp.id('r2'), jsonb_build_object('assignee_id', pg_temp.emp('E-201'), 'priority', 'normal'));
select pg_temp.check((select priority = 'normal' and pg_temp.near(due_at, reported_at, 120) from pg_temp.rq(pg_temp.id('r2'))), 'تغيير الأولوية يعيد حساب الموعد من وقت البلاغ');
reset role;
select pg_temp.check(pg_temp.notes('k.qa@test.ly', 'أُسنِد إليك بلاغ صيانة%') = 1, 'الفني بحساب يُشعَر بإسناده');
set role authenticated;
select pg_temp.as_user('pending@test.ly');
select pg_temp.expect_error(format($q$select public.mt_assign(%L, jsonb_build_object('assignee_id', %L))$q$, pg_temp.id('r1'), pg_temp.emp('E-200')), 'صاحب البلاغ لا يُسند');
select pg_temp.as_user('u.safetyhead@test.ly');
select pg_temp.expect_error(format($q$select public.mt_assign(%L, jsonb_build_object('assignee_id', %L))$q$, pg_temp.id('r1'), pg_temp.emp('E-200')), 'المراجع لا يُسند');

-- ---------------------------------------------------------------- تنفيذ الفني
select pg_temp.as_user('k.qa@test.ly');
select pg_temp.check((select count(*) = 1 and bool_and(id = pg_temp.id('r1')) from mt_requests), 'الفني يرى بلاغه المسنَد إليه وحده');
select pg_temp.check((select count(*) = 3 from mt_technicians) and (select count(*) = 0 from mt_settings) = false, 'ويقرأ الفنيين والإعدادات (من أهل القسم)');
select pg_temp.expect_error(format($q$select public.mt_progress(%L, 'done', '{"resolution": "تم الإصلاح"}'::jsonb)$q$, pg_temp.id('r1')), 'لا إنجاز قبل التنفيذ');
select pg_temp.expect_error(format($q$select public.mt_progress(%L, 'start')$q$, pg_temp.id('r2')), 'الفني لا يبدأ بلاغ غيره');
select pg_temp.expect_error(format($q$select public.mt_progress(%L, 'fly')$q$, pg_temp.id('r1')), 'إجراء غير معروف');
select pg_temp.expect_error(format($q$select public.mt_assign(%L, jsonb_build_object('assignee_id', %L))$q$, pg_temp.id('r1'), pg_temp.emp('E-201')), 'الفني لا يُسند');
select public.mt_progress(pg_temp.id('r1'), 'start');
select pg_temp.check((select status = 'in_progress' and started_at is not null from pg_temp.rq(pg_temp.id('r1'))), 'بدء التنفيذ');
select pg_temp.expect_error(format($q$select public.mt_progress(%L, 'start')$q$, pg_temp.id('r1')), 'لا بدء مرتين');
select pg_temp.expect_error(format($q$select public.mt_progress(%L, 'hold')$q$, pg_temp.id('r1')), 'التعليق بسبب');
select public.mt_progress(pg_temp.id('r1'), 'hold', '{"note": "بانتظار مصباح بديل"}'::jsonb);
select pg_temp.check((select status = 'on_hold' and on_hold_at is not null and hold_reason = 'بانتظار مصباح بديل' from pg_temp.rq(pg_temp.id('r1'))), 'تعليق بسببه');
select public.mt_progress(pg_temp.id('r1'), 'resume');
select pg_temp.check((select status = 'in_progress' and on_hold_at is null and hold_reason = '' from pg_temp.rq(pg_temp.id('r1'))), 'استئناف');
select pg_temp.expect_error(format($q$select public.mt_progress(%L, 'done', '{"resolution": "ت"}'::jsonb)$q$, pg_temp.id('r1')), 'الإنجاز بوصف المعالجة');
select public.mt_progress(pg_temp.id('r1'), 'done', '{"resolution": "استُبدل المصباح وفُحصت التوصيلات"}'::jsonb);
select pg_temp.check((select status = 'done' and done_at is not null and resolution like 'استُبدل%' from pg_temp.rq(pg_temp.id('r1')))
                     and pg_temp.events(pg_temp.id('r1')) = 'create,assign,start,hold,resume,done', 'إنجاز بوصف المعالجة، وسجل أحداث البلاغ بترتيبه');
reset role;
select pg_temp.check(pg_temp.notes('pending@test.ly', 'أُنجز بلاغك%') = 1, 'صاحب البلاغ يُشعَر بإنجازه');
set role authenticated;

-- ---------------------------------------------------------------- تأكيد صاحب البلاغ
select pg_temp.as_user('u.safety@test.ly');
select pg_temp.expect_error(format($q$select public.mt_confirm(%L, true)$q$, pg_temp.id('r1')), 'غير صاحب البلاغ لا يؤكد');
select pg_temp.as_user('pending@test.ly');
select pg_temp.expect_error(format($q$select public.mt_confirm(%L, true, 'جيد', 6)$q$, pg_temp.id('r1')), 'التقييم من 1 إلى 5');
select pg_temp.expect_error(format($q$select public.mt_confirm(%L, false)$q$, pg_temp.id('r1')), 'إعادة الفتح بسبب');
select pg_temp.expect_error(format($q$select public.mt_confirm(%L, true)$q$, pg_temp.id('r2')), 'لا يُؤكَّد بلاغ لم يُنجَز');
select public.mt_confirm(pg_temp.id('r1'), true, 'تم الإصلاح بسرعة', 5);
select pg_temp.check((select status = 'closed' and rating = 5 and closed_by = pg_temp.uid('pending@test.ly') and closed_at is not null and rating_note = 'تم الإصلاح بسرعة'
                        from pg_temp.rq(pg_temp.id('r1'))), 'صاحب البلاغ يؤكد الإغلاق بتقييم 5');
select pg_temp.expect_error(format($q$select public.mt_confirm(%L, true)$q$, pg_temp.id('r1')), 'لا تأكيد بعد الإغلاق');
select pg_temp.expect_error(format($q$select public.mt_progress(%L, 'start')$q$, pg_temp.id('r1')), 'المغلق لا يُنفَّذ');

-- ---------------------------------------------------------------- الأصول: تحت الصيانة وعودته، والعهدة لا تُغيَّر
select pg_temp.as_user('headrest@test.ly');
select public.st_save_asset(null, jsonb_build_object('name', 'مكيف مكتبي', 'category_id', pg_temp.cat('FUR'), 'cost', 2000,
  'location_id', pg_temp.loc('غرفة 004'), 'warranty_until', (current_date + 30)::text));
select public.st_save_asset(null, jsonb_build_object('name', 'هاتف مكتبي', 'category_id', pg_temp.cat('OFE'), 'cost', 100));
reset role;
create temp table tags (k text primary key, v text);
insert into tags select 'ac', tag from st_assets where name = 'مكيف مكتبي';
insert into tags select 'phone', tag from st_assets where name = 'هاتف مكتبي';
grant all on tags to authenticated;
create or replace function pg_temp.tag(p_k text) returns text language sql as $$ select v from tags where k = p_k $$;
grant execute on function pg_temp.tag(text) to authenticated;
set role authenticated;
select pg_temp.as_user('headrest@test.ly');
select public.st_custody_out((select id from pg_temp.asset(pg_temp.tag('phone')) a), jsonb_build_object('employee_id', pg_temp.emp('E-100'), 'condition', 'good'));
select pg_temp.check((select status = 'custody' from pg_temp.asset(pg_temp.tag('phone'))), 'الهاتف في عهدة موظف');

select pg_temp.as_user('pending@test.ly');
insert into ids select 'r4', public.mt_report(jsonb_build_object('title', 'المكيف لا يبرّد', 'category', 'hvac', 'priority', 'high', 'asset_tag', pg_temp.tag('ac')));
insert into ids select 'r5', public.mt_report(jsonb_build_object('title', 'الهاتف بلا صوت', 'category', 'it', 'asset_tag', pg_temp.tag('phone')));
select pg_temp.as_user('u.qc@test.ly');
select public.mt_assign(pg_temp.id('r4'), jsonb_build_object('assignee_id', pg_temp.emp('E-200')));
select public.mt_assign(pg_temp.id('r5'), jsonb_build_object('assignee_id', pg_temp.emp('E-200')));
select pg_temp.as_user('k.qa@test.ly');
select pg_temp.check((select status = 'in_use' and warranty_until = current_date + 30 from pg_temp.asset(pg_temp.tag('ac'))), 'المكيف مستخدم وتحت الضمان قبل الصيانة');
select public.mt_progress(pg_temp.id('r4'), 'start');
select pg_temp.check((select status = 'maintenance' from pg_temp.asset(pg_temp.tag('ac'))) and (select asset_held from pg_temp.rq(pg_temp.id('r4'))),
                     'بدء الصيانة يجعل الأصل «تحت الصيانة»');
select public.mt_progress(pg_temp.id('r5'), 'start');
select pg_temp.check((select status = 'custody' from pg_temp.asset(pg_temp.tag('phone'))) and not (select asset_held from pg_temp.rq(pg_temp.id('r5'))),
                     'أصل العهدة لا يتغير وضعه ببدء الصيانة');
select public.mt_progress(pg_temp.id('r4'), 'done', '{"resolution": "تعبئة غاز وتنظيف الفلاتر"}'::jsonb);
select pg_temp.check((select status = 'in_use' from pg_temp.asset(pg_temp.tag('ac'))) and not (select asset_held from pg_temp.rq(pg_temp.id('r4'))),
                     'إنجاز البلاغ يعيد الأصل لوضعه (مستخدم)');
select pg_temp.as_user('pending@test.ly');
select public.mt_confirm(pg_temp.id('r4'), false, 'ما زال لا يبرّد');
select pg_temp.check((select status = 'in_progress' and done_at is null from pg_temp.rq(pg_temp.id('r4')))
                     and (select status = 'maintenance' from pg_temp.asset(pg_temp.tag('ac'))), 'إعادة فتح البلاغ بسبب تعيد الأصل إلى «تحت الصيانة»');
select pg_temp.as_user('k.qa@test.ly');
select public.mt_progress(pg_temp.id('r4'), 'done', '{"resolution": "استُبدل الضاغط"}'::jsonb);
select pg_temp.as_user('pending@test.ly');
select public.mt_confirm(pg_temp.id('r4'), true);
select pg_temp.check((select status = 'closed' and rating is null from pg_temp.rq(pg_temp.id('r4'))) and (select status = 'in_use' from pg_temp.asset(pg_temp.tag('ac')))
                     and pg_temp.events(pg_temp.id('r4')) = 'create,assign,start,done,reopen,done,close', 'تأكيد دون تقييم، والأصل مستخدم، وسجل الأحداث كاملاً');
reset role;
select pg_temp.check((select count(*) = 4 from st_asset_events e join st_assets a on a.id = e.asset_id
                       where a.tag = pg_temp.tag('ac') and e.kind = 'status' and e.data ->> 'request' is not null),
                     'أحداث الأصل: دخول الصيانة وخروجها مرتين بإشارة رقم البلاغ');
set role authenticated;

-- ---------------------------------------------------------------- الرفض والإلغاء والتعليق والبلاغ نيابة عن صاحبه
select pg_temp.as_user('pending@test.ly');
insert into ids select 'r6', public.mt_report('{"title": "طلب خارج اختصاص الصيانة", "category": "other", "priority": "low"}'::jsonb);
select pg_temp.as_user('u.qc@test.ly');
select pg_temp.expect_error(format($q$select public.mt_reject(%L, '')$q$, pg_temp.id('r6')), 'الرفض بسبب');
select pg_temp.expect_error(format($q$select public.mt_reject(%L, 'سبب')$q$, pg_temp.id('r2')), 'لا يُرفض بلاغ مُسنَد');
select public.mt_reject(pg_temp.id('r6'), 'يُرفع لقسم المشتريات');
select pg_temp.check((select status = 'rejected' and reject_reason = 'يُرفع لقسم المشتريات' from pg_temp.rq(pg_temp.id('r6'))), 'مدير الصيانة يرفض بلاغاً جديداً بسبب');
reset role;
select pg_temp.check(pg_temp.notes('pending@test.ly', 'رُفض بلاغك%') = 1, 'صاحب البلاغ يُشعَر برفضه');
set role authenticated;
select pg_temp.as_user('pending@test.ly');
insert into ids select 'r7', public.mt_report('{"title": "بلاغ مكرر", "category": "civil"}'::jsonb);
select public.mt_cancel(pg_temp.id('r7'), 'رُفع مكرراً');
select pg_temp.check((select status = 'cancelled' from pg_temp.rq(pg_temp.id('r7'))), 'صاحب البلاغ يلغي بلاغه ما دام جديداً');
select pg_temp.expect_error(format($q$select public.mt_cancel(%L)$q$, pg_temp.id('r2')), 'لا يلغي صاحب البلاغ بلاغاً أُسنِد');
insert into ids select 'r8', public.mt_report('{"title": "باب مكتب لا يُغلق", "category": "carpentry"}'::jsonb);
select pg_temp.as_user('u.qc@test.ly');
select public.mt_assign(pg_temp.id('r8'), jsonb_build_object('assignee_id', pg_temp.emp('E-201')));
select public.mt_cancel(pg_temp.id('r8'), 'أُصلح من الإدارة');
select pg_temp.check((select status = 'cancelled' from pg_temp.rq(pg_temp.id('r8'))), 'مدير الصيانة يلغي بلاغاً مُسنَداً');
select pg_temp.expect_error(format($q$select public.mt_assign(%L, jsonb_build_object('assignee_id', %L))$q$, pg_temp.id('r8'), pg_temp.emp('E-200')), 'لا إسناد لملغى');
select pg_temp.expect_error(format($q$select public.mt_cancel(%L)$q$, pg_temp.id('r1')), 'لا يُلغى بلاغ مغلق');

select public.mt_comment(pg_temp.id('r2'), 'تم التواصل مع الصاحب');
select pg_temp.as_user('pending@test.ly');
select public.mt_comment(pg_temp.id('r2'), 'الحاسوب ما زال معطلاً');
select pg_temp.as_user('u.safety@test.ly');
select pg_temp.expect_error(format($q$select public.mt_comment(%L, 'تعليق متطفل')$q$, pg_temp.id('r2')), 'غير المعني لا يعلّق');
select pg_temp.as_user('k.qa@test.ly');
select public.mt_comment(pg_temp.id('r1'), 'للعلم');
select pg_temp.expect_error(format($q$select public.mt_comment(%L, 'م')$q$, pg_temp.id('r1')), 'التعليق حرفان فأكثر');
reset role;
select pg_temp.check((select string_agg(kind, ',' order by id) = 'create,assign,comment,comment' from mt_request_events where request_id = pg_temp.id('r2')), 'التعليقات في سجل أحداث البلاغ');
set role authenticated;

-- بلاغ هاتفي يسجله مدير الصيانة نيابة عن صاحبه: لا حساب فيؤكد المدير إغلاقه
select pg_temp.as_user('u.qc@test.ly');
insert into ids select 'r9', public.mt_report(jsonb_build_object('title', 'تسريب في دورة المياه', 'category', 'plumbing', 'reporter_name', 'مراجع من خارج المقر',
  'reporter_dept', 'الاستقبال', 'phone', '0925550000'));
select pg_temp.check((select reporter_id is null and reporter_name = 'مراجع من خارج المقر' and reporter_dept = 'الاستقبال' from pg_temp.rq(pg_temp.id('r9'))),
                     'البلاغ نيابة عن صاحبه بلا حساب');
select public.mt_assign(pg_temp.id('r9'), jsonb_build_object('assignee_id', pg_temp.emp('E-200')));
select pg_temp.as_user('k.qa@test.ly');
select public.mt_progress(pg_temp.id('r9'), 'start');
select public.mt_progress(pg_temp.id('r9'), 'done', '{"resolution": "استُبدلت الوصلة"}'::jsonb);
select pg_temp.as_user('pending@test.ly');
select pg_temp.expect_error(format($q$select public.mt_confirm(%L, true)$q$, pg_temp.id('r9')), 'لا يؤكده غير مدير الصيانة');
select pg_temp.as_user('u.qc@test.ly');
select pg_temp.expect_error(format($q$select public.mt_confirm(%L, true, 'جيد', 4)$q$, pg_temp.id('r9')), 'التقييم من صاحب البلاغ وحده');

-- ---------------------------------------------------------------- الصيانة الدورية
select pg_temp.as_user('k.qa@test.ly');
select pg_temp.expect_error($q$select public.mt_save_plan(null, '{"title": "فحص", "interval_unit": "month", "interval_count": 1, "start_date": "2026-01-01"}'::jsonb)$q$,
                            'الفني لا يضع خططاً');
select pg_temp.as_user('u.qc@test.ly');
insert into ids select 'p1', public.mt_save_plan(null, jsonb_build_object('title', 'فحص مولد الكهرباء', 'category', 'electrical', 'interval_unit', 'month',
  'interval_count', 1, 'start_date', (current_date - 10)::text, 'lead_days', 30, 'assignee_id', pg_temp.emp('E-200'), 'checklist', 'الزيت، البطارية، الوقود'));
insert into ids select 'p2', public.mt_save_plan(null, jsonb_build_object('title', 'تنظيف فلاتر التكييف', 'category', 'hvac', 'interval_unit', 'week',
  'interval_count', 1, 'start_date', (current_date + 3)::text, 'asset_tag', pg_temp.tag('ac')));
insert into ids select 'p3', public.mt_save_plan(null, jsonb_build_object('title', 'فحص طفايات الحريق', 'category', 'safety', 'interval_unit', 'year',
  'interval_count', 1, 'start_date', (current_date + 200)::text, 'priority', 'high'));
select pg_temp.check((select plan_no = 'MP-0001' and next_due >= current_date and next_due - current_date between 15 and 25 and seq = 1 and active
                        from pg_temp.pl(pg_temp.id('p1'))), 'الخطة الشهرية: رقمها MP-0001، وموعدها القادم أول موعد لا يقل عن اليوم');
select pg_temp.check((select next_due = current_date + 3 and seq = 0 and asset_tag = pg_temp.tag('ac') from pg_temp.pl(pg_temp.id('p2'))), 'خطة تبدأ بعد ثلاثة أيام: موعدها تاريخ البدء، ومربوطة بالأصل');
select pg_temp.expect_error($q$select public.mt_save_plan(null, '{"title": "خطة", "interval_unit": "month", "interval_count": 0, "start_date": "2026-01-01"}'::jsonb)$q$, 'التكرار 1 فأكثر');
select pg_temp.expect_error($q$select public.mt_save_plan(null, '{"title": "خطة", "interval_unit": "decade", "interval_count": 1, "start_date": "2026-01-01"}'::jsonb)$q$, 'وحدة تكرار غير معروفة');
select pg_temp.expect_error($q$select public.mt_save_plan(null, '{"title": "خطة", "interval_unit": "month", "interval_count": 61, "start_date": "2026-01-01"}'::jsonb)$q$, 'حتى 60 شهراً');
select pg_temp.expect_error($q$select public.mt_save_plan(null, '{"title": "خطة", "interval_unit": "week", "interval_count": 53, "start_date": "2026-01-01"}'::jsonb)$q$, 'حتى 52 أسبوعاً');
select pg_temp.expect_error($q$select public.mt_save_plan(null, '{"title": "خطة", "interval_unit": "month", "interval_count": 1}'::jsonb)$q$, 'تاريخ البدء مطلوب');
select pg_temp.expect_error($q$select public.mt_save_plan(null, '{"title": "خطة", "interval_unit": "month", "interval_count": 1, "start_date": "2026-01-01", "lead_days": 91}'::jsonb)$q$, 'التنبيه المسبق حتى 90 يوماً');
select pg_temp.expect_error(format($q$select public.mt_save_plan(null, jsonb_build_object('title', 'خطة', 'interval_unit', 'month', 'interval_count', 1,
  'start_date', '2026-01-01', 'assignee_id', %L))$q$, pg_temp.emp('E-101')), 'لا إسناد خطة لفني موقوف');
select pg_temp.expect_error($q$select public.mt_save_plan(null, '{"title": "خطة", "interval_unit": "month", "interval_count": 1, "start_date": "2026-01-01", "priority": "now"}'::jsonb)$q$, 'أولوية الخطة');
select pg_temp.as_user('pending@test.ly');
select pg_temp.expect_error($q$select public.mt_generate_due()$q$, 'التوليد لأهل القسم');
select pg_temp.check((select count(*) = 0 from mt_plans), 'والخطط لا تُقرأ من غير أهل القسم');
select pg_temp.as_user('k.qa@test.ly');
select pg_temp.check(public.mt_generate_due() = '{"created": 2, "skipped": 0}'::jsonb, 'التوليد: بلاغان وقائيان (الخطة الشهرية بتنبيهها المسبق، والأسبوعية)، والسنوية لم يحن وقتها');
select pg_temp.check(public.mt_generate_due() = '{"created": 0, "skipped": 0}'::jsonb, 'إعادة التوليد لا تكرر الموعد الواحد');
select pg_temp.as_user('u.qc@test.ly');
insert into ids select 'q1', id from mt_requests where plan_id = pg_temp.id('p1');
insert into ids select 'q2', id from mt_requests where plan_id = pg_temp.id('p2');
select pg_temp.check((select source = 'plan' and status = 'assigned' and assignee_id = pg_temp.emp('E-200') and title = 'فحص مولد الكهرباء' and description = 'الزيت، البطارية، الوقود'
                        and due_at = ((pg_temp.occ(current_date - 10, 'month', 1, 1) + 1)::timestamp at time zone 'Africa/Tripoli') - interval '1 second'
                        from pg_temp.rq(pg_temp.id('q1'))), 'البلاغ الوقائي من الخطة الشهرية: مُسنَد للفني، وموعده يوم استحقاقها، وبند الفحص في وصفه');
select pg_temp.check((select source = 'plan' and status = 'new' and asset_tag = pg_temp.tag('ac') and reporter_id is null and reporter_name = 'الصيانة الدورية MP-0002'
                        and due_at = ((current_date + 4)::timestamp at time zone 'Africa/Tripoli') - interval '1 second' from pg_temp.rq(pg_temp.id('q2'))),
                     'والأسبوعي: جديد غير مُسنَد مربوط بالمكيف، وموعده بعد ثلاثة أيام');
select pg_temp.check((select next_due = current_date + 10 and seq = 1 from pg_temp.pl(pg_temp.id('p2'))), 'الموعد القادم للخطة الأسبوعية يتقدم أسبوعاً');
-- لا تتراكم بلاغات الخطة المفتوحة: عند فتحها يُتخطّى الموعد
select pg_temp.check(public.mt_generate_due(current_date + 60) = '{"created": 0, "skipped": 2}'::jsonb, 'ما دام للخطة بلاغ مفتوح لا يُولَّد آخر (يُتخطّى)');
-- إنجاز الوقائي يغلقه ويسجل آخر تنفيذ
select pg_temp.as_user('k.qa@test.ly');
select public.mt_progress(pg_temp.id('q1'), 'start');
select public.mt_progress(pg_temp.id('q1'), 'done', '{"resolution": "الفحص سليم"}'::jsonb);
select pg_temp.check((select status = 'closed' and closed_at is not null and done_at is not null from pg_temp.rq(pg_temp.id('q1')))
                     and (select last_done = current_date from pg_temp.pl(pg_temp.id('p1'))), 'إنجاز البلاغ الوقائي يغلقه (لا صاحب له) ويسجل آخر تنفيذ للخطة');
-- تعديل الخطة: الجدولة نفسها تُبقي الموعد، وتغييرها يعيد حسابه
select pg_temp.as_user('u.qc@test.ly');
select public.mt_save_plan(pg_temp.id('p3'), jsonb_build_object('title', 'فحص طفايات الحريق السنوي', 'category', 'safety', 'interval_unit', 'year',
  'interval_count', 1, 'start_date', (current_date + 200)::text, 'priority', 'high'));
select pg_temp.check((select title like '%السنوي' and next_due = current_date + 200 and seq = 0 from pg_temp.pl(pg_temp.id('p3'))), 'تعديل الاسم يُبقي الموعد القادم');
select public.mt_save_plan(pg_temp.id('p3'), jsonb_build_object('title', 'فحص طفايات الحريق السنوي', 'category', 'safety', 'interval_unit', 'month',
  'interval_count', 6, 'start_date', (current_date + 20)::text, 'priority', 'high', 'active', false));
select pg_temp.check((select next_due = current_date + 20 and interval_unit = 'month' and interval_count = 6 and not active from pg_temp.pl(pg_temp.id('p3'))), 'تغيير الجدولة يعيد حساب الموعد، وإيقاف الخطة');
select pg_temp.check(public.mt_generate_due(current_date + 15) = '{"created": 0, "skipped": 0}'::jsonb, 'الخطة الموقوفة لا تُولِّد');
select public.mt_delete_plan(pg_temp.id('p2'));
select pg_temp.check((select count(*) = 0 from mt_plans where id = pg_temp.id('p2')) and (select plan_id is null and source = 'plan' from pg_temp.rq(pg_temp.id('q2'))),
                     'حذف الخطة يُبقي بلاغاتها المولَّدة');
select pg_temp.expect_error(format($q$select public.mt_delete_plan(%L)$q$, pg_temp.id('p2')), 'خطة محذوفة');

-- ---------------------------------------------------------------- التنبيهات
select pg_temp.as_user('pending@test.ly');
insert into ids select 'r10', public.mt_report('{"title": "تنظيف السجاد", "category": "cleaning", "priority": "low"}'::jsonb);
insert into ids select 'r11', public.mt_report(jsonb_build_object('title', 'المكيف يصدر ضجيجاً', 'category', 'hvac', 'asset_tag', pg_temp.tag('ac')));
insert into ids select 'r12', public.mt_report(jsonb_build_object('title', 'المكيف يقطّر ماء', 'category', 'hvac', 'asset_tag', pg_temp.tag('ac')));
insert into ids select 'r13', public.mt_report('{"title": "ستارة مكسورة", "category": "furniture"}'::jsonb);
select pg_temp.as_user('u.qc@test.ly');
select public.mt_assign(pg_temp.id('r13'), jsonb_build_object('assignee_id', pg_temp.emp('E-200')));
select pg_temp.as_user('k.qa@test.ly');
select public.mt_progress(pg_temp.id('r13'), 'start');
select public.mt_progress(pg_temp.id('r13'), 'hold', '{"note": "بانتظار قماش"}'::jsonb);
reset role;
-- الأصل ac له الآن ثلاثة بلاغات بلاغية غير مرفوضة (r4 وr11 وr12) خلال 90 يوماً
create or replace function pg_temp.snap(p_who text, p_email text, p_at timestamptz) returns void language plpgsql security definer as $$
begin
  perform set_config('request.jwt.claim.sub', (select id::text from auth.users where email = p_email), false);
  insert into snap select p_who, kind, severity, ref_kind, ref_id, since from public.mt_alerts(p_at);
end $$;
grant execute on function pg_temp.snap(text, text, timestamptz) to authenticated;
-- المدير: البلاغ r2 مُسنَد منذ البداية (مدته 120 ساعة)، وr3 العاجل بمدة 8 ساعات
set role authenticated;
select pg_temp.as_user('u.qc@test.ly');
insert into snap select 'mgr_now', kind, severity, ref_kind, ref_id, since from public.mt_alerts();
insert into snap select 'mgr_9h', kind, severity, ref_kind, ref_id, since from public.mt_alerts(now() + interval '9 hours');
insert into snap select 'mgr_5d', kind, severity, ref_kind, ref_id, since from public.mt_alerts(now() + interval '5 days');
insert into snap select 'mgr_8d', kind, severity, ref_kind, ref_id, since from public.mt_alerts(now() + interval '8 days');
select pg_temp.check(exists (select 1 from snap where who = 'mgr_now' and kind = 'due_soon' and ref_id = pg_temp.id('r3') and severity = 'info'),
                     'تنبيه «قريب الاستحقاق»: بلاغ r3 العاجل موعده خلال 24 ساعة');
select pg_temp.check(exists (select 1 from snap where who = 'mgr_9h' and kind = 'overdue' and ref_id = pg_temp.id('r3') and severity = 'critical')
                     and not exists (select 1 from snap where who = 'mgr_9h' and kind = 'overdue' and ref_id = pg_temp.id('r2')),
                     'تنبيه «متأخر»: العاجل بعد 9 ساعات حرج، والعادي لم يتأخر بعد');
select pg_temp.check(exists (select 1 from snap where who = 'mgr_5d' and kind = 'overdue' and ref_id = pg_temp.id('r2') and severity = 'warning'),
                     'والعادي بعد 5 أيام: تحذير');
select pg_temp.check(exists (select 1 from snap where who = 'mgr_9h' and kind = 'unassigned' and ref_id = pg_temp.id('r10') and severity = 'warning'),
                     'تنبيه «لم يُسنَد»: بلاغ جديد مضى عليه أكثر من 4 ساعات');
select pg_temp.check(not exists (select 1 from snap where who = 'mgr_now' and kind = 'unassigned' and ref_id = pg_temp.id('r10')), 'ولا ينبّه قبل مضي المدة');
select pg_temp.check(not exists (select 1 from snap where kind = 'unassigned' and ref_id = pg_temp.id('r10') and who = 'mgr_8d')
                     or exists (select 1 from snap where kind = 'overdue' and ref_id = pg_temp.id('r10') and who = 'mgr_8d') = false,
                     'غير المُسنَد لا يتكرر مع المتأخر نفسه');
select pg_temp.check(exists (select 1 from snap where who = 'mgr_8d' and kind = 'on_hold' and ref_id = pg_temp.id('r13') and severity = 'warning')
                     and not exists (select 1 from snap where who = 'mgr_5d' and kind = 'on_hold'), 'تنبيه «معلّق طويلاً» بعد 7 أيام، ولا يُحتسب المعلّق متأخراً');
select pg_temp.check(not exists (select 1 from snap where kind = 'overdue' and ref_id = pg_temp.id('r13')), 'المعلّق لا يتأخر');
select pg_temp.check(exists (select 1 from snap where who = 'mgr_5d' and kind = 'awaiting_confirm' and ref_id = pg_temp.id('r9') and severity = 'info')
                     and not exists (select 1 from snap where who = 'mgr_now' and kind = 'awaiting_confirm'), 'تنبيه «ينتظر التأكيد»: بلاغ r9 المنجز بعد 3 أيام');
select pg_temp.check(exists (select 1 from snap where who = 'mgr_now' and kind = 'warranty' and ref_id = pg_temp.id('r11') and severity = 'info')
                     and not exists (select 1 from snap where kind = 'warranty' and ref_id = pg_temp.id('r4')), 'تنبيه «تحت الضمان»: لبلاغ مفتوح على المكيف دون المغلق');
select pg_temp.check((select count(*) = 1 from snap where who = 'mgr_now' and kind = 'repeat' and ref_kind = 'asset'
                        and ref_id = (select id from pg_temp.asset(pg_temp.tag('ac')) a)), 'تنبيه «تكرار الأعطال»: ثلاثة بلاغات على المكيف خلال 90 يوماً');
select pg_temp.check(not exists (select 1 from snap where who = 'mgr_now' and ref_id = pg_temp.id('r1') or ref_id = pg_temp.id('r6') or ref_id = pg_temp.id('r7')),
                     'المغلق والمرفوض والملغى بلا تنبيه');
select pg_temp.as_user('k.qa@test.ly');
insert into snap select 'tech_8d', kind, severity, ref_kind, ref_id, since from public.mt_alerts(now() + interval '8 days');
select pg_temp.as_user('u.safetyhead@test.ly');
insert into snap select 'aud_8d', kind, severity, ref_kind, ref_id, since from public.mt_alerts(now() + interval '8 days');
select pg_temp.as_user('pending@test.ly');
insert into snap select 'rep_8d', kind, severity, ref_kind, ref_id, since from public.mt_alerts(now() + interval '8 days');
select pg_temp.as_user('u.safety@test.ly');
insert into snap select 'oth_8d', kind, severity, ref_kind, ref_id, since from public.mt_alerts(now() + interval '8 days');
reset role;
select pg_temp.check((select count(*) = 0 from snap where who in ('rep_8d', 'oth_8d')), 'من ليس من أهل القسم لا تنبيهات له');
select pg_temp.check((select count(*) > 0 and count(*) = (select count(*) from snap where who = 'mgr_8d') from snap where who = 'aud_8d'), 'المراجع يرى تنبيهات المدير كلها');
select pg_temp.check((select count(*) > 0 and bool_and(s.ref_kind = 'request' and r.assignee_id = pg_temp.emp('E-200')) from snap s join mt_requests r on r.id = s.ref_id where s.who = 'tech_8d')
                     and (select count(*) < (select count(*) from snap where who = 'mgr_8d') from snap where who = 'tech_8d'),
                     'الفني يرى تنبيهات بلاغاته المسنَدة وحدها، لا تنبيهات الأصول');
set role authenticated;

-- ---------------------------------------------------------------- الإعدادات
select pg_temp.as_user('u.qc@test.ly');
select pg_temp.expect_error($q$select public.mt_save_settings('{"hold_days": 10}'::jsonb)$q$, 'الإعدادات لمدير النظام أو المدير');
select pg_temp.as_user('u.heritage@test.ly');
select pg_temp.expect_error($q$select public.mt_save_settings('{"sla_hours": {"urgent": 50, "high": 24, "normal": 72, "low": 120}}'::jsonb)$q$, 'العاجل لا يزيد على العالي');
select pg_temp.expect_error($q$select public.mt_save_settings('{"sla_hours": {"urgent": 4, "high": 24, "normal": 72}}'::jsonb)$q$, 'أربع أولويات مطلوبة');
select pg_temp.expect_error($q$select public.mt_save_settings('{"sla_hours": {"urgent": 0, "high": 24, "normal": 72, "low": 120}}'::jsonb)$q$, 'مدة الإنجاز من ساعة');
select pg_temp.expect_error($q$select public.mt_save_settings('{"hold_days": 0}'::jsonb)$q$, 'المدة بالأيام من 1');
select pg_temp.expect_error($q$select public.mt_save_settings('{"repeat_count": 1}'::jsonb)$q$, 'التكرار يبدأ من بلاغين');
select pg_temp.expect_error($q$select public.mt_save_settings('{"plan_lead_days": 120}'::jsonb)$q$, 'التنبيه المسبق حتى 90');
select pg_temp.expect_error($q$select public.mt_save_settings('{"hold_days": 2.5}'::jsonb)$q$, 'عدد صحيح');
select pg_temp.expect_error($q$select public.mt_save_settings('{"magic": 1}'::jsonb)$q$, 'إعداد غير معروف');
select public.mt_save_settings('{"sla_hours": {"urgent": 4, "high": 24, "normal": 72, "low": 120}, "hold_days": 10}'::jsonb);
select pg_temp.check((select (value ->> 'normal')::int = 72 from mt_settings where key = 'sla_hours') and (select value = '10'::jsonb from mt_settings where key = 'hold_days'),
                     'مدير النظام يعدّل مدد الإنجاز وحد التعليق');
select pg_temp.as_user('pending@test.ly');
insert into ids select 'r14', public.mt_report('{"title": "بلاغ بالمدة الجديدة", "category": "civil"}'::jsonb);
select pg_temp.check((select pg_temp.near(due_at, reported_at, 72) from pg_temp.rq(pg_temp.id('r14'))), 'البلاغ الجديد يأخذ مدة الإنجاز المعدَّلة');
select pg_temp.as_user('u.heritage@test.ly');
select public.mt_save_settings('{"sla_hours": {"urgent": 8, "high": 48, "normal": 120, "low": 240}, "hold_days": 7}'::jsonb);
select pg_temp.check((select (value ->> 'normal')::int = 120 from mt_settings where key = 'sla_hours'), 'وتُعاد القيم المبدئية');

-- ---------------------------------------------------------------- إيقاف الفني
select pg_temp.expect_error($q$select public.mt_save_technician(pg_temp.emp('E-200'), '{"trade": "electrical", "active": false}'::jsonb)$q$, 'لا يُوقَف فني له بلاغات مفتوحة');

-- ---------------------------------------------------------------- لا كتابة مباشرة، وسجل الأحداث لا يُعدَّل
select pg_temp.as_user('pending@test.ly');
select pg_temp.expect_error($q$insert into mt_requests (req_no, title, due_at) values ('MR-X', 'بلاغ مباشر', now())$q$, 'لا إدراج مباشر في البلاغات');
select pg_temp.expect_error(format($q$update mt_requests set status = 'closed' where id = %L$q$, pg_temp.id('r14')), 'لا تحديث مباشر للبلاغات');
select pg_temp.expect_error($q$delete from mt_request_events$q$, 'لا حذف من سجل الأحداث');
select pg_temp.as_user('u.qc@test.ly');
select pg_temp.expect_error($q$update mt_plans set active = false$q$, 'ولا لمدير الصيانة مباشرة في الخطط');
select pg_temp.expect_error($q$update mt_request_events set note = 'x'$q$, 'سجل الأحداث لا يُعدَّل');

-- ---------------------------------------------------------------- التجميد الطارئ
reset role;
update app_settings set value = 'true' where key = 'security.freeze';
set role authenticated;
select pg_temp.as_user('pending@test.ly');
select pg_temp.expect_error($q$select public.mt_report('{"title": "بلاغ وقت التجميد"}'::jsonb)$q$, 'لا رفع بلاغات في وضع القراءة فقط');
select pg_temp.expect_error(format($q$select public.mt_cancel(%L)$q$, pg_temp.id('r14')), 'ولا إلغاء');
select pg_temp.as_user('u.qc@test.ly');
select pg_temp.expect_error(format($q$select public.mt_assign(%L, jsonb_build_object('assignee_id', %L))$q$, pg_temp.id('r14'), pg_temp.emp('E-200')), 'ولا إسناد');
select pg_temp.expect_error($q$select public.mt_generate_due()$q$, 'ولا توليد');
select pg_temp.as_user('director.new@test.ly', 'aal2');
select public.mt_assign(pg_temp.id('r14'), jsonb_build_object('assignee_id', pg_temp.emp('E-200')));
select pg_temp.check((select status = 'assigned' from pg_temp.rq(pg_temp.id('r14'))), 'المدير وحده يعمل في وضع القراءة فقط');
reset role;
update app_settings set value = 'false' where key = 'security.freeze';

-- ---------------------------------------------------------------- سلامة البيانات وسجل التدقيق
select pg_temp.check((select count(*) = 0 from mt_requests r join st_assets a on a.id = r.asset_id where r.asset_held and a.status <> 'maintenance'),
                     'كل بلاغ يحجز أصلاً فأصله «تحت الصيانة»');
select pg_temp.check((select count(*) = 0 from mt_requests where asset_held and status not in ('in_progress', 'on_hold')), 'ولا يحجز الأصل إلا بلاغ قيد التنفيذ أو معلّق');
select pg_temp.check((select count(*) = 0 from mt_requests where status in ('assigned', 'in_progress', 'on_hold', 'done', 'closed') and assignee_id is null and vendor = ''),
                     'كل بلاغ بعد الإسناد له فني أو جهة');
select pg_temp.check((select count(*) = 0 from mt_requests where status = 'closed' and (done_at is null or closed_at is null)), 'كل بلاغ مغلق له وقت إنجاز وإغلاق');
select pg_temp.check((select count(distinct action) = 15 from audit_log where action in ('maintenance.report', 'maintenance.assign', 'maintenance.start',
                        'maintenance.hold', 'maintenance.resume', 'maintenance.done', 'maintenance.close', 'maintenance.reopen', 'maintenance.reject',
                        'maintenance.cancel', 'maintenance.plan', 'maintenance.plan_delete', 'maintenance.generate', 'maintenance.settings',
                        'maintenance.technician')), 'إجراءات الصيانة الخمسة عشر في سجل التدقيق');
select pg_temp.check((select count(*) filter (where source = 'report') = 14 and count(*) filter (where source = 'plan') = 2 from mt_requests),
                     'عدد البلاغات: أربعة عشر مرفوعاً وبلاغان وقائيان مولَّدان');
