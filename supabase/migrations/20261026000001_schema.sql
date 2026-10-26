-- =====================================================================
--  منظومة متابعة نماذج الدورة المستندية للمشاريع
--  مكتب الشؤون الهندسية — لجنة إعادة إعمار منطقة الصابري ووسط البلاد
--
--  المخطط الكامل لقاعدة بيانات Supabase:
--  الأدوار، الصلاحيات (RLS)، مسار اعتماد النماذج الحساسة، سجل التدقيق.
--  كل قواعد «المسؤول الأول والأخير» مفروضة هنا داخل قاعدة البيانات،
--  فلا يمكن تجاوزها من أي نسخة من التطبيق.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. الأنواع
-- ---------------------------------------------------------------------
create type public.app_role as enum ('director', 'office_staff', 'dept_head', 'contracts', 'planning_qa');
create type public.form_status as enum ('done', 'wip', 'todo', 'na');
create type public.request_state as enum ('pending', 'approved', 'rejected', 'withdrawn');

-- ---------------------------------------------------------------------
-- 2. الجداول
-- ---------------------------------------------------------------------

-- الأقسام الأربعة لمكتب الشؤون الهندسية
create table public.departments (
  key           text primary key,
  name          text not null unique,
  can_supervise boolean not null default false,   -- يمكن إسناد الإشراف على مشروع إليه
  sort          smallint not null default 0
);

-- ملف كل مستخدم. role = null و active = false حتى يفعّله المدير.
create table public.profiles (
  id           uuid primary key references auth.users (id) on delete cascade,
  full_name    text not null default '',
  email        text,
  role         public.app_role,
  department   text references public.departments (key),
  active       boolean not null default false,
  created_at   timestamptz not null default now(),
  activated_at timestamptz,
  activated_by uuid references public.profiles (id) on delete set null,
  constraint dept_head_needs_department check (role is distinct from 'dept_head' or department is not null),
  constraint active_needs_role check (not active or role is not null)
);
-- مدير واحد فقط في المنظومة كلها
create unique index profiles_one_director on public.profiles ((true)) where role = 'director';

-- تعريف النماذج الثمانية عشر وتوزيع الاختصاص عليها
--   responsible: من يحدّث النموذج غير المدير. القيم المسموحة:
--     office_staff      موظفو مكتب المدير
--     contracts         مكتب العقود والتوريدات والمستخلصات
--     planning_qa       مكتب التخطيط والتقييم وضمان الجودة
--     head:supervising  رئيس القسم المشرف على المشروع (الإشراف والتنسيق أو الترميم)
--     head:technical    رئيس قسم الشؤون الفنية
--     head:acceptance   رئيس قسم المطابقة والاستلام
--   sensitive: تغييره من غير المدير يرفع طلب اعتماد.
create table public.form_defs (
  key            text primary key,
  name           text not null unique,
  stage          smallint not null check (stage between 0 and 4),
  sort           smallint not null unique,
  sensitive      boolean not null default false,
  responsible    text[] not null default '{}',
  engineer_field text check (engineer_field in ('eng_sup', 'eng_qty', 'eng_fol', 'eng_saf')),
  constraint responsible_tokens check (
    responsible <@ array['office_staff', 'contracts', 'planning_qa',
                         'head:supervising', 'head:technical', 'head:acceptance']::text[])
);

create table public.projects (
  id          uuid primary key default gen_random_uuid(),
  assign_no   text unique,
  code        text not null default '',
  name        text not null default '',
  owner       text not null default '',
  company     text not null default '',
  department  text not null default 'supervision' references public.departments (key),
  notes       text not null default '',
  eng_sup     text not null default '',
  eng_qty     text not null default '',
  eng_fol     text not null default '',
  eng_saf     text not null default '',
  sort_order  integer not null default 0,
  created_at  timestamptz not null default now(),
  created_by  uuid references public.profiles (id) on delete set null,
  updated_at  timestamptz not null default now(),
  updated_by  uuid references public.profiles (id) on delete set null,
  constraint projects_has_identity check (coalesce(assign_no, '') <> '' or name <> '')
);
create index projects_sort_idx on public.projects (sort_order);

-- حالة كل نموذج في كل مشروع. غياب الصف يعني «لم يتم».
create table public.project_forms (
  project_id  uuid not null references public.projects (id) on delete cascade,
  form_key    text not null references public.form_defs (key),
  status      public.form_status not null default 'todo',
  updated_at  timestamptz not null default now(),
  updated_by  uuid references public.profiles (id) on delete set null,
  approved_by uuid references public.profiles (id) on delete set null,
  primary key (project_id, form_key)
);

-- طلبات اعتماد النماذج الحساسة
create table public.change_requests (
  id            uuid primary key default gen_random_uuid(),
  project_id    uuid not null references public.projects (id) on delete cascade,
  form_key      text not null references public.form_defs (key),
  from_status   public.form_status not null,
  to_status     public.form_status not null,
  note          text not null default '',
  requested_by  uuid references public.profiles (id) on delete set null,
  requested_at  timestamptz not null default now(),
  state         public.request_state not null default 'pending',
  decided_by    uuid references public.profiles (id) on delete set null,
  decided_at    timestamptz,
  decision_note text not null default ''
);
-- طلب معلّق واحد فقط لكل نموذج في كل مشروع
create unique index change_requests_one_pending on public.change_requests (project_id, form_key) where state = 'pending';
create index change_requests_state_idx on public.change_requests (state, requested_at desc);

-- ملاحظات التقييم والجودة
create table public.quality_notes (
  id         uuid primary key default gen_random_uuid(),
  project_id uuid not null references public.projects (id) on delete cascade,
  author     uuid references public.profiles (id) on delete set null,
  body       text not null check (length(btrim(body)) > 0),
  created_at timestamptz not null default now()
);
create index quality_notes_project_idx on public.quality_notes (project_id, created_at desc);

-- الإشعارات داخل التطبيق
create table public.notifications (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null references public.profiles (id) on delete cascade,
  created_at timestamptz not null default now(),
  kind       text not null,
  title      text not null,
  body       text not null default '',
  project_id uuid,
  request_id uuid,
  read_at    timestamptz
);
create index notifications_user_idx on public.notifications (user_id, created_at desc);

-- سجل التدقيق: لا يُعدّل ولا يُحذف. لا يرتبط بمفاتيح خارجية حتى يبقى بعد حذف المشروع أو المستخدم.
create table public.audit_log (
  id            bigint generated always as identity primary key,
  at            timestamptz not null default now(),
  actor         uuid,
  actor_name    text not null default '',
  project_id    uuid,
  project_label text not null default '',
  action        text not null,
  form_key      text,
  detail        jsonb not null default '{}'::jsonb
);
create index audit_log_project_idx on public.audit_log (project_id, at desc);
create index audit_log_at_idx on public.audit_log (at desc);

-- ---------------------------------------------------------------------
-- 3. دوال مساعدة للصلاحيات
-- ---------------------------------------------------------------------
create or replace function public.my_role()
returns public.app_role
language sql stable security definer set search_path = public
as $$
  select role from public.profiles where id = auth.uid() and active
$$;

create or replace function public.is_member()
returns boolean
language sql stable security definer set search_path = public
as $$
  select exists (select 1 from public.profiles where id = auth.uid() and active and role is not null)
$$;

create or replace function public.is_director()
returns boolean
language sql stable security definer set search_path = public
as $$
  select exists (select 1 from public.profiles where id = auth.uid() and active and role = 'director')
$$;

create or replace function public.actor_name(p_id uuid)
returns text
language sql stable security definer set search_path = public
as $$
  select coalesce((select nullif(full_name, '') from public.profiles where id = p_id),
                  (select email from public.profiles where id = p_id),
                  'النظام')
$$;

create or replace function public.project_label(p_id uuid)
returns text
language sql stable security definer set search_path = public
as $$
  select btrim(coalesce(assign_no, '') || ' ' || name) from public.projects where id = p_id
$$;

-- هل يملك المستخدم الحالي تحديث هذا النموذج في هذا المشروع؟
create or replace function public.can_edit_form(p_project uuid, p_form text)
returns boolean
language plpgsql stable security definer set search_path = public
as $$
declare
  me        public.profiles;
  d         public.form_defs;
  proj_dept text;
begin
  select * into me from public.profiles where id = auth.uid() and active and role is not null;
  if not found then return false; end if;
  if me.role = 'director' then return true; end if;

  select * into d from public.form_defs where key = p_form;
  if not found then return false; end if;
  select department into proj_dept from public.projects where id = p_project;
  if not found then return false; end if;

  return case me.role
    when 'office_staff' then 'office_staff' = any (d.responsible)
    when 'contracts'    then 'contracts'    = any (d.responsible)
    when 'planning_qa'  then 'planning_qa'  = any (d.responsible)
    when 'dept_head'    then
         ('head:supervising' = any (d.responsible) and me.department = proj_dept)
      or ('head:technical'   = any (d.responsible) and me.department = 'technical')
      or ('head:acceptance'  = any (d.responsible) and me.department = 'acceptance')
    else false
  end;
end;
$$;

-- قائمة النماذج التي يملك المستخدم تحديثها في مشروع، مع معرفة إن كانت تحتاج اعتماداً
create or replace function public.my_form_rights(p_project uuid)
returns table (form_key text, can_edit boolean, needs_approval boolean)
language sql stable security definer set search_path = public
as $$
  select d.key,
         public.can_edit_form(p_project, d.key),
         d.sensitive and not public.is_director()
  from public.form_defs d
  order by d.sort
$$;

-- كتابة سطر في سجل التدقيق (داخلي)
create or replace function public.write_audit(
  p_action text, p_project uuid default null, p_form text default null,
  p_detail jsonb default '{}'::jsonb, p_label text default null, p_actor uuid default null)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  v_actor uuid := coalesce(p_actor, auth.uid());
begin
  insert into public.audit_log (actor, actor_name, project_id, project_label, action, form_key, detail)
  values (v_actor, public.actor_name(v_actor), p_project,
          coalesce(p_label, public.project_label(p_project), ''), p_action, p_form, coalesce(p_detail, '{}'::jsonb));
end;
$$;

-- إرسال إشعار (داخلي)
create or replace function public.notify_user(
  p_user uuid, p_kind text, p_title text, p_body text default '',
  p_project uuid default null, p_request uuid default null)
returns void
language sql security definer set search_path = public
as $$
  insert into public.notifications (user_id, kind, title, body, project_id, request_id)
  select p_user, p_kind, p_title, coalesce(p_body, ''), p_project, p_request
  where p_user is not null
$$;

create or replace function public.notify_director(
  p_kind text, p_title text, p_body text default '', p_project uuid default null, p_request uuid default null)
returns void
language sql security definer set search_path = public
as $$
  insert into public.notifications (user_id, kind, title, body, project_id, request_id)
  select id, p_kind, p_title, coalesce(p_body, ''), p_project, p_request
  from public.profiles where role = 'director' and active
$$;

create or replace function public.status_label(s public.form_status)
returns text
language sql immutable
as $$
  select case s when 'done' then 'مكتمل' when 'wip' then 'قيد الإجراء' when 'na' then 'لا ينطبق' else 'لم يتم' end
$$;

-- ---------------------------------------------------------------------
-- 4. المحفّزات (Triggers)
-- ---------------------------------------------------------------------

-- إنشاء ملف المستخدم عند التسجيل، وإشعار المدير بطلب الانضمام
create or replace function public.handle_new_user()
returns trigger
language plpgsql security definer set search_path = public
as $$
begin
  insert into public.profiles (id, email, full_name)
  values (new.id, new.email, coalesce(nullif(btrim(new.raw_user_meta_data ->> 'full_name'), ''), ''))
  on conflict (id) do nothing;
  perform public.notify_director('signup', 'طلب انضمام جديد',
    coalesce(nullif(btrim(new.raw_user_meta_data ->> 'full_name'), ''), new.email) || ' بانتظار التفعيل');
  return new;
end;
$$;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ملفات للحسابات المسجلة قبل تشغيل هذا الملف (إن وُجدت)
insert into public.profiles (id, email, full_name)
select u.id, u.email, coalesce(nullif(btrim(u.raw_user_meta_data ->> 'full_name'), ''), '')
from auth.users u
on conflict (id) do nothing;

-- منع المستخدم من تغيير أي شيء في ملفه غير الاسم (احتياط إضافي فوق صلاحيات الأعمدة)
create or replace function public.profiles_guard()
returns trigger
language plpgsql security definer set search_path = public
as $$
begin
  if current_setting('app.trusted', true) = 'on' or auth.uid() is null then
    return new;
  end if;
  if new.role is distinct from old.role or new.active is distinct from old.active
     or new.department is distinct from old.department or new.email is distinct from old.email
     or new.id is distinct from old.id then
    raise exception 'لا يملك تغيير الدور أو الحالة إلا مدير المكتب' using errcode = '42501';
  end if;
  return new;
end;
$$;
create trigger profiles_guard
  before update on public.profiles
  for each row execute function public.profiles_guard();

-- ختم المشروع (من أنشأه ومن عدّله ومتى) وتنظيف رقم التكليف
create or replace function public.projects_stamp()
returns trigger
language plpgsql security definer set search_path = public
as $$
begin
  new.assign_no := nullif(btrim(coalesce(new.assign_no, '')), '');
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
    raise exception 'القسم المشرف يجب أن يكون الإشراف والتنسيق أو الترميم' using errcode = '23514';
  end if;
  return new;
end;
$$;
create trigger projects_stamp
  before insert or update on public.projects
  for each row execute function public.projects_stamp();

-- تدقيق تغييرات المشاريع
create or replace function public.projects_audit()
returns trigger
language plpgsql security definer set search_path = public
as $$
declare
  changes jsonb := '{}'::jsonb;
  col     text;
  o       jsonb;
  n       jsonb;
begin
  if current_setting('app.seeding', true) = 'on' then
    return null;
  end if;
  if tg_op = 'INSERT' then
    perform public.write_audit('project.create', new.id, null,
      jsonb_build_object('assign_no', new.assign_no, 'name', new.name, 'owner', new.owner, 'company', new.company));
  elsif tg_op = 'DELETE' then
    perform public.write_audit('project.delete', old.id, null,
      jsonb_build_object('assign_no', old.assign_no, 'name', old.name),
      btrim(coalesce(old.assign_no, '') || ' ' || old.name));
  else
    o := to_jsonb(old); n := to_jsonb(new);
    foreach col in array array['assign_no', 'code', 'name', 'owner', 'company', 'department', 'notes',
                               'eng_sup', 'eng_qty', 'eng_fol', 'eng_saf'] loop
      if o -> col is distinct from n -> col then
        changes := changes || jsonb_build_object(col, jsonb_build_object('from', o -> col, 'to', n -> col));
      end if;
    end loop;
    if changes <> '{}'::jsonb then
      perform public.write_audit('project.update', new.id, null, changes);
    end if;
  end if;
  return null;
end;
$$;
create trigger projects_audit
  after insert or update or delete on public.projects
  for each row execute function public.projects_audit();

-- تدقيق تغيير صلاحيات النماذج
create or replace function public.form_defs_audit()
returns trigger
language plpgsql security definer set search_path = public
as $$
begin
  if new.sensitive is distinct from old.sensitive or new.responsible is distinct from old.responsible then
    perform public.write_audit('form_def.update', null, new.key,
      jsonb_build_object('sensitive', jsonb_build_object('from', old.sensitive, 'to', new.sensitive),
                         'responsible', jsonb_build_object('from', to_jsonb(old.responsible), 'to', to_jsonb(new.responsible))),
      new.name);
  end if;
  return null;
end;
$$;
create trigger form_defs_audit
  after update on public.form_defs
  for each row execute function public.form_defs_audit();

-- لا يغيّر المدير من تعريف النموذج إلا الحساسية والاختصاص
create or replace function public.form_defs_guard()
returns trigger
language plpgsql
as $$
begin
  if new.key is distinct from old.key or new.name is distinct from old.name or new.stage is distinct from old.stage
     or new.sort is distinct from old.sort or new.engineer_field is distinct from old.engineer_field then
    raise exception 'يُعدَّل من النموذج اختصاصه وحساسيته فقط' using errcode = '42501';
  end if;
  return new;
end;
$$;
create trigger form_defs_guard
  before update on public.form_defs
  for each row execute function public.form_defs_guard();

-- تدقيق ملاحظات الجودة
create or replace function public.quality_notes_audit()
returns trigger
language plpgsql security definer set search_path = public
as $$
begin
  new.author := auth.uid();
  new.created_at := now();
  return new;
end;
$$;
create trigger quality_notes_stamp
  before insert on public.quality_notes
  for each row execute function public.quality_notes_audit();

create or replace function public.quality_notes_after()
returns trigger
language plpgsql security definer set search_path = public
as $$
begin
  perform public.write_audit('note.add', new.project_id, null, jsonb_build_object('body', new.body));
  return null;
end;
$$;
create trigger quality_notes_after
  after insert on public.quality_notes
  for each row execute function public.quality_notes_after();

-- ---------------------------------------------------------------------
-- 5. العمليات (RPC) — الطريق الوحيد لتغيير حالات النماذج والطلبات والمستخدمين
-- ---------------------------------------------------------------------

-- تطبيق حالة نموذج (داخلي، غير متاح للتطبيق مباشرة)
create or replace function public.apply_form_status(
  p_project uuid, p_form text, p_status public.form_status, p_actor uuid, p_approved_by uuid, p_request uuid default null)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  v_from public.form_status;
begin
  select status into v_from from public.project_forms where project_id = p_project and form_key = p_form;
  v_from := coalesce(v_from, 'todo');

  insert into public.project_forms (project_id, form_key, status, updated_at, updated_by, approved_by)
  values (p_project, p_form, p_status, now(), p_actor, p_approved_by)
  on conflict (project_id, form_key) do update
    set status = excluded.status, updated_at = excluded.updated_at,
        updated_by = excluded.updated_by, approved_by = excluded.approved_by;

  update public.projects set updated_at = now(), updated_by = p_actor where id = p_project;

  perform public.write_audit('form.set', p_project, p_form,
    jsonb_strip_nulls(jsonb_build_object('from', v_from, 'to', p_status,
      'approved_by', p_approved_by, 'approved_by_name', case when p_approved_by is not null then public.actor_name(p_approved_by) end,
      'request_id', p_request)),
    null, p_actor);
end;
$$;

-- UC-07 / UC-08: تحديث حالة نموذج. يُرجع applied أو pending أو unchanged.
create or replace function public.set_form_status(
  p_project uuid, p_form text, p_status public.form_status, p_note text default '')
returns text
language plpgsql security definer set search_path = public
as $$
declare
  me     public.profiles;
  d      public.form_defs;
  v_cur  public.form_status;
  v_req  uuid;
  v_pend uuid;
begin
  select * into me from public.profiles where id = auth.uid() and active and role is not null;
  if not found then
    raise exception 'حسابك غير مفعّل' using errcode = '42501';
  end if;
  select * into d from public.form_defs where key = p_form;
  if not found then
    raise exception 'نموذج غير معروف: %', p_form using errcode = '22023';
  end if;
  if not exists (select 1 from public.projects where id = p_project) then
    raise exception 'المشروع غير موجود' using errcode = '22023';
  end if;
  if not public.can_edit_form(p_project, p_form) then
    raise exception 'نموذج «%» خارج اختصاصك', d.name using errcode = '42501';
  end if;

  select status into v_cur from public.project_forms where project_id = p_project and form_key = p_form for update;
  v_cur := coalesce(v_cur, 'todo');

  -- نموذج حساس من غير المدير: طلب اعتماد
  if d.sensitive and me.role <> 'director' then
    if v_cur = p_status then
      return 'unchanged';
    end if;
    if exists (select 1 from public.change_requests
               where project_id = p_project and form_key = p_form and state = 'pending') then
      raise exception 'يوجد طلب معلّق لهذا النموذج بانتظار قرار المدير' using errcode = 'P0001';
    end if;
    insert into public.change_requests (project_id, form_key, from_status, to_status, note, requested_by)
    values (p_project, p_form, v_cur, p_status, coalesce(p_note, ''), me.id)
    returning id into v_req;
    perform public.write_audit('request.create', p_project, p_form,
      jsonb_build_object('request_id', v_req, 'from', v_cur, 'to', p_status, 'note', coalesce(p_note, '')));
    perform public.notify_director('request', 'طلب اعتماد: ' || d.name,
      public.actor_name(me.id) || ' يطلب تغيير «' || d.name || '» إلى «' || public.status_label(p_status)
        || '» في المشروع ' || coalesce(public.project_label(p_project), ''),
      p_project, v_req);
    return 'pending';
  end if;

  -- تعديل مباشر
  if v_cur = p_status then
    return 'unchanged';
  end if;
  perform public.apply_form_status(p_project, p_form, p_status, me.id, null);

  -- إذا عدّل المدير نموذجاً عليه طلب معلّق، يُغلق الطلب
  if me.role = 'director' then
    update public.change_requests
       set state = 'rejected', decided_by = me.id, decided_at = now(),
           decision_note = 'عدّل المدير حالة النموذج مباشرة'
     where project_id = p_project and form_key = p_form and state = 'pending'
     returning id into v_pend;
    if v_pend is not null then
      perform public.notify_user((select requested_by from public.change_requests where id = v_pend),
        'decision', 'أُغلق طلبك: ' || d.name, 'عدّل المدير حالة النموذج مباشرة', p_project, v_pend);
    end if;
  end if;
  return 'applied';
end;
$$;

-- UC-15: البتّ في طلب اعتماد (المدير فقط)
create or replace function public.decide_request(p_request uuid, p_approve boolean, p_note text default '')
returns void
language plpgsql security definer set search_path = public
as $$
declare
  r public.change_requests;
  d public.form_defs;
begin
  if not public.is_director() then
    raise exception 'البتّ في الطلبات من صلاحية مدير المكتب وحده' using errcode = '42501';
  end if;
  select * into r from public.change_requests where id = p_request for update;
  if not found then
    raise exception 'الطلب غير موجود' using errcode = '22023';
  end if;
  if r.state <> 'pending' then
    raise exception 'تم البتّ في هذا الطلب مسبقاً' using errcode = 'P0001';
  end if;
  if not p_approve and length(btrim(coalesce(p_note, ''))) = 0 then
    raise exception 'اكتب سبب الرفض' using errcode = '22023';
  end if;
  select * into d from public.form_defs where key = r.form_key;

  update public.change_requests
     set state = case when p_approve then 'approved'::public.request_state else 'rejected'::public.request_state end,
         decided_by = auth.uid(), decided_at = now(), decision_note = coalesce(p_note, '')
   where id = p_request;

  if p_approve then
    perform public.apply_form_status(r.project_id, r.form_key, r.to_status, r.requested_by, auth.uid(), r.id);
  end if;

  perform public.write_audit(case when p_approve then 'request.approve' else 'request.reject' end,
    r.project_id, r.form_key,
    jsonb_build_object('request_id', r.id, 'from', r.from_status, 'to', r.to_status,
                       'requested_by', r.requested_by, 'requested_by_name', public.actor_name(r.requested_by),
                       'note', coalesce(p_note, '')));

  perform public.notify_user(r.requested_by, 'decision',
    case when p_approve then 'اعتُمد طلبك: ' else 'رُفض طلبك: ' end || d.name,
    case when p_approve then 'أصبحت حالة «' || d.name || '» «' || public.status_label(r.to_status) || '»'
         else 'السبب: ' || p_note end,
    r.project_id, r.id);
end;
$$;

-- UC-09: سحب طلب معلّق (مقدّم الطلب فقط)
create or replace function public.withdraw_request(p_request uuid)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  r public.change_requests;
begin
  select * into r from public.change_requests where id = p_request for update;
  if not found or r.requested_by is distinct from auth.uid() then
    raise exception 'لا يمكنك سحب هذا الطلب' using errcode = '42501';
  end if;
  if r.state <> 'pending' then
    raise exception 'لا يُسحب إلا الطلب المعلّق' using errcode = 'P0001';
  end if;
  update public.change_requests set state = 'withdrawn', decided_at = now() where id = p_request;
  perform public.write_audit('request.withdraw', r.project_id, r.form_key, jsonb_build_object('request_id', r.id));
end;
$$;

-- UC-10: إسناد مهندس (لمن يختص بنموذج التكليف المقابل)
create or replace function public.set_engineer(p_project uuid, p_form text, p_name text)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  f text;
begin
  select engineer_field into f from public.form_defs where key = p_form;
  if f is null then
    raise exception 'هذا النموذج ليس تكليف مهندس' using errcode = '22023';
  end if;
  if not public.can_edit_form(p_project, p_form) then
    raise exception 'إسناد هذا المهندس خارج اختصاصك' using errcode = '42501';
  end if;
  execute format('update public.projects set %I = $1 where id = $2', f) using btrim(coalesce(p_name, '')), p_project;
end;
$$;

-- UC-16: إدارة المستخدمين (المدير فقط). لا يمكن منح دور المدير ولا تعديل حساب المدير.
create or replace function public.set_user_access(
  p_user uuid, p_role public.app_role, p_department text, p_active boolean, p_full_name text default null)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  old_p public.profiles;
begin
  if not public.is_director() then
    raise exception 'إدارة المستخدمين من صلاحية مدير المكتب وحده' using errcode = '42501';
  end if;
  if p_user = auth.uid() then
    raise exception 'لا يمكن تعديل صلاحيات حساب المدير من التطبيق' using errcode = '42501';
  end if;
  if p_role = 'director' then
    raise exception 'دور مدير المكتب لا يُمنح من التطبيق' using errcode = '42501';
  end if;
  select * into old_p from public.profiles where id = p_user for update;
  if not found then
    raise exception 'المستخدم غير موجود' using errcode = '22023';
  end if;
  if old_p.role = 'director' then
    raise exception 'لا يمكن تعديل حساب المدير' using errcode = '42501';
  end if;
  if p_active and p_role is null then
    raise exception 'اختر الدور قبل التفعيل' using errcode = '22023';
  end if;
  if p_role = 'dept_head' and p_department is null then
    raise exception 'اختر القسم لرئيس القسم' using errcode = '22023';
  end if;

  perform set_config('app.trusted', 'on', true);
  update public.profiles
     set role = p_role,
         department = case when p_role = 'dept_head' then p_department else null end,
         active = coalesce(p_active, false),
         full_name = coalesce(nullif(btrim(p_full_name), ''), full_name),
         activated_at = case when coalesce(p_active, false) and not old_p.active then now() else activated_at end,
         activated_by = case when coalesce(p_active, false) and not old_p.active then auth.uid() else activated_by end
   where id = p_user;
  perform set_config('app.trusted', 'off', true);

  perform public.write_audit(
    case when coalesce(p_active, false) and not old_p.active then 'user.activate'
         when not coalesce(p_active, false) and old_p.active then 'user.deactivate'
         else 'user.update' end,
    null, null,
    jsonb_build_object('user_id', p_user, 'email', old_p.email,
      'role', jsonb_build_object('from', old_p.role, 'to', p_role),
      'department', jsonb_build_object('from', old_p.department, 'to', case when p_role = 'dept_head' then p_department end),
      'active', jsonb_build_object('from', old_p.active, 'to', coalesce(p_active, false))),
    coalesce(nullif(old_p.full_name, ''), old_p.email));

  if coalesce(p_active, false) and not old_p.active then
    perform public.notify_user(p_user, 'activated', 'تم تفعيل حسابك', 'يمكنك الآن استخدام المنظومة');
  end if;
end;
$$;

-- الإعداد لأول مرة: منح دور المدير لحسابك. يُشغَّل من محرر SQL في Supabase فقط، ومرة واحدة.
create or replace function public.claim_director(p_email text)
returns text
language plpgsql security definer set search_path = public
as $$
declare
  v_id uuid;
begin
  if exists (select 1 from public.profiles where role = 'director') then
    raise exception 'يوجد مدير للمنظومة بالفعل' using errcode = '42501';
  end if;
  select id into v_id from public.profiles where lower(email) = lower(btrim(p_email));
  if v_id is null then
    raise exception 'لا يوجد حساب بالبريد %؛ أنشئ الحساب من التطبيق أولاً', p_email using errcode = '22023';
  end if;
  perform set_config('app.trusted', 'on', true);
  update public.profiles set role = 'director', department = null, active = true, activated_at = now()
   where id = v_id;
  perform set_config('app.trusted', 'off', true);
  perform public.write_audit('user.claim_director', null, null, jsonb_build_object('user_id', v_id, 'email', p_email),
                             p_email, v_id);
  return 'تم: ' || p_email || ' هو مدير المنظومة';
end;
$$;

-- ---------------------------------------------------------------------
-- 6. عرض نسب الإنجاز (للتقارير والاستعلام المباشر)
-- ---------------------------------------------------------------------
create or replace view public.v_project_progress
with (security_invoker = true)
as
with cells as (
  select p.id as project_id, d.key, d.sort, d.stage, coalesce(pf.status, 'todo') as status
  from public.projects p
  cross join public.form_defs d
  left join public.project_forms pf on pf.project_id = p.id and pf.form_key = d.key
),
agg as (
  select project_id,
         count(*) filter (where status = 'done') as done,
         count(*) filter (where status = 'wip')  as wip,
         count(*) filter (where status = 'na')   as na,
         count(*) filter (where status <> 'na')  as required,
         (array_agg(key order by sort) filter (where status not in ('done', 'na')))[1] as next_form
  from cells group by project_id
)
select a.project_id, a.done, a.wip, a.na, a.required,
       case when a.required = 0 then 1.0 else round(a.done::numeric / a.required, 4) end as pct,
       a.next_form,
       nf.name as next_form_name,
       case when a.next_form is null then 'اكتملت الدورة'
            else (array['التعاقد', 'تكليف المهندسين', 'بدء التنفيذ', 'المستخلصات', 'الاستلام والإقفال'])[nf.stage + 1] end as current_stage,
       case when a.next_form is null then 'مكتملة'
            when a.done + a.wip = 0 then 'لم تبدأ'
            else 'جارية' end as cycle_state
from agg a
left join public.form_defs nf on nf.key = a.next_form;

-- ---------------------------------------------------------------------
-- 7. سياسات الوصول (Row Level Security)
-- ---------------------------------------------------------------------
alter table public.departments     enable row level security;
alter table public.profiles        enable row level security;
alter table public.form_defs       enable row level security;
alter table public.projects        enable row level security;
alter table public.project_forms   enable row level security;
alter table public.change_requests enable row level security;
alter table public.quality_notes   enable row level security;
alter table public.notifications   enable row level security;
alter table public.audit_log       enable row level security;

-- الأقسام والنماذج: يقرؤها كل عضو؛ والمدير وحده يعدّل اختصاص النماذج وحساسيتها
create policy departments_read on public.departments for select to authenticated using (true);
create policy form_defs_read   on public.form_defs   for select to authenticated using (true);
create policy form_defs_update on public.form_defs   for update to authenticated
  using (public.is_director()) with check (public.is_director());

-- الملفات: كل مستخدم يرى ملفه؛ الأعضاء يرون المفعّلين؛ المدير يرى الجميع
create policy profiles_read on public.profiles for select to authenticated
  using (id = auth.uid() or public.is_director() or (public.is_member() and active));
create policy profiles_update_own on public.profiles for update to authenticated
  using (id = auth.uid()) with check (id = auth.uid());

-- المشاريع
create policy projects_read   on public.projects for select to authenticated using (public.is_member());
create policy projects_insert on public.projects for insert to authenticated
  with check (public.my_role() in ('director', 'office_staff'));
create policy projects_update on public.projects for update to authenticated
  using (public.my_role() in ('director', 'office_staff'))
  with check (public.my_role() in ('director', 'office_staff'));
create policy projects_delete on public.projects for delete to authenticated using (public.is_director());

-- حالات النماذج: قراءة فقط؛ التغيير عبر set_form_status و decide_request
create policy project_forms_read on public.project_forms for select to authenticated using (public.is_member());

-- الطلبات: قراءة للأعضاء؛ التغيير عبر الدوال فقط
create policy change_requests_read on public.change_requests for select to authenticated using (public.is_member());

-- ملاحظات الجودة: يكتبها مكتب التخطيط والتقييم وضمان الجودة والمدير؛ ويحذفها المدير
create policy quality_notes_read   on public.quality_notes for select to authenticated using (public.is_member());
create policy quality_notes_insert on public.quality_notes for insert to authenticated
  with check (public.my_role() in ('director', 'planning_qa'));
create policy quality_notes_delete on public.quality_notes for delete to authenticated using (public.is_director());

-- الإشعارات: كل مستخدم يرى إشعاراته ويعلّمها مقروءة
create policy notifications_read   on public.notifications for select to authenticated using (user_id = auth.uid());
create policy notifications_update on public.notifications for update to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());

-- سجل التدقيق: المدير يرى كل شيء؛ الأعضاء يرون سجل المشاريع فقط. لا تعديل ولا حذف لأحد.
create policy audit_read on public.audit_log for select to authenticated
  using (public.is_director() or (public.is_member() and project_id is not null));

-- ---------------------------------------------------------------------
-- 8. الصلاحيات على مستوى الجداول والأعمدة والدوال
-- ---------------------------------------------------------------------
revoke all on all tables in schema public from anon;
revoke all on public.v_project_progress from anon;

revoke insert, update, delete, truncate on public.departments, public.form_defs, public.project_forms,
  public.change_requests, public.audit_log, public.notifications, public.profiles from authenticated;
revoke update, truncate on public.quality_notes from authenticated;
revoke truncate on public.projects from authenticated;

grant select on all tables in schema public to authenticated;
grant insert, update, delete on public.projects to authenticated;
grant insert, delete on public.quality_notes to authenticated;
grant update (full_name) on public.profiles to authenticated;
grant update (read_at) on public.notifications to authenticated;
grant update (sensitive, responsible) on public.form_defs to authenticated;

-- الدوال الداخلية لا تُستدعى من التطبيق
revoke execute on all functions in schema public from public, anon, authenticated;
grant execute on function
  public.my_role(), public.is_member(), public.is_director(), public.can_edit_form(uuid, text),
  public.my_form_rights(uuid), public.set_form_status(uuid, text, public.form_status, text),
  public.decide_request(uuid, boolean, text), public.withdraw_request(uuid),
  public.set_engineer(uuid, text, text),
  public.set_user_access(uuid, public.app_role, text, boolean, text),
  public.status_label(public.form_status), public.actor_name(uuid), public.project_label(uuid)
to authenticated;

-- ---------------------------------------------------------------------
-- 9. التحديث اللحظي (Realtime)
-- ---------------------------------------------------------------------
alter publication supabase_realtime add table
  public.projects, public.project_forms, public.change_requests, public.notifications, public.quality_notes,
  public.form_defs;

-- ---------------------------------------------------------------------
-- 10. البيانات المرجعية: الأقسام والنماذج وتوزيع الاختصاص الافتراضي
-- ---------------------------------------------------------------------
insert into public.departments (key, name, can_supervise, sort) values
  ('supervision', 'الإشراف والتنسيق',   true,  1),
  ('technical',   'الشؤون الفنية',       false, 2),
  ('restoration', 'الترميم',             true,  3),
  ('acceptance',  'المطابقة والاستلام',  false, 4);

insert into public.form_defs (key, name, stage, sort, sensitive, responsible, engineer_field) values
  ('f01', 'أمر تعاقد',                 0,  1, false, '{office_staff,contracts}',        null),
  ('f02', 'أمر عمل',                   0,  2, false, '{office_staff,contracts}',        null),
  ('f03', 'نموذج عقد أشغال عامة',       0,  3, false, '{office_staff,contracts}',        null),
  ('f04', 'تكليف مهندس مشرف',          1,  4, false, '{office_staff,head:supervising}', 'eng_sup'),
  ('f05', 'تكليف مهندس حصر',           1,  5, false, '{office_staff,head:technical}',   'eng_qty'),
  ('f06', 'تكليف مهندس متابعة',        1,  6, false, '{office_staff,head:supervising}', 'eng_fol'),
  ('f07', 'تكليف مهندس سلامة',         1,  7, false, '{office_staff,head:supervising}', 'eng_saf'),
  ('f08', 'محضر تسليم واستلام موقع',    2,  8, false, '{office_staff,head:supervising}', null),
  ('f09', 'تصريح عمل',                 2,  9, false, '{office_staff,head:supervising}', null),
  ('f10', 'ورقة قياس مستخلص نموذج أ',   3, 10, true,  '{office_staff,head:supervising}', null),
  ('f11', 'ورقة قياس مستخلص نموذج ب',   3, 11, true,  '{office_staff,head:supervising}', null),
  ('f12', 'كشف حصر مستخلص',            3, 12, true,  '{office_staff,head:technical}',   null),
  ('f13', 'شهادة دفع مستخلص',          3, 13, true,  '{office_staff,contracts}',        null),
  ('f14', 'مستند مستخلص جاري',         3, 14, true,  '{office_staff,contracts}',        null),
  ('f15', 'مستند مستخلص ختامي',        3, 15, true,  '{office_staff,contracts}',        null),
  ('f16', 'محضر استلام ابتدائي',       4, 16, true,  '{office_staff,head:acceptance}',  null),
  ('f17', 'محضر استلام نهائي',         4, 17, true,  '{office_staff,head:acceptance}',  null),
  ('f18', 'إقفال عقد',                 4, 18, true,  '{office_staff,contracts}',        null);
