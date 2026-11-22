// =====================================================================
// البرنامج الزمني لكل عقد (الترحيلان 29 و30) وحساباته:
//   تعدّه الشؤون الفنية من المقايسة المعتمدة (مراحل، ومدد، وتبعيات، ثم اعتماد)، ويتابعه الإشراف:
//   النسبة المخططة لكل بند حتى تاريخ الإسناد، والانحراف بالنقاط وبالأيام، وحالة البند،
//   والنسبة الكلية الموزونة للمشروع (المخطط والفعلي) ومؤشر SPI وحالة المشروع، ثم ملخص المحفظة.
// المعادلات مشروحة في الفصلين 29 و30 من الدليل، وتطابق ما هنا وما في قاعدة البيانات حرفياً.
// =====================================================================

import 'dart:math' as math;

import 'models.dart';
import 'pm.dart';

double? _num(dynamic v) => v is num ? v.toDouble() : double.tryParse('${v ?? ''}');
int? _int(dynamic v) => v is num ? v.toInt() : int.tryParse('${v ?? ''}');
String _str(dynamic v) => v == null ? '' : v.toString();
String? _id(dynamic v) => v == null || '$v'.isEmpty ? null : '$v';
DateTime? _day(dynamic v) {
  final d = DateTime.tryParse(_str(v));
  return d == null ? null : DateTime(d.year, d.month, d.day);
}

/// مصدر البند: من المقايسة المعتمدة، أو بند إضافي للعقد ليس في المقايسة، أو نشاط.
const Map<String, String> itemSourceLabels = {
  'boq': 'بند مقايسة',
  'extra': 'بند إضافي',
  'manual': 'نشاط',
};

/// بند في البرنامج الزمني للعقد.
class PmItem {
  const PmItem({
    required this.id,
    required this.projectId,
    this.workId,
    this.sort = 0,
    this.code = '',
    required this.title,
    required this.plannedStart,
    required this.plannedEnd,
    this.weight,
    this.progress = 0,
    this.actualStart,
    this.actualEnd,
    this.notes = '',
    this.originProject,
    this.phaseId,
    this.durationDays,
    this.offsetDays = 0,
    this.dependsOn,
    this.source = 'manual',
    this.boqSheetId,
    this.boqLine,
    this.priceSeq,
    this.unit = '',
    this.qty,
    this.notApplicable = false,
  });

  final String id;
  final String projectId;
  final String? workId;
  final int sort;
  final String code;
  final String title;
  final DateTime plannedStart;
  final DateTime plannedEnd;

  /// الوزن النسبي (قيمة أو نسبة)؛ فارغ = متوسط أوزان البنود الأخرى.
  final double? weight;

  /// نسبة الإنجاز الفعلية 0–100.
  final double progress;
  final DateTime? actualStart;
  final DateTime? actualEnd;
  final String notes;
  final String? originProject;

  /// مرحلة التنفيذ، والمدة (تُحسب منها التواريخ)، والإزاحة داخل المرحلة، والبند الذي يتبعه.
  final String? phaseId;
  final int? durationDays;
  final int offsetDays;
  final String? dependsOn;
  final String source;
  final String? boqSheetId;
  final int? boqLine;
  final int? priceSeq;
  final String unit;
  final double? qty;

  /// «لا ينطبق»: يبقى في البرنامج ويخرج من الحساب.
  final bool notApplicable;

  factory PmItem.fromMap(Map<String, dynamic> m) => PmItem(
        id: _str(m['id']),
        projectId: _str(m['project_id']),
        workId: _id(m['work_id']),
        sort: _int(m['sort']) ?? 0,
        code: _str(m['code']),
        title: _str(m['title']),
        plannedStart: _day(m['planned_start']) ?? pmToday(),
        plannedEnd: _day(m['planned_end']) ?? pmToday(),
        weight: _num(m['weight']),
        progress: _num(m['progress']) ?? 0,
        actualStart: _day(m['actual_start']),
        actualEnd: _day(m['actual_end']),
        notes: _str(m['notes']),
        originProject: _id(m['origin_project']),
        phaseId: _id(m['phase_id']),
        durationDays: _int(m['duration_days']),
        offsetDays: _int(m['offset_days']) ?? 0,
        dependsOn: _id(m['depends_on']),
        source: _str(m['source']).isEmpty ? 'manual' : _str(m['source']),
        boqSheetId: _id(m['boq_sheet_id']),
        boqLine: _int(m['boq_line']),
        priceSeq: _int(m['price_seq']),
        unit: _str(m['unit']),
        qty: _num(m['qty']),
        notApplicable: m['not_applicable'] == true,
      );

  PmItem copyWith({int? durationDays, int? offsetDays, String? phaseId, String? dependsOn, bool clearDepends = false, String? boqSheetId}) => PmItem(
        id: id,
        projectId: projectId,
        workId: workId,
        sort: sort,
        code: code,
        title: title,
        plannedStart: plannedStart,
        plannedEnd: plannedEnd,
        weight: weight,
        progress: progress,
        actualStart: actualStart,
        actualEnd: actualEnd,
        notes: notes,
        originProject: originProject,
        phaseId: phaseId ?? this.phaseId,
        durationDays: durationDays ?? this.durationDays,
        offsetDays: offsetDays ?? this.offsetDays,
        dependsOn: clearDepends ? null : (dependsOn ?? this.dependsOn),
        source: source,
        boqSheetId: boqSheetId ?? this.boqSheetId,
        boqLine: boqLine,
        priceSeq: priceSeq,
        unit: unit,
        qty: qty,
        notApplicable: notApplicable,
      );

  /// المدة بالأيام: المسجلة، وإلا الفرق بين التاريخين المخططين.
  int get days => durationDays ?? math.max(1, daysBetween(plannedEnd, plannedStart));

  Map<String, dynamic> toJson() => {
        'project_id': projectId,
        'work_id': workId ?? '',
        'code': code,
        'title': title,
        'planned_start': pmIso(plannedStart),
        'planned_end': pmIso(plannedEnd),
        'weight': weight,
        'progress': progress,
        'actual_start': pmIso(actualStart),
        'actual_end': pmIso(actualEnd),
        'notes': notes,
      };
}

/// البرنامج الزمني للعقد: مسودة تعدّها الشؤون الفنية، ثم معتمد ومُحال إلى الإشراف.
class PmPlan {
  const PmPlan({
    required this.id,
    required this.projectId,
    required this.status,
    required this.startDate,
    this.notes = '',
    this.version = 0,
    this.approvedAt,
    this.approvedBy,
    this.updatedAt,
    this.updatedBy,
  });

  final String id;
  final String projectId;
  final String status; // draft | approved
  final DateTime startDate;
  final String notes;
  final int version;
  final DateTime? approvedAt;
  final String? approvedBy;
  final DateTime? updatedAt;
  final String? updatedBy;

  bool get approved => status == 'approved';

  factory PmPlan.fromMap(Map<String, dynamic> m) => PmPlan(
        id: _str(m['id']),
        projectId: _str(m['project_id']),
        status: _str(m['status']).isEmpty ? 'draft' : _str(m['status']),
        startDate: _day(m['start_date']) ?? pmToday(),
        notes: _str(m['notes']),
        version: _int(m['version']) ?? 0,
        approvedAt: DateTime.tryParse(_str(m['approved_at']))?.toLocal(),
        approvedBy: _id(m['approved_by']),
        updatedAt: DateTime.tryParse(_str(m['updated_at']))?.toLocal(),
        updatedBy: _id(m['updated_by']),
      );
}

/// مرحلة تنفيذ في البرنامج، بفاصلها عن المرحلة السابقة (سالب = تداخل).
class PmPhase {
  const PmPhase({required this.id, required this.projectId, required this.sort, required this.name, this.lagDays = 0});

  final String id;
  final String projectId;
  final int sort;
  final String name;
  final int lagDays;

  factory PmPhase.fromMap(Map<String, dynamic> m) => PmPhase(
        id: _str(m['id']),
        projectId: _str(m['project_id']),
        sort: _int(m['sort']) ?? 0,
        name: _str(m['name']),
        lagDays: _int(m['lag_days']) ?? 0,
      );
}

/// ترتيب البنود في البرنامج: البنود دون مرحلة أولاً، ثم بترتيب المراحل، ثم بترتيب البند.
List<PmItem> orderItems(List<PmItem> items, List<PmPhase> phases) {
  final rank = {for (final p in phases) p.id: p.sort};
  int r(PmItem i) => i.phaseId == null ? -1000000 : (rank[i.phaseId] ?? 1000000);
  return [...items]..sort((a, b) {
      final x = r(a), y = r(b);
      if (x != y) return x.compareTo(y);
      if (a.sort != b.sort) return a.sort.compareTo(b.sort);
      return a.plannedStart.compareTo(b.plannedStart);
    });
}

/// امتداد مرحلة بعد الحساب.
class PhaseSpan {
  const PhaseSpan(this.phase, this.start, this.end);

  final PmPhase phase;
  final DateTime start;
  final DateTime end;
  int get days => daysBetween(end, start);
}

/// حساب تواريخ البرنامج (كدالة pm_plan_recalc في قاعدة البيانات):
///   البنود دون مرحلة تبدأ ببداية البرنامج أو بنهاية البند الذي تتبعه، + إزاحتها.
///   المرحلة الأولى تبدأ ببداية البرنامج، وكل مرحلة تالية بنهاية سابقتها + فاصلها (ولا تسبق بداية البرنامج).
///   البند يبدأ ببداية مرحلته أو بنهاية البند الذي يتبعه (أيهما أبعد) + إزاحته، وينتهي بعد مدته.
///   البند بلا مدة يحتفظ بتاريخيه، ونهاية المرحلة أبعد نهايات بنودها.
class PlanLayout {
  PlanLayout(this.start, List<PmPhase> phases, List<PmItem> items) {
    final ph = [...phases]..sort((a, b) => a.sort.compareTo(b.sort));
    final ends = <String, DateTime>{};
    DateTime place(PmItem i, DateTime base) {
      if (i.durationDays == null) {
        dates[i.id] = (i.plannedStart, i.plannedEnd);
        ends[i.id] = i.plannedEnd;
        return i.plannedEnd;
      }
      final dep = i.dependsOn == null ? null : ends[i.dependsOn];
      final b = dep != null && dep.isAfter(base) ? dep : base;
      final s = addDays(b, i.offsetDays);
      final e = addDays(s, i.durationDays!);
      dates[i.id] = (s, e);
      ends[i.id] = e;
      return e;
    }

    final byPhase = <String?, List<PmItem>>{};
    for (final i in orderItems(items, ph)) {
      (byPhase[ph.any((p) => p.id == i.phaseId) ? i.phaseId : null] ??= []).add(i);
    }
    for (final i in byPhase[null] ?? const <PmItem>[]) {
      place(i, start);
    }
    DateTime? prev;
    for (final p in ph) {
      var ps = prev == null ? start : addDays(prev, p.lagDays);
      if (ps.isBefore(start)) ps = start;
      var pe = ps;
      for (final i in byPhase[p.id] ?? const <PmItem>[]) {
        final e = place(i, ps);
        if (e.isAfter(pe)) pe = e;
      }
      spans.add(PhaseSpan(p, ps, pe));
      prev = pe;
    }
  }

  final DateTime start;
  final Map<String, (DateTime, DateTime)> dates = {};
  final List<PhaseSpan> spans = [];

  DateTime get end {
    var e = start;
    for (final d in dates.values) {
      if (d.$2.isAfter(e)) e = d.$2;
    }
    return e;
  }

  /// المدة الإجمالية للبرنامج (يوم).
  int get totalDays => daysBetween(end, start);
}

/// تصنيف الأداء بمؤشر SPI وحدود الإعدادات (كالمستعمل في سجل المشاريع).
String spiPerf(double spi, PmConfig cfg) {
  if (spi >= cfg.spiAhead) return 'ahead';
  if (spi >= cfg.spiOk) return 'on_track';
  if (spi >= cfg.spiWarn) return 'slight';
  return 'critical';
}

/// حساب بند في تاريخ الإسناد [ref]:
///   المدة D = النهاية المخططة − البداية المخططة (يوم واحد على الأقل)
///   المنقضي E = تاريخ الإسناد − البداية المخططة، محصوراً بين 0 وD
///   المخطط P = E ÷ D × 100، والفعلي A = نسبة الإنجاز المسجلة
///   الانحراف = A − P (نقطة مئوية)، والانحراف بالأيام = A ÷ 100 × D − E (موجب = متقدم)
class ItemCalc {
  ItemCalc(this.item, this.ref, this.cfg);

  final PmItem item;
  final DateTime ref;
  final PmConfig cfg;

  int get duration => math.max(1, daysBetween(item.plannedEnd, item.plannedStart));
  int get elapsed => daysBetween(ref, item.plannedStart).clamp(0, duration).toInt();
  double get planned => elapsed / duration * 100;
  double get actual => item.progress;
  double get variance => actual - planned;
  double get daysVariance => actual / 100 * duration - elapsed;

  /// أيام التجاوز بعد النهاية المخططة لبند لم يكتمل.
  int? get overdueDays => actual < 100 && ref.isAfter(item.plannedEnd) ? daysBetween(ref, item.plannedEnd) : null;

  /// أيام التأخر (للمخاطر): max(round(E − A ÷ 100 × D)، أيام التجاوز، 0).
  int get behindDays => math.max(0, math.max((elapsed - actual / 100 * duration).round(), overdueDays ?? 0));

  double? get spi => planned == 0 ? null : actual / planned;

  /// منجز، أو لم يحن موعده، أو تصنيف SPI.
  String get status {
    if (actual >= 100) return 'done';
    if (planned == 0) return actual > 0 ? 'ahead' : 'not_started';
    return spiPerf(actual / planned, cfg);
  }

  bool get isLate => status == 'slight' || status == 'critical';

  /// الإنهاء المتوقع بالسرعة الحالية: تاريخ الإسناد + (100 − A) ÷ (A ÷ E).
  DateTime? get forecastEnd {
    if (actual >= 100) return item.actualEnd;
    if (actual <= 0 || elapsed <= 0) return null;
    return addDays(ref, ((100 - actual) / (actual / elapsed)).ceil());
  }

  /// التأخير المتوقع عن النهاية المخططة (أيام).
  int? get forecastDelay {
    final f = forecastEnd;
    return f == null ? null : daysBetween(f, item.plannedEnd);
  }

  /// النهاية المتوقعة لكل بند (لإنهاء العقد المتوقع):
  ///   المنجز: نهايته الفعلية، وإلا الأقرب من نهايته المخططة وتاريخ الإسناد
  ///   الجاري (A > 0 وE > 0): الإنهاء المتوقع بالسرعة الحالية
  ///   الذي حان موعده ولم يبدأ (A = 0 وE > 0): تاريخ الإسناد + مدته كاملة
  ///   الذي لم يحن موعده: نهايته المخططة
  DateTime get projectedEnd {
    if (actual >= 100) return item.actualEnd ?? (item.plannedEnd.isBefore(ref) ? item.plannedEnd : ref);
    if (actual > 0 && elapsed > 0) return forecastEnd!;
    if (elapsed > 0) return addDays(ref, duration);
    return item.plannedEnd;
  }
}

/// الأوزان الفعلية: الوزن المسجل، وإلا متوسط الأوزان المسجلة، وإن لم يُسجَّل وزن فأوزان متساوية.
List<double> effectiveWeights(List<PmItem> items) {
  final given = [for (final i in items) if ((i.weight ?? 0) > 0) i.weight!];
  final mean = given.isEmpty ? 1.0 : given.reduce((a, b) => a + b) / given.length;
  return [for (final i in items) (i.weight ?? 0) > 0 ? i.weight! : mean];
}

/// الجدول الزمني لعقد: بنوده وحسابه الكلي (البنود «لا ينطبق» خارج الحساب).
///   النسبة الكلية الفعلية = Σ(وزن × A) ÷ Σ وزن، والمخططة = Σ(وزن × P) ÷ Σ وزن، وSPI = الفعلية ÷ المخططة.
class ScheduleTrack {
  ScheduleTrack(this.project, List<PmItem> items, this.ref, this.cfg, {this.plan, this.phases = const []})
      : allItems = orderItems(items, phases) {
    this.items = allItems.where((i) => !i.notApplicable).toList();
    calcs = [for (final i in this.items) ItemCalc(i, ref, cfg)];
    weights = effectiveWeights(this.items);
    final sw = weights.fold<double>(0, (a, b) => a + b);
    if (calcs.isNotEmpty && sw > 0) {
      var a = 0.0, p = 0.0;
      for (var k = 0; k < calcs.length; k++) {
        a += weights[k] * calcs[k].actual;
        p += weights[k] * calcs[k].planned;
      }
      actual = a / sw;
      planned = p / sw;
    }
    shares = [for (final w in weights) sw == 0 ? 0 : w / sw * 100];
  }

  final Project project;
  final PmPlan? plan;
  final List<PmPhase> phases;

  /// كل البنود بترتيب البرنامج، ومنها «لا ينطبق».
  final List<PmItem> allItems;

  /// البنود الداخلة في الحساب.
  late final List<PmItem> items;
  final DateTime ref;
  final PmConfig cfg;
  late final List<ItemCalc> calcs;
  late final List<double> weights;

  /// نصيب كل بند من الوزن الكلي (%).
  late final List<double> shares;
  double? actual;
  double? planned;

  double? get variance => actual == null || planned == null ? null : actual! - planned!;
  double? get spi => planned == null || planned == 0 ? null : actual! / planned!;

  String get perf {
    if (calcs.isEmpty || actual == null) return 'no_data';
    if (actual! >= 100) return 'done';
    if (planned == 0) return actual! > 0 ? 'ahead' : 'not_started';
    return spiPerf(actual! / planned!, cfg);
  }

  bool get isLate => perf == 'slight' || perf == 'critical';
  bool get isAhead => perf == 'ahead';

  DateTime? get start => items.isEmpty ? null : items.map((i) => i.plannedStart).reduce((a, b) => a.isBefore(b) ? a : b);
  DateTime? get end => items.isEmpty ? null : items.map((i) => i.plannedEnd).reduce((a, b) => a.isAfter(b) ? a : b);

  /// بداية البرنامج: المسجلة في البرنامج المعتمد، وإلا أول بداية مخططة.
  DateTime? get planStart => plan?.startDate ?? start;

  /// مدة البرنامج (يوم).
  int? get totalDays => end == null || planStart == null ? null : math.max(1, daysBetween(end!, planStart!));

  /// فارق الإنجاز الكلي بالأيام = (الفعلي الكلي − المخطط الكلي) ÷ 100 × مدة البرنامج (موجب = متقدم).
  int? get daysVariance =>
      actual == null || planned == null || totalDays == null ? null : ((actual! - planned!) / 100 * totalDays!).round();

  /// الإنهاء المتوقع للعقد: أبعد نهاية متوقعة بين بنوده.
  DateTime? get projectedEnd {
    DateTime? e;
    for (final c in calcs) {
      final d = c.projectedEnd;
      if (e == null || d.isAfter(e)) e = d;
    }
    return e;
  }

  /// الإنهاء المتوقع ناقص نهاية البرنامج (موجب = تجاوز متوقع، سالب = إنهاء مبكر).
  int? get forecastDelay => perf == 'done' || projectedEnd == null || end == null ? null : daysBetween(projectedEnd!, end!);

  List<ItemCalc> get lateItems => calcs.where((c) => c.isLate).toList();
  List<ItemCalc> get overdueItems => calcs.where((c) => c.overdueDays != null).toList();
  int get doneItems => calcs.where((c) => c.status == 'done').length;
  int get runningItems => calcs.where((c) => c.status != 'done' && (c.actual > 0 || c.item.actualStart != null)).length;
  int get notStartedItems => calcs.where((c) => c.actual <= 0 && c.item.actualStart == null).length;

  /// أكبر تأخير متوقع بين البنود (أيام).
  int? get worstForecastDelay {
    int? w;
    for (final c in calcs) {
      final d = c.forecastDelay;
      if (d != null && (w == null || d > w)) w = d;
    }
    return w;
  }

  ItemCalc? calcOf(String itemId) {
    for (final c in calcs) {
      if (c.item.id == itemId) return c;
    }
    return null;
  }
}

/// ملخص الجداول الزمنية للمحفظة: العقود ذات البرنامج المعتمد (والبنود القديمة بلا برنامج).
class ScheduleAnalysis {
  ScheduleAnalysis({
    required List<Project> projects,
    required List<PmItem> items,
    required this.cfg,
    Map<String, PmPlan> plans = const {},
    List<PmPhase> phases = const [],
  }) : ref = cfg.refDay {
    final by = <String, List<PmItem>>{};
    for (final i in items) {
      (by[i.projectId] ??= []).add(i);
    }
    final phBy = <String, List<PmPhase>>{};
    for (final p in phases) {
      (phBy[p.projectId] ??= []).add(p);
    }
    final list = [...projects]..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    for (final p in list) {
      final l = by[p.id];
      final plan = plans[p.id];
      if (l == null || l.isEmpty || (plan != null && !plan.approved)) continue;
      tracks[p.id] = ScheduleTrack(p, l, ref, cfg, plan: plan, phases: phBy[p.id] ?? const []);
    }
  }

  final PmConfig cfg;
  final DateTime ref;
  final Map<String, ScheduleTrack> tracks = {};

  ScheduleTrack? track(String projectId) => tracks[projectId];

  Map<String, int> get perfCounts {
    final m = <String, int>{};
    for (final t in tracks.values) {
      m[t.perf] = (m[t.perf] ?? 0) + 1;
    }
    return m;
  }

  int get lateProjects => tracks.values.where((t) => t.isLate).length;
  int get aheadProjects => tracks.values.where((t) => t.isAhead).length;

  /// البنود المتأخرة في كل المشاريع، الأكبر انحرافاً أولاً.
  List<(ScheduleTrack, ItemCalc)> get lateItems {
    final out = <(ScheduleTrack, ItemCalc)>[
      for (final t in tracks.values)
        for (final c in t.lateItems) (t, c),
    ];
    out.sort((a, b) => a.$2.variance.compareTo(b.$2.variance));
    return out;
  }

  /// متوسط بسيط لنسب المشاريع (فعلي ومخطط).
  double? get avgActual => tracks.isEmpty ? null : tracks.values.map((t) => t.actual ?? 0).reduce((a, b) => a + b) / tracks.length;
  double? get avgPlanned => tracks.isEmpty ? null : tracks.values.map((t) => t.planned ?? 0).reduce((a, b) => a + b) / tracks.length;
}
