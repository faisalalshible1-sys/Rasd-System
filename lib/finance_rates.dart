// النسب والخصومات والصلاحيات المالية (الإصدار 3.0.0، الترحيل 47).
//
// الحسابات دوال نقية تطابق فصل «المالية والمرتبات» في الدليل.

/// رموز النسب بترتيب العرض.
const List<String> financeRateCodes = ['income_tax', 'insurance', 'extra_rule'];

const Map<String, String> financeRateNames = {
  'income_tax': 'ضريبة الدخل',
  'insurance': 'التأمينات',
  'extra_rule': 'القاعدة الإضافية',
};

/// أسس الاحتساب.
const Map<String, String> financeBasisNames = {
  'extract_gross': 'إجمالي المستخلص',
  'extract_net': 'صافي المستخلص',
  'contract_value': 'قيمة العقد',
  'payroll_basic': 'الراتب الأساسي',
  'payroll_gross': 'إجمالي الراتب',
  'none': 'مبلغ ثابت بلا أساس',
};

/// نطاقات التطبيق.
const Map<String, String> financeScopeNames = {
  'contracts': 'العقود',
  'employees': 'الموظفون',
  'selected': 'محدد بالاختيار',
};

const Map<String, String> financeAppliesNames = {
  'payroll': 'المرتبات',
  'contracts': 'العقود',
  'both': 'الاثنان',
};

const Map<String, String> financePermNames = {
  'view': 'اطّلاع',
  'edit': 'تحرير',
  'approve': 'اعتماد',
};

DateTime? _day(Object? v) {
  if (v == null) return null;
  final p = DateTime.tryParse('$v');
  return p == null ? null : DateTime(p.year, p.month, p.day);
}

double _n(Object? v) => v is num ? v.toDouble() : double.tryParse('$v') ?? 0;

/// إصدار نسبة بتاريخ سريانه.
class FinanceRate {
  const FinanceRate({
    required this.id,
    required this.code,
    required this.percent,
    required this.basis,
    required this.scope,
    required this.active,
    required this.from,
    this.to,
    this.reason = '',
  });

  final String id;
  final String code;
  final double percent;
  final String basis;
  final String scope;
  final bool active;
  final DateTime from;
  final DateTime? to;
  final String reason;

  factory FinanceRate.fromMap(Map<String, dynamic> m) => FinanceRate(
        id: '${m['id'] ?? ''}',
        code: '${m['code'] ?? ''}',
        percent: _n(m['percent']),
        basis: '${m['basis'] ?? ''}',
        scope: '${m['scope'] ?? ''}',
        active: m['active'] != false,
        from: _day(m['effective_from']) ?? DateTime(2000),
        to: _day(m['effective_to']),
        reason: '${m['reason'] ?? ''}',
      );

  /// هل يسري في هذا اليوم؟
  bool coversDay(DateTime d) {
    final day = DateTime(d.year, d.month, d.day);
    return !day.isBefore(from) && (to == null || !day.isAfter(to!));
  }
}

/// النسبة السارية لرمز في يوم معيّن: null إن لم يوجد إصدار ساري أو كان معطّلاً.
/// لا تُطبَّق نسبة معطّلة ولا خارج تاريخ سريانها.
FinanceRate? rateAt(List<FinanceRate> all, String code, DateTime day) {
  for (final r in all) {
    if (r.code == code && r.coversDay(day)) return r.active ? r : null;
  }
  return null;
}

/// مبلغ النسبة على أساس: الأساس × النسبة ÷ 100، مقرّباً إلى ثلاث منازل.
double rateAmount(double base, double percent) => ((base * percent / 100) * 1000).round() / 1000;

/// بند في دليل الخصومات.
class FinanceDeduction {
  const FinanceDeduction({
    required this.id,
    required this.name,
    required this.kind,
    required this.value,
    required this.basis,
    required this.appliesTo,
    required this.active,
    this.note = '',
  });

  final String id;
  final String name;
  final String kind; // percent | fixed
  final double value;
  final String basis;
  final String appliesTo;
  final bool active;
  final String note;

  bool get isPercent => kind == 'percent';

  factory FinanceDeduction.fromMap(Map<String, dynamic> m) => FinanceDeduction(
        id: '${m['id'] ?? ''}',
        name: '${m['name'] ?? ''}',
        kind: '${m['kind'] ?? 'fixed'}',
        value: _n(m['value']),
        basis: '${m['basis'] ?? 'none'}',
        appliesTo: '${m['applies_to'] ?? 'payroll'}',
        active: m['active'] != false,
        note: '${m['note'] ?? ''}',
      );

  /// مبلغ الخصم على أساس معطى (النسبة من الأساس، والثابت كما هو).
  double amountOn(double base) => isPercent ? rateAmount(base, value) : value;
}

/// صلاحية مالية ممنوحة لمستخدم.
class FinanceGrant {
  const FinanceGrant({required this.userId, required this.perm});
  final String userId;
  final String perm;

  factory FinanceGrant.fromMap(Map<String, dynamic> m) =>
      FinanceGrant(userId: '${m['user_id'] ?? ''}', perm: '${m['perm'] ?? ''}');
}
