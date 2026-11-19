-- =====================================================================
-- الترحيل 25: مركز الأمن السيبراني الموسّع
--   قسم مستقل لمسؤول الأمن السيبراني (CISO) ومدير المكتب: لوحة شاملة بالمؤشرات والسلاسل الزمنية وخريطة النشاط،
--   وفحص الوضع الأمني لقاعدة البيانات والسياسات، وكشف الأنماط غير المعتادة، ومصفوفة الصلاحيات الفعلية لكل مستخدم،
--   ونشاط البيانات (التصدير والطباعة والأرقام الإشارية والملفات والتخزين والحذف)، والبحث في سجل التدقيق كاملاً،
--   وسجل الحوادث الأمنية. وصلاحيات أوسع للمسؤول: تجميد المنظومة فوراً عند الطوارئ (يرفعه المدير)،
--   وتعليق الصلاحيات الدقيقة لأي مستخدم، إضافة إلى قفل الدخول والإخراج من الأجهزة وحظرها وقفل المحادثات.
-- يُشغَّل بعد الترحيلات 1–24، ويمكن إعادة تشغيله دون ضرر.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. سجل الحوادث الأمنية
-- ---------------------------------------------------------------------
create table if not exists public.security_incidents (
  id          uuid primary key default gen_random_uuid(),
  title       text not null check (length(btrim(title)) between 3 and 200),
  severity    text not null default 'medium' check (severity in ('low', 'medium', 'high', 'critical')),
  status      text not null default 'open' check (status in ('open', 'investigating', 'contained', 'closed')),
  category    text not null default 'other' check (category in ('access', 'device', 'data', 'chat', 'account', 'policy', 'other')),
  details     text not null default '' check (length(details) <= 8000),
  actions     text not null default '' check (length(actions) <= 8000),
  user_id     uuid references public.profiles(id) on delete set null,
  detected_at timestamptz not null default now(),
  closed_at   timestamptz,
  created_by  uuid references public.profiles(id) on delete set null default auth.uid(),
  created_at  timestamptz not null default now(),
  updated_by  uuid references public.profiles(id) on delete set null,
  updated_at  timestamptz not null default now()
);
create index if not exists security_incidents_user_idx on public.security_incidents (user_id);
create index if not exists security_incidents_created_by_idx on public.security_incidents (created_by);
create index if not exists security_incidents_updated_by_idx on public.security_incidents (updated_by);
create index if not exists security_incidents_status_idx on public.security_incidents (status, detected_at desc);
create index if not exists audit_log_at_idx2 on public.audit_log (at desc, action);

create or replace function public.sec_save_incident(p_id uuid, p_data jsonb)
returns uuid
language plpgsql security definer set search_path = public
as $$
declare
  o     public.security_incidents;
  n     public.security_incidents;
  v_usr uuid;
begin
  if not public.can_audit() then
    raise exception 'سجل الحوادث لمسؤول الأمن السيبراني ومدير المكتب' using errcode = '42501';
  end if;
  if jsonb_typeof(coalesce(p_data, 'null'::jsonb)) <> 'object' then
    raise exception 'بيانات غير صالحة' using errcode = '22023';
  end if;
  if nullif(p_data ->> 'user_id', '') is not null then
    begin
      v_usr := (p_data ->> 'user_id')::uuid;
    exception when others then
      raise exception 'المستخدم غير صالح' using errcode = '22023';
    end;
  end if;
  if p_id is null then
    insert into public.security_incidents (title, severity, status, category, details, actions, user_id, detected_at, updated_by)
    values (btrim(coalesce(p_data ->> 'title', '')), coalesce(p_data ->> 'severity', 'medium'), coalesce(p_data ->> 'status', 'open'),
            coalesce(p_data ->> 'category', 'other'), coalesce(p_data ->> 'details', ''), coalesce(p_data ->> 'actions', ''), v_usr,
            coalesce(nullif(p_data ->> 'detected_at', '')::timestamptz, now()), auth.uid())
    returning * into n;
  else
    select * into o from public.security_incidents where id = p_id for update;
    if not found then
      raise exception 'الحادثة غير موجودة' using errcode = 'P0002';
    end if;
    update public.security_incidents set
      title = coalesce(btrim(p_data ->> 'title'), title), severity = coalesce(p_data ->> 'severity', severity),
      status = coalesce(p_data ->> 'status', status), category = coalesce(p_data ->> 'category', category),
      details = coalesce(p_data ->> 'details', details), actions = coalesce(p_data ->> 'actions', actions),
      user_id = case when p_data ? 'user_id' then v_usr else user_id end,
      detected_at = coalesce(nullif(p_data ->> 'detected_at', '')::timestamptz, detected_at),
      updated_by = auth.uid(), updated_at = now()
    where id = p_id
    returning * into n;
  end if;
  update public.security_incidents
     set closed_at = case when n.status = 'closed' then coalesce(n.closed_at, now()) end
   where id = n.id
  returning * into n;
  perform public.write_audit('security.incident_save', null, null,
    jsonb_build_object('incident_id', n.id, 'title', n.title, 'severity', n.severity, 'status', n.status, 'created', p_id is null,
                       'changes', case when p_id is null then null
                                       else public.jsonb_changes(to_jsonb(o), to_jsonb(n), array['updated_at', 'updated_by']) end),
    'الحوادث الأمنية');
  return n.id;
end;
$$;

create or replace function public.sec_delete_incident(p_id uuid)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  o public.security_incidents;
begin
  if not public.is_director() then
    raise exception 'حذف الحوادث لمدير المكتب وحده؛ أغلقها بدلاً من ذلك' using errcode = '42501';
  end if;
  delete from public.security_incidents where id = p_id returning * into o;
  if o.id is null then
    raise exception 'الحادثة غير موجودة' using errcode = 'P0002';
  end if;
  perform public.write_audit('security.incident_delete', null, null,
    jsonb_build_object('incident_id', p_id, 'title', o.title, 'severity', o.severity, 'status', o.status), 'الحوادث الأمنية');
end;
$$;

-- ---------------------------------------------------------------------
-- 2. صلاحيات الطوارئ
-- ---------------------------------------------------------------------
-- يجمّد المسؤول المنظومة فوراً عند الاشتباه؛ رفع التجميد لمدير المكتب وحده
create or replace function public.sec_freeze(p_on boolean, p_reason text)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  v_old boolean := public.setting_bool('security.freeze', false);
begin
  if not public.can_audit() then
    raise exception 'التجميد لمدير المكتب ومسؤول الأمن السيبراني' using errcode = '42501';
  end if;
  if not coalesce(p_on, false) and not public.is_director() then
    raise exception 'رفع التجميد لمدير المكتب وحده' using errcode = '42501';
  end if;
  if length(btrim(coalesce(p_reason, ''))) < 3 then
    raise exception 'اكتب السبب' using errcode = '22023';
  end if;
  if v_old = coalesce(p_on, false) then
    return;
  end if;
  insert into public.app_settings (key, value, updated_at, updated_by)
  values ('security.freeze', to_jsonb(coalesce(p_on, false)), now(), auth.uid())
  on conflict (key) do update set value = excluded.value, updated_at = excluded.updated_at, updated_by = excluded.updated_by;
  perform public.write_audit('security.emergency_freeze', null, null,
    jsonb_build_object('on', coalesce(p_on, false), 'reason', left(btrim(p_reason), 500)), 'مركز الأمن');
end;
$$;

-- تعليق كل الصلاحيات الدقيقة لمستخدم (يعيد المدير منحها بعد التحقق)
create or replace function public.sec_suspend_grants(p_user uuid, p_reason text)
returns integer
language plpgsql security definer set search_path = public
as $$
declare
  v_scopes text[];
begin
  if not public.can_audit() then
    raise exception 'تعليق الصلاحيات لمدير المكتب ومسؤول الأمن السيبراني' using errcode = '42501';
  end if;
  if length(btrim(coalesce(p_reason, ''))) < 3 then
    raise exception 'اكتب السبب' using errcode = '22023';
  end if;
  with d as (delete from public.user_grants where user_id = p_user returning scope)
  select coalesce(array_agg(scope order by scope), '{}') into v_scopes from d;
  if coalesce(array_length(v_scopes, 1), 0) = 0 then
    return 0;
  end if;
  perform public.write_audit('security.grants_suspend', null, null,
    jsonb_build_object('user_id', p_user, 'scopes', to_jsonb(v_scopes), 'reason', left(btrim(p_reason), 500)),
    public.actor_name(p_user));
  return array_length(v_scopes, 1);
end;
$$;

-- ---------------------------------------------------------------------
-- 3. اللوحة الشاملة
-- ---------------------------------------------------------------------
create or replace function public.sec_last_seen(p_user uuid)
returns timestamptz
language sql stable security definer set search_path = public
as $$
  select max(greatest(last_seen, last_login)) from public.user_devices where user_id = p_user
$$;

create or replace function public.sec_dashboard(p_days integer default 30)
returns jsonb
language plpgsql stable security definer set search_path = public, auth
as $$
declare
  v_days     integer := least(greatest(coalesce(p_days, 30), 1), 365);
  v_from     timestamptz := now() - make_interval(days => v_days);
  v_sessions integer;
  v_logins   jsonb := '[]'::jsonb;
  v_storage  jsonb := '[]'::jsonb;
begin
  if not public.can_audit() then
    raise exception 'مركز الأمن لمدير المكتب ومسؤول الأمن السيبراني' using errcode = '42501';
  end if;
  if to_regclass('auth.sessions') is not null then
    execute 'select count(*) from auth.sessions where coalesce(not_after, ''infinity'') > now()' into v_sessions;
  end if;
  if to_regclass('auth.audit_log_entries') is not null then
    execute $q$select coalesce(jsonb_agg(jsonb_build_object('day', d, 'logins', n, 'other', o) order by d), '[]'::jsonb) from (
                 select (created_at at time zone 'Africa/Tripoli')::date d,
                        count(*) filter (where payload ->> 'action' = 'login') n,
                        count(*) filter (where payload ->> 'action' <> 'login') o
                   from auth.audit_log_entries where created_at >= $1 group by 1) s$q$
      into v_logins using v_from;
  end if;
  if to_regclass('storage.objects') is not null then
    execute $q$select coalesce(jsonb_agg(jsonb_build_object('bucket', bucket_id, 'files', n, 'bytes', b, 'new', nw) order by b desc), '[]'::jsonb)
                 from (select bucket_id, count(*) n, coalesce(sum((metadata ->> 'size')::bigint), 0) b,
                              count(*) filter (where created_at >= $1) nw
                         from storage.objects group by bucket_id) s$q$
      into v_storage using v_from;
  end if;
  return jsonb_build_object(
    'days', v_days,
    'generated_at', now(),
    'viewer', case when public.is_director() then 'director' else 'auditor' end,
    'freeze', public.setting_bool('security.freeze', false),
    'users', (select jsonb_build_object(
        'total', count(*), 'active', count(*) filter (where active and role is not null),
        'pending', count(*) filter (where not active and role is null),
        'disabled', count(*) filter (where not active and role is not null),
        'locked', count(*) filter (where locked_until > now()),
        'mfa', count(*) filter (where active and public.mfa_enrolled(id)),
        'no_mfa_sensitive', count(*) filter (where active and role::text in ('director', 'security_auditor', 'office_staff')
                                                and not public.mfa_enrolled(id)),
        'stale_60', count(*) filter (where active and role is not null
                                       and coalesce(public.sec_last_seen(id), activated_at, created_at) < now() - interval '60 days'),
        'by_role', (select coalesce(jsonb_object_agg(r, n), '{}'::jsonb) from (
                      select coalesce(role::text, 'pending') r, count(*) n from public.profiles group by 1) s),
        'with_grants', (select count(distinct user_id) from public.user_grants),
        'grants', (select count(*) from public.user_grants))
      from public.profiles),
    'sessions', v_sessions,
    'devices', (select jsonb_build_object('total', count(*), 'trusted', count(*) filter (where trusted and blocked_at is null),
                  'blocked', count(*) filter (where blocked_at is not null),
                  'new', count(*) filter (where first_seen >= v_from),
                  'active_24h', count(*) filter (where last_seen > now() - interval '1 day'),
                  'platforms', (select coalesce(jsonb_object_agg(coalesce(platform, '?'), n), '{}'::jsonb) from (
                                  select platform, count(*) n from public.user_devices group by 1) s))
                from public.user_devices),
    'audit', (select jsonb_build_object(
        'events', count(*),
        'writes', count(*) filter (where action ~ '\.(create|update|save|set|add|delete|remove|move|merge)'),
        'deletes', count(*) filter (where action like '%delete%' or action like '%remove%'),
        'exports', count(*) filter (where action like 'export.%'),
        'security', count(*) filter (where action like 'security.%' or action like 'user.%'),
        'settings', count(*) filter (where action in ('setting.update', 'security.setting') or action like 'config.%'),
        'off_hours', count(*) filter (where extract(hour from at at time zone 'Africa/Tripoli') not between 7 and 16
                                         or extract(isodow from at at time zone 'Africa/Tripoli') in (5, 6)),
        'actors', count(distinct actor))
      from public.audit_log where at >= v_from),
    'categories', (select coalesce(jsonb_agg(jsonb_build_object('key', k, 'n', n) order by n desc), '[]'::jsonb) from (
        select split_part(action, '.', 1) k, count(*) n from public.audit_log where at >= v_from group by 1) s),
    'daily', (select coalesce(jsonb_agg(jsonb_build_object('day', d, 'events', n, 'deletes', x, 'security', s) order by d), '[]'::jsonb) from (
        select (at at time zone 'Africa/Tripoli')::date d, count(*) n,
               count(*) filter (where action like '%delete%') x,
               count(*) filter (where action like 'security.%' or action like 'user.%') s
          from public.audit_log where at >= v_from group by 1) q),
    'heatmap', (select coalesce(jsonb_agg(jsonb_build_array(dw, h, n)), '[]'::jsonb) from (
        select extract(isodow from at at time zone 'Africa/Tripoli')::int dw, extract(hour from at at time zone 'Africa/Tripoli')::int h,
               count(*) n
          from public.audit_log where at >= v_from group by 1, 2) q),
    'actors', (select coalesce(jsonb_agg(jsonb_build_object('id', actor, 'name', public.actor_name(actor), 'n', n, 'deletes', x,
                                                           'exports', e, 'last', l) order by n desc), '[]'::jsonb) from (
        select actor, count(*) n, count(*) filter (where action like '%delete%') x, count(*) filter (where action like 'export.%') e,
               max(at) l
          from public.audit_log where at >= v_from and actor is not null group by actor order by count(*) desc limit 15) q),
    'logins', v_logins,
    'storage', v_storage,
    'chat', (select jsonb_build_object('messages', count(*) filter (where kind <> 'system'),
                  'files', count(*) filter (where kind = 'file'), 'bytes', coalesce(sum(file_size), 0),
                  'senders', count(distinct sender), 'locked_rooms', (select count(*) from public.chat_rooms where locked))
               from public.chat_messages where created_at >= v_from),
    'refs', (select jsonb_build_object('issued', count(*), 'schemes', count(distinct scheme)) from public.ref_log where created_at >= v_from),
    'incidents', (select jsonb_build_object('open', count(*) filter (where status <> 'closed'),
                    'critical', count(*) filter (where status <> 'closed' and severity in ('high', 'critical')),
                    'total', count(*)) from public.security_incidents),
    'alerts', (select count(*) from public.security_alerts()));
end;
$$;

-- ---------------------------------------------------------------------
-- 4. فحص الوضع الأمني
-- ---------------------------------------------------------------------
create or replace function public.sec_posture()
returns setof jsonb
language plpgsql stable security definer set search_path = public, auth
as $$
declare
  v_director uuid := (select id from public.profiles where role = 'director' limit 1);
  v_n        integer;
  v_list     jsonb;
begin
  if not public.can_audit() then
    raise exception 'مركز الأمن لمدير المكتب ومسؤول الأمن السيبراني' using errcode = '42501';
  end if;

  select count(*), coalesce(jsonb_agg(c.relname order by c.relname), '[]'::jsonb) into v_n, v_list
    from pg_class c join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public' and c.relkind = 'r' and not c.relrowsecurity;
  return next jsonb_build_object('key', 'rls', 'group', 'قاعدة البيانات', 'title', 'حماية مستوى الصفوف على كل الجداول',
    'ok', v_n = 0, 'severity', 'high', 'count', v_n, 'items', v_list,
    'detail', case when v_n = 0 then 'كل جداول المنظومة محمية بسياسات قراءة.' else 'جداول بلا حماية مستوى الصفوف.' end);

  select count(*), coalesce(jsonb_agg(p.proname order by p.proname), '[]'::jsonb) into v_n, v_list
    from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prosecdef
     and not exists (select 1 from unnest(coalesce(p.proconfig, '{}')) c where c like 'search_path=%');
  return next jsonb_build_object('key', 'search_path', 'group', 'قاعدة البيانات', 'title', 'مسار بحث ثابت لكل دالة بصلاحية المالك',
    'ok', v_n = 0, 'severity', 'high', 'count', v_n, 'items', v_list,
    'detail', 'يمنع تمرير دوال مزيّفة إلى الدوال التي تعمل بصلاحية المالك.');

  select count(*), coalesce(jsonb_agg(distinct table_name), '[]'::jsonb) into v_n, v_list
    from information_schema.role_table_grants
   where grantee = 'anon' and table_schema = 'public' and privilege_type in ('INSERT', 'UPDATE', 'DELETE', 'TRUNCATE');
  return next jsonb_build_object('key', 'anon_write', 'group', 'قاعدة البيانات', 'title', 'لا كتابة لغير المسجّلين',
    'ok', v_n = 0, 'severity', 'high', 'count', v_n, 'items', v_list, 'detail', 'صلاحيات كتابة ممنوحة للدور anon.');

  select count(*), coalesce(jsonb_agg(distinct table_name), '[]'::jsonb) into v_n, v_list
    from information_schema.role_table_grants
   where grantee = 'authenticated' and table_schema = 'public' and privilege_type in ('INSERT', 'UPDATE', 'DELETE', 'TRUNCATE')
     and table_name not in ('profiles');
  return next jsonb_build_object('key', 'direct_write', 'group', 'قاعدة البيانات', 'title', 'الكتابة عبر الدوال المدققة فقط',
    'ok', v_n = 0, 'severity', 'medium', 'count', v_n, 'items', v_list,
    'detail', 'جداول يكتب فيها المستخدمون مباشرة دون المرور بدالة تتحقق وتسجّل في سجل التدقيق.');

  if to_regclass('storage.buckets') is not null then
    -- حاوية الإصدارات عامة عمداً (تنزيل التطبيق)
    execute 'select count(*), coalesce(jsonb_agg(id), ''[]''::jsonb) from storage.buckets where public and id <> ''releases''' into v_n, v_list;
    return next jsonb_build_object('key', 'buckets', 'group', 'التخزين', 'title', 'حاويات الملفات خاصة',
      'ok', v_n = 0, 'severity', 'high', 'count', v_n, 'items', v_list,
      'detail', 'المستندات والمرفقات والمراسلات لا تُقرأ إلا بصلاحية؛ حاوية الإصدارات وحدها عامة لتنزيل التطبيق.');
  end if;

  return next jsonb_build_object('key', 'director_mfa', 'group', 'الهوية', 'title', 'مدير المكتب يستخدم التحقق بخطوتين',
    'ok', public.mfa_enrolled(v_director), 'severity', 'high', 'detail', 'أهم حساب في المنظومة.');
  return next jsonb_build_object('key', 'mfa_director_policy', 'group', 'السياسات', 'title', 'فرض التحقق بخطوتين على المدير',
    'ok', public.setting_bool('security.require_mfa_director', false), 'severity', 'medium', 'detail', 'من مركز الأمان في لوحة التحكم.');
  return next jsonb_build_object('key', 'mfa_all_policy', 'group', 'السياسات', 'title', 'فرض التحقق بخطوتين على كل المستخدمين',
    'ok', public.setting_bool('security.require_mfa_all', false), 'severity', 'low', 'detail', 'يُنصح به عند اكتمال تفعيل الهواتف.');

  select count(*), coalesce(jsonb_agg(public.actor_name(id)), '[]'::jsonb) into v_n, v_list
    from public.profiles where active and role::text in ('security_auditor', 'office_staff') and not public.mfa_enrolled(id);
  return next jsonb_build_object('key', 'mfa_sensitive', 'group', 'الهوية', 'title', 'الحسابات الحساسة تستخدم التحقق بخطوتين',
    'ok', v_n = 0, 'severity', 'medium', 'count', v_n, 'items', v_list, 'detail', 'مسؤول الأمن وموظفو المكتب.');

  select count(*), coalesce(jsonb_agg(public.actor_name(id)), '[]'::jsonb) into v_n, v_list
    from public.profiles
   where active and role is not null and role::text <> 'director'
     and coalesce(public.sec_last_seen(id), activated_at, created_at) < now() - interval '60 days';
  return next jsonb_build_object('key', 'stale', 'group', 'الهوية', 'title', 'لا حسابات خاملة مفعّلة',
    'ok', v_n = 0, 'severity', 'medium', 'count', v_n, 'items', v_list, 'detail', 'حسابات مفعّلة لم تُستخدم منذ 60 يوماً؛ أوقفها إن لم تعد لازمة.');

  select count(*), coalesce(jsonb_agg(coalesce(nullif(full_name, ''), email)), '[]'::jsonb) into v_n, v_list
    from public.profiles where not active and role is null and created_at < now() - interval '7 days';
  return next jsonb_build_object('key', 'pending', 'group', 'الهوية', 'title', 'لا طلبات تسجيل معلّقة قديمة',
    'ok', v_n = 0, 'severity', 'low', 'count', v_n, 'items', v_list, 'detail', 'طلبات تسجيل مضى عليها أكثر من أسبوع.');

  return next jsonb_build_object('key', 'signups', 'group', 'السياسات', 'title', 'التسجيل الجديد مغلق عند عدم الحاجة',
    'ok', not public.setting_bool('security.signups_open', true), 'severity', 'low',
    'detail', 'إبقاؤه مفتوحاً يسمح بطلبات تسجيل من أي بريد (تبقى بانتظار التفعيل).');

  return next jsonb_build_object('key', 'idle', 'group', 'السياسات', 'title', 'قفل الجلسة بعد خمول لا يتجاوز ساعة',
    'ok', coalesce((select (value #>> '{}')::int from public.app_settings where key = 'security.idle_minutes'), 30) between 1 and 60,
    'severity', 'medium', 'detail', 'الخروج التلقائي من الأجهزة المتروكة.');

  select count(*), coalesce(jsonb_agg(public.actor_name(user_id)), '[]'::jsonb) into v_n, v_list
    from (select user_id from public.user_grants group by user_id having count(*) > 20) s;
  return next jsonb_build_object('key', 'grants_excess', 'group', 'الصلاحيات', 'title', 'لا صلاحيات دقيقة مفرطة',
    'ok', v_n = 0, 'severity', 'low', 'count', v_n, 'items', v_list,
    'detail', 'مستخدمون بأكثر من 20 صلاحية دقيقة؛ قد يكون الأنسب دور أو وحدة.');

  select count(*), coalesce(jsonb_agg(public.actor_name(g.user_id)), '[]'::jsonb) into v_n, v_list
    from (select distinct user_id from public.user_grants) g join public.profiles p on p.id = g.user_id
   where not p.active or p.role is null or p.locked_until > now();
  return next jsonb_build_object('key', 'grants_inactive', 'group', 'الصلاحيات', 'title', 'لا صلاحيات لحسابات موقوفة أو مقفلة',
    'ok', v_n = 0, 'severity', 'medium', 'count', v_n, 'items', v_list, 'detail', 'تبقى معطلة لكنها تعود إن أعيد التفعيل.');

  select count(*) into v_n from public.profiles where role = 'director';
  return next jsonb_build_object('key', 'one_director', 'group', 'الصلاحيات', 'title', 'مدير مكتب واحد',
    'ok', v_n = 1, 'severity', 'high', 'count', v_n, 'detail', 'لا يُمنح دور المدير من التطبيق.');

  select count(*) into v_n from public.profiles where active and role::text = 'security_auditor';
  return next jsonb_build_object('key', 'ciso', 'group', 'الصلاحيات', 'title', 'مسؤول أمن سيبراني مفعّل',
    'ok', v_n >= 1, 'severity', 'low', 'count', v_n, 'detail', 'فصل المهام: من يراقب غير من يدير.');

  select count(*) into v_n from public.user_devices d
   where d.blocked_at is not null and d.last_seen > d.blocked_at;
  return next jsonb_build_object('key', 'blocked_active', 'group', 'الأجهزة', 'title', 'لا نشاط من أجهزة محظورة',
    'ok', v_n = 0, 'severity', 'high', 'count', v_n, 'detail', 'أجهزة حاولت الفتح بعد حظرها.');

  select count(*) into v_n from public.security_incidents where status <> 'closed' and severity in ('high', 'critical');
  return next jsonb_build_object('key', 'incidents', 'group', 'الحوادث', 'title', 'لا حوادث عالية الخطورة مفتوحة',
    'ok', v_n = 0, 'severity', 'high', 'count', v_n, 'detail', 'من سجل الحوادث الأمنية.');

  return next jsonb_build_object('key', 'freeze', 'group', 'السياسات', 'title', 'المنظومة غير مجمّدة',
    'ok', not public.setting_bool('security.freeze', false), 'severity', 'low', 'detail', 'التجميد إجراء طوارئ مؤقت.');
end;
$$;

-- ---------------------------------------------------------------------
-- 5. كشف الأنماط غير المعتادة
-- ---------------------------------------------------------------------
create or replace function public.sec_anomalies(p_days integer default 7)
returns setof jsonb
language plpgsql stable security definer set search_path = public
as $$
declare
  v_from timestamptz := now() - make_interval(days => least(greatest(coalesce(p_days, 7), 1), 90));
begin
  if not public.can_audit() then
    raise exception 'مركز الأمن لمدير المكتب ومسؤول الأمن السيبراني' using errcode = '42501';
  end if;
  -- حذف كثير في ساعة واحدة
  return query
    select jsonb_build_object('kind', 'mass_delete', 'severity', 'high', 'user_id', actor, 'name', public.actor_name(actor),
             'title', 'حذف ' || count(*) || ' عنصراً خلال ساعة', 'at', max(at), 'count', count(*))
      from public.audit_log
     where at >= v_from and (action like '%delete%' or action like '%remove%') and actor is not null
     group by actor, date_trunc('hour', at)
    having count(*) >= 10;
  -- تصدير كثير في يوم واحد
  return query
    select jsonb_build_object('kind', 'mass_export', 'severity', 'medium', 'user_id', actor, 'name', public.actor_name(actor),
             'title', 'استخرج ' || count(*) || ' ملفاً في يوم واحد', 'at', max(at), 'count', count(*),
             'rows', sum(coalesce((detail ->> 'rows')::bigint, 0)))
      from public.audit_log
     where at >= v_from and action like 'export.%' and actor is not null
     group by actor, (at at time zone 'Africa/Tripoli')::date
    having count(*) >= 25;
  -- كتابة خارج أوقات الدوام
  return query
    select jsonb_build_object('kind', 'off_hours', 'severity', 'low', 'user_id', actor, 'name', public.actor_name(actor),
             'title', count(*) || ' تعديلاً خارج أوقات الدوام', 'at', max(at), 'count', count(*))
      from public.audit_log
     where at >= v_from and actor is not null and action not like 'export.%' and action not like 'security.device%'
       and (extract(hour from at at time zone 'Africa/Tripoli') not between 6 and 18
            or extract(isodow from at at time zone 'Africa/Tripoli') in (5, 6))
     group by actor
    having count(*) >= 5;
  -- تغييرات الصلاحيات والإعدادات الحساسة
  return query
    select jsonb_build_object('kind', 'privilege', 'severity', 'medium', 'user_id', actor, 'name', public.actor_name(actor),
             'title', case when action = 'user.grants' then 'تعديل صلاحيات دقيقة: ' || project_label
                           when action in ('user.update', 'user.activate', 'user.unit') then 'تغيير صلاحيات حساب: ' || project_label
                           else 'تغيير إعداد أمني: ' || project_label end,
             'at', at, 'count', 1, 'action', action)
      from public.audit_log
     where at >= v_from and (action in ('user.grants', 'user.update', 'user.activate', 'user.unit', 'security.setting', 'security.emergency_freeze',
                                         'security.grants_suspend', 'security.mfa_reset'))
     order by at desc limit 60;
  -- أجهزة جديدة لحسابات حساسة
  return query
    select jsonb_build_object('kind', 'new_device', 'severity', 'medium', 'user_id', d.user_id, 'name', public.actor_name(d.user_id),
             'title', 'جهاز جديد لحساب ' || case p.role::text when 'director' then 'المدير' when 'security_auditor' then 'مسؤول الأمن'
                                                              else 'موظف المكتب' end || ': ' || coalesce(nullif(d.label, ''), d.platform, ''),
             'at', d.first_seen, 'count', 1)
      from public.user_devices d join public.profiles p on p.id = d.user_id
     where d.first_seen >= v_from and p.role::text in ('director', 'security_auditor', 'office_staff');
  -- حجم مرفقات كبير في المراسلات
  return query
    select jsonb_build_object('kind', 'chat_volume', 'severity', 'low', 'user_id', sender, 'name', public.actor_name(sender),
             'title', 'أرسل مرفقات بحجم ' || round(sum(file_size) / 1048576.0) || ' ميجابايت', 'at', max(created_at), 'count', count(*))
      from public.chat_messages
     where created_at >= v_from and kind = 'file' and sender is not null
     group by sender
    having sum(file_size) > 300 * 1048576;
  -- محاولات فاشلة متكررة (رفض العمليات لعدم الصلاحية لا يُسجَّل، فنقيس محاولات الأجهزة المحظورة)
  return query
    select jsonb_build_object('kind', 'blocked_device', 'severity', 'high', 'user_id', actor, 'name', public.actor_name(actor),
             'title', count(*) || ' محاولة من جهاز محظور', 'at', max(at), 'count', count(*))
      from public.audit_log
     where at >= v_from and action = 'security.device_blocked_attempt'
     group by actor;
end;
$$;

-- ---------------------------------------------------------------------
-- 6. مصفوفة الصلاحيات الفعلية
-- ---------------------------------------------------------------------
create or replace function public.sec_access_matrix()
returns setof jsonb
language plpgsql stable security definer set search_path = public
as $$
begin
  if not public.can_audit() then
    raise exception 'مركز الأمن لمدير المكتب ومسؤول الأمن السيبراني' using errcode = '42501';
  end if;
  return query
    select jsonb_build_object(
      'id', p.id, 'name', public.actor_name(p.id), 'email', p.email, 'role', p.role, 'department', p.department,
      'unit', p.unit, 'unit_head', p.unit_head, 'active', p.active, 'locked', p.locked_until > now(),
      'mfa', public.mfa_enrolled(p.id), 'last_seen', public.sec_last_seen(p.id),
      'devices', (select count(*) from public.user_devices d where d.user_id = p.id),
      'grants', coalesce((select jsonb_agg(g.scope order by g.scope) from public.user_grants g where g.user_id = p.id), '[]'::jsonb),
      'forms', (select count(*) from public.form_defs d where d.active and (
                  p.role::text = 'director' or p.role::text = any (d.responsible)
                  or (p.role::text = 'dept_head' and (('head:technical' = any (d.responsible) and p.department = 'technical')
                                                     or ('head:acceptance' = any (d.responsible) and p.department = 'acceptance')
                                                     or 'head:supervising' = any (d.responsible)))
                  or exists (select 1 from public.user_grants g where g.user_id = p.id and g.scope = 'form:' || d.key))),
      'forms_total', (select count(*) from public.form_defs where active),
      'events_30d', (select count(*) from public.audit_log a where a.actor = p.id and a.at > now() - interval '30 days'),
      'deletes_30d', (select count(*) from public.audit_log a where a.actor = p.id and a.at > now() - interval '30 days'
                        and a.action like '%delete%'),
      'exports_30d', (select count(*) from public.audit_log a where a.actor = p.id and a.at > now() - interval '30 days'
                        and a.action like 'export.%'),
      'messages_30d', (select count(*) from public.chat_messages m where m.sender = p.id and m.created_at > now() - interval '30 days'))
    from public.profiles p
    order by p.active desc, (p.role is null), p.role, public.actor_name(p.id);
end;
$$;

-- ---------------------------------------------------------------------
-- 7. نشاط البيانات وسجل التدقيق كاملاً
-- ---------------------------------------------------------------------
create or replace function public.sec_data_activity(p_days integer default 30)
returns jsonb
language plpgsql stable security definer set search_path = public
as $$
declare
  v_days integer := least(greatest(coalesce(p_days, 30), 1), 365);
  v_from timestamptz := now() - make_interval(days => v_days);
begin
  if not public.can_audit() then
    raise exception 'مركز الأمن لمدير المكتب ومسؤول الأمن السيبراني' using errcode = '42501';
  end if;
  return jsonb_build_object(
    'days', v_days,
    'exports', coalesce((select jsonb_agg(jsonb_build_object('at', at, 'name', actor_name, 'kind', split_part(action, '.', 2),
                          'source', detail ->> 'source', 'title', detail ->> 'title', 'format', detail ->> 'format',
                          'rows', detail -> 'rows', 'bytes', detail -> 'bytes') order by at desc)
                         from (select * from public.audit_log where at >= v_from and action like 'export.%' order by at desc limit 400) s), '[]'::jsonb),
    'export_formats', coalesce((select jsonb_object_agg(f, n) from (
                         select coalesce(detail ->> 'format', '?') f, count(*) n from public.audit_log
                          where at >= v_from and action like 'export.%' group by 1) s), '{}'::jsonb),
    'deletes', coalesce((select jsonb_agg(jsonb_build_object('at', at, 'name', actor_name, 'action', action, 'label', project_label,
                          'detail', detail - 'changes') order by at desc)
                         from (select * from public.audit_log where at >= v_from and (action like '%delete%' or action like '%remove%')
                                order by at desc limit 300) s), '[]'::jsonb),
    'refs', coalesce((select jsonb_agg(jsonb_build_object('at', l.created_at, 'ref', l.ref, 'scheme', s.name, 'by', public.actor_name(l.created_by),
                        'source', l.source, 'title', l.title) order by l.created_at desc)
                       from (select * from public.ref_log where created_at >= v_from order by created_at desc limit 300) l
                       join public.ref_schemes s on s.key = l.scheme), '[]'::jsonb),
    'uploads', coalesce((select jsonb_agg(jsonb_build_object('at', f.created_at, 'by', public.actor_name(f.created_by), 'name', f.name,
                           'mime', f.mime, 'size', f.size_bytes,
                           'where', case when f.revision_id is not null then 'مستند فني' when f.record_id is not null then 'سجل وحدة'
                                         else 'تقرير إشراف' end) order by f.created_at desc)
                          from (select * from public.doc_files where created_at >= v_from order by created_at desc limit 300) f), '[]'::jsonb),
    'uploads_total', (select jsonb_build_object('files', count(*), 'bytes', coalesce(sum(size_bytes), 0)) from public.doc_files),
    'settings', coalesce((select jsonb_agg(jsonb_build_object('at', at, 'name', actor_name, 'key', detail ->> 'key',
                            'from', detail -> 'from', 'to', detail -> 'to', 'action', action) order by at desc)
                           from (select * from public.audit_log where at >= v_from and (action in ('setting.update', 'security.setting')
                                   or action like 'config.%') order by at desc limit 200) s), '[]'::jsonb));
end;
$$;

create or replace function public.sec_audit_search(p_from timestamptz default null, p_to timestamptz default null, p_actor uuid default null,
                                                   p_prefix text default null, p_text text default null, p_limit integer default 500)
returns setof public.audit_log
language plpgsql stable security definer set search_path = public
as $$
begin
  if not public.can_audit() then
    raise exception 'مركز الأمن لمدير المكتب ومسؤول الأمن السيبراني' using errcode = '42501';
  end if;
  return query
    select * from public.audit_log a
     where (p_from is null or a.at >= p_from) and (p_to is null or a.at < p_to)
       and (p_actor is null or a.actor = p_actor)
       and (coalesce(p_prefix, '') = '' or a.action like p_prefix || '%')
       and (coalesce(btrim(p_text), '') = '' or a.project_label ilike '%' || btrim(p_text) || '%'
            or a.actor_name ilike '%' || btrim(p_text) || '%' or a.detail::text ilike '%' || btrim(p_text) || '%')
     order by a.at desc, a.id desc
     limit least(greatest(coalesce(p_limit, 500), 1), 5000);
end;
$$;

-- ---------------------------------------------------------------------
-- 8. القراءة والصلاحيات
-- ---------------------------------------------------------------------
alter table public.security_incidents enable row level security;
drop policy if exists security_incidents_read on public.security_incidents;
create policy security_incidents_read on public.security_incidents for select to authenticated
  using ((select public.can_audit()));
revoke all on public.security_incidents from anon;
revoke insert, update, delete, truncate on public.security_incidents from authenticated;
grant select on public.security_incidents to authenticated;
grant all on public.security_incidents to service_role;

do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime')
     and not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and tablename = 'security_incidents') then
    execute 'alter publication supabase_realtime add table public.security_incidents';
  end if;
end $$;

revoke execute on function
  public.sec_save_incident(uuid, jsonb), public.sec_delete_incident(uuid), public.sec_freeze(boolean, text),
  public.sec_suspend_grants(uuid, text), public.sec_last_seen(uuid), public.sec_dashboard(integer), public.sec_posture(),
  public.sec_anomalies(integer), public.sec_access_matrix(), public.sec_data_activity(integer),
  public.sec_audit_search(timestamptz, timestamptz, uuid, text, text, integer)
from public, anon;
grant execute on function
  public.sec_save_incident(uuid, jsonb), public.sec_delete_incident(uuid), public.sec_freeze(boolean, text),
  public.sec_suspend_grants(uuid, text), public.sec_dashboard(integer), public.sec_posture(),
  public.sec_anomalies(integer), public.sec_access_matrix(), public.sec_data_activity(integer),
  public.sec_audit_search(timestamptz, timestamptz, uuid, text, text, integer)
to authenticated;

notify pgrst, 'reload schema';
