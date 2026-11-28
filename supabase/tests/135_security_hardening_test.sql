-- اختبار الترحيل 53: مسار البحث وصلاحيات الزائر
\set ON_ERROR_STOP 1
\set QUIET 1
\pset tuples_only on
\pset format unaligned

do $t$
declare f text; n integer;
begin
  select count(*) into n from pg_proc where proname in ('fin_gl_debit_normal', 'fin_journal_guard') and proconfig is not null and proconfig::text like '%search_path=public%';
  if n <> 2 then raise exception 'FAIL: مسار البحث غير مثبّت في الدالتين'; end if;
  raise notice 'PASS: مسار البحث مثبّت في الدالتين';
  foreach f in array array['public.fin_cfg(text)', 'public.fin_period_open(date)', 'public.fin_rate_for(text, date)',
      'public.finance_can_approve()', 'public.finance_can_edit()', 'public.finance_can_view()', 'public.finance_has(text)'] loop
    if has_function_privilege('anon', f, 'execute') then raise exception 'FAIL: الزائر ما زال ينفّذ %', f; end if;
    if not has_function_privilege('authenticated', f, 'execute') then raise exception 'FAIL: المسجَّل لا ينفّذ %', f; end if;
  end loop;
  raise notice 'PASS: الزائر لا ينفّذ الدوال المالية المساعدة والمسجَّل ينفّذها';
  if not has_function_privilege('anon', 'public.public_settings()', 'execute') then raise exception 'FAIL: public_settings يجب أن تبقى للزائر'; end if;
  raise notice 'PASS: public_settings باقية للزائر';
end $t$;
