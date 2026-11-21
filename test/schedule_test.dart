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
}
