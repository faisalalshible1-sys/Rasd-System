-- =====================================================================
-- الترحيل 22: قسم الشؤون الفنية، ونقل السجلات، والفيديو، والطباعة والتصدير
--   • قسم «الشؤون الفنية» (كان «المستندات الفنية»): وحدة جديدة technical، وإليها ينتقل «اعتماد المواد»
--     من وحدة ضبط الجودة.
--   • «حالات عدم المطابقة» تنتقل من قسم ضمان الجودة (التخطيط) إلى وحدة ضبط الجودة (المطابقة والاستلام)،
--     وتُربط اختيارياً بالاختبار الذي كشفها بدل التدقيق.
--   • رفع الفيديو (MP4 وMOV وWebM) حتى 50 ميجابايت في التقارير اليومية وسجلات الأقسام والتصاميم.
--   • قوالب الطباعة: عامة للمكتب (المدير وموظفو مكتبه) أو خاصة بصاحبها، وقالب افتراضي واحد.
--   • سجل التصدير: كل ملف يُستخرج من المنظومة وكل تنزيل مجمّع للوسائط يُسجَّل في التدقيق.
-- يُشغَّل بعد الترحيلات 1–21، ويمكن إعادة تشغيله دون ضرر.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. وحدة الشؤون الفنية
-- ---------------------------------------------------------------------
alter table public.org_units drop constraint if exists org_units_section_check;
alter table public.org_units add constraint org_units_section_check
  check (section in ('heritage', 'planning_qa', 'safety', 'acceptance', 'technical'));
insert into public.org_units (key, section, name, sort) values ('technical', 'technical', 'قسم الشؤون الفنية', 8)
on conflict (key) do update set section = excluded.section, name = excluded.name, sort = excluded.sort;

-- ---------------------------------------------------------------------
-- 2. مواصفات الأنواع: عدم المطابقة إلى ضبط الجودة، واعتماد المواد إلى الشؤون الفنية
-- ---------------------------------------------------------------------
create or replace function public.unit_kind_spec(p_kind text)
returns jsonb
language sql immutable set search_path = public
as $$
  select case p_kind
    when 'heritage_building' then jsonb_build_object('unit', 'heritage',
      'statuses', array['registered', 'under_study', 'under_restoration', 'restored'], 'closed', array['restored'],
      'levels', array['good', 'fair', 'poor', 'critical'], 'parent', null, 'parent_required', false, 'project_required', false)
    when 'heritage_assessment' then jsonb_build_object('unit', 'heritage',
      'statuses', array['draft', 'final'], 'closed', array['final'],
      'levels', array['good', 'fair', 'poor', 'critical'], 'parent', 'heritage_building', 'parent_required', true, 'project_required', false)
    when 'plan' then jsonb_build_object('unit', 'planning',
      'statuses', array['draft', 'active', 'done', 'cancelled'], 'closed', array['done', 'cancelled'],
      'levels', array['annual', 'quarterly', 'monthly', 'project'], 'parent', null, 'parent_required', false, 'project_required', false)
    when 'qa_audit' then jsonb_build_object('unit', 'quality_assurance',
      'statuses', array['planned', 'in_progress', 'done', 'cancelled'], 'closed', array['done', 'cancelled'],
      'levels', array['', 'satisfactory', 'needs_improvement', 'unsatisfactory'], 'parent', null, 'parent_required', false, 'project_required', false)
    when 'ncr' then jsonb_build_object('unit', 'quality_control',
      'statuses', array['open', 'in_progress', 'closed'], 'closed', array['closed'],
      'levels', array['minor', 'major', 'critical'], 'parent', 'qc_test', 'parent_required', false, 'project_required', false)
    when 'followup_task' then jsonb_build_object('unit', 'follow_up',
      'statuses', array['open', 'done', 'cancelled'], 'closed', array['done', 'cancelled'],
      'levels', array['normal', 'high', 'urgent'], 'parent', null, 'parent_required', false, 'project_required', false)
    when 'safety_inspection' then jsonb_build_object('unit', 'safety',
      'statuses', array['open', 'closed'], 'closed', array['closed'],
      'levels', array['excellent', 'good', 'acceptable', 'poor'], 'parent', null, 'parent_required', false, 'project_required', true)
    when 'safety_incident' then jsonb_build_object('unit', 'safety',
      'statuses', array['open', 'investigating', 'closed'], 'closed', array['closed'],
      'levels', array['near_miss', 'minor', 'major', 'critical'], 'parent', null, 'parent_required', false, 'project_required', false)
    when 'safety_violation' then jsonb_build_object('unit', 'safety',
      'statuses', array['open', 'closed'], 'closed', array['closed'],
      'levels', array['low', 'medium', 'high'], 'parent', 'safety_inspection', 'parent_required', false, 'project_required', true)
    when 'handover' then jsonb_build_object('unit', 'receiving',
      'statuses', array['scheduled', 'accepted', 'accepted_notes', 'rejected'], 'closed', array['accepted', 'accepted_notes', 'rejected'],
      'levels', array['initial', 'final', 'partial'], 'parent', null, 'parent_required', false, 'project_required', true)
    when 'punch_item' then jsonb_build_object('unit', 'receiving',
      'statuses', array['open', 'closed'], 'closed', array['closed'],
      'levels', array[''], 'parent', 'handover', 'parent_required', true, 'project_required', false)
    when 'qc_test' then jsonb_build_object('unit', 'quality_control',
      'statuses', array['pending', 'passed', 'failed'], 'closed', array['passed', 'failed'],
      'levels', array['concrete', 'soil', 'steel', 'asphalt', 'masonry', 'other'], 'parent', null, 'parent_required', false, 'project_required', true)
    when 'material_approval' then jsonb_build_object('unit', 'technical',
      'statuses', array['under_review', 'approved', 'approved_notes', 'rejected'], 'closed', array['approved', 'approved_notes', 'rejected'],
      'levels', array[''], 'parent', null, 'parent_required', false, 'project_required', true)
  end
$$;

-- نقل السجلات القائمة (حالة عدم المطابقة المرتبطة بتدقيق تفقد ارتباطها لأن التدقيق بقي في ضمان الجودة)
update public.unit_records n set parent_id = null
 where n.kind = 'ncr' and n.parent_id is not null
   and exists (select 1 from public.unit_records p where p.id = n.parent_id and p.kind <> 'qc_test');
update public.unit_records set unit = 'quality_control' where kind = 'ncr' and unit <> 'quality_control';
update public.unit_records set unit = 'technical' where kind = 'material_approval' and unit <> 'technical';

-- ---------------------------------------------------------------------
-- 3. الصلاحيات: رئيس قسم الشؤون الفنية يكتب في وحدته ويرأسها
-- ---------------------------------------------------------------------
create or replace function public.unit_can_edit(p_unit text)
returns boolean
language plpgsql stable security definer set search_path = public
as $$
declare
  me        public.profiles;
  v_section text;
begin
  if not public.writes_allowed() then
    return false;
  end if;
  select section into v_section from public.org_units where key = p_unit;
  if not found then
    return false;
  end if;
  select * into me from public.profiles where id = auth.uid();
  if not found or not me.active or me.role is null then
    return false;
  end if;
  return coalesce(me.role in ('director', 'office_staff')
      or coalesce(me.unit = p_unit, false)
      or (v_section = 'heritage' and me.role = 'dept_head' and me.department = 'restoration')
      or (v_section = 'acceptance' and me.role = 'dept_head' and me.department = 'acceptance')
      or (v_section = 'technical' and me.role = 'dept_head' and me.department = 'technical')
      or (v_section = 'planning_qa' and me.role = 'planning_qa'), false);
end;
$$;

create or replace function public.unit_is_head(p_unit text)
returns boolean
language plpgsql stable security definer set search_path = public
as $$
declare
  me        public.profiles;
  v_section text;
begin
  if not public.writes_allowed() then
    return false;
  end if;
  select section into v_section from public.org_units where key = p_unit;
  select * into me from public.profiles where id = auth.uid();
  if not found or not me.active or me.role is null then
    return false;
  end if;
  return coalesce(me.role = 'director'
      or coalesce(me.unit = p_unit and me.unit_head, false)
      or (v_section = 'heritage' and me.role = 'dept_head' and me.department = 'restoration')
      or (v_section = 'acceptance' and me.role = 'dept_head' and me.department = 'acceptance')
      or (v_section = 'technical' and me.role = 'dept_head' and me.department = 'technical')
      or (v_section = 'planning_qa' and me.role = 'planning_qa'), false);
end;
$$;

-- ---------------------------------------------------------------------
-- 4. الفيديو: MP4 وMOV وWebM حتى 50 ميجابايت (الصور وPDF تبقى حتى 20 ميجابايت)
-- ---------------------------------------------------------------------
do $$
begin
  if to_regclass('storage.buckets') is not null then
    update storage.buckets
       set file_size_limit = 52428800,
           allowed_mime_types = array['application/pdf', 'image/jpeg', 'image/png', 'image/webp', 'image/gif',
                                      'video/mp4', 'video/quicktime', 'video/webm']
     where id = 'docs';
  end if;
end $$;

alter table public.doc_files drop constraint if exists doc_files_mime_check;
alter table public.doc_files add constraint doc_files_mime_check
  check (mime in ('application/pdf', 'image/jpeg', 'image/png', 'image/webp', 'image/gif', 'video/mp4', 'video/quicktime', 'video/webm'));
alter table public.doc_files drop constraint if exists doc_files_size_bytes_check;
alter table public.doc_files add constraint doc_files_size_bytes_check
  check (size_bytes between 1 and (case when mime like 'video/%' then 52428800 else 20971520 end));

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
    select unit into v_unit from public.unit_records where id = v_owner;
    return found and public.unit_can_edit(v_unit);
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
$$;

-- ---------------------------------------------------------------------
-- 5. قوالب الطباعة
--   owner_id فارغ: قالب عام للمكتب يراه الجميع (يحفظه المدير وموظفو مكتبه).
--   owner_id معبّأ: قالب خاص بصاحبه وحده.
--   is_default: القالب العام الذي يُختار تلقائياً عند الطباعة (واحد فقط).
-- ---------------------------------------------------------------------
create table if not exists public.print_templates (
  id          uuid primary key default gen_random_uuid(),
  name        text not null check (length(btrim(name)) between 2 and 80),
  owner_id    uuid references public.profiles(id) on delete cascade,
  is_default  boolean not null default false,
  config      jsonb not null default '{}'::jsonb check (jsonb_typeof(config) = 'object'),
  created_at  timestamptz not null default now(),
  created_by  uuid,
  updated_at  timestamptz not null default now(),
  updated_by  uuid
);
create index if not exists print_templates_owner_idx on public.print_templates (owner_id);
create unique index if not exists print_templates_one_default on public.print_templates (is_default) where is_default;

-- حفظ قالب (إنشاء أو تعديل). يعيد معرّفه.
create or replace function public.save_print_template(p_id uuid, p_name text, p_config jsonb, p_shared boolean default false,
                                                      p_default boolean default false)
returns uuid
language plpgsql security definer set search_path = public
as $$
declare
  me      public.profiles;
  old_t   public.print_templates;
  v_name  text := btrim(coalesce(p_name, ''));
  v_share boolean := coalesce(p_shared, false) or coalesce(p_default, false);
  v_admin boolean;
  v_id    uuid;
begin
  if not public.writes_allowed() then
    raise exception 'المنظومة في وضع القراءة فقط' using errcode = '42501';
  end if;
  select * into me from public.profiles where id = auth.uid();
  if not found or not me.active or me.role is null or me.role = 'security_auditor' then
    raise exception 'غير مصرح' using errcode = '42501';
  end if;
  v_admin := me.role in ('director', 'office_staff');
  if length(v_name) < 2 or length(v_name) > 80 then
    raise exception 'اكتب اسماً للقالب (حرفان إلى 80 حرفاً)' using errcode = '22023';
  end if;
  if jsonb_typeof(coalesce(p_config, 'null'::jsonb)) <> 'object' then
    raise exception 'إعدادات القالب غير صالحة' using errcode = '22023';
  end if;
  if length(p_config::text) > 400000 then
    raise exception 'إعدادات القالب كبيرة؛ صغّر الشعار المخصص' using errcode = '22023';
  end if;
  if v_share and not v_admin then
    raise exception 'القوالب العامة للمدير وموظفي مكتبه؛ احفظه قالباً خاصاً بك' using errcode = '42501';
  end if;
  if p_id is not null then
    select * into old_t from public.print_templates where id = p_id for update;
    if not found then
      raise exception 'القالب غير موجود' using errcode = 'P0002';
    end if;
    if not (old_t.owner_id is not distinct from me.id or (old_t.owner_id is null and v_admin)) then
      raise exception 'لا تملك تعديل هذا القالب' using errcode = '42501';
    end if;
  end if;
  if coalesce(p_default, false) then
    update public.print_templates set is_default = false where is_default and id is distinct from p_id;
  end if;
  if p_id is null then
    insert into public.print_templates (name, owner_id, is_default, config, created_by, updated_by)
    values (v_name, case when v_share then null else me.id end, coalesce(p_default, false), p_config, me.id, me.id)
    returning id into v_id;
  else
    update public.print_templates
       set name = v_name, owner_id = case when v_share then null else me.id end, is_default = coalesce(p_default, false),
           config = p_config, updated_at = now(), updated_by = me.id
     where id = p_id;
    v_id := p_id;
  end if;
  perform public.write_audit('print.template_save', null, null,
    jsonb_build_object('template_id', v_id, 'name', v_name, 'shared', v_share, 'default', coalesce(p_default, false),
                       'created', p_id is null),
    'قوالب الطباعة');
  return v_id;
end;
$$;

create or replace function public.delete_print_template(p_id uuid)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  me public.profiles;
  t  public.print_templates;
begin
  if not public.writes_allowed() then
    raise exception 'المنظومة في وضع القراءة فقط' using errcode = '42501';
  end if;
  select * into me from public.profiles where id = auth.uid();
  select * into t from public.print_templates where id = p_id for update;
  if not found then
    raise exception 'القالب غير موجود' using errcode = 'P0002';
  end if;
  if me.id is null or not coalesce(me.active, false)
     or not (t.owner_id is not distinct from me.id or (t.owner_id is null and me.role in ('director', 'office_staff'))) then
    raise exception 'لا تملك حذف هذا القالب' using errcode = '42501';
  end if;
  delete from public.print_templates where id = p_id;
  perform public.write_audit('print.template_delete', null, null,
    jsonb_build_object('template_id', p_id, 'name', t.name, 'shared', t.owner_id is null), 'قوالب الطباعة');
end;
$$;

-- ---------------------------------------------------------------------
-- 6. سجل التصدير: ملف مستخرج (PDF أو Word أو Excel…) أو تنزيل مجمّع للوسائط
-- ---------------------------------------------------------------------
create or replace function public.log_export(p_kind text, p_source text, p_title text, p_format text,
                                             p_rows integer default 0, p_bytes bigint default 0)
returns void
language plpgsql security definer set search_path = public
as $$
begin
  if not public.is_member() then
    raise exception 'غير مصرح' using errcode = '42501';
  end if;
  if coalesce(p_kind, '') not in ('file', 'media', 'print') then
    raise exception 'نوع غير معروف' using errcode = '22023';
  end if;
  perform public.write_audit('export.' || p_kind, null, null,
    jsonb_build_object('source', left(coalesce(p_source, ''), 80), 'title', left(coalesce(p_title, ''), 200),
                       'format', left(coalesce(p_format, ''), 20), 'rows', greatest(coalesce(p_rows, 0), 0),
                       'bytes', greatest(coalesce(p_bytes, 0), 0)),
    'الطباعة والتصدير');
end;
$$;

-- ---------------------------------------------------------------------
-- 7. القراءة والصلاحيات والتحديث اللحظي
-- ---------------------------------------------------------------------
alter table public.print_templates enable row level security;
drop policy if exists print_templates_read on public.print_templates;
create policy print_templates_read on public.print_templates for select to authenticated
  using ((select public.is_member()) and (owner_id is null or owner_id = (select auth.uid())));
revoke all on public.print_templates from anon;
revoke insert, update, delete, truncate on public.print_templates from authenticated;
grant select on public.print_templates to authenticated;
grant all on public.print_templates to service_role;

do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime')
     and not exists (select 1 from pg_publication_tables
                     where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'print_templates') then
    execute 'alter publication supabase_realtime add table public.print_templates';
  end if;
end $$;

revoke execute on function
  public.save_print_template(uuid, text, jsonb, boolean, boolean), public.delete_print_template(uuid),
  public.log_export(text, text, text, text, integer, bigint)
from public, anon;
grant execute on function
  public.save_print_template(uuid, text, jsonb, boolean, boolean), public.delete_print_template(uuid),
  public.log_export(text, text, text, text, integer, bigint)
to authenticated;

-- تنبيه مستشار الأمان: مسار البحث ثابت لدالة تسمية المستندات
alter function public.doc_kind_label(text) set search_path = public;

notify pgrst, 'reload schema';
