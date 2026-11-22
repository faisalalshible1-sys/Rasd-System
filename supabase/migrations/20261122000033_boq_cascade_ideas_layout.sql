-- =====================================================================
-- الترحيل 33: حذف المقايسة يحذف بنودها من البرنامج الزمني ومتابعة الإشراف، والأفكار مربوطة بالقسم والصفحة،
-- وتخصيص الواجهة الموسّع من حساب المدير.
--
--   1. delete_boq: يحذف مع المقايسة بنود البرنامج الزمني المأخوذة منها، والمراحل التي فرغت بحذفها، ومسودة البرنامج
--      ومراحلها إن لم يبقَ فيها بند، ثم يعيد حساب البرنامج وترجمته إلى المخاطر وSWOT، ويسجّل الأعداد في سجل التدقيق.
--      يُرفض الحذف إن كانت المقايسة معتمدة أو كان البرنامج المعتمد مبنياً عليها (يُعاد فتحهما أولاً).
--      pm_items.boq_sheet_id صار on delete cascade فلا يبقى بند بلا مقايسته، ويُنظَّف ما بقي من حذف سابق.
--   2. الأفكار: القسم (section) والصفحة (page_id وpage_label) التي كُتبت منها؛ submit_idea يقبلهما،
--      وmove_idea للمدير لنقل الفكرة إلى قسم أو صفحة أخرى.
--   3. ui.layout: مجموعات الأقسام، ونمط عرض شاشة الدخول، وأيقونة القسم ولونه ومجموعته، وأيقونة الصفحة ونقلها إلى قسم آخر.
--
-- يُشغَّل مرتين دون ضرر.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. حذف المقايسة وبنودها
-- ---------------------------------------------------------------------

-- لا يبقى بند بلا مقايسته (كان on delete set null)
do $$
declare
  c text;
  t "char";
begin
  select con.conname, con.confdeltype into c, t
    from pg_constraint con
    join pg_attribute a on a.attrelid = con.conrelid and a.attnum = any (con.conkey)
   where con.conrelid = 'public.pm_items'::regclass and con.contype = 'f' and a.attname = 'boq_sheet_id';
  if c is not null and t <> 'c' then
    execute format('alter table public.pm_items drop constraint %I', c);
    c := null;
  end if;
  if c is null then
    alter table public.pm_items add constraint pm_items_boq_sheet_id_fkey
      foreign key (boq_sheet_id) references public.boq_sheets (id) on delete cascade;
  end if;
end $$;

-- حذف بنود من البرامج الزمنية (داخلية): المراحل التي فرغت بحذفها، ومسودة البرنامج ومراحلها إن لم يبقَ فيها بند،
-- ثم إعادة الحساب والترجمة لكل عقد. تعيد الأعداد.
create or replace function public.pm_remove_items(p_ids uuid[])
returns jsonb
language plpgsql security definer set search_path = public
as $$
declare
  v_items    integer := 0;
  v_tracked  integer := 0;
  v_phases   integer := 0;
  v_plans    integer := 0;
  v_projects uuid[];
  v_phids    uuid[];
  p          uuid;
  n          integer;
begin
  select count(*),
         count(*) filter (where progress > 0 or actual_start is not null or actual_end is not null),
         array_agg(distinct project_id),
         array_agg(distinct phase_id) filter (where phase_id is not null)
    into v_items, v_tracked, v_projects, v_phids
    from public.pm_items where id = any (coalesce(p_ids, '{}'::uuid[]));
  if v_items = 0 then
    return jsonb_build_object('items', 0, 'tracked', 0, 'phases', 0, 'plans', 0);
  end if;
  delete from public.pm_items where id = any (p_ids);
  delete from public.pm_phases ph
   where ph.id = any (coalesce(v_phids, '{}'::uuid[]))
     and not exists (select 1 from public.pm_items i where i.phase_id = ph.id);
  get diagnostics v_phases = row_count;
  foreach p in array v_projects loop
    if not exists (select 1 from public.pm_items where project_id = p)
       and exists (select 1 from public.pm_plans where project_id = p and status = 'draft') then
      delete from public.pm_phases where project_id = p;
      get diagnostics n = row_count;
      v_phases := v_phases + n;
      delete from public.pm_plans where project_id = p and status = 'draft';
      v_plans := v_plans + 1;
    end if;
    perform public.pm_after_change(p);
  end loop;
  return jsonb_build_object('items', v_items, 'tracked', v_tracked, 'phases', v_phases, 'plans', v_plans);
end;
$$;

-- حذف مقايسة: المدير، أو من أعدّها ما دامت له صلاحية المقايسات. تُحذف معها بنودها في البرنامج الزمني والإشراف.
drop function if exists public.delete_boq(uuid);
create function public.delete_boq(p_id uuid)
returns jsonb
language plpgsql security definer set search_path = public
as $$
declare
  r     public.boq_sheets;
  v_ids uuid[];
  v_res jsonb;
begin
  select * into r from public.boq_sheets where id = p_id for update;
  if not found then
    raise exception 'المقايسة غير موجودة' using errcode = 'P0002';
  end if;
  if not (public.is_director() or (r.created_by = auth.uid() and public.doc_can_edit('boq', r.project_id))) then
    raise exception 'حذف المقايسة لمن أعدّها أو لمدير المكتب' using errcode = '42501';
  end if;
  if r.status = 'approved' then
    raise exception 'المقايسة معتمدة؛ يعيد فتحها رئيس الشؤون الفنية أو المدير قبل حذفها' using errcode = '42501';
  end if;
  if exists (select 1 from public.pm_items i join public.pm_plans pl on pl.project_id = i.project_id
              where i.boq_sheet_id = p_id and pl.status = 'approved') then
    raise exception 'البرنامج الزمني المعتمد مبني على هذه المقايسة؛ يعيد فتحه رئيس الشؤون الفنية أو المدير قبل حذفها'
      using errcode = '22023';
  end if;
  select array_agg(id) into v_ids from public.pm_items where boq_sheet_id = p_id;
  v_res := public.pm_remove_items(v_ids);
  delete from public.boq_sheets where id = p_id;
  perform public.write_audit('boq.delete', r.project_id, null,
    jsonb_build_object('title', r.title, 'lines', r.line_count, 'total', r.total,
                       'plan_items', v_res -> 'items', 'tracked_items', v_res -> 'tracked',
                       'phases', v_res -> 'phases', 'plan_removed', (v_res ->> 'plans')::integer > 0));
  return v_res;
end;
$$;

-- ما بقي من حذف سابق: بنود مأخوذة من مقايسة لم تعد موجودة، في برامج غير معتمدة
do $$
declare
  r     record;
  v_res jsonb;
begin
  for r in select i.project_id, array_agg(i.id) as ids
             from public.pm_items i
             left join public.pm_plans pl on pl.project_id = i.project_id
            where i.source = 'boq' and i.boq_sheet_id is null and coalesce(pl.status, 'draft') = 'draft'
            group by i.project_id loop
    v_res := public.pm_remove_items(r.ids);
    perform public.write_audit('pm.boq_orphans', r.project_id, null, v_res);
  end loop;
end $$;

-- ---------------------------------------------------------------------
-- 2. الأفكار مربوطة بالقسم والصفحة
-- ---------------------------------------------------------------------
alter table public.ideas add column if not exists section text;
alter table public.ideas add column if not exists page_id integer;
alter table public.ideas add column if not exists page_label text not null default '';

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'ideas_section_check' and conrelid = 'public.ideas'::regclass) then
    alter table public.ideas add constraint ideas_section_check check (section is null or section in (
      'cycle', 'risks', 'swot', 'docs', 'supervision', 'heritage', 'planning_qa', 'safety', 'acceptance',
      'chat', 'security', 'print', 'manual'));
  end if;
  if not exists (select 1 from pg_constraint where conname = 'ideas_page_check' and conrelid = 'public.ideas'::regclass) then
    alter table public.ideas add constraint ideas_page_check
      check ((page_id is null or page_id between 0 and 999) and length(page_label) <= 60);
  end if;
end $$;
create index if not exists ideas_section_idx on public.ideas (section, status);

-- أقسام المنظومة كما في التطبيق (lib/screens/hub.dart)
create or replace function public.app_section_ok(p_key text)
returns boolean
language sql immutable
as $$
  select p_key in ('cycle', 'risks', 'swot', 'docs', 'supervision', 'heritage', 'planning_qa', 'safety', 'acceptance',
                   'chat', 'security', 'print', 'manual')
$$;

drop function if exists public.submit_idea(text, text, text, text);
create or replace function public.submit_idea(p_title text, p_body text, p_category text, p_priority text,
                                              p_section text default null, p_page integer default null,
                                              p_page_label text default null)
returns uuid
language plpgsql security definer set search_path = public
as $$
declare
  v_id    uuid;
  v_label text := left(btrim(coalesce(p_page_label, '')), 60);
begin
  if not public.is_member() then
    raise exception 'حسابك غير مفعّل' using errcode = '42501';
  end if;
  if not public.is_director() and not coalesce((public.setting('ui.features') ->> 'ideas_for_all')::boolean, true) then
    raise exception 'إرسال الأفكار متاح لمدير المكتب حالياً' using errcode = '42501';
  end if;
  if p_section is not null and not public.app_section_ok(p_section) then
    raise exception 'قسم غير معروف' using errcode = '22023';
  end if;
  if p_page is not null and (p_page < 0 or p_page > 999 or p_section is null) then
    raise exception 'صفحة غير معروفة' using errcode = '22023';
  end if;
  insert into public.ideas (title, body, category, priority, created_by, section, page_id, page_label)
  values (btrim(p_title), coalesce(p_body, ''), coalesce(p_category, 'feature'), coalesce(p_priority, 'normal'), auth.uid(),
          p_section, case when p_section is null then null else p_page end,
          case when p_section is null or p_page is null then '' else v_label end)
  returning id into v_id;
  perform public.write_audit('idea.create', null, null,
    jsonb_build_object('idea_id', v_id, 'title', btrim(p_title), 'section', p_section, 'page', nullif(v_label, '')), btrim(p_title));
  if not public.is_director() then
    perform public.notify_director('idea', 'فكرة جديدة: ' || btrim(p_title),
      public.actor_name(auth.uid()) || case when v_label <> '' and p_page is not null then ' · ' || v_label else '' end);
  end if;
  return v_id;
end;
$$;

-- نقل الفكرة إلى قسم أو صفحة (المدير): القسم الفارغ يجعلها عامة، والصفحة الفارغة تجعلها للقسم كله
create or replace function public.move_idea(p_id uuid, p_section text, p_page integer, p_page_label text)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  i       public.ideas;
  v_label text := left(btrim(coalesce(p_page_label, '')), 60);
begin
  if not public.is_director() then
    raise exception 'إدارة الأفكار من صلاحية مدير المكتب وحده' using errcode = '42501';
  end if;
  select * into i from public.ideas where id = p_id for update;
  if not found then
    raise exception 'الفكرة غير موجودة' using errcode = '22023';
  end if;
  if p_section is not null and not public.app_section_ok(p_section) then
    raise exception 'قسم غير معروف' using errcode = '22023';
  end if;
  if p_page is not null and (p_page < 0 or p_page > 999 or p_section is null) then
    raise exception 'صفحة غير معروفة' using errcode = '22023';
  end if;
  if (i.section, i.page_id) is not distinct from (p_section, case when p_section is null then null else p_page end) then
    return;
  end if;
  update public.ideas
     set section = p_section,
         page_id = case when p_section is null then null else p_page end,
         page_label = case when p_section is null or p_page is null then '' else v_label end,
         updated_at = now()
   where id = p_id;
  perform public.write_audit('idea.move', null, null,
    jsonb_build_object('idea_id', p_id,
                       'from', jsonb_build_object('section', i.section, 'page', nullif(i.page_label, '')),
                       'to', jsonb_build_object('section', p_section, 'page', nullif(v_label, ''))), i.title);
end;
$$;

-- ---------------------------------------------------------------------
-- 3. تخصيص الواجهة الموسّع (ui.layout)
--   {"groups": [{"key": "g1", "name": "..."}], "hub_style": "cards" | "compact" | "icons",
--    "sections": {"<قسم>": {"name", "desc", "hidden", "icon", "color", "group"}}, "section_order": [...],
--    "pages": {"<رقم>": {"label", "hidden", "icon", "section"}}, "page_order": {"<قسم>": [...]}}
--   الصفحة تُنقل إلى قسم آخر بـ section، عدا صفحات الأمن السيبراني (150–169) فلا تُنقل ولا يُنقل إليها.
-- ---------------------------------------------------------------------
do $$
begin
  if not exists (select 1 from pg_proc where proname = 'set_setting_v33' and pronamespace = 'public'::regnamespace) then
    alter function public.set_setting(text, jsonb) rename to set_setting_v33;
  end if;
end $$;

create or replace function public.set_setting(p_key text, p_value jsonb)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  v_bad boolean := false;
  g     jsonb;
  e     record;
begin
  -- التحقق الأساسي (الشكل والأطوال والصلاحية) في السلسلة السابقة؛ هنا الحقول الجديدة وحدها
  if p_key = 'ui.layout' and public.is_director() and jsonb_typeof(p_value) = 'object' then
    if p_value ? 'groups' then
      if jsonb_typeof(p_value -> 'groups') <> 'array' or jsonb_array_length(p_value -> 'groups') > 12 then
        v_bad := true;
      else
        for g in select x from jsonb_array_elements(p_value -> 'groups') x loop
          if jsonb_typeof(g) <> 'object' or coalesce(g ->> 'key', '') !~ '^g[a-z0-9]{1,12}$'
             or length(btrim(coalesce(g ->> 'name', ''))) not between 1 and 40 then
            v_bad := true;
          end if;
        end loop;
        if (select count(distinct x ->> 'key') from jsonb_array_elements(p_value -> 'groups') x)
           <> jsonb_array_length(p_value -> 'groups') then
          v_bad := true;
        end if;
      end if;
    end if;
    if p_value ? 'hub_style' and coalesce(p_value ->> 'hub_style', '') not in ('cards', 'compact', 'icons') then
      v_bad := true;
    end if;
    if jsonb_typeof(p_value -> 'sections') = 'object' then
      for e in select k, v from jsonb_each(p_value -> 'sections') s(k, v) loop
        if not public.app_section_ok(e.k) then
          v_bad := true;
        elsif jsonb_typeof(e.v) = 'object'
              and ((e.v ? 'icon' and coalesce(e.v ->> 'icon', '') !~ '^[a-z0-9_]{1,40}$')
                   or (e.v ? 'color' and coalesce(e.v ->> 'color', '') !~ '^[a-z0-9_]{1,20}$')
                   or (e.v ? 'group' and coalesce(e.v ->> 'group', '') !~ '^g[a-z0-9]{1,12}$')) then
          v_bad := true;
        end if;
      end loop;
    end if;
    if jsonb_typeof(p_value -> 'pages') = 'object' then
      for e in select k, v from jsonb_each(p_value -> 'pages') s(k, v) loop
        if jsonb_typeof(e.v) <> 'object' then
          continue;
        end if;
        if e.v ? 'icon' and coalesce(e.v ->> 'icon', '') !~ '^[a-z0-9_]{1,40}$' then
          v_bad := true;
        end if;
        if e.v ? 'section' then
          if not public.app_section_ok(coalesce(e.v ->> 'section', '')) or e.v ->> 'section' = 'security' then
            v_bad := true;
          elsif e.k ~ '^\d{1,4}$' then
            if e.k::integer between 150 and 169 then
              v_bad := true;
            end if;
          end if;
        end if;
      end loop;
    end if;
    if v_bad then
      raise exception 'قيمة غير صالحة للإعداد %', p_key using errcode = '22023';
    end if;
  end if;
  perform public.set_setting_v33(p_key, p_value);
end;
$$;

-- ---------------------------------------------------------------------
-- 4. الصلاحيات على الدوال
-- ---------------------------------------------------------------------
revoke execute on function public.pm_remove_items(uuid[]), public.set_setting_v33(text, jsonb) from public, anon, authenticated;
revoke execute on function
  public.delete_boq(uuid), public.submit_idea(text, text, text, text, text, integer, text),
  public.move_idea(uuid, text, integer, text), public.set_setting(text, jsonb), public.app_section_ok(text)
from public, anon;
grant execute on function
  public.delete_boq(uuid), public.submit_idea(text, text, text, text, text, integer, text),
  public.move_idea(uuid, text, integer, text), public.set_setting(text, jsonb), public.app_section_ok(text)
to authenticated;
