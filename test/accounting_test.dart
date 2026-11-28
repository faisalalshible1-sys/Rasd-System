import 'package:flutter_test/flutter_test.dart';
import 'package:dc_app/accounting.dart';

void main() {
  GlAccount a(String id, String code, String type) => GlAccount(id: id, code: code, name: code, type: type, postable: true, active: true);
  JournalEntry j(String id, int no, DateTime d, {String status = 'posted'}) =>
      JournalEntry(id: id, entryNo: no, date: d, memo: 'م$no', source: 'manual', status: status);
  JournalLine l(String j, int n, String acc, double d, double c) => JournalLine(journalId: j, lineNo: n, accountId: acc, debit: d, credit: c);

  final cash = a('c', '1110', 'asset'), bank = a('b', '1120', 'asset'), eq = a('e', '3100', 'equity');
  final journals = [
    j('j1', 1, DateTime(2027, 4, 1)),
    j('j2', 2, DateTime(2027, 4, 10)),
    j('j3', 3, DateTime(2027, 4, 12), status: 'draft'),
  ];
  final lines = [
    l('j1', 1, 'c', 10000, 0), l('j1', 2, 'e', 0, 10000),
    l('j2', 1, 'b', 1200.5, 0), l('j2', 2, 'c', 0, 1200.5),
    l('j3', 1, 'c', 999, 0), l('j3', 2, 'e', 0, 999),
  ];

  test('مثال الدليل: ميزان نيسان بالجانب الطبيعي والمسودة خارجه', () {
    final rows = trialBalance([cash, bank, eq], journals, lines, DateTime(2027, 4, 1), DateTime(2027, 4, 30));
    final byCode = {for (final r in rows) r.account.code: r};
    expect(byCode['1110']!.debit, 10000);
    expect(byCode['1110']!.credit, 1200.5);
    expect(byCode['1110']!.closing, 8799.5);
    expect(byCode['1120']!.closing, 1200.5);
    expect(byCode['3100']!.credit, 10000);
    expect(byCode['3100']!.closing, 10000);
    final t = trialTotals(rows);
    expect(t.debit, 11200.5);
    expect(t.credit, 11200.5);
  });

  test('الافتتاحي لفترة لاحقة بلا حركة، وما بعد الفترة خارجها', () {
    final may = trialBalance([cash, bank, eq], journals, lines, DateTime(2027, 5, 1), DateTime(2027, 5, 31));
    final c = may.firstWhere((r) => r.account.code == '1110');
    expect(c.opening, 8799.5);
    expect(c.debit, 0);
    expect(c.closing, 8799.5);
    final early = trialBalance([cash, bank, eq], journals, lines, DateTime(2027, 4, 1), DateTime(2027, 4, 5));
    expect(early.firstWhere((r) => r.account.code == '1110').closing, 10000);
    expect(early.any((r) => r.account.code == '1120'), false);
  });

  test('أستاذ الخزينة: رصيد جارٍ مدين طبيعي، وأستاذ حقوق الملكية دائن طبيعي', () {
    final lc = ledgerFor(cash, journals, lines, DateTime(2027, 4, 1), DateTime(2027, 4, 30));
    expect(lc.opening, 0);
    expect(lc.rows.map((r) => r.balance), [10000, 8799.5]);
    expect(lc.closing, 8799.5);
    final le = ledgerFor(eq, journals, lines, DateTime(2027, 4, 1), DateTime(2027, 4, 30));
    expect(le.closing, 10000);
  });

  test('مثال قيد المرتبات: المدين = الدائن ويرفض القيد غير المتوازن', () {
    final ok = journalBalance([l('x', 1, 'e', 3428.571, 0), l('x', 2, 'n', 0, 3138.571), l('x', 3, 'i', 0, 150), l('x', 4, 'o', 0, 140)]);
    expect(ok.debit, 3428.571);
    expect(ok.credit, 3428.571);
    expect(ok.balanced, true);
    expect(journalBalance([l('x', 1, 'e', 100, 0), l('x', 2, 'n', 0, 99.999)]).balanced, false);
    expect(journalBalance(const <JournalLine>[]).balanced, false);
  });

  test('الجانب الطبيعي للأنواع', () {
    expect(glDebitNormal('asset'), true);
    expect(glDebitNormal('expense'), true);
    expect(glDebitNormal('liability'), false);
    expect(glDebitNormal('equity'), false);
    expect(glDebitNormal('revenue'), false);
  });
}
