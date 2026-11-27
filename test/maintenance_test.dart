import 'package:dc_app/app_state.dart';
import 'package:dc_app/maintenance.dart';
import 'package:flutter_test/flutter_test.dart';

/// الإصدار 1.9.0 (الترحيل 40): قسم الصيانة — الإعدادات والمواعيد والمؤشرات وربط الصفحات بالقسم.
/// الأمثلة هي أمثلة الفصل 35 المحلولة.
void main() {
  test('الإعدادات المبدئية كما في الترحيل 40', () {
    const s = MtSettings();
    expect(s.slaHours('urgent'), 8);
    expect(s.slaHours('high'), 48);
    expect(s.slaHours('normal'), 120);
    expect(s.slaHours('low'), 240);
    expect(s.assignHours, 4);
    expect(s.holdDays, 7);
    expect(s.confirmDays, 3);
    expect(s.soonHours, 24);
    expect(s.repeatCount, 3);
    expect(s.repeatDays, 90);
    expect(s.planLeadDays, 7);
  });

  test('الإعدادات المحمَّلة تغلب المبدئية وما غاب يبقى مبدئياً', () {
    final s = MtSettings.fromRows([
      {'key': 'sla_hours', 'value': {'urgent': 4, 'low': 100}},
      {'key': 'hold_days', 'value': 10},
    ]);
    expect(s.slaHours('urgent'), 4);
    expect(s.slaHours('low'), 100);
    expect(s.slaHours('high'), 48);
    expect(s.holdDays, 10);
    expect(s.assignHours, 4);
  });

  test('نص تكرار الخطة', () {
    MtPlan p(String unit, int n) => MtPlan(id: 'p', planNo: 'MP-1', title: 't', intervalUnit: unit, intervalCount: n);
    expect(p('month', 1).intervalText, 'كل شهر');
    expect(p('month', 2).intervalText, 'كل شهرين');
    expect(p('month', 3).intervalText, 'كل 3 أشهر');
    expect(p('week', 12).intervalText, 'كل 12 أسبوعاً');
    expect(p('year', 1).intervalText, 'كل سنة');
    expect(p('day', 5).intervalText, 'كل 5 أيام');
  });

  test('الأيام إلى موعد الخطة والتنبيه المسبق', () {
    final plan = MtPlan(id: 'p', planNo: 'MP-1', title: 't', nextDue: DateTime(2026, 12, 10), leadDays: 3);
    expect(plan.daysToDue(DateTime(2026, 12, 7, 15)), 3);
    expect(plan.daysToDue(DateTime(2026, 12, 12)), -2);
    expect(plan.leadFor(const MtSettings()), 3);
    expect(const MtPlan(id: 'q', planNo: 'MP-2', title: 't').leadFor(const MtSettings()), 7);
    final data = MaintenanceData(plans: [plan]);
    expect(data.plansDue(DateTime(2026, 12, 7), 3), hasLength(1));
    expect(data.plansDue(DateTime(2026, 12, 1), 3), isEmpty);
  });

  test('نص الوقت المتبقي أو المتجاوز', () {
    final now = DateTime(2026, 12, 1, 12);
    expect(mtDueText(null, now), '');
    expect(mtDueText(now.add(const Duration(hours: 3)), now), 'بعد 3 ساعة');
    expect(mtDueText(now.add(const Duration(days: 1, hours: 2)), now), 'بعد يوم');
    expect(mtDueText(now.subtract(const Duration(days: 3)), now), 'متأخر 3 أيام');
    expect(mtDueText(now.subtract(const Duration(minutes: 20)), now), 'متأخر أقل من ساعة');
  });

  MtRequest req(String id, String status, {DateTime? reported, DateTime? due, DateTime? done, String tag = '', String source = 'report'}) =>
      MtRequest(id: id, reqNo: 'MR-2026-$id', title: 't', status: status, reportedAt: reported, dueAt: due, doneAt: done, assetTag: tag, assetName: tag, source: source);

  test('المؤشرات: الإنجاز في الموعد ومتوسط الساعات وأكثر الأصول', () {
    final t0 = DateTime(2026, 12, 1, 9);
    final data = MaintenanceData(requests: [
      req('1', 'closed', reported: t0, due: t0.add(const Duration(hours: 8)), done: t0.add(const Duration(hours: 6)), tag: 'A-1'),
      req('2', 'done', reported: t0, due: t0.add(const Duration(hours: 8)), done: t0.add(const Duration(hours: 10)), tag: 'A-1'),
      req('3', 'new', reported: t0, tag: 'B-2'),
      req('4', 'new', reported: t0, tag: 'B-2', source: 'plan'),
    ]);
    expect(data.onTimeRate, 0.5);
    expect(data.avgHours, 8);
    expect(data.countByStatus(), {'closed': 1, 'done': 1, 'new': 2});
    expect(data.awaitingConfirm.map((r) => r.id), ['2']);
    expect(data.unassigned, hasLength(2));
    expect(data.topAssets().first, ('A-1', 'A-1', 2));
    // بلاغات الصيانة الدورية لا تُحتسب أعطالاً
    expect(data.topAssets().firstWhere((e) => e.$1 == 'B-2').$3, 1);
  });

  test('ترتيب التنبيهات: الأشد أولاً', () {
    expect(mtAlertOrder.first, 'overdue');
    expect(mtAlertOrder.indexOf('unassigned'), lessThan(mtAlertOrder.indexOf('due_soon')));
    expect(mtAlertOrder.toSet(), mtAlertLabels.keys.toSet());
  });

  test('صفحات الصيانة 220–229 تتبع قسم «maintenance»', () {
    for (var t = 220; t <= 229; t++) {
      expect(AppState.sectionOf(t), 'maintenance');
    }
    expect(AppState.sectionOf(219), isNot('maintenance'));
    expect(AppState.sectionOf(240), isNot('maintenance'));
  });
}
