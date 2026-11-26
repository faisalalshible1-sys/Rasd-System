-- =====================================================================
--  تراجع الترحيل 36 (البرنامج الزمني من المقايسة): يعيد الدوال والقيود كما كانت بعد الترحيل 35،
--  ويحذف جداول المعدلات والعلاقات والإصدارات وعمودي مصدر المقايسة و«لا يبدأ قبل».
--  يرفض التراجع إن وُجدت بيانات أدخلها المستخدمون بعد الترحيل حتى لا تُفقد: معدلات إنتاجية، أو علاقات غير
--  «يتبع البند» القديمة، أو «لا يبدأ قبل»، أو إصدارات اعتُمدت بعده، أو مقايسات مستوردة، أو صلاحيات البرنامج الدقيقة.
--  يُشغَّل يدوياً عند الحاجة فقط، ويُختبر في supabase/tests/run_tests.sh.
-- =====================================================================
do $$
declare
  v text;
begin
  v := concat_ws('، ',
    case when exists (select 1 from public.pm_rates) then 'معدلات إنتاجية' end,
    case when exists (select 1 from public.pm_item_links l
                       where not (l.kind = 'FS' and l.lag_days = 0
                                  and exists (select 1 from public.pm_items i where i.id = l.succ_id and i.depends_on = l.pred_id)))
         then 'علاقات بين الأنشطة' end,
    case when exists (select 1 from public.pm_items where start_not_before is not null) then '«لا يبدأ قبل»' end,
    case when exists (select 1 from public.pm_plan_versions where source = 'approval') then 'إصدارات معتمدة' end,
    case when exists (select 1 from public.boq_sheets where source = 'import') then 'مقايسات مستوردة' end,
    case when exists (select 1 from public.user_grants where scope like 'docs:pm\_%') then 'صلاحيات البرنامج الدقيقة' end);
  if v <> '' then
    raise exception 'لا يُتراجع عن الترحيل 36: في المنظومة %', v using errcode = 'P0001';
  end if;
end $$;

drop trigger if exists projects_pm_versions_follow_merge on public.projects;
drop function if exists public.pm_versions_follow_merge();
drop function if exists public.save_pm_link(uuid, jsonb);
drop function if exists public.delete_pm_link(uuid);
drop function if exists public.pm_plan_snapshot(uuid, integer, text);
drop table if exists public.pm_plan_versions;
drop table if exists public.pm_item_links;
alter table public.pm_items drop column if exists start_not_before;
drop function if exists public.save_pm_rate(jsonb);
drop function if exists public.delete_pm_rate(uuid);
drop function if exists public.pm_can_rates();
drop function if exists public.pm_rate_days(text, text, numeric);
drop function if exists public.pm_rate_for(text, text);
drop function if exists public.pm_rates_current();
drop table if exists public.pm_rates;
drop function if exists public.pm_unit_norm(text);
drop function if exists public.pm_text_norm(text);
alter table public.boq_sheets drop constraint if exists boq_sheets_source_check;
alter table public.boq_sheets drop column if exists source;
alter table public.boq_sheets drop column if exists source_file;
alter table public.user_grants drop constraint if exists user_grants_scope_check;
alter table public.user_grants add constraint user_grants_scope_check check (
  scope ~ '^(form:[a-z0-9_]{1,40}|docs:(boq|letter|design)|supervision:reports|unit:[a-z_]{2,40}|swot|pm:(plan|track))$');

-- الدوال كما كانت بعد الترحيل 35
CREATE OR REPLACE FUNCTION public.save_boq(p_id uuid, p_data jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $$
declare
  old_row public.boq_sheets;
  new_row public.boq_sheets;
  v_proj  uuid;
  v_list  text;
  v_lines jsonb := '[]'::jsonb;
  v_total numeric := 0;
  v_title text := public.jtext(p_data, 'title', 200, 'عنوان المقايسة');
  ln      jsonb;
  it      public.price_items;
  v_qty   numeric;
  v_price numeric;
  v_desc  text;
  v_seq   integer;
  i       integer := 0;
begin
  if jsonb_typeof(coalesce(p_data, 'null'::jsonb)) <> 'object' then
    raise exception 'بيانات غير صالحة' using errcode = '22023';
  end if;
  if p_id is not null then
    select * into old_row from public.boq_sheets where id = p_id for update;
    if not found then
      raise exception 'المقايسة غير موجودة' using errcode = 'P0002';
    end if;
    if not public.doc_can_edit('boq', old_row.project_id) then
      raise exception 'لا تملك صلاحية تعديل المقايسات' using errcode = '42501';
    end if;
  end if;
  v_proj := case when p_data ? 'project_id' then public.jproject(p_data, 'project_id', false) else old_row.project_id end;
  if not public.doc_can_edit('boq', v_proj) then
    raise exception 'إعداد المقايسات لمكتب المدير ومكتب العقود ورئيسي الشؤون الفنية والمطابقة والاستلام' using errcode = '42501';
  end if;
  if length(v_title) < 2 then
    raise exception 'أدخل عنوان المقايسة' using errcode = '22023';
  end if;
  v_list := coalesce(nullif(btrim(coalesce(p_data ->> 'list_id', '')), ''), old_row.list_id,
                     (select id from public.price_lists where active order by year desc, id limit 1));
  if v_list is null or not exists (select 1 from public.price_lists where id = v_list) then
    raise exception 'لائحة الأسعار غير موجودة' using errcode = '22023';
  end if;
  if jsonb_typeof(coalesce(p_data -> 'lines', '[]'::jsonb)) <> 'array' then
    raise exception 'بنود المقايسة غير صالحة' using errcode = '22023';
  end if;
  if jsonb_array_length(coalesce(p_data -> 'lines', '[]'::jsonb)) > 2000 then
    raise exception 'المقايسة أكبر من 2000 بند؛ قسّمها إلى أكثر من مقايسة' using errcode = '22023';
  end if;

  for ln in select x from jsonb_array_elements(coalesce(p_data -> 'lines', '[]'::jsonb)) x loop
    i := i + 1;
    if jsonb_typeof(ln) <> 'object' then
      raise exception 'البند % غير صالح', i using errcode = '22023';
    end if;
    v_qty := public.jnum(ln, 'qty', 0, 1e10, 'الكمية في البند ' || i);
    v_seq := public.jint(ln, 'seq', 1, 1000000, 'رقم البند في اللائحة');
    if v_seq is not null then
      select * into it from public.price_items where list_id = v_list and seq = v_seq;
      if not found or it.kind <> 'item' then
        raise exception 'البند % ليس بنداً مسعّراً في اللائحة', i using errcode = '22023';
      end if;
      v_price := it.price;
      v_lines := v_lines || jsonb_build_object(
        'seq', it.seq, 'chapter', it.chapter, 'code', it.code, 'desc', it.full_desc, 'unit', it.unit,
        'price', it.price, 'qty', v_qty, 'notes', public.jtext(ln, 'notes', 1000, 'ملاحظات البند ' || i));
    else
      v_desc := public.jtext(ln, 'desc', 4000, 'وصف البند ' || i);
      if length(v_desc) < 2 then
        raise exception 'أدخل وصف البند % أو اختره من اللائحة', i using errcode = '22023';
      end if;
      v_price := public.jnum(ln, 'price', 0, 1e10, 'سعر الوحدة في البند ' || i);
      v_lines := v_lines || jsonb_build_object(
        'seq', null, 'chapter', '', 'code', public.jtext(ln, 'code', 30, 'رقم البند ' || i), 'desc', v_desc,
        'unit', public.jtext(ln, 'unit', 20, 'وحدة البند ' || i), 'price', v_price, 'qty', v_qty,
        'notes', public.jtext(ln, 'notes', 1000, 'ملاحظات البند ' || i));
    end if;
    v_total := v_total + coalesce(v_qty, 0) * coalesce(v_price, 0);
  end loop;

  if p_id is null then
    insert into public.boq_sheets (project_id, list_id, title, ref_no, notes, show_prices, lines, line_count, total,
                                   created_by, updated_by)
    values (v_proj, v_list, v_title, public.jtext(p_data, 'ref_no', 60, 'الرقم الإشاري'), public.jtext(p_data, 'notes', 2000, 'ملاحظات'),
            case when p_data ? 'show_prices' then public.jbool(p_data, 'show_prices') else true end, v_lines, jsonb_array_length(v_lines), round(v_total, 3),
            auth.uid(), auth.uid())
    returning * into new_row;
    perform public.write_audit('boq.create', v_proj, null,
      jsonb_build_object('title', v_title, 'lines', new_row.line_count, 'total', new_row.total));
  else
    update public.boq_sheets set
      project_id = v_proj, list_id = v_list, title = v_title,
      ref_no = public.jtext(p_data, 'ref_no', 60, 'الرقم الإشاري'), notes = public.jtext(p_data, 'notes', 2000, 'ملاحظات'),
      show_prices = case when p_data ? 'show_prices' then public.jbool(p_data, 'show_prices') else old_row.show_prices end,
      lines = v_lines, line_count = jsonb_array_length(v_lines), total = round(v_total, 3),
      updated_at = now(), updated_by = auth.uid()
    where id = p_id
    returning * into new_row;
    perform public.write_audit('boq.update', v_proj, null,
      jsonb_build_object('title', v_title, 'lines', new_row.line_count, 'total', new_row.total,
                         'changes', public.jsonb_changes(to_jsonb(old_row) - 'lines', to_jsonb(new_row) - 'lines',
                                                         array['updated_at', 'updated_by'])));
  end if;
  return new_row.id;
end;
$$;

CREATE OR REPLACE FUNCTION public.grant_scope_ok(p_scope text)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $$
  select case
    when p_scope like 'form:%' then exists (select 1 from public.form_defs where key = substr(p_scope, 6))
    when p_scope like 'unit:%' then public.unit_kind_spec(substr(p_scope, 6)) is not null
    else p_scope in ('docs:boq', 'docs:letter', 'docs:design', 'supervision:reports', 'swot', 'pm:plan', 'pm:track')
  end
$$;

CREATE OR REPLACE FUNCTION public.pm_plan_recalc(p_project uuid)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $$
declare
  v_start  date;
  ph       record;
  it       record;
  v_pstart date;
  v_pend   date;
  v_prev   date;
  v_base   date;
  v_s      date;
  v_ends   jsonb := '{}'::jsonb;
  n        integer := 0;
begin
  select start_date into v_start from public.pm_plans where project_id = p_project;
  if v_start is null then
    return 0;
  end if;
  -- البنود دون مرحلة وبمدة: من بداية البرنامج
  for it in select i.id, i.duration_days, i.offset_days, i.depends_on, i.planned_end
              from public.pm_items i where i.project_id = p_project and i.phase_id is null
             order by i.sort, i.created_at loop
    if it.duration_days is null then
      v_ends := v_ends || jsonb_build_object(it.id::text, it.planned_end);
      continue;
    end if;
    v_base := greatest(v_start, coalesce((v_ends ->> it.depends_on::text)::date, v_start));
    v_s := v_base + it.offset_days;
    update public.pm_items set planned_start = v_s, planned_end = v_s + it.duration_days
     where id = it.id and (planned_start, planned_end) is distinct from (v_s, v_s + it.duration_days);
    v_ends := v_ends || jsonb_build_object(it.id::text, v_s + it.duration_days);
    n := n + 1;
  end loop;
  v_prev := null;
  for ph in select id, lag_days from public.pm_phases where project_id = p_project order by sort, created_at loop
    v_pstart := case when v_prev is null then v_start else greatest(v_start, v_prev + ph.lag_days) end;
    v_pend := v_pstart;
    for it in select i.id, i.duration_days, i.offset_days, i.depends_on, i.planned_end
                from public.pm_items i where i.project_id = p_project and i.phase_id = ph.id
               order by i.sort, i.created_at loop
      if it.duration_days is null then
        v_pend := greatest(v_pend, it.planned_end);
        v_ends := v_ends || jsonb_build_object(it.id::text, it.planned_end);
        continue;
      end if;
      v_base := greatest(v_pstart, coalesce((v_ends ->> it.depends_on::text)::date, v_pstart));
      v_s := v_base + it.offset_days;
      update public.pm_items set planned_start = v_s, planned_end = v_s + it.duration_days
       where id = it.id and (planned_start, planned_end) is distinct from (v_s, v_s + it.duration_days);
      v_ends := v_ends || jsonb_build_object(it.id::text, v_s + it.duration_days);
      v_pend := greatest(v_pend, v_s + it.duration_days);
      n := n + 1;
    end loop;
    v_prev := v_pend;
  end loop;
  return n;
end;
$$;

drop function if exists public.pm_recalc_group(uuid, uuid, date, jsonb, jsonb);

CREATE OR REPLACE FUNCTION public.save_pm_item(p_id uuid, p_data jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $$
declare
  o        public.pm_items;
  n        public.pm_items;
  pl       public.pm_plans;
  v_proj   uuid;
  v_new    boolean := p_id is null;
  v_struct boolean := false;
  v_track  boolean := false;
  v_title  text;
  v_code   text;
  v_phase  uuid;
  v_dur    integer;
  v_off    integer;
  v_dep    uuid;
  v_w      numeric;
  v_work   uuid;
  v_sort   integer;
  v_ps     date;
  v_pe     date;
  v_src    text;
  v_unit   text;
  v_qty    numeric;
  v_pseq   integer;
  v_pr     numeric;
  v_as     date;
  v_ae     date;
  v_notes  text;
  v_na     boolean;
  v_rank   bigint;
begin
  if jsonb_typeof(coalesce(p_data, 'null'::jsonb)) <> 'object' then
    raise exception 'بيانات غير صالحة' using errcode = '22023';
  end if;
  if v_new then
    v_proj := public.jproject(p_data, 'project_id', true);
  else
    select * into o from public.pm_items where id = p_id for update;
    if not found then
      raise exception 'البند غير موجود' using errcode = 'P0002';
    end if;
    v_proj := o.project_id;
  end if;

  -- القيم: المرسلة، وإلا القائمة
  v_title := case when p_data ? 'title' then public.jtext(p_data, 'title', 300, 'اسم البند') else o.title end;
  v_code  := case when p_data ? 'code' then public.jtext(p_data, 'code', 20, 'رقم البند') else coalesce(o.code, '') end;
  begin
    v_phase := case when p_data ? 'phase_id' then nullif(btrim(coalesce(p_data ->> 'phase_id', '')), '')::uuid else o.phase_id end;
    v_dep   := case when p_data ? 'depends_on' then nullif(btrim(coalesce(p_data ->> 'depends_on', '')), '')::uuid else o.depends_on end;
    v_work  := case when p_data ? 'work_id' then nullif(btrim(coalesce(p_data ->> 'work_id', '')), '')::uuid else o.work_id end;
  exception when invalid_text_representation then
    raise exception 'مرجع غير صالح' using errcode = '22023';
  end;
  v_dur   := case when p_data ? 'duration_days' then public.jint(p_data, 'duration_days', 1, 3650, 'المدة') else o.duration_days end;
  v_off   := case when p_data ? 'offset_days' then coalesce(public.jint(p_data, 'offset_days', 0, 3650, 'الإزاحة'), 0) else coalesce(o.offset_days, 0) end;
  v_w     := case when p_data ? 'weight' then public.jnum(p_data, 'weight', 0.001, 1e11, 'الوزن') else o.weight end;
  v_sort  := case when p_data ? 'sort' then public.jint(p_data, 'sort', 0, 100000000, 'الترتيب') else o.sort end;
  v_ps    := case when p_data ? 'planned_start' then public.jdate(p_data, 'planned_start', 'البداية المخططة') else o.planned_start end;
  v_pe    := case when p_data ? 'planned_end' then public.jdate(p_data, 'planned_end', 'النهاية المخططة') else o.planned_end end;
  v_src   := case when v_new then coalesce(nullif(p_data ->> 'source', ''), 'manual') else o.source end;
  v_unit  := case when p_data ? 'unit' then public.jtext(p_data, 'unit', 20, 'الوحدة') else coalesce(o.unit, '') end;
  v_qty   := case when p_data ? 'qty' then public.jnum(p_data, 'qty', 0, 1e12, 'الكمية') else o.qty end;
  v_pseq  := case when p_data ? 'price_seq' then public.jint(p_data, 'price_seq', 1, 1000000, 'رقم اللائحة') else o.price_seq end;
  v_pr    := case when p_data ? 'progress' then coalesce(public.jnum(p_data, 'progress', 0, 100, 'نسبة الإنجاز'), 0) else coalesce(o.progress, 0) end;
  v_as    := case when p_data ? 'actual_start' then public.jdate(p_data, 'actual_start', 'البداية الفعلية') else o.actual_start end;
  v_ae    := case when p_data ? 'actual_end' then public.jdate(p_data, 'actual_end', 'النهاية الفعلية') else o.actual_end end;
  v_notes := case when p_data ? 'notes' then public.jtext(p_data, 'notes', 1000, 'ملاحظات') else coalesce(o.notes, '') end;
  v_na    := case when p_data ? 'not_applicable' then public.jbool(p_data, 'not_applicable') else coalesce(o.not_applicable, false) end;

  if v_new and v_src not in ('manual', 'extra') then
    raise exception 'بنود المقايسة تُنشأ من توليد البرنامج' using errcode = '22023';
  end if;

  -- ما الذي تغيّر: بيانات البند (إعداد) أم التنفيذ (متابعة)
  v_struct := v_new or v_title is distinct from o.title or v_code is distinct from o.code or v_phase is distinct from o.phase_id
              or v_dur is distinct from o.duration_days or v_off is distinct from o.offset_days or v_dep is distinct from o.depends_on
              or v_w is distinct from o.weight or v_work is distinct from o.work_id or v_sort is distinct from o.sort
              or (v_dur is null and (v_ps is distinct from o.planned_start or v_pe is distinct from o.planned_end))
              or v_unit is distinct from o.unit or v_qty is distinct from o.qty or v_pseq is distinct from o.price_seq;
  v_track := (v_new and (v_pr <> 0 or v_as is not null or v_ae is not null or v_na))
             or (not v_new and (v_pr is distinct from o.progress or v_as is distinct from o.actual_start
                                or v_ae is distinct from o.actual_end or v_na is distinct from o.not_applicable
                                or v_notes is distinct from o.notes));

  if v_struct then
    if not public.can_prepare_plan(v_proj) then
      raise exception 'إعداد البرنامج الزمني وبنوده ومددها من اختصاص الشؤون الفنية' using errcode = '42501';
    end if;
    pl := public.pm_plan_draft(v_proj);
  else
    select * into pl from public.pm_plans where project_id = v_proj;
  end if;
  if v_track then
    if v_new then
      raise exception 'تُسجَّل نسبة الإنجاز بعد اعتماد البرنامج الزمني وإحالته إلى الإشراف' using errcode = '22023';
    end if;
    if not public.can_track_plan(v_proj) then
      raise exception 'متابعة التنفيذ وتسجيل الإنجاز من اختصاص القسم المشرف على العقد' using errcode = '42501';
    end if;
    if pl.id is null or pl.status <> 'approved' then
      raise exception 'تُسجَّل نسب الإنجاز على البرنامج الزمني المعتمد' using errcode = '22023';
    end if;
  end if;
  if not v_struct and not v_track then
    return p_id;
  end if;

  -- التحقق
  if length(v_title) < 2 then
    raise exception 'أدخل اسم البند' using errcode = '22023';
  end if;
  if v_phase is not null and not exists (select 1 from public.pm_phases where id = v_phase and project_id = v_proj) then
    raise exception 'المرحلة ليست من مراحل هذا العقد' using errcode = '22023';
  end if;
  if v_work is not null and not exists (select 1 from public.contract_works where id = v_work and project_id = v_proj) then
    raise exception 'عمل العقد المختار ليس من أعمال هذا العقد' using errcode = '22023';
  end if;
  if v_dur is null then
    if v_ps is null or v_pe is null then
      raise exception 'حدّد مدة البند، أو بدايته ونهايته المخططتين' using errcode = '22023';
    end if;
    if v_pe < v_ps then
      raise exception 'النهاية المخططة قبل البداية المخططة' using errcode = '22023';
    end if;
  else
    v_ps := coalesce(v_ps, pl.start_date);
    v_pe := v_ps + v_dur;
  end if;
  if v_struct and v_src <> 'boq' and public.pm_boq_duplicate(v_proj, v_pseq, v_title, p_id) then
    raise exception 'هذا البند موجود في المقايسة المعتمدة للعقد؛ لا يُضاف مرة أخرى' using errcode = '22023';
  end if;
  if v_as is not null and v_as > current_date + 1 then
    raise exception 'البداية الفعلية في المستقبل' using errcode = '22023';
  end if;
  if v_ae is not null and v_ae > current_date + 1 then
    raise exception 'النهاية الفعلية في المستقبل' using errcode = '22023';
  end if;
  if v_ae is not null and v_as is not null and v_ae < v_as then
    raise exception 'النهاية الفعلية قبل البداية الفعلية' using errcode = '22023';
  end if;
  if v_ae is not null and v_pr < 100 then
    raise exception 'النهاية الفعلية تُسجَّل عند اكتمال البند (100%%)' using errcode = '22023';
  end if;

  if v_new then
    insert into public.pm_items (project_id, work_id, sort, code, title, planned_start, planned_end, weight, progress,
                                 notes, phase_id, duration_days, offset_days, source, unit, qty, price_seq,
                                 created_by, updated_by)
    values (v_proj, v_work, coalesce(v_sort, (select coalesce(max(sort), 0) + 10 from public.pm_items where project_id = v_proj)),
            v_code, v_title, v_ps, v_pe, v_w, 0, v_notes, v_phase, v_dur, v_off, v_src, v_unit, v_qty, v_pseq,
            auth.uid(), auth.uid())
    returning * into n;
  else
    update public.pm_items set
      work_id = v_work, sort = coalesce(v_sort, o.sort), code = v_code, title = v_title, planned_start = v_ps, planned_end = v_pe,
      weight = v_w, progress = round(v_pr, 2), actual_start = v_as, actual_end = v_ae, notes = v_notes,
      phase_id = v_phase, duration_days = v_dur, offset_days = v_off, depends_on = v_dep, unit = v_unit, qty = v_qty,
      price_seq = v_pseq, not_applicable = v_na, updated_at = now(), updated_by = auth.uid()
    where id = p_id
    returning * into n;
  end if;

  -- التبعية لبند سابق في الترتيب من العقد نفسه
  if v_new and v_dep is not null then
    update public.pm_items set depends_on = v_dep where id = n.id returning * into n;
  end if;
  if n.depends_on is not null then
    v_rank := public.pm_item_rank(n.id);
    if n.depends_on = n.id
       or not exists (select 1 from public.pm_items where id = n.depends_on and project_id = v_proj)
       or public.pm_item_rank(n.depends_on) >= v_rank then
      raise exception 'يتبع البند بنداً سابقاً له في ترتيب البرنامج من العقد نفسه' using errcode = '22023';
    end if;
  end if;

  perform public.pm_after_change(v_proj);
  select * into n from public.pm_items where id = n.id;
  if v_new then
    perform public.write_audit('pm.item_add', v_proj, null,
      jsonb_build_object('title', v_title, 'source', v_src, 'duration_days', v_dur, 'planned_start', n.planned_start, 'planned_end', n.planned_end));
  else
    perform public.write_audit(case when v_struct then 'pm.item_update' else 'pm.item_progress' end, v_proj, null,
      jsonb_build_object('title', v_title,
                         'changes', public.jsonb_changes(to_jsonb(o), to_jsonb(n), array['updated_at', 'updated_by'])));
  end if;
  return n.id;
end;
$$;

CREATE OR REPLACE FUNCTION public.delete_pm_item(p_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $$
declare
  r public.pm_items;
begin
  select * into r from public.pm_items where id = p_id for update;
  if not found then
    raise exception 'البند غير موجود' using errcode = 'P0002';
  end if;
  if not public.can_prepare_plan(r.project_id) then
    raise exception 'حذف بنود البرنامج الزمني من اختصاص الشؤون الفنية' using errcode = '42501';
  end if;
  perform public.pm_plan_draft(r.project_id);
  delete from public.pm_items where id = p_id;
  perform public.pm_after_change(r.project_id);
  perform public.write_audit('pm.item_delete', r.project_id, null,
    jsonb_build_object('title', r.title, 'planned_start', r.planned_start, 'planned_end', r.planned_end, 'progress', r.progress));
end;
$$;

CREATE OR REPLACE FUNCTION public.pm_plan_set_status(p_project uuid, p_status text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $$
declare
  pl  public.pm_plans;
  v_n integer;
  v_e date;
  u   record;
begin
  if not public.can_approve_plan(p_project) then
    raise exception 'اعتماد البرنامج الزمني وإعادة فتحه لرئيس الشؤون الفنية ومدير المكتب' using errcode = '42501';
  end if;
  select * into pl from public.pm_plans where project_id = p_project for update;
  if not found then
    raise exception 'لا برنامج زمني لهذا العقد بعد' using errcode = '22023';
  end if;
  if p_status = 'approved' then
    if pl.status = 'approved' then
      return;
    end if;
    perform public.pm_plan_recalc(p_project);
    select count(*), max(planned_end) into v_n, v_e from public.pm_items where project_id = p_project;
    if v_n = 0 then
      raise exception 'البرنامج بلا بنود' using errcode = '22023';
    end if;
    update public.pm_plans set status = 'approved', version = version + 1, approved_at = now(), approved_by = auth.uid(),
                               updated_at = now(), updated_by = auth.uid()
     where id = pl.id;
    perform public.write_audit('pm.plan_approve', p_project, null,
      jsonb_build_object('version', pl.version + 1, 'items', v_n, 'start_date', pl.start_date, 'end_date', v_e,
                         'total_days', v_e - pl.start_date));
    for u in select pr.id from public.profiles pr join public.projects p on p.id = p_project
              where pr.active and pr.role::text = 'dept_head' and pr.department = p.department and pr.id <> coalesce(auth.uid(), pr.id) loop
      perform public.notify_user(u.id, 'plan', 'أُحيل إليكم برنامج زمني معتمد',
        public.project_label(p_project) || ': ' || v_n || ' بنداً من ' || to_char(pl.start_date, 'YYYY/MM/DD') || ' إلى ' || to_char(v_e, 'YYYY/MM/DD'),
        p_project);
    end loop;
  elsif p_status = 'draft' then
    if pl.status = 'draft' then
      return;
    end if;
    update public.pm_plans set status = 'draft', updated_at = now(), updated_by = auth.uid() where id = pl.id;
    perform public.write_audit('pm.plan_reopen', p_project, null, jsonb_build_object('version', pl.version));
  else
    raise exception 'حالة غير معروفة' using errcode = '22023';
  end if;
  perform public.pm_after_change(p_project);
end;
$$;

drop function if exists public.pm_gen_plan(uuid, integer);
CREATE OR REPLACE FUNCTION public.pm_gen_plan(p_project uuid, p_total_days integer)
 RETURNS TABLE(pkey text, pname text, porder bigint, pdays integer, pcost numeric, sheet uuid, idx integer, pseq integer, code text, title text, unit text, qty numeric, cost numeric, idays integer, lorder bigint)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $$
  with l0 as (
    select s.id as sheet, l.ord::integer as idx, nullif(l.x ->> 'seq', '')::integer as pseq, coalesce(l.x ->> 'code', '') as code,
           coalesce(l.x ->> 'desc', '') as descr, coalesce(l.x ->> 'unit', '') as unit, nullif(l.x ->> 'qty', '')::numeric as qty,
           coalesce(nullif(l.x ->> 'qty', '')::numeric, 0) * coalesce(nullif(l.x ->> 'price', '')::numeric, 0) as cost,
           case when pi.seq is null then 'zz' else pi.chapter || ':' || split_part(pi.code, '.', 1) end as pkey,
           case when pi.seq is null or pi.section = '' then 'بنود أخرى'
                else left(btrim(regexp_replace(pi.section, '^[^:]{1,25}:-?\s*', '')), 120) end as pname,
           case when pi.seq is null then 999999999::bigint
                else coalesce((select o.n from jsonb_array_elements(pli.chapters) with ordinality o(c, n) where o.c ->> 'key' = pi.chapter), 99) * 100000
                     + coalesce(nullif(regexp_replace(split_part(pi.code, '.', 1), '\D', '', 'g'), '')::integer, 9999) end as porder,
           coalesce(pi.seq, 900000000 + l.ord::integer)::bigint as lorder
      from public.boq_sheets s
      cross join lateral jsonb_array_elements(s.lines) with ordinality l(x, ord)
      left join public.price_items pi on pi.list_id = s.list_id and pi.seq = nullif(l.x ->> 'seq', '')::integer
      left join public.price_lists pli on pli.id = s.list_id
     where s.project_id = p_project and s.status = 'approved'
  ), tot as (
    select sum(cost) as total, count(*) as n from l0
  ), ph as (
    select l0.pkey, min(l0.pname) as pname, min(l0.porder) as porder, sum(l0.cost) as pcost, max(l0.cost) as maxc,
           greatest(3, round(p_total_days * case when coalesce(tot.total, 0) > 0 then sum(l0.cost) / tot.total
                                                 else count(*)::numeric / tot.n end)::integer) as pdays
      from l0, tot group by l0.pkey, tot.total, tot.n
  )
  select ph.pkey, ph.pname, ph.porder, ph.pdays, ph.pcost, l0.sheet, l0.idx, l0.pseq, left(l0.code, 20),
         left(coalesce(nullif(btrim(regexp_replace(l0.descr, '^.* — ', '')), ''), l0.descr), 300), left(l0.unit, 20), l0.qty, l0.cost,
         case when coalesce(ph.maxc, 0) > 0 then greatest(1, round(ph.pdays * sqrt(l0.cost / ph.maxc))::integer) else ph.pdays end,
         l0.lorder
    from l0 join ph on ph.pkey = l0.pkey
   order by ph.porder, ph.pkey, l0.lorder, l0.idx
$$;

CREATE OR REPLACE FUNCTION public.pm_plan_preview_v34(p_project uuid, p_total_days integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $$
declare
  v jsonb;
begin
  if not public.is_member() then
    raise exception 'غير مصرح' using errcode = '42501';
  end if;
  if p_total_days is null or p_total_days < 7 or p_total_days > 3650 then
    raise exception 'المدة الإجمالية المقترحة بين 7 و3650 يوماً' using errcode = '22023';
  end if;
  select jsonb_build_object(
           'phases', coalesce(jsonb_agg(jsonb_build_object('name', x.pname, 'days', x.pdays, 'cost', x.pcost, 'items', x.items)
                                        order by x.porder, x.pkey), '[]'::jsonb),
           'total_days', coalesce(sum(x.pdays), 0), 'items', coalesce(sum(x.n), 0))
    into v
    from (select g.pkey, g.pname, g.porder, g.pdays, g.pcost, count(*) as n,
                 jsonb_agg(jsonb_build_object('code', g.code, 'title', g.title, 'days', g.idays, 'cost', g.cost, 'unit', g.unit, 'qty', g.qty)
                           order by g.lorder, g.idx) as items
            from public.pm_gen_plan(p_project, p_total_days) g
           group by g.pkey, g.pname, g.porder, g.pdays, g.pcost) x;
  return v;
end;
$$;

drop function if exists public.pm_can(uuid, text);

revoke execute on function public.pm_gen_plan(uuid, integer), public.pm_plan_recalc(uuid), public.pm_plan_preview_v34(uuid, integer)
  from public, anon, authenticated;
revoke execute on function public.save_boq(uuid, jsonb), public.save_pm_item(uuid, jsonb), public.delete_pm_item(uuid),
  public.pm_plan_set_status(uuid, text), public.grant_scope_ok(text) from public, anon;
grant execute on function public.save_boq(uuid, jsonb), public.save_pm_item(uuid, jsonb), public.delete_pm_item(uuid),
  public.pm_plan_set_status(uuid, text), public.grant_scope_ok(text) to authenticated;
