-- التراجع عن الترحيل 44 (مواقع الخريطة). يُرفض إن وُجدت نقاط مسجَّلة حتى لا تضيع.
do $$
begin
  if to_regclass('public.geo_points') is not null and exists (select 1 from public.geo_points) then
    raise exception 'لا يُتراجع عن الترحيل 44: توجد مواقع مسجَّلة على الخريطة. المنظومة كما هي.';
  end if;
end $$;
drop function if exists public.geo_set(text, uuid, double precision, double precision, text);
drop function if exists public.geo_clear(text, uuid);
drop function if exists public.geo_target_ok(text, uuid);
drop table if exists public.geo_points;
