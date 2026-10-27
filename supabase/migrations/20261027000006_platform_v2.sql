-- =====================================================================
--  الإصدار الثاني للمنظومة:
--    1. الإعدادات الحيّة (تُعدَّل من داخل التطبيق وتسري فوراً على الجميع)
--    2. المراحل والنماذج والأقسام والحقول الإضافية قابلة للتعديل من لوحة التحكم
--    3. الأفكار وطلبات التطوير
--    4. الأمان: التحقق بخطوتين، الجلسات، سجل الدخول، تجميد المنظومة، إغلاق التسجيل
--    5. نسب الضمان من الإعدادات بدل القيم الثابتة
--  يُشغَّل مرة واحدة بعد الملفات السابقة، وإعادة تشغيله آمنة.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. الإعدادات الحيّة
-- ---------------------------------------------------------------------
create table if not exists public.app_settings (
  key        text primary key check (key ~ '^[a-z][a-z0-9_]*(\.[a-z0-9_]+)+$'),
  value      jsonb not null,
  updated_at timestamptz not null default now(),
  updated_by uuid references public.profiles (id) on delete set null
);

insert into public.app_settings (key, value) values
  ('brand.app_title',               '"منظومة متابعة الدورة المستندية"'),
  ('brand.org_name',                '"مكتب الشؤون الهندسية"'),
  ('brand.org_parent',              '"لجنة إعادة إعمار منطقة الصابري ووسط البلاد"'),
  ('brand.primary_color',           '"#8A6A1E"'),
  ('ui.announcement',               '{"text": "", "level": "info"}'),
  ('ui.status_labels',              '{"done": "مكتمل", "wip": "قيد الإجراء", "todo": "لم يتم", "na": "لا ينطبق"}'),
  ('ui.features',                   '{"analysis": true, "export": true, "quality_notes": true, "ideas_for_all": true}'),
  ('finance.guarantee_initial_rate', '0.05'),
  ('finance.guarantee_final_rate',   '0.02'),
  ('finance.currency',              '"د.ل"'),
  ('security.require_mfa_director', 'false'),
  ('security.require_mfa_all',      'false'),
  ('security.idle_minutes',         '30'),
  ('security.freeze',               'false'),
  ('security.signups_open',         'true')
on conflict (key) do nothing;

-- قراءة إعداد (داخلي)
create or replace function public.setting(p_key text)
returns jsonb
language sql stable security definer set search_path = public
as $$
  select value from public.app_settings where key = p_key
$$;

create or replace function public.setting_bool(p_key text, p_default boolean)
returns boolean
language sql stable security definer set search_path = public
as $$
  select coalesce((select case when jsonb_typeof(value) = 'boolean' then (value #>> '{}')::boolean end
                   from public.app_settings where key = p_key), p_default)
$$;

create or replace function public.setting_num(p_key text, p_default numeric)
returns numeric
language sql stable security definer set search_path = public
as $$
  select coalesce((select case when jsonb_typeof(value) = 'number' then (value #>> '{}')::numeric end
                   from public.app_settings where key = p_key), p_default)
$$;

-- ---------------------------------------------------------------------
-- 2. التحقق بخطوتين داخل قاعدة البيانات
--    من فعّل التحقق بخطوتين لا تُقبل جلسته إلا بعد إدخال الرمز (aal2).
--    ومن يُلزَم به (المدير أو الجميع حسب الإعداد) لا يرى شيئاً قبل تفعيله.
-- ---------------------------------------------------------------------
create or replace function public.mfa_enrolled(p_user uuid)
returns boolean
language plpgsql stable security definer set search_path = public, auth
as $$
begin
  if to_regclass('auth.mfa_factors') is null or p_user is null then
    return false;
  end if;
  return exists (select 1 from auth.mfa_factors f where f.user_id = p_user and f.status::text = 'verified');
end;
$$;

create or replace function public.mfa_ok()
returns boolean
language plpgsql stable security definer set search_path = public, auth
as $$
declare
  v_aal  text := coalesce(auth.jwt() ->> 'aal', 'aal1');
  v_role public.app_role;
begin
  if auth.uid() is null then
    return true;
  end if;
  if public.mfa_enrolled(auth.uid()) then
    return v_aal = 'aal2';
  end if;
  select role into v_role from public.profiles where id = auth.uid();
  if public.setting_bool('security.require_mfa_all', false) then
    return false;
  end if;
  if v_role = 'director' and public.setting_bool('security.require_mfa_director', false) then
    return false;
  end if;
  return true;
end;
$$;

create or replace function public.my_role()
returns public.app_role
language sql stable security definer set search_path = public
as $$
  select role from public.profiles where id = auth.uid() and active and public.mfa_ok()
$$;

create or replace function public.is_member()
returns boolean
language sql stable security definer set search_path = public
as $$
  select exists (select 1 from public.profiles where id = auth.uid() and active and role is not null)
     and public.mfa_ok()
$$;

create or replace function public.is_director()
returns boolean
language sql stable security definer set search_path = public
as $$
  select exists (select 1 from public.profiles where id = auth.uid() and active and role = 'director')
     and public.mfa_ok()
$$;

-- تجميد المنظومة: قراءة فقط للجميع عدا المدير
create or replace function public.writes_allowed()
returns boolean
language sql stable security definer set search_path = public
as $$
  select public.is_director() or (public.is_member() and not public.setting_bool('security.freeze', false))
$$;

-- ---------------------------------------------------------------------
-- 3. الاختصاص: دالة عامة لرموز الاختصاص تُستخدم للنماذج والحقول الإضافية
-- ---------------------------------------------------------------------
create or replace function public.has_token(p_project uuid, p_tokens text[])
returns boolean
language plpgsql stable security definer set search_path = public
as $$
declare
  me        public.profiles;
  proj_dept text;
begin
  if not public.mfa_ok() then return false; end if;
  select * into me from public.profiles where id = auth.uid() and active and role is not null;
  if not found then return false; end if;
  if me.role = 'director' then return true; end if;
  if public.setting_bool('security.freeze', false) then return false; end if;
  select department into proj_dept from public.projects where id = p_project;
  if not found then return false; end if;
  return case me.role
    when 'office_staff' then 'office_staff' = any (p_tokens)
    when 'contracts'    then 'contracts'    = any (p_tokens)
    when 'planning_qa'  then 'planning_qa'  = any (p_tokens)
    when 'dept_head'    then
         ('head:supervising' = any (p_tokens) and me.department = proj_dept)
      or ('head:technical'   = any (p_tokens) and me.department = 'technical')
      or ('head:acceptance'  = any (p_tokens) and me.department = 'acceptance')
    else false
  end;
end;
$$;

-- ---------------------------------------------------------------------
-- 4. المراحل والنماذج القابلة للتعديل
-- ---------------------------------------------------------------------
create table if not exists public.stages (
  idx  smallint primary key check (idx between 0 and 19),
  name text not null check (length(btrim(name)) between 2 and 60)
);
insert into public.stages (idx, name) values
  (0, 'التعاقد'), (1, 'تكليف المهندسين'), (2, 'بدء التنفيذ'), (3, 'المستخلصات'), (4, 'الاستلام والإقفال')
on conflict (idx) do nothing;

alter table public.form_defs add column if not exists active boolean not null default true;
alter table public.form_defs drop constraint if exists form_defs_stage_check;
do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'form_defs_stage_fk') then
    alter table public.form_defs add constraint form_defs_stage_fk foreign key (stage) references public.stages (idx);
  end if;
end $$;

create or replace function public.can_edit_form(p_project uuid, p_form text)
returns boolean
language plpgsql stable security definer set search_path = public
as $$
declare
  d public.form_defs;
begin
  select * into d from public.form_defs where key = p_form;
  if not found or not d.active then
    return public.is_director() and found;
  end if;
  return public.has_token(p_project, d.responsible);
end;
$$;

-- يُسمح بتغيير اسم النموذج ومرحلته وترتيبه من دوال لوحة التحكم فقط
create or replace function public.form_defs_guard()
returns trigger
language plpgsql
as $$
begin
  if current_setting('app.trusted', true) = 'on' then
    return new;
  end if;
  if new.key is distinct from old.key or new.name is distinct from old.name or new.stage is distinct from old.stage
     or new.sort is distinct from old.sort or new.engineer_field is distinct from old.engineer_field
     or new.active is distinct from old.active then
    raise exception 'يُعدَّل اسم النموذج ومرحلته وترتيبه من لوحة التحكم' using errcode = '42501';
  end if;
  return new;
end;
$$;

-- إعادة ترقيم ترتيب النماذج حسب المرحلة ثم الترتيب الحالي (داخلي)
create or replace function public.normalize_form_order()
returns void
language plpgsql security definer set search_path = public
as $$
begin
  perform set_config('app.trusted', 'on', true);
  update public.form_defs set sort = sort + 10000;
  update public.form_defs d set sort = r.rn
    from (select key, row_number() over (order by stage, sort) as rn from public.form_defs) r
   where d.key = r.key;
end;
$$;

create or replace function public.save_stage(p_idx smallint, p_name text)
returns smallint
language plpgsql security definer set search_path = public
as $$
declare
  v_idx smallint := p_idx;
  v_old text;
begin
  if not public.is_director() then
    raise exception 'تعديل المراحل من صلاحية مدير المكتب وحده' using errcode = '42501';
  end if;
  if length(btrim(coalesce(p_name, ''))) < 2 then
    raise exception 'اكتب اسم المرحلة' using errcode = '22023';
  end if;
  if v_idx is null then
    select coalesce(max(idx), -1) + 1 into v_idx from public.stages;
    if v_idx > 19 then
      raise exception 'الحد الأقصى عشرون مرحلة' using errcode = '22023';
    end if;
    insert into public.stages (idx, name) values (v_idx, btrim(p_name));
  else
    select name into v_old from public.stages where idx = v_idx;
    if not found then
      raise exception 'المرحلة غير موجودة' using errcode = '22023';
    end if;
    update public.stages set name = btrim(p_name) where idx = v_idx;
  end if;
  perform public.write_audit('config.stage', null, null,
    jsonb_build_object('idx', v_idx, 'from', v_old, 'to', btrim(p_name)), btrim(p_name));
  return v_idx;
end;
$$;

create or replace function public.delete_stage(p_idx smallint)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  v_name text;
begin
  if not public.is_director() then
    raise exception 'تعديل المراحل من صلاحية مدير المكتب وحده' using errcode = '42501';
  end if;
  if exists (select 1 from public.form_defs where stage = p_idx) then
    raise exception 'انقل نماذج هذه المرحلة أولاً' using errcode = 'P0001';
  end if;
  if p_idx <> (select max(idx) from public.stages) then
    raise exception 'تُحذف المرحلة الأخيرة فقط' using errcode = 'P0001';
  end if;
  delete from public.stages where idx = p_idx returning name into v_name;
  perform public.write_audit('config.stage_delete', null, null, jsonb_build_object('idx', p_idx), v_name);
end;
$$;

create or replace function public.save_form_def(
  p_key text, p_name text, p_stage smallint, p_sensitive boolean, p_responsible text[], p_active boolean)
returns text
language plpgsql security definer set search_path = public
as $$
declare
  v_key text := nullif(btrim(coalesce(p_key, '')), '');
  v_old public.form_defs;
  v_n   int;
begin
  if not public.is_director() then
    raise exception 'تعديل النماذج من صلاحية مدير المكتب وحده' using errcode = '42501';
  end if;
  if length(btrim(coalesce(p_name, ''))) < 2 then
    raise exception 'اكتب اسم النموذج' using errcode = '22023';
  end if;
  if not exists (select 1 from public.stages where idx = p_stage) then
    raise exception 'المرحلة غير موجودة' using errcode = '22023';
  end if;
  if exists (select 1 from public.form_defs where name = btrim(p_name) and key is distinct from v_key) then
    raise exception 'يوجد نموذج بهذا الاسم' using errcode = '23505';
  end if;
  perform set_config('app.trusted', 'on', true);
  if v_key is null then
    select coalesce(max(nullif(regexp_replace(key, '\D', '', 'g'), '')::int), 0) + 1 into v_n from public.form_defs;
    v_key := 'f' || lpad(v_n::text, 2, '0');
    insert into public.form_defs (key, name, stage, sort, sensitive, responsible, active)
    values (v_key, btrim(p_name), p_stage, 20000, coalesce(p_sensitive, false), coalesce(p_responsible, '{}'), coalesce(p_active, true));
  else
    select * into v_old from public.form_defs where key = v_key;
    if not found then
      raise exception 'النموذج غير موجود' using errcode = '22023';
    end if;
    update public.form_defs
       set name = btrim(p_name),
           stage = p_stage,
           sort = case when p_stage <> v_old.stage then 20000 else sort end,
           sensitive = coalesce(p_sensitive, sensitive),
           responsible = coalesce(p_responsible, responsible),
           active = coalesce(p_active, active)
     where key = v_key;
  end if;
  perform public.normalize_form_order();
  perform public.write_audit('config.form', null, v_key,
    jsonb_strip_nulls(jsonb_build_object('created', v_old.key is null,
      'name', jsonb_build_object('from', v_old.name, 'to', btrim(p_name)),
      'stage', jsonb_build_object('from', v_old.stage, 'to', p_stage),
      'active', jsonb_build_object('from', v_old.active, 'to', coalesce(p_active, true)))),
    btrim(p_name));
  return v_key;
end;
$$;

create or replace function public.reorder_forms(p_keys text[])
returns void
language plpgsql security definer set search_path = public
as $$
begin
  if not public.is_director() then
    raise exception 'ترتيب النماذج من صلاحية مدير المكتب وحده' using errcode = '42501';
  end if;
  perform set_config('app.trusted', 'on', true);
  update public.form_defs set sort = sort + 10000;
  update public.form_defs d set sort = k.ord
    from unnest(p_keys) with ordinality as k(key, ord)
   where d.key = k.key;
  perform public.normalize_form_order();
  perform public.write_audit('config.form_order', null, null, jsonb_build_object('order', to_jsonb(p_keys)), 'ترتيب النماذج');
end;
$$;

create or replace function public.delete_form_def(p_key text)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  v_name text;
begin
  if not public.is_director() then
    raise exception 'حذف النماذج من صلاحية مدير المكتب وحده' using errcode = '42501';
  end if;
  if exists (select 1 from public.project_forms where form_key = p_key)
     or exists (select 1 from public.change_requests where form_key = p_key) then
    raise exception 'لهذا النموذج حالات مسجّلة في المشاريع؛ أوقفه بدل حذفه' using errcode = 'P0001';
  end if;
  perform set_config('app.trusted', 'on', true);
  delete from public.form_defs where key = p_key returning name into v_name;
  if v_name is null then
    raise exception 'النموذج غير موجود' using errcode = '22023';
  end if;
  perform public.normalize_form_order();
  perform public.write_audit('config.form_delete', null, null, jsonb_build_object('key', p_key), v_name);
end;
$$;

-- الأقسام: تغيير الاسم وإضافة قسم
create or replace function public.save_department(p_key text, p_name text, p_can_supervise boolean)
returns text
language plpgsql security definer set search_path = public
as $$
declare
  v_key text := nullif(btrim(coalesce(p_key, '')), '');
  v_old text;
  v_n   int;
begin
  if not public.is_director() then
    raise exception 'تعديل الأقسام من صلاحية مدير المكتب وحده' using errcode = '42501';
  end if;
  if length(btrim(coalesce(p_name, ''))) < 2 then
    raise exception 'اكتب اسم القسم' using errcode = '22023';
  end if;
  if v_key is null then
    select count(*) + 1 into v_n from public.departments;
    v_key := 'dept' || v_n;
    while exists (select 1 from public.departments where key = v_key) loop
      v_n := v_n + 1; v_key := 'dept' || v_n;
    end loop;
    insert into public.departments (key, name, can_supervise, sort)
    values (v_key, btrim(p_name), coalesce(p_can_supervise, false), (select coalesce(max(sort), 0) + 1 from public.departments));
  else
    select name into v_old from public.departments where key = v_key;
    if not found then
      raise exception 'القسم غير موجود' using errcode = '22023';
    end if;
    update public.departments set name = btrim(p_name) where key = v_key;
  end if;
  perform public.write_audit('config.department', null, null,
    jsonb_build_object('key', v_key, 'from', v_old, 'to', btrim(p_name)), btrim(p_name));
  return v_key;
end;
$$;

-- عرض نسب الإنجاز: النماذج الفعّالة فقط، وأسماء المراحل من جدولها
create or replace view public.v_project_progress
with (security_invoker = true)
as
with cells as (
  select p.id as project_id, d.key, d.sort, d.stage, coalesce(pf.status, 'todo') as status
  from public.projects p
  cross join public.form_defs d
  left join public.project_forms pf on pf.project_id = p.id and pf.form_key = d.key
  where d.active
),
agg as (
  select project_id,
         count(*) filter (where status = 'done') as done,
         count(*) filter (where status = 'wip')  as wip,
         count(*) filter (where status = 'na')   as na,
         count(*) filter (where status <> 'na')  as required,
         (array_agg(key order by sort) filter (where status not in ('done', 'na')))[1] as next_form
  from cells group by project_id
)
select a.project_id, a.done, a.wip, a.na, a.required,
       case when a.required = 0 then 1.0 else round(a.done::numeric / a.required, 4) end as pct,
       a.next_form,
       nf.name as next_form_name,
       case when a.next_form is null then 'اكتملت الدورة' else st.name end as current_stage,
       case when a.next_form is null then 'مكتملة'
            when a.done + a.wip = 0 then 'لم تبدأ'
            else 'جارية' end as cycle_state
from agg a
left join public.form_defs nf on nf.key = a.next_form
left join public.stages st on st.idx = nf.stage;

-- ---------------------------------------------------------------------
-- 5. الحقول الإضافية للمشاريع (تُعرَّف من لوحة التحكم دون تعديل البرمجة)
-- ---------------------------------------------------------------------
create table if not exists public.custom_fields (
  key         text primary key check (key ~ '^c[0-9]+$'),
  label       text not null check (length(btrim(label)) between 2 and 80),
  kind        text not null check (kind in ('text', 'longtext', 'number', 'money', 'date', 'select', 'bool')),
  options     text[] not null default '{}',
  section     text not null default 'بيانات إضافية',
  sort        integer not null default 0,
  editable_by text[] not null default '{office_staff}',
  active      boolean not null default true,
  created_at  timestamptz not null default now(),
  constraint custom_fields_tokens check (
    editable_by <@ array['office_staff', 'contracts', 'planning_qa',
                         'head:supervising', 'head:technical', 'head:acceptance']::text[])
);
alter table public.projects add column if not exists extra jsonb not null default '{}'::jsonb;

create or replace function public.save_custom_field(
  p_key text, p_label text, p_kind text, p_options text[], p_section text, p_editable_by text[], p_active boolean)
returns text
language plpgsql security definer set search_path = public
as $$
declare
  v_key text := nullif(btrim(coalesce(p_key, '')), '');
  v_n   int;
begin
  if not public.is_director() then
    raise exception 'تعريف الحقول من صلاحية مدير المكتب وحده' using errcode = '42501';
  end if;
  if p_kind = 'select' and coalesce(array_length(p_options, 1), 0) < 2 then
    raise exception 'القائمة تحتاج خيارين على الأقل' using errcode = '22023';
  end if;
  if v_key is null then
    select coalesce(max(substring(key from 2)::int), 0) + 1 into v_n from public.custom_fields;
    v_key := 'c' || v_n;
    insert into public.custom_fields (key, label, kind, options, section, sort, editable_by, active)
    values (v_key, btrim(p_label), p_kind, coalesce(p_options, '{}'), coalesce(nullif(btrim(p_section), ''), 'بيانات إضافية'),
            (select coalesce(max(sort), 0) + 1 from public.custom_fields), coalesce(p_editable_by, '{office_staff}'),
            coalesce(p_active, true));
  else
    update public.custom_fields
       set label = btrim(p_label), kind = p_kind, options = coalesce(p_options, '{}'),
           section = coalesce(nullif(btrim(p_section), ''), section),
           editable_by = coalesce(p_editable_by, editable_by), active = coalesce(p_active, active)
     where key = v_key;
    if not found then
      raise exception 'الحقل غير موجود' using errcode = '22023';
    end if;
  end if;
  perform public.write_audit('config.field', null, null,
    jsonb_build_object('key', v_key, 'label', btrim(p_label), 'kind', p_kind, 'active', coalesce(p_active, true)), btrim(p_label));
  return v_key;
end;
$$;

create or replace function public.reorder_custom_fields(p_keys text[])
returns void
language plpgsql security definer set search_path = public
as $$
begin
  if not public.is_director() then
    raise exception 'ترتيب الحقول من صلاحية مدير المكتب وحده' using errcode = '42501';
  end if;
  update public.custom_fields c set sort = k.ord
    from unnest(p_keys) with ordinality as k(key, ord)
   where c.key = k.key;
end;
$$;

create or replace function public.set_project_field(p_project uuid, p_key text, p_value jsonb)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  f     public.custom_fields;
  v_old jsonb;
  v     jsonb := case when p_value is null or p_value = 'null'::jsonb then null else p_value end;
begin
  select * into f from public.custom_fields where key = p_key and active;
  if not found then
    raise exception 'الحقل غير موجود' using errcode = '22023';
  end if;
  if not public.has_token(p_project, f.editable_by) then
    raise exception 'تعديل «%» خارج اختصاصك', f.label using errcode = '42501';
  end if;
  if v is not null then
    if f.kind in ('number', 'money') and jsonb_typeof(v) <> 'number' then
      raise exception '«%» يقبل رقماً فقط', f.label using errcode = '22023';
    elsif f.kind in ('number', 'money') and (v #>> '{}')::numeric < 0 and f.kind = 'money' then
      raise exception '«%» لا يكون سالباً', f.label using errcode = '22023';
    elsif f.kind = 'bool' and jsonb_typeof(v) <> 'boolean' then
      raise exception '«%» يقبل نعم أو لا', f.label using errcode = '22023';
    elsif f.kind = 'date' and (jsonb_typeof(v) <> 'string' or (v #>> '{}') !~ '^\d{4}-\d{2}-\d{2}$') then
      raise exception '«%» يقبل تاريخاً', f.label using errcode = '22023';
    elsif f.kind = 'select' and (jsonb_typeof(v) <> 'string' or not ((v #>> '{}') = any (f.options))) then
      raise exception 'اختر قيمة من قائمة «%»', f.label using errcode = '22023';
    elsif f.kind in ('text', 'longtext') and (jsonb_typeof(v) <> 'string' or length(v #>> '{}') > 4000) then
      raise exception '«%» نص لا يتجاوز 4000 حرف', f.label using errcode = '22023';
    end if;
  end if;
  select extra -> p_key into v_old from public.projects where id = p_project;
  if v_old is not distinct from v then
    return;
  end if;
  perform set_config('app.trusted', 'on', true);
  update public.projects
     set extra = case when v is null then extra - p_key else jsonb_set(extra, array[p_key], v) end
   where id = p_project;
  perform set_config('app.trusted', 'off', true);
  perform public.write_audit('project.field', p_project, null,
    jsonb_build_object('key', p_key, 'label', f.label, 'from', v_old, 'to', v));
end;
$$;

-- ---------------------------------------------------------------------
-- 6. نسب الضمان من الإعدادات، وحماية الحقول المحسوبة والإضافية
-- ---------------------------------------------------------------------
do $$
begin
  if exists (select 1 from information_schema.columns
             where table_schema = 'public' and table_name = 'projects' and column_name = 'guarantee_initial'
               and is_generated = 'ALWAYS') then
    alter table public.projects drop column guarantee_initial;
    alter table public.projects drop column guarantee_final;
  end if;
end $$;
alter table public.projects
  add column if not exists guarantee_initial numeric(16, 3),
  add column if not exists guarantee_final   numeric(16, 3);

create or replace function public.projects_finance_calc()
returns trigger
language plpgsql security definer set search_path = public
as $$
begin
  new.guarantee_initial := round(new.contract_value * public.setting_num('finance.guarantee_initial_rate', 0.05), 3);
  new.guarantee_final   := round(new.contract_value * public.setting_num('finance.guarantee_final_rate', 0.02), 3);
  if tg_op = 'UPDATE' and new.extra is distinct from old.extra
     and current_setting('app.trusted', true) is distinct from 'on'
     and auth.uid() is not null and not public.is_director() then
    raise exception 'تُعدَّل الحقول الإضافية من صفحة المشروع' using errcode = '42501';
  end if;
  return new;
end;
$$;
drop trigger if exists projects_finance_calc on public.projects;
create trigger projects_finance_calc
  before insert or update on public.projects
  for each row execute function public.projects_finance_calc();

-- إعادة حساب الضمانات دون تغيير «آخر تحديث» للمشاريع (عند تغيير النسب)
create or replace function public.projects_stamp()
returns trigger
language plpgsql security definer set search_path = public
as $$
begin
  new.assign_no := nullif(btrim(coalesce(new.assign_no, '')), '');
  if tg_op = 'UPDATE' and current_setting('app.recalc', true) = 'on' then
    new.updated_at := old.updated_at;
    new.updated_by := old.updated_by;
    return new;
  end if;
  if tg_op = 'INSERT' then
    new.created_by := coalesce(auth.uid(), new.created_by);
    new.updated_by := coalesce(auth.uid(), new.updated_by);
    new.created_at := coalesce(new.created_at, now());
    if coalesce(new.sort_order, 0) = 0 then
      select coalesce(max(sort_order), 0) + 1 into new.sort_order from public.projects;
    end if;
  else
    new.created_by := old.created_by;
    new.created_at := old.created_at;
    new.updated_by := coalesce(auth.uid(), new.updated_by);
  end if;
  new.updated_at := now();
  if not exists (select 1 from public.departments where key = new.department and can_supervise) then
    raise exception 'القسم المشرف يجب أن يكون قسماً يمكن إسناد الإشراف إليه' using errcode = '23514';
  end if;
  return new;
end;
$$;

do $$
begin
  perform set_config('app.recalc', 'on', true);
  update public.projects set contract_value = contract_value where contract_value is not null and guarantee_initial is null;
  perform set_config('app.recalc', 'off', true);
end $$;

-- ---------------------------------------------------------------------
-- 7. تعديل الإعدادات (المدير وحده) مع التحقق من القيم
-- ---------------------------------------------------------------------
create or replace function public.set_setting(p_key text, p_value jsonb)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  v_old jsonb;
  t     text := jsonb_typeof(p_value);
  ok    boolean;
begin
  if not public.is_director() then
    raise exception 'الإعدادات من صلاحية مدير المكتب وحده' using errcode = '42501';
  end if;
  ok := case
    when p_key in ('brand.app_title', 'brand.org_name', 'brand.org_parent') then
      t = 'string' and length(btrim(p_value #>> '{}')) between 2 and 120
    when p_key = 'brand.primary_color' then
      t = 'string' and (p_value #>> '{}') ~ '^#[0-9A-Fa-f]{6}$'
    when p_key = 'finance.currency' then
      t = 'string' and length(btrim(p_value #>> '{}')) between 1 and 12
    when p_key in ('finance.guarantee_initial_rate', 'finance.guarantee_final_rate') then
      t = 'number' and (p_value #>> '{}')::numeric between 0 and 0.5
    when p_key = 'security.idle_minutes' then
      t = 'number' and (p_value #>> '{}')::numeric between 0 and 480
    when p_key in ('security.require_mfa_director', 'security.require_mfa_all', 'security.freeze', 'security.signups_open') then
      t = 'boolean'
    when p_key = 'ui.announcement' then
      t = 'object' and jsonb_typeof(p_value -> 'text') = 'string' and length(p_value ->> 'text') <= 500
      and coalesce(p_value ->> 'level', 'info') in ('info', 'warning', 'critical')
    when p_key = 'ui.status_labels' then
      t = 'object' and (select bool_and(jsonb_typeof(p_value -> k) = 'string' and length(btrim(p_value ->> k)) between 2 and 30)
                          from unnest(array['done', 'wip', 'todo', 'na']) k)
    when p_key = 'ui.features' then
      t = 'object' and (select bool_and(jsonb_typeof(v) = 'boolean') from jsonb_each(p_value) e(k, v))
    else false
  end;
  if not coalesce(ok, false) then
    raise exception 'قيمة غير صالحة للإعداد %', p_key using errcode = '22023';
  end if;
  -- لا يُفرض التحقق بخطوتين قبل أن يفعّله المدير لنفسه، حتى لا يُغلق الباب عليه
  if p_key in ('security.require_mfa_director', 'security.require_mfa_all') and p_value = 'true'::jsonb
     and not public.mfa_enrolled(auth.uid()) then
    raise exception 'فعّل التحقق بخطوتين لحسابك أولاً' using errcode = 'P0001';
  end if;

  select value into v_old from public.app_settings where key = p_key;
  if v_old is not distinct from p_value then
    return;
  end if;
  insert into public.app_settings (key, value, updated_at, updated_by)
  values (p_key, p_value, now(), auth.uid())
  on conflict (key) do update set value = excluded.value, updated_at = excluded.updated_at, updated_by = excluded.updated_by;

  if p_key in ('finance.guarantee_initial_rate', 'finance.guarantee_final_rate') then
    perform set_config('app.recalc', 'on', true);
    update public.projects set contract_value = contract_value where contract_value is not null;
    perform set_config('app.recalc', 'off', true);
  end if;

  perform public.write_audit(case when p_key like 'security.%' then 'security.setting' else 'setting.update' end,
    null, null, jsonb_build_object('key', p_key, 'from', v_old, 'to', p_value), p_key);
end;
$$;

-- إعدادات الهوية والإعلان للشاشة قبل تسجيل الدخول
create or replace function public.public_settings()
returns jsonb
language sql stable security definer set search_path = public
as $$
  select coalesce(jsonb_object_agg(key, value), '{}'::jsonb)
  from public.app_settings
  where key like 'brand.%' or key in ('security.signups_open', 'security.idle_minutes',
                                       'security.require_mfa_all', 'security.require_mfa_director')
$$;

-- نسخة كاملة من الإعدادات والتعريفات (للتصدير والمزامنة)
create or replace function public.export_config()
returns jsonb
language plpgsql stable security definer set search_path = public
as $$
begin
  if not public.is_director() and auth.uid() is not null then
    raise exception 'التصدير من صلاحية مدير المكتب وحده' using errcode = '42501';
  end if;
  return jsonb_build_object(
    'exported_at', now(),
    'settings', (select coalesce(jsonb_object_agg(key, value order by key), '{}'::jsonb) from public.app_settings),
    'stages', (select coalesce(jsonb_agg(to_jsonb(s) order by idx), '[]'::jsonb) from public.stages s),
    'departments', (select coalesce(jsonb_agg(to_jsonb(d) order by sort), '[]'::jsonb) from public.departments d),
    'forms', (select coalesce(jsonb_agg(to_jsonb(f) order by sort), '[]'::jsonb) from public.form_defs f),
    'custom_fields', (select coalesce(jsonb_agg(to_jsonb(c) order by sort), '[]'::jsonb) from public.custom_fields c));
end;
$$;

-- استعادة الإعدادات من نسخة (الإعدادات فقط؛ تمر كل قيمة بالتحقق نفسه)
create or replace function public.import_settings(p_settings jsonb)
returns integer
language plpgsql security definer set search_path = public
as $$
declare
  k text;
  v jsonb;
  n integer := 0;
begin
  if not public.is_director() then
    raise exception 'الاستعادة من صلاحية مدير المكتب وحده' using errcode = '42501';
  end if;
  for k, v in select key, value from jsonb_each(coalesce(p_settings, '{}'::jsonb)) loop
    if k like 'security.require_mfa%' then
      continue;  -- لا تُستعاد إعدادات التحقق بخطوتين من ملف
    end if;
    perform public.set_setting(k, v);
    n := n + 1;
  end loop;
  return n;
end;
$$;

-- ---------------------------------------------------------------------
-- 8. الأفكار وطلبات التطوير
-- ---------------------------------------------------------------------
create table if not exists public.ideas (
  id           uuid primary key default gen_random_uuid(),
  title        text not null check (length(btrim(title)) between 3 and 200),
  body         text not null default '' check (length(body) <= 8000),
  category     text not null default 'feature' check (category in ('feature', 'design', 'data', 'security', 'bug', 'other')),
  priority     text not null default 'normal' check (priority in ('low', 'normal', 'high', 'urgent')),
  status       text not null default 'new' check (status in ('new', 'planned', 'in_progress', 'done', 'rejected')),
  response     text not null default '',
  created_by   uuid references public.profiles (id) on delete set null,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  github_issue integer,
  github_url   text
);
create index if not exists ideas_created_idx on public.ideas (created_at desc);

create or replace function public.submit_idea(p_title text, p_body text, p_category text, p_priority text)
returns uuid
language plpgsql security definer set search_path = public
as $$
declare
  v_id uuid;
begin
  if not public.is_member() then
    raise exception 'حسابك غير مفعّل' using errcode = '42501';
  end if;
  if not public.is_director() and not coalesce((public.setting('ui.features') ->> 'ideas_for_all')::boolean, true) then
    raise exception 'إرسال الأفكار متاح لمدير المكتب حالياً' using errcode = '42501';
  end if;
  insert into public.ideas (title, body, category, priority, created_by)
  values (btrim(p_title), coalesce(p_body, ''), coalesce(p_category, 'feature'), coalesce(p_priority, 'normal'), auth.uid())
  returning id into v_id;
  perform public.write_audit('idea.create', null, null, jsonb_build_object('idea_id', v_id, 'title', btrim(p_title)), btrim(p_title));
  if not public.is_director() then
    perform public.notify_director('idea', 'فكرة جديدة: ' || btrim(p_title), public.actor_name(auth.uid()));
  end if;
  return v_id;
end;
$$;

create or replace function public.update_idea(p_id uuid, p_status text, p_priority text, p_response text)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  i public.ideas;
begin
  if not public.is_director() then
    raise exception 'إدارة الأفكار من صلاحية مدير المكتب وحده' using errcode = '42501';
  end if;
  select * into i from public.ideas where id = p_id for update;
  if not found then
    raise exception 'الفكرة غير موجودة' using errcode = '22023';
  end if;
  update public.ideas
     set status = coalesce(p_status, status), priority = coalesce(p_priority, priority),
         response = coalesce(p_response, response), updated_at = now()
   where id = p_id;
  perform public.write_audit('idea.update', null, null,
    jsonb_build_object('idea_id', p_id, 'status', jsonb_build_object('from', i.status, 'to', coalesce(p_status, i.status))), i.title);
  if coalesce(p_status, i.status) <> i.status and i.created_by is not null and i.created_by <> auth.uid() then
    perform public.notify_user(i.created_by, 'idea', 'تحديث على فكرتك: ' || i.title, coalesce(p_response, ''));
  end if;
end;
$$;

create or replace function public.delete_idea(p_id uuid)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  v_title text;
begin
  if not public.is_director() then
    raise exception 'حذف الأفكار من صلاحية مدير المكتب وحده' using errcode = '42501';
  end if;
  delete from public.ideas where id = p_id returning title into v_title;
  perform public.write_audit('idea.delete', null, null, jsonb_build_object('idea_id', p_id), coalesce(v_title, ''));
end;
$$;

-- ---------------------------------------------------------------------
-- 9. مركز الأمان (المدير وحده)
-- ---------------------------------------------------------------------
create or replace function public.security_overview()
returns jsonb
language plpgsql stable security definer set search_path = public, auth
as $$
declare
  v_sessions integer := null;
  v_logins   integer := null;
begin
  if not public.is_director() then
    raise exception 'مركز الأمان لمدير المكتب وحده' using errcode = '42501';
  end if;
  if to_regclass('auth.sessions') is not null then
    execute 'select count(*) from auth.sessions where coalesce(not_after, ''infinity'') > now()' into v_sessions;
  end if;
  if to_regclass('auth.audit_log_entries') is not null then
    execute $q$select count(*) from auth.audit_log_entries
               where created_at > now() - interval '7 days' and payload ->> 'action' = 'login'$q$ into v_logins;
  end if;
  return jsonb_build_object(
    'director_mfa', public.mfa_enrolled(auth.uid()),
    'current_aal', coalesce(auth.jwt() ->> 'aal', 'aal1'),
    'users_total', (select count(*) from public.profiles),
    'users_active', (select count(*) from public.profiles where active),
    'users_pending', (select count(*) from public.profiles where not active and role is null),
    'users_disabled', (select count(*) from public.profiles where not active and role is not null),
    'users_mfa', (select count(*) from public.profiles p where p.active and public.mfa_enrolled(p.id)),
    'sessions_active', v_sessions,
    'logins_7d', v_logins,
    'tables_without_rls', (select coalesce(jsonb_agg(c.relname order by c.relname), '[]'::jsonb)
                             from pg_class c join pg_namespace n on n.oid = c.relnamespace
                            where n.nspname = 'public' and c.relkind = 'r' and not c.relrowsecurity),
    'pending_requests', (select count(*) from public.change_requests where state = 'pending'),
    'security_events_7d', (select count(*) from public.audit_log
                            where at > now() - interval '7 days'
                              and (action like 'security.%' or action like 'user.%')));
end;
$$;

-- المستخدمون وحالة التحقق بخطوتين وآخر دخول
create or replace function public.security_users()
returns table (id uuid, full_name text, email text, role public.app_role, active boolean,
               mfa boolean, last_sign_in_at timestamptz, created_at timestamptz)
language plpgsql stable security definer set search_path = public, auth
as $$
begin
  if not public.is_director() then
    raise exception 'مركز الأمان لمدير المكتب وحده' using errcode = '42501';
  end if;
  return query
    select p.id, p.full_name, p.email, p.role, p.active, public.mfa_enrolled(p.id),
           (to_jsonb(u) ->> 'last_sign_in_at')::timestamptz, p.created_at
      from public.profiles p left join auth.users u on u.id = p.id
     order by p.active desc, p.created_at;
end;
$$;

-- الجلسات المفتوحة (الأجهزة المتصلة)
create or replace function public.list_sessions()
returns setof jsonb
language plpgsql stable security definer set search_path = public, auth
as $$
begin
  if not public.is_director() then
    raise exception 'مركز الأمان لمدير المكتب وحده' using errcode = '42501';
  end if;
  if to_regclass('auth.sessions') is null then
    return;
  end if;
  return query execute $q$
    select jsonb_build_object(
             'id', s.id, 'user_id', s.user_id, 'name', public.actor_name(s.user_id),
             'created_at', s.created_at, 'updated_at', coalesce(to_jsonb(s) ->> 'refreshed_at', to_jsonb(s) ->> 'updated_at'),
             'user_agent', to_jsonb(s) ->> 'user_agent', 'ip', to_jsonb(s) ->> 'ip', 'aal', to_jsonb(s) ->> 'aal',
             'current', s.id::text = coalesce(auth.jwt() ->> 'session_id', ''))
      from auth.sessions s
     where coalesce(s.not_after, 'infinity') > now()
     order by coalesce(to_jsonb(s) ->> 'refreshed_at', to_jsonb(s) ->> 'updated_at', s.created_at::text) desc
     limit 300$q$;
end;
$$;

create or replace function public.revoke_session(p_session uuid)
returns void
language plpgsql security definer set search_path = public, auth
as $$
declare
  v_user uuid;
begin
  if not public.is_director() then
    raise exception 'إنهاء الجلسات من صلاحية مدير المكتب وحده' using errcode = '42501';
  end if;
  execute 'delete from auth.sessions where id = $1 returning user_id' into v_user using p_session;
  perform public.write_audit('security.session_revoke', null, null,
    jsonb_build_object('session_id', p_session, 'user_id', v_user), public.actor_name(v_user));
end;
$$;

-- إخراج مستخدم من كل أجهزته فوراً
create or replace function public.revoke_user_sessions(p_user uuid)
returns integer
language plpgsql security definer set search_path = public, auth
as $$
declare
  n integer;
begin
  if not public.is_director() then
    raise exception 'إنهاء الجلسات من صلاحية مدير المكتب وحده' using errcode = '42501';
  end if;
  if p_user = auth.uid() then
    raise exception 'لإنهاء جلساتك الأخرى استخدم «تسجيل الخروج من الأجهزة الأخرى»' using errcode = 'P0001';
  end if;
  execute 'with d as (delete from auth.sessions where user_id = $1 returning 1) select count(*) from d' into n using p_user;
  perform public.write_audit('security.user_signout', null, null,
    jsonb_build_object('user_id', p_user, 'sessions', n), public.actor_name(p_user));
  return n;
end;
$$;

-- إلغاء التحقق بخطوتين لمستخدم فقد هاتفه (لا يُستخدم لحساب المدير نفسه)
create or replace function public.reset_user_mfa(p_user uuid)
returns integer
language plpgsql security definer set search_path = public, auth
as $$
declare
  n integer := 0;
begin
  if not public.is_director() then
    raise exception 'من صلاحية مدير المكتب وحده' using errcode = '42501';
  end if;
  if p_user = auth.uid() then
    raise exception 'لا يُلغى التحقق بخطوتين لحساب المدير من التطبيق' using errcode = '42501';
  end if;
  if to_regclass('auth.mfa_factors') is not null then
    execute 'with d as (delete from auth.mfa_factors where user_id = $1 returning 1) select count(*) from d' into n using p_user;
  end if;
  perform public.write_audit('security.mfa_reset', null, null, jsonb_build_object('user_id', p_user, 'factors', n),
                             public.actor_name(p_user));
  perform public.notify_user(p_user, 'security', 'أُلغي التحقق بخطوتين لحسابك', 'فعّله من جديد من إعدادات حسابك');
  return n;
end;
$$;

-- سجل الدخول من سجلات المصادقة
create or replace function public.login_history(p_limit integer default 200)
returns setof jsonb
language plpgsql stable security definer set search_path = public, auth
as $$
begin
  if not public.is_director() then
    raise exception 'مركز الأمان لمدير المكتب وحده' using errcode = '42501';
  end if;
  if to_regclass('auth.audit_log_entries') is null then
    return;
  end if;
  return query execute $q$
    select jsonb_build_object(
             'at', e.created_at, 'action', e.payload ->> 'action',
             'actor_id', e.payload ->> 'actor_id',
             'name', case when (e.payload ->> 'actor_id') ~ '^[0-9a-f-]{36}$'
                          then public.actor_name((e.payload ->> 'actor_id')::uuid) end,
             'email', e.payload ->> 'actor_username', 'ip', to_jsonb(e) ->> 'ip_address')
      from auth.audit_log_entries e
     where e.payload ->> 'action' in ('login', 'logout', 'user_signedup', 'user_recovery_requested',
                                      'user_updated_password', 'factor_in_progress', 'factor_unenrolled',
                                      'mfa_code_login', 'token_revoked', 'user_deleted')
     order by e.created_at desc
     limit least(greatest(coalesce($1, 200), 1), 1000)$q$ using p_limit;
end;
$$;

-- إغلاق التسجيل الجديد يُطبَّق عند إنشاء الحساب
create or replace function public.handle_new_user()
returns trigger
language plpgsql security definer set search_path = public
as $$
begin
  if not public.setting_bool('security.signups_open', true) then
    raise exception 'التسجيل في المنظومة مغلق حالياً بقرار مدير المكتب' using errcode = '42501';
  end if;
  insert into public.profiles (id, email, full_name)
  values (new.id, new.email, coalesce(nullif(btrim(new.raw_user_meta_data ->> 'full_name'), ''), ''))
  on conflict (id) do nothing;
  perform public.notify_director('signup', 'طلب انضمام جديد',
    coalesce(nullif(btrim(new.raw_user_meta_data ->> 'full_name'), ''), new.email) || ' بانتظار التفعيل');
  return new;
end;
$$;

create or replace function public.withdraw_request(p_request uuid)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  r public.change_requests;
begin
  if not public.is_member() then
    raise exception 'حسابك غير مفعّل' using errcode = '42501';
  end if;
  select * into r from public.change_requests where id = p_request for update;
  if not found or r.requested_by is distinct from auth.uid() then
    raise exception 'لا يمكنك سحب هذا الطلب' using errcode = '42501';
  end if;
  if r.state <> 'pending' then
    raise exception 'لا يُسحب إلا الطلب المعلّق' using errcode = 'P0001';
  end if;
  update public.change_requests set state = 'withdrawn', decided_at = now() where id = p_request;
  perform public.write_audit('request.withdraw', r.project_id, r.form_key, jsonb_build_object('request_id', r.id));
end;
$$;

-- ---------------------------------------------------------------------
-- 10. سياسات الوصول
-- ---------------------------------------------------------------------
alter table public.app_settings  enable row level security;
alter table public.stages        enable row level security;
alter table public.custom_fields enable row level security;
alter table public.ideas         enable row level security;

drop policy if exists app_settings_read on public.app_settings;
create policy app_settings_read on public.app_settings for select to authenticated using (public.is_member());
drop policy if exists stages_read on public.stages;
create policy stages_read on public.stages for select to authenticated using (true);
drop policy if exists custom_fields_read on public.custom_fields;
create policy custom_fields_read on public.custom_fields for select to authenticated using (public.is_member());
drop policy if exists ideas_read on public.ideas;
create policy ideas_read on public.ideas for select to authenticated using (public.is_member());

-- تجميد المنظومة يوقف تعديل المشاريع وإضافة الملاحظات لغير المدير
drop policy if exists projects_insert on public.projects;
create policy projects_insert on public.projects for insert to authenticated
  with check (public.my_role() in ('director', 'office_staff') and public.writes_allowed());
drop policy if exists projects_update on public.projects;
create policy projects_update on public.projects for update to authenticated
  using (public.my_role() in ('director', 'office_staff') and public.writes_allowed())
  with check (public.my_role() in ('director', 'office_staff') and public.writes_allowed());
drop policy if exists quality_notes_insert on public.quality_notes;
create policy quality_notes_insert on public.quality_notes for insert to authenticated
  with check (public.my_role() in ('director', 'planning_qa') and public.writes_allowed());

revoke all on public.app_settings, public.stages, public.custom_fields, public.ideas from anon;
revoke insert, update, delete, truncate on public.app_settings, public.stages, public.custom_fields, public.ideas from authenticated;
grant select on public.app_settings, public.stages, public.custom_fields, public.ideas to authenticated;
grant all on public.app_settings, public.stages, public.custom_fields, public.ideas to service_role;
-- الأعمدة التي تُكتب مباشرة من التطبيق فقط؛ الحقول الإضافية والضمانات والأختام لا تُكتب مباشرة
revoke insert, update on public.projects from authenticated;
grant insert (assign_no, code, name, owner, company, department, notes, eng_sup, eng_qty, eng_fol, eng_saf, sort_order)
  on public.projects to authenticated;
grant update (assign_no, code, name, owner, company, department, notes, eng_sup, eng_qty, eng_fol, eng_saf, sort_order,
              contract_value, payment_first, payment_second, payment_final, deductions)
  on public.projects to authenticated;

-- الدوال
revoke execute on function
  public.setting(text), public.setting_bool(text, boolean), public.setting_num(text, numeric),
  public.mfa_enrolled(uuid), public.normalize_form_order(), public.projects_finance_calc(),
  public.projects_stamp(), public.handle_new_user(), public.form_defs_guard()
from public, anon, authenticated;

revoke execute on function
  public.mfa_ok(), public.writes_allowed(), public.has_token(uuid, text[]),
  public.save_stage(smallint, text), public.delete_stage(smallint),
  public.save_form_def(text, text, smallint, boolean, text[], boolean), public.reorder_forms(text[]),
  public.delete_form_def(text), public.save_department(text, text, boolean),
  public.save_custom_field(text, text, text, text[], text, text[], boolean), public.reorder_custom_fields(text[]),
  public.set_project_field(uuid, text, jsonb), public.set_setting(text, jsonb), public.export_config(),
  public.import_settings(jsonb), public.submit_idea(text, text, text, text), public.update_idea(uuid, text, text, text),
  public.delete_idea(uuid), public.security_overview(), public.security_users(), public.list_sessions(),
  public.revoke_session(uuid), public.revoke_user_sessions(uuid), public.reset_user_mfa(uuid), public.login_history(integer),
  public.public_settings(), public.withdraw_request(uuid)
from public, anon;

grant execute on function
  public.mfa_ok(), public.writes_allowed(), public.has_token(uuid, text[]),
  public.save_stage(smallint, text), public.delete_stage(smallint),
  public.save_form_def(text, text, smallint, boolean, text[], boolean), public.reorder_forms(text[]),
  public.delete_form_def(text), public.save_department(text, text, boolean),
  public.save_custom_field(text, text, text, text[], text, text[], boolean), public.reorder_custom_fields(text[]),
  public.set_project_field(uuid, text, jsonb), public.set_setting(text, jsonb), public.export_config(),
  public.import_settings(jsonb), public.submit_idea(text, text, text, text), public.update_idea(uuid, text, text, text),
  public.delete_idea(uuid), public.security_overview(), public.security_users(), public.list_sessions(),
  public.revoke_session(uuid), public.revoke_user_sessions(uuid), public.reset_user_mfa(uuid), public.login_history(integer),
  public.withdraw_request(uuid)
to authenticated;
grant execute on function public.public_settings() to anon, authenticated;
grant execute on function public.export_config() to service_role;

-- التحديث اللحظي للجداول الجديدة
do $$
declare
  t text;
begin
  foreach t in array array['app_settings', 'stages', 'custom_fields', 'ideas', 'departments'] loop
    if not exists (select 1 from pg_publication_tables
                   where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = t) then
      execute format('alter publication supabase_realtime add table public.%I', t);
    end if;
  end loop;
end $$;

notify pgrst, 'reload schema';

select 'تم: الإصدار الثاني (الإعدادات الحية، لوحة التحكم، الأفكار، مركز الأمان)' as result;
