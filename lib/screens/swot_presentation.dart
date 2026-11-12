import 'package:flutter/material.dart';

import '../app_state.dart';
import '../registers.dart';
import '../ui/board.dart';
import '../ui/charts.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';
import 'hub.dart' show sectionColor;
import 'risks.dart' show RegistersNotReady;
import 'swot.dart' show swotColor, strategyColor, swotPriorityColor, commitmentColor, IeMatrix;

// =====================================================================
// تحليل SWOT – لوحة العرض التنفيذية: صفحة واحدة للعرض والطباعة
// =====================================================================
class SwotPresentationPage extends StatefulWidget {
  const SwotPresentationPage({super.key});

  @override
  State<SwotPresentationPage> createState() => _SwotPresentationPageState();
}

class _SwotPresentationPageState extends State<SwotPresentationPage> {
  final _board = GlobalKey();

  static String _day(DateTime d) => '${d.year}/${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    if (!app.v6Ready) return const RegistersNotReady(title: 'لوحة العرض');
    final sem = Sem.of(context);
    final a = app.swot;
    final meta = app.swotMeta;
    final accent = sectionColor(context, 'swot');
    final width = MediaQuery.sizeOf(context).width;
    final wide = width >= 1100;
    final today = a.today;

    // ---------------------------------------------------------------- الصف الأول: التصنيفات ونتيجتا IFE وEFE
    final kindCards = [
      for (final k in swotKinds)
        BoardKpi(
          label: swotKindTitles[k]!,
          value: '${a.ofKind(k).length}',
          sub: 'عالية الأولوية: ${a.ofKind(k).where((f) => f.level == 'high').length}',
          color: swotColor(context, k),
        ),
      BoardKpi(
        label: 'نتيجة IFE – العوامل الداخلية',
        value: a.ifeTotal.toStringAsFixed(2),
        sub: a.ifeTotal >= 2.5 ? 'فوق المتوسط المرجعي (2.50)' : 'دون المتوسط المرجعي (2.50)',
        color: a.ifeTotal >= 2.5 ? sem.ok : sem.danger,
      ),
      BoardKpi(
        label: 'نتيجة EFE – العوامل الخارجية',
        value: a.efeTotal.toStringAsFixed(2),
        sub: a.efeTotal >= 2.5 ? 'فوق المتوسط المرجعي (2.50)' : 'دون المتوسط المرجعي (2.50)',
        color: a.efeTotal >= 2.5 ? sem.ok : sem.danger,
      ),
    ];

    // ---------------------------------------------------------------- الصف الثاني: التنفيذ والتغطية
    final inProgress = a.actions.where((x) => x.status == 'in_progress').length;
    final uncovered = a.factors.where((f) => (f.kind == 'W' || f.kind == 'T') && !a.covered(f)).length;
    final unused = a.factors.where((f) => (f.kind == 'S' || f.kind == 'O') && !a.covered(f)).length;
    final coverage = a.factors.isEmpty ? null : a.factors.where(a.covered).length / a.factors.length;
    final avg = a.avgProgress, planned = a.avgPlanned;
    final follow = a.lateOrStalled + a.awaiting;
    final execCards = [
      BoardKpi(label: 'إجمالي عوامل SWOT', value: '${a.factors.length}', sub: 'عالية الأولوية: ${a.highFactors}', color: accent),
      BoardKpi(
        label: 'استراتيجيات TOWS',
        value: '${a.strategies.length}',
        sub: 'عالية الأولوية: ${a.strategies.where((s) => s.priority == 'high').length}',
        color: accent,
      ),
      BoardKpi(label: 'الإجراءات التنفيذية', value: '${a.actionsTotal}', sub: 'مكتملة: ${a.completed}  •  قيد التنفيذ: $inProgress', color: sem.ok),
      BoardKpi(
        label: 'متوسط الإنجاز الفعلي',
        value: avg == null ? '—' : pctText(avg),
        sub: planned == null ? null : 'المخطط حتى اليوم: ${pctText(planned)}',
        color: avg != null && planned != null && avg + 0.1 < planned ? sem.wip : sem.ok,
      ),
      BoardKpi(
        label: 'إجراءات تتطلب متابعة',
        value: '$follow',
        sub: 'متأخرة: ${a.lateOrStalled}  •  بانتظار التحديث: ${a.awaiting}',
        color: follow > 0 ? sem.danger : sem.muted,
      ),
      BoardKpi(
        label: 'تغطية العوامل بالمعالجة والاستثمار',
        value: coverage == null ? '—' : pctText(coverage),
        sub: 'غير مُعالَج: $uncovered  •  غير مُستثمَر: $unused',
        color: uncovered + unused > 0 ? sem.wip : sem.ok,
      ),
    ];

    // ---------------------------------------------------------------- المصفوفة: أعلى 4 عوامل في كل تصنيف
    List<SwotFactor> top4(String k) => a.ofKind(k)
      ..sort((x, y) => y.priority != x.priority ? y.priority.compareTo(x.priority) : x.code.compareTo(y.code));
    Widget quadrant(String k) {
      final c = swotColor(context, k);
      final list = top4(k);
      return Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: c.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: c.withValues(alpha: 0.45)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('${swotKindTitles[k]}   –   العدد: ${list.length}',
              style: TextStyle(fontWeight: FontWeight.w900, color: c, fontSize: 13.5)),
          const SizedBox(height: 6),
          if (list.isEmpty) Text('لا عوامل.', style: TextStyle(color: sem.muted, fontSize: 12)),
          for (final f in list.take(4))
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(5)),
                  child: Text(f.code, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 11.5)),
                ),
                const SizedBox(width: 8),
                Expanded(child: Text(f.factor, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5, height: 1.4))),
                const SizedBox(width: 6),
                Text('${f.priority}',
                    style: TextStyle(fontWeight: FontWeight.w900, fontSize: 12.5, color: swotPriorityColor(sem, f.level))),
              ]),
            ),
        ]),
      );
    }

    final matrix = BoardPanel(
      title: 'مصفوفة SWOT – أعلى 4 عوامل أولوية في كل تصنيف',
      icon: Icons.grid_view_rounded,
      trailing: 'الرقم = الأهمية × الاستعجال (من 25)',
      child: ResponsiveGrid(minItemWidth: 280, spacing: 10, children: [for (final k in swotKinds) quadrant(k)]),
    );
    final ie = BoardPanel(
      title: 'مصفوفة IE والتوجه الاستراتيجي',
      icon: Icons.explore_outlined,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        IeMatrix(cell: a.ieCell, ife: a.ifeTotal, efe: a.efeTotal),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: accent.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(8)),
          child: Text('الموقع ${SwotAnalysis.roman[a.ieCell - 1]} ← التوجه الاستراتيجي المقترح: ${a.direction}',
              style: TextStyle(fontWeight: FontWeight.w800, color: accent)),
        ),
      ]),
    );

    // ---------------------------------------------------------------- الرسوم
    final pColors = {for (final p in swotPriorities) p: swotPriorityColor(sem, p)};
    final factorsChart = BoardPanel(
      title: 'عوامل SWOT حسب التصنيف والأولوية',
      icon: Icons.stacked_bar_chart_rounded,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (final k in swotKinds)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(children: [
              SizedBox(width: 92, child: Text(swotKindTitles[k]!, style: const TextStyle(fontSize: 12))),
              Expanded(
                child: StackBar(
                  legend: false,
                  height: 13,
                  parts: [
                    for (final p in swotPriorities)
                      (swotPriorityLabels[p]!, a.ofKind(k).where((f) => f.level == p).length.toDouble(), pColors[p]!),
                  ],
                ),
              ),
              SizedBox(
                width: 34,
                child: Text('${a.ofKind(k).length}', textAlign: TextAlign.end, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12)),
              ),
            ]),
          ),
        const SizedBox(height: 6),
        Legend(items: [for (final p in swotPriorities) (pColors[p]!, 'أولوية ${swotPriorityLabels[p]}')]),
      ]),
    );
    final towsChart = BoardPanel(
      title: 'الاستراتيجيات والإجراءات حسب نوع TOWS',
      icon: Icons.alt_route_rounded,
      child: PairBarChart(
        names: ('الاستراتيجيات', 'الإجراءات'),
        labelWidth: 120,
        groups: [
          for (final k in strategyKinds)
            (
              '$k · ${strategyDirections[k]}',
              a.strategies.where((s) => s.kind == k).length.toDouble(),
              a.actions.where((x) => a.strategyByCode[x.strategyCode]?.kind == k).length.toDouble(),
              strategyColor(context, k),
            ),
        ],
      ),
    );
    final statusColors = <String, Color>{
      'not_started': sem.muted,
      'in_progress': const Color(0xFF2B62A8),
      'completed': sem.ok,
      'stalled': sem.danger,
      'on_hold': sem.wip,
    };
    final statusItems = [
      for (final s in actionStatuses)
        if (a.actions.any((x) => x.status == s)) (s, a.actions.where((x) => x.status == s).length.toDouble()),
    ];
    final statusChart = BoardPanel(
      title: 'حالة الإجراءات التنفيذية',
      icon: Icons.donut_large_rounded,
      child: statusItems.isEmpty
          ? Text('لا إجراءات بعد.', style: TextStyle(color: sem.muted, fontSize: 12.5))
          : BreakdownChart(
              type: 'donut',
              size: 150,
              centerTitle: 'إجراء',
              centerValue: '${a.actionsTotal}',
              format: (v) => v.toStringAsFixed(0),
              items: [for (final i in statusItems) (actionStatusLabels[i.$1] ?? i.$1, i.$2)],
              colors: [for (final i in statusItems) statusColors[i.$1] ?? sem.muted],
            ),
    );

    // ---------------------------------------------------------------- الأقسام والتنبيهات
    final depts = a.byDepartment().entries.toList()..sort((x, y) => y.value.count.compareTo(x.value.count));
    final deptPanel = BoardPanel(
      title: 'الأداء حسب القسم المسؤول',
      icon: Icons.groups_2_outlined,
      child: depts.isEmpty
          ? Text('لا إجراءات بعد.', style: TextStyle(color: sem.muted, fontSize: 12.5))
          : SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                headingRowHeight: 36,
                dataRowMinHeight: 30,
                dataRowMaxHeight: 40,
                columnSpacing: 16,
                horizontalMargin: 6,
                headingTextStyle: TextStyle(fontWeight: FontWeight.w800, color: sem.muted, fontSize: 11.5),
                columns: const [
                  DataColumn(label: Text('القسم')),
                  DataColumn(label: Text('الإجراءات'), numeric: true),
                  DataColumn(label: Text('متأخرة / متعثرة'), numeric: true),
                  DataColumn(label: Text('الإنجاز الفعلي'), numeric: true),
                  DataColumn(label: Text('الإنجاز المخطط'), numeric: true),
                ],
                rows: [
                  for (final e in depts)
                    DataRow(cells: [
                      DataCell(Text(e.key, style: const TextStyle(fontSize: 12))),
                      DataCell(Text('${e.value.count}', style: const TextStyle(fontSize: 12))),
                      DataCell(Text('${e.value.late}',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: e.value.late > 0 ? sem.danger : null))),
                      DataCell(Text(e.value.actual == null ? '—' : pctText(e.value.actual!), style: const TextStyle(fontSize: 12))),
                      DataCell(Text(e.value.planned == null ? '—' : pctText(e.value.planned!), style: const TextStyle(fontSize: 12))),
                    ]),
                ],
              ),
            ),
    );
    final alerts = a.alerts;
    final alertsPanel = BoardPanel(
      title: 'تنبيهات – إجراءات تتطلب متابعة',
      icon: Icons.notifications_active_outlined,
      trailing: alerts.length > 5 ? 'أول 5 من ${alerts.length}' : null,
      child: alerts.isEmpty
          ? Text('لا توجد إجراءات تتطلب متابعة حالياً.', style: TextStyle(color: sem.muted, fontSize: 12.5))
          : Column(children: [
              for (final x in alerts.take(5))
                Builder(builder: (context) {
                  final c = x.commitment(today);
                  final col = commitmentColor(sem, c);
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      SizedBox(width: 36, child: Text(x.code, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12))),
                      Expanded(child: Text(x.action, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5, height: 1.4))),
                      const SizedBox(width: 6),
                      ToneBadge(commitmentLabels[c] ?? c, color: col),
                    ]),
                  );
                }),
            ]),
    );

    return PageBody(
      maxWidth: 1500,
      onRefresh: app.loadAll,
      children: [
        PageHeader(
          title: 'لوحة العرض',
          subtitle: 'لوحة تنفيذية في صفحة واحدة للعرض التقديمي والطباعة · تتحدث تلقائياً من السجل والاستراتيجيات والخطة',
          icon: Icons.co_present_outlined,
          actions: [SaveBoardButton(boundaryKey: _board, fileName: 'لوحة العرض – تحليل SWOT')],
        ),
        BoardFrame(
          boundaryKey: _board,
          accent: accent,
          title: 'تحليل SWOT الاستراتيجي – لوحة العرض التنفيذية',
          org: '${app.orgName}   |   ${app.settings.orgParent}   |   الإصدار ${meta.version}',
          date: _day(today),
          footer: 'تتحدث هذه اللوحة تلقائياً من سجل العوامل والتقييم المرجح واستراتيجيات TOWS وخطة التنفيذ – لا تتطلب أي إدخال يدوي',
          children: [
            ResponsiveGrid(minItemWidth: wide ? 170 : 150, spacing: 10, children: kindCards),
            const SizedBox(height: 10),
            ResponsiveGrid(minItemWidth: wide ? 170 : 150, spacing: 10, children: execCards),
            const SizedBox(height: 14),
            if (wide)
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(flex: 7, child: matrix),
                const SizedBox(width: 14),
                Expanded(flex: 3, child: ie),
              ])
            else ...[
              matrix,
              const SizedBox(height: 14),
              ie,
            ],
            const SizedBox(height: 14),
            ResponsiveGrid(minItemWidth: wide ? 380 : 320, spacing: 14, children: [factorsChart, towsChart, statusChart]),
            const SizedBox(height: 14),
            ResponsiveGrid(minItemWidth: 420, spacing: 14, children: [deptPanel, alertsPanel]),
          ],
        ),
      ],
    );
  }
}
