-- التراجع عن الترحيل 45 (المعالم والمؤشرات). يُرفض إن وُجدت بيانات حتى لا تضيع.
do $$
begin
  if (to_regclass('public.pm_milestones') is not null and exists (select 1 from public.pm_milestones))
     or (to_regclass('public.kpi_defs') is not null and exists (select 1 from public.kpi_defs)) then
    raise exception 'لا يُتراجع عن الترحيل 45: توجد معالم أو مؤشرات مسجَّلة. المنظومة كما هي.';
  end if;
end $$;
drop function if exists public.pm_milestone_save(uuid, uuid, text, date, date, text, integer);
drop function if exists public.pm_milestone_status(uuid, text, date);
drop function if exists public.pm_milestone_delete(uuid);
drop function if exists public.kpi_def_save(uuid, text, text, numeric, text, boolean, text);
drop function if exists public.kpi_def_delete(uuid);
drop function if exists public.kpi_value_set(uuid, text, numeric, text);
drop function if exists public.kpi_value_delete(uuid, text);
drop function if exists public.kpi_can_define();
drop function if exists public.kpi_can_record();
drop table if exists public.kpi_values;
drop table if exists public.kpi_defs;
drop table if exists public.pm_milestones;
