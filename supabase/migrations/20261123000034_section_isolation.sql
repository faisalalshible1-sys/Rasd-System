-- =====================================================================
--  الترحيل 34: عزل الأقسام — كل قسم يطّلع على عمله وحده
--   القاعدة: المدير وموظفو مكتبه يطّلعون على كل الأقسام للمتابعة، وكل مستخدم آخر يرى قسمه وتفرّعه فقط:
--     مكتب العقود         : الدورة المستندية (وكل بيانات العقود)
--     رئيس الشؤون الفنية  : الشؤون الفنية
--     رئيس الإشراف        : الإشراف، وتفاصيل العقود التي يشرف عليها قسمه
--     رئيس الترميم        : الترميم والمباني التاريخية، والإشراف على عقود قسمه
--     رئيس المطابقة       : المطابقة والاستلام
--     التخطيط وضمان الجودة: مكتب التخطيط وضمان الجودة
--     عضو وحدة            : وحدته وحدها (لا وحدات القسم الأخرى)
--     الصلاحيات الدقيقة   : تضيف قسمها (مقايسات ومراسلات وتصاميم وبرامج ← الشؤون الفنية، تقارير ومتابعة ← الإشراف…)
--     مسؤول الأمن (CISO)  : الأمن السيبراني وحده
--   ويبقى للجميع: المراسلات الداخلية، ودليل الاستخدام، والطباعة والتصدير (لبيانات أقسامهم)، والأفكار والتطوير.
--   أساسيات العقود (الرقم والاسم والشركة والجهة والقسم) متاحة للربط عبر project_refs() دون المالية والتفاصيل.
--   نماذج الدورة المسندة لقسم (مثل «نطاق وطريقة عمل» للشؤون الفنية) يراها ويحدّثها من قسمه.
--   كل ذلك في سياسات القراءة (RLS) نفسها، لا في الواجهة وحدها، ومعه تشديد الكتابة بالمثل.
--  يُشغَّل بعد 20261122000033_boq_cascade_ideas_layout.sql. إعادة تشغيله آمنة.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. نطاق المستخدم الحالي
-- ---------------------------------------------------------------------

-- المدير وموظفو مكتبه: كل الأقسام للمتابعة
create or replace function public.full_view()
returns boolean
language sql stable security definer set search_path = public
as $$
  select coalesce(public.my_role()::text, '') in ('director', 'office_staff')
$$;

-- من يطّلع على كل العقود بتفاصيلها: المدير وموظفو مكتبه ومكتب العقود
create or replace function public.project_full_all()
returns boolean
language sql stable security definer set search_path = public
as $$
  select coalesce(public.my_role()::text, '') in ('director', 'office_staff', 'contracts')
$$;

-- العقود التي يشرف عليها قسم رئيس القسم الحالي (الإشراف أو الترميم)
create or replace function public.my_supervised()
returns uuid[]
language sql stable security definer set search_path = public
as $$
  select coalesce(array_agg(p.id order by p.id), '{}'::uuid[])
    from public.projects p
    join public.profiles me on me.id = auth.uid()
    join public.departments d on d.key = p.department and d.can_supervise
   where coalesce(public.my_role()::text, '') = 'dept_head' and me.department is not null and me.department = p.department
$$;

create or replace function public.supervises(p_project uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
  select p_project is not null and p_project = any (public.my_supervised())
$$;

-- قسم الشاشة الرئيسية لوحدة (قسم الشؤون الفنية مفتاحه في الواجهة docs)
create or replace function public.unit_app_section(p_unit text)
returns text
language sql stable security definer set search_path = public
as $$
  select case section when 'technical' then 'docs' else section end from public.org_units where key = p_unit
$$;

-- الوحدات التي يطّلع على سجلاتها: وحدته، ورئيس القسم وحدات قسمه، ومكتب التخطيط وحداته، ومن مُنح نوع سجل
create or replace function public.my_units()
returns text[]
language plpgsql stable security definer set search_path = public
as $$
declare
  r  text := coalesce(public.my_role()::text, '');
  me public.profiles;
  u  text[] := '{}';
begin
  if r in ('', 'security_auditor') then
    return '{}';
  end if;
  if r in ('director', 'office_staff') then
    return array(select key from public.org_units order by key);
  end if;
  select * into me from public.profiles where id = auth.uid();
  if me.unit is not null then
    u := u || me.unit;
  end if;
  if r = 'dept_head' then
    u := u || array(select key from public.org_units
                     where section = case me.department when 'restoration' then 'heritage' when 'acceptance' then 'acceptance'
                                                        when 'technical' then 'technical' else '-' end);
  elsif r = 'planning_qa' then
    u := u || array(select key from public.org_units where section = 'planning_qa');
  end if;
  u := u || array(select public.unit_kind_spec(substr(g.scope, 6)) ->> 'unit'
                    from public.user_grants g where g.user_id = me.id and g.scope like 'unit:%');
  return array(select distinct x from unnest(u) x where x is not null order by x);
end;
$$;

-- نماذج الدورة المسندة إليه في كل العقود (نماذج الإشراف تتبع العقود التي يشرف عليها، لا هذه القائمة)
create or replace function public.my_forms()
returns text[]
language sql stable security definer set search_path = public
as $$
  select coalesce(array_agg(d.key order by d.sort), '{}'::text[])
    from public.form_defs d
    cross join (select coalesce(public.my_role()::text, '') as role) r
    join public.profiles me on me.id = auth.uid()
   where r.role not in ('', 'security_auditor') and (
         r.role in ('director', 'office_staff')
      or (r.role = 'contracts' and 'contracts' = any (d.responsible))
      or (r.role = 'planning_qa' and 'planning_qa' = any (d.responsible))
      or (r.role = 'dept_head' and me.department = 'technical' and 'head:technical' = any (d.responsible))
      or (r.role = 'dept_head' and me.department = 'acceptance' and 'head:acceptance' = any (d.responsible))
      or exists (select 1 from public.user_grants g where g.user_id = me.id and g.scope = 'form:' || d.key))
$$;

-- أقسام الشاشة الرئيسية التي يراها
create or replace function public.my_sections()
returns text[]
language plpgsql stable security definer set search_path = public
as $$
declare
  r  text := coalesce(public.my_role()::text, '');
  me public.profiles;
  s  text[] := '{}';
  g  text;
begin
  if r = '' then
    return '{}';
  end if;
  select * into me from public.profiles where id = auth.uid();
  if r in ('director', 'office_staff') then
    s := array['cycle', 'risks', 'swot', 'docs', 'supervision', 'heritage', 'planning_qa', 'safety', 'acceptance'];
  elsif r = 'contracts' then
    s := array['cycle'];
  elsif r = 'planning_qa' then
    s := array['planning_qa'];
  elsif r = 'dept_head' then
    s := case me.department
           when 'technical'   then array['docs']
           when 'supervision' then array['supervision']
           when 'restoration' then array['heritage', 'supervision']
           when 'acceptance'  then array['acceptance']
           else '{}'::text[]
         end;
  end if;
  if r <> 'security_auditor' then
    s := s || array(select public.unit_app_section(x) from unnest(public.my_units()) x);
    for g in select scope from public.user_grants where user_id = me.id loop
      s := s || case
                  when g like 'docs:%' or g = 'pm:plan' then 'docs'
                  when g in ('supervision:reports', 'pm:track') then 'supervision'
                  when g = 'swot' then 'swot'
                  else null
                end;
    end loop;
  end if;
  if public.can_audit() then
    s := s || 'security'::text;
  end if;
  s := s || array['chat', 'manual', 'print'];
  return array(select distinct x from unnest(s) x where x is not null order by x);
end;
$$;

create or replace function public.sees_section(p_section text)
returns boolean
language sql stable security definer set search_path = public
as $$
  select p_section is not null and p_section = any (public.my_sections())
$$;

-- أسماء القسم كما تُكتب في «القسم المسؤول» عن إجراءات خطة SWOT (لرئيس القسم)
create or replace function public.my_swot_departments()
returns text[]
language sql stable security definer set search_path = public
as $$
  select case when coalesce(public.my_role()::text, '') = 'dept_head' then
           array['جميع الأقسام'] || coalesce((select array['قسم ' || d.name, d.name]
                                                  from public.profiles me join public.departments d on d.key = me.department
                                                 where me.id = auth.uid()), '{}'::text[])
         else '{}'::text[] end
$$;

-- نطاق المستخدم للواجهة في استدعاء واحد
create or replace function public.my_scope()
returns jsonb
language sql stable security definer set search_path = public
as $$
  select jsonb_build_object(
    'sections',   to_jsonb(public.my_sections()),
    'units',      to_jsonb(public.my_units()),
    'forms',      to_jsonb(public.my_forms()),
    'supervised', to_jsonb(public.my_supervised()),
    'full',       public.full_view(),
    'all_projects', public.project_full_all())
$$;

-- أساسيات كل العقود للربط (الاختيار والعرض بالاسم) دون المالية والتفاصيل
create or replace function public.project_refs()
returns jsonb
language sql stable security definer set search_path = public
as $$
  select case when coalesce(public.my_role()::text, '') in ('', 'security_auditor') then '[]'::jsonb
         else coalesce((select jsonb_agg(jsonb_build_object(
                  'id', p.id, 'assign_no', p.assign_no, 'code', p.code, 'name', p.name, 'owner', p.owner,
                  'company', p.company, 'department', p.department, 'contract_no', p.contract_no, 'sort_order', p.sort_order)
                  order by p.sort_order, p.name)
                from public.projects p where p.merged_into is null), '[]'::jsonb)
         end
$$;

-- ---------------------------------------------------------------------
-- 2. سياسات القراءة
-- ---------------------------------------------------------------------

-- العقود: تفاصيلها لمكتب المدير ومكتب العقود، ولرئيس القسم المشرف على عقوده
drop policy if exists projects_read on public.projects;
create policy projects_read on public.projects for select to authenticated
  using (merged_into is null and ((select public.project_full_all()) or id = any ((select public.my_supervised())::uuid[])));

-- حالات النماذج: كلها لمن يرى العقد، والنماذج المسندة إليه في كل العقود
drop policy if exists project_forms_read on public.project_forms;
create policy project_forms_read on public.project_forms for select to authenticated
  using ((select public.project_full_all()) or project_id = any ((select public.my_supervised())::uuid[])
         or form_key = any ((select public.my_forms())::text[]));

-- طلبات اعتماد الحالات: لمن يرى العقد، ولصاحب الطلب
drop policy if exists change_requests_read on public.change_requests;
create policy change_requests_read on public.change_requests for select to authenticated
  using ((select public.project_full_all()) or project_id = any ((select public.my_supervised())::uuid[])
         or requested_by = (select auth.uid()));

-- مالية العقد وسجلاته
drop policy if exists contract_extracts_read on public.contract_extracts;
create policy contract_extracts_read on public.contract_extracts for select to authenticated
  using ((select public.project_full_all()) or project_id = any ((select public.my_supervised())::uuid[]));
drop policy if exists contract_variations_read on public.contract_variations;
create policy contract_variations_read on public.contract_variations for select to authenticated
  using ((select public.project_full_all()) or project_id = any ((select public.my_supervised())::uuid[]));
drop policy if exists extract_payments_read on public.extract_payments;
create policy extract_payments_read on public.extract_payments for select to authenticated
  using ((select public.project_full_all()) or project_id = any ((select public.my_supervised())::uuid[]));

-- أعمال العقد: وللشؤون الفنية (تُعدّ منها المقايسات والبرامج)
drop policy if exists contract_works_read on public.contract_works;
create policy contract_works_read on public.contract_works for select to authenticated
  using ((select public.project_full_all()) or project_id = any ((select public.my_supervised())::uuid[])
         or (select public.sees_section('docs')));

-- المهندسون المكلّفون: ولمن أُسند إليه نموذج تكليفهم
drop policy if exists contract_engineers_read on public.contract_engineers;
create policy contract_engineers_read on public.contract_engineers for select to authenticated
  using ((select public.project_full_all()) or project_id = any ((select public.my_supervised())::uuid[])
         or public.engineer_form(kind) = any ((select public.my_forms())::text[]));

-- ملاحظات التقييم والجودة: ولمكتب التخطيط وضمان الجودة الذي يكتبها
drop policy if exists quality_notes_read on public.quality_notes;
create policy quality_notes_read on public.quality_notes for select to authenticated
  using ((select public.project_full_all()) or project_id = any ((select public.my_supervised())::uuid[])
         or (select coalesce(public.my_role()::text, '') = 'planning_qa'));

-- متابعة المشاريع: لمن يرى العقد بتفاصيله
drop policy if exists pm_projects_read on public.pm_projects;
create policy pm_projects_read on public.pm_projects for select to authenticated
  using ((select public.project_full_all()) or project_id = any ((select public.my_supervised())::uuid[]));
drop policy if exists pm_progress_read on public.pm_progress;
create policy pm_progress_read on public.pm_progress for select to authenticated
  using ((select public.project_full_all()) or project_id = any ((select public.my_supervised())::uuid[]));
drop policy if exists pm_issues_read on public.pm_issues;
create policy pm_issues_read on public.pm_issues for select to authenticated
  using ((select public.project_full_all()) or project_id = any ((select public.my_supervised())::uuid[]));
drop policy if exists pm_delays_read on public.pm_delays;
create policy pm_delays_read on public.pm_delays for select to authenticated
  using ((select public.project_full_all()) or project_id = any ((select public.my_supervised())::uuid[]));
drop policy if exists pm_changes_read on public.pm_changes;
create policy pm_changes_read on public.pm_changes for select to authenticated
  using ((select public.project_full_all()) or project_id = any ((select public.my_supervised())::uuid[]));
drop policy if exists pm_evaluations_read on public.pm_evaluations;
create policy pm_evaluations_read on public.pm_evaluations for select to authenticated
  using ((select public.project_full_all()) or project_id = any ((select public.my_supervised())::uuid[]));
drop policy if exists pm_lessons_read on public.pm_lessons;
create policy pm_lessons_read on public.pm_lessons for select to authenticated
  using ((select public.full_view()) or (project_id is not null
         and ((select public.project_full_all()) or project_id = any ((select public.my_supervised())::uuid[]))));

-- البرنامج الزمني ومراحله وبنوده: وللشؤون الفنية التي تعدّه، ولمن مُنح متابعته
drop policy if exists pm_plans_read on public.pm_plans;
create policy pm_plans_read on public.pm_plans for select to authenticated
  using ((select public.project_full_all()) or project_id = any ((select public.my_supervised())::uuid[])
         or (select public.sees_section('docs')) or (select public.has_grant('pm:track')));
drop policy if exists pm_phases_read on public.pm_phases;
create policy pm_phases_read on public.pm_phases for select to authenticated
  using ((select public.project_full_all()) or project_id = any ((select public.my_supervised())::uuid[])
         or (select public.sees_section('docs')) or (select public.has_grant('pm:track')));
drop policy if exists pm_items_read on public.pm_items;
create policy pm_items_read on public.pm_items for select to authenticated
  using ((select public.project_full_all()) or project_id = any ((select public.my_supervised())::uuid[])
         or (select public.sees_section('docs')) or (select public.has_grant('pm:track')));

-- المقايسات المعدّة ولائحة الأسعار: الشؤون الفنية، والمقايسات المعتمدة لعقود القسم المشرف
drop policy if exists boq_sheets_read on public.boq_sheets;
create policy boq_sheets_read on public.boq_sheets for select to authenticated
  using ((select public.sees_section('docs')) or (project_id is not null and project_id = any ((select public.my_supervised())::uuid[])));
drop policy if exists price_lists_read on public.price_lists;
create policy price_lists_read on public.price_lists for select to authenticated
  using ((select public.sees_section('docs')));
drop policy if exists price_items_read on public.price_items;
create policy price_items_read on public.price_items for select to authenticated
  using ((select public.sees_section('docs')));

-- مستندات الشؤون الفنية: لها، ولعقود القسم المشرف
drop policy if exists doc_items_read on public.doc_items;
create policy doc_items_read on public.doc_items for select to authenticated
  using ((select public.sees_section('docs')) or (project_id is not null and project_id = any ((select public.my_supervised())::uuid[])));
drop policy if exists doc_revisions_read on public.doc_revisions;
create policy doc_revisions_read on public.doc_revisions for select to authenticated
  using ((select public.sees_section('docs')) or exists (select 1 from public.doc_items i where i.id = doc_revisions.item_id));

-- التقارير اليومية: الإشراف على عقوده، ومن مُنح كتابتها، ومكتب المدير
drop policy if exists site_reports_read on public.site_reports;
create policy site_reports_read on public.site_reports for select to authenticated
  using ((select public.full_view()) or project_id = any ((select public.my_supervised())::uuid[])
         or (select public.has_grant('supervision:reports')) or created_by = (select auth.uid()));

-- سجلات الوحدات: وحداته وحدها
drop policy if exists unit_records_read on public.unit_records;
create policy unit_records_read on public.unit_records for select to authenticated
  using (unit = any ((select public.my_units())::text[]));

-- الملفات: تتبع صاحبها (مراجعة مستند، أو تقرير يومي، أو سجل وحدة) بسياسة قراءته
drop policy if exists doc_files_read on public.doc_files;
create policy doc_files_read on public.doc_files for select to authenticated
  using ((select public.full_view())
         or (revision_id is not null and exists (select 1 from public.doc_revisions r where r.id = doc_files.revision_id))
         or (report_id is not null and exists (select 1 from public.site_reports s where s.id = doc_files.report_id))
         or (record_id is not null and exists (select 1 from public.unit_records u where u.id = doc_files.record_id)));

-- المخاطر: قسم المخاطر، ومخاطر العقد لمن يرى العقد بتفاصيله
drop policy if exists risks_read on public.risks;
create policy risks_read on public.risks for select to authenticated
  using ((select public.sees_section('risks'))
         or (project_id is not null and ((select public.project_full_all()) or project_id = any ((select public.my_supervised())::uuid[]))));
drop policy if exists risk_reviews_read on public.risk_reviews;
create policy risk_reviews_read on public.risk_reviews for select to authenticated
  using ((select public.sees_section('risks')) or exists (select 1 from public.risks r where r.id = risk_reviews.risk_id));

-- تحليل SWOT: لقسمه، وإجراءات الخطة المسندة إلى قسم رئيسه
drop policy if exists swot_factors_read on public.swot_factors;
create policy swot_factors_read on public.swot_factors for select to authenticated
  using ((select public.sees_section('swot')));
drop policy if exists swot_strategies_read on public.swot_strategies;
create policy swot_strategies_read on public.swot_strategies for select to authenticated
  using ((select public.sees_section('swot')));
drop policy if exists swot_actions_read on public.swot_actions;
create policy swot_actions_read on public.swot_actions for select to authenticated
  using ((select public.sees_section('swot')) or department = any ((select public.my_swot_departments())::text[]));

-- الأفكار: العامة لمكتب المدير، وأفكار كل قسم لمن يراه، وأفكار المستخدم نفسه
drop policy if exists ideas_read on public.ideas;
create policy ideas_read on public.ideas for select to authenticated
  using ((select public.full_view()) or created_by = (select auth.uid())
         or (section is not null and section = any ((select public.my_sections())::text[])));

-- سجل التدقيق: كاملاً للمدير وCISO، وسجل العقد لمن يرى العقد، وأفعال المستخدم نفسه
drop policy if exists audit_read on public.audit_log;
create policy audit_read on public.audit_log for select to authenticated
  using ((select public.can_audit()) or (select public.full_view()) or actor = (select auth.uid())
         or (project_id is not null and ((select public.project_full_all()) or project_id = any ((select public.my_supervised())::uuid[]))));

-- سجل الأرقام الإشارية: لمكتب المدير، ولصاحب الرقم
drop policy if exists ref_log_read on public.ref_log;
create policy ref_log_read on public.ref_log for select to authenticated
  using ((select public.full_view()) or created_by = (select auth.uid()));

-- ---------------------------------------------------------------------
-- 3. الملفات المخزّنة ونسخ PDF المحفوظة
-- ---------------------------------------------------------------------

-- قسم المصدر الذي استُخرجت منه النسخة (مفتاح «الطباعة والتصدير»)
create or replace function public.export_source_section(p_source text)
returns text
language sql stable security definer set search_path = public
as $$
  select case
    when p_source like 'cycle:%' then 'cycle'
    when p_source like 'risks:%' then 'risks'
    when p_source like 'swot:%' then 'swot'
    when p_source like 'docs:%' then 'docs'
    when p_source like 'supervision:%' then 'supervision'
    when p_source like 'unit:%' then public.unit_app_section(public.unit_kind_spec(substr(p_source, 6)) ->> 'unit')
  end
$$;

-- «كل أعضاء المنظومة» صارت: من يرى قسم المصدر (ومكتب المدير دائماً)
create or replace function public.export_can_open(p_access text, p_owner uuid, p_source text)
returns boolean
language sql stable security definer set search_path = public
as $$
  select public.is_member() and (
    p_owner = auth.uid()
    or public.is_director()
    or (p_access = 'members' and (public.full_view() or public.sees_section(public.export_source_section(p_source))))
    or (p_access = 'people' and coalesce(public.my_role()::text, '') = 'security_auditor'))
$$;

-- الصيغة القديمة (دون المصدر): مكتب المدير وحده لنسخ «الأعضاء»
create or replace function public.export_can_open(p_access text, p_owner uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
  select public.export_can_open(p_access, p_owner, '')
$$;

create or replace function public.export_can_open_path(p_path text)
returns boolean
language sql stable security definer set search_path = public
as $$
  select exists (select 1 from public.export_files f where f.path = p_path and public.export_can_open(f.access, f.created_by, f.source))
$$;

create or replace function public.open_export_file(p_token text)
returns jsonb
language plpgsql security definer set search_path = public
as $$
declare
  f public.export_files;
begin
  if not public.is_member() then
    raise exception 'سجّل الدخول بحساب مفعّل في المنظومة لفتح المستند' using errcode = '42501';
  end if;
  -- الرفض يُعاد نتيجةً (لا استثناءً) ليبقى مسجّلاً في سجل التدقيق
  select * into f from public.export_files where token = btrim(coalesce(p_token, ''));
  if not found then
    perform public.write_audit('export.unknown', null, null, jsonb_build_object('token', left(coalesce(p_token, ''), 40)), 'عام');
    return jsonb_build_object('ok', false, 'reason', 'unknown');
  end if;
  if not public.export_can_open(f.access, f.created_by, f.source) then
    perform public.write_audit('export.denied', f.project_id, null,
      jsonb_build_object('title', f.title, 'ref_no', f.ref_no, 'access', f.access, 'source', f.source),
      coalesce(public.project_label(f.project_id), 'عام'));
    return jsonb_build_object('ok', false, 'reason', 'denied', 'title', f.title, 'access', f.access);
  end if;
  perform public.write_audit('export.open', f.project_id, null,
    jsonb_build_object('title', f.title, 'ref_no', f.ref_no, 'access', f.access), coalesce(public.project_label(f.project_id), 'عام'));
  return jsonb_build_object('ok', true, 'path', f.path, 'title', f.title, 'ref_no', f.ref_no, 'created_at', f.created_at,
                            'created_by', public.actor_name(f.created_by), 'sha256', f.sha256, 'bytes', f.bytes,
                            'pages', f.pages, 'access', f.access);
end;
$$;

-- ملفات المستندات والتقارير والسجلات: لمن يقرأ صاحبها (أو رافعها قبل تسجيله)، ونسخة الدليل PDF للجميع
do $$
begin
  if to_regclass('storage.objects') is null then
    return;
  end if;
  drop policy if exists docs_read on storage.objects;
  create policy docs_read on storage.objects for select to authenticated
    using (bucket_id = 'docs' and (select public.is_member())
           and (name like 'manual/%' or owner_id = (select auth.uid())::text or owner = (select auth.uid())
                or exists (select 1 from public.doc_files f where f.path = objects.name)));
end $$;

-- ---------------------------------------------------------------------
-- 4. تشديد الكتابة بالمثل
-- ---------------------------------------------------------------------

-- مستندات الشؤون الفنية يكتبها من يرى قسمها
create or replace function public.doc_can_edit(p_kind text, p_project uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
  select public.sees_section('docs') and (
    coalesce(public.doc_can_edit_v22(p_kind, p_project), false)
    or (public.writes_allowed() and p_kind in ('boq', 'letter', 'design') and public.has_grant('docs:' || p_kind)
        and (p_project is null or exists (select 1 from public.projects where id = p_project and merged_into is null))))
$$;

-- المخاطر ومتابعة المشاريع: مكتب المدير ومكتب العقود، ورئيس القسم المشرف لعقوده (يُتحقق من العقد في كل سجل)
create or replace function public.can_edit_risks()
returns boolean
language sql stable security definer set search_path = public
as $$
  select public.writes_allowed() and (public.project_full_all() or cardinality(public.my_supervised()) > 0)
$$;

create or replace function public.pm_row_ok(p_project uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
  select case when p_project is null then public.full_view()
              else public.project_full_all() or p_project = any (public.my_supervised()) end
$$;

-- حارس كل سجل: لا يكتب مستخدم في متابعة عقد لا يراه (التحديث الآلي من البرنامج المعتمد وأعمال الخادم مستثناة)
create or replace function public.pm_guard_project()
returns trigger
language plpgsql security definer set search_path = public
as $$
begin
  if auth.uid() is null or coalesce(current_setting('role', true), 'none') not in ('authenticated', 'anon')
     or coalesce(current_setting('rasd.auto_sync', true), '') = 'on' then
    return coalesce(new, old);
  end if;
  if tg_op in ('UPDATE', 'DELETE') and not public.pm_row_ok(old.project_id) then
    raise exception 'هذا السجل لعقد خارج نطاق قسمك' using errcode = '42501';
  end if;
  if tg_op in ('INSERT', 'UPDATE') and not public.pm_row_ok(new.project_id) then
    raise exception 'لا تملك صلاحية التسجيل على هذا العقد من قسمك' using errcode = '42501';
  end if;
  return coalesce(new, old);
end;
$$;

create or replace function public.pm_guard_review()
returns trigger
language plpgsql security definer set search_path = public
as $$
declare
  v uuid;
begin
  if auth.uid() is null or coalesce(current_setting('role', true), 'none') not in ('authenticated', 'anon')
     or coalesce(current_setting('rasd.auto_sync', true), '') = 'on' then
    return coalesce(new, old);
  end if;
  select project_id into v from public.risks where id = coalesce(new.risk_id, old.risk_id);
  if not public.pm_row_ok(v) then
    raise exception 'هذا الخطر خارج نطاق قسمك' using errcode = '42501';
  end if;
  return coalesce(new, old);
end;
$$;

do $$
declare
  t text;
begin
  foreach t in array array['risks', 'pm_projects', 'pm_progress', 'pm_issues', 'pm_delays', 'pm_changes', 'pm_evaluations', 'pm_lessons'] loop
    execute format('drop trigger if exists %I on public.%I', t || '_scope_guard', t);
    execute format('create trigger %I before insert or update or delete on public.%I for each row execute function public.pm_guard_project()',
                   t || '_scope_guard', t);
  end loop;
  drop trigger if exists risk_reviews_scope_guard on public.risk_reviews;
  create trigger risk_reviews_scope_guard before insert or update or delete on public.risk_reviews
    for each row execute function public.pm_guard_review();
end $$;

-- ترجمة البرنامج المعتمد إلى المخاطر وSWOT تعمل لكل العقود أياً كان من فتح المنظومة
do $$
begin
  if not exists (select 1 from pg_proc where proname = 'pm_sync_auto_v34' and pronamespace = 'public'::regnamespace) then
    alter function public.pm_sync_auto(uuid) rename to pm_sync_auto_v34;
  end if;
end $$;

create or replace function public.pm_sync_auto(p_project uuid)
returns jsonb
language plpgsql security definer set search_path = public
as $$
declare
  v_prev text := coalesce(current_setting('rasd.auto_sync', true), '');
  r      jsonb;
begin
  perform set_config('rasd.auto_sync', 'on', true);
  r := public.pm_sync_auto_v34(p_project);
  perform set_config('rasd.auto_sync', v_prev, true);
  return r;
end;
$$;

-- الأفكار تُرسل إلى أقسام المستخدم وحدها (أو عامة)
do $$
begin
  if not exists (select 1 from pg_proc where proname = 'submit_idea_v34' and pronamespace = 'public'::regnamespace) then
    alter function public.submit_idea(text, text, text, text, text, integer, text) rename to submit_idea_v34;
  end if;
end $$;

create or replace function public.submit_idea(p_title text, p_body text, p_category text, p_priority text,
                                              p_section text default null, p_page integer default null,
                                              p_page_label text default null)
returns uuid
language plpgsql security definer set search_path = public
as $$
begin
  if p_section is not null and public.is_member() and not public.full_view() and not public.sees_section(p_section) then
    raise exception 'تُرسل الفكرة إلى قسمك أو عامةً للمنظومة' using errcode = '42501';
  end if;
  return public.submit_idea_v34(p_title, p_body, p_category, p_priority, p_section, p_page, p_page_label);
end;
$$;

-- ---------------------------------------------------------------------
-- 5. دوال القراءة الخاصة بحدود القسم نفسها
-- ---------------------------------------------------------------------

-- سجل المالية من سجل التدقيق: لمن يرى العقد بتفاصيله (ومكتب المدير وCISO)
create or replace function public.finance_history(p_project uuid default null, p_limit integer default 300)
returns setof jsonb
language sql stable security definer set search_path = public
as $$
  select to_jsonb(a)
    from public.audit_log a
   where public.is_member()
     and (p_project is null or a.project_id = p_project)
     and (a.action like 'finance.%'
          or a.action in ('contract.merge', 'contract.unmerge')
          or (a.action = 'project.update' and a.detail ?| array['contract_value', 'executed_value', 'payment_first',
                                                                'payment_second', 'payment_final', 'deductions'])
          or (a.action = 'setting.update' and a.detail ->> 'key' like 'finance.%'))
     and (public.can_audit()
          or (a.project_id is not null and (public.project_full_all() or a.project_id = any (public.my_supervised())))
          or (a.project_id is null and a.action = 'setting.update' and public.project_full_all()))
   order by a.at desc
   limit least(greatest(coalesce(p_limit, 300), 1), 2000)
$$;

-- العقود المدمجة في عقد: لمن يرى العقد الهدف بتفاصيله
create or replace function public.merged_sources(p_target uuid)
returns setof jsonb
language sql stable security definer set search_path = public
as $$
  select jsonb_build_object('id', p.id, 'assign_no', p.assign_no, 'contract_no', p.contract_no, 'name', p.name,
                            'company', p.company, 'merged_at', p.merged_at)
    from public.projects p
   where p.merged_into = p_target and public.is_member()
     and (public.project_full_all() or p_target = any (public.my_supervised()))
   order by p.merged_at, p.sort_order
$$;

-- معاينة توليد البرنامج الزمني (بنود المقايسة وتكلفتها): للشؤون الفنية ومكتب المدير ومكتب العقود
do $$
begin
  if not exists (select 1 from pg_proc where proname = 'pm_plan_preview_v34' and pronamespace = 'public'::regnamespace) then
    alter function public.pm_plan_preview(uuid, integer) rename to pm_plan_preview_v34;
  end if;
end $$;

create or replace function public.pm_plan_preview(p_project uuid, p_total_days integer)
returns jsonb
language plpgsql stable security definer set search_path = public
as $$
begin
  if public.is_member() and not (public.sees_section('docs') or public.project_full_all()) then
    raise exception 'معاينة البرنامج الزمني لقسم الشؤون الفنية' using errcode = '42501';
  end if;
  return public.pm_plan_preview_v34(p_project, p_total_days);
end;
$$;

-- ---------------------------------------------------------------------
-- 6. الصلاحيات على الدوال
-- ---------------------------------------------------------------------
revoke execute on function
  public.pm_sync_auto_v34(uuid), public.pm_sync_auto(uuid), public.submit_idea_v34(text, text, text, text, text, integer, text),
  public.pm_plan_preview_v34(uuid, integer), public.pm_guard_project(), public.pm_guard_review()
from public, anon, authenticated;
revoke execute on function
  public.full_view(), public.project_full_all(), public.my_supervised(), public.supervises(uuid), public.unit_app_section(text),
  public.my_units(), public.my_forms(), public.my_sections(), public.sees_section(text), public.my_swot_departments(),
  public.my_scope(), public.project_refs(),
  public.export_source_section(text), public.export_can_open(text, uuid, text), public.export_can_open(text, uuid),
  public.export_can_open_path(text), public.open_export_file(text), public.doc_can_edit(text, uuid), public.can_edit_risks(),
  public.pm_row_ok(uuid), public.submit_idea(text, text, text, text, text, integer, text),
  public.finance_history(uuid, integer), public.merged_sources(uuid), public.pm_plan_preview(uuid, integer)
from public, anon;
grant execute on function
  public.full_view(), public.project_full_all(), public.my_supervised(), public.supervises(uuid), public.unit_app_section(text),
  public.my_units(), public.my_forms(), public.my_sections(), public.sees_section(text), public.my_swot_departments(),
  public.my_scope(), public.project_refs(),
  public.export_source_section(text), public.export_can_open(text, uuid, text), public.export_can_open(text, uuid),
  public.export_can_open_path(text), public.open_export_file(text), public.doc_can_edit(text, uuid), public.can_edit_risks(),
  public.pm_row_ok(uuid), public.submit_idea(text, text, text, text, text, integer, text),
  public.finance_history(uuid, integer), public.merged_sources(uuid), public.pm_plan_preview(uuid, integer)
to authenticated;
