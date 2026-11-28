-- الإصدار 3.4.2 — الترحيل 53: تحصين الأمان (تنبيهات Supabase).
--
-- 1) تثبيت مسار البحث (search_path) في دالتين لم يُثبَّت فيهما: fin_gl_debit_normal وfin_journal_guard.
-- 2) سحب صلاحية التنفيذ من الزائر غير المسجَّل (anon) عن دوال مساعدة مالية لا تفيد إلا المسجَّلين.
--    تبقى public_settings متاحة للزائر لأن شاشة الدخول تحتاجها.
-- لا تُمسّ بيانات. يعمل الملف مرتين دون ضرر.

alter function public.fin_gl_debit_normal(text) set search_path = public;
alter function public.fin_journal_guard() set search_path = public;

do $m$
declare f text;
begin
  foreach f in array array[
    'public.fin_cfg(text)',
    'public.fin_period_open(date)',
    'public.fin_rate_for(text, date)',
    'public.finance_can_approve()',
    'public.finance_can_edit()',
    'public.finance_can_view()',
    'public.finance_has(text)'
  ] loop
    execute format('revoke execute on function %s from public, anon', f);
    execute format('grant execute on function %s to authenticated, service_role', f);
  end loop;
end $m$;
