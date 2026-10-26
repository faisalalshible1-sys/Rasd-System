-- =====================================================================
--  إعادة ضبط قاعدة البيانات: يحذف كل ما أنشأه ملف المخطط (الجداول والدوال والأنواع)
--  لإعادة تشغيل ملفي migrations من البداية.
--  لا يحذف حسابات المستخدمين المسجلة في Authentication.
--  تحذير: يحذف كل المشاريع والسجلات المدخلة. استخدمه فقط عند الإعداد الأول.
-- =====================================================================
drop trigger if exists on_auth_user_created on auth.users;
drop view if exists public.v_project_progress;
drop table if exists
  public.audit_log, public.notifications, public.quality_notes, public.change_requests,
  public.project_forms, public.projects, public.form_defs, public.profiles, public.departments
  cascade;

do $$
declare
  r record;
begin
  for r in
    select p.oid::regprocedure as sig
    from pg_proc p
    where p.pronamespace = 'public'::regnamespace
      and p.proname in (
        'my_role', 'is_member', 'is_director', 'actor_name', 'project_label', 'can_edit_form', 'my_form_rights',
        'write_audit', 'notify_user', 'notify_director', 'status_label', 'handle_new_user', 'profiles_guard',
        'projects_stamp', 'projects_audit', 'form_defs_audit', 'form_defs_guard', 'quality_notes_audit',
        'quality_notes_after', 'apply_form_status', 'set_form_status', 'decide_request', 'withdraw_request',
        'set_engineer', 'set_user_access', 'claim_director')
  loop
    execute 'drop function if exists ' || r.sig || ' cascade';
  end loop;
end $$;

drop type if exists public.app_role, public.form_status, public.request_state cascade;

select 'تمت إعادة الضبط. شغّل الآن ملفي migrations بالترتيب.' as result;
