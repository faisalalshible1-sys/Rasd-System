import 'package:dc_app/registers.dart';
import 'package:flutter_test/flutter_test.dart';

/// إجراءات الاستجابة ومخاطر الأقسام (الترحيل 43): القسم من بادئة المفتاح، والتأخر، وخطر المكتب.
void main() {
  Risk risk({String? key, String? project}) =>
      Risk(id: 'r', code: 'R01', description: 'خطر', probability: 3, impact: 3, autoKey: key, projectId: project);

  test('قسم الخطر التلقائي من بادئة مفتاحه', () {
    expect(risk(key: 'st_item:abc').section, 'stores');
    expect(risk(key: 'pr_order:abc').section, 'procurement');
    expect(risk(key: 'mt_req:abc').section, 'maintenance');
    expect(risk(key: 'pm_item:abc').section, isNull, reason: 'مخاطر البرنامج الزمني ليست من قسم');
    expect(risk().section, isNull);
    expect(riskSectionLabels.keys.toSet(), {'stores', 'procurement', 'maintenance'});
  });

  test('خطر المكتب: بلا مشروع', () {
    expect(risk().isOffice, isTrue);
    expect(risk(project: 'p1').isOffice, isFalse);
  });

  test('تأخر الإجراء: مفتوح وفات موعده قبل اليوم فقط', () {
    final today = DateTime(2026, 11, 27);
    RiskAction a({DateTime? due, String status = 'open'}) => RiskAction(id: 'a', riskId: 'r', title: 'إجراء', dueDate: due, status: status);
    expect(a(due: DateTime(2026, 11, 26)).isLate(today), isTrue);
    expect(a(due: DateTime(2026, 11, 27)).isLate(today), isFalse, reason: 'موعده اليوم لم يفت');
    expect(a(due: DateTime(2026, 11, 20), status: 'done').isLate(today), isFalse);
    expect(a(due: DateTime(2026, 11, 20), status: 'cancelled').isLate(today), isFalse);
    expect(a().isLate(today), isFalse, reason: 'بلا موعد');
  });

  test('قراءة الإجراء من صف الجدول', () {
    final a = RiskAction.fromMap({'id': 'x', 'risk_id': 'r', 'title': 'عنوان', 'owner': 'م. أحمد', 'due_date': '2026-12-20', 'status': 'done', 'done_on': '2026-12-01'});
    expect(a.dueDate, DateTime(2026, 12, 20));
    expect(a.doneOn, DateTime(2026, 12, 1));
    expect(a.isOpen, isFalse);
    expect(riskActionStatusLabels['cancelled'], 'ملغى');
  });
}
