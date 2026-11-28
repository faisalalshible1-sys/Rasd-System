// اعتماد الصرف: دورة صرف المستخلص (الإصدار 3.4.0، الترحيل 51).
//
// الطلب والمراجعة المالية والاعتماد والعكس في قاعدة البيانات؛ والدوال هنا نسخة نقية بالمعادلات نفسها
// لحساب المتبقي للصرف ولعرضه ولاختباره ولأمثلة الدليل.

import 'payroll.dart' show round3;

double _n(Object? v) => v is num ? v.toDouble() : double.tryParse('$v') ?? 0;

DateTime _day(Object? v) {
  final p = DateTime.tryParse('$v');
  return p == null ? DateTime(2000) : DateTime(p.year, p.month, p.day);
}

const Map<String, String> disbStatusNames = {
  'requested': 'مطلوب (بانتظار المراجعة)',
  'reviewed': 'روجع (بانتظار الاعتماد)',
  'returned': 'أُعيد للتصحيح',
  'approved': 'معتمد ومصروف',
  'rejected': 'مرفوض',
  'cancelled': 'ملغى',
  'reversed': 'معكوس',
};

const Map<String, String> disbMethodNames = {
  'cheque': 'صك',
  'transfer': 'حوالة',
  'cash': 'نقداً',
  'other': 'أخرى',
};

/// الحالات التي تحجز من المتبقي للصرف: طلب مفتوح (مطلوب أو روجع) أو معتمد.
const Set<String> disbHoldingStatuses = {'requested', 'reviewed', 'approved'};

class FinDisbursement {
  const FinDisbursement({
    required this.id,
    required this.extractId,
    required this.projectId,
    required this.amount,
    required this.accountId,
    required this.payDate,
    required this.method,
    required this.status,
    this.refNo = '',
    this.note = '',
    this.reviewNote = '',
    this.decisionNote = '',
    this.reverseReason = '',
    this.requestedAt,
  });

  final String id;
  final String extractId;
  final String projectId;
  final double amount;
  final String accountId;
  final DateTime payDate;
  final String method;
  final String status;
  final String refNo;
  final String note;
  final String reviewNote;
  final String decisionNote;
  final String reverseReason;
  final DateTime? requestedAt;

  bool get isOpen => status == 'requested' || status == 'reviewed';
  bool get isRequested => status == 'requested';
  bool get isReviewed => status == 'reviewed';
  bool get isApproved => status == 'approved';
  bool get holds => disbHoldingStatuses.contains(status);
  String get statusLabel => disbStatusNames[status] ?? status;
  String get methodLabel => disbMethodNames[method] ?? method;

  factory FinDisbursement.fromMap(Map<String, dynamic> m) => FinDisbursement(
        id: '${m['id'] ?? ''}',
        extractId: '${m['extract_id'] ?? ''}',
        projectId: '${m['project_id'] ?? ''}',
        amount: _n(m['amount']),
        accountId: '${m['account_id'] ?? ''}',
        payDate: _day(m['pay_date']),
        method: '${m['method'] ?? 'transfer'}',
        status: '${m['status'] ?? 'requested'}',
        refNo: '${m['ref_no'] ?? ''}',
        note: '${m['note'] ?? ''}',
        reviewNote: '${m['review_note'] ?? ''}',
        decisionNote: '${m['decision_note'] ?? ''}',
        reverseReason: '${m['reverse_reason'] ?? ''}',
        requestedAt: m['requested_at'] == null ? null : DateTime.tryParse('${m['requested_at']}'),
      );
}

/// المتبقي للصرف = صافي المستخلص − ما دُفع − الطلبات المفتوحة (مطلوب أو روجع)، ولا يقل عن صفر.
/// الصرف المعتمد داخل «المدفوع» أصلاً فلا يُخصم مرتين.
double extractRemaining({required double net, required double paid, required Iterable<FinDisbursement> disbursements, String? exceptId}) {
  var open = 0.0;
  for (final d in disbursements) {
    if (d.isOpen && d.id != exceptId) open += d.amount;
  }
  final r = round3(net - paid - open);
  return r < 0 ? 0 : r;
}

/// رصيد الحساب المالي بعد الصرف المعتمد: الافتتاحي + الوارد − الصادر − الصرف المعتمد.
double balanceAfterDisbursements(double balance, Iterable<FinDisbursement> disbursements, String accountId) {
  var out = 0.0;
  for (final d in disbursements) {
    if (d.isApproved && d.accountId == accountId) out += d.amount;
  }
  return round3(balance - out);
}
