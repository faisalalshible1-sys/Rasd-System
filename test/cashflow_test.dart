import 'package:dc_app/budget.dart';
import 'package:dc_app/cashflow.dart';
import 'package:dc_app/models.dart';
import 'package:flutter_test/flutter_test.dart';

ContractExtract _x(String id, double net, String status,
        {double paid = 0, DateTime? approved, DateTime? referred}) =>
    ContractExtract(
      id: id, projectId: 'p', originProject: null, workId: null, seq: 1, refNo: '', kind: 'interim',
      periodFrom: null, periodTo: null, submittedOn: null, gross: net, retention: 0, advanceRecovery: 0,
      penalties: 0, taxes: 0, otherDeductions: 0, net: net, status: status, approvedOn: approved,
      paidAmount: paid, paidOn: null, notes: '', referredOn: referred,
    );

void main() {
  final today = DateTime(2026, 11, 27);

  test('التدفق النقدي: مثال الفصل 7', () {
    final f = cashForecast([
      _x('أ', 100000, 'referred', referred: DateTime(2026, 10, 15)),
      _x('ب', 80000, 'approved', paid: 20000, approved: DateTime(2026, 11, 10)),
      _x('ج', 50000, 'referred', referred: DateTime(2026, 11, 25)),
      _x('د', 30000, 'approved'),
      _x('هـ', 10000, 'approved', approved: DateTime(2027, 5, 20)),
      _x('و', 40000, 'submitted'),
      _x('ز', 90000, 'paid', paid: 90000, approved: DateTime(2026, 9, 1)),
      _x('ح', 70000, 'draft'),
    ], today, commitments: [
      BudgetCommitment(id: 'c', lineId: 'L', description: 'd', amount: 80000, paid: 30000, date: today),
      BudgetCommitment(id: 'r', lineId: 'L', description: 'd', amount: 99000, paid: 0, date: today, status: 'released'),
    ]);
    expect(f.overdue, 100000);
    expect(f.months[0].$2, 0);
    expect(f.months[1].$1, DateTime(2026, 12, 1));
    expect(f.months[1].$2, 110000);
    expect(f.later, 10000);
    expect(f.undated, 30000);
    expect(f.pending, 40000);
    expect(f.commitments, 50000);
    expect(f.total, 250000);
  });

  test('موعد اليوم نفسه ليس متأخراً، ونهاية الأفق', () {
    final due = DateTime(2026, 11, 27).subtract(const Duration(days: cashPayLagDays));
    final f = cashForecast([_x('أ', 5000, 'approved', approved: due)], today);
    expect(f.overdue, 0);
    expect(f.months[0].$2, 5000);
    final far = cashForecast([_x('ب', 7000, 'approved', approved: DateTime(2027, 4, 28))], today);
    expect(far.months[5].$2, 7000); // الموعد 2027/05/28 = الشهر السادس
    expect(cashDueOf(_x('ج', 1, 'paid', paid: 1, approved: today)), isNull);
  });
}
