import 'package:flutter/material.dart';

import '../app_state.dart';
import '../pm.dart';
import '../print/export_dialog.dart' show ExportButton;
import '../ui/slideshow.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';
import '../units.dart';
import 'docs.dart';
import 'pm_common.dart';

// =====================================================================
// أقسام الوحدات: الترميم والمباني التاريخية، مكتب التخطيط وضمان الجودة، مكتب السلامة المهنية،
// المطابقة والاستلام. صفحة سجل عامة لكل نوع، وصفحة تفاصيل بمرفقاتها وسجلاتها التابعة، ولوحة لكل قسم.
// =====================================================================

DateTime _today() {
  final n = DateTime.now();
  return DateTime(n.year, n.month, n.day);
}

/// تنبيه: قاعدة البيانات لم تُحدَّث بعد بالترحيل 21.
class UnitsNotReady extends StatelessWidget {
  const UnitsNotReady({super.key, required this.title, this.icon = Icons.apartment_rounded});

  final String title;
  final IconData icon;

  @override
  Widget build(BuildContext context) => PageBody(children: [
        PageHeader(title: title, icon: icon),
        const InfoBanner(
          text: 'هذا القسم يعمل بعد تحديث قاعدة البيانات بالملف 20261114000021_unit_sections.sql.',
          level: 'warning',
        ),
      ]);
}

Color unitToneColor(BuildContext context, UnitTone t) {
  final sem = Sem.of(context);
  return switch (t) {
    UnitTone.ok => sem.ok,
    UnitTone.wip => sem.wip,
    UnitTone.danger => sem.danger,
    UnitTone.info => Theme.of(context).colorScheme.primary,
    UnitTone.neutral => sem.muted,
  };
}

IconData unitKindIcon(String kind) => switch (kind) {
      'heritage_building' => Icons.museum_outlined,
      'heritage_assessment' => Icons.fact_check_outlined,
      'plan' => Icons.flag_outlined,
      'qa_audit' => Icons.manage_search_rounded,
      'ncr' => Icons.report_gmailerrorred_outlined,
      'followup_task' => Icons.assignment_turned_in_outlined,
      'safety_inspection' => Icons.health_and_safety_outlined,
      'safety_incident' => Icons.personal_injury_outlined,
      'safety_violation' => Icons.do_not_disturb_on_outlined,
      'handover' => Icons.handshake_outlined,
      'punch_item' => Icons.checklist_rounded,
      'qc_test' => Icons.science_outlined,
      'material_approval' => Icons.inventory_2_outlined,
      _ => Icons.description_outlined,
    };

IconData unitIcon(String unit) => switch (unit) {
      'heritage' => Icons.museum_outlined,
      'planning' => Icons.flag_outlined,
      'quality_assurance' => Icons.verified_outlined,
      'follow_up' => Icons.track_changes_rounded,
      'safety' => Icons.health_and_safety_outlined,
      'receiving' => Icons.handshake_outlined,
      'quality_control' => Icons.science_outlined,
      'technical' => Icons.inventory_2_outlined,
      _ => Icons.apartment_rounded,
    };

/// شارة الموعد: متأخر بعدد الأيام، أو متبقٍ، أو اليوم.
Widget? unitDueBadge(BuildContext context, UnitRecord r, DateTime today) {
  final sem = Sem.of(context);
  final left = r.daysLeft(today);
  if (left == null || r.isClosed) return null;
  if (left < 0) return ToneBadge('متأخر ${-left} يوم', color: sem.danger, icon: Icons.schedule_rounded);
  if (left == 0) return ToneBadge('الموعد اليوم', color: sem.wip, icon: Icons.schedule_rounded);
  return ToneBadge('باقٍ $left يوم', color: left <= 3 ? sem.wip : sem.muted, icon: Icons.schedule_rounded);
}

// ---------------------------------------------------------------------
// نموذج السجل
// ---------------------------------------------------------------------
Future<void> showUnitRecordEditor(BuildContext context, String kind, {UnitRecord? record, String? parentId, String? projectId}) async {
  final app = AppScope.read(context);
  final k = unitKinds[kind]!;
  if (!app.canEditUnit(k.unit)) {
    showToast(context, 'لا تملك صلاحية الكتابة في ${unitNames[k.unit]}.', error: true);
    return;
  }
  final parentKind = k.parent == null ? null : unitKinds[k.parent!];
  final parents = parentKind == null ? const <UnitRecord>[] : app.units.ofKind(parentKind.key);
  if (record == null && k.parentRequired && parents.isEmpty) {
    showToast(context, 'أضف ${parentKind!.single} أولاً، ثم أضف إليه ${k.single}.', error: true);
    return;
  }
  final parent = parentId == null ? null : app.units.byId(parentId);
  // العقد مطلوب لهذا النوع، إلا إن كان يتبع سجلاً فيأخذ عقده
  final projectRequired = k.projectRequired && k.parent == null;
  String? newId;
  final ok = await showPmForm(
    context,
    title: record == null ? '${k.single} جديد' : 'تعديل ${k.single}',
    note: record == null && k.parent != null && !k.parentRequired
        ? 'يمكن ربطه بـ${parentKind!.single}؛ وإن تُرك العقد فارغاً أُخذ عقد ${parentKind.single}.'
        : null,
    sections: [
      PmSection('البيانات الأساسية', [
        PmField('title', k.titleLabel, PmKind.text, required: true, max: 200, full: true),
        PmField('ref_no', k.refLabel, PmKind.text, max: 60),
        PmField('rec_date', k.dateLabel, PmKind.date, required: true),
        if (k.dueLabel != null) PmField('due_date', k.dueLabel!, PmKind.date),
        PmField('status', 'الحالة', PmKind.select, options: k.statuses, required: true),
        if (k.hasLevels) PmField('level', k.levelLabel, PmKind.select, options: k.levels, required: k.levels.first.$1.isNotEmpty),
        if (k.progress) const PmField('progress', 'نسبة الإنجاز', PmKind.percent),
        if (k.ownerLabel != null) PmField('owner_text', k.ownerLabel!, PmKind.text, max: 120),
      ]),
      PmSection('الارتباط', [
        if (parentKind != null)
          PmField('parent_id', parentKind.single, PmKind.select,
              options: [for (final p in parents) (p.id, [p.refNo, p.title].where((x) => x.isNotEmpty).join(' · '))],
              required: k.parentRequired,
              full: true),
        PmField('project_id', 'العقد', PmKind.select,
            options: pmProjectOptions(app, general: projectRequired ? null : 'دون عقد'),
            required: projectRequired,
            full: true,
            helper: k.projectRequired && k.parent != null ? 'إن تُرك فارغاً أُخذ عقد ${parentKind!.single}' : null),
      ]),
      if (k.fields.isNotEmpty)
        PmSection('التفاصيل', [
          for (final f in k.fields)
            PmField('f_${f.key}', f.label, switch (f.type) {
              UnitFieldType.text => PmKind.text,
              UnitFieldType.long => PmKind.multiline,
              UnitFieldType.number => PmKind.decimal,
              UnitFieldType.select => PmKind.select,
            },
                options: f.type == UnitFieldType.select ? pmPlain(f.options) : const [],
                max: f.max,
                helper: f.helper,
                full: f.type == UnitFieldType.long),
        ]),
      const PmSection('', [PmField('notes', 'ملاحظات', PmKind.multiline, max: 4000)]),
    ],
    values: record?.toForm() ??
        {
          'rec_date': pmIso(_today()),
          'status': k.defaultStatus,
          'level': k.defaultLevel,
          'parent_id': parentId ?? '',
          'project_id': projectId ?? (k.parent != null ? '' : (parent?.projectId ?? '')),
        },
    onSave: (d) async {
      newId = await app.saveUnitRecord(record?.id, unitPayload(k, d, create: record == null));
    },
  );
  if (!ok || !context.mounted) return;
  showToast(context, record == null ? 'سُجّل ${k.single}' : 'حُفظ ${k.single}');
  final id = newId;
  if (record == null && id != null) {
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => UnitRecordDetailPage(recordId: id)));
  }
}

// ---------------------------------------------------------------------
// صفحة السجل: نوع واحد، أو أنواع الوحدة بمبدّل
// ---------------------------------------------------------------------
class UnitRecordsPage extends StatefulWidget {
  const UnitRecordsPage({super.key, required this.unit, required this.kinds, this.title});

  final String unit;
  final List<String> kinds;

  /// العنوان (افتراضياً: اسم النوع إن كان واحداً، أو اسم الوحدة).
  final String? title;

  @override
  State<UnitRecordsPage> createState() => _UnitRecordsPageState();
}

class _UnitRecordsPageState extends State<UnitRecordsPage> {
  final _search = TextEditingController();
  late String _kind = widget.kinds.first;
  String _project = 'all';
  String _status = 'all';
  String _level = 'all';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final sem = Sem.of(context);
    final k = unitKinds[_kind]!;
    final title = widget.title ?? (widget.kinds.length == 1 ? k.label : unitNames[widget.unit]!);
    if (!app.v9Ready) return UnitsNotReady(title: title, icon: unitIcon(widget.unit));
    final today = _today();
    final all = app.units.ofKind(_kind);
    final q = _search.text.trim();
    final list = all.where((r) {
      if (_project != 'all' && (r.projectId ?? '') != _project) return false;
      // قيم التصفية: is:* للمجموعات (المفتوحة، المغلقة، المتأخرة) وst:* لحالة بعينها، حتى لا تتكرر مفاتيح مثل open وclosed
      if (_status == 'is:open' && r.isClosed) return false;
      if (_status == 'is:closed' && !r.isClosed) return false;
      if (_status == 'is:overdue' && !r.overdue(today)) return false;
      if (_status.startsWith('st:') && r.status != _status.substring(3)) return false;
      if (_level != 'all' && r.level != _level) return false;
      final parent = r.parentId == null ? null : app.units.byId(r.parentId!);
      return pmMatch(q, [r.title, r.refNo, r.ownerText, r.notes, parent?.title ?? '', pmProjectName(app, r.projectId), ...r.data.values.map((v) => '$v')]);
    }).toList();
    final open = all.where((r) => !r.isClosed).length;
    final overdue = all.where((r) => r.overdue(today)).length;
    final closedMonth = all.where((r) => r.closedAt != null && r.closedAt!.year == today.year && r.closedAt!.month == today.month).length;
    final projects = {for (final r in all) if (r.projectId != null) r.projectId!};
    final canAdd = app.canEditUnit(k.unit);

    return PmListScaffold(
      title: title,
      subtitle: widget.kinds.length == 1 ? unitNames[widget.unit] : null,
      icon: unitKindIcon(_kind),
      actions: [
        ExportButton(sourceId: 'unit:$_kind', items: list),
        if (canAdd)
          FilledButton.icon(
            onPressed: () => showUnitRecordEditor(context, _kind),
            icon: const Icon(Icons.add_rounded),
            label: Text('إضافة ${k.single}'),
          ),
      ],
      search: _search,
      searchHint: 'بحث في ${k.label}',
      onSearch: () => setState(() {}),
      top: [
        if (widget.kinds.length > 1) ...[
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SegmentedButton<String>(
              segments: [
                for (final kk in widget.kinds)
                  ButtonSegment(value: kk, label: Text(unitKinds[kk]!.label), icon: Icon(unitKindIcon(kk), size: 18)),
              ],
              selected: {_kind},
              onSelectionChanged: (s) => setState(() {
                _kind = s.first;
                _status = 'all';
                _level = 'all';
              }),
            ),
          ),
          const SizedBox(height: 14),
        ],
        ResponsiveGrid(minItemWidth: 180, children: [
          StatCard(label: 'الإجمالي', value: '${all.length}', icon: unitKindIcon(_kind)),
          StatCard(label: 'مفتوحة', value: '$open', sub: 'لم تُغلق بعد', icon: Icons.pending_actions_rounded, color: open > 0 ? sem.wip : sem.ok),
          if (k.dueLabel != null)
            StatCard(
              label: 'متأخرة',
              value: '$overdue',
              sub: 'تجاوزت ${k.dueLabel}',
              icon: Icons.schedule_rounded,
              color: overdue > 0 ? sem.danger : sem.ok,
              onTap: overdue > 0 ? () => setState(() => _status = 'is:overdue') : null,
            ),
          StatCard(label: 'أُغلقت هذا الشهر', value: '$closedMonth', icon: Icons.task_alt_rounded, color: sem.ok),
        ]),
        const SizedBox(height: 14),
      ],
      filters: [
        pmFilter('العقد', _project, [('all', 'كل العقود'), for (final o in pmProjectOptions(app)) if (projects.contains(o.$1)) o],
            (v) => setState(() => _project = v), width: 240),
        pmFilter('الحالة', _status, [
          ('all', 'الكل'),
          ('is:open', 'المفتوحة'),
          ('is:closed', 'المغلقة'),
          if (k.dueLabel != null) ('is:overdue', 'المتأخرة'),
          for (final st in k.statuses) ('st:${st.$1}', st.$2),
        ], (v) => setState(() => _status = v)),
        if (k.hasLevels) pmFilter(k.levelLabel, _level, [('all', 'الكل'), ...k.levels.where((l) => l.$1.isNotEmpty)], (v) => setState(() => _level = v)),
      ],
      items: [for (final r in list) UnitRecordTile(record: r, today: today)],
      emptyTitle: all.isEmpty ? 'لا ${k.label} بعد' : 'لا نتائج',
      emptyMessage: all.isEmpty
          ? (canAdd ? 'أضف أول ${k.single} من زر الإضافة.' : 'تظهر هنا حين تضيفها ${unitNames[k.unit]}.')
          : 'غيّر البحث أو التصفية.',
    );
  }
}

class UnitRecordTile extends StatelessWidget {
  const UnitRecordTile({super.key, required this.record, required this.today, this.showUnit = false});

  final UnitRecord record;
  final DateTime today;
  final bool showUnit;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final sem = Sem.of(context);
    final r = record;
    final k = r.spec!;
    final parent = r.parentId == null ? null : app.units.byId(r.parentId!);
    final files = app.docs.filesOfRecord(r.id);
    final due = unitDueBadge(context, r, today);
    final childBadges = <Widget>[
      for (final c in k.children)
        if (app.units.childrenOf(r.id, c.key).where((x) => !x.isClosed).isNotEmpty)
          ToneBadge('${c.label}: ${app.units.childrenOf(r.id, c.key).where((x) => !x.isClosed).length} مفتوحة',
              color: sem.wip, icon: unitKindIcon(c.key)),
    ];
    final latest = r.kind == 'heritage_building' ? UnitStats(app.units, today).latestAssessment(r.id) : null;
    return PmTile(
      code: r.refNo,
      meta: [
        pmDay(r.recDate),
        if (showUnit) unitNames[r.unit] ?? '',
        if (r.projectId != null) pmProjectName(app, r.projectId),
        if (parent != null) parent.title,
      ].where((x) => x.isNotEmpty).join(' · '),
      title: r.title,
      leading: CircleAvatar(
        radius: 18,
        backgroundColor: unitToneColor(context, k.statusTone(r.status)).withValues(alpha: 0.14),
        child: Icon(unitKindIcon(r.kind), size: 19, color: unitToneColor(context, k.statusTone(r.status))),
      ),
      badges: [
        ToneBadge(r.statusLabel, color: unitToneColor(context, k.statusTone(r.status))),
        if (k.hasLevels && r.level.isNotEmpty) ToneBadge(r.levelLabel, color: unitToneColor(context, k.levelTone(r.level))),
        if (r.progress != null) ToneBadge('إنجاز ${r.progress!.toStringAsFixed(r.progress! % 1 == 0 ? 0 : 1)}%', color: sem.muted),
        if (due != null) due,
        if (r.ownerText.isNotEmpty) ToneBadge(r.ownerText, color: sem.muted, icon: Icons.person_outline_rounded),
        if (latest != null) ToneBadge('آخر تقييم: ${latest.levelLabel}', color: unitToneColor(context, latest.spec!.levelTone(latest.level))),
        ...childBadges,
        if (files.isNotEmpty) ToneBadge('${files.length} مرفق', color: sem.muted, icon: Icons.attach_file_rounded),
      ],
      onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => UnitRecordDetailPage(recordId: r.id))),
    );
  }
}

// ---------------------------------------------------------------------
// تفاصيل السجل: البيانات، والسجلات التابعة، والمرفقات
// ---------------------------------------------------------------------
class UnitRecordDetailPage extends StatelessWidget {
  const UnitRecordDetailPage({super.key, required this.recordId});

  final String recordId;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final sem = Sem.of(context);
    final r = app.units.byId(recordId);
    if (r == null || r.spec == null) {
      return Scaffold(
        appBar: brandAppBar(context, title: const Text('السجل')),
        body: const EmptyState(title: 'السجل غير موجود', message: 'ربما حُذف.', icon: Icons.search_off_rounded),
      );
    }
    final k = r.spec!;
    final today = _today();
    final canEdit = app.canEditUnit(r.unit);
    final canDelete = app.canDeleteUnitRecord(r);
    final parent = r.parentId == null ? null : app.units.byId(r.parentId!);
    final files = app.docs.filesOfRecord(r.id);
    final images = [for (final f in files) if (f.isImage) f];
    final slides = [for (final f in images) Slide(file: f, caption: f.name, date: pmDay(r.recDate))];
    final due = unitDueBadge(context, r, today);
    final details = [
      for (final f in k.fields)
        if (r.field(f.key).isNotEmpty) (f, r.field(f.key)),
    ];

    Future<void> delete() async {
      final kids = [for (final c in k.children) ...app.units.childrenOf(r.id, c.key)];
      final ok = await confirmDialog(context,
          title: 'حذف ${k.single}',
          message: 'يُحذف «${r.title}» بمرفقاته${kids.isEmpty ? '' : ' و${kids.length} سجل تابع له'} نهائياً، ويبقى أثره في سجل التدقيق.',
          confirmLabel: 'حذف',
          danger: true);
      if (!ok || !context.mounted) return;
      try {
        await app.deleteUnitRecord(r.id);
        if (context.mounted) {
          Navigator.of(context).pop();
          showToast(context, 'حُذف ${k.single}');
        }
      } catch (e) {
        if (context.mounted) showToast(context, friendlyError(e), error: true);
      }
    }

    return Scaffold(
      appBar: brandAppBar(context, title: Text(k.single), actions: [
        if (canEdit)
          IconButton(tooltip: 'تعديل', onPressed: () => showUnitRecordEditor(context, r.kind, record: r), icon: const Icon(Icons.edit_outlined)),
        if (canDelete)
          IconButton(tooltip: 'حذف', icon: Icon(Icons.delete_outline_rounded, color: sem.danger), onPressed: delete),
      ]),
      body: PageBody(maxWidth: 1000, onRefresh: app.loadAll, children: [
        PageHeader(
          title: r.title,
          subtitle: [
            if (r.refNo.isNotEmpty) '${k.refLabel} ${r.refNo}',
            unitNames[r.unit] ?? '',
            if (r.projectId != null) pmProjectName(app, r.projectId),
          ].where((x) => x.isNotEmpty).join(' · '),
          icon: unitKindIcon(r.kind),
        ),
        Wrap(spacing: 6, runSpacing: 6, children: [
          ToneBadge(r.statusLabel, color: unitToneColor(context, k.statusTone(r.status))),
          if (k.hasLevels && r.level.isNotEmpty)
            ToneBadge('${k.levelLabel}: ${r.levelLabel}', color: unitToneColor(context, k.levelTone(r.level))),
          if (due != null) due,
          if (r.closedAt != null) ToneBadge('أُغلق ${pmDay(r.closedAt)}', color: sem.ok, icon: Icons.task_alt_rounded),
        ]),
        const SizedBox(height: 14),
        ResponsiveGrid(minItemWidth: 170, children: [
          StatCard(label: k.dateLabel, value: pmDay(r.recDate), icon: Icons.event_outlined),
          if (k.dueLabel != null)
            StatCard(
              label: k.dueLabel!,
              value: pmDay(r.dueDate),
              icon: Icons.schedule_rounded,
              color: r.overdue(today) ? sem.danger : null,
            ),
          if (k.progress)
            StatCard(
              label: 'نسبة الإنجاز',
              value: r.progress == null ? '—' : '${r.progress!.toStringAsFixed(r.progress! % 1 == 0 ? 0 : 1)}%',
              icon: Icons.trending_up_rounded,
            ),
          if (k.ownerLabel != null) StatCard(label: k.ownerLabel!, value: r.ownerText.isEmpty ? '—' : r.ownerText, icon: Icons.person_outline_rounded),
          StatCard(label: 'المرفقات', value: '${files.length}', sub: '${images.length} صورة', icon: Icons.attach_file_rounded),
        ]),
        const SizedBox(height: 14),
        if (parent != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: SectionCard(
              title: 'يتبع ${parent.spec?.single ?? ''}',
              icon: unitKindIcon(parent.kind),
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: UnitRecordTile(record: parent, today: today),
            ),
          ),
        if (details.isNotEmpty || r.notes.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: SectionCard(
              title: 'التفاصيل',
              icon: Icons.notes_rounded,
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                for (final (f, v) in details)
                  if (f.type == UnitFieldType.long)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(f.label, style: TextStyle(color: sem.muted, fontSize: 12.5)),
                        const SizedBox(height: 2),
                        Text(v, style: const TextStyle(height: 1.55)),
                      ]),
                    )
                  else
                    PmKv(f.label, v),
                if (r.notes.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('ملاحظات', style: TextStyle(color: sem.muted, fontSize: 12.5)),
                      const SizedBox(height: 2),
                      Text(r.notes, style: const TextStyle(height: 1.55)),
                    ]),
                  ),
              ]),
            ),
          ),
        for (final c in k.children)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: _ChildrenCard(parent: r, kind: c, today: today),
          ),
        SectionCard(
          title: 'الصور والمرفقات',
          icon: Icons.photo_library_outlined,
          trailing: canEdit
              ? FilledButton.tonalIcon(
                  onPressed: () => pickAndAttach(context, 'unit', r.id),
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
                    if (app.canRemoveUnitFile(r, f))
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
              if (!f.isImage) DocFileTile(file: f, canRemove: app.canRemoveUnitFile(r, f)),
            if (files.isEmpty) Text('لا مرفقات بعد. أرفق صور الموقع وملفات PDF.', style: TextStyle(color: sem.muted)),
          ]),
        ),
        const SizedBox(height: 10),
        Text('أضافه ${app.people[r.createdBy]?.displayName ?? '—'} · ${fmtDate(r.createdAt)}'
            '${r.updatedAt != null && r.createdAt != null && r.updatedAt!.difference(r.createdAt!).inMinutes > 1 ? ' · آخر تعديل ${fmtDate(r.updatedAt)}' : ''}',
            style: TextStyle(color: sem.muted, fontSize: 12)),
      ]),
    );
  }
}

/// السجلات التابعة لسجل (تقييمات مبنى، حالات عدم مطابقة لتدقيق، مخالفات جولة، ملاحظات محضر).
class _ChildrenCard extends StatelessWidget {
  const _ChildrenCard({required this.parent, required this.kind, required this.today});

  final UnitRecord parent;
  final UnitKind kind;
  final DateTime today;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final sem = Sem.of(context);
    final kids = app.units.childrenOf(parent.id, kind.key);
    final open = kids.where((x) => !x.isClosed).length;
    return SectionCard(
      title: kind.label,
      subtitle: kids.isEmpty ? null : '${kids.length} · منها $open مفتوحة',
      icon: unitKindIcon(kind.key),
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 6),
      trailing: app.canEditUnit(kind.unit)
          ? TextButton.icon(
              onPressed: () => showUnitRecordEditor(context, kind.key, parentId: parent.id, projectId: parent.projectId),
              icon: const Icon(Icons.add_rounded),
              label: Text('إضافة ${kind.single}'),
            )
          : null,
      child: kids.isEmpty
          ? Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text('لا ${kind.label} بعد.', style: TextStyle(color: sem.muted)),
            )
          : Column(children: [
              for (var i = 0; i < kids.length; i++) ...[
                if (i > 0) Divider(height: 1, color: sem.rule),
                UnitRecordTile(record: kids[i], today: today),
              ],
            ]),
    );
  }
}

// ---------------------------------------------------------------------
// لوحة القسم: مؤشرات كل وحدة، ومستخدموها، والمتأخر، وأحدث السجلات
// ---------------------------------------------------------------------
class UnitOverviewPage extends StatelessWidget {
  const UnitOverviewPage({super.key, required this.section});

  final String section;

  /// مؤشرات الوحدة: (العنوان، القيمة، الشرح، النبرة، الأيقونة)
  static List<(String, String, String?, UnitTone, IconData)> kpis(UnitStats s, String unit) {
    String pct(double? v) => v == null ? '—' : '${v.round()}%';
    String rate(double? v) => v == null ? '—' : '${(v * 100).round()}%';
    UnitTone bad(int n, [UnitTone t = UnitTone.danger]) => n > 0 ? t : UnitTone.ok;
    return switch (unit) {
      'heritage' => [
          ('المباني المسجّلة', '${s.buildings}', null, UnitTone.info, Icons.museum_outlined),
          ('بحالة سيئة أو خطرة', '${s.buildingsAtRisk}', 'حسب الحالة الإنشائية للمبنى', bad(s.buildingsAtRisk), Icons.warning_amber_rounded),
          ('قيد الترميم', '${s.underRestoration}', '${s.restored} مُرمَّم', UnitTone.wip, Icons.construction_rounded),
          ('تقييمات هذا العام', '${s.assessmentsThisYear}', null, UnitTone.neutral, Icons.fact_check_outlined),
        ],
      'planning' => [
          ('خطط قيد التنفيذ', '${s.activePlans}', null, UnitTone.info, Icons.flag_outlined),
          ('متوسط إنجازها', pct(s.avgActiveProgress), 'للخطط قيد التنفيذ', UnitTone.ok, Icons.trending_up_rounded),
          ('تجاوزت نهايتها', '${s.overduePlans}', 'ولم تُغلق', bad(s.overduePlans), Icons.schedule_rounded),
        ],
      'quality_assurance' => [
          ('تدقيقات هذا العام', '${s.auditsThisYear}', null, UnitTone.info, Icons.manage_search_rounded),
          ('مخططة أو جارية', '${s.auditsOpen}', null, UnitTone.wip, Icons.pending_actions_rounded),
          ('نتيجة غير مرضية', '${s.unsatisfactoryAudits}', 'من تدقيقات هذا العام', bad(s.unsatisfactoryAudits), Icons.thumb_down_alt_outlined),
        ],
      'follow_up' => [
          ('تكليفات قيد المتابعة', '${s.openTasks}', null, UnitTone.info, Icons.assignment_turned_in_outlined),
          ('متأخرة', '${s.overdueTasks}', 'تجاوزت موعدها', bad(s.overdueTasks), Icons.schedule_rounded),
          ('الإنجاز في الموعد', rate(s.onTimeRate), 'من التكليفات المنجزة ذات الموعد', UnitTone.ok, Icons.timer_outlined),
        ],
      'safety' => [
          ('أيام بلا حوادث', s.daysWithoutIncident?.toString() ?? '—', s.daysWithoutIncident == null ? 'لا حوادث مسجّلة' : 'منذ آخر حادث',
              UnitTone.ok, Icons.verified_user_outlined),
          ('جولات هذا الشهر', '${s.inspectionsThisMonth}', 'متوسط الالتزام ${pct(s.avgComplianceThisMonth)}', UnitTone.info,
              Icons.health_and_safety_outlined),
          ('حوادث هذا العام', '${s.incidentsThisYear}', '${s.nearMissesThisYear} وشيكة · ${s.lostDaysThisYear} يوم ضائع',
              bad(s.incidentsThisYear), Icons.personal_injury_outlined),
          ('مخالفات قائمة', '${s.openViolations}', '${s.overdueViolations} متأخرة المعالجة', bad(s.openViolations, UnitTone.wip),
              Icons.do_not_disturb_on_outlined),
        ],
      'receiving' => [
          ('محاضر مجدولة', '${s.scheduledHandovers}', null, UnitTone.info, Icons.event_available_outlined),
          ('استلامات هذا العام', '${s.handoversThisYear}', null, UnitTone.ok, Icons.handshake_outlined),
          ('ملاحظات قائمة', '${s.openPunch}', '${s.overduePunch} تجاوزت موعد الإصلاح', bad(s.openPunch, UnitTone.wip),
              Icons.checklist_rounded),
        ],
      'quality_control' => [
          ('اختبارات هذا الشهر', '${s.testsThisMonth}', '${s.pendingTests} بانتظار النتيجة', UnitTone.info, Icons.science_outlined),
          ('نسبة المطابقة', rate(s.passRate), 'من الاختبارات ذات النتيجة', UnitTone.ok, Icons.verified_outlined),
          ('عدم مطابقة مفتوحة', '${s.openNcr}', '${s.seriousOpenNcr} جسيمة أو حرجة', bad(s.openNcr, UnitTone.wip),
              Icons.report_gmailerrorred_outlined),
          ('إجراءات متأخرة', '${s.overdueNcr}', 'تجاوزت موعد الإجراء التصحيحي', bad(s.overdueNcr), Icons.schedule_rounded),
        ],
      'technical' => [
          ('مواد قيد المراجعة', '${s.materialsUnderReview}', '${s.overdueMaterials} تجاوزت موعد الرد',
              bad(s.overdueMaterials, UnitTone.wip), Icons.inventory_2_outlined),
          ('معتمدة هذا العام', '${s.materialsApprovedThisYear}', 'بملاحظات أو دونها', UnitTone.ok, Icons.task_alt_rounded),
          ('مرفوضة هذا العام', '${s.materialsRejectedThisYear}', null, bad(s.materialsRejectedThisYear, UnitTone.wip),
              Icons.block_rounded),
        ],
      _ => const [],
    };
  }

  /// صفحة الوحدة في القائمة (لفتحها من بطاقة المؤشرات).
  static int tabOf(String unit) => switch (unit) {
        'heritage' => 91,
        'planning' => 101,
        'quality_assurance' => 102,
        'follow_up' => 103,
        'safety' => 111,
        'receiving' => 121,
        'quality_control' => 122,
        'technical' => 64,
        _ => 0,
      };

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final sem = Sem.of(context);
    final name = unitSectionNames[section] ?? section;
    if (!app.v9Ready) return UnitsNotReady(title: name, icon: unitIcon(section));
    final today = _today();
    final stats = UnitStats(app.units, today);
    final units = unitsOfSection(section);
    final late = stats.overdueInSection(section);
    final recent = [for (final u in units) ...app.units.ofUnit(u)]
      ..sort((a, b) => (b.updatedAt ?? b.createdAt ?? DateTime(2000)).compareTo(a.updatedAt ?? a.createdAt ?? DateTime(2000)));
    return PageBody(maxWidth: 1180, onRefresh: app.loadAll, children: [
      PageHeader(
        title: name,
        subtitle: units.length > 1 ? units.map((u) => unitNames[u]).join(' · ') : 'لوحة القسم',
        icon: section == 'heritage' ? Icons.museum_outlined : unitIcon(units.first),
      ),
      for (final u in units) ...[
        SectionCard(
          title: unitNames[u]!,
          icon: unitIcon(u),
          subtitle: _membersText(app, u),
          trailing: TextButton(onPressed: () => app.setTab(tabOf(u)), child: const Text('فتح السجل')),
          child: ResponsiveGrid(minItemWidth: 190, children: [
            for (final (label, value, sub, tone, icon) in kpis(stats, u))
              StatCard(label: label, value: value, sub: sub, icon: icon, color: unitToneColor(context, tone), onTap: () => app.setTab(tabOf(u))),
          ]),
        ),
        const SizedBox(height: 14),
      ],
      SectionCard(
        title: 'تحتاج متابعة',
        subtitle: late.isEmpty ? null : '${late.length} سجل تجاوز موعده',
        icon: Icons.schedule_rounded,
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 6),
        child: late.isEmpty
            ? Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text('لا سجلات متأخرة.', style: TextStyle(color: sem.ok, fontWeight: FontWeight.w700)),
              )
            : Column(children: [
                for (var i = 0; i < late.length && i < 10; i++) ...[
                  if (i > 0) Divider(height: 1, color: sem.rule),
                  UnitRecordTile(record: late[i], today: today, showUnit: units.length > 1),
                ],
              ]),
      ),
      const SizedBox(height: 14),
      SectionCard(
        title: 'أحدث السجلات',
        icon: Icons.history_rounded,
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 6),
        child: recent.isEmpty
            ? Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text('لا سجلات بعد.', style: TextStyle(color: sem.muted)),
              )
            : Column(children: [
                for (var i = 0; i < recent.length && i < 6; i++) ...[
                  if (i > 0) Divider(height: 1, color: sem.rule),
                  UnitRecordTile(record: recent[i], today: today, showUnit: units.length > 1),
                ],
              ]),
      ),
    ]);
  }

  static String _membersText(AppState app, String unit) {
    final m = app.unitMembers(unit);
    if (m.isEmpty) return 'لا مستخدمين مُسنَدين بعد (يُسندهم المدير من لوحة التحكم)';
    return m.map((p) => p.unitHead ? '${p.displayName} (رئيس)' : p.displayName).join('، ');
  }
}
