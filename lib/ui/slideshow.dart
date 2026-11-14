import 'dart:async';

import 'package:flutter/material.dart';

import '../app_state.dart';
import '../docs.dart';
import 'motion.dart';
import 'theme.dart';

/// شريحة في العرض المتحرك: ملف صورة وعنوانه وشارته (مثل «الإصدار 2»).
class Slide {
  const Slide({required this.file, this.caption = '', this.badge = '', this.date = ''});

  final DocFile file;
  final String caption;
  final String badge;
  final String date;
}

/// لاختبارات الشاشات: مصدر صور بديل عن الشبكة.
ImageProvider Function(DocFile file)? debugSlideImage;

/// صورة ملف من الحاوية الخاصة عبر رابط موقّع مؤقت.
class DocImage extends StatefulWidget {
  const DocImage({super.key, required this.file, this.fit = BoxFit.cover});

  final DocFile file;
  final BoxFit fit;

  @override
  State<DocImage> createState() => _DocImageState();
}

class _DocImageState extends State<DocImage> {
  Future<String>? _url;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (debugSlideImage == null) _url ??= AppScope.read(context).signedUrls.of(widget.file.path);
  }

  @override
  void didUpdateWidget(DocImage old) {
    super.didUpdateWidget(old);
    if (old.file.path != widget.file.path && debugSlideImage == null) {
      _url = AppScope.read(context).signedUrls.of(widget.file.path);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sem = Sem.of(context);
    Widget placeholder(IconData icon) => Container(
          color: sem.surface2,
          alignment: Alignment.center,
          child: Icon(icon, color: sem.muted, size: 32),
        );
    final override = debugSlideImage;
    if (override != null) return Image(image: override(widget.file), fit: widget.fit, gaplessPlayback: true);
    return FutureBuilder<String>(
      future: _url,
      builder: (context, snap) {
        if (snap.hasError) return placeholder(Icons.broken_image_outlined);
        final url = snap.data;
        if (url == null) return placeholder(Icons.image_outlined);
        return Image.network(
          url,
          fit: widget.fit,
          gaplessPlayback: true,
          loadingBuilder: (context, child, p) => p == null ? child : Stack(fit: StackFit.expand, children: [
            placeholder(Icons.image_outlined),
            const Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))),
          ]),
          errorBuilder: (_, __, ___) => placeholder(Icons.broken_image_outlined),
        );
      },
    );
  }
}

/// عرض متحرك للصور: يتنقل تلقائياً كل [interval]، ويتوقف عند التأشير بالماوس أو الضغط المطوّل،
/// ويُفتح بالنقر في عارض بملء الشاشة مع التكبير.
class AutoSlideshow extends StatefulWidget {
  const AutoSlideshow({
    super.key,
    required this.slides,
    this.interval = const Duration(seconds: 4),
    this.aspectRatio = 16 / 10,
    this.radius = 14,
    this.fit = BoxFit.cover,
    this.showControls = true,
    this.onOpen,
  });

  final List<Slide> slides;
  final Duration interval;
  final double aspectRatio;
  final double radius;
  final BoxFit fit;
  final bool showControls;

  /// عند النقر: يُفتح العارض بملء الشاشة على الشريحة الحالية (افتراضياً).
  final void Function(int index)? onOpen;

  @override
  State<AutoSlideshow> createState() => _AutoSlideshowState();
}

class _AutoSlideshowState extends State<AutoSlideshow> {
  int _index = 0;
  bool _hover = false;
  bool _held = false;
  Timer? _timer;

  bool get _paused => _hover || _held;

  @override
  void initState() {
    super.initState();
    _restart();
  }

  @override
  void didUpdateWidget(AutoSlideshow old) {
    super.didUpdateWidget(old);
    if (_index >= widget.slides.length) _index = 0;
    if (old.slides.length != widget.slides.length || old.interval != widget.interval) _restart();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _restart() {
    _timer?.cancel();
    if (widget.slides.length < 2) return;
    _timer = Timer.periodic(widget.interval, (_) {
      if (!mounted || _paused) return;
      // «تعطيل الحركة» في إعدادات الجهاز يوقف التنقل التلقائي (يبقى التنقل اليدوي)
      if (MediaQuery.maybeDisableAnimationsOf(context) == true) return;
      setState(() => _index = (_index + 1) % widget.slides.length);
    });
  }

  void _go(int delta) {
    final n = widget.slides.length;
    if (n == 0) return;
    setState(() => _index = (_index + delta + n) % n);
    _restart();
  }

  @override
  Widget build(BuildContext context) {
    final sem = Sem.of(context);
    final slides = widget.slides;
    if (slides.isEmpty) {
      return AspectRatio(
        aspectRatio: widget.aspectRatio,
        child: Container(
          decoration: BoxDecoration(color: sem.surface2, borderRadius: BorderRadius.circular(widget.radius)),
          alignment: Alignment.center,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.image_not_supported_outlined, color: sem.muted, size: 34),
            const SizedBox(height: 6),
            Text('لا صور بعد', style: TextStyle(color: sem.muted)),
          ]),
        ),
      );
    }
    final s = slides[_index.clamp(0, slides.length - 1)];
    final d = Motion.of(context, 650);
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: () {
          final open = widget.onOpen;
          if (open != null) {
            open(_index);
          } else {
            showSlideViewer(context, slides, _index);
          }
        },
        onLongPressStart: (_) => setState(() => _held = true),
        onLongPressEnd: (_) => setState(() => _held = false),
        child: AspectRatio(
          aspectRatio: widget.aspectRatio,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(widget.radius),
            child: Stack(fit: StackFit.expand, children: [
              Container(color: sem.surface2),
              AnimatedSwitcher(
                duration: d,
                switchInCurve: Curves.easeOutCubic,
                transitionBuilder: (child, a) => FadeTransition(
                  opacity: a,
                  child: Motion.full(context) ? ScaleTransition(scale: Tween(begin: 1.04, end: 1.0).animate(a), child: child) : child,
                ),
                child: KeyedSubtree(key: ValueKey(s.file.path), child: DocImage(file: s.file, fit: widget.fit)),
              ),
              // شريط المعلومات السفلي
              if (s.caption.isNotEmpty || s.badge.isNotEmpty)
                Align(
                  alignment: Alignment.bottomCenter,
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(12, 22, 12, 10),
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Color(0x00000000), Color(0xB0000000)],
                      ),
                    ),
                    child: Row(children: [
                      if (s.badge.isNotEmpty)
                        Container(
                          margin: const EdgeInsetsDirectional.only(end: 8),
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.9), borderRadius: BorderRadius.circular(99)),
                          child: Text(s.badge, style: const TextStyle(color: Colors.black87, fontWeight: FontWeight.w800, fontSize: 11.5)),
                        ),
                      Expanded(
                        child: Text(s.caption,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 12.5)),
                      ),
                      if (s.date.isNotEmpty) Text(s.date, style: const TextStyle(color: Colors.white70, fontSize: 11.5)),
                    ]),
                  ),
                ),
              // مؤشر الإيقاف عند التأشير
              if (slides.length > 1)
                PositionedDirectional(
                  top: 8,
                  start: 8,
                  child: AnimatedOpacity(
                    opacity: _paused ? 1 : 0,
                    duration: Motion.of(context, 180),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.55), borderRadius: BorderRadius.circular(99)),
                      child: const Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.pause_rounded, color: Colors.white, size: 14),
                        SizedBox(width: 3),
                        Text('متوقف', style: TextStyle(color: Colors.white, fontSize: 11)),
                      ]),
                    ),
                  ),
                ),
              // أزرار السابق والتالي تظهر عند التأشير
              if (widget.showControls && slides.length > 1) ...[
                _arrow(context, Alignment.centerRight, Icons.chevron_right_rounded, () => _go(-1)),
                _arrow(context, Alignment.centerLeft, Icons.chevron_left_rounded, () => _go(1)),
              ],
              // نقاط الموضع
              if (slides.length > 1)
                PositionedDirectional(
                  top: 10,
                  end: 10,
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    for (var i = 0; i < slides.length && i < 12; i++)
                      AnimatedContainer(
                        duration: Motion.of(context, 220),
                        margin: const EdgeInsets.symmetric(horizontal: 2),
                        width: i == _index ? 14 : 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: i == _index ? 0.95 : 0.55),
                          borderRadius: BorderRadius.circular(99),
                        ),
                      ),
                  ]),
                ),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _arrow(BuildContext context, Alignment a, IconData icon, VoidCallback onTap) => Align(
        alignment: a,
        child: AnimatedOpacity(
          opacity: _hover ? 1 : 0,
          duration: Motion.of(context, 160),
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: Material(
              color: Colors.black.withValues(alpha: 0.45),
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: _hover ? onTap : null,
                child: Padding(padding: const EdgeInsets.all(4), child: Icon(icon, color: Colors.white)),
              ),
            ),
          ),
        ),
      );
}

/// عارض بملء الشاشة: تنقّل بين الصور وتكبير بالسحب أو العجلة.
Future<void> showSlideViewer(BuildContext context, List<Slide> slides, int initial, {List<Widget> Function(Slide s)? actions}) {
  return showDialog<void>(
    context: context,
    useSafeArea: false,
    builder: (ctx) => Dialog.fullscreen(
      backgroundColor: Colors.black,
      child: _SlideViewer(slides: slides, initial: initial, actions: actions),
    ),
  );
}

class _SlideViewer extends StatefulWidget {
  const _SlideViewer({required this.slides, required this.initial, this.actions});

  final List<Slide> slides;
  final int initial;
  final List<Widget> Function(Slide s)? actions;

  @override
  State<_SlideViewer> createState() => _SlideViewerState();
}

class _SlideViewerState extends State<_SlideViewer> {
  late final PageController _pc = PageController(initialPage: widget.initial);
  late int _i = widget.initial;

  @override
  void dispose() {
    _pc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.slides[_i];
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(s.caption.isEmpty ? s.file.name : s.caption, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
          Text([if (s.badge.isNotEmpty) s.badge, if (s.date.isNotEmpty) s.date, '${_i + 1} من ${widget.slides.length}'].join(' · '),
              style: const TextStyle(fontSize: 12, color: Colors.white70)),
        ]),
        actions: widget.actions?.call(s) ?? const [],
      ),
      body: Stack(children: [
        PageView.builder(
          controller: _pc,
          itemCount: widget.slides.length,
          onPageChanged: (i) => setState(() => _i = i),
          itemBuilder: (_, i) => InteractiveViewer(
            minScale: 1,
            maxScale: 6,
            child: Center(child: DocImage(file: widget.slides[i].file, fit: BoxFit.contain)),
          ),
        ),
        if (widget.slides.length > 1) ...[
          Align(
            alignment: Alignment.centerRight,
            child: IconButton(
              color: Colors.white,
              iconSize: 36,
              onPressed: _i > 0 ? () => _pc.previousPage(duration: const Duration(milliseconds: 280), curve: Curves.easeOut) : null,
              icon: const Icon(Icons.chevron_right_rounded),
            ),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: IconButton(
              color: Colors.white,
              iconSize: 36,
              onPressed: _i < widget.slides.length - 1
                  ? () => _pc.nextPage(duration: const Duration(milliseconds: 280), curve: Curves.easeOut)
                  : null,
              icon: const Icon(Icons.chevron_left_rounded),
            ),
          ),
        ],
      ]),
    );
  }
}
