-- =====================================================================
--  الترحيل 31: ترجمة تنفيذ البرنامج الزمني المعتمد تلقائياً إلى سجل المخاطر وتحليل SWOT
--   pm_sync_auto(عقد): يحسب كل بند (عدا «لا ينطبق») في تاريخ الإسناد بمعادلات الفصل 29 وحدود pm.config، ثم:
--     • خطر زمني لكل بند متأخر أو متجاوز لنهايته (المفتاح pm_item:<البند>): الاحتمالية 5 للمتجاوز و4 للحرج و3 للبسيط،
--       والتأثير من نصيب البند من الوزن (≥20% = 5، ≥10% = 4، ≥5% = 3، وإلا 2)، والأثر الزمني = أيام التأخر.
--       يُغلق تلقائياً حين يتعافى البند، ويُعاد فتحه إن تأخر من جديد، ولا يُمَسّ ما عدّله المستخدم من الوصف والإجراء والمالك،
--       ولا يُعاد فتح ما أغلقه المستخدم ما دام البند متأخراً.
--     • خطر للعقد كله إن تأخر إنجازه الكلي (pm_plan:<العقد>).
--     • عوامل SWOT للعقد: ضعف (W) إن تأخر، وتهديد (T) إن توقع تجاوز نهاية البرنامج بـ alert_days فأكثر،
--       وقوة (S) إن تقدم، وفرصة (O) إن توقع الإنهاء قبل الموعد بـ alert_days فأكثر، بأثرها الإيجابي أو السلبي بالأيام.
--       يُحذف العامل حين يزول سببه ما لم تستند إليه استراتيجية.
--   pm_refresh_auto(): يعيد الترجمة لكل البرامج المعتمدة مرة في الساعة على الأكثر (تاريخ الإسناد يتقدم كل يوم).
--  يُشغَّل بعد 20261122000030_plans_supervision.sql. إعادة تشغيله آمنة.
-- =====================================================================

alter table public.risks add column if not exists auto_key text;
alter table public.risks add column if not exists auto_active boolean;
create unique index if not exists risks_auto_key_idx on public.risks (auto_key) where auto_key is not null;

alter table public.swot_factors add column if not exists auto_key text;
alter table public.swot_factors add column if not exists project_id uuid references public.projects (id) on delete cascade;
create unique index if not exists swot_factors_auto_key_idx on public.swot_factors (auto_key) where auto_key is not null;
create index if not exists swot_factors_project_idx on public.swot_factors (project_id);

create table if not exists public.pm_auto_runs (
  id     integer primary key default 1 check (id = 1),
  ran_at timestamptz not null default now()
);
alter table public.pm_auto_runs enable row level security;
revoke all on public.pm_auto_runs from anon, authenticated;
grant all on public.pm_auto_runs to service_role;

-- ---------------------------------------------------------------------
-- حساب بنود العقد في تاريخ الإسناد (المعادلات نفسها في lib/schedule.dart)
-- ---------------------------------------------------------------------
create or replace function public.pm_item_calcs(p_project uuid)
returns table (id uuid, title text, share numeric, d integer, e integer, planned numeric, actual numeric,
               status text, overdue integer, behind integer, forecast_end date, planned_end date)
language sql stable security definer set search_path = public
as $$
  with cfg as (
    select coalesce(nullif(c ->> 'ref_date', '')::date, current_date) as ref,
           coalesce((c ->> 'spi_ahead')::numeric, 1.05) as sa,
           coalesce((c ->> 'spi_ok')::numeric, 0.95) as so,
           coalesce((c ->> 'spi_warn')::numeric, 0.85) as sw
      from (select coalesce(public.setting('pm.config'), '{}'::jsonb) as c) x
  ), its as (
    select i.*, greatest(1, i.planned_end - i.planned_start) as dd
      from public.pm_items i where i.project_id = p_project and not i.not_applicable
  ), w as (
    select its.*, case when coalesce(its.weight, 0) > 0 then its.weight
                       else coalesce((select avg(weight) from its x where coalesce(x.weight, 0) > 0), 1) end as ew
      from its
  ), c as (
    select w.*, cfg.*, least(greatest(cfg.ref - w.planned_start, 0), w.dd) as ee from w, cfg
  ), c2 as (
    select c.*, c.ee::numeric / c.dd * 100 as pp, c.progress as aa from c
  )
  select c2.id, c2.title,
         c2.ew / nullif(sum(c2.ew) over (), 0) * 100,
         c2.dd, c2.ee, c2.pp, c2.aa,
         case when c2.aa >= 100 then 'done'
              when c2.pp = 0 then case when c2.aa > 0 then 'ahead' else 'not_started' end
              when c2.aa / c2.pp >= c2.sa then 'ahead'
              when c2.aa / c2.pp >= c2.so then 'on_track'
              when c2.aa / c2.pp >= c2.sw then 'slight'
              else 'critical' end,
         case when c2.aa < 100 and c2.ref > c2.planned_end then c2.ref - c2.planned_end end,
         greatest(round(c2.ee - c2.aa / 100 * c2.dd)::integer,
                  case when c2.aa < 100 and c2.ref > c2.planned_end then c2.ref - c2.planned_end else 0 end, 0),
         case when c2.aa >= 100 then coalesce(c2.actual_end, least(c2.planned_end, c2.ref))
              when c2.aa > 0 and c2.ee > 0 then c2.ref + ceil((100 - c2.aa) / (c2.aa / c2.ee))::integer
              when c2.ee > 0 then c2.ref + c2.dd
              else c2.planned_end end,
         c2.planned_end
    from c2
$$;

-- ---------------------------------------------------------------------
-- الترجمة إلى المخاطر وSWOT لعقد واحد
-- ---------------------------------------------------------------------
create or replace function public.pm_sync_auto(p_project uuid)
returns jsonb
language plpgsql security definer set search_path = public
as $$
declare
  pl       public.pm_plans;
  v_label  text;
  v_dept   text;
  cfg      jsonb := coalesce(public.setting('pm.config'), '{}'::jsonb);
  v_ref    date := coalesce(nullif(cfg ->> 'ref_date', '')::date, current_date);
  v_alert  integer := coalesce((cfg ->> 'alert_days')::integer, 7);
  v_sa     numeric := coalesce((cfg ->> 'spi_ahead')::numeric, 1.05);
  v_so     numeric := coalesce((cfg ->> 'spi_ok')::numeric, 0.95);
  v_sw     numeric := coalesce((cfg ->> 'spi_warn')::numeric, 0.85);
  r        record;
  rk       public.risks;
  v_key    text;
  v_late   boolean;
  v_prob   smallint;
  v_imp    smallint;
  v_code   text;
  v_eff    text;
  v_opened integer := 0;
  v_closed integer := 0;
  v_upd    integer := 0;
  v_act    numeric;
  v_pln    numeric;
  v_perf   text;
  v_total  integer;
  v_pend   date;
  v_fend   date;
  v_fdelay integer;
  v_pdays  integer;
  v_want   jsonb := '{}'::jsonb;
  k        text;
  f        public.swot_factors;
  v_sw_add integer := 0;
  v_sw_del integer := 0;
begin
  select * into pl from public.pm_plans where project_id = p_project;
  -- لا ترجمة إلا لبرنامج معتمد؛ وإن أُعيد فتحه تُغلق مخاطره وتُحذف عوامله إلى أن يُعتمد
  v_label := left(coalesce(public.project_label(p_project), ''), 120);
  select left(d.name, 60) into v_dept from public.projects p join public.departments d on d.key = p.department where p.id = p_project;
  v_dept := coalesce(v_dept, '');

  -- 1. مخاطر البنود
  for r in select c.* from public.pm_item_calcs(p_project) c where pl.status = 'approved' loop
    v_key := 'pm_item:' || r.id;
    v_late := r.status in ('slight', 'critical') or r.overdue is not null;
    v_prob := case when r.overdue is not null then 5 when r.status = 'critical' then 4 else 3 end;
    v_imp := case when r.share >= 20 then 5 when r.share >= 10 then 4 when r.share >= 5 then 3 else 2 end;
    v_eff := left(format('الإنجاز %s%% مقابل %s%% مخطط حتى %s (%s)، ونصيبه %s%% من وزن العقد',
                         round(r.actual, 1), round(r.planned, 1), to_char(v_ref, 'YYYY/MM/DD'),
                         case when r.overdue is not null then 'تجاوز نهايته المخططة ' || to_char(r.planned_end, 'YYYY/MM/DD') || ' بـ' || r.overdue || ' يوماً'
                              else 'متأخر نحو ' || r.behind || ' يوماً' end,
                         round(r.share, 1)), 500);
    select * into rk from public.risks where auto_key = v_key for update;
    if v_late then
      if not found then
        select 'R' || lpad((coalesce(max(substring(code from 2)::integer), 0) + 1)::text, 2, '0') into v_code
          from public.risks where code ~ '^R[0-9]+$';
        insert into public.risks (code, project_id, phase, category, description, cause, effect, probability, impact, response,
                                  owner, status, department, time_impact_days, early_warning, notes, auto_key, auto_active,
                                  created_by, updated_by)
        values (v_code, p_project, 'التنفيذ', 'زمني', left(format('تأخر البند «%s» عن البرنامج الزمني المعتمد — %s', r.title, v_label), 300),
                'تقدم تنفيذ البند أبطأ من مدته المخططة', v_eff, v_prob, v_imp, 'mitigate', 'الإشراف', 'open', v_dept,
                least(r.behind, 3650), 'SPI البند دون الحد المقبول في البرنامج الزمني',
                'سُجّل تلقائياً من متابعة البرنامج الزمني', v_key, true, auth.uid(), auth.uid());
        v_opened := v_opened + 1;
      else
        update public.risks set
          effect = v_eff, probability = v_prob, impact = v_imp, time_impact_days = least(r.behind, 3650),
          status = case when status = 'closed' and auto_active is false then 'open' else status end,
          closed_on = case when status = 'closed' and auto_active is false then null else closed_on end,
          auto_active = true,
          updated_at = case when (effect, probability, impact, time_impact_days, auto_active)
                                 is distinct from (v_eff, v_prob, v_imp, least(r.behind, 3650), true) then now() else updated_at end
        where id = rk.id
          and ((effect, probability, impact, time_impact_days, auto_active) is distinct from (v_eff, v_prob, v_imp, least(r.behind, 3650), true)
               or (status = 'closed' and auto_active is false));
        if found then
          v_upd := v_upd + 1;
          if rk.status = 'closed' and rk.auto_active is false then
            v_opened := v_opened + 1;
          end if;
        end if;
      end if;
    elsif found and rk.auto_active then
      update public.risks set
        auto_active = false, effect = v_eff,
        status = 'closed', closed_on = coalesce(closed_on, current_date),
        notes = left(case when notes like '%تعافى البند%' then notes else notes || ' · تعافى البند وأُغلق الخطر تلقائياً' end, 1000),
        updated_at = now()
      where id = rk.id;
      v_closed := v_closed + 1;
    end if;
  end loop;

  -- مخاطر بنود حُذفت أو صارت «لا ينطبق» أو أُعيد فتح برنامجها
  for rk in select * from public.risks
             where auto_key like 'pm_item:%' and project_id = p_project and auto_active
               and (pl.status is distinct from 'approved'
                    or not exists (select 1 from public.pm_items i where 'pm_item:' || i.id = auto_key and not i.not_applicable)) loop
    update public.risks set auto_active = false, status = 'closed', closed_on = coalesce(closed_on, current_date), updated_at = now()
     where id = rk.id;
    v_closed := v_closed + 1;
  end loop;

  -- 2. العقد كله
  if pl.status = 'approved' then
    select sum(c.share * c.actual) / nullif(sum(c.share), 0), sum(c.share * c.planned) / nullif(sum(c.share), 0),
           max(c.planned_end), max(c.forecast_end)
      into v_act, v_pln, v_pend, v_fend
      from public.pm_item_calcs(p_project) c;
    v_total := greatest(1, coalesce(v_pend - pl.start_date, 1));
    v_perf := case when v_act is null then 'no_data'
                   when v_act >= 100 then 'done'
                   when v_pln = 0 then case when v_act > 0 then 'ahead' else 'not_started' end
                   when v_act / v_pln >= v_sa then 'ahead'
                   when v_act / v_pln >= v_so then 'on_track'
                   when v_act / v_pln >= v_sw then 'slight'
                   else 'critical' end;
    v_pdays := round((coalesce(v_act, 0) - coalesce(v_pln, 0)) / 100 * v_total)::integer;   -- موجب = متقدم
    v_fdelay := case when v_perf = 'done' or v_fend is null or v_pend is null then null else v_fend - v_pend end;

    v_key := 'pm_plan:' || p_project;
    v_eff := left(format('الإنجاز الكلي الموزون %s%% مقابل %s%% مخطط حتى %s (فارق يعادل %s يوماً من مدة البرنامج)%s',
                         round(coalesce(v_act, 0), 1), round(coalesce(v_pln, 0), 1), to_char(v_ref, 'YYYY/MM/DD'), greatest(-v_pdays, 0),
                         case when coalesce(v_fdelay, 0) > 0 then '، والإنهاء المتوقع ' || to_char(v_fend, 'YYYY/MM/DD') || ' بعد نهاية البرنامج بـ' || v_fdelay || ' يوماً' else '' end), 500);
    select * into rk from public.risks where auto_key = v_key for update;
    if v_perf in ('slight', 'critical') then
      v_prob := case when v_perf = 'critical' then 4 else 3 end;
      v_imp := case when coalesce(v_fdelay, 0) >= 30 or v_perf = 'critical' then 5 else 4 end;
      if not found then
        select 'R' || lpad((coalesce(max(substring(code from 2)::integer), 0) + 1)::text, 2, '0') into v_code
          from public.risks where code ~ '^R[0-9]+$';
        insert into public.risks (code, project_id, phase, category, description, cause, effect, probability, impact, response,
                                  owner, status, department, time_impact_days, early_warning, notes, auto_key, auto_active,
                                  created_by, updated_by)
        values (v_code, p_project, 'التنفيذ', 'زمني', left(format('تأخر تنفيذ العقد عن برنامجه الزمني المعتمد — %s', v_label), 300),
                'الإنجاز الكلي الموزون دون المخطط', v_eff, v_prob, v_imp, 'mitigate', 'الإشراف', 'open', v_dept,
                least(greatest(-v_pdays, coalesce(v_fdelay, 0), 0), 3650), 'SPI العقد دون الحد المقبول',
                'سُجّل تلقائياً من متابعة البرنامج الزمني', v_key, true, auth.uid(), auth.uid());
        v_opened := v_opened + 1;
      else
        update public.risks set
          effect = v_eff, probability = v_prob, impact = v_imp,
          time_impact_days = least(greatest(-v_pdays, coalesce(v_fdelay, 0), 0), 3650),
          status = case when status = 'closed' and auto_active is false then 'open' else status end,
          closed_on = case when status = 'closed' and auto_active is false then null else closed_on end,
          auto_active = true, updated_at = now()
        where id = rk.id
          and ((effect, probability, impact, auto_active) is distinct from (v_eff, v_prob, v_imp, true)
               or (status = 'closed' and auto_active is false));
        if found then
          v_upd := v_upd + 1;
          if rk.status = 'closed' and rk.auto_active is false then
            v_opened := v_opened + 1;
          end if;
        end if;
      end if;
    elsif found and rk.auto_active then
      update public.risks set auto_active = false, effect = v_eff, status = 'closed', closed_on = coalesce(closed_on, current_date),
                              updated_at = now()
       where id = rk.id;
      v_closed := v_closed + 1;
    end if;

    -- 3. عوامل SWOT المطلوبة الآن
    if v_perf in ('slight', 'critical') then
      v_want := v_want || jsonb_build_object('W', jsonb_build_object(
        'factor', left(format('تأخر تنفيذ «%s» عن برنامجه الزمني', v_label), 300),
        'impact', left(format('سلبي: متأخر بما يعادل %s يوماً (الإنجاز %s%% مقابل %s%% مخطط)', greatest(-v_pdays, 0), round(v_act, 1), round(v_pln, 1)), 300),
        'importance', case when v_perf = 'critical' then 5 else 4 end, 'urgency', case when v_perf = 'critical' then 5 else 3 end));
    elsif v_perf = 'ahead' then
      v_want := v_want || jsonb_build_object('S', jsonb_build_object(
        'factor', left(format('تقدم تنفيذ «%s» على برنامجه الزمني', v_label), 300),
        'impact', left(format('إيجابي: متقدم بما يعادل %s يوماً (الإنجاز %s%% مقابل %s%% مخطط)', greatest(v_pdays, 0), round(v_act, 1), round(v_pln, 1)), 300),
        'importance', 3, 'urgency', 2));
    end if;
    if coalesce(v_fdelay, 0) >= v_alert then
      v_want := v_want || jsonb_build_object('T', jsonb_build_object(
        'factor', left(format('توقع تجاوز «%s» نهاية برنامجه الزمني', v_label), 300),
        'impact', left(format('سلبي: إنهاء متوقع %s بعد نهاية البرنامج %s بـ%s يوماً', to_char(v_fend, 'YYYY/MM/DD'), to_char(v_pend, 'YYYY/MM/DD'), v_fdelay), 300),
        'importance', case when v_fdelay >= 30 then 5 else 4 end, 'urgency', case when v_fdelay >= 30 then 4 else 3 end));
    elsif coalesce(-v_fdelay, 0) >= v_alert then
      v_want := v_want || jsonb_build_object('O', jsonb_build_object(
        'factor', left(format('فرصة إنهاء «%s» قبل موعده', v_label), 300),
        'impact', left(format('إيجابي: إنهاء متوقع %s قبل نهاية البرنامج %s بـ%s يوماً', to_char(v_fend, 'YYYY/MM/DD'), to_char(v_pend, 'YYYY/MM/DD'), -v_fdelay), 300),
        'importance', 3, 'urgency', 2));
    end if;
  end if;

  foreach k in array array['S', 'W', 'O', 'T'] loop
    v_key := 'pm_plan:' || p_project || ':' || k;
    select * into f from public.swot_factors where auto_key = v_key for update;
    if v_want ? k then
      if not found then
        select k || n into v_code from generate_series(901, 999) n
         where not exists (select 1 from public.swot_factors where code = k || n) order by n limit 1;
        if v_code is not null then
          insert into public.swot_factors (code, kind, factor, impact, department, importance, urgency, evidence, source, sort,
                                           auto_key, project_id, updated_by)
          values (v_code, k, v_want -> k ->> 'factor', v_want -> k ->> 'impact', v_dept,
                  (v_want -> k ->> 'importance')::smallint, (v_want -> k ->> 'urgency')::smallint,
                  left('البرنامج الزمني المعتمد للعقد، تاريخ الإسناد ' || to_char(v_ref, 'YYYY/MM/DD'), 300),
                  'البرنامج الزمني', 900, v_key, p_project, auth.uid());
          v_sw_add := v_sw_add + 1;
        end if;
      elsif (f.impact, f.importance, f.urgency) is distinct from
            (v_want -> k ->> 'impact', (v_want -> k ->> 'importance')::smallint, (v_want -> k ->> 'urgency')::smallint) then
        update public.swot_factors set impact = v_want -> k ->> 'impact',
               importance = (v_want -> k ->> 'importance')::smallint, urgency = (v_want -> k ->> 'urgency')::smallint,
               evidence = left('البرنامج الزمني المعتمد للعقد، تاريخ الإسناد ' || to_char(v_ref, 'YYYY/MM/DD'), 300),
               updated_at = now()
         where id = f.id;
      end if;
    elsif found and not exists (select 1 from public.swot_strategies s
                                 where f.code = any (s.internal_factors) or f.code = any (s.external_factors)) then
      delete from public.swot_factors where id = f.id;
      v_sw_del := v_sw_del + 1;
    end if;
  end loop;

  if v_opened + v_closed > 0 then
    perform public.write_audit('risk.auto', p_project, null,
      jsonb_build_object('opened', v_opened, 'closed', v_closed, 'ref_date', v_ref));
  end if;
  if v_sw_add + v_sw_del > 0 then
    perform public.write_audit('swot.auto', p_project, null,
      jsonb_build_object('added', v_sw_add, 'removed', v_sw_del, 'ref_date', v_ref));
  end if;
  return jsonb_build_object('opened', v_opened, 'closed', v_closed, 'updated', v_upd, 'swot_added', v_sw_add, 'swot_removed', v_sw_del,
                            'perf', v_perf);
end;
$$;

-- يُستدعى عند فتح التطبيق: كل البرامج المعتمدة مرة في الساعة على الأكثر
create or replace function public.pm_refresh_auto()
returns integer
language plpgsql security definer set search_path = public
as $$
declare
  v_last timestamptz;
  n      integer := 0;
  p      uuid;
begin
  if not public.is_member() then
    raise exception 'غير مصرح' using errcode = '42501';
  end if;
  select ran_at into v_last from public.pm_auto_runs where id = 1 for update;
  if v_last is not null and v_last > now() - interval '1 hour' then
    return 0;
  end if;
  insert into public.pm_auto_runs (id, ran_at) values (1, now()) on conflict (id) do update set ran_at = excluded.ran_at;
  for p in select pl.project_id from public.pm_plans pl join public.projects pr on pr.id = pl.project_id
            where pl.status = 'approved' and pr.merged_into is null loop
    perform public.pm_sync_auto(p);
    n := n + 1;
  end loop;
  return n;
end;
$$;

revoke execute on function public.pm_item_calcs(uuid), public.pm_sync_auto(uuid) from public, anon, authenticated;
revoke execute on function public.pm_refresh_auto() from public, anon;
grant execute on function public.pm_refresh_auto() to authenticated;

-- البرامج المعتمدة الموجودة: ترجمتها الآن
do $$
declare
  p uuid;
begin
  for p in select project_id from public.pm_plans where status = 'approved' loop
    perform public.pm_sync_auto(p);
  end loop;
end $$;
