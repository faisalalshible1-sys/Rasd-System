// =====================================================================
// أقسام الوحدات (الترحيل 21): الترميم والمباني التاريخية، مكتب التخطيط وضمان الجودة،
// مكتب السلامة المهنية، المطابقة والاستلام.
// مواصفات أنواع السجلات الثلاثة عشر وتسمياتها ونموذجها وفهرسها. الحساب والعرض فقط؛
// الصلاحيات والتحقق الفعلي في قاعدة البيانات (unit_kind_spec وsave_unit_record).
// =====================================================================

DateTime? _day(Object? v) {
  if (v == null) return null;
  final d = DateTime.tryParse(v.toString());
  return d == null ? null : DateTime(d.year, d.month, d.day);
}

DateTime? _ts(Object? v) => v == null ? null : DateTime.tryParse(v.toString())?.toLocal();
String _s(Object? v) => v == null ? '' : v.toString();
double? _d(Object? v) => v is num ? v.toDouble() : double.tryParse(_s(v));

String _iso(DateTime? d) =>
    d == null ? '' : '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

// ---------------------------------------------------------------------
// الأقسام والوحدات
// ---------------------------------------------------------------------
/// الأقسام الأربعة في الشاشة الرئيسية بالترتيب.
const List<String> unitSections = ['heritage', 'planning_qa', 'safety', 'acceptance'];

/// الوحدات السبع بالترتيب (تطابق جدول org_units).
const List<String> unitKeys = ['heritage', 'planning', 'quality_assurance', 'follow_up', 'safety', 'receiving', 'quality_control'];

const Map<String, String> unitNames = {
  'heritage': 'الترميم والمباني التاريخية',
  'planning': 'قسم التخطيط',
  'quality_assurance': 'قسم ضمان الجودة',
  'follow_up': 'قسم المتابعة',
  'safety': 'مكتب السلامة المهنية',
  'receiving': 'وحدة الاستلام',
  'quality_control': 'وحدة ضبط الجودة',
};

const Map<String, String> unitSectionOf = {
  'heritage': 'heritage',
  'planning': 'planning_qa',
  'quality_assurance': 'planning_qa',
  'follow_up': 'planning_qa',
  'safety': 'safety',
  'receiving': 'acceptance',
  'quality_control': 'acceptance',
};

/// أسماء الأقسام كما تظهر في الشاشة الرئيسية.
const Map<String, String> unitSectionNames = {
  'heritage': 'الترميم والمباني التاريخية',
  'planning_qa': 'مكتب التخطيط وضمان الجودة',
  'safety': 'مكتب السلامة المهنية',
  'acceptance': 'المطابقة والاستلام',
};

List<String> unitsOfSection(String section) => [for (final u in unitKeys) if (unitSectionOf[u] == section) u];

/// أنواع السجلات في كل وحدة بالترتيب.
const Map<String, List<String>> unitKindsOf = {
  'heritage': ['heritage_building', 'heritage_assessment'],
  'planning': ['plan'],
  'quality_assurance': ['qa_audit', 'ncr'],
  'follow_up': ['followup_task'],
  'safety': ['safety_inspection', 'safety_incident', 'safety_violation'],
  'receiving': ['handover', 'punch_item'],
  'quality_control': ['qc_test', 'material_approval'],
};

// ---------------------------------------------------------------------
// مواصفات الأنواع
// ---------------------------------------------------------------------
enum UnitFieldType { text, long, number, select }

class UnitField {
  const UnitField(this.key, this.label, this.type, {this.options = const [], this.helper, this.max = 300});

  final String key;
  final String label;
  final UnitFieldType type;

  /// للقوائم: القيم كما تُحفظ وتُعرض.
  final List<String> options;
  final String? helper;
  final int max;
}

/// نبرة لون الحالة أو التصنيف في الواجهة.
enum UnitTone { neutral, info, ok, wip, danger }

class UnitKind {
  const UnitKind({
    required this.key,
    required this.unit,
    required this.label,
    required this.single,
    required this.titleLabel,
    this.dateLabel = 'التاريخ',
    this.refLabel = 'الرقم',
    required this.statuses,
    required this.closed,
    this.statusTones = const {},
    this.levels = const [],
    this.levelLabel = '',
    this.levelTones = const {},
    this.parent,
    this.parentRequired = false,
    this.projectRequired = false,
    this.dueLabel,
    this.progress = false,
    this.ownerLabel,
    this.fields = const [],
  });

  final String key;
  final String unit;

  /// اسم السجل بالجمع (عنوان الصفحة) والمفرد (عنوان النموذج).
  final String label;
  final String single;
  final String titleLabel;
  final String dateLabel;
  final String refLabel;

  /// الحالات بالترتيب: (المفتاح، التسمية)؛ الأولى افتراضية.
  final List<(String, String)> statuses;

  /// الحالات التي تعني أن السجل أُغلق (يُسجَّل تاريخ إغلاقه ولا يُحسب متأخراً).
  final Set<String> closed;
  final Map<String, UnitTone> statusTones;

  /// التصنيف (الحالة الإنشائية، الخطورة، النتيجة…): (المفتاح، التسمية). فارغة إن لم يكن للنوع تصنيف.
  final List<(String, String)> levels;
  final String levelLabel;
  final Map<String, UnitTone> levelTones;

  /// النوع الأم إن كان السجل يتبع سجلاً آخر.
  final String? parent;
  final bool parentRequired;
  final bool projectRequired;

  /// اسم حقل الموعد (null: لا موعد لهذا النوع).
  final String? dueLabel;

  /// نسبة إنجاز من 0 إلى 100.
  final bool progress;

  /// اسم حقل «المسؤول» (null: لا يظهر).
  final String? ownerLabel;

  /// الحقول الخاصة بالنوع (تُحفظ في data).
  final List<UnitField> fields;

  bool get hasLevels => levels.any((l) => l.$1.isNotEmpty);
  String get defaultStatus => statuses.first.$1;
  String get defaultLevel => levels.isEmpty ? '' : levels.first.$1;

  String statusLabel(String s) {
    for (final x in statuses) {
      if (x.$1 == s) return x.$2;
    }
    return s;
  }

  String levelLabelOf(String l) {
    for (final x in levels) {
      if (x.$1 == l) return x.$2;
    }
    return l;
  }

  UnitTone statusTone(String s) => statusTones[s] ?? (closed.contains(s) ? UnitTone.ok : UnitTone.wip);
  UnitTone levelTone(String l) => levelTones[l] ?? UnitTone.neutral;

  /// الأنواع التي تتبع هذا النوع (مثل تقييمات المبنى أو ملاحظات محضر الاستلام).
  List<UnitKind> get children => [for (final k in unitKinds.values) if (k.parent == key) k];
}

const _conditionLevels = [('good', 'جيدة'), ('fair', 'متوسطة'), ('poor', 'سيئة'), ('critical', 'خطرة')];
const _conditionTones = {'good': UnitTone.ok, 'fair': UnitTone.info, 'poor': UnitTone.wip, 'critical': UnitTone.danger};

/// الأنواع الثلاثة عشر (تطابق unit_kind_spec في قاعدة البيانات).
const Map<String, UnitKind> unitKinds = {
  // ------------------------------------------------ الترميم والمباني التاريخية
  'heritage_building': UnitKind(
    key: 'heritage_building',
    unit: 'heritage',
    label: 'سجل المباني التاريخية',
    single: 'مبنى تاريخي',
    titleLabel: 'اسم المبنى',
    dateLabel: 'تاريخ التسجيل',
    refLabel: 'رقم القيد',
    statuses: [('registered', 'مسجّل'), ('under_study', 'قيد الدراسة'), ('under_restoration', 'قيد الترميم'), ('restored', 'مُرمَّم')],
    closed: {'restored'},
    statusTones: {'registered': UnitTone.neutral, 'under_study': UnitTone.info, 'under_restoration': UnitTone.wip, 'restored': UnitTone.ok},
    levels: _conditionLevels,
    levelLabel: 'الحالة الإنشائية',
    levelTones: _conditionTones,
    ownerLabel: 'الجهة المالكة',
    fields: [
      UnitField('area', 'المنطقة', UnitFieldType.text, helper: 'مثل: وسط البلاد، الصابري'),
      UnitField('location', 'العنوان أو الإحداثيات', UnitFieldType.text),
      UnitField('era', 'الحقبة التاريخية', UnitFieldType.select,
          options: ['العهد العثماني', 'العهد الإيطالي', 'ما بعد الاستقلال', 'أقدم من ذلك', 'غير محددة']),
      UnitField('build_year', 'سنة البناء التقريبية', UnitFieldType.text, max: 30),
      UnitField('grade', 'درجة الحماية', UnitFieldType.select, options: ['مسجّل وطنياً', 'مسجّل محلياً', 'مقترح للتسجيل', 'غير مصنّف']),
      UnitField('style', 'الطراز المعماري', UnitFieldType.text),
      UnitField('current_use', 'الاستخدام الحالي', UnitFieldType.text),
      UnitField('floors', 'عدد الطوابق', UnitFieldType.number),
      UnitField('area_m2', 'المساحة المبنية (م²)', UnitFieldType.number),
      UnitField('description', 'الوصف التاريخي والمعماري', UnitFieldType.long, max: 2000),
    ],
  ),
  'heritage_assessment': UnitKind(
    key: 'heritage_assessment',
    unit: 'heritage',
    label: 'تقييمات الحالة',
    single: 'تقييم حالة',
    titleLabel: 'عنوان التقييم',
    dateLabel: 'تاريخ التقييم',
    statuses: [('draft', 'مسودة'), ('final', 'معتمد')],
    closed: {'final'},
    statusTones: {'draft': UnitTone.wip, 'final': UnitTone.ok},
    levels: _conditionLevels,
    levelLabel: 'الحالة الإنشائية',
    levelTones: _conditionTones,
    parent: 'heritage_building',
    parentRequired: true,
    ownerLabel: 'المقيِّم',
    fields: [
      UnitField('urgency', 'أولوية التدخل', UnitFieldType.select, options: ['عاجلة', 'خلال سنة', 'مراقبة دورية']),
      UnitField('cost_estimate', 'التكلفة التقديرية للتدخل', UnitFieldType.number),
      UnitField('structure', 'العناصر الإنشائية', UnitFieldType.long, max: 2000),
      UnitField('facades', 'الواجهات والزخارف', UnitFieldType.long, max: 2000),
      UnitField('damages', 'الأضرار وأسبابها', UnitFieldType.long, max: 2000),
      UnitField('recommendations', 'التوصيات', UnitFieldType.long, max: 2000),
    ],
  ),
  // ------------------------------------------------ قسم التخطيط
  'plan': UnitKind(
    key: 'plan',
    unit: 'planning',
    label: 'الخطط',
    single: 'خطة',
    titleLabel: 'اسم الخطة',
    dateLabel: 'بداية الخطة',
    statuses: [('draft', 'مسودة'), ('active', 'قيد التنفيذ'), ('done', 'منجزة'), ('cancelled', 'ملغاة')],
    closed: {'done', 'cancelled'},
    statusTones: {'draft': UnitTone.neutral, 'active': UnitTone.info, 'done': UnitTone.ok, 'cancelled': UnitTone.neutral},
    levels: [('annual', 'سنوية'), ('quarterly', 'ربع سنوية'), ('monthly', 'شهرية'), ('project', 'خاصة بعقد')],
    levelLabel: 'نوع الخطة',
    dueLabel: 'نهاية الخطة',
    progress: true,
    ownerLabel: 'الجهة المسؤولة',
    fields: [
      UnitField('kpi', 'مؤشر الأداء', UnitFieldType.text),
      UnitField('target', 'القيمة المستهدفة', UnitFieldType.text, max: 120),
      UnitField('actual', 'القيمة المحققة', UnitFieldType.text, max: 120),
      UnitField('budget', 'الموازنة التقديرية', UnitFieldType.number),
      UnitField('objectives', 'الأهداف والأنشطة', UnitFieldType.long, max: 2000),
    ],
  ),
  // ------------------------------------------------ قسم ضمان الجودة
  'qa_audit': UnitKind(
    key: 'qa_audit',
    unit: 'quality_assurance',
    label: 'التدقيقات',
    single: 'تدقيق',
    titleLabel: 'موضوع التدقيق',
    dateLabel: 'تاريخ التدقيق',
    statuses: [('planned', 'مخطط'), ('in_progress', 'جارٍ'), ('done', 'مكتمل'), ('cancelled', 'ملغى')],
    closed: {'done', 'cancelled'},
    statusTones: {'planned': UnitTone.neutral, 'in_progress': UnitTone.info, 'done': UnitTone.ok, 'cancelled': UnitTone.neutral},
    levels: [('', 'لم تُحدَّد بعد'), ('satisfactory', 'مرضية'), ('needs_improvement', 'تحتاج تحسيناً'), ('unsatisfactory', 'غير مرضية')],
    levelLabel: 'النتيجة',
    levelTones: {'satisfactory': UnitTone.ok, 'needs_improvement': UnitTone.wip, 'unsatisfactory': UnitTone.danger},
    ownerLabel: 'المدقِّق',
    fields: [
      UnitField('auditee', 'الجهة المدقَّق عليها', UnitFieldType.text),
      UnitField('scope', 'النطاق والمعايير', UnitFieldType.long, max: 2000),
      UnitField('findings', 'الملاحظات', UnitFieldType.long, max: 2000),
    ],
  ),
  'ncr': UnitKind(
    key: 'ncr',
    unit: 'quality_assurance',
    label: 'حالات عدم المطابقة',
    single: 'حالة عدم مطابقة',
    titleLabel: 'وصف عدم المطابقة',
    dateLabel: 'تاريخ الرصد',
    statuses: [('open', 'مفتوحة'), ('in_progress', 'قيد المعالجة'), ('closed', 'مغلقة')],
    closed: {'closed'},
    statusTones: {'open': UnitTone.danger, 'in_progress': UnitTone.wip, 'closed': UnitTone.ok},
    levels: [('minor', 'بسيطة'), ('major', 'جسيمة'), ('critical', 'حرجة')],
    levelLabel: 'الدرجة',
    levelTones: {'minor': UnitTone.info, 'major': UnitTone.wip, 'critical': UnitTone.danger},
    parent: 'qa_audit',
    dueLabel: 'موعد الإجراء التصحيحي',
    ownerLabel: 'المسؤول عن المعالجة',
    fields: [
      UnitField('requirement', 'المتطلب المخالف', UnitFieldType.text),
      UnitField('root_cause', 'السبب الجذري', UnitFieldType.long, max: 2000),
      UnitField('corrective_action', 'الإجراء التصحيحي', UnitFieldType.long, max: 2000),
      UnitField('verification', 'التحقق من فعالية الإجراء', UnitFieldType.long, max: 2000),
    ],
  ),
  // ------------------------------------------------ قسم المتابعة
  'followup_task': UnitKind(
    key: 'followup_task',
    unit: 'follow_up',
    label: 'التكليفات',
    single: 'تكليف',
    titleLabel: 'موضوع التكليف',
    dateLabel: 'تاريخ التكليف',
    statuses: [('open', 'قيد المتابعة'), ('done', 'منجز'), ('cancelled', 'ملغى')],
    closed: {'done', 'cancelled'},
    statusTones: {'open': UnitTone.info, 'done': UnitTone.ok, 'cancelled': UnitTone.neutral},
    levels: [('normal', 'عادية'), ('high', 'مهمة'), ('urgent', 'عاجلة')],
    levelLabel: 'الأولوية',
    levelTones: {'high': UnitTone.wip, 'urgent': UnitTone.danger},
    dueLabel: 'الموعد',
    ownerLabel: 'المكلَّف',
    fields: [
      UnitField('source', 'مصدر التكليف', UnitFieldType.text, helper: 'اجتماع، مراسلة، توجيه المدير…'),
      UnitField('progress_notes', 'ما تمّ', UnitFieldType.long, max: 2000),
    ],
  ),
  // ------------------------------------------------ مكتب السلامة المهنية
  'safety_inspection': UnitKind(
    key: 'safety_inspection',
    unit: 'safety',
    label: 'جولات التفتيش',
    single: 'جولة تفتيش',
    titleLabel: 'موضوع الجولة',
    dateLabel: 'تاريخ الجولة',
    statuses: [('open', 'ملاحظات قائمة'), ('closed', 'مغلقة')],
    closed: {'closed'},
    levels: [('excellent', 'ممتاز'), ('good', 'جيد'), ('acceptable', 'مقبول'), ('poor', 'ضعيف')],
    levelLabel: 'التقييم العام',
    levelTones: {'excellent': UnitTone.ok, 'good': UnitTone.ok, 'acceptable': UnitTone.wip, 'poor': UnitTone.danger},
    projectRequired: true,
    ownerLabel: 'المفتش',
    fields: [
      UnitField('score', 'نسبة الالتزام (%)', UnitFieldType.number),
      UnitField('workers', 'عدد العمالة وقت الجولة', UnitFieldType.number),
      UnitField('ppe', 'معدات الوقاية الشخصية', UnitFieldType.text),
      UnitField('observations', 'الملاحظات', UnitFieldType.long, max: 2000),
      UnitField('actions', 'الإجراءات المطلوبة', UnitFieldType.long, max: 2000),
    ],
  ),
  'safety_incident': UnitKind(
    key: 'safety_incident',
    unit: 'safety',
    label: 'الحوادث',
    single: 'حادث',
    titleLabel: 'وصف مختصر للحادث',
    dateLabel: 'تاريخ الحادث',
    statuses: [('open', 'مسجّل'), ('investigating', 'قيد التحقيق'), ('closed', 'مغلق')],
    closed: {'closed'},
    statusTones: {'open': UnitTone.danger, 'investigating': UnitTone.wip, 'closed': UnitTone.ok},
    levels: [('near_miss', 'حادث وشيك'), ('minor', 'بسيط'), ('major', 'جسيم'), ('critical', 'خطير')],
    levelLabel: 'الخطورة',
    levelTones: {'near_miss': UnitTone.info, 'minor': UnitTone.wip, 'major': UnitTone.danger, 'critical': UnitTone.danger},
    ownerLabel: 'المبلِّغ',
    fields: [
      UnitField('incident_type', 'نوع الحادث', UnitFieldType.select,
          options: ['إصابة عمل', 'سقوط من ارتفاع', 'سقوط أجسام', 'حريق', 'صعق كهربائي', 'انهيار حفرية', 'حادث معدات', 'أضرار ممتلكات', 'أخرى']),
      UnitField('injured', 'عدد المصابين', UnitFieldType.number),
      UnitField('lost_days', 'أيام العمل الضائعة', UnitFieldType.number),
      UnitField('location', 'مكان الحادث', UnitFieldType.text),
      UnitField('description', 'تفاصيل الحادث', UnitFieldType.long, max: 2000),
      UnitField('immediate_action', 'الإجراء الفوري', UnitFieldType.long, max: 2000),
      UnitField('root_cause', 'نتيجة التحقيق والسبب الجذري', UnitFieldType.long, max: 2000),
    ],
  ),
  'safety_violation': UnitKind(
    key: 'safety_violation',
    unit: 'safety',
    label: 'المخالفات',
    single: 'مخالفة',
    titleLabel: 'المخالفة',
    dateLabel: 'تاريخ الرصد',
    statuses: [('open', 'قائمة'), ('closed', 'عولجت')],
    closed: {'closed'},
    statusTones: {'open': UnitTone.danger, 'closed': UnitTone.ok},
    levels: [('low', 'منخفضة'), ('medium', 'متوسطة'), ('high', 'عالية')],
    levelLabel: 'الخطورة',
    levelTones: {'low': UnitTone.info, 'medium': UnitTone.wip, 'high': UnitTone.danger},
    parent: 'safety_inspection',
    projectRequired: true,
    dueLabel: 'موعد المعالجة',
    ownerLabel: 'المسؤول عن المعالجة',
    fields: [
      UnitField('category', 'التصنيف', UnitFieldType.select, options: [
        'معدات الوقاية الشخصية', 'العمل على ارتفاع', 'الكهرباء', 'الحفريات', 'المعدات والرافعات', 'السقالات', 'النظافة والترتيب',
        'مكافحة الحريق', 'أخرى',
      ]),
      UnitField('corrective_action', 'الإجراء المطلوب', UnitFieldType.long, max: 2000),
      UnitField('penalty', 'الجزاء المطبّق', UnitFieldType.text),
    ],
  ),
  // ------------------------------------------------ وحدة الاستلام
  'handover': UnitKind(
    key: 'handover',
    unit: 'receiving',
    label: 'محاضر الاستلام',
    single: 'محضر استلام',
    titleLabel: 'موضوع المحضر',
    dateLabel: 'تاريخ الاستلام',
    refLabel: 'رقم المحضر',
    statuses: [('scheduled', 'مجدول'), ('accepted', 'مقبول'), ('accepted_notes', 'مقبول بملاحظات'), ('rejected', 'مرفوض')],
    closed: {'accepted', 'accepted_notes', 'rejected'},
    statusTones: {'scheduled': UnitTone.info, 'accepted': UnitTone.ok, 'accepted_notes': UnitTone.wip, 'rejected': UnitTone.danger},
    levels: [('initial', 'ابتدائي'), ('final', 'نهائي'), ('partial', 'جزئي')],
    levelLabel: 'نوع الاستلام',
    projectRequired: true,
    ownerLabel: 'رئيس اللجنة',
    fields: [
      UnitField('committee', 'أعضاء اللجنة', UnitFieldType.long, max: 1000),
      UnitField('contractor_rep', 'ممثل المقاول', UnitFieldType.text),
      UnitField('scope', 'الأعمال المستلمة', UnitFieldType.long, max: 2000),
      UnitField('decision', 'قرار اللجنة', UnitFieldType.long, max: 2000),
    ],
  ),
  'punch_item': UnitKind(
    key: 'punch_item',
    unit: 'receiving',
    label: 'قوائم الملاحظات',
    single: 'ملاحظة استلام',
    titleLabel: 'الملاحظة',
    dateLabel: 'تاريخ الرصد',
    statuses: [('open', 'قائمة'), ('closed', 'أُصلحت')],
    closed: {'closed'},
    statusTones: {'open': UnitTone.danger, 'closed': UnitTone.ok},
    levels: [('', '')],
    parent: 'handover',
    parentRequired: true,
    dueLabel: 'موعد الإصلاح',
    ownerLabel: 'المسؤول عن الإصلاح',
    fields: [UnitField('location', 'الموقع في المبنى', UnitFieldType.text)],
  ),
  // ------------------------------------------------ وحدة ضبط الجودة
  'qc_test': UnitKind(
    key: 'qc_test',
    unit: 'quality_control',
    label: 'الاختبارات',
    single: 'اختبار',
    titleLabel: 'الاختبار',
    dateLabel: 'تاريخ الاختبار',
    refLabel: 'رقم التقرير',
    statuses: [('pending', 'بانتظار النتيجة'), ('passed', 'مطابق'), ('failed', 'غير مطابق')],
    closed: {'passed', 'failed'},
    statusTones: {'pending': UnitTone.info, 'passed': UnitTone.ok, 'failed': UnitTone.danger},
    levels: [('concrete', 'خرسانة'), ('soil', 'تربة'), ('steel', 'حديد تسليح'), ('asphalt', 'أسفلت'), ('masonry', 'طوب ومباني'), ('other', 'أخرى')],
    levelLabel: 'نوع الاختبار',
    projectRequired: true,
    ownerLabel: 'المختبر',
    fields: [
      UnitField('sample', 'العينة وموقعها', UnitFieldType.text),
      UnitField('standard', 'المواصفة', UnitFieldType.text),
      UnitField('required', 'القيمة المطلوبة', UnitFieldType.text, max: 60),
      UnitField('result', 'النتيجة', UnitFieldType.text, max: 60),
      UnitField('unit', 'وحدة القياس', UnitFieldType.text, max: 30),
    ],
  ),
  'material_approval': UnitKind(
    key: 'material_approval',
    unit: 'quality_control',
    label: 'اعتماد المواد',
    single: 'طلب اعتماد مادة',
    titleLabel: 'المادة',
    dateLabel: 'تاريخ التقديم',
    statuses: [('under_review', 'قيد المراجعة'), ('approved', 'معتمدة'), ('approved_notes', 'معتمدة بملاحظات'), ('rejected', 'مرفوضة')],
    closed: {'approved', 'approved_notes', 'rejected'},
    statusTones: {'under_review': UnitTone.info, 'approved': UnitTone.ok, 'approved_notes': UnitTone.wip, 'rejected': UnitTone.danger},
    levels: [('', '')],
    projectRequired: true,
    dueLabel: 'موعد الرد',
    ownerLabel: 'المورّد أو المصنّع',
    fields: [
      UnitField('spec_ref', 'بند المواصفات', UnitFieldType.text),
      UnitField('samples', 'العينات والكتالوجات المقدّمة', UnitFieldType.text),
      UnitField('decision_notes', 'ملاحظات الاعتماد', UnitFieldType.long, max: 2000),
    ],
  ),
};

UnitKind? unitKind(String key) => unitKinds[key];

// ---------------------------------------------------------------------
// النموذج
// ---------------------------------------------------------------------
class UnitRecord {
  const UnitRecord({
    required this.id,
    required this.unit,
    required this.kind,
    this.projectId,
    this.originProject,
    this.parentId,
    required this.title,
    this.refNo = '',
    required this.recDate,
    this.dueDate,
    required this.status,
    this.level = '',
    this.progress,
    this.ownerText = '',
    this.closedAt,
    this.data = const {},
    this.notes = '',
    this.createdAt,
    this.createdBy,
    this.updatedAt,
  });

  final String id;
  final String unit;
  final String kind;
  final String? projectId;
  final String? originProject;
  final String? parentId;
  final String title;
  final String refNo;
  final DateTime recDate;
  final DateTime? dueDate;
  final String status;
  final String level;

  /// نسبة الإنجاز من 0 إلى 100 (للخطط).
  final double? progress;
  final String ownerText;
  final DateTime? closedAt;
  final Map<String, dynamic> data;
  final String notes;
  final DateTime? createdAt;
  final String? createdBy;
  final DateTime? updatedAt;

  factory UnitRecord.fromMap(Map<String, dynamic> m) => UnitRecord(
        id: _s(m['id']),
        unit: _s(m['unit']),
        kind: _s(m['kind']),
        projectId: m['project_id'] as String?,
        originProject: m['origin_project'] as String?,
        parentId: m['parent_id'] as String?,
        title: _s(m['title']),
        refNo: _s(m['ref_no']),
        recDate: _day(m['rec_date']) ?? DateTime(2000),
        dueDate: _day(m['due_date']),
        status: _s(m['status']),
        level: _s(m['level']),
        progress: _d(m['progress']),
        ownerText: _s(m['owner_text']),
        closedAt: _day(m['closed_at']),
        data: m['data'] is Map ? Map<String, dynamic>.from(m['data'] as Map) : const {},
        notes: _s(m['notes']),
        createdAt: _ts(m['created_at']),
        createdBy: m['created_by'] as String?,
        updatedAt: _ts(m['updated_at']),
      );

  UnitKind? get spec => unitKinds[kind];
  bool get isClosed => spec?.closed.contains(status) ?? false;

  /// تجاوز موعده ولم يُغلق.
  bool overdue(DateTime today) => !isClosed && dueDate != null && dueDate!.isBefore(today);

  /// الأيام المتبقية حتى الموعد (سالبة إن تجاوزه).
  int? daysLeft(DateTime today) => dueDate?.difference(today).inDays;

  String get statusLabel => spec?.statusLabel(status) ?? status;
  String get levelLabel => spec?.levelLabelOf(level) ?? level;

  /// قيمة حقل خاص للعرض.
  String field(String key) {
    final v = data[key];
    if (v == null) return '';
    if (v is num) return v % 1 == 0 ? v.toInt().toString() : v.toString();
    return v.toString();
  }

  /// القيم كما تُرسل إلى save_unit_record (لنموذج التعديل): الحقول العامة بأسمائها والخاصة بالبادئة f_.
  Map<String, dynamic> toForm() => {
        'project_id': projectId ?? '',
        'parent_id': parentId ?? '',
        'title': title,
        'ref_no': refNo,
        'rec_date': _iso(recDate),
        'due_date': _iso(dueDate),
        'status': status,
        'level': level,
        'progress': progress == null ? null : progress! / 100,
        'owner_text': ownerText,
        'notes': notes,
        for (final e in data.entries) 'f_${e.key}': e.value,
      };
}

/// يحوّل قيم النموذج إلى ما تستقبله save_unit_record: الحقول الخاصة (f_*) تُجمع في data،
/// والنسبة من 0–1 (كما يعيدها حقل النسبة) إلى 0–100.
Map<String, dynamic> unitPayload(UnitKind k, Map<String, dynamic> form, {bool create = false}) {
  final data = <String, dynamic>{};
  for (final f in k.fields) {
    final v = form['f_${f.key}'];
    if (v == null) continue;
    if (v is String && v.trim().isEmpty) continue;
    data[f.key] = v;
  }
  final p = form['progress'];
  return {
    if (create) 'kind': k.key,
    for (final key in const ['project_id', 'parent_id', 'title', 'ref_no', 'rec_date', 'due_date', 'status', 'level', 'owner_text', 'notes'])
      if (form.containsKey(key)) key: form[key],
    'progress': p is num ? double.parse((p * 100).toStringAsFixed(2)) : null,
    'data': data,
  };
}

/// فهرس سجلات الوحدات (يُبنى عند كل تحميل).
class UnitIndex {
  UnitIndex(this.records) {
    for (final r in records) {
      (_byKind[r.kind] ??= []).add(r);
      if (r.parentId != null) (_children[r.parentId!] ??= []).add(r);
      _byId[r.id] = r;
    }
    int cmp(UnitRecord a, UnitRecord b) {
      final c = b.recDate.compareTo(a.recDate);
      return c != 0 ? c : (b.createdAt ?? DateTime(2000)).compareTo(a.createdAt ?? DateTime(2000));
    }

    for (final l in [..._byKind.values, ..._children.values]) {
      l.sort(cmp);
    }
  }

  UnitIndex.empty() : this(const []);

  final List<UnitRecord> records;
  final Map<String, List<UnitRecord>> _byKind = {};
  final Map<String, List<UnitRecord>> _children = {};
  final Map<String, UnitRecord> _byId = {};

  UnitRecord? byId(String id) => _byId[id];

  /// سجلات نوع، من الأحدث إلى الأقدم.
  List<UnitRecord> ofKind(String kind) => _byKind[kind] ?? const [];
  List<UnitRecord> ofUnit(String unit) => [for (final k in unitKindsOf[unit] ?? const <String>[]) ...ofKind(k)];
  List<UnitRecord> childrenOf(String id, [String? kind]) =>
      [for (final r in _children[id] ?? const <UnitRecord>[]) if (kind == null || r.kind == kind) r];
  List<UnitRecord> ofProject(String projectId) => records.where((r) => r.projectId == projectId).toList();

  int openOf(String kind) => ofKind(kind).where((r) => !r.isClosed).length;
  int overdueOf(String kind, DateTime today) => ofKind(kind).where((r) => r.overdue(today)).length;
  int overdueInUnit(String unit, DateTime today) => ofUnit(unit).where((r) => r.overdue(today)).length;
}

// ---------------------------------------------------------------------
// المؤشرات (تُشرح معادلاتها في فصول دليل الاستخدام 22–25)
// ---------------------------------------------------------------------
double? _num(Object? v) => v is num ? v.toDouble() : double.tryParse(_s(v));

/// مؤشرات لوحات الأقسام والشاشة الرئيسية، محسوبة من السجلات بتاريخ [today].
class UnitStats {
  UnitStats(this.index, DateTime today) : today = DateTime(today.year, today.month, today.day);

  final UnitIndex index;
  final DateTime today;

  bool _thisMonth(DateTime d) => d.year == today.year && d.month == today.month;
  bool _thisYear(DateTime d) => d.year == today.year;
  int _count(String kind, bool Function(UnitRecord r) test) => index.ofKind(kind).where(test).length;

  static double? _avg(Iterable<double> xs) {
    final l = xs.toList();
    return l.isEmpty ? null : l.reduce((a, b) => a + b) / l.length;
  }

  // ------------------------------------------------ الترميم والمباني التاريخية
  int get buildings => index.ofKind('heritage_building').length;

  /// المباني بحالة إنشائية «سيئة» أو «خطرة».
  int get buildingsAtRisk => _count('heritage_building', (r) => r.level == 'poor' || r.level == 'critical');
  int get underRestoration => _count('heritage_building', (r) => r.status == 'under_restoration');
  int get restored => _count('heritage_building', (r) => r.status == 'restored');
  int get assessmentsThisYear => _count('heritage_assessment', (r) => _thisYear(r.recDate));

  /// أحدث تقييم للمبنى (بتاريخ التقييم).
  UnitRecord? latestAssessment(String buildingId) {
    final l = index.childrenOf(buildingId, 'heritage_assessment');
    return l.isEmpty ? null : l.first;
  }

  // ------------------------------------------------ قسم التخطيط
  int get activePlans => _count('plan', (r) => r.status == 'active');

  /// متوسط نسبة إنجاز الخطط «قيد التنفيذ» التي سُجّلت لها نسبة (0–100).
  double? get avgActiveProgress => _avg([for (final r in index.ofKind('plan')) if (r.status == 'active' && r.progress != null) r.progress!]);
  int get overduePlans => index.overdueOf('plan', today);

  // ------------------------------------------------ قسم ضمان الجودة
  int get auditsThisYear => _count('qa_audit', (r) => _thisYear(r.recDate) && r.status != 'cancelled');
  int get openNcr => index.openOf('ncr');

  /// حالات عدم مطابقة مفتوحة درجتها «جسيمة» أو «حرجة».
  int get seriousOpenNcr => _count('ncr', (r) => !r.isClosed && (r.level == 'major' || r.level == 'critical'));
  int get overdueNcr => index.overdueOf('ncr', today);

  // ------------------------------------------------ قسم المتابعة
  int get openTasks => _count('followup_task', (r) => r.status == 'open');
  int get overdueTasks => index.overdueOf('followup_task', today);

  /// نسبة الإنجاز في الموعد: التكليفات المنجزة التي لها موعد وأُغلقت في موعدها أو قبله ÷ كل المنجزة التي لها موعد.
  double? get onTimeRate {
    final done = [for (final r in index.ofKind('followup_task')) if (r.status == 'done' && r.dueDate != null && r.closedAt != null) r];
    if (done.isEmpty) return null;
    return done.where((r) => !r.closedAt!.isAfter(r.dueDate!)).length / done.length;
  }

  // ------------------------------------------------ مكتب السلامة المهنية
  /// الأيام منذ آخر حادث (عدا الحوادث الوشيكة)؛ null إن لم يُسجَّل حادث.
  int? get daysWithoutIncident {
    DateTime? last;
    for (final r in index.ofKind('safety_incident')) {
      if (r.level == 'near_miss') continue;
      if (last == null || r.recDate.isAfter(last)) last = r.recDate;
    }
    if (last == null) return null;
    final d = today.difference(last).inDays;
    return d < 0 ? 0 : d;
  }

  int get inspectionsThisMonth => _count('safety_inspection', (r) => _thisMonth(r.recDate));

  /// متوسط «نسبة الالتزام» لجولات هذا الشهر التي سُجّلت لها نسبة (0–100).
  double? get avgComplianceThisMonth =>
      _avg([for (final r in index.ofKind('safety_inspection')) if (_thisMonth(r.recDate) && _num(r.data['score']) != null) _num(r.data['score'])!]);
  int get incidentsThisYear => _count('safety_incident', (r) => _thisYear(r.recDate) && r.level != 'near_miss');
  int get nearMissesThisYear => _count('safety_incident', (r) => _thisYear(r.recDate) && r.level == 'near_miss');

  /// مجموع «أيام العمل الضائعة» لحوادث هذا العام.
  int get lostDaysThisYear => index
      .ofKind('safety_incident')
      .where((r) => _thisYear(r.recDate))
      .fold(0, (s, r) => s + (_num(r.data['lost_days']) ?? 0).round());
  int get openIncidents => index.openOf('safety_incident');
  int get openViolations => index.openOf('safety_violation');
  int get overdueViolations => index.overdueOf('safety_violation', today);

  // ------------------------------------------------ وحدة الاستلام
  int get scheduledHandovers => _count('handover', (r) => r.status == 'scheduled');
  int get handoversThisYear => _count('handover', (r) => _thisYear(r.recDate) && r.status != 'scheduled');
  int get openPunch => index.openOf('punch_item');
  int get overduePunch => index.overdueOf('punch_item', today);

  // ------------------------------------------------ وحدة ضبط الجودة
  int get testsThisMonth => _count('qc_test', (r) => _thisMonth(r.recDate));
  int get pendingTests => _count('qc_test', (r) => r.status == 'pending');

  /// نسبة المطابقة: الاختبارات «المطابقة» ÷ (المطابقة + غير المطابقة)؛ لا تدخل فيها الاختبارات بانتظار النتيجة.
  double? get passRate {
    final passed = _count('qc_test', (r) => r.status == 'passed');
    final failed = _count('qc_test', (r) => r.status == 'failed');
    return passed + failed == 0 ? null : passed / (passed + failed);
  }

  int get materialsUnderReview => _count('material_approval', (r) => r.status == 'under_review');
  int get overdueMaterials => index.overdueOf('material_approval', today);

  /// كل السجلات المتأخرة في قسم، من الأقدم موعداً.
  List<UnitRecord> overdueInSection(String section) => [
        for (final u in unitsOfSection(section))
          for (final r in index.ofUnit(u))
            if (r.overdue(today)) r,
      ]..sort((a, b) => a.dueDate!.compareTo(b.dueDate!));
}
