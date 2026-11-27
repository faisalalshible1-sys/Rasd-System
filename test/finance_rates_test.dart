import 'package:dc_app/finance_rates.dart';
import 'package:flutter_test/flutter_test.dart';

FinanceRate _r(String code, double p, String from, {String? to, bool active = true}) => FinanceRate(
      id: '$code$from',
      code: code,
      percent: p,
      basis: 'extract_gross',
      scope: 'contracts',
      active: active,
      from: DateTime.parse(from),
      to: to == null ? null : DateTime.parse(to),
    );

void main() {
  test('النسبة السارية في يوم معيّن بحسب تاريخ السريان', () {
    final all = [
      _r('income_tax', 3, '2026-01-01', to: '2026-12-31'),
      _r('income_tax', 3.5, '2027-01-01'),
    ];
    expect(rateAt(all, 'income_tax', DateTime(2026, 6, 1))?.percent, 3);
    expect(rateAt(all, 'income_tax', DateTime(2026, 12, 31))?.percent, 3);
    expect(rateAt(all, 'income_tax', DateTime(2027, 1, 1))?.percent, 3.5);
    expect(rateAt(all, 'income_tax', DateTime(2025, 12, 31)), isNull, reason: 'قبل أول إصدار لا نسبة');
    expect(rateAt(all, 'insurance', DateTime(2026, 6, 1)), isNull, reason: 'رمز بلا إصدارات');
  });

  test('النسبة المعطّلة لا تُطبَّق', () {
    final all = [_r('extra_rule', 3.75, '2026-01-01', active: false)];
    expect(rateAt(all, 'extra_rule', DateTime(2026, 6, 1)), isNull);
  });

  test('مبلغ النسبة: الأساس × النسبة ÷ 100 بثلاث منازل', () {
    expect(rateAmount(120000, 3), 3600);
    expect(rateAmount(1500, 2), 30);
    expect(rateAmount(1000.5, 3.75), 37.519);
    expect(rateAmount(0, 5), 0);
  });

  test('مبلغ الخصم: نسبة من الأساس أو ثابت', () {
    const pct = FinanceDeduction(id: '1', name: 'غياب', kind: 'percent', value: 2, basis: 'payroll_basic', appliesTo: 'payroll', active: true);
    const fixed = FinanceDeduction(id: '2', name: 'سلفة', kind: 'fixed', value: 500, basis: 'none', appliesTo: 'payroll', active: true);
    expect(pct.amountOn(1500), 30);
    expect(fixed.amountOn(1500), 500);
    expect(fixed.amountOn(0), 500);
  });

  test('قراءة الإصدار من صف قاعدة البيانات', () {
    final r = FinanceRate.fromMap({
      'id': 'a',
      'code': 'insurance',
      'percent': '5.0000',
      'basis': 'payroll_basic',
      'scope': 'employees',
      'active': true,
      'effective_from': '2026-01-01',
      'effective_to': null,
      'reason': 'س',
    });
    expect(r.percent, 5);
    expect(r.to, isNull);
    expect(r.coversDay(DateTime(2030, 1, 1)), isTrue);
  });
}
