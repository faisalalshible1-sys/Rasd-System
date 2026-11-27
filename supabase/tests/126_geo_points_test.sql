-- اختبارات الترحيل 44: مواقع المشاريع وبلاغات الصيانة (الحفظ والتحديث والمسح والصلاحية والتدقيق والحذف المتتالي)
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
insert into public.mt_requests (req_no, title, priority, status, due_at) values ('MT-GEO-1', 'بلاغ موقع', 'normal', 'new', now() + interval '3 days');
insert into ids select 'req', id from public.mt_requests where req_no = 'MT-GEO-1';

-- مشروع: مدير المكتب
select pg_temp.as_user('director.new@test.ly', 'aal2');
set role authenticated;
select public.geo_set('project', (select v from ids where k = 'proj'), 32.1167, 20.0667, 'مدخل الموقع');
select pg_temp.check((select count(*) from public.geo_points where project_id = (select v from ids where k = 'proj') and lat = 32.1167 and lng = 20.0667 and note = 'مدخل الموقع') = 1, 'حفظ موقع مشروع');
select public.geo_set('project', (select v from ids where k = 'proj'), 32.12, 20.07);
select pg_temp.check((select count(*) from public.geo_points where project_id = (select v from ids where k = 'proj')) = 1
                     and (select lat from public.geo_points where project_id = (select v from ids where k = 'proj')) = 32.12, 'التعديل يحدّث النقطة ولا يكرّرها');
select pg_temp.expect_error(format($q$select public.geo_set('project', %L, 91, 20)$q$, (select v from ids where k = 'proj')), 'عرض خارج النطاق');
select pg_temp.expect_error(format($q$select public.geo_set('project', %L, 32, 181)$q$, (select v from ids where k = 'proj')), 'طول خارج النطاق');
select pg_temp.expect_error(format($q$select public.geo_set('project', %L, null, 20)$q$, (select v from ids where k = 'proj')), 'إحداثي فارغ');
select pg_temp.expect_error($q$select public.geo_set('project', gen_random_uuid(), 32, 20)$q$, 'مشروع غير موجود');
select pg_temp.expect_error(format($q$select public.geo_set('building', %L, 32, 20)$q$, (select v from ids where k = 'proj')), 'نوع غير معروف');
select pg_temp.expect_error($q$insert into public.geo_points (project_id, lat, lng) select id, 1, 1 from public.projects limit 1$q$, 'لا كتابة مباشرة');
-- بلاغ: المدير
select public.geo_set('request', (select v from ids where k = 'req'), 32.11, 20.06);
select pg_temp.check((select count(*) from public.geo_points where request_id = (select v from ids where k = 'req')) = 1, 'حفظ موقع بلاغ');
reset role;

-- مدير الصيانة يكتب موقع البلاغ لا المشروع
select pg_temp.as_user('director.new@test.ly', 'aal2');
set role authenticated;
select public.set_user_grants(pg_temp.uid('u.qc@test.ly'), array['stores:manager', 'maintenance:manager']);
reset role;
select pg_temp.as_user('u.qc@test.ly');
set role authenticated;
select public.geo_set('request', (select v from ids where k = 'req'), 32.115, 20.065, 'عند البوابة');
select pg_temp.check((select note from public.geo_points where request_id = (select v from ids where k = 'req')) = 'عند البوابة', 'مدير الصيانة يحدّد موقع البلاغ');
select pg_temp.expect_error(format($q$select public.geo_set('project', %L, 32, 20)$q$, (select v from ids where k = 'proj')), 'مدير الصيانة لا يحدّد موقع مشروع');
reset role;

-- من لا صلاحية له
select pg_temp.as_user('pending@test.ly');
set role authenticated;
select pg_temp.expect_error(format($q$select public.geo_set('request', %L, 32, 20)$q$, (select v from ids where k = 'req')), 'حساب معلّق لا يحدّد موقع بلاغ');
select pg_temp.expect_error(format($q$select public.geo_clear('request', %L)$q$, (select v from ids where k = 'req')), 'حساب معلّق لا يمسح موقعاً');
reset role;
select pg_temp.as_user('k.qa@test.ly');
set role authenticated;
select pg_temp.expect_error(format($q$select public.geo_set('request', %L, 32, 20)$q$, (select v from ids where k = 'req')), 'فني ليس مديراً ولا مقدّماً للبلاغ');
reset role;

-- المسح والتدقيق
select pg_temp.as_user('director.new@test.ly', 'aal2');
set role authenticated;
select public.geo_clear('request', (select v from ids where k = 'req'));
select pg_temp.check((select count(*) from public.geo_points where request_id = (select v from ids where k = 'req')) = 0, 'مسح موقع البلاغ');
select public.geo_clear('request', (select v from ids where k = 'req'));
reset role;
select pg_temp.check((select count(*) from public.audit_log where action = 'geo.set') >= 4 and (select count(*) from public.audit_log where action = 'geo.clear') = 1,
  'الحفظ والمسح مسجَّلان، ومسح غير الموجود لا يسجّل');

-- الحذف المتتالي
insert into public.geo_points (request_id, lat, lng) select v, 1, 1 from ids where k = 'req';
delete from public.mt_requests where id = (select v from ids where k = 'req');
select pg_temp.check((select count(*) from public.geo_points where request_id is not null) = 0, 'حذف البلاغ يحذف موقعه');
