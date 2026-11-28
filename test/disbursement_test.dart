import 'package:flutter_test/flutter_test.dart';
import 'package:dc_app/accounting.dart';
import 'package:dc_app/disbursement.dart';

void main() {
  FinDisbursement d(String id, double amount, String status, {String account = 'a1'}) => FinDisbursement(
        id: id,
        extractId: 'x',
        projectId: 'p',
        amount: amount,
        accountId: account,
        payDate: DateTime(2026, 11, 10),
        method: 'transfer',
        status: status,
      );

  test('مثال الدليل: المتبقي بعد طلب 40,000 ثم اكتمال الصافي', () {
    expect(extractRemaining(net: 95000, paid: 0, disbursements: const []), 95000);
    final req = d('d1', 40000, 'requested');
    expect(extractRemaining(net: 95000, paid: 0, disbursements: [req]), 55000);
    // بعد الاعتماد: الدفعة داخل المدفوع والطلب لا يُخصم مرتين.
    final app = d('d1', 40000, 'approved');
    expect(extractRemaining(net: 95000, paid: 40000, disbursements: [app]), 55000);
    expect(extractRemaining(net: 95000, paid: 40000, disbursements: [app, d('d2', 55000, 'reviewed')]), 0);
    expect(extractRemaining(net: 95000, paid: 95000, disbursements: [app, d('d2', 55000, 'approved')]), 0);
  });

  test('الملغى والمُعاد والمرفوض والمعكوس لا تحجز، والاستثناء يرفع الحجز', () {
    for (final s in ['cancelled', 'returned', 'rejected', 'reversed']) {
      expect(extractRemaining(net: 1000, paid: 0, disbursements: [d('d', 400, s)]), 1000, reason: s);
    }
    expect(extractRemaining(net: 1000, paid: 0, disbursements: [d('d', 400, 'requested')], exceptId: 'd'), 1000);
    expect(extractRemaining(net: 1000, paid: 1200, disbursements: const []), 0);
  });

  test('مثال الدليل: رصيد الخزينة بعد الصرف المعتمد والمعكوس', () {
    expect(balanceAfterDisbursements(100000, [d('d1', 40000, 'approved')], 'a1'), 60000);
    expect(balanceAfterDisbursements(100000, [d('d1', 40000, 'approved'), d('d2', 55000, 'approved')], 'a1'), 5000);
    expect(balanceAfterDisbursements(100000, [d('d1', 40000, 'approved'), d('d2', 55000, 'reversed')], 'a1'), 60000);
    expect(balanceAfterDisbursements(100000, [d('d1', 40000, 'requested'), d('d3', 9, 'approved', account: 'other')], 'a1'), 100000);
  });

  test('الحالات والتعيين الجديد مسمّاة', () {
    for (final s in ['requested', 'reviewed', 'returned', 'approved', 'rejected', 'cancelled', 'reversed']) {
      expect(disbStatusNames.containsKey(s), true, reason: s);
    }
    expect(glMapKeys['extract_payable']!.$2, 'liability');
    expect(journalSourceNames['disbursement'], isNotNull);
    expect(journalSourceNames['disbursement_reversal'], isNotNull);
  });

  test('fromMap يقرأ الحقول', () {
    final x = FinDisbursement.fromMap({'id': 'i', 'extract_id': 'e', 'project_id': 'p', 'amount': '12.5', 'account_id': 'a', 'pay_date': '2026-11-10', 'method': 'cheque', 'status': 'reviewed'});
    expect(x.amount, 12.5);
    expect(x.isReviewed, true);
    expect(x.holds, true);
    expect(x.methodLabel, 'صك');
  });
}
