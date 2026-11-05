-- =====================================================================
--  أداء سياسات الصلاحيات (RLS):
--    التحقق من هوية المستخدم (auth.uid) ودوال الصلاحية يُحسب مرة واحدة
--    لكل استعلام بدل حسابه لكل صف، بلفّه داخل (select ...).
--    قواعد الوصول نفسها لم تتغير: من يرى ماذا كما هو.
--  يُشغَّل بعد 20261105000012_finance_v5.sql. إعادة تشغيله آمنة.
-- =====================================================================

alter policy notifications_read on public.notifications
  using (user_id = (select auth.uid()));

alter policy notifications_update on public.notifications
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

alter policy profiles_read on public.profiles
  using ((id = (select auth.uid())) or (select public.can_audit()) or ((select public.is_member()) and active));

alter policy profiles_update_own on public.profiles
  using (id = (select auth.uid()))
  with check (id = (select auth.uid()));

alter policy user_devices_read on public.user_devices
  using ((user_id = (select auth.uid())) or (select public.can_audit()));
