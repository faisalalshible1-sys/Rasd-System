import 'package:flutter/material.dart';

import '../app_state.dart';
import '../contractor_account.dart';
import '../models.dart';
import '../print/export_dialog.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';
import 'project_detail.dart';

/// كشف حساب المقاولين (الإصدار 2.2.0): لكل مقاول عقوده ومستخلصاته والمدفوع والمستحق وأعمار الدين.
class ContractorsAccountView extends StatefulWidget {
  const ContractorsAccountView({super.key, required this.projects, required this.extracts});

  /// عقود النطاق الحالي في صفحة المالية ومستخلصاتها.
  final List<Project> projects;
  final List<ContractExtract> extracts;

  @override
  State<ContractorsAccountView> createState() => _ContractorsAccountViewState();
}

class _ContractorsAccountViewState extends State<ContractorsAccountView> {
  final Set<String> _open = {};
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final sem = Sem.of(context);
    final all = contractorAccounts(widget.projects, widget.extracts, DateTime.now());
    final shown = _q.trim().isEmpty ? all : all.where((a) => a.name.contains(_q.trim())).toList();
    final totalUnpaid = all.fold<double>(0, (s, a) => s + a.unpaid);
    final totalPaid = all.fold<double>(0, (s, a) => s + a.paid);
    final noCompany = widget.projects.where((p) => p.company.trim().isEmpty).length;

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SectionCard(
        title: 'كشف حساب المقاولين',
        icon: Icons.groups_2_outlined,
        subtitle: 'عقود كل مقاول (باسم الشركة في المشروع) وما نُفِّذ وما دُفع وما استحق ولم يُدفع، وأعمار المستحقات منذ الاعتماد.',
        trailing: ExportButton(sourceId: 'cycle:contractors', items: List<Object>.from(shown)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Wrap(spacing: 10, runSpacing: 10, children: [
            SizedBox(width: 190, child: KpiTile(label: 'المقاولون', value: '${all.length}')),
            SizedBox(width: 190, child: KpiTile(label: 'إجمالي المدفوع', value: fmtMoney(totalPaid))),
            SizedBox(width: 190, child: KpiTile(label: 'مستحق غير مدفوع', value: fmtMoney(totalUnpaid), color: totalUnpaid > 0 ? sem.wip : null)),
          ]),
          const SizedBox(height: 12),
          TextField(
            decoration: const InputDecoration(prefixIcon: Icon(Icons.search_rounded), hintText: 'بحث باسم المقاول', isDense: true, border: OutlineInputBorder()),
            onChanged: (v) => setState(() => _q = v),
          ),
          if (noCompany > 0)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text('$noCompany عقد بلا اسم شركة لا يدخل الكشف؛ سجّل الشركة في بيانات المشروع.', style: TextStyle(color: sem.muted, fontSize: 12)),
            ),
        ]),
      ),
      const SizedBox(height: 12),
      if (shown.isEmpty)
        const EmptyState(title: 'لا مقاولين لعرضهم', message: 'يظهر المقاول حين يُسجَّل اسم شركته في مشروع ضمن النطاق.', icon: Icons.groups_2_outlined)
      else
        for (final a in shown) Padding(padding: const EdgeInsets.only(bottom: 10), child: _card(context, sem, a)),
    ]);
  }

  Widget _card(BuildContext context, Sem sem, ContractorAccount a) {
    final open = _open.contains(a.name);
    return SectionCard(
      title: a.name,
      icon: Icons.business_rounded,
      subtitle: '${a.projects.length} عقد · القيمة بعد التغيير ${fmtMoney(a.adjusted)}',
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        if (a.hasOldDue) ToneBadge('مستحق قديم', color: sem.danger),
        IconButton(
          tooltip: open ? 'إخفاء التفاصيل' : 'عرض التفاصيل',
          onPressed: () => setState(() => open ? _open.remove(a.name) : _open.add(a.name)),
          icon: Icon(open ? Icons.expand_less_rounded : Icons.expand_more_rounded),
        ),
      ]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Wrap(spacing: 10, runSpacing: 10, children: [
          SizedBox(width: 170, child: KpiTile(label: 'المنفذ', value: fmtMoney(a.executed))),
          SizedBox(width: 170, child: KpiTile(label: 'المدفوع', value: fmtMoney(a.paid), sub: a.paidRatio == null ? null : '${(a.paidRatio! * 100).toStringAsFixed(1)}% من العقد')),
          SizedBox(width: 170, child: KpiTile(label: 'مستحق غير مدفوع', value: fmtMoney(a.unpaid), color: a.unpaid > 0 ? sem.wip : null)),
          SizedBox(width: 170, child: KpiTile(label: 'المتبقي للدفع', value: fmtMoney(a.remainingToPay))),
        ]),
        if (open) ...[
          const Divider(height: 24),
          Text('أعمار المستحقات غير المدفوعة', style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          for (var i = 0; i < 5; i++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(children: [
                Expanded(child: Text(contractorAgingLabels[i])),
                Text(fmtMoney(a.aging[i]), style: TextStyle(fontWeight: FontWeight.w600, color: i == 3 && a.aging[i] > 0 ? sem.danger : null)),
              ]),
            ),
          const SizedBox(height: 4),
          Text('التأمين المحتجز ${fmtMoney(a.retention)} · مستخلصات قيد الاعتماد ${fmtMoney(a.pending)}', style: TextStyle(color: sem.muted, fontSize: 12.5)),
          const SizedBox(height: 12),
          Row(children: [
            const Expanded(child: Text('العقود', style: TextStyle(fontWeight: FontWeight.w700))),
            ExportButton(sourceId: 'cycle:extracts', items: List<Object>.from(a.extracts)),
          ]),
          for (final p in a.projects)
            ListTile(
              contentPadding: EdgeInsets.zero,
              onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ProjectDetailPage(projectId: p.id))),
              title: Text(p.label, style: const TextStyle(fontSize: 13.5)),
              subtitle: Text(
                'القيمة ${fmtMoney(p.adjustedValue)} · المنفذ ${fmtMoney(p.executedValue)} · المدفوع ${fmtMoney(p.paidTotal)} · المستحق ${fmtMoney(p.outstanding)}',
                style: TextStyle(color: sem.muted, fontSize: 12),
              ),
            ),
        ],
      ]),
    );
  }
}
