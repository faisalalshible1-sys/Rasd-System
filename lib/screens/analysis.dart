import 'package:flutter/material.dart';

import '../app_state.dart';
import '../models.dart';
import '../services/export.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';
import 'dashboard.dart';

/// التحليل: إنجاز المراحل والنماذج، التوزيع، والجداول حسب المالك والشركة. UC-05: التصدير.
class AnalysisPage extends StatefulWidget {
  const AnalysisPage({super.key});

  @override
  State<AnalysisPage> createState() => _AnalysisPageState();
}

class _AnalysisPageState extends State<AnalysisPage> {
  bool _exporting = false;

  Future<void> _export(AppState app) async {
    setState(() => _exporting = true);
    try {
      final list = app.scoped..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
      final path = await exportProjectsXlsx(app, list);
      if (!mounted) return;
      if (path != null && path.isNotEmpty) showToast(context, 'حُفظ ملف Excel');
    } catch (e) {
      if (mounted) showToast(context, 'تعذّر التصدير: $e', error: true);
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final sem = Sem.of(context);
    if (!app.loadedOnce) return const Center(child: CircularProgressIndicator());
    final list = app.scoped;
    final n = list.length;

    // إنجاز المراحل
    final nStages = stageNames.length;
    final stageReq = List<int>.filled(nStages, 0), stageDone = List<int>.filled(nStages, 0), stageWip = List<int>.filled(nStages, 0);
    // إنجاز النماذج
    final fDone = <String, int>{}, fWip = <String, int>{}, fTodo = <String, int>{}, fNa = <String, int>{};
    // التوزيع
    final buckets = List<int>.filled(6, 0);
    for (final p in list) {
      final pr = app.progressOf(p);
      for (var i = 0; i < app.formDefs.length; i++) {
        final d = app.formDefs[i];
        final s = pr.cells[i];
        switch (s) {
          case FormStatus.done:
            fDone[d.key] = (fDone[d.key] ?? 0) + 1;
            stageDone[d.stage]++;
            stageReq[d.stage]++;
          case FormStatus.wip:
            fWip[d.key] = (fWip[d.key] ?? 0) + 1;
            stageWip[d.stage]++;
            stageReq[d.stage]++;
          case FormStatus.todo:
            fTodo[d.key] = (fTodo[d.key] ?? 0) + 1;
            stageReq[d.stage]++;
          case FormStatus.na:
            fNa[d.key] = (fNa[d.key] ?? 0) + 1;
        }
      }
      final v = pr.pct;
      buckets[v <= 0 ? 0 : v >= 1 ? 5 : v <= .25 ? 1 : v <= .5 ? 2 : v <= .75 ? 3 : 4]++;
    }
    final maxB = buckets.fold<int>(1, (a, b) => b > a ? b : a);
    const bucketLabels = ['0%', '1–25%', '26–50%', '51–75%', '76–99%', '100%'];

    List<(String, int, int, int, double)> group(String Function(Project) key) {
      final m = <String, List<Project>>{};
      for (final p in list) {
        final k = key(p).trim().isEmpty ? '(غير محدد)' : key(p).trim();
        (m[k] ??= []).add(p);
      }
      final rows = m.entries.map((e) {
        final ps = e.value.map(app.progressOf).toList();
        final complete = ps.where((x) => x.cycle == CycleState.complete).length;
        final running = ps.where((x) => x.cycle == CycleState.running).length;
        final avg = ps.fold<double>(0, (a, x) => a + x.pct) / ps.length;
        return (e.key, ps.length, complete, running, avg);
      }).toList()
        ..sort((a, b) => b.$2.compareTo(a.$2));
      return rows;
    }

    Widget table(String title, List<(String, int, int, int, double)> rows) => SectionCard(
          title: title,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columnSpacing: 18,
              headingRowHeight: 38,
              dataRowMinHeight: 40,
              dataRowMaxHeight: 56,
              columns: const [
                DataColumn(label: Text('الاسم')),
                DataColumn(label: Text('المشاريع'), numeric: true),
                DataColumn(label: Text('مكتملة'), numeric: true),
                DataColumn(label: Text('جارية'), numeric: true),
                DataColumn(label: Text('متوسط الإنجاز'), numeric: true),
              ],
              rows: [
                for (final r in rows)
                  DataRow(cells: [
                    DataCell(ConstrainedBox(constraints: const BoxConstraints(maxWidth: 280), child: Text(r.$1))),
                    DataCell(Text('${r.$2}')),
                    DataCell(Text('${r.$3}')),
                    DataCell(Text('${r.$4}')),
                    DataCell(Text(pctText(r.$5, digits: 1))),
                  ]),
              ],
            ),
          ),
        );

    return PageBody(
      onRefresh: app.loadAll,
      children: [
          ScopeFilters(app: app),
          const SizedBox(height: 14),
          SectionCard(
            title: 'إنجاز المراحل',
            trailing: Text('نسبة من النماذج المطلوبة', style: TextStyle(color: sem.muted, fontSize: 12)),
            child: Column(
              children: [
                for (var s = 0; s < nStages; s++)
                  BarRow(
                    title: '${s + 1}. ${stageNames[s]}',
                    trailing: stageReq[s] == 0 ? '—' : pctText(stageDone[s] / stageReq[s]),
                    subtitle: '${FormStatus.done.label} ${stageDone[s]} · ${FormStatus.wip.label} ${stageWip[s]} · ${FormStatus.todo.label} ${stageReq[s] - stageDone[s] - stageWip[s]} — من ${stageReq[s]}',
                    meter: SegmentMeter(parts: [
                      (stageDone[s], sem.ok),
                      (stageWip[s], sem.wip),
                      (stageReq[s] - stageDone[s] - stageWip[s], sem.statusColor(FormStatus.todo)),
                    ]),
                    onTap: () => app.openProjects(stage: s),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          SectionCard(
            title: 'إنجاز النماذج',
            trailing: Text('اضغط لعرض المشاريع غير المكتملة', style: TextStyle(color: sem.muted, fontSize: 11.5)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Legend(items: [for (final s in FormStatus.values) (sem.statusColor(s), s.label)]),
                const SizedBox(height: 6),
                for (final d in app.formDefs)
                  BarRow(
                    title: d.name,
                    trailing: (n - (fNa[d.key] ?? 0)) == 0 ? '—' : pctText((fDone[d.key] ?? 0) / (n - (fNa[d.key] ?? 0))),
                    meter: SegmentMeter(parts: [
                      (fDone[d.key] ?? 0, sem.ok),
                      (fWip[d.key] ?? 0, sem.wip),
                      (fTodo[d.key] ?? 0, sem.statusColor(FormStatus.todo)),
                      (fNa[d.key] ?? 0, sem.na),
                    ], height: 8),
                    onTap: () => app.openProjects(form: d.key),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          SectionCard(
            title: 'توزيع المشاريع حسب نسبة الإنجاز',
            child: SizedBox(
              height: 170,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (var i = 0; i < 6; i++)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 5),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Text('${buckets[i]}', style: const TextStyle(fontWeight: FontWeight.w700, fontFeatures: [FontFeature.tabularFigures()])),
                            const SizedBox(height: 4),
                            Container(
                              height: 110 * buckets[i] / maxB + 2,
                              decoration: BoxDecoration(
                                color: buckets[i] == 0 ? sem.rule : Theme.of(context).colorScheme.primary,
                                borderRadius: const BorderRadius.vertical(top: Radius.circular(6), bottom: Radius.circular(2)),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(bucketLabels[i], style: TextStyle(fontSize: 11, color: sem.muted), maxLines: 1),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          table('حسب مالك المشروع', group((p) => p.owner)),
          const SizedBox(height: 14),
          table('حسب الشركة المنفذة', group((p) => p.company)),
          const SizedBox(height: 14),
          if (app.canAudit || app.settings.feature('export'))
          FilledButton.icon(
            onPressed: _exporting || list.isEmpty ? null : () => _export(app),
            icon: _exporting
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.download_outlined),
            label: Text('تصدير ${list.length} مشروعاً إلى Excel'),
            style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
          ),
          const SizedBox(height: 24),
      ],
    );
  }
}
