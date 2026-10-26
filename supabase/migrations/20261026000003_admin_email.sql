-- =====================================================================
--  تغيير بريد الدخول لأي مستخدم — من صلاحية مدير المكتب وحده.
--  يُشغَّل بعد ملفي المخطط والاستيراد.
--  التغيير فوري ولا يحتاج إرسال بريد تأكيد. يُسجَّل في سجل التدقيق ويُشعَر صاحب الحساب.
-- =====================================================================
create or replace function public.admin_set_email(p_user uuid, p_email text)
returns void
language plpgsql security definer set search_path = public, auth
as $$
declare
  v_email text := lower(btrim(coalesce(p_email, '')));
  v_old   text;
  v_name  text;
begin
  if not public.is_director() then
    raise exception 'تغيير بريد الدخول من صلاحية مدير المكتب وحده' using errcode = '42501';
  end if;
  if v_email !~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$' then
    raise exception 'صيغة البريد غير صحيحة' using errcode = '22023';
  end if;
  select email into v_old from auth.users where id = p_user;
  if not found then
    raise exception 'المستخدم غير موجود' using errcode = '22023';
  end if;
  if lower(coalesce(v_old, '')) = v_email then
    return;
  end if;
  if exists (select 1 from auth.users where lower(email) = v_email and id <> p_user) then
    raise exception 'هذا البريد مستخدم لحساب آخر' using errcode = '23505';
  end if;

  update auth.users set email = v_email, updated_at = now() where id = p_user;
  update auth.identities
     set identity_data = jsonb_set(coalesce(identity_data, '{}'::jsonb), '{email}', to_jsonb(v_email)),
         updated_at = now()
   where user_id = p_user and provider = 'email';

  perform set_config('app.trusted', 'on', true);
  update public.profiles set email = v_email where id = p_user;
  perform set_config('app.trusted', 'off', true);

  select coalesce(nullif(full_name, ''), v_email) into v_name from public.profiles where id = p_user;
  perform public.write_audit('user.email', null, null,
    jsonb_build_object('user_id', p_user, 'from', v_old, 'to', v_email), v_name);
  perform public.notify_user(p_user, 'email', 'تغيّر بريد الدخول', 'بريد الدخول الجديد: ' || v_email);
end;
$$;

revoke execute on function public.admin_set_email(uuid, text) from public, anon;
grant execute on function public.admin_set_email(uuid, text) to authenticated;
