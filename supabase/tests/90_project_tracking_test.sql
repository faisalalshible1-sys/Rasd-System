-- اختبارات «سجل المخاطر ومتابعة المشاريع – الإصدار 2.0» (الترحيل 16).
-- تُشغَّل بعد 80_risks_swot_test.sql وبعد تطبيق 20261111000016_project_tracking.sql على القاعدة نفسها.
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
create or replace function pg_temp.pid(p_no text) returns uuid language sql security definer as $$
  select id from public.projects where assign_no = p_no
$$;
create or replace function pg_temp.q(p_sql text) returns jsonb language plpgsql security definer as $$
declare r jsonb;
begin
  execute 'select to_jsonb(t) from (' || p_sql || ') t limit 1' into r;
  return r;
end $$;
create or replace function pg_temp.n(p_sql text) returns bigint language plpgsql security definer as $$
declare r bigint;
begin
  execute 'select count(*) from (' || p_sql || ') t' into r;
  return r;
end $$;
grant execute on all functions in schema pg_temp to authenticated, anon;

-- ---------------------------------------------------------------- الترقية والبيانات الأولية
select pg_temp.check((select department = 'الشؤون الفنية' and cost_impact = 1500000 and time_impact_days = 45 and executor = 'الاستشاري'
                             and description = 'قصور الدراسات الجيوتقنية لموقع الجسر' and residual_probability = 2
                        from public.risks where code = 'R01'), 'ترقية R01 إلى صيغة الإصدار 2.0');
select pg_temp.check((select status = 'closed' and closed_on = '2026-07-30' from public.risks where description = 'نزاعات ملكية على مسارات الأرصفة'),
                     'R11 مغلق بتاريخ إغلاقه');
select pg_temp.check((select description = 'تأخر اعتماد المخططات التنفيذية' from public.risks where code = 'R13'),
                     'خطر أنشأه مستخدم لا يُمس');
select pg_temp.check((select count(*) = 2 from public.risks where description in ('العثور على مخلفات حرب أثناء أعمال الحفر',
                                                                                  'تدهور إنشائي غير مكتشف في المبنى التراثي')),
                     'إضافة الخطرين الجديدين برموز متاحة');
select pg_temp.check((select count(*) = 18 from public.risk_reviews), 'ثماني عشرة مراجعة من الملف');
select pg_temp.check((select count(*) = 3 and max(v.score) = 20 from public.risk_reviews v join public.risks r on r.id = v.risk_id where r.code = 'R01'),
                     'مراجعات R01');
select pg_temp.check((select bool_and(x ? 'review_days') from public.app_settings, jsonb_array_elements(value -> 'levels') x where key = 'risk.config'),
                     'دورية المراجعة لكل مستوى');
select pg_temp.check((select value -> 'categories' ? 'مخلفات الحرب والأمن' and value -> 'executors' ? 'المقاول'
                        from public.app_settings where key = 'risk.config'), 'تصنيفات ومنفذو الإصدار 2.0');
select pg_temp.check((select (value ->> 'spi_ok')::numeric = 0.95 and jsonb_array_length(value -> 'grades') = 5
                        from public.app_settings where key = 'pm.config'), 'إعدادات المتابعة الافتراضية');
select pg_temp.check((select count(*) from public.pm_issues) + (select count(*) from public.pm_progress) = 0,
                     'السجلات الجديدة تبدأ فارغة');

-- ---------------------------------------------------------------- البرنامج الزمني
set role authenticated;
select pg_temp.as_user('staff.new@test.ly');
select public.save_project_schedule(pg_temp.pid('003'),
  '{"project_type": "طرق", "location": "القطاع (أ)", "consultant": "المكتب الاستشاري (1)", "op_status": "running", "start_date": "2026-01-01", "end_date": "2026-12-31"}');
select pg_temp.check((select start_date = '2026-01-01' and project_type = 'طرق' from public.pm_projects where project_id = pg_temp.pid('003')),
                     'موظف مكتب المدير يحفظ البرنامج الزمني');
select pg_temp.check(pg_temp.n($$select 1 from public.audit_log where action = 'pm.schedule'$$) = 1, 'تسجيل البرنامج الزمني في التدقيق');
select pg_temp.expect_error($$select public.save_project_schedule(pg_temp.pid('003'), '{"start_date": "2026-05-01", "end_date": "2026-01-01"}')$$,
                            'نهاية قبل البداية');
select pg_temp.as_user('headtech@test.ly');
select pg_temp.expect_error($$select public.save_project_schedule(pg_temp.pid('003'), '{"op_status": "suspended"}')$$,
                            'رئيس قسم غير مشرف يعدّل البرنامج الزمني');
select pg_temp.as_user('headsup@test.ly');
select public.save_project_schedule(pg_temp.pid('003'),
  '{"project_type": "طرق", "op_status": "running", "start_date": "2026-01-01", "end_date": "2027-01-31"}');
select pg_temp.check((select end_date = '2027-01-31' from public.pm_projects where project_id = pg_temp.pid('003')),
                     'رئيس القسم المشرف يعدّل البرنامج الزمني');
select pg_temp.as_user('auditor@test.ly');
select pg_temp.expect_error($$select public.save_project_schedule(pg_temp.pid('003'), '{}')$$, 'CISO يعدّل البرنامج الزمني');

-- ---------------------------------------------------------------- سجل التقدم
select pg_temp.as_user('headsup@test.ly');
select public.save_pm_progress(null, jsonb_build_object('project_id', pg_temp.pid('003'), 'measured_on', '2026-09-30', 'planned', 0.6, 'actual', 0.52,
                                                         'prepared_by', 'الإشراف والتنسيق'));
select public.save_pm_progress(null, jsonb_build_object('project_id', pg_temp.pid('003'), 'measured_on', '2026-10-31', 'planned', 0.75, 'actual', 0.64,
                                                         'obstacles', 'تأخر التوريد'));
select pg_temp.check(pg_temp.n($$select 1 from public.pm_progress where project_id = pg_temp.pid('003')$$) = 2, 'قياسان للعقد');
select pg_temp.expect_error($$select public.save_pm_progress(null, jsonb_build_object('project_id', pg_temp.pid('003'), 'measured_on', '2026-10-31', 'planned', 0.8, 'actual', 0.7))$$,
                            'قياس مكرر بالتاريخ نفسه');
select pg_temp.expect_error($$select public.save_pm_progress(null, jsonb_build_object('project_id', pg_temp.pid('003'), 'measured_on', '2026-11-01', 'planned', 1.2, 'actual', 0.7))$$,
                            'نسبة أكبر من 100%');
select pg_temp.expect_error($$select public.save_pm_progress(null, jsonb_build_object('project_id', pg_temp.pid('003'), 'measured_on', (current_date + 30)::text, 'planned', 0.9, 'actual', 0.8))$$,
                            'قياس بتاريخ مستقبلي');
select pg_temp.expect_error($$select public.save_pm_progress(null, jsonb_build_object('measured_on', '2026-08-31', 'planned', 0.4, 'actual', 0.4))$$,
                            'قياس بلا عقد');
select public.save_pm_progress((select id from public.pm_progress where measured_on = '2026-10-31' and project_id = pg_temp.pid('003')),
  jsonb_build_object('measured_on', '2026-10-31', 'planned', 0.75, 'actual', 0.66, 'obstacles', 'تأخر التوريد'));
select pg_temp.check((select actual = 0.66 from public.pm_progress where measured_on = '2026-10-31' and project_id = pg_temp.pid('003')),
                     'تصحيح قياس');
select pg_temp.expect_error($$select public.delete_pm_progress((select id from public.pm_progress limit 1))$$, 'رئيس القسم يحذف قياساً');

-- ---------------------------------------------------------------- مراجعات المخاطر والحقول الجديدة
select public.save_risk_review(null, (select id from public.risks where code = 'R05'),
  '{"reviewed_on": "2026-11-01", "probability": 2, "impact": 5, "actions_done": "تفتيش أسبوعي", "progress": 0.5, "reviewer": "الإشراف والتنسيق"}');
select pg_temp.check((select v.score = 10 and v.progress = 0.5 from public.risk_reviews v join public.risks r on r.id = v.risk_id
                       where r.code = 'R05' order by reviewed_on desc limit 1), 'مراجعة جديدة بالتقييم الحالي');
select pg_temp.check(pg_temp.n($$select 1 from public.audit_log where action = 'risk.review' and project_label = 'R05'$$) = 1, 'تسجيل المراجعة');
select pg_temp.expect_error($$select public.save_risk_review(null, (select id from public.risks where code = 'R05'), '{"probability": 6, "impact": 2}')$$,
                            'احتمالية خارج المقياس');
select pg_temp.expect_error($$select public.save_risk_review(null, (select id from public.risks where code = 'R05'), '{"probability": 2, "impact": 2, "progress": 1.5}')$$,
                            'نسبة تنفيذ أكبر من 100%');
select public.save_risk(null, '{"description": "تأخر تسليم الموقع للمقاول", "probability": 3, "impact": 4, "department": "الإشراف والتنسيق", "time_impact_days": 20, "cost_impact": 50000, "contingency": "تسليم جزئي", "executor": "مكتب المدير"}');
select pg_temp.check((select department = 'الإشراف والتنسيق' and time_impact_days = 20 and cost_impact = 50000 and contingency = 'تسليم جزئي'
                        from public.risks where description = 'تأخر تسليم الموقع للمقاول'), 'حفظ حقول الإصدار 2.0 في الخطر');
select public.save_risk((select id from public.risks where description = 'تأخر تسليم الموقع للمقاول'),
  '{"description": "تأخر تسليم الموقع للمقاول", "probability": 3, "impact": 4}');
select pg_temp.check((select department = 'الإشراف والتنسيق' and cost_impact = 50000 from public.risks where description = 'تأخر تسليم الموقع للمقاول'),
                     'نسخة التطبيق السابقة لا تمسح الحقول الجديدة');
select pg_temp.as_user('auditor@test.ly');
select pg_temp.expect_error($$select public.save_risk_review(null, (select id from public.risks where code = 'R05'), '{"probability": 2, "impact": 2}')$$,
                            'CISO يسجّل مراجعة');

-- ---------------------------------------------------------------- المشاكل والتأخيرات
select pg_temp.as_user('headsup@test.ly');
select public.save_pm_issue(null, jsonb_build_object('project_id', pg_temp.pid('003'), 'description', 'تأخر اعتماد عينات الخلطة الإسفلتية',
  'category', 'جودة', 'risk_id', (select id from public.risks where code = 'R07'), 'priority', 'high', 'party', 'consultant',
  'department', 'المطابقة والاستلام', 'time_impact_days', 10, 'target_date', '2026-11-20'));
select pg_temp.check((select code = 'I01' and status = 'open' and party = 'consultant' from public.pm_issues), 'مشكلة برمز تلقائي I01');
select public.save_pm_issue((select id from public.pm_issues where code = 'I01'),
  jsonb_build_object('description', 'تأخر اعتماد عينات الخلطة الإسفلتية', 'status', 'closed', 'priority', 'high', 'party', 'consultant'));
select pg_temp.check((select closed_on = current_date and project_id = pg_temp.pid('003') from public.pm_issues where code = 'I01'),
                     'الإغلاق يسجّل تاريخ اليوم ويبقي العقد');
select pg_temp.expect_error($$select public.save_pm_issue(null, jsonb_build_object('project_id', pg_temp.pid('003'), 'description', 'مشكلة', 'party', 'جهة'))$$,
                            'جهة مسؤولة غير معروفة');
select public.save_pm_delay(null, jsonb_build_object('project_id', pg_temp.pid('003'), 'description', 'تأخر توريد حديد التسليح',
  'cause', 'المواد والتوريد', 'party', 'contractor', 'delay_class', 'non_excusable', 'critical', true, 'start_date', '2026-09-01',
  'end_date', '2026-09-21', 'eot_requested', 20));
select pg_temp.check((select code = 'D01' and critical and eot_approved is null from public.pm_delays), 'حدث تأخير D01');
select pg_temp.expect_error($$select public.save_pm_delay(null, jsonb_build_object('project_id', pg_temp.pid('003'), 'description', 'حدث', 'start_date', '2026-09-10', 'end_date', '2026-09-01'))$$,
                            'نهاية الأثر قبل بدايته');
select pg_temp.expect_error($$select public.delete_pm_record('delay', (select id from public.pm_delays where code = 'D01'))$$, 'رئيس القسم يحذف حدثاً');

-- ---------------------------------------------------------------- التغييرات وربطها بمالية العقد
select pg_temp.as_user('headtech@test.ly');
select public.save_pm_change(null, jsonb_build_object('project_id', pg_temp.pid('003'), 'description', 'إضافة طبقة أساس في مقطع ضعيف التربة',
  'change_type', 'أعمال إضافية', 'source', 'consultant', 'reason', 'ظروف موقع غير متوقعة', 'cost_estimate', 420000, 'time_requested', 20));
select pg_temp.check((select code = 'C01' and status = 'submitted' and variation_id is null from public.pm_changes), 'طلب تغيير C01');
select pg_temp.expect_error($$select public.save_pm_change((select id from public.pm_changes where code = 'C01'),
  jsonb_build_object('description', 'إضافة طبقة أساس في مقطع ضعيف التربة', 'source', 'consultant', 'status', 'approved', 'cost_approved', 385000))$$,
  'الشؤون الفنية تعتمد التغيير');
select pg_temp.as_user('k.contracts@test.ly');
select public.save_pm_change((select id from public.pm_changes where code = 'C01'),
  jsonb_build_object('description', 'إضافة طبقة أساس في مقطع ضعيف التربة', 'source', 'consultant', 'change_type', 'أعمال إضافية',
                     'cost_estimate', 420000, 'cost_approved', 385000, 'time_requested', 20, 'time_approved', 15, 'status', 'approved',
                     'approval_ref', 'ق.ت/2026/014', 'decided_on', '2026-11-05'));
select pg_temp.check((select v.kind = 'add' and v.amount = 385000 and v.approved_on = '2026-11-05' and v.ref_no = 'ق.ت/2026/014'
                        from public.pm_changes c join public.contract_variations v on v.id = c.variation_id where c.code = 'C01'),
                     'الاعتماد يُنشئ أمر تغيير في مالية العقد');
select pg_temp.check((select variations_net = 385000 from public.projects where id = pg_temp.pid('003')), 'صافي أوامر التغيير في العقد');
select pg_temp.expect_error($$select public.delete_variation((select variation_id from public.pm_changes where code = 'C01'))$$,
                            'حذف أمر التغيير المرتبط من المالية');
select pg_temp.expect_error($$select public.save_variation((select variation_id from public.pm_changes where code = 'C01'), null, null, 'x', 'تعديل', 'add', 1, null, '')$$,
                            'تعديل أمر التغيير المرتبط من المالية');
select public.save_pm_change((select id from public.pm_changes where code = 'C01'),
  jsonb_build_object('description', 'إضافة طبقة أساس في مقطع ضعيف التربة', 'source', 'consultant', 'cost_approved', 400000,
                     'time_approved', 15, 'status', 'approved', 'approval_ref', 'ق.ت/2026/014', 'decided_on', '2026-11-05'));
select pg_temp.check((select variations_net = 400000 from public.projects where id = pg_temp.pid('003'))
                     and pg_temp.n($$select 1 from public.contract_variations where notes like 'من سجل التغييرات C01'$$) = 1,
                     'تعديل القيمة المعتمدة يحدّث أمر التغيير نفسه');
select public.save_pm_change(null, jsonb_build_object('project_id', pg_temp.pid('003'), 'description', 'حذف أعمال السور الخارجي',
  'source', 'owner', 'cost_approved', -210000, 'status', 'approved'));
select pg_temp.check((select v.kind = 'deduct' and v.amount = 210000 and c.decided_on = current_date
                        from public.pm_changes c join public.contract_variations v on v.id = c.variation_id where c.code = 'C02'),
                     'الحذف بالسالب أمر نقص بتاريخ البت');
select pg_temp.check((select variations_net = 190000 from public.projects where id = pg_temp.pid('003')), 'الصافي بعد الزيادة والنقص');
select public.save_pm_change((select id from public.pm_changes where code = 'C02'),
  jsonb_build_object('description', 'حذف أعمال السور الخارجي', 'source', 'owner', 'cost_approved', -210000, 'status', 'under_study'));
select pg_temp.check((select variation_id is null and decided_on is null from public.pm_changes where code = 'C02')
                     and (select variations_net = 400000 from public.projects where id = pg_temp.pid('003')),
                     'إلغاء الاعتماد يحذف أمر التغيير');
select pg_temp.as_user('headtech@test.ly');
select pg_temp.expect_error($$select public.save_pm_change((select id from public.pm_changes where code = 'C01'),
  jsonb_build_object('description', 'تعديل', 'source', 'consultant', 'status', 'approved', 'cost_approved', 1))$$,
  'الشؤون الفنية تعدّل تغييراً معتمداً');
select pg_temp.as_user('director.new@test.ly', 'aal2');
select public.delete_pm_record('change', (select id from public.pm_changes where code = 'C01'));
select pg_temp.check((select variations_net = 0 from public.projects where id = pg_temp.pid('003'))
                     and pg_temp.n($$select 1 from public.contract_variations where notes like 'من سجل التغييرات%'$$) = 0,
                     'حذف التغيير يحذف أمر التغيير المرتبط');
select pg_temp.check(pg_temp.n($$select 1 from public.audit_log where action = 'pm.change_delete' and project_label = 'C01'$$) = 1, 'تسجيل الحذف');

-- ---------------------------------------------------------------- الدروس والتقييمات
select pg_temp.as_user('headsup@test.ly');
select public.save_pm_lesson(null, '{"situation": "اكتشاف مرافق مدفونة بعد بدء الحفر", "lesson": "كشف تجريبي قبل الحفر في كل مقطع", "lesson_type": "negative", "apply_mechanism": "تعديل إجراء"}');
select pg_temp.check((select code = 'L01' and status = 'proposed' and project_id is null from public.pm_lessons), 'درس عام برمز L01');
select pg_temp.expect_error($$select public.save_pm_lesson((select id from public.pm_lessons where code = 'L01'),
  '{"situation": "اكتشاف مرافق مدفونة بعد بدء الحفر", "lesson": "كشف تجريبي قبل الحفر في كل مقطع", "status": "approved"}')$$,
  'رئيس القسم يعتمد درساً');
select pg_temp.as_user('staff.new@test.ly');
select public.save_pm_lesson((select id from public.pm_lessons where code = 'L01'),
  '{"situation": "اكتشاف مرافق مدفونة بعد بدء الحفر", "lesson": "كشف تجريبي قبل الحفر في كل مقطع", "status": "approved"}');
select pg_temp.check((select status = 'approved' and applied_on = current_date from public.pm_lessons where code = 'L01'), 'مكتب المدير يعتمد الدرس');
select public.save_pm_evaluation(null, jsonb_build_object('project_id', pg_temp.pid('003'), 'evaluated_on', '2026-09-30',
  'quality', 4, 'safety', 4, 'schedule', 3, 'resources', 4, 'cooperation', 4, 'documentation', 3, 'evaluator', 'الإشراف والتنسيق'));
select pg_temp.check((select company = 'اثمار بنغازي للمقاولات' from public.pm_evaluations), 'الشركة من العقد تلقائياً');
select pg_temp.expect_error($$select public.save_pm_evaluation(null, jsonb_build_object('project_id', pg_temp.pid('003')))$$, 'تقييم بلا معايير');
select pg_temp.expect_error($$select public.save_pm_evaluation(null, jsonb_build_object('project_id', pg_temp.pid('003'), 'quality', 7))$$, 'درجة خارج المقياس');

-- ---------------------------------------------------------------- الإعدادات
select pg_temp.expect_error($$select public.set_setting('pm.config', '{"spi_ok": 0.95}')$$, 'الموظف يعدّل إعدادات المتابعة');
select pg_temp.as_user('director.new@test.ly', 'aal2');
select pg_temp.expect_error($$select public.set_setting('pm.config', '{"weights": {"schedule": 0.5, "delay": 0.2, "field": 0.2, "response": 0.2}}')$$,
                            'أوزان لا يساوي مجموعها 100%');
select pg_temp.expect_error($$select public.set_setting('pm.config', '{"spi_ok": 1.2, "spi_ahead": 1.05}')$$, 'حد «ضمن المخطط» أعلى من «متقدم»');
select pg_temp.expect_error($$select public.set_setting('pm.config', '{"grades": [{"min": 10, "name": "ضعيف"}, {"min": 50, "name": "جيد"}]}')$$,
                            'جدول تقدير لا يبدأ من الصفر');
select public.set_setting('pm.config', (select value || '{"stale_days": 14}' from public.app_settings where key = 'pm.config'));
select pg_temp.check((select (value ->> 'stale_days')::int = 14 from public.app_settings where key = 'pm.config'), 'حفظ إعدادات المتابعة');
select pg_temp.expect_error($$select public.set_setting('risk.config', (select jsonb_set(value, '{levels,0,review_days}', '400') from public.app_settings where key = 'risk.config'))$$,
                            'دورية مراجعة أكبر من سنة');
select public.set_setting('risk.config', (select jsonb_set(value, '{levels,0,review_days}', '45') from public.app_settings where key = 'risk.config'));
select pg_temp.check((select (value -> 'levels' -> 0 ->> 'review_days')::int = 45 from public.app_settings where key = 'risk.config'),
                     'تعديل دورية المراجعة');
select public.set_setting('ui.motion', '"reduced"');
select pg_temp.check((select value = '"reduced"' from public.app_settings where key = 'ui.motion'), 'الإعدادات الأخرى تعمل كما كانت');

-- ---------------------------------------------------------------- الدمج وفكّه
select public.save_pm_issue(null, jsonb_build_object('project_id', pg_temp.pid('002'), 'description', 'تأخر تصريح الحفر', 'party', 'utilities'));
select pg_temp.as_user('k.contracts@test.ly');
select pg_temp.check(public.merge_contracts(pg_temp.pid('001'), array[pg_temp.pid('002')]) = 1, 'دمج عقد له مشكلة مسجلة');
select pg_temp.check((select project_id = pg_temp.pid('001') and origin_project = pg_temp.pid('002') from public.pm_issues
                       where description = 'تأخر تصريح الحفر'), 'المشكلة تنتقل مع الدمج');
select pg_temp.as_user('director.new@test.ly', 'aal2');
select public.unmerge_contract(pg_temp.pid('002'));
select pg_temp.check((select project_id = pg_temp.pid('002') and origin_project is null from public.pm_issues where description = 'تأخر تصريح الحفر'),
                     'وتعود بفك الدمج');
select pg_temp.check((public.ai_context() -> 'pm' -> 'issues') is not null and jsonb_array_length(public.ai_context() -> 'pm' -> 'schedules') = 1,
                     'ملخص Claude يشمل متابعة المشاريع');
select public.delete_pm_record('issue', (select id from public.pm_issues where description = 'تأخر تصريح الحفر'));
select pg_temp.check(pg_temp.n($$select 1 from public.pm_issues where description = 'تأخر تصريح الحفر'$$) = 0, 'المدير يحذف مشكلة');
select pg_temp.as_user('k.staff@test.ly');
select pg_temp.check((select count(*) = 2 from public.pm_progress), 'القراءة متاحة لكل الأعضاء');
select pg_temp.as_user('pending@test.ly');
select pg_temp.check((select count(*) = 0 from public.pm_progress), 'غير المفعّل لا يرى شيئاً');

reset role;
\echo 'PROJECT TRACKING TESTS PASSED'
