-- =====================================================================
-- الترحيل 20: «المستندات الفنية» (المقايسات، المراسلات، التصاميم) و«الإشراف» (التقارير اليومية)
-- يُشغَّل بعد الترحيلات 1–19، ويمكن إعادة تشغيله دون ضرر.
--
--  1. doc_items      : بند مستند (مقايسة / مراسلة / تصميم) مرتبط بعقد أو عام للمكتب
--  2. doc_revisions  : مسار التطوير: الإصدار 1 ثم 2 ثم 3… بتاريخه وملاحظته (لكل بند إصدار واحد على الأقل)
--  3. site_reports   : التقرير اليومي للإشراف (نموذج منظم) لكل عقد ويوم
--  4. doc_files      : الملفات المرفقة (PDF والصور) لإصدار مستند أو لتقرير يومي
--  5. حاوية التخزين الخاصة «docs» (حد 20 ميجابايت للملف، PDF والصور فقط) وسياساتها
--  6. الدوال: الحفظ والحذف والإرفاق والمراجعة ومؤشر المساحة، مع التدقيق والتحديث اللحظي
--  7. اتباع الدمج: مستندات العقد وتقاريره تنتقل مع دمجه وتعود مع فكّه
--
-- مسار الملف في الحاوية: doc/<معرّف الإصدار>/<اسم عشوائي>.<الامتداد>  أو  report/<معرّف التقرير>/<…>
-- القراءة لكل أعضاء المنظومة، والكتابة عبر الدوال وحدها.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. الجداول
-- ---------------------------------------------------------------------
create table if not exists public.doc_items (
  id             uuid primary key default gen_random_uuid(),
  kind           text not null check (kind in ('boq', 'letter', 'design')),
  project_id     uuid references public.projects(id) on delete set null,
  origin_project uuid references public.projects(id) on delete set null,
  title          text not null check (length(btrim(title)) between 2 and 200),
  ref_no         text not null default '' check (length(ref_no) <= 60),
  doc_date       date,
  category       text not null default '',
  direction      text check (direction in ('in', 'out', 'internal')),
  party          text not null default '' check (length(party) <= 120),
  amount         numeric(16,3) check (amount is null or amount >= 0),
  status         text not null default 'draft',
  reply_to       uuid references public.doc_items(id) on delete set null,
  due_date       date,
  notes          text not null default '' check (length(notes) <= 2000),
  created_at     timestamptz not null default now(),
  created_by     uuid,
  updated_at     timestamptz not null default now(),
  updated_by     uuid,
  constraint doc_items_kind_fields check (
    (kind = 'boq'    and category in ('estimate', 'contract', 'variation', 'final') and status in ('draft', 'review', 'approved') and direction is null)
 or (kind = 'letter' and category in ('', 'contract', 'finance', 'technical', 'admin', 'other') and status in ('open', 'closed', 'info') and direction is not null)
 or (kind = 'design' and category in ('architectural', 'structural', 'electrical', 'mechanical', 'plumbing', 'landscape', 'urban', 'heritage', 'other')
                     and status in ('draft', 'review', 'approved') and direction is null))
);
create index if not exists doc_items_project_idx on public.doc_items (project_id);
create index if not exists doc_items_origin_idx on public.doc_items (origin_project);
create index if not exists doc_items_reply_idx on public.doc_items (reply_to);
create index if not exists doc_items_kind_idx on public.doc_items (kind, doc_date desc);

create table if not exists public.doc_revisions (
  id         uuid primary key default gen_random_uuid(),
  item_id    uuid not null references public.doc_items(id) on delete cascade,
  rev_no     smallint not null check (rev_no between 1 and 999),
  rev_date   date not null default current_date,
  note       text not null default '' check (length(note) <= 1000),
  created_at timestamptz not null default now(),
  created_by uuid,
  updated_at timestamptz not null default now(),
  updated_by uuid,
  unique (item_id, rev_no)
);

create table if not exists public.site_reports (
  id             uuid primary key default gen_random_uuid(),
  project_id     uuid not null references public.projects(id) on delete cascade,
  origin_project uuid references public.projects(id) on delete set null,
  work_id        uuid references public.contract_works(id) on delete set null,
  report_date    date not null,
  weather        text not null default 'clear' check (weather in ('clear', 'cloudy', 'rain', 'wind', 'dust', 'hot', 'cold')),
  temp_c         smallint check (temp_c between -20 and 60),
  workers        integer check (workers between 0 and 5000),
  equipment      text not null default '' check (length(equipment) <= 1000),
  works_done     text not null check (length(btrim(works_done)) between 3 and 4000),
  materials      text not null default '' check (length(materials) <= 1500),
  issues         text not null default '' check (length(issues) <= 2000),
  safety         text not null default '' check (length(safety) <= 1500),
  next_plan      text not null default '' check (length(next_plan) <= 1500),
  progress_pct   numeric(5,2) check (progress_pct between 0 and 100),
  notes          text not null default '' check (length(notes) <= 1500),
  reviewed_by    uuid,
  reviewed_at    timestamptz,
  review_note    text not null default '' check (length(review_note) <= 1000),
  created_at     timestamptz not null default now(),
  created_by     uuid,
  updated_at     timestamptz not null default now(),
  updated_by     uuid
);
create unique index if not exists site_reports_day_uq
  on public.site_reports (project_id, report_date, coalesce(work_id, '00000000-0000-0000-0000-000000000000'::uuid));
create index if not exists site_reports_date_idx on public.site_reports (report_date desc);
create index if not exists site_reports_origin_idx on public.site_reports (origin_project);
create index if not exists site_reports_work_idx on public.site_reports (work_id);

create table if not exists public.doc_files (
  id          uuid primary key default gen_random_uuid(),
  revision_id uuid references public.doc_revisions(id) on delete cascade,
  report_id   uuid references public.site_reports(id) on delete cascade,
  path        text not null unique check (length(path) <= 300),
  name        text not null check (length(name) between 1 and 200),
  mime        text not null check (mime in ('application/pdf', 'image/jpeg', 'image/png', 'image/webp', 'image/gif')),
  size_bytes  bigint not null check (size_bytes between 1 and 20971520),
  width       integer check (width between 1 and 20000),
  height      integer check (height between 1 and 20000),
  sort        integer not null default 0,
  created_at  timestamptz not null default now(),
  created_by  uuid,
  constraint doc_files_one_owner check (num_nonnulls(revision_id, report_id) = 1)
);
create index if not exists doc_files_revision_idx on public.doc_files (revision_id, sort);
create index if not exists doc_files_report_idx on public.doc_files (report_id, sort);

-- ---------------------------------------------------------------------
-- 2. الصلاحيات
-- ---------------------------------------------------------------------
-- من يكتب في كل نوع:
--   المقايسات : المدير، موظفو مكتب المدير، مكتب العقود، رئيسا الشؤون الفنية والمطابقة والاستلام
--   المراسلات : كل الأدوار عدا CISO
--   التصاميم  : المدير، موظفو مكتب المدير، رئيسا الشؤون الفنية والترميم، ورئيس القسم المشرف على العقد
create or replace function public.doc_can_edit(p_kind text, p_project uuid)
returns boolean
language plpgsql stable security definer set search_path = public
as $$
declare
  me     public.profiles;
  v_dept text;
begin
  if not public.writes_allowed() then
    return false;
  end if;
  select * into me from public.profiles where id = auth.uid();
  if not found or me.role is null then
    return false;
  end if;
  if p_project is not null then
    select department into v_dept from public.projects where id = p_project and merged_into is null;
    if not found then
      return false;
    end if;
  end if;
  if me.role = 'director' then
    return p_kind in ('boq', 'letter', 'design');
  end if;
  return case p_kind
    when 'boq'    then me.role in ('office_staff', 'contracts')
                       or (me.role = 'dept_head' and me.department in ('technical', 'acceptance'))
    when 'letter' then me.role in ('office_staff', 'contracts', 'planning_qa', 'dept_head')
    when 'design' then me.role = 'office_staff'
                       or (me.role = 'dept_head' and (me.department in ('technical', 'restoration')
                                                      or (v_dept is not null and me.department = v_dept)))
    else false
  end;
end;
$$;

-- التقرير اليومي: المدير، موظفو مكتب المدير، ورئيس القسم المشرف على العقد
create or replace function public.site_report_can_edit(p_project uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
  select public.writes_allowed()
     and exists (select 1 from public.projects p where p.id = p_project and p.merged_into is null)
     and (coalesce(public.my_role()::text, '') in ('director', 'office_staff')
          or (coalesce(public.my_role()::text, '') = 'dept_head'
              and exists (select 1 from public.profiles me join public.projects p on p.id = p_project
                           where me.id = auth.uid() and me.department is not null and me.department = p.department)))
$$;

-- هل يحق للمستخدم رفع ملف بهذا المسار؟ (تستعملها سياسة الحاوية)
create or replace function public.can_upload_doc_path(p_name text)
returns boolean
language plpgsql stable security definer set search_path = public
as $$
declare
  v_scope text := split_part(coalesce(p_name, ''), '/', 1);
  v_owner uuid;
  v_kind  text;
  v_proj  uuid;
begin
  if p_name is null or p_name !~ '^(doc|report)/[0-9a-f-]{36}/[A-Za-z0-9_-]{8,64}\.(pdf|jpg|jpeg|png|webp|gif)$' then
    return false;
  end if;
  v_owner := split_part(p_name, '/', 2)::uuid;
  if v_scope = 'doc' then
    select i.kind, i.project_id into v_kind, v_proj
      from public.doc_revisions r join public.doc_items i on i.id = r.item_id where r.id = v_owner;
    return found and public.doc_can_edit(v_kind, v_proj);
  end if;
  select project_id into v_proj from public.site_reports where id = v_owner;
  return found and public.site_report_can_edit(v_proj);
end;
$$;

-- ---------------------------------------------------------------------
-- 3. حاوية التخزين وسياساتها (على Supabase فقط)
-- ---------------------------------------------------------------------
do $$
begin
  if to_regclass('storage.buckets') is null then
    return;
  end if;
  insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
  values ('docs', 'docs', false, 20971520,
          array['application/pdf', 'image/jpeg', 'image/png', 'image/webp', 'image/gif'])
  on conflict (id) do update set public = false, file_size_limit = excluded.file_size_limit,
                                 allowed_mime_types = excluded.allowed_mime_types;

  drop policy if exists docs_read on storage.objects;
  create policy docs_read on storage.objects for select to authenticated
    using (bucket_id = 'docs' and (select public.is_member()));

  drop policy if exists docs_upload on storage.objects;
  create policy docs_upload on storage.objects for insert to authenticated
    with check (bucket_id = 'docs' and public.can_upload_doc_path(name));

  -- الحذف بعد إزالة السجل فقط (لا يُحذف ملف ما زال مرتبطاً)، لصاحب الملف أو المدير
  drop policy if exists docs_delete on storage.objects;
  create policy docs_delete on storage.objects for delete to authenticated
    using (bucket_id = 'docs'
           and ((select public.is_director()) or owner_id = (select auth.uid())::text or owner = (select auth.uid()))
           and not exists (select 1 from public.doc_files f where f.path = objects.name));
end $$;

-- ---------------------------------------------------------------------
-- 4. الدوال: المستندات
-- ---------------------------------------------------------------------
create or replace function public.doc_kind_label(p_kind text)
returns text language sql immutable as $$
  select case p_kind when 'boq' then 'مقايسة' when 'letter' then 'مراسلة' when 'design' then 'تصميم' else p_kind end
$$;

-- حفظ بند مستند. عند الإنشاء يُنشأ «الإصدار 1» معه. يعيد {item_id, revision_id}.
create or replace function public.save_doc_item(p_id uuid, p_data jsonb)
returns jsonb
language plpgsql security definer set search_path = public
as $$
declare
  old_row  public.doc_items;
  new_row  public.doc_items;
  v_kind   text;
  v_proj   uuid;
  v_title  text := public.jtext(p_data, 'title', 200, 'العنوان');
  v_reply  uuid;
  v_rev    uuid;
  v_cat    text;
  v_stat   text;
  v_dir    text;
  v_skip   text[] := array['updated_at', 'updated_by'];
  v_ch     jsonb;
begin
  if jsonb_typeof(coalesce(p_data, 'null'::jsonb)) <> 'object' then
    raise exception 'بيانات غير صالحة' using errcode = '22023';
  end if;
  if p_id is not null then
    select * into old_row from public.doc_items where id = p_id for update;
    if not found then
      raise exception 'المستند غير موجود' using errcode = 'P0002';
    end if;
    v_kind := old_row.kind;
    v_proj := case when p_data ? 'project_id' then public.jproject(p_data, 'project_id', false) else old_row.project_id end;
    if not public.doc_can_edit(v_kind, old_row.project_id) then
      raise exception 'لا تملك صلاحية تعديل هذا المستند' using errcode = '42501';
    end if;
  else
    v_kind := public.jpick(p_data, 'kind', array['boq', 'letter', 'design'], null, 'نوع المستند');
    if v_kind is null then
      raise exception 'اختر نوع المستند' using errcode = '22023';
    end if;
    v_proj := public.jproject(p_data, 'project_id', false);
  end if;
  if not public.doc_can_edit(v_kind, v_proj) then
    raise exception 'لا تملك صلاحية إضافة % لهذا العقد', public.doc_kind_label(v_kind) using errcode = '42501';
  end if;
  if length(v_title) < 2 then
    raise exception 'اكتب عنوان المستند' using errcode = '22023';
  end if;

  v_cat := case v_kind
    when 'boq'    then public.jpick(p_data, 'category', array['estimate', 'contract', 'variation', 'final'], 'estimate', 'نوع المقايسة')
    when 'letter' then public.jpick(p_data, 'category', array['', 'contract', 'finance', 'technical', 'admin', 'other'], '', 'تصنيف المراسلة')
    else public.jpick(p_data, 'category', array['architectural', 'structural', 'electrical', 'mechanical', 'plumbing', 'landscape',
                                                 'urban', 'heritage', 'other'], 'architectural', 'تخصص التصميم') end;
  v_stat := case v_kind
    when 'letter' then public.jpick(p_data, 'status', array['open', 'closed', 'info'], 'open', 'حالة المراسلة')
    else public.jpick(p_data, 'status', array['draft', 'review', 'approved'], 'draft', 'الحالة') end;
  v_dir := case when v_kind = 'letter' then public.jpick(p_data, 'direction', array['in', 'out', 'internal'], 'in', 'اتجاه المراسلة') end;

  if v_kind = 'letter' and nullif(p_data ->> 'reply_to', '') is not null then
    begin
      v_reply := (p_data ->> 'reply_to')::uuid;
    exception when others then
      raise exception 'مراسلة مرتبطة غير صالحة' using errcode = '22023';
    end;
    if v_reply = p_id or not exists (select 1 from public.doc_items where id = v_reply and kind = 'letter') then
      raise exception 'المراسلة المرتبطة غير موجودة' using errcode = '22023';
    end if;
  end if;

  if p_id is null then
    insert into public.doc_items (kind, project_id, title, ref_no, doc_date, category, direction, party, amount, status, reply_to,
                                  due_date, notes, created_by, updated_by)
    values (v_kind, v_proj, v_title, public.jtext(p_data, 'ref_no', 60, 'الرقم'),
            coalesce(public.jdate(p_data, 'doc_date', 'التاريخ'), current_date), v_cat, v_dir,
            public.jtext(p_data, 'party', 120, 'الجهة'),
            case when v_kind = 'boq' then public.jnum(p_data, 'amount', 0, 1e13, 'القيمة الإجمالية') end,
            v_stat, v_reply,
            case when v_kind = 'letter' then public.jdate(p_data, 'due_date', 'موعد الرد') end,
            public.jtext(p_data, 'notes', 2000, 'ملاحظات'), auth.uid(), auth.uid())
    returning * into new_row;
    insert into public.doc_revisions (item_id, rev_no, rev_date, note, created_by, updated_by)
    values (new_row.id, 1, new_row.doc_date, public.jtext(p_data, 'rev_note', 1000, 'ملاحظة الإصدار'), auth.uid(), auth.uid())
    returning id into v_rev;
    perform public.write_audit('doc.create', v_proj, null,
      jsonb_build_object('item_id', new_row.id, 'kind', v_kind, 'title', v_title, 'ref_no', new_row.ref_no),
      coalesce(public.project_label(v_proj), 'عام'));
  else
    update public.doc_items set
      project_id = v_proj, title = v_title, ref_no = public.jtext(p_data, 'ref_no', 60, 'الرقم'),
      doc_date = coalesce(public.jdate(p_data, 'doc_date', 'التاريخ'), old_row.doc_date), category = v_cat, direction = v_dir,
      party = public.jtext(p_data, 'party', 120, 'الجهة'),
      amount = case when v_kind = 'boq' then public.jnum(p_data, 'amount', 0, 1e13, 'القيمة الإجمالية') end,
      status = v_stat, reply_to = v_reply,
      due_date = case when v_kind = 'letter' then public.jdate(p_data, 'due_date', 'موعد الرد') end,
      notes = public.jtext(p_data, 'notes', 2000, 'ملاحظات'),
      origin_project = case when v_proj is distinct from old_row.project_id then null else old_row.origin_project end,
      updated_at = now(), updated_by = auth.uid()
    where id = p_id
    returning * into new_row;
    v_ch := public.jsonb_changes(to_jsonb(old_row), to_jsonb(new_row), v_skip);
    if v_ch <> '{}'::jsonb then
      perform public.write_audit('doc.update', v_proj, null,
        jsonb_build_object('item_id', p_id, 'kind', v_kind, 'title', v_title, 'changes', v_ch),
        coalesce(public.project_label(v_proj), 'عام'));
    end if;
    select id into v_rev from public.doc_revisions where item_id = p_id order by rev_no desc limit 1;
  end if;
  return jsonb_build_object('item_id', new_row.id, 'revision_id', v_rev);
end;
$$;

-- إضافة إصدار جديد (p_id = null) أو تعديل تاريخ/ملاحظة إصدار قائم
create or replace function public.save_doc_revision(p_id uuid, p_item uuid, p_data jsonb)
returns uuid
language plpgsql security definer set search_path = public
as $$
declare
  it     public.doc_items;
  old_r  public.doc_revisions;
  v_id   uuid;
  v_no   smallint;
  v_date date := public.jdate(p_data, 'rev_date', 'تاريخ الإصدار');
  v_note text := public.jtext(p_data, 'note', 1000, 'ملاحظة الإصدار');
begin
  if p_id is not null then
    select * into old_r from public.doc_revisions where id = p_id for update;
    if not found then
      raise exception 'الإصدار غير موجود' using errcode = 'P0002';
    end if;
    p_item := old_r.item_id;
  end if;
  select * into it from public.doc_items where id = p_item for update;
  if not found then
    raise exception 'المستند غير موجود' using errcode = 'P0002';
  end if;
  if not public.doc_can_edit(it.kind, it.project_id) then
    raise exception 'لا تملك صلاحية تعديل هذا المستند' using errcode = '42501';
  end if;
  if p_id is null then
    select coalesce(max(rev_no), 0) + 1 into v_no from public.doc_revisions where item_id = p_item;
    if v_no > 999 then
      raise exception 'بلغ المستند الحد الأعلى للإصدارات' using errcode = '22023';
    end if;
    insert into public.doc_revisions (item_id, rev_no, rev_date, note, created_by, updated_by)
    values (p_item, v_no, coalesce(v_date, current_date), v_note, auth.uid(), auth.uid())
    returning id into v_id;
    update public.doc_items set updated_at = now(), updated_by = auth.uid() where id = p_item;
    perform public.write_audit('doc.revision_add', it.project_id, null,
      jsonb_build_object('item_id', p_item, 'kind', it.kind, 'title', it.title, 'rev_no', v_no, 'note', v_note),
      coalesce(public.project_label(it.project_id), 'عام'));
    return v_id;
  end if;
  update public.doc_revisions set rev_date = coalesce(v_date, old_r.rev_date), note = v_note, updated_at = now(), updated_by = auth.uid()
   where id = p_id;
  if old_r.note is distinct from v_note or old_r.rev_date is distinct from coalesce(v_date, old_r.rev_date) then
    perform public.write_audit('doc.revision_update', it.project_id, null,
      jsonb_build_object('item_id', p_item, 'kind', it.kind, 'title', it.title, 'rev_no', old_r.rev_no,
                         'from', jsonb_build_object('date', old_r.rev_date, 'note', old_r.note),
                         'to', jsonb_build_object('date', coalesce(v_date, old_r.rev_date), 'note', v_note)),
      coalesce(public.project_label(it.project_id), 'عام'));
  end if;
  return p_id;
end;
$$;

-- حذف إصدار (ليس الوحيد): المدير، أو منشئه خلال 24 ساعة. يعيد مسارات ملفاته لحذفها من الحاوية.
create or replace function public.delete_doc_revision(p_id uuid)
returns text[]
language plpgsql security definer set search_path = public
as $$
declare
  r      public.doc_revisions;
  it     public.doc_items;
  v_paths text[];
begin
  select * into r from public.doc_revisions where id = p_id for update;
  if not found then
    raise exception 'الإصدار غير موجود' using errcode = 'P0002';
  end if;
  select * into it from public.doc_items where id = r.item_id for update;
  if not (public.is_director()
          or (public.doc_can_edit(it.kind, it.project_id) and r.created_by = auth.uid() and r.created_at > now() - interval '24 hours')) then
    raise exception 'حذف الإصدار للمدير، أو لمن أضافه خلال 24 ساعة' using errcode = '42501';
  end if;
  if (select count(*) from public.doc_revisions where item_id = r.item_id) <= 1 then
    raise exception 'هذا هو الإصدار الوحيد؛ احذف المستند نفسه بدلاً منه' using errcode = '22023';
  end if;
  select coalesce(array_agg(path), '{}') into v_paths from public.doc_files where revision_id = p_id;
  delete from public.doc_revisions where id = p_id;
  perform public.write_audit('doc.revision_delete', it.project_id, null,
    jsonb_build_object('item_id', it.id, 'kind', it.kind, 'title', it.title, 'rev_no', r.rev_no, 'files', coalesce(array_length(v_paths, 1), 0)),
    coalesce(public.project_label(it.project_id), 'عام'));
  return v_paths;
end;
$$;

-- حذف مستند بكل إصداراته: المدير وحده. يعيد مسارات الملفات.
create or replace function public.delete_doc_item(p_id uuid)
returns text[]
language plpgsql security definer set search_path = public
as $$
declare
  it      public.doc_items;
  v_paths text[];
begin
  if not public.is_director() then
    raise exception 'حذف المستندات من صلاحية مدير المكتب وحده' using errcode = '42501';
  end if;
  select * into it from public.doc_items where id = p_id for update;
  if not found then
    raise exception 'المستند غير موجود' using errcode = 'P0002';
  end if;
  select coalesce(array_agg(f.path), '{}') into v_paths
    from public.doc_files f join public.doc_revisions r on r.id = f.revision_id where r.item_id = p_id;
  delete from public.doc_items where id = p_id;
  perform public.write_audit('doc.delete', it.project_id, null,
    jsonb_build_object('item_id', it.id, 'kind', it.kind, 'title', it.title, 'ref_no', it.ref_no,
                       'files', coalesce(array_length(v_paths, 1), 0)),
    coalesce(public.project_label(it.project_id), 'عام'));
  return v_paths;
end;
$$;

-- ---------------------------------------------------------------------
-- 5. الدوال: التقارير اليومية
-- ---------------------------------------------------------------------
create or replace function public.save_site_report(p_id uuid, p_data jsonb)
returns uuid
language plpgsql security definer set search_path = public
as $$
declare
  old_row public.site_reports;
  new_row public.site_reports;
  v_proj  uuid;
  v_date  date := public.jdate(p_data, 'report_date', 'تاريخ التقرير');
  v_work  uuid;
  v_done  text := public.jtext(p_data, 'works_done', 4000, 'الأعمال المنفذة');
  v_skip  text[] := array['updated_at', 'updated_by'];
  v_ch    jsonb;
begin
  if jsonb_typeof(coalesce(p_data, 'null'::jsonb)) <> 'object' then
    raise exception 'بيانات غير صالحة' using errcode = '22023';
  end if;
  if p_id is not null then
    select * into old_row from public.site_reports where id = p_id for update;
    if not found then
      raise exception 'التقرير غير موجود' using errcode = 'P0002';
    end if;
    v_proj := old_row.project_id;
    v_date := coalesce(v_date, old_row.report_date);
  else
    v_proj := public.jproject(p_data, 'project_id', true);
  end if;
  if not public.site_report_can_edit(v_proj) then
    raise exception 'التقرير اليومي يرفعه مكتب المدير ورئيس القسم المشرف على العقد' using errcode = '42501';
  end if;
  if v_date is null then
    raise exception 'حدّد تاريخ التقرير' using errcode = '22023';
  end if;
  if v_date > current_date + 1 then
    raise exception 'لا يُسجَّل تقرير ليوم لم يأتِ بعد' using errcode = '22023';
  end if;
  if length(v_done) < 3 then
    raise exception 'اكتب الأعمال المنفذة' using errcode = '22023';
  end if;
  if nullif(p_data ->> 'work_id', '') is not null then
    begin
      v_work := (p_data ->> 'work_id')::uuid;
    exception when others then
      raise exception 'عمل غير صالح' using errcode = '22023';
    end;
    if not exists (select 1 from public.contract_works where id = v_work and project_id = v_proj) then
      raise exception 'العمل المختار لا يتبع هذا العقد' using errcode = '22023';
    end if;
  end if;
  if exists (select 1 from public.site_reports s
              where s.project_id = v_proj and s.report_date = v_date and s.work_id is not distinct from v_work
                and s.id is distinct from p_id) then
    raise exception 'يوجد تقرير لهذا العقد في التاريخ نفسه؛ افتحه وعدّله' using errcode = '23505';
  end if;

  if p_id is null then
    insert into public.site_reports (project_id, work_id, report_date, weather, temp_c, workers, equipment, works_done, materials,
                                     issues, safety, next_plan, progress_pct, notes, created_by, updated_by)
    values (v_proj, v_work, v_date,
            public.jpick(p_data, 'weather', array['clear', 'cloudy', 'rain', 'wind', 'dust', 'hot', 'cold'], 'clear', 'الطقس'),
            public.jint(p_data, 'temp_c', -20, 60, 'درجة الحرارة'), public.jint(p_data, 'workers', 0, 5000, 'عدد العمالة'),
            public.jtext(p_data, 'equipment', 1000, 'المعدات'), v_done, public.jtext(p_data, 'materials', 1500, 'المواد الموردة'),
            public.jtext(p_data, 'issues', 2000, 'المعوقات والملاحظات'), public.jtext(p_data, 'safety', 1500, 'السلامة'),
            public.jtext(p_data, 'next_plan', 1500, 'خطة اليوم التالي'),
            public.jnum(p_data, 'progress_pct', 0, 100, 'نسبة الإنجاز التقديرية'), public.jtext(p_data, 'notes', 1500, 'ملاحظات'),
            auth.uid(), auth.uid())
    returning * into new_row;
    perform public.write_audit('report.create', v_proj, null,
      jsonb_build_object('report_id', new_row.id, 'date', v_date, 'workers', new_row.workers));
  else
    update public.site_reports set
      work_id = v_work, report_date = v_date,
      weather = public.jpick(p_data, 'weather', array['clear', 'cloudy', 'rain', 'wind', 'dust', 'hot', 'cold'], 'clear', 'الطقس'),
      temp_c = public.jint(p_data, 'temp_c', -20, 60, 'درجة الحرارة'), workers = public.jint(p_data, 'workers', 0, 5000, 'عدد العمالة'),
      equipment = public.jtext(p_data, 'equipment', 1000, 'المعدات'), works_done = v_done,
      materials = public.jtext(p_data, 'materials', 1500, 'المواد الموردة'),
      issues = public.jtext(p_data, 'issues', 2000, 'المعوقات والملاحظات'), safety = public.jtext(p_data, 'safety', 1500, 'السلامة'),
      next_plan = public.jtext(p_data, 'next_plan', 1500, 'خطة اليوم التالي'),
      progress_pct = public.jnum(p_data, 'progress_pct', 0, 100, 'نسبة الإنجاز التقديرية'),
      notes = public.jtext(p_data, 'notes', 1500, 'ملاحظات'),
      updated_at = now(), updated_by = auth.uid()
    where id = p_id
    returning * into new_row;
    v_ch := public.jsonb_changes(to_jsonb(old_row), to_jsonb(new_row), v_skip);
    if v_ch <> '{}'::jsonb then
      perform public.write_audit('report.update', v_proj, null,
        jsonb_build_object('report_id', p_id, 'date', v_date, 'changes', v_ch));
    end if;
  end if;
  return new_row.id;
end;
$$;

-- اطلاع المدير على التقرير مع ملاحظة (أو إلغاء الاطلاع بتمرير p_reviewed = false)
create or replace function public.review_site_report(p_id uuid, p_reviewed boolean, p_note text default '')
returns void
language plpgsql security definer set search_path = public
as $$
declare
  r public.site_reports;
begin
  if not public.is_director() then
    raise exception 'الاطلاع على التقارير واعتمادها لمدير المكتب' using errcode = '42501';
  end if;
  if length(coalesce(p_note, '')) > 1000 then
    raise exception 'الملاحظة أطول من 1000 حرف' using errcode = '22023';
  end if;
  select * into r from public.site_reports where id = p_id for update;
  if not found then
    raise exception 'التقرير غير موجود' using errcode = 'P0002';
  end if;
  update public.site_reports set
    reviewed_by = case when p_reviewed then auth.uid() end,
    reviewed_at = case when p_reviewed then now() end,
    review_note = case when p_reviewed then btrim(coalesce(p_note, '')) else '' end
  where id = p_id;
  perform public.write_audit('report.review', r.project_id, null,
    jsonb_build_object('report_id', p_id, 'date', r.report_date, 'reviewed', p_reviewed, 'note', btrim(coalesce(p_note, ''))));
end;
$$;

-- حذف تقرير: المدير، أو من أضافه خلال 24 ساعة. يعيد مسارات ملفاته.
create or replace function public.delete_site_report(p_id uuid)
returns text[]
language plpgsql security definer set search_path = public
as $$
declare
  r       public.site_reports;
  v_paths text[];
begin
  select * into r from public.site_reports where id = p_id for update;
  if not found then
    raise exception 'التقرير غير موجود' using errcode = 'P0002';
  end if;
  if not (public.is_director()
          or (public.site_report_can_edit(r.project_id) and r.created_by = auth.uid() and r.created_at > now() - interval '24 hours')) then
    raise exception 'حذف التقرير للمدير، أو لمن أضافه خلال 24 ساعة' using errcode = '42501';
  end if;
  select coalesce(array_agg(path), '{}') into v_paths from public.doc_files where report_id = p_id;
  delete from public.site_reports where id = p_id;
  perform public.write_audit('report.delete', r.project_id, null,
    jsonb_build_object('report_id', p_id, 'date', r.report_date, 'works_done', left(r.works_done, 200),
                       'files', coalesce(array_length(v_paths, 1), 0)));
  return v_paths;
end;
$$;

-- ---------------------------------------------------------------------
-- 6. الدوال: الملفات المرفقة
-- ---------------------------------------------------------------------
-- تسجيل ملف بعد رفعه إلى الحاوية. النوع والحجم يُؤخذان من الحاوية نفسها لا من التطبيق.
create or replace function public.add_doc_file(p_path text, p_name text, p_width integer default null, p_height integer default null)
returns uuid
language plpgsql security definer set search_path = public
as $$
declare
  v_scope text := split_part(coalesce(p_path, ''), '/', 1);
  v_owner uuid;
  v_mime  text;
  v_size  bigint;
  v_name  text := btrim(coalesce(p_name, ''));
  v_id    uuid;
  v_n     integer;
  it      public.doc_items;
  rv      public.doc_revisions;
  rp      public.site_reports;
begin
  if not public.can_upload_doc_path(p_path) then
    raise exception 'لا تملك صلاحية إرفاق ملف هنا' using errcode = '42501';
  end if;
  if length(v_name) < 1 or length(v_name) > 200 then
    raise exception 'اسم الملف غير صالح' using errcode = '22023';
  end if;
  v_owner := split_part(p_path, '/', 2)::uuid;
  if to_regclass('storage.objects') is not null then
    execute 'select metadata ->> ''mimetype'', (metadata ->> ''size'')::bigint from storage.objects where bucket_id = ''docs'' and name = $1'
      into v_mime, v_size using p_path;
    if v_size is null then
      raise exception 'لم يكتمل رفع الملف؛ أعد المحاولة' using errcode = 'P0002';
    end if;
  end if;
  v_mime := lower(coalesce(v_mime, case
    when p_path ~* '\.pdf$' then 'application/pdf' when p_path ~* '\.png$' then 'image/png'
    when p_path ~* '\.webp$' then 'image/webp' when p_path ~* '\.gif$' then 'image/gif' else 'image/jpeg' end));
  if v_mime not in ('application/pdf', 'image/jpeg', 'image/png', 'image/webp', 'image/gif') then
    raise exception 'نوع الملف غير مسموح؛ المسموح PDF والصور' using errcode = '22023';
  end if;
  v_size := coalesce(v_size, 1);
  if v_size > 20971520 then
    raise exception 'حجم الملف أكبر من 20 ميجابايت' using errcode = '22023';
  end if;

  if v_scope = 'doc' then
    select * into rv from public.doc_revisions where id = v_owner;
    select * into it from public.doc_items where id = rv.item_id;
    select count(*) into v_n from public.doc_files where revision_id = v_owner;
    if v_n >= 40 then
      raise exception 'الحد الأعلى 40 ملفاً للإصدار الواحد' using errcode = '22023';
    end if;
    insert into public.doc_files (revision_id, path, name, mime, size_bytes, width, height, sort, created_by)
    values (v_owner, p_path, v_name, v_mime, v_size, p_width, p_height, v_n + 1, auth.uid())
    returning id into v_id;
    perform public.write_audit('doc.file_add', it.project_id, null,
      jsonb_build_object('item_id', it.id, 'kind', it.kind, 'title', it.title, 'rev_no', rv.rev_no, 'file', v_name, 'size', v_size),
      coalesce(public.project_label(it.project_id), 'عام'));
  else
    select * into rp from public.site_reports where id = v_owner;
    select count(*) into v_n from public.doc_files where report_id = v_owner;
    if v_n >= 40 then
      raise exception 'الحد الأعلى 40 ملفاً للتقرير الواحد' using errcode = '22023';
    end if;
    insert into public.doc_files (report_id, path, name, mime, size_bytes, width, height, sort, created_by)
    values (v_owner, p_path, v_name, v_mime, v_size, p_width, p_height, v_n + 1, auth.uid())
    returning id into v_id;
    perform public.write_audit('report.file_add', rp.project_id, null,
      jsonb_build_object('report_id', rp.id, 'date', rp.report_date, 'file', v_name, 'size', v_size));
  end if;
  return v_id;
end;
$$;

-- إزالة ملف مرفق: المدير، أو من رفعه خلال 24 ساعة. يعيد مساره لحذفه من الحاوية.
create or replace function public.delete_doc_file(p_id uuid)
returns text
language plpgsql security definer set search_path = public
as $$
declare
  f    public.doc_files;
  v_p  uuid;
  v_ok boolean;
begin
  select * into f from public.doc_files where id = p_id for update;
  if not found then
    raise exception 'الملف غير موجود' using errcode = 'P0002';
  end if;
  if f.revision_id is not null then
    select i.project_id, public.doc_can_edit(i.kind, i.project_id) into v_p, v_ok
      from public.doc_revisions r join public.doc_items i on i.id = r.item_id where r.id = f.revision_id;
  else
    select project_id, public.site_report_can_edit(project_id) into v_p, v_ok from public.site_reports where id = f.report_id;
  end if;
  if not (public.is_director() or (v_ok and f.created_by = auth.uid() and f.created_at > now() - interval '24 hours')) then
    raise exception 'إزالة الملف للمدير، أو لمن رفعه خلال 24 ساعة' using errcode = '42501';
  end if;
  delete from public.doc_files where id = p_id;
  perform public.write_audit(case when f.revision_id is not null then 'doc.file_delete' else 'report.file_delete' end, v_p, null,
    jsonb_build_object('file', f.name, 'size', f.size_bytes, 'revision_id', f.revision_id, 'report_id', f.report_id));
  return f.path;
end;
$$;

-- مؤشر المساحة: المستخدم من حاوية المستندات وملفات الإصدارات، من حد الخطة (1 جيجابايت افتراضياً)
create or replace function public.docs_storage_usage()
returns jsonb
language plpgsql stable security definer set search_path = public
as $$
declare
  v_docs bigint := 0;
  v_rel  bigint := 0;
  v_n    integer := 0;
begin
  if not public.is_member() then
    raise exception 'غير مصرح' using errcode = '42501';
  end if;
  if to_regclass('storage.objects') is not null then
    execute 'select coalesce(sum((metadata ->> ''size'')::bigint) filter (where bucket_id = ''docs''), 0),
                    coalesce(sum((metadata ->> ''size'')::bigint) filter (where bucket_id <> ''docs''), 0),
                    count(*) filter (where bucket_id = ''docs'')::integer
               from storage.objects'
      into v_docs, v_rel, v_n;
  else
    select coalesce(sum(size_bytes), 0), count(*)::integer into v_docs, v_n from public.doc_files;
  end if;
  return jsonb_build_object('docs_bytes', v_docs, 'other_bytes', v_rel, 'files', v_n,
                            'limit_bytes', coalesce(public.setting_num('storage.limit_bytes', 1073741824), 1073741824));
end;
$$;

-- الملفات اليتيمة في الحاوية (رُفعت ولم تُسجَّل، أو بقيت بعد حذف سجلها) الأقدم من ساعة: للمدير لتنظيفها
-- (نسخة PDF من دليل الاستخدام تحت manual/ يرفعها سير عمل الإصدار، فلا تُعد يتيمة)
create or replace function public.docs_orphan_paths()
returns text[]
language plpgsql stable security definer set search_path = public
as $$
declare
  v text[] := '{}';
begin
  if not public.is_director() then
    raise exception 'للمدير وحده' using errcode = '42501';
  end if;
  if to_regclass('storage.objects') is not null then
    execute 'select coalesce(array_agg(o.name order by o.name), ''{}'') from storage.objects o
              where o.bucket_id = ''docs'' and o.created_at < now() - interval ''1 hour''
                and o.name !~ ''^manual/''
                and not exists (select 1 from public.doc_files f where f.path = o.name)'
      into v;
  end if;
  return v;
end;
$$;

-- ---------------------------------------------------------------------
-- 7. اتباع الدمج
-- ---------------------------------------------------------------------
create or replace function public.docs_follow_merge()
returns trigger
language plpgsql security definer set search_path = public
as $$
begin
  if new.merged_into is not null and old.merged_into is null then
    update public.doc_items set project_id = new.merged_into, origin_project = coalesce(origin_project, new.id)
     where project_id = new.id;
    update public.site_reports s set project_id = new.merged_into, origin_project = coalesce(s.origin_project, new.id)
     where s.project_id = new.id
       and not exists (select 1 from public.site_reports x
                        where x.project_id = new.merged_into and x.report_date = s.report_date
                          and x.work_id is not distinct from s.work_id);
  elsif new.merged_into is null and old.merged_into is not null then
    update public.doc_items set project_id = new.id, origin_project = null
     where project_id = old.merged_into and origin_project = new.id;
    update public.site_reports set project_id = new.id, origin_project = null
     where project_id = old.merged_into and origin_project = new.id;
  end if;
  return null;
end;
$$;
drop trigger if exists projects_docs_follow_merge on public.projects;
create trigger projects_docs_follow_merge after update of merged_into on public.projects
  for each row when (old.merged_into is distinct from new.merged_into) execute function public.docs_follow_merge();

-- ---------------------------------------------------------------------
-- 8. القراءة والصلاحيات والتحديث اللحظي
-- ---------------------------------------------------------------------
do $$
declare
  t text;
begin
  foreach t in array array['doc_items', 'doc_revisions', 'doc_files', 'site_reports'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('drop policy if exists %I on public.%I', t || '_read', t);
    execute format('create policy %I on public.%I for select to authenticated using ((select public.is_member()))', t || '_read', t);
    execute format('revoke all on public.%I from anon', t);
    execute format('revoke insert, update, delete, truncate on public.%I from authenticated', t);
    execute format('grant select on public.%I to authenticated', t);
    execute format('grant all on public.%I to service_role', t);
    if not exists (select 1 from pg_publication_tables
                   where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = t) then
      execute format('alter publication supabase_realtime add table public.%I', t);
    end if;
  end loop;
end $$;

revoke execute on function public.docs_follow_merge(), public.doc_kind_label(text) from public, anon, authenticated;
revoke execute on function
  public.doc_can_edit(text, uuid), public.site_report_can_edit(uuid), public.can_upload_doc_path(text),
  public.save_doc_item(uuid, jsonb), public.save_doc_revision(uuid, uuid, jsonb), public.delete_doc_revision(uuid),
  public.delete_doc_item(uuid), public.save_site_report(uuid, jsonb), public.review_site_report(uuid, boolean, text),
  public.delete_site_report(uuid), public.add_doc_file(text, text, integer, integer), public.delete_doc_file(uuid),
  public.docs_storage_usage(), public.docs_orphan_paths()
from public, anon;
grant execute on function
  public.doc_can_edit(text, uuid), public.site_report_can_edit(uuid), public.can_upload_doc_path(text),
  public.save_doc_item(uuid, jsonb), public.save_doc_revision(uuid, uuid, jsonb), public.delete_doc_revision(uuid),
  public.delete_doc_item(uuid), public.save_site_report(uuid, jsonb), public.review_site_report(uuid, boolean, text),
  public.delete_site_report(uuid), public.add_doc_file(text, text, integer, integer), public.delete_doc_file(uuid),
  public.docs_storage_usage(), public.docs_orphan_paths()
to authenticated;

notify pgrst, 'reload schema';
