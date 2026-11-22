import 'package:flutter/material.dart';

import '../models.dart';
import 'motion.dart';
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

/// بطاقة قسم بعنوان، وأيقونة وشرح اختياريين.
class SectionCard extends StatelessWidget {
  const SectionCard({
    super.key,
    required this.title,
    this.trailing,
    required this.child,
    this.padding,
    this.icon,
    this.subtitle,
  });

  final String title;
  final Widget? trailing;
  final Widget child;
  final EdgeInsets? padding;
  final IconData? icon;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final sem = Sem.of(context);
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    // Material شفافة فوق لون البطاقة حتى يظهر أثر الضغط في عناصر القوائم داخلها
    return Container(
      decoration: cardDecoration(context),
      child: Material(
        type: MaterialType.transparency,
        child: Padding(
      padding: padding ?? EdgeInsets.all(appearance.pad + 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (icon != null) ...[
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(color: cs.primaryContainer, borderRadius: BorderRadius.circular(10)),
                  child: Icon(icon, size: 19, color: cs.onPrimaryContainer),
                ),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: t.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                    if (subtitle != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(subtitle!, style: t.bodySmall?.copyWith(color: sem.muted, height: 1.5)),
                      ),
                  ],
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
        ),
      ),
    );
  }
}

/// غلاف صفحة: عرض أقصى ومسافات موحّدة وسحب للتحديث.
class PageBody extends StatelessWidget {
  const PageBody({super.key, required this.children, this.maxWidth = 1180, this.onRefresh, this.padding});

  final List<Widget> children;
  final double maxWidth;
  final Future<void> Function()? onRefresh;
  final EdgeInsets? padding;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final narrow = width < 600;
    final list = LayoutBuilder(builder: (context, c) {
      final side = c.maxWidth > maxWidth + 48 ? (c.maxWidth - maxWidth) / 2 : (narrow ? 14.0 : 24.0);
      return ListView(
        padding: padding ?? EdgeInsets.fromLTRB(side, narrow ? 14 : 22, side, 40),
        children: children,
      );
    });
    final refresh = onRefresh;
    return refresh == null ? list : RefreshIndicator(onRefresh: refresh, child: list);
  }
}

/// ترويسة صفحة: عنوان وشرح وأزرار.
class PageHeader extends StatelessWidget {
  const PageHeader({super.key, required this.title, this.subtitle, this.actions = const [], this.icon});

  final String title;
  final String? subtitle;
  final List<Widget> actions;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final sem = Sem.of(context);
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        runSpacing: 12,
        spacing: 12,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(color: cs.primaryContainer, borderRadius: BorderRadius.circular(13)),
                  child: Icon(icon, color: cs.onPrimaryContainer),
                ),
                const SizedBox(width: 12),
              ],
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(title, style: t.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
                    if (subtitle != null)
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 640),
                        child: Text(subtitle!, style: t.bodyMedium?.copyWith(color: sem.muted)),
                      ),
                  ],
                ),
              ),
            ],
          ),
          if (actions.isNotEmpty) Wrap(spacing: 8, runSpacing: 8, children: actions),
        ],
      ),
    );
  }
}

/// بطاقة مؤشر: أيقونة ورقم وعنوان.
class StatCard extends StatelessWidget {
  const StatCard({super.key, required this.label, required this.value, this.icon, this.sub, this.color, this.onTap});

  final String label;
  final String value;
  final IconData? icon;
  final String? sub;
  final Color? color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final sem = Sem.of(context);
    final t = Theme.of(context).textTheme;
    final c = color ?? Theme.of(context).colorScheme.primary;
    final card = Material(
      color: cardColor(context),
      elevation: cardElevation(context),
      shadowColor: Colors.black26,
      shape: cardShape(context),
      child: InkWell(
        borderRadius: BorderRadius.circular(appearance.radius),
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.all(appearance.pad),
          child: Row(
            children: [
              if (icon != null) ...[
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(color: c.withAlpha(28), borderRadius: BorderRadius.circular(12)),
                  child: Icon(icon, color: c, size: 22),
                ),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // سطران للعنوان والشرح حتى لا تُقطع العناوين الطويلة في بطاقات الهاتف الضيقة
                    Text(label, maxLines: 2, overflow: TextOverflow.ellipsis, style: t.bodySmall?.copyWith(color: sem.muted)),
                    _value(t),
                    if (sub != null) Text(sub!, maxLines: 2, overflow: TextOverflow.ellipsis, style: t.labelSmall?.copyWith(color: sem.muted)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
    return onTap == null ? card : HoverLift(child: card);
  }

  /// القيمة الواحدة بلا مسافات (رقم، تاريخ، نسبة) تُصغَّر لتبقى في سطر واحد بدل أن تنكسر في البطاقات الضيقة؛
  /// والنص الطويل ذو الكلمات (كالأسماء) يلتف كما هو.
  Widget _value(TextTheme t) {
    final text = Text(value,
        style: t.headlineSmall?.copyWith(fontWeight: FontWeight.w700, fontFeatures: const [FontFeature.tabularFigures()]));
    if (value.trim().contains(' ')) return text;
    return FittedBox(fit: BoxFit.scaleDown, alignment: AlignmentDirectional.centerStart, child: text);
  }
}

/// شبكة متجاوبة لبطاقات متساوية العرض.
class ResponsiveGrid extends StatelessWidget {
  const ResponsiveGrid({super.key, required this.children, this.minItemWidth = 220, this.spacing = 12});

  final List<Widget> children;
  final double minItemWidth;
  final double spacing;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      var cols = (c.maxWidth / minItemWidth).floor().clamp(1, 6);
      final n = children.length;
      if (n >= 2 && n < cols) {
        // عناصر أقل من الأعمدة: تملأ العرض بدل ترك فراغ
        cols = n;
      } else if (n > cols && n % cols != 0) {
        // صف أخير ناقص: أعمدة أقل قليلاً إن ملأت الصفوف كلها
        for (var k = cols - 1; k >= (cols * 0.7).ceil() && k >= 2; k--) {
          if (n % k == 0) {
            cols = k;
            break;
          }
        }
      }
      final w = (c.maxWidth - spacing * (cols - 1)) / cols;
      return Wrap(
        spacing: spacing,
        runSpacing: spacing,
        children: [for (final ch in children) SizedBox(width: w, child: ch)],
      );
    });
  }
}

/// صف إعداد: عنوان وشرح وعنصر تحكم.
class SettingRow extends StatelessWidget {
  const SettingRow({super.key, required this.title, this.subtitle, this.trailing, this.icon, this.onTap, this.danger = false});

  final String title;
  final String? subtitle;
  final Widget? trailing;
  final IconData? icon;
  final VoidCallback? onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final sem = Sem.of(context);
    final color = danger ? sem.danger : null;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        child: Row(
          children: [
            if (icon != null) ...[
              Icon(icon, size: 21, color: color ?? sem.muted),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: TextStyle(fontWeight: FontWeight.w600, color: color)),
                  if (subtitle != null) Text(subtitle!, style: TextStyle(color: sem.muted, fontSize: 12.5, height: 1.5)),
                ],
              ),
            ),
            if (trailing != null) ...[const SizedBox(width: 10), trailing!],
          ],
        ),
      ),
    );
  }
}

/// شارة نصية ملونة.
class ToneBadge extends StatelessWidget {
  const ToneBadge(this.text, {super.key, required this.color, this.icon});

  final String text;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(color: color.withAlpha(30), borderRadius: BorderRadius.circular(99)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: 13, color: color), const SizedBox(width: 4)],
          Text(text, style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 11.5)),
        ],
      ),
    );
  }
}

/// شريط تنبيه داخل الصفحة.
class InfoBanner extends StatelessWidget {
  const InfoBanner({super.key, required this.text, this.level = 'info', this.icon, this.action});

  final String text;
  final String level; // info | warning | critical | ok
  final IconData? icon;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final sem = Sem.of(context);
    final cs = Theme.of(context).colorScheme;
    final (bg, fg, ic) = switch (level) {
      'warning' => (sem.wipSoft, sem.wip, Icons.warning_amber_rounded),
      'critical' => (sem.dangerSoft, sem.danger, Icons.gpp_maybe_outlined),
      'ok' => (sem.okSoft, sem.ok, Icons.verified_outlined),
      _ => (cs.primaryContainer, cs.onPrimaryContainer, Icons.campaign_outlined),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(14)),
      child: Row(
        children: [
          Icon(icon ?? ic, color: fg, size: 20),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: TextStyle(color: fg, fontWeight: FontWeight.w600, height: 1.5))),
          if (action != null) action!,
        ],
      ),
    );
  }
}

/// دائرة بالحرف الأول من الاسم.
class InitialsAvatar extends StatelessWidget {
  const InitialsAvatar({super.key, required this.name, this.size = 36, this.color});

  final String name;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final words = name.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    final letters = words.isEmpty
        ? '؟'
        : (words.length == 1 ? words.first.characters.first : '${words.first.characters.first}${words[1].characters.first}');
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: color ?? cs.primaryContainer, shape: BoxShape.circle),
      child: Text(letters,
          style: TextStyle(color: color == null ? cs.onPrimaryContainer : Colors.white, fontWeight: FontWeight.w700, fontSize: size * 0.38)),
    );
  }
}

/// اختيار جهات الاختصاص (من يحدّث النموذج أو الحقل).
class TokenSelector extends StatelessWidget {
  const TokenSelector({super.key, required this.selected, required this.onChanged, this.enabled = true});

  final List<String> selected;
  final ValueChanged<List<String>> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final t in responsibleLabels.keys)
          FilterChip(
            label: Text(responsibleLabels[t]!, style: const TextStyle(fontSize: 12.5)),
            selected: selected.contains(t),
            onSelected: !enabled
                ? null
                : (sel) {
                    final next = [...selected];
                    if (sel) {
                      if (!next.contains(t)) next.add(t);
                    } else {
                      next.remove(t);
                    }
                    onChanged(next);
                  },
          ),
      ],
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
      child: Container(
        height: height,
        color: sem.todoSoft,
        child: total == 0
            ? null
            : RevealWidth(
                child: Row(
                  children: [
                    for (final p in parts)
                      if (p.$1 > 0) Expanded(flex: p.$1, child: Container(color: p.$2)),
                  ],
                ),
              ),
      ),
    );
  }
}

/// شريط الدورة المستندية: خانة لكل نموذج، مجمّعة في المراحل الخمس.
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
                        : (i < cells.length && cells[i] == FormStatus.todo ? sem.statusSoft(FormStatus.todo) : sem.todoSoft),
                    border: i < cells.length && cells[i] == FormStatus.na ? Border.all(color: sem.na, width: 1) : null,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
          ],
        ),
      ));
    }
    return RevealWidth(duration: 1100, child: Row(children: groups));
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

/// وسم العقد: «عقد 12/2026»، أو رقم التكليف إن لم يُحدَّد رقم العقد بعد.
class ContractTag extends StatelessWidget {
  const ContractTag(this.project, {super.key, this.large = false});

  final Project project;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final has = project.contractNo.isNotEmpty;
    final fg = has ? cs.onPrimary : cs.onPrimaryContainer;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: large ? 12 : 8, vertical: large ? 5 : 3),
      decoration: BoxDecoration(color: has ? cs.primary : cs.primaryContainer, borderRadius: BorderRadius.circular(8)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(has ? Icons.description_outlined : Icons.tag_rounded, size: large ? 16 : 13, color: fg),
          const SizedBox(width: 4),
          Text(
            has ? 'عقد ${project.contractNo}' : (project.assignNo.isEmpty ? 'بلا رقم' : project.assignNo),
            style: TextStyle(
              color: fg,
              fontWeight: FontWeight.w700,
              fontSize: large ? 14 : 12.5,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
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
    final r = (appearance.radius * 0.8).clamp(6.0, 22.0);
    return Material(
      color: cardColor(context),
      elevation: cardElevation(context),
      shadowColor: Colors.black26,
      shape: cardShape(context, radius: r),
      child: InkWell(
        borderRadius: BorderRadius.circular(r),
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: appearance.pad - 2, vertical: appearance.pad - 4),
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
