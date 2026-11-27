// نماذج البيانات ومنطق حساب الإنجاز. يطابق منطق ملف Excel الأصلي وعرض v_project_progress.

enum FormStatus { done, wip, todo, na }

/// مسميات الحالات (قابلة للتعديل من الإعدادات الحية). الافتراضية من الترحيل 30: تم، قيد التنفيذ، لم يتم، لا ينطبق.
final Map<String, String> statusLabels = {'done': 'تم', 'wip': 'قيد التنفيذ', 'todo': 'لم يتم', 'na': 'لا ينطبق'};

extension FormStatusX on FormStatus {
  String get label => statusLabels[name] ?? switch (this) {
        FormStatus.done => 'تم',
        FormStatus.wip => 'قيد التنفيذ',
        FormStatus.todo => 'لم يتم',
        FormStatus.na => 'لا ينطبق',
      };

  String get db => name;
}

FormStatus parseStatus(Object? v) => switch (v) {
      'done' => FormStatus.done,
      'wip' => FormStatus.wip,
      'na' => FormStatus.na,
      _ => FormStatus.todo,
    };

enum AppRole { director, officeStaff, deptHead, contracts, planningQa, securityAuditor, employee }

extension AppRoleX on AppRole {
  String get db => switch (this) {
        AppRole.director => 'director',
        AppRole.officeStaff => 'office_staff',
        AppRole.deptHead => 'dept_head',
        AppRole.contracts => 'contracts',
        AppRole.planningQa => 'planning_qa',
        AppRole.securityAuditor => 'security_auditor',
        AppRole.employee => 'employee',
      };

  String get label => switch (this) {
        AppRole.director => 'مدير المكتب',
        AppRole.officeStaff => 'موظف مكتب المدير',
        AppRole.deptHead => 'رئيس قسم',
        AppRole.contracts => 'مكتب العقود والتوريدات والمستخلصات',
        AppRole.planningQa => 'مكتب التخطيط والتقييم وضمان الجودة',
        AppRole.securityAuditor => 'CISO',
        AppRole.employee => 'موظف (خدمة ذاتية)',
      };

  /// وصف مختصر لما يستطيعه كل دور (يظهر عند اختيار الدور).
  String get summary => switch (this) {
        AppRole.director => 'كل الصلاحيات',
        AppRole.officeStaff => 'يضيف المشاريع ويعدّلها ويحدّث النماذج كلها، والحساسة بطلب اعتماد',
        AppRole.deptHead => 'يحدّث نماذج اختصاص قسمه فقط',
        AppRole.contracts => 'يحدّث نماذج التعاقد والمستخلصات وإقفال العقد والبيانات المالية',
        AppRole.planningQa => 'يطّلع على المؤشرات ويصدّر التقارير ويسجّل ملاحظات الجودة',
        AppRole.securityAuditor =>
          'مسؤول الأمن السيبراني: قسم الأمن السيبراني كاملاً واطلاع على كل الأقسام، وإجراءات الحماية (إنهاء الجلسات، '
              'والقفل، وحظر الأجهزة، وتعليق الصلاحيات الدقيقة، وقفل المحادثات، والتجميد الطارئ)، دون كتابة في بيانات العمل. '
              'التحقق بخطوتين إلزامي له.',
        AppRole.employee =>
          'موظف في المقر دون عمل في المنظومة: يرى في قسم المخازن ما صُرف له ويؤكد استلامه، ولا يرى أي قسم آخر. '
              'يُربط حسابه بسجله في سجل الموظفين.',
      };
}

AppRole? parseRole(Object? v) => switch (v) {
      'director' => AppRole.director,
      'office_staff' => AppRole.officeStaff,
      'dept_head' => AppRole.deptHead,
      'contracts' => AppRole.contracts,
      'planning_qa' => AppRole.planningQa,
      'security_auditor' => AppRole.securityAuditor,
      'employee' => AppRole.employee,
      _ => null,
    };

/// الجهات التي يمكن إسناد نموذج إليها (غير المدير الذي يملك كل النماذج).
const Map<String, String> responsibleLabels = {
  'office_staff': 'موظفو مكتب المدير',
  'head:supervising': 'رئيس القسم المشرف',
  'head:technical': 'رئيس قسم الشؤون الفنية',
  'head:acceptance': 'رئيس قسم المطابقة والاستلام',
  'contracts': 'مكتب العقود والمستخلصات',
  'planning_qa': 'مكتب التخطيط وضمان الجودة',
};

/// أسماء المراحل بالترتيب (تُحمَّل من جدول المراحل، وهذه قيمها الافتراضية).
List<String> stageNames = [
  'التعاقد والإعداد الفني',
  'أمر العمل وتسليم الموقع',
  'التنفيذ والمستخلصات الجارية',
  'الاستلام الابتدائي والمستخلص الختامي',
  'الاستلام النهائي وإقفال العقد',
];
const String stageDoneName = 'اكتملت الدورة';

String stageName(int i) => i >= 0 && i < stageNames.length ? stageNames[i] : stageDoneName;

DateTime? _date(Object? v) => v == null ? null : DateTime.tryParse(v.toString());
String _str(Object? v) => v == null ? '' : v.toString();
double? _money(Object? v) => v == null ? null : (v is num ? v.toDouble() : double.tryParse(v.toString()));

// ---------------------------------------------------------------------
// البيانات المالية للعقد (بالدينار الليبي)
// ---------------------------------------------------------------------

/// نموذج «أمر بالتعاقد»: من يختص به يحدّث البيانات المالية للعقد.
const String contractFormKey = 'f01';

/// النسبتان الافتراضيتان للضمانين في العقود الجديدة (من الإعدادات الحية). لكل عقد نسبتاه الثابتتان منذ الترحيل 37،
/// ويُحسب المبلغان في قاعدة البيانات من قيمة الأعمال المنفذة.
double guaranteeInitialRate = 0.02;
double guaranteeFinalRate = 0.05;

/// رمز العملة المعروض (من الإعدادات الحية).
String currencyLabel = 'د.ل';

double roundMoney(double v) => (v * 1000).roundToDouble() / 1000;

/// يقرأ مبلغاً كتبه المستخدم: يقبل الأرقام العربية والفواصل، والفراغ يعني «غير مُدخل».
/// يُرجع ok=false إذا لم يكن مبلغاً صحيحاً غير سالب.
({bool ok, double? value}) parseMoney(String input) {
  final buf = StringBuffer();
  for (final r in input.trim().runes) {
    if (r >= 0x0660 && r <= 0x0669) {
      buf.writeCharCode(0x30 + r - 0x0660); // ٠-٩
    } else if (r >= 0x06F0 && r <= 0x06F9) {
      buf.writeCharCode(0x30 + r - 0x06F0); // ۰-۹
    } else if (r == 0x066B) {
      buf.write('.'); // الفاصلة العشرية العربية
    } else if (r == 0x066C || r == 0x2C || r == 0x20 || r == 0xA0) {
      continue; // فواصل الآلاف والمسافات
    } else {
      buf.writeCharCode(r);
    }
  }
  final s = buf.toString();
  if (s.isEmpty) return (ok: true, value: null);
  if (!RegExp(r'^\d+(\.\d+)?$').hasMatch(s)) return (ok: false, value: null);
  final v = double.tryParse(s);
  if (v == null || v >= 1e13) return (ok: false, value: null);
  return (ok: true, value: roundMoney(v));
}

/// مبلغ مقروء بفواصل الآلاف، وحتى ثلاث خانات عشرية عند الحاجة.
String fmtMoney(double? v) {
  if (v == null) return '—';
  final parts = v.abs().toStringAsFixed(3).split('.');
  final whole = parts[0];
  final frac = parts[1].replaceFirst(RegExp(r'0+$'), '');
  final buf = StringBuffer(v < 0 ? '-' : '');
  for (var i = 0; i < whole.length; i++) {
    if (i > 0 && (whole.length - i) % 3 == 0) buf.write(',');
    buf.write(whole[i]);
  }
  if (frac.isNotEmpty) buf.write('.$frac');
  return buf.toString();
}

/// المبلغ كما يُعرض داخل حقل الإدخال (بلا فواصل آلاف).
String moneyInput(double? v) => v == null ? '' : fmtMoney(v).replaceAll(',', '');

class Department {
  const Department({required this.key, required this.name, required this.canSupervise, required this.sort});

  final String key;
  final String name;
  final bool canSupervise;
  final int sort;

  factory Department.fromMap(Map<String, dynamic> m) => Department(
        key: _str(m['key']),
        name: _str(m['name']),
        canSupervise: m['can_supervise'] == true,
        sort: (m['sort'] as num?)?.toInt() ?? 0,
      );
}

class FormDef {
  const FormDef({
    required this.key,
    required this.name,
    required this.stage,
    required this.sort,
    required this.sensitive,
    required this.responsible,
    this.engineerField,
    this.active = true,
  });

  final String key;
  final String name;
  final int stage;
  final int sort;
  final bool sensitive;
  final List<String> responsible;
  final String? engineerField;
  final bool active;

  factory FormDef.fromMap(Map<String, dynamic> m) => FormDef(
        key: _str(m['key']),
        name: _str(m['name']),
        stage: (m['stage'] as num?)?.toInt() ?? 0,
        sort: (m['sort'] as num?)?.toInt() ?? 0,
        sensitive: m['sensitive'] == true,
        responsible: (m['responsible'] as List?)?.map((e) => e.toString()).toList() ?? const [],
        engineerField: m['engineer_field'] as String?,
        active: m['active'] != false,
      );
}

/// اسم حقل المهندس المرتبط بنموذج التكليف.
String engineerFieldLabel(String field) => switch (field) {
      'eng_sup' => 'المهندسون المشرفون',
      'eng_qty' => 'مهندسو الحصر',
      'eng_fol' => 'مهندسو المتابعة',
      'eng_saf' => 'مهندسو السلامة',
      _ => field,
    };

/// أنواع المهندسين في العقد بالترتيب: مشرف، حصر، متابعة، سلامة.
const List<String> engineerKinds = ['sup', 'qty', 'fol', 'saf'];

/// اسم نوع المهندس (مفرد).
String engineerKindLabel(String kind) => switch (kind) {
      'sup' => 'المهندس المشرف',
      'qty' => 'مهندس الحصر',
      'fol' => 'مهندس المتابعة',
      'saf' => 'مهندس السلامة',
      _ => kind,
    };

/// اسم نوع المهندس (جمع) كما يظهر عنواناً لقائمته.
String engineerKindPlural(String kind) => engineerFieldLabel('eng_$kind');

class Profile {
  const Profile({
    required this.id,
    required this.fullName,
    required this.email,
    required this.role,
    required this.department,
    required this.active,
    this.createdAt,
    this.lockedUntil,
    this.lockReason = '',
    this.unit,
    this.unitHead = false,
  });

  final String id;
  final String fullName;
  final String email;
  final AppRole? role;
  final String? department;
  final bool active;
  final DateTime? createdAt;
  final DateTime? lockedUntil; // قفل الدخول المؤقت (أو الدائم حتى يُفك)
  final String lockReason;

  /// الوحدة المُسنَدة (الترحيل 21): مثل safety أو quality_control، وهل هو رئيسها.
  final String? unit;
  final bool unitHead;

  bool get locked => lockedUntil != null && lockedUntil!.isAfter(DateTime.now());

  String get displayName => fullName.trim().isNotEmpty ? fullName.trim() : (email.isNotEmpty ? email : 'مستخدم');
  bool get isDirector => active && role == AppRole.director;
  bool get isAuditor => active && role == AppRole.securityAuditor;

  factory Profile.fromMap(Map<String, dynamic> m) => Profile(
        id: _str(m['id']),
        fullName: _str(m['full_name']),
        email: _str(m['email']),
        role: parseRole(m['role']),
        department: m['department'] as String?,
        active: m['active'] == true,
        createdAt: _date(m['created_at']),
        lockedUntil: m['locked_until'] == 'infinity' ? DateTime(9999) : _date(m['locked_until']),
        lockReason: _str(m['lock_reason']),
        unit: (m['unit'] as String?)?.isEmpty ?? true ? null : m['unit'] as String,
        unitHead: m['unit_head'] == true,
      );

  /// نسخة بوحدة أخرى (تُدمج بها بيانات الوحدات بعد تحميلها).
  Profile withUnit(String? u, bool head) => Profile(
        id: id,
        fullName: fullName,
        email: email,
        role: role,
        department: department,
        active: active,
        createdAt: createdAt,
        lockedUntil: lockedUntil,
        lockReason: lockReason,
        unit: u,
        unitHead: u != null && head,
      );
}

class Project {
  const Project({
    required this.id,
    required this.assignNo,
    required this.code,
    required this.name,
    required this.owner,
    required this.company,
    required this.department,
    required this.notes,
    required this.engineers,
    required this.sortOrder,
    this.contractNo = '',
    this.contractValue,
    this.executedValue,
    this.paymentFirst,
    this.paymentSecond,
    this.paymentFinal,
    this.deductions,
    this.guaranteeInitial,
    this.guaranteeFinal,
    this.guaranteeInitialNa = false,
    this.initialGuaranteeRate,
    this.finalGuaranteeRate,
    this.guaranteeFinalNa = false,
    this.retentionDeduct = true,
    this.contractRetentionRate,
    this.variationsAdd = 0,
    this.variationsDeduct = 0,
    this.extractsSubmitted = 0,
    this.valueSource = 'manual',
    this.executedSource = 'manual',
    this.variationsNet = 0,
    this.extractsCount = 0,
    this.extractsGross = 0,
    this.extractsNet = 0,
    this.extractsPaid = 0,
    this.retentionHeld = 0,
    this.advanceAmount,
    this.advancePaidOn,
    this.advanceRecovered = 0,
    this.extra = const {},
    this.updatedAt,
    this.updatedBy,
    this.limited = false,
  });

  final String id;
  final String assignNo;
  final String code;
  final String name;
  final String owner;
  final String company;
  final String department;
  final String notes;
  final Map<String, String> engineers; // eng_sup, eng_qty, eng_fol, eng_saf
  final int sortOrder;

  /// رقم العقد كما يدخله مكتب العقود (فارغ = لم يُحدَّد بعد).
  final String contractNo;
  // البيانات المالية للعقد (null = لم تُدخل بعد)
  final double? contractValue; // قيمة الأعمال التعاقدية
  final double? executedValue; // قيمة الأعمال المنفذة
  final double? paymentFirst;
  final double? paymentSecond;
  final double? paymentFinal;
  final double? deductions;
  final double? guaranteeInitial; // نسبة العقد من قيمة الأعمال المنفذة، تحسبه قاعدة البيانات (فارغ إن لم ينطبق)
  /// الضمان الابتدائي لا ينطبق على هذا العقد (الترحيل 18)
  final bool guaranteeInitialNa;
  final double? guaranteeFinal; // نسبة العقد من قيمة الأعمال المنفذة، تحسبه قاعدة البيانات (فارغ إن لم ينطبق)

  // ضمانات العقد وتأميناته (الترحيل 37): نسب ثابتة لكل عقد
  final double? initialGuaranteeRate;
  final double? finalGuaranteeRate;
  /// الضمان النهائي لا ينطبق على هذا العقد.
  final bool guaranteeFinalNa;
  /// خصم التأمينات من المستخلصات مفعّل.
  final bool retentionDeduct;
  /// نسبة التأمين المحتجز المقترحة في مستخلصات هذا العقد.
  final double? contractRetentionRate;
  final double variationsAdd; // الزيادة المعتمدة في أوامر التغيير
  final double variationsDeduct; // النقص المعتمد في أوامر التغيير
  final double extractsSubmitted; // إجمالي المستخلصات المقدمة (المقدَّم والمعتمد والمحال والمدفوع)

  // المالية الموسعة (تحسبها قاعدة البيانات من البنود والمستخلصات وأوامر التغيير)
  final String valueSource; // manual | items
  final String executedSource; // manual | items | extracts
  final double variationsNet; // صافي أوامر التغيير (زيادة − نقص)
  final int extractsCount; // المستخلصات المعتمدة والمدفوعة
  final double extractsGross; // إجمالي قيمة أعمالها
  final double extractsNet; // صافيها بعد الاستقطاعات
  final double extractsPaid; // المدفوع منها
  final double retentionHeld; // التأمين المحتجز منها
  final double? advanceAmount; // الدفعة المقدمة للعقد
  final DateTime? advancePaidOn; // تاريخ صرفها
  final double advanceRecovered; // ما استُرد منها في المستخلصات المعتمدة
  final Map<String, dynamic> extra; // قيم الحقول الإضافية
  final DateTime? updatedAt;
  final String? updatedBy;

  /// أساسيات العقد وحدها للربط (الترحيل 34): الرقم والاسم والشركة والجهة والقسم، دون المالية والتفاصيل،
  /// لمن لا يرى العقد بتفاصيله من قسمه (تُقرأ من project_refs()).
  final bool limited;

  String get title => name.trim().isNotEmpty ? name.trim() : 'مشروع بدون اسم';
  /// «عقد 5/2026 — اسم المشروع». رقم التكليف القديم لا يُعرض (الإصدار 1.4.0) إلا لعقد قديم بلا اسم ولا رقم.
  String get label {
    final parts = [if (contractNo.isNotEmpty) 'عقد $contractNo', name].where((s) => s.trim().isNotEmpty).toList();
    return parts.isNotEmpty ? parts.join(' — ') : (assignNo.isEmpty ? 'عقد بلا اسم' : assignNo);
  }

  /// عنوان مختصر للعقد: «عقد 12/2026» أو رقم التكليف عند غياب رقم العقد.
  String get contractTitle => contractNo.isNotEmpty ? 'عقد $contractNo' : 'عقد بلا رقم';

  /// اسم المشروع، وإلا رقم العقد (للعناوين القصيرة).
  String get shortName => name.trim().isNotEmpty ? name : (contractNo.isNotEmpty ? 'عقد $contractNo' : assignNo);
  String engineer(String field) => engineers[field] ?? '';

  double get paymentsTotal => (paymentFirst ?? 0) + (paymentSecond ?? 0) + (paymentFinal ?? 0);

  /// نسبتا الضمانين في هذا العقد (الافتراضيتان إن لم تُحدَّدا بعد).
  double get initialRate => initialGuaranteeRate ?? guaranteeInitialRate;
  double get finalRate => finalGuaranteeRate ?? guaranteeFinalRate;

  /// نسبة التأمين المقترحة في مستخلص جديد (صفر إن كان الخصم معطّلاً).
  double retentionRateOr(double fallback) => retentionDeduct ? (contractRetentionRate ?? fallback) : 0;

  /// المستحق من المستخلصات المعتمدة قبل الاستقطاعات وبعد المدفوع.
  double get unpaidGross => (extractsGross - extractsPaid).clamp(0, double.infinity).toDouble();

  /// استقطاعات المستخلصات المعتمدة عدا استرداد الدفعة المقدمة (التأمين المحتجز والغرامات والضرائب وغيرها).
  double get extractDeductions => (extractsGross - extractsNet - advanceRecovered).clamp(0, double.infinity).toDouble();

  /// نسبة الإنجاز المالي = المستخلصات المعتمدة ÷ القيمة المعدلة.
  double? get financialProgress {
    final a = adjustedValue;
    if (a == null || a <= 0) return null;
    return extractsGross / a;
  }

  /// القيمة التعاقدية تُحسب من قيم البنود.
  bool get valueFromItems => valueSource == 'items';

  /// قيمة الأعمال المنفذة تُحسب من البنود أو المستخلصات.
  bool get executedComputed => executedSource != 'manual';

  /// القيمة بعد أوامر التغيير.
  double? get adjustedValue => contractValue == null && variationsNet == 0 ? null : (contractValue ?? 0) + variationsNet;

  /// الدفعة المقدمة المصروفة (لها تاريخ صرف).
  double get advancePaid => advancePaidOn == null ? 0 : (advanceAmount ?? 0);

  /// رصيد الدفعة المقدمة الذي لم يُسترد بعد.
  double get advanceRemaining => ((advanceAmount ?? 0) - advanceRecovered).clamp(0, double.infinity).toDouble();

  /// كل المدفوع: مدفوع المستخلصات، والدفعة المقدمة المصروفة، والدفعات المسجلة يدوياً.
  double get paidTotal => extractsPaid + advancePaid + paymentsTotal;

  /// المتبقي من العقد (أعمال لم تُنفَّذ بعد) = القيمة بعد التغيير − المنفذ.
  double? get remainingWork {
    final a = adjustedValue;
    return a == null ? null : a - (executedValue ?? 0);
  }

  /// المتبقي للدفع من قيمة العقد = القيمة بعد التغيير − المدفوع.
  double? get remainingToPay {
    final a = adjustedValue;
    return a == null ? null : a - paidTotal;
  }

  /// مستحق غير مدفوع من المستخلصات المعتمدة.
  double get outstanding => (extractsNet - extractsPaid).clamp(0, double.infinity).toDouble();

  /// نسبة المدفوع إلى القيمة بعد التغيير.
  double? get paidRatio {
    final a = adjustedValue;
    if (a == null || a <= 0) return null;
    return paidTotal / a;
  }

  /// نسبة الأعمال المنفذة إلى التعاقدية (null إن لم تُدخل القيمتان).
  double? get executionRatio {
    final c = contractValue, e = executedValue;
    if (c == null || e == null || c <= 0) return null;
    return e / c;
  }

  factory Project.fromMap(Map<String, dynamic> m) => Project(
        id: _str(m['id']),
        assignNo: _str(m['assign_no']),
        code: _str(m['code']),
        name: _str(m['name']),
        owner: _str(m['owner']),
        company: _str(m['company']),
        department: _str(m['department']).isEmpty ? 'supervision' : _str(m['department']),
        notes: _str(m['notes']),
        engineers: {
          'eng_sup': _str(m['eng_sup']),
          'eng_qty': _str(m['eng_qty']),
          'eng_fol': _str(m['eng_fol']),
          'eng_saf': _str(m['eng_saf']),
        },
        sortOrder: (m['sort_order'] as num?)?.toInt() ?? 0,
        contractNo: _str(m['contract_no']),
        contractValue: _money(m['contract_value']),
        executedValue: _money(m['executed_value']),
        paymentFirst: _money(m['payment_first']),
        paymentSecond: _money(m['payment_second']),
        paymentFinal: _money(m['payment_final']),
        deductions: _money(m['deductions']),
        guaranteeInitial: _money(m['guarantee_initial']),
        guaranteeFinal: _money(m['guarantee_final']),
        guaranteeInitialNa: m['guarantee_initial_na'] == true,
        initialGuaranteeRate: _money(m['guarantee_initial_rate']),
        finalGuaranteeRate: _money(m['guarantee_final_rate']),
        guaranteeFinalNa: m['guarantee_final_na'] == true,
        retentionDeduct: m['retention_deduct'] != false,
        contractRetentionRate: _money(m['retention_rate']),
        variationsAdd: _money(m['variations_add']) ?? 0,
        variationsDeduct: _money(m['variations_deduct']) ?? 0,
        extractsSubmitted: _money(m['extracts_submitted']) ?? 0,
        valueSource: _str(m['value_source']).isEmpty ? 'manual' : _str(m['value_source']),
        executedSource: _str(m['executed_source']).isEmpty ? 'manual' : _str(m['executed_source']),
        variationsNet: _money(m['variations_net']) ?? 0,
        extractsCount: (m['extracts_count'] as num?)?.toInt() ?? 0,
        extractsGross: _money(m['extracts_gross']) ?? 0,
        extractsNet: _money(m['extracts_net']) ?? 0,
        extractsPaid: _money(m['extracts_paid']) ?? 0,
        retentionHeld: _money(m['retention_held']) ?? 0,
        advanceAmount: _money(m['advance_amount']),
        advancePaidOn: _date(m['advance_paid_on']),
        advanceRecovered: _money(m['advance_recovered']) ?? 0,
        extra: m['extra'] is Map ? Map<String, dynamic>.from(m['extra'] as Map) : const {},
        updatedAt: _date(m['updated_at']),
        updatedBy: m['updated_by'] as String?,
      );

  /// أساسيات عقد من project_refs() (للربط دون التفاصيل).
  factory Project.ref(Map<String, dynamic> m) => Project(
        id: _str(m['id']),
        assignNo: _str(m['assign_no']),
        code: _str(m['code']),
        name: _str(m['name']),
        owner: _str(m['owner']),
        company: _str(m['company']),
        department: _str(m['department']).isEmpty ? 'supervision' : _str(m['department']),
        notes: '',
        engineers: const {'eng_sup': '', 'eng_qty': '', 'eng_fol': '', 'eng_saf': ''},
        sortOrder: (m['sort_order'] as num?)?.toInt() ?? 0,
        contractNo: _str(m['contract_no']),
        limited: true,
      );
}

/// عمل (بند) داخل العقد: وصفه وشركته ورقمه الأصلي. الأعمال المدمجة تحمل أصلها.
class ContractWork {
  const ContractWork({
    required this.id,
    required this.projectId,
    required this.originProject,
    required this.title,
    required this.company,
    required this.refNo,
    required this.notes,
    required this.sort,
    this.createdAt,
    this.contractValue,
    this.executedValue,
  });

  final String id;
  final String projectId;
  final String? originProject;
  final String title;
  final String company;
  final String refNo;
  final String notes;
  final int sort;
  final DateTime? createdAt;
  final double? contractValue; // القيمة التعاقدية للبند
  final double? executedValue; // المنفذ من البند

  /// دُمج هذا العمل من عقد آخر (يعود إليه عند فك الدمج).
  bool get merged => originProject != null && originProject != projectId;

  String get display => [title, company].where((s) => s.trim().isNotEmpty).join(' · ');

  factory ContractWork.fromMap(Map<String, dynamic> m) => ContractWork(
        id: _str(m['id']),
        projectId: _str(m['project_id']),
        originProject: m['origin_project'] as String?,
        title: _str(m['title']),
        company: _str(m['company']),
        refNo: _str(m['ref_no']),
        notes: _str(m['notes']),
        sort: (m['sort'] as num?)?.toInt() ?? 0,
        createdAt: _date(m['created_at']),
        contractValue: _money(m['contract_value']),
        executedValue: _money(m['executed_value']),
      );
}

/// حالات أمر التغيير (الترحيل 37): لا يدخل في قيمة العقد إلا المعتمد.
const Map<String, String> variationStatusLabels = {'draft': 'مسودة', 'approved': 'معتمد', 'rejected': 'مرفوض'};

/// أمر تغيير: زيادة أو نقص على قيمة العقد، أو الاثنان معاً ببنوده.
class ContractVariation {
  const ContractVariation({
    required this.id,
    required this.projectId,
    required this.originProject,
    required this.workId,
    required this.refNo,
    required this.title,
    required this.kind,
    required this.amount,
    required this.approvedOn,
    required this.notes,
    this.createdAt,
    this.status = 'approved',
    double? addedValue,
    double? deductedValue,
    this.decidedBy,
    this.decidedAt,
    this.decisionNote = '',
    this.updatedAt,
  })  : addedValue = addedValue ?? (kind == 'deduct' ? 0.0 : amount),
        deductedValue = deductedValue ?? (kind == 'deduct' ? amount : 0.0);

  final String id;
  final String projectId;
  final String? originProject;
  final String? workId;
  final String refNo;
  final String title;
  final String kind; // add | deduct
  final double amount;
  final DateTime? approvedOn;
  final String notes;
  final DateTime? createdAt;
  final String status; // draft | approved | rejected
  final double addedValue; // قيمة الأعمال المضافة
  final double deductedValue; // قيمة الأعمال الملغاة أو المخفضة
  final String? decidedBy;
  final DateTime? decidedAt;
  final String decisionNote;
  final DateTime? updatedAt;

  bool get isAdd => kind == 'add';
  double get signed => addedValue - deductedValue;
  bool get merged => originProject != null && originProject != projectId;
  bool get isDraft => status == 'draft';
  bool get isApproved => status == 'approved';
  bool get isRejected => status == 'rejected';
  String get statusLabel => variationStatusLabels[status] ?? status;

  factory ContractVariation.fromMap(Map<String, dynamic> m) => ContractVariation(
        id: _str(m['id']),
        projectId: _str(m['project_id']),
        originProject: m['origin_project'] as String?,
        workId: m['work_id'] as String?,
        refNo: _str(m['ref_no']),
        title: _str(m['title']),
        kind: _str(m['kind']) == 'deduct' ? 'deduct' : 'add',
        amount: _money(m['amount']) ?? 0,
        approvedOn: _date(m['approved_on']),
        notes: _str(m['notes']),
        createdAt: _date(m['created_at']),
        status: const {'draft', 'approved', 'rejected'}.contains(m['status']) ? m['status'] as String : 'approved',
        addedValue: _money(m['added_value']),
        deductedValue: _money(m['deducted_value']),
        decidedBy: m['decided_by'] as String?,
        decidedAt: _date(m['decided_at']),
        decisionNote: _str(m['decision_note']),
        updatedAt: _date(m['updated_at']),
      );
}

/// بند في أمر تغيير: زيادة أو نقص، مربوط ببند المقايسة أو بعمل العقد أو حر.
class VariationItem {
  const VariationItem({
    this.id = '',
    this.variationId = '',
    this.sort = 0,
    required this.direction,
    this.boqSheetId,
    this.boqLine,
    this.workId,
    this.code = '',
    required this.description,
    this.unit = '',
    this.qty,
    this.unitPrice,
    required this.amount,
  });

  final String id;
  final String variationId;
  final int sort;
  final String direction; // add | deduct
  final String? boqSheetId;
  final int? boqLine;
  final String? workId;
  final String code;
  final String description;
  final String unit;
  final double? qty;
  final double? unitPrice;
  final double amount;

  bool get isAdd => direction != 'deduct';
  bool get linkedToBoq => boqSheetId != null && boqLine != null;

  /// القيمة = الكمية × السعر إن أُدخلا، وإلا القيمة المكتوبة.
  static double valueOf(double? qty, double? price, double? amount) =>
      qty != null && price != null ? roundMoney(qty * price) : roundMoney(amount ?? 0);

  Map<String, dynamic> toJson() => {
        'direction': direction,
        if (boqSheetId != null) 'boq_sheet_id': boqSheetId,
        if (boqLine != null) 'boq_line': boqLine,
        if (workId != null) 'work_id': workId,
        'code': code,
        'description': description,
        'unit': unit,
        if (qty != null) 'qty': qty,
        if (unitPrice != null) 'unit_price': unitPrice,
        'amount': amount,
      };

  VariationItem copyWith({String? direction, double? qty, double? unitPrice, double? amount, String? description}) => VariationItem(
        id: id,
        variationId: variationId,
        sort: sort,
        direction: direction ?? this.direction,
        boqSheetId: boqSheetId,
        boqLine: boqLine,
        workId: workId,
        code: code,
        description: description ?? this.description,
        unit: unit,
        qty: qty ?? this.qty,
        unitPrice: unitPrice ?? this.unitPrice,
        amount: amount ?? this.amount,
      );

  factory VariationItem.fromMap(Map<String, dynamic> m) => VariationItem(
        id: _str(m['id']),
        variationId: _str(m['variation_id']),
        sort: (m['sort'] as num?)?.toInt() ?? 0,
        direction: _str(m['direction']) == 'deduct' ? 'deduct' : 'add',
        boqSheetId: m['boq_sheet_id'] as String?,
        boqLine: (m['boq_line'] as num?)?.toInt(),
        workId: m['work_id'] as String?,
        code: _str(m['code']),
        description: _str(m['description']),
        unit: _str(m['unit']),
        qty: _money(m['qty']),
        unitPrice: _money(m['unit_price']),
        amount: _money(m['amount']) ?? 0,
      );
}

/// حدث في سجل أمر التغيير: إنشاء أو تعديل أو اعتماد أو رفض أو إعادة إلى مسودة، بصورة الأمر عندها.
class VariationEvent {
  const VariationEvent({
    required this.id,
    required this.variationId,
    required this.action,
    required this.actorName,
    required this.at,
    this.note = '',
    this.snapshot = const {},
  });

  final String id;
  final String variationId;
  final String action;
  final String actorName;
  final DateTime? at;
  final String note;
  final Map<String, dynamic> snapshot;

  static const labels = {'create': 'أُنشئ', 'update': 'عُدِّل', 'approve': 'اعتُمد', 'reject': 'رُفض', 'reopen': 'أُعيد إلى مسودة'};
  String get label => labels[action] ?? action;
  double? get added => _money(snapshot['added']);
  double? get deducted => _money(snapshot['deducted']);
  int get itemCount => snapshot['items'] is List ? (snapshot['items'] as List).length : 0;

  factory VariationEvent.fromMap(Map<String, dynamic> m) => VariationEvent(
        id: _str(m['id']),
        variationId: _str(m['variation_id']),
        action: _str(m['action']),
        actorName: _str(m['actor_name']),
        at: DateTime.tryParse(_str(m['at']))?.toLocal(),
        note: _str(m['note']),
        snapshot: m['snapshot'] is Map ? Map<String, dynamic>.from(m['snapshot'] as Map) : const {},
      );
}

/// لجنة استلام العقد (الترحيل 37): ابتدائي أو نهائي، برئيس واحد وأعضاء بصفاتهم.
const Map<String, String> committeeKindLabels = {'initial': 'لجنة الاستلام الابتدائي', 'final': 'لجنة الاستلام النهائي'};

/// نموذج تكليف كل لجنة في الدورة المستندية (من يختص به يشكّلها).
const Map<String, String> committeeFormKeys = {'initial': 'f25', 'final': 'f26'};

class CommitteeMember {
  const CommitteeMember({this.id = '', this.role = 'member', required this.name, this.title = '', this.profileId, this.sort = 0});

  final String id;
  final String role; // chair | member
  final String name;
  final String title; // الصفة الوظيفية أو الجهة
  final String? profileId;
  final int sort;

  bool get isChair => role == 'chair';

  Map<String, dynamic> toJson() => {'name': name.trim(), 'title': title.trim(), if (profileId != null) 'profile_id': profileId};

  factory CommitteeMember.fromMap(Map<String, dynamic> m) => CommitteeMember(
        id: _str(m['id']),
        role: _str(m['role']) == 'chair' ? 'chair' : 'member',
        name: _str(m['name']),
        title: _str(m['title']),
        profileId: m['profile_id'] as String?,
        sort: (m['sort'] as num?)?.toInt() ?? 0,
      );
}

class ContractCommittee {
  const ContractCommittee({
    required this.id,
    required this.projectId,
    this.originProject,
    required this.kind,
    this.decisionNo = '',
    this.decisionDate,
    this.notes = '',
    this.members = const [],
    this.updatedAt,
  });

  final String id;
  final String projectId;
  final String? originProject;
  final String kind; // initial | final
  final String decisionNo;
  final DateTime? decisionDate;
  final String notes;
  final List<CommitteeMember> members; // الرئيس أولاً ثم الأعضاء بترتيبهم
  final DateTime? updatedAt;

  bool get merged => originProject != null && originProject != projectId;
  CommitteeMember? get chair => members.where((m) => m.isChair).firstOrNull;
  List<CommitteeMember> get others => members.where((m) => !m.isChair).toList();
  String get label => committeeKindLabels[kind] ?? kind;

  /// نص اللجنة لمحضر الاستلام: «الرئيس (صفته) · العضو (صفته) …».
  String get text => [
        for (final m in members) [m.isChair ? 'رئيس اللجنة: ${m.name}' : m.name, if (m.title.isNotEmpty) '(${m.title})'].join(' '),
      ].join('، ');

  ContractCommittee withMembers(List<CommitteeMember> list) => ContractCommittee(
        id: id,
        projectId: projectId,
        originProject: originProject,
        kind: kind,
        decisionNo: decisionNo,
        decisionDate: decisionDate,
        notes: notes,
        members: list,
        updatedAt: updatedAt,
      );

  factory ContractCommittee.fromMap(Map<String, dynamic> m) => ContractCommittee(
        id: _str(m['id']),
        projectId: _str(m['project_id']),
        originProject: m['origin_project'] as String?,
        kind: _str(m['kind']) == 'final' ? 'final' : 'initial',
        decisionNo: _str(m['decision_no']),
        decisionDate: _date(m['decision_date']),
        notes: _str(m['notes']),
        updatedAt: _date(m['updated_at']),
      );
}

/// مفتاح مطابقة الأسماء كما في قاعدة البيانات (pm_text_norm): بلا تشكيل ولا تطويل، والهمزات ألف، والتاء المربوطة هاء.
String nameKey(String s) {
  final b = StringBuffer();
  for (final r in s.toLowerCase().runes) {
    if (r == 0x0640 || (r >= 0x064B && r <= 0x0652) || r == 0x0670) continue;
    var c = r;
    if (c == 0x0623 || c == 0x0625 || c == 0x0622 || c == 0x0671) c = 0x0627;
    if (c == 0x0629) c = 0x0647;
    if (c == 0x0649) c = 0x064A;
    b.writeCharCode(c);
  }
  return b.toString().trim().replaceAll(RegExp(r'\s+'), ' ');
}

/// حالات المستخلص بالترتيب.
const List<String> extractStatuses = ['draft', 'submitted', 'approved', 'referred', 'paid', 'rejected'];

const Map<String, String> extractStatusLabels = {
  'draft': 'مسودة',
  'submitted': 'مقدَّم',
  'approved': 'معتمد',
  'referred': 'محال للصرف',
  'paid': 'مدفوع',
  'rejected': 'مرفوض',
};

/// طرق صرف الدفعات.
const Map<String, String> paymentMethodLabels = {
  'transfer': 'حوالة مصرفية',
  'cheque': 'صك',
  'cash': 'نقداً',
  'other': 'أخرى',
};

/// دفعة من سجل صرف المستخلص.
class ExtractPayment {
  const ExtractPayment({
    required this.id,
    required this.extractId,
    required this.projectId,
    required this.amount,
    required this.paidOn,
    required this.method,
    required this.refNo,
    required this.notes,
    this.createdAt,
    this.createdBy,
  });

  final String id;
  final String extractId;
  final String projectId;
  final double amount;
  final DateTime? paidOn;
  final String method;
  final String refNo;
  final String notes;
  final DateTime? createdAt;
  final String? createdBy;

  String get methodLabel => paymentMethodLabels[method] ?? method;

  factory ExtractPayment.fromMap(Map<String, dynamic> m) => ExtractPayment(
        id: _str(m['id']),
        extractId: _str(m['extract_id']),
        projectId: _str(m['project_id']),
        amount: _money(m['amount']) ?? 0,
        paidOn: _date(m['paid_on']),
        method: _str(m['method']).isEmpty ? 'transfer' : _str(m['method']),
        refNo: _str(m['ref_no']),
        notes: _str(m['notes']),
        createdAt: _date(m['created_at']),
        createdBy: m['created_by'] as String?,
      );
}

/// استقطاع مخصص يعرّفه مدير المكتب (الاسم ونسبة افتراضية اختيارية من قيمة الأعمال).
class DeductionType {
  const DeductionType({required this.key, required this.label, this.rate});

  final String key;
  final String label;
  final double? rate;

  Map<String, dynamic> toJson() => {'key': key, 'label': label, 'rate': rate};
}

/// مستخلص: قيمة الأعمال في الفترة، واستقطاعاتها، وصافيها، وما دُفع منه.
class ContractExtract {
  const ContractExtract({
    required this.id,
    required this.projectId,
    required this.originProject,
    required this.workId,
    required this.seq,
    required this.refNo,
    required this.kind,
    required this.periodFrom,
    required this.periodTo,
    required this.submittedOn,
    required this.gross,
    required this.retention,
    required this.advanceRecovery,
    required this.penalties,
    required this.taxes,
    required this.otherDeductions,
    required this.net,
    required this.status,
    required this.approvedOn,
    required this.paidAmount,
    required this.paidOn,
    required this.notes,
    this.createdAt,
    this.updatedAt,
    this.updatedBy,
    this.referredOn,
    this.referralNo = '',
    this.customDeductions = const {},
    this.customTotal = 0,
  });

  final String id;
  final String projectId;
  final String? originProject;
  final String? workId;
  final DateTime? referredOn; // تاريخ الإحالة للصرف
  final String referralNo; // رقم كتاب الإحالة
  final Map<String, double> customDeductions; // الاستقطاعات المخصصة بمفاتيحها
  final double customTotal;
  final int seq;
  final String refNo;
  final String kind; // interim | final
  final DateTime? periodFrom;
  final DateTime? periodTo;
  final DateTime? submittedOn;
  final double gross;
  final double retention;
  final double advanceRecovery;
  final double penalties;
  final double taxes;
  final double otherDeductions;
  final double net;
  final String status;
  final DateTime? approvedOn;
  final double paidAmount;
  final DateTime? paidOn;
  final String notes;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final String? updatedBy;

  bool get counted => status == 'approved' || status == 'referred' || status == 'paid';
  bool get isPaid => status == 'paid';
  bool get isReferred => status == 'referred';
  bool get isFinal => kind == 'final';
  bool get merged => originProject != null && originProject != projectId;
  double get deductionsTotal => retention + advanceRecovery + penalties + taxes + otherDeductions + customTotal;
  double get otherThanRetention => advanceRecovery + penalties + taxes + otherDeductions + customTotal;
  double get unpaid => counted ? (net - paidAmount).clamp(0, double.infinity).toDouble() : 0;
  String get statusLabel => extractStatusLabels[status] ?? status;
  String get title => 'مستخلص ${isFinal ? 'ختامي' : 'رقم $seq'}${refNo.isNotEmpty ? ' ($refNo)' : ''}';

  /// تاريخ المستخلص للرسوم الزمنية: الدفع ثم الاعتماد ثم التقديم ثم نهاية الفترة.
  DateTime? get when => paidOn ?? approvedOn ?? submittedOn ?? periodTo ?? createdAt;

  factory ContractExtract.fromMap(Map<String, dynamic> m) => ContractExtract(
        id: _str(m['id']),
        projectId: _str(m['project_id']),
        originProject: m['origin_project'] as String?,
        workId: m['work_id'] as String?,
        seq: (m['seq'] as num?)?.toInt() ?? 0,
        refNo: _str(m['ref_no']),
        kind: _str(m['kind']) == 'final' ? 'final' : 'interim',
        periodFrom: _date(m['period_from']),
        periodTo: _date(m['period_to']),
        submittedOn: _date(m['submitted_on']),
        gross: _money(m['gross_amount']) ?? 0,
        retention: _money(m['retention']) ?? 0,
        advanceRecovery: _money(m['advance_recovery']) ?? 0,
        penalties: _money(m['penalties']) ?? 0,
        taxes: _money(m['taxes']) ?? 0,
        otherDeductions: _money(m['other_deductions']) ?? 0,
        net: _money(m['net_amount']) ?? 0,
        status: extractStatuses.contains(_str(m['status'])) ? _str(m['status']) : 'submitted',
        approvedOn: _date(m['approved_on']),
        paidAmount: _money(m['paid_amount']) ?? 0,
        paidOn: _date(m['paid_on']),
        notes: _str(m['notes']),
        createdAt: _date(m['created_at']),
        updatedAt: _date(m['updated_at']),
        updatedBy: m['updated_by'] as String?,
        referredOn: _date(m['referred_on']),
        referralNo: _str(m['referral_no']),
        customDeductions: m['custom_deductions'] is Map
            ? {
                for (final e in (m['custom_deductions'] as Map).entries)
                  if (e.value is num) e.key.toString(): (e.value as num).toDouble(),
              }
            : const {},
        customTotal: _money(m['custom_total']) ?? 0,
      );
}

/// جهاز دخل منه حساب (سجل الأجهزة).
class UserDevice {
  const UserDevice(this.raw);
  final Map<String, dynamic> raw;

  String get id => _str(raw['id']);
  String get userId => _str(raw['user_id']);
  String get name => _str(raw['name']);
  String get email => _str(raw['email']);
  String get platform => _str(raw['platform']);
  String get label => _str(raw['label']);
  String get userAgent => _str(raw['user_agent']);
  String get ip => _str(raw['ip']);
  String get firstIp => _str(raw['first_ip']);
  String get appVersion => _str(raw['app_version']);
  bool get trusted => raw['trusted'] == true;
  DateTime? get firstSeen => _date(raw['first_seen']);
  DateTime? get lastSeen => _date(raw['last_seen']);
  DateTime? get lastLogin => _date(raw['last_login']);
  int get signIns => (raw['sign_ins'] as num?)?.toInt() ?? 0;
  int get opens => (raw['opens'] as num?)?.toInt() ?? 0;
  DateTime? get blockedAt => _date(raw['blocked_at']);
  bool get blocked => blockedAt != null;
  String get blockedByName => _str(raw['blocked_by_name']);
  String get display => label.isNotEmpty ? label : (platformLabels[platform] ?? (platform.isEmpty ? 'جهاز' : platform));
}

const Map<String, String> platformLabels = {
  'android': 'Android',
  'ios': 'iPhone/iPad',
  'windows': 'Windows',
  'web': 'متصفح الويب',
  'macos': 'macOS',
  'linux': 'Linux',
};

/// مهندس مكلّف في العقد برقم تكليفه. أكثر من مهندس من كل نوع.
class ContractEngineer {
  const ContractEngineer({
    required this.id,
    required this.projectId,
    required this.originProject,
    required this.kind,
    required this.name,
    required this.assignNo,
    required this.assignedOn,
    required this.workId,
    required this.notes,
    required this.sort,
  });

  final String id;
  final String projectId;
  final String? originProject;
  final String kind; // sup | qty | fol | saf
  final String name;
  final String assignNo;
  final DateTime? assignedOn;
  final String? workId;
  final String notes;
  final int sort;

  bool get merged => originProject != null && originProject != projectId;

  factory ContractEngineer.fromMap(Map<String, dynamic> m) => ContractEngineer(
        id: _str(m['id']),
        projectId: _str(m['project_id']),
        originProject: m['origin_project'] as String?,
        kind: _str(m['kind']),
        name: _str(m['name']),
        assignNo: _str(m['assign_no']),
        assignedOn: _date(m['assigned_on']),
        workId: m['work_id'] as String?,
        notes: _str(m['notes']),
        sort: (m['sort'] as num?)?.toInt() ?? 0,
      );
}

/// رسالة في محادثة مساعد Claude.
class AssistantMessage {
  AssistantMessage({
    required this.role,
    required this.text,
    this.model = '',
    this.inputTokens = 0,
    this.outputTokens = 0,
    this.error = false,
    this.actions = const [],
    DateTime? at,
  }) : at = at ?? DateTime.now();

  final String role; // user | assistant
  final String text;
  final String model;
  final int inputTokens;
  final int outputTokens;
  final bool error;
  final List<AssistantAction> actions; // تعديلات يقترحها Claude وينفّذها المدير بضغطة
  final DateTime at;

  bool get isUser => role == 'user';
}

/// تعديل يقترحه مساعد Claude (أداة propose_*). لا يُنفَّذ إلا بضغطة المدير، وقاعدة البيانات تتحقق من الصلاحيات.
class AssistantAction {
  AssistantAction({required this.id, required this.name, required this.input});

  final String id;
  final String name;
  final Map<String, dynamic> input;
  String state = 'pending'; // pending | running | done | dismissed | failed
  String? result;

  String get summary => (input['summary'] ?? '').toString();

  static const Map<String, String> titles = {
    'propose_work_values': 'قيم بند',
    'propose_variation': 'أمر تغيير',
    'propose_extract': 'مستخلص جديد',
    'propose_extract_status': 'حالة مستخلص',
    'propose_contract_no': 'رقم عقد',
    'propose_form_status': 'حالة نموذج',
    'propose_setting': 'إعداد',
    'propose_idea': 'فكرة تطوير',
    'propose_extract_payment': 'دفعة مستخلص',
    'propose_contract_advance': 'دفعة مقدمة',
  };

  String get title => titles[name] ?? name;

  factory AssistantAction.fromMap(Map<String, dynamic> m) => AssistantAction(
        id: _str(m['id']),
        name: _str(m['name']),
        input: m['input'] is Map ? Map<String, dynamic>.from(m['input'] as Map) : <String, dynamic>{},
      );
}

/// تاريخ بصيغة قاعدة البيانات (yyyy-mm-dd).
String dbDate(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// تاريخ مقروء (yyyy/mm/dd).
String dayText(DateTime? d) => d == null ? '' : dbDate(d).replaceAll('-', '/');

enum RequestState { pending, approved, rejected, withdrawn }

RequestState parseRequestState(Object? v) => switch (v) {
      'approved' => RequestState.approved,
      'rejected' => RequestState.rejected,
      'withdrawn' => RequestState.withdrawn,
      _ => RequestState.pending,
    };

extension RequestStateX on RequestState {
  String get label => switch (this) {
        RequestState.pending => 'معلّق',
        RequestState.approved => 'معتمد',
        RequestState.rejected => 'مرفوض',
        RequestState.withdrawn => 'مسحوب',
      };
}

class ChangeRequest {
  const ChangeRequest({
    required this.id,
    required this.projectId,
    required this.formKey,
    required this.fromStatus,
    required this.toStatus,
    required this.note,
    required this.requestedBy,
    required this.requestedAt,
    required this.state,
    required this.decidedBy,
    required this.decidedAt,
    required this.decisionNote,
  });

  final String id;
  final String projectId;
  final String formKey;
  final FormStatus fromStatus;
  final FormStatus toStatus;
  final String note;
  final String? requestedBy;
  final DateTime? requestedAt;
  final RequestState state;
  final String? decidedBy;
  final DateTime? decidedAt;
  final String decisionNote;

  bool get isPending => state == RequestState.pending;

  factory ChangeRequest.fromMap(Map<String, dynamic> m) => ChangeRequest(
        id: _str(m['id']),
        projectId: _str(m['project_id']),
        formKey: _str(m['form_key']),
        fromStatus: parseStatus(m['from_status']),
        toStatus: parseStatus(m['to_status']),
        note: _str(m['note']),
        requestedBy: m['requested_by'] as String?,
        requestedAt: _date(m['requested_at']),
        state: parseRequestState(m['state']),
        decidedBy: m['decided_by'] as String?,
        decidedAt: _date(m['decided_at']),
        decisionNote: _str(m['decision_note']),
      );
}

class AuditEntry {
  const AuditEntry({
    required this.id,
    required this.at,
    required this.actor,
    required this.actorName,
    required this.projectId,
    required this.projectLabel,
    required this.action,
    required this.formKey,
    required this.detail,
  });

  final int id;
  final DateTime? at;
  final String? actor;
  final String actorName;
  final String? projectId;
  final String projectLabel;
  final String action;
  final String? formKey;
  final Map<String, dynamic> detail;

  factory AuditEntry.fromMap(Map<String, dynamic> m) => AuditEntry(
        id: (m['id'] as num?)?.toInt() ?? 0,
        at: _date(m['at']),
        actor: m['actor'] as String?,
        actorName: _str(m['actor_name']),
        projectId: m['project_id'] as String?,
        projectLabel: _str(m['project_label']),
        action: _str(m['action']),
        formKey: m['form_key'] as String?,
        detail: (m['detail'] is Map) ? Map<String, dynamic>.from(m['detail'] as Map) : <String, dynamic>{},
      );
}

const Map<String, String> auditActionLabels = {
  'risk.create': 'سجّل خطراً',
  'risk.update': 'عدّل خطراً',
  'risk.delete': 'حذف خطراً',
  'risk.review': 'سجّل مراجعة خطر',
  'risk.review_update': 'صحّح مراجعة خطر',
  'risk.review_delete': 'حذف مراجعة خطر',
  'pm.schedule': 'البرنامج الزمني للعقد',
  'pm.progress_add': 'سجّل قياس تقدم',
  'pm.progress_update': 'صحّح قياس تقدم',
  'pm.progress_delete': 'حذف قياس تقدم',
  'pm.item_add': 'أضاف بنداً للجدول الزمني',
  'pm.item_update': 'عدّل بند جدول زمني',
  'pm.item_delete': 'حذف بند جدول زمني',
  'pm.items_from_works': 'أنشأ بنود الجدول الزمني من أعمال العقد',
  'pm.items_reorder': 'رتّب بنود الجدول الزمني',
  'boq.create': 'أعدّ مقايسة أو استوردها من ملف',
  'boq.update': 'عدّل مقايسة',
  'boq.delete': 'حذف مقايسة',
  'pm.boq_orphans': 'حذف بنود مقايسات محذوفة من البرنامج الزمني',
  'boq.approve': 'اعتمد مقايسة',
  'boq.reopen': 'أعاد فتح مقايسة معتمدة',
  'pm.item_progress': 'حدّث إنجاز بند في البرنامج الزمني',
  'pm.plan_save': 'حدّث بداية البرنامج الزمني',
  'pm.phase_save': 'حفظ مرحلة تنفيذ',
  'pm.phase_delete': 'حذف مرحلة تنفيذ',
  'pm.plan_generate': 'ولّد برنامجاً زمنياً من المقايسة',
  'pm.plan_approve': 'اعتمد البرنامج الزمني وأحاله إلى الإشراف',
  'pm.plan_reopen': 'أعاد فتح البرنامج الزمني',
  'pm.link_add': 'أضاف علاقة بين نشاطين',
  'pm.link_update': 'عدّل علاقة بين نشاطين',
  'pm.link_delete': 'حذف علاقة بين نشاطين',
  'pm.rate_save': 'حفظ معدل إنتاجية',
  'pm.rate_delete': 'حذف قيد معدل إنتاجية',
  'risk.auto': 'ترجم التنفيذ إلى سجل المخاطر',
  'risk.action_save': 'سجّل إجراء استجابة لخطر',
  'risk.action_status': 'غيّر حالة إجراء استجابة',
  'risk.action_delete': 'حذف إجراء استجابة',
  'risk.sync_sections': 'حدّث مخاطر الأقسام تلقائياً',
  'geo.set': 'حدّد موقعاً على الخريطة',
  'geo.clear': 'أزال موقعاً من الخريطة',
  'budget.line_save': 'حفظ بند ميزانية',
  'budget.line_delete': 'حذف بند ميزانية',
  'budget.commit_save': 'سجّل التزاماً على بند ميزانية',
  'budget.commit_status': 'غيّر حالة التزام ميزانية',
  'budget.commit_delete': 'حذف التزام ميزانية',
  'finance.rate_save': 'أضاف إصداراً لنسبة مالية',
  'finance.deduction_save': 'حفظ خصم في دليل الخصومات',
  'finance.deduction_delete': 'حذف خصم من دليل الخصومات',
  'finance.perm_set': 'منح أو سحب صلاحية مالية',
  'milestone.save': 'حفظ معلماً في مشروع',
  'milestone.status': 'غيّر حالة معلم مشروع',
  'milestone.delete': 'حذف معلماً من مشروع',
  'kpi.def_save': 'حفظ تعريف مؤشر أداء',
  'kpi.def_delete': 'حذف مؤشر أداء',
  'kpi.value_set': 'سجّل قيمة مؤشر أداء',
  'kpi.value_delete': 'حذف قيمة مؤشر أداء',
  'swot.auto': 'ترجم التنفيذ إلى تحليل SWOT',
  'pm.issue_create': 'سجّل مشكلة',
  'pm.issue_update': 'عدّل مشكلة',
  'pm.issue_delete': 'حذف مشكلة',
  'pm.delay_create': 'سجّل حدث تأخير',
  'pm.delay_update': 'عدّل حدث تأخير',
  'pm.delay_delete': 'حذف حدث تأخير',
  'pm.change_create': 'سجّل طلب تغيير',
  'pm.change_update': 'عدّل طلب تغيير',
  'pm.change_delete': 'حذف طلب تغيير',
  'pm.lesson_create': 'وثّق درساً مستفاداً',
  'pm.lesson_update': 'عدّل درساً مستفاداً',
  'pm.lesson_delete': 'حذف درساً مستفاداً',
  'pm.evaluation_add': 'قيّم شركة ميدانياً',
  'pm.evaluation_update': 'عدّل تقييماً ميدانياً',
  'pm.evaluation_delete': 'حذف تقييماً ميدانياً',
  'swot.factor': 'عامل SWOT',
  'swot.strategy': 'استراتيجية SWOT',
  'swot.action': 'إجراء تنفيذي',
  'swot.progress': 'تحديث إنجاز إجراء',
  'swot.delete': 'حذف من تحليل SWOT',
  'project.create': 'أنشأ المشروع',
  'project.update': 'عدّل بيانات المشروع',
  'project.delete': 'حذف المشروع',
  'form.set': 'غيّر حالة نموذج',
  'request.create': 'قدّم طلب اعتماد',
  'request.approve': 'اعتمد طلباً',
  'request.reject': 'رفض طلباً',
  'request.withdraw': 'سحب طلباً',
  'note.add': 'أضاف ملاحظة تقييم',
  'user.activate': 'فعّل مستخدماً',
  'user.deactivate': 'أوقف مستخدماً',
  'user.update': 'عدّل صلاحيات مستخدم',
  'user.claim_director': 'تولّى إدارة المنظومة',
  'user.email': 'غيّر بريد الدخول',
  'user.rename': 'غيّر اسمه في المنظومة',
  'form_def.update': 'عدّل صلاحيات نموذج',
  'system.import': 'استيراد أولي للمشاريع',
  'project.field': 'عدّل حقلاً إضافياً',
  'setting.update': 'عدّل إعداداً',
  'security.setting': 'عدّل إعداد أمان',
  'security.session_revoke': 'أنهى جلسة',
  'security.user_signout': 'أخرج مستخدماً من أجهزته',
  'security.mfa_reset': 'ألغى التحقق بخطوتين لمستخدم',
  'config.stage': 'عدّل مرحلة',
  'config.stage_delete': 'حذف مرحلة',
  'config.form': 'عدّل نموذجاً',
  'config.form_order': 'غيّر ترتيب النماذج',
  'config.form_delete': 'حذف نموذجاً',
  'config.department': 'عدّل قسماً',
  'config.field': 'عدّل حقلاً إضافياً في التعريفات',
  'idea.create': 'أرسل فكرة',
  'idea.update': 'حدّث فكرة',
  'idea.delete': 'حذف فكرة',
  'idea.move': 'نقل فكرة إلى قسم أو صفحة',
  'user.delete': 'حذف مستخدماً',
  'contract.work_add': 'أضاف عملاً إلى العقد',
  'contract.work_update': 'عدّل عملاً في العقد',
  'contract.work_delete': 'حذف عملاً من العقد',
  'contract.merge': 'دمج أعمالاً في العقد',
  'contract.merged_into': 'دُمج في عقد',
  'contract.unmerge': 'فكّ دمج عمل',
  'engineer.add': 'كلّف مهندساً',
  'engineer.update': 'عدّل تكليف مهندس',
  'engineer.delete': 'ألغى تكليف مهندس',
  'engineer.set': 'حدّث أسماء المهندسين',
  'ai.ask': 'سأل مساعد Claude',
  'ai.action': 'نفّذ اقتراحاً من مساعد Claude',
  'finance.work_values': 'عدّل قيم بند',
  'finance.variation_add': 'سجّل أمر تغيير',
  'finance.variation_update': 'عدّل أمر تغيير',
  'finance.variation_delete': 'حذف أمر تغيير',
  'finance.extract_add': 'سجّل مستخلصاً',
  'finance.extract_update': 'عدّل مستخلصاً',
  'finance.extract_delete': 'حذف مستخلصاً',
  'finance.payment_add': 'سجّل دفعة مستخلص',
  'finance.payment_delete': 'حذف دفعة مستخلص',
  'finance.advance': 'عدّل الدفعة المقدمة',
  'finance.guarantee_initial': 'حدّد انطباق الضمان الابتدائي',
  'finance.guarantees': 'عدّل ضمانات العقد وتأميناته',
  'finance.variation_approve': 'اعتمد أمر تغيير',
  'finance.variation_reject': 'رفض أمر تغيير',
  'finance.variation_reopen': 'أعاد أمر تغيير إلى مسودة',
  'committee.save': 'شكّل لجنة استلام أو عدّلها',
  'committee.delete': 'حذف لجنة استلام',
  // قسم المخازن (الترحيل 38)
  'stores.setup': 'عدّل تهيئة المخازن',
  'stores.settings': 'عدّل إعدادات المخازن',
  'stores.employee': 'عدّل سجل موظف',
  'stores.employees_import': 'استورد الموظفين',
  'stores.item': 'عدّل بطاقة صنف',
  'stores.items_import': 'استورد الأصناف',
  'stores.doc_save': 'حفظ مستند مخزون',
  'stores.doc_submit': 'قدّم مستند مخزون للاعتماد',
  'stores.doc_return': 'أعاد مستند مخزون للتعديل',
  'stores.doc_reject': 'رفض مستند مخزون',
  'stores.doc_approve': 'اعتمد مستند مخزون',
  'stores.doc_post': 'رحّل مستند مخزون',
  'stores.doc_cancel': 'ألغى مستند مخزون',
  'stores.doc_delete': 'حذف مسودة مستند مخزون',
  'stores.doc_reverse': 'أنشأ مستنداً عكسياً',
  'stores.receipt_confirm': 'أكّد استلام ما صُرف له',
  'stores.asset': 'عدّل سجل أصل',
  'stores.asset_transfer': 'نقل أصلاً',
  'stores.asset_status': 'غيّر وضع أصل',
  'stores.custody_out': 'سلّم عهدة',
  'stores.custody_in': 'استلم عهدة مرجعة',
  'stores.custody_confirm': 'أكّد استلام عهدته أو إرجاعها',
  'stores.asset_dispose_request': 'طلب استبعاد أصل',
  'stores.asset_dispose': 'قرّر في استبعاد أصل',
  'stores.assets_import': 'استورد سجل الأصول',
  'stores.asset_policy': 'عدّل سياسة إهلاك',
  'stores.count_start': 'بدأ جلسة جرد',
  'stores.count_save': 'حفظ عدّ جلسة جرد',
  'stores.count_submit': 'قدّم جلسة جرد للقرار',
  'stores.count_return': 'أعاد جلسة جرد للعدّ',
  'stores.count_approve': 'اعتمد جلسة جرد',
  'stores.count_cancel': 'ألغى جلسة جرد',
  // قسم الصيانة (الترحيل 40)
  'maintenance.report': 'رفع بلاغ صيانة',
  'maintenance.assign': 'أسند بلاغ صيانة',
  'maintenance.start': 'بدأ تنفيذ بلاغ صيانة',
  'maintenance.hold': 'علّق بلاغ صيانة',
  'maintenance.resume': 'استأنف بلاغ صيانة',
  'maintenance.done': 'أنجز بلاغ صيانة',
  'maintenance.close': 'أكّد إغلاق بلاغ صيانة',
  'maintenance.reopen': 'أعاد فتح بلاغ صيانة',
  'maintenance.reject': 'رفض بلاغ صيانة',
  'maintenance.cancel': 'ألغى بلاغ صيانة',
  'maintenance.plan': 'عدّل خطة صيانة دورية',
  'maintenance.plan_delete': 'حذف خطة صيانة دورية',
  'maintenance.generate': 'ولّد بلاغات الصيانة الدورية',
  'maintenance.settings': 'عدّل إعدادات الصيانة',
  'maintenance.technician': 'عدّل قائمة فنيي الصيانة',
  'procurement.request': 'حفظ طلب احتياج',
  'procurement.submit': 'قدّم طلب احتياج',
  'procurement.review': 'راجع توفر طلب احتياج',
  'procurement.reject': 'رفض طلب احتياج',
  'procurement.decide': 'قرّر في طلب احتياج',
  'procurement.cancel': 'ألغى طلب احتياج',
  'procurement.supplier': 'عدّل بيانات مورّد',
  'procurement.quote': 'سجّل عرض سعر',
  'procurement.quote_delete': 'حذف عرض سعر',
  'procurement.order': 'أصدر أمر شراء',
  'procurement.order_cancel': 'ألغى أمر شراء',
  'procurement.receive': 'استلم دفعة من أمر شراء',
  'procurement.settings': 'عدّل إعدادات المشتريات',
  'procurement.comment': 'علّق على طلب احتياج',
  'security.user_lock': 'قفل دخول حساب',
  'security.user_unlock': 'فكّ قفل حساب',
  'security.device_new': 'دخل من جهاز جديد',
  'security.device_trust': 'وثّق جهازاً',
  'security.device_untrust': 'ألغى توثيق جهاز',
  'security.device_block': 'حظر جهازاً',
  'security.device_unblock': 'رفع حظر جهاز',
  'security.device_blocked_attempt': 'حاول الدخول من جهاز محظور',
  'doc.create': 'أضاف مستنداً أو مرفق عقد',
  'doc.update': 'عدّل مستنداً أو مرفق عقد',
  'doc.delete': 'حذف مستنداً أو مرفق عقد',
  'doc.revision_add': 'أضاف إصداراً لمستند',
  'doc.revision_update': 'عدّل إصدار مستند',
  'doc.revision_delete': 'حذف إصدار مستند',
  'doc.file_add': 'أرفق ملفاً بمستند',
  'doc.file_delete': 'أزال ملفاً من مستند',
  'report.create': 'رفع تقريراً يومياً',
  'report.update': 'عدّل تقريراً يومياً',
  'report.delete': 'حذف تقريراً يومياً',
  'report.review': 'اطّلع على تقرير يومي',
  'report.file_add': 'أرفق صورة أو ملفاً بتقرير يومي',
  'report.file_delete': 'أزال ملفاً من تقرير يومي',
  'unit.create': 'أضاف سجلاً في وحدة',
  'unit.update': 'عدّل سجلاً في وحدة',
  'unit.delete': 'حذف سجلاً من وحدة',
  'unit.file_add': 'أرفق ملفاً بسجل وحدة',
  'unit.file_delete': 'أزال ملفاً من سجل وحدة',
  'user.unit': 'أسند مستخدماً إلى وحدة',
  'print.template_save': 'حفظ قالب طباعة',
  'print.template_delete': 'حذف قالب طباعة',
  'export.file': 'استخرج ملفاً من المنظومة',
  'export.print': 'طبع من المنظومة',
  'export.store': 'حفظ نسخة PDF الأصلية لرمز التحقق',
  'export.open': 'فتح نسخة PDF أصلية من رمز التحقق',
  'export.denied': 'رُفض فتح نسخة PDF مقيّدة',
  'export.unknown': 'رمز تحقق غير معروف',
  'export.media': 'نزّل حزمة وسائط',
  'user.grants': 'عدّل الصلاحيات الدقيقة لمستخدم',
  'ref.scheme_save': 'حفظ صيغة رقم إشاري',
  'ref.scheme_delete': 'حذف صيغة رقم إشاري',
  'ref.counter_set': 'ضبط تسلسل رقم إشاري',
  'chat.room_create': 'أنشأ محادثة',
  'chat.room_update': 'عدّل محادثة',
  'chat.members': 'عدّل أعضاء محادثة',
  'chat.lock': 'قفل محادثة',
  'chat.unlock': 'فتح محادثة مقفلة',
  'chat.room_delete': 'حذف محادثة',
  'chat.message_delete': 'حذف رسالة لغيره',
  'security.incident_save': 'سجّل حادثة أمنية أو عدّلها',
  'security.incident_delete': 'حذف حادثة أمنية',
  'security.emergency_freeze': 'جمّد المنظومة أو رفع التجميد',
  'security.grants_suspend': 'علّق الصلاحيات الدقيقة لمستخدم',
};

const Map<String, String> projectFieldLabels = {
  'contract_no': 'رقم العقد',
  'executed_value': 'قيمة الأعمال المنفذة',
  'assign_no': 'رقم التكليف',
  'code': 'رمز المشروع',
  'name': 'اسم المشروع',
  'owner': 'مالك المشروع',
  'company': 'اسم الشركة',
  'department': 'القسم المشرف',
  'notes': 'الملاحظات',
  'eng_sup': 'المهندس المشرف',
  'eng_qty': 'مهندس الحصر',
  'eng_fol': 'مهندس المتابعة',
  'eng_saf': 'مهندس السلامة',
  'contract_value': 'قيمة الأعمال التعاقدية',
  'payment_first': 'الدفعة الأولى',
  'payment_second': 'الدفعة الثانية',
  'payment_final': 'الدفعة الختامية',
  'deductions': 'قيمة الخصومات',
};

class QualityNote {
  const QualityNote({required this.id, required this.projectId, required this.author, required this.body, required this.createdAt});

  final String id;
  final String projectId;
  final String? author;
  final String body;
  final DateTime? createdAt;

  factory QualityNote.fromMap(Map<String, dynamic> m) => QualityNote(
        id: _str(m['id']),
        projectId: _str(m['project_id']),
        author: m['author'] as String?,
        body: _str(m['body']),
        createdAt: _date(m['created_at']),
      );
}

class AppNotification {
  const AppNotification({
    required this.id,
    required this.createdAt,
    required this.kind,
    required this.title,
    required this.body,
    required this.projectId,
    required this.requestId,
    required this.readAt,
  });

  final String id;
  final DateTime? createdAt;
  final String kind;
  final String title;
  final String body;
  final String? projectId;
  final String? requestId;
  final DateTime? readAt;

  bool get unread => readAt == null;

  factory AppNotification.fromMap(Map<String, dynamic> m) => AppNotification(
        id: _str(m['id']),
        createdAt: _date(m['created_at']),
        kind: _str(m['kind']),
        title: _str(m['title']),
        body: _str(m['body']),
        projectId: m['project_id'] as String?,
        requestId: m['request_id'] as String?,
        readAt: _date(m['read_at']),
      );
}

/// إصدار منشور من سير عمل «release».
class AppRelease {
  const AppRelease({
    required this.platform,
    required this.version,
    required this.build,
    required this.url,
    required this.notes,
    required this.mandatory,
    this.publishedAt,
  });

  final String platform;
  final String version;
  final int build;
  final String url;
  final String notes;
  final bool mandatory;
  final DateTime? publishedAt;

  factory AppRelease.fromMap(Map<String, dynamic> m) => AppRelease(
        platform: _str(m['platform']),
        version: _str(m['version']),
        build: (m['build'] as num?)?.toInt() ?? 0,
        url: _str(m['url']),
        notes: _str(m['notes']),
        mandatory: m['mandatory'] == true,
        publishedAt: _date(m['published_at']),
      );
}

// ---------------------------------------------------------------------
// حساب الإنجاز
// ---------------------------------------------------------------------

enum CycleState { running, complete, notStarted }

extension CycleStateX on CycleState {
  String get label => switch (this) {
        CycleState.running => 'جارية',
        CycleState.complete => 'مكتملة',
        CycleState.notStarted => 'لم تبدأ',
      };
}

class Progress {
  const Progress({
    required this.done,
    required this.wip,
    required this.na,
    required this.required,
    required this.next,
    required this.cells,
  });

  final int done;
  final int wip;
  final int na;
  final int required;
  final FormDef? next;
  final List<FormStatus> cells; // بترتيب النماذج

  int get todo => required - done - wip;
  double get pct => required == 0 ? 1.0 : done / required;

  /// المرحلة الحالية، وعدد المراحل عند اكتمال الدورة.
  int get stage => next?.stage ?? stageNames.length;

  CycleState get cycle {
    if (next == null) return CycleState.complete;
    if (done + wip == 0) return CycleState.notStarted;
    return CycleState.running;
  }
}

Progress computeProgress(List<FormDef> allDefs, Map<String, FormStatus>? statuses) {
  var done = 0, wip = 0, na = 0;
  FormDef? next;
  final cells = <FormStatus>[];
  final defs = allDefs.where((d) => d.active).toList();
  for (final d in defs) {
    final s = statuses?[d.key] ?? FormStatus.todo;
    cells.add(s);
    switch (s) {
      case FormStatus.done:
        done++;
      case FormStatus.wip:
        wip++;
      case FormStatus.na:
        na++;
      case FormStatus.todo:
        break;
    }
    if (next == null && s != FormStatus.done && s != FormStatus.na) next = d;
  }
  return Progress(done: done, wip: wip, na: na, required: defs.length - na, next: next, cells: cells);
}

/// تطبيع النص العربي للبحث: إزالة التشكيل وتوحيد الألف والتاء المربوطة والياء.
String normalizeArabic(String s) {
  final buf = StringBuffer();
  for (final r in s.toLowerCase().runes) {
    if ((r >= 0x064B && r <= 0x0652) || r == 0x0640) continue; // تشكيل وتطويل
    if (r == 0x0623 || r == 0x0625 || r == 0x0622) {
      buf.writeCharCode(0x0627); // أ إ آ -> ا
    } else if (r == 0x0629) {
      buf.writeCharCode(0x0647); // ة -> ه
    } else if (r == 0x0649) {
      buf.writeCharCode(0x064A); // ى -> ي
    } else {
      buf.writeCharCode(r);
    }
  }
  return buf.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
}


// ---------------------------------------------------------------------
// المراحل والحقول الإضافية والأفكار والإعدادات الحية (الإصدار الثاني)
// ---------------------------------------------------------------------

class StageDef {
  const StageDef(this.idx, this.name);

  final int idx;
  final String name;

  factory StageDef.fromMap(Map<String, dynamic> m) => StageDef((m['idx'] as num?)?.toInt() ?? 0, _str(m['name']));
}

/// أنواع الحقول الإضافية.
const Map<String, String> fieldKindLabels = {
  'text': 'نص قصير',
  'longtext': 'نص طويل',
  'number': 'رقم',
  'money': 'مبلغ مالي',
  'date': 'تاريخ',
  'select': 'قائمة اختيار',
  'bool': 'نعم / لا',
};

class CustomField {
  const CustomField({
    required this.key,
    required this.label,
    required this.kind,
    required this.options,
    required this.section,
    required this.sort,
    required this.editableBy,
    required this.active,
  });

  final String key;
  final String label;
  final String kind;
  final List<String> options;
  final String section;
  final int sort;
  final List<String> editableBy;
  final bool active;

  factory CustomField.fromMap(Map<String, dynamic> m) => CustomField(
        key: _str(m['key']),
        label: _str(m['label']),
        kind: _str(m['kind']),
        options: (m['options'] as List?)?.map((e) => e.toString()).toList() ?? const [],
        section: _str(m['section']),
        sort: (m['sort'] as num?)?.toInt() ?? 0,
        editableBy: (m['editable_by'] as List?)?.map((e) => e.toString()).toList() ?? const [],
        active: m['active'] != false,
      );

  /// القيمة كما تُعرض.
  String display(Object? v) {
    if (v == null) return '—';
    return switch (kind) {
      'money' => v is num ? '${fmtMoney(v.toDouble())} $currencyLabel' : v.toString(),
      'number' => v is num ? fmtMoney(v.toDouble()) : v.toString(),
      'bool' => v == true ? 'نعم' : 'لا',
      'date' => v.toString().replaceAll('-', '/'),
      _ => v.toString().isEmpty ? '—' : v.toString(),
    };
  }
}

const Map<String, String> ideaCategoryLabels = {
  'feature': 'ميزة جديدة',
  'design': 'التصميم والشكل',
  'data': 'البيانات والتقارير',
  'security': 'الأمان',
  'bug': 'خلل يحتاج إصلاحاً',
  'other': 'أخرى',
};

const Map<String, String> ideaPriorityLabels = {'low': 'منخفضة', 'normal': 'عادية', 'high': 'عالية', 'urgent': 'عاجلة'};

const Map<String, String> ideaStatusLabels = {
  'new': 'جديدة',
  'planned': 'مخطط لها',
  'in_progress': 'قيد التنفيذ',
  'done': 'نُفّذت',
  'rejected': 'مستبعدة',
};

class Idea {
  const Idea({
    required this.id,
    required this.title,
    required this.body,
    required this.category,
    required this.priority,
    required this.status,
    required this.response,
    required this.createdBy,
    required this.createdAt,
    required this.updatedAt,
    required this.githubUrl,
    this.section,
    this.pageId,
    this.pageLabel = '',
  });

  final String id;
  final String title;
  final String body;
  final String category;
  final String priority;
  final String status;
  final String response;
  final String? createdBy;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final String githubUrl;

  /// القسم الذي كُتبت منه الفكرة أو نقلها إليه المدير (null = فكرة عامة للمنظومة). الترحيل 33.
  final String? section;

  /// الصفحة داخل القسم (null = للقسم كله)، واسمها كما ظهر لكاتبها.
  final int? pageId;
  final String pageLabel;

  /// جديدة أو مخططة أو قيد التنفيذ.
  bool get isOpen => status == 'new' || status == 'planned' || status == 'in_progress';

  factory Idea.fromMap(Map<String, dynamic> m) => Idea(
        id: _str(m['id']),
        title: _str(m['title']),
        body: _str(m['body']),
        category: _str(m['category']),
        priority: _str(m['priority']),
        status: _str(m['status']),
        response: _str(m['response']),
        createdBy: m['created_by'] as String?,
        createdAt: _date(m['created_at']),
        updatedAt: _date(m['updated_at']),
        githubUrl: _str(m['github_url']),
        section: (m['section'] as String?)?.trim().isEmpty ?? true ? null : (m['section'] as String).trim(),
        pageId: (m['page_id'] as num?)?.toInt(),
        pageLabel: _str(m['page_label']),
      );
}

/// الإعدادات الحية كما تُقرأ من جدول app_settings.
class LiveSettings {
  LiveSettings(this.raw);

  final Map<String, dynamic> raw;

  static LiveSettings empty() => LiveSettings(const {});

  String str(String key, String fallback) {
    final v = raw[key];
    return v is String && v.trim().isNotEmpty ? v : fallback;
  }

  bool flag(String key, bool fallback) {
    final v = raw[key];
    return v is bool ? v : fallback;
  }

  double number(String key, double fallback) {
    final v = raw[key];
    return v is num ? v.toDouble() : fallback;
  }

  Map<String, dynamic> map(String key) {
    final v = raw[key];
    return v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};
  }

  String get appTitle => str('brand.app_title', 'منظومة رصد');
  String get orgName => str('brand.org_name', 'مكتب الشؤون الهندسية');
  String get orgParent => str('brand.org_parent', 'لجنة إعادة إعمار منطقة الصابري ووسط البلاد');
  String get primaryHex => str('brand.primary_color', '#8A6A1E');
  String get announcementText => (map('ui.announcement')['text'] ?? '').toString();
  String get announcementLevel => (map('ui.announcement')['level'] ?? 'info').toString();
  bool feature(String name, {bool fallback = true}) {
    final v = map('ui.features')[name];
    return v is bool ? v : fallback;
  }

  bool get frozen => flag('security.freeze', false);
  bool get signupsOpen => flag('security.signups_open', true);
  bool get requireMfaDirector => flag('security.require_mfa_director', false);
  bool get requireMfaAll => flag('security.require_mfa_all', false);
  int get idleMinutes => number('security.idle_minutes', 30).round();

  // ---- التعديل الداخلي (المدير) ----

  /// مستوى الحركة: full كاملة، reduced مخففة، off بلا حركة.
  String get motion => normalizeMotion(raw['ui.motion']);

  /// صفحات القائمة المخفية عن الموظفين.
  List<String> get navHidden => strList(map('ui.nav')['hidden']);

  /// ترتيب صفحات القائمة.
  List<String> get navOrder => strList(map('ui.nav')['order']);

  /// أسماء مخصصة لصفحات القائمة.
  Map<String, String> get navLabels => strMap(map('ui.nav')['labels']);

  /// أقسام الرئيسية بالترتيب وحالة ظهورها.
  List<(String, bool)> get dashboardSections {
    final l = map('ui.dashboard')['sections'];
    if (l is! List) return const [];
    return [
      for (final x in l)
        if (x is Map && x['key'] is String) (x['key'] as String, x['on'] != false),
    ];
  }

  /// المصطلحات المخصصة (العقد، الأعمال...).
  Map<String, String> get terms => strMap(raw['ui.labels']);

  /// النسب الافتراضية للمستخلصات (من قيمة الأعمال).
  double get retentionRate => number('finance.retention_rate', 0.1);
  double get taxRate => number('finance.tax_rate', 0);

  /// نسبة استرداد الدفعة المقدمة من كل مستخلص (0 = بنسبة الدفعة إلى قيمة العقد).
  double get advanceRecoveryRate => number('finance.advance_recovery_rate', 0);

  /// الاستقطاعات المخصصة التي يعرّفها المدير.
  List<DeductionType> get deductionTypes {
    final v = raw['finance.deduction_types'];
    if (v is! List) return const [];
    return [
      for (final x in v)
        if (x is Map && x['key'] is String && x['label'] is String)
          DeductionType(key: x['key'] as String, label: x['label'] as String, rate: x['rate'] is num ? (x['rate'] as num).toDouble() : null),
    ];
  }

  bool get aiEnabled => flag('ai.enabled', true);
  String get aiModel => str('ai.model', 'claude-sonnet-5-5');
  String get aiInstructions => raw['ai.instructions'] is String ? raw['ai.instructions'] as String : '';

  /// يطبّق القيم العامة على المتغيرات المشتركة (المسميات والنسب والعملة والحركة والمصطلحات).
  void applyGlobals() {
    final labels = map('ui.status_labels');
    for (final k in const ['done', 'wip', 'todo', 'na']) {
      final v = labels[k];
      if (v is String && v.trim().isNotEmpty) statusLabels[k] = v.trim();
    }
    guaranteeInitialRate = number('finance.guarantee_initial_rate', 0.02);
    guaranteeFinalRate = number('finance.guarantee_final_rate', 0.05);
    currencyLabel = str('finance.currency', 'د.ل');
    motionSetting = motion;
    customTerms
      ..clear()
      ..addAll(terms);
  }
}

List<String> strList(Object? v) => v is List ? [for (final x in v) if (x is String && x.isNotEmpty) x] : <String>[];

Map<String, String> strMap(Object? v) {
  if (v is! Map) return <String, String>{};
  return {
    for (final e in v.entries)
      if (e.value is String && (e.value as String).trim().isNotEmpty) e.key.toString(): (e.value as String).trim(),
  };
}

// ---------------------------------------------------------------------
// الحركة والمصطلحات (يتحكم بها المدير من «التخصيص والتطوير»)
// ---------------------------------------------------------------------

/// مستوى الحركة في الواجهة: full | reduced | off.
String motionSetting = 'full';

String normalizeMotion(Object? v) => v is String && (v == 'reduced' || v == 'off') ? v : 'full';

/// المصطلحات الافتراضية التي يستطيع المدير تغييرها.
const Map<String, String> defaultTerms = {
  'contracts': 'العقود',
  'contract': 'العقد',
  'new_contract': 'عقد جديد',
  'works': 'أعمال العقد',
  'company': 'الشركة المنفذة',
  'engineers': 'المهندسون والتكليفات',
  'finance': 'البيانات المالية للعقد',
  'cycle': 'نماذج الدورة المستندية',
};

/// شرح كل مصطلح في شاشة التخصيص.
const Map<String, String> termHints = {
  'contracts': 'اسم صفحة العقود وعناوين القوائم',
  'contract': 'كلمة «العقد» في صفحة التفاصيل',
  'new_contract': 'زر الإضافة',
  'works': 'عنوان قائمة الأعمال المدمجة في العقد',
  'company': 'مسمى الشركة في البطاقات والتصفية',
  'engineers': 'عنوان قسم المهندسين وأرقام تكليفهم',
  'finance': 'عنوان القيم المالية والضمانات',
  'cycle': 'عنوان قائمة النماذج والمراحل',
};

final Map<String, String> customTerms = {};

/// المصطلح كما يحدده المدير، أو الافتراضي.
String term(String key) => customTerms[key] ?? defaultTerms[key] ?? key;

/// نسبة مئوية مقروءة من كسر (0.05 ← 5%).
String rateText(double r) {
  final v = r * 100;
  return '${v == v.roundToDouble() ? v.round() : v.toStringAsFixed(1)}%';
}
