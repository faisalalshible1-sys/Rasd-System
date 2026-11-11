// متابعة المشاريع (الإصدار السابع): نماذج ملف «سجل المخاطر ومتابعة المشاريع – الإصدار 2.0» وحساباته:
// البرنامج الزمني، والتقدم الدوري (SPI والسرعة والتوقع)، والوضع الحالي للمخاطر من مراجعاتها،
// والمشاكل والتأخيرات والتغييرات والدروس، ومؤشرات أداء الشركات، والتقرير الدوري، والتنبيهات.

import 'models.dart';
import 'registers.dart';

DateTime? _day(dynamic v) {
  if (v == null) return null;
  final d = DateTime.tryParse(v.toString());
  return d == null ? null : DateTime(d.year, d.month, d.day);
}

int? _int(dynamic v) => v is num ? v.toInt() : int.tryParse('${v ?? ''}');
double? _num(dynamic v) => v is num ? v.toDouble() : double.tryParse('${v ?? ''}');
String _str(dynamic v) => v == null ? '' : v.toString();

/// تاريخ اليوم بلا وقت.
DateTime pmToday() {
  final n = DateTime.now();
  return DateTime(n.year, n.month, n.day);
}

/// الفرق بالأيام بين تاريخين (a − b) دون أثر للتوقيت الصيفي.
int daysBetween(DateTime a, DateTime b) =>
    DateTime.utc(a.year, a.month, a.day).difference(DateTime.utc(b.year, b.month, b.day)).inDays;

DateTime addDays(DateTime d, int n) => DateTime(d.year, d.month, d.day + n);

String pmDay(DateTime? d) => d == null ? '—' : '${d.year}/${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}';

String pmIso(DateTime? d) =>
    d == null ? '' : '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

// =====================================================================
// القوائم الثابتة (المعلّمة 🔒 في الملف: مستخدمة في الحسابات)
// =====================================================================
const List<String> opStatuses = ['not_started', 'running', 'suspended', 'completed', 'prov_accepted', 'final_accepted'];
const Map<String, String> opStatusLabels = {
  'not_started': 'لم يبدأ',
  'running': 'جارٍ',
  'suspended': 'موقوف',
  'completed': 'منجز',
  'prov_accepted': 'مستلم ابتدائياً',
  'final_accepted': 'مستلم نهائياً',
};
const Set<String> opDone = {'completed', 'prov_accepted', 'final_accepted'};

const List<String> pmPriorities = ['high', 'medium', 'low'];
const Map<String, String> pmPriorityLabels = {'high': 'عالية', 'medium': 'متوسطة', 'low': 'منخفضة'};

const List<String> pmParties = ['contractor', 'owner', 'consultant', 'utilities', 'force_majeure', 'other'];
const Map<String, String> pmPartyLabels = {
  'contractor': 'المقاول',
  'owner': 'الجهة المالكة (اللجنة)',
  'consultant': 'الاستشاري',
  'utilities': 'جهات خدمية وحكومية',
  'force_majeure': 'ظروف قاهرة',
  'other': 'أخرى',
};

const List<String> issueStatuses = ['open', 'in_progress', 'closed'];
const Map<String, String> issueStatusLabels = {'open': 'مفتوحة', 'in_progress': 'قيد المعالجة', 'closed': 'مغلقة'};

const List<String> delayClasses = ['excusable_comp', 'excusable', 'non_excusable', 'concurrent'];
const Map<String, String> delayClassLabels = {
  'excusable_comp': 'معذور مع تعويض',
  'excusable': 'معذور دون تعويض',
  'non_excusable': 'غير معذور',
  'concurrent': 'متزامن',
};
const Map<String, String> delayClassMeaning = {
  'excusable_comp': 'يستحق المقاول تمديداً وقد يستحق تعويضاً عن التكاليف',
  'excusable': 'يستحق المقاول تمديداً دون تعويض مالي',
  'non_excusable': 'لا يستحق تمديداً – تُطبق أحكام غرامة التأخير وفق العقد',
  'concurrent': 'يُحلل كل حالة على حدة لتوزيع المسؤولية',
};

const List<String> changeSources = ['owner', 'consultant', 'contractor', 'site', 'external'];
const Map<String, String> changeSourceLabels = {
  'owner': 'الجهة المالكة',
  'consultant': 'الاستشاري',
  'contractor': 'المقاول',
  'site': 'متطلبات الموقع',
  'external': 'جهات خارجية',
};
const List<String> changeStatuses = ['submitted', 'under_study', 'approved', 'rejected'];
const Map<String, String> changeStatusLabels = {'submitted': 'مقدم', 'under_study': 'قيد الدراسة', 'approved': 'معتمد', 'rejected': 'مرفوض'};

const List<String> lessonTypes = ['positive', 'negative'];
const Map<String, String> lessonTypeLabels = {'positive': 'إيجابي – ممارسة ناجحة', 'negative': 'سلبي – فرصة تحسين'};
const List<String> lessonStatuses = ['proposed', 'approved', 'applied'];
const Map<String, String> lessonStatusLabels = {'proposed': 'مقترح', 'approved': 'معتمد', 'applied': 'مُطبَّق'};

/// مؤشر الأداء الزمني للمشروع.
const List<String> perfKeys = ['ahead', 'on_track', 'slight', 'critical', 'done', 'not_started', 'suspended', 'no_data'];
const Map<String, String> perfLabels = {
  'ahead': 'متقدم',
  'on_track': 'ضمن المخطط',
  'slight': 'تأخر بسيط',
  'critical': 'متأخر حرج',
  'done': 'منجز',
  'not_started': 'لم يبدأ',
  'suspended': 'موقوف',
  'no_data': 'بلا قياس',
};

/// معايير التقييم الميداني الستة.
const List<(String, String)> evalCriteria = [
  ('quality', 'جودة الأعمال'),
  ('safety', 'السلامة المهنية'),
  ('schedule', 'الالتزام بالبرنامج الزمني'),
  ('resources', 'كفاءة الجهاز الفني والمعدات'),
  ('cooperation', 'الاستجابة والتعاون'),
  ('documentation', 'التوثيق والتقارير'),
];
const Map<int, String> evalScaleLabels = {5: 'ممتاز', 4: 'جيد جداً', 3: 'جيد', 2: 'مقبول', 1: 'ضعيف'};

/// اتجاه الخطر منذ المراجعة السابقة.
const Map<String, String> trendLabels = {'up': '▲ متصاعد', 'down': '▼ متراجع', 'flat': '● ثابت', 'none': 'لم يُراجع بعد'};

// =====================================================================
// الإعدادات (pm.config)
// =====================================================================
class PmGrade {
  const PmGrade(this.min, this.name, this.rec);

  final double min;
  final String name;
  final String rec;

  Map<String, dynamic> toJson() => {'min': min, 'name': name, 'rec': rec};
}

class PmConfig {
  const PmConfig({
    this.projectTypes = const [],
    this.departments = const [],
    this.delayCauses = const [],
    this.changeTypes = const [],
    this.changeReasons = const [],
    this.lessonApply = const [],
    this.alertDays = 7,
    this.spiAhead = 1.05,
    this.spiOk = 0.95,
    this.spiWarn = 0.85,
    this.changeLimit = 0.10,
    this.changeDecideDays = 21,
    this.issueDays = 14,
    this.staleDays = 10,
    this.forecastDelayAlert = 30,
    this.weights = const {'schedule': 0.3, 'delay': 0.15, 'field': 0.4, 'response': 0.15},
    this.spiZero = 0.7,
    this.delayZero = 0.2,
    this.grades = const [],
    this.refDate,
    this.raw = const {},
  });

  final List<String> projectTypes;
  final List<String> departments;
  final List<String> delayCauses;
  final List<String> changeTypes;
  final List<String> changeReasons;
  final List<String> lessonApply;
  final int alertDays;
  final double spiAhead;
  final double spiOk;
  final double spiWarn;
  final double changeLimit;
  final int changeDecideDays;
  final int issueDays;
  final int staleDays;
  final int forecastDelayAlert;
  final Map<String, double> weights;
  final double spiZero;
  final double delayZero;
  final List<PmGrade> grades;
  final DateTime? refDate;

  /// القيمة كما حُفظت (لتعديلها دون فقد مفاتيح لا يعرفها هذا الإصدار).
  final Map<String, dynamic> raw;

  static const List<PmGrade> defaultGrades = [
    PmGrade(0, 'ضعيف', 'تحتاج مراجعة قبل أي إسناد جديد'),
    PmGrade(50, 'مقبول', 'إسناد مشروط بخطة تحسين'),
    PmGrade(65, 'جيد', 'مؤهلة مع متابعة'),
    PmGrade(75, 'جيد جداً', 'مؤهلة'),
    PmGrade(85, 'ممتاز', 'مؤهلة ومفضّلة'),
  ];

  static const PmConfig defaults = PmConfig(
    projectTypes: ['طرق', 'جسور', 'مبانٍ عامة', 'مدارس', 'إسكان', 'مرافق وشبكات', 'ترميم مبانٍ تراثية', 'فراغات عامة وأحياء', 'مرافق صحية'],
    departments: ['الإشراف والتنسيق', 'الشؤون الفنية', 'الترميم', 'المطابقة والاستلام', 'مكتب المدير'],
    delayCauses: [
      'التمويل والمستخلصات', 'التصميم والمخططات', 'أوامر التغيير', 'المقاول – الموارد والإدارة', 'المواد والتوريد', //
      'الموقع وتسليمه', 'المرافق والجهات الخدمية', 'الاعتمادات والتصاريح', 'الظروف الجوية', 'مخلفات الحرب والأمن', 'أخرى',
    ],
    changeTypes: ['أمر تغيير', 'أعمال إضافية', 'حذف أعمال', 'تعديل تصميم', 'تعديل مواصفات', 'تمديد مدة'],
    changeReasons: [
      'نقص أو خطأ في التصميم', 'طلب الجهة المالكة', 'ظروف موقع غير متوقعة', 'تعارض مع مرافق قائمة', //
      'تحديث مواصفات أو معايير', 'اقتراح توفير من المقاول', 'متطلبات الحفاظ التراثي', 'أخرى',
    ],
    lessonApply: ['تعديل نموذج', 'تعديل إجراء', 'شرط تعاقدي', 'تدريب', 'معيار تأهيل', 'أخرى'],
    grades: defaultGrades,
  );

  static PmConfig fromJson(dynamic v) {
    if (v is! Map) return defaults;
    final m = Map<String, dynamic>.from(v);
    List<String> list(String k, List<String> d) =>
        m[k] is List ? [for (final e in m[k] as List) if (e.toString().trim().isNotEmpty) e.toString().trim()] : d;
    double dbl(String k, double d) => _num(m[k]) ?? d;
    int integer(String k, int d) => _int(m[k]) ?? d;
    final w = <String, double>{};
    if (m['weights'] is Map) {
      (m['weights'] as Map).forEach((k, x) {
        final d = _num(x);
        if (d != null) w[k.toString()] = d;
      });
    }
    final gr = <PmGrade>[];
    if (m['grades'] is List) {
      for (final g in m['grades'] as List) {
        if (g is Map && _num(g['min']) != null && _str(g['name']).isNotEmpty) {
          gr.add(PmGrade(_num(g['min'])!, _str(g['name']), _str(g['rec'])));
        }
      }
    }
    gr.sort((a, b) => a.min.compareTo(b.min));
    return PmConfig(
      projectTypes: list('project_types', defaults.projectTypes),
      departments: list('departments', defaults.departments),
      delayCauses: list('delay_causes', defaults.delayCauses),
      changeTypes: list('change_types', defaults.changeTypes),
      changeReasons: list('change_reasons', defaults.changeReasons),
      lessonApply: list('lesson_apply', defaults.lessonApply),
      alertDays: integer('alert_days', 7),
      spiAhead: dbl('spi_ahead', 1.05),
      spiOk: dbl('spi_ok', 0.95),
      spiWarn: dbl('spi_warn', 0.85),
      changeLimit: dbl('change_limit', 0.10),
      changeDecideDays: integer('change_decide_days', 21),
      issueDays: integer('issue_days', 14),
      staleDays: integer('stale_days', 10),
      forecastDelayAlert: integer('forecast_delay_alert', 30),
      weights: w.length == 4 ? w : defaults.weights,
      spiZero: dbl('spi_zero', 0.7),
      delayZero: dbl('delay_zero', 0.2),
      grades: gr.length >= 2 ? gr : defaultGrades,
      refDate: _day(m['ref_date']),
      raw: m,
    );
  }

  /// تاريخ الإسناد: المثبّت في الإعدادات، وإلا اليوم.
  DateTime get refDay => refDate ?? pmToday();

  double weight(String k) => weights[k] ?? 0;

  PmGrade gradeOf(double score) {
    var g = grades.first;
    for (final x in grades) {
      if (score >= x.min) g = x;
    }
    return g;
  }

  /// أدنى تقديرين (مقبول وضعيف): يستوجبان خطة تحسين.
  bool isWeakGrade(String name) => grades.take(2).any((g) => g.name == name);
}

// =====================================================================
// الكيانات
// =====================================================================
class PmSchedule {
  const PmSchedule({
    required this.projectId,
    this.projectType = '',
    this.location = '',
    this.consultant = '',
    this.opStatus = 'running',
    this.startDate,
    this.endDate,
    this.notes = '',
  });

  final String projectId;
  final String projectType;
  final String location;
  final String consultant;
  final String opStatus;
  final DateTime? startDate;
  final DateTime? endDate;
  final String notes;

  factory PmSchedule.fromMap(Map<String, dynamic> m) => PmSchedule(
        projectId: _str(m['project_id']),
        projectType: _str(m['project_type']),
        location: _str(m['location']),
        consultant: _str(m['consultant']),
        opStatus: _str(m['op_status']).isEmpty ? 'running' : _str(m['op_status']),
        startDate: _day(m['start_date']),
        endDate: _day(m['end_date']),
        notes: _str(m['notes']),
      );

  Map<String, dynamic> toJson() => {
        'project_type': projectType,
        'location': location,
        'consultant': consultant,
        'op_status': opStatus,
        'start_date': pmIso(startDate),
        'end_date': pmIso(endDate),
        'notes': notes,
      };
}

class PmProgress {
  const PmProgress({
    required this.id,
    required this.projectId,
    required this.measuredOn,
    required this.planned,
    required this.actual,
    this.works = '',
    this.obstacles = '',
    this.preparedBy = '',
  });

  final String id;
  final String projectId;
  final DateTime measuredOn;
  final double planned;
  final double actual;
  final String works;
  final String obstacles;
  final String preparedBy;

  factory PmProgress.fromMap(Map<String, dynamic> m) => PmProgress(
        id: _str(m['id']),
        projectId: _str(m['project_id']),
        measuredOn: _day(m['measured_on']) ?? pmToday(),
        planned: _num(m['planned']) ?? 0,
        actual: _num(m['actual']) ?? 0,
        works: _str(m['works']),
        obstacles: _str(m['obstacles']),
        preparedBy: _str(m['prepared_by']),
      );

  double get deviation => actual - planned;
  double? get spi => planned == 0 ? null : actual / planned;

  Map<String, dynamic> toJson() => {
        'project_id': projectId,
        'measured_on': pmIso(measuredOn),
        'planned': planned,
        'actual': actual,
        'works': works,
        'obstacles': obstacles,
        'prepared_by': preparedBy,
      };
}

class RiskReview {
  const RiskReview({
    required this.id,
    required this.riskId,
    required this.reviewedOn,
    required this.probability,
    required this.impact,
    this.actionsDone = '',
    this.progress,
    this.reviewer = '',
    this.notes = '',
    this.createdAt,
  });

  final String id;
  final String riskId;
  final DateTime reviewedOn;
  final int probability;
  final int impact;
  final String actionsDone;
  final double? progress;
  final String reviewer;
  final String notes;
  final DateTime? createdAt;

  int get score => probability * impact;

  factory RiskReview.fromMap(Map<String, dynamic> m) => RiskReview(
        id: _str(m['id']),
        riskId: _str(m['risk_id']),
        reviewedOn: _day(m['reviewed_on']) ?? pmToday(),
        probability: _int(m['probability']) ?? 1,
        impact: _int(m['impact']) ?? 1,
        actionsDone: _str(m['actions_done']),
        progress: _num(m['progress']),
        reviewer: _str(m['reviewer']),
        notes: _str(m['notes']),
        createdAt: DateTime.tryParse(_str(m['created_at'])),
      );

  Map<String, dynamic> toJson() => {
        'reviewed_on': pmIso(reviewedOn),
        'probability': probability,
        'impact': impact,
        'actions_done': actionsDone,
        'progress': progress,
        'reviewer': reviewer,
        'notes': notes,
      };
}

class PmIssue {
  const PmIssue({
    required this.id,
    required this.code,
    required this.projectId,
    required this.detectedOn,
    required this.description,
    this.category = '',
    this.riskId,
    this.priority = 'medium',
    this.party = 'contractor',
    this.department = '',
    this.action = '',
    this.timeImpactDays,
    this.costImpact,
    this.targetDate,
    this.status = 'open',
    this.closedOn,
    this.notes = '',
  });

  final String id;
  final String code;
  final String projectId;
  final DateTime detectedOn;
  final String description;
  final String category;
  final String? riskId;
  final String priority;
  final String party;
  final String department;
  final String action;
  final int? timeImpactDays;
  final double? costImpact;
  final DateTime? targetDate;
  final String status;
  final DateTime? closedOn;
  final String notes;

  factory PmIssue.fromMap(Map<String, dynamic> m) => PmIssue(
        id: _str(m['id']),
        code: _str(m['code']),
        projectId: _str(m['project_id']),
        detectedOn: _day(m['detected_on']) ?? pmToday(),
        description: _str(m['description']),
        category: _str(m['category']),
        riskId: m['risk_id']?.toString(),
        priority: _str(m['priority']).isEmpty ? 'medium' : _str(m['priority']),
        party: _str(m['party']).isEmpty ? 'contractor' : _str(m['party']),
        department: _str(m['department']),
        action: _str(m['action']),
        timeImpactDays: _int(m['time_impact_days']),
        costImpact: _num(m['cost_impact']),
        targetDate: _day(m['target_date']),
        status: _str(m['status']).isEmpty ? 'open' : _str(m['status']),
        closedOn: _day(m['closed_on']),
        notes: _str(m['notes']),
      );

  bool get isClosed => status == 'closed';

  /// عمر المشكلة: حتى الإغلاق، أو حتى تاريخ الإسناد إن لم تُغلق.
  int age(DateTime ref) => daysBetween(closedOn ?? ref, detectedOn);

  String followUp(DateTime ref, int alertDays) {
    if (isClosed) return 'closed';
    if (targetDate == null) return 'none';
    if (targetDate!.isBefore(ref)) return 'overdue';
    if (daysBetween(targetDate!, ref) <= alertDays) return 'soon';
    return 'ontime';
  }

  int overdueDays(DateTime ref) => targetDate == null ? 0 : daysBetween(ref, targetDate!);

  Map<String, dynamic> toJson() => {
        'code': code,
        'project_id': projectId,
        'detected_on': pmIso(detectedOn),
        'description': description,
        'category': category,
        'risk_id': riskId ?? '',
        'priority': priority,
        'party': party,
        'department': department,
        'action': action,
        'time_impact_days': timeImpactDays,
        'cost_impact': costImpact,
        'target_date': pmIso(targetDate),
        'status': status,
        'closed_on': pmIso(closedOn),
        'notes': notes,
      };
}

class PmDelay {
  const PmDelay({
    required this.id,
    required this.code,
    required this.projectId,
    required this.description,
    this.cause = '',
    this.subCause = '',
    this.party = 'contractor',
    this.delayClass = '',
    this.critical = false,
    required this.startDate,
    this.endDate,
    this.eotRequested,
    this.eotApproved,
    this.refs = '',
    this.notes = '',
  });

  final String id;
  final String code;
  final String projectId;
  final String description;
  final String cause;
  final String subCause;
  final String party;
  final String delayClass;
  final bool critical;
  final DateTime startDate;
  final DateTime? endDate;
  final int? eotRequested;
  final int? eotApproved;
  final String refs;
  final String notes;

  factory PmDelay.fromMap(Map<String, dynamic> m) => PmDelay(
        id: _str(m['id']),
        code: _str(m['code']),
        projectId: _str(m['project_id']),
        description: _str(m['description']),
        cause: _str(m['cause']),
        subCause: _str(m['sub_cause']),
        party: _str(m['party']).isEmpty ? 'contractor' : _str(m['party']),
        delayClass: _str(m['delay_class']),
        critical: m['critical'] == true,
        startDate: _day(m['start_date']) ?? pmToday(),
        endDate: _day(m['end_date']),
        eotRequested: _int(m['eot_requested']),
        eotApproved: _int(m['eot_approved']),
        refs: _str(m['refs']),
        notes: _str(m['notes']),
      );

  bool get isOngoing => endDate == null;

  /// مدة الأثر: حتى نهايته، أو حتى تاريخ الإسناد إن كان قائماً.
  int days(DateTime ref) {
    final d = daysBetween(endDate ?? ref, startDate);
    return d < 0 ? 0 : d;
  }

  bool get eotPending => (eotRequested ?? 0) > 0 && eotApproved == null;

  Map<String, dynamic> toJson() => {
        'code': code,
        'project_id': projectId,
        'description': description,
        'cause': cause,
        'sub_cause': subCause,
        'party': party,
        'delay_class': delayClass,
        'critical': critical,
        'start_date': pmIso(startDate),
        'end_date': pmIso(endDate),
        'eot_requested': eotRequested,
        'eot_approved': eotApproved,
        'refs': refs,
        'notes': notes,
      };
}

class PmChange {
  const PmChange({
    required this.id,
    required this.code,
    required this.projectId,
    required this.submittedOn,
    required this.description,
    this.changeType = '',
    this.source = 'owner',
    this.reason = '',
    this.costEstimate,
    this.costApproved,
    this.timeRequested,
    this.timeApproved,
    this.status = 'submitted',
    this.decidedOn,
    this.approvalRef = '',
    this.refs = '',
    this.notes = '',
    this.variationId,
  });

  final String id;
  final String code;
  final String projectId;
  final DateTime submittedOn;
  final String description;
  final String changeType;
  final String source;
  final String reason;
  final double? costEstimate;
  final double? costApproved;
  final int? timeRequested;
  final int? timeApproved;
  final String status;
  final DateTime? decidedOn;
  final String approvalRef;
  final String refs;
  final String notes;
  final String? variationId;

  factory PmChange.fromMap(Map<String, dynamic> m) => PmChange(
        id: _str(m['id']),
        code: _str(m['code']),
        projectId: _str(m['project_id']),
        submittedOn: _day(m['submitted_on']) ?? pmToday(),
        description: _str(m['description']),
        changeType: _str(m['change_type']),
        source: _str(m['source']).isEmpty ? 'owner' : _str(m['source']),
        reason: _str(m['reason']),
        costEstimate: _num(m['cost_estimate']),
        costApproved: _num(m['cost_approved']),
        timeRequested: _int(m['time_requested']),
        timeApproved: _int(m['time_approved']),
        status: _str(m['status']).isEmpty ? 'submitted' : _str(m['status']),
        decidedOn: _day(m['decided_on']),
        approvalRef: _str(m['approval_ref']),
        refs: _str(m['refs']),
        notes: _str(m['notes']),
        variationId: m['variation_id']?.toString(),
      );

  bool get isApproved => status == 'approved';
  bool get isPending => status == 'submitted' || status == 'under_study';
  bool get isDecided => status == 'approved' || status == 'rejected';

  /// مدة البت: من التقديم إلى البت، أو إلى تاريخ الإسناد إن لم يُبت فيه.
  int decisionDays(DateTime ref) => daysBetween(decidedOn ?? ref, submittedOn);

  Map<String, dynamic> toJson() => {
        'code': code,
        'project_id': projectId,
        'submitted_on': pmIso(submittedOn),
        'description': description,
        'change_type': changeType,
        'source': source,
        'reason': reason,
        'cost_estimate': costEstimate,
        'cost_approved': costApproved,
        'time_requested': timeRequested,
        'time_approved': timeApproved,
        'status': status,
        'decided_on': pmIso(decidedOn),
        'approval_ref': approvalRef,
        'refs': refs,
        'notes': notes,
      };
}

class PmLesson {
  const PmLesson({
    required this.id,
    required this.code,
    this.projectId,
    required this.documentedOn,
    this.phase = '',
    this.domain = '',
    this.lessonType = 'negative',
    required this.situation,
    this.rootCause = '',
    this.effect = '',
    required this.lesson,
    this.applyMechanism = '',
    this.applyParty = '',
    this.refs = '',
    this.status = 'proposed',
    this.appliedOn,
    this.preparedBy = '',
  });

  final String id;
  final String code;
  final String? projectId;
  final DateTime documentedOn;
  final String phase;
  final String domain;
  final String lessonType;
  final String situation;
  final String rootCause;
  final String effect;
  final String lesson;
  final String applyMechanism;
  final String applyParty;
  final String refs;
  final String status;
  final DateTime? appliedOn;
  final String preparedBy;

  factory PmLesson.fromMap(Map<String, dynamic> m) => PmLesson(
        id: _str(m['id']),
        code: _str(m['code']),
        projectId: m['project_id']?.toString(),
        documentedOn: _day(m['documented_on']) ?? pmToday(),
        phase: _str(m['phase']),
        domain: _str(m['domain']),
        lessonType: _str(m['lesson_type']).isEmpty ? 'negative' : _str(m['lesson_type']),
        situation: _str(m['situation']),
        rootCause: _str(m['root_cause']),
        effect: _str(m['effect']),
        lesson: _str(m['lesson']),
        applyMechanism: _str(m['apply_mechanism']),
        applyParty: _str(m['apply_party']),
        refs: _str(m['refs']),
        status: _str(m['status']).isEmpty ? 'proposed' : _str(m['status']),
        appliedOn: _day(m['applied_on']),
        preparedBy: _str(m['prepared_by']),
      );

  Map<String, dynamic> toJson() => {
        'code': code,
        'project_id': projectId ?? '',
        'documented_on': pmIso(documentedOn),
        'phase': phase,
        'domain': domain,
        'lesson_type': lessonType,
        'situation': situation,
        'root_cause': rootCause,
        'effect': effect,
        'lesson': lesson,
        'apply_mechanism': applyMechanism,
        'apply_party': applyParty,
        'refs': refs,
        'status': status,
        'applied_on': pmIso(appliedOn),
        'prepared_by': preparedBy,
      };
}

class PmEvaluation {
  const PmEvaluation({
    required this.id,
    required this.projectId,
    this.company = '',
    required this.evaluatedOn,
    this.scores = const {},
    this.evaluator = '',
    this.notes = '',
  });

  final String id;
  final String projectId;
  final String company;
  final DateTime evaluatedOn;
  final Map<String, int?> scores;
  final String evaluator;
  final String notes;

  factory PmEvaluation.fromMap(Map<String, dynamic> m) => PmEvaluation(
        id: _str(m['id']),
        projectId: _str(m['project_id']),
        company: _str(m['company']),
        evaluatedOn: _day(m['evaluated_on']) ?? pmToday(),
        scores: {for (final c in evalCriteria) c.$1: _int(m[c.$1])},
        evaluator: _str(m['evaluator']),
        notes: _str(m['notes']),
      );

  /// متوسط المعايير المُقيَّمة (1–5).
  double? get average {
    final v = scores.values.whereType<int>().toList();
    return v.isEmpty ? null : v.reduce((a, b) => a + b) / v.length;
  }

  Map<String, dynamic> toJson() => {
        'project_id': projectId,
        'company': company,
        'evaluated_on': pmIso(evaluatedOn),
        for (final c in evalCriteria) c.$1: scores[c.$1],
        'evaluator': evaluator,
        'notes': notes,
      };
}

// =====================================================================
// الوضع الحالي للخطر (من آخر مراجعة) ومتابعته
// =====================================================================
class RiskState {
  RiskState._(this.risk, this.reviews, this.cfg, this.ref, this.alertDays);

  factory RiskState.of(Risk r, List<RiskReview> all, RiskConfig cfg, DateTime ref, int alertDays) {
    final list = [...all]..sort((a, b) {
        final c = a.reviewedOn.compareTo(b.reviewedOn);
        if (c != 0) return c;
        return (a.createdAt ?? DateTime(2000)).compareTo(b.createdAt ?? DateTime(2000));
      });
    return RiskState._(r, list, cfg, ref, alertDays);
  }

  final Risk risk;

  /// المراجعات من الأقدم إلى الأحدث.
  final List<RiskReview> reviews;
  final RiskConfig cfg;
  final DateTime ref;
  final int alertDays;

  RiskReview? get last => reviews.isEmpty ? null : reviews.last;
  RiskReview? get previous => reviews.length < 2 ? null : reviews[reviews.length - 2];

  int get initialScore => risk.score;
  int get currentProbability => last?.probability ?? risk.probability;
  int get currentImpact => last?.impact ?? risk.impact;
  int get currentScore => currentProbability * currentImpact;
  int? get targetScore => risk.residualScore;

  RiskLevel get initialLevel => cfg.level(initialScore)!;
  RiskLevel get currentLevel => cfg.level(currentScore)!;

  /// مسار التصعيد الحالي حسب المستوى الحالي.
  String get escalation => risk.isClosed ? '—' : currentLevel.action;

  /// الاتجاه: مقارنة آخر مراجعة بالسابقة (أو بالتقييم الأولي).
  String get trend {
    if (last == null) return 'none';
    final before = previous?.score ?? initialScore;
    if (currentScore > before) return 'up';
    if (currentScore < before) return 'down';
    return 'flat';
  }

  /// نسبة تنفيذ الإجراء الوقائي من آخر مراجعة.
  double get progress => last?.progress ?? 0;

  /// نسبة الخفض المحققة من الدرجة الأولية إلى الحالية.
  double get reduction => initialScore == 0 ? 0 : 1 - currentScore / initialScore;

  DateTime? get lastReviewDate => last?.reviewedOn ?? risk.registeredOn;
  int get reviewDays => cfg.reviewDaysFor(currentScore);

  /// موعد المراجعة القادمة = آخر مراجعة + دورية المراجعة حسب المستوى الحالي.
  DateTime? get nextReview => risk.isClosed || lastReviewDate == null ? null : addDays(lastReviewDate!, reviewDays);

  bool get isActive => !risk.isClosed;
  bool get isHighNow => isActive && cfg.isHigh(currentScore);

  String get followUp {
    if (risk.isClosed) return 'closed';
    final n = nextReview;
    if (n == null) return 'none';
    if (n.isBefore(ref) || (risk.targetDate != null && risk.targetDate!.isBefore(ref) && progress < 1)) return 'overdue';
    if (daysBetween(n, ref) <= alertDays) return 'soon';
    return 'ontime';
  }

  /// تحقق البيانات (معايير الإغلاق واكتمال الخطة)؛ null = سليم.
  String? get check {
    final r = risk;
    if (r.isClosed && (r.closedOn == null || progress < 1 || (targetScore != null && currentScore > targetScore!))) {
      return 'إغلاق غير مستوفٍ للمعايير';
    }
    final lv = cfg.levels;
    final planMin = lv.length >= 3 ? lv[lv.length - 3].min : lv.first.min;
    if (initialScore >= planMin && r.mitigation.trim().isEmpty) return 'خطة المعالجة ناقصة';
    if (initialScore >= cfg.highMin && r.earlyWarning.trim().isEmpty) return 'مؤشر الإنذار ناقص';
    return null;
  }
}

// =====================================================================
// سجل المشاريع: البرنامج الزمني والإنجاز والسرعة والتوقع
// =====================================================================
class ProjectTrack {
  ProjectTrack({
    required this.project,
    required this.schedule,
    required this.measurements,
    required this.cfg,
    required this.ref,
    required this.risks,
    required this.issues,
    required this.delays,
    required this.changes,
    required this.riskCfg,
  });

  final Project project;
  final PmSchedule? schedule;

  /// القياسات من الأقدم إلى الأحدث.
  final List<PmProgress> measurements;
  final PmConfig cfg;
  final DateTime ref;
  final List<RiskState> risks;
  final List<PmIssue> issues;
  final List<PmDelay> delays;
  final List<PmChange> changes;
  final RiskConfig riskCfg;

  String get opStatus => schedule?.opStatus ?? 'running';
  bool get isRunning => opStatus == 'running';
  DateTime? get start => schedule?.startDate;
  DateTime? get end => schedule?.endDate;
  int? get durationDays => start == null || end == null ? null : daysBetween(end!, start!);

  /// التمديد المعتمد = التغييرات المعتمدة + تمديدات أحداث التأخير المعتمدة.
  int get extensionDays =>
      changes.where((c) => c.isApproved).fold<int>(0, (a, c) => a + (c.timeApproved ?? 0)) +
      delays.fold<int>(0, (a, d) => a + (d.eotApproved ?? 0));

  DateTime? get revisedEnd => end == null ? null : addDays(end!, extensionDays);

  double? get elapsedPct {
    if (start == null || revisedEnd == null) return null;
    final total = daysBetween(revisedEnd!, start!);
    final v = daysBetween(ref, start!) / (total < 1 ? 1 : total);
    return v.clamp(0, 1).toDouble();
  }

  int? get remainingDays {
    if (revisedEnd == null) return null;
    if (opDone.contains(opStatus)) return 0;
    return daysBetween(revisedEnd!, ref);
  }

  PmProgress? get last => measurements.isEmpty ? null : measurements.last;
  PmProgress? get previous => measurements.length < 2 ? null : measurements[measurements.length - 2];
  DateTime? get lastDate => last?.measuredOn;
  double? get planned => last?.planned;
  double? get actual => last?.actual;
  double? get deviation => last?.deviation;
  double? get spi => last?.spi;

  /// سرعة الإنجاز الحالية (نقطة مئوية في الأسبوع × 100%) بين آخر قياسين.
  double? get speed {
    final p = previous, l = last;
    if (p == null || l == null) return null;
    final d = daysBetween(l.measuredOn, p.measuredOn);
    if (d <= 0) return null;
    return (l.actual - p.actual) / d * 7;
  }

  /// تجاوز المشروع مدته المعدّلة قبل اكتمال الإنجاز.
  bool get overrun => actual != null && actual! < 1 && revisedEnd != null && lastDate != null && !revisedEnd!.isAfter(lastDate!);

  /// السرعة المطلوبة للإنهاء في الموعد المعدّل.
  double? get requiredSpeed {
    final a = actual, rEnd = revisedEnd, ld = lastDate;
    if (a == null || rEnd == null || ld == null || a >= 1 || overrun) return null;
    return (1 - a) / daysBetween(rEnd, ld) * 7;
  }

  bool get tooSlow => speed != null && requiredSpeed != null && requiredSpeed! > speed!;

  DateTime? get forecastEnd {
    final a = actual, ld = lastDate;
    if (a == null || ld == null) return null;
    if (a >= 1) return ld;
    final s = speed;
    if (s == null || s <= 0) return null;
    return addDays(ld, ((1 - a) / s * 7).round());
  }

  int? get forecastDelay => forecastEnd == null || revisedEnd == null ? null : daysBetween(forecastEnd!, revisedEnd!);

  String get perf {
    if (opStatus == 'not_started') return 'not_started';
    if ((actual ?? 0) >= 1 || opDone.contains(opStatus)) return 'done';
    if (opStatus == 'suspended') return 'suspended';
    final s = spi;
    if (s == null) return 'no_data';
    if (s >= cfg.spiAhead) return 'ahead';
    if (s >= cfg.spiOk) return 'on_track';
    if (s >= cfg.spiWarn) return 'slight';
    return 'critical';
  }

  bool get isLate => perf == 'slight' || perf == 'critical';

  /// جارٍ دون قياس حديث (أكثر من أيام التنبيه).
  bool get stale => isRunning && (lastDate == null || daysBetween(ref, lastDate!) > cfg.staleDays);

  int get activeRisks => risks.where((r) => r.isActive).length;
  int get highRisksNow => risks.where((r) => r.isHighNow).length;
  int get openIssues => issues.where((i) => !i.isClosed).length;
  int get delayEvents => delays.length;
  int get delayDays => delays.fold<int>(0, (a, d) => a + d.days(ref));
  int get contractorDelayDays => delays.where((d) => d.party == 'contractor').fold<int>(0, (a, d) => a + d.days(ref));
  int get changesCount => changes.length;
  double get approvedChangesValue => changes.where((c) => c.isApproved).fold<double>(0, (a, c) => a + (c.costApproved ?? 0));
  double? get contractValue => project.contractValue;
  double? get revisedValue => contractValue == null ? null : contractValue! + approvedChangesValue;
  double? get changePct => contractValue == null || contractValue == 0 ? null : approvedChangesValue / contractValue!;
  bool get overChangeLimit => (changePct ?? 0) > cfg.changeLimit;

  /// آخر قياس حتى تاريخ معيّن (لحسابات التقرير الدوري).
  PmProgress? lastOnOrBefore(DateTime d) {
    PmProgress? out;
    for (final m in measurements) {
      if (!m.measuredOn.isAfter(d)) out = m;
    }
    return out;
  }
}

// =====================================================================
// مؤشرات أداء الشركات المنفذة
// =====================================================================
class ContractorKpi {
  ContractorKpi(this.name);

  final String name;
  int projects = 0;
  int running = 0;
  double totalValue = 0;
  final List<double> actuals = [];
  final List<double> spis = [];
  int contractorDelayDays = 0;
  int totalDuration = 0;
  int issuesAssigned = 0;
  int openIssues = 0;
  final List<int> issueAges = [];
  int safetyIssues = 0;
  int qualityIssues = 0;
  int changesFromContractor = 0;
  int rejectedChanges = 0;
  final List<double> fieldScores = [];

  double? scheduleScore;
  double? delayScore;
  double? fieldScore;
  double? responseScore;
  double? composite;
  PmGrade? grade;
  int rank = 0;

  double? get avgActual => actuals.isEmpty ? null : actuals.reduce((a, b) => a + b) / actuals.length;
  double? get avgSpi => spis.isEmpty ? null : spis.reduce((a, b) => a + b) / spis.length;
  double? get delayRatio => totalDuration == 0 ? null : contractorDelayDays / totalDuration;
  double? get avgIssueAge => issueAges.isEmpty ? null : issueAges.reduce((a, b) => a + b) / issueAges.length;
  double? get avgField => fieldScores.isEmpty ? null : fieldScores.reduce((a, b) => a + b) / fieldScores.length;
  int get evaluations => fieldScores.length;

  /// اكتمال البيانات: عدد المكونات المتاحة من أربعة.
  int get completeness => [scheduleScore, delayScore, fieldScore, responseScore].whereType<double>().length;

  void compute(PmConfig cfg) {
    final s = avgSpi;
    scheduleScore = s == null ? null : 100 * ((s - cfg.spiZero) / (1 - cfg.spiZero)).clamp(0, 1).toDouble();
    final r = delayRatio;
    delayScore = r == null ? null : 100 * (1 - r / cfg.delayZero).clamp(0, 1).toDouble();
    final f = avgField;
    fieldScore = f == null ? null : (f - 1) / 4 * 100;
    final a = avgIssueAge;
    responseScore = a == null ? null : 100 * (cfg.issueDays / (a < 1 ? 1 : a)).clamp(0, 1).toDouble();
    var sum = 0.0, w = 0.0;
    for (final (v, k) in [(scheduleScore, 'schedule'), (delayScore, 'delay'), (fieldScore, 'field'), (responseScore, 'response')]) {
      if (v != null) {
        sum += v * cfg.weight(k);
        w += cfg.weight(k);
      }
    }
    composite = w == 0 ? null : sum / w;
    grade = composite == null ? null : cfg.gradeOf(composite!);
  }
}

// =====================================================================
// تحليل أسباب التأخير
// =====================================================================
class DelayGroup {
  DelayGroup(this.key);

  final String key;
  int count = 0;
  int days = 0;
  int criticalDays = 0;
  int eotRequested = 0;
  int eotApproved = 0;
  int ongoing = 0;
  final Map<String, int> classDays = {};
  double pct = 0;
  double cumPct = 0;

  void add(PmDelay d, DateTime ref) {
    final n = d.days(ref);
    count++;
    days += n;
    if (d.critical) criticalDays += n;
    eotRequested += d.eotRequested ?? 0;
    eotApproved += d.eotApproved ?? 0;
    if (d.isOngoing) ongoing++;
    if (d.delayClass.isNotEmpty) classDays[d.delayClass] = (classDays[d.delayClass] ?? 0) + n;
  }

  /// التصنيف التعاقدي الغالب (الأكثر أياماً).
  String get dominantClass {
    if (classDays.isEmpty) return '';
    final e = classDays.entries.reduce((a, b) => b.value > a.value ? b : a);
    return e.key;
  }
}

class DelayAnalysis {
  DelayAnalysis(List<PmDelay> delays, this.ref) {
    for (final d in delays) {
      total.add(d, ref);
      (byCause[d.cause.isEmpty ? 'غير محدد' : d.cause] ??= DelayGroup(d.cause.isEmpty ? 'غير محدد' : d.cause)).add(d, ref);
      (byParty[d.party] ??= DelayGroup(d.party)).add(d, ref);
      (byClass[d.delayClass.isEmpty ? '' : d.delayClass] ??= DelayGroup(d.delayClass)).add(d, ref);
      (byProject[d.projectId] ??= DelayGroup(d.projectId)).add(d, ref);
      final row = matrix[d.cause.isEmpty ? 'غير محدد' : d.cause] ??= {};
      row[d.party] = (row[d.party] ?? 0) + d.days(ref);
      final pp = projectParties[d.projectId] ??= {};
      pp[d.party] = (pp[d.party] ?? 0) + d.days(ref);
    }
    pareto = byCause.values.toList()..sort((a, b) => b.days != a.days ? b.days.compareTo(a.days) : b.count.compareTo(a.count));
    var cum = 0.0;
    for (final g in pareto) {
      g.pct = total.days == 0 ? 0 : g.days / total.days;
      cum += g.pct;
      g.cumPct = cum;
    }
    for (final g in [...byParty.values, ...byClass.values, ...byProject.values]) {
      g.pct = total.days == 0 ? 0 : g.days / total.days;
    }
  }

  final DateTime ref;
  final DelayGroup total = DelayGroup('');
  final Map<String, DelayGroup> byCause = {};
  final Map<String, DelayGroup> byParty = {};
  final Map<String, DelayGroup> byClass = {};
  final Map<String, DelayGroup> byProject = {};
  final Map<String, Map<String, int>> matrix = {};
  final Map<String, Map<String, int>> projectParties = {};
  late final List<DelayGroup> pareto;

  /// الأسباب الحيوية القليلة: حتى 80% من أيام التأخير (مبدأ باريتو).
  bool isVital(DelayGroup g) => g.days > 0 && g.cumPct - g.pct < 0.8;
}

// =====================================================================
// التنبيهات (أبرز التنبيهات في لوحة القيادة)
// =====================================================================
class PmAlert {
  const PmAlert(this.key, this.label, this.count, this.action, this.tab);

  final String key;
  final String label;
  final int count;
  final String action;

  /// الصفحة التي تفتح المرجع.
  final int tab;
}

/// أرقام صفحات القسم (تطابق Tabs في الهيكل الرئيسي).
class PmTabs {
  static const dashboard = 40;
  static const projects = 41;
  static const progress = 42;
  static const issues = 43;
  static const delays = 44;
  static const changes = 45;
  static const lessons = 46;
  static const contractors = 47;
  static const report = 48;
  static const settings = 49;
  static const guide = 50;
  static const riskDashboard = 20;
  static const riskRegister = 21;
  static const riskMatrix = 22;
}

// =====================================================================
// التحليل الشامل: يُبنى مرة واحدة لكل تحميل للبيانات
// =====================================================================
class PmAnalysis {
  PmAnalysis({
    required List<Project> projects,
    required Map<String, PmSchedule> schedules,
    required List<PmProgress> progress,
    required List<Risk> risks,
    required List<RiskReview> reviews,
    required this.issues,
    required this.delays,
    required this.changes,
    required this.lessons,
    required this.evaluations,
    required this.riskCfg,
    required this.cfg,
  }) : ref = cfg.refDay {
    final revBy = <String, List<RiskReview>>{};
    for (final v in reviews) {
      (revBy[v.riskId] ??= []).add(v);
    }
    for (final r in risks) {
      riskStates[r.id] = RiskState.of(r, revBy[r.id] ?? const [], riskCfg, ref, riskCfg.alertDays);
    }
    final progBy = <String, List<PmProgress>>{};
    for (final m in progress) {
      (progBy[m.projectId] ??= []).add(m);
    }
    List<T> by<T>(List<T> l, String Function(T) key, String id) => l.where((x) => key(x) == id).toList();
    for (final p in projects) {
      final ms = [...(progBy[p.id] ?? const <PmProgress>[])]..sort((a, b) => a.measuredOn.compareTo(b.measuredOn));
      tracks[p.id] = ProjectTrack(
        project: p,
        schedule: schedules[p.id],
        measurements: ms,
        cfg: cfg,
        ref: ref,
        risks: [for (final r in risks) if (r.projectId == p.id) riskStates[r.id]!],
        issues: by(issues, (PmIssue i) => i.projectId, p.id),
        delays: by(delays, (PmDelay d) => d.projectId, p.id),
        changes: by(changes, (PmChange c) => c.projectId, p.id),
        riskCfg: riskCfg,
      );
    }
    delayAnalysis = DelayAnalysis(delays, ref);
    contractors = _contractors(projects);
  }

  final DateTime ref;
  final List<PmIssue> issues;
  final List<PmDelay> delays;
  final List<PmChange> changes;
  final List<PmLesson> lessons;
  final List<PmEvaluation> evaluations;
  final RiskConfig riskCfg;
  final PmConfig cfg;
  final Map<String, RiskState> riskStates = {};
  final Map<String, ProjectTrack> tracks = {};
  late final DelayAnalysis delayAnalysis;
  late final List<ContractorKpi> contractors;

  ProjectTrack? track(String projectId) => tracks[projectId];
  Iterable<RiskState> get riskList => riskStates.values;

  List<ContractorKpi> _contractors(List<Project> projects) {
    final by = <String, ContractorKpi>{};
    final projCompany = <String, String>{};
    for (final p in projects) {
      final name = p.company.trim();
      if (name.isEmpty) continue;
      projCompany[p.id] = name;
      final k = by[name] ??= ContractorKpi(name);
      final t = tracks[p.id]!;
      k.projects++;
      if (t.isRunning) k.running++;
      k.totalValue += p.contractValue ?? 0;
      if (t.actual != null) k.actuals.add(t.actual!);
      if (t.spi != null) k.spis.add(t.spi!);
      if (t.opStatus != 'not_started' && t.durationDays != null) k.totalDuration += t.durationDays!;
    }
    for (final d in delays) {
      final c = projCompany[d.projectId];
      if (c != null && d.party == 'contractor') by[c]!.contractorDelayDays += d.days(ref);
    }
    for (final i in issues) {
      final c = projCompany[i.projectId];
      if (c == null) continue;
      final k = by[c]!;
      if (i.party == 'contractor') {
        k.issuesAssigned++;
        if (!i.isClosed) k.openIssues++;
        k.issueAges.add(i.age(ref));
      }
      if (i.category == 'سلامة') k.safetyIssues++;
      if (i.category == 'جودة') k.qualityIssues++;
    }
    for (final ch in changes) {
      final c = projCompany[ch.projectId];
      if (c == null || ch.source != 'contractor') continue;
      by[c]!.changesFromContractor++;
      if (ch.status == 'rejected') by[c]!.rejectedChanges++;
    }
    for (final e in evaluations) {
      final name = e.company.trim().isNotEmpty ? e.company.trim() : (projCompany[e.projectId] ?? '');
      if (name.isEmpty) continue;
      final avg = e.average;
      if (avg == null) continue;
      (by[name] ??= ContractorKpi(name)).fieldScores.add(avg);
    }
    final list = by.values.toList();
    for (final k in list) {
      k.compute(cfg);
    }
    final ranked = list.where((k) => k.composite != null).toList()..sort((a, b) => b.composite!.compareTo(a.composite!));
    for (var i = 0; i < ranked.length; i++) {
      ranked[i].rank = i + 1;
    }
    list.sort((a, b) {
      if (a.composite == null && b.composite == null) return a.name.compareTo(b.name);
      if (a.composite == null) return 1;
      if (b.composite == null) return -1;
      return b.composite!.compareTo(a.composite!);
    });
    return list;
  }

  // ---------------------------------------------------------------
  // مؤشرات لوحة القيادة
  // ---------------------------------------------------------------
  List<ProjectTrack> get running => tracks.values.where((t) => t.isRunning).toList();

  /// متوسط موزون بقيمة العقد للمشاريع الجارية (بالتساوي إن لم تُسجَّل القيم).
  double? weighted(double? Function(ProjectTrack) f, [List<ProjectTrack>? list]) {
    final l = (list ?? running).where((t) => f(t) != null).toList();
    if (l.isEmpty) return null;
    final anyValue = l.any((t) => (t.contractValue ?? 0) > 0);
    var s = 0.0, w = 0.0;
    for (final t in l) {
      final wt = anyValue ? (t.contractValue ?? 0) : 1.0;
      s += f(t)! * wt;
      w += wt;
    }
    return w == 0 ? null : s / w;
  }

  double? get weightedActual => weighted((t) => t.actual);
  double? get weightedPlanned => weighted((t) => t.planned);
  double? get portfolioSpi {
    final a = weightedActual, p = weightedPlanned;
    return a == null || p == null || p == 0 ? null : a / p;
  }

  Map<String, int> get perfCounts {
    final out = <String, int>{};
    for (final t in tracks.values) {
      out[t.perf] = (out[t.perf] ?? 0) + 1;
    }
    return out;
  }

  int get activeRisks => riskList.where((r) => r.isActive).length;
  int get highRisksNow => riskList.where((r) => r.isHighNow).length;
  int get risingRisks => riskList.where((r) => r.isActive && r.trend == 'up').length;
  int get overdueReviews => riskList.where((r) => r.followUp == 'overdue').length;
  int get soonReviews => riskList.where((r) => r.followUp == 'soon').length;
  int get riskChecks => riskList.where((r) => r.check != null).length;
  int get openIssues => issues.where((i) => !i.isClosed).length;
  int get overdueIssues => issues.where((i) => i.followUp(ref, cfg.alertDays) == 'overdue').length;
  int get delayDays => delays.fold<int>(0, (a, d) => a + d.days(ref));
  int get criticalDelayDays => delays.where((d) => d.critical).fold<int>(0, (a, d) => a + d.days(ref));
  int get ongoingDelays => delays.where((d) => d.isOngoing).length;
  int get pendingEot => delays.where((d) => d.eotPending).length;
  int get extensions => tracks.values.fold<int>(0, (a, t) => a + t.extensionDays);
  double get approvedChangesValue => changes.where((c) => c.isApproved).fold<double>(0, (a, c) => a + (c.costApproved ?? 0));
  int get approvedChanges => changes.where((c) => c.isApproved).length;
  int get pendingChanges => changes.where((c) => c.isPending).length;
  int get lateDecisions => changes.where((c) => c.isPending && c.decisionDays(ref) > cfg.changeDecideDays).length;
  double get totalContractValue => tracks.values.fold<double>(0, (a, t) => a + (t.contractValue ?? 0));
  double? get changesPct => totalContractValue == 0 ? null : approvedChangesValue / totalContractValue;
  int get proposedLessons => lessons.where((l) => l.status == 'proposed').length;
  int get appliedLessons => lessons.where((l) => l.status == 'applied').length;
  int get approvedLessons => lessons.where((l) => l.status == 'approved').length;
  int get staleProjects => tracks.values.where((t) => t.stale).length;
  double? get avgField {
    final v = evaluations.map((e) => e.average).whereType<double>().toList();
    return v.isEmpty ? null : v.reduce((a, b) => a + b) / v.length;
  }

  ContractorKpi? get bestContractor {
    final r = contractors.where((k) => k.composite != null).toList();
    return r.isEmpty ? null : r.first;
  }

  ContractorKpi? get worstContractor {
    final r = contractors.where((k) => k.composite != null).toList();
    return r.length < 2 ? null : r.last;
  }

  List<PmAlert> get alerts {
    final t = tracks.values;
    return [
      PmAlert('critical', 'مشاريع بحالة «متأخر حرج»', t.where((x) => x.perf == 'critical').length,
          'خطة تعافٍ ملزمة واجتماع عاجل مع الشركة', PmTabs.projects),
      PmAlert('forecast', 'مشاريع بتأخير متوقع يتجاوز ${cfg.forecastDelayAlert} يوماً',
          t.where((x) => (x.forecastDelay ?? 0) > cfg.forecastDelayAlert).length, 'مراجعة البرنامج الزمني وموارد الشركة', PmTabs.projects),
      PmAlert('slow', 'مشاريع سرعتها الحالية أقل من السرعة المطلوبة', t.where((x) => x.tooSlow).length,
          'رفع وتيرة العمل أو إعادة جدولة الأعمال', PmTabs.projects),
      PmAlert('stale', 'مشاريع جارية دون تحديث للتقدم', staleProjects, 'إدخال القياس الأسبوعي في سجل التقدم', PmTabs.progress),
      PmAlert('high', 'مخاطر مرتفعة/مرتفعة جداً نشطة', highRisksNow, 'التصعيد وفق المسار المحدد في مصفوفة المخاطر', PmTabs.riskRegister),
      PmAlert('rising', 'مخاطر متصاعدة منذ آخر مراجعة', risingRisks, 'مراجعة فعالية الإجراء الوقائي وتعزيزه', PmTabs.riskRegister),
      PmAlert('reviews', 'مراجعات مخاطر متأخرة', overdueReviews, 'تنفيذ المراجعة وتسجيلها', PmTabs.riskRegister),
      PmAlert('checks', 'مخاطر بملاحظات في «تحقق البيانات»', riskChecks, 'استكمال البيانات أو تصحيح الإغلاق', PmTabs.riskRegister),
      PmAlert('issues', 'مشاكل متأخرة عن موعد الحل', overdueIssues, 'متابعة الجهة المسؤولة وتحديث الموعد', PmTabs.issues),
      PmAlert('ongoing', 'أحداث تأخير قائمة', ongoingDelays, 'تحديد إجراء المعالجة وتاريخ انتهاء الأثر', PmTabs.delays),
      PmAlert('eot', 'طلبات تمديد لم يُبت فيها', pendingEot, 'دراسة الطلب والبت فيه', PmTabs.delays),
      PmAlert('limit', 'مشاريع تجاوزت حد نسبة التغييرات (${(cfg.changeLimit * 100).toStringAsFixed(0)}%)',
          t.where((x) => x.overChangeLimit).length, 'مراجعة مبررات التغييرات واعتمادها من الجهة المختصة', PmTabs.changes),
      PmAlert('decide', 'طلبات تغيير تأخر البت فيها (أكثر من ${cfg.changeDecideDays} يوماً)', lateDecisions,
          'البت في الطلب أو تحديد موعد', PmTabs.changes),
      PmAlert('lessons', 'دروس مقترحة بانتظار الاعتماد', proposedLessons, 'عرضها للاعتماد وتحديد آلية التعميم', PmTabs.lessons),
      PmAlert('weak', 'شركات بتقدير «${cfg.grades.length > 1 ? cfg.grades[1].name : ''}» أو «${cfg.grades.first.name}»',
          contractors.where((k) => k.grade != null && cfg.isWeakGrade(k.grade!.name)).length, 'خطة تحسين قبل أي إسناد جديد',
          PmTabs.contractors),
    ];
  }

  /// التغييرات المعتمدة حسب السبب: (العدد، المعتمدة، القيمة، الأيام).
  Map<String, ({int count, int approved, double value, int days})> get changesByReason {
    final out = <String, ({int count, int approved, double value, int days})>{};
    for (final c in changes) {
      final k = c.reason.isEmpty ? 'غير محدد' : c.reason;
      final o = out[k] ?? (count: 0, approved: 0, value: 0.0, days: 0);
      out[k] = (
        count: o.count + 1,
        approved: o.approved + (c.isApproved ? 1 : 0),
        value: o.value + (c.isApproved ? (c.costApproved ?? 0) : 0),
        days: o.days + (c.isApproved ? (c.timeApproved ?? 0) : 0),
      );
    }
    return out;
  }

  // ---------------------------------------------------------------
  // التقرير الدوري
  // ---------------------------------------------------------------
  PeriodicReport report(bool monthly, DateTime date) => PeriodicReport(this, monthly, date);
}

class ReportRow {
  const ReportRow(this.track, this.planned, this.actualStart, this.actualEnd, this.obstacles);

  final ProjectTrack track;
  final double? planned;
  final double? actualStart;
  final double? actualEnd;
  final String obstacles;

  double? get gain => actualEnd == null ? null : actualEnd! - (actualStart ?? 0);
  double? get deviation => actualEnd == null || planned == null ? null : actualEnd! - planned!;
  double? get spi => actualEnd == null || planned == null || planned == 0 ? null : actualEnd! / planned!;

  String perf(PmConfig cfg) {
    final s = spi;
    if (s == null) return track.perf;
    if ((actualEnd ?? 0) >= 1) return 'done';
    if (s >= cfg.spiAhead) return 'ahead';
    if (s >= cfg.spiOk) return 'on_track';
    if (s >= cfg.spiWarn) return 'slight';
    return 'critical';
  }
}

class PeriodicReport {
  PeriodicReport(this.a, this.monthly, DateTime date) {
    final d = DateTime(date.year, date.month, date.day);
    if (monthly) {
      start = DateTime(d.year, d.month, 1);
      end = DateTime(d.year, d.month + 1, 0);
    } else {
      start = addDays(d, -(d.weekday % 7)); // الأسبوع من الأحد إلى السبت
      end = addDays(start, 6);
    }
    for (final t in a.tracks.values) {
      final atEnd = t.lastOnOrBefore(end);
      if (atEnd == null) continue;
      final atStart = t.lastOnOrBefore(addDays(start, -1));
      final inPeriod = !atEnd.measuredOn.isBefore(start);
      rows.add(ReportRow(t, atEnd.planned, atStart?.actual ?? 0, atEnd.actual, inPeriod ? atEnd.obstacles : ''));
    }
    rows.sort((x, y) => x.track.project.sortOrder.compareTo(y.track.project.sortOrder));
  }

  final PmAnalysis a;
  final bool monthly;
  late final DateTime start;
  late final DateTime end;
  final List<ReportRow> rows = [];

  bool inP(DateTime? d) => d != null && !d.isBefore(start) && !d.isAfter(end);

  String get title => monthly ? 'التقرير الشهري لمتابعة المشاريع' : 'التقرير الأسبوعي لمتابعة المشاريع';
  String get periodLabel {
    if (monthly) return 'شهر ${start.month} / ${start.year}';
    final firstDay = DateTime(start.year, 1, 1);
    final week = (daysBetween(start, addDays(firstDay, -(firstDay.weekday % 7))) ~/ 7) + 1;
    return 'أسبوع $week / ${start.year}';
  }

  List<ReportRow> get runningRows => rows.where((r) => r.track.isRunning).toList();
  int get runningProjects => a.running.length;
  int get lateAtEnd => runningRows.where((r) => ['slight', 'critical'].contains(r.perf(a.cfg))).length;

  double? _w(double? Function(ReportRow) f) {
    final l = runningRows.where((r) => f(r) != null).toList();
    if (l.isEmpty) return null;
    final anyValue = l.any((r) => (r.track.contractValue ?? 0) > 0);
    var s = 0.0, w = 0.0;
    for (final r in l) {
      final wt = anyValue ? (r.track.contractValue ?? 0) : 1.0;
      s += f(r)! * wt;
      w += wt;
    }
    return w == 0 ? null : s / w;
  }

  double? get plannedW => _w((r) => r.planned);
  double? get actualW => _w((r) => r.actualEnd);
  double? get gainW => _w((r) => r.gain);
  double? get spiW {
    final p = plannedW, x = actualW;
    return p == null || x == null || p == 0 ? null : x / p;
  }

  int get newRisks => a.riskList.where((r) => inP(r.risk.registeredOn)).length;
  int get closedRisks => a.riskList.where((r) => inP(r.risk.closedOn)).length;
  int get reviewsDone => a.riskList.fold<int>(0, (s, r) => s + r.reviews.where((v) => inP(v.reviewedOn)).length);
  int get highNow => a.highRisksNow;
  int get newIssues => a.issues.where((i) => inP(i.detectedOn)).length;
  int get closedIssues => a.issues.where((i) => inP(i.closedOn)).length;
  int get overdueIssues => a.overdueIssues;
  int get delaysStarted => a.delays.where((d) => inP(d.startDate)).length;
  int get ongoingDelays => a.ongoingDelays;
  int get changesSubmitted => a.changes.where((c) => inP(c.submittedOn)).length;
  int get changesApproved => a.changes.where((c) => c.isApproved && inP(c.decidedOn)).length;
  double get approvedValue => a.changes.where((c) => c.isApproved && inP(c.decidedOn)).fold<double>(0, (s, c) => s + (c.costApproved ?? 0));
  int get lessonsDocumented => a.lessons.where((l) => inP(l.documentedOn)).length;
  int get evaluationsDone => a.evaluations.where((e) => inP(e.evaluatedOn)).length;

  List<RiskState> get topRisks {
    final l = a.riskList.where((r) => r.isActive).toList()
      ..sort((x, y) => y.currentScore != x.currentScore ? y.currentScore.compareTo(x.currentScore) : y.initialScore.compareTo(x.initialScore));
    return l.take(5).toList();
  }

  List<PmIssue> get lateIssues {
    final l = a.issues.where((i) => i.followUp(a.ref, a.cfg.alertDays) == 'overdue').toList()
      ..sort((x, y) => y.overdueDays(a.ref).compareTo(x.overdueDays(a.ref)));
    return l.take(5).toList();
  }
}
