import 'package:dc_app/lifecycle.dart';
import 'package:dc_app/models.dart';
import 'package:dc_app/pm.dart';
import 'package:dc_app/prices.dart';
import 'package:dc_app/schedule.dart';
import 'package:flutter_test/flutter_test.dart';

// المثال المحلول في الفصل 29 من الدليل بالمعادلات نفسها، وحساب المقايسة في الفصل 28.
void main() {
  final ref = DateTime(2026, 11, 14);
  final cfg = PmConfig.fromJson({'ref_date': '2026-11-14'});
  final project = Project.fromMap({'id': 'p1', 'assign_no': 'T-29', 'name': 'عقد المثال', 'sort_order': 1});

  PmItem item(String id, String title, DateTime s, DateTime e, double? w, double progress, {int sort = 0}) => PmItem(
      id: id, projectId: 'p1', title: title, plannedStart: s, plannedEnd: e, weight: w, progress: progress, sort: sort);

  final items = [
    item('a', 'أعمال الحفر والردم', DateTime(2026, 9, 1), DateTime(2026, 10, 31), 200000, 100, sort: 10),
    item('b', 'الأعمال الخرسانية', DateTime(2026, 10, 1), DateTime(2027, 1, 28), 500000, 30, sort: 20),
    item('c', 'التشطيبات', DateTime(2026, 12, 1), DateTime(2027, 2, 28), null, 0, sort: 30),
  ];

  test('حساب البند: المدة والمنقضي والمخطط والانحراف بالنقاط وبالأيام', () {
    final a = ItemCalc(items[0], ref, cfg);
    expect(a.duration, 60);
    expect(a.elapsed, 60);
    expect(a.planned, 100);
    expect(a.status, 'done');

    final b = ItemCalc(items[1], ref, cfg);
    expect(b.duration, 119);
    expect(b.elapsed, 44);
    expect(b.planned, closeTo(36.97, 0.01));
    expect(b.variance, closeTo(-6.97, 0.01));
    expect(b.daysVariance, closeTo(-8.3, 0.01));
    expect(b.spi, closeTo(0.81, 0.01));
    expect(b.status, 'critical');
    expect(b.isLate, isTrue);
    expect(b.forecastEnd, DateTime(2027, 2, 25));
    expect(b.forecastDelay, 28);
    expect(b.overdueDays, isNull);

    final c = ItemCalc(items[2], ref, cfg);
    expect(c.elapsed, 0);
    expect(c.planned, 0);
    expect(c.status, 'not_started');
  });

  test('النسبة الكلية الموزونة وحالة المشروع (الوزن الفارغ = متوسط المسجلة)', () {
    final t = ScheduleTrack(project, items, ref, cfg);
    expect(t.weights, [200000, 500000, 350000]);
    expect(t.shares.map((s) => (s * 10).round() / 10).toList(), [19.0, 47.6, 33.3]);
    expect(t.actual, closeTo(33.33, 0.01));
    expect(t.planned, closeTo(36.65, 0.01));
    expect(t.variance, closeTo(-3.32, 0.01));
    expect(t.spi, closeTo(0.91, 0.01));
    expect(t.perf, 'slight');
    expect(t.lateItems.length, 1);
    expect(t.doneItems, 1);
    expect(t.start, DateTime(2026, 9, 1));
    expect(t.end, DateTime(2027, 2, 28));
  });

  test('بلا أوزان: أوزان متساوية، وبند متجاوز لنهايته', () {
    final late = item('d', 'بند متجاوز', DateTime(2026, 10, 1), DateTime(2026, 11, 1), null, 50);
    final ok = item('e', 'بند في موعده', DateTime(2026, 11, 1), DateTime(2026, 11, 27), null, 50);
    final t = ScheduleTrack(project, [late, ok], ref, cfg);
    expect(t.weights, [1, 1]);
    final d = t.calcs.firstWhere((c) => c.item.id == 'd');
    expect(d.planned, 100);
    expect(d.overdueDays, 13);
    expect(d.status, 'critical');
    final e = t.calcs.firstWhere((c) => c.item.id == 'e');
    expect(e.planned, 50);
    expect(e.status, 'on_track');
    expect(t.actual, 50);
    expect(t.planned, 75);
  });

  test('المحفظة: المتأخرة والمتقدمة والبنود المتأخرة الأكبر انحرافاً أولاً', () {
    final p2 = Project.fromMap({'id': 'p2', 'assign_no': 'T-30', 'name': 'عقد متقدم', 'sort_order': 2});
    final ahead = PmItem(
        id: 'x', projectId: 'p2', title: 'بند متقدم', plannedStart: DateTime(2026, 11, 1), plannedEnd: DateTime(2026, 12, 1), progress: 60);
    final s = ScheduleAnalysis(projects: [project, p2], items: [...items, ahead], cfg: cfg);
    expect(s.tracks.length, 2);
    expect(s.lateProjects, 1);
    expect(s.aheadProjects, 1);
    expect(s.lateItems.first.$2.item.id, 'b');
  });

  test('حدود SPI من الإعدادات', () {
    final strict = PmConfig.fromJson({'ref_date': '2026-11-14', 'spi_warn': 0.8});
    expect(ItemCalc(items[1], ref, strict).status, 'slight');
  });

  test('المقايسة: إجمالي البند = الكمية × السعر، والكمية الفارغة صفر، وما يُرسل للحفظ', () {
    final l1 = BoqLine(seq: 200, code: '3.2.6.5', desc: 'أعمدة', unit: 'م3', price: 1880.75, qty: 45);
    final l2 = BoqLine(seq: 900, code: '7.2.2.1', desc: 'رخام', unit: 'م2', price: 287.5, qty: 120);
    final l3 = BoqLine(desc: 'تنظيف نهائي للموقع', unit: 'مقطوعية', price: 2500, qty: 1);
    final l4 = BoqLine(seq: 901, desc: 'بلا كمية', unit: 'م2', price: 100);
    expect(l1.total, 84633.75);
    expect([l1, l2, l3, l4].fold<double>(0, (s, l) => s + (l.total ?? 0)), 121633.75);
    expect(l4.total, 0);
    expect(l1.toJson(), {'seq': 200, 'qty': 45.0, 'notes': ''});
    expect(l3.toJson()['desc'], 'تنظيف نهائي للموقع');
    expect(isPriceCode('7.2.2'), isTrue);
    expect(isPriceCode('٧.٢'), isTrue);
    expect(isPriceCode('خرسانة'), isFalse);
  });

  // ------------------------------------------------------------------ الفصل 29: البرنامج حيّ (أمثلة الدليل)
  group('حساب تواريخ البرنامج من المراحل والمدد والتبعيات', () {
    final start = DateTime(2026, 1, 1);
    const ph = [
      PmPhase(id: 'f1', projectId: 'p1', sort: 10, name: 'الأعمال التمهيدية'),
      PmPhase(id: 'f2', projectId: 'p1', sort: 20, name: 'الأعمال الخرسانية'),
      PmPhase(id: 'f3', projectId: 'p1', sort: 30, name: 'أعمال تكسيات الحوائط والأرضيات والوزرات'),
      PmPhase(id: 'f4', projectId: 'p1', sort: 40, name: 'بنود أخرى'),
    ];
    PmItem b(String id, String phase, int sort, int days, {int offset = 0, String? dep}) => PmItem(
        id: id, projectId: 'p1', title: id, plannedStart: start, plannedEnd: start, sort: sort, phaseId: phase, durationDays: days,
        offsetDays: offset, dependsOn: dep);
    final generated = [
      b('i4', 'f1', 10, 13),
      b('i19', 'f1', 20, 15),
      b('i201', 'f2', 30, 72),
      b('i376', 'f3', 40, 28),
      b('free', 'f4', 50, 5),
    ];

    test('التوزيع المبدئي: 15 + 72 + 28 + 5 = 120 يوماً، والبنود متوازية داخل المرحلة', () {
      final l = PlanLayout(start, ph, generated);
      expect(l.totalDays, 120);
      expect(l.dates['i4'], (DateTime(2026, 1, 1), DateTime(2026, 1, 14)));
      expect(l.dates['i201'], (DateTime(2026, 1, 16), DateTime(2026, 3, 29)));
      expect(l.dates['i376'], (DateTime(2026, 3, 29), DateTime(2026, 4, 26)));
      expect(l.end, DateTime(2026, 5, 1));
      expect(l.spans.map((s) => s.days).toList(), [15, 72, 28, 5]);
    });

    test('تعديل مدة وإزاحة وتبعية وفاصل يعيد حساب ما بعده: 125 ثم 128 ثم 138 ثم 136 يوماً', () {
      var items = [for (final i in generated) i.id == 'i19' ? i.copyWith(durationDays: 20) : i];
      expect(PlanLayout(start, ph, items).totalDays, 125);
      items = [for (final i in items) i.id == 'i376' ? i.copyWith(offsetDays: 3) : i];
      expect(PlanLayout(start, ph, items).totalDays, 128);
      items = [...items, b('x', 'f2', 60, 10, dep: 'i201')];
      final l = PlanLayout(start, ph, items);
      expect(l.dates['x'], (DateTime(2026, 4, 3), DateTime(2026, 4, 13)));
      expect(l.totalDays, 138);
      final lagged = [for (final p in ph) p.id == 'f2' ? PmPhase(id: p.id, projectId: p.projectId, sort: p.sort, name: p.name, lagDays: -2) : p];
      expect(PlanLayout(start, lagged, items).totalDays, 136);
    });
  });

  // ------------------------------------------------------------------ الفصل 30: المثال المحلول للترجمة إلى المخاطر
  test('العقد في 2026/02/19: الفعلي 38.4% والمخطط 43.8% وفارق 7 أيام، والبند المتجاوز 29 يوماً', () {
    final c19 = PmConfig.fromJson({'ref_date': '2026-02-19'});
    PmItem i(String id, DateTime s, DateTime e, double w, double pr, {bool na = false, DateTime? ae}) => PmItem(
        id: id, projectId: 'p1', title: id, plannedStart: s, plannedEnd: e, weight: w, progress: pr, notApplicable: na, actualEnd: ae);
    final t = ScheduleTrack(
      project,
      [
        i('1.1.1.1', DateTime(2026, 1, 1), DateTime(2026, 1, 14), 6500, 100, ae: DateTime(2026, 1, 15)),
        i('1.2.1.1', DateTime(2026, 1, 1), DateTime(2026, 1, 21), 9250, 0),
        i('3.2.6.5', DateTime(2026, 1, 19), DateTime(2026, 3, 20), 75230, 55),
        i('سياج', DateTime(2026, 3, 20), DateTime(2026, 3, 30), 1200, 0, na: true),
        i('7.2.2.1', DateTime(2026, 4, 2), DateTime(2026, 4, 30), 28750, 0),
        i('تنظيف', DateTime(2026, 4, 30), DateTime(2026, 5, 5), 5000, 0),
      ],
      DateTime(2026, 2, 19),
      c19,
      plan: PmPlan(id: 'pl', projectId: 'p1', status: 'approved', startDate: DateTime(2026, 1, 1)),
    );
    expect(t.allItems.length, 6);
    expect(t.items.length, 5, reason: '«لا ينطبق» خارج الحساب');
    expect(t.actual, closeTo(38.38, 0.01));
    expect(t.planned, closeTo(43.79, 0.01));
    expect(t.perf, 'slight');
    expect(t.totalDays, 124);
    expect(t.daysVariance, -7);
    final over = t.calcOf('1.2.1.1')!;
    expect(over.overdueDays, 29);
    expect(over.behindDays, 29);
    expect(t.shares[t.items.indexWhere((x) => x.id == '1.2.1.1')], closeTo(7.42, 0.01));
    expect(over.projectedEnd, DateTime(2026, 3, 11));
    final col = t.calcOf('3.2.6.5')!;
    expect(col.status, 'ahead');
    expect(col.projectedEnd, DateTime(2026, 3, 17));
    expect(t.projectedEnd, DateTime(2026, 5, 5));
    expect(t.forecastDelay, 0);
  });

  test('دورة حياة العقد: حالة المرحلة ونسبتها من نماذجها', () {
    FormDef d(String k) => FormDef.fromMap({'key': k, 'name': k, 'stage': 1, 'sort': 1, 'active': true});
    LifeForm f(String k, FormStatus s) => LifeForm(d(k), s, null);
    expect(formsStatus([f('f25', FormStatus.done), f('f16', FormStatus.done)]), (FormStatus.done, 100.0));
    expect(formsStatus([f('f25', FormStatus.done), f('f16', FormStatus.todo)]), (FormStatus.wip, 50.0));
    expect(formsStatus([f('f25', FormStatus.todo), f('f16', FormStatus.na)]), (FormStatus.todo, 0.0));
    expect(formsStatus([f('f25', FormStatus.na), f('f16', FormStatus.na)]).$1, FormStatus.na);
    final life = lifecycleOf(
      formDefs: [for (final k in ['f02', 'f08', 'f25', 'f16', 'f18']) d(k)],
      statuses: {'f02': FormStatus.done, 'f08': FormStatus.done, 'f25': FormStatus.wip},
    );
    expect(life.map((p) => p.name).toList(), ['أمر العمل', 'التنفيذ', 'الاستلام الابتدائي', 'المستخلصات', 'الاستلام النهائي', 'إقفال العقد']);
    expect(life[0].status, FormStatus.done);
    expect(life[2].status, FormStatus.wip);
    expect(life[3].status, FormStatus.na);
    expect(life[5].status, FormStatus.todo);
    expect(currentPhaseIndex(life), 2);
  });
}
