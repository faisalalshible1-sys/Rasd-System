// المرتبات والموظفون والحضور والمكافآت والسلف (الإصدار 3.1.0، الترحيل 48).
//
// الكشف يُحتسب في قاعدة البيانات (دالة fin_payroll_generate) ويُحفظ لقطةً لكل موظف؛ والدوال هنا نسخة نقية
// بالمعادلات نفسها لاختبارها ولأمثلة الدليل المحلولة.

import 'finance_rates.dart';

DateTime? _day(Object? v) {
  if (v == null) return null;
  final p = DateTime.tryParse('$v');
  return p == null ? null : DateTime(p.year, p.month, p.day);
}

double _n(Object? v) => v is num ? v.toDouble() : double.tryParse('$v') ?? 0;

/// تقريب إلى ثلاث منازل عشرية كما في قاعدة البيانات.
double round3(double v) => (v * 1000).round() / 1000;

/// أول يوم من شهر اليوم المعطى.
DateTime periodOf(DateTime d) => DateTime(d.year, d.month);

String periodIso(DateTime p) => '${p.year.toString().padLeft(4, '0')}-${p.month.toString().padLeft(2, '0')}-01';

String periodLabel(DateTime p) => '${p.year}/${p.month.toString().padLeft(2, '0')}';

const Map<String, String> attendanceStatusNames = {
  'present': 'حاضر',
  'absent': 'غائب',
  'leave': 'إجازة',
  'holiday': 'عطلة',
};

const Map<String, String> payrollStatusNames = {
  'draft': 'مسودة',
  'approved': 'معتمد',
  'locked': 'مقفل',
};

/// إعدادات الاحتساب: أيام الشهر وساعات الأسبوع ومعامل الإضافي.
class PayrollConfig {
  const PayrollConfig({this.daysInMonth = 30, this.weeklyHours = 42, this.overtimeFactor = 1.5});
  final double daysInMonth;
  final double weeklyHours;
  final double overtimeFactor;

  factory PayrollConfig.fromRows(List<Map<String, dynamic>> rows) {
    double pick(String k, double d) {
      for (final r in rows) {
        if (r['key'] == k) return _n(r['value']);
      }
      return d;
    }

    return PayrollConfig(
      daysInMonth: pick('days_in_month', 30),
      weeklyHours: pick('weekly_hours', 42),
      overtimeFactor: pick('overtime_factor', 1.5),
    );
  }

  /// الأجر اليومي = الأساسي ÷ أيام الشهر.
  double daily(double basic) => basic / daysInMonth;

  /// أجر الساعة = اليومي ÷ (ساعات الأسبوع ÷ 6).
  double hourly(double basic) => daily(basic) / (weeklyHours / 6);
}

class FinEmployee {
  const FinEmployee({
    required this.id,
    required this.name,
    required this.title,
    required this.basic,
    required this.hireDate,
    required this.active,
    this.profileId,
    this.insured = true,
    this.taxable = false,
    this.extra = false,
    this.note = '',
  });

  final String id;
  final String name;
  final String title;
  final double basic;
  final DateTime hireDate;
  final bool active;
  final String? profileId;
  final bool insured;
  final bool taxable;
  final bool extra;
  final String note;

  factory FinEmployee.fromMap(Map<String, dynamic> m) => FinEmployee(
        id: '${m['id'] ?? ''}',
        name: '${m['full_name'] ?? ''}',
        title: '${m['job_title'] ?? ''}',
        basic: _n(m['basic']),
        hireDate: _day(m['hire_date']) ?? DateTime(2000),
        active: m['status'] != 'inactive',
        profileId: m['profile_id'] == null ? null : '${m['profile_id']}',
        insured: m['insured'] != false,
        taxable: m['taxable'] == true,
        extra: m['extra'] == true,
        note: '${m['note'] ?? ''}',
      );
}

class FinAllowance {
  const FinAllowance({required this.id, required this.employeeId, required this.name, required this.amount, required this.active});
  final String id;
  final String employeeId;
  final String name;
  final double amount;
  final bool active;

  factory FinAllowance.fromMap(Map<String, dynamic> m) => FinAllowance(
        id: '${m['id'] ?? ''}',
        employeeId: '${m['employee_id'] ?? ''}',
        name: '${m['name'] ?? ''}',
        amount: _n(m['amount']),
        active: m['active'] != false,
      );
}

class FinEmpDeduction {
  const FinEmpDeduction({required this.employeeId, required this.deductionId, this.override});
  final String employeeId;
  final String deductionId;
  final double? override;

  factory FinEmpDeduction.fromMap(Map<String, dynamic> m) => FinEmpDeduction(
        employeeId: '${m['employee_id'] ?? ''}',
        deductionId: '${m['deduction_id'] ?? ''}',
        override: m['override'] == null ? null : _n(m['override']),
      );
}

class FinAttendanceDay {
  const FinAttendanceDay({required this.employeeId, required this.day, required this.status, required this.overtime});
  final String employeeId;
  final DateTime day;
  final String status;
  final double overtime;

  factory FinAttendanceDay.fromMap(Map<String, dynamic> m) => FinAttendanceDay(
        employeeId: '${m['employee_id'] ?? ''}',
        day: _day(m['day']) ?? DateTime(2000),
        status: '${m['status'] ?? 'present'}',
        overtime: _n(m['overtime_hours']),
      );
}

class FinAttendanceMonth {
  const FinAttendanceMonth({
    required this.employeeId,
    required this.period,
    required this.absent,
    required this.leave,
    required this.overtime,
    this.note = '',
  });
  final String employeeId;
  final DateTime period;
  final double absent;
  final double leave;
  final double overtime;
  final String note;

  factory FinAttendanceMonth.fromMap(Map<String, dynamic> m) => FinAttendanceMonth(
        employeeId: '${m['employee_id'] ?? ''}',
        period: _day(m['period']) ?? DateTime(2000),
        absent: _n(m['absent_days']),
        leave: _n(m['leave_days']),
        overtime: _n(m['overtime_hours']),
        note: '${m['note'] ?? ''}',
      );
}

class FinBonus {
  const FinBonus({required this.id, required this.employeeId, required this.period, required this.name, required this.amount, this.note = ''});
  final String id;
  final String employeeId;
  final DateTime period;
  final String name;
  final double amount;
  final String note;

  factory FinBonus.fromMap(Map<String, dynamic> m) => FinBonus(
        id: '${m['id'] ?? ''}',
        employeeId: '${m['employee_id'] ?? ''}',
        period: _day(m['period']) ?? DateTime(2000),
        name: '${m['name'] ?? ''}',
        amount: _n(m['amount']),
        note: '${m['note'] ?? ''}',
      );
}

class FinLoan {
  const FinLoan({
    required this.id,
    required this.employeeId,
    required this.total,
    required this.installments,
    required this.start,
    required this.active,
    this.note = '',
  });
  final String id;
  final String employeeId;
  final double total;
  final int installments;
  final DateTime start;
  final bool active;
  final String note;

  factory FinLoan.fromMap(Map<String, dynamic> m) => FinLoan(
        id: '${m['id'] ?? ''}',
        employeeId: '${m['employee_id'] ?? ''}',
        total: _n(m['total']),
        installments: (m['installments'] as num?)?.toInt() ?? 1,
        start: _day(m['start_period']) ?? DateTime(2000),
        active: m['status'] != 'closed',
        note: '${m['note'] ?? ''}',
      );

  /// قسط شهر معيّن (0 إن لم يكن ضمن مدة السلفة).
  double installmentIn(DateTime period) {
    if (!active) return 0;
    final idx = (period.year * 12 + period.month) - (start.year * 12 + start.month);
    return loanInstallment(total, installments, idx);
  }
}

/// القسط الثابت = الإجمالي ÷ العدد مقرّباً، وآخر قسط يأخذ الباقي؛ خارج المدة صفر.
double loanInstallment(double total, int count, int index) {
  if (count < 1 || index < 0 || index >= count) return 0;
  final each = round3(total / count);
  return index == count - 1 ? round3(total - each * (count - 1)) : each;
}

class FinPayroll {
  const FinPayroll({required this.id, required this.period, required this.status});
  final String id;
  final DateTime period;
  final String status;

  bool get isDraft => status == 'draft';
  bool get isApproved => status == 'approved';
  bool get isLocked => status == 'locked';

  factory FinPayroll.fromMap(Map<String, dynamic> m) => FinPayroll(
        id: '${m['id'] ?? ''}',
        period: _day(m['period']) ?? DateTime(2000),
        status: '${m['status'] ?? 'draft'}',
      );
}

class FinPayrollLine {
  const FinPayrollLine({
    required this.payrollId,
    required this.employeeId,
    required this.name,
    required this.title,
    required this.basic,
    required this.allowances,
    required this.overtimeHours,
    required this.overtimeAmount,
    required this.bonuses,
    required this.gross,
    required this.absentDays,
    required this.absence,
    required this.insurance,
    required this.tax,
    required this.extraRule,
    required this.other,
    required this.otherDetail,
    required this.loan,
    required this.net,
  });

  final String payrollId;
  final String employeeId;
  final String name;
  final String title;
  final double basic;
  final double allowances;
  final double overtimeHours;
  final double overtimeAmount;
  final double bonuses;
  final double gross;
  final double absentDays;
  final double absence;
  final double insurance;
  final double tax;
  final double extraRule;
  final double other;
  final List<({String name, double amount})> otherDetail;
  final double loan;
  final double net;

  /// مجموع الاستقطاعات.
  double get deductions => absence + insurance + tax + extraRule + other + loan;

  factory FinPayrollLine.fromMap(Map<String, dynamic> m) => FinPayrollLine(
        payrollId: '${m['payroll_id'] ?? ''}',
        employeeId: '${m['employee_id'] ?? ''}',
        name: '${m['employee_name'] ?? ''}',
        title: '${m['job_title'] ?? ''}',
        basic: _n(m['basic']),
        allowances: _n(m['allowances']),
        overtimeHours: _n(m['overtime_hours']),
        overtimeAmount: _n(m['overtime_amount']),
        bonuses: _n(m['bonuses']),
        gross: _n(m['gross']),
        absentDays: _n(m['absent_days']),
        absence: _n(m['absence']),
        insurance: _n(m['insurance']),
        tax: _n(m['tax']),
        extraRule: _n(m['extra_rule']),
        other: _n(m['other_deductions']),
        otherDetail: [
          if (m['other_detail'] is List)
            for (final d in m['other_detail'] as List)
              if (d is Map) (name: '${d['name'] ?? ''}', amount: _n(d['amount'])),
        ],
        loan: _n(m['loan']),
        net: _n(m['net']),
      );
}

/// مجاميع كشف.
class PayrollTotals {
  const PayrollTotals({required this.count, required this.gross, required this.deductions, required this.net});
  final int count;
  final double gross;
  final double deductions;
  final double net;
}

PayrollTotals payrollTotals(Iterable<FinPayrollLine> lines) {
  var c = 0;
  var g = 0.0, d = 0.0, n = 0.0;
  for (final l in lines) {
    c++;
    g += l.gross;
    d += l.deductions;
    n += l.net;
  }
  return PayrollTotals(count: c, gross: round3(g), deductions: round3(d), net: round3(n));
}

/// نسبة راتبية تسري على موظف: النسبة وهل أساسها الإجمالي (وإلا الأساسي).
typedef PayRate = ({double percent, bool onGross});

/// ناتج احتساب سطر راتب.
class PayLineResult {
  const PayLineResult({
    required this.overtimeAmount,
    required this.gross,
    required this.absence,
    required this.insurance,
    required this.tax,
    required this.extraRule,
    required this.other,
    required this.loan,
    required this.net,
  });
  final double overtimeAmount, gross, absence, insurance, tax, extraRule, other, loan, net;
}

/// نسخة نقية من حساب fin_payroll_generate لسطر موظف واحد.
///
/// الإجمالي = الأساسي + البدلات + الإضافي + المكافآت. الإضافي = الساعات × أجر الساعة × المعامل.
/// الغياب = الأيام × الأجر اليومي. كل نسبة = أساسها × النسبة ÷ 100 (الأساسي أو الإجمالي).
/// الصافي = الإجمالي − الغياب − التأمينات − الضريبة − القاعدة الإضافية − الخصومات − قسط السلفة.
PayLineResult computePayLine({
  required PayrollConfig cfg,
  required double basic,
  double allowances = 0,
  double absentDays = 0,
  double overtimeHours = 0,
  double bonuses = 0,
  PayRate? insurance,
  PayRate? tax,
  PayRate? extraRule,
  List<({FinanceDeduction d, double? override})> deductions = const [],
  double loan = 0,
}) {
  final otAmt = round3(overtimeHours * cfg.hourly(basic) * cfg.overtimeFactor);
  final gross = round3(basic + allowances + otAmt + bonuses);
  final absence = round3(absentDays * cfg.daily(basic));
  double rate(PayRate? r) => r == null ? 0 : round3((r.onGross ? gross : basic) * r.percent / 100);
  var other = 0.0;
  for (final x in deductions) {
    final v = x.override ?? x.d.value;
    if (x.d.isPercent) {
      final base = switch (x.d.basis) {
        'payroll_basic' => basic,
        'payroll_gross' => gross,
        _ => null,
      };
      if (base == null) continue;
      other += round3(base * v / 100);
    } else {
      other += round3(v);
    }
  }
  final ins = rate(insurance), tx = rate(tax), ex = rate(extraRule);
  final net = round3(gross - absence - ins - tx - ex - other - loan);
  return PayLineResult(
    overtimeAmount: otAmt,
    gross: gross,
    absence: absence,
    insurance: ins,
    tax: tx,
    extraRule: ex,
    other: round3(other),
    loan: loan,
    net: net,
  );
}
