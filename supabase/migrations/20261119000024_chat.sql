-- =====================================================================
-- الترحيل 24: المراسلات الداخلية
--   • محادثة خاصة بين شخصين، ومجموعات خاصة يختار منشئها أعضاءها، وقنوات للأقسام يحدد المدير جمهورها
--     (كل المكتب، أو أدوار، أو أقسام، أو وحدات) فيدخلها كل من يطابقها تلقائياً.
--   • الرسائل: نص وأرقام، ومرفقات (صور وفيديو وصوت وPDF وملفات Office) في حاوية خاصة لا يقرؤها إلا أعضاء المحادثة،
--     وربط عقد أو سجل من المنظومة، والرد على رسالة، والتعديل والحذف، ومؤشر غير المقروء، والتحديث اللحظي.
--   • مسؤول الأمن السيبراني والمدير يطّلعان على البيانات الوصفية فقط (من راسل من ومتى وأحجام المرفقات)
--     دون نص الرسائل أو محتوى المرفقات، ويقفلان أي محادثة عند الحاجة.
-- يُشغَّل بعد الترحيلات 1–23، ويمكن إعادة تشغيله دون ضرر.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. الجداول
-- ---------------------------------------------------------------------
create table if not exists public.chat_rooms (
  id              uuid primary key default gen_random_uuid(),
  kind            text not null check (kind in ('dm', 'group', 'channel')),
  title           text not null default '' check (length(title) <= 80),
  description     text not null default '' check (length(description) <= 500),
  dm_key          text unique,
  audience        jsonb not null default '{}'::jsonb check (jsonb_typeof(audience) = 'object' and length(audience::text) <= 3000),
  admins_only     boolean not null default false,
  locked          boolean not null default false,
  lock_reason     text not null default '',
  locked_by       uuid references public.profiles(id) on delete set null,
  locked_at       timestamptz,
  archived        boolean not null default false,
  created_by      uuid references public.profiles(id) on delete set null,
  created_at      timestamptz not null default now(),
  last_message_at timestamptz,
  msg_count       integer not null default 0
);
create index if not exists chat_rooms_created_by_idx on public.chat_rooms (created_by);
create index if not exists chat_rooms_locked_by_idx on public.chat_rooms (locked_by);

create table if not exists public.chat_members (
  room_id      uuid not null references public.chat_rooms(id) on delete cascade,
  user_id      uuid not null references public.profiles(id) on delete cascade,
  role         text not null default 'member' check (role in ('owner', 'admin', 'member')),
  -- false: صف حالة القراءة لعضو دخل القناة بمطابقة جمهورها (لا يمنحه وصولاً بعد خروجه من الجمهور)
  explicit     boolean not null default true,
  joined_at    timestamptz not null default now(),
  added_by     uuid references public.profiles(id) on delete set null,
  last_read_id bigint not null default 0,
  muted        boolean not null default false,
  pinned       boolean not null default false,
  primary key (room_id, user_id)
);
create index if not exists chat_members_user_idx on public.chat_members (user_id);
create index if not exists chat_members_added_by_idx on public.chat_members (added_by);

create table if not exists public.chat_messages (
  id         bigint generated always as identity primary key,
  room_id    uuid not null references public.chat_rooms(id) on delete cascade,
  sender     uuid references public.profiles(id) on delete set null,
  kind       text not null default 'text' check (kind in ('text', 'file', 'link', 'system')),
  body       text not null default '' check (length(body) <= 8000),
  file_path  text,
  file_name  text check (file_name is null or length(file_name) <= 200),
  file_mime  text,
  file_size  bigint,
  width      integer,
  height     integer,
  ref        jsonb check (ref is null or (jsonb_typeof(ref) = 'object' and length(ref::text) <= 1000)),
  reply_to   bigint references public.chat_messages(id) on delete set null,
  created_at timestamptz not null default now(),
  edited_at  timestamptz,
  deleted_at timestamptz,
  deleted_by uuid references public.profiles(id) on delete set null
);
create index if not exists chat_messages_room_idx on public.chat_messages (room_id, id desc);
create index if not exists chat_messages_sender_idx on public.chat_messages (sender, created_at desc);
create index if not exists chat_messages_reply_idx on public.chat_messages (reply_to);
create index if not exists chat_messages_deleted_by_idx on public.chat_messages (deleted_by);
create index if not exists chat_messages_file_idx on public.chat_messages (file_path) where file_path is not null;
create index if not exists chat_messages_created_idx on public.chat_messages (created_at desc);

insert into public.app_settings (key, value) values
  ('chat.config', '{"enabled": true, "groups": true, "max_file_mb": 50, "edit_minutes": 60}'::jsonb)
on conflict (key) do nothing;

-- قناة عامة لكل المكتب
insert into public.chat_rooms (id, kind, title, description, audience)
values ('00000000-0000-4000-8000-00000000c4a7', 'channel', 'المكتب – عام', 'قناة يراها كل مستخدمي المنظومة',
        '{"all": true}'::jsonb)
on conflict (id) do nothing;

-- ---------------------------------------------------------------------
-- 2. الوصول
-- ---------------------------------------------------------------------
create or replace function public.chat_cfg(p_key text, p_default jsonb)
returns jsonb
language sql stable security definer set search_path = public
as $$
  select coalesce((select value -> p_key from public.app_settings where key = 'chat.config'), p_default)
$$;

-- هل يطابق المستخدم الحالي جمهور القناة؟
create or replace function public.chat_audience_ok(p_aud jsonb)
returns boolean
language sql stable security definer set search_path = public
as $$
  select exists (
    select 1 from public.profiles me
     where me.id = auth.uid() and me.active and me.role is not null
       and (me.role::text = 'director'
            or coalesce((p_aud ->> 'all')::boolean, false)
            or coalesce(p_aud -> 'roles', '[]'::jsonb) ? me.role::text
            or (me.department is not null and coalesce(p_aud -> 'departments', '[]'::jsonb) ? me.department)
            or (me.unit is not null and coalesce(p_aud -> 'units', '[]'::jsonb) ? me.unit)
            or coalesce(p_aud -> 'users', '[]'::jsonb) ? me.id::text))
$$;

create or replace function public.chat_can_access(p_room uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
  select public.is_member() and exists (
    select 1 from public.chat_rooms r
     where r.id = p_room
       and (exists (select 1 from public.chat_members m where m.room_id = r.id and m.user_id = auth.uid() and m.explicit)
            or (r.kind = 'channel' and public.chat_audience_ok(r.audience))))
$$;

-- مشرف المحادثة: المالك أو المشرف فيها، والمدير في القنوات
create or replace function public.chat_is_admin(p_room uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
  select public.chat_can_access(p_room) and (
    (public.is_director() and exists (select 1 from public.chat_rooms where id = p_room and kind = 'channel'))
    or exists (select 1 from public.chat_members m join public.chat_rooms r on r.id = m.room_id
                where m.room_id = p_room and m.user_id = auth.uid() and m.explicit and m.role in ('owner', 'admin')
                  and r.kind <> 'dm'))
$$;

create or replace function public.chat_can_post(p_room uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
  select coalesce((public.chat_cfg('enabled', 'true') #>> '{}')::boolean, true)
     and public.chat_can_access(p_room)
     and exists (select 1 from public.chat_rooms r where r.id = p_room and not r.locked and not r.archived
                   and (not r.admins_only or public.chat_is_admin(p_room)))
$$;

-- الحاوية: <المحادثة>/<اسم عشوائي>.<الامتداد>
create or replace function public.chat_path_room(p_name text)
returns uuid
language sql immutable set search_path = public
as $$
  select case when p_name ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/[A-Za-z0-9_-]{8,64}\.[a-z0-9]{2,5}$'
              then split_part(p_name, '/', 1)::uuid end
$$;

create or replace function public.chat_can_upload_path(p_name text)
returns boolean
language sql stable security definer set search_path = public
as $$
  select p_name ~* '\.(jpg|jpeg|png|webp|gif|heic|mp4|mov|webm|m4a|mp3|ogg|wav|aac|pdf|docx|xlsx|pptx|txt|csv|zip)$'
     and public.chat_path_room(p_name) is not null
     and public.chat_can_post(public.chat_path_room(p_name))
$$;

-- ---------------------------------------------------------------------
-- 3. إنشاء المحادثات وإدارتها
-- ---------------------------------------------------------------------
create or replace function public.chat_sys(p_room uuid, p_text text)
returns void
language plpgsql security definer set search_path = public
as $$
begin
  insert into public.chat_messages (room_id, sender, kind, body) values (p_room, auth.uid(), 'system', left(p_text, 500));
  update public.chat_rooms set last_message_at = now(), msg_count = msg_count + 1 where id = p_room;
end;
$$;

create or replace function public.chat_open_dm(p_user uuid)
returns uuid
language plpgsql security definer set search_path = public
as $$
declare
  v_key  text;
  v_room uuid;
begin
  if not public.is_member() then
    raise exception 'غير مصرح' using errcode = '42501';
  end if;
  if not coalesce((public.chat_cfg('enabled', 'true') #>> '{}')::boolean, true) then
    raise exception 'المراسلات الداخلية موقوفة' using errcode = '42501';
  end if;
  if p_user is null or p_user = auth.uid() then
    raise exception 'اختر شخصاً آخر' using errcode = '22023';
  end if;
  if not exists (select 1 from public.profiles where id = p_user and active and role is not null) then
    raise exception 'المستخدم غير موجود أو غير مفعّل' using errcode = 'P0002';
  end if;
  v_key := least(auth.uid()::text, p_user::text) || ':' || greatest(auth.uid()::text, p_user::text);
  select id into v_room from public.chat_rooms where dm_key = v_key;
  if found then
    return v_room;
  end if;
  insert into public.chat_rooms (kind, dm_key, created_by) values ('dm', v_key, auth.uid())
  on conflict (dm_key) do nothing
  returning id into v_room;
  if v_room is null then
    select id into v_room from public.chat_rooms where dm_key = v_key;
    return v_room;
  end if;
  insert into public.chat_members (room_id, user_id, role, added_by)
  values (v_room, auth.uid(), 'member', auth.uid()), (v_room, p_user, 'member', auth.uid())
  on conflict do nothing;
  return v_room;
end;
$$;

create or replace function public.chat_create_group(p_title text, p_members uuid[], p_description text default '')
returns uuid
language plpgsql security definer set search_path = public
as $$
declare
  v_title text := btrim(coalesce(p_title, ''));
  v_ids   uuid[] := array(select distinct x from unnest(coalesce(p_members, '{}'::uuid[])) x where x is not null and x <> auth.uid());
  v_room  uuid;
  v_bad   integer;
begin
  if not public.is_member() then
    raise exception 'غير مصرح' using errcode = '42501';
  end if;
  if not coalesce((public.chat_cfg('enabled', 'true') #>> '{}')::boolean, true) then
    raise exception 'المراسلات الداخلية موقوفة' using errcode = '42501';
  end if;
  if not public.is_director() and not coalesce((public.chat_cfg('groups', 'true') #>> '{}')::boolean, true) then
    raise exception 'إنشاء المجموعات لمدير المكتب وحده حالياً' using errcode = '42501';
  end if;
  if length(v_title) < 2 or length(v_title) > 80 then
    raise exception 'اكتب اسماً للمجموعة (حرفان على الأقل)' using errcode = '22023';
  end if;
  if coalesce(array_length(v_ids, 1), 0) < 1 then
    raise exception 'اختر عضواً واحداً على الأقل' using errcode = '22023';
  end if;
  if array_length(v_ids, 1) > 200 then
    raise exception 'الحد الأعلى 200 عضو' using errcode = '22023';
  end if;
  select count(*) into v_bad from unnest(v_ids) x
   where not exists (select 1 from public.profiles where id = x and active and role is not null);
  if v_bad > 0 then
    raise exception 'بعض الأعضاء غير مفعّلين' using errcode = '22023';
  end if;
  insert into public.chat_rooms (kind, title, description, created_by)
  values ('group', v_title, left(btrim(coalesce(p_description, '')), 500), auth.uid())
  returning id into v_room;
  insert into public.chat_members (room_id, user_id, role, added_by) values (v_room, auth.uid(), 'owner', auth.uid());
  insert into public.chat_members (room_id, user_id, role, added_by) select v_room, x, 'member', auth.uid() from unnest(v_ids) x;
  perform public.chat_sys(v_room, 'أنشأ ' || public.actor_name(auth.uid()) || ' المجموعة');
  perform public.write_audit('chat.room_create', null, null,
    jsonb_build_object('room_id', v_room, 'kind', 'group', 'title', v_title, 'members', array_length(v_ids, 1) + 1), 'المراسلات');
  return v_room;
end;
$$;

create or replace function public.chat_clean_audience(p_aud jsonb)
returns jsonb
language plpgsql immutable set search_path = public
as $$
declare
  a jsonb := coalesce(p_aud, '{}'::jsonb);
  k text;
begin
  if jsonb_typeof(a) <> 'object' then
    raise exception 'جمهور القناة غير صالح' using errcode = '22023';
  end if;
  for k in select jsonb_object_keys(a) loop
    if k not in ('all', 'roles', 'departments', 'units', 'users') then
      raise exception 'مفتاح غير معروف في جمهور القناة: %', k using errcode = '22023';
    end if;
    if k <> 'all' and jsonb_typeof(a -> k) <> 'array' then
      raise exception 'جمهور القناة غير صالح' using errcode = '22023';
    end if;
  end loop;
  if not coalesce((a ->> 'all')::boolean, false)
     and coalesce(jsonb_array_length(a -> 'roles'), 0) + coalesce(jsonb_array_length(a -> 'departments'), 0)
       + coalesce(jsonb_array_length(a -> 'units'), 0) + coalesce(jsonb_array_length(a -> 'users'), 0) = 0 then
    raise exception 'حدّد جمهور القناة: كل المكتب، أو أدواراً، أو أقساماً، أو وحدات، أو أشخاصاً' using errcode = '22023';
  end if;
  return a;
end;
$$;

create or replace function public.chat_create_channel(p_title text, p_description text, p_audience jsonb, p_admins_only boolean default false)
returns uuid
language plpgsql security definer set search_path = public
as $$
declare
  v_title text := btrim(coalesce(p_title, ''));
  v_room  uuid;
begin
  if not public.is_director() then
    raise exception 'قنوات الأقسام من صلاحية مدير المكتب' using errcode = '42501';
  end if;
  if length(v_title) < 2 or length(v_title) > 80 then
    raise exception 'اكتب اسماً للقناة' using errcode = '22023';
  end if;
  insert into public.chat_rooms (kind, title, description, audience, admins_only, created_by)
  values ('channel', v_title, left(btrim(coalesce(p_description, '')), 500), public.chat_clean_audience(p_audience),
          coalesce(p_admins_only, false), auth.uid())
  returning id into v_room;
  perform public.chat_sys(v_room, 'أنشأ ' || public.actor_name(auth.uid()) || ' القناة');
  perform public.write_audit('chat.room_create', null, null,
    jsonb_build_object('room_id', v_room, 'kind', 'channel', 'title', v_title, 'audience', p_audience), 'المراسلات');
  return v_room;
end;
$$;

create or replace function public.chat_update_room(p_room uuid, p_data jsonb)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  r     public.chat_rooms;
  v_new public.chat_rooms;
begin
  select * into r from public.chat_rooms where id = p_room for update;
  if not found then
    raise exception 'المحادثة غير موجودة' using errcode = 'P0002';
  end if;
  if r.kind = 'dm' or not public.chat_is_admin(p_room) then
    raise exception 'تعديل المحادثة لمشرفيها' using errcode = '42501';
  end if;
  if jsonb_typeof(coalesce(p_data, 'null'::jsonb)) <> 'object' then
    raise exception 'بيانات غير صالحة' using errcode = '22023';
  end if;
  if p_data ? 'audience' and not (r.kind = 'channel' and public.is_director()) then
    raise exception 'جمهور القناة يحدده مدير المكتب' using errcode = '42501';
  end if;
  update public.chat_rooms set
    title = case when p_data ? 'title' then left(btrim(p_data ->> 'title'), 80) else title end,
    description = case when p_data ? 'description' then left(btrim(coalesce(p_data ->> 'description', '')), 500) else description end,
    admins_only = coalesce((p_data ->> 'admins_only')::boolean, admins_only),
    archived = coalesce((p_data ->> 'archived')::boolean, archived),
    audience = case when p_data ? 'audience' then public.chat_clean_audience(p_data -> 'audience') else audience end
  where id = p_room
  returning * into v_new;
  if length(v_new.title) < 2 then
    raise exception 'اكتب اسماً للمحادثة' using errcode = '22023';
  end if;
  perform public.write_audit('chat.room_update', null, null,
    jsonb_build_object('room_id', p_room, 'kind', r.kind, 'title', v_new.title,
                       'changes', public.jsonb_changes(to_jsonb(r), to_jsonb(v_new), array['last_message_at', 'msg_count'])),
    'المراسلات');
end;
$$;

create or replace function public.chat_set_members(p_room uuid, p_add uuid[], p_remove uuid[])
returns void
language plpgsql security definer set search_path = public
as $$
declare
  r       public.chat_rooms;
  v_add   uuid[] := array(select distinct x from unnest(coalesce(p_add, '{}'::uuid[])) x where x is not null);
  v_rem   uuid[] := array(select distinct x from unnest(coalesce(p_remove, '{}'::uuid[])) x where x is not null);
  v_added integer := 0;
  v_gone  integer := 0;
begin
  select * into r from public.chat_rooms where id = p_room for update;
  if not found then
    raise exception 'المحادثة غير موجودة' using errcode = 'P0002';
  end if;
  if r.kind = 'dm' then
    raise exception 'المحادثة الخاصة بين شخصين فقط؛ أنشئ مجموعة لإضافة آخرين' using errcode = '22023';
  end if;
  if not public.chat_is_admin(p_room) then
    raise exception 'إدارة الأعضاء لمشرفي المحادثة' using errcode = '42501';
  end if;
  if exists (select 1 from unnest(v_add) x where not exists (select 1 from public.profiles where id = x and active and role is not null)) then
    raise exception 'بعض الأعضاء غير مفعّلين' using errcode = '22023';
  end if;
  if exists (select 1 from public.chat_members where room_id = p_room and role = 'owner' and user_id = any (v_rem))
     and not public.is_director() then
    raise exception 'لا يُزال مالك المجموعة' using errcode = '42501';
  end if;
  insert into public.chat_members (room_id, user_id, role, added_by, explicit)
  select p_room, x, 'member', auth.uid(), true from unnest(v_add) x
  on conflict (room_id, user_id) do update set explicit = true
    where not public.chat_members.explicit;
  get diagnostics v_added = row_count;
  delete from public.chat_members where room_id = p_room and user_id = any (v_rem) and not (user_id = any (v_add));
  get diagnostics v_gone = row_count;
  if (select count(*) from public.chat_members where room_id = p_room and explicit) + 0 > 500 then
    raise exception 'الحد الأعلى 500 عضو' using errcode = '22023';
  end if;
  if v_added + v_gone > 0 then
    perform public.chat_sys(p_room, public.actor_name(auth.uid())
      || case when v_added > 0 then ' أضاف ' || (select string_agg(public.actor_name(x), '، ') from unnest(v_add) x) else '' end
      || case when v_added > 0 and v_gone > 0 then ' و' else '' end
      || case when v_gone > 0 then ' أزال ' || (select string_agg(public.actor_name(x), '، ') from unnest(v_rem) x) else '' end);
    perform public.write_audit('chat.members', null, null,
      jsonb_build_object('room_id', p_room, 'title', r.title, 'kind', r.kind, 'added', to_jsonb(v_add), 'removed', to_jsonb(v_rem)),
      'المراسلات');
  end if;
end;
$$;

create or replace function public.chat_set_member_role(p_room uuid, p_user uuid, p_role text)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  r public.chat_rooms;
begin
  select * into r from public.chat_rooms where id = p_room;
  if not found or r.kind = 'dm' then
    raise exception 'المحادثة غير موجودة' using errcode = 'P0002';
  end if;
  if p_role not in ('admin', 'member') then
    raise exception 'الدور غير صالح' using errcode = '22023';
  end if;
  if not (public.is_director() and public.chat_can_access(p_room))
     and not exists (select 1 from public.chat_members where room_id = p_room and user_id = auth.uid() and role = 'owner') then
    raise exception 'تعيين المشرفين لمالك المجموعة' using errcode = '42501';
  end if;
  insert into public.chat_members (room_id, user_id, role, added_by, explicit)
  select p_room, p_user, p_role, auth.uid(), true
   where exists (select 1 from public.profiles where id = p_user and active and role is not null)
  on conflict (room_id, user_id) do update set role = excluded.role, explicit = true
    where public.chat_members.role <> 'owner';
  if not found then
    raise exception 'لا يتغير دور المالك' using errcode = '22023';
  end if;
  perform public.write_audit('chat.members', null, null,
    jsonb_build_object('room_id', p_room, 'title', r.title, 'kind', r.kind, 'user_id', p_user, 'role', p_role), 'المراسلات');
end;
$$;

create or replace function public.chat_leave(p_room uuid)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  r      public.chat_rooms;
  m      public.chat_members;
  v_next uuid;
begin
  select * into r from public.chat_rooms where id = p_room for update;
  select * into m from public.chat_members where room_id = p_room and user_id = auth.uid();
  if r.id is null or m.room_id is null or not m.explicit then
    raise exception 'لست عضواً في هذه المحادثة' using errcode = 'P0002';
  end if;
  if r.kind <> 'group' then
    raise exception 'المغادرة من المجموعات فقط' using errcode = '22023';
  end if;
  delete from public.chat_members where room_id = p_room and user_id = auth.uid();
  if m.role = 'owner' then
    select user_id into v_next from public.chat_members where room_id = p_room and explicit
     order by (role = 'admin') desc, joined_at limit 1;
    if v_next is null then
      update public.chat_rooms set archived = true where id = p_room;
    else
      update public.chat_members set role = 'owner' where room_id = p_room and user_id = v_next;
    end if;
  end if;
  perform public.chat_sys(p_room, 'غادر ' || public.actor_name(auth.uid()) || ' المجموعة');
end;
$$;

-- ---------------------------------------------------------------------
-- 4. الرسائل
-- ---------------------------------------------------------------------
create or replace function public.chat_send(p_room uuid, p_body text, p_file jsonb default null, p_reply_to bigint default null,
                                            p_ref jsonb default null)
returns bigint
language plpgsql security definer set search_path = public
as $$
declare
  v_body  text := btrim(coalesce(p_body, ''));
  v_kind  text := 'text';
  v_path  text;
  v_name  text;
  v_mime  text;
  v_size  bigint;
  v_max   bigint := least(greatest(coalesce((public.chat_cfg('max_file_mb', '50') #>> '{}')::int, 50), 1), 50)::bigint * 1048576;
  v_id    bigint;
  v_ref   jsonb;
begin
  if not public.chat_can_post(p_room) then
    if exists (select 1 from public.chat_rooms where id = p_room and locked) and public.chat_can_access(p_room) then
      raise exception 'المحادثة مقفلة: %', (select coalesce(nullif(lock_reason, ''), 'بقرار أمني') from public.chat_rooms where id = p_room)
        using errcode = '42501';
    end if;
    raise exception 'لا تملك الإرسال في هذه المحادثة' using errcode = '42501';
  end if;
  if length(v_body) > 8000 then
    raise exception 'الرسالة أطول من 8000 حرف' using errcode = '22023';
  end if;
  if (select count(*) from public.chat_messages where sender = auth.uid() and created_at > now() - interval '1 minute') >= 40 then
    raise exception 'رسائل كثيرة في دقيقة واحدة؛ انتظر قليلاً' using errcode = '54000';
  end if;
  if p_file is not null and jsonb_typeof(p_file) = 'object' then
    v_path := p_file ->> 'path';
    v_name := left(btrim(coalesce(p_file ->> 'name', '')), 200);
    if v_path is null or public.chat_path_room(v_path) is distinct from p_room or not public.chat_can_upload_path(v_path) then
      raise exception 'مسار المرفق غير صالح' using errcode = '22023';
    end if;
    if exists (select 1 from public.chat_messages where file_path = v_path) then
      raise exception 'المرفق مستخدم في رسالة أخرى' using errcode = '22023';
    end if;
    if to_regclass('storage.objects') is not null then
      execute 'select metadata ->> ''mimetype'', (metadata ->> ''size'')::bigint from storage.objects where bucket_id = ''chat'' and name = $1'
        into v_mime, v_size using v_path;
      if v_size is null then
        raise exception 'لم يكتمل رفع المرفق؛ أعد المحاولة' using errcode = 'P0002';
      end if;
    end if;
    v_mime := lower(coalesce(v_mime, 'application/octet-stream'));
    v_size := coalesce(v_size, 1);
    if v_size > v_max then
      raise exception 'حجم المرفق أكبر من الحد المسموح (% ميجابايت)', v_max / 1048576 using errcode = '22023';
    end if;
    if length(v_name) < 1 then
      v_name := split_part(v_path, '/', 2);
    end if;
    v_kind := 'file';
  elsif p_ref is not null and jsonb_typeof(p_ref) = 'object' then
    if coalesce(p_ref ->> 'type', '') not in ('project', 'unit', 'doc', 'report', 'risk', 'swot', 'request', 'ref')
       or length(coalesce(p_ref ->> 'label', '')) not between 1 and 200 then
      raise exception 'الرابط غير صالح' using errcode = '22023';
    end if;
    v_ref := jsonb_build_object('type', p_ref ->> 'type', 'id', left(coalesce(p_ref ->> 'id', ''), 64),
                                'label', left(p_ref ->> 'label', 200), 'sub', left(coalesce(p_ref ->> 'sub', ''), 200));
    v_kind := 'link';
  elsif length(v_body) < 1 then
    raise exception 'الرسالة فارغة' using errcode = '22023';
  end if;
  if p_reply_to is not null and not exists (select 1 from public.chat_messages where id = p_reply_to and room_id = p_room) then
    raise exception 'الرسالة المردود عليها غير موجودة' using errcode = '22023';
  end if;
  insert into public.chat_messages (room_id, sender, kind, body, file_path, file_name, file_mime, file_size, width, height, ref, reply_to)
  values (p_room, auth.uid(), v_kind, v_body, v_path, v_name, v_mime, v_size,
          case when v_path is not null then nullif(p_file ->> 'width', '')::int end,
          case when v_path is not null then nullif(p_file ->> 'height', '')::int end, v_ref, p_reply_to)
  returning id into v_id;
  update public.chat_rooms set last_message_at = now(), msg_count = msg_count + 1 where id = p_room;
  insert into public.chat_members (room_id, user_id, explicit, last_read_id)
  values (p_room, auth.uid(), false, v_id)
  on conflict (room_id, user_id) do update set last_read_id = greatest(public.chat_members.last_read_id, excluded.last_read_id);
  return v_id;
end;
$$;

create or replace function public.chat_edit_message(p_id bigint, p_body text)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  m      public.chat_messages;
  v_body text := btrim(coalesce(p_body, ''));
  v_min  integer := least(greatest(coalesce((public.chat_cfg('edit_minutes', '60') #>> '{}')::int, 60), 0), 10080);
begin
  select * into m from public.chat_messages where id = p_id for update;
  if not found or m.deleted_at is not null then
    raise exception 'الرسالة غير موجودة' using errcode = 'P0002';
  end if;
  if m.sender is distinct from auth.uid() or m.kind = 'system' then
    raise exception 'تعدّل رسائلك فقط' using errcode = '42501';
  end if;
  if not public.chat_can_post(m.room_id) then
    raise exception 'لا تملك الإرسال في هذه المحادثة' using errcode = '42501';
  end if;
  if m.created_at < now() - make_interval(mins => v_min) then
    raise exception 'انتهت مهلة التعديل (% دقيقة)', v_min using errcode = '22023';
  end if;
  if length(v_body) > 8000 or (length(v_body) < 1 and m.kind = 'text') then
    raise exception 'نص الرسالة غير صالح' using errcode = '22023';
  end if;
  update public.chat_messages set body = v_body, edited_at = now() where id = p_id;
end;
$$;

-- يحذف المرسل رسالته، ويحذف المشرف أي رسالة في محادثته (ويُسجَّل ذلك). يعيد مسار المرفق لحذفه من الحاوية.
create or replace function public.chat_delete_message(p_id bigint)
returns text
language plpgsql security definer set search_path = public
as $$
declare
  m public.chat_messages;
  r public.chat_rooms;
begin
  select * into m from public.chat_messages where id = p_id for update;
  if not found or m.deleted_at is not null then
    raise exception 'الرسالة غير موجودة' using errcode = 'P0002';
  end if;
  select * into r from public.chat_rooms where id = m.room_id;
  if not ((m.sender = auth.uid() and m.kind <> 'system' and public.chat_can_access(m.room_id)) or public.chat_is_admin(m.room_id)) then
    raise exception 'تحذف رسائلك، أو أي رسالة إن كنت مشرف المحادثة' using errcode = '42501';
  end if;
  update public.chat_messages set body = '', file_path = null, file_name = null, ref = null, deleted_at = now(), deleted_by = auth.uid()
   where id = p_id;
  if m.sender is distinct from auth.uid() then
    perform public.write_audit('chat.message_delete', null, null,
      jsonb_build_object('room_id', m.room_id, 'title', r.title, 'kind', r.kind, 'message_id', p_id,
                         'sender', public.actor_name(m.sender), 'at', m.created_at, 'file_size', m.file_size),
      'المراسلات');
  end if;
  return m.file_path;
end;
$$;

create or replace function public.chat_mark_read(p_room uuid, p_last bigint default null)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  v_last bigint;
begin
  if not public.chat_can_access(p_room) then
    raise exception 'غير مصرح' using errcode = '42501';
  end if;
  v_last := coalesce(p_last, (select max(id) from public.chat_messages where room_id = p_room), 0);
  insert into public.chat_members (room_id, user_id, explicit, last_read_id)
  values (p_room, auth.uid(), false, v_last)
  on conflict (room_id, user_id) do update set last_read_id = greatest(public.chat_members.last_read_id, excluded.last_read_id);
end;
$$;

create or replace function public.chat_set_pref(p_room uuid, p_muted boolean default null, p_pinned boolean default null)
returns void
language plpgsql security definer set search_path = public
as $$
begin
  if not public.chat_can_access(p_room) then
    raise exception 'غير مصرح' using errcode = '42501';
  end if;
  insert into public.chat_members (room_id, user_id, explicit, muted, pinned)
  values (p_room, auth.uid(), false, coalesce(p_muted, false), coalesce(p_pinned, false))
  on conflict (room_id, user_id) do update set muted = coalesce(p_muted, public.chat_members.muted),
                                               pinned = coalesce(p_pinned, public.chat_members.pinned);
end;
$$;

-- محادثاتي مع غير المقروء وآخر رسالة
create or replace function public.chat_my_rooms()
returns setof jsonb
language plpgsql stable security definer set search_path = public
as $$
begin
  if not public.is_member() then
    raise exception 'غير مصرح' using errcode = '42501';
  end if;
  return query
  with rooms as (
    select r.* from public.chat_rooms r
     where exists (select 1 from public.chat_members m where m.room_id = r.id and m.user_id = auth.uid() and m.explicit)
        or (r.kind = 'channel' and public.chat_audience_ok(r.audience))
  )
  select to_jsonb(r) - 'dm_key' - 'msg_count'
    || jsonb_build_object(
         'my_role', coalesce(me.role, case when r.kind = 'channel' and public.is_director() then 'admin' else 'member' end),
         'muted', coalesce(me.muted, false), 'pinned', coalesce(me.pinned, false),
         'last_read_id', coalesce(me.last_read_id, 0),
         'unread', (select count(*) from public.chat_messages x
                     where x.room_id = r.id and x.id > coalesce(me.last_read_id, 0) and x.sender is distinct from auth.uid()
                       and x.deleted_at is null and x.kind <> 'system'),
         'members', case when r.kind = 'channel' and not exists (select 1 from public.chat_members e where e.room_id = r.id and e.explicit)
                         then null else (select count(*) from public.chat_members e where e.room_id = r.id and e.explicit) end,
         'peer', case when r.kind = 'dm' then (
                    select jsonb_build_object('id', p.id, 'name', public.actor_name(p.id), 'active', p.active, 'role', p.role)
                      from public.chat_members o join public.profiles p on p.id = o.user_id
                     where o.room_id = r.id and o.user_id <> auth.uid() limit 1) end,
         'last', (select jsonb_build_object('id', l.id, 'kind', l.kind, 'sender', l.sender, 'sender_name', public.actor_name(l.sender),
                                            'at', l.created_at, 'deleted', l.deleted_at is not null,
                                            'text', case when l.deleted_at is not null then '' when l.kind = 'file' then coalesce(nullif(l.body, ''), l.file_name)
                                                         when l.kind = 'link' then l.ref ->> 'label' else left(l.body, 140) end,
                                            'mime', l.file_mime)
                    from public.chat_messages l where l.room_id = r.id order by l.id desc limit 1))
    from rooms r
    left join public.chat_members me on me.room_id = r.id and me.user_id = auth.uid()
   where not (r.kind = 'dm' and r.msg_count = 0 and r.created_by is distinct from auth.uid())
   order by coalesce(me.pinned, false) desc, coalesce(r.last_message_at, r.created_at) desc;
end;
$$;

-- ---------------------------------------------------------------------
-- 5. الأمن: قفل المحادثات والبيانات الوصفية
-- ---------------------------------------------------------------------
create or replace function public.chat_set_lock(p_room uuid, p_locked boolean, p_reason text default '')
returns void
language plpgsql security definer set search_path = public
as $$
declare
  r public.chat_rooms;
begin
  if not public.can_audit() then
    raise exception 'قفل المحادثات لمدير المكتب ومسؤول الأمن السيبراني' using errcode = '42501';
  end if;
  select * into r from public.chat_rooms where id = p_room for update;
  if not found then
    raise exception 'المحادثة غير موجودة' using errcode = 'P0002';
  end if;
  if coalesce(p_locked, false) and length(btrim(coalesce(p_reason, ''))) < 3 then
    raise exception 'اكتب سبب القفل' using errcode = '22023';
  end if;
  if r.locked = coalesce(p_locked, false) then
    return;
  end if;
  update public.chat_rooms set locked = coalesce(p_locked, false),
    lock_reason = case when p_locked then left(btrim(p_reason), 300) else '' end,
    locked_by = case when p_locked then auth.uid() end, locked_at = case when p_locked then now() end
  where id = p_room;
  perform public.chat_sys(p_room, case when p_locked then 'قُفلت المحادثة: ' || left(btrim(p_reason), 300) else 'فُتحت المحادثة' end);
  perform public.write_audit(case when p_locked then 'chat.lock' else 'chat.unlock' end, null, null,
    jsonb_build_object('room_id', p_room, 'kind', r.kind, 'title', public.chat_room_label(p_room), 'reason', left(btrim(coalesce(p_reason, '')), 300)),
    'المراسلات');
end;
$$;

create or replace function public.chat_room_label(p_room uuid)
returns text
language sql stable security definer set search_path = public
as $$
  select case when r.kind = 'dm'
              then coalesce((select string_agg(public.actor_name(m.user_id), ' — ' order by m.joined_at, m.user_id)
                               from public.chat_members m where m.room_id = r.id and m.explicit), 'محادثة خاصة')
              else r.title end
    from public.chat_rooms r where r.id = p_room
$$;

create or replace function public.chat_delete_room(p_room uuid)
returns text[]
language plpgsql security definer set search_path = public
as $$
declare
  r       public.chat_rooms;
  v_paths text[];
  v_label text;
begin
  select * into r from public.chat_rooms where id = p_room for update;
  if not found then
    raise exception 'المحادثة غير موجودة' using errcode = 'P0002';
  end if;
  if not (public.is_director()
          or (r.kind = 'group' and exists (select 1 from public.chat_members where room_id = p_room and user_id = auth.uid() and role = 'owner'))) then
    raise exception 'حذف المحادثة لمدير المكتب أو مالك المجموعة' using errcode = '42501';
  end if;
  if r.id = '00000000-0000-4000-8000-00000000c4a7' then
    raise exception 'القناة العامة لا تُحذف؛ أرشفها بدلاً من ذلك' using errcode = '22023';
  end if;
  v_label := public.chat_room_label(p_room);
  select coalesce(array_agg(file_path), '{}') into v_paths from public.chat_messages where room_id = p_room and file_path is not null;
  delete from public.chat_rooms where id = p_room;
  perform public.write_audit('chat.room_delete', null, null,
    jsonb_build_object('room_id', p_room, 'kind', r.kind, 'title', v_label, 'messages', r.msg_count,
                       'files', coalesce(array_length(v_paths, 1), 0)),
    'المراسلات');
  return v_paths;
end;
$$;

-- البيانات الوصفية للمراسلات: من راسل من ومتى وأحجام المرفقات، دون نص الرسائل ولا أسماء الملفات
create or replace function public.sec_chat_overview(p_days integer default 30)
returns jsonb
language plpgsql stable security definer set search_path = public
as $$
declare
  v_days  integer := least(greatest(coalesce(p_days, 30), 1), 365);
  v_from  timestamptz := now() - make_interval(days => v_days);
begin
  if not public.can_audit() then
    raise exception 'مركز الأمن لمدير المكتب ومسؤول الأمن السيبراني' using errcode = '42501';
  end if;
  return jsonb_build_object(
    'days', v_days,
    'totals', (select jsonb_build_object(
                 'rooms', (select count(*) from public.chat_rooms),
                 'dm', (select count(*) from public.chat_rooms where kind = 'dm'),
                 'groups', (select count(*) from public.chat_rooms where kind = 'group'),
                 'channels', (select count(*) from public.chat_rooms where kind = 'channel'),
                 'locked', (select count(*) from public.chat_rooms where locked),
                 'messages', count(*) filter (where kind <> 'system'),
                 'files', count(*) filter (where kind = 'file'),
                 'bytes', coalesce(sum(file_size) filter (where kind = 'file'), 0),
                 'deleted', count(*) filter (where deleted_at is not null),
                 'edited', count(*) filter (where edited_at is not null),
                 'senders', count(distinct sender) filter (where kind <> 'system'),
                 'off_hours', count(*) filter (where kind <> 'system' and (
                     extract(hour from created_at at time zone 'Africa/Tripoli') not between 7 and 16
                     or extract(isodow from created_at at time zone 'Africa/Tripoli') in (5, 6))))
               from public.chat_messages where created_at >= v_from),
    'rooms', coalesce((select jsonb_agg(x order by x ->> 'last_at' desc nulls last) from (
        select jsonb_build_object('id', r.id, 'kind', r.kind, 'title', public.chat_room_label(r.id), 'locked', r.locked,
                 'lock_reason', r.lock_reason, 'archived', r.archived, 'created_at', r.created_at,
                 'created_by', public.actor_name(r.created_by), 'audience', case when r.kind = 'channel' then r.audience end,
                 'members', (select count(*) from public.chat_members m where m.room_id = r.id and m.explicit),
                 'messages', (select count(*) from public.chat_messages x where x.room_id = r.id and x.kind <> 'system' and x.created_at >= v_from),
                 'files', (select count(*) from public.chat_messages x where x.room_id = r.id and x.kind = 'file' and x.created_at >= v_from),
                 'bytes', (select coalesce(sum(file_size), 0) from public.chat_messages x where x.room_id = r.id and x.created_at >= v_from),
                 'last_at', r.last_message_at) x
          from public.chat_rooms r) s), '[]'::jsonb),
    'senders', coalesce((select jsonb_agg(x order by (x ->> 'messages')::int desc) from (
        select jsonb_build_object('id', sender, 'name', public.actor_name(sender), 'messages', count(*),
                 'files', count(*) filter (where kind = 'file'), 'bytes', coalesce(sum(file_size), 0),
                 'rooms', count(distinct room_id), 'last_at', max(created_at)) x
          from public.chat_messages where created_at >= v_from and kind <> 'system' and sender is not null
         group by sender) s), '[]'::jsonb),
    'pairs', coalesce((select jsonb_agg(x order by (x ->> 'messages')::int desc) from (
        select jsonb_build_object('from', public.actor_name(x.sender), 'to', public.chat_room_label(x.room_id), 'kind', r.kind,
                 'messages', count(*), 'bytes', coalesce(sum(x.file_size), 0), 'last_at', max(x.created_at)) x
          from public.chat_messages x join public.chat_rooms r on r.id = x.room_id
         where x.created_at >= v_from and x.kind <> 'system' and x.sender is not null
         group by x.sender, x.room_id, r.kind
         order by count(*) desc limit 60) s), '[]'::jsonb),
    'daily', coalesce((select jsonb_agg(jsonb_build_object('day', d, 'messages', n, 'bytes', b) order by d) from (
        select (created_at at time zone 'Africa/Tripoli')::date d, count(*) n, coalesce(sum(file_size), 0) b
          from public.chat_messages where created_at >= v_from and kind <> 'system' group by 1) s), '[]'::jsonb),
    'types', coalesce((select jsonb_agg(jsonb_build_object('type', t, 'files', n, 'bytes', b) order by b desc) from (
        select split_part(coalesce(file_mime, 'غير معروف'), '/', 1) t, count(*) n, coalesce(sum(file_size), 0) b
          from public.chat_messages where created_at >= v_from and kind = 'file' group by 1) s), '[]'::jsonb),
    'large', coalesce((select jsonb_agg(x order by (x ->> 'size')::bigint desc) from (
        select jsonb_build_object('sender', public.actor_name(sender), 'room', public.chat_room_label(room_id), 'mime', file_mime,
                 'size', file_size, 'at', created_at, 'deleted', deleted_at is not null) x
          from public.chat_messages where created_at >= v_from and kind = 'file' and file_size is not null
         order by file_size desc limit 20) s), '[]'::jsonb));
end;
$$;

create or replace function public.sec_chat_room_log(p_room uuid, p_limit integer default 300)
returns setof jsonb
language plpgsql stable security definer set search_path = public
as $$
begin
  if not public.can_audit() then
    raise exception 'مركز الأمن لمدير المكتب ومسؤول الأمن السيبراني' using errcode = '42501';
  end if;
  return query
    select jsonb_build_object('id', x.id, 'sender', public.actor_name(x.sender), 'at', x.created_at, 'kind', x.kind,
             'length', length(x.body), 'mime', x.file_mime, 'size', x.file_size, 'edited', x.edited_at is not null,
             'deleted', x.deleted_at is not null, 'deleted_by', case when x.deleted_by is not null then public.actor_name(x.deleted_by) end,
             'reply', x.reply_to is not null, 'link', x.ref ->> 'type')
      from public.chat_messages x
     where x.room_id = p_room
     order by x.id desc
     limit least(greatest(coalesce(p_limit, 300), 1), 2000);
end;
$$;

-- إعدادات المراسلات من لوحة التحكم
do $$
begin
  if not exists (select 1 from pg_proc where proname = 'set_setting_v23' and pronamespace = 'public'::regnamespace) then
    alter function public.set_setting(text, jsonb) rename to set_setting_v23;
  end if;
end $$;

create or replace function public.set_setting(p_key text, p_value jsonb)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  v_old jsonb;
begin
  if p_key <> 'chat.config' then
    perform public.set_setting_v23(p_key, p_value);
    return;
  end if;
  if not public.is_director() then
    raise exception 'الإعدادات من صلاحية مدير المكتب وحده' using errcode = '42501';
  end if;
  if jsonb_typeof(p_value) <> 'object'
     or exists (select 1 from jsonb_object_keys(p_value) k where k not in ('enabled', 'groups', 'max_file_mb', 'edit_minutes'))
     or jsonb_typeof(coalesce(p_value -> 'enabled', 'true')) <> 'boolean'
     or jsonb_typeof(coalesce(p_value -> 'groups', 'true')) <> 'boolean'
     or jsonb_typeof(coalesce(p_value -> 'max_file_mb', '50')) <> 'number'
     or jsonb_typeof(coalesce(p_value -> 'edit_minutes', '60')) <> 'number'
     or coalesce((p_value ->> 'max_file_mb')::numeric, 50) not between 1 and 50
     or coalesce((p_value ->> 'edit_minutes')::numeric, 60) not between 0 and 10080 then
    raise exception 'قيمة غير صالحة للإعداد %', p_key using errcode = '22023';
  end if;
  select value into v_old from public.app_settings where key = p_key;
  if v_old is not distinct from p_value then
    return;
  end if;
  insert into public.app_settings (key, value, updated_at, updated_by)
  values (p_key, p_value, now(), auth.uid())
  on conflict (key) do update set value = excluded.value, updated_at = excluded.updated_at, updated_by = excluded.updated_by;
  perform public.write_audit('setting.update', null, null, jsonb_build_object('key', p_key, 'from', v_old, 'to', p_value), p_key);
end;
$$;

-- ---------------------------------------------------------------------
-- 6. القراءة والتخزين والتحديث اللحظي
-- ---------------------------------------------------------------------
alter table public.chat_rooms enable row level security;
alter table public.chat_members enable row level security;
alter table public.chat_messages enable row level security;

drop policy if exists chat_rooms_read on public.chat_rooms;
create policy chat_rooms_read on public.chat_rooms for select to authenticated
  using ((select public.chat_can_access(id)));
drop policy if exists chat_members_read on public.chat_members;
create policy chat_members_read on public.chat_members for select to authenticated
  using (user_id = (select auth.uid()) or (select public.chat_can_access(room_id)));
drop policy if exists chat_messages_read on public.chat_messages;
create policy chat_messages_read on public.chat_messages for select to authenticated
  using ((select public.chat_can_access(room_id)));

revoke all on public.chat_rooms, public.chat_members, public.chat_messages from anon;
revoke insert, update, delete, truncate on public.chat_rooms, public.chat_members, public.chat_messages from authenticated;
grant select on public.chat_rooms, public.chat_members, public.chat_messages to authenticated;
grant all on public.chat_rooms, public.chat_members, public.chat_messages to service_role;

do $$
begin
  if to_regclass('storage.buckets') is null then
    return;
  end if;
  insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
  values ('chat', 'chat', false, 52428800,
          array['image/jpeg', 'image/png', 'image/webp', 'image/gif', 'image/heic',
                'video/mp4', 'video/quicktime', 'video/webm',
                'audio/mp4', 'audio/x-m4a', 'audio/mpeg', 'audio/ogg', 'audio/wav', 'audio/aac', 'audio/webm',
                'application/pdf', 'text/plain', 'text/csv', 'application/zip',
                'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
                'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
                'application/vnd.openxmlformats-officedocument.presentationml.presentation'])
  on conflict (id) do update set public = false, file_size_limit = excluded.file_size_limit,
                                 allowed_mime_types = excluded.allowed_mime_types;

  drop policy if exists chat_files_read on storage.objects;
  create policy chat_files_read on storage.objects for select to authenticated
    using (bucket_id = 'chat' and public.chat_can_access(public.chat_path_room(name)));

  drop policy if exists chat_files_upload on storage.objects;
  create policy chat_files_upload on storage.objects for insert to authenticated
    with check (bucket_id = 'chat' and public.chat_can_upload_path(name));

  -- يُحذف الملف بعد حذف رسالته فقط، أو إن رُفع ولم يُرسل
  drop policy if exists chat_files_delete on storage.objects;
  create policy chat_files_delete on storage.objects for delete to authenticated
    using (bucket_id = 'chat'
           and ((select public.is_director()) or owner_id = (select auth.uid())::text or owner = (select auth.uid()))
           and not exists (select 1 from public.chat_messages m where m.file_path = objects.name));
end $$;

do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and tablename = 'chat_messages') then
      execute 'alter publication supabase_realtime add table public.chat_messages';
    end if;
    if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and tablename = 'chat_rooms') then
      execute 'alter publication supabase_realtime add table public.chat_rooms';
    end if;
    if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and tablename = 'chat_members') then
      execute 'alter publication supabase_realtime add table public.chat_members';
    end if;
  end if;
end $$;

revoke execute on function
  public.chat_cfg(text, jsonb), public.chat_audience_ok(jsonb), public.chat_can_access(uuid), public.chat_is_admin(uuid),
  public.chat_can_post(uuid), public.chat_path_room(text), public.chat_can_upload_path(text), public.chat_sys(uuid, text),
  public.chat_open_dm(uuid), public.chat_create_group(text, uuid[], text), public.chat_clean_audience(jsonb),
  public.chat_create_channel(text, text, jsonb, boolean), public.chat_update_room(uuid, jsonb),
  public.chat_set_members(uuid, uuid[], uuid[]), public.chat_set_member_role(uuid, uuid, text), public.chat_leave(uuid),
  public.chat_send(uuid, text, jsonb, bigint, jsonb), public.chat_edit_message(bigint, text), public.chat_delete_message(bigint),
  public.chat_mark_read(uuid, bigint), public.chat_set_pref(uuid, boolean, boolean), public.chat_my_rooms(),
  public.chat_set_lock(uuid, boolean, text), public.chat_room_label(uuid), public.chat_delete_room(uuid),
  public.sec_chat_overview(integer), public.sec_chat_room_log(uuid, integer), public.set_setting(text, jsonb)
from public, anon;
grant execute on function
  public.chat_can_access(uuid), public.chat_is_admin(uuid), public.chat_can_post(uuid), public.chat_path_room(text),
  public.chat_can_upload_path(text),
  public.chat_open_dm(uuid), public.chat_create_group(text, uuid[], text),
  public.chat_create_channel(text, text, jsonb, boolean), public.chat_update_room(uuid, jsonb),
  public.chat_set_members(uuid, uuid[], uuid[]), public.chat_set_member_role(uuid, uuid, text), public.chat_leave(uuid),
  public.chat_send(uuid, text, jsonb, bigint, jsonb), public.chat_edit_message(bigint, text), public.chat_delete_message(bigint),
  public.chat_mark_read(uuid, bigint), public.chat_set_pref(uuid, boolean, boolean), public.chat_my_rooms(),
  public.chat_set_lock(uuid, boolean, text), public.chat_room_label(uuid), public.chat_delete_room(uuid),
  public.sec_chat_overview(integer), public.sec_chat_room_log(uuid, integer), public.set_setting(text, jsonb)
to authenticated;
revoke execute on function public.set_setting_v23(text, jsonb) from public, anon, authenticated;

notify pgrst, 'reload schema';
