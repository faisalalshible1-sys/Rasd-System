-- التراجع عن الترحيل 53: يعيد الصلاحية للزائر ويزيل تثبيت مسار البحث.
do $m$
declare f text;
begin
  foreach f in array array[
    'public.fin_cfg(text)', 'public.fin_period_open(date)', 'public.fin_rate_for(text, date)',
    'public.finance_can_approve()', 'public.finance_can_edit()', 'public.finance_can_view()', 'public.finance_has(text)'
  ] loop
    execute format('grant execute on function %s to public', f);
  end loop;
end $m$;
alter function public.fin_gl_debit_normal(text) reset search_path;
alter function public.fin_journal_guard() reset search_path;
