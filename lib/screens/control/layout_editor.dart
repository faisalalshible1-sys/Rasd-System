import 'package:flutter/material.dart';

import '../../app_state.dart';
import '../../rasd.dart';
import '../../ui/theme.dart';
import '../../ui/widgets.dart';
import '../home_shell.dart' show sectionPageCatalog;
import '../hub.dart';
import 'control_panel.dart' show runAction;

/// تخصيص الأقسام والصفحات (ui.layout): أسماؤها وأوصافها وترتيبها بالسحب وإخفاؤها، لكل المستخدمين فوراً.
class LayoutEditor extends StatefulWidget {
  const LayoutEditor({super.key});

  @override
  State<LayoutEditor> createState() => _LayoutEditorState();
}

class _LayoutEditorState extends State<LayoutEditor> {
  bool _ready = false;
  bool _busy = false;
  List<String> _order = [];
  final Map<String, TextEditingController> _name = {};
  final Map<String, TextEditingController> _desc = {};
  final Map<String, bool> _hidden = {};
  String _section = 'cycle';
  final Map<String, List<int>> _pageOrder = {};
  final Map<int, TextEditingController> _pageLabel = {};
  final Map<int, bool> _pageHidden = {};

  @override
  void dispose() {
    for (final c in [..._name.values, ..._desc.values, ..._pageLabel.values]) {
      c.dispose();
    }
    super.dispose();
  }

  void _init(AppState app) {
    final l = app.layout;
    _order = UiLayout.ordered([for (final s in appSections) s.$1], l.sectionOrder, (k) => k);
    for (final s in appSections) {
      _name[s.$1] = TextEditingController(text: l.sections[s.$1]?.name ?? '');
      _desc[s.$1] = TextEditingController(text: l.sections[s.$1]?.desc ?? '');
      _hidden[s.$1] = l.sections[s.$1]?.hidden ?? false;
      final pages = sectionPageCatalog(app, s.$1);
      _pageOrder[s.$1] = UiLayout.ordered([for (final p in pages) p.$1], l.pageOrder[s.$1] ?? const [], (k) => k);
      for (final p in pages) {
        _pageLabel[p.$1] ??= TextEditingController(text: l.pages[p.$1]?.label ?? '');
        _pageHidden[p.$1] = l.pages[p.$1]?.hidden ?? false;
      }
    }
    _ready = true;
  }

  UiLayout _value(AppState app) {
    final defaultOrder = [for (final s in appSections) s.$1];
    return UiLayout(
      sections: {
        for (final k in _order)
          k: SectionCustom(name: _name[k]!.text, desc: _desc[k]!.text, hidden: k != 'security' && (_hidden[k] ?? false)),
      },
      sectionOrder: _order.join() == defaultOrder.join() ? const [] : _order,
      pages: {for (final e in _pageLabel.entries) e.key: PageCustom(label: e.value.text, hidden: _pageHidden[e.key] ?? false)},
      pageOrder: {
        for (final s in appSections)
          if (_pageOrder[s.$1] != null &&
              _pageOrder[s.$1]!.join(',') != [for (final p in sectionPageCatalog(app, s.$1)) p.$1].join(','))
            s.$1: _pageOrder[s.$1]!,
      },
    );
  }

  Future<void> _save(AppState app, {bool reset = false}) async {
    setState(() => _busy = true);
    await runAction(context, () => app.saveLayout(reset ? UiLayout.empty : _value(app)),
        success: reset ? 'عادت الأقسام والصفحات إلى الافتراضي' : 'حُفظ تخصيص الأقسام والصفحات');
    if (mounted) {
      setState(() {
        _busy = false;
        if (reset) {
          _ready = false;
          for (final c in [..._name.values, ..._desc.values, ..._pageLabel.values]) {
            c.clear();
          }
          _pageLabel.clear();
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final sem = Sem.of(context);
    if (!app.v11Ready) {
      return const SectionCard(
        title: 'الأقسام والصفحات',
        icon: Icons.view_quilt_outlined,
        child: InfoBanner(text: 'يعمل بعد تحديث قاعدة البيانات بالملف 20261119000023_rasd_grants_refs.sql.', level: 'warning'),
      );
    }
    if (!_ready) _init(app);
    final meta = {for (final s in appSections) s.$1: s};
    final pages = {for (final p in sectionPageCatalog(app, _section)) p.$1: p};
    final pageIds = [for (final id in _pageOrder[_section] ?? const <int>[]) if (pages.containsKey(id)) id];

    return SectionCard(
      title: 'الأقسام والصفحات',
      icon: Icons.view_quilt_outlined,
      subtitle: 'اسحب ⠿ لترتيب الأقسام في شاشة الدخول وصفحات كل قسم في قائمته، وغيّر الأسماء والأوصاف، وأخفِ ما لا يحتاجه الموظفون. '
          'يُطبَّق على الجميع فوراً، وأنت ترى كل شيء دائماً.',
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('الأقسام', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        ReorderableListView(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          buildDefaultDragHandles: false,
          onReorder: (a, b) => setState(() {
            if (b > a) b--;
            _order.insert(b, _order.removeAt(a));
          }),
          children: [
            for (var i = 0; i < _order.length; i++)
              Container(
                key: ValueKey('s-${_order[i]}'),
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.fromLTRB(4, 6, 8, 6),
                decoration: BoxDecoration(
                  color: _section == _order[i] ? Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.5) : sem.surface2,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(children: [
                  ReorderableDragStartListener(
                    index: i,
                    child: const Padding(padding: EdgeInsets.all(8), child: Icon(Icons.drag_indicator_rounded)),
                  ),
                  Icon(meta[_order[i]]!.$4, color: sectionColor(context, _order[i])),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 3,
                    child: TextField(
                      controller: _name[_order[i]],
                      maxLength: 40,
                      decoration: fieldDeco('الاسم', hint: meta[_order[i]]!.$2).copyWith(counterText: ''),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 4,
                    child: TextField(
                      controller: _desc[_order[i]],
                      maxLength: 200,
                      decoration: fieldDeco('الوصف في شاشة الدخول', hint: meta[_order[i]]!.$3).copyWith(counterText: ''),
                    ),
                  ),
                  if (_order[i] != 'security')
                    IconButton(
                      tooltip: _hidden[_order[i]] == true ? 'مخفي عن الموظفين' : 'ظاهر للجميع',
                      onPressed: () => setState(() => _hidden[_order[i]] = !(_hidden[_order[i]] ?? false)),
                      icon: Icon(_hidden[_order[i]] == true ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                          color: _hidden[_order[i]] == true ? sem.danger : null),
                    )
                  else
                    const SizedBox(width: 48),
                  IconButton(
                    tooltip: 'صفحات القسم',
                    onPressed: () => setState(() => _section = _order[i]),
                    icon: Icon(Icons.chevron_left_rounded, color: _section == _order[i] ? Theme.of(context).colorScheme.primary : null),
                  ),
                ]),
              ),
          ],
        ),
        const SizedBox(height: 14),
        Text('صفحات «${_name[_section]!.text.trim().isNotEmpty ? _name[_section]!.text.trim() : meta[_section]!.$2}»',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        if (pageIds.isEmpty)
          Text('لا صفحات قابلة للتخصيص في هذا القسم الآن.', style: TextStyle(color: sem.muted))
        else
          ReorderableListView(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            buildDefaultDragHandles: false,
            onReorder: (a, b) => setState(() {
              if (b > a) b--;
              final list = [...pageIds];
              list.insert(b, list.removeAt(a));
              _pageOrder[_section] = list;
            }),
            children: [
              for (var i = 0; i < pageIds.length; i++)
                Container(
                  key: ValueKey('p-${pageIds[i]}'),
                  margin: const EdgeInsets.only(bottom: 6),
                  padding: const EdgeInsets.fromLTRB(4, 4, 8, 4),
                  decoration: BoxDecoration(color: sem.surface2, borderRadius: BorderRadius.circular(12)),
                  child: Row(children: [
                    ReorderableDragStartListener(
                      index: i,
                      child: const Padding(padding: EdgeInsets.all(8), child: Icon(Icons.drag_indicator_rounded)),
                    ),
                    Icon(pages[pageIds[i]]!.$3, color: sem.muted),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _pageLabel[pageIds[i]] ??= TextEditingController(),
                        maxLength: 40,
                          decoration: fieldDeco('اسم الصفحة في القائمة', hint: pages[pageIds[i]]!.$2).copyWith(counterText: ''),
                      ),
                    ),
                    IconButton(
                      tooltip: _pageHidden[pageIds[i]] == true ? 'مخفية عن الموظفين' : 'ظاهرة',
                      onPressed: () => setState(() => _pageHidden[pageIds[i]] = !(_pageHidden[pageIds[i]] ?? false)),
                      icon: Icon(_pageHidden[pageIds[i]] == true ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                          color: _pageHidden[pageIds[i]] == true ? sem.danger : null),
                    ),
                  ]),
                ),
            ],
          ),
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 8, children: [
          FilledButton.icon(
            onPressed: _busy ? null : () => _save(app),
            icon: const Icon(Icons.save_outlined),
            label: const Text('حفظ التخصيص'),
          ),
          OutlinedButton.icon(
            onPressed: _busy || app.layout.isEmpty ? null : () => _save(app, reset: true),
            icon: const Icon(Icons.restart_alt_rounded),
            label: const Text('الافتراضي'),
          ),
        ]),
      ]),
    );
  }
}
