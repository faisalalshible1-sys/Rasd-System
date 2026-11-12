-- اختبارات الترحيل 18: «لا ينطبق» للضمان الابتدائي ولتكليف المهندسين، وتصحيحات الدمج.
-- يُشغَّل بعد تطبيق 20261112000018_na_options.sql مرتين.
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
create or replace function pg_temp.p(p_no text) returns public.projects language sql security definer as $$
  select * from public.projects where assign_no = p_no
$$;
create or replace function pg_temp.st(p_no text, p_form text) returns text language sql security definer as $$
  select coalesce((select status::text from public.project_forms where project_id = pg_temp.pid(p_no) and form_key = p_form), 'todo')
$$;
grant execute on all functions in schema pg_temp to authenticated, anon;

update app_settings set value = 'false' where key in ('security.freeze', 'security.require_mfa_all');

-- ---------------------------------------------------------------- عقود الاختبار
set role authenticated;
select pg_temp.as_user('k.staff@test.ly');
insert into projects (assign_no, name, owner, company, department) values
  ('960', 'عقد ن', 'المالك', 'شركة ن', 'supervision'),
  ('961', 'عمل ن1', 'المالك', 'شركة ن1', 'supervision'),
  ('962', 'عقد م', 'المالك', 'شركة م', 'supervision'),
  ('963', 'عمل م1', 'المالك', 'شركة م1', 'supervision'),
  ('964', 'عمل م2', 'المالك', 'شركة م2', 'supervision');

-- ---------------------------------------------------------------- 1. الضمان الابتدائي
select pg_temp.as_user('k.contracts@test.ly');
select public.set_contract_finance(pg_temp.pid('960'), 100000, 40000, null, null, null, null);
select pg_temp.check((select guarantee_initial = 2000 and guarantee_final = 800 and not guarantee_initial_na from pg_temp.p('960')),
                     'الضمان الابتدائي ينطبق افتراضياً: 5% من المنفذ');

select pg_temp.as_user('k.qa@test.ly');
select pg_temp.expect_error($$select public.set_guarantee_initial_na(pg_temp.pid('960'), true)$$, 'مكتب الجودة يغيّر انطباق الضمان');
select pg_temp.expect_error($$update projects set guarantee_initial_na = true where assign_no = '960'$$, 'تعديل الخانة مباشرة دون الدالة');

select pg_temp.as_user('k.contracts@test.ly');
select pg_temp.expect_error($$select public.set_guarantee_initial_na(pg_temp.pid('960'), null)$$, 'قيمة فارغة');
select public.set_guarantee_initial_na(pg_temp.pid('960'), true);
select pg_temp.check((select guarantee_initial is null and guarantee_final = 800 and guarantee_initial_na from pg_temp.p('960')),
                     'لا ينطبق: لا يُحسب الضمان الابتدائي، والنهائي كما هو');
select pg_temp.check((select count(*) = 1 from public.finance_history(pg_temp.pid('960')) h
                       where h ->> 'action' = 'finance.guarantee_initial' and (h -> 'detail' ->> 'na')::boolean),
                     'التغيير في سجل التعديلات المالية');
select public.set_guarantee_initial_na(pg_temp.pid('960'), true);
select pg_temp.check((select count(*) = 1 from audit_log where action = 'finance.guarantee_initial' and project_id = pg_temp.pid('960')),
                     'التكرار لا يُسجَّل مرتين');
select public.set_contract_finance(pg_temp.pid('960'), 100000, 50000, null, null, null, null);
select pg_temp.check((select guarantee_initial is null and guarantee_final = 1000 from pg_temp.p('960')),
                     'تعديل المنفذ لا يعيد الضمان الابتدائي');
select public.set_guarantee_initial_na(pg_temp.pid('960'), false);
select pg_temp.check((select guarantee_initial = 2500 and (select (detail ->> 'amount')::numeric = 2500 from audit_log
                        where action = 'finance.guarantee_initial' and project_id = pg_temp.pid('960') order by at desc limit 1)
                        from pg_temp.p('960')),
                     'ينطبق من جديد: يُحسب من القيمة المدرجة للأعمال المنفذة');
select public.set_guarantee_initial_na(pg_temp.pid('960'), true);

-- تغيير النسبة يعيد الحساب ويحترم «لا ينطبق»
select pg_temp.as_user('director.new@test.ly', 'aal2');
select public.set_setting('finance.guarantee_initial_rate', '0.1');
select pg_temp.check((select guarantee_initial is null from pg_temp.p('960')), 'تغيير النسبة لا يعيد ضماناً لا ينطبق');
select public.set_setting('finance.guarantee_initial_rate', '0.05');

-- ---------------------------------------------------------------- 2. مهندس السلامة لا ينطبق
select pg_temp.as_user('k.staff@test.ly');
select public.set_form_status(pg_temp.pid('960'), 'f07', 'na');
select pg_temp.check((select eng_saf = 'لا ينطبق' from pg_temp.p('960')), 'الخانة النصية تُظهر «لا ينطبق»');
select pg_temp.expect_error($$select public.save_engineer(null, pg_temp.pid('960'), 'saf', 'مهندس سلامة ن', '', null, null, '')$$,
                            'تكليف مهندس سلامة والنموذج «لا ينطبق»');
select pg_temp.check(public.save_engineer(null, pg_temp.pid('960'), 'sup', 'مهندس مشرف ن', '7', null, null, '') is not null,
                     'بقية الأنواع تُكلَّف كالمعتاد');
select public.set_form_status(pg_temp.pid('960'), 'f07', 'todo');
select pg_temp.check((select eng_saf = '' from pg_temp.p('960')), 'إلغاء «لا ينطبق» يفرغ الخانة');
select public.save_engineer(null, pg_temp.pid('960'), 'saf', 'مهندس سلامة ن', '8', null, null, '');
select pg_temp.expect_error($$select public.set_form_status(pg_temp.pid('960'), 'f07', 'na')$$, '«لا ينطبق» وفي العقد مهندس سلامة مكلّف');
select pg_temp.check(pg_temp.st('960', 'f07') = 'todo' and (select eng_saf = 'مهندس سلامة ن' from pg_temp.p('960')),
                     'الحالة والاسم كما هما بعد الرفض');
select public.delete_engineer((select id from contract_engineers where project_id = pg_temp.pid('960') and kind = 'saf'));
select public.set_form_status(pg_temp.pid('960'), 'f07', 'na');
select pg_temp.check(pg_temp.st('960', 'f07') = 'na' and (select eng_saf = 'لا ينطبق' from pg_temp.p('960')),
                     'بعد إلغاء التكليف يُسجَّل «لا ينطبق»');

-- ---------------------------------------------------------------- 3. الدمج مع «لا ينطبق»
select public.save_engineer(null, pg_temp.pid('961'), 'saf', 'مهندس سلامة ن1', '9', null, null, '');
select public.set_form_status(pg_temp.pid('961'), 'f07', 'done');
select pg_temp.as_user('k.contracts@test.ly');
select public.set_contract_finance(pg_temp.pid('961'), 20000, 10000, null, null, null, null);
select pg_temp.check((select guarantee_initial = 500 from pg_temp.p('961')), 'العمل المدمج يُحسب له الضمان');
select pg_temp.check(public.merge_contracts(pg_temp.pid('960'), array[pg_temp.pid('961')]) = 1, 'دمج عمل فيه مهندس سلامة في عقد «لا ينطبق»');
select pg_temp.check(pg_temp.st('960', 'f07') = 'wip', 'النموذج يعود إلى «قيد الإنجاز» بدل التناقض');
select pg_temp.check((select eng_saf = 'مهندس سلامة ن1' from pg_temp.p('960')), 'المهندس المدمج يظهر في العقد');
select pg_temp.check((select count(*) = 1 from audit_log where action = 'form.set' and project_id = pg_temp.pid('960')
                        and form_key = 'f07' and detail ->> 'reason' is not null), 'تغيير الحالة مسجّل بسببه');
select pg_temp.check((select guarantee_initial is null and executed_value = 60000 from pg_temp.p('960')),
                     'العقد المستهدف يحتفظ بخيار «لا ينطبق» للضمان بعد الدمج');

select pg_temp.as_user('director.new@test.ly', 'aal2');
select public.unmerge_contract(pg_temp.pid('961'));
select pg_temp.check((select eng_saf = 'مهندس سلامة ن1' and guarantee_initial = 500 from pg_temp.p('961'))
                     and (select eng_saf = '' and guarantee_initial is null from pg_temp.p('960')),
                     'فك الدمج: المهندس والضمان يعودان إلى العمل');

-- العكس: عقد فيه مهندس سلامة وحالته «لم يبدأ» يُدمج فيه عمل مسجّل «لا ينطبق»
select pg_temp.as_user('k.staff@test.ly');
select public.set_form_status(pg_temp.pid('960'), 'f07', 'todo');
select public.save_engineer(null, pg_temp.pid('962'), 'saf', 'مهندس سلامة م', '10', null, null, '');
select public.set_form_status(pg_temp.pid('964'), 'f07', 'na');
select pg_temp.as_user('k.contracts@test.ly');
select public.merge_contracts(pg_temp.pid('962'), array[pg_temp.pid('964')]);
select pg_temp.check(pg_temp.st('962', 'f07') = 'todo' and (select eng_saf = 'مهندس سلامة م' from pg_temp.p('962')),
                     '«لا ينطبق» من العمل المدمج لا يُسقط تكليفاً قائماً في العقد');
select pg_temp.as_user('director.new@test.ly', 'aal2');
select public.unmerge_contract(pg_temp.pid('964'));

-- ---------------------------------------------------------------- 4. الدمج المتسلسل والدفعات اليدوية
select pg_temp.as_user('k.contracts@test.ly');
select public.set_contract_finance(pg_temp.pid('962'), null, null, 100, null, null, 7);
select public.set_contract_finance(pg_temp.pid('963'), null, null, 50, null, null, null);
select public.set_contract_finance(pg_temp.pid('964'), null, null, 10, 5, null, null);
select public.merge_contracts(pg_temp.pid('963'), array[pg_temp.pid('964')]);
select pg_temp.check((select payment_first = 60 and payment_second = 5 from pg_temp.p('963')), 'الدمج الأول يجمع الدفعات');
select public.merge_contracts(pg_temp.pid('962'), array[pg_temp.pid('963')]);
select pg_temp.check((select payment_first = 160 and payment_second = 5 and deductions = 7 from pg_temp.p('962')),
                     'الدمج المتسلسل يجمع كل الدفعات مرة واحدة');
select pg_temp.check((select merged_into = pg_temp.pid('962') from pg_temp.p('964')), 'العمل المدمج سابقاً يتبع العقد مباشرة');
select pg_temp.check((select payment_first = 50 and payment_second = 0 from pg_temp.p('963')),
                     'صف المصدر يحتفظ بدفعاته وحده بعد نقل ما دُمج فيه');

select pg_temp.as_user('director.new@test.ly', 'aal2');
select public.unmerge_contract(pg_temp.pid('964'));
select pg_temp.check((select payment_first = 150 and payment_second = 0 from pg_temp.p('962')), 'فك أول عمل يطرح دفعاته وحدها');
select public.unmerge_contract(pg_temp.pid('963'));
select pg_temp.check((select payment_first = 100 and deductions = 7 from pg_temp.p('962'))
                     and (select payment_first = 50 from pg_temp.p('963'))
                     and (select payment_first = 10 and payment_second = 5 from pg_temp.p('964')),
                     'فك الدمج المتسلسل يعيد لكلٍّ دفعاته دون طرح مزدوج');

-- ---------------------------------------------------------------- 5. ملاحظات التقييم تعود مع العمل
select pg_temp.as_user('k.qa@test.ly');
insert into quality_notes (project_id, body, origin_project) values (pg_temp.pid('963'), 'ملاحظة على العمل م1', pg_temp.pid('962'));
select pg_temp.check((select origin_project is null from quality_notes where body = 'ملاحظة على العمل م1'),
                     'لا يُحدَّد أصل الملاحظة من التطبيق');
select pg_temp.as_user('k.contracts@test.ly');
select public.merge_contracts(pg_temp.pid('962'), array[pg_temp.pid('963')]);
select pg_temp.check((select project_id = pg_temp.pid('962') from quality_notes where body = 'ملاحظة على العمل م1'),
                     'الملاحظة تنتقل إلى العقد عند الدمج');
select pg_temp.as_user('director.new@test.ly', 'aal2');
select public.unmerge_contract(pg_temp.pid('963'));
select pg_temp.check((select project_id = pg_temp.pid('963') and origin_project is null from quality_notes where body = 'ملاحظة على العمل م1'),
                     'وتعود إلى العمل عند فك الدمج');

reset role;
select 'NA OPTIONS TESTS PASSED';
