-- =====================================================================
--  قسمان رئيسيان جديدان بجانب الدورة المستندية:
--    1. سجل المخاطر: تعريف الخطر، والتقييم قبل المعالجة وبعدها، وخطة الاستجابة
--       والمتابعة (من ملف «سجل المخاطر» المعتمد للمكتب).
--    2. تحليل SWOT: سجل العوامل وأولوياتها، والتقييم المرجح IFE/EFE،
--       واستراتيجيات TOWS، وخطة التنفيذ ومتابعتها (من ملف SWOT_RBCS v2.0).
--  القراءة لكل الأعضاء، والكتابة عبر دوال تتحقق من الصلاحية وتسجل في سجل التدقيق.
--  يُشغَّل بعد 20261105000014_fk_indexes.sql. إعادة تشغيله آمنة.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 0. أدوات عامة
-- ---------------------------------------------------------------------
-- الحقول التي تغيّرت بين نسختين من الصف (لسجل التدقيق)
create or replace function public.jsonb_changes(p_old jsonb, p_new jsonb, p_skip text[] default '{}')
returns jsonb
language sql immutable set search_path = public
as $$
  select coalesce(jsonb_object_agg(n.k, jsonb_build_object('from', o.v, 'to', n.v)), '{}'::jsonb)
    from jsonb_each(coalesce(p_new, '{}'::jsonb)) n(k, v)
    left join jsonb_each(coalesce(p_old, '{}'::jsonb)) o(k, v) on o.k = n.k
   where o.v is distinct from n.v and not (n.k = any (p_skip))
$$;

-- نص من حقل jsonb بعد التشذيب، مع حد أقصى للطول
create or replace function public.jtext(p_data jsonb, p_key text, p_max integer, p_label text)
returns text
language plpgsql immutable set search_path = public
as $$
declare
  v text := btrim(coalesce(p_data ->> p_key, ''));
begin
  if length(v) > p_max then
    raise exception '«%» أطول من % حرفاً', p_label, p_max using errcode = '22023';
  end if;
  return v;
end;
$$;

-- رقم صحيح من 1 إلى حد أعلى (أو فارغ)
create or replace function public.jscore(p_data jsonb, p_key text, p_max integer, p_label text, p_required boolean default false)
returns smallint
language plpgsql immutable set search_path = public
as $$
declare
  raw text := nullif(btrim(coalesce(p_data ->> p_key, '')), '');
  v   integer;
begin
  if raw is null then
    if p_required then
      raise exception 'حدّد «%» من 1 إلى %', p_label, p_max using errcode = '22023';
    end if;
    return null;
  end if;
  begin
    v := raw::integer;
  exception when others then
    raise exception '«%» يجب أن يكون رقماً من 1 إلى %', p_label, p_max using errcode = '22023';
  end;
  if v < 1 or v > p_max then
    raise exception '«%» يجب أن يكون من 1 إلى %', p_label, p_max using errcode = '22023';
  end if;
  return v::smallint;
end;
$$;

-- تاريخ من حقل jsonb (أو فارغ)
create or replace function public.jdate(p_data jsonb, p_key text, p_label text)
returns date
language plpgsql immutable set search_path = public
as $$
declare
  raw text := nullif(btrim(coalesce(p_data ->> p_key, '')), '');
begin
  if raw is null then return null; end if;
  begin
    return raw::date;
  exception when others then
    raise exception 'تاريخ غير صالح في «%»', p_label using errcode = '22023';
  end;
end;
$$;

-- قائمة رموز من حقل jsonb (مصفوفة نصوص أو نص مفصول بفواصل)
create or replace function public.jcodes(p_data jsonb, p_key text, p_pattern text, p_label text)
returns text[]
language plpgsql immutable set search_path = public
as $$
declare
  j   jsonb := p_data -> p_key;
  out text[] := '{}';
  c   text;
begin
  if j is null or jsonb_typeof(j) = 'null' then return out; end if;
  if jsonb_typeof(j) = 'array' then
    for c in select btrim(x) from jsonb_array_elements_text(j) x loop
      if c <> '' and not (c = any (out)) then out := out || upper(c); end if;
    end loop;
  else
    for c in select btrim(x) from regexp_split_to_table(j #>> '{}', '[,،\s]+') x loop
      if c <> '' and not (upper(c) = any (out)) then out := out || upper(c); end if;
    end loop;
  end if;
  foreach c in array out loop
    if c !~ p_pattern then
      raise exception 'رمز غير صالح «%» في «%»', c, p_label using errcode = '22023';
    end if;
  end loop;
  if cardinality(out) > 20 then
    raise exception 'رموز كثيرة في «%»', p_label using errcode = '22023';
  end if;
  return out;
end;
$$;

-- من يعدّل سجل المخاطر: كل عضو عدا مدقق الأمن، ما لم تكن المنظومة مجمّدة
create or replace function public.can_edit_risks()
returns boolean
language sql stable security definer set search_path = public
as $$
  select public.writes_allowed() and coalesce(public.my_role()::text, 'security_auditor') <> 'security_auditor'
$$;

-- من يعدّل تحليل SWOT (العوامل والاستراتيجيات والخطة): المدير وفريق مكتب المدير
create or replace function public.can_edit_swot()
returns boolean
language sql stable security definer set search_path = public
as $$
  select public.writes_allowed() and coalesce(public.my_role()::text, '') in ('director', 'office_staff')
$$;

-- من يحدّث تقدم إجراء في خطة التنفيذ: محررو SWOT، ورئيس القسم المسؤول عن الإجراء
create or replace function public.can_update_swot_action(p_department text)
returns boolean
language plpgsql stable security definer set search_path = public
as $$
declare
  me public.profiles;
  dn text;
begin
  if public.can_edit_swot() then return true; end if;
  if not public.writes_allowed() or coalesce(public.my_role()::text, '') <> 'dept_head' then return false; end if;
  select * into me from public.profiles where id = auth.uid();
  select name into dn from public.departments where key = me.department;
  return p_department = 'جميع الأقسام' or (dn is not null and p_department in ('قسم ' || dn, dn));
end;
$$;

-- ---------------------------------------------------------------------
-- 1. سجل المخاطر
-- ---------------------------------------------------------------------
create table if not exists public.risks (
  id                   uuid primary key default gen_random_uuid(),
  code                 text not null unique check (code ~ '^R[0-9]{2,4}$'),
  project_group        text not null default '' check (length(project_group) <= 60),
  project_id           uuid references public.projects (id) on delete set null,
  phase                text not null default '' check (length(phase) <= 40),
  category             text not null default '' check (length(category) <= 40),
  description          text not null check (length(btrim(description)) between 3 and 300),
  cause                text not null default '' check (length(cause) <= 500),
  effect               text not null default '' check (length(effect) <= 500),
  probability          smallint not null check (probability between 1 and 5),
  impact               smallint not null check (impact between 1 and 5),
  score                smallint generated always as (probability * impact) stored,
  mitigation           text not null default '' check (length(mitigation) <= 600),
  response             text not null default '' check (response in ('', 'avoid', 'mitigate', 'transfer', 'accept')),
  owner                text not null default '' check (length(owner) <= 60),
  status               text not null default 'open' check (status in ('open', 'in_progress', 'on_hold', 'closed')),
  residual_probability smallint check (residual_probability between 1 and 5),
  residual_impact      smallint check (residual_impact between 1 and 5),
  residual_score       smallint generated always as (residual_probability * residual_impact) stored,
  next_review          date,
  registered_on        date not null default current_date,
  target_date          date,
  closed_on            date,
  early_warning        text not null default '' check (length(early_warning) <= 300),
  notes                text not null default '' check (length(notes) <= 1000),
  created_at           timestamptz not null default now(),
  created_by           uuid references public.profiles (id) on delete set null,
  updated_at           timestamptz not null default now(),
  updated_by           uuid references public.profiles (id) on delete set null,
  check ((residual_probability is null) = (residual_impact is null)),
  check ((status = 'closed') = (closed_on is not null))
);
create index if not exists risks_project_idx    on public.risks (project_id);
create index if not exists risks_created_by_idx on public.risks (created_by);
create index if not exists risks_updated_by_idx on public.risks (updated_by);

alter table public.risks enable row level security;
drop policy if exists risks_read on public.risks;
create policy risks_read on public.risks for select to authenticated using ((select public.is_member()));
revoke all on public.risks from anon;
revoke insert, update, delete, truncate on public.risks from authenticated;
grant select on public.risks to authenticated;
grant all on public.risks to service_role;

-- حفظ خطر (جديد أو تعديل). يُرسل التطبيق السجل كاملاً في p_data.
create or replace function public.save_risk(p_id uuid, p_data jsonb)
returns uuid
language plpgsql security definer set search_path = public
as $$
declare
  old_row public.risks;
  new_row public.risks;
  v_code  text := upper(nullif(btrim(coalesce(p_data ->> 'code', '')), ''));
  v_proj  uuid;
  v_stat  text := coalesce(nullif(p_data ->> 'status', ''), 'open');
  v_resp  text := coalesce(p_data ->> 'response', '');
  v_rp    smallint := public.jscore(p_data, 'residual_probability', 5, 'الاحتمالية بعد المعالجة');
  v_ri    smallint := public.jscore(p_data, 'residual_impact', 5, 'التأثير بعد المعالجة');
  v_closed date := public.jdate(p_data, 'closed_on', 'تاريخ الإغلاق');
  v_desc  text := public.jtext(p_data, 'description', 300, 'وصف الخطر');
begin
  if not public.can_edit_risks() then
    raise exception 'لا تملك صلاحية تعديل سجل المخاطر' using errcode = '42501';
  end if;
  if jsonb_typeof(coalesce(p_data, 'null'::jsonb)) <> 'object' then
    raise exception 'بيانات الخطر غير صالحة' using errcode = '22023';
  end if;
  if length(v_desc) < 3 then
    raise exception 'اكتب وصف الخطر' using errcode = '22023';
  end if;
  if v_stat not in ('open', 'in_progress', 'on_hold', 'closed') then
    raise exception 'حالة خطر غير معروفة' using errcode = '22023';
  end if;
  if v_resp not in ('', 'avoid', 'mitigate', 'transfer', 'accept') then
    raise exception 'نوع استجابة غير معروف' using errcode = '22023';
  end if;
  if (v_rp is null) <> (v_ri is null) then
    raise exception 'حدّد الاحتمالية والتأثير بعد المعالجة معاً، أو اتركهما فارغين' using errcode = '22023';
  end if;
  if nullif(p_data ->> 'project_id', '') is not null then
    begin
      v_proj := (p_data ->> 'project_id')::uuid;
    exception when others then
      raise exception 'عقد غير صالح' using errcode = '22023';
    end;
    if not exists (select 1 from public.projects where id = v_proj) then
      raise exception 'العقد المرتبط غير موجود' using errcode = '22023';
    end if;
  end if;
  if v_code is not null and v_code !~ '^R[0-9]{2,4}$' then
    raise exception 'رمز الخطر بالصيغة R01' using errcode = '22023';
  end if;
  v_closed := case when v_stat = 'closed' then coalesce(v_closed, current_date) end;

  if p_id is not null then
    select * into old_row from public.risks where id = p_id for update;
    if not found then
      raise exception 'الخطر غير موجود' using errcode = 'P0002';
    end if;
    v_code := coalesce(v_code, old_row.code);
  elsif v_code is null then
    select 'R' || lpad((coalesce(max(substring(code from 2)::integer), 0) + 1)::text, 2, '0') into v_code
      from public.risks where code ~ '^R[0-9]+$';
  end if;
  if exists (select 1 from public.risks where code = v_code and id is distinct from p_id) then
    raise exception 'الرمز % مستخدم لخطر آخر', v_code using errcode = '23505';
  end if;

  if p_id is null then
    insert into public.risks (code, project_group, project_id, phase, category, description, cause, effect, probability, impact,
                              mitigation, response, owner, status, residual_probability, residual_impact, next_review,
                              registered_on, target_date, closed_on, early_warning, notes, created_by, updated_by)
    values (v_code, public.jtext(p_data, 'project_group', 60, 'المشروع'), v_proj,
            public.jtext(p_data, 'phase', 40, 'المرحلة'), public.jtext(p_data, 'category', 40, 'التصنيف'), v_desc,
            public.jtext(p_data, 'cause', 500, 'السبب'), public.jtext(p_data, 'effect', 500, 'الأثر'),
            public.jscore(p_data, 'probability', 5, 'الاحتمالية', true), public.jscore(p_data, 'impact', 5, 'التأثير', true),
            public.jtext(p_data, 'mitigation', 600, 'الإجراء الوقائي'), v_resp, public.jtext(p_data, 'owner', 60, 'المسؤول'),
            v_stat, v_rp, v_ri, public.jdate(p_data, 'next_review', 'موعد المراجعة القادمة'),
            coalesce(public.jdate(p_data, 'registered_on', 'تاريخ التسجيل'), current_date),
            public.jdate(p_data, 'target_date', 'الموعد المستهدف'), v_closed,
            public.jtext(p_data, 'early_warning', 300, 'مؤشر الإنذار المبكر'), public.jtext(p_data, 'notes', 1000, 'الملاحظات'),
            auth.uid(), auth.uid())
    returning * into new_row;
    perform public.write_audit('risk.create', v_proj, null,
      jsonb_build_object('code', new_row.code, 'description', new_row.description, 'score', new_row.score), new_row.code);
  else
    update public.risks set
      code = v_code,
      project_group = public.jtext(p_data, 'project_group', 60, 'المشروع'),
      project_id = v_proj,
      phase = public.jtext(p_data, 'phase', 40, 'المرحلة'),
      category = public.jtext(p_data, 'category', 40, 'التصنيف'),
      description = v_desc,
      cause = public.jtext(p_data, 'cause', 500, 'السبب'),
      effect = public.jtext(p_data, 'effect', 500, 'الأثر'),
      probability = public.jscore(p_data, 'probability', 5, 'الاحتمالية', true),
      impact = public.jscore(p_data, 'impact', 5, 'التأثير', true),
      mitigation = public.jtext(p_data, 'mitigation', 600, 'الإجراء الوقائي'),
      response = v_resp,
      owner = public.jtext(p_data, 'owner', 60, 'المسؤول'),
      status = v_stat,
      residual_probability = v_rp,
      residual_impact = v_ri,
      next_review = public.jdate(p_data, 'next_review', 'موعد المراجعة القادمة'),
      registered_on = coalesce(public.jdate(p_data, 'registered_on', 'تاريخ التسجيل'), old_row.registered_on),
      target_date = public.jdate(p_data, 'target_date', 'الموعد المستهدف'),
      closed_on = v_closed,
      early_warning = public.jtext(p_data, 'early_warning', 300, 'مؤشر الإنذار المبكر'),
      notes = public.jtext(p_data, 'notes', 1000, 'الملاحظات'),
      updated_at = now(),
      updated_by = auth.uid()
    where id = p_id
    returning * into new_row;
    if public.jsonb_changes(to_jsonb(old_row), to_jsonb(new_row),
                            array['updated_at', 'updated_by', 'score', 'residual_score']) <> '{}'::jsonb then
      perform public.write_audit('risk.update', coalesce(v_proj, old_row.project_id), null,
        jsonb_build_object('code', new_row.code,
                           'changes', public.jsonb_changes(to_jsonb(old_row), to_jsonb(new_row),
                                                           array['updated_at', 'updated_by', 'score', 'residual_score'])),
        new_row.code);
    end if;
  end if;
  return new_row.id;
end;
$$;

create or replace function public.delete_risk(p_id uuid)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  r public.risks;
begin
  if not public.is_director() then
    raise exception 'حذف المخاطر من صلاحية مدير المكتب وحده' using errcode = '42501';
  end if;
  delete from public.risks where id = p_id returning * into r;
  if not found then
    raise exception 'الخطر غير موجود' using errcode = 'P0002';
  end if;
  perform public.write_audit('risk.delete', r.project_id, null,
    jsonb_build_object('code', r.code, 'description', r.description, 'score', r.score, 'status', r.status), r.code);
end;
$$;

-- ---------------------------------------------------------------------
-- 2. تحليل SWOT
-- ---------------------------------------------------------------------
create table if not exists public.swot_factors (
  id         uuid primary key default gen_random_uuid(),
  code       text not null unique check (code ~ '^[SWOT][0-9]{2,3}$'),
  kind       text not null check (kind in ('S', 'W', 'O', 'T')),
  factor     text not null check (length(btrim(factor)) between 3 and 300),
  impact     text not null default '' check (length(impact) <= 300),
  department text not null default '' check (length(department) <= 60),
  importance smallint not null check (importance between 1 and 5),
  urgency    smallint not null check (urgency between 1 and 5),
  priority   smallint generated always as (importance * urgency) stored,
  evidence   text not null default '' check (length(evidence) <= 300),
  source     text not null default '' check (length(source) <= 80),
  rating     smallint check (rating between 1 and 4),
  sort       integer not null default 0,
  updated_at timestamptz not null default now(),
  updated_by uuid references public.profiles (id) on delete set null,
  check (left(code, 1) = kind)
);
create index if not exists swot_factors_updated_by_idx on public.swot_factors (updated_by);

create table if not exists public.swot_strategies (
  id               uuid primary key default gen_random_uuid(),
  code             text not null unique check (code ~ '^(SO|WO|ST|WT)[0-9]{1,2}$'),
  kind             text not null check (kind in ('SO', 'WO', 'ST', 'WT')),
  strategy         text not null check (length(btrim(strategy)) between 3 and 400),
  internal_factors text[] not null default '{}',
  external_factors text[] not null default '{}',
  priority         text not null default 'medium' check (priority in ('high', 'medium', 'low')),
  lead_department  text not null default '' check (length(lead_department) <= 60),
  source           text not null default '' check (length(source) <= 80),
  sort             integer not null default 0,
  updated_at       timestamptz not null default now(),
  updated_by       uuid references public.profiles (id) on delete set null,
  check (left(code, 2) = kind)
);
create index if not exists swot_strategies_updated_by_idx on public.swot_strategies (updated_by);

create table if not exists public.swot_actions (
  id              uuid primary key default gen_random_uuid(),
  code            text not null unique check (code ~ '^A[0-9]{2,3}$'),
  strategy_code   text references public.swot_strategies (code) on update cascade on delete restrict,
  factors         text[] not null default '{}',
  action          text not null check (length(btrim(action)) between 3 and 500),
  output          text not null default '' check (length(output) <= 300),
  department      text not null default '' check (length(department) <= 60),
  owner           text not null default '' check (length(owner) <= 120),
  kpi             text not null default '' check (length(kpi) <= 300),
  priority        text not null default 'medium' check (priority in ('high', 'medium', 'low')),
  start_date      date,
  duration_months smallint check (duration_months between 1 and 60),
  verification    text not null default '' check (length(verification) <= 300),
  review_cycle    text not null default '' check (length(review_cycle) <= 40),
  status          text not null default 'not_started'
                  check (status in ('not_started', 'in_progress', 'completed', 'stalled', 'on_hold')),
  progress        numeric(5, 4) check (progress between 0 and 1),
  notes           text not null default '' check (length(notes) <= 1000),
  source          text not null default '' check (length(source) <= 80),
  sort            integer not null default 0,
  updated_at      timestamptz not null default now(),
  updated_by      uuid references public.profiles (id) on delete set null
);
create index if not exists swot_actions_strategy_idx   on public.swot_actions (strategy_code);
create index if not exists swot_actions_updated_by_idx on public.swot_actions (updated_by);

alter table public.swot_factors    enable row level security;
alter table public.swot_strategies enable row level security;
alter table public.swot_actions    enable row level security;
drop policy if exists swot_factors_read on public.swot_factors;
drop policy if exists swot_strategies_read on public.swot_strategies;
drop policy if exists swot_actions_read on public.swot_actions;
create policy swot_factors_read    on public.swot_factors    for select to authenticated using ((select public.is_member()));
create policy swot_strategies_read on public.swot_strategies for select to authenticated using ((select public.is_member()));
create policy swot_actions_read    on public.swot_actions    for select to authenticated using ((select public.is_member()));
revoke all on public.swot_factors, public.swot_strategies, public.swot_actions from anon;
revoke insert, update, delete, truncate on public.swot_factors, public.swot_strategies, public.swot_actions from authenticated;
grant select on public.swot_factors, public.swot_strategies, public.swot_actions to authenticated;
grant all on public.swot_factors, public.swot_strategies, public.swot_actions to service_role;

-- العامل: جديد أو تعديل. تغيير الرمز يُحدَّث في الاستراتيجيات والإجراءات المرتبطة.
create or replace function public.save_swot_factor(p_id uuid, p_data jsonb)
returns uuid
language plpgsql security definer set search_path = public
as $$
declare
  old_row public.swot_factors;
  new_row public.swot_factors;
  v_kind  text := upper(btrim(coalesce(p_data ->> 'kind', '')));
  v_code  text := upper(nullif(btrim(coalesce(p_data ->> 'code', '')), ''));
  v_fac   text := public.jtext(p_data, 'factor', 300, 'العامل');
  v_rate  smallint := public.jscore(p_data, 'rating', 4, 'التقييم');
  v_chg   jsonb;
begin
  if not public.can_edit_swot() then
    raise exception 'تعديل تحليل SWOT لمدير المكتب وفريق مكتبه' using errcode = '42501';
  end if;
  if v_kind not in ('S', 'W', 'O', 'T') then
    raise exception 'حدّد تصنيف العامل' using errcode = '22023';
  end if;
  if length(v_fac) < 3 then
    raise exception 'اكتب العامل' using errcode = '22023';
  end if;
  if v_rate is not null and ((v_kind = 'S' and v_rate < 3) or (v_kind = 'W' and v_rate > 2)) then
    raise exception 'تقييم IFE: نقاط القوة 3 أو 4، ونقاط الضعف 1 أو 2' using errcode = '22023';
  end if;
  if p_id is not null then
    select * into old_row from public.swot_factors where id = p_id for update;
    if not found then
      raise exception 'العامل غير موجود' using errcode = 'P0002';
    end if;
    if v_code is null and old_row.kind = v_kind then v_code := old_row.code; end if;
  end if;
  if v_code is null then
    select v_kind || lpad((coalesce(max(substring(code from 2)::integer), 0) + 1)::text, 2, '0') into v_code
      from public.swot_factors where kind = v_kind and code ~ '^[SWOT][0-9]+$';
  end if;
  if v_code !~ '^[SWOT][0-9]{2,3}$' or left(v_code, 1) <> v_kind then
    raise exception 'رمز العامل يبدأ بحرف تصنيفه (مثل %01)', v_kind using errcode = '22023';
  end if;
  if exists (select 1 from public.swot_factors where code = v_code and id is distinct from p_id) then
    raise exception 'الرمز % مستخدم لعامل آخر', v_code using errcode = '23505';
  end if;

  if p_id is null then
    insert into public.swot_factors (code, kind, factor, impact, department, importance, urgency, evidence, source, rating, sort, updated_by)
    values (v_code, v_kind, v_fac, public.jtext(p_data, 'impact', 300, 'الأثر المتوقع'),
            public.jtext(p_data, 'department', 60, 'القسم المعني'),
            public.jscore(p_data, 'importance', 5, 'الأهمية', true), public.jscore(p_data, 'urgency', 5, 'الاستعجال', true),
            public.jtext(p_data, 'evidence', 300, 'مصدر التحقق'), public.jtext(p_data, 'source', 80, 'مصدر البند'), v_rate,
            coalesce((select max(sort) + 1 from public.swot_factors), 1), auth.uid())
    returning * into new_row;
    perform public.write_audit('swot.factor', null, null,
      jsonb_build_object('op', 'create', 'code', new_row.code, 'factor', new_row.factor), new_row.code);
  else
    update public.swot_factors set
      code = v_code, kind = v_kind, factor = v_fac,
      impact = public.jtext(p_data, 'impact', 300, 'الأثر المتوقع'),
      department = public.jtext(p_data, 'department', 60, 'القسم المعني'),
      importance = public.jscore(p_data, 'importance', 5, 'الأهمية', true),
      urgency = public.jscore(p_data, 'urgency', 5, 'الاستعجال', true),
      evidence = public.jtext(p_data, 'evidence', 300, 'مصدر التحقق'),
      source = public.jtext(p_data, 'source', 80, 'مصدر البند'),
      rating = v_rate, updated_at = now(), updated_by = auth.uid()
    where id = p_id
    returning * into new_row;
    if new_row.code <> old_row.code then
      update public.swot_strategies set
        internal_factors = array_replace(internal_factors, old_row.code, new_row.code),
        external_factors = array_replace(external_factors, old_row.code, new_row.code)
      where old_row.code = any (internal_factors) or old_row.code = any (external_factors);
      update public.swot_actions set factors = array_replace(factors, old_row.code, new_row.code)
      where old_row.code = any (factors);
    end if;
    v_chg := public.jsonb_changes(to_jsonb(old_row), to_jsonb(new_row), array['updated_at', 'updated_by', 'priority', 'sort']);
    if v_chg <> '{}'::jsonb then
      perform public.write_audit('swot.factor', null, null,
        jsonb_build_object('op', 'update', 'code', new_row.code, 'changes', v_chg), new_row.code);
    end if;
  end if;
  return new_row.id;
end;
$$;

create or replace function public.delete_swot_factor(p_id uuid)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  r public.swot_factors;
begin
  if not public.is_director() then
    raise exception 'الحذف من صلاحية مدير المكتب وحده' using errcode = '42501';
  end if;
  delete from public.swot_factors where id = p_id returning * into r;
  if not found then
    raise exception 'العامل غير موجود' using errcode = 'P0002';
  end if;
  update public.swot_strategies set
    internal_factors = array_remove(internal_factors, r.code),
    external_factors = array_remove(external_factors, r.code)
  where r.code = any (internal_factors) or r.code = any (external_factors);
  update public.swot_actions set factors = array_remove(factors, r.code) where r.code = any (factors);
  perform public.write_audit('swot.delete', null, null, jsonb_build_object('item', 'factor', 'code', r.code, 'text', r.factor), r.code);
end;
$$;

create or replace function public.save_swot_strategy(p_id uuid, p_data jsonb)
returns uuid
language plpgsql security definer set search_path = public
as $$
declare
  old_row public.swot_strategies;
  new_row public.swot_strategies;
  v_kind  text := upper(btrim(coalesce(p_data ->> 'kind', '')));
  v_code  text := upper(nullif(btrim(coalesce(p_data ->> 'code', '')), ''));
  v_text  text := public.jtext(p_data, 'strategy', 400, 'الاستراتيجية');
  v_int   text[] := public.jcodes(p_data, 'internal_factors', '^[SW][0-9]{2,3}$', 'العوامل الداخلية');
  v_ext   text[] := public.jcodes(p_data, 'external_factors', '^[OT][0-9]{2,3}$', 'العوامل الخارجية');
  v_pri   text := coalesce(nullif(p_data ->> 'priority', ''), 'medium');
  v_chg   jsonb;
begin
  if not public.can_edit_swot() then
    raise exception 'تعديل تحليل SWOT لمدير المكتب وفريق مكتبه' using errcode = '42501';
  end if;
  if v_kind not in ('SO', 'WO', 'ST', 'WT') then
    raise exception 'حدّد نوع الاستراتيجية' using errcode = '22023';
  end if;
  if length(v_text) < 3 then
    raise exception 'اكتب الاستراتيجية' using errcode = '22023';
  end if;
  if v_pri not in ('high', 'medium', 'low') then
    raise exception 'أولوية غير معروفة' using errcode = '22023';
  end if;
  if p_id is not null then
    select * into old_row from public.swot_strategies where id = p_id for update;
    if not found then
      raise exception 'الاستراتيجية غير موجودة' using errcode = 'P0002';
    end if;
    if v_code is null and old_row.kind = v_kind then v_code := old_row.code; end if;
  end if;
  if v_code is null then
    select v_kind || (coalesce(max(substring(code from 3)::integer), 0) + 1)::text into v_code
      from public.swot_strategies where kind = v_kind and code ~ '^(SO|WO|ST|WT)[0-9]+$';
  end if;
  if v_code !~ '^(SO|WO|ST|WT)[0-9]{1,2}$' or left(v_code, 2) <> v_kind then
    raise exception 'رمز الاستراتيجية يبدأ بنوعها (مثل %1)', v_kind using errcode = '22023';
  end if;
  if exists (select 1 from public.swot_strategies where code = v_code and id is distinct from p_id) then
    raise exception 'الرمز % مستخدم لاستراتيجية أخرى', v_code using errcode = '23505';
  end if;

  if p_id is null then
    insert into public.swot_strategies (code, kind, strategy, internal_factors, external_factors, priority, lead_department, source, sort, updated_by)
    values (v_code, v_kind, v_text, v_int, v_ext, v_pri, public.jtext(p_data, 'lead_department', 60, 'القسم القائد'),
            public.jtext(p_data, 'source', 80, 'مصدر البند'), coalesce((select max(sort) + 1 from public.swot_strategies), 1), auth.uid())
    returning * into new_row;
    perform public.write_audit('swot.strategy', null, null,
      jsonb_build_object('op', 'create', 'code', new_row.code, 'strategy', new_row.strategy), new_row.code);
  else
    update public.swot_strategies set
      code = v_code, kind = v_kind, strategy = v_text, internal_factors = v_int, external_factors = v_ext, priority = v_pri,
      lead_department = public.jtext(p_data, 'lead_department', 60, 'القسم القائد'),
      source = public.jtext(p_data, 'source', 80, 'مصدر البند'),
      updated_at = now(), updated_by = auth.uid()
    where id = p_id
    returning * into new_row;
    v_chg := public.jsonb_changes(to_jsonb(old_row), to_jsonb(new_row), array['updated_at', 'updated_by', 'sort']);
    if v_chg <> '{}'::jsonb then
      perform public.write_audit('swot.strategy', null, null,
        jsonb_build_object('op', 'update', 'code', new_row.code, 'changes', v_chg), new_row.code);
    end if;
  end if;
  return new_row.id;
end;
$$;

create or replace function public.delete_swot_strategy(p_id uuid)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  r public.swot_strategies;
  n integer;
begin
  if not public.is_director() then
    raise exception 'الحذف من صلاحية مدير المكتب وحده' using errcode = '42501';
  end if;
  select * into r from public.swot_strategies where id = p_id for update;
  if not found then
    raise exception 'الاستراتيجية غير موجودة' using errcode = 'P0002';
  end if;
  select count(*) into n from public.swot_actions where strategy_code = r.code;
  if n > 0 then
    raise exception 'الاستراتيجية % مرتبطة بـ % إجراء في خطة التنفيذ؛ انقلها أو احذفها أولاً', r.code, n using errcode = 'P0001';
  end if;
  delete from public.swot_strategies where id = p_id;
  perform public.write_audit('swot.delete', null, null, jsonb_build_object('item', 'strategy', 'code', r.code, 'text', r.strategy), r.code);
end;
$$;

create or replace function public.save_swot_action(p_id uuid, p_data jsonb)
returns uuid
language plpgsql security definer set search_path = public
as $$
declare
  old_row public.swot_actions;
  new_row public.swot_actions;
  v_code  text := upper(nullif(btrim(coalesce(p_data ->> 'code', '')), ''));
  v_strat text := upper(nullif(btrim(coalesce(p_data ->> 'strategy_code', '')), ''));
  v_text  text := public.jtext(p_data, 'action', 500, 'الإجراء التنفيذي');
  v_pri   text := coalesce(nullif(p_data ->> 'priority', ''), 'medium');
  v_stat  text := coalesce(nullif(p_data ->> 'status', ''), 'not_started');
  v_prog  numeric;
  v_dur   smallint := public.jscore(p_data, 'duration_months', 60, 'المدة بالأشهر');
  v_chg   jsonb;
begin
  if not public.can_edit_swot() then
    raise exception 'تعديل خطة التنفيذ لمدير المكتب وفريق مكتبه' using errcode = '42501';
  end if;
  if length(v_text) < 3 then
    raise exception 'اكتب الإجراء التنفيذي' using errcode = '22023';
  end if;
  if v_pri not in ('high', 'medium', 'low') then
    raise exception 'أولوية غير معروفة' using errcode = '22023';
  end if;
  if v_stat not in ('not_started', 'in_progress', 'completed', 'stalled', 'on_hold') then
    raise exception 'حالة تنفيذ غير معروفة' using errcode = '22023';
  end if;
  if v_strat is not null and not exists (select 1 from public.swot_strategies where code = v_strat) then
    raise exception 'الاستراتيجية % غير موجودة', v_strat using errcode = '22023';
  end if;
  if nullif(p_data ->> 'progress', '') is not null then
    begin
      v_prog := (p_data ->> 'progress')::numeric;
    exception when others then
      raise exception 'نسبة الإنجاز رقم من 0 إلى 1' using errcode = '22023';
    end;
    if v_prog < 0 or v_prog > 1 then
      raise exception 'نسبة الإنجاز من 0 إلى 100%%' using errcode = '22023';
    end if;
  end if;
  if v_stat = 'completed' then v_prog := 1; end if;

  if p_id is not null then
    select * into old_row from public.swot_actions where id = p_id for update;
    if not found then
      raise exception 'الإجراء غير موجود' using errcode = 'P0002';
    end if;
    v_code := coalesce(v_code, old_row.code);
  elsif v_code is null then
    select 'A' || lpad((coalesce(max(substring(code from 2)::integer), 0) + 1)::text, 2, '0') into v_code
      from public.swot_actions where code ~ '^A[0-9]+$';
  end if;
  if v_code !~ '^A[0-9]{2,3}$' then
    raise exception 'رمز الإجراء بالصيغة A01' using errcode = '22023';
  end if;
  if exists (select 1 from public.swot_actions where code = v_code and id is distinct from p_id) then
    raise exception 'الرمز % مستخدم لإجراء آخر', v_code using errcode = '23505';
  end if;

  if p_id is null then
    insert into public.swot_actions (code, strategy_code, factors, action, output, department, owner, kpi, priority, start_date,
                                     duration_months, verification, review_cycle, status, progress, notes, source, sort, updated_by)
    values (v_code, v_strat, public.jcodes(p_data, 'factors', '^[SWOT][0-9]{2,3}$', 'العوامل المرتبطة'), v_text,
            public.jtext(p_data, 'output', 300, 'المخرج المتوقع'), public.jtext(p_data, 'department', 60, 'القسم المسؤول'),
            public.jtext(p_data, 'owner', 120, 'المسؤول المباشر'), public.jtext(p_data, 'kpi', 300, 'مؤشر القياس'), v_pri,
            public.jdate(p_data, 'start_date', 'تاريخ البدء'), v_dur, public.jtext(p_data, 'verification', 300, 'مصدر التحقق'),
            public.jtext(p_data, 'review_cycle', 40, 'دورية المراجعة'), v_stat, v_prog, public.jtext(p_data, 'notes', 1000, 'الملاحظات'),
            public.jtext(p_data, 'source', 80, 'مصدر البند'), coalesce((select max(sort) + 1 from public.swot_actions), 1), auth.uid())
    returning * into new_row;
    perform public.write_audit('swot.action', null, null,
      jsonb_build_object('op', 'create', 'code', new_row.code, 'action', new_row.action), new_row.code);
  else
    update public.swot_actions set
      code = v_code, strategy_code = v_strat,
      factors = public.jcodes(p_data, 'factors', '^[SWOT][0-9]{2,3}$', 'العوامل المرتبطة'),
      action = v_text,
      output = public.jtext(p_data, 'output', 300, 'المخرج المتوقع'),
      department = public.jtext(p_data, 'department', 60, 'القسم المسؤول'),
      owner = public.jtext(p_data, 'owner', 120, 'المسؤول المباشر'),
      kpi = public.jtext(p_data, 'kpi', 300, 'مؤشر القياس'),
      priority = v_pri,
      start_date = public.jdate(p_data, 'start_date', 'تاريخ البدء'),
      duration_months = v_dur,
      verification = public.jtext(p_data, 'verification', 300, 'مصدر التحقق'),
      review_cycle = public.jtext(p_data, 'review_cycle', 40, 'دورية المراجعة'),
      status = v_stat, progress = v_prog,
      notes = public.jtext(p_data, 'notes', 1000, 'الملاحظات'),
      source = public.jtext(p_data, 'source', 80, 'مصدر البند'),
      updated_at = now(), updated_by = auth.uid()
    where id = p_id
    returning * into new_row;
    v_chg := public.jsonb_changes(to_jsonb(old_row), to_jsonb(new_row), array['updated_at', 'updated_by', 'sort']);
    if v_chg <> '{}'::jsonb then
      perform public.write_audit('swot.action', null, null,
        jsonb_build_object('op', 'update', 'code', new_row.code, 'changes', v_chg), new_row.code);
    end if;
  end if;
  return new_row.id;
end;
$$;

-- تحديث المتابعة الدورية للإجراء (خلايا الإدخال في الملف): البدء والمدة والحالة والإنجاز والملاحظات.
-- متاح لرئيس القسم المسؤول عن الإجراء أيضاً.
create or replace function public.update_swot_action(p_id uuid, p_start date, p_duration integer, p_status text,
                                                     p_progress numeric, p_notes text)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  old_row public.swot_actions;
  new_row public.swot_actions;
  v_prog  numeric := p_progress;
  v_chg   jsonb;
begin
  select * into old_row from public.swot_actions where id = p_id for update;
  if not found then
    raise exception 'الإجراء غير موجود' using errcode = 'P0002';
  end if;
  if not public.can_update_swot_action(old_row.department) then
    raise exception 'تحديث هذا الإجراء لمدير المكتب وفريقه ورئيس القسم المسؤول' using errcode = '42501';
  end if;
  if p_status not in ('not_started', 'in_progress', 'completed', 'stalled', 'on_hold') then
    raise exception 'حالة تنفيذ غير معروفة' using errcode = '22023';
  end if;
  if p_duration is not null and (p_duration < 1 or p_duration > 60) then
    raise exception 'المدة من 1 إلى 60 شهراً' using errcode = '22023';
  end if;
  if v_prog is not null and (v_prog < 0 or v_prog > 1) then
    raise exception 'نسبة الإنجاز من 0 إلى 100%%' using errcode = '22023';
  end if;
  if length(coalesce(p_notes, '')) > 1000 then
    raise exception 'الملاحظات أطول من 1000 حرف' using errcode = '22023';
  end if;
  if p_status = 'completed' then v_prog := 1; end if;
  update public.swot_actions set
    start_date = p_start, duration_months = p_duration, status = p_status, progress = v_prog,
    notes = btrim(coalesce(p_notes, '')), updated_at = now(), updated_by = auth.uid()
  where id = p_id
  returning * into new_row;
  v_chg := public.jsonb_changes(to_jsonb(old_row), to_jsonb(new_row), array['updated_at', 'updated_by']);
  if v_chg <> '{}'::jsonb then
    perform public.write_audit('swot.progress', null, null,
      jsonb_build_object('code', new_row.code, 'changes', v_chg), new_row.code);
  end if;
end;
$$;

create or replace function public.delete_swot_action(p_id uuid)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  r public.swot_actions;
begin
  if not public.is_director() then
    raise exception 'الحذف من صلاحية مدير المكتب وحده' using errcode = '42501';
  end if;
  delete from public.swot_actions where id = p_id returning * into r;
  if not found then
    raise exception 'الإجراء غير موجود' using errcode = 'P0002';
  end if;
  perform public.write_audit('swot.delete', null, null, jsonb_build_object('item', 'action', 'code', r.code, 'text', r.action), r.code);
end;
$$;

-- ---------------------------------------------------------------------
-- 3. الإعدادات: معايير المخاطر وقوائمها، وبيانات وثيقة SWOT
-- ---------------------------------------------------------------------
create or replace function public.valid_text_list(p jsonb, p_max_items integer, p_max_len integer)
returns boolean
language sql immutable set search_path = public
as $$
  select p is null or jsonb_typeof(p) = 'null'
      or (jsonb_typeof(p) = 'array' and jsonb_array_length(p) <= p_max_items
          and coalesce((select bool_and(jsonb_typeof(x) = 'string' and length(btrim(x #>> '{}')) between 1 and p_max_len)
                          from jsonb_array_elements(p) x), true))
$$;

create or replace function public.set_setting(p_key text, p_value jsonb)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  v_old jsonb;
  t     text := jsonb_typeof(p_value);
  ok    boolean;
begin
  if not public.is_director() then
    raise exception 'الإعدادات من صلاحية مدير المكتب وحده' using errcode = '42501';
  end if;
  ok := case
    when p_key in ('brand.app_title', 'brand.org_name', 'brand.org_parent') then
      t = 'string' and length(btrim(p_value #>> '{}')) between 2 and 120
    when p_key = 'brand.primary_color' then
      t = 'string' and (p_value #>> '{}') ~ '^#[0-9A-Fa-f]{6}$'
    when p_key = 'finance.currency' then
      t = 'string' and length(btrim(p_value #>> '{}')) between 1 and 12
    when p_key in ('finance.guarantee_initial_rate', 'finance.guarantee_final_rate', 'finance.retention_rate', 'finance.tax_rate') then
      t = 'number' and (p_value #>> '{}')::numeric between 0 and 0.5
    when p_key = 'finance.advance_recovery_rate' then
      t = 'number' and (p_value #>> '{}')::numeric between 0 and 1
    when p_key = 'finance.deduction_types' then
      t = 'array' and jsonb_array_length(p_value) <= 12
      and coalesce((select bool_and(jsonb_typeof(x) = 'object'
                                    and jsonb_typeof(x -> 'key') = 'string' and (x ->> 'key') ~ '^[a-z][a-z0-9_]{1,29}$'
                                    and jsonb_typeof(x -> 'label') = 'string' and length(btrim(x ->> 'label')) between 2 and 40
                                    and (x -> 'rate' is null or jsonb_typeof(x -> 'rate') = 'null'
                                         or (jsonb_typeof(x -> 'rate') = 'number' and (x ->> 'rate')::numeric between 0 and 0.5)))
                      from jsonb_array_elements(p_value) x), true)
      and (select count(distinct x ->> 'key') = count(*) from jsonb_array_elements(p_value) x)
    when p_key = 'risk.config' then
      t = 'object' and length(p_value::text) <= 8000
      and jsonb_typeof(p_value -> 'levels') = 'array'
      and jsonb_array_length(p_value -> 'levels') between 3 and 7
      and coalesce((select bool_and(jsonb_typeof(x -> 'name') = 'string' and length(btrim(x ->> 'name')) between 2 and 30
                                    and jsonb_typeof(x -> 'min') = 'number' and (x ->> 'min')::numeric between 1 and 25
                                    and coalesce(jsonb_typeof(x -> 'action'), 'string') = 'string'
                                    and length(coalesce(x ->> 'action', '')) <= 60)
                      from jsonb_array_elements(p_value -> 'levels') x), false)
      and ((p_value -> 'levels' -> 0 ->> 'min')::numeric = 1)
      and (select bool_and(a < b) from (
             select (x ->> 'min')::numeric a, lead((x ->> 'min')::numeric) over (order by i) b
               from jsonb_array_elements(p_value -> 'levels') with ordinality e(x, i)) s where b is not null)
      and (p_value -> 'alert_days' is null or (jsonb_typeof(p_value -> 'alert_days') = 'number'
                                               and (p_value ->> 'alert_days')::numeric between 0 and 90))
      and public.valid_text_list(p_value -> 'phases', 40, 40)
      and public.valid_text_list(p_value -> 'categories', 40, 40)
      and public.valid_text_list(p_value -> 'projects', 60, 60)
      and public.valid_text_list(p_value -> 'owners', 40, 60)
    when p_key = 'swot.meta' then
      t = 'object' and length(p_value::text) <= 3000
      and coalesce((select bool_and(jsonb_typeof(v) in ('string', 'number', 'null') and length(v #>> '{}') <= 200)
                      from jsonb_each(p_value) e(k, v)), true)
      and (p_value -> 'review_cycle_months' is null or jsonb_typeof(p_value -> 'review_cycle_months') = 'null'
           or (jsonb_typeof(p_value -> 'review_cycle_months') = 'number'
               and (p_value ->> 'review_cycle_months')::numeric between 1 and 24))
      and (nullif(p_value ->> 'issue_date', '') is null or (p_value ->> 'issue_date') ~ '^\d{4}-\d{2}-\d{2}$')
    when p_key = 'security.idle_minutes' then
      t = 'number' and (p_value #>> '{}')::numeric between 0 and 480
    when p_key in ('security.require_mfa_director', 'security.require_mfa_all', 'security.freeze', 'security.signups_open',
                   'ai.enabled') then
      t = 'boolean'
    when p_key = 'ui.announcement' then
      t = 'object' and jsonb_typeof(p_value -> 'text') = 'string' and length(p_value ->> 'text') <= 500
      and coalesce(p_value ->> 'level', 'info') in ('info', 'warning', 'critical')
    when p_key = 'ui.status_labels' then
      t = 'object' and (select bool_and(jsonb_typeof(p_value -> k) = 'string' and length(btrim(p_value ->> k)) between 2 and 30)
                          from unnest(array['done', 'wip', 'todo', 'na']) k)
    when p_key = 'ui.features' then
      t = 'object' and (select bool_and(jsonb_typeof(v) = 'boolean') from jsonb_each(p_value) e(k, v))
    when p_key = 'ui.motion' then
      t = 'string' and (p_value #>> '{}') in ('full', 'reduced', 'off')
    when p_key = 'ui.nav' then
      t = 'object'
      and coalesce(jsonb_typeof(p_value -> 'hidden'), 'array') = 'array'
      and coalesce(jsonb_typeof(p_value -> 'order'), 'array') = 'array'
      and coalesce(jsonb_typeof(p_value -> 'labels'), 'object') = 'object'
      and coalesce((select bool_and(jsonb_typeof(v) = 'string' and length(v #>> '{}') <= 40)
                      from jsonb_each(coalesce(p_value -> 'labels', '{}')) e(k, v)), true)
      and length(p_value::text) <= 4000
    when p_key = 'ui.dashboard' then
      t = 'object' and jsonb_typeof(p_value -> 'sections') = 'array' and length(p_value::text) <= 4000
      and coalesce((select bool_and(jsonb_typeof(x -> 'key') = 'string' and jsonb_typeof(x -> 'on') = 'boolean')
                      from jsonb_array_elements(p_value -> 'sections') x), true)
    when p_key = 'ui.labels' then
      t = 'object' and length(p_value::text) <= 8000
      and coalesce((select bool_and(jsonb_typeof(v) = 'string' and length(v #>> '{}') between 1 and 60)
                      from jsonb_each(p_value) e(k, v)), true)
    when p_key = 'ui.appearance' then
      t = 'object' and length(p_value::text) <= 6000
      and coalesce(jsonb_typeof(p_value -> 'charts'), 'object') = 'object'
    when p_key = 'ai.model' then
      t = 'string' and (p_value #>> '{}') ~ '^[a-z0-9][a-z0-9.\-]{2,60}$'
    when p_key = 'ai.instructions' then
      t = 'string' and length(p_value #>> '{}') <= 4000
    else false
  end;
  if not coalesce(ok, false) then
    raise exception 'قيمة غير صالحة للإعداد %', p_key using errcode = '22023';
  end if;
  if p_key in ('security.require_mfa_director', 'security.require_mfa_all') and p_value = 'true'::jsonb
     and not public.mfa_enrolled(auth.uid()) then
    raise exception 'فعّل التحقق بخطوتين لحسابك أولاً' using errcode = 'P0001';
  end if;

  select value into v_old from public.app_settings where key = p_key;
  if v_old is not distinct from p_value then
    return;
  end if;
  insert into public.app_settings (key, value, updated_at, updated_by)
  values (p_key, p_value, now(), auth.uid())
  on conflict (key) do update set value = excluded.value, updated_at = excluded.updated_at, updated_by = excluded.updated_by;

  if p_key in ('finance.guarantee_initial_rate', 'finance.guarantee_final_rate') then
    perform set_config('app.recalc', 'on', true);
    perform set_config('app.trusted', 'on', true);
    update public.projects set executed_value = executed_value where executed_value is not null;
    perform set_config('app.trusted', 'off', true);
    perform set_config('app.recalc', 'off', true);
  end if;

  perform public.write_audit(case when p_key like 'security.%' then 'security.setting' else 'setting.update' end,
    null, null, jsonb_build_object('key', p_key, 'from', v_old, 'to', p_value), p_key);
end;
$$;

insert into public.app_settings (key, value) values
  ('risk.config', '{"levels": [{"name": "منخفض جداً", "min": 1, "action": "مراقبة"}, {"name": "منخفض", "min": 5, "action": "متابعة"}, {"name": "متوسط", "min": 9, "action": "خطة معالجة"}, {"name": "مرتفع", "min": 13, "action": "تصعيد إلى PMO"}, {"name": "مرتفع جداً", "min": 20, "action": "تصعيد عاجل"}], "alert_days": 7, "phases": ["التخطيط", "التصميم", "التعاقد", "التنفيذ", "الاستلام", "المتابعة"], "categories": ["فني", "تعاقدي", "موقعي", "مالي", "سلامة", "توريد", "جودة", "تنسيق", "زمني", "بيئي", "قانوني", "حوكمة"], "projects": ["الطرق والجسور", "المباني العامة", "المرافق", "المدارس", "الجسور", "الإسكان", "الطرق", "المباني", "الأحياء", "متعدد المشاريع"], "owners": ["مدير المشروع", "PMO", "الاستشاري", "المقاول", "العقود", "المالية", "المشتريات", "السلامة", "الجودة", "القانونية"]}'::jsonb),
  ('swot.meta', '{"title": "تحليل SWOT الاستراتيجي وخطة التنفيذ والمتابعة", "subtitle": "مشروع إعادة إعمار منطقة الصابري ووسط البلاد – بنغازي", "version": "2.0", "issue_date": "2026-11-08", "status": "مسودة للمراجعة والاعتماد", "review_cycle_months": 6, "prepared_by": "فريق مكتب المدير", "reviewed_by": "رؤساء الأقسام الأربعة", "approved_by": "م. فيصل خليفة الشبلي — مدير المكتب الهندسي المكلف"}'::jsonb)
on conflict (key) do nothing;

-- ---------------------------------------------------------------------
-- 4. ملخص مساعد Claude: يضاف إليه سجل المخاطر وتحليل SWOT
-- ---------------------------------------------------------------------
do $$
begin
  if not exists (select 1 from pg_proc where proname = 'ai_context_core' and pronamespace = 'public'::regnamespace) then
    alter function public.ai_context() rename to ai_context_core;
  end if;
end $$;

create or replace function public.ai_context()
returns jsonb
language plpgsql stable security definer set search_path = public
as $$
declare
  base jsonb := public.ai_context_core();
begin
  return base || jsonb_build_object(
    'risk_config', public.setting('risk.config'),
    'risks', coalesce((
      select jsonb_agg(jsonb_build_object(
               'code', r.code, 'project', r.project_group, 'contract', public.project_label(r.project_id),
               'phase', r.phase, 'category', r.category, 'description', r.description, 'cause', r.cause, 'effect', r.effect,
               'score', r.score, 'residual_score', r.residual_score, 'mitigation', r.mitigation, 'response', r.response,
               'owner', r.owner, 'status', r.status, 'next_review', r.next_review, 'target_date', r.target_date,
               'early_warning', r.early_warning) order by r.score desc, r.code)
        from public.risks r), '[]'::jsonb),
    'swot', jsonb_build_object(
      'meta', public.setting('swot.meta'),
      'factors', coalesce((
        select jsonb_agg(jsonb_build_object('code', f.code, 'factor', f.factor, 'department', f.department,
                                            'importance', f.importance, 'urgency', f.urgency, 'priority', f.priority,
                                            'rating', f.rating) order by f.sort, f.code)
          from public.swot_factors f), '[]'::jsonb),
      'strategies', coalesce((
        select jsonb_agg(jsonb_build_object('code', s.code, 'strategy', s.strategy, 'internal', s.internal_factors,
                                            'external', s.external_factors, 'priority', s.priority, 'lead', s.lead_department)
                         order by s.sort, s.code)
          from public.swot_strategies s), '[]'::jsonb),
      'actions', coalesce((
        select jsonb_agg(jsonb_build_object('code', a.code, 'strategy', a.strategy_code, 'action', a.action,
                                            'department', a.department, 'owner', a.owner, 'kpi', a.kpi, 'priority', a.priority,
                                            'start', a.start_date, 'months', a.duration_months, 'status', a.status,
                                            'progress', a.progress, 'notes', a.notes) order by a.sort, a.code)
          from public.swot_actions a), '[]'::jsonb)));
end;
$$;

-- ---------------------------------------------------------------------
-- 5. الصلاحيات والتحديث اللحظي
-- ---------------------------------------------------------------------
revoke execute on function
  public.jsonb_changes(jsonb, jsonb, text[]), public.jtext(jsonb, text, integer, text),
  public.jscore(jsonb, text, integer, text, boolean), public.jdate(jsonb, text, text),
  public.jcodes(jsonb, text, text, text), public.valid_text_list(jsonb, integer, integer), public.ai_context_core()
from public, anon, authenticated;

revoke execute on function
  public.can_edit_risks(), public.can_edit_swot(), public.can_update_swot_action(text),
  public.save_risk(uuid, jsonb), public.delete_risk(uuid),
  public.save_swot_factor(uuid, jsonb), public.delete_swot_factor(uuid),
  public.save_swot_strategy(uuid, jsonb), public.delete_swot_strategy(uuid),
  public.save_swot_action(uuid, jsonb), public.delete_swot_action(uuid),
  public.update_swot_action(uuid, date, integer, text, numeric, text),
  public.set_setting(text, jsonb), public.ai_context()
from public, anon;
grant execute on function
  public.can_edit_risks(), public.can_edit_swot(), public.can_update_swot_action(text),
  public.save_risk(uuid, jsonb), public.delete_risk(uuid),
  public.save_swot_factor(uuid, jsonb), public.delete_swot_factor(uuid),
  public.save_swot_strategy(uuid, jsonb), public.delete_swot_strategy(uuid),
  public.save_swot_action(uuid, jsonb), public.delete_swot_action(uuid),
  public.update_swot_action(uuid, date, integer, text, numeric, text),
  public.set_setting(text, jsonb), public.ai_context()
to authenticated;

do $$
declare
  t text;
begin
  foreach t in array array['risks', 'swot_factors', 'swot_strategies', 'swot_actions'] loop
    if not exists (select 1 from pg_publication_tables
                   where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = t) then
      execute format('alter publication supabase_realtime add table public.%I', t);
    end if;
  end loop;
end $$;

-- ---------------------------------------------------------------------
-- 6. البيانات الأولية من الملفين (تُدرج مرة واحدة فقط، حين تكون الجداول فارغة)
-- ---------------------------------------------------------------------
insert into public.risks (code, project_group, phase, category, description, cause, effect, probability, impact, mitigation,
                          response, owner, status, residual_probability, residual_impact, next_review, registered_on, target_date,
                          closed_on, early_warning, notes)
select v.c1, v.c2, v.c3, v.c4, v.c5, v.c6, v.c7, v.c8, v.c9, v.c10, v.c11, v.c12, v.c13, v.c14, v.c15,
       v.c16::date, v.c17::date, v.c18::date, v.c19::date, v.c20, v.c21
from (values
  ('R01', 'الطرق والجسور', 'التصميم', 'فني', 'قصور الدراسات الجيوتقنية', 'نقص الجسات', 'إعادة التصميم', 4, 5, 'استكمال الجسات واعتماد التصميم', '', 'الاستشاري', 'open', 2, 2, null, current_date::text, null, null, '', ''),
  ('R02', 'المباني العامة', 'التعاقد', 'تعاقدي', 'تأخر الترسية', 'إجراءات اعتماد مطولة', 'تأخر البدء', 4, 4, 'خطة مشتريات ومتابعة الاعتمادات', '', 'العقود', 'open', 2, 3, null, current_date::text, null, null, '', ''),
  ('R03', 'المرافق', 'التنفيذ', 'موقعي', 'مرافق مدفونة غير موثقة', 'خرائط قديمة', 'توقف الأعمال', 4, 5, 'كشف تجريبي وتنسيق مع الجهات', '', 'مدير المشروع', 'open', 2, 4, null, current_date::text, null, null, '', ''),
  ('R04', 'المدارس', 'التنفيذ', 'مالي', 'تأخر المستخلصات', 'تأخر الصرف', 'تعثر المقاول', 4, 4, 'متابعة السيولة والمستخلصات', '', 'المالية', 'in_progress', 2, 3, null, current_date::text, null, null, '', ''),
  ('R05', 'الجسور', 'التنفيذ', 'سلامة', 'حادث عمل جسيم', 'قصور السلامة', 'إصابات وتوقف', 3, 5, 'تفتيش وخطة سلامة وتصاريح', '', 'السلامة', 'open', 2, 4, null, current_date::text, null, null, '', ''),
  ('R06', 'الإسكان', 'التنفيذ', 'توريد', 'نقص مواد البناء', 'اضطراب التوريد', 'تأخير وتكلفة', 4, 4, 'توريد مبكر وبدائل', '', 'المشتريات', 'open', 3, 3, null, current_date::text, null, null, '', ''),
  ('R07', 'الطرق', 'التنفيذ', 'جودة', 'عدم مطابقة الرصف', 'قصور الاختبارات', 'إعادة العمل', 3, 4, 'اختبارات ونقاط فحص', '', 'الجودة', 'open', 2, 2, null, current_date::text, null, null, '', ''),
  ('R08', 'المرافق', 'التصميم', 'تنسيق', 'تعارض المخططات', 'غياب التنسيق', 'أوامر تغيير', 4, 4, 'مراجعة تنسيقية للتخصصات', '', 'PMO', 'open', 2, 2, null, current_date::text, null, null, '', ''),
  ('R09', 'المباني', 'التنفيذ', 'زمني', 'ضعف أداء المقاول', 'نقص الموارد', 'تجاوز المدة', 4, 4, 'خطة تعافٍ أسبوعية', '', 'مدير المشروع', 'in_progress', 2, 3, null, current_date::text, null, null, '', ''),
  ('R10', 'الطرق', 'التنفيذ', 'بيئي', 'السيول والأمطار', 'تصريف غير كافٍ', 'تلف وتأخير', 3, 4, 'حماية الموقع وخطة طوارئ', '', 'المقاول', 'open', 2, 3, null, current_date::text, null, null, '', ''),
  ('R11', 'الأحياء', 'التخطيط', 'قانوني', 'نزاعات ملكية', 'عدم حسم الحدود', 'تعطيل الموقع', 3, 5, 'تدقيق الملكيات والتنسيق', '', 'القانونية', 'open', 2, 3, null, current_date::text, null, null, '', ''),
  ('R12', 'متعدد المشاريع', 'المتابعة', 'حوكمة', 'تقارير إنجاز غير دقيقة', 'ضعف التوثيق', 'قرارات وصرف غير دقيق', 4, 5, 'التحقق الميداني وتوحيد التقارير', '', 'PMO', 'open', 2, 3, null, current_date::text, null, null, '', '')
) v(c1, c2, c3, c4, c5, c6, c7, c8, c9, c10, c11, c12, c13, c14, c15, c16, c17, c18, c19, c20, c21)
where not exists (select 1 from public.risks);

insert into public.swot_factors (code, kind, factor, impact, department, importance, urgency, evidence, source, rating, sort)
select * from (values
  ('S01', 'S', 'خبرة في إدارة ومتابعة مشاريع الإعمار من التخطيط حتى الاستلام', 'استمرارية المتابعة عبر دورة حياة المشروع كاملة', 'جميع الأقسام', 5, 3, 'سجل المشاريع المنجزة والجارية', 'الملف الأصلي', 4, 1),
  ('S02', 'S', 'خبرة ميدانية في الإشراف والتنسيق بين المقاولين والاستشاريين والجهات ذات العلاقة', 'تسريع حل الإشكالات الميدانية وتقليل التعارضات', 'قسم الإشراف والتنسيق', 5, 4, 'محاضر الاجتماعات التنسيقية والتقارير الميدانية', 'الملف الأصلي', 4, 2),
  ('S03', 'S', 'وجود قسم للمطابقة والاستلام للتحقق من الأعمال والوثائق قبل الاعتماد', 'ضمان عدم اعتماد أعمال أو وثائق غير مطابقة', 'قسم المطابقة والاستلام', 5, 4, 'محاضر المطابقة والاستلام', 'الملف الأصلي', 4, 3),
  ('S04', 'S', 'توفر كوادر فنية متعددة التخصصات لدعم تقييم الأعمال والمشاريع', 'تغطية التخصصات الإنشائية والمعمارية والكهروميكانيكية داخليًا', 'قسم الشؤون الفنية', 4, 3, 'الهيكل التنظيمي وملفات الموظفين', 'الملف الأصلي', 3, 4),
  ('S05', 'S', 'القدرة على متابعة عدة مشاريع والتعامل مع الأولويات والضغوط الميدانية', 'مرونة توزيع الجهد بين المشاريع المتزامنة', 'جميع الأقسام', 4, 3, 'التقارير الدورية وعدد المشاريع المتابعة', 'الملف الأصلي', 3, 5),
  ('S06', 'S', 'المتابعة اليومية لنسب الإنجاز وجودة التنفيذ والملاحظات الفنية', 'رصد ميداني يومي يكشف الانحرافات مبكرًا (القوة في الرصد، وتقابلها W04 في سرعة التحديث)', 'قسم الإشراف والتنسيق', 4, 3, 'التقارير اليومية وسجلات الموقع', 'الملف الأصلي', 4, 6),
  ('S07', 'S', 'القدرة على حل التعارضات الفنية وتسريع التنسيق واتخاذ الإجراءات التصحيحية', 'تقليل التوقفات وإعادة العمل', 'قسم الشؤون الفنية', 4, 3, 'سجل الإجراءات التصحيحية', 'الملف الأصلي', 3, 7),
  ('S08', 'S', 'وجود قسم متخصص للترميم يدعم الحفاظ على المباني ذات القيمة التاريخية بوسط البلاد', 'الحفاظ على الهوية العمرانية لوسط البلاد', 'قسم الترميم', 4, 3, 'خطة عمل قسم الترميم والمشاريع المسندة إليه', 'مقترح – للتحقق في ورشة العمل', 3, 8),
  ('S09', 'S', 'انتظام إعداد التقارير الدورية (نصف الشهرية والشهرية) على مستوى الأقسام والمكتب', 'قاعدة بيانات تاريخية لقياس الأداء ودعم القرار', 'إدارة المكتب', 4, 3, 'أرشيف التقارير نصف الشهرية والشهرية', 'مقترح – للتحقق في ورشة العمل', 3, 9),
  ('S10', 'S', 'مبادرات تطوير قائمة: مراجعة حزمة النماذج التشغيلية وتطوير منظومة رقمية لمتابعة الدورة المستندية', 'أساس جاهز للتحول الرقمي وتوحيد الإجراءات', 'إدارة المكتب', 4, 4, 'مسودة حزمة النماذج ووثيقة متطلبات المنظومة', 'مقترح – للتحقق في ورشة العمل', 3, 10),
  ('W01', 'W', 'عدم توحيد نماذج متابعة المشاريع والتقارير الفنية ومحاضر الاجتماعات', 'تفاوت جودة البيانات وصعوبة المقارنة والتجميع', 'جميع الأقسام', 5, 5, 'عينة من النماذج المستخدمة في الأقسام', 'الملف الأصلي', 1, 11),
  ('W02', 'W', 'تداخل بعض الصلاحيات بين الإشراف والتنسيق والمطابقة والاستلام', 'ازدواجية في العمل أو فجوات في المسؤولية', 'إدارة المكتب', 4, 4, 'الهيكل التنظيمي والوصف الوظيفي', 'الملف الأصلي', 2, 12),
  ('W03', 'W', 'ضعف ربط بيانات الموقع بالمخططات والمواصفات وجداول الكميات', 'صعوبة التحقق من الكميات والمطابقة قبل الاستلام', 'قسم الشؤون الفنية', 4, 3, 'مقارنة سجلات الموقع بجداول الكميات', 'الملف الأصلي', 2, 13),
  ('W04', 'W', 'تأخر تحديث نسب الإنجاز والملاحظات وحالة الإغلاقات التصحيحية', 'قرارات مبنية على بيانات غير محدثة (الضعف في التحديث والتوثيق لا في الرصد الميداني)', 'قسم الإشراف والتنسيق', 4, 5, 'تواريخ آخر تحديث للتقارير والسجلات', 'الملف الأصلي', 1, 14),
  ('W05', 'W', 'محدودية إجراءات ضبط التغيير وإدارة المطالبات والمخاطر', 'مطالبات غير موثقة وتجاوزات في المدة والتكلفة', 'قسم الشؤون الفنية', 5, 4, 'سجل أوامر التغيير والمطالبات', 'الملف الأصلي', 1, 15),
  ('W06', 'W', 'تفاوت استخدام أدوات إدارة المشاريع والتوثيق الرقمي بين الأقسام', 'صعوبة تكامل البيانات بين الأقسام', 'جميع الأقسام', 3, 3, 'حصر البرامج والأدوات المستخدمة في كل قسم', 'الملف الأصلي', 2, 16),
  ('W07', 'W', 'عدم اكتمال مؤشرات أداء موحدة للوقت والجودة والمطابقة والاستلام', 'تعذر القياس الموضوعي للأداء والمقارنة بين المشاريع', 'إدارة المكتب', 4, 4, 'التقارير الدورية الحالية', 'الملف الأصلي', 2, 17),
  ('W08', 'W', 'محدودية البرامج التدريبية المتخصصة والمتقدمة (BIM، GIS، إدارة المشاريع)', 'فجوة مهارية تبطئ التحول الرقمي', 'قسم الشؤون الفنية', 3, 3, 'سجل التدريب للعامين الأخيرين', 'الملف الأصلي (خطة التنفيذ)', 2, 18),
  ('W09', 'W', 'عدم اكتمال توثيق الإجراءات التشغيلية في أدلة معتمدة لكل قسم', 'اعتماد الأداء على الأفراد بدل الإجراءات الموثقة', 'إدارة المكتب', 4, 3, 'الأدلة والإجراءات المعتمدة حاليًا', 'الملف الأصلي (خطة التنفيذ)', 2, 19),
  ('W10', 'W', 'عدم وضوح مسارات الاعتماد والتصعيد عند وجود تعارضات أو تغييرات', 'تأخر القرارات وتراكم الإشكالات دون حسم', 'إدارة المكتب', 4, 4, 'المراسلات وحالات التصعيد السابقة', 'الملف الأصلي (مصفوفة TOWS)', 2, 20),
  ('W11', 'W', 'قصور التوثيق المرحلي (الصور والأدلة ومحاضر الاستلام) وغياب أرشيف مركزي موحد', 'إضعاف موقف المكتب عند النزاعات أو المساءلة', 'قسم المطابقة والاستلام', 5, 4, 'عينة من ملفات الاستلام المرحلي والنهائي', 'الملف الأصلي (مصفوفة TOWS)', 1, 21),
  ('W12', 'W', 'ضعف توثيق الدروس المستفادة ونقل المعرفة بين المشاريع', 'تكرار الأخطاء نفسها في المشاريع اللاحقة', 'جميع الأقسام', 3, 2, 'تقارير إغلاق المشاريع', 'مقترح – للتحقق في ورشة العمل', 2, 22),
  ('O01', 'O', 'تطبيق نظام موحد لإدارة الوثائق والتقارير ومحاضر الاجتماعات والاستلام', 'توحيد البيانات وسرعة الوصول إليها', 'إدارة المكتب', 5, 4, 'عروض الأنظمة المتاحة ومتطلبات المكتب', 'الملف الأصلي', 2, 23),
  ('O02', 'O', 'استخدام لوحات متابعة رقمية لقياس الإنجاز والملاحظات والمخاطر والإغلاقات', 'رؤية لحظية لحالة المشاريع لدعم القرار', 'إدارة المكتب', 4, 3, 'نماذج لوحات المتابعة المقترحة', 'الملف الأصلي', 2, 24),
  ('O03', 'O', 'تعزيز التنسيق مع الجهات المالكة والاستشارية والمقاولين لتسريع قرارات المشاريع', 'تقليص زمن الاعتماد والرد', 'قسم الإشراف والتنسيق', 4, 3, 'محاضر الاجتماعات التنسيقية', 'الملف الأصلي', 3, 25),
  ('O04', 'O', 'التوجه الرسمي لتسريع وتيرة الإعمار وتوفر الدعم المؤسسي والتمويلي عبر صندوق التنمية وإعادة إعمار ليبيا', 'إمكانية توفير الموارد اللازمة لمبادرات التطوير', 'إدارة المكتب', 5, 4, 'القرارات والتعميمات الرسمية', 'مقترح – للتحقق في ورشة العمل', 3, 26),
  ('O05', 'O', 'الاهتمام المحلي والدولي بترميم المباني التاريخية بوسط البلاد وإمكانية الشراكات الفنية', 'نقل الخبرة ورفع جودة أعمال الترميم', 'قسم الترميم', 4, 3, 'مبادرات التعاون المعلنة مع جهات مختصة', 'مقترح – للتحقق في ورشة العمل', 2, 27),
  ('O06', 'O', 'توفر تقنيات حديثة (BIM، GIS، المسح بالطائرات المسيّرة والمسح ثلاثي الأبعاد) لتحسين التوثيق والمطابقة', 'دقة أعلى في الحصر والتوثيق والمطابقة', 'قسم الشؤون الفنية', 4, 3, 'عروض المزودين وتجارب جهات مماثلة', 'مقترح – للتحقق في ورشة العمل', 2, 28),
  ('O07', 'O', 'إمكانية الشراكة مع الجامعات والجهات الأكاديمية المحلية للتدريب والدعم الفني', 'تأهيل الكوادر بتكلفة مناسبة', 'إدارة المكتب', 3, 2, 'مراسلات واتفاقيات التعاون', 'مقترح – للتحقق في ورشة العمل', 1, 29),
  ('O08', 'O', 'الاستفادة من المعايير والممارسات الدولية (ISO 9001، ISO 21500، ISO 19650، ISO 31000)', 'إطار مرجعي جاهز لتطوير الإجراءات والجودة', 'إدارة المكتب', 3, 3, 'المعايير المرجعية المعتمدة', 'مقترح – للتحقق في ورشة العمل', 2, 30),
  ('O09', 'O', 'الربط مع مكاتب اللجنة (التخطيط والتقييم وضمان الجودة، العقود والتوريدات والمستخلصات) عبر منظومة رقمية مشتركة', 'دورة مستندية أسرع وأقل أخطاء', 'إدارة المكتب', 4, 4, 'متطلبات منظومة الدورة المستندية', 'مقترح – للتحقق في ورشة العمل', 3, 31),
  ('O10', 'O', 'دعم المجتمع المحلي وعودة السكان والأنشطة التجارية إلى المنطقة', 'تغذية راجعة مبكرة ودعم مجتمعي للمشاريع', 'قسم الإشراف والتنسيق', 3, 2, 'ملاحظات السكان وأصحاب المحال', 'مقترح – للتحقق في ورشة العمل', 2, 32),
  ('T01', 'T', 'تعدد التوجيهات أو تدخل جهات خارجية بما يؤثر على نطاق العمل والصلاحيات', 'تغييرات في النطاق وإرباك الأولويات', 'إدارة المكتب', 5, 4, 'المراسلات والتوجيهات الواردة', 'الملف الأصلي', 2, 33),
  ('T02', 'T', 'ضعف جودة التنفيذ أو الأعمال غير المطابقة وتأخر معالجة الملاحظات', 'إعادة العمل وتأخر الاستلام', 'قسم المطابقة والاستلام', 5, 5, 'سجل الملاحظات وحالات عدم المطابقة', 'الملف الأصلي', 3, 34),
  ('T03', 'T', 'بطء اعتماد القرارات أو الردود من الجهات ذات العلاقة بما يؤخر التنفيذ والإغلاقات', 'تأخر التنفيذ وتمديد المدد', 'قسم الإشراف والتنسيق', 4, 4, 'سجل المراسلات وأزمنة الرد', 'الملف الأصلي (مصفوفة TOWS)', 2, 35),
  ('T04', 'T', 'الضغط الزمني لتسريع الإنجاز على حساب الجودة والتوثيق', 'ارتفاع مخاطر عدم المطابقة وضعف التوثيق', 'جميع الأقسام', 4, 5, 'الجداول الزمنية والتوجيهات', 'مقترح – للتحقق في ورشة العمل', 2, 36),
  ('T05', 'T', 'تقلب أسعار مواد البناء وسعر الصرف وصعوبات التوريد', 'مطالبات مالية وتأخر التوريد', 'قسم الشؤون الفنية', 4, 3, 'بيانات الأسعار ومطالبات المقاولين', 'مقترح – للتحقق في ورشة العمل', 2, 37),
  ('T06', 'T', 'محدودية قدرات بعض المقاولين ونقص العمالة الماهرة، خاصة في أعمال الترميم التراثي', 'تدني الجودة وبطء الإنجاز', 'قسم الترميم', 4, 3, 'تقييمات أداء المقاولين', 'مقترح – للتحقق في ورشة العمل', 2, 38),
  ('T07', 'T', 'مخاطر السلامة في المواقع المتضررة (احتمال وجود مخلفات حرب، ومبانٍ متضررة إنشائيًا)', 'حوادث وتوقف الأعمال ومسؤوليات قانونية', 'قسم الإشراف والتنسيق', 5, 4, 'تقارير المسح الأمني والإنشائي للمواقع', 'مقترح – للتحقق في ورشة العمل', 3, 39),
  ('T08', 'T', 'تأخر جاهزية وتسليم المواقع لأسباب تتعلق بالملكية أو الإخلاء', 'تأخر بدء الأعمال وتمديد المدد', 'قسم الإشراف والتنسيق', 4, 3, 'محاضر تسليم المواقع', 'مقترح – للتحقق في ورشة العمل', 2, 40),
  ('T09', 'T', 'تعارض أعمال شبكات المرافق العامة وتعدد الجهات المسؤولة عنها', 'إعادة الحفر والتوقفات والتكاليف الإضافية', 'قسم الشؤون الفنية', 4, 3, 'مخططات المرافق ومحاضر التنسيق', 'مقترح – للتحقق في ورشة العمل', 2, 41),
  ('T10', 'T', 'الضغط الإعلامي والمجتمعي بشأن سرعة الإنجاز والحفاظ على الطابع التراثي', 'مخاطر على السمعة وتغيير مفاجئ في الأولويات', 'إدارة المكتب', 3, 3, 'الرصد الإعلامي والشكاوى', 'مقترح – للتحقق في ورشة العمل', 2, 42),
  ('T11', 'T', 'تأثير البيئة الساحلية (الرطوبة والأملاح) على متانة المواد وجودة التنفيذ', 'تدهور مبكر للمنشآت وارتفاع تكاليف الصيانة', 'قسم الشؤون الفنية', 3, 3, 'نتائج الفحوص المخبرية والمعاينات', 'مقترح – للتحقق في ورشة العمل', 2, 43)
) v
where not exists (select 1 from public.swot_factors);

insert into public.swot_strategies (code, kind, strategy, internal_factors, external_factors, priority, lead_department, source, sort)
select * from (values
  ('SO1', 'SO', 'استثمار خبرة المكتب في إنشاء نظام موحد للتقارير والمتابعة والاستلام', array['S01', 'S03', 'S09']::text[], array['O01']::text[], 'high', 'قسم الإشراف والتنسيق', 'الملف الأصلي', 1),
  ('SO2', 'SO', 'توظيف المتابعة الميدانية اليومية لإطلاق لوحة مؤشرات أسبوعية للمشاريع', array['S06', 'S05']::text[], array['O02', 'O04']::text[], 'high', 'قسم الإشراف والتنسيق', 'الملف الأصلي', 2),
  ('SO3', 'SO', 'استخدام الخبرة الفنية لتوحيد قوائم الفحص وتسريع معالجة الملاحظات', array['S04', 'S07']::text[], array['O01', 'O08']::text[], 'medium', 'قسم المطابقة والاستلام', 'الملف الأصلي', 3),
  ('SO4', 'SO', 'توظيف قسم الترميم لبناء شراكات فنية مع جهات مختصة وتوحيد منهجية ترميم المباني التاريخية', array['S08']::text[], array['O05']::text[], 'medium', 'قسم الترميم', 'مقترح – للتحقق في ورشة العمل', 4),
  ('SO5', 'SO', 'استكمال منظومة متابعة الدورة المستندية الرقمية وربطها بمكاتب اللجنة ذات العلاقة', array['S10']::text[], array['O02', 'O09']::text[], 'high', 'إدارة المكتب', 'مقترح – للتحقق في ورشة العمل', 5),
  ('SO6', 'SO', 'توظيف الخبرة الميدانية والتقارير الدورية في إطلاع المجتمع المحلي على مراحل الإنجاز وتلقي ملاحظاته', array['S02', 'S09']::text[], array['O10']::text[], 'low', 'إدارة المكتب', 'مقترح – للتحقق في ورشة العمل', 6),
  ('WO1', 'WO', 'اعتماد حزمة نماذج موحدة للتقارير ومحاضر المطابقة والاستلام ضمن نظام موحد لإدارة الوثائق', array['W01']::text[], array['O01']::text[], 'high', 'إدارة المكتب', 'الملف الأصلي (أُعيدت صياغته كاستراتيجية)', 7),
  ('WO2', 'WO', 'ربط بيانات الإشراف والتنسيق والمطابقة والاستلام بالمخططات وجداول الكميات في سجل رقمي موحد', array['W03', 'W06']::text[], array['O02']::text[], 'medium', 'قسم الشؤون الفنية', 'الملف الأصلي (أُعيدت صياغته كاستراتيجية)', 8),
  ('WO3', 'WO', 'تحديد أزمنة قياسية للرد والاعتماد بالتنسيق مع الجهات المالكة والاستشارية والمقاولين', array['W10', 'W04']::text[], array['O03', 'O04']::text[], 'high', 'قسم الإشراف والتنسيق', 'الملف الأصلي (أُعيدت صياغته كاستراتيجية)', 9),
  ('WO4', 'WO', 'برنامج تأهيل في BIM وGIS وإدارة المشاريع بالشراكة مع الجهات الأكاديمية', array['W08', 'W06']::text[], array['O06', 'O07']::text[], 'high', 'قسم الشؤون الفنية', 'الملف الأصلي (خطة التنفيذ)', 10),
  ('WO5', 'WO', 'إعداد أدلة إجراءات تشغيلية موحدة لكل قسم وفق الممارسات الدولية', array['W09', 'W07']::text[], array['O08']::text[], 'high', 'إدارة المكتب', 'الملف الأصلي (خطة التنفيذ)', 11),
  ('WO6', 'WO', 'تأسيس قاعدة معرفية للدروس المستفادة ضمن نظام إدارة الوثائق', array['W12']::text[], array['O01', 'O08']::text[], 'low', 'قسم الشؤون الفنية', 'مقترح – للتحقق في ورشة العمل', 12),
  ('ST1', 'ST', 'تفعيل مصفوفة صلاحيات ومسار تصعيد واضح بين المكتب والجهات ذات العلاقة', array['S02', 'S07']::text[], array['T01', 'T03']::text[], 'high', 'إدارة المكتب', 'الملف الأصلي', 13),
  ('ST2', 'ST', 'تعزيز قوائم الفحص والتوثيق المرحلي قبل الاستلام النهائي', array['S03', 'S06']::text[], array['T02']::text[], 'high', 'قسم المطابقة والاستلام', 'الملف الأصلي', 14),
  ('ST3', 'ST', 'توظيف الخبرة الميدانية في تقييم سلامة المواقع قبل تسليمها للمقاولين بالتنسيق مع الجهات المختصة', array['S02', 'S04']::text[], array['T07']::text[], 'high', 'قسم الإشراف والتنسيق', 'مقترح – للتحقق في ورشة العمل', 15),
  ('ST4', 'ST', 'توظيف خبرة الترميم والكوادر الفنية في وضع اشتراطات لمواد ملائمة للبيئة الساحلية ومعايير لتأهيل مقاولي الترميم', array['S08', 'S04']::text[], array['T06', 'T11']::text[], 'medium', 'قسم الترميم', 'مقترح – للتحقق في ورشة العمل', 16),
  ('ST5', 'ST', 'التنسيق المبكر مع جهات المرافق العامة لضمان جاهزية المواقع ومنع التعارضات', array['S02', 'S07']::text[], array['T08', 'T09']::text[], 'medium', 'قسم الإشراف والتنسيق', 'مقترح – للتحقق في ورشة العمل', 17),
  ('WT1', 'WT', 'إعداد إجراء معتمد لضبط التغيير وإدارة المطالبات بمسار اعتماد وتصعيد واضح', array['W05', 'W02', 'W10']::text[], array['T01', 'T03']::text[], 'high', 'قسم الشؤون الفنية', 'الملف الأصلي (أُعيدت صياغته كاستراتيجية)', 18),
  ('WT2', 'WT', 'إنشاء أرشيف توثيقي مركزي للأدلة والصور ومحاضر الاستلام لحماية موقف المكتب', array['W11']::text[], array['T02', 'T10']::text[], 'medium', 'قسم الشؤون الفنية', 'الملف الأصلي (أُعيدت صياغته كاستراتيجية)', 19),
  ('WT3', 'WT', 'تفعيل سجل مخاطر حي للمشاريع يُحدَّث شهريًا مع خطط استجابة', array['W05']::text[], array['T04', 'T05', 'T07']::text[], 'high', 'قسم الإشراف والتنسيق', 'مقترح – للتحقق في ورشة العمل', 20),
  ('WT4', 'WT', 'اعتماد مؤشرات أداء موحدة للوقت والجودة تحمي الجودة تحت الضغط الزمني', array['W07', 'W04']::text[], array['T04']::text[], 'high', 'إدارة المكتب', 'مقترح – للتحقق في ورشة العمل', 21)
) v
where not exists (select 1 from public.swot_strategies);

insert into public.swot_actions (code, strategy_code, factors, action, output, department, owner, kpi, priority, start_date,
                                 duration_months, verification, review_cycle, status, progress, notes, source, sort)
select v.c1, v.c2, v.c3, v.c4, v.c5, v.c6, v.c7, v.c8, v.c9, v.c10::date, v.c11::smallint, v.c12, v.c13, v.c14, v.c15::numeric, v.c16, v.c17, v.c18
from (values
  ('A01', 'WO5', array['W09', 'W07']::text[], 'إعداد واعتماد دليل إجراءات موحد لكل قسم وتنفيذ جلسة تعريفية', 'دليل إجراءات تشغيلية معتمد للأقسام الأربعة', 'إدارة المكتب', 'مدير المكتب بالتنسيق مع رؤساء الأقسام', 'اعتماد الدليل وتطبيقه في 100% من الأقسام', 'high', '2026-12-01', 3, 'الدليل المعتمد ومحاضر التدريب', 'كل 6 أشهر', 'not_started', 0.0, '', 'الملف الأصلي', 1),
  ('A02', 'WO4', array['W08', 'W06']::text[], 'تنفيذ دورات متخصصة في GIS وBIM وإدارة المشاريع بالتنسيق مع جهات أكاديمية', 'خطة تدريب معتمدة وكوادر مؤهلة', 'قسم الشؤون الفنية', 'مدير المكتب ورئيس قسم الشؤون الفنية', 'تدريب 80% من الموظفين المستهدفين', 'high', '2027-01-01', 6, 'سجلات الحضور وشهادات التدريب', 'كل 6 أشهر', 'not_started', 0.0, '', 'الملف الأصلي', 2),
  ('A03', 'SO1', array['W01', 'W04', 'S09']::text[], 'اعتماد نموذج موحد للتقارير وتحديد موعد أسبوعي للتسليم', 'نموذج تقرير موحد وجدول تسليم أسبوعي', 'قسم الإشراف والتنسيق', 'رئيس قسم الإشراف والتنسيق', 'استلام 90% من التقارير في موعدها', 'high', '2026-12-01', 2, 'سجل استلام التقارير ومحاضر الاجتماعات', 'شهريًا', 'not_started', 0.0, '', 'الملف الأصلي', 3),
  ('A04', 'WO2', array['W03', 'W06']::text[], 'إنشاء سجل موحد لربط الملاحظات والمخططات والمواصفات ومحاضر المطابقة والاستلام', 'سجل رقمي موحد للملاحظات مرتبط بالمخططات وجداول الكميات', 'قسم الشؤون الفنية', 'مدير المكتب ورئيس قسم الشؤون الفنية', 'إغلاق 90% من الملاحظات الموثقة قبل الاستلام المرحلي', 'medium', '2027-01-01', 4, 'سجل الملاحظات وقوائم الفحص ومحاضر الاستلام', 'شهريًا', 'not_started', 0.0, '', 'الملف الأصلي', 4),
  ('A05', 'ST2', array['T02', 'W11']::text[], 'تفعيل قوائم فحص ونقاط توقف وإجراءات تصحيحية قبل الاستلام النهائي', 'نقاط توقف (Hold Points) معتمدة لكل مرحلة استلام', 'قسم المطابقة والاستلام', 'رئيسا قسمي الإشراف والتنسيق والمطابقة والاستلام', 'عدم اعتماد أي أعمال غير مطابقة وإغلاق 90% من الملاحظات ضمن المدة المحددة', 'high', '2026-12-01', 3, 'قوائم الفحص ومحاضر المطابقة والاستلام', 'مع كل مرحلة استلام', 'not_started', 0.0, '', 'الملف الأصلي', 5),
  ('A06', 'WO1', array['W01']::text[], 'استكمال مراجعة حزمة النماذج التشغيلية واعتمادها رسميًا بترميز وإصدار موحدين وتعميمها', 'حزمة نماذج معتمدة ومرمّزة', 'إدارة المكتب', 'مدير المكتب', 'اعتماد وتعميم 100% من النماذج المراجعة', 'high', '2026-10-01', 3, 'قرار الاعتماد وسجل النماذج المعتمدة', 'شهريًا', 'in_progress', null, 'مبادرة قائمة؛ تاريخ البدء تقريبي، وتُدخَل نسبة الإنجاز الفعلية من المسؤول', 'مضاف (مبادرة قائمة)', 6),
  ('A07', 'SO2', array['W04', 'W07']::text[], 'إطلاق لوحة مؤشرات أسبوعية للمشاريع (الإنجاز، الملاحظات، المخاطر، الإغلاقات)', 'لوحة متابعة أسبوعية معتمدة', 'قسم الإشراف والتنسيق', 'رئيس قسم الإشراف والتنسيق', 'إصدار اللوحة أسبوعيًا لـ 100% من المشاريع النشطة', 'high', '2027-01-01', 2, 'نسخ اللوحة الأسبوعية المؤرشفة', 'أسبوعيًا', 'not_started', 0.0, '', 'الملف الأصلي (مصفوفة TOWS)', 7),
  ('A08', 'SO3', array['T02', 'W01']::text[], 'إعداد مكتبة قوائم فحص موحدة حسب نوع العمل (إنشائي، معماري، كهروميكانيكي، ترميم)', 'مكتبة قوائم فحص معتمدة', 'قسم المطابقة والاستلام', 'رئيس قسم المطابقة والاستلام', 'اعتماد قوائم فحص لـ 100% من بنود الأعمال الرئيسية', 'medium', '2026-12-01', 3, 'قوائم الفحص المعتمدة', 'ربع سنوي', 'not_started', 0.0, '', 'الملف الأصلي (مصفوفة TOWS)', 8),
  ('A09', 'SO4', array['S08', 'O05', 'T06']::text[], 'إعداد ملف فني للمباني ذات القيمة التاريخية ضمن النطاق واعتماد منهجية ترميم موحدة بالتعاون مع جهة مختصة', 'سجل حصر وتوثيق ومنهجية ترميم معتمدة', 'قسم الترميم', 'رئيس قسم الترميم', 'توثيق 100% من المباني المصنفة واعتماد المنهجية', 'medium', '2027-02-01', 4, 'سجل الحصر ومذكرة التعاون', 'ربع سنوي', 'not_started', 0.0, '', 'مضاف', 9),
  ('A10', 'SO5', array['W06', 'O09', 'S10']::text[], 'استكمال وتشغيل منظومة متابعة نماذج الدورة المستندية وربطها بمكتبي التخطيط والتقييم وضمان الجودة والعقود والتوريدات والمستخلصات', 'منظومة رقمية مشغّلة ومستخدمون مدربون', 'إدارة المكتب', 'مدير المكتب', 'تشغيل المنظومة لدى 100% من المستخدمين المستهدفين', 'high', '2026-10-01', 6, 'تقارير المنظومة وسجل المستخدمين', 'شهريًا', 'in_progress', null, 'مبادرة قائمة؛ تاريخ البدء تقريبي، وتُدخَل نسبة الإنجاز الفعلية من المسؤول', 'مضاف (مبادرة قائمة)', 10),
  ('A11', 'WO3', array['W10', 'T03']::text[], 'إعداد ميثاق تنسيق يحدد الأزمنة القياسية للرد على المراسلات وطلبات الاعتماد والفحص ومتابعتها في سجل', 'ميثاق تنسيق معتمد وسجل للطلبات', 'قسم الإشراف والتنسيق', 'رئيس قسم الإشراف والتنسيق', 'الرد على 90% من الطلبات ضمن الزمن القياسي', 'high', '2026-12-01', 2, 'سجل المراسلات وطلبات الاعتماد', 'شهريًا', 'not_started', 0.0, '', 'الملف الأصلي (مصفوفة TOWS)', 11),
  ('A12', 'WT4', array['W07', 'T04']::text[], 'اعتماد بطاقة مؤشرات أداء موحدة (الوقت، الجودة، المطابقة، الاستلام) مع تعريف وطريقة احتساب كل مؤشر', 'بطاقة مؤشرات أداء معتمدة', 'إدارة المكتب', 'مدير المكتب', 'قياس المؤشرات شهريًا في 100% من الأقسام', 'high', '2027-01-01', 3, 'التقرير الشهري لمكتب الشؤون الهندسية', 'شهريًا', 'not_started', 0.0, '', 'مضاف', 12),
  ('A13', 'WO6', array['W12']::text[], 'إنشاء سجل للدروس المستفادة يُحدَّث عند إغلاق كل مرحلة ويُراجَع في اجتماع ربع سنوي', 'سجل دروس مستفادة ضمن نظام الوثائق', 'قسم الشؤون الفنية', 'رئيس قسم الشؤون الفنية', 'توثيق الدروس المستفادة لـ 100% من المراحل المغلقة', 'low', '2027-04-01', 3, 'سجل الدروس المستفادة', 'ربع سنوي', 'not_started', 0.0, '', 'مضاف', 13),
  ('A14', 'ST1', array['W02', 'W10', 'T01']::text[], 'إعداد واعتماد مصفوفة الصلاحيات والمسؤوليات (RACI) ومسار التصعيد بين الأقسام والجهات ذات العلاقة', 'مصفوفة صلاحيات ومسار تصعيد معتمدان', 'إدارة المكتب', 'مدير المكتب', 'اعتماد المصفوفة وتعميمها ومعالجة 100% من حالات التصعيد عبر المسار المعتمد', 'high', '2026-12-01', 2, 'المصفوفة المعتمدة وسجل حالات التصعيد', 'كل 6 أشهر', 'not_started', 0.0, '', 'الملف الأصلي (مصفوفة TOWS)', 14),
  ('A15', 'ST3', array['T07']::text[], 'اعتماد إجراء تقييم سلامة الموقع قبل التسليم (مسح المخلفات بالتنسيق مع الجهات المختصة، تقييم إنشائي للمباني المتضررة، خطة طوارئ)', 'إجراء سلامة معتمد ونموذج تقييم موقع', 'قسم الإشراف والتنسيق', 'رئيس قسم الإشراف والتنسيق', 'تقييم 100% من المواقع قبل التسليم وعدم تسجيل حوادث جسيمة', 'high', '2026-12-01', 1, 'نماذج تقييم المواقع ومحاضر التسليم', 'مع كل تسليم موقع', 'not_started', 0.0, '', 'مضاف', 15),
  ('A16', 'ST4', array['T06', 'T11']::text[], 'إعداد اشتراطات فنية للمواد وأعمال الحماية في البيئة الساحلية ومعايير لتأهيل مقاولي الترميم', 'اشتراطات فنية ومعايير تأهيل معتمدة', 'قسم الترميم', 'رئيس قسم الترميم بالتنسيق مع قسم الشؤون الفنية', 'تضمين الاشتراطات في 100% من وثائق الطرح الجديدة', 'medium', '2027-02-01', 4, 'وثائق الطرح والمواصفات المعتمدة', 'كل 6 أشهر', 'not_started', 0.0, '', 'مضاف', 16),
  ('A17', 'ST5', array['T08', 'T09']::text[], 'تشكيل لجنة تنسيق دورية مع جهات المرافق العامة وإعداد مخطط مرافق موحد للنطاق', 'محاضر تنسيق شهرية ومخطط مرافق موحد', 'قسم الإشراف والتنسيق', 'رئيس قسم الإشراف والتنسيق', 'حل 90% من تعارضات المرافق خلال 30 يومًا من رصدها', 'medium', '2027-01-01', 2, 'محاضر لجنة التنسيق وسجل التعارضات', 'شهريًا', 'not_started', 0.0, '', 'مضاف', 17),
  ('A18', 'WT1', array['W05', 'W02', 'T01']::text[], 'إعداد إجراء ضبط التغيير وإدارة المطالبات (نموذج طلب تغيير، دراسة الأثر الزمني والمالي، صلاحيات الاعتماد، سجل التغييرات)', 'إجراء معتمد وسجل للتغييرات والمطالبات', 'قسم الشؤون الفنية', 'رئيس قسم الشؤون الفنية', 'توثيق واعتماد 100% من التغييرات قبل تنفيذها', 'high', '2027-01-01', 3, 'سجل أوامر التغيير والمطالبات', 'شهريًا', 'not_started', 0.0, '', 'الملف الأصلي (مصفوفة TOWS)', 18),
  ('A19', 'WT2', array['W11', 'T10']::text[], 'إنشاء أرشيف رقمي مركزي بهيكل ترميز موحد للمخططات المعتمدة ومخططات التنفيذ الفعلي والصور ومحاضر الاستلام', 'أرشيف مركزي مفهرس', 'قسم الشؤون الفنية', 'رئيس قسم الشؤون الفنية', 'أرشفة 100% من وثائق الاستلام خلال 7 أيام من صدورها', 'medium', '2027-02-01', 4, 'تقرير جرد الأرشيف', 'ربع سنوي', 'not_started', 0.0, '', 'الملف الأصلي (مصفوفة TOWS)', 19),
  ('A20', 'WT3', array['W05', 'T04', 'T05']::text[], 'إعداد سجل مخاطر موحد للمشاريع (الاحتمال × الأثر، مالك الخطر، خطة الاستجابة) ومراجعته شهريًا', 'سجل مخاطر حي ومحدث', 'قسم الإشراف والتنسيق', 'رئيس قسم الإشراف والتنسيق', 'تحديث السجل شهريًا لـ 100% من المشاريع النشطة', 'high', '2026-12-01', 2, 'سجل المخاطر ومحاضر المراجعة', 'شهريًا', 'not_started', 0.0, '', 'مضاف (من عناصر الحوكمة الأصلية)', 20),
  ('A21', 'SO6', array['O10', 'T10']::text[], 'إصدار نشرة إنجاز دورية مبسطة بالتنسيق مع إعلام اللجنة وإتاحة قناة لتلقي ملاحظات السكان وأصحاب المحال', 'نشرة دورية وقناة ملاحظات مفعّلة', 'إدارة المكتب', 'مدير المكتب بالتنسيق مع إعلام اللجنة', 'إصدار النشرة شهريًا والرد على 90% من الملاحظات خلال 14 يومًا', 'low', '2027-03-01', 3, 'أعداد النشرة وسجل الملاحظات', 'شهريًا', 'not_started', 0.0, '', 'مضاف', 21)
) v(c1, c2, c3, c4, c5, c6, c7, c8, c9, c10, c11, c12, c13, c14, c15, c16, c17, c18)
where not exists (select 1 from public.swot_actions);

notify pgrst, 'reload schema';

select 'تم: سجل المخاطر وتحليل SWOT (العوامل والاستراتيجيات وخطة التنفيذ)' as result;
