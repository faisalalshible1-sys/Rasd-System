-- =====================================================================
-- الإصدار 1.7.0 (الترحيل 38): قسم المخازن والأصول والخدمات العامة — الأساس والمخزون
--
--  قسم مستقل تماماً عن القسم المالي: لا قيود مالية ولا اعتماد على جداول المالية. كل جداوله جديدة بالبادئة st_،
--  ولا يُعدَّل من القائم إلا ما يلزم للدور الجديد ونطاقات الصلاحيات:
--  1. دور «موظف» (employee) للخدمة الذاتية: لا يُعدّ «عضواً» في بقية المنظومة (is_member)، فلا يرى أي قسم آخر ولا
--     يكتب فيه، ولا تُمنح له صلاحيات دقيقة ولا وحدات ولا نماذج؛ يرى في قسم المخازن ما صُرف له وحده ويؤكد استلامه.
--  2. نطاقات الصلاحيات: stores:admin (التهيئة والموظفون)، stores:manager (الأصناف واعتماد المستندات)،
--     stores:keeper:<المخزن> (حركات مخزنه)، stores:audit (اطلاع وتقارير فقط).
--  3. الهيكل: إدارات المقر، وسجل الموظفين (يُربط الحساب به اختيارياً)، والمواقع (مبنى/طابق/غرفة)، والمخازن.
--  4. الأصناف: التصنيفات (الثمانية في المستند)، والوحدات وتحويلاتها، وبطاقة الصنف بحدودها والاحتياطي الحرج والصلاحية.
--  5. المستندات: أول المدة والوارد والصرف والمرتجع والتحويل والتسوية: مسودة ← مقدَّم ← معتمد ← مرحَّل (أو مرفوض/ملغى).
--     الاعتماد يحجز الكمية الخارجة، والترحيل وحده يغيّر الرصيد ويكتب دفتر الحركات. المرحَّل لا يُعدَّل ولا يُحذف،
--     ويُصحَّح بمستند عكسي يمر بالمسار نفسه. الرصيد الفعلي لا ينزل عن الصفر، والصرف من الاحتياطي الحرج استثناء
--     لمدير المخازن بسبب مكتوب. فصل المهام (منشئ المستند لا يعتمده) إعداد مفعّل افتراضياً.
--  يُشغَّل بعد 20261128000037_contracts_v3.sql، وإعادة تشغيله آمنة. التراجع: supabase/rollbacks/20261129000038_stores_foundation_down.sql
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. دور «موظف» للخدمة الذاتية، وعزله عن بقية المنظومة
-- ---------------------------------------------------------------------
-- لا تُستعمل القيمة الجديدة في هذا الترحيل إلا نصاً (role::text)، فيصح تشغيله في معاملة واحدة.
alter type public.app_role add value if not exists 'employee';

-- «العضو» حساب نشط بدور في المنظومة غير دور الموظف: كل سياسات القراءة والكتابة القائمة تعتمد عليه
create or replace function public.is_member()
returns boolean
language sql stable security definer set search_path = public
as $$
  select exists (select 1 from public.profiles
                  where id = auth.uid() and active and role is not null and role::text <> 'employee'
                    and (locked_until is null or locked_until <= now()))
     and public.mfa_ok()
$$;

create or replace function public.has_grant(p_scope text)
returns boolean
language sql stable security definer set search_path = public
as $$
  select exists (select 1 from public.user_grants g join public.profiles me on me.id = g.user_id
                  where g.user_id = auth.uid() and g.scope = p_scope and me.active and me.role is not null
                    and me.role::text not in ('security_auditor', 'employee')
                    and (me.locked_until is null or me.locked_until <= now()))
$$;

create or replace function public.my_units()
returns text[]
language plpgsql stable security definer set search_path = public
as $$
declare
  r  text := coalesce(public.my_role()::text, '');
  me public.profiles;
  u  text[] := '{}';
begin
  if r in ('', 'security_auditor', 'employee') then
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
$$;

create or replace function public.my_forms()
returns text[]
language sql stable security definer set search_path = public
as $$
  select coalesce(array_agg(d.key order by d.sort), '{}'::text[])
    from public.form_defs d
    cross join (select coalesce(public.my_role()::text, '') as role) r
    join public.profiles me on me.id = auth.uid()
   where r.role not in ('', 'security_auditor', 'employee') and (
         r.role in ('director', 'office_staff')
      or (r.role = 'contracts' and 'contracts' = any (d.responsible))
      or (r.role = 'planning_qa' and 'planning_qa' = any (d.responsible))
      or (r.role = 'dept_head' and me.department = 'technical' and 'head:technical' = any (d.responsible))
      or (r.role = 'dept_head' and me.department = 'acceptance' and 'head:acceptance' = any (d.responsible))
      or exists (select 1 from public.user_grants g where g.user_id = me.id and g.scope = 'form:' || d.key))
$$;

-- الأقسام: الموظف يرى المخازن (صفحته) والدليل وحدهما، والمدير وأصحاب صلاحيات المخازن يرون القسم.
-- موظفو مكتب المدير لا يرون المخازن تلقائياً (استقلال القسم): يدخلونه بصلاحية stores:*.
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
$$;

-- قسم المخازن في تخصيص الواجهة (ui.layout)
create or replace function public.app_section_ok(p_key text)
returns boolean
language sql immutable set search_path = public
as $$
  select p_key in ('cycle', 'risks', 'swot', 'docs', 'supervision', 'heritage', 'planning_qa', 'safety', 'acceptance',
                   'chat', 'security', 'print', 'manual', 'stores')
$$;

-- لا تُمنح صلاحيات دقيقة لحساب الموظف (خدمته الذاتية محددة بسجله)
create or replace function public.set_user_grants(p_user uuid, p_scopes text[])
returns void
language plpgsql security definer set search_path = public
as $$
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
  if u.role::text = 'employee' and coalesce(array_length(v_new, 1), 0) > 0 then
    raise exception 'حساب الموظف للخدمة الذاتية وحدها؛ غيّر دوره أولاً لمنحه صلاحيات' using errcode = '22023';
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
$$;

-- ---------------------------------------------------------------------
-- 2. الهيكل: الإدارات، والموظفون، والمواقع، والمخازن
-- ---------------------------------------------------------------------
create table if not exists public.st_departments (
  id         uuid primary key default gen_random_uuid(),
  parent_id  uuid references public.st_departments (id) on delete restrict,
  code       text not null default '' check (length(code) <= 20),
  name       text not null check (length(btrim(name)) between 2 and 120),
  name_key   text generated always as (public.pm_text_norm(name)) stored,
  active     boolean not null default true,
  sort       integer not null default 0,
  created_at timestamptz not null default now(),
  created_by uuid references public.profiles (id) on delete set null,
  updated_at timestamptz not null default now(),
  updated_by uuid references public.profiles (id) on delete set null,
  constraint st_departments_not_self check (parent_id is distinct from id)
);
create unique index if not exists st_departments_name_uq on public.st_departments (coalesce(parent_id::text, ''), name_key);
create unique index if not exists st_departments_code_uq on public.st_departments (lower(code)) where code <> '';
create index if not exists st_departments_parent_idx on public.st_departments (parent_id);
create index if not exists st_departments_created_by_idx on public.st_departments (created_by);
create index if not exists st_departments_updated_by_idx on public.st_departments (updated_by);

create table if not exists public.st_employees (
  id            uuid primary key default gen_random_uuid(),
  emp_no        text not null default '' check (length(emp_no) <= 30),
  full_name     text not null check (length(btrim(full_name)) between 3 and 120),
  name_key      text generated always as (public.pm_text_norm(full_name)) stored,
  department_id uuid references public.st_departments (id) on delete set null,
  job_title     text not null default '' check (length(job_title) <= 120),
  phone         text not null default '' check (length(phone) <= 30),
  email         text not null default '' check (length(email) <= 160),
  profile_id    uuid references public.profiles (id) on delete set null,
  active        boolean not null default true,
  note          text not null default '' check (length(note) <= 500),
  created_at    timestamptz not null default now(),
  created_by    uuid references public.profiles (id) on delete set null,
  updated_at    timestamptz not null default now(),
  updated_by    uuid references public.profiles (id) on delete set null
);
create unique index if not exists st_employees_no_uq on public.st_employees (lower(emp_no)) where emp_no <> '';
create unique index if not exists st_employees_profile_uq on public.st_employees (profile_id) where profile_id is not null;
create index if not exists st_employees_department_idx on public.st_employees (department_id);
create index if not exists st_employees_name_idx on public.st_employees (name_key);
create index if not exists st_employees_created_by_idx on public.st_employees (created_by);
create index if not exists st_employees_updated_by_idx on public.st_employees (updated_by);

create table if not exists public.st_locations (
  id         uuid primary key default gen_random_uuid(),
  parent_id  uuid references public.st_locations (id) on delete restrict,
  kind       text not null check (kind in ('building', 'floor', 'room', 'area')),
  code       text not null default '' check (length(code) <= 20),
  name       text not null check (length(btrim(name)) between 1 and 120),
  name_key   text generated always as (public.pm_text_norm(name)) stored,
  active     boolean not null default true,
  sort       integer not null default 0,
  created_at timestamptz not null default now(),
  created_by uuid references public.profiles (id) on delete set null,
  updated_at timestamptz not null default now(),
  updated_by uuid references public.profiles (id) on delete set null,
  constraint st_locations_tree check ((kind = 'building') = (parent_id is null)),
  constraint st_locations_not_self check (parent_id is distinct from id)
);
create unique index if not exists st_locations_name_uq on public.st_locations (coalesce(parent_id::text, ''), name_key);
create index if not exists st_locations_parent_idx on public.st_locations (parent_id);
create index if not exists st_locations_created_by_idx on public.st_locations (created_by);
create index if not exists st_locations_updated_by_idx on public.st_locations (updated_by);

create table if not exists public.st_warehouses (
  id          uuid primary key default gen_random_uuid(),
  code        text not null check (code ~ '^[A-Za-z0-9_-]{1,12}$'),
  name        text not null check (length(btrim(name)) between 2 and 120),
  name_key    text generated always as (public.pm_text_norm(name)) stored,
  kind        text not null default 'sub' check (kind in ('main', 'sub')),
  parent_id   uuid references public.st_warehouses (id) on delete restrict,
  location_id uuid references public.st_locations (id) on delete set null,
  active      boolean not null default true,
  note        text not null default '' check (length(note) <= 500),
  sort        integer not null default 0,
  created_at  timestamptz not null default now(),
  created_by  uuid references public.profiles (id) on delete set null,
  updated_at  timestamptz not null default now(),
  updated_by  uuid references public.profiles (id) on delete set null,
  constraint st_warehouses_main_top check (kind = 'sub' or parent_id is null),
  constraint st_warehouses_not_self check (parent_id is distinct from id)
);
create unique index if not exists st_warehouses_code_uq on public.st_warehouses (lower(code));
create unique index if not exists st_warehouses_name_uq on public.st_warehouses (name_key);
create index if not exists st_warehouses_parent_idx on public.st_warehouses (parent_id);
create index if not exists st_warehouses_location_idx on public.st_warehouses (location_id);
create index if not exists st_warehouses_created_by_idx on public.st_warehouses (created_by);
create index if not exists st_warehouses_updated_by_idx on public.st_warehouses (updated_by);

-- ---------------------------------------------------------------------
-- 3. الأصناف: التصنيفات والوحدات وبطاقة الصنف
-- ---------------------------------------------------------------------
create table if not exists public.st_categories (
  id         uuid primary key default gen_random_uuid(),
  parent_id  uuid references public.st_categories (id) on delete restrict,
  code       text not null check (code ~ '^[A-Z0-9]{2,8}$'),
  name       text not null check (length(btrim(name)) between 2 and 80),
  name_key   text generated always as (public.pm_text_norm(name)) stored,
  kind       text not null default 'consumable' check (kind in ('consumable', 'asset')),
  active     boolean not null default true,
  sort       integer not null default 0,
  created_at timestamptz not null default now(),
  created_by uuid references public.profiles (id) on delete set null,
  updated_at timestamptz not null default now(),
  updated_by uuid references public.profiles (id) on delete set null,
  constraint st_categories_not_self check (parent_id is distinct from id)
);
create unique index if not exists st_categories_code_uq on public.st_categories (code);
create unique index if not exists st_categories_name_uq on public.st_categories (coalesce(parent_id::text, ''), name_key);
create index if not exists st_categories_parent_idx on public.st_categories (parent_id);
create index if not exists st_categories_created_by_idx on public.st_categories (created_by);
create index if not exists st_categories_updated_by_idx on public.st_categories (updated_by);

create table if not exists public.st_units (
  id         uuid primary key default gen_random_uuid(),
  name       text not null check (length(btrim(name)) between 1 and 30),
  name_key   text generated always as (public.pm_text_norm(name)) stored,
  active     boolean not null default true,
  sort       integer not null default 0,
  created_at timestamptz not null default now(),
  created_by uuid references public.profiles (id) on delete set null,
  updated_at timestamptz not null default now(),
  updated_by uuid references public.profiles (id) on delete set null
);
create unique index if not exists st_units_name_uq on public.st_units (name_key);
create index if not exists st_units_created_by_idx on public.st_units (created_by);
create index if not exists st_units_updated_by_idx on public.st_units (updated_by);

create table if not exists public.st_items (
  id            uuid primary key default gen_random_uuid(),
  code          text not null check (code ~ '^[A-Za-z0-9._/-]{1,30}$'),
  name          text not null check (length(btrim(name)) between 2 and 160),
  name_key      text generated always as (public.pm_text_norm(name)) stored,
  description   text not null default '' check (length(description) <= 1000),
  category_id   uuid not null references public.st_categories (id) on delete restrict,
  base_unit_id  uuid not null references public.st_units (id) on delete restrict,
  min_qty       numeric(14, 3) not null default 0 check (min_qty >= 0),
  max_qty       numeric(14, 3) check (max_qty is null or max_qty >= 0),
  reorder_qty   numeric(14, 3) not null default 0 check (reorder_qty >= 0),
  critical_qty  numeric(14, 3) not null default 0 check (critical_qty >= 0),
  tracks_expiry boolean not null default false,
  barcode       text not null default '' check (length(barcode) <= 60),
  active        boolean not null default true,
  created_at    timestamptz not null default now(),
  created_by    uuid references public.profiles (id) on delete set null,
  updated_at    timestamptz not null default now(),
  updated_by    uuid references public.profiles (id) on delete set null,
  constraint st_items_max_ge_min check (max_qty is null or max_qty >= min_qty)
);
create unique index if not exists st_items_code_uq on public.st_items (lower(code));
create unique index if not exists st_items_barcode_uq on public.st_items (barcode) where barcode <> '';
create index if not exists st_items_category_idx on public.st_items (category_id);
create index if not exists st_items_unit_idx on public.st_items (base_unit_id);
create index if not exists st_items_name_idx on public.st_items (name_key);
create index if not exists st_items_created_by_idx on public.st_items (created_by);
create index if not exists st_items_updated_by_idx on public.st_items (updated_by);

-- وحدات الصنف الأخرى: كم من الوحدة الأساسية في كل منها (الأساسية معاملها 1 ولا تُكتب هنا)
create table if not exists public.st_item_units (
  item_id uuid not null references public.st_items (id) on delete cascade,
  unit_id uuid not null references public.st_units (id) on delete restrict,
  factor  numeric(14, 4) not null check (factor > 0 and factor <= 1000000),
  primary key (item_id, unit_id)
);
create index if not exists st_item_units_unit_idx on public.st_item_units (unit_id);

-- ---------------------------------------------------------------------
-- 4. المستندات والأرصدة ودفتر الحركات
-- ---------------------------------------------------------------------
create table if not exists public.st_docs (
  id              uuid primary key default gen_random_uuid(),
  doc_no          text not null,
  kind            text not null check (kind in ('opening', 'receipt', 'issue', 'return', 'transfer', 'adjust')),
  status          text not null default 'draft'
                  check (status in ('draft', 'submitted', 'approved', 'posted', 'rejected', 'cancelled')),
  warehouse_id    uuid not null references public.st_warehouses (id) on delete restrict,
  to_warehouse_id uuid references public.st_warehouses (id) on delete restrict,
  department_id   uuid references public.st_departments (id) on delete set null,
  employee_id     uuid references public.st_employees (id) on delete set null,
  doc_date        date not null default current_date,
  party           text not null default '' check (length(party) <= 160),
  ref_no          text not null default '' check (length(ref_no) <= 60),
  note            text not null default '' check (length(note) <= 1000),
  reverses_id     uuid references public.st_docs (id) on delete restrict,
  override_note   text not null default '' check (length(override_note) <= 500),
  decision_note   text not null default '' check (length(decision_note) <= 500),
  created_at      timestamptz not null default now(),
  created_by      uuid references public.profiles (id) on delete set null,
  updated_at      timestamptz not null default now(),
  updated_by      uuid references public.profiles (id) on delete set null,
  submitted_at    timestamptz,
  submitted_by    uuid references public.profiles (id) on delete set null,
  approved_at     timestamptz,
  approved_by     uuid references public.profiles (id) on delete set null,
  posted_at       timestamptz,
  posted_by       uuid references public.profiles (id) on delete set null,
  decided_at      timestamptz,
  decided_by      uuid references public.profiles (id) on delete set null,
  confirmed_at    timestamptz,
  confirmed_by    uuid references public.profiles (id) on delete set null,
  constraint st_docs_transfer_target check ((kind = 'transfer') = (to_warehouse_id is not null)),
  constraint st_docs_transfer_distinct check (to_warehouse_id is distinct from warehouse_id),
  constraint st_docs_recipient check (kind not in ('issue', 'return') or department_id is not null or employee_id is not null),
  constraint st_docs_not_self check (reverses_id is distinct from id)
);
create unique index if not exists st_docs_no_uq on public.st_docs (doc_no);
-- مستند عكسي واحد قائم لكل مستند مرحَّل
create unique index if not exists st_docs_one_reversal on public.st_docs (reverses_id)
  where reverses_id is not null and status not in ('rejected', 'cancelled');
create index if not exists st_docs_warehouse_idx on public.st_docs (warehouse_id, status);
create index if not exists st_docs_to_warehouse_idx on public.st_docs (to_warehouse_id);
create index if not exists st_docs_department_idx on public.st_docs (department_id);
create index if not exists st_docs_employee_idx on public.st_docs (employee_id);
create index if not exists st_docs_date_idx on public.st_docs (doc_date desc, created_at desc);
create index if not exists st_docs_open_idx on public.st_docs (status) where status in ('draft', 'submitted', 'approved');
create index if not exists st_docs_created_by_idx on public.st_docs (created_by);
create index if not exists st_docs_updated_by_idx on public.st_docs (updated_by);
create index if not exists st_docs_submitted_by_idx on public.st_docs (submitted_by);
create index if not exists st_docs_approved_by_idx on public.st_docs (approved_by);
create index if not exists st_docs_posted_by_idx on public.st_docs (posted_by);
create index if not exists st_docs_decided_by_idx on public.st_docs (decided_by);
create index if not exists st_docs_confirmed_by_idx on public.st_docs (confirmed_by);

create table if not exists public.st_doc_lines (
  id          uuid primary key default gen_random_uuid(),
  doc_id      uuid not null references public.st_docs (id) on delete cascade,
  line_no     integer not null check (line_no between 1 and 500),
  item_id     uuid not null references public.st_items (id) on delete restrict,
  unit_id     uuid not null references public.st_units (id) on delete restrict,
  qty         numeric(14, 3) not null check (qty <> 0 and abs(qty) <= 100000000),
  factor      numeric(14, 4) not null default 1 check (factor > 0),
  base_qty    numeric(18, 3) generated always as (round(qty * factor, 3)) stored,
  expiry_date date,
  batch_no    text not null default '' check (length(batch_no) <= 40),
  note        text not null default '' check (length(note) <= 300),
  constraint st_doc_lines_no_uq unique (doc_id, line_no)
);
create index if not exists st_doc_lines_item_idx on public.st_doc_lines (item_id);
create index if not exists st_doc_lines_unit_idx on public.st_doc_lines (unit_id);

-- الرصيد لكل صنف في كل مخزن: الفعلي والمحجوز (المتاح = الفعلي − المحجوز)
create table if not exists public.st_stock (
  warehouse_id uuid not null references public.st_warehouses (id) on delete restrict,
  item_id      uuid not null references public.st_items (id) on delete restrict,
  on_hand      numeric(18, 3) not null default 0 check (on_hand >= 0),
  reserved     numeric(18, 3) not null default 0 check (reserved >= 0),
  updated_at   timestamptz not null default now(),
  primary key (warehouse_id, item_id),
  constraint st_stock_reserved_le check (reserved <= on_hand)
);
create index if not exists st_stock_item_idx on public.st_stock (item_id);

-- دفعات الأصناف ذات الصلاحية: تُصرف الأقرب انتهاءً أولاً
create table if not exists public.st_batches (
  id           uuid primary key default gen_random_uuid(),
  warehouse_id uuid not null references public.st_warehouses (id) on delete restrict,
  item_id      uuid not null references public.st_items (id) on delete restrict,
  expiry_date  date not null,
  batch_no     text not null default '' check (length(batch_no) <= 40),
  qty          numeric(18, 3) not null default 0 check (qty >= 0),
  constraint st_batches_uq unique (warehouse_id, item_id, expiry_date, batch_no)
);
create index if not exists st_batches_item_idx on public.st_batches (item_id);
create index if not exists st_batches_expiry_idx on public.st_batches (expiry_date) where qty > 0;

-- دفتر الحركات (بطاقة الصنف): سطر لكل أثر مرحَّل، لا يُعدَّل ولا يُحذف
create table if not exists public.st_moves (
  id            bigint generated always as identity primary key,
  doc_id        uuid not null references public.st_docs (id) on delete restrict,
  line_id       uuid references public.st_doc_lines (id) on delete set null,
  warehouse_id  uuid not null references public.st_warehouses (id) on delete restrict,
  item_id       uuid not null references public.st_items (id) on delete restrict,
  qty           numeric(18, 3) not null check (qty <> 0),
  balance_after numeric(18, 3) not null check (balance_after >= 0),
  expiry_date   date,
  batch_no      text not null default '',
  at            timestamptz not null default now(),
  by_user       uuid references public.profiles (id) on delete set null
);
create index if not exists st_moves_item_idx on public.st_moves (item_id, warehouse_id, id);
create index if not exists st_moves_doc_idx on public.st_moves (doc_id);
create index if not exists st_moves_line_idx on public.st_moves (line_id);
create index if not exists st_moves_warehouse_idx on public.st_moves (warehouse_id);
create index if not exists st_moves_by_idx on public.st_moves (by_user);

create table if not exists public.st_counters (
  scope text not null check (length(scope) between 1 and 40),
  year  integer not null,
  value integer not null default 0,
  primary key (scope, year)
);

-- إعدادات القسم: فصل المهام، ومدة التنبيه قبل انتهاء الصلاحية بالأيام
create table if not exists public.st_settings (
  key        text primary key check (key in ('separation', 'expiry_days')),
  value      jsonb not null,
  updated_at timestamptz not null default now(),
  updated_by uuid references public.profiles (id) on delete set null
);
create index if not exists st_settings_updated_by_idx on public.st_settings (updated_by);
insert into public.st_settings (key, value) values ('separation', 'true'::jsonb), ('expiry_days', '60'::jsonb)
on conflict (key) do nothing;

-- التصنيفات الثمانية في مستند المتطلبات، والوحدات الأساسية (قابلة للتعديل والإضافة من الواجهة)
insert into public.st_categories (code, name, kind, sort) values
  ('STA', 'القرطاسية', 'consumable', 1),
  ('PAP', 'الورق ومستلزمات الطباعة', 'consumable', 2),
  ('OFE', 'الأجهزة المكتبية', 'asset', 3),
  ('FUR', 'الأثاث', 'asset', 4),
  ('CLN', 'النظافة والخدمات', 'consumable', 5),
  ('HOS', 'الضيافة والاستهلاك اليومي', 'consumable', 6),
  ('MNT', 'الصيانة والتشغيل', 'consumable', 7),
  ('SAF', 'السلامة والطوارئ', 'consumable', 8)
on conflict (code) do nothing;

insert into public.st_units (name, sort)
select v.name, v.sort
  from (values ('قطعة', 1), ('علبة', 2), ('رزمة', 3), ('كرتونة', 4), ('عبوة', 5), ('لتر', 6), ('متر', 7)) v(name, sort)
 where not exists (select 1 from public.st_units u where u.name_key = public.pm_text_norm(v.name));

-- ---------------------------------------------------------------------
-- 5. الصلاحيات داخل القسم
-- ---------------------------------------------------------------------
-- نطاقات المنح الدقيق الجديدة: stores:admin|manager|audit و stores:keeper:<معرّف المخزن>
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
                     'stores:admin', 'stores:manager', 'stores:audit')
  end
$$;

alter table public.user_grants drop constraint if exists user_grants_scope_check;
alter table public.user_grants add constraint user_grants_scope_check check (
  scope ~ '^(form:[a-z0-9_]{1,40}|docs:(boq|letter|design|pm_view|pm_add|pm_duration|pm_dates|pm_approve)|supervision:reports|unit:[a-z_]{2,40}|swot|pm:(plan|track)|stores:(admin|manager|audit)|stores:keeper:[0-9a-f-]{36})$');

-- يرى كل القسم: المدير، ومدير المخازن، ومدير النظام في القسم، والمراجع
create or replace function public.st_sees_all()
returns boolean
language sql stable security definer set search_path = public
as $$
  select public.is_director() or public.has_grant('stores:manager') or public.has_grant('stores:admin')
      or public.has_grant('stores:audit')
$$;

-- المخازن التي يتولاها أمين المخزن
create or replace function public.st_my_warehouses()
returns uuid[]
language sql stable security definer set search_path = public
as $$
  select coalesce(array_agg(substr(g.scope, 15)::uuid order by g.scope), '{}'::uuid[])
    from public.user_grants g join public.profiles me on me.id = g.user_id
   where g.user_id = auth.uid() and g.scope like 'stores:keeper:%'
     and substr(g.scope, 15) ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' and me.active
     and me.role is not null and me.role::text not in ('security_auditor', 'employee')
     and (me.locked_until is null or me.locked_until <= now()) and public.mfa_ok()
$$;

-- من أهل القسم (يرى صفحاته غير الخدمة الذاتية)
create or replace function public.st_staff()
returns boolean
language sql stable security definer set search_path = public
as $$
  select public.st_sees_all() or cardinality(public.st_my_warehouses()) > 0
$$;

-- التهيئة والموظفون: المدير ومدير النظام في القسم
create or replace function public.st_can_setup()
returns boolean
language sql stable security definer set search_path = public
as $$
  select public.writes_allowed() and (public.is_director() or public.has_grant('stores:admin'))
$$;

-- بطاقات الأصناف: المدير ومدير المخازن ومدير النظام في القسم
create or replace function public.st_can_items()
returns boolean
language sql stable security definer set search_path = public
as $$
  select public.writes_allowed() and (public.is_director() or public.has_grant('stores:manager') or public.has_grant('stores:admin'))
$$;

-- اعتماد المستندات وعكسها: المدير ومدير المخازن
create or replace function public.st_can_approve()
returns boolean
language sql stable security definer set search_path = public
as $$
  select public.writes_allowed() and (public.is_director() or public.has_grant('stores:manager'))
$$;

-- حركات مخزن بعينه: أمينه، ومدير المخازن، والمدير
create or replace function public.st_can_move(p_warehouse uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
  select public.writes_allowed()
     and (public.is_director() or public.has_grant('stores:manager') or p_warehouse = any (public.st_my_warehouses()))
$$;

-- سجل الموظف المرتبط بالحساب الحالي (للخدمة الذاتية؛ لأي حساب نشط مربوط بسجل موظف)
create or replace function public.st_my_employee()
returns uuid
language sql stable security definer set search_path = public
as $$
  select e.id from public.st_employees e join public.profiles me on me.id = e.profile_id
   where e.profile_id = auth.uid() and e.active and me.active and me.role is not null
     and (me.locked_until is null or me.locked_until <= now()) and public.mfa_ok()
$$;

create or replace function public.st_setting_bool(p_key text, p_default boolean)
returns boolean
language sql stable security definer set search_path = public
as $$
  select coalesce((select case when jsonb_typeof(value) = 'boolean' then (value #>> '{}')::boolean end
                     from public.st_settings where key = p_key), p_default)
$$;

-- رقم المستند: RC-2026-0001 (وارد)، IS صرف، RT مرتجع، TR تحويل، AD تسوية، OB أول المدة، RV عكسي
create or replace function public.st_next_no(p_scope text, p_prefix text, p_year integer, p_pad integer default 4)
returns text
language plpgsql security definer set search_path = public
as $$
declare
  v integer;
begin
  insert into public.st_counters (scope, year, value) values (p_scope, p_year, 1)
  on conflict (scope, year) do update set value = public.st_counters.value + 1
  returning value into v;
  return p_prefix || case when p_year > 0 then '-' || p_year::text else '' end || '-' || lpad(v::text, p_pad, '0');
end;
$$;

-- ---------------------------------------------------------------------
-- 6. التهيئة: الإدارات والمواقع والمخازن والتصنيفات والوحدات والإعدادات
-- ---------------------------------------------------------------------
create or replace function public.st_text(p_data jsonb, p_key text, p_max integer)
returns text
language plpgsql immutable set search_path = public
as $$
declare
  v text := btrim(coalesce(p_data ->> p_key, ''));
begin
  if length(v) > p_max then
    raise exception 'النص في الحقل % أطول من % حرفاً', p_key, p_max using errcode = '22023';
  end if;
  return v;
end;
$$;

create or replace function public.st_num(p_data jsonb, p_key text, p_default numeric default 0)
returns numeric
language plpgsql immutable set search_path = public
as $$
begin
  if p_data -> p_key is null or jsonb_typeof(p_data -> p_key) = 'null' then
    return p_default;
  end if;
  if jsonb_typeof(p_data -> p_key) <> 'number' then
    raise exception 'قيمة غير رقمية في الحقل %', p_key using errcode = '22023';
  end if;
  return (p_data ->> p_key)::numeric;
end;
$$;

create or replace function public.st_uuid(p_data jsonb, p_key text)
returns uuid
language plpgsql immutable set search_path = public
as $$
declare
  v text := nullif(btrim(coalesce(p_data ->> p_key, '')), '');
begin
  if v is null then
    return null;
  end if;
  if v !~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$' then
    raise exception 'معرّف غير صالح في الحقل %', p_key using errcode = '22023';
  end if;
  return v::uuid;
end;
$$;

create or replace function public.st_save_department(p_id uuid, p_data jsonb)
returns uuid
language plpgsql security definer set search_path = public
as $$
declare
  old_r  public.st_departments;
  v_id   uuid := p_id;
  v_par  uuid;
  v_name text;
  v_code text;
  v_cur  uuid;
  i      integer := 0;
begin
  if not public.st_can_setup() then
    raise exception 'تهيئة المخازن لمدير النظام في القسم أو المدير' using errcode = '42501';
  end if;
  if jsonb_typeof(coalesce(p_data, 'null'::jsonb)) <> 'object' then
    raise exception 'بيانات غير صالحة' using errcode = '22023';
  end if;
  v_name := public.st_text(p_data, 'name', 120);
  v_code := public.st_text(p_data, 'code', 20);
  v_par := public.st_uuid(p_data, 'parent_id');
  if length(v_name) < 2 then
    raise exception 'اكتب اسم الإدارة' using errcode = '22023';
  end if;
  if v_par is not null and not exists (select 1 from public.st_departments where id = v_par) then
    raise exception 'الإدارة الأعلى غير موجودة' using errcode = '22023';
  end if;
  -- لا دورة في الشجرة
  v_cur := v_par;
  while v_cur is not null loop
    if v_cur = p_id then
      raise exception 'لا تكون الإدارة تابعة لنفسها أو لإحدى إداراتها' using errcode = '22023';
    end if;
    i := i + 1;
    exit when i > 20;
    select parent_id into v_cur from public.st_departments where id = v_cur;
  end loop;
  if p_id is null then
    insert into public.st_departments (parent_id, code, name, active, sort, created_by, updated_by)
    values (v_par, v_code, v_name, coalesce((p_data ->> 'active')::boolean, true), coalesce((p_data ->> 'sort')::integer, 0),
            auth.uid(), auth.uid())
    returning id into v_id;
  else
    select * into old_r from public.st_departments where id = p_id for update;
    if not found then
      raise exception 'الإدارة غير موجودة' using errcode = 'P0002';
    end if;
    update public.st_departments
       set parent_id = v_par, code = v_code, name = v_name, active = coalesce((p_data ->> 'active')::boolean, active),
           sort = coalesce((p_data ->> 'sort')::integer, sort), updated_at = now(), updated_by = auth.uid()
     where id = p_id;
  end if;
  perform public.write_audit('stores.setup', null, null,
    jsonb_build_object('entity', 'department', 'op', case when p_id is null then 'create' else 'update' end, 'id', v_id,
                       'name', v_name, 'from', case when p_id is null then null else to_jsonb(old_r) - 'name_key' end),
    v_name);
  return v_id;
exception
  when unique_violation then
    raise exception 'يوجد إدارة بالاسم أو الرمز نفسه' using errcode = '23505';
end;
$$;

create or replace function public.st_save_location(p_id uuid, p_data jsonb)
returns uuid
language plpgsql security definer set search_path = public
as $$
declare
  old_r  public.st_locations;
  v_id   uuid := p_id;
  v_par  uuid;
  v_kind text := coalesce(p_data ->> 'kind', '');
  v_name text;
  v_pk   text;
  v_cur  uuid;
  i      integer := 0;
begin
  if not public.st_can_setup() then
    raise exception 'تهيئة المخازن لمدير النظام في القسم أو المدير' using errcode = '42501';
  end if;
  if jsonb_typeof(coalesce(p_data, 'null'::jsonb)) <> 'object' then
    raise exception 'بيانات غير صالحة' using errcode = '22023';
  end if;
  if v_kind not in ('building', 'floor', 'room', 'area') then
    raise exception 'نوع الموقع: مبنى أو طابق أو غرفة أو مساحة' using errcode = '22023';
  end if;
  v_name := public.st_text(p_data, 'name', 120);
  if length(v_name) < 1 then
    raise exception 'اكتب اسم الموقع' using errcode = '22023';
  end if;
  v_par := public.st_uuid(p_data, 'parent_id');
  if v_kind = 'building' and v_par is not null then
    raise exception 'المبنى في أعلى الشجرة' using errcode = '22023';
  end if;
  if v_kind <> 'building' then
    select kind into v_pk from public.st_locations where id = v_par;
    if v_pk is null then
      raise exception 'حدّد الموقع الأعلى (المبنى أو الطابق)' using errcode = '22023';
    end if;
    if v_kind = 'floor' and v_pk <> 'building' then
      raise exception 'الطابق يتبع مبنى' using errcode = '22023';
    end if;
    if v_pk = 'room' then
      raise exception 'الغرفة لا يتبعها موقع آخر' using errcode = '22023';
    end if;
  end if;
  v_cur := v_par;
  while v_cur is not null loop
    if v_cur = p_id then
      raise exception 'لا يكون الموقع تابعاً لنفسه أو لأحد مواقعه' using errcode = '22023';
    end if;
    i := i + 1;
    exit when i > 20;
    select parent_id into v_cur from public.st_locations where id = v_cur;
  end loop;
  if p_id is null then
    insert into public.st_locations (parent_id, kind, code, name, active, sort, created_by, updated_by)
    values (v_par, v_kind, public.st_text(p_data, 'code', 20), v_name, coalesce((p_data ->> 'active')::boolean, true),
            coalesce((p_data ->> 'sort')::integer, 0), auth.uid(), auth.uid())
    returning id into v_id;
  else
    select * into old_r from public.st_locations where id = p_id for update;
    if not found then
      raise exception 'الموقع غير موجود' using errcode = 'P0002';
    end if;
    if old_r.kind <> v_kind and exists (select 1 from public.st_locations where parent_id = p_id) then
      raise exception 'لا يتغير نوع موقع تتبعه مواقع أخرى' using errcode = '22023';
    end if;
    update public.st_locations
       set parent_id = v_par, kind = v_kind, code = public.st_text(p_data, 'code', 20), name = v_name,
           active = coalesce((p_data ->> 'active')::boolean, active), sort = coalesce((p_data ->> 'sort')::integer, sort),
           updated_at = now(), updated_by = auth.uid()
     where id = p_id;
  end if;
  perform public.write_audit('stores.setup', null, null,
    jsonb_build_object('entity', 'location', 'op', case when p_id is null then 'create' else 'update' end, 'id', v_id,
                       'name', v_name, 'kind', v_kind, 'from', case when p_id is null then null else to_jsonb(old_r) - 'name_key' end),
    v_name);
  return v_id;
exception
  when unique_violation then
    raise exception 'يوجد موقع بالاسم نفسه في المكان نفسه' using errcode = '23505';
end;
$$;

create or replace function public.st_save_warehouse(p_id uuid, p_data jsonb)
returns uuid
language plpgsql security definer set search_path = public
as $$
declare
  old_r  public.st_warehouses;
  v_id   uuid := p_id;
  v_kind text := coalesce(p_data ->> 'kind', 'sub');
  v_par  uuid;
  v_loc  uuid;
  v_name text;
  v_code text;
begin
  if not public.st_can_setup() then
    raise exception 'تهيئة المخازن لمدير النظام في القسم أو المدير' using errcode = '42501';
  end if;
  if jsonb_typeof(coalesce(p_data, 'null'::jsonb)) <> 'object' then
    raise exception 'بيانات غير صالحة' using errcode = '22023';
  end if;
  if v_kind not in ('main', 'sub') then
    raise exception 'نوع المخزن رئيسي أو فرعي' using errcode = '22023';
  end if;
  v_name := public.st_text(p_data, 'name', 120);
  v_code := upper(public.st_text(p_data, 'code', 12));
  if length(v_name) < 2 then
    raise exception 'اكتب اسم المخزن' using errcode = '22023';
  end if;
  if v_code !~ '^[A-Z0-9_-]{1,12}$' then
    raise exception 'رمز المخزن حروف لاتينية وأرقام (حتى 12)' using errcode = '22023';
  end if;
  v_par := case when v_kind = 'sub' then public.st_uuid(p_data, 'parent_id') end;
  v_loc := public.st_uuid(p_data, 'location_id');
  if v_par is not null and not exists (select 1 from public.st_warehouses where id = v_par and kind = 'main') then
    raise exception 'المخزن الفرعي يتبع مخزناً رئيسياً' using errcode = '22023';
  end if;
  if v_loc is not null and not exists (select 1 from public.st_locations where id = v_loc) then
    raise exception 'الموقع غير موجود' using errcode = '22023';
  end if;
  if p_id is null then
    insert into public.st_warehouses (code, name, kind, parent_id, location_id, active, note, sort, created_by, updated_by)
    values (v_code, v_name, v_kind, v_par, v_loc, coalesce((p_data ->> 'active')::boolean, true),
            public.st_text(p_data, 'note', 500), coalesce((p_data ->> 'sort')::integer, 0), auth.uid(), auth.uid())
    returning id into v_id;
  else
    select * into old_r from public.st_warehouses where id = p_id for update;
    if not found then
      raise exception 'المخزن غير موجود' using errcode = 'P0002';
    end if;
    if v_kind = 'sub' and old_r.kind = 'main' and exists (select 1 from public.st_warehouses where parent_id = p_id) then
      raise exception 'مخزن رئيسي تتبعه مخازن فرعية' using errcode = '22023';
    end if;
    if not coalesce((p_data ->> 'active')::boolean, true) and old_r.active
       and exists (select 1 from public.st_stock where warehouse_id = p_id and (on_hand > 0 or reserved > 0)) then
      raise exception 'لا يُوقف مخزن فيه رصيد؛ حوّل رصيده أولاً' using errcode = '22023';
    end if;
    update public.st_warehouses
       set code = v_code, name = v_name, kind = v_kind, parent_id = v_par, location_id = v_loc,
           active = coalesce((p_data ->> 'active')::boolean, active), note = public.st_text(p_data, 'note', 500),
           sort = coalesce((p_data ->> 'sort')::integer, sort), updated_at = now(), updated_by = auth.uid()
     where id = p_id;
  end if;
  perform public.write_audit('stores.setup', null, null,
    jsonb_build_object('entity', 'warehouse', 'op', case when p_id is null then 'create' else 'update' end, 'id', v_id,
                       'name', v_name, 'code', v_code, 'from', case when p_id is null then null else to_jsonb(old_r) - 'name_key' end),
    v_name);
  return v_id;
exception
  when unique_violation then
    raise exception 'يوجد مخزن بالاسم أو الرمز نفسه' using errcode = '23505';
end;
$$;

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

create or replace function public.st_save_unit(p_id uuid, p_data jsonb)
returns uuid
language plpgsql security definer set search_path = public
as $$
declare
  old_r  public.st_units;
  v_id   uuid := p_id;
  v_name text;
begin
  if not public.st_can_setup() then
    raise exception 'تهيئة المخازن لمدير النظام في القسم أو المدير' using errcode = '42501';
  end if;
  if jsonb_typeof(coalesce(p_data, 'null'::jsonb)) <> 'object' then
    raise exception 'بيانات غير صالحة' using errcode = '22023';
  end if;
  v_name := public.st_text(p_data, 'name', 30);
  if length(v_name) < 1 then
    raise exception 'اكتب اسم الوحدة' using errcode = '22023';
  end if;
  if p_id is null then
    insert into public.st_units (name, active, sort, created_by, updated_by)
    values (v_name, coalesce((p_data ->> 'active')::boolean, true), coalesce((p_data ->> 'sort')::integer, 0), auth.uid(), auth.uid())
    returning id into v_id;
  else
    select * into old_r from public.st_units where id = p_id for update;
    if not found then
      raise exception 'الوحدة غير موجودة' using errcode = 'P0002';
    end if;
    update public.st_units
       set name = v_name, active = coalesce((p_data ->> 'active')::boolean, active),
           sort = coalesce((p_data ->> 'sort')::integer, sort), updated_at = now(), updated_by = auth.uid()
     where id = p_id;
  end if;
  perform public.write_audit('stores.setup', null, null,
    jsonb_build_object('entity', 'unit', 'op', case when p_id is null then 'create' else 'update' end, 'id', v_id,
                       'name', v_name, 'from', case when p_id is null then null else to_jsonb(old_r) - 'name_key' end),
    v_name);
  return v_id;
exception
  when unique_violation then
    raise exception 'توجد وحدة بالاسم نفسه' using errcode = '23505';
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
         or exists (select 1 from public.st_docs where department_id = p_id) then
        raise exception 'الإدارة مرتبطة بإدارات أو موظفين أو مستندات؛ أوقفها بدل حذفها' using errcode = '23503';
      end if;
      delete from public.st_departments where id = p_id;
    when 'location' then
      select to_jsonb(l) - 'name_key', l.name into v_row, v_name from public.st_locations l where id = p_id;
      if exists (select 1 from public.st_locations where parent_id = p_id)
         or exists (select 1 from public.st_warehouses where location_id = p_id) then
        raise exception 'الموقع تتبعه مواقع أو مخازن؛ أوقفه بدل حذفه' using errcode = '23503';
      end if;
      delete from public.st_locations where id = p_id;
    when 'warehouse' then
      select to_jsonb(w) - 'name_key', w.name into v_row, v_name from public.st_warehouses w where id = p_id;
      if exists (select 1 from public.st_docs where warehouse_id = p_id or to_warehouse_id = p_id)
         or exists (select 1 from public.st_stock where warehouse_id = p_id)
         or exists (select 1 from public.st_warehouses where parent_id = p_id) then
        raise exception 'للمخزن مستندات أو رصيد أو مخازن فرعية؛ أوقفه بدل حذفه' using errcode = '23503';
      end if;
      delete from public.user_grants where scope = 'stores:keeper:' || p_id::text;
      delete from public.st_warehouses where id = p_id;
    when 'category' then
      select to_jsonb(c) - 'name_key', c.name into v_row, v_name from public.st_categories c where id = p_id;
      if exists (select 1 from public.st_categories where parent_id = p_id)
         or exists (select 1 from public.st_items where category_id = p_id) then
        raise exception 'التصنيف فيه أصناف أو تصنيفات فرعية؛ أوقفه بدل حذفه' using errcode = '23503';
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

create or replace function public.st_set_settings(p_data jsonb)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  v_old jsonb;
  k     text;
begin
  if not public.st_can_setup() then
    raise exception 'إعدادات المخازن لمدير النظام في القسم أو المدير' using errcode = '42501';
  end if;
  if jsonb_typeof(coalesce(p_data, 'null'::jsonb)) <> 'object' then
    raise exception 'بيانات غير صالحة' using errcode = '22023';
  end if;
  select jsonb_object_agg(key, value) into v_old from public.st_settings;
  for k in select jsonb_object_keys(p_data) loop
    if k = 'separation' and jsonb_typeof(p_data -> k) = 'boolean' then
      null;
    elsif k = 'expiry_days' and jsonb_typeof(p_data -> k) = 'number' and (p_data ->> k)::numeric = round((p_data ->> k)::numeric)
          and (p_data ->> k)::numeric between 7 and 365 then
      null;
    else
      raise exception 'قيمة غير صالحة للإعداد %', k using errcode = '22023';
    end if;
    insert into public.st_settings (key, value, updated_at, updated_by) values (k, p_data -> k, now(), auth.uid())
    on conflict (key) do update set value = excluded.value, updated_at = now(), updated_by = auth.uid();
  end loop;
  perform public.write_audit('stores.settings', null, null, jsonb_build_object('from', v_old, 'to', p_data), 'إعدادات المخازن');
end;
$$;

-- ---------------------------------------------------------------------
-- 7. سجل الموظفين
-- ---------------------------------------------------------------------
create or replace function public.st_save_employee(p_id uuid, p_data jsonb)
returns uuid
language plpgsql security definer set search_path = public
as $$
declare
  old_r  public.st_employees;
  v_id   uuid := p_id;
  v_dep  uuid;
  v_prof uuid;
  v_name text;
begin
  if not public.st_can_setup() then
    raise exception 'سجل الموظفين لمدير النظام في القسم أو المدير' using errcode = '42501';
  end if;
  if jsonb_typeof(coalesce(p_data, 'null'::jsonb)) <> 'object' then
    raise exception 'بيانات غير صالحة' using errcode = '22023';
  end if;
  v_name := public.st_text(p_data, 'full_name', 120);
  if length(v_name) < 3 then
    raise exception 'اكتب اسم الموظف' using errcode = '22023';
  end if;
  v_dep := public.st_uuid(p_data, 'department_id');
  if v_dep is not null and not exists (select 1 from public.st_departments where id = v_dep) then
    raise exception 'الإدارة غير موجودة' using errcode = '22023';
  end if;
  v_prof := public.st_uuid(p_data, 'profile_id');
  if v_prof is not null and not exists (select 1 from public.profiles where id = v_prof) then
    raise exception 'الحساب غير موجود' using errcode = '22023';
  end if;
  if p_id is null then
    insert into public.st_employees (emp_no, full_name, department_id, job_title, phone, email, profile_id, active, note,
                                     created_by, updated_by)
    values (public.st_text(p_data, 'emp_no', 30), v_name, v_dep, public.st_text(p_data, 'job_title', 120),
            public.st_text(p_data, 'phone', 30), lower(public.st_text(p_data, 'email', 160)), v_prof,
            coalesce((p_data ->> 'active')::boolean, true), public.st_text(p_data, 'note', 500), auth.uid(), auth.uid())
    returning id into v_id;
  else
    select * into old_r from public.st_employees where id = p_id for update;
    if not found then
      raise exception 'الموظف غير موجود' using errcode = 'P0002';
    end if;
    update public.st_employees
       set emp_no = public.st_text(p_data, 'emp_no', 30), full_name = v_name, department_id = v_dep,
           job_title = public.st_text(p_data, 'job_title', 120), phone = public.st_text(p_data, 'phone', 30),
           email = lower(public.st_text(p_data, 'email', 160)), profile_id = v_prof,
           active = coalesce((p_data ->> 'active')::boolean, active), note = public.st_text(p_data, 'note', 500),
           updated_at = now(), updated_by = auth.uid()
     where id = p_id;
  end if;
  perform public.write_audit('stores.employee', null, null,
    jsonb_build_object('op', case when p_id is null then 'create' else 'update' end, 'id', v_id, 'name', v_name,
                       'profile', jsonb_build_object('from', old_r.profile_id, 'to', v_prof),
                       'from', case when p_id is null then null else to_jsonb(old_r) - 'name_key' end),
    v_name);
  return v_id;
exception
  when unique_violation then
    raise exception 'الرقم الوظيفي أو الحساب مسجّل لموظف آخر' using errcode = '23505';
end;
$$;

-- استيراد الموظفين من ملف بعد مراجعته: يُحدَّث الموجود بالرقم الوظيفي ويُضاف الجديد، والإدارة غير الموجودة تُنشأ
create or replace function public.st_import_employees(p_rows jsonb)
returns jsonb
language plpgsql security definer set search_path = public
as $$
declare
  r       jsonb;
  n       integer := 0;
  v_no    text;
  v_name  text;
  v_dname text;
  v_dep   uuid;
  v_ins   integer := 0;
  v_upd   integer := 0;
  v_deps  integer := 0;
  v_id    uuid;
begin
  if not public.st_can_setup() then
    raise exception 'سجل الموظفين لمدير النظام في القسم أو المدير' using errcode = '42501';
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
    v_no := btrim(coalesce(r ->> 'emp_no', ''));
    v_name := btrim(coalesce(r ->> 'full_name', ''));
    if v_no = '' or length(v_no) > 30 then
      raise exception 'الصف %: الرقم الوظيفي مطلوب (حتى 30 حرفاً)', n using errcode = '22023';
    end if;
    if length(v_name) not between 3 and 120 then
      raise exception 'الصف %: الاسم من 3 إلى 120 حرفاً', n using errcode = '22023';
    end if;
    v_dep := null;
    v_dname := btrim(coalesce(r ->> 'department', ''));
    if v_dname <> '' then
      select id into v_dep from public.st_departments
       where lower(code) = lower(v_dname) or name_key = public.pm_text_norm(v_dname)
       order by (lower(code) = lower(v_dname)) desc, (parent_id is null) desc limit 1;
      if v_dep is null then
        if length(v_dname) not between 2 and 120 then
          raise exception 'الصف %: اسم الإدارة غير صالح', n using errcode = '22023';
        end if;
        insert into public.st_departments (name, created_by, updated_by) values (v_dname, auth.uid(), auth.uid())
        returning id into v_dep;
        v_deps := v_deps + 1;
      end if;
    end if;
    select id into v_id from public.st_employees where lower(emp_no) = lower(v_no);
    if v_id is null then
      insert into public.st_employees (emp_no, full_name, department_id, job_title, phone, email, created_by, updated_by)
      values (v_no, v_name, v_dep, left(btrim(coalesce(r ->> 'job_title', '')), 120), left(btrim(coalesce(r ->> 'phone', '')), 30),
              lower(left(btrim(coalesce(r ->> 'email', '')), 160)), auth.uid(), auth.uid());
      v_ins := v_ins + 1;
    else
      update public.st_employees
         set full_name = v_name, department_id = coalesce(v_dep, department_id),
             job_title = coalesce(nullif(left(btrim(coalesce(r ->> 'job_title', '')), 120), ''), job_title),
             phone = coalesce(nullif(left(btrim(coalesce(r ->> 'phone', '')), 30), ''), phone),
             email = coalesce(nullif(lower(left(btrim(coalesce(r ->> 'email', '')), 160)), ''), email),
             updated_at = now(), updated_by = auth.uid()
       where id = v_id;
      v_upd := v_upd + 1;
    end if;
  end loop;
  perform public.write_audit('stores.employees_import', null, null,
    jsonb_build_object('rows', n, 'inserted', v_ins, 'updated', v_upd, 'departments', v_deps), 'استيراد الموظفين');
  return jsonb_build_object('rows', n, 'inserted', v_ins, 'updated', v_upd, 'departments', v_deps);
end;
$$;

-- ---------------------------------------------------------------------
-- 8. بطاقة الصنف
-- ---------------------------------------------------------------------
create or replace function public.st_save_item(p_id uuid, p_data jsonb)
returns uuid
language plpgsql security definer set search_path = public
as $$
declare
  old_r   public.st_items;
  v_id    uuid := p_id;
  v_cat   public.st_categories;
  v_unit  uuid;
  v_name  text;
  v_code  text;
  v_min   numeric;
  v_max   numeric;
  v_exp   boolean;
  v_used  boolean := false;
  u       jsonb;
  v_uid   uuid;
  v_units jsonb := '[]'::jsonb;
  v_old_u jsonb;
begin
  if not public.st_can_items() then
    raise exception 'بطاقات الأصناف لمدير المخازن أو مدير النظام في القسم' using errcode = '42501';
  end if;
  if jsonb_typeof(coalesce(p_data, 'null'::jsonb)) <> 'object' then
    raise exception 'بيانات غير صالحة' using errcode = '22023';
  end if;
  v_name := public.st_text(p_data, 'name', 160);
  if length(v_name) < 2 then
    raise exception 'اكتب اسم الصنف' using errcode = '22023';
  end if;
  select * into v_cat from public.st_categories where id = public.st_uuid(p_data, 'category_id');
  if not found then
    raise exception 'اختر تصنيف الصنف' using errcode = '22023';
  end if;
  v_unit := public.st_uuid(p_data, 'base_unit_id');
  if v_unit is null or not exists (select 1 from public.st_units where id = v_unit) then
    raise exception 'اختر الوحدة الأساسية' using errcode = '22023';
  end if;
  v_min := public.st_num(p_data, 'min_qty', 0);
  v_max := case when jsonb_typeof(p_data -> 'max_qty') = 'number' then (p_data ->> 'max_qty')::numeric end;
  if v_min < 0 or (v_max is not null and v_max < v_min) then
    raise exception 'الحد الأقصى لا يقل عن الحد الأدنى' using errcode = '22023';
  end if;
  if public.st_num(p_data, 'reorder_qty', 0) < 0 or public.st_num(p_data, 'critical_qty', 0) < 0 then
    raise exception 'الكميات لا تكون سالبة' using errcode = '22023';
  end if;
  v_exp := coalesce((p_data ->> 'tracks_expiry')::boolean, false);
  v_code := public.st_text(p_data, 'code', 30);
  if v_code <> '' and v_code !~ '^[A-Za-z0-9._/-]{1,30}$' then
    raise exception 'رمز الصنف حروف لاتينية وأرقام ونقطة وشرطة (حتى 30)' using errcode = '22023';
  end if;
  -- الوحدات الأخرى ومعاملاتها
  if jsonb_typeof(p_data -> 'units') = 'array' then
    if jsonb_array_length(p_data -> 'units') > 10 then
      raise exception 'الحد الأعلى 10 وحدات للصنف' using errcode = '22023';
    end if;
    for u in select x from jsonb_array_elements(p_data -> 'units') x loop
      v_uid := public.st_uuid(u, 'unit_id');
      if v_uid is null or not exists (select 1 from public.st_units where id = v_uid) then
        raise exception 'وحدة غير موجودة' using errcode = '22023';
      end if;
      if v_uid = v_unit then
        continue;
      end if;
      if jsonb_typeof(u -> 'factor') <> 'number' or (u ->> 'factor')::numeric <= 0 or (u ->> 'factor')::numeric > 1000000 then
        raise exception 'معامل التحويل رقم موجب' using errcode = '22023';
      end if;
      if v_units @> jsonb_build_array(jsonb_build_object('unit_id', v_uid)) then
        raise exception 'وحدة مكررة' using errcode = '22023';
      end if;
      v_units := v_units || jsonb_build_array(jsonb_build_object('unit_id', v_uid, 'factor', (u ->> 'factor')::numeric));
    end loop;
  end if;
  if p_id is null then
    if v_code = '' then
      v_code := public.st_next_no('item:' || v_cat.code, v_cat.code, 0, 4);
    end if;
    insert into public.st_items (code, name, description, category_id, base_unit_id, min_qty, max_qty, reorder_qty,
                                 critical_qty, tracks_expiry, barcode, active, created_by, updated_by)
    values (v_code, v_name, public.st_text(p_data, 'description', 1000), v_cat.id, v_unit, v_min, v_max,
            public.st_num(p_data, 'reorder_qty', 0), public.st_num(p_data, 'critical_qty', 0), v_exp,
            public.st_text(p_data, 'barcode', 60), coalesce((p_data ->> 'active')::boolean, true), auth.uid(), auth.uid())
    returning id into v_id;
  else
    select * into old_r from public.st_items where id = p_id for update;
    if not found then
      raise exception 'الصنف غير موجود' using errcode = 'P0002';
    end if;
    if v_code = '' then
      v_code := old_r.code;
    end if;
    v_used := exists (select 1 from public.st_doc_lines where item_id = p_id) or exists (select 1 from public.st_stock where item_id = p_id);
    if v_used and old_r.base_unit_id <> v_unit then
      raise exception 'لا تتغير الوحدة الأساسية لصنف له حركات' using errcode = '22023';
    end if;
    if old_r.tracks_expiry <> v_exp and exists (select 1 from public.st_stock where item_id = p_id and on_hand > 0) then
      raise exception 'لا يتغير تتبع الصلاحية لصنف له رصيد' using errcode = '22023';
    end if;
    select coalesce(jsonb_agg(jsonb_build_object('unit_id', unit_id, 'factor', factor) order by unit_id), '[]'::jsonb)
      into v_old_u from public.st_item_units where item_id = p_id;
    -- معامل وحدة مستعملة في مستند لا يتغير (المستندات تحفظ معاملها، والتغيير يربك القراءة)
    if exists (select 1 from public.st_item_units iu
                where iu.item_id = p_id
                  and exists (select 1 from public.st_doc_lines l where l.item_id = p_id and l.unit_id = iu.unit_id)
                  and not (v_units @> jsonb_build_array(jsonb_build_object('unit_id', iu.unit_id, 'factor', iu.factor)))) then
      raise exception 'وحدة مستعملة في مستندات لا تُحذف ولا يتغير معاملها' using errcode = '22023';
    end if;
    update public.st_items
       set code = v_code, name = v_name, description = public.st_text(p_data, 'description', 1000), category_id = v_cat.id,
           base_unit_id = v_unit, min_qty = v_min, max_qty = v_max, reorder_qty = public.st_num(p_data, 'reorder_qty', 0),
           critical_qty = public.st_num(p_data, 'critical_qty', 0), tracks_expiry = v_exp,
           barcode = public.st_text(p_data, 'barcode', 60), active = coalesce((p_data ->> 'active')::boolean, active),
           updated_at = now(), updated_by = auth.uid()
     where id = p_id;
  end if;
  delete from public.st_item_units where item_id = v_id;
  insert into public.st_item_units (item_id, unit_id, factor)
  select v_id, (x ->> 'unit_id')::uuid, (x ->> 'factor')::numeric from jsonb_array_elements(v_units) x;
  perform public.write_audit('stores.item', null, null,
    jsonb_build_object('op', case when p_id is null then 'create' else 'update' end, 'id', v_id, 'name', v_name, 'code', v_code,
                       'from', case when p_id is null then null else (to_jsonb(old_r) - 'name_key') || jsonb_build_object('units', v_old_u) end,
                       'units', v_units),
    v_name);
  return v_id;
exception
  when unique_violation then
    raise exception 'رمز الصنف أو الباركود مستعمل لصنف آخر' using errcode = '23505';
end;
$$;

-- استيراد الأصناف بعد مراجعتها: يُحدَّث الموجود بالرمز، وإلا يُضاف؛ الوحدة غير الموجودة تُنشأ والتصنيف يجب أن يوجد
create or replace function public.st_import_items(p_rows jsonb)
returns jsonb
language plpgsql security definer set search_path = public
as $$
declare
  r      jsonb;
  n      integer := 0;
  v_cat  public.st_categories;
  v_ct   text;
  v_un   text;
  v_unit uuid;
  v_code text;
  v_name text;
  v_id   uuid;
  v_ins  integer := 0;
  v_upd  integer := 0;
  v_unew integer := 0;
  v_min  numeric;
  v_max  numeric;
begin
  if not public.st_can_items() then
    raise exception 'بطاقات الأصناف لمدير المخازن أو مدير النظام في القسم' using errcode = '42501';
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
      raise exception 'الصف %: اسم الصنف من 2 إلى 160 حرفاً', n using errcode = '22023';
    end if;
    v_ct := btrim(coalesce(r ->> 'category', ''));
    select * into v_cat from public.st_categories
     where code = upper(v_ct) or name_key = public.pm_text_norm(v_ct)
     order by (code = upper(v_ct)) desc limit 1;
    if not found then
      raise exception 'الصف %: التصنيف «%» غير موجود', n, v_ct using errcode = '22023';
    end if;
    v_un := btrim(coalesce(r ->> 'unit', ''));
    if length(v_un) not between 1 and 30 then
      raise exception 'الصف %: الوحدة مطلوبة', n using errcode = '22023';
    end if;
    select id into v_unit from public.st_units where name_key = public.pm_text_norm(v_un);
    if v_unit is null then
      insert into public.st_units (name, created_by, updated_by) values (v_un, auth.uid(), auth.uid()) returning id into v_unit;
      v_unew := v_unew + 1;
    end if;
    v_min := coalesce(public.st_num(r, 'min_qty', 0), 0);
    v_max := case when jsonb_typeof(r -> 'max_qty') = 'number' then (r ->> 'max_qty')::numeric end;
    if v_min < 0 or (v_max is not null and v_max < v_min) or public.st_num(r, 'reorder_qty', 0) < 0
       or public.st_num(r, 'critical_qty', 0) < 0 then
      raise exception 'الصف %: الكميات غير صالحة (الأقصى لا يقل عن الأدنى، ولا سالب)', n using errcode = '22023';
    end if;
    v_code := btrim(coalesce(r ->> 'code', ''));
    if v_code <> '' and v_code !~ '^[A-Za-z0-9._/-]{1,30}$' then
      raise exception 'الصف %: رمز الصنف «%» غير صالح', n, v_code using errcode = '22023';
    end if;
    v_id := null;
    if v_code <> '' then
      select id into v_id from public.st_items where lower(code) = lower(v_code);
    end if;
    if v_id is null then
      if v_code = '' then
        v_code := public.st_next_no('item:' || v_cat.code, v_cat.code, 0, 4);
      end if;
      insert into public.st_items (code, name, description, category_id, base_unit_id, min_qty, max_qty, reorder_qty,
                                   critical_qty, tracks_expiry, barcode, created_by, updated_by)
      values (v_code, v_name, left(btrim(coalesce(r ->> 'description', '')), 1000), v_cat.id, v_unit, v_min, v_max,
              public.st_num(r, 'reorder_qty', 0), public.st_num(r, 'critical_qty', 0),
              coalesce((r ->> 'tracks_expiry')::boolean, false), left(btrim(coalesce(r ->> 'barcode', '')), 60),
              auth.uid(), auth.uid());
      v_ins := v_ins + 1;
    else
      if exists (select 1 from public.st_items where id = v_id and base_unit_id <> v_unit)
         and (exists (select 1 from public.st_doc_lines where item_id = v_id) or exists (select 1 from public.st_stock where item_id = v_id)) then
        raise exception 'الصف %: لا تتغير الوحدة الأساسية لصنف له حركات', n using errcode = '22023';
      end if;
      update public.st_items
         set name = v_name, category_id = v_cat.id, base_unit_id = v_unit, min_qty = v_min, max_qty = v_max,
             reorder_qty = public.st_num(r, 'reorder_qty', 0), critical_qty = public.st_num(r, 'critical_qty', 0),
             description = coalesce(nullif(left(btrim(coalesce(r ->> 'description', '')), 1000), ''), description),
             barcode = coalesce(nullif(left(btrim(coalesce(r ->> 'barcode', '')), 60), ''), barcode),
             updated_at = now(), updated_by = auth.uid()
       where id = v_id;
      v_upd := v_upd + 1;
    end if;
  end loop;
  perform public.write_audit('stores.items_import', null, null,
    jsonb_build_object('rows', n, 'inserted', v_ins, 'updated', v_upd, 'units', v_unew), 'استيراد الأصناف');
  return jsonb_build_object('rows', n, 'inserted', v_ins, 'updated', v_upd, 'units', v_unew);
exception
  when unique_violation then
    raise exception 'رمز صنف أو باركود مكرر في الملف أو مستعمل لصنف آخر' using errcode = '23505';
end;
$$;

-- ---------------------------------------------------------------------
-- 9. المستندات: الحفظ والمسار والترحيل
-- ---------------------------------------------------------------------
create or replace function public.st_doc_snapshot(p_id uuid)
returns jsonb
language sql stable security definer set search_path = public
as $$
  select (to_jsonb(d) - 'created_at' - 'updated_at') || jsonb_build_object(
           'lines', coalesce((select jsonb_agg(jsonb_build_object('line_no', l.line_no, 'item_id', l.item_id, 'unit_id', l.unit_id,
                                                                   'qty', l.qty, 'factor', l.factor, 'base_qty', l.base_qty,
                                                                   'expiry_date', l.expiry_date, 'batch_no', l.batch_no,
                                                                   'note', l.note) order by l.line_no)
                                from public.st_doc_lines l where l.doc_id = d.id), '[]'::jsonb))
    from public.st_docs d where d.id = p_id
$$;

-- عرض الكمية دون أصفار زائدة: 12 و12.5 و0.125
create or replace function public.st_fmt(p numeric)
returns text
language sql immutable set search_path = public
as $$
  select rtrim(rtrim(to_char(coalesce(p, 0), 'FM999999999999990.000'), '0'), '.')
$$;

create or replace function public.st_save_doc(p_id uuid, p_data jsonb)
returns uuid
language plpgsql security definer set search_path = public
as $$
declare
  d       public.st_docs;
  v_id    uuid := p_id;
  v_kind  text;
  v_wh    uuid;
  v_to    uuid;
  v_dep   uuid;
  v_emp   uuid;
  v_date  date;
  l       jsonb;
  n       integer := 0;
  v_item  public.st_items;
  v_unit  uuid;
  v_fac   numeric;
  v_qty   numeric;
  v_exp   date;
  v_year  integer := extract(year from (now() at time zone 'Africa/Tripoli'))::integer;
  v_pre   text;
begin
  if jsonb_typeof(coalesce(p_data, 'null'::jsonb)) <> 'object' then
    raise exception 'بيانات غير صالحة' using errcode = '22023';
  end if;
  if p_id is not null then
    select * into d from public.st_docs where id = p_id for update;
    if not found then
      raise exception 'المستند غير موجود' using errcode = 'P0002';
    end if;
    if d.status <> 'draft' then
      raise exception 'لا يُعدَّل إلا المستند المسودة' using errcode = '22023';
    end if;
    if d.reverses_id is not null then
      raise exception 'المستند العكسي يطابق أصله ولا تُعدَّل بنوده' using errcode = '22023';
    end if;
    v_kind := d.kind;
  else
    v_kind := coalesce(p_data ->> 'kind', '');
    if v_kind not in ('opening', 'receipt', 'issue', 'return', 'transfer', 'adjust') then
      raise exception 'نوع المستند غير معروف' using errcode = '22023';
    end if;
  end if;
  v_wh := public.st_uuid(p_data, 'warehouse_id');
  if v_wh is null or not exists (select 1 from public.st_warehouses where id = v_wh and active) then
    raise exception 'اختر المخزن' using errcode = '22023';
  end if;
  if not public.st_can_move(v_wh) or (p_id is not null and not public.st_can_move(d.warehouse_id)) then
    raise exception 'حركات هذا المخزن لأمينه أو لمدير المخازن' using errcode = '42501';
  end if;
  v_to := case when v_kind = 'transfer' then public.st_uuid(p_data, 'to_warehouse_id') end;
  if v_kind = 'transfer' then
    if v_to is null or v_to = v_wh or not exists (select 1 from public.st_warehouses where id = v_to and active) then
      raise exception 'اختر المخزن المحوَّل إليه (غير المخزن المحوَّل منه)' using errcode = '22023';
    end if;
  end if;
  v_dep := case when v_kind in ('issue', 'return') then public.st_uuid(p_data, 'department_id') end;
  v_emp := case when v_kind in ('issue', 'return') then public.st_uuid(p_data, 'employee_id') end;
  if v_kind in ('issue', 'return') then
    if v_emp is not null and not exists (select 1 from public.st_employees where id = v_emp) then
      raise exception 'الموظف غير موجود' using errcode = '22023';
    end if;
    if v_dep is not null and not exists (select 1 from public.st_departments where id = v_dep) then
      raise exception 'الإدارة غير موجودة' using errcode = '22023';
    end if;
    if v_dep is null and v_emp is not null then
      select department_id into v_dep from public.st_employees where id = v_emp;
    end if;
    if v_dep is null and v_emp is null then
      raise exception 'حدّد الإدارة أو الموظف %', case v_kind when 'issue' then 'المصروف له' else 'المُرجِع' end using errcode = '22023';
    end if;
  end if;
  v_date := coalesce(nullif(p_data ->> 'doc_date', '')::date, (now() at time zone 'Africa/Tripoli')::date);
  if v_date > (now() at time zone 'Africa/Tripoli')::date + 1 then
    raise exception 'تاريخ المستند في المستقبل' using errcode = '22023';
  end if;
  if jsonb_typeof(p_data -> 'lines') <> 'array' or jsonb_array_length(p_data -> 'lines') = 0 then
    raise exception 'أضف بنداً واحداً على الأقل' using errcode = '22023';
  end if;
  if jsonb_array_length(p_data -> 'lines') > 500 then
    raise exception 'الحد الأعلى 500 بند في المستند' using errcode = '22023';
  end if;

  if p_id is null then
    v_pre := case v_kind when 'opening' then 'OB' when 'receipt' then 'RC' when 'issue' then 'IS' when 'return' then 'RT'
                         when 'transfer' then 'TR' else 'AD' end;
    insert into public.st_docs (doc_no, kind, warehouse_id, to_warehouse_id, department_id, employee_id, doc_date, party, ref_no,
                                note, created_by, updated_by)
    values (public.st_next_no('doc:' || v_pre, v_pre, v_year), v_kind, v_wh, v_to, v_dep, v_emp, v_date,
            public.st_text(p_data, 'party', 160), public.st_text(p_data, 'ref_no', 60), public.st_text(p_data, 'note', 1000),
            auth.uid(), auth.uid())
    returning id into v_id;
  else
    update public.st_docs
       set warehouse_id = v_wh, to_warehouse_id = v_to, department_id = v_dep, employee_id = v_emp, doc_date = v_date,
           party = public.st_text(p_data, 'party', 160), ref_no = public.st_text(p_data, 'ref_no', 60),
           note = public.st_text(p_data, 'note', 1000), updated_at = now(), updated_by = auth.uid()
     where id = p_id;
    delete from public.st_doc_lines where doc_id = p_id;
  end if;

  for l in select x from jsonb_array_elements(p_data -> 'lines') x loop
    n := n + 1;
    select * into v_item from public.st_items where id = public.st_uuid(l, 'item_id');
    if not found then
      raise exception 'البند %: الصنف غير موجود', n using errcode = '22023';
    end if;
    if not v_item.active then
      raise exception 'البند %: الصنف «%» موقوف', n, v_item.name using errcode = '22023';
    end if;
    v_unit := coalesce(public.st_uuid(l, 'unit_id'), v_item.base_unit_id);
    if v_unit = v_item.base_unit_id then
      v_fac := 1;
    else
      select factor into v_fac from public.st_item_units where item_id = v_item.id and unit_id = v_unit;
      if v_fac is null then
        raise exception 'البند %: الوحدة غير معرّفة للصنف «%»', n, v_item.name using errcode = '22023';
      end if;
    end if;
    if jsonb_typeof(l -> 'qty') <> 'number' then
      raise exception 'البند %: الكمية رقم', n using errcode = '22023';
    end if;
    v_qty := round((l ->> 'qty')::numeric, 3);
    if v_qty = 0 or (v_kind <> 'adjust' and v_qty < 0) or abs(v_qty) > 100000000 then
      raise exception 'البند %: الكمية موجبة%', n, case when v_kind = 'adjust' then ' أو سالبة للنقص، ولا تكون صفراً' else '' end
        using errcode = '22023';
    end if;
    v_exp := nullif(l ->> 'expiry_date', '')::date;
    -- الداخل من صنف يتتبع الصلاحية يحتاج تاريخها؛ والخارج يُصرف من الأقرب انتهاءً
    if v_item.tracks_expiry and (v_kind in ('opening', 'receipt', 'return') or (v_kind = 'adjust' and v_qty > 0)) and v_exp is null then
      raise exception 'البند %: حدّد تاريخ انتهاء صلاحية «%»', n, v_item.name using errcode = '22023';
    end if;
    if not v_item.tracks_expiry or not (v_kind in ('opening', 'receipt', 'return') or (v_kind = 'adjust' and v_qty > 0)) then
      v_exp := null;
    end if;
    insert into public.st_doc_lines (doc_id, line_no, item_id, unit_id, qty, factor, expiry_date, batch_no, note)
    values (v_id, n, v_item.id, v_unit, v_qty, v_fac, v_exp,
            case when v_exp is null then '' else public.st_text(l, 'batch_no', 40) end, public.st_text(l, 'note', 300));
  end loop;

  perform public.write_audit('stores.doc_save', null, null,
    jsonb_build_object('op', case when p_id is null then 'create' else 'update' end, 'id', v_id,
                       'doc', public.st_doc_snapshot(v_id), 'from', case when p_id is null then null else (to_jsonb(d) - 'created_at') end),
    (select doc_no from public.st_docs where id = v_id));
  return v_id;
end;
$$;

-- الكميات الخارجة التي يحجزها الاعتماد (لكل مخزن وصنف، بالوحدة الأساسية)
create or replace function public.st_doc_outgoing(p_id uuid)
returns table (warehouse_id uuid, item_id uuid, qty numeric)
language sql stable security definer set search_path = public
as $$
  with d as (select * from public.st_docs where id = p_id),
  raw as (
    -- المستند العادي من بنوده
    select d.warehouse_id, l.item_id, l.base_qty as q
      from d join public.st_doc_lines l on l.doc_id = d.id
     where d.reverses_id is null and (d.kind in ('issue', 'transfer') or (d.kind = 'adjust' and l.base_qty < 0))
    union all
    -- العكسي من حركات أصله: كل داخل فيه يصير خارجاً
    select m.warehouse_id, m.item_id, m.qty
      from d join public.st_moves m on m.doc_id = d.reverses_id
     where d.reverses_id is not null and m.qty > 0
  )
  select warehouse_id, item_id, sum(abs(q))::numeric from raw group by warehouse_id, item_id
$$;

-- حجز الخارج عند الاعتماد (p_sign = 1) أو فكّه عند الإلغاء (p_sign = -1)
create or replace function public.st_reserve(p_id uuid, p_sign integer, p_override boolean default false)
returns jsonb
language plpgsql security definer set search_path = public
as $$
declare
  o       record;
  s       public.st_stock;
  it      public.st_items;
  wh      text;
  v_crit  jsonb := '[]'::jsonb;
  v_kind  text;
begin
  select kind into v_kind from public.st_docs where id = p_id;
  for o in select * from public.st_doc_outgoing(p_id) order by warehouse_id, item_id loop
    select * into it from public.st_items where id = o.item_id;
    select name into wh from public.st_warehouses where id = o.warehouse_id;
    select * into s from public.st_stock where warehouse_id = o.warehouse_id and item_id = o.item_id for update;
    if p_sign > 0 then
      if not found or s.on_hand - s.reserved < o.qty then
        raise exception 'المتاح من «%» في مخزن «%» هو %، والمطلوب %', it.name, wh,
          public.st_fmt(s.on_hand - s.reserved), public.st_fmt(o.qty) using errcode = 'P0001';
      end if;
      if v_kind in ('issue', 'transfer') and s.on_hand - s.reserved - o.qty < it.critical_qty then
        v_crit := v_crit || jsonb_build_array(jsonb_build_object('item', it.name, 'warehouse', wh,
                                                                  'available', s.on_hand - s.reserved, 'qty', o.qty,
                                                                  'critical', it.critical_qty));
        if not p_override then
          raise exception 'صرف «%» يمس الاحتياطي الحرج في مخزن «%» (الاحتياطي %)؛ يلزم استثناء من مدير المخازن بسبب مكتوب',
            it.name, wh, public.st_fmt(it.critical_qty) using errcode = 'P0001';
        end if;
      end if;
      update public.st_stock set reserved = reserved + o.qty, updated_at = now()
       where warehouse_id = o.warehouse_id and item_id = o.item_id;
    else
      update public.st_stock set reserved = greatest(reserved - o.qty, 0), updated_at = now()
       where warehouse_id = o.warehouse_id and item_id = o.item_id;
    end if;
  end loop;
  return v_crit;
end;
$$;

-- إدخال كمية إلى مخزن (وإلى دفعتها إن كان الصنف يتتبع الصلاحية)، وسطرها في دفتر الحركات
create or replace function public.st_apply_in(p_doc uuid, p_line uuid, p_wh uuid, p_item uuid, p_qty numeric,
                                              p_expiry date, p_batch text)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  v_bal numeric;
  v_exp boolean;
begin
  select tracks_expiry into v_exp from public.st_items where id = p_item;
  insert into public.st_stock (warehouse_id, item_id, on_hand, reserved) values (p_wh, p_item, p_qty, 0)
  on conflict (warehouse_id, item_id) do update set on_hand = public.st_stock.on_hand + excluded.on_hand, updated_at = now()
  returning on_hand into v_bal;
  if v_exp then
    if p_expiry is null then
      raise exception 'تاريخ الصلاحية مطلوب لإدخال الصنف' using errcode = '22023';
    end if;
    insert into public.st_batches (warehouse_id, item_id, expiry_date, batch_no, qty)
    values (p_wh, p_item, p_expiry, coalesce(p_batch, ''), p_qty)
    on conflict (warehouse_id, item_id, expiry_date, batch_no) do update set qty = public.st_batches.qty + excluded.qty;
  end if;
  insert into public.st_moves (doc_id, line_id, warehouse_id, item_id, qty, balance_after, expiry_date, batch_no, by_user)
  values (p_doc, p_line, p_wh, p_item, p_qty, v_bal, case when v_exp then p_expiry end,
          case when v_exp then coalesce(p_batch, '') else '' end, auth.uid());
end;
$$;

-- إخراج كمية محجوزة من مخزن: من الدفعة المحددة (العكسي) أو من الأقرب انتهاءً؛ تُرجع الدفعات المصروفة
create or replace function public.st_apply_out(p_doc uuid, p_line uuid, p_wh uuid, p_item uuid, p_qty numeric,
                                               p_expiry date default null, p_batch text default null)
returns jsonb
language plpgsql security definer set search_path = public
as $$
declare
  s      public.st_stock;
  it     public.st_items;
  b      public.st_batches;
  v_left numeric := p_qty;
  v_take numeric;
  v_bal  numeric;
  v_out  jsonb := '[]'::jsonb;
begin
  select * into it from public.st_items where id = p_item;
  select * into s from public.st_stock where warehouse_id = p_wh and item_id = p_item for update;
  if not found or s.on_hand < p_qty or s.reserved < p_qty then
    raise exception 'رصيد «%» لا يكفي للترحيل', it.name using errcode = 'P0001';
  end if;
  if not it.tracks_expiry then
    update public.st_stock set on_hand = on_hand - p_qty, reserved = reserved - p_qty, updated_at = now()
     where warehouse_id = p_wh and item_id = p_item returning on_hand into v_bal;
    insert into public.st_moves (doc_id, line_id, warehouse_id, item_id, qty, balance_after, by_user)
    values (p_doc, p_line, p_wh, p_item, -p_qty, v_bal, auth.uid());
    return jsonb_build_array(jsonb_build_object('qty', p_qty, 'expiry_date', null, 'batch_no', ''));
  end if;
  for b in select * from public.st_batches
            where warehouse_id = p_wh and item_id = p_item and qty > 0
              and (p_expiry is null or (expiry_date = p_expiry and batch_no = coalesce(p_batch, '')))
            order by expiry_date, batch_no
            for update loop
    exit when v_left <= 0;
    v_take := least(b.qty, v_left);
    update public.st_batches set qty = qty - v_take where id = b.id;
    update public.st_stock set on_hand = on_hand - v_take, reserved = reserved - v_take, updated_at = now()
     where warehouse_id = p_wh and item_id = p_item returning on_hand into v_bal;
    insert into public.st_moves (doc_id, line_id, warehouse_id, item_id, qty, balance_after, expiry_date, batch_no, by_user)
    values (p_doc, p_line, p_wh, p_item, -v_take, v_bal, b.expiry_date, b.batch_no, auth.uid());
    v_out := v_out || jsonb_build_array(jsonb_build_object('qty', v_take, 'expiry_date', b.expiry_date, 'batch_no', b.batch_no));
    v_left := v_left - v_take;
  end loop;
  if v_left > 0 then
    raise exception 'دفعات صلاحية «%» لا تغطي الكمية%', it.name,
      case when p_expiry is not null then ' (الدفعة الأصلية صُرف منها)' else '' end using errcode = 'P0001';
  end if;
  return v_out;
end;
$$;

-- الترحيل: يطبّق المستند المعتمد على الأرصدة ويكتب دفتر الحركات
create or replace function public.st_post(p_id uuid)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  d   public.st_docs;
  l   public.st_doc_lines;
  m   public.st_moves;
  bt  jsonb;
  x   jsonb;
begin
  select * into d from public.st_docs where id = p_id;
  if d.reverses_id is not null then
    -- العكسي: كل حركة في الأصل بعكسها، بدفعتها نفسها (الخارج أولاً ثم الداخل)
    for m in select * from public.st_moves where doc_id = d.reverses_id and qty > 0 order by id loop
      perform public.st_apply_out(p_id, null, m.warehouse_id, m.item_id, m.qty, m.expiry_date, m.batch_no);
    end loop;
    for m in select * from public.st_moves where doc_id = d.reverses_id and qty < 0 order by id loop
      perform public.st_apply_in(p_id, null, m.warehouse_id, m.item_id, -m.qty, m.expiry_date, m.batch_no);
    end loop;
    return;
  end if;
  for l in select * from public.st_doc_lines where doc_id = p_id order by line_no loop
    if d.kind in ('opening', 'receipt', 'return') or (d.kind = 'adjust' and l.base_qty > 0) then
      perform public.st_apply_in(p_id, l.id, d.warehouse_id, l.item_id, abs(l.base_qty), l.expiry_date, l.batch_no);
    elsif d.kind = 'transfer' then
      bt := public.st_apply_out(p_id, l.id, d.warehouse_id, l.item_id, l.base_qty);
      for x in select y from jsonb_array_elements(bt) y loop
        perform public.st_apply_in(p_id, l.id, d.to_warehouse_id, l.item_id, (x ->> 'qty')::numeric,
                                   nullif(x ->> 'expiry_date', '')::date, x ->> 'batch_no');
      end loop;
    else
      perform public.st_apply_out(p_id, l.id, d.warehouse_id, l.item_id, abs(l.base_qty));
    end if;
  end loop;
end;
$$;

-- إجراءات المسار: submit تقديم، return إعادة للتعديل، reject رفض، approve اعتماد، post ترحيل، cancel إلغاء
create or replace function public.st_doc_action(p_id uuid, p_action text, p_note text default '', p_override boolean default false)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  d       public.st_docs;
  v_note  text := btrim(coalesce(p_note, ''));
  v_crit  jsonb := '[]'::jsonb;
  v_sep   boolean := public.st_setting_bool('separation', true);
  v_from  text;
begin
  select * into d from public.st_docs where id = p_id for update;
  if not found then
    raise exception 'المستند غير موجود' using errcode = 'P0002';
  end if;
  if length(v_note) > 500 then
    raise exception 'الملاحظة حتى 500 حرف' using errcode = '22023';
  end if;
  v_from := d.status;
  case p_action
    when 'submit' then
      if d.status <> 'draft' then
        raise exception 'لا يُقدَّم إلا المستند المسودة' using errcode = '22023';
      end if;
      if not public.st_can_move(d.warehouse_id) then
        raise exception 'تقديم مستندات هذا المخزن لأمينه أو لمدير المخازن' using errcode = '42501';
      end if;
      if d.reverses_id is null and not exists (select 1 from public.st_doc_lines where doc_id = p_id) then
        raise exception 'المستند بلا بنود' using errcode = '22023';
      end if;
      update public.st_docs set status = 'submitted', submitted_at = now(), submitted_by = auth.uid(), decision_note = '',
                                updated_at = now(), updated_by = auth.uid()
       where id = p_id;
    when 'return', 'reject' then
      if d.status <> 'submitted' then
        raise exception 'يُعاد أو يُرفض المستند المقدَّم وحده' using errcode = '22023';
      end if;
      if not public.st_can_approve() then
        raise exception 'قرار المستندات لمدير المخازن أو المدير' using errcode = '42501';
      end if;
      if length(v_note) < 3 then
        raise exception 'اكتب سبب %', case p_action when 'return' then 'الإعادة' else 'الرفض' end using errcode = '22023';
      end if;
      update public.st_docs set status = case p_action when 'return' then 'draft' else 'rejected' end, decision_note = v_note,
                                decided_at = now(), decided_by = auth.uid(), updated_at = now(), updated_by = auth.uid()
       where id = p_id;
    when 'approve' then
      if d.status <> 'submitted' then
        raise exception 'يُعتمد المستند المقدَّم وحده' using errcode = '22023';
      end if;
      if not public.st_can_approve() then
        raise exception 'اعتماد المستندات لمدير المخازن أو المدير' using errcode = '42501';
      end if;
      if v_sep and auth.uid() in (d.created_by, d.submitted_by) then
        raise exception 'فصل المهام: لا يعتمد المستند من أنشأه أو قدّمه' using errcode = '42501';
      end if;
      if p_override and length(v_note) < 5 then
        raise exception 'اكتب سبب استثناء الاحتياطي الحرج' using errcode = '22023';
      end if;
      v_crit := public.st_reserve(p_id, 1, p_override);
      update public.st_docs set status = 'approved', approved_at = now(), approved_by = auth.uid(), decision_note = v_note,
                                override_note = case when jsonb_array_length(v_crit) > 0 then v_note else '' end,
                                updated_at = now(), updated_by = auth.uid()
       where id = p_id;
    when 'post' then
      if d.status <> 'approved' then
        raise exception 'يُرحَّل المستند المعتمد وحده' using errcode = '22023';
      end if;
      if not public.st_can_move(d.warehouse_id) then
        raise exception 'ترحيل مستندات هذا المخزن لأمينه أو لمدير المخازن' using errcode = '42501';
      end if;
      perform public.st_post(p_id);
      update public.st_docs set status = 'posted', posted_at = now(), posted_by = auth.uid(), updated_at = now(),
                                updated_by = auth.uid()
       where id = p_id;
    when 'cancel' then
      if d.status in ('posted', 'rejected', 'cancelled') then
        raise exception 'لا يُلغى المستند %', case d.status when 'posted' then 'المرحَّل (اعكسه بمستند عكسي)' else 'المنتهي' end
          using errcode = '22023';
      end if;
      if d.status = 'approved' then
        if not public.st_can_approve() then
          raise exception 'إلغاء المستند المعتمد لمدير المخازن أو المدير' using errcode = '42501';
        end if;
        if length(v_note) < 3 then
          raise exception 'اكتب سبب الإلغاء' using errcode = '22023';
        end if;
        perform public.st_reserve(p_id, -1);
      elsif not (public.st_can_move(d.warehouse_id) or public.st_can_approve()) then
        raise exception 'إلغاء مستندات هذا المخزن لأمينه أو لمدير المخازن' using errcode = '42501';
      end if;
      update public.st_docs set status = 'cancelled', decision_note = v_note, decided_at = now(), decided_by = auth.uid(),
                                updated_at = now(), updated_by = auth.uid()
       where id = p_id;
    else
      raise exception 'إجراء غير معروف' using errcode = '22023';
  end case;
  perform public.write_audit('stores.doc_' || p_action, null, null,
    jsonb_build_object('id', p_id, 'doc_no', d.doc_no, 'kind', d.kind, 'status', jsonb_build_object('from', v_from,
                       'to', (select status from public.st_docs where id = p_id)), 'note', v_note,
                       'override', case when jsonb_array_length(v_crit) > 0 then v_crit end,
                       'doc', case when p_action in ('approve', 'post') then public.st_doc_snapshot(p_id) end),
    d.doc_no);
end;
$$;

-- حذف المسودة التي لم تُقدَّم قط (المقدَّمة سابقاً تُلغى ليبقى أثرها)
create or replace function public.st_delete_doc(p_id uuid)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  d      public.st_docs;
  v_snap jsonb;
begin
  select * into d from public.st_docs where id = p_id for update;
  if not found then
    raise exception 'المستند غير موجود' using errcode = 'P0002';
  end if;
  if d.status <> 'draft' or d.submitted_at is not null then
    raise exception 'يُحذف المستند المسودة الذي لم يُقدَّم قط؛ ألغِ غيره' using errcode = '22023';
  end if;
  if not public.st_can_move(d.warehouse_id) then
    raise exception 'مستندات هذا المخزن لأمينه أو لمدير المخازن' using errcode = '42501';
  end if;
  v_snap := public.st_doc_snapshot(p_id);
  delete from public.st_docs where id = p_id;
  perform public.write_audit('stores.doc_delete', null, null, jsonb_build_object('id', p_id, 'doc', v_snap), d.doc_no);
end;
$$;

-- مستند عكسي لمستند مرحَّل: مسودة بالبنود نفسها تمر بالتقديم والاعتماد والترحيل
create or replace function public.st_reverse_doc(p_id uuid, p_note text)
returns uuid
language plpgsql security definer set search_path = public
as $$
declare
  d      public.st_docs;
  v_id   uuid;
  v_note text := btrim(coalesce(p_note, ''));
  v_year integer := extract(year from (now() at time zone 'Africa/Tripoli'))::integer;
begin
  if not public.st_can_approve() then
    raise exception 'عكس المستندات لمدير المخازن أو المدير' using errcode = '42501';
  end if;
  select * into d from public.st_docs where id = p_id for update;
  if not found then
    raise exception 'المستند غير موجود' using errcode = 'P0002';
  end if;
  if d.status <> 'posted' then
    raise exception 'يُعكس المستند المرحَّل وحده' using errcode = '22023';
  end if;
  if d.reverses_id is not null then
    raise exception 'لا يُعكس مستند عكسي؛ أنشئ مستنداً جديداً' using errcode = '22023';
  end if;
  if length(v_note) < 5 or length(v_note) > 500 then
    raise exception 'اكتب سبب العكس (من 5 إلى 500 حرف)' using errcode = '22023';
  end if;
  if exists (select 1 from public.st_docs where reverses_id = p_id and status not in ('rejected', 'cancelled')) then
    raise exception 'للمستند عكسي قائم' using errcode = '22023';
  end if;
  insert into public.st_docs (doc_no, kind, warehouse_id, to_warehouse_id, department_id, employee_id, doc_date, party, ref_no,
                              note, reverses_id, created_by, updated_by)
  values (public.st_next_no('doc:RV', 'RV', v_year), d.kind, d.warehouse_id, d.to_warehouse_id, d.department_id, d.employee_id,
          (now() at time zone 'Africa/Tripoli')::date, d.party, d.ref_no, v_note, p_id, auth.uid(), auth.uid())
  returning id into v_id;
  insert into public.st_doc_lines (doc_id, line_no, item_id, unit_id, qty, factor, expiry_date, batch_no, note)
  select v_id, line_no, item_id, unit_id, qty, factor, expiry_date, batch_no, note from public.st_doc_lines where doc_id = p_id;
  perform public.write_audit('stores.doc_reverse', null, null,
    jsonb_build_object('id', v_id, 'reverses', p_id, 'reverses_no', d.doc_no, 'note', v_note),
    (select doc_no from public.st_docs where id = v_id));
  return v_id;
end;
$$;

-- تأكيد الموظف استلام ما صُرف له (من صفحته)
create or replace function public.st_confirm_receipt(p_id uuid)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  d   public.st_docs;
  v_e uuid := public.st_my_employee();
begin
  if v_e is null then
    raise exception 'حسابك غير مربوط بسجل موظف نشط' using errcode = '42501';
  end if;
  if public.setting_bool('security.freeze', false) and not public.is_director() then
    raise exception 'المنظومة في وضع القراءة فقط' using errcode = '42501';
  end if;
  select * into d from public.st_docs where id = p_id for update;
  if not found or d.employee_id is distinct from v_e then
    raise exception 'المستند غير موجود' using errcode = 'P0002';
  end if;
  if d.kind <> 'issue' or d.status <> 'posted' or d.reverses_id is not null then
    raise exception 'يُؤكَّد استلام مستند الصرف المرحَّل وحده' using errcode = '22023';
  end if;
  if d.confirmed_at is not null then
    return;
  end if;
  update public.st_docs set confirmed_at = now(), confirmed_by = auth.uid() where id = p_id;
  perform public.write_audit('stores.receipt_confirm', null, null, jsonb_build_object('id', p_id, 'doc_no', d.doc_no), d.doc_no);
end;
$$;

-- ---------------------------------------------------------------------
-- 10. سياسات القراءة والصلاحيات والتحديث اللحظي
-- ---------------------------------------------------------------------
alter table public.st_settings enable row level security;
alter table public.st_departments enable row level security;
alter table public.st_employees enable row level security;
alter table public.st_locations enable row level security;
alter table public.st_warehouses enable row level security;
alter table public.st_categories enable row level security;
alter table public.st_units enable row level security;
alter table public.st_items enable row level security;
alter table public.st_item_units enable row level security;
alter table public.st_docs enable row level security;
alter table public.st_doc_lines enable row level security;
alter table public.st_stock enable row level security;
alter table public.st_batches enable row level security;
alter table public.st_moves enable row level security;
alter table public.st_counters enable row level security;

-- البيانات المرجعية: أهل القسم، والموظف المربوط بسجله (أسماء الأصناف والوحدات والمخازن فيما صُرف له)
drop policy if exists st_settings_read on public.st_settings;
create policy st_settings_read on public.st_settings for select to authenticated using ((select public.st_staff()));
drop policy if exists st_departments_read on public.st_departments;
create policy st_departments_read on public.st_departments for select to authenticated
  using ((select public.st_staff()) or (select public.st_my_employee()) is not null);
drop policy if exists st_locations_read on public.st_locations;
create policy st_locations_read on public.st_locations for select to authenticated using ((select public.st_staff()));
drop policy if exists st_warehouses_read on public.st_warehouses;
create policy st_warehouses_read on public.st_warehouses for select to authenticated
  using ((select public.st_staff()) or (select public.st_my_employee()) is not null);
drop policy if exists st_categories_read on public.st_categories;
create policy st_categories_read on public.st_categories for select to authenticated
  using ((select public.st_staff()) or (select public.st_my_employee()) is not null);
drop policy if exists st_units_read on public.st_units;
create policy st_units_read on public.st_units for select to authenticated
  using ((select public.st_staff()) or (select public.st_my_employee()) is not null);
drop policy if exists st_items_read on public.st_items;
create policy st_items_read on public.st_items for select to authenticated
  using ((select public.st_staff()) or (select public.st_my_employee()) is not null);
drop policy if exists st_item_units_read on public.st_item_units;
create policy st_item_units_read on public.st_item_units for select to authenticated
  using ((select public.st_staff()) or (select public.st_my_employee()) is not null);
-- الموظفون: أهل القسم، والموظف سجله وحده
drop policy if exists st_employees_read on public.st_employees;
create policy st_employees_read on public.st_employees for select to authenticated
  using ((select public.st_staff()) or profile_id = (select auth.uid()));
-- المستندات: من يرى القسم كله، وأمين المخزن مستندات مخزنه، والموظف ما صُرف له أو أرجعه بعد ترحيله
drop policy if exists st_docs_read on public.st_docs;
create policy st_docs_read on public.st_docs for select to authenticated
  using ((select public.st_sees_all())
         or warehouse_id = any ((select public.st_my_warehouses())::uuid[])
         or to_warehouse_id = any ((select public.st_my_warehouses())::uuid[])
         or (employee_id is not null and employee_id = (select public.st_my_employee())
             and status = 'posted' and kind in ('issue', 'return')));
drop policy if exists st_doc_lines_read on public.st_doc_lines;
create policy st_doc_lines_read on public.st_doc_lines for select to authenticated
  using (exists (select 1 from public.st_docs d where d.id = doc_id));
-- الأرصدة والدفعات والحركات: من يرى القسم كله، وأمين المخزن مخزنه
drop policy if exists st_stock_read on public.st_stock;
create policy st_stock_read on public.st_stock for select to authenticated
  using ((select public.st_sees_all()) or warehouse_id = any ((select public.st_my_warehouses())::uuid[]));
drop policy if exists st_batches_read on public.st_batches;
create policy st_batches_read on public.st_batches for select to authenticated
  using ((select public.st_sees_all()) or warehouse_id = any ((select public.st_my_warehouses())::uuid[]));
drop policy if exists st_moves_read on public.st_moves;
create policy st_moves_read on public.st_moves for select to authenticated
  using ((select public.st_sees_all()) or warehouse_id = any ((select public.st_my_warehouses())::uuid[]));

-- لا كتابة مباشرة: كل الكتابة عبر الدوال أعلاه
revoke all on public.st_settings, public.st_departments, public.st_employees, public.st_locations, public.st_warehouses,
  public.st_categories, public.st_units, public.st_items, public.st_item_units, public.st_docs, public.st_doc_lines,
  public.st_stock, public.st_batches, public.st_moves, public.st_counters from anon, authenticated;
grant select on public.st_settings, public.st_departments, public.st_employees, public.st_locations, public.st_warehouses,
  public.st_categories, public.st_units, public.st_items, public.st_item_units, public.st_docs, public.st_doc_lines,
  public.st_stock, public.st_batches, public.st_moves to authenticated;
grant all on public.st_settings, public.st_departments, public.st_employees, public.st_locations, public.st_warehouses,
  public.st_categories, public.st_units, public.st_items, public.st_item_units, public.st_docs, public.st_doc_lines,
  public.st_stock, public.st_batches, public.st_moves, public.st_counters to service_role;

-- الدوال المتاحة للتطبيق
revoke execute on function public.st_sees_all(), public.st_my_warehouses(), public.st_staff(), public.st_can_setup(),
  public.st_can_items(), public.st_can_approve(), public.st_can_move(uuid), public.st_my_employee(),
  public.st_save_department(uuid, jsonb), public.st_save_location(uuid, jsonb), public.st_save_warehouse(uuid, jsonb),
  public.st_save_category(uuid, jsonb), public.st_save_unit(uuid, jsonb), public.st_delete_setup(text, uuid),
  public.st_set_settings(jsonb), public.st_save_employee(uuid, jsonb), public.st_import_employees(jsonb),
  public.st_save_item(uuid, jsonb), public.st_import_items(jsonb), public.st_save_doc(uuid, jsonb),
  public.st_doc_action(uuid, text, text, boolean), public.st_delete_doc(uuid), public.st_reverse_doc(uuid, text),
  public.st_confirm_receipt(uuid) from public, anon;
grant execute on function public.st_sees_all(), public.st_my_warehouses(), public.st_staff(), public.st_can_setup(),
  public.st_can_items(), public.st_can_approve(), public.st_can_move(uuid), public.st_my_employee(),
  public.st_save_department(uuid, jsonb), public.st_save_location(uuid, jsonb), public.st_save_warehouse(uuid, jsonb),
  public.st_save_category(uuid, jsonb), public.st_save_unit(uuid, jsonb), public.st_delete_setup(text, uuid),
  public.st_set_settings(jsonb), public.st_save_employee(uuid, jsonb), public.st_import_employees(jsonb),
  public.st_save_item(uuid, jsonb), public.st_import_items(jsonb), public.st_save_doc(uuid, jsonb),
  public.st_doc_action(uuid, text, text, boolean), public.st_delete_doc(uuid), public.st_reverse_doc(uuid, text),
  public.st_confirm_receipt(uuid) to authenticated;
-- داخلية: لا تُستدعى من التطبيق
revoke execute on function public.st_setting_bool(text, boolean), public.st_next_no(text, text, integer, integer),
  public.st_text(jsonb, text, integer), public.st_num(jsonb, text, numeric), public.st_uuid(jsonb, text),
  public.st_doc_snapshot(uuid), public.st_fmt(numeric), public.st_doc_outgoing(uuid),
  public.st_reserve(uuid, integer, boolean), public.st_apply_in(uuid, uuid, uuid, uuid, numeric, date, text),
  public.st_apply_out(uuid, uuid, uuid, uuid, numeric, date, text), public.st_post(uuid)
  from public, anon, authenticated;

do $$
declare
  t text;
begin
  foreach t in array array['st_docs', 'st_stock', 'st_items', 'st_employees', 'st_warehouses', 'st_settings'] loop
    if exists (select 1 from pg_publication where pubname = 'supabase_realtime')
       and not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = t) then
      execute format('alter publication supabase_realtime add table public.%I', t);
    end if;
  end loop;
end $$;
