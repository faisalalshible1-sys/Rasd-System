-- =====================================================================
-- التراجع عن الترحيل 38 (قسم المخازن: الأساس والمخزون)
--
-- يُرفض إن كان في القسم أي بيانات أُدخلت بعد الترحيل (إدارات، موظفون، مواقع، مخازن، أصناف، مستندات، أرصدة، أو تعديل
-- على التصنيفات والوحدات والإعدادات المبدئية)، أو صلاحيات stores:*، أو حساب بدور «موظف». عندها تبقى المنظومة كما هي.
-- يعيد تعريف الدوال المعدَّلة كما كانت حرفياً، وقيد نطاقات الصلاحيات، ثم يحذف جداول القسم ودواله.
-- قيمة الدور employee تبقى في نوع app_role (PostgreSQL لا يحذف قيم الأنواع) دون أي حساب بها، فلا أثر لها.
-- =====================================================================
do $$
declare
  v_bad text := '';
begin
  if to_regclass('public.st_docs') is null then
    return;
  end if;
  if exists (select 1 from public.st_departments) then v_bad := v_bad || ' إدارات'; end if;
  if exists (select 1 from public.st_employees) then v_bad := v_bad || ' موظفون'; end if;
  if exists (select 1 from public.st_locations) then v_bad := v_bad || ' مواقع'; end if;
  if exists (select 1 from public.st_warehouses) then v_bad := v_bad || ' مخازن'; end if;
  if exists (select 1 from public.st_items) then v_bad := v_bad || ' أصناف'; end if;
  if exists (select 1 from public.st_docs) or exists (select 1 from public.st_stock) or exists (select 1 from public.st_moves) then
    v_bad := v_bad || ' مستندات وأرصدة';
  end if;
  if exists (select 1 from public.st_categories where created_by is not null or updated_by is not null)
     or (select count(*) from public.st_categories) <> 8 then
    v_bad := v_bad || ' تصنيفات معدّلة';
  end if;
  if exists (select 1 from public.st_units where created_by is not null or updated_by is not null)
     or (select count(*) from public.st_units) <> 7 then
    v_bad := v_bad || ' وحدات معدّلة';
  end if;
  if exists (select 1 from public.st_settings where updated_by is not null) then v_bad := v_bad || ' إعدادات معدّلة'; end if;
  if exists (select 1 from public.user_grants where scope like 'stores:%') then v_bad := v_bad || ' صلاحيات المخازن'; end if;
  if exists (select 1 from public.profiles where role::text = 'employee') then v_bad := v_bad || ' حسابات بدور موظف'; end if;
  if v_bad <> '' then
    raise exception 'لا يُتراجع عن الترحيل 38: في قسم المخازن بيانات (%). المنظومة كما هي.', btrim(v_bad);
  end if;
end $$;

-- الدوال المعدَّلة كما كانت قبل الترحيل
CREATE OR REPLACE FUNCTION public.is_member()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select exists (select 1 from public.profiles
                  where id = auth.uid() and active and role is not null
                    and (locked_until is null or locked_until <= now()))
     and public.mfa_ok()
$function$
;

CREATE OR REPLACE FUNCTION public.has_grant(p_scope text)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select exists (select 1 from public.user_grants g join public.profiles me on me.id = g.user_id
                  where g.user_id = auth.uid() and g.scope = p_scope and me.active and me.role is not null
                    and me.role::text <> 'security_auditor'
                    and (me.locked_until is null or me.locked_until <= now()))
$function$
;

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
  select * into me from public.profiles where id = auth.uid();
  if r in ('director', 'office_staff') then
    s := array['cycle', 'risks', 'swot', 'docs', 'supervision', 'heritage', 'planning_qa', 'safety', 'acceptance'];
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
$function$
;

CREATE OR REPLACE FUNCTION public.my_units()
 RETURNS text[]
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  r  text := coalesce(public.my_role()::text, '');
  me public.profiles;
  u  text[] := '{}';
begin
  if r in ('', 'security_auditor') then
    return '{}';
  end if;
  if r in ('director', 'office_staff') then
    return array(select key from public.org_units order by key);
  end if;
  select * into me from public.profiles where id = auth.uid();
  if me.unit is not null then
    u := u || me.unit;
  end if;
  if r = 'dept_head' then
    u := u || array(select key from public.org_units
                     where section = case me.department when 'restoration' then 'heritage' when 'acceptance' then 'acceptance'
                                                        when 'technical' then 'technical' else '-' end);
  elsif r = 'planning_qa' then
    u := u || array(select key from public.org_units where section = 'planning_qa');
  end if;
  u := u || array(select public.unit_kind_spec(substr(g.scope, 6)) ->> 'unit'
                    from public.user_grants g where g.user_id = me.id and g.scope like 'unit:%');
  return array(select distinct x from unnest(u) x where x is not null order by x);
end;
$function$
;

CREATE OR REPLACE FUNCTION public.my_forms()
 RETURNS text[]
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select coalesce(array_agg(d.key order by d.sort), '{}'::text[])
    from public.form_defs d
    cross join (select coalesce(public.my_role()::text, '') as role) r
    join public.profiles me on me.id = auth.uid()
   where r.role not in ('', 'security_auditor') and (
         r.role in ('director', 'office_staff')
      or (r.role = 'contracts' and 'contracts' = any (d.responsible))
      or (r.role = 'planning_qa' and 'planning_qa' = any (d.responsible))
      or (r.role = 'dept_head' and me.department = 'technical' and 'head:technical' = any (d.responsible))
      or (r.role = 'dept_head' and me.department = 'acceptance' and 'head:acceptance' = any (d.responsible))
      or exists (select 1 from public.user_grants g where g.user_id = me.id and g.scope = 'form:' || d.key))
$function$
;

CREATE OR REPLACE FUNCTION public.set_user_grants(p_user uuid, p_scopes text[])
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  u       public.profiles;
  v_new   text[] := array(select distinct btrim(x) from unnest(coalesce(p_scopes, '{}'::text[])) x where btrim(x) <> '' order by 1);
  v_old   text[];
  v_bad   text;
begin
  if not public.is_director() then
    raise exception 'منح الصلاحيات من صلاحية مدير المكتب وحده' using errcode = '42501';
  end if;
  if not public.writes_allowed() then
    raise exception 'المنظومة في وضع القراءة فقط' using errcode = '42501';
  end if;
  select * into u from public.profiles where id = p_user;
  if not found then
    raise exception 'المستخدم غير موجود' using errcode = 'P0002';
  end if;
  if u.role::text in ('director', 'security_auditor') then
    raise exception 'لا تُمنح صلاحيات دقيقة للمدير أو لمسؤول الأمن' using errcode = '22023';
  end if;
  if coalesce(array_length(v_new, 1), 0) > 80 then
    raise exception 'الحد الأعلى 80 صلاحية دقيقة للمستخدم' using errcode = '22023';
  end if;
  select x into v_bad from unnest(v_new) x where not public.grant_scope_ok(x) limit 1;
  if v_bad is not null then
    raise exception 'نطاق غير معروف: %', v_bad using errcode = '22023';
  end if;
  select coalesce(array_agg(scope order by scope), '{}') into v_old from public.user_grants where user_id = p_user;
  if v_old = v_new then
    return;
  end if;
  delete from public.user_grants where user_id = p_user and not (scope = any (v_new));
  insert into public.user_grants (user_id, scope, granted_by)
  select p_user, x, auth.uid() from unnest(v_new) x
  on conflict (user_id, scope) do nothing;
  perform public.write_audit('user.grants', null, null,
    jsonb_build_object('user_id', p_user, 'name', u.full_name,
                       'added', to_jsonb(array(select x from unnest(v_new) x where not (x = any (v_old)))),
                       'removed', to_jsonb(array(select x from unnest(v_old) x where not (x = any (v_new))))),
    coalesce(u.full_name, 'مستخدم'));
end;
$function$
;

CREATE OR REPLACE FUNCTION public.grant_scope_ok(p_scope text)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select case
    when p_scope like 'form:%' then exists (select 1 from public.form_defs where key = substr(p_scope, 6))
    when p_scope like 'unit:%' then public.unit_kind_spec(substr(p_scope, 6)) is not null
    else p_scope in ('docs:boq', 'docs:letter', 'docs:design', 'supervision:reports', 'swot', 'pm:plan', 'pm:track',
                     'docs:pm_view', 'docs:pm_add', 'docs:pm_duration', 'docs:pm_dates', 'docs:pm_approve')
  end
$function$
;

CREATE OR REPLACE FUNCTION public.app_section_ok(p_key text)
 RETURNS boolean
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public'
AS $function$
  select p_key in ('cycle', 'risks', 'swot', 'docs', 'supervision', 'heritage', 'planning_qa', 'safety', 'acceptance',
                   'chat', 'security', 'print', 'manual')
$function$
;

alter table public.user_grants drop constraint if exists user_grants_scope_check;
alter table public.user_grants add constraint user_grants_scope_check check (
  scope ~ '^(form:[a-z0-9_]{1,40}|docs:(boq|letter|design|pm_view|pm_add|pm_duration|pm_dates|pm_approve)|supervision:reports|unit:[a-z_]{2,40}|swot|pm:(plan|track))$');

-- جداول القسم ثم دواله
drop table if exists public.st_moves;
drop table if exists public.st_batches;
drop table if exists public.st_stock;
drop table if exists public.st_doc_lines;
drop table if exists public.st_docs;
drop table if exists public.st_item_units;
drop table if exists public.st_items;
drop table if exists public.st_units;
drop table if exists public.st_categories;
drop table if exists public.st_warehouses;
drop table if exists public.st_locations;
drop table if exists public.st_employees;
drop table if exists public.st_departments;
drop table if exists public.st_settings;
drop table if exists public.st_counters;

drop function if exists public.st_confirm_receipt(uuid);
drop function if exists public.st_reverse_doc(uuid, text);
drop function if exists public.st_delete_doc(uuid);
drop function if exists public.st_doc_action(uuid, text, text, boolean);
drop function if exists public.st_post(uuid);
drop function if exists public.st_apply_out(uuid, uuid, uuid, uuid, numeric, date, text);
drop function if exists public.st_apply_in(uuid, uuid, uuid, uuid, numeric, date, text);
drop function if exists public.st_reserve(uuid, integer, boolean);
drop function if exists public.st_doc_outgoing(uuid);
drop function if exists public.st_save_doc(uuid, jsonb);
drop function if exists public.st_fmt(numeric);
drop function if exists public.st_doc_snapshot(uuid);
drop function if exists public.st_import_items(jsonb);
drop function if exists public.st_save_item(uuid, jsonb);
drop function if exists public.st_import_employees(jsonb);
drop function if exists public.st_save_employee(uuid, jsonb);
drop function if exists public.st_set_settings(jsonb);
drop function if exists public.st_delete_setup(text, uuid);
drop function if exists public.st_save_unit(uuid, jsonb);
drop function if exists public.st_save_category(uuid, jsonb);
drop function if exists public.st_save_warehouse(uuid, jsonb);
drop function if exists public.st_save_location(uuid, jsonb);
drop function if exists public.st_save_department(uuid, jsonb);
drop function if exists public.st_uuid(jsonb, text);
drop function if exists public.st_num(jsonb, text, numeric);
drop function if exists public.st_text(jsonb, text, integer);
drop function if exists public.st_next_no(text, text, integer, integer);
drop function if exists public.st_setting_bool(text, boolean);
drop function if exists public.st_my_employee();
drop function if exists public.st_can_move(uuid);
drop function if exists public.st_can_approve();
drop function if exists public.st_can_items();
drop function if exists public.st_can_setup();
drop function if exists public.st_staff();
drop function if exists public.st_my_warehouses();
drop function if exists public.st_sees_all();
