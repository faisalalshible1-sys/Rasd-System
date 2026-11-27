-- =====================================================================
-- التراجع عن الترحيل 40 (قسم الصيانة: البلاغات والصيانة الدورية والتنبيهات)
--
-- يُرفض إن كان في القسم أي بلاغ أو خطة أو فني، أو عُدّلت إعداداته المبدئية، أو مُنحت أي صلاحية maintenance:*.
-- عندها تبقى المنظومة كما هي. يعيد تعريف دوال الترحيل 38 و39 المعدَّلة (my_sections وapp_section_ok وgrant_scope_ok)
-- وقيد نطاقات الصلاحيات كما كانت حرفياً، ثم يحذف جداول الصيانة ودوالها. لا يمس المخازن والأصول.
-- =====================================================================
do $$
declare
  v_bad text := '';
begin
  if to_regclass('public.mt_requests') is null then
    return;
  end if;
  if exists (select 1 from public.mt_requests) then v_bad := v_bad || ' بلاغات'; end if;
  if exists (select 1 from public.mt_plans) then v_bad := v_bad || ' خطط دورية'; end if;
  if exists (select 1 from public.mt_technicians) then v_bad := v_bad || ' فنيون'; end if;
  if exists (select 1 from public.mt_settings where updated_by is not null) then v_bad := v_bad || ' إعدادات معدّلة'; end if;
  if exists (select 1 from public.user_grants where scope like 'maintenance:%') then v_bad := v_bad || ' صلاحيات الصيانة'; end if;
  if v_bad <> '' then
    raise exception 'لا يُتراجع عن الترحيل 40: في قسم الصيانة بيانات (%). المنظومة كما هي.', btrim(v_bad);
  end if;
end $$;

-- قيد نطاقات الصلاحيات كما كان بعد الترحيل 39
alter table public.user_grants drop constraint if exists user_grants_scope_check;
alter table public.user_grants add constraint user_grants_scope_check check (
  scope ~ '^(form:[a-z0-9_]{1,40}|docs:(boq|letter|design|pm_view|pm_add|pm_duration|pm_dates|pm_approve)|supervision:reports|unit:[a-z_]{2,40}|swot|pm:(plan|track)|stores:(admin|manager|audit|assets)|stores:keeper:[0-9a-f-]{36})$');

-- دوال الترحيلين 38 و39 المعدَّلة كما كانت
CREATE OR REPLACE FUNCTION public.my_sections()
 RETURNS text[]
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  r  text := coalesce(public.my_role()::text, '');
  me public.profiles;
  s  text[] := '{}';
  g  text;
begin
  if r = '' then
    return '{}';
  end if;
  if r = 'employee' then
    return array['manual', 'stores'];
  end if;
  select * into me from public.profiles where id = auth.uid();
  if r in ('director', 'office_staff') then
    s := array['cycle', 'risks', 'swot', 'docs', 'supervision', 'heritage', 'planning_qa', 'safety', 'acceptance'];
    if r = 'director' then
      s := s || 'stores'::text;
    end if;
  elsif r = 'contracts' then
    s := array['cycle'];
  elsif r = 'planning_qa' then
    s := array['planning_qa'];
  elsif r = 'dept_head' then
    s := case me.department
           when 'technical'   then array['docs']
           when 'supervision' then array['supervision']
           when 'restoration' then array['heritage', 'supervision']
           when 'acceptance'  then array['acceptance']
           else '{}'::text[]
         end;
  end if;
  if r <> 'security_auditor' then
    s := s || array(select public.unit_app_section(x) from unnest(public.my_units()) x);
    for g in select scope from public.user_grants where user_id = me.id loop
      s := s || case
                  when g like 'docs:%' or g = 'pm:plan' then 'docs'
                  when g in ('supervision:reports', 'pm:track') then 'supervision'
                  when g = 'swot' then 'swot'
                  when g like 'stores:%' then 'stores'
                  else null
                end;
    end loop;
  end if;
  if public.can_audit() then
    s := s || 'security'::text;
  end if;
  s := s || array['chat', 'manual', 'print'];
  return array(select distinct x from unnest(s) x where x is not null order by x);
end;
$function$;

CREATE OR REPLACE FUNCTION public.app_section_ok(p_key text)
 RETURNS boolean
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public'
AS $function$
  select p_key in ('cycle', 'risks', 'swot', 'docs', 'supervision', 'heritage', 'planning_qa', 'safety', 'acceptance',
                   'chat', 'security', 'print', 'manual', 'stores')
$function$;

CREATE OR REPLACE FUNCTION public.grant_scope_ok(p_scope text)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select case
    when p_scope like 'form:%' then exists (select 1 from public.form_defs where key = substr(p_scope, 6))
    when p_scope like 'unit:%' then public.unit_kind_spec(substr(p_scope, 6)) is not null
    when p_scope like 'stores:keeper:%' then
      substr(p_scope, 15) ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
      and exists (select 1 from public.st_warehouses w where w.id::text = substr(p_scope, 15))
    else p_scope in ('docs:boq', 'docs:letter', 'docs:design', 'supervision:reports', 'swot', 'pm:plan', 'pm:track',
                     'docs:pm_view', 'docs:pm_add', 'docs:pm_duration', 'docs:pm_dates', 'docs:pm_approve',
                     'stores:admin', 'stores:manager', 'stores:audit', 'stores:assets')
  end
$function$;

-- الجداول أولاً (سياساتها تعتمد على الدوال)
drop table if exists public.mt_request_events;
drop table if exists public.mt_requests;
drop table if exists public.mt_plans;
drop table if exists public.mt_technicians;
drop table if exists public.mt_settings;

drop function if exists public.mt_alerts(timestamptz);
drop function if exists public.mt_lookups();
drop function if exists public.mt_save_technician(uuid, jsonb);
drop function if exists public.mt_save_settings(jsonb);
drop function if exists public.mt_generate_due(date);
drop function if exists public.mt_delete_plan(uuid);
drop function if exists public.mt_save_plan(uuid, jsonb);
drop function if exists public.mt_comment(uuid, text);
drop function if exists public.mt_cancel(uuid, text);
drop function if exists public.mt_reject(uuid, text);
drop function if exists public.mt_confirm(uuid, boolean, text, integer);
drop function if exists public.mt_progress(uuid, text, jsonb);
drop function if exists public.mt_assign(uuid, jsonb);
drop function if exists public.mt_report(jsonb);
drop function if exists public.mt_valid_category(text);
drop function if exists public.mt_resolve_asset(jsonb, boolean);
drop function if exists public.mt_release_asset(uuid);
drop function if exists public.mt_hold_asset(uuid);
drop function if exists public.mt_notify_managers(text, text);
drop function if exists public.mt_event(uuid, text, jsonb, text);
drop function if exists public.mt_occurrence(date, text, integer, integer);
drop function if exists public.mt_end_of_day(date);
drop function if exists public.mt_sla_hours(text);
drop function if exists public.mt_setting_num(text, numeric);
drop function if exists public.mt_is_assignee(uuid);
drop function if exists public.mt_can_report();
drop function if exists public.mt_me_ok();
drop function if exists public.mt_can_admin();
drop function if exists public.mt_can_manage();
drop function if exists public.mt_staff();
drop function if exists public.mt_sees_all();
