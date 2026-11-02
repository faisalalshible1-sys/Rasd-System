-- اختبارات العقود: رقم العقد، والأعمال، والمهندسون بأرقام التكليف، والدمج وفكّه،
-- وقيمة الأعمال المنفذة والضمانان منها، والإعدادات الجديدة، ومساعد Claude.
-- تُشغَّل بعد 40_hardening_test.sql على القاعدة نفسها.
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
create or replace function pg_temp.expect_no_change(p_sql text, p_label text) returns void language plpgsql as $$
declare n bigint;
begin
  begin
    execute p_sql;
    get diagnostics n = row_count;
  exception when others then
    raise notice 'PASS (رُفض كما يجب): % — %', p_label, sqlerrm;
    return;
  end;
  if n <> 0 then raise exception 'FAIL: % (تغيّر % صف)', p_label, n; end if;
  raise notice 'PASS (لم يتغير شيء): %', p_label;
end $$;
grant execute on all functions in schema pg_temp to authenticated, anon;

-- ---------------------------------------------------------------- التهيئة: حسابات جديدة لهذه الاختبارات
update app_settings set value = 'true' where key = 'security.signups_open';
update app_settings set value = 'false' where key in ('security.freeze', 'security.require_mfa_all');
insert into auth.users (email, raw_user_meta_data) values
  ('k.contracts@test.ly', '{"full_name":"مكتب العقود ك"}'),
  ('k.staff@test.ly',     '{"full_name":"موظف ك"}'),
  ('k.headsup@test.ly',   '{"full_name":"رئيس الإشراف ك"}'),
  ('k.headtech@test.ly',  '{"full_name":"رئيس الفنية ك"}'),
  ('k.qa@test.ly',        '{"full_name":"الجودة ك"}');

set role authenticated;
select pg_temp.as_user('director.new@test.ly', 'aal2');
select public.set_user_access((select id from profiles where email = 'k.contracts@test.ly'), 'contracts', null, true);
select public.set_user_access((select id from profiles where email = 'k.staff@test.ly'), 'office_staff', null, true);
select public.set_user_access((select id from profiles where email = 'k.headsup@test.ly'), 'dept_head', 'supervision', true);
select public.set_user_access((select id from profiles where email = 'k.headtech@test.ly'), 'dept_head', 'technical', true);
select public.set_user_access((select id from profiles where email = 'k.qa@test.ly'), 'planning_qa', null, true);

-- ---------------------------------------------------------------- نقل البيانات الحالية
select pg_temp.check((select count(*) = 0 from projects p
                       where (p.name <> '' or p.company <> '' or p.assign_no is not null)
                         and not exists (select 1 from contract_works w where w.project_id = p.id)),
                     'لكل عقد عمل واحد على الأقل');
select pg_temp.check((select w.title = p.name and w.company = p.company and w.ref_no = p.assign_no
                        from contract_works w join projects p on p.id = w.project_id where p.assign_no = '005'),
                     'العمل الأول يحمل اسم المشروع وشركته ورقمه');
select pg_temp.check((select e.name = 'سراج محمد لطيوش' and e.assign_no = '005'
                        from contract_engineers e join projects p on p.id = e.project_id
                       where p.assign_no = '005' and e.kind = 'sup'),
                     'المهندس المشرف انتقل إلى جدول المهندسين برقم تكليفه');
select pg_temp.check((select eng_sup = 'سراج محمد لطيوش' from projects where assign_no = '005'),
                     'الخانة النصية القديمة باقية للنسخ السابقة');

-- ---------------------------------------------------------------- رقم العقد: مكتب العقود والمدير
select pg_temp.as_user('k.contracts@test.ly');
select public.set_contract_no((select id from projects where assign_no = '005'), ' ع-2026/15 ');
select pg_temp.check((select contract_no = 'ع-2026/15' from projects where assign_no = '005'), 'مكتب العقود يدخل رقم العقد (بلا فراغات زائدة)');
select pg_temp.check(exists (select 1 from audit_log where action = 'project.update' and detail ? 'contract_no'), 'رقم العقد مسجّل في السجل');
select pg_temp.expect_error($$select public.set_contract_no((select id from projects where assign_no = '006'), 'ع-2026/15')$$, 'رقم عقد مكرر');
select pg_temp.expect_no_change($q$update projects set contract_no = 'x' where assign_no = '006'$q$, 'تعديل رقم العقد مباشرة في الجدول');
select pg_temp.as_user('k.staff@test.ly');
select pg_temp.expect_error($$select public.set_contract_no((select id from projects where assign_no = '006'), 'ع-1')$$, 'موظف المكتب يدخل رقم العقد');
select pg_temp.expect_error($$update projects set contract_no = 'ع-1' where assign_no = '006'$$, 'موظف المكتب يعدّل رقم العقد مباشرة');
select pg_temp.as_user('director.new@test.ly', 'aal2');
select public.set_contract_no((select id from projects where assign_no = '006'), 'ع-2026/16');
select pg_temp.check((select contract_no = 'ع-2026/16' from projects where assign_no = '006'), 'المدير يدخل رقم العقد');

-- ---------------------------------------------------------------- أعمال العقد
select pg_temp.as_user('k.contracts@test.ly');
select pg_temp.check(public.save_work(null, (select id from projects where assign_no = '005'), 'معالجة مختنقات شبكة المياه', 'جودة الاعمار', '', '') is not null,
                     'مكتب العقود يضيف عملاً للعقد');
select pg_temp.check((select count(*) = 2 from contract_works w join projects p on p.id = w.project_id where p.assign_no = '005'), 'للعقد عملان');
select pg_temp.as_user('k.qa@test.ly');
select pg_temp.expect_error($$select public.save_work(null, (select id from projects where assign_no = '005'), 'x', 'y', '', '')$$, 'مكتب الجودة يضيف عملاً');
select pg_temp.expect_error($$insert into contract_works (project_id, title) values ((select id from projects where assign_no = '005'), 'x')$$, 'الإضافة المباشرة في جدول الأعمال');

-- ---------------------------------------------------------------- مهندسون متعددون بأرقام تكليف
select pg_temp.as_user('k.headsup@test.ly');
select public.save_engineer(null, (select id from projects where assign_no = '005'), 'sup', 'م. أحمد الإشراف', 'ت-77', '2026-11-01', null, '');
select public.save_engineer(null, (select id from projects where assign_no = '005'), 'fol', 'م. سالم المتابعة', 'ت-78', null, null, '');
select public.save_engineer(null, (select id from projects where assign_no = '005'), 'fol', 'م. علي المتابعة', 'ت-79', null, null, '');
select pg_temp.check((select count(*) = 2 from contract_engineers e join projects p on p.id = e.project_id where p.assign_no = '005' and e.kind = 'sup'),
                     'مشرفان في العقد نفسه برقمي تكليف');
select pg_temp.check((select eng_sup = 'سراج محمد لطيوش، م. أحمد الإشراف' and eng_fol = 'م. سالم المتابعة، م. علي المتابعة'
                        from projects where assign_no = '005'), 'الخانات القديمة تجمع الأسماء');
select pg_temp.expect_error($$select public.save_engineer(null, (select id from projects where assign_no = '005'), 'sup', 'م. آخر', 'ت-77', null, null, '')$$,
                            'رقم تكليف مكرر لمهندس آخر في العقد نفسه');
select pg_temp.expect_error($$select public.save_engineer(null, (select id from projects where assign_no = '005'), 'qty', 'م. حصر', 'ح-1', null, null, '')$$,
                            'رئيس الإشراف يكلّف مهندس الحصر');
select pg_temp.as_user('k.headtech@test.ly');
select public.save_engineer(null, (select id from projects where assign_no = '005'), 'qty', 'م. حصر أول', 'ح-1', null, null, '');
select public.save_engineer(null, (select id from projects where assign_no = '005'), 'qty', 'م. حصر ثانٍ', 'ح-2', null,
                            (select w.id from contract_works w join projects p on p.id = w.project_id where p.assign_no = '005' and w.title like 'معالجة%'), '');
select pg_temp.check((select count(*) = 2 and count(work_id) = 1 from contract_engineers e join projects p on p.id = e.project_id
                       where p.assign_no = '005' and e.kind = 'qty'), 'رئيس الفنية يكلّف مهندسَي حصر، أحدهما لعمل محدد');
select pg_temp.expect_error($$select public.delete_engineer((select e.id from contract_engineers e join projects p on p.id = e.project_id
                                                              where p.assign_no = '005' and e.assign_no = 'ت-78'))$$, 'رئيس الفنية يحذف مهندس متابعة');
select pg_temp.as_user('k.headsup@test.ly');
select public.delete_engineer((select e.id from contract_engineers e join projects p on p.id = e.project_id where p.assign_no = '005' and e.assign_no = 'ت-79'));
select pg_temp.check((select eng_fol = 'م. سالم المتابعة' from projects where assign_no = '005'), 'حذف تكليف يحدّث الأسماء');
select pg_temp.check(exists (select 1 from audit_log where action = 'engineer.add' and detail ->> 'assign_no' = 'ح-2')
                     and exists (select 1 from audit_log where action = 'engineer.delete' and detail ->> 'assign_no' = 'ت-79'),
                     'التكليفات مسجّلة في السجل');

-- النسخ السابقة: خانة واحدة تحل محل القائمة
select public.set_engineer((select id from projects where assign_no = '007'), 'f06', 'م. متابعة قديمة');
select pg_temp.check((select count(*) = 1 from contract_engineers e join projects p on p.id = e.project_id
                       where p.assign_no = '007' and e.kind = 'fol' and e.name = 'م. متابعة قديمة'), 'الإسناد من النسخ السابقة يعمل');

-- ---------------------------------------------------------------- المالية: قيمة الأعمال المنفذة والضمانان منها
select pg_temp.as_user('k.contracts@test.ly');
select public.set_contract_finance((select id from projects where assign_no = '005'), 900000, 400000, 100000, null, null, 5000);
select pg_temp.check((select contract_value = 900000 and executed_value = 400000 and guarantee_initial = 20000 and guarantee_final = 8000
                        from projects where assign_no = '005'), 'الضمان الابتدائي 5% والنهائي 2% من قيمة الأعمال المنفذة');
select pg_temp.expect_error($$select public.set_contract_finance((select id from projects where assign_no = '005'), 1, -5, null, null, null, null)$$,
                            'قيمة منفذة سالبة');
select public.set_contract_finance((select id from projects where assign_no = '006'), 300000, 100000, 50000, null, null, null);

-- ---------------------------------------------------------------- الدمج
-- حالة نموذج في العمل المدمج لا تُلغي حالة العقد، وما لم يبدأ في العقد يأخذها
select pg_temp.as_user('director.new@test.ly', 'aal2');
select public.set_form_status((select id from projects where assign_no = '006'), 'f03', 'done');
select public.set_form_status((select id from projects where assign_no = '005'), 'f03', 'wip');
select public.set_form_status((select id from projects where assign_no = '006'), 'f09', 'done');
select public.set_form_status((select id from projects where assign_no = '005'), 'f09', 'todo');

select pg_temp.as_user('k.staff@test.ly');
select pg_temp.expect_error($$select public.merge_contracts((select id from projects where assign_no = '005'), array[(select id from projects where assign_no = '006')])$$,
                            'موظف المكتب يدمج الأعمال');
select pg_temp.as_user('k.contracts@test.ly');
select pg_temp.check(public.merge_contracts((select id from projects where assign_no = '005'),
                                            array[(select id from projects where assign_no = '006')]) = 1, 'مكتب العقود يدمج عملاً في العقد');
select pg_temp.check((select count(*) = 0 from projects where assign_no = '006'), 'العمل المدمج اختفى من قائمة العقود');
select pg_temp.check((select count(*) = 3 from contract_works w join projects p on p.id = w.project_id where p.assign_no = '005'), 'أعماله انتقلت إلى العقد');
select pg_temp.check((select count(*) = 3 from contract_engineers e join projects p on p.id = e.project_id where p.assign_no = '005' and e.kind = 'sup'),
                     'مهندسوه انتقلوا إلى العقد');
select pg_temp.check((select contract_value = 1200000 and executed_value = 500000 and payment_first = 150000 and deductions = 5000
                             and guarantee_initial = 25000 and guarantee_final = 10000 and contract_no = 'ع-2026/15'
                        from projects where assign_no = '005'), 'القيم المالية جُمعت والضمانان أُعيد حسابهما ورقم العقد باقٍ');
select pg_temp.check((select status = 'wip' from project_forms pf join projects p on p.id = pf.project_id where p.assign_no = '005' and pf.form_key = 'f03'),
                     'حالة العقد في النموذج تبقى');
select pg_temp.check((select status = 'done' from project_forms pf join projects p on p.id = pf.project_id where p.assign_no = '005' and pf.form_key = 'f09'),
                     'ما لم يبدأ في العقد يأخذ حالة العمل المدمج');
select pg_temp.check((select count(*) = 1 from v_project_progress v where v.project_id in (select id from projects where assign_no = '005'))
                     and not exists (select 1 from public.merged_sources((select id from projects where assign_no = '005')) m where m ->> 'assign_no' <> '006'),
                     'نسبة الإنجاز للعقد وحده، والمدمج يظهر في قائمة الأعمال المدمجة');
select pg_temp.check(exists (select 1 from audit_log where action = 'contract.merge' and (detail ->> 'count')::int = 1), 'الدمج مسجّل في السجل');
select pg_temp.expect_error($$select public.set_contract_finance((select (m ->> 'id')::uuid from public.merged_sources((select id from projects where assign_no = '005')) m), 1, 1, 1, 1, 1, 1)$$,
                            'تعديل مالية عمل مدمج');
select pg_temp.expect_error($$select public.delete_work((select w.id from contract_works w join projects p on p.id = w.project_id
                                                          where p.assign_no = '005' and w.ref_no = '006'))$$, 'حذف عمل مدمج بدل فك الدمج');
select pg_temp.expect_error($$select public.unmerge_contract((select (m ->> 'id')::uuid from public.merged_sources((select id from projects where assign_no = '005')) m))$$,
                            'مكتب العقود يفك الدمج');

-- ---------------------------------------------------------------- فك الدمج (المدير)
select pg_temp.as_user('director.new@test.ly', 'aal2');
select public.unmerge_contract((select (m ->> 'id')::uuid from public.merged_sources((select id from projects where assign_no = '005')) m));
select pg_temp.check((select count(*) = 1 from projects where assign_no = '006' and merged_into is null), 'العمل عاد عقداً مستقلاً');
select pg_temp.check((select count(*) = 2 from contract_works w join projects p on p.id = w.project_id where p.assign_no = '005')
                     and (select count(*) = 1 from contract_works w join projects p on p.id = w.project_id where p.assign_no = '006'),
                     'الأعمال عادت إلى أصحابها');
select pg_temp.check((select contract_value = 900000 and executed_value = 400000 and guarantee_initial = 20000 from projects where assign_no = '005'),
                     'القيم المالية عادت');
select pg_temp.check((select eng_sup = 'محمد يونس السعيطي' from projects where assign_no = '006'), 'المهندسون عادوا');

-- ---------------------------------------------------------------- الإعدادات الجديدة
select public.set_setting('ui.motion', '"reduced"');
select public.set_setting('ui.nav', '{"hidden": ["analysis"], "order": ["home", "projects"], "labels": {"projects": "العقود"}}');
select public.set_setting('ui.dashboard', '{"sections": [{"key": "finance", "on": true}, {"key": "engineers", "on": false}]}');
select public.set_setting('ui.labels', '{"project": "عقد", "projects": "العقود"}');
select public.set_setting('ai.model', '"claude-opus-5-5"');
select pg_temp.expect_error($$select public.set_setting('ui.motion', '"fast"')$$, 'قيمة حركة غير معروفة');
select pg_temp.expect_error($$select public.set_setting('ui.dashboard', '{"sections": [{"key": 1}]}')$$, 'قسم لوحة بصيغة خاطئة');
select pg_temp.expect_error($$select public.set_setting('ai.model', '"bad model!"')$$, 'اسم نموذج غير صالح');
reset role;
set role anon;
select pg_temp.check((select public.public_settings() ->> 'ui.motion') = 'reduced', 'إعداد الحركة متاح لشاشة الدخول');
reset role;
set role authenticated;
select pg_temp.as_user('k.staff@test.ly');
select pg_temp.expect_error($$select public.set_setting('ui.motion', '"off"')$$, 'موظف يغيّر إعدادات التطبيق');

-- ---------------------------------------------------------------- مساعد Claude (المدير وحده)
select pg_temp.expect_error($$select public.ai_context()$$, 'موظف يستخدم مساعد Claude');
select pg_temp.as_user('director.new@test.ly', 'aal2');
select pg_temp.check((select jsonb_array_length(c -> 'contracts') > 10 and c ? 'pending_requests' and c ->> 'model' is not null
                        from public.ai_context() c), 'ملخص المنظومة لمساعد Claude');
select public.ai_log('claude-opus-5-5', 1200, 300, 40);
select pg_temp.check(exists (select 1 from audit_log where action = 'ai.ask' and (detail ->> 'output_tokens')::int = 300), 'استخدام المساعد مسجّل دون نص السؤال');
select public.set_setting('ai.enabled', 'false');
select pg_temp.expect_error($$select public.ai_context()$$, 'المساعد متوقف من الإعدادات');
select public.set_setting('ai.enabled', 'true');
select public.set_setting('ui.motion', '"full"');

-- ---------------------------------------------------------------- عقد جديد يبدأ بعمله الأول
select pg_temp.as_user('k.staff@test.ly');
insert into projects (assign_no, name, owner, company, department) values ('950', 'عقد اختبار', 'المالك', 'شركة ب', 'supervision');
select pg_temp.check((select count(*) = 1 from contract_works w join projects p on p.id = w.project_id
                       where p.assign_no = '950' and w.company = 'شركة ب'), 'العقد الجديد يبدأ بعمله الأول');
reset role;

\echo 'CONTRACTS TESTS PASSED'
