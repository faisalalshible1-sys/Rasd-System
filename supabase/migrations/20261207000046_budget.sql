-- =====================================================================
-- الإصدار 2.0.0 (الترحيل 46): ميزانية المكتب والالتزامات
--
--  budget_lines: بنود ميزانية سنوية (سنة، باب، بند، مبلغ مخصص). يعرّفها المدير وحده.
--  budget_commitments: التزامات على بند (مبلغ ملتزم ومدفوع منه، وعقد مرتبط اختيارياً). يسجّلها المدير وموظفو مكتبه.
--  القاعدة: مجموع الالتزامات النشطة على البند لا يتجاوز المخصص، ولا يُخفَّض المخصص دون الملتزم، ولا يُحذف بند له التزامات.
--  القراءة لمن يرى كل شيء (full_view)، والكتابة بدوال تسجّل في سجل التدقيق، لا كتابة مباشرة.
--  يُشغَّل بعد 20261206000045_milestones_kpi.sql، وإعادة تشغيله آمنة. التراجع: supabase/rollbacks/20261207000046_budget_down.sql
-- =====================================================================
create table if not exists public.budget_lines (
  id         uuid primary key default gen_random_uuid(),
  fiscal_year integer not null check (fiscal_year between 2000 and 2100),
  category   text not null check (length(btrim(category)) between 1 and 60),
  name       text not null check (length(btrim(name)) between 1 and 120),
  allocated  numeric(18, 3) not null check (allocated >= 0),
  note       text not null default '' check (length(note) <= 300),
  created_at timestamptz not null default now(),
  created_by uuid references public.profiles (id) on delete set null,
  updated_at timestamptz not null default now(),
  updated_by uuid references public.profiles (id) on delete set null
);
create unique index if not exists budget_lines_name_uidx on public.budget_lines (fiscal_year, lower(btrim(name)));
create index if not exists budget_lines_created_by_idx on public.budget_lines (created_by);
create index if not exists budget_lines_updated_by_idx on public.budget_lines (updated_by);

create table if not exists public.budget_commitments (
  id           uuid primary key default gen_random_uuid(),
  line_id      uuid not null references public.budget_lines (id) on delete restrict,
  project_id   uuid references public.projects (id) on delete set null,
  description  text not null check (length(btrim(description)) between 1 and 200),
  amount       numeric(18, 3) not null check (amount > 0),
  paid         numeric(18, 3) not null default 0 check (paid >= 0),
  committed_on date not null,
  status       text not null default 'active' check (status in ('active', 'released')),
  note         text not null default '' check (length(note) <= 300),
  created_at   timestamptz not null default now(),
  created_by   uuid references public.profiles (id) on delete set null,
  updated_at   timestamptz not null default now(),
  updated_by   uuid references public.profiles (id) on delete set null,
  check (paid <= amount)
);
create index if not exists budget_commitments_line_idx on public.budget_commitments (line_id);
create index if not exists budget_commitments_project_idx on public.budget_commitments (project_id);
create index if not exists budget_commitments_created_by_idx on public.budget_commitments (created_by);
create index if not exists budget_commitments_updated_by_idx on public.budget_commitments (updated_by);

alter table public.budget_lines enable row level security;
alter table public.budget_commitments enable row level security;
drop policy if exists budget_lines_read on public.budget_lines;
create policy budget_lines_read on public.budget_lines for select to authenticated using ((select public.full_view()));
drop policy if exists budget_commitments_read on public.budget_commitments;
create policy budget_commitments_read on public.budget_commitments for select to authenticated using ((select public.full_view()));

revoke all on public.budget_lines, public.budget_commitments from anon;
revoke insert, update, delete, truncate on public.budget_lines, public.budget_commitments from authenticated;
grant select on public.budget_lines, public.budget_commitments to authenticated;
grant all on public.budget_lines, public.budget_commitments to service_role;

create or replace function public.budget_can_define()
returns boolean
language sql stable security definer set search_path = public
as $$ select coalesce(public.my_role()::text = 'director', false) and public.writes_allowed() $$;

create or replace function public.budget_can_commit()
returns boolean
language sql stable security definer set search_path = public
as $$ select coalesce(public.my_role()::text in ('director', 'office_staff'), false) and public.writes_allowed() $$;

-- الملتزم النشط على بند (باستثناء التزام بعينه)
create or replace function public.budget_committed(p_line uuid, p_except uuid default null)
returns numeric
language sql stable security definer set search_path = public
as $$
  select coalesce(sum(amount), 0) from public.budget_commitments
   where line_id = p_line and status = 'active' and id is distinct from p_except
$$;

create or replace function public.budget_line_save(
  p_id uuid, p_year integer, p_category text, p_name text, p_allocated numeric, p_note text default '')
returns uuid
language plpgsql security definer set search_path = public
as $$
declare
  v_id uuid := p_id;
  v_cat text := btrim(coalesce(p_category, ''));
  v_name text := btrim(coalesce(p_name, ''));
begin
  if not public.budget_can_define() then
    raise exception 'تعريف بنود الميزانية للمدير وحده' using errcode = '42501';
  end if;
  if p_year is null or p_year not between 2000 and 2100 then
    raise exception 'السنة المالية بين 2000 و2100' using errcode = '22023';
  end if;
  if length(v_cat) not between 1 and 60 or length(v_name) not between 1 and 120 then
    raise exception 'الباب حتى 60 حرفاً والبند حتى 120' using errcode = '22023';
  end if;
  if p_allocated is null or p_allocated < 0 then
    raise exception 'المخصص مبلغ غير سالب' using errcode = '22023';
  end if;
  if length(coalesce(p_note, '')) > 300 then
    raise exception 'الملاحظة أطول من 300 حرف' using errcode = '22023';
  end if;
  if exists (select 1 from public.budget_lines where fiscal_year = p_year and lower(btrim(name)) = lower(v_name) and id is distinct from p_id) then
    raise exception 'يوجد بند بهذا الاسم في السنة نفسها' using errcode = '23505';
  end if;
  if p_id is null then
    insert into public.budget_lines (fiscal_year, category, name, allocated, note, created_by, updated_by)
    values (p_year, v_cat, v_name, p_allocated, coalesce(p_note, ''), auth.uid(), auth.uid())
    returning id into v_id;
  else
    if not exists (select 1 from public.budget_lines where id = p_id) then
      raise exception 'البند غير موجود' using errcode = 'P0002';
    end if;
    if p_allocated < public.budget_committed(p_id) then
      raise exception 'لا يُخفَّض المخصص دون الملتزم (%)', public.budget_committed(p_id) using errcode = '23514';
    end if;
    update public.budget_lines set fiscal_year = p_year, category = v_cat, name = v_name, allocated = p_allocated,
           note = coalesce(p_note, ''), updated_at = now(), updated_by = auth.uid()
     where id = p_id;
  end if;
  perform public.write_audit('budget.line_save', null, null,
    jsonb_build_object('id', v_id, 'year', p_year, 'category', v_cat, 'name', v_name, 'allocated', p_allocated, 'created', p_id is null), v_name);
  return v_id;
end;
$$;

create or replace function public.budget_line_delete(p_id uuid)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  l public.budget_lines;
begin
  if not public.budget_can_define() then
    raise exception 'تعريف بنود الميزانية للمدير وحده' using errcode = '42501';
  end if;
  select * into l from public.budget_lines where id = p_id;
  if not found then
    raise exception 'البند غير موجود' using errcode = 'P0002';
  end if;
  if exists (select 1 from public.budget_commitments where line_id = p_id) then
    raise exception 'لا يُحذف بند له التزامات؛ احذف التزاماته أولاً' using errcode = '23503';
  end if;
  delete from public.budget_lines where id = p_id;
  perform public.write_audit('budget.line_delete', null, null,
    jsonb_build_object('id', p_id, 'year', l.fiscal_year, 'name', l.name, 'allocated', l.allocated), l.name);
end;
$$;

create or replace function public.budget_commit_save(
  p_id uuid, p_line uuid, p_project uuid, p_desc text, p_amount numeric, p_paid numeric, p_on date, p_note text default '')
returns uuid
language plpgsql security definer set search_path = public
as $$
declare
  v_id uuid := p_id;
  v_line uuid := p_line;
  v_status text := 'active';
  l public.budget_lines;
  v_desc text := btrim(coalesce(p_desc, ''));
begin
  if not public.budget_can_commit() then
    raise exception 'تسجيل الالتزامات للمدير وموظفي مكتبه' using errcode = '42501';
  end if;
  if p_id is not null then
    select line_id, status into v_line, v_status from public.budget_commitments where id = p_id;
    if not found then
      raise exception 'الالتزام غير موجود' using errcode = 'P0002';
    end if;
  end if;
  select * into l from public.budget_lines where id = v_line;
  if not found then
    raise exception 'البند غير موجود' using errcode = 'P0002';
  end if;
  if length(v_desc) not between 1 and 200 then
    raise exception 'وصف الالتزام من 1 إلى 200 حرف' using errcode = '22023';
  end if;
  if p_amount is null or p_amount <= 0 then
    raise exception 'المبلغ الملتزم موجب' using errcode = '22023';
  end if;
  if p_paid is null or p_paid < 0 or p_paid > p_amount then
    raise exception 'المدفوع بين صفر والمبلغ الملتزم' using errcode = '22023';
  end if;
  if p_on is null then
    raise exception 'تاريخ الالتزام مطلوب' using errcode = '22023';
  end if;
  if p_project is not null and not exists (select 1 from public.projects where id = p_project) then
    raise exception 'المشروع غير موجود' using errcode = 'P0002';
  end if;
  if length(coalesce(p_note, '')) > 300 then
    raise exception 'الملاحظة أطول من 300 حرف' using errcode = '22023';
  end if;
  if v_status = 'active' and public.budget_committed(v_line, p_id) + p_amount > l.allocated then
    raise exception 'الالتزام يتجاوز المتبقي من البند (%)', l.allocated - public.budget_committed(v_line, p_id) using errcode = '23514';
  end if;
  if p_id is null then
    insert into public.budget_commitments (line_id, project_id, description, amount, paid, committed_on, note, created_by, updated_by)
    values (v_line, p_project, v_desc, p_amount, p_paid, p_on, coalesce(p_note, ''), auth.uid(), auth.uid())
    returning id into v_id;
  else
    update public.budget_commitments set project_id = p_project, description = v_desc, amount = p_amount, paid = p_paid,
           committed_on = p_on, note = coalesce(p_note, ''), updated_at = now(), updated_by = auth.uid()
     where id = p_id;
  end if;
  perform public.write_audit('budget.commit_save', p_project, null,
    jsonb_build_object('id', v_id, 'line', l.name, 'description', v_desc, 'amount', p_amount, 'paid', p_paid, 'created', p_id is null), l.name);
  return v_id;
end;
$$;

create or replace function public.budget_commit_status(p_id uuid, p_status text)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  c public.budget_commitments;
  l public.budget_lines;
begin
  if not public.budget_can_commit() then
    raise exception 'تسجيل الالتزامات للمدير وموظفي مكتبه' using errcode = '42501';
  end if;
  select * into c from public.budget_commitments where id = p_id;
  if not found then
    raise exception 'الالتزام غير موجود' using errcode = 'P0002';
  end if;
  if p_status not in ('active', 'released') then
    raise exception 'حالة الالتزام: active أو released' using errcode = '22023';
  end if;
  select * into l from public.budget_lines where id = c.line_id;
  if p_status = 'active' and c.status = 'released' and public.budget_committed(c.line_id) + c.amount > l.allocated then
    raise exception 'لا يتّسع البند لإعادة تفعيل الالتزام' using errcode = '23514';
  end if;
  update public.budget_commitments set status = p_status, updated_at = now(), updated_by = auth.uid() where id = p_id;
  perform public.write_audit('budget.commit_status', c.project_id, null,
    jsonb_build_object('id', p_id, 'line', l.name, 'description', c.description, 'status', p_status), l.name);
end;
$$;

create or replace function public.budget_commit_delete(p_id uuid)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  c public.budget_commitments;
  v_line text;
begin
  if not public.budget_can_define() then
    raise exception 'حذف الالتزامات للمدير وحده' using errcode = '42501';
  end if;
  select * into c from public.budget_commitments where id = p_id;
  if not found then
    raise exception 'الالتزام غير موجود' using errcode = 'P0002';
  end if;
  select name into v_line from public.budget_lines where id = c.line_id;
  delete from public.budget_commitments where id = p_id;
  perform public.write_audit('budget.commit_delete', c.project_id, null,
    jsonb_build_object('id', p_id, 'line', v_line, 'description', c.description, 'amount', c.amount), v_line);
end;
$$;

revoke execute on function public.budget_can_define(), public.budget_can_commit(), public.budget_committed(uuid, uuid) from public, anon, authenticated;
revoke execute on function
  public.budget_line_save(uuid, integer, text, text, numeric, text), public.budget_line_delete(uuid),
  public.budget_commit_save(uuid, uuid, uuid, text, numeric, numeric, date, text),
  public.budget_commit_status(uuid, text), public.budget_commit_delete(uuid)
  from public, anon;
grant execute on function
  public.budget_line_save(uuid, integer, text, text, numeric, text), public.budget_line_delete(uuid),
  public.budget_commit_save(uuid, uuid, uuid, text, numeric, numeric, date, text),
  public.budget_commit_status(uuid, text), public.budget_commit_delete(uuid)
  to authenticated;
