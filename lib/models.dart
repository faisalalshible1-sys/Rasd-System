// نماذج البيانات ومنطق حساب الإنجاز. يطابق منطق ملف Excel الأصلي وعرض v_project_progress.

enum FormStatus { done, wip, todo, na }

extension FormStatusX on FormStatus {
  String get label => switch (this) {
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

enum AppRole { director, officeStaff, deptHead, contracts, planningQa }

extension AppRoleX on AppRole {
  String get db => switch (this) {
        AppRole.director => 'director',
        AppRole.officeStaff => 'office_staff',
        AppRole.deptHead => 'dept_head',
        AppRole.contracts => 'contracts',
        AppRole.planningQa => 'planning_qa',
      };

  String get label => switch (this) {
        AppRole.director => 'مدير المكتب',
        AppRole.officeStaff => 'موظف مكتب المدير',
        AppRole.deptHead => 'رئيس قسم',
        AppRole.contracts => 'مكتب العقود والتوريدات والمستخلصات',
        AppRole.planningQa => 'مكتب التخطيط والتقييم وضمان الجودة',
      };
}

AppRole? parseRole(Object? v) => switch (v) {
      'director' => AppRole.director,
      'office_staff' => AppRole.officeStaff,
      'dept_head' => AppRole.deptHead,
      'contracts' => AppRole.contracts,
      'planning_qa' => AppRole.planningQa,
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

const List<String> stageNames = ['التعاقد', 'تكليف المهندسين', 'بدء التنفيذ', 'المستخلصات', 'الاستلام والإقفال'];
const String stageDoneName = 'اكتملت الدورة';

String stageName(int i) => i >= 0 && i < stageNames.length ? stageNames[i] : stageDoneName;

DateTime? _date(Object? v) => v == null ? null : DateTime.tryParse(v.toString());
String _str(Object? v) => v == null ? '' : v.toString();

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
  });

  final String key;
  final String name;
  final int stage;
  final int sort;
  final bool sensitive;
  final List<String> responsible;
  final String? engineerField;

  factory FormDef.fromMap(Map<String, dynamic> m) => FormDef(
        key: _str(m['key']),
        name: _str(m['name']),
        stage: (m['stage'] as num?)?.toInt() ?? 0,
        sort: (m['sort'] as num?)?.toInt() ?? 0,
        sensitive: m['sensitive'] == true,
        responsible: (m['responsible'] as List?)?.map((e) => e.toString()).toList() ?? const [],
        engineerField: m['engineer_field'] as String?,
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

  /// 0..4 المرحلة الحالية، و5 عند اكتمال الدورة.
  int get stage => next?.stage ?? 5;

  CycleState get cycle {
    if (next == null) return CycleState.complete;
    if (done + wip == 0) return CycleState.notStarted;
    return CycleState.running;
  }
}

Progress computeProgress(List<FormDef> defs, Map<String, FormStatus>? statuses) {
  var done = 0, wip = 0, na = 0;
  FormDef? next;
  final cells = <FormStatus>[];
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
