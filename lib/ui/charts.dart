import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models.dart';
import 'motion.dart';
import 'theme.dart';

/// رسوم بيانية مرسومة يدوياً (بلا مكتبات): منحنى زمني بخط أو مساحة أو أعمدة، وتوزيع حلقي أو دائري أو أشرطة،
/// وشريط مكدّس. شكلها من إعداد المظهر (ui.appearance.charts) ويمكن تجاوزه لكل رسم.

/// مبلغ مختصر للمحاور والتسميات (12.5 ألف، 3.2 م، 1.1 مليار).
String compactMoney(double v) {
  final a = v.abs();
  String f(double x) {
    final s = x >= 100 ? x.toStringAsFixed(0) : x.toStringAsFixed(1);
    return s.endsWith('.0') ? s.substring(0, s.length - 2) : s;
  }

  final sign = v < 0 ? '-' : '';
  if (a >= 1e9) return '$sign${f(a / 1e9)} مليار';
  if (a >= 1e6) return '$sign${f(a / 1e6)} م';
  if (a >= 1e3) return '$sign${f(a / 1e3)} ألف';
  return '$sign${f(a)}';
}

/// سلسلة بيانات في رسم زمني.
class ChartSeries {
  const ChartSeries(this.name, this.values, {this.color});

  final String name;
  final List<double> values;
  final Color? color;
}

/// منحنى زمني: خط أو مساحة أو أعمدة، بسلسلة أو أكثر، مع شبكة ونقاط وقيم وتلميح عند اللمس.
class TrendChart extends StatefulWidget {
  const TrendChart({
    super.key,
    required this.labels,
    required this.series,
    this.style,
    this.type,
    this.height = 240,
    this.format = compactMoney,
    this.tooltipFormat,
  });

  final List<String> labels;
  final List<ChartSeries> series;
  final ChartStyle? style;
  final String? type; // line | area | bar (الافتراضي من الإعداد)
  final double height;
  final String Function(double) format;
  final String Function(double)? tooltipFormat;

  @override
  State<TrendChart> createState() => _TrendChartState();
}

class _TrendChartState extends State<TrendChart> {
  int? _selected;

  @override
  Widget build(BuildContext context) {
    final st = widget.style ?? appearance.charts;
    final type = widget.type ?? st.trend;
    final palette = st.colors(context);
    final colors = [
      for (var i = 0; i < widget.series.length; i++) widget.series[i].color ?? palette[i % palette.length],
    ];
    final sem = Sem.of(context);
    final t = Theme.of(context).textTheme;
    final n = widget.labels.length;
    if (n == 0 || widget.series.every((s) => s.values.every((v) => v == 0))) {
      return SizedBox(
        height: widget.height * 0.6,
        child: Center(child: Text('لا توجد بيانات كافية للرسم بعد.', style: TextStyle(color: sem.muted))),
      );
    }
    final dataKey = Object.hashAll([type, n, for (final s in widget.series) ...s.values]);
    final animate = st.animate && Motion.enabled(context);
    final chart = LayoutBuilder(builder: (context, c) {
      final geo = _TrendGeometry(width: c.maxWidth, height: widget.height, count: n, series: widget.series, bar: type == 'bar');
      void pick(Offset local) {
        final i = geo.indexAt(local.dx);
        if (i != _selected) setState(() => _selected = i);
      }

      return MouseRegion(
        onHover: (e) => pick(e.localPosition),
        onExit: (_) => setState(() => _selected = null),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (d) => pick(d.localPosition),
          onHorizontalDragUpdate: (d) => pick(d.localPosition),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              TweenAnimationBuilder<double>(
                key: ValueKey(dataKey),
                tween: Tween(begin: animate ? 0 : 1, end: 1),
                duration: Duration(milliseconds: animate ? 900 : 0),
                curve: Curves.easeOutCubic,
                builder: (context, p, _) => CustomPaint(
                  size: Size(c.maxWidth, widget.height),
                  painter: _TrendPainter(
                    geo: geo,
                    progress: p,
                    labels: widget.labels,
                    series: widget.series,
                    colors: colors,
                    type: type,
                    style: st,
                    selected: _selected,
                    gridColor: sem.rule,
                    textStyle: (t.labelSmall ?? const TextStyle(fontSize: 11)).copyWith(color: sem.muted),
                    valueStyle: (t.labelSmall ?? const TextStyle(fontSize: 11))
                        .copyWith(color: Theme.of(context).colorScheme.onSurface, fontWeight: FontWeight.w700),
                    format: widget.format,
                    surface: cardColor(context),
                  ),
                ),
              ),
              if (_selected != null) _tooltip(context, geo, colors),
            ],
          ),
        ),
      );
    });
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Directionality(textDirection: TextDirection.ltr, child: SizedBox(height: widget.height, child: chart)),
        if (st.legend && widget.series.length > 1) ...[
          const SizedBox(height: 10),
          ChartLegend(items: [for (var i = 0; i < widget.series.length; i++) (colors[i], widget.series[i].name)]),
        ],
      ],
    );
  }

  Widget _tooltip(BuildContext context, _TrendGeometry geo, List<Color> colors) {
    final i = _selected!;
    final fmt = widget.tooltipFormat ?? (v) => '${fmtMoney(v)} $currencyLabel';
    final x = geo.xAt(i);
    const w = 190.0;
    final left = (x + 12 + w > geo.width) ? x - w - 12 : x + 12;
    return Positioned(
      left: left.clamp(0, math.max(0, geo.width - w)).toDouble(),
      top: 4,
      child: IgnorePointer(
        child: Directionality(
          textDirection: TextDirection.rtl,
          child: Container(
            width: w,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: toneOf(context).overlay.withValues(alpha: 0.94),
              borderRadius: BorderRadius.circular(10),
              boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 12, offset: Offset(0, 4))],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(widget.labels[i], style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12)),
                const SizedBox(height: 4),
                for (var s = 0; s < widget.series.length; s++)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Row(
                      children: [
                        Container(width: 8, height: 8, decoration: BoxDecoration(color: colors[s], shape: BoxShape.circle)),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(widget.series[s].name,
                              maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 11.5)),
                        ),
                        Text(fmt(i < widget.series[s].values.length ? widget.series[s].values[i] : 0),
                            style: const TextStyle(color: Colors.white, fontSize: 11.5, fontFeatures: [FontFeature.tabularFigures()])),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TrendGeometry {
  _TrendGeometry({required this.width, required this.height, required this.count, required List<ChartSeries> series, required this.bar}) {
    var hi = 0.0, lo = 0.0;
    for (final s in series) {
      for (final v in s.values) {
        hi = math.max(hi, v);
        lo = math.min(lo, v);
      }
    }
    final top = _nice(hi <= 0 ? 1 : hi * 1.08);
    maxY = top;
    minY = lo < 0 ? -_nice(-lo * 1.08) : 0;
  }

  final double width;
  final double height;
  final int count;
  final bool bar;
  late final double maxY;
  late final double minY;

  static const double left = 58;
  static const double right = 12;
  static const double topPad = 14;
  static const double bottom = 26;

  double get plotW => math.max(10, width - left - right);
  double get plotH => math.max(10, height - topPad - bottom);

  double xAt(int i) {
    if (bar) return left + plotW * (i + 0.5) / count;
    if (count == 1) return left + plotW / 2;
    return left + plotW * i / (count - 1);
  }

  double yAt(double v) => topPad + plotH * (1 - (v - minY) / (maxY - minY == 0 ? 1 : maxY - minY));

  int indexAt(double dx) {
    if (count <= 1) return 0;
    final rel = ((dx - left) / plotW).clamp(0.0, 1.0);
    return bar ? (rel * count).floor().clamp(0, count - 1) : (rel * (count - 1)).round();
  }

  static double _nice(double v) {
    final e = math.pow(10, (math.log(v) / math.ln10).floor()).toDouble();
    final f = v / e;
    final n = f <= 1 ? 1.0 : f <= 2 ? 2.0 : f <= 2.5 ? 2.5 : f <= 5 ? 5.0 : 10.0;
    return n * e;
  }
}

class _TrendPainter extends CustomPainter {
  _TrendPainter({
    required this.geo,
    required this.progress,
    required this.labels,
    required this.series,
    required this.colors,
    required this.type,
    required this.style,
    required this.selected,
    required this.gridColor,
    required this.textStyle,
    required this.valueStyle,
    required this.format,
    required this.surface,
  });

  final _TrendGeometry geo;
  final double progress;
  final List<String> labels;
  final List<ChartSeries> series;
  final List<Color> colors;
  final String type;
  final ChartStyle style;
  final int? selected;
  final Color gridColor;
  final TextStyle textStyle;
  final TextStyle valueStyle;
  final String Function(double) format;
  final Color surface;

  void _text(Canvas c, String s, Offset at, TextStyle st, {TextAlign align = TextAlign.center, double maxW = 120}) {
    final tp = TextPainter(text: TextSpan(text: s, style: st), textDirection: TextDirection.rtl, textAlign: align, maxLines: 1, ellipsis: '…')
      ..layout(maxWidth: maxW);
    final dx = switch (align) { TextAlign.right => at.dx - tp.width, TextAlign.left => at.dx, _ => at.dx - tp.width / 2 };
    tp.paint(c, Offset(dx, at.dy - tp.height / 2));
  }

  @override
  void paint(Canvas canvas, Size size) {
    final g = geo;
    // الشبكة والمحور الرأسي
    const lines = 4;
    final gridPaint = Paint()
      ..color = gridColor.withValues(alpha: 0.7)
      ..strokeWidth = 1;
    for (var k = 0; k <= lines; k++) {
      final v = g.minY + (g.maxY - g.minY) * k / lines;
      final y = g.yAt(v);
      if (style.grid || k == 0) {
        _dashed(canvas, Offset(_TrendGeometry.left, y), Offset(g.width - _TrendGeometry.right, y), gridPaint, dashed: k != 0 && v != 0);
      }
      _text(canvas, format(v), Offset(_TrendGeometry.left - 6, y), textStyle, align: TextAlign.right, maxW: 54);
    }
    if (g.minY < 0) {
      canvas.drawLine(Offset(_TrendGeometry.left, g.yAt(0)), Offset(g.width - _TrendGeometry.right, g.yAt(0)), gridPaint..strokeWidth = 1.2);
    }

    // تسميات المحور الأفقي (حتى 8 تسميات)
    final n = labels.length;
    final step = math.max(1, (n / 8).ceil());
    for (var i = 0; i < n; i += step) {
      _text(canvas, labels[i], Offset(g.xAt(i), g.height - _TrendGeometry.bottom / 2 + 2), textStyle, maxW: math.max(40, g.plotW / math.min(n, 8)));
    }

    // خط الاختيار
    if (selected != null) {
      final x = g.xAt(selected!);
      canvas.drawLine(Offset(x, _TrendGeometry.topPad), Offset(x, _TrendGeometry.topPad + g.plotH),
          Paint()
            ..color = gridColor
            ..strokeWidth = g.bar ? g.plotW / n * 0.9 : 1.2);
    }

    if (type == 'bar') {
      _bars(canvas);
    } else {
      _lines(canvas);
    }
  }

  void _bars(Canvas canvas) {
    final g = geo;
    final n = labels.length;
    final groupW = g.plotW / n;
    final m = series.length;
    final barW = math.min(34.0, groupW * 0.72 / m);
    final base = g.yAt(math.max(0, g.minY));
    for (var s = 0; s < m; s++) {
      final paint = Paint()..color = colors[s];
      for (var i = 0; i < n && i < series[s].values.length; i++) {
        final v = series[s].values[i] * progress;
        final cx = g.xAt(i) - (m * barW) / 2 + barW * (s + 0.5);
        final y = g.yAt(v);
        final r = RRect.fromRectAndCorners(
          Rect.fromLTRB(cx - barW / 2 + 1, math.min(y, base), cx + barW / 2 - 1, math.max(y, base)),
          topLeft: Radius.circular(v >= 0 ? 4 : 0),
          topRight: Radius.circular(v >= 0 ? 4 : 0),
          bottomLeft: Radius.circular(v < 0 ? 4 : 0),
          bottomRight: Radius.circular(v < 0 ? 4 : 0),
        );
        canvas.drawRRect(r, paint..color = selected == null || selected == i ? colors[s] : colors[s].withValues(alpha: 0.55));
        if (style.values && progress > 0.95 && series[s].values[i] != 0) {
          _text(canvas, format(series[s].values[i]), Offset(cx, math.min(y, base) - 9), valueStyle, maxW: 70);
        }
      }
    }
  }

  void _lines(Canvas canvas) {
    final g = geo;
    final n = labels.length;
    final clipW = _TrendGeometry.left + g.plotW * progress + 4;
    canvas.save();
    canvas.clipRect(Rect.fromLTWH(0, 0, clipW, g.height));
    for (var s = 0; s < series.length; s++) {
      final vals = series[s].values;
      if (vals.isEmpty) continue;
      final pts = [for (var i = 0; i < n && i < vals.length; i++) Offset(g.xAt(i), g.yAt(vals[i]))];
      final path = Path()..moveTo(pts.first.dx, pts.first.dy);
      for (var i = 1; i < pts.length; i++) {
        final a = pts[i - 1], b = pts[i];
        if (style.curved) {
          final mx = (a.dx + b.dx) / 2;
          path.cubicTo(mx, a.dy, mx, b.dy, b.dx, b.dy);
        } else {
          path.lineTo(b.dx, b.dy);
        }
      }
      if (type == 'area') {
        final base = g.yAt(math.max(0, g.minY));
        final area = Path.from(path)
          ..lineTo(pts.last.dx, base)
          ..lineTo(pts.first.dx, base)
          ..close();
        canvas.drawPath(
          area,
          Paint()
            ..shader = LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [colors[s].withValues(alpha: series.length > 1 ? 0.18 : 0.28), colors[s].withValues(alpha: 0.02)],
            ).createShader(Rect.fromLTWH(0, _TrendGeometry.topPad, g.width, g.plotH)),
        );
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = colors[s]
          ..style = PaintingStyle.stroke
          ..strokeWidth = style.stroke
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
      if (style.points || selected != null) {
        for (var i = 0; i < pts.length; i++) {
          final sel = selected == i;
          if (!style.points && !sel) continue;
          final r = sel ? style.stroke + 3.2 : style.stroke + 1.2;
          canvas.drawCircle(pts[i], r, Paint()..color = surface);
          canvas.drawCircle(
              pts[i],
              r,
              Paint()
                ..color = colors[s]
                ..style = PaintingStyle.stroke
                ..strokeWidth = math.max(1.5, style.stroke * 0.8));
        }
      }
      if (style.values && progress > 0.95) {
        for (var i = 0; i < pts.length; i++) {
          if (vals[i] == 0) continue;
          _text(canvas, format(vals[i]), pts[i].translate(0, -12), valueStyle, maxW: 70);
        }
      }
    }
    canvas.restore();
  }

  void _dashed(Canvas c, Offset a, Offset b, Paint p, {bool dashed = true}) {
    if (!dashed) {
      c.drawLine(a, b, p);
      return;
    }
    const d = 4.0, gap = 4.0;
    var x = a.dx;
    while (x < b.dx) {
      c.drawLine(Offset(x, a.dy), Offset(math.min(x + d, b.dx), b.dy), p);
      x += d + gap;
    }
  }

  @override
  bool shouldRepaint(covariant _TrendPainter old) =>
      old.progress != progress || old.selected != selected || old.type != type || old.series != series || old.style != style;
}

/// توزيع قيم على فئات: حلقة أو دائرة أو أشرطة أفقية.
class BreakdownChart extends StatelessWidget {
  const BreakdownChart({
    super.key,
    required this.items,
    this.style,
    this.type,
    this.size = 190,
    this.centerTitle,
    this.centerValue,
    this.format,
    this.colors,
    this.onTap,
  });

  final List<(String, double)> items;
  final ChartStyle? style;
  final String? type; // donut | pie | bar
  final double size;
  final String? centerTitle;
  final String? centerValue;
  final String Function(double)? format;
  final List<Color>? colors;
  final void Function(int index)? onTap;

  @override
  Widget build(BuildContext context) {
    final st = style ?? appearance.charts;
    final kind = type ?? st.breakdown;
    final palette = colors ?? st.colors(context);
    final sem = Sem.of(context);
    final fmt = format ?? (v) => '${fmtMoney(v)} $currencyLabel';
    final total = items.fold<double>(0, (a, e) => a + math.max(0, e.$2));
    if (items.isEmpty || total <= 0) {
      return SizedBox(height: size * 0.6, child: Center(child: Text('لا توجد قيم بعد.', style: TextStyle(color: sem.muted))));
    }
    Color colorAt(int i) => palette[i % palette.length];
    final animate = st.animate && Motion.enabled(context);

    if (kind == 'bar') {
      final maxV = items.fold<double>(0, (a, e) => math.max(a, e.$2));
      return Column(
        children: [
          for (var i = 0; i < items.length; i++)
            InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: onTap == null ? null : () => onTap!(i),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(children: [
                      Container(width: 9, height: 9, decoration: BoxDecoration(color: colorAt(i), borderRadius: BorderRadius.circular(3))),
                      const SizedBox(width: 6),
                      Expanded(child: Text(items[i].$1, maxLines: 1, overflow: TextOverflow.ellipsis)),
                      Text(fmt(items[i].$2), style: const TextStyle(fontWeight: FontWeight.w700, fontFeatures: [FontFeature.tabularFigures()])),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 44,
                        child: Text(pctOf(items[i].$2, total), textAlign: TextAlign.end, style: TextStyle(color: sem.muted, fontSize: 12)),
                      ),
                    ]),
                    const SizedBox(height: 5),
                    AnimatedMeter(value: maxV <= 0 ? 0 : (items[i].$2 / maxV).clamp(0, 1).toDouble(), color: colorAt(i), height: 8),
                  ],
                ),
              ),
            ),
        ],
      );
    }

    final ring = TweenAnimationBuilder<double>(
      key: ValueKey(Object.hashAll([kind, for (final e in items) e.$2])),
      tween: Tween(begin: animate ? 0 : 1, end: 1),
      duration: Duration(milliseconds: animate ? 950 : 0),
      curve: Curves.easeOutCubic,
      builder: (context, p, _) => CustomPaint(
        size: Size.square(size),
        painter: _RingPainter(
          values: [for (final e in items) math.max(0, e.$2)],
          colors: [for (var i = 0; i < items.length; i++) colorAt(i)],
          progress: p,
          hole: kind == 'pie' ? 0 : 0.62,
          gapColor: cardColor(context),
        ),
      ),
    );
    final center = kind == 'pie' || (centerTitle == null && centerValue == null)
        ? null
        : Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (centerValue != null)
                Text(centerValue!, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
              if (centerTitle != null) Text(centerTitle!, style: TextStyle(color: sem.muted, fontSize: 11.5)),
            ],
          );
    final legend = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < items.length; i++)
          InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: onTap == null ? null : () => onTap!(i),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
              child: Row(children: [
                Container(width: 10, height: 10, decoration: BoxDecoration(color: colorAt(i), borderRadius: BorderRadius.circular(3))),
                const SizedBox(width: 8),
                Expanded(child: Text(items[i].$1, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13))),
                const SizedBox(width: 6),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(fmt(items[i].$2), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5, fontFeatures: [FontFeature.tabularFigures()])),
                    Text(pctOf(items[i].$2, total), style: TextStyle(color: sem.muted, fontSize: 11)),
                  ],
                ),
              ]),
            ),
          ),
      ],
    );
    return LayoutBuilder(builder: (context, c) {
      final graphic = SizedBox.square(
        dimension: size,
        child: Stack(alignment: Alignment.center, children: [ring, if (center != null) center]),
      );
      if (!st.legend) return Center(child: graphic);
      if (c.maxWidth < size + 220) {
        return Column(children: [graphic, const SizedBox(height: 12), legend]);
      }
      return Row(
        children: [graphic, const SizedBox(width: 20), Expanded(child: legend)],
      );
    });
  }
}

/// نسبة مقروءة من المجموع.
String pctOf(double v, double total) => total <= 0 ? '—' : '${(v / total * 100).toStringAsFixed(v / total >= 0.1 ? 0 : 1)}%';

class _RingPainter extends CustomPainter {
  _RingPainter({required this.values, required this.colors, required this.progress, required this.hole, required this.gapColor});

  final List<double> values;
  final List<Color> colors;
  final double progress;
  final double hole; // 0 = دائرة كاملة
  final Color gapColor;

  @override
  void paint(Canvas canvas, Size size) {
    final total = values.fold<double>(0, (a, v) => a + v);
    if (total <= 0) return;
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2;
    final rect = Rect.fromCircle(center: c, radius: r);
    var start = -math.pi / 2;
    final sweepAll = 2 * math.pi * progress;
    for (var i = 0; i < values.length; i++) {
      final sweep = sweepAll * values[i] / total;
      if (sweep <= 0) continue;
      final paint = Paint()..color = colors[i];
      if (hole > 0) {
        final w = r * (1 - hole);
        canvas.drawArc(
          rect.deflate(w / 2),
          start,
          sweep,
          false,
          paint
            ..style = PaintingStyle.stroke
            ..strokeWidth = w
            ..strokeCap = StrokeCap.butt,
        );
      } else {
        canvas.drawArc(rect, start, sweep, true, paint);
      }
      // فاصل رفيع بين الأجزاء
      if (values.where((v) => v > 0).length > 1) {
        final a = start + sweep;
        canvas.drawLine(
          c + Offset(math.cos(a), math.sin(a)) * (r * hole),
          c + Offset(math.cos(a), math.sin(a)) * r,
          Paint()
            ..color = gapColor
            ..strokeWidth = 2,
        );
      }
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) => old.progress != progress || old.values != values || old.hole != hole;
}

/// شريط مكدّس أفقي بأجزاء ملونة ووسيلة إيضاح.
class StackBar extends StatelessWidget {
  const StackBar({super.key, required this.parts, this.height = 14, this.legend = true, this.format});

  final List<(String, double, Color)> parts;
  final double height;
  final bool legend;
  final String Function(double)? format;

  @override
  Widget build(BuildContext context) {
    final sem = Sem.of(context);
    final total = parts.fold<double>(0, (a, p) => a + math.max(0, p.$2));
    final fmt = format ?? compactMoney;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(height),
          child: Container(
            height: height,
            color: sem.todoSoft,
            child: total <= 0
                ? null
                : RevealWidth(
                    child: Row(children: [
                      for (final p in parts)
                        if (p.$2 > 0) Expanded(flex: math.max(1, (p.$2 / total * 1000).round()), child: Container(color: p.$3)),
                    ]),
                  ),
          ),
        ),
        if (legend) ...[
          const SizedBox(height: 8),
          Wrap(spacing: 14, runSpacing: 6, children: [
            for (final p in parts)
              Row(mainAxisSize: MainAxisSize.min, children: [
                Container(width: 10, height: 10, decoration: BoxDecoration(color: p.$3, borderRadius: BorderRadius.circular(3))),
                const SizedBox(width: 6),
                Text('${p.$1}: ', style: TextStyle(fontSize: 12, color: sem.muted)),
                Text(fmt(p.$2), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, fontFeatures: [FontFeature.tabularFigures()])),
                if (total > 0) Text(' (${pctOf(p.$2, total)})', style: TextStyle(fontSize: 11.5, color: sem.muted)),
              ]),
          ]),
        ],
      ],
    );
  }
}

/// وسيلة إيضاح للرسوم.
class ChartLegend extends StatelessWidget {
  const ChartLegend({super.key, required this.items});

  final List<(Color, String)> items;

  @override
  Widget build(BuildContext context) {
    final sem = Sem.of(context);
    return Wrap(
      spacing: 14,
      runSpacing: 4,
      children: [
        for (final it in items)
          Row(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 12, height: 4, decoration: BoxDecoration(color: it.$1, borderRadius: BorderRadius.circular(2))),
            const SizedBox(width: 6),
            Text(it.$2, style: TextStyle(fontSize: 12, color: sem.muted)),
          ]),
      ],
    );
  }
}
