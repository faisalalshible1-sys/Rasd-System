import 'package:flutter/material.dart';

import '../../app_state.dart';
import '../../rasd.dart' show hubStyleLabels;
import '../../ui/theme.dart';
import '../../ui/widgets.dart';

/// تخصيص الواجهة (ui.layout): يُحرَّر في شاشة الأقسام الرئيسية نفسها حتى يرى المدير النتيجة وهو يرتّب (الفصل 31).
/// هنا ملخص ما خُصّص وزر الفتح.
class LayoutEditor extends StatelessWidget {
  const LayoutEditor({super.key});

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
    final l = app.layout;
    final renamed = l.sections.values.where((s) => s.name.trim().isNotEmpty || s.desc.trim().isNotEmpty).length;
    final styled = l.sections.values.where((s) => s.icon.isNotEmpty || s.color.isNotEmpty).length;
    final hidden = l.sections.values.where((s) => s.hidden).length;
    final moved = l.movedPages.length;
    final pages = l.pages.values.where((p) => p.label.trim().isNotEmpty || p.icon.isNotEmpty || p.hidden).length;
    final items = <(IconData, String)>[
      (Icons.view_quilt_outlined, 'نمط العرض: ${hubStyleLabels[l.style]}'),
      (Icons.folder_special_outlined, l.groups.isEmpty ? 'دون مجموعات' : 'المجموعات: ${l.groups.map((g) => g.name).join('، ')}'),
      if (l.sectionOrder.isNotEmpty) (Icons.swap_vert_rounded, 'ترتيب الأقسام مخصص'),
      if (renamed > 0) (Icons.drive_file_rename_outline, 'أقسام بأسماء أو أوصاف مخصصة: $renamed'),
      if (styled > 0) (Icons.palette_outlined, 'أقسام بأيقونة أو لون مخصص: $styled'),
      if (hidden > 0) (Icons.visibility_off_outlined, 'أقسام مخفية عن الموظفين: $hidden'),
      if (moved > 0) (Icons.drive_file_move_outlined, 'صفحات منقولة إلى غير أقسامها: $moved'),
      if (pages > 0) (Icons.web_asset_rounded, 'صفحات بأسماء أو أيقونات مخصصة أو مخفية: $pages'),
    ];
    return SectionCard(
      title: 'الأقسام والصفحات',
      icon: Icons.view_quilt_outlined,
      subtitle: 'رتّب الأيقونات الرئيسية ووزّعها بالكامل من شاشة الأقسام نفسها: السحب والمجموعات ونمط العرض، '
          'واسم كل قسم ووصفه وأيقونته ولونه، وصفحاته ونقلها بين الأقسام. يُطبَّق على الجميع فوراً بعد الحفظ.',
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (final it in items)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(children: [
              Icon(it.$1, size: 18, color: sem.muted),
              const SizedBox(width: 10),
              Expanded(child: Text(it.$2)),
            ]),
          ),
        const SizedBox(height: 8),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: FilledButton.icon(
            onPressed: () => app.openHub(edit: true),
            icon: const Icon(Icons.dashboard_customize_outlined),
            label: const Text('فتح محرر الواجهة'),
          ),
        ),
      ]),
    );
  }
}
