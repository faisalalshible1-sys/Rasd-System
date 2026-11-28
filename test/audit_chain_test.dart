import 'package:flutter_test/flutter_test.dart';
import 'package:dc_app/models.dart';

void main() {
  test('المنظومة تحمل تسميات التدقيق المالية الجديدة', () {
    expect(auditActionLabels['finance.disb_approve'], isNotNull);
    expect(auditActionLabels['finance.journal_reverse'], isNotNull);
  });
}
