import 'package:flutter_test/flutter_test.dart';
import 'package:dc_app/guarantees.dart';

void main() {
  FinTransfer t(String id, String from, String to, double amt, String st) =>
      FinTransfer(id: id, fromId: from, toId: to, amount: amt, date: DateTime(2026, 3, 1), status: st);

  test('مثال الدليل: الرصيد من الافتتاحي والتحويلات المرحَّلة وحدها', () {
    const cash = FinAccount(id: 'a1', name: 'الخزينة', kind: 'cash', opening: 10000, active: true);
    const bank = FinAccount(id: 'a2', name: 'المصرف', kind: 'bank', opening: 0, active: true);
    final ts = [t('1', 'a1', 'a2', 4000.25, 'posted'), t('2', 'a2', 'a1', 9000, 'rejected'), t('3', 'a1', 'a2', 1, 'pending')];
    expect(accountBalance(cash, ts), 5999.75);
    expect(accountBalance(bank, ts), 4000.25);
  });

  FinGuarantee g(String st, DateTime? exp, {double amt = 100}) =>
      FinGuarantee(id: 'g', kind: 'final', party: 'ج', amount: amt, issued: DateTime(2026, 1, 1), status: st, expires: exp);

  test('حالة الانتهاء: منتهٍ وقريب وسليم، والمُسترد لا ينتهي', () {
    final today = DateTime(2026, 6, 1);
    expect(guaranteeExpiry(g('held', DateTime(2026, 5, 31)), today), 'expired');
    expect(guaranteeExpiry(g('held', DateTime(2026, 6, 1)), today), 'soon');
    expect(guaranteeExpiry(g('held', DateTime(2026, 7, 1)), today), 'soon');
    expect(guaranteeExpiry(g('held', DateTime(2026, 7, 2)), today), 'ok');
    expect(guaranteeExpiry(g('held', null), today), 'none');
    expect(guaranteeExpiry(g('released', DateTime(2026, 5, 1)), today), 'none');
  });

  test('مجاميع الضمانات بحسب الحالة وعدد المنتهية أو القريبة', () {
    final today = DateTime(2026, 6, 1);
    final tot = guaranteeTotals([
      g('held', DateTime(2026, 5, 1), amt: 55000),
      g('release_requested', null, amt: 8000.5),
      g('released', DateTime(2026, 1, 1), amt: 100),
      g('held', DateTime(2027, 1, 1), amt: 10),
    ], today);
    expect(tot.held, 55010);
    expect(tot.requested, 8000.5);
    expect(tot.released, 100);
    expect(tot.expiring, 1);
  });
}
