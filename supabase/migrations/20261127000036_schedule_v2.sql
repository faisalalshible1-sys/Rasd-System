-- =====================================================================
--  الترحيل 36: البرنامج الزمني من المقايسة (الإصدار 1.5.0)
--   1. استيراد المقايسات من ملفات Excel أو PDF: مصدر المقايسة واسم ملفها (التطبيق يستخرج البنود ويراجعها المستخدم قبل الحفظ).
--   2. معدلات الإنتاجية (كمية في اليوم لكل وحدة وكلمة في الوصف) بتاريخ سريانها؛ لا يُعدَّل معدل، بل يُضاف إصدار جديد له.
--      توليد البرنامج يقترح مدة البند = ⌈الكمية ÷ المعدل⌉، وبالقيمة كما كان إن لم يطابقه معدل.
--   3. العلاقات بين الأنشطة: نهاية←بداية، بداية←بداية، نهاية←نهاية، بداية←نهاية، بفترة انتظار (موجبة أو سالبة)،
--      و«لا يبدأ قبل» تاريخ؛ وتُرحَّل «يتبع البند» القديمة علاقاتِ نهاية←بداية دون تغيير أي تاريخ.
--   4. إصدارات البرنامج: يُحفظ كل إصدار معتمد كاملاً للمقارنة بالحالي وبالتنفيذ الفعلي.
--   5. صلاحيات دقيقة: عرض البرنامج، وإضافة الأنشطة، وتعديل المدد، وتعديل التواريخ والعلاقات، واعتماد البرنامج.
--   لا يحذف بيانات ولا يغيّر تاريخاً قائماً. التراجع: supabase/rollbacks/20261127000036_schedule_v2_down.sql
--  يُشغَّل بعد 20261126000035_contract_files.sql. إعادة تشغيله آمنة.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. مصدر المقايسة
-- ---------------------------------------------------------------------
alter table public.boq_sheets add column if not exists source text not null default 'builder';
alter table public.boq_sheets add column if not exists source_file text not null default '';
alter table public.boq_sheets drop constraint if exists boq_sheets_source_check;
alter table public.boq_sheets add constraint boq_sheets_source_check check (source in ('builder', 'import') and length(source_file) <= 200);

-- يُحفظ معها مصدرها: مُعِدّ المقايسات أو ملف مستورد بعد مراجعته
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
                                   source, source_file, created_by, updated_by)
    values (v_proj, v_list, v_title, public.jtext(p_data, 'ref_no', 60, 'الرقم الإشاري'), public.jtext(p_data, 'notes', 2000, 'ملاحظات'),
            case when p_data ? 'show_prices' then public.jbool(p_data, 'show_prices') else true end, v_lines, jsonb_array_length(v_lines), round(v_total, 3),
            public.jpick(p_data, 'source', array['builder', 'import'], 'builder', 'مصدر المقايسة'),
            case when p_data ->> 'source' = 'import' then public.jtext(p_data, 'source_file', 200, 'اسم الملف') else '' end,
            auth.uid(), auth.uid())
    returning * into new_row;
    perform public.write_audit('boq.create', v_proj, null,
      jsonb_build_object('title', v_title, 'lines', new_row.line_count, 'total', new_row.total, 'source', new_row.source,
                         'file', new_row.source_file));
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

-- ---------------------------------------------------------------------
-- 2. معدلات الإنتاجية
-- ---------------------------------------------------------------------
-- تطبيع الوحدة (م3 = م٣ = م 3) والنص (الهمزات والتاء المربوطة والتشكيل) للمطابقة
create or replace function public.pm_unit_norm(p text)
returns text
language sql immutable set search_path = public
as $$
  select lower(regexp_replace(translate(coalesce(p, ''), '٠١٢٣٤٥٦٧٨٩۰۱۲۳۴۵۶۷۸۹²³', '0123456789012345678923'), '[[:space:]./_-]', '', 'g'))
$$;

create or replace function public.pm_text_norm(p text)
returns text
language sql immutable set search_path = public
as $$
  select btrim(regexp_replace(lower(translate(regexp_replace(coalesce(p, ''), '[ـً-ْٰ]', '', 'g'), 'أإآٱةى', 'ااااهي')), '[[:space:]]+', ' ', 'g'))
$$;

create table if not exists public.pm_rates (
  id           uuid primary key default gen_random_uuid(),
  unit         text not null check (length(btrim(unit)) between 1 and 20),
  unit_key     text generated always as (public.pm_unit_norm(unit)) stored,
  keyword      text not null default '' check (length(keyword) <= 60),
  keyword_key  text generated always as (public.pm_text_norm(keyword)) stored,
  rate         numeric(14, 3) not null check (rate > 0 and rate <= 1000000000),
  label        text not null default '' check (length(label) <= 120),
  active       boolean not null default true,
  valid_from   date not null default current_date,
  note         text not null default '' check (length(note) <= 300),
  created_at   timestamptz not null default now(),
  created_by   uuid references public.profiles (id) on delete set null
);
create index if not exists pm_rates_key_idx        on public.pm_rates (unit_key, keyword_key, valid_from desc);
create index if not exists pm_rates_created_by_idx on public.pm_rates (created_by);

-- المعدل الساري لكل وحدة وكلمة: أحدث إصدار بلغ تاريخ سريانه
create or replace function public.pm_rates_current()
returns setof public.pm_rates
language sql stable security definer set search_path = public
as $$
  select distinct on (unit_key, keyword_key) *
    from public.pm_rates
   where valid_from <= current_date
   order by unit_key, keyword_key, valid_from desc, created_at desc
$$;

-- المعدل المطابق لبند: الوحدة نفسها، وأطول كلمة يحويها الوصف (أو المعدل العام للوحدة بلا كلمة)
create or replace function public.pm_rate_for(p_unit text, p_desc text)
returns numeric
language sql stable security definer set search_path = public
as $$
  select r.rate
    from public.pm_rates_current() r
   where r.active and r.unit_key <> '' and r.unit_key = public.pm_unit_norm(p_unit)
     and (r.keyword_key = '' or strpos(public.pm_text_norm(p_desc), r.keyword_key) > 0)
   order by length(r.keyword_key) desc, r.valid_from desc
   limit 1
$$;

-- المدة المقترحة بالإنتاجية = ⌈الكمية ÷ المعدل⌉ بين يوم و3650 يوماً؛ ولا شيء دون كمية أو معدل
create or replace function public.pm_rate_days(p_unit text, p_desc text, p_qty numeric)
returns integer
language sql stable security definer set search_path = public
as $$
  select case when coalesce(p_qty, 0) > 0 and x.r is not null then least(3650, greatest(1, ceil(p_qty / x.r)::integer)) end
    from (select public.pm_rate_for(p_unit, p_desc) as r) x
$$;

-- من يعتمد المعدلات: المدير ورئيس الشؤون الفنية ومن مُنح «اعتماد البرنامج»
create or replace function public.pm_can_rates()
returns boolean
language sql stable security definer set search_path = public
as $$
  select public.writes_allowed() and (public.is_director() or public.is_dept_head_of('technical') or public.has_grant('docs:pm_approve'))
$$;

-- إضافة معدل أو إصدار جديد لمعدل قائم (يبقى السابق في السجل بتاريخه)
create or replace function public.save_pm_rate(p_data jsonb)
returns uuid
language plpgsql security definer set search_path = public
as $$
declare
  v_unit  text;
  v_kw    text;
  v_rate  numeric;
  v_from  date;
  v_prev  numeric;
  n       public.pm_rates;
begin
  if not public.pm_can_rates() then
    raise exception 'معدلات الإنتاجية يعتمدها مدير المكتب ورئيس الشؤون الفنية' using errcode = '42501';
  end if;
  if jsonb_typeof(coalesce(p_data, 'null'::jsonb)) <> 'object' then
    raise exception 'بيانات غير صالحة' using errcode = '22023';
  end if;
  v_unit := public.jtext(p_data, 'unit', 20, 'الوحدة');
  v_kw   := public.jtext(p_data, 'keyword', 60, 'الكلمة في الوصف');
  v_rate := public.jnum(p_data, 'rate', 0.001, 1000000000, 'المعدل');
  v_from := coalesce(public.jdate(p_data, 'valid_from', 'تاريخ السريان'), current_date);
  if public.pm_unit_norm(v_unit) = '' then
    raise exception 'اكتب الوحدة كما في المقايسة (مثل م3 أو م2 أو عدد)' using errcode = '22023';
  end if;
  if v_rate is null then
    raise exception 'اكتب المعدل: الكمية المنجزة في اليوم' using errcode = '22023';
  end if;
  if v_from < current_date - 3650 or v_from > current_date + 3650 then
    raise exception 'تاريخ السريان غير معقول' using errcode = '22023';
  end if;
  select rate into v_prev from public.pm_rates_current()
   where unit_key = public.pm_unit_norm(v_unit) and keyword_key = public.pm_text_norm(v_kw) and active;
  insert into public.pm_rates (unit, keyword, rate, label, active, valid_from, note, created_by)
  values (v_unit, v_kw, round(v_rate, 3), public.jtext(p_data, 'label', 120, 'الوصف'),
          case when p_data ? 'active' then public.jbool(p_data, 'active') else true end, v_from,
          public.jtext(p_data, 'note', 300, 'سبب التعديل'), auth.uid())
  returning * into n;
  perform public.write_audit('pm.rate_save', null, null,
    jsonb_build_object('unit', n.unit, 'keyword', n.keyword, 'rate', n.rate, 'previous', v_prev, 'valid_from', n.valid_from,
                       'active', n.active, 'note', n.note));
  return n.id;
end;
$$;

-- حذف قيد أُدخل خطأً: للمدير وحده، ويبقى أثره في سجل التدقيق
create or replace function public.delete_pm_rate(p_id uuid)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  r public.pm_rates;
begin
  if not public.is_director() then
    raise exception 'حذف قيود المعدلات لمدير المكتب وحده؛ ولإيقاف معدل أضف له إصداراً غير مفعّل' using errcode = '42501';
  end if;
  delete from public.pm_rates where id = p_id returning * into r;
  if r.id is null then
    raise exception 'القيد غير موجود' using errcode = 'P0002';
  end if;
  perform public.write_audit('pm.rate_delete', null, null,
    jsonb_build_object('unit', r.unit, 'keyword', r.keyword, 'rate', r.rate, 'valid_from', r.valid_from));
end;
$$;

-- ---------------------------------------------------------------------
-- 3. الصلاحيات الدقيقة للبرنامج الزمني
-- ---------------------------------------------------------------------
--   docs:pm_view عرض البرنامج (يُظهر قسم الشؤون الفنية بقراءة البرامج)، docs:pm_add إضافة الأنشطة وبياناتها،
--   docs:pm_duration تعديل المدد، docs:pm_dates تعديل التواريخ والعلاقات، docs:pm_approve اعتماد البرنامج وإعادة فتحه.
create or replace function public.pm_can(p_project uuid, p_what text)
returns boolean
language sql stable security definer set search_path = public
as $$
  select case p_what
    when 'approve' then public.can_approve_plan(p_project) or (public.writes_allowed() and public.has_grant('docs:pm_approve'))
    when 'add'      then public.can_prepare_plan(p_project) or (public.writes_allowed() and public.has_grant('docs:pm_add'))
    when 'duration' then public.can_prepare_plan(p_project) or (public.writes_allowed() and public.has_grant('docs:pm_duration'))
    when 'dates'    then public.can_prepare_plan(p_project) or (public.writes_allowed() and public.has_grant('docs:pm_dates'))
    else false
  end
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
    else p_scope in ('docs:boq', 'docs:letter', 'docs:design', 'supervision:reports', 'swot', 'pm:plan', 'pm:track',
                     'docs:pm_view', 'docs:pm_add', 'docs:pm_duration', 'docs:pm_dates', 'docs:pm_approve')
  end
$$;

alter table public.user_grants drop constraint if exists user_grants_scope_check;
alter table public.user_grants add constraint user_grants_scope_check check (
  scope ~ '^(form:[a-z0-9_]{1,40}|docs:(boq|letter|design|pm_view|pm_add|pm_duration|pm_dates|pm_approve)|supervision:reports|unit:[a-z_]{2,40}|swot|pm:(plan|track))$');

-- ---------------------------------------------------------------------
-- 4. العلاقات بين الأنشطة، و«لا يبدأ قبل»
-- ---------------------------------------------------------------------
alter table public.pm_items add column if not exists start_not_before date;

create table if not exists public.pm_item_links (
  id          uuid primary key default gen_random_uuid(),
  pred_id     uuid not null references public.pm_items (id) on delete cascade,
  succ_id     uuid not null references public.pm_items (id) on delete cascade,
  kind        text not null default 'FS' check (kind in ('FS', 'SS', 'FF', 'SF')),
  lag_days    integer not null default 0 check (lag_days between -3650 and 3650),
  created_at  timestamptz not null default now(),
  created_by  uuid references public.profiles (id) on delete set null,
  updated_at  timestamptz not null default now(),
  updated_by  uuid references public.profiles (id) on delete set null,
  constraint pm_item_links_pair unique (pred_id, succ_id),
  constraint pm_item_links_self check (pred_id <> succ_id)
);
create index if not exists pm_item_links_succ_idx       on public.pm_item_links (succ_id);
create index if not exists pm_item_links_created_by_idx on public.pm_item_links (created_by);
create index if not exists pm_item_links_updated_by_idx on public.pm_item_links (updated_by);

-- «يتبع البند» القديمة علاقاتُ نهاية←بداية بلا انتظار: الحساب الجديد يعطي التواريخ نفسها
insert into public.pm_item_links (pred_id, succ_id, kind, lag_days, created_by, updated_by)
select i.depends_on, i.id, 'FS', 0, i.updated_by, i.updated_by
  from public.pm_items i
 where i.depends_on is not null and i.depends_on <> i.id
   and exists (select 1 from public.pm_items d where d.id = i.depends_on and d.project_id = i.project_id)
on conflict (pred_id, succ_id) do nothing;

-- حساب تواريخ الأنشطة ذات المدة (تمريرة أمامية بترتيب المراحل ثم الأنشطة):
--   الأساس = بداية المرحلة (وبداية البرنامج لما خارج المراحل)
--   القيد من كل علاقة: نهاية←بداية = نهاية السابق + الانتظار؛ بداية←بداية = بداية السابق + الانتظار؛
--                      نهاية←نهاية = نهاية السابق + الانتظار − المدة؛ بداية←نهاية = بداية السابق + الانتظار − المدة
--   البداية = أكبر (الأساس، القيود) + الإزاحة، ثم لا تسبق «لا يبدأ قبل»؛ والنهاية = البداية + المدة
--   بداية المرحلة = نهاية المرحلة السابقة + فاصلها، ولا تسبق بداية البرنامج
create or replace function public.pm_plan_recalc(p_project uuid)
returns integer
language plpgsql security definer set search_path = public
as $$
declare
  v_start  date;
  ph       record;
  v_prev   date;
  v_pstart date;
  v_pend   date;
  v_es     jsonb := '{}'::jsonb;
  v_ef     jsonb := '{}'::jsonb;
  v_res    record;
  n        integer := 0;
begin
  select start_date into v_start from public.pm_plans where project_id = p_project;
  if v_start is null then
    return 0;
  end if;
  -- الأنشطة دون مرحلة: من بداية البرنامج
  select * into v_res from public.pm_recalc_group(p_project, null, v_start, v_es, v_ef);
  v_es := v_res.es;
  v_ef := v_res.ef;
  n := n + v_res.n;
  v_prev := null;
  for ph in select id, lag_days from public.pm_phases where project_id = p_project order by sort, created_at loop
    v_pstart := case when v_prev is null then v_start else greatest(v_start, v_prev + ph.lag_days) end;
    select * into v_res from public.pm_recalc_group(p_project, ph.id, v_pstart, v_es, v_ef);
    v_es := v_res.es;
    v_ef := v_res.ef;
    n := n + v_res.n;
    v_pend := greatest(v_pstart, v_res.last_end);
    v_prev := v_pend;
  end loop;
  return n;
end;
$$;

-- حساب مجموعة (مرحلة، أو ما خارج المراحل حين p_phase فارغ) من أساسها
create or replace function public.pm_recalc_group(p_project uuid, p_phase uuid, p_base date, p_es jsonb, p_ef jsonb,
                                                  out es jsonb, out ef jsonb, out n integer, out last_end date)
language plpgsql security definer set search_path = public
as $$
declare
  it     record;
  lk     record;
  v_s    date;
  v_c    date;
begin
  es := p_es;
  ef := p_ef;
  n := 0;
  last_end := p_base;
  for it in select i.id, i.duration_days, i.offset_days, i.depends_on, i.planned_start, i.planned_end, i.start_not_before
              from public.pm_items i
             where i.project_id = p_project and i.phase_id is not distinct from p_phase
             order by i.sort, i.created_at loop
    if it.duration_days is null then
      -- نشاط بتاريخين محددين: يبقى كما هو
      es := es || jsonb_build_object(it.id::text, it.planned_start);
      ef := ef || jsonb_build_object(it.id::text, it.planned_end);
      last_end := greatest(last_end, it.planned_end);
      continue;
    end if;
    v_s := p_base;
    for lk in select l.pred_id, l.kind, l.lag_days from public.pm_item_links l where l.succ_id = it.id loop
      continue when not (ef ? lk.pred_id::text);
      v_c := case lk.kind
               when 'FS' then (ef ->> lk.pred_id::text)::date + lk.lag_days
               when 'SS' then (es ->> lk.pred_id::text)::date + lk.lag_days
               when 'FF' then (ef ->> lk.pred_id::text)::date + lk.lag_days - it.duration_days
               else (es ->> lk.pred_id::text)::date + lk.lag_days - it.duration_days
             end;
      v_s := greatest(v_s, v_c);
    end loop;
    -- «يتبع البند» من نسخة أقدم من التطبيق، إن لم تقابلها علاقة
    if it.depends_on is not null and ef ? it.depends_on::text
       and not exists (select 1 from public.pm_item_links l where l.pred_id = it.depends_on and l.succ_id = it.id) then
      v_s := greatest(v_s, (ef ->> it.depends_on::text)::date);
    end if;
    v_s := v_s + coalesce(it.offset_days, 0);
    if it.start_not_before is not null then
      v_s := greatest(v_s, it.start_not_before);
    end if;
    update public.pm_items set planned_start = v_s, planned_end = v_s + it.duration_days
     where id = it.id and (planned_start, planned_end) is distinct from (v_s, v_s + it.duration_days);
    es := es || jsonb_build_object(it.id::text, v_s);
    ef := ef || jsonb_build_object(it.id::text, v_s + it.duration_days);
    last_end := greatest(last_end, v_s + it.duration_days);
    n := n + 1;
  end loop;
end;
$$;

-- إضافة علاقة أو تعديل نوعها وانتظارها
create or replace function public.save_pm_link(p_id uuid, p_data jsonb)
returns uuid
language plpgsql security definer set search_path = public
as $$
declare
  o      public.pm_item_links;
  n      public.pm_item_links;
  ps     public.pm_items;
  ss     public.pm_items;
  v_pred uuid;
  v_succ uuid;
  v_kind text;
  v_lag  integer;
begin
  if jsonb_typeof(coalesce(p_data, 'null'::jsonb)) <> 'object' then
    raise exception 'بيانات غير صالحة' using errcode = '22023';
  end if;
  if p_id is not null then
    select * into o from public.pm_item_links where id = p_id for update;
    if not found then
      raise exception 'العلاقة غير موجودة' using errcode = 'P0002';
    end if;
    v_pred := o.pred_id;
    v_succ := o.succ_id;
  else
    begin
      v_pred := nullif(btrim(coalesce(p_data ->> 'pred_id', '')), '')::uuid;
      v_succ := nullif(btrim(coalesce(p_data ->> 'succ_id', '')), '')::uuid;
    exception when invalid_text_representation then
      raise exception 'مرجع غير صالح' using errcode = '22023';
    end;
  end if;
  select * into ps from public.pm_items where id = v_pred;
  select * into ss from public.pm_items where id = v_succ;
  if ps.id is null or ss.id is null then
    raise exception 'اختر النشاطين' using errcode = '22023';
  end if;
  if ps.project_id <> ss.project_id then
    raise exception 'العلاقة بين نشاطين من العقد نفسه' using errcode = '22023';
  end if;
  if not public.pm_can(ss.project_id, 'dates') then
    raise exception 'العلاقات وتواريخ الأنشطة من اختصاص الشؤون الفنية أو من مُنح صلاحية «تعديل التواريخ»' using errcode = '42501';
  end if;
  perform public.pm_plan_draft(ss.project_id);
  if v_pred = v_succ then
    raise exception 'لا يرتبط النشاط بنفسه' using errcode = '22023';
  end if;
  if public.pm_item_rank(v_pred) >= public.pm_item_rank(v_succ) then
    raise exception 'النشاط السابق في العلاقة يسبق التالي في ترتيب البرنامج؛ رتّب الأنشطة أولاً' using errcode = '22023';
  end if;
  v_kind := public.jpick(p_data, 'kind', array['FS', 'SS', 'FF', 'SF'], coalesce(o.kind, 'FS'), 'نوع العلاقة');
  v_lag := case when p_data ? 'lag_days' then coalesce(public.jint(p_data, 'lag_days', -3650, 3650, 'الانتظار'), 0)
                else coalesce(o.lag_days, 0) end;
  if p_id is null then
    if exists (select 1 from public.pm_item_links where pred_id = v_pred and succ_id = v_succ) then
      raise exception 'العلاقة بين النشاطين موجودة؛ عدّلها' using errcode = '22023';
    end if;
    insert into public.pm_item_links (pred_id, succ_id, kind, lag_days, created_by, updated_by)
    values (v_pred, v_succ, v_kind, v_lag, auth.uid(), auth.uid())
    returning * into n;
  else
    update public.pm_item_links set kind = v_kind, lag_days = v_lag, updated_at = now(), updated_by = auth.uid()
     where id = p_id
    returning * into n;
  end if;
  perform public.pm_after_change(ss.project_id);
  perform public.write_audit(case when p_id is null then 'pm.link_add' else 'pm.link_update' end, ss.project_id, null,
    jsonb_build_object('pred', ps.title, 'succ', ss.title, 'kind', n.kind, 'lag', n.lag_days,
                       'from_kind', o.kind, 'from_lag', o.lag_days));
  return n.id;
end;
$$;

create or replace function public.delete_pm_link(p_id uuid)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  l  public.pm_item_links;
  ps public.pm_items;
  ss public.pm_items;
begin
  select * into l from public.pm_item_links where id = p_id for update;
  if not found then
    raise exception 'العلاقة غير موجودة' using errcode = 'P0002';
  end if;
  select * into ps from public.pm_items where id = l.pred_id;
  select * into ss from public.pm_items where id = l.succ_id;
  if not public.pm_can(ss.project_id, 'dates') then
    raise exception 'العلاقات وتواريخ الأنشطة من اختصاص الشؤون الفنية أو من مُنح صلاحية «تعديل التواريخ»' using errcode = '42501';
  end if;
  perform public.pm_plan_draft(ss.project_id);
  delete from public.pm_item_links where id = p_id;
  -- «يتبع البند» القديمة المقابلة تُزال معها حتى لا تعود العلاقة في الحساب
  update public.pm_items set depends_on = null where id = l.succ_id and depends_on = l.pred_id;
  perform public.pm_after_change(ss.project_id);
  perform public.write_audit('pm.link_delete', ss.project_id, null,
    jsonb_build_object('pred', ps.title, 'succ', ss.title, 'kind', l.kind, 'lag', l.lag_days));
end;
$$;

-- ---------------------------------------------------------------------
-- 5. إصدارات البرنامج المعتمدة
-- ---------------------------------------------------------------------
create table if not exists public.pm_plan_versions (
  id             uuid primary key default gen_random_uuid(),
  project_id     uuid not null references public.projects (id) on delete cascade,
  origin_project uuid references public.projects (id) on delete set null,
  version        integer not null check (version >= 1),
  source         text not null default 'approval' check (source in ('approval', 'backfill')),
  start_date     date not null,
  end_date       date,
  items          jsonb not null default '[]' check (jsonb_typeof(items) = 'array'),
  phases         jsonb not null default '[]' check (jsonb_typeof(phases) = 'array'),
  links          jsonb not null default '[]' check (jsonb_typeof(links) = 'array'),
  approved_at    timestamptz not null default now(),
  approved_by    uuid references public.profiles (id) on delete set null,
  constraint pm_plan_versions_one unique (project_id, version)
);
create index if not exists pm_plan_versions_origin_idx      on public.pm_plan_versions (origin_project);
create index if not exists pm_plan_versions_approved_by_idx on public.pm_plan_versions (approved_by);

create or replace function public.pm_plan_snapshot(p_project uuid, p_version integer, p_source text)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  pl public.pm_plans;
begin
  select * into pl from public.pm_plans where project_id = p_project;
  if pl.id is null then
    return;
  end if;
  insert into public.pm_plan_versions (project_id, origin_project, version, source, start_date, end_date, items, phases, links,
                                       approved_at, approved_by)
  select p_project, pl.origin_project, p_version, p_source, pl.start_date,
         (select max(planned_end) from public.pm_items where project_id = p_project),
         coalesce((select jsonb_agg(jsonb_build_object('id', i.id, 'code', i.code, 'title', i.title, 'phase_id', i.phase_id,
                                                       'start', i.planned_start, 'end', i.planned_end, 'duration', i.duration_days,
                                                       'weight', i.weight, 'source', i.source)
                                    order by ph.sort nulls first, i.sort, i.created_at)
                     from public.pm_items i left join public.pm_phases ph on ph.id = i.phase_id
                    where i.project_id = p_project), '[]'::jsonb),
         coalesce((select jsonb_agg(jsonb_build_object('id', ph.id, 'name', ph.name, 'lag', ph.lag_days) order by ph.sort, ph.created_at)
                     from public.pm_phases ph where ph.project_id = p_project), '[]'::jsonb),
         coalesce((select jsonb_agg(jsonb_build_object('pred', l.pred_id, 'succ', l.succ_id, 'kind', l.kind, 'lag', l.lag_days))
                     from public.pm_item_links l join public.pm_items i on i.id = l.succ_id where i.project_id = p_project), '[]'::jsonb),
         coalesce(case when p_source = 'backfill' then pl.approved_at end, now()),
         case when p_source = 'backfill' then pl.approved_by else auth.uid() end
  on conflict (project_id, version) do nothing;
end;
$$;

-- البرامج المعتمدة الآن: إصدارها الحالي أساساً أول (لا يُعرف ما قبله)
do $$
declare
  pl record;
begin
  for pl in select project_id, version from public.pm_plans where status = 'approved' and version >= 1 loop
    perform public.pm_plan_snapshot(pl.project_id, pl.version, 'backfill');
  end loop;
end $$;

-- الإصدارات تتبع البرنامج عند دمج العقود وفكّها (بعد pm_plans_follow_merge بترتيب الأسماء)
create or replace function public.pm_versions_follow_merge()
returns trigger
language plpgsql security definer set search_path = public
as $$
begin
  if new.merged_into is not null and old.merged_into is null then
    if exists (select 1 from public.pm_plans where project_id = new.merged_into and origin_project = new.id) then
      update public.pm_plan_versions set project_id = new.merged_into, origin_project = coalesce(origin_project, new.id)
       where project_id = new.id;
    end if;
  elsif new.merged_into is null and old.merged_into is not null then
    update public.pm_plan_versions set project_id = new.id, origin_project = null
     where project_id = old.merged_into and origin_project = new.id;
  end if;
  return null;
end;
$$;
drop trigger if exists projects_pm_versions_follow_merge on public.projects;
create trigger projects_pm_versions_follow_merge
  after update of merged_into on public.projects
  for each row when (old.merged_into is distinct from new.merged_into)
  execute function public.pm_versions_follow_merge();


-- ---------------------------------------------------------------------
-- 6. الدوال القائمة بإضافاتها: «لا يبدأ قبل» والصلاحيات الدقيقة، والاعتماد يحفظ الإصدار،
--    والتوليد يقترح المدد بالإنتاجية، ونطاقات الصلاحيات الجديدة
-- ---------------------------------------------------------------------
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
  v_snb    date;
  v_need   text;
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
  v_snb   := case when p_data ? 'start_not_before' then public.jdate(p_data, 'start_not_before', 'لا يبدأ قبل') else o.start_not_before end;

  if v_new and v_src not in ('manual', 'extra') then
    raise exception 'بنود المقايسة تُنشأ من توليد البرنامج' using errcode = '22023';
  end if;

  -- ما الذي تغيّر: بيانات البند (إعداد) أم التنفيذ (متابعة)
  v_struct := v_new or v_title is distinct from o.title or v_code is distinct from o.code or v_phase is distinct from o.phase_id
              or v_dur is distinct from o.duration_days or v_off is distinct from o.offset_days or v_dep is distinct from o.depends_on
              or v_w is distinct from o.weight or v_work is distinct from o.work_id or v_sort is distinct from o.sort
              or (v_dur is null and (v_ps is distinct from o.planned_start or v_pe is distinct from o.planned_end))
              or v_unit is distinct from o.unit or v_qty is distinct from o.qty or v_pseq is distinct from o.price_seq
              or v_snb is distinct from o.start_not_before;
  v_track := (v_new and (v_pr <> 0 or v_as is not null or v_ae is not null or v_na))
             or (not v_new and (v_pr is distinct from o.progress or v_as is distinct from o.actual_start
                                or v_ae is distinct from o.actual_end or v_na is distinct from o.not_applicable
                                or v_notes is distinct from o.notes));

  if v_struct then
    -- إعداد البرنامج كاملاً، أو بالصلاحيات الدقيقة: إضافة الأنشطة وبياناتها، والمدد، والتواريخ (الترحيل 36)
    if not public.can_prepare_plan(v_proj) then
      if v_new or (v_title, v_code, v_phase, v_w, v_work, v_sort, v_unit, v_qty, v_pseq)
                  is distinct from (o.title, o.code, o.phase_id, o.weight, o.work_id, o.sort, o.unit, o.qty, o.price_seq) then
        v_need := 'add';
      end if;
      if v_need is not null and not public.pm_can(v_proj, 'add') then
        raise exception 'إضافة أنشطة البرنامج الزمني وتعديل بياناتها من اختصاص الشؤون الفنية أو من مُنح صلاحية «إضافة الأنشطة»' using errcode = '42501';
      end if;
      if not v_new and v_dur is distinct from o.duration_days and not public.pm_can(v_proj, 'duration') then
        raise exception 'تعديل مدد الأنشطة من اختصاص الشؤون الفنية أو من مُنح صلاحية «تعديل المدد»' using errcode = '42501';
      end if;
      if not v_new and ((v_off, v_dep, v_snb) is distinct from (o.offset_days, o.depends_on, o.start_not_before)
                        or (v_dur is null and (v_ps, v_pe) is distinct from (o.planned_start, o.planned_end)))
         and not public.pm_can(v_proj, 'dates') then
        raise exception 'تعديل تواريخ البداية والنهاية من اختصاص الشؤون الفنية أو من مُنح صلاحية «تعديل التواريخ»' using errcode = '42501';
      end if;
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
                                 notes, phase_id, duration_days, offset_days, source, unit, qty, price_seq, start_not_before,
                                 created_by, updated_by)
    values (v_proj, v_work, coalesce(v_sort, (select coalesce(max(sort), 0) + 10 from public.pm_items where project_id = v_proj)),
            v_code, v_title, v_ps, v_pe, v_w, 0, v_notes, v_phase, v_dur, v_off, v_src, v_unit, v_qty, v_pseq, v_snb,
            auth.uid(), auth.uid())
    returning * into n;
  else
    update public.pm_items set
      work_id = v_work, sort = coalesce(v_sort, o.sort), code = v_code, title = v_title, planned_start = v_ps, planned_end = v_pe,
      weight = v_w, progress = round(v_pr, 2), actual_start = v_as, actual_end = v_ae, notes = v_notes,
      phase_id = v_phase, duration_days = v_dur, offset_days = v_off, depends_on = v_dep, unit = v_unit, qty = v_qty,
      price_seq = v_pseq, not_applicable = v_na, start_not_before = v_snb, updated_at = now(), updated_by = auth.uid()
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

  -- «يتبع البند» علاقة نهاية←بداية في جدول العلاقات (الترحيل 36)، حتى يبقى للعلاقات مصدر واحد
  if n.depends_on is not null then
    insert into public.pm_item_links (pred_id, succ_id, kind, lag_days, created_by, updated_by)
    values (n.depends_on, n.id, 'FS', 0, auth.uid(), auth.uid())
    on conflict (pred_id, succ_id) do nothing;
  end if;
  if not v_new and o.depends_on is not null and o.depends_on is distinct from n.depends_on then
    delete from public.pm_item_links where pred_id = o.depends_on and succ_id = n.id and kind = 'FS' and lag_days = 0;
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
  if not (public.can_prepare_plan(r.project_id) or public.pm_can(r.project_id, 'add')) then
    raise exception 'حذف بنود البرنامج الزمني من اختصاص الشؤون الفنية أو من مُنح صلاحية «إضافة الأنشطة»' using errcode = '42501';
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
  if not public.pm_can(p_project, 'approve') then
    raise exception 'اعتماد البرنامج الزمني وإعادة فتحه لرئيس الشؤون الفنية ومدير المكتب ومن مُنح صلاحية «اعتماد البرنامج»' using errcode = '42501';
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
    -- يُحفظ الإصدار المعتمد كاملاً (أساساً للمقارنة) ولا يُعدَّل بعده (الترحيل 36)
    perform public.pm_plan_snapshot(p_project, pl.version + 1, 'approval');
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

-- يتغير شكل ما تعيده الدالة (عمود basis: بالإنتاجية أم بالقيمة)، فتُحذف وتُنشأ
drop function if exists public.pm_gen_plan(uuid, integer);
CREATE OR REPLACE FUNCTION public.pm_gen_plan(p_project uuid, p_total_days integer)
 RETURNS TABLE(pkey text, pname text, porder bigint, pdays integer, pcost numeric, sheet uuid, idx integer, pseq integer, code text, title text, unit text, qty numeric, cost numeric, idays integer, lorder bigint, basis text)
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
         coalesce(public.pm_rate_days(l0.unit, l0.descr, l0.qty),
                  case when coalesce(ph.maxc, 0) > 0 then greatest(1, round(ph.pdays * sqrt(l0.cost / ph.maxc))::integer) else ph.pdays end),
         l0.lorder,
         case when public.pm_rate_days(l0.unit, l0.descr, l0.qty) is not null then 'rate' else 'value' end
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
           'total_days', coalesce(sum(x.pdays), 0), 'items', coalesce(sum(x.n), 0), 'by_rate', coalesce(sum(x.r), 0))
    into v
    from (select g.pkey, g.pname, g.porder, g.pdays, g.pcost, count(*) as n, count(*) filter (where g.basis = 'rate') as r,
                 jsonb_agg(jsonb_build_object('code', g.code, 'title', g.title, 'days', g.idays, 'cost', g.cost, 'unit', g.unit, 'qty', g.qty,
                                              'basis', g.basis)
                           order by g.lorder, g.idx) as items
            from public.pm_gen_plan(p_project, p_total_days) g
           group by g.pkey, g.pname, g.porder, g.pdays, g.pcost) x;
  return v;
end;
$$;

-- ---------------------------------------------------------------------
-- 7. القراءة والصلاحيات
-- ---------------------------------------------------------------------
do $$
declare
  t text;
begin
  foreach t in array array['pm_rates', 'pm_item_links', 'pm_plan_versions'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke all on public.%I from anon', t);
    execute format('revoke insert, update, delete, truncate on public.%I from authenticated', t);
    execute format('grant select on public.%I to authenticated', t);
    execute format('grant all on public.%I to service_role', t);
  end loop;
end $$;

-- المعدلات: لمن يرى الشؤون الفنية أو العقود كاملة
drop policy if exists pm_rates_read on public.pm_rates;
create policy pm_rates_read on public.pm_rates for select to authenticated
  using ((select public.project_full_all()) or (select public.sees_section('docs')));
-- العلاقات والإصدارات: لمن يرى أنشطة البرنامج نفسه (سياسة pm_items وpm_plans)
drop policy if exists pm_item_links_read on public.pm_item_links;
create policy pm_item_links_read on public.pm_item_links for select to authenticated
  using (exists (select 1 from public.pm_items i where i.id = pm_item_links.succ_id));
drop policy if exists pm_plan_versions_read on public.pm_plan_versions;
create policy pm_plan_versions_read on public.pm_plan_versions for select to authenticated
  using (exists (select 1 from public.pm_plans p where p.project_id = pm_plan_versions.project_id));

revoke execute on function
  public.pm_rates_current(), public.pm_rate_for(text, text), public.pm_recalc_group(uuid, uuid, date, jsonb, jsonb),
  public.pm_plan_snapshot(uuid, integer, text), public.pm_versions_follow_merge(), public.pm_gen_plan(uuid, integer),
  public.pm_plan_recalc(uuid), public.pm_plan_preview_v34(uuid, integer)
from public, anon, authenticated;
revoke execute on function
  public.pm_unit_norm(text), public.pm_text_norm(text), public.pm_rate_days(text, text, numeric), public.pm_can_rates(),
  public.save_pm_rate(jsonb), public.delete_pm_rate(uuid), public.pm_can(uuid, text), public.save_pm_link(uuid, jsonb),
  public.delete_pm_link(uuid), public.save_boq(uuid, jsonb), public.save_pm_item(uuid, jsonb), public.delete_pm_item(uuid),
  public.pm_plan_set_status(uuid, text), public.grant_scope_ok(text)
from public, anon;
grant execute on function
  public.pm_unit_norm(text), public.pm_text_norm(text), public.pm_rate_days(text, text, numeric), public.pm_can_rates(),
  public.save_pm_rate(jsonb), public.delete_pm_rate(uuid), public.pm_can(uuid, text), public.save_pm_link(uuid, jsonb),
  public.delete_pm_link(uuid), public.save_boq(uuid, jsonb), public.save_pm_item(uuid, jsonb), public.delete_pm_item(uuid),
  public.pm_plan_set_status(uuid, text), public.grant_scope_ok(text)
to authenticated;
