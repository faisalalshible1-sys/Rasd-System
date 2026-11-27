-- التراجع عن الترحيل 46 (ميزانية المكتب). يُرفض إن وُجدت بنود حتى لا تضيع.
do $$
begin
  if to_regclass('public.budget_lines') is not null and exists (select 1 from public.budget_lines) then
    raise exception 'لا يُتراجع عن الترحيل 46: توجد بنود ميزانية أو التزامات مسجَّلة. المنظومة كما هي.';
  end if;
end $$;
drop function if exists public.budget_line_save(uuid, integer, text, text, numeric, text);
drop function if exists public.budget_line_delete(uuid);
drop function if exists public.budget_commit_save(uuid, uuid, uuid, text, numeric, numeric, date, text);
drop function if exists public.budget_commit_status(uuid, text);
drop function if exists public.budget_commit_delete(uuid);
drop function if exists public.budget_committed(uuid, uuid);
drop function if exists public.budget_can_define();
drop function if exists public.budget_can_commit();
drop table if exists public.budget_commitments;
drop table if exists public.budget_lines;
