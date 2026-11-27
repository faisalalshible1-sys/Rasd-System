-- =====================================================================
-- الإصدار 1.14.0 (الترحيل 45): معالم المشاريع ومؤشرات الأداء
--
--  pm_milestones: معالم كل مشروع (تاريخ مخطط، متوقع، فعلي، حالة). تُقرأ بقراءة متابعة المشروع نفسها (pm_row_ok)
--                 وتُكتب بدوال تتحقق من can_edit_pm وpm_row_ok.
--  kpi_defs / kpi_values: مؤشرات مخصصة يحددها المدير (اسم، وحدة، مستهدف، اتجاه الأفضل) وقيم شهرية لكل مؤشر.
--                 التعريف للمدير وحده، والقيم للمدير وموظفي مكتبه.
--  لا كتابة مباشرة على أي جدول؛ كل دالة تسجّل في سجل التدقيق.
--  يُشغَّل بعد 20261205000044_geo_points.sql، وإعادة تشغيله آمنة. التراجع: supabase/rollbacks/20261206000045_milestones_kpi_down.sql
-- =====================================================================
create table if not exists public.pm_milestones (
  id            uuid primary key default gen_random_uuid(),
  project_id    uuid not null references public.projects (id) on delete cascade,
  title         text not null check (length(btrim(title)) between 1 and 120),
  planned_date  date not null,
  forecast_date date,
  actual_date   date,
  status        text not null default 'pending' check (status in ('pending', 'done', 'cancelled')),
  note          text not null default '' check (length(note) <= 300),
  sort_order    integer not null default 0,
  created_at    timestamptz not null default now(),
  created_by    uuid references public.profiles (id) on delete set null,
  updated_at    timestamptz not null default now(),
  updated_by    uuid references public.profiles (id) on delete set null,
  check ((status = 'done') = (actual_date is not null))
);
create index if not exists pm_milestones_project_idx on public.pm_milestones (project_id, planned_date);
create index if not exists pm_milestones_created_by_idx on public.pm_milestones (created_by);
create index if not exists pm_milestones_updated_by_idx on public.pm_milestones (updated_by);

create table if not exists public.kpi_defs (
  id         uuid primary key default gen_random_uuid(),
  name       text not null check (length(btrim(name)) between 1 and 80),
  unit       text not null default '' check (length(unit) <= 20),
  target     numeric not null,
  direction  text not null default 'higher' check (direction in ('higher', 'lower')),
  active     boolean not null default true,
  note       text not null default '' check (length(note) <= 300),
  created_at timestamptz not null default now(),
  created_by uuid references public.profiles (id) on delete set null,
  updated_at timestamptz not null default now(),
  updated_by uuid references public.profiles (id) on delete set null
);
create unique index if not exists kpi_defs_name_uidx on public.kpi_defs (lower(btrim(name)));
create index if not exists kpi_defs_created_by_idx on public.kpi_defs (created_by);
create index if not exists kpi_defs_updated_by_idx on public.kpi_defs (updated_by);

create table if not exists public.kpi_values (
  id         uuid primary key default gen_random_uuid(),
  kpi_id     uuid not null references public.kpi_defs (id) on delete cascade,
  period     text not null check (period ~ '^[0-9]{4}-(0[1-9]|1[0-2])$'),
  value      numeric not null,
  note       text not null default '' check (length(note) <= 300),
  updated_at timestamptz not null default now(),
  updated_by uuid references public.profiles (id) on delete set null,
  unique (kpi_id, period)
);
create index if not exists kpi_values_updated_by_idx on public.kpi_values (updated_by);

alter table public.pm_milestones enable row level security;
alter table public.kpi_defs enable row level security;
alter table public.kpi_values enable row level security;
drop policy if exists pm_milestones_read on public.pm_milestones;
create policy pm_milestones_read on public.pm_milestones for select to authenticated
  using ((select public.project_full_all()) or project_id = any ((select public.my_supervised())::uuid[]));
drop policy if exists kpi_defs_read on public.kpi_defs;
create policy kpi_defs_read on public.kpi_defs for select to authenticated using ((select public.full_view()));
drop policy if exists kpi_values_read on public.kpi_values;
create policy kpi_values_read on public.kpi_values for select to authenticated using ((select public.full_view()));

revoke all on public.pm_milestones, public.kpi_defs, public.kpi_values from anon;
revoke insert, update, delete, truncate on public.pm_milestones, public.kpi_defs, public.kpi_values from authenticated;
grant select on public.pm_milestones, public.kpi_defs, public.kpi_values to authenticated;
grant all on public.pm_milestones, public.kpi_defs, public.kpi_values to service_role;

-- ---------------------------------------------------------------------
-- المعالم
-- ---------------------------------------------------------------------
create or replace function public.pm_milestone_save(
  p_id uuid, p_project uuid, p_title text, p_planned date, p_forecast date default null,
  p_note text default '', p_sort integer default 0)
returns uuid
language plpgsql security definer set search_path = public
as $$
declare
  v_id uuid := p_id;
  v_proj uuid := p_project;
  v_title text := btrim(coalesce(p_title, ''));
  v_label text;
begin
  if not public.can_edit_pm() then
    raise exception 'ليست لك صلاحية تحديث متابعة المشاريع' using errcode = '42501';
  end if;
  if p_id is not null then
    select project_id into v_proj from public.pm_milestones where id = p_id;
    if not found then
      raise exception 'المعلم غير موجود' using errcode = 'P0002';
    end if;
  end if;
  if v_proj is null or not exists (select 1 from public.projects where id = v_proj) then
    raise exception 'المشروع غير موجود' using errcode = 'P0002';
  end if;
  if not public.pm_row_ok(v_proj) then
    raise exception 'هذا المشروع خارج نطاقك' using errcode = '42501';
  end if;
  if length(v_title) not between 1 and 120 then
    raise exception 'عنوان المعلم من 1 إلى 120 حرفاً' using errcode = '22023';
  end if;
  if p_planned is null then
    raise exception 'التاريخ المخطط مطلوب' using errcode = '22023';
  end if;
  if length(coalesce(p_note, '')) > 300 then
    raise exception 'الملاحظة أطول من 300 حرف' using errcode = '22023';
  end if;
  if p_id is null then
    insert into public.pm_milestones (project_id, title, planned_date, forecast_date, note, sort_order, created_by, updated_by)
    values (v_proj, v_title, p_planned, p_forecast, coalesce(p_note, ''), coalesce(p_sort, 0), auth.uid(), auth.uid())
    returning id into v_id;
  else
    update public.pm_milestones
       set title = v_title, planned_date = p_planned, forecast_date = p_forecast, note = coalesce(p_note, ''),
           sort_order = coalesce(p_sort, 0), updated_at = now(), updated_by = auth.uid()
     where id = p_id;
  end if;
  select coalesce(nullif(assign_no, ''), name) into v_label from public.projects where id = v_proj;
  perform public.write_audit('milestone.save', v_proj, null,
    jsonb_build_object('id', v_id, 'title', v_title, 'planned', p_planned, 'forecast', p_forecast, 'created', p_id is null), v_label);
  return v_id;
end;
$$;

create or replace function public.pm_milestone_status(p_id uuid, p_status text, p_actual date default null)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  m public.pm_milestones;
  v_actual date;
  v_label text;
begin
  if not public.can_edit_pm() then
    raise exception 'ليست لك صلاحية تحديث متابعة المشاريع' using errcode = '42501';
  end if;
  select * into m from public.pm_milestones where id = p_id;
  if not found then
    raise exception 'المعلم غير موجود' using errcode = 'P0002';
  end if;
  if not public.pm_row_ok(m.project_id) then
    raise exception 'هذا المشروع خارج نطاقك' using errcode = '42501';
  end if;
  if p_status not in ('pending', 'done', 'cancelled') then
    raise exception 'حالة المعلم غير معروفة' using errcode = '22023';
  end if;
  if p_status = 'done' then
    v_actual := coalesce(p_actual, current_date);
    if v_actual > current_date then
      raise exception 'التاريخ الفعلي لا يكون في المستقبل' using errcode = '22023';
    end if;
  end if;
  update public.pm_milestones set status = p_status, actual_date = v_actual, updated_at = now(), updated_by = auth.uid()
   where id = p_id;
  select coalesce(nullif(assign_no, ''), name) into v_label from public.projects where id = m.project_id;
  perform public.write_audit('milestone.status', m.project_id, null,
    jsonb_build_object('id', p_id, 'title', m.title, 'status', p_status, 'actual', v_actual), v_label);
end;
$$;

create or replace function public.pm_milestone_delete(p_id uuid)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  m public.pm_milestones;
  v_label text;
begin
  if not public.can_edit_pm() then
    raise exception 'ليست لك صلاحية تحديث متابعة المشاريع' using errcode = '42501';
  end if;
  select * into m from public.pm_milestones where id = p_id;
  if not found then
    raise exception 'المعلم غير موجود' using errcode = 'P0002';
  end if;
  if not public.pm_row_ok(m.project_id) then
    raise exception 'هذا المشروع خارج نطاقك' using errcode = '42501';
  end if;
  delete from public.pm_milestones where id = p_id;
  select coalesce(nullif(assign_no, ''), name) into v_label from public.projects where id = m.project_id;
  perform public.write_audit('milestone.delete', m.project_id, null,
    jsonb_build_object('id', p_id, 'title', m.title), v_label);
end;
$$;

-- ---------------------------------------------------------------------
-- المؤشرات المخصصة
-- ---------------------------------------------------------------------
create or replace function public.kpi_can_define()
returns boolean
language sql stable security definer set search_path = public
as $$ select coalesce(public.my_role()::text = 'director', false) and public.writes_allowed() $$;

create or replace function public.kpi_can_record()
returns boolean
language sql stable security definer set search_path = public
as $$ select coalesce(public.my_role()::text in ('director', 'office_staff'), false) and public.writes_allowed() $$;

create or replace function public.kpi_def_save(
  p_id uuid, p_name text, p_unit text, p_target numeric, p_direction text default 'higher',
  p_active boolean default true, p_note text default '')
returns uuid
language plpgsql security definer set search_path = public
as $$
declare
  v_id uuid := p_id;
  v_name text := btrim(coalesce(p_name, ''));
begin
  if not public.kpi_can_define() then
    raise exception 'تعريف المؤشرات للمدير وحده' using errcode = '42501';
  end if;
  if length(v_name) not between 1 and 80 then
    raise exception 'اسم المؤشر من 1 إلى 80 حرفاً' using errcode = '22023';
  end if;
  if p_target is null then
    raise exception 'المستهدف مطلوب' using errcode = '22023';
  end if;
  if p_direction not in ('higher', 'lower') then
    raise exception 'اتجاه الأفضل: higher أو lower' using errcode = '22023';
  end if;
  if length(coalesce(p_unit, '')) > 20 or length(coalesce(p_note, '')) > 300 then
    raise exception 'الوحدة حتى 20 حرفاً والملاحظة حتى 300' using errcode = '22023';
  end if;
  if exists (select 1 from public.kpi_defs where lower(btrim(name)) = lower(v_name) and id is distinct from p_id) then
    raise exception 'يوجد مؤشر بهذا الاسم' using errcode = '23505';
  end if;
  if p_id is null then
    insert into public.kpi_defs (name, unit, target, direction, active, note, created_by, updated_by)
    values (v_name, coalesce(p_unit, ''), p_target, p_direction, coalesce(p_active, true), coalesce(p_note, ''), auth.uid(), auth.uid())
    returning id into v_id;
  else
    update public.kpi_defs set name = v_name, unit = coalesce(p_unit, ''), target = p_target, direction = p_direction,
           active = coalesce(p_active, true), note = coalesce(p_note, ''), updated_at = now(), updated_by = auth.uid()
     where id = p_id;
    if not found then
      raise exception 'المؤشر غير موجود' using errcode = 'P0002';
    end if;
  end if;
  perform public.write_audit('kpi.def_save', null, null,
    jsonb_build_object('id', v_id, 'name', v_name, 'target', p_target, 'direction', p_direction, 'created', p_id is null), v_name);
  return v_id;
end;
$$;

create or replace function public.kpi_def_delete(p_id uuid)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  v_name text;
begin
  if not public.kpi_can_define() then
    raise exception 'تعريف المؤشرات للمدير وحده' using errcode = '42501';
  end if;
  select name into v_name from public.kpi_defs where id = p_id;
  if not found then
    raise exception 'المؤشر غير موجود' using errcode = 'P0002';
  end if;
  delete from public.kpi_defs where id = p_id;
  perform public.write_audit('kpi.def_delete', null, null, jsonb_build_object('id', p_id, 'name', v_name), v_name);
end;
$$;

create or replace function public.kpi_value_set(p_kpi uuid, p_period text, p_value numeric, p_note text default '')
returns void
language plpgsql security definer set search_path = public
as $$
declare
  v_name text;
begin
  if not public.kpi_can_record() then
    raise exception 'تسجيل قيم المؤشرات للمدير وموظفي مكتبه' using errcode = '42501';
  end if;
  select name into v_name from public.kpi_defs where id = p_kpi;
  if not found then
    raise exception 'المؤشر غير موجود' using errcode = 'P0002';
  end if;
  if p_period is null or p_period !~ '^[0-9]{4}-(0[1-9]|1[0-2])$' then
    raise exception 'الفترة بصيغة YYYY-MM' using errcode = '22023';
  end if;
  if p_value is null then
    raise exception 'القيمة مطلوبة' using errcode = '22023';
  end if;
  if length(coalesce(p_note, '')) > 300 then
    raise exception 'الملاحظة أطول من 300 حرف' using errcode = '22023';
  end if;
  insert into public.kpi_values (kpi_id, period, value, note, updated_by)
  values (p_kpi, p_period, p_value, coalesce(p_note, ''), auth.uid())
  on conflict (kpi_id, period)
  do update set value = excluded.value, note = excluded.note, updated_at = now(), updated_by = auth.uid();
  perform public.write_audit('kpi.value_set', null, null,
    jsonb_build_object('kpi', p_kpi, 'name', v_name, 'period', p_period, 'value', p_value), v_name);
end;
$$;

create or replace function public.kpi_value_delete(p_kpi uuid, p_period text)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  v_name text;
begin
  if not public.kpi_can_record() then
    raise exception 'تسجيل قيم المؤشرات للمدير وموظفي مكتبه' using errcode = '42501';
  end if;
  select name into v_name from public.kpi_defs where id = p_kpi;
  if not found then
    raise exception 'المؤشر غير موجود' using errcode = 'P0002';
  end if;
  delete from public.kpi_values where kpi_id = p_kpi and period = p_period;
  if found then
    perform public.write_audit('kpi.value_delete', null, null,
      jsonb_build_object('kpi', p_kpi, 'name', v_name, 'period', p_period), v_name);
  end if;
end;
$$;

revoke execute on function public.kpi_can_define(), public.kpi_can_record() from public, anon, authenticated;
revoke execute on function
  public.pm_milestone_save(uuid, uuid, text, date, date, text, integer), public.pm_milestone_status(uuid, text, date),
  public.pm_milestone_delete(uuid), public.kpi_def_save(uuid, text, text, numeric, text, boolean, text),
  public.kpi_def_delete(uuid), public.kpi_value_set(uuid, text, numeric, text), public.kpi_value_delete(uuid, text)
  from public, anon;
grant execute on function
  public.pm_milestone_save(uuid, uuid, text, date, date, text, integer), public.pm_milestone_status(uuid, text, date),
  public.pm_milestone_delete(uuid), public.kpi_def_save(uuid, text, text, numeric, text, boolean, text),
  public.kpi_def_delete(uuid), public.kpi_value_set(uuid, text, numeric, text), public.kpi_value_delete(uuid, text)
  to authenticated;
