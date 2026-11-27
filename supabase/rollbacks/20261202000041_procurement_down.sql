-- =====================================================================
-- التراجع عن الترحيل 41 (قسم المشتريات: الطلبات والعروض والأوامر والاستلام)
--
-- يُرفض إن كان في القسم أي طلب أو مورد أو أمر، أو عُدّلت إعداداته المبدئية، أو مُنحت أي صلاحية procurement:*.
-- عندها تبقى المنظومة كما هي. يعيد دوال الترحيل 40 (my_sections وapp_section_ok وgrant_scope_ok) وقيد نطاقات الصلاحيات
-- كما كانت حرفياً، ثم يحذف جداول المشتريات ودوالها. لا يمس المخازن والأصول ولا ما استُلم منها.
-- =====================================================================
do $$
declare
  v_bad text := '';
begin
  if to_regclass('public.pr_requests') is null then
    return;
  end if;
  if exists (select 1 from public.pr_requests) then v_bad := v_bad || ' طلبات'; end if;
  if exists (select 1 from public.pr_suppliers) then v_bad := v_bad || ' موردون'; end if;
  if exists (select 1 from public.pr_orders) then v_bad := v_bad || ' أوامر شراء'; end if;
  if exists (select 1 from public.pr_settings where updated_by is not null) then v_bad := v_bad || ' إعدادات معدّلة'; end if;
  if exists (select 1 from public.user_grants where scope like 'procurement:%') then v_bad := v_bad || ' صلاحيات المشتريات'; end if;
  if v_bad <> '' then
    raise exception 'لا يُتراجع عن الترحيل 41: في قسم المشتريات بيانات (%). المنظومة كما هي.', btrim(v_bad);
  end if;
end $$;

-- قيد نطاقات الصلاحيات كما كان بعد الترحيل 40
alter table public.user_grants drop constraint if exists user_grants_scope_check;
alter table public.user_grants add constraint user_grants_scope_check check (
  scope ~ '^(form:[a-z0-9_]{1,40}|docs:(boq|letter|design|pm_view|pm_add|pm_duration|pm_dates|pm_approve)|supervision:reports|unit:[a-z_]{2,40}|swot|pm:(plan|track)|stores:(admin|manager|audit|assets)|stores:keeper:[0-9a-f-]{36}|maintenance:(admin|manager|tech|audit))$');

-- دوال الترحيل 40 كما كانت
create or replace function public.grant_scope_ok(p_scope text)
returns boolean
language sql stable security definer set search_path = public
as $$
  select case
    when p_scope like 'form:%' then exists (select 1 from public.form_defs where key = substr(p_scope, 6))
    when p_scope like 'unit:%' then public.unit_kind_spec(substr(p_scope, 6)) is not null
    when p_scope like 'stores:keeper:%' then
      substr(p_scope, 15) ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
      and exists (select 1 from public.st_warehouses w where w.id::text = substr(p_scope, 15))
    else p_scope in ('docs:boq', 'docs:letter', 'docs:design', 'supervision:reports', 'swot', 'pm:plan', 'pm:track',
                     'docs:pm_view', 'docs:pm_add', 'docs:pm_duration', 'docs:pm_dates', 'docs:pm_approve',
                     'stores:admin', 'stores:manager', 'stores:audit', 'stores:assets',
                     'maintenance:admin', 'maintenance:manager', 'maintenance:tech', 'maintenance:audit')
  end
$$;
create or replace function public.my_sections()
returns text[]
language plpgsql stable security definer set search_path = public
as $$
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
    return array['maintenance', 'manual', 'stores'];
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
    s := s || 'maintenance'::text;
  end if;
  if public.can_audit() then
    s := s || 'security'::text;
  end if;
  s := s || array['chat', 'manual', 'print'];
  return array(select distinct x from unnest(s) x where x is not null order by x);
end;
$$;
create or replace function public.app_section_ok(p_key text)
returns boolean
language sql immutable set search_path = public
as $$
  select p_key in ('cycle', 'risks', 'swot', 'docs', 'supervision', 'heritage', 'planning_qa', 'safety', 'acceptance',
                   'chat', 'security', 'print', 'manual', 'stores', 'maintenance')
$$;

drop table if exists public.pr_events, public.pr_receipts, public.pr_order_lines, public.pr_orders, public.pr_quotes,
  public.pr_request_lines, public.pr_requests, public.pr_suppliers, public.pr_settings cascade;

drop function if exists public.pr_sees_all(), public.pr_staff(), public.pr_can_review(), public.pr_can_buy(), public.pr_can_admin(),
  public.pr_me_ok(), public.pr_can_request(), public.pr_save_request(uuid, jsonb), public.pr_submit(uuid), public.pr_review(uuid, jsonb),
  public.pr_reject(uuid, text), public.pr_decide(uuid, boolean, text), public.pr_cancel(uuid, text), public.pr_comment(uuid, text),
  public.pr_save_supplier(uuid, jsonb), public.pr_save_quote(uuid, jsonb), public.pr_delete_quote(uuid),
  public.pr_issue_order(uuid, jsonb), public.pr_cancel_order(uuid, text), public.pr_receive(uuid, jsonb),
  public.pr_save_settings(jsonb), public.pr_lookups(), public.pr_setting_num(text, numeric), public.pr_event(uuid, text, jsonb, text),
  public.pr_notify(text[], text, text), public.pr_factor(uuid, uuid), public.pr_available(uuid);
