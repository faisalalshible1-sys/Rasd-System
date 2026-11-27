-- =====================================================================
-- التراجع عن الترحيل 39 (قسم المخازن: الأصول والعُهد والإهلاك)
--
-- يُرفض إن كان في سجل الأصول أي أصل أو عهدة، أو عُدّلت سياسات الإهلاك المبدئية، أو مُنحت صلاحية stores:assets.
-- عندها تبقى المنظومة كما هي. يعيد تعريف دوال الترحيل 38 المعدَّلة كما كانت حرفياً وقيد نطاقات الصلاحيات،
-- ثم يحذف جداول الأصول ودوالها. لا يمس بيانات المخزون (الترحيل 38).
-- =====================================================================
do $$
declare
  v_bad text := '';
begin
  if to_regclass('public.st_assets') is null then
    return;
  end if;
  if exists (select 1 from public.st_assets) then v_bad := v_bad || ' أصول'; end if;
  if exists (select 1 from public.st_custody) then v_bad := v_bad || ' عهد'; end if;
  if exists (select 1 from public.st_asset_policies where updated_by is not null)
     or (select count(*) from public.st_asset_policies) <> (select count(*) from public.st_categories where code in ('OFE', 'FUR') and kind = 'asset') then
    v_bad := v_bad || ' سياسات إهلاك معدّلة';
  end if;
  if exists (select 1 from public.user_grants where scope = 'stores:assets') then v_bad := v_bad || ' صلاحية مسؤول الأصول'; end if;
  if v_bad <> '' then
    raise exception 'لا يُتراجع عن الترحيل 39: في سجل الأصول بيانات (%). المنظومة كما هي.', btrim(v_bad);
  end if;
end $$;

-- قيد نطاقات الصلاحيات كما كان بعد الترحيل 38
alter table public.user_grants drop constraint if exists user_grants_scope_check;
alter table public.user_grants add constraint user_grants_scope_check check (
  scope ~ '^(form:[a-z0-9_]{1,40}|docs:(boq|letter|design|pm_view|pm_add|pm_duration|pm_dates|pm_approve)|supervision:reports|unit:[a-z_]{2,40}|swot|pm:(plan|track)|stores:(admin|manager|audit)|stores:keeper:[0-9a-f-]{36})$');

-- دوال الترحيل 38 المعدَّلة كما كانت
CREATE OR REPLACE FUNCTION public.grant_scope_ok(p_scope text)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select case
    when p_scope like 'form:%' then exists (select 1 from public.form_defs where key = substr(p_scope, 6))
    when p_scope like 'unit:%' then public.unit_kind_spec(substr(p_scope, 6)) is not null
    when p_scope like 'stores:keeper:%' then
      substr(p_scope, 15) ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
      and exists (select 1 from public.st_warehouses w where w.id::text = substr(p_scope, 15))
    else p_scope in ('docs:boq', 'docs:letter', 'docs:design', 'supervision:reports', 'swot', 'pm:plan', 'pm:track',
                     'docs:pm_view', 'docs:pm_add', 'docs:pm_duration', 'docs:pm_dates', 'docs:pm_approve',
                     'stores:admin', 'stores:manager', 'stores:audit')
  end
$function$
;

CREATE OR REPLACE FUNCTION public.st_delete_setup(p_entity text, p_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_name text;
  v_row  jsonb;
begin
  if p_entity in ('item') then
    if not public.st_can_items() then
      raise exception 'بطاقات الأصناف لمدير المخازن أو مدير النظام في القسم' using errcode = '42501';
    end if;
  elsif not public.st_can_setup() then
    raise exception 'تهيئة المخازن لمدير النظام في القسم أو المدير' using errcode = '42501';
  end if;
  case p_entity
    when 'department' then
      select to_jsonb(d) - 'name_key', d.name into v_row, v_name from public.st_departments d where id = p_id;
      if exists (select 1 from public.st_departments where parent_id = p_id)
         or exists (select 1 from public.st_employees where department_id = p_id)
         or exists (select 1 from public.st_docs where department_id = p_id) then
        raise exception 'الإدارة مرتبطة بإدارات أو موظفين أو مستندات؛ أوقفها بدل حذفها' using errcode = '23503';
      end if;
      delete from public.st_departments where id = p_id;
    when 'location' then
      select to_jsonb(l) - 'name_key', l.name into v_row, v_name from public.st_locations l where id = p_id;
      if exists (select 1 from public.st_locations where parent_id = p_id)
         or exists (select 1 from public.st_warehouses where location_id = p_id) then
        raise exception 'الموقع تتبعه مواقع أو مخازن؛ أوقفه بدل حذفه' using errcode = '23503';
      end if;
      delete from public.st_locations where id = p_id;
    when 'warehouse' then
      select to_jsonb(w) - 'name_key', w.name into v_row, v_name from public.st_warehouses w where id = p_id;
      if exists (select 1 from public.st_docs where warehouse_id = p_id or to_warehouse_id = p_id)
         or exists (select 1 from public.st_stock where warehouse_id = p_id)
         or exists (select 1 from public.st_warehouses where parent_id = p_id) then
        raise exception 'للمخزن مستندات أو رصيد أو مخازن فرعية؛ أوقفه بدل حذفه' using errcode = '23503';
      end if;
      delete from public.user_grants where scope = 'stores:keeper:' || p_id::text;
      delete from public.st_warehouses where id = p_id;
    when 'category' then
      select to_jsonb(c) - 'name_key', c.name into v_row, v_name from public.st_categories c where id = p_id;
      if exists (select 1 from public.st_categories where parent_id = p_id)
         or exists (select 1 from public.st_items where category_id = p_id) then
        raise exception 'التصنيف فيه أصناف أو تصنيفات فرعية؛ أوقفه بدل حذفه' using errcode = '23503';
      end if;
      delete from public.st_categories where id = p_id;
    when 'unit' then
      select to_jsonb(u) - 'name_key', u.name into v_row, v_name from public.st_units u where id = p_id;
      if exists (select 1 from public.st_items where base_unit_id = p_id)
         or exists (select 1 from public.st_item_units where unit_id = p_id)
         or exists (select 1 from public.st_doc_lines where unit_id = p_id) then
        raise exception 'الوحدة مستعملة في أصناف أو مستندات؛ أوقفها بدل حذفها' using errcode = '23503';
      end if;
      delete from public.st_units where id = p_id;
    when 'employee' then
      select to_jsonb(e) - 'name_key', e.full_name into v_row, v_name from public.st_employees e where id = p_id;
      if exists (select 1 from public.st_docs where employee_id = p_id) then
        raise exception 'للموظف مستندات صرف أو إرجاع؛ أوقفه بدل حذفه' using errcode = '23503';
      end if;
      delete from public.st_employees where id = p_id;
    when 'item' then
      select to_jsonb(i) - 'name_key', i.name into v_row, v_name from public.st_items i where id = p_id;
      if exists (select 1 from public.st_doc_lines where item_id = p_id)
         or exists (select 1 from public.st_stock where item_id = p_id) then
        raise exception 'للصنف حركات أو رصيد؛ أوقفه بدل حذفه' using errcode = '23503';
      end if;
      delete from public.st_items where id = p_id;
    else
      raise exception 'نوع غير معروف' using errcode = '22023';
  end case;
  if v_row is null then
    raise exception 'غير موجود' using errcode = 'P0002';
  end if;
  perform public.write_audit(case when p_entity = 'employee' then 'stores.employee' when p_entity = 'item' then 'stores.item'
                                  else 'stores.setup' end,
    null, null, jsonb_build_object('entity', p_entity, 'op', 'delete', 'id', p_id, 'name', v_name, 'from', v_row), v_name);
end;
$function$
;

CREATE OR REPLACE FUNCTION public.st_save_category(p_id uuid, p_data jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  old_r  public.st_categories;
  v_id   uuid := p_id;
  v_par  uuid;
  v_name text;
  v_code text;
  v_kind text := coalesce(p_data ->> 'kind', 'consumable');
  v_cur  uuid;
  i      integer := 0;
begin
  if not public.st_can_setup() then
    raise exception 'تهيئة المخازن لمدير النظام في القسم أو المدير' using errcode = '42501';
  end if;
  if jsonb_typeof(coalesce(p_data, 'null'::jsonb)) <> 'object' then
    raise exception 'بيانات غير صالحة' using errcode = '22023';
  end if;
  if v_kind not in ('consumable', 'asset') then
    raise exception 'نوع التصنيف استهلاكي أو أصل' using errcode = '22023';
  end if;
  v_name := public.st_text(p_data, 'name', 80);
  v_code := upper(public.st_text(p_data, 'code', 8));
  if length(v_name) < 2 then
    raise exception 'اكتب اسم التصنيف' using errcode = '22023';
  end if;
  if v_code !~ '^[A-Z0-9]{2,8}$' then
    raise exception 'رمز التصنيف من 2 إلى 8 حروف لاتينية كبيرة أو أرقام' using errcode = '22023';
  end if;
  v_par := public.st_uuid(p_data, 'parent_id');
  if v_par is not null and not exists (select 1 from public.st_categories where id = v_par) then
    raise exception 'التصنيف الأعلى غير موجود' using errcode = '22023';
  end if;
  v_cur := v_par;
  while v_cur is not null loop
    if v_cur = p_id then
      raise exception 'لا يكون التصنيف فرعاً من نفسه' using errcode = '22023';
    end if;
    i := i + 1;
    exit when i > 20;
    select parent_id into v_cur from public.st_categories where id = v_cur;
  end loop;
  if p_id is null then
    insert into public.st_categories (parent_id, code, name, kind, active, sort, created_by, updated_by)
    values (v_par, v_code, v_name, v_kind, coalesce((p_data ->> 'active')::boolean, true),
            coalesce((p_data ->> 'sort')::integer, 0), auth.uid(), auth.uid())
    returning id into v_id;
  else
    select * into old_r from public.st_categories where id = p_id for update;
    if not found then
      raise exception 'التصنيف غير موجود' using errcode = 'P0002';
    end if;
    update public.st_categories
       set parent_id = v_par, code = v_code, name = v_name, kind = v_kind,
           active = coalesce((p_data ->> 'active')::boolean, active), sort = coalesce((p_data ->> 'sort')::integer, sort),
           updated_at = now(), updated_by = auth.uid()
     where id = p_id;
  end if;
  perform public.write_audit('stores.setup', null, null,
    jsonb_build_object('entity', 'category', 'op', case when p_id is null then 'create' else 'update' end, 'id', v_id,
                       'name', v_name, 'code', v_code, 'from', case when p_id is null then null else to_jsonb(old_r) - 'name_key' end),
    v_name);
  return v_id;
exception
  when unique_violation then
    raise exception 'يوجد تصنيف بالاسم أو الرمز نفسه' using errcode = '23505';
end;
$function$
;

CREATE OR REPLACE FUNCTION public.st_staff()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select public.st_sees_all() or cardinality(public.st_my_warehouses()) > 0
$function$
;


-- إزالة الأصول: الجداول ثم الدوال
do $$
begin
  if to_regclass('public.st_assets') is not null then
    if exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'st_assets') then
      alter publication supabase_realtime drop table public.st_assets;
    end if;
    if exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'st_custody') then
      alter publication supabase_realtime drop table public.st_custody;
    end if;
    if exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'st_asset_policies') then
      alter publication supabase_realtime drop table public.st_asset_policies;
    end if;
  end if;
end $$;

drop function if exists public.st_book_value(public.st_assets, date);
drop table if exists public.st_asset_events;
drop table if exists public.st_custody;
drop table if exists public.st_assets;
drop table if exists public.st_asset_policies;

drop function if exists public.st_import_assets(jsonb);
drop function if exists public.st_asset_dispose_decide(uuid, boolean, text);
drop function if exists public.st_asset_dispose_request(uuid, jsonb);
drop function if exists public.st_my_custody();
drop function if exists public.st_confirm_custody(uuid, text);
drop function if exists public.st_custody_in(uuid, jsonb);
drop function if exists public.st_custody_out(uuid, jsonb);
drop function if exists public.st_asset_status(uuid, text, text, text);
drop function if exists public.st_asset_transfer(uuid, jsonb);
drop function if exists public.st_delete_asset(uuid);
drop function if exists public.st_save_asset(uuid, jsonb);
drop function if exists public.st_save_asset_policy(uuid, jsonb);
drop function if exists public.st_place_status(uuid, uuid, uuid);
drop function if exists public.st_asset_row(uuid);
drop function if exists public.st_asset_event(uuid, text, jsonb, text);
drop function if exists public.st_accumulated(numeric, numeric, text, integer, date, date);
drop function if exists public.st_months_between(date, date);
drop function if exists public.st_date(jsonb, text);
drop function if exists public.st_can_assets();
drop function if exists public.st_assets_sees();
delete from public.st_counters where scope = 'custody' or scope like 'asset:%';
