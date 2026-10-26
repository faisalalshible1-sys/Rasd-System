import 'package:flutter/material.dart';

import '../models.dart';
import 'theme.dart';

String two(int n) => n.toString().padLeft(2, '0');

String fmtDate(DateTime? d) {
  if (d == null) return '';
  final l = d.toLocal();
  return '${l.year}/${two(l.month)}/${two(l.day)}  ${two(l.hour)}:${two(l.minute)}';
}

String pctText(double v, {int digits = 0}) => '${(v * 100).toStringAsFixed(digits)}%';

void showToast(BuildContext context, String message, {bool error = false}) {
  final sem = Sem.of(context);
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor: error ? sem.danger : null,
      behavior: SnackBarBehavior.floating,
    ));
}

/// بطاقة قسم بعنوان.
class SectionCard extends StatelessWidget {
  const SectionCard({super.key, required this.title, this.trailing, required this.child, this.padding = const EdgeInsets.all(16)});

  final String title;
  final Widget? trailing;
  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final sem = Sem.of(context);
    final t = Theme.of(context).textTheme;
    return Container(
      decoration: BoxDecoration(
        color: sem.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: sem.rule),
      ),
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(child: Text(title, style: t.titleMedium?.copyWith(fontWeight: FontWeight.w700))),
              if (trailing != null) trailing!,
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

/// شريط مقسّم بنسب (مكتمل / قيد الإجراء / لم يتم ...).
class SegmentMeter extends StatelessWidget {
  const SegmentMeter({super.key, required this.parts, this.height = 10});

  final List<(int, Color)> parts;
  final double height;

  @override
  Widget build(BuildContext context) {
    final sem = Sem.of(context);
    final total = parts.fold<int>(0, (a, p) => a + p.$1);
    return ClipRRect(
      borderRadius: BorderRadius.circular(height),
      child: SizedBox(
        height: height,
        child: total == 0
            ? Container(color: sem.todoSoft)
            : Row(
                children: [
                  for (final p in parts)
                    if (p.$1 > 0) Expanded(flex: p.$1, child: Container(color: p.$2)),
                ],
              ),
      ),
    );
  }
}

/// شريط الدورة المستندية: 18 خانة مجمّعة في المراحل الخمس.
class CycleStrip extends StatelessWidget {
  const CycleStrip({super.key, required this.defs, required this.cells, this.height = 8});

  final List<FormDef> defs;
  final List<FormStatus> cells;
  final double height;

  @override
  Widget build(BuildContext context) {
    final sem = Sem.of(context);
    final groups = <Widget>[];
    for (var stage = 0; stage < stageNames.length; stage++) {
      final idx = <int>[];
      for (var i = 0; i < defs.length; i++) {
        if (defs[i].stage == stage) idx.add(i);
      }
      if (idx.isEmpty) continue;
      if (groups.isNotEmpty) groups.add(const SizedBox(width: 4));
      groups.add(Expanded(
        flex: idx.length,
        child: Row(
          children: [
            for (final i in idx)
              Expanded(
                child: Container(
                  height: height,
                  margin: const EdgeInsets.symmetric(horizontal: 1),
                  decoration: BoxDecoration(
                    color: i < cells.length && cells[i] != FormStatus.todo && cells[i] != FormStatus.na
                        ? sem.statusColor(cells[i])
                        : sem.todoSoft,
                    border: i < cells.length && cells[i] == FormStatus.na ? Border.all(color: sem.na, width: 1) : null,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
          ],
        ),
      ));
    }
    return Row(children: groups);
  }
}

/// شارة حالة الدورة.
class CyclePill extends StatelessWidget {
  const CyclePill(this.state, {super.key});

  final CycleState state;

  @override
  Widget build(BuildContext context) {
    final sem = Sem.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(color: sem.cycleSoft(state), borderRadius: BorderRadius.circular(99)),
      child: Text(state.label,
          style: TextStyle(color: sem.cycleColor(state), fontWeight: FontWeight.w700, fontSize: 12)),
    );
  }
}

/// وسم رقم التكليف.
class NoTag extends StatelessWidget {
  const NoTag(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(color: cs.primaryContainer, borderRadius: BorderRadius.circular(6)),
      child: Text(text.isEmpty ? '—' : text,
          style: TextStyle(color: cs.onPrimaryContainer, fontWeight: FontWeight.w700, fontSize: 12.5, fontFeatures: const [FontFeature.tabularFigures()])),
    );
  }
}

/// اختيار حالة النموذج: أربعة أزرار متجاورة.
class StatusSelector extends StatelessWidget {
  const StatusSelector({super.key, required this.value, required this.onChanged, this.enabled = true, this.busy = false});

  final FormStatus value;
  final ValueChanged<FormStatus>? onChanged;
  final bool enabled;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final sem = Sem.of(context);
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: sem.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: sem.rule),
      ),
      child: Row(
        children: [
          for (final s in FormStatus.values)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 1.5),
                child: Material(
                  color: s == value ? sem.statusSoft(s) : Colors.transparent,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(7),
                    side: s == value ? BorderSide(color: sem.statusColor(s), width: 1.4) : BorderSide.none,
                  ),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(7),
                    onTap: enabled && !busy && s != value && onChanged != null ? () => onChanged!(s) : null,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Center(
                        child: Text(
                          s.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: s == value ? FontWeight.w700 : FontWeight.w500,
                            color: s == value
                                ? (s == FormStatus.todo || s == FormStatus.na ? null : sem.statusColor(s))
                                : (enabled ? sem.muted : sem.muted.withAlpha(140)),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// بطاقة رقم كبير.
class KpiTile extends StatelessWidget {
  const KpiTile({super.key, required this.label, required this.value, this.sub, this.color, this.onTap});

  final String label;
  final String value;
  final String? sub;
  final Color? color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final sem = Sem.of(context);
    final t = Theme.of(context).textTheme;
    return Material(
      color: sem.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: sem.rule)),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label, style: t.bodySmall?.copyWith(color: sem.muted)),
              const SizedBox(height: 2),
              Text(value,
                  style: t.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w700, color: color, fontFeatures: const [FontFeature.tabularFigures()])),
              if (sub != null) Text(sub!, style: t.labelSmall?.copyWith(color: sem.muted)),
            ],
          ),
        ),
      ),
    );
  }
}

/// صف بشريط تقدّم قابل للضغط.
class BarRow extends StatelessWidget {
  const BarRow({super.key, required this.title, required this.trailing, required this.meter, this.subtitle, this.onTap});

  final String title;
  final String trailing;
  final Widget meter;
  final String? subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final sem = Sem.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis)),
                Text(trailing, style: const TextStyle(fontWeight: FontWeight.w700, fontFeatures: [FontFeature.tabularFigures()])),
              ],
            ),
            const SizedBox(height: 6),
            meter,
            if (subtitle != null) ...[
              const SizedBox(height: 4),
              Text(subtitle!, style: TextStyle(fontSize: 11.5, color: sem.muted)),
            ],
          ],
        ),
      ),
    );
  }
}

class Legend extends StatelessWidget {
  const Legend({super.key, required this.items});

  final List<(Color, String)> items;

  @override
  Widget build(BuildContext context) {
    final sem = Sem.of(context);
    return Wrap(
      spacing: 14,
      runSpacing: 4,
      children: [
        for (final it in items)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(width: 10, height: 10, decoration: BoxDecoration(color: it.$1, borderRadius: BorderRadius.circular(3))),
              const SizedBox(width: 6),
              Text(it.$2, style: TextStyle(fontSize: 12, color: sem.muted)),
            ],
          ),
      ],
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.title, this.message, this.icon = Icons.inbox_outlined, this.action});

  final String title;
  final String? message;
  final IconData icon;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final sem = Sem.of(context);
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 40, color: sem.muted),
          const SizedBox(height: 10),
          Text(title, style: t.titleMedium?.copyWith(fontWeight: FontWeight.w700), textAlign: TextAlign.center),
          if (message != null) ...[
            const SizedBox(height: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 380),
              child: Text(message!, textAlign: TextAlign.center, style: TextStyle(color: sem.muted)),
            ),
          ],
          if (action != null) ...[const SizedBox(height: 14), action!],
        ],
      ),
    );
  }
}

/// قائمة منسدلة بعنوان، تستخدم '' لقيمة «الكل».
class SelectField extends StatelessWidget {
  const SelectField({super.key, required this.label, required this.value, required this.items, required this.onChanged});

  final String label;
  final String value;
  final List<(String, String)> items; // (value, label)
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final values = items.map((e) => e.$1).toList();
    return InputDecorator(
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: values.contains(value) ? value : (values.isNotEmpty ? values.first : null),
          isExpanded: true,
          items: [
            for (final it in items)
              DropdownMenuItem<String>(value: it.$1, child: Text(it.$2, maxLines: 1, overflow: TextOverflow.ellipsis)),
          ],
          onChanged: (v) {
            if (v != null) onChanged(v);
          },
        ),
      ),
    );
  }
}

/// نافذة تأكيد بسيطة.
Future<bool> confirmDialog(BuildContext context,
    {required String title, required String message, required String confirmLabel, bool danger = false}) async {
  final sem = Sem.of(context);
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('إلغاء')),
        FilledButton(
          style: danger ? FilledButton.styleFrom(backgroundColor: sem.danger, foregroundColor: Colors.white) : null,
          onPressed: () => Navigator.of(ctx).pop(true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return ok == true;
}

/// نافذة إدخال نص (سبب، ملاحظة...). تُرجع null عند الإلغاء.
Future<String?> textInputDialog(BuildContext context,
    {required String title,
    String? message,
    required String label,
    required String confirmLabel,
    bool required = false,
    String? initial,
    bool multiline = true,
    TextInputType? keyboardType,
    TextDirection? textDirection}) async {
  final controller = TextEditingController(text: initial ?? '');
  final result = await showDialog<String>(
    context: context,
    builder: (ctx) {
      String? error;
      return StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text(title),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (message != null) ...[Text(message), const SizedBox(height: 12)],
                TextField(
                  controller: controller,
                  autofocus: true,
                  minLines: multiline ? 2 : 1,
                  maxLines: multiline ? 5 : 1,
                  keyboardType: keyboardType,
                  textDirection: textDirection,
                  decoration: fieldDeco(label, error: error),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('إلغاء')),
            FilledButton(
              onPressed: () {
                final v = controller.text.trim();
                if (required && v.isEmpty) {
                  setLocal(() => error = 'هذا الحقل مطلوب');
                  return;
                }
                Navigator.of(ctx).pop(v);
              },
              child: Text(confirmLabel),
            ),
          ],
        ),
      );
    },
  );
  return result;
}
