-- =====================================================================
--  فهارس المفاتيح الأجنبية:
--    فهرس لكل علاقة بين الجداول نبّه إليها مستشار الأداء في Supabase،
--    لتسريع الربط والحذف المتسلسل مع نمو المشاريع والمستخلصات.
--    إضافة فقط، لا تغيير في البيانات.
--  يُشغَّل بعد 20261105000013_rls_initplan.sql. إعادة تشغيله آمنة.
-- =====================================================================

create index if not exists app_settings_updated_by_idx        on public.app_settings (updated_by);
create index if not exists change_requests_decided_by_idx     on public.change_requests (decided_by);
create index if not exists change_requests_form_key_idx       on public.change_requests (form_key);
create index if not exists change_requests_requested_by_idx   on public.change_requests (requested_by);
create index if not exists contract_engineers_created_by_idx  on public.contract_engineers (created_by);
create index if not exists contract_engineers_origin_idx      on public.contract_engineers (origin_project);
create index if not exists contract_engineers_work_idx        on public.contract_engineers (work_id);
create index if not exists contract_extracts_created_by_idx   on public.contract_extracts (created_by);
create index if not exists contract_extracts_origin_idx       on public.contract_extracts (origin_project);
create index if not exists contract_extracts_updated_by_idx   on public.contract_extracts (updated_by);
create index if not exists contract_extracts_work_idx         on public.contract_extracts (work_id);
create index if not exists contract_variations_created_by_idx on public.contract_variations (created_by);
create index if not exists contract_variations_origin_idx     on public.contract_variations (origin_project);
create index if not exists contract_variations_work_idx       on public.contract_variations (work_id);
create index if not exists contract_works_created_by_idx      on public.contract_works (created_by);
create index if not exists contract_works_origin_idx          on public.contract_works (origin_project);
create index if not exists extract_payments_created_by_idx    on public.extract_payments (created_by);
create index if not exists form_defs_stage_idx                on public.form_defs (stage);
create index if not exists ideas_created_by_idx               on public.ideas (created_by);
create index if not exists profiles_activated_by_idx          on public.profiles (activated_by);
create index if not exists profiles_department_idx            on public.profiles (department);
create index if not exists profiles_locked_by_idx             on public.profiles (locked_by);
create index if not exists project_forms_approved_by_idx      on public.project_forms (approved_by);
create index if not exists project_forms_form_key_idx         on public.project_forms (form_key);
create index if not exists project_forms_updated_by_idx       on public.project_forms (updated_by);
create index if not exists projects_created_by_idx            on public.projects (created_by);
create index if not exists projects_department_idx            on public.projects (department);
create index if not exists projects_updated_by_idx            on public.projects (updated_by);
create index if not exists quality_notes_author_idx           on public.quality_notes (author);
create index if not exists user_devices_blocked_by_idx        on public.user_devices (blocked_by);
