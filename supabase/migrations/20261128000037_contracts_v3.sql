-- =====================================================================
-- الإصدار 1.6.0 (الترحيل 37): ضمانات العقد وتأميناته، وأوامر التغيير ببنودها واعتمادها وسجلها، ولجنة الاستلام
--
--  1. نسبتا الضمانين ثابتتان لكل عقد (guarantee_initial_rate وguarantee_final_rate): تُؤخذان من الإعداد عند إنشاء
--     العقد، ولا يغيّرهما تعديل الإعداد بعد ذلك. والتصحيح المقرر للعقود القائمة: الابتدائي 2% والنهائي 5%، بعد نسخ
--     القيم السابقة إلى backup.m37_projects_guarantees وتسجيل كل عقد في سجل التدقيق. الأساس كما كان: قيمة الأعمال المنفذة.
--  2. «لا ينطبق» للضمان النهائي، و«خصم التأمينات» لكل عقد: مفعّل بنسبته المقترحة في المستخلصات، أو معطّل فلا يُحتجز
--     تأمين في مستخلص جديد. المستخلصات السابقة تبقى كما هي.
--  3. أوامر التغيير: مسودة ← معتمد أو مرفوض، ولا يدخل في قيمة العقد إلا المعتمد. لكل أمر بنود زيادة ونقص مربوطة
--     ببند المقايسة أو بعمل العقد، وسجل بكل حفظ وقرار. أوامر «سجل التغييرات» تبقى معتمدة بقرار البت فيها هناك.
--     النقص في أوامر التغيير ينقص قيمة العقد، ولا علاقة له باستقطاعات المستخلصات (فلا يُحسب مرتين).
--  4. لجنة الاستلام الابتدائي (والنهائي) لكل عقد: رئيس واحد وأعضاء بصفاتهم، ولا يتكرر عضو.
--  5. مجاميع لوحة العقد: الزيادة والنقص المعتمدان، وإجمالي المستخلصات المقدمة.
--  يُشغَّل بعد 20261127000036_schedule_v2.sql، وإعادة تشغيله آمنة. التراجع: supabase/rollbacks/20261128000037_contracts_v3_down.sql
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. أعمدة العقد الجديدة
-- ---------------------------------------------------------------------
alter table public.projects
  add column if not exists guarantee_initial_rate numeric(7, 5),
  add column if not exists guarantee_final_rate   numeric(7, 5),
  add column if not exists guarantee_final_na     boolean not null default false,
  add column if not exists retention_deduct       boolean not null default true,
  add column if not exists retention_rate         numeric(7, 5),
  add column if not exists variations_add         numeric(16, 3) not null default 0,
  add column if not exists variations_deduct      numeric(16, 3) not null default 0,
  add column if not exists extracts_submitted     numeric(16, 3) not null default 0;

comment on column public.projects.guarantee_initial_rate is 'نسبة الضمان الابتدائي لهذا العقد (ثابتة، من الإعداد عند إنشائه)';
comment on column public.projects.guarantee_final_rate is 'نسبة الضمان النهائي لهذا العقد (ثابتة، من الإعداد عند إنشائه)';
comment on column public.projects.guarantee_final_na is 'الضمان النهائي لا ينطبق على هذا العقد';
comment on column public.projects.retention_deduct is 'خصم التأمينات من مستخلصات العقد مفعّل';
comment on column public.projects.retention_rate is 'نسبة التأمين المحتجز المقترحة في مستخلصات هذا العقد';

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'projects_guarantee_rates_chk') then
    alter table public.projects add constraint projects_guarantee_rates_chk
      check (coalesce(guarantee_initial_rate, 0) between 0 and 0.5 and coalesce(guarantee_final_rate, 0) between 0 and 0.5
             and coalesce(retention_rate, 0) between 0 and 0.5);
  end if;
end $$;

-- ---------------------------------------------------------------------
-- 2. الحساب الآلي للعقد: الضمانان بنسبتي العقد، وحماية الأعمدة الجديدة من الكتابة المباشرة
-- ---------------------------------------------------------------------
create or replace function public.projects_finance_calc()
returns trigger
language plpgsql security definer set search_path = public
as $$
begin
  if tg_op = 'INSERT' then
    new.guarantee_initial_rate := coalesce(new.guarantee_initial_rate, public.setting_num('finance.guarantee_initial_rate', 0.02));
    new.guarantee_final_rate   := coalesce(new.guarantee_final_rate, public.setting_num('finance.guarantee_final_rate', 0.05));
    new.retention_rate         := coalesce(new.retention_rate, public.setting_num('finance.retention_rate', 0));
  end if;
  if tg_op = 'UPDATE' and current_setting('app.trusted', true) is distinct from 'on' then
    new.value_source           := old.value_source;
    new.executed_source        := old.executed_source;
    new.variations_net         := old.variations_net;
    new.variations_add         := old.variations_add;
    new.variations_deduct      := old.variations_deduct;
    new.extracts_count         := old.extracts_count;
    new.extracts_gross         := old.extracts_gross;
    new.extracts_net           := old.extracts_net;
    new.extracts_paid          := old.extracts_paid;
    new.extracts_submitted     := old.extracts_submitted;
    new.retention_held         := old.retention_held;
    new.advance_amount         := old.advance_amount;
    new.advance_paid_on        := old.advance_paid_on;
    new.advance_recovered      := old.advance_recovered;
    new.guarantee_initial_rate := old.guarantee_initial_rate;
    new.guarantee_final_rate   := old.guarantee_final_rate;
    new.guarantee_final_na     := old.guarantee_final_na;
    new.retention_deduct       := old.retention_deduct;
    new.retention_rate         := old.retention_rate;
    if old.value_source = 'items' then
      new.contract_value := old.contract_value;
    end if;
    if old.executed_source <> 'manual' then
      new.executed_value := old.executed_value;
    end if;
  end if;
  if new.guarantee_initial_na then
    new.guarantee_initial := null;
  else
    new.guarantee_initial := round(new.executed_value
      * coalesce(new.guarantee_initial_rate, public.setting_num('finance.guarantee_initial_rate', 0.02)), 3);
  end if;
  if new.guarantee_final_na then
    new.guarantee_final := null;
  else
    new.guarantee_final := round(new.executed_value
      * coalesce(new.guarantee_final_rate, public.setting_num('finance.guarantee_final_rate', 0.05)), 3);
  end if;
  if tg_op = 'UPDATE' and new.extra is distinct from old.extra
     and current_setting('app.trusted', true) is distinct from 'on'
     and auth.uid() is not null and not public.is_director() then
    raise exception 'تُعدَّل الحقول الإضافية من صفحة المشروع' using errcode = '42501';
  end if;
  if tg_op = 'UPDATE' and (new.contract_no is distinct from old.contract_no or new.merged_into is distinct from old.merged_into)
     and current_setting('app.trusted', true) is distinct from 'on' and auth.uid() is not null then
    raise exception 'رقم العقد والدمج من صلاحية مكتب العقود عبر صفحة العقد' using errcode = '42501';
  end if;
  return new;
end;
$$;

-- ---------------------------------------------------------------------
-- 3. تصحيح الضمانات في العقود القائمة (القرار المعتمد: الابتدائي 2% والنهائي 5%) بنسخة احتياطية وسجل تدقيق
--    يجري مرة واحدة لكل عقد: العقد الذي حُدّدت نسبتاه لا يُمس في إعادة التشغيل.
-- ---------------------------------------------------------------------
create schema if not exists backup;
revoke all on schema backup from public;
do $$
begin
  if exists (select 1 from pg_roles where rolname = 'anon') then
    execute 'revoke all on schema backup from anon, authenticated';
  end if;
end $$;

create table if not exists backup.m37_projects_guarantees (
  project_id           uuid primary key,
  executed_value       numeric,
  guarantee_initial    numeric,
  guarantee_final      numeric,
  guarantee_initial_na boolean,
  initial_rate         numeric,
  final_rate           numeric,
  retention_rate       numeric,
  backed_at            timestamptz not null default now()
);
revoke all on backup.m37_projects_guarantees from public;

do $$
declare
  r     record;
  v_ir  numeric := public.setting_num('finance.guarantee_initial_rate', 0.05);
  v_fr  numeric := public.setting_num('finance.guarantee_final_rate', 0.02);
  v_rr  numeric := public.setting_num('finance.retention_rate', 0);
  n_gi  numeric;
  n_gf  numeric;
  v_was text := coalesce(current_setting('app.trusted', true), '');
begin
  for r in select * from public.projects
            where guarantee_initial_rate is null or guarantee_final_rate is null or retention_rate is null
            order by id loop
    insert into backup.m37_projects_guarantees (project_id, executed_value, guarantee_initial, guarantee_final,
                                                guarantee_initial_na, initial_rate, final_rate, retention_rate)
    values (r.id, r.executed_value, r.guarantee_initial, r.guarantee_final, r.guarantee_initial_na, v_ir, v_fr, v_rr)
    on conflict (project_id) do nothing;
    perform set_config('app.trusted', 'on', true);
    update public.projects
       set guarantee_initial_rate = coalesce(guarantee_initial_rate, 0.02),
           guarantee_final_rate   = coalesce(guarantee_final_rate, 0.05),
           retention_rate         = coalesce(retention_rate, v_rr)
     where id = r.id
    returning guarantee_initial, guarantee_final into n_gi, n_gf;
    perform set_config('app.trusted', v_was, true);
    perform public.write_audit('finance.guarantees', r.id, null, jsonb_build_object(
      'source', 'migration_37',
      'initial_rate', jsonb_build_object('from', v_ir, 'to', 0.02),
      'final_rate', jsonb_build_object('from', v_fr, 'to', 0.05),
      'initial', jsonb_build_object('from', r.guarantee_initial, 'to', n_gi),
      'final', jsonb_build_object('from', r.guarantee_final, 'to', n_gf)));
  end loop;
end $$;

-- النسبتان الافتراضيتان للعقود الجديدة (تُعدَّلان من لوحة التحكم، ولا تمسّان العقود القائمة)
do $$
declare
  v_old jsonb;
begin
  select value into v_old from public.app_settings where key = 'finance.guarantee_initial_rate';
  if v_old is null or v_old = '0.05'::jsonb then
    insert into public.app_settings (key, value, updated_at) values ('finance.guarantee_initial_rate', '0.02', now())
    on conflict (key) do update set value = excluded.value, updated_at = excluded.updated_at;
    perform public.write_audit('setting.update', null, null,
      jsonb_build_object('key', 'finance.guarantee_initial_rate', 'from', v_old, 'to', 0.02, 'source', 'migration_37'),
      'finance.guarantee_initial_rate');
  end if;
  select value into v_old from public.app_settings where key = 'finance.guarantee_final_rate';
  if v_old is null or v_old = '0.02'::jsonb then
    insert into public.app_settings (key, value, updated_at) values ('finance.guarantee_final_rate', '0.05', now())
    on conflict (key) do update set value = excluded.value, updated_at = excluded.updated_at;
    perform public.write_audit('setting.update', null, null,
      jsonb_build_object('key', 'finance.guarantee_final_rate', 'from', v_old, 'to', 0.05, 'source', 'migration_37'),
      'finance.guarantee_final_rate');
  end if;
end $$;

-- ---------------------------------------------------------------------
-- 4. تحديد ضمانات العقد وتأميناته: النسبتان، و«لا ينطبق» لكل منهما، وخصم التأمينات ونسبته
-- ---------------------------------------------------------------------
create or replace function public.set_contract_guarantees(p_project uuid, p_data jsonb)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  p     public.projects;
  n     public.projects;
  v_ir  numeric;
  v_fr  numeric;
  v_ina boolean;
  v_fna boolean;
  v_rd  boolean;
  v_rr  numeric;
  v_ch  jsonb := '{}'::jsonb;
  v_was text := coalesce(current_setting('app.trusted', true), '');
begin
  if jsonb_typeof(coalesce(p_data, 'null'::jsonb)) <> 'object' then
    raise exception 'بيانات غير صالحة' using errcode = '22023';
  end if;
  select * into p from public.projects where id = p_project and merged_into is null for update;
  if not found then
    raise exception 'العقد غير موجود أو مدموج في عقد آخر' using errcode = '22023';
  end if;
  if not public.can_edit_finance(p_project) then
    raise exception 'ضمانات العقد وتأميناته يحدّدها من يختص بالبيانات المالية للعقد' using errcode = '42501';
  end if;
  v_ir  := coalesce(public.jnum(p_data, 'initial_rate', 0, 0.5, 'نسبة الضمان الابتدائي'), p.guarantee_initial_rate);
  v_fr  := coalesce(public.jnum(p_data, 'final_rate', 0, 0.5, 'نسبة الضمان النهائي'), p.guarantee_final_rate);
  v_rr  := coalesce(public.jnum(p_data, 'retention_rate', 0, 0.5, 'نسبة التأمين المحتجز'), p.retention_rate);
  v_ina := case when p_data ? 'initial_na' then public.jbool(p_data, 'initial_na') else p.guarantee_initial_na end;
  v_fna := case when p_data ? 'final_na' then public.jbool(p_data, 'final_na') else p.guarantee_final_na end;
  v_rd  := case when p_data ? 'retention_deduct' then public.jbool(p_data, 'retention_deduct') else p.retention_deduct end;
  v_ir := round(v_ir, 5);
  v_fr := round(v_fr, 5);
  v_rr := round(v_rr, 5);

  if v_ir is distinct from p.guarantee_initial_rate then
    v_ch := v_ch || jsonb_build_object('initial_rate', jsonb_build_object('from', p.guarantee_initial_rate, 'to', v_ir));
  end if;
  if v_fr is distinct from p.guarantee_final_rate then
    v_ch := v_ch || jsonb_build_object('final_rate', jsonb_build_object('from', p.guarantee_final_rate, 'to', v_fr));
  end if;
  if v_ina is distinct from p.guarantee_initial_na then
    v_ch := v_ch || jsonb_build_object('initial_na', jsonb_build_object('from', p.guarantee_initial_na, 'to', v_ina));
  end if;
  if v_fna is distinct from p.guarantee_final_na then
    v_ch := v_ch || jsonb_build_object('final_na', jsonb_build_object('from', p.guarantee_final_na, 'to', v_fna));
  end if;
  if v_rd is distinct from p.retention_deduct then
    v_ch := v_ch || jsonb_build_object('retention_deduct', jsonb_build_object('from', p.retention_deduct, 'to', v_rd));
  end if;
  if v_rr is distinct from p.retention_rate then
    v_ch := v_ch || jsonb_build_object('retention_rate', jsonb_build_object('from', p.retention_rate, 'to', v_rr));
  end if;
  if v_ch = '{}'::jsonb then
    return;
  end if;

  perform set_config('app.trusted', 'on', true);
  update public.projects
     set guarantee_initial_rate = v_ir, guarantee_final_rate = v_fr, guarantee_initial_na = v_ina,
         guarantee_final_na = v_fna, retention_deduct = v_rd, retention_rate = v_rr
   where id = p_project
  returning * into n;
  perform set_config('app.trusted', v_was, true);
  perform public.write_audit('finance.guarantees', p_project, null, v_ch || jsonb_build_object(
    'initial', jsonb_build_object('from', p.guarantee_initial, 'to', n.guarantee_initial),
    'final', jsonb_build_object('from', p.guarantee_final, 'to', n.guarantee_final)));
end;
$$;

-- خصم التأمينات المعطّل: لا يُحتجز تأمين في مستخلص جديد ولا يُرفع في مستخلص قائم (ما سُجّل قبل التعطيل يبقى)
create or replace function public.contract_extracts_retention_guard()
returns trigger
language plpgsql security definer set search_path = public
as $$
begin
  if coalesce(new.retention, 0) > 0
     and (tg_op = 'INSERT' or new.retention > coalesce(old.retention, 0))
     and exists (select 1 from public.projects where id = new.project_id and not retention_deduct) then
    raise exception 'خصم التأمينات معطّل في هذا العقد؛ اجعل التأمين المحتجز صفراً، أو فعّل الخصم من ضمانات العقد'
      using errcode = '22023';
  end if;
  return new;
end;
$$;
drop trigger if exists contract_extracts_retention_guard on public.contract_extracts;
create trigger contract_extracts_retention_guard
  before insert or update of retention on public.contract_extracts
  for each row execute function public.contract_extracts_retention_guard();

-- ---------------------------------------------------------------------
-- 5. أوامر التغيير: الحالة والقيمتان والبنود والسجل
-- ---------------------------------------------------------------------
alter table public.contract_variations
  add column if not exists status         text not null default 'approved',
  add column if not exists added_value    numeric(16, 3) not null default 0,
  add column if not exists deducted_value numeric(16, 3) not null default 0,
  add column if not exists decided_by     uuid references public.profiles (id) on delete set null,
  add column if not exists decided_at     timestamptz,
  add column if not exists decision_note  text not null default '',
  add column if not exists updated_at     timestamptz,
  add column if not exists updated_by     uuid references public.profiles (id) on delete set null;
comment on column public.contract_variations.status is 'draft مسودة · approved معتمد (يدخل في قيمة العقد) · rejected مرفوض';
comment on column public.contract_variations.added_value is 'قيمة الأعمال المضافة في الأمر';
comment on column public.contract_variations.deducted_value is 'قيمة الأعمال الملغاة أو المخفضة في الأمر';
create index if not exists contract_variations_decided_by_idx on public.contract_variations (decided_by);
create index if not exists contract_variations_updated_by_idx on public.contract_variations (updated_by);

create table if not exists public.contract_variation_items (
  id           uuid primary key default gen_random_uuid(),
  variation_id uuid not null references public.contract_variations (id) on delete cascade,
  sort         integer not null default 0,
  direction    text not null check (direction in ('add', 'deduct')),
  boq_sheet_id uuid references public.boq_sheets (id) on delete set null,
  boq_line     integer check (boq_line >= 0),
  work_id      uuid references public.contract_works (id) on delete set null,
  code         text not null default '' check (length(code) <= 40),
  description  text not null check (length(btrim(description)) between 2 and 500),
  unit         text not null default '' check (length(unit) <= 20),
  qty          numeric(16, 3) check (qty >= 0),
  unit_price   numeric(16, 3) check (unit_price >= 0),
  amount       numeric(16, 3) not null check (amount > 0),
  created_at   timestamptz not null default now()
);
create index if not exists contract_variation_items_variation_idx on public.contract_variation_items (variation_id, sort);
create index if not exists contract_variation_items_boq_idx on public.contract_variation_items (boq_sheet_id);
create index if not exists contract_variation_items_work_idx on public.contract_variation_items (work_id);

create table if not exists public.contract_variation_events (
  id           uuid primary key default gen_random_uuid(),
  variation_id uuid not null references public.contract_variations (id) on delete cascade,
  action       text not null check (action in ('create', 'update', 'approve', 'reject', 'reopen')),
  actor        uuid references public.profiles (id) on delete set null,
  actor_name   text not null default '',
  at           timestamptz not null default now(),
  note         text not null default '' check (length(note) <= 1000),
  snapshot     jsonb not null default '{}'::jsonb
);
create index if not exists contract_variation_events_variation_idx on public.contract_variation_events (variation_id, at);
create index if not exists contract_variation_events_actor_idx on public.contract_variation_events (actor);

-- القيمتان للأوامر القائمة من نوعها وقيمتها، والقيدان الجديدان (الصافي قد يكون صفراً إن تساوت الزيادة والنقص)
update public.contract_variations
   set added_value = case when kind = 'add' then amount else 0 end,
       deducted_value = case when kind = 'deduct' then amount else 0 end
 where added_value = 0 and deducted_value = 0;
do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'contract_variations_status_chk') then
    alter table public.contract_variations add constraint contract_variations_status_chk
      check (status in ('draft', 'approved', 'rejected'));
  end if;
  if exists (select 1 from pg_constraint where conname = 'contract_variations_amount_check') then
    alter table public.contract_variations drop constraint contract_variations_amount_check;
  end if;
  if not exists (select 1 from pg_constraint where conname = 'contract_variations_values_chk') then
    alter table public.contract_variations add constraint contract_variations_values_chk
      check (amount >= 0 and added_value >= 0 and deducted_value >= 0 and added_value + deducted_value > 0
             and amount = abs(added_value - deducted_value));
  end if;
end $$;

-- أمر بلا بنود (يدوي قديم أو من سجل التغييرات): قيمتاه من نوعه وقيمته
create or replace function public.contract_variations_values()
returns trigger
language plpgsql security definer set search_path = public
as $$
begin
  if tg_op = 'INSERT' or not exists (select 1 from public.contract_variation_items where variation_id = new.id) then
    if coalesce(current_setting('app.vo_lines', true), '') <> 'on' then
      new.added_value    := case when new.kind = 'add' then new.amount else 0 end;
      new.deducted_value := case when new.kind = 'deduct' then new.amount else 0 end;
    end if;
  end if;
  return new;
end;
$$;
drop trigger if exists contract_variations_values on public.contract_variations;
create trigger contract_variations_values
  before insert or update on public.contract_variations
  for each row execute function public.contract_variations_values();

-- مجاميع العقد: المعتمد وحده من أوامر التغيير، والمستخلصات المقدمة
create or replace function public.recalc_contract_finance(p_project uuid)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  v_cv   numeric; n_cv integer;
  v_ev   numeric; n_ev integer;
  v_var  numeric; v_vadd numeric; v_vded numeric;
  n_ext  integer;
  v_eg   numeric; v_en numeric; v_paid numeric; v_ret numeric; v_adv numeric;
  v_sub  numeric;
  v_trusted text := coalesce(current_setting('app.trusted', true), '');
  v_recalc  text := coalesce(current_setting('app.recalc', true), '');
begin
  if p_project is null then
    return;
  end if;
  select sum(contract_value), count(contract_value), sum(executed_value), count(executed_value)
    into v_cv, n_cv, v_ev, n_ev
    from public.contract_works where project_id = p_project;
  select coalesce(sum(added_value - deducted_value), 0), coalesce(sum(added_value), 0), coalesce(sum(deducted_value), 0)
    into v_var, v_vadd, v_vded
    from public.contract_variations where project_id = p_project and status = 'approved';
  select count(*), coalesce(sum(gross_amount), 0), coalesce(sum(net_amount), 0),
         coalesce(sum(paid_amount), 0), coalesce(sum(retention), 0), coalesce(sum(advance_recovery), 0)
    into n_ext, v_eg, v_en, v_paid, v_ret, v_adv
    from public.contract_extracts where project_id = p_project and status in ('approved', 'referred', 'paid');
  select coalesce(sum(gross_amount), 0) into v_sub
    from public.contract_extracts where project_id = p_project and status in ('submitted', 'approved', 'referred', 'paid');

  perform set_config('app.trusted', 'on', true);
  perform set_config('app.recalc', 'on', true);
  update public.projects set
    value_source       = case when n_cv > 0 then 'items' else 'manual' end,
    contract_value     = case when n_cv > 0 then v_cv else contract_value end,
    executed_source    = case when n_ext > 0 then 'extracts' when n_ev > 0 then 'items' else 'manual' end,
    executed_value     = case when n_ext > 0 then v_eg when n_ev > 0 then v_ev else executed_value end,
    variations_net     = v_var,
    variations_add     = v_vadd,
    variations_deduct  = v_vded,
    extracts_count     = n_ext,
    extracts_gross     = v_eg,
    extracts_net       = v_en,
    extracts_paid      = v_paid,
    extracts_submitted = v_sub,
    retention_held     = v_ret,
    advance_recovered  = v_adv
   where id = p_project
     and (value_source, contract_value, executed_source, executed_value, variations_net, variations_add, variations_deduct,
          extracts_count, extracts_gross, extracts_net, extracts_paid, extracts_submitted, retention_held, advance_recovered)
         is distinct from
         (case when n_cv > 0 then 'items' else 'manual' end,
          case when n_cv > 0 then v_cv else contract_value end,
          case when n_ext > 0 then 'extracts' when n_ev > 0 then 'items' else 'manual' end,
          case when n_ext > 0 then v_eg when n_ev > 0 then v_ev else executed_value end,
          v_var, v_vadd, v_vded, n_ext, v_eg, v_en, v_paid, v_sub, v_ret, v_adv);
  perform set_config('app.trusted', v_trusted, true);
  perform set_config('app.recalc', v_recalc, true);
end;
$$;

-- من يعتمد أمر التغيير أو يرفضه: المدير ومن يعتمد المستخلصات («اعتماد مستخلص»، افتراضياً موظفو مكتب المدير)
create or replace function public.can_approve_variation(p_project uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
  select public.writes_allowed() and (public.is_director() or public.can_edit_form(p_project, 'f24'))
$$;

-- صورة أمر التغيير ببنوده (للسجل)
create or replace function public.variation_snapshot(p_id uuid)
returns jsonb
language sql stable security definer set search_path = public
as $$
  select jsonb_build_object(
           'ref_no', v.ref_no, 'title', v.title, 'status', v.status, 'kind', v.kind, 'amount', v.amount,
           'added', v.added_value, 'deducted', v.deducted_value, 'work_id', v.work_id, 'approved_on', v.approved_on,
           'notes', v.notes,
           'items', coalesce((select jsonb_agg(jsonb_build_object(
                                'direction', i.direction, 'code', i.code, 'description', i.description, 'unit', i.unit,
                                'qty', i.qty, 'unit_price', i.unit_price, 'amount', i.amount,
                                'boq_sheet_id', i.boq_sheet_id, 'boq_line', i.boq_line, 'work_id', i.work_id) order by i.sort)
                                from public.contract_variation_items i where i.variation_id = v.id), '[]'::jsonb))
    from public.contract_variations v where v.id = p_id
$$;

-- حفظ أمر تغيير (جديد أو مسودة): رأسه وبنوده. يبقى مسودة حتى يُعتمد.
create or replace function public.save_contract_variation(p_id uuid, p_data jsonb)
returns uuid
language plpgsql security definer set search_path = public
as $$
declare
  o       public.contract_variations;
  v_id    uuid := p_id;
  v_new   boolean := p_id is null;
  v_proj  uuid;
  v_title text;
  v_ref   text;
  v_notes text;
  v_work  uuid;
  v_kind  text;
  v_amt   numeric;
  v_add   numeric := 0;
  v_ded   numeric := 0;
  v_items jsonb := coalesce(p_data -> 'items', '[]'::jsonb);
  it      jsonb;
  n       integer := 0;
  v_dir   text;
  v_desc  text;
  v_unit  text;
  v_code  text;
  v_qty   numeric;
  v_price numeric;
  v_lamt  numeric;
  v_sheet uuid;
  v_line  integer;
  v_iwork uuid;
  v_lines integer;
  v_before jsonb;
  v_after  jsonb;
begin
  if jsonb_typeof(coalesce(p_data, 'null'::jsonb)) <> 'object' then
    raise exception 'بيانات غير صالحة' using errcode = '22023';
  end if;
  if jsonb_typeof(v_items) <> 'array' or jsonb_array_length(v_items) > 200 then
    raise exception 'بنود أمر التغيير بصيغة غير صحيحة (حتى 200 بند)' using errcode = '22023';
  end if;
  if not v_new then
    select * into o from public.contract_variations where id = p_id for update;
    if not found then
      raise exception 'أمر التغيير غير موجود' using errcode = 'P0002';
    end if;
    if exists (select 1 from public.pm_changes where variation_id = o.id) then
      raise exception 'أمر التغيير هذا من سجل التغييرات؛ عدّله من هناك' using errcode = 'P0001';
    end if;
    if o.status <> 'draft' then
      raise exception 'أمر التغيير المعتمد أو المرفوض لا يُعدَّل؛ يعيده مدير المكتب إلى مسودة أولاً' using errcode = 'P0001';
    end if;
    v_proj := o.project_id;
    v_before := public.variation_snapshot(o.id);
  else
    v_proj := public.jproject(p_data, 'project_id', true);
  end if;
  if not exists (select 1 from public.projects where id = v_proj and merged_into is null) then
    raise exception 'العقد غير موجود أو مدموج في عقد آخر' using errcode = '22023';
  end if;
  if not public.can_edit_finance(v_proj) then
    raise exception 'أوامر التغيير يسجّلها من يختص بالبيانات المالية للعقد' using errcode = '42501';
  end if;
  v_title := public.jtext(p_data, 'title', 300, 'وصف أمر التغيير');
  if length(v_title) < 2 then
    raise exception 'اكتب وصف أمر التغيير' using errcode = '22023';
  end if;
  v_ref := public.jtext(p_data, 'ref_no', 40, 'رقم الأمر');
  v_notes := public.jtext(p_data, 'notes', 2000, 'الملاحظات');
  begin
    v_work := nullif(btrim(coalesce(p_data ->> 'work_id', '')), '')::uuid;
  exception when others then
    raise exception 'عمل العقد المحدد غير صالح' using errcode = '22023';
  end;
  if v_work is not null and not exists (select 1 from public.contract_works where id = v_work and project_id = v_proj) then
    raise exception 'البند المحدد ليس من بنود هذا العقد' using errcode = '22023';
  end if;

  -- البنود: تُتحقق كلها قبل أي كتابة
  for it in select * from jsonb_array_elements(v_items) loop
    n := n + 1;
    if jsonb_typeof(it) <> 'object' then
      raise exception 'البند % بصيغة غير صحيحة', n using errcode = '22023';
    end if;
    v_dir := public.jpick(it, 'direction', array['add', 'deduct'], 'add', 'اتجاه البند');
    v_desc := public.jtext(it, 'description', 500, 'وصف البند');
    if length(v_desc) < 2 then
      raise exception 'اكتب وصف البند %', n using errcode = '22023';
    end if;
    v_qty := public.jnum(it, 'qty', 0, 1e12, 'الكمية');
    v_price := public.jnum(it, 'unit_price', 0, 1e12, 'سعر الوحدة');
    v_lamt := case when v_qty is not null and v_price is not null then round(v_qty * v_price, 3)
                   else round(public.jnum(it, 'amount', 0, 1e13, 'قيمة البند'), 3) end;
    if coalesce(v_lamt, 0) <= 0 then
      raise exception 'قيمة البند % أكبر من صفر (الكمية × السعر أو القيمة)', n using errcode = '22023';
    end if;
    begin
      v_sheet := nullif(btrim(coalesce(it ->> 'boq_sheet_id', '')), '')::uuid;
      v_iwork := nullif(btrim(coalesce(it ->> 'work_id', '')), '')::uuid;
    exception when others then
      raise exception 'مرجع البند % غير صالح', n using errcode = '22023';
    end;
    v_line := public.jint(it, 'boq_line', 0, 100000, 'رقم سطر المقايسة');
    if v_sheet is not null then
      select jsonb_array_length(lines) into v_lines from public.boq_sheets where id = v_sheet and project_id = v_proj;
      if v_lines is null then
        raise exception 'المقايسة المرتبطة بالبند % ليست من مقايسات هذا العقد', n using errcode = '22023';
      end if;
      if v_line is null or v_line >= v_lines then
        raise exception 'بند المقايسة المرتبط بالبند % غير موجود فيها', n using errcode = '22023';
      end if;
    elsif v_line is not null then
      raise exception 'حدّد المقايسة لسطر البند %', n using errcode = '22023';
    end if;
    if v_iwork is not null and not exists (select 1 from public.contract_works where id = v_iwork and project_id = v_proj) then
      raise exception 'عمل العقد في البند % ليس من أعمال هذا العقد', n using errcode = '22023';
    end if;
    if v_dir = 'add' then v_add := v_add + v_lamt; else v_ded := v_ded + v_lamt; end if;
  end loop;

  if n > 0 then
    v_kind := case when v_add >= v_ded then 'add' else 'deduct' end;
    v_amt := abs(v_add - v_ded);
  else
    v_kind := public.jpick(p_data, 'kind', array['add', 'deduct'], 'add', 'نوع أمر التغيير');
    v_amt := round(public.jnum(p_data, 'amount', 0, 1e13, 'قيمة أمر التغيير'), 3);
    if coalesce(v_amt, 0) <= 0 then
      raise exception 'قيمة أمر التغيير أكبر من صفر' using errcode = '22023';
    end if;
    v_add := case when v_kind = 'add' then v_amt else 0 end;
    v_ded := case when v_kind = 'deduct' then v_amt else 0 end;
  end if;

  perform set_config('app.vo_lines', 'on', true);
  if v_new then
    insert into public.contract_variations (project_id, work_id, ref_no, title, kind, amount, added_value, deducted_value,
                                            status, approved_on, notes, created_by, updated_at, updated_by)
    values (v_proj, v_work, v_ref, v_title, v_kind, v_amt, v_add, v_ded, 'draft', null, v_notes, auth.uid(), now(), auth.uid())
    returning id into v_id;
  else
    update public.contract_variations
       set work_id = v_work, ref_no = v_ref, title = v_title, kind = v_kind, amount = v_amt,
           added_value = v_add, deducted_value = v_ded, notes = v_notes, updated_at = now(), updated_by = auth.uid()
     where id = v_id;
  end if;
  delete from public.contract_variation_items where variation_id = v_id;
  n := 0;
  for it in select * from jsonb_array_elements(v_items) loop
    n := n + 1;
    v_qty := public.jnum(it, 'qty', 0, 1e12, 'الكمية');
    v_price := public.jnum(it, 'unit_price', 0, 1e12, 'سعر الوحدة');
    insert into public.contract_variation_items (variation_id, sort, direction, boq_sheet_id, boq_line, work_id, code,
                                                 description, unit, qty, unit_price, amount)
    values (v_id, n, public.jpick(it, 'direction', array['add', 'deduct'], 'add', 'اتجاه البند'),
            nullif(btrim(coalesce(it ->> 'boq_sheet_id', '')), '')::uuid,
            public.jint(it, 'boq_line', 0, 100000, 'رقم سطر المقايسة'),
            nullif(btrim(coalesce(it ->> 'work_id', '')), '')::uuid,
            public.jtext(it, 'code', 40, 'رقم البند'), public.jtext(it, 'description', 500, 'وصف البند'),
            public.jtext(it, 'unit', 20, 'الوحدة'), round(v_qty, 3), round(v_price, 3),
            case when v_qty is not null and v_price is not null then round(v_qty * v_price, 3)
                 else round(public.jnum(it, 'amount', 0, 1e13, 'قيمة البند'), 3) end);
  end loop;
  perform set_config('app.vo_lines', 'off', true);

  v_after := public.variation_snapshot(v_id);
  insert into public.contract_variation_events (variation_id, action, actor, actor_name, snapshot)
  values (v_id, case when v_new then 'create' else 'update' end, auth.uid(), public.actor_name(auth.uid()), v_after);
  if v_new then
    perform public.write_audit('finance.variation_add', v_proj, null, jsonb_build_object(
      'variation_id', v_id, 'title', v_title, 'kind', v_kind, 'amount', v_amt, 'ref_no', v_ref,
      'added', v_add, 'deducted', v_ded, 'items', n, 'status', 'draft'));
  else
    perform public.write_audit('finance.variation_update', v_proj, null, jsonb_build_object(
      'variation_id', v_id, 'title', v_title, 'status', 'draft',
      'kind', jsonb_build_object('from', o.kind, 'to', v_kind),
      'amount', jsonb_build_object('from', o.amount, 'to', v_amt),
      'added', jsonb_build_object('from', o.added_value, 'to', v_add),
      'deducted', jsonb_build_object('from', o.deducted_value, 'to', v_ded),
      'items', jsonb_build_object('from', jsonb_array_length(v_before -> 'items'), 'to', n)));
  end if;
  return v_id;
end;
$$;

-- البت في أمر التغيير: اعتماد أو رفض المسودة، أو إعادتها إلى مسودة (المدير وحده)
create or replace function public.decide_variation(p_id uuid, p_decision text, p_note text default '', p_date date default null)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  v      public.contract_variations;
  v_note text := left(btrim(coalesce(p_note, '')), 1000);
  v_code text;
begin
  select * into v from public.contract_variations where id = p_id for update;
  if not found then
    raise exception 'أمر التغيير غير موجود' using errcode = 'P0002';
  end if;
  select code into v_code from public.pm_changes where variation_id = v.id;
  if v_code is not null then
    raise exception 'أمر التغيير هذا من سجل التغييرات (%)؛ يُبت فيه من هناك', v_code using errcode = 'P0001';
  end if;
  if p_decision in ('approve', 'reject') then
    if v.status <> 'draft' then
      raise exception 'يُبت في أمر التغيير وهو مسودة' using errcode = 'P0001';
    end if;
    if not public.can_approve_variation(v.project_id) then
      raise exception 'اعتماد أوامر التغيير ورفضها لمدير المكتب ولمن يعتمد المستخلصات' using errcode = '42501';
    end if;
    if p_decision = 'reject' and length(v_note) < 3 then
      raise exception 'اكتب سبب الرفض' using errcode = '22023';
    end if;
    update public.contract_variations
       set status = case when p_decision = 'approve' then 'approved' else 'rejected' end,
           approved_on = case when p_decision = 'approve' then coalesce(p_date, current_date) end,
           decided_by = auth.uid(), decided_at = now(), decision_note = v_note,
           updated_at = now(), updated_by = auth.uid()
     where id = p_id;
  elsif p_decision = 'reopen' then
    if v.status = 'draft' then
      raise exception 'أمر التغيير مسودة أصلاً' using errcode = 'P0001';
    end if;
    if not (public.is_director() and public.writes_allowed()) then
      raise exception 'إعادة أمر التغيير إلى مسودة لمدير المكتب وحده' using errcode = '42501';
    end if;
    if length(v_note) < 3 then
      raise exception 'اكتب سبب إعادته إلى مسودة' using errcode = '22023';
    end if;
    update public.contract_variations
       set status = 'draft', approved_on = null, decided_by = auth.uid(), decided_at = now(), decision_note = v_note,
           updated_at = now(), updated_by = auth.uid()
     where id = p_id;
  else
    raise exception 'قرار غير معروف' using errcode = '22023';
  end if;
  insert into public.contract_variation_events (variation_id, action, actor, actor_name, note, snapshot)
  values (p_id, p_decision, auth.uid(), public.actor_name(auth.uid()), v_note, public.variation_snapshot(p_id));
  perform public.write_audit('finance.variation_' || p_decision, v.project_id, null, jsonb_build_object(
    'variation_id', v.id, 'title', v.title, 'kind', v.kind, 'amount', v.amount,
    'added', v.added_value, 'deducted', v.deducted_value, 'note', v_note,
    'approved_on', case when p_decision = 'approve' then coalesce(p_date, current_date) end));
end;
$$;

-- الحذف: المسودة والمرفوض لمن يختص بالمالية، والمعتمد للمدير وحده
create or replace function public.delete_variation(p_id uuid)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  v public.contract_variations;
begin
  select * into v from public.contract_variations where id = p_id;
  if not found then
    raise exception 'أمر التغيير غير موجود' using errcode = '22023';
  end if;
  if not public.can_edit_finance(v.project_id) then
    raise exception 'أوامر التغيير يسجّلها من يختص بالبيانات المالية للعقد' using errcode = '42501';
  end if;
  if v.status = 'approved' and not public.is_director() then
    raise exception 'أمر التغيير المعتمد لا يحذفه إلا مدير المكتب' using errcode = '42501';
  end if;
  if v.origin_project is not null and v.origin_project <> v.project_id then
    raise exception 'أمر التغيير هذا دُمج من عقد آخر؛ افصله بفك الدمج بدل حذفه' using errcode = 'P0001';
  end if;
  delete from public.contract_variations where id = p_id;
  perform public.write_audit('finance.variation_delete', v.project_id, null, jsonb_build_object(
    'variation_id', v.id, 'title', v.title, 'kind', v.kind, 'amount', v.amount, 'status', v.status));
end;
$$;

-- ---------------------------------------------------------------------
-- 6. لجنة الاستلام: رئيس واحد وأعضاء بصفاتهم، ولا يتكرر عضو
-- ---------------------------------------------------------------------
create table if not exists public.contract_committees (
  id             uuid primary key default gen_random_uuid(),
  project_id     uuid not null references public.projects (id) on delete cascade,
  origin_project uuid references public.projects (id) on delete set null,
  kind           text not null check (kind in ('initial', 'final')),
  decision_no    text not null default '' check (length(decision_no) <= 60),
  decision_date  date,
  notes          text not null default '' check (length(notes) <= 1000),
  created_at     timestamptz not null default now(),
  created_by     uuid references public.profiles (id) on delete set null,
  updated_at     timestamptz not null default now(),
  updated_by     uuid references public.profiles (id) on delete set null
);
-- لجنة واحدة من كل نوع للعقد نفسه (لجان العقود المدموجة فيه تبقى بأصلها)
create unique index if not exists contract_committees_native_uq on public.contract_committees (project_id, kind)
  where origin_project is null;
create index if not exists contract_committees_origin_idx on public.contract_committees (origin_project);
create index if not exists contract_committees_created_by_idx on public.contract_committees (created_by);
create index if not exists contract_committees_updated_by_idx on public.contract_committees (updated_by);

create table if not exists public.contract_committee_members (
  id           uuid primary key default gen_random_uuid(),
  committee_id uuid not null references public.contract_committees (id) on delete cascade,
  role         text not null check (role in ('chair', 'member')),
  profile_id   uuid references public.profiles (id) on delete set null,
  name         text not null check (length(btrim(name)) between 2 and 120),
  name_key     text generated always as (public.pm_text_norm(name)) stored,
  title        text not null default '' check (length(title) <= 120),
  sort         integer not null default 0
);
create unique index if not exists contract_committee_one_chair on public.contract_committee_members (committee_id) where role = 'chair';
create unique index if not exists contract_committee_name_uq on public.contract_committee_members (committee_id, name_key);
create unique index if not exists contract_committee_profile_uq on public.contract_committee_members (committee_id, profile_id)
  where profile_id is not null;
create index if not exists contract_committee_members_profile_idx on public.contract_committee_members (profile_id);

create or replace function public.committee_snapshot(p_id uuid)
returns jsonb
language sql stable security definer set search_path = public
as $$
  select jsonb_build_object(
           'decision_no', c.decision_no, 'decision_date', c.decision_date, 'notes', c.notes,
           'chair', (select jsonb_build_object('name', m.name, 'title', m.title, 'profile_id', m.profile_id)
                       from public.contract_committee_members m where m.committee_id = c.id and m.role = 'chair'),
           'members', coalesce((select jsonb_agg(jsonb_build_object('name', m.name, 'title', m.title, 'profile_id', m.profile_id)
                                                 order by m.sort)
                                  from public.contract_committee_members m where m.committee_id = c.id and m.role = 'member'),
                               '[]'::jsonb))
    from public.contract_committees c where c.id = p_id
$$;

create or replace function public.save_committee(p_project uuid, p_kind text, p_data jsonb)
returns uuid
language plpgsql security definer set search_path = public
as $$
declare
  c        public.contract_committees;
  v_id     uuid;
  v_form   text;
  v_chair  jsonb;
  v_list   jsonb;
  m        jsonb;
  v_all    jsonb := '[]'::jsonb;
  v_seq    jsonb;
  v_name   text;
  v_title  text;
  v_prof   uuid;
  v_key    text;
  v_keys   text[] := '{}';
  v_profs  uuid[] := '{}';
  v_before jsonb;
  v_after  jsonb;
  i        integer := 0;
begin
  if p_kind is null or p_kind not in ('initial', 'final') then
    raise exception 'نوع اللجنة استلام ابتدائي أو نهائي' using errcode = '22023';
  end if;
  if jsonb_typeof(coalesce(p_data, 'null'::jsonb)) <> 'object' then
    raise exception 'بيانات غير صالحة' using errcode = '22023';
  end if;
  if not exists (select 1 from public.projects where id = p_project and merged_into is null) then
    raise exception 'العقد غير موجود أو مدموج في عقد آخر' using errcode = '22023';
  end if;
  v_form := case p_kind when 'initial' then 'f25' else 'f26' end;
  if not (public.writes_allowed() and public.can_edit_form(p_project, v_form)) then
    raise exception 'تشكيل لجنة الاستلام لمن يختص بنموذج «تكليف لجنة استلام %»',
      case p_kind when 'initial' then 'ابتدائي' else 'نهائي' end using errcode = '42501';
  end if;
  v_chair := p_data -> 'chair';
  if jsonb_typeof(coalesce(v_chair, 'null'::jsonb)) <> 'object' or length(btrim(coalesce(v_chair ->> 'name', ''))) < 2 then
    raise exception 'حدّد رئيس اللجنة' using errcode = '22023';
  end if;
  v_list := coalesce(p_data -> 'members', '[]'::jsonb);
  if jsonb_typeof(v_list) <> 'array' then
    raise exception 'أعضاء اللجنة بصيغة غير صحيحة' using errcode = '22023';
  end if;
  if jsonb_array_length(v_list) < 1 then
    raise exception 'أضف عضواً واحداً على الأقل مع رئيس اللجنة' using errcode = '22023';
  end if;
  if jsonb_array_length(v_list) > 30 then
    raise exception 'اللجنة حتى 30 عضواً' using errcode = '22023';
  end if;

  -- الرئيس أولاً ثم الأعضاء: لا يتكرر الاسم ولا الموظف
  v_seq := jsonb_build_array(v_chair) || v_list;
  for m in select x from jsonb_array_elements(v_seq) with ordinality as t(x, o) order by o loop
    i := i + 1;
    if jsonb_typeof(m) <> 'object' then
      raise exception 'عضو اللجنة بصيغة غير صحيحة' using errcode = '22023';
    end if;
    v_name := public.jtext(m, 'name', 120, 'اسم العضو');
    if length(v_name) < 2 then
      raise exception 'اكتب اسم كل عضو في اللجنة' using errcode = '22023';
    end if;
    v_title := public.jtext(m, 'title', 120, 'الصفة');
    begin
      v_prof := nullif(btrim(coalesce(m ->> 'profile_id', '')), '')::uuid;
    exception when others then
      raise exception 'الموظف المحدد للعضو «%» غير صالح', v_name using errcode = '22023';
    end;
    if v_prof is not null and not exists (select 1 from public.profiles where id = v_prof) then
      raise exception 'الموظف المحدد للعضو «%» غير موجود', v_name using errcode = '22023';
    end if;
    v_key := public.pm_text_norm(v_name);
    if v_key = any (v_keys) or (v_prof is not null and v_prof = any (v_profs)) then
      if i > 1 and (public.pm_text_norm(v_chair ->> 'name') = v_key
                    or (v_prof is not null and v_prof::text = coalesce(v_chair ->> 'profile_id', ''))) then
        raise exception '«%» رئيس اللجنة؛ لا يُضاف عضواً أيضاً', v_name using errcode = '22023';
      end if;
      raise exception 'العضو «%» مكرر في اللجنة', v_name using errcode = '22023';
    end if;
    v_keys := v_keys || v_key;
    if v_prof is not null then
      v_profs := v_profs || v_prof;
    end if;
    v_all := v_all || jsonb_build_array(jsonb_build_object('role', case when i = 1 then 'chair' else 'member' end,
                                                           'name', v_name, 'title', v_title, 'profile_id', v_prof));
  end loop;

  select * into c from public.contract_committees
   where project_id = p_project and kind = p_kind and origin_project is null for update;
  if found then
    v_id := c.id;
    v_before := public.committee_snapshot(c.id);
    update public.contract_committees
       set decision_no = public.jtext(p_data, 'decision_no', 60, 'رقم قرار التشكيل'),
           decision_date = public.jdate(p_data, 'decision_date', 'تاريخ القرار'),
           notes = public.jtext(p_data, 'notes', 1000, 'الملاحظات'),
           updated_at = now(), updated_by = auth.uid()
     where id = v_id;
    delete from public.contract_committee_members where committee_id = v_id;
  else
    insert into public.contract_committees (project_id, kind, decision_no, decision_date, notes, created_by, updated_by)
    values (p_project, p_kind, public.jtext(p_data, 'decision_no', 60, 'رقم قرار التشكيل'),
            public.jdate(p_data, 'decision_date', 'تاريخ القرار'), public.jtext(p_data, 'notes', 1000, 'الملاحظات'),
            auth.uid(), auth.uid())
    returning id into v_id;
  end if;
  insert into public.contract_committee_members (committee_id, role, profile_id, name, title, sort)
  select v_id, x ->> 'role', nullif(x ->> 'profile_id', '')::uuid, x ->> 'name', x ->> 'title', ord::integer - 1
    from jsonb_array_elements(v_all) with ordinality as t(x, ord);

  v_after := public.committee_snapshot(v_id);
  if v_before is distinct from v_after then
    perform public.write_audit('committee.save', p_project, v_form, jsonb_build_object(
      'kind', p_kind, 'from', v_before, 'to', v_after));
  end if;
  return v_id;
end;
$$;

create or replace function public.delete_committee(p_project uuid, p_kind text)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  c      public.contract_committees;
  v_form text := case p_kind when 'initial' then 'f25' when 'final' then 'f26' end;
begin
  if v_form is null then
    raise exception 'نوع اللجنة استلام ابتدائي أو نهائي' using errcode = '22023';
  end if;
  if not (public.writes_allowed() and public.can_edit_form(p_project, v_form)) then
    raise exception 'تشكيل لجنة الاستلام لمن يختص بنموذج تكليفها' using errcode = '42501';
  end if;
  select * into c from public.contract_committees
   where project_id = p_project and kind = p_kind and origin_project is null for update;
  if not found then
    return;
  end if;
  perform public.write_audit('committee.delete', p_project, v_form, jsonb_build_object(
    'kind', p_kind, 'from', public.committee_snapshot(c.id)));
  delete from public.contract_committees where id = c.id;
end;
$$;

-- اللجان تتبع العقد عند دمجه وفكّه (كأوامر التغيير والمستخلصات)
create or replace function public.committees_follow_merge()
returns trigger
language plpgsql security definer set search_path = public
as $$
begin
  if new.merged_into is not null and old.merged_into is null then
    update public.contract_committees set project_id = new.merged_into, origin_project = coalesce(origin_project, new.id)
     where project_id = new.id;
  elsif new.merged_into is null and old.merged_into is not null then
    update public.contract_committees set project_id = new.id, origin_project = null
     where project_id = old.merged_into and origin_project = new.id;
  end if;
  return null;
end;
$$;
drop trigger if exists projects_committees_follow_merge on public.projects;
create trigger projects_committees_follow_merge
  after update of merged_into on public.projects
  for each row when (old.merged_into is distinct from new.merged_into)
  execute function public.committees_follow_merge();

-- ---------------------------------------------------------------------
-- 7. الحساب الأول للمجاميع الجديدة، وسياسات الوصول والصلاحيات
-- ---------------------------------------------------------------------
do $$
declare
  r record;
begin
  for r in select id from public.projects where merged_into is null loop
    perform public.recalc_contract_finance(r.id);
  end loop;
end $$;

alter table public.contract_variation_items enable row level security;
alter table public.contract_variation_events enable row level security;
alter table public.contract_committees enable row level security;
alter table public.contract_committee_members enable row level security;

-- البنود والسجل بصلاحية قراءة أمر التغيير نفسه (عزل الأقسام)
drop policy if exists contract_variation_items_read on public.contract_variation_items;
create policy contract_variation_items_read on public.contract_variation_items for select to authenticated
  using (exists (select 1 from public.contract_variations v where v.id = variation_id));
drop policy if exists contract_variation_events_read on public.contract_variation_events;
create policy contract_variation_events_read on public.contract_variation_events for select to authenticated
  using (exists (select 1 from public.contract_variations v where v.id = variation_id));
-- اللجنة: من يرى العقد بتفاصيله، والقسم المشرف عليه، وقسم المطابقة والاستلام
drop policy if exists contract_committees_read on public.contract_committees;
create policy contract_committees_read on public.contract_committees for select to authenticated
  using ((select public.project_full_all()) or project_id = any ((select public.my_supervised())::uuid[])
         or (select public.sees_section('acceptance')));
drop policy if exists contract_committee_members_read on public.contract_committee_members;
create policy contract_committee_members_read on public.contract_committee_members for select to authenticated
  using (exists (select 1 from public.contract_committees c where c.id = committee_id));

revoke all on public.contract_variation_items, public.contract_variation_events, public.contract_committees,
  public.contract_committee_members from anon;
revoke insert, update, delete, truncate on public.contract_variation_items, public.contract_variation_events,
  public.contract_committees, public.contract_committee_members from authenticated;
grant select on public.contract_variation_items, public.contract_variation_events, public.contract_committees,
  public.contract_committee_members to authenticated;
grant all on public.contract_variation_items, public.contract_variation_events, public.contract_committees,
  public.contract_committee_members to service_role;

revoke execute on function public.set_contract_guarantees(uuid, jsonb), public.save_contract_variation(uuid, jsonb),
  public.decide_variation(uuid, text, text, date), public.save_committee(uuid, text, jsonb),
  public.delete_committee(uuid, text), public.can_approve_variation(uuid) from public, anon;
grant execute on function public.set_contract_guarantees(uuid, jsonb), public.save_contract_variation(uuid, jsonb),
  public.decide_variation(uuid, text, text, date), public.save_committee(uuid, text, jsonb),
  public.delete_committee(uuid, text), public.can_approve_variation(uuid) to authenticated;
-- داخلية: لا تُستدعى من التطبيق
revoke execute on function public.variation_snapshot(uuid), public.committee_snapshot(uuid),
  public.contract_variations_values(), public.contract_extracts_retention_guard(), public.committees_follow_merge()
  from public, anon, authenticated;
-- الصيغة السابقة لحفظ أمر التغيير كانت تسجّله معتمداً مباشرة؛ الحفظ الآن مسودة ثم اعتماد
revoke execute on function public.save_variation(uuid, uuid, uuid, text, text, text, numeric, date, text) from authenticated;
