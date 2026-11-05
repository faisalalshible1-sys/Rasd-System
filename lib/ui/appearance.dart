import 'package:flutter/material.dart';

/// المظهر كما يحدده مدير المكتب من «التخصيص والتطوير» (الإعداد ui.appearance):
/// درجات الوضع الداكن والفاتح، والكثافة، والاستدارة، وشكل البطاقات، وحجم الخط، وشكل الرسوم البيانية.
class Appearance {
  const Appearance({
    this.darkTone = 'slate',
    this.lightTone = 'gray',
    this.density = 'comfortable',
    this.radius = 16,
    this.cardStyle = 'outlined',
    this.fontScale = 1.0,
    this.charts = const ChartStyle(),
  });

  final String darkTone; // slate | graphite | navy | warm | oled
  final String lightTone; // gray | silver | cool | warm
  final String density; // compact | comfortable | spacious
  final double radius; // 6..26
  final String cardStyle; // outlined | elevated | filled
  final double fontScale; // 0.9..1.2
  final ChartStyle charts;

  static const defaults = Appearance();

  factory Appearance.fromJson(Object? v) {
    if (v is! Map) return defaults;
    String pick(String key, List<String> allowed, String fallback) {
      final x = v[key];
      return x is String && allowed.contains(x) ? x : fallback;
    }

    double numIn(String key, double lo, double hi, double fallback) {
      final x = v[key];
      return x is num ? x.toDouble().clamp(lo, hi) : fallback;
    }

    return Appearance(
      darkTone: pick('dark_tone', darkTones.keys.toList(), 'slate'),
      lightTone: pick('light_tone', lightTones.keys.toList(), 'gray'),
      density: pick('density', const ['compact', 'comfortable', 'spacious'], 'comfortable'),
      radius: numIn('radius', 6, 26, 16),
      cardStyle: pick('card_style', const ['outlined', 'elevated', 'filled'], 'outlined'),
      fontScale: numIn('font_scale', 0.9, 1.2, 1.0),
      charts: ChartStyle.fromJson(v['charts']),
    );
  }

  Map<String, dynamic> toJson() => {
        'dark_tone': darkTone,
        'light_tone': lightTone,
        'density': density,
        'radius': radius,
        'card_style': cardStyle,
        'font_scale': fontScale,
        'charts': charts.toJson(),
      };

  Appearance copyWith({
    String? darkTone,
    String? lightTone,
    String? density,
    double? radius,
    String? cardStyle,
    double? fontScale,
    ChartStyle? charts,
  }) =>
      Appearance(
        darkTone: darkTone ?? this.darkTone,
        lightTone: lightTone ?? this.lightTone,
        density: density ?? this.density,
        radius: radius ?? this.radius,
        cardStyle: cardStyle ?? this.cardStyle,
        fontScale: fontScale ?? this.fontScale,
        charts: charts ?? this.charts,
      );

  /// المسافات الداخلية حسب الكثافة.
  double get gap => switch (density) { 'compact' => 10, 'spacious' => 20, _ => 14 };
  double get pad => switch (density) { 'compact' => 12, 'spacious' => 22, _ => 16 };
  VisualDensity get visualDensity => switch (density) {
        'compact' => VisualDensity.compact,
        'spacious' => const VisualDensity(horizontal: 1, vertical: 1),
        _ => VisualDensity.standard,
      };

  Tone tone(Brightness b) => b == Brightness.dark ? (darkTones[darkTone] ?? darkTones['slate']!) : (lightTones[lightTone] ?? lightTones['gray']!);

  @override
  bool operator ==(Object other) => other is Appearance && other.toJson().toString() == toJson().toString();

  @override
  int get hashCode => toJson().toString().hashCode;
}

/// شكل الرسوم البيانية.
class ChartStyle {
  const ChartStyle({
    this.trend = 'area',
    this.breakdown = 'donut',
    this.palette = 'brand',
    this.curved = true,
    this.points = true,
    this.values = false,
    this.grid = true,
    this.legend = true,
    this.animate = true,
    this.stroke = 2.4,
  });

  final String trend; // line | area | bar
  final String breakdown; // donut | pie | bar
  final String palette; // brand | ocean | earth | vivid | mono
  final bool curved;
  final bool points;
  final bool values; // إظهار القيم على الرسم
  final bool grid;
  final bool legend;
  final bool animate;
  final double stroke; // 1..5

  factory ChartStyle.fromJson(Object? v) {
    if (v is! Map) return const ChartStyle();
    String pick(String key, List<String> allowed, String fallback) {
      final x = v[key];
      return x is String && allowed.contains(x) ? x : fallback;
    }

    bool flag(String key, bool fallback) => v[key] is bool ? v[key] as bool : fallback;
    final s = v['stroke'];
    return ChartStyle(
      trend: pick('trend', const ['line', 'area', 'bar'], 'area'),
      breakdown: pick('breakdown', const ['donut', 'pie', 'bar'], 'donut'),
      palette: pick('palette', chartPalettes.keys.toList(), 'brand'),
      curved: flag('curved', true),
      points: flag('points', true),
      values: flag('values', false),
      grid: flag('grid', true),
      legend: flag('legend', true),
      animate: flag('animate', true),
      stroke: s is num ? s.toDouble().clamp(1, 5) : 2.4,
    );
  }

  Map<String, dynamic> toJson() => {
        'trend': trend,
        'breakdown': breakdown,
        'palette': palette,
        'curved': curved,
        'points': points,
        'values': values,
        'grid': grid,
        'legend': legend,
        'animate': animate,
        'stroke': stroke,
      };

  ChartStyle copyWith({
    String? trend,
    String? breakdown,
    String? palette,
    bool? curved,
    bool? points,
    bool? values,
    bool? grid,
    bool? legend,
    bool? animate,
    double? stroke,
  }) =>
      ChartStyle(
        trend: trend ?? this.trend,
        breakdown: breakdown ?? this.breakdown,
        palette: palette ?? this.palette,
        curved: curved ?? this.curved,
        points: points ?? this.points,
        values: values ?? this.values,
        grid: grid ?? this.grid,
        legend: legend ?? this.legend,
        animate: animate ?? this.animate,
        stroke: stroke ?? this.stroke,
      );

  /// ألوان السلاسل بالترتيب (اللون الأول للهوية إن اختيرت لوحة الهوية).
  List<Color> colors(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final p = chartPalettes[palette] ?? chartPalettes['brand']!;
    final base = palette == 'brand' ? [Theme.of(context).colorScheme.primary, ...p.skip(1)] : p;
    if (!dark) return base;
    // في الداكن: ألوان أفتح قليلاً وأقل تشبعاً حتى لا تُتعب العين
    return [
      for (final c in base)
        HSLColor.fromColor(c)
            .withLightness((HSLColor.fromColor(c).lightness + 0.12).clamp(0.45, 0.74))
            .withSaturation((HSLColor.fromColor(c).saturation * 0.82).clamp(0.0, 1.0))
            .toColor(),
    ];
  }
}

/// لوحات ألوان الرسوم.
const Map<String, List<Color>> chartPalettes = {
  'brand': [Color(0xFF8A6A1E), Color(0xFF2F6B8F), Color(0xFF27894D), Color(0xFFC2570C), Color(0xFF7A4E9C), Color(0xFFB4232F)],
  'ocean': [Color(0xFF1F5F8B), Color(0xFF2A9D8F), Color(0xFF5DA9E9), Color(0xFF264653), Color(0xFF8AB17D), Color(0xFFE9C46A)],
  'earth': [Color(0xFF8C5A2B), Color(0xFF6B7F3A), Color(0xFFB08944), Color(0xFF5E4B3C), Color(0xFFA0522D), Color(0xFF7D8471)],
  'vivid': [Color(0xFF3A5BD9), Color(0xFFE5484D), Color(0xFF12A594), Color(0xFFF76B15), Color(0xFF8E4EC6), Color(0xFFD6409F)],
  'mono': [Color(0xFF3D4651), Color(0xFF66707C), Color(0xFF8E97A2), Color(0xFFB4BBC4), Color(0xFF515B66), Color(0xFF7A848F)],
};

const Map<String, String> chartPaletteLabels = {
  'brand': 'الهوية',
  'ocean': 'محيطي',
  'earth': 'ترابي',
  'vivid': 'زاهٍ',
  'mono': 'رمادي',
};

/// درجات الخلفيات والأسطح لكل وضع.
class Tone {
  const Tone({
    required this.label,
    required this.background,
    required this.bar,
    required this.surface,
    required this.surface2,
    required this.surface3,
    required this.rule,
    required this.muted,
    required this.text,
    required this.input,
    required this.overlay,
  });

  final String label;
  final Color background; // خلفية الصفحات
  final Color bar; // الشريط العلوي والقائمة
  final Color surface; // البطاقات
  final Color surface2; // الأسطح الثانوية داخل البطاقات
  final Color surface3; // الأسطح المرتفعة (القوائم المنبثقة)
  final Color rule; // الحدود والفواصل
  final Color muted; // النص الثانوي
  final Color text; // النص الأساسي
  final Color input; // تعبئة الحقول
  final Color overlay; // الرسائل المنبثقة والتلميحات
}

/// الوضع الداكن: درجات رمادية مزرقة أو دافئة بدل الأسود الحاد، وتباين مريح للنص.
const Map<String, Tone> darkTones = {
  'slate': Tone(
    label: 'أردوازي هادئ',
    background: Color(0xFF181C21),
    bar: Color(0xFF1D2228),
    surface: Color(0xFF20252C),
    surface2: Color(0xFF272D35),
    surface3: Color(0xFF2E353E),
    rule: Color(0xFF353D47),
    muted: Color(0xFF9AA4B1),
    text: Color(0xFFDCE1E7),
    input: Color(0xFF242A31),
    overlay: Color(0xFF353D48),
  ),
  'graphite': Tone(
    label: 'غرافيت',
    background: Color(0xFF1A1A1C),
    bar: Color(0xFF1F1F22),
    surface: Color(0xFF232326),
    surface2: Color(0xFF2A2A2E),
    surface3: Color(0xFF313136),
    rule: Color(0xFF3A3A3F),
    muted: Color(0xFFA1A1A8),
    text: Color(0xFFE3E3E6),
    input: Color(0xFF26262A),
    overlay: Color(0xFF3A3A40),
  ),
  'navy': Tone(
    label: 'كحلي',
    background: Color(0xFF131A27),
    bar: Color(0xFF18202F),
    surface: Color(0xFF1B2333),
    surface2: Color(0xFF222B3D),
    surface3: Color(0xFF293348),
    rule: Color(0xFF2F3A51),
    muted: Color(0xFF97A2BA),
    text: Color(0xFFDCE2EE),
    input: Color(0xFF1F2738),
    overlay: Color(0xFF2F3A52),
  ),
  'warm': Tone(
    label: 'دافئ',
    background: Color(0xFF1C1A17),
    bar: Color(0xFF211F1B),
    surface: Color(0xFF25221E),
    surface2: Color(0xFF2C2924),
    surface3: Color(0xFF34302A),
    rule: Color(0xFF3C3730),
    muted: Color(0xFFA9A296),
    text: Color(0xFFE7E2D9),
    input: Color(0xFF292621),
    overlay: Color(0xFF3B362F),
  ),
  'oled': Tone(
    label: 'أسود عميق',
    background: Color(0xFF0B0B0C),
    bar: Color(0xFF111113),
    surface: Color(0xFF151517),
    surface2: Color(0xFF1B1B1E),
    surface3: Color(0xFF222225),
    rule: Color(0xFF2A2A2E),
    muted: Color(0xFF9C9CA3),
    text: Color(0xFFE6E6E9),
    input: Color(0xFF18181B),
    overlay: Color(0xFF2C2C30),
  ),
};

/// الوضع الفاتح: تدرّج رصاصي بين الخلفية والشريط والبطاقات والحقول.
const Map<String, Tone> lightTones = {
  // رصاصي متدرّج بوضوح: الخلفية أغمق، ثم الشريط، ثم البطاقات، والنوافذ أفتحها، دون أبيض صرف.
  'gray': Tone(
    label: 'رصاصي متدرّج',
    background: Color(0xFFD5D9DE),
    bar: Color(0xFFE1E4E8),
    surface: Color(0xFFECEEF1),
    surface2: Color(0xFFE0E3E7),
    surface3: Color(0xFFF4F5F7),
    rule: Color(0xFFC3C8CF),
    muted: Color(0xFF4E5660),
    text: Color(0xFF1B1F24),
    input: Color(0xFFE4E7EB),
    overlay: Color(0xFF2B3036),
  ),
  'silver': Tone(
    label: 'فضي',
    background: Color(0xFFDDE0E4),
    bar: Color(0xFFEDEFF1),
    surface: Color(0xFFFFFFFF),
    surface2: Color(0xFFF0F2F4),
    surface3: Color(0xFFFFFFFF),
    rule: Color(0xFFC9CED4),
    muted: Color(0xFF555D68),
    text: Color(0xFF1C2026),
    input: Color(0xFFF2F3F5),
    overlay: Color(0xFF262A30),
  ),
  'cool': Tone(
    label: 'رمادي بارد',
    background: Color(0xFFE5EAF0),
    bar: Color(0xFFF0F3F7),
    surface: Color(0xFFF8FAFC),
    surface2: Color(0xFFECF0F5),
    surface3: Color(0xFFFFFFFF),
    rule: Color(0xFFCED7E1),
    muted: Color(0xFF566476),
    text: Color(0xFF1B2430),
    input: Color(0xFFEDF1F6),
    overlay: Color(0xFF243040),
  ),
  'warm': Tone(
    label: 'عاجي دافئ',
    background: Color(0xFFF1F0EC),
    bar: Color(0xFFFFFFFF),
    surface: Color(0xFFFFFFFF),
    surface2: Color(0xFFF7F6F3),
    surface3: Color(0xFFFFFFFF),
    rule: Color(0xFFDDDBD5),
    muted: Color(0xFF5E5C57),
    text: Color(0xFF262626),
    input: Color(0xFFF7F6F3),
    overlay: Color(0xFF262626),
  ),
};

/// المظهر الحالي (من الإعدادات الحية، أو من إعدادات ما قبل الدخول).
Appearance appearance = Appearance.defaults;

/// درجات الوضع الحالي.
Tone toneOf(BuildContext context) => appearance.tone(Theme.of(context).brightness);
