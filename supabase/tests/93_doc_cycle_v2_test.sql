-- اختبارات الترحيل 19: الدورة المستندية للعقود – الإصدار 2 المعتمد.
-- يُشغَّل بعد تطبيق 20261112000019_doc_cycle_v2.sql مرتين.
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
create or replace function pg_temp.st(p_no text, p_form text) returns text language sql security definer as $$
  select coalesce((select status::text from public.project_forms where project_id = pg_temp.pid(p_no) and form_key = p_form), 'todo')
$$;
grant execute on all functions in schema pg_temp to authenticated, anon;

update app_settings set value = 'false' where key in ('security.freeze', 'security.require_mfa_all');
update app_settings set value = 'true' where key = 'security.signups_open';
insert into auth.users (email, raw_user_meta_data) values ('k.headacc@test.ly', '{"full_name":"رئيس المطابقة ك"}');
set role authenticated;
select pg_temp.as_user('director.new@test.ly', 'aal2');
select public.set_user_access((select id from profiles where email = 'k.headacc@test.ly'), 'dept_head', 'acceptance', true);
reset role;
select pg_temp.as_user('');

-- ---------------------------------------------------------------- البنية
select pg_temp.check((select string_agg(name, ' / ' order by idx) from stages) =
  'التعاقد والإعداد الفني / أمر العمل وتسليم الموقع / التنفيذ والمستخلصات الجارية / الاستلام الابتدائي والمستخلص الختامي / الاستلام النهائي وإقفال العقد',
  'المراحل الخمس بأسمائها المعتمدة');
select pg_temp.check((select string_agg(name, ' / ' order by sort) from form_defs) =
  'أمر بالتعاقد / نطاق وطريقة عمل / مقايسة تقديرية / ملحق فني / نموذج عقد أشغال عامة / '
  'أمر عمل / تكليف مهندس إشراف / تكليف مهندس حصر / تكليف مهندس متابعة / تكليف مهندس سلامة / محضر تسليم موقع عمل / تصريح عمل / '
  'ورقة قياس نموذج أ / ورقة قياس نموذج ب / محضر حصر كميات / كشف حصر مستخلص / مستخلص جاري / شهادة دفع مستخلص / مراجعة مستخلص / اعتماد مستخلص / '
  'تكليف لجنة استلام ابتدائي / محضر استلام ابتدائي / مستخلص ختامي / '
  'تكليف لجنة استلام نهائي / محضر استلام نهائي / إقفال عقد',
  'الترتيب المعتمد: 25 بنداً ومعها تكليف مهندس سلامة');
select pg_temp.check((select string_agg(n::text, ',' order by stage) from (select stage, count(*) n from form_defs group by stage) x) = '5,7,8,3,3',
  'عدد النماذج في كل مرحلة');
select pg_temp.check((select bool_and(active) and count(*) = 26 and count(distinct sort) = 26 and min(sort) = 1 and max(sort) = 26 from form_defs),
  'كل النماذج فعّالة وترتيبها متصل');
select pg_temp.check(public.engineer_form('sup') = 'f04' and public.engineer_form('qty') = 'f05'
                     and public.engineer_form('fol') = 'f06' and public.engineer_form('saf') = 'f07',
  'نماذج تكليف المهندسين كما هي');
select pg_temp.check((select sensitive from form_defs where key = 'f01') is not null
                     and (select count(*) = 7 from form_defs where key in ('f20','f21','f22','f23','f24','f25','f26') and not sensitive),
  'النماذج السبعة الجديدة');
select pg_temp.check((select count(*) = 1 from audit_log where action = 'config.form_order' and detail ->> 'reason' like '%الإصدار 2%'),
  'الاعتماد مسجّل مرة واحدة رغم تشغيل الملف مرتين');

-- ---------------------------------------------------------------- جهات التنفيذ والمتابعة
set role authenticated;
select pg_temp.as_user('k.staff@test.ly');
insert into projects (assign_no, name, owner, company, department) values ('970', 'عقد الدورة 2', 'المالك', 'شركة', 'supervision');
select public.set_form_status(pg_temp.pid('970'), 'f20', 'done');
select pg_temp.check(pg_temp.st('970', 'f20') = 'done', 'موظف مكتب المدير يحدّث النماذج الجديدة');

select pg_temp.as_user('k.headtech@test.ly');
select public.set_form_status(pg_temp.pid('970'), 'f19', 'done');
select pg_temp.expect_error($$select public.set_form_status(pg_temp.pid('970'), 'f12', 'done')$$, 'كشف الحصر انتقل من الشؤون الفنية إلى المطابقة والاستلام');
select pg_temp.expect_error($$select public.save_engineer(null, pg_temp.pid('970'), 'qty', 'مهندس حصر', '1', null, null, '')$$,
  'تكليف مهندس الحصر لم يعد للشؤون الفنية');

select pg_temp.as_user('k.headacc@test.ly');
-- (النموذج الحساس يُسجَّل طلباً بانتظار الاعتماد؛ المهم هنا أنه من اختصاص القسم)
select pg_temp.check(public.set_form_status(pg_temp.pid('970'), 'f12', 'done') in ('applied', 'pending')
                     and public.set_form_status(pg_temp.pid('970'), 'f13', 'wip') in ('applied', 'pending')
                     and public.set_form_status(pg_temp.pid('970'), 'f22', 'done') = 'applied'
                     and pg_temp.st('970', 'f22') = 'done',
  'قسم المطابقة والاستلام: كشف الحصر وشهادة الدفع ومحضر حصر الكميات');
select pg_temp.check(public.save_engineer(null, pg_temp.pid('970'), 'qty', 'مهندس حصر', '1', null, null, '') is not null,
  'وتكليف مهندس الحصر');
select pg_temp.expect_error($$select public.set_form_status(pg_temp.pid('970'), 'f25', 'done')$$, 'تكليف لجنة الاستلام لمدير المكتب');

select pg_temp.as_user('k.qa@test.ly');
select public.set_form_status(pg_temp.pid('970'), 'f06', 'wip');
select pg_temp.check(pg_temp.st('970', 'f06') = 'wip', 'تكليف مهندس المتابعة لقسم المتابعة وتقييم الأداء');
select pg_temp.check(public.save_engineer(null, pg_temp.pid('970'), 'fol', 'مهندس متابعة', '2', null, null, '') is not null,
  'ومنه يُكلَّف مهندس المتابعة');

select pg_temp.as_user('k.contracts@test.ly');
select pg_temp.expect_error($$select public.set_form_status(pg_temp.pid('970'), 'f02', 'done')$$, 'أمر العمل لرئيس اللجنة (يسجّله مكتب المدير)');
select public.set_form_status(pg_temp.pid('970'), 'f23', 'done');
select pg_temp.check(pg_temp.st('970', 'f23') = 'done', 'مراجعة المستخلص لمكتب العقود');
select pg_temp.expect_error($$select public.set_form_status(pg_temp.pid('970'), 'f24', 'done')$$, 'اعتماد المستخلص لرئيس اللجنة');
select public.set_contract_finance(pg_temp.pid('970'), 1000, 500, null, null, null, null);
select pg_temp.check((select executed_value = 500 from projects where assign_no = '970'), 'البيانات المالية ما زالت لمكتب العقود عبر «أمر بالتعاقد»');

select pg_temp.as_user('k.headsup@test.ly');
select public.set_form_status(pg_temp.pid('970'), 'f07', 'na');
select pg_temp.check(pg_temp.st('970', 'f07') = 'na', 'مهندس السلامة «لا ينطبق» من قسم الإشراف');
select pg_temp.expect_error($$select public.set_form_status(pg_temp.pid('970'), 'f10', 'done')$$, 'ورقة القياس انتقلت إلى المطابقة والاستلام');

reset role;
select 'DOC CYCLE V2 TESTS PASSED';
