// =====================================================================
// بنود الجدول الزمني لكل مشروع (الترحيل 29) وحساباتها:
//   النسبة المخططة لكل بند حتى تاريخ الإسناد، والانحراف بالنقاط وبالأيام، وحالة البند،
//   والنسبة الكلية الموزونة للمشروع (المخطط والفعلي) ومؤشر SPI وحالة المشروع، ثم ملخص المحفظة.
// المعادلات مشروحة في الفصل 29 من الدليل، وتطابق ما هنا حرفياً.
// =====================================================================

import 'dart:math' as math;

import 'models.dart';
import 'pm.dart';

double? _num(dynamic v) => v is num ? v.toDouble() : double.tryParse('${v ?? ''}');
int? _int(dynamic v) => v is num ? v.toInt() : int.tryParse('${v ?? ''}');
String _str(dynamic v) => v == null ? '' : v.toString();
DateTime? _day(dynamic v) {
  final d = DateTime.tryParse(_str(v));
  return d == null ? null : DateTime(d.year, d.month, d.day);
}

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

  factory PmItem.fromMap(Map<String, dynamic> m) => PmItem(
        id: _str(m['id']),
        projectId: _str(m['project_id']),
        workId: m['work_id'] == null ? null : _str(m['work_id']),
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
        originProject: m['origin_project'] == null ? null : _str(m['origin_project']),
      );

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
}

/// الأوزان الفعلية: الوزن المسجل، وإلا متوسط الأوزان المسجلة، وإن لم يُسجَّل وزن فأوزان متساوية.
List<double> effectiveWeights(List<PmItem> items) {
  final given = [for (final i in items) if ((i.weight ?? 0) > 0) i.weight!];
  final mean = given.isEmpty ? 1.0 : given.reduce((a, b) => a + b) / given.length;
  return [for (final i in items) (i.weight ?? 0) > 0 ? i.weight! : mean];
}

/// الجدول الزمني لعقد: بنوده وحسابه الكلي.
///   النسبة الكلية الفعلية = Σ(وزن × A) ÷ Σ وزن، والمخططة = Σ(وزن × P) ÷ Σ وزن، وSPI = الفعلية ÷ المخططة.
class ScheduleTrack {
  ScheduleTrack(this.project, List<PmItem> items, this.ref, this.cfg)
      : items = [...items]..sort((a, b) => a.sort != b.sort ? a.sort.compareTo(b.sort) : a.plannedStart.compareTo(b.plannedStart)) {
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
  final List<PmItem> items;
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

  List<ItemCalc> get lateItems => calcs.where((c) => c.isLate).toList();
  List<ItemCalc> get overdueItems => calcs.where((c) => c.overdueDays != null).toList();
  int get doneItems => calcs.where((c) => c.status == 'done').length;

  /// أكبر تأخير متوقع بين البنود (أيام).
  int? get worstForecastDelay {
    int? w;
    for (final c in calcs) {
      final d = c.forecastDelay;
      if (d != null && (w == null || d > w)) w = d;
    }
    return w;
  }
}

/// ملخص الجداول الزمنية للمحفظة.
class ScheduleAnalysis {
  ScheduleAnalysis({required List<Project> projects, required List<PmItem> items, required this.cfg}) : ref = cfg.refDay {
    final by = <String, List<PmItem>>{};
    for (final i in items) {
      (by[i.projectId] ??= []).add(i);
    }
    final list = [...projects]..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    for (final p in list) {
      final l = by[p.id];
      if (l != null && l.isNotEmpty) tracks[p.id] = ScheduleTrack(p, l, ref, cfg);
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
