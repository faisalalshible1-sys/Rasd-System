-- =====================================================================
--  إعادة ضبط قاعدة البيانات: يحذف كل ما أنشأه ملف المخطط (الجداول والدوال والأنواع)
--  لإعادة تشغيل ملفات migrations من البداية.
--  لا يحذف حسابات المستخدمين المسجلة في Authentication.
--  تحذير: يحذف كل المشاريع والسجلات المدخلة. استخدمه فقط عند الإعداد الأول.
-- =====================================================================
drop trigger if exists on_auth_user_created on auth.users;
drop view if exists public.v_project_progress;
drop table if exists public.user_devices, public.contract_extracts, public.contract_variations cascade;
drop table if exists public.contract_engineers, public.contract_works cascade;
drop table if exists public.app_releases, public.app_settings, public.ideas, public.custom_fields cascade;
drop table if exists
  public.audit_log, public.notifications, public.quality_notes, public.change_requests,
  public.project_forms, public.projects, public.form_defs, public.stages, public.profiles, public.departments
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
        'set_engineer', 'set_user_access', 'claim_director', 'admin_set_email',
        'projects_finance_guard', 'set_contract_finance', 'projects_finance_calc',
        'setting', 'setting_bool', 'setting_num', 'mfa_enrolled', 'mfa_ok', 'writes_allowed', 'has_token',
        'normalize_form_order', 'save_stage', 'delete_stage', 'save_form_def', 'reorder_forms', 'delete_form_def',
        'save_department', 'save_custom_field', 'reorder_custom_fields', 'set_project_field', 'set_setting',
        'public_settings', 'export_config', 'import_settings', 'submit_idea', 'update_idea', 'delete_idea',
        'security_overview', 'security_users', 'list_sessions', 'revoke_session', 'revoke_user_sessions',
        'reset_user_mfa', 'login_history', 'is_auditor', 'can_audit', 'user_details', 'delete_user',
        'sync_engineer_names', 'contract_engineers_after', 'projects_first_work', 'set_contract_no', 'save_work',
        'delete_work', 'engineer_form', 'can_assign_engineer', 'save_engineer', 'delete_engineer', 'merge_contracts',
        'unmerge_contract', 'merged_sources', 'ai_context', 'ai_log',
        'recalc_contract_finance', 'finance_children_after', 'materialize_finance', 'can_edit_finance', 'set_work_values',
        'save_variation', 'delete_variation', 'save_extract', 'delete_extract', 'finance_history', 'security_target_ok',
        'lock_user', 'unlock_user', 'my_lock', 'request_header', 'register_device', 'my_devices', 'forget_my_device',
        'set_device_blocked', 'security_devices', 'security_timeline', 'security_alerts', 'ai_action_log')
  loop
    execute 'drop function if exists ' || r.sig || ' cascade';
  end loop;
end $$;

drop type if exists public.app_role, public.form_status, public.request_state cascade;

select 'تمت إعادة الضبط. شغّل الآن ملفات migrations بالترتيب.' as result;
