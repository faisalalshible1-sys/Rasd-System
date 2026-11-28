-- اختبار الترحيل 52: فحص تاريخ شراء الأصل بتوقيت طرابلس لا UTC
\set ON_ERROR_STOP 1
\set QUIET 1
\pset tuples_only on
\pset format unaligned

do $t$
declare n integer;
begin
  select count(*) into n from pg_proc p join pg_namespace s on s.oid = p.pronamespace
   where s.nspname = 'public' and p.proname in ('st_save_asset', 'st_import_assets')
     and pg_get_functiondef(p.oid) like '%current_date%';
  if n <> 0 then raise exception 'FAIL: ما زالت دالة أصول تقارن بـ current_date'; end if;
  select count(*) into n from pg_proc p join pg_namespace s on s.oid = p.pronamespace
   where s.nspname = 'public' and p.proname in ('st_save_asset', 'st_import_assets')
     and pg_get_functiondef(p.oid) like '%Africa/Tripoli%';
  if n <> 2 then raise exception 'FAIL: الدالتان لا تستعملان توقيت طرابلس'; end if;
  raise notice 'PASS: فحص تاريخ الشراء بتوقيت طرابلس في الدالتين';
end $t$;
