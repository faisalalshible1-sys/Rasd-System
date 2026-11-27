-- =====================================================================
-- الإصدار 1.9.0 (الترحيل 40): قسم الصيانة والخدمات العامة — البلاغات والصيانة الدورية والتنبيهات
--
--  قسم مستقل عن القسم المالي وعن المخازن في صفحاته وصلاحياته، ويرتبط بسجل الأصول والمواقع (الترحيلان 38 و39)
--  ارتباط قراءة وإشارة فقط. كل جداوله جديدة بالبادئة mt_ ولا أثر مالي لشيء فيها:
--  1. البلاغات: يرفعها أي حساب فعّال (ومنه حساب الموظف) بعنوان ووصف وتصنيف وأولوية وموقع (وأصل برقمه إن عُرف)،
--     برقم MR-سنة-تسلسل، ومسارها: جديد ← مُسنَد ← قيد التنفيذ ← (معلّق) ← منجز ← مغلق، أو مرفوض أو ملغى.
--     الإسناد لفني من قائمة الفنيين أو لجهة خارجية، والإنجاز بوصف المعالجة، وتأكيد صاحب البلاغ إغلاقه أو إعادة فتحه.
--     الموعد المستهدف يُحسب من الأولوية بحدود قابلة للتعديل (إعدادات الصيانة). سجل أحداث لا يُعدَّل لكل بلاغ.
--  2. الصيانة الدورية: خطط بتكرار (أيام أو أسابيع أو أشهر أو سنوات) وفترة تنبيه مسبق، تولّد بلاغات وقائية في وقتها
--     (دالة mt_generate_due) دون تكرار الموعد الواحد ودون تراكم بلاغات الخطة المفتوحة.
--  3. التنبيهات (دالة mt_alerts): متأخر عن موعده، وغير مُسنَد طويلاً، ومعلّق طويلاً، وقريب الاستحقاق، وينتظر تأكيد صاحبه،
--     وأصل تحت الضمان، وأصل تتكرر أعطاله. وإشعارات داخلية عند الإسناد والإنجاز وإعادة الفتح والرفض.
--  4. الأصول: بدء التنفيذ على بلاغ مربوط بأصل متاح أو مستخدم يجعله «تحت الصيانة» وإنجازه يعيده لوضعه؛ كل ذلك
--     بحدث في سجل الأصل. أصل العهدة لا يُغيَّر وضعه.
--  5. نطاقات صلاحية جديدة: maintenance:admin (الإعدادات والفنيون)، maintenance:manager (الفرز والإسناد والخطط والإغلاق)،
--     maintenance:tech (الفني: بلاغاته المسندة وتقدمها)، maintenance:audit (اطلاع فقط). والقسم يظهر لكل حساب فعّال
--     (عدا مسؤول الأمن) ليرفع بلاغاته ويتابعها، ولا يرى غيرها إلا أهل القسم.
--  يُشغَّل بعد 20261130000039_stores_assets.sql، وإعادة تشغيله آمنة. التراجع: supabase/rollbacks/20261201000040_maintenance_down.sql
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. الجداول
-- ---------------------------------------------------------------------
-- حدود الصيانة القابلة للتعديل من واجهة الإعدادات
create table if not exists public.mt_settings (
  key        text primary key check (key in ('sla_hours', 'assign_hours', 'hold_days', 'confirm_days', 'soon_hours',
                                              'repeat_count', 'repeat_days', 'plan_lead_days')),
  value      jsonb not null,
  updated_at timestamptz not null default now(),
  updated_by uuid references public.profiles (id) on delete set null
);
create index if not exists mt_settings_updated_by_idx on public.mt_settings (updated_by);
insert into public.mt_settings (key, value) values
  ('sla_hours', '{"urgent": 8, "high": 48, "normal": 120, "low": 240}'::jsonb),
  ('assign_hours', '4'::jsonb),
  ('hold_days', '7'::jsonb),
  ('confirm_days', '3'::jsonb),
  ('soon_hours', '24'::jsonb),
  ('repeat_count', '3'::jsonb),
  ('repeat_days', '90'::jsonb),
  ('plan_lead_days', '7'::jsonb)
on conflict (key) do nothing;

-- الفنيون: موظفون من سجل الموظفين (الترحيل 38) يُسنَد إليهم؛ ولمن له حساب منهم صلاحية maintenance:tech
create table if not exists public.mt_technicians (
  employee_id uuid primary key references public.st_employees (id) on delete restrict,
  trade       text not null default 'general'
              check (trade in ('general', 'electrical', 'plumbing', 'hvac', 'civil', 'carpentry', 'it', 'furniture', 'cleaning', 'safety')),
  active      boolean not null default true,
  note        text not null default '' check (length(note) <= 300),
  created_at  timestamptz not null default now(),
  created_by  uuid references public.profiles (id) on delete set null,
  updated_at  timestamptz not null default now(),
  updated_by  uuid references public.profiles (id) on delete set null
);
create index if not exists mt_technicians_created_by_idx on public.mt_technicians (created_by);
create index if not exists mt_technicians_updated_by_idx on public.mt_technicians (updated_by);

-- خطط الصيانة الدورية
create table if not exists public.mt_plans (
  id             uuid primary key default gen_random_uuid(),
  plan_no        text not null,
  title          text not null check (length(btrim(title)) between 3 and 160),
  category       text not null default 'other'
                 check (category in ('electrical', 'plumbing', 'hvac', 'civil', 'carpentry', 'it', 'furniture', 'cleaning', 'safety', 'other')),
  asset_id       uuid references public.st_assets (id) on delete set null,
  asset_tag      text not null default '' check (length(asset_tag) <= 30),
  asset_name     text not null default '' check (length(asset_name) <= 160),
  location_id    uuid references public.st_locations (id) on delete set null,
  place_note     text not null default '' check (length(place_note) <= 200),
  interval_unit  text not null check (interval_unit in ('day', 'week', 'month', 'year')),
  interval_count integer not null check (interval_count between 1 and 365),
  start_date     date not null,
  seq            integer not null default 0 check (seq >= 0),
  next_due       date not null,
  last_done      date,
  lead_days      integer check (lead_days between 0 and 90),
  priority       text not null default 'normal' check (priority in ('low', 'normal', 'high', 'urgent')),
  assignee_id    uuid references public.st_employees (id) on delete restrict,
  vendor         text not null default '' check (length(vendor) <= 160),
  checklist      text not null default '' check (length(checklist) <= 2000),
  active         boolean not null default true,
  created_at     timestamptz not null default now(),
  created_by     uuid references public.profiles (id) on delete set null,
  updated_at     timestamptz not null default now(),
  updated_by     uuid references public.profiles (id) on delete set null,
  constraint mt_plans_interval check ((interval_unit = 'day' and interval_count <= 365) or (interval_unit = 'week' and interval_count <= 52)
                                      or (interval_unit = 'month' and interval_count <= 60) or (interval_unit = 'year' and interval_count <= 10)),
  constraint mt_plans_next check (next_due >= start_date)
);
create unique index if not exists mt_plans_no_uq on public.mt_plans (plan_no);
create index if not exists mt_plans_asset_idx on public.mt_plans (asset_id);
create index if not exists mt_plans_location_idx on public.mt_plans (location_id);
create index if not exists mt_plans_assignee_idx on public.mt_plans (assignee_id);
create index if not exists mt_plans_due_idx on public.mt_plans (next_due) where active;
create index if not exists mt_plans_created_by_idx on public.mt_plans (created_by);
create index if not exists mt_plans_updated_by_idx on public.mt_plans (updated_by);

-- البلاغات (ومنها الوقائية المولَّدة من الخطط)
create table if not exists public.mt_requests (
  id            uuid primary key default gen_random_uuid(),
  req_no        text not null,
  title         text not null check (length(btrim(title)) between 3 and 160),
  description   text not null default '' check (length(description) <= 2000),
  category      text not null default 'other'
                check (category in ('electrical', 'plumbing', 'hvac', 'civil', 'carpentry', 'it', 'furniture', 'cleaning', 'safety', 'other')),
  priority      text not null default 'normal' check (priority in ('low', 'normal', 'high', 'urgent')),
  status        text not null default 'new'
                check (status in ('new', 'assigned', 'in_progress', 'on_hold', 'done', 'closed', 'rejected', 'cancelled')),
  source        text not null default 'report' check (source in ('report', 'plan')),
  plan_id       uuid references public.mt_plans (id) on delete set null,
  asset_id      uuid references public.st_assets (id) on delete set null,
  asset_tag     text not null default '' check (length(asset_tag) <= 30),
  asset_name    text not null default '' check (length(asset_name) <= 160),
  asset_held    boolean not null default false,
  location_id   uuid references public.st_locations (id) on delete set null,
  place_note    text not null default '' check (length(place_note) <= 200),
  reporter_id   uuid references public.profiles (id) on delete set null,
  reporter_name text not null default '' check (length(reporter_name) <= 120),
  reporter_dept text not null default '' check (length(reporter_dept) <= 120),
  reporter_phone text not null default '' check (length(reporter_phone) <= 30),
  assignee_id   uuid references public.st_employees (id) on delete restrict,
  assignee_name text not null default '' check (length(assignee_name) <= 120),
  vendor        text not null default '' check (length(vendor) <= 160),
  reported_at   timestamptz not null default now(),
  assigned_at   timestamptz,
  started_at    timestamptz,
  on_hold_at    timestamptz,
  hold_reason   text not null default '' check (length(hold_reason) <= 300),
  done_at       timestamptz,
  closed_at     timestamptz,
  closed_by     uuid references public.profiles (id) on delete set null,
  due_at        timestamptz not null,
  resolution    text not null default '' check (length(resolution) <= 1000),
  reject_reason text not null default '' check (length(reject_reason) <= 300),
  rating        smallint check (rating between 1 and 5),
  rating_note   text not null default '' check (length(rating_note) <= 300),
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  updated_by    uuid references public.profiles (id) on delete set null,
  constraint mt_requests_assigned check (status in ('new', 'rejected', 'cancelled') or assignee_id is not null or vendor <> ''),
  constraint mt_requests_done check (status not in ('done', 'closed') or done_at is not null),
  constraint mt_requests_closed check (status <> 'closed' or closed_at is not null),
  constraint mt_requests_hold check ((status = 'on_hold') = (on_hold_at is not null)),
  constraint mt_requests_rating check (rating is null or status = 'closed'),
  constraint mt_requests_plan check (source = 'plan' or plan_id is null)
);
create unique index if not exists mt_requests_no_uq on public.mt_requests (req_no);
create index if not exists mt_requests_status_idx on public.mt_requests (status, due_at);
create index if not exists mt_requests_reporter_idx on public.mt_requests (reporter_id);
create index if not exists mt_requests_assignee_idx on public.mt_requests (assignee_id);
create index if not exists mt_requests_asset_idx on public.mt_requests (asset_id);
create index if not exists mt_requests_plan_idx on public.mt_requests (plan_id);
create index if not exists mt_requests_location_idx on public.mt_requests (location_id);
create index if not exists mt_requests_closed_by_idx on public.mt_requests (closed_by);
create index if not exists mt_requests_updated_by_idx on public.mt_requests (updated_by);

-- سجل أحداث البلاغ: لا يُعدَّل ولا يُحذف
create table if not exists public.mt_request_events (
  id         bigint generated always as identity primary key,
  request_id uuid not null references public.mt_requests (id) on delete cascade,
  kind       text not null check (kind in ('create', 'assign', 'start', 'hold', 'resume', 'done', 'close', 'reopen', 'reject',
                                           'cancel', 'update', 'comment')),
  at         timestamptz not null default now(),
  by_user    uuid references public.profiles (id) on delete set null,
  data       jsonb not null default '{}'::jsonb,
  note       text not null default ''
);
create index if not exists mt_request_events_req_idx on public.mt_request_events (request_id, id);
create index if not exists mt_request_events_by_idx on public.mt_request_events (by_user);

-- ---------------------------------------------------------------------
-- 2. الصلاحيات والقسم
-- ---------------------------------------------------------------------
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

alter table public.user_grants drop constraint if exists user_grants_scope_check;
alter table public.user_grants add constraint user_grants_scope_check check (
  scope ~ '^(form:[a-z0-9_]{1,40}|docs:(boq|letter|design|pm_view|pm_add|pm_duration|pm_dates|pm_approve)|supervision:reports|unit:[a-z_]{2,40}|swot|pm:(plan|track)|stores:(admin|manager|audit|assets)|stores:keeper:[0-9a-f-]{36}|maintenance:(admin|manager|tech|audit))$');

-- الأقسام: يضاف قسم الصيانة لكل حساب فعّال عدا مسؤول الأمن (يرفع بلاغاته ويتابعها)
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

-- يرى كل بلاغات القسم وخططه: المدير ومدير الصيانة ومدير النظام في القسم والمراجع
create or replace function public.mt_sees_all()
returns boolean
language sql stable security definer set search_path = public
as $$
  select public.is_director() or public.has_grant('maintenance:manager') or public.has_grant('maintenance:admin')
      or public.has_grant('maintenance:audit')
$$;

-- من أهل القسم: يرى صفحاته غير البلاغات الشخصية (ومنهم الفني)
create or replace function public.mt_staff()
returns boolean
language sql stable security definer set search_path = public
as $$
  select public.mt_sees_all() or public.has_grant('maintenance:tech')
$$;

-- الفرز والإسناد والخطط والإغلاق: المدير ومدير الصيانة ومدير النظام في القسم
create or replace function public.mt_can_manage()
returns boolean
language sql stable security definer set search_path = public
as $$
  select public.writes_allowed()
     and (public.is_director() or public.has_grant('maintenance:manager') or public.has_grant('maintenance:admin'))
$$;

-- الإعدادات والفنيون: المدير ومدير النظام في القسم
create or replace function public.mt_can_admin()
returns boolean
language sql stable security definer set search_path = public
as $$
  select public.writes_allowed() and (public.is_director() or public.has_grant('maintenance:admin'))
$$;

-- حساب فعّال غير مسؤول الأمن: يرفع البلاغات ويتابعها (ومنه حساب الموظف)
create or replace function public.mt_me_ok()
returns boolean
language sql stable security definer set search_path = public
as $$
  select exists (select 1 from public.profiles
                  where id = auth.uid() and active and role is not null and role::text <> 'security_auditor'
                    and (locked_until is null or locked_until <= now()))
     and public.mfa_ok()
$$;

create or replace function public.mt_can_report()
returns boolean
language sql stable security definer set search_path = public
as $$
  select public.mt_me_ok() and (public.is_director() or not public.setting_bool('security.freeze', false))
$$;

-- الفني المسنَد إليه البلاغ (بحسابه وصلاحيته)
create or replace function public.mt_is_assignee(p_assignee uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
  select p_assignee is not null and p_assignee is not distinct from public.st_my_employee() and public.has_grant('maintenance:tech')
$$;

-- ---------------------------------------------------------------------
-- 3. أدوات داخلية: الإعدادات والتواريخ والأحداث والإشعارات والأصول
-- ---------------------------------------------------------------------
create or replace function public.mt_setting_num(p_key text, p_default numeric)
returns numeric
language sql stable security definer set search_path = public
as $$
  select coalesce((select case when jsonb_typeof(value) = 'number' then (value #>> '{}')::numeric end
                     from public.mt_settings where key = p_key), p_default)
$$;

-- الحد الأقصى للإنجاز بالساعات لأولوية
create or replace function public.mt_sla_hours(p_priority text)
returns numeric
language sql stable security definer set search_path = public
as $$
  select coalesce((select case when jsonb_typeof(value -> p_priority) = 'number' then (value ->> p_priority)::numeric end
                     from public.mt_settings where key = 'sla_hours'),
                  case p_priority when 'urgent' then 8 when 'high' then 48 when 'low' then 240 else 120 end)
$$;

-- آخر لحظة من يوم (بتوقيت طرابلس)
create or replace function public.mt_end_of_day(p_day date)
returns timestamptz
language sql immutable set search_path = public
as $$
  select ((p_day + 1)::timestamp at time zone 'Africa/Tripoli') - interval '1 second'
$$;

-- موعد الخطة رقم n: يُحسب من تاريخ البدء دائماً فلا ينزلق نهاية الأشهر
create or replace function public.mt_occurrence(p_start date, p_unit text, p_count integer, p_n integer)
returns date
language sql immutable set search_path = public
as $$
  select case p_unit
    when 'day' then p_start + p_n * p_count
    when 'week' then p_start + p_n * p_count * 7
    when 'month' then (p_start + (p_n * p_count) * interval '1 month')::date
    else (p_start + (p_n * p_count * 12) * interval '1 month')::date
  end
$$;

create or replace function public.mt_event(p_req uuid, p_kind text, p_data jsonb, p_note text default '')
returns void
language sql security definer set search_path = public
as $$
  insert into public.mt_request_events (request_id, kind, by_user, data, note)
  values (p_req, p_kind, auth.uid(), coalesce(p_data, '{}'::jsonb), left(coalesce(p_note, ''), 500))
$$;

-- إشعار المدير ومديري الصيانة
create or replace function public.mt_notify_managers(p_title text, p_body text)
returns void
language sql security definer set search_path = public
as $$
  select public.notify_user(u.id, 'maintenance', p_title, p_body)
    from (select p.id from public.profiles p where p.role = 'director' and p.active
          union
          select g.user_id from public.user_grants g join public.profiles p on p.id = g.user_id
           where g.scope in ('maintenance:manager', 'maintenance:admin') and p.active) u
$$;

-- بدء العمل على أصل: يصير «تحت الصيانة» إن كان متاحاً أو مستخدماً (أصل العهدة لا يُغيَّر)
create or replace function public.mt_hold_asset(p_req uuid)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  r public.mt_requests;
  a public.st_assets;
begin
  select * into r from public.mt_requests where id = p_req;
  if r.asset_id is null or r.asset_held then
    return;
  end if;
  select * into a from public.st_assets where id = r.asset_id for update;
  if found and a.status in ('available', 'in_use') then
    update public.st_assets set status = 'maintenance', updated_at = now(), updated_by = auth.uid() where id = a.id;
    update public.mt_requests set asset_held = true where id = p_req;
    perform public.st_asset_event(a.id, 'status',
      jsonb_build_object('from', a.status, 'to', 'maintenance', 'condition_from', a.condition, 'condition_to', a.condition,
                         'request', r.req_no), 'بدء الصيانة ' || r.req_no);
  end if;
end;
$$;

-- انتهاء العمل: يعود الأصل لوضعه إن كان هذا البلاغ هو الذي أوقفه ولا بلاغ آخر قيد التنفيذ عليه
create or replace function public.mt_release_asset(p_req uuid)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  r  public.mt_requests;
  a  public.st_assets;
  st text;
begin
  select * into r from public.mt_requests where id = p_req;
  if r.asset_id is null or not r.asset_held then
    return;
  end if;
  update public.mt_requests set asset_held = false where id = p_req;
  if exists (select 1 from public.mt_requests o
              where o.asset_id = r.asset_id and o.id <> p_req and o.asset_held and o.status in ('in_progress', 'on_hold')) then
    return;
  end if;
  select * into a from public.st_assets where id = r.asset_id for update;
  if found and a.status = 'maintenance' then
    st := public.st_place_status(a.warehouse_id, a.location_id, a.department_id);
    update public.st_assets set status = st, updated_at = now(), updated_by = auth.uid() where id = a.id;
    perform public.st_asset_event(a.id, 'status',
      jsonb_build_object('from', 'maintenance', 'to', st, 'condition_from', a.condition, 'condition_to', a.condition,
                         'request', r.req_no), 'انتهاء الصيانة ' || r.req_no);
  end if;
end;
$$;

-- يحلّ رقم الأصل (الملصق) إلى معرّفه دون كشف بياناته لمن لا يرى الأصول
create or replace function public.mt_resolve_asset(p_data jsonb, p_staff boolean)
returns public.st_assets
language plpgsql security definer set search_path = public
as $$
declare
  a     public.st_assets;
  v_id  uuid := public.st_uuid(p_data, 'asset_id');
  v_tag text := public.st_text(p_data, 'asset_tag', 30);
begin
  if v_id is not null and not p_staff then
    raise exception 'ربط الأصل بمعرّفه لأهل القسم؛ اكتب رقم الأصل من ملصقه' using errcode = '42501';
  end if;
  if v_id is null and v_tag = '' then
    return null;
  end if;
  if v_id is not null then
    select * into a from public.st_assets where id = v_id;
  else
    select * into a from public.st_assets where lower(tag) = lower(v_tag);
  end if;
  if not found then
    raise exception 'رقم الأصل غير مسجل' using errcode = '22023';
  end if;
  if a.status in ('disposal', 'disposed') then
    raise exception 'الأصل مستبعد أو بانتظار الاستبعاد' using errcode = '22023';
  end if;
  return a;
end;
$$;

create or replace function public.mt_valid_category(p_cat text)
returns boolean
language sql immutable set search_path = public
as $$
  select p_cat in ('electrical', 'plumbing', 'hvac', 'civil', 'carpentry', 'it', 'furniture', 'cleaning', 'safety', 'other')
$$;

-- ---------------------------------------------------------------------
-- 4. البلاغات: الرفع والفرز والإسناد والتنفيذ والتأكيد
-- ---------------------------------------------------------------------
create or replace function public.mt_report(p_data jsonb)
returns uuid
language plpgsql security definer set search_path = public
as $$
declare
  v_title  text;
  v_cat    text;
  v_prio   text;
  v_loc    uuid;
  v_on_beh boolean := false;
  a        public.st_assets;
  e        public.st_employees;
  v_dept   text := '';
  v_name   text;
  v_phone  text;
  v_id     uuid;
  v_no     text;
begin
  if not public.mt_can_report() then
    raise exception 'رفع البلاغات لحساب فعّال' using errcode = '42501';
  end if;
  if jsonb_typeof(coalesce(p_data, 'null'::jsonb)) <> 'object' then
    raise exception 'بيانات غير صالحة' using errcode = '22023';
  end if;
  v_title := public.st_text(p_data, 'title', 160);
  if length(v_title) < 3 then
    raise exception 'اكتب عنواناً للبلاغ (3 أحرف فأكثر)' using errcode = '22023';
  end if;
  v_cat := coalesce(nullif(p_data ->> 'category', ''), 'other');
  if not public.mt_valid_category(v_cat) then
    raise exception 'تصنيف البلاغ غير معروف' using errcode = '22023';
  end if;
  v_prio := coalesce(nullif(p_data ->> 'priority', ''), 'normal');
  if v_prio not in ('low', 'normal', 'high', 'urgent') then
    raise exception 'أولوية البلاغ: منخفضة أو عادية أو عالية أو عاجلة' using errcode = '22023';
  end if;
  v_loc := public.st_uuid(p_data, 'location_id');
  if v_loc is not null and not exists (select 1 from public.st_locations where id = v_loc and active) then
    raise exception 'الموقع غير موجود أو موقوف' using errcode = '22023';
  end if;
  a := public.mt_resolve_asset(p_data, public.mt_staff());
  select * into e from public.st_employees where id = public.st_my_employee();
  if found and e.department_id is not null then
    select name into v_dept from public.st_departments where id = e.department_id;
  end if;
  -- بلاغ هاتفي يسجله مدير الصيانة نيابة عن صاحبه: لا حساب لصاحبه فيؤكد المدير إغلاقه
  if public.mt_can_manage() and nullif(btrim(coalesce(p_data ->> 'reporter_name', '')), '') is not null then
    v_on_beh := true;
    v_name := public.st_text(p_data, 'reporter_name', 120);
    v_dept := public.st_text(p_data, 'reporter_dept', 120);
  else
    v_name := coalesce(e.full_name, public.actor_name(auth.uid()));
  end if;
  v_phone := coalesce(nullif(public.st_text(p_data, 'phone', 30), ''), case when not v_on_beh then e.phone end, '');
  v_no := public.st_next_no('mt_request', 'MR', extract(year from now())::integer, 4);
  insert into public.mt_requests (req_no, title, description, category, priority, asset_id, asset_tag, asset_name, location_id,
                                  place_note, reporter_id, reporter_name, reporter_dept, reporter_phone, due_at, updated_by)
  values (v_no, v_title, public.st_text(p_data, 'description', 2000), v_cat, v_prio, a.id, coalesce(a.tag, ''), coalesce(a.name, ''),
          v_loc, public.st_text(p_data, 'place_note', 200), case when v_on_beh then null else auth.uid() end, v_name, v_dept, v_phone,
          now() + (public.mt_sla_hours(v_prio) || ' hours')::interval, auth.uid())
  returning id into v_id;
  perform public.mt_event(v_id, 'create', jsonb_build_object('priority', v_prio, 'category', v_cat, 'on_behalf', v_on_beh), '');
  perform public.write_audit('maintenance.report', null, null,
    jsonb_build_object('id', v_id, 'req_no', v_no, 'title', v_title, 'category', v_cat, 'priority', v_prio,
                       'reporter', v_name, 'tag', coalesce(a.tag, '')), v_no);
  if v_prio in ('urgent', 'high') then
    perform public.mt_notify_managers(case v_prio when 'urgent' then 'بلاغ صيانة عاجل ' else 'بلاغ صيانة عالي الأولوية ' end || v_no,
                                      v_title);
  end if;
  return v_id;
end;
$$;

-- الفرز والإسناد: فني من القائمة أو جهة خارجية، مع تعديل الأولوية والتصنيف والموعد
create or replace function public.mt_assign(p_id uuid, p_data jsonb)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  r       public.mt_requests;
  t       public.mt_technicians;
  e       public.st_employees;
  v_emp   uuid := public.st_uuid(p_data, 'assignee_id');
  v_vend  text := public.st_text(p_data, 'vendor', 160);
  v_prio  text;
  v_cat   text;
  v_due   timestamptz;
  v_day   date := public.st_date(p_data, 'due_date');
  v_loc   uuid;
begin
  if not public.mt_can_manage() then
    raise exception 'إسناد البلاغات لمدير الصيانة أو المدير' using errcode = '42501';
  end if;
  if jsonb_typeof(coalesce(p_data, 'null'::jsonb)) <> 'object' then
    raise exception 'بيانات غير صالحة' using errcode = '22023';
  end if;
  select * into r from public.mt_requests where id = p_id for update;
  if not found then
    raise exception 'البلاغ غير موجود' using errcode = 'P0002';
  end if;
  if r.status not in ('new', 'assigned', 'in_progress', 'on_hold') then
    raise exception 'لا يُسنَد بلاغ منجز أو مغلق أو مرفوض أو ملغى' using errcode = '22023';
  end if;
  if v_emp is null and v_vend = '' then
    raise exception 'اختر الفني المسنَد إليه أو اكتب الجهة الخارجية' using errcode = '22023';
  end if;
  if v_emp is not null then
    select * into t from public.mt_technicians where employee_id = v_emp;
    if not found or not t.active then
      raise exception 'الموظف ليس فنياً فعّالاً في قائمة الفنيين' using errcode = '22023';
    end if;
    select * into e from public.st_employees where id = v_emp;
    if not e.active then
      raise exception 'الموظف «%» موقوف', e.full_name using errcode = '22023';
    end if;
  end if;
  v_prio := coalesce(nullif(p_data ->> 'priority', ''), r.priority);
  if v_prio not in ('low', 'normal', 'high', 'urgent') then
    raise exception 'أولوية البلاغ: منخفضة أو عادية أو عالية أو عاجلة' using errcode = '22023';
  end if;
  v_cat := coalesce(nullif(p_data ->> 'category', ''), r.category);
  if not public.mt_valid_category(v_cat) then
    raise exception 'تصنيف البلاغ غير معروف' using errcode = '22023';
  end if;
  v_loc := coalesce(public.st_uuid(p_data, 'location_id'), r.location_id);
  if v_loc is not null and not exists (select 1 from public.st_locations where id = v_loc) then
    raise exception 'الموقع غير موجود' using errcode = '22023';
  end if;
  -- الموعد: التاريخ المكتوب، وإلا يُعاد حسابه من الأولوية إن تغيّرت، وإلا يبقى
  v_due := case when v_day is not null then public.mt_end_of_day(v_day)
                when v_prio <> r.priority then r.reported_at + (public.mt_sla_hours(v_prio) || ' hours')::interval
                else r.due_at end;
  update public.mt_requests
     set status = case when status = 'new' then 'assigned' else status end,
         assignee_id = v_emp, assignee_name = coalesce(e.full_name, ''), vendor = case when v_emp is null then v_vend else '' end,
         priority = v_prio, category = v_cat, location_id = v_loc, due_at = v_due,
         assigned_at = now(), updated_at = now(), updated_by = auth.uid()
   where id = p_id;
  perform public.mt_event(p_id, 'assign',
    jsonb_build_object('assignee_id', v_emp, 'assignee', coalesce(e.full_name, ''), 'vendor', case when v_emp is null then v_vend else '' end,
                       'priority', v_prio, 'category', v_cat, 'due_at', v_due, 'from_status', r.status),
    public.st_text(p_data, 'note', 500));
  perform public.write_audit('maintenance.assign', null, null,
    jsonb_build_object('id', p_id, 'req_no', r.req_no, 'title', r.title, 'assignee', coalesce(e.full_name, v_vend),
                       'priority', v_prio, 'due_at', v_due), r.req_no);
  if e.profile_id is not null then
    perform public.notify_user(e.profile_id, 'maintenance', 'أُسنِد إليك بلاغ صيانة ' || r.req_no, r.title);
  end if;
end;
$$;

-- التنفيذ: بدء، وتعليق بسبب، واستئناف، وإنجاز بوصف المعالجة (مدير الصيانة أو الفني المسنَد إليه)
create or replace function public.mt_progress(p_id uuid, p_action text, p_data jsonb default '{}'::jsonb)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  r      public.mt_requests;
  v_note text := public.st_text(p_data, 'note', 500);
  v_res  text;
  v_st   text;
begin
  if p_action not in ('start', 'hold', 'resume', 'done') then
    raise exception 'إجراء غير معروف' using errcode = '22023';
  end if;
  select * into r from public.mt_requests where id = p_id for update;
  if not found then
    raise exception 'البلاغ غير موجود' using errcode = 'P0002';
  end if;
  if not (public.mt_can_manage()
          or (public.writes_allowed() and public.mt_is_assignee(r.assignee_id))) then
    raise exception 'تحديث التنفيذ لمدير الصيانة أو الفني المسنَد إليه' using errcode = '42501';
  end if;
  if p_action = 'start' then
    if r.status <> 'assigned' then
      raise exception 'يبدأ التنفيذ من بلاغ مُسنَد' using errcode = '22023';
    end if;
    update public.mt_requests set status = 'in_progress', started_at = coalesce(started_at, now()), updated_at = now(),
           updated_by = auth.uid() where id = p_id;
    perform public.mt_hold_asset(p_id);
    perform public.mt_event(p_id, 'start', '{}'::jsonb, v_note);
    perform public.write_audit('maintenance.start', null, null,
      jsonb_build_object('id', p_id, 'req_no', r.req_no, 'title', r.title), r.req_no);
  elsif p_action = 'hold' then
    if r.status not in ('assigned', 'in_progress') then
      raise exception 'يُعلَّق بلاغ مُسنَد أو قيد التنفيذ' using errcode = '22023';
    end if;
    if length(v_note) < 3 then
      raise exception 'اكتب سبب التعليق' using errcode = '22023';
    end if;
    update public.mt_requests set status = 'on_hold', on_hold_at = now(), hold_reason = v_note, updated_at = now(),
           updated_by = auth.uid() where id = p_id;
    perform public.mt_event(p_id, 'hold', jsonb_build_object('from_status', r.status), v_note);
    perform public.write_audit('maintenance.hold', null, null,
      jsonb_build_object('id', p_id, 'req_no', r.req_no, 'title', r.title, 'reason', v_note), r.req_no);
  elsif p_action = 'resume' then
    if r.status <> 'on_hold' then
      raise exception 'يُستأنف بلاغ معلّق' using errcode = '22023';
    end if;
    v_st := case when r.started_at is null then 'assigned' else 'in_progress' end;
    update public.mt_requests set status = v_st, on_hold_at = null, hold_reason = '', updated_at = now(),
           updated_by = auth.uid() where id = p_id;
    perform public.mt_event(p_id, 'resume', jsonb_build_object('to_status', v_st), v_note);
    perform public.write_audit('maintenance.resume', null, null,
      jsonb_build_object('id', p_id, 'req_no', r.req_no, 'title', r.title), r.req_no);
  else
    if r.status <> 'in_progress' then
      raise exception 'يُنجَز بلاغ قيد التنفيذ' using errcode = '22023';
    end if;
    v_res := public.st_text(p_data, 'resolution', 1000);
    if length(v_res) < 3 then
      raise exception 'اكتب ما تمت به المعالجة' using errcode = '22023';
    end if;
    -- الوقائي لا صاحب له يؤكد، فيُغلَق عند إنجازه
    if r.source = 'plan' then
      update public.mt_requests set status = 'closed', done_at = now(), closed_at = now(), closed_by = auth.uid(), resolution = v_res,
             updated_at = now(), updated_by = auth.uid() where id = p_id;
      update public.mt_plans set last_done = current_date where id = r.plan_id;
    else
      update public.mt_requests set status = 'done', done_at = now(), resolution = v_res, updated_at = now(),
             updated_by = auth.uid() where id = p_id;
    end if;
    perform public.mt_release_asset(p_id);
    perform public.mt_event(p_id, 'done', jsonb_build_object('closed', r.source = 'plan'), v_res);
    perform public.write_audit('maintenance.done', null, null,
      jsonb_build_object('id', p_id, 'req_no', r.req_no, 'title', r.title, 'resolution', v_res), r.req_no);
    if r.reporter_id is not null then
      perform public.notify_user(r.reporter_id, 'maintenance', 'أُنجز بلاغك ' || r.req_no || ': أكّد الإغلاق أو أعد فتحه', r.title);
    end if;
  end if;
end;
$$;

-- صاحب البلاغ (أو مدير الصيانة) يؤكد الإغلاق مع تقييم اختياري، أو يعيد فتحه بسبب
create or replace function public.mt_confirm(p_id uuid, p_accept boolean, p_note text default '', p_rating integer default null)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  r      public.mt_requests;
  v_own  boolean;
  v_note text := left(btrim(coalesce(p_note, '')), 500);
  e      public.st_employees;
begin
  select * into r from public.mt_requests where id = p_id for update;
  if not found then
    raise exception 'البلاغ غير موجود' using errcode = 'P0002';
  end if;
  v_own := r.reporter_id is not null and r.reporter_id = auth.uid();
  if not ((v_own and public.mt_can_report()) or public.mt_can_manage()) then
    raise exception 'التأكيد لصاحب البلاغ أو مدير الصيانة' using errcode = '42501';
  end if;
  if r.status <> 'done' then
    raise exception 'يُؤكَّد بلاغ منجز' using errcode = '22023';
  end if;
  if p_accept then
    if p_rating is not null and (p_rating < 1 or p_rating > 5 or not v_own) then
      raise exception 'التقييم من 1 إلى 5 من صاحب البلاغ' using errcode = '22023';
    end if;
    update public.mt_requests
       set status = 'closed', closed_at = now(), closed_by = auth.uid(), rating = p_rating,
           rating_note = case when p_rating is null then '' else left(v_note, 300) end,
           updated_at = now(), updated_by = auth.uid()
     where id = p_id;
    if r.plan_id is not null then
      update public.mt_plans set last_done = current_date where id = r.plan_id;
    end if;
    perform public.mt_event(p_id, 'close', jsonb_build_object('rating', p_rating, 'by_reporter', v_own), v_note);
    perform public.write_audit('maintenance.close', null, null,
      jsonb_build_object('id', p_id, 'req_no', r.req_no, 'title', r.title, 'rating', p_rating, 'by_reporter', v_own), r.req_no);
  else
    if length(v_note) < 3 then
      raise exception 'اكتب سبب إعادة الفتح' using errcode = '22023';
    end if;
    update public.mt_requests set status = 'in_progress', done_at = null, updated_at = now(), updated_by = auth.uid() where id = p_id;
    perform public.mt_hold_asset(p_id);
    perform public.mt_event(p_id, 'reopen', jsonb_build_object('by_reporter', v_own), v_note);
    perform public.write_audit('maintenance.reopen', null, null,
      jsonb_build_object('id', p_id, 'req_no', r.req_no, 'title', r.title, 'reason', v_note, 'by_reporter', v_own), r.req_no);
    select * into e from public.st_employees where id = r.assignee_id;
    if e.profile_id is not null then
      perform public.notify_user(e.profile_id, 'maintenance', 'أُعيد فتح البلاغ ' || r.req_no, v_note);
    end if;
    perform public.mt_notify_managers('أُعيد فتح البلاغ ' || r.req_no, v_note);
  end if;
end;
$$;

create or replace function public.mt_reject(p_id uuid, p_reason text)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  r      public.mt_requests;
  v_why  text := left(btrim(coalesce(p_reason, '')), 300);
begin
  if not public.mt_can_manage() then
    raise exception 'رفض البلاغات لمدير الصيانة أو المدير' using errcode = '42501';
  end if;
  if length(v_why) < 3 then
    raise exception 'اكتب سبب الرفض' using errcode = '22023';
  end if;
  select * into r from public.mt_requests where id = p_id for update;
  if not found then
    raise exception 'البلاغ غير موجود' using errcode = 'P0002';
  end if;
  if r.status <> 'new' then
    raise exception 'يُرفض بلاغ جديد لم يُسنَد' using errcode = '22023';
  end if;
  update public.mt_requests set status = 'rejected', reject_reason = v_why, updated_at = now(), updated_by = auth.uid() where id = p_id;
  perform public.mt_event(p_id, 'reject', '{}'::jsonb, v_why);
  perform public.write_audit('maintenance.reject', null, null,
    jsonb_build_object('id', p_id, 'req_no', r.req_no, 'title', r.title, 'reason', v_why), r.req_no);
  if r.reporter_id is not null then
    perform public.notify_user(r.reporter_id, 'maintenance', 'رُفض بلاغك ' || r.req_no, v_why);
  end if;
end;
$$;

-- الإلغاء: صاحب البلاغ ما دام جديداً، ومدير الصيانة قبل الإنجاز
create or replace function public.mt_cancel(p_id uuid, p_note text default '')
returns void
language plpgsql security definer set search_path = public
as $$
declare
  r      public.mt_requests;
  v_note text := left(btrim(coalesce(p_note, '')), 500);
begin
  select * into r from public.mt_requests where id = p_id for update;
  if not found then
    raise exception 'البلاغ غير موجود' using errcode = 'P0002';
  end if;
  if not (public.mt_can_manage()
          or (r.status = 'new' and r.reporter_id is not null and r.reporter_id = auth.uid() and public.mt_can_report())) then
    raise exception 'يُلغي البلاغ صاحبه قبل إسناده أو مدير الصيانة' using errcode = '42501';
  end if;
  if r.status not in ('new', 'assigned', 'in_progress', 'on_hold') then
    raise exception 'لا يُلغى بلاغ منجز أو مغلق أو مرفوض' using errcode = '22023';
  end if;
  update public.mt_requests set status = 'cancelled', on_hold_at = null, updated_at = now(), updated_by = auth.uid() where id = p_id;
  perform public.mt_release_asset(p_id);
  perform public.mt_event(p_id, 'cancel', jsonb_build_object('from_status', r.status), v_note);
  perform public.write_audit('maintenance.cancel', null, null,
    jsonb_build_object('id', p_id, 'req_no', r.req_no, 'title', r.title, 'from', r.status, 'note', v_note), r.req_no);
end;
$$;

-- تعليق على بلاغ: صاحبه والمسنَد إليه وأهل القسم
create or replace function public.mt_comment(p_id uuid, p_note text)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  r      public.mt_requests;
  v_note text := left(btrim(coalesce(p_note, '')), 500);
begin
  select * into r from public.mt_requests where id = p_id;
  if not found then
    raise exception 'البلاغ غير موجود' using errcode = 'P0002';
  end if;
  if not (public.mt_sees_all() or (r.reporter_id is not null and r.reporter_id = auth.uid()) or public.mt_is_assignee(r.assignee_id)) then
    raise exception 'البلاغ غير موجود' using errcode = 'P0002';
  end if;
  if not (public.mt_can_report() or public.mt_can_manage()) then
    raise exception 'المنظومة في وضع القراءة فقط' using errcode = '42501';
  end if;
  if length(v_note) < 2 then
    raise exception 'اكتب التعليق' using errcode = '22023';
  end if;
  perform public.mt_event(p_id, 'comment', '{}'::jsonb, v_note);
end;
$$;

-- ---------------------------------------------------------------------
-- 5. الصيانة الدورية: الخطط وتوليد البلاغات الوقائية
-- ---------------------------------------------------------------------
create or replace function public.mt_save_plan(p_id uuid, p_data jsonb)
returns uuid
language plpgsql security definer set search_path = public
as $$
declare
  old_r   public.mt_plans;
  a       public.st_assets;
  t       public.mt_technicians;
  v_id    uuid := p_id;
  v_title text;
  v_cat   text;
  v_unit  text;
  v_cnt   integer;
  v_start date;
  v_prio  text;
  v_emp   uuid := public.st_uuid(p_data, 'assignee_id');
  v_vend  text := public.st_text(p_data, 'vendor', 160);
  v_loc   uuid := public.st_uuid(p_data, 'location_id');
  v_lead  integer;
  v_seq   integer := 0;
  v_next  date;
  v_active boolean;
  v_no    text;
begin
  if not public.mt_can_manage() then
    raise exception 'خطط الصيانة الدورية لمدير الصيانة أو المدير' using errcode = '42501';
  end if;
  if jsonb_typeof(coalesce(p_data, 'null'::jsonb)) <> 'object' then
    raise exception 'بيانات غير صالحة' using errcode = '22023';
  end if;
  if p_id is not null then
    select * into old_r from public.mt_plans where id = p_id for update;
    if not found then
      raise exception 'الخطة غير موجودة' using errcode = 'P0002';
    end if;
  end if;
  v_title := public.st_text(p_data, 'title', 160);
  if length(v_title) < 3 then
    raise exception 'اكتب عنوان الخطة (3 أحرف فأكثر)' using errcode = '22023';
  end if;
  v_cat := coalesce(nullif(p_data ->> 'category', ''), 'other');
  if not public.mt_valid_category(v_cat) then
    raise exception 'تصنيف الخطة غير معروف' using errcode = '22023';
  end if;
  v_unit := p_data ->> 'interval_unit';
  if v_unit is null or v_unit not in ('day', 'week', 'month', 'year') then
    raise exception 'وحدة التكرار: يوم أو أسبوع أو شهر أو سنة' using errcode = '22023';
  end if;
  if jsonb_typeof(p_data -> 'interval_count') is distinct from 'number' then
    raise exception 'حدد عدد وحدات التكرار' using errcode = '22023';
  end if;
  v_cnt := (p_data ->> 'interval_count')::integer;
  if v_cnt < 1 or (v_unit = 'day' and v_cnt > 365) or (v_unit = 'week' and v_cnt > 52) or (v_unit = 'month' and v_cnt > 60)
     or (v_unit = 'year' and v_cnt > 10) then
    raise exception 'التكرار خارج الحد: حتى 365 يوماً أو 52 أسبوعاً أو 60 شهراً أو 10 سنوات' using errcode = '22023';
  end if;
  v_start := public.st_date(p_data, 'start_date');
  if v_start is null then
    raise exception 'حدد تاريخ بدء الخطة' using errcode = '22023';
  end if;
  v_prio := coalesce(nullif(p_data ->> 'priority', ''), 'normal');
  if v_prio not in ('low', 'normal', 'high', 'urgent') then
    raise exception 'أولوية الخطة: منخفضة أو عادية أو عالية أو عاجلة' using errcode = '22023';
  end if;
  if p_data ? 'lead_days' and jsonb_typeof(p_data -> 'lead_days') = 'number' then
    v_lead := (p_data ->> 'lead_days')::integer;
    if v_lead < 0 or v_lead > 90 then
      raise exception 'التنبيه المسبق من 0 إلى 90 يوماً' using errcode = '22023';
    end if;
  end if;
  if v_emp is not null then
    select * into t from public.mt_technicians where employee_id = v_emp;
    if not found or not t.active then
      raise exception 'الموظف ليس فنياً فعّالاً في قائمة الفنيين' using errcode = '22023';
    end if;
    v_vend := '';
  end if;
  if v_loc is not null and not exists (select 1 from public.st_locations where id = v_loc) then
    raise exception 'الموقع غير موجود' using errcode = '22023';
  end if;
  a := public.mt_resolve_asset(p_data, true);
  v_active := coalesce((p_data ->> 'active')::boolean, true);
  -- الموعد القادم: من تاريخ البدء، أو عند تعديل الجدولة أول موعد لا يقل عن اليوم؛ ويبقى كما هو إن لم تتغير الجدولة
  if p_id is not null and old_r.start_date = v_start and old_r.interval_unit = v_unit and old_r.interval_count = v_cnt then
    v_seq := old_r.seq;
    v_next := old_r.next_due;
  else
    v_seq := 0;
    v_next := public.mt_occurrence(v_start, v_unit, v_cnt, 0);
    while v_next < current_date loop
      v_seq := v_seq + 1;
      v_next := public.mt_occurrence(v_start, v_unit, v_cnt, v_seq);
    end loop;
  end if;
  if p_id is null then
    v_no := public.st_next_no('mt_plan', 'MP', 0, 4);
    insert into public.mt_plans (plan_no, title, category, asset_id, asset_tag, asset_name, location_id, place_note, interval_unit,
                                 interval_count, start_date, seq, next_due, lead_days, priority, assignee_id, vendor, checklist,
                                 active, created_by, updated_by)
    values (v_no, v_title, v_cat, a.id, coalesce(a.tag, ''), coalesce(a.name, ''), v_loc, public.st_text(p_data, 'place_note', 200),
            v_unit, v_cnt, v_start, v_seq, v_next, v_lead, v_prio, v_emp, v_vend, public.st_text(p_data, 'checklist', 2000),
            v_active, auth.uid(), auth.uid())
    returning id into v_id;
    perform public.write_audit('maintenance.plan', null, null,
      jsonb_build_object('id', v_id, 'plan_no', v_no, 'title', v_title, 'every', v_cnt, 'unit', v_unit, 'created', true), v_no);
  else
    update public.mt_plans
       set title = v_title, category = v_cat, asset_id = a.id, asset_tag = coalesce(a.tag, ''), asset_name = coalesce(a.name, ''),
           location_id = v_loc, place_note = public.st_text(p_data, 'place_note', 200), interval_unit = v_unit,
           interval_count = v_cnt, start_date = v_start, seq = v_seq, next_due = v_next, lead_days = v_lead, priority = v_prio,
           assignee_id = v_emp, vendor = v_vend, checklist = public.st_text(p_data, 'checklist', 2000), active = v_active,
           updated_at = now(), updated_by = auth.uid()
     where id = p_id;
    perform public.write_audit('maintenance.plan', null, null,
      jsonb_build_object('id', p_id, 'plan_no', old_r.plan_no, 'title', v_title, 'every', v_cnt, 'unit', v_unit, 'active', v_active,
                         'created', false), old_r.plan_no);
  end if;
  return v_id;
end;
$$;

create or replace function public.mt_delete_plan(p_id uuid)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  p public.mt_plans;
begin
  if not public.mt_can_manage() then
    raise exception 'خطط الصيانة الدورية لمدير الصيانة أو المدير' using errcode = '42501';
  end if;
  select * into p from public.mt_plans where id = p_id for update;
  if not found then
    raise exception 'الخطة غير موجودة' using errcode = 'P0002';
  end if;
  delete from public.mt_plans where id = p_id;
  perform public.write_audit('maintenance.plan_delete', null, null,
    jsonb_build_object('id', p_id, 'plan_no', p.plan_no, 'title', p.title), p.plan_no);
end;
$$;

-- توليد بلاغات الخطط التي حان موعدها (قبله بفترة التنبيه المسبق). آمنة التكرار: كل موعد يُولَّد مرة واحدة،
-- والموعد الفائت لا يُولَّد، ولا تتراكم بلاغات خطة ما دام لها بلاغ مفتوح.
create or replace function public.mt_generate_due(p_as_of date default current_date)
returns jsonb
language plpgsql security definer set search_path = public
as $$
declare
  p        public.mt_plans;
  v_lead   integer;
  v_n      integer;
  v_due    date;
  v_made   integer := 0;
  v_skip   integer := 0;
  v_no     text;
  v_id     uuid;
  v_emp    public.st_employees;
begin
  if not (public.mt_staff() and public.writes_allowed()) then
    raise exception 'توليد الصيانة الدورية لأهل القسم' using errcode = '42501';
  end if;
  for p in select * from public.mt_plans pl
            where pl.active and pl.next_due - coalesce(pl.lead_days, public.mt_setting_num('plan_lead_days', 7)::integer) <= p_as_of
            order by pl.next_due, pl.plan_no for update
  loop
    v_lead := coalesce(p.lead_days, public.mt_setting_num('plan_lead_days', 7)::integer);
    v_due := p.next_due;
    if exists (select 1 from public.mt_requests q where q.plan_id = p.id and q.status in ('new', 'assigned', 'in_progress', 'on_hold', 'done')) then
      v_skip := v_skip + 1;
    else
      v_no := public.st_next_no('mt_request', 'MR', extract(year from now())::integer, 4);
      select * into v_emp from public.st_employees where id = p.assignee_id;
      insert into public.mt_requests (req_no, title, description, category, priority, status, source, plan_id, asset_id, asset_tag,
                                      asset_name, location_id, place_note, reporter_name, assignee_id, assignee_name, vendor,
                                      assigned_at, due_at, updated_by)
      values (v_no, p.title, p.checklist, p.category, p.priority,
              case when p.assignee_id is not null or p.vendor <> '' then 'assigned' else 'new' end, 'plan', p.id, p.asset_id,
              p.asset_tag, p.asset_name, p.location_id, p.place_note, 'الصيانة الدورية ' || p.plan_no, p.assignee_id,
              coalesce(v_emp.full_name, ''), p.vendor,
              case when p.assignee_id is not null or p.vendor <> '' then now() end, public.mt_end_of_day(v_due), auth.uid())
      returning id into v_id;
      perform public.mt_event(v_id, 'create', jsonb_build_object('plan_id', p.id, 'plan_no', p.plan_no, 'due', v_due), '');
      v_made := v_made + 1;
      if v_emp.profile_id is not null then
        perform public.notify_user(v_emp.profile_id, 'maintenance', 'أُسنِد إليك بلاغ صيانة دورية ' || v_no, p.title);
      end if;
    end if;
    -- التقدم إلى أول موعد يقع خارج نافذة التنبيه المسبق (الفائت يُتخطّى)
    v_n := p.seq;
    loop
      v_n := v_n + 1;
      exit when public.mt_occurrence(p.start_date, p.interval_unit, p.interval_count, v_n) - v_lead > p_as_of;
    end loop;
    update public.mt_plans
       set seq = v_n, next_due = public.mt_occurrence(p.start_date, p.interval_unit, p.interval_count, v_n), updated_at = now()
     where id = p.id;
  end loop;
  if v_made > 0 then
    perform public.write_audit('maintenance.generate', null, null,
      jsonb_build_object('created', v_made, 'skipped', v_skip, 'as_of', p_as_of), 'الصيانة الدورية');
  end if;
  return jsonb_build_object('created', v_made, 'skipped', v_skip);
end;
$$;

-- ---------------------------------------------------------------------
-- 6. الإعدادات والفنيون
-- ---------------------------------------------------------------------
create or replace function public.mt_save_settings(p_data jsonb)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  k    text;
  v    jsonb;
  p    text;
  x    numeric;
  v_old jsonb;
  v_min numeric;
  v_max numeric;
  v_changed jsonb := '{}'::jsonb;
begin
  if not public.mt_can_admin() then
    raise exception 'إعدادات الصيانة للمدير أو مدير النظام في القسم' using errcode = '42501';
  end if;
  if jsonb_typeof(coalesce(p_data, 'null'::jsonb)) <> 'object' then
    raise exception 'بيانات غير صالحة' using errcode = '22023';
  end if;
  for k, v in select key, value from jsonb_each(p_data) loop
    if k = 'sla_hours' then
      if jsonb_typeof(v) <> 'object' then
        raise exception 'مدد الإنجاز بحسب الأولوية' using errcode = '22023';
      end if;
      foreach p in array array['urgent', 'high', 'normal', 'low'] loop
        if jsonb_typeof(v -> p) is distinct from 'number' or (v ->> p)::numeric < 1 or (v ->> p)::numeric > 2000 then
          raise exception 'مدة الإنجاز لكل أولوية من ساعة إلى 2000 ساعة' using errcode = '22023';
        end if;
      end loop;
      v := jsonb_build_object('urgent', (v ->> 'urgent')::numeric, 'high', (v ->> 'high')::numeric,
                              'normal', (v ->> 'normal')::numeric, 'low', (v ->> 'low')::numeric);
      if not ((v ->> 'urgent')::numeric <= (v ->> 'high')::numeric and (v ->> 'high')::numeric <= (v ->> 'normal')::numeric
              and (v ->> 'normal')::numeric <= (v ->> 'low')::numeric) then
        raise exception 'مدة العاجل لا تزيد على العالي، ولا العالي على العادي، ولا العادي على المنخفض' using errcode = '22023';
      end if;
    elsif k in ('assign_hours', 'hold_days', 'confirm_days', 'soon_hours', 'repeat_count', 'repeat_days', 'plan_lead_days') then
      if jsonb_typeof(v) <> 'number' then
        raise exception 'قيمة غير رقمية في %', k using errcode = '22023';
      end if;
      x := (v #>> '{}')::numeric;
      v_min := case k when 'repeat_count' then 2 else 1 end;
      v_max := case k when 'assign_hours' then 720 when 'soon_hours' then 720 when 'plan_lead_days' then 90
                      when 'repeat_count' then 50 else 365 end;
      if x <> trunc(x) or x < v_min or x > v_max then
        raise exception 'قيمة % خارج الحد', k using errcode = '22023';
      end if;
    else
      raise exception 'إعداد غير معروف: %', k using errcode = '22023';
    end if;
    select value into v_old from public.mt_settings where key = k;
    if v_old is distinct from v then
      insert into public.mt_settings (key, value, updated_by) values (k, v, auth.uid())
      on conflict (key) do update set value = excluded.value, updated_at = now(), updated_by = auth.uid();
      v_changed := v_changed || jsonb_build_object(k, jsonb_build_object('from', v_old, 'to', v));
    end if;
  end loop;
  if v_changed <> '{}'::jsonb then
    perform public.write_audit('maintenance.settings', null, null, jsonb_build_object('changed', v_changed), 'إعدادات الصيانة');
  end if;
end;
$$;

create or replace function public.mt_save_technician(p_employee uuid, p_data jsonb)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  e        public.st_employees;
  old_t    public.mt_technicians;
  v_trade  text := coalesce(nullif(p_data ->> 'trade', ''), 'general');
  v_active boolean := coalesce((p_data ->> 'active')::boolean, true);
  v_note   text := public.st_text(p_data, 'note', 300);
begin
  if not public.mt_can_admin() then
    raise exception 'قائمة الفنيين للمدير أو مدير النظام في القسم' using errcode = '42501';
  end if;
  if v_trade not in ('general', 'electrical', 'plumbing', 'hvac', 'civil', 'carpentry', 'it', 'furniture', 'cleaning', 'safety') then
    raise exception 'تخصص الفني غير معروف' using errcode = '22023';
  end if;
  select * into e from public.st_employees where id = p_employee;
  if not found then
    raise exception 'الموظف غير موجود في السجل' using errcode = 'P0002';
  end if;
  select * into old_t from public.mt_technicians where employee_id = p_employee for update;
  if not found and not e.active then
    raise exception 'الموظف «%» موقوف', e.full_name using errcode = '22023';
  end if;
  if found and not v_active and exists (select 1 from public.mt_requests r
                                         where r.assignee_id = p_employee and r.status in ('assigned', 'in_progress', 'on_hold')) then
    raise exception 'للفني بلاغات مفتوحة؛ أعد إسنادها قبل إيقافه' using errcode = '22023';
  end if;
  insert into public.mt_technicians (employee_id, trade, active, note, created_by, updated_by)
  values (p_employee, v_trade, v_active, v_note, auth.uid(), auth.uid())
  on conflict (employee_id) do update
    set trade = excluded.trade, active = excluded.active, note = excluded.note, updated_at = now(), updated_by = auth.uid();
  perform public.write_audit('maintenance.technician', null, null,
    jsonb_build_object('employee_id', p_employee, 'name', e.full_name, 'trade', v_trade, 'active', v_active, 'created', old_t.employee_id is null),
    e.full_name);
end;
$$;

-- ---------------------------------------------------------------------
-- 7. القوائم المساندة للواجهة، والتنبيهات
-- ---------------------------------------------------------------------
-- المواقع لكل حساب فعّال (ليختار موقع البلاغ)، والفنيون والأصول والإدارات لأهل القسم
create or replace function public.mt_lookups()
returns jsonb
language plpgsql stable security definer set search_path = public
as $$
declare
  v_staff boolean := public.mt_staff();
begin
  if not public.mt_me_ok() then
    return '{}'::jsonb;
  end if;
  return jsonb_build_object(
    'locations', coalesce((select jsonb_agg(jsonb_build_object('id', l.id, 'parent_id', l.parent_id, 'kind', l.kind, 'name', l.name)
                                              order by l.sort, l.name) from public.st_locations l where l.active), '[]'::jsonb),
    'technicians', case when v_staff then coalesce((
        select jsonb_agg(jsonb_build_object('employee_id', t.employee_id, 'name', e.full_name, 'emp_no', e.emp_no, 'phone', e.phone,
                                             'trade', t.trade, 'active', t.active, 'note', t.note, 'has_account', e.profile_id is not null)
                         order by e.full_name)
          from public.mt_technicians t join public.st_employees e on e.id = t.employee_id), '[]'::jsonb) else '[]'::jsonb end,
    'employees', case when public.mt_can_admin() then coalesce((
        select jsonb_agg(jsonb_build_object('id', e.id, 'name', e.full_name, 'emp_no', e.emp_no) order by e.full_name)
          from public.st_employees e where e.active), '[]'::jsonb) else '[]'::jsonb end,
    'assets', case when v_staff then coalesce((
        select jsonb_agg(jsonb_build_object('id', a.id, 'tag', a.tag, 'name', a.name, 'status', a.status, 'location_id', a.location_id,
                                             'warranty_until', a.warranty_until) order by a.tag)
          from public.st_assets a where a.status not in ('disposal', 'disposed')), '[]'::jsonb) else '[]'::jsonb end
  );
end;
$$;

-- التنبيهات: تُحسب لحظة الطلب بحدود الإعدادات؛ أهل القسم يرونها كلها، والفني ما يخص بلاغاته
create or replace function public.mt_alerts(p_as_of timestamptz default now())
returns table (kind text, severity text, ref_kind text, ref_id uuid, title text, detail text, since timestamptz)
language plpgsql stable security definer set search_path = public
as $$
declare
  v_all    boolean := public.mt_sees_all();
  v_me     uuid := public.st_my_employee();
  v_tech   boolean := public.has_grant('maintenance:tech');
  v_assign numeric := public.mt_setting_num('assign_hours', 4);
  v_hold   numeric := public.mt_setting_num('hold_days', 7);
  v_conf   numeric := public.mt_setting_num('confirm_days', 3);
  v_soon   numeric := public.mt_setting_num('soon_hours', 24);
  v_rep_n  numeric := public.mt_setting_num('repeat_count', 3);
  v_rep_d  numeric := public.mt_setting_num('repeat_days', 90);
begin
  if not (v_all or v_tech) then
    return;
  end if;
  return query
  -- متأخر عن موعده المستهدف (المعلّق لا يُحتسب)
  select 'overdue'::text, (case when r.priority in ('urgent', 'high') then 'critical' else 'warning' end)::text, 'request'::text,
         r.id, (r.req_no || ' — ' || r.title)::text, 'تجاوز الموعد المستهدف'::text, r.due_at
    from public.mt_requests r
   where r.status in ('new', 'assigned', 'in_progress') and r.due_at < p_as_of
     and (v_all or (v_tech and r.assignee_id is not distinct from v_me))
  union all
  -- جديد لم يُسنَد خلال المدة (ولم يتأخر بعد)
  select 'unassigned'::text, (case when r.priority in ('urgent', 'high') then 'critical' else 'warning' end)::text, 'request'::text,
         r.id, (r.req_no || ' — ' || r.title)::text, 'لم يُسنَد بعد'::text, r.reported_at
    from public.mt_requests r
   where v_all and r.status = 'new' and r.due_at >= p_as_of and r.reported_at < p_as_of - (v_assign || ' hours')::interval
  union all
  -- معلّق أطول من المدة
  select 'on_hold'::text, 'warning'::text, 'request'::text, r.id, (r.req_no || ' — ' || r.title)::text,
         ('معلّق: ' || r.hold_reason)::text, r.on_hold_at
    from public.mt_requests r
   where r.status = 'on_hold' and r.on_hold_at < p_as_of - (v_hold || ' days')::interval
     and (v_all or (v_tech and r.assignee_id is not distinct from v_me))
  union all
  -- قريب الاستحقاق
  select 'due_soon'::text, 'info'::text, 'request'::text, r.id, (r.req_no || ' — ' || r.title)::text,
         'يقترب موعده المستهدف'::text, r.due_at
    from public.mt_requests r
   where r.status in ('new', 'assigned', 'in_progress') and r.due_at >= p_as_of and r.due_at < p_as_of + (v_soon || ' hours')::interval
     and (v_all or (v_tech and r.assignee_id is not distinct from v_me))
  union all
  -- منجز ينتظر تأكيد صاحبه
  select 'awaiting_confirm'::text, 'info'::text, 'request'::text, r.id, (r.req_no || ' — ' || r.title)::text,
         'منجز وينتظر تأكيد صاحب البلاغ'::text, r.done_at
    from public.mt_requests r
   where v_all and r.status = 'done' and r.done_at < p_as_of - (v_conf || ' days')::interval
  union all
  -- أصل تحت الضمان وعليه بلاغ مفتوح: راجع المورد قبل الإصلاح
  select 'warranty'::text, 'info'::text, 'request'::text, r.id, (r.req_no || ' — ' || r.title)::text,
         ('الأصل ' || a.tag || ' تحت الضمان حتى ' || a.warranty_until::text)::text, r.reported_at
    from public.mt_requests r join public.st_assets a on a.id = r.asset_id
   where v_all and r.status in ('new', 'assigned', 'in_progress', 'on_hold') and a.warranty_until >= (p_as_of at time zone 'Africa/Tripoli')::date
  union all
  -- أصل تتكرر أعطاله
  select 'repeat'::text, 'warning'::text, 'asset'::text, a.id, (a.tag || ' — ' || a.name)::text,
         (count(*)::text || ' بلاغات خلال ' || v_rep_d::integer::text || ' يوماً')::text, max(r.reported_at)
    from public.mt_requests r join public.st_assets a on a.id = r.asset_id
   where v_all and r.source = 'report' and r.status not in ('rejected', 'cancelled')
     and r.reported_at >= p_as_of - (v_rep_d || ' days')::interval
   group by a.id, a.tag, a.name
  having count(*) >= v_rep_n;
end;
$$;

-- ---------------------------------------------------------------------
-- 8. سياسات القراءة والصلاحيات والتحديث اللحظي
-- ---------------------------------------------------------------------
alter table public.mt_settings enable row level security;
alter table public.mt_technicians enable row level security;
alter table public.mt_plans enable row level security;
alter table public.mt_requests enable row level security;
alter table public.mt_request_events enable row level security;

drop policy if exists mt_settings_read on public.mt_settings;
create policy mt_settings_read on public.mt_settings for select to authenticated using ((select public.mt_staff()));
drop policy if exists mt_technicians_read on public.mt_technicians;
create policy mt_technicians_read on public.mt_technicians for select to authenticated using ((select public.mt_staff()));
drop policy if exists mt_plans_read on public.mt_plans;
create policy mt_plans_read on public.mt_plans for select to authenticated using ((select public.mt_staff()));
-- البلاغات: أهل القسم كلها، وصاحب البلاغ بلاغاته، والفني المسنَد إليه بلاغاته
drop policy if exists mt_requests_read on public.mt_requests;
create policy mt_requests_read on public.mt_requests for select to authenticated
  using ((select public.mt_sees_all()) or reporter_id = (select auth.uid()) or (select public.mt_is_assignee(assignee_id)));
drop policy if exists mt_request_events_read on public.mt_request_events;
create policy mt_request_events_read on public.mt_request_events for select to authenticated
  using (exists (select 1 from public.mt_requests r where r.id = request_id));

revoke all on public.mt_settings, public.mt_technicians, public.mt_plans, public.mt_requests, public.mt_request_events
  from anon, authenticated;
grant select on public.mt_settings, public.mt_technicians, public.mt_plans, public.mt_requests, public.mt_request_events to authenticated;
grant all on public.mt_settings, public.mt_technicians, public.mt_plans, public.mt_requests, public.mt_request_events to service_role;

revoke execute on function public.mt_sees_all(), public.mt_staff(), public.mt_can_manage(), public.mt_can_admin(), public.mt_me_ok(),
  public.mt_can_report(), public.mt_is_assignee(uuid), public.mt_report(jsonb), public.mt_assign(uuid, jsonb),
  public.mt_progress(uuid, text, jsonb), public.mt_confirm(uuid, boolean, text, integer), public.mt_reject(uuid, text),
  public.mt_cancel(uuid, text), public.mt_comment(uuid, text), public.mt_save_plan(uuid, jsonb), public.mt_delete_plan(uuid),
  public.mt_generate_due(date), public.mt_save_settings(jsonb), public.mt_save_technician(uuid, jsonb), public.mt_lookups(),
  public.mt_alerts(timestamptz) from public, anon;
grant execute on function public.mt_sees_all(), public.mt_staff(), public.mt_can_manage(), public.mt_can_admin(), public.mt_me_ok(),
  public.mt_can_report(), public.mt_is_assignee(uuid), public.mt_report(jsonb), public.mt_assign(uuid, jsonb),
  public.mt_progress(uuid, text, jsonb), public.mt_confirm(uuid, boolean, text, integer), public.mt_reject(uuid, text),
  public.mt_cancel(uuid, text), public.mt_comment(uuid, text), public.mt_save_plan(uuid, jsonb), public.mt_delete_plan(uuid),
  public.mt_generate_due(date), public.mt_save_settings(jsonb), public.mt_save_technician(uuid, jsonb), public.mt_lookups(),
  public.mt_alerts(timestamptz) to authenticated;
-- داخلية: لا تُستدعى من التطبيق
revoke execute on function public.mt_setting_num(text, numeric), public.mt_sla_hours(text), public.mt_end_of_day(date),
  public.mt_occurrence(date, text, integer, integer), public.mt_event(uuid, text, jsonb, text),
  public.mt_notify_managers(text, text), public.mt_hold_asset(uuid), public.mt_release_asset(uuid),
  public.mt_resolve_asset(jsonb, boolean), public.mt_valid_category(text) from public, anon, authenticated;

do $$
declare
  t text;
begin
  foreach t in array array['mt_requests', 'mt_plans', 'mt_technicians', 'mt_settings'] loop
    if exists (select 1 from pg_publication where pubname = 'supabase_realtime')
       and not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = t) then
      execute format('alter publication supabase_realtime add table public.%I', t);
    end if;
  end loop;
end $$;
