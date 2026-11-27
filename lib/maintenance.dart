// =====================================================================
// قسم الصيانة (الإصدار 1.9.0، الترحيل 40): نماذج البيانات والحسابات.
//
// الموعد المستهدف للبلاغ = وقت رفعه + مدة الإنجاز لأولويته (من الإعدادات)، أو آخر يوم التاريخ الذي يحدده المدير عند الإسناد.
// موعد الخطة الدورية رقم k = تاريخ البدء + k × التكرار (من تاريخ البدء لا من الموعد السابق فلا ينزلق نهاية الأشهر)،
// ويُولَّد بلاغها قبل استحقاقه بالتنبيه المسبق (أيام الخطة أو الإعداد العام).
// =====================================================================

String _s(Object? v) => v == null ? '' : '$v';
String? _id(Object? v) => v == null || '$v'.isEmpty ? null : '$v';
DateTime? _d(Object? v) => v == null ? null : DateTime.tryParse('$v')?.toLocal();
int _i(Object? v) => v is num ? v.toInt() : int.tryParse('${v ?? ''}') ?? 0;

DateTime? _day(Object? v) {
  if (v == null) return null;
  final d = DateTime.tryParse('$v');
  return d == null ? null : DateTime(d.year, d.month, d.day);
}

const Map<String, String> mtCategoryLabels = {
  'electrical': 'كهرباء',
  'plumbing': 'سباكة',
  'hvac': 'تكييف وتبريد',
  'civil': 'أعمال مدنية',
  'carpentry': 'نجارة',
  'it': 'حاسوب وشبكات',
  'furniture': 'أثاث',
  'cleaning': 'نظافة',
  'safety': 'سلامة',
  'other': 'غير ذلك',
};

const Map<String, String> mtTradeLabels = {
  'general': 'عام',
  'electrical': 'كهرباء',
  'plumbing': 'سباكة',
  'hvac': 'تكييف وتبريد',
  'civil': 'أعمال مدنية',
  'carpentry': 'نجارة',
  'it': 'حاسوب وشبكات',
  'furniture': 'أثاث',
  'cleaning': 'نظافة',
  'safety': 'سلامة',
};

const Map<String, String> mtPriorityLabels = {'low': 'منخفضة', 'normal': 'عادية', 'high': 'عالية', 'urgent': 'عاجلة'};

const Map<String, String> mtStatusLabels = {
  'new': 'جديد',
  'assigned': 'مُسنَد',
  'in_progress': 'قيد التنفيذ',
  'on_hold': 'معلّق',
  'done': 'منجَز',
  'closed': 'مغلق',
  'rejected': 'مرفوض',
  'cancelled': 'ملغى',
};

const Map<String, String> mtUnitLabels = {'day': 'يوم', 'week': 'أسبوع', 'month': 'شهر', 'year': 'سنة'};

const Map<String, String> mtEventLabels = {
  'create': 'رفع البلاغ',
  'assign': 'إسناد',
  'start': 'بدء التنفيذ',
  'hold': 'تعليق',
  'resume': 'استئناف',
  'done': 'إنجاز',
  'close': 'تأكيد الإغلاق',
  'reopen': 'إعادة فتح',
  'reject': 'رفض',
  'cancel': 'إلغاء',
  'update': 'تعديل',
  'comment': 'تعليق',
};

const Map<String, String> mtAlertLabels = {
  'overdue': 'متأخر',
  'unassigned': 'لم يُسنَد',
  'on_hold': 'معلّق طويلاً',
  'due_soon': 'قريب الاستحقاق',
  'awaiting_confirm': 'ينتظر التأكيد',
  'warranty': 'تحت الضمان',
  'repeat': 'تكرار أعطال',
};

/// ترتيب عرض التنبيهات: الأشد أولاً.
const List<String> mtAlertOrder = ['overdue', 'unassigned', 'on_hold', 'repeat', 'due_soon', 'awaiting_confirm', 'warranty'];

const List<String> mtPriorityOrder = ['urgent', 'high', 'normal', 'low'];

/// الإعدادات المبدئية (كما في الترحيل 40).
const Map<String, num> mtDefaultNumbers = {
  'assign_hours': 4,
  'hold_days': 7,
  'confirm_days': 3,
  'soon_hours': 24,
  'repeat_count': 3,
  'repeat_days': 90,
  'plan_lead_days': 7,
};

const Map<String, int> mtDefaultSla = {'urgent': 8, 'high': 48, 'normal': 120, 'low': 240};

class MtSettings {
  const MtSettings({this.sla = mtDefaultSla, this.numbers = mtDefaultNumbers});

  final Map<String, int> sla;
  final Map<String, num> numbers;

  int slaHours(String priority) => sla[priority] ?? mtDefaultSla[priority] ?? 120;
  int num_(String key) => (numbers[key] ?? mtDefaultNumbers[key] ?? 0).toInt();

  int get assignHours => num_('assign_hours');
  int get holdDays => num_('hold_days');
  int get confirmDays => num_('confirm_days');
  int get soonHours => num_('soon_hours');
  int get repeatCount => num_('repeat_count');
  int get repeatDays => num_('repeat_days');
  int get planLeadDays => num_('plan_lead_days');

  factory MtSettings.fromRows(List<Map<String, dynamic>> rows) {
    final sla = Map<String, int>.from(mtDefaultSla);
    final nums = Map<String, num>.from(mtDefaultNumbers);
    for (final r in rows) {
      final k = _s(r['key']);
      final v = r['value'];
      if (k == 'sla_hours' && v is Map) {
        for (final p in mtDefaultSla.keys) {
          if (v[p] is num) sla[p] = (v[p] as num).toInt();
        }
      } else if (nums.containsKey(k) && v is num) {
        nums[k] = v;
      }
    }
    return MtSettings(sla: sla, numbers: nums);
  }
}

class MtRequest {
  const MtRequest({
    required this.id,
    required this.reqNo,
    required this.title,
    this.description = '',
    this.category = 'other',
    this.priority = 'normal',
    this.status = 'new',
    this.source = 'report',
    this.planId,
    this.assetId,
    this.assetTag = '',
    this.assetName = '',
    this.assetHeld = false,
    this.locationId,
    this.placeNote = '',
    this.reporterId,
    this.reporterName = '',
    this.reporterDept = '',
    this.reporterPhone = '',
    this.assigneeId,
    this.assigneeName = '',
    this.vendor = '',
    this.reportedAt,
    this.assignedAt,
    this.startedAt,
    this.onHoldAt,
    this.holdReason = '',
    this.doneAt,
    this.closedAt,
    this.dueAt,
    this.resolution = '',
    this.rejectReason = '',
    this.rating,
    this.ratingNote = '',
    this.updatedAt,
  });

  final String id, reqNo, title, description, category, priority, status, source;
  final String? planId, assetId, locationId, reporterId, assigneeId;
  final String assetTag, assetName, placeNote, reporterName, reporterDept, reporterPhone, assigneeName, vendor;
  final String holdReason, resolution, rejectReason, ratingNote;
  final bool assetHeld;
  final DateTime? reportedAt, assignedAt, startedAt, onHoldAt, doneAt, closedAt, dueAt, updatedAt;
  final int? rating;

  factory MtRequest.fromMap(Map<String, dynamic> m) => MtRequest(
        id: _s(m['id']),
        reqNo: _s(m['req_no']),
        title: _s(m['title']),
        description: _s(m['description']),
        category: _s(m['category']),
        priority: _s(m['priority']),
        status: _s(m['status']),
        source: _s(m['source']),
        planId: _id(m['plan_id']),
        assetId: _id(m['asset_id']),
        assetTag: _s(m['asset_tag']),
        assetName: _s(m['asset_name']),
        assetHeld: m['asset_held'] == true,
        locationId: _id(m['location_id']),
        placeNote: _s(m['place_note']),
        reporterId: _id(m['reporter_id']),
        reporterName: _s(m['reporter_name']),
        reporterDept: _s(m['reporter_dept']),
        reporterPhone: _s(m['reporter_phone']),
        assigneeId: _id(m['assignee_id']),
        assigneeName: _s(m['assignee_name']),
        vendor: _s(m['vendor']),
        reportedAt: _d(m['reported_at']),
        assignedAt: _d(m['assigned_at']),
        startedAt: _d(m['started_at']),
        onHoldAt: _d(m['on_hold_at']),
        holdReason: _s(m['hold_reason']),
        doneAt: _d(m['done_at']),
        closedAt: _d(m['closed_at']),
        dueAt: _d(m['due_at']),
        resolution: _s(m['resolution']),
        rejectReason: _s(m['reject_reason']),
        rating: m['rating'] is num ? (m['rating'] as num).toInt() : null,
        ratingNote: _s(m['rating_note']),
        updatedAt: _d(m['updated_at']),
      );

  /// بلاغ مفتوح (لم يُنجَز ولم يُغلق ولم يُرفض ولم يُلغَ).
  bool get isOpen => const {'new', 'assigned', 'in_progress', 'on_hold'}.contains(status);

  /// يجري عليه موعده المستهدف (المعلّق لا يُحتسب).
  bool get isRunning => const {'new', 'assigned', 'in_progress'}.contains(status);

  bool get isPlan => source == 'plan';

  bool isOverdue(DateTime now) => isRunning && dueAt != null && dueAt!.isBefore(now);

  /// مَن يُنفّذه: الفني أو الجهة الخارجية.
  String get executor => assigneeName.isNotEmpty ? assigneeName : vendor;

  /// الأصل نصاً.
  String get assetText => assetTag.isEmpty ? '' : '$assetTag — $assetName';

  /// المدة من الرفع إلى الإنجاز (أو إلى الآن إن لم يُنجَز).
  Duration age(DateTime now) => (doneAt ?? now).difference(reportedAt ?? now);

  bool matches(String q) {
    if (q.isEmpty) return true;
    final n = q.toLowerCase();
    return reqNo.toLowerCase().contains(n) ||
        title.contains(q) ||
        description.contains(q) ||
        assetTag.toLowerCase().contains(n) ||
        assetName.contains(q) ||
        reporterName.contains(q) ||
        executor.contains(q);
  }
}

class MtEvent {
  const MtEvent({required this.id, required this.requestId, required this.kind, this.at, this.byUser, this.note = '', this.data = const {}});

  final int id;
  final String requestId, kind, note;
  final String? byUser;
  final DateTime? at;
  final Map<String, dynamic> data;

  factory MtEvent.fromMap(Map<String, dynamic> m) => MtEvent(
        id: _i(m['id']),
        requestId: _s(m['request_id']),
        kind: _s(m['kind']),
        at: _d(m['at']),
        byUser: _id(m['by_user']),
        note: _s(m['note']),
        data: m['data'] is Map ? Map<String, dynamic>.from(m['data'] as Map) : const {},
      );
}

class MtPlan {
  const MtPlan({
    required this.id,
    required this.planNo,
    required this.title,
    this.category = 'other',
    this.assetId,
    this.assetTag = '',
    this.assetName = '',
    this.locationId,
    this.placeNote = '',
    this.intervalUnit = 'month',
    this.intervalCount = 1,
    this.startDate,
    this.seq = 0,
    this.nextDue,
    this.lastDone,
    this.leadDays,
    this.priority = 'normal',
    this.assigneeId,
    this.vendor = '',
    this.checklist = '',
    this.active = true,
  });

  final String id, planNo, title, category, assetTag, assetName, placeNote, intervalUnit, priority, vendor, checklist;
  final String? assetId, locationId, assigneeId;
  final int intervalCount, seq;
  final int? leadDays;
  final DateTime? startDate, nextDue, lastDone;
  final bool active;

  factory MtPlan.fromMap(Map<String, dynamic> m) => MtPlan(
        id: _s(m['id']),
        planNo: _s(m['plan_no']),
        title: _s(m['title']),
        category: _s(m['category']),
        assetId: _id(m['asset_id']),
        assetTag: _s(m['asset_tag']),
        assetName: _s(m['asset_name']),
        locationId: _id(m['location_id']),
        placeNote: _s(m['place_note']),
        intervalUnit: _s(m['interval_unit']),
        intervalCount: _i(m['interval_count']),
        startDate: _day(m['start_date']),
        seq: _i(m['seq']),
        nextDue: _day(m['next_due']),
        lastDone: _day(m['last_done']),
        leadDays: m['lead_days'] is num ? (m['lead_days'] as num).toInt() : null,
        priority: _s(m['priority']),
        assigneeId: _id(m['assignee_id']),
        vendor: _s(m['vendor']),
        checklist: _s(m['checklist']),
        active: m['active'] != false,
      );

  /// «كل 3 أشهر».
  String get intervalText {
    final n = intervalCount;
    final u = switch (intervalUnit) {
      'day' => n == 1 ? 'يوم' : (n == 2 ? 'يومين' : (n <= 10 ? 'أيام' : 'يوماً')),
      'week' => n == 1 ? 'أسبوع' : (n == 2 ? 'أسبوعين' : (n <= 10 ? 'أسابيع' : 'أسبوعاً')),
      'month' => n == 1 ? 'شهر' : (n == 2 ? 'شهرين' : (n <= 10 ? 'أشهر' : 'شهراً')),
      _ => n == 1 ? 'سنة' : (n == 2 ? 'سنتين' : (n <= 10 ? 'سنوات' : 'سنة')),
    };
    return (n == 1 || n == 2) ? 'كل $u' : 'كل $n $u';
  }

  /// أيام التنبيه المسبق الفعلية.
  int leadFor(MtSettings s) => leadDays ?? s.planLeadDays;

  /// الأيام إلى الموعد القادم (سالبة إن فات).
  int? daysToDue(DateTime today) => nextDue?.difference(DateTime(today.year, today.month, today.day)).inDays;
}

class MtTechnician {
  const MtTechnician({
    required this.employeeId,
    required this.name,
    this.empNo = '',
    this.phone = '',
    this.trade = 'general',
    this.active = true,
    this.note = '',
    this.hasAccount = false,
  });

  final String employeeId, name, empNo, phone, trade, note;
  final bool active, hasAccount;

  factory MtTechnician.fromMap(Map<String, dynamic> m) => MtTechnician(
        employeeId: _s(m['employee_id']),
        name: _s(m['name']),
        empNo: _s(m['emp_no']),
        phone: _s(m['phone']),
        trade: _s(m['trade']),
        active: m['active'] != false,
        note: _s(m['note']),
        hasAccount: m['has_account'] == true,
      );
}

/// أصل في قائمة اختيار الأصل لأهل القسم.
class MtAssetRef {
  const MtAssetRef({required this.id, required this.tag, required this.name, this.status = '', this.locationId, this.warrantyUntil});

  final String id, tag, name, status;
  final String? locationId;
  final DateTime? warrantyUntil;

  factory MtAssetRef.fromMap(Map<String, dynamic> m) => MtAssetRef(
        id: _s(m['id']),
        tag: _s(m['tag']),
        name: _s(m['name']),
        status: _s(m['status']),
        locationId: _id(m['location_id']),
        warrantyUntil: _day(m['warranty_until']),
      );
}

class MtLocation {
  const MtLocation({required this.id, required this.name, this.parentId, this.kind = ''});

  final String id, name, kind;
  final String? parentId;

  factory MtLocation.fromMap(Map<String, dynamic> m) =>
      MtLocation(id: _s(m['id']), name: _s(m['name']), parentId: _id(m['parent_id']), kind: _s(m['kind']));
}

class MtEmployeeRef {
  const MtEmployeeRef({required this.id, required this.name, this.empNo = ''});

  final String id, name, empNo;

  factory MtEmployeeRef.fromMap(Map<String, dynamic> m) => MtEmployeeRef(id: _s(m['id']), name: _s(m['name']), empNo: _s(m['emp_no']));
}

class MtAlert {
  const MtAlert({required this.kind, required this.severity, required this.refKind, required this.refId, required this.title, this.detail = '', this.since});

  final String kind, severity, refKind, title, detail;
  final String refId;
  final DateTime? since;

  bool get isCritical => severity == 'critical';
  bool get isRequest => refKind == 'request';

  factory MtAlert.fromMap(Map<String, dynamic> m) => MtAlert(
        kind: _s(m['kind']),
        severity: _s(m['severity']),
        refKind: _s(m['ref_kind']),
        refId: _s(m['ref_id']),
        title: _s(m['title']),
        detail: _s(m['detail']),
        since: _d(m['since']),
      );
}

/// بيانات القسم كلها.
class MaintenanceData {
  const MaintenanceData({
    this.requests = const [],
    this.plans = const [],
    this.technicians = const [],
    this.settings = const MtSettings(),
    this.locations = const [],
    this.assets = const [],
    this.employees = const [],
    this.alerts = const [],
  });

  factory MaintenanceData.empty() => const MaintenanceData();

  final List<MtRequest> requests;
  final List<MtPlan> plans;
  final List<MtTechnician> technicians;
  final MtSettings settings;
  final List<MtLocation> locations;
  final List<MtAssetRef> assets;
  final List<MtEmployeeRef> employees;
  final List<MtAlert> alerts;

  MtRequest? request(String? id) {
    for (final r in requests) {
      if (r.id == id) return r;
    }
    return null;
  }

  MtPlan? plan(String? id) {
    for (final p in plans) {
      if (p.id == id) return p;
    }
    return null;
  }

  MtTechnician? technician(String? employeeId) {
    for (final t in technicians) {
      if (t.employeeId == employeeId) return t;
    }
    return null;
  }

  /// الفنيون الفعّالون.
  List<MtTechnician> get activeTechnicians => [for (final t in technicians) if (t.active) t];

  /// موقع بمساره من الجذر («المبنى · الطابق · الغرفة»).
  String locationPath(String? id) {
    final names = <String>[];
    var cur = id;
    var guard = 0;
    while (cur != null && guard++ < 8) {
      MtLocation? l;
      for (final x in locations) {
        if (x.id == cur) l = x;
      }
      if (l == null) break;
      names.insert(0, l.name);
      cur = l.parentId;
    }
    return names.join(' · ');
  }

  List<MtRequest> get open => [for (final r in requests) if (r.isOpen) r];

  List<MtRequest> overdue(DateTime now) => [for (final r in requests) if (r.isOverdue(now)) r];

  List<MtRequest> get unassigned => [for (final r in requests) if (r.status == 'new') r];

  List<MtRequest> get awaitingConfirm => [for (final r in requests) if (r.status == 'done') r];

  /// بلاغات فني بعينه (غير المنتهية).
  List<MtRequest> openOf(String? employeeId) => [for (final r in requests) if (r.isOpen && r.assigneeId == employeeId) r];

  /// بلاغات رفعها هذا الحساب.
  List<MtRequest> reportedBy(String? userId) => [for (final r in requests) if (r.reporterId == userId) r];

  /// الخطط التي حان أو قرب موعدها خلال أيام.
  List<MtPlan> plansDue(DateTime today, int days) =>
      [for (final p in plans) if (p.active && (p.daysToDue(today) ?? 9999) <= days) p];

  /// عدد البلاغات بحسب الحالة.
  Map<String, int> countByStatus() {
    final m = <String, int>{};
    for (final r in requests) {
      m[r.status] = (m[r.status] ?? 0) + 1;
    }
    return m;
  }

  /// متوسط التقييم (من 1 إلى 5) للمقيَّمة، أو null.
  double? get avgRating {
    final rated = [for (final r in requests) if (r.rating != null) r.rating!];
    if (rated.isEmpty) return null;
    return rated.fold<int>(0, (a, b) => a + b) / rated.length;
  }

  /// نسبة المنجَز في موعده من البلاغات المنجَزة والمغلقة (null إن لم يوجد).
  double? get onTimeRate {
    final done = [for (final r in requests) if ((r.status == 'done' || r.status == 'closed') && r.doneAt != null && r.dueAt != null) r];
    if (done.isEmpty) return null;
    return done.where((r) => !r.doneAt!.isAfter(r.dueAt!)).length / done.length;
  }

  /// متوسط ساعات المعالجة من الرفع إلى الإنجاز.
  double? get avgHours {
    final done = [for (final r in requests) if (r.doneAt != null && r.reportedAt != null) r];
    if (done.isEmpty) return null;
    return done.fold<double>(0, (a, r) => a + r.doneAt!.difference(r.reportedAt!).inMinutes / 60) / done.length;
  }

  /// أعلى الأصول أعطالاً: (الرقم، الاسم، العدد).
  List<(String, String, int)> topAssets([int n = 5]) {
    final c = <String, (String, int)>{};
    for (final r in requests) {
      if (r.assetTag.isEmpty || r.isPlan) continue;
      final cur = c[r.assetTag];
      c[r.assetTag] = (r.assetName, (cur?.$2 ?? 0) + 1);
    }
    final l = [for (final e in c.entries) (e.key, e.value.$1, e.value.$2)]..sort((a, b) => b.$3.compareTo(a.$3));
    return l.take(n).toList();
  }
}

/// الوقت المتبقي أو المتجاوز نصاً («بعد 3 ساعات» / «متأخر يومين»).
String mtDueText(DateTime? due, DateTime now) {
  if (due == null) return '';
  final diff = due.difference(now);
  final late = diff.isNegative;
  final h = diff.abs().inHours;
  final d = diff.abs().inDays;
  final span = d >= 2 ? '$d أيام' : (d == 1 ? 'يوم' : (h >= 1 ? '$h ساعة' : 'أقل من ساعة'));
  return late ? 'متأخر $span' : 'بعد $span';
}
