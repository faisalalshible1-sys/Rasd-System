-- =====================================================================
-- الإصدار 1.13.0 (الترحيل 44): مواقع المشاريع وبلاغات الصيانة على الخريطة
--
--  جدول geo_points: نقطة (خط عرض وطول) لمشروع أو لبلاغ صيانة، واحدة لكل منهما. لا يمسّ جدولي المشاريع والبلاغات،
--  وتُقرأ النقطة بقراءة صاحبها (مشروع يراه المستخدم أو بلاغ يراه). المخاطر تأخذ موقع مشروعها فلا نقطة لها.
--  الكتابة بدالتين تسجّلان في سجل التدقيق: geo_set وgeo_clear، لا كتابة مباشرة:
--    مشروع: مدير المكتب وموظفو مكتبه (كحفظ بيانات العقد)؛ بلاغ: من يديرون الصيانة، أو مقدّم البلاغ لبلاغه.
--  يُشغَّل بعد 20261204000043_risk_actions_sections.sql، وإعادة تشغيله آمنة. التراجع: supabase/rollbacks/20261205000044_geo_points_down.sql
-- =====================================================================
create table if not exists public.geo_points (
  id            uuid primary key default gen_random_uuid(),
  project_id    uuid references public.projects (id) on delete cascade,
  request_id    uuid references public.mt_requests (id) on delete cascade,
  lat           double precision not null check (lat between -90 and 90),
  lng           double precision not null check (lng between -180 and 180),
  note          text not null default '' check (length(note) <= 200),
  updated_at    timestamptz not null default now(),
  updated_by    uuid references public.profiles (id) on delete set null,
  check ((project_id is not null)::int + (request_id is not null)::int = 1)
);
create unique index if not exists geo_points_project_uidx on public.geo_points (project_id) where project_id is not null;
create unique index if not exists geo_points_request_uidx on public.geo_points (request_id) where request_id is not null;
create index if not exists geo_points_updated_by_idx on public.geo_points (updated_by);

alter table public.geo_points enable row level security;
drop policy if exists geo_points_read on public.geo_points;
create policy geo_points_read on public.geo_points for select to authenticated
  using ((project_id is not null and exists (select 1 from public.projects p where p.id = geo_points.project_id))
      or (request_id is not null and exists (select 1 from public.mt_requests r where r.id = geo_points.request_id)));
revoke all on public.geo_points from anon;
revoke insert, update, delete, truncate on public.geo_points from authenticated;
grant select on public.geo_points to authenticated;
grant all on public.geo_points to service_role;

-- صلاحية الكتابة على صاحب النقطة؛ تعيد وصف الصاحب للتدقيق
create or replace function public.geo_target_ok(p_kind text, p_ref uuid)
returns text
language plpgsql stable security definer set search_path = public
as $$
declare
  r public.mt_requests;
  v_label text;
begin
  if p_kind = 'project' then
    if not (coalesce(public.my_role()::text in ('director', 'office_staff'), false) and public.writes_allowed()) then
      raise exception 'موقع المشروع لمدير المكتب وموظفي مكتبه' using errcode = '42501';
    end if;
    select coalesce(nullif(assign_no, ''), name) into v_label from public.projects where id = p_ref;
    if not found then
      raise exception 'المشروع غير موجود' using errcode = 'P0002';
    end if;
    return v_label;
  elsif p_kind = 'request' then
    select * into r from public.mt_requests where id = p_ref;
    if not found then
      raise exception 'البلاغ غير موجود' using errcode = 'P0002';
    end if;
    if not (public.mt_can_manage() or (public.mt_can_report() and r.reporter_id is not distinct from auth.uid())) then
      raise exception 'موقع البلاغ لمن يديرون الصيانة أو لمقدّمه' using errcode = '42501';
    end if;
    return r.req_no;
  end if;
  raise exception 'نوع الموقع غير معروف' using errcode = '22023';
end;
$$;

create or replace function public.geo_set(p_kind text, p_ref uuid, p_lat double precision, p_lng double precision, p_note text default '')
returns void
language plpgsql security definer set search_path = public
as $$
declare
  v_label text := public.geo_target_ok(p_kind, p_ref);
  v_note  text := btrim(coalesce(p_note, ''));
begin
  if p_lat is null or p_lng is null or p_lat not between -90 and 90 or p_lng not between -180 and 180 then
    raise exception 'إحداثيات غير صالحة (العرض بين −90 و90، والطول بين −180 و180)' using errcode = '22023';
  end if;
  if length(v_note) > 200 then
    raise exception 'الملاحظة أطول من 200 حرف' using errcode = '22023';
  end if;
  if p_kind = 'project' then
    insert into public.geo_points (project_id, lat, lng, note, updated_by) values (p_ref, p_lat, p_lng, v_note, auth.uid())
    on conflict (project_id) where project_id is not null
    do update set lat = excluded.lat, lng = excluded.lng, note = excluded.note, updated_at = now(), updated_by = auth.uid();
  else
    insert into public.geo_points (request_id, lat, lng, note, updated_by) values (p_ref, p_lat, p_lng, v_note, auth.uid())
    on conflict (request_id) where request_id is not null
    do update set lat = excluded.lat, lng = excluded.lng, note = excluded.note, updated_at = now(), updated_by = auth.uid();
  end if;
  perform public.write_audit('geo.set', case when p_kind = 'project' then p_ref end, null,
    jsonb_build_object('kind', p_kind, 'ref', p_ref, 'label', v_label, 'lat', round(p_lat::numeric, 6), 'lng', round(p_lng::numeric, 6)), v_label);
end;
$$;

create or replace function public.geo_clear(p_kind text, p_ref uuid)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  v_label text := public.geo_target_ok(p_kind, p_ref);
begin
  if p_kind = 'project' then
    delete from public.geo_points where project_id = p_ref;
  else
    delete from public.geo_points where request_id = p_ref;
  end if;
  if found then
    perform public.write_audit('geo.clear', case when p_kind = 'project' then p_ref end, null,
      jsonb_build_object('kind', p_kind, 'ref', p_ref, 'label', v_label), v_label);
  end if;
end;
$$;

revoke execute on function public.geo_target_ok(text, uuid) from public, anon, authenticated;
revoke execute on function public.geo_set(text, uuid, double precision, double precision, text), public.geo_clear(text, uuid) from public, anon;
grant execute on function public.geo_set(text, uuid, double precision, double precision, text), public.geo_clear(text, uuid) to authenticated;
