import 'package:flutter/material.dart';

import '../app_state.dart';
import '../docs.dart';
import '../models.dart';
import '../pm.dart';
import '../print/export_dialog.dart' show ExportButton;
import '../services/doc_files.dart';
import '../ui/motion.dart';
import '../ui/slideshow.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';
import 'pm_common.dart';
import 'supervision.dart' show showReportEditor;

// =====================================================================
// قسم «المستندات الفنية»: المقايسات والمراسلات (ملفات PDF) والتصاميم (عرض صور متحرك ومسار تطوير).
// =====================================================================

/// تنبيه: قاعدة البيانات لم تُحدَّث بالترحيل 20 بعد.
class DocsNotReady extends StatelessWidget {
  const DocsNotReady({super.key, required this.title, this.icon = Icons.folder_copy_outlined});

  final String title;
  final IconData icon;

  @override
  Widget build(BuildContext context) => PageBody(children: [
        PageHeader(title: title, icon: icon),
        const InfoBanner(
          text: 'هذا القسم يعمل بعد تحديث قاعدة البيانات بالملف 20261114000020_documents_supervision.sql.',
          level: 'warning',
        ),
      ]);
}

IconData docKindIcon(String kind) => switch (kind) {
      'boq' => Icons.request_quote_outlined,
      'letter' => Icons.mark_email_read_outlined,
      _ => Icons.architecture_rounded,
    };

/// أنواع الملفات المسموحة لكل نوع: المقايسات والمراسلات PDF، والتصاميم صور ومعها PDF.
/// الأنواع المسموحة لكل مستند: المقايسات والمراسلات PDF، والتصاميم PDF وصور وفيديو (الفيديو بعد الترحيل 22).
({bool pdf, bool images, bool videos}) docAllowedFiles(String kind, {bool videos = false}) =>
    kind == 'design' ? (pdf: true, images: true, videos: videos) : (pdf: true, images: false, videos: false);

Color docStatusColor(Sem sem, DocItem i, DateTime today) {
  if (i.isLetter) {
    if (i.overdue(today)) return sem.danger;
    return switch (i.status) { 'open' => sem.wip, 'closed' => sem.ok, _ => sem.muted };
  }
  return switch (i.status) { 'approved' => sem.ok, 'review' => sem.wip, _ => sem.muted };
}

DateTime _today() {
  final n = DateTime.now();
  return DateTime(n.year, n.month, n.day);
}

/// «مقايسة جديدة» / «مراسلة جديدة» / «تصميم جديد»
String docNewLabel(String kind) => switch (kind) { 'boq' => 'مقايسة جديدة', 'letter' => 'مراسلة جديدة', _ => 'تصميم جديد' };

String docProjectName(AppState app, String? id) {
  if (id == null || id.isEmpty) return 'عام – على مستوى المكتب';
  return pmProjectName(app, id);
}

// ---------------------------------------------------------------------
// نماذج الإدخال
// ---------------------------------------------------------------------
Future<void> showDocEditor(BuildContext context, String kind, {DocItem? item, String? projectId}) async {
  final app = AppScope.read(context);
  final single = docKindSingle[kind] ?? 'مستند';
  final projects = [
    ('', 'عام – على مستوى المكتب'),
    for (final o in pmProjectOptions(app))
      if (app.canEditDoc(kind, o.$1) || o.$1 == item?.projectId) o,
  ];
  final letters = [
    ('', '—'),
    for (final l in app.docs.ofKind('letter'))
      if (l.id != item?.id) (l.id, [letterDirectionLabels[l.direction] ?? '', l.refNo, l.title].where((x) => x.isNotEmpty).join(' · ')),
  ];
  final generalAllowed = app.canEditDoc(kind, null);
  final sections = <PmSection>[
    PmSection('البيانات الأساسية', [
      PmField('project_id', 'العقد', PmKind.select,
          options: generalAllowed ? projects : projects.where((p) => p.$1.isNotEmpty).toList(), required: !generalAllowed, full: true),
      PmField('title', kind == 'letter' ? 'الموضوع' : 'العنوان', PmKind.text, required: true, max: 200, full: true),
      PmField('ref_no', switch (kind) { 'boq' => 'رقم المقايسة', 'letter' => 'رقم المراسلة', _ => 'رقم اللوحة / المشروع' }, PmKind.text,
          max: 60),
      PmField('doc_date', 'التاريخ', PmKind.date),
    ]),
    if (kind == 'boq')
      PmSection('المقايسة', [
        PmField('category', 'نوع المقايسة', PmKind.select, options: pmLabels(boqCategories, boqCategoryLabels), required: true),
        PmField('status', 'الحالة', PmKind.select, options: pmLabels(docStatuses, docStatusLabels), required: true),
        const PmField('amount', 'القيمة الإجمالية', PmKind.money),
        const PmField('party', 'الجهة المعدّة', PmKind.text, max: 120),
      ]),
    if (kind == 'letter')
      PmSection('المراسلة', [
        PmField('direction', 'الاتجاه', PmKind.select, options: pmLabels(letterDirections, letterDirectionLabels), required: true),
        PmField('category', 'التصنيف', PmKind.select, options: [('', 'دون تصنيف'), ...pmLabels(letterCategories, letterCategoryLabels)]),
        const PmField('party', 'الجهة (المرسل أو المرسل إليه)', PmKind.text, max: 120),
        PmField('status', 'الحالة', PmKind.select, options: pmLabels(letterStatuses, letterStatusLabels), required: true),
        const PmField('due_date', 'موعد الرد', PmKind.date, helper: 'للمراسلات التي تنتظر رداً'),
        PmField('reply_to', 'رداً على مراسلة', PmKind.select, options: letters, full: true),
      ]),
    if (kind == 'design')
      PmSection('التصميم', [
        PmField('category', 'التخصص', PmKind.select, options: pmLabels(designCategories, designCategoryLabels), required: true),
        PmField('status', 'الحالة', PmKind.select, options: pmLabels(docStatuses, docStatusLabels), required: true),
        const PmField('party', 'المصمم / الاستشاري', PmKind.text, max: 120),
      ]),
    PmSection('', [
      const PmField('notes', 'ملاحظات', PmKind.multiline, max: 2000),
      if (item == null) const PmField('rev_note', 'ملاحظة الإصدار الأول', PmKind.text, max: 300, full: true),
    ]),
  ];
  String? newRev;
  String? newItem;
  final ok = await showPmForm(
    context,
    title: item == null ? docNewLabel(kind) : 'تعديل ${item.title}',
    note: item == null
        ? (kind == 'design'
            ? 'بعد الحفظ تختار صور الإصدار الأول (وملفات PDF إن وجدت). كل تعديل لاحق على التصميم يُضاف «إصداراً جديداً» فيظهر في مسار التطوير.'
            : 'بعد الحفظ تختار ملف PDF للإصدار الأول. أي نسخة معدّلة لاحقاً تُضاف «إصداراً جديداً» ولا تحل محل القديمة.')
        : null,
    sections: sections,
    values: item?.toJson() ??
        {
          'project_id': projectId ?? (generalAllowed ? '' : (projects.length > 1 ? projects[1].$1 : '')),
          'doc_date': pmIso(DateTime.now()),
          'category': switch (kind) { 'boq' => 'estimate', 'design' => 'architectural', _ => '' },
          'status': kind == 'letter' ? 'open' : 'draft',
          'direction': 'in',
        },
    onSave: (d) async {
      final data = {...d, 'kind': kind};
      if (kind != 'letter') data.remove('direction');
      final r = await app.saveDocItem(item?.id, data);
      newItem = r.$1;
      newRev = r.$2;
    },
  );
  if (!ok || !context.mounted) return;
  if (item != null) {
    showToast(context, 'حُفظت التعديلات');
    return;
  }
  showToast(context, kind == 'design' ? 'سُجّل التصميم' : 'سُجّلت $single');
  final rev = newRev;
  if (rev != null) await pickAndAttach(context, 'doc', rev, kind: kind);
  final id = newItem;
  if (id != null && context.mounted) {
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => DocDetailPage(itemId: id)));
  }
}

/// اختيار الملفات ورفعها مع نافذة تقدّم.
Future<void> pickAndAttach(BuildContext context, String scope, String ownerId, {String kind = 'report'}) async {
  final app = AppScope.read(context);
  // المستندات حسب نوعها؛ والتقارير اليومية وسجلات الوحدات تقبل PDF والصور والفيديو
  final allowed = scope == 'doc' ? docAllowedFiles(kind, videos: app.v10Ready) : (pdf: true, images: true, videos: app.v10Ready);
  List<PickedDoc> files;
  try {
    files = await pickDocFiles(pdf: allowed.pdf, images: allowed.images, videos: allowed.videos);
  } catch (e) {
    if (context.mounted) showToast(context, friendlyError(e), error: true);
    return;
  }
  if (files.isEmpty || !context.mounted) return;
  final progress = ValueNotifier<int>(0);
  final total = files.length;
  final size = files.fold<int>(0, (s, f) => s + f.bytes.length);
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => PopScope(
      canPop: false,
      child: AlertDialog(
        title: const Text('رفع الملفات'),
        content: ValueListenableBuilder<int>(
          valueListenable: progress,
          builder: (_, done, __) => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('$done من $total · ${fmtBytes(size)}'),
            const SizedBox(height: 12),
            LinearProgressIndicator(value: total == 0 ? null : (done == 0 ? null : done / total)),
          ]),
        ),
      ),
    ),
  );
  String? error;
  try {
    await app.attachFiles(scope, ownerId, files, onProgress: (d) => progress.value = d);
  } catch (e) {
    error = friendlyError(e);
  }
  if (!context.mounted) return;
  Navigator.of(context, rootNavigator: true).pop();
  progress.dispose();
  showToast(context, error ?? (total == 1 ? 'أُرفق الملف' : 'أُرفقت $total ملفات'), error: error != null);
}

Future<void> showRevisionEditor(BuildContext context, DocItem item, {DocRevision? rev}) async {
  final app = AppScope.read(context);
  String? newId;
  final ok = await showPmForm(
    context,
    title: rev == null ? 'إصدار جديد: ${item.title}' : 'تعديل ${rev.label}',
    note: rev == null ? 'يُضاف الإصدار برقم يلي آخر إصدار، ثم تختار ملفاته. تبقى الإصدارات السابقة وملفاتها كما هي في مسار التطوير.' : null,
    sections: const [
      PmSection('', [
        PmField('rev_date', 'تاريخ الإصدار', PmKind.date, required: true),
        PmField('note', 'ما الذي تغيّر في هذا الإصدار؟', PmKind.multiline, max: 1000),
      ]),
    ],
    values: {'rev_date': pmIso(rev?.revDate ?? DateTime.now()), 'note': rev?.note ?? ''},
    onSave: (d) async => newId = await app.saveDocRevision(rev?.id, item.id, d),
  );
  if (!ok || !context.mounted) return;
  if (rev == null && newId != null) {
    showToast(context, 'أُضيف الإصدار');
    await pickAndAttach(context, 'doc', newId!, kind: item.kind);
  } else {
    showToast(context, 'حُفظ الإصدار');
  }
}

// ---------------------------------------------------------------------
// صفحة القائمة لكل نوع
// ---------------------------------------------------------------------
class DocsPage extends StatefulWidget {
  const DocsPage({super.key, required this.kind});

  final String kind;

  @override
  State<DocsPage> createState() => _DocsPageState();
}

class _DocsPageState extends State<DocsPage> {
  final _search = TextEditingController();
  String _project = '';
  String _category = '';
  String _status = '';
  String _direction = '';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final app = AppScope.read(context);
    final req = app.takeDocsProject();
    if (req != null) _project = req;
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final kind = widget.kind;
    final title = docKindLabels[kind]!;
    if (!app.v8Ready) return DocsNotReady(title: title, icon: docKindIcon(kind));
    final sem = Sem.of(context);
    final today = _today();
    final q = _search.text.trim();
    final all = app.docs.ofKind(kind);
    final list = all.where((i) {
      if (_project == '-' && i.projectId != null) return false;
      if (_project.isNotEmpty && _project != '-' && i.projectId != _project) return false;
      if (_category.isNotEmpty && i.category != _category) return false;
      if (_status == 'overdue') {
        if (!i.overdue(today)) return false;
      } else if (_status.isNotEmpty && i.status != _status) {
        return false;
      }
      if (_direction.isNotEmpty && i.direction != _direction) return false;
      return pmMatch(q, [i.title, i.refNo, i.party, i.notes, docProjectName(app, i.projectId)]);
    }).toList()
      ..sort((a, b) {
        final c = (b.docDate ?? DateTime(2000)).compareTo(a.docDate ?? DateTime(2000));
        return c != 0 ? c : (b.updatedAt ?? DateTime(2000)).compareTo(a.updatedAt ?? DateTime(2000));
      });

    final subtitle = switch (kind) {
      'boq' => '${all.length} مقايسة · ${all.where((i) => i.status == 'approved').length} معتمدة'
          '${all.any((i) => i.amount != null) ? ' · إجمالي المعتمد ${fmtMoney(all.where((i) => i.status == 'approved').fold<double>(0, (s, i) => s + (i.amount ?? 0)))} $currencyLabel' : ''}',
      'letter' => '${all.length} مراسلة · ${all.where((i) => i.direction == 'in').length} واردة · ${all.where((i) => i.direction == 'out').length} صادرة'
          ' · ${all.where((i) => i.status == 'open').length} بانتظار رد',
      _ => '${all.length} تصميم · ${app.docs.revisions.where((r) => all.any((i) => i.id == r.itemId)).length} إصداراً في مسارات التطوير',
    };
    final overdue = kind == 'letter' ? all.where((i) => i.overdue(today)).length : 0;

    final filters = [
      pmFilter('العقد', _project, [('', 'الكل'), ('-', 'العامة فقط'), ...pmProjectOptions(app)], (v) => setState(() => _project = v),
          width: 300),
      pmFilter(
          kind == 'design' ? 'التخصص' : (kind == 'boq' ? 'النوع' : 'التصنيف'),
          _category,
          [
            ('', 'الكل'),
            ...switch (kind) {
              'boq' => pmLabels(boqCategories, boqCategoryLabels),
              'letter' => pmLabels(letterCategories, letterCategoryLabels),
              _ => pmLabels(designCategories, designCategoryLabels),
            }
          ],
          (v) => setState(() => _category = v)),
      pmFilter(
          'الحالة',
          _status,
          [
            ('', 'الكل'),
            if (kind == 'letter') ...[...pmLabels(letterStatuses, letterStatusLabels), ('overdue', 'متأخر الرد')],
            if (kind != 'letter') ...pmLabels(docStatuses, docStatusLabels),
          ],
          (v) => setState(() => _status = v)),
      if (kind == 'letter')
        pmFilter('الاتجاه', _direction, [('', 'الكل'), ...pmLabels(letterDirections, letterDirectionLabels)],
            (v) => setState(() => _direction = v)),
    ];

    final actions = <Widget>[
      ExportButton(sourceId: 'docs:$kind', items: list),
      if (kind == 'boq' && app.v14Ready)
        OutlinedButton.icon(
          onPressed: () => app.setTab(66),
          icon: const Icon(Icons.calculate_outlined),
          label: const Text('إعداد من لائحة الأسعار'),
        ),
      if (app.canAddDoc(kind))
        FilledButton.icon(
          onPressed: () => showDocEditor(context, kind, projectId: _project.isNotEmpty && _project != '-' ? _project : null),
          icon: const Icon(Icons.add_rounded),
          label: Text(docNewLabel(kind)),
        ),
    ];

    if (kind == 'design') {
      return PageBody(maxWidth: 1240, onRefresh: app.loadAll, children: [
        PageHeader(title: title, subtitle: subtitle, icon: docKindIcon(kind), actions: actions),
        _searchField(),
        Wrap(spacing: 10, runSpacing: 10, children: filters),
        const SizedBox(height: 14),
        if (list.isEmpty)
          EmptyState(
            icon: Icons.architecture_rounded,
            title: all.isEmpty ? 'لا تصاميم بعد' : 'لا نتائج مطابقة',
            message: all.isEmpty ? 'أضف التصميم وارفع صوره؛ تتحرك الصور تلقائياً وتتوقف عند التأشير عليها، ويُحفظ كل تعديل إصداراً في مسار التطوير.' : null,
          )
        else
          ResponsiveGrid(minItemWidth: 340, spacing: 14, children: [
            for (final (i, d) in list.indexed) FadeSlideIn(delay: Duration(milliseconds: 40 * (i % 9)), child: DesignCard(item: d)),
          ]),
      ]);
    }

    return PmListScaffold(
      title: title,
      subtitle: subtitle,
      icon: docKindIcon(kind),
      actions: actions,
      top: [
        if (overdue > 0)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: InfoBanner(
              text: overdue == 1 ? 'مراسلة واحدة تجاوزت موعد الرد.' : '$overdue مراسلات تجاوزت موعد الرد.',
              level: 'warning',
              action: TextButton(onPressed: () => setState(() => _status = 'overdue'), child: const Text('عرضها')),
            ),
          ),
      ],
      search: _search,
      searchHint: kind == 'letter' ? 'بحث بالموضوع أو الرقم أو الجهة أو العقد' : 'بحث بالعنوان أو الرقم أو العقد',
      onSearch: () => setState(() {}),
      filters: filters,
      emptyTitle: all.isEmpty ? (kind == 'boq' ? 'لا مقايسات بعد' : 'لا مراسلات بعد') : 'لا نتائج مطابقة',
      emptyMessage: all.isEmpty
          ? (kind == 'boq'
              ? 'سجّل المقايسة وارفع ملفها PDF. كل تعديل عليها يُضاف إصداراً جديداً دون أن تضيع النسخ السابقة.'
              : 'سجّل الوارد والصادر وارفع ملف PDF لكل مراسلة، واربط الرد بالمراسلة التي يرد عليها.')
          : null,
      items: [
        for (final i in list)
          PmTile(
            code: i.refNo,
            leading: _KindIcon(kind: kind, direction: i.direction),
            meta: [docProjectName(app, i.projectId), pmDay(i.docDate), if (i.party.isNotEmpty) i.party].join(' · '),
            title: i.title,
            badges: [
              ToneBadge(i.statusLabel, color: docStatusColor(sem, i, today)),
              if (i.isLetter && i.direction != null) ToneBadge(letterDirectionLabels[i.direction] ?? '', color: sem.muted),
              if (i.category.isNotEmpty) ToneBadge(i.categoryLabel, color: sem.muted),
              if (i.overdue(today))
                ToneBadge('تجاوز موعد الرد ${pmDay(i.dueDate)}', color: sem.danger, icon: Icons.event_busy_outlined)
              else if (i.isLetter && i.status == 'open' && i.dueDate != null)
                ToneBadge('الرد حتى ${pmDay(i.dueDate)}', color: sem.wip),
              if (i.amount != null) Text('${fmtMoney(i.amount)} $currencyLabel', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5)),
              _RevFilesBadge(item: i),
            ],
            onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => DocDetailPage(itemId: i.id))),
          ),
      ],
    );
  }

  Widget _searchField() => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: TextField(
          controller: _search,
          onChanged: (_) => setState(() {}),
          decoration: fieldDeco('بحث بالعنوان أو الرقم أو العقد', prefixIcon: const Icon(Icons.search_rounded)),
        ),
      );
}

class _KindIcon extends StatelessWidget {
  const _KindIcon({required this.kind, this.direction});

  final String kind;
  final String? direction;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final icon = kind == 'letter'
        ? switch (direction) { 'out' => Icons.outbox_rounded, 'internal' => Icons.swap_horiz_rounded, _ => Icons.move_to_inbox_rounded }
        : docKindIcon(kind);
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(color: cs.primaryContainer, borderRadius: BorderRadius.circular(11)),
      child: Icon(icon, size: 21, color: cs.onPrimaryContainer),
    );
  }
}

class _RevFilesBadge extends StatelessWidget {
  const _RevFilesBadge({required this.item});

  final DocItem item;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final sem = Sem.of(context);
    final revs = app.docs.revisionsOf(item.id);
    final files = app.docs.currentFiles(item.id);
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(Icons.history_rounded, size: 15, color: sem.muted),
      const SizedBox(width: 3),
      Text('${revs.isEmpty ? 1 : revs.last.revNo}', style: TextStyle(color: sem.muted, fontSize: 12)),
      const SizedBox(width: 8),
      Icon(files.isEmpty ? Icons.attach_file_rounded : Icons.picture_as_pdf_outlined, size: 15, color: files.isEmpty ? sem.danger : sem.muted),
      const SizedBox(width: 3),
      Text(files.isEmpty ? 'بلا ملف' : '${files.length}', style: TextStyle(color: files.isEmpty ? sem.danger : sem.muted, fontSize: 12)),
    ]);
  }
}

/// بطاقة تصميم: عرض متحرك لصور مسار تطويره (كل الإصدارات) يتوقف عند التأشير.
class DesignCard extends StatelessWidget {
  const DesignCard({super.key, required this.item});

  final DocItem item;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final sem = Sem.of(context);
    final t = Theme.of(context).textTheme;
    final revs = app.docs.revisionsOf(item.id);
    final slides = [
      for (final (r, f) in app.docs.imagesAcrossRevisions(item.id))
        Slide(file: f, caption: f.name, badge: r.label, date: pmDay(r.revDate)),
    ];
    void open() => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => DocDetailPage(itemId: item.id)));
    return Container(
      decoration: cardDecoration(context),
      clipBehavior: Clip.antiAlias,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: open,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              AutoSlideshow(slides: slides, onOpen: (_) => open()),
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 10, 4, 2),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(item.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 2),
                  Text([docProjectName(app, item.projectId), if (item.party.isNotEmpty) item.party].join(' · '),
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: sem.muted, fontSize: 12.5)),
                  const SizedBox(height: 8),
                  Wrap(spacing: 6, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                    ToneBadge(item.statusLabel, color: docStatusColor(sem, item, _today())),
                    ToneBadge(item.categoryLabel, color: sem.muted),
                    RevisionPath(revisions: revs, compact: true),
                  ]),
                ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

/// مسار التطوير المختصر: الإصدار 1 ← 2 ← 3 (الأحدث مميز).
class RevisionPath extends StatelessWidget {
  const RevisionPath({super.key, required this.revisions, this.compact = false});

  final List<DocRevision> revisions;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final sem = Sem.of(context);
    final cs = Theme.of(context).colorScheme;
    if (revisions.isEmpty) return const SizedBox.shrink();
    final shown = revisions.length > 6 ? revisions.sublist(revisions.length - 6) : revisions;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      if (revisions.length > shown.length) Text('… ', style: TextStyle(color: sem.muted)),
      for (var i = 0; i < shown.length; i++) ...[
        if (i > 0) Icon(Icons.arrow_left_rounded, size: 16, color: sem.muted),
        Container(
          padding: EdgeInsets.symmetric(horizontal: compact ? 6 : 8, vertical: 2),
          decoration: BoxDecoration(
            color: i == shown.length - 1 ? cs.primary : sem.surface2,
            borderRadius: BorderRadius.circular(99),
          ),
          child: Text('${shown[i].revNo}',
              style: TextStyle(
                  fontSize: 11.5, fontWeight: FontWeight.w800, color: i == shown.length - 1 ? cs.onPrimary : sem.muted)),
        ),
      ],
    ]);
  }
}

// ---------------------------------------------------------------------
// صفحة المستند: البيانات، ومسار التطوير بإصداراته وملفاته
// ---------------------------------------------------------------------
class DocDetailPage extends StatelessWidget {
  const DocDetailPage({super.key, required this.itemId});

  final String itemId;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final sem = Sem.of(context);
    DocItem? found;
    for (final i in app.docs.items) {
      if (i.id == itemId) found = i;
    }
    final item = found;
    if (item == null) {
      return Scaffold(
        appBar: brandAppBar(context, title: const Text('المستند')),
        body: const EmptyState(title: 'المستند غير موجود', message: 'ربما حُذف.', icon: Icons.search_off_rounded),
      );
    }
    final today = _today();
    final revs = app.docs.revisionsOf(item.id);
    final canEdit = app.canEditDoc(item.kind, item.projectId);
    final images = app.docs.imagesAcrossRevisions(item.id);
    final slides = [for (final (r, f) in images) Slide(file: f, caption: f.name, badge: r.label, date: pmDay(r.revDate))];
    DocItem? replyOf;
    if (item.replyTo != null) {
      for (final i in app.docs.items) {
        if (i.id == item.replyTo) replyOf = i;
      }
    }
    final replies = item.isLetter ? app.docs.repliesTo(item.id) : const <DocItem>[];

    return Scaffold(
      appBar: brandAppBar(context, title: Text(docKindSingle[item.kind] ?? 'المستند'), actions: [
        if (canEdit)
          IconButton(tooltip: 'تعديل البيانات', onPressed: () => showDocEditor(context, item.kind, item: item), icon: const Icon(Icons.edit_outlined)),
        if (app.isDirector)
          IconButton(
            tooltip: 'حذف المستند',
            icon: Icon(Icons.delete_outline_rounded, color: sem.danger),
            onPressed: () async {
              final ok = await confirmDialog(context,
                  title: 'حذف «${item.title}»',
                  message: 'يُحذف المستند بكل إصداراته وملفاته نهائياً من المخزن، ويبقى أثره في سجل التدقيق.',
                  confirmLabel: 'حذف',
                  danger: true);
              if (!ok || !context.mounted) return;
              try {
                await app.deleteDocItem(item.id);
                if (context.mounted) {
                  Navigator.of(context).pop();
                  showToast(context, 'حُذف المستند');
                }
              } catch (e) {
                if (context.mounted) showToast(context, friendlyError(e), error: true);
              }
            },
          ),
      ]),
      body: PageBody(maxWidth: 1100, onRefresh: app.loadAll, children: [
        PageHeader(
          title: item.title,
          subtitle: [docProjectName(app, item.projectId), if (item.refNo.isNotEmpty) 'رقم ${item.refNo}', pmDay(item.docDate)].join(' · '),
          icon: docKindIcon(item.kind),
        ),
        Wrap(spacing: 6, runSpacing: 6, children: [
          ToneBadge(item.statusLabel, color: docStatusColor(sem, item, today)),
          if (item.isLetter && item.direction != null) ToneBadge(letterDirectionLabels[item.direction] ?? '', color: sem.muted),
          if (item.category.isNotEmpty) ToneBadge(item.categoryLabel, color: sem.muted),
          if (item.overdue(today)) ToneBadge('تجاوز موعد الرد', color: sem.danger, icon: Icons.event_busy_outlined),
        ]),
        const SizedBox(height: 16),
        if (item.kind == 'design' && slides.isNotEmpty) ...[
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 900),
              child: AutoSlideshow(slides: slides, aspectRatio: 16 / 9, fit: BoxFit.contain, interval: const Duration(seconds: 5)),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 6, bottom: 16),
            child: Text('تتنقل الصور تلقائياً عبر كل الإصدارات، وتتوقف حين تؤشر عليها بالماوس أو تضغط عليها مطولاً. اضغط للتكبير.',
                textAlign: TextAlign.center, style: TextStyle(color: sem.muted, fontSize: 12.5)),
          ),
        ],
        SectionCard(
          title: 'البيانات',
          icon: Icons.info_outline_rounded,
          child: Column(children: [
            for (final (k, v) in [
              ('العقد', docProjectName(app, item.projectId)),
              (item.isLetter ? 'الجهة' : (item.kind == 'design' ? 'المصمم / الاستشاري' : 'الجهة المعدّة'), item.party),
              if (item.amount != null) ('القيمة الإجمالية', '${fmtMoney(item.amount)} $currencyLabel'),
              if (item.dueDate != null) ('موعد الرد', pmDay(item.dueDate)),
              ('ملاحظات', item.notes),
              ('آخر تحديث', fmtDate(item.updatedAt)),
            ])
              if (v.trim().isNotEmpty) PmKv(k, v),
            if (replyOf != null)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.reply_rounded),
                title: Text('رداً على: ${replyOf.title}'),
                subtitle: Text([replyOf.refNo, pmDay(replyOf.docDate)].where((x) => x.isNotEmpty && x != '—').join(' · ')),
                onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => DocDetailPage(itemId: replyOf!.id))),
              ),
            for (final r in replies)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.subdirectory_arrow_left_rounded),
                title: Text('الرد: ${r.title}'),
                subtitle: Text([letterDirectionLabels[r.direction] ?? '', r.refNo, pmDay(r.docDate)].where((x) => x.isNotEmpty && x != '—').join(' · ')),
                onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => DocDetailPage(itemId: r.id))),
              ),
          ]),
        ),
        const SizedBox(height: 14),
        SectionCard(
          title: 'مسار التطوير',
          subtitle: 'كل تعديل يُحفظ إصداراً مستقلاً بتاريخه وملاحظته وملفاته. الأحدث في الأعلى.',
          icon: Icons.timeline_rounded,
          trailing: canEdit
              ? FilledButton.tonalIcon(
                  onPressed: () => showRevisionEditor(context, item), icon: const Icon(Icons.add_rounded), label: const Text('إصدار جديد'))
              : null,
          child: Column(children: [
            for (final (i, r) in revs.reversed.indexed) RevisionBlock(item: item, rev: r, latest: i == 0, last: i == revs.length - 1),
          ]),
        ),
      ]),
    );
  }
}

/// كتلة إصدار في مسار التطوير: خط زمني، والملاحظة، والملفات، والإجراءات.
class RevisionBlock extends StatelessWidget {
  const RevisionBlock({super.key, required this.item, required this.rev, required this.latest, required this.last});

  final DocItem item;
  final DocRevision rev;
  final bool latest;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final sem = Sem.of(context);
    final cs = Theme.of(context).colorScheme;
    final files = app.docs.filesOfRevision(rev.id);
    final canEdit = app.canEditDoc(item.kind, item.projectId);
    final images = [for (final f in files) if (f.isImage) f];
    final slides = [for (final f in images) Slide(file: f, caption: f.name, badge: rev.label, date: pmDay(rev.revDate))];
    return Stack(children: [
      if (!last) PositionedDirectional(start: 6, top: 20, bottom: 0, child: Container(width: 2, color: sem.rule)),
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 14,
          height: 14,
          margin: const EdgeInsets.only(top: 4),
          decoration: BoxDecoration(
            color: latest ? cs.primary : sem.surface,
            shape: BoxShape.circle,
            border: Border.all(color: latest ? cs.primary : sem.muted, width: 2),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Padding(
            padding: EdgeInsets.only(bottom: last ? 0 : 18),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                Text(rev.label, style: const TextStyle(fontWeight: FontWeight.w800)),
                if (latest) ToneBadge('الأحدث', color: cs.primary),
                Text(pmDay(rev.revDate), style: TextStyle(color: sem.muted, fontSize: 12.5)),
                Text('· ${app.people[rev.createdBy]?.displayName ?? ''}', style: TextStyle(color: sem.muted, fontSize: 12.5)),
              ]),
              if (rev.note.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Text(rev.note, style: const TextStyle(height: 1.45))),
              const SizedBox(height: 8),
              if (images.isNotEmpty)
                Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final (i, f) in images.indexed)
                    Stack(children: [
                      InkWell(
                        borderRadius: BorderRadius.circular(10),
                        onTap: () => showSlideViewer(context, slides, i, actions: (s) => _fileActions(context, s.file)),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: SizedBox(width: 132, height: 88, child: DocImage(file: f)),
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
              for (final f in files)
                if (!f.isImage) DocFileTile(file: f, canRemove: app.canRemoveOwn(f.createdBy, f.createdAt)),
              if (files.isEmpty) Text('لا ملفات في هذا الإصدار.', style: TextStyle(color: sem.muted, fontSize: 12.5)),
              if (canEdit || app.canRemoveOwn(rev.createdBy, rev.createdAt))
                Wrap(spacing: 4, children: [
                  if (canEdit)
                    TextButton.icon(
                      onPressed: () => pickAndAttach(context, 'doc', rev.id, kind: item.kind),
                      icon: const Icon(Icons.attach_file_rounded, size: 18),
                      label: Text(item.kind == 'design' ? 'إرفاق صور أو PDF' : 'إرفاق PDF'),
                    ),
                  if (canEdit)
                    TextButton.icon(
                      onPressed: () => showRevisionEditor(context, item, rev: rev),
                      icon: const Icon(Icons.edit_note_rounded, size: 18),
                      label: const Text('تعديل الملاحظة'),
                    ),
                  if (app.canRemoveOwn(rev.createdBy, rev.createdAt) && app.docs.revisionsOf(item.id).length > 1)
                    TextButton.icon(
                      style: TextButton.styleFrom(foregroundColor: sem.danger),
                      onPressed: () async {
                        final ok = await confirmDialog(context,
                            title: 'حذف ${rev.label}',
                            message: 'يُحذف الإصدار وملفاته نهائياً. يبقى رقمه محجوزاً حتى لا يختلط بإصدار لاحق.',
                            confirmLabel: 'حذف',
                            danger: true);
                        if (!ok || !context.mounted) return;
                        try {
                          await app.deleteDocRevision(rev.id);
                          if (context.mounted) showToast(context, 'حُذف ${rev.label}');
                        } catch (e) {
                          if (context.mounted) showToast(context, friendlyError(e), error: true);
                        }
                      },
                      icon: const Icon(Icons.delete_outline_rounded, size: 18),
                      label: const Text('حذف الإصدار'),
                    ),
                ]),
            ]),
          ),
        ),
      ]),
    ]);
  }
}

List<Widget> _fileActions(BuildContext context, DocFile f) {
  final app = AppScope.read(context);
  return [
    IconButton(
      tooltip: 'فتح في عارض الجهاز',
      onPressed: () async {
        try {
          await openDocExternally(await app.signedUrls.of(f.path));
        } catch (e) {
          if (context.mounted) showToast(context, friendlyError(e), error: true);
        }
      },
      icon: const Icon(Icons.open_in_new_rounded),
    ),
    IconButton(
      tooltip: 'حفظ نسخة على الجهاز',
      onPressed: () async {
        try {
          await saveDocCopy(app.client, f.path, f.name, f.mime);
          if (context.mounted) showToast(context, 'حُفظت نسخة من ${f.name}');
        } catch (e) {
          if (context.mounted) showToast(context, friendlyError(e), error: true);
        }
      },
      icon: const Icon(Icons.download_rounded),
    ),
  ];
}

Future<void> removeDocFile(BuildContext context, DocFile file) async {
  final app = AppScope.read(context);
  final ok = await confirmDialog(context, title: 'إزالة ${file.name}', message: 'يُحذف الملف من المخزن نهائياً.', confirmLabel: 'إزالة', danger: true);
  if (!ok || !context.mounted) return;
  try {
    await app.deleteDocFile(file.id);
    if (context.mounted) showToast(context, 'أُزيل الملف');
  } catch (e) {
    if (context.mounted) showToast(context, friendlyError(e), error: true);
  }
}

/// سطر ملف: فتح في عارض الجهاز، وحفظ نسخة، وإزالة (للمدير أو لمن رفعه خلال 24 ساعة).
class DocFileTile extends StatelessWidget {
  const DocFileTile({super.key, required this.file, this.canRemove = false, this.dense = false});

  final DocFile file;
  final bool canRemove;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final sem = Sem.of(context);
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      visualDensity: dense ? VisualDensity.compact : null,
      leading: Icon(file.isPdf ? Icons.picture_as_pdf_rounded : (file.isVideo ? Icons.movie_rounded : Icons.image_outlined),
          color: file.isPdf ? sem.danger : (file.isVideo ? sem.wip : sem.muted)),
      title: Text(file.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text('${fmtBytes(file.sizeBytes)} · ${app.people[file.createdBy]?.displayName ?? ''}'),
      onTap: file.isPdf || file.isVideo
          ? () async {
              try {
                await openDocExternally(await app.signedUrls.of(file.path));
              } catch (e) {
                if (context.mounted) showToast(context, friendlyError(e), error: true);
              }
            }
          : null,
      trailing: Wrap(children: [
        ..._fileActions(context, file),
        if (canRemove)
          IconButton(tooltip: 'إزالة الملف', icon: Icon(Icons.close_rounded, color: sem.danger), onPressed: () => removeDocFile(context, file)),
      ]),
    );
  }
}

// ---------------------------------------------------------------------
// مؤشر المساحة (للمدير)
// ---------------------------------------------------------------------
class StorageGauge extends StatefulWidget {
  const StorageGauge({super.key});

  @override
  State<StorageGauge> createState() => _StorageGaugeState();
}

class _StorageGaugeState extends State<StorageGauge> {
  Future<(int, int, int, int)>? _f;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _f ??= AppScope.read(context).storageUsage();
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final sem = Sem.of(context);
    return SectionCard(
      title: 'مساحة التخزين',
      subtitle: 'ملفات المستندات والتقارير مع ملفات الإصدارات، من حد الخطة الحالية.',
      icon: Icons.cloud_outlined,
      trailing: app.isDirector
          ? TextButton(
              onPressed: () async {
                try {
                  final n = await app.cleanOrphanFiles();
                  if (!context.mounted) return;
                  showToast(context, n == 0 ? 'لا ملفات يتيمة' : 'نُظّف $n ملفاً يتيماً');
                  setState(() => _f = app.storageUsage());
                } catch (e) {
                  if (context.mounted) showToast(context, friendlyError(e), error: true);
                }
              },
              child: const Text('تنظيف'),
            )
          : null,
      child: FutureBuilder<(int, int, int, int)>(
        future: _f,
        builder: (context, snap) {
          final v = snap.data;
          if (v == null) return const LinearProgressIndicator();
          final (docsB, other, n, limit) = v;
          final used = docsB + other;
          final ratio = limit <= 0 ? 0.0 : (used / limit).clamp(0.0, 1.0);
          final color = ratio >= 0.85 ? sem.danger : (ratio >= 0.6 ? sem.wip : sem.ok);
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            AnimatedMeter(value: ratio, color: color, height: 10),
            const SizedBox(height: 8),
            Text('${fmtBytes(used)} من ${fmtBytes(limit)} (${pctText(ratio)}) · المستندات والتقارير ${fmtBytes(docsB)} في $n ملفاً',
                style: TextStyle(color: sem.muted, fontSize: 12.5)),
            if (ratio >= 0.85)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: InfoBanner(text: 'المساحة توشك على النفاد. رقِّ الخطة من لوحة Supabase أو احذف الملفات غير اللازمة.', level: 'warning'),
              ),
          ]);
        },
      ),
    );
  }
}

/// صفحة «مساحة التخزين»: المؤشر وشرح حدود الملفات.
class StoragePage extends StatelessWidget {
  const StoragePage({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    if (!app.v8Ready) return const DocsNotReady(title: 'مساحة التخزين', icon: Icons.cloud_outlined);
    final sem = Sem.of(context);
    final byKind = {
      for (final k in docKinds)
        k: app.docs.files
            .where((f) => f.revisionId != null && app.docs.items.any((i) => i.kind == k && app.docs.revisionsOf(i.id).any((r) => r.id == f.revisionId)))
            .fold<int>(0, (s, f) => s + f.sizeBytes),
    };
    final reports = app.docs.files.where((f) => f.reportId != null).fold<int>(0, (s, f) => s + f.sizeBytes);
    return PageBody(maxWidth: 900, onRefresh: app.loadAll, children: [
      const PageHeader(
        title: 'مساحة التخزين',
        subtitle: 'ملفات المستندات والتقارير في مخزن خاص لا يُفتح إلا من داخل المنظومة، بحد 20 ميجابايت للملف.',
        icon: Icons.cloud_rounded,
      ),
      const StorageGauge(),
      const SizedBox(height: 14),
      SectionCard(
        title: 'التوزيع',
        icon: Icons.pie_chart_outline_rounded,
        child: Column(children: [
          for (final k in docKinds) PmKv(docKindLabels[k]!, fmtBytes(byKind[k])),
          PmKv('التقارير اليومية', fmtBytes(reports)),
        ]),
      ),
      const SizedBox(height: 14),
      Text('الصور تُصغَّر وتُضغط تلقائياً قبل رفعها، فتبقى المساحة لملفات PDF. التفاصيل في الفصل 17 من دليل الاستخدام.',
          style: TextStyle(color: sem.muted, fontSize: 12.5)),
    ]);
  }
}

/// بطاقة في صفحة العقد: مستنداته الفنية وتقاريره اليومية، مع فتحها مصفّاة على العقد.
class ContractDocsCard extends StatelessWidget {
  const ContractDocsCard({super.key, required this.project});

  final Project project;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final sem = Sem.of(context);
    final items = app.docs.itemsOfProject(project.id);
    final reports = app.docs.reportsOfProject(project.id);
    final today = _today();
    final last = reports.isEmpty ? null : reports.first;
    final openLetters = items.where((i) => i.isLetter && i.status == 'open').length;
    final late = items.where((i) => i.overdue(today)).length;
    void go(int tab) {
      Navigator.of(context).popUntil((r) => r.isFirst);
      app.openDocsTab(tab, projectId: project.id);
    }

    Widget tile(IconData icon, String label, String value, int tab, {Color? color}) => Expanded(
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => go(tab),
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: sem.surface2, borderRadius: BorderRadius.circular(12)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(icon, size: 20, color: color ?? sem.muted),
                const SizedBox(height: 6),
                Text(value, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17, color: color)),
                Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: sem.muted, fontSize: 11.5)),
              ]),
            ),
          ),
        );

    return SectionCard(
      title: 'المستندات والتقارير اليومية',
      subtitle: last == null
          ? 'لا تقرير يومي لهذا العقد بعد.'
          : 'آخر تقرير يومي ${pmDay(last.reportDate)} · ${last.workers ?? '—'} عامل${last.hasIssues ? ' · فيه معوقات' : ''}',
      icon: Icons.folder_copy_outlined,
      trailing: app.canEditReport(project.id)
          ? FilledButton.tonalIcon(
              onPressed: () => showReportEditor(context, projectId: project.id),
              icon: const Icon(Icons.add_rounded),
              label: const Text('تقرير اليوم'),
            )
          : null,
      child: Row(children: [
        tile(Icons.request_quote_outlined, 'مقايسة', '${items.where((i) => i.kind == 'boq').length}', 60),
        const SizedBox(width: 8),
        tile(Icons.mark_email_read_outlined, late > 0 ? 'متأخرة الرد' : 'بانتظار رد', late > 0 ? '$late' : '$openLetters', 61,
            color: late > 0 ? sem.danger : null),
        const SizedBox(width: 8),
        tile(Icons.architecture_outlined, 'تصميم', '${items.where((i) => i.kind == 'design').length}', 62),
        const SizedBox(width: 8),
        tile(Icons.assignment_outlined, 'تقرير يومي', '${reports.length}', 70),
      ]),
    );
  }
}
