-- =====================================================================
-- الإصدار 1.12.0 (الترحيل 43): خطط الاستجابة للمخاطر ومخاطر الأقسام الآلية
--
--  1. إجراءات الاستجابة (risk_actions): لكل خطر إجراءات بعنوان ومسؤول وموعد وحالة (مفتوح ← منجَز أو ملغى)، يكتبها من يحرر
--     سجل المخاطر (can_edit_risks) على خطر داخل نطاقه، وتُقرأ بقراءة الخطر نفسه. كل كتابة بدالة تسجّل في سجل التدقيق.
--  2. مخاطر الأقسام الآلية: risk_refresh_sections() (مرة في الساعة على الأكثر) تفتح وتحدّث وتغلق مخاطر مفتاحها
--       st_item:<الصنف>   نفاد صنف أو نزول متاحه دون حده الأدنى في كل المخازن (الاحتمالية 5 إن نفد وإلا 4، والتأثير 4 إن له احتياطي حرج وإلا 3)
--       pr_order:<الأمر>  أمر شراء لم يكتمل استلامه بعد موعده المتوقع + مهلة المشتريات (الاحتمالية 5 إن جاوز 14 يوماً وإلا 4، والتأثير 3)
--       mt_req:<البلاغ>   بلاغ صيانة مفتوح فات موعده (الاحتمالية 5 إن جاوز 7 أيام وإلا 4، والتأثير من الأولوية: عاجلة 5، عالية 4، عادية 3، منخفضة 2)
--     بقاعدة مخاطر البرنامج الزمني نفسها: يُغلق الخطر حين يزول سببه ويُعاد فتحه إن عاد، ولا يُمَسّ ما عدّله المستخدم من
--     الوصف والإجراء والمالك، ولا يُعاد فتح ما أغلقه المستخدم ما دام سببه قائماً.
--  يُشغَّل بعد 20261203000042_stocktaking.sql، وإعادة تشغيله آمنة. التراجع: supabase/rollbacks/20261204000043_risk_actions_sections_down.sql
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. إجراءات الاستجابة
-- ---------------------------------------------------------------------
create table if not exists public.risk_actions (
  id         uuid primary key default gen_random_uuid(),
  risk_id    uuid not null references public.risks (id) on delete cascade,
  title      text not null check (length(btrim(title)) between 3 and 200),
  owner      text not null default '' check (length(owner) <= 60),
  due_date   date,
  status     text not null default 'open' check (status in ('open', 'done', 'cancelled')),
  done_on    date,
  note       text not null default '' check (length(note) <= 300),
  created_at timestamptz not null default now(),
  created_by uuid references public.profiles (id) on delete set null,
  updated_at timestamptz not null default now(),
  updated_by uuid references public.profiles (id) on delete set null,
  check ((status = 'done') = (done_on is not null))
);
create index if not exists risk_actions_risk_idx on public.risk_actions (risk_id);
create index if not exists risk_actions_created_by_idx on public.risk_actions (created_by);
create index if not exists risk_actions_updated_by_idx on public.risk_actions (updated_by);
create index if not exists risk_actions_due_idx on public.risk_actions (due_date) where status = 'open';

alter table public.risk_actions enable row level security;
drop policy if exists risk_actions_read on public.risk_actions;
create policy risk_actions_read on public.risk_actions for select to authenticated
  using (exists (select 1 from public.risks r where r.id = risk_actions.risk_id));
revoke all on public.risk_actions from anon;
revoke insert, update, delete, truncate on public.risk_actions from authenticated;
grant select on public.risk_actions to authenticated;
grant all on public.risk_actions to service_role;

-- حفظ إجراء (جديد أو تعديل): p_data = {title, owner?, due_date?, note?}
create or replace function public.risk_action_save(p_id uuid, p_risk uuid, p_data jsonb)
returns uuid
language plpgsql security definer set search_path = public
as $$
declare
  rk    public.risks;
  a     public.risk_actions;
  v_id  uuid;
  v_title text := public.jtext(p_data, 'title', 200, 'الإجراء');
  v_due   date := public.jdate(p_data, 'due_date', 'موعد الإجراء');
begin
  if not public.can_edit_risks() then
    raise exception 'لا تملك صلاحية تعديل سجل المخاطر' using errcode = '42501';
  end if;
  if jsonb_typeof(coalesce(p_data, 'null'::jsonb)) <> 'object' then
    raise exception 'بيانات الإجراء غير صالحة' using errcode = '22023';
  end if;
  if length(v_title) < 3 then
    raise exception 'اكتب الإجراء (3 أحرف على الأقل)' using errcode = '22023';
  end if;
  if p_id is not null then
    select * into a from public.risk_actions where id = p_id for update;
    if not found then
      raise exception 'الإجراء غير موجود' using errcode = 'P0002';
    end if;
    select * into rk from public.risks where id = a.risk_id;
  else
    select * into rk from public.risks where id = p_risk;
  end if;
  if rk.id is null then
    raise exception 'الخطر غير موجود' using errcode = 'P0002';
  end if;
  if not public.pm_row_ok(rk.project_id) then
    raise exception 'هذا الخطر خارج نطاق قسمك' using errcode = '42501';
  end if;
  if p_id is null then
    insert into public.risk_actions (risk_id, title, owner, due_date, note, created_by, updated_by)
    values (rk.id, v_title, public.jtext(p_data, 'owner', 60, 'مسؤول الإجراء'), v_due,
            public.jtext(p_data, 'note', 300, 'الملاحظة'), auth.uid(), auth.uid())
    returning id into v_id;
  else
    update public.risk_actions set
      title = v_title, owner = public.jtext(p_data, 'owner', 60, 'مسؤول الإجراء'), due_date = v_due,
      note = public.jtext(p_data, 'note', 300, 'الملاحظة'), updated_at = now(), updated_by = auth.uid()
     where id = p_id;
    v_id := p_id;
  end if;
  perform public.write_audit('risk.action_save', rk.project_id, null,
    jsonb_build_object('id', v_id, 'op', case when p_id is null then 'create' else 'update' end, 'title', v_title, 'due', v_due), rk.code);
  return v_id;
end;
$$;

-- حالة الإجراء: open مفتوح، done منجَز (بتاريخ اليوم)، cancelled ملغى
create or replace function public.risk_action_status(p_id uuid, p_status text, p_note text default '')
returns void
language plpgsql security definer set search_path = public
as $$
declare
  a    public.risk_actions;
  rk   public.risks;
  v_note text := btrim(coalesce(p_note, ''));
begin
  if not public.can_edit_risks() then
    raise exception 'لا تملك صلاحية تعديل سجل المخاطر' using errcode = '42501';
  end if;
  if p_status not in ('open', 'done', 'cancelled') then
    raise exception 'حالة إجراء غير معروفة' using errcode = '22023';
  end if;
  if length(v_note) > 300 then
    raise exception 'الملاحظة أطول من 300 حرف' using errcode = '22023';
  end if;
  select * into a from public.risk_actions where id = p_id for update;
  if not found then
    raise exception 'الإجراء غير موجود' using errcode = 'P0002';
  end if;
  select * into rk from public.risks where id = a.risk_id;
  if not public.pm_row_ok(rk.project_id) then
    raise exception 'هذا الخطر خارج نطاق قسمك' using errcode = '42501';
  end if;
  if p_status = 'cancelled' and length(v_note) < 3 then
    raise exception 'اكتب سبب إلغاء الإجراء' using errcode = '22023';
  end if;
  update public.risk_actions set
    status = p_status,
    done_on = case when p_status = 'done' then coalesce(done_on, current_date) end,
    note = case when v_note <> '' then v_note else note end,
    updated_at = now(), updated_by = auth.uid()
   where id = p_id;
  perform public.write_audit('risk.action_status', rk.project_id, null,
    jsonb_build_object('id', p_id, 'title', a.title, 'from', a.status, 'to', p_status, 'note', v_note), rk.code);
end;
$$;

create or replace function public.risk_action_delete(p_id uuid)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  a  public.risk_actions;
  rk public.risks;
begin
  if not public.can_edit_risks() then
    raise exception 'لا تملك صلاحية تعديل سجل المخاطر' using errcode = '42501';
  end if;
  select * into a from public.risk_actions where id = p_id for update;
  if not found then
    raise exception 'الإجراء غير موجود' using errcode = 'P0002';
  end if;
  select * into rk from public.risks where id = a.risk_id;
  if not public.pm_row_ok(rk.project_id) then
    raise exception 'هذا الخطر خارج نطاق قسمك' using errcode = '42501';
  end if;
  delete from public.risk_actions where id = p_id;
  perform public.write_audit('risk.action_delete', rk.project_id, null, jsonb_build_object('id', p_id, 'title', a.title), rk.code);
end;
$$;

-- ---------------------------------------------------------------------
-- 2. مخاطر الأقسام الآلية
-- ---------------------------------------------------------------------
create table if not exists public.risk_auto_runs (
  id     integer primary key default 1 check (id = 1),
  ran_at timestamptz not null default now()
);
alter table public.risk_auto_runs enable row level security;
revoke all on public.risk_auto_runs from anon, authenticated;
grant all on public.risk_auto_runs to service_role;

-- الأسباب القائمة الآن: صف لكل خطر مرغوب (المفتاح والنص والاحتمالية والتأثير...)
create or replace function public.risk_section_wants()
returns table (k text, descr text, cause text, effect text, prob smallint, imp smallint, category text, department text,
               owner text, days integer, early text)
language sql stable security definer set search_path = public
as $$
  -- المخازن: نفاد أو نقص عن الحد الأدنى في كل المخازن
  select 'st_item:' || i.id,
         left(format('نفاد أو نقص الصنف «%s» (%s) عن حده الأدنى', i.name, i.code), 300),
         'نزل الرصيد المتاح عن الحد الأدنى المعتمد لبطاقة الصنف',
         left(format('الفعلي %s والمتاح %s مقابل حد أدنى %s%s', t.on_hand, t.av, i.min_qty,
                     case when i.critical_qty > 0 then '، وللصنف احتياطي حرج ' || i.critical_qty else '' end), 500),
         (case when t.on_hand <= 0 then 5 else 4 end)::smallint,
         (case when i.critical_qty > 0 then 4 else 3 end)::smallint,
         'مخزون', 'المخازن', 'مدير المخازن', null::integer,
         'الرصيد المتاح دون الحد الأدنى في لوحة المخازن'
    from public.st_items i
    cross join lateral (select coalesce(sum(s.on_hand), 0) as on_hand, coalesce(sum(s.on_hand - s.reserved), 0) as av
                          from public.st_stock s where s.item_id = i.id) t
   where i.active
     and ((t.on_hand <= 0 and (i.min_qty > 0 or i.reorder_qty > 0)) or (i.min_qty > 0 and t.av < i.min_qty))
  union all
  -- المشتريات: توريد متأخر عن موعده + المهلة
  select 'pr_order:' || o.id,
         left(format('تأخر توريد أمر الشراء %s عن موعده المتوقع', o.po_no), 300),
         'لم يكتمل استلام الأمر بعد الموعد المتوقع ومهلة القسم',
         left(format('الموعد المتوقع %s وتأخر %s يوماً', to_char(o.expected_date, 'YYYY/MM/DD'), current_date - o.expected_date), 500),
         (case when current_date - o.expected_date > 14 then 5 else 4 end)::smallint,
         3::smallint,
         'توريد', 'المشتريات', 'مسؤول المشتريات', least(current_date - o.expected_date, 3650),
         'أمر شراء متأخر في تنبيهات المشتريات'
    from public.pr_orders o
   where o.status in ('issued', 'partial') and o.expected_date is not null
     and o.expected_date + public.pr_setting_num('grace_days', 3)::integer < current_date
  union all
  -- الصيانة: بلاغ مفتوح فات موعده
  select 'mt_req:' || r.id,
         left(format('تأخر بلاغ الصيانة %s «%s» عن موعده المستهدف', r.req_no, r.title), 300),
         'لم يُنجز البلاغ حتى موعده المستهدف',
         left(format('الموعد المستهدف %s وتأخر %s يوماً', to_char(r.due_at at time zone 'Africa/Tripoli', 'YYYY/MM/DD'),
                     (now() at time zone 'Africa/Tripoli')::date - (r.due_at at time zone 'Africa/Tripoli')::date), 500),
         (case when now() - r.due_at > interval '7 days' then 5 else 4 end)::smallint,
         (case r.priority when 'urgent' then 5 when 'high' then 4 when 'normal' then 3 else 2 end)::smallint,
         'صيانة', 'الصيانة', 'مدير الصيانة',
         least(greatest((now() at time zone 'Africa/Tripoli')::date - (r.due_at at time zone 'Africa/Tripoli')::date, 0), 3650),
         'بلاغ متأخر في تنبيهات الصيانة'
    from public.mt_requests r
   where r.status in ('new', 'assigned', 'in_progress') and r.due_at < now()
$$;

-- يفتح ويحدّث ويغلق مخاطر الأقسام بما تعيده risk_section_wants؛ يعيد أعداد ما فُتح وحُدّث وأُغلق
create or replace function public.risk_sync_sections()
returns jsonb
language plpgsql security definer set search_path = public
as $$
declare
  w        record;
  rk       public.risks;
  v_code   text;
  v_open   integer := 0;
  v_upd    integer := 0;
  v_close  integer := 0;
begin
  for w in select * from public.risk_section_wants() loop
    select * into rk from public.risks where auto_key = w.k for update;
    if not found then
      select 'R' || lpad((coalesce(max(substring(code from 2)::integer), 0) + 1)::text, 2, '0') into v_code
        from public.risks where code ~ '^R[0-9]+$';
      insert into public.risks (code, phase, category, description, cause, effect, probability, impact, response, owner, status,
                                department, time_impact_days, early_warning, notes, auto_key, auto_active, created_by, updated_by)
      values (v_code, 'التشغيل', w.category, w.descr, w.cause, w.effect, w.prob, w.imp, 'mitigate', w.owner, 'open',
              w.department, w.days, w.early, 'سُجّل تلقائياً من بيانات القسم', w.k, true, auth.uid(), auth.uid());
      v_open := v_open + 1;
    else
      update public.risks set
        effect = w.effect, probability = w.prob, impact = w.imp, time_impact_days = w.days,
        status = case when status = 'closed' and auto_active is false then 'open' else status end,
        closed_on = case when status = 'closed' and auto_active is false then null else closed_on end,
        auto_active = true, updated_at = now()
       where id = rk.id
         and ((effect, probability, impact, time_impact_days, auto_active) is distinct from (w.effect, w.prob, w.imp, w.days, true)
              or (status = 'closed' and auto_active is false));
      if found then
        v_upd := v_upd + 1;
        if rk.status = 'closed' and rk.auto_active is false then
          v_open := v_open + 1;
        end if;
      end if;
    end if;
  end loop;

  -- ما زال سببه قائماً غير وارد: يُغلق
  for rk in select * from public.risks
             where auto_key ~ '^(st_item|pr_order|mt_req):' and auto_active
               and not exists (select 1 from public.risk_section_wants() x where x.k = risks.auto_key) loop
    update public.risks set
      auto_active = false, status = 'closed', closed_on = coalesce(closed_on, current_date),
      notes = left(case when notes like '%زال سببه%' then notes else notes || ' · زال سببه وأُغلق الخطر تلقائياً' end, 1000),
      updated_at = now()
     where id = rk.id;
    v_close := v_close + 1;
  end loop;
  return jsonb_build_object('opened', v_open, 'updated', v_upd, 'closed', v_close);
end;
$$;

-- تحديث مرة في الساعة على الأكثر يطلبه التطبيق عند فتحه (كمخاطر البرنامج الزمني)
create or replace function public.risk_refresh_sections()
returns integer
language plpgsql security definer set search_path = public
as $$
declare
  v_last timestamptz;
  v_prev text := coalesce(current_setting('rasd.auto_sync', true), '');
  r      jsonb;
begin
  if not public.is_member() then
    raise exception 'غير مصرح' using errcode = '42501';
  end if;
  select ran_at into v_last from public.risk_auto_runs where id = 1 for update;
  if v_last is not null and v_last > now() - interval '1 hour' then
    return 0;
  end if;
  insert into public.risk_auto_runs (id, ran_at) values (1, now()) on conflict (id) do update set ran_at = excluded.ran_at;
  perform set_config('rasd.auto_sync', 'on', true);
  r := public.risk_sync_sections();
  perform set_config('rasd.auto_sync', v_prev, true);
  if (r ->> 'opened')::integer + (r ->> 'closed')::integer > 0 then
    perform public.write_audit('risk.sync_sections', null, null, r, 'مخاطر الأقسام');
  end if;
  return (r ->> 'opened')::integer + (r ->> 'updated')::integer + (r ->> 'closed')::integer;
end;
$$;

revoke execute on function public.risk_action_save(uuid, uuid, jsonb), public.risk_action_status(uuid, text, text),
  public.risk_action_delete(uuid), public.risk_refresh_sections() from public, anon;
grant execute on function public.risk_action_save(uuid, uuid, jsonb), public.risk_action_status(uuid, text, text),
  public.risk_action_delete(uuid), public.risk_refresh_sections() to authenticated;
revoke execute on function public.risk_section_wants(), public.risk_sync_sections() from public, anon, authenticated;
