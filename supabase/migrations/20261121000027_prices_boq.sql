-- =====================================================================
--  الترحيل 27: لائحة الأسعار الاسترشادية ومُعِدّ المقايسات
--   1. price_lists: اللوائح (السنة والفصول ومصدرها). بياناتها في الترحيل 28.
--   2. price_items: بنود اللائحة (العناوين والبنود المسعّرة والملاحظات) مع البند الأم المباشر،
--      ويحسب price_rebuild القسم ومجموعة الأعمال والوصف الكامل بسياق البنود الأم ونص البحث.
--   3. price_search: البحث برقم البند (البند وما تحته) أو بكلمات من الوصف (كل الكلمات بعد توحيد الحروف).
--   4. boq_sheets: المقايسات المعدّة من اللائحة (البنود والكميات والملاحظات)، تُحفظ وتُفتح وتُصدَّر.
--      الكتابة عبر save_boq وdelete_boq بصلاحية المقايسات نفسها (doc_can_edit('boq', …)) وتُسجَّل في سجل التدقيق.
--      الوصف والوحدة والسعر تؤخذ من اللائحة في القاعدة عند الحفظ، لا مما يرسله التطبيق.
--  القراءة لكل الأعضاء. يُشغَّل بعد 20261121000026_audited_writes.sql. إعادة تشغيله آمنة.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. توحيد النص للبحث: الهمزات والتاء المربوطة والألف المقصورة والتشكيل والتطويل والأرقام الهندية
-- ---------------------------------------------------------------------
create or replace function public.price_norm(p text)
returns text
language sql immutable parallel safe set search_path = public
as $$
  select btrim(regexp_replace(
    translate(lower(coalesce(p, '')),
              'أإآٱىةؤئ٠١٢٣٤٥٦٧٨٩۰۱۲۳۴۵۶۷۸۹ـًٌٍَُِّْٰ',
              'اااايهوي01234567890123456789'),
    '[^0-9a-zء-ي.]+', ' ', 'g'))
$$;

-- ---------------------------------------------------------------------
-- 2. اللوائح وبنودها
-- ---------------------------------------------------------------------
create table if not exists public.price_lists (
  id         text primary key check (id ~ '^[a-z0-9_-]{2,40}$'),
  title      text not null check (length(btrim(title)) between 2 and 200),
  year       integer not null check (year between 2000 and 2100),
  source     text not null default '' check (length(source) <= 300),
  chapters   jsonb not null default '[]' check (jsonb_typeof(chapters) = 'array'),
  currency   text not null default 'دينار' check (length(currency) <= 20),
  active     boolean not null default true,
  created_at timestamptz not null default now()
);

create table if not exists public.price_items (
  list_id       text not null references public.price_lists (id) on delete cascade,
  seq           integer not null check (seq > 0),
  chapter       text not null check (length(chapter) between 2 and 40),
  code          text not null default '' check (length(code) <= 30),
  parent_seq    integer,
  kind          text not null check (kind in ('heading', 'item', 'note')),
  description   text not null check (length(description) <= 6000),
  unit          text not null default '' check (length(unit) <= 20),
  unit_inferred boolean not null default false,
  price         numeric(14, 3) check (price >= 0),
  section       text not null default '',
  grp           text not null default '',
  full_desc     text not null default '',
  desc_norm     text not null default '',
  search_text   text not null default '',
  primary key (list_id, seq),
  check ((kind = 'item') = (price is not null))
);
create index if not exists price_items_parent_idx on public.price_items (list_id, parent_seq);
create index if not exists price_items_code_idx on public.price_items (list_id, chapter, code);

-- يحسب القسم (البند الأم الأعلى) ومجموعة الأعمال (البنود الأم التي تبدأ بـ«أعمال») والوصف الكامل
-- (البنود الأم الأخرى ثم وصف البند) ونص البحث، من سلسلة البنود الأم عبر parent_seq.
create or replace function public.price_rebuild(p_list text)
returns integer
language plpgsql security definer set search_path = public
as $$
declare
  n integer;
begin
  with recursive chain(item, aseq) as (
    select seq, parent_seq from public.price_items where list_id = p_list and parent_seq is not null
    union all
    select c.item, p.parent_seq
      from chain c join public.price_items p on p.list_id = p_list and p.seq = c.aseq
     where p.parent_seq is not null
  ), info as (
    select c.item, p.seq, p.description,
           p.code !~ '\.' as top,
           p.description ~ '^(أعمال|اعمال|الأعمال|الاعمال)' as is_group
      from chain c join public.price_items p on p.list_id = p_list and p.seq = c.aseq
  ), agg as (
    select item,
           max(description) filter (where top) as section,
           string_agg(description, ' › ' order by seq) filter (where not top and is_group) as grp,
           string_agg(description, ' — ' order by seq) filter (where not top and not is_group) as ctx
      from info group by item
  )
  update public.price_items i set
    section   = coalesce(a.section, ''),
    grp       = coalesce(a.grp, ''),
    full_desc = case when a.ctx is null then i.description else a.ctx || ' — ' || i.description end
    from public.price_items s left join agg a on a.item = s.seq
   where s.list_id = p_list and i.list_id = p_list and i.seq = s.seq;
  update public.price_items set
    desc_norm   = public.price_norm(description),
    search_text = public.price_norm(code || ' ' || full_desc || ' ' || grp || ' ' || section || ' ' || unit)
   where list_id = p_list;
  get diagnostics n = row_count;
  return n;
end;
$$;

-- البحث: رقم بند (مثل 7.2 أو 1.10.3) يعيد البند وما تحته بعناوينه بترتيب اللائحة؛ وغير ذلك كلمات يجب أن تظهر
-- كلها في نص البحث للبنود المسعّرة، وتتقدّم البنود التي تظهر الكلمات في وصفها نفسه.
create or replace function public.price_search(p_list text, p_q text, p_chapter text default null, p_limit integer default 60)
returns setof public.price_items
language plpgsql stable set search_path = public
as $$
declare
  q    text := btrim(coalesce(p_q, ''));
  lim  integer := least(greatest(coalesce(p_limit, 60), 1), 300);
  w    text[];
begin
  if q = '' then
    return;
  end if;
  q := translate(q, '٠١٢٣٤٥٦٧٨٩۰۱۲۳۴۵۶۷۸۹', '01234567890123456789');
  if q ~ '^\d+(\.\d+)*\.?$' then
    q := rtrim(q, '.');
    return query
      select * from public.price_items i
       where i.list_id = p_list and (p_chapter is null or i.chapter = p_chapter)
         and (i.code = q or i.code like q || '.%')
       order by i.seq
       limit lim;
    return;
  end if;
  select array_agg(case when length(x) >= 5 and x like 'ال%' then substr(x, 3) else x end)
    into w
    from unnest(string_to_array(public.price_norm(q), ' ')) x
   where length(x) >= 2 or x ~ '^\d+$';
  if w is null then
    return;
  end if;
  return query
    select i.* from public.price_items i
     where i.list_id = p_list and i.kind = 'item' and (p_chapter is null or i.chapter = p_chapter)
       and not exists (select 1 from unnest(w) x where position(x in i.search_text) = 0)
     order by (select count(*) from unnest(w) x where position(x in i.desc_norm) > 0) desc, i.seq
     limit lim;
end;
$$;

-- ---------------------------------------------------------------------
-- 3. المقايسات المعدّة من اللائحة
-- ---------------------------------------------------------------------
create table if not exists public.boq_sheets (
  id             uuid primary key default gen_random_uuid(),
  project_id     uuid references public.projects (id) on delete set null,
  origin_project uuid references public.projects (id) on delete set null,
  list_id        text not null references public.price_lists (id),
  title          text not null check (length(btrim(title)) between 2 and 200),
  ref_no         text not null default '' check (length(ref_no) <= 60),
  notes          text not null default '' check (length(notes) <= 2000),
  show_prices    boolean not null default true,
  lines          jsonb not null default '[]' check (jsonb_typeof(lines) = 'array'),
  line_count     integer not null default 0,
  total          numeric(18, 3) not null default 0,
  created_at     timestamptz not null default now(),
  created_by     uuid references public.profiles (id) on delete set null,
  updated_at     timestamptz not null default now(),
  updated_by     uuid references public.profiles (id) on delete set null
);
create index if not exists boq_sheets_project_idx    on public.boq_sheets (project_id);
create index if not exists boq_sheets_origin_idx     on public.boq_sheets (origin_project);
create index if not exists boq_sheets_list_idx       on public.boq_sheets (list_id);
create index if not exists boq_sheets_created_by_idx on public.boq_sheets (created_by);
create index if not exists boq_sheets_updated_by_idx on public.boq_sheets (updated_by);

-- حفظ مقايسة (جديدة أو تعديل). البنود: {seq, qty, notes} من اللائحة، أو بند حر {desc, unit, price, code, qty, notes}.
create or replace function public.save_boq(p_id uuid, p_data jsonb)
returns uuid
language plpgsql security definer set search_path = public
as $$
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

-- حذف مقايسة: المدير، أو من أعدّها ما دامت له صلاحية المقايسات
create or replace function public.delete_boq(p_id uuid)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  r public.boq_sheets;
begin
  select * into r from public.boq_sheets where id = p_id for update;
  if not found then
    raise exception 'المقايسة غير موجودة' using errcode = 'P0002';
  end if;
  if not (public.is_director() or (r.created_by = auth.uid() and public.doc_can_edit('boq', r.project_id))) then
    raise exception 'حذف المقايسة لمن أعدّها أو لمدير المكتب' using errcode = '42501';
  end if;
  delete from public.boq_sheets where id = p_id;
  perform public.write_audit('boq.delete', r.project_id, null,
    jsonb_build_object('title', r.title, 'lines', r.line_count, 'total', r.total));
end;
$$;

-- المقايسة تتبع العقد عند الدمج وتعود بفكّه
create or replace function public.boq_follow_merge()
returns trigger
language plpgsql security definer set search_path = public
as $$
begin
  if new.merged_into is not null and old.merged_into is null then
    update public.boq_sheets set project_id = new.merged_into, origin_project = coalesce(origin_project, new.id)
     where project_id = new.id;
  elsif new.merged_into is null and old.merged_into is not null then
    update public.boq_sheets set project_id = new.id, origin_project = null
     where project_id = old.merged_into and origin_project = new.id;
  end if;
  return null;
end;
$$;
drop trigger if exists projects_boq_follow_merge on public.projects;
create trigger projects_boq_follow_merge
  after update of merged_into on public.projects
  for each row when (old.merged_into is distinct from new.merged_into)
  execute function public.boq_follow_merge();

-- ---------------------------------------------------------------------
-- 4. الصلاحيات: القراءة للأعضاء، ولا كتابة مباشرة
-- ---------------------------------------------------------------------
do $$
declare
  t text;
begin
  foreach t in array array['price_lists', 'price_items', 'boq_sheets'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('drop policy if exists %I on public.%I', t || '_read', t);
    execute format('create policy %I on public.%I for select to authenticated using ((select public.is_member()))', t || '_read', t);
    execute format('revoke all on public.%I from anon', t);
    execute format('revoke insert, update, delete, truncate on public.%I from authenticated', t);
    execute format('grant select on public.%I to authenticated', t);
    execute format('grant all on public.%I to service_role', t);
  end loop;
  if not exists (select 1 from pg_publication_tables
                 where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'boq_sheets') then
    alter publication supabase_realtime add table public.boq_sheets;
  end if;
end $$;

revoke execute on function public.price_rebuild(text), public.boq_follow_merge() from public, anon, authenticated;
revoke execute on function public.price_norm(text), public.price_search(text, text, text, integer),
  public.save_boq(uuid, jsonb), public.delete_boq(uuid) from public, anon;
grant execute on function public.price_norm(text), public.price_search(text, text, text, integer),
  public.save_boq(uuid, jsonb), public.delete_boq(uuid) to authenticated;
