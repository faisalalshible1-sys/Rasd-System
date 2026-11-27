// ميزانية المكتب والالتزامات (الإصدار 2.0.0، الترحيل 46).
//
// الحسابات دوال نقية تطابق فصل «المالية» في الدليل (قسم «ميزانية المكتب والالتزامات»).

/// نسبة استنفاد البند التي يبدأ عندها التنبيه (من المخصص).
const double budgetWarnRatio = 0.9;

DateTime? _day(Object? v) {
  if (v == null) return null;
  final p = DateTime.tryParse('$v');
  return p == null ? null : DateTime(p.year, p.month, p.day);
}

double _n(Object? v) => v is num ? v.toDouble() : double.tryParse('$v') ?? 0;

/// بند ميزانية سنوي.
class BudgetLine {
  const BudgetLine({
    required this.id,
    required this.year,
    required this.category,
    required this.name,
    required this.allocated,
    this.note = '',
  });

  final String id;
  final int year;
  final String category;
  final String name;
  final double allocated;
  final String note;

  factory BudgetLine.fromMap(Map<String, dynamic> m) => BudgetLine(
        id: '${m['id'] ?? ''}',
        year: (m['fiscal_year'] as num?)?.toInt() ?? 0,
        category: '${m['category'] ?? ''}',
        name: '${m['name'] ?? ''}',
        allocated: _n(m['allocated']),
        note: '${m['note'] ?? ''}',
      );
}

/// التزام على بند.
class BudgetCommitment {
  const BudgetCommitment({
    required this.id,
    required this.lineId,
    this.projectId,
    required this.description,
    required this.amount,
    this.paid = 0,
    required this.date,
    this.status = 'active',
    this.note = '',
  });

  final String id;
  final String lineId;
  final String? projectId;
  final String description;
  final double amount;
  final double paid;
  final DateTime date;
  final String status;
  final String note;

  bool get isActive => status == 'active';

  /// الباقي دفعه من الالتزام.
  double get unpaid => amount - paid;

  factory BudgetCommitment.fromMap(Map<String, dynamic> m) => BudgetCommitment(
        id: '${m['id'] ?? ''}',
        lineId: '${m['line_id'] ?? ''}',
        projectId: m['project_id'] as String?,
        description: '${m['description'] ?? ''}',
        amount: _n(m['amount']),
        paid: _n(m['paid']),
        date: _day(m['committed_on']) ?? DateTime.now(),
        status: '${m['status'] ?? 'active'}',
        note: '${m['note'] ?? ''}',
      );
}

/// موقف بند: المخصص والملتزم والمدفوع والمتبقي ونسبة الاستنفاد.
class BudgetStatus {
  const BudgetStatus({required this.allocated, required this.committed, required this.paid});

  final double allocated;
  final double committed;
  final double paid;

  /// المتبقي للالتزام = المخصص − الملتزم النشط.
  double get remaining => allocated - committed;

  /// الملتزم الذي لم يُدفع بعد.
  double get unpaid => committed - paid;

  /// نسبة الاستنفاد = الملتزم ÷ المخصص (null إن كان المخصص صفراً).
  double? get usage => allocated <= 0 ? null : committed / allocated;

  /// بلغ الاستنفاد حد التنبيه.
  bool get warn => usage != null && usage! >= budgetWarnRatio;

  /// استُنفد البند كلياً.
  bool get exhausted => allocated > 0 && remaining <= 0;
}

/// موقف بند من التزاماته: النشطة وحدها تُحسب.
BudgetStatus budgetStatusOf(BudgetLine line, Iterable<BudgetCommitment> all) {
  var c = 0.0, p = 0.0;
  for (final x in all) {
    if (x.lineId != line.id || !x.isActive) continue;
    c += x.amount;
    p += x.paid;
  }
  return BudgetStatus(allocated: line.allocated, committed: c, paid: p);
}

/// مجموع موقف بنود (لسنة أو لباب).
BudgetStatus budgetTotal(Iterable<BudgetLine> lines, Iterable<BudgetCommitment> all) {
  var a = 0.0, c = 0.0, p = 0.0;
  for (final l in lines) {
    final s = budgetStatusOf(l, all);
    a += s.allocated;
    c += s.committed;
    p += s.paid;
  }
  return BudgetStatus(allocated: a, committed: c, paid: p);
}
