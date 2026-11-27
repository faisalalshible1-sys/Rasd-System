-- =====================================================================
-- الإصدار 3.3.0 (الترحيل 50): المحاسبة (دليل الحسابات وقيود اليومية المزدوجة والأستاذ وميزان المراجعة)
--
--  fin_gl_accounts: دليل الحسابات (أصول وخصوم وحقوق ملكية وإيرادات ومصروفات) بشجرة؛ لا قيد إلا على حساب فرعي مفعّل (قابل للترحيل إليه).
--  fin_journals / fin_journal_lines: قيود مزدوجة (مجموع المدين = مجموع الدائن). قيد يدوي: مسودة ثم ترحيل بموافقة من يملك الاعتماد؛
--      والقيد المرحَّل لا يُعدَّل ولا يُحذف (يمنع ذلك مشغّل) ويُصحَّح بقيد عكسي مسبَّب. القيود الآلية تُنشأ مرحَّلة من مصدرها.
--  fin_gl_map: تعيين حسابات القيود الآلية لكشف المرتبات. fin_accounts.gl_account_id: ربط كل حساب مالي (الخزينة والمصرف) بحساب أصل.
--  قيد كشف المرتبات عند الاعتماد: مدين الرواتب والأجور (الإجمالي − الغياب)، دائن المرتبات المستحقة (الصافي) والتأمينات والضرائب
--      (الضريبة + القاعدة الإضافية) والاستقطاعات الأخرى وسلف الموظفين (الأقساط)؛ ويُعكس تلقائياً عند التراجع عن الكشف.
--  قيد التحويل عند الترحيل: مدين حساب المستلِم ودائن حساب المحوَّل منه، ولا يُرحَّل تحويل لحساب غير مربوط.
--  القراءة لمن له اطّلاع مالي، والتحرير بصلاحية التحرير، والترحيل والعكس والتعيين بصلاحية الاعتماد، بدوال تسجّل في سجل التدقيق.
--  يُشغَّل بعد 20261210000049_guarantees.sql، وإعادة تشغيله آمنة. التراجع: supabase/rollbacks/20261211000050_accounting_down.sql
-- =====================================================================
create table if not exists public.fin_gl_accounts (
  id         uuid primary key default gen_random_uuid(),
  code       text not null check (code ~ '^[0-9A-Za-z.-]{1,12}$'),
  name       text not null check (length(btrim(name)) between 1 and 100),
  type       text not null check (type in ('asset', 'liability', 'equity', 'revenue', 'expense')),
  parent_id  uuid references public.fin_gl_accounts (id) on delete restrict,
  postable   boolean not null default true,
  active     boolean not null default true,
  created_at timestamptz not null default now(),
  created_by uuid references public.profiles (id) on delete set null
);
create unique index if not exists fin_gl_accounts_code_uidx on public.fin_gl_accounts (code);
create index if not exists fin_gl_accounts_parent_idx on public.fin_gl_accounts (parent_id);
create index if not exists fin_gl_accounts_created_by_idx on public.fin_gl_accounts (created_by);

create sequence if not exists public.fin_journal_seq;

create table if not exists public.fin_journals (
  id             uuid primary key default gen_random_uuid(),
  entry_no       integer unique,
  entry_date     date not null,
  memo           text not null check (length(btrim(memo)) between 1 and 300),
  source         text not null default 'manual' check (source in ('manual', 'payroll', 'payroll_reversal', 'transfer')),
  source_id      uuid,
  status         text not null default 'draft' check (status in ('draft', 'posted')),
  reverses       uuid references public.fin_journals (id) on delete restrict,
  reversed_by    uuid references public.fin_journals (id) on delete restrict,
  reverse_reason text not null default '' check (length(reverse_reason) <= 300),
  created_at     timestamptz not null default now(),
  created_by     uuid references public.profiles (id) on delete set null,
  posted_at      timestamptz,
  posted_by      uuid references public.profiles (id) on delete set null
);
create index if not exists fin_journals_date_idx on public.fin_journals (entry_date);
create index if not exists fin_journals_source_idx on public.fin_journals (source, source_id);
create index if not exists fin_journals_reverses_idx on public.fin_journals (reverses);
create index if not exists fin_journals_reversed_by_idx on public.fin_journals (reversed_by);
create index if not exists fin_journals_created_by_idx on public.fin_journals (created_by);
create index if not exists fin_journals_posted_by_idx on public.fin_journals (posted_by);

create table if not exists public.fin_journal_lines (
  id         uuid primary key default gen_random_uuid(),
  journal_id uuid not null references public.fin_journals (id) on delete cascade,
  line_no    integer not null,
  account_id uuid not null references public.fin_gl_accounts (id) on delete restrict,
  debit      numeric(18, 3) not null default 0 check (debit >= 0),
  credit     numeric(18, 3) not null default 0 check (credit >= 0),
  memo       text not null default '' check (length(memo) <= 200),
  check ((debit = 0) <> (credit = 0)),
  unique (journal_id, line_no)
);
create index if not exists fin_journal_lines_account_idx on public.fin_journal_lines (account_id);

create table if not exists public.fin_gl_map (
  key        text primary key check (key in ('payroll_expense', 'payroll_net', 'payroll_insurance', 'payroll_tax', 'payroll_other', 'payroll_loan')),
  account_id uuid not null references public.fin_gl_accounts (id) on delete restrict
);
create index if not exists fin_gl_map_account_idx on public.fin_gl_map (account_id);

alter table public.fin_accounts add column if not exists gl_account_id uuid references public.fin_gl_accounts (id) on delete restrict;
create unique index if not exists fin_accounts_gl_uidx on public.fin_accounts (gl_account_id) where gl_account_id is not null;

-- حماية القيود المرحَّلة: لا تعديل ولا حذف (عدا ختم العكس)
create or replace function public.fin_journal_guard()
returns trigger
language plpgsql
as $$
begin
  if tg_table_name = 'fin_journals' then
    if tg_op = 'DELETE' then
      if old.status = 'posted' then raise exception 'القيد المرحَّل لا يُحذف؛ يُصحَّح بقيد عكسي' using errcode = '23514'; end if;
      return old;
    end if;
    if old.status = 'posted' and (to_jsonb(new) - 'reversed_by' - 'reverse_reason') is distinct from (to_jsonb(old) - 'reversed_by' - 'reverse_reason') then
      raise exception 'القيد المرحَّل لا يُعدَّل؛ يُصحَّح بقيد عكسي' using errcode = '23514';
    end if;
    return new;
  else
    if exists (select 1 from public.fin_journals j where j.id = coalesce(old.journal_id, new.journal_id) and j.status = 'posted') then
      raise exception 'سطور القيد المرحَّل لا تُعدَّل ولا تُحذف' using errcode = '23514';
    end if;
    return coalesce(new, old);
  end if;
end $$;

drop trigger if exists fin_journals_guard on public.fin_journals;
create trigger fin_journals_guard before update or delete on public.fin_journals for each row execute function public.fin_journal_guard();
drop trigger if exists fin_journal_lines_guard on public.fin_journal_lines;
create trigger fin_journal_lines_guard before update or delete on public.fin_journal_lines for each row execute function public.fin_journal_guard();

do $$
declare t text;
begin
  foreach t in array array['fin_gl_accounts', 'fin_journals', 'fin_journal_lines', 'fin_gl_map'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('drop policy if exists %I on public.%I', t || '_read', t);
    execute format('create policy %I on public.%I for select to authenticated using ((select public.finance_can_view()))', t || '_read', t);
    execute format('revoke all on public.%I from anon', t);
    execute format('revoke insert, update, delete, truncate on public.%I from authenticated', t);
    execute format('grant select on public.%I to authenticated', t);
    execute format('grant all on public.%I to service_role', t);
  end loop;
end $$;

-- الدليل الابتدائي (يُدرج مرة واحدة؛ يعدّله المحرر بعد ذلك)
insert into public.fin_gl_accounts (code, name, type, postable) values
  ('1', 'الأصول', 'asset', false), ('11', 'النقدية والمصارف', 'asset', false), ('1110', 'الخزينة', 'asset', true), ('1120', 'المصارف', 'asset', true),
  ('12', 'الذمم والسلف', 'asset', false), ('1210', 'سلف الموظفين', 'asset', true), ('1220', 'ضمانات وتأمينات لدى الغير', 'asset', true),
  ('2', 'الخصوم', 'liability', false), ('21', 'المستحقات', 'liability', false), ('2110', 'مرتبات مستحقة الدفع', 'liability', true),
  ('2120', 'تأمينات اجتماعية مستحقة', 'liability', true), ('2130', 'ضرائب مستحقة', 'liability', true), ('2140', 'استقطاعات أخرى مستحقة', 'liability', true),
  ('2210', 'ضمانات وتأمينات محتجزة', 'liability', true),
  ('3', 'حقوق الملكية', 'equity', false), ('3100', 'الأرصدة الافتتاحية', 'equity', true),
  ('4', 'الإيرادات', 'revenue', false), ('4100', 'إيرادات متنوعة', 'revenue', true),
  ('5', 'المصروفات', 'expense', false), ('5110', 'الرواتب والأجور', 'expense', true), ('5120', 'مصروفات أخرى', 'expense', true)
on conflict (code) do nothing;
update public.fin_gl_accounts c set parent_id = p.id
  from public.fin_gl_accounts p
 where c.parent_id is null and c.code in ('11', '12', '21') and p.code = case c.code when '11' then '1' when '12' then '1' else '2' end;
update public.fin_gl_accounts c set parent_id = p.id
  from public.fin_gl_accounts p
 where c.parent_id is null and p.code = case c.code when '1110' then '11' when '1120' then '11' when '1210' then '12' when '1220' then '12'
                                                    when '2110' then '21' when '2120' then '21' when '2130' then '21' when '2140' then '21'
                                                    when '2210' then '2' when '3100' then '3' when '4100' then '4' when '5110' then '5' when '5120' then '5' end;
insert into public.fin_gl_map (key, account_id)
select m.key, a.id from (values ('payroll_expense', '5110'), ('payroll_net', '2110'), ('payroll_insurance', '2120'),
                                ('payroll_tax', '2130'), ('payroll_other', '2140'), ('payroll_loan', '1210')) m (key, code)
  join public.fin_gl_accounts a on a.code = m.code
on conflict (key) do nothing;

-- نوع الحساب جانبه الطبيعي: المدين للأصول والمصروفات
create or replace function public.fin_gl_debit_normal(p_type text)
returns boolean
language sql immutable
as $$ select p_type in ('asset', 'expense') $$;

-- دليل الحسابات
create or replace function public.fin_gl_account_save(p_id uuid, p_code text, p_name text, p_type text, p_parent uuid, p_postable boolean, p_active boolean default true)
returns uuid
language plpgsql security definer set search_path = public
as $$
declare
  v_id uuid := p_id; v_code text := btrim(coalesce(p_code, '')); v_name text := btrim(coalesce(p_name, '')); par public.fin_gl_accounts; cur public.fin_gl_accounts;
begin
  perform public.fin_need_edit();
  if v_code !~ '^[0-9A-Za-z.-]{1,12}$' then raise exception 'رمز الحساب حروف وأرقام حتى 12' using errcode = '22023'; end if;
  if length(v_name) not between 1 and 100 then raise exception 'اسم الحساب حتى 100 حرف' using errcode = '22023'; end if;
  if p_type is null or p_type not in ('asset', 'liability', 'equity', 'revenue', 'expense') then raise exception 'نوع حساب غير صالح' using errcode = '22023'; end if;
  if p_postable is null then raise exception 'حدّد هل الحساب فرعي' using errcode = '22023'; end if;
  if exists (select 1 from public.fin_gl_accounts where code = v_code and id is distinct from p_id) then raise exception 'رمز الحساب مستخدم' using errcode = '23505'; end if;
  if p_parent is not null then
    select * into par from public.fin_gl_accounts where id = p_parent;
    if not found then raise exception 'الحساب الأب غير موجود' using errcode = 'P0002'; end if;
    if par.postable then raise exception 'الحساب الأب حساب رئيسي لا فرعي' using errcode = '23514'; end if;
    if par.type <> p_type then raise exception 'نوع الحساب يطابق نوع أبيه' using errcode = '23514'; end if;
    if p_parent = p_id then raise exception 'حساب لا يكون أباً لنفسه' using errcode = '23514'; end if;
  end if;
  if p_id is null then
    insert into public.fin_gl_accounts (code, name, type, parent_id, postable, active, created_by)
    values (v_code, v_name, p_type, p_parent, p_postable, coalesce(p_active, true), auth.uid()) returning id into v_id;
  else
    select * into cur from public.fin_gl_accounts where id = p_id;
    if not found then raise exception 'الحساب غير موجود' using errcode = 'P0002'; end if;
    if exists (select 1 from public.fin_journal_lines where account_id = p_id)
       and (cur.code <> v_code or cur.type <> p_type or cur.postable <> p_postable or cur.parent_id is distinct from p_parent) then
      raise exception 'عليه قيود؛ لا يُغيَّر رمزه ولا نوعه ولا موضعه' using errcode = '23514';
    end if;
    if p_postable and exists (select 1 from public.fin_gl_accounts where parent_id = p_id) then
      raise exception 'له حسابات فرعية؛ لا يصير حساب قيد' using errcode = '23514';
    end if;
    update public.fin_gl_accounts set code = v_code, name = v_name, type = p_type, parent_id = p_parent, postable = p_postable, active = coalesce(p_active, true) where id = p_id;
  end if;
  perform public.write_audit('finance.gl_save', null, null,
    jsonb_build_object('code', v_code, 'name', v_name, 'type', p_type, 'created', p_id is null), v_code || ' ' || v_name);
  return v_id;
end $$;

create or replace function public.fin_gl_account_delete(p_id uuid)
returns void
language plpgsql security definer set search_path = public
as $$
declare a public.fin_gl_accounts;
begin
  perform public.fin_need_edit();
  select * into a from public.fin_gl_accounts where id = p_id;
  if not found then raise exception 'الحساب غير موجود' using errcode = 'P0002'; end if;
  if exists (select 1 from public.fin_journal_lines where account_id = p_id) then raise exception 'عليه قيود؛ أوقفه بدل حذفه' using errcode = '23503'; end if;
  if exists (select 1 from public.fin_gl_accounts where parent_id = p_id) then raise exception 'له حسابات فرعية' using errcode = '23503'; end if;
  if exists (select 1 from public.fin_gl_map where account_id = p_id) then raise exception 'معيَّن لقيود آلية؛ غيّر التعيين أولاً' using errcode = '23503'; end if;
  if exists (select 1 from public.fin_accounts where gl_account_id = p_id) then raise exception 'مربوط بحساب مالي؛ افصل الربط أولاً' using errcode = '23503'; end if;
  delete from public.fin_gl_accounts where id = p_id;
  perform public.write_audit('finance.gl_delete', null, null, jsonb_build_object('code', a.code, 'name', a.name), a.code || ' ' || a.name);
end $$;

-- ربط حساب مالي بحساب أصل في الدليل
create or replace function public.fin_account_link(p_account uuid, p_gl uuid)
returns void
language plpgsql security definer set search_path = public
as $$
declare f public.fin_accounts; g public.fin_gl_accounts;
begin
  perform public.fin_need_edit();
  select * into f from public.fin_accounts where id = p_account;
  if not found then raise exception 'الحساب المالي غير موجود' using errcode = 'P0002'; end if;
  if p_gl is not null then
    select * into g from public.fin_gl_accounts where id = p_gl;
    if not found then raise exception 'حساب الدليل غير موجود' using errcode = 'P0002'; end if;
    if g.type <> 'asset' or not g.postable or not g.active then raise exception 'يُربط الحساب المالي بحساب أصل فرعي مفعّل' using errcode = '23514'; end if;
    if exists (select 1 from public.fin_accounts where gl_account_id = p_gl and id <> p_account) then
      raise exception 'حساب الدليل مربوط بحساب مالي آخر' using errcode = '23505';
    end if;
  end if;
  update public.fin_accounts set gl_account_id = p_gl where id = p_account;
  perform public.write_audit('finance.gl_link', null, null,
    jsonb_build_object('account', f.name, 'gl', case when p_gl is null then null else g.code || ' ' || g.name end), f.name);
end $$;

-- تعيين حسابات القيود الآلية (بصلاحية الاعتماد)
create or replace function public.fin_gl_map_set(p_key text, p_gl uuid)
returns void
language plpgsql security definer set search_path = public
as $$
declare g public.fin_gl_accounts; v_type text;
begin
  perform public.fin_need_approve();
  if p_key is null or p_key not in ('payroll_expense', 'payroll_net', 'payroll_insurance', 'payroll_tax', 'payroll_other', 'payroll_loan') then
    raise exception 'مفتاح تعيين غير صالح' using errcode = '22023';
  end if;
  select * into g from public.fin_gl_accounts where id = p_gl;
  if not found then raise exception 'حساب الدليل غير موجود' using errcode = 'P0002'; end if;
  v_type := case p_key when 'payroll_expense' then 'expense' when 'payroll_loan' then 'asset' else 'liability' end;
  if g.type <> v_type or not g.postable or not g.active then
    raise exception 'هذا التعيين لحساب % فرعي مفعّل', case v_type when 'expense' then 'مصروفات' when 'asset' then 'أصول' else 'خصوم' end using errcode = '23514';
  end if;
  insert into public.fin_gl_map (key, account_id) values (p_key, p_gl) on conflict (key) do update set account_id = excluded.account_id;
  perform public.write_audit('finance.gl_map_set', null, null, jsonb_build_object('key', p_key, 'gl', g.code || ' ' || g.name), g.code);
end $$;

-- قيد آلي مرحَّل (داخلي: لا يُمنح للمستخدمين)
create or replace function public.fin_journal_auto(p_source text, p_source_id uuid, p_date date, p_memo text, p_lines jsonb, p_reverses uuid default null)
returns uuid
language plpgsql security definer set search_path = public
as $$
declare v_id uuid; l jsonb; n integer := 0; v_d numeric := 0; v_c numeric := 0; a public.fin_gl_accounts;
begin
  if jsonb_typeof(p_lines) <> 'array' or jsonb_array_length(p_lines) < 2 then raise exception 'القيد الآلي يحتاج سطرين فأكثر' using errcode = '23514'; end if;
  insert into public.fin_journals (entry_no, entry_date, memo, source, source_id, status, reverses, created_by, posted_at, posted_by)
  values (nextval('public.fin_journal_seq'), p_date, left(p_memo, 300), p_source, p_source_id, 'draft', p_reverses, auth.uid(), null, null)
  returning id into v_id;
  for l in select * from jsonb_array_elements(p_lines) loop
    n := n + 1;
    select * into a from public.fin_gl_accounts where id = (l ->> 'account')::uuid;
    if not found or not a.postable or not a.active then raise exception 'حساب القيد الآلي غير صالح للترحيل' using errcode = '23514'; end if;
    insert into public.fin_journal_lines (journal_id, line_no, account_id, debit, credit, memo)
    values (v_id, n, a.id, round(coalesce((l ->> 'debit')::numeric, 0), 3), round(coalesce((l ->> 'credit')::numeric, 0), 3), coalesce(l ->> 'memo', ''));
    v_d := v_d + round(coalesce((l ->> 'debit')::numeric, 0), 3);
    v_c := v_c + round(coalesce((l ->> 'credit')::numeric, 0), 3);
  end loop;
  if v_d <> v_c or v_d <= 0 then raise exception 'القيد الآلي غير متوازن (مدين % دائن %)', v_d, v_c using errcode = '23514'; end if;
  update public.fin_journals set status = 'posted', posted_at = now(), posted_by = auth.uid() where id = v_id;
  return v_id;
end $$;

-- قيود يدوية
create or replace function public.fin_journal_save(p_id uuid, p_date date, p_memo text, p_lines jsonb)
returns uuid
language plpgsql security definer set search_path = public
as $$
declare v_id uuid := p_id; v_memo text := btrim(coalesce(p_memo, '')); l jsonb; n integer := 0; a public.fin_gl_accounts; v_d numeric; v_c numeric; j public.fin_journals;
begin
  perform public.fin_need_edit();
  if p_date is null then raise exception 'تاريخ القيد مطلوب' using errcode = '22023'; end if;
  if length(v_memo) not between 1 and 300 then raise exception 'بيان القيد حتى 300 حرف' using errcode = '22023'; end if;
  if p_lines is null or jsonb_typeof(p_lines) <> 'array' or jsonb_array_length(p_lines) not between 2 and 100 then
    raise exception 'القيد من سطرين إلى 100 سطر' using errcode = '22023';
  end if;
  if p_id is null then
    insert into public.fin_journals (entry_date, memo, source, status, created_by) values (p_date, v_memo, 'manual', 'draft', auth.uid()) returning id into v_id;
  else
    select * into j from public.fin_journals where id = p_id;
    if not found then raise exception 'القيد غير موجود' using errcode = 'P0002'; end if;
    if j.status <> 'draft' or j.source <> 'manual' then raise exception 'تُعدَّل مسودة القيد اليدوي وحدها' using errcode = '23514'; end if;
    update public.fin_journals set entry_date = p_date, memo = v_memo where id = p_id;
    delete from public.fin_journal_lines where journal_id = p_id;
  end if;
  for l in select * from jsonb_array_elements(p_lines) loop
    n := n + 1;
    select * into a from public.fin_gl_accounts where id = nullif(l ->> 'account', '')::uuid;
    if not found then raise exception 'السطر %: الحساب غير موجود', n using errcode = 'P0002'; end if;
    if not a.postable or not a.active then raise exception 'السطر %: القيد على حساب فرعي مفعّل وحده', n using errcode = '23514'; end if;
    v_d := round(coalesce((l ->> 'debit')::numeric, 0), 3);
    v_c := round(coalesce((l ->> 'credit')::numeric, 0), 3);
    if v_d < 0 or v_c < 0 or (v_d = 0) = (v_c = 0) then raise exception 'السطر %: مدين أو دائن بمبلغ موجب لا كلاهما', n using errcode = '22023'; end if;
    if length(coalesce(l ->> 'memo', '')) > 200 then raise exception 'السطر %: البيان حتى 200 حرف', n using errcode = '22023'; end if;
    insert into public.fin_journal_lines (journal_id, line_no, account_id, debit, credit, memo) values (v_id, n, a.id, v_d, v_c, coalesce(l ->> 'memo', ''));
  end loop;
  perform public.write_audit('finance.journal_save', null, null,
    jsonb_build_object('memo', v_memo, 'date', p_date, 'lines', n, 'created', p_id is null), v_memo);
  return v_id;
end $$;

create or replace function public.fin_journal_delete(p_id uuid)
returns void
language plpgsql security definer set search_path = public
as $$
declare j public.fin_journals;
begin
  perform public.fin_need_edit();
  select * into j from public.fin_journals where id = p_id;
  if not found then raise exception 'القيد غير موجود' using errcode = 'P0002'; end if;
  if j.status <> 'draft' or j.source <> 'manual' then raise exception 'تُحذف مسودة القيد اليدوي وحدها' using errcode = '23514'; end if;
  delete from public.fin_journals where id = p_id;
  perform public.write_audit('finance.journal_delete', null, null, jsonb_build_object('memo', j.memo, 'date', j.entry_date), j.memo);
end $$;

create or replace function public.fin_journal_post(p_id uuid)
returns void
language plpgsql security definer set search_path = public
as $$
declare j public.fin_journals; v_d numeric; v_c numeric; v_n integer;
begin
  perform public.fin_need_approve();
  select * into j from public.fin_journals where id = p_id for update;
  if not found then raise exception 'القيد غير موجود' using errcode = 'P0002'; end if;
  if j.status <> 'draft' or j.source <> 'manual' then raise exception 'تُرحَّل مسودة القيد اليدوي وحدها' using errcode = '23514'; end if;
  select count(*), coalesce(sum(debit), 0), coalesce(sum(credit), 0) into v_n, v_d, v_c from public.fin_journal_lines where journal_id = p_id;
  if v_n < 2 then raise exception 'القيد بلا سطور كافية' using errcode = '23514'; end if;
  if v_d <> v_c or v_d <= 0 then raise exception 'القيد غير متوازن: مدين % ودائن %', v_d, v_c using errcode = '23514'; end if;
  if exists (select 1 from public.fin_journal_lines l join public.fin_gl_accounts a on a.id = l.account_id where l.journal_id = p_id and (not a.active or not a.postable)) then
    raise exception 'في القيد حساب موقوف أو غير فرعي' using errcode = '23514';
  end if;
  update public.fin_journals set status = 'posted', entry_no = nextval('public.fin_journal_seq'), posted_at = now(), posted_by = auth.uid() where id = p_id;
  perform public.write_audit('finance.journal_post', null, null,
    jsonb_build_object('memo', j.memo, 'date', j.entry_date, 'amount', v_d, 'no', (select entry_no from public.fin_journals where id = p_id)), j.memo);
end $$;

create or replace function public.fin_journal_reverse(p_id uuid, p_reason text)
returns uuid
language plpgsql security definer set search_path = public
as $$
declare j public.fin_journals; v_r text := btrim(coalesce(p_reason, '')); v_new uuid; v_lines jsonb;
begin
  perform public.fin_need_approve();
  if length(v_r) not between 3 and 300 then raise exception 'سبب العكس من 3 إلى 300 حرف' using errcode = '22023'; end if;
  select * into j from public.fin_journals where id = p_id for update;
  if not found then raise exception 'القيد غير موجود' using errcode = 'P0002'; end if;
  if j.status <> 'posted' then raise exception 'يُعكس القيد المرحَّل وحده' using errcode = '23514'; end if;
  if j.source <> 'manual' then raise exception 'القيد الآلي يُعكس بالتراجع عن مصدره' using errcode = '23514'; end if;
  if j.reverses is not null then raise exception 'القيد العكسي لا يُعكس' using errcode = '23514'; end if;
  if j.reversed_by is not null then raise exception 'القيد معكوس سابقاً' using errcode = '23514'; end if;
  select jsonb_agg(jsonb_build_object('account', account_id, 'debit', credit, 'credit', debit, 'memo', memo) order by line_no) into v_lines
    from public.fin_journal_lines where journal_id = p_id;
  v_new := public.fin_journal_auto('manual', null, current_date, left('عكس قيد رقم ' || j.entry_no || ': ' || v_r, 300), v_lines, p_id);
  update public.fin_journals set reversed_by = v_new, reverse_reason = v_r where id = p_id;
  perform public.write_audit('finance.journal_reverse', null, null,
    jsonb_build_object('no', j.entry_no, 'memo', j.memo, 'reason', v_r), j.memo);
  return v_new;
end $$;

-- ميزان المراجعة لفترة: الرصيد الافتتاحي (قبلها) وحركتها ورصيدها الختامي بالجانب الطبيعي للحساب
create or replace function public.fin_trial_balance(p_from date, p_to date)
returns table (account_id uuid, code text, name text, type text, opening numeric, debit numeric, credit numeric, closing numeric)
language sql stable security definer set search_path = public
as $$
  with s as (
    select a.id, a.code, a.name, a.type,
           coalesce(sum(case when j.entry_date < p_from then l.debit - l.credit end), 0) as o,
           coalesce(sum(case when j.entry_date between p_from and p_to then l.debit end), 0) as d,
           coalesce(sum(case when j.entry_date between p_from and p_to then l.credit end), 0) as c
      from public.fin_gl_accounts a
      join public.fin_journal_lines l on l.account_id = a.id
      join public.fin_journals j on j.id = l.journal_id and j.status = 'posted' and j.entry_date <= p_to
     where public.finance_can_view()
     group by a.id, a.code, a.name, a.type
  )
  select id, code, name, type,
         case when public.fin_gl_debit_normal(type) then o else -o end,
         d, c,
         case when public.fin_gl_debit_normal(type) then o + d - c else -(o + d - c) end
    from s where o <> 0 or d <> 0 or c <> 0
   order by code
$$;

-- اعتماد الكشف: يُنشئ قيده الآلي (الترحيل 48 + قيود 3.3)
create or replace function public.fin_payroll_approve(p_period date)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  p public.fin_payrolls; v_p date := date_trunc('month', p_period)::date;
  s record; v_lines jsonb := '[]'::jsonb; v_exp uuid; v_net uuid; v_ins uuid; v_tax uuid; v_oth uuid; v_loan uuid;
  v_end date := (date_trunc('month', p_period) + interval '1 month' - interval '1 day')::date;
begin
  if not public.finance_can_approve() then raise exception 'اعتماد الكشف لمن يملك صلاحية الاعتماد' using errcode = '42501'; end if;
  select * into p from public.fin_payrolls where period = v_p;
  if not found then raise exception 'لا كشف لهذا الشهر' using errcode = 'P0002'; end if;
  if p.status <> 'draft' then raise exception 'الكشف ليس مسودة' using errcode = '23514'; end if;
  if not exists (select 1 from public.fin_payroll_lines where payroll_id = p.id) then raise exception 'الكشف بلا موظفين' using errcode = '23514'; end if;
  if exists (select 1 from public.fin_payroll_lines where payroll_id = p.id and net < 0) then
    raise exception 'في الكشف صافٍ سالب؛ راجع الخصومات قبل الاعتماد' using errcode = '23514';
  end if;
  select account_id into v_exp from public.fin_gl_map where key = 'payroll_expense';
  select account_id into v_net from public.fin_gl_map where key = 'payroll_net';
  select account_id into v_ins from public.fin_gl_map where key = 'payroll_insurance';
  select account_id into v_tax from public.fin_gl_map where key = 'payroll_tax';
  select account_id into v_oth from public.fin_gl_map where key = 'payroll_other';
  select account_id into v_loan from public.fin_gl_map where key = 'payroll_loan';
  if v_exp is null or v_net is null or v_ins is null or v_tax is null or v_oth is null or v_loan is null then
    raise exception 'حدّد حسابات قيد المرتبات في دليل الحسابات قبل الاعتماد' using errcode = '23514';
  end if;
  select sum(gross) - sum(absence) as expense, sum(net) as net, sum(insurance) as ins, sum(tax + extra_rule) as tax,
         sum(other_deductions) as oth, sum(loan) as loan
    into s from public.fin_payroll_lines where payroll_id = p.id;
  v_lines := jsonb_build_array(jsonb_build_object('account', v_exp, 'debit', s.expense, 'credit', 0, 'memo', 'الرواتب والأجور'));
  if s.net > 0 then v_lines := v_lines || jsonb_build_object('account', v_net, 'debit', 0, 'credit', s.net, 'memo', 'صافي المرتبات'); end if;
  if s.ins > 0 then v_lines := v_lines || jsonb_build_object('account', v_ins, 'debit', 0, 'credit', s.ins, 'memo', 'التأمينات'); end if;
  if s.tax > 0 then v_lines := v_lines || jsonb_build_object('account', v_tax, 'debit', 0, 'credit', s.tax, 'memo', 'ضريبة الدخل والقاعدة الإضافية'); end if;
  if s.oth > 0 then v_lines := v_lines || jsonb_build_object('account', v_oth, 'debit', 0, 'credit', s.oth, 'memo', 'استقطاعات أخرى'); end if;
  if s.loan > 0 then v_lines := v_lines || jsonb_build_object('account', v_loan, 'debit', 0, 'credit', s.loan, 'memo', 'أقساط السلف'); end if;
  if s.expense > 0 then
    perform public.fin_journal_auto('payroll', p.id, v_end, 'كشف مرتبات ' || to_char(v_p, 'YYYY-MM'), v_lines);
  end if;
  update public.fin_payrolls set status = 'approved', approved_at = now(), approved_by = auth.uid() where id = p.id;
  perform public.write_audit('finance.payroll_approve', null, null,
    jsonb_build_object('period', v_p, 'net', (select sum(net) from public.fin_payroll_lines where payroll_id = p.id)), to_char(v_p, 'YYYY-MM'));
end $$;

-- التراجع عن الكشف: يعكس قيده الآلي إن وُجد
create or replace function public.fin_payroll_reopen(p_period date, p_reason text)
returns void
language plpgsql security definer set search_path = public
as $$
declare p public.fin_payrolls; v_p date := date_trunc('month', p_period)::date; j public.fin_journals; v_lines jsonb; v_new uuid;
begin
  if not public.finance_can_approve() then raise exception 'التراجع لمن يملك صلاحية الاعتماد' using errcode = '42501'; end if;
  if length(btrim(coalesce(p_reason, ''))) < 3 or length(p_reason) > 300 then raise exception 'سبب التراجع مطلوب (3 إلى 300 حرف)' using errcode = '22023'; end if;
  select * into p from public.fin_payrolls where period = v_p;
  if not found then raise exception 'لا كشف لهذا الشهر' using errcode = 'P0002'; end if;
  if p.status = 'draft' then raise exception 'الكشف مسودة أصلاً' using errcode = '23514'; end if;
  for j in select * from public.fin_journals where source = 'payroll' and source_id = p.id and status = 'posted' and reversed_by is null loop
    select jsonb_agg(jsonb_build_object('account', account_id, 'debit', credit, 'credit', debit, 'memo', memo) order by line_no) into v_lines
      from public.fin_journal_lines where journal_id = j.id;
    v_new := public.fin_journal_auto('payroll_reversal', p.id, current_date, left('عكس قيد كشف مرتبات ' || to_char(v_p, 'YYYY-MM') || ': ' || btrim(p_reason), 300), v_lines, j.id);
    update public.fin_journals set reversed_by = v_new, reverse_reason = left(btrim(p_reason), 300) where id = j.id;
  end loop;
  update public.fin_payrolls set status = 'draft', approved_at = null, approved_by = null, locked_at = null, locked_by = null where id = p.id;
  perform public.write_audit('finance.payroll_reopen', null, null,
    jsonb_build_object('period', v_p, 'from', p.status, 'reason', btrim(p_reason)), to_char(v_p, 'YYYY-MM'));
end $$;

-- ترحيل التحويل: يُنشئ قيده الآلي، ولا يُرحَّل لحساب غير مربوط بالدليل
create or replace function public.fin_transfer_decide(p_id uuid, p_approve boolean, p_note text default '')
returns void
language plpgsql security definer set search_path = public
as $$
declare x public.fin_transfers; f public.fin_accounts; t public.fin_accounts; v_n text := btrim(coalesce(p_note, ''));
begin
  perform public.fin_need_approve();
  if p_approve is null then raise exception 'حدّد الموافقة أو الرفض' using errcode = '22023'; end if;
  if length(v_n) > 300 then raise exception 'الملاحظة أطول من 300 حرف' using errcode = '22023'; end if;
  if not p_approve and length(v_n) < 3 then raise exception 'سبب الرفض مطلوب (3 أحرف فأكثر)' using errcode = '22023'; end if;
  select * into x from public.fin_transfers where id = p_id for update;
  if not found then raise exception 'التحويل غير موجود' using errcode = 'P0002'; end if;
  if x.status <> 'pending' then raise exception 'التحويل ليس معلّقاً' using errcode = '23514'; end if;
  select * into f from public.fin_accounts where id = x.from_id;
  select * into t from public.fin_accounts where id = x.to_id;
  if p_approve then
    if f.gl_account_id is null or t.gl_account_id is null then
      raise exception 'اربط الحسابين المالييْن بحسابات الدليل قبل ترحيل التحويل' using errcode = '23514';
    end if;
    if public.fin_account_balance(x.from_id) < x.amount then
      raise exception 'رصيد «%» لا يكفي لهذا التحويل', f.name using errcode = '23514';
    end if;
    perform public.fin_journal_auto('transfer', x.id, x.on_date, left('تحويل من ' || f.name || ' إلى ' || t.name, 300),
      jsonb_build_array(jsonb_build_object('account', t.gl_account_id, 'debit', x.amount, 'credit', 0, 'memo', 'إلى ' || t.name),
                        jsonb_build_object('account', f.gl_account_id, 'debit', 0, 'credit', x.amount, 'memo', 'من ' || f.name)));
  end if;
  update public.fin_transfers set status = case when p_approve then 'posted' else 'rejected' end, decided_at = now(),
         decided_by = auth.uid(), decision_note = v_n where id = p_id;
  perform public.write_audit(case when p_approve then 'finance.transfer_approve' else 'finance.transfer_reject' end, null, null,
    jsonb_build_object('from', f.name, 'to', t.name, 'amount', x.amount, 'note', v_n), f.name || ' ← ' || t.name);
end $$;

do $$
declare f record;
begin
  for f in select p.oid::regprocedure as sig from pg_proc p
            where p.pronamespace = 'public'::regnamespace
              and p.proname in ('fin_gl_account_save', 'fin_gl_account_delete', 'fin_account_link', 'fin_gl_map_set', 'fin_journal_save',
                                'fin_journal_delete', 'fin_journal_post', 'fin_journal_reverse', 'fin_trial_balance', 'fin_gl_debit_normal') loop
    execute format('revoke all on function %s from public, anon', f.sig);
    execute format('grant execute on function %s to authenticated, service_role', f.sig);
  end loop;
  -- الدالة الداخلية للقيود الآلية: لا تُستدعى من المستخدمين مباشرة
  for f in select p.oid::regprocedure as sig from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'fin_journal_auto' loop
    execute format('revoke all on function %s from public, anon, authenticated', f.sig);
    execute format('grant execute on function %s to service_role', f.sig);
  end loop;
end $$;
