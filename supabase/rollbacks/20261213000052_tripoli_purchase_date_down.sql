-- التراجع عن الترحيل 52: يعيد المقارنة بـ current_date في الدالتين.
do $m$
declare r record;
begin
  for r in
    select p.oid, pg_get_functiondef(p.oid) as def
      from pg_proc p join pg_namespace s on s.oid = p.pronamespace
     where s.nspname = 'public' and p.proname in ('st_save_asset', 'st_import_assets')
  loop
    if r.def like '%(now() at time zone ''Africa/Tripoli'')::date%' then
      execute replace(r.def, '(now() at time zone ''Africa/Tripoli'')::date', 'current_date');
    end if;
  end loop;
end $m$;
