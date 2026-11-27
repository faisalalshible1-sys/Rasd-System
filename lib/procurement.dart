// =====================================================================
// قسم المشتريات (الإصدار 1.10.0، الترحيل 41): نماذج البيانات والتنبيهات.
//
// دورة الطلب: مسودة ← مقدَّم ← مراجَع (مدير المخازن يحدد المتاح ويلبّي من المخزون) ← معتمَد (المدير)
// ← مأمور (أمر شراء من عرض فائز) ← مستلَم جزئياً ← مستلَم. وإن لُبّي كله من المخزون أُغلق «مكتفى من المخزون».
// الكمية المطلوب شراؤها للبند = الكمية − المُلبّى من المخزون. وإجمالي الأمر = مجموع (كمية الشراء × سعر الوحدة).
// التنبيهات تُحسب هنا من البيانات ومدد الإعدادات (لا مُجدول في الخادم).
// =====================================================================

String _s(Object? v) => v == null ? '' : '$v';
String? _id(Object? v) => v == null || '$v'.isEmpty ? null : '$v';
DateTime? _d(Object? v) => v == null ? null : DateTime.tryParse('$v')?.toLocal();
int _i(Object? v) => v is num ? v.toInt() : int.tryParse('${v ?? ''}') ?? 0;
double _n(Object? v) => v is num ? v.toDouble() : double.tryParse('${v ?? ''}') ?? 0;

DateTime? _day(Object? v) {
  if (v == null) return null;
  final d = DateTime.tryParse('$v');
  return d == null ? null : DateTime(d.year, d.month, d.day);
}

const Map<String, String> prStatusLabels = {
  'draft': 'مسودة',
  'submitted': 'بانتظار مراجعة التوفر',
  'reviewed': 'بانتظار اعتماد المدير',
  'approved': 'معتمَد بانتظار أمر الشراء',
  'ordered': 'صدر أمر الشراء',
  'partial': 'مستلَم جزئياً',
  'received': 'مستلَم',
  'fulfilled': 'مكتفى من المخزون',
  'rejected': 'مرفوض',
  'cancelled': 'ملغى',
};

const Map<String, String> prPriorityLabels = {'low': 'منخفضة', 'normal': 'عادية', 'high': 'عالية', 'urgent': 'عاجلة'};
const List<String> prPriorityOrder = ['urgent', 'high', 'normal', 'low'];

const Map<String, String> prOrderStatusLabels = {
  'issued': 'صادر',
  'partial': 'مستلَم جزئياً',
  'received': 'مستلَم',
  'cancelled': 'ملغى',
};

const Map<String, String> prEventLabels = {
  'create': 'إنشاء الطلب',
  'update': 'تعديل',
  'submit': 'تقديم',
  'review': 'مراجعة التوفر',
  'reject': 'رفض',
  'approve': 'اعتماد',
  'decline': 'عدم اعتماد',
  'cancel': 'إلغاء',
  'quote': 'عرض سعر',
  'select': 'اختيار عرض',
  'order': 'أمر شراء',
  'order_cancel': 'إلغاء أمر الشراء',
  'receive': 'استلام',
  'comment': 'تعليق',
};

const Map<String, String> prAlertLabels = {
  'review_late': 'مراجعة التوفر متأخرة',
  'approve_late': 'اعتماد المدير متأخر',
  'order_late': 'معتمَد ولم يصدر أمره',
  'delivery_late': 'توريد متأخر',
  'needed_late': 'فات موعد الحاجة',
};

/// ترتيب عرض التنبيهات: الأشد أولاً.
const List<String> prAlertOrder = ['delivery_late', 'needed_late', 'order_late', 'approve_late', 'review_late'];

/// الإعدادات المبدئية (كما في الترحيل 41).
const Map<String, int> prDefaultSettings = {'min_quotes': 3, 'review_days': 3, 'approve_days': 3, 'grace_days': 3};

class PrSettings {
  const PrSettings({this.values = prDefaultSettings});

  final Map<String, int> values;

  int get(String k) => values[k] ?? prDefaultSettings[k] ?? 0;
  int get minQuotes => get('min_quotes');
  int get reviewDays => get('review_days');
  int get approveDays => get('approve_days');
  int get graceDays => get('grace_days');

  factory PrSettings.fromRows(List<Map<String, dynamic>> rows) {
    final v = Map<String, int>.from(prDefaultSettings);
    for (final r in rows) {
      final k = _s(r['key']);
      if (v.containsKey(k) && r['value'] is num) v[k] = (r['value'] as num).toInt();
    }
    return PrSettings(values: v);
  }
}

class PrLine {
  const PrLine({
    required this.id,
    required this.requestId,
    required this.lineNo,
    this.itemId,
    this.name = '',
    this.unitId,
    this.unitName = '',
    this.qty = 0,
    this.stockQty = 0,
    this.note = '',
  });

  final String id, requestId, name, unitName, note;
  final String? itemId, unitId;
  final int lineNo;
  final double qty, stockQty;

  /// الكمية المطلوب شراؤها بعد التلبية من المخزون.
  double get toBuy => qty - stockQty;

  factory PrLine.fromMap(Map<String, dynamic> m) => PrLine(
        id: _s(m['id']),
        requestId: _s(m['request_id']),
        lineNo: _i(m['line_no']),
        itemId: _id(m['item_id']),
        name: _s(m['name']),
        unitId: _id(m['unit_id']),
        unitName: _s(m['unit_name']),
        qty: _n(m['qty']),
        stockQty: _n(m['stock_qty']),
        note: _s(m['note']),
      );
}

class PrRequest {
  const PrRequest({
    required this.id,
    required this.reqNo,
    required this.title,
    this.reason = '',
    this.priority = 'normal',
    this.status = 'draft',
    this.neededBy,
    this.departmentId,
    this.requesterId,
    this.requesterName = '',
    this.submittedAt,
    this.reviewedAt,
    this.reviewedBy,
    this.reviewNote = '',
    this.decidedAt,
    this.decidedBy,
    this.decisionNote = '',
    this.closedAt,
    this.createdAt,
    this.updatedAt,
  });

  final String id, reqNo, title, reason, priority, status, requesterName, reviewNote, decisionNote;
  final String? departmentId, requesterId, reviewedBy, decidedBy;
  final DateTime? neededBy, submittedAt, reviewedAt, decidedAt, closedAt, createdAt, updatedAt;

  factory PrRequest.fromMap(Map<String, dynamic> m) => PrRequest(
        id: _s(m['id']),
        reqNo: _s(m['req_no']),
        title: _s(m['title']),
        reason: _s(m['reason']),
        priority: _s(m['priority']),
        status: _s(m['status']),
        neededBy: _day(m['needed_by']),
        departmentId: _id(m['department_id']),
        requesterId: _id(m['requester_id']),
        requesterName: _s(m['requester_name']),
        submittedAt: _d(m['submitted_at']),
        reviewedAt: _d(m['reviewed_at']),
        reviewedBy: _id(m['reviewed_by']),
        reviewNote: _s(m['review_note']),
        decidedAt: _d(m['decided_at']),
        decidedBy: _id(m['decided_by']),
        decisionNote: _s(m['decision_note']),
        closedAt: _d(m['closed_at']),
        createdAt: _d(m['created_at']),
        updatedAt: _d(m['updated_at']),
      );

  /// طلب جارٍ: لم يُغلق بعد.
  bool get isOpen => const {'draft', 'submitted', 'reviewed', 'approved', 'ordered', 'partial'}.contains(status);

  /// يمكن لصاحبه تعديله.
  bool get isDraft => status == 'draft';

  bool matches(String q) {
    if (q.isEmpty) return true;
    return reqNo.toLowerCase().contains(q.toLowerCase()) || title.contains(q) || requesterName.contains(q) || reason.contains(q);
  }
}

class PrQuote {
  const PrQuote({
    required this.id,
    required this.requestId,
    required this.supplierId,
    this.total = 0,
    this.deliveryDays,
    this.validUntil,
    this.note = '',
    this.selected = false,
  });

  final String id, requestId, supplierId, note;
  final double total;
  final int? deliveryDays;
  final DateTime? validUntil;
  final bool selected;

  factory PrQuote.fromMap(Map<String, dynamic> m) => PrQuote(
        id: _s(m['id']),
        requestId: _s(m['request_id']),
        supplierId: _s(m['supplier_id']),
        total: _n(m['total']),
        deliveryDays: m['delivery_days'] is num ? (m['delivery_days'] as num).toInt() : null,
        validUntil: _day(m['valid_until']),
        note: _s(m['note']),
        selected: m['selected'] == true,
      );
}

class PrOrder {
  const PrOrder({
    required this.id,
    required this.poNo,
    required this.requestId,
    required this.supplierId,
    this.quoteId,
    this.warehouseId,
    this.status = 'issued',
    this.total = 0,
    this.expectedDate,
    this.waiverNote = '',
    this.note = '',
    this.issuedAt,
    this.closedAt,
  });

  final String id, poNo, requestId, supplierId, status, waiverNote, note;
  final String? quoteId, warehouseId;
  final double total;
  final DateTime? expectedDate, issuedAt, closedAt;

  factory PrOrder.fromMap(Map<String, dynamic> m) => PrOrder(
        id: _s(m['id']),
        poNo: _s(m['po_no']),
        requestId: _s(m['request_id']),
        supplierId: _s(m['supplier_id']),
        quoteId: _id(m['quote_id']),
        warehouseId: _id(m['warehouse_id']),
        status: _s(m['status']),
        total: _n(m['total']),
        expectedDate: _day(m['expected_date']),
        waiverNote: _s(m['waiver_note']),
        note: _s(m['note']),
        issuedAt: _d(m['issued_at']),
        closedAt: _d(m['closed_at']),
      );

  /// أمر قائم ينتظر استلاماً.
  bool get isLive => status == 'issued' || status == 'partial';
}

class PrOrderLine {
  const PrOrderLine({
    required this.id,
    required this.orderId,
    required this.lineId,
    required this.itemId,
    required this.unitId,
    this.qty = 0,
    this.unitPrice = 0,
    this.received = 0,
  });

  final String id, orderId, lineId, itemId, unitId;
  final double qty, unitPrice, received;

  double get remaining => qty - received;
  double get amount => (qty * unitPrice * 1000).round() / 1000;

  factory PrOrderLine.fromMap(Map<String, dynamic> m) => PrOrderLine(
        id: _s(m['id']),
        orderId: _s(m['order_id']),
        lineId: _s(m['line_id']),
        itemId: _s(m['item_id']),
        unitId: _s(m['unit_id']),
        qty: _n(m['qty']),
        unitPrice: _n(m['unit_price']),
        received: _n(m['received']),
      );
}

class PrSupplier {
  const PrSupplier({
    required this.id,
    required this.name,
    this.contact = '',
    this.phone = '',
    this.email = '',
    this.address = '',
    this.note = '',
    this.active = true,
  });

  final String id, name, contact, phone, email, address, note;
  final bool active;

  factory PrSupplier.fromMap(Map<String, dynamic> m) => PrSupplier(
        id: _s(m['id']),
        name: _s(m['name']),
        contact: _s(m['contact']),
        phone: _s(m['phone']),
        email: _s(m['email']),
        address: _s(m['address']),
        note: _s(m['note']),
        active: m['active'] != false,
      );
}

class PrEvent {
  const PrEvent({required this.id, required this.requestId, required this.kind, this.at, this.byUser, this.note = '', this.data = const {}});

  final int id;
  final String requestId, kind, note;
  final String? byUser;
  final DateTime? at;
  final Map<String, dynamic> data;

  factory PrEvent.fromMap(Map<String, dynamic> m) => PrEvent(
        id: _i(m['id']),
        requestId: _s(m['request_id']),
        kind: _s(m['kind']),
        at: _d(m['at']),
        byUser: _id(m['by_user']),
        note: _s(m['note']),
        data: m['data'] is Map ? Map<String, dynamic>.from(m['data'] as Map) : const {},
      );
}

class PrReceipt {
  const PrReceipt({required this.id, required this.orderId, this.receivedAt, this.invoiceNo = '', this.note = '', this.docId, this.assetCount = 0, this.lines = const []});

  final String id, orderId, invoiceNo, note;
  final String? docId;
  final DateTime? receivedAt;
  final int assetCount;
  final List<Map<String, dynamic>> lines;

  factory PrReceipt.fromMap(Map<String, dynamic> m) => PrReceipt(
        id: _s(m['id']),
        orderId: _s(m['order_id']),
        receivedAt: _d(m['received_at']),
        invoiceNo: _s(m['invoice_no']),
        note: _s(m['note']),
        docId: _id(m['doc_id']),
        assetCount: m['asset_ids'] is List ? (m['asset_ids'] as List).length : 0,
        lines: m['lines'] is List ? [for (final x in m['lines'] as List) if (x is Map) Map<String, dynamic>.from(x)] : const [],
      );
}

/// صنف للاختيار (من pr_lookups): المتاح للمراجعين وحدهم.
class PrItemRef {
  const PrItemRef({required this.id, required this.code, required this.name, this.kind = 'consumable', this.baseUnitId, this.available});

  final String id, code, name, kind;
  final String? baseUnitId;
  final double? available;

  bool get isAsset => kind == 'asset';

  factory PrItemRef.fromMap(Map<String, dynamic> m) => PrItemRef(
        id: _s(m['id']),
        code: _s(m['code']),
        name: _s(m['name']),
        kind: _s(m['kind']),
        baseUnitId: _id(m['base_unit_id']),
        available: m['available'] is num ? (m['available'] as num).toDouble() : null,
      );
}

class PrUnitRef {
  const PrUnitRef({required this.id, required this.name});

  final String id, name;

  factory PrUnitRef.fromMap(Map<String, dynamic> m) => PrUnitRef(id: _s(m['id']), name: _s(m['name']));
}

class PrItemUnit {
  const PrItemUnit({required this.itemId, required this.unitId, this.factor = 1});

  final String itemId, unitId;
  final double factor;

  factory PrItemUnit.fromMap(Map<String, dynamic> m) => PrItemUnit(itemId: _s(m['item_id']), unitId: _s(m['unit_id']), factor: _n(m['factor']));
}

/// تنبيه محسوب: نوعه وعنصره (طلب أو أمر) ووصفه.
class PrAlert {
  const PrAlert({required this.kind, required this.requestId, required this.title, required this.detail, this.orderId, this.days = 0});

  final String kind, requestId, title, detail;
  final String? orderId;

  /// عدد أيام التأخر.
  final int days;

  bool get isCritical => kind == 'delivery_late' || kind == 'needed_late';
}

class ProcurementData {
  const ProcurementData({
    this.requests = const [],
    this.lines = const [],
    this.quotes = const [],
    this.orders = const [],
    this.orderLines = const [],
    this.suppliers = const [],
    this.settings = const PrSettings(),
    this.items = const [],
    this.units = const [],
    this.itemUnits = const [],
    this.departments = const [],
    this.warehouses = const [],
  });

  factory ProcurementData.empty() => const ProcurementData();

  final List<PrRequest> requests;
  final List<PrLine> lines;
  final List<PrQuote> quotes;
  final List<PrOrder> orders;
  final List<PrOrderLine> orderLines;
  final List<PrSupplier> suppliers;
  final PrSettings settings;
  final List<PrItemRef> items;
  final List<PrUnitRef> units;
  final List<PrItemUnit> itemUnits;
  final List<(String, String)> departments;
  final List<(String, String)> warehouses;

  PrRequest? request(String? id) {
    for (final r in requests) {
      if (r.id == id) return r;
    }
    return null;
  }

  PrOrder? order(String? id) {
    for (final o in orders) {
      if (o.id == id) return o;
    }
    return null;
  }

  PrSupplier? supplier(String? id) {
    for (final s in suppliers) {
      if (s.id == id) return s;
    }
    return null;
  }

  PrItemRef? item(String? id) {
    for (final i in items) {
      if (i.id == id) return i;
    }
    return null;
  }

  String unitName(String? id) {
    for (final u in units) {
      if (u.id == id) return u.name;
    }
    return '';
  }

  /// عدد الوحدات الأساسية في وحدة الصنف (1 للأساسية).
  double factorOf(String itemId, String? unitId) {
    final it = item(itemId);
    if (it == null || unitId == null || unitId == it.baseUnitId) return 1;
    for (final x in itemUnits) {
      if (x.itemId == itemId && x.unitId == unitId) return x.factor == 0 ? 1 : x.factor;
    }
    return 1;
  }

  /// المتاح في المخازن مقيساً بوحدة البند (لا يعرفه إلا المراجعون).
  double? availableIn(String itemId, String? unitId) {
    final a = item(itemId)?.available;
    return a == null ? null : a / factorOf(itemId, unitId);
  }

  /// وحدات الصنف: الأساسية ثم المعرَّفة له.
  List<PrUnitRef> unitsOf(String itemId) {
    final it = item(itemId);
    final ids = <String>{if (it?.baseUnitId != null) it!.baseUnitId!, for (final x in itemUnits) if (x.itemId == itemId) x.unitId};
    return [for (final u in units) if (ids.contains(u.id)) u];
  }

  List<PrLine> linesOf(String requestId) => [for (final l in lines) if (l.requestId == requestId) l]..sort((a, b) => a.lineNo.compareTo(b.lineNo));

  List<PrQuote> quotesOf(String requestId) => [for (final q in quotes) if (q.requestId == requestId) q]..sort((a, b) => a.total.compareTo(b.total));

  /// الأمر القائم للطلب (غير الملغى)، أو آخر ما صدر.
  PrOrder? orderOfRequest(String requestId) {
    PrOrder? last;
    for (final o in orders) {
      if (o.requestId != requestId) continue;
      if (o.status != 'cancelled') return o;
      last = o;
    }
    return last;
  }

  List<PrOrderLine> orderLinesOf(String orderId) => [for (final l in orderLines) if (l.orderId == orderId) l];

  PrLine? line(String id) {
    for (final l in lines) {
      if (l.id == id) return l;
    }
    return null;
  }

  List<PrRequest> requestedBy(String? userId) => [for (final r in requests) if (userId != null && r.requesterId == userId) r];

  /// الطلبات المنتظرة إجراءً من مدير المخازن.
  List<PrRequest> get awaitingReview => [for (final r in requests) if (r.status == 'submitted') r];

  /// الطلبات المنتظرة اعتماد المدير.
  List<PrRequest> get awaitingDecision => [for (final r in requests) if (r.status == 'reviewed') r];

  /// معتمدة بلا أمر.
  List<PrRequest> get awaitingOrder => [for (final r in requests) if (r.status == 'approved') r];

  /// أوامر تنتظر استلاماً.
  List<PrOrder> get liveOrders => [for (final o in orders) if (o.isLive) o];

  List<PrRequest> get open => [for (final r in requests) if (r.isOpen && r.status != 'draft') r];

  /// قيمة الأوامر القائمة ولم يُستلَم منها بعد (تقريبية: الإجمالي − المستلَم بسعر الوحدة).
  double get outstandingValue {
    var t = 0.0;
    for (final o in liveOrders) {
      for (final l in orderLinesOf(o.id)) {
        t += l.remaining * l.unitPrice;
      }
    }
    return (t * 1000).round() / 1000;
  }

  /// التنبيهات من البيانات ومدد الإعدادات.
  List<PrAlert> alerts(DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    int daysSince(DateTime? from, int grace) {
      if (from == null) return 0;
      final d = today.difference(DateTime(from.year, from.month, from.day)).inDays - grace;
      return d;
    }

    final out = <PrAlert>[];
    for (final r in requests) {
      if (r.status == 'submitted') {
        final d = daysSince(r.submittedAt, settings.reviewDays);
        if (d >= 0) out.add(PrAlert(kind: 'review_late', requestId: r.id, title: r.title, detail: '${r.reqNo} · مقدَّم منذ ${d + settings.reviewDays} يوماً', days: d));
      } else if (r.status == 'reviewed') {
        final d = daysSince(r.reviewedAt, settings.approveDays);
        if (d >= 0) out.add(PrAlert(kind: 'approve_late', requestId: r.id, title: r.title, detail: '${r.reqNo} · ينتظر الاعتماد منذ ${d + settings.approveDays} يوماً', days: d));
      } else if (r.status == 'approved') {
        final d = daysSince(r.decidedAt, settings.graceDays);
        if (d >= 0) out.add(PrAlert(kind: 'order_late', requestId: r.id, title: r.title, detail: '${r.reqNo} · معتمَد منذ ${d + settings.graceDays} يوماً بلا أمر شراء', days: d));
      }
      if (r.isOpen && r.status != 'draft' && r.neededBy != null && r.neededBy!.isBefore(today) && r.status != 'received') {
        out.add(PrAlert(kind: 'needed_late', requestId: r.id, title: r.title, detail: '${r.reqNo} · فات موعد الحاجة بـ ${today.difference(r.neededBy!).inDays} يوماً', days: today.difference(r.neededBy!).inDays));
      }
    }
    for (final o in liveOrders) {
      final e = o.expectedDate;
      if (e == null) continue;
      final d = today.difference(e).inDays - settings.graceDays;
      if (d >= 0) {
        final r = request(o.requestId);
        out.add(PrAlert(
            kind: 'delivery_late',
            requestId: o.requestId,
            orderId: o.id,
            title: r?.title ?? o.poNo,
            detail: '${o.poNo} · تأخر التوريد ${d + settings.graceDays} يوماً عن الموعد المتوقع',
            days: d));
      }
    }
    out.sort((a, b) {
      final ka = prAlertOrder.indexOf(a.kind), kb = prAlertOrder.indexOf(b.kind);
      return ka != kb ? ka.compareTo(kb) : b.days.compareTo(a.days);
    });
    return out;
  }
}
