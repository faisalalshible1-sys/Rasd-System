-- =====================================================================
--  إعادة ضبط قاعدة البيانات: يحذف كل ما أنشأه ملف المخطط (الجداول والدوال والأنواع)
--  لإعادة تشغيل ملفات migrations من البداية.
--  لا يحذف حسابات المستخدمين المسجلة في Authentication.
--  تحذير: يحذف كل المشاريع والسجلات المدخلة. استخدمه فقط عند الإعداد الأول.
-- =====================================================================
drop trigger if exists on_auth_user_created on auth.users;
drop view if exists public.v_project_progress;
drop table if exists public.pm_evaluations, public.pm_lessons, public.pm_changes, public.pm_delays, public.pm_issues,
  public.risk_reviews, public.pm_progress, public.pm_projects cascade;
drop table if exists public.swot_actions, public.swot_strategies, public.swot_factors, public.risks cascade;
drop table if exists public.extract_payments, public.user_devices, public.contract_extracts, public.contract_variations cascade;
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
        'jsonb_changes', 'jtext', 'jscore', 'jdate', 'jcodes', 'valid_text_list', 'can_edit_risks', 'can_edit_swot',
        'can_update_swot_action', 'save_risk', 'delete_risk', 'save_swot_factor', 'delete_swot_factor', 'save_swot_strategy',
        'delete_swot_strategy', 'save_swot_action', 'delete_swot_action', 'update_swot_action', 'ai_context_core',
        'recalc_contract_finance', 'finance_children_after', 'materialize_finance', 'can_edit_finance', 'set_work_values',
        'save_variation', 'delete_variation', 'save_extract', 'delete_extract', 'finance_history', 'security_target_ok',
        'lock_user', 'unlock_user', 'my_lock', 'request_header', 'register_device', 'my_devices', 'forget_my_device',
        'set_device_blocked', 'security_devices', 'security_timeline', 'security_alerts', 'ai_action_log',
        'sync_extract_paid', 'extract_payments_after', 'contract_extracts_move_payments', 'add_extract_payment',
        'delete_extract_payment', 'set_contract_advance',
        'jint', 'jnum', 'jpick', 'jbool', 'jproject', 'pm_next_code', 'pm_code', 'pm_num_ok', 'can_edit_pm', 'can_edit_schedule',
        'can_decide_change', 'can_approve_lessons', 'save_project_schedule', 'save_pm_progress', 'delete_pm_progress',
        'save_risk_review', 'delete_risk_review', 'save_pm_issue', 'save_pm_delay', 'save_pm_change', 'save_pm_lesson',
        'save_pm_evaluation', 'delete_pm_record', 'pm_sync_change_variation', 'contract_variations_pm_guard', 'pm_follow_merge',
        'set_setting_v15', 'ai_context_v15')
  loop
    execute 'drop function if exists ' || r.sig || ' cascade';
  end loop;
end $$;

drop type if exists public.app_role, public.form_status, public.request_state cascade;

select 'تمت إعادة الضبط. شغّل الآن ملفات migrations بالترتيب.' as result;
