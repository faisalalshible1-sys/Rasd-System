-- =====================================================================
--  مرحلة التعاقد: نموذج «المقايسة التقديرية»، والبيانات المالية للعقد
--  (قيمة التعاقد، الدفعات الثلاث، الضمانان الابتدائي والنهائي، الخصومات).
--  يُشغَّل مرة واحدة بعد الملفات السابقة، وإعادة تشغيله آمنة.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. نموذج «المقايسة التقديرية» بعد «أمر تعاقد» مباشرة
--    بالحالات نفسها (مكتمل، قيد الإجراء، لم يتم، لا ينطبق)،
--    وبالاختصاص والحساسية نفسيهما المضبوطين حالياً على «أمر تعاقد».
-- ---------------------------------------------------------------------
do $$
begin
  if not exists (select 1 from public.form_defs where key = 'f19') then
    -- ترتيب النماذج ثابت من التطبيق؛ يُفتح هنا مؤقتاً لإفساح المكان للنموذج الجديد
    alter table public.form_defs disable trigger form_defs_guard;
    update public.form_defs set sort = sort + 100 where sort >= 2;
    update public.form_defs set sort = sort - 99 where sort >= 102;
    insert into public.form_defs (key, name, stage, sort, sensitive, responsible, engineer_field)
    select 'f19', 'المقايسة التقديرية', 0, 2, sensitive, responsible, null
    from public.form_defs where key = 'f01';
    alter table public.form_defs enable trigger form_defs_guard;
  end if;
end $$;

-- ---------------------------------------------------------------------
-- 2. البيانات المالية للعقد (بالدينار الليبي، ثلاث خانات عشرية)
--    الضمان الابتدائي 5% والضمان النهائي 2% من قيمة التعاقد، يُحسبان تلقائياً.
-- ---------------------------------------------------------------------
alter table public.projects
  add column if not exists contract_value    numeric(16, 3) check (contract_value >= 0),
  add column if not exists payment_first     numeric(16, 3) check (payment_first >= 0),
  add column if not exists payment_second    numeric(16, 3) check (payment_second >= 0),
  add column if not exists payment_final     numeric(16, 3) check (payment_final >= 0),
  add column if not exists deductions        numeric(16, 3) check (deductions >= 0),
  add column if not exists guarantee_initial numeric(16, 3) generated always as (round(contract_value * 0.05, 3)) stored,
  add column if not exists guarantee_final   numeric(16, 3) generated always as (round(contract_value * 0.02, 3)) stored;

-- من يحدّث «أمر تعاقد» في المشروع هو من يحدّث بياناته المالية (والمدير دائماً).
-- يسري على التعديل المباشر في الجدول أيضاً، فلا يُتجاوز من أي نسخة من التطبيق.
create or replace function public.projects_finance_guard()
returns trigger
language plpgsql security definer set search_path = public
as $$
begin
  if current_setting('app.seeding', true) = 'on' or auth.uid() is null then
    return new;  -- الاستيراد ومحرر SQL
  end if;
  if tg_op = 'INSERT' then
    if coalesce(new.contract_value, new.payment_first, new.payment_second, new.payment_final, new.deductions) is not null
       and not public.is_director() then
      raise exception 'تُدخل البيانات المالية بعد إنشاء المشروع' using errcode = '42501';
    end if;
  elsif (old.contract_value, old.payment_first, old.payment_second, old.payment_final, old.deductions)
        is distinct from
        (new.contract_value, new.payment_first, new.payment_second, new.payment_final, new.deductions)
        and not public.can_edit_form(new.id, 'f01') then
    raise exception 'البيانات المالية للعقد يحدّثها من يختص بـ«أمر تعاقد»' using errcode = '42501';
  end if;
  return new;
end;
$$;
drop trigger if exists projects_finance_guard on public.projects;
create trigger projects_finance_guard
  before insert or update on public.projects
  for each row execute function public.projects_finance_guard();

-- حفظ البيانات المالية من التطبيق (يستخدمه كذلك مكتب العقود الذي لا يعدّل بقية بيانات المشروع)
create or replace function public.set_contract_finance(
  p_project uuid, p_contract_value numeric, p_payment_first numeric, p_payment_second numeric,
  p_payment_final numeric, p_deductions numeric)
returns void
language plpgsql security definer set search_path = public
as $$
begin
  if not public.can_edit_form(p_project, 'f01') then
    raise exception 'البيانات المالية للعقد يحدّثها من يختص بـ«أمر تعاقد»' using errcode = '42501';
  end if;
  if least(p_contract_value, p_payment_first, p_payment_second, p_payment_final, p_deductions) < 0 then
    raise exception 'القيم المالية لا تكون سالبة' using errcode = '22023';
  end if;
  update public.projects
     set contract_value = p_contract_value,
         payment_first  = p_payment_first,
         payment_second = p_payment_second,
         payment_final  = p_payment_final,
         deductions     = p_deductions
   where id = p_project;
end;
$$;

-- تدقيق تغييرات المشاريع، مع البيانات المالية
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
  if current_setting('app.seeding', true) = 'on' then
    return null;
  end if;
  if tg_op = 'INSERT' then
    perform public.write_audit('project.create', new.id, null,
      jsonb_build_object('assign_no', new.assign_no, 'name', new.name, 'owner', new.owner, 'company', new.company));
  elsif tg_op = 'DELETE' then
    perform public.write_audit('project.delete', old.id, null,
      jsonb_build_object('assign_no', old.assign_no, 'name', old.name),
      btrim(coalesce(old.assign_no, '') || ' ' || old.name));
  else
    o := to_jsonb(old); n := to_jsonb(new);
    foreach col in array array['assign_no', 'code', 'name', 'owner', 'company', 'department', 'notes',
                               'eng_sup', 'eng_qty', 'eng_fol', 'eng_saf',
                               'contract_value', 'payment_first', 'payment_second', 'payment_final', 'deductions'] loop
      if o -> col is distinct from n -> col then
        changes := changes || jsonb_build_object(col, jsonb_build_object('from', o -> col, 'to', n -> col));
      end if;
    end loop;
    if changes <> '{}'::jsonb then
      perform public.write_audit('project.update', new.id, null, changes);
    end if;
  end if;
  return null;
end;
$$;

-- الصلاحيات: الدالة الجديدة للمستخدمين المسجلين فقط، ودالة الحماية لا تُستدعى مباشرة
revoke execute on function public.projects_finance_guard() from public, anon, authenticated;
revoke execute on function public.projects_audit() from public, anon, authenticated;
revoke execute on function public.set_contract_finance(uuid, numeric, numeric, numeric, numeric, numeric) from public, anon;
grant execute on function public.set_contract_finance(uuid, numeric, numeric, numeric, numeric, numeric) to authenticated;

-- تحديث واجهة البيانات (PostgREST) لتظهر الأعمدة والدالة الجديدة فوراً
notify pgrst, 'reload schema';

select 'تم: أُضيف نموذج «المقايسة التقديرية» والبيانات المالية للعقد' as result;
