import 'package:flutter/material.dart';

import '../app_state.dart';
import '../lifecycle.dart';
import '../models.dart';
import '../pm.dart';
import '../registers.dart';
import '../schedule.dart';
import '../ui/charts.dart';
import '../ui/motion.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';
import '../print/export_dialog.dart';
import 'hub.dart' show sectionColor;
import 'plan_widgets.dart';
import 'plans.dart' show PlanNotReady, fmtQty, openPlanEditor;
import 'pm_common.dart';
import 'project_detail.dart' show ProjectDetailPage;
import 'schedule.dart' show PlanActualBar, ScheduleNotReady, itemsText, varText, daysVarText;

// =====================================================================
// الإشراف مركزاً لمتابعة التنفيذ: لوحة المشاريع والعقود، وبنود كل العقود (امتداد مقايساتها المعتمدة)،
// وصفحة متابعة العقد بخط دورة حياته من اليمين وبرنامجه المعتمد وإنجاز بنوده، وأثرها في المخاطر وSWOT.
// الإشراف يتابع البرنامج المعتمد ولا يعدّه؛ الإعداد في «البرامج الزمنية» بالشؤون الفنية.
// =====================================================================

/// حالة المشروع في لوحة الإشراف.
const Map<String, String> projectStateLabels = {
  'done': 'منجز',
  'late': 'متأخر',
  'running': 'قيد التنفيذ',
  'not_started': 'لم يبدأ',
};

Color projectStateColor(Sem sem, String s) => switch (s) {
      'done' => sem.statusColor(FormStatus.done),
      'late' => sem.statusColor(FormStatus.todo),
      'running' => sem.statusColor(FormStatus.wip),
      _ => sem.muted,
    };

/// متابعة عقد مجمّعة: جدوله ومراحل دورة حياته وحالته.
class ProjectFollow {
  ProjectFollow(this.project, this.track, this.life, this.schedule);

  final Project project;
  final ScheduleTrack? track;
  final List<LifePhase> life;
  final PmSchedule? schedule;

  /// منجز: أُقفل العقد أو اكتمل تنفيذه؛ متأخر: البرنامج المعتمد متأخر؛ قيد التنفيذ: بدأ تنفيذه؛ وإلا لم يبدأ.
  String get state {
    final exec = life[1].status;
    if (life.last.status == FormStatus.done || exec == FormStatus.done) return 'done';
    if (track?.isLate ?? false) return 'late';
    if (exec == FormStatus.wip) return 'running';
    return 'not_started';
  }

  LifePhase get current => life[currentPhaseIndex(life)];
}

ProjectFollow followOf(AppState app, Project p) {
  final t = app.schedule.track(p.id);
  return ProjectFollow(
    p,
    t,
    lifecycleOf(
      formDefs: app.allFormDefs,
      statuses: app.statuses[p.id] ?? const {},
      formDates: app.formDates[p.id] ?? const {},
      track: t,
      schedule: app.schedules[p.id],
      extracts: app.extractsOf(p.id),
    ),
    app.schedules[p.id],
  );
}

// =====================================================================
// لوحة الإشراف
// =====================================================================
class SupervisionDashboardPage extends StatefulWidget {
  const SupervisionDashboardPage({super.key});

  @override
  State<SupervisionDashboardPage> createState() => _SupervisionDashboardPageState();
}

class _SupervisionDashboardPageState extends State<SupervisionDashboardPage> {
  String _project = '';
  String _company = '';
  String _location = '';
  String _period = '';
  String _state = '';

  (DateTime, DateTime)? _range(DateTime ref) => switch (_period) {
        'month' => (DateTime(ref.year, ref.month, 1), DateTime(ref.year, ref.month + 1, 0)),
        'quarter' => (DateTime(ref.year, ((ref.month - 1) ~/ 3) * 3 + 1, 1), DateTime(ref.year, ((ref.month - 1) ~/ 3) * 3 + 4, 0)),
        'year' => (DateTime(ref.year, 1, 1), DateTime(ref.year, 12, 31)),
        _ => null,
      };

  bool _inPeriod(ProjectFollow f, (DateTime, DateTime)? r) {
    if (r == null) return true;
    final s = f.track?.start ?? f.schedule?.startDate, e = f.track?.end ?? f.schedule?.endDate;
    if (s == null && e == null) return false;
    return !(s ?? e!).isAfter(r.$2) && !(e ?? s!).isBefore(r.$1);
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    if (!app.v14Ready) return const ScheduleNotReady(title: 'لوحة الإشراف');
    if (!app.v15Ready) return const PlanNotReady(title: 'لوحة الإشراف');
    final sem = Sem.of(context);
    final accent = sectionColor(context, 'supervision');
    final narrow = MediaQuery.sizeOf(context).width < 700;
    final ref = app.pmConfig.refDay;
    final all = [for (final p in app.projects) followOf(app, p)];
    final companies = {for (final f in all) if (f.project.company.trim().isNotEmpty) f.project.company.trim()}.toList()..sort();
    final locations = {for (final f in all) if ((f.schedule?.location ?? '').trim().isNotEmpty) f.schedule!.location.trim()}.toList()..sort();
    final range = _range(ref);
    final scope = all
        .where((f) =>
            (_project.isEmpty || f.project.id == _project) &&
            (_company.isEmpty || f.project.company.trim() == _company) &&
            (_location.isEmpty || (f.schedule?.location ?? '').trim() == _location) &&
            _inPeriod(f, range))
        .toList();
    final shown = scope.where((f) => _state.isEmpty || f.state == _state || (_state == 'running' && f.state == 'late')).toList();
    final states = <String, int>{};
    for (final f in scope) {
      states[f.state] = (states[f.state] ?? 0) + 1;
    }
    final items = [for (final f in scope) ...?f.track?.allItems];
    final ist = <FormStatus, int>{};
    for (final i in items) {
      ist[itemStatus(i)] = (ist[itemStatus(i)] ?? 0) + 1;
    }
    final lateItems = [
      for (final f in scope)
        if (f.track != null)
          for (final c in f.track!.lateItems) (f, c),
    ]..sort((a, b) => a.$2.variance.compareTo(b.$2.variance));
    final tracked = scope.where((f) => f.track != null).toList();
    final running = (states['running'] ?? 0) + (states['late'] ?? 0);

    return PageBody(
      maxWidth: 1320,
      onRefresh: app.loadAll,
      children: staggered([
        PageHeader(
          title: 'لوحة الإشراف',
          subtitle: 'متابعة التنفيذ مرتبطة بالعقود والمقايسات والبرامج الزمنية المعتمدة ومراحل التنفيذ والمستخلصات · تاريخ الإسناد ${pmDay(ref)}',
          icon: Icons.space_dashboard_outlined,
          actions: [
            if (items.isNotEmpty)
              OutlinedButton.icon(
                onPressed: () => showExportDialog(context,
                    sourceId: 'risks:schedule',
                    items: [for (final f in tracked) ...f.track!.calcs],
                    title: 'بنود العقود ونسب تنفيذها'),
                icon: const Icon(Icons.ios_share_rounded),
                label: const Text('تصدير البنود'),
              ),
          ],
        ),
        Wrap(spacing: 10, runSpacing: 10, children: [
          SizedBox(
            width: narrow ? double.infinity : 300,
            child: SelectField(
              label: 'المشروع',
              value: _project,
              items: [('', 'كل المشاريع'), for (final f in all) (f.project.id, pmProjectName(app, f.project.id))],
              onChanged: (v) => setState(() => _project = v),
            ),
          ),
          SizedBox(
            width: narrow ? double.infinity : 220,
            child: SelectField(
              label: 'الشركة',
              value: _company,
              items: [('', 'كل الشركات'), for (final c in companies) (c, c)],
              onChanged: (v) => setState(() => _company = v),
            ),
          ),
          SizedBox(
            width: narrow ? double.infinity : 200,
            child: SelectField(
              label: 'الموقع',
              value: _location,
              items: [('', 'كل المواقع'), for (final c in locations) (c, c)],
              onChanged: (v) => setState(() => _location = v),
            ),
          ),
          SizedBox(
            width: narrow ? double.infinity : 200,
            child: SelectField(
              label: 'الفترة',
              value: _period,
              items: const [('', 'كل الفترات'), ('month', 'الشهر الحالي'), ('quarter', 'الربع الحالي'), ('year', 'السنة الحالية')],
              onChanged: (v) => setState(() => _period = v),
            ),
          ),
        ]),
        const SizedBox(height: 14),
        ResponsiveGrid(minItemWidth: narrow ? 150 : 200, spacing: 10, children: [
          StatCard(
              label: 'إجمالي المشاريع',
              value: '${scope.length}',
              sub: 'لها برنامج معتمد: ${tracked.length}',
              icon: Icons.apartment_rounded,
              color: accent,
              onTap: () => setState(() => _state = '')),
          StatCard(
              label: 'قيد التنفيذ',
              value: '$running',
              sub: 'لم تبدأ: ${states['not_started'] ?? 0}',
              icon: Icons.construction_rounded,
              color: sem.statusColor(FormStatus.wip),
              onTap: () => setState(() => _state = 'running')),
          StatCard(
              label: 'المنجزة',
              value: '${states['done'] ?? 0}',
              sub: 'أُقفل منها: ${scope.where((f) => f.life.last.status == FormStatus.done).length}',
              icon: Icons.verified_outlined,
              color: sem.statusColor(FormStatus.done),
              onTap: () => setState(() => _state = 'done')),
          StatCard(
              label: 'المتأخرة',
              value: '${states['late'] ?? 0}',
              sub: 'عن برامجها الزمنية المعتمدة',
              icon: Icons.running_with_errors_rounded,
              color: (states['late'] ?? 0) > 0 ? sem.statusColor(FormStatus.todo) : sem.ok,
              onTap: () => setState(() => _state = 'late')),
        ]),
        const SizedBox(height: 10),
        ResponsiveGrid(minItemWidth: narrow ? 150 : 200, spacing: 10, children: [
          StatCard(
              label: 'بنود العقود',
              value: '${items.length}',
              sub: 'لا ينطبق: ${ist[FormStatus.na] ?? 0}',
              icon: Icons.format_list_numbered_rounded,
              onTap: () => app.setTab(73)),
          StatCard(label: 'المنفذة', value: '${ist[FormStatus.done] ?? 0}', icon: Icons.task_alt_rounded, color: sem.statusColor(FormStatus.done)),
          StatCard(label: 'قيد التنفيذ', value: '${ist[FormStatus.wip] ?? 0}', icon: Icons.timelapse_rounded, color: sem.statusColor(FormStatus.wip)),
          StatCard(
              label: 'غير المنفذة',
              value: '${ist[FormStatus.todo] ?? 0}',
              sub: 'المتأخرة من كل البنود: ${lateItems.length}',
              icon: Icons.pending_outlined,
              color: sem.statusColor(FormStatus.todo)),
        ]),
        const SizedBox(height: 14),
        LayoutBuilder(builder: (context, box) {
          final wide = box.maxWidth >= 900;
          final donut = SectionCard(
            title: 'حالة المشاريع',
            icon: Icons.donut_large_rounded,
            child: Column(children: [
              BreakdownChart(
                items: [for (final k in projectStateLabels.keys) (projectStateLabels[k]!, (states[k] ?? 0).toDouble())],
                colors: [for (final k in projectStateLabels.keys) projectStateColor(sem, k)],
                centerTitle: 'مشروع',
                centerValue: '${scope.length}',
                format: (v) => v.toStringAsFixed(0),
                onTap: (i) => setState(() => _state = projectStateLabels.keys.elementAt(i)),
              ),
            ]),
          );
          final stack = SectionCard(
            title: 'بنود العقود حسب الحالة',
            icon: Icons.stacked_bar_chart_rounded,
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              StackBar(
                parts: [for (final s in FormStatus.values) (s.label, (ist[s] ?? 0).toDouble(), sem.statusColor(s))],
                format: (v) => v.toStringAsFixed(0),
                height: 18,
              ),
              const SizedBox(height: 18),
              Text('الاستلام والمستخلصات وإقفال العقود', style: TextStyle(fontWeight: FontWeight.w800, color: sem.muted, fontSize: 13)),
              const SizedBox(height: 8),
              for (final k in const [2, 3, 4, 5]) ...[
                Text(lifeDefs[k].name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5)),
                const SizedBox(height: 4),
                StackBar(
                  parts: [
                    for (final s in FormStatus.values) (s.label, scope.where((f) => f.life[k].status == s).length.toDouble(), sem.statusColor(s)),
                  ],
                  format: (v) => v.toStringAsFixed(0),
                  legend: false,
                  height: 12,
                ),
                const SizedBox(height: 10),
              ],
              const StatusLegend(),
            ]),
          );
          return wide
              ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(flex: 4, child: donut),
                  const SizedBox(width: 14),
                  Expanded(flex: 6, child: stack),
                ])
              : Column(children: [donut, const SizedBox(height: 14), stack]);
        }),
        const SizedBox(height: 14),
        SectionCard(
          title: 'المشاريع ومراحلها',
          icon: Icons.table_rows_outlined,
          subtitle: 'لكل مشروع مرحلته الحالية في دورة حياة العقد، والمخطط (الفاتح) مقابل الفعلي (الملوّن) من برنامجه المعتمد. اضغطه للتفاصيل.',
          trailing: _state.isEmpty ? null : TextButton(onPressed: () => setState(() => _state = ''), child: const Text('كل الحالات')),
          child: shown.isEmpty
              ? const EmptyState(title: 'لا مشاريع بهذه التصفية', icon: Icons.filter_alt_off_outlined)
              : Column(children: [
                  for (var k = 0; k < shown.length; k++) ...[
                    if (k > 0) Divider(height: 1, color: sem.rule),
                    _FollowRow(follow: shown[k]),
                  ],
                ]),
        ),
        if (lateItems.isNotEmpty) ...[
          const SizedBox(height: 14),
          SectionCard(
            title: 'البنود المتأخرة وحجم التأخير',
            icon: Icons.warning_amber_rounded,
            subtitle: 'الأكبر انحرافاً أولاً، وكل تأخير يُترجم تلقائياً خطراً زمنياً في سجل المخاطر.',
            child: Column(children: [
              for (final (f, c) in lateItems.take(12))
                _LateItemRow(follow: f, calc: c),
            ]),
          ),
        ],
      ], stepMs: 30),
    );
  }
}

class _FollowRow extends StatelessWidget {
  const _FollowRow({required this.follow});

  final ProjectFollow follow;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final sem = Sem.of(context);
    final f = follow;
    final t = f.track;
    final cur = f.current;
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => openProjectFollow(context, f.project.id),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(
              child: Text(pmProjectName(app, f.project.id),
                  maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, height: 1.35)),
            ),
            const SizedBox(width: 8),
            ToneBadge(projectStateLabels[f.state]!, color: projectStateColor(sem, f.state)),
          ]),
          const SizedBox(height: 6),
          Wrap(spacing: 12, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
            LifecycleTimeline(phases: f.life, compact: true),
            Row(mainAxisSize: MainAxisSize.min, children: [
              Text('المرحلة الحالية: ', style: TextStyle(color: sem.muted, fontSize: 12.5)),
              Text(cur.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5)),
              const SizedBox(width: 6),
              StatusChip(cur.status, small: true),
            ]),
            if (f.project.company.isNotEmpty) Text(f.project.company, style: TextStyle(color: sem.muted, fontSize: 12.5)),
            if ((f.schedule?.location ?? '').isNotEmpty) Text(f.schedule!.location, style: TextStyle(color: sem.muted, fontSize: 12.5)),
          ]),
          if (t != null) ...[
            const SizedBox(height: 8),
            PlanActualBar(planned: t.planned ?? 0, actual: t.actual ?? 0, color: perfColor(context, t.perf)),
            const SizedBox(height: 5),
            Wrap(spacing: 14, runSpacing: 2, children: [
              Text('الفعلي ${pctOrDash((t.actual ?? 0) / 100, digits: 1)}',
                  style: TextStyle(fontWeight: FontWeight.w800, color: perfColor(context, t.perf), fontSize: 12.5)),
              Text('المخطط ${pctOrDash((t.planned ?? 0) / 100, digits: 1)}', style: TextStyle(color: sem.muted, fontSize: 12.5)),
              Text(varText(t.variance), style: TextStyle(color: (t.variance ?? 0) < 0 ? sem.danger : sem.muted, fontSize: 12.5)),
              Text('SPI ${spiText(t.spi)}', style: TextStyle(color: sem.muted, fontSize: 12.5)),
              Text('${itemsText(t.items.length)}${t.lateItems.isEmpty ? '' : ' · متأخرة ${t.lateItems.length}'}',
                  style: TextStyle(color: t.lateItems.isEmpty ? sem.muted : sem.danger, fontSize: 12.5)),
            ]),
          ] else
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                  app.planOf(f.project.id) == null ? 'لا برنامج زمني معتمد بعد (تعدّه الشؤون الفنية)' : 'البرنامج الزمني مسودة لدى الشؤون الفنية',
                  style: TextStyle(color: sem.muted, fontSize: 12.5)),
            ),
        ]),
      ),
    );
  }
}

class _LateItemRow extends StatelessWidget {
  const _LateItemRow({required this.follow, required this.calc});

  final ProjectFollow follow;
  final ItemCalc calc;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final sem = Sem.of(context);
    final c = calc;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      onTap: () => openProjectFollow(context, follow.project.id),
      title: Text([if (c.item.code.isNotEmpty) c.item.code, c.item.title].join(' '), maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: Text('${pmProjectName(app, follow.project.id)} · ${varText(c.variance)} · ${daysVarText(c.daysVariance)}'
          '${c.overdueDays == null ? '' : ' · تجاوز النهاية بـ${daysWord(c.overdueDays!)}'}'),
      trailing: Text(daysWord(c.behindDays), style: TextStyle(color: sem.danger, fontWeight: FontWeight.w800)),
    );
  }
}

Future<void> openProjectFollow(BuildContext context, String projectId) =>
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ProjectFollowPage(projectId: projectId)));

// =====================================================================
// بنود العقود: كل البنود من مقايسات العقود المعتمدة وإضافاتها، بحالة تنفيذ كل بند
// =====================================================================
class ContractItemsPage extends StatefulWidget {
  const ContractItemsPage({super.key});

  @override
  State<ContractItemsPage> createState() => _ContractItemsPageState();
}

class _ContractItemsPageState extends State<ContractItemsPage> {
  String _project = '';
  String _status = '';
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    if (!app.v14Ready) return const ScheduleNotReady(title: 'بنود العقود');
    if (!app.v15Ready) return const PlanNotReady(title: 'بنود العقود');
    final sem = Sem.of(context);
    final narrow = MediaQuery.sizeOf(context).width < 700;
    final projects = app.projects.where((p) => app.itemsOf(p.id).isNotEmpty || app.approvedBoqsOf(p.id).isNotEmpty).toList();
    bool match(PmItem i, ScheduleTrack t) {
      if (_q.isNotEmpty && !pmMatch(_q, [i.title, i.code, i.unit])) return false;
      if (_status.isEmpty) return true;
      if (_status == 'late') return t.calcOf(i.id)?.isLate ?? false;
      return itemStatus(i).name == _status;
    }

    final groups = <(Project, ScheduleTrack, List<PmItem>)>[];
    final counts = <String, int>{};
    for (final p in projects) {
      if (_project.isNotEmpty && p.id != _project) continue;
      final t = app.trackOf(p);
      for (final i in t.allItems) {
        counts[itemStatus(i).name] = (counts[itemStatus(i).name] ?? 0) + 1;
        if (t.calcOf(i.id)?.isLate ?? false) counts['late'] = (counts['late'] ?? 0) + 1;
      }
      final list = t.allItems.where((i) => match(i, t)).toList();
      if (list.isNotEmpty || (_status.isEmpty && _q.isEmpty)) groups.add((p, t, list));
    }

    return PageBody(
      maxWidth: 1300,
      onRefresh: app.loadAll,
      children: [
        PageHeader(
          title: 'بنود العقود',
          subtitle: 'بنود كل عقد هي بنود مقايسته المعتمدة من الشؤون الفنية وما أُضيف إليها مما ليس فيها، مرتبطة بعقدها وبرنامجه الزمني. '
              'من المشروع إلى العقد إلى بنوده وحالة تنفيذ كل بند.',
          icon: Icons.format_list_numbered_rounded,
        ),
        Wrap(spacing: 10, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.center, children: [
          SizedBox(
            width: narrow ? double.infinity : 320,
            child: SelectField(
              label: 'العقد',
              value: _project,
              items: [('', 'كل العقود'), for (final p in projects) (p.id, pmProjectName(app, p.id))],
              onChanged: (v) => setState(() => _project = v),
            ),
          ),
          SizedBox(
            width: narrow ? double.infinity : 280,
            child: TextField(
              decoration: fieldDeco('بحث في وصف البند أو رقمه', prefixIcon: const Icon(Icons.search_rounded)),
              onChanged: (v) => setState(() => _q = v.trim()),
            ),
          ),
        ]),
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 8, children: [
          ChoiceChip(label: const Text('الكل'), selected: _status.isEmpty, onSelected: (_) => setState(() => _status = '')),
          for (final s in FormStatus.values)
            ChoiceChip(
              avatar: CircleAvatar(backgroundColor: sem.statusColor(s), radius: 6),
              label: Text('${s.label} ${counts[s.name] ?? 0}'),
              selected: _status == s.name,
              onSelected: (_) => setState(() => _status = s.name),
            ),
          ChoiceChip(
            avatar: Icon(Icons.warning_amber_rounded, size: 16, color: sem.danger),
            label: Text('متأخرة ${counts['late'] ?? 0}'),
            selected: _status == 'late',
            onSelected: (_) => setState(() => _status = 'late'),
          ),
        ]),
        const SizedBox(height: 12),
        if (groups.isEmpty)
          const SectionCard(
            title: 'البنود',
            child: EmptyState(
              title: 'لا بنود بعد',
              message: 'تُعتمد مقايسة العقد ثم تولّد الشؤون الفنية برنامجه الزمني منها، فتظهر بنوده هنا للمتابعة.',
              icon: Icons.format_list_numbered_rounded,
            ),
          )
        else
          for (final (p, t, list) in groups) ...[
            _ContractItemsCard(project: p, track: t, items: list),
            const SizedBox(height: 12),
          ],
      ],
    );
  }
}

class _ContractItemsCard extends StatelessWidget {
  const _ContractItemsCard({required this.project, required this.track, required this.items});

  final Project project;
  final ScheduleTrack track;
  final List<PmItem> items;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final sem = Sem.of(context);
    final plan = app.planOf(project.id);
    final boqs = app.approvedBoqsOf(project.id);
    final phaseName = {for (final ph in track.phases) ph.id: ph.name};
    return SectionCard(
      title: pmProjectName(app, project.id),
      icon: Icons.description_outlined,
      subtitle: [
        if (boqs.isNotEmpty) 'مقايسة معتمدة: ${boqs.map((b) => b.title).join('، ')}',
        plan == null ? 'لا برنامج زمني بعد' : (plan.approved ? 'البرنامج معتمد (الإصدار ${plan.version})' : 'البرنامج مسودة لدى الشؤون الفنية'),
        if (track.actual != null && plan?.approved == true) 'الإنجاز ${pctOrDash(track.actual! / 100, digits: 1)}',
      ].join(' · '),
      trailing: TextButton(onPressed: () => openProjectFollow(context, project.id), child: const Text('متابعة العقد')),
      child: items.isEmpty
          ? Text(plan == null ? 'تولّد الشؤون الفنية البرنامج من المقايسة المعتمدة.' : 'لا بنود بهذه التصفية.', style: TextStyle(color: sem.muted))
          : Column(children: [
              for (var k = 0; k < items.length; k++) ...[
                if (k > 0) Divider(height: 1, color: sem.rule),
                _ItemTrackRow(
                  item: items[k],
                  calc: plan?.approved == true ? track.calcOf(items[k].id) : null,
                  phase: phaseName[items[k].phaseId],
                  onTap: () => showItemFollowSheet(context, project, track, items[k]),
                ),
              ],
            ]),
    );
  }
}

/// سطر بند للمتابعة: الرقم والوصف والوحدة والكمية، والمخطط والفعلي، والحالة بلونها الموحّد، والتأخير.
class _ItemTrackRow extends StatelessWidget {
  const _ItemTrackRow({required this.item, required this.calc, this.phase, this.onTap});

  final PmItem item;
  final ItemCalc? calc;
  final String? phase;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final sem = Sem.of(context);
    final i = item;
    final c = calc;
    final st = itemStatus(i);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 2),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(width: 4, height: 38, margin: const EdgeInsetsDirectional.only(end: 10), decoration: BoxDecoration(color: sem.statusColor(st), borderRadius: BorderRadius.circular(2))),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text([if (i.code.isNotEmpty) i.code, i.title].join('  '),
                  maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w600, height: 1.35, color: i.notApplicable ? sem.muted : null)),
              const SizedBox(height: 3),
              Wrap(spacing: 12, runSpacing: 2, children: [
                if (phase != null) Text(phase!, style: TextStyle(color: sem.muted, fontSize: 12)),
                if (i.qty != null || i.unit.isNotEmpty) Text('${i.qty == null ? '' : fmtQty(i.qty!)} ${i.unit}', style: TextStyle(color: sem.muted, fontSize: 12)),
                Text('${pmDay(i.plannedStart)} إلى ${pmDay(i.plannedEnd)}', style: TextStyle(color: sem.muted, fontSize: 12)),
                if (c != null) Text('المخطط ${c.planned.toStringAsFixed(0)}% · الفعلي ${c.actual.toStringAsFixed(0)}%', style: TextStyle(color: sem.muted, fontSize: 12)),
                if (c != null && c.isLate)
                  Text('متأخر ${daysWord(c.behindDays)}', style: TextStyle(color: sem.danger, fontSize: 12, fontWeight: FontWeight.w700)),
                if (i.source != 'boq') Text(itemSourceLabels[i.source] ?? '', style: TextStyle(color: Theme.of(context).colorScheme.primary, fontSize: 12)),
              ]),
            ]),
          ),
          const SizedBox(width: 8),
          StatusChip(st, small: true),
        ]),
      ),
    );
  }
}

/// تفاصيل بند ومتابعته.
Future<void> showItemFollowSheet(BuildContext context, Project p, ScheduleTrack t, PmItem i) {
  final app = AppScope.read(context);
  final c = t.calcOf(i.id);
  final plan = app.planOf(p.id);
  final dep = i.dependsOn == null ? null : t.allItems.where((x) => x.id == i.dependsOn).firstOrNull;
  final k = t.items.indexWhere((x) => x.id == i.id);
  return showPmSheet(
    context,
    code: i.code,
    title: i.title,
    badges: [
      StatusChip(itemStatus(i)),
      if (c != null) PerfBadge(c.status),
      if (c?.overdueDays != null) ToneBadge('تجاوز النهاية المخططة', color: Sem.of(context).danger),
    ],
    rows: [
      ('العقد', pmProjectName(app, p.id)),
      ('المرحلة', t.phases.where((x) => x.id == i.phaseId).firstOrNull?.name ?? ''),
      ('النوع', itemSourceLabels[i.source] ?? ''),
      ('الوحدة · الكمية', i.unit.isEmpty && i.qty == null ? '' : '${i.unit} · ${i.qty == null ? '—' : fmtQty(i.qty!)}'),
      ('البداية · النهاية المخططتان', '${pmDay(i.plannedStart)} إلى ${pmDay(i.plannedEnd)} (${daysWord(i.days)})'),
      ('يتبع البند', dep == null ? '' : [dep.code, dep.title].where((x) => x.isNotEmpty).join(' ')),
      ('الوزن', k < 0 ? '' : 'نصيبه ${t.shares[k].toStringAsFixed(1)}% من العقد'),
      if (c != null) ...[
        ('المخطط حتى تاريخ الإسناد', '${c.planned.toStringAsFixed(1)}%'),
        ('الإنجاز الفعلي', '${c.actual.toStringAsFixed(1)}%'),
        ('الانحراف', '${varText(c.variance)} · ${daysVarText(c.daysVariance)}'),
        ('الإنهاء المتوقع', c.actual >= 100 ? '' : pmDay(c.projectedEnd)),
      ],
      ('البداية · النهاية الفعليتان', i.actualStart == null && i.actualEnd == null ? '' : '${pmDay(i.actualStart)} · ${pmDay(i.actualEnd)}'),
      ('ملاحظات', i.notes),
      if (plan?.approved != true) ('الحالة', 'البرنامج غير معتمد بعد؛ يُسجَّل الإنجاز بعد اعتماده وإحالته إلى الإشراف'),
    ],
    actions: (sheet) => [
      if (app.canUpdateItemProgress(p))
        FilledButton.icon(
          onPressed: () {
            Navigator.of(sheet).pop();
            showTrackItemEditor(context, p, i);
          },
          icon: const Icon(Icons.trending_up_rounded),
          label: const Text('تحديث التنفيذ'),
        ),
      if (app.canEditItems(p))
        OutlinedButton.icon(
          onPressed: () {
            Navigator.of(sheet).pop();
            openPlanEditor(context, p.id);
          },
          icon: const Icon(Icons.event_note_outlined),
          label: const Text('إعداد البرنامج'),
        ),
    ],
  );
}

/// متابعة البند: نسبة الإنجاز والتاريخان الفعليان و«لا ينطبق» والملاحظات.
Future<void> showTrackItemEditor(BuildContext context, Project p, PmItem item) async {
  final app = AppScope.read(context);
  final cfg = app.pmConfig;
  final ok = await showPmForm(
    context,
    title: 'تحديث تنفيذ البند',
    note: 'الإنجاز تراكمي من بداية البند، والنهاية الفعلية تُسجَّل عند اكتماله (100%). '
        '«لا ينطبق» يُبقي البند في البرنامج ويخرجه من حساب الإنجاز. كل تحديث يُترجم فوراً إلى سجل المخاطر وSWOT.',
    sections: const [
      PmSection('التنفيذ', [
        PmField('progress', 'نسبة الإنجاز الفعلية (تراكمي)', PmKind.percent),
        PmField('actual_start', 'البداية الفعلية', PmKind.date),
        PmField('actual_end', 'النهاية الفعلية', PmKind.date, helper: 'عند اكتمال البند 100%'),
        PmField('not_applicable', 'لا ينطبق على هذا العقد', PmKind.toggle),
        PmField('notes', 'ملاحظات (مثل أسباب التأخير)', PmKind.multiline, max: 1000, full: true),
      ]),
    ],
    values: {
      'progress': item.progress / 100,
      'actual_start': item.actualStart,
      'actual_end': item.actualEnd,
      'not_applicable': item.notApplicable,
      'notes': item.notes,
    },
    preview: (v) {
      final pr = ((v['progress'] as double?) ?? 0) * 100;
      final c = ItemCalc(
          PmItem(id: '', projectId: p.id, title: '', plannedStart: item.plannedStart, plannedEnd: item.plannedEnd, progress: pr), cfg.refDay, cfg);
      return InfoBanner(
        text: 'حتى ${pmDay(c.ref)}: المخطط ${c.planned.toStringAsFixed(1)}% · الفعلي ${c.actual.toStringAsFixed(1)}% · ${varText(c.variance)}'
            '${c.status == 'done' || c.status == 'not_started' ? '' : ' (${daysVarText(c.daysVariance)})'} · ${perfLabels[c.status]}',
        level: c.status == 'critical' ? 'critical' : (c.status == 'slight' ? 'warning' : 'ok'),
      );
    },
    onSave: (d) async {
      await app.savePmItem(item.id, {
        'progress': d['progress'] == null ? 0 : ((d['progress'] as double) * 10000).round() / 100,
        'actual_start': d['actual_start'] ?? '',
        'actual_end': d['actual_end'] ?? '',
        'not_applicable': d['not_applicable'] == true,
        'notes': d['notes'] ?? '',
      });
    },
  );
  if (ok && context.mounted) showToast(context, 'حُفظ التنفيذ');
}

// =====================================================================
// متابعة تنفيذ عقد: دورة الحياة من اليمين، والمؤشرات، والمخطط الزمني، والبنود، والأثر في المخاطر وSWOT
// =====================================================================
class ProjectFollowPage extends StatelessWidget {
  const ProjectFollowPage({super.key, required this.projectId});

  final String projectId;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final p = app.project(projectId);
    if (p == null || !app.v15Ready) {
      return Scaffold(
        appBar: brandAppBar(context, title: const Text('متابعة التنفيذ')),
        body: p == null
            ? const EmptyState(title: 'العقد غير موجود', message: 'ربما حُذف أو دُمج في عقد آخر.', icon: Icons.search_off_rounded)
            : const PlanNotReady(title: 'متابعة التنفيذ'),
      );
    }
    final sem = Sem.of(context);
    final f = followOf(app, p);
    final plan = app.planOf(p.id);
    final t = f.track ?? app.trackOf(p);
    final approved = plan?.approved == true;
    final narrow = MediaQuery.sizeOf(context).width < 700;
    final risks = app.risks.where((r) => r.isAuto && r.projectId == p.id).toList()
      ..sort((a, b) => a.isClosed == b.isClosed ? b.score.compareTo(a.score) : (a.isClosed ? 1 : -1));
    final swot = app.swotFactors.where((x) => x.isAuto && x.projectId == p.id).toList();

    return Scaffold(
      appBar: brandAppBar(context, title: const Text('متابعة تنفيذ العقد'), actions: [
        if (t.calcs.isNotEmpty)
          IconButton(
            tooltip: 'تصدير البنود',
            icon: const Icon(Icons.ios_share_rounded),
            onPressed: () => showExportDialog(context, sourceId: 'risks:schedule', items: t.calcs, projectId: p.id, title: 'بنود العقد — ${p.name}'),
          ),
      ]),
      body: PageBody(maxWidth: 1250, onRefresh: app.loadAll, children: [
        PageHeader(
          title: p.name.isEmpty ? p.assignNo : p.name,
          subtitle: [
            if (p.assignNo.isNotEmpty) 'التكليف ${p.assignNo}',
            if (p.company.isNotEmpty) p.company,
            if ((f.schedule?.location ?? '').isNotEmpty) f.schedule!.location,
            plan == null ? 'لا برنامج زمني بعد' : (approved ? 'البرنامج المعتمد (الإصدار ${plan.version})' : 'البرنامج مسودة لدى الشؤون الفنية'),
            'تاريخ الإسناد ${pmDay(t.ref)}',
          ].join(' · '),
          icon: Icons.engineering_outlined,
          actions: [
            OutlinedButton.icon(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ProjectDetailPage(projectId: p.id))),
              icon: const Icon(Icons.description_outlined),
              label: const Text('ملف العقد ونماذجه'),
            ),
            if (app.canPreparePlan || plan != null)
              OutlinedButton.icon(
                onPressed: () => openPlanEditor(context, p.id),
                icon: const Icon(Icons.event_note_outlined),
                label: const Text('البرنامج الزمني'),
              ),
          ],
        ),
        SectionCard(
          title: 'دورة حياة العقد',
          icon: Icons.linear_scale_rounded,
          subtitle: 'من اليمين: أمر العمل ثم التنفيذ ثم الاستلام الابتدائي ثم المستخلصات ثم الاستلام النهائي ثم إقفال العقد. اضغط المرحلة لتفاصيلها.',
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            LifecycleTimeline(phases: f.life, onTap: (i) => showLifePhaseSheet(context, p, f, i)),
            const SizedBox(height: 12),
            const StatusLegend(),
          ]),
        ),
        const SizedBox(height: 14),
        if (!approved)
          InfoBanner(
            text: plan == null
                ? 'لا برنامج زمني لهذا العقد بعد: تعدّه الشؤون الفنية من المقايسة المعتمدة وتعتمده، ثم يتابعه الإشراف هنا.'
                : 'البرنامج الزمني مسودة لدى الشؤون الفنية؛ يبدأ تسجيل الإنجاز بعد اعتماده وإحالته إلى الإشراف.',
            level: 'warning',
          )
        else ...[
          ResponsiveGrid(minItemWidth: narrow ? 150 : 185, spacing: 10, children: [
            StatCard(
                label: 'الإنجاز الفعلي',
                value: pctOrDash((t.actual ?? 0) / 100, digits: 1),
                sub: 'موزون بقيم البنود',
                icon: Icons.trending_up_rounded,
                color: perfColor(context, t.perf)),
            StatCard(
                label: 'المخطط حتى الإسناد',
                value: pctOrDash((t.planned ?? 0) / 100, digits: 1),
                sub: '${varText(t.variance)} · SPI ${spiText(t.spi)}',
                icon: Icons.flag_outlined),
            StatCard(
                label: 'حالة العقد',
                value: perfLabels[t.perf] ?? t.perf,
                sub: t.daysVariance == null ? null : daysVarText(t.daysVariance!.toDouble()),
                icon: Icons.speed_rounded,
                color: perfColor(context, t.perf)),
            StatCard(
                label: 'البنود',
                value: '${t.allItems.length}',
                sub: 'تم ${t.doneItems} · قيد التنفيذ ${t.runningItems} · لم يتم ${t.notStartedItems}',
                icon: Icons.list_alt_rounded),
            StatCard(
                label: 'المتأخرة',
                value: '${t.lateItems.length}',
                sub: 'تجاوزت نهايتها: ${t.overdueItems.length}',
                icon: Icons.warning_amber_rounded,
                color: t.lateItems.isEmpty ? sem.ok : sem.statusColor(FormStatus.todo)),
            StatCard(
                label: 'الإنهاء المتوقع',
                value: t.projectedEnd == null ? '—' : pmDay(t.projectedEnd),
                sub: t.forecastDelay == null || t.forecastDelay == 0
                    ? 'نهاية البرنامج ${pmDay(t.end)}'
                    : (t.forecastDelay! > 0 ? 'بعد النهاية بـ${daysWord(t.forecastDelay!)}' : 'قبل النهاية بـ${daysWord(-t.forecastDelay!)}'),
                icon: Icons.event_available_outlined,
                color: (t.forecastDelay ?? 0) > 0 ? sem.statusColor(FormStatus.todo) : ((t.forecastDelay ?? 0) < 0 ? sem.ok : null)),
          ]),
          const SizedBox(height: 14),
          SectionCard(
            title: 'المخطط الزمني المعتمد',
            icon: Icons.view_timeline_rounded,
            subtitle: 'من اليمين: الشريط الفاتح المدة المخططة والملوّن ما أُنجز منها، والخط العمودي تاريخ الإسناد، والأحمر تجاوز بند لم يكتمل.',
            child: PlanGantt(rows: ganttRows(context, t, onTap: (i) => showItemFollowSheet(context, p, t, i)), ref: t.ref),
          ),
        ],
        const SizedBox(height: 14),
        SectionCard(
          title: 'بنود العقد وحالة تنفيذها',
          icon: Icons.format_list_numbered_rounded,
          subtitle: app.canUpdateItemProgress(p) ? 'اضغط البند لتحديث إنجازه وتاريخيه الفعليين.' : null,
          child: t.allItems.isEmpty
              ? Text('لا بنود بعد.', style: TextStyle(color: sem.muted))
              : Column(children: [
                  for (var k = 0; k < t.allItems.length; k++) ...[
                    if (k > 0) Divider(height: 1, color: sem.rule),
                    _ItemTrackRow(
                      item: t.allItems[k],
                      calc: approved ? t.calcOf(t.allItems[k].id) : null,
                      phase: t.phases.where((x) => x.id == t.allItems[k].phaseId).firstOrNull?.name,
                      onTap: () => showItemFollowSheet(context, p, t, t.allItems[k]),
                    ),
                  ],
                ]),
        ),
        if (app.v16Ready && (risks.isNotEmpty || swot.isNotEmpty)) ...[
          const SizedBox(height: 14),
          SectionCard(
            title: 'الأثر في سجل المخاطر وتحليل SWOT',
            icon: Icons.insights_rounded,
            subtitle: 'تترجم المنظومة التنفيذ تلقائياً: كل بند متأخر خطر زمني، والعقد المتقدم قوة وفرصة، والمتأخر ضعف وتهديد.',
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              for (final x in swot) _SwotImpactRow(factor: x),
              if (swot.isNotEmpty && risks.isNotEmpty) Divider(height: 18, color: sem.rule),
              for (final r in risks.take(12)) _AutoRiskRow(risk: r),
            ]),
          ),
        ],
      ]),
    );
  }
}

class _SwotImpactRow extends StatelessWidget {
  const _SwotImpactRow({required this.factor});

  final SwotFactor factor;

  @override
  Widget build(BuildContext context) {
    final sem = Sem.of(context);
    final positive = factor.kind == 'S' || factor.kind == 'O';
    final kindName = switch (factor.kind) { 'S' => 'قوة', 'W' => 'ضعف', 'O' => 'فرصة', _ => 'تهديد' };
    final c = positive ? sem.statusColor(FormStatus.done) : sem.statusColor(FormStatus.todo);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(positive ? Icons.trending_up_rounded : Icons.trending_down_rounded, color: c),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${factor.code} · $kindName', style: TextStyle(color: c, fontWeight: FontWeight.w800, fontSize: 12.5)),
            Text(factor.factor, style: const TextStyle(fontWeight: FontWeight.w600, height: 1.35)),
            Text(factor.impact, style: TextStyle(color: sem.muted, fontSize: 12.5, height: 1.35)),
          ]),
        ),
        ToneBadge(positive ? 'أثر إيجابي' : 'أثر سلبي', color: c),
      ]),
    );
  }
}

class _AutoRiskRow extends StatelessWidget {
  const _AutoRiskRow({required this.risk});

  final Risk risk;

  @override
  Widget build(BuildContext context) {
    final sem = Sem.of(context);
    final r = risk;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(Icons.report_gmailerrorred_rounded, color: r.isClosed ? sem.muted : sem.danger),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${r.code} · الدرجة ${r.score}${r.timeImpactDays == null ? '' : ' · الأثر الزمني ${daysWord(r.timeImpactDays!)}'}',
                style: TextStyle(color: r.isClosed ? sem.muted : sem.danger, fontWeight: FontWeight.w800, fontSize: 12.5)),
            Text(r.description, style: const TextStyle(fontWeight: FontWeight.w600, height: 1.35)),
            Text(r.effect, style: TextStyle(color: sem.muted, fontSize: 12.5, height: 1.35)),
          ]),
        ),
        StatusChip(r.isClosed ? FormStatus.done : FormStatus.todo, label: r.isClosed ? 'مغلق' : 'قائم', small: true, soft: true),
      ]),
    );
  }
}

/// تفاصيل مرحلة من دورة حياة العقد وبياناتها ومستنداتها المرتبطة.
Future<void> showLifePhaseSheet(BuildContext context, Project p, ProjectFollow f, int index) {
  final app = AppScope.read(context);
  final sem = Sem.of(context);
  final ph = f.life[index];
  final xs = app.extractsOf(p.id);
  final reports = app.docs.reportsOfProject(p.id);
  final docs = app.docs.itemsOfProject(p.id);
  return showPmSheet(
    context,
    code: 'المرحلة ${index + 1} من ${f.life.length}',
    title: ph.name,
    badges: [StatusChip(ph.status), if (ph.late) StatusChip(FormStatus.todo, label: 'متأخر عن البرنامج', soft: true)],
    rows: [
      ('النسبة', ph.pct == null ? 'لا تنطبق' : '${ph.pct!.toStringAsFixed(1)}%'),
      ('البداية · النهاية', ph.start == null && ph.end == null ? 'لم تُسجَّل بعد' : '${pmDay(ph.start)} · ${pmDay(ph.end)}'),
      ('المخطط', ph.plannedStart == null ? '' : '${pmDay(ph.plannedStart)} إلى ${pmDay(ph.plannedEnd)}'),
      ('عن الحساب', ph.note),
      if (ph.def.key == 'execution') ...[
        ('التقارير اليومية للموقع', reports.isEmpty ? 'لا تقارير' : '${reports.length} تقريراً، آخرها ${pmDay(reports.first.reportDate)}'),
        ('المستندات الفنية للعقد', docs.isEmpty ? '' : '${docs.length} مستنداً (مقايسات ومراسلات وتصاميم)'),
      ],
    ],
    extra: [
      if (ph.forms.isNotEmpty) ...[
        Text('النماذج', style: TextStyle(color: sem.muted, fontSize: 12.5)),
        const SizedBox(height: 6),
        for (final x in ph.forms)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(children: [
              Text(x.def.key.toUpperCase(), style: TextStyle(color: sem.muted, fontWeight: FontWeight.w700, fontSize: 12)),
              const SizedBox(width: 8),
              Expanded(child: Text(x.def.name, style: const TextStyle(height: 1.35))),
              if (x.at != null && (x.status == FormStatus.done || x.status == FormStatus.wip))
                Text(pmDay(x.at), style: TextStyle(color: sem.muted, fontSize: 12)),
              const SizedBox(width: 8),
              StatusChip(x.status, small: true),
            ]),
          ),
        const SizedBox(height: 10),
      ],
      if (ph.def.key == 'extracts' && xs.isNotEmpty) ...[
        Text('المستخلصات', style: TextStyle(color: sem.muted, fontSize: 12.5)),
        const SizedBox(height: 6),
        for (final x in xs)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(children: [
              Text('${x.kind == 'final' ? 'ختامي' : 'جارٍ'} ${x.seq}', style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(width: 8),
              Expanded(child: Text('${fmtMoney(x.gross)} · ${pmDay(x.submittedOn ?? x.periodTo)}', style: TextStyle(color: sem.muted, fontSize: 12.5))),
              StatusChip(
                  switch (x.status) { 'paid' || 'approved' => FormStatus.done, 'rejected' => FormStatus.todo, _ => FormStatus.wip },
                  label: switch (x.status) { 'paid' => 'مدفوع', 'approved' => 'معتمد', 'submitted' => 'مقدّم', 'rejected' => 'مرفوض', _ => 'مسودة' },
                  small: true),
            ]),
          ),
        const SizedBox(height: 10),
      ],
    ],
    actions: (sheet) => [
      FilledButton.tonalIcon(
        onPressed: () {
          Navigator.of(sheet).pop();
          Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ProjectDetailPage(projectId: p.id)));
        },
        icon: const Icon(Icons.description_outlined),
        label: const Text('فتح ملف العقد'),
      ),
    ],
  );
}
