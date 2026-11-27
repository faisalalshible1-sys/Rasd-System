-- التراجع عن الترحيل 47 (نسب المالية والخصومات والصلاحيات). يُرفض إن وُجد تغيير على الإعدادات الابتدائية حتى لا يضيع.
do $$
begin
  if to_regclass('public.finance_rates') is not null and (
       (select count(*) from public.finance_rates) > 3
    or exists (select 1 from public.finance_deductions)
    or exists (select 1 from public.finance_permissions)) then
    raise exception 'لا يُتراجع عن الترحيل 47: توجد إصدارات نسب أو خصومات أو صلاحيات مسجَّلة. المنظومة كما هي.';
  end if;
end $$;
drop function if exists public.finance_rate_save(text, numeric, text, text, date, text, boolean);
drop function if exists public.finance_deduction_save(uuid, text, text, numeric, text, text, boolean, text);
drop function if exists public.finance_deduction_delete(uuid);
drop function if exists public.finance_perm_set(uuid, text, boolean);
drop function if exists public.finance_can_approve();
drop function if exists public.finance_can_edit();
drop function if exists public.finance_can_view();
drop function if exists public.finance_has(text);
drop table if exists public.finance_permissions;
drop table if exists public.finance_deductions;
drop table if exists public.finance_rates;
