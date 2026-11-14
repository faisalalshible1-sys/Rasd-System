-- =====================================================================
-- الترحيل 21: أقسام الوحدات
--   • الترميم والمباني التاريخية
--   • مكتب التخطيط وضمان الجودة: قسم التخطيط، قسم ضمان الجودة، قسم المتابعة
--   • مكتب السلامة المهنية
--   • المطابقة والاستلام: وحدة الاستلام، وحدة ضبط الجودة
-- يُشغَّل بعد الترحيلات 1–20، ويمكن إعادة تشغيله دون ضرر.
--
--  1. org_units      : الوحدات السبع وأقسامها الأربعة في الشاشة الرئيسية
--  2. profiles       : وحدة المستخدم (unit) وهل هو رئيسها (unit_head)، يحددهما المدير
--  3. unit_records   : سجلات عمل الوحدات (13 نوعاً) في جدول واحد، الحقول العامة أعمدة والخاصة في data
--  4. doc_files      : المرفقات تقبل سجلاً من سجلات الوحدات (المسار unit/<السجل>/<اسم عشوائي>)
--  5. الدوال: الحفظ والحذف والإسناد، مع التدقيق والتحديث اللحظي واتباع دمج العقود
--
-- الاطلاع لكل أعضاء المنظومة. الكتابة في كل وحدة: المدير، وموظفو مكتبه، ومستخدمو الوحدة،
-- ورئيس القسم الأم (رئيس الترميم لسجل المباني التاريخية، ورئيس المطابقة والاستلام لوحدتيه)،
-- ودور «مكتب التخطيط وضمان الجودة» لأقسامه الثلاثة.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. الوحدات
-- ---------------------------------------------------------------------
create table if not exists public.org_units (
  key     text primary key,
  section text not null check (section in ('heritage', 'planning_qa', 'safety', 'acceptance')),
  name    text not null,
  sort    smallint not null default 0
);
insert into public.org_units (key, section, name, sort) values
  ('heritage',          'heritage',    'الترميم والمباني التاريخية', 1),
  ('planning',          'planning_qa', 'قسم التخطيط',                2),
  ('quality_assurance', 'planning_qa', 'قسم ضمان الجودة',            3),
  ('follow_up',         'planning_qa', 'قسم المتابعة',               4),
  ('safety',            'safety',      'مكتب السلامة المهنية',       5),
  ('receiving',         'acceptance',  'وحدة الاستلام',              6),
  ('quality_control',   'acceptance',  'وحدة ضبط الجودة',            7)
on conflict (key) do update set section = excluded.section, name = excluded.name, sort = excluded.sort;

-- ---------------------------------------------------------------------
-- 2. وحدة المستخدم
-- ---------------------------------------------------------------------
alter table public.profiles add column if not exists unit text references public.org_units(key) on delete set null;
alter table public.profiles add column if not exists unit_head boolean not null default false;
create index if not exists profiles_unit_idx on public.profiles (unit);

-- منع المستخدم من تغيير أي شيء في ملفه غير الاسم (الوحدة تُضاف إلى الحقول المحمية)
create or replace function public.profiles_guard()
returns trigger
language plpgsql security definer set search_path = public
as $$
begin
  if current_setting('app.trusted', true) = 'on' or auth.uid() is null then
    return new;
  end if;
  if new.role is distinct from old.role or new.active is distinct from old.active
     or new.department is distinct from old.department or new.email is distinct from old.email
     or new.id is distinct from old.id
     or new.unit is distinct from old.unit or new.unit_head is distinct from old.unit_head then
    raise exception 'لا يملك تغيير الدور أو الحالة أو الوحدة إلا مدير المكتب' using errcode = '42501';
  end if;
  return new;
end;
$$;

-- إسناد مستخدم إلى وحدة (أو إزالته منها بتمرير null): المدير وحده
create or replace function public.set_user_unit(p_user uuid, p_unit text, p_head boolean default false)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  old_p  public.profiles;
  v_unit text := nullif(btrim(coalesce(p_unit, '')), '');
  v_head boolean := v_unit is not null and coalesce(p_head, false);
begin
  if not public.is_director() then
    raise exception 'إسناد المستخدمين إلى الوحدات من صلاحية مدير المكتب وحده' using errcode = '42501';
  end if;
  if not public.writes_allowed() then
    raise exception 'المنظومة في وضع القراءة فقط' using errcode = '42501';
  end if;
  select * into old_p from public.profiles where id = p_user for update;
  if not found then
    raise exception 'المستخدم غير موجود' using errcode = '22023';
  end if;
  if old_p.role = 'director' then
    raise exception 'حساب المدير لا يُسند إلى وحدة' using errcode = '22023';
  end if;
  if v_unit is not null and not exists (select 1 from public.org_units where key = v_unit) then
    raise exception 'الوحدة غير موجودة' using errcode = '22023';
  end if;
  if old_p.unit is not distinct from v_unit and old_p.unit_head = v_head then
    return;
  end if;
  perform set_config('app.trusted', 'on', true);
  update public.profiles set unit = v_unit, unit_head = v_head where id = p_user;
  perform set_config('app.trusted', 'off', true);
  perform public.write_audit('user.unit', null, null,
    jsonb_build_object('user_id', p_user, 'email', old_p.email,
      'unit', jsonb_build_object('from', old_p.unit, 'to', v_unit),
      'from_name', (select name from public.org_units where key = old_p.unit),
      'to_name', (select name from public.org_units where key = v_unit),
      'head', jsonb_build_object('from', old_p.unit_head, 'to', v_head)),
    coalesce(nullif(old_p.full_name, ''), old_p.email));
end;
$$;

-- ---------------------------------------------------------------------
-- 3. سجلات الوحدات
-- ---------------------------------------------------------------------
create table if not exists public.unit_records (
  id             uuid primary key default gen_random_uuid(),
  unit           text not null references public.org_units(key),
  kind           text not null,
  project_id     uuid references public.projects(id) on delete set null,
  origin_project uuid references public.projects(id) on delete set null,
  parent_id      uuid references public.unit_records(id) on delete cascade,
  title          text not null check (length(btrim(title)) between 2 and 200),
  ref_no         text not null default '' check (length(ref_no) <= 60),
  rec_date       date not null default current_date,
  due_date       date,
  status         text not null,
  level          text not null default '' check (length(level) <= 30),
  progress       numeric(5,2) check (progress between 0 and 100),
  owner_text     text not null default '' check (length(owner_text) <= 120),
  closed_at      date,
  data           jsonb not null default '{}'::jsonb check (jsonb_typeof(data) = 'object'),
  notes          text not null default '' check (length(notes) <= 4000),
  created_at     timestamptz not null default now(),
  created_by     uuid,
  updated_at     timestamptz not null default now(),
  updated_by     uuid
);
create index if not exists unit_records_unit_idx on public.unit_records (unit, kind, rec_date desc);
create index if not exists unit_records_project_idx on public.unit_records (project_id);
create index if not exists unit_records_origin_idx on public.unit_records (origin_project);
create index if not exists unit_records_parent_idx on public.unit_records (parent_id);

-- مواصفات كل نوع: الوحدة، والحالات (الأولى افتراضية)، والحالات المغلقة، والتصنيفات (level)، والسجل الأم، والعقد
create or replace function public.unit_kind_spec(p_kind text)
returns jsonb
language sql immutable set search_path = public
as $$
  select case p_kind
    when 'heritage_building' then jsonb_build_object('unit', 'heritage',
      'statuses', array['registered', 'under_study', 'under_restoration', 'restored'], 'closed', array['restored'],
      'levels', array['good', 'fair', 'poor', 'critical'], 'parent', null, 'parent_required', false, 'project_required', false)
    when 'heritage_assessment' then jsonb_build_object('unit', 'heritage',
      'statuses', array['draft', 'final'], 'closed', array['final'],
      'levels', array['good', 'fair', 'poor', 'critical'], 'parent', 'heritage_building', 'parent_required', true, 'project_required', false)
    when 'plan' then jsonb_build_object('unit', 'planning',
      'statuses', array['draft', 'active', 'done', 'cancelled'], 'closed', array['done', 'cancelled'],
      'levels', array['annual', 'quarterly', 'monthly', 'project'], 'parent', null, 'parent_required', false, 'project_required', false)
    when 'qa_audit' then jsonb_build_object('unit', 'quality_assurance',
      'statuses', array['planned', 'in_progress', 'done', 'cancelled'], 'closed', array['done', 'cancelled'],
      'levels', array['', 'satisfactory', 'needs_improvement', 'unsatisfactory'], 'parent', null, 'parent_required', false, 'project_required', false)
    when 'ncr' then jsonb_build_object('unit', 'quality_assurance',
      'statuses', array['open', 'in_progress', 'closed'], 'closed', array['closed'],
      'levels', array['minor', 'major', 'critical'], 'parent', 'qa_audit', 'parent_required', false, 'project_required', false)
    when 'followup_task' then jsonb_build_object('unit', 'follow_up',
      'statuses', array['open', 'done', 'cancelled'], 'closed', array['done', 'cancelled'],
      'levels', array['normal', 'high', 'urgent'], 'parent', null, 'parent_required', false, 'project_required', false)
    when 'safety_inspection' then jsonb_build_object('unit', 'safety',
      'statuses', array['open', 'closed'], 'closed', array['closed'],
      'levels', array['excellent', 'good', 'acceptable', 'poor'], 'parent', null, 'parent_required', false, 'project_required', true)
    when 'safety_incident' then jsonb_build_object('unit', 'safety',
      'statuses', array['open', 'investigating', 'closed'], 'closed', array['closed'],
      'levels', array['near_miss', 'minor', 'major', 'critical'], 'parent', null, 'parent_required', false, 'project_required', false)
    when 'safety_violation' then jsonb_build_object('unit', 'safety',
      'statuses', array['open', 'closed'], 'closed', array['closed'],
      'levels', array['low', 'medium', 'high'], 'parent', 'safety_inspection', 'parent_required', false, 'project_required', true)
    when 'handover' then jsonb_build_object('unit', 'receiving',
      'statuses', array['scheduled', 'accepted', 'accepted_notes', 'rejected'], 'closed', array['accepted', 'accepted_notes', 'rejected'],
      'levels', array['initial', 'final', 'partial'], 'parent', null, 'parent_required', false, 'project_required', true)
    when 'punch_item' then jsonb_build_object('unit', 'receiving',
      'statuses', array['open', 'closed'], 'closed', array['closed'],
      'levels', array[''], 'parent', 'handover', 'parent_required', true, 'project_required', false)
    when 'qc_test' then jsonb_build_object('unit', 'quality_control',
      'statuses', array['pending', 'passed', 'failed'], 'closed', array['passed', 'failed'],
      'levels', array['concrete', 'soil', 'steel', 'asphalt', 'masonry', 'other'], 'parent', null, 'parent_required', false, 'project_required', true)
    when 'material_approval' then jsonb_build_object('unit', 'quality_control',
      'statuses', array['under_review', 'approved', 'approved_notes', 'rejected'], 'closed', array['approved', 'approved_notes', 'rejected'],
      'levels', array[''], 'parent', null, 'parent_required', false, 'project_required', true)
  end
$$;

-- هل يكتب المستخدم الحالي في هذه الوحدة؟
create or replace function public.unit_can_edit(p_unit text)
returns boolean
language plpgsql stable security definer set search_path = public
as $$
declare
  me        public.profiles;
  v_section text;
begin
  if not public.writes_allowed() then
    return false;
  end if;
  select section into v_section from public.org_units where key = p_unit;
  if not found then
    return false;
  end if;
  select * into me from public.profiles where id = auth.uid();
  if not found or not me.active or me.role is null then
    return false;
  end if;
  return coalesce(me.role in ('director', 'office_staff')
      or coalesce(me.unit = p_unit, false)
      or (v_section = 'heritage' and me.role = 'dept_head' and me.department = 'restoration')
      or (v_section = 'acceptance' and me.role = 'dept_head' and me.department = 'acceptance')
      or (v_section = 'planning_qa' and me.role = 'planning_qa'), false);
end;
$$;

-- رئيس الوحدة (يحذف سجلاتها): المدير، ورئيس الوحدة المُسنَد، ورئيس القسم الأم، ودور مكتب التخطيط لأقسامه
create or replace function public.unit_is_head(p_unit text)
returns boolean
language plpgsql stable security definer set search_path = public
as $$
declare
  me        public.profiles;
  v_section text;
begin
  if not public.writes_allowed() then
    return false;
  end if;
  select section into v_section from public.org_units where key = p_unit;
  select * into me from public.profiles where id = auth.uid();
  if not found or not me.active or me.role is null then
    return false;
  end if;
  return coalesce(me.role = 'director'
      or coalesce(me.unit = p_unit and me.unit_head, false)
      or (v_section = 'heritage' and me.role = 'dept_head' and me.department = 'restoration')
      or (v_section = 'acceptance' and me.role = 'dept_head' and me.department = 'acceptance')
      or (v_section = 'planning_qa' and me.role = 'planning_qa'), false);
end;
$$;

-- التحقق من حقول data الخاصة بالنوع: كائن بمفاتيح قصيرة وقيم بسيطة (نص حتى 2000 حرف، رقم، منطقي، أو فارغ)
create or replace function public.unit_clean_data(p_data jsonb)
returns jsonb
language plpgsql immutable set search_path = public
as $$
declare
  k text;
  v jsonb;
  out jsonb := '{}'::jsonb;
begin
  if p_data is null or jsonb_typeof(p_data) = 'null' then
    return '{}'::jsonb;
  end if;
  if jsonb_typeof(p_data) <> 'object' then
    raise exception 'بيانات السجل غير صالحة' using errcode = '22023';
  end if;
  if (select count(*) from jsonb_object_keys(p_data)) > 40 then
    raise exception 'حقول السجل أكثر من المسموح' using errcode = '22023';
  end if;
  for k, v in select * from jsonb_each(p_data) loop
    if k !~ '^[a-z][a-z0-9_]{0,39}$' then
      raise exception 'اسم حقل غير صالح: %', k using errcode = '22023';
    end if;
    case jsonb_typeof(v)
      when 'string' then
        if length(v #>> '{}') > 2000 then
          raise exception 'الحقل % أطول من 2000 حرف', k using errcode = '22023';
        end if;
        if btrim(v #>> '{}') <> '' then
          out := out || jsonb_build_object(k, btrim(v #>> '{}'));
        end if;
      when 'number', 'boolean' then
        out := out || jsonb_build_object(k, v);
      when 'null' then
        null;
      else
        raise exception 'قيمة الحقل % غير صالحة', k using errcode = '22023';
    end case;
  end loop;
  return out;
end;
$$;

-- حفظ سجل (إنشاء أو تعديل). عند الإنشاء يُحدَّد النوع بالمفتاح kind. يعيد معرّف السجل.
create or replace function public.save_unit_record(p_id uuid, p_data jsonb)
returns uuid
language plpgsql security definer set search_path = public
as $$
declare
  old_row  public.unit_records;
  new_row  public.unit_records;
  par      public.unit_records;
  v_kind   text;
  v_spec   jsonb;
  v_unit   text;
  v_title  text := public.jtext(p_data, 'title', 200, 'العنوان');
  v_proj   uuid;
  v_parent uuid;
  v_status text;
  v_level  text;
  v_closed boolean;
  v_date   date := public.jdate(p_data, 'rec_date', 'التاريخ');
  v_due    date := public.jdate(p_data, 'due_date', 'الموعد');
  v_data   jsonb;
  v_skip   text[] := array['updated_at', 'updated_by'];
  v_ch     jsonb;
begin
  if jsonb_typeof(coalesce(p_data, 'null'::jsonb)) <> 'object' then
    raise exception 'بيانات غير صالحة' using errcode = '22023';
  end if;
  if p_id is not null then
    select * into old_row from public.unit_records where id = p_id for update;
    if not found then
      raise exception 'السجل غير موجود' using errcode = 'P0002';
    end if;
    v_kind := old_row.kind;
  else
    v_kind := nullif(btrim(coalesce(p_data ->> 'kind', '')), '');
  end if;
  v_spec := public.unit_kind_spec(v_kind);
  if v_spec is null then
    raise exception 'نوع السجل غير معروف' using errcode = '22023';
  end if;
  v_unit := v_spec ->> 'unit';
  if not public.unit_can_edit(v_unit) then
    raise exception 'لا تملك صلاحية الكتابة في سجلات «%»', (select name from public.org_units where key = v_unit)
      using errcode = '42501';
  end if;
  if length(v_title) < 2 then
    raise exception 'اكتب العنوان' using errcode = '22023';
  end if;

  -- السجل الأم (التقييم يتبع مبنى، وبند الملاحظات يتبع محضر استلام…)
  if p_id is not null and not (p_data ? 'parent_id') then
    v_parent := old_row.parent_id;
  elsif nullif(p_data ->> 'parent_id', '') is not null then
    begin
      v_parent := (p_data ->> 'parent_id')::uuid;
    exception when others then
      raise exception 'السجل المرتبط غير صالح' using errcode = '22023';
    end;
  end if;
  if v_parent is not null then
    if v_spec ->> 'parent' is null then
      raise exception 'هذا النوع لا يتبع سجلاً آخر' using errcode = '22023';
    end if;
    select * into par from public.unit_records where id = v_parent;
    if not found or par.kind <> v_spec ->> 'parent' or par.id = p_id then
      raise exception 'السجل المرتبط غير موجود' using errcode = '22023';
    end if;
  elsif (v_spec ->> 'parent_required')::boolean then
    raise exception 'اختر السجل الذي يتبعه هذا السجل' using errcode = '22023';
  end if;

  -- العقد: من البيانات، أو من السجل الأم، أو كما كان
  if p_data ? 'project_id' then
    v_proj := public.jproject(p_data, 'project_id', false);
  elsif p_id is not null then
    v_proj := old_row.project_id;
  end if;
  if v_proj is null and v_parent is not null then
    v_proj := par.project_id;
  end if;
  if v_proj is null and (v_spec ->> 'project_required')::boolean then
    raise exception 'اختر العقد' using errcode = '22023';
  end if;

  v_status := public.jpick(p_data, 'status', array(select jsonb_array_elements_text(v_spec -> 'statuses')),
                           v_spec -> 'statuses' ->> 0, 'الحالة');
  v_level := public.jpick(p_data, 'level', array(select jsonb_array_elements_text(v_spec -> 'levels')),
                          v_spec -> 'levels' ->> 0, 'التصنيف');
  v_closed := v_status in (select jsonb_array_elements_text(v_spec -> 'closed'));
  v_data := public.unit_clean_data(p_data -> 'data');
  if v_due is not null and v_due < coalesce(v_date, old_row.rec_date, current_date) then
    raise exception 'الموعد قبل تاريخ السجل' using errcode = '22023';
  end if;

  if p_id is null then
    insert into public.unit_records (unit, kind, project_id, parent_id, title, ref_no, rec_date, due_date, status, level, progress,
                                     owner_text, closed_at, data, notes, created_by, updated_by)
    values (v_unit, v_kind, v_proj, v_parent, v_title, public.jtext(p_data, 'ref_no', 60, 'الرقم'),
            coalesce(v_date, current_date), v_due, v_status, v_level, public.jnum(p_data, 'progress', 0, 100, 'نسبة الإنجاز'),
            public.jtext(p_data, 'owner_text', 120, 'المسؤول'), case when v_closed then current_date end, v_data,
            public.jtext(p_data, 'notes', 4000, 'ملاحظات'), auth.uid(), auth.uid())
    returning * into new_row;
    perform public.write_audit('unit.create', v_proj, null,
      jsonb_build_object('record_id', new_row.id, 'unit', v_unit, 'kind', v_kind, 'title', v_title, 'status', v_status),
      coalesce(public.project_label(v_proj), (select name from public.org_units where key = v_unit)));
  else
    update public.unit_records set
      project_id = v_proj, parent_id = v_parent, title = v_title, ref_no = public.jtext(p_data, 'ref_no', 60, 'الرقم'),
      rec_date = coalesce(v_date, old_row.rec_date), due_date = v_due, status = v_status, level = v_level,
      progress = public.jnum(p_data, 'progress', 0, 100, 'نسبة الإنجاز'),
      owner_text = public.jtext(p_data, 'owner_text', 120, 'المسؤول'),
      closed_at = case when not v_closed then null when old_row.closed_at is not null then old_row.closed_at else current_date end,
      data = v_data, notes = public.jtext(p_data, 'notes', 4000, 'ملاحظات'),
      origin_project = case when v_proj is distinct from old_row.project_id then null else old_row.origin_project end,
      updated_at = now(), updated_by = auth.uid()
    where id = p_id
    returning * into new_row;
    v_ch := public.jsonb_changes(to_jsonb(old_row), to_jsonb(new_row), v_skip);
    if v_ch <> '{}'::jsonb then
      perform public.write_audit('unit.update', v_proj, null,
        jsonb_build_object('record_id', p_id, 'unit', v_unit, 'kind', v_kind, 'title', v_title, 'changes', v_ch),
        coalesce(public.project_label(v_proj), (select name from public.org_units where key = v_unit)));
    end if;
  end if;
  return new_row.id;
end;
$$;

-- حذف سجل مع ما يتبعه: المدير، أو رئيس الوحدة، أو من أضافه خلال 24 ساعة. يعيد مسارات ملفاته لحذفها من الحاوية.
create or replace function public.delete_unit_record(p_id uuid)
returns text[]
language plpgsql security definer set search_path = public
as $$
declare
  r       public.unit_records;
  v_paths text[];
  v_n     integer;
begin
  select * into r from public.unit_records where id = p_id for update;
  if not found then
    raise exception 'السجل غير موجود' using errcode = 'P0002';
  end if;
  if not (public.unit_is_head(r.unit)
          or (public.unit_can_edit(r.unit) and r.created_by = auth.uid() and r.created_at > now() - interval '24 hours')) then
    raise exception 'حذف السجل للمدير ورئيس الوحدة، أو لمن أضافه خلال 24 ساعة' using errcode = '42501';
  end if;
  with recursive tree as (
    select id from public.unit_records where id = p_id
    union all
    select c.id from public.unit_records c join tree t on c.parent_id = t.id
  )
  select coalesce(array_agg(f.path), '{}'), (select count(*) - 1 from tree)
    into v_paths, v_n
    from public.doc_files f where f.record_id in (select id from tree);
  delete from public.unit_records where id = p_id;
  perform public.write_audit('unit.delete', r.project_id, null,
    jsonb_build_object('record_id', p_id, 'unit', r.unit, 'kind', r.kind, 'title', r.title, 'ref_no', r.ref_no,
                       'children', coalesce(v_n, 0), 'files', coalesce(array_length(v_paths, 1), 0)),
    coalesce(public.project_label(r.project_id), (select name from public.org_units where key = r.unit)));
  return v_paths;
end;
$$;

-- ---------------------------------------------------------------------
-- 4. المرفقات: سجلات الوحدات
-- ---------------------------------------------------------------------
alter table public.doc_files add column if not exists record_id uuid references public.unit_records(id) on delete cascade;
create index if not exists doc_files_record_idx on public.doc_files (record_id, sort);
alter table public.doc_files drop constraint if exists doc_files_one_owner;
alter table public.doc_files add constraint doc_files_one_owner check (num_nonnulls(revision_id, report_id, record_id) = 1);

create or replace function public.can_upload_doc_path(p_name text)
returns boolean
language plpgsql stable security definer set search_path = public
as $$
declare
  v_scope text := split_part(coalesce(p_name, ''), '/', 1);
  v_owner uuid;
  v_kind  text;
  v_proj  uuid;
  v_unit  text;
begin
  if p_name is null or p_name !~ '^(doc|report|unit)/[0-9a-f-]{36}/[A-Za-z0-9_-]{8,64}\.(pdf|jpg|jpeg|png|webp|gif)$' then
    return false;
  end if;
  v_owner := split_part(p_name, '/', 2)::uuid;
  if v_scope = 'doc' then
    select i.kind, i.project_id into v_kind, v_proj
      from public.doc_revisions r join public.doc_items i on i.id = r.item_id where r.id = v_owner;
    return found and public.doc_can_edit(v_kind, v_proj);
  end if;
  if v_scope = 'unit' then
    select unit into v_unit from public.unit_records where id = v_owner;
    return found and public.unit_can_edit(v_unit);
  end if;
  select project_id into v_proj from public.site_reports where id = v_owner;
  return found and public.site_report_can_edit(v_proj);
end;
$$;

create or replace function public.add_doc_file(p_path text, p_name text, p_width integer default null, p_height integer default null)
returns uuid
language plpgsql security definer set search_path = public
as $$
declare
  v_scope text := split_part(coalesce(p_path, ''), '/', 1);
  v_owner uuid;
  v_mime  text;
  v_size  bigint;
  v_name  text := btrim(coalesce(p_name, ''));
  v_id    uuid;
  v_n     integer;
  it      public.doc_items;
  rv      public.doc_revisions;
  rp      public.site_reports;
  ur      public.unit_records;
begin
  if not public.can_upload_doc_path(p_path) then
    raise exception 'لا تملك صلاحية إرفاق ملف هنا' using errcode = '42501';
  end if;
  if length(v_name) < 1 or length(v_name) > 200 then
    raise exception 'اسم الملف غير صالح' using errcode = '22023';
  end if;
  v_owner := split_part(p_path, '/', 2)::uuid;
  if to_regclass('storage.objects') is not null then
    execute 'select metadata ->> ''mimetype'', (metadata ->> ''size'')::bigint from storage.objects where bucket_id = ''docs'' and name = $1'
      into v_mime, v_size using p_path;
    if v_size is null then
      raise exception 'لم يكتمل رفع الملف؛ أعد المحاولة' using errcode = 'P0002';
    end if;
  end if;
  v_mime := lower(coalesce(v_mime, case
    when p_path ~* '\.pdf$' then 'application/pdf' when p_path ~* '\.png$' then 'image/png'
    when p_path ~* '\.webp$' then 'image/webp' when p_path ~* '\.gif$' then 'image/gif' else 'image/jpeg' end));
  if v_mime not in ('application/pdf', 'image/jpeg', 'image/png', 'image/webp', 'image/gif') then
    raise exception 'نوع الملف غير مسموح؛ المسموح PDF والصور' using errcode = '22023';
  end if;
  v_size := coalesce(v_size, 1);
  if v_size > 20971520 then
    raise exception 'حجم الملف أكبر من 20 ميجابايت' using errcode = '22023';
  end if;

  if v_scope = 'doc' then
    select * into rv from public.doc_revisions where id = v_owner;
    select * into it from public.doc_items where id = rv.item_id;
    select count(*) into v_n from public.doc_files where revision_id = v_owner;
    if v_n >= 40 then
      raise exception 'الحد الأعلى 40 ملفاً للإصدار الواحد' using errcode = '22023';
    end if;
    insert into public.doc_files (revision_id, path, name, mime, size_bytes, width, height, sort, created_by)
    values (v_owner, p_path, v_name, v_mime, v_size, p_width, p_height, v_n + 1, auth.uid())
    returning id into v_id;
    perform public.write_audit('doc.file_add', it.project_id, null,
      jsonb_build_object('item_id', it.id, 'kind', it.kind, 'title', it.title, 'rev_no', rv.rev_no, 'file', v_name, 'size', v_size),
      coalesce(public.project_label(it.project_id), 'عام'));
  elsif v_scope = 'unit' then
    select * into ur from public.unit_records where id = v_owner;
    select count(*) into v_n from public.doc_files where record_id = v_owner;
    if v_n >= 40 then
      raise exception 'الحد الأعلى 40 ملفاً للسجل الواحد' using errcode = '22023';
    end if;
    insert into public.doc_files (record_id, path, name, mime, size_bytes, width, height, sort, created_by)
    values (v_owner, p_path, v_name, v_mime, v_size, p_width, p_height, v_n + 1, auth.uid())
    returning id into v_id;
    perform public.write_audit('unit.file_add', ur.project_id, null,
      jsonb_build_object('record_id', ur.id, 'unit', ur.unit, 'kind', ur.kind, 'title', ur.title, 'file', v_name, 'size', v_size),
      coalesce(public.project_label(ur.project_id), (select name from public.org_units where key = ur.unit)));
  else
    select * into rp from public.site_reports where id = v_owner;
    select count(*) into v_n from public.doc_files where report_id = v_owner;
    if v_n >= 40 then
      raise exception 'الحد الأعلى 40 ملفاً للتقرير الواحد' using errcode = '22023';
    end if;
    insert into public.doc_files (report_id, path, name, mime, size_bytes, width, height, sort, created_by)
    values (v_owner, p_path, v_name, v_mime, v_size, p_width, p_height, v_n + 1, auth.uid())
    returning id into v_id;
    perform public.write_audit('report.file_add', rp.project_id, null,
      jsonb_build_object('report_id', rp.id, 'date', rp.report_date, 'file', v_name, 'size', v_size));
  end if;
  return v_id;
end;
$$;

create or replace function public.delete_doc_file(p_id uuid)
returns text
language plpgsql security definer set search_path = public
as $$
declare
  f      public.doc_files;
  v_p    uuid;
  v_ok   boolean;
  v_head boolean := false;
  v_act  text;
begin
  select * into f from public.doc_files where id = p_id for update;
  if not found then
    raise exception 'الملف غير موجود' using errcode = 'P0002';
  end if;
  if f.revision_id is not null then
    select i.project_id, public.doc_can_edit(i.kind, i.project_id) into v_p, v_ok
      from public.doc_revisions r join public.doc_items i on i.id = r.item_id where r.id = f.revision_id;
    v_act := 'doc.file_delete';
  elsif f.record_id is not null then
    select project_id, public.unit_can_edit(unit), public.unit_is_head(unit) into v_p, v_ok, v_head
      from public.unit_records where id = f.record_id;
    v_act := 'unit.file_delete';
  else
    select project_id, public.site_report_can_edit(project_id) into v_p, v_ok from public.site_reports where id = f.report_id;
    v_act := 'report.file_delete';
  end if;
  if not (public.is_director() or coalesce(v_head, false)
          or (v_ok and f.created_by = auth.uid() and f.created_at > now() - interval '24 hours')) then
    raise exception 'إزالة الملف للمدير، أو لمن رفعه خلال 24 ساعة' using errcode = '42501';
  end if;
  delete from public.doc_files where id = p_id;
  perform public.write_audit(v_act, v_p, null,
    jsonb_build_object('file', f.name, 'size', f.size_bytes, 'revision_id', f.revision_id, 'report_id', f.report_id,
                       'record_id', f.record_id));
  return f.path;
end;
$$;

-- ---------------------------------------------------------------------
-- 5. اتباع الدمج: سجلات الوحدات المرتبطة بعقد تنتقل مع دمجه وتعود مع فكّه
-- ---------------------------------------------------------------------
create or replace function public.units_follow_merge()
returns trigger
language plpgsql security definer set search_path = public
as $$
begin
  if new.merged_into is not null and old.merged_into is null then
    update public.unit_records set project_id = new.merged_into, origin_project = coalesce(origin_project, new.id)
     where project_id = new.id;
  elsif new.merged_into is null and old.merged_into is not null then
    update public.unit_records set project_id = new.id, origin_project = null
     where project_id = old.merged_into and origin_project = new.id;
  end if;
  return null;
end;
$$;
drop trigger if exists projects_units_follow_merge on public.projects;
create trigger projects_units_follow_merge after update of merged_into on public.projects
  for each row when (old.merged_into is distinct from new.merged_into) execute function public.units_follow_merge();

-- ---------------------------------------------------------------------
-- 6. القراءة والصلاحيات والتحديث اللحظي
-- ---------------------------------------------------------------------
do $$
declare
  t text;
begin
  foreach t in array array['org_units', 'unit_records'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('drop policy if exists %I on public.%I', t || '_read', t);
    execute format('create policy %I on public.%I for select to authenticated using ((select public.is_member()))', t || '_read', t);
    execute format('revoke all on public.%I from anon', t);
    execute format('revoke insert, update, delete, truncate on public.%I from authenticated', t);
    execute format('grant select on public.%I to authenticated', t);
    execute format('grant all on public.%I to service_role', t);
  end loop;
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime')
     and not exists (select 1 from pg_publication_tables
                     where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'unit_records') then
    execute 'alter publication supabase_realtime add table public.unit_records';
  end if;
end $$;

revoke execute on function public.units_follow_merge(), public.unit_clean_data(jsonb) from public, anon, authenticated;
revoke execute on function
  public.set_user_unit(uuid, text, boolean), public.unit_kind_spec(text), public.unit_can_edit(text), public.unit_is_head(text),
  public.save_unit_record(uuid, jsonb), public.delete_unit_record(uuid)
from public, anon;
grant execute on function
  public.set_user_unit(uuid, text, boolean), public.unit_kind_spec(text), public.unit_can_edit(text), public.unit_is_head(text),
  public.save_unit_record(uuid, jsonb), public.delete_unit_record(uuid)
to authenticated;

notify pgrst, 'reload schema';
