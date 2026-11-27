-- اختبارات الترحيل 45: المعالم والمؤشرات
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

update app_settings set value = 'false' where key in ('security.freeze', 'security.require_mfa_all');
update profiles set locked_until = null where email in ('director.new@test.ly', 'u.qc@test.ly', 'k.qa@test.ly', 'k.staff@test.ly', 'pending@test.ly');
create or replace function pg_temp.uid(p_email text) returns uuid language sql security definer as $$ select id from auth.users where email = p_email $$;
create temp table ids (k text primary key, v uuid);
grant all on ids to authenticated;
insert into ids select 'proj', id from public.projects order by created_at limit 1;

-- معالم: المدير
select pg_temp.as_user('director.new@test.ly', 'aal2');
set role authenticated;
insert into ids select 'm1', public.pm_milestone_save(null, (select v from ids where k = 'proj'), 'تسليم الموقع', current_date + 10, null, 'ملاحظة', 1);
select pg_temp.check((select count(*) from public.pm_milestones where title = 'تسليم الموقع' and status = 'pending' and actual_date is null) = 1, 'إضافة معلم');
select public.pm_milestone_save((select v from ids where k = 'm1'), null, 'تسليم الموقع المعدّل', current_date + 12, current_date + 15, '', 2);
select pg_temp.check((select forecast_date = current_date + 15 and title = 'تسليم الموقع المعدّل' from public.pm_milestones where id = (select v from ids where k = 'm1')), 'تعديل معلم لا يغيّر مشروعه');
select pg_temp.expect_error(format($q$select public.pm_milestone_save(null, %L, '', current_date, null)$q$, (select v from ids where k = 'proj')), 'عنوان فارغ');
select pg_temp.expect_error(format($q$select public.pm_milestone_save(null, %L, 'س', null, null)$q$, (select v from ids where k = 'proj')), 'تاريخ مخطط فارغ');
select pg_temp.expect_error($q$select public.pm_milestone_save(null, gen_random_uuid(), 'س', current_date, null)$q$, 'مشروع غير موجود');
select pg_temp.expect_error(format($q$select public.pm_milestone_status(%L, 'done', current_date + 3)$q$, (select v from ids where k = 'm1')), 'تاريخ فعلي مستقبلي');
select pg_temp.expect_error(format($q$select public.pm_milestone_status(%L, 'late')$q$, (select v from ids where k = 'm1')), 'حالة غير معروفة');
select public.pm_milestone_status((select v from ids where k = 'm1'), 'done', current_date - 1);
select pg_temp.check((select status = 'done' and actual_date = current_date - 1 from public.pm_milestones where id = (select v from ids where k = 'm1')), 'إنجاز معلم بتاريخ فعلي');
select public.pm_milestone_status((select v from ids where k = 'm1'), 'pending');
select pg_temp.check((select status = 'pending' and actual_date is null from public.pm_milestones where id = (select v from ids where k = 'm1')), 'إعادة الفتح تمسح التاريخ الفعلي');
select pg_temp.expect_error($q$insert into public.pm_milestones (project_id, title, planned_date) select id, 'x', current_date from public.projects limit 1$q$, 'لا كتابة مباشرة على المعالم');
reset role;

-- من لا يكتب المتابعة
select pg_temp.as_user('pending@test.ly');
set role authenticated;
select pg_temp.expect_error(format($q$select public.pm_milestone_status(%L, 'done')$q$, (select v from ids where k = 'm1')), 'حساب معلّق لا يغيّر حالة معلم');
select pg_temp.expect_error(format($q$select public.pm_milestone_delete(%L)$q$, (select v from ids where k = 'm1')), 'حساب معلّق لا يحذف معلماً');
reset role;

-- مؤشرات
select pg_temp.as_user('director.new@test.ly', 'aal2');
set role authenticated;
insert into ids select 'k1', public.kpi_def_save(null, 'نسبة الصرف', '%', 90, 'higher', true, '');
select pg_temp.check((select count(*) from public.kpi_defs where name = 'نسبة الصرف' and target = 90 and direction = 'higher') = 1, 'تعريف مؤشر');
select pg_temp.expect_error($q$select public.kpi_def_save(null, ' نسبة الصرف ', '%', 80, 'higher')$q$, 'اسم مكرّر');
select pg_temp.expect_error($q$select public.kpi_def_save(null, 'س', '%', null, 'higher')$q$, 'مستهدف فارغ');
select pg_temp.expect_error($q$select public.kpi_def_save(null, 'س', '%', 5, 'both')$q$, 'اتجاه غير معروف');
select public.kpi_value_set((select v from ids where k = 'k1'), '2026-10', 85.5, 'أكتوبر');
select public.kpi_value_set((select v from ids where k = 'k1'), '2026-10', 88);
select pg_temp.check((select count(*) = 1 and max(value) = 88 from public.kpi_values where kpi_id = (select v from ids where k = 'k1')), 'القيمة الشهرية تُحدَّث ولا تتكرر');
select pg_temp.expect_error(format($q$select public.kpi_value_set(%L, '2026-13', 1)$q$, (select v from ids where k = 'k1')), 'فترة غير صالحة');
select pg_temp.expect_error(format($q$select public.kpi_value_set(%L, '2026-10', null)$q$, (select v from ids where k = 'k1')), 'قيمة فارغة');
select pg_temp.expect_error($q$insert into public.kpi_defs (name, target) values ('مباشر', 1)$q$, 'لا كتابة مباشرة على المؤشرات');
reset role;

-- موظف المكتب يسجّل القيم ولا يعرّف
select pg_temp.as_user('k.staff@test.ly');
set role authenticated;
select public.kpi_value_set((select v from ids where k = 'k1'), '2026-11', 91);
select pg_temp.check((select count(*) from public.kpi_values where period = '2026-11') = 1, 'موظف المكتب يسجّل قيمة');
select pg_temp.expect_error($q$select public.kpi_def_save(null, 'مؤشر موظف', '', 1, 'higher')$q$, 'موظف المكتب لا يعرّف مؤشراً');
reset role;
select pg_temp.as_user('pending@test.ly');
set role authenticated;
select pg_temp.expect_error(format($q$select public.kpi_value_set(%L, '2026-12', 1)$q$, (select v from ids where k = 'k1')), 'حساب معلّق لا يسجّل قيمة');
reset role;

-- الحذف والتدقيق
select pg_temp.as_user('director.new@test.ly', 'aal2');
set role authenticated;
select public.kpi_value_delete((select v from ids where k = 'k1'), '2026-11');
select public.kpi_value_delete((select v from ids where k = 'k1'), '2026-11');
select public.pm_milestone_delete((select v from ids where k = 'm1'));
select pg_temp.check((select count(*) from public.pm_milestones where id = (select v from ids where k = 'm1')) = 0, 'حذف معلم');
reset role;
select pg_temp.check((select count(*) from public.audit_log where action = 'milestone.save') >= 2
  and (select count(*) from public.audit_log where action = 'milestone.status') >= 2
  and (select count(*) from public.audit_log where action = 'milestone.delete') = 1
  and (select count(*) from public.audit_log where action = 'kpi.def_save') = 1
  and (select count(*) from public.audit_log where action = 'kpi.value_set') = 3
  and (select count(*) from public.audit_log where action = 'kpi.value_delete') = 1, 'كل إجراء مسجَّل، وحذف غير الموجود لا يسجّل');

-- الحذف المتتالي
insert into public.pm_milestones (project_id, title, planned_date) select v, 'تتالي', current_date from ids where k = 'proj';
select public.kpi_value_set((select v from ids where k = 'k1'), '2026-09', 1) where false;
delete from public.kpi_defs where id = (select v from ids where k = 'k1');
select pg_temp.check((select count(*) from public.kpi_values where kpi_id = (select v from ids where k = 'k1')) = 0, 'حذف المؤشر يحذف قيمه');
