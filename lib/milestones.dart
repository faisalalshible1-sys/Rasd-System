// معالم المشاريع ومؤشرات الأداء (الإصدار 1.14.0، الترحيل 45).
//
// كل مؤشر دالة نقية على بيانات بسيطة ليسهل اختبارها، وتطابق معادلاتها فصل «المعالم ومؤشرات الأداء» في الدليل (الفصل 39).

import 'maintenance.dart';
import 'pm.dart' show daysBetween;
import 'procurement.dart';

/// نافذة الأحداث المنتهية التي تدخل في المؤشرات الآلية (بالأيام قبل اليوم).
const int kpiWindowDays = 90;

/// المستهدفات الثابتة للمؤشرات الآلية (نسب مئوية).
const double kpiMilestoneTarget = 80;
const double kpiProjectsTarget = 80;
const double kpiSlaTarget = 90;
const double kpiProcurementTarget = 80;
const double kpiStoresTarget = 90;

DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

DateTime? _dayOf(Object? v) {
  if (v == null) return null;
  final p = DateTime.tryParse('$v');
  return p == null ? null : DateTime(p.year, p.month, p.day);
}

/// معلم في مشروع.
class PmMilestone {
  const PmMilestone({
    required this.id,
    required this.projectId,
    required this.title,
    required this.planned,
    this.forecast,
    this.actual,
    this.status = 'pending',
    this.note = '',
    this.sort = 0,
  });

  final String id;
  final String projectId;
  final String title;
  final DateTime planned;
  final DateTime? forecast;
  final DateTime? actual;
  final String status;
  final String note;
  final int sort;

  factory PmMilestone.fromMap(Map<String, dynamic> m) => PmMilestone(
        id: '${m['id'] ?? ''}',
        projectId: '${m['project_id'] ?? ''}',
        title: '${m['title'] ?? ''}',
        planned: _dayOf(m['planned_date']) ?? DateTime.now(),
        forecast: _dayOf(m['forecast_date']),
        actual: _dayOf(m['actual_date']),
        status: '${m['status'] ?? 'pending'}',
        note: '${m['note'] ?? ''}',
        sort: (m['sort_order'] as num?)?.toInt() ?? 0,
      );

  bool get isDone => status == 'done';
  bool get isCancelled => status == 'cancelled';
  bool get isPending => status == 'pending';

  /// متأخر: لم يُنجَز وفات تاريخه المخطط قبل اليوم.
  bool isOverdue(DateTime today) => isPending && planned.isBefore(_dateOnly(today));

  /// أيام التأخر: للمنجز الفرق بين الفعلي والمخطط، وللمعلّق الفائت الفرق بين اليوم والمخطط، وإلا صفر.
  int lateDays(DateTime today) {
    if (isDone && actual != null) {
      final d = daysBetween(actual!, planned);
      return d > 0 ? d : 0;
    }
    if (isOverdue(today)) return daysBetween(today, planned);
    return 0;
  }

  /// أُنجز في موعده أو قبله.
  bool get doneOnTime => isDone && actual != null && !actual!.isAfter(planned);

  /// تاريخه المتوقع يتأخر عن المخطط وهو لم يُنجَز بعد.
  bool get slipping => isPending && forecast != null && forecast!.isAfter(planned);
}

/// تعريف مؤشر مخصص يحدده المدير.
class KpiDef {
  const KpiDef({
    required this.id,
    required this.name,
    this.unit = '',
    required this.target,
    this.higherBetter = true,
    this.active = true,
    this.note = '',
  });

  final String id;
  final String name;
  final String unit;
  final double target;
  final bool higherBetter;
  final bool active;
  final String note;

  factory KpiDef.fromMap(Map<String, dynamic> m) => KpiDef(
        id: '${m['id'] ?? ''}',
        name: '${m['name'] ?? ''}',
        unit: '${m['unit'] ?? ''}',
        target: (m['target'] as num?)?.toDouble() ?? 0,
        higherBetter: '${m['direction'] ?? 'higher'}' != 'lower',
        active: m['active'] != false,
        note: '${m['note'] ?? ''}',
      );
}

/// قيمة شهرية لمؤشر مخصص (الفترة «YYYY-MM»).
class KpiValue {
  const KpiValue({required this.id, required this.kpiId, required this.period, required this.value, this.note = ''});

  final String id;
  final String kpiId;
  final String period;
  final double value;
  final String note;

  factory KpiValue.fromMap(Map<String, dynamic> m) => KpiValue(
        id: '${m['id'] ?? ''}',
        kpiId: '${m['kpi_id'] ?? ''}',
        period: '${m['period'] ?? ''}',
        value: (m['value'] as num?)?.toDouble() ?? 0,
        note: '${m['note'] ?? ''}',
      );
}

/// نسبة تحقق مؤشر مخصص: الأعلى أفضل = القيمة ÷ المستهدف؛ الأقل أفضل = 1 إن لم تتجاوز القيمة المستهدف وإلا المستهدف ÷ القيمة.
/// null إن تعذّر الحساب (مستهدف صفر في «الأعلى أفضل»، أو قيمة غير موجبة تتجاوز مستهدفاً في «الأقل أفضل»).
double? kpiAttainment(KpiDef d, double value) {
  if (d.higherBetter) {
    if (d.target <= 0) return null;
    return value / d.target;
  }
  if (value <= d.target) return 1;
  if (value <= 0) return null;
  return d.target / value;
}

/// آخر قيمة مسجلة لمؤشر (الأحدث فترةً).
KpiValue? kpiLatest(Iterable<KpiValue> values) {
  KpiValue? best;
  for (final v in values) {
    if (best == null || v.period.compareTo(best.period) > 0) best = v;
  }
  return best;
}

/// نتيجة مؤشر آلي.
class KpiResult {
  const KpiResult({
    required this.key,
    required this.title,
    required this.section,
    required this.value,
    required this.unit,
    this.target,
    this.higherBetter = true,
    this.sample = 0,
    this.hint = '',
  });

  final String key;
  final String title;

  /// القسم الذي يعود إليه المؤشر: milestones أو projects أو maintenance أو procurement أو stores.
  final String section;
  final double? value;
  final String unit;
  final double? target;
  final bool higherBetter;

  /// حجم العيّنة (عدد العناصر التي بُني عليها المؤشر).
  final int sample;
  final String hint;

  /// null إن لم يُحسب المؤشر أو لا مستهدف له.
  bool? get met {
    if (value == null || target == null) return null;
    return higherBetter ? value! >= target! : value! <= target!;
  }
}

double _pct(int part, int whole) => whole == 0 ? 0 : part / whole * 100;

/// التزام المعالم بمواعيدها: المنجزة في موعدها ÷ (المنجزة خلال النافذة + المعلّقة الفائتة). الملغاة لا تدخل.
KpiResult kpiMilestones(List<PmMilestone> ms, DateTime today) {
  final from = DateTime(today.year, today.month, today.day - kpiWindowDays);
  var met = 0, counted = 0;
  for (final m in ms) {
    if (m.isCancelled) continue;
    if (m.isDone && m.actual != null && !m.actual!.isBefore(from)) {
      counted++;
      if (m.doneOnTime) met++;
    } else if (m.isOverdue(today)) {
      counted++;
    }
  }
  return KpiResult(
    key: 'milestones',
    title: 'التزام المعالم بمواعيدها',
    section: 'milestones',
    value: counted == 0 ? null : _pct(met, counted),
    unit: '%',
    target: kpiMilestoneTarget,
    sample: counted,
    hint: 'المنجزة في موعدها ÷ (المنجزة آخر $kpiWindowDays يوماً + المتأخرة غير المنجزة)',
  );
}

/// نسبة المشاريع الجارية المنتظمة: التي أداؤها «متقدم» أو «ضمن المسار» من الجارية التي لها قياس.
/// [perfs] قيم ProjectTrack.perf للمشاريع الجارية.
KpiResult kpiProjectsOnTrack(List<String> perfs) {
  const counted = {'ahead', 'on_track', 'slight', 'critical'};
  final rated = perfs.where(counted.contains).toList();
  final ok = rated.where((p) => p == 'ahead' || p == 'on_track').length;
  return KpiResult(
    key: 'projects_on_track',
    title: 'المشاريع الجارية المنتظمة',
    section: 'projects',
    value: rated.isEmpty ? null : _pct(ok, rated.length),
    unit: '%',
    target: kpiProjectsTarget,
    sample: rated.length,
    hint: 'المتقدمة أو ضمن المسار ÷ الجارية التي لها قياس',
  );
}

/// متوسط SPI للجارية موزوناً بقيمة العقد (بالتساوي إن لم تُسجَّل القيم). [items] أزواج (SPI، الوزن).
/// المستهدف [spiOk] حد «ضمن المسار» من إعدادات المتابعة.
KpiResult kpiProjectsSpi(List<({double spi, double weight})> items, double spiOk) {
  final anyWeight = items.any((i) => i.weight > 0);
  var s = 0.0, w = 0.0;
  for (final i in items) {
    final wt = anyWeight ? i.weight : 1.0;
    s += i.spi * wt;
    w += wt;
  }
  return KpiResult(
    key: 'projects_spi',
    title: 'متوسط مؤشر الأداء الزمني (SPI)',
    section: 'projects',
    value: w == 0 ? null : s / w,
    unit: '',
    target: spiOk,
    sample: items.length,
    hint: 'المتوسط الموزون بقيمة العقد للجارية',
  );
}

/// مجموع أيام التأخير المتراكمة على المشاريع (الأقل أفضل، المستهدف صفر).
KpiResult kpiProjectsDelay(List<int> delayDays) {
  final total = delayDays.fold<int>(0, (a, b) => a + b);
  return KpiResult(
    key: 'projects_delay',
    title: 'أيام التأخير المتراكمة',
    section: 'projects',
    value: total.toDouble(),
    unit: 'يوم',
    target: 0,
    higherBetter: false,
    sample: delayDays.length,
    hint: 'مجموع أيام أحداث التأخير المسجلة على المشاريع الجارية',
  );
}

bool _inWindow(DateTime? d, DateTime now) {
  if (d == null) return false;
  return !d.isBefore(DateTime(now.year, now.month, now.day - kpiWindowDays));
}

/// الالتزام بموعد البلاغ المستهدف: المنجز في موعده ÷ (المنجز خلال النافذة + المفتوح الفائت موعده).
/// البلاغ بلا موعد مستهدف لا يدخل.
KpiResult kpiMaintenanceSla(List<MtRequest> reqs, DateTime now) {
  var met = 0, counted = 0;
  for (final r in reqs) {
    final due = r.dueAt;
    if (due == null) continue;
    final done = r.doneAt;
    if (done != null) {
      if (!_inWindow(done, now)) continue;
      counted++;
      if (!done.isAfter(due)) met++;
    } else if (r.isOpen && due.isBefore(now)) {
      counted++;
    }
  }
  return KpiResult(
    key: 'maintenance_sla',
    title: 'الالتزام بموعد بلاغات الصيانة',
    section: 'maintenance',
    value: counted == 0 ? null : _pct(met, counted),
    unit: '%',
    target: kpiSlaTarget,
    sample: counted,
    hint: 'المنجزة في موعدها ÷ (المنجزة آخر $kpiWindowDays يوماً + المفتوحة الفائتة)',
  );
}

/// متوسط زمن الإنجاز بالساعات: من تقديم البلاغ إلى إنجازه، للمنجز خلال النافذة (الأقل أفضل، بلا مستهدف).
KpiResult kpiMaintenanceMttr(List<MtRequest> reqs, DateTime now) {
  var sum = 0.0, n = 0;
  for (final r in reqs) {
    final rep = r.reportedAt, done = r.doneAt;
    if (rep == null || done == null || !_inWindow(done, now) || done.isBefore(rep)) continue;
    sum += done.difference(rep).inMinutes / 60;
    n++;
  }
  return KpiResult(
    key: 'maintenance_mttr',
    title: 'متوسط زمن إنجاز البلاغ',
    section: 'maintenance',
    value: n == 0 ? null : sum / n,
    unit: 'ساعة',
    higherBetter: false,
    sample: n,
    hint: 'متوسط (الإنجاز − التقديم) للمنجزة آخر $kpiWindowDays يوماً',
  );
}

/// الاستلام في الموعد: المستلمة في موعدها المتوقع ÷ (المستلمة خلال النافذة + القائمة الفائت موعدها).
/// الأمر بلا موعد متوقع لا يدخل.
KpiResult kpiProcurementOnTime(List<PrOrder> orders, DateTime today) {
  final t = _dateOnly(today);
  var met = 0, counted = 0;
  for (final o in orders) {
    final exp = o.expectedDate;
    if (exp == null) continue;
    final closed = o.closedAt;
    if (o.status == 'received' && closed != null) {
      if (!_inWindow(closed, today)) continue;
      counted++;
      if (!_dateOnly(closed).isAfter(_dateOnly(exp))) met++;
    } else if (o.isLive && _dateOnly(exp).isBefore(t)) {
      counted++;
    }
  }
  return KpiResult(
    key: 'procurement_on_time',
    title: 'استلام أوامر الشراء في موعدها',
    section: 'procurement',
    value: counted == 0 ? null : _pct(met, counted),
    unit: '%',
    target: kpiProcurementTarget,
    sample: counted,
    hint: 'المستلمة في موعدها ÷ (المستلمة آخر $kpiWindowDays يوماً + القائمة الفائتة)',
  );
}

/// سلامة المخزون: الأصناف النشطة التي ليست نافدة ولا دون حدها الأدنى ولا عند نقطة إعادة الطلب ÷ الأصناف النشطة.
KpiResult kpiStoresHealth(int activeItems, int alertItems) {
  final ok = activeItems - alertItems;
  return KpiResult(
    key: 'stores_health',
    title: 'سلامة المخزون',
    section: 'stores',
    value: activeItems == 0 ? null : _pct(ok < 0 ? 0 : ok, activeItems),
    unit: '%',
    target: kpiStoresTarget,
    sample: activeItems,
    hint: 'الأصناف النشطة خارج التنبيه ÷ الأصناف النشطة',
  );
}

/// «YYYY-MM» لتاريخ.
String kpiPeriodOf(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}';

/// عرض قيمة مؤشر: النسبة وأيام التأخير أعداداً صحيحة، وSPI بمنزلتين.
String kpiFormat(double? v, String unit) {
  if (v == null) return '—';
  final t = unit == '%' || unit == 'يوم' ? v.round().toString() : (v == v.roundToDouble() ? v.round().toString() : v.toStringAsFixed(2));
  return unit.isEmpty ? t : (unit == '%' ? '$t%' : '$t $unit');
}
