-- =====================================================================
--  الإصدارات والتحديث التلقائي.
--  يسجّل سير عمل «release» على GitHub كل إصدار هنا بعد موافقة مدير المكتب،
--  ويقرأ التطبيق أحدث إصدار لمنصته فيعرض «يتوفر تحديث» أو يطلب التحديث الإلزامي.
--  القراءة للجميع، والكتابة لمفتاح الخدمة (service) المستخدم في GitHub فقط.
-- =====================================================================
create table if not exists public.app_releases (
  id           bigint generated always as identity primary key,
  platform     text not null check (platform in ('android', 'windows', 'web', 'ios')),
  version      text not null,
  build        integer not null check (build > 0),
  url          text not null,
  notes        text not null default '',
  mandatory    boolean not null default false,
  published_at timestamptz not null default now(),
  unique (platform, build)
);
create index if not exists app_releases_latest_idx on public.app_releases (platform, build desc);

alter table public.app_releases enable row level security;
drop policy if exists app_releases_read on public.app_releases;
create policy app_releases_read on public.app_releases for select to anon, authenticated using (true);

revoke all on public.app_releases from anon, authenticated;
grant select on public.app_releases to anon, authenticated;

do $$
begin
  if not exists (select 1 from pg_publication_tables
                 where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'app_releases') then
    alter publication supabase_realtime add table public.app_releases;
  end if;
end $$;

-- حاوية ملفات الإصدارات (عامة للتنزيل). ينشئها سير العمل أيضاً إن لم تكن موجودة.
do $$
begin
  if to_regclass('storage.buckets') is not null then
    execute $q$insert into storage.buckets (id, name, public) values ('releases', 'releases', true)
               on conflict (id) do nothing$q$;
  end if;
end $$;
