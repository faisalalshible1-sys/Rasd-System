import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../app_state.dart' show friendlyError;
import '../services/export.dart' show saveImageBytes;
import 'theme.dart';
import 'widgets.dart';

// =====================================================================
// لوحات العرض: صفحة واحدة للعرض التقديمي والطباعة، تُحفظ صورةً PNG.
// =====================================================================

/// يلتقط ما داخل [BoardFrame] ذي المفتاح [key] صورةً ويحفظها.
Future<String?> saveBoardImage(GlobalKey key, String baseName, {double pixelRatio = 2}) async {
  final ro = key.currentContext?.findRenderObject();
  if (ro is! RenderRepaintBoundary) throw StateError('تعذّر التقاط اللوحة');
  final image = await ro.toImage(pixelRatio: pixelRatio);
  try {
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    if (data == null) throw StateError('تعذّر إنشاء الصورة');
    return await saveImageBytes(data.buffer.asUint8List(), baseName);
  } finally {
    image.dispose();
  }
}

/// إطار اللوحة: ترويسة بالشعار والعنوان وتاريخ الإسناد، والمحتوى، وسطر المصدر.
class BoardFrame extends StatelessWidget {
  const BoardFrame({
    super.key,
    required this.boundaryKey,
    required this.title,
    required this.org,
    required this.children,
    this.date,
    this.note,
    this.footer,
    this.accent,
  });

  final GlobalKey boundaryKey;
  final String title;
  final String org;
  final String? date;
  final String? note;
  final String? footer;
  final Color? accent;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final sem = Sem.of(context);
    final cs = Theme.of(context).colorScheme;
    final a = accent ?? cs.primary;
    final narrow = MediaQuery.sizeOf(context).width < 700;
    return RepaintBoundary(
      key: boundaryKey,
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: sem.rule),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(
            padding: EdgeInsets.symmetric(horizontal: narrow ? 14 : 22, vertical: narrow ? 12 : 16),
            decoration: BoxDecoration(
              color: a.withValues(alpha: 0.10),
              border: Border(bottom: BorderSide(color: a.withValues(alpha: 0.55), width: 3)),
            ),
            child: Row(children: [
              BrandEmblem(size: narrow ? 38 : 50),
              SizedBox(width: narrow ? 10 : 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title,
                      style: TextStyle(fontSize: narrow ? 16 : 21, fontWeight: FontWeight.w900, color: cs.onSurface, height: 1.3)),
                  const SizedBox(height: 2),
                  Text(org, style: TextStyle(color: sem.muted, fontSize: narrow ? 11.5 : 13)),
                ]),
              ),
              if (date != null) ...[
                const SizedBox(width: 10),
                Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Text('تاريخ الإسناد', style: TextStyle(color: sem.muted, fontSize: 11)),
                  Text(date!, style: TextStyle(fontWeight: FontWeight.w800, fontSize: narrow ? 13 : 15, color: a)),
                ]),
              ],
            ]),
          ),
          if (note != null && note!.isNotEmpty)
            Container(
              color: sem.wipSoft,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 7),
              child: Text(note!, style: TextStyle(color: sem.wip, fontWeight: FontWeight.w700, fontSize: 12.5)),
            ),
          Padding(
            padding: EdgeInsets.all(narrow ? 12 : 18),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
          ),
          if (footer != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
              decoration: BoxDecoration(border: Border(top: BorderSide(color: sem.rule))),
              child: Text(footer!, style: TextStyle(color: sem.muted, fontSize: 11.5)),
            ),
        ]),
      ),
    );
  }
}

/// بطاقة مؤشر مضغوطة للوحة العرض: عنوان، قيمة كبيرة، وسطر توضيح.
class BoardKpi extends StatelessWidget {
  const BoardKpi({super.key, required this.label, required this.value, this.sub, this.color});

  final String label;
  final String value;
  final String? sub;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final sem = Sem.of(context);
    final c = color ?? Theme.of(context).colorScheme.primary;
    final body = Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Text(label, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: sem.muted, fontSize: 12, height: 1.3)),
        const SizedBox(height: 4),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: AlignmentDirectional.centerStart,
          child: Text(value,
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: c, fontFeatures: const [ui.FontFeature.tabularFigures()])),
        ),
        if (sub != null && sub!.isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(sub!, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: sem.muted, fontSize: 11.5, height: 1.3)),
        ],
      ]),
    );
    // شريط لون جانبي داخل إطار مدوّر (حدود غير متماثلة لا تقبل زوايا مدورة)
    return Container(
      decoration: BoxDecoration(color: cardColor(context), borderRadius: BorderRadius.circular(10)),
      clipBehavior: Clip.antiAlias,
      child: IntrinsicHeight(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(width: 4, color: c),
          Expanded(child: body),
        ]),
      ),
    );
  }
}

/// قسم داخل اللوحة بعنوان صغير.
class BoardPanel extends StatelessWidget {
  const BoardPanel({super.key, required this.title, required this.child, this.icon, this.trailing});

  final String title;
  final IconData? icon;
  final String? trailing;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final sem = Sem.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: cardColor(context), borderRadius: BorderRadius.circular(10), border: Border.all(color: sem.rule)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          if (icon != null) ...[Icon(icon, size: 17, color: sem.muted), const SizedBox(width: 6)],
          Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5))),
          if (trailing != null) Text(trailing!, style: TextStyle(color: sem.muted, fontSize: 11.5)),
        ]),
        const SizedBox(height: 10),
        child,
      ]),
    );
  }
}

/// صف في رسم أعمدة أفقية.
class HBar {
  const HBar(this.label, this.value, this.color, {this.text});

  final String label;
  final double value;
  final Color color;

  /// النص المعروض بجانب العمود (افتراضياً القيمة).
  final String? text;
}

/// رسم أعمدة أفقية بسيط يناسب العرض والطباعة (يدعم القيم السالبة بطولها المطلق).
class HBarChart extends StatelessWidget {
  const HBarChart({super.key, required this.bars, this.labelWidth = 150, this.empty = 'لا بيانات بعد.', this.legend});

  final List<HBar> bars;
  final double labelWidth;
  final String empty;
  final List<(Color, String)>? legend;

  @override
  Widget build(BuildContext context) {
    final sem = Sem.of(context);
    if (bars.isEmpty) return Text(empty, style: TextStyle(color: sem.muted, fontSize: 12.5));
    final max = bars.fold<double>(0, (a, b) => b.value.abs() > a ? b.value.abs() : a);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (final b in bars)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(children: [
            SizedBox(
              width: labelWidth,
              child: Text(b.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Container(
                height: 13,
                alignment: AlignmentDirectional.centerStart,
                decoration: BoxDecoration(color: sem.todoSoft, borderRadius: BorderRadius.circular(4)),
                child: FractionallySizedBox(
                  widthFactor: max <= 0 ? 0 : (b.value.abs() / max).clamp(0.0, 1.0),
                  child: Container(decoration: BoxDecoration(color: b.color, borderRadius: BorderRadius.circular(4))),
                ),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 58,
              child: Text(b.text ?? _num(b.value),
                  textAlign: TextAlign.end,
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, fontFeatures: [ui.FontFeature.tabularFigures()])),
            ),
          ]),
        ),
      if (legend != null) ...[
        const SizedBox(height: 6),
        Wrap(spacing: 14, runSpacing: 4, children: [
          for (final l in legend!)
            Row(mainAxisSize: MainAxisSize.min, children: [
              Container(width: 10, height: 10, decoration: BoxDecoration(color: l.$1, borderRadius: BorderRadius.circular(3))),
              const SizedBox(width: 5),
              Text(l.$2, style: TextStyle(fontSize: 11.5, color: sem.muted)),
            ]),
        ]),
      ],
    ]);
  }

  static String _num(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);
}

/// مجموعات أعمدة مزدوجة أفقية (مثل: عند التسجيل مقابل الحالي) لكل فئة.
class PairBarChart extends StatelessWidget {
  const PairBarChart({super.key, required this.groups, required this.names, this.labelWidth = 110});

  /// (الفئة، القيمة الأولى، القيمة الثانية، اللون)
  final List<(String, double, double, Color)> groups;

  /// اسما القيمتين للإيضاح.
  final (String, String) names;
  final double labelWidth;

  @override
  Widget build(BuildContext context) {
    final sem = Sem.of(context);
    final max = groups.fold<double>(0, (a, g) => [a, g.$2, g.$3].reduce((x, y) => x > y ? x : y));
    Widget bar(double v, Color c) => Row(children: [
          Expanded(
            child: Container(
              height: 9,
              alignment: AlignmentDirectional.centerStart,
              child: FractionallySizedBox(
                widthFactor: max <= 0 ? 0 : (v / max).clamp(0.0, 1.0),
                child: Container(decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(3))),
              ),
            ),
          ),
          SizedBox(
            width: 30,
            child: Text(v.toStringAsFixed(0),
                textAlign: TextAlign.end, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700)),
          ),
        ]);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (final g in groups)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(children: [
            SizedBox(
              width: labelWidth,
              child: Row(children: [
                Container(width: 9, height: 9, decoration: BoxDecoration(color: g.$4, shape: BoxShape.circle)),
                const SizedBox(width: 6),
                Expanded(child: Text(g.$1, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12))),
              ]),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(children: [
                bar(g.$2, g.$4.withValues(alpha: 0.35)),
                const SizedBox(height: 3),
                bar(g.$3, g.$4),
              ]),
            ),
          ]),
        ),
      const SizedBox(height: 6),
      Wrap(spacing: 14, children: [
        for (final (i, n) in [(0.35, names.$1), (1.0, names.$2)])
          Row(mainAxisSize: MainAxisSize.min, children: [
            Container(
                width: 14,
                height: 8,
                decoration: BoxDecoration(color: sem.muted.withValues(alpha: i), borderRadius: BorderRadius.circular(2))),
            const SizedBox(width: 5),
            Text(n, style: TextStyle(fontSize: 11.5, color: sem.muted)),
          ]),
      ]),
    ]);
  }
}

/// زر حفظ اللوحة صورةً (يعرض مؤشر انتظار أثناء الحفظ).
class SaveBoardButton extends StatefulWidget {
  const SaveBoardButton({super.key, required this.boundaryKey, required this.fileName});

  final GlobalKey boundaryKey;
  final String fileName;

  @override
  State<SaveBoardButton> createState() => _SaveBoardButtonState();
}

class _SaveBoardButtonState extends State<SaveBoardButton> {
  bool _busy = false;

  Future<void> _save() async {
    setState(() => _busy = true);
    try {
      final r = await saveBoardImage(widget.boundaryKey, widget.fileName);
      if (mounted && r != null) showToast(context, 'حُفظت اللوحة صورةً');
    } catch (e) {
      if (mounted) showToast(context, friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => FilledButton.icon(
        onPressed: _busy ? null : _save,
        icon: _busy
            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.image_outlined),
        label: const Text('حفظ صورة'),
      );
}
