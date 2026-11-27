-- اختبارات الترحيل 46: ميزانية المكتب والالتزامات
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

update app_settings set value = 'false' where key in ('security.freeze', 'security.require_mfa_all');
update profiles set locked_until = null where email in ('director.new@test.ly', 'u.qc@test.ly', 'k.qa@test.ly', 'k.staff@test.ly', 'pending@test.ly');
create or replace function pg_temp.uid(p_email text) returns uuid language sql security definer as $$ select id from auth.users where email = p_email $$;
create temp table ids (k text primary key, v uuid);
grant all on ids to authenticated;
insert into ids select 'proj', id from public.projects order by created_at limit 1;

-- المدير يعرّف بنداً
select pg_temp.as_user('director.new@test.ly', 'aal2');
set role authenticated;
insert into ids select 'l1', public.budget_line_save(null, 2026, 'الباب الثاني', 'صيانة المباني', 100000, '');
select pg_temp.check((select count(*) from public.budget_lines where name = 'صيانة المباني' and allocated = 100000) = 1, 'تعريف بند');
select pg_temp.expect_error($q$select public.budget_line_save(null, 2026, 'الباب الثاني', ' صيانة المباني ', 5)$q$, 'اسم مكرر في السنة');
select public.budget_line_save(null, 2027, 'الباب الثاني', 'صيانة المباني', 5);
select pg_temp.expect_error($q$select public.budget_line_save(null, 1999, 'ب', 'س', 5)$q$, 'سنة غير صالحة');
select pg_temp.expect_error($q$select public.budget_line_save(null, 2026, 'ب', 'س', -1)$q$, 'مخصص سالب');
select pg_temp.expect_error($q$insert into public.budget_lines (fiscal_year, category, name, allocated) values (2026, 'ب', 'مباشر', 1)$q$, 'لا كتابة مباشرة على البنود');

-- الالتزامات
insert into ids select 'c1', public.budget_commit_save(null, (select v from ids where k = 'l1'), (select v from ids where k = 'proj'), 'صيانة السقف', 60000, 10000, current_date, '');
select pg_temp.check((select coalesce(sum(amount), 0) from public.budget_commitments where line_id = (select v from ids where k = 'l1') and status = 'active') = 60000, 'الملتزم النشط');
select pg_temp.expect_error(format($q$select public.budget_commit_save(null, %L, null, 'تجاوز', 50000, 0, current_date)$q$, (select v from ids where k = 'l1')), 'التزام يتجاوز المتبقي');
select pg_temp.expect_error(format($q$select public.budget_commit_save(null, %L, null, 'مدفوع أكبر', 1000, 2000, current_date)$q$, (select v from ids where k = 'l1')), 'مدفوع يتجاوز الملتزم');
select pg_temp.expect_error(format($q$select public.budget_commit_save(null, %L, null, '', 1000, 0, current_date)$q$, (select v from ids where k = 'l1')), 'وصف فارغ');
select pg_temp.expect_error(format($q$select public.budget_commit_save(null, %L, null, 'س', 0, 0, current_date)$q$, (select v from ids where k = 'l1')), 'مبلغ صفر');
insert into ids select 'c2', public.budget_commit_save(null, (select v from ids where k = 'l1'), null, 'دهان', 40000, 0, current_date, '');
select pg_temp.expect_error(format($q$select public.budget_line_save(%L, 2026, 'الباب الثاني', 'صيانة المباني', 90000)$q$, (select v from ids where k = 'l1')), 'تخفيض المخصص دون الملتزم');
select public.budget_commit_save((select v from ids where k = 'c1'), (select v from ids where k = 'l1'), null, 'صيانة السقف', 55000, 55000, current_date, 'عُدّل');
select pg_temp.check((select amount = 55000 and paid = 55000 and project_id is null from public.budget_commitments where id = (select v from ids where k = 'c1')), 'تعديل الالتزام');
select pg_temp.expect_error(format($q$select public.budget_line_delete(%L)$q$, (select v from ids where k = 'l1')), 'لا يُحذف بند له التزامات');
-- الإفراج وإعادة التفعيل
select public.budget_commit_status((select v from ids where k = 'c2'), 'released');
select pg_temp.check((select coalesce(sum(amount), 0) from public.budget_commitments where line_id = (select v from ids where k = 'l1') and status = 'active') = 55000, 'المفرَج عنه لا يُحسب');
insert into ids select 'c3', public.budget_commit_save(null, (select v from ids where k = 'l1'), null, 'عمل جديد', 45000, 0, current_date, '');
select pg_temp.expect_error(format($q$select public.budget_commit_status(%L, 'active')$q$, (select v from ids where k = 'c2')), 'إعادة تفعيل لا يتسع لها البند');
select pg_temp.expect_error(format($q$select public.budget_commit_status(%L, 'x')$q$, (select v from ids where k = 'c2')), 'حالة غير معروفة');
reset role;

-- موظف المكتب يسجّل الالتزامات ولا يعرّف ولا يحذف
select pg_temp.as_user('k.staff@test.ly');
set role authenticated;
select public.budget_line_save(null, 2026, 'ب', 'بند موظف', 1) where false;
select pg_temp.expect_error($q$select public.budget_line_save(null, 2026, 'ب', 'بند موظف', 1)$q$, 'موظف المكتب لا يعرّف بنداً');
insert into ids select 'c4', public.budget_commit_save(null, (select v from ids where k = 'l1'), null, 'عمل موظف', 100, 0, current_date, '') where false;
select pg_temp.expect_error(format($q$select public.budget_commit_delete(%L)$q$, (select v from ids where k = 'c1')), 'موظف المكتب لا يحذف التزاماً');
reset role;
select pg_temp.as_user('pending@test.ly');
set role authenticated;
select pg_temp.expect_error(format($q$select public.budget_commit_save(null, %L, null, 'x', 1, 0, current_date)$q$, (select v from ids where k = 'l1')), 'حساب معلّق لا يسجّل التزاماً');
select pg_temp.check((select count(*) from public.budget_lines) = 0, 'الحساب المعلّق لا يقرأ الميزانية');
reset role;

-- الحذف والتدقيق
select pg_temp.as_user('director.new@test.ly', 'aal2');
set role authenticated;
select public.budget_commit_delete((select v from ids where k = 'c3'));
select public.budget_commit_delete((select v from ids where k = 'c2'));
select public.budget_commit_delete((select v from ids where k = 'c1'));
select public.budget_line_delete((select v from ids where k = 'l1'));
select pg_temp.check((select count(*) from public.budget_lines where id = (select v from ids where k = 'l1')) = 0, 'حذف بند بلا التزامات');
reset role;
select pg_temp.check((select count(*) from public.audit_log where action = 'budget.line_save') = 2
  and (select count(*) from public.audit_log where action = 'budget.commit_save') = 4
  and (select count(*) from public.audit_log where action = 'budget.commit_status') = 1
  and (select count(*) from public.audit_log where action = 'budget.commit_delete') = 3
  and (select count(*) from public.audit_log where action = 'budget.line_delete') = 1, 'كل إجراء مسجَّل بعدده');
