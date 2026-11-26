import 'package:flutter/material.dart';

import '../app_state.dart';
import '../pm.dart';
import '../ui/board.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';
import 'pm_common.dart';
import 'risks.dart' show riskLevelColor;

// =====================================================================
// لوحة العرض: ملخص المحفظة في صفحة واحدة للعرض التقديمي والطباعة
// (ثمانية مؤشرات، جدول المشاريع، أبرز التنبيهات، أعلى المخاطر، ثلاثة رسوم)
// =====================================================================
class PmPresentationPage extends StatefulWidget {
  const PmPresentationPage({super.key});

  @override
  State<PmPresentationPage> createState() => _PmPresentationPageState();
}

class _PmPresentationPageState extends State<PmPresentationPage> {
  final _board = GlobalKey();

  static String _m(double v) => (v / 1000000).toStringAsFixed(2);

  /// رمز العقد للعرض: رقم العقد.
  static String _code(ProjectTrack t) => t.project.contractNo.trim();

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    if (!app.v7Ready) return const PmNotReady(title: 'لوحة العرض');
    final sem = Sem.of(context);
    final pm = app.pm;
    final cfg = app.pmConfig;
    final rc = app.riskConfig;
    final width = MediaQuery.sizeOf(context).width;
    final wide = width >= 1100;
    final tracks = pm.tracks.values.toList()..sort((a, b) => a.project.sortOrder.compareTo(b.project.sortOrder));

    // ---------------------------------------------------------------- المؤشرات الثمانية
    final done = tracks.where((t) => t.perf == 'done').length;
    final running = tracks.where((t) => t.isRunning).length;
    final anyValue = tracks.any((t) => (t.contractValue ?? 0) > 0);
    final revised = tracks.fold<double>(0, (a, t) => a + (t.revisedValue ?? 0));
    final late = tracks.where((t) => (t.forecastDelay ?? 0) > 0).length;
    final onTime = tracks.where((t) => t.forecastDelay != null && t.forecastDelay! <= 0).length;
    final avgField = pm.avgField;
    final kpis = [
      BoardKpi(label: 'عدد المشاريع', value: '${tracks.length}', sub: 'منجزة: $done  |  جارية: $running', color: sem.ok),
      BoardKpi(
        label: 'قيمة العقود (م.د.ل)',
        value: anyValue ? _m(pm.totalContractValue) : '—',
        sub: anyValue ? 'بعد التغييرات: ${_m(revised)}' : 'لم تُسجَّل قيم العقود بعد',
        color: const Color(0xFF2E7D9A),
      ),
      BoardKpi(
        label: 'التغييرات المعتمدة (م.د.ل)',
        value: _m(pm.approvedChangesValue),
        sub: pm.changesPct == null ? '${pm.approvedChanges} تغيير معتمد' : '${pctText(pm.changesPct!, digits: 1)} من قيمة العقود',
        color: (pm.changesPct ?? 0) > cfg.changeLimit ? sem.danger : const Color(0xFF7A5BA6),
      ),
      BoardKpi(
        label: 'التمديدات المعتمدة (يوم)',
        value: '${pm.extensions}',
        sub: 'أيام التأخير المسجلة: ${pm.delayDays}',
        color: sem.wip,
      ),
      BoardKpi(
        label: 'مشاريع متأخرة عن الموعد المعدّل',
        value: '$late',
        sub: 'في الموعد أو قبله: $onTime',
        color: late > 0 ? sem.danger : sem.ok,
      ),
      BoardKpi(
        label: 'المخاطر النشطة',
        value: '${pm.activeRisks}',
        sub: 'مرتفعة حالياً: ${pm.highRisksNow}  |  متصاعدة: ${pm.risingRisks}',
        color: pm.highRisksNow > 0 ? sem.danger : sem.wip,
      ),
      BoardKpi(
        label: 'المشاكل المفتوحة',
        value: '${pm.openIssues}',
        sub: 'متأخرة عن موعد الحل: ${pm.overdueIssues}',
        color: pm.overdueIssues > 0 ? sem.danger : sem.muted,
      ),
      BoardKpi(
        label: 'متوسط التقييم الميداني (من 5)',
        value: avgField == null ? '—' : avgField.toStringAsFixed(2),
        sub: avgField == null ? 'لا تقييمات بعد' : '${pm.evaluations.length} تقييم ميداني',
        color: const Color(0xFF5E6B1F),
      ),
    ];

    // ---------------------------------------------------------------- جدول المشاريع
    final kpiByName = {for (final k in pm.contractors) k.name: k};
    String grade(ProjectTrack t) {
      final k = kpiByName[t.project.company.trim()];
      if (k == null) return '—';
      return k.composite == null ? k.gradeName : '${k.gradeName} (${k.composite!.toStringAsFixed(0)})';
    }

    final rows = [
      for (final t in tracks)
        [
          _code(t),
          t.displayName,
          t.project.company,
          t.contractValue == null ? '—' : _m(t.contractValue!),
          '${t.extensionDays}',
          t.forecastDelay == null ? '—' : '${t.forecastDelay}',
          pctOrDash(t.changePct, digits: 1),
          '${t.activeRisks}',
          '${t.openIssues}',
          grade(t),
        ],
    ];
    final delays = [for (final t in tracks) t.forecastDelay].whereType<int>().toList();
    final scored = pm.contractors.where((k) => k.composite != null).toList();
    final totals = [
      'الإجمالي / المتوسط',
      '',
      '',
      anyValue ? _m(pm.totalContractValue) : '—',
      '${tracks.fold<int>(0, (a, t) => a + t.extensionDays)}',
      delays.isEmpty ? '—' : (delays.reduce((a, b) => a + b) / delays.length).toStringAsFixed(1),
      pctOrDash(pm.changesPct, digits: 1),
      '${tracks.fold<int>(0, (a, t) => a + t.activeRisks)}',
      '${tracks.fold<int>(0, (a, t) => a + t.openIssues)}',
      scored.isEmpty ? '—' : 'متوسط ${(scored.fold<double>(0, (a, k) => a + k.composite!) / scored.length).toStringAsFixed(0)}',
    ];

    final table = BoardPanel(
      title: 'ملخص المشاريع',
      icon: Icons.table_chart_outlined,
      trailing: 'القيم بالمليون دينار',
      child: _BoardTable(
        columns: const [
          'الرمز', 'المشروع', 'الشركة المنفذة', 'قيمة العقد', 'التمديد المعتمد (يوم)', 'التأخير عن الموعد المعدّل (يوم)', //
          'التغييرات من العقد', 'مخاطر نشطة', 'مشاكل مفتوحة', 'تقدير الشركة (الدرجة)',
        ],
        rows: rows,
        totals: totals,
        flags: [for (final t in tracks) (t.forecastDelay ?? 0) > 0],
      ),
    );

    // ---------------------------------------------------------------- التنبيهات وأعلى المخاطر
    final alerts = pm.alerts.where((a) => a.count > 0).toList()..sort((a, b) => b.count.compareTo(a.count));
    final alertsPanel = BoardPanel(
      title: 'أبرز التنبيهات',
      icon: Icons.notifications_active_outlined,
      child: alerts.isEmpty
          ? Text('لا تنبيهات حالياً.', style: TextStyle(color: sem.muted, fontSize: 12.5))
          : Column(children: [
              for (final a in alerts.take(7))
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Container(
                      width: 30,
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(color: sem.dangerSoft, borderRadius: BorderRadius.circular(6)),
                      child: Text('${a.count}', style: TextStyle(color: sem.danger, fontWeight: FontWeight.w900, fontSize: 12.5)),
                    ),
                    const SizedBox(width: 8),
                    Expanded(child: Text(a.label, style: const TextStyle(fontSize: 12.5, height: 1.4))),
                  ]),
                ),
            ]),
    );
    final top = pm.riskList.where((r) => r.isActive).toList()
      ..sort((x, y) => y.currentScore != x.currentScore ? y.currentScore.compareTo(x.currentScore) : y.initialScore.compareTo(x.initialScore));
    final risksPanel = BoardPanel(
      title: 'أعلى المخاطر النشطة (الدرجة الحالية)',
      icon: Icons.local_fire_department_outlined,
      child: top.isEmpty
          ? Text('لا مخاطر نشطة.', style: TextStyle(color: sem.muted, fontSize: 12.5))
          : Column(children: [
              for (final s in top.take(5))
                Builder(builder: (context) {
                  final c = riskLevelColor(context, rc.levelIndex(s.currentScore), rc.levels.length);
                  final proj = s.risk.projectId == null ? s.risk.projectGroup : (pm.track(s.risk.projectId!)?.displayName ?? '');
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Container(
                        width: 30,
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(color: c.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(6)),
                        child: Text('${s.currentScore}', style: TextStyle(color: c, fontWeight: FontWeight.w900, fontSize: 12.5)),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text('${s.risk.code} – ${s.risk.description}${proj.isEmpty ? '' : ' ($proj)'}',
                            maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5, height: 1.4)),
                      ),
                      const SizedBox(width: 6),
                      Text(s.currentLevel.name, style: TextStyle(color: c, fontWeight: FontWeight.w800, fontSize: 11.5)),
                    ]),
                  );
                }),
            ]),
    );

    // ---------------------------------------------------------------- الرسوم الثلاثة
    final delayChart = BoardPanel(
      title: 'التأخير عن الموعد المعدّل لكل مشروع (يوم)',
      icon: Icons.timelapse_rounded,
      child: HBarChart(
        labelWidth: wide ? 150 : 120,
        empty: 'يظهر التأخير بعد إدخال قياسات التقدم.',
        bars: [
          for (final t in tracks)
            if (t.forecastDelay != null)
              HBar(t.displayName, t.forecastDelay!.toDouble(), t.forecastDelay! > 0 ? sem.danger : sem.ok,
                  text: t.forecastDelay! > 0 ? '+${t.forecastDelay}' : '${t.forecastDelay}'),
        ],
        legend: [(sem.danger, 'متأخر'), (sem.ok, 'في الموعد أو قبله')],
      ),
    );
    final pareto = pm.delayAnalysis.pareto.where((g) => g.days > 0).toList();
    final causeChart = BoardPanel(
      title: 'أيام التأخير حسب السبب الرئيسي',
      icon: Icons.hourglass_bottom_rounded,
      child: HBarChart(
        labelWidth: wide ? 150 : 120,
        empty: 'لا أحداث تأخير مسجلة.',
        bars: [
          for (final g in pareto.take(8))
            HBar(g.key, g.days.toDouble(), pm.delayAnalysis.isVital(g) ? sem.wip : sem.muted.withValues(alpha: 0.6)),
        ],
        legend: pareto.isEmpty ? null : [(sem.wip, 'الأسباب الحيوية (80% من الأيام)')],
      ),
    );
    final initialBy = List<double>.filled(rc.levels.length, 0);
    final currentBy = List<double>.filled(rc.levels.length, 0);
    for (final s in pm.riskList) {
      initialBy[rc.levelIndex(s.initialScore)]++;
      if (s.isActive) currentBy[rc.levelIndex(s.currentScore)]++;
    }
    final levelChart = BoardPanel(
      title: 'المخاطر حسب المستوى: عند التسجيل مقابل الحالي',
      icon: Icons.stacked_bar_chart_rounded,
      child: PairBarChart(
        names: ('عند التسجيل', 'الحالي (النشطة)'),
        groups: [
          for (var i = rc.levels.length - 1; i >= 0; i--)
            (rc.levels[i].name, initialBy[i], currentBy[i], riskLevelColor(context, i, rc.levels.length)),
        ],
      ),
    );

    final ref = cfg.refDay;
    return PageBody(
      maxWidth: 1500,
      onRefresh: app.loadAll,
      children: [
        PageHeader(
          title: 'لوحة العرض',
          subtitle: 'ملخص المحفظة في صفحة واحدة للعرض التقديمي والطباعة · تتحدث تلقائياً من السجلات',
          icon: Icons.co_present_outlined,
          actions: [SaveBoardButton(boundaryKey: _board, fileName: 'لوحة العرض – متابعة المشاريع')],
        ),
        BoardFrame(
          boundaryKey: _board,
          title: 'لوحة العرض – ملخص مشاريع إعادة إعمار منطقة الصابري ووسط البلاد',
          org: '${app.orgName} – ${app.settings.orgParent}',
          date: pmDay(ref),
          footer: 'المصدر: «المخاطر ومتابعة المشاريع» في منظومة رصد – تتحدث هذه الصفحة تلقائياً من السجلات  |  ${app.orgName}',
          children: [
            ResponsiveGrid(minItemWidth: wide ? 170 : 150, spacing: 10, children: kpis),
            const SizedBox(height: 14),
            if (wide)
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(flex: 7, child: table),
                const SizedBox(width: 14),
                Expanded(
                  flex: 3,
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    alertsPanel,
                    const SizedBox(height: 14),
                    risksPanel,
                  ]),
                ),
              ])
            else ...[
              table,
              const SizedBox(height: 14),
              ResponsiveGrid(minItemWidth: 320, spacing: 14, children: [alertsPanel, risksPanel]),
            ],
            const SizedBox(height: 14),
            ResponsiveGrid(minItemWidth: wide ? 380 : 320, spacing: 14, children: [delayChart, causeChart, levelChart]),
          ],
        ),
      ],
    );
  }
}

/// جدول مضغوط للوحة العرض بسطر إجمالي، ويُظلَّل الصف المتأخر.
class _BoardTable extends StatelessWidget {
  const _BoardTable({required this.columns, required this.rows, required this.totals, required this.flags});

  final List<String> columns;
  final List<List<String>> rows;
  final List<String> totals;
  final List<bool> flags;

  @override
  Widget build(BuildContext context) {
    final sem = Sem.of(context);
    if (rows.isEmpty) return Text('لا عقود بعد.', style: TextStyle(color: sem.muted, fontSize: 12.5));
    TextStyle cell([bool bold = false]) =>
        TextStyle(fontSize: 12, fontWeight: bold ? FontWeight.w800 : FontWeight.w500, fontFeatures: const [FontFeature.tabularFigures()]);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        headingRowHeight: 46,
        dataRowMinHeight: 32,
        dataRowMaxHeight: 48,
        columnSpacing: 14,
        horizontalMargin: 6,
        headingTextStyle: TextStyle(fontWeight: FontWeight.w800, color: sem.muted, fontSize: 11.5),
        columns: [
          for (final c in columns)
            DataColumn(label: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 92), child: Text(c, maxLines: 3))),
        ],
        rows: [
          for (var i = 0; i < rows.length; i++)
            DataRow(
              color: flags[i] ? WidgetStatePropertyAll(sem.dangerSoft.withValues(alpha: 0.6)) : null,
              cells: [
                for (var j = 0; j < rows[i].length; j++)
                  DataCell(ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: j == 1 ? 260 : (j == 2 ? 170 : 120)),
                    child: Text(rows[i][j], maxLines: 2, overflow: TextOverflow.ellipsis, style: cell(j == 0)),
                  )),
              ],
            ),
          DataRow(
            color: WidgetStatePropertyAll(sem.surface2),
            cells: [
              for (final v in totals) DataCell(Text(v, maxLines: 1, style: cell(true))),
            ],
          ),
        ],
      ),
    );
  }
}
