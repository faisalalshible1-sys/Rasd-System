import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_state.dart';
import '../models.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';
import 'home_shell.dart' show Tabs, layoutPagesFor;
import 'hub.dart';

// =====================================================================
// الأفكار والتطوير (الفصل 31): مفتاح تطوير المنظومة وتحسينها.
//   • تُكتب الفكرة من أي صفحة في أي قسم بزر «فكرة» في أعلاها، فتُحفظ بقسمها وصفحتها.
//   • لكل قسم صفحة «الأفكار والتطوير» في ذيل قائمته بأفكاره وخريطتها على صفحاته،
//     والصفحة العامة (في الدورة المستندية) خريطة لكل الأقسام.
//   • تتحول كل فكرة إلى مهمة تطوير في مستودع المشروع، ويدير المدير حالتها وأولويتها ومكانها ويرد عليها.
// =====================================================================

/// اسم الصفحة كما يراه المستخدم الآن (بعد تخصيص المدير)، أو الاسم المحفوظ مع الفكرة.
String _pageName(AppState app, int id, String fallback) {
  final custom = (app.layout.pages[id]?.label ?? '').trim();
  return custom.isNotEmpty ? custom : fallback;
}

/// صفحات قسم للاختيار في نافذة الفكرة: (الرقم، الاسم).
List<(int, String)> _pagesOf(AppState app, String section) => [
      for (final p in layoutPagesFor(app, section, app.layout.movedPages)) (p.id, _pageName(app, p.id, p.label)),
    ];

/// نافذة فكرة جديدة مربوطة بقسم وصفحة (تُفتح من زر «فكرة» في كل صفحة، أو من صفحة الأفكار).
Future<void> showIdeaComposer(BuildContext context, {String? section, int? pageId, String pageLabel = ''}) async {
  final app = AppScope.read(context);
  final res = await showDialog<_IdeaDraft>(
    context: context,
    builder: (_) => _IdeaDialog(app: app, section: section, pageId: pageId, pageLabel: pageLabel),
  );
  if (res == null || !context.mounted) return;
  try {
    await app.submitIdea(
      title: res.title,
      body: res.body,
      category: res.category,
      priority: res.priority,
      section: res.section,
      pageId: res.pageId,
      pageLabel: res.pageLabel,
    );
    if (context.mounted) showToast(context, 'وصلت فكرتك، وستُضاف إلى مهام التطوير');
  } catch (e) {
    if (context.mounted) showToast(context, friendlyError(e), error: true);
  }
}

class IdeasPage extends StatefulWidget {
  const IdeasPage({super.key, this.section});

  /// قسم الصفحة (null = الصفحة العامة بخريطة كل الأقسام).
  final String? section;

  @override
  State<IdeasPage> createState() => _IdeasPageState();
}

class _IdeasPageState extends State<IdeasPage> {
  String _status = 'open';

  /// تصفية القسم في الصفحة العامة: null = كل الأقسام، '' = الأفكار العامة.
  String? _section;

  /// تصفية الصفحة داخل القسم: null = كل الصفحات، -1 = للقسم كله.
  int? _page;
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _section = widget.section;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_focused) return;
    _focused = true;
    final f = AppScope.read(context).takeIdeasFocus();
    if (f != null && widget.section == null) _section = f;
  }

  Color _statusColor(Sem sem, BuildContext context, String s) => switch (s) {
        'done' => sem.ok,
        'in_progress' => sem.wip,
        'planned' => Theme.of(context).colorScheme.primary,
        'rejected' => sem.muted,
        _ => sem.danger,
      };

  Color _priorityColor(Sem sem, String p) => switch (p) {
        'urgent' => sem.danger,
        'high' => sem.wip,
        'low' => sem.muted,
        _ => sem.ok,
      };

  Future<void> _respond(AppState app, Idea i) async {
    final text = await textInputDialog(context,
        title: 'رد على الفكرة', label: 'الرد (يصل لصاحب الفكرة)', confirmLabel: 'حفظ', initial: i.response);
    if (text == null) return;
    try {
      await app.updateIdea(i.id, response: text);
      if (mounted) showToast(context, 'حُفظ الرد');
    } catch (e) {
      if (mounted) showToast(context, friendlyError(e), error: true);
    }
  }

  Future<void> _move(AppState app, Idea i) async {
    final res = await showDialog<(String?, int?, String)>(
      context: context,
      builder: (_) => _PlaceDialog(app: app, title: 'نقل الفكرة', section: i.section, pageId: i.pageId, pageLabel: i.pageLabel),
    );
    if (res == null) return;
    try {
      await app.moveIdea(i.id, section: res.$1, pageId: res.$2, pageLabel: res.$3);
      if (mounted) showToast(context, res.$1 == null ? 'صارت الفكرة عامة للمنظومة' : 'نُقلت الفكرة إلى ${sectionTitle(app, res.$1!)}');
    } catch (e) {
      if (mounted) showToast(context, friendlyError(e), error: true);
    }
  }

  /// يفتح مكان الفكرة: صفحتها إن وُجدت في قائمة قسمها، وإلا القسم.
  void _goTo(AppState app, Idea i) {
    final s = i.section;
    if (s == null) return;
    final pid = i.pageId;
    if (pid != null && _pagesOf(app, s).any((p) => p.$1 == pid)) {
      app.setTab(pid);
    } else {
      app.openSection(s);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final sem = Sem.of(context);
    final canSubmit = app.isDirector || app.settings.feature('ideas_for_all');
    final fixed = widget.section;
    final sec = fixed ?? _section;

    bool inSection(Idea i) => sec == null || (sec.isEmpty ? i.section == null : i.section == sec);
    bool inPage(Idea i) => _page == null || (_page == -1 ? i.pageId == null : i.pageId == _page);
    bool inStatus(Idea i) => _status.isEmpty || (_status == 'open' ? i.isOpen : i.status == _status);
    final scoped = [for (final i in app.ideas) if (inSection(i) && inPage(i)) i];
    final ideas = [for (final i in scoped) if (inStatus(i)) i];
    int count(String s) => scoped.where((i) => s.isEmpty || (s == 'open' ? i.isOpen : i.status == s)).length;

    final title = fixed == null ? 'الأفكار والتطوير' : 'الأفكار والتطوير · ${sectionTitle(app, fixed)}';
    final subtitle = fixed == null
        ? 'مفتاح تطوير المنظومة وتحسينها: اكتب فكرة أو خللاً من أي صفحة بزر «فكرة» في أعلاها، فتُحفظ بقسمها وصفحتها. '
            'تتحول كل فكرة تلقائياً إلى مهمة تطوير في مستودع المشروع، ويُتابَع تنفيذها هنا.'
        : 'أفكار تطوير هذا القسم وصفحاته وتحسينها. اكتب فكرة من أي صفحة في القسم بزر «فكرة» في أعلاها، أو من هنا.';

    return PageBody(
      onRefresh: app.loadAll,
      maxWidth: 1040,
      children: [
        PageHeader(
          icon: Icons.lightbulb_outline_rounded,
          title: title,
          subtitle: subtitle,
          actions: [
            if (canSubmit)
              FilledButton.icon(
                onPressed: () {
                  final s = sec == null || sec.isEmpty ? null : sec;
                  final p = s == null || _page == null || _page! < 0 ? null : _page;
                  final label = p == null ? '' : _pagesOf(app, s!).firstWhere((x) => x.$1 == p, orElse: () => (p, '')).$2;
                  showIdeaComposer(context, section: s, pageId: p, pageLabel: label);
                },
                icon: const Icon(Icons.add),
                label: const Text('فكرة جديدة'),
              ),
          ],
        ),
        if (!app.v18Ready && app.v2Ready) ...[
          const InfoBanner(
            level: 'warning',
            text: 'ربط الأفكار بالأقسام والصفحات يعمل بعد تحديث قاعدة البيانات بالملف 20261122000033_boq_cascade_ideas_layout.sql.',
          ),
          const SizedBox(height: 12),
        ],
        if (app.v18Ready) ...[
          _IdeasMap(
            app: app,
            fixed: fixed,
            section: sec,
            page: _page,
            onSection: (s) => setState(() {
              _section = s;
              _page = null;
            }),
            onPage: (p) => setState(() => _page = p),
          ),
          const SizedBox(height: 14),
        ],
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ChoiceChip(label: Text('المفتوحة (${count('open')})'), selected: _status == 'open', showCheckmark: false, onSelected: (_) => setState(() => _status = 'open')),
            ChoiceChip(label: Text('الكل (${count('')})'), selected: _status.isEmpty, showCheckmark: false, onSelected: (_) => setState(() => _status = '')),
            for (final e in ideaStatusLabels.entries)
              ChoiceChip(
                label: Text('${e.value} (${count(e.key)})'),
                selected: _status == e.key,
                showCheckmark: false,
                onSelected: (_) => setState(() => _status = e.key),
              ),
          ],
        ),
        const SizedBox(height: 14),
        if (ideas.isEmpty)
          EmptyState(
            icon: Icons.lightbulb_outline_rounded,
            title: 'لا توجد أفكار هنا بعد',
            message: canSubmit ? 'ابدأ بفكرة: ميزة، تقرير، تحسين في الشكل، أو خلل لاحظته.' : null,
          ),
        for (final i in ideas)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: sem.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: sem.rule)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: Text(i.title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700))),
                      if (app.isDirector)
                        PopupMenuButton<String>(
                          tooltip: 'إدارة الفكرة',
                          onSelected: (v) async {
                            try {
                              if (v.startsWith('s:')) {
                                await app.updateIdea(i.id, status: v.substring(2));
                              } else if (v.startsWith('p:')) {
                                await app.updateIdea(i.id, priority: v.substring(2));
                              } else if (v == 'respond') {
                                await _respond(app, i);
                              } else if (v == 'move') {
                                await _move(app, i);
                              } else if (v == 'delete') {
                                final ok = await confirmDialog(context, title: 'حذف الفكرة؟', message: i.title, confirmLabel: 'حذف', danger: true);
                                if (ok) await app.deleteIdea(i.id);
                              }
                            } catch (e) {
                              if (context.mounted) showToast(context, friendlyError(e), error: true);
                            }
                          },
                          itemBuilder: (_) => [
                            for (final e in ideaStatusLabels.entries)
                              PopupMenuItem(value: 's:${e.key}', enabled: e.key != i.status, child: Text('الحالة: ${e.value}')),
                            const PopupMenuDivider(),
                            for (final e in ideaPriorityLabels.entries)
                              PopupMenuItem(value: 'p:${e.key}', enabled: e.key != i.priority, child: Text('الأولوية: ${e.value}')),
                            const PopupMenuDivider(),
                            if (app.v18Ready) const PopupMenuItem(value: 'move', child: Text('نقل إلى قسم أو صفحة')),
                            const PopupMenuItem(value: 'respond', child: Text('كتابة رد')),
                            const PopupMenuItem(value: 'delete', child: Text('حذف')),
                          ],
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Wrap(spacing: 6, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
                    if (app.v18Ready) _IdeaPlace(app: app, idea: i, onTap: () => _goTo(app, i)),
                    ToneBadge(ideaStatusLabels[i.status] ?? i.status, color: _statusColor(sem, context, i.status)),
                    ToneBadge(ideaCategoryLabels[i.category] ?? i.category, color: Theme.of(context).colorScheme.primary),
                    ToneBadge('أولوية ${ideaPriorityLabels[i.priority] ?? i.priority}', color: _priorityColor(sem, i.priority)),
                  ]),
                  if (i.body.trim().isNotEmpty) ...[const SizedBox(height: 10), Text(i.body)],
                  if (i.response.trim().isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: sem.surface2, borderRadius: BorderRadius.circular(12)),
                      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Icon(Icons.reply_rounded, size: 18, color: sem.muted),
                        const SizedBox(width: 8),
                        Expanded(child: Text(i.response)),
                      ]),
                    ),
                  ],
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: Text('${app.personName(i.createdBy)} · ${fmtDate(i.createdAt)}', style: TextStyle(color: sem.muted, fontSize: 12)),
                      ),
                      if (i.githubUrl.isNotEmpty)
                        TextButton.icon(
                          onPressed: () => launchUrl(Uri.parse(i.githubUrl), mode: LaunchMode.externalApplication),
                          icon: const Icon(Icons.task_alt_rounded, size: 18),
                          label: const Text('مهمة التطوير'),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// مكان الفكرة: القسم › الصفحة، ويفتحها عند الضغط.
class _IdeaPlace extends StatelessWidget {
  const _IdeaPlace({required this.app, required this.idea, required this.onTap});

  final AppState app;
  final Idea idea;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final sem = Sem.of(context);
    final s = idea.section;
    if (s == null) return ToneBadge('عامة للمنظومة', color: sem.muted, icon: Icons.public_rounded);
    final color = sectionColor(context, s);
    final page = idea.pageId == null ? '' : _pageName(app, idea.pageId!, idea.pageLabel);
    return Material(
      color: color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(99),
      child: InkWell(
        borderRadius: BorderRadius.circular(99),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(sectionIcon(s, app), size: 13, color: color),
            const SizedBox(width: 4),
            Text(page.isEmpty ? sectionTitle(app, s) : '${sectionTitle(app, s)} › $page',
                style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 11.5)),
          ]),
        ),
      ),
    );
  }
}

/// خريطة الأفكار: كل الأقسام بأعداد أفكارها في الصفحة العامة، وصفحات القسم بأعدادها داخل القسم.
class _IdeasMap extends StatelessWidget {
  const _IdeasMap({
    required this.app,
    required this.fixed,
    required this.section,
    required this.page,
    required this.onSection,
    required this.onPage,
  });

  final AppState app;
  final String? fixed;
  final String? section;
  final int? page;
  final ValueChanged<String?> onSection;
  final ValueChanged<int?> onPage;

  @override
  Widget build(BuildContext context) {
    final sem = Sem.of(context);
    final cs = Theme.of(context).colorScheme;
    final sec = section;

    Widget tile({
      required String label,
      required IconData icon,
      required Color color,
      required int open,
      required int total,
      required bool selected,
      required VoidCallback onTap,
    }) {
      final active = total > 0;
      return Material(
        color: selected ? color.withValues(alpha: 0.16) : sem.surface2,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: selected ? color : Colors.transparent, width: 1.5),
            ),
            child: Row(children: [
              Icon(icon, size: 22, color: active ? color : sem.muted),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w700, color: active ? null : sem.muted)),
                  Text(total == 0 ? 'لا أفكار بعد' : '$open مفتوحة من $total',
                      style: TextStyle(color: sem.muted, fontSize: 11.5)),
                ]),
              ),
              if (open > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(99)),
                  child: Text('$open',
                      style: TextStyle(color: Theme.of(context).brightness == Brightness.dark ? Colors.black : Colors.white, fontWeight: FontWeight.w800, fontSize: 12)),
                ),
            ]),
          ),
        ),
      );
    }

    // الصفحة العامة دون قسم مختار: الأقسام كلها
    if (fixed == null && sec == null) {
      final general = app.ideas.where((i) => i.section == null).toList();
      return SectionCard(
        title: 'خريطة الأفكار في المنظومة',
        icon: Icons.hub_outlined,
        subtitle: 'كل قسم بأفكاره المفتوحة وإجماليها. اضغط قسماً لعرض أفكاره موزعة على صفحاته.',
        child: ResponsiveGrid(minItemWidth: 230, spacing: 8, children: [
          for (final s in hubSections(app))
            tile(
              label: s.$2,
              icon: s.$4,
              color: sectionColor(context, s.$1),
              open: app.openIdeas(s.$1).length,
              total: app.ideas.where((i) => i.section == s.$1).length,
              selected: false,
              onTap: () => onSection(s.$1),
            ),
          tile(
            label: 'عامة للمنظومة',
            icon: Icons.public_rounded,
            color: cs.primary,
            open: general.where((i) => i.isOpen).length,
            total: general.length,
            selected: false,
            onTap: () => onSection(''),
          ),
        ]),
      );
    }

    // الأفكار العامة
    if (sec != null && sec.isEmpty) {
      return Align(
        alignment: AlignmentDirectional.centerStart,
        child: ActionChip(
          avatar: const Icon(Icons.arrow_forward_rounded, size: 18),
          label: const Text('كل الأقسام'),
          onPressed: () => onSection(null),
        ),
      );
    }

    // قسم: صفحاته بأعداد أفكارها
    final s = sec!;
    final inSec = app.ideas.where((i) => i.section == s).toList();
    final pages = _pagesOf(app, s);
    final known = {for (final p in pages) p.$1};
    // صفحات بأفكار لم تعد في قائمة القسم (نُقلت أو أُخفيت) تبقى ظاهرة بأسمائها المحفوظة
    final extra = <int, String>{
      for (final i in inSec)
        if (i.pageId != null && !known.contains(i.pageId)) i.pageId!: i.pageLabel.isEmpty ? 'صفحة ${i.pageId}' : i.pageLabel,
    };
    final color = sectionColor(context, s);
    final whole = inSec.where((i) => i.pageId == null).toList();
    return SectionCard(
      title: 'الأفكار على صفحات «${sectionTitle(app, s)}»',
      icon: sectionIcon(s, app),
      subtitle: 'اضغط صفحة لعرض أفكارها وحدها، واضغطها ثانية لعرض كل أفكار القسم.',
      trailing: fixed == null
          ? TextButton.icon(onPressed: () => onSection(null), icon: const Icon(Icons.arrow_forward_rounded, size: 18), label: const Text('كل الأقسام'))
          : TextButton.icon(
              onPressed: () => app.setTab(Tabs.ideas),
              icon: const Icon(Icons.hub_outlined, size: 18),
              label: const Text('خريطة المنظومة'),
            ),
      child: ResponsiveGrid(minItemWidth: 220, spacing: 8, children: [
        tile(
          label: 'القسم كله',
          icon: Icons.select_all_rounded,
          color: color,
          open: whole.where((i) => i.isOpen).length,
          total: whole.length,
          selected: page == -1,
          onTap: () => onPage(page == -1 ? null : -1),
        ),
        for (final p in [...pages, ...extra.entries.map((e) => (e.key, e.value))])
          tile(
            label: p.$2,
            icon: Icons.web_asset_rounded,
            color: color,
            open: inSec.where((i) => i.pageId == p.$1 && i.isOpen).length,
            total: inSec.where((i) => i.pageId == p.$1).length,
            selected: page == p.$1,
            onTap: () => onPage(page == p.$1 ? null : p.$1),
          ),
      ]),
    );
  }
}

class _IdeaDraft {
  const _IdeaDraft(this.title, this.body, this.category, this.priority, this.section, this.pageId, this.pageLabel);

  final String title;
  final String body;
  final String category;
  final String priority;
  final String? section;
  final int? pageId;
  final String pageLabel;
}

/// اختيار القسم والصفحة (مشترك بين نافذة الفكرة ونقلها).
class _PlacePicker extends StatelessWidget {
  const _PlacePicker({required this.app, required this.section, required this.pageId, required this.extraPage, required this.onChanged});

  final AppState app;
  final String? section;
  final int? pageId;

  /// صفحة الفكرة إن لم تكن في قائمة القسم (صفحة تفاصيل أو منقولة): (الرقم، الاسم).
  final (int, String)? extraPage;
  final void Function(String? section, int? pageId, String pageLabel) onChanged;

  @override
  Widget build(BuildContext context) {
    final sections = hubSections(app);
    final s = section;
    final pages = s == null ? const <(int, String)>[] : _pagesOf(app, s);
    final x = extraPage;
    final all = [...pages, if (x != null && !pages.any((p) => p.$1 == x.$1)) x];
    String labelOf(int id) => all.firstWhere((p) => p.$1 == id, orElse: () => (id, '')).$2;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      SelectField(
        label: 'القسم',
        value: s ?? '',
        items: [('', 'عامة للمنظومة'), for (final x in sections) (x.$1, x.$2)],
        onChanged: (v) => onChanged(v.isEmpty ? null : v, null, ''),
      ),
      if (s != null) ...[
        const SizedBox(height: 12),
        SelectField(
          label: 'الصفحة',
          value: pageId?.toString() ?? '',
          items: [('', 'القسم كله'), for (final p in all) ('${p.$1}', p.$2)],
          onChanged: (v) {
            final id = int.tryParse(v);
            onChanged(s, id, id == null ? '' : labelOf(id));
          },
        ),
      ],
    ]);
  }
}

class _IdeaDialog extends StatefulWidget {
  const _IdeaDialog({required this.app, this.section, this.pageId, this.pageLabel = ''});

  final AppState app;
  final String? section;
  final int? pageId;
  final String pageLabel;

  @override
  State<_IdeaDialog> createState() => _IdeaDialogState();
}

class _IdeaDialogState extends State<_IdeaDialog> {
  final _title = TextEditingController();
  final _body = TextEditingController();
  String _category = 'feature';
  String _priority = 'normal';
  String? _error;
  late String? _section = widget.section;
  late int? _page = widget.section == null ? null : widget.pageId;
  late String _pageLabel = widget.pageLabel;

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = widget.app;
    final sem = Sem.of(context);
    final placed = app.v18Ready;
    return AlertDialog(
      title: const Text('فكرة جديدة'),
      content: SizedBox(
        width: 540,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (placed && widget.section != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(children: [
                    Icon(sectionIcon(widget.section!, app), size: 18, color: sectionColor(context, widget.section!)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'من: ${sectionTitle(app, widget.section!)}${widget.pageLabel.isEmpty ? '' : ' › ${widget.pageLabel}'}',
                        style: TextStyle(color: sem.muted, fontSize: 12.5),
                      ),
                    ),
                  ]),
                ),
              TextField(controller: _title, autofocus: true, maxLength: 200, decoration: fieldDeco('عنوان مختصر', error: _error, hint: 'مثال: تقرير شهري للمستخلصات')),
              TextField(
                controller: _body,
                minLines: 4,
                maxLines: 10,
                decoration: fieldDeco('التفاصيل', hint: 'ما الذي تريده؟ ولماذا؟ وما الذي يتحسن به العمل؟'),
              ),
              const SizedBox(height: 12),
              if (placed) ...[
                _PlacePicker(
                  app: app,
                  section: _section,
                  pageId: _page,
                  extraPage: widget.section != null && widget.pageId != null && _section == widget.section ? (widget.pageId!, widget.pageLabel) : null,
                  onChanged: (s, p, l) => setState(() {
                    _section = s;
                    _page = p;
                    _pageLabel = l;
                  }),
                ),
                const SizedBox(height: 12),
              ],
              SelectField(
                label: 'النوع',
                value: _category,
                items: [for (final e in ideaCategoryLabels.entries) (e.key, e.value)],
                onChanged: (v) => setState(() => _category = v),
              ),
              const SizedBox(height: 12),
              SelectField(
                label: 'الأولوية',
                value: _priority,
                items: [for (final e in ideaPriorityLabels.entries) (e.key, e.value)],
                onChanged: (v) => setState(() => _priority = v),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('إلغاء')),
        FilledButton(
          onPressed: () {
            if (_title.text.trim().length < 3) {
              setState(() => _error = 'اكتب عنواناً من ثلاثة أحرف على الأقل');
              return;
            }
            Navigator.of(context).pop(_IdeaDraft(_title.text.trim(), _body.text.trim(), _category, _priority, _section,
                _section == null ? null : _page, _section == null || _page == null ? '' : _pageLabel));
          },
          child: const Text('إرسال'),
        ),
      ],
    );
  }
}

/// نقل الفكرة إلى قسم أو صفحة (المدير).
class _PlaceDialog extends StatefulWidget {
  const _PlaceDialog({required this.app, required this.title, this.section, this.pageId, this.pageLabel = ''});

  final AppState app;
  final String title;
  final String? section;
  final int? pageId;
  final String pageLabel;

  @override
  State<_PlaceDialog> createState() => _PlaceDialogState();
}

class _PlaceDialogState extends State<_PlaceDialog> {
  late String? _section = widget.section;
  late int? _page = widget.pageId;
  late String _label = widget.pageLabel;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 460,
        child: _PlacePicker(
          app: widget.app,
          section: _section,
          pageId: _page,
          extraPage: widget.section != null && widget.pageId != null && _section == widget.section
              ? (widget.pageId!, widget.pageLabel.isEmpty ? 'صفحة ${widget.pageId}' : widget.pageLabel)
              : null,
          onChanged: (s, p, l) => setState(() {
            _section = s;
            _page = p;
            _label = l;
          }),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('إلغاء')),
        FilledButton(onPressed: () => Navigator.of(context).pop((_section, _section == null ? null : _page, _label)), child: const Text('نقل')),
      ],
    );
  }
}
