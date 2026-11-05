import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models.dart';
import 'appearance.dart';
import 'motion.dart';

export 'appearance.dart';

/// الهوية البصرية مأخوذة من شعار صندوق التنمية وإعادة إعمار ليبيا
/// ولجنة إعادة إعمار منطقة الصابري ووسط البلاد: ذهبي الختم، حبر الخط، وألوان العلم.
class Brand {
  static const Color gold = Color(0xFFCDAE5E);
  static const Color goldDeep = Color(0xFF8A6A1E);
  static const Color goldSoft = Color(0xFFF4ECD6);
  static const Color ink = Color(0xFF262626);
  static const Color flagRedDeep = Color(0xFF963037);
  static const Color flagRed = Color(0xFFCB263D);
  static const Color flagGreen = Color(0xFF27894D);

  static const String emblem = 'assets/brand/emblem.png';
  static const String banner = 'assets/brand/banner.png';
}

/// الخط الأساسي للتطبيق: Readex Pro (عصري وواضح، وأرقامه مقروءة في الجداول).
const String appFontFamily = 'Readex Pro';

ThemeData buildTheme(Brightness brightness, {Color? brand}) {
  final isDark = brightness == Brightness.dark;
  final primary = brand ?? Brand.goldDeep;
  final ap = appearance;
  final tone = ap.tone(brightness);
  final seed = ColorScheme.fromSeed(seedColor: primary, brightness: brightness);
  final hsl = HSLColor.fromColor(primary);
  final scheme = isDark
      ? seed.copyWith(
          // لون الهوية في الداكن أفتح وأقل تشبعاً حتى يريح العين
          primary: hsl
              .withLightness((hsl.lightness + 0.3).clamp(0.55, 0.74))
              .withSaturation((hsl.saturation * 0.78).clamp(0.0, 1.0))
              .toColor(),
          onPrimary: const Color(0xFF17140C),
          primaryContainer: hsl.withLightness(0.24).withSaturation((hsl.saturation * 0.45).clamp(0.0, 1.0)).toColor(),
          onPrimaryContainer: hsl.withLightness(0.86).toColor(),
          secondary: const Color(0xFF5BAF82),
          surface: tone.surface,
          onSurface: tone.text,
          onSurfaceVariant: tone.muted,
          surfaceContainerLowest: tone.background,
          surfaceContainerLow: tone.bar,
          surfaceContainer: tone.surface2,
          surfaceContainerHigh: tone.surface3,
          surfaceContainerHighest: tone.surface3,
          outline: tone.muted,
          outlineVariant: tone.rule,
        )
      : seed.copyWith(
          primary: primary,
          onPrimary: Colors.white,
          primaryContainer: hsl.withLightness(0.92).withSaturation((hsl.saturation * 0.6).clamp(0.0, 1.0)).toColor(),
          onPrimaryContainer: hsl.withLightness(0.22).toColor(),
          secondary: Brand.flagGreen,
          surface: tone.surface,
          onSurface: tone.text,
          onSurfaceVariant: tone.muted,
          surfaceContainerLowest: tone.surface3,
          surfaceContainerLow: tone.surface2,
          surfaceContainer: tone.surface2,
          surfaceContainerHigh: tone.background,
          surfaceContainerHighest: tone.background,
          outline: tone.muted,
          outlineVariant: tone.rule,
        );
  final sem = Sem.forBrightness(brightness);
  final base = ThemeData(colorScheme: scheme, useMaterial3: true, brightness: brightness, visualDensity: ap.visualDensity);
  final text = _arabicText(base.textTheme)
      .apply(bodyColor: tone.text, displayColor: tone.text, fontSizeFactor: ap.fontScale);
  final r = ap.radius;
  final radiusField = BorderRadius.circular((r * 0.72).clamp(6, 18));
  final cardShape = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(r),
    side: ap.cardStyle == 'outlined' ? BorderSide(color: sem.rule) : BorderSide.none,
  );

  return base.copyWith(
    textTheme: text.copyWith(
      titleLarge: text.titleLarge?.copyWith(fontWeight: FontWeight.w600, letterSpacing: 0),
      titleMedium: text.titleMedium?.copyWith(fontWeight: FontWeight.w600),
      bodyMedium: text.bodyMedium?.copyWith(height: 1.55),
      bodyLarge: text.bodyLarge?.copyWith(height: 1.55),
      labelLarge: text.labelLarge?.copyWith(fontWeight: FontWeight.w600),
    ),
    scaffoldBackgroundColor: tone.background,
    canvasColor: tone.background,
    dividerTheme: DividerThemeData(color: sem.rule, thickness: 1, space: 1),
    cardTheme: CardThemeData(
      elevation: ap.cardStyle == 'elevated' ? (isDark ? 3 : 2) : 0,
      shadowColor: Colors.black.withValues(alpha: isDark ? 0.5 : 0.12),
      color: ap.cardStyle == 'filled' ? sem.surface2 : sem.surface,
      surfaceTintColor: Colors.transparent,
      margin: EdgeInsets.zero,
      shape: cardShape,
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: tone.bar,
      foregroundColor: tone.text,
      elevation: 0,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
      titleTextStyle: text.titleMedium?.copyWith(fontWeight: FontWeight.w700),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: tone.input,
      isDense: true,
      contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: ap.density == 'compact' ? 11 : 14),
      border: OutlineInputBorder(borderRadius: radiusField, borderSide: BorderSide(color: sem.rule)),
      enabledBorder: OutlineInputBorder(borderRadius: radiusField, borderSide: BorderSide(color: sem.rule)),
      focusedBorder: OutlineInputBorder(borderRadius: radiusField, borderSide: BorderSide(color: scheme.primary, width: 1.6)),
      errorBorder: OutlineInputBorder(borderRadius: radiusField, borderSide: BorderSide(color: sem.danger)),
      focusedErrorBorder: OutlineInputBorder(borderRadius: radiusField, borderSide: BorderSide(color: sem.danger, width: 1.6)),
      labelStyle: TextStyle(color: sem.muted),
      floatingLabelStyle: TextStyle(color: scheme.primary, fontWeight: FontWeight.w600),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: Size(0, ap.density == 'compact' ? 40 : 46),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: radiusField),
        textStyle: text.labelLarge?.copyWith(fontWeight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: Size(0, ap.density == 'compact' ? 40 : 46),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: radiusField),
        side: BorderSide(color: sem.rule),
        foregroundColor: isDark ? tone.text : null,
        textStyle: text.labelLarge?.copyWith(fontWeight: FontWeight.w600),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: radiusField)),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: SegmentedButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: radiusField),
        side: BorderSide(color: sem.rule),
        selectedBackgroundColor: scheme.primaryContainer,
        selectedForegroundColor: scheme.onPrimaryContainer,
      ),
    ),
    chipTheme: ChipThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular((r * 0.6).clamp(6, 14))),
      side: BorderSide(color: sem.rule),
      backgroundColor: sem.surface,
      selectedColor: scheme.primaryContainer,
      labelStyle: text.labelMedium,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: isDark ? tone.surface2 : tone.surface3,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(r + 6)),
      titleTextStyle: text.titleLarge?.copyWith(fontWeight: FontWeight.w700),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: isDark ? tone.surface2 : sem.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(r + 8))),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: tone.surface3,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: radiusField, side: BorderSide(color: sem.rule)),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: radiusField),
      backgroundColor: tone.overlay,
      contentTextStyle: text.bodyMedium?.copyWith(color: Colors.white),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: tone.bar,
      surfaceTintColor: Colors.transparent,
      indicatorColor: scheme.primaryContainer,
      height: ap.density == 'compact' ? 60 : 66,
      labelTextStyle: WidgetStatePropertyAll(text.labelSmall?.copyWith(fontWeight: FontWeight.w600)),
    ),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: tone.bar,
      indicatorColor: scheme.primaryContainer,
    ),
    tabBarTheme: TabBarThemeData(
      labelStyle: text.labelLarge?.copyWith(fontWeight: FontWeight.w700),
      unselectedLabelStyle: text.labelLarge,
      dividerColor: sem.rule,
      indicatorSize: TabBarIndicatorSize.label,
    ),
    listTileTheme: ListTileThemeData(shape: RoundedRectangleBorder(borderRadius: radiusField)),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(color: tone.overlay, borderRadius: BorderRadius.circular(8)),
      textStyle: text.bodySmall?.copyWith(color: Colors.white),
    ),
    // انتقال الصفحات: صعود وتلاشٍ للجديدة، وانكماش خفيف للسابقة (iOS يحتفظ بسحب الرجوع)
    pageTransitionsTheme: const PageTransitionsTheme(builders: {
      TargetPlatform.android: DcPageTransitionsBuilder(),
      TargetPlatform.fuchsia: DcPageTransitionsBuilder(),
      TargetPlatform.windows: DcPageTransitionsBuilder(),
      TargetPlatform.linux: DcPageTransitionsBuilder(),
      TargetPlatform.macOS: DcPageTransitionsBuilder(),
      TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
    }),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? Colors.white : null),
      trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? scheme.primary : null),
    ),
  );
}

TextTheme _arabicText(TextTheme base) {
  try {
    return GoogleFonts.getTextTheme(appFontFamily, base);
  } catch (_) {
    try {
      return GoogleFonts.getTextTheme('IBM Plex Sans Arabic', base);
    } catch (_) {
      return base; // خط النظام عند تعذّر تحميل الخط
    }
  }
}

bool _isDark(BuildContext context) => Theme.of(context).brightness == Brightness.dark;

/// لون البطاقة حسب شكلها المختار في «التخصيص والتطوير».
Color cardColor(BuildContext context) => appearance.cardStyle == 'filled' ? Sem.of(context).surface2 : Sem.of(context).surface;

/// زخرفة البطاقات الموحّدة: الاستدارة والحدود والظل من إعداد المظهر.
BoxDecoration cardDecoration(BuildContext context, {Color? color, double? radius}) {
  final sem = Sem.of(context);
  final ap = appearance;
  return BoxDecoration(
    color: color ?? cardColor(context),
    borderRadius: BorderRadius.circular(radius ?? ap.radius),
    border: ap.cardStyle == 'outlined' ? Border.all(color: sem.rule) : null,
    boxShadow: ap.cardStyle == 'elevated'
        ? [BoxShadow(color: Colors.black.withValues(alpha: _isDark(context) ? 0.32 : 0.07), blurRadius: 18, offset: const Offset(0, 6))]
        : null,
  );
}

/// شكل البطاقات القابلة للضغط (Material).
ShapeBorder cardShape(BuildContext context, {double? radius}) => RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(radius ?? appearance.radius),
      side: appearance.cardStyle == 'outlined' ? BorderSide(color: Sem.of(context).rule) : BorderSide.none,
    );

/// ظل البطاقات المرتفعة.
double cardElevation(BuildContext context) => appearance.cardStyle == 'elevated' ? (_isDark(context) ? 3 : 2) : 0;

/// لون شريط التطبيق العلوي.
Color barColor(BuildContext context) => toneOf(context).bar;

/// لون النص على الشريط العلوي.
Color barForeground(BuildContext context) => toneOf(context).text;

/// شريط ألوان العلم كما يظهر تحت الخط في الشعار.
class BrandStripe extends StatelessWidget implements PreferredSizeWidget {
  const BrandStripe({super.key, this.height = 3});

  final double height;

  @override
  Size get preferredSize => Size.fromHeight(height);

  @override
  Widget build(BuildContext context) {
    final black = _isDark(context) ? toneOf(context).rule : Brand.ink;
    return SizedBox(
      height: height,
      child: Row(
        textDirection: TextDirection.ltr,
        children: [
          const Expanded(flex: 1, child: ColoredBox(color: Brand.flagRedDeep)),
          const Expanded(flex: 1, child: ColoredBox(color: Brand.flagRed)),
          Expanded(flex: 3, child: ColoredBox(color: black)),
          const Expanded(flex: 2, child: ColoredBox(color: Brand.flagGreen)),
        ],
      ),
    );
  }
}

/// ختم المؤسسة الدائري.
class BrandEmblem extends StatelessWidget {
  const BrandEmblem({super.key, this.size = 36});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Image.asset(Brand.emblem, width: size, height: size, filterQuality: FilterQuality.medium);
  }
}

/// شريط علوي موحّد لكل الشاشات، بألوان الهوية وشريط العلم.
AppBar brandAppBar(BuildContext context,
    {required Widget title, List<Widget>? actions, Widget? leading, PreferredSizeWidget? bottom, bool showEmblem = false}) {
  return AppBar(
    backgroundColor: barColor(context),
    foregroundColor: barForeground(context),
    surfaceTintColor: Colors.transparent,
    elevation: 0,
    scrolledUnderElevation: 0,
    centerTitle: false,
    leading: leading,
    title: showEmblem
        ? Row(children: [const BrandEmblem(size: 38), const SizedBox(width: 10), Expanded(child: title)])
        : title,
    actions: actions,
    bottom: bottom ?? const BrandStripe(),
  );
}

/// زخرفة حقل إدخال موحّدة (الشكل من سمة التطبيق).
InputDecoration fieldDeco(String label, {String? hint, String? error, Widget? suffix, Widget? prefixIcon, String? helper}) =>
    InputDecoration(
      labelText: label,
      hintText: hint,
      errorText: error,
      helperText: helper,
      helperMaxLines: 3,
      suffixIcon: suffix,
      prefixIcon: prefixIcon,
    );

/// الألوان الدلالية لحالات النماذج، مستقلة عن لون الهوية.
class Sem {
  const Sem({
    required this.ok,
    required this.okSoft,
    required this.wip,
    required this.wipSoft,
    required this.todo,
    required this.todoSoft,
    required this.na,
    required this.danger,
    required this.dangerSoft,
    required this.surface,
    required this.surface2,
    required this.rule,
    required this.muted,
  });

  final Color ok, okSoft, wip, wipSoft, todo, todoSoft, na, danger, dangerSoft, surface, surface2, rule, muted;

  static const _lightBase = Sem(
    ok: Color(0xFF1E7A4C),
    okSoft: Color(0xFFDCEFE4),
    wip: Color(0xFFC2570C),
    wipSoft: Color(0xFFFBE5D3),
    todo: Color(0xFFA7ABB1),
    todoSoft: Color(0xFFE6E8EB),
    na: Color(0xFFC7CBD0),
    danger: Color(0xFFB4232F),
    dangerSoft: Color(0xFFF6DDE0),
    surface: Color(0xFFFFFFFF),
    surface2: Color(0xFFF7F6F3),
    rule: Color(0xFFDDDBD5),
    muted: Color(0xFF5E5C57),
  );

  // ألوان الحالات في الداكن أهدأ تشبعاً حتى لا تُجهد العين
  static const _darkBase = Sem(
    ok: Color(0xFF5DB88A),
    okSoft: Color(0xFF1E3A2E),
    wip: Color(0xFFE39A62),
    wipSoft: Color(0xFF3D2C20),
    todo: Color(0xFF66707C),
    todoSoft: Color(0xFF2A3038),
    na: Color(0xFF3E4650),
    danger: Color(0xFFE57C85),
    dangerSoft: Color(0xFF402429),
    surface: Color(0xFF20252C),
    surface2: Color(0xFF272D35),
    rule: Color(0xFF353D47),
    muted: Color(0xFF9AA4B1),
  );

  Sem _withTone(Tone t) => Sem(
        ok: ok,
        okSoft: okSoft,
        wip: wip,
        wipSoft: wipSoft,
        todo: todo,
        todoSoft: todoSoft,
        na: na,
        danger: danger,
        dangerSoft: dangerSoft,
        surface: t.surface,
        surface2: t.surface2,
        rule: t.rule,
        muted: t.muted,
      );

  static final Map<String, Sem> _cache = {};

  /// الألوان حسب الوضع ودرجته المختارة في «التخصيص والتطوير».
  static Sem forBrightness(Brightness b) {
    final isDark = b == Brightness.dark;
    final key = isDark ? 'd:${appearance.darkTone}' : 'l:${appearance.lightTone}';
    return _cache.putIfAbsent(key, () => (isDark ? _darkBase : _lightBase)._withTone(appearance.tone(b)));
  }

  static Sem get light => forBrightness(Brightness.light);
  static Sem get dark => forBrightness(Brightness.dark);

  static Sem of(BuildContext context) => forBrightness(Theme.of(context).brightness);

  Color statusColor(FormStatus s) => switch (s) {
        FormStatus.done => ok,
        FormStatus.wip => wip,
        FormStatus.todo => todo,
        FormStatus.na => na,
      };

  Color statusSoft(FormStatus s) => switch (s) {
        FormStatus.done => okSoft,
        FormStatus.wip => wipSoft,
        FormStatus.todo => todoSoft,
        FormStatus.na => surface2,
      };

  Color cycleColor(CycleState c) => switch (c) {
        CycleState.complete => ok,
        CycleState.running => wip,
        CycleState.notStarted => muted,
      };

  Color cycleSoft(CycleState c) => switch (c) {
        CycleState.complete => okSoft,
        CycleState.running => wipSoft,
        CycleState.notStarted => todoSoft,
      };
}
