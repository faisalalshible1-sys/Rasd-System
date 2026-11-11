import 'package:flutter/material.dart';

import '../app_state.dart';
import '../models.dart';
import '../pm.dart';
import '../ui/charts.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';
import 'pm_common.dart';

// =====================================================================
// سجلات المشاكل، والتأخيرات وتحليل أسبابها، والتغييرات، والدروس المستفادة
// =====================================================================

String _riskLabel(AppState app, String? id) {
  if (id == null || id.isEmpty) return '';
  final r = app.riskById(id);
  return r == null ? '' : '${r.code} · ${r.description}';
}

List<(String, String)> _riskOptions(AppState app) => [
      for (final r in [...app.risks]..sort((a, b) => a.code.compareTo(b.code))) (r.id, '${r.code} · ${r.description}'),
    ];

// =====================================================================
// سجل المشاكل
// =====================================================================
Future<void> showIssueEditor(BuildContext context, {PmIssue? issue}) async {
  final app = AppScope.of(context);
  final cfg = app.pmConfig;
  final ok = await showPmForm(
    context,
    title: issue == null ? 'مشكلة جديدة' : 'تعديل ${issue.code}',
    note: 'المشكلة حدث وقع فعلاً ويحتاج حلاً (بخلاف الخطر المحتمل). اربطها بالخطر الذي تحقق إن وُجد.',
    sections: [
      PmSection('تعريف المشكلة', [
        PmField('project_id', 'العقد', PmKind.select, options: pmProjectOptions(app), required: true, full: true),
        const PmField('description', 'وصف المشكلة', PmKind.multiline, required: true, max: 400),
        const PmField('detected_on', 'تاريخ الرصد', PmKind.date, required: true),
        PmField('category', 'التصنيف', PmKind.select, options: pmPlain(app.riskConfig.categories)),
        PmField('risk_id', 'الخطر المرتبط', PmKind.select, options: _riskOptions(app), full: true),
      ]),
      PmSection('المسؤولية والأثر', [
        PmField('priority', 'الأولوية', PmKind.select, options: pmLabels(pmPriorities, pmPriorityLabels), required: true),
        PmField('party', 'الجهة المسؤولة عن الحل', PmKind.select, options: pmLabels(pmParties, pmPartyLabels), required: true),
        PmField('department', 'القسم المتابع', PmKind.select, options: pmPlain(cfg.departments)),
        const PmField('action', 'الإجراء المتخذ / المطلوب', PmKind.multiline, max: 600),
        const PmField('time_impact_days', 'الأثر الزمني (يوم)', PmKind.integer),
        const PmField('cost_impact', 'الأثر المالي', PmKind.money),
      ]),
      PmSection('المتابعة والإغلاق', [
        const PmField('target_date', 'الموعد المستهدف للحل', PmKind.date, helper: 'المدة المستهدفة لحل المشكلة في الإعدادات'),
        PmField('status', 'الحالة', PmKind.select, options: pmLabels(issueStatuses, issueStatusLabels), required: true),
        const PmField('notes', 'ملاحظات', PmKind.multiline, max: 1000),
      ]),
    ],
    values: issue?.toJson() ??
        {
          'detected_on': pmToday(),
          'priority': 'medium',
          'party': 'contractor',
          'status': 'open',
          'target_date': addDays(pmToday(), cfg.issueDays),
        },
    onSave: (d) => app.savePmRecord('issue', issue?.id, {...d, 'code': issue?.code ?? ''}),
  );
  if (ok && context.mounted) showToast(context, issue == null ? 'سُجّلت المشكلة' : 'حُفظت ${issue.code}');
}

void showIssueDetails(BuildContext context, PmIssue i) {
  final app = AppScope.of(context);
  final sem = Sem.of(context);
  final ref = app.pmConfig.refDay;
  final f = i.followUp(ref, app.pmConfig.alertDays);
  showPmSheet(
    context,
    code: i.code,
    title: i.description,
    badges: [
      ToneBadge(issueStatusLabels[i.status] ?? i.status, color: i.isClosed ? sem.ok : sem.wip),
      ToneBadge('الأولوية ${pmPriorityLabels[i.priority]}', color: priorityColor(sem, i.priority)),
      if (f != 'closed') ToneBadge(followUpText(f), color: pmFollowColor(sem, f)),
    ],
    rows: [
      ('العقد', pmProjectName(app, i.projectId)),
      ('الشركة المنفذة', app.project(i.projectId)?.company ?? ''),
      ('تاريخ الرصد · عمر المشكلة', '${pmDay(i.detectedOn)} · ${i.age(ref)} يوم'),
      ('التصنيف', i.category),
      ('الخطر المرتبط', _riskLabel(app, i.riskId)),
      ('الجهة المسؤولة عن الحل', pmPartyLabels[i.party] ?? i.party),
      ('القسم المتابع', i.department),
      ('الإجراء المتخذ / المطلوب', i.action),
      ('الأثر الزمني', daysOrDash(i.timeImpactDays)),
      ('الأثر المالي', moneyOrDash(i.costImpact)),
      ('الموعد المستهدف للحل', pmDay(i.targetDate)),
      ('تاريخ الإغلاق', pmDay(i.closedOn)),
      ('ملاحظات', i.notes),
    ],
    actions: (sheet) => [
      if (app.canEditPm)
        FilledButton.tonalIcon(
          onPressed: () {
            Navigator.of(sheet).pop();
            showIssueEditor(context, issue: i);
          },
          icon: const Icon(Icons.edit_outlined),
          label: const Text('تعديل'),
        ),
      if (app.canEditPm && !i.isClosed)
        OutlinedButton.icon(
          onPressed: () async {
            Navigator.of(sheet).pop();
            try {
              await app.savePmRecord('issue', i.id, {...i.toJson(), 'status': 'closed', 'closed_on': ''});
              if (context.mounted) showToast(context, 'أُغلقت ${i.code}');
            } catch (e) {
              if (context.mounted) showToast(context, friendlyError(e), error: true);
            }
          },
          icon: const Icon(Icons.task_alt_rounded),
          label: const Text('إغلاق المشكلة'),
        ),
      if (app.isDirector) pmDeleteButton(context, sheet, what: i.code, onDelete: () => app.deletePmRecord('issue', i.id)),
    ],
  );
}

String followUpText(String f) => switch (f) {
      'overdue' => 'متأخرة',
      'soon' => 'مستحقة قريباً',
      'ontime' => 'ضمن الموعد',
      'none' => 'بلا موعد',
      _ => 'مغلقة',
    };

class PmIssuesPage extends StatefulWidget {
  const PmIssuesPage({super.key});

  @override
  State<PmIssuesPage> createState() => _PmIssuesPageState();
}

class _PmIssuesPageState extends State<PmIssuesPage> {
  final _search = TextEditingController();
  String _status = 'active';
  String _priority = '';
  String _party = '';
  String _follow = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    if (!app.v7Ready) return const PmNotReady(title: 'سجل المشاكل');
    final sem = Sem.of(context);
    final cfg = app.pmConfig;
    final ref = cfg.refDay;
    final q = _search.text.trim();
    final all = app.pmIssues;
    final list = all.where((i) {
      if (_status == 'active' && i.isClosed) return false;
      if (_status != 'active' && _status != 'all' && i.status != _status) return false;
      if (_priority.isNotEmpty && i.priority != _priority) return false;
      if (_party.isNotEmpty && i.party != _party) return false;
      if (_follow.isNotEmpty && i.followUp(ref, cfg.alertDays) != _follow) return false;
      return pmMatch(q, [i.code, i.description, i.category, i.action, i.department, pmProjectName(app, i.projectId)]);
    }).toList()
      ..sort((a, b) {
        final fa = a.followUp(ref, cfg.alertDays) == 'overdue' ? 0 : 1, fb = b.followUp(ref, cfg.alertDays) == 'overdue' ? 0 : 1;
        if (fa != fb) return fa.compareTo(fb);
        final pa = pmPriorities.indexOf(a.priority), pb = pmPriorities.indexOf(b.priority);
        if (pa != pb) return pa.compareTo(pb);
        return b.code.compareTo(a.code);
      });
    final overdue = all.where((i) => i.followUp(ref, cfg.alertDays) == 'overdue').length;
    return PmListScaffold(
      title: 'سجل المشاكل والقضايا',
      subtitle: '${all.length} مشكلة · ${all.where((i) => !i.isClosed).length} مفتوحة · $overdue متأخرة عن موعد الحل',
      icon: Icons.report_problem_rounded,
      actions: [
        if (app.canEditPm)
          FilledButton.icon(onPressed: () => showIssueEditor(context), icon: const Icon(Icons.add_rounded), label: const Text('مشكلة جديدة')),
      ],
      search: _search,
      searchHint: 'بحث بالرمز أو الوصف أو العقد',
      onSearch: () => setState(() {}),
      filters: [
        pmFilter('الحالة', _status, [('active', 'غير المغلقة'), ('all', 'الكل'), ...pmLabels(issueStatuses, issueStatusLabels)],
            (v) => setState(() => _status = v)),
        pmFilter('الأولوية', _priority, [('', 'الكل'), ...pmLabels(pmPriorities, pmPriorityLabels)], (v) => setState(() => _priority = v)),
        pmFilter('الجهة المسؤولة', _party, [('', 'الكل'), ...pmLabels(pmParties, pmPartyLabels)], (v) => setState(() => _party = v)),
        pmFilter('المتابعة', _follow, const [('', 'الكل'), ('overdue', 'متأخرة'), ('soon', 'مستحقة قريباً'), ('ontime', 'ضمن الموعد'), ('none', 'بلا موعد')],
            (v) => setState(() => _follow = v)),
      ],
      emptyTitle: all.isEmpty ? 'لا مشاكل مسجلة' : 'لا نتائج مطابقة',
      emptyMessage: all.isEmpty ? 'سجّل المشكلة فور رصدها، وراجع المفتوحة أسبوعياً.' : null,
      items: [
        for (final i in list)
          PmTile(
            code: i.code,
            meta: [pmProjectName(app, i.projectId), i.category].where((x) => x.isNotEmpty).join(' · '),
            title: i.description,
            badges: [
              ToneBadge(issueStatusLabels[i.status] ?? i.status, color: i.isClosed ? sem.ok : sem.wip),
              ToneBadge(pmPriorityLabels[i.priority] ?? i.priority, color: priorityColor(sem, i.priority)),
              ToneBadge(pmPartyLabels[i.party] ?? i.party, color: sem.muted),
              if (!i.isClosed) ...[
                if (i.followUp(ref, cfg.alertDays) == 'overdue')
                  ToneBadge('متأخرة ${i.overdueDays(ref)} يوم', color: sem.danger, icon: Icons.event_busy_outlined)
                else if (i.targetDate != null)
                  ToneBadge('الموعد ${pmDay(i.targetDate)}', color: pmFollowColor(sem, i.followUp(ref, cfg.alertDays))),
                Text('عمرها ${i.age(ref)} يوم', style: TextStyle(color: sem.muted, fontSize: 12)),
              ],
            ],
            onTap: () => showIssueDetails(context, i),
          ),
      ],
    );
  }
}

// =====================================================================
// سجل التأخيرات وتحليل أسبابها
// =====================================================================
Future<void> showDelayEditor(BuildContext context, {PmDelay? delay}) async {
  final app = AppScope.of(context);
  final cfg = app.pmConfig;
  final ok = await showPmForm(
    context,
    title: delay == null ? 'حدث تأخير جديد' : 'تعديل ${delay.code}',
    note: 'اترك تاريخ النهاية فارغاً إن كان الحدث قائماً (تُحسب المدة حتى تاريخ الإسناد). التمديد الناتج عن أمر تغيير يُسجَّل في «سجل التغييرات» فقط لتجنب احتسابه مرتين.',
    sections: [
      PmSection('حدث التأخير', [
        PmField('project_id', 'العقد', PmKind.select, options: pmProjectOptions(app), required: true, full: true),
        const PmField('description', 'وصف حدث التأخير', PmKind.multiline, required: true, max: 400),
      ]),
      PmSection('تحليل السبب والمسؤولية', [
        PmField('cause', 'السبب الرئيسي', PmKind.select, options: pmPlain(cfg.delayCauses), required: true),
        const PmField('sub_cause', 'السبب الفرعي / التفاصيل', PmKind.text, max: 300),
        PmField('party', 'الجهة المسؤولة', PmKind.select, options: pmLabels(pmParties, pmPartyLabels), required: true),
        PmField('delay_class', 'التصنيف التعاقدي', PmKind.select, options: pmLabels(delayClasses, delayClassLabels)),
        const PmField('critical', 'على المسار الحرج', PmKind.toggle, helper: 'الحدث يؤخر تاريخ إنهاء المشروع'),
      ]),
      const PmSection('المدة والتمديد', [
        PmField('start_date', 'تاريخ بداية التأثير', PmKind.date, required: true),
        PmField('end_date', 'تاريخ نهاية التأثير', PmKind.date, helper: 'فارغ = الحدث قائم'),
        PmField('eot_requested', 'التمديد المطلوب (يوم)', PmKind.integer),
        PmField('eot_approved', 'التمديد المعتمد (يوم)', PmKind.integer, helper: 'فارغ = لم يُبت فيه بعد'),
        PmField('refs', 'المرجع المرتبط (خطر / مشكلة / تغيير)', PmKind.text, max: 120),
        PmField('notes', 'ملاحظات', PmKind.multiline, max: 1000),
      ]),
    ],
    values: delay?.toJson() ?? {'start_date': pmToday(), 'party': 'contractor', 'critical': false},
    onSave: (d) => app.savePmRecord('delay', delay?.id, {...d, 'code': delay?.code ?? ''}),
  );
  if (ok && context.mounted) showToast(context, delay == null ? 'سُجّل حدث التأخير' : 'حُفظ ${delay.code}');
}

void showDelayDetails(BuildContext context, PmDelay d) {
  final app = AppScope.of(context);
  final sem = Sem.of(context);
  final ref = app.pmConfig.refDay;
  showPmSheet(
    context,
    code: d.code,
    title: d.description,
    badges: [
      ToneBadge(d.isOngoing ? 'قائم' : 'منتهٍ', color: d.isOngoing ? sem.danger : sem.ok),
      if (d.critical) ToneBadge('على المسار الحرج', color: sem.danger),
      if (d.delayClass.isNotEmpty) ToneBadge(delayClassLabels[d.delayClass] ?? d.delayClass, color: sem.muted),
      if (d.eotPending) ToneBadge('طلب تمديد لم يُبت فيه', color: sem.wip),
    ],
    rows: [
      ('العقد', pmProjectName(app, d.projectId)),
      ('الشركة المنفذة', app.project(d.projectId)?.company ?? ''),
      ('السبب الرئيسي', d.cause),
      ('السبب الفرعي / التفاصيل', d.subCause),
      ('الجهة المسؤولة', pmPartyLabels[d.party] ?? d.party),
      ('الدلالة التعاقدية', delayClassMeaning[d.delayClass] ?? ''),
      ('فترة التأثير', '${pmDay(d.startDate)} ← ${d.endDate == null ? 'قائم' : pmDay(d.endDate)}'),
      ('مدة التأخير', '${d.days(ref)} يوم'),
      ('التمديد المطلوب · المعتمد', '${daysOrDash(d.eotRequested)} · ${d.eotApproved == null ? 'لم يُبت فيه' : '${d.eotApproved} يوم'}'),
      ('المرجع المرتبط', d.refs),
      ('ملاحظات', d.notes),
    ],
    actions: (sheet) => [
      if (app.canEditPm)
        FilledButton.tonalIcon(
          onPressed: () {
            Navigator.of(sheet).pop();
            showDelayEditor(context, delay: d);
          },
          icon: const Icon(Icons.edit_outlined),
          label: const Text('تعديل'),
        ),
      if (app.isDirector) pmDeleteButton(context, sheet, what: d.code, onDelete: () => app.deletePmRecord('delay', d.id)),
    ],
  );
}

class PmDelaysPage extends StatefulWidget {
  const PmDelaysPage({super.key});

  @override
  State<PmDelaysPage> createState() => _PmDelaysPageState();
}

class _PmDelaysPageState extends State<PmDelaysPage> {
  final _search = TextEditingController();
  String _view = 'list';
  String _state = '';
  String _party = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    if (!app.v7Ready) return const PmNotReady(title: 'التأخيرات وأسبابها');
    final sem = Sem.of(context);
    final ref = app.pmConfig.refDay;
    final pm = app.pm;
    final toggle = Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: SegmentedButton<String>(
        segments: const [
          ButtonSegment(value: 'list', label: Text('سجل التأخيرات'), icon: Icon(Icons.list_rounded)),
          ButtonSegment(value: 'analysis', label: Text('تحليل الأسباب'), icon: Icon(Icons.analytics_outlined)),
        ],
        selected: {_view},
        onSelectionChanged: (s) => setState(() => _view = s.first),
      ),
    );
    final add = [
      if (app.canEditPm)
        FilledButton.icon(onPressed: () => showDelayEditor(context), icon: const Icon(Icons.add_rounded), label: const Text('حدث تأخير')),
    ];
    if (_view == 'analysis') {
      return PageBody(
        maxWidth: 1200,
        onRefresh: app.loadAll,
        children: [
          PageHeader(title: 'تحليل أسباب التأخير', subtitle: 'يتحدث تلقائياً من سجل التأخيرات', icon: Icons.analytics_rounded, actions: add),
          toggle,
          DelayAnalysisView(analysis: pm.delayAnalysis),
        ],
      );
    }
    final q = _search.text.trim();
    final list = app.pmDelays.where((d) {
      if (_state == 'ongoing' && !d.isOngoing) return false;
      if (_state == 'ended' && d.isOngoing) return false;
      if (_state == 'eot' && !d.eotPending) return false;
      if (_party.isNotEmpty && d.party != _party) return false;
      return pmMatch(q, [d.code, d.description, d.cause, d.subCause, d.refs, pmProjectName(app, d.projectId)]);
    }).toList()
      ..sort((a, b) => b.startDate.compareTo(a.startDate));
    return PmListScaffold(
      title: 'سجل أحداث التأخير',
      subtitle: '${app.pmDelays.length} حدثاً · ${pm.delayDays} يوم تأخير · ${pm.ongoingDelays} قائم',
      icon: Icons.hourglass_bottom_rounded,
      actions: add,
      top: [toggle],
      search: _search,
      searchHint: 'بحث بالرمز أو الوصف أو السبب',
      onSearch: () => setState(() {}),
      filters: [
        pmFilter('الحالة', _state, const [('', 'الكل'), ('ongoing', 'قائم'), ('ended', 'منتهٍ'), ('eot', 'تمديد لم يُبت فيه')],
            (v) => setState(() => _state = v)),
        pmFilter('الجهة المسؤولة', _party, [('', 'الكل'), ...pmLabels(pmParties, pmPartyLabels)], (v) => setState(() => _party = v)),
      ],
      emptyTitle: app.pmDelays.isEmpty ? 'لا أحداث تأخير مسجلة' : 'لا نتائج مطابقة',
      emptyMessage: app.pmDelays.isEmpty ? 'سجّل كل حدث أثّر على البرنامج الزمني عند بدئه وعند انتهائه.' : null,
      items: [
        for (final d in list)
          PmTile(
            code: d.code,
            meta: [pmProjectName(app, d.projectId), d.cause].where((x) => x.isNotEmpty).join(' · '),
            title: d.description,
            leading: Container(
              width: 50,
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                  color: (d.isOngoing ? sem.danger : sem.muted).withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
              child: Column(children: [
                Text('${d.days(ref)}', style: TextStyle(fontWeight: FontWeight.w900, color: d.isOngoing ? sem.danger : null)),
                Text('يوم', style: TextStyle(fontSize: 10.5, color: sem.muted)),
              ]),
            ),
            badges: [
              ToneBadge(d.isOngoing ? 'قائم' : 'منتهٍ', color: d.isOngoing ? sem.danger : sem.ok),
              ToneBadge(pmPartyLabels[d.party] ?? d.party, color: sem.muted),
              if (d.delayClass.isNotEmpty) ToneBadge(delayClassLabels[d.delayClass]!, color: sem.muted),
              if (d.critical) ToneBadge('مسار حرج', color: sem.danger),
              if (d.eotPending) ToneBadge('تمديد ${d.eotRequested} يوم بانتظار البت', color: sem.wip),
              if ((d.eotApproved ?? 0) > 0) ToneBadge('تمديد معتمد ${d.eotApproved} يوم', color: sem.ok),
            ],
            onTap: () => showDelayDetails(context, d),
          ),
      ],
    );
  }
}

/// تحليل أسباب التأخير: باريتو، والجهات، والتصنيف التعاقدي، ومصفوفة الأسباب × الجهات، والمشاريع.
class DelayAnalysisView extends StatelessWidget {
  const DelayAnalysisView({super.key, required this.analysis});

  final DelayAnalysis analysis;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final sem = Sem.of(context);
    final a = analysis;
    final t = a.total;
    if (t.count == 0) return const EmptyState(title: 'لا توجد أحداث تأخير مسجلة', icon: Icons.hourglass_empty_rounded);
    final top3 = a.pareto.take(3).fold<double>(0, (s, g) => s + g.pct);
    final parties = [for (final k in pmParties) if (a.byParty.containsKey(k)) k];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      InfoBanner(
        text: 'إجمالي أيام التأخير المسجلة ${t.days} يوماً في ${t.count} حدثاً، منها ${t.criticalDays} يوماً على المسار الحرج، والأحداث القائمة ${t.ongoing}. '
            'السبب الأول «${a.pareto.first.key}» بنسبة ${pctText(a.pareto.first.pct)} من أيام التأخير، وأول ثلاثة أسباب ${pctText(top3)}. '
            'الأحداث المتزامنة قد تتداخل، فتُقرأ النتائج للمقارنة بين الأسباب.',
        level: 'info',
      ),
      const SizedBox(height: 14),
      SectionCard(
        title: '١. تحليل باريتو لأسباب التأخير',
        icon: Icons.bar_chart_rounded,
        subtitle: 'الصفوف المظللة: الأسباب الحيوية القليلة التي تشكل حتى 80% من أيام التأخير — ابدأ المعالجة بها.',
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          BreakdownChart(type: 'bar', items: [for (final g in a.pareto) (g.key, g.days.toDouble())], format: (v) => '${v.toInt()} يوم'),
          const SizedBox(height: 10),
          PmTable(
            columns: const ['السبب الرئيسي', 'الترتيب', 'الأحداث', 'أيام التأخير', 'على المسار الحرج', 'النسبة', 'التراكمية', 'التمديد المعتمد', 'القائمة'],
            rows: [
              for (var i = 0; i < a.pareto.length; i++)
                [
                  a.pareto[i].key,
                  '${i + 1}',
                  '${a.pareto[i].count}',
                  '${a.pareto[i].days}',
                  '${a.pareto[i].criticalDays}',
                  pctText(a.pareto[i].pct),
                  pctText(a.pareto[i].cumPct),
                  '${a.pareto[i].eotApproved}',
                  '${a.pareto[i].ongoing}',
                ],
            ],
            highlight: (i) => a.isVital(a.pareto[i]),
          ),
        ]),
      ),
      const SizedBox(height: 14),
      ResponsiveGrid(minItemWidth: 460, spacing: 14, children: [
        SectionCard(
          title: '٢. التوزيع حسب الجهة المسؤولة',
          icon: Icons.groups_2_outlined,
          subtitle: 'التصنيف الغالب استرشادي؛ التصنيف الفعلي لكل حدث وفق شروط العقد.',
          child: PmTable(
            columns: const ['الجهة', 'الأحداث', 'الأيام', 'النسبة', 'مسار حرج', 'مطلوب', 'معتمد', 'قائمة', 'التصنيف الغالب'],
            rows: [
              for (final k in parties)
                [
                  pmPartyLabels[k]!,
                  '${a.byParty[k]!.count}',
                  '${a.byParty[k]!.days}',
                  pctText(a.byParty[k]!.pct),
                  '${a.byParty[k]!.criticalDays}',
                  '${a.byParty[k]!.eotRequested}',
                  '${a.byParty[k]!.eotApproved}',
                  '${a.byParty[k]!.ongoing}',
                  delayClassLabels[a.byParty[k]!.dominantClass] ?? '—',
                ],
            ],
          ),
        ),
        SectionCard(
          title: '٣. التوزيع حسب التصنيف التعاقدي',
          icon: Icons.gavel_rounded,
          child: PmTable(
            columns: const ['التصنيف', 'الأحداث', 'الأيام', 'النسبة', 'مطلوب', 'معتمد', 'الدلالة التعاقدية'],
            rows: [
              for (final k in [...delayClasses, ''])
                if (a.byClass.containsKey(k))
                  [
                    k.isEmpty ? 'غير مصنف' : delayClassLabels[k]!,
                    '${a.byClass[k]!.count}',
                    '${a.byClass[k]!.days}',
                    pctText(a.byClass[k]!.pct),
                    '${a.byClass[k]!.eotRequested}',
                    '${a.byClass[k]!.eotApproved}',
                    delayClassMeaning[k] ?? '',
                  ],
            ],
          ),
        ),
      ]),
      const SizedBox(height: 14),
      SectionCard(
        title: '٤. مصفوفة الأسباب × الجهات المسؤولة (أيام التأخير)',
        icon: Icons.grid_on_rounded,
        child: PmTable(
          columns: ['السبب الرئيسي', for (final k in parties) pmPartyLabels[k]!, 'الإجمالي'],
          rows: [
            for (final g in a.pareto)
              [
                g.key,
                for (final k in parties) '${a.matrix[g.key]?[k] ?? 0}',
                '${g.days}',
              ],
          ],
        ),
      ),
      const SizedBox(height: 14),
      SectionCard(
        title: '٥. التأخير حسب المشروع',
        icon: Icons.folder_open_outlined,
        child: PmTable(
          columns: const ['العقد', 'الشركة', 'الأحداث', 'إجمالي الأيام', 'منسوب للمقاول', 'للمالك والاستشاري', 'جهات خارجية وظروف قاهرة', 'مسار حرج', 'مطلوب', 'معتمد', 'قائمة'],
          rows: [
            for (final e in (a.byProject.entries.toList()..sort((x, y) => y.value.days.compareTo(x.value.days))))
              [
                pmProjectName(app, e.key),
                app.project(e.key)?.company ?? '',
                '${e.value.count}',
                '${e.value.days}',
                '${a.projectParties[e.key]?['contractor'] ?? 0}',
                '${(a.projectParties[e.key]?['owner'] ?? 0) + (a.projectParties[e.key]?['consultant'] ?? 0)}',
                '${(a.projectParties[e.key]?['utilities'] ?? 0) + (a.projectParties[e.key]?['force_majeure'] ?? 0) + (a.projectParties[e.key]?['other'] ?? 0)}',
                '${e.value.criticalDays}',
                '${e.value.eotRequested}',
                '${e.value.eotApproved}',
                '${e.value.ongoing}',
              ],
          ],
        ),
      ),
      const SizedBox(height: 8),
      Text('آخر تحديث للحساب: ${pmDay(a.ref)}', style: TextStyle(color: sem.muted, fontSize: 12)),
    ]);
  }
}

// =====================================================================
// سجل التغييرات
// =====================================================================
Future<void> showChangeEditor(BuildContext context, {PmChange? change}) async {
  final app = AppScope.of(context);
  final cfg = app.pmConfig;
  final project = change == null ? null : app.project(change.projectId);
  final canDecide = change == null
      ? app.isDirector || app.role == AppRole.contracts || app.role == AppRole.officeStaff
      : app.canDecideChange(project);
  final locked = change != null && change.isDecided && !app.canDecideChange(project);
  final statuses = canDecide ? changeStatuses : changeStatuses.where((s) => s == 'submitted' || s == 'under_study').toList();
  final ok = await showPmForm(
    context,
    title: change == null ? 'طلب تغيير جديد' : 'تعديل ${change.code}',
    note: locked
        ? 'تم البت في هذا الطلب؛ تعديله لمن يختص بمالية العقد والمدير.'
        : 'الأثر المعتمد فقط يُضاف إلى قيمة العقد المعدّلة وتاريخ النهاية المعدّل. أدخل قيمة الحذف بالسالب. '
            'عند الاعتماد بأثر مالي يُنشأ أمر تغيير في مالية العقد تلقائياً (ويُحدَّث أو يُحذف معه).',
    sections: [
      PmSection('تعريف التغيير', [
        PmField('project_id', 'العقد', PmKind.select, options: pmProjectOptions(app), required: true, full: true, enabled: !locked),
        PmField('description', 'وصف التغيير', PmKind.multiline, required: true, max: 280, enabled: !locked),
        PmField('submitted_on', 'تاريخ التقديم', PmKind.date, required: true, enabled: !locked),
        PmField('change_type', 'نوع التغيير', PmKind.select, options: pmPlain(cfg.changeTypes), enabled: !locked),
        PmField('source', 'مصدر التغيير', PmKind.select, options: pmLabels(changeSources, changeSourceLabels), required: true, enabled: !locked),
        PmField('reason', 'سبب التغيير', PmKind.select, options: pmPlain(cfg.changeReasons), enabled: !locked),
      ]),
      PmSection('الأثر (التكلفة والزمن)', [
        PmField('cost_estimate', 'الأثر المالي المقدر', PmKind.signedMoney, enabled: !locked),
        PmField('time_requested', 'الأثر الزمني المطلوب (يوم)', PmKind.integer, enabled: !locked),
        PmField('cost_approved', 'الأثر المالي المعتمد', PmKind.signedMoney, enabled: canDecide && !locked),
        PmField('time_approved', 'الأثر الزمني المعتمد (يوم)', PmKind.integer, enabled: canDecide && !locked),
      ]),
      PmSection('البت والاعتماد', [
        PmField('status', 'الحالة', PmKind.select, options: pmLabels(statuses, changeStatusLabels), required: true, enabled: !locked),
        PmField('decided_on', 'تاريخ البت', PmKind.date, enabled: canDecide && !locked, helper: 'للمعتمد والمرفوض (فارغ = اليوم)'),
        PmField('approval_ref', 'مرجع الاعتماد', PmKind.text, max: 60, enabled: canDecide && !locked),
        PmField('refs', 'المرجع المرتبط (خطر / تأخير)', PmKind.text, max: 120, enabled: !locked),
        PmField('notes', 'ملاحظات', PmKind.multiline, max: 1000, enabled: !locked),
      ]),
    ],
    values: change?.toJson() ?? {'submitted_on': pmToday(), 'source': 'owner', 'status': 'submitted'},
    onSave: (d) => app.savePmRecord('change', change?.id, {...d, 'code': change?.code ?? ''}),
  );
  if (ok && context.mounted) showToast(context, change == null ? 'سُجّل طلب التغيير' : 'حُفظ ${change.code}');
}

Color changeStatusColor(Sem sem, String s) => switch (s) {
      'approved' => sem.ok,
      'rejected' => sem.danger,
      'under_study' => sem.wip,
      _ => sem.muted,
    };

void showChangeDetails(BuildContext context, PmChange c) {
  final app = AppScope.of(context);
  final sem = Sem.of(context);
  final cfg = app.pmConfig;
  final t = app.pm.track(c.projectId);
  final base = app.project(c.projectId)?.contractValue;
  final late = c.isPending && c.decisionDays(cfg.refDay) > cfg.changeDecideDays;
  showPmSheet(
    context,
    code: c.code,
    title: c.description,
    badges: [
      ToneBadge(changeStatusLabels[c.status] ?? c.status, color: changeStatusColor(sem, c.status)),
      if (late) ToneBadge('تأخر البت', color: sem.danger),
      if (c.variationId != null) ToneBadge('أمر تغيير في مالية العقد', color: sem.ok, icon: Icons.link_rounded),
      if (t != null && t.overChangeLimit && c.isApproved) ToneBadge('تجاوز حد التغييرات', color: sem.danger),
    ],
    rows: [
      ('العقد', pmProjectName(app, c.projectId)),
      ('الشركة المنفذة', app.project(c.projectId)?.company ?? ''),
      ('تاريخ التقديم', pmDay(c.submittedOn)),
      ('نوع التغيير · المصدر · السبب', [c.changeType, changeSourceLabels[c.source] ?? '', c.reason].where((x) => x.isNotEmpty).join(' · ')),
      ('الأثر المالي المقدر · المعتمد', '${moneyOrDash(c.costEstimate)} · ${moneyOrDash(c.costApproved)}'),
      ('الأثر الزمني المطلوب · المعتمد', '${daysOrDash(c.timeRequested)} · ${daysOrDash(c.timeApproved)}'),
      ('تاريخ البت · مدة البت', c.decidedOn == null ? '${c.decisionDays(cfg.refDay)} يوم حتى الآن' : '${pmDay(c.decidedOn)} · ${c.decisionDays(cfg.refDay)} يوم'),
      ('مرجع الاعتماد', c.approvalRef),
      ('نسبة الأثر المعتمد من قيمة العقد', c.costApproved == null || base == null || base == 0 ? '' : pctText(c.costApproved! / base, digits: 1)),
      ('النسبة التراكمية المعتمدة للمشروع', t?.changePct == null ? '' : pctText(t!.changePct!, digits: 1)),
      ('المرجع المرتبط', c.refs),
      ('ملاحظات', c.notes),
    ],
    actions: (sheet) => [
      if (app.canEditPm && (!c.isDecided || app.canDecideChange(app.project(c.projectId))))
        FilledButton.tonalIcon(
          onPressed: () {
            Navigator.of(sheet).pop();
            showChangeEditor(context, change: c);
          },
          icon: const Icon(Icons.edit_outlined),
          label: Text(c.isDecided ? 'تعديل' : (app.canDecideChange(app.project(c.projectId)) ? 'تعديل أو البت' : 'تعديل')),
        ),
      if (app.isDirector)
        pmDeleteButton(context, sheet,
            what: c.code,
            message: c.variationId == null ? null : 'يُحذف الطلب ويُحذف معه أمر التغيير المرتبط في مالية العقد. يبقى الأثر في سجل التدقيق.',
            onDelete: () => app.deletePmRecord('change', c.id)),
    ],
  );
}

class PmChangesPage extends StatefulWidget {
  const PmChangesPage({super.key});

  @override
  State<PmChangesPage> createState() => _PmChangesPageState();
}

class _PmChangesPageState extends State<PmChangesPage> {
  final _search = TextEditingController();
  String _status = '';
  String _source = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    if (!app.v7Ready) return const PmNotReady(title: 'سجل التغييرات');
    final sem = Sem.of(context);
    final cfg = app.pmConfig;
    final pm = app.pm;
    final q = _search.text.trim();
    final list = app.pmChanges.where((c) {
      if (_status == 'pending' && !c.isPending) return false;
      if (_status.isNotEmpty && _status != 'pending' && c.status != _status) return false;
      if (_source.isNotEmpty && c.source != _source) return false;
      return pmMatch(q, [c.code, c.description, c.changeType, c.reason, c.approvalRef, pmProjectName(app, c.projectId)]);
    }).toList()
      ..sort((a, b) => b.submittedOn.compareTo(a.submittedOn));
    final byReason = pm.changesByReason.entries.toList()..sort((a, b) => b.value.value.compareTo(a.value.value));
    return PmListScaffold(
      title: 'سجل التغييرات وأثرها',
      subtitle: '${app.pmChanges.length} طلباً · ${pm.approvedChanges} معتمداً بقيمة ${moneyOrDash(pm.approvedChangesValue)} · ${pm.pendingChanges} بانتظار البت',
      icon: Icons.change_circle_rounded,
      actions: [
        if (app.canEditPm)
          FilledButton.icon(onPressed: () => showChangeEditor(context), icon: const Icon(Icons.add_rounded), label: const Text('طلب تغيير')),
      ],
      top: [
        if (byReason.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: SectionCard(
              title: 'التغييرات حسب السبب',
              icon: Icons.pie_chart_outline_rounded,
              subtitle: 'عدد الطلبات والمعتمد منها وقيمته وأيامه. حد التنبيه لنسبة التغييرات ${pctText(cfg.changeLimit)} من قيمة العقد.',
              child: PmTable(
                columns: const ['السبب', 'الطلبات', 'المعتمدة', 'القيمة المعتمدة', 'الأيام المعتمدة', 'من الإجمالي'],
                rows: [
                  for (final e in byReason)
                    [
                      e.key,
                      '${e.value.count}',
                      '${e.value.approved}',
                      moneyOrDash(e.value.value),
                      '${e.value.days}',
                      pm.approvedChangesValue == 0 ? '—' : pctText(e.value.value / pm.approvedChangesValue),
                    ],
                ],
              ),
            ),
          ),
      ],
      search: _search,
      searchHint: 'بحث بالرمز أو الوصف أو المرجع',
      onSearch: () => setState(() {}),
      filters: [
        pmFilter('الحالة', _status, [('', 'الكل'), ('pending', 'بانتظار البت'), ...pmLabels(changeStatuses, changeStatusLabels)],
            (v) => setState(() => _status = v)),
        pmFilter('المصدر', _source, [('', 'الكل'), ...pmLabels(changeSources, changeSourceLabels)], (v) => setState(() => _source = v)),
      ],
      emptyTitle: app.pmChanges.isEmpty ? 'لا طلبات تغيير' : 'لا نتائج مطابقة',
      items: [
        for (final c in list)
          PmTile(
            code: c.code,
            meta: [pmProjectName(app, c.projectId), c.changeType].where((x) => x.isNotEmpty).join(' · '),
            title: c.description,
            badges: [
              ToneBadge(changeStatusLabels[c.status] ?? c.status, color: changeStatusColor(sem, c.status)),
              if (c.isApproved && c.costApproved != null)
                ToneBadge(moneyOrDash(c.costApproved), color: (c.costApproved ?? 0) < 0 ? sem.danger : sem.ok)
              else if (c.costEstimate != null)
                ToneBadge('مقدر ${moneyOrDash(c.costEstimate)}', color: sem.muted),
              if ((c.timeApproved ?? 0) > 0) ToneBadge('+${c.timeApproved} يوم', color: sem.wip),
              if (c.isPending && c.decisionDays(cfg.refDay) > cfg.changeDecideDays)
                ToneBadge('تأخر البت ${c.decisionDays(cfg.refDay)} يوم', color: sem.danger),
              if (c.variationId != null) ToneBadge('في المالية', color: sem.ok, icon: Icons.link_rounded),
            ],
            onTap: () => showChangeDetails(context, c),
          ),
      ],
    );
  }
}

// =====================================================================
// الدروس المستفادة
// =====================================================================
Future<void> showLessonEditor(BuildContext context, {PmLesson? lesson}) async {
  final app = AppScope.of(context);
  final cfg = app.pmConfig;
  final statuses = app.canApproveLessons ? lessonStatuses : const ['proposed'];
  final ok = await showPmForm(
    context,
    title: lesson == null ? 'درس مستفاد جديد' : 'تعديل ${lesson.code}',
    note: 'وثّق الدرس عند وقوع حدث مهم وعند إغلاق كل مرحلة. الدرس لا يكتمل إلا بتحديد آلية تعميمه والجهة المعنية بتطبيقه.',
    sections: [
      PmSection('التعريف', [
        PmField('project_id', 'العقد', PmKind.select, options: pmProjectOptions(app, general: 'عام – متعدد المشاريع'), full: true),
        const PmField('documented_on', 'تاريخ التوثيق', PmKind.date, required: true),
        PmField('phase', 'المرحلة', PmKind.select, options: pmPlain(app.riskConfig.phases)),
        PmField('domain', 'المجال', PmKind.select, options: pmPlain(app.riskConfig.categories)),
        PmField('lesson_type', 'نوع الدرس', PmKind.select, options: pmLabels(lessonTypes, lessonTypeLabels), required: true),
      ]),
      const PmSection('الدرس', [
        PmField('situation', 'الموقف (ما الذي حدث)', PmKind.multiline, required: true, max: 600),
        PmField('root_cause', 'السبب الجذري', PmKind.multiline, max: 600),
        PmField('effect', 'الأثر على المشروع', PmKind.text, max: 300),
        PmField('lesson', 'الدرس المستفاد / التوصية', PmKind.multiline, required: true, max: 800),
      ]),
      PmSection('التعميم والتطبيق', [
        PmField('apply_mechanism', 'آلية التعميم', PmKind.select, options: pmPlain(cfg.lessonApply)),
        PmField('apply_party', 'الجهة المعنية بالتطبيق', PmKind.select, options: pmPlain(cfg.departments)),
        const PmField('refs', 'المرجع المرتبط', PmKind.text, max: 120),
        PmField('status', 'حالة التطبيق', PmKind.select, options: pmLabels(statuses, lessonStatusLabels), required: true),
        PmField('applied_on', 'تاريخ الاعتماد / التطبيق', PmKind.date, enabled: app.canApproveLessons),
        PmField('prepared_by', 'أعدّه (القسم)', PmKind.select, options: pmPlain(cfg.departments)),
      ]),
    ],
    values: lesson?.toJson() ?? {'documented_on': pmToday(), 'lesson_type': 'negative', 'status': 'proposed'},
    onSave: (d) => app.savePmRecord('lesson', lesson?.id, {...d, 'code': lesson?.code ?? ''}),
  );
  if (ok && context.mounted) showToast(context, lesson == null ? 'وُثّق الدرس' : 'حُفظ ${lesson.code}');
}

class PmLessonsPage extends StatefulWidget {
  const PmLessonsPage({super.key});

  @override
  State<PmLessonsPage> createState() => _PmLessonsPageState();
}

class _PmLessonsPageState extends State<PmLessonsPage> {
  final _search = TextEditingController();
  String _status = '';
  String _type = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    if (!app.v7Ready) return const PmNotReady(title: 'الدروس المستفادة');
    final sem = Sem.of(context);
    final q = _search.text.trim();
    final list = app.pmLessons.where((l) {
      if (_status.isNotEmpty && l.status != _status) return false;
      if (_type.isNotEmpty && l.lessonType != _type) return false;
      return pmMatch(q, [l.code, l.situation, l.lesson, l.rootCause, l.domain, l.refs, pmProjectName(app, l.projectId)]);
    }).toList()
      ..sort((a, b) => b.documentedOn.compareTo(a.documentedOn));
    Color statusColor(String s) => s == 'applied' ? sem.ok : (s == 'approved' ? const Color(0xFF2E7D9A) : sem.wip);
    return PmListScaffold(
      title: 'سجل الدروس المستفادة',
      subtitle: '${app.pmLessons.length} درساً · ${app.pm.proposedLessons} بانتظار الاعتماد · ${app.pm.appliedLessons} مُطبَّق',
      icon: Icons.school_rounded,
      actions: [
        if (app.canEditPm)
          FilledButton.icon(onPressed: () => showLessonEditor(context), icon: const Icon(Icons.add_rounded), label: const Text('درس جديد')),
      ],
      search: _search,
      searchHint: 'بحث في الموقف أو الدرس أو المرجع',
      onSearch: () => setState(() {}),
      filters: [
        pmFilter('حالة التطبيق', _status, [('', 'الكل'), ...pmLabels(lessonStatuses, lessonStatusLabels)], (v) => setState(() => _status = v)),
        pmFilter('النوع', _type, [('', 'الكل'), ...pmLabels(lessonTypes, lessonTypeLabels)], (v) => setState(() => _type = v), width: 240),
      ],
      emptyTitle: app.pmLessons.isEmpty ? 'لا دروس موثقة بعد' : 'لا نتائج مطابقة',
      items: [
        for (final l in list)
          PmTile(
            code: l.code,
            meta: [pmProjectName(app, l.projectId), l.phase, l.domain].where((x) => x.isNotEmpty).join(' · '),
            title: l.lesson,
            leading: Icon(l.lessonType == 'positive' ? Icons.thumb_up_alt_outlined : Icons.lightbulb_outline_rounded,
                color: l.lessonType == 'positive' ? sem.ok : sem.wip),
            badges: [
              ToneBadge(lessonStatusLabels[l.status] ?? l.status, color: statusColor(l.status)),
              if (l.applyMechanism.isNotEmpty) ToneBadge(l.applyMechanism, color: sem.muted),
              if (l.applyParty.isNotEmpty) Text('التطبيق: ${l.applyParty}', style: TextStyle(color: sem.muted, fontSize: 12)),
            ],
            onTap: () => showPmSheet(
              context,
              code: l.code,
              title: l.lesson,
              badges: [
                ToneBadge(lessonTypeLabels[l.lessonType] ?? l.lessonType, color: l.lessonType == 'positive' ? sem.ok : sem.wip),
                ToneBadge(lessonStatusLabels[l.status] ?? l.status, color: statusColor(l.status)),
              ],
              rows: [
                ('العقد', pmProjectName(app, l.projectId)),
                ('تاريخ التوثيق', pmDay(l.documentedOn)),
                ('المرحلة · المجال', [l.phase, l.domain].where((x) => x.isNotEmpty).join(' · ')),
                ('الموقف (ما الذي حدث)', l.situation),
                ('السبب الجذري', l.rootCause),
                ('الأثر على المشروع', l.effect),
                ('آلية التعميم', l.applyMechanism),
                ('الجهة المعنية بالتطبيق', l.applyParty),
                ('المرجع المرتبط', l.refs),
                ('تاريخ الاعتماد / التطبيق', pmDay(l.appliedOn)),
                ('أعدّه', l.preparedBy),
              ],
              actions: (sheet) => [
                if (app.canEditPm && (l.status == 'proposed' || app.canApproveLessons))
                  FilledButton.tonalIcon(
                    onPressed: () {
                      Navigator.of(sheet).pop();
                      showLessonEditor(context, lesson: l);
                    },
                    icon: const Icon(Icons.edit_outlined),
                    label: Text(app.canApproveLessons && l.status == 'proposed' ? 'تعديل أو اعتماد' : 'تعديل'),
                  ),
                if (app.isDirector) pmDeleteButton(context, sheet, what: l.code, onDelete: () => app.deletePmRecord('lesson', l.id)),
              ],
            ),
          ),
      ],
    );
  }
}
