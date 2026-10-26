import 'package:flutter/material.dart';

import '../app_state.dart';
import '../models.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';
import 'project_detail.dart';

/// UC-02: لوحة المؤشرات.
class DashboardPage extends StatelessWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final sem = Sem.of(context);
    if (!app.loadedOnce) return const Center(child: CircularProgressIndicator());

    final list = app.scoped;
    final n = list.length;
    var running = 0, complete = 0, notStarted = 0, done = 0, wip = 0, todo = 0, req = 0;
    var sumPct = 0.0;
    final byStage = List<int>.filled(6, 0);
    final byNext = <String, int>{};
    for (final p in list) {
      final pr = app.progressOf(p);
      switch (pr.cycle) {
        case CycleState.running:
          running++;
        case CycleState.complete:
          complete++;
        case CycleState.notStarted:
          notStarted++;
      }
      done += pr.done;
      wip += pr.wip;
      todo += pr.todo;
      req += pr.required;
      sumPct += pr.pct;
      byStage[pr.stage]++;
      final nx = pr.next;
      if (nx != null) byNext[nx.key] = (byNext[nx.key] ?? 0) + 1;
    }
    final avg = n == 0 ? 0.0 : sumPct / n;
    String share(int v) => n == 0 ? '—' : '${pctText(v / n)} من المشاريع';
    final nexts = byNext.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final attention = list.where((p) => app.progressOf(p).cycle != CycleState.complete).toList()
      ..sort((a, b) => app.progressOf(a).pct.compareTo(app.progressOf(b).pct));
    final maxStage = byStage.fold<int>(1, (a, b) => b > a ? b : a);
    final pending = app.pendingRequests;

    return RefreshIndicator(
      onRefresh: app.loadAll,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ScopeFilters(app: app),
          const SizedBox(height: 14),
          if (app.projects.isEmpty)
            EmptyState(
              title: 'لا توجد مشاريع بعد',
              message: app.canManageProjects ? 'أضف أول مشروع من تبويب «المشاريع».' : 'لم تُسجَّل مشاريع حتى الآن.',
            )
          else ...[
            LayoutBuilder(builder: (context, c) {
              final cols = c.maxWidth >= 640 ? 4 : 2;
              final w = (c.maxWidth - (cols - 1) * 10) / cols;
              return Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  SizedBox(width: w, child: KpiTile(label: 'إجمالي المشاريع', value: '$n', sub: 'ضمن التصفية', onTap: () => app.openProjects())),
                  SizedBox(
                      width: w,
                      child: KpiTile(
                          label: 'دورات جارية', value: '$running', sub: share(running), color: sem.wip, onTap: () => app.openProjects(cycle: CycleState.running))),
                  SizedBox(
                      width: w,
                      child: KpiTile(
                          label: 'دورات مكتملة', value: '$complete', sub: share(complete), color: sem.ok, onTap: () => app.openProjects(cycle: CycleState.complete))),
                  SizedBox(
                      width: w,
                      child: KpiTile(label: 'لم تبدأ', value: '$notStarted', sub: share(notStarted), onTap: () => app.openProjects(cycle: CycleState.notStarted))),
                ],
              );
            }),
            const SizedBox(height: 14),
            if (app.isDirector && pending.isNotEmpty) ...[
              Material(
                color: sem.wipSoft,
                borderRadius: BorderRadius.circular(14),
                child: ListTile(
                  leading: Icon(Icons.fact_check, color: sem.wip),
                  title: Text('${pending.length} طلب اعتماد بانتظار قرارك', style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: const Text('نماذج حساسة لن تتغير حتى تعتمدها أو ترفضها'),
                  trailing: const Icon(Icons.chevron_left),
                  onTap: () => app.setTab(2),
                ),
              ),
              const SizedBox(height: 14),
            ],
            SectionCard(
              title: 'الإنجاز المستندي',
              trailing: Text('متوسط المشاريع', style: TextStyle(color: sem.muted, fontSize: 12)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(pctText(avg, digits: 1),
                      style: Theme.of(context).textTheme.displaySmall?.copyWith(
                          fontWeight: FontWeight.w700, fontFeatures: const [FontFeature.tabularFigures()])),
                  const SizedBox(height: 10),
                  SegmentMeter(parts: [(done, sem.ok), (wip, sem.wip), (todo, sem.todo)]),
                  const SizedBox(height: 8),
                  Legend(items: [
                    (sem.ok, 'مكتمل $done'),
                    (sem.wip, 'قيد الإجراء $wip'),
                    (sem.todo, 'لم يتم $todo'),
                  ]),
                  const SizedBox(height: 4),
                  Text('من أصل $req نموذجاً مطلوباً', style: TextStyle(color: sem.muted, fontSize: 12)),
                ],
              ),
            ),
            const SizedBox(height: 14),
            SectionCard(
              title: 'أين تتوقف المشاريع؟',
              trailing: Text('المستند التالي المطلوب', style: TextStyle(color: sem.muted, fontSize: 12)),
              child: nexts.isEmpty
                  ? Text('كل المشاريع ضمن التصفية أكملت دورتها.', style: TextStyle(color: sem.muted))
                  : Column(
                      children: [
                        for (final e in nexts)
                          BarRow(
                            title: app.formDef(e.key)?.name ?? e.key,
                            trailing: '${e.value} ${e.value == 1 ? 'مشروع' : 'مشاريع'}',
                            subtitle: 'مرحلة ${stageName(app.formDef(e.key)?.stage ?? 0)}',
                            meter: SegmentMeter(parts: [(e.value, sem.wip), (n - e.value, sem.todoSoft)], height: 8),
                            onTap: () => app.openProjects(form: e.key, nextOnly: true),
                          ),
                      ],
                    ),
            ),
            const SizedBox(height: 14),
            SectionCard(
              title: 'المشاريع حسب المرحلة الحالية',
              child: Column(
                children: [
                  for (var i = 0; i < 6; i++)
                    BarRow(
                      title: i < 5 ? '${i + 1}. ${stageNames[i]}' : stageDoneName,
                      trailing: '${byStage[i]}',
                      meter: SegmentMeter(
                          parts: [(byStage[i], i == 5 ? sem.ok : Theme.of(context).colorScheme.primary), (maxStage - byStage[i], sem.todoSoft)],
                          height: 8),
                      onTap: () => app.openProjects(stage: i),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            SectionCard(
              title: 'تحتاج متابعة',
              trailing: Text('الأقل إنجازاً', style: TextStyle(color: sem.muted, fontSize: 12)),
              padding: const EdgeInsets.fromLTRB(8, 16, 8, 8),
              child: attention.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(8),
                      child: Text('لا توجد مشاريع غير مكتملة.', style: TextStyle(color: sem.muted)),
                    )
                  : Column(
                      children: [
                        for (final p in attention.take(5))
                          ListTile(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                            leading: NoTag(p.assignNo),
                            title: Text(p.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                            subtitle: Text(
                              'التالي: ${app.progressOf(p).next?.name ?? '—'}' + (p.company.isNotEmpty ? ' · ' + p.company : ''),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: Text(pctText(app.progressOf(p).pct),
                                style: const TextStyle(fontWeight: FontWeight.w700, fontFeatures: [FontFeature.tabularFigures()])),
                            onTap: () => Navigator.of(context)
                                .push(MaterialPageRoute<void>(builder: (_) => ProjectDetailPage(projectId: p.id))),
                          ),
                      ],
                    ),
            ),
          ],
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

/// تصفية حسب مالك المشروع والشركة المنفذة (مشتركة بين الرئيسية والتحليل).
class ScopeFilters extends StatelessWidget {
  const ScopeFilters({super.key, required this.app});

  final AppState app;

  @override
  Widget build(BuildContext context) {
    final owner = SelectField(
      label: 'مالك المشروع',
      value: app.ownerFilter,
      items: [('', '(الكل)'), for (final o in app.owners) (o, o)],
      onChanged: (v) => app.setScope(owner: v),
    );
    final company = SelectField(
      label: 'الشركة المنفذة',
      value: app.companyFilter,
      items: [('', '(الكل)'), for (final c in app.companies) (c, c)],
      onChanged: (v) => app.setScope(company: v),
    );
    return LayoutBuilder(builder: (context, c) {
      if (c.maxWidth < 520) {
        return Column(children: [owner, const SizedBox(height: 10), company]);
      }
      return Row(children: [Expanded(child: owner), const SizedBox(width: 10), Expanded(child: company)]);
    });
  }
}
