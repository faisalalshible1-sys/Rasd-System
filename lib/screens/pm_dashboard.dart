import 'package:flutter/material.dart';

import '../app_state.dart';
import '../pm.dart';
import '../services/export.dart';
import '../ui/charts.dart';
import '../ui/motion.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';
import 'hub.dart' show sectionColor;
import 'pm_common.dart';
import 'pm_projects.dart';

// =====================================================================
// لوحة القيادة الموحدة لمشاريع إعادة الإعمار (تتحدث تلقائياً من جميع السجلات)
// =====================================================================
class PmDashboardPage extends StatefulWidget {
  const PmDashboardPage({super.key});

  @override
  State<PmDashboardPage> createState() => _PmDashboardPageState();
}

class _PmDashboardPageState extends State<PmDashboardPage> {
  String _curve = '';
  bool _exporting = false;

  Future<void> _export(AppState app) async {
    setState(() => _exporting = true);
    try {
      final r = await exportPmXlsx(app);
      if (mounted && r != null) showToast(context, 'صُدّر ملف متابعة المشاريع');
    } catch (e) {
      if (mounted) showToast(context, friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    if (!app.v7Ready) return const PmNotReady(title: 'لوحة القيادة');
    final pm = app.pm;
    final cfg = app.pmConfig;
    final sem = Sem.of(context);
    final accent = sectionColor(context, 'risks');
    final narrow = MediaQuery.sizeOf(context).width < 700;
    final pc = pm.perfCounts;
    final late = (pc['slight'] ?? 0) + (pc['critical'] ?? 0);
    final alerts = pm.alerts.where((a) => a.count > 0).toList();
    final withCurve = pm.tracks.values.where((t) => t.measurements.length >= 2).toList()
      ..sort((a, b) => a.project.sortOrder.compareTo(b.project.sortOrder));
    final curve = withCurve.where((t) => t.project.id == _curve).firstOrNull ?? withCurve.firstOrNull;
    final curvePicker = curve == null
        ? const SizedBox.shrink()
        : SelectField(
            label: 'المشروع',
            value: curve.project.id,
            items: [for (final t in withCurve) (t.project.id, pmProjectName(app, t.project.id))],
            onChanged: (v) => setState(() => _curve = v),
          );
    final summary = pm.tracks.values.where((t) => t.measurements.isNotEmpty || t.start != null).toList()
      ..sort((a, b) => a.project.sortOrder.compareTo(b.project.sortOrder));
    final best = pm.bestContractor, worst = pm.worstContractor;

    return PageBody(
      maxWidth: 1300,
      onRefresh: app.loadAll,
      children: staggered([
        PageHeader(
          title: 'لوحة القيادة الموحدة',
          subtitle: 'مشاريع إعادة الإعمار · تاريخ الإسناد ${pmDay(pm.ref)}${cfg.refDate == null ? '' : ' (مثبّت في الإعدادات)'}',
          icon: Icons.space_dashboard_outlined,
          actions: [
            OutlinedButton.icon(
              onPressed: _exporting ? null : () => _export(app),
              icon: _exporting
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.file_download_outlined),
              label: const Text('تصدير Excel'),
            ),
          ],
        ),
        ResponsiveGrid(minItemWidth: narrow ? 150 : 210, spacing: 10, children: [
          StatCard(
              label: 'إجمالي المشاريع',
              value: '${pm.tracks.length}',
              sub: pm.totalContractValue == 0 ? null : 'قيمة العقود ${compactMoney(pm.totalContractValue)}',
              icon: Icons.folder_open_rounded,
              color: accent,
              onTap: () => app.setTab(PmTabs.projects)),
          StatCard(label: 'المشاريع الجارية', value: '${pm.running.length}', sub: 'لم يبدأ: ${pc['not_started'] ?? 0}', icon: Icons.play_circle_outline_rounded),
          StatCard(
              label: 'مشاريع متأخرة',
              value: '$late',
              sub: 'منها حرج: ${pc['critical'] ?? 0}',
              icon: Icons.running_with_errors_rounded,
              color: late > 0 ? sem.danger : sem.ok,
              onTap: () => app.setTab(PmTabs.projects)),
          StatCard(label: 'مشاريع منجزة', value: '${pc['done'] ?? 0}', sub: 'متقدمة: ${pc['ahead'] ?? 0}', icon: Icons.verified_outlined, color: sem.ok),
          StatCard(label: 'الإنجاز الفعلي (موزون)', value: pctOrDash(pm.weightedActual), sub: 'للمشاريع الجارية', icon: Icons.trending_up_rounded),
          StatCard(label: 'الإنجاز المخطط (موزون)', value: pctOrDash(pm.weightedPlanned), sub: 'للمشاريع الجارية', icon: Icons.flag_outlined),
          StatCard(
              label: 'مؤشر أداء المحفظة SPI',
              value: spiText(pm.portfolioSpi),
              sub: 'فعلي ÷ مخطط',
              icon: Icons.speed_rounded,
              color: pm.portfolioSpi == null ? sem.muted : (pm.portfolioSpi! >= cfg.spiOk ? sem.ok : (pm.portfolioSpi! >= cfg.spiWarn ? sem.wip : sem.danger))),
        ]),
        const SizedBox(height: 10),
        ResponsiveGrid(minItemWidth: narrow ? 150 : 210, spacing: 10, children: [
          StatCard(
              label: 'مخاطر نشطة',
              value: '${pm.activeRisks}',
              sub: 'مسجلة: ${app.risks.length}',
              icon: Icons.warning_amber_rounded,
              onTap: () => app.setTab(PmTabs.riskRegister)),
          StatCard(
              label: 'مخاطر مرتفعة حالياً',
              value: '${pm.highRisksNow}',
              sub: 'متصاعدة ▲: ${pm.risingRisks}',
              icon: Icons.priority_high_rounded,
              color: pm.highRisksNow > 0 ? sem.danger : sem.ok),
          StatCard(
              label: 'مشاكل مفتوحة',
              value: '${pm.openIssues}',
              sub: 'متأخرة الحل: ${pm.overdueIssues}',
              icon: Icons.report_problem_outlined,
              color: pm.overdueIssues > 0 ? sem.danger : null,
              onTap: () => app.setTab(PmTabs.issues)),
          StatCard(
              label: 'أيام التأخير المسجلة',
              value: '${pm.delayDays}',
              sub: 'على المسار الحرج: ${pm.criticalDelayDays}',
              icon: Icons.hourglass_bottom_rounded,
              onTap: () => app.setTab(PmTabs.delays)),
          StatCard(label: 'التمديدات المعتمدة', value: '${pm.extensions} يوم', sub: 'أحداث قائمة: ${pm.ongoingDelays}', icon: Icons.more_time_rounded),
          StatCard(
              label: 'التغييرات المعتمدة',
              value: compactMoney(pm.approvedChangesValue),
              sub: 'عدد المعتمدة: ${pm.approvedChanges}',
              icon: Icons.change_circle_outlined,
              onTap: () => app.setTab(PmTabs.changes)),
          StatCard(
              label: 'نسبة التغييرات من العقود',
              value: pctOrDash(pm.changesPct, digits: 1),
              sub: 'بانتظار البت: ${pm.pendingChanges}',
              icon: Icons.percent_rounded,
              color: (pm.changesPct ?? 0) > cfg.changeLimit ? sem.danger : null),
        ]),
        const SizedBox(height: 10),
        ResponsiveGrid(minItemWidth: narrow ? 150 : 210, spacing: 10, children: [
          StatCard(
              label: 'الدروس الموثقة',
              value: '${app.pmLessons.length}',
              sub: 'مُطبَّقة: ${pm.appliedLessons}',
              icon: Icons.school_outlined,
              onTap: () => app.setTab(PmTabs.lessons)),
          StatCard(
              label: 'دروس بانتظار الاعتماد',
              value: '${pm.proposedLessons}',
              sub: 'معتمدة: ${pm.approvedLessons}',
              icon: Icons.pending_actions_outlined,
              color: pm.proposedLessons > 0 ? sem.wip : null),
          StatCard(
              label: 'متوسط التقييم الميداني',
              value: pm.avgField?.toStringAsFixed(2) ?? '—',
              sub: 'من 5 – ${app.pmEvaluations.length} تقييماً',
              icon: Icons.fact_check_outlined,
              onTap: () => app.setTab(PmTabs.contractors)),
          StatCard(
              label: 'الشركة الأعلى أداءً',
              value: best?.name ?? '—',
              sub: best?.composite == null ? 'لا توجد درجات بعد' : 'الدرجة ${best!.composite!.toStringAsFixed(0)} من 100',
              icon: Icons.emoji_events_outlined,
              color: sem.ok),
          StatCard(
              label: 'الشركة الأدنى أداءً',
              value: worst?.name ?? '—',
              sub: worst?.composite == null ? 'لا توجد درجات بعد' : 'الدرجة ${worst!.composite!.toStringAsFixed(0)} من 100',
              icon: Icons.trending_down_rounded,
              color: worst == null ? null : sem.danger),
          StatCard(
              label: 'مراجعات مخاطر متأخرة',
              value: '${pm.overdueReviews}',
              sub: 'مستحقة قريباً: ${pm.soonReviews}',
              icon: Icons.event_busy_outlined,
              color: pm.overdueReviews > 0 ? sem.danger : null,
              onTap: () => app.setTab(PmTabs.riskRegister)),
          StatCard(
              label: 'مشاريع دون تحديث للتقدم',
              value: '${pm.staleProjects}',
              sub: 'أكثر من ${cfg.staleDays} أيام',
              icon: Icons.update_disabled_rounded,
              color: pm.staleProjects > 0 ? sem.wip : null,
              onTap: () => app.setTab(PmTabs.progress)),
        ]),
        const SizedBox(height: 16),
        SectionCard(
          title: 'أبرز التنبيهات والملاحظات',
          icon: Icons.notifications_active_outlined,
          subtitle: alerts.isEmpty ? 'لا تنبيهات حالياً.' : '${alerts.length} بنداً يحتاج إجراء. اضغط البند لفتح مرجعه.',
          child: Column(children: [
            for (final a in pm.alerts)
              InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: () => app.setTab(a.tab),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 4),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Container(
                      width: 34,
                      alignment: Alignment.center,
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      decoration: BoxDecoration(
                        color: (a.count > 0 ? sem.danger : sem.ok).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text('${a.count}',
                          style: TextStyle(fontWeight: FontWeight.w900, color: a.count > 0 ? sem.danger : sem.ok)),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(a.label, style: TextStyle(fontWeight: FontWeight.w700, color: a.count > 0 ? null : sem.muted)),
                        if (a.count > 0) Text(a.action, style: TextStyle(color: sem.muted, fontSize: 12.5)),
                      ]),
                    ),
                    Icon(Icons.chevron_left_rounded, color: sem.muted),
                  ]),
                ),
              ),
          ]),
        ),
        const SizedBox(height: 14),
        ResponsiveGrid(minItemWidth: 430, spacing: 14, children: [
          SectionCard(
            title: 'المشاريع حسب مؤشر الأداء الزمني',
            icon: Icons.donut_large_rounded,
            child: pm.tracks.isEmpty
                ? const EmptyState(title: 'لا مشاريع')
                : Column(children: [
                    StackBar(
                      format: (v) => v.toInt().toString(),
                      parts: [
                        for (final k in perfKeys)
                          if ((pc[k] ?? 0) > 0) (perfLabels[k]!, (pc[k] ?? 0).toDouble(), perfColor(context, k)),
                      ],
                    ),
                    const SizedBox(height: 10),
                    for (final k in perfKeys)
                      if ((pc[k] ?? 0) > 0)
                        PmKv(perfLabels[k]!, '${pc[k]} · ${pctText((pc[k] ?? 0) / pm.tracks.length)}', color: perfColor(context, k)),
                  ]),
          ),
          SectionCard(
            title: 'التغييرات المعتمدة حسب السبب',
            icon: Icons.pie_chart_outline_rounded,
            child: pm.approvedChanges == 0
                ? Text('لا تغييرات معتمدة بعد.', style: TextStyle(color: sem.muted))
                : BreakdownChart(
                    items: [
                      for (final e in pm.changesByReason.entries)
                        if (e.value.value != 0) (e.key, e.value.value.abs()),
                    ],
                    format: compactMoney,
                  ),
          ),
        ]),
        const SizedBox(height: 14),
        SectionCard(
          title: 'ملخص أداء المشاريع',
          icon: Icons.table_rows_outlined,
          subtitle: 'المشاريع التي لها برنامج زمني أو قياسات تقدم. اضغط «سجل المشاريع» للتفاصيل.',
          trailing: TextButton(onPressed: () => app.setTab(PmTabs.projects), child: const Text('سجل المشاريع')),
          child: PmTable(
            columns: const ['العقد', 'الشركة', 'المخطط', 'الفعلي', 'الانحراف', 'SPI', 'التأخير المتوقع', 'مخاطر مرتفعة', 'مشاكل مفتوحة', 'نسبة التغييرات', 'مؤشر الأداء'],
            rows: [
              for (final t in summary)
                [
                  pmProjectName(app, t.project.id),
                  t.project.company,
                  pctOrDash(t.planned, digits: 1),
                  pctOrDash(t.actual, digits: 1),
                  pctOrDash(t.deviation, digits: 1),
                  spiText(t.spi),
                  t.forecastDelay == null ? '—' : '${t.forecastDelay}',
                  '${t.highRisksNow}',
                  '${t.openIssues}',
                  pctOrDash(t.changePct, digits: 1),
                  perfLabels[t.perf] ?? '',
                ],
            ],
          ),
        ),
        if (curve != null) ...[
          const SizedBox(height: 14),
          SectionCard(
            title: 'منحنى تقدم مشروع',
            icon: Icons.stacked_line_chart_rounded,
            subtitle: 'SPI ${spiText(curve.spi)} · ${perfLabels[curve.perf]} · الإنجاز المتوقع ${curve.forecastEnd == null ? 'غير محدد' : pmDay(curve.forecastEnd)}',
            // على الشاشات الضيقة يُنقل اختيار المشروع تحت العنوان حتى لا يضيق العنوان
            trailing: narrow ? null : SizedBox(width: 260, child: curvePicker),
            child: narrow
                ? Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    curvePicker,
                    const SizedBox(height: 12),
                    ProgressCurve(track: curve),
                  ])
                : ProgressCurve(track: curve),
          ),
        ],
      ], stepMs: 35),
    );
  }
}
