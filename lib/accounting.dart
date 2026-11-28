// المحاسبة: دليل الحسابات وقيود اليومية المزدوجة والأستاذ وميزان المراجعة (الإصدار 3.3.0، الترحيل 50).
//
// الإنشاء والترحيل والعكس والقيود الآلية في قاعدة البيانات؛ والدوال هنا نسخة نقية بالمعادلات نفسها
// لعرض الأستاذ وميزان المراجعة ولاختبارها ولأمثلة الدليل.

import 'payroll.dart' show round3;

double _n(Object? v) => v is num ? v.toDouble() : double.tryParse('$v') ?? 0;

DateTime _day(Object? v) {
  final p = DateTime.tryParse('$v');
  return p == null ? DateTime(2000) : DateTime(p.year, p.month, p.day);
}

const Map<String, String> glTypeNames = {
  'asset': 'أصول',
  'liability': 'خصوم',
  'equity': 'حقوق ملكية',
  'revenue': 'إيرادات',
  'expense': 'مصروفات',
};

const Map<String, String> journalSourceNames = {
  'manual': 'يدوي',
  'payroll': 'كشف مرتبات',
  'payroll_reversal': 'عكس كشف مرتبات',
  'transfer': 'تحويل بين حسابين',
  'disbursement': 'صرف مستخلص',
  'disbursement_reversal': 'عكس صرف مستخلص',
};

/// تعيينات حسابات القيد الآلي لكشف المرتبات: المفتاح ← (الاسم، نوع الحساب المسموح).
const Map<String, (String, String)> glMapKeys = {
  'payroll_expense': ('الرواتب والأجور (مدين)', 'expense'),
  'payroll_net': ('المرتبات المستحقة (صافي الكشف)', 'liability'),
  'payroll_insurance': ('التأمينات المستحقة', 'liability'),
  'payroll_tax': ('الضرائب المستحقة (الدخل والقاعدة الإضافية)', 'liability'),
  'payroll_other': ('الاستقطاعات الأخرى المستحقة', 'liability'),
  'payroll_loan': ('سلف الموظفين (أقساط)', 'asset'),
  'extract_payable': ('مستحقات المقاولين (صرف المستخلصات)', 'liability'),
};

/// الجانب الطبيعي للحساب: المدين للأصول والمصروفات، والدائن لغيرهما.
bool glDebitNormal(String type) => type == 'asset' || type == 'expense';

class GlAccount {
  const GlAccount({required this.id, required this.code, required this.name, required this.type, required this.postable, required this.active, this.parentId});
  final String id;
  final String code;
  final String name;
  final String type;
  final String? parentId;
  final bool postable;
  final bool active;

  String get label => '$code — $name';

  factory GlAccount.fromMap(Map<String, dynamic> m) => GlAccount(
        id: '${m['id'] ?? ''}',
        code: '${m['code'] ?? ''}',
        name: '${m['name'] ?? ''}',
        type: '${m['type'] ?? 'asset'}',
        parentId: m['parent_id'] == null ? null : '${m['parent_id']}',
        postable: m['postable'] != false,
        active: m['active'] != false,
      );
}

class JournalEntry {
  const JournalEntry({
    required this.id,
    required this.date,
    required this.memo,
    required this.source,
    required this.status,
    this.entryNo,
    this.reverses,
    this.reversedBy,
    this.reverseReason = '',
  });
  final String id;
  final int? entryNo;
  final DateTime date;
  final String memo;
  final String source;
  final String status;
  final String? reverses;
  final String? reversedBy;
  final String reverseReason;

  bool get isPosted => status == 'posted';
  bool get isDraft => status == 'draft';
  bool get isManual => source == 'manual';
  bool get isReversed => reversedBy != null;
  bool get isReversal => reverses != null;

  factory JournalEntry.fromMap(Map<String, dynamic> m) => JournalEntry(
        id: '${m['id'] ?? ''}',
        entryNo: m['entry_no'] is num ? (m['entry_no'] as num).toInt() : null,
        date: _day(m['entry_date']),
        memo: '${m['memo'] ?? ''}',
        source: '${m['source'] ?? 'manual'}',
        status: '${m['status'] ?? 'draft'}',
        reverses: m['reverses'] == null ? null : '${m['reverses']}',
        reversedBy: m['reversed_by'] == null ? null : '${m['reversed_by']}',
        reverseReason: '${m['reverse_reason'] ?? ''}',
      );
}

class JournalLine {
  const JournalLine({required this.journalId, required this.lineNo, required this.accountId, required this.debit, required this.credit, this.memo = ''});
  final String journalId;
  final int lineNo;
  final String accountId;
  final double debit;
  final double credit;
  final String memo;

  factory JournalLine.fromMap(Map<String, dynamic> m) => JournalLine(
        journalId: '${m['journal_id'] ?? ''}',
        lineNo: m['line_no'] is num ? (m['line_no'] as num).toInt() : 0,
        accountId: '${m['account_id'] ?? ''}',
        debit: _n(m['debit']),
        credit: _n(m['credit']),
        memo: '${m['memo'] ?? ''}',
      );
}

/// مجموع المدين والدائن لسطور قيد، ومتوازن إن تساويا وكان أكبر من صفر (شرط الترحيل).
({double debit, double credit, bool balanced}) journalBalance(Iterable<JournalLine> lines) {
  var d = 0.0, c = 0.0;
  for (final l in lines) {
    d += l.debit;
    c += l.credit;
  }
  d = round3(d);
  c = round3(c);
  return (debit: d, credit: c, balanced: d == c && d > 0);
}

class TrialRow {
  const TrialRow({required this.account, required this.opening, required this.debit, required this.credit, required this.closing});
  final GlAccount account;
  final double opening;
  final double debit;
  final double credit;
  final double closing;
}

DateTime _d(DateTime v) => DateTime(v.year, v.month, v.day);

/// ميزان المراجعة لفترة [from, to]: الافتتاحي (قبل الفترة) والحركة والختامي بالجانب الطبيعي للحساب.
/// القيود المرحَّلة وحدها، وتُحذف الحسابات التي لا رصيد ولا حركة لها.
List<TrialRow> trialBalance(Iterable<GlAccount> accounts, Iterable<JournalEntry> journals, Iterable<JournalLine> lines, DateTime from, DateTime to) {
  final f = _d(from), t = _d(to);
  final posted = {for (final j in journals) if (j.isPosted && !_d(j.date).isAfter(t)) j.id: _d(j.date)};
  final o = <String, double>{}, dr = <String, double>{}, cr = <String, double>{};
  for (final l in lines) {
    final jd = posted[l.journalId];
    if (jd == null) continue;
    if (jd.isBefore(f)) {
      o[l.accountId] = (o[l.accountId] ?? 0) + l.debit - l.credit;
    } else {
      dr[l.accountId] = (dr[l.accountId] ?? 0) + l.debit;
      cr[l.accountId] = (cr[l.accountId] ?? 0) + l.credit;
    }
  }
  final out = <TrialRow>[];
  for (final a in accounts) {
    final ov = round3(o[a.id] ?? 0), dv = round3(dr[a.id] ?? 0), cv = round3(cr[a.id] ?? 0);
    if (ov == 0 && dv == 0 && cv == 0) continue;
    final sign = glDebitNormal(a.type) ? 1 : -1;
    out.add(TrialRow(account: a, opening: round3(sign * ov), debit: dv, credit: cv, closing: round3(sign * (ov + dv - cv))));
  }
  out.sort((a, b) => a.account.code.compareTo(b.account.code));
  return out;
}

/// مجموع عمودي المدين والدائن لميزان المراجعة؛ متساويان دائماً إن كانت كل القيود متوازنة.
({double debit, double credit}) trialTotals(Iterable<TrialRow> rows) {
  var d = 0.0, c = 0.0;
  for (final r in rows) {
    d += r.debit;
    c += r.credit;
  }
  return (debit: round3(d), credit: round3(c));
}

class LedgerRow {
  const LedgerRow({required this.entry, required this.line, required this.balance});
  final JournalEntry entry;
  final JournalLine line;
  final double balance;
}

/// أستاذ حساب لفترة: رصيد افتتاحي ثم حركاته بترتيب التاريخ فرقم القيد، برصيد جارٍ بالجانب الطبيعي.
({double opening, List<LedgerRow> rows, double closing}) ledgerFor(
    GlAccount account, Iterable<JournalEntry> journals, Iterable<JournalLine> lines, DateTime from, DateTime to) {
  final f = _d(from), t = _d(to);
  final sign = glDebitNormal(account.type) ? 1 : -1;
  final byId = {for (final j in journals) if (j.isPosted) j.id: j};
  var open = 0.0;
  final inRange = <(JournalEntry, JournalLine)>[];
  for (final l in lines) {
    if (l.accountId != account.id) continue;
    final j = byId[l.journalId];
    if (j == null) continue;
    final jd = _d(j.date);
    if (jd.isBefore(f)) {
      open += l.debit - l.credit;
    } else if (!jd.isAfter(t)) {
      inRange.add((j, l));
    }
  }
  inRange.sort((a, b) {
    final c = a.$1.date.compareTo(b.$1.date);
    if (c != 0) return c;
    final n = (a.$1.entryNo ?? 0).compareTo(b.$1.entryNo ?? 0);
    return n != 0 ? n : a.$2.lineNo.compareTo(b.$2.lineNo);
  });
  var run = round3(sign * open);
  final opening = run;
  final rows = <LedgerRow>[];
  for (final e in inRange) {
    run = round3(run + sign * (e.$2.debit - e.$2.credit));
    rows.add(LedgerRow(entry: e.$1, line: e.$2, balance: run));
  }
  return (opening: opening, rows: rows, closing: run);
}
