-- استيراد المشاريع السبعة عشر من ملف «متابعة نماذج الدورة المستندية للمشاريع_1.xlsx»
-- يُشغَّل مرة واحدة بعد ملف المخطط.
begin;
set local app.seeding = 'on';

insert into public.projects (assign_no, code, name, owner, company, department, notes, eng_sup, eng_qty, eng_fol, eng_saf, sort_order) values ('001', '', 'اعمال نقل ركام ومخلفات انشائية من المدينة القديمة منطقة A', 'صندوق التنمية وإعادة إعمار ليبيا', 'المجموعة الوطنية للمقاولات العامة', 'supervision', '', 'سالم جمال الخرم', 'ح', '', '', 1);
insert into public.projects (assign_no, code, name, owner, company, department, notes, eng_sup, eng_qty, eng_fol, eng_saf, sort_order) values ('002', '', 'اعمال نقل ركام ومخلفات انشائية من المدينة القديمة منطقة A', 'صندوق التنمية وإعادة إعمار ليبيا', 'ليبيا العصرية للمقاولات العامة', 'supervision', '', 'عوض خالد سميو', '', '', '', 2);
insert into public.projects (assign_no, code, name, owner, company, department, notes, eng_sup, eng_qty, eng_fol, eng_saf, sort_order) values ('003', '', 'اعمال نقل ركام ومخلفات انشائية من المدينة القديمة منطقة A', 'صندوق التنمية وإعادة إعمار ليبيا', 'اثمار بنغازي للمقاولات', 'supervision', '', 'عبدالمنعم البراني', '', '', '', 3);
insert into public.projects (assign_no, code, name, owner, company, department, notes, eng_sup, eng_qty, eng_fol, eng_saf, sort_order) values ('004', '', '', 'صندوق التنمية وإعادة إعمار ليبيا', '', 'supervision', '', '', '', '', '', 4);
insert into public.projects (assign_no, code, name, owner, company, department, notes, eng_sup, eng_qty, eng_fol, eng_saf, sort_order) values ('005', '', 'اعمال طواري تشمل نقل المخلفات وإزالة العوائق ومعالجة مختنقات شبكات مياه الصرف صحي ورصف وصيانة طرق بالمدينة القديمة ووسط البلاد و اخريبيش والصابري', 'صندوق التنمية وإعادة إعمار ليبيا', 'جودة الاعمار للمقاولات العامة', 'supervision', '', 'سراج محمد لطيوش', '', '', '', 5);
insert into public.projects (assign_no, code, name, owner, company, department, notes, eng_sup, eng_qty, eng_fol, eng_saf, sort_order) values ('006', '', 'اعمال نقل ركام ومخلفات انشائية من منطفة سيدي خريبيش منطقة C', 'صندوق التنمية وإعادة إعمار ليبيا', 'درع ليبيا للمقاولات العامة', 'supervision', '', 'محمد يونس السعيطي', '', '', '', 6);
insert into public.projects (assign_no, code, name, owner, company, department, notes, eng_sup, eng_qty, eng_fol, eng_saf, sort_order) values ('007', '', 'اعمال نقل ركام ومخلفات انشائية من منطفة سيدي خريبيش منطقة C', 'صندوق التنمية وإعادة إعمار ليبيا', 'المجموعة الوطنية للمقاولات العامة', 'supervision', '', 'سالم جمال الخرم', '', '', '', 7);
insert into public.projects (assign_no, code, name, owner, company, department, notes, eng_sup, eng_qty, eng_fol, eng_saf, sort_order) values ('008', '', 'اعمال إعادة تأهيل طرق ومسارات ضمن منطقة الصابري و وسط لبلاد', 'صندوق التنمية وإعادة إعمار ليبيا', 'شركة المنارة المتجددة للمقاولات والاستثمار العقاري', 'supervision', '', 'محمد بلعيد العبيدي', '', '', '', 8);
insert into public.projects (assign_no, code, name, owner, company, department, notes, eng_sup, eng_qty, eng_fol, eng_saf, sort_order) values ('009', '', 'اعمال نقل ركام ومخلفات انشائية من منطقة الصابري منطقة E', 'صندوق التنمية وإعادة إعمار ليبيا', 'المجموعة الوطنية للمقاولات العامة', 'supervision', '', 'سالم جمال الخرم', '', '', '', 9);
insert into public.projects (assign_no, code, name, owner, company, department, notes, eng_sup, eng_qty, eng_fol, eng_saf, sort_order) values ('010', '', '', '', '', 'supervision', '', '', '', '', '', 10);
insert into public.projects (assign_no, code, name, owner, company, department, notes, eng_sup, eng_qty, eng_fol, eng_saf, sort_order) values ('011', '', 'اعمال طارئة ونقل الركام و المخلفات بالمنطقة D', 'صندوق التنمية وإعادة إعمار ليبيا', 'شركة بدرالحديث للمقاولات العامة', 'supervision', '', 'انس ادريس الظراط', '', '', '', 11);
insert into public.projects (assign_no, code, name, owner, company, department, notes, eng_sup, eng_qty, eng_fol, eng_saf, sort_order) values ('012', '', 'إنشاء فندق سيقرسيوني', 'صندوق الضمان الإجتماعي', 'شركة الجودة الإفريقية للمقاولات والاستثمار العقاري', 'supervision', '', '', 'لا ينطبق', '', '', 12);
insert into public.projects (assign_no, code, name, owner, company, department, notes, eng_sup, eng_qty, eng_fol, eng_saf, sort_order) values ('013', '', 'اعمال نقل ركام ومخلفات انشائية من منطقة الصابري منطقة E', 'صندوق التنمية وإعادة إعمار ليبيا', 'إثمار بنغازي للمقاولات العامة', 'supervision', '', 'عبدالمنعم البراني', '', '', '', 13);
insert into public.projects (assign_no, code, name, owner, company, department, notes, eng_sup, eng_qty, eng_fol, eng_saf, sort_order) values ('014', '', 'صيانة و تركيب أعمدة إنارة عامة للطرق الرئيسية بمنطقة الصابري و وسط البلاد', 'صندوق التنمية وإعادة إعمار ليبيا', 'إثمار بنغازي للمقاولات العامة', 'supervision', '', 'عبدالمعز الفرجاني', '', '', '', 14);
insert into public.projects (assign_no, code, name, owner, company, department, notes, eng_sup, eng_qty, eng_fol, eng_saf, sort_order) values ('015', '', 'اعمال نقل ركام ومخلفات انشائية من منطقة الصابري منطقة E', 'صندوق التنمية وإعادة إعمار ليبيا', 'ليبيا العصرية للمقاولات العامة', 'supervision', '', 'عوض خالد سميو', '', '', '', 15);
insert into public.projects (assign_no, code, name, owner, company, department, notes, eng_sup, eng_qty, eng_fol, eng_saf, sort_order) values ('016', '', '', '', '', 'supervision', '', '', '', '', '', 16);
insert into public.projects (assign_no, code, name, owner, company, department, notes, eng_sup, eng_qty, eng_fol, eng_saf, sort_order) values ('017', '', 'اعمال نقل ركام و مخلفات انشائية ومعالجة مختنقات شبكات مياه وصرف صحي بالمدينة القديمة ووسط البلاد', 'صندوق التنمية وإعادة إعمار ليبيا', '', 'supervision', '', 'محمد يونس السعيطي', '', '', '', 17);

insert into public.project_forms (project_id, form_key, status)
select p.id, v.form_key, v.status::public.form_status
from (values
  ('001', 'f01', 'wip'),
  ('001', 'f04', 'done'),
  ('001', 'f08', 'done'),
  ('001', 'f09', 'done'),
  ('001', 'f10', 'na'),
  ('001', 'f11', 'na'),
  ('001', 'f14', 'na'),
  ('001', 'f15', 'done'),
  ('002', 'f01', 'wip'),
  ('002', 'f04', 'done'),
  ('002', 'f08', 'done'),
  ('002', 'f09', 'done'),
  ('002', 'f10', 'na'),
  ('002', 'f11', 'na'),
  ('003', 'f01', 'wip'),
  ('003', 'f04', 'done'),
  ('003', 'f08', 'done'),
  ('003', 'f09', 'done'),
  ('003', 'f10', 'na'),
  ('003', 'f11', 'na'),
  ('004', 'f01', 'wip'),
  ('004', 'f04', 'done'),
  ('004', 'f10', 'na'),
  ('004', 'f11', 'na'),
  ('005', 'f01', 'wip'),
  ('005', 'f04', 'done'),
  ('005', 'f08', 'done'),
  ('005', 'f09', 'done'),
  ('005', 'f10', 'na'),
  ('005', 'f11', 'na'),
  ('006', 'f01', 'wip'),
  ('006', 'f04', 'done'),
  ('006', 'f08', 'done'),
  ('006', 'f09', 'done'),
  ('006', 'f10', 'na'),
  ('006', 'f11', 'na'),
  ('007', 'f01', 'wip'),
  ('007', 'f04', 'done'),
  ('007', 'f08', 'done'),
  ('007', 'f09', 'done'),
  ('007', 'f10', 'na'),
  ('007', 'f11', 'na'),
  ('007', 'f14', 'na'),
  ('007', 'f15', 'done'),
  ('008', 'f01', 'wip'),
  ('008', 'f04', 'done'),
  ('008', 'f08', 'done'),
  ('008', 'f09', 'done'),
  ('008', 'f10', 'na'),
  ('008', 'f11', 'na'),
  ('009', 'f01', 'wip'),
  ('009', 'f04', 'done'),
  ('009', 'f08', 'done'),
  ('009', 'f09', 'done'),
  ('009', 'f10', 'na'),
  ('009', 'f11', 'na'),
  ('010', 'f01', 'wip'),
  ('010', 'f10', 'na'),
  ('010', 'f11', 'na'),
  ('011', 'f01', 'wip'),
  ('011', 'f04', 'done'),
  ('011', 'f08', 'done'),
  ('011', 'f09', 'done'),
  ('011', 'f10', 'na'),
  ('011', 'f11', 'na'),
  ('012', 'f01', 'na'),
  ('012', 'f03', 'na'),
  ('012', 'f04', 'done'),
  ('012', 'f05', 'na'),
  ('012', 'f08', 'done'),
  ('012', 'f10', 'na'),
  ('012', 'f11', 'na'),
  ('013', 'f01', 'wip'),
  ('013', 'f04', 'done'),
  ('013', 'f08', 'done'),
  ('013', 'f09', 'done'),
  ('013', 'f10', 'na'),
  ('013', 'f11', 'na'),
  ('014', 'f01', 'wip'),
  ('014', 'f04', 'done'),
  ('014', 'f08', 'done'),
  ('014', 'f09', 'done'),
  ('014', 'f10', 'na'),
  ('014', 'f11', 'na'),
  ('015', 'f01', 'wip'),
  ('015', 'f04', 'done'),
  ('015', 'f08', 'done'),
  ('015', 'f09', 'done'),
  ('015', 'f10', 'na'),
  ('015', 'f11', 'na'),
  ('016', 'f01', 'wip'),
  ('016', 'f10', 'na'),
  ('016', 'f11', 'na'),
  ('017', 'f01', 'wip'),
  ('017', 'f04', 'done'),
  ('017', 'f08', 'done'),
  ('017', 'f09', 'done'),
  ('017', 'f10', 'na'),
  ('017', 'f11', 'na')
) as v(assign_no, form_key, status)
join public.projects p on p.assign_no = v.assign_no;

select public.write_audit('system.import', null, null, jsonb_build_object('projects', 17, 'source', 'متابعة نماذج الدورة المستندية للمشاريع_1.xlsx'), 'استيراد أولي');
commit;
