import 'package:flutter/material.dart';

import '../../app_state.dart';
import '../../models.dart';
import '../../ui/charts.dart';
import '../../ui/theme.dart';
import '../../ui/widgets.dart';
import 'control_panel.dart' show runAction;

/// المظهر والرسوم البيانية (للمدير): درجات الداكن والفاتح، والكثافة والاستدارة وشكل البطاقات وحجم الخط،
/// وشكل الرسوم ولوحتها وتفاصيلها. التغييرات تُعاين مباشرة على المنظومة كلها قبل حفظها للجميع.
class AppearanceEditor extends StatefulWidget {
  const AppearanceEditor({super.key});

  @override
  State<AppearanceEditor> createState() => _AppearanceEditorState();
}

class _AppearanceEditorState extends State<AppearanceEditor> {
  late Appearance _draft;
  late Appearance _saved;
  bool _init = false;
  bool _busy = false;
  AppState? _app;

  bool get _dirty => _draft != _saved;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _app = AppScope.read(context);
    if (_init) return;
    _init = true;
    _saved = Appearance.fromJson(_app!.settings.raw['ui.appearance']);
    _draft = _saved;
  }

  @override
  void dispose() {
    // المعاينة غير المحفوظة لا تبقى بعد مغادرة الصفحة
    final app = _app;
    if (app != null && _dirty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => app.restoreAppearance());
    }
    super.dispose();
  }

  void _set(Appearance a, {bool preview = true}) {
    setState(() => _draft = a);
    if (preview) AppScope.read(context).previewAppearance(a);
  }

  void _setCharts(ChartStyle c) => _set(_draft.copyWith(charts: c));

  Future<void> _save() async {
    setState(() => _busy = true);
    final app = AppScope.read(context);
    final ok = await runAction(context, () => app.setSetting('ui.appearance', _draft.toJson()), success: 'حُفظ المظهر لكل المستخدمين');
    if (ok) app.restoreAppearance();
    if (mounted) {
      setState(() {
        _busy = false;
        _saved = Appearance.fromJson(app.settings.raw['ui.appearance']);
      });
    }
  }

  void _revert() {
    setState(() => _draft = _saved);
    AppScope.read(context).restoreAppearance();
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final sem = Sem.of(context);
    final cs = Theme.of(context).colorScheme;
    final c = _draft.charts;
    return SectionCard(
      title: 'المظهر والرسوم البيانية',
      icon: Icons.palette_outlined,
      subtitle: 'الألوان والدرجات وشكل الواجهة وطريقة عرض الرسوم والمنحنيات. تُعاين فوراً على المنظومة كلها، وتسري على الجميع بعد الحفظ.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ---- الوضع ----
          _label(context, 'الوضع على هذا الجهاز'),
          SegmentedButton<ThemeMode>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: ThemeMode.system, label: Text('حسب الجهاز'), icon: Icon(Icons.brightness_auto_outlined)),
              ButtonSegment(value: ThemeMode.light, label: Text('فاتح'), icon: Icon(Icons.light_mode_outlined)),
              ButtonSegment(value: ThemeMode.dark, label: Text('داكن'), icon: Icon(Icons.dark_mode_outlined)),
            ],
            selected: {app.themeMode},
            onSelectionChanged: (v) => app.setThemeMode(v.first),
          ),
          const SizedBox(height: 16),
          _label(context, 'درجة الوضع الداكن'),
          Wrap(spacing: 10, runSpacing: 10, children: [
            for (final e in darkTones.entries)
              _ToneSwatch(tone: e.value, selected: _draft.darkTone == e.key, onTap: () => _set(_draft.copyWith(darkTone: e.key))),
          ]),
          const SizedBox(height: 14),
          _label(context, 'درجة الوضع الفاتح (تدرّج رصاصي بين الخلفية والبطاقات)'),
          Wrap(spacing: 10, runSpacing: 10, children: [
            for (final e in lightTones.entries)
              _ToneSwatch(tone: e.value, selected: _draft.lightTone == e.key, onTap: () => _set(_draft.copyWith(lightTone: e.key))),
          ]),
          Divider(height: 32, color: sem.rule),

          // ---- الشكل ----
          _label(context, 'كثافة العرض'),
          SegmentedButton<String>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: 'compact', label: Text('مضغوطة')),
              ButtonSegment(value: 'comfortable', label: Text('مريحة')),
              ButtonSegment(value: 'spacious', label: Text('واسعة')),
            ],
            selected: {_draft.density},
            onSelectionChanged: (v) => _set(_draft.copyWith(density: v.first)),
          ),
          const SizedBox(height: 14),
          _label(context, 'شكل البطاقات'),
          SegmentedButton<String>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: 'outlined', label: Text('بحدود'), icon: Icon(Icons.crop_square_rounded)),
              ButtonSegment(value: 'elevated', label: Text('مرتفعة'), icon: Icon(Icons.layers_outlined)),
              ButtonSegment(value: 'filled', label: Text('مملوءة'), icon: Icon(Icons.square_rounded)),
            ],
            selected: {_draft.cardStyle},
            onSelectionChanged: (v) => _set(_draft.copyWith(cardStyle: v.first)),
          ),
          const SizedBox(height: 10),
          _slider(context, 'استدارة الحواف', _draft.radius, 6, 26, 20, (v) => '${v.round()}',
              (v) => _set(_draft.copyWith(radius: v.roundToDouble()), preview: false), (v) => _set(_draft.copyWith(radius: v.roundToDouble()))),
          _slider(context, 'حجم الخط', _draft.fontScale, 0.9, 1.2, 6, (v) => '${(v * 100).round()}%',
              (v) => _set(_draft.copyWith(fontScale: (v * 100).round() / 100), preview: false),
              (v) => _set(_draft.copyWith(fontScale: (v * 100).round() / 100))),
          Divider(height: 32, color: sem.rule),

          // ---- الرسوم ----
          _label(context, 'المنحنيات الزمنية'),
          SegmentedButton<String>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: 'area', label: Text('مساحة'), icon: Icon(Icons.area_chart_outlined)),
              ButtonSegment(value: 'line', label: Text('خط'), icon: Icon(Icons.show_chart_rounded)),
              ButtonSegment(value: 'bar', label: Text('أعمدة'), icon: Icon(Icons.bar_chart_rounded)),
            ],
            selected: {c.trend},
            onSelectionChanged: (v) => _setCharts(c.copyWith(trend: v.first)),
          ),
          const SizedBox(height: 12),
          _label(context, 'التوزيعات'),
          SegmentedButton<String>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: 'donut', label: Text('حلقة'), icon: Icon(Icons.donut_large_rounded)),
              ButtonSegment(value: 'pie', label: Text('دائرة'), icon: Icon(Icons.pie_chart_outline_rounded)),
              ButtonSegment(value: 'bar', label: Text('أشرطة'), icon: Icon(Icons.align_horizontal_left_rounded)),
            ],
            selected: {c.breakdown},
            onSelectionChanged: (v) => _setCharts(c.copyWith(breakdown: v.first)),
          ),
          const SizedBox(height: 12),
          _label(context, 'لوحة الألوان'),
          Wrap(spacing: 10, runSpacing: 10, children: [
            for (final e in chartPalettes.entries)
              InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => _setCharts(c.copyWith(palette: e.key)),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: sem.surface2,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: c.palette == e.key ? cs.primary : sem.rule, width: c.palette == e.key ? 2 : 1),
                  ),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Row(mainAxisSize: MainAxisSize.min, children: [
                      for (final col in (e.key == 'brand' ? [cs.primary, ...e.value.skip(1)] : e.value).take(5))
                        Container(width: 14, height: 14, margin: const EdgeInsets.symmetric(horizontal: 1.5), decoration: BoxDecoration(color: col, shape: BoxShape.circle)),
                    ]),
                    const SizedBox(height: 4),
                    Text(chartPaletteLabels[e.key] ?? e.key, style: const TextStyle(fontSize: 12)),
                  ]),
                ),
              ),
          ]),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 4, children: [
            _toggle('منحنيات ناعمة', c.curved, (v) => _setCharts(c.copyWith(curved: v))),
            _toggle('نقاط القيم', c.points, (v) => _setCharts(c.copyWith(points: v))),
            _toggle('القيم على الرسم', c.values, (v) => _setCharts(c.copyWith(values: v))),
            _toggle('خطوط الشبكة', c.grid, (v) => _setCharts(c.copyWith(grid: v))),
            _toggle('وسيلة الإيضاح', c.legend, (v) => _setCharts(c.copyWith(legend: v))),
            _toggle('تحريك الرسوم', c.animate, (v) => _setCharts(c.copyWith(animate: v))),
          ]),
          _slider(context, 'سماكة الخطوط', c.stroke, 1, 5, 8, (v) => v.toStringAsFixed(1),
              (v) => setState(() => _draft = _draft.copyWith(charts: c.copyWith(stroke: v))), (v) => _setCharts(c.copyWith(stroke: v))),
          const SizedBox(height: 12),
          _label(context, 'معاينة'),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: cardDecoration(context, color: sem.surface2),
            child: LayoutBuilder(builder: (context, box) {
              final trend = TrendChart(
                style: c,
                height: 180,
                labels: const ['يول', 'أغس', 'سبت', 'أكت', 'نوف', 'ديس'],
                series: const [
                  ChartSeries('قيمة الأعمال', [120000, 180000, 150000, 240000, 210000, 290000]),
                  ChartSeries('المدفوع', [80000, 120000, 140000, 160000, 200000, 230000]),
                ],
              );
              final breakdown = BreakdownChart(
                style: c,
                size: 150,
                centerTitle: 'الإجمالي',
                centerValue: '1.2 م',
                items: const [('مدفوع', 520000), ('مستحق', 180000), ('محتجز', 90000), ('لم يُنفَّذ', 410000)],
              );
              if (box.maxWidth < 760) return Column(children: [trend, const SizedBox(height: 16), breakdown]);
              return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(flex: 3, child: trend),
                const SizedBox(width: 18),
                Expanded(flex: 2, child: breakdown),
              ]);
            }),
          ),
          const SizedBox(height: 14),
          Wrap(alignment: WrapAlignment.end, spacing: 8, runSpacing: 8, children: [
            TextButton.icon(
              onPressed: _busy ? null : () => _set(Appearance.defaults),
              icon: const Icon(Icons.restart_alt_rounded, size: 18),
              label: const Text('الافتراضي'),
            ),
            if (_dirty)
              OutlinedButton(onPressed: _busy ? null : _revert, child: const Text('تراجع عن المعاينة')),
            FilledButton.icon(
              onPressed: _busy || !_dirty ? null : _save,
              icon: _busy ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.check_rounded, size: 18),
              label: const Text('حفظ للجميع'),
            ),
          ]),
          if (_dirty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('تعرض المنظومة الآن معاينة لم تُحفظ. تعود إلى المحفوظ عند مغادرة الصفحة دون حفظ.',
                  textAlign: TextAlign.end, style: TextStyle(color: sem.muted, fontSize: 12)),
            ),
        ],
      ),
    );
  }

  Widget _label(BuildContext context, String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(text, style: TextStyle(fontWeight: FontWeight.w700, color: Sem.of(context).muted, fontSize: 12.5)),
      );

  Widget _toggle(String label, bool value, ValueChanged<bool> onChanged) => FilterChip(
        label: Text(label),
        selected: value,
        onSelected: onChanged,
      );

  Widget _slider(BuildContext context, String label, double value, double min, double max, int divisions, String Function(double) text,
          ValueChanged<double> onChanged, ValueChanged<double> onEnd) =>
      Row(children: [
        SizedBox(width: 110, child: Text(label, style: const TextStyle(fontSize: 13))),
        Expanded(
          child: Slider(
            value: value.clamp(min, max).toDouble(),
            min: min,
            max: max,
            divisions: divisions,
            label: text(value),
            onChanged: onChanged,
            onChangeEnd: onEnd,
          ),
        ),
        SizedBox(width: 48, child: Text(text(value), textAlign: TextAlign.end, style: const TextStyle(fontFeatures: [FontFeature.tabularFigures()]))),
      ]);
}

/// عيّنة درجة: الخلفية والشريط والبطاقة والنص.
class _ToneSwatch extends StatelessWidget {
  const _ToneSwatch({required this.tone, required this.selected, required this.onTap});

  final Tone tone;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 132,
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: tone.background,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: selected ? cs.primary : tone.rule, width: selected ? 2.5 : 1),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(height: 10, decoration: BoxDecoration(color: tone.bar, borderRadius: BorderRadius.circular(4))),
          const SizedBox(height: 5),
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(color: tone.surface, borderRadius: BorderRadius.circular(8), border: Border.all(color: tone.rule)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(height: 6, width: 54, decoration: BoxDecoration(color: tone.text, borderRadius: BorderRadius.circular(3))),
              const SizedBox(height: 4),
              Container(height: 5, width: 80, decoration: BoxDecoration(color: tone.muted, borderRadius: BorderRadius.circular(3))),
              const SizedBox(height: 5),
              Container(height: 12, decoration: BoxDecoration(color: tone.surface2, borderRadius: BorderRadius.circular(4))),
            ]),
          ),
          const SizedBox(height: 5),
          Row(children: [
            if (selected) Icon(Icons.check_circle_rounded, size: 14, color: cs.primary),
            if (selected) const SizedBox(width: 4),
            Expanded(child: Text(tone.label, style: TextStyle(fontSize: 11.5, color: tone.text, fontWeight: FontWeight.w600))),
          ]),
        ]),
      ),
    );
  }
}
