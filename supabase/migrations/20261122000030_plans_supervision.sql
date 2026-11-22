-- =====================================================================
--  الترحيل 30: إعداد البرنامج الزمني من المقايسة المعتمدة (الشؤون الفنية) ومتابعة تنفيذه (الإشراف)
--   1. اعتماد المقايسة: مسودة أو معتمدة، يعتمدها رئيس الشؤون الفنية أو المدير، والمعتمدة لا تُعدَّل ولا تُحذف
--      إلا بإعادة فتحها. بنود المقايسات المعتمدة للعقد هي بنود العقد.
--   2. pm_plans: البرنامج الزمني لكل عقد (مسودة أو معتمد ومُحال إلى الإشراف) ببداية البرنامج.
--   3. pm_phases: مراحل التنفيذ مرتبة، ولكل مرحلة فاصل عن سابقتها (سالب = تداخل).
--   4. بنود البرنامج (pm_items) تُضاف لها: المرحلة، والمدة، والإزاحة داخل المرحلة، والبند السابق (تبعية)،
--      والمصدر (بند مقايسة، أو بند إضافي للعقد، أو نشاط)، والوحدة والكمية، و«لا ينطبق».
--      تواريخ البنود ذات المدة تُحسب (pm_plan_recalc): المرحلة تبدأ بنهاية سابقتها + فاصلها، والبند يبدأ ببداية
--      مرحلته أو بنهاية البند السابق له (أيهما أبعد) + إزاحته، وينتهي بعد مدته.
--   5. pm_plan_generate: برنامج مبدئي من بنود المقايسات المعتمدة: مرحلة لكل قسم من أقسام اللائحة بترتيبها،
--      مدة المرحلة = المدة الإجمالية × نصيبها من قيمة المقايسة (3 أيام على الأقل)، ومدة البند = مدة مرحلته
--      × الجذر التربيعي لنسبة قيمته إلى أكبر بند في المرحلة (يوم على الأقل).
--   6. الصلاحيات: الإعداد (البنود والمراحل والمدد والتوليد) للشؤون الفنية ومكتب المدير والمنح «pm:plan»،
--      ولا يُعدَّل إلا والبرنامج مسودة؛ والاعتماد وإعادة الفتح لرئيس الشؤون الفنية والمدير؛ والمتابعة (الإنجاز
--      والتواريخ الفعلية و«لا ينطبق» والملاحظات) لرئيس القسم المشرف على العقد ومكتب المدير والمنح «pm:track»،
--      وعلى البرنامج المعتمد وحده.
--   7. البند الإضافي أو النشاط لا يكرر بنداً في المقايسة المعتمدة للعقد (رقم اللائحة نفسه أو الوصف نفسه).
--  كل كتابة عبر دوال مدققة. يُشغَّل بعد 20261121000029_schedule_items.sql. إعادة تشغيله آمنة.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 0. أدوار مساعدة
-- ---------------------------------------------------------------------
create or replace function public.is_dept_head_of(p_dept text)
returns boolean
language sql stable security definer set search_path = public
as $$
  select coalesce(public.my_role()::text, '') = 'dept_head'
     and exists (select 1 from public.profiles where id = auth.uid() and department = p_dept)
$$;

create or replace function public.can_prepare_plan(p_project uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
  select public.writes_allowed() and (
    coalesce(public.my_role()::text, '') in ('director', 'office_staff')
    or public.is_dept_head_of('technical')
    or public.has_grant('pm:plan'))
$$;

create or replace function public.can_approve_plan(p_project uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
  select public.writes_allowed() and (public.is_director() or public.is_dept_head_of('technical'))
$$;

create or replace function public.can_track_plan(p_project uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
  select public.writes_allowed() and (
    coalesce(public.my_role()::text, '') in ('director', 'office_staff')
    or (coalesce(public.my_role()::text, '') = 'dept_head'
        and exists (select 1 from public.profiles me join public.projects p on p.id = p_project
                     where me.id = auth.uid() and me.department is not null and me.department = p.department))
    or public.has_grant('pm:track'))
$$;

-- النطاقان الجديدان للمنح الدقيق
alter table public.user_grants drop constraint if exists user_grants_scope_check;
alter table public.user_grants add constraint user_grants_scope_check
  check (scope ~ '^(form:[a-z0-9_]{1,40}|docs:(boq|letter|design)|supervision:reports|unit:[a-z_]{2,40}|swot|pm:(plan|track))$');

create or replace function public.grant_scope_ok(p_scope text)
returns boolean
language sql stable security definer set search_path = public
as $$
  select case
    when p_scope like 'form:%' then exists (select 1 from public.form_defs where key = substr(p_scope, 6))
    when p_scope like 'unit:%' then public.unit_kind_spec(substr(p_scope, 6)) is not null
    else p_scope in ('docs:boq', 'docs:letter', 'docs:design', 'supervision:reports', 'swot', 'pm:plan', 'pm:track')
  end
$$;

-- ---------------------------------------------------------------------
-- 1. اعتماد المقايسة
-- ---------------------------------------------------------------------
alter table public.boq_sheets add column if not exists status text not null default 'draft';
alter table public.boq_sheets drop constraint if exists boq_sheets_status_check;
alter table public.boq_sheets add constraint boq_sheets_status_check check (status in ('draft', 'approved'));
alter table public.boq_sheets add column if not exists approved_at timestamptz;
alter table public.boq_sheets add column if not exists approved_by uuid references public.profiles (id) on delete set null;
create index if not exists boq_sheets_approved_by_idx on public.boq_sheets (approved_by);

-- المعتمدة لا تُعدَّل ولا تُحذف (إلا نقلها مع العقد عند الدمج وفكّه)
create or replace function public.boq_sheets_lock()
returns trigger
language plpgsql security definer set search_path = public
as $$
begin
  if tg_op = 'DELETE' then
    if old.status = 'approved' then
      raise exception 'المقايسة معتمدة؛ يعيد فتحها رئيس الشؤون الفنية أو المدير قبل حذفها' using errcode = '42501';
    end if;
    return old;
  end if;
  -- المحتوى وحده؛ نقل العقد عند الدمج وفكّ ربط المستخدمين المحذوفين مسموحان
  if old.status = 'approved' and new.status = 'approved'
     and (new.list_id, new.title, new.ref_no, new.notes, new.show_prices, new.lines, new.line_count, new.total)
         is distinct from (old.list_id, old.title, old.ref_no, old.notes, old.show_prices, old.lines, old.line_count, old.total) then
    raise exception 'المقايسة معتمدة؛ يعيد فتحها رئيس الشؤون الفنية أو المدير للتعديل' using errcode = '42501';
  end if;
  return new;
end;
$$;
drop trigger if exists boq_sheets_lock on public.boq_sheets;
create trigger boq_sheets_lock before update or delete on public.boq_sheets
  for each row execute function public.boq_sheets_lock();

create or replace function public.approve_boq(p_id uuid, p_approve boolean)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  r public.boq_sheets;
begin
  select * into r from public.boq_sheets where id = p_id for update;
  if not found then
    raise exception 'المقايسة غير موجودة' using errcode = 'P0002';
  end if;
  if not (public.writes_allowed() and (public.is_director() or public.is_dept_head_of('technical'))) then
    raise exception 'اعتماد المقايسات لرئيس الشؤون الفنية ومدير المكتب' using errcode = '42501';
  end if;
  if coalesce(p_approve, false) then
    if r.status = 'approved' then
      return;
    end if;
    if r.project_id is null then
      raise exception 'اربط المقايسة بعقد قبل اعتمادها' using errcode = '22023';
    end if;
    if r.line_count = 0 then
      raise exception 'المقايسة بلا بنود' using errcode = '22023';
    end if;
    update public.boq_sheets set status = 'approved', approved_at = now(), approved_by = auth.uid() where id = p_id;
    perform public.write_audit('boq.approve', r.project_id, null,
      jsonb_build_object('title', r.title, 'lines', r.line_count, 'total', r.total));
  else
    if r.status = 'draft' then
      return;
    end if;
    if exists (select 1 from public.pm_plans where project_id = r.project_id and status = 'approved')
       and exists (select 1 from public.pm_items where boq_sheet_id = p_id) then
      raise exception 'البرنامج الزمني المعتمد للعقد مبني على هذه المقايسة؛ أعد فتح البرنامج أولاً' using errcode = '22023';
    end if;
    update public.boq_sheets set status = 'draft', approved_at = null, approved_by = null where id = p_id;
    perform public.write_audit('boq.reopen', r.project_id, null, jsonb_build_object('title', r.title));
  end if;
end;
$$;

-- ---------------------------------------------------------------------
-- 2. البرنامج الزمني ومراحله
-- ---------------------------------------------------------------------
create table if not exists public.pm_plans (
  id             uuid primary key default gen_random_uuid(),
  project_id     uuid not null unique references public.projects (id) on delete cascade,
  origin_project uuid references public.projects (id) on delete set null,
  status         text not null default 'draft' check (status in ('draft', 'approved')),
  start_date     date not null,
  notes          text not null default '' check (length(notes) <= 1000),
  version        integer not null default 0,
  approved_at    timestamptz,
  approved_by    uuid references public.profiles (id) on delete set null,
  created_at     timestamptz not null default now(),
  created_by     uuid references public.profiles (id) on delete set null,
  updated_at     timestamptz not null default now(),
  updated_by     uuid references public.profiles (id) on delete set null
);
create index if not exists pm_plans_origin_idx      on public.pm_plans (origin_project);
create index if not exists pm_plans_approved_by_idx on public.pm_plans (approved_by);
create index if not exists pm_plans_created_by_idx  on public.pm_plans (created_by);
create index if not exists pm_plans_updated_by_idx  on public.pm_plans (updated_by);

create table if not exists public.pm_phases (
  id             uuid primary key default gen_random_uuid(),
  project_id     uuid not null references public.projects (id) on delete cascade,
  origin_project uuid references public.projects (id) on delete set null,
  sort           integer not null default 0,
  name           text not null check (length(btrim(name)) between 2 and 120),
  lag_days       integer not null default 0 check (lag_days between -3650 and 3650),
  created_at     timestamptz not null default now(),
  created_by     uuid references public.profiles (id) on delete set null,
  updated_at     timestamptz not null default now(),
  updated_by     uuid references public.profiles (id) on delete set null
);
create index if not exists pm_phases_project_idx    on public.pm_phases (project_id, sort);
create index if not exists pm_phases_origin_idx     on public.pm_phases (origin_project);
create index if not exists pm_phases_created_by_idx on public.pm_phases (created_by);
create index if not exists pm_phases_updated_by_idx on public.pm_phases (updated_by);

alter table public.pm_items add column if not exists phase_id uuid references public.pm_phases (id) on delete set null;
alter table public.pm_items add column if not exists duration_days integer check (duration_days between 1 and 3650);
alter table public.pm_items add column if not exists offset_days integer not null default 0 check (offset_days between 0 and 3650);
alter table public.pm_items add column if not exists depends_on uuid references public.pm_items (id) on delete set null;
alter table public.pm_items add column if not exists source text not null default 'manual' check (source in ('manual', 'boq', 'extra'));
alter table public.pm_items add column if not exists boq_sheet_id uuid references public.boq_sheets (id) on delete set null;
alter table public.pm_items add column if not exists boq_line integer;
alter table public.pm_items add column if not exists price_seq integer;
alter table public.pm_items add column if not exists unit text not null default '' check (length(unit) <= 20);
alter table public.pm_items add column if not exists qty numeric(16, 3) check (qty >= 0);
alter table public.pm_items add column if not exists not_applicable boolean not null default false;
create index if not exists pm_items_phase_idx      on public.pm_items (phase_id);
create index if not exists pm_items_depends_idx    on public.pm_items (depends_on);
create index if not exists pm_items_boq_sheet_idx  on public.pm_items (boq_sheet_id);

-- البرنامج مسودة (يُنشأ إن لم يوجد ببداية البرنامج الزمني للعقد)، وإلا فلا تعديل
create or replace function public.pm_plan_draft(p_project uuid)
returns public.pm_plans
language plpgsql security definer set search_path = public
as $$
declare
  pl public.pm_plans;
begin
  select * into pl from public.pm_plans where project_id = p_project for update;
  if not found then
    if not exists (select 1 from public.projects where id = p_project and merged_into is null) then
      raise exception 'العقد غير موجود' using errcode = '22023';
    end if;
    insert into public.pm_plans (project_id, start_date, created_by, updated_by)
    values (p_project, coalesce((select start_date from public.pm_projects where project_id = p_project), current_date),
            auth.uid(), auth.uid())
    returning * into pl;
  elsif pl.status = 'approved' then
    raise exception 'البرنامج الزمني معتمد ومُحال إلى الإشراف؛ يعيد فتحه رئيس الشؤون الفنية أو المدير للتعديل' using errcode = '42501';
  end if;
  return pl;
end;
$$;

-- حساب تواريخ البنود ذات المدة (تمريرة أمامية بترتيب المراحل ثم البنود)
create or replace function public.pm_plan_recalc(p_project uuid)
returns integer
language plpgsql security definer set search_path = public
as $$
declare
  v_start  date;
  ph       record;
  it       record;
  v_pstart date;
  v_pend   date;
  v_prev   date;
  v_base   date;
  v_s      date;
  v_ends   jsonb := '{}'::jsonb;
  n        integer := 0;
begin
  select start_date into v_start from public.pm_plans where project_id = p_project;
  if v_start is null then
    return 0;
  end if;
  -- البنود دون مرحلة وبمدة: من بداية البرنامج
  for it in select i.id, i.duration_days, i.offset_days, i.depends_on, i.planned_end
              from public.pm_items i where i.project_id = p_project and i.phase_id is null
             order by i.sort, i.created_at loop
    if it.duration_days is null then
      v_ends := v_ends || jsonb_build_object(it.id::text, it.planned_end);
      continue;
    end if;
    v_base := greatest(v_start, coalesce((v_ends ->> it.depends_on::text)::date, v_start));
    v_s := v_base + it.offset_days;
    update public.pm_items set planned_start = v_s, planned_end = v_s + it.duration_days
     where id = it.id and (planned_start, planned_end) is distinct from (v_s, v_s + it.duration_days);
    v_ends := v_ends || jsonb_build_object(it.id::text, v_s + it.duration_days);
    n := n + 1;
  end loop;
  v_prev := null;
  for ph in select id, lag_days from public.pm_phases where project_id = p_project order by sort, created_at loop
    v_pstart := case when v_prev is null then v_start else greatest(v_start, v_prev + ph.lag_days) end;
    v_pend := v_pstart;
    for it in select i.id, i.duration_days, i.offset_days, i.depends_on, i.planned_end
                from public.pm_items i where i.project_id = p_project and i.phase_id = ph.id
               order by i.sort, i.created_at loop
      if it.duration_days is null then
        v_pend := greatest(v_pend, it.planned_end);
        v_ends := v_ends || jsonb_build_object(it.id::text, it.planned_end);
        continue;
      end if;
      v_base := greatest(v_pstart, coalesce((v_ends ->> it.depends_on::text)::date, v_pstart));
      v_s := v_base + it.offset_days;
      update public.pm_items set planned_start = v_s, planned_end = v_s + it.duration_days
       where id = it.id and (planned_start, planned_end) is distinct from (v_s, v_s + it.duration_days);
      v_ends := v_ends || jsonb_build_object(it.id::text, v_s + it.duration_days);
      v_pend := greatest(v_pend, v_s + it.duration_days);
      n := n + 1;
    end loop;
    v_prev := v_pend;
  end loop;
  return n;
end;
$$;

-- بعد كل تغيير: إعادة الحساب، ثم ترجمة التنفيذ إلى المخاطر وSWOT إن وُجدت دالتها (الترحيل 31)
create or replace function public.pm_after_change(p_project uuid)
returns void
language plpgsql security definer set search_path = public
as $$
begin
  perform public.pm_plan_recalc(p_project);
  if to_regprocedure('public.pm_sync_auto(uuid)') is not null then
    execute 'select public.pm_sync_auto($1)' using p_project;
  end if;
end;
$$;

-- ترتيب البند في البرنامج: (ترتيب مرحلته، ترتيبه)؛ البند دون مرحلة يسبق المراحل
create or replace function public.pm_item_rank(p_item uuid)
returns bigint
language sql stable security definer set search_path = public
as $$
  select (coalesce(ph.sort, -1000000)::bigint + 1000000) * 1000000000 + i.sort
    from public.pm_items i left join public.pm_phases ph on ph.id = i.phase_id
   where i.id = p_item
$$;

-- لا يكرر البند غير المأخوذ من المقايسة بنداً في المقايسات المعتمدة للعقد
create or replace function public.pm_boq_duplicate(p_project uuid, p_price_seq integer, p_title text, p_self uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
  with lines as (
    select (l ->> 'seq')::integer as seq,
           public.price_norm(regexp_replace(coalesce(l ->> 'desc', ''), '^.* — ', '')) as d
      from public.boq_sheets s, jsonb_array_elements(s.lines) l
     where s.project_id = p_project and s.status = 'approved'
  )
  select exists (select 1 from lines where (p_price_seq is not null and seq = p_price_seq)
                                        or (d <> '' and d = public.price_norm(p_title)))
      or exists (select 1 from public.pm_items i
                  where i.project_id = p_project and i.id is distinct from p_self and i.source = 'boq'
                    and ((p_price_seq is not null and i.price_seq = p_price_seq)
                         or public.price_norm(i.title) = public.price_norm(p_title)))
$$;

-- ---------------------------------------------------------------------
-- 3. الحفظ: الإعداد للشؤون الفنية على المسودة، والمتابعة للإشراف على المعتمد
-- ---------------------------------------------------------------------
create or replace function public.save_pm_item(p_id uuid, p_data jsonb)
returns uuid
language plpgsql security definer set search_path = public
as $$
declare
  o        public.pm_items;
  n        public.pm_items;
  pl       public.pm_plans;
  v_proj   uuid;
  v_new    boolean := p_id is null;
  v_struct boolean := false;
  v_track  boolean := false;
  v_title  text;
  v_code   text;
  v_phase  uuid;
  v_dur    integer;
  v_off    integer;
  v_dep    uuid;
  v_w      numeric;
  v_work   uuid;
  v_sort   integer;
  v_ps     date;
  v_pe     date;
  v_src    text;
  v_unit   text;
  v_qty    numeric;
  v_pseq   integer;
  v_pr     numeric;
  v_as     date;
  v_ae     date;
  v_notes  text;
  v_na     boolean;
  v_rank   bigint;
begin
  if jsonb_typeof(coalesce(p_data, 'null'::jsonb)) <> 'object' then
    raise exception 'بيانات غير صالحة' using errcode = '22023';
  end if;
  if v_new then
    v_proj := public.jproject(p_data, 'project_id', true);
  else
    select * into o from public.pm_items where id = p_id for update;
    if not found then
      raise exception 'البند غير موجود' using errcode = 'P0002';
    end if;
    v_proj := o.project_id;
  end if;

  -- القيم: المرسلة، وإلا القائمة
  v_title := case when p_data ? 'title' then public.jtext(p_data, 'title', 300, 'اسم البند') else o.title end;
  v_code  := case when p_data ? 'code' then public.jtext(p_data, 'code', 20, 'رقم البند') else coalesce(o.code, '') end;
  begin
    v_phase := case when p_data ? 'phase_id' then nullif(btrim(coalesce(p_data ->> 'phase_id', '')), '')::uuid else o.phase_id end;
    v_dep   := case when p_data ? 'depends_on' then nullif(btrim(coalesce(p_data ->> 'depends_on', '')), '')::uuid else o.depends_on end;
    v_work  := case when p_data ? 'work_id' then nullif(btrim(coalesce(p_data ->> 'work_id', '')), '')::uuid else o.work_id end;
  exception when invalid_text_representation then
    raise exception 'مرجع غير صالح' using errcode = '22023';
  end;
  v_dur   := case when p_data ? 'duration_days' then public.jint(p_data, 'duration_days', 1, 3650, 'المدة') else o.duration_days end;
  v_off   := case when p_data ? 'offset_days' then coalesce(public.jint(p_data, 'offset_days', 0, 3650, 'الإزاحة'), 0) else coalesce(o.offset_days, 0) end;
  v_w     := case when p_data ? 'weight' then public.jnum(p_data, 'weight', 0.001, 1e11, 'الوزن') else o.weight end;
  v_sort  := case when p_data ? 'sort' then public.jint(p_data, 'sort', 0, 100000000, 'الترتيب') else o.sort end;
  v_ps    := case when p_data ? 'planned_start' then public.jdate(p_data, 'planned_start', 'البداية المخططة') else o.planned_start end;
  v_pe    := case when p_data ? 'planned_end' then public.jdate(p_data, 'planned_end', 'النهاية المخططة') else o.planned_end end;
  v_src   := case when v_new then coalesce(nullif(p_data ->> 'source', ''), 'manual') else o.source end;
  v_unit  := case when p_data ? 'unit' then public.jtext(p_data, 'unit', 20, 'الوحدة') else coalesce(o.unit, '') end;
  v_qty   := case when p_data ? 'qty' then public.jnum(p_data, 'qty', 0, 1e12, 'الكمية') else o.qty end;
  v_pseq  := case when p_data ? 'price_seq' then public.jint(p_data, 'price_seq', 1, 1000000, 'رقم اللائحة') else o.price_seq end;
  v_pr    := case when p_data ? 'progress' then coalesce(public.jnum(p_data, 'progress', 0, 100, 'نسبة الإنجاز'), 0) else coalesce(o.progress, 0) end;
  v_as    := case when p_data ? 'actual_start' then public.jdate(p_data, 'actual_start', 'البداية الفعلية') else o.actual_start end;
  v_ae    := case when p_data ? 'actual_end' then public.jdate(p_data, 'actual_end', 'النهاية الفعلية') else o.actual_end end;
  v_notes := case when p_data ? 'notes' then public.jtext(p_data, 'notes', 1000, 'ملاحظات') else coalesce(o.notes, '') end;
  v_na    := case when p_data ? 'not_applicable' then public.jbool(p_data, 'not_applicable') else coalesce(o.not_applicable, false) end;

  if v_new and v_src not in ('manual', 'extra') then
    raise exception 'بنود المقايسة تُنشأ من توليد البرنامج' using errcode = '22023';
  end if;

  -- ما الذي تغيّر: بيانات البند (إعداد) أم التنفيذ (متابعة)
  v_struct := v_new or v_title is distinct from o.title or v_code is distinct from o.code or v_phase is distinct from o.phase_id
              or v_dur is distinct from o.duration_days or v_off is distinct from o.offset_days or v_dep is distinct from o.depends_on
              or v_w is distinct from o.weight or v_work is distinct from o.work_id or v_sort is distinct from o.sort
              or (v_dur is null and (v_ps is distinct from o.planned_start or v_pe is distinct from o.planned_end))
              or v_unit is distinct from o.unit or v_qty is distinct from o.qty or v_pseq is distinct from o.price_seq;
  v_track := (v_new and (v_pr <> 0 or v_as is not null or v_ae is not null or v_na))
             or (not v_new and (v_pr is distinct from o.progress or v_as is distinct from o.actual_start
                                or v_ae is distinct from o.actual_end or v_na is distinct from o.not_applicable
                                or v_notes is distinct from o.notes));

  if v_struct then
    if not public.can_prepare_plan(v_proj) then
      raise exception 'إعداد البرنامج الزمني وبنوده ومددها من اختصاص الشؤون الفنية' using errcode = '42501';
    end if;
    pl := public.pm_plan_draft(v_proj);
  else
    select * into pl from public.pm_plans where project_id = v_proj;
  end if;
  if v_track then
    if v_new then
      raise exception 'تُسجَّل نسبة الإنجاز بعد اعتماد البرنامج الزمني وإحالته إلى الإشراف' using errcode = '22023';
    end if;
    if not public.can_track_plan(v_proj) then
      raise exception 'متابعة التنفيذ وتسجيل الإنجاز من اختصاص القسم المشرف على العقد' using errcode = '42501';
    end if;
    if pl.id is null or pl.status <> 'approved' then
      raise exception 'تُسجَّل نسب الإنجاز على البرنامج الزمني المعتمد' using errcode = '22023';
    end if;
  end if;
  if not v_struct and not v_track then
    return p_id;
  end if;

  -- التحقق
  if length(v_title) < 2 then
    raise exception 'أدخل اسم البند' using errcode = '22023';
  end if;
  if v_phase is not null and not exists (select 1 from public.pm_phases where id = v_phase and project_id = v_proj) then
    raise exception 'المرحلة ليست من مراحل هذا العقد' using errcode = '22023';
  end if;
  if v_work is not null and not exists (select 1 from public.contract_works where id = v_work and project_id = v_proj) then
    raise exception 'عمل العقد المختار ليس من أعمال هذا العقد' using errcode = '22023';
  end if;
  if v_dur is null then
    if v_ps is null or v_pe is null then
      raise exception 'حدّد مدة البند، أو بدايته ونهايته المخططتين' using errcode = '22023';
    end if;
    if v_pe < v_ps then
      raise exception 'النهاية المخططة قبل البداية المخططة' using errcode = '22023';
    end if;
  else
    v_ps := coalesce(v_ps, pl.start_date);
    v_pe := v_ps + v_dur;
  end if;
  if v_struct and v_src <> 'boq' and public.pm_boq_duplicate(v_proj, v_pseq, v_title, p_id) then
    raise exception 'هذا البند موجود في المقايسة المعتمدة للعقد؛ لا يُضاف مرة أخرى' using errcode = '22023';
  end if;
  if v_as is not null and v_as > current_date + 1 then
    raise exception 'البداية الفعلية في المستقبل' using errcode = '22023';
  end if;
  if v_ae is not null and v_ae > current_date + 1 then
    raise exception 'النهاية الفعلية في المستقبل' using errcode = '22023';
  end if;
  if v_ae is not null and v_as is not null and v_ae < v_as then
    raise exception 'النهاية الفعلية قبل البداية الفعلية' using errcode = '22023';
  end if;
  if v_ae is not null and v_pr < 100 then
    raise exception 'النهاية الفعلية تُسجَّل عند اكتمال البند (100%%)' using errcode = '22023';
  end if;

  if v_new then
    insert into public.pm_items (project_id, work_id, sort, code, title, planned_start, planned_end, weight, progress,
                                 notes, phase_id, duration_days, offset_days, source, unit, qty, price_seq,
                                 created_by, updated_by)
    values (v_proj, v_work, coalesce(v_sort, (select coalesce(max(sort), 0) + 10 from public.pm_items where project_id = v_proj)),
            v_code, v_title, v_ps, v_pe, v_w, 0, v_notes, v_phase, v_dur, v_off, v_src, v_unit, v_qty, v_pseq,
            auth.uid(), auth.uid())
    returning * into n;
  else
    update public.pm_items set
      work_id = v_work, sort = coalesce(v_sort, o.sort), code = v_code, title = v_title, planned_start = v_ps, planned_end = v_pe,
      weight = v_w, progress = round(v_pr, 2), actual_start = v_as, actual_end = v_ae, notes = v_notes,
      phase_id = v_phase, duration_days = v_dur, offset_days = v_off, depends_on = v_dep, unit = v_unit, qty = v_qty,
      price_seq = v_pseq, not_applicable = v_na, updated_at = now(), updated_by = auth.uid()
    where id = p_id
    returning * into n;
  end if;

  -- التبعية لبند سابق في الترتيب من العقد نفسه
  if v_new and v_dep is not null then
    update public.pm_items set depends_on = v_dep where id = n.id returning * into n;
  end if;
  if n.depends_on is not null then
    v_rank := public.pm_item_rank(n.id);
    if n.depends_on = n.id
       or not exists (select 1 from public.pm_items where id = n.depends_on and project_id = v_proj)
       or public.pm_item_rank(n.depends_on) >= v_rank then
      raise exception 'يتبع البند بنداً سابقاً له في ترتيب البرنامج من العقد نفسه' using errcode = '22023';
    end if;
  end if;

  perform public.pm_after_change(v_proj);
  select * into n from public.pm_items where id = n.id;
  if v_new then
    perform public.write_audit('pm.item_add', v_proj, null,
      jsonb_build_object('title', v_title, 'source', v_src, 'duration_days', v_dur, 'planned_start', n.planned_start, 'planned_end', n.planned_end));
  else
    perform public.write_audit(case when v_struct then 'pm.item_update' else 'pm.item_progress' end, v_proj, null,
      jsonb_build_object('title', v_title,
                         'changes', public.jsonb_changes(to_jsonb(o), to_jsonb(n), array['updated_at', 'updated_by'])));
  end if;
  return n.id;
end;
$$;

create or replace function public.delete_pm_item(p_id uuid)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  r public.pm_items;
begin
  select * into r from public.pm_items where id = p_id for update;
  if not found then
    raise exception 'البند غير موجود' using errcode = 'P0002';
  end if;
  if not public.can_prepare_plan(r.project_id) then
    raise exception 'حذف بنود البرنامج الزمني من اختصاص الشؤون الفنية' using errcode = '42501';
  end if;
  perform public.pm_plan_draft(r.project_id);
  delete from public.pm_items where id = p_id;
  perform public.pm_after_change(r.project_id);
  perform public.write_audit('pm.item_delete', r.project_id, null,
    jsonb_build_object('title', r.title, 'planned_start', r.planned_start, 'planned_end', r.planned_end, 'progress', r.progress));
end;
$$;

create or replace function public.reorder_pm_items(p_project uuid, p_ids uuid[])
returns void
language plpgsql security definer set search_path = public
as $$
begin
  if not public.can_prepare_plan(p_project) then
    raise exception 'ترتيب البنود من اختصاص الشؤون الفنية' using errcode = '42501';
  end if;
  perform public.pm_plan_draft(p_project);
  if coalesce(array_length(p_ids, 1), 0) <> (select count(*) from public.pm_items where project_id = p_project)
     or exists (select 1 from unnest(p_ids) x where not exists (select 1 from public.pm_items where id = x and project_id = p_project))
     or (select count(distinct x) from unnest(p_ids) x) <> coalesce(array_length(p_ids, 1), 0) then
    raise exception 'قائمة البنود لا تطابق بنود العقد' using errcode = '22023';
  end if;
  update public.pm_items i set sort = o.n * 10, updated_at = now(), updated_by = auth.uid()
    from unnest(p_ids) with ordinality o(id, n)
   where i.id = o.id and i.sort <> o.n * 10;
  if exists (select 1 from public.pm_items i where i.project_id = p_project and i.depends_on is not null
               and public.pm_item_rank(i.depends_on) >= public.pm_item_rank(i.id)) then
    raise exception 'الترتيب يضع بنداً قبل البند الذي يتبعه' using errcode = '22023';
  end if;
  perform public.pm_after_change(p_project);
  perform public.write_audit('pm.items_reorder', p_project, null, jsonb_build_object('items', array_length(p_ids, 1)));
end;
$$;

create or replace function public.pm_items_from_works(p_project uuid)
returns integer
language plpgsql security definer set search_path = public
as $$
declare
  s  public.pm_projects;
  pl public.pm_plans;
  n  integer;
begin
  if not public.can_prepare_plan(p_project) then
    raise exception 'إنشاء البنود من اختصاص الشؤون الفنية' using errcode = '42501';
  end if;
  pl := public.pm_plan_draft(p_project);
  select * into s from public.pm_projects where project_id = p_project;
  if s.start_date is null or s.end_date is null then
    raise exception 'سجّل تاريخي بداية العقد ونهايته في البرنامج الزمني أولاً' using errcode = '22023';
  end if;
  insert into public.pm_items (project_id, work_id, sort, code, title, planned_start, planned_end, created_by, updated_by)
  select p_project, w.id,
         (select coalesce(max(sort), 0) from public.pm_items where project_id = p_project) + 10 * row_number() over (order by w.sort, w.created_at),
         left(w.ref_no, 20),
         left(coalesce(nullif(btrim(w.title), ''), nullif(btrim(w.company), ''), 'عمل ' || w.ref_no), 300),
         s.start_date, s.end_date, auth.uid(), auth.uid()
    from public.contract_works w
   where w.project_id = p_project
     and not exists (select 1 from public.pm_items i where i.work_id = w.id)
     and length(btrim(coalesce(nullif(btrim(w.title), ''), nullif(btrim(w.company), ''), 'عمل ' || w.ref_no))) >= 2;
  get diagnostics n = row_count;
  if n > 0 then
    perform public.pm_after_change(p_project);
    perform public.write_audit('pm.items_from_works', p_project, null, jsonb_build_object('items', n));
  end if;
  return n;
end;
$$;

-- بداية البرنامج وملاحظاته
create or replace function public.save_pm_plan(p_project uuid, p_data jsonb)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  pl public.pm_plans;
  v_start date := public.jdate(p_data, 'start_date', 'بداية البرنامج');
begin
  if not public.can_prepare_plan(p_project) then
    raise exception 'إعداد البرنامج الزمني من اختصاص الشؤون الفنية' using errcode = '42501';
  end if;
  pl := public.pm_plan_draft(p_project);
  update public.pm_plans set
    start_date = coalesce(v_start, start_date),
    notes = case when p_data ? 'notes' then public.jtext(p_data, 'notes', 1000, 'ملاحظات') else notes end,
    updated_at = now(), updated_by = auth.uid()
  where id = pl.id;
  perform public.pm_after_change(p_project);
  perform public.write_audit('pm.plan_save', p_project, null,
    jsonb_build_object('start_date', coalesce(v_start, pl.start_date), 'old_start', pl.start_date));
end;
$$;

create or replace function public.save_pm_phase(p_id uuid, p_data jsonb)
returns uuid
language plpgsql security definer set search_path = public
as $$
declare
  o      public.pm_phases;
  v_proj uuid;
  v_name text := public.jtext(p_data, 'name', 120, 'اسم المرحلة');
  v_lag  integer := coalesce(public.jint(p_data, 'lag_days', -3650, 3650, 'الفاصل'), 0);
  v_sort integer := public.jint(p_data, 'sort', 0, 100000000, 'الترتيب');
  v_id   uuid;
begin
  if p_id is null then
    v_proj := public.jproject(p_data, 'project_id', true);
  else
    select * into o from public.pm_phases where id = p_id for update;
    if not found then
      raise exception 'المرحلة غير موجودة' using errcode = 'P0002';
    end if;
    v_proj := o.project_id;
  end if;
  if not public.can_prepare_plan(v_proj) then
    raise exception 'مراحل البرنامج الزمني من اختصاص الشؤون الفنية' using errcode = '42501';
  end if;
  perform public.pm_plan_draft(v_proj);
  if length(v_name) < 2 then
    raise exception 'أدخل اسم المرحلة' using errcode = '22023';
  end if;
  if p_id is null then
    insert into public.pm_phases (project_id, sort, name, lag_days, created_by, updated_by)
    values (v_proj, coalesce(v_sort, (select coalesce(max(sort), 0) + 10 from public.pm_phases where project_id = v_proj)),
            v_name, v_lag, auth.uid(), auth.uid())
    returning id into v_id;
  else
    update public.pm_phases set name = v_name, lag_days = v_lag, sort = coalesce(v_sort, sort), updated_at = now(), updated_by = auth.uid()
     where id = p_id;
    v_id := p_id;
    if exists (select 1 from public.pm_items i where i.project_id = v_proj and i.depends_on is not null
                 and public.pm_item_rank(i.depends_on) >= public.pm_item_rank(i.id)) then
      raise exception 'ترتيب المرحلة يضع بنداً قبل البند الذي يتبعه' using errcode = '22023';
    end if;
  end if;
  perform public.pm_after_change(v_proj);
  perform public.write_audit('pm.phase_save', v_proj, null,
    jsonb_build_object('name', v_name, 'lag_days', v_lag, 'new', p_id is null));
  return v_id;
end;
$$;

create or replace function public.delete_pm_phase(p_id uuid)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  r public.pm_phases;
begin
  select * into r from public.pm_phases where id = p_id for update;
  if not found then
    raise exception 'المرحلة غير موجودة' using errcode = 'P0002';
  end if;
  if not public.can_prepare_plan(r.project_id) then
    raise exception 'مراحل البرنامج الزمني من اختصاص الشؤون الفنية' using errcode = '42501';
  end if;
  perform public.pm_plan_draft(r.project_id);
  if exists (select 1 from public.pm_items where phase_id = p_id) then
    raise exception 'انقل بنود المرحلة إلى مرحلة أخرى أو احذفها أولاً' using errcode = '22023';
  end if;
  delete from public.pm_phases where id = p_id;
  perform public.pm_after_change(r.project_id);
  perform public.write_audit('pm.phase_delete', r.project_id, null, jsonb_build_object('name', r.name));
end;
$$;

-- ---------------------------------------------------------------------
-- 4. البرنامج المبدئي من المقايسات المعتمدة
-- ---------------------------------------------------------------------
-- بنود المقايسات المعتمدة للعقد مقسومة إلى مراحل بمددها المقترحة:
--   المرحلة = قسم اللائحة الأعلى (بترتيب فصول اللائحة ثم رقم القسم)، والبنود الحرة في «بنود أخرى» آخراً
--   مدة المرحلة = max(3, round(المدة الإجمالية × قيمة المرحلة ÷ قيمة المقايسة))، وبعدد البنود إن كانت القيم كلها صفراً
--   مدة البند = max(1, round(مدة مرحلته × √(قيمة البند ÷ أكبر بند في المرحلة)))، ومدة مرحلته إن كانت قيمها صفراً
create or replace function public.pm_gen_plan(p_project uuid, p_total_days integer)
returns table (pkey text, pname text, porder bigint, pdays integer, pcost numeric, sheet uuid, idx integer, pseq integer,
               code text, title text, unit text, qty numeric, cost numeric, idays integer, lorder bigint)
language sql stable security definer set search_path = public
as $$
  with l0 as (
    select s.id as sheet, l.ord::integer as idx, nullif(l.x ->> 'seq', '')::integer as pseq, coalesce(l.x ->> 'code', '') as code,
           coalesce(l.x ->> 'desc', '') as descr, coalesce(l.x ->> 'unit', '') as unit, nullif(l.x ->> 'qty', '')::numeric as qty,
           coalesce(nullif(l.x ->> 'qty', '')::numeric, 0) * coalesce(nullif(l.x ->> 'price', '')::numeric, 0) as cost,
           case when pi.seq is null then 'zz' else pi.chapter || ':' || split_part(pi.code, '.', 1) end as pkey,
           case when pi.seq is null or pi.section = '' then 'بنود أخرى'
                else left(btrim(regexp_replace(pi.section, '^[^:]{1,25}:-?\s*', '')), 120) end as pname,
           case when pi.seq is null then 999999999::bigint
                else coalesce((select o.n from jsonb_array_elements(pli.chapters) with ordinality o(c, n) where o.c ->> 'key' = pi.chapter), 99) * 100000
                     + coalesce(nullif(regexp_replace(split_part(pi.code, '.', 1), '\D', '', 'g'), '')::integer, 9999) end as porder,
           coalesce(pi.seq, 900000000 + l.ord::integer)::bigint as lorder
      from public.boq_sheets s
      cross join lateral jsonb_array_elements(s.lines) with ordinality l(x, ord)
      left join public.price_items pi on pi.list_id = s.list_id and pi.seq = nullif(l.x ->> 'seq', '')::integer
      left join public.price_lists pli on pli.id = s.list_id
     where s.project_id = p_project and s.status = 'approved'
  ), tot as (
    select sum(cost) as total, count(*) as n from l0
  ), ph as (
    select l0.pkey, min(l0.pname) as pname, min(l0.porder) as porder, sum(l0.cost) as pcost, max(l0.cost) as maxc,
           greatest(3, round(p_total_days * case when coalesce(tot.total, 0) > 0 then sum(l0.cost) / tot.total
                                                 else count(*)::numeric / tot.n end)::integer) as pdays
      from l0, tot group by l0.pkey, tot.total, tot.n
  )
  select ph.pkey, ph.pname, ph.porder, ph.pdays, ph.pcost, l0.sheet, l0.idx, l0.pseq, left(l0.code, 20),
         left(coalesce(nullif(btrim(regexp_replace(l0.descr, '^.* — ', '')), ''), l0.descr), 300), left(l0.unit, 20), l0.qty, l0.cost,
         case when coalesce(ph.maxc, 0) > 0 then greatest(1, round(ph.pdays * sqrt(l0.cost / ph.maxc))::integer) else ph.pdays end,
         l0.lorder
    from l0 join ph on ph.pkey = l0.pkey
   order by ph.porder, ph.pkey, l0.lorder, l0.idx
$$;

-- معاينة البرنامج المبدئي دون حفظه (للشؤون الفنية قبل التوليد)
create or replace function public.pm_plan_preview(p_project uuid, p_total_days integer)
returns jsonb
language plpgsql stable security definer set search_path = public
as $$
declare
  v jsonb;
begin
  if not public.is_member() then
    raise exception 'غير مصرح' using errcode = '42501';
  end if;
  if p_total_days is null or p_total_days < 7 or p_total_days > 3650 then
    raise exception 'المدة الإجمالية المقترحة بين 7 و3650 يوماً' using errcode = '22023';
  end if;
  select jsonb_build_object(
           'phases', coalesce(jsonb_agg(jsonb_build_object('name', x.pname, 'days', x.pdays, 'cost', x.pcost, 'items', x.items)
                                        order by x.porder, x.pkey), '[]'::jsonb),
           'total_days', coalesce(sum(x.pdays), 0), 'items', coalesce(sum(x.n), 0))
    into v
    from (select g.pkey, g.pname, g.porder, g.pdays, g.pcost, count(*) as n,
                 jsonb_agg(jsonb_build_object('code', g.code, 'title', g.title, 'days', g.idays, 'cost', g.cost, 'unit', g.unit, 'qty', g.qty)
                           order by g.lorder, g.idx) as items
            from public.pm_gen_plan(p_project, p_total_days) g
           group by g.pkey, g.pname, g.porder, g.pdays, g.pcost) x;
  return v;
end;
$$;

create or replace function public.pm_plan_generate(p_project uuid, p_start date, p_total_days integer, p_replace boolean default false)
returns jsonb
language plpgsql security definer set search_path = public
as $$
declare
  pl      public.pm_plans;
  g       record;
  v_key   text := null;
  v_phase uuid;
  v_sort  integer;
  v_psort integer;
  v_items integer := 0;
  v_phs   integer := 0;
  v_end   date;
begin
  if not public.can_prepare_plan(p_project) then
    raise exception 'إعداد البرنامج الزمني من اختصاص الشؤون الفنية' using errcode = '42501';
  end if;
  if p_total_days is null or p_total_days < 7 or p_total_days > 3650 then
    raise exception 'المدة الإجمالية المقترحة بين 7 و3650 يوماً' using errcode = '22023';
  end if;
  pl := public.pm_plan_draft(p_project);
  if not exists (select 1 from public.boq_sheets where project_id = p_project and status = 'approved') then
    raise exception 'لا مقايسة معتمدة لهذا العقد؛ تعتمدها الشؤون الفنية أولاً' using errcode = '22023';
  end if;
  if exists (select 1 from public.pm_items where project_id = p_project and source = 'boq') then
    if not coalesce(p_replace, false) then
      raise exception 'البرنامج يحوي بنود المقايسة؛ اختر الاستبدال لإعادة التوليد' using errcode = '22023';
    end if;
    delete from public.pm_items where project_id = p_project and source = 'boq';
    delete from public.pm_phases ph0 where ph0.project_id = p_project
       and not exists (select 1 from public.pm_items i where i.phase_id = ph0.id);
  end if;
  update public.pm_plans set start_date = coalesce(p_start, start_date), updated_at = now(), updated_by = auth.uid()
   where id = pl.id;
  select * into pl from public.pm_plans where id = pl.id;
  select coalesce(max(sort), 0) into v_psort from public.pm_phases where project_id = p_project;
  select coalesce(max(sort), 0) into v_sort from public.pm_items where project_id = p_project;

  for g in select * from public.pm_gen_plan(p_project, p_total_days) loop
    if v_key is distinct from g.pkey then
      v_key := g.pkey;
      v_psort := v_psort + 10;
      insert into public.pm_phases (project_id, sort, name, lag_days, created_by, updated_by)
      values (p_project, v_psort, g.pname, 0, auth.uid(), auth.uid())
      returning id into v_phase;
      v_phs := v_phs + 1;
    end if;
    v_sort := v_sort + 10;
    insert into public.pm_items (project_id, sort, code, title, planned_start, planned_end, weight, phase_id, duration_days,
                                 offset_days, source, boq_sheet_id, boq_line, price_seq, unit, qty, created_by, updated_by)
    values (p_project, v_sort, g.code, g.title, pl.start_date, pl.start_date, nullif(round(g.cost, 3), 0), v_phase, g.idays,
            0, 'boq', g.sheet, g.idx, g.pseq, g.unit, g.qty, auth.uid(), auth.uid());
    v_items := v_items + 1;
  end loop;

  perform public.pm_after_change(p_project);
  select max(planned_end) into v_end from public.pm_items where project_id = p_project;
  perform public.write_audit('pm.plan_generate', p_project, null,
    jsonb_build_object('phases', v_phs, 'items', v_items, 'total_days', v_end - pl.start_date, 'requested_days', p_total_days,
                       'start_date', pl.start_date));
  return jsonb_build_object('phases', v_phs, 'items', v_items, 'total_days', v_end - pl.start_date);
end;
$$;

-- ---------------------------------------------------------------------
-- 5. الاعتماد والإحالة إلى الإشراف، وإعادة الفتح
-- ---------------------------------------------------------------------
create or replace function public.pm_plan_set_status(p_project uuid, p_status text)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  pl  public.pm_plans;
  v_n integer;
  v_e date;
  u   record;
begin
  if not public.can_approve_plan(p_project) then
    raise exception 'اعتماد البرنامج الزمني وإعادة فتحه لرئيس الشؤون الفنية ومدير المكتب' using errcode = '42501';
  end if;
  select * into pl from public.pm_plans where project_id = p_project for update;
  if not found then
    raise exception 'لا برنامج زمني لهذا العقد بعد' using errcode = '22023';
  end if;
  if p_status = 'approved' then
    if pl.status = 'approved' then
      return;
    end if;
    perform public.pm_plan_recalc(p_project);
    select count(*), max(planned_end) into v_n, v_e from public.pm_items where project_id = p_project;
    if v_n = 0 then
      raise exception 'البرنامج بلا بنود' using errcode = '22023';
    end if;
    update public.pm_plans set status = 'approved', version = version + 1, approved_at = now(), approved_by = auth.uid(),
                               updated_at = now(), updated_by = auth.uid()
     where id = pl.id;
    perform public.write_audit('pm.plan_approve', p_project, null,
      jsonb_build_object('version', pl.version + 1, 'items', v_n, 'start_date', pl.start_date, 'end_date', v_e,
                         'total_days', v_e - pl.start_date));
    for u in select pr.id from public.profiles pr join public.projects p on p.id = p_project
              where pr.active and pr.role::text = 'dept_head' and pr.department = p.department and pr.id <> coalesce(auth.uid(), pr.id) loop
      perform public.notify_user(u.id, 'plan', 'أُحيل إليكم برنامج زمني معتمد',
        public.project_label(p_project) || ': ' || v_n || ' بنداً من ' || to_char(pl.start_date, 'YYYY/MM/DD') || ' إلى ' || to_char(v_e, 'YYYY/MM/DD'),
        p_project);
    end loop;
  elsif p_status = 'draft' then
    if pl.status = 'draft' then
      return;
    end if;
    update public.pm_plans set status = 'draft', updated_at = now(), updated_by = auth.uid() where id = pl.id;
    perform public.write_audit('pm.plan_reopen', p_project, null, jsonb_build_object('version', pl.version));
  else
    raise exception 'حالة غير معروفة' using errcode = '22023';
  end if;
  perform public.pm_after_change(p_project);
end;
$$;

-- ---------------------------------------------------------------------
-- 6. الدمج: البرنامج ومراحله تتبع العقد (البرنامج ينتقل إن لم يكن للعقد المدموج فيه برنامج)
-- ---------------------------------------------------------------------
create or replace function public.pm_plans_follow_merge()
returns trigger
language plpgsql security definer set search_path = public
as $$
begin
  if new.merged_into is not null and old.merged_into is null then
    update public.pm_phases set project_id = new.merged_into, origin_project = coalesce(origin_project, new.id)
     where project_id = new.id;
    if not exists (select 1 from public.pm_plans where project_id = new.merged_into) then
      update public.pm_plans set project_id = new.merged_into, origin_project = coalesce(origin_project, new.id)
       where project_id = new.id;
    end if;
  elsif new.merged_into is null and old.merged_into is not null then
    update public.pm_phases set project_id = new.id, origin_project = null
     where project_id = old.merged_into and origin_project = new.id;
    update public.pm_plans set project_id = new.id, origin_project = null
     where project_id = old.merged_into and origin_project = new.id;
  end if;
  return null;
end;
$$;
drop trigger if exists projects_pm_plans_follow_merge on public.projects;
create trigger projects_pm_plans_follow_merge
  after update of merged_into on public.projects
  for each row when (old.merged_into is distinct from new.merged_into)
  execute function public.pm_plans_follow_merge();

-- ---------------------------------------------------------------------
-- 7. الصلاحيات
-- ---------------------------------------------------------------------
do $$
declare
  t text;
begin
  foreach t in array array['pm_plans', 'pm_phases'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('drop policy if exists %I on public.%I', t || '_read', t);
    execute format('create policy %I on public.%I for select to authenticated using ((select public.is_member()))', t || '_read', t);
    execute format('revoke all on public.%I from anon', t);
    execute format('revoke insert, update, delete, truncate on public.%I from authenticated', t);
    execute format('grant select on public.%I to authenticated', t);
    execute format('grant all on public.%I to service_role', t);
    if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = t) then
      execute format('alter publication supabase_realtime add table public.%I', t);
    end if;
  end loop;
end $$;

revoke execute on function public.pm_plan_recalc(uuid), public.pm_after_change(uuid), public.pm_plan_draft(uuid),
  public.pm_gen_plan(uuid, integer),
  public.pm_plans_follow_merge(), public.boq_sheets_lock(), public.pm_item_rank(uuid),
  public.pm_boq_duplicate(uuid, integer, text, uuid) from public, anon, authenticated;
revoke execute on function public.is_dept_head_of(text), public.can_prepare_plan(uuid), public.can_approve_plan(uuid),
  public.can_track_plan(uuid), public.approve_boq(uuid, boolean), public.save_pm_plan(uuid, jsonb),
  public.save_pm_phase(uuid, jsonb), public.delete_pm_phase(uuid), public.pm_plan_generate(uuid, date, integer, boolean),
  public.pm_plan_set_status(uuid, text), public.pm_plan_preview(uuid, integer) from public, anon;
grant execute on function public.is_dept_head_of(text), public.can_prepare_plan(uuid), public.can_approve_plan(uuid),
  public.can_track_plan(uuid), public.approve_boq(uuid, boolean), public.save_pm_plan(uuid, jsonb),
  public.save_pm_phase(uuid, jsonb), public.delete_pm_phase(uuid), public.pm_plan_generate(uuid, date, integer, boolean),
  public.pm_plan_set_status(uuid, text), public.pm_plan_preview(uuid, integer) to authenticated;

-- أسماء الحالات كما في دليل التنفيذ المعتمد، إن كانت ما تزال بالأسماء الافتراضية السابقة
update public.app_settings
   set value = '{"done": "تم", "wip": "قيد التنفيذ", "todo": "لم يتم", "na": "لا ينطبق"}'::jsonb
 where key = 'ui.status_labels'
   and value = '{"done": "مكتمل", "wip": "قيد الإجراء", "todo": "لم يتم", "na": "لا ينطبق"}'::jsonb;
