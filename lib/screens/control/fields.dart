import 'package:flutter/material.dart';

import '../../app_state.dart';
import '../../models.dart';
import '../../ui/theme.dart';
import '../../ui/widgets.dart';
import 'control_panel.dart';

/// الحقول الإضافية للمشاريع: تُعرَّف هنا وتظهر في صفحة كل مشروع دون تعديل البرمجة.
class FieldsSection extends StatefulWidget {
  const FieldsSection({super.key});

  @override
  State<FieldsSection> createState() => _FieldsSectionState();
}

class _FieldsSectionState extends State<FieldsSection> {
  bool _busy = false;

  Future<void> _edit(AppState app, CustomField? f) async {
    final res = await showDialog<_FieldDraft>(context: context, builder: (_) => _FieldEditorDialog(field: f, app: app));
    if (res == null) return;
    setState(() => _busy = true);
    await runAction(
      context,
      () => app.saveCustomField(
        key: f?.key,
        label: res.label,
        kind: res.kind,
        options: res.options,
        section: res.section,
        editableBy: res.editableBy,
        active: res.active,
      ),
      success: f == null ? 'أُضيف الحقل' : 'حُفظ الحقل',
    );
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _move(AppState app, CustomField f, int dir) async {
    final list = [...app.customFields]..sort((a, b) => a.sort.compareTo(b.sort));
    final i = list.indexWhere((x) => x.key == f.key);
    final j = i + dir;
    if (j < 0 || j >= list.length) return;
    final t = list[i];
    list[i] = list[j];
    list[j] = t;
    setState(() => _busy = true);
    await runAction(context, () => app.reorderCustomFields([for (final x in list) x.key]));
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final sem = Sem.of(context);
    final fields = [...app.customFields]..sort((a, b) => a.sort.compareTo(b.sort));
    return PageBody(
      onRefresh: app.loadAll,
      children: [
        PageHeader(
          icon: Icons.dynamic_form_outlined,
          title: 'الحقول الإضافية',
          subtitle: 'أضف أي بيان تحتاجه للمشاريع (رقم العقد، تاريخ التوقيع، نوع المشروع...) فيظهر فوراً في صفحة كل مشروع، '
              'ويحدّثه من تحدده فقط، ويُسجَّل كل تعديل عليه.',
          actions: [
            FilledButton.icon(onPressed: _busy ? null : () => _edit(app, null), icon: const Icon(Icons.add), label: const Text('حقل جديد')),
          ],
        ),
        if (fields.isEmpty)
          const EmptyState(
            icon: Icons.dynamic_form_outlined,
            title: 'لا توجد حقول إضافية بعد',
            message: 'ابدأ بحقل مثل «رقم العقد» أو «تاريخ التوقيع».',
          ),
        for (final f in fields)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: sem.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: sem.rule)),
              child: Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(color: Theme.of(context).colorScheme.primaryContainer, borderRadius: BorderRadius.circular(10)),
                    child: Icon(_kindIcon(f.kind), size: 20, color: Theme.of(context).colorScheme.onPrimaryContainer),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Opacity(
                      opacity: f.active ? 1 : 0.55,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(f.label, style: const TextStyle(fontWeight: FontWeight.w700)),
                          Text(
                            '${fieldKindLabels[f.kind] ?? f.kind} · ${f.section} · يحدّثه: ${f.editableBy.isEmpty ? 'المدير فقط' : f.editableBy.map((t) => responsibleLabels[t] ?? t).join('، ')}',
                            style: TextStyle(color: sem.muted, fontSize: 12.5),
                          ),
                          if (!f.active) Padding(padding: const EdgeInsets.only(top: 4), child: ToneBadge('موقوف', color: sem.muted)),
                        ],
                      ),
                    ),
                  ),
                  IconButton(tooltip: 'لأعلى', onPressed: _busy ? null : () => _move(app, f, -1), icon: const Icon(Icons.keyboard_arrow_up_rounded)),
                  IconButton(tooltip: 'لأسفل', onPressed: _busy ? null : () => _move(app, f, 1), icon: const Icon(Icons.keyboard_arrow_down_rounded)),
                  IconButton(tooltip: 'تعديل', onPressed: _busy ? null : () => _edit(app, f), icon: const Icon(Icons.edit_outlined)),
                ],
              ),
            ),
          ),
      ],
    );
  }

  static IconData _kindIcon(String k) => switch (k) {
        'longtext' => Icons.notes_rounded,
        'number' => Icons.pin_outlined,
        'money' => Icons.payments_outlined,
        'date' => Icons.event_outlined,
        'select' => Icons.list_rounded,
        'bool' => Icons.toggle_on_outlined,
        _ => Icons.short_text_rounded,
      };
}

class _FieldDraft {
  const _FieldDraft(this.label, this.kind, this.options, this.section, this.editableBy, this.active);

  final String label;
  final String kind;
  final List<String> options;
  final String section;
  final List<String> editableBy;
  final bool active;
}

class _FieldEditorDialog extends StatefulWidget {
  const _FieldEditorDialog({required this.field, required this.app});

  final CustomField? field;
  final AppState app;

  @override
  State<_FieldEditorDialog> createState() => _FieldEditorDialogState();
}

class _FieldEditorDialogState extends State<_FieldEditorDialog> {
  late final TextEditingController _label = TextEditingController(text: widget.field?.label ?? '');
  late final TextEditingController _section = TextEditingController(text: widget.field?.section ?? 'بيانات إضافية');
  late final TextEditingController _options = TextEditingController(text: (widget.field?.options ?? const []).join('\n'));
  late String _kind = widget.field?.kind ?? 'text';
  late List<String> _editable = [...(widget.field?.editableBy ?? const ['office_staff'])];
  late bool _active = widget.field?.active ?? true;
  String? _error;

  @override
  void dispose() {
    _label.dispose();
    _section.dispose();
    _options.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sections = widget.app.customFields.map((f) => f.section).toSet().toList();
    return AlertDialog(
      title: Text(widget.field == null ? 'حقل جديد' : 'تعديل الحقل'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(controller: _label, autofocus: true, decoration: fieldDeco('اسم الحقل', hint: 'مثال: رقم العقد')),
              const SizedBox(height: 12),
              SelectField(
                label: 'نوع الحقل',
                value: _kind,
                items: [for (final e in fieldKindLabels.entries) (e.key, e.value)],
                onChanged: (v) => setState(() => _kind = v),
              ),
              if (_kind == 'select') ...[
                const SizedBox(height: 12),
                TextField(
                  controller: _options,
                  minLines: 3,
                  maxLines: 6,
                  decoration: fieldDeco('الخيارات', helper: 'خيار في كل سطر'),
                ),
              ],
              const SizedBox(height: 12),
              TextField(
                controller: _section,
                decoration: fieldDeco('المجموعة في صفحة المشروع', helper: sections.isEmpty ? null : 'المجموعات الحالية: ${sections.join('، ')}'),
              ),
              const SizedBox(height: 12),
              const Text('من يحدّثه (إضافة إلى مدير المكتب)', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              TokenSelector(selected: _editable, onChanged: (v) => setState(() => _editable = v)),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _active,
                onChanged: (v) => setState(() => _active = v),
                title: const Text('فعّال'),
                subtitle: const Text('الموقوف يختفي من صفحات المشاريع وتبقى قيمه محفوظة'),
              ),
              if (_error != null) InfoBanner(text: _error!, level: 'critical'),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('إلغاء')),
        FilledButton(
          onPressed: () {
            final label = _label.text.trim();
            final options = _options.text.split('\n').map((e) => e.trim()).where((e) => e.isNotEmpty).toSet().toList();
            if (label.length < 2) {
              setState(() => _error = 'اكتب اسم الحقل');
              return;
            }
            if (_kind == 'select' && options.length < 2) {
              setState(() => _error = 'القائمة تحتاج خيارين على الأقل');
              return;
            }
            Navigator.of(context).pop(_FieldDraft(label, _kind, _kind == 'select' ? options : const [], _section.text.trim(), _editable, _active));
          },
          child: const Text('حفظ'),
        ),
      ],
    );
  }
}
