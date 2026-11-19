-- =====================================================================
-- الترحيل 23: «منظومة رصد»، والصلاحيات الدقيقة، والرقم الإشاري الموسّع، وتخصيص الواجهة
--   • الاسم الجديد للمنظومة «منظومة رصد» (إن كان الاسم ما زال الافتراضي القديم).
--   • صلاحيات دقيقة: يمنح المدير مستخدماً صلاحية الكتابة في صفحة بعينها (سجل وحدة، مستندات فنية،
--     تقارير الإشراف، SWOT) أو في نموذج بعينه من نماذج الدورة المستندية، دون القسم كله.
--   • الرقم الإشاري: صيغ يبنيها المدير لكل نوع (المطبوعات، والمراسلات الصادرة والواردة والداخلية...)،
--     وتسلسل لا يتكرر تصونه قاعدة البيانات، يُصفَّر سنوياً أو شهرياً أو يومياً أو لا يُصفَّر، وسجل لكل رقم صدر.
--   • تخصيص الواجهة (ui.layout): أسماء الأقسام والصفحات وأوصافها وترتيبها وإخفاؤها.
-- يُشغَّل بعد الترحيلات 1–22، ويمكن إعادة تشغيله دون ضرر.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. الاسم الجديد
-- ---------------------------------------------------------------------
-- الأسماء السابقة كلها كانت تحوي «الدورة المستندية»؛ أي اسم آخر وضعه المدير يبقى كما هو
update public.app_settings set value = '"منظومة رصد"'::jsonb, updated_at = now()
 where key = 'brand.app_title' and value #>> '{}' like '%الدورة المستندية%';

-- ---------------------------------------------------------------------
-- 2. الصلاحيات الدقيقة
-- ---------------------------------------------------------------------
create table if not exists public.user_grants (
  user_id    uuid not null references public.profiles(id) on delete cascade,
  scope      text not null check (scope ~ '^(form:[a-z0-9_]{1,40}|docs:(boq|letter|design)|supervision:reports|unit:[a-z_]{2,40}|swot)$'),
  granted_by uuid references public.profiles(id) on delete set null,
  granted_at timestamptz not null default now(),
  primary key (user_id, scope)
);
create index if not exists user_grants_granted_by_idx on public.user_grants (granted_by);

-- هل لي صلاحية دقيقة على هذا النطاق؟
create or replace function public.has_grant(p_scope text)
returns boolean
language sql stable security definer set search_path = public
as $$
  select exists (select 1 from public.user_grants g join public.profiles me on me.id = g.user_id
                  where g.user_id = auth.uid() and g.scope = p_scope and me.active and me.role is not null
                    and me.role::text <> 'security_auditor'
                    and (me.locked_until is null or me.locked_until <= now()))
$$;

-- يحق للمدير منح أي نطاق صالح: النموذج موجود، ونوع السجل معروف
create or replace function public.grant_scope_ok(p_scope text)
returns boolean
language sql stable security definer set search_path = public
as $$
  select case
    when p_scope like 'form:%' then exists (select 1 from public.form_defs where key = substr(p_scope, 6))
    when p_scope like 'unit:%' then public.unit_kind_spec(substr(p_scope, 6)) is not null
    else p_scope in ('docs:boq', 'docs:letter', 'docs:design', 'supervision:reports', 'swot')
  end
$$;

-- يستبدل المدير صلاحيات المستخدم الدقيقة كلها بالقائمة المعطاة
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

alter table public.user_grants enable row level security;
drop policy if exists user_grants_read on public.user_grants;
create policy user_grants_read on public.user_grants for select to authenticated
  using ((select public.is_member()) and (user_id = (select auth.uid()) or (select public.is_director())
         or (select public.my_role())::text in ('office_staff', 'security_auditor')));
revoke all on public.user_grants from anon;
revoke insert, update, delete, truncate on public.user_grants from authenticated;
grant select on public.user_grants to authenticated;
grant all on public.user_grants to service_role;

-- الكتابة في سجلات الوحدات حسب النوع: صلاحية الوحدة كلها، أو صلاحية دقيقة على هذا النوع
create or replace function public.unit_kind_can_edit(p_kind text)
returns boolean
language sql stable security definer set search_path = public
as $$
  select coalesce(public.unit_can_edit(public.unit_kind_spec(p_kind) ->> 'unit'), false)
      or (public.writes_allowed() and public.unit_kind_spec(p_kind) is not null and public.has_grant('unit:' || p_kind))
$$;

-- الدوال الأصلية تبقى بأسماء محفوظة، والدوال الجديدة تضيف إليها الصلاحية الدقيقة
do $$
begin
  if not exists (select 1 from pg_proc where proname = 'doc_can_edit_v22' and pronamespace = 'public'::regnamespace) then
    alter function public.doc_can_edit(text, uuid) rename to doc_can_edit_v22;
  end if;
  if not exists (select 1 from pg_proc where proname = 'site_report_can_edit_v22' and pronamespace = 'public'::regnamespace) then
    alter function public.site_report_can_edit(uuid) rename to site_report_can_edit_v22;
  end if;
  if not exists (select 1 from pg_proc where proname = 'can_edit_form_v22' and pronamespace = 'public'::regnamespace) then
    alter function public.can_edit_form(uuid, text) rename to can_edit_form_v22;
  end if;
  if not exists (select 1 from pg_proc where proname = 'can_edit_swot_v22' and pronamespace = 'public'::regnamespace) then
    alter function public.can_edit_swot() rename to can_edit_swot_v22;
  end if;
end $$;

create or replace function public.doc_can_edit(p_kind text, p_project uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
  select coalesce(public.doc_can_edit_v22(p_kind, p_project), false)
      or (public.writes_allowed() and p_kind in ('boq', 'letter', 'design') and public.has_grant('docs:' || p_kind)
          and (p_project is null or exists (select 1 from public.projects where id = p_project and merged_into is null)))
$$;

create or replace function public.site_report_can_edit(p_project uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
  select coalesce(public.site_report_can_edit_v22(p_project), false)
      or (public.writes_allowed() and public.has_grant('supervision:reports')
          and exists (select 1 from public.projects where id = p_project and merged_into is null))
$$;

create or replace function public.can_edit_form(p_project uuid, p_form text)
returns boolean
language sql stable security definer set search_path = public
as $$
  select coalesce(public.can_edit_form_v22(p_project, p_form), false)
      or (public.writes_allowed() and public.has_grant('form:' || p_form)
          and exists (select 1 from public.form_defs where key = p_form and active)
          and exists (select 1 from public.projects where id = p_project))
$$;

create or replace function public.can_edit_swot()
returns boolean
language sql stable security definer set search_path = public
as $$
  select coalesce(public.can_edit_swot_v22(), false) or (public.writes_allowed() and public.has_grant('swot'))
$$;

create or replace function public.save_unit_record(p_id uuid, p_data jsonb)
returns uuid
language plpgsql security definer set search_path = public
as $$
declare
  old_row  public.unit_records;
  new_row  public.unit_records;
  par      public.unit_records;
  v_kind   text;
  v_spec   jsonb;
  v_unit   text;
  v_title  text := public.jtext(p_data, 'title', 200, 'العنوان');
  v_proj   uuid;
  v_parent uuid;
  v_status text;
  v_level  text;
  v_closed boolean;
  v_date   date := public.jdate(p_data, 'rec_date', 'التاريخ');
  v_due    date := public.jdate(p_data, 'due_date', 'الموعد');
  v_data   jsonb;
  v_skip   text[] := array['updated_at', 'updated_by'];
  v_ch     jsonb;
begin
  if jsonb_typeof(coalesce(p_data, 'null'::jsonb)) <> 'object' then
    raise exception 'بيانات غير صالحة' using errcode = '22023';
  end if;
  if p_id is not null then
    select * into old_row from public.unit_records where id = p_id for update;
    if not found then
      raise exception 'السجل غير موجود' using errcode = 'P0002';
    end if;
    v_kind := old_row.kind;
  else
    v_kind := nullif(btrim(coalesce(p_data ->> 'kind', '')), '');
  end if;
  v_spec := public.unit_kind_spec(v_kind);
  if v_spec is null then
    raise exception 'نوع السجل غير معروف' using errcode = '22023';
  end if;
  v_unit := v_spec ->> 'unit';
  if not public.unit_kind_can_edit(v_kind) then
    raise exception 'لا تملك صلاحية الكتابة في سجلات «%»', (select name from public.org_units where key = v_unit)
      using errcode = '42501';
  end if;
  if length(v_title) < 2 then
    raise exception 'اكتب العنوان' using errcode = '22023';
  end if;

  -- السجل الأم (التقييم يتبع مبنى، وبند الملاحظات يتبع محضر استلام…)
  if p_id is not null and not (p_data ? 'parent_id') then
    v_parent := old_row.parent_id;
  elsif nullif(p_data ->> 'parent_id', '') is not null then
    begin
      v_parent := (p_data ->> 'parent_id')::uuid;
    exception when others then
      raise exception 'السجل المرتبط غير صالح' using errcode = '22023';
    end;
  end if;
  if v_parent is not null then
    if v_spec ->> 'parent' is null then
      raise exception 'هذا النوع لا يتبع سجلاً آخر' using errcode = '22023';
    end if;
    select * into par from public.unit_records where id = v_parent;
    if not found or par.kind <> v_spec ->> 'parent' or par.id = p_id then
      raise exception 'السجل المرتبط غير موجود' using errcode = '22023';
    end if;
  elsif (v_spec ->> 'parent_required')::boolean then
    raise exception 'اختر السجل الذي يتبعه هذا السجل' using errcode = '22023';
  end if;

  -- العقد: من البيانات، أو من السجل الأم، أو كما كان
  if p_data ? 'project_id' then
    v_proj := public.jproject(p_data, 'project_id', false);
  elsif p_id is not null then
    v_proj := old_row.project_id;
  end if;
  if v_proj is null and v_parent is not null then
    v_proj := par.project_id;
  end if;
  if v_proj is null and (v_spec ->> 'project_required')::boolean then
    raise exception 'اختر العقد' using errcode = '22023';
  end if;

  v_status := public.jpick(p_data, 'status', array(select jsonb_array_elements_text(v_spec -> 'statuses')),
                           v_spec -> 'statuses' ->> 0, 'الحالة');
  v_level := public.jpick(p_data, 'level', array(select jsonb_array_elements_text(v_spec -> 'levels')),
                          v_spec -> 'levels' ->> 0, 'التصنيف');
  v_closed := v_status in (select jsonb_array_elements_text(v_spec -> 'closed'));
  v_data := public.unit_clean_data(p_data -> 'data');
  if v_due is not null and v_due < coalesce(v_date, old_row.rec_date, current_date) then
    raise exception 'الموعد قبل تاريخ السجل' using errcode = '22023';
  end if;

  if p_id is null then
    insert into public.unit_records (unit, kind, project_id, parent_id, title, ref_no, rec_date, due_date, status, level, progress,
                                     owner_text, closed_at, data, notes, created_by, updated_by)
    values (v_unit, v_kind, v_proj, v_parent, v_title, public.jtext(p_data, 'ref_no', 60, 'الرقم'),
            coalesce(v_date, current_date), v_due, v_status, v_level, public.jnum(p_data, 'progress', 0, 100, 'نسبة الإنجاز'),
            public.jtext(p_data, 'owner_text', 120, 'المسؤول'), case when v_closed then current_date end, v_data,
            public.jtext(p_data, 'notes', 4000, 'ملاحظات'), auth.uid(), auth.uid())
    returning * into new_row;
    perform public.write_audit('unit.create', v_proj, null,
      jsonb_build_object('record_id', new_row.id, 'unit', v_unit, 'kind', v_kind, 'title', v_title, 'status', v_status),
      coalesce(public.project_label(v_proj), (select name from public.org_units where key = v_unit)));
  else
    update public.unit_records set
      project_id = v_proj, parent_id = v_parent, title = v_title, ref_no = public.jtext(p_data, 'ref_no', 60, 'الرقم'),
      rec_date = coalesce(v_date, old_row.rec_date), due_date = v_due, status = v_status, level = v_level,
      progress = public.jnum(p_data, 'progress', 0, 100, 'نسبة الإنجاز'),
      owner_text = public.jtext(p_data, 'owner_text', 120, 'المسؤول'),
      closed_at = case when not v_closed then null when old_row.closed_at is not null then old_row.closed_at else current_date end,
      data = v_data, notes = public.jtext(p_data, 'notes', 4000, 'ملاحظات'),
      origin_project = case when v_proj is distinct from old_row.project_id then null else old_row.origin_project end,
      updated_at = now(), updated_by = auth.uid()
    where id = p_id
    returning * into new_row;
    v_ch := public.jsonb_changes(to_jsonb(old_row), to_jsonb(new_row), v_skip);
    if v_ch <> '{}'::jsonb then
      perform public.write_audit('unit.update', v_proj, null,
        jsonb_build_object('record_id', p_id, 'unit', v_unit, 'kind', v_kind, 'title', v_title, 'changes', v_ch),
        coalesce(public.project_label(v_proj), (select name from public.org_units where key = v_unit)));
    end if;
  end if;
  return new_row.id;
end;
$$;

create or replace function public.delete_unit_record(p_id uuid)
returns text[]
language plpgsql security definer set search_path = public
as $$
declare
  r       public.unit_records;
  v_paths text[];
  v_n     integer;
begin
  select * into r from public.unit_records where id = p_id for update;
  if not found then
    raise exception 'السجل غير موجود' using errcode = 'P0002';
  end if;
  if not (public.unit_is_head(r.unit)
          or (public.unit_kind_can_edit(r.kind) and r.created_by = auth.uid() and r.created_at > now() - interval '24 hours')) then
    raise exception 'حذف السجل للمدير ورئيس الوحدة، أو لمن أضافه خلال 24 ساعة' using errcode = '42501';
  end if;
  with recursive tree as (
    select id from public.unit_records where id = p_id
    union all
    select c.id from public.unit_records c join tree t on c.parent_id = t.id
  )
  select coalesce(array_agg(f.path), '{}'), (select count(*) - 1 from tree)
    into v_paths, v_n
    from public.doc_files f where f.record_id in (select id from tree);
  delete from public.unit_records where id = p_id;
  perform public.write_audit('unit.delete', r.project_id, null,
    jsonb_build_object('record_id', p_id, 'unit', r.unit, 'kind', r.kind, 'title', r.title, 'ref_no', r.ref_no,
                       'children', coalesce(v_n, 0), 'files', coalesce(array_length(v_paths, 1), 0)),
    coalesce(public.project_label(r.project_id), (select name from public.org_units where key = r.unit)));
  return v_paths;
end;
$$;

create or replace function public.delete_doc_file(p_id uuid)
returns text
language plpgsql security definer set search_path = public
as $$
declare
  f      public.doc_files;
  v_p    uuid;
  v_ok   boolean;
  v_head boolean := false;
  v_act  text;
begin
  select * into f from public.doc_files where id = p_id for update;
  if not found then
    raise exception 'الملف غير موجود' using errcode = 'P0002';
  end if;
  if f.revision_id is not null then
    select i.project_id, public.doc_can_edit(i.kind, i.project_id) into v_p, v_ok
      from public.doc_revisions r join public.doc_items i on i.id = r.item_id where r.id = f.revision_id;
    v_act := 'doc.file_delete';
  elsif f.record_id is not null then
    select project_id, public.unit_kind_can_edit(kind), public.unit_is_head(unit) into v_p, v_ok, v_head
      from public.unit_records where id = f.record_id;
    v_act := 'unit.file_delete';
  else
    select project_id, public.site_report_can_edit(project_id) into v_p, v_ok from public.site_reports where id = f.report_id;
    v_act := 'report.file_delete';
  end if;
  if not (public.is_director() or coalesce(v_head, false)
          or (v_ok and f.created_by = auth.uid() and f.created_at > now() - interval '24 hours')) then
    raise exception 'إزالة الملف للمدير، أو لمن رفعه خلال 24 ساعة' using errcode = '42501';
  end if;
  delete from public.doc_files where id = p_id;
  perform public.write_audit(v_act, v_p, null,
    jsonb_build_object('file', f.name, 'size', f.size_bytes, 'revision_id', f.revision_id, 'report_id', f.report_id,
                       'record_id', f.record_id));
  return f.path;
end;
$$;

create or replace function public.can_upload_doc_path(p_name text)
returns boolean
language plpgsql stable security definer set search_path = public
as $$
declare
  v_scope text := split_part(coalesce(p_name, ''), '/', 1);
  v_owner uuid;
  v_kind  text;
  v_proj  uuid;
  v_unit  text;
begin
  if p_name is null or p_name !~ '^(doc|report|unit)/[0-9a-f-]{36}/[A-Za-z0-9_-]{8,64}\.(pdf|jpg|jpeg|png|webp|gif|mp4|mov|webm)$' then
    return false;
  end if;
  v_owner := split_part(p_name, '/', 2)::uuid;
  if v_scope = 'doc' then
    select i.kind, i.project_id into v_kind, v_proj
      from public.doc_revisions r join public.doc_items i on i.id = r.item_id where r.id = v_owner;
    -- الفيديو في التصاميم وحدها من بين المستندات
    if found and v_kind <> 'design' and p_name ~ '\.(mp4|mov|webm)$' then
      return false;
    end if;
    return found and public.doc_can_edit(v_kind, v_proj);
  end if;
  if v_scope = 'unit' then
    select kind into v_unit from public.unit_records where id = v_owner;
    return found and public.unit_kind_can_edit(v_unit);
  end if;
  select project_id into v_proj from public.site_reports where id = v_owner;
  return found and public.site_report_can_edit(v_proj);
end;
$$;


-- ---------------------------------------------------------------------
-- 3. الرقم الإشاري الموسّع
--   رموز الصيغة: {YYYY} {YY} {MM} {DD} السنة والشهر واليوم بتوقيت طرابلس، {SEQ} التسلسل بعدد الخانات المحدد
--   أو {SEQ:n} بعدد خانات n، {SECTION} رمز القسم، {DEPT} رمز القسم المشرف على العقد، {CODE} رمز يمرره المصدر
--   (رقم العقد مثلاً)، {KIND} نوع السجل. وأي نص آخر في الصيغة يُكتب كما هو.
-- ---------------------------------------------------------------------
create table if not exists public.ref_schemes (
  key         text primary key check (key ~ '^[a-z][a-z0-9_]{1,29}$'),
  name        text not null check (length(btrim(name)) between 2 and 60),
  pattern     text not null check (length(pattern) between 3 and 120 and pattern like '%{SEQ%'),
  reset       text not null default 'yearly' check (reset in ('never', 'yearly', 'monthly', 'daily')),
  per_section boolean not null default false,
  pad         integer not null default 4 check (pad between 1 and 8),
  start_at    integer not null default 1 check (start_at between 0 and 9999999),
  codes       jsonb not null default '{}'::jsonb check (jsonb_typeof(codes) = 'object' and length(codes::text) <= 4000),
  active      boolean not null default true,
  system      boolean not null default false,
  updated_at  timestamptz not null default now(),
  updated_by  uuid references public.profiles(id) on delete set null
);
create index if not exists ref_schemes_updated_by_idx on public.ref_schemes (updated_by);

create table if not exists public.ref_counters (
  scheme  text not null references public.ref_schemes(key) on delete cascade,
  period  text not null,
  value   integer not null,
  primary key (scheme, period)
);

create table if not exists public.ref_log (
  id         bigint generated always as identity primary key,
  scheme     text not null references public.ref_schemes(key) on delete cascade,
  ref        text not null,
  period     text not null,
  seq        integer not null,
  section    text,
  source     text,
  title      text,
  created_by uuid references public.profiles(id) on delete set null default auth.uid(),
  created_at timestamptz not null default now(),
  unique (scheme, ref)
);
create index if not exists ref_log_created_by_idx on public.ref_log (created_by);
create index if not exists ref_log_created_at_idx on public.ref_log (created_at desc);

insert into public.ref_schemes (key, name, pattern, reset, pad, codes, system) values
  ('print', 'المطبوعات والملفات المصدّرة', 'م.ش.هـ/{SECTION}/{YYYY}/{SEQ}', 'yearly', 4,
   '{"cycle":"د.م","risks":"م.م","swot":"ت.س","docs":"ش.ف","supervision":"إش","heritage":"تر","planning_qa":"ت.ج","safety":"س.م","acceptance":"م.س","print":"ط","manual":"د"}', true),
  ('letter_out', 'المراسلات الصادرة', 'م.ش.هـ/ص/{YYYY}/{SEQ}', 'yearly', 4, '{}', true),
  ('letter_in', 'المراسلات الواردة', 'م.ش.هـ/و/{YYYY}/{SEQ}', 'yearly', 4, '{}', true),
  ('letter_internal', 'المراسلات الداخلية', 'م.ش.هـ/د/{YYYY}/{SEQ}', 'yearly', 4, '{}', true)
on conflict (key) do nothing;

-- تنسيق رقم من صيغة وتسلسل وتاريخ وسياق
create or replace function public.ref_format(p_pattern text, p_seq integer, p_pad integer, p_at timestamptz, p_ctx jsonb, p_codes jsonb)
returns text
language plpgsql immutable set search_path = public
as $$
declare
  t   timestamp := p_at at time zone 'Africa/Tripoli';
  r   text := p_pattern;
  m   text[];
  sec text := coalesce(p_ctx ->> 'section', '');
  dep text := coalesce(p_ctx ->> 'dept', '');
begin
  r := replace(r, '{YYYY}', to_char(t, 'YYYY'));
  r := replace(r, '{YY}', to_char(t, 'YY'));
  r := replace(r, '{MM}', to_char(t, 'MM'));
  r := replace(r, '{DD}', to_char(t, 'DD'));
  r := replace(r, '{SECTION}', coalesce(nullif(p_codes ->> sec, ''), nullif(sec, ''), '-'));
  r := replace(r, '{DEPT}', coalesce(nullif(p_codes ->> dep, ''), nullif(dep, ''), '-'));
  r := replace(r, '{CODE}', coalesce(nullif(left(regexp_replace(coalesce(p_ctx ->> 'code', ''), '[\s/]+', '-', 'g'), 30), ''), '-'));
  r := replace(r, '{KIND}', coalesce(nullif(p_codes ->> coalesce(p_ctx ->> 'kind', ''), ''), nullif(p_ctx ->> 'kind', ''), '-'));
  loop
    m := regexp_match(r, '\{SEQ:([1-8])\}');
    exit when m is null;
    r := replace(r, '{SEQ:' || m[1] || '}', lpad(p_seq::text, m[1]::int, '0'));
  end loop;
  r := replace(r, '{SEQ}', lpad(p_seq::text, p_pad, '0'));
  return r;
end;
$$;

-- يصدر الرقم التالي لصيغة: تسلسل لا يتكرر حتى مع طلبات متزامنة، ويُسجَّل في سجل الأرقام
create or replace function public.next_ref(p_scheme text, p_ctx jsonb default '{}'::jsonb)
returns jsonb
language plpgsql security definer set search_path = public
as $$
declare
  s        public.ref_schemes;
  v_at     timestamptz := now();
  t        timestamp := v_at at time zone 'Africa/Tripoli';
  v_ctx    jsonb := coalesce(p_ctx, '{}'::jsonb);
  v_period text;
  v_seq    integer;
  v_ref    text;
begin
  if not public.is_member() then
    raise exception 'غير مصرح' using errcode = '42501';
  end if;
  if jsonb_typeof(v_ctx) <> 'object' or length(v_ctx::text) > 2000 then
    raise exception 'سياق غير صالح' using errcode = '22023';
  end if;
  select * into s from public.ref_schemes where key = p_scheme;
  if not found or not s.active then
    raise exception 'صيغة الرقم الإشاري غير موجودة أو موقوفة' using errcode = 'P0002';
  end if;
  v_period := case s.reset when 'yearly' then to_char(t, 'YYYY') when 'monthly' then to_char(t, 'YYYY-MM')
                           when 'daily' then to_char(t, 'YYYY-MM-DD') else 'all' end;
  if s.per_section then
    v_period := v_period || '|' || left(coalesce(v_ctx ->> 'section', ''), 30);
  end if;
  insert into public.ref_counters (scheme, period, value) values (s.key, v_period, s.start_at)
  on conflict (scheme, period) do update set value = public.ref_counters.value + 1
  returning value into v_seq;
  v_ref := public.ref_format(s.pattern, v_seq, s.pad, v_at, v_ctx, s.codes);
  insert into public.ref_log (scheme, ref, period, seq, section, source, title)
  values (s.key, v_ref, v_period, v_seq, left(v_ctx ->> 'section', 30), left(v_ctx ->> 'source', 80), left(v_ctx ->> 'title', 200));
  return jsonb_build_object('ref', v_ref, 'seq', v_seq, 'period', v_period, 'at', v_at);
end;
$$;

create or replace function public.save_ref_scheme(p_key text, p_data jsonb)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  old_s public.ref_schemes;
  v_key text := lower(btrim(coalesce(p_key, '')));
begin
  if not public.is_director() then
    raise exception 'صيغ الأرقام الإشارية من صلاحية مدير المكتب وحده' using errcode = '42501';
  end if;
  if not public.writes_allowed() then
    raise exception 'المنظومة في وضع القراءة فقط' using errcode = '42501';
  end if;
  if jsonb_typeof(p_data) <> 'object' then
    raise exception 'بيانات غير صالحة' using errcode = '22023';
  end if;
  if coalesce(p_data ->> 'pattern', '') not like '%{SEQ%' then
    raise exception 'الصيغة يجب أن تحوي {SEQ} حتى لا يتكرر الرقم' using errcode = '22023';
  end if;
  select * into old_s from public.ref_schemes where key = v_key;
  insert into public.ref_schemes (key, name, pattern, reset, per_section, pad, start_at, codes, active, updated_at, updated_by)
  values (v_key, btrim(p_data ->> 'name'), p_data ->> 'pattern', coalesce(p_data ->> 'reset', 'yearly'),
          coalesce((p_data ->> 'per_section')::boolean, false), coalesce((p_data ->> 'pad')::int, 4),
          coalesce((p_data ->> 'start_at')::int, 1), coalesce(p_data -> 'codes', '{}'::jsonb),
          coalesce((p_data ->> 'active')::boolean, true), now(), auth.uid())
  on conflict (key) do update set name = excluded.name, pattern = excluded.pattern, reset = excluded.reset,
    per_section = excluded.per_section, pad = excluded.pad, start_at = excluded.start_at, codes = excluded.codes,
    active = excluded.active, updated_at = now(), updated_by = auth.uid();
  perform public.write_audit('ref.scheme_save', null, null,
    jsonb_build_object('key', v_key, 'name', p_data ->> 'name', 'pattern', p_data ->> 'pattern',
                       'from', case when old_s.key is null then null else old_s.pattern end, 'created', old_s.key is null),
    'الأرقام الإشارية');
end;
$$;

create or replace function public.delete_ref_scheme(p_key text)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  s public.ref_schemes;
begin
  if not public.is_director() or not public.writes_allowed() then
    raise exception 'غير مصرح' using errcode = '42501';
  end if;
  select * into s from public.ref_schemes where key = p_key for update;
  if not found then
    raise exception 'الصيغة غير موجودة' using errcode = 'P0002';
  end if;
  if s.system then
    raise exception 'الصيغ الأساسية لا تُحذف؛ أوقفها بدلاً من ذلك' using errcode = '22023';
  end if;
  if exists (select 1 from public.ref_log where scheme = p_key) then
    raise exception 'صدرت أرقام بهذه الصيغة؛ أوقفها بدلاً من حذفها حفاظاً على السجل' using errcode = '22023';
  end if;
  delete from public.ref_schemes where key = p_key;
  perform public.write_audit('ref.scheme_delete', null, null, jsonb_build_object('key', p_key, 'name', s.name), 'الأرقام الإشارية');
end;
$$;

-- يضبط المدير الرقم الذي يبدأ منه التسلسل في الفترة الحالية (عند الانتقال من دفتر ورقي مثلاً)
create or replace function public.set_ref_counter(p_scheme text, p_next integer, p_section text default null)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  s        public.ref_schemes;
  t        timestamp := now() at time zone 'Africa/Tripoli';
  v_period text;
  v_old    integer;
begin
  if not public.is_director() or not public.writes_allowed() then
    raise exception 'غير مصرح' using errcode = '42501';
  end if;
  select * into s from public.ref_schemes where key = p_scheme;
  if not found then
    raise exception 'الصيغة غير موجودة' using errcode = 'P0002';
  end if;
  if p_next is null or p_next < 1 or p_next > 9999999 then
    raise exception 'الرقم التالي من 1 إلى 9999999' using errcode = '22023';
  end if;
  v_period := case s.reset when 'yearly' then to_char(t, 'YYYY') when 'monthly' then to_char(t, 'YYYY-MM')
                           when 'daily' then to_char(t, 'YYYY-MM-DD') else 'all' end;
  if s.per_section then
    v_period := v_period || '|' || left(coalesce(p_section, ''), 30);
  end if;
  select value into v_old from public.ref_counters where scheme = s.key and period = v_period;
  if exists (select 1 from public.ref_log where scheme = s.key and period = v_period and seq >= p_next) then
    raise exception 'صدرت أرقام بهذا التسلسل أو بعده في الفترة الحالية؛ اختر رقماً أكبر' using errcode = '22023';
  end if;
  insert into public.ref_counters (scheme, period, value) values (s.key, v_period, p_next - 1)
  on conflict (scheme, period) do update set value = excluded.value;
  perform public.write_audit('ref.counter_set', null, null,
    jsonb_build_object('key', s.key, 'period', v_period, 'from', coalesce(v_old, 0) + 1, 'to', p_next), 'الأرقام الإشارية');
end;
$$;

alter table public.ref_schemes enable row level security;
alter table public.ref_counters enable row level security;
alter table public.ref_log enable row level security;
drop policy if exists ref_schemes_read on public.ref_schemes;
create policy ref_schemes_read on public.ref_schemes for select to authenticated using ((select public.is_member()));
drop policy if exists ref_counters_read on public.ref_counters;
create policy ref_counters_read on public.ref_counters for select to authenticated using ((select public.is_member()));
drop policy if exists ref_log_read on public.ref_log;
create policy ref_log_read on public.ref_log for select to authenticated using ((select public.is_member()));
revoke all on public.ref_schemes, public.ref_counters, public.ref_log from anon;
revoke insert, update, delete, truncate on public.ref_schemes, public.ref_counters, public.ref_log from authenticated;
grant select on public.ref_schemes, public.ref_counters, public.ref_log to authenticated;
grant all on public.ref_schemes, public.ref_counters, public.ref_log to service_role;

do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and tablename = 'ref_schemes') then
      execute 'alter publication supabase_realtime add table public.ref_schemes';
    end if;
    if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and tablename = 'user_grants') then
      execute 'alter publication supabase_realtime add table public.user_grants';
    end if;
  end if;
end $$;

-- ---------------------------------------------------------------------
-- 4. تخصيص الواجهة: ui.layout
--   {"sections": {"<قسم>": {"name": "...", "desc": "...", "hidden": false}}, "section_order": ["..."],
--    "pages": {"<رقم الصفحة>": {"label": "...", "hidden": false}}, "page_order": {"<قسم>": [أرقام الصفحات]}}
-- ---------------------------------------------------------------------
do $$
begin
  if not exists (select 1 from pg_proc where proname = 'set_setting_v22' and pronamespace = 'public'::regnamespace) then
    alter function public.set_setting(text, jsonb) rename to set_setting_v22;
  end if;
end $$;

create or replace function public.set_setting(p_key text, p_value jsonb)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  v_old jsonb;
begin
  if p_key <> 'ui.layout' then
    perform public.set_setting_v22(p_key, p_value);
    return;
  end if;
  if not public.is_director() then
    raise exception 'الإعدادات من صلاحية مدير المكتب وحده' using errcode = '42501';
  end if;
  if jsonb_typeof(p_value) <> 'object' or length(p_value::text) > 30000
     or (p_value -> 'sections' is not null and jsonb_typeof(p_value -> 'sections') <> 'object')
     or (p_value -> 'pages' is not null and jsonb_typeof(p_value -> 'pages') <> 'object')
     or (p_value -> 'section_order' is not null and jsonb_typeof(p_value -> 'section_order') <> 'array')
     or (p_value -> 'page_order' is not null and jsonb_typeof(p_value -> 'page_order') <> 'object')
     or exists (select 1 from jsonb_each(coalesce(p_value -> 'sections', '{}'::jsonb)) e(k, v)
                 where jsonb_typeof(v) <> 'object' or length(coalesce(v ->> 'name', '')) > 40 or length(coalesce(v ->> 'desc', '')) > 200)
     or exists (select 1 from jsonb_each(coalesce(p_value -> 'pages', '{}'::jsonb)) e(k, v)
                 where k !~ '^\d{1,4}$' or jsonb_typeof(v) <> 'object' or length(coalesce(v ->> 'label', '')) > 40) then
    raise exception 'قيمة غير صالحة للإعداد %', p_key using errcode = '22023';
  end if;
  select value into v_old from public.app_settings where key = p_key;
  if v_old is not distinct from p_value then
    return;
  end if;
  insert into public.app_settings (key, value, updated_at, updated_by)
  values (p_key, p_value, now(), auth.uid())
  on conflict (key) do update set value = excluded.value, updated_at = excluded.updated_at, updated_by = excluded.updated_by;
  perform public.write_audit('setting.update', null, null, jsonb_build_object('key', p_key, 'from', v_old, 'to', p_value), p_key);
end;
$$;

insert into public.app_settings (key, value) values ('ui.layout', '{}'::jsonb) on conflict (key) do nothing;

-- ---------------------------------------------------------------------
-- 5. الصلاحيات على الدوال
-- ---------------------------------------------------------------------
revoke execute on function
  public.has_grant(text), public.grant_scope_ok(text), public.set_user_grants(uuid, text[]), public.unit_kind_can_edit(text),
  public.doc_can_edit(text, uuid), public.site_report_can_edit(uuid), public.can_edit_form(uuid, text), public.can_edit_swot(),
  public.ref_format(text, integer, integer, timestamptz, jsonb, jsonb), public.next_ref(text, jsonb),
  public.save_ref_scheme(text, jsonb), public.delete_ref_scheme(text), public.set_ref_counter(text, integer, text),
  public.set_setting(text, jsonb)
from public, anon;
grant execute on function
  public.has_grant(text), public.grant_scope_ok(text), public.set_user_grants(uuid, text[]), public.unit_kind_can_edit(text),
  public.doc_can_edit(text, uuid), public.site_report_can_edit(uuid), public.can_edit_form(uuid, text), public.can_edit_swot(),
  public.ref_format(text, integer, integer, timestamptz, jsonb, jsonb), public.next_ref(text, jsonb),
  public.save_ref_scheme(text, jsonb), public.delete_ref_scheme(text), public.set_ref_counter(text, integer, text),
  public.set_setting(text, jsonb)
to authenticated;
revoke execute on function public.set_setting_v22(text, jsonb), public.doc_can_edit_v22(text, uuid),
  public.site_report_can_edit_v22(uuid), public.can_edit_form_v22(uuid, text), public.can_edit_swot_v22() from public, anon, authenticated;

notify pgrst, 'reload schema';
