-- التراجع عن الترحيل 55: يزيل النداء من الدوال ثم الدالة والجدول.
do $m$
declare r record; v_def text;
begin
  for r in
    select p.oid from pg_proc p join pg_namespace s on s.oid = p.pronamespace
     where s.nspname = 'public' and p.prokind = 'f' and p.proname <> 'sec_rate_hit' and pg_get_functiondef(p.oid) like '%perform public.sec_rate_hit(%'
  loop
    v_def := regexp_replace(pg_get_functiondef(r.oid), E'  perform public\\.sec_rate_hit\\([^\\n]*\\);\\n', '');
    execute v_def;
  end loop;
end $m$;
drop function if exists public.sec_rate_hit(text, integer, integer);
drop table if exists public.sec_rate_hits;
