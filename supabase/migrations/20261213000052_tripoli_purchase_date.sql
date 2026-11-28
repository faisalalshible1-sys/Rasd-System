-- الإصدار 3.4.1 — الترحيل 52: فحص تاريخ شراء الأصل بتوقيت طرابلس.
--
-- كان فحص «تاريخ الشراء لا يكون في المستقبل» في st_save_asset وst_import_assets يقارن بـ current_date (بتوقيت الخادم UTC)،
-- بينما تسجّل المشتريات تاريخ الاستلام بتوقيت طرابلس؛ فيُرفض أصل تاريخه اليوم بين 00:00 و02:00 بتوقيت طرابلس.
-- يُستبدل current_date بتاريخ طرابلس في الدالتين وحدهما، دون مساس بالبيانات. يعمل الملف مرتين دون ضرر.

do $m$
declare r record;
begin
  for r in
    select p.oid, pg_get_functiondef(p.oid) as def
      from pg_proc p join pg_namespace s on s.oid = p.pronamespace
     where s.nspname = 'public' and p.proname in ('st_save_asset', 'st_import_assets')
  loop
    if r.def like '%current_date%' then
      execute replace(r.def, 'current_date', '(now() at time zone ''Africa/Tripoli'')::date');
    end if;
  end loop;
end $m$;
