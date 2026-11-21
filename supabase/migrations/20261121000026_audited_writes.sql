-- =====================================================================
-- الترحيل 26: الكتابة عبر الدوال المدققة فقط
--   آخر ما كان التطبيق يكتبه في الجداول مباشرة (بسياسات حماية الصفوف) صار دوالاً بصلاحية المالك تتحقق من الصلاحية
--   ويُسجَّل أثرها في سجل التدقيق: إنشاء العقد وتعديل بياناته وملاحظاته وحذفه، وملاحظات التقييم والجودة،
--   وصلاحيات النماذج وحساسيتها، واسم المستخدم، وقراءة الإشعارات. ثم تُسحب صلاحيات الكتابة المباشرة على الجداول
--   وأعمدتها، ويفحص «الوضع الأمني» صلاحيات الأعمدة أيضاً دون استثناء أي جدول.
--   مشغّلات التدقيق والحماية القائمة على الجداول (projects_audit، projects_finance_guard، form_defs_audit،
--   quality_notes_after، profiles_guard…) تبقى كما هي وتعمل داخل الدوال.
-- يُشغَّل بعد الترحيلات 1–25، ويمكن إعادة تشغيله دون ضرر.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. العقود: الإنشاء والتعديل والحذف
-- ---------------------------------------------------------------------
-- p_id فارغ: عقد جديد. الحقول المسموحة هي نفسها التي كان التطبيق يكتبها؛ والبيانات المالية يحميها
-- projects_finance_guard (لا تُدخل عند الإنشاء، ويعدّلها من يختص بـ«أمر تعاقد»)، ورقم العقد له دالته set_contract_no.
create or replace function public.save_project(p_id uuid, p_data jsonb)
returns uuid
language plpgsql security definer set search_path = public
as $$
declare
  v_ins  text[] := array['assign_no', 'code', 'name', 'owner', 'company', 'department', 'notes', 'sort_order',
                         'eng_sup', 'eng_qty', 'eng_fol', 'eng_saf'];
  v_upd  text[] := array['assign_no', 'code', 'name', 'owner', 'company', 'department', 'notes', 'sort_order',
                         'eng_sup', 'eng_qty', 'eng_fol', 'eng_saf',
                         'contract_value', 'executed_value', 'payment_first', 'payment_second', 'payment_final', 'deductions'];
  v_keys text[];
  v_bad  text;
  v_cols text;
  v_id   uuid;
begin
  if not (coalesce(public.my_role()::text in ('director', 'office_staff'), false) and public.writes_allowed()) then
    raise exception 'إضافة العقود وتعديل بياناتها لمدير المكتب وموظفي مكتبه' using errcode = '42501';
  end if;
  if jsonb_typeof(coalesce(p_data, 'null'::jsonb)) <> 'object' then
    raise exception 'بيانات غير صالحة' using errcode = '22023';
  end if;
  v_keys := array(select jsonb_object_keys(p_data) order by 1);
  select k into v_bad from unnest(v_keys) k
   where not (k = any (case when p_id is null then v_ins else v_upd end)) limit 1;
  if v_bad is not null then
    raise exception 'الحقل «%» لا يُكتب من هنا', v_bad using errcode = '22023';
  end if;
  v_cols := (select string_agg(quote_ident(k), ', ' order by k) from unnest(v_keys) k);

  if p_id is null then
    if v_cols is null then
      raise exception 'بيانات العقد فارغة' using errcode = '22023';
    end if;
    execute format('insert into public.projects (%1$s) select %1$s from jsonb_populate_record(null::public.projects, $1) returning id', v_cols)
      into v_id using p_data;
    return v_id;
  end if;

  perform 1 from public.projects where id = p_id and merged_into is null for update;
  if not found then
    raise exception 'العقد غير موجود' using errcode = 'P0002';
  end if;
  if v_cols is not null then
    execute format('update public.projects p set (%1$s) = (select %1$s from jsonb_populate_record(p, $1)) where p.id = $2', v_cols)
      using p_data, p_id;
  end if;
  return p_id;
end;
$$;

-- الحذف لمدير المكتب وحده، ويسجّله projects_audit (project.delete)
create or replace function public.delete_project(p_id uuid)
returns void
language plpgsql security definer set search_path = public
as $$
begin
  if not public.is_director() then
    raise exception 'حذف العقود لمدير المكتب وحده' using errcode = '42501';
  end if;
  delete from public.projects where id = p_id and merged_into is null;
  if not found then
    raise exception 'العقد غير موجود' using errcode = 'P0002';
  end if;
end;
$$;

-- ---------------------------------------------------------------------
-- 2. ملاحظات التقييم والجودة (يسجّلها quality_notes_after: note.add)
-- ---------------------------------------------------------------------
create or replace function public.add_quality_note(p_project uuid, p_body text)
returns uuid
language plpgsql security definer set search_path = public
as $$
declare
  v_body text := btrim(coalesce(p_body, ''));
  v_id   uuid;
begin
  if not (coalesce(public.my_role()::text in ('director', 'planning_qa'), false) and public.writes_allowed()) then
    raise exception 'ملاحظات التقييم والجودة لمدير المكتب ومكتب التخطيط وضمان الجودة' using errcode = '42501';
  end if;
  if length(v_body) < 1 or length(v_body) > 4000 then
    raise exception 'اكتب الملاحظة (حتى 4000 حرف)' using errcode = '22023';
  end if;
  if not exists (select 1 from public.projects where id = p_project and merged_into is null) then
    raise exception 'العقد غير موجود' using errcode = 'P0002';
  end if;
  insert into public.quality_notes (project_id, body) values (p_project, v_body) returning id into v_id;
  return v_id;
end;
$$;

-- ---------------------------------------------------------------------
-- 3. صلاحيات النماذج وحساسيتها (يسجّلها form_defs_audit: form_def.update)
-- ---------------------------------------------------------------------
create or replace function public.set_form_rights(p_key text, p_sensitive boolean default null, p_responsible text[] default null)
returns void
language plpgsql security definer set search_path = public
as $$
begin
  if not public.is_director() then
    raise exception 'صلاحيات النماذج من صلاحية مدير المكتب وحده' using errcode = '42501';
  end if;
  if p_responsible is not null and (coalesce(array_length(p_responsible, 1), 0) > 30
     or exists (select 1 from unnest(p_responsible) x where x is null or x !~ '^[a-z_:]{2,40}$')) then
    raise exception 'قائمة المختصين بالنموذج غير صالحة' using errcode = '22023';
  end if;
  update public.form_defs
     set sensitive = coalesce(p_sensitive, sensitive),
         responsible = coalesce(p_responsible, responsible)
   where key = p_key;
  if not found then
    raise exception 'النموذج غير موجود' using errcode = 'P0002';
  end if;
end;
$$;

-- ---------------------------------------------------------------------
-- 4. اسم المستخدم (user.rename)، وقراءة الإشعارات
-- ---------------------------------------------------------------------
create or replace function public.set_my_name(p_name text)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  v_name text := btrim(regexp_replace(coalesce(p_name, ''), '\s+', ' ', 'g'));
  v_old  text;
begin
  if auth.uid() is null then
    raise exception 'سجّل الدخول أولاً' using errcode = '42501';
  end if;
  if length(v_name) < 2 or length(v_name) > 80 then
    raise exception 'الاسم من حرفين إلى 80 حرفاً' using errcode = '22023';
  end if;
  select full_name into v_old from public.profiles where id = auth.uid() for update;
  if not found then
    raise exception 'الحساب غير موجود' using errcode = 'P0002';
  end if;
  if v_old is not distinct from v_name then
    return;
  end if;
  update public.profiles set full_name = v_name where id = auth.uid();
  perform public.write_audit('user.rename', null, null,
    jsonb_build_object('user_id', auth.uid(), 'from', v_old, 'to', v_name), v_name);
end;
$$;

-- حالة قراءة شخصية لا تُسجَّل في سجل التدقيق (مثل «مقروء» في المراسلات)
create or replace function public.mark_notifications_read()
returns integer
language plpgsql security definer set search_path = public
as $$
declare
  v_n integer;
begin
  if auth.uid() is null then
    raise exception 'سجّل الدخول أولاً' using errcode = '42501';
  end if;
  update public.notifications set read_at = now() where user_id = auth.uid() and read_at is null;
  get diagnostics v_n = row_count;
  return v_n;
end;
$$;

-- ---------------------------------------------------------------------
-- 5. سحب الكتابة المباشرة: لا صلاحيات كتابة للمستخدمين على الجداول ولا على أعمدتها
-- ---------------------------------------------------------------------
drop policy if exists projects_insert on public.projects;
drop policy if exists projects_update on public.projects;
drop policy if exists projects_delete on public.projects;
drop policy if exists quality_notes_insert on public.quality_notes;
drop policy if exists quality_notes_delete on public.quality_notes;
drop policy if exists form_defs_update on public.form_defs;
drop policy if exists notifications_update on public.notifications;
drop policy if exists profiles_update_own on public.profiles;

-- سحب الصلاحية على الجدول يسحب صلاحيات أعمدته معها
revoke insert, update, delete, truncate on public.projects, public.quality_notes, public.form_defs,
  public.notifications, public.profiles, public.v_project_progress from authenticated, anon;

-- ---------------------------------------------------------------------
-- 6. فحص «الكتابة عبر الدوال المدققة فقط» يشمل صلاحيات الأعمدة، دون استثناء
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

  -- صلاحيات الجدول كله وصلاحيات أعمدة بعينها معاً، دون استثناء أي جدول
  select count(*), coalesce(jsonb_agg(t order by t), '[]'::jsonb) into v_n, v_list from (
    select table_name::text t from information_schema.role_table_grants
     where grantee in ('authenticated', 'anon') and table_schema = 'public' and privilege_type in ('INSERT', 'UPDATE', 'DELETE', 'TRUNCATE')
    union
    select table_name::text from information_schema.role_column_grants
     where grantee in ('authenticated', 'anon') and table_schema = 'public' and privilege_type in ('INSERT', 'UPDATE')) s;
  return next jsonb_build_object('key', 'direct_write', 'group', 'قاعدة البيانات', 'title', 'الكتابة عبر الدوال المدققة فقط',
    'ok', v_n = 0, 'severity', 'medium', 'count', v_n, 'items', v_list,
    'detail', 'جداول أو أعمدة يكتب فيها المستخدمون مباشرة دون المرور بدالة تتحقق من الصلاحية وتسجّل في سجل التدقيق.');

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
-- 7. الصلاحيات على الدوال
-- ---------------------------------------------------------------------
revoke execute on function
  public.save_project(uuid, jsonb), public.delete_project(uuid), public.add_quality_note(uuid, text),
  public.set_form_rights(text, boolean, text[]), public.set_my_name(text), public.mark_notifications_read(),
  public.sec_posture()
from public, anon;
grant execute on function
  public.save_project(uuid, jsonb), public.delete_project(uuid), public.add_quality_note(uuid, text),
  public.set_form_rights(text, boolean, text[]), public.set_my_name(text), public.mark_notifications_read(),
  public.sec_posture()
to authenticated;

notify pgrst, 'reload schema';
