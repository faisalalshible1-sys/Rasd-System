import 'package:flutter/material.dart';

import '../app_state.dart';
import '../cashflow.dart';
import '../models.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';

const _monthNames = ['يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو', 'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر'];

/// التدفق النقدي والمدفوعات المتوقعة (الإصدار 2.1.0): متى يُنتظر صرف المستخلصات المعتمدة والمحالة.
class CashflowView extends StatelessWidget {
  const CashflowView({super.key, required this.extracts});

  /// مستخلصات النطاق الحالي في صفحة المالية.
  final List<ContractExtract> extracts;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final sem = Sem.of(context);
    final f = cashForecast(extracts, DateTime.now(), commitments: app.canSeeBudget ? app.budgetCommitments : const []);
    final peak = [f.overdue, f.later, f.undated, ...f.months.map((m) => m.$2)].fold(0.0, (a, b) => a > b ? a : b);

    Widget bar(String title, double v, {Color? color, String? sub}) => BarRow(
          title: title,
          trailing: fmtMoney(v),
          subtitle: sub,
          meter: ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(value: peak <= 0 ? 0 : v / peak, minHeight: 10, color: color ?? sem.wip, backgroundColor: sem.surface2),
          ),
        );

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SectionCard(
        title: 'التدفق النقدي والمدفوعات المتوقعة',
        icon: Icons.timeline_rounded,
        subtitle: 'غير المدفوع من المستخلصات المعتمدة والمحالة، موزَّعاً على الأشهر بموعد صرف متوقع = تاريخ الإحالة (أو الاعتماد) + $cashPayLagDays يوماً.',
        child: Wrap(spacing: 10, runSpacing: 10, children: [
          SizedBox(width: 190, child: KpiTile(label: 'إجمالي المتوقع صرفه', value: fmtMoney(f.total))),
          SizedBox(width: 190, child: KpiTile(label: 'متأخر عن موعده', value: fmtMoney(f.overdue), color: f.overdue > 0 ? sem.danger : null)),
          SizedBox(width: 190, child: KpiTile(label: 'مستخلصات قيد الاعتماد', value: fmtMoney(f.pending), sub: 'لا تدخل الإجمالي')),
          if (app.canSeeBudget)
            SizedBox(width: 190, child: KpiTile(label: 'التزامات ميزانية غير مدفوعة', value: fmtMoney(f.commitments), sub: 'بلا موعد، لا تدخل الإجمالي')),
        ]),
      ),
      const SizedBox(height: 12),
      SectionCard(
        title: 'الجدول الزمني',
        icon: Icons.bar_chart_rounded,
        child: Column(children: [
          if (f.overdue > 0) bar('متأخر عن موعده', f.overdue, color: sem.danger),
          for (final m in f.months) bar('${_monthNames[m.$1.month - 1]} ${m.$1.year}', m.$2),
          if (f.later > 0) bar('بعد ذلك', f.later),
          if (f.undated > 0) bar('بلا تاريخ إحالة أو اعتماد', f.undated, color: sem.na, sub: 'سجّل تاريخ الاعتماد في المستخلص ليُوضع في شهره'),
          if (f.total <= 0) Text('لا مستخلصات معتمدة غير مدفوعة.', style: TextStyle(color: sem.muted)),
        ]),
      ),
    ]);
  }
}
