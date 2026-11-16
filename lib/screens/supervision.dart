import 'package:flutter/material.dart';

import '../app_state.dart';
import '../docs.dart';
import '../models.dart';
import '../pm.dart';
import '../print/export_dialog.dart' show ExportButton;
import '../ui/motion.dart';
import '../ui/slideshow.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';
import 'docs.dart';
import 'pm_common.dart';

// =====================================================================
// قسم «الإشراف»: التقارير اليومية للمواقع (نموذج منظم ومرفقات PDF وصور) ومتابعة تغطيتها.
// =====================================================================

IconData weatherIcon(String w) => switch (w) {
      'cloudy' => Icons.cloud_outlined,
      'rain' => Icons.water_drop_outlined,
      'wind' => Icons.air_rounded,
      'dust' => Icons.blur_on_rounded,
      'hot' => Icons.local_fire_department_outlined,
      'cold' => Icons.ac_unit_rounded,
      _ => Icons.wb_sunny_outlined,
    };

DateTime _today() {
  final n = DateTime.now();
  return DateTime(n.year, n.month, n.day);
}

const List<String> _weekdays = ['الاثنين', 'الثلاثاء', 'الأربعاء', 'الخميس', 'الجمعة', 'السبت', 'الأحد'];

String dayName(DateTime d) => _weekdays[d.weekday - 1];

/// الحرف المختصر لليوم في جدول التغطية: ن ث ر خ ج س ح
String dayLetter(DateTime d) => const ['ن', 'ث', 'ر', 'خ', 'ج', 'س', 'ح'][d.weekday - 1];

/// العقود الجارية التي يُنتظر لها تقرير يومي: الوضع التشغيلي «جارٍ» في البرنامج الزمني،
/// أو عقود بلا برنامج زمني لم تكتمل دورتها المستندية.
List<String> activeSiteProjects(AppState app) {
  final out = <String>[];
  for (final p in app.projects) {
    final s = app.v7Ready ? app.schedules[p.id] : null;
    if (s != null) {
      if (s.opStatus == 'running') out.add(p.id);
    } else if (app.progressOf(p).pct < 1) {
      out.add(p.id);
    }
  }
  return out;
}

// ---------------------------------------------------------------------
// نموذج التقرير
// ---------------------------------------------------------------------
Future<void> showReportEditor(BuildContext context, {SiteReport? report, String? projectId, DateTime? date}) async {
  final app = AppScope.read(context);
  final pid = report?.projectId ?? projectId;
  final options = [for (final o in pmProjectOptions(app)) if (app.canEditReport(o.$1) || o.$1 == report?.projectId) o];
  if (options.isEmpty) {
    showToast(context, 'لا عقود تشرف عليها لرفع تقرير يومي.', error: true);
    return;
  }
  final works = pid == null ? const <ContractWork>[] : app.worksOf(pid);
  // تعبئة مسبقة من آخر تقرير للعقد: المعدات والعمالة والطقس وخطة اليوم السابق كأعمال متوقعة
  SiteReport? last;
  if (report == null && pid != null) {
    final prev = app.docs.reportsOfProject(pid);
    if (prev.isNotEmpty) last = prev.first;
  }
  String? newId;
  final ok = await showPmForm(
    context,
    title: report == null ? 'تقرير يومي جديد' : 'تعديل تقرير ${pmDay(report.reportDate)}',
    note: report == null
        ? 'تقرير واحد لكل عقد في اليوم (ولكل عمل إن كان العقد يضم أكثر من عمل). بعد الحفظ تختار صور الموقع وملفات PDF.'
            '${last != null ? ' عُبّئت المعدات والعمالة من تقرير ${pmDay(last.reportDate)}؛ عدّلها حسب اليوم.' : ''}'
        : null,
    sections: [
      PmSection('العقد واليوم', [
        PmField('project_id', 'العقد', PmKind.select, options: options, required: true, full: true, enabled: report == null),
        if (works.length > 1)
          PmField('work_id', 'العمل', PmKind.select,
              options: [('', 'العقد كله'), for (final w in works) (w.id, w.display)], full: true),
        const PmField('report_date', 'تاريخ التقرير', PmKind.date, required: true),
        PmField('weather', 'الطقس', PmKind.select, options: pmLabels(weatherKinds, weatherLabels), required: true),
        const PmField('temp_c', 'درجة الحرارة (°م)', PmKind.integer),
      ]),
      const PmSection('الموارد في الموقع', [
        PmField('workers', 'عدد العمالة', PmKind.integer),
        PmField('progress_pct', 'نسبة الإنجاز التقديرية (%)', PmKind.decimal, helper: 'تقدير المشرف من 0 إلى 100'),
        PmField('equipment', 'المعدات العاملة', PmKind.multiline, max: 1000),
        PmField('materials', 'المواد الموردة', PmKind.multiline, max: 1500),
      ]),
      const PmSection('سير العمل', [
        PmField('works_done', 'الأعمال المنفذة اليوم', PmKind.multiline, required: true, max: 4000),
        PmField('issues', 'المعوقات والملاحظات', PmKind.multiline, max: 2000),
        PmField('safety', 'السلامة المهنية', PmKind.multiline, max: 1500, helper: 'المخالفات والحوادث والحوادث الوشيكة'),
        PmField('next_plan', 'خطة اليوم التالي', PmKind.multiline, max: 1500),
        PmField('notes', 'ملاحظات أخرى', PmKind.multiline, max: 1500),
      ]),
    ],
    values: report?.toJson() ??
        {
          'project_id': pid ?? options.first.$1,
          'report_date': pmIso(date ?? DateTime.now()),
          'weather': last?.weather ?? 'clear',
          'workers': last?.workers,
          'equipment': last?.equipment ?? '',
        },
    onSave: (d) async {
      final pct = d['progress_pct'];
      if (pct is num && (pct < 0 || pct > 100)) throw StateError('نسبة الإنجاز من 0 إلى 100');
      newId = await app.saveSiteReport(report?.id, d);
    },
  );
  if (!ok || !context.mounted) return;
  if (report != null) {
    showToast(context, 'حُفظ التقرير');
    return;
  }
  showToast(context, 'سُجّل التقرير اليومي');
  final id = newId;
  if (id != null) {
    await pickAndAttach(context, 'report', id);
    if (context.mounted) {
      await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => SiteReportDetailPage(reportId: id)));
    }
  }
}

// ---------------------------------------------------------------------
// صفحة التقارير اليومية
// ---------------------------------------------------------------------
class SiteReportsPage extends StatefulWidget {
  const SiteReportsPage({super.key});

  @override
  State<SiteReportsPage> createState() => _SiteReportsPageState();
}

class _SiteReportsPageState extends State<SiteReportsPage> {
  final _search = TextEditingController();
  String _project = '';
  String _period = '30';
  String _status = '';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final req = AppScope.read(context).takeDocsProject();
    if (req != null) {
      _project = req;
      _period = '';
    }
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    if (!app.v8Ready) return const DocsNotReady(title: 'التقارير اليومية', icon: Icons.assignment_outlined);
    final sem = Sem.of(context);
    final today = _today();
    final q = _search.text.trim();
    final all = app.docs.reports;
    final from = _period.isEmpty ? null : DateTime(today.year, today.month, today.day - int.parse(_period) + 1);
    final list = all.where((r) {
      if (_project.isNotEmpty && r.projectId != _project) return false;
      if (from != null && r.reportDate.isBefore(from)) return false;
      if (_status == 'unreviewed' && r.reviewed) return false;
      if (_status == 'reviewed' && !r.reviewed) return false;
      if (_status == 'issues' && !r.hasIssues) return false;
      if (_status == 'weather' && !r.adverseWeather) return false;
      return pmMatch(q, [r.worksDone, r.issues, r.equipment, r.materials, r.safety, pmProjectName(app, r.projectId)]);
    }).toList()
      ..sort((a, b) {
        final c = b.reportDate.compareTo(a.reportDate);
        return c != 0 ? c : pmProjectName(app, a.projectId).compareTo(pmProjectName(app, b.projectId));
      });

    final active = activeSiteProjects(app);
    final todayCount = all.where((r) => r.reportDate == today && active.contains(r.projectId)).map((r) => r.projectId).toSet().length;
    final unreviewed = all.where((r) => !r.reviewed).length;
    final week = all.where((r) => !r.reportDate.isBefore(DateTime(today.year, today.month, today.day - 6))).length;

    final items = <Widget>[];
    DateTime? lastDay;
    for (final r in list) {
      if (r.reportDate != lastDay) {
        lastDay = r.reportDate;
        final n = list.where((x) => x.reportDate == r.reportDate).length;
        items.add(Container(
          color: sem.surface2,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Row(children: [
            Icon(Icons.calendar_today_rounded, size: 16, color: sem.muted),
            const SizedBox(width: 8),
            Text('${dayName(r.reportDate)} ${pmDay(r.reportDate)}', style: const TextStyle(fontWeight: FontWeight.w800)),
            if (r.reportDate == today) ...[const SizedBox(width: 8), ToneBadge('اليوم', color: Theme.of(context).colorScheme.primary)],
            const Spacer(),
            Text('$n ${n == 1 ? 'تقرير' : 'تقارير'}', style: TextStyle(color: sem.muted, fontSize: 12.5)),
          ]),
        ));
      }
      items.add(ReportTile(report: r));
    }

    return PmListScaffold(
      title: 'التقارير اليومية',
      subtitle: '${all.length} تقرير · $week في آخر 7 أيام${app.isDirector ? ' · $unreviewed بانتظار اطلاعك' : ''}',
      icon: Icons.assignment_rounded,
      actions: [
        ExportButton(sourceId: 'supervision:reports', items: list),
        if (app.canAddReport)
          FilledButton.icon(
            onPressed: () => showReportEditor(context, projectId: _project.isEmpty ? null : _project),
            icon: const Icon(Icons.add_rounded),
            label: const Text('تقرير اليوم'),
          ),
      ],
      top: [
        ResponsiveGrid(minItemWidth: 200, children: [
          StatCard(
            label: 'تقارير اليوم',
            value: '$todayCount من ${active.length}',
            sub: 'عقداً جارياً',
            icon: Icons.today_rounded,
            color: todayCount >= active.length && active.isNotEmpty ? sem.ok : sem.wip,
            onTap: () => app.setTab(71),
          ),
          StatCard(label: 'آخر 7 أيام', value: '$week', sub: 'تقريراً', icon: Icons.date_range_rounded),
          StatCard(
            label: 'بمعوقات (30 يوماً)',
            value: '${all.where((r) => r.hasIssues && !r.reportDate.isBefore(DateTime(today.year, today.month, today.day - 29))).length}',
            icon: Icons.report_problem_outlined,
            color: sem.danger,
            onTap: () => setState(() => _status = 'issues'),
          ),
          if (app.isDirector)
            StatCard(
              label: 'بانتظار اطلاعك',
              value: '$unreviewed',
              icon: Icons.mark_email_unread_outlined,
              color: unreviewed > 0 ? sem.wip : sem.ok,
              onTap: () => setState(() {
                _status = 'unreviewed';
                _period = '';
              }),
            ),
        ]),
        const SizedBox(height: 14),
      ],
      search: _search,
      searchHint: 'بحث في الأعمال والمعوقات والمعدات والعقد',
      onSearch: () => setState(() {}),
      filters: [
        pmFilter('العقد', _project, [('', 'كل العقود'), ...pmProjectOptions(app)], (v) => setState(() => _project = v), width: 300),
        pmFilter('الفترة', _period, const [('7', 'آخر 7 أيام'), ('30', 'آخر 30 يوماً'), ('90', 'آخر 90 يوماً'), ('', 'الكل')],
            (v) => setState(() => _period = v)),
        pmFilter(
            'العرض',
            _status,
            const [
              ('', 'الكل'),
              ('unreviewed', 'لم يُطّلع عليها'),
              ('reviewed', 'اطّلع عليها المدير'),
              ('issues', 'فيها معوقات'),
              ('weather', 'طقس معطِّل'),
            ],
            (v) => setState(() => _status = v)),
      ],
      emptyTitle: all.isEmpty ? 'لا تقارير يومية بعد' : 'لا تقارير مطابقة',
      emptyMessage: all.isEmpty ? 'يرفع رئيس القسم المشرف أو مكتب المدير تقريراً لكل عقد جارٍ في كل يوم عمل، مع صور الموقع.' : null,
      items: items,
    );
  }
}

class ReportTile extends StatelessWidget {
  const ReportTile({super.key, required this.report, this.showProject = true});

  final SiteReport report;
  final bool showProject;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final sem = Sem.of(context);
    final r = report;
    final files = app.docs.filesOfReport(r.id);
    final photos = files.where((f) => f.isImage).length;
    final pdfs = files.length - photos;
    String? work;
    if (r.workId != null) {
      for (final w in app.worksOf(r.projectId)) {
        if (w.id == r.workId) work = w.display;
      }
    }
    return PmTile(
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(color: (r.adverseWeather ? sem.wip : sem.ok).withAlpha(30), borderRadius: BorderRadius.circular(11)),
        child: Icon(weatherIcon(r.weather), color: r.adverseWeather ? sem.wip : sem.ok, size: 21),
      ),
      meta: [
        if (showProject) pmProjectName(app, r.projectId) else '${dayName(r.reportDate)} ${pmDay(r.reportDate)}',
        if (work != null) work,
        weatherLabels[r.weather] ?? r.weather,
        if (r.tempC != null) '${r.tempC}°',
      ].join(' · '),
      title: r.worksDone,
      badges: [
        if (r.workers != null) ToneBadge('${r.workers} عامل', color: sem.muted, icon: Icons.groups_2_outlined),
        if (r.progressPct != null) ToneBadge('إنجاز ${r.progressPct!.toStringAsFixed(r.progressPct! % 1 == 0 ? 0 : 1)}%', color: sem.muted),
        if (photos > 0) ToneBadge('$photos صورة', color: sem.muted, icon: Icons.photo_library_outlined),
        if (pdfs > 0) ToneBadge('$pdfs PDF', color: sem.muted, icon: Icons.picture_as_pdf_outlined),
        if (r.hasIssues) ToneBadge('معوقات', color: sem.danger, icon: Icons.report_problem_outlined),
        if (r.safety.trim().isNotEmpty) ToneBadge('ملاحظة سلامة', color: sem.wip, icon: Icons.health_and_safety_outlined),
        if (r.reviewed) ToneBadge('اطّلع المدير', color: sem.ok, icon: Icons.done_all_rounded),
      ],
      onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => SiteReportDetailPage(reportId: r.id))),
    );
  }
}

// ---------------------------------------------------------------------
// صفحة التقرير
// ---------------------------------------------------------------------
class SiteReportDetailPage extends StatelessWidget {
  const SiteReportDetailPage({super.key, required this.reportId});

  final String reportId;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final sem = Sem.of(context);
    SiteReport? found;
    for (final r in app.docs.reports) {
      if (r.id == reportId) found = r;
    }
    final r = found;
    if (r == null) {
      return Scaffold(
        appBar: brandAppBar(context, title: const Text('التقرير اليومي')),
        body: const EmptyState(title: 'التقرير غير موجود', message: 'ربما حُذف.', icon: Icons.search_off_rounded),
      );
    }
    final files = app.docs.filesOfReport(r.id);
    final images = [for (final f in files) if (f.isImage) f];
    final slides = [for (final f in images) Slide(file: f, caption: f.name, date: pmDay(r.reportDate))];
    final canEdit = app.canEditReport(r.projectId);
    final canDelete = app.isDirector || (canEdit && app.canRemoveOwn(r.createdBy, r.createdAt));
    String? work;
    if (r.workId != null) {
      for (final w in app.worksOf(r.projectId)) {
        if (w.id == r.workId) work = w.display;
      }
    }
    // التقرير السابق والتالي للعقد نفسه
    final siblings = app.docs.reportsOfProject(r.projectId);
    final pos = siblings.indexWhere((x) => x.id == r.id);
    final newer = pos > 0 ? siblings[pos - 1] : null;
    final older = pos >= 0 && pos < siblings.length - 1 ? siblings[pos + 1] : null;

    Widget block(String title, String text, IconData icon, {Color? color}) => text.trim().isEmpty
        ? const SizedBox.shrink()
        : Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: SectionCard(
              title: title,
              icon: icon,
              child: Text(text, style: TextStyle(height: 1.55, color: color)),
            ),
          );

    return Scaffold(
      appBar: brandAppBar(context, title: const Text('التقرير اليومي'), actions: [
        if (older != null)
          IconButton(
            tooltip: 'التقرير السابق (${pmDay(older.reportDate)})',
            onPressed: () => Navigator.of(context)
                .pushReplacement(MaterialPageRoute<void>(builder: (_) => SiteReportDetailPage(reportId: older.id))),
            icon: const Icon(Icons.chevron_right_rounded),
          ),
        if (newer != null)
          IconButton(
            tooltip: 'التقرير التالي (${pmDay(newer.reportDate)})',
            onPressed: () => Navigator.of(context)
                .pushReplacement(MaterialPageRoute<void>(builder: (_) => SiteReportDetailPage(reportId: newer.id))),
            icon: const Icon(Icons.chevron_left_rounded),
          ),
        if (canEdit)
          IconButton(tooltip: 'تعديل', onPressed: () => showReportEditor(context, report: r), icon: const Icon(Icons.edit_outlined)),
        if (canDelete)
          IconButton(
            tooltip: 'حذف التقرير',
            icon: Icon(Icons.delete_outline_rounded, color: sem.danger),
            onPressed: () async {
              final ok = await confirmDialog(context,
                  title: 'حذف تقرير ${pmDay(r.reportDate)}',
                  message: 'يُحذف التقرير بصوره وملفاته نهائياً، ويبقى أثره في سجل التدقيق.',
                  confirmLabel: 'حذف',
                  danger: true);
              if (!ok || !context.mounted) return;
              try {
                await app.deleteSiteReport(r.id);
                if (context.mounted) {
                  Navigator.of(context).pop();
                  showToast(context, 'حُذف التقرير');
                }
              } catch (e) {
                if (context.mounted) showToast(context, friendlyError(e), error: true);
              }
            },
          ),
      ]),
      body: PageBody(maxWidth: 1000, onRefresh: app.loadAll, children: [
        PageHeader(
          title: '${dayName(r.reportDate)} ${pmDay(r.reportDate)}',
          subtitle: [pmProjectName(app, r.projectId), if (work != null) work, app.project(r.projectId)?.company ?? '']
              .where((x) => x.isNotEmpty)
              .join(' · '),
          icon: Icons.assignment_rounded,
        ),
        ResponsiveGrid(minItemWidth: 170, children: [
          StatCard(
            label: 'الطقس',
            value: weatherLabels[r.weather] ?? r.weather,
            sub: r.tempC == null ? null : '${r.tempC}° م',
            icon: weatherIcon(r.weather),
            color: r.adverseWeather ? sem.wip : sem.ok,
          ),
          StatCard(label: 'العمالة', value: r.workers?.toString() ?? '—', sub: 'عاملاً', icon: Icons.groups_2_outlined),
          StatCard(
            label: 'الإنجاز التقديري',
            value: r.progressPct == null ? '—' : '${r.progressPct!.toStringAsFixed(r.progressPct! % 1 == 0 ? 0 : 1)}%',
            icon: Icons.trending_up_rounded,
          ),
          StatCard(label: 'المرفقات', value: '${files.length}', sub: '${images.length} صورة', icon: Icons.attach_file_rounded),
        ]),
        const SizedBox(height: 14),
        if (r.reviewed)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: InfoBanner(
              text: 'اطّلع المدير ${fmtDate(r.reviewedAt)}${r.reviewNote.isNotEmpty ? ' — ${r.reviewNote}' : ''}',
              level: 'ok',
              icon: Icons.done_all_rounded,
            ),
          ),
        if (app.isDirector)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: r.reviewed
                  ? TextButton.icon(
                      onPressed: () async {
                        try {
                          await app.reviewSiteReport(r.id, false, '');
                        } catch (e) {
                          if (context.mounted) showToast(context, friendlyError(e), error: true);
                        }
                      },
                      icon: const Icon(Icons.undo_rounded),
                      label: const Text('إلغاء الاطلاع'),
                    )
                  : FilledButton.tonalIcon(
                      onPressed: () async {
                        final note = await textInputDialog(context,
                            title: 'الاطلاع على التقرير',
                            message: 'تُسجَّل ملاحظتك على التقرير ويراها من رفعه.',
                            label: 'ملاحظة (اختيارية)',
                            confirmLabel: 'تم الاطلاع');
                        if (note == null || !context.mounted) return;
                        try {
                          await app.reviewSiteReport(r.id, true, note);
                          if (context.mounted) showToast(context, 'سُجّل اطلاعك');
                        } catch (e) {
                          if (context.mounted) showToast(context, friendlyError(e), error: true);
                        }
                      },
                      icon: const Icon(Icons.done_all_rounded),
                      label: const Text('تم الاطلاع'),
                    ),
            ),
          ),
        block('الأعمال المنفذة', r.worksDone, Icons.construction_rounded),
        block('المعوقات والملاحظات', r.issues, Icons.report_problem_outlined, color: sem.danger),
        block('السلامة المهنية', r.safety, Icons.health_and_safety_outlined),
        block('المعدات العاملة', r.equipment, Icons.precision_manufacturing_outlined),
        block('المواد الموردة', r.materials, Icons.inventory_2_outlined),
        block('خطة اليوم التالي', r.nextPlan, Icons.event_note_outlined),
        block('ملاحظات أخرى', r.notes, Icons.notes_rounded),
        SectionCard(
          title: 'صور الموقع والمرفقات',
          icon: Icons.photo_library_outlined,
          trailing: canEdit
              ? FilledButton.tonalIcon(
                  onPressed: () => pickAndAttach(context, 'report', r.id),
                  icon: const Icon(Icons.add_a_photo_outlined),
                  label: const Text('إرفاق'),
                )
              : null,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (images.isNotEmpty) ...[
              AutoSlideshow(slides: slides, aspectRatio: 16 / 9, fit: BoxFit.contain),
              const SizedBox(height: 10),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final (i, f) in images.indexed)
                  Stack(children: [
                    InkWell(
                      borderRadius: BorderRadius.circular(10),
                      onTap: () => showSlideViewer(context, slides, i),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: SizedBox(width: 110, height: 76, child: DocImage(file: f)),
                      ),
                    ),
                    if (app.canRemoveOwn(f.createdBy, f.createdAt))
                      PositionedDirectional(
                        top: 2,
                        end: 2,
                        child: Material(
                          color: Colors.black54,
                          shape: const CircleBorder(),
                          child: InkWell(
                            customBorder: const CircleBorder(),
                            onTap: () => removeDocFile(context, f),
                            child: const Padding(padding: EdgeInsets.all(3), child: Icon(Icons.close_rounded, size: 16, color: Colors.white)),
                          ),
                        ),
                      ),
                  ]),
              ]),
            ],
            for (final f in files)
              if (!f.isImage) DocFileTile(file: f, canRemove: app.canRemoveOwn(f.createdBy, f.createdAt)),
            if (files.isEmpty) Text('لا مرفقات بعد.', style: TextStyle(color: sem.muted)),
          ]),
        ),
        const SizedBox(height: 10),
        Text('رفعه ${app.people[r.createdBy]?.displayName ?? '—'} · ${fmtDate(r.createdAt)}'
            '${r.updatedAt != null && r.createdAt != null && r.updatedAt!.difference(r.createdAt!).inMinutes > 1 ? ' · آخر تعديل ${fmtDate(r.updatedAt)}' : ''}',
            style: TextStyle(color: sem.muted, fontSize: 12)),
      ]),
    );
  }
}

// ---------------------------------------------------------------------
// متابعة التغطية: لكل عقد جارٍ، هل رُفع تقرير في كل يوم من الأيام الأخيرة؟
// ---------------------------------------------------------------------
class ReportCoveragePage extends StatefulWidget {
  const ReportCoveragePage({super.key});

  @override
  State<ReportCoveragePage> createState() => _ReportCoveragePageState();
}

class _ReportCoveragePageState extends State<ReportCoveragePage> {
  int _days = 14;
  bool _skipFriday = true;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    if (!app.v8Ready) return const DocsNotReady(title: 'متابعة التغطية', icon: Icons.grid_on_rounded);
    final sem = Sem.of(context);
    final cs = Theme.of(context).colorScheme;
    final today = _today();
    final days = [for (var i = _days - 1; i >= 0; i--) DateTime(today.year, today.month, today.day - i)];
    final workDays = days.where((d) => !_skipFriday || d.weekday != DateTime.friday).toList();
    final active = activeSiteProjects(app);
    final rows = [
      for (final pid in active)
        (
          pid,
          {for (final r in app.docs.reportsOfProject(pid)) pmIso(r.reportDate): r},
        ),
    ];
    double cover(Map<String, SiteReport> m) =>
        workDays.isEmpty ? 0 : workDays.where((d) => m.containsKey(pmIso(d))).length / workDays.length;
    rows.sort((a, b) => cover(a.$2).compareTo(cover(b.$2)));
    final avg = rows.isEmpty ? 0.0 : rows.fold<double>(0, (s, r) => s + cover(r.$2)) / rows.length;
    final missingToday = rows.where((r) => !r.$2.containsKey(pmIso(today))).length;

    return PageBody(maxWidth: 1300, onRefresh: app.loadAll, children: [
      PageHeader(
        title: 'متابعة التغطية',
        subtitle: 'العقود الجارية وتقاريرها اليومية في آخر $_days يوماً. الخانة الفارغة يوم بلا تقرير؛ اضغطها لرفعه إن كان من اختصاصك.',
        icon: Icons.grid_on_rounded,
      ),
      ResponsiveGrid(minItemWidth: 220, children: [
        StatCard(label: 'متوسط التغطية', value: pctText(avg), icon: Icons.donut_large_rounded, color: avg >= 0.9 ? sem.ok : (avg >= 0.6 ? sem.wip : sem.danger)),
        StatCard(label: 'عقود جارية', value: '${rows.length}', icon: Icons.construction_rounded),
        StatCard(label: 'بلا تقرير اليوم', value: '$missingToday', icon: Icons.event_busy_outlined, color: missingToday > 0 ? sem.wip : sem.ok),
      ]),
      const SizedBox(height: 14),
      Wrap(spacing: 10, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.center, children: [
        pmFilter('المدة', '$_days', const [('7', '7 أيام'), ('14', '14 يوماً'), ('30', '30 يوماً')], (v) => setState(() => _days = int.parse(v)),
            width: 150),
        FilterChip(
          label: const Text('استبعاد الجمعة من النسبة'),
          selected: _skipFriday,
          onSelected: (v) => setState(() => _skipFriday = v),
        ),
      ]),
      const SizedBox(height: 14),
      if (rows.isEmpty)
        const EmptyState(title: 'لا عقود جارية', message: 'تظهر هنا العقود التي وضعها التشغيلي «جارٍ» في البرنامج الزمني.', icon: Icons.inbox_outlined)
      else
        Container(
          decoration: cardDecoration(context),
          clipBehavior: Clip.antiAlias,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                const SizedBox(width: 260),
                SizedBox(width: 70, child: Text('التغطية', style: TextStyle(color: sem.muted, fontSize: 12, fontWeight: FontWeight.w700))),
                for (final d in days)
                  SizedBox(
                    width: 30,
                    child: Column(children: [
                      Text(dayLetter(d), style: TextStyle(color: d.weekday == DateTime.friday ? sem.wip : sem.muted, fontSize: 10.5)),
                      Text('${d.day}', style: TextStyle(fontSize: 11.5, fontWeight: d == today ? FontWeight.w900 : FontWeight.w600)),
                    ]),
                  ),
              ]),
              const SizedBox(height: 6),
              for (final (i, row) in rows.indexed)
                FadeSlideIn(
                  delay: Duration(milliseconds: 25 * (i % 20)),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(children: [
                      SizedBox(
                        width: 260,
                        child: Text(pmProjectName(app, row.$1), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13)),
                      ),
                      SizedBox(
                        width: 70,
                        child: Text(pctText(cover(row.$2)),
                            style: TextStyle(
                                fontWeight: FontWeight.w800,
                                color: cover(row.$2) >= 0.9 ? sem.ok : (cover(row.$2) >= 0.6 ? sem.wip : sem.danger))),
                      ),
                      for (final d in days)
                        Padding(
                          padding: const EdgeInsets.all(2),
                          child: _Cell(
                            report: row.$2[pmIso(d)],
                            friday: d.weekday == DateTime.friday,
                            today: d == today,
                            onTap: () {
                              final rep = row.$2[pmIso(d)];
                              if (rep != null) {
                                Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => SiteReportDetailPage(reportId: rep.id)));
                              } else if (app.canEditReport(row.$1)) {
                                showReportEditor(context, projectId: row.$1, date: d);
                              }
                            },
                            color: cs.primary,
                          ),
                        ),
                    ]),
                  ),
                ),
            ]),
          ),
        ),
      const SizedBox(height: 10),
      Wrap(spacing: 14, runSpacing: 6, children: [
        _legend(context, cs.primary, 'تقرير مرفوع'),
        _legend(context, sem.danger, 'فيه معوقات'),
        _legend(context, sem.surface2, 'بلا تقرير'),
      ]),
    ]);
  }

  Widget _legend(BuildContext context, Color c, String t) => Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 12, height: 12, decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(3))),
        const SizedBox(width: 5),
        Text(t, style: TextStyle(color: Sem.of(context).muted, fontSize: 12)),
      ]);
}

class _Cell extends StatelessWidget {
  const _Cell({required this.report, required this.friday, required this.today, required this.onTap, required this.color});

  final SiteReport? report;
  final bool friday;
  final bool today;
  final VoidCallback onTap;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final sem = Sem.of(context);
    final r = report;
    final c = r == null ? (friday ? sem.surface2.withValues(alpha: 0.5) : sem.surface2) : (r.hasIssues ? sem.danger : color);
    return Tooltip(
      message: r == null ? (friday ? 'جمعة – بلا تقرير' : 'بلا تقرير') : '${r.workers ?? '—'} عامل · ${r.worksDone}',
      child: InkWell(
        borderRadius: BorderRadius.circular(5),
        onTap: onTap,
        child: Container(
          width: 26,
          height: 22,
          decoration: BoxDecoration(
            color: c,
            borderRadius: BorderRadius.circular(5),
            border: today ? Border.all(color: Theme.of(context).colorScheme.primary, width: 1.5) : null,
          ),
          child: r != null && r.reviewed ? const Icon(Icons.check_rounded, size: 14, color: Colors.white) : null,
        ),
      ),
    );
  }
}
