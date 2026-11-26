-- =====================================================================
--  تراجع الترحيل 37 (ضمانات العقد وتأميناته، وأوامر التغيير ببنودها واعتمادها، ولجنة الاستلام):
--  يعيد الدوال والقيود كما كانت بعد الترحيل 36، والنسبتين الافتراضيتين (الابتدائي 5% والنهائي 2%)، فتعود مبالغ
--  الضمانات كما كانت قبل التصحيح (تُطابَق بالنسخة الاحتياطية ثم تُحذف النسخة)، ويحذف الجداول والأعمدة الجديدة.
--  يرفض التراجع إن وُجدت بيانات أُدخلت بعد الترحيل حتى لا تُفقد: أوامر تغيير في مسودة أو مرفوضة أو ببنود، أو لجان
--  استلام، أو ضمانات أو تأمينات حُدّدت لعقد بعده، أو نسبتان افتراضيتان غُيّرتا بعده.
--  يُشغَّل يدوياً عند الحاجة فقط، ويُختبر في supabase/tests/run_tests.sh.
-- =====================================================================
do $$
declare
  v text;
begin
  v := concat_ws('، ',
    case when exists (select 1 from public.contract_variations where status <> 'approved')
           or exists (select 1 from public.contract_variation_items) then 'أوامر تغيير بعد الترحيل' end,
    case when exists (select 1 from public.contract_committees) then 'لجان استلام' end,
    case when exists (select 1 from public.projects
                       where guarantee_final_na or not retention_deduct
                          or guarantee_initial_rate is distinct from 0.02 or guarantee_final_rate is distinct from 0.05
                          or retention_rate is distinct from public.setting_num('finance.retention_rate', 0))
         then 'ضمانات أو تأمينات حُدّدت لعقد' end,
    case when public.setting_num('finance.guarantee_initial_rate', 0.02) <> 0.02
           or public.setting_num('finance.guarantee_final_rate', 0.05) <> 0.05 then 'نسبتا ضمان افتراضيتان غُيّرتا' end);
  if v <> '' then
    raise exception 'لا يُتراجع عن الترحيل 37: في المنظومة %', v using errcode = 'P0001';
  end if;
end $$;

-- الحساب والدوال كما كانت
CREATE OR REPLACE FUNCTION public.projects_finance_calc()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if tg_op = 'UPDATE' and current_setting('app.trusted', true) is distinct from 'on' then
    new.value_source      := old.value_source;
    new.executed_source   := old.executed_source;
    new.variations_net    := old.variations_net;
    new.extracts_count    := old.extracts_count;
    new.extracts_gross    := old.extracts_gross;
    new.extracts_net      := old.extracts_net;
    new.extracts_paid     := old.extracts_paid;
    new.retention_held    := old.retention_held;
    new.advance_amount    := old.advance_amount;
    new.advance_paid_on   := old.advance_paid_on;
    new.advance_recovered := old.advance_recovered;
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
    new.guarantee_initial := round(new.executed_value * public.setting_num('finance.guarantee_initial_rate', 0.05), 3);
  end if;
  new.guarantee_final := round(new.executed_value * public.setting_num('finance.guarantee_final_rate', 0.02), 3);
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
$function$

;

CREATE OR REPLACE FUNCTION public.recalc_contract_finance(p_project uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_cv   numeric; n_cv integer;
  v_ev   numeric; n_ev integer;
  v_var  numeric;
  n_ext  integer;
  v_eg   numeric; v_en numeric; v_paid numeric; v_ret numeric; v_adv numeric;
  v_trusted text := coalesce(current_setting('app.trusted', true), '');
  v_recalc  text := coalesce(current_setting('app.recalc', true), '');
begin
  if p_project is null then
    return;
  end if;
  select sum(contract_value), count(contract_value), sum(executed_value), count(executed_value)
    into v_cv, n_cv, v_ev, n_ev
    from public.contract_works where project_id = p_project;
  select coalesce(sum(case when kind = 'add' then amount else -amount end), 0)
    into v_var from public.contract_variations where project_id = p_project;
  select count(*), coalesce(sum(gross_amount), 0), coalesce(sum(net_amount), 0),
         coalesce(sum(paid_amount), 0), coalesce(sum(retention), 0), coalesce(sum(advance_recovery), 0)
    into n_ext, v_eg, v_en, v_paid, v_ret, v_adv
    from public.contract_extracts where project_id = p_project and status in ('approved', 'referred', 'paid');

  perform set_config('app.trusted', 'on', true);
  perform set_config('app.recalc', 'on', true);
  update public.projects set
    value_source      = case when n_cv > 0 then 'items' else 'manual' end,
    contract_value    = case when n_cv > 0 then v_cv else contract_value end,
    executed_source   = case when n_ext > 0 then 'extracts' when n_ev > 0 then 'items' else 'manual' end,
    executed_value    = case when n_ext > 0 then v_eg when n_ev > 0 then v_ev else executed_value end,
    variations_net    = v_var,
    extracts_count    = n_ext,
    extracts_gross    = v_eg,
    extracts_net      = v_en,
    extracts_paid     = v_paid,
    retention_held    = v_ret,
    advance_recovered = v_adv
   where id = p_project
     and (value_source, contract_value, executed_source, executed_value, variations_net, extracts_count,
          extracts_gross, extracts_net, extracts_paid, retention_held, advance_recovered)
         is distinct from
         (case when n_cv > 0 then 'items' else 'manual' end,
          case when n_cv > 0 then v_cv else contract_value end,
          case when n_ext > 0 then 'extracts' when n_ev > 0 then 'items' else 'manual' end,
          case when n_ext > 0 then v_eg when n_ev > 0 then v_ev else executed_value end,
          v_var, n_ext, v_eg, v_en, v_paid, v_ret, v_adv);
  perform set_config('app.trusted', v_trusted, true);
  perform set_config('app.recalc', v_recalc, true);
end;
$function$

;

CREATE OR REPLACE FUNCTION public.delete_variation(p_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
  if v.origin_project is not null and v.origin_project <> v.project_id then
    raise exception 'أمر التغيير هذا دُمج من عقد آخر؛ افصله بفك الدمج بدل حذفه' using errcode = 'P0001';
  end if;
  delete from public.contract_variations where id = p_id;
  perform public.write_audit('finance.variation_delete', v.project_id, null, jsonb_build_object(
    'variation_id', v.id, 'title', v.title, 'kind', v.kind, 'amount', v.amount));
end;
$function$

;

drop trigger if exists contract_extracts_retention_guard on public.contract_extracts;
drop trigger if exists contract_variations_values on public.contract_variations;
drop trigger if exists projects_committees_follow_merge on public.projects;
drop function if exists public.contract_extracts_retention_guard();
drop function if exists public.contract_variations_values();
drop function if exists public.committees_follow_merge();
drop function if exists public.set_contract_guarantees(uuid, jsonb);
drop function if exists public.save_contract_variation(uuid, jsonb);
drop function if exists public.decide_variation(uuid, text, text, date);
drop function if exists public.can_approve_variation(uuid);
drop function if exists public.variation_snapshot(uuid);
drop function if exists public.save_committee(uuid, text, jsonb);
drop function if exists public.delete_committee(uuid, text);
drop function if exists public.committee_snapshot(uuid);
drop table if exists public.contract_committee_members;
drop table if exists public.contract_committees;
drop table if exists public.contract_variation_events;
drop table if exists public.contract_variation_items;

-- أوامر التغيير: القيد القديم (القيمة أكبر من صفر) دون الحالة والقيمتين
alter table public.contract_variations drop constraint if exists contract_variations_values_chk;
alter table public.contract_variations drop constraint if exists contract_variations_status_chk;
drop index if exists public.contract_variations_decided_by_idx;
drop index if exists public.contract_variations_updated_by_idx;
alter table public.contract_variations
  drop column if exists status,
  drop column if exists added_value,
  drop column if exists deducted_value,
  drop column if exists decided_by,
  drop column if exists decided_at,
  drop column if exists decision_note,
  drop column if exists updated_at,
  drop column if exists updated_by;
do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'contract_variations_amount_check') then
    alter table public.contract_variations add constraint contract_variations_amount_check check (amount > (0)::numeric);
  end if;
end $$;

-- النسبتان الافتراضيتان كما كانتا، ثم أعمدة العقد
do $$
begin
  if (select value from public.app_settings where key = 'finance.guarantee_initial_rate') = '0.02'::jsonb then
    update public.app_settings set value = '0.05', updated_at = now() where key = 'finance.guarantee_initial_rate';
    perform public.write_audit('setting.update', null, null,
      jsonb_build_object('key', 'finance.guarantee_initial_rate', 'from', 0.02, 'to', 0.05, 'source', 'rollback_37'),
      'finance.guarantee_initial_rate');
  end if;
  if (select value from public.app_settings where key = 'finance.guarantee_final_rate') = '0.05'::jsonb then
    update public.app_settings set value = '0.02', updated_at = now() where key = 'finance.guarantee_final_rate';
    perform public.write_audit('setting.update', null, null,
      jsonb_build_object('key', 'finance.guarantee_final_rate', 'from', 0.05, 'to', 0.02, 'source', 'rollback_37'),
      'finance.guarantee_final_rate');
  end if;
end $$;
alter table public.projects drop constraint if exists projects_guarantee_rates_chk;
alter table public.projects
  drop column if exists guarantee_initial_rate,
  drop column if exists guarantee_final_rate,
  drop column if exists guarantee_final_na,
  drop column if exists retention_deduct,
  drop column if exists retention_rate,
  drop column if exists variations_add,
  drop column if exists variations_deduct,
  drop column if exists extracts_submitted;

-- إعادة حساب الضمانات بالنسبتين السابقتين والمجاميع، ومطابقتها بالنسخة الاحتياطية ثم حذفها
do $$
declare
  r     record;
  v_was text := coalesce(current_setting('app.trusted', true), '');
  n     integer;
begin
  perform set_config('app.trusted', 'on', true);
  update public.projects set executed_value = executed_value;
  perform set_config('app.trusted', v_was, true);
  for r in select id from public.projects loop
    perform public.recalc_contract_finance(r.id);
  end loop;
  if to_regclass('backup.m37_projects_guarantees') is not null then
    execute $q$select count(*) from backup.m37_projects_guarantees b join public.projects p on p.id = b.project_id
               where p.executed_value is not distinct from b.executed_value
                 and (p.guarantee_initial is distinct from b.guarantee_initial or p.guarantee_final is distinct from b.guarantee_final)$q$
       into n;
    if n > 0 then
      raise exception 'التراجع عن الترحيل 37: % عقداً لا تطابق ضماناته النسخة الاحتياطية', n using errcode = 'P0001';
    end if;
    execute 'drop table backup.m37_projects_guarantees';
  end if;
  if exists (select 1 from pg_namespace where nspname = 'backup')
     and not exists (select 1 from pg_class c join pg_namespace s on s.oid = c.relnamespace where s.nspname = 'backup') then
    execute 'drop schema backup';
  end if;
end $$;

grant execute on function public.save_variation(uuid, uuid, uuid, text, text, text, numeric, date, text) to authenticated;
