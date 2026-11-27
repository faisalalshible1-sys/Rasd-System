-- =====================================================================
-- الإصدار 1.10.0 (الترحيل 41): قسم المشتريات — دورة الاحتياج حتى الاستلام
--
--  قسم مستقل عن القسم المالي وعن المخازن في صفحاته وصلاحياته، يرتبط ببطاقات الأصناف والمخازن والأصول (الترحيلان 38 و39)
--  ويستعمل دوالها عند الاستلام. لا قيود مالية ولا حسابات؛ الأسعار للمقارنة وتكلفة الأصل المستلَم. جداوله بالبادئة pr_:
--  1. طلب الاحتياج: يرفعه أي حساب فعّال (ومنه حساب الموظف) ببنود من بطاقات الأصناف أو وصف حر لما لا بطاقة له،
--     برقم PR-سنة-تسلسل، وأولوية وتاريخ احتياج وإدارة. مساره: مسودة ← مقدَّم ← مراجَع ← معتمَد ← مأمور ← مستلَم جزئياً ← مستلَم،
--     أو مكتفى من المخزون أو مرفوض أو ملغى.
--  2. مراجعة التوفر: مدير المخازن (أو المدير) يحدد لكل بند ما يُلبّى من الرصيد المتاح (لا يتجاوز المتاح فعلاً)؛
--     فإن لبّى المخزون الطلب كله صار «مكتفى من المخزون» وانتهى، وإلا انتقل الباقي للاعتماد.
--  3. الاعتماد: المدير وحده، وفصل المهام: من راجع الطلب لا يعتمده ما دام فصل المهام مفعّلاً في إعدادات المخازن.
--  4. عروض الأسعار: مسؤول المشتريات يسجّل عروض الموردين (إجمالي ومدة توريد وصلاحية) ويختار الفائز؛
--     وأمر الشراء لا يصدر بأقل من الحد الأدنى للعروض (إعداد، مبدئياً 3) إلا باستثناء مُعلَّل من المدير.
--  5. أمر الشراء PO-سنة-تسلسل: واحد لكل طلب، بأسعار الوحدة وتاريخ التوريد المتوقع ومخزن الاستلام؛ ويُلغى قبل أي استلام.
--  6. الاستلام: على دفعات. الأصناف الاستهلاكية تدخل في مستند استلام (مسودة) في قسم المخازن يعتمده أمين المخزن ويرحّله،
--     وبنود الأصول تُسجَّل أصولاً (واحد لكل وحدة بتكلفة الوحدة من أمر الشراء) بدوال سجل الأصول نفسها وصلاحياتها.
--  7. نطاقات صلاحية جديدة: procurement:admin (الموردون والإعدادات) وprocurement:buyer (العروض والأوامر) وprocurement:audit (اطلاع).
--     وتراجع التوفر لمدير المخازن. والقسم يظهر لكل حساب فعّال (عدا مسؤول الأمن) ليرفع طلباته ويتابعها.
--  يُشغَّل بعد 20261201000040_maintenance.sql، وإعادة تشغيله آمنة. التراجع: supabase/rollbacks/20261202000041_procurement_down.sql
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. الجداول
-- ---------------------------------------------------------------------
create table if not exists public.pr_settings (
  key        text primary key check (key in ('min_quotes', 'review_days', 'approve_days', 'grace_days')),
  value      jsonb not null,
  updated_at timestamptz not null default now(),
  updated_by uuid references public.profiles (id) on delete set null
);
create index if not exists pr_settings_updated_by_idx on public.pr_settings (updated_by);
insert into public.pr_settings (key, value) values
  ('min_quotes', '3'::jsonb),
  ('review_days', '3'::jsonb),
  ('approve_days', '3'::jsonb),
  ('grace_days', '3'::jsonb)
on conflict (key) do nothing;

create table if not exists public.pr_suppliers (
  id         uuid primary key default gen_random_uuid(),
  name       text not null check (length(btrim(name)) between 2 and 160),
  name_key   text generated always as (public.pm_text_norm(name)) stored,
  contact    text not null default '' check (length(contact) <= 120),
  phone      text not null default '' check (length(phone) <= 40),
  email      text not null default '' check (length(email) <= 120),
  address    text not null default '' check (length(address) <= 200),
  note       text not null default '' check (length(note) <= 500),
  active     boolean not null default true,
  created_at timestamptz not null default now(),
  created_by uuid references public.profiles (id) on delete set null,
  updated_at timestamptz not null default now(),
  updated_by uuid references public.profiles (id) on delete set null
);
create unique index if not exists pr_suppliers_name_uq on public.pr_suppliers (name_key);
create index if not exists pr_suppliers_created_by_idx on public.pr_suppliers (created_by);
create index if not exists pr_suppliers_updated_by_idx on public.pr_suppliers (updated_by);

create table if not exists public.pr_requests (
  id            uuid primary key default gen_random_uuid(),
  req_no        text not null,
  title         text not null check (length(btrim(title)) between 3 and 160),
  reason        text not null default '' check (length(reason) <= 2000),
  priority      text not null default 'normal' check (priority in ('low', 'normal', 'high', 'urgent')),
  status        text not null default 'draft'
                check (status in ('draft', 'submitted', 'reviewed', 'approved', 'ordered', 'partial', 'received', 'fulfilled', 'rejected', 'cancelled')),
  needed_by     date,
  department_id uuid references public.st_departments (id) on delete set null,
  requester_id  uuid references public.profiles (id) on delete set null,
  requester_name text not null default '' check (length(requester_name) <= 120),
  submitted_at  timestamptz,
  reviewed_at   timestamptz,
  reviewed_by   uuid references public.profiles (id) on delete set null,
  review_note   text not null default '' check (length(review_note) <= 500),
  decided_at    timestamptz,
  decided_by    uuid references public.profiles (id) on delete set null,
  decision_note text not null default '' check (length(decision_note) <= 500),
  closed_at     timestamptz,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  updated_by    uuid references public.profiles (id) on delete set null
);
create unique index if not exists pr_requests_no_uq on public.pr_requests (req_no);
create index if not exists pr_requests_status_idx on public.pr_requests (status);
create index if not exists pr_requests_requester_idx on public.pr_requests (requester_id);
create index if not exists pr_requests_department_idx on public.pr_requests (department_id);
create index if not exists pr_requests_reviewed_by_idx on public.pr_requests (reviewed_by);
create index if not exists pr_requests_decided_by_idx on public.pr_requests (decided_by);
create index if not exists pr_requests_updated_by_idx on public.pr_requests (updated_by);

create table if not exists public.pr_request_lines (
  id         uuid primary key default gen_random_uuid(),
  request_id uuid not null references public.pr_requests (id) on delete cascade,
  line_no    integer not null check (line_no between 1 and 200),
  item_id    uuid references public.st_items (id) on delete restrict,
  name       text not null check (length(btrim(name)) between 2 and 160),
  unit_id    uuid references public.st_units (id) on delete restrict,
  unit_name  text not null default '' check (length(unit_name) <= 40),
  qty        numeric(14, 3) not null check (qty > 0 and qty <= 100000000),
  stock_qty  numeric(14, 3) not null default 0 check (stock_qty >= 0),
  note       text not null default '' check (length(note) <= 300),
  constraint pr_request_lines_no_uq unique (request_id, line_no),
  constraint pr_request_lines_stock check (stock_qty <= qty)
);
create index if not exists pr_request_lines_item_idx on public.pr_request_lines (item_id);
create index if not exists pr_request_lines_unit_idx on public.pr_request_lines (unit_id);

create table if not exists public.pr_quotes (
  id            uuid primary key default gen_random_uuid(),
  request_id    uuid not null references public.pr_requests (id) on delete cascade,
  supplier_id   uuid not null references public.pr_suppliers (id) on delete restrict,
  total         numeric(14, 3) not null check (total >= 0 and total <= 999999999),
  delivery_days integer check (delivery_days between 0 and 730),
  valid_until   date,
  note          text not null default '' check (length(note) <= 500),
  selected      boolean not null default false,
  created_at    timestamptz not null default now(),
  created_by    uuid references public.profiles (id) on delete set null,
  updated_at    timestamptz not null default now(),
  updated_by    uuid references public.profiles (id) on delete set null,
  constraint pr_quotes_supplier_uq unique (request_id, supplier_id)
);
create unique index if not exists pr_quotes_selected_uq on public.pr_quotes (request_id) where selected;
create index if not exists pr_quotes_supplier_idx on public.pr_quotes (supplier_id);
create index if not exists pr_quotes_created_by_idx on public.pr_quotes (created_by);
create index if not exists pr_quotes_updated_by_idx on public.pr_quotes (updated_by);

create table if not exists public.pr_orders (
  id            uuid primary key default gen_random_uuid(),
  po_no         text not null,
  request_id    uuid not null references public.pr_requests (id) on delete restrict,
  supplier_id   uuid not null references public.pr_suppliers (id) on delete restrict,
  quote_id      uuid references public.pr_quotes (id) on delete set null,
  warehouse_id  uuid references public.st_warehouses (id) on delete restrict,
  status        text not null default 'issued' check (status in ('issued', 'partial', 'received', 'cancelled')),
  total         numeric(14, 3) not null default 0 check (total >= 0),
  expected_date date,
  waiver_note   text not null default '' check (length(waiver_note) <= 500),
  note          text not null default '' check (length(note) <= 500),
  issued_at     timestamptz not null default now(),
  issued_by     uuid references public.profiles (id) on delete set null,
  closed_at     timestamptz
);
create unique index if not exists pr_orders_no_uq on public.pr_orders (po_no);
create unique index if not exists pr_orders_one_live_uq on public.pr_orders (request_id) where status <> 'cancelled';
create index if not exists pr_orders_supplier_idx on public.pr_orders (supplier_id);
create index if not exists pr_orders_quote_idx on public.pr_orders (quote_id);
create index if not exists pr_orders_warehouse_idx on public.pr_orders (warehouse_id);
create index if not exists pr_orders_issued_by_idx on public.pr_orders (issued_by);

create table if not exists public.pr_order_lines (
  id          uuid primary key default gen_random_uuid(),
  order_id    uuid not null references public.pr_orders (id) on delete cascade,
  line_id     uuid not null references public.pr_request_lines (id) on delete restrict,
  item_id     uuid not null references public.st_items (id) on delete restrict,
  unit_id     uuid not null references public.st_units (id) on delete restrict,
  qty         numeric(14, 3) not null check (qty > 0),
  unit_price  numeric(14, 3) not null default 0 check (unit_price >= 0),
  received    numeric(14, 3) not null default 0 check (received >= 0),
  constraint pr_order_lines_uq unique (order_id, line_id),
  constraint pr_order_lines_received check (received <= qty)
);
create index if not exists pr_order_lines_line_idx on public.pr_order_lines (line_id);
create index if not exists pr_order_lines_item_idx on public.pr_order_lines (item_id);
create index if not exists pr_order_lines_unit_idx on public.pr_order_lines (unit_id);

create table if not exists public.pr_receipts (
  id          uuid primary key default gen_random_uuid(),
  order_id    uuid not null references public.pr_orders (id) on delete restrict,
  received_at timestamptz not null default now(),
  received_by uuid references public.profiles (id) on delete set null,
  invoice_no  text not null default '' check (length(invoice_no) <= 60),
  note        text not null default '' check (length(note) <= 500),
  doc_id      uuid references public.st_docs (id) on delete set null,
  asset_ids   uuid[] not null default '{}',
  lines       jsonb not null default '[]'::jsonb
);
create index if not exists pr_receipts_order_idx on public.pr_receipts (order_id);
create index if not exists pr_receipts_doc_idx on public.pr_receipts (doc_id);
create index if not exists pr_receipts_by_idx on public.pr_receipts (received_by);

create table if not exists public.pr_events (
  id         bigint generated always as identity primary key,
  request_id uuid not null references public.pr_requests (id) on delete cascade,
  kind       text not null check (kind in ('create', 'submit', 'review', 'reject', 'approve', 'decline', 'cancel', 'quote', 'select',
                                           'order', 'order_cancel', 'receive', 'comment', 'update')),
  at         timestamptz not null default now(),
  by_user    uuid references public.profiles (id) on delete set null,
  data       jsonb not null default '{}'::jsonb,
  note       text not null default ''
);
create index if not exists pr_events_req_idx on public.pr_events (request_id, id);
create index if not exists pr_events_by_idx on public.pr_events (by_user);

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
                     'maintenance:admin', 'maintenance:manager', 'maintenance:tech', 'maintenance:audit',
                     'procurement:admin', 'procurement:buyer', 'procurement:audit')
  end
$$;

alter table public.user_grants drop constraint if exists user_grants_scope_check;
alter table public.user_grants add constraint user_grants_scope_check check (
  scope ~ '^(form:[a-z0-9_]{1,40}|docs:(boq|letter|design|pm_view|pm_add|pm_duration|pm_dates|pm_approve)|supervision:reports|unit:[a-z_]{2,40}|swot|pm:(plan|track)|stores:(admin|manager|audit|assets)|stores:keeper:[0-9a-f-]{36}|maintenance:(admin|manager|tech|audit)|procurement:(admin|buyer|audit))$');

-- الأقسام: يضاف قسم المشتريات لكل حساب فعّال عدا مسؤول الأمن (يرفع طلباته ويتابعها)
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
    return array['maintenance', 'manual', 'procurement', 'stores'];
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
    s := s || array['maintenance', 'procurement'];
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
                   'chat', 'security', 'print', 'manual', 'stores', 'maintenance', 'procurement')
$$;

-- يرى كل طلبات القسم وعروضه وأوامره: المدير ومسؤولو المشتريات ومدير المخازن (للمراجعة) والمراجع
create or replace function public.pr_sees_all()
returns boolean
language sql stable security definer set search_path = public
as $$
  select public.is_director() or public.has_grant('procurement:admin') or public.has_grant('procurement:buyer')
      or public.has_grant('procurement:audit') or public.has_grant('stores:manager')
$$;

-- من أهل القسم (يرى صفحاته غير الطلبات الشخصية)
create or replace function public.pr_staff()
returns boolean
language sql stable security definer set search_path = public
as $$
  select public.pr_sees_all()
$$;

-- مراجعة التوفر: المدير ومدير المخازن
create or replace function public.pr_can_review()
returns boolean
language sql stable security definer set search_path = public
as $$
  select public.writes_allowed() and (public.is_director() or public.has_grant('stores:manager'))
$$;

-- العروض والأوامر: المدير ومسؤول المشتريات ومدير النظام في القسم
create or replace function public.pr_can_buy()
returns boolean
language sql stable security definer set search_path = public
as $$
  select public.writes_allowed()
     and (public.is_director() or public.has_grant('procurement:buyer') or public.has_grant('procurement:admin'))
$$;

-- الموردون والإعدادات: المدير ومدير النظام في القسم
create or replace function public.pr_can_admin()
returns boolean
language sql stable security definer set search_path = public
as $$
  select public.writes_allowed() and (public.is_director() or public.has_grant('procurement:admin'))
$$;

-- حساب فعّال غير مسؤول الأمن: يرفع الطلبات ويتابعها (ومنه حساب الموظف)
create or replace function public.pr_me_ok()
returns boolean
language sql stable security definer set search_path = public
as $$
  select exists (select 1 from public.profiles
                  where id = auth.uid() and active and role is not null and role::text <> 'security_auditor'
                    and (locked_until is null or locked_until <= now()))
     and public.mfa_ok()
$$;

create or replace function public.pr_can_request()
returns boolean
language sql stable security definer set search_path = public
as $$
  select public.pr_me_ok() and (public.is_director() or not public.setting_bool('security.freeze', false))
$$;

-- ---------------------------------------------------------------------
-- 3. أدوات داخلية
-- ---------------------------------------------------------------------
create or replace function public.pr_setting_num(p_key text, p_default numeric)
returns numeric
language sql stable security definer set search_path = public
as $$
  select coalesce((select case when jsonb_typeof(value) = 'number' then (value #>> '{}')::numeric end
                     from public.pr_settings where key = p_key), p_default)
$$;

create or replace function public.pr_event(p_req uuid, p_kind text, p_data jsonb, p_note text default '')
returns void
language sql security definer set search_path = public
as $$
  insert into public.pr_events (request_id, kind, by_user, data, note)
  values (p_req, p_kind, auth.uid(), coalesce(p_data, '{}'::jsonb), left(coalesce(p_note, ''), 500))
$$;

-- إشعار المدير ومن له صلاحية بعينها
create or replace function public.pr_notify(p_scopes text[], p_title text, p_body text)
returns void
language sql security definer set search_path = public
as $$
  select public.notify_user(u.id, 'procurement', p_title, p_body)
    from (select p.id from public.profiles p where p.role = 'director' and p.active
          union
          select g.user_id from public.user_grants g join public.profiles p on p.id = g.user_id
           where g.scope = any (p_scopes) and p.active) u
$$;

-- معامل وحدة لصنف (الأساسية 1)
create or replace function public.pr_factor(p_item uuid, p_unit uuid)
returns numeric
language sql stable security definer set search_path = public
as $$
  select case when i.base_unit_id = p_unit then 1
              else (select iu.factor from public.st_item_units iu where iu.item_id = i.id and iu.unit_id = p_unit) end
    from public.st_items i where i.id = p_item
$$;

-- المتاح من صنف في كل المخازن بوحدته الأساسية (الفعلي − المحجوز)
create or replace function public.pr_available(p_item uuid)
returns numeric
language sql stable security definer set search_path = public
as $$
  select coalesce(sum(s.on_hand - s.reserved), 0) from public.st_stock s where s.item_id = p_item
$$;

-- ---------------------------------------------------------------------
-- 4. طلب الاحتياج: الحفظ والتقديم والمراجعة والاعتماد والإلغاء
-- ---------------------------------------------------------------------
create or replace function public.pr_save_request(p_id uuid, p_data jsonb)
returns uuid
language plpgsql security definer set search_path = public
as $$
declare
  r       public.pr_requests;
  v_id    uuid := p_id;
  v_title text;
  v_prio  text;
  v_need  date;
  v_dep   uuid;
  v_name  text;
  v_no    text;
  l       jsonb;
  n       integer := 0;
  it      public.st_items;
  v_unit  uuid;
  v_uname text;
  v_lname text;
  v_qty   numeric;
begin
  if not public.pr_can_request() then
    raise exception 'رفع الطلبات لحساب فعّال' using errcode = '42501';
  end if;
  if jsonb_typeof(coalesce(p_data, 'null'::jsonb)) <> 'object' then
    raise exception 'بيانات غير صالحة' using errcode = '22023';
  end if;
  if p_id is not null then
    select * into r from public.pr_requests where id = p_id for update;
    if not found then
      raise exception 'الطلب غير موجود' using errcode = 'P0002';
    end if;
    if r.requester_id is distinct from auth.uid() then
      raise exception 'لا يعدّل الطلب إلا صاحبه' using errcode = '42501';
    end if;
    if r.status <> 'draft' then
      raise exception 'لا يُعدَّل إلا الطلب المسودة' using errcode = '22023';
    end if;
  end if;
  v_title := public.st_text(p_data, 'title', 160);
  if length(v_title) < 3 then
    raise exception 'اكتب عنواناً للطلب (3 أحرف فأكثر)' using errcode = '22023';
  end if;
  v_prio := coalesce(nullif(p_data ->> 'priority', ''), 'normal');
  if v_prio not in ('low', 'normal', 'high', 'urgent') then
    raise exception 'أولوية الطلب: منخفضة أو عادية أو عالية أو عاجلة' using errcode = '22023';
  end if;
  v_need := nullif(p_data ->> 'needed_by', '')::date;
  if v_need is not null and v_need < (now() at time zone 'Africa/Tripoli')::date - 1 then
    raise exception 'تاريخ الاحتياج في الماضي' using errcode = '22023';
  end if;
  v_dep := public.st_uuid(p_data, 'department_id');
  if v_dep is not null and not exists (select 1 from public.st_departments where id = v_dep) then
    raise exception 'الإدارة غير موجودة' using errcode = '22023';
  end if;
  if v_dep is null then
    select department_id into v_dep from public.st_employees where id = public.st_my_employee();
  end if;
  if jsonb_typeof(p_data -> 'lines') <> 'array' or jsonb_array_length(p_data -> 'lines') = 0 then
    raise exception 'أضف بنداً واحداً على الأقل' using errcode = '22023';
  end if;
  if jsonb_array_length(p_data -> 'lines') > 200 then
    raise exception 'الحد الأعلى 200 بند في الطلب' using errcode = '22023';
  end if;
  v_name := coalesce((select e.full_name from public.st_employees e where e.id = public.st_my_employee()), public.actor_name(auth.uid()));

  if p_id is null then
    v_no := public.st_next_no('pr_request', 'PR', extract(year from now())::integer, 4);
    insert into public.pr_requests (req_no, title, reason, priority, needed_by, department_id, requester_id, requester_name, updated_by)
    values (v_no, v_title, public.st_text(p_data, 'reason', 2000), v_prio, v_need, v_dep, auth.uid(), v_name, auth.uid())
    returning id into v_id;
    perform public.pr_event(v_id, 'create', jsonb_build_object('priority', v_prio), '');
  else
    v_no := r.req_no;
    update public.pr_requests
       set title = v_title, reason = public.st_text(p_data, 'reason', 2000), priority = v_prio, needed_by = v_need,
           department_id = v_dep, updated_at = now(), updated_by = auth.uid()
     where id = p_id;
    delete from public.pr_request_lines where request_id = p_id;
    perform public.pr_event(p_id, 'update', '{}'::jsonb, '');
  end if;

  for l in select x from jsonb_array_elements(p_data -> 'lines') x loop
    n := n + 1;
    it := null;
    if public.st_uuid(l, 'item_id') is not null then
      select * into it from public.st_items where id = public.st_uuid(l, 'item_id');
      if not found then
        raise exception 'البند %: الصنف غير موجود', n using errcode = '22023';
      end if;
      if not it.active then
        raise exception 'البند %: الصنف «%» موقوف', n, it.name using errcode = '22023';
      end if;
    end if;
    if jsonb_typeof(l -> 'qty') <> 'number' then
      raise exception 'البند %: الكمية رقم', n using errcode = '22023';
    end if;
    v_qty := round((l ->> 'qty')::numeric, 3);
    if v_qty <= 0 or v_qty > 100000000 then
      raise exception 'البند %: الكمية موجبة', n using errcode = '22023';
    end if;
    if it.id is not null then
      v_unit := coalesce(public.st_uuid(l, 'unit_id'), it.base_unit_id);
      if public.pr_factor(it.id, v_unit) is null then
        raise exception 'البند %: الوحدة غير معرّفة للصنف «%»', n, it.name using errcode = '22023';
      end if;
      v_lname := it.name;
      v_uname := '';
    else
      v_unit := null;
      v_lname := public.st_text(l, 'name', 160);
      v_uname := public.st_text(l, 'unit_name', 40);
      if length(v_lname) < 2 then
        raise exception 'البند %: اختر صنفاً أو اكتب وصف المطلوب', n using errcode = '22023';
      end if;
    end if;
    insert into public.pr_request_lines (request_id, line_no, item_id, name, unit_id, unit_name, qty, note)
    values (v_id, n, it.id, v_lname, v_unit, v_uname, v_qty, public.st_text(l, 'note', 300));
  end loop;

  perform public.write_audit('procurement.request', null, null,
    jsonb_build_object('op', case when p_id is null then 'create' else 'update' end, 'id', v_id, 'req_no', v_no, 'title', v_title,
                       'priority', v_prio, 'lines', n), v_no);
  return v_id;
end;
$$;

create or replace function public.pr_submit(p_id uuid)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  r public.pr_requests;
begin
  select * into r from public.pr_requests where id = p_id for update;
  if not found then
    raise exception 'الطلب غير موجود' using errcode = 'P0002';
  end if;
  if r.requester_id is distinct from auth.uid() or not public.pr_can_request() then
    raise exception 'يقدّم الطلب صاحبه' using errcode = '42501';
  end if;
  if r.status <> 'draft' then
    raise exception 'قُدّم الطلب من قبل' using errcode = '22023';
  end if;
  update public.pr_requests set status = 'submitted', submitted_at = now(), updated_at = now(), updated_by = auth.uid() where id = p_id;
  perform public.pr_event(p_id, 'submit', '{}'::jsonb, '');
  perform public.write_audit('procurement.submit', null, null, jsonb_build_object('id', p_id, 'req_no', r.req_no, 'title', r.title), r.req_no);
  perform public.pr_notify(array['stores:manager'], 'طلب احتياج جديد ' || r.req_no, r.title);
end;
$$;

-- مراجعة التوفر: ما يُلبّى من المخزون لكل بند، وربط البنود الحرة بأصناف
create or replace function public.pr_review(p_id uuid, p_data jsonb)
returns text
language plpgsql security definer set search_path = public
as $$
declare
  r      public.pr_requests;
  l      jsonb;
  ln     public.pr_request_lines;
  v_item uuid;
  v_stock numeric;
  v_fac  numeric;
  v_avail numeric;
  v_note text;
  v_buy  numeric;
  v_status text;
begin
  if not public.pr_can_review() then
    raise exception 'مراجعة التوفر لمدير المخازن أو المدير' using errcode = '42501';
  end if;
  select * into r from public.pr_requests where id = p_id for update;
  if not found then
    raise exception 'الطلب غير موجود' using errcode = 'P0002';
  end if;
  if r.status not in ('submitted', 'reviewed') then
    raise exception 'تُراجَع الطلبات المقدَّمة وحدها' using errcode = '22023';
  end if;
  v_note := public.st_text(p_data, 'note', 500);
  if jsonb_typeof(p_data -> 'lines') = 'array' then
    for l in select x from jsonb_array_elements(p_data -> 'lines') x loop
      select * into ln from public.pr_request_lines where id = public.st_uuid(l, 'line_id') and request_id = p_id for update;
      if not found then
        raise exception 'بند غير تابع للطلب' using errcode = '22023';
      end if;
      v_item := coalesce(public.st_uuid(l, 'item_id'), ln.item_id);
      if v_item is not null and not exists (select 1 from public.st_items where id = v_item and active) then
        raise exception 'البند %: الصنف غير موجود أو موقوف', ln.line_no using errcode = '22023';
      end if;
      -- ربط بند حر بصنف: تُؤخذ وحدته الأساسية
      if v_item is distinct from ln.item_id then
        update public.pr_request_lines
           set item_id = v_item, unit_id = (select base_unit_id from public.st_items where id = v_item), unit_name = ''
         where id = ln.id;
        select * into ln from public.pr_request_lines where id = ln.id;
      end if;
      v_stock := case when l ? 'stock_qty' then round(public.st_num(l, 'stock_qty', 0), 3) else ln.stock_qty end;
      if v_stock < 0 or v_stock > ln.qty then
        raise exception 'البند %: المُلبّى من المخزون بين الصفر والكمية المطلوبة', ln.line_no using errcode = '22023';
      end if;
      if v_stock > 0 then
        if ln.item_id is null then
          raise exception 'البند %: اربط البند بصنف قبل تلبيته من المخزون', ln.line_no using errcode = '22023';
        end if;
        v_fac := public.pr_factor(ln.item_id, ln.unit_id);
        v_avail := public.pr_available(ln.item_id);
        if v_stock * v_fac > v_avail then
          raise exception 'البند %: المتاح في المخزون أقل مما حددت', ln.line_no using errcode = '22023';
        end if;
      end if;
      update public.pr_request_lines set stock_qty = v_stock where id = ln.id;
    end loop;
  end if;
  select coalesce(sum(qty - stock_qty), 0) into v_buy from public.pr_request_lines where request_id = p_id;
  v_status := case when v_buy = 0 then 'fulfilled' else 'reviewed' end;
  update public.pr_requests
     set status = v_status, reviewed_at = now(), reviewed_by = auth.uid(), review_note = v_note,
         closed_at = case when v_status = 'fulfilled' then now() end, updated_at = now(), updated_by = auth.uid()
   where id = p_id;
  perform public.pr_event(p_id, 'review', jsonb_build_object('to_buy', v_buy, 'status', v_status), v_note);
  perform public.write_audit('procurement.review', null, null,
    jsonb_build_object('id', p_id, 'req_no', r.req_no, 'title', r.title, 'to_buy', v_buy, 'status', v_status, 'note', v_note), r.req_no);
  if v_status = 'reviewed' then
    perform public.pr_notify(array[]::text[], 'طلب احتياج ينتظر اعتمادك ' || r.req_no, r.title);
  else
    perform public.notify_user(r.requester_id, 'procurement', 'لُبّي طلبك من المخزون ' || r.req_no, 'اصرف احتياجك بمستند صرف من المخزن');
  end if;
  return v_status;
end;
$$;

-- رفض الطلب: مدير المخازن قبل الاعتماد، والمدير قبل الأمر
create or replace function public.pr_reject(p_id uuid, p_note text)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  r      public.pr_requests;
  v_note text := left(btrim(coalesce(p_note, '')), 500);
begin
  select * into r from public.pr_requests where id = p_id for update;
  if not found then
    raise exception 'الطلب غير موجود' using errcode = 'P0002';
  end if;
  if not (public.pr_can_review() or (public.is_director() and public.writes_allowed())) then
    raise exception 'رفض الطلب لمدير المخازن أو المدير' using errcode = '42501';
  end if;
  if r.status not in ('submitted', 'reviewed', 'approved') then
    raise exception 'لا يُرفض طلب غير مقدَّم أو بعد صدور أمره' using errcode = '22023';
  end if;
  if length(v_note) < 3 then
    raise exception 'اكتب سبب الرفض' using errcode = '22023';
  end if;
  update public.pr_requests
     set status = 'rejected', decision_note = v_note, decided_at = now(), decided_by = auth.uid(), closed_at = now(),
         updated_at = now(), updated_by = auth.uid()
   where id = p_id;
  perform public.pr_event(p_id, 'reject', jsonb_build_object('from', r.status), v_note);
  perform public.write_audit('procurement.reject', null, null,
    jsonb_build_object('id', p_id, 'req_no', r.req_no, 'title', r.title, 'from', r.status, 'note', v_note), r.req_no);
  perform public.notify_user(r.requester_id, 'procurement', 'رُفض طلبك ' || r.req_no, v_note);
end;
$$;

-- اعتماد المدير للشراء
create or replace function public.pr_decide(p_id uuid, p_approve boolean, p_note text default '')
returns void
language plpgsql security definer set search_path = public
as $$
declare
  r      public.pr_requests;
  v_note text := left(btrim(coalesce(p_note, '')), 500);
begin
  if not (public.is_director() and public.writes_allowed()) then
    raise exception 'اعتماد الشراء للمدير' using errcode = '42501';
  end if;
  select * into r from public.pr_requests where id = p_id for update;
  if not found then
    raise exception 'الطلب غير موجود' using errcode = 'P0002';
  end if;
  if r.status <> 'reviewed' then
    raise exception 'يُعتمد الطلب بعد مراجعة توفره' using errcode = '22023';
  end if;
  if public.st_setting_bool('separation', true) and r.reviewed_by = auth.uid() then
    raise exception 'فصل المهام: من راجع الطلب لا يعتمده' using errcode = '42501';
  end if;
  if not p_approve and length(v_note) < 3 then
    raise exception 'اكتب سبب الرفض' using errcode = '22023';
  end if;
  update public.pr_requests
     set status = case when p_approve then 'approved' else 'rejected' end, decision_note = v_note, decided_at = now(),
         decided_by = auth.uid(), closed_at = case when p_approve then null else now() end, updated_at = now(), updated_by = auth.uid()
   where id = p_id;
  perform public.pr_event(p_id, case when p_approve then 'approve' else 'decline' end, '{}'::jsonb, v_note);
  perform public.write_audit('procurement.decide', null, null,
    jsonb_build_object('id', p_id, 'req_no', r.req_no, 'title', r.title, 'approve', p_approve, 'note', v_note), r.req_no);
  perform public.notify_user(r.requester_id, 'procurement',
    case when p_approve then 'اعتُمد طلبك ' else 'رُفض طلبك ' end || r.req_no, case when p_approve then r.title else v_note end);
  if p_approve then
    perform public.pr_notify(array['procurement:buyer', 'procurement:admin'], 'طلب معتمد للشراء ' || r.req_no, r.title);
  end if;
end;
$$;

create or replace function public.pr_cancel(p_id uuid, p_note text default '')
returns void
language plpgsql security definer set search_path = public
as $$
declare
  r      public.pr_requests;
  v_note text := left(btrim(coalesce(p_note, '')), 500);
begin
  select * into r from public.pr_requests where id = p_id for update;
  if not found then
    raise exception 'الطلب غير موجود' using errcode = 'P0002';
  end if;
  if not ((r.requester_id = auth.uid() and r.status in ('draft', 'submitted') and public.pr_can_request())
          or ((public.pr_can_review() or public.pr_can_buy()) and r.status in ('draft', 'submitted', 'reviewed', 'approved'))) then
    raise exception 'يُلغي الطلب صاحبه قبل مراجعته أو أهل القسم قبل أمره' using errcode = '42501';
  end if;
  update public.pr_requests set status = 'cancelled', closed_at = now(), updated_at = now(), updated_by = auth.uid() where id = p_id;
  perform public.pr_event(p_id, 'cancel', jsonb_build_object('from', r.status), v_note);
  perform public.write_audit('procurement.cancel', null, null,
    jsonb_build_object('id', p_id, 'req_no', r.req_no, 'title', r.title, 'from', r.status, 'note', v_note), r.req_no);
end;
$$;

create or replace function public.pr_comment(p_id uuid, p_note text)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  r      public.pr_requests;
  v_note text := left(btrim(coalesce(p_note, '')), 500);
begin
  select * into r from public.pr_requests where id = p_id;
  if not found or not (public.pr_sees_all() or r.requester_id = auth.uid()) or not public.pr_me_ok() then
    raise exception 'الطلب غير موجود' using errcode = 'P0002';
  end if;
  if length(v_note) < 1 then
    raise exception 'اكتب التعليق' using errcode = '22023';
  end if;
  perform public.pr_event(p_id, 'comment', '{}'::jsonb, v_note);
  perform public.write_audit('procurement.comment', null, null,
    jsonb_build_object('id', p_id, 'req_no', r.req_no, 'title', r.title, 'note', v_note), r.req_no);
end;
$$;

-- ---------------------------------------------------------------------
-- 5. الموردون والعروض والأوامر
-- ---------------------------------------------------------------------
create or replace function public.pr_save_supplier(p_id uuid, p_data jsonb)
returns uuid
language plpgsql security definer set search_path = public
as $$
declare
  v_id   uuid := p_id;
  v_name text;
  old_r  public.pr_suppliers;
begin
  if not public.pr_can_admin() then
    raise exception 'الموردون لمدير النظام في المشتريات أو المدير' using errcode = '42501';
  end if;
  if jsonb_typeof(coalesce(p_data, 'null'::jsonb)) <> 'object' then
    raise exception 'بيانات غير صالحة' using errcode = '22023';
  end if;
  v_name := public.st_text(p_data, 'name', 160);
  if length(v_name) < 2 then
    raise exception 'اكتب اسم المورد' using errcode = '22023';
  end if;
  if p_id is null then
    insert into public.pr_suppliers (name, contact, phone, email, address, note, active, created_by, updated_by)
    values (v_name, public.st_text(p_data, 'contact', 120), public.st_text(p_data, 'phone', 40), public.st_text(p_data, 'email', 120),
            public.st_text(p_data, 'address', 200), public.st_text(p_data, 'note', 500), coalesce((p_data ->> 'active')::boolean, true),
            auth.uid(), auth.uid())
    returning id into v_id;
  else
    select * into old_r from public.pr_suppliers where id = p_id for update;
    if not found then
      raise exception 'المورد غير موجود' using errcode = 'P0002';
    end if;
    update public.pr_suppliers
       set name = v_name, contact = public.st_text(p_data, 'contact', 120), phone = public.st_text(p_data, 'phone', 40),
           email = public.st_text(p_data, 'email', 120), address = public.st_text(p_data, 'address', 200),
           note = public.st_text(p_data, 'note', 500), active = coalesce((p_data ->> 'active')::boolean, old_r.active),
           updated_at = now(), updated_by = auth.uid()
     where id = p_id;
  end if;
  perform public.write_audit('procurement.supplier', null, null,
    jsonb_build_object('op', case when p_id is null then 'create' else 'update' end, 'id', v_id, 'name', v_name), v_name);
  return v_id;
exception
  when unique_violation then
    raise exception 'مورد بهذا الاسم مسجَّل' using errcode = '23505';
end;
$$;

create or replace function public.pr_save_quote(p_request uuid, p_data jsonb)
returns uuid
language plpgsql security definer set search_path = public
as $$
declare
  r      public.pr_requests;
  v_sup  uuid := public.st_uuid(p_data, 'supplier_id');
  v_tot  numeric;
  v_days integer;
  v_id   uuid;
  s      public.pr_suppliers;
begin
  if not public.pr_can_buy() then
    raise exception 'العروض لمسؤول المشتريات أو المدير' using errcode = '42501';
  end if;
  select * into r from public.pr_requests where id = p_request for update;
  if not found then
    raise exception 'الطلب غير موجود' using errcode = 'P0002';
  end if;
  if r.status not in ('reviewed', 'approved') then
    raise exception 'تُسجَّل العروض على طلب مراجَع أو معتمد قبل أمره' using errcode = '22023';
  end if;
  select * into s from public.pr_suppliers where id = v_sup;
  if not found or not s.active then
    raise exception 'اختر مورداً فعّالاً' using errcode = '22023';
  end if;
  v_tot := public.st_num(p_data, 'total', null);
  if v_tot is null or v_tot < 0 or v_tot > 999999999 then
    raise exception 'إجمالي العرض رقم غير سالب' using errcode = '22023';
  end if;
  v_days := nullif(p_data ->> 'delivery_days', '')::integer;
  if v_days is not null and v_days not between 0 and 730 then
    raise exception 'مدة التوريد من 0 إلى 730 يوماً' using errcode = '22023';
  end if;
  insert into public.pr_quotes (request_id, supplier_id, total, delivery_days, valid_until, note, created_by, updated_by)
  values (p_request, v_sup, round(v_tot, 3), v_days, nullif(p_data ->> 'valid_until', '')::date, public.st_text(p_data, 'note', 500),
          auth.uid(), auth.uid())
  on conflict (request_id, supplier_id) do update
     set total = excluded.total, delivery_days = excluded.delivery_days, valid_until = excluded.valid_until, note = excluded.note,
         updated_at = now(), updated_by = auth.uid()
  returning id into v_id;
  perform public.pr_event(p_request, 'quote', jsonb_build_object('supplier', s.name, 'total', round(v_tot, 3)), '');
  perform public.write_audit('procurement.quote', null, null,
    jsonb_build_object('id', v_id, 'request', p_request, 'req_no', r.req_no, 'supplier', s.name, 'total', round(v_tot, 3)), r.req_no);
  return v_id;
end;
$$;

create or replace function public.pr_delete_quote(p_id uuid)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  q public.pr_quotes;
  r public.pr_requests;
begin
  if not public.pr_can_buy() then
    raise exception 'العروض لمسؤول المشتريات أو المدير' using errcode = '42501';
  end if;
  select * into q from public.pr_quotes where id = p_id for update;
  if not found then
    raise exception 'العرض غير موجود' using errcode = 'P0002';
  end if;
  select * into r from public.pr_requests where id = q.request_id;
  if r.status not in ('reviewed', 'approved') or exists (select 1 from public.pr_orders o where o.quote_id = p_id and o.status <> 'cancelled') then
    raise exception 'لا يُحذف عرض بُني عليه أمر شراء' using errcode = '22023';
  end if;
  delete from public.pr_quotes where id = p_id;
  perform public.write_audit('procurement.quote_delete', null, null,
    jsonb_build_object('id', p_id, 'request', q.request_id, 'req_no', r.req_no, 'total', q.total), r.req_no);
end;
$$;

-- إصدار أمر الشراء من طلب معتمد بالعرض المختار وأسعار الوحدات
create or replace function public.pr_issue_order(p_request uuid, p_data jsonb)
returns uuid
language plpgsql security definer set search_path = public
as $$
declare
  r       public.pr_requests;
  q       public.pr_quotes;
  v_quote uuid := public.st_uuid(p_data, 'quote_id');
  v_wh    uuid := public.st_uuid(p_data, 'warehouse_id');
  v_min   integer := public.pr_setting_num('min_quotes', 3)::integer;
  v_cnt   integer;
  v_waive text := public.st_text(p_data, 'waiver_note', 500);
  v_exp   date := nullif(p_data ->> 'expected_date', '')::date;
  ln      public.pr_request_lines;
  l       jsonb;
  v_price numeric;
  v_id    uuid;
  v_no    text;
  v_total numeric := 0;
begin
  if not public.pr_can_buy() then
    raise exception 'أمر الشراء لمسؤول المشتريات أو المدير' using errcode = '42501';
  end if;
  select * into r from public.pr_requests where id = p_request for update;
  if not found then
    raise exception 'الطلب غير موجود' using errcode = 'P0002';
  end if;
  if r.status <> 'approved' then
    raise exception 'يصدر الأمر لطلب معتمد' using errcode = '22023';
  end if;
  select * into q from public.pr_quotes where id = v_quote and request_id = p_request;
  if not found then
    raise exception 'اختر العرض الفائز' using errcode = '22023';
  end if;
  select count(*) into v_cnt from public.pr_quotes where request_id = p_request;
  if v_cnt < v_min then
    if length(v_waive) < 5 then
      raise exception 'العروض % أقل من الحد الأدنى %؛ يستثني المدير بسبب مكتوب', v_cnt, v_min using errcode = '22023';
    end if;
    if not public.is_director() then
      raise exception 'استثناء الحد الأدنى للعروض للمدير' using errcode = '42501';
    end if;
  else
    v_waive := '';
  end if;
  if v_exp is not null and v_exp < (now() at time zone 'Africa/Tripoli')::date then
    raise exception 'تاريخ التوريد المتوقع في الماضي' using errcode = '22023';
  end if;
  if v_wh is null or not exists (select 1 from public.st_warehouses where id = v_wh and active) then
    raise exception 'اختر مخزن الاستلام' using errcode = '22023';
  end if;
  if exists (select 1 from public.pr_request_lines x where x.request_id = p_request and x.qty > x.stock_qty and x.item_id is null) then
    raise exception 'اربط كل بند يُشترى بصنف قبل إصدار الأمر' using errcode = '22023';
  end if;
  v_no := public.st_next_no('pr_order', 'PO', extract(year from now())::integer, 4);
  insert into public.pr_orders (po_no, request_id, supplier_id, quote_id, warehouse_id, expected_date, waiver_note, note, issued_by)
  values (v_no, p_request, q.supplier_id, q.id, v_wh, v_exp, v_waive, public.st_text(p_data, 'note', 500), auth.uid())
  returning id into v_id;
  for ln in select * from public.pr_request_lines where request_id = p_request and qty > stock_qty order by line_no loop
    v_price := 0;
    for l in select x from jsonb_array_elements(coalesce(p_data -> 'lines', '[]'::jsonb)) x loop
      if public.st_uuid(l, 'line_id') = ln.id then
        v_price := round(public.st_num(l, 'unit_price', 0), 3);
      end if;
    end loop;
    if v_price < 0 or v_price > 999999999 then
      raise exception 'البند %: سعر الوحدة رقم غير سالب', ln.line_no using errcode = '22023';
    end if;
    insert into public.pr_order_lines (order_id, line_id, item_id, unit_id, qty, unit_price)
    values (v_id, ln.id, ln.item_id, ln.unit_id, ln.qty - ln.stock_qty, v_price);
    v_total := v_total + round((ln.qty - ln.stock_qty) * v_price, 3);
  end loop;
  update public.pr_orders set total = v_total where id = v_id;
  update public.pr_quotes set selected = (id = v_quote) where request_id = p_request;
  update public.pr_requests set status = 'ordered', updated_at = now(), updated_by = auth.uid() where id = p_request;
  perform public.pr_event(p_request, 'order', jsonb_build_object('po_no', v_no, 'total', v_total, 'waived', v_waive <> ''), v_waive);
  perform public.write_audit('procurement.order', null, null,
    jsonb_build_object('id', v_id, 'po_no', v_no, 'req_no', r.req_no, 'supplier', (select name from public.pr_suppliers where id = q.supplier_id),
                       'total', v_total, 'quotes', v_cnt, 'waiver', v_waive), v_no);
  perform public.notify_user(r.requester_id, 'procurement', 'صدر أمر شراء لطلبك ' || r.req_no, v_no);
  return v_id;
exception
  when unique_violation then
    raise exception 'للطلب أمر شراء قائم' using errcode = '23505';
end;
$$;

create or replace function public.pr_cancel_order(p_id uuid, p_note text default '')
returns void
language plpgsql security definer set search_path = public
as $$
declare
  o      public.pr_orders;
  r      public.pr_requests;
  v_note text := left(btrim(coalesce(p_note, '')), 500);
begin
  if not public.pr_can_buy() then
    raise exception 'إلغاء الأمر لمسؤول المشتريات أو المدير' using errcode = '42501';
  end if;
  select * into o from public.pr_orders where id = p_id for update;
  if not found then
    raise exception 'أمر الشراء غير موجود' using errcode = 'P0002';
  end if;
  if o.status <> 'issued' or exists (select 1 from public.pr_receipts where order_id = p_id) then
    raise exception 'لا يُلغى أمر بدأ استلامه' using errcode = '22023';
  end if;
  if length(v_note) < 3 then
    raise exception 'اكتب سبب الإلغاء' using errcode = '22023';
  end if;
  update public.pr_orders set status = 'cancelled', closed_at = now(), note = v_note where id = p_id;
  update public.pr_quotes set selected = false where request_id = o.request_id;
  update public.pr_requests set status = 'approved', updated_at = now(), updated_by = auth.uid() where id = o.request_id returning * into r;
  perform public.pr_event(o.request_id, 'order_cancel', jsonb_build_object('po_no', o.po_no), v_note);
  perform public.write_audit('procurement.order_cancel', null, null,
    jsonb_build_object('id', p_id, 'po_no', o.po_no, 'req_no', r.req_no, 'note', v_note), o.po_no);
end;
$$;

-- استلام دفعة من أمر الشراء: مستند استلام للاستهلاكي (مسودة في المخازن)، وأصول لكل وحدة من بنود الأصول
create or replace function public.pr_receive(p_order uuid, p_data jsonb)
returns jsonb
language plpgsql security definer set search_path = public
as $$
declare
  o       public.pr_orders;
  r       public.pr_requests;
  l       jsonb;
  ol      public.pr_order_lines;
  it      public.st_items;
  cat     public.st_categories;
  v_qty   numeric;
  v_lines jsonb := '[]'::jsonb;
  v_doc_lines jsonb := '[]'::jsonb;
  v_snap  jsonb := '[]'::jsonb;
  v_assets uuid[] := '{}';
  v_doc   uuid;
  v_inv   text := public.st_text(p_data, 'invoice_no', 60);
  v_date  date := coalesce(nullif(p_data ->> 'doc_date', '')::date, (now() at time zone 'Africa/Tripoli')::date);
  v_sup   text;
  v_aid   uuid;
  i       integer;
  v_left  numeric;
begin
  if not public.writes_allowed() or not (public.pr_can_buy() or public.st_staff()) then
    raise exception 'الاستلام لأمين المخزن أو مسؤول الأصول أو مدير المخازن أو مسؤول المشتريات' using errcode = '42501';
  end if;
  select * into o from public.pr_orders where id = p_order for update;
  if not found then
    raise exception 'أمر الشراء غير موجود' using errcode = 'P0002';
  end if;
  if o.status not in ('issued', 'partial') then
    raise exception 'لا يُستلم أمر مغلق أو ملغى' using errcode = '22023';
  end if;
  select * into r from public.pr_requests where id = o.request_id for update;
  if v_date > (now() at time zone 'Africa/Tripoli')::date + 1 then
    raise exception 'تاريخ الاستلام في المستقبل' using errcode = '22023';
  end if;
  select name into v_sup from public.pr_suppliers where id = o.supplier_id;
  if jsonb_typeof(p_data -> 'lines') <> 'array' or jsonb_array_length(p_data -> 'lines') = 0 then
    raise exception 'حدّد الكميات المستلَمة' using errcode = '22023';
  end if;
  for l in select x from jsonb_array_elements(p_data -> 'lines') x loop
    select * into ol from public.pr_order_lines where id = public.st_uuid(l, 'line_id') and order_id = p_order for update;
    if not found then
      raise exception 'بند غير تابع للأمر' using errcode = '22023';
    end if;
    v_qty := round(public.st_num(l, 'qty', 0), 3);
    if v_qty <= 0 then
      continue;
    end if;
    v_left := ol.qty - ol.received;
    if v_qty > v_left then
      raise exception 'الكمية المستلَمة تتجاوز المتبقي من البند (%)', v_left using errcode = '22023';
    end if;
    select * into it from public.st_items where id = ol.item_id;
    select * into cat from public.st_categories where id = it.category_id;
    if cat.kind = 'asset' then
      if v_qty <> trunc(v_qty) or v_qty > 200 then
        raise exception '«%»: كميات الأصول أعداد صحيحة حتى 200 في الدفعة', it.name using errcode = '22023';
      end if;
      -- أصل بتكلفة الوحدة؛ الأصل المقيس بوحدة أكبر من الأساسية يُسجَّل بتكلفة الوحدة المطلوبة كما هي
      for i in 1..v_qty::integer loop
        v_aid := public.st_save_asset(null, jsonb_build_object(
          'name', it.name, 'category_id', it.category_id, 'item_id', it.id, 'cost', ol.unit_price, 'supplier', v_sup,
          'invoice_no', v_inv, 'purchase_date', v_date, 'warehouse_id', o.warehouse_id, 'condition', 'new',
          'note', 'استلام ' || o.po_no));
        v_assets := v_assets || v_aid;
      end loop;
    else
      v_doc_lines := v_doc_lines || jsonb_build_object('item_id', ol.item_id, 'unit_id', ol.unit_id, 'qty', v_qty,
                                                       'expiry_date', nullif(l ->> 'expiry_date', ''), 'batch_no', coalesce(l ->> 'batch_no', ''));
    end if;
    update public.pr_order_lines set received = received + v_qty where id = ol.id;
    v_snap := v_snap || jsonb_build_object('line_id', ol.id, 'item', it.name, 'qty', v_qty, 'kind', cat.kind);
  end loop;
  if jsonb_array_length(v_snap) = 0 then
    raise exception 'حدّد كمية موجبة لبند واحد على الأقل' using errcode = '22023';
  end if;
  if jsonb_array_length(v_doc_lines) > 0 then
    v_doc := public.st_save_doc(null, jsonb_build_object(
      'kind', 'receipt', 'warehouse_id', o.warehouse_id, 'doc_date', v_date, 'party', v_sup, 'ref_no', o.po_no,
      'note', 'استلام أمر الشراء ' || o.po_no || case when v_inv <> '' then ' — فاتورة ' || v_inv else '' end, 'lines', v_doc_lines));
  end if;
  insert into public.pr_receipts (order_id, received_by, invoice_no, note, doc_id, asset_ids, lines)
  values (p_order, auth.uid(), v_inv, public.st_text(p_data, 'note', 500), v_doc, v_assets, v_snap);
  if exists (select 1 from public.pr_order_lines where order_id = p_order and received < qty) then
    update public.pr_orders set status = 'partial' where id = p_order;
    update public.pr_requests set status = 'partial', updated_at = now(), updated_by = auth.uid() where id = o.request_id;
  else
    update public.pr_orders set status = 'received', closed_at = now() where id = p_order;
    update public.pr_requests set status = 'received', closed_at = now(), updated_at = now(), updated_by = auth.uid() where id = o.request_id;
  end if;
  perform public.pr_event(o.request_id, 'receive', jsonb_build_object('po_no', o.po_no, 'lines', v_snap, 'assets', cardinality(v_assets),
                                                                        'doc', v_doc), public.st_text(p_data, 'note', 500));
  perform public.write_audit('procurement.receive', null, null,
    jsonb_build_object('order', p_order, 'po_no', o.po_no, 'req_no', r.req_no, 'lines', v_snap, 'assets', cardinality(v_assets),
                       'doc', v_doc, 'invoice_no', v_inv), o.po_no);
  perform public.notify_user(r.requester_id, 'procurement', 'استُلمت دفعة من طلبك ' || r.req_no, o.po_no);
  return jsonb_build_object('doc_id', v_doc, 'assets', cardinality(v_assets), 'status', (select status from public.pr_orders where id = p_order));
end;
$$;

-- ---------------------------------------------------------------------
-- 6. الإعدادات والبيانات المساعدة
-- ---------------------------------------------------------------------
create or replace function public.pr_save_settings(p_data jsonb)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  k     text;
  v     jsonb;
  v_old jsonb;
  v_min numeric;
  v_max numeric;
begin
  if not public.pr_can_admin() then
    raise exception 'الإعدادات لمدير النظام في المشتريات أو المدير' using errcode = '42501';
  end if;
  if jsonb_typeof(coalesce(p_data, 'null'::jsonb)) <> 'object' then
    raise exception 'بيانات غير صالحة' using errcode = '22023';
  end if;
  for k, v in select * from jsonb_each(p_data) loop
    if k not in ('min_quotes', 'review_days', 'approve_days', 'grace_days') then
      raise exception 'إعداد غير معروف: %', k using errcode = '22023';
    end if;
    v_min := case k when 'min_quotes' then 1 else 0 end;
    v_max := case k when 'min_quotes' then 10 else 60 end;
    if jsonb_typeof(v) <> 'number' or (v #>> '{}')::numeric <> round((v #>> '{}')::numeric)
       or (v #>> '{}')::numeric not between v_min and v_max then
      raise exception 'الإعداد %: عدد صحيح من % إلى %', k, v_min::integer, v_max::integer using errcode = '22023';
    end if;
    select value into v_old from public.pr_settings where key = k;
    if v_old is distinct from v then
      insert into public.pr_settings (key, value, updated_by) values (k, v, auth.uid())
      on conflict (key) do update set value = excluded.value, updated_at = now(), updated_by = excluded.updated_by;
      perform public.write_audit('procurement.settings', null, null, jsonb_build_object('key', k, 'from', v_old, 'to', v), k);
    end if;
  end loop;
end;
$$;

-- بيانات الاختيار لأي حساب: الأصناف والوحدات والإدارات، وللمراجعين المخازن والمتاح
create or replace function public.pr_lookups()
returns jsonb
language plpgsql stable security definer set search_path = public
as $$
declare
  v_rev boolean := public.pr_can_review() or public.pr_can_buy() or public.pr_staff();
begin
  if not public.pr_me_ok() then
    return '{}'::jsonb;
  end if;
  return jsonb_build_object(
    'items', coalesce((select jsonb_agg(jsonb_build_object('id', i.id, 'code', i.code, 'name', i.name, 'category_id', i.category_id,
                                                           'kind', c.kind, 'base_unit_id', i.base_unit_id,
                                                           'available', case when v_rev then public.pr_available(i.id) end)
                                         order by i.name)
                         from public.st_items i join public.st_categories c on c.id = i.category_id where i.active), '[]'::jsonb),
    'units', coalesce((select jsonb_agg(jsonb_build_object('id', u.id, 'name', u.name) order by u.name) from public.st_units u), '[]'::jsonb),
    'item_units', coalesce((select jsonb_agg(jsonb_build_object('item_id', iu.item_id, 'unit_id', iu.unit_id, 'factor', iu.factor))
                              from public.st_item_units iu), '[]'::jsonb),
    'departments', coalesce((select jsonb_agg(jsonb_build_object('id', d.id, 'name', d.name) order by d.name) from public.st_departments d), '[]'::jsonb),
    'warehouses', case when v_rev then coalesce((select jsonb_agg(jsonb_build_object('id', w.id, 'name', w.name) order by w.name)
                                                   from public.st_warehouses w where w.active), '[]'::jsonb) else '[]'::jsonb end
  );
end;
$$;

-- ---------------------------------------------------------------------
-- 7. سياسات القراءة والصلاحيات والتحديث اللحظي
-- ---------------------------------------------------------------------
alter table public.pr_settings enable row level security;
alter table public.pr_suppliers enable row level security;
alter table public.pr_requests enable row level security;
alter table public.pr_request_lines enable row level security;
alter table public.pr_quotes enable row level security;
alter table public.pr_orders enable row level security;
alter table public.pr_order_lines enable row level security;
alter table public.pr_receipts enable row level security;
alter table public.pr_events enable row level security;

drop policy if exists pr_settings_read on public.pr_settings;
create policy pr_settings_read on public.pr_settings for select to authenticated using ((select public.pr_staff()));
drop policy if exists pr_suppliers_read on public.pr_suppliers;
create policy pr_suppliers_read on public.pr_suppliers for select to authenticated using ((select public.pr_staff()));
drop policy if exists pr_requests_read on public.pr_requests;
create policy pr_requests_read on public.pr_requests for select to authenticated
  using (requester_id = (select auth.uid()) or ((select public.pr_sees_all()) and status <> 'draft'));
drop policy if exists pr_request_lines_read on public.pr_request_lines;
create policy pr_request_lines_read on public.pr_request_lines for select to authenticated
  using (exists (select 1 from public.pr_requests r where r.id = request_id));
drop policy if exists pr_quotes_read on public.pr_quotes;
create policy pr_quotes_read on public.pr_quotes for select to authenticated using ((select public.pr_staff()));
drop policy if exists pr_orders_read on public.pr_orders;
create policy pr_orders_read on public.pr_orders for select to authenticated
  using (exists (select 1 from public.pr_requests r where r.id = request_id));
drop policy if exists pr_order_lines_read on public.pr_order_lines;
create policy pr_order_lines_read on public.pr_order_lines for select to authenticated
  using (exists (select 1 from public.pr_orders o where o.id = order_id));
drop policy if exists pr_receipts_read on public.pr_receipts;
create policy pr_receipts_read on public.pr_receipts for select to authenticated
  using (exists (select 1 from public.pr_orders o where o.id = order_id));
drop policy if exists pr_events_read on public.pr_events;
create policy pr_events_read on public.pr_events for select to authenticated
  using (exists (select 1 from public.pr_requests r where r.id = request_id));

revoke all on public.pr_settings, public.pr_suppliers, public.pr_requests, public.pr_request_lines, public.pr_quotes,
  public.pr_orders, public.pr_order_lines, public.pr_receipts, public.pr_events from anon, authenticated;
grant select on public.pr_settings, public.pr_suppliers, public.pr_requests, public.pr_request_lines, public.pr_quotes,
  public.pr_orders, public.pr_order_lines, public.pr_receipts, public.pr_events to authenticated;
grant all on public.pr_settings, public.pr_suppliers, public.pr_requests, public.pr_request_lines, public.pr_quotes,
  public.pr_orders, public.pr_order_lines, public.pr_receipts, public.pr_events to service_role;

revoke execute on function public.pr_sees_all(), public.pr_staff(), public.pr_can_review(), public.pr_can_buy(), public.pr_can_admin(),
  public.pr_me_ok(), public.pr_can_request(), public.pr_save_request(uuid, jsonb), public.pr_submit(uuid), public.pr_review(uuid, jsonb),
  public.pr_reject(uuid, text), public.pr_decide(uuid, boolean, text), public.pr_cancel(uuid, text), public.pr_comment(uuid, text),
  public.pr_save_supplier(uuid, jsonb), public.pr_save_quote(uuid, jsonb), public.pr_delete_quote(uuid),
  public.pr_issue_order(uuid, jsonb), public.pr_cancel_order(uuid, text), public.pr_receive(uuid, jsonb),
  public.pr_save_settings(jsonb), public.pr_lookups() from public, anon;
grant execute on function public.pr_sees_all(), public.pr_staff(), public.pr_can_review(), public.pr_can_buy(), public.pr_can_admin(),
  public.pr_me_ok(), public.pr_can_request(), public.pr_save_request(uuid, jsonb), public.pr_submit(uuid), public.pr_review(uuid, jsonb),
  public.pr_reject(uuid, text), public.pr_decide(uuid, boolean, text), public.pr_cancel(uuid, text), public.pr_comment(uuid, text),
  public.pr_save_supplier(uuid, jsonb), public.pr_save_quote(uuid, jsonb), public.pr_delete_quote(uuid),
  public.pr_issue_order(uuid, jsonb), public.pr_cancel_order(uuid, text), public.pr_receive(uuid, jsonb),
  public.pr_save_settings(jsonb), public.pr_lookups() to authenticated;
-- داخلية: لا تُستدعى من التطبيق
revoke execute on function public.pr_setting_num(text, numeric), public.pr_event(uuid, text, jsonb, text),
  public.pr_notify(text[], text, text), public.pr_factor(uuid, uuid), public.pr_available(uuid) from public, anon, authenticated;

do $$
declare
  t text;
begin
  foreach t in array array['pr_requests', 'pr_orders', 'pr_quotes', 'pr_suppliers', 'pr_settings'] loop
    if exists (select 1 from pg_publication where pubname = 'supabase_realtime')
       and not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = t) then
      execute format('alter publication supabase_realtime add table public.%I', t);
    end if;
  end loop;
end $$;
