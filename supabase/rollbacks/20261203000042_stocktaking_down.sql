-- =====================================================================
-- التراجع عن الترحيل 42 (الجرد الدوري بالتسوية)
--
-- يُرفض إن كانت في القسم أي جلسة جرد. عندها تبقى المنظومة كما هي. لا يمس المخازن ولا مستنداتها.
-- =====================================================================
do $$
begin
  if to_regclass('public.st_counts') is null then
    return;
  end if;
  if exists (select 1 from public.st_counts) then
    raise exception 'لا يُتراجع عن الترحيل 42: في القسم جلسات جرد. المنظومة كما هي.';
  end if;
end $$;

drop function if exists public.st_count_start(jsonb);
drop function if exists public.st_count_save(uuid, jsonb);
drop function if exists public.st_count_submit(uuid);
drop function if exists public.st_count_return(uuid, text);
drop function if exists public.st_count_cancel(uuid, text);
drop function if exists public.st_count_approve(uuid, text);
drop table if exists public.st_count_lines;
drop table if exists public.st_counts;
delete from public.st_counters where scope = 'count:CN';
