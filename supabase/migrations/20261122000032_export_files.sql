-- =====================================================================
--  الترحيل 32: رمز QR يفتح نسخة PDF الأصلية المحفوظة
--   كل ملف PDF يُستخرج برمز التحقق يُرفع كما هو إلى حاوية خاصة (exports/<المستخدم>/<الرمز>.pdf) ويُسجَّل
--   في export_files ببصمته SHA-256 وحجمه وعنوانه ورقمه الإشاري. رمز QR في الملف رابط إلى المنظومة بهذا الرمز:
--   بعد الدخول تفتح المنظومة النسخة المحفوظة نفسها لمن يحق له، وترفض لغيره.
--   من يحق له الفتح:
--     members : كل أعضاء المنظومة (البيانات نفسها مقروءة لهم داخلها)
--     people  : بيانات المستخدمين — المدير ومسؤول الأمن ومن استخرجه
--     private : مستند عليه عبارة سرية — المدير ومن استخرجه
--   كل فتح أو رفض يُسجَّل في سجل التدقيق. لا تعديل ولا حذف للنسخ المسجّلة.
--  يُشغَّل بعد 20261122000031_auto_risks_swot.sql. إعادة تشغيله آمنة.
-- =====================================================================

create table if not exists public.export_files (
  token      text primary key check (token ~ '^[A-Za-z0-9]{20,40}$'),
  path       text not null unique check (length(path) <= 200),
  title      text not null check (length(btrim(title)) between 1 and 300),
  ref_no     text not null default '' check (length(ref_no) <= 80),
  source     text not null default '' check (length(source) <= 80),
  project_id uuid references public.projects (id) on delete set null,
  access     text not null default 'members' check (access in ('members', 'people', 'private')),
  sha256     text not null check (sha256 ~ '^[0-9a-f]{64}$'),
  bytes      bigint not null check (bytes > 0),
  pages      integer check (pages > 0),
  created_by uuid references public.profiles (id) on delete set null,
  created_at timestamptz not null default now()
);
create index if not exists export_files_created_by_idx on public.export_files (created_by, created_at desc);
create index if not exists export_files_project_idx    on public.export_files (project_id);

alter table public.export_files enable row level security;
drop policy if exists export_files_read on public.export_files;
create policy export_files_read on public.export_files for select to authenticated
  using ((select public.is_director()) or created_by = (select auth.uid()));
revoke all on public.export_files from anon;
revoke insert, update, delete, truncate on public.export_files from authenticated;
grant select on public.export_files to authenticated;
grant all on public.export_files to service_role;

-- هل يفتح المستخدم الحالي هذه النسخة؟
create or replace function public.export_can_open(p_access text, p_owner uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
  select public.is_member() and (
    p_owner = auth.uid()
    or public.is_director()
    or p_access = 'members'
    or (p_access = 'people' and coalesce(public.my_role()::text, '') = 'security_auditor'))
$$;

create or replace function public.export_can_open_path(p_path text)
returns boolean
language sql stable security definer set search_path = public
as $$
  select exists (select 1 from public.export_files f where f.path = p_path and public.export_can_open(f.access, f.created_by))
$$;

-- ---------------------------------------------------------------------
-- حاوية التخزين وسياساتها (على Supabase، وفي بيئة الاختبار المحاكية)
-- ---------------------------------------------------------------------
do $$
begin
  if to_regclass('storage.buckets') is null then
    return;
  end if;
  insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
  values ('exports', 'exports', false, 26214400, array['application/pdf'])
  on conflict (id) do update set public = false, file_size_limit = excluded.file_size_limit,
                                 allowed_mime_types = excluded.allowed_mime_types;

  -- الرفع إلى مجلد المستخدم نفسه فقط، وباسم الرمز
  drop policy if exists exports_upload on storage.objects;
  create policy exports_upload on storage.objects for insert to authenticated
    with check (bucket_id = 'exports' and (select public.is_member())
                and name ~ ('^' || (select auth.uid())::text || '/[A-Za-z0-9]{20,40}\.pdf$'));

  -- القراءة (ومنها الرابط الموقّت) لصاحب الملف، ولمن يحق له فتح النسخة المسجّلة
  drop policy if exists exports_read on storage.objects;
  create policy exports_read on storage.objects for select to authenticated
    using (bucket_id = 'exports'
           and (owner_id = (select auth.uid())::text or owner = (select auth.uid()) or public.export_can_open_path(name)));

  -- يحذف صاحبه الملف الذي لم يُسجَّل (فشل التسجيل)، ولا تُحذف نسخة مسجّلة
  drop policy if exists exports_delete on storage.objects;
  create policy exports_delete on storage.objects for delete to authenticated
    using (bucket_id = 'exports' and (owner_id = (select auth.uid())::text or owner = (select auth.uid()))
           and not exists (select 1 from public.export_files f where f.path = objects.name));
end $$;

-- ---------------------------------------------------------------------
-- تسجيل نسخة مرفوعة
-- ---------------------------------------------------------------------
create or replace function public.register_export_file(p_token text, p_data jsonb)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  v_path   text := auth.uid()::text || '/' || coalesce(p_token, '') || '.pdf';
  v_size   bigint;
  v_mime   text;
  v_source text := public.jtext(p_data, 'source', 80, 'المصدر');
  v_access text := coalesce(nullif(p_data ->> 'access', ''), 'members');
  v_sha    text := lower(btrim(coalesce(p_data ->> 'sha256', '')));
  v_title  text := public.jtext(p_data, 'title', 300, 'العنوان');
  v_proj   uuid;
begin
  if not public.is_member() then
    raise exception 'غير مصرح' using errcode = '42501';
  end if;
  if coalesce(p_token, '') !~ '^[A-Za-z0-9]{20,40}$' then
    raise exception 'رمز غير صالح' using errcode = '22023';
  end if;
  if v_access not in ('members', 'people', 'private') then
    raise exception 'نطاق الاطلاع غير معروف' using errcode = '22023';
  end if;
  if v_sha !~ '^[0-9a-f]{64}$' then
    raise exception 'بصمة الملف غير صالحة' using errcode = '22023';
  end if;
  if length(v_title) < 1 then
    raise exception 'عنوان المستند مطلوب' using errcode = '22023';
  end if;
  -- بيانات المستخدمين لا تُفتح لكل الأعضاء أياً كان الطلب
  if v_source = 'cycle:users' and v_access = 'members' then
    v_access := 'people';
  end if;
  if nullif(p_data ->> 'project_id', '') is not null then
    begin
      v_proj := (p_data ->> 'project_id')::uuid;
    exception when others then
      v_proj := null;
    end;
    if not exists (select 1 from public.projects where id = v_proj) then
      v_proj := null;
    end if;
  end if;
  if exists (select 1 from public.export_files where token = p_token) then
    raise exception 'الرمز مسجّل من قبل' using errcode = '23505';
  end if;
  if to_regclass('storage.objects') is not null then
    execute 'select (metadata ->> ''size'')::bigint, metadata ->> ''mimetype'' from storage.objects where bucket_id = ''exports'' and name = $1'
      into v_size, v_mime using v_path;
    if v_size is null then
      raise exception 'لم يكتمل رفع الملف؛ أعد المحاولة' using errcode = 'P0002';
    end if;
    if coalesce(v_mime, 'application/pdf') <> 'application/pdf' then
      raise exception 'النسخة المحفوظة PDF فقط' using errcode = '22023';
    end if;
  end if;
  v_size := coalesce(v_size, public.jint(p_data, 'bytes', 1, 26214400, 'الحجم'), 1);
  insert into public.export_files (token, path, title, ref_no, source, project_id, access, sha256, bytes, pages, created_by)
  values (p_token, v_path, v_title, public.jtext(p_data, 'ref_no', 80, 'الرقم الإشاري'), v_source, v_proj, v_access, v_sha, v_size,
          public.jint(p_data, 'pages', 1, 100000, 'عدد الصفحات'), auth.uid());
  perform public.write_audit('export.store', v_proj, null,
    jsonb_build_object('title', v_title, 'ref_no', public.jtext(p_data, 'ref_no', 80, 'الرقم الإشاري'), 'source', v_source,
                       'access', v_access, 'bytes', v_size, 'sha256', v_sha),
    coalesce(public.project_label(v_proj), 'عام'));
end;
$$;

-- ---------------------------------------------------------------------
-- فتح نسخة من رمزها: المسار للرابط الموقّت، وبيانات المطابقة
-- ---------------------------------------------------------------------
create or replace function public.open_export_file(p_token text)
returns jsonb
language plpgsql security definer set search_path = public
as $$
declare
  f public.export_files;
begin
  if not public.is_member() then
    raise exception 'سجّل الدخول بحساب مفعّل في المنظومة لفتح المستند' using errcode = '42501';
  end if;
  -- الرفض يُعاد نتيجةً (لا استثناءً) ليبقى مسجّلاً في سجل التدقيق
  select * into f from public.export_files where token = btrim(coalesce(p_token, ''));
  if not found then
    perform public.write_audit('export.unknown', null, null, jsonb_build_object('token', left(coalesce(p_token, ''), 40)), 'عام');
    return jsonb_build_object('ok', false, 'reason', 'unknown');
  end if;
  if not public.export_can_open(f.access, f.created_by) then
    perform public.write_audit('export.denied', f.project_id, null,
      jsonb_build_object('title', f.title, 'ref_no', f.ref_no, 'access', f.access), coalesce(public.project_label(f.project_id), 'عام'));
    return jsonb_build_object('ok', false, 'reason', 'denied', 'title', f.title, 'access', f.access);
  end if;
  perform public.write_audit('export.open', f.project_id, null,
    jsonb_build_object('title', f.title, 'ref_no', f.ref_no, 'access', f.access), coalesce(public.project_label(f.project_id), 'عام'));
  return jsonb_build_object('ok', true, 'path', f.path, 'title', f.title, 'ref_no', f.ref_no, 'created_at', f.created_at,
                            'created_by', public.actor_name(f.created_by), 'sha256', f.sha256, 'bytes', f.bytes,
                            'pages', f.pages, 'access', f.access);
end;
$$;

revoke execute on function public.export_can_open(text, uuid), public.export_can_open_path(text),
  public.register_export_file(text, jsonb), public.open_export_file(text) from public, anon;
grant execute on function public.export_can_open(text, uuid), public.export_can_open_path(text),
  public.register_export_file(text, jsonb), public.open_export_file(text) to authenticated;
