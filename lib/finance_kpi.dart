// المؤشرات المالية الآلية والتقرير المالي الشهري (الإصدار 2.3.0، بلا ترحيل).
//
// الحسابات دوال نقية تطابق الفصلين 7 و39 في الدليل.

import 'budget.dart';
import 'cashflow.dart';
import 'contractor_account.dart';
import 'milestones.dart';
import 'models.dart';

const double kpiFinPayTarget = 80;
const double kpiFinOldDueTarget = 10;
const double kpiBudgetTarget = 90;

DateTime _d(DateTime d) => DateTime(d.year, d.month, d.day);

/// الصرف في موعده: المستخلصات المدفوعة خلال النافذة قبل موعدها المتوقع (إحالة/اعتماد + أيام الصرف)
/// ÷ (المدفوعة خلال النافذة + غير المدفوعة الفائت موعدها المتوقع).
KpiResult kpiFinancePayOnTime(Iterable<ContractExtract> extracts, DateTime now) {
  final today = _d(now);
  final from = DateTime(today.year, today.month, today.day - kpiWindowDays);
  var met = 0, counted = 0;
  for (final x in extracts) {
    final a = x.referredOn ?? x.approvedOn;
    if (a == null) continue;
    final due = _d(a).add(const Duration(days: cashPayLagDays));
    if (x.isPaid && x.paidOn != null) {
      final p = _d(x.paidOn!);
      if (p.isBefore(from) || p.isAfter(today)) continue;
      counted++;
      if (!p.isAfter(due)) met++;
    } else if (x.counted && x.unpaid > 0 && due.isBefore(today)) {
      counted++;
    }
  }
  return KpiResult(
    key: 'finance_pay_on_time',
    title: 'صرف المستخلصات في موعده',
    section: 'finance',
    value: counted == 0 ? null : met / counted * 100,
    unit: '%',
    target: kpiFinPayTarget,
    sample: counted,
    hint: 'المدفوعة في موعدها المتوقع ÷ (المدفوعة آخر $kpiWindowDays يوماً + غير المدفوعة الفائت موعدها)',
  );
}

/// المستحق الأقدم من 90 يوماً: ما مضى على اعتماده أكثر من 90 يوماً من غير المدفوع ÷ كل غير المدفوع. الأقل أفضل.
KpiResult kpiFinanceOldDue(Iterable<ContractExtract> extracts, DateTime now) {
  final list = extracts.toList();
  final b = agingBuckets(list, now);
  final total = b.fold(0.0, (a, v) => a + v);
  return KpiResult(
    key: 'finance_old_due',
    title: 'المستحق الأقدم من 90 يوماً',
    section: 'finance',
    value: total <= 0 ? null : b[3] / total * 100,
    unit: '%',
    target: kpiFinOldDueTarget,
    higherBetter: false,
    sample: list.where((x) => x.unpaid > 0).length,
    hint: 'غير المدفوع الذي مضى على اعتماده أكثر من 90 يوماً ÷ كل غير المدفوع',
  );
}

/// سلامة الميزانية: بنود السنة التي لم تبلغ حد التنبيه (90% استنفاداً) ÷ كل بنود السنة.
KpiResult kpiBudgetHealth(Iterable<BudgetLine> lines, Iterable<BudgetCommitment> commitments, int year) {
  final ls = lines.where((l) => l.year == year).toList();
  final cs = commitments.toList();
  final ok = ls.where((l) => !budgetStatusOf(l, cs).warn).length;
  return KpiResult(
    key: 'budget_health',
    title: 'سلامة بنود الميزانية',
    section: 'finance',
    value: ls.isEmpty ? null : ok / ls.length * 100,
    unit: '%',
    target: kpiBudgetTarget,
    sample: ls.length,
    hint: 'بنود سنة $year التي لم يبلغ استنفادها 90% ÷ كل بنود السنة',
  );
}

/// حركة شهر مالية.
class FinanceMonth {
  FinanceMonth(this.month);

  final DateTime month;
  int approvedCount = 0;
  double approvedNet = 0, referredNet = 0, paid = 0;

  /// الفرق بين المعتمد والمدفوع في الشهر (موجب: ازداد المستحق).
  double get gap => approvedNet - paid;
}

/// حركة آخر [months] شهراً (الأحدث أولاً): المعتمد بتاريخ اعتماده، والمحال بتاريخ إحالته،
/// والمدفوع بتاريخ كل دفعة (أو دفعة المستخلص الواحدة إن لم يكن له سجل دفعات).
List<FinanceMonth> monthlyFinance(
  Iterable<ContractExtract> extracts,
  List<ExtractPayment> Function(String extractId) paymentsOf,
  DateTime now, {
  int months = 12,
}) {
  final rows = [for (var i = 0; i < months; i++) FinanceMonth(DateTime(now.year, now.month - i, 1))];
  FinanceMonth? at(DateTime? d) {
    if (d == null) return null;
    for (final r in rows) {
      if (r.month.year == d.year && r.month.month == d.month) return r;
    }
    return null;
  }

  for (final x in extracts) {
    if (!x.counted) continue;
    final a = at(x.approvedOn);
    if (a != null) {
      a.approvedCount++;
      a.approvedNet += x.net;
    }
    final r = at(x.referredOn);
    if (r != null) r.referredNet += x.net;
    final pays = paymentsOf(x.id);
    if (pays.isNotEmpty) {
      for (final p in pays) {
        final m = at(p.paidOn);
        if (m != null) m.paid += p.amount;
      }
    } else if (x.paidAmount > 0) {
      final m = at(x.paidOn);
      if (m != null) m.paid += x.paidAmount;
    }
  }
  return rows;
}
