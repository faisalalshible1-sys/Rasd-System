import 'assets.dart' show StAsset;
import 'stores.dart';

// =====================================================================
// الجرد الدوري والتقارير الأساسية في قسم المخازن (الإصدار 1.11.0، الترحيل 42).
//
// جلسة الجرد: مفتوحة (عدّ) ← مقدَّمة (بانتظار القرار) ← مغلقة (اعتُمدت وتولّدت تسويتها) أو ملغاة.
// فرق البند عند الاعتماد = المعدود − الرصيد الفعلي وقتها (يحسبه الخادم)، وهنا نعرض الفرق المتوقع بالصيغة نفسها.
// التقارير تُحسب هنا من المستندات المرحَّلة والأرصدة المحمّلة (لا جداول جديدة ولا مُجدول).
// =====================================================================

String _s(Object? v) => v == null ? '' : '$v';
String? _id(Object? v) => v == null || '$v'.isEmpty ? null : '$v';
DateTime? _d(Object? v) => v == null ? null : DateTime.tryParse('$v')?.toLocal();
double _n(Object? v) => v is num ? v.toDouble() : double.tryParse('${v ?? ''}') ?? 0;
double? _nn(Object? v) => v == null ? null : _n(v);

const Map<String, String> stCountStatusLabels = {
  'open': 'قيد العدّ',
  'submitted': 'بانتظار القرار',
  'closed': 'مغلقة',
  'cancelled': 'ملغاة',
};

/// الأيام المبدئية لاعتبار الصنف راكداً (لا صرف مرحَّل له خلالها)، ويغيّرها المستخدم في صفحة التقارير.
const int stDefaultStagnantDays = 90;

/// الأيام التي يُحسب عليها معدل الاستهلاك اليومي لتغطية المخزون.
const int stCoverWindowDays = 90;

/// خيارات الأيام في صفحة التقارير.
const List<int> stReportDayOptions = [30, 60, 90, 180, 365];

class StCount {
  const StCount({
    required this.id,
    required this.countNo,
    required this.warehouseId,
    this.categoryId,
    this.status = 'open',
    this.blind = true,
    this.note = '',
    this.decisionNote = '',
    this.adjustDocId,
    this.createdAt,
    this.createdBy,
    this.submittedAt,
    this.submittedBy,
    this.decidedAt,
    this.decidedBy,
  });

  factory StCount.fromMap(Map<String, dynamic> m) => StCount(
        id: _s(m['id']),
        countNo: _s(m['count_no']),
        warehouseId: _s(m['warehouse_id']),
        categoryId: _id(m['category_id']),
        status: _s(m['status']).isEmpty ? 'open' : _s(m['status']),
        blind: m['blind'] != false,
        note: _s(m['note']),
        decisionNote: _s(m['decision_note']),
        adjustDocId: _id(m['adjust_doc_id']),
        createdAt: _d(m['created_at']),
        createdBy: _id(m['created_by']),
        submittedAt: _d(m['submitted_at']),
        submittedBy: _id(m['submitted_by']),
        decidedAt: _d(m['decided_at']),
        decidedBy: _id(m['decided_by']),
      );

  final String id;
  final String countNo;
  final String warehouseId;
  final String? categoryId;
  final String status;

  /// إخفاء الرصيد الدفتري أثناء العدّ (تيسير في الشاشة وليس ضابطاً أمنياً).
  final bool blind;
  final String note;
  final String decisionNote;
  final String? adjustDocId;
  final DateTime? createdAt;
  final String? createdBy;
  final DateTime? submittedAt;
  final String? submittedBy;
  final DateTime? decidedAt;
  final String? decidedBy;

  bool get isOpen => status == 'open';
  bool get isSubmitted => status == 'submitted';
  bool get isClosed => status == 'closed';
  bool get isCancelled => status == 'cancelled';

  /// قائمة (مفتوحة أو مقدَّمة): جلسة واحدة منها لكل مخزن.
  bool get isLive => isOpen || isSubmitted;

  String get statusLabel => stCountStatusLabels[status] ?? status;
}

class StCountLine {
  const StCountLine({
    required this.id,
    required this.countId,
    required this.itemId,
    this.systemQty = 0,
    this.countedQty,
    this.expiryDate,
    this.batchNo = '',
    this.note = '',
    this.variance,
  });

  factory StCountLine.fromMap(Map<String, dynamic> m) => StCountLine(
        id: _s(m['id']),
        countId: _s(m['count_id']),
        itemId: _s(m['item_id']),
        systemQty: _n(m['system_qty']),
        countedQty: _nn(m['counted_qty']),
        expiryDate: m['expiry_date'] == null ? null : DateTime.tryParse('${m['expiry_date']}'),
        batchNo: _s(m['batch_no']),
        note: _s(m['note']),
        variance: _nn(m['variance']),
      );

  final String id;
  final String countId;
  final String itemId;

  /// الرصيد الدفتري وقت بدء الجلسة، بالوحدة الأساسية.
  final double systemQty;

  /// المعدود بالوحدة الأساسية؛ null لم يُعدّ بعد.
  final double? countedQty;
  final DateTime? expiryDate;
  final String batchNo;
  final String note;

  /// الفرق المقيَّد عند الاعتماد (المعدود − الرصيد وقتها).
  final double? variance;

  bool get counted => countedQty != null;
}

class StocktakingData {
  StocktakingData({this.counts = const [], this.lines = const []}) {
    for (final c in counts) {
      _count[c.id] = c;
    }
    for (final l in lines) {
      (_lines[l.countId] ??= []).add(l);
    }
  }

  factory StocktakingData.empty() => StocktakingData();

  final List<StCount> counts;
  final List<StCountLine> lines;

  final Map<String, StCount> _count = {};
  final Map<String, List<StCountLine>> _lines = {};

  StCount? count(String? id) => id == null ? null : _count[id];
  List<StCountLine> linesOf(String countId) => _lines[countId] ?? const [];

  /// الجلسة القائمة (مفتوحة أو مقدَّمة) لمخزن، إن وُجدت.
  StCount? liveOf(String warehouseId) {
    for (final c in counts) {
      if (c.warehouseId == warehouseId && c.isLive) return c;
    }
    return null;
  }

  List<StCount> get live => [for (final c in counts) if (c.isLive) c];
  int get awaitingDecision => counts.where((c) => c.isSubmitted).length;

  /// آخر جلسة مغلقة لمخزن.
  StCount? lastClosed(String warehouseId) {
    StCount? best;
    for (final c in counts) {
      if (c.warehouseId == warehouseId && c.isClosed && (best == null || (c.decidedAt ?? DateTime(2000)).isAfter(best.decidedAt ?? DateTime(2000)))) {
        best = c;
      }
    }
    return best;
  }

  /// ملخص جلسة: عدد البنود والمعدود منها، وعدد بنود الفرق وإجمالي الزيادة والنقص (كميات بوحداتها الأساسية).
  CountSummary summary(StCount c, double Function(String itemId) onHandNow) {
    var total = 0, done = 0, diff = 0;
    var gain = 0.0, loss = 0.0;
    for (final l in linesOf(c.id)) {
      total++;
      if (!l.counted) continue;
      done++;
      final v = c.isClosed ? (l.variance ?? 0) : roundQty(l.countedQty! - onHandNow(l.itemId));
      if (v != 0) diff++;
      if (v > 0) gain += v;
      if (v < 0) loss += -v;
    }
    return CountSummary(total: total, counted: done, withVariance: diff, gain: roundQty(gain), loss: roundQty(loss));
  }
}

class CountSummary {
  const CountSummary({required this.total, required this.counted, required this.withVariance, required this.gain, required this.loss});

  final int total;
  final int counted;
  final int withVariance;
  final double gain;
  final double loss;

  bool get complete => total > 0 && counted == total;
}

// ---------------------------------------------------------------------
// التقارير: كلها من المستندات المرحَّلة والأرصدة المحمّلة.
// الاستهلاك الصافي للصنف = مجموع (−اتجاه المستند × الكمية الأساسية) على مستندات الصرف والمرتجع المرحَّلة بما فيها عكسها؛
// فالصرف يزيده والمرتجع ينقصه وعكس الصرف ينقصه. التحويل والوارد والتسوية لا تدخل فيه.
// ---------------------------------------------------------------------

DateTime _dayOnly(DateTime d) => DateTime(d.year, d.month, d.day);

extension StoresReports on StoresData {
  /// تاريخ أثر المستند المرحَّل: يوم المستند، وإلا يوم الترحيل.
  DateTime? _effectDay(StDoc d) {
    final x = d.docDate ?? d.postedAt;
    return x == null ? null : _dayOnly(x);
  }

  /// الاستهلاك الصافي لكل صنف خلال [from, to] شاملةً الطرفين.
  Map<String, double> consumption(DateTime from, DateTime to, {String? warehouseId}) {
    final f = _dayOnly(from), t = _dayOnly(to);
    final out = <String, double>{};
    for (final d in docs) {
      if (!d.isPosted || !(d.kind == 'issue' || d.kind == 'return')) continue;
      if (warehouseId != null && d.warehouseId != warehouseId) continue;
      final day = _effectDay(d);
      if (day == null || day.isBefore(f) || day.isAfter(t)) continue;
      for (final l in linesOf(d.id)) {
        out[l.itemId] = (out[l.itemId] ?? 0) - d.direction * l.baseQty;
      }
    }
    return {for (final e in out.entries) e.key: roundQty(e.value)};
  }

  /// آخر يوم صرف (مرحَّل وغير عكسي) لكل صنف.
  Map<String, DateTime> lastIssueDay() {
    final out = <String, DateTime>{};
    for (final d in docs) {
      if (!d.isPosted || d.kind != 'issue' || d.isReversal) continue;
      final day = _effectDay(d);
      if (day == null) continue;
      for (final l in linesOf(d.id)) {
        final cur = out[l.itemId];
        if (cur == null || day.isAfter(cur)) out[l.itemId] = day;
      }
    }
    return out;
  }

  /// أصناف راكدة: نشطة بها رصيد ولم يُصرف منها شيء مرحَّل خلال [days] يوماً (الأقدم صرفاً أولاً، ومن لم يُصرف قط أولاً).
  List<StagnantItem> stagnant(DateTime today, int days) {
    final last = lastIssueDay();
    final limit = _dayOnly(today).subtract(Duration(days: days));
    final out = <StagnantItem>[];
    for (final it in items) {
      if (!it.active) continue;
      final qty = onHand(it.id);
      if (qty <= 0) continue;
      final l = last[it.id];
      if (l == null || l.isBefore(limit)) {
        out.add(StagnantItem(it, qty, l, l == null ? null : _dayOnly(today).difference(l).inDays));
      }
    }
    out.sort((a, b) {
      if (a.lastIssue == null && b.lastIssue != null) return -1;
      if (a.lastIssue != null && b.lastIssue == null) return 1;
      if (a.lastIssue != null && b.lastIssue != null) {
        final c = a.lastIssue!.compareTo(b.lastIssue!);
        if (c != 0) return c;
      }
      return a.item.name.compareTo(b.item.name);
    });
    return out;
  }

  /// تغطية الصنف بالأيام = الرصيد الفعلي ÷ (استهلاك آخر [stCoverWindowDays] يوماً ÷ عدد الأيام)؛ null إن لم يُستهلك.
  double? coverDays(String itemId, DateTime today, {Map<String, double>? recent}) {
    final c = (recent ?? consumption(today.subtract(const Duration(days: stCoverWindowDays - 1)), today))[itemId] ?? 0;
    if (c <= 0) return null;
    return onHand(itemId) / (c / stCoverWindowDays);
  }

  /// صف في تقرير الحركة: الصنف وما دخل وما خرج (بحسب اتجاه المستند) وصافي الاستهلاك خلال المدة.
  List<MovementRow> movement(DateTime from, DateTime to, {String? warehouseId}) {
    final f = _dayOnly(from), t = _dayOnly(to);
    final inQ = <String, double>{}, outQ = <String, double>{}, net = <String, double>{};
    for (final d in docs) {
      if (!d.isPosted) continue;
      if (warehouseId != null && d.warehouseId != warehouseId && d.toWarehouseId != warehouseId) continue;
      // التحويل بين المخازن صافيه صفر على المنظومة كلها فلا يظهر إلا عند اختيار مخزن
      if (warehouseId == null && d.kind == 'transfer') continue;
      final day = _effectDay(d);
      if (day == null || day.isBefore(f) || day.isAfter(t)) continue;
      for (final l in linesOf(d.id)) {
        final q = l.baseQty;
        // أثر المستند على مخزنه المصدر؛ والتحويل يدخل مخزن الوجهة
        var delta = d.kind == 'adjust' ? q : d.direction * q;
        if (d.kind == 'transfer') {
          if (warehouseId != null && d.toWarehouseId == warehouseId && d.warehouseId != warehouseId) {
            delta = d.isReversal ? -q : q;
          }
        }
        if (delta > 0) {
          inQ[l.itemId] = (inQ[l.itemId] ?? 0) + delta;
        } else if (delta < 0) {
          outQ[l.itemId] = (outQ[l.itemId] ?? 0) - delta;
        }
        if (d.kind == 'issue' || d.kind == 'return') net[l.itemId] = (net[l.itemId] ?? 0) - d.direction * q;
      }
    }
    final ids = {...inQ.keys, ...outQ.keys};
    final rows = [
      for (final id in ids)
        if (item(id) != null) MovementRow(item(id)!, roundQty(inQ[id] ?? 0), roundQty(outQ[id] ?? 0), roundQty(net[id] ?? 0)),
    ];
    rows.sort((a, b) => b.consumed != a.consumed ? b.consumed.compareTo(a.consumed) : a.item.name.compareTo(b.item.name));
    return rows;
  }
}

class StagnantItem {
  const StagnantItem(this.item, this.onHand, this.lastIssue, this.daysSince);

  final StItem item;
  final double onHand;

  /// آخر صرف مرحَّل؛ null لم يُصرف قط.
  final DateTime? lastIssue;
  final int? daysSince;
}

class MovementRow {
  const MovementRow(this.item, this.received, this.issued, this.consumed);

  final StItem item;
  final double received;
  final double issued;

  /// صافي الاستهلاك (الصرف − المرتجع).
  final double consumed;
}

// ---------------------------------------------------------------------
// عمر الأصول
// ---------------------------------------------------------------------

/// فئات عمر الأصل من تاريخ الخدمة (أو الشراء): أقل من سنة، 1–3، 3–5، أكثر من 5، وغير معروف.
const List<String> assetAgeBuckets = ['lt1', 'y1_3', 'y3_5', 'gt5', 'unknown'];

const Map<String, String> assetAgeLabels = {
  'lt1': 'أقل من سنة',
  'y1_3': 'من 1 إلى 3 سنوات',
  'y3_5': 'من 3 إلى 5 سنوات',
  'gt5': 'أكثر من 5 سنوات',
  'unknown': 'بلا تاريخ',
};

/// عمر الأصل بالسنوات (أيام ÷ 365.25)؛ null إن لم يُعرف تاريخ الخدمة ولا الشراء.
double? assetAgeYears(StAsset a, DateTime today) {
  final from = a.inServiceDate ?? a.purchaseDate;
  if (from == null) return null;
  final days = _dayOnly(today).difference(_dayOnly(from)).inDays;
  return days < 0 ? 0 : days / 365.25;
}

String assetAgeBucket(StAsset a, DateTime today) {
  final y = assetAgeYears(a, today);
  if (y == null) return 'unknown';
  if (y < 1) return 'lt1';
  if (y < 3) return 'y1_3';
  if (y < 5) return 'y3_5';
  return 'gt5';
}

/// هل تجاوز الأصل عمره الافتراضي المسجَّل (بالأشهر)؟
bool assetPastLife(StAsset a, DateTime today) {
  final y = assetAgeYears(a, today);
  final life = a.lifeMonths;
  if (y == null || life == null || life <= 0) return false;
  return y * 12 > life;
}
