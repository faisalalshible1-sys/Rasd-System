-- =====================================================================
--  الترحيل 35: ملف العقد ومرفقاته
--   مرفقات مصنّفة لكل عقد على نظام المستندات القائم نفسه (doc_items/doc_revisions/doc_files):
--     نوع مستند جديد «attachment» بتسعة تصنيفات: العقد، المقايسة، المخططات، محاضر الاستلام، قرارات التكليف،
--     المستخلصات، أوامر التغيير، المراسلات، أخرى — ولكل مرفق وصف وتاريخ ورقم، وإصدارات تحفظ السابق عند الاستبدال.
--   قرار التكليف يُربط بالمهندس المكلَّف نفسه (engineer_id).
--   أنواع الملفات: PDF وWord وExcel وPowerPoint والصور وDWG وDXF وRevit والمضغوط وKML/KMZ وCSV والنص، حتى 50 ميغابايت.
--   الاطلاع: من يرى العقد بتفاصيله (مكتب المدير ومكتب العقود والقسم المشرف). الكتابة: هؤلاء، والحذف للمدير وحده.
--   لا يمس بيانات قائمة: يوسّع القيود والدوال فقط. التراجع: supabase/rollbacks/20261126000035_contract_files_down.sql
--  يُشغَّل بعد 20261123000034_section_isolation.sql. إعادة تشغيله آمنة.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. نوع «مرفق العقد» في جدول المستندات
-- ---------------------------------------------------------------------
alter table public.doc_items
  add column if not exists engineer_id uuid references public.contract_engineers(id) on delete set null;
create index if not exists doc_items_engineer_idx on public.doc_items (engineer_id) where engineer_id is not null;

alter table public.doc_items drop constraint if exists doc_items_kind_check;
alter table public.doc_items add constraint doc_items_kind_check
  check (kind = any (array['boq', 'letter', 'design', 'attachment']));

alter table public.doc_items drop constraint if exists doc_items_kind_fields;
alter table public.doc_items add constraint doc_items_kind_fields check (
     (kind = 'boq' and category = any (array['estimate', 'contract', 'variation', 'final'])
        and status = any (array['draft', 'review', 'approved']) and direction is null)
  or (kind = 'letter' and category = any (array['', 'contract', 'finance', 'technical', 'admin', 'other'])
        and status = any (array['open', 'closed', 'info']) and direction is not null)
  or (kind = 'design' and category = any (array['architectural', 'structural', 'electrical', 'mechanical', 'plumbing', 'landscape',
                                                'urban', 'heritage', 'other'])
        and status = any (array['draft', 'review', 'approved']) and direction is null)
  or (kind = 'attachment' and category = any (array['contract', 'boq', 'drawings', 'handover', 'assignment', 'extract', 'variation',
                                                    'correspondence', 'other'])
        and status = 'active' and direction is null and project_id is not null));

-- قرار التكليف وحده يرتبط بمهندس
alter table public.doc_items drop constraint if exists doc_items_engineer_link;
alter table public.doc_items add constraint doc_items_engineer_link
  check (engineer_id is null or (kind = 'attachment' and category = 'assignment'));

create or replace function public.doc_kind_label(p_kind text)
returns text
language sql immutable set search_path = public
as $$
  select case p_kind when 'boq' then 'مقايسة' when 'letter' then 'مراسلة' when 'design' then 'تصميم'
                     when 'attachment' then 'مرفق عقد' else p_kind end
$$;

-- امتدادات المرفقات وأنواعها كما تُرفع (المسار يحدد الامتداد، والنوع يجب أن يطابقه)
create or replace function public.attachment_mime(p_ext text)
returns text
language sql immutable set search_path = public
as $$
  select case lower(coalesce(p_ext, ''))
    when 'pdf'  then 'application/pdf'
    when 'jpg'  then 'image/jpeg'
    when 'jpeg' then 'image/jpeg'
    when 'png'  then 'image/png'
    when 'webp' then 'image/webp'
    when 'gif'  then 'image/gif'
    when 'heic' then 'image/heic'
    when 'doc'  then 'application/msword'
    when 'docx' then 'application/vnd.openxmlformats-officedocument.wordprocessingml.document'
    when 'xls'  then 'application/vnd.ms-excel'
    when 'xlsx' then 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'
    when 'ppt'  then 'application/vnd.ms-powerpoint'
    when 'pptx' then 'application/vnd.openxmlformats-officedocument.presentationml.presentation'
    when 'csv'  then 'text/csv'
    when 'txt'  then 'text/plain'
    when 'dwg'  then 'image/vnd.dwg'
    when 'dxf'  then 'image/vnd.dxf'
    when 'rvt'  then 'application/vnd.autodesk.revit'
    when 'zip'  then 'application/zip'
    when 'rar'  then 'application/vnd.rar'
    when '7z'   then 'application/x-7z-compressed'
    when 'kml'  then 'application/vnd.google-earth.kml+xml'
    when 'kmz'  then 'application/vnd.google-earth.kmz'
  end
$$;

-- ---------------------------------------------------------------------
-- 2. الصلاحيات
-- ---------------------------------------------------------------------

-- مرفقات العقد: من يرى العقد بتفاصيله يكتب فيها (مكتب المدير ومكتب العقود والقسم المشرف لعقوده)
create or replace function public.doc_can_edit(p_kind text, p_project uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
  select case when p_kind = 'attachment' then
           public.writes_allowed() and p_project is not null
           and (public.project_full_all() or p_project = any (public.my_supervised()))
           and exists (select 1 from public.projects where id = p_project and merged_into is null)
         else
           public.sees_section('docs') and (
             coalesce(public.doc_can_edit_v22(p_kind, p_project), false)
             or (public.writes_allowed() and p_kind in ('boq', 'letter', 'design') and public.has_grant('docs:' || p_kind)
                 and (p_project is null or exists (select 1 from public.projects where id = p_project and merged_into is null))))
         end
$$;

-- القراءة: مستندات الشؤون الفنية كما كانت، ومرفقات العقد لمن يرى العقد بتفاصيله
drop policy if exists doc_items_read on public.doc_items;
create policy doc_items_read on public.doc_items for select to authenticated
  using (case when kind = 'attachment'
              then (select public.project_full_all()) or project_id = any ((select public.my_supervised())::uuid[])
              else (select public.sees_section('docs'))
                   or (project_id is not null and project_id = any ((select public.my_supervised())::uuid[]))
         end);

-- الإصدارات تتبع مستندها وحده (لا يكفي قسم الشؤون الفنية لقراءة إصدارات مرفقات العقود)
drop policy if exists doc_revisions_read on public.doc_revisions;
create policy doc_revisions_read on public.doc_revisions for select to authenticated
  using (exists (select 1 from public.doc_items i where i.id = doc_revisions.item_id));

-- ---------------------------------------------------------------------
-- 3. حفظ المستند (بنوع المرفق)
-- ---------------------------------------------------------------------
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
  v_eng    uuid;
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
    v_kind := public.jpick(p_data, 'kind', array['boq', 'letter', 'design', 'attachment'], null, 'نوع المستند');
    if v_kind is null then
      raise exception 'اختر نوع المستند' using errcode = '22023';
    end if;
    v_proj := public.jproject(p_data, 'project_id', false);
  end if;
  if v_kind = 'attachment' and v_proj is null then
    raise exception 'اختر العقد الذي يتبعه المرفق' using errcode = '22023';
  end if;
  if not public.doc_can_edit(v_kind, v_proj) then
    raise exception 'لا تملك صلاحية إضافة % لهذا العقد', public.doc_kind_label(v_kind) using errcode = '42501';
  end if;
  if length(v_title) < 2 then
    raise exception 'اكتب % المستند', case when v_kind = 'attachment' then 'وصف' else 'عنوان' end using errcode = '22023';
  end if;

  v_cat := case v_kind
    when 'boq'        then public.jpick(p_data, 'category', array['estimate', 'contract', 'variation', 'final'], 'estimate', 'نوع المقايسة')
    when 'letter'     then public.jpick(p_data, 'category', array['', 'contract', 'finance', 'technical', 'admin', 'other'], '', 'تصنيف المراسلة')
    when 'attachment' then public.jpick(p_data, 'category', array['contract', 'boq', 'drawings', 'handover', 'assignment', 'extract',
                                                                  'variation', 'correspondence', 'other'], 'other', 'تصنيف المرفق')
    else public.jpick(p_data, 'category', array['architectural', 'structural', 'electrical', 'mechanical', 'plumbing', 'landscape',
                                                 'urban', 'heritage', 'other'], 'architectural', 'تخصص التصميم') end;
  v_stat := case v_kind
    when 'letter'     then public.jpick(p_data, 'status', array['open', 'closed', 'info'], 'open', 'حالة المراسلة')
    when 'attachment' then 'active'
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

  -- قرار التكليف: يُربط بمهندس مكلَّف في العقد نفسه
  if v_kind = 'attachment' and v_cat = 'assignment' and nullif(p_data ->> 'engineer_id', '') is not null then
    begin
      v_eng := (p_data ->> 'engineer_id')::uuid;
    exception when others then
      raise exception 'المهندس المكلَّف غير صالح' using errcode = '22023';
    end;
    if not exists (select 1 from public.contract_engineers where id = v_eng and project_id = v_proj) then
      raise exception 'المهندس المختار ليس من تكليفات هذا العقد' using errcode = '22023';
    end if;
  end if;

  if p_id is null then
    insert into public.doc_items (kind, project_id, title, ref_no, doc_date, category, direction, party, amount, status, reply_to,
                                  due_date, notes, engineer_id, created_by, updated_by)
    values (v_kind, v_proj, v_title, public.jtext(p_data, 'ref_no', 60, 'الرقم'),
            coalesce(public.jdate(p_data, 'doc_date', 'التاريخ'), current_date), v_cat, v_dir,
            public.jtext(p_data, 'party', 120, 'الجهة'),
            case when v_kind = 'boq' then public.jnum(p_data, 'amount', 0, 1e13, 'القيمة الإجمالية') end,
            v_stat, v_reply,
            case when v_kind = 'letter' then public.jdate(p_data, 'due_date', 'موعد الرد') end,
            public.jtext(p_data, 'notes', 2000, 'ملاحظات'), v_eng, auth.uid(), auth.uid())
    returning * into new_row;
    insert into public.doc_revisions (item_id, rev_no, rev_date, note, created_by, updated_by)
    values (new_row.id, 1, new_row.doc_date, public.jtext(p_data, 'rev_note', 1000, 'ملاحظة الإصدار'), auth.uid(), auth.uid())
    returning id into v_rev;
    perform public.write_audit('doc.create', v_proj, null,
      jsonb_build_object('item_id', new_row.id, 'kind', v_kind, 'title', v_title, 'ref_no', new_row.ref_no, 'category', v_cat),
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
      engineer_id = v_eng,
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

-- ---------------------------------------------------------------------
-- 4. رفع الملفات: كل الأنواع الهندسية والمكتبية للمرفقات، وكما كانت لبقية المستندات
-- ---------------------------------------------------------------------
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
  if p_name is null or p_name !~ '^(doc|report|unit)/[0-9a-f-]{36}/[A-Za-z0-9_-]{8,64}\.[a-z0-9]{2,5}$' then
    return false;
  end if;
  v_owner := split_part(p_name, '/', 2)::uuid;
  if v_scope = 'doc' then
    select i.kind, i.project_id into v_kind, v_proj
      from public.doc_revisions r join public.doc_items i on i.id = r.item_id where r.id = v_owner;
    if not found then
      return false;
    end if;
    if v_kind = 'attachment' then
      -- مرفقات العقد: الأنواع المعروفة وحدها (لا ملفات تنفيذية)
      if public.attachment_mime(substring(p_name from '\.([a-z0-9]{2,5})$')) is null then
        return false;
      end if;
    elsif p_name !~ '\.(pdf|jpg|jpeg|png|webp|gif|mp4|mov|webm)$' then
      return false;
    elsif v_kind <> 'design' and p_name ~ '\.(mp4|mov|webm)$' then
      -- الفيديو في التصاميم وحدها من بين المستندات
      return false;
    end if;
    return public.doc_can_edit(v_kind, v_proj);
  end if;
  if p_name !~ '\.(pdf|jpg|jpeg|png|webp|gif|mp4|mov|webm)$' then
    return false;
  end if;
  if v_scope = 'unit' then
    select kind into v_unit from public.unit_records where id = v_owner;
    return found and public.unit_kind_can_edit(v_unit);
  end if;
  select project_id into v_proj from public.site_reports where id = v_owner;
  return found and public.site_report_can_edit(v_proj);
end;
$$;

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
  v_ext   text := lower(substring(coalesce(p_path, '') from '\.([a-z0-9]{2,5})$'));
  v_att   boolean := false;
  v_id    uuid;
  v_n     integer;
  it      public.doc_items;
  rv      public.doc_revisions;
  rp      public.site_reports;
  ur      public.unit_records;
begin
  if not public.can_upload_doc_path(p_path) then
    raise exception 'لا تملك صلاحية إرفاق ملف هنا' using errcode = '42501';
  end if;
  if length(v_name) < 1 or length(v_name) > 200 then
    raise exception 'اسم الملف غير صالح' using errcode = '22023';
  end if;
  v_owner := split_part(p_path, '/', 2)::uuid;
  if v_scope = 'doc' then
    select * into rv from public.doc_revisions where id = v_owner;
    select * into it from public.doc_items where id = rv.item_id;
    v_att := it.kind = 'attachment';
  end if;
  if to_regclass('storage.objects') is not null then
    execute 'select metadata ->> ''mimetype'', (metadata ->> ''size'')::bigint from storage.objects where bucket_id = ''docs'' and name = $1'
      into v_mime, v_size using p_path;
    if v_size is null then
      raise exception 'لم يكتمل رفع الملف؛ أعد المحاولة' using errcode = 'P0002';
    end if;
  end if;
  if v_att then
    -- نوع الملف يتبع امتداده دائماً
    if v_mime is not null and lower(v_mime) <> public.attachment_mime(v_ext)
       and not (lower(v_mime) in ('application/octet-stream', 'binary/octet-stream')) then
      raise exception 'نوع الملف لا يطابق امتداده (%)', v_ext using errcode = '22023';
    end if;
    v_mime := public.attachment_mime(v_ext);
    v_size := coalesce(v_size, 1);
    if v_size > 52428800 then
      raise exception 'حجم الملف أكبر من 50 ميجابايت' using errcode = '22023';
    end if;
  else
    v_mime := lower(coalesce(v_mime, case
      when p_path ~* '\.pdf$' then 'application/pdf' when p_path ~* '\.png$' then 'image/png'
      when p_path ~* '\.webp$' then 'image/webp' when p_path ~* '\.gif$' then 'image/gif'
      when p_path ~* '\.mp4$' then 'video/mp4' when p_path ~* '\.mov$' then 'video/quicktime'
      when p_path ~* '\.webm$' then 'video/webm' else 'image/jpeg' end));
    if v_mime not in ('application/pdf', 'image/jpeg', 'image/png', 'image/webp', 'image/gif', 'video/mp4', 'video/quicktime', 'video/webm') then
      raise exception 'نوع الملف غير مسموح؛ المسموح PDF والصور والفيديو' using errcode = '22023';
    end if;
    v_size := coalesce(v_size, 1);
    if v_mime like 'video/%' and v_size > 52428800 then
      raise exception 'حجم الفيديو أكبر من 50 ميجابايت' using errcode = '22023';
    end if;
    if v_mime not like 'video/%' and v_size > 20971520 then
      raise exception 'حجم الملف أكبر من 20 ميجابايت' using errcode = '22023';
    end if;
  end if;

  if v_scope = 'doc' then
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
  elsif v_scope = 'unit' then
    select * into ur from public.unit_records where id = v_owner;
    select count(*) into v_n from public.doc_files where record_id = v_owner;
    if v_n >= 40 then
      raise exception 'الحد الأعلى 40 ملفاً للسجل الواحد' using errcode = '22023';
    end if;
    insert into public.doc_files (record_id, path, name, mime, size_bytes, width, height, sort, created_by)
    values (v_owner, p_path, v_name, v_mime, v_size, p_width, p_height, v_n + 1, auth.uid())
    returning id into v_id;
    perform public.write_audit('unit.file_add', ur.project_id, null,
      jsonb_build_object('record_id', ur.id, 'unit', ur.unit, 'kind', ur.kind, 'title', ur.title, 'file', v_name, 'size', v_size),
      coalesce(public.project_label(ur.project_id), (select name from public.org_units where key = ur.unit)));
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

-- حاوية الملفات: الأنواع الجديدة بحد 50 ميغابايت (تتحقق add_doc_file من النوع والحجم لكل مستند بعد الرفع)
do $$
begin
  if to_regclass('storage.buckets') is null then
    return;
  end if;
  update storage.buckets set
    file_size_limit = 52428800,
    allowed_mime_types = array(select distinct x from unnest(coalesce(allowed_mime_types, '{}'::text[]) || array[
      'application/pdf', 'image/jpeg', 'image/png', 'image/webp', 'image/gif', 'image/heic', 'video/mp4', 'video/quicktime', 'video/webm',
      'application/msword', 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      'application/vnd.ms-excel', 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      'application/vnd.ms-powerpoint', 'application/vnd.openxmlformats-officedocument.presentationml.presentation',
      'text/csv', 'text/plain', 'image/vnd.dwg', 'image/vnd.dxf', 'application/vnd.autodesk.revit',
      'application/zip', 'application/vnd.rar', 'application/x-7z-compressed',
      'application/vnd.google-earth.kml+xml', 'application/vnd.google-earth.kmz']) x order by x)
  where id = 'docs';
end $$;

-- قيود سجل الملفات: أنواع المرفقات وحد 50 ميغابايت (حد كل مستند تفرضه add_doc_file: 20 ميغابايت لغير المرفقات والفيديو)
alter table public.doc_files drop constraint if exists doc_files_mime_check;
alter table public.doc_files add constraint doc_files_mime_check
  check (mime in ('application/pdf', 'image/jpeg', 'image/png', 'image/webp', 'image/gif', 'video/mp4', 'video/quicktime', 'video/webm',
                  'image/heic', 'application/msword', 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
                  'application/vnd.ms-excel', 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
                  'application/vnd.ms-powerpoint', 'application/vnd.openxmlformats-officedocument.presentationml.presentation',
                  'text/csv', 'text/plain', 'image/vnd.dwg', 'image/vnd.dxf', 'application/vnd.autodesk.revit',
                  'application/zip', 'application/vnd.rar', 'application/x-7z-compressed',
                  'application/vnd.google-earth.kml+xml', 'application/vnd.google-earth.kmz'));
alter table public.doc_files drop constraint if exists doc_files_size_bytes_check;
alter table public.doc_files add constraint doc_files_size_bytes_check check (size_bytes between 1 and 52428800);

-- ---------------------------------------------------------------------
-- 5. الصلاحيات على الدوال
-- ---------------------------------------------------------------------
revoke execute on function public.attachment_mime(text), public.doc_kind_label(text), public.doc_can_edit(text, uuid),
  public.save_doc_item(uuid, jsonb), public.can_upload_doc_path(text), public.add_doc_file(text, text, integer, integer)
from public, anon;
grant execute on function public.attachment_mime(text), public.doc_kind_label(text), public.doc_can_edit(text, uuid),
  public.save_doc_item(uuid, jsonb), public.can_upload_doc_path(text), public.add_doc_file(text, text, integer, integer)
to authenticated;
