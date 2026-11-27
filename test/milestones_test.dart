import 'package:dc_app/maintenance.dart';
import 'package:dc_app/milestones.dart';
import 'package:dc_app/procurement.dart';
import 'package:flutter_test/flutter_test.dart';

PmMilestone _m(String id, DateTime planned, {DateTime? actual, DateTime? forecast, String status = 'pending'}) =>
    PmMilestone(id: id, projectId: 'p', title: id, planned: planned, actual: actual, forecast: forecast, status: status);

void main() {
  final today = DateTime(2026, 11, 27);

  test('المعالم: أيام التأخر وحالاتها (مثال الفصل 38)', () {
    final a = _m('أ', DateTime(2026, 11, 1), actual: DateTime(2026, 10, 30), status: 'done');
    final b = _m('ب', DateTime(2026, 11, 10), actual: DateTime(2026, 11, 14), status: 'done');
    final c = _m('ج', DateTime(2026, 11, 20));
    final d = _m('د', DateTime(2026, 12, 15), forecast: DateTime(2026, 12, 25));
    expect(a.lateDays(today), 0);
    expect(a.doneOnTime, isTrue);
    expect(b.lateDays(today), 4);
    expect(c.lateDays(today), 7);
    expect(c.isOverdue(today), isTrue);
    expect(d.isOverdue(today), isFalse);
    expect(d.slipping, isTrue);
    final r = kpiMilestones([a, b, c, d, _m('هـ', DateTime(2026, 11, 2), status: 'cancelled')], today);
    expect(r.sample, 3);
    expect(r.value!.round(), 33);
    expect(r.met, isFalse);
  });

  test('المعالم: المنجز قبل النافذة لا يدخل، وبلا عينة لا قيمة', () {
    final old = _m('قديم', DateTime(2026, 6, 1), actual: DateTime(2026, 6, 1), status: 'done');
    expect(kpiMilestones([old], today).value, isNull);
    expect(kpiMilestones([], today).value, isNull);
  });

  test('المشاريع: المنتظمة ومتوسط SPI الموزون (مثال الفصل 39)', () {
    final perfs = [...List.filled(4, 'on_track'), ...List.filled(2, 'ahead'), 'slight', 'critical', 'no_data', 'not_started'];
    expect(kpiProjectsOnTrack(perfs).value!.round(), 75);
    final spi = kpiProjectsSpi([(spi: 1.0, weight: 2000000), (spi: 0.8, weight: 1000000)], 0.95);
    expect(spi.value!.toStringAsFixed(2), '0.93');
    expect(kpiFormat(spi.value, ''), '0.93');
    expect(kpiProjectsSpi([(spi: 1.0, weight: 0), (spi: 0.5, weight: 0)], 0.95).value, 0.75);
    expect(kpiProjectsDelay([3, 4]).value, 7);
    expect(kpiProjectsDelay([0]).met, isTrue);
  });

  test('المخازن: سلامة المخزون (مثال الفصل 39)', () {
    expect(kpiStoresHealth(120, 18).value!.round(), 85);
    expect(kpiStoresHealth(120, 18).met, isFalse);
    expect(kpiStoresHealth(0, 0).value, isNull);
  });

  test('المؤشرات المخصصة: نسبة التحقق (مثال الفصل 39)', () {
    const hi = KpiDef(id: '1', name: 'نسبة الصرف', target: 90);
    expect(kpiAttainment(hi, 85.5), closeTo(0.95, 1e-9));
    const lo = KpiDef(id: '2', name: 'أيام المستخلص', target: 10, higherBetter: false);
    expect(kpiAttainment(lo, 12.5), closeTo(0.8, 1e-9));
    expect(kpiAttainment(lo, 8), 1);
    expect(kpiAttainment(const KpiDef(id: '3', name: 'س', target: 0), 5), isNull);
    final latest = kpiLatest(const [
      KpiValue(id: 'a', kpiId: '1', period: '2026-09', value: 1),
      KpiValue(id: 'b', kpiId: '1', period: '2026-11', value: 2),
      KpiValue(id: 'c', kpiId: '1', period: '2026-10', value: 3),
    ]);
    expect(latest!.period, '2026-11');
  });

  test('الصيغة والفترة', () {
    expect(kpiPeriodOf(DateTime(2026, 3, 5)), '2026-03');
    expect(kpiFormat(null, '%'), '—');
    expect(kpiFormat(33.4, '%'), '33%');
    expect(kpiFormat(9.0, 'ساعة'), '9 ساعة');
  });

  test('الاستيراد يبقى سليماً للأنواع المستعملة', () {
    expect(kpiWindowDays, 90);
    expect(MtRequest, isNotNull);
    expect(PrOrder, isNotNull);
  });
}
