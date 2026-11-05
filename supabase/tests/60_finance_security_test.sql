-- اختبارات المالية الموسعة (قيم البنود، أوامر التغيير، المستخلصات، الحساب الآلي، الدمج)
-- والأمان الموسع (الأجهزة، قفل الدخول، إجراءات CISO، الحركة والتنبيهات) وإعداد المظهر.
-- تُشغَّل بعد 50_contracts_test.sql على القاعدة نفسها.
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
create or replace function pg_temp.pid(p_assign text) returns uuid language sql security definer as $$
  select id from public.projects where assign_no = p_assign
$$;
create or replace function pg_temp.fin(p_assign text) returns public.projects language sql security definer as $$
  select * from public.projects where assign_no = p_assign
$$;
create or replace function pg_temp.work_id(p_assign text, p_n integer default 1) returns uuid language sql security definer as $$
  select w.id from public.contract_works w where w.project_id = (select id from public.projects where assign_no = p_assign)
   order by w.sort, w.created_at offset p_n - 1 limit 1
$$;
create or replace function pg_temp.sessions_of(p_email text) returns bigint language sql security definer as $$
  select count(*) from auth.sessions s join auth.users u on u.id = s.user_id where u.email = p_email
$$;
create or replace function pg_temp.session_of(p_email text, p_ua text) returns uuid language sql security definer as $$
  select s.id from auth.sessions s join auth.users u on u.id = s.user_id where u.email = p_email and coalesce(s.user_agent, '') like p_ua limit 1
$$;
create or replace function pg_temp.director_notified(p_like text) returns boolean language sql security definer as $$
  select exists (select 1 from public.notifications n join public.profiles p on p.id = n.user_id where p.role = 'director' and n.title like p_like)
$$;
grant execute on all functions in schema pg_temp to authenticated, anon;

-- ---------------------------------------------------------------- الحالة بعد الترحيل
select pg_temp.check((select bool_and(value_source = 'manual' or exists (select 1 from contract_works w where w.project_id = p.id and w.contract_value is not null))
                        from projects p), 'مصدر القيمة يدوي ما لم تُدخل قيم البنود');
select pg_temp.check(not exists (select 1 from pg_class c join pg_namespace n on n.oid = c.relnamespace
                                  where n.nspname = 'public' and c.relkind = 'r' and not c.relrowsecurity),
                     'كل الجداول الجديدة محمية بسياسات الوصول');

-- ---------------------------------------------------------------- قيم البنود
set role authenticated;
select pg_temp.as_user('k.contracts@test.ly');
select public.set_work_values(pg_temp.work_id('007'), 50000, 20000);
select pg_temp.check((select contract_value = 50000 and executed_value = 20000 and value_source = 'items' and executed_source = 'items'
                             and guarantee_initial = 1000 and guarantee_final = 400 from pg_temp.fin('007')),
                     'قيم البند تصبح قيمة العقد والمنفذ، والضمانان منها');
select public.save_work(null, pg_temp.pid('007'), 'أعمال إضافية', 'شركة ج', '', '');
select public.set_work_values(pg_temp.work_id('007', 2), 30000, null);
select pg_temp.check((select contract_value = 80000 and executed_value = 20000 from pg_temp.fin('007')), 'القيمة التعاقدية مجموع البنود');
update projects set contract_value = 1, executed_value = 2 where assign_no = '007';
select pg_temp.check((select contract_value = 80000 and executed_value = 20000 from pg_temp.fin('007')),
                     'القيم المحسوبة من البنود لا تُعدَّل يدوياً');
select pg_temp.expect_error($$select public.set_work_values(pg_temp.work_id('007'), -1, 0)$$, 'قيمة بند سالبة');
select pg_temp.check(exists (select 1 from audit_log where action = 'finance.work_values' and project_id = pg_temp.pid('007')),
                     'تعديل قيم البنود مسجّل');
select pg_temp.as_user('k.qa@test.ly');
select pg_temp.expect_error($$select public.set_work_values(pg_temp.work_id('007'), 1, 1)$$, 'مكتب الجودة يعدّل قيم البنود');
select pg_temp.expect_error($$update contract_works set contract_value = 1 where id = pg_temp.work_id('007')$$, 'التعديل المباشر في جدول البنود');

-- ---------------------------------------------------------------- أوامر التغيير
select pg_temp.as_user('k.contracts@test.ly');
select public.save_variation(null, pg_temp.pid('007'), pg_temp.work_id('007'), 'أ.ت-1', 'زيادة كميات الحفر', 'add', 10000, '2026-11-01', '');
select public.save_variation(null, pg_temp.pid('007'), null, 'أ.ت-2', 'إلغاء بند الأرصفة', 'deduct', 2000, '2026-11-03', '');
select pg_temp.check((select variations_net = 8000 and contract_value = 80000 from pg_temp.fin('007')),
                     'صافي أوامر التغيير (زيادة ونقص) دون تغيير القيمة الأصلية');
select pg_temp.expect_error($$select public.save_variation(null, pg_temp.pid('007'), null, '', 'خطأ', 'add', 0, null, '')$$, 'أمر تغيير بلا قيمة');
select pg_temp.expect_error($$select public.save_variation(null, pg_temp.pid('007'), null, '', 'خطأ', 'x', 10, null, '')$$, 'نوع أمر تغيير غير معروف');
select pg_temp.expect_error($$select public.save_variation(null, pg_temp.pid('007'), pg_temp.work_id('005'), '', 'بند عقد آخر', 'add', 10, null, '')$$,
                            'أمر تغيير لبند من عقد آخر');
select public.save_variation((select id from contract_variations where ref_no = 'أ.ت-2'), null, null, 'أ.ت-2', 'إلغاء بند الأرصفة', 'deduct', 3000, '2026-11-03', 'معدّل');
select pg_temp.check((select variations_net = 7000 from pg_temp.fin('007')), 'تعديل أمر التغيير يُحدّث الصافي');
select pg_temp.check(exists (select 1 from audit_log where action = 'finance.variation_update'), 'تعديل أمر التغيير مسجّل');

-- ---------------------------------------------------------------- المستخلصات
select pg_temp.check(public.save_extract(null, pg_temp.pid('007'), null, 'م-1', 'interim', '2026-10-01', '2026-10-31', '2026-11-02',
                                         40000, 4000, 0, 0, 1000, 0, 'approved', '2026-11-04', 0, null, '') is not null,
                     'تسجيل مستخلص معتمد');
select pg_temp.check((select x.seq = 1 and x.net_amount = 35000 and x.approved_on = '2026-11-04' from contract_extracts x
                        where x.project_id = pg_temp.pid('007') and x.ref_no = 'م-1'), 'الرقم التسلسلي والصافي بعد الاستقطاعات');
select pg_temp.check((select executed_source = 'extracts' and executed_value = 40000 and extracts_count = 1 and extracts_gross = 40000
                             and extracts_net = 35000 and extracts_paid = 0 and retention_held = 4000
                             and guarantee_initial = 2000 and guarantee_final = 800 from pg_temp.fin('007')),
                     'المنفذ من المستخلصات المعتمدة، والتأمين المحتجز والضمانان');
select public.save_extract(null, pg_temp.pid('007'), null, 'م-2', 'interim', null, null, null, 10000, 0, 0, 0, 0, 0, 'draft', null, 0, null, '');
select pg_temp.check((select extracts_count = 1 and executed_value = 40000 from pg_temp.fin('007')), 'المسودة لا تدخل في المنفذ');
select pg_temp.check((select seq = 2 from contract_extracts where ref_no = 'م-2'), 'الرقم التسلسلي التالي');
select pg_temp.expect_error($$select public.save_extract(null, pg_temp.pid('007'), null, '', 'interim', null, null, null, 100, 60, 50, 0, 0, 0, 'submitted', null, 0, null, '')$$,
                            'استقطاعات أكبر من قيمة الأعمال');
select pg_temp.expect_error($$select public.save_extract(null, pg_temp.pid('007'), null, '', 'interim', null, null, null, 100, 0, 0, 0, 0, 0, 'approved', null, 150, null, '')$$,
                            'مدفوع أكبر من الصافي');
select pg_temp.expect_error($$select public.save_extract(null, pg_temp.pid('007'), null, '', 'interim', null, null, null, 100, 0, 0, 0, 0, 0, 'submitted', null, 50, null, '')$$,
                            'دفع لمستخلص غير معتمد');
select pg_temp.expect_error($$select public.save_extract(null, pg_temp.pid('007'), null, '', 'interim', '2026-10-31', '2026-10-01', null, 100, 0, 0, 0, 0, 0, 'draft', null, 0, null, '')$$,
                            'فترة مستخلص معكوسة');
-- الدفع الجزئي ثم الكامل
select public.save_extract((select id from contract_extracts where ref_no = 'م-1'), null, null, 'م-1', 'interim', '2026-10-01', '2026-10-31', '2026-11-02',
                           40000, 4000, 0, 0, 1000, 0, 'approved', '2026-11-04', 20000, '2026-11-05', '');
select pg_temp.check((select status = 'approved' and paid_amount = 20000 from contract_extracts where ref_no = 'م-1')
                     and (select extracts_paid = 20000 from pg_temp.fin('007')), 'دفع جزئي');
select public.save_extract((select id from contract_extracts where ref_no = 'م-1'), null, null, 'م-1', 'interim', '2026-10-01', '2026-10-31', '2026-11-02',
                           40000, 4000, 0, 0, 1000, 0, 'paid', '2026-11-04', 0, null, '');
select pg_temp.check((select status = 'paid' and paid_amount = 35000 and paid_on is not null from contract_extracts where ref_no = 'م-1')
                     and (select extracts_paid = 35000 from pg_temp.fin('007')), '«مدفوع» يعني دفع الصافي كاملاً');
select pg_temp.expect_error($$select public.save_extract((select id from contract_extracts where ref_no = 'م-1'), null, null, 'م-1', 'interim', null, null, null, 50000, 0, 0, 0, 0, 0, 'approved', null, 0, null, '')$$,
                            'مكتب العقود يعدّل مستخلصاً مدفوعاً');
select pg_temp.expect_error($$select public.delete_extract((select id from contract_extracts where ref_no = 'م-1'))$$, 'مكتب العقود يحذف مستخلصاً مدفوعاً');
select public.delete_extract((select id from contract_extracts where ref_no = 'م-2'));
select pg_temp.check(not exists (select 1 from contract_extracts where ref_no = 'م-2')
                     and exists (select 1 from audit_log where action = 'finance.extract_delete' and detail ->> 'seq' = '2'), 'حذف مسودة مستخلص مسجّل');
select pg_temp.expect_error($$insert into contract_extracts (project_id, gross_amount) values (pg_temp.pid('007'), 1)$$, 'الإضافة المباشرة في جدول المستخلصات');
select pg_temp.check((select count(*) >= 5 from public.finance_history(pg_temp.pid('007'), 100) h where h ->> 'action' like 'finance.%'),
                     'سجل التعديلات المالية للعقد');
select pg_temp.as_user('k.qa@test.ly');
select pg_temp.expect_error($$select public.save_extract(null, pg_temp.pid('007'), null, '', 'interim', null, null, null, 1, 0, 0, 0, 0, 0, 'draft', null, 0, null, '')$$,
                            'مكتب الجودة يسجّل مستخلصاً');
select pg_temp.check((select count(*) = 1 from contract_extracts where project_id = pg_temp.pid('007')), 'كل الأعضاء يقرؤون المستخلصات');

-- ---------------------------------------------------------------- الدمج وفكّه مع البنود والمستخلصات وأوامر التغيير
select pg_temp.as_user('k.contracts@test.ly');
select public.set_contract_finance(pg_temp.pid('950'), 70000, 30000, null, null, null, null);
select public.save_variation(null, pg_temp.pid('950'), null, 'أ.ت-9', 'زيادة', 'add', 5000, null, '');
select public.save_extract(null, pg_temp.pid('950'), null, 'م-9', 'interim', null, null, null, 1000, 100, 0, 0, 0, 0, 'approved', null, 0, null, '');
select pg_temp.check((select value_source = 'manual' and contract_value = 70000 and executed_value = 1000 from pg_temp.fin('950')),
                     'عقد بقيمة يدوية ومستخلص');
select pg_temp.check(public.merge_contracts(pg_temp.pid('007'), array[pg_temp.pid('950')]) = 1, 'دمج عقد بقيمة يدوية');
select pg_temp.check((select contract_value = 150000 and variations_net = 12000 and extracts_count = 2 and executed_value = 41000
                             and retention_held = 4100 from pg_temp.fin('007')),
                     'بعد الدمج: البنود والمستخلصات وأوامر التغيير تُجمع دون تكرار');
select pg_temp.check((select x.seq = 2 from contract_extracts x where x.ref_no = 'م-9'), 'المستخلص المدمج يأخذ رقماً بعد مستخلصات العقد');
select pg_temp.expect_error($$select public.delete_variation((select id from contract_variations where ref_no = 'أ.ت-9'))$$,
                            'حذف أمر تغيير مدمج بدل فك الدمج');
reset role;
set role authenticated;
select pg_temp.as_user('director.new@test.ly', 'aal2');
select public.unmerge_contract(pg_temp.pid('950'));
select pg_temp.check((select contract_value = 80000 and variations_net = 7000 and extracts_count = 1 and executed_value = 40000 from pg_temp.fin('007'))
                     and (select value_source = 'items' and contract_value = 70000 and variations_net = 5000 and executed_value = 1000
                             from pg_temp.fin('950'))
                     and (select seq = 1 from contract_extracts where ref_no = 'م-9'),
                     'فك الدمج يعيد لكلٍّ بنوده ومستخلصاته وأوامره');
-- المدير وحده يعدّل المستخلص المدفوع
select public.save_extract((select id from contract_extracts where ref_no = 'م-1'), null, null, 'م-1', 'interim', '2026-10-01', '2026-10-31', '2026-11-02',
                           40000, 4000, 0, 0, 1000, 0, 'paid', '2026-11-04', 35000, '2026-11-05', 'تصحيح التاريخ');
select pg_temp.check((select paid_on = '2026-11-05' from contract_extracts where ref_no = 'م-1'), 'المدير يصحّح المستخلص المدفوع');
select pg_temp.check((select (c -> 'contracts') @? '$[*] ? (exists(@.extract_list) && exists(@.works[*].id))' from public.ai_context() c)
                     and (select c ? 'security' from public.ai_context() c), 'ملخص Claude يشمل المستخلصات ومعرّفات البنود والأمان');
select public.ai_action_log('propose_variation', 'أمر تغيير مقترح');
select pg_temp.check(exists (select 1 from audit_log where action = 'ai.action' and detail ->> 'name' = 'propose_variation'), 'تنفيذ اقتراح المساعد مسجّل');

-- ---------------------------------------------------------------- إعداد المظهر
select public.set_setting('ui.appearance', '{"density": "compact", "radius": 12, "charts": {"trend": "area", "curved": true}}');
select pg_temp.expect_error($$select public.set_setting('ui.appearance', '{"charts": 5}')$$, 'إعداد رسوم بصيغة خاطئة');
reset role;
set role anon;
select pg_temp.check((select public.public_settings() -> 'ui.appearance' ->> 'density') = 'compact', 'المظهر متاح قبل الدخول');
reset role;

-- ---------------------------------------------------------------- سجل الأجهزة
set role authenticated;
select pg_temp.as_user('staff.new@test.ly');
select set_config('request.headers', '{"user-agent": "TestUA/1.0", "x-forwarded-for": "10.0.0.5, 1.1.1.1"}', false);
select pg_temp.check((select (r ->> 'new')::boolean and (r ->> 'status') = 'ok'
                        from public.register_device('dev-staff-0001', 'android', 'هاتف الموظف', '2.0.7', true, 'login') r),
                     'تسجيل جهاز جديد موثّق');
select pg_temp.check((select ip = '10.0.0.5' and first_ip = '10.0.0.5' and user_agent = 'TestUA/1.0' and trusted and sign_ins = 1
                        from user_devices where device_key = 'dev-staff-0001'), 'العنوان والمتصفح من ترويسات الطلب');
select public.register_device('dev-staff-0001', 'android', '', '2.0.7', null, 'open');
select public.register_device('dev-staff-0001', 'android', '', '2.0.7', false, 'ping');
select pg_temp.check((select opens = 2 and sign_ins = 1 and not trusted and label = 'هاتف الموظف' from user_devices where device_key = 'dev-staff-0001'),
                     'الفتح يُعدّ، والتوثيق يُلغى بطلب صاحبه');
select pg_temp.expect_error($$select public.register_device('x', 'web', '', '', true, 'login')$$, 'معرّف جهاز قصير');
select pg_temp.expect_error($$insert into user_devices (user_id, device_key) values (auth.uid(), 'manual-device-1')$$, 'الإضافة المباشرة في جدول الأجهزة');
select pg_temp.check((select count(*) = 1 from public.my_devices()), 'أجهزتي');
select pg_temp.expect_error($$select * from public.security_devices()$$, 'موظف يطّلع على أجهزة الجميع');
select pg_temp.expect_error($$select public.lock_user((select id from profiles where email = 'k.qa@test.ly'), 30, 'اختبار')$$, 'موظف يقفل حساباً');
select pg_temp.as_user('k.qa@test.ly');
select public.register_device('dev-qa-000001', 'web', 'متصفح الجودة', '2.0.7', false, 'login');
select pg_temp.check((select count(*) = 1 from user_devices), 'كل مستخدم يرى أجهزته فقط');
reset role;

-- ---------------------------------------------------------------- إجراءات CISO
insert into auth.sessions (user_id, user_agent, ip)
select u.id, v.ua, '10.0.0.5' from auth.users u cross join (values ('TestUA/1.0'), ('TestUA/2.0'), ('Other')) v(ua)
 where u.email = 'staff.new@test.ly';
insert into auth.sessions (user_id, user_agent) select id, 'Director' from auth.users where email = 'director.new@test.ly';
insert into auth.audit_log_entries (payload, created_at)
select json_build_object('action', 'login', 'actor_id', id, 'actor_username', email), now() - interval '1 hour'
  from auth.users where email = 'staff.new@test.ly';
set role authenticated;
select pg_temp.as_user('auditor@test.ly', 'aal2');
select pg_temp.check((select (o ->> 'devices_total')::int = 2 and (o ->> 'devices_trusted')::int = 0 and o ? 'users_locked' and o ? 'logins_24h'
                        from public.security_overview() o), 'مركز الأمان يعدّ الأجهزة');
select pg_temp.check((select count(*) = 2 from public.security_devices() d), 'CISO يرى أجهزة الجميع');
select pg_temp.check(exists (select 1 from audit_log where action = 'security.device_new')
                     and exists (select 1 from audit_log where action = 'security.device_untrust'), 'الجهاز الجديد وإلغاء التوثيق في السجل');
select pg_temp.check(exists (select 1 from public.security_alerts() a where a ->> 'kind' = 'new_device'), 'تنبيه جهاز جديد');
select pg_temp.check(exists (select 1 from public.security_timeline((select id from profiles where email = 'staff.new@test.ly'), 7, 100) t
                              where t ->> 'action' = 'login' and t ->> 'source' = 'auth')
                     and exists (select 1 from public.security_timeline((select id from profiles where email = 'staff.new@test.ly'), 7, 100) t
                                  where t ->> 'action' = 'security.device_new'),
                     'الحركة الدقيقة للحساب: الدخول وأحداث الأجهزة');
select pg_temp.check((select u.devices = 1 and u.sessions = 3 from public.security_users() u
                       where u.email = 'staff.new@test.ly'), 'عدد الأجهزة والجلسات لكل حساب');
select pg_temp.check((select jsonb_array_length(d -> 'devices') = 1 and (d -> 'profile' ->> 'can_act')::boolean
                        from public.user_details((select id from profiles where email = 'staff.new@test.ly')) d), 'بيانات الحساب تشمل أجهزته');
select pg_temp.check(not (select (d -> 'profile' ->> 'can_act')::boolean
                            from public.user_details((select id from profiles where email = 'director.new@test.ly')) d),
                     'CISO لا يملك إجراءات على حساب المدير');
select pg_temp.expect_error($$select public.revoke_user_sessions((select id from profiles where email = 'director.new@test.ly'))$$, 'CISO يُخرج المدير');
select pg_temp.expect_error($$select public.lock_user((select id from profiles where email = 'director.new@test.ly'), 30, 'اختبار القفل')$$, 'CISO يقفل المدير');
select pg_temp.expect_error($$select public.lock_user(auth.uid(), 30, 'اختبار القفل')$$, 'CISO يقفل نفسه');
select pg_temp.expect_error($$select public.lock_user((select id from profiles where email = 'staff.new@test.ly'), 30, 'x')$$, 'قفل بلا سبب');
select pg_temp.expect_error($$select public.lock_user((select id from profiles where email = 'staff.new@test.ly'), 2, 'مدة قصيرة')$$, 'مدة قفل أقل من 5 دقائق');
select public.revoke_session(pg_temp.session_of('staff.new@test.ly', 'Other'));
select pg_temp.check(pg_temp.sessions_of('staff.new@test.ly') = 2,
                     'CISO ينهي جلسة محددة');
select pg_temp.expect_error($$select public.revoke_session(pg_temp.session_of('director.new@test.ly', '%'))$$, 'CISO ينهي جلسة المدير');
select pg_temp.check(public.lock_user((select id from profiles where email = 'staff.new@test.ly'), 30, 'محاولات دخول مريبة') = 2,
                     'CISO يقفل الدخول مؤقتاً وتنتهي جلسات الحساب');
select pg_temp.check(pg_temp.director_notified('CISO قفل دخول%'), 'المدير يُبلَّغ بقفل CISO');
select pg_temp.check(exists (select 1 from public.security_alerts() a where a ->> 'kind' = 'locked'), 'تنبيه الحساب المقفل');

select pg_temp.as_user('staff.new@test.ly');
select pg_temp.check(not public.writes_allowed() and (select count(*) = 0 from projects), 'الحساب المقفل لا يرى ولا يعدّل شيئاً');
select pg_temp.check((select (l ->> 'locked')::boolean and l ->> 'reason' = 'محاولات دخول مريبة' from public.my_lock() l), 'صاحب الحساب يعرف سبب القفل');
select pg_temp.expect_error($$select public.set_contract_finance(pg_temp.pid('005'), 1, 1, 1, 1, 1, 1)$$, 'الحساب المقفل يعدّل المالية');

select pg_temp.as_user('auditor@test.ly', 'aal2');
select public.unlock_user((select id from profiles where email = 'staff.new@test.ly'));
select pg_temp.as_user('staff.new@test.ly');
select pg_temp.check(public.is_member() and (select count(*) > 0 from projects), 'فك القفل يعيد الدخول');

-- القفل بلا مدة (حتى يُفك)، والقفل الذي انتهت مدته
select pg_temp.as_user('director.new@test.ly', 'aal2');
select public.lock_user((select id from profiles where email = 'k.qa@test.ly'), null, 'إيقاف إلى حين المراجعة');
select pg_temp.check((select locked_until = 'infinity' from profiles where email = 'k.qa@test.ly'), 'قفل بلا مدة');
reset role;
update profiles set locked_until = now() - interval '1 minute' where email = 'k.qa@test.ly';
set role authenticated;
select pg_temp.as_user('k.qa@test.ly');
select pg_temp.check(public.is_member(), 'انتهاء مدة القفل يعيد الدخول تلقائياً');

-- حظر جهاز
select pg_temp.as_user('auditor@test.ly', 'aal2');
select pg_temp.check(public.set_device_blocked((select id from user_devices where device_key = 'dev-staff-0001'), true) >= 0, 'CISO يحظر جهازاً');
select pg_temp.check(pg_temp.sessions_of('staff.new@test.ly') = 0,
                     'حظر الجهاز يُخرج الحساب من جلساته');
select pg_temp.as_user('staff.new@test.ly');
select pg_temp.check((select r ->> 'status' = 'blocked' from public.register_device('dev-staff-0001', 'android', '', '2.0.7', null, 'login') r),
                     'الجهاز المحظور يُرفض عند الدخول');
select pg_temp.check((select r ->> 'status' = 'ok' from public.register_device('dev-staff-0002', 'windows', 'حاسوب المكتب', '2.0.7', true, 'login') r),
                     'الأجهزة الأخرى تدخل');
select pg_temp.as_user('auditor@test.ly', 'aal2');
select pg_temp.check(exists (select 1 from audit_log where action = 'security.device_blocked_attempt')
                     and exists (select 1 from public.security_alerts() a where a ->> 'kind' = 'blocked_device_active'),
                     'محاولة الجهاز المحظور مسجّلة وتظهر تنبيهاً');
select public.set_device_blocked((select id from user_devices where device_key = 'dev-staff-0001'), false);
select pg_temp.check((select blocked_at is null from user_devices where device_key = 'dev-staff-0001')
                     and exists (select 1 from audit_log where action = 'security.device_unblock'), 'رفع الحظر');
select pg_temp.expect_error($$select public.set_device_blocked((select d.id from user_devices d join profiles p on p.id = d.user_id
                                                                  where p.role = 'director' limit 1), true)$$, 'CISO يحظر جهاز المدير (أو لا جهاز له)');
reset role;

\echo 'FINANCE SECURITY TESTS PASSED'
