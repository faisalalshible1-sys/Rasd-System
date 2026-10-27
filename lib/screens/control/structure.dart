import 'package:flutter/material.dart';

import '../../app_state.dart';
import '../../models.dart';
import '../../ui/theme.dart';
import '../../ui/widgets.dart';
import 'control_panel.dart';

/// هيكل البيانات: المراحل والنماذج والأقسام.
class StructureSection extends StatefulWidget {
  const StructureSection({super.key});

  @override
  State<StructureSection> createState() => _StructureSectionState();
}

class _StructureSectionState extends State<StructureSection> {
  bool _busy = false;

  Future<void> _do(Future<void> Function() f, String ok) async {
    setState(() => _busy = true);
    await runAction(context, f, success: ok);
    if (mounted) setState(() => _busy = false);
  }

  // ------------------------------------------------------------ المراحل
  Future<void> _editStage(AppState app, StageDef? st) async {
    final name = await textInputDialog(context,
        title: st == null ? 'مرحلة جديدة' : 'تسمية المرحلة',
        label: 'اسم المرحلة',
        confirmLabel: 'حفظ',
        required: true,
        initial: st?.name,
        multiline: false);
    if (name == null) return;
    await _do(() => app.saveStage(st?.idx, name), st == null ? 'أُضيفت المرحلة' : 'حُفظ اسم المرحلة');
  }

  Future<void> _deleteStage(AppState app, StageDef st) async {
    final ok = await confirmDialog(context,
        title: 'حذف مرحلة «${st.name}»؟', message: 'تُحذف المرحلة الأخيرة فقط، وبعد نقل نماذجها.', confirmLabel: 'حذف', danger: true);
    if (!ok) return;
    await _do(() => app.deleteStage(st.idx), 'حُذفت المرحلة');
  }

  // ------------------------------------------------------------ النماذج
  Future<void> _editForm(AppState app, FormDef? d) async {
    final res = await showDialog<_FormDraft>(
      context: context,
      builder: (ctx) => _FormEditorDialog(app: app, def: d),
    );
    if (res == null) return;
    await _do(
      () => app.saveFormDef(
          key: d?.key, name: res.name, stage: res.stage, sensitive: res.sensitive, responsible: res.responsible, active: res.active),
      d == null ? 'أُضيف النموذج' : 'حُفظ النموذج',
    );
  }

  Future<void> _move(AppState app, FormDef d, int dir) async {
    final order = [...app.allFormDefs]..sort((a, b) => a.sort.compareTo(b.sort));
    final sameStage = order.where((x) => x.stage == d.stage).toList();
    final i = sameStage.indexWhere((x) => x.key == d.key);
    final j = i + dir;
    if (j < 0 || j >= sameStage.length) return;
    final a = order.indexWhere((x) => x.key == sameStage[i].key);
    final b = order.indexWhere((x) => x.key == sameStage[j].key);
    final tmp = order[a];
    order[a] = order[b];
    order[b] = tmp;
    await _do(() => app.reorderForms([for (final x in order) x.key]), 'تغيّر الترتيب');
  }

  Future<void> _deleteForm(AppState app, FormDef d) async {
    final ok = await confirmDialog(context,
        title: 'حذف «${d.name}»؟',
        message: 'يُحذف النموذج نهائياً إن لم تُسجَّل له حالات في أي مشروع؛ وإلا فأوقفه بدل حذفه.',
        confirmLabel: 'حذف',
        danger: true);
    if (!ok) return;
    await _do(() => app.deleteFormDef(d.key), 'حُذف النموذج');
  }

  // ------------------------------------------------------------ الأقسام
  Future<void> _editDepartment(AppState app, Department? d) async {
    final res = await showDialog<(String, bool)>(
      context: context,
      builder: (ctx) {
        final c = TextEditingController(text: d?.name ?? '');
        var sup = d?.canSupervise ?? false;
        return StatefulBuilder(
          builder: (ctx, setLocal) => AlertDialog(
            title: Text(d == null ? 'قسم جديد' : 'تسمية القسم'),
            content: SizedBox(
              width: 420,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(controller: c, autofocus: true, decoration: fieldDeco('اسم القسم')),
                  if (d == null)
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: sup,
                      onChanged: (v) => setLocal(() => sup = v),
                      title: const Text('يمكن إسناد الإشراف على مشروع إليه'),
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('إلغاء')),
              FilledButton(
                onPressed: () {
                  if (c.text.trim().length < 2) return;
                  Navigator.of(ctx).pop((c.text.trim(), sup));
                },
                child: const Text('حفظ'),
              ),
            ],
          ),
        );
      },
    );
    if (res == null) return;
    await _do(() => app.saveDepartment(key: d?.key, name: res.$1, canSupervise: res.$2), 'حُفظ القسم');
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final sem = Sem.of(context);
    final defs = [...app.allFormDefs]..sort((a, b) => a.sort.compareTo(b.sort));
    return PageBody(
      onRefresh: app.loadAll,
      children: [
        PageHeader(
          icon: Icons.account_tree_outlined,
          title: 'المراحل والنماذج والأقسام',
          subtitle: 'كل تغيير هنا يسري فوراً على الجميع وعلى حساب نسب الإنجاز، ويُسجَّل في سجل التدقيق.',
          actions: [if (_busy) const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))],
        ),
        SectionCard(
          title: 'المراحل',
          icon: Icons.linear_scale_rounded,
          subtitle: 'تتابع الدورة المستندية من المرحلة الأولى إلى الأخيرة',
          trailing: TextButton.icon(onPressed: _busy ? null : () => _editStage(app, null), icon: const Icon(Icons.add), label: const Text('مرحلة')),
          child: Column(
            children: [
              for (final st in app.stages)
                SettingRow(
                  icon: Icons.flag_outlined,
                  title: '${st.idx + 1}. ${st.name}',
                  subtitle: '${defs.where((d) => d.stage == st.idx && d.active).length} نموذجاً فعّالاً',
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(tooltip: 'تسمية', onPressed: _busy ? null : () => _editStage(app, st), icon: const Icon(Icons.edit_outlined)),
                      if (st.idx == app.stages.last.idx && !defs.any((d) => d.stage == st.idx))
                        IconButton(
                            tooltip: 'حذف', onPressed: _busy ? null : () => _deleteStage(app, st), icon: Icon(Icons.delete_outline, color: sem.danger)),
                    ],
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        SectionCard(
          title: 'النماذج',
          icon: Icons.description_outlined,
          subtitle: 'أضف نموذجاً، أو غيّر اسمه ومرحلته وترتيبه، أو أوقفه مؤقتاً',
          trailing: FilledButton.tonalIcon(onPressed: _busy ? null : () => _editForm(app, null), icon: const Icon(Icons.add), label: const Text('نموذج')),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final st in app.stages) ...[
                SubHeading('${st.idx + 1}. ${st.name}'),
                if (!defs.any((d) => d.stage == st.idx))
                  Padding(padding: const EdgeInsets.only(bottom: 8), child: Text('لا توجد نماذج في هذه المرحلة', style: TextStyle(color: sem.muted))),
                for (final d in defs.where((d) => d.stage == st.idx))
                  Container(
                    margin: const EdgeInsets.only(bottom: 6),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(color: sem.surface2, borderRadius: BorderRadius.circular(12)),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(d.name,
                                  style: TextStyle(fontWeight: FontWeight.w600, decoration: d.active ? null : TextDecoration.lineThrough)),
                              Wrap(spacing: 6, runSpacing: 4, children: [
                                if (d.sensitive) ToneBadge('حساس', color: sem.wip),
                                if (!d.active) ToneBadge('موقوف', color: sem.muted),
                                if (d.engineerField != null) ToneBadge(engineerFieldLabel(d.engineerField!), color: sem.ok),
                              ]),
                            ],
                          ),
                        ),
                        IconButton(tooltip: 'لأعلى', onPressed: _busy ? null : () => _move(app, d, -1), icon: const Icon(Icons.keyboard_arrow_up_rounded)),
                        IconButton(tooltip: 'لأسفل', onPressed: _busy ? null : () => _move(app, d, 1), icon: const Icon(Icons.keyboard_arrow_down_rounded)),
                        IconButton(tooltip: 'تعديل', onPressed: _busy ? null : () => _editForm(app, d), icon: const Icon(Icons.edit_outlined)),
                        IconButton(
                            tooltip: 'حذف', onPressed: _busy ? null : () => _deleteForm(app, d), icon: Icon(Icons.delete_outline, color: sem.danger)),
                      ],
                    ),
                  ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),
        SectionCard(
          title: 'الأقسام',
          icon: Icons.apartment_rounded,
          trailing: TextButton.icon(onPressed: _busy ? null : () => _editDepartment(app, null), icon: const Icon(Icons.add), label: const Text('قسم')),
          child: Column(
            children: [
              for (final d in app.departments)
                SettingRow(
                  icon: d.canSupervise ? Icons.engineering_outlined : Icons.business_outlined,
                  title: d.name,
                  subtitle: d.canSupervise ? 'يُسند إليه الإشراف على المشاريع' : 'قسم متخصص',
                  trailing: IconButton(tooltip: 'تسمية', onPressed: _busy ? null : () => _editDepartment(app, d), icon: const Icon(Icons.edit_outlined)),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _FormDraft {
  const _FormDraft(this.name, this.stage, this.sensitive, this.responsible, this.active);

  final String name;
  final int stage;
  final bool sensitive;
  final List<String> responsible;
  final bool active;
}

class _FormEditorDialog extends StatefulWidget {
  const _FormEditorDialog({required this.app, required this.def});

  final AppState app;
  final FormDef? def;

  @override
  State<_FormEditorDialog> createState() => _FormEditorDialogState();
}

class _FormEditorDialogState extends State<_FormEditorDialog> {
  late final TextEditingController _name = TextEditingController(text: widget.def?.name ?? '');
  late int _stage = widget.def?.stage ?? (widget.app.stages.isEmpty ? 0 : widget.app.stages.first.idx);
  late bool _sensitive = widget.def?.sensitive ?? false;
  late List<String> _responsible = [...(widget.def?.responsible ?? const ['office_staff'])];
  late bool _active = widget.def?.active ?? true;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.def == null ? 'نموذج جديد' : 'تعديل النموذج'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(controller: _name, autofocus: true, decoration: fieldDeco('اسم النموذج', error: _error)),
              const SizedBox(height: 12),
              SelectField(
                label: 'المرحلة',
                value: '$_stage',
                items: [for (final st in widget.app.stages) ('${st.idx}', '${st.idx + 1}. ${st.name}')],
                onChanged: (v) => setState(() => _stage = int.parse(v)),
              ),
              const SizedBox(height: 12),
              const Text('من يحدّثه (إضافة إلى مدير المكتب)', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              TokenSelector(selected: _responsible, onChanged: (v) => setState(() => _responsible = v)),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _sensitive,
                onChanged: (v) => setState(() => _sensitive = v),
                title: const Text('نموذج حساس'),
                subtitle: const Text('تغييره من غيرك يرفع طلب اعتماد إليك'),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _active,
                onChanged: (v) => setState(() => _active = v),
                title: const Text('فعّال'),
                subtitle: const Text('الموقوف يختفي من المشاريع ولا يدخل في نسبة الإنجاز'),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('إلغاء')),
        FilledButton(
          onPressed: () {
            if (_name.text.trim().length < 2) {
              setState(() => _error = 'اكتب اسم النموذج');
              return;
            }
            Navigator.of(context).pop(_FormDraft(_name.text.trim(), _stage, _sensitive, _responsible, _active));
          },
          child: const Text('حفظ'),
        ),
      ],
    );
  }
}
