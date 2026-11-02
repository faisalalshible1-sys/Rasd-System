import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models.dart';
import 'theme.dart';

/// نظام الحركة في الواجهة: من شاشة الدخول إلى أعماق المنظومة.
/// يحترم إعداد المدير (ui.motion: كاملة / مخففة / بلا حركة) وإعداد «تقليل الحركة» في جهاز المستخدم.
class Motion {
  /// معامل الحركة: 1 كاملة، 0.6 مخففة (تلاشٍ فقط وأقصر)، 0 بلا حركة.
  static double factor(BuildContext context) {
    if (MediaQuery.maybeDisableAnimationsOf(context) == true) return 0;
    return switch (motionSetting) {
      'off' => 0.0,
      'reduced' => 0.6,
      _ => 1.0,
    };
  }

  static bool enabled(BuildContext context) => factor(context) > 0;

  /// الحركة الكاملة (انزلاق وتكبير)، لا التلاشي وحده.
  static bool full(BuildContext context) => factor(context) >= 1;

  /// مدة مضبوطة حسب مستوى الحركة.
  static Duration of(BuildContext context, int ms) {
    final f = factor(context);
    return f == 0 ? Duration.zero : Duration(milliseconds: (ms * f).round());
  }
}

/// ظهور تدريجي مع انزلاق خفيف عند أول بناء للعنصر.
class FadeSlideIn extends StatefulWidget {
  const FadeSlideIn({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.duration = const Duration(milliseconds: 480),
    this.offset = const Offset(0, 0.06),
    this.scale = 1.0,
  });

  final Widget child;
  final Duration delay;
  final Duration duration;
  final Offset offset;

  /// حجم البداية (1 = بلا تكبير).
  final double scale;

  @override
  State<FadeSlideIn> createState() => _FadeSlideInState();
}

class _FadeSlideInState extends State<FadeSlideIn> with SingleTickerProviderStateMixin {
  AnimationController? _c;
  Animation<double>? _fade;
  Animation<Offset>? _slide;
  Animation<double>? _scale;
  Timer? _timer;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    final f = Motion.factor(context);
    if (f == 0) return;
    final c = AnimationController(vsync: this, duration: Duration(milliseconds: (widget.duration.inMilliseconds * f).round()));
    _c = c;
    _fade = c.drive(CurveTween(curve: Curves.easeOut));
    if (f >= 1) {
      _slide = c.drive(Tween<Offset>(begin: widget.offset, end: Offset.zero).chain(CurveTween(curve: Curves.easeOutCubic)));
      if (widget.scale != 1.0) {
        _scale = c.drive(Tween<double>(begin: widget.scale, end: 1.0).chain(CurveTween(curve: Curves.easeOutBack)));
      }
    }
    final delay = Duration(milliseconds: (widget.delay.inMilliseconds * f).round());
    if (delay == Duration.zero) {
      c.forward();
    } else {
      _timer = Timer(delay, () {
        if (mounted) c.forward();
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _c?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final fade = _fade;
    if (fade == null) return widget.child;
    Widget child = widget.child;
    final scale = _scale;
    if (scale != null) child = ScaleTransition(scale: scale, child: child);
    final slide = _slide;
    if (slide != null) child = SlideTransition(position: slide, child: child);
    return FadeTransition(opacity: fade, child: child);
  }
}

/// يغلّف العناصر بظهور متتابع (الأول فالثاني...)، والتأخير محدود حتى لا يطول الانتظار.
List<Widget> staggered(
  List<Widget> children, {
  int stepMs = 55,
  int startMs = 0,
  int maxSteps = 9,
  Offset offset = const Offset(0, 0.05),
}) =>
    [
      for (var i = 0; i < children.length; i++)
        FadeSlideIn(
          delay: Duration(milliseconds: startMs + math.min(i, maxSteps) * stepMs),
          offset: offset,
          child: children[i],
        ),
    ];

/// تبديل محتوى بانتقال ناعم (تلاشٍ وانزلاق وتكبير خفيف) — للتنقل بين الأقسام.
class MotionSwitcher extends StatelessWidget {
  const MotionSwitcher({
    super.key,
    required this.child,
    this.duration = const Duration(milliseconds: 420),
    this.offset = const Offset(0, 0.018),
    this.expand = true,
  });

  final Widget child;
  final Duration duration;
  final Offset offset;

  /// يملأ المساحة المتاحة (للصفحات داخل Expanded).
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final d = Motion.of(context, duration.inMilliseconds);
    final full = Motion.full(context);
    return AnimatedSwitcher(
      duration: d,
      reverseDuration: d * 0.55,
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      layoutBuilder: (current, previous) => Stack(
        fit: expand ? StackFit.expand : StackFit.loose,
        alignment: Alignment.topCenter,
        children: [...previous, if (current != null) current],
      ),
      transitionBuilder: (child, anim) {
        if (!full) return FadeTransition(opacity: anim, child: child);
        return FadeTransition(
          opacity: anim,
          child: SlideTransition(
            position: anim.drive(Tween<Offset>(begin: offset, end: Offset.zero)),
            child: ScaleTransition(scale: anim.drive(Tween<double>(begin: 0.985, end: 1.0)), child: child),
          ),
        );
      },
      child: child,
    );
  }
}

/// انتقال الصفحات في كل التطبيق: الصفحة الجديدة تصعد وتظهر، والسابقة تنكمش قليلاً وتخفت.
class DcPageTransitionsBuilder extends PageTransitionsBuilder {
  const DcPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final f = Motion.factor(context);
    if (f == 0) return child;
    final fadeIn = animation.drive(CurveTween(curve: Curves.easeOut));
    if (f < 1) return FadeTransition(opacity: fadeIn, child: child);
    final slideIn = animation.drive(Tween<Offset>(begin: const Offset(0, 0.04), end: Offset.zero).chain(CurveTween(curve: Curves.easeOutCubic)));
    final scaleOut = secondaryAnimation.drive(Tween<double>(begin: 1.0, end: 0.965).chain(CurveTween(curve: Curves.easeOutCubic)));
    final fadeOut = secondaryAnimation.drive(Tween<double>(begin: 1.0, end: 0.55).chain(CurveTween(curve: Curves.easeOut)));
    return FadeTransition(
      opacity: fadeOut,
      child: ScaleTransition(
        scale: scaleOut,
        child: FadeTransition(opacity: fadeIn, child: SlideTransition(position: slideIn, child: child)),
      ),
    );
  }
}

/// رقم يعدّ تصاعدياً حتى قيمته.
class AnimatedCount extends StatelessWidget {
  const AnimatedCount({
    super.key,
    required this.value,
    required this.format,
    this.style,
    this.duration = const Duration(milliseconds: 1000),
    this.textAlign,
  });

  final double value;
  final String Function(double v) format;
  final TextStyle? style;
  final Duration duration;
  final TextAlign? textAlign;

  @override
  Widget build(BuildContext context) {
    final d = Motion.of(context, duration.inMilliseconds);
    if (d == Duration.zero) return Text(format(value), style: style, textAlign: textAlign);
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: value),
      duration: d,
      curve: Curves.easeOutCubic,
      builder: (context, v, _) => Text(format(v), style: style, textAlign: textAlign),
    );
  }
}

/// رفع خفيف وظل عند مرور المؤشر (الحاسوب والويب).
class HoverLift extends StatefulWidget {
  const HoverLift({super.key, required this.child, this.lift = 3, this.radius = 18});

  final Widget child;
  final double lift;
  final double radius;

  @override
  State<HoverLift> createState() => _HoverLiftState();
}

class _HoverLiftState extends State<HoverLift> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    if (!Motion.enabled(context)) return widget.child;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedContainer(
        duration: Motion.of(context, 220),
        curve: Curves.easeOutCubic,
        transform: Matrix4.translationValues(0, _hover ? -widget.lift : 0, 0),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(widget.radius),
          boxShadow: _hover
              ? [BoxShadow(color: Colors.black.withAlpha(dark ? 90 : 26), blurRadius: 22, offset: const Offset(0, 10))]
              : const [],
        ),
        child: widget.child,
      ),
    );
  }
}

/// شريط نسبة يمتلئ بحركة.
class AnimatedMeter extends StatelessWidget {
  const AnimatedMeter({super.key, required this.value, this.color, this.background, this.height = 8});

  final double value;
  final Color? color;
  final Color? background;
  final double height;

  @override
  Widget build(BuildContext context) {
    final sem = Sem.of(context);
    final c = color ?? Theme.of(context).colorScheme.primary;
    final bg = background ?? sem.todoSoft;
    final target = value.isNaN ? 0.0 : value.clamp(0.0, 1.0);
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: target),
      duration: Motion.of(context, 900),
      curve: Curves.easeOutCubic,
      builder: (context, v, _) => Container(
        height: height,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(height)),
        child: Align(
          alignment: AlignmentDirectional.centerStart,
          child: FractionallySizedBox(
            widthFactor: v,
            heightFactor: 1,
            child: DecoratedBox(decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(height))),
          ),
        ),
      ),
    );
  }
}

/// يكشف عنصراً أفقياً من بدايته (للأشرطة المقسّمة).
class RevealWidth extends StatelessWidget {
  const RevealWidth({super.key, required this.child, this.duration = 900});

  final Widget child;
  final int duration;

  @override
  Widget build(BuildContext context) {
    final d = Motion.of(context, duration);
    if (d == Duration.zero) return child;
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: d,
      curve: Curves.easeOutCubic,
      child: child,
      // الخارجي يأخذ العرض كاملاً، والداخلي يتسع تدريجياً ويُقص ما بعده
      builder: (context, v, ch) => Align(
        alignment: AlignmentDirectional.centerStart,
        child: ClipRect(
          child: Align(alignment: AlignmentDirectional.centerStart, widthFactor: v, child: ch),
        ),
      ),
    );
  }
}

/// حلقة نسبة إنجاز متحركة، وفي وسطها محتوى اختياري.
class RingProgress extends StatelessWidget {
  const RingProgress({
    super.key,
    required this.value,
    this.size = 88,
    this.stroke = 9,
    this.color,
    this.track,
    this.child,
  });

  final double value;
  final double size;
  final double stroke;
  final Color? color;
  final Color? track;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final sem = Sem.of(context);
    final c = color ?? Theme.of(context).colorScheme.primary;
    final tr = track ?? sem.todoSoft;
    final target = value.isNaN ? 0.0 : value.clamp(0.0, 1.0);
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: target),
      duration: Motion.of(context, 1200),
      curve: Curves.easeOutCubic,
      child: child,
      builder: (context, v, ch) => SizedBox.square(
        dimension: size,
        child: CustomPaint(
          painter: _RingPainter(v, c, tr, stroke),
          child: Center(child: ch),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.value, this.color, this.track, this.stroke);

  final double value;
  final Color color;
  final Color track;
  final double stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final r = rect.deflate(stroke / 2);
    final base = Paint()
      ..color = track
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;
    canvas.drawArc(r, 0, math.pi * 2, false, base);
    if (value <= 0) return;
    final fg = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = stroke;
    canvas.drawArc(r, -math.pi / 2, math.pi * 2 * value, false, fg);
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) =>
      old.value != value || old.color != color || old.track != track || old.stroke != stroke;
}

/// هيكل تحميل لامع بدل مؤشر الدوران.
class Skeleton extends StatefulWidget {
  const Skeleton({super.key, this.height = 14, this.width, this.radius = 8});

  final double height;
  final double? width;
  final double radius;

  @override
  State<Skeleton> createState() => _SkeletonState();
}

class _SkeletonState extends State<Skeleton> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400));
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_started && Motion.enabled(context)) {
      _started = true;
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sem = Sem.of(context);
    final base = sem.todoSoft;
    final hi = sem.surface2;
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) => Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(widget.radius),
          gradient: LinearGradient(
            colors: [base, hi, base],
            stops: const [0.25, 0.5, 0.75],
            transform: _SlideGradient(_c.value),
          ),
        ),
      ),
    );
  }
}

class _SlideGradient extends GradientTransform {
  const _SlideGradient(this.t);

  final double t;

  @override
  Matrix4? transform(Rect bounds, {TextDirection? textDirection}) =>
      Matrix4.translationValues(bounds.width * (t * 2 - 1), 0, 0);
}

/// بطاقات هيكلية أثناء تحميل البيانات أول مرة.
class SkeletonPage extends StatelessWidget {
  const SkeletonPage({super.key, this.cards = 4});

  final int cards;

  @override
  Widget build(BuildContext context) {
    final sem = Sem.of(context);
    return ListView(
      padding: const EdgeInsets.all(18),
      physics: const NeverScrollableScrollPhysics(),
      children: [
        const Skeleton(height: 26, width: 220),
        const SizedBox(height: 10),
        const Skeleton(height: 14, width: 320),
        const SizedBox(height: 22),
        for (var i = 0; i < cards; i++)
          Container(
            margin: const EdgeInsets.only(bottom: 14),
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(color: sem.surface, borderRadius: BorderRadius.circular(18), border: Border.all(color: sem.rule)),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Skeleton(height: 16, width: 160),
                SizedBox(height: 14),
                Skeleton(height: 10),
                SizedBox(height: 10),
                Skeleton(height: 10, width: 260),
              ],
            ),
          ),
      ],
    );
  }
}

/// ختم المؤسسة نابضاً بحلقات تتسع (شاشة التحميل).
class PulseEmblem extends StatefulWidget {
  const PulseEmblem({super.key, this.size = 84, this.ripples = true});

  final double size;
  final bool ripples;

  @override
  State<PulseEmblem> createState() => _PulseEmblemState();
}

class _PulseEmblemState extends State<PulseEmblem> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 2200));
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_started && Motion.enabled(context)) {
      _started = true;
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    final box = widget.size * (widget.ripples ? 2.2 : 1.15);
    return SizedBox.square(
      dimension: box,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, child) {
          final t = _c.value;
          final breath = 1 + 0.035 * math.sin(t * math.pi * 2);
          return Stack(
            alignment: Alignment.center,
            children: [
              if (widget.ripples)
                for (final phase in const [0.0, 0.5])
                  Builder(builder: (context) {
                    final p = (t + phase) % 1.0;
                    return Opacity(
                      opacity: (1 - p) * 0.5,
                      child: Container(
                        width: widget.size * (1 + p * 1.1),
                        height: widget.size * (1 + p * 1.1),
                        decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: color, width: 1.6)),
                      ),
                    );
                  }),
              Transform.scale(scale: breath, child: child),
            ],
          );
        },
        child: BrandEmblem(size: widget.size),
      ),
    );
  }
}

/// خلفية متحركة للوحة الهوية في شاشة الدخول: شبكة هندسية تنساب وأضواء ناعمة وحلقات تدور.
class AnimatedBackdrop extends StatefulWidget {
  const AnimatedBackdrop({super.key, this.child, this.intensity = 1});

  final Widget? child;
  final double intensity;

  @override
  State<AnimatedBackdrop> createState() => _AnimatedBackdropState();
}

class _AnimatedBackdropState extends State<AnimatedBackdrop> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(seconds: 24));
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_started && Motion.full(context)) {
      _started = true;
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CustomPaint(painter: _BackdropPainter(_c, widget.intensity), child: widget.child);
  }
}

class _BackdropPainter extends CustomPainter {
  _BackdropPainter(this.t, this.intensity) : super(repaint: t);

  final Animation<double> t;
  final double intensity;

  int _a(int v) => (v * intensity).round().clamp(0, 255);

  @override
  void paint(Canvas canvas, Size size) {
    final v = t.value * math.pi * 2;

    // أضواء ناعمة تتحرك ببطء
    const blobs = <(double, double, double, double)>[
      (0.15, 0.20, 0.45, 0.0),
      (0.85, 0.28, 0.38, 1.7),
      (0.30, 0.86, 0.50, 3.1),
      (0.92, 0.90, 0.32, 4.4),
    ];
    for (final b in blobs) {
      final center = Offset(
        size.width * (b.$1 + 0.06 * math.sin(v + b.$4)),
        size.height * (b.$2 + 0.05 * math.cos(v * 0.8 + b.$4)),
      );
      final r = size.shortestSide * b.$3;
      final paint = Paint()
        ..shader = RadialGradient(colors: [Colors.white.withAlpha(_a(38)), Colors.white.withAlpha(0)])
            .createShader(Rect.fromCircle(center: center, radius: r));
      canvas.drawCircle(center, r, paint);
    }

    // شبكة المخططات الهندسية تنساب
    final grid = Paint()
      ..color = Colors.white.withAlpha(_a(15))
      ..strokeWidth = 1;
    const step = 44.0;
    final shift = (t.value * step * 6) % step;
    for (var x = -step + shift; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), grid);
    }
    for (var y = -step + shift; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }

    // حلقات تدور (من ختم المؤسسة)
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..color = Colors.white.withAlpha(_a(34))
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 1.4;
    final c = Offset(size.width * 0.80, size.height * 0.18);
    for (var i = 0; i < 3; i++) {
      final rr = size.shortestSide * (0.16 + i * 0.075);
      canvas.drawArc(Rect.fromCircle(center: c, radius: rr), v * (i.isEven ? 1 : -1) + i, math.pi * (1.1 + i * 0.2), false, ring);
    }
    final c2 = Offset(size.width * 0.12, size.height * 0.82);
    for (var i = 0; i < 2; i++) {
      final rr = size.shortestSide * (0.10 + i * 0.06);
      canvas.drawArc(Rect.fromCircle(center: c2, radius: rr), -v * 0.7 + i * 2, math.pi * 0.9, false, ring);
    }
  }

  @override
  bool shouldRepaint(covariant _BackdropPainter old) => old.intensity != intensity || old.t != t;
}

/// ثلاث نقاط تنبض (المساعد يكتب).
class TypingDots extends StatefulWidget {
  const TypingDots({super.key, this.color, this.size = 7});

  final Color? color;
  final double size;

  @override
  State<TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<TypingDots> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.color ?? Sem.of(context).muted;
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < 3; i++)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2.5),
              child: Opacity(
                opacity: 0.3 + 0.7 * (0.5 + 0.5 * math.sin((_c.value - i * 0.18) * math.pi * 2)).clamp(0.0, 1.0),
                child: Container(
                  width: widget.size,
                  height: widget.size,
                  decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
