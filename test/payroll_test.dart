import 'package:dc_app/finance_rates.dart';
import 'package:dc_app/payroll.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const cfg = PayrollConfig();

  test('الأجر اليومي والساعي: 30 يوماً و42 ساعة أسبوعياً', () {
    expect(cfg.daily(3000), 100);
    expect(cfg.hourly(2100), 10);
  });

  test('مثال الدليل: صافي موظف بغياب وإضافي ومكافأة وتأمينات وخصومين', () {
    const pct = FinanceDeduction(id: '1', name: 'صندوق', kind: 'percent', value: 2, basis: 'payroll_basic', appliesTo: 'payroll', active: true);
    const fixed = FinanceDeduction(id: '2', name: 'ثابت', kind: 'fixed', value: 50, basis: 'none', appliesTo: 'payroll', active: true);
    final r = computePayLine(
      cfg: cfg,
      basic: 3000,
      allowances: 300,
      absentDays: 2,
      overtimeHours: 6,
      bonuses: 200,
      insurance: (percent: 5, onGross: false),
      deductions: [(d: pct, override: null), (d: fixed, override: 80)],
    );
    expect(r.overtimeAmount, 128.571);
    expect(r.gross, 3628.571);
    expect(r.absence, 200);
    expect(r.insurance, 150);
    expect(r.other, 140);
    expect(r.net, 3138.571);
  });

  test('نسبة على الإجمالي وخصم نسبة بلا أساس راتبي يُهمَل', () {
    const bad = FinanceDeduction(id: '3', name: 'س', kind: 'percent', value: 10, basis: 'extract_gross', appliesTo: 'payroll', active: true);
    final r = computePayLine(cfg: cfg, basic: 1000, tax: (percent: 3, onGross: true), deductions: [(d: bad, override: null)]);
    expect(r.tax, 30);
    expect(r.other, 0);
    expect(r.net, 970);
  });

  test('قسط السلفة الثابت وآخر قسط يأخذ الباقي', () {
    expect(loanInstallment(1000, 3, 0), 333.333);
    expect(loanInstallment(1000, 3, 1), 333.333);
    expect(loanInstallment(1000, 3, 2), 333.334);
    expect(loanInstallment(1000, 3, 3), 0);
    expect(loanInstallment(1000, 3, -1), 0);
    final loan = FinLoan(id: '1', employeeId: 'e', total: 1000, installments: 3, start: DateTime(2026, 3), active: true);
    expect(loan.installmentIn(DateTime(2026, 2)), 0);
    expect(loan.installmentIn(DateTime(2026, 5)), 333.334);
    expect(loan.installmentIn(DateTime(2026, 6)), 0);
  });

  test('مجاميع الكشف', () {
    FinPayrollLine l(double g, double ab, double n) => FinPayrollLine(
        payrollId: 'p', employeeId: 'e', name: 'ن', title: '', basic: 0, allowances: 0, overtimeHours: 0, overtimeAmount: 0,
        bonuses: 0, gross: g, absentDays: 0, absence: ab, insurance: 0, tax: 0, extraRule: 0, other: 0, otherDetail: const [], loan: 0, net: n);
    final t = payrollTotals([l(1000, 50, 950), l(2000, 0, 2000)]);
    expect(t.count, 2);
    expect(t.gross, 3000);
    expect(t.deductions, 50);
    expect(t.net, 2950);
  });

  test('قراءة إعدادات الاحتساب وصف الكشف', () {
    final c = PayrollConfig.fromRows([
      {'key': 'days_in_month', 'value': '26'},
      {'key': 'overtime_factor', 'value': 2},
    ]);
    expect(c.daysInMonth, 26);
    expect(c.weeklyHours, 42);
    expect(c.overtimeFactor, 2);
    expect(periodIso(DateTime(2026, 3, 15)), '2026-03-01');
    expect(periodLabel(DateTime(2026, 3)), '2026/03');
  });
}
