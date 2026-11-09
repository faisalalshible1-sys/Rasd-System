-- اختبارات سجل المخاطر وتحليل SWOT.
-- تُشغَّل بعد 70_finance_v5_test.sql على القاعدة نفسها.
\set ON_ERROR_STOP 1
\set QUIET 1
\pset tuples_only on
\pset format unaligned

create or replace function pg_temp.as_user(p_email text, p_aal text default 'aal1') returns void language plpgsql security definer as $$
declare v uuid := (select id from auth.users where email = p_email);
begin
  perform set_config('request.jwt.claim.sub', coalesce(v::text, ''), false);
  perform set_config('request.jwt.claims', jsonb_build_object('sub', v, 'aal', p_aal, 'session_id', '00000000-0000-0000-0000-000000000001')::text, false);
end $$;
create or replace function pg_temp.expect_error(p_sql text, p_label text) returns void language plpgsql as $$
begin
  begin
    execute p_sql;
  exception when others then
    raise notice 'PASS (رُفض كما يجب): % — %', p_label, sqlerrm;
    return;
  end;
  raise exception 'FAIL: كان يجب رفض: %', p_label;
end $$;
create or replace function pg_temp.check(p_ok boolean, p_label text) returns void language plpgsql as $$
begin
  if not coalesce(p_ok, false) then raise exception 'FAIL: %', p_label; end if;
  raise notice 'PASS: %', p_label;
end $$;
create or replace function pg_temp.risk(p_code text) returns public.risks language sql security definer as $$
  select * from public.risks where code = p_code
$$;
create or replace function pg_temp.audits(p_action text, p_label text) returns bigint language sql security definer as $$
  select count(*) from public.audit_log where action = p_action and project_label = p_label
$$;
create or replace function pg_temp.last_detail(p_action text, p_label text) returns jsonb language sql security definer as $$
  select detail from public.audit_log where action = p_action and project_label = p_label order by at desc limit 1
$$;
grant execute on all functions in schema pg_temp to authenticated, anon;

-- ---------------------------------------------------------------- البيانات الأولية
select pg_temp.check((select count(*) = 12 from public.risks), 'اثنا عشر خطراً من الملف');
select pg_temp.check((select count(*) = 43 from public.swot_factors) and (select count(*) = 10 from public.swot_factors where kind = 'S')
                     and (select count(*) = 11 from public.swot_factors where kind = 'T'), '43 عاملاً بتصنيفاتها');
select pg_temp.check((select count(*) = 21 from public.swot_strategies) and (select count(*) = 21 from public.swot_actions), '21 استراتيجية و21 إجراءً');
select pg_temp.check((select score = 20 and residual_score = 4 from pg_temp.risk('R01')), 'الدرجة = الاحتمالية × التأثير');
select pg_temp.check((select jsonb_array_length(value -> 'levels') = 5 and (value ->> 'alert_days')::int = 7 from public.app_settings where key = 'risk.config'),
                     'معايير المستويات وأيام التنبيه');
select pg_temp.check((select rating = 4 from public.swot_factors where code = 'S01') and (select rating = 1 from public.swot_factors where code = 'W01'),
                     'تقييمات IFE من الملف');
select pg_temp.check((select 'W09' = any (factors) and strategy_code = 'WO5' from public.swot_actions where code = 'A01'), 'ربط الإجراء بالاستراتيجية والعوامل');

-- ---------------------------------------------------------------- سجل المخاطر
set role authenticated;
select pg_temp.as_user('staff.new@test.ly');
select public.save_risk(null, '{"description": "تأخر اعتماد المخططات التنفيذية", "category": "تنسيق", "phase": "التنفيذ", "probability": 4, "impact": 3, "owner": "PMO", "next_review": "2026-12-01"}');
select pg_temp.check((select score = 12 and status = 'open' and created_by = auth.uid() from pg_temp.risk('R13')), 'خطر جديد برمز تلقائي R13');
select pg_temp.check(pg_temp.audits('risk.create', 'R13') = 1, 'تسجيل الإنشاء في سجل التدقيق');
select public.save_risk((select id from pg_temp.risk('R13')),
  '{"description": "تأخر اعتماد المخططات التنفيذية", "category": "تنسيق", "phase": "التنفيذ", "probability": 4, "impact": 3, "owner": "PMO", "status": "closed", "residual_probability": 1, "residual_impact": 2, "response": "mitigate"}');
select pg_temp.check((select status = 'closed' and closed_on = current_date and residual_score = 2 and response = 'mitigate' from pg_temp.risk('R13')),
                     'الإغلاق يسجل تاريخه');
select pg_temp.check((select (d -> 'changes') ? 'status' and not ((d -> 'changes') ? 'description') from pg_temp.last_detail('risk.update', 'R13') d),
                     'التدقيق يسجل الحقول المتغيرة فقط');
select public.save_risk((select id from pg_temp.risk('R13')),
  '{"description": "تأخر اعتماد المخططات التنفيذية", "probability": 4, "impact": 3, "status": "in_progress"}');
select pg_temp.check((select closed_on is null and residual_score is null from pg_temp.risk('R13')), 'إعادة الفتح تمسح تاريخ الإغلاق');
select pg_temp.expect_error($$select public.save_risk(null, '{"description": "خطر", "probability": 6, "impact": 3}')$$, 'احتمالية خارج 1–5');
select pg_temp.expect_error($$select public.save_risk(null, '{"description": "خطر بلا تأثير", "probability": 3}')$$, 'تأثير مفقود');
select pg_temp.expect_error($$select public.save_risk(null, '{"description": "خطر", "probability": 3, "impact": 3, "residual_probability": 2}')$$,
                            'تقييم متبقٍ ناقص');
select pg_temp.expect_error($$select public.save_risk(null, '{"code": "R01", "description": "رمز مكرر", "probability": 3, "impact": 3}')$$, 'رمز مكرر');
select pg_temp.expect_error($$select public.save_risk(null, '{"description": "خطر", "probability": 3, "impact": 3, "status": "done"}')$$, 'حالة غير معروفة');
select pg_temp.expect_error($$insert into public.risks (code, description, probability, impact) values ('R99', 'مباشر', 1, 1)$$, 'الكتابة المباشرة في الجدول');
select pg_temp.expect_error($$select public.delete_risk((select id from pg_temp.risk('R13')))$$, 'الموظف يحذف خطراً');

select pg_temp.as_user('k.contracts@test.ly');
select public.save_risk(null, jsonb_build_object('description', 'تأخر صرف المستخلصات', 'probability', 3, 'impact', 4,
                                                 'project_id', (select id from projects order by assign_no limit 1)));
select pg_temp.check((select project_id is not null and score = 12 from pg_temp.risk('R14')), 'ربط الخطر بعقد');

select pg_temp.as_user('auditor@test.ly', 'aal2');
select pg_temp.check((select count(*) >= 14 from public.risks), 'مدقق الأمن يقرأ السجل');
select pg_temp.expect_error($$select public.save_risk(null, '{"description": "من المدقق", "probability": 3, "impact": 3}')$$, 'مدقق الأمن يضيف خطراً');

select pg_temp.as_user('director.new@test.ly', 'aal2');
select public.delete_risk((select id from pg_temp.risk('R14')));
select pg_temp.check((select count(*) = 0 from public.risks where code = 'R14') and pg_temp.audits('risk.delete', 'R14') = 1, 'المدير يحذف خطراً');

-- معايير المستويات
select pg_temp.expect_error($$select public.set_setting('risk.config', '{"levels": [{"name": "أ", "min": 1}, {"name": "بب", "min": 9}, {"name": "جج", "min": 5}]}')$$,
                            'مستويات غير متصاعدة');
select pg_temp.expect_error($$select public.set_setting('risk.config', '{"levels": [{"name": "منخفض", "min": 2}, {"name": "متوسط", "min": 9}, {"name": "مرتفع", "min": 16}]}')$$,
                            'المستوى الأول لا يبدأ من 1');
select public.set_setting('risk.config', '{"levels": [{"name": "منخفض", "min": 1, "action": "مراقبة"}, {"name": "متوسط", "min": 6, "action": "خطة"}, {"name": "مرتفع", "min": 12, "action": "تصعيد"}, {"name": "حرج", "min": 20, "action": "عاجل"}], "alert_days": 10, "categories": ["فني", "مالي"]}');
select pg_temp.check((select (value ->> 'alert_days')::int = 10 from public.app_settings where key = 'risk.config'), 'حفظ معايير المخاطر');
select pg_temp.as_user('staff.new@test.ly');
select pg_temp.expect_error($$select public.set_setting('risk.config', '{"levels": []}')$$, 'الموظف يعدّل المعايير');

-- ---------------------------------------------------------------- تحليل SWOT
select public.save_swot_factor(null, '{"kind": "W", "factor": "نقص المهندسين المختصين في الترميم", "importance": 4, "urgency": 3, "department": "قسم الترميم", "rating": 2}');
select pg_temp.check((select priority = 12 and department = 'قسم الترميم' from public.swot_factors where code = 'W13'), 'عامل جديد برمز W13');
select pg_temp.expect_error($$select public.save_swot_factor(null, '{"kind": "W", "factor": "ضعف بتقييم قوة", "importance": 3, "urgency": 3, "rating": 3}')$$,
                            'تقييم IFE لنقطة ضعف');
select pg_temp.expect_error($$select public.save_swot_factor(null, '{"kind": "S", "code": "W30", "factor": "رمز لا يطابق التصنيف", "importance": 3, "urgency": 3}')$$,
                            'رمز لا يطابق التصنيف');
select public.save_swot_strategy(null, '{"kind": "WO", "strategy": "برنامج تأهيل لمهندسي الترميم بالشراكة مع الجامعات", "internal_factors": "W13، W08", "external_factors": ["O07"], "priority": "high", "lead_department": "قسم الترميم"}');
select pg_temp.check((select internal_factors = array['W13', 'W08'] and external_factors = array['O07'] from public.swot_strategies where code = 'WO7'),
                     'استراتيجية برمز WO7 وعوامل مرمّزة');
select pg_temp.expect_error($$select public.save_swot_strategy(null, '{"kind": "SO", "strategy": "عوامل خارجية في الداخلية", "internal_factors": ["O01"]}')$$,
                            'عامل خارجي في خانة الداخلية');
select public.save_swot_action(null, '{"strategy_code": "WO7", "factors": ["W13"], "action": "تنفيذ برنامج تأهيل لمهندسي الترميم", "department": "قسم الترميم", "start_date": "2027-01-01", "duration_months": 4, "priority": "high"}');
select pg_temp.check((select strategy_code = 'WO7' and status = 'not_started' and progress is null from public.swot_actions where code = 'A22'),
                     'إجراء جديد برمز A22');
-- تغيير رمز العامل يُحدَّث في الاستراتيجيات والإجراءات
select public.save_swot_factor((select id from public.swot_factors where code = 'W13'),
  '{"kind": "W", "code": "W14", "factor": "نقص المهندسين المختصين في الترميم", "importance": 4, "urgency": 3, "rating": 2}');
select pg_temp.check((select 'W14' = any (internal_factors) and not ('W13' = any (internal_factors)) from public.swot_strategies where code = 'WO7')
                     and (select factors = array['W14'] from public.swot_actions where code = 'A22'), 'إعادة الترميز تنتقل إلى الروابط');
select pg_temp.expect_error($$select public.delete_swot_strategy((select id from public.swot_strategies where code = 'WO7'))$$, 'الموظف يحذف استراتيجية');

-- المتابعة الدورية: رئيس القسم المسؤول فقط
select pg_temp.as_user('headsup@test.ly');
select public.update_swot_action((select id from public.swot_actions where code = 'A03'), '2026-12-01', 2, 'in_progress', 0.4, 'اعتُمد النموذج مبدئياً');
select pg_temp.check((select status = 'in_progress' and progress = 0.4 and notes = 'اعتُمد النموذج مبدئياً' from public.swot_actions where code = 'A03'),
                     'رئيس قسم الإشراف يحدّث إجراء قسمه');
select pg_temp.check(pg_temp.audits('swot.progress', 'A03') = 1, 'تسجيل التحديث في التدقيق');
select pg_temp.expect_error($$select public.update_swot_action((select id from public.swot_actions where code = 'A01'), null, 3, 'in_progress', 0.1, '')$$,
                            'رئيس قسم يحدّث إجراء الإدارة');
select pg_temp.expect_error($$select public.save_swot_factor(null, '{"kind": "S", "factor": "من رئيس القسم", "importance": 3, "urgency": 3}')$$,
                            'رئيس القسم يضيف عاملاً');
select pg_temp.expect_error($$select public.update_swot_action((select id from public.swot_actions where code = 'A03'), null, 2, 'in_progress', 1.4, '')$$,
                            'نسبة إنجاز أكبر من 100%');
select pg_temp.as_user('headtech@test.ly');
select pg_temp.expect_error($$select public.update_swot_action((select id from public.swot_actions where code = 'A03'), null, 2, 'completed', null, '')$$,
                            'رئيس قسم آخر يحدّث إجراء الإشراف');
select public.update_swot_action((select id from public.swot_actions where code = 'A02'), '2027-01-01', 6, 'completed', null, 'اكتمل');
select pg_temp.check((select progress = 1 from public.swot_actions where code = 'A02'), 'الاكتمال يجعل الإنجاز 100%');

select pg_temp.as_user('k.contracts@test.ly');
select pg_temp.expect_error($$select public.save_swot_action(null, '{"action": "من العقود", "strategy_code": "SO1"}')$$, 'مكتب العقود يضيف إجراءً');

select pg_temp.as_user('director.new@test.ly', 'aal2');
select pg_temp.expect_error($$select public.delete_swot_strategy((select id from public.swot_strategies where code = 'WO7'))$$, 'حذف استراتيجية لها إجراءات');
select public.delete_swot_action((select id from public.swot_actions where code = 'A22'));
select public.delete_swot_strategy((select id from public.swot_strategies where code = 'WO7'));
select public.delete_swot_factor((select id from public.swot_factors where code = 'W14'));
select pg_temp.check((select count(*) = 43 from public.swot_factors) and (select count(*) = 21 from public.swot_strategies)
                     and (select count(*) = 21 from public.swot_actions), 'المدير يحذف ما أُضيف');
select public.set_setting('swot.meta', '{"version": "2.1", "issue_date": "2026-12-01", "status": "معتمد", "review_cycle_months": 6}');
select pg_temp.expect_error($$select public.set_setting('swot.meta', '{"review_cycle_months": 40}')$$, 'دورة مراجعة غير معقولة');

-- ملخص المساعد
select pg_temp.check((select jsonb_array_length(c -> 'risks') = 13 and jsonb_array_length(c -> 'swot' -> 'actions') = 21
                             and (c -> 'finance_defaults') is not null from public.ai_context() c),
                     'ملخص Claude يشمل المخاطر وSWOT والمالية');
reset role;

\echo 'RISKS & SWOT TESTS PASSED'
