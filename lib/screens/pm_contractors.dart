import 'package:flutter/material.dart';

import '../app_state.dart';
import '../models.dart';
import '../pm.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';
import 'pm_common.dart';

// =====================================================================
// تقييم الشركات المنفذة: التقييم الميداني الدوري (6 معايير) ومؤشرات الأداء والدرجة المركّبة
// =====================================================================

Future<void> showEvaluationEditor(BuildContext context, {PmEvaluation? e, String? projectId}) async {
  final app = AppScope.of(context);
  final cfg = app.pmConfig;
  final scale = [for (final k in evalScaleLabels.keys) ('$k', evalScaleLabels[k]!)];
  final pid = e?.projectId ?? projectId;
  final project = pid == null ? null : app.project(pid);
  final companies = project == null ? <String>[] : app.companiesOf(project);
  final ok = await showPmForm(
    context,
    title: e == null ? 'تقييم ميداني جديد' : 'تعديل تقييم ${pmDay(e.evaluatedOn)}',
    note: 'تقييم ربع سنوي لكل مشروع جارٍ (أو شهري للمشاريع المتعثرة) من القسم المشرف. المقياس: 5 ممتاز، 4 جيد جداً، 3 جيد، 2 مقبول، 1 ضعيف.',
    sections: [
      PmSection('التقييم', [
        PmField('project_id', 'العقد', PmKind.select, options: pmProjectOptions(app), required: true, full: true),
        PmField('company', 'الشركة المنفذة', PmKind.select, options: pmPlain(companies),
            helper: companies.isEmpty ? 'فارغ = شركة العقد' : null),
        const PmField('evaluated_on', 'تاريخ التقييم', PmKind.date, required: true),
        PmField('evaluator', 'المُقيِّم (القسم)', PmKind.select, options: pmPlain(cfg.departments)),
      ]),
      PmSection('معايير التقييم (1–5)', [
        for (final c in evalCriteria) PmField(c.$1, c.$2, PmKind.score, options: scale),
      ]),
      const PmSection('', [PmField('notes', 'ملاحظات وأدلة التقييم', PmKind.multiline, max: 1000)]),
    ],
    values: e?.toJson() ?? {'project_id': projectId ?? '', 'evaluated_on': pmToday()},
    preview: (v) {
      final s = [for (final c in evalCriteria) v[c.$1]].whereType<int>().toList();
      if (s.isEmpty) return null;
      final avg = s.reduce((a, b) => a + b) / s.length;
      return InfoBanner(text: 'المتوسط ${avg.toStringAsFixed(2)} من 5 (${s.length} معايير)', level: avg >= 3 ? 'ok' : 'warning');
    },
    onSave: (d) => app.savePmRecord('evaluation', e?.id, d),
  );
  if (ok && context.mounted) showToast(context, e == null ? 'سُجّل التقييم' : 'حُفظ التقييم');
}

Color gradeColor(BuildContext context, PmConfig cfg, PmGrade? g) {
  final sem = Sem.of(context);
  if (g == null) return sem.muted;
  final i = cfg.grades.indexWhere((x) => x.name == g.name);
  if (i <= 0) return sem.danger;
  if (i == 1) return sem.wip;
  if (i >= cfg.grades.length - 1) return const Color(0xFF2E7D9A);
  return sem.ok;
}

class PmContractorsPage extends StatefulWidget {
  const PmContractorsPage({super.key});

  @override
  State<PmContractorsPage> createState() => _PmContractorsPageState();
}

class _PmContractorsPageState extends State<PmContractorsPage> {
  String _view = 'kpi';

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    if (!app.v7Ready) return const PmNotReady(title: 'تقييم الشركات');
    final sem = Sem.of(context);
    final pm = app.pm;
    final cfg = app.pmConfig;
    final toggle = Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: SegmentedButton<String>(
        segments: const [
          ButtonSegment(value: 'kpi', label: Text('مؤشرات الأداء'), icon: Icon(Icons.leaderboard_outlined)),
          ButtonSegment(value: 'evals', label: Text('التقييم الميداني'), icon: Icon(Icons.fact_check_outlined)),
        ],
        selected: {_view},
        onSelectionChanged: (s) => setState(() => _view = s.first),
      ),
    );
    final add = [
      if (app.canEditPm)
        FilledButton.icon(onPressed: () => showEvaluationEditor(context), icon: const Icon(Icons.add_rounded), label: const Text('تقييم ميداني')),
    ];
    if (_view == 'evals') {
      final list = [...app.pmEvaluations]..sort((a, b) => b.evaluatedOn.compareTo(a.evaluatedOn));
      return PmListScaffold(
        title: 'التقييم الميداني الدوري للشركات',
        subtitle: '${list.length} تقييماً · متوسط ${pm.avgField?.toStringAsFixed(2) ?? '—'} من 5',
        icon: Icons.fact_check_rounded,
        actions: add,
        top: [toggle],
        emptyTitle: 'لا تقييمات بعد',
        emptyMessage: 'قيّم كل مشروع جارٍ ربع سنوياً، وشهرياً للمتعثر.',
        items: [
          for (final e in list)
            PmTile(
              code: pmDay(e.evaluatedOn),
              meta: [pmProjectName(app, e.projectId), e.evaluator].where((x) => x.isNotEmpty).join(' · '),
              title: e.company.isEmpty ? (app.project(e.projectId)?.company ?? '') : e.company,
              leading: Container(
                width: 50,
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(color: sem.surface2, borderRadius: BorderRadius.circular(12)),
                child: Column(children: [
                  Text(e.average?.toStringAsFixed(1) ?? '—', style: const TextStyle(fontWeight: FontWeight.w900)),
                  Text('من 5', style: TextStyle(fontSize: 10.5, color: sem.muted)),
                ]),
              ),
              badges: [
                for (final c in evalCriteria)
                  if (e.scores[c.$1] != null)
                    ToneBadge('${c.$2}: ${e.scores[c.$1]}', color: (e.scores[c.$1] ?? 0) <= 2 ? sem.danger : sem.muted),
              ],
              onTap: () => showPmSheet(
                context,
                code: pmDay(e.evaluatedOn),
                title: e.company.isEmpty ? (app.project(e.projectId)?.company ?? '') : e.company,
                rows: [
                  ('العقد', pmProjectName(app, e.projectId)),
                  for (final c in evalCriteria)
                    (c.$2, e.scores[c.$1] == null ? '' : '${e.scores[c.$1]} — ${evalScaleLabels[e.scores[c.$1]]}'),
                  ('المتوسط', e.average?.toStringAsFixed(2) ?? ''),
                  ('المُقيِّم', e.evaluator),
                  ('ملاحظات وأدلة التقييم', e.notes),
                ],
                actions: (sheet) => [
                  if (app.canEditPm)
                    FilledButton.tonalIcon(
                      onPressed: () {
                        Navigator.of(sheet).pop();
                        showEvaluationEditor(context, e: e);
                      },
                      icon: const Icon(Icons.edit_outlined),
                      label: const Text('تعديل'),
                    ),
                  if (app.isDirector) pmDeleteButton(context, sheet, what: 'التقييم', onDelete: () => app.deletePmRecord('evaluation', e.id)),
                ],
              ),
            ),
        ],
      );
    }

    final ks = pm.contractors;
    return PageBody(
      maxWidth: 1250,
      onRefresh: app.loadAll,
      children: [
        PageHeader(
          title: 'مؤشرات أداء الشركات المنفذة',
          subtitle: 'تُحسب تلقائياً من سجل المشاريع والتأخيرات والمشاكل والتغييرات والتقييم الميداني.',
          icon: Icons.leaderboard_rounded,
          actions: add,
        ),
        toggle,
        if (ks.isEmpty)
          const EmptyState(title: 'لا شركات بعد', message: 'تظهر الشركات من حقل «الشركة» في بيانات العقود.', icon: Icons.business_outlined)
        else ...[
          ResponsiveGrid(minItemWidth: 340, spacing: 12, children: [
            for (final k in ks) _KpiCard(k: k, cfg: cfg),
          ]),
          const SizedBox(height: 16),
          SectionCard(
            title: 'جدول المؤشرات',
            icon: Icons.table_chart_outlined,
            child: PmTable(
              columns: const [
                'الشركة', 'المشاريع', 'الجارية', 'قيمة العقود', 'متوسط الإنجاز', 'متوسط SPI', 'أيام التأخير المنسوبة', 'نسبة التأخير', //
                'المشاكل المسندة', 'المفتوحة', 'متوسط عمر المشاكل', 'السلامة', 'الجودة', 'تغييرات منها', 'المرفوضة', 'التقييم الميداني', //
                'الدرجة', 'التقدير', 'الترتيب', 'اكتمال البيانات',
              ],
              rows: [
                for (final k in ks)
                  [
                    k.name,
                    '${k.projects}',
                    '${k.running}',
                    k.totalValue == 0 ? '—' : fmtMoney(k.totalValue),
                    pctOrDash(k.avgActual),
                    spiText(k.avgSpi),
                    '${k.contractorDelayDays}',
                    pctOrDash(k.delayRatio, digits: 1),
                    '${k.issuesAssigned}',
                    '${k.openIssues}',
                    k.avgIssueAge?.toStringAsFixed(0) ?? '—',
                    '${k.safetyIssues}',
                    '${k.qualityIssues}',
                    '${k.changesFromContractor}',
                    '${k.rejectedChanges}',
                    k.avgField == null ? '—' : '${k.avgField!.toStringAsFixed(2)} (${k.evaluations})',
                    k.composite?.toStringAsFixed(0) ?? '—',
                    k.grade?.name ?? '—',
                    k.rank == 0 ? '—' : '${k.rank}',
                    '${k.completeness} من 4',
                  ],
              ],
            ),
          ),
        ],
        const SizedBox(height: 16),
        SectionCard(
          title: 'منهجية حساب الدرجات',
          icon: Icons.functions_rounded,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            for (final line in [
              'درجة الالتزام الزمني = 100 × (متوسط SPI − ${cfg.spiZero}) ÷ (1 − ${cfg.spiZero})، بحد أقصى 100 عند SPI ≥ 1.',
              'درجة التأخير المنسوب = 100 × (1 − نسبة أيام التأخير المنسوبة للشركة من مددها التعاقدية ÷ ${cfg.delayZero}).',
              'درجة التقييم الميداني = (متوسط التقييم من 1 إلى 5 − 1) ÷ 4 × 100.',
              'درجة سرعة الحل = 100 × ${cfg.issueDays} يوماً ÷ متوسط عمر المشاكل المسندة للشركة، بحد أقصى 100.',
              'الدرجة المركّبة = المتوسط الموزون للدرجات المتاحة بأوزان: الالتزام ${pctText(cfg.weight('schedule'))}، التأخير ${pctText(cfg.weight('delay'))}، '
                  'الميداني ${pctText(cfg.weight('field'))}، سرعة الحل ${pctText(cfg.weight('response'))}؛ وعند غياب مكوّن يُعاد توزيع وزنه.',
              'تكتمل موثوقية التقييم بتوفر المكونات الأربعة لعدة مشاريع وفترات؛ تعامل بحذر مع الشركة ذات المشروع الواحد.',
            ])
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text('• $line', style: TextStyle(height: 1.5, color: sem.muted)),
              ),
            const SizedBox(height: 6),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final g in cfg.grades) ToneBadge('${g.min.toStringAsFixed(0)}+ ${g.name}: ${g.rec}', color: gradeColor(context, cfg, g)),
            ]),
          ]),
        ),
      ],
    );
  }
}

class _KpiCard extends StatelessWidget {
  const _KpiCard({required this.k, required this.cfg});

  final ContractorKpi k;
  final PmConfig cfg;

  @override
  Widget build(BuildContext context) {
    final sem = Sem.of(context);
    final color = gradeColor(context, cfg, k.grade);
    Widget meter(String label, double? v) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(children: [
            SizedBox(width: 108, child: Text(label, style: TextStyle(fontSize: 12, color: sem.muted))),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: v == null ? 0 : (v / 100).clamp(0, 1).toDouble(),
                  minHeight: 7,
                  backgroundColor: sem.surface2,
                  color: v == null ? sem.muted : color,
                ),
              ),
            ),
            SizedBox(
              width: 34,
              child: Text(v == null ? '—' : v.toStringAsFixed(0),
                  textAlign: TextAlign.end, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5)),
            ),
          ]),
        );
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: cardDecoration(context),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Container(
            width: 52,
            height: 52,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: color.withValues(alpha: 0.14), shape: BoxShape.circle),
            child: Text(k.composite?.toStringAsFixed(0) ?? '—', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17, color: color)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(k.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800)),
              Text(
                  [
                    if (k.rank > 0) 'الترتيب ${k.rank}',
                    '${k.projects} مشروع',
                    if (k.grade != null) k.grade!.name,
                  ].join(' · '),
                  style: TextStyle(color: color, fontSize: 12.5, fontWeight: FontWeight.w700)),
            ]),
          ),
        ]),
        const SizedBox(height: 10),
        meter('الالتزام الزمني', k.scheduleScore),
        meter('التأخير المنسوب', k.delayScore),
        meter('التقييم الميداني', k.fieldScore),
        meter('سرعة حل المشاكل', k.responseScore),
        if (k.grade != null) ...[
          const SizedBox(height: 8),
          Text('التوصية: ${k.grade!.rec}', style: TextStyle(color: sem.muted, fontSize: 12.5)),
        ],
        if (k.completeness < 4)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text('اكتمال البيانات ${k.completeness} من 4', style: TextStyle(color: sem.wip, fontSize: 12)),
          ),
      ]),
    );
  }
}
