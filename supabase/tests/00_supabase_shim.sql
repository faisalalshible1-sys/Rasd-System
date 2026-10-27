-- محاكاة بيئة Supabase لاختبار المخطط محلياً على Postgres عادي (لا يُشغَّل على Supabase)
do $$ begin
  if not exists (select 1 from pg_roles where rolname = 'anon') then create role anon nologin; end if;
  if not exists (select 1 from pg_roles where rolname = 'authenticated') then create role authenticated nologin; end if;
  if not exists (select 1 from pg_roles where rolname = 'service_role') then create role service_role nologin bypassrls; end if;
end $$;
grant usage on schema public to anon, authenticated, service_role;
create schema auth;
grant usage on schema auth to anon, authenticated, service_role;
create table auth.users (id uuid primary key default gen_random_uuid(), email text unique, raw_user_meta_data jsonb default '{}'::jsonb, updated_at timestamptz);
create table auth.identities (id uuid primary key default gen_random_uuid(), user_id uuid references auth.users(id) on delete cascade, provider text, identity_data jsonb, updated_at timestamptz);
create function auth.uid() returns uuid language sql stable as $$
  select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid $$;
grant execute on function auth.uid() to anon, authenticated, service_role;
create publication supabase_realtime;
-- الصلاحيات الافتراضية كما في Supabase
alter default privileges in schema public grant all on tables to anon, authenticated, service_role;
alter default privileges in schema public grant all on functions to anon, authenticated, service_role;
alter default privileges in schema public grant all on sequences to anon, authenticated, service_role;
-- المصادقة متعددة العوامل والجلسات وسجل المصادقة (للإصدار الثاني)
alter table auth.users add column if not exists last_sign_in_at timestamptz;
create table auth.mfa_factors (id uuid primary key default gen_random_uuid(), user_id uuid references auth.users(id) on delete cascade,
  friendly_name text, factor_type text default 'totp', status text not null default 'unverified',
  created_at timestamptz default now(), updated_at timestamptz default now());
create table auth.sessions (id uuid primary key default gen_random_uuid(), user_id uuid references auth.users(id) on delete cascade,
  created_at timestamptz default now(), updated_at timestamptz default now(), aal text default 'aal1', not_after timestamptz,
  refreshed_at timestamp, user_agent text, ip inet);
create table auth.audit_log_entries (instance_id uuid, id uuid primary key default gen_random_uuid(), payload json,
  created_at timestamptz default now(), ip_address varchar(64) default '');
create function auth.jwt() returns jsonb language sql stable as $$
  select coalesce(nullif(current_setting('request.jwt.claims', true), ''), '{}')::jsonb $$;
grant execute on function auth.jwt() to anon, authenticated, service_role;
