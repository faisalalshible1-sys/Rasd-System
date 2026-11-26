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
    this.startNotBefore,
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

  /// «لا يبدأ قبل» تاريخ (الترحيل 36).
  final DateTime? startNotBefore;

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
        startNotBefore: _day(m['start_not_before']),
      );

  PmItem copyWith(
          {int? durationDays,
          int? offsetDays,
          String? phaseId,
          String? dependsOn,
          bool clearDepends = false,
          String? boqSheetId,
          DateTime? startNotBefore,
          bool clearStartNotBefore = false}) =>
      PmItem(
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
        startNotBefore: clearStartNotBefore ? null : (startNotBefore ?? this.startNotBefore),
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

/// حساب تواريخ البرنامج (كدالة pm_plan_recalc في قاعدة البيانات بعد الترحيل 36):
///   الأساس = بداية المرحلة (وبداية البرنامج لما خارج المراحل). القيد من كل علاقة:
///     نهاية←بداية = نهاية السابق + الانتظار، بداية←بداية = بداية السابق + الانتظار،
///     نهاية←نهاية = نهاية السابق + الانتظار − المدة، بداية←نهاية = بداية السابق + الانتظار − المدة.
///   البداية = أكبر (الأساس، القيود) + الإزاحة، ثم لا تسبق «لا يبدأ قبل»، والنهاية = البداية + المدة.
///   «يتبع البند» القديم نهاية←بداية بلا انتظار إن لم تقابله علاقة.
///   المرحلة الأولى تبدأ ببداية البرنامج، وكل مرحلة تالية بنهاية سابقتها + فاصلها (ولا تسبق بداية البرنامج).
///   البند بلا مدة يحتفظ بتاريخيه، ونهاية المرحلة أبعد نهايات بنودها.
class PlanLayout {
  PlanLayout(this.start, List<PmPhase> phases, List<PmItem> items, {List<PmLink> links = const []}) {
    final ph = [...phases]..sort((a, b) => a.sort.compareTo(b.sort));
    final starts = <String, DateTime>{};
    final ends = <String, DateTime>{};
    final into = <String, List<PmLink>>{};
    for (final l in links) {
      (into[l.succId] ??= []).add(l);
    }
    DateTime place(PmItem i, DateTime base) {
      if (i.durationDays == null) {
        dates[i.id] = (i.plannedStart, i.plannedEnd);
        starts[i.id] = i.plannedStart;
        ends[i.id] = i.plannedEnd;
        return i.plannedEnd;
      }
      final d = i.durationDays!;
      var s = base;
      for (final l in into[i.id] ?? const <PmLink>[]) {
        final ps = starts[l.predId], pe = ends[l.predId];
        if (ps == null || pe == null) continue;
        final c = switch (l.kind) {
          'SS' => addDays(ps, l.lagDays),
          'FF' => addDays(pe, l.lagDays - d),
          'SF' => addDays(ps, l.lagDays - d),
          _ => addDays(pe, l.lagDays),
        };
        if (c.isAfter(s)) s = c;
      }
      final dep = i.dependsOn == null ? null : ends[i.dependsOn];
      if (dep != null && !(into[i.id] ?? const <PmLink>[]).any((l) => l.predId == i.dependsOn) && dep.isAfter(s)) s = dep;
      s = addDays(s, i.offsetDays);
      final snb = i.startNotBefore;
      if (snb != null && snb.isAfter(s)) s = snb;
      final e = addDays(s, d);
      dates[i.id] = (s, e);
      starts[i.id] = s;
      ends[i.id] = e;
      return e;
    }

    final byPhase = <String?, List<PmItem>>{};
    for (final i in orderItems(items, ph)) {
      (byPhase[ph.any((p) => p.id == i.phaseId) ? i.phaseId : null] ??= []).add(i);
    }
    for (final i in byPhase[null] ?? const <PmItem>[]) {
      order.add(i);
      place(i, start);
    }
    DateTime? prev;
    for (final p in ph) {
      var ps = prev == null ? start : addDays(prev, p.lagDays);
      if (ps.isBefore(start)) ps = start;
      var pe = ps;
      for (final i in byPhase[p.id] ?? const <PmItem>[]) {
        order.add(i);
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

  /// الأنشطة بترتيب الحساب (ما خارج المراحل ثم المراحل).
  final List<PmItem> order = [];

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

// ---------------------------------------------------------------------
// العلاقات والمسار الحرج (الترحيل 36)
// ---------------------------------------------------------------------

/// أنواع العلاقات: نهاية←بداية، بداية←بداية، نهاية←نهاية، بداية←نهاية.
const List<String> linkKinds = ['FS', 'SS', 'FF', 'SF'];
const Map<String, String> linkKindLabels = {
  'FS': 'نهاية ← بداية',
  'SS': 'بداية ← بداية',
  'FF': 'نهاية ← نهاية',
  'SF': 'بداية ← نهاية',
};
const Map<String, String> linkKindHelp = {
  'FS': 'يبدأ بعد انتهاء السابق',
  'SS': 'يبدأ مع بداية السابق',
  'FF': 'ينتهي مع نهاية السابق',
  'SF': 'ينتهي مع بداية السابق',
};

class PmLink {
  const PmLink({required this.id, required this.predId, required this.succId, this.kind = 'FS', this.lagDays = 0});

  final String id;
  final String predId;
  final String succId;
  final String kind;
  final int lagDays;

  factory PmLink.fromMap(Map<String, dynamic> m) => PmLink(
        id: _str(m['id']),
        predId: _str(m['pred_id']),
        succId: _str(m['succ_id']),
        kind: linkKinds.contains(_str(m['kind'])) ? _str(m['kind']) : 'FS',
        lagDays: _int(m['lag_days']) ?? 0,
      );

  /// «نهاية ← بداية +2»
  String get label => '${linkKindLabels[kind]}${lagDays == 0 ? '' : (lagDays > 0 ? ' +$lagDays' : ' $lagDays')}';
}

/// المسار الحرج: تمريرة عكسية على تواريخ [PlanLayout] تعطي آخر بداية وآخر نهاية لكل نشاط دون تأخير نهاية البرنامج،
/// والمرونة الكلية = آخر نهاية − النهاية المخططة. النشاط حرج إن كانت مرونته صفراً.
///   قيود العلاقة على السابق (ب = التالي، والإزاحة تُطرح من آخر بدايته ونهايته):
///     نهاية←بداية: آخر نهاية ≤ آخر بداية ب − الانتظار؛ بداية←بداية: آخر نهاية ≤ آخر بداية ب − الانتظار + المدة؛
///     نهاية←نهاية: آخر نهاية ≤ آخر نهاية ب − الانتظار؛ بداية←نهاية: آخر نهاية ≤ آخر نهاية ب − الانتظار + المدة.
///   وقيد المراحل: نهاية كل نشاط في مرحلة ≤ آخر بداية المرحلة التالية − فاصلها، وآخر بداية المرحلة
///   = أصغر (آخر بداية كل نشاط فيها − إزاحته)، ولا تتجاوز آخر بداية التالية − فاصلها.
class PlanFloat {
  PlanFloat(PlanLayout layout, List<PmPhase> phases, List<PmLink> links) {
    final finish = layout.end;
    final ph = [...phases]..sort((a, b) => a.sort.compareTo(b.sort));
    final phaseOf = <String, int>{};
    for (final i in layout.order) {
      final k = ph.indexWhere((p) => p.id == i.phaseId);
      phaseOf[i.id] = k;
    }
    final out = <String, List<PmLink>>{};
    for (final l in links) {
      (out[l.predId] ??= []).add(l);
    }
    final byId = {for (final i in layout.order) i.id: i};
    final followers = <String, List<PmItem>>{};
    for (final s in layout.order) {
      if (s.dependsOn != null) (followers[s.dependsOn!] ??= []).add(s);
    }
    // آخر بداية كل مرحلة (من الأخيرة)، تُحسب بعد أنشطتها
    final phaseLatest = List<DateTime?>.filled(ph.length + 1, null);
    DateTime? limitAfter(int k) {
      // قيد نهاية أنشطة المرحلة k: آخر بداية المرحلة التالية − فاصلها
      if (k < 0 || k + 1 >= ph.length) return null;
      final nl = phaseLatest[k + 1];
      return nl == null ? null : addDays(nl, -ph[k + 1].lagDays);
    }

    var lastPhase = ph.length;
    for (final i in layout.order.reversed) {
      final k = phaseOf[i.id] ?? -1;
      // عند الانتقال إلى مرحلة أسبق: أكمل آخر بدايات المراحل الفارغة بينهما
      while (lastPhase - 1 > k && lastPhase - 1 >= 0) {
        lastPhase--;
        _closePhase(lastPhase, ph, phaseLatest, byId, phaseOf);
      }
      final (es, ef) = layout.dates[i.id]!;
      final d = daysBetween(ef, es);
      var lf = finish;
      final lim = limitAfter(k);
      if (lim != null && lim.isBefore(lf)) lf = lim;
      for (final l in out[i.id] ?? const <PmLink>[]) {
        final s = byId[l.succId];
        final sl = latest[l.succId];
        if (s == null || sl == null) continue;
        final ls = addDays(sl.$1, -s.offsetDays), lfs = addDays(sl.$2, -s.offsetDays);
        final c = switch (l.kind) {
          'SS' => addDays(ls, d - l.lagDays),
          'FF' => addDays(lfs, -l.lagDays),
          'SF' => addDays(lfs, d - l.lagDays),
          _ => addDays(ls, -l.lagDays),
        };
        if (c.isBefore(lf)) lf = c;
      }
      // «يتبع البند» القديم دون علاقة مقابلة
      for (final s in followers[i.id] ?? const <PmItem>[]) {
        if (!(out[i.id] ?? const <PmLink>[]).any((l) => l.succId == s.id)) {
          final sl = latest[s.id];
          if (sl == null) continue;
          final c = addDays(sl.$1, -s.offsetDays);
          if (c.isBefore(lf)) lf = c;
        }
      }
      latest[i.id] = (addDays(lf, -d), lf);
      total[i.id] = daysBetween(lf, ef);
    }
    while (lastPhase > 0) {
      lastPhase--;
      _closePhase(lastPhase, ph, phaseLatest, byId, phaseOf);
    }
    this.finish = finish;
  }

  void _closePhase(int k, List<PmPhase> ph, List<DateTime?> phaseLatest, Map<String, PmItem> byId, Map<String, int> phaseOf) {
    DateTime? m;
    for (final e in phaseOf.entries) {
      if (e.value != k) continue;
      final i = byId[e.key]!;
      if (i.durationDays == null) continue;
      final l = latest[e.key];
      if (l == null) continue;
      final c = addDays(l.$1, -i.offsetDays);
      if (m == null || c.isBefore(m)) m = c;
    }
    if (k + 1 < ph.length && phaseLatest[k + 1] != null) {
      final c = addDays(phaseLatest[k + 1]!, -ph[k + 1].lagDays);
      if (m == null || c.isBefore(m)) m = c;
    }
    phaseLatest[k] = m;
  }

  late final DateTime finish;

  /// آخر بداية وآخر نهاية لكل نشاط.
  final Map<String, (DateTime, DateTime)> latest = {};

  /// المرونة الكلية بالأيام.
  final Map<String, int> total = {};

  bool critical(String id) => (total[id] ?? 1) <= 0;
  List<String> get criticalIds => [for (final e in total.entries) if (e.value <= 0) e.key];
}

// ---------------------------------------------------------------------
// معدلات الإنتاجية (الترحيل 36)، كالدوال pm_unit_norm وpm_text_norm وpm_rate_for في قاعدة البيانات
// ---------------------------------------------------------------------
String pmUnitNorm(String s) {
  final b = StringBuffer();
  for (final r in s.runes) {
    if (r >= 0x0660 && r <= 0x0669) {
      b.writeCharCode(0x30 + r - 0x0660);
    } else if (r >= 0x06F0 && r <= 0x06F9) {
      b.writeCharCode(0x30 + r - 0x06F0);
    } else if (r == 0xB2) {
      b.write('2');
    } else if (r == 0xB3) {
      b.write('3');
    } else if (r == 0x20 || r == 0x09 || r == 0x0A || r == 0x2E || r == 0x2F || r == 0x5F || r == 0x2D) {
      continue;
    } else {
      b.writeCharCode(r);
    }
  }
  return b.toString().toLowerCase();
}

String pmTextNorm(String s) {
  final b = StringBuffer();
  for (final r in s.runes) {
    if (r == 0x0640 || (r >= 0x064B && r <= 0x0652) || r == 0x0670) continue;
    var c = r;
    if (c == 0x0623 || c == 0x0625 || c == 0x0622 || c == 0x0671) c = 0x0627;
    if (c == 0x0629) c = 0x0647;
    if (c == 0x0649) c = 0x064A;
    b.writeCharCode(c);
  }
  return b.toString().toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();
}

class PmRate {
  const PmRate({
    required this.id,
    required this.unit,
    this.keyword = '',
    required this.rate,
    this.label = '',
    this.active = true,
    required this.validFrom,
    this.note = '',
    this.createdAt,
    this.createdBy,
  });

  final String id;
  final String unit;
  final String keyword;

  /// الكمية المنجزة في يوم عمل.
  final double rate;
  final String label;
  final bool active;
  final DateTime validFrom;
  final String note;
  final DateTime? createdAt;
  final String? createdBy;

  String get key => '${pmUnitNorm(unit)}|${pmTextNorm(keyword)}';

  factory PmRate.fromMap(Map<String, dynamic> m) => PmRate(
        id: _str(m['id']),
        unit: _str(m['unit']),
        keyword: _str(m['keyword']),
        rate: _num(m['rate']) ?? 0,
        label: _str(m['label']),
        active: m['active'] != false,
        validFrom: _day(m['valid_from']) ?? pmToday(),
        note: _str(m['note']),
        createdAt: DateTime.tryParse(_str(m['created_at']))?.toLocal(),
        createdBy: _id(m['created_by']),
      );
}

/// المعدلات السارية في [today]: لكل وحدة وكلمة أحدث إصدار بلغ تاريخه.
List<PmRate> currentRates(List<PmRate> all, DateTime today) {
  final best = <String, PmRate>{};
  for (final r in all) {
    if (r.validFrom.isAfter(today)) continue;
    final b = best[r.key];
    final newer = b == null ||
        r.validFrom.isAfter(b.validFrom) ||
        (r.validFrom == b.validFrom && (r.createdAt ?? DateTime(0)).isAfter(b.createdAt ?? DateTime(0)));
    if (newer) best[r.key] = r;
  }
  return best.values.toList();
}

/// المعدل المطابق: الوحدة نفسها، وأطول كلمة يحويها الوصف، أو المعدل العام للوحدة.
PmRate? rateFor(List<PmRate> current, String unit, String desc) {
  final u = pmUnitNorm(unit);
  if (u.isEmpty) return null;
  final d = pmTextNorm(desc);
  PmRate? best;
  for (final r in current) {
    if (!r.active || pmUnitNorm(r.unit) != u) continue;
    final k = pmTextNorm(r.keyword);
    if (k.isNotEmpty && !d.contains(k)) continue;
    if (best == null || k.length > pmTextNorm(best.keyword).length) best = r;
  }
  return best;
}

/// المدة بالإنتاجية = ⌈الكمية ÷ المعدل⌉ بين يوم و3650 يوماً.
int? rateDays(List<PmRate> current, String unit, String desc, double? qty) {
  if (qty == null || qty <= 0) return null;
  final r = rateFor(current, unit, desc);
  if (r == null || r.rate <= 0) return null;
  return math.min(3650, math.max(1, (qty / r.rate).ceil()));
}

// ---------------------------------------------------------------------
// إصدارات البرنامج المعتمدة (الترحيل 36)
// ---------------------------------------------------------------------
class PlanVersionItem {
  const PlanVersionItem({required this.id, this.code = '', required this.title, required this.start, required this.end, this.duration});

  final String id;
  final String code;
  final String title;
  final DateTime start;
  final DateTime end;
  final int? duration;
}

class PmPlanVersion {
  const PmPlanVersion({
    required this.id,
    required this.projectId,
    required this.version,
    this.source = 'approval',
    required this.startDate,
    this.endDate,
    this.items = const [],
    this.approvedAt,
    this.approvedBy,
  });

  final String id;
  final String projectId;
  final int version;
  final String source;
  final DateTime startDate;
  final DateTime? endDate;
  final List<PlanVersionItem> items;
  final DateTime? approvedAt;
  final String? approvedBy;

  int get totalDays => endDate == null ? 0 : daysBetween(endDate!, startDate);

  factory PmPlanVersion.fromMap(Map<String, dynamic> m) => PmPlanVersion(
        id: _str(m['id']),
        projectId: _str(m['project_id']),
        version: _int(m['version']) ?? 1,
        source: _str(m['source']),
        startDate: _day(m['start_date']) ?? pmToday(),
        endDate: _day(m['end_date']),
        items: [
          for (final x in (m['items'] is List ? m['items'] as List : const []))
            if (x is Map)
              PlanVersionItem(
                id: _str(x['id']),
                code: _str(x['code']),
                title: _str(x['title']),
                start: _day(x['start']) ?? pmToday(),
                end: _day(x['end']) ?? pmToday(),
                duration: _int(x['duration']),
              ),
        ],
        approvedAt: DateTime.tryParse(_str(m['approved_at']))?.toLocal(),
        approvedBy: _id(m['approved_by']),
      );
}

/// مقارنة نشاط بين إصدار أساس والبرنامج الحالي والتنفيذ الفعلي.
class VersionDelta {
  const VersionDelta({required this.title, this.base, this.current, this.startShift, this.endShift, this.actualEndShift, this.added = false, this.removed = false});

  final String title;
  final PlanVersionItem? base;
  final PmItem? current;

  /// فرق البداية والنهاية المخططتين (الحالي − الأساس) بالأيام، وفرق النهاية الفعلية عن نهاية الأساس.
  final int? startShift;
  final int? endShift;
  final int? actualEndShift;
  final bool added;
  final bool removed;
}

List<VersionDelta> compareVersion(PmPlanVersion base, List<PmItem> current) {
  final cur = {for (final i in current) i.id: i};
  final seen = <String>{};
  final out = <VersionDelta>[];
  for (final b in base.items) {
    final c = cur[b.id];
    seen.add(b.id);
    if (c == null) {
      out.add(VersionDelta(title: b.title, base: b, removed: true));
      continue;
    }
    out.add(VersionDelta(
      title: c.title,
      base: b,
      current: c,
      startShift: daysBetween(c.plannedStart, b.start),
      endShift: daysBetween(c.plannedEnd, b.end),
      actualEndShift: c.actualEnd == null ? null : daysBetween(c.actualEnd!, b.end),
    ));
  }
  for (final c in current) {
    if (!seen.contains(c.id)) out.add(VersionDelta(title: c.title, current: c, added: true));
  }
  return out;
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
