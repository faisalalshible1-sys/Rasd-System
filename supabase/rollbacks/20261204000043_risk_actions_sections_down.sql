-- =====================================================================
-- التراجع عن الترحيل 43 (إجراءات الاستجابة ومخاطر الأقسام الآلية)
--
-- يُرفض إن كان للمخاطر أي إجراء استجابة مسجَّل. عندها تبقى المنظومة كما هي.
-- تُحذف المخاطر المولَّدة آلياً من الأقسام (st_item/pr_order/mt_req) لأنها تُعاد من بيانات الأقسام نفسها.
-- =====================================================================
do $$
begin
  if to_regclass('public.risk_actions') is not null and exists (select 1 from public.risk_actions) then
    raise exception 'لا يُتراجع عن الترحيل 43: للمخاطر إجراءات استجابة مسجَّلة. المنظومة كما هي.';
  end if;
end $$;

drop function if exists public.risk_refresh_sections();
drop function if exists public.risk_sync_sections();
drop function if exists public.risk_section_wants();
drop function if exists public.risk_action_save(uuid, uuid, jsonb);
drop function if exists public.risk_action_status(uuid, text, text);
drop function if exists public.risk_action_delete(uuid);
drop table if exists public.risk_auto_runs;
drop table if exists public.risk_actions;
delete from public.risks where auto_key ~ '^(st_item|pr_order|mt_req):';
