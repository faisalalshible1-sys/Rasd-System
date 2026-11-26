import 'package:flutter/material.dart';

import '../app_state.dart';
import '../docs.dart';
import '../models.dart';
import '../pm.dart';
import '../services/doc_files.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';
import 'docs.dart' show DocDetailPage, docFileIcon, pickAndAttach;
import 'pm_common.dart';

// =====================================================================
// «ملف العقد» (الترحيل 35): مرفقات العقد المصنّفة — العقد وملاحقه، والمقايسة، والمخططات، ومحاضر التسليم،
// وقرارات التكليف (مربوطة بالمهندس)، والمستخلصات، وأوامر التغيير، والمراسلات، وأخرى.
// يقوم على نظام المستندات القائم: لكل مرفق إصدارات، واستبدال الملف يضيف إصداراً ويحفظ السابق.
// يراه ويضيف إليه مكتب المدير ومكتب العقود والقسم المشرف على العقد؛ والحذف للمدير وحده.
// =====================================================================

IconData attachmentCategoryIcon(String c) => switch (c) {
      'contract' => Icons.handshake_outlined,
      'boq' => Icons.request_quote_outlined,
      'drawings' => Icons.architecture_rounded,
      'handover' => Icons.fact_check_outlined,
      'assignment' => Icons.badge_outlined,
      'extract' => Icons.receipt_long_outlined,
      'variation' => Icons.change_circle_outlined,
      'correspondence' => Icons.mark_email_read_outlined,
      _ => Icons.attach_file_rounded,
    };

/// التصنيفات التي يُتوقع وجودها في كل ملف عقد (يُنبَّه إلى ما لم يُرفع منها).
const List<String> attachmentEssentials = ['contract', 'boq', 'drawings'];

/// نموذج إضافة مرفق أو تعديل بياناته. بعد الإضافة يختار المستخدم الملفات مباشرة.
Future<void> showAttachmentEditor(BuildContext context, String projectId, {DocItem? item, String? category, String? engineerId}) async {
  final app = AppScope.read(context);
  final engineers = [
    ('', '—'),
    for (final e in app.engineersOf(projectId))
      (e.id, '${engineerKindLabel(e.kind)}: ${e.name}${e.assignNo.isEmpty ? '' : ' (تكليف ${e.assignNo})'}'),
  ];
  final sections = <PmSection>[
    PmSection('المرفق', [
      PmField('category', 'التصنيف', PmKind.select, options: pmLabels(attachmentCategories, attachmentCategoryLabels), required: true),
      const PmField('doc_date', 'التاريخ', PmKind.date),
      const PmField('title', 'الوصف', PmKind.text, required: true, max: 200, full: true, helper: 'مثل: نسخة العقد الموقّعة، محضر تسليم الموقع'),
      const PmField('ref_no', 'الرقم', PmKind.text, max: 60),
      const PmField('party', 'الجهة المصدرة', PmKind.text, max: 120),
      if (engineers.length > 1)
        PmField('engineer_id', 'المهندس المكلَّف', PmKind.select,
            options: engineers, full: true, helper: 'لقرارات التكليف فقط: يظهر القرار بجانب اسم المهندس في بطاقة المهندسين.'),
    ]),
    PmSection('', [
      const PmField('notes', 'ملاحظات', PmKind.multiline, max: 2000),
      if (item == null) const PmField('rev_note', 'ملاحظة الإصدار الأول', PmKind.text, max: 300, full: true),
    ]),
  ];
  String? newRev;
  String title = item?.title ?? '';
  final ok = await showPmForm(
    context,
    title: item == null ? 'مرفق جديد في ملف العقد' : 'تعديل ${item.title}',
    note: item == null
        ? 'بعد الحفظ تختار الملف أو الملفات: PDF وWord وExcel وPowerPoint والصور وDWG وDXF وRevit والمضغوط وKML/KMZ، حتى 50 ميجابايت للملف. '
            'الصور المتعددة يمكن دمجها في ملف PDF واحد. استبدال الملف لاحقاً يُضاف إصداراً جديداً ويبقى السابق محفوظاً.'
        : null,
    sections: sections,
    values: item?.toJson() ??
        {
          'project_id': projectId,
          'category': category ?? (engineerId != null ? 'assignment' : 'contract'),
          'doc_date': pmIso(DateTime.now()),
          'engineer_id': engineerId ?? '',
          if (engineerId != null)
            for (final e in app.engineersOf(projectId))
              if (e.id == engineerId) ...{'title': 'قرار تكليف ${e.name}', 'ref_no': e.assignNo, 'doc_date': pmIso(e.assignedOn ?? DateTime.now())},
        },
    onSave: (d) async {
      final data = {...d, 'kind': 'attachment', 'project_id': projectId};
      if (data['category'] != 'assignment') data['engineer_id'] = '';
      title = '${data['title'] ?? ''}'.trim();
      final r = await app.saveDocItem(item?.id, data);
      newRev = r.$2;
    },
  );
  if (!ok || !context.mounted) return;
  if (item != null) {
    showToast(context, 'حُفظت التعديلات');
    return;
  }
  showToast(context, 'سُجّل المرفق؛ اختر ملفه');
  final rev = newRev;
  if (rev != null) await pickAndAttach(context, 'doc', rev, kind: 'attachment', ownerTitle: title);
}

/// بطاقة «ملف العقد» في صفحة العقد: تصفية بالتصنيف مع العدد، والقائمة، وإضافة مرفق.
class ContractFilesCard extends StatefulWidget {
  const ContractFilesCard({super.key, required this.project});

  final Project project;

  @override
  State<ContractFilesCard> createState() => _ContractFilesCardState();
}

class _ContractFilesCardState extends State<ContractFilesCard> {
  String _category = '';

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final sem = Sem.of(context);
    final cs = Theme.of(context).colorScheme;
    final p = widget.project;
    final all = app.docs.attachmentsOf(p.id);
    final counts = <String, int>{for (final i in all) i.category: 0};
    for (final i in all) {
      counts[i.category] = counts[i.category]! + 1;
    }
    if (_category.isNotEmpty && !counts.containsKey(_category)) _category = '';
    final shown = _category.isEmpty ? all : all.where((i) => i.category == _category).toList();
    final bytes = all.fold<int>(0, (s, i) {
      final rev = app.docs.revisionsOf(i.id);
      return s + rev.fold<int>(0, (t, r) => t + app.docs.filesOfRevision(r.id).fold<int>(0, (u, f) => u + f.sizeBytes));
    });
    final missing = [for (final c in attachmentEssentials) if (!counts.containsKey(c)) attachmentCategoryLabels[c]!];
    final canAdd = app.canEditDoc('attachment', p.id);

    return SectionCard(
      title: 'ملف العقد',
      icon: Icons.folder_shared_outlined,
      subtitle: all.isEmpty
          ? 'العقد الموقّع ومقايسته ومخططاته ومحاضره وقرارات التكليف في مكان واحد، بإصدارات تحفظ كل نسخة.'
          : '${all.length} مرفقاً · ${fmtBytes(bytes)}',
      trailing: canAdd
          ? FilledButton.tonalIcon(
              onPressed: () => showAttachmentEditor(context, p.id, category: _category.isEmpty ? null : _category),
              icon: const Icon(Icons.upload_file_rounded),
              label: const Text('إضافة مرفق'),
            )
          : null,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (all.isNotEmpty)
          Wrap(spacing: 6, runSpacing: 6, children: [
            ChoiceChip(
              label: Text('الكل ${all.length}'),
              selected: _category.isEmpty,
              onSelected: (_) => setState(() => _category = ''),
            ),
            for (final c in attachmentCategories)
              if (counts.containsKey(c))
                ChoiceChip(
                  avatar: Icon(attachmentCategoryIcon(c), size: 16),
                  label: Text('${attachmentCategoryLabels[c]} ${counts[c]}'),
                  selected: _category == c,
                  onSelected: (_) => setState(() => _category = _category == c ? '' : c),
                ),
          ]),
        if (all.isNotEmpty) const SizedBox(height: 8),
        for (final i in shown) _AttachmentTile(item: i, showCategory: _category.isEmpty),
        if (all.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Text(canAdd ? 'لا مرفقات بعد. ابدأ بنسخة العقد الموقّعة.' : 'لا مرفقات في ملف هذا العقد بعد.',
                style: TextStyle(color: sem.muted, fontSize: 12.5)),
          ),
        if (missing.isNotEmpty && all.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Row(children: [
              Icon(Icons.info_outline_rounded, size: 15, color: cs.tertiary),
              const SizedBox(width: 6),
              Expanded(child: Text('لم يُرفع بعد: ${missing.join('، ')}', style: TextStyle(color: sem.muted, fontSize: 12))),
            ]),
          ),
      ]),
    );
  }
}

class _AttachmentTile extends StatelessWidget {
  const _AttachmentTile({required this.item, required this.showCategory});

  final DocItem item;
  final bool showCategory;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final sem = Sem.of(context);
    final cs = Theme.of(context).colorScheme;
    final files = app.docs.currentFiles(item.id);
    final revs = app.docs.revisionsOf(item.id);
    ContractEngineer? eng;
    for (final e in app.engineersOf(item.projectId ?? '')) {
      if (e.id == item.engineerId) eng = e;
    }
    final parts = [
      if (showCategory) item.categoryLabel,
      if (item.refNo.isNotEmpty) 'رقم ${item.refNo}',
      pmDay(item.docDate),
      if (eng != null) eng.name,
      if (files.length == 1) '${files.first.typeLabel} ${fmtBytes(files.first.sizeBytes)}' else if (files.length > 1) '${files.length} ملفات',
      if (files.isEmpty) 'بلا ملف',
      if (revs.length > 1) 'الإصدار ${revs.last.revNo}',
    ];
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: sem.surface2,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => DocDetailPage(itemId: item.id))),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 4, 8),
            child: Row(children: [
              Icon(attachmentCategoryIcon(item.category), color: files.isEmpty ? sem.muted : cs.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(item.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
                  Text(parts.where((x) => x.isNotEmpty && x != '—').join(' · '),
                      style: TextStyle(color: files.isEmpty ? sem.danger : sem.muted, fontSize: 12)),
                ]),
              ),
              if (files.length == 1)
                IconButton(
                  tooltip: 'فتح ${files.first.name}',
                  icon: Icon(docFileIcon(files.first), size: 20),
                  onPressed: () async {
                    try {
                      await openDocExternally(await app.signedUrls.of(files.first.path));
                    } catch (e) {
                      if (context.mounted) showToast(context, friendlyError(e), error: true);
                    }
                  },
                )
              else
                Icon(Icons.chevron_left_rounded, color: sem.muted),
            ]),
          ),
        ),
      ),
    );
  }
}
