import 'package:dc_app/contractor_account.dart';
import 'package:dc_app/models.dart';
import 'package:flutter_test/flutter_test.dart';

ContractExtract _x(double net, {double paid = 0, DateTime? approved, String status = 'approved'}) => ContractExtract(
      id: 'x', projectId: 'p', originProject: null, workId: null, seq: 1, refNo: '', kind: 'interim',
      periodFrom: null, periodTo: null, submittedOn: null, gross: net, retention: 0, advanceRecovery: 0,
      penalties: 0, taxes: 0, otherDeductions: 0, net: net, status: status, approvedOn: approved,
      paidAmount: paid, paidOn: null, notes: '',
    );

void main() {
  final now = DateTime(2026, 11, 27);

  test('أعمار المستحقات: مثال الفصل 7', () {
    final b = agingBuckets([
      _x(150000, approved: DateTime(2026, 11, 10)),
      _x(100000, approved: DateTime(2026, 7, 1)),
      _x(60000, approved: DateTime(2026, 10, 1), paid: 10000), // 57 يوماً، غير المدفوع 50,000
      _x(30000), // بلا تاريخ اعتماد
      _x(90000, approved: DateTime(2026, 9, 1), paid: 90000), // مدفوع كله: لا يدخل
      _x(40000, status: 'submitted'), // غير معتمد: لا يدخل
    ], now);
    expect(b, [150000, 50000, 0, 100000, 30000]);
  });

  test('حدود الشرائح', () {
    expect(agingBuckets([_x(1, approved: DateTime(2026, 10, 28))], now)[0], 1); // 30 يوماً
    expect(agingBuckets([_x(1, approved: DateTime(2026, 10, 27))], now)[1], 1); // 31
    expect(agingBuckets([_x(1, approved: DateTime(2026, 8, 29))], now)[2], 1); // 90
    expect(agingBuckets([_x(1, approved: DateTime(2026, 8, 28))], now)[3], 1); // 91
  });

  test('حسابات المقاول', () {
    final a = ContractorAccount('شركة')
      ..contract = 1400000
      ..variationsNet = 50000
      ..paid = 370000;
    expect(a.adjusted, 1450000);
    expect(a.remainingToPay, 1080000);
    expect(a.paidRatio, closeTo(0.2552, 1e-4));
    a.paid = 2000000;
    expect(a.remainingToPay, 0);
    expect(ContractorAccount('ب').paidRatio, isNull);
  });
}
