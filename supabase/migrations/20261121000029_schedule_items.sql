-- =====================================================================
--  الترحيل 29: بنود الجدول الزمني لكل مشروع
--   pm_items: بنود البرنامج الزمني للعقد (من أعمال العقد أو تُضاف يدوياً) بتاريخي البداية والنهاية المخططين،
--   والوزن، ونسبة الإنجاز الفعلية (0–100)، وتاريخي البداية والنهاية الفعليين.
--   الحسابات (النسبة المخططة حتى تاريخ الإسناد، والانحراف بالنقاط وبالأيام، والنسبة الكلية الموزونة، وحالة المشروع)
--   تجري في التطبيق بالمعادلات المشروحة في الفصل 29 من الدليل.
--   الكتابة عبر دوال مدققة:
--     save_pm_item          : بيانات البند لمن يحدّث البرنامج الزمني (can_edit_schedule)، ونسبة الإنجاز والتواريخ الفعلية
--                             والملاحظات أيضاً لمن يحدّث سجل التقدم (can_edit_pm).
--     delete_pm_item / reorder_pm_items / pm_items_from_works : لمن يحدّث البرنامج الزمني.
--   البنود تتبع العقد عند الدمج وتعود بفكّه. القراءة لكل الأعضاء.
--  يُشغَّل بعد 20261121000028_price_list_2026.sql. إعادة تشغيله آمنة.
-- =====================================================================

create table if not exists public.pm_items (
  id             uuid primary key default gen_random_uuid(),
  project_id     uuid not null references public.projects (id) on delete cascade,
  origin_project uuid references public.projects (id) on delete set null,
  work_id        uuid references public.contract_works (id) on delete set null,
  sort           integer not null default 0,
  code           text not null default '' check (length(code) <= 20),
  title          text not null check (length(btrim(title)) between 2 and 300),
  planned_start  date not null,
  planned_end    date not null,
  weight         numeric(14, 3) check (weight > 0),
  progress       numeric(5, 2) not null default 0 check (progress between 0 and 100),
  actual_start   date,
  actual_end     date,
  notes          text not null default '' check (length(notes) <= 1000),
  created_at     timestamptz not null default now(),
  created_by     uuid references public.profiles (id) on delete set null,
  updated_at     timestamptz not null default now(),
  updated_by     uuid references public.profiles (id) on delete set null,
  check (planned_end >= planned_start),
  check (actual_end is null or actual_start is null or actual_end >= actual_start)
);
create index if not exists pm_items_project_idx    on public.pm_items (project_id, sort);
create index if not exists pm_items_origin_idx     on public.pm_items (origin_project);
create index if not exists pm_items_work_idx       on public.pm_items (work_id);
create index if not exists pm_items_created_by_idx on public.pm_items (created_by);
create index if not exists pm_items_updated_by_idx on public.pm_items (updated_by);

-- حفظ بند (جديد أو تعديل)
create or replace function public.save_pm_item(p_id uuid, p_data jsonb)
returns uuid
language plpgsql security definer set search_path = public
as $$
declare
  old_row public.pm_items;
  new_row public.pm_items;
  v_proj  uuid;
  v_struct boolean;
  v_title text := public.jtext(p_data, 'title', 300, 'اسم البند');
  v_code  text := public.jtext(p_data, 'code', 20, 'رقم البند');
  v_ps    date := public.jdate(p_data, 'planned_start', 'البداية المخططة');
  v_pe    date := public.jdate(p_data, 'planned_end', 'النهاية المخططة');
  v_w     numeric := public.jnum(p_data, 'weight', 0.001, 1e11, 'الوزن');
  v_pr    numeric := coalesce(public.jnum(p_data, 'progress', 0, 100, 'نسبة الإنجاز'), 0);
  v_as    date := public.jdate(p_data, 'actual_start', 'البداية الفعلية');
  v_ae    date := public.jdate(p_data, 'actual_end', 'النهاية الفعلية');
  v_notes text := public.jtext(p_data, 'notes', 1000, 'ملاحظات');
  v_work  uuid;
  v_sort  integer := public.jint(p_data, 'sort', 0, 1000000, 'الترتيب');
begin
  if jsonb_typeof(coalesce(p_data, 'null'::jsonb)) <> 'object' then
    raise exception 'بيانات غير صالحة' using errcode = '22023';
  end if;
  if p_id is not null then
    select * into old_row from public.pm_items where id = p_id for update;
    if not found then
      raise exception 'البند غير موجود' using errcode = 'P0002';
    end if;
    v_proj := old_row.project_id;
  else
    v_proj := public.jproject(p_data, 'project_id', true);
  end if;
  v_struct := public.can_edit_schedule(v_proj);
  if not v_struct and not (p_id is not null and public.can_edit_pm()) then
    raise exception 'بنود البرنامج الزمني يحدّثها مكتب المدير ومكتب العقود والقسم المشرف على العقد' using errcode = '42501';
  end if;
  begin
    v_work := nullif(btrim(coalesce(p_data ->> 'work_id', '')), '')::uuid;
  exception when others then
    raise exception 'عمل العقد غير صالح' using errcode = '22023';
  end;
  if v_work is not null and not exists (select 1 from public.contract_works where id = v_work and project_id = v_proj) then
    raise exception 'عمل العقد المختار ليس من أعمال هذا العقد' using errcode = '22023';
  end if;
  if length(v_title) < 2 then
    raise exception 'أدخل اسم البند' using errcode = '22023';
  end if;
  if v_ps is null or v_pe is null then
    raise exception 'حدّد البداية والنهاية المخططتين للبند' using errcode = '22023';
  end if;
  if v_pe < v_ps then
    raise exception 'النهاية المخططة قبل البداية المخططة' using errcode = '22023';
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

  if p_id is null then
    insert into public.pm_items (project_id, work_id, sort, code, title, planned_start, planned_end, weight, progress,
                                 actual_start, actual_end, notes, created_by, updated_by)
    values (v_proj, v_work,
            coalesce(v_sort, (select coalesce(max(sort), 0) + 10 from public.pm_items where project_id = v_proj)),
            v_code, v_title, v_ps, v_pe, v_w, round(v_pr, 2), v_as, v_ae, v_notes, auth.uid(), auth.uid())
    returning * into new_row;
    perform public.write_audit('pm.item_add', v_proj, null,
      jsonb_build_object('title', v_title, 'planned_start', v_ps, 'planned_end', v_pe, 'weight', v_w, 'progress', new_row.progress));
  else
    -- من يحدّث سجل التقدم وحده يغيّر الإنجاز والتواريخ الفعلية والملاحظات، لا بيانات البند
    if not v_struct and (v_title <> old_row.title or v_code <> old_row.code or v_ps <> old_row.planned_start
                         or v_pe <> old_row.planned_end or v_w is distinct from old_row.weight
                         or v_work is distinct from old_row.work_id
                         or (v_sort is not null and v_sort <> old_row.sort)) then
      raise exception 'تعديل اسم البند وتواريخه المخططة ووزنه لمن يحدّث البرنامج الزمني؛ يمكنك تحديث الإنجاز والتواريخ الفعلية'
        using errcode = '42501';
    end if;
    update public.pm_items set
      work_id = v_work, sort = coalesce(v_sort, old_row.sort), code = v_code, title = v_title,
      planned_start = v_ps, planned_end = v_pe, weight = v_w, progress = round(v_pr, 2),
      actual_start = v_as, actual_end = v_ae, notes = v_notes, updated_at = now(), updated_by = auth.uid()
    where id = p_id
    returning * into new_row;
    if to_jsonb(new_row) - array['updated_at', 'updated_by'] <> to_jsonb(old_row) - array['updated_at', 'updated_by'] then
      perform public.write_audit('pm.item_update', v_proj, null,
        jsonb_build_object('title', v_title,
                           'changes', public.jsonb_changes(to_jsonb(old_row), to_jsonb(new_row), array['updated_at', 'updated_by'])));
    end if;
  end if;
  return new_row.id;
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
  if not public.can_edit_schedule(r.project_id) then
    raise exception 'حذف بنود البرنامج الزمني لمن يحدّث البرنامج الزمني' using errcode = '42501';
  end if;
  delete from public.pm_items where id = p_id;
  perform public.write_audit('pm.item_delete', r.project_id, null,
    jsonb_build_object('title', r.title, 'planned_start', r.planned_start, 'planned_end', r.planned_end, 'progress', r.progress));
end;
$$;

-- ترتيب البنود كما في القائمة المرسلة (كل بنود العقد)
create or replace function public.reorder_pm_items(p_project uuid, p_ids uuid[])
returns void
language plpgsql security definer set search_path = public
as $$
begin
  if not public.can_edit_schedule(p_project) then
    raise exception 'ترتيب البنود لمن يحدّث البرنامج الزمني' using errcode = '42501';
  end if;
  if coalesce(array_length(p_ids, 1), 0) <> (select count(*) from public.pm_items where project_id = p_project)
     or exists (select 1 from unnest(p_ids) x where not exists (select 1 from public.pm_items where id = x and project_id = p_project))
     or (select count(distinct x) from unnest(p_ids) x) <> coalesce(array_length(p_ids, 1), 0) then
    raise exception 'قائمة البنود لا تطابق بنود العقد' using errcode = '22023';
  end if;
  update public.pm_items i set sort = o.n * 10, updated_at = now(), updated_by = auth.uid()
    from unnest(p_ids) with ordinality o(id, n)
   where i.id = o.id and i.sort <> o.n * 10;
  perform public.write_audit('pm.items_reorder', p_project, null, jsonb_build_object('items', array_length(p_ids, 1)));
end;
$$;

-- بند لكل عمل من أعمال العقد لم يُربط ببند بعد، بتاريخي البرنامج الزمني للعقد
create or replace function public.pm_items_from_works(p_project uuid)
returns integer
language plpgsql security definer set search_path = public
as $$
declare
  s public.pm_projects;
  n integer;
begin
  if not public.can_edit_schedule(p_project) then
    raise exception 'إنشاء البنود لمن يحدّث البرنامج الزمني' using errcode = '42501';
  end if;
  if not exists (select 1 from public.projects where id = p_project and merged_into is null) then
    raise exception 'العقد غير موجود' using errcode = '22023';
  end if;
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
    perform public.write_audit('pm.items_from_works', p_project, null, jsonb_build_object('items', n));
  end if;
  return n;
end;
$$;

-- البنود تتبع العقد عند الدمج وتعود بفكّه
create or replace function public.pm_items_follow_merge()
returns trigger
language plpgsql security definer set search_path = public
as $$
begin
  if new.merged_into is not null and old.merged_into is null then
    update public.pm_items set project_id = new.merged_into, origin_project = coalesce(origin_project, new.id)
     where project_id = new.id;
  elsif new.merged_into is null and old.merged_into is not null then
    update public.pm_items set project_id = new.id, origin_project = null
     where project_id = old.merged_into and origin_project = new.id;
  end if;
  return null;
end;
$$;
drop trigger if exists projects_pm_items_follow_merge on public.projects;
create trigger projects_pm_items_follow_merge
  after update of merged_into on public.projects
  for each row when (old.merged_into is distinct from new.merged_into)
  execute function public.pm_items_follow_merge();

do $$
begin
  alter table public.pm_items enable row level security;
  drop policy if exists pm_items_read on public.pm_items;
  create policy pm_items_read on public.pm_items for select to authenticated using ((select public.is_member()));
  revoke all on public.pm_items from anon;
  revoke insert, update, delete, truncate on public.pm_items from authenticated;
  grant select on public.pm_items to authenticated;
  grant all on public.pm_items to service_role;
  if not exists (select 1 from pg_publication_tables
                 where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'pm_items') then
    alter publication supabase_realtime add table public.pm_items;
  end if;
end $$;

revoke execute on function public.pm_items_follow_merge() from public, anon, authenticated;
revoke execute on function public.save_pm_item(uuid, jsonb), public.delete_pm_item(uuid), public.reorder_pm_items(uuid, uuid[]),
  public.pm_items_from_works(uuid) from public, anon;
grant execute on function public.save_pm_item(uuid, jsonb), public.delete_pm_item(uuid), public.reorder_pm_items(uuid, uuid[]),
  public.pm_items_from_works(uuid) to authenticated;
