-- =====================================================================
-- الإصدار 1.8.0 (الترحيل 39): قسم المخازن — الأصول والعُهد والإهلاك
--
--  يبني على الترحيل 38 ولا يمس جداول المنظومة القائمة. كل جداوله جديدة بالبادئة st_:
--  1. سجل الأصول: رقم الأصل (ملصق QR)، الوصف والتصنيف، المصنع والموديل والرقم التسلسلي، الشراء والتكلفة والمورد
--     والضمان، طريقة الإهلاك والعمر والخردة، الحالة والوضع، الموقع والإدارة، والعهدة الحالية.
--  2. العُهد: تسليم أصل لموظف بمحضر مرقّم (CU-سنة-تسلسل) بحالته وملحقاته، وإرجاعه بحالته وملحقاته، وتأكيد الموظف
--     الاستلام والإرجاع من صفحته. عهدة واحدة مفتوحة للأصل.
--  3. دورة الحياة: النقل بين المواقع والإدارات والمخازن، وتغيير الحالة، والاستبعاد (إتلاف أو بيع أو إهداء أو فقد)
--     بطلب من مسؤول الأصول واعتماد مدير المخازن أو المدير، مع فصل المهام. كل حدث في سجل الأصل وفي سجل التدقيق.
--  4. الإهلاك يُحسب ولا يُقيَّد (لا أثر مالي): القسط الثابت شهرياً من تاريخ بدء الاستخدام:
--     المتراكم = أقل من (التكلفة − الخردة) و(التكلفة − الخردة) × الأشهر المنقضية ÷ العمر بالأشهر؛ القيمة الدفترية = التكلفة − المتراكم.
--     لكل تصنيف أصول سياسة افتراضية (العمر ونسبة الخردة) تُقترح للأصل الجديد فقط، ولا تُطبَّق على الأصول القائمة.
--  5. نطاق صلاحية جديد stores:assets (مسؤول الأصول).
--  يُشغَّل بعد 20261129000038_stores_foundation.sql، وإعادة تشغيله آمنة. التراجع: supabase/rollbacks/20261130000039_stores_assets_down.sql
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. الجداول
-- ---------------------------------------------------------------------
-- سياسة الإهلاك الافتراضية لكل تصنيف أصول (تُقترح للأصل الجديد وحده)
create table if not exists public.st_asset_policies (
  category_id uuid primary key references public.st_categories (id) on delete cascade,
  dep_method  text not null default 'straight' check (dep_method in ('straight', 'none')),
  life_months integer check (life_months between 1 and 600),
  salvage_pct numeric(5,2) not null default 0 check (salvage_pct between 0 and 100),
  updated_at  timestamptz not null default now(),
  updated_by  uuid references public.profiles (id) on delete set null,
  constraint st_asset_policies_life check (dep_method = 'none' or life_months is not null)
);
create index if not exists st_asset_policies_updated_by_idx on public.st_asset_policies (updated_by);

create table if not exists public.st_assets (
  id              uuid primary key default gen_random_uuid(),
  tag             text not null check (tag ~ '^[A-Za-z0-9._/-]{1,30}$'),
  name            text not null check (length(btrim(name)) between 2 and 160),
  name_key        text generated always as (public.pm_text_norm(name)) stored,
  category_id     uuid not null references public.st_categories (id) on delete restrict,
  item_id         uuid references public.st_items (id) on delete set null,
  manufacturer    text not null default '' check (length(manufacturer) <= 80),
  model           text not null default '' check (length(model) <= 80),
  serial_no       text not null default '' check (length(serial_no) <= 80),
  purchase_date   date,
  in_service_date date,
  cost            numeric(14,3) not null default 0 check (cost >= 0),
  supplier        text not null default '' check (length(supplier) <= 160),
  invoice_no      text not null default '' check (length(invoice_no) <= 60),
  warranty_until  date,
  dep_method      text not null default 'straight' check (dep_method in ('straight', 'none')),
  life_months     integer check (life_months between 1 and 600),
  salvage         numeric(14,3) not null default 0 check (salvage >= 0),
  status          text not null default 'available'
                  check (status in ('available', 'in_use', 'custody', 'maintenance', 'damaged', 'disposal', 'disposed')),
  condition       text not null default 'good' check (condition in ('new', 'good', 'fair', 'poor', 'damaged')),
  warehouse_id    uuid references public.st_warehouses (id) on delete restrict,
  location_id     uuid references public.st_locations (id) on delete restrict,
  department_id   uuid references public.st_departments (id) on delete restrict,
  employee_id     uuid references public.st_employees (id) on delete restrict,
  disposal_kind   text check (disposal_kind in ('scrap', 'sale', 'donate', 'lost', 'other')),
  disposal_reason text not null default '' check (length(disposal_reason) <= 500),
  disposal_value  numeric(14,3) check (disposal_value >= 0),
  disposal_date   date,
  disposal_requested_at timestamptz,
  disposal_requested_by uuid references public.profiles (id) on delete set null,
  disposed_at     timestamptz,
  disposed_by     uuid references public.profiles (id) on delete set null,
  decision_note   text not null default '' check (length(decision_note) <= 500),
  note            text not null default '' check (length(note) <= 1000),
  created_at      timestamptz not null default now(),
  created_by      uuid references public.profiles (id) on delete set null,
  updated_at      timestamptz not null default now(),
  updated_by      uuid references public.profiles (id) on delete set null,
  constraint st_assets_salvage check (salvage <= cost),
  constraint st_assets_life check (dep_method = 'none' or life_months is not null),
  constraint st_assets_custody check ((status = 'custody') = (employee_id is not null)),
  constraint st_assets_disposal check ((status in ('disposal', 'disposed')) = (disposal_kind is not null)),
  constraint st_assets_disposed check ((status = 'disposed') = (disposed_at is not null)),
  constraint st_assets_store check (warehouse_id is null or status in ('available', 'maintenance', 'damaged', 'disposal', 'disposed'))
);
create unique index if not exists st_assets_tag_uq on public.st_assets (lower(tag));
create unique index if not exists st_assets_serial_uq on public.st_assets (lower(serial_no)) where serial_no <> '';
create index if not exists st_assets_category_idx on public.st_assets (category_id);
create index if not exists st_assets_item_idx on public.st_assets (item_id);
create index if not exists st_assets_warehouse_idx on public.st_assets (warehouse_id);
create index if not exists st_assets_location_idx on public.st_assets (location_id);
create index if not exists st_assets_department_idx on public.st_assets (department_id);
create index if not exists st_assets_employee_idx on public.st_assets (employee_id);
create index if not exists st_assets_status_idx on public.st_assets (status);
create index if not exists st_assets_name_idx on public.st_assets (name_key);
create index if not exists st_assets_requested_by_idx on public.st_assets (disposal_requested_by);
create index if not exists st_assets_disposed_by_idx on public.st_assets (disposed_by);
create index if not exists st_assets_created_by_idx on public.st_assets (created_by);
create index if not exists st_assets_updated_by_idx on public.st_assets (updated_by);

-- محاضر العهدة: التسليم ثم الإرجاع على السطر نفسه
create table if not exists public.st_custody (
  id                  uuid primary key default gen_random_uuid(),
  custody_no          text not null,
  asset_id            uuid not null references public.st_assets (id) on delete restrict,
  employee_id         uuid not null references public.st_employees (id) on delete restrict,
  department_id       uuid references public.st_departments (id) on delete set null,
  location_id         uuid references public.st_locations (id) on delete set null,
  handed_on           date not null,
  handed_at           timestamptz not null default now(),
  handed_by           uuid references public.profiles (id) on delete set null,
  condition_out       text not null check (condition_out in ('new', 'good', 'fair', 'poor', 'damaged')),
  accessories_out     text not null default '' check (length(accessories_out) <= 500),
  note_out            text not null default '' check (length(note_out) <= 500),
  confirmed_at        timestamptz,
  confirmed_by        uuid references public.profiles (id) on delete set null,
  returned_on         date,
  returned_at         timestamptz,
  received_by         uuid references public.profiles (id) on delete set null,
  condition_in        text check (condition_in in ('new', 'good', 'fair', 'poor', 'damaged')),
  accessories_in      text not null default '' check (length(accessories_in) <= 500),
  note_in             text not null default '' check (length(note_in) <= 500),
  return_confirmed_at timestamptz,
  return_confirmed_by uuid references public.profiles (id) on delete set null,
  constraint st_custody_dates check (returned_on is null or returned_on >= handed_on),
  constraint st_custody_return check ((returned_on is null) = (condition_in is null) and (returned_on is null) = (returned_at is null)),
  constraint st_custody_return_confirm check (return_confirmed_at is null or returned_on is not null)
);
create unique index if not exists st_custody_no_uq on public.st_custody (custody_no);
-- عهدة مفتوحة واحدة للأصل
create unique index if not exists st_custody_open_uq on public.st_custody (asset_id) where returned_on is null;
create index if not exists st_custody_asset_idx on public.st_custody (asset_id);
create index if not exists st_custody_employee_idx on public.st_custody (employee_id);
create index if not exists st_custody_department_idx on public.st_custody (department_id);
create index if not exists st_custody_location_idx on public.st_custody (location_id);
create index if not exists st_custody_handed_by_idx on public.st_custody (handed_by);
create index if not exists st_custody_confirmed_by_idx on public.st_custody (confirmed_by);
create index if not exists st_custody_received_by_idx on public.st_custody (received_by);
create index if not exists st_custody_return_confirmed_by_idx on public.st_custody (return_confirmed_by);

-- سجل دورة حياة الأصل: لا يُعدَّل ولا يُحذف (يُحذف مع الأصل المحذوف خطأً قبل أي عهدة أو استبعاد)
create table if not exists public.st_asset_events (
  id       bigint generated always as identity primary key,
  asset_id uuid not null references public.st_assets (id) on delete cascade,
  kind     text not null check (kind in ('create', 'update', 'transfer', 'status', 'custody_out', 'custody_in',
                                         'dispose_request', 'dispose', 'dispose_reject')),
  at       timestamptz not null default now(),
  by_user  uuid references public.profiles (id) on delete set null,
  data     jsonb not null default '{}'::jsonb,
  note     text not null default ''
);
create index if not exists st_asset_events_asset_idx on public.st_asset_events (asset_id, id);
create index if not exists st_asset_events_by_idx on public.st_asset_events (by_user);

-- السياسات المبدئية لتصنيفَي الأصول في المستند: الأجهزة المكتبية 60 شهراً، والأثاث 120 شهراً، بلا خردة
insert into public.st_asset_policies (category_id, dep_method, life_months, salvage_pct)
select c.id, 'straight', case c.code when 'OFE' then 60 else 120 end, 0
  from public.st_categories c
 where c.code in ('OFE', 'FUR') and c.kind = 'asset'
on conflict (category_id) do nothing;

-- ---------------------------------------------------------------------
-- 2. الصلاحيات
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
                     'stores:admin', 'stores:manager', 'stores:audit', 'stores:assets')
  end
$$;

alter table public.user_grants drop constraint if exists user_grants_scope_check;
alter table public.user_grants add constraint user_grants_scope_check check (
  scope ~ '^(form:[a-z0-9_]{1,40}|docs:(boq|letter|design|pm_view|pm_add|pm_duration|pm_dates|pm_approve)|supervision:reports|unit:[a-z_]{2,40}|swot|pm:(plan|track)|stores:(admin|manager|audit|assets)|stores:keeper:[0-9a-f-]{36})$');

-- أهل القسم: من يرى القسم كله، ومسؤول الأصول، وأمناء المخازن
create or replace function public.st_staff()
returns boolean
language sql stable security definer set search_path = public
as $$
  select public.st_sees_all() or public.has_grant('stores:assets') or cardinality(public.st_my_warehouses()) > 0
$$;

-- يرى الأصول والعهد: من يرى القسم كله (المدير ومدير المخازن ومدير النظام في القسم والمراجع)، ومسؤول الأصول
create or replace function public.st_assets_sees()
returns boolean
language sql stable security definer set search_path = public
as $$
  select public.st_sees_all() or public.has_grant('stores:assets')
$$;

-- يسجّل الأصول ويسلّم العهد ويستلمها وينقل ويطلب الاستبعاد: المدير ومدير المخازن ومسؤول الأصول
create or replace function public.st_can_assets()
returns boolean
language sql stable security definer set search_path = public
as $$
  select public.writes_allowed()
     and (public.is_director() or public.has_grant('stores:manager') or public.has_grant('stores:assets'))
$$;

-- ---------------------------------------------------------------------
-- 3. أدوات: التاريخ، والأشهر المنقضية، والقيمة الدفترية، وحدث الأصل
-- ---------------------------------------------------------------------
create or replace function public.st_date(p_data jsonb, p_key text)
returns date
language plpgsql immutable set search_path = public
as $$
declare
  v text := nullif(btrim(coalesce(p_data ->> p_key, '')), '');
begin
  if v is null then
    return null;
  end if;
  if v !~ '^\d{4}-\d{2}-\d{2}$' then
    raise exception 'تاريخ غير صالح في الحقل %', p_key using errcode = '22023';
  end if;
  begin
    return v::date;
  exception when others then
    raise exception 'تاريخ غير صالح في الحقل %', p_key using errcode = '22023';
  end;
end;
$$;

-- الأشهر الكاملة المنقضية: فرق السنين × 12 + فرق الأشهر، ناقص شهر إن لم يبلغ اليوم يوم البداية
create or replace function public.st_months_between(p_from date, p_to date)
returns integer
language sql immutable set search_path = public
as $$
  select case when p_from is null or p_to is null or p_to < p_from then 0
    else (extract(year from p_to)::integer - extract(year from p_from)::integer) * 12
         + extract(month from p_to)::integer - extract(month from p_from)::integer
         - case when extract(day from p_to) < extract(day from p_from) then 1 else 0 end end
$$;

-- الإهلاك المتراكم بالقسط الثابت حتى تاريخ: أقل من (التكلفة − الخردة) و(التكلفة − الخردة) × الأشهر ÷ العمر
create or replace function public.st_accumulated(p_cost numeric, p_salvage numeric, p_method text, p_life integer,
                                                 p_start date, p_as_of date)
returns numeric
language sql immutable set search_path = public
as $$
  select case when p_method <> 'straight' or p_life is null or p_life <= 0 or p_start is null or p_as_of is null
              or p_cost <= p_salvage then 0::numeric
    else round(least(p_cost - p_salvage,
                     (p_cost - p_salvage) * public.st_months_between(p_start, p_as_of) / p_life), 3) end
$$;

-- القيمة الدفترية للأصل في تاريخ (تتوقف عند تاريخ استبعاده)
create or replace function public.st_book_value(a public.st_assets, p_as_of date)
returns numeric
language sql stable set search_path = public
as $$
  select a.cost - public.st_accumulated(a.cost, a.salvage, a.dep_method, a.life_months,
                                        coalesce(a.in_service_date, a.purchase_date),
                                        case when a.status = 'disposed' and a.disposal_date is not null
                                             then least(p_as_of, a.disposal_date) else p_as_of end)
$$;

create or replace function public.st_asset_event(p_asset uuid, p_kind text, p_data jsonb, p_note text default '')
returns void
language sql security definer set search_path = public
as $$
  insert into public.st_asset_events (asset_id, kind, by_user, data, note)
  values (p_asset, p_kind, auth.uid(), coalesce(p_data, '{}'::jsonb), left(coalesce(p_note, ''), 500))
$$;

-- لقطة الأصل للتدقيق (دون الحقول المشتقة)
create or replace function public.st_asset_row(p_id uuid)
returns jsonb
language sql stable security definer set search_path = public
as $$
  select to_jsonb(a) - 'name_key' from public.st_assets a where a.id = p_id
$$;

-- الوضع التلقائي للأصل غير المسلَّم: في مخزن أو بلا موقع ← متاح، وفي موقع أو إدارة دون مخزن ← مستخدم
create or replace function public.st_place_status(p_wh uuid, p_loc uuid, p_dep uuid)
returns text
language sql immutable set search_path = public
as $$
  select case when p_wh is null and (p_loc is not null or p_dep is not null) then 'in_use' else 'available' end
$$;

-- ---------------------------------------------------------------------
-- 4. التهيئة: التصنيف لا يتحول إلى استهلاكي وفيه أصول، والحذف يراعي الأصول والعهد، وسياسة الإهلاك
-- ---------------------------------------------------------------------
create or replace function public.st_save_category(p_id uuid, p_data jsonb)
returns uuid
language plpgsql security definer set search_path = public
as $$
declare
  old_r  public.st_categories;
  v_id   uuid := p_id;
  v_par  uuid;
  v_name text;
  v_code text;
  v_kind text := coalesce(p_data ->> 'kind', 'consumable');
  v_cur  uuid;
  i      integer := 0;
begin
  if not public.st_can_setup() then
    raise exception 'تهيئة المخازن لمدير النظام في القسم أو المدير' using errcode = '42501';
  end if;
  if jsonb_typeof(coalesce(p_data, 'null'::jsonb)) <> 'object' then
    raise exception 'بيانات غير صالحة' using errcode = '22023';
  end if;
  if v_kind not in ('consumable', 'asset') then
    raise exception 'نوع التصنيف استهلاكي أو أصل' using errcode = '22023';
  end if;
  v_name := public.st_text(p_data, 'name', 80);
  v_code := upper(public.st_text(p_data, 'code', 8));
  if length(v_name) < 2 then
    raise exception 'اكتب اسم التصنيف' using errcode = '22023';
  end if;
  if v_code !~ '^[A-Z0-9]{2,8}$' then
    raise exception 'رمز التصنيف من 2 إلى 8 حروف لاتينية كبيرة أو أرقام' using errcode = '22023';
  end if;
  v_par := public.st_uuid(p_data, 'parent_id');
  if v_par is not null and not exists (select 1 from public.st_categories where id = v_par) then
    raise exception 'التصنيف الأعلى غير موجود' using errcode = '22023';
  end if;
  v_cur := v_par;
  while v_cur is not null loop
    if v_cur = p_id then
      raise exception 'لا يكون التصنيف فرعاً من نفسه' using errcode = '22023';
    end if;
    i := i + 1;
    exit when i > 20;
    select parent_id into v_cur from public.st_categories where id = v_cur;
  end loop;
  if p_id is not null and v_kind <> 'asset' and exists (select 1 from public.st_assets where category_id = p_id) then
    raise exception 'في التصنيف أصول مسجلة؛ لا يتحول إلى استهلاكي' using errcode = '23503';
  end if;
  if p_id is null then
    insert into public.st_categories (parent_id, code, name, kind, active, sort, created_by, updated_by)
    values (v_par, v_code, v_name, v_kind, coalesce((p_data ->> 'active')::boolean, true),
            coalesce((p_data ->> 'sort')::integer, 0), auth.uid(), auth.uid())
    returning id into v_id;
  else
    select * into old_r from public.st_categories where id = p_id for update;
    if not found then
      raise exception 'التصنيف غير موجود' using errcode = 'P0002';
    end if;
    update public.st_categories
       set parent_id = v_par, code = v_code, name = v_name, kind = v_kind,
           active = coalesce((p_data ->> 'active')::boolean, active), sort = coalesce((p_data ->> 'sort')::integer, sort),
           updated_at = now(), updated_by = auth.uid()
     where id = p_id;
  end if;
  perform public.write_audit('stores.setup', null, null,
    jsonb_build_object('entity', 'category', 'op', case when p_id is null then 'create' else 'update' end, 'id', v_id,
                       'name', v_name, 'code', v_code, 'from', case when p_id is null then null else to_jsonb(old_r) - 'name_key' end),
    v_name);
  return v_id;
exception
  when unique_violation then
    raise exception 'يوجد تصنيف بالاسم أو الرمز نفسه' using errcode = '23505';
end;
$$;

-- حذف عنصر تهيئة لا يرتبط به شيء (وإلا فإيقافه)
create or replace function public.st_delete_setup(p_entity text, p_id uuid)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  v_name text;
  v_row  jsonb;
begin
  if p_entity in ('item') then
    if not public.st_can_items() then
      raise exception 'بطاقات الأصناف لمدير المخازن أو مدير النظام في القسم' using errcode = '42501';
    end if;
  elsif not public.st_can_setup() then
    raise exception 'تهيئة المخازن لمدير النظام في القسم أو المدير' using errcode = '42501';
  end if;
  case p_entity
    when 'department' then
      select to_jsonb(d) - 'name_key', d.name into v_row, v_name from public.st_departments d where id = p_id;
      if exists (select 1 from public.st_departments where parent_id = p_id)
         or exists (select 1 from public.st_employees where department_id = p_id)
         or exists (select 1 from public.st_docs where department_id = p_id)
         or exists (select 1 from public.st_assets where department_id = p_id) then
        raise exception 'الإدارة مرتبطة بإدارات أو موظفين أو مستندات أو أصول؛ أوقفها بدل حذفها' using errcode = '23503';
      end if;
      delete from public.st_departments where id = p_id;
    when 'location' then
      select to_jsonb(l) - 'name_key', l.name into v_row, v_name from public.st_locations l where id = p_id;
      if exists (select 1 from public.st_locations where parent_id = p_id)
         or exists (select 1 from public.st_warehouses where location_id = p_id)
         or exists (select 1 from public.st_assets where location_id = p_id) then
        raise exception 'الموقع تتبعه مواقع أو مخازن أو أصول؛ أوقفه بدل حذفه' using errcode = '23503';
      end if;
      delete from public.st_locations where id = p_id;
    when 'warehouse' then
      select to_jsonb(w) - 'name_key', w.name into v_row, v_name from public.st_warehouses w where id = p_id;
      if exists (select 1 from public.st_docs where warehouse_id = p_id or to_warehouse_id = p_id)
         or exists (select 1 from public.st_stock where warehouse_id = p_id)
         or exists (select 1 from public.st_warehouses where parent_id = p_id)
         or exists (select 1 from public.st_assets where warehouse_id = p_id) then
        raise exception 'للمخزن مستندات أو رصيد أو مخازن فرعية أو أصول؛ أوقفه بدل حذفه' using errcode = '23503';
      end if;
      delete from public.user_grants where scope = 'stores:keeper:' || p_id::text;
      delete from public.st_warehouses where id = p_id;
    when 'category' then
      select to_jsonb(c) - 'name_key', c.name into v_row, v_name from public.st_categories c where id = p_id;
      if exists (select 1 from public.st_categories where parent_id = p_id)
         or exists (select 1 from public.st_items where category_id = p_id)
         or exists (select 1 from public.st_assets where category_id = p_id) then
        raise exception 'التصنيف فيه أصناف أو أصول أو تصنيفات فرعية؛ أوقفه بدل حذفه' using errcode = '23503';
      end if;
      delete from public.st_categories where id = p_id;
    when 'unit' then
      select to_jsonb(u) - 'name_key', u.name into v_row, v_name from public.st_units u where id = p_id;
      if exists (select 1 from public.st_items where base_unit_id = p_id)
         or exists (select 1 from public.st_item_units where unit_id = p_id)
         or exists (select 1 from public.st_doc_lines where unit_id = p_id) then
        raise exception 'الوحدة مستعملة في أصناف أو مستندات؛ أوقفها بدل حذفها' using errcode = '23503';
      end if;
      delete from public.st_units where id = p_id;
    when 'employee' then
      select to_jsonb(e) - 'name_key', e.full_name into v_row, v_name from public.st_employees e where id = p_id;
      if exists (select 1 from public.st_docs where employee_id = p_id) then
        raise exception 'للموظف مستندات صرف أو إرجاع؛ أوقفه بدل حذفه' using errcode = '23503';
      end if;
      if exists (select 1 from public.st_custody where employee_id = p_id) then
        raise exception 'للموظف عهد مسجلة؛ أوقفه بدل حذفه' using errcode = '23503';
      end if;
      delete from public.st_employees where id = p_id;
    when 'item' then
      select to_jsonb(i) - 'name_key', i.name into v_row, v_name from public.st_items i where id = p_id;
      if exists (select 1 from public.st_doc_lines where item_id = p_id)
         or exists (select 1 from public.st_stock where item_id = p_id) then
        raise exception 'للصنف حركات أو رصيد؛ أوقفه بدل حذفه' using errcode = '23503';
      end if;
      delete from public.st_items where id = p_id;
    else
      raise exception 'نوع غير معروف' using errcode = '22023';
  end case;
  if v_row is null then
    raise exception 'غير موجود' using errcode = 'P0002';
  end if;
  perform public.write_audit(case when p_entity = 'employee' then 'stores.employee' when p_entity = 'item' then 'stores.item'
                                  else 'stores.setup' end,
    null, null, jsonb_build_object('entity', p_entity, 'op', 'delete', 'id', p_id, 'name', v_name, 'from', v_row), v_name);
end;
$$;

-- سياسة الإهلاك الافتراضية لتصنيف أصول: تُقترح للأصل الجديد، ولا تغيّر الأصول المسجلة
create or replace function public.st_save_asset_policy(p_category uuid, p_data jsonb)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  v_cat    public.st_categories;
  v_old    jsonb;
  v_method text := coalesce(p_data ->> 'dep_method', 'straight');
  v_life   numeric;
  v_pct    numeric;
begin
  if not public.st_can_setup() then
    raise exception 'سياسات الإهلاك لمدير النظام في القسم أو المدير' using errcode = '42501';
  end if;
  if jsonb_typeof(coalesce(p_data, 'null'::jsonb)) <> 'object' then
    raise exception 'بيانات غير صالحة' using errcode = '22023';
  end if;
  select * into v_cat from public.st_categories where id = p_category;
  if not found then
    raise exception 'التصنيف غير موجود' using errcode = 'P0002';
  end if;
  if v_cat.kind <> 'asset' then
    raise exception 'سياسة الإهلاك لتصنيفات الأصول وحدها' using errcode = '22023';
  end if;
  if v_method not in ('straight', 'none') then
    raise exception 'طريقة الإهلاك: قسط ثابت أو بلا إهلاك' using errcode = '22023';
  end if;
  v_life := public.st_num(p_data, 'life_months', null);
  v_pct := public.st_num(p_data, 'salvage_pct', 0);
  if v_method = 'straight' and (v_life is null or v_life <> round(v_life) or v_life not between 1 and 600) then
    raise exception 'العمر بالأشهر عدد صحيح من 1 إلى 600' using errcode = '22023';
  end if;
  if v_pct < 0 or v_pct > 100 then
    raise exception 'نسبة الخردة من 0 إلى 100' using errcode = '22023';
  end if;
  select to_jsonb(p) into v_old from public.st_asset_policies p where category_id = p_category;
  insert into public.st_asset_policies (category_id, dep_method, life_months, salvage_pct, updated_at, updated_by)
  values (p_category, v_method, case when v_method = 'straight' then v_life::integer end, round(v_pct, 2), now(), auth.uid())
  on conflict (category_id) do update
    set dep_method = excluded.dep_method, life_months = excluded.life_months, salvage_pct = excluded.salvage_pct,
        updated_at = now(), updated_by = auth.uid();
  perform public.write_audit('stores.asset_policy', null, null,
    jsonb_build_object('category', v_cat.code, 'name', v_cat.name, 'from', v_old,
                       'to', jsonb_build_object('dep_method', v_method, 'life_months', case when v_method = 'straight' then v_life::integer end,
                                                'salvage_pct', round(v_pct, 2))),
    v_cat.name);
end;
$$;

-- ---------------------------------------------------------------------
-- 5. سجل الأصول
-- ---------------------------------------------------------------------
create or replace function public.st_save_asset(p_id uuid, p_data jsonb)
returns uuid
language plpgsql security definer set search_path = public
as $$
declare
  old_r    public.st_assets;
  v_id     uuid := p_id;
  v_cat    public.st_categories;
  v_pol    public.st_asset_policies;
  v_tag    text;
  v_name   text;
  v_item   uuid;
  v_cost   numeric;
  v_salv   numeric;
  v_method text;
  v_life   numeric;
  v_buy    date;
  v_start  date;
  v_warr   date;
  v_cond   text;
  v_wh     uuid;
  v_loc    uuid;
  v_dep    uuid;
  v_serial text;
begin
  if not public.st_can_assets() then
    raise exception 'سجل الأصول لمسؤول الأصول أو مدير المخازن أو المدير' using errcode = '42501';
  end if;
  if jsonb_typeof(coalesce(p_data, 'null'::jsonb)) <> 'object' then
    raise exception 'بيانات غير صالحة' using errcode = '22023';
  end if;
  if p_id is not null then
    select * into old_r from public.st_assets where id = p_id for update;
    if not found then
      raise exception 'الأصل غير موجود' using errcode = 'P0002';
    end if;
    if old_r.status in ('disposal', 'disposed') then
      raise exception 'الأصل مستبعد أو بانتظار اعتماد استبعاده؛ لا تُعدَّل بياناته' using errcode = '22023';
    end if;
  end if;
  v_name := public.st_text(p_data, 'name', 160);
  if length(v_name) < 2 then
    raise exception 'اكتب وصف الأصل' using errcode = '22023';
  end if;
  select * into v_cat from public.st_categories where id = public.st_uuid(p_data, 'category_id');
  if not found then
    raise exception 'اختر تصنيف الأصل' using errcode = '22023';
  end if;
  if v_cat.kind <> 'asset' then
    raise exception 'التصنيف «%» استهلاكي؛ اختر تصنيف أصول', v_cat.name using errcode = '22023';
  end if;
  if p_id is null and not v_cat.active then
    raise exception 'التصنيف «%» موقوف', v_cat.name using errcode = '22023';
  end if;
  v_item := public.st_uuid(p_data, 'item_id');
  if v_item is not null and not exists (select 1 from public.st_items where id = v_item) then
    raise exception 'الصنف المرتبط غير موجود' using errcode = '22023';
  end if;
  v_cost := public.st_num(p_data, 'cost', 0);
  if v_cost < 0 or v_cost > 999999999 then
    raise exception 'التكلفة رقم موجب' using errcode = '22023';
  end if;
  v_cost := round(v_cost, 3);
  v_buy := public.st_date(p_data, 'purchase_date');
  v_start := coalesce(public.st_date(p_data, 'in_service_date'), v_buy);
  v_warr := public.st_date(p_data, 'warranty_until');
  if v_buy is not null and v_buy > (now() at time zone 'Africa/Tripoli')::date then
    raise exception 'تاريخ الشراء في المستقبل' using errcode = '22023';
  end if;
  if v_buy is not null and v_start < v_buy then
    raise exception 'بدء الاستخدام قبل تاريخ الشراء' using errcode = '22023';
  end if;
  -- الإهلاك: ما أُرسل، وإلا فسياسة التصنيف (للأصل الجديد)، وإلا فما كان
  select * into v_pol from public.st_asset_policies where category_id = v_cat.id;
  v_method := coalesce(p_data ->> 'dep_method', old_r.dep_method, v_pol.dep_method, 'straight');
  if v_method not in ('straight', 'none') then
    raise exception 'طريقة الإهلاك: قسط ثابت أو بلا إهلاك' using errcode = '22023';
  end if;
  if p_data ? 'life_months' then
    v_life := public.st_num(p_data, 'life_months', null);
  elsif p_id is null then
    v_life := v_pol.life_months;
  else
    v_life := old_r.life_months;
  end if;
  if v_method = 'none' then
    v_life := null;
  elsif v_life is null then
    raise exception 'حدد عمر الأصل بالأشهر، أو اجعله «بلا إهلاك»' using errcode = '22023';
  elsif v_life <> round(v_life) or v_life not between 1 and 600 then
    raise exception 'العمر بالأشهر عدد صحيح من 1 إلى 600' using errcode = '22023';
  end if;
  if p_data ? 'salvage' then
    v_salv := round(public.st_num(p_data, 'salvage', 0), 3);
  elsif p_id is null then
    v_salv := round(v_cost * coalesce(v_pol.salvage_pct, 0) / 100, 3);
  else
    v_salv := least(old_r.salvage, v_cost);
  end if;
  if v_salv < 0 or v_salv > v_cost then
    raise exception 'قيمة الخردة بين الصفر والتكلفة' using errcode = '22023';
  end if;
  v_cond := coalesce(p_data ->> 'condition', old_r.condition, 'good');
  if v_cond not in ('new', 'good', 'fair', 'poor', 'damaged') then
    raise exception 'حالة الأصل غير معروفة' using errcode = '22023';
  end if;
  v_serial := public.st_text(p_data, 'serial_no', 80);
  v_tag := public.st_text(p_data, 'tag', 30);
  if v_tag <> '' and v_tag !~ '^[A-Za-z0-9._/-]{1,30}$' then
    raise exception 'رقم الأصل حروف لاتينية وأرقام و . _ / - فقط' using errcode = '22023';
  end if;

  if p_id is null then
    v_wh := public.st_uuid(p_data, 'warehouse_id');
    v_loc := public.st_uuid(p_data, 'location_id');
    v_dep := public.st_uuid(p_data, 'department_id');
    if v_wh is not null then
      select location_id into v_loc from public.st_warehouses where id = v_wh and active;
      if not found then
        raise exception 'المخزن غير موجود أو موقوف' using errcode = '22023';
      end if;
    end if;
    if v_loc is not null and not exists (select 1 from public.st_locations where id = v_loc) then
      raise exception 'الموقع غير موجود' using errcode = '22023';
    end if;
    if v_dep is not null and not exists (select 1 from public.st_departments where id = v_dep) then
      raise exception 'الإدارة غير موجودة' using errcode = '22023';
    end if;
    if v_tag = '' then
      v_tag := public.st_next_no('asset:' || v_cat.code, v_cat.code || '-A', 0, 4);
    end if;
    insert into public.st_assets (tag, name, category_id, item_id, manufacturer, model, serial_no, purchase_date,
                                  in_service_date, cost, supplier, invoice_no, warranty_until, dep_method, life_months,
                                  salvage, status, condition, warehouse_id, location_id, department_id, note,
                                  created_by, updated_by)
    values (v_tag, v_name, v_cat.id, v_item, public.st_text(p_data, 'manufacturer', 80), public.st_text(p_data, 'model', 80),
            v_serial, v_buy, v_start, v_cost, public.st_text(p_data, 'supplier', 160), public.st_text(p_data, 'invoice_no', 60),
            v_warr, v_method, v_life::integer, v_salv, public.st_place_status(v_wh, v_loc, v_dep), v_cond, v_wh, v_loc, v_dep,
            public.st_text(p_data, 'note', 1000), auth.uid(), auth.uid())
    returning id into v_id;
    perform public.st_asset_event(v_id, 'create', jsonb_build_object('tag', v_tag, 'cost', v_cost));
  else
    if v_tag = '' then
      v_tag := old_r.tag;
    end if;
    update public.st_assets
       set tag = v_tag, name = v_name, category_id = v_cat.id, item_id = v_item,
           manufacturer = public.st_text(p_data, 'manufacturer', 80), model = public.st_text(p_data, 'model', 80),
           serial_no = v_serial, purchase_date = v_buy, in_service_date = v_start, cost = v_cost,
           supplier = public.st_text(p_data, 'supplier', 160), invoice_no = public.st_text(p_data, 'invoice_no', 60),
           warranty_until = v_warr, dep_method = v_method, life_months = v_life::integer, salvage = v_salv,
           condition = case when status = 'custody' then condition else v_cond end,
           note = public.st_text(p_data, 'note', 1000), updated_at = now(), updated_by = auth.uid()
     where id = p_id;
    perform public.st_asset_event(p_id, 'update',
      jsonb_build_object('changed', (select coalesce(jsonb_agg(n.key order by n.key), '[]'::jsonb)
                                       from jsonb_each(public.st_asset_row(p_id)) n
                                       join jsonb_each(to_jsonb(old_r) - 'name_key') o using (key)
                                      where n.value is distinct from o.value and n.key not in ('updated_at', 'updated_by'))));
  end if;
  perform public.write_audit('stores.asset', null, null,
    jsonb_build_object('op', case when p_id is null then 'create' else 'update' end, 'id', v_id, 'tag', v_tag, 'name', v_name,
                       'from', case when p_id is null then null else to_jsonb(old_r) - 'name_key' end),
    v_tag);
  return v_id;
exception
  when unique_violation then
    raise exception 'رقم الأصل أو الرقم التسلسلي مسجل لأصل آخر' using errcode = '23505';
end;
$$;

-- حذف أصل سُجّل خطأً: قبل أي عهدة أو استبعاد
create or replace function public.st_delete_asset(p_id uuid)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  a public.st_assets;
begin
  if not public.st_can_assets() then
    raise exception 'سجل الأصول لمسؤول الأصول أو مدير المخازن أو المدير' using errcode = '42501';
  end if;
  select * into a from public.st_assets where id = p_id for update;
  if not found then
    raise exception 'الأصل غير موجود' using errcode = 'P0002';
  end if;
  if a.status in ('custody', 'disposal', 'disposed') or exists (select 1 from public.st_custody where asset_id = p_id) then
    raise exception 'للأصل عهد أو استبعاد؛ لا يُحذف ويبقى سجله' using errcode = '23503';
  end if;
  delete from public.st_assets where id = p_id;
  perform public.write_audit('stores.asset', null, null,
    jsonb_build_object('op', 'delete', 'id', p_id, 'tag', a.tag, 'name', a.name, 'from', to_jsonb(a) - 'name_key'), a.tag);
end;
$$;

-- النقل: إلى مخزن (يُحفظ فيه) أو إلى موقع وإدارة (يُستخدم فيهما). الأصل المسلَّم يبقى مع موظفه ويتغير موقعه أو إدارته
create or replace function public.st_asset_transfer(p_id uuid, p_data jsonb)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  a     public.st_assets;
  v_wh  uuid;
  v_loc uuid;
  v_dep uuid;
  v_st  text;
begin
  if not public.st_can_assets() then
    raise exception 'نقل الأصول لمسؤول الأصول أو مدير المخازن أو المدير' using errcode = '42501';
  end if;
  if jsonb_typeof(coalesce(p_data, 'null'::jsonb)) <> 'object' then
    raise exception 'بيانات غير صالحة' using errcode = '22023';
  end if;
  select * into a from public.st_assets where id = p_id for update;
  if not found then
    raise exception 'الأصل غير موجود' using errcode = 'P0002';
  end if;
  if a.status in ('disposal', 'disposed') then
    raise exception 'الأصل مستبعد أو بانتظار اعتماد استبعاده' using errcode = '22023';
  end if;
  v_wh := public.st_uuid(p_data, 'warehouse_id');
  v_loc := public.st_uuid(p_data, 'location_id');
  v_dep := public.st_uuid(p_data, 'department_id');
  if v_wh is not null then
    if a.status = 'custody' then
      raise exception 'الأصل في عهدة موظف؛ سجّل إرجاعه إلى المخزن' using errcode = '22023';
    end if;
    select location_id into v_loc from public.st_warehouses where id = v_wh and active;
    if not found then
      raise exception 'المخزن غير موجود أو موقوف' using errcode = '22023';
    end if;
  end if;
  if v_loc is not null and not exists (select 1 from public.st_locations where id = v_loc) then
    raise exception 'الموقع غير موجود' using errcode = '22023';
  end if;
  if v_dep is not null and not exists (select 1 from public.st_departments where id = v_dep) then
    raise exception 'الإدارة غير موجودة' using errcode = '22023';
  end if;
  if v_wh is not distinct from a.warehouse_id and v_loc is not distinct from a.location_id
     and v_dep is not distinct from a.department_id then
    raise exception 'لم يتغير المكان' using errcode = '22023';
  end if;
  v_st := case when a.status in ('available', 'in_use') then public.st_place_status(v_wh, v_loc, v_dep) else a.status end;
  update public.st_assets
     set warehouse_id = v_wh, location_id = v_loc, department_id = v_dep, status = v_st, updated_at = now(), updated_by = auth.uid()
   where id = p_id;
  perform public.st_asset_event(p_id, 'transfer',
    jsonb_build_object('from', jsonb_build_object('warehouse_id', a.warehouse_id, 'location_id', a.location_id,
                                                  'department_id', a.department_id, 'status', a.status),
                       'to', jsonb_build_object('warehouse_id', v_wh, 'location_id', v_loc, 'department_id', v_dep, 'status', v_st)),
    public.st_text(p_data, 'note', 500));
  perform public.write_audit('stores.asset_transfer', null, null,
    jsonb_build_object('id', p_id, 'tag', a.tag, 'name', a.name,
                       'from', jsonb_build_object('warehouse_id', a.warehouse_id, 'location_id', a.location_id, 'department_id', a.department_id),
                       'to', jsonb_build_object('warehouse_id', v_wh, 'location_id', v_loc, 'department_id', v_dep)),
    a.tag);
end;
$$;

-- تغيير وضع الأصل غير المسلَّم: متاح، مستخدم، تحت الصيانة، معطّل (مع حالته المادية)
create or replace function public.st_asset_status(p_id uuid, p_status text, p_condition text default null, p_note text default '')
returns void
language plpgsql security definer set search_path = public
as $$
declare
  a      public.st_assets;
  v_cond text;
begin
  if not public.st_can_assets() then
    raise exception 'سجل الأصول لمسؤول الأصول أو مدير المخازن أو المدير' using errcode = '42501';
  end if;
  if p_status not in ('available', 'in_use', 'maintenance', 'damaged') then
    raise exception 'الوضع: متاح أو مستخدم أو تحت الصيانة أو معطّل' using errcode = '22023';
  end if;
  select * into a from public.st_assets where id = p_id for update;
  if not found then
    raise exception 'الأصل غير موجود' using errcode = 'P0002';
  end if;
  if a.status = 'custody' then
    raise exception 'الأصل في عهدة موظف؛ سجّل إرجاعه أولاً' using errcode = '22023';
  end if;
  if a.status in ('disposal', 'disposed') then
    raise exception 'الأصل مستبعد أو بانتظار اعتماد استبعاده' using errcode = '22023';
  end if;
  if p_status = 'in_use' and a.warehouse_id is not null then
    raise exception 'الأصل في مخزن؛ انقله إلى موقع أو إدارة ليكون مستخدماً' using errcode = '22023';
  end if;
  v_cond := coalesce(nullif(p_condition, ''), case when p_status = 'damaged' then 'damaged' else a.condition end);
  if v_cond not in ('new', 'good', 'fair', 'poor', 'damaged') then
    raise exception 'حالة الأصل غير معروفة' using errcode = '22023';
  end if;
  if p_status = a.status and v_cond = a.condition then
    raise exception 'لم يتغير الوضع' using errcode = '22023';
  end if;
  update public.st_assets set status = p_status, condition = v_cond, updated_at = now(), updated_by = auth.uid() where id = p_id;
  perform public.st_asset_event(p_id, 'status',
    jsonb_build_object('from', a.status, 'to', p_status, 'condition_from', a.condition, 'condition_to', v_cond), p_note);
  perform public.write_audit('stores.asset_status', null, null,
    jsonb_build_object('id', p_id, 'tag', a.tag, 'name', a.name, 'from', a.status, 'to', p_status,
                       'condition', v_cond, 'note', left(coalesce(p_note, ''), 500)),
    a.tag);
end;
$$;

-- ---------------------------------------------------------------------
-- 6. العُهد: التسليم والإرجاع وتأكيد الموظف
-- ---------------------------------------------------------------------
create or replace function public.st_custody_out(p_asset uuid, p_data jsonb)
returns uuid
language plpgsql security definer set search_path = public
as $$
declare
  a      public.st_assets;
  e      public.st_employees;
  v_id   uuid;
  v_no   text;
  v_on   date;
  v_cond text;
  v_dep  uuid;
  v_loc  uuid;
begin
  if not public.st_can_assets() then
    raise exception 'تسليم العهد لمسؤول الأصول أو مدير المخازن أو المدير' using errcode = '42501';
  end if;
  if jsonb_typeof(coalesce(p_data, 'null'::jsonb)) <> 'object' then
    raise exception 'بيانات غير صالحة' using errcode = '22023';
  end if;
  select * into a from public.st_assets where id = p_asset for update;
  if not found then
    raise exception 'الأصل غير موجود' using errcode = 'P0002';
  end if;
  if a.status = 'custody' then
    raise exception 'الأصل في عهدة موظف آخر؛ سجّل إرجاعه أولاً' using errcode = '22023';
  end if;
  if a.status not in ('available', 'in_use') then
    raise exception 'لا يُسلَّم أصل تحت الصيانة أو معطّل أو مستبعد' using errcode = '22023';
  end if;
  select * into e from public.st_employees where id = public.st_uuid(p_data, 'employee_id');
  if not found then
    raise exception 'اختر الموظف المستلم' using errcode = '22023';
  end if;
  if not e.active then
    raise exception 'الموظف «%» موقوف', e.full_name using errcode = '22023';
  end if;
  v_on := coalesce(public.st_date(p_data, 'handed_on'), current_date);
  if v_on > current_date then
    raise exception 'تاريخ التسليم في المستقبل' using errcode = '22023';
  end if;
  if exists (select 1 from public.st_custody where asset_id = p_asset and returned_on > v_on) then
    raise exception 'تاريخ التسليم قبل آخر إرجاع للأصل' using errcode = '22023';
  end if;
  v_cond := coalesce(nullif(p_data ->> 'condition', ''), a.condition);
  if v_cond not in ('new', 'good', 'fair', 'poor', 'damaged') then
    raise exception 'حالة الأصل غير معروفة' using errcode = '22023';
  end if;
  if v_cond = 'damaged' then
    raise exception 'لا يُسلَّم أصل تالف' using errcode = '22023';
  end if;
  v_dep := coalesce(public.st_uuid(p_data, 'department_id'), e.department_id, a.department_id);
  v_loc := coalesce(public.st_uuid(p_data, 'location_id'), case when a.warehouse_id is null then a.location_id end);
  if v_loc is not null and not exists (select 1 from public.st_locations where id = v_loc) then
    raise exception 'الموقع غير موجود' using errcode = '22023';
  end if;
  if v_dep is not null and not exists (select 1 from public.st_departments where id = v_dep) then
    raise exception 'الإدارة غير موجودة' using errcode = '22023';
  end if;
  v_no := public.st_next_no('custody', 'CU', extract(year from v_on)::integer, 4);
  insert into public.st_custody (custody_no, asset_id, employee_id, department_id, location_id, handed_on, handed_by,
                                 condition_out, accessories_out, note_out)
  values (v_no, p_asset, e.id, v_dep, v_loc, v_on, auth.uid(), v_cond, public.st_text(p_data, 'accessories', 500),
          public.st_text(p_data, 'note', 500))
  returning id into v_id;
  update public.st_assets
     set status = 'custody', employee_id = e.id, department_id = v_dep, location_id = v_loc, warehouse_id = null,
         condition = v_cond, updated_at = now(), updated_by = auth.uid()
   where id = p_asset;
  perform public.st_asset_event(p_asset, 'custody_out',
    jsonb_build_object('custody_id', v_id, 'custody_no', v_no, 'employee_id', e.id, 'employee', e.full_name,
                       'condition', v_cond, 'from_status', a.status),
    public.st_text(p_data, 'note', 500));
  perform public.write_audit('stores.custody_out', null, null,
    jsonb_build_object('id', v_id, 'custody_no', v_no, 'asset_id', p_asset, 'tag', a.tag, 'name', a.name,
                       'employee', e.full_name, 'emp_no', e.emp_no, 'handed_on', v_on, 'condition', v_cond),
    v_no);
  return v_id;
end;
$$;

create or replace function public.st_custody_in(p_id uuid, p_data jsonb)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  c      public.st_custody;
  a      public.st_assets;
  v_on   date;
  v_cond text;
  v_st   text;
  v_wh   uuid;
  v_loc  uuid;
begin
  if not public.st_can_assets() then
    raise exception 'استلام العهد لمسؤول الأصول أو مدير المخازن أو المدير' using errcode = '42501';
  end if;
  if jsonb_typeof(coalesce(p_data, 'null'::jsonb)) <> 'object' then
    raise exception 'بيانات غير صالحة' using errcode = '22023';
  end if;
  select * into c from public.st_custody where id = p_id for update;
  if not found then
    raise exception 'العهدة غير موجودة' using errcode = 'P0002';
  end if;
  if c.returned_on is not null then
    raise exception 'سُجّل إرجاع هذه العهدة من قبل' using errcode = '22023';
  end if;
  select * into a from public.st_assets where id = c.asset_id for update;
  v_on := coalesce(public.st_date(p_data, 'returned_on'), current_date);
  if v_on > current_date then
    raise exception 'تاريخ الإرجاع في المستقبل' using errcode = '22023';
  end if;
  if v_on < c.handed_on then
    raise exception 'تاريخ الإرجاع قبل تاريخ التسليم' using errcode = '22023';
  end if;
  v_cond := nullif(p_data ->> 'condition', '');
  if v_cond is null or v_cond not in ('new', 'good', 'fair', 'poor', 'damaged') then
    raise exception 'حدد حالة الأصل عند الإرجاع' using errcode = '22023';
  end if;
  v_st := coalesce(nullif(p_data ->> 'status', ''), case when v_cond = 'damaged' then 'damaged' else 'available' end);
  if v_st not in ('available', 'maintenance', 'damaged') then
    raise exception 'وضع الأصل بعد الإرجاع: متاح أو تحت الصيانة أو معطّل' using errcode = '22023';
  end if;
  v_wh := public.st_uuid(p_data, 'warehouse_id');
  v_loc := a.location_id;
  if v_wh is not null then
    select location_id into v_loc from public.st_warehouses where id = v_wh and active;
    if not found then
      raise exception 'المخزن غير موجود أو موقوف' using errcode = '22023';
    end if;
  end if;
  update public.st_custody
     set returned_on = v_on, returned_at = now(), received_by = auth.uid(), condition_in = v_cond,
         accessories_in = public.st_text(p_data, 'accessories', 500), note_in = public.st_text(p_data, 'note', 500)
   where id = p_id;
  update public.st_assets
     set status = v_st, employee_id = null, condition = v_cond, warehouse_id = v_wh, location_id = v_loc,
         updated_at = now(), updated_by = auth.uid()
   where id = a.id;
  perform public.st_asset_event(a.id, 'custody_in',
    jsonb_build_object('custody_id', p_id, 'custody_no', c.custody_no, 'employee_id', c.employee_id,
                       'employee', (select full_name from public.st_employees where id = c.employee_id),
                       'condition', v_cond, 'to_status', v_st, 'warehouse_id', v_wh),
    public.st_text(p_data, 'note', 500));
  perform public.write_audit('stores.custody_in', null, null,
    jsonb_build_object('id', p_id, 'custody_no', c.custody_no, 'asset_id', a.id, 'tag', a.tag, 'name', a.name,
                       'employee', (select full_name from public.st_employees where id = c.employee_id),
                       'returned_on', v_on, 'condition', v_cond, 'status', v_st),
    c.custody_no);
end;
$$;

-- تأكيد الموظف من صفحته: استلام العهدة (receipt) أو إرجاعها (return)
create or replace function public.st_confirm_custody(p_id uuid, p_kind text)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  c   public.st_custody;
  v_e uuid := public.st_my_employee();
begin
  if v_e is null then
    raise exception 'حسابك غير مربوط بسجل موظف نشط' using errcode = '42501';
  end if;
  if public.setting_bool('security.freeze', false) and not public.is_director() then
    raise exception 'المنظومة في وضع القراءة فقط' using errcode = '42501';
  end if;
  if p_kind not in ('receipt', 'return') then
    raise exception 'نوع التأكيد غير معروف' using errcode = '22023';
  end if;
  select * into c from public.st_custody where id = p_id for update;
  if not found or c.employee_id is distinct from v_e then
    raise exception 'العهدة غير موجودة' using errcode = 'P0002';
  end if;
  if p_kind = 'receipt' then
    if c.confirmed_at is not null then
      return;
    end if;
    update public.st_custody set confirmed_at = now(), confirmed_by = auth.uid() where id = p_id;
  else
    if c.returned_on is null then
      raise exception 'لم يُسجَّل إرجاع هذه العهدة بعد' using errcode = '22023';
    end if;
    if c.return_confirmed_at is not null then
      return;
    end if;
    update public.st_custody set return_confirmed_at = now(), return_confirmed_by = auth.uid() where id = p_id;
  end if;
  perform public.write_audit('stores.custody_confirm', null, null,
    jsonb_build_object('id', p_id, 'custody_no', c.custody_no, 'kind', p_kind), c.custody_no);
end;
$$;

-- عهد الموظف المرتبط بالحساب: الأصل ووصفه دون تكلفته
create or replace function public.st_my_custody()
returns jsonb
language sql stable security definer set search_path = public
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', c.id, 'custody_no', c.custody_no, 'asset_id', a.id, 'tag', a.tag, 'name', a.name,
           'category', cat.name, 'manufacturer', a.manufacturer, 'model', a.model, 'serial_no', a.serial_no,
           'handed_on', c.handed_on, 'condition_out', c.condition_out, 'accessories_out', c.accessories_out,
           'note_out', c.note_out, 'confirmed_at', c.confirmed_at, 'returned_on', c.returned_on,
           'condition_in', c.condition_in, 'accessories_in', c.accessories_in, 'return_confirmed_at', c.return_confirmed_at)
         order by (c.returned_on is null) desc, c.handed_on desc, c.custody_no desc), '[]'::jsonb)
    from public.st_custody c
    join public.st_assets a on a.id = c.asset_id
    join public.st_categories cat on cat.id = a.category_id
   where c.employee_id = public.st_my_employee()
$$;

-- ---------------------------------------------------------------------
-- 7. الاستبعاد: طلب من مسؤول الأصول، واعتماد مدير المخازن أو المدير
-- ---------------------------------------------------------------------
create or replace function public.st_asset_dispose_request(p_id uuid, p_data jsonb)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  a        public.st_assets;
  v_kind   text := nullif(p_data ->> 'kind', '');
  v_reason text;
  v_value  numeric;
  v_date   date;
begin
  if not public.st_can_assets() then
    raise exception 'طلب الاستبعاد لمسؤول الأصول أو مدير المخازن أو المدير' using errcode = '42501';
  end if;
  if jsonb_typeof(coalesce(p_data, 'null'::jsonb)) <> 'object' then
    raise exception 'بيانات غير صالحة' using errcode = '22023';
  end if;
  select * into a from public.st_assets where id = p_id for update;
  if not found then
    raise exception 'الأصل غير موجود' using errcode = 'P0002';
  end if;
  if a.status = 'custody' then
    raise exception 'الأصل في عهدة موظف؛ سجّل إرجاعه أولاً' using errcode = '22023';
  end if;
  if a.status in ('disposal', 'disposed') then
    raise exception 'الأصل مستبعد أو بانتظار اعتماد استبعاده' using errcode = '22023';
  end if;
  if v_kind is null or v_kind not in ('scrap', 'sale', 'donate', 'lost', 'other') then
    raise exception 'نوع الاستبعاد: إتلاف أو بيع أو إهداء أو فقد أو غير ذلك' using errcode = '22023';
  end if;
  v_reason := public.st_text(p_data, 'reason', 500);
  if length(v_reason) < 3 then
    raise exception 'اكتب سبب الاستبعاد' using errcode = '22023';
  end if;
  v_value := public.st_num(p_data, 'value', null);
  if v_value is not null and v_value < 0 then
    raise exception 'قيمة البيع رقم موجب' using errcode = '22023';
  end if;
  v_date := public.st_date(p_data, 'date');
  if v_date is not null and v_date > current_date then
    raise exception 'تاريخ الاستبعاد في المستقبل' using errcode = '22023';
  end if;
  update public.st_assets
     set status = 'disposal', disposal_kind = v_kind, disposal_reason = v_reason, disposal_value = round(v_value, 3),
         disposal_date = v_date, disposal_requested_at = now(), disposal_requested_by = auth.uid(), decision_note = '',
         updated_at = now(), updated_by = auth.uid()
   where id = p_id;
  perform public.st_asset_event(p_id, 'dispose_request',
    jsonb_build_object('kind', v_kind, 'value', round(v_value, 3), 'date', v_date, 'from_status', a.status), v_reason);
  perform public.write_audit('stores.asset_dispose_request', null, null,
    jsonb_build_object('id', p_id, 'tag', a.tag, 'name', a.name, 'kind', v_kind, 'reason', v_reason,
                       'value', round(v_value, 3), 'from', a.status),
    a.tag);
end;
$$;

create or replace function public.st_asset_dispose_decide(p_id uuid, p_approve boolean, p_note text default '')
returns void
language plpgsql security definer set search_path = public
as $$
declare
  a      public.st_assets;
  v_prev text;
  v_note text := left(btrim(coalesce(p_note, '')), 500);
begin
  if not public.st_can_approve() then
    raise exception 'اعتماد الاستبعاد لمدير المخازن أو المدير' using errcode = '42501';
  end if;
  select * into a from public.st_assets where id = p_id for update;
  if not found then
    raise exception 'الأصل غير موجود' using errcode = 'P0002';
  end if;
  if a.status <> 'disposal' then
    raise exception 'لا طلب استبعاد قائم لهذا الأصل' using errcode = '22023';
  end if;
  if public.st_setting_bool('separation', true) and a.disposal_requested_by = auth.uid() then
    raise exception 'فصل المهام: طلب الاستبعاد يعتمده غير من قدّمه' using errcode = '42501';
  end if;
  if p_approve then
    update public.st_assets
       set status = 'disposed', disposed_at = now(), disposed_by = auth.uid(),
           disposal_date = coalesce(disposal_date, current_date), decision_note = v_note, location_id = null,
           department_id = null, warehouse_id = null, updated_at = now(), updated_by = auth.uid()
     where id = p_id;
    perform public.st_asset_event(p_id, 'dispose',
      jsonb_build_object('kind', a.disposal_kind, 'value', a.disposal_value, 'date', coalesce(a.disposal_date, current_date),
                         'book_value', public.st_book_value(a, coalesce(a.disposal_date, current_date))),
      v_note);
  else
    if length(v_note) < 3 then
      raise exception 'اكتب سبب رفض الاستبعاد' using errcode = '22023';
    end if;
    select data ->> 'from_status' into v_prev from public.st_asset_events
     where asset_id = p_id and kind = 'dispose_request' order by id desc limit 1;
    v_prev := coalesce(v_prev, public.st_place_status(a.warehouse_id, a.location_id, a.department_id));
    if v_prev not in ('available', 'in_use', 'maintenance', 'damaged') then
      v_prev := 'available';
    end if;
    if v_prev = 'in_use' and a.warehouse_id is not null then
      v_prev := 'available';
    end if;
    update public.st_assets
       set status = v_prev, disposal_kind = null, disposal_reason = '', disposal_value = null, disposal_date = null,
           disposal_requested_at = null, disposal_requested_by = null, decision_note = v_note,
           updated_at = now(), updated_by = auth.uid()
     where id = p_id;
    perform public.st_asset_event(p_id, 'dispose_reject', jsonb_build_object('kind', a.disposal_kind, 'to_status', v_prev), v_note);
  end if;
  perform public.write_audit('stores.asset_dispose', null, null,
    jsonb_build_object('id', p_id, 'tag', a.tag, 'name', a.name, 'approve', p_approve, 'kind', a.disposal_kind,
                       'reason', a.disposal_reason, 'value', a.disposal_value, 'note', v_note),
    a.tag);
end;
$$;

-- ---------------------------------------------------------------------
-- 8. استيراد سجل الأصول بعد مراجعته: يُحدَّث الموجود برقمه وإلا يُضاف، ومن له رقم وظيفي تُسجَّل عهدته
-- ---------------------------------------------------------------------
create or replace function public.st_import_assets(p_rows jsonb)
returns jsonb
language plpgsql security definer set search_path = public
as $$
declare
  r       jsonb;
  n       integer := 0;
  v_ins   integer := 0;
  v_upd   integer := 0;
  v_cus   integer := 0;
  v_cat   public.st_categories;
  v_pol   public.st_asset_policies;
  v_tag   text;
  v_name  text;
  v_id    uuid;
  v_old   public.st_assets;
  v_cost  numeric;
  v_life  numeric;
  v_salv  numeric;
  v_buy   date;
  v_loc   uuid;
  v_dep   uuid;
  v_emp   public.st_employees;
  v_txt   text;
  v_cond  text;
  v_cnt   integer;
begin
  if not public.st_can_assets() then
    raise exception 'سجل الأصول لمسؤول الأصول أو مدير المخازن أو المدير' using errcode = '42501';
  end if;
  if jsonb_typeof(coalesce(p_rows, 'null'::jsonb)) <> 'array' or jsonb_array_length(p_rows) = 0 then
    raise exception 'لا صفوف للاستيراد' using errcode = '22023';
  end if;
  if jsonb_array_length(p_rows) > 2000 then
    raise exception 'الحد الأعلى 2000 صف في الاستيراد الواحد' using errcode = '22023';
  end if;
  for r in select x from jsonb_array_elements(p_rows) x loop
    n := n + 1;
    if jsonb_typeof(r) <> 'object' then
      raise exception 'الصف %: بيانات غير صالحة', n using errcode = '22023';
    end if;
    v_name := btrim(coalesce(r ->> 'name', ''));
    if length(v_name) not between 2 and 160 then
      raise exception 'الصف %: وصف الأصل من 2 إلى 160 حرفاً', n using errcode = '22023';
    end if;
    v_txt := upper(btrim(coalesce(r ->> 'category', '')));
    select * into v_cat from public.st_categories
     where code = v_txt or name_key = public.pm_text_norm(r ->> 'category')
     order by (code = v_txt) desc limit 1;
    if not found then
      raise exception 'الصف %: التصنيف «%» غير موجود', n, coalesce(r ->> 'category', '') using errcode = '22023';
    end if;
    if v_cat.kind <> 'asset' then
      raise exception 'الصف %: التصنيف «%» استهلاكي؛ الأصول في تصنيفات الأصول', n, v_cat.name using errcode = '22023';
    end if;
    select * into v_pol from public.st_asset_policies where category_id = v_cat.id;
    v_tag := btrim(coalesce(r ->> 'tag', ''));
    if v_tag <> '' and v_tag !~ '^[A-Za-z0-9._/-]{1,30}$' then
      raise exception 'الصف %: رقم الأصل «%» غير صالح', n, v_tag using errcode = '22023';
    end if;
    begin
      v_cost := round(coalesce(public.st_num(r, 'cost', 0), 0), 3);
      v_buy := public.st_date(r, 'purchase_date');
    exception when others then
      raise exception 'الصف %: %', n, sqlerrm using errcode = '22023';
    end;
    if v_cost < 0 then
      raise exception 'الصف %: التكلفة رقم موجب', n using errcode = '22023';
    end if;
    if v_buy is not null and v_buy > (now() at time zone 'Africa/Tripoli')::date then
      raise exception 'الصف %: تاريخ الشراء في المستقبل', n using errcode = '22023';
    end if;
    begin
      v_life := coalesce(public.st_num(r, 'life_months', null), v_pol.life_months);
      v_salv := round(coalesce(public.st_num(r, 'salvage', null), v_cost * coalesce(v_pol.salvage_pct, 0) / 100), 3);
    exception when others then
      raise exception 'الصف %: %', n, sqlerrm using errcode = '22023';
    end;
    if v_life is not null and (v_life <> round(v_life) or v_life not between 1 and 600) then
      raise exception 'الصف %: العمر بالأشهر عدد صحيح من 1 إلى 600', n using errcode = '22023';
    end if;
    if v_salv > v_cost then
      raise exception 'الصف %: الخردة أكبر من التكلفة', n using errcode = '22023';
    end if;
    v_cond := coalesce(nullif(btrim(coalesce(r ->> 'condition', '')), ''), 'good');
    if v_cond not in ('new', 'good', 'fair', 'poor', 'damaged') then
      raise exception 'الصف %: حالة الأصل غير معروفة', n using errcode = '22023';
    end if;
    -- الموقع والإدارة: بالرمز أو بالاسم، ويجب أن يدل على واحد
    v_loc := null;
    v_txt := btrim(coalesce(r ->> 'location', ''));
    if v_txt <> '' then
      select count(*) into v_cnt from public.st_locations where lower(code) = lower(v_txt) and code <> '';
      if v_cnt = 1 then
        select id into v_loc from public.st_locations where lower(code) = lower(v_txt) and code <> '';
      else
        select count(*) into v_cnt from public.st_locations where name_key = public.pm_text_norm(v_txt);
        if v_cnt = 1 then
          select id into v_loc from public.st_locations where name_key = public.pm_text_norm(v_txt);
        end if;
      end if;
      if v_loc is null then
        raise exception 'الصف %: الموقع «%» غير موجود أو يدل على أكثر من موقع؛ اكتب رمزه', n, v_txt using errcode = '22023';
      end if;
    end if;
    v_dep := null;
    v_txt := btrim(coalesce(r ->> 'department', ''));
    if v_txt <> '' then
      select id into v_dep from public.st_departments
       where lower(code) = lower(v_txt) or name_key = public.pm_text_norm(v_txt)
       order by (lower(code) = lower(v_txt)) desc, (parent_id is null) desc limit 1;
      if v_dep is null then
        raise exception 'الصف %: الإدارة «%» غير موجودة', n, v_txt using errcode = '22023';
      end if;
    end if;
    v_emp := null;
    v_txt := btrim(coalesce(r ->> 'emp_no', ''));
    if v_txt <> '' then
      select * into v_emp from public.st_employees where lower(emp_no) = lower(v_txt) and active;
      if not found then
        raise exception 'الصف %: لا موظف نشط بالرقم الوظيفي «%»', n, v_txt using errcode = '22023';
      end if;
    end if;

    v_old := null;
    if v_tag <> '' then
      select * into v_old from public.st_assets where lower(tag) = lower(v_tag) for update;
    end if;
    if v_old.id is null then
      if v_tag = '' then
        v_tag := public.st_next_no('asset:' || v_cat.code, v_cat.code || '-A', 0, 4);
      end if;
      insert into public.st_assets (tag, name, category_id, manufacturer, model, serial_no, purchase_date, in_service_date,
                                    cost, supplier, invoice_no, warranty_until, dep_method, life_months, salvage, status,
                                    condition, location_id, department_id, note, created_by, updated_by)
      values (v_tag, v_name, v_cat.id, left(btrim(coalesce(r ->> 'manufacturer', '')), 80), left(btrim(coalesce(r ->> 'model', '')), 80),
              left(btrim(coalesce(r ->> 'serial_no', '')), 80), v_buy, v_buy, v_cost, left(btrim(coalesce(r ->> 'supplier', '')), 160),
              left(btrim(coalesce(r ->> 'invoice_no', '')), 60), public.st_date(r, 'warranty_until'),
              case when v_life is null then 'none' else 'straight' end, v_life::integer, v_salv,
              public.st_place_status(null, v_loc, v_dep), v_cond, v_loc, v_dep, left(btrim(coalesce(r ->> 'note', '')), 1000),
              auth.uid(), auth.uid())
      returning id into v_id;
      perform public.st_asset_event(v_id, 'create', jsonb_build_object('tag', v_tag, 'cost', v_cost, 'import', true));
      v_ins := v_ins + 1;
    else
      if v_old.status in ('disposal', 'disposed') then
        raise exception 'الصف %: الأصل «%» مستبعد؛ لا يُحدَّث', n, v_tag using errcode = '22023';
      end if;
      v_id := v_old.id;
      update public.st_assets
         set name = v_name, category_id = v_cat.id,
             manufacturer = coalesce(nullif(left(btrim(coalesce(r ->> 'manufacturer', '')), 80), ''), manufacturer),
             model = coalesce(nullif(left(btrim(coalesce(r ->> 'model', '')), 80), ''), model),
             serial_no = coalesce(nullif(left(btrim(coalesce(r ->> 'serial_no', '')), 80), ''), serial_no),
             purchase_date = coalesce(v_buy, purchase_date), in_service_date = coalesce(in_service_date, v_buy),
             cost = case when r ? 'cost' then v_cost else cost end,
             salvage = case when r ? 'salvage' or r ? 'cost' then least(v_salv, case when r ? 'cost' then v_cost else cost end) else salvage end,
             supplier = coalesce(nullif(left(btrim(coalesce(r ->> 'supplier', '')), 160), ''), supplier),
             invoice_no = coalesce(nullif(left(btrim(coalesce(r ->> 'invoice_no', '')), 60), ''), invoice_no),
             warranty_until = coalesce(public.st_date(r, 'warranty_until'), warranty_until),
             life_months = case when r ? 'life_months' and v_life is not null then v_life::integer else life_months end,
             dep_method = case when r ? 'life_months' and v_life is not null then 'straight' else dep_method end,
             updated_at = now(), updated_by = auth.uid()
       where id = v_id;
      perform public.st_asset_event(v_id, 'update', jsonb_build_object('import', true));
      v_upd := v_upd + 1;
    end if;
    -- العهدة من الملف: للأصل غير المسلَّم
    if v_emp.id is not null and not exists (select 1 from public.st_custody where asset_id = v_id and returned_on is null)
       and (select status from public.st_assets where id = v_id) in ('available', 'in_use') and v_cond <> 'damaged' then
      perform public.st_custody_out(v_id, jsonb_build_object('employee_id', v_emp.id, 'department_id', v_dep,
                                                             'location_id', v_loc, 'condition', v_cond, 'note', 'من الاستيراد'));
      v_cus := v_cus + 1;
    end if;
  end loop;
  perform public.write_audit('stores.assets_import', null, null,
    jsonb_build_object('rows', n, 'inserted', v_ins, 'updated', v_upd, 'custody', v_cus), 'استيراد الأصول');
  return jsonb_build_object('rows', n, 'inserted', v_ins, 'updated', v_upd, 'custody', v_cus);
exception
  when unique_violation then
    raise exception 'الصف %: رقم الأصل أو الرقم التسلسلي مسجل لأصل آخر', n using errcode = '23505';
end;
$$;

-- ---------------------------------------------------------------------
-- 9. سياسات القراءة والصلاحيات والتحديث اللحظي
-- ---------------------------------------------------------------------
alter table public.st_asset_policies enable row level security;
alter table public.st_assets enable row level security;
alter table public.st_custody enable row level security;
alter table public.st_asset_events enable row level security;

drop policy if exists st_asset_policies_read on public.st_asset_policies;
create policy st_asset_policies_read on public.st_asset_policies for select to authenticated using ((select public.st_staff()));
drop policy if exists st_assets_read on public.st_assets;
create policy st_assets_read on public.st_assets for select to authenticated using ((select public.st_assets_sees()));
-- العهد: من يرى الأصول، والموظف عهده وحدها (وصف الأصل يصله من st_my_custody دون تكلفته)
drop policy if exists st_custody_read on public.st_custody;
create policy st_custody_read on public.st_custody for select to authenticated
  using ((select public.st_assets_sees()) or employee_id = (select public.st_my_employee()));
drop policy if exists st_asset_events_read on public.st_asset_events;
create policy st_asset_events_read on public.st_asset_events for select to authenticated using ((select public.st_assets_sees()));

revoke all on public.st_asset_policies, public.st_assets, public.st_custody, public.st_asset_events from anon, authenticated;
grant select on public.st_asset_policies, public.st_assets, public.st_custody, public.st_asset_events to authenticated;
grant all on public.st_asset_policies, public.st_assets, public.st_custody, public.st_asset_events to service_role;

revoke execute on function public.st_assets_sees(), public.st_can_assets(), public.st_save_asset_policy(uuid, jsonb),
  public.st_save_asset(uuid, jsonb), public.st_delete_asset(uuid), public.st_asset_transfer(uuid, jsonb),
  public.st_asset_status(uuid, text, text, text), public.st_custody_out(uuid, jsonb), public.st_custody_in(uuid, jsonb),
  public.st_confirm_custody(uuid, text), public.st_my_custody(), public.st_asset_dispose_request(uuid, jsonb),
  public.st_asset_dispose_decide(uuid, boolean, text), public.st_import_assets(jsonb) from public, anon;
grant execute on function public.st_assets_sees(), public.st_can_assets(), public.st_save_asset_policy(uuid, jsonb),
  public.st_save_asset(uuid, jsonb), public.st_delete_asset(uuid), public.st_asset_transfer(uuid, jsonb),
  public.st_asset_status(uuid, text, text, text), public.st_custody_out(uuid, jsonb), public.st_custody_in(uuid, jsonb),
  public.st_confirm_custody(uuid, text), public.st_my_custody(), public.st_asset_dispose_request(uuid, jsonb),
  public.st_asset_dispose_decide(uuid, boolean, text), public.st_import_assets(jsonb) to authenticated;
-- حساب الإهلاك: دوال حسابية بحتة لا تقرأ الجداول، متاحة لمن سجّل الدخول
revoke execute on function public.st_months_between(date, date), public.st_accumulated(numeric, numeric, text, integer, date, date),
  public.st_book_value(public.st_assets, date) from public, anon;
grant execute on function public.st_months_between(date, date), public.st_accumulated(numeric, numeric, text, integer, date, date),
  public.st_book_value(public.st_assets, date) to authenticated;
-- داخلية: لا تُستدعى من التطبيق
revoke execute on function public.st_date(jsonb, text), public.st_asset_event(uuid, text, jsonb, text), public.st_asset_row(uuid),
  public.st_place_status(uuid, uuid, uuid)
  from public, anon, authenticated;

do $$
declare
  t text;
begin
  foreach t in array array['st_assets', 'st_custody', 'st_asset_policies'] loop
    if exists (select 1 from pg_publication where pubname = 'supabase_realtime')
       and not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = t) then
      execute format('alter publication supabase_realtime add table public.%I', t);
    end if;
  end loop;
end $$;
