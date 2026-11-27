// نماذج القسمين الرئيسيين الجديدين: سجل المخاطر وتحليل SWOT، وحساباتهما (كما في ملفي Excel المعتمدين).

DateTime? _day(dynamic v) {
  if (v == null) return null;
  final d = DateTime.tryParse(v.toString());
  return d == null ? null : DateTime(d.year, d.month, d.day);
}

int? _int(dynamic v) => v is num ? v.toInt() : int.tryParse('${v ?? ''}');
double? _num(dynamic v) => v is num ? v.toDouble() : double.tryParse('${v ?? ''}');
String _str(dynamic v) => v == null ? '' : v.toString();
List<String> _codes(dynamic v) => v is List ? [for (final x in v) x.toString()] : const [];

String isoDay(DateTime? d) =>
    d == null ? '' : '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

DateTime get _today {
  final n = DateTime.now();
  return DateTime(n.year, n.month, n.day);
}

// =====================================================================
// سجل المخاطر
// =====================================================================

const List<String> riskStatuses = ['open', 'in_progress', 'on_hold', 'closed'];
const Map<String, String> riskStatusLabels = {
  'open': 'مفتوح',
  'in_progress': 'قيد المعالجة',
  'on_hold': 'معلق',
  'closed': 'مغلق',
};

const List<String> riskResponses = ['avoid', 'mitigate', 'transfer', 'accept'];
const Map<String, String> riskResponseLabels = {
  'avoid': 'تجنب',
  'mitigate': 'تخفيف',
  'transfer': 'نقل',
  'accept': 'قبول',
};

/// أسماء درجات الاحتمالية والتأثير (مصفوفة المخاطر).
const Map<int, String> probabilityLabels = {1: 'نادر', 2: 'غير مرجح', 3: 'ممكن', 4: 'مرجح', 5: 'شبه مؤكد'};
const Map<int, String> impactLabels = {1: 'ضئيل', 2: 'طفيف', 3: 'متوسط', 4: 'كبير', 5: 'جسيم'};

/// حالة متابعة مواعيد المراجعة والإجراءات.
const List<String> followUpKeys = ['overdue', 'soon', 'ontime', 'none', 'closed'];
const Map<String, String> followUpLabels = {
  'overdue': 'متأخرة',
  'soon': 'مستحقة قريباً',
  'ontime': 'ضمن الموعد',
  'none': 'بلا موعد',
  'closed': 'مغلق',
};
const Map<String, String> followUpActions = {
  'overdue': 'مراجعة فورية وتحديث الموعد والإجراء',
  'soon': 'التحضير للمراجعة خلال فترة التنبيه',
  'ontime': 'متابعة اعتيادية',
  'none': 'تحديد موعد المراجعة القادمة',
  'closed': '—',
};

class RiskLevel {
  const RiskLevel(this.name, this.min, this.action, [this.reviewDays]);

  final String name;
  final int min;
  final String action;

  /// دورية المراجعة بالأيام (الإصدار 2.0): تحدد موعد المراجعة القادمة لكل خطر حسب مستواه الحالي.
  final int? reviewDays;

  Map<String, dynamic> toJson() => {'name': name, 'min': min, 'action': action, if (reviewDays != null) 'review_days': reviewDays};
}

/// معايير التصنيف والقوائم المرجعية لسجل المخاطر (إعداد risk.config).
class RiskConfig {
  const RiskConfig({
    required this.levels,
    this.alertDays = 7,
    this.phases = const [],
    this.categories = const [],
    this.projects = const [],
    this.owners = const [],
    this.executors = const [],
  });

  final List<RiskLevel> levels;
  final int alertDays;
  final List<String> phases;
  final List<String> categories;
  final List<String> projects;
  final List<String> owners;

  /// منفذو الإجراءات (الإصدار 2.0).
  final List<String> executors;

  static const RiskConfig defaults = RiskConfig(
    levels: [
      RiskLevel('منخفض جداً', 1, 'مراقبة – رئيس القسم المختص', 90),
      RiskLevel('منخفض', 5, 'متابعة دورية – رئيس القسم المختص', 60),
      RiskLevel('متوسط', 9, 'خطة معالجة – رئيس القسم المختص', 30),
      RiskLevel('مرتفع', 13, 'تصعيد إلى مدير المكتب', 14),
      RiskLevel('مرتفع جداً', 20, 'تصعيد عاجل إلى مدير المكتب ورفعه للجنة', 7),
    ],
    phases: ['التخطيط', 'التصميم', 'التعاقد', 'التنفيذ', 'الاستلام', 'فترة الضمان', 'المتابعة'],
    categories: [
      'فني', 'تعاقدي', 'موقعي', 'مالي', 'سلامة', 'توريد', 'جودة', 'تنسيق', 'زمني', 'بيئي', 'قانوني', 'حوكمة', //
      'مخلفات الحرب والأمن', 'تراثي وترميم',
    ],
    owners: ['الإشراف والتنسيق', 'الشؤون الفنية', 'الترميم', 'المطابقة والاستلام', 'مكتب المدير'],
    executors: [
      'المقاول', 'الاستشاري', 'الإشراف والتنسيق', 'الشؤون الفنية', 'الترميم', 'المطابقة والاستلام', 'مكتب المدير', //
      'الشؤون المالية', 'العقود والمشتريات', 'الشؤون القانونية', 'السلامة المهنية', 'الجهات المختصة', 'اللجنة',
    ],
  );

  static RiskConfig fromJson(dynamic v) {
    if (v is! Map) return defaults;
    List<String> list(dynamic x) => x is List ? [for (final e in x) if (e.toString().trim().isNotEmpty) e.toString().trim()] : const [];
    final lv = <RiskLevel>[];
    final raw = v['levels'];
    if (raw is List) {
      for (final e in raw) {
        if (e is Map && e['name'] != null && _int(e['min']) != null) {
          lv.add(RiskLevel(e['name'].toString(), _int(e['min'])!, _str(e['action']), _int(e['review_days'])));
        }
      }
    }
    lv.sort((a, b) => a.min.compareTo(b.min));
    return RiskConfig(
      levels: lv.length >= 3 ? lv : defaults.levels,
      alertDays: _int(v['alert_days']) ?? 7,
      phases: v.containsKey('phases') ? list(v['phases']) : defaults.phases,
      categories: v.containsKey('categories') ? list(v['categories']) : defaults.categories,
      projects: list(v['projects']),
      owners: list(v['owners']),
      executors: v.containsKey('executors') ? list(v['executors']) : defaults.executors,
    );
  }

  Map<String, dynamic> toJson() => {
        'levels': [for (final l in levels) l.toJson()],
        'alert_days': alertDays,
        'phases': phases,
        'categories': categories,
        'projects': projects,
        'owners': owners,
        'executors': executors,
      };

  RiskConfig copyWith({
    List<RiskLevel>? levels,
    int? alertDays,
    List<String>? phases,
    List<String>? categories,
    List<String>? projects,
    List<String>? owners,
    List<String>? executors,
  }) =>
      RiskConfig(
        levels: levels ?? this.levels,
        alertDays: alertDays ?? this.alertDays,
        phases: phases ?? this.phases,
        categories: categories ?? this.categories,
        projects: projects ?? this.projects,
        owners: owners ?? this.owners,
        executors: executors ?? this.executors,
      );

  /// رقم المستوى (0 = الأدنى) لدرجة من 1 إلى 25.
  int levelIndex(int score) {
    var i = 0;
    for (var k = 0; k < levels.length; k++) {
      if (score >= levels[k].min) i = k;
    }
    return i;
  }

  RiskLevel? level(int? score) => score == null ? null : levels[levelIndex(score)];

  /// نهاية نطاق المستوى (بداية التالي − 1، أو 25 للأخير).
  int maxOf(int i) => i + 1 < levels.length ? levels[i + 1].min - 1 : 25;

  /// بداية «المرتفع»: المستويان الأعليان.
  int get highMin => levels[levels.length - 2].min;

  bool isHigh(int? score) => score != null && score >= highMin;

  /// دورية المراجعة لمستوى الدرجة (الافتراضي حسب موضع المستوى من الأعلى: 7، 14، 30، 60، 90 يوماً).
  int reviewDaysFor(int score) {
    final i = levelIndex(score);
    final d = levels[i].reviewDays;
    if (d != null && d > 0) return d;
    const ladder = [7, 14, 30, 60, 90, 120, 180];
    final fromTop = levels.length - 1 - i;
    return ladder[fromTop.clamp(0, ladder.length - 1)];
  }
}

class Risk {
  Risk({
    required this.id,
    required this.code,
    this.projectGroup = '',
    this.projectId,
    this.phase = '',
    this.category = '',
    required this.description,
    this.cause = '',
    this.effect = '',
    required this.probability,
    required this.impact,
    this.mitigation = '',
    this.response = '',
    this.owner = '',
    this.status = 'open',
    this.residualProbability,
    this.residualImpact,
    this.nextReview,
    this.registeredOn,
    this.targetDate,
    this.closedOn,
    this.earlyWarning = '',
    this.notes = '',
    this.updatedAt,
    this.department = '',
    this.timeImpactDays,
    this.costImpact,
    this.contingency = '',
    this.executor = '',
    this.autoKey,
    this.autoActive = false,
  });

  final String id;
  final String code;
  final String projectGroup;
  final String? projectId;
  final String phase;
  final String category;
  final String description;
  final String cause;
  final String effect;
  final int probability;
  final int impact;
  final String mitigation;
  final String response;
  final String owner;
  final String status;
  final int? residualProbability;
  final int? residualImpact;
  final DateTime? nextReview;
  final DateTime? registeredOn;
  final DateTime? targetDate;
  final DateTime? closedOn;
  final String earlyWarning;
  final String notes;
  final DateTime? updatedAt;

  // الإصدار 2.0
  final String department; // القسم المختص
  final int? timeImpactDays; // الأثر الزمني المقدر (يوم)
  final double? costImpact; // الأثر المالي المقدر
  final String contingency; // الإجراء الاحتياطي عند وقوع الخطر
  final String executor; // منفذ الإجراء

  /// خطر سجّلته متابعة البرنامج الزمني تلقائياً (الترحيل 31): pm_item:<البند> أو pm_plan:<العقد>، وهل سببه قائم.
  final String? autoKey;
  final bool autoActive;
  bool get isAuto => autoKey != null;

  /// القسم الذي ولّد الخطر آلياً (الترحيل 43): من بادئة المفتاح؛ وللبقية (برنامج زمني أو يدوي) لا قسم.
  String? get section => riskSectionOfKey(autoKey);

  /// خطر المكتب: غير مرتبط بمشروع (يدوي للمكتب أو مولَّد من قسم).
  bool get isOffice => projectId == null;

  factory Risk.fromMap(Map<String, dynamic> m) => Risk(
        id: m['id'].toString(),
        code: _str(m['code']),
        projectGroup: _str(m['project_group']),
        projectId: m['project_id']?.toString(),
        phase: _str(m['phase']),
        category: _str(m['category']),
        description: _str(m['description']),
        cause: _str(m['cause']),
        effect: _str(m['effect']),
        probability: _int(m['probability']) ?? 1,
        impact: _int(m['impact']) ?? 1,
        mitigation: _str(m['mitigation']),
        response: _str(m['response']),
        owner: _str(m['owner']),
        status: _str(m['status']).isEmpty ? 'open' : _str(m['status']),
        residualProbability: _int(m['residual_probability']),
        residualImpact: _int(m['residual_impact']),
        nextReview: _day(m['next_review']),
        registeredOn: _day(m['registered_on']),
        targetDate: _day(m['target_date']),
        closedOn: _day(m['closed_on']),
        earlyWarning: _str(m['early_warning']),
        notes: _str(m['notes']),
        updatedAt: DateTime.tryParse(_str(m['updated_at'])),
        department: _str(m['department']),
        timeImpactDays: _int(m['time_impact_days']),
        costImpact: _num(m['cost_impact']),
        contingency: _str(m['contingency']),
        executor: _str(m['executor']),
        autoKey: m['auto_key']?.toString(),
        autoActive: m['auto_active'] == true,
      );

  int get score => probability * impact;
  int? get residualScore => residualProbability == null || residualImpact == null ? null : residualProbability! * residualImpact!;
  bool get isClosed => status == 'closed';
  String get statusLabel => riskStatusLabels[status] ?? status;
  String get responseLabel => riskResponseLabels[response] ?? '';

  /// نسبة خفض الخطر من الدرجة الأولية إلى المتبقية.
  double? get reduction => residualScore == null || score == 0 ? null : 1 - residualScore! / score;

  /// حالة متابعة المواعيد كما في عمود «حالة المتابعة».
  String followUp(int alertDays, [DateTime? today]) {
    final t = today ?? _today;
    if (isClosed) return 'closed';
    if (nextReview == null) return 'none';
    if (nextReview!.isBefore(t) || (targetDate != null && targetDate!.isBefore(t))) return 'overdue';
    if (nextReview!.difference(t).inDays <= alertDays) return 'soon';
    return 'ontime';
  }

  /// الحقول المرسلة إلى save_risk.
  Map<String, dynamic> toJson() => {
        'code': code,
        'project_group': projectGroup,
        'project_id': projectId ?? '',
        'phase': phase,
        'category': category,
        'description': description,
        'cause': cause,
        'effect': effect,
        'probability': probability,
        'impact': impact,
        'mitigation': mitigation,
        'response': response,
        'owner': owner,
        'status': status,
        'residual_probability': residualProbability,
        'residual_impact': residualImpact,
        'next_review': isoDay(nextReview),
        'registered_on': isoDay(registeredOn),
        'target_date': isoDay(targetDate),
        'closed_on': isoDay(closedOn),
        'early_warning': earlyWarning,
        'notes': notes,
        'department': department,
        'time_impact_days': timeImpactDays,
        'cost_impact': costImpact,
        'contingency': contingency,
        'executor': executor,
      };
}

/// مؤشرات لوحة متابعة المخاطر.
class RiskStats {
  RiskStats(this.risks, this.cfg, [DateTime? today]) {
    final t = today ?? _today;
    for (final r in risks) {
      final li = cfg.levelIndex(r.score);
      byLevel[li] = (byLevel[li] ?? 0) + 1;
      if (cfg.isHigh(r.score)) highBefore++;
      final rs = r.residualScore;
      if (rs != null) {
        final ri = cfg.levelIndex(rs);
        byResidualLevel[ri] = (byResidualLevel[ri] ?? 0) + 1;
        residualCount++;
        if (cfg.isHigh(rs)) highAfter++;
        reductionSum += r.reduction ?? 0;
        residualSum += rs;
      }
      scoreSum += r.score;
      byStatus[r.status] = (byStatus[r.status] ?? 0) + 1;
      final f = r.followUp(cfg.alertDays, t);
      byFollowUp[f] = (byFollowUp[f] ?? 0) + 1;
      heat[r.probability - 1][r.impact - 1]++;
      if (r.residualProbability != null && r.residualImpact != null) {
        heatAfter[r.residualProbability! - 1][r.residualImpact! - 1]++;
      }
    }
  }

  final List<Risk> risks;
  final RiskConfig cfg;
  final Map<int, int> byLevel = {};
  final Map<int, int> byResidualLevel = {};
  final Map<String, int> byStatus = {};
  final Map<String, int> byFollowUp = {};

  /// heat[احتمالية-1][تأثير-1] = عدد المخاطر
  final List<List<int>> heat = List.generate(5, (_) => List.filled(5, 0));
  final List<List<int>> heatAfter = List.generate(5, (_) => List.filled(5, 0));
  int highBefore = 0, highAfter = 0, residualCount = 0, scoreSum = 0, residualSum = 0;
  double reductionSum = 0;

  int get total => risks.length;
  int get closed => byStatus['closed'] ?? 0;
  int get notClosed => total - closed;
  double? get closureRate => total == 0 ? null : closed / total;
  double? get avgReduction => residualCount == 0 ? null : reductionSum / residualCount;
  double? get avgScore => total == 0 ? null : scoreSum / total;
  double? get avgResidual => residualCount == 0 ? null : residualSum / residualCount;

  /// أعلى المخاطر النشطة حسب الدرجة، وعند التساوي الأعلى درجة متبقية.
  List<Risk> topActive([int n = 5]) {
    final list = risks.where((r) => !r.isClosed).toList()
      ..sort((a, b) {
        final c = b.score.compareTo(a.score);
        if (c != 0) return c;
        return (b.residualScore ?? 0).compareTo(a.residualScore ?? 0);
      });
    return list.take(n).toList();
  }

  /// التوزيع حسب التصنيف: (العدد، المرتفعة، متوسط الدرجة، متوسط المتبقية، غير المغلقة)
  Map<String, ({int count, int high, double avg, double? avgResidual, int open})> byCategory() {
    final out = <String, ({int count, int high, double avg, double? avgResidual, int open})>{};
    final groups = <String, List<Risk>>{};
    for (final r in risks) {
      (groups[r.category.isEmpty ? 'غير مصنف' : r.category] ??= []).add(r);
    }
    for (final e in groups.entries) {
      final l = e.value;
      final res = l.where((r) => r.residualScore != null).toList();
      out[e.key] = (
        count: l.length,
        high: l.where((r) => cfg.isHigh(r.score)).length,
        avg: l.fold<int>(0, (a, r) => a + r.score) / l.length,
        avgResidual: res.isEmpty ? null : res.fold<int>(0, (a, r) => a + r.residualScore!) / res.length,
        open: l.where((r) => !r.isClosed).length,
      );
    }
    return out;
  }
}

// =====================================================================
// تحليل SWOT
// =====================================================================

const List<String> swotKinds = ['S', 'W', 'O', 'T'];
const Map<String, String> swotKindLabels = {'S': 'قوة', 'W': 'ضعف', 'O': 'فرصة', 'T': 'تهديد'};
const Map<String, String> swotKindTitles = {'S': 'نقاط القوة', 'W': 'نقاط الضعف', 'O': 'الفرص', 'T': 'التهديدات'};
const Map<String, String> swotKindEnglish = {'S': 'Strengths', 'W': 'Weaknesses', 'O': 'Opportunities', 'T': 'Threats'};

const List<String> strategyKinds = ['SO', 'WO', 'ST', 'WT'];
const Map<String, String> strategyKindLabels = {
  'SO': 'توظيف نقاط القوة لاقتناص الفرص',
  'WO': 'معالجة نقاط الضعف بالاستفادة من الفرص',
  'ST': 'توظيف نقاط القوة لمواجهة التهديدات',
  'WT': 'تقليل نقاط الضعف وتجنب التهديدات',
};
const Map<String, String> strategyDirections = {
  'SO': 'نمو وتوسع',
  'WO': 'تطوير ومعالجة',
  'ST': 'حماية وتنويع',
  'WT': 'دفاع وتقليص مخاطر',
};

const List<String> swotPriorities = ['high', 'medium', 'low'];
const Map<String, String> swotPriorityLabels = {'high': 'عالية', 'medium': 'متوسطة', 'low': 'منخفضة'};

const List<String> actionStatuses = ['not_started', 'in_progress', 'completed', 'stalled', 'on_hold'];
const Map<String, String> actionStatusLabels = {
  'not_started': 'لم يبدأ',
  'in_progress': 'قيد التنفيذ',
  'completed': 'مكتمل',
  'stalled': 'متعثر',
  'on_hold': 'معلق',
};

/// مؤشر الالتزام بخطة التنفيذ.
const Map<String, String> commitmentLabels = {
  'completed': 'مكتمل',
  'stalled': 'متعثر',
  'on_hold': 'معلق',
  'not_due': 'لم يحن موعده',
  'late': 'متأخر',
  'awaiting': 'بانتظار التحديث',
  'behind': 'متأخر عن الخطة',
  'on_track': 'ضمن الخطة',
};

const List<String> swotDepartments = [
  'إدارة المكتب',
  'قسم الإشراف والتنسيق',
  'قسم الشؤون الفنية',
  'قسم الترميم',
  'قسم المطابقة والاستلام',
  'جميع الأقسام',
];
const List<String> swotReviewCycles = ['أسبوعيًا', 'شهريًا', 'ربع سنوي', 'كل 6 أشهر', 'سنويًا', 'مع كل مرحلة استلام', 'مع كل تسليم موقع'];
const List<String> swotSources = [
  'الملف الأصلي',
  'الملف الأصلي (خطة التنفيذ)',
  'الملف الأصلي (مصفوفة TOWS)',
  'مقترح – للتحقق في ورشة العمل',
  'الملف الأصلي (أُعيدت صياغته كاستراتيجية)',
  'مضاف',
  'مضاف (مبادرة قائمة)',
  'مضاف (من عناصر الحوكمة الأصلية)',
  'إفادة إدارة المكتب',
];

/// مستوى الأولوية من درجة (الأهمية × الاستعجال).
String priorityLevel(int score) => score >= 16 ? 'high' : (score >= 9 ? 'medium' : 'low');

class SwotFactor {
  SwotFactor({
    required this.id,
    required this.code,
    required this.kind,
    required this.factor,
    this.impact = '',
    this.department = '',
    required this.importance,
    required this.urgency,
    this.evidence = '',
    this.source = '',
    this.rating,
    this.sort = 0,
    this.autoKey,
    this.projectId,
  });

  final String id;
  final String code;
  final String kind;
  final String factor;
  final String impact;
  final String department;
  final int importance;
  final int urgency;
  final String evidence;
  final String source;
  final int? rating;
  final int sort;

  /// عامل ترجمته متابعة البرنامج الزمني لعقد (الترحيل 31).
  final String? autoKey;
  final String? projectId;
  bool get isAuto => autoKey != null;

  factory SwotFactor.fromMap(Map<String, dynamic> m) => SwotFactor(
        id: m['id'].toString(),
        code: _str(m['code']),
        kind: _str(m['kind']),
        factor: _str(m['factor']),
        impact: _str(m['impact']),
        department: _str(m['department']),
        importance: _int(m['importance']) ?? 1,
        urgency: _int(m['urgency']) ?? 1,
        evidence: _str(m['evidence']),
        source: _str(m['source']),
        rating: _int(m['rating']),
        sort: _int(m['sort']) ?? 0,
        autoKey: m['auto_key']?.toString(),
        projectId: m['project_id']?.toString(),
      );

  int get priority => importance * urgency;
  String get level => priorityLevel(priority);
  bool get internal => kind == 'S' || kind == 'W';
  bool get proposed => source.startsWith('مقترح');

  Map<String, dynamic> toJson() => {
        'code': code,
        'kind': kind,
        'factor': factor,
        'impact': impact,
        'department': department,
        'importance': importance,
        'urgency': urgency,
        'evidence': evidence,
        'source': source,
        'rating': rating,
      };
}

class SwotStrategy {
  SwotStrategy({
    required this.id,
    required this.code,
    required this.kind,
    required this.strategy,
    this.internal = const [],
    this.external = const [],
    this.priority = 'medium',
    this.leadDepartment = '',
    this.source = '',
    this.sort = 0,
  });

  final String id;
  final String code;
  final String kind;
  final String strategy;
  final List<String> internal;
  final List<String> external;
  final String priority;
  final String leadDepartment;
  final String source;
  final int sort;

  factory SwotStrategy.fromMap(Map<String, dynamic> m) => SwotStrategy(
        id: m['id'].toString(),
        code: _str(m['code']),
        kind: _str(m['kind']),
        strategy: _str(m['strategy']),
        internal: _codes(m['internal_factors']),
        external: _codes(m['external_factors']),
        priority: _str(m['priority']).isEmpty ? 'medium' : _str(m['priority']),
        leadDepartment: _str(m['lead_department']),
        source: _str(m['source']),
        sort: _int(m['sort']) ?? 0,
      );

  List<String> get factors => [...internal, ...external];
  bool get proposed => source.startsWith('مقترح');

  Map<String, dynamic> toJson() => {
        'code': code,
        'kind': kind,
        'strategy': strategy,
        'internal_factors': internal,
        'external_factors': external,
        'priority': priority,
        'lead_department': leadDepartment,
        'source': source,
      };
}

class SwotAction {
  SwotAction({
    required this.id,
    required this.code,
    this.strategyCode,
    this.factors = const [],
    required this.action,
    this.output = '',
    this.department = '',
    this.owner = '',
    this.kpi = '',
    this.priority = 'medium',
    this.startDate,
    this.durationMonths,
    this.verification = '',
    this.reviewCycle = '',
    this.status = 'not_started',
    this.progress,
    this.notes = '',
    this.source = '',
    this.sort = 0,
    this.updatedAt,
  });

  final String id;
  final String code;
  final String? strategyCode;
  final List<String> factors;
  final String action;
  final String output;
  final String department;
  final String owner;
  final String kpi;
  final String priority;
  final DateTime? startDate;
  final int? durationMonths;
  final String verification;
  final String reviewCycle;
  final String status;
  final double? progress;
  final String notes;
  final String source;
  final int sort;
  final DateTime? updatedAt;

  factory SwotAction.fromMap(Map<String, dynamic> m) => SwotAction(
        id: m['id'].toString(),
        code: _str(m['code']),
        strategyCode: m['strategy_code']?.toString(),
        factors: _codes(m['factors']),
        action: _str(m['action']),
        output: _str(m['output']),
        department: _str(m['department']),
        owner: _str(m['owner']),
        kpi: _str(m['kpi']),
        priority: _str(m['priority']).isEmpty ? 'medium' : _str(m['priority']),
        startDate: _day(m['start_date']),
        durationMonths: _int(m['duration_months']),
        verification: _str(m['verification']),
        reviewCycle: _str(m['review_cycle']),
        status: _str(m['status']).isEmpty ? 'not_started' : _str(m['status']),
        progress: _num(m['progress']),
        notes: _str(m['notes']),
        source: _str(m['source']),
        sort: _int(m['sort']) ?? 0,
        updatedAt: DateTime.tryParse(_str(m['updated_at'])),
      );

  String get statusLabel => actionStatusLabels[status] ?? status;

  /// نوع الاستراتيجية من رمزها (SO / WO / ST / WT).
  String? get strategyKind => strategyCode != null && strategyCode!.length >= 2 ? strategyCode!.substring(0, 2) : null;

  /// تاريخ الانتهاء المخطط = البدء + المدة بالأشهر (مثل EDATE).
  DateTime? get endDate {
    if (startDate == null || durationMonths == null) return null;
    final s = startDate!;
    final m = s.month - 1 + durationMonths!;
    final y = s.year + m ~/ 12;
    final mo = m % 12 + 1;
    final last = DateTime(y, mo + 1, 0).day;
    return DateTime(y, mo, s.day > last ? last : s.day);
  }

  /// الإنجاز المخطط حتى اليوم (خطي بين البدء والانتهاء).
  double? planned([DateTime? today]) {
    final s = startDate, e = endDate;
    if (s == null || e == null) return null;
    final t = today ?? _today;
    final span = e.difference(s).inDays;
    if (span <= 0) return t.isBefore(s) ? 0 : 1;
    return (t.difference(s).inDays / span).clamp(0, 1).toDouble();
  }

  double? deviation([DateTime? today]) {
    final p = planned(today);
    return progress == null || p == null ? null : progress! - p;
  }

  int? daysRemaining([DateTime? today]) {
    final e = endDate;
    if (e == null || status == 'completed') return null;
    return e.difference(today ?? _today).inDays;
  }

  /// مؤشر الالتزام كما في الملف.
  String commitment([DateTime? today]) {
    final t = today ?? _today;
    if (status == 'completed') return 'completed';
    if (status == 'stalled') return 'stalled';
    if (status == 'on_hold') return 'on_hold';
    if (startDate != null && t.isBefore(startDate!)) return 'not_due';
    final e = endDate;
    if (e != null && t.isAfter(e)) return 'late';
    if (progress == null) return 'awaiting';
    final d = deviation(t);
    if (d != null && d < -0.1) return 'behind';
    return 'on_track';
  }

  /// يحتاج متابعة (تنبيه): متأخر، متأخر عن الخطة، متعثر، بانتظار التحديث.
  bool needsAttention([DateTime? today]) => const {'late', 'behind', 'stalled', 'awaiting'}.contains(commitment(today));

  Map<String, dynamic> toJson() => {
        'code': code,
        'strategy_code': strategyCode ?? '',
        'factors': factors,
        'action': action,
        'output': output,
        'department': department,
        'owner': owner,
        'kpi': kpi,
        'priority': priority,
        'start_date': isoDay(startDate),
        'duration_months': durationMonths,
        'verification': verification,
        'review_cycle': reviewCycle,
        'status': status,
        'progress': progress,
        'notes': notes,
        'source': source,
      };
}

/// بيانات وثيقة التحليل (إعداد swot.meta).
class SwotMeta {
  const SwotMeta(this.raw);

  final Map<String, dynamic> raw;

  String _s(String k, String f) {
    final v = raw[k];
    return v == null || v.toString().trim().isEmpty ? f : v.toString();
  }

  String get title => _s('title', 'تحليل SWOT الاستراتيجي وخطة التنفيذ والمتابعة');
  String get subtitle => _s('subtitle', '');
  String get version => _s('version', '1.0');
  DateTime? get issueDate => _day(raw['issue_date']);
  String get status => _s('status', 'مسودة');
  int get reviewCycleMonths => _int(raw['review_cycle_months']) ?? 6;
  String get preparedBy => _s('prepared_by', '');
  String get reviewedBy => _s('reviewed_by', '');
  String get approvedBy => _s('approved_by', '');

  DateTime? get nextReview {
    final d = issueDate;
    if (d == null) return null;
    final m = d.month - 1 + reviewCycleMonths;
    return DateTime(d.year + m ~/ 12, m % 12 + 1, d.day);
  }
}

/// الأوزان والتقييم المرجح لعامل في IFE أو EFE.
class WeightedRow {
  const WeightedRow(this.factor, this.weight, this.score);

  final SwotFactor factor;
  final double weight;
  final double? score;
}

/// حسابات تحليل SWOT كاملة (الربط والتغطية والتقييم المرجح والمؤشرات).
class SwotAnalysis {
  SwotAnalysis(List<SwotFactor> factors, List<SwotStrategy> strategies, List<SwotAction> actions, [DateTime? today])
      : factors = [...factors]..sort((a, b) => a.sort != b.sort ? a.sort.compareTo(b.sort) : a.code.compareTo(b.code)),
        strategies = [...strategies]..sort((a, b) => a.sort != b.sort ? a.sort.compareTo(b.sort) : a.code.compareTo(b.code)),
        actions = [...actions]..sort((a, b) => a.sort != b.sort ? a.sort.compareTo(b.sort) : a.code.compareTo(b.code)),
        today = today ?? _today {
    for (final f in this.factors) {
      byCode[f.code] = f;
    }
    for (final s in this.strategies) {
      strategyByCode[s.code] = s;
      for (final c in s.factors) {
        stratCount[c] = (stratCount[c] ?? 0) + 1;
      }
    }
    for (final a in this.actions) {
      for (final c in a.factors) {
        actionCount[c] = (actionCount[c] ?? 0) + 1;
      }
      if (a.strategyCode != null) (actionsOf[a.strategyCode!] ??= []).add(a);
    }
    ife = _weighted(['S', 'W']);
    efe = _weighted(['O', 'T']);
  }

  final List<SwotFactor> factors;
  final List<SwotStrategy> strategies;
  final List<SwotAction> actions;
  final DateTime today;
  final Map<String, SwotFactor> byCode = {};
  final Map<String, SwotStrategy> strategyByCode = {};
  final Map<String, int> stratCount = {};
  final Map<String, int> actionCount = {};
  final Map<String, List<SwotAction>> actionsOf = {};
  late final List<WeightedRow> ife;
  late final List<WeightedRow> efe;

  List<SwotFactor> ofKind(String k) => factors.where((f) => f.kind == k).toList();

  List<WeightedRow> _weighted(List<String> kinds) {
    final list = factors.where((f) => kinds.contains(f.kind)).toList();
    final total = list.fold<int>(0, (a, f) => a + f.importance);
    return [
      for (final f in list)
        WeightedRow(f, total == 0 ? 0 : f.importance / total, f.rating == null || total == 0 ? null : f.importance / total * f.rating!),
    ];
  }

  double _sum(List<WeightedRow> rows, String kind) =>
      rows.where((r) => r.factor.kind == kind).fold<double>(0, (a, r) => a + (r.score ?? 0));

  double get strengthsScore => _sum(ife, 'S');
  double get weaknessesScore => _sum(ife, 'W');
  double get ifeTotal => strengthsScore + weaknessesScore;
  double get opportunitiesScore => _sum(efe, 'O');
  double get threatsScore => _sum(efe, 'T');
  double get efeTotal => opportunitiesScore + threatsScore;
  int get unrated => factors.where((f) => f.rating == null).length;

  /// خلية مصفوفة IE (1–9): الصف من EFE والعمود من IFE.
  int get ieCell {
    final row = efeTotal >= 3 ? 0 : (efeTotal >= 2 ? 1 : 2);
    final col = ifeTotal >= 3 ? 1 : (ifeTotal >= 2 ? 2 : 3);
    return row * 3 + col;
  }

  static const List<String> roman = ['I', 'II', 'III', 'IV', 'V', 'VI', 'VII', 'VIII', 'IX'];

  static String directionOf(int cell) => switch (cell) {
        1 || 2 || 4 => 'النمو والبناء',
        3 || 5 || 7 => 'الحفاظ والاستقرار',
        _ => 'المعالجة وإعادة الهيكلة',
      };

  String get direction => directionOf(ieCell);

  int strategiesFor(String code) => stratCount[code] ?? 0;
  int actionsFor(String code) => actionCount[code] ?? 0;

  /// حالة التغطية: الضعف والتهديد «مُعالَج» بإجراء، والقوة والفرصة «مُستثمَر» باستراتيجية.
  bool covered(SwotFactor f) => f.kind == 'W' || f.kind == 'T' ? actionsFor(f.code) > 0 : strategiesFor(f.code) > 0;

  String coverageLabel(SwotFactor f) =>
      f.kind == 'W' || f.kind == 'T' ? (covered(f) ? 'مُعالَج' : 'غير مُعالَج') : (covered(f) ? 'مُستثمَر' : 'غير مُستثمَر');

  /// متوسط إنجاز إجراءات استراتيجية (بلا قيمة إن لم يُحدَّث أي منها).
  double? strategyProgress(String code) {
    final l = (actionsOf[code] ?? const <SwotAction>[]).where((a) => a.progress != null).toList();
    if (l.isEmpty) return null;
    return l.fold<double>(0, (a, x) => a + x.progress!) / l.length;
  }

  // مؤشرات خطة التنفيذ
  int get actionsTotal => actions.length;
  double? get avgProgress {
    final l = actions.where((a) => a.progress != null).toList();
    return l.isEmpty ? null : l.fold<double>(0, (a, x) => a + x.progress!) / l.length;
  }

  double? get avgPlanned {
    final l = [for (final a in actions) a.planned(today)].whereType<double>().toList();
    return l.isEmpty ? null : l.fold<double>(0, (a, x) => a + x) / l.length;
  }

  int get completed => actions.where((a) => a.status == 'completed').length;
  int get lateOrStalled => actions.where((a) => const {'late', 'behind', 'stalled'}.contains(a.commitment(today))).length;
  int get awaiting => actions.where((a) => a.commitment(today) == 'awaiting').length;
  List<SwotAction> get alerts => actions.where((a) => a.needsAttention(today)).toList();

  int get highFactors => factors.where((f) => f.level == 'high').length;

  List<SwotFactor> topFactors([int n = 10]) {
    final l = [...factors]..sort((a, b) {
        final c = b.priority.compareTo(a.priority);
        return c != 0 ? c : a.code.compareTo(b.code);
      });
    return l.take(n).toList();
  }

  /// خريطة الأولويات: grid[أهمية-1][استعجال-1] = عدد العوامل
  List<List<int>> get priorityGrid {
    final g = List.generate(5, (_) => List.filled(5, 0));
    for (final f in factors) {
      g[f.importance - 1][f.urgency - 1]++;
    }
    return g;
  }

  /// الأداء حسب القسم المسؤول: (العدد، المتأخرة/المتعثرة، الإنجاز الفعلي، المخطط)
  Map<String, ({int count, int late, double? actual, double? planned})> byDepartment() {
    final groups = <String, List<SwotAction>>{};
    for (final a in actions) {
      (groups[a.department.isEmpty ? 'غير محدد' : a.department] ??= []).add(a);
    }
    final out = <String, ({int count, int late, double? actual, double? planned})>{};
    for (final e in groups.entries) {
      final l = e.value;
      final act = l.where((a) => a.progress != null).toList();
      final pl = [for (final a in l) a.planned(today)].whereType<double>().toList();
      out[e.key] = (
        count: l.length,
        late: l.where((a) => const {'late', 'behind', 'stalled'}.contains(a.commitment(today))).length,
        actual: act.isEmpty ? null : act.fold<double>(0, (s, a) => s + a.progress!) / act.length,
        planned: pl.isEmpty ? null : pl.fold<double>(0, (s, x) => s + x) / pl.length,
      );
    }
    return out;
  }
}


/// قسم الخطر المولَّد آلياً من بادئة مفتاحه: st_item ← المخازن، pr_order ← المشتريات، mt_req ← الصيانة.
String? riskSectionOfKey(String? key) {
  if (key == null) return null;
  return switch (key.split(':').first) {
    'st_item' => 'stores',
    'pr_order' => 'procurement',
    'mt_req' => 'maintenance',
    _ => null,
  };
}

const riskSectionLabels = {'stores': 'المخازن', 'procurement': 'المشتريات', 'maintenance': 'الصيانة'};

const riskActionStatusLabels = {'open': 'مفتوح', 'done': 'منجَز', 'cancelled': 'ملغى'};

/// إجراء استجابة لخطر (الترحيل 43): عنوان ومسؤول وموعد وحالة.
class RiskAction {
  const RiskAction({
    required this.id,
    required this.riskId,
    required this.title,
    this.owner = '',
    this.dueDate,
    this.status = 'open',
    this.doneOn,
    this.note = '',
    this.createdAt,
  });

  final String id;
  final String riskId;
  final String title;
  final String owner;
  final DateTime? dueDate;
  final String status;
  final DateTime? doneOn;
  final String note;
  final DateTime? createdAt;

  bool get isOpen => status == 'open';

  /// متأخر: مفتوح وفات موعده قبل اليوم المعطى.
  bool isLate(DateTime today) {
    final d = dueDate;
    return isOpen && d != null && d.isBefore(DateTime(today.year, today.month, today.day));
  }

  factory RiskAction.fromMap(Map<String, dynamic> m) => RiskAction(
        id: _str(m['id']),
        riskId: _str(m['risk_id']),
        title: _str(m['title']),
        owner: _str(m['owner']),
        dueDate: _day(m['due_date']),
        status: _str(m['status']).isEmpty ? 'open' : _str(m['status']),
        doneOn: _day(m['done_on']),
        note: _str(m['note']),
        createdAt: DateTime.tryParse(_str(m['created_at'])),
      );
}
