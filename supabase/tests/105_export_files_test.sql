-- اختبارات الترحيل 32: نسخ PDF المحفوظة لرمز QR — الرفع والتسجيل والفتح بالصلاحية ونطاق الاطلاع والتدقيق.
-- يُشغَّل بعد تطبيق 20261122000032_export_files.sql مرتين. التخزين هنا محاكاة (00_supabase_shim.sql).
\set ON_ERROR_STOP 1
\set QUIET 1
\pset tuples_only on
\pset format unaligned

create or replace function pg_temp.as_user(p_email text, p_aal text default 'aal1') returns void language plpgsql security definer as $$
declare v uuid := (select id from auth.users where email = p_email);
begin
  perform set_config('request.jwt.claim.sub', coalesce(v::text, ''), false);
  perform set_config('request.jwt.claims', jsonb_build_object('sub', v, 'aal', p_aal, 'session_id', '00000000-0000-0000-0000-000000000001')::text, false);
end $$;
create or replace function pg_temp.expect_error(p_sql text, p_label text) returns void language plpgsql as $$
begin
  begin
    execute p_sql;
  exception when others then
    raise notice 'PASS (رُفض كما يجب): % — %', p_label, sqlerrm;
    return;
  end;
  raise exception 'FAIL: كان يجب رفض: %', p_label;
end $$;
create or replace function pg_temp.check(p_ok boolean, p_label text) returns void language plpgsql as $$
begin
  if not coalesce(p_ok, false) then raise exception 'FAIL: %', p_label; end if;
  raise notice 'PASS: %', p_label;
end $$;
create or replace function pg_temp.alog() returns setof public.audit_log language sql security definer as $$
  select * from public.audit_log
$$;
create or replace function pg_temp.uid(p_email text) returns uuid language sql security definer as $$
  select id from auth.users where email = p_email
$$;
-- رفع ملف كما يفعل Supabase (المالك هو المستخدم، والحجم والنوع في البيانات الوصفية)
create or replace function pg_temp.upload(p_name text, p_size bigint default 52000, p_mime text default 'application/pdf') returns void language sql as $$
  insert into storage.objects (bucket_id, name, owner, owner_id, metadata)
  values ('exports', p_name, auth.uid(), auth.uid()::text, jsonb_build_object('size', p_size, 'mimetype', p_mime))
$$;
create or replace function pg_temp.fpath(p_k text) returns text language plpgsql security definer as $$
begin
  return (select path from public.export_files where token = (select s from v where k = p_k));
end $$;
create or replace function pg_temp.visible(p_name text) returns boolean language sql as $$
  select exists (select 1 from storage.objects where bucket_id = 'exports' and name = p_name)
$$;
grant execute on all functions in schema pg_temp to authenticated, anon;

update app_settings set value = 'false' where key in ('security.freeze', 'security.require_mfa_all');
update profiles set locked_until = null where email like 'k.%@test.ly';
create temp table v (k text primary key, s text);
grant all on v to authenticated;
insert into v values ('sha', repeat('ab', 32)),
                     ('t1', 'Ab12Cd34Ef56Gh78Ij90'), ('t2', 'Zz12Yy34Xx56Ww78Vv90'), ('t3', 'Pp12Qq34Rr56Ss78Tt90'),
                     ('t4', 'Mm12Nn34Oo56Kk78Ll90');

select pg_temp.check((select not public and file_size_limit = 26214400 and allowed_mime_types = array['application/pdf']
                        from storage.buckets where id = 'exports'), 'حاوية خاصة لملفات PDF حتى 25 ميجابايت');

-- ---------------------------------------------------------------- الرفع والتسجيل
set role authenticated;
select pg_temp.as_user('k.contracts@test.ly');
select pg_temp.expect_error($$select pg_temp.upload(pg_temp.uid('k.staff@test.ly') || '/Ab12Cd34Ef56Gh78Ij90.pdf')$$, 'لا رفع إلى مجلد مستخدم آخر');
select pg_temp.expect_error($$select pg_temp.upload(auth.uid() || '/short.pdf')$$, 'ولا باسم غير الرمز');
select pg_temp.expect_error($$select pg_temp.upload(auth.uid() || '/Ab12Cd34Ef56Gh78Ij90.docx')$$, 'ولا بغير PDF');
select pg_temp.expect_error($$select public.register_export_file((select s from v where k = 't1'), jsonb_build_object('title', 'كشف', 'sha256', (select s from v where k = 'sha')))$$,
                            'لا تسجيل قبل اكتمال الرفع');
select pg_temp.upload(auth.uid() || '/' || (select s from v where k = 't1') || '.pdf');
select pg_temp.expect_error($$select public.register_export_file((select s from v where k = 't1'), jsonb_build_object('title', 'كشف', 'sha256', 'xyz'))$$,
                            'البصمة SHA-256 مطلوبة');
select public.register_export_file((select s from v where k = 't1'), jsonb_build_object(
  'title', 'كشف العقود', 'ref_no', 'م.ش.ه/2026/0012', 'source', 'cycle:contracts', 'sha256', (select s from v where k = 'sha'), 'pages', 3,
  'project_id', (select id from projects where merged_into is null order by assign_no limit 1)));
select pg_temp.check((select access = 'members' and bytes = 52000 and pages = 3 and created_by = auth.uid() and path = auth.uid() || '/' || token || '.pdf'
                        from export_files where token = (select s from v where k = 't1')),
                     'التسجيل بالحجم الفعلي للملف المرفوع ومساره ومُستخرجه');
select pg_temp.check((select count(*) = 1 from pg_temp.alog() where action = 'export.store' and detail ->> 'ref_no' = 'م.ش.ه/2026/0012'), 'التسجيل مسجّل');
select pg_temp.expect_error($$select public.register_export_file((select s from v where k = 't1'), jsonb_build_object('title', 'كشف', 'sha256', (select s from v where k = 'sha')))$$,
                            'الرمز لا يُسجَّل مرتين');
delete from storage.objects where bucket_id = 'exports' and name like '%' || (select s from v where k = 't1') || '%';
reset role;
select pg_temp.check((select count(*) = 1 from storage.objects where bucket_id = 'exports' and name like '%' || (select s from v where k = 't1') || '%'),
                     'النسخة المسجّلة لا يحذفها صاحبها');
set role authenticated;

-- بيانات المستخدمين: للمدير ومسؤول الأمن ومن استخرجها مهما طُلب
select pg_temp.as_user('k.contracts@test.ly');
select pg_temp.upload(auth.uid() || '/' || (select s from v where k = 't2') || '.pdf');
select public.register_export_file((select s from v where k = 't2'), jsonb_build_object('title', 'مستخدمو المنظومة', 'source', 'cycle:users',
  'access', 'members', 'sha256', (select s from v where k = 'sha')));
select pg_temp.check((select access = 'people' from export_files where token = (select s from v where k = 't2')), 'بيانات المستخدمين مقيّدة دائماً');
-- مستند سري: للمدير ومن استخرجه
select pg_temp.upload(auth.uid() || '/' || (select s from v where k = 't3') || '.pdf');
select public.register_export_file((select s from v where k = 't3'), jsonb_build_object('title', 'مذكرة سرية', 'access', 'private',
  'sha256', (select s from v where k = 'sha')));
-- رفع لم يُسجَّل يحذفه صاحبه
select pg_temp.upload(auth.uid() || '/' || (select s from v where k = 't4') || '.pdf');
delete from storage.objects where bucket_id = 'exports' and name = auth.uid() || '/' || (select s from v where k = 't4') || '.pdf';
reset role;
select pg_temp.check((select count(*) = 0 from storage.objects where name like '%' || (select s from v where k = 't4') || '%'), 'الرفع غير المسجّل يحذفه صاحبه');
set role authenticated;

-- ---------------------------------------------------------------- الفتح بالصلاحية
select pg_temp.as_user('k.qa@test.ly');
select pg_temp.check((select r ->> 'ok' = 'true' and r ->> 'ref_no' = 'م.ش.ه/2026/0012' and r ->> 'sha256' = (select s from v where k = 'sha')
                             and r ->> 'path' like '%.pdf' and r ->> 'created_by' <> ''
                        from public.open_export_file((select s from v where k = 't1')) r),
                     'العضو يفتح النسخة العامة ويتلقى مسارها وبصمتها ورقمها');
select pg_temp.check(pg_temp.visible(pg_temp.fpath('t1')),
                     'ويقرأ الملف من التخزين (الرابط الموقّت)');
select pg_temp.check((select r ->> 'ok' = 'false' and r ->> 'reason' = 'denied' from public.open_export_file((select s from v where k = 't2')) r),
                     'ولا يفتح بيانات المستخدمين');
select pg_temp.check(not pg_temp.visible(pg_temp.fpath('t2')),
                     'ولا يقرأ ملفها من التخزين');
select pg_temp.check((select r ->> 'reason' = 'denied' from public.open_export_file((select s from v where k = 't3')) r), 'ولا المستند السري');
select pg_temp.check((select r ->> 'ok' = 'false' and r ->> 'reason' = 'unknown' from public.open_export_file('Nn00Nn00Nn00Nn00Nn00') r), 'الرمز غير المعروف');
select pg_temp.check((select count(*) = 0 from export_files), 'ولا يرى العضو سجل نسخ غيره');
select pg_temp.as_user('auditor@test.ly', 'aal2');
select pg_temp.check((select r ->> 'ok' = 'true' from public.open_export_file((select s from v where k = 't2')) r)
                     and pg_temp.visible(pg_temp.fpath('t2')),
                     'مسؤول الأمن يفتح بيانات المستخدمين');
select pg_temp.check((select r ->> 'reason' = 'denied' from public.open_export_file((select s from v where k = 't3')) r), 'ولا يفتح المستند السري');
select pg_temp.as_user('k.contracts@test.ly');
select pg_temp.check((select r ->> 'ok' = 'true' from public.open_export_file((select s from v where k = 't3')) r)
                     and pg_temp.visible(auth.uid() || '/' || (select s from v where k = 't3') || '.pdf'),
                     'ومن استخرجه يفتحه');
select pg_temp.check((select count(*) = 3 from export_files), 'ويرى سجل نسخه');
select pg_temp.as_user('director.new@test.ly', 'aal2');
select pg_temp.check((select r ->> 'ok' = 'true' from public.open_export_file((select s from v where k = 't3')) r), 'والمدير يفتح كل النسخ');
select pg_temp.check((select count(*) = 3 from pg_temp.alog() where action = 'export.denied')
                     and (select count(*) = 1 from pg_temp.alog() where action = 'export.unknown')
                     and (select count(*) >= 4 from pg_temp.alog() where action = 'export.open'),
                     'كل فتح ورفض مسجّل في التدقيق');

-- ---------------------------------------------------------------- لا كتابة مباشرة، ولا للزائر
select pg_temp.expect_error($$insert into export_files (token, path, title, sha256, bytes) values ('Qq00Qq00Qq00Qq00Qq00', 'x', 'x', repeat('a', 64), 1)$$,
                            'لا كتابة مباشرة في سجل النسخ');
select pg_temp.expect_error($$update export_files set access = 'members'$$, 'ولا تعديل لنطاق الاطلاع');
reset role;
set role anon;
select pg_temp.expect_error($$select public.open_export_file('Ab12Cd34Ef56Gh78Ij90')$$, 'الزائر دون دخول لا يفتح شيئاً');
reset role;
set app.trusted = 'on';
update profiles set active = false where email = 'k.qa@test.ly';
set app.trusted = 'off';
set role authenticated;
select pg_temp.as_user('k.qa@test.ly');
select pg_temp.expect_error($$select public.open_export_file((select s from v where k = 't1'))$$, 'ولا الحساب الموقوف');
reset role;
set app.trusted = 'on';
update profiles set active = true where email = 'k.qa@test.ly';
set app.trusted = 'off';
