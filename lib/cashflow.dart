// التدفق النقدي والمدفوعات المتوقعة (الإصدار 2.1.0، بلا ترحيل: قراءة من بيانات قائمة).
//
// الحسابات دوال نقية تطابق فصل «المالية» في الدليل (قسم «التدفق النقدي والمدفوعات المتوقعة»).

import 'budget.dart';
import 'models.dart';

/// أيام الصرف المتوقعة بعد الإحالة (أو الاعتماد إن لم يُحَل المستخلص).
const int cashPayLagDays = 30;

/// عدد الأشهر المعروضة في الجدول الزمني (الشهر الحالي وما بعده).
const int cashHorizonMonths = 6;

DateTime _d(DateTime d) => DateTime(d.year, d.month, d.day);

/// تاريخ الصرف المتوقع للمستخلص غير المدفوع: تاريخ الإحالة، فإن لم يوجد فالاعتماد، زائداً [lag] يوماً.
/// null إن لم يوجد أي من التاريخين، أو كان المستخلص غير معتمد أو مدفوعاً بالكامل.
DateTime? cashDueOf(ContractExtract x, {int lag = cashPayLagDays}) {
  if (!x.counted || x.unpaid <= 0) return null;
  final a = x.referredOn ?? x.approvedOn;
  return a == null ? null : _d(a).add(Duration(days: lag));
}

/// نتيجة التوقع.
class CashForecast {
  const CashForecast({
    required this.overdue,
    required this.months,
    required this.later,
    required this.undated,
    required this.pending,
    required this.commitments,
  });

  /// المتأخر عن موعده المتوقع.
  final double overdue;

  /// مبلغ كل شهر من [cashHorizonMonths] بدءاً بالشهر الحالي، مع أول يوم فيه.
  final List<(DateTime, double)> months;

  /// ما يقع بعد نهاية الأفق.
  final double later;

  /// معتمد غير مدفوع بلا تاريخ إحالة ولا اعتماد.
  final double undated;

  /// مستخلصات مقدمة لم تُعتمد بعد (لا تدخل المجاميع).
  final double pending;

  /// التزامات الميزانية النشطة غير المدفوعة (بلا موعد، لا تدخل المجاميع).
  final double commitments;

  double get monthsTotal => months.fold(0.0, (a, b) => a + b.$2);

  /// إجمالي المتوقع صرفه من المستخلصات: المتأخر + الأشهر + ما بعد الأفق + بلا تاريخ.
  double get total => overdue + monthsTotal + later + undated;
}

/// يبني التوقع من المستخلصات والتزامات الميزانية في يوم [today].
CashForecast cashForecast(
  Iterable<ContractExtract> extracts,
  DateTime today, {
  Iterable<BudgetCommitment> commitments = const [],
  int lag = cashPayLagDays,
}) {
  final t = _d(today);
  final first = DateTime(t.year, t.month, 1);
  final buckets = List<double>.filled(cashHorizonMonths, 0);
  var overdue = 0.0, later = 0.0, undated = 0.0, pending = 0.0;
  for (final x in extracts) {
    if (x.status == 'submitted') {
      pending += x.net;
      continue;
    }
    if (!x.counted || x.unpaid <= 0) continue;
    final due = cashDueOf(x, lag: lag);
    if (due == null) {
      undated += x.unpaid;
    } else if (due.isBefore(t)) {
      overdue += x.unpaid;
    } else {
      final i = (due.year - t.year) * 12 + due.month - t.month;
      if (i >= cashHorizonMonths) {
        later += x.unpaid;
      } else {
        buckets[i] += x.unpaid;
      }
    }
  }
  var c = 0.0;
  for (final k in commitments) {
    if (k.isActive) c += k.unpaid;
  }
  return CashForecast(
    overdue: overdue,
    months: [for (var i = 0; i < cashHorizonMonths; i++) (DateTime(first.year, first.month + i, 1), buckets[i])],
    later: later,
    undated: undated,
    pending: pending,
    commitments: c,
  );
}
