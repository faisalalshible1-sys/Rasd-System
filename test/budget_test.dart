import 'package:dc_app/budget.dart';
import 'package:flutter_test/flutter_test.dart';

BudgetCommitment _c(String id, double amount, double paid, {String status = 'active', String line = 'L'}) =>
    BudgetCommitment(id: id, lineId: line, description: id, amount: amount, paid: paid, date: DateTime(2026, 3, 1), status: status);

void main() {
  const line = BudgetLine(id: 'L', year: 2026, category: 'صيانة', name: 'صيانة المقر', allocated: 200000);

  test('رصيد البند: مثال الفصل 7 (الإفراج لا يُحسب)', () {
    final s = budgetStatusOf(line, [
      _c('أ', 80000, 30000),
      _c('ب', 60000, 60000),
      _c('ج', 25000, 0, status: 'released'),
      _c('د', 99999, 0, line: 'غيره'),
    ]);
    expect(s.committed, 140000);
    expect(s.remaining, 60000);
    expect(s.usage, closeTo(0.70, 1e-9));
    expect(s.paid, 90000);
    expect(s.unpaid, 50000);
    expect(s.warn, isFalse);
    expect(s.exhausted, isFalse);
  });

  test('حد التنبيه 90% والاستنفاد', () {
    final warn = budgetStatusOf(line, [_c('أ', 180000, 0)]);
    expect(warn.usage, closeTo(0.9, 1e-9));
    expect(warn.warn, isTrue);
    expect(warn.exhausted, isFalse);
    final full = budgetStatusOf(line, [_c('أ', 200000, 0)]);
    expect(full.exhausted, isTrue);
    expect(full.remaining, 0);
  });

  test('بند بلا مخصص لا نسبة له ولا تنبيه', () {
    const zero = BudgetLine(id: 'L', year: 2026, category: 'ك', name: 'ن', allocated: 0);
    final s = budgetStatusOf(zero, const []);
    expect(s.usage, isNull);
    expect(s.warn, isFalse);
    expect(s.exhausted, isFalse);
  });

  test('مجموع السنة هو مجموع بنودها', () {
    const l2 = BudgetLine(id: 'M', year: 2026, category: 'معدات', name: 'أجهزة', allocated: 100000);
    final t = budgetTotal([line, l2], [_c('أ', 80000, 30000), _c('ب', 40000, 10000, line: 'M')]);
    expect(t.allocated, 300000);
    expect(t.committed, 120000);
    expect(t.paid, 40000);
    expect(t.remaining, 180000);
    expect(t.usage, closeTo(0.4, 1e-9));
  });

  test('تحليل الصفوف', () {
    final l = BudgetLine.fromMap({'id': 'x', 'fiscal_year': 2026, 'category': 'ك', 'name': 'ن', 'allocated': '1500.500', 'note': null});
    expect(l.allocated, 1500.5);
    expect(l.note, '');
    final c = BudgetCommitment.fromMap({
      'id': 'c', 'line_id': 'x', 'project_id': null, 'description': 'د', 'amount': 10, 'paid': 2.5, 'committed_on': '2026-03-01', 'status': 'active', 'note': ''
    });
    expect(c.unpaid, 7.5);
    expect(c.date, DateTime(2026, 3, 1));
    expect(c.projectId, isNull);
  });
}
