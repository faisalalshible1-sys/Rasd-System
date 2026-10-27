// نماذج البيانات ومنطق حساب الإنجاز. يطابق منطق ملف Excel الأصلي وعرض v_project_progress.

enum FormStatus { done, wip, todo, na }

/// مسميات الحالات (قابلة للتعديل من الإعدادات الحية).
final Map<String, String> statusLabels = {'done': 'مكتمل', 'wip': 'قيد الإجراء', 'todo': 'لم يتم', 'na': 'لا ينطبق'};

extension FormStatusX on FormStatus {
  String get label => statusLabels[name] ?? switch (this) {
        FormStatus.done => 'مكتمل',
        FormStatus.wip => 'قيد الإجراء',
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

enum AppRole { director, officeStaff, deptHead, contracts, planningQa, securityAuditor }

extension AppRoleX on AppRole {
  String get db => switch (this) {
        AppRole.director => 'director',
        AppRole.officeStaff => 'office_staff',
        AppRole.deptHead => 'dept_head',
        AppRole.contracts => 'contracts',
        AppRole.planningQa => 'planning_qa',
        AppRole.securityAuditor => 'security_auditor',
      };

  String get label => switch (this) {
        AppRole.director => 'مدير المكتب',
        AppRole.officeStaff => 'موظف مكتب المدير',
        AppRole.deptHead => 'رئيس قسم',
        AppRole.contracts => 'مكتب العقود والتوريدات والمستخلصات',
        AppRole.planningQa => 'مكتب التخطيط والتقييم وضمان الجودة',
        AppRole.securityAuditor => 'مدقق الأمن',
      };

  /// وصف مختصر لما يستطيعه كل دور (يظهر عند اختيار الدور).
  String get summary => switch (this) {
        AppRole.director => 'كل الصلاحيات',
        AppRole.officeStaff => 'يضيف المشاريع ويعدّلها ويحدّث النماذج كلها، والحساسة بطلب اعتماد',
        AppRole.deptHead => 'يحدّث نماذج اختصاص قسمه فقط',
        AppRole.contracts => 'يحدّث نماذج التعاقد والمستخلصات وإقفال العقد والبيانات المالية',
        AppRole.planningQa => 'يطّلع على المؤشرات ويصدّر التقارير ويسجّل ملاحظات الجودة',
        AppRole.securityAuditor =>
          'التدقيق الأمني على المعلومات: اطلاع كامل للقراءة فقط على مركز الأمان وسجل التدقيق وبيانات المستخدمين، '
              'دون أي تعديل. التحقق بخطوتين إلزامي له.',
      };
}

AppRole? parseRole(Object? v) => switch (v) {
      'director' => AppRole.director,
      'office_staff' => AppRole.officeStaff,
      'dept_head' => AppRole.deptHead,
      'contracts' => AppRole.contracts,
      'planning_qa' => AppRole.planningQa,
      'security_auditor' => AppRole.securityAuditor,
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
List<String> stageNames = ['التعاقد', 'تكليف المهندسين', 'بدء التنفيذ', 'المستخلصات', 'الاستلام والإقفال'];
const String stageDoneName = 'اكتملت الدورة';

String stageName(int i) => i >= 0 && i < stageNames.length ? stageNames[i] : stageDoneName;

DateTime? _date(Object? v) => v == null ? null : DateTime.tryParse(v.toString());
String _str(Object? v) => v == null ? '' : v.toString();
double? _money(Object? v) => v == null ? null : (v is num ? v.toDouble() : double.tryParse(v.toString()));

// ---------------------------------------------------------------------
// البيانات المالية للعقد (بالدينار الليبي)
// ---------------------------------------------------------------------

/// نموذج «أمر تعاقد»: من يختص به يحدّث البيانات المالية للعقد.
const String contractFormKey = 'f01';

/// الضمان الابتدائي والنهائي نسبةً من قيمة التعاقد (تحسبهما قاعدة البيانات بالنسبتين نفسيهما).
double guaranteeInitialRate = 0.05;
double guaranteeFinalRate = 0.02;

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
      'eng_sup' => 'اسم المهندس المشرف',
      'eng_qty' => 'اسم مهندس الحصر',
      'eng_fol' => 'اسم مهندس المتابعة',
      'eng_saf' => 'اسم مهندس السلامة',
      _ => field,
    };

class Profile {
  const Profile({
    required this.id,
    required this.fullName,
    required this.email,
    required this.role,
    required this.department,
    required this.active,
    this.createdAt,
  });

  final String id;
  final String fullName;
  final String email;
  final AppRole? role;
  final String? department;
  final bool active;
  final DateTime? createdAt;

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
    this.contractValue,
    this.paymentFirst,
    this.paymentSecond,
    this.paymentFinal,
    this.deductions,
    this.guaranteeInitial,
    this.guaranteeFinal,
    this.extra = const {},
    this.updatedAt,
    this.updatedBy,
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
  // البيانات المالية للعقد (null = لم تُدخل بعد)
  final double? contractValue;
  final double? paymentFirst;
  final double? paymentSecond;
  final double? paymentFinal;
  final double? deductions;
  final double? guaranteeInitial; // 5% من قيمة التعاقد، تحسبه قاعدة البيانات
  final double? guaranteeFinal; // 2% من قيمة التعاقد، تحسبه قاعدة البيانات
  final Map<String, dynamic> extra; // قيم الحقول الإضافية
  final DateTime? updatedAt;
  final String? updatedBy;

  String get title => name.trim().isNotEmpty ? name.trim() : 'مشروع بدون اسم';
  String get label => [assignNo, name].where((s) => s.trim().isNotEmpty).join(' — ');
  String engineer(String field) => engineers[field] ?? '';

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
        contractValue: _money(m['contract_value']),
        paymentFirst: _money(m['payment_first']),
        paymentSecond: _money(m['payment_second']),
        paymentFinal: _money(m['payment_final']),
        deductions: _money(m['deductions']),
        guaranteeInitial: _money(m['guarantee_initial']),
        guaranteeFinal: _money(m['guarantee_final']),
        extra: m['extra'] is Map ? Map<String, dynamic>.from(m['extra'] as Map) : const {},
        updatedAt: _date(m['updated_at']),
        updatedBy: m['updated_by'] as String?,
      );
}

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
};

const Map<String, String> projectFieldLabels = {
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
  'contract_value': 'قيمة التعاقد',
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

  String get appTitle => str('brand.app_title', 'منظومة متابعة الدورة المستندية');
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

  /// يطبّق القيم العامة على المتغيرات المشتركة (المسميات والنسب والعملة).
  void applyGlobals() {
    final labels = map('ui.status_labels');
    for (final k in const ['done', 'wip', 'todo', 'na']) {
      final v = labels[k];
      if (v is String && v.trim().isNotEmpty) statusLabels[k] = v.trim();
    }
    guaranteeInitialRate = number('finance.guarantee_initial_rate', 0.05);
    guaranteeFinalRate = number('finance.guarantee_final_rate', 0.02);
    currencyLabel = str('finance.currency', 'د.ل');
  }
}

/// نسبة مئوية مقروءة من كسر (0.05 ← 5%).
String rateText(double r) {
  final v = r * 100;
  return '${v == v.roundToDouble() ? v.round() : v.toStringAsFixed(1)}%';
}
