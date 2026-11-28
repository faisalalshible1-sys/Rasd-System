-- اختبارات الترحيل 54: سلسلة سجل التدقيق
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
  begin execute p_sql; exception when others then raise notice 'PASS (رُفض كما يجب): % — %', p_label, sqlerrm; return; end;
  raise exception 'FAIL: كان يجب رفض: %', p_label;
end $$;
create or replace function pg_temp.check(p_ok boolean, p_label text) returns void language plpgsql as $$
begin
  if not coalesce(p_ok, false) then raise exception 'FAIL: %', p_label; end if;
  raise notice 'PASS: %', p_label;
end $$;

select pg_temp.check((select count(*) = 0 from public.audit_log where row_hash is null), 'كل أحداث السجل مسلسلة');
select pg_temp.check((select count(*) = count(distinct chain_no) from public.audit_log), 'أرقام السلسلة فريدة');

-- كتابة حدث جديد تمدّ السلسلة
select public.write_audit('test.chain', null, null, '{"k": 1}'::jsonb, 'اختبار السلسلة');
select public.write_audit('test.chain', null, null, '{"k": 2}'::jsonb, 'اختبار السلسلة');
select pg_temp.check((select b.prev_hash = a.row_hash and b.chain_no = a.chain_no + 1
                        from (select * from public.audit_log order by chain_no desc limit 1 offset 1) a,
                             (select * from public.audit_log order by chain_no desc limit 1) b), 'الحدث الجديد يرتبط ببصمة سابقه');

-- التحقق (المدير)
select pg_temp.as_user('director.new@test.ly', 'aal2');
set role authenticated;
select pg_temp.check((select (public.security_audit_verify() ->> 'ok')::boolean), 'السلسلة سليمة');
select pg_temp.check((select (public.security_audit_verify() ->> 'head_hash') = (select row_hash from public.audit_log order by chain_no desc limit 1)), 'رأس السلسلة يطابق آخر حدث');
reset role;

-- لا تعديل ولا حذف ولا تفريغ، حتى بصلاحية المالك
select pg_temp.expect_error($q$update public.audit_log set action = 'x' where chain_no = 1$q$, 'تعديل حدث');
select pg_temp.expect_error($q$delete from public.audit_log where chain_no = 1$q$, 'حذف حدث');
select pg_temp.expect_error($q$truncate public.audit_log$q$, 'تفريغ السجل');

-- كشف التلاعب: نعطّل الحارس ونغيّر محتوى حدث، فيكشفه الفحص ثم نعيد الحال
alter table public.audit_log disable trigger audit_chain_guard_trg;
update public.audit_log set detail = '{"k": 99}'::jsonb where chain_no = (select max(chain_no) - 1 from public.audit_log);
select pg_temp.as_user('director.new@test.ly', 'aal2');
set role authenticated;
select pg_temp.check(not (public.security_audit_verify() ->> 'ok')::boolean and (public.security_audit_verify() ->> 'reason') = 'محتوى الحدث عُدِّل', 'الفحص يكشف تعديل محتوى حدث');
reset role;
update public.audit_log set detail = '{"k": 1}'::jsonb where chain_no = (select max(chain_no) - 1 from public.audit_log);
-- كشف الحذف من الوسط
create temp table _saved as select * from public.audit_log where chain_no = (select max(chain_no) - 1 from public.audit_log);
delete from public.audit_log where chain_no = (select max(chain_no) - 1 from public.audit_log);
select pg_temp.as_user('director.new@test.ly', 'aal2');
set role authenticated;
select pg_temp.check(not (public.security_audit_verify() ->> 'ok')::boolean, 'الفحص يكشف حذف حدث من الوسط');
reset role;
alter table public.audit_log disable trigger audit_chain_insert_trg;
insert into public.audit_log overriding system value select * from _saved;
alter table public.audit_log enable trigger audit_chain_insert_trg;
alter table public.audit_log enable trigger audit_chain_guard_trg;
select pg_temp.as_user('director.new@test.ly', 'aal2');
set role authenticated;
select pg_temp.check((public.security_audit_verify() ->> 'ok')::boolean, 'السلسلة سليمة بعد إعادة الحال');
reset role;

-- الصلاحيات
select pg_temp.as_user('k.staff@test.ly');
set role authenticated;
select pg_temp.expect_error($q$select public.security_audit_verify()$q$, 'موظف المكتب لا يفحص السلسلة');
reset role;
