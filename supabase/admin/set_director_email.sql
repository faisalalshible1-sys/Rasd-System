-- =====================================================================
--  تعيين بريد المدير الكامل للمنظومة.
--  غيّر البريد في السطر التالي ثم شغّل الملف كاملاً في SQL Editor.
--  يعالج الحالات الثلاث تلقائياً:
--   1) البريد هو بريد المدير بالفعل: لا تغيير.
--   2) لا يوجد حساب بهذا البريد: يتغير بريد حساب المدير الحالي إليه (كلمة المرور كما هي).
--   3) يوجد حساب آخر بهذا البريد: يُنقل دور المدير إليه، ويُوقف حساب المدير السابق.
-- =====================================================================
do $$
declare
  v_target    text := lower(btrim('faisalalshible1@gmail.com'));
  v_dir       uuid;
  v_dir_email text;
  v_tid       uuid;
begin
  select id, email into v_dir, v_dir_email from public.profiles where role = 'director' limit 1;
  select id into v_tid from auth.users where lower(email) = v_target;

  if v_dir is not null and lower(coalesce(v_dir_email, '')) = v_target then
    raise notice 'البريد % هو بريد المدير بالفعل. لا تغيير.', v_target;
    return;
  end if;

  if v_tid is null then
    if v_dir is null then
      raise exception 'لا يوجد مدير ولا حساب بالبريد %. أنشئ الحساب من التطبيق أولاً ثم أعد التشغيل.', v_target;
    end if;
    update auth.users set email = v_target, updated_at = now() where id = v_dir;
    update auth.identities
       set identity_data = jsonb_set(coalesce(identity_data, '{}'::jsonb), '{email}', to_jsonb(v_target)),
           updated_at = now()
     where user_id = v_dir and provider = 'email';
    update public.profiles set email = v_target where id = v_dir;
    perform public.write_audit('user.email', null, null,
      jsonb_build_object('user_id', v_dir, 'from', v_dir_email, 'to', v_target), v_target, v_dir);
    raise notice 'تغيّر بريد دخول المدير من % إلى %. كلمة المرور كما هي.', v_dir_email, v_target;
  else
    insert into public.profiles (id, email) values (v_tid, v_target) on conflict (id) do nothing;
    if v_dir is not null then
      update public.profiles set role = null, department = null, active = false where id = v_dir;
    end if;
    update public.profiles
       set role = 'director', department = null, active = true, activated_at = coalesce(activated_at, now())
     where id = v_tid;
    perform public.write_audit('user.claim_director', null, null,
      jsonb_build_object('user_id', v_tid, 'email', v_target, 'previous_director', v_dir_email), v_target, v_tid);
    raise notice 'أصبح % مدير المنظومة.%', v_target,
      case when v_dir is not null then ' أُوقف حساب المدير السابق ' || v_dir_email else '' end;
  end if;
end $$;

-- النتيجة: يجب أن يظهر سطر واحد بدور director ومفعّل
select email, role, active from public.profiles
where role = 'director' or lower(email) = lower('faisalalshible1@gmail.com');
