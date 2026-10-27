-- =====================================================================
--  إدارة المستخدمين المتقدمة ومدقق الأمن:
--    1. دور «مدقق الأمن»: اطلاع كامل للقراءة فقط على مركز الأمان وسجل التدقيق
--       وبيانات المستخدمين، دون أي صلاحية تعديل. التحقق بخطوتين إلزامي له دائماً.
--    2. البيانات الكاملة لكل مستخدم (الحساب، الأمان، الأجهزة، سجل الدخول، النشاط).
--    3. حذف المستخدم نهائياً (مدير المكتب وحده، بتأكيد البريد، ويبقى أثره في سجل التدقيق).
--  يُشغَّل بعد 20261027000007_security_auditor_role.sql. إعادة تشغيله آمنة.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. مدقق الأمن
-- ---------------------------------------------------------------------
create or replace function public.mfa_ok()
returns boolean
language plpgsql stable security definer set search_path = public, auth
as $$
declare
  v_aal  text := coalesce(auth.jwt() ->> 'aal', 'aal1');
  v_role text;
begin
  if auth.uid() is null then
    return true;
  end if;
  if public.mfa_enrolled(auth.uid()) then
    return v_aal = 'aal2';
  end if;
  select role::text into v_role from public.profiles where id = auth.uid();
  -- مدقق الأمن يطّلع على بيانات حساسة، فلا يرى شيئاً قبل تفعيل التحقق بخطوتين
  if v_role = 'security_auditor' then
    return false;
  end if;
  if public.setting_bool('security.require_mfa_all', false) then
    return false;
  end if;
  if v_role = 'director' and public.setting_bool('security.require_mfa_director', false) then
    return false;
  end if;
  return true;
end;
$$;

create or replace function public.is_auditor()
returns boolean
language sql stable security definer set search_path = public
as $$
  select exists (select 1 from public.profiles where id = auth.uid() and active and role::text = 'security_auditor')
     and public.mfa_ok()
$$;

-- من يحق له الاطلاع على بيانات الأمان والتدقيق: المدير ومدقق الأمن
create or replace function public.can_audit()
returns boolean
language sql stable security definer set search_path = public
as $$
  select public.is_director() or public.is_auditor()
$$;

-- المدير ومدقق الأمن يريان كل الحسابات (بما فيها الموقوفة والمعلّقة) وسجل التدقيق كاملاً
drop policy if exists profiles_read on public.profiles;
create policy profiles_read on public.profiles for select to authenticated
  using (id = auth.uid() or public.can_audit() or (public.is_member() and active));

drop policy if exists audit_read on public.audit_log;
create policy audit_read on public.audit_log for select to authenticated
  using (public.can_audit() or (public.is_member() and project_id is not null));

-- ---------------------------------------------------------------------
-- 2. مركز الأمان: قراءة للمدير ومدقق الأمن، والإجراءات للمدير وحده
-- ---------------------------------------------------------------------
create or replace function public.security_overview()
returns jsonb
language plpgsql stable security definer set search_path = public, auth
as $$
declare
  v_sessions integer := null;
  v_logins   integer := null;
  v_director uuid := (select id from public.profiles where role = 'director' limit 1);
begin
  if not public.can_audit() then
    raise exception 'مركز الأمان لمدير المكتب ومدقق الأمن' using errcode = '42501';
  end if;
  if to_regclass('auth.sessions') is not null then
    execute 'select count(*) from auth.sessions where coalesce(not_after, ''infinity'') > now()' into v_sessions;
  end if;
  if to_regclass('auth.audit_log_entries') is not null then
    execute $q$select count(*) from auth.audit_log_entries
               where created_at > now() - interval '7 days' and payload ->> 'action' = 'login'$q$ into v_logins;
  end if;
  return jsonb_build_object(
    'viewer', case when public.is_director() then 'director' else 'auditor' end,
    'director_mfa', public.mfa_enrolled(v_director),
    'my_mfa', public.mfa_enrolled(auth.uid()),
    'current_aal', coalesce(auth.jwt() ->> 'aal', 'aal1'),
    'users_total', (select count(*) from public.profiles),
    'users_active', (select count(*) from public.profiles where active),
    'users_pending', (select count(*) from public.profiles where not active and role is null),
    'users_disabled', (select count(*) from public.profiles where not active and role is not null),
    'users_mfa', (select count(*) from public.profiles p where p.active and public.mfa_enrolled(p.id)),
    'auditors', (select count(*) from public.profiles where active and role::text = 'security_auditor'),
    'sessions_active', v_sessions,
    'logins_7d', v_logins,
    'tables_without_rls', (select coalesce(jsonb_agg(c.relname order by c.relname), '[]'::jsonb)
                             from pg_class c join pg_namespace n on n.oid = c.relnamespace
                            where n.nspname = 'public' and c.relkind = 'r' and not c.relrowsecurity),
    'pending_requests', (select count(*) from public.change_requests where state = 'pending'),
    'security_events_7d', (select count(*) from public.audit_log
                            where at > now() - interval '7 days'
                              and (action like 'security.%' or action like 'user.%')));
end;
$$;

create or replace function public.security_users()
returns table (id uuid, full_name text, email text, role public.app_role, active boolean,
               mfa boolean, last_sign_in_at timestamptz, created_at timestamptz)
language plpgsql stable security definer set search_path = public, auth
as $$
begin
  if not public.can_audit() then
    raise exception 'مركز الأمان لمدير المكتب ومدقق الأمن' using errcode = '42501';
  end if;
  return query
    select p.id, p.full_name, p.email, p.role, p.active, public.mfa_enrolled(p.id),
           (to_jsonb(u) ->> 'last_sign_in_at')::timestamptz, p.created_at
      from public.profiles p left join auth.users u on u.id = p.id
     order by p.active desc, p.created_at;
end;
$$;

create or replace function public.list_sessions()
returns setof jsonb
language plpgsql stable security definer set search_path = public, auth
as $$
begin
  if not public.can_audit() then
    raise exception 'مركز الأمان لمدير المكتب ومدقق الأمن' using errcode = '42501';
  end if;
  if to_regclass('auth.sessions') is null then
    return;
  end if;
  return query execute $q$
    select jsonb_build_object(
             'id', s.id, 'user_id', s.user_id, 'name', public.actor_name(s.user_id),
             'created_at', s.created_at, 'updated_at', coalesce(to_jsonb(s) ->> 'refreshed_at', to_jsonb(s) ->> 'updated_at'),
             'user_agent', to_jsonb(s) ->> 'user_agent', 'ip', to_jsonb(s) ->> 'ip', 'aal', to_jsonb(s) ->> 'aal',
             'current', s.id::text = coalesce(auth.jwt() ->> 'session_id', ''))
      from auth.sessions s
     where coalesce(s.not_after, 'infinity') > now()
     order by coalesce(to_jsonb(s) ->> 'refreshed_at', to_jsonb(s) ->> 'updated_at', s.created_at::text) desc
     limit 300$q$;
end;
$$;

create or replace function public.login_history(p_limit integer default 200)
returns setof jsonb
language plpgsql stable security definer set search_path = public, auth
as $$
begin
  if not public.can_audit() then
    raise exception 'مركز الأمان لمدير المكتب ومدقق الأمن' using errcode = '42501';
  end if;
  if to_regclass('auth.audit_log_entries') is null then
    return;
  end if;
  return query execute $q$
    select jsonb_build_object(
             'at', e.created_at, 'action', e.payload ->> 'action',
             'actor_id', e.payload ->> 'actor_id',
             'name', case when (e.payload ->> 'actor_id') ~ '^[0-9a-f-]{36}$'
                          then public.actor_name((e.payload ->> 'actor_id')::uuid) end,
             'email', e.payload ->> 'actor_username', 'ip', to_jsonb(e) ->> 'ip_address')
      from auth.audit_log_entries e
     where e.payload ->> 'action' in ('login', 'logout', 'user_signedup', 'user_recovery_requested',
                                      'user_updated_password', 'factor_in_progress', 'factor_unenrolled',
                                      'mfa_code_login', 'token_revoked', 'user_deleted')
     order by e.created_at desc
     limit least(greatest(coalesce($1, 200), 1), 1000)$q$ using p_limit;
end;
$$;

-- ---------------------------------------------------------------------
-- 3. البيانات الكاملة لمستخدم (للمدير ومدقق الأمن). لا تُعاد كلمات المرور
--    ولا الرموز السرية ولا مفاتيح التحقق بخطوتين.
-- ---------------------------------------------------------------------
create or replace function public.user_details(p_user uuid)
returns jsonb
language plpgsql stable security definer set search_path = public, auth
as $$
declare
  p        public.profiles;
  u        jsonb;
  v_mfa    jsonb := '[]'::jsonb;
  v_sess   jsonb := '[]'::jsonb;
  v_logins jsonb := '[]'::jsonb;
begin
  if not public.can_audit() then
    raise exception 'البيانات الكاملة للمستخدمين لمدير المكتب ومدقق الأمن' using errcode = '42501';
  end if;
  select * into p from public.profiles where id = p_user;
  if not found then
    raise exception 'المستخدم غير موجود' using errcode = '22023';
  end if;
  select to_jsonb(x) into u from auth.users x where x.id = p_user;

  if to_regclass('auth.mfa_factors') is not null then
    execute $q$select coalesce(jsonb_agg(jsonb_build_object(
                 'id', f.id, 'type', to_jsonb(f) ->> 'factor_type', 'name', to_jsonb(f) ->> 'friendly_name',
                 'status', to_jsonb(f) ->> 'status', 'created_at', f.created_at, 'updated_at', f.updated_at,
                 'last_challenged_at', to_jsonb(f) -> 'last_challenged_at') order by f.created_at), '[]'::jsonb)
               from auth.mfa_factors f where f.user_id = $1$q$ into v_mfa using p_user;
  end if;
  if to_regclass('auth.sessions') is not null then
    execute $q$select coalesce(jsonb_agg(jsonb_build_object(
                 'id', s.id, 'created_at', s.created_at,
                 'updated_at', coalesce(to_jsonb(s) ->> 'refreshed_at', to_jsonb(s) ->> 'updated_at'),
                 'user_agent', to_jsonb(s) ->> 'user_agent', 'ip', to_jsonb(s) ->> 'ip', 'aal', to_jsonb(s) ->> 'aal',
                 'not_after', s.not_after) order by s.created_at desc), '[]'::jsonb)
               from auth.sessions s
              where s.user_id = $1 and coalesce(s.not_after, 'infinity') > now()$q$ into v_sess using p_user;
  end if;
  if to_regclass('auth.audit_log_entries') is not null then
    execute $q$select coalesce(jsonb_agg(x order by (x ->> 'at') desc), '[]'::jsonb) from (
                 select jsonb_build_object('at', e.created_at, 'action', e.payload ->> 'action',
                                           'ip', to_jsonb(e) ->> 'ip_address') as x
                   from auth.audit_log_entries e
                  where e.payload ->> 'actor_id' = $1::text
                  order by e.created_at desc
                  limit 40) t$q$ into v_logins using p_user;
  end if;

  return jsonb_build_object(
    'profile', to_jsonb(p) || jsonb_build_object(
        'activated_by_name', case when p.activated_by is not null then public.actor_name(p.activated_by) end,
        'department_name', (select d.name from public.departments d where d.key = p.department),
        'mfa_required', p.role::text in ('director', 'security_auditor')
                        or public.setting_bool('security.require_mfa_all', false)),
    'auth', case when u is null then null else jsonb_build_object(
        'email', u ->> 'email',
        'phone', nullif(u ->> 'phone', ''),
        'created_at', u -> 'created_at',
        'updated_at', u -> 'updated_at',
        'email_confirmed_at', u -> 'email_confirmed_at',
        'last_sign_in_at', u -> 'last_sign_in_at',
        'invited_at', u -> 'invited_at',
        'recovery_sent_at', u -> 'recovery_sent_at',
        'banned_until', u -> 'banned_until',
        'email_change', nullif(u ->> 'email_change', ''),
        'providers', coalesce(u -> 'raw_app_meta_data' -> 'providers', '[]'::jsonb),
        'signup_name', u -> 'raw_user_meta_data' ->> 'full_name',
        'is_sso_user', u -> 'is_sso_user') end,
    'mfa', v_mfa,
    'sessions', v_sess,
    'logins', v_logins,
    'activity', jsonb_build_object(
        'audit_total', (select count(*) from public.audit_log where actor = p_user),
        'audit_30d', (select count(*) from public.audit_log where actor = p_user and at > now() - interval '30 days'),
        'last_action_at', (select max(at) from public.audit_log where actor = p_user),
        'forms_updated', (select count(*) from public.project_forms where updated_by = p_user),
        'projects_created', (select count(*) from public.projects where created_by = p_user),
        'requests', (select coalesce(jsonb_object_agg(state, n), '{}'::jsonb)
                       from (select state::text as state, count(*) as n from public.change_requests
                              where requested_by = p_user group by state) r),
        'ideas', (select count(*) from public.ideas where created_by = p_user),
        'quality_notes', (select count(*) from public.quality_notes where author = p_user)),
    'recent', (select coalesce(jsonb_agg(to_jsonb(a) order by a.at desc), '[]'::jsonb)
                 from (select * from public.audit_log where actor = p_user order by at desc limit 30) a),
    'history', (select coalesce(jsonb_agg(to_jsonb(a) order by a.at desc), '[]'::jsonb)
                  from (select * from public.audit_log
                         where detail ->> 'user_id' = p_user::text order by at desc limit 30) a));
end;
$$;

-- ---------------------------------------------------------------------
-- 4. حذف مستخدم نهائياً (مدير المكتب وحده)
--    عند الحذف تُفرَّغ إشارات المشاريع إلى المستخدم المحذوف (أنشأه/عدّله)
--    دون تغيير «آخر تحديث» للمشاريع.
-- ---------------------------------------------------------------------
create or replace function public.projects_stamp()
returns trigger
language plpgsql security definer set search_path = public
as $$
begin
  if tg_op = 'UPDATE' and current_setting('app.user_cleanup', true) = 'on' then
    return new;
  end if;
  new.assign_no := nullif(btrim(coalesce(new.assign_no, '')), '');
  if tg_op = 'UPDATE' and current_setting('app.recalc', true) = 'on' then
    new.updated_at := old.updated_at;
    new.updated_by := old.updated_by;
    return new;
  end if;
  if tg_op = 'INSERT' then
    new.created_by := coalesce(auth.uid(), new.created_by);
    new.updated_by := coalesce(auth.uid(), new.updated_by);
    new.created_at := coalesce(new.created_at, now());
    if coalesce(new.sort_order, 0) = 0 then
      select coalesce(max(sort_order), 0) + 1 into new.sort_order from public.projects;
    end if;
  else
    new.created_by := old.created_by;
    new.created_at := old.created_at;
    new.updated_by := coalesce(auth.uid(), new.updated_by);
  end if;
  new.updated_at := now();
  if not exists (select 1 from public.departments where key = new.department and can_supervise) then
    raise exception 'القسم المشرف يجب أن يكون قسماً يمكن إسناد الإشراف إليه' using errcode = '23514';
  end if;
  return new;
end;
$$;
revoke execute on function public.projects_stamp() from public, anon, authenticated;

-- ---------------------------------------------------------------------
--    يُحذف الحساب وجلساته وأجهزته وإشعاراته، وتُسحب طلباته المعلّقة،
--    ويبقى اسمه في سجل التدقيق وفي سطر الحذف نفسه.
-- ---------------------------------------------------------------------
create or replace function public.delete_user(p_user uuid, p_confirm_email text)
returns void
language plpgsql security definer set search_path = public, auth
as $$
declare
  p     public.profiles;
  v_req integer := 0;
begin
  if not public.is_director() then
    raise exception 'حذف المستخدمين من صلاحية مدير المكتب وحده' using errcode = '42501';
  end if;
  if p_user = auth.uid() then
    raise exception 'لا يمكنك حذف حسابك' using errcode = '42501';
  end if;
  select * into p from public.profiles where id = p_user for update;
  if not found then
    raise exception 'المستخدم غير موجود' using errcode = '22023';
  end if;
  if p.role = 'director' then
    raise exception 'لا يُحذف حساب مدير المكتب' using errcode = '42501';
  end if;
  if lower(btrim(coalesce(p_confirm_email, ''))) is distinct from lower(btrim(coalesce(p.email, ''))) then
    raise exception 'اكتب بريد المستخدم كما هو لتأكيد الحذف' using errcode = '22023';
  end if;

  update public.change_requests set state = 'withdrawn', decided_at = now()
   where requested_by = p_user and state = 'pending';
  get diagnostics v_req = row_count;

  perform public.write_audit('user.delete', null, null,
    jsonb_build_object('user_id', p_user, 'email', p.email, 'full_name', p.full_name, 'role', p.role,
                       'department', p.department, 'active', p.active, 'created_at', p.created_at,
                       'withdrawn_requests', v_req),
    coalesce(nullif(p.full_name, ''), p.email));

  perform set_config('app.user_cleanup', 'on', true);
  perform set_config('app.trusted', 'on', true);
  delete from auth.users where id = p_user;
  delete from public.profiles where id = p_user;
  perform set_config('app.trusted', 'off', true);
  perform set_config('app.user_cleanup', 'off', true);
end;
$$;

-- ---------------------------------------------------------------------
-- 5. الصلاحيات
-- ---------------------------------------------------------------------
revoke execute on function
  public.is_auditor(), public.can_audit(), public.user_details(uuid), public.delete_user(uuid, text)
from public, anon;
grant execute on function
  public.is_auditor(), public.can_audit(), public.user_details(uuid), public.delete_user(uuid, text)
to authenticated;

notify pgrst, 'reload schema';

select 'تم: مدقق الأمن، والبيانات الكاملة للمستخدمين، وحذف المستخدم' as result;
