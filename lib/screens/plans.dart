import 'package:flutter/material.dart';

import '../app_state.dart';
import '../models.dart';
import '../pm.dart';
import '../prices.dart';
import '../schedule.dart';
import '../ui/motion.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';
import 'hub.dart' show sectionColor;
import 'plan_widgets.dart';
import 'pm_common.dart';
import 'prices.dart' show openBoqEditor;
import 'schedule.dart' show ScheduleNotReady, itemsText, pickScheduleProject;

// =====================================================================
// إعداد البرامج الزمنية (الشؤون الفنية): من المقايسة المعتمدة إلى برنامج بمراحل ومدد وتبعيات،
// يُراجَع ويُعدَّل ثم يُعتمد ويُحال إلى الإشراف. الإشراف لا يعدّ البرنامج؛ يتابع تنفيذه.
// =====================================================================

const Map<String, String> planStatusLabels = {'': 'لا برنامج', 'draft': 'مسودة', 'approved': 'معتمد'};

FormStatus planStatusTone(PmPlan? p) => p == null ? FormStatus.todo : (p.approved ? FormStatus.done : FormStatus.wip);

/// لا يعمل الإعداد قبل الترحيل 30.
class PlanNotReady extends StatelessWidget {
  const PlanNotReady({super.key, required this.title});

  final String title;

  @override
  Widget build(BuildContext context) => PageBody(children: [
        PageHeader(title: title, icon: Icons.event_note_outlined),
        const InfoBanner(
          text: 'تعمل هذه الصفحة بعد تحديث قاعدة البيانات بالترحيلات 30 و31 و32 (البرامج الزمنية من المقايسة المعتمدة ومتابعتها في الإشراف).',
          level: 'warning',
        ),
      ]);
}

// =====================================================================
// صفحة «البرامج الزمنية» في الشؤون الفنية
// =====================================================================
class PlansPage extends StatefulWidget {
  const PlansPage({super.key});

  @override
  State<PlansPage> createState() => _PlansPageState();
}

class _PlansPageState extends State<PlansPage> {
  String _filter = '';

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    if (!app.v14Ready) return const ScheduleNotReady(title: 'البرامج الزمنية');
    if (!app.v15Ready) return const PlanNotReady(title: 'البرامج الزمنية');
    final sem = Sem.of(context);
    final accent = sectionColor(context, 'docs');
    final narrow = MediaQuery.sizeOf(context).width < 700;
    final withBoq = {for (final s in app.boqSheets) if (s.approved && s.projectId != null) s.projectId!};
    final ids = {...withBoq, ...app.pmPlans.keys};
    final projects = app.projects.where((p) => ids.contains(p.id)).toList()..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    String key(Project p) => app.planOf(p.id)?.status ?? '';
    final counts = <String, int>{};
    for (final p in projects) {
      counts[key(p)] = (counts[key(p)] ?? 0) + 1;
    }
    final shown = projects.where((p) => _filter.isEmpty || key(p) == _filter || (_filter == 'none' && key(p).isEmpty)).toList();

    return PageBody(
      maxWidth: 1200,
      onRefresh: app.loadAll,
      children: staggered([
        PageHeader(
          title: 'إعداد البرامج الزمنية',
          subtitle: 'من المقايسات المعتمدة: برنامج مبدئي بمراحل ومدد مقترحة، يُراجَع ويُعدَّل ثم يُعتمد ويُحال إلى الإشراف لمتابعة تنفيذه.',
          icon: Icons.event_note_outlined,
          actions: [
            if (app.canPreparePlan)
              FilledButton.icon(
                onPressed: () async {
                  final id = await pickScheduleProject(context, app);
                  if (id != null && context.mounted) openPlanEditor(context, id);
                },
                icon: const Icon(Icons.add_rounded),
                label: const Text('برنامج عقد'),
              ),
          ],
        ),
        ResponsiveGrid(minItemWidth: narrow ? 150 : 200, spacing: 10, children: [
          StatCard(
              label: 'عقود لها مقايسة معتمدة',
              value: '${withBoq.length}',
              sub: 'المقايسات المعتمدة: ${app.boqSheets.where((s) => s.approved).length}',
              icon: Icons.request_quote_outlined,
              color: accent),
          StatCard(
              label: 'بلا برنامج بعد',
              value: '${counts[''] ?? 0}',
              sub: 'تنتظر التوليد من المقايسة',
              icon: Icons.pending_actions_outlined,
              color: (counts[''] ?? 0) > 0 ? sem.statusColor(FormStatus.todo) : null,
              onTap: () => setState(() => _filter = 'none')),
          StatCard(
              label: 'مسودات قيد الإعداد',
              value: '${counts['draft'] ?? 0}',
              sub: 'تُراجَع ثم تُعتمد',
              icon: Icons.edit_calendar_outlined,
              color: sem.statusColor(FormStatus.wip),
              onTap: () => setState(() => _filter = 'draft')),
          StatCard(
              label: 'برامج معتمدة',
              value: '${counts['approved'] ?? 0}',
              sub: 'أُحيلت إلى الإشراف',
              icon: Icons.verified_outlined,
              color: sem.ok,
              onTap: () => setState(() => _filter = 'approved')),
        ]),
        const SizedBox(height: 14),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final f in const [('', 'الكل'), ('none', 'بلا برنامج'), ('draft', 'مسودة'), ('approved', 'معتمد')])
            ChoiceChip(
              label: Text('${f.$2} ${f.$1 == '' ? projects.length : (f.$1 == 'none' ? (counts[''] ?? 0) : (counts[f.$1] ?? 0))}'),
              selected: _filter == f.$1,
              onSelected: (_) => setState(() => _filter = f.$1),
            ),
        ]),
        const SizedBox(height: 12),
        SectionCard(
          title: 'العقود',
          icon: Icons.table_rows_outlined,
          subtitle: 'اضغط العقد لفتح برنامجه: التوليد من المقايسة، والمراحل والمدد والتبعيات، والاعتماد.',
          child: shown.isEmpty
              ? EmptyState(
                  title: projects.isEmpty ? 'لا مقايسات معتمدة بعد' : 'لا عقود بهذا التصنيف',
                  message: projects.isEmpty
                      ? 'اعتمد مقايسة العقد من «مُعِدّ المقايسات» (رئيس الشؤون الفنية أو المدير)، ثم ولّد برنامجه الزمني هنا.'
                      : null,
                  icon: Icons.event_note_outlined,
                )
              : Column(children: [
                  for (var k = 0; k < shown.length; k++) ...[
                    if (k > 0) Divider(height: 1, color: sem.rule),
                    _PlanRow(project: shown[k]),
                  ],
                ]),
        ),
      ], stepMs: 35),
    );
  }
}

class _PlanRow extends StatelessWidget {
  const _PlanRow({required this.project});

  final Project project;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final sem = Sem.of(context);
    final p = project;
    final plan = app.planOf(p.id);
    final items = app.itemsOf(p.id);
    final boqs = app.approvedBoqsOf(p.id);
    final layout = plan == null ? null : PlanLayout(plan.startDate, app.phasesOf(p.id), items);
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => openPlanEditor(context, p.id),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(pmProjectName(app, p.id), maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, height: 1.35)),
              const SizedBox(height: 4),
              Wrap(spacing: 12, runSpacing: 2, children: [
                Text('مقايسات معتمدة: ${boqs.length}${boqs.isEmpty ? '' : ' · ${fmtMoney(boqs.fold<double>(0, (a, s) => a + s.total))}'}',
                    style: TextStyle(color: sem.muted, fontSize: 12.5)),
                if (plan != null) Text('${itemsText(items.length)} · ${app.phasesOf(p.id).length} مراحل', style: TextStyle(color: sem.muted, fontSize: 12.5)),
                if (layout != null && items.isNotEmpty)
                  Text('${pmDay(layout.start)} إلى ${pmDay(layout.end)} · ${daysWord(layout.totalDays)}', style: TextStyle(color: sem.muted, fontSize: 12.5)),
                if (plan?.approved == true) Text('الإصدار ${plan!.version}', style: TextStyle(color: sem.muted, fontSize: 12.5)),
              ]),
            ]),
          ),
          const SizedBox(width: 8),
          StatusChip(planStatusTone(plan), label: planStatusLabels[plan?.status ?? ''], small: true),
          Icon(Icons.chevron_left_rounded, color: sem.muted),
        ]),
      ),
    );
  }
}

Future<void> openPlanEditor(BuildContext context, String projectId) =>
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => PlanEditorPage(projectId: projectId)));

// =====================================================================
// برنامج عقد: التوليد والمراحل والبنود والمدد والتبعيات، والاعتماد
// =====================================================================
class PlanEditorPage extends StatelessWidget {
  const PlanEditorPage({super.key, required this.projectId});

  final String projectId;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final p = app.project(projectId);
    if (p == null || !app.v15Ready) {
      return Scaffold(
        appBar: brandAppBar(context, title: const Text('البرنامج الزمني')),
        body: p == null
            ? const EmptyState(title: 'العقد غير موجود', message: 'ربما حُذف أو دُمج في عقد آخر.', icon: Icons.search_off_rounded)
            : const PlanNotReady(title: 'البرنامج الزمني'),
      );
    }
    final plan = app.planOf(p.id);
    final phases = app.phasesOf(p.id);
    final items = app.itemsOf(p.id);
    final boqs = app.approvedBoqsOf(p.id);
    final draft = plan == null || !plan.approved;
    final canEdit = app.canPreparePlan && draft;
    final start = plan?.startDate ?? app.schedules[p.id]?.startDate ?? pmToday();
    final layout = PlanLayout(start, phases, items);
    final track = ScheduleTrack(p, items, app.pmConfig.refDay, app.pmConfig, plan: plan, phases: phases);
    final narrow = MediaQuery.sizeOf(context).width < 700;
    final hasBoqItems = items.any((i) => i.source == 'boq');
    final bySource = <String, int>{};
    for (final i in items) {
      bySource[i.source] = (bySource[i.source] ?? 0) + 1;
    }

    return Scaffold(
      appBar: brandAppBar(context, title: const Text('إعداد البرنامج الزمني'), actions: [
        if (app.canApprovePlan && plan != null && items.isNotEmpty)
          Padding(
            padding: const EdgeInsetsDirectional.only(end: 8),
            child: plan.approved
                ? OutlinedButton.icon(
                    onPressed: () => _setStatus(context, app, p, 'draft'), icon: const Icon(Icons.lock_open_rounded), label: const Text('إعادة فتح'))
                : FilledButton.icon(
                    onPressed: () => _setStatus(context, app, p, 'approved'),
                    icon: const Icon(Icons.send_rounded),
                    label: const Text('اعتماد وإحالة للإشراف')),
          ),
      ]),
      body: PageBody(maxWidth: 1200, onRefresh: app.loadAll, children: [
        PageHeader(
          title: p.name.isEmpty ? p.assignNo : p.name,
          subtitle: [
            if (p.assignNo.isNotEmpty) 'التكليف ${p.assignNo}',
            if (p.company.isNotEmpty) p.company,
            'البرنامج: ${planStatusLabels[plan?.status ?? '']}${plan?.approved == true ? ' (الإصدار ${plan!.version})' : ''}',
          ].join(' · '),
          icon: Icons.event_note_outlined,
          actions: [
            if (canEdit && boqs.isNotEmpty)
              FilledButton.icon(
                onPressed: () => showGenerateDialog(context, p, replace: hasBoqItems),
                icon: const Icon(Icons.auto_awesome_rounded),
                label: Text(hasBoqItems ? 'إعادة التوليد من المقايسة' : 'توليد من المقايسة'),
              ),
            if (canEdit)
              OutlinedButton.icon(
                onPressed: () => showPhaseEditor(context, p, null),
                icon: const Icon(Icons.view_week_outlined),
                label: const Text('مرحلة'),
              ),
            if (canEdit)
              OutlinedButton.icon(
                onPressed: () => showPlanItemEditor(context, p, null),
                icon: const Icon(Icons.add_rounded),
                label: const Text('بند إضافي أو نشاط'),
              ),
            if (canEdit && plan != null)
              OutlinedButton.icon(
                onPressed: () => _editStart(context, app, p, plan),
                icon: const Icon(Icons.event_outlined),
                label: Text('البداية ${pmDay(plan.startDate)}'),
              ),
          ],
        ),
        if (plan?.approved == true)
          InfoBanner(
            text: 'معتمد ومُحال إلى الإشراف (الإصدار ${plan!.version}${plan.approvedAt == null ? '' : '، ${fmtDate(plan.approvedAt)}'}'
                '${app.people[plan.approvedBy]?.displayName == null ? '' : ' من ${app.people[plan.approvedBy]!.displayName}'}). '
                'لا تُعدَّل المدد ولا المراحل إلا بإعادة فتحه؛ والإشراف يسجّل الإنجاز عليه.',
            level: 'ok',
            icon: Icons.verified_outlined,
          )
        else if (boqs.isEmpty)
          InfoBanner(
            text: 'لا مقايسة معتمدة لهذا العقد: بنود العقد هي بنود مقايسته المعتمدة. اعتمد المقايسة أولاً، أو أضف الأنشطة يدوياً.',
            level: 'warning',
            action: app.boqSheets.any((s) => s.projectId == p.id)
                ? TextButton(onPressed: () => openBoqEditor(context, sheetId: app.boqSheets.firstWhere((s) => s.projectId == p.id).id), child: const Text('المقايسة'))
                : null,
          )
        else if (!app.canPreparePlan)
          const InfoBanner(text: 'للاطلاع: يعدّ البرنامج الزمني الشؤون الفنية ومكتب المدير، ويعتمده رئيس الشؤون الفنية أو المدير.'),
        const SizedBox(height: 10),
        ResponsiveGrid(minItemWidth: narrow ? 150 : 190, spacing: 10, children: [
          StatCard(
              label: 'المدة الإجمالية',
              value: items.isEmpty ? '—' : daysWord(layout.totalDays),
              sub: items.isEmpty ? 'لا بنود بعد' : '${pmDay(layout.start)} إلى ${pmDay(layout.end)}',
              icon: Icons.timelapse_rounded,
              color: Theme.of(context).colorScheme.primary),
          StatCard(label: 'مراحل التنفيذ', value: '${phases.length}', sub: 'بترتيب منطقي متتالٍ', icon: Icons.view_week_outlined),
          StatCard(
              label: 'البنود',
              value: '${items.length}',
              sub: 'مقايسة ${bySource['boq'] ?? 0} · إضافية ${bySource['extra'] ?? 0} · أنشطة ${bySource['manual'] ?? 0}',
              icon: Icons.list_alt_rounded),
          StatCard(
              label: 'قيمة المقايسات المعتمدة',
              value: boqs.isEmpty ? '—' : fmtMoney(boqs.fold<double>(0, (a, s) => a + s.total)),
              sub: '${boqs.length} مقايسة · أوزان البنود منها',
              icon: Icons.request_quote_outlined),
        ]),
        const SizedBox(height: 14),
        if (items.isEmpty)
          SectionCard(
            title: 'البرنامج',
            icon: Icons.event_note_outlined,
            child: EmptyState(
              title: 'لا بنود بعد',
              message: canEdit && boqs.isNotEmpty
                  ? '«توليد من المقايسة» ينشئ مرحلة لكل قسم من أقسام اللائحة ويقترح مدة لكل بند بحسب قيمته، ثم تعدّل كل مدة على حدة.'
                  : 'يبدأ البرنامج من المقايسة المعتمدة للعقد.',
              icon: Icons.auto_awesome_outlined,
            ),
          )
        else ...[
          SectionCard(
            title: 'المخطط الزمني',
            icon: Icons.view_timeline_rounded,
            subtitle: 'من اليمين إلى اليسار: شريط لكل مرحلة بامتدادها، ثم بنودها بمددها. أي تعديل في مدة أو فاصل يعيد حساب ما بعده والمدة الإجمالية.',
            child: PlanGantt(rows: ganttRows(context, track, progress: plan?.approved == true, onTap: (i) => _itemSheet(context, app, p, track, i))),
          ),
          const SizedBox(height: 14),
          SectionCard(
            title: 'المراحل والبنود',
            icon: Icons.account_tree_outlined,
            subtitle: canEdit ? 'اضغط المرحلة لتعديل اسمها وفاصلها، والبند لتعديل مدته وإزاحته وتبعيته.' : null,
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              for (final i in items.where((i) => i.phaseId == null || !phases.any((ph) => ph.id == i.phaseId)))
                _ItemLine(item: i, layout: layout, items: items, onTap: () => _itemSheet(context, app, p, track, i)),
              for (final ph in phases) ...[
                _PhaseHeader(
                  phase: ph,
                  span: layout.spans.where((s) => s.phase.id == ph.id).firstOrNull,
                  onTap: canEdit ? () => showPhaseEditor(context, p, ph) : null,
                  onDelete: canEdit && !items.any((i) => i.phaseId == ph.id) ? () => _deletePhase(context, app, ph) : null,
                ),
                for (final i in items.where((i) => i.phaseId == ph.id))
                  _ItemLine(item: i, layout: layout, items: items, onTap: () => _itemSheet(context, app, p, track, i)),
                const SizedBox(height: 6),
              ],
            ]),
          ),
        ],
      ]),
    );
  }

  Future<void> _setStatus(BuildContext context, AppState app, Project p, String status) async {
    final approve = status == 'approved';
    final ok = await confirmDialog(context,
        title: approve ? 'اعتماد البرنامج الزمني' : 'إعادة فتح البرنامج الزمني',
        message: approve
            ? 'يُعتمد البرنامج بتواريخه الحالية ويُحال إلى الإشراف، فيُشعَر رئيس القسم المشرف على العقد ويبدأ تسجيل الإنجاز عليه. '
                'لا تُعدَّل بعده المدد ولا المراحل إلا بإعادة فتحه.'
            : 'يعود البرنامج مسودة للتعديل، ويتوقف تسجيل الإنجاز عليه وترجمته إلى المخاطر حتى يُعتمد من جديد. الإنجاز المسجّل يبقى.',
        confirmLabel: approve ? 'اعتماد وإحالة' : 'إعادة فتح');
    if (!ok || !context.mounted) return;
    try {
      await app.setPlanStatus(p.id, status);
      if (context.mounted) showToast(context, approve ? 'اعتُمد البرنامج وأُحيل إلى الإشراف' : 'أُعيد فتح البرنامج للتعديل');
    } catch (e) {
      if (context.mounted) showToast(context, friendlyError(e), error: true);
    }
  }

  Future<void> _editStart(BuildContext context, AppState app, Project p, PmPlan plan) async {
    final d = await showDatePicker(
      context: context,
      initialDate: plan.startDate,
      firstDate: DateTime(2015),
      lastDate: DateTime(2040),
      helpText: 'بداية البرنامج الزمني',
    );
    if (d == null || !context.mounted) return;
    try {
      await app.savePmPlan(p.id, {'start_date': pmIso(d)});
      if (context.mounted) showToast(context, 'بداية البرنامج ${pmDay(d)}، وأُعيد حساب التواريخ');
    } catch (e) {
      if (context.mounted) showToast(context, friendlyError(e), error: true);
    }
  }

  Future<void> _deletePhase(BuildContext context, AppState app, PmPhase ph) async {
    final ok = await confirmDialog(context, title: 'حذف المرحلة', message: 'تُحذف المرحلة «${ph.name}» الفارغة.', confirmLabel: 'حذف', danger: true);
    if (!ok || !context.mounted) return;
    try {
      await app.deletePmPhase(ph.id);
      if (context.mounted) showToast(context, 'حُذفت المرحلة');
    } catch (e) {
      if (context.mounted) showToast(context, friendlyError(e), error: true);
    }
  }

  Future<void> _itemSheet(BuildContext context, AppState app, Project p, ScheduleTrack t, PmItem i) {
    final plan = app.planOf(p.id);
    final canEdit = app.canPreparePlan && plan?.approved != true;
    final dep = i.dependsOn == null ? null : t.allItems.where((x) => x.id == i.dependsOn).firstOrNull;
    final phase = t.phases.where((x) => x.id == i.phaseId).firstOrNull;
    return showPmSheet(
      context,
      code: i.code,
      title: i.title,
      badges: [
        ToneBadge(itemSourceLabels[i.source] ?? i.source, color: Theme.of(context).colorScheme.primary),
        StatusChip(itemStatus(i), small: true),
      ],
      rows: [
        ('المرحلة', phase?.name ?? 'دون مرحلة'),
        ('المدة', i.durationDays == null ? '${daysWord(i.days)} (بتاريخين محددين)' : daysWord(i.durationDays!)),
        ('البداية · النهاية المخططتان', '${pmDay(i.plannedStart)} إلى ${pmDay(i.plannedEnd)}'),
        ('الإزاحة داخل المرحلة', i.offsetDays == 0 ? '' : daysWord(i.offsetDays)),
        ('يتبع البند', dep == null ? '' : [dep.code, dep.title].where((x) => x.isNotEmpty).join(' ')),
        ('الوحدة · الكمية', i.unit.isEmpty && i.qty == null ? '' : '${i.unit} · ${i.qty == null ? '—' : fmtQty(i.qty!)}'),
        ('الوزن (القيمة)', i.weight == null ? 'متوسط أوزان البنود' : fmtMoney(i.weight)),
        ('الإنجاز', plan?.approved == true ? '${i.progress.toStringAsFixed(0)}%' : ''),
      ],
      actions: (sheet) => [
        if (canEdit)
          FilledButton.icon(
            onPressed: () {
              Navigator.of(sheet).pop();
              showPlanItemEditor(context, p, i);
            },
            icon: const Icon(Icons.edit_outlined),
            label: const Text('المدة والترتيب'),
          ),
        if (canEdit) pmDeleteButton(context, sheet, what: 'البند', onDelete: () => app.deletePmItem(i.id)),
      ],
    );
  }
}

String fmtQty(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(3).replaceFirst(RegExp(r'0+$'), '');

class _PhaseHeader extends StatelessWidget {
  const _PhaseHeader({required this.phase, required this.span, this.onTap, this.onDelete});

  final PmPhase phase;
  final PhaseSpan? span;
  final VoidCallback? onTap;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final sem = Sem.of(context);
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.primaryContainer.withValues(alpha: 0.45),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          child: Row(children: [
            Icon(Icons.view_week_rounded, size: 18, color: cs.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(phase.name, style: TextStyle(fontWeight: FontWeight.w800, color: cs.primary)),
            ),
            if (span != null)
              Text('${pmDay(span!.start)} إلى ${pmDay(span!.end)} · ${daysWord(span!.days)}',
                  style: TextStyle(color: sem.muted, fontSize: 12.5, fontFeatures: const [FontFeature.tabularFigures()])),
            if (phase.lagDays != 0) ...[
              const SizedBox(width: 8),
              ToneBadge(phase.lagDays > 0 ? 'فاصل ${daysWord(phase.lagDays)}' : 'تداخل ${daysWord(-phase.lagDays)}', color: sem.muted),
            ],
            if (onDelete != null) IconButton(tooltip: 'حذف المرحلة الفارغة', onPressed: onDelete, icon: const Icon(Icons.delete_outline_rounded, size: 18)),
          ]),
        ),
      ),
    );
  }
}

class _ItemLine extends StatelessWidget {
  const _ItemLine({required this.item, required this.layout, required this.items, this.onTap});

  final PmItem item;
  final PlanLayout layout;
  final List<PmItem> items;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final sem = Sem.of(context);
    final i = item;
    final dep = i.dependsOn == null ? null : items.where((x) => x.id == i.dependsOn).firstOrNull;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(12, 8, 4, 8),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
            width: 70,
            child: Text(i.code.isEmpty ? '—' : i.code, style: TextStyle(color: sem.muted, fontWeight: FontWeight.w700, fontSize: 12.5)),
          ),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(i.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(height: 1.35, color: i.notApplicable ? sem.muted : null)),
              const SizedBox(height: 3),
              Wrap(spacing: 10, runSpacing: 2, children: [
                Text('${pmDay(i.plannedStart)} إلى ${pmDay(i.plannedEnd)}', style: TextStyle(color: sem.muted, fontSize: 12)),
                if (i.offsetDays > 0) Text('إزاحة ${daysWord(i.offsetDays)}', style: TextStyle(color: sem.muted, fontSize: 12)),
                if (dep != null) Text('يتبع ${dep.code.isEmpty ? dep.title : dep.code}', style: TextStyle(color: sem.muted, fontSize: 12)),
                if (i.unit.isNotEmpty || i.qty != null) Text('${i.qty == null ? '' : fmtQty(i.qty!)} ${i.unit}', style: TextStyle(color: sem.muted, fontSize: 12)),
                if (i.source != 'boq') Text(itemSourceLabels[i.source] ?? '', style: TextStyle(color: Theme.of(context).colorScheme.primary, fontSize: 12)),
              ]),
            ]),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
            decoration: BoxDecoration(color: sem.surface2, borderRadius: BorderRadius.circular(8), border: Border.all(color: sem.rule)),
            child: Text(daysWord(i.days), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5)),
          ),
        ]),
      ),
    );
  }
}

int? _intOf(dynamic v) {
  if (v is num) return v.toInt();
  final t = '${v ?? ''}'.trim().replaceAllMapped(RegExp('[٠-٩]'), (m) => '${m[0]!.codeUnitAt(0) - 0x0660}').replaceAll('−', '-');
  return t.isEmpty ? null : int.tryParse(t);
}

/// المرحلة: اسمها وفاصلها عن سابقتها (سالب = تداخل).
Future<void> showPhaseEditor(BuildContext context, Project p, PmPhase? ph) async {
  final app = AppScope.read(context);
  final ok = await showPmForm(
    context,
    title: ph == null ? 'مرحلة تنفيذ جديدة' : 'تعديل المرحلة',
    note: 'المرحلة تبدأ بنهاية المرحلة السابقة + الفاصل. الفاصل السالب يجعلها تتداخل مع سابقتها بعدد أيامه. '
        'المرحلة الجديدة تُضاف في آخر البرنامج.',
    sections: const [
      PmSection('المرحلة', [
        PmField('name', 'اسم المرحلة', PmKind.text, required: true, max: 120, full: true),
        PmField('lag_days', 'الفاصل عن المرحلة السابقة (يوم، سالب للتداخل)', PmKind.text, max: 6),
        PmField('sort', 'الترتيب', PmKind.integer, helper: 'رقم أصغر = أبكر'),
      ]),
    ],
    values: {'name': ph?.name ?? '', 'lag_days': '${ph?.lagDays ?? 0}', 'sort': ph?.sort},
    onSave: (d) async {
      final lag = _intOf(d['lag_days']);
      if ('${d['lag_days'] ?? ''}'.trim().isNotEmpty && lag == null) throw 'الفاصل رقم صحيح (مثل 5 أو -3)';
      await app.savePmPhase(ph?.id, {
        'project_id': p.id,
        'name': d['name'],
        'lag_days': lag ?? 0,
        if (d['sort'] != null) 'sort': d['sort'],
      });
    },
  );
  if (ok && context.mounted) showToast(context, ph == null ? 'أُضيفت المرحلة' : 'حُفظت المرحلة وأُعيد حساب التواريخ');
}

/// بند البرنامج: المدة والإزاحة والمرحلة والتبعية (والاسم والوحدة والكمية لغير بنود المقايسة)، مع معاينة حية للمدة الإجمالية.
Future<void> showPlanItemEditor(BuildContext context, Project p, PmItem? item) async {
  final app = AppScope.read(context);
  final plan = app.planOf(p.id);
  final phases = app.phasesOf(p.id);
  final items = app.itemsOf(p.id);
  final start = plan?.startDate ?? app.schedules[p.id]?.startDate ?? pmToday();
  final before = PlanLayout(start, phases, items);
  final boqItem = item?.source == 'boq';
  final order = orderItems(items, phases);
  final idx = item == null ? order.length : order.indexWhere((x) => x.id == item.id);
  // التبعية لبند سابق في الترتيب (المرحلة ثم البند)
  final earlier = [for (var k = 0; k < (idx < 0 ? order.length : idx); k++) order[k]];
  final ok = await showPmForm(
    context,
    title: item == null ? 'بند إضافي أو نشاط' : 'البند في البرنامج',
    note: boqItem
        ? 'بند من المقايسة المعتمدة: وصفه وكميته منها. عدّل مدته وإزاحته داخل المرحلة والبند الذي يتبعه.'
        : 'البند الإضافي للعقد لا يكون في المقايسة المعتمدة ولا يُضاف مرتين؛ والنشاط عمل ليس بنداً مالياً (مثل تجهيز الموقع). '
            'البند يبدأ ببداية مرحلته أو بنهاية البند الذي يتبعه، أيهما أبعد، + الإزاحة.',
    sections: [
      PmSection('البند', [
        PmField('title', 'الوصف', PmKind.text, required: true, max: 300, full: true, enabled: !boqItem),
        PmField('code', 'الرقم', PmKind.text, max: 20, enabled: !boqItem),
        if (item == null) const PmField('source', 'النوع', PmKind.select, options: [('extra', 'بند إضافي للعقد'), ('manual', 'نشاط')]),
        PmField('unit', 'الوحدة', PmKind.text, max: 20, enabled: !boqItem),
        PmField('qty', 'الكمية', PmKind.decimal, enabled: !boqItem),
        PmField('weight', 'الوزن (القيمة)', PmKind.decimal, enabled: !boqItem, helper: 'فارغ = متوسط أوزان البنود'),
      ]),
      PmSection('الجدولة', [
        PmField('phase_id', 'المرحلة', PmKind.select, options: [('', 'دون مرحلة (من بداية البرنامج)'), for (final ph in phases) (ph.id, ph.name)]),
        const PmField('duration_days', 'المدة (يوم)', PmKind.integer, required: true),
        const PmField('offset_days', 'الإزاحة داخل المرحلة (يوم)', PmKind.integer, helper: 'تأخير بدايته عن بداية مرحلته أو عن نهاية البند الذي يتبعه'),
        PmField('depends_on', 'يتبع البند', PmKind.select,
            options: [('', 'لا يتبع بنداً'), for (final x in earlier) (x.id, [x.code, x.title].where((s) => s.isNotEmpty).join(' '))],
            full: true),
      ]),
    ],
    values: item == null
        ? {'source': 'extra', 'phase_id': phases.isEmpty ? '' : phases.last.id, 'duration_days': 7, 'offset_days': 0, 'depends_on': ''}
        : {
            'title': item.title,
            'code': item.code,
            'unit': item.unit,
            'qty': item.qty,
            'weight': item.weight,
            'phase_id': item.phaseId ?? '',
            'duration_days': item.days,
            'offset_days': item.offsetDays,
            'depends_on': item.dependsOn ?? '',
          },
    preview: (v) {
      final dur = v['duration_days'] as int?;
      if (dur == null || dur < 1) return null;
      final ph = '${v['phase_id'] ?? ''}';
      final dep = '${v['depends_on'] ?? ''}';
      final draftItem = (item ??
              PmItem(id: '__new__', projectId: p.id, title: '', plannedStart: start, plannedEnd: start, sort: 1 << 30))
          .copyWith(
              durationDays: dur,
              offsetDays: (v['offset_days'] as int?) ?? 0,
              phaseId: ph.isEmpty ? null : ph,
              dependsOn: dep.isEmpty ? null : dep,
              clearDepends: dep.isEmpty);
      final list = [for (final x in items) if (x.id != draftItem.id) x, draftItem];
      final after = PlanLayout(start, phases, list);
      final d = after.dates[draftItem.id];
      final diff = after.totalDays - before.totalDays;
      return InfoBanner(
        text: 'البند ${d == null ? '' : 'من ${pmDay(d.$1)} إلى ${pmDay(d.$2)}'} · المدة الإجمالية للبرنامج ${daysWord(after.totalDays)}'
            '${items.isEmpty || diff == 0 ? '' : (diff > 0 ? ' (تزيد ${daysWord(diff)})' : ' (تنقص ${daysWord(-diff)})')}'
            ' · النهاية ${pmDay(after.end)}',
        level: diff > 0 ? 'warning' : 'info',
      );
    },
    onSave: (d) async {
      final data = <String, dynamic>{
        'project_id': p.id,
        'phase_id': d['phase_id'] ?? '',
        'duration_days': d['duration_days'],
        'offset_days': d['offset_days'] ?? 0,
        'depends_on': d['depends_on'] ?? '',
        if (!boqItem) ...{
          'title': d['title'],
          'code': d['code'] ?? '',
          'unit': d['unit'] ?? '',
          'qty': d['qty'],
          'weight': d['weight'],
        },
        if (item == null) 'source': d['source'] ?? 'extra',
      };
      await app.savePmItem(item?.id, data);
    },
  );
  if (ok && context.mounted) showToast(context, item == null ? 'أُضيف البند وأُعيد حساب البرنامج' : 'حُفظ البند وأُعيد حساب البرنامج');
}

/// التوليد من المقايسات المعتمدة: معاينة المراحل والمدد المقترحة، ثم الإنشاء.
Future<void> showGenerateDialog(BuildContext context, Project p, {bool replace = false}) async {
  final app = AppScope.read(context);
  final sched = app.schedules[p.id];
  var start = app.planOf(p.id)?.startDate ?? sched?.startDate ?? pmToday();
  final suggested = sched?.startDate != null && sched?.endDate != null ? daysBetween(sched!.endDate!, sched.startDate!) : 180;
  final days = TextEditingController(text: '${suggested.clamp(7, 3650)}');
  Map<String, dynamic>? preview;
  String? error;
  var busy = false;
  var started = false;
  final done = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(builder: (ctx, setLocal) {
      final sem = Sem.of(ctx);
      void upd(VoidCallback f) {
        if (ctx.mounted) setLocal(f);
      }

      Future<void> load() async {
        final n = _intOf(days.text);
        if (n == null || n < 7 || n > 3650) {
          upd(() => error = 'المدة الإجمالية بين 7 و3650 يوماً');
          return;
        }
        upd(() {
          busy = true;
          error = null;
        });
        try {
          final r = await app.planPreview(p.id, n);
          upd(() => preview = r);
        } catch (e) {
          upd(() => error = friendlyError(e));
        } finally {
          upd(() => busy = false);
        }
      }

      // المعاينة بالمدة المقترحة فور فتح النافذة
      if (!started) {
        started = true;
        Future.microtask(load);
      }
      final phases = (preview?['phases'] as List?) ?? const [];
      return AlertDialog(
        title: const Text('برنامج مبدئي من المقايسة المعتمدة'),
        content: SizedBox(
          width: 640,
          child: SingleChildScrollView(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
              Text(
                'مرحلة لكل قسم من أقسام لائحة الأسعار بترتيبها، والمراحل متتالية والبنود داخل كل مرحلة متوازية. '
                'مدة المرحلة = المدة الإجمالية × نصيبها من قيمة المقايسة (3 أيام على الأقل)، '
                'ومدة البند = مدة مرحلته × الجذر التربيعي لنسبة قيمته إلى أكبر بند في المرحلة (يوم على الأقل). '
                'بعد التوليد تُعدَّل كل مدة على حدة.',
                style: TextStyle(color: sem.muted, fontSize: 12.5, height: 1.5),
              ),
              const SizedBox(height: 12),
              Wrap(spacing: 10, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.center, children: [
                OutlinedButton.icon(
                  onPressed: () async {
                    final d = await showDatePicker(context: ctx, initialDate: start, firstDate: DateTime(2015), lastDate: DateTime(2040));
                    if (d != null) setLocal(() => start = d);
                  },
                  icon: const Icon(Icons.event_outlined),
                  label: Text('البداية ${pmDay(start)}'),
                ),
                SizedBox(
                  width: 220,
                  child: TextField(
                    controller: days,
                    keyboardType: TextInputType.number,
                    decoration: fieldDeco('المدة الإجمالية المقترحة (يوم)'),
                    onSubmitted: (_) => load(),
                  ),
                ),
                TextButton.icon(onPressed: busy ? null : load, icon: const Icon(Icons.preview_outlined), label: const Text('معاينة')),
              ]),
              if (error != null) ...[const SizedBox(height: 10), InfoBanner(text: error!, level: 'critical')],
              if (busy) const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator())),
              if (preview != null && !busy) ...[
                const SizedBox(height: 12),
                InfoBanner(
                  text: '${phases.length} مراحل · ${preview!['items']} بنداً · المدة الإجمالية ${daysWord((preview!['total_days'] as num).toInt())} '
                      '(من ${pmDay(start)} إلى ${pmDay(addDays(start, (preview!['total_days'] as num).toInt()))})',
                  level: 'ok',
                ),
                const SizedBox(height: 8),
                for (final ph in phases)
                  ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    title: Text('${ph['name']}', style: const TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: Text('${daysWord((ph['days'] as num).toInt())} · ${fmtMoney((ph['cost'] as num?)?.toDouble() ?? 0)}',
                        style: TextStyle(color: sem.muted, fontSize: 12.5)),
                    children: [
                      for (final it in (ph['items'] as List? ?? const []))
                        ListTile(
                          dense: true,
                          contentPadding: const EdgeInsetsDirectional.only(start: 12),
                          title: Text('${it['code']} ${it['title']}', maxLines: 2, overflow: TextOverflow.ellipsis),
                          trailing: Text(daysWord((it['days'] as num).toInt()), style: const TextStyle(fontWeight: FontWeight.w800)),
                        ),
                    ],
                  ),
              ],
              if (replace) ...[
                const SizedBox(height: 10),
                const InfoBanner(
                  text: 'البرنامج يحوي بنود المقايسة: إعادة التوليد تستبدلها ومراحلها الفارغة بمدد جديدة. البنود الإضافية والأنشطة تبقى.',
                  level: 'warning',
                ),
              ],
            ]),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('إلغاء')),
          FilledButton.icon(
            onPressed: busy || preview == null
                ? null
                : () async {
                    final n = _intOf(days.text)!;
                    setLocal(() => busy = true);
                    try {
                      await app.planGenerate(p.id, start, n, replace: replace);
                      if (ctx.mounted) Navigator.of(ctx).pop(true);
                    } catch (e) {
                      setLocal(() {
                        busy = false;
                        error = friendlyError(e);
                      });
                    }
                  },
            icon: const Icon(Icons.auto_awesome_rounded),
            label: Text(replace ? 'استبدال وتوليد' : 'توليد البرنامج'),
          ),
        ],
      );
    }),
  );
  days.dispose();
  if (done == true && context.mounted) showToast(context, 'وُلّد البرنامج المبدئي؛ راجع المدد والترتيب ثم اعتمده');
}

/// ملخص نصي لمقايسات عقد معتمدة (للوحة والدليل).
String boqSummary(List<BoqSheet> s) => s.isEmpty ? 'لا مقايسة معتمدة' : '${s.length} مقايسة · ${fmtMoney(s.fold<double>(0, (a, x) => a + x.total))}';
