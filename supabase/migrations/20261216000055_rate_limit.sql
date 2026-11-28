-- الإصدار 3.6.0 — الترحيل 55: تحديد معدل الإجراءات الحساسة (ضد الاستنزاف والآلية).
--
-- جدول خفيف يعدّ إجراءات كل مستخدم في نافذة زمنية، ودالة sec_rate_hit تمنع التجاوز.
-- تُحقَن في أولى سطور دوال الاعتماد والعكس المالية وتجميد النظام: حدٌّ سخيّ (60 مرة كل 10 دقائق للاعتماد)
-- لا يلمس الاستعمال الطبيعي ويوقف التكرار الآلي. لا تُمسّ بيانات. يعمل الملف مرتين دون ضرر.

create table if not exists public.sec_rate_hits (
  id      bigint generated always as identity primary key,
  user_id uuid not null,
  action  text not null,
  at      timestamptz not null default now()
);
create index if not exists sec_rate_hits_idx on public.sec_rate_hits (user_id, action, at desc);
alter table public.sec_rate_hits enable row level security;
revoke all on public.sec_rate_hits from public, anon, authenticated;

create or replace function public.sec_rate_hit(p_action text, p_max integer, p_window_seconds integer)
returns void language plpgsql security definer set search_path = public
as $$
declare v_uid uuid := auth.uid(); v_n integer;
begin
  if v_uid is null then return; end if;          -- نداءات داخلية وخدمية
  select count(*) into v_n from public.sec_rate_hits
   where user_id = v_uid and action = p_action and at > now() - make_interval(secs => p_window_seconds);
  if v_n >= p_max then
    raise exception 'تجاوزتَ الحد المسموح لهذا الإجراء: الحد الأقصى % طلباً خلال % دقائق. حاول بعد قليل.', p_max, greatest(1, p_window_seconds / 60)
      using errcode = '54000';
  end if;
  insert into public.sec_rate_hits (user_id, action) values (v_uid, p_action);
  if random() < 0.02 then
    delete from public.sec_rate_hits where at < now() - interval '1 day';
  end if;
end;
$$;
revoke all on function public.sec_rate_hit(text, integer, integer) from public, anon;
grant execute on function public.sec_rate_hit(text, integer, integer) to authenticated, service_role;

-- حقن النداء في الدوال الحساسة (مرة واحدة لكل دالة).
do $m$
declare r record; v_def text; v_pos integer;
begin
  for r in
    select p.oid, p.proname from pg_proc p join pg_namespace s on s.oid = p.pronamespace
     where s.nspname = 'public'
       and p.proname in ('fin_disb_decide', 'fin_disb_reverse', 'fin_guarantee_release_decide', 'fin_journal_reverse',
                         'fin_payroll_approve', 'fin_transfer_decide', 'sec_freeze')
  loop
    v_def := pg_get_functiondef(r.oid);
    continue when v_def like '%sec_rate_hit%';
    v_pos := position(E'\nbegin\n' in v_def);
    if v_pos = 0 then raise exception 'تعذّر تحديد بداية الدالة %', r.proname; end if;
    v_def := substr(v_def, 1, v_pos + 5) || format('  perform public.sec_rate_hit(%L, 60, 600);', r.proname) || E'\n' || substr(v_def, v_pos + 6);
    execute v_def;
  end loop;
end $m$;
