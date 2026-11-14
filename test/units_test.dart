import 'package:dc_app/units.dart';
import 'package:flutter_test/flutter_test.dart';

/// اختبارات سجلات الوحدات ومؤشراتها: الأمثلة المحلولة في الفصول 19–22 من الدليل تُحسب هنا بالشيفرة نفسها.
void main() {
  final today = DateTime(2026, 11, 14);
  String day(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  var seq = 0;
  UnitRecord rec(String kind,
      {String? status, String level = '', DateTime? date, DateTime? due, DateTime? closed, double? progress, Map<String, dynamic> data = const {}, String? parent}) {
    final k = unitKinds[kind]!;
    seq++;
    return UnitRecord.fromMap({
      'id': 'r$seq', 'unit': k.unit, 'kind': kind, 'title': 'سجل $seq', 'rec_date': day(date ?? today), 'status': status ?? k.defaultStatus,
      'level': level, 'due_date': due == null ? null : day(due), 'closed_at': closed == null ? null : day(closed), 'progress': progress,
      'data': data, 'parent_id': parent,
    });
  }

  test('مواصفات الأنواع الثلاثة عشر تطابق قاعدة البيانات', () {
    expect(unitKinds.length, 13);
    for (final k in unitKinds.values) {
      expect(unitKeys.contains(k.unit), isTrue, reason: k.key);
      expect(unitKindsOf[k.unit], contains(k.key));
      expect(k.closed.every((c) => k.statuses.any((s) => s.$1 == c)), isTrue, reason: 'حالة مغلقة غير معروفة في ${k.key}');
      if (k.parent != null) expect(unitKinds[k.parent!]!.unit, k.unit, reason: 'السجل الأم من الوحدة نفسها');
    }
    expect(unitsOfSection('planning_qa'), ['planning', 'quality_assurance', 'follow_up']);
    expect(unitsOfSection('acceptance'), ['receiving', 'quality_control']);
    expect(unitKinds['handover']!.children.map((k) => k.key), ['punch_item']);
    expect(unitKinds['punch_item']!.hasLevels, isFalse);
    expect(unitKinds['qa_audit']!.defaultLevel, '');
  });

  test('المتأخر والمغلق والأيام المتبقية', () {
    final late = rec('followup_task', due: DateTime(2026, 11, 10));
    final done = rec('followup_task', status: 'done', due: DateTime(2026, 11, 10), closed: DateTime(2026, 11, 12));
    final soon = rec('followup_task', due: DateTime(2026, 11, 16));
    expect(late.overdue(today), isTrue);
    expect(late.daysLeft(today), -4);
    expect(done.isClosed, isTrue);
    expect(done.overdue(today), isFalse);
    expect(soon.daysLeft(today), 2);
  });

  test('النموذج: الحقول الخاصة في data والنسبة من 0–1 إلى 0–100', () {
    final k = unitKinds['plan']!;
    final p = unitPayload(k, {'title': 'خطة', 'progress': 0.625, 'f_kpi': 'مؤشر', 'f_budget': 1200.0, 'f_target': '  '}, create: true);
    expect(p['kind'], 'plan');
    expect(p['progress'], 62.5);
    expect(p['data'], {'kpi': 'مؤشر', 'budget': 1200.0});
    final r = rec('plan', progress: 40, data: {'kpi': 'مؤشر'});
    expect(r.toForm()['progress'], 0.4);
    expect(r.toForm()['f_kpi'], 'مؤشر');
  });

  test('الفصل 21: أيام بلا حوادث ومتوسط الالتزام', () {
    final idx = UnitIndex([
      rec('safety_incident', level: 'minor', date: DateTime(2026, 10, 20)),
      rec('safety_incident', level: 'near_miss', date: DateTime(2026, 11, 5)),
      rec('safety_inspection', date: DateTime(2026, 11, 2), data: {'score': 72}),
      rec('safety_inspection', date: DateTime(2026, 11, 6), data: {'score': 85}),
      rec('safety_inspection', date: DateTime(2026, 11, 9), data: {'score': 90}),
      rec('safety_inspection', date: DateTime(2026, 10, 28), data: {'score': 40}),
    ]);
    final s = UnitStats(idx, today);
    expect(s.daysWithoutIncident, 25);
    expect(s.avgComplianceThisMonth!.round(), 82);
    expect(s.inspectionsThisMonth, 3);
    expect(s.incidentsThisYear, 1);
    expect(s.nearMissesThisYear, 1);
    expect(UnitStats(UnitIndex([rec('safety_incident', level: 'near_miss')]), today).daysWithoutIncident, isNull);
  });

  test('الفصل 22: نسبة المطابقة لا تدخل فيها الاختبارات المعلقة', () {
    final idx = UnitIndex([
      for (var i = 0; i < 18; i++) rec('qc_test', status: 'passed'),
      for (var i = 0; i < 2; i++) rec('qc_test', status: 'failed'),
      for (var i = 0; i < 3; i++) rec('qc_test'),
    ]);
    final s = UnitStats(idx, today);
    expect(s.passRate, 0.9);
    expect(s.pendingTests, 3);
    expect(UnitStats(UnitIndex([rec('qc_test')]), today).passRate, isNull);
  });

  test('الفصل 20: متوسط إنجاز الخطط والإنجاز في الموعد', () {
    final plans = UnitIndex([
      rec('plan', status: 'active', progress: 40),
      rec('plan', status: 'active', progress: 65),
      rec('plan', status: 'active', progress: 70),
      rec('plan', status: 'active'),
      rec('plan', status: 'done', progress: 100),
    ]);
    expect(UnitStats(plans, today).avgActiveProgress!.round(), 58);
    final due = DateTime(2026, 11, 1);
    final tasks = UnitIndex([
      for (var i = 0; i < 9; i++) rec('followup_task', status: 'done', due: due, closed: DateTime(2026, 10, 30)),
      for (var i = 0; i < 3; i++) rec('followup_task', status: 'done', due: due, closed: DateTime(2026, 11, 3)),
      rec('followup_task', status: 'done', closed: DateTime(2026, 11, 3)),
    ]);
    expect(UnitStats(tasks, today).onTimeRate, 0.75);
  });

  test('الفصل 19: المباني بحالة سيئة أو خطرة وآخر تقييم', () {
    final b = rec('heritage_building', level: 'poor', status: 'under_restoration');
    final idx = UnitIndex([
      b,
      rec('heritage_building', level: 'critical'),
      rec('heritage_building', level: 'good', status: 'restored'),
      rec('heritage_assessment', parent: b.id, level: 'fair', date: DateTime(2026, 9, 1)),
      rec('heritage_assessment', parent: b.id, level: 'poor', date: DateTime(2026, 11, 1)),
    ]);
    final s = UnitStats(idx, today);
    expect(s.buildings, 3);
    expect(s.buildingsAtRisk, 2);
    expect(s.underRestoration, 1);
    expect(s.restored, 1);
    expect(s.latestAssessment(b.id)!.level, 'poor');
    expect(s.assessmentsThisYear, 2);
  });
}
