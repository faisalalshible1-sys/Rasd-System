-- =====================================================================
--  تراجع الترحيل 35 (ملف العقد ومرفقاته): يعيد المستندات وصلاحياتها ورفع الملفات كما كانت بعد الترحيل 34.
--  يرفض التراجع إن وُجدت مرفقات عقود، حتى لا تُحذف بيانات: تُنقل أو تُحذف من المنظومة أولاً.
--  يُشغَّل يدوياً عند الحاجة فقط، ويُختبر في supabase/tests/108_contract_files_test.sql.
-- =====================================================================
do $$
begin
  if exists (select 1 from public.doc_items where kind = 'attachment') then
    raise exception 'في المنظومة مرفقات عقود؛ لا يُتراجع عن الترحيل 35 قبل نقلها' using errcode = 'P0001';
  end if;
end $$;

alter table public.doc_items drop constraint if exists doc_items_engineer_link;
alter table public.doc_items drop constraint if exists doc_items_kind_fields;
alter table public.doc_items drop constraint if exists doc_items_kind_check;
alter table public.doc_items add constraint doc_items_kind_check check (kind = any (array['boq', 'letter', 'design']));
alter table public.doc_items add constraint doc_items_kind_fields check (
     (kind = 'boq' and category = any (array['estimate', 'contract', 'variation', 'final'])
        and status = any (array['draft', 'review', 'approved']) and direction is null)
  or (kind = 'letter' and category = any (array['', 'contract', 'finance', 'technical', 'admin', 'other'])
        and status = any (array['open', 'closed', 'info']) and direction is not null)
  or (kind = 'design' and category = any (array['architectural', 'structural', 'electrical', 'mechanical', 'plumbing', 'landscape',
                                                'urban', 'heritage', 'other'])
        and status = any (array['draft', 'review', 'approved']) and direction is null));
drop index if exists public.doc_items_engineer_idx;
alter table public.doc_items drop column if exists engineer_id;

drop policy if exists doc_items_read on public.doc_items;
create policy doc_items_read on public.doc_items for select to authenticated
  using ((select public.sees_section('docs')) or (project_id is not null and project_id = any ((select public.my_supervised())::uuid[])));
drop policy if exists doc_revisions_read on public.doc_revisions;
create policy doc_revisions_read on public.doc_revisions for select to authenticated
  using ((select public.sees_section('docs')) or exists (select 1 from public.doc_items i where i.id = doc_revisions.item_id));

CREATE OR REPLACE FUNCTION public.doc_kind_label(p_kind text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public'
AS $function$
  select case p_kind when 'boq' then 'مقايسة' when 'letter' then 'مراسلة' when 'design' then 'تصميم' else p_kind end
$function$

;

CREATE OR REPLACE FUNCTION public.doc_can_edit(p_kind text, p_project uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select public.sees_section('docs') and (
    coalesce(public.doc_can_edit_v22(p_kind, p_project), false)
    or (public.writes_allowed() and p_kind in ('boq', 'letter', 'design') and public.has_grant('docs:' || p_kind)
        and (p_project is null or exists (select 1 from public.projects where id = p_project and merged_into is null))))
$function$

;

CREATE OR REPLACE FUNCTION public.save_doc_item(p_id uuid, p_data jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
$function$

;

CREATE OR REPLACE FUNCTION public.can_upload_doc_path(p_name text)
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
$function$

;

CREATE OR REPLACE FUNCTION public.add_doc_file(p_path text, p_name text, p_width integer DEFAULT NULL::integer, p_height integer DEFAULT NULL::integer)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
  ur      public.unit_records;
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
$function$

;

drop function if exists public.attachment_mime(text);

do $$
begin
  if to_regclass('storage.buckets') is null then
    return;
  end if;
  update storage.buckets set file_size_limit = 52428800,
    allowed_mime_types = array['application/pdf', 'image/jpeg', 'image/png', 'image/webp', 'image/gif', 'video/mp4', 'video/quicktime', 'video/webm']
  where id = 'docs';
end $$;

alter table public.doc_files drop constraint if exists doc_files_mime_check;
alter table public.doc_files add constraint doc_files_mime_check
  check (mime in ('application/pdf', 'image/jpeg', 'image/png', 'image/webp', 'image/gif', 'video/mp4', 'video/quicktime', 'video/webm'));
alter table public.doc_files drop constraint if exists doc_files_size_bytes_check;
alter table public.doc_files add constraint doc_files_size_bytes_check
  check (size_bytes between 1 and (case when mime like 'video/%' then 52428800 else 20971520 end));
