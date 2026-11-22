import 'package:flutter/material.dart';

import '../app_state.dart';
import '../rasd.dart';
import '../ui/layout_catalog.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';

// =====================================================================
// محرر الواجهة (للمدير وحده): يعمل فوق شاشة الأقسام الرئيسية نفسها (الفصل 31).
//   • ترتيب بطاقات الأقسام بالسحب، ونقلها بين المجموعات.
//   • مجموعات بعناوين تُضاف وتُسمّى وتُرتَّب وتُحذف.
//   • نمط العرض: بطاقات بالمؤشرات، أو مدمجة، أو أيقونات.
//   • لكل قسم: الاسم والوصف والأيقونة واللون والإخفاء عن الموظفين، وصفحاته: ترتيبها وأسماؤها وأيقوناتها
//     وإخفاؤها ونقلها إلى قسم آخر.
// يُحفظ كله في الإعداد ui.layout مرة واحدة بزر «حفظ التخصيص»، ويسري على الجميع فوراً.
// =====================================================================

/// صفحة في محرر صفحات القسم: رقمها واسمها وأيقونتها الافتراضيان، وقسمها الأصلي.
class LayoutPage {
  const LayoutPage(this.id, this.label, this.icon, this.home);

  final int id;
  final String label;
  final IconData icon;
  final String home;
}

/// صفحات قسم بعد النقل: صفحاته التي لم تُنقل، والمنقولة إليه من غيره.
typedef LayoutPagesFn = List<LayoutPage> Function(AppState app, String section, Map<int, String> moved);

/// نسخة قابلة للتعديل من التخصيص، تُعرض حية في شاشة الدخول ولا تُحفظ إلا بالحفظ.
class HubDraft {
  HubDraft.from(UiLayout l, List<String> defaultOrder)
      : _default = [...defaultOrder],
        order = [...UiLayout.ordered(defaultOrder, l.sectionOrder, (k) => k)],
        sections = Map.of(l.sections),
        groups = [...l.groups],
        style = l.style,
        pages = Map.of(l.pages),
        pageOrder = {for (final e in l.pageOrder.entries) e.key: [...e.value]};

  final List<String> _default;
  List<String> order;
  Map<String, SectionCustom> sections;
  List<LayoutGroup> groups;
  String style;
  Map<int, PageCustom> pages;
  Map<String, List<int>> pageOrder;

  UiLayout toLayout() => UiLayout(
        sections: {for (final e in sections.entries) if (!e.value.isEmpty) e.key: e.value},
        sectionOrder: order.join(',') == _default.join(',') ? const [] : [...order],
        pages: {for (final e in pages.entries) if (!e.value.isEmpty) e.key: e.value},
        pageOrder: {for (final e in pageOrder.entries) if (e.value.isNotEmpty) e.key: [...e.value]},
        groups: [...groups],
        hubStyle: style == 'cards' ? '' : style,
      );

  SectionCustom sec(String k) => sections[k] ?? const SectionCustom();

  void setSec(String k, SectionCustom c) => sections[k] = c;

  String groupOf(String k) {
    final g = sec(k).group;
    return groups.any((x) => x.key == g) ? g : '';
  }

  /// ضع [dragged] قبل [target] وفي مجموعته.
  void moveBefore(String dragged, String target) {
    if (dragged == target) return;
    order.remove(dragged);
    order.insert(order.indexOf(target), dragged);
    setSec(dragged, sec(dragged).copyWith(group: groupOf(target)));
  }

  /// انقل [dragged] إلى آخر مجموعة (المفتاح الفارغ = دون مجموعة).
  void moveToGroup(String dragged, String group) {
    setSec(dragged, sec(dragged).copyWith(group: group));
    order.remove(dragged);
    final last = order.lastIndexWhere((k) => groupOf(k) == group);
    order.insert(last < 0 ? order.length : last + 1, dragged);
  }

  /// تقديم القسم أو تأخيره بين أقسام مجموعته.
  void shift(String k, int delta) {
    final g = groupOf(k);
    final same = [for (final x in order) if (groupOf(x) == g) x];
    final i = same.indexOf(k);
    final j = i + delta;
    if (i < 0 || j < 0 || j >= same.length) return;
    final other = same[j];
    final a = order.indexOf(k);
    final b = order.indexOf(other);
    order[a] = other;
    order[b] = k;
  }

  String addGroup(String name) {
    var n = groups.length + 1;
    while (groups.any((g) => g.key == 'g$n')) {
      n++;
    }
    final key = 'g$n';
    groups = [...groups, LayoutGroup(key, name.trim())];
    return key;
  }

  void renameGroup(String key, String name) {
    groups = [for (final g in groups) g.key == key ? LayoutGroup(key, name.trim()) : g];
  }

  void deleteGroup(String key) {
    groups = [for (final g in groups) if (g.key != key) g];
    for (final k in [...sections.keys]) {
      if (sec(k).group == key) setSec(k, sec(k).copyWith(group: ''));
    }
  }

  void moveGroup(String key, int delta) {
    final i = groups.indexWhere((g) => g.key == key);
    final j = i + delta;
    if (i < 0 || j < 0 || j >= groups.length) return;
    final list = [...groups];
    list.insert(j, list.removeAt(i));
    groups = list;
  }

  PageCustom page(int id) => pages[id] ?? const PageCustom();

  void setPage(int id, PageCustom c) => pages[id] = c;
}

// ---------------------------------------------------------------------
// شريط التحرير أعلى شاشة الدخول
// ---------------------------------------------------------------------
class HubEditBar extends StatelessWidget {
  const HubEditBar({
    super.key,
    required this.draft,
    required this.busy,
    required this.onChanged,
    required this.onSave,
    required this.onCancel,
    required this.onReset,
  });

  final HubDraft draft;
  final bool busy;
  final VoidCallback onChanged;
  final VoidCallback onSave;
  final VoidCallback onCancel;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.primaryContainer.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.primary.withValues(alpha: 0.35)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Icon(Icons.dashboard_customize_outlined, color: cs.onPrimaryContainer),
          const SizedBox(width: 10),
          Expanded(
            child: Text('تخصيص الواجهة', style: t.titleMedium?.copyWith(fontWeight: FontWeight.w800, color: cs.onPrimaryContainer)),
          ),
          if (busy) const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
        ]),
        const SizedBox(height: 6),
        Text(
          'اسحب البطاقة من مقبضها، أو اضغطها مطولاً، لترتيبها أو نقلها إلى مجموعة. اضغط البطاقة لتعديل اسمها ووصفها '
          'وأيقونتها ولونها وصفحاتها، وزر العين لإخفائها عن الموظفين. لا يُطبَّق شيء حتى تحفظ.',
          style: TextStyle(color: cs.onPrimaryContainer, height: 1.55, fontSize: 12.5),
        ),
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'cards', label: Text('بطاقات'), icon: Icon(Icons.view_agenda_outlined)),
              ButtonSegment(value: 'compact', label: Text('مدمجة'), icon: Icon(Icons.view_list_outlined)),
              ButtonSegment(value: 'icons', label: Text('أيقونات'), icon: Icon(Icons.apps_rounded)),
            ],
            selected: {draft.style},
            showSelectedIcon: false,
            onSelectionChanged: busy
                ? null
                : (v) {
                    draft.style = v.first;
                    onChanged();
                  },
          ),
          OutlinedButton.icon(
            onPressed: busy || draft.groups.length >= 12
                ? null
                : () async {
                    final name = await textInputDialog(context,
                        title: 'مجموعة جديدة',
                        message: 'عنوان يظهر فوق أقسامه في شاشة الدخول، مثل «الأقسام الهندسية» أو «المكاتب المساندة».',
                        label: 'اسم المجموعة',
                        confirmLabel: 'إضافة',
                        required: true,
                        multiline: false);
                    if (name == null || name.trim().isEmpty) return;
                    draft.addGroup(name.trim().length > 40 ? name.trim().substring(0, 40) : name.trim());
                    onChanged();
                  },
            icon: const Icon(Icons.create_new_folder_outlined, size: 18),
            label: const Text('مجموعة جديدة'),
          ),
        ]),
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 8, children: [
          FilledButton.icon(onPressed: busy ? null : onSave, icon: const Icon(Icons.save_outlined, size: 18), label: const Text('حفظ التخصيص')),
          OutlinedButton(onPressed: busy ? null : onCancel, child: const Text('إلغاء')),
          TextButton.icon(
            onPressed: busy ? null : onReset,
            icon: const Icon(Icons.restart_alt_rounded, size: 18),
            label: const Text('الافتراضي'),
          ),
        ]),
      ]),
    );
  }
}

// ---------------------------------------------------------------------
// عنوان المجموعة (ويستقبل الأقسام المسحوبة إليه أثناء التحرير)
// ---------------------------------------------------------------------
class HubGroupHeading extends StatelessWidget {
  const HubGroupHeading({super.key, required this.group, this.draft, this.onChanged, this.count = 0});

  final LayoutGroup group;
  final HubDraft? draft;
  final VoidCallback? onChanged;
  final int count;

  @override
  Widget build(BuildContext context) {
    final sem = Sem.of(context);
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final d = draft;
    final title = Row(children: [
      Text(group.name, style: t.titleSmall?.copyWith(fontWeight: FontWeight.w800, color: d == null ? sem.muted : cs.primary)),
      const SizedBox(width: 10),
      Expanded(child: Divider(color: sem.rule, height: 1)),
    ]);
    if (d == null) return Padding(padding: const EdgeInsets.fromLTRB(4, 18, 4, 10), child: title);
    final real = group.key.isNotEmpty;
    final i = d.groups.indexWhere((g) => g.key == group.key);
    return DragTarget<String>(
      onAcceptWithDetails: (x) {
        d.moveToGroup(x.data, group.key);
        onChanged?.call();
      },
      builder: (context, cand, _) => AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        margin: const EdgeInsets.only(top: 14, bottom: 8),
        padding: const EdgeInsets.fromLTRB(8, 2, 4, 2),
        decoration: BoxDecoration(
          color: cand.isNotEmpty ? cs.primaryContainer : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: cand.isNotEmpty ? cs.primary : Colors.transparent),
        ),
        child: Row(children: [
          Expanded(child: title),
          if (cand.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text('أفلِت هنا لنقله إلى «${group.name}»', style: TextStyle(color: cs.primary, fontSize: 12)),
            ),
          if (real) ...[
            IconButton(
              tooltip: 'إعادة تسمية المجموعة',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.edit_outlined, size: 19),
              onPressed: () async {
                final name = await textInputDialog(context,
                    title: 'اسم المجموعة', label: 'الاسم', confirmLabel: 'تطبيق', initial: group.name, required: true, multiline: false);
                if (name == null || name.trim().isEmpty) return;
                d.renameGroup(group.key, name.trim().length > 40 ? name.trim().substring(0, 40) : name.trim());
                onChanged?.call();
              },
            ),
            IconButton(
              tooltip: 'تقديم المجموعة',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.arrow_upward_rounded, size: 18),
              onPressed: i <= 0
                  ? null
                  : () {
                      d.moveGroup(group.key, -1);
                      onChanged?.call();
                    },
            ),
            IconButton(
              tooltip: 'تأخير المجموعة',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.arrow_downward_rounded, size: 18),
              onPressed: i < 0 || i >= d.groups.length - 1
                  ? null
                  : () {
                      d.moveGroup(group.key, 1);
                      onChanged?.call();
                    },
            ),
            IconButton(
              tooltip: 'حذف المجموعة (تبقى أقسامها دون مجموعة)',
              visualDensity: VisualDensity.compact,
              icon: Icon(Icons.delete_outline_rounded, size: 19, color: sem.danger),
              onPressed: () {
                d.deleteGroup(group.key);
                onChanged?.call();
              },
            ),
          ],
        ]),
      ),
    );
  }
}

/// مكان إفلات في مجموعة فارغة.
class HubEmptyDrop extends StatelessWidget {
  const HubEmptyDrop({super.key, required this.draft, required this.group, required this.onChanged});

  final HubDraft draft;
  final String group;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final sem = Sem.of(context);
    final cs = Theme.of(context).colorScheme;
    return DragTarget<String>(
      onAcceptWithDetails: (x) {
        draft.moveToGroup(x.data, group);
        onChanged();
      },
      builder: (context, cand, _) => Container(
        height: 72,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: cand.isNotEmpty ? cs.primaryContainer : sem.surface2,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: cand.isNotEmpty ? cs.primary : sem.rule),
        ),
        child: Text('اسحب قسماً إلى هنا', style: TextStyle(color: cand.isNotEmpty ? cs.primary : sem.muted)),
      ),
    );
  }
}

// ---------------------------------------------------------------------
// بطاقة قابلة للسحب والتعديل
// ---------------------------------------------------------------------
class EditableHubTile extends StatelessWidget {
  const EditableHubTile({
    super.key,
    required this.sectionKey,
    required this.title,
    required this.icon,
    required this.color,
    required this.hidden,
    required this.canHide,
    required this.child,
    required this.onDrop,
    required this.onEdit,
    required this.onToggleHidden,
  });

  final String sectionKey;
  final String title;
  final IconData icon;
  final Color color;
  final bool hidden;
  final bool canHide;
  final Widget child;
  final ValueChanged<String> onDrop;
  final VoidCallback onEdit;
  final VoidCallback onToggleHidden;

  Widget _feedback(BuildContext context) => Material(
        elevation: 8,
        borderRadius: BorderRadius.circular(14),
        color: Theme.of(context).colorScheme.surface,
        child: Container(
          width: 230,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), border: Border.all(color: color, width: 2)),
          child: Row(children: [
            Icon(icon, color: color),
            const SizedBox(width: 10),
            Expanded(child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700))),
          ]),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final sem = Sem.of(context);
    final cs = Theme.of(context).colorScheme;
    Widget round(IconData i, String tip, VoidCallback onTap, {Color? c}) => Tooltip(
          message: tip,
          child: Material(
            color: cs.surface,
            shape: CircleBorder(side: BorderSide(color: sem.rule)),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onTap,
              child: Padding(padding: const EdgeInsets.all(7), child: Icon(i, size: 18, color: c ?? sem.muted)),
            ),
          ),
        );
    final handle = Draggable<String>(
      data: sectionKey,
      feedback: _feedback(context),
      child: Tooltip(
        message: 'اسحب لترتيب القسم أو نقله إلى مجموعة',
        child: Material(
          color: cs.surface,
          shape: CircleBorder(side: BorderSide(color: sem.rule)),
          child: Padding(padding: const EdgeInsets.all(7), child: Icon(Icons.drag_indicator_rounded, size: 18, color: cs.primary)),
        ),
      ),
    );
    // شريط أدوات البطاقة فوقها (لا يغطي محتواها في أي نمط عرض)
    Widget tile(bool target) => AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: target ? cs.primaryContainer.withValues(alpha: 0.6) : sem.surface2.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: target ? cs.primary : sem.rule, width: target ? 2 : 1),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 2, 4, 6),
              child: Row(children: [
                if (hidden)
                  Flexible(child: ToneBadge('مخفي عن الموظفين', color: sem.danger, icon: Icons.visibility_off_outlined))
                else
                  const Spacer(),
                if (hidden) const Spacer(),
                if (canHide) ...[
                  round(hidden ? Icons.visibility_off_outlined : Icons.visibility_outlined, hidden ? 'مخفي عن الموظفين' : 'ظاهر للجميع',
                      onToggleHidden,
                      c: hidden ? sem.danger : null),
                  const SizedBox(width: 6),
                ],
                round(Icons.edit_outlined, 'تعديل القسم وصفحاته', onEdit),
                const SizedBox(width: 6),
                handle,
              ]),
            ),
            Stack(children: [
              AnimatedOpacity(duration: const Duration(milliseconds: 200), opacity: hidden ? 0.42 : 1, child: IgnorePointer(child: child)),
              Positioned.fill(
                child: Material(
                  type: MaterialType.transparency,
                  child: InkWell(borderRadius: BorderRadius.circular(18), onTap: onEdit),
                ),
              ),
            ]),
          ]),
        );
    return DragTarget<String>(
      onWillAcceptWithDetails: (x) => x.data != sectionKey,
      onAcceptWithDetails: (x) => onDrop(x.data),
      builder: (context, cand, _) => LongPressDraggable<String>(
        data: sectionKey,
        feedback: _feedback(context),
        childWhenDragging: Opacity(opacity: 0.3, child: tile(false)),
        child: tile(cand.isNotEmpty),
      ),
    );
  }
}

// ---------------------------------------------------------------------
// اختيار الأيقونة واللون
// ---------------------------------------------------------------------
class LayoutIconPicker extends StatelessWidget {
  const LayoutIconPicker({super.key, required this.value, required this.fallback, required this.color, required this.onChanged});

  final String value;
  final IconData fallback;
  final Color color;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final sem = Sem.of(context);
    Widget cell(String key, IconData icon, String tip) {
      final selected = value == key;
      final box = InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => onChanged(key),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: selected ? color.withValues(alpha: 0.16) : sem.surface2,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: selected ? color : sem.rule, width: selected ? 2 : 1),
            ),
            child: Icon(icon, size: 22, color: selected ? color : sem.muted),
          ),
        );
      return tip.isEmpty ? box : Tooltip(message: tip, child: box);
    }

    return Wrap(spacing: 6, runSpacing: 6, children: [
      cell('', fallback, 'الأيقونة الافتراضية'),
      for (final e in layoutIcons.entries)
        if (e.value != fallback) cell(e.key, e.value, ''),
    ]);
  }
}

class LayoutColorPicker extends StatelessWidget {
  const LayoutColorPicker({super.key, required this.value, required this.fallback, required this.onChanged});

  final String value;
  final Color fallback;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final cs = Theme.of(context).colorScheme;
    Widget dot(String key, Color c, String tip) {
      final selected = value == key;
      return Tooltip(
        message: tip,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: () => onChanged(key),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: c,
              shape: BoxShape.circle,
              border: Border.all(color: selected ? cs.onSurface : Colors.transparent, width: 3),
            ),
            child: selected ? Icon(Icons.check_rounded, size: 18, color: dark ? Colors.black : Colors.white) : null,
          ),
        ),
      );
    }

    return Wrap(spacing: 8, runSpacing: 8, children: [
      dot('', fallback, 'اللون الافتراضي للقسم'),
      for (final e in layoutColors.entries) dot(e.key, dark ? e.value.$3 : e.value.$2, e.value.$1),
    ]);
  }
}

// ---------------------------------------------------------------------
// تعديل قسم
// ---------------------------------------------------------------------
Future<void> showSectionEditor(
  BuildContext context, {
  required AppState app,
  required HubDraft draft,
  required String sectionKey,
  required String defaultName,
  required String defaultDesc,
  required IconData defaultIcon,
  required Color defaultColor,
  required LayoutPagesFn? pagesOf,
  required VoidCallback onChanged,
}) async {
  final name = TextEditingController(text: draft.sec(sectionKey).name);
  final desc = TextEditingController(text: draft.sec(sectionKey).desc);
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => StatefulBuilder(builder: (ctx, setLocal) {
      final sem = Sem.of(ctx);
      final t = Theme.of(ctx).textTheme;
      final c = draft.sec(sectionKey);
      final color = layoutColor(ctx, c.color) ?? defaultColor;
      final icon = layoutIcons[c.icon] ?? defaultIcon;
      void update(SectionCustom v) {
        draft.setSec(sectionKey, v);
        setLocal(() {});
        onChanged();
      }

      final pages = pagesOf?.call(app, sectionKey, draft.toLayout().movedPages) ?? const <LayoutPage>[];
      final sameGroup = [for (final k in draft.order) if (draft.groupOf(k) == draft.groupOf(sectionKey)) k];
      final pos = sameGroup.indexOf(sectionKey);
      return SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.9),
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(ctx).bottom),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(14)),
                  child: Icon(icon, color: color, size: 28),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(name.text.trim().isEmpty ? defaultName : name.text.trim(),
                        style: t.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                    Text('الاسم الافتراضي: $defaultName', style: TextStyle(color: sem.muted, fontSize: 12)),
                  ]),
                ),
              ]),
              const SizedBox(height: 16),
              TextField(
                controller: name,
                maxLength: 40,
                onChanged: (v) => update(draft.sec(sectionKey).copyWith(name: v)),
                decoration: fieldDeco('اسم مخصص', hint: defaultName).copyWith(counterText: ''),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: desc,
                maxLength: 200,
                minLines: 2,
                maxLines: 4,
                onChanged: (v) => update(draft.sec(sectionKey).copyWith(desc: v)),
                decoration: fieldDeco('وصف مخصص في شاشة الدخول', hint: defaultDesc),
              ),
              const SizedBox(height: 14),
              Text('الأيقونة', style: t.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              LayoutIconPicker(value: c.icon, fallback: defaultIcon, color: color, onChanged: (v) => update(c.copyWith(icon: v))),
              const SizedBox(height: 16),
              Text('اللون', style: t.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              LayoutColorPicker(value: c.color, fallback: defaultColor, onChanged: (v) => update(c.copyWith(color: v))),
              const SizedBox(height: 16),
              SelectField(
                label: 'المجموعة في شاشة الدخول',
                value: draft.groupOf(sectionKey),
                items: [('', 'دون مجموعة'), for (final g in draft.groups) (g.key, g.name)],
                onChanged: (v) {
                  draft.moveToGroup(sectionKey, v);
                  setLocal(() {});
                  onChanged();
                },
              ),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(
                  child: Text('الترتيب في مجموعته: ${pos + 1} من ${sameGroup.length}', style: TextStyle(color: sem.muted)),
                ),
                IconButton(
                  tooltip: 'تقديم',
                  onPressed: pos <= 0
                      ? null
                      : () {
                          draft.shift(sectionKey, -1);
                          setLocal(() {});
                          onChanged();
                        },
                  icon: const Icon(Icons.arrow_upward_rounded),
                ),
                IconButton(
                  tooltip: 'تأخير',
                  onPressed: pos < 0 || pos >= sameGroup.length - 1
                      ? null
                      : () {
                          draft.shift(sectionKey, 1);
                          setLocal(() {});
                          onChanged();
                        },
                  icon: const Icon(Icons.arrow_downward_rounded),
                ),
              ]),
              if (sectionKey != 'security')
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('مخفي عن الموظفين', style: TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text('أنت ترى كل الأقسام دائماً. الصلاحيات لا تتغير.', style: TextStyle(color: sem.muted, fontSize: 12)),
                  value: c.hidden,
                  onChanged: (v) => update(c.copyWith(hidden: v)),
                ),
              const Divider(height: 24),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.view_list_rounded, color: color),
                title: Text('صفحات القسم (${pages.length})', style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text('ترتيبها وأسماؤها وأيقوناتها وإخفاؤها، ونقل صفحة إلى قسم آخر',
                    style: TextStyle(color: sem.muted, fontSize: 12)),
                trailing: const Icon(Icons.chevron_left_rounded),
                onTap: pagesOf == null
                    ? null
                    : () async {
                        await showPagesEditor(ctx,
                            app: app, draft: draft, sectionKey: sectionKey, sectionName: name.text.trim().isEmpty ? defaultName : name.text.trim(),
                            pagesOf: pagesOf, onChanged: () {
                          setLocal(() {});
                          onChanged();
                        });
                      },
              ),
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 8, children: [
                FilledButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('تم')),
                TextButton(
                  onPressed: () {
                    name.clear();
                    desc.clear();
                    update(SectionCustom(group: c.group));
                  },
                  child: const Text('إعادة القسم إلى الافتراضي'),
                ),
              ]),
            ]),
          ),
        ),
      );
    }),
  );
  name.dispose();
  desc.dispose();
}

// ---------------------------------------------------------------------
// صفحات القسم: الترتيب والأسماء والأيقونات والإخفاء والنقل بين الأقسام
// ---------------------------------------------------------------------
Future<void> showPagesEditor(
  BuildContext context, {
  required AppState app,
  required HubDraft draft,
  required String sectionKey,
  required String sectionName,
  required LayoutPagesFn pagesOf,
  required VoidCallback onChanged,
}) async {
  final labels = <int, TextEditingController>{};
  TextEditingController ctl(int id) => labels[id] ??= TextEditingController(text: draft.page(id).label);
  // أسماء الأقسام كما تظهر في المحرر الآن
  final sectionNames = sectionNamesForEditor(app, draft);
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => StatefulBuilder(builder: (ctx, setLocal) {
      final sem = Sem.of(ctx);
      final t = Theme.of(ctx).textTheme;
      final pages = pagesOf(app, sectionKey, draft.toLayout().movedPages);
      final byId = {for (final p in pages) p.id: p};
      final ids = UiLayout.ordered([for (final p in pages) p.id], draft.pageOrder[sectionKey] ?? const [], (k) => k);
      void changed() {
        setLocal(() {});
        onChanged();
      }

      Future<void> pickIcon(LayoutPage p) async {
        final v = await showDialog<String>(
          context: ctx,
          builder: (d) => AlertDialog(
            title: Text('أيقونة «${p.label}»'),
            content: SizedBox(
              width: 460,
              child: SingleChildScrollView(
                child: LayoutIconPicker(
                  value: draft.page(p.id).icon,
                  fallback: p.icon,
                  color: Theme.of(d).colorScheme.primary,
                  onChanged: (k) => Navigator.of(d).pop(k),
                ),
              ),
            ),
            actions: [TextButton(onPressed: () => Navigator.of(d).pop(), child: const Text('إلغاء'))],
          ),
        );
        if (v == null) return;
        draft.setPage(p.id, draft.page(p.id).copyWith(icon: v));
        changed();
      }

      return SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(ctx).height * 0.86,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 6),
              child: Text('صفحات «$sectionName»', style: t.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
              child: Text(
                'اسحب من المقبض لترتيب القائمة، واكتب اسماً مخصصاً، واضغط الأيقونة لتغييرها، وزر العين لإخفاء الصفحة عن الموظفين، '
                'و«نقل» لعرض الصفحة في قسم آخر بدل قسمها. الصلاحيات تبقى كما هي.',
                style: TextStyle(color: sem.muted, fontSize: 12.5, height: 1.5),
              ),
            ),
            Expanded(
              child: ids.isEmpty
                  ? const EmptyState(icon: Icons.view_list_outlined, title: 'لا صفحات قابلة للتخصيص في هذا القسم الآن')
                  : ReorderableListView(
                      padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                      buildDefaultDragHandles: false,
                      onReorder: (a, b) {
                        if (b > a) b--;
                        final list = [...ids];
                        list.insert(b, list.removeAt(a));
                        draft.pageOrder[sectionKey] = list;
                        changed();
                      },
                      children: [
                        for (var i = 0; i < ids.length; i++)
                          Builder(
                            key: ValueKey('pg-${ids[i]}'),
                            builder: (context) {
                              final p = byId[ids[i]]!;
                              final c = draft.page(p.id);
                              final moved = p.home != sectionKey;
                              return Container(
                                margin: const EdgeInsets.only(bottom: 6),
                                padding: const EdgeInsets.fromLTRB(2, 4, 4, 4),
                                decoration: BoxDecoration(color: sem.surface2, borderRadius: BorderRadius.circular(12)),
                                child: Row(children: [
                                  ReorderableDragStartListener(
                                    index: i,
                                    child: const Padding(padding: EdgeInsets.all(8), child: Icon(Icons.drag_indicator_rounded)),
                                  ),
                                  IconButton(
                                    tooltip: 'تغيير الأيقونة',
                                    onPressed: () => pickIcon(p),
                                    icon: Icon(layoutIcons[c.icon] ?? p.icon),
                                  ),
                                  Expanded(
                                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
                                      TextField(
                                        controller: ctl(p.id),
                                        maxLength: 40,
                                        onChanged: (v) {
                                          draft.setPage(p.id, draft.page(p.id).copyWith(label: v));
                                          onChanged();
                                        },
                                        decoration: fieldDeco(p.label, hint: 'الاسم الافتراضي')
                                            .copyWith(counterText: '', isDense: true),
                                      ),
                                      if (moved)
                                        Padding(
                                          padding: const EdgeInsets.only(top: 4),
                                          child: Text('منقولة من «${sectionNames[p.home] ?? p.home}»',
                                              style: TextStyle(color: Theme.of(context).colorScheme.primary, fontSize: 11.5)),
                                        ),
                                    ]),
                                  ),
                                  IconButton(
                                    tooltip: c.hidden ? 'مخفية عن الموظفين' : 'ظاهرة',
                                    onPressed: () {
                                      draft.setPage(p.id, c.copyWith(hidden: !c.hidden));
                                      changed();
                                    },
                                    icon: Icon(c.hidden ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                                        color: c.hidden ? sem.danger : null),
                                  ),
                                  if (sectionKey != 'security' && p.home != 'security')
                                    PopupMenuButton<String>(
                                      tooltip: 'نقل إلى قسم آخر',
                                      icon: const Icon(Icons.drive_file_move_outlined),
                                      onSelected: (target) {
                                        draft.setPage(p.id, c.copyWith(section: target == p.home ? '' : target));
                                        draft.pageOrder[sectionKey]?.remove(p.id);
                                        changed();
                                        showToast(ctx, target == p.home
                                            ? 'أُعيدت «${p.label}» إلى «${sectionNames[target] ?? target}»'
                                            : 'نُقلت «${p.label}» إلى «${sectionNames[target] ?? target}»');
                                      },
                                      itemBuilder: (_) => [
                                        if (moved)
                                          PopupMenuItem(value: p.home, child: Text('إعادتها إلى قسمها الأصلي: ${sectionNames[p.home] ?? p.home}')),
                                        for (final e in sectionNames.entries)
                                          if (e.key != sectionKey && e.key != 'security' && e.key != p.home)
                                            PopupMenuItem(value: e.key, child: Text('نقل إلى: ${e.value}')),
                                      ],
                                    ),
                                ]),
                              );
                            },
                          ),
                      ],
                    ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 6, 20, 12),
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: FilledButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('تم')),
              ),
            ),
          ]),
        ),
      );
    }),
  );
  for (final c in labels.values) {
    c.dispose();
  }
}

/// أسماء الأقسام بعد تعديلها في المحرر (للنقل بين الأقسام)، بترتيب المحرر.
Map<String, String> sectionNamesForEditor(AppState app, HubDraft draft) {
  final names = <String, String>{};
  for (final k in draft.order) {
    final custom = draft.sec(k).name.trim();
    names[k] = custom.isNotEmpty ? custom : (sectionDefaultNames[k] ?? k);
  }
  if (!app.canAudit) names.remove('security');
  return names;
}
