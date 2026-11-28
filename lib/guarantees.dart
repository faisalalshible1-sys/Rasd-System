// الضمانات والتأمينات النقدية والحسابات والتحويلات (الإصدار 3.2.0، الترحيل 49).
//
// الدورة والتحقق في قاعدة البيانات؛ والدوال هنا نسخة نقية بالمعادلات نفسها لاختبارها ولأمثلة الدليل.

import 'payroll.dart' show round3;

DateTime? _day(Object? v) {
  if (v == null) return null;
  final p = DateTime.tryParse('$v');
  return p == null ? null : DateTime(p.year, p.month, p.day);
}

double _n(Object? v) => v is num ? v.toDouble() : double.tryParse('$v') ?? 0;

const Map<String, String> guaranteeKindNames = {
  'initial': 'ضمان ابتدائي',
  'final': 'ضمان نهائي',
  'retention': 'محتجز',
  'deposit': 'تأمين نقدي',
};

const Map<String, String> guaranteeStatusNames = {
  'held': 'محتجز',
  'release_requested': 'طُلب استرداده',
  'released': 'مُسترد',
};

const Map<String, String> transferStatusNames = {
  'pending': 'بانتظار الموافقة',
  'posted': 'مرحَّل',
  'rejected': 'مرفوض',
};

const Map<String, String> accountKindNames = {'cash': 'نقدي', 'bank': 'مصرفي'};

/// مدة التنبيه قبل انتهاء الضمان بالأيام.
const int guaranteeWarnDays = 30;

class FinGuarantee {
  const FinGuarantee({
    required this.id,
    required this.kind,
    required this.party,
    required this.amount,
    required this.issued,
    required this.status,
    this.projectId,
    this.expires,
    this.reference = '',
    this.note = '',
    this.releaseReason = '',
    this.decisionNote = '',
    this.extractId,
  });
  final String id;
  /// المستخلص الذي خُصم منه هذا المحتجز (الترحيل 51)؛ فارغ للضمانات الأخرى.
  final String? extractId;
  final String kind;
  final String? projectId;
  final String party;
  final double amount;
  final DateTime issued;
  final DateTime? expires;
  final String reference;
  final String note;
  final String status;
  final String releaseReason;
  final String decisionNote;

  bool get isHeld => status == 'held';
  bool get isRequested => status == 'release_requested';
  bool get isReleased => status == 'released';

  factory FinGuarantee.fromMap(Map<String, dynamic> m) => FinGuarantee(
        id: '${m['id'] ?? ''}',
        kind: '${m['kind'] ?? 'initial'}',
        projectId: m['project_id'] == null ? null : '${m['project_id']}',
        party: '${m['party'] ?? ''}',
        amount: _n(m['amount']),
        issued: _day(m['issued_on']) ?? DateTime(2000),
        expires: _day(m['expires_on']),
        reference: '${m['reference'] ?? ''}',
        note: '${m['note'] ?? ''}',
        status: '${m['status'] ?? 'held'}',
        releaseReason: '${m['release_reason'] ?? ''}',
        decisionNote: '${m['decision_note'] ?? ''}',
        extractId: m['extract_id'] == null ? null : '${m['extract_id']}',
      );
}

/// حالة الانتهاء: none (بلا تاريخ) أو expired أو soon (خلال مدة التنبيه) أو ok. المُستردّ لا ينتهي.
String guaranteeExpiry(FinGuarantee g, DateTime today) {
  final e = g.expires;
  if (g.isReleased || e == null) return 'none';
  final t = DateTime(today.year, today.month, today.day);
  if (e.isBefore(t)) return 'expired';
  if (e.difference(t).inDays <= guaranteeWarnDays) return 'soon';
  return 'ok';
}

class GuaranteeTotals {
  const GuaranteeTotals({this.held = 0, this.requested = 0, this.released = 0, this.expiring = 0});
  final double held;
  final double requested;
  final double released;

  /// عدد الضمانات المحتجزة أو المطلوب استردادها وقد انتهت أو قاربت الانتهاء.
  final int expiring;
}

GuaranteeTotals guaranteeTotals(Iterable<FinGuarantee> list, DateTime today) {
  double h = 0, r = 0, x = 0;
  var e = 0;
  for (final g in list) {
    if (g.isHeld) h += g.amount;
    if (g.isRequested) r += g.amount;
    if (g.isReleased) x += g.amount;
    if (!g.isReleased) {
      final s = guaranteeExpiry(g, today);
      if (s == 'expired' || s == 'soon') e++;
    }
  }
  return GuaranteeTotals(held: round3(h), requested: round3(r), released: round3(x), expiring: e);
}

class FinAccount {
  const FinAccount({required this.id, required this.name, required this.kind, required this.opening, required this.active, this.glAccountId});
  final String id;
  /// حساب الأصل المربوط في دليل الحسابات (الترحيل 50)؛ فارغ حتى يُربط.
  final String? glAccountId;
  final String name;
  final String kind;
  final double opening;
  final bool active;

  factory FinAccount.fromMap(Map<String, dynamic> m) => FinAccount(
        id: '${m['id'] ?? ''}',
        name: '${m['name'] ?? ''}',
        kind: '${m['kind'] ?? 'bank'}',
        opening: _n(m['opening']),
        active: m['active'] != false,
        glAccountId: m['gl_account_id'] == null ? null : '${m['gl_account_id']}',
      );
}

class FinTransfer {
  const FinTransfer({
    required this.id,
    required this.fromId,
    required this.toId,
    required this.amount,
    required this.date,
    required this.status,
    this.note = '',
    this.decisionNote = '',
  });
  final String id;
  final String fromId;
  final String toId;
  final double amount;
  final DateTime date;
  final String status;
  final String note;
  final String decisionNote;

  bool get isPending => status == 'pending';
  bool get isPosted => status == 'posted';

  factory FinTransfer.fromMap(Map<String, dynamic> m) => FinTransfer(
        id: '${m['id'] ?? ''}',
        fromId: '${m['from_id'] ?? ''}',
        toId: '${m['to_id'] ?? ''}',
        amount: _n(m['amount']),
        date: _day(m['on_date']) ?? DateTime(2000),
        status: '${m['status'] ?? 'pending'}',
        note: '${m['note'] ?? ''}',
        decisionNote: '${m['decision_note'] ?? ''}',
      );
}

/// الرصيد = الافتتاحي + المرحَّل وارداً − المرحَّل صادراً (المعلّق والمرفوض لا يؤثران).
double accountBalance(FinAccount a, Iterable<FinTransfer> transfers) {
  var b = a.opening;
  for (final t in transfers) {
    if (!t.isPosted) continue;
    if (t.toId == a.id) b += t.amount;
    if (t.fromId == a.id) b -= t.amount;
  }
  return round3(b);
}
