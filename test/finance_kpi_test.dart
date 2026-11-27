import 'package:dc_app/budget.dart';
import 'package:dc_app/finance_kpi.dart';
import 'package:dc_app/models.dart';
import 'package:flutter_test/flutter_test.dart';

ContractExtract _x(String id, double net,
        {String status = 'approved', double paid = 0, DateTime? approved, DateTime? referred, DateTime? paidOn}) =>
    ContractExtract(
      id: id, projectId: 'p', originProject: null, workId: null, seq: 1, refNo: '', kind: 'interim',
      periodFrom: null, periodTo: null, submittedOn: null, gross: net, retention: 0, advanceRecovery: 0,
      penalties: 0, taxes: 0, otherDeductions: 0, net: net, status: status, approvedOn: approved,
      paidAmount: paid, paidOn: paidOn, notes: '', referredOn: referred,
    );

void main() {
  final now = DateTime(2026, 11, 27);

  test('الصرف في موعده: مثال الفصل 39', () {
    final xs = <ContractExtract>[
      // خمسة دُفعت في موعدها (الاعتماد + 30 يوماً ≥ الدفع)
      for (var i = 0; i < 5; i++)
        _x('م$i', 100, status: 'paid', paid: 100, approved: DateTime(2026, 10, 1), paidOn: DateTime(2026, 10, 20)),
      // واحد دُفع متأخراً
      _x('ت', 100, status: 'paid', paid: 100, approved: DateTime(2026, 9, 1), paidOn: DateTime(2026, 11, 1)),
      // مدفوع قبل النافذة: لا يدخل
      _x('ق', 100, status: 'paid', paid: 100, approved: DateTime(2026, 1, 1), paidOn: DateTime(2026, 2, 1)),
      // غير مدفوعين فات موعدهما
      _x('ف1', 100, approved: DateTime(2026, 9, 1)),
      _x('ف2', 100, status: 'referred', referred: DateTime(2026, 10, 1)),
      // غير مدفوع لم يفت موعده: لا يدخل
      _x('ل', 100, approved: DateTime(2026, 11, 20)),
    ];
    final r = kpiFinancePayOnTime(xs, now);
    expect(r.sample, 8);
    expect(r.value, closeTo(62.5, 1e-9));
    expect(r.met, isFalse);
  });

  test('الصرف في موعده بلا بيانات', () {
    expect(kpiFinancePayOnTime(const [], now).value, isNull);
  });

  test('المستحق الأقدم من 90 يوماً', () {
    final r = kpiFinanceOldDue([
      _x('أ', 60000, approved: DateTime(2026, 7, 1)),
      _x('ب', 340000, approved: DateTime(2026, 11, 1)),
      _x('ج', 500, status: 'paid', paid: 500, approved: DateTime(2026, 1, 1)),
    ], now);
    expect(r.value, closeTo(15, 1e-9));
    expect(r.met, isFalse);
    expect(r.sample, 2);
    expect(kpiFinanceOldDue(const [], now).value, isNull);
  });

  test('سلامة الميزانية', () {
    final lines = [
      for (var i = 0; i < 8; i++) BudgetLine(id: 'L$i', year: 2026, category: 'ك', name: 'ب$i', allocated: 100),
      const BudgetLine(id: 'Z', year: 2025, category: 'ك', name: 'قديم', allocated: 100),
    ];
    final cs = [BudgetCommitment(id: 'c', lineId: 'L0', description: 'د', amount: 90, date: now)];
    final r = kpiBudgetHealth(lines, cs, 2026);
    expect(r.sample, 8);
    expect(r.value, closeTo(87.5, 1e-9));
    expect(kpiBudgetHealth(lines, cs, 2030).value, isNull);
  });

  test('حركة الشهر: مثال الفصل 7', () {
    final xs = [
      _x('أ', 150000, approved: DateTime(2026, 10, 5)),
      _x('ب', 100000, status: 'referred', approved: DateTime(2026, 10, 9), referred: DateTime(2026, 10, 12)),
    ];
    final pays = {
      'أ': [ExtractPayment(id: 'p1', extractId: 'أ', projectId: 'p', amount: 40000, paidOn: DateTime(2026, 10, 20), method: 'transfer', refNo: '', notes: '')],
      'ب': [ExtractPayment(id: 'p2', extractId: 'ب', projectId: 'p', amount: 30000, paidOn: DateTime(2026, 10, 25), method: 'transfer', refNo: '', notes: '')],
    };
    final rows = monthlyFinance(xs, (id) => pays[id] ?? const [], now);
    expect(rows.length, 12);
    expect(rows.first.month, DateTime(2026, 11, 1));
    final oct = rows[1];
    expect(oct.month, DateTime(2026, 10, 1));
    expect(oct.approvedCount, 2);
    expect(oct.approvedNet, 250000);
    expect(oct.referredNet, 100000);
    expect(oct.paid, 70000);
    expect(oct.gap, 180000);
  });

  test('مستخلص بلا سجل دفعات يُنسب مدفوعه لتاريخ دفعه', () {
    final rows = monthlyFinance([_x('أ', 500, status: 'paid', paid: 500, approved: DateTime(2026, 8, 1), paidOn: DateTime(2026, 9, 3))], (_) => const [], now);
    expect(rows.firstWhere((r) => r.month == DateTime(2026, 9, 1)).paid, 500);
  });
}
