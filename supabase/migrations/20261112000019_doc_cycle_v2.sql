-- =====================================================================
-- اعتماد «الدورة المستندية للعقود» – الإصدار 2 (عرض 2026-11-09، اعتمده مدير المكتب في 2026-11-12)
-- مستقل عن الملفات 16 و17 و18، ويمكن إعادة تشغيله دون ضرر.
--
--  - المراحل الخمس بأسمائها المعتمدة
--  - 25 بنداً بالترتيب المعتمد (التعديلات Δ1–Δ5) وجهات التنفيذ والمتابعة (ومنها الجهات التي حُدّدت للخانات الفارغة)
--  - سبعة نماذج جديدة: نطاق وطريقة عمل، ملحق فني، محضر حصر كميات، مراجعة مستخلص، اعتماد مستخلص،
--    تكليف لجنة استلام ابتدائي، تكليف لجنة استلام نهائي
--  - «تكليف مهندس سلامة» يبقى في المرحلة الثانية مع التكليفات (له خيار «لا ينطبق»)
--  - حالات النماذج المسجّلة في العقود تبقى كما هي؛ النماذج الجديدة «لم يبدأ» حتى تُحدَّث
--
-- جهات التنفيذ والمتابعة → من يحدّث حالة النموذج (موظفو مكتب المدير والمدير دائماً):
--   مكتب العقود → contracts · قسم الشؤون الفنية → head:technical · قسم الإشراف والتنسيق → head:supervising
--   قسم المطابقة والاستلام ولجان الاستلام → head:acceptance · قسم المتابعة وتقييم الأداء → planning_qa
--   رئيس اللجنة ومدير المكتب → مكتب المدير · الجهة المنفذة (المستخلصات) → مكتب العقود
-- =====================================================================

do $$
declare
  r       record;
  v_old   public.form_defs;
  v_key   text;
  v_n     int;
  v_oldst text;
  v_any   boolean := false;
begin
  perform set_config('app.trusted', 'on', true);

  -- المراحل
  for r in select * from (values
      (0::smallint, 'التعاقد والإعداد الفني'),
      (1::smallint, 'أمر العمل وتسليم الموقع'),
      (2::smallint, 'التنفيذ والمستخلصات الجارية'),
      (3::smallint, 'الاستلام الابتدائي والمستخلص الختامي'),
      (4::smallint, 'الاستلام النهائي وإقفال العقد')) s(idx, name)
  loop
    select name into v_oldst from public.stages where idx = r.idx;
    if not found then
      insert into public.stages (idx, name) values (r.idx, r.name);
      perform public.write_audit('config.stage', null, null, jsonb_build_object('idx', r.idx, 'to', r.name), r.name);
    elsif v_oldst is distinct from r.name then
      update public.stages set name = r.name where idx = r.idx;
      perform public.write_audit('config.stage', null, null,
        jsonb_build_object('idx', r.idx, 'from', v_oldst, 'to', r.name), r.name);
    end if;
  end loop;

  -- النماذج بالترتيب المعتمد. is_new: نموذج جديد يُطابَق باسمه إن أضافه المدير من قبل
  update public.form_defs set sort = sort + 1000;
  for r in select * from (values
      ( 1, 'f01', false, 'أمر بالتعاقد',               0, array['office_staff', 'contracts']),
      ( 2, 'f20', true,  'نطاق وطريقة عمل',            0, array['office_staff', 'head:technical']),
      ( 3, 'f19', false, 'مقايسة تقديرية',              0, array['office_staff', 'head:technical']),
      ( 4, 'f21', true,  'ملحق فني',                    0, array['office_staff', 'contracts']),
      ( 5, 'f03', false, 'نموذج عقد أشغال عامة',        0, array['office_staff', 'contracts']),
      ( 6, 'f02', false, 'أمر عمل',                     1, array['office_staff']),
      ( 7, 'f04', false, 'تكليف مهندس إشراف',          1, array['office_staff', 'head:supervising']),
      ( 8, 'f05', false, 'تكليف مهندس حصر',            1, array['office_staff', 'head:acceptance']),
      ( 9, 'f06', false, 'تكليف مهندس متابعة',         1, array['office_staff', 'planning_qa']),
      (10, 'f07', false, 'تكليف مهندس سلامة',          1, array['office_staff', 'head:supervising']),
      (11, 'f08', false, 'محضر تسليم موقع عمل',        1, array['office_staff', 'head:supervising']),
      (12, 'f09', false, 'تصريح عمل',                   1, array['office_staff', 'head:supervising']),
      (13, 'f10', false, 'ورقة قياس نموذج أ',           2, array['office_staff', 'head:acceptance']),
      (14, 'f11', false, 'ورقة قياس نموذج ب',           2, array['office_staff', 'head:acceptance']),
      (15, 'f22', true,  'محضر حصر كميات',              2, array['office_staff', 'head:acceptance']),
      (16, 'f12', false, 'كشف حصر مستخلص',              2, array['office_staff', 'head:acceptance']),
      (17, 'f14', false, 'مستخلص جاري',                 2, array['office_staff', 'contracts']),
      (18, 'f13', false, 'شهادة دفع مستخلص',            2, array['office_staff', 'head:acceptance']),
      (19, 'f23', true,  'مراجعة مستخلص',               2, array['office_staff', 'contracts']),
      (20, 'f24', true,  'اعتماد مستخلص',               2, array['office_staff']),
      (21, 'f25', true,  'تكليف لجنة استلام ابتدائي',  3, array['office_staff']),
      (22, 'f16', false, 'محضر استلام ابتدائي',         3, array['office_staff', 'head:acceptance']),
      (23, 'f15', false, 'مستخلص ختامي',                3, array['office_staff', 'contracts']),
      (24, 'f26', true,  'تكليف لجنة استلام نهائي',    4, array['office_staff']),
      (25, 'f17', false, 'محضر استلام نهائي',           4, array['office_staff', 'head:acceptance']),
      (26, 'f18', false, 'إقفال عقد',                   4, array['office_staff', 'contracts'])
    ) c(ord, key, is_new, name, stage, resp)
    order by ord
  loop
    if r.is_new then
      select * into v_old from public.form_defs where name = r.name;
    else
      select * into v_old from public.form_defs where key = r.key;
    end if;

    if v_old.key is null then
      v_key := r.key;
      if exists (select 1 from public.form_defs where key = v_key) then
        select coalesce(max(nullif(regexp_replace(key, '\D', '', 'g'), '')::int), 0) + 1 into v_n from public.form_defs;
        v_key := 'f' || lpad(v_n::text, 2, '0');
      end if;
      insert into public.form_defs (key, name, stage, sort, sensitive, responsible, active)
      values (v_key, r.name, r.stage::smallint, r.ord, false, r.resp, true);
      perform public.write_audit('config.form', null, v_key,
        jsonb_build_object('created', true, 'name', jsonb_build_object('to', r.name),
                           'stage', jsonb_build_object('to', r.stage), 'active', jsonb_build_object('to', true)),
        r.name);
      v_any := true;
    else
      update public.form_defs
         set name = r.name, stage = r.stage::smallint, sort = r.ord, responsible = r.resp, active = true
       where key = v_old.key;
      if v_old.name is distinct from r.name or v_old.stage <> r.stage or not v_old.active then
        perform public.write_audit('config.form', null, v_old.key,
          jsonb_strip_nulls(jsonb_build_object('created', false,
            'name', case when v_old.name is distinct from r.name
                         then jsonb_build_object('from', v_old.name, 'to', r.name) end,
            'stage', case when v_old.stage <> r.stage
                          then jsonb_build_object('from', v_old.stage, 'to', r.stage) end,
            'active', case when not v_old.active then jsonb_build_object('from', false, 'to', true) end)),
          r.name);
      end if;
      if v_old.name is distinct from r.name or v_old.stage <> r.stage or v_old.sort - 1000 <> r.ord
         or v_old.responsible is distinct from r.resp or not v_old.active then
        v_any := true;
      end if;
    end if;
    v_old := null;
  end loop;

  -- نماذج أضافها المدير خارج الدورة المعتمدة تبقى في آخر مرحلتها
  perform public.normalize_form_order();
  if v_any then
    perform public.write_audit('config.form_order', null, null,
      jsonb_build_object('order', (select jsonb_agg(key order by sort) from public.form_defs),
                         'reason', 'اعتماد الدورة المستندية للعقود – الإصدار 2'),
      'الدورة المستندية للعقود – الإصدار 2');
  end if;
  perform set_config('app.trusted', 'off', true);
end $$;

notify pgrst, 'reload schema';

select 'تم: الدورة المستندية للعقود – الإصدار 2 (25 بنداً في 5 مراحل، ومعها تكليف مهندس سلامة)' as result;
