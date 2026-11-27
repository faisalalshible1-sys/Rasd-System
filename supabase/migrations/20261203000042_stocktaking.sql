-- =====================================================================
-- الإصدار 1.11.0 (الترحيل 42): الجرد الدوري بالتسوية في قسم المخازن
--
--  جلسة جرد لكل مخزن (كلية أو لتصنيف بعينه) داخل قسم المخازن نفسه وبصلاحياته (الترحيل 38) دون نطاقات جديدة:
--  1. البدء: أمين المخزن أو مدير المخازن أو المدير يبدأ جلسة برقم CN-سنة-تسلسل، فتُلتقط أرصدة الأصناف الفعلية
--     «الدفترية» عند البدء بنداً بنداً (بالوحدة الأساسية). جلسة واحدة قائمة (مفتوحة أو مقدَّمة) لكل مخزن في آن.
--  2. العدّ: يكتب العادّ الكمية المعدودة لكل بند، ويضيف ما وجده من أصناف لا رصيد لها، وتاريخ انتهاء ما يتتبع الصلاحية
--     إن وجد زيادة. إخفاء الرصيد الدفتري أثناء العدّ تيسير في الشاشة وليس ضابطاً أمنياً (رصيد المخزن مقروء لأمينه).
--  3. التقديم: بعد عدّ كل البنود. 4. القرار: مدير المخازن أو المدير يعتمد أو يعيد للعدّ بسبب، مع فصل المهام:
--     لا يعتمد الجلسة من أنشأها أو قدّمها ما دام فصل المهام مفعّلاً.
--  5. الاعتماد: الفرق لكل بند = المعدود − الرصيد الفعلي وقت الاعتماد (لا وقت البدء، فحركة المخزن بين الاثنين لا تُحسب فرقاً)،
--     فتتولّد تسوية AD معتمدة (بحجز النقص) بالفروق وحدها تُرحَّل بالإجراء المعتاد للمستندات؛ وإن لم يكن فرق أُغلقت الجلسة بلا مستند.
--  يُشغَّل بعد 20261202000041_procurement.sql، وإعادة تشغيله آمنة. التراجع: supabase/rollbacks/20261203000042_stocktaking_down.sql
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. الجداول
-- ---------------------------------------------------------------------
create table if not exists public.st_counts (
  id            uuid primary key default gen_random_uuid(),
  count_no      text not null,
  warehouse_id  uuid not null references public.st_warehouses (id) on delete restrict,
  category_id   uuid references public.st_categories (id) on delete restrict,
  status        text not null default 'open' check (status in ('open', 'submitted', 'closed', 'cancelled')),
  blind         boolean not null default true,
  note          text not null default '' check (length(note) <= 500),
  decision_note text not null default '' check (length(decision_note) <= 500),
  adjust_doc_id uuid references public.st_docs (id) on delete set null,
  created_at    timestamptz not null default now(),
  created_by    uuid references public.profiles (id) on delete set null,
  updated_at    timestamptz not null default now(),
  submitted_at  timestamptz,
  submitted_by  uuid references public.profiles (id) on delete set null,
  decided_at    timestamptz,
  decided_by    uuid references public.profiles (id) on delete set null
);
create unique index if not exists st_counts_no_uq on public.st_counts (count_no);
-- جلسة قائمة واحدة لكل مخزن
create unique index if not exists st_counts_one_live on public.st_counts (warehouse_id) where status in ('open', 'submitted');
create index if not exists st_counts_category_idx on public.st_counts (category_id);
create index if not exists st_counts_doc_idx on public.st_counts (adjust_doc_id);
create index if not exists st_counts_created_by_idx on public.st_counts (created_by);
create index if not exists st_counts_submitted_by_idx on public.st_counts (submitted_by);
create index if not exists st_counts_decided_by_idx on public.st_counts (decided_by);
create index if not exists st_counts_date_idx on public.st_counts (created_at desc);

create table if not exists public.st_count_lines (
  id          uuid primary key default gen_random_uuid(),
  count_id    uuid not null references public.st_counts (id) on delete cascade,
  item_id     uuid not null references public.st_items (id) on delete restrict,
  system_qty  numeric(18, 3) not null default 0 check (system_qty >= 0),
  counted_qty numeric(18, 3) check (counted_qty is null or (counted_qty >= 0 and counted_qty <= 100000000)),
  expiry_date date,
  batch_no    text not null default '' check (length(batch_no) <= 40),
  note        text not null default '' check (length(note) <= 300),
  variance    numeric(18, 3),
  constraint st_count_lines_uq unique (count_id, item_id)
);
create index if not exists st_count_lines_item_idx on public.st_count_lines (item_id);

-- ---------------------------------------------------------------------
-- 2. الدوال
-- ---------------------------------------------------------------------
-- يبدأ جلسة جرد: p_data = {warehouse_id, category_id?, blind?, note?}
create or replace function public.st_count_start(p_data jsonb)
returns uuid
language plpgsql security definer set search_path = public
as $$
declare
  v_wh   uuid;
  v_cat  uuid;
  v_id   uuid;
  v_year integer := extract(year from (now() at time zone 'Africa/Tripoli'))::integer;
  v_n    integer;
begin
  if jsonb_typeof(coalesce(p_data, 'null'::jsonb)) <> 'object' then
    raise exception 'بيانات غير صالحة' using errcode = '22023';
  end if;
  v_wh := public.st_uuid(p_data, 'warehouse_id');
  if v_wh is null or not exists (select 1 from public.st_warehouses where id = v_wh and active) then
    raise exception 'اختر المخزن' using errcode = '22023';
  end if;
  if not public.st_can_move(v_wh) then
    raise exception 'جرد هذا المخزن لأمينه أو لمدير المخازن' using errcode = '42501';
  end if;
  v_cat := public.st_uuid(p_data, 'category_id');
  if v_cat is not null and not exists (select 1 from public.st_categories where id = v_cat) then
    raise exception 'التصنيف غير موجود' using errcode = '22023';
  end if;
  if exists (select 1 from public.st_counts where warehouse_id = v_wh and status in ('open', 'submitted')) then
    raise exception 'في هذا المخزن جلسة جرد قائمة؛ أغلقها أو ألغِها أولاً' using errcode = '22023';
  end if;
  insert into public.st_counts (count_no, warehouse_id, category_id, blind, note, created_by)
  values (public.st_next_no('count:CN', 'CN', v_year), v_wh, v_cat,
          case when jsonb_typeof(p_data -> 'blind') = 'boolean' then (p_data ->> 'blind')::boolean else true end,
          public.st_text(p_data, 'note', 500), auth.uid())
  returning id into v_id;
  insert into public.st_count_lines (count_id, item_id, system_qty)
  select v_id, s.item_id, s.on_hand
    from public.st_stock s join public.st_items i on i.id = s.item_id
   where s.warehouse_id = v_wh and s.on_hand > 0 and i.active and (v_cat is null or i.category_id = v_cat);
  get diagnostics v_n = row_count;
  if v_n = 0 then
    raise exception 'لا أصناف برصيد في هذا المخزن%', case when v_cat is null then '' else ' ضمن التصنيف المختار' end
      using errcode = '22023';
  end if;
  perform public.write_audit('stores.count_start', null, null,
    jsonb_build_object('id', v_id, 'warehouse', v_wh, 'category', v_cat, 'items', v_n), (select count_no from public.st_counts where id = v_id));
  return v_id;
end;
$$;

-- يحفظ المعدود: p_lines = [{item_id, counted_qty (أو null لمسحه), expiry_date?, batch_no?, note?}]؛ صنف جديد يُضاف بلا رصيد دفتري
create or replace function public.st_count_save(p_id uuid, p_lines jsonb)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  c    public.st_counts;
  l    jsonb;
  v_it public.st_items;
  v_q  numeric;
  v_ex date;
  n    integer := 0;
begin
  select * into c from public.st_counts where id = p_id for update;
  if not found then
    raise exception 'جلسة الجرد غير موجودة' using errcode = 'P0002';
  end if;
  if c.status <> 'open' then
    raise exception 'لا يُعدَّل العدّ إلا في الجلسة المفتوحة' using errcode = '22023';
  end if;
  if not public.st_can_move(c.warehouse_id) then
    raise exception 'جرد هذا المخزن لأمينه أو لمدير المخازن' using errcode = '42501';
  end if;
  if jsonb_typeof(coalesce(p_lines, 'null'::jsonb)) <> 'array' or jsonb_array_length(p_lines) = 0 then
    raise exception 'لا بنود للحفظ' using errcode = '22023';
  end if;
  if jsonb_array_length(p_lines) > 1000 then
    raise exception 'الحد الأعلى 1000 بند في الدفعة' using errcode = '22023';
  end if;
  for l in select x from jsonb_array_elements(p_lines) x loop
    n := n + 1;
    select * into v_it from public.st_items where id = public.st_uuid(l, 'item_id');
    if not found then
      raise exception 'البند %: الصنف غير موجود', n using errcode = '22023';
    end if;
    if c.category_id is not null and v_it.category_id <> c.category_id then
      raise exception 'البند %: «%» خارج تصنيف هذه الجلسة', n, v_it.name using errcode = '22023';
    end if;
    if l -> 'counted_qty' is null or jsonb_typeof(l -> 'counted_qty') = 'null' then
      v_q := null;
    elsif jsonb_typeof(l -> 'counted_qty') <> 'number' then
      raise exception 'البند %: الكمية رقم', n using errcode = '22023';
    else
      v_q := round((l ->> 'counted_qty')::numeric, 3);
      if v_q < 0 or v_q > 100000000 then
        raise exception 'البند %: الكمية المعدودة من صفر فأكثر', n using errcode = '22023';
      end if;
    end if;
    v_ex := case when v_it.tracks_expiry then nullif(l ->> 'expiry_date', '')::date end;
    if not exists (select 1 from public.st_count_lines where count_id = p_id and item_id = v_it.id) then
      if not v_it.active then
        raise exception 'البند %: الصنف «%» موقوف', n, v_it.name using errcode = '22023';
      end if;
      insert into public.st_count_lines (count_id, item_id, system_qty)
      values (p_id, v_it.id, coalesce((select on_hand from public.st_stock where warehouse_id = c.warehouse_id and item_id = v_it.id), 0));
    end if;
    update public.st_count_lines
       set counted_qty = v_q, expiry_date = v_ex, batch_no = case when v_ex is null then '' else public.st_text(l, 'batch_no', 40) end,
           note = public.st_text(l, 'note', 300)
     where count_id = p_id and item_id = v_it.id;
  end loop;
  update public.st_counts set updated_at = now() where id = p_id;
  perform public.write_audit('stores.count_save', null, null, jsonb_build_object('id', p_id, 'lines', n), c.count_no);
end;
$$;

-- يقدّم الجلسة بعد عدّ كل بنودها
create or replace function public.st_count_submit(p_id uuid)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  c public.st_counts;
  v_left integer;
begin
  select * into c from public.st_counts where id = p_id for update;
  if not found then
    raise exception 'جلسة الجرد غير موجودة' using errcode = 'P0002';
  end if;
  if c.status <> 'open' then
    raise exception 'لا تُقدَّم إلا الجلسة المفتوحة' using errcode = '22023';
  end if;
  if not public.st_can_move(c.warehouse_id) then
    raise exception 'جرد هذا المخزن لأمينه أو لمدير المخازن' using errcode = '42501';
  end if;
  select count(*) into v_left from public.st_count_lines where count_id = p_id and counted_qty is null;
  if v_left > 0 then
    raise exception 'بقي % بند لم يُعدّ؛ اكتب كميته (صفراً إن لم يوجد)', v_left using errcode = '22023';
  end if;
  update public.st_counts set status = 'submitted', submitted_at = now(), submitted_by = auth.uid(), decision_note = '', updated_at = now()
   where id = p_id;
  perform public.write_audit('stores.count_submit', null, null, jsonb_build_object('id', p_id), c.count_no);
end;
$$;

-- يعيد الجلسة المقدَّمة للعدّ بسبب (مدير المخازن أو المدير)
create or replace function public.st_count_return(p_id uuid, p_note text)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  c public.st_counts;
  v_note text := btrim(coalesce(p_note, ''));
begin
  select * into c from public.st_counts where id = p_id for update;
  if not found then
    raise exception 'جلسة الجرد غير موجودة' using errcode = 'P0002';
  end if;
  if c.status <> 'submitted' then
    raise exception 'تُعاد الجلسة المقدَّمة وحدها' using errcode = '22023';
  end if;
  if not public.st_can_approve() then
    raise exception 'قرار الجرد لمدير المخازن أو المدير' using errcode = '42501';
  end if;
  if length(v_note) < 3 or length(v_note) > 500 then
    raise exception 'اكتب سبب الإعادة (3 إلى 500 حرف)' using errcode = '22023';
  end if;
  update public.st_counts set status = 'open', decision_note = v_note, decided_at = now(), decided_by = auth.uid(), updated_at = now()
   where id = p_id;
  perform public.write_audit('stores.count_return', null, null, jsonb_build_object('id', p_id, 'note', v_note), c.count_no);
end;
$$;

-- يلغي جلسة مفتوحة أو مقدَّمة
create or replace function public.st_count_cancel(p_id uuid, p_note text default '')
returns void
language plpgsql security definer set search_path = public
as $$
declare
  c public.st_counts;
  v_note text := btrim(coalesce(p_note, ''));
begin
  select * into c from public.st_counts where id = p_id for update;
  if not found then
    raise exception 'جلسة الجرد غير موجودة' using errcode = 'P0002';
  end if;
  if c.status not in ('open', 'submitted') then
    raise exception 'لا تُلغى الجلسة المنتهية' using errcode = '22023';
  end if;
  if not (public.st_can_move(c.warehouse_id) or public.st_can_approve()) then
    raise exception 'إلغاء جرد هذا المخزن لأمينه أو لمدير المخازن' using errcode = '42501';
  end if;
  if length(v_note) > 500 or (c.status = 'submitted' and length(v_note) < 3) then
    raise exception 'اكتب سبب إلغاء الجلسة المقدَّمة (3 إلى 500 حرف)' using errcode = '22023';
  end if;
  update public.st_counts set status = 'cancelled', decision_note = v_note, decided_at = now(), decided_by = auth.uid(), updated_at = now()
   where id = p_id;
  perform public.write_audit('stores.count_cancel', null, null, jsonb_build_object('id', p_id, 'note', v_note), c.count_no);
end;
$$;

-- يعتمد الجلسة المقدَّمة: يحسب الفروق على الرصيد الفعلي الآن ويولّد تسوية معتمدة بها (إن وُجدت فروق)
create or replace function public.st_count_approve(p_id uuid, p_note text default '')
returns uuid
language plpgsql security definer set search_path = public
as $$
declare
  c       public.st_counts;
  l       record;
  v_note  text := btrim(coalesce(p_note, ''));
  v_sep   boolean := public.st_setting_bool('separation', true);
  v_on    numeric;
  v_var   numeric;
  v_lines jsonb := '[]'::jsonb;
  v_doc   uuid;
  v_gain  integer := 0;
  v_loss  integer := 0;
begin
  select * into c from public.st_counts where id = p_id for update;
  if not found then
    raise exception 'جلسة الجرد غير موجودة' using errcode = 'P0002';
  end if;
  if c.status <> 'submitted' then
    raise exception 'تُعتمد الجلسة المقدَّمة وحدها' using errcode = '22023';
  end if;
  if not public.st_can_approve() then
    raise exception 'اعتماد الجرد لمدير المخازن أو المدير' using errcode = '42501';
  end if;
  if v_sep and auth.uid() in (c.created_by, c.submitted_by) then
    raise exception 'فصل المهام: لا يعتمد الجرد من أنشأه أو قدّمه' using errcode = '42501';
  end if;
  if length(v_note) > 500 then
    raise exception 'الملاحظة حتى 500 حرف' using errcode = '22023';
  end if;
  for l in select cl.*, i.name, i.tracks_expiry from public.st_count_lines cl join public.st_items i on i.id = cl.item_id
            where cl.count_id = p_id order by i.name loop
    select coalesce(on_hand, 0) into v_on from public.st_stock where warehouse_id = c.warehouse_id and item_id = l.item_id;
    v_on := coalesce(v_on, 0);
    v_var := round(l.counted_qty - v_on, 3);
    update public.st_count_lines set variance = v_var where id = l.id;
    if v_var <> 0 then
      if v_var > 0 and l.tracks_expiry and l.expiry_date is null then
        raise exception 'زيادة «%» تحتاج تاريخ انتهاء صلاحيتها؛ أعد الجلسة للعدّ', l.name using errcode = '22023';
      end if;
      v_lines := v_lines || jsonb_build_array(jsonb_build_object('item_id', l.item_id, 'qty', v_var,
                   'expiry_date', case when v_var > 0 then l.expiry_date end, 'batch_no', l.batch_no,
                   'note', 'جرد ' || c.count_no));
      if v_var > 0 then v_gain := v_gain + 1; else v_loss := v_loss + 1; end if;
    end if;
  end loop;
  if jsonb_array_length(v_lines) > 0 then
    v_doc := public.st_save_doc(null, jsonb_build_object('kind', 'adjust', 'warehouse_id', c.warehouse_id,
               'ref_no', c.count_no, 'note', 'تسوية جرد ' || c.count_no, 'lines', v_lines));
    -- تسوية معتمدة بقرار الجرد نفسه: يحجز النقص ثم يرحّلها أمين المخزن أو مدير المخازن بالإجراء المعتاد
    perform public.st_reserve(v_doc, 1, true);
    update public.st_docs set status = 'approved', submitted_at = c.submitted_at, submitted_by = c.submitted_by,
                              approved_at = now(), approved_by = auth.uid(), decision_note = 'تسوية جرد ' || c.count_no,
                              updated_at = now(), updated_by = auth.uid()
     where id = v_doc;
  end if;
  update public.st_counts set status = 'closed', decision_note = v_note, decided_at = now(), decided_by = auth.uid(),
                              adjust_doc_id = v_doc, updated_at = now()
   where id = p_id;
  perform public.write_audit('stores.count_approve', null, null,
    jsonb_build_object('id', p_id, 'count_no', c.count_no, 'gains', v_gain, 'losses', v_loss, 'doc', v_doc, 'note', v_note), c.count_no);
  return v_doc;
end;
$$;

-- ---------------------------------------------------------------------
-- 3. الصلاحيات
-- ---------------------------------------------------------------------
alter table public.st_counts enable row level security;
alter table public.st_count_lines enable row level security;

drop policy if exists st_counts_read on public.st_counts;
create policy st_counts_read on public.st_counts for select to authenticated
  using ((select public.st_sees_all()) or warehouse_id = any ((select public.st_my_warehouses())::uuid[]));
drop policy if exists st_count_lines_read on public.st_count_lines;
create policy st_count_lines_read on public.st_count_lines for select to authenticated
  using (exists (select 1 from public.st_counts c where c.id = count_id));

revoke all on public.st_counts, public.st_count_lines from anon, authenticated;
grant select on public.st_counts, public.st_count_lines to authenticated;
grant all on public.st_counts, public.st_count_lines to service_role;

revoke execute on function public.st_count_start(jsonb), public.st_count_save(uuid, jsonb), public.st_count_submit(uuid),
  public.st_count_return(uuid, text), public.st_count_cancel(uuid, text), public.st_count_approve(uuid, text) from public, anon;
grant execute on function public.st_count_start(jsonb), public.st_count_save(uuid, jsonb), public.st_count_submit(uuid),
  public.st_count_return(uuid, text), public.st_count_cancel(uuid, text), public.st_count_approve(uuid, text) to authenticated;

do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime')
     and not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'st_counts') then
    alter publication supabase_realtime add table public.st_counts;
  end if;
end $$;
