import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app_state.dart';
import '../models.dart';
import '../pm.dart';
import '../print/export_dialog.dart';
import '../schedule.dart';
import '../ui/motion.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';
import 'hub.dart' show sectionColor;
import 'pm_common.dart';
import 'pm_projects.dart' show showScheduleEditor;

// =====================================================================
// الجداول الزمنية لكل مشروع: لوحة المشاريع المتقدمة والمتأخرة، وصفحة جدول المشروع ببنوده
// (المخطط والفعلي والانحراف بالنقاط وبالأيام لكل بند، والنسبة الكلية الموزونة) ومخطط زمني.
// =====================================================================

String _pts(double? v) => v == null ? '—' : '${v >= 0 ? '+' : '−'}${v.abs().toStringAsFixed(1)}';
String _pct1(double? v) => v == null ? '—' : '${v.toStringAsFixed(1)}%';

/// الانحراف بالأيام نصاً: «متقدم 5 أيام» أو «متأخر 12 يوماً».
String daysVarText(double d) {
  final n = d.round();
  if (n == 0) return 'في موعده';
  return '${n > 0 ? 'متقدم' : 'متأخر'} ${_daysWord(n.abs())}';
}

String _daysWord(int n) => switch (n) {
      1 => 'يوماً واحداً',
      2 => 'يومين',
      <= 10 => '$n أيام',
      _ => '$n يوماً',
    };

const List<(String, String)> _filters = [
  ('', 'الكل'),
  ('ahead', 'متقدمة'),
  ('on_track', 'ضمن المخطط'),
  ('late', 'متأخرة'),
  ('done', 'منجزة'),
  ('not_started', 'لم تبدأ'),
];

/// ملاحظة: القاعدة لم تُحدَّث بالترحيلات 27–29 بعد.
class ScheduleNotReady extends StatelessWidget {
  const ScheduleNotReady({super.key, required this.title});

  final String title;

  @override
  Widget build(BuildContext context) => PageBody(children: [
        PageHeader(title: title, icon: Icons.date_range_outlined),
        const InfoBanner(
          text: 'تعمل هذه الصفحة بعد تحديث قاعدة البيانات بالترحيلات 27 و28 و29 (لائحة الأسعار والمقايسات وبنود الجدول الزمني).',
          level: 'warning',
        ),
      ]);
}

// =====================================================================
// لوحة الجداول الزمنية
// =====================================================================
class ScheduleDashboardPage extends StatefulWidget {
  const ScheduleDashboardPage({super.key});

  @override
  State<ScheduleDashboardPage> createState() => _ScheduleDashboardPageState();
}

class _ScheduleDashboardPageState extends State<ScheduleDashboardPage> {
  String _filter = '';

  bool _match(ScheduleTrack t) => switch (_filter) {
        '' => true,
        'late' => t.isLate,
        _ => t.perf == _filter,
      };

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    if (!app.v14Ready) return const ScheduleNotReady(title: 'الجداول الزمنية');
    final s = app.schedule;
    final cfg = app.pmConfig;
    final sem = Sem.of(context);
    final accent = sectionColor(context, 'risks');
    final narrow = MediaQuery.sizeOf(context).width < 700;
    final pc = s.perfCounts;
    final tracks = s.tracks.values.where(_match).toList();
    final lateItems = s.lateItems;
    final overdue = s.tracks.values.fold<int>(0, (a, t) => a + t.overdueItems.length);
    final itemsCount = s.tracks.values.fold<int>(0, (a, t) => a + t.items.length);
    final without = app.projects.where((p) => !s.tracks.containsKey(p.id)).length;

    return PageBody(
      maxWidth: 1300,
      onRefresh: app.loadAll,
      children: staggered([
        PageHeader(
          title: 'الجداول الزمنية والانحرافات',
          subtitle: 'من بنود الجدول الزمني لكل مشروع · تاريخ الإسناد ${pmDay(s.ref)}${cfg.refDate == null ? '' : ' (مثبّت في الإعدادات)'}',
          icon: Icons.date_range_outlined,
          actions: [
            FilledButton.icon(
              onPressed: () => _openPicker(context, app),
              icon: const Icon(Icons.edit_calendar_outlined),
              label: const Text('جدول مشروع'),
            ),
          ],
        ),
        ResponsiveGrid(minItemWidth: narrow ? 150 : 200, spacing: 10, children: [
          StatCard(
              label: 'مشاريع لها جدول زمني',
              value: '${s.tracks.length}',
              sub: 'البنود: $itemsCount · بلا جدول: $without',
              icon: Icons.view_timeline_rounded,
              color: accent),
          StatCard(
              label: 'مشاريع متقدمة',
              value: '${pc['ahead'] ?? 0}',
              sub: 'ضمن المخطط: ${pc['on_track'] ?? 0}',
              icon: Icons.trending_up_rounded,
              color: perfColor(context, 'ahead'),
              onTap: () => setState(() => _filter = 'ahead')),
          StatCard(
              label: 'مشاريع متأخرة',
              value: '${s.lateProjects}',
              sub: 'منها حرج: ${pc['critical'] ?? 0}',
              icon: Icons.running_with_errors_rounded,
              color: s.lateProjects > 0 ? sem.danger : sem.ok,
              onTap: () => setState(() => _filter = 'late')),
          StatCard(
              label: 'مشاريع منجزة',
              value: '${pc['done'] ?? 0}',
              sub: 'لم تبدأ: ${pc['not_started'] ?? 0}',
              icon: Icons.verified_outlined,
              color: sem.ok,
              onTap: () => setState(() => _filter = 'done')),
          StatCard(
              label: 'بنود متأخرة',
              value: '${lateItems.length}',
              sub: 'تجاوزت نهايتها المخططة: $overdue',
              icon: Icons.hourglass_bottom_rounded,
              color: lateItems.isNotEmpty ? sem.danger : null),
          StatCard(
              label: 'متوسط الإنجاز الفعلي',
              value: _pct1(s.avgActual),
              sub: 'المخطط: ${_pct1(s.avgPlanned)}',
              icon: Icons.donut_large_rounded),
        ]),
        const SizedBox(height: 14),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final f in _filters)
            ChoiceChip(
              label: Text(f.$1 == ''
                  ? '${f.$2} ${s.tracks.length}'
                  : '${f.$2} ${f.$1 == 'late' ? s.lateProjects : (pc[f.$1] ?? 0)}'),
              selected: _filter == f.$1,
              onSelected: (_) => setState(() => _filter = f.$1),
            ),
        ]),
        const SizedBox(height: 12),
        SectionCard(
          title: 'المشاريع',
          icon: Icons.table_rows_outlined,
          subtitle: 'الشريط الفاتح المخطط حتى تاريخ الإسناد، والملوّن الإنجاز الفعلي الموزون. اضغط المشروع لفتح جدوله وبنوده.',
          child: tracks.isEmpty
              ? EmptyState(
                  title: s.tracks.isEmpty ? 'لا جداول زمنية بعد' : 'لا مشاريع بهذا التصنيف',
                  message: s.tracks.isEmpty
                      ? 'افتح «جدول مشروع» واختر العقد، ثم أنشئ البنود من أعمال العقد أو أضفها يدوياً بتواريخها المخططة.'
                      : null,
                  icon: Icons.date_range_outlined,
                )
              : Column(children: [
                  for (final t in tracks) _TrackRow(track: t),
                ]),
        ),
        if (lateItems.isNotEmpty) ...[
          const SizedBox(height: 14),
          SectionCard(
            title: 'البنود المتأخرة',
            icon: Icons.warning_amber_rounded,
            subtitle: 'الأكبر انحرافاً أولاً. الانحراف بالنقاط = الفعلي − المخطط، وبالأيام = الفعلي × المدة − الأيام المنقضية.',
            child: Column(children: [
              for (final (t, c) in lateItems.take(20))
                _ItemRow(
                  calc: c,
                  share: null,
                  projectName: pmProjectName(app, t.project.id),
                  onTap: () => openProjectSchedule(context, t.project.id),
                ),
              if (lateItems.length > 20)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text('و${lateItems.length - 20} بنداً آخر — صدّرها كلها من زر التصدير أعلى الصفحة.',
                      style: TextStyle(color: sem.muted, fontSize: 12.5)),
                ),
            ]),
          ),
        ],
      ], stepMs: 35),
    );
  }

  Future<void> _openPicker(BuildContext context, AppState app) async {
    final id = await pickScheduleProject(context, app);
    if (id != null && context.mounted) openProjectSchedule(context, id);
  }
}

/// يفتح صفحة الجدول الزمني لعقد.
Future<void> openProjectSchedule(BuildContext context, String projectId) =>
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ProjectSchedulePage(projectId: projectId)));

/// اختيار عقد (بحث بالاسم أو الرقم)، والعقود التي لها جدول أولاً.
Future<String?> pickScheduleProject(BuildContext context, AppState app) {
  final s = app.schedule;
  final all = [...app.projects]..sort((a, b) {
      final x = s.tracks.containsKey(a.id) ? 0 : 1, y = s.tracks.containsKey(b.id) ? 0 : 1;
      return x != y ? x.compareTo(y) : a.sortOrder.compareTo(b.sortOrder);
    });
  var q = '';
  return showDialog<String>(
    context: context,
    builder: (ctx) => StatefulBuilder(builder: (ctx, setLocal) {
      final sem = Sem.of(ctx);
      final list = all.where((p) => pmMatch(q, [p.name, p.assignNo, p.contractNo, p.company])).toList();
      return AlertDialog(
        title: const Text('اختر العقد'),
        content: SizedBox(
          width: 520,
          height: 460,
          child: Column(children: [
            TextField(
              autofocus: true,
              decoration: fieldDeco('بحث بالاسم أو رقم التكليف أو العقد', prefixIcon: const Icon(Icons.search_rounded)),
              onChanged: (v) => setLocal(() => q = v.trim()),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.separated(
                itemCount: list.length,
                separatorBuilder: (_, __) => Divider(height: 1, color: sem.rule),
                itemBuilder: (_, i) {
                  final p = list[i];
                  final t = s.tracks[p.id];
                  return ListTile(
                    dense: true,
                    title: Text(p.name.isEmpty ? p.assignNo : p.name, maxLines: 2, overflow: TextOverflow.ellipsis),
                    subtitle: Text(
                        [if (p.assignNo.isNotEmpty) p.assignNo, if (t != null) '${t.items.length} بنداً · ${perfLabels[t.perf]}' else 'بلا جدول']
                            .join(' · ')),
                    trailing: t == null ? null : PerfBadge(t.perf),
                    onTap: () => Navigator.of(ctx).pop(p.id),
                  );
                },
              ),
            ),
          ]),
        ),
        actions: [TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('إلغاء'))],
      );
    }),
  );
}

/// شريطا المخطط (فاتح) والفعلي (ملوّن) على مقياس 0–100.
class PlanActualBar extends StatelessWidget {
  const PlanActualBar({super.key, required this.planned, required this.actual, required this.color, this.height = 10});

  final double planned;
  final double actual;
  final Color color;
  final double height;

  @override
  Widget build(BuildContext context) {
    final sem = Sem.of(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(height),
      child: SizedBox(
        height: height,
        child: LayoutBuilder(builder: (context, c) {
          final w = c.maxWidth;
          return Stack(children: [
            Container(color: sem.todoSoft),
            PositionedDirectional(start: 0, top: 0, bottom: 0, width: w * (planned / 100).clamp(0, 1), child: Container(color: sem.muted.withValues(alpha: 0.28))),
            PositionedDirectional(
              start: 0,
              top: height * 0.22,
              bottom: height * 0.22,
              width: w * (actual / 100).clamp(0, 1),
              child: Container(decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(height))),
            ),
          ]);
        }),
      ),
    );
  }
}

class _TrackRow extends StatelessWidget {
  const _TrackRow({required this.track});

  final ScheduleTrack track;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final sem = Sem.of(context);
    final t = track;
    final color = perfColor(context, t.perf);
    final late = t.lateItems.length;
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => openProjectSchedule(context, t.project.id),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(
              child: Text(pmProjectName(app, t.project.id),
                  maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, height: 1.35)),
            ),
            const SizedBox(width: 8),
            PerfBadge(t.perf),
          ]),
          const SizedBox(height: 8),
          PlanActualBar(planned: t.planned ?? 0, actual: t.actual ?? 0, color: color),
          const SizedBox(height: 6),
          Wrap(spacing: 14, runSpacing: 2, children: [
            Text('الفعلي ${_pct1(t.actual)}', style: TextStyle(fontWeight: FontWeight.w800, color: color, fontSize: 12.5)),
            Text('المخطط ${_pct1(t.planned)}', style: TextStyle(color: sem.muted, fontSize: 12.5)),
            Text('الانحراف ${_pts(t.variance)} نقطة', style: TextStyle(color: (t.variance ?? 0) < 0 ? sem.danger : sem.muted, fontSize: 12.5)),
            Text('SPI ${spiText(t.spi)}', style: TextStyle(color: sem.muted, fontSize: 12.5)),
            Text('البنود ${t.items.length}${late > 0 ? ' · متأخرة $late' : ''}',
                style: TextStyle(color: late > 0 ? sem.danger : sem.muted, fontSize: 12.5)),
            Text('${pmDay(t.start)} إلى ${pmDay(t.end)}', style: TextStyle(color: sem.muted, fontSize: 12.5)),
          ]),
        ]),
      ),
    );
  }
}

/// سطر بند: اسمه وحالته، وشريط المخطط والفعلي، والانحراف بالنقاط وبالأيام.
class _ItemRow extends StatelessWidget {
  const _ItemRow({required this.calc, required this.share, this.projectName, this.onTap});

  final ItemCalc calc;
  final double? share;
  final String? projectName;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final sem = Sem.of(context);
    final c = calc;
    final i = c.item;
    final color = perfColor(context, c.status);
    final over = c.overdueDays;
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (projectName != null)
            Text(projectName!, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: sem.muted, fontSize: 12)),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (i.code.isNotEmpty) ...[
              Text(i.code, style: TextStyle(color: sem.muted, fontWeight: FontWeight.w800, fontSize: 12.5)),
              const SizedBox(width: 8),
            ],
            Expanded(child: Text(i.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, height: 1.35))),
            const SizedBox(width: 8),
            PerfBadge(c.status),
          ]),
          const SizedBox(height: 8),
          PlanActualBar(planned: c.planned, actual: c.actual, color: color, height: 9),
          const SizedBox(height: 6),
          Wrap(spacing: 14, runSpacing: 2, children: [
            Text('الفعلي ${_pct1(c.actual)}', style: TextStyle(fontWeight: FontWeight.w800, color: color, fontSize: 12.5)),
            Text('المخطط ${_pct1(c.planned)}', style: TextStyle(color: sem.muted, fontSize: 12.5)),
            Text('الانحراف ${_pts(c.variance)} نقطة', style: TextStyle(color: c.variance < 0 ? sem.danger : sem.muted, fontSize: 12.5)),
            if (c.status != 'done' && c.status != 'not_started')
              Text(daysVarText(c.daysVariance), style: TextStyle(color: c.daysVariance < -0.5 ? sem.danger : sem.muted, fontSize: 12.5)),
            if (over != null) Text('تجاوز النهاية المخططة بـ${_daysWord(over)}', style: TextStyle(color: sem.danger, fontSize: 12.5)),
            Text('${pmDay(i.plannedStart)} إلى ${pmDay(i.plannedEnd)} · ${_daysWord(c.duration)}', style: TextStyle(color: sem.muted, fontSize: 12.5)),
            if (share != null) Text('الوزن ${share!.toStringAsFixed(1)}%', style: TextStyle(color: sem.muted, fontSize: 12.5)),
          ]),
        ]),
      ),
    );
  }
}

// =====================================================================
// جدول مشروع: البنود والمخطط الزمني والنسبة الكلية
// =====================================================================
class ProjectSchedulePage extends StatelessWidget {
  const ProjectSchedulePage({super.key, required this.projectId});

  final String projectId;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final p = app.project(projectId);
    if (p == null || !app.v14Ready) {
      return Scaffold(
        appBar: brandAppBar(context, title: const Text('الجدول الزمني')),
        body: EmptyState(
          title: p == null ? 'العقد غير موجود' : 'قاعدة البيانات لم تُحدَّث بعد',
          message: p == null ? 'ربما حُذف أو دُمج في عقد آخر.' : 'تعمل الصفحة بعد الترحيل 29.',
          icon: Icons.search_off_rounded,
        ),
      );
    }
    final sem = Sem.of(context);
    final track = app.schedule.track(p.id) ?? ScheduleTrack(p, const [], app.pmConfig.refDay, app.pmConfig);
    final canItems = app.canEditItems(p);
    final canProgress = app.canUpdateItemProgress(p);
    final pmSchedule = app.schedules[p.id];
    final hasDates = pmSchedule?.startDate != null && pmSchedule?.endDate != null;
    final freeWorks = app.worksOf(p.id).where((w) => !track.items.any((i) => i.workId == w.id)).length;
    final narrow = MediaQuery.sizeOf(context).width < 700;

    return Scaffold(
      appBar: brandAppBar(context, title: const Text('الجدول الزمني للمشروع'), actions: [
        if (track.items.isNotEmpty)
          IconButton(
            tooltip: 'تصدير البنود',
            icon: const Icon(Icons.ios_share_rounded),
            onPressed: () => showExportDialog(context,
                sourceId: 'risks:schedule', items: track.calcs, projectId: p.id, title: 'الجدول الزمني — ${p.name}'),
          ),
      ]),
      body: PageBody(maxWidth: 1200, onRefresh: app.loadAll, children: [
        PageHeader(
          title: p.name.isEmpty ? p.assignNo : p.name,
          subtitle: [
            if (p.assignNo.isNotEmpty) 'التكليف ${p.assignNo}',
            if (pmSchedule?.startDate != null) 'البرنامج الزمني ${pmDay(pmSchedule!.startDate)} إلى ${pmDay(pmSchedule.endDate)}',
            'تاريخ الإسناد ${pmDay(track.ref)}',
          ].join(' · '),
          icon: Icons.date_range_outlined,
          actions: [
            if (canItems)
              FilledButton.icon(
                onPressed: () => showPmItemEditor(context, p, null),
                icon: const Icon(Icons.add_rounded),
                label: const Text('بند جديد'),
              ),
            if (canItems && freeWorks > 0)
              OutlinedButton.icon(
                onPressed: () => _fromWorks(context, app, p, hasDates),
                icon: const Icon(Icons.playlist_add_rounded),
                label: Text('من أعمال العقد ($freeWorks)'),
              ),
            if (canItems && track.items.length > 1)
              OutlinedButton.icon(
                onPressed: () => _reorder(context, app, p, track),
                icon: const Icon(Icons.swap_vert_rounded),
                label: const Text('ترتيب البنود'),
              ),
            if (app.canEditPm && track.items.isNotEmpty)
              OutlinedButton.icon(
                onPressed: () => _record(context, app, track),
                icon: const Icon(Icons.add_chart_rounded),
                label: const Text('تسجيل في التقدم الدوري'),
              ),
          ],
        ),
        if (track.items.isEmpty) ...[
          if (!hasDates && canItems)
            InfoBanner(
              text: 'سجّل تاريخي بداية العقد ونهايته في البرنامج الزمني لتُنشأ البنود من أعمال العقد بهما، أو أضف البنود يدوياً بتواريخها.',
              level: 'info',
              action: TextButton(onPressed: () => showScheduleEditor(context, p), child: const Text('البرنامج الزمني')),
            ),
          const SizedBox(height: 10),
          SectionCard(
            title: 'بنود الجدول الزمني',
            icon: Icons.list_alt_rounded,
            child: EmptyState(
              title: 'لا بنود بعد',
              message: canItems
                  ? 'أنشئ بنداً لكل عمل من أعمال العقد، أو أضف البنود يدوياً بتاريخي البداية والنهاية المخططين ووزن كل بند.'
                  : 'يضيف البنود مكتب المدير ومكتب العقود والقسم المشرف على العقد.',
              icon: Icons.date_range_outlined,
            ),
          ),
        ] else ...[
          ResponsiveGrid(minItemWidth: narrow ? 150 : 190, spacing: 10, children: [
            StatCard(
                label: 'الإنجاز الكلي الفعلي',
                value: _pct1(track.actual),
                sub: 'موزون بأوزان البنود',
                icon: Icons.trending_up_rounded,
                color: perfColor(context, track.perf)),
            StatCard(label: 'المخطط حتى تاريخ الإسناد', value: _pct1(track.planned), sub: 'موزون', icon: Icons.flag_outlined),
            StatCard(
                label: 'الانحراف',
                value: '${_pts(track.variance)} نقطة',
                sub: 'SPI ${spiText(track.spi)} · ${perfLabels[track.perf]}',
                icon: Icons.speed_rounded,
                color: (track.variance ?? 0) < 0 ? sem.danger : sem.ok),
            StatCard(
                label: 'البنود',
                value: '${track.items.length}',
                sub: 'منجزة ${track.doneItems} · متأخرة ${track.lateItems.length}',
                icon: Icons.list_alt_rounded,
                color: track.lateItems.isNotEmpty ? sem.danger : null),
            StatCard(
                label: 'أكبر تأخير متوقع',
                value: track.worstForecastDelay == null || track.worstForecastDelay! <= 0 ? '—' : _daysWord(track.worstForecastDelay!),
                sub: 'بالسرعة الحالية لكل بند',
                icon: Icons.event_busy_outlined,
                color: (track.worstForecastDelay ?? 0) > 0 ? sem.wip : null),
          ]),
          const SizedBox(height: 14),
          SectionCard(
            title: 'المخطط الزمني',
            icon: Icons.view_timeline_rounded,
            subtitle: 'الشريط الفاتح مدة البند المخططة، والملوّن ما أُنجز منها، والخط العمودي تاريخ الإسناد، والأحمر بعد النهاية تجاوز لبند لم يكتمل.',
            child: ScheduleGantt(track: track),
          ),
          const SizedBox(height: 14),
          SectionCard(
            title: 'البنود والانحرافات',
            icon: Icons.list_alt_rounded,
            subtitle: canProgress ? 'اضغط البند لتحديث نسبة إنجازه أو تعديله.' : null,
            child: Column(children: [
              for (var k = 0; k < track.calcs.length; k++) ...[
                if (k > 0) Divider(height: 1, color: sem.rule),
                _ItemRow(
                  calc: track.calcs[k],
                  share: track.shares[k],
                  onTap: () => _itemSheet(context, app, p, track, k),
                ),
              ],
            ]),
          ),
        ],
      ]),
    );
  }

  Future<void> _fromWorks(BuildContext context, AppState app, Project p, bool hasDates) async {
    if (!hasDates) {
      showToast(context, 'سجّل تاريخي بداية العقد ونهايته في البرنامج الزمني أولاً', error: true);
      await showScheduleEditor(context, p);
      return;
    }
    try {
      final n = await app.pmItemsFromWorks(p.id);
      if (context.mounted) showToast(context, n == 0 ? 'كل الأعمال لها بنود' : 'أُنشئ $n ${n <= 10 ? 'بنود' : 'بنداً'} بتاريخي البرنامج الزمني؛ عدّل تواريخ كل بند ووزنه');
    } catch (e) {
      if (context.mounted) showToast(context, friendlyError(e), error: true);
    }
  }

  Future<void> _record(BuildContext context, AppState app, ScheduleTrack t) async {
    final ok = await confirmDialog(context,
        title: 'تسجيل في التقدم الدوري',
        message: 'يُسجَّل قياس بتاريخ ${pmDay(t.ref)}: المخطط ${_pct1(t.planned)} والفعلي ${_pct1(t.actual)} كما حُسبا من البنود. '
            'إن وُجد قياس بالتاريخ نفسه تُحدَّث نسبتاه.',
        confirmLabel: 'تسجيل');
    if (!ok || !context.mounted) return;
    try {
      await app.recordScheduleMeasurement(t);
      if (context.mounted) showToast(context, 'سُجّل القياس في التقدم الدوري');
    } catch (e) {
      if (context.mounted) showToast(context, friendlyError(e), error: true);
    }
  }

  Future<void> _reorder(BuildContext context, AppState app, Project p, ScheduleTrack t) async {
    final list = [...t.items];
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setLocal) {
        return AlertDialog(
          title: const Text('ترتيب البنود'),
          content: SizedBox(
            width: 480,
            height: math.min(520.0, 64.0 * list.length + 20),
            child: ReorderableListView.builder(
              buildDefaultDragHandles: false,
              itemCount: list.length,
              onReorder: (a, b) => setLocal(() {
                if (b > a) b--;
                list.insert(b, list.removeAt(a));
              }),
              itemBuilder: (_, k) => ListTile(
                key: ValueKey(list[k].id),
                leading: ReorderableDragStartListener(index: k, child: const Icon(Icons.drag_indicator_rounded)),
                title: Text(list[k].title, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text('${pmDay(list[k].plannedStart)} إلى ${pmDay(list[k].plannedEnd)}'),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => setLocal(() => list.sort((a, b) => a.plannedStart.compareTo(b.plannedStart))),
              child: const Text('حسب البداية'),
            ),
            TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('إلغاء')),
            FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('حفظ الترتيب')),
          ],
        );
      }),
    );
    if (ok != true || !context.mounted) return;
    try {
      await app.reorderPmItems(p.id, [for (final i in list) i.id]);
      if (context.mounted) showToast(context, 'حُفظ الترتيب');
    } catch (e) {
      if (context.mounted) showToast(context, friendlyError(e), error: true);
    }
  }

  Future<void> _itemSheet(BuildContext context, AppState app, Project p, ScheduleTrack t, int k) {
    final c = t.calcs[k];
    final i = c.item;
    final work = i.workId == null ? null : app.worksOf(p.id).where((w) => w.id == i.workId).firstOrNull;
    return showPmSheet(
      context,
      code: i.code,
      title: i.title,
      badges: [
        PerfBadge(c.status),
        if (c.overdueDays != null) ToneBadge('تجاوز النهاية المخططة', color: Sem.of(context).danger),
      ],
      rows: [
        ('عمل العقد المرتبط', work == null ? '' : [work.title, work.company, work.refNo].where((x) => x.trim().isNotEmpty).join(' · ')),
        ('البداية · النهاية المخططتان', '${pmDay(i.plannedStart)} إلى ${pmDay(i.plannedEnd)} (${_daysWord(c.duration)})'),
        ('الأيام المنقضية حتى تاريخ الإسناد', '${c.elapsed} من ${c.duration}'),
        ('الوزن', '${i.weight == null ? 'متوسط أوزان البنود' : fmtNum(i.weight!)} · نصيبه ${t.shares[k].toStringAsFixed(1)}% من المشروع'),
        ('المخطط حتى تاريخ الإسناد', _pct1(c.planned)),
        ('الإنجاز الفعلي', _pct1(c.actual)),
        ('الانحراف', '${_pts(c.variance)} نقطة · ${daysVarText(c.daysVariance)}'),
        ('SPI', spiText(c.spi)),
        ('البداية · النهاية الفعليتان', i.actualStart == null && i.actualEnd == null ? '' : '${pmDay(i.actualStart)} · ${pmDay(i.actualEnd)}'),
        ('الإنهاء المتوقع بالسرعة الحالية', c.actual >= 100 || c.forecastEnd == null ? '' : '${pmDay(c.forecastEnd)}${(c.forecastDelay ?? 0) > 0 ? ' (بعد النهاية المخططة بـ${_daysWord(c.forecastDelay!)})' : ''}'),
        ('ملاحظات', i.notes),
      ],
      actions: (sheet) => [
        if (app.canUpdateItemProgress(p))
          FilledButton.icon(
            onPressed: () {
              Navigator.of(sheet).pop();
              showPmItemEditor(context, p, i);
            },
            icon: Icon(app.canEditItems(p) ? Icons.edit_outlined : Icons.trending_up_rounded),
            label: Text(app.canEditItems(p) ? 'تعديل البند والإنجاز' : 'تحديث الإنجاز'),
          ),
        if (app.canEditItems(p))
          pmDeleteButton(context, sheet, what: 'البند', onDelete: () => app.deletePmItem(i.id)),
      ],
    );
  }
}

String fmtNum(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);

/// نموذج البند: البيانات لمن يحدّث البرنامج الزمني، والإنجاز والتواريخ الفعلية والملاحظات أيضاً لمن يحدّث سجل التقدم.
Future<void> showPmItemEditor(BuildContext context, Project p, PmItem? item) async {
  final app = AppScope.read(context);
  final cfg = app.pmConfig;
  final full = app.canEditItems(p);
  final sched = app.schedules[p.id];
  final works = app.worksOf(p.id);
  final ok = await showPmForm(
    context,
    title: item == null ? 'بند جديد في الجدول الزمني' : (full ? 'تعديل البند' : 'تحديث إنجاز البند'),
    note: full
        ? 'الوزن قيمة البند أو نسبته من المشروع (مثل قيمته المالية)؛ إن تُرك فارغاً أخذ متوسط أوزان البنود الأخرى. '
            'نسبة الإنجاز تراكمية من بداية البند، والنهاية الفعلية تُسجَّل عند اكتماله.'
        : 'تحدّث نسبة الإنجاز والتواريخ الفعلية والملاحظات؛ بيانات البند يعدّلها من يحدّث البرنامج الزمني.',
    sections: [
      PmSection('البند', [
        PmField('title', 'اسم البند', PmKind.text, required: true, max: 300, full: true, enabled: full),
        PmField('code', 'رقم البند', PmKind.text, max: 20, enabled: full),
        PmField('work_id', 'عمل العقد المرتبط', PmKind.select,
            options: [('', 'دون ربط'), for (final w in works) (w.id, [w.refNo, w.title, w.company].where((x) => x.trim().isNotEmpty).join(' · '))],
            enabled: full),
        PmField('planned_start', 'البداية المخططة', PmKind.date, required: true, enabled: full),
        PmField('planned_end', 'النهاية المخططة', PmKind.date, required: true, enabled: full),
        PmField('weight', 'الوزن', PmKind.decimal, enabled: full, helper: 'فارغ = متوسط أوزان البنود الأخرى'),
      ]),
      const PmSection('الإنجاز', [
        PmField('progress', 'نسبة الإنجاز الفعلية (تراكمي)', PmKind.percent),
        PmField('actual_start', 'البداية الفعلية', PmKind.date),
        PmField('actual_end', 'النهاية الفعلية', PmKind.date, helper: 'عند اكتمال البند 100%'),
        PmField('notes', 'ملاحظات', PmKind.multiline, max: 1000),
      ]),
    ],
    values: item == null
        ? {
            'planned_start': sched?.startDate ?? pmToday(),
            'planned_end': sched?.endDate ?? addDays(pmToday(), 30),
            'progress': 0.0,
            'work_id': '',
          }
        : {...item.toJson(), 'progress': item.progress / 100},
    preview: (v) {
      final ps = DateTime.tryParse('${v['planned_start'] ?? ''}'), pe = DateTime.tryParse('${v['planned_end'] ?? ''}');
      if (ps == null || pe == null || pe.isBefore(ps)) return null;
      final pr = ((v['progress'] as double?) ?? 0) * 100;
      final c = ItemCalc(PmItem(id: '', projectId: p.id, title: '', plannedStart: ps, plannedEnd: pe, progress: pr), cfg.refDay, cfg);
      return InfoBanner(
        text: 'حتى ${pmDay(c.ref)}: المخطط ${_pct1(c.planned)} · الفعلي ${_pct1(c.actual)} · الانحراف ${_pts(c.variance)} نقطة'
            '${c.status == 'done' || c.status == 'not_started' ? '' : ' (${daysVarText(c.daysVariance)})'} · ${perfLabels[c.status]}',
        level: c.status == 'critical' ? 'critical' : (c.status == 'slight' ? 'warning' : 'ok'),
      );
    },
    onSave: (d) async {
      final data = {
        ...d,
        'project_id': p.id,
        'progress': d['progress'] == null ? 0 : ((d['progress'] as double) * 10000).round() / 100,
        if (item != null) 'sort': item.sort,
      };
      await app.savePmItem(item?.id, data);
    },
  );
  if (ok && context.mounted) showToast(context, item == null ? 'أُضيف البند' : 'حُفظ البند');
}

// =====================================================================
// المخطط الزمني (Gantt): الزمن من اليسار إلى اليمين كبقية الرسوم
// =====================================================================
class ScheduleGantt extends StatelessWidget {
  const ScheduleGantt({super.key, required this.track});

  final ScheduleTrack track;

  @override
  Widget build(BuildContext context) {
    final sem = Sem.of(context);
    final t = track;
    if (t.items.isEmpty) return const SizedBox.shrink();
    var from = t.start!, to = t.end!;
    if (t.ref.isBefore(from)) from = t.ref;
    if (t.ref.isAfter(to)) to = t.ref;
    from = DateTime(from.year, from.month, 1);
    to = DateTime(to.year, to.month + 1, 1);
    final span = math.max(1, daysBetween(to, from));
    final narrow = MediaQuery.sizeOf(context).width < 600;
    final labelW = narrow ? 112.0 : 210.0;
    final colors = _GanttColors(
      track: sem.todoSoft,
      plan: sem.muted.withValues(alpha: 0.30),
      ref: Theme.of(context).colorScheme.primary,
      over: sem.danger,
      grid: sem.rule,
    );
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          SizedBox(width: labelW),
          Expanded(
            child: SizedBox(
              height: 22,
              child: CustomPaint(painter: _AxisPainter(from: from, to: to, span: span, color: sem.muted, grid: sem.rule)),
            ),
          ),
        ]),
        for (final c in t.calcs)
          SizedBox(
            height: 30,
            child: Row(children: [
              SizedBox(
                width: labelW,
                child: Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Text(
                    [if (c.item.code.isNotEmpty) c.item.code, c.item.title].join(' '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textDirection: TextDirection.rtl,
                    textAlign: TextAlign.right,
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ),
              Expanded(
                child: Tooltip(
                  message: '${c.item.title}\n${pmDay(c.item.plannedStart)} إلى ${pmDay(c.item.plannedEnd)} · '
                      'المخطط ${_pct1(c.planned)} · الفعلي ${_pct1(c.actual)}',
                  child: CustomPaint(
                    painter: _BarPainter(
                      calc: c,
                      from: from,
                      span: span,
                      colors: colors,
                      fill: perfColor(context, c.status),
                    ),
                    child: const SizedBox.expand(),
                  ),
                ),
              ),
            ]),
          ),
      ]),
    );
  }
}

class _GanttColors {
  const _GanttColors({required this.track, required this.plan, required this.ref, required this.over, required this.grid});

  final Color track, plan, ref, over, grid;
}

class _AxisPainter extends CustomPainter {
  _AxisPainter({required this.from, required this.to, required this.span, required this.color, required this.grid});

  final DateTime from, to;
  final int span;
  final Color color, grid;

  @override
  void paint(Canvas canvas, Size size) {
    final months = <DateTime>[];
    for (var d = from; d.isBefore(to); d = DateTime(d.year, d.month + 1, 1)) {
      months.add(d);
    }
    final perMonth = size.width / math.max(1, months.length);
    final step = math.max(1, (46 / perMonth).ceil());
    final line = Paint()
      ..color = grid
      ..strokeWidth = 1;
    for (var k = 0; k < months.length; k++) {
      final x = daysBetween(months[k], from) / span * size.width;
      canvas.drawLine(Offset(x, size.height - 4), Offset(x, size.height), line);
      if (k % step != 0) continue;
      final m = months[k];
      final tp = TextPainter(
        text: TextSpan(text: '${m.month}/${m.year % 100}', style: TextStyle(fontSize: 10.5, color: color)),
        textDirection: TextDirection.ltr,
      )..layout();
      if (x + tp.width <= size.width) tp.paint(canvas, Offset(x + 2, 2));
    }
  }

  @override
  bool shouldRepaint(covariant _AxisPainter old) => old.from != from || old.to != to || old.color != color;
}

class _BarPainter extends CustomPainter {
  _BarPainter({required this.calc, required this.from, required this.span, required this.colors, required this.fill});

  final ItemCalc calc;
  final DateTime from;
  final int span;
  final _GanttColors colors;
  final Color fill;

  double _x(DateTime d, double w) => (daysBetween(d, from) / span * w).clamp(0, w).toDouble();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final i = calc.item;
    final bar = h * 0.42;
    final top = (h - bar) / 2;
    final x0 = _x(i.plannedStart, w);
    final x1 = math.max(x0 + 3, _x(i.plannedEnd, w));
    final r = Radius.circular(bar / 2);
    canvas.drawLine(Offset(0, h - 0.5), Offset(w, h - 0.5), Paint()..color = colors.grid.withValues(alpha: 0.5));
    canvas.drawRRect(RRect.fromLTRBR(x0, top, x1, top + bar, r), Paint()..color = colors.plan);
    final done = (x1 - x0) * (calc.actual / 100).clamp(0, 1);
    if (done > 0) {
      canvas.drawRRect(RRect.fromLTRBR(x0, top + 1.5, x0 + done, top + bar - 1.5, r), Paint()..color = fill);
    }
    if (calc.overdueDays != null) {
      final xo = _x(calc.ref, w);
      canvas.drawLine(Offset(x1, h / 2), Offset(xo, h / 2), Paint()
        ..color = colors.over
        ..strokeWidth = 2.5);
    }
    final xr = _x(calc.ref, w);
    canvas.drawLine(Offset(xr, 0), Offset(xr, h), Paint()
      ..color = colors.ref
      ..strokeWidth = 1.5);
  }

  @override
  bool shouldRepaint(covariant _BarPainter old) => old.calc != calc || old.fill != fill || old.span != span;
}
