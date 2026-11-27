-- التراجع عن الترحيل 49 (الضمانات والحسابات والتحويلات). يُرفض إن وُجدت بيانات حتى لا تضيع.
do $$
begin
  if to_regclass('public.fin_guarantees') is not null and (exists (select 1 from public.fin_guarantees)
     or exists (select 1 from public.fin_accounts) or exists (select 1 from public.fin_transfers)) then
    raise exception 'لا يُتراجع عن الترحيل 49: توجد ضمانات أو حسابات أو تحويلات مسجَّلة. المنظومة كما هي.';
  end if;
end $$;
drop table if exists public.fin_transfers;
drop table if exists public.fin_accounts;
drop table if exists public.fin_guarantees;
drop function if exists public.fin_need_approve();
drop function if exists public.fin_account_balance(uuid);
drop function if exists public.fin_guarantee_save(uuid, text, uuid, text, numeric, date, date, text, text);
drop function if exists public.fin_guarantee_delete(uuid);
drop function if exists public.fin_guarantee_release_request(uuid, text);
drop function if exists public.fin_guarantee_release_decide(uuid, boolean, text);
drop function if exists public.fin_account_save(uuid, text, text, numeric, boolean);
drop function if exists public.fin_account_delete(uuid);
drop function if exists public.fin_transfer_create(uuid, uuid, numeric, date, text);
drop function if exists public.fin_transfer_decide(uuid, boolean, text);
drop function if exists public.fin_transfer_delete(uuid);
