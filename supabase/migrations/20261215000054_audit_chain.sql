-- الإصدار 3.5.0 — الترحيل 54: سجل تدقيق محصَّن ضد التلاعب.
--
-- كل حدث في audit_log يحمل بصمة SHA-256 تربطه بما قبله (سلسلة)، فيُكشف أي تعديل أو حذف أو إدراج في الوسط.
-- لا يُعدَّل السجل ولا يُحذف ولا يُفرَّغ حتى من المالك عبر الواجهة؛ وتفحص security_audit_verify() السلسلة كاملة.
-- يُسلسَل السجل القائم مرة واحدة بترتيب (at, id). يعمل الملف مرتين دون ضرر.

alter table public.audit_log add column if not exists chain_no bigint;
alter table public.audit_log add column if not exists prev_hash text;
alter table public.audit_log add column if not exists row_hash text;
create unique index if not exists audit_log_chain_no_idx on public.audit_log (chain_no) where chain_no is not null;

-- بصمة الصف: حقوله القانونية + بصمة السابق.
create or replace function public.audit_row_hash(p public.audit_log, p_prev text)
returns text language sql immutable set search_path = public
as $$
  select encode(sha256(convert_to(concat_ws('|', p.chain_no, extract(epoch from p.at)::text, coalesce(p.actor::text, ''),
    p.actor_name, coalesce(p.project_id::text, ''), p.project_label, p.action, coalesce(p.form_key, ''),
    p.detail::text, coalesce(p_prev, '')), 'UTF8')), 'hex')
$$;

-- إدراج: يأخذ رقم السلسلة وبصمة السابق تحت قفل يسلسل المدخلين.
create or replace function public.audit_chain_insert()
returns trigger language plpgsql security definer set search_path = public
as $$
declare v_last record;
begin
  perform pg_advisory_xact_lock(7305401);
  select chain_no, row_hash into v_last from public.audit_log where chain_no is not null order by chain_no desc limit 1;
  new.chain_no := coalesce(v_last.chain_no, 0) + 1;
  new.prev_hash := v_last.row_hash;
  new.row_hash := public.audit_row_hash(new, new.prev_hash);
  return new;
end;
$$;

-- لا تعديل ولا حذف إلا لتسلسل صف قديم لم تُحسب بصمته (مرة واحدة عند الترحيل).
create or replace function public.audit_chain_guard()
returns trigger language plpgsql set search_path = public
as $$
begin
  if tg_op = 'UPDATE' and old.row_hash is null and current_setting('app.audit_backfill', true) = 'on' then
    return new;
  end if;
  raise exception 'سجل التدقيق لا يُعدَّل ولا يُحذف' using errcode = '42501';
end;
$$;

drop trigger if exists audit_chain_insert_trg on public.audit_log;
create trigger audit_chain_insert_trg before insert on public.audit_log
  for each row execute function public.audit_chain_insert();
drop trigger if exists audit_chain_guard_trg on public.audit_log;
create trigger audit_chain_guard_trg before update or delete on public.audit_log
  for each row execute function public.audit_chain_guard();
drop trigger if exists audit_chain_truncate_trg on public.audit_log;
create trigger audit_chain_truncate_trg before truncate on public.audit_log
  for each statement execute function public.audit_chain_guard();

-- تسلسل السجل القائم مرة واحدة.
do $m$
declare r record; v_prev text; v_no bigint;
begin
  if exists (select 1 from public.audit_log where row_hash is null) then
    perform pg_advisory_xact_lock(7305401);
    perform set_config('app.audit_backfill', 'on', true);
    select coalesce(max(chain_no), 0), (select row_hash from public.audit_log where chain_no is not null order by chain_no desc limit 1)
      into v_no, v_prev from public.audit_log where chain_no is not null;
    for r in select id from public.audit_log where row_hash is null order by at, id loop
      v_no := v_no + 1;
      update public.audit_log a set chain_no = v_no, prev_hash = v_prev where a.id = r.id;
      update public.audit_log a set row_hash = public.audit_row_hash(a, v_prev) where a.id = r.id returning a.row_hash into v_prev;
    end loop;
    perform set_config('app.audit_backfill', 'off', true);
  end if;
end $m$;

-- فحص السلسلة كاملة: يعيد أول صف مكسور إن وُجد، ورأس السلسلة لتثبيته خارج القاعدة.
create or replace function public.security_audit_verify()
returns jsonb language plpgsql stable security definer set search_path = public
as $$
declare
  r public.audit_log; v_prev text := null; v_n bigint := 0; v_expect bigint := 1; v_bad bigint := null; v_why text := null;
begin
  if not public.can_audit() then
    raise exception 'فحص سلامة السجل لمدير المكتب وCISO' using errcode = '42501';
  end if;
  for r in select * from public.audit_log order by chain_no nulls last, id loop
    v_n := v_n + 1;
    if r.chain_no is null or r.row_hash is null then
      v_bad := coalesce(r.chain_no, r.id); v_why := 'حدث بلا بصمة'; exit;
    elsif r.chain_no <> v_expect then
      v_bad := r.chain_no; v_why := 'انقطاع في الترقيم (حدث محذوف أو مُدرَج)'; exit;
    elsif r.prev_hash is distinct from v_prev then
      v_bad := r.chain_no; v_why := 'بصمة السابق لا تطابق'; exit;
    elsif r.row_hash <> public.audit_row_hash(r, v_prev) then
      v_bad := r.chain_no; v_why := 'محتوى الحدث عُدِّل'; exit;
    end if;
    v_prev := r.row_hash;
    v_expect := v_expect + 1;
  end loop;
  return jsonb_build_object('ok', v_bad is null, 'checked', v_n, 'total', (select count(*) from public.audit_log),
    'bad_chain_no', v_bad, 'reason', v_why, 'head_no', v_expect - 1, 'head_hash', v_prev, 'at', now());
end;
$$;

revoke all on function public.audit_row_hash(public.audit_log, text) from public, anon;
revoke all on function public.audit_chain_insert() from public, anon, authenticated;
revoke all on function public.audit_chain_guard() from public, anon, authenticated;
revoke all on function public.security_audit_verify() from public, anon;
grant execute on function public.security_audit_verify() to authenticated, service_role;
grant execute on function public.audit_row_hash(public.audit_log, text) to service_role;
