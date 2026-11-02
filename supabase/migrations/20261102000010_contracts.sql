-- =====================================================================
--  العقود:
--    1. رقم العقد يُدخله مكتب العقود (والمدير)، فريداً بين العقود.
--    2. دمج الأعمال في عقد واحد: يحدد مكتب العقود الأعمال التي يضمها العقد، أياً كانت
--       شركاتها، وتُتابع الدورة المستندية على مستوى العقد. الأعمال المدمجة تبقى بنوداً
--       داخل العقد، والصف الأصلي يُخفى ويبقى أثره لفك الدمج وفي سجل التدقيق.
--    3. أكثر من مهندس مشرف وحصر ومتابعة وسلامة في العقد الواحد، لكلٍّ رقم تكليفه.
--    4. قيمة الأعمال التعاقدية وقيمة الأعمال المنفذة، والضمان الابتدائي 5% والنهائي 2%
--       من قيمة الأعمال المنفذة.
--    5. إعدادات التعديل الداخلي (الأقسام، لوحة المؤشرات، المسميات، الحركة) ومساعد Claude.
--  يُشغَّل بعد 20261028000009_security_hardening.sql. إعادة تشغيله آمنة.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. أعمدة العقد
-- ---------------------------------------------------------------------
alter table public.projects
  add column if not exists contract_no    text,
  add column if not exists executed_value numeric(16, 3) check (executed_value >= 0),
  add column if not exists merged_into    uuid references public.projects (id) on delete set null,
  add column if not exists merged_at      timestamptz;

create unique index if not exists projects_contract_no_uq
  on public.projects (contract_no) where contract_no is not null and merged_into is null;
create index if not exists projects_merged_idx on public.projects (merged_into) where merged_into is not null;

-- ---------------------------------------------------------------------
-- 2. أعمال العقد (البنود): كل عمل بشركته ورقمه الأصلي
-- ---------------------------------------------------------------------
create table if not exists public.contract_works (
  id             uuid primary key default gen_random_uuid(),
  project_id     uuid not null references public.projects (id) on delete cascade,
  origin_project uuid references public.projects (id) on delete set null,
  title          text not null default '' check (length(title) <= 300),
  company        text not null default '' check (length(company) <= 200),
  ref_no         text not null default '' check (length(ref_no) <= 40),
  notes          text not null default '' check (length(notes) <= 2000),
  sort           integer not null default 0,
  created_at     timestamptz not null default now(),
  created_by     uuid references public.profiles (id) on delete set null,
  constraint contract_works_identity check (btrim(title) <> '' or btrim(company) <> '' or btrim(ref_no) <> '')
);
create index if not exists contract_works_project_idx on public.contract_works (project_id, sort);

-- ---------------------------------------------------------------------
-- 3. مهندسو العقد: أكثر من مهندس من كل نوع، لكلٍّ رقم تكليفه
--    sup مشرف · qty حصر · fol متابعة · saf سلامة
-- ---------------------------------------------------------------------
create table if not exists public.contract_engineers (
  id             uuid primary key default gen_random_uuid(),
  project_id     uuid not null references public.projects (id) on delete cascade,
  origin_project uuid references public.projects (id) on delete set null,
  kind           text not null check (kind in ('sup', 'qty', 'fol', 'saf')),
  name           text not null check (length(btrim(name)) between 2 and 120),
  assign_no      text not null default '' check (length(assign_no) <= 40),
  assigned_on    date,
  work_id        uuid references public.contract_works (id) on delete set null,
  notes          text not null default '' check (length(notes) <= 1000),
  sort           integer not null default 0,
  created_at     timestamptz not null default now(),
  created_by     uuid references public.profiles (id) on delete set null
);
create index if not exists contract_engineers_project_idx on public.contract_engineers (project_id, kind, sort);

-- ---------------------------------------------------------------------
-- 4. نقل البيانات الحالية: عمل لكل مشروع، ومهندسوه من الخانات النصية
--    (رقم التكليف الحالي لكل صف هو رقم تكليف المهندس المشرف)
-- ---------------------------------------------------------------------
insert into public.contract_works (project_id, origin_project, title, company, ref_no, sort)
select p.id, p.id, p.name, p.company, coalesce(p.assign_no, ''), 1
  from public.projects p
 where not exists (select 1 from public.contract_works w where w.project_id = p.id)
   and (btrim(p.name) <> '' or btrim(p.company) <> '' or coalesce(p.assign_no, '') <> '');

insert into public.contract_engineers (project_id, origin_project, kind, name, assign_no, sort)
select p.id, p.id, e.kind, btrim(e.name), case when e.kind = 'sup' then coalesce(p.assign_no, '') else '' end, 1
  from public.projects p
  cross join lateral (values ('sup', p.eng_sup), ('qty', p.eng_qty), ('fol', p.eng_fol), ('saf', p.eng_saf)) as e(kind, name)
 where length(btrim(e.name)) >= 2 and btrim(e.name) <> 'لا ينطبق'
   and not exists (select 1 from public.contract_engineers c where c.project_id = p.id);

-- ---------------------------------------------------------------------
-- 5. أسماء المهندسين في الخانات النصية القديمة تتبع الجدول الجديد
--    (للنسخ السابقة من التطبيق وللتصدير)
-- ---------------------------------------------------------------------
create or replace function public.sync_engineer_names(p_project uuid)
returns void
language plpgsql security definer set search_path = public
as $$
begin
  perform set_config('app.eng_sync', 'on', true);
  update public.projects p
     set eng_sup = coalesce((select string_agg(name, '، ' order by sort, created_at) from public.contract_engineers
                              where project_id = p.id and kind = 'sup'), ''),
         eng_qty = coalesce((select string_agg(name, '، ' order by sort, created_at) from public.contract_engineers
                              where project_id = p.id and kind = 'qty'), ''),
         eng_fol = coalesce((select string_agg(name, '، ' order by sort, created_at) from public.contract_engineers
                              where project_id = p.id and kind = 'fol'), ''),
         eng_saf = coalesce((select string_agg(name, '، ' order by sort, created_at) from public.contract_engineers
                              where project_id = p.id and kind = 'saf'), '')
   where p.id = p_project;
  perform set_config('app.eng_sync', 'off', true);
end;
$$;

create or replace function public.contract_engineers_after()
returns trigger
language plpgsql security definer set search_path = public
as $$
begin
  if tg_op in ('UPDATE', 'DELETE') then
    perform public.sync_engineer_names(old.project_id);
  end if;
  if tg_op in ('INSERT', 'UPDATE') and (tg_op = 'INSERT' or new.project_id is distinct from old.project_id) then
    perform public.sync_engineer_names(new.project_id);
  end if;
  return null;
end;
$$;
drop trigger if exists contract_engineers_after on public.contract_engineers;
create trigger contract_engineers_after
  after insert or update or delete on public.contract_engineers
  for each row execute function public.contract_engineers_after();

-- ختم المشروع: مزامنة أسماء المهندسين ونقل الدمج لا يغيّران «آخر تحديث» ولا يُفحص لهما القسم
create or replace function public.projects_stamp()
returns trigger
language plpgsql security definer set search_path = public
as $$
begin
  if tg_op = 'UPDATE' and (current_setting('app.user_cleanup', true) = 'on'
                           or current_setting('app.eng_sync', true) = 'on') then
    return new;
  end if;
  new.assign_no   := nullif(btrim(coalesce(new.assign_no, '')), '');
  new.contract_no := nullif(btrim(coalesce(new.contract_no, '')), '');
  if tg_op = 'UPDATE' and current_setting('app.recalc', true) = 'on' then
    new.updated_at := old.updated_at;
    new.updated_by := old.updated_by;
    return new;
  end if;
  if tg_op = 'INSERT' then
    new.created_by := coalesce(auth.uid(), new.created_by);
    new.updated_by := coalesce(auth.uid(), new.updated_by);
    new.created_at := coalesce(new.created_at, now());
    if coalesce(new.sort_order, 0) = 0 then
      select coalesce(max(sort_order), 0) + 1 into new.sort_order from public.projects;
    end if;
  else
    new.created_by := old.created_by;
    new.created_at := old.created_at;
    new.updated_by := coalesce(auth.uid(), new.updated_by);
  end if;
  new.updated_at := now();
  if not exists (select 1 from public.departments where key = new.department and can_supervise) then
    raise exception 'القسم المشرف يجب أن يكون قسماً يمكن إسناد الإشراف إليه' using errcode = '23514';
  end if;
  return new;
end;
$$;

-- عقد جديد يبدأ بعمله الأول تلقائياً
create or replace function public.projects_first_work()
returns trigger
language plpgsql security definer set search_path = public
as $$
begin
  if current_setting('app.seeding', true) = 'on' then
    return null;
  end if;
  if btrim(new.name) <> '' or btrim(new.company) <> '' or coalesce(new.assign_no, '') <> '' then
    insert into public.contract_works (project_id, origin_project, title, company, ref_no, sort, created_by)
    values (new.id, new.id, new.name, new.company, coalesce(new.assign_no, ''), 1, auth.uid());
  end if;
  return null;
end;
$$;
drop trigger if exists projects_first_work on public.projects;
create trigger projects_first_work
  after insert on public.projects
  for each row execute function public.projects_first_work();

-- ---------------------------------------------------------------------
-- 6. المالية: قيمة الأعمال المنفذة، والضمانان منها
-- ---------------------------------------------------------------------
create or replace function public.projects_finance_calc()
returns trigger
language plpgsql security definer set search_path = public
as $$
begin
  new.guarantee_initial := round(new.executed_value * public.setting_num('finance.guarantee_initial_rate', 0.05), 3);
  new.guarantee_final   := round(new.executed_value * public.setting_num('finance.guarantee_final_rate', 0.02), 3);
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

create or replace function public.projects_finance_guard()
returns trigger
language plpgsql security definer set search_path = public
as $$
begin
  if current_setting('app.seeding', true) = 'on' or current_setting('app.trusted', true) = 'on' or auth.uid() is null then
    return new;
  end if;
  if tg_op = 'INSERT' then
    if coalesce(new.contract_value, new.executed_value, new.payment_first, new.payment_second, new.payment_final,
                new.deductions) is not null
       and not public.is_director() then
      raise exception 'تُدخل البيانات المالية بعد إنشاء العقد' using errcode = '42501';
    end if;
  elsif (old.contract_value, old.executed_value, old.payment_first, old.payment_second, old.payment_final, old.deductions)
        is distinct from
        (new.contract_value, new.executed_value, new.payment_first, new.payment_second, new.payment_final, new.deductions)
        and not public.can_edit_form(new.id, 'f01') then
    raise exception 'البيانات المالية للعقد يحدّثها من يختص بـ«أمر تعاقد»' using errcode = '42501';
  end if;
  return new;
end;
$$;

-- حفظ البيانات المالية مع قيمة الأعمال المنفذة (النسخة السابقة بست قيم تبقى للتطبيقات القديمة)
create or replace function public.set_contract_finance(
  p_project uuid, p_contract_value numeric, p_executed_value numeric, p_payment_first numeric,
  p_payment_second numeric, p_payment_final numeric, p_deductions numeric)
returns void
language plpgsql security definer set search_path = public
as $$
begin
  if not public.can_edit_form(p_project, 'f01') then
    raise exception 'البيانات المالية للعقد يحدّثها من يختص بـ«أمر تعاقد»' using errcode = '42501';
  end if;
  if not public.writes_allowed() then
    raise exception 'المنظومة مجمّدة حالياً (قراءة فقط)' using errcode = '42501';
  end if;
  if least(p_contract_value, p_executed_value, p_payment_first, p_payment_second, p_payment_final, p_deductions) < 0 then
    raise exception 'القيم المالية لا تكون سالبة' using errcode = '22023';
  end if;
  update public.projects
     set contract_value = p_contract_value,
         executed_value = p_executed_value,
         payment_first  = p_payment_first,
         payment_second = p_payment_second,
         payment_final  = p_payment_final,
         deductions     = p_deductions
   where id = p_project and merged_into is null;
  if not found then
    raise exception 'العقد غير موجود' using errcode = '22023';
  end if;
end;
$$;

-- إعادة حساب الضمانات من قيمة الأعمال المنفذة دون تغيير «آخر تحديث»
do $$
begin
  perform set_config('app.recalc', 'on', true);
  perform set_config('app.trusted', 'on', true);
  update public.projects set executed_value = executed_value;
  perform set_config('app.trusted', 'off', true);
  perform set_config('app.recalc', 'off', true);
end $$;

-- ---------------------------------------------------------------------
-- 7. التدقيق: أعمدة العقد الجديدة، والمهندسون يُدقَّقون من جدولهم
-- ---------------------------------------------------------------------
create or replace function public.projects_audit()
returns trigger
language plpgsql security definer set search_path = public
as $$
declare
  changes jsonb := '{}'::jsonb;
  col     text;
  o       jsonb;
  n       jsonb;
begin
  if current_setting('app.seeding', true) = 'on' or current_setting('app.eng_sync', true) = 'on' then
    return null;
  end if;
  if tg_op = 'INSERT' then
    perform public.write_audit('project.create', new.id, null,
      jsonb_build_object('assign_no', new.assign_no, 'name', new.name, 'owner', new.owner, 'company', new.company));
  elsif tg_op = 'DELETE' then
    perform public.write_audit('project.delete', old.id, null,
      jsonb_build_object('assign_no', old.assign_no, 'contract_no', old.contract_no, 'name', old.name),
      btrim(coalesce(old.assign_no, '') || ' ' || old.name));
  else
    o := to_jsonb(old); n := to_jsonb(new);
    foreach col in array array['assign_no', 'code', 'name', 'owner', 'company', 'department', 'notes', 'contract_no',
                               'contract_value', 'executed_value', 'payment_first', 'payment_second', 'payment_final',
                               'deductions'] loop
      if o -> col is distinct from n -> col then
        changes := changes || jsonb_build_object(col, jsonb_build_object('from', o -> col, 'to', n -> col));
      end if;
    end loop;
    if changes <> '{}'::jsonb and current_setting('app.recalc', true) is distinct from 'on' then
      perform public.write_audit('project.update', new.id, null, changes);
    end if;
  end if;
  return null;
end;
$$;

-- عنوان العقد في السجل: رقم العقد إن وُجد
create or replace function public.project_label(p_id uuid)
returns text
language sql stable security definer set search_path = public
as $$
  select btrim(coalesce('عقد ' || contract_no || ' · ', '') || coalesce(assign_no, '') || ' ' || name)
    from public.projects where id = p_id
$$;

-- ---------------------------------------------------------------------
-- 8. رقم العقد: من مكتب العقود والمدير
-- ---------------------------------------------------------------------
create or replace function public.set_contract_no(p_project uuid, p_no text)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  v_no  text := nullif(btrim(coalesce(p_no, '')), '');
  v_old text;
begin
  if not public.has_token(p_project, array['contracts']) then
    raise exception 'رقم العقد يُدخله مكتب العقود' using errcode = '42501';
  end if;
  select contract_no into v_old from public.projects where id = p_project and merged_into is null;
  if not found then
    raise exception 'العقد غير موجود' using errcode = '22023';
  end if;
  if v_no is not null and length(v_no) > 40 then
    raise exception 'رقم العقد لا يتجاوز 40 حرفاً' using errcode = '22023';
  end if;
  if v_no is not null and exists (select 1 from public.projects
                                   where contract_no = v_no and merged_into is null and id <> p_project) then
    raise exception 'رقم العقد % مستخدم لعقد آخر', v_no using errcode = '23505';
  end if;
  if v_old is not distinct from v_no then
    return;
  end if;
  perform set_config('app.trusted', 'on', true);
  update public.projects set contract_no = v_no where id = p_project;
  perform set_config('app.trusted', 'off', true);
end;
$$;

-- ---------------------------------------------------------------------
-- 9. أعمال العقد: مكتب العقود وموظفو مكتب المدير والمدير
-- ---------------------------------------------------------------------
create or replace function public.save_work(
  p_id uuid, p_project uuid, p_title text, p_company text, p_ref_no text, p_notes text)
returns uuid
language plpgsql security definer set search_path = public
as $$
declare
  w    public.contract_works;
  v_id uuid := p_id;
begin
  if v_id is not null then
    select * into w from public.contract_works where id = v_id;
    if not found then
      raise exception 'العمل غير موجود' using errcode = '22023';
    end if;
    p_project := w.project_id;
  end if;
  if not exists (select 1 from public.projects where id = p_project and merged_into is null) then
    raise exception 'العقد غير موجود' using errcode = '22023';
  end if;
  if not public.has_token(p_project, array['contracts', 'office_staff']) then
    raise exception 'أعمال العقد يحدّثها مكتب العقود أو مكتب المدير' using errcode = '42501';
  end if;
  if btrim(coalesce(p_title, '')) = '' and btrim(coalesce(p_company, '')) = '' and btrim(coalesce(p_ref_no, '')) = '' then
    raise exception 'اكتب وصف العمل أو الشركة' using errcode = '22023';
  end if;
  if v_id is null then
    insert into public.contract_works (project_id, title, company, ref_no, notes, sort, created_by)
    values (p_project, btrim(coalesce(p_title, '')), btrim(coalesce(p_company, '')), btrim(coalesce(p_ref_no, '')),
            coalesce(p_notes, ''),
            (select coalesce(max(sort), 0) + 1 from public.contract_works where project_id = p_project), auth.uid())
    returning id into v_id;
    perform public.write_audit('contract.work_add', p_project, null,
      jsonb_build_object('work_id', v_id, 'title', btrim(coalesce(p_title, '')), 'company', btrim(coalesce(p_company, ''))));
  else
    update public.contract_works
       set title = btrim(coalesce(p_title, '')), company = btrim(coalesce(p_company, '')),
           ref_no = btrim(coalesce(p_ref_no, '')), notes = coalesce(p_notes, '')
     where id = v_id;
    perform public.write_audit('contract.work_update', p_project, null,
      jsonb_build_object('work_id', v_id,
        'title', jsonb_build_object('from', w.title, 'to', btrim(coalesce(p_title, ''))),
        'company', jsonb_build_object('from', w.company, 'to', btrim(coalesce(p_company, '')))));
  end if;
  return v_id;
end;
$$;

create or replace function public.delete_work(p_id uuid)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  w public.contract_works;
begin
  select * into w from public.contract_works where id = p_id;
  if not found then
    raise exception 'العمل غير موجود' using errcode = '22023';
  end if;
  if not public.has_token(w.project_id, array['contracts', 'office_staff']) then
    raise exception 'أعمال العقد يحدّثها مكتب العقود أو مكتب المدير' using errcode = '42501';
  end if;
  if w.origin_project is not null and w.origin_project <> w.project_id then
    raise exception 'هذا العمل دُمج من عقد آخر؛ افصله بفك الدمج بدل حذفه' using errcode = 'P0001';
  end if;
  delete from public.contract_works where id = p_id;
  perform public.write_audit('contract.work_delete', w.project_id, null,
    jsonb_build_object('work_id', w.id, 'title', w.title, 'company', w.company, 'ref_no', w.ref_no));
end;
$$;

-- ---------------------------------------------------------------------
-- 10. المهندسون: من يختص بنموذج التكليف المقابل (تكليف مهندس مشرف/حصر/متابعة/سلامة)
-- ---------------------------------------------------------------------
create or replace function public.engineer_form(p_kind text)
returns text
language sql stable security definer set search_path = public
as $$
  select key from public.form_defs where engineer_field = 'eng_' || p_kind order by sort limit 1
$$;

create or replace function public.can_assign_engineer(p_project uuid, p_kind text)
returns boolean
language plpgsql stable security definer set search_path = public
as $$
declare
  f text := public.engineer_form(p_kind);
begin
  if f is null then
    return public.is_director();
  end if;
  return public.can_edit_form(p_project, f);
end;
$$;

create or replace function public.save_engineer(
  p_id uuid, p_project uuid, p_kind text, p_name text, p_assign_no text, p_assigned_on date,
  p_work uuid, p_notes text)
returns uuid
language plpgsql security definer set search_path = public
as $$
declare
  e    public.contract_engineers;
  v_id uuid := p_id;
begin
  if p_kind not in ('sup', 'qty', 'fol', 'saf') then
    raise exception 'نوع المهندس غير معروف' using errcode = '22023';
  end if;
  if v_id is not null then
    select * into e from public.contract_engineers where id = v_id;
    if not found then
      raise exception 'التكليف غير موجود' using errcode = '22023';
    end if;
    p_project := e.project_id;
  end if;
  if not exists (select 1 from public.projects where id = p_project and merged_into is null) then
    raise exception 'العقد غير موجود' using errcode = '22023';
  end if;
  if not public.can_assign_engineer(p_project, p_kind)
     or (v_id is not null and not public.can_assign_engineer(p_project, e.kind)) then
    raise exception 'تكليف هذا المهندس خارج اختصاصك' using errcode = '42501';
  end if;
  if length(btrim(coalesce(p_name, ''))) < 2 then
    raise exception 'اكتب اسم المهندس' using errcode = '22023';
  end if;
  if p_work is not null and not exists (select 1 from public.contract_works where id = p_work and project_id = p_project) then
    raise exception 'العمل المحدد ليس من أعمال هذا العقد' using errcode = '22023';
  end if;
  if btrim(coalesce(p_assign_no, '')) <> '' and exists (
       select 1 from public.contract_engineers
        where project_id = p_project and kind = p_kind and assign_no = btrim(p_assign_no)
          and id is distinct from v_id) then
    raise exception 'رقم التكليف % مسجّل لمهندس آخر في هذا العقد', btrim(p_assign_no) using errcode = '23505';
  end if;

  if v_id is null then
    insert into public.contract_engineers (project_id, kind, name, assign_no, assigned_on, work_id, notes, sort, created_by)
    values (p_project, p_kind, btrim(p_name), btrim(coalesce(p_assign_no, '')), p_assigned_on, p_work, coalesce(p_notes, ''),
            (select coalesce(max(sort), 0) + 1 from public.contract_engineers where project_id = p_project and kind = p_kind),
            auth.uid())
    returning id into v_id;
    perform public.write_audit('engineer.add', p_project, public.engineer_form(p_kind),
      jsonb_build_object('engineer_id', v_id, 'kind', p_kind, 'name', btrim(p_name), 'assign_no', btrim(coalesce(p_assign_no, ''))));
  else
    update public.contract_engineers
       set kind = p_kind, name = btrim(p_name), assign_no = btrim(coalesce(p_assign_no, '')),
           assigned_on = p_assigned_on, work_id = p_work, notes = coalesce(p_notes, '')
     where id = v_id;
    perform public.write_audit('engineer.update', p_project, public.engineer_form(p_kind),
      jsonb_build_object('engineer_id', v_id, 'kind', p_kind,
        'name', jsonb_build_object('from', e.name, 'to', btrim(p_name)),
        'assign_no', jsonb_build_object('from', e.assign_no, 'to', btrim(coalesce(p_assign_no, '')))));
  end if;
  return v_id;
end;
$$;

create or replace function public.delete_engineer(p_id uuid)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  e public.contract_engineers;
begin
  select * into e from public.contract_engineers where id = p_id;
  if not found then
    raise exception 'التكليف غير موجود' using errcode = '22023';
  end if;
  if not public.can_assign_engineer(e.project_id, e.kind) then
    raise exception 'تكليف هذا المهندس خارج اختصاصك' using errcode = '42501';
  end if;
  delete from public.contract_engineers where id = p_id;
  perform public.write_audit('engineer.delete', e.project_id, public.engineer_form(e.kind),
    jsonb_build_object('engineer_id', e.id, 'kind', e.kind, 'name', e.name, 'assign_no', e.assign_no));
end;
$$;

-- النسخ السابقة من التطبيق: خانة نصية واحدة لكل نوع
create or replace function public.set_engineer(p_project uuid, p_form text, p_name text)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  f      text;
  v_kind text;
  v_name text := btrim(coalesce(p_name, ''));
  v_cur  text;
begin
  select engineer_field into f from public.form_defs where key = p_form;
  if f is null then
    raise exception 'هذا النموذج ليس تكليف مهندس' using errcode = '22023';
  end if;
  if not public.can_edit_form(p_project, p_form) then
    raise exception 'إسناد هذا المهندس خارج اختصاصك' using errcode = '42501';
  end if;
  v_kind := substring(f from 5);
  select coalesce(string_agg(name, '، ' order by sort, created_at), '') into v_cur
    from public.contract_engineers where project_id = p_project and kind = v_kind;
  if v_cur = v_name then
    return;
  end if;
  delete from public.contract_engineers where project_id = p_project and kind = v_kind;
  if length(v_name) >= 2 then
    insert into public.contract_engineers (project_id, kind, name, sort, created_by)
    values (p_project, v_kind, v_name, 1, auth.uid());
  end if;
  perform public.write_audit('engineer.set', p_project, p_form,
    jsonb_build_object('kind', v_kind, 'from', v_cur, 'to', v_name));
end;
$$;

-- ---------------------------------------------------------------------
-- 11. دمج الأعمال في عقد واحد (مكتب العقود والمدير) وفكّه (المدير)
--     الدورة المستندية تُتابع على العقد: حالة النموذج في العقد تبقى، وما لم يبدأ فيه
--     يأخذ حالة العمل المدمج. القيم المالية تُجمع. الصف الأصلي يُخفى ويبقى للرجوع.
-- ---------------------------------------------------------------------
create or replace function public.merge_contracts(p_target uuid, p_sources uuid[])
returns integer
language plpgsql security definer set search_path = public
as $$
declare
  t      public.projects;
  s      public.projects;
  v_src  uuid;
  n      integer := 0;
  v_info jsonb := '[]'::jsonb;
begin
  select * into t from public.projects where id = p_target and merged_into is null for update;
  if not found then
    raise exception 'العقد المستهدف غير موجود' using errcode = '22023';
  end if;
  if not public.has_token(p_target, array['contracts']) then
    raise exception 'دمج الأعمال في العقود من صلاحية مكتب العقود' using errcode = '42501';
  end if;
  if coalesce(array_length(p_sources, 1), 0) = 0 then
    raise exception 'اختر الأعمال المراد دمجها' using errcode = '22023';
  end if;

  perform set_config('app.trusted', 'on', true);
  foreach v_src in array p_sources loop
    if v_src = p_target then
      continue;
    end if;
    select * into s from public.projects where id = v_src and merged_into is null for update;
    if not found then
      raise exception 'أحد الأعمال المختارة غير موجود أو مدمج من قبل' using errcode = '22023';
    end if;
    if not public.has_token(v_src, array['contracts']) then
      raise exception 'دمج الأعمال في العقود من صلاحية مكتب العقود' using errcode = '42501';
    end if;

    -- الأعمال والمهندسون ينتقلون مع أصلهم (ليعودوا عند فك الدمج)، وما دُمج في العمل من قبل يتبع العقد
    update public.contract_works set project_id = p_target, origin_project = coalesce(origin_project, v_src),
           sort = sort + (select coalesce(max(sort), 0) from public.contract_works where project_id = p_target)
     where project_id = v_src;
    update public.contract_engineers set project_id = p_target, origin_project = coalesce(origin_project, v_src),
           sort = sort + (select coalesce(max(sort), 0) from public.contract_engineers where project_id = p_target)
     where project_id = v_src;
    update public.projects set merged_into = p_target where merged_into = v_src;

    -- حالات النماذج: ما لم يبدأ في العقد يأخذ حالة العمل المدمج
    insert into public.project_forms as pf (project_id, form_key, status, updated_at, updated_by, approved_by)
    select p_target, f.form_key, f.status, now(), auth.uid(), f.approved_by
      from public.project_forms f
     where f.project_id = v_src and f.status <> 'todo'
    on conflict (project_id, form_key) do update
       set status = excluded.status, updated_at = excluded.updated_at, updated_by = excluded.updated_by,
           approved_by = excluded.approved_by
     where pf.status = 'todo';

    -- الطلبات المعلّقة: تنتقل إن لم يكن للعقد طلب معلّق للنموذج نفسه، وإلا تُسحب
    update public.change_requests c set project_id = p_target
     where c.project_id = v_src and c.state = 'pending'
       and not exists (select 1 from public.change_requests x
                        where x.project_id = p_target and x.form_key = c.form_key and x.state = 'pending');
    update public.change_requests set state = 'withdrawn', decided_at = now(),
           decision_note = 'سُحب عند دمج العمل في عقد'
     where project_id = v_src and state = 'pending';

    update public.quality_notes set project_id = p_target where project_id = v_src;
    update public.notifications set project_id = p_target where project_id = v_src;

    -- القيم المالية تُجمع في العقد
    update public.projects set
      contract_value = case when contract_value is null and s.contract_value is null then null
                            else coalesce(contract_value, 0) + coalesce(s.contract_value, 0) end,
      executed_value = case when executed_value is null and s.executed_value is null then null
                            else coalesce(executed_value, 0) + coalesce(s.executed_value, 0) end,
      payment_first  = case when payment_first is null and s.payment_first is null then null
                            else coalesce(payment_first, 0) + coalesce(s.payment_first, 0) end,
      payment_second = case when payment_second is null and s.payment_second is null then null
                            else coalesce(payment_second, 0) + coalesce(s.payment_second, 0) end,
      payment_final  = case when payment_final is null and s.payment_final is null then null
                            else coalesce(payment_final, 0) + coalesce(s.payment_final, 0) end,
      deductions     = case when deductions is null and s.deductions is null then null
                            else coalesce(deductions, 0) + coalesce(s.deductions, 0) end,
      contract_no    = coalesce(contract_no, s.contract_no)
     where id = p_target;

    update public.projects set merged_into = p_target, merged_at = now() where id = v_src;
    perform public.write_audit('contract.merged_into', v_src, null,
      jsonb_build_object('target', p_target, 'target_label', public.project_label(p_target)));
    v_info := v_info || jsonb_build_object('id', s.id, 'assign_no', s.assign_no, 'contract_no', s.contract_no,
                                           'name', s.name, 'company', s.company);
    n := n + 1;
  end loop;
  perform public.sync_engineer_names(p_target);
  perform set_config('app.trusted', 'off', true);

  if n > 0 then
    update public.projects set updated_at = now(), updated_by = auth.uid() where id = p_target;
    perform public.write_audit('contract.merge', p_target, null, jsonb_build_object('sources', v_info, 'count', n));
  end if;
  return n;
end;
$$;

create or replace function public.unmerge_contract(p_source uuid)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  s public.projects;
  t uuid;
begin
  if not public.is_director() then
    raise exception 'فك الدمج من صلاحية مدير المكتب' using errcode = '42501';
  end if;
  select * into s from public.projects where id = p_source for update;
  if not found or s.merged_into is null then
    raise exception 'هذا العمل غير مدمج' using errcode = '22023';
  end if;
  t := s.merged_into;
  perform set_config('app.trusted', 'on', true);
  update public.contract_works set project_id = p_source where project_id = t and origin_project = p_source;
  update public.contract_engineers set project_id = p_source where project_id = t and origin_project = p_source;
  update public.projects set
    contract_value = case when s.contract_value is null then contract_value else greatest(coalesce(contract_value, 0) - s.contract_value, 0) end,
    executed_value = case when s.executed_value is null then executed_value else greatest(coalesce(executed_value, 0) - s.executed_value, 0) end,
    payment_first  = case when s.payment_first  is null then payment_first  else greatest(coalesce(payment_first, 0)  - s.payment_first, 0) end,
    payment_second = case when s.payment_second is null then payment_second else greatest(coalesce(payment_second, 0) - s.payment_second, 0) end,
    payment_final  = case when s.payment_final  is null then payment_final  else greatest(coalesce(payment_final, 0)  - s.payment_final, 0) end,
    deductions     = case when s.deductions     is null then deductions     else greatest(coalesce(deductions, 0)     - s.deductions, 0) end
   where id = t;
  update public.projects set merged_into = null, merged_at = null,
         contract_no = case when exists (select 1 from public.projects x where x.contract_no = s.contract_no
                                          and x.merged_into is null and x.id <> p_source) then null else contract_no end
   where id = p_source;
  perform public.sync_engineer_names(t);
  perform public.sync_engineer_names(p_source);
  perform set_config('app.trusted', 'off', true);
  perform public.write_audit('contract.unmerge', t, null,
    jsonb_build_object('source', p_source, 'source_label', public.project_label(p_source)));
end;
$$;

-- الأعمال المدمجة في عقد (صفوفها الأصلية مخفية عن القوائم)
create or replace function public.merged_sources(p_target uuid)
returns setof jsonb
language sql stable security definer set search_path = public
as $$
  select jsonb_build_object('id', p.id, 'assign_no', p.assign_no, 'contract_no', p.contract_no, 'name', p.name,
                            'company', p.company, 'merged_at', p.merged_at)
    from public.projects p
   where p.merged_into = p_target and public.is_member()
   order by p.merged_at, p.sort_order
$$;

-- ---------------------------------------------------------------------
-- 12. نسب الإنجاز: العقود القائمة فقط
-- ---------------------------------------------------------------------
create or replace view public.v_project_progress
with (security_invoker = true)
as
with cells as (
  select p.id as project_id, d.key, d.sort, d.stage, coalesce(pf.status, 'todo') as status
  from public.projects p
  cross join public.form_defs d
  left join public.project_forms pf on pf.project_id = p.id and pf.form_key = d.key
  where d.active and p.merged_into is null
),
agg as (
  select project_id,
         count(*) filter (where status = 'done') as done,
         count(*) filter (where status = 'wip')  as wip,
         count(*) filter (where status = 'na')   as na,
         count(*) filter (where status <> 'na')  as required,
         (array_agg(key order by sort) filter (where status not in ('done', 'na')))[1] as next_form
  from cells group by project_id
)
select a.project_id, a.done, a.wip, a.na, a.required,
       case when a.required = 0 then 1.0 else round(a.done::numeric / a.required, 4) end as pct,
       a.next_form,
       nf.name as next_form_name,
       case when a.next_form is null then 'اكتملت الدورة' else st.name end as current_stage,
       case when a.next_form is null then 'مكتملة'
            when a.done + a.wip = 0 then 'لم تبدأ'
            else 'جارية' end as cycle_state
from agg a
left join public.form_defs nf on nf.key = a.next_form
left join public.stages st on st.idx = nf.stage;

-- ---------------------------------------------------------------------
-- 13. الإعدادات: التعديل الداخلي ومساعد Claude
-- ---------------------------------------------------------------------
insert into public.app_settings (key, value) values
  ('ui.motion',       '"full"'),
  ('ui.nav',          '{"hidden": [], "order": [], "labels": {}}'),
  ('ui.dashboard',    '{"sections": []}'),
  ('ui.labels',       '{}'),
  ('ai.enabled',      'true'),
  ('ai.model',        '"claude-sonnet-5-5"'),
  ('ai.instructions', '""')
on conflict (key) do nothing;

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
    when p_key in ('finance.guarantee_initial_rate', 'finance.guarantee_final_rate') then
      t = 'number' and (p_value #>> '{}')::numeric between 0 and 0.5
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
    when p_key = 'ai.model' then
      t = 'string' and (p_value #>> '{}') ~ '^[a-z0-9][a-z0-9.\-]{2,60}$'
    when p_key = 'ai.instructions' then
      t = 'string' and length(p_value #>> '{}') <= 4000
    else false
  end;
  if not coalesce(ok, false) then
    raise exception 'قيمة غير صالحة للإعداد %', p_key using errcode = '22023';
  end if;
  -- لا يُفرض التحقق بخطوتين قبل أن يفعّله المدير لنفسه، حتى لا يُغلق الباب عليه
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

create or replace function public.public_settings()
returns jsonb
language sql stable security definer set search_path = public
as $$
  select coalesce(jsonb_object_agg(key, value), '{}'::jsonb)
  from public.app_settings
  where key like 'brand.%' or key in ('security.signups_open', 'security.idle_minutes',
                                       'security.require_mfa_all', 'security.require_mfa_director', 'ui.motion')
$$;

-- ---------------------------------------------------------------------
-- 14. مساعد Claude (المدير وحده): ملخص المنظومة الذي يُرسل مع كل سؤال، وسجل الاستخدام.
--     مفتاح Anthropic لا يدخل قاعدة البيانات ولا التطبيق؛ يبقى سراً في Edge Functions.
-- ---------------------------------------------------------------------
create or replace function public.ai_context()
returns jsonb
language plpgsql stable security definer set search_path = public
as $$
begin
  if not public.is_director() then
    raise exception 'مساعد Claude لمدير المكتب وحده' using errcode = '42501';
  end if;
  if not public.setting_bool('ai.enabled', true) then
    raise exception 'مساعد Claude متوقف من الإعدادات' using errcode = 'P0001';
  end if;
  return jsonb_build_object(
    'generated_at', now(),
    'org', public.setting('brand.org_name'),
    'currency', public.setting('finance.currency'),
    'guarantee_rates', jsonb_build_object('initial', public.setting('finance.guarantee_initial_rate'),
                                          'final', public.setting('finance.guarantee_final_rate'),
                                          'base', 'قيمة الأعمال المنفذة'),
    'stages', (select coalesce(jsonb_agg(name order by idx), '[]'::jsonb) from public.stages),
    'forms', (select coalesce(jsonb_agg(jsonb_build_object('key', key, 'name', name, 'stage', stage, 'sensitive', sensitive)
                                        order by sort), '[]'::jsonb) from public.form_defs where active),
    'departments', (select coalesce(jsonb_object_agg(key, name), '{}'::jsonb) from public.departments),
    'contracts', (select coalesce(jsonb_agg(c order by (c ->> 'sort')::int), '[]'::jsonb) from (
      select jsonb_strip_nulls(jsonb_build_object(
               'sort', p.sort_order, 'contract_no', p.contract_no, 'assign_no', p.assign_no, 'name', p.name,
               'owner', p.owner, 'company', p.company, 'department', p.department,
               'contract_value', p.contract_value, 'executed_value', p.executed_value,
               'payments', coalesce(p.payment_first, 0) + coalesce(p.payment_second, 0) + coalesce(p.payment_final, 0),
               'deductions', p.deductions, 'guarantee_initial', p.guarantee_initial, 'guarantee_final', p.guarantee_final,
               'progress_pct', v.pct, 'cycle', v.cycle_state, 'stage', v.current_stage, 'next_form', v.next_form_name,
               'works', (select jsonb_agg(jsonb_build_object('title', w.title, 'company', w.company, 'ref', w.ref_no) order by w.sort)
                           from public.contract_works w where w.project_id = p.id),
               'engineers', (select jsonb_agg(jsonb_build_object('kind', e.kind, 'name', e.name, 'assign_no', e.assign_no)
                                              order by e.kind, e.sort)
                               from public.contract_engineers e where e.project_id = p.id),
               'notes', nullif(p.notes, ''))) as c
        from public.projects p
        left join public.v_project_progress v on v.project_id = p.id
       where p.merged_into is null
       order by p.sort_order
       limit 400) x),
    'pending_requests', (select coalesce(jsonb_agg(jsonb_build_object(
                            'contract', public.project_label(r.project_id), 'form', d.name,
                            'to', r.to_status, 'by', public.actor_name(r.requested_by), 'at', r.requested_at)
                            order by r.requested_at), '[]'::jsonb)
                           from public.change_requests r join public.form_defs d on d.key = r.form_key
                          where r.state = 'pending'),
    'recent_activity', (select coalesce(jsonb_agg(jsonb_build_object('at', a.at, 'who', a.actor_name, 'action', a.action,
                                                                     'contract', a.project_label, 'form', a.form_key)
                                                  order by a.at desc), '[]'::jsonb)
                          from (select * from public.audit_log order by at desc limit 40) a),
    'users', (select jsonb_build_object('active', count(*) filter (where active), 'pending', count(*) filter (where not active and role is null))
                from public.profiles),
    'ideas_open', (select count(*) from public.ideas where status in ('new', 'planned', 'in_progress')),
    'instructions', public.setting('ai.instructions'),
    'model', public.setting('ai.model'));
end;
$$;

create or replace function public.ai_log(p_model text, p_input_tokens integer, p_output_tokens integer, p_question_chars integer)
returns void
language plpgsql security definer set search_path = public
as $$
begin
  if not public.is_director() then
    raise exception 'مساعد Claude لمدير المكتب وحده' using errcode = '42501';
  end if;
  perform public.write_audit('ai.ask', null, null,
    jsonb_build_object('model', left(coalesce(p_model, ''), 60), 'input_tokens', p_input_tokens,
                       'output_tokens', p_output_tokens, 'question_chars', p_question_chars),
    'مساعد Claude');
end;
$$;

-- ---------------------------------------------------------------------
-- 15. سياسات الوصول والصلاحيات
-- ---------------------------------------------------------------------
-- الصفوف المدمجة في عقود تختفي من القوائم (تبقى للرجوع عبر merged_sources وفك الدمج)
drop policy if exists projects_read on public.projects;
create policy projects_read on public.projects for select to authenticated
  using (public.is_member() and merged_into is null);

alter table public.contract_works     enable row level security;
alter table public.contract_engineers enable row level security;
drop policy if exists contract_works_read on public.contract_works;
create policy contract_works_read on public.contract_works for select to authenticated using (public.is_member());
drop policy if exists contract_engineers_read on public.contract_engineers;
create policy contract_engineers_read on public.contract_engineers for select to authenticated using (public.is_member());

revoke all on public.contract_works, public.contract_engineers from anon;
revoke insert, update, delete, truncate on public.contract_works, public.contract_engineers from authenticated;
grant select on public.contract_works, public.contract_engineers to authenticated;
grant all on public.contract_works, public.contract_engineers to service_role;

-- قيمة الأعمال المنفذة تُحدَّث كبقية البيانات المالية (بحماية «أمر تعاقد»)؛ رقم العقد والدمج عبر الدوال فقط
revoke insert, update on public.projects from authenticated;
grant insert (assign_no, code, name, owner, company, department, notes, eng_sup, eng_qty, eng_fol, eng_saf, sort_order)
  on public.projects to authenticated;
grant update (assign_no, code, name, owner, company, department, notes, eng_sup, eng_qty, eng_fol, eng_saf, sort_order,
              contract_value, executed_value, payment_first, payment_second, payment_final, deductions)
  on public.projects to authenticated;

revoke execute on function
  public.sync_engineer_names(uuid), public.contract_engineers_after(), public.projects_first_work(),
  public.projects_stamp(), public.projects_finance_calc(), public.projects_finance_guard(), public.projects_audit(),
  public.engineer_form(text), public.can_assign_engineer(uuid, text), public.project_label(uuid)
from public, anon, authenticated;

revoke execute on function
  public.set_contract_finance(uuid, numeric, numeric, numeric, numeric, numeric, numeric),
  public.set_contract_no(uuid, text), public.save_work(uuid, uuid, text, text, text, text), public.delete_work(uuid),
  public.save_engineer(uuid, uuid, text, text, text, date, uuid, text), public.delete_engineer(uuid),
  public.set_engineer(uuid, text, text), public.merge_contracts(uuid, uuid[]), public.unmerge_contract(uuid),
  public.merged_sources(uuid), public.set_setting(text, jsonb), public.public_settings(), public.ai_context(),
  public.ai_log(text, integer, integer, integer)
from public, anon;
grant execute on function
  public.set_contract_finance(uuid, numeric, numeric, numeric, numeric, numeric, numeric),
  public.set_contract_no(uuid, text), public.save_work(uuid, uuid, text, text, text, text), public.delete_work(uuid),
  public.save_engineer(uuid, uuid, text, text, text, date, uuid, text), public.delete_engineer(uuid),
  public.set_engineer(uuid, text, text), public.merge_contracts(uuid, uuid[]), public.unmerge_contract(uuid),
  public.merged_sources(uuid), public.set_setting(text, jsonb), public.ai_context(),
  public.ai_log(text, integer, integer, integer)
to authenticated;
grant execute on function public.public_settings() to anon, authenticated;

-- التحديث اللحظي
do $$
declare
  t text;
begin
  foreach t in array array['contract_works', 'contract_engineers'] loop
    if not exists (select 1 from pg_publication_tables
                   where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = t) then
      execute format('alter publication supabase_realtime add table public.%I', t);
    end if;
  end loop;
end $$;

notify pgrst, 'reload schema';

select 'تم: العقود، ودمج الأعمال، والمهندسون بأرقام التكليف، وقيمة الأعمال المنفذة، والتعديل الداخلي، ومساعد Claude' as result;
