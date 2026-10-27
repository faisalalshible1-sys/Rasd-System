import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models.dart';

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
  final seed = ColorScheme.fromSeed(seedColor: primary, brightness: brightness);
  final hsl = HSLColor.fromColor(primary);
  final scheme = isDark
      ? seed.copyWith(
          primary: hsl.withLightness((hsl.lightness + 0.32).clamp(0.55, 0.78)).toColor(),
          onPrimary: const Color(0xFF1C1607),
          primaryContainer: hsl.withLightness(0.2).withSaturation((hsl.saturation * 0.6).clamp(0.0, 1.0)).toColor(),
          onPrimaryContainer: hsl.withLightness(0.86).toColor(),
          secondary: Brand.flagGreen,
          surface: const Color(0xFF171716),
          surfaceContainerLowest: const Color(0xFF121211),
          surfaceContainerLow: const Color(0xFF1B1B1A),
          surfaceContainer: const Color(0xFF201F1E),
          surfaceContainerHigh: const Color(0xFF282725),
          outlineVariant: const Color(0xFF34322E),
        )
      : seed.copyWith(
          primary: primary,
          onPrimary: Colors.white,
          primaryContainer: hsl.withLightness(0.93).withSaturation((hsl.saturation * 0.7).clamp(0.0, 1.0)).toColor(),
          onPrimaryContainer: hsl.withLightness(0.22).toColor(),
          secondary: Brand.flagGreen,
          surface: Colors.white,
          surfaceContainerLowest: Colors.white,
          surfaceContainerLow: const Color(0xFFF8F7F4),
          surfaceContainer: const Color(0xFFF3F2EE),
          surfaceContainerHigh: const Color(0xFFECEAE5),
          outlineVariant: const Color(0xFFE3E1DB),
        );
  final sem = isDark ? Sem.dark : Sem.light;
  final base = ThemeData(colorScheme: scheme, useMaterial3: true, brightness: brightness, visualDensity: VisualDensity.standard);
  final text = _arabicText(base.textTheme).apply(bodyColor: isDark ? const Color(0xFFECEAE4) : Brand.ink, displayColor: isDark ? Colors.white : Brand.ink);
  final radius12 = BorderRadius.circular(12);

  return base.copyWith(
    textTheme: text.copyWith(
      titleLarge: text.titleLarge?.copyWith(fontWeight: FontWeight.w600, letterSpacing: 0),
      titleMedium: text.titleMedium?.copyWith(fontWeight: FontWeight.w600),
      bodyMedium: text.bodyMedium?.copyWith(height: 1.55),
      bodyLarge: text.bodyLarge?.copyWith(height: 1.55),
      labelLarge: text.labelLarge?.copyWith(fontWeight: FontWeight.w600),
    ),
    scaffoldBackgroundColor: isDark ? const Color(0xFF0F0F0E) : const Color(0xFFF4F3EF),
    dividerTheme: DividerThemeData(color: sem.rule, thickness: 1, space: 1),
    cardTheme: CardThemeData(
      elevation: 0,
      color: sem.surface,
      surfaceTintColor: Colors.transparent,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: BorderSide(color: sem.rule)),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: isDark ? const Color(0xFF151514) : Colors.white,
      foregroundColor: isDark ? Colors.white : Brand.ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
      titleTextStyle: text.titleMedium?.copyWith(fontWeight: FontWeight.w700),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: isDark ? const Color(0xFF1E1E1C) : const Color(0xFFF7F6F3),
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(borderRadius: radius12, borderSide: BorderSide(color: sem.rule)),
      enabledBorder: OutlineInputBorder(borderRadius: radius12, borderSide: BorderSide(color: sem.rule)),
      focusedBorder: OutlineInputBorder(borderRadius: radius12, borderSide: BorderSide(color: scheme.primary, width: 1.6)),
      errorBorder: OutlineInputBorder(borderRadius: radius12, borderSide: BorderSide(color: sem.danger)),
      focusedErrorBorder: OutlineInputBorder(borderRadius: radius12, borderSide: BorderSide(color: sem.danger, width: 1.6)),
      labelStyle: TextStyle(color: sem.muted),
      floatingLabelStyle: TextStyle(color: scheme.primary, fontWeight: FontWeight.w600),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 46),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: radius12),
        textStyle: text.labelLarge?.copyWith(fontWeight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 46),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: radius12),
        side: BorderSide(color: sem.rule),
        textStyle: text.labelLarge?.copyWith(fontWeight: FontWeight.w600),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: radius12)),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: SegmentedButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: radius12),
        side: BorderSide(color: sem.rule),
        selectedBackgroundColor: scheme.primaryContainer,
        selectedForegroundColor: scheme.onPrimaryContainer,
      ),
    ),
    chipTheme: ChipThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      side: BorderSide(color: sem.rule),
      backgroundColor: sem.surface,
      selectedColor: scheme.primaryContainer,
      labelStyle: text.labelMedium,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: sem.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      titleTextStyle: text.titleLarge?.copyWith(fontWeight: FontWeight.w700),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: sem.surface,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: radius12),
      backgroundColor: isDark ? const Color(0xFF2C2B28) : Brand.ink,
      contentTextStyle: text.bodyMedium?.copyWith(color: Colors.white),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: isDark ? const Color(0xFF151514) : Colors.white,
      surfaceTintColor: Colors.transparent,
      indicatorColor: scheme.primaryContainer,
      height: 66,
      labelTextStyle: WidgetStatePropertyAll(text.labelSmall?.copyWith(fontWeight: FontWeight.w600)),
    ),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: isDark ? const Color(0xFF151514) : Colors.white,
      indicatorColor: scheme.primaryContainer,
    ),
    tabBarTheme: TabBarThemeData(
      labelStyle: text.labelLarge?.copyWith(fontWeight: FontWeight.w700),
      unselectedLabelStyle: text.labelLarge,
      dividerColor: sem.rule,
      indicatorSize: TabBarIndicatorSize.label,
    ),
    listTileTheme: ListTileThemeData(shape: RoundedRectangleBorder(borderRadius: radius12)),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(color: isDark ? const Color(0xFF2C2B28) : Brand.ink, borderRadius: BorderRadius.circular(8)),
      textStyle: text.bodySmall?.copyWith(color: Colors.white),
    ),
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

/// لون شريط التطبيق العلوي.
Color barColor(BuildContext context) => _isDark(context) ? const Color(0xFF171716) : Colors.white;

/// لون النص على الشريط العلوي.
Color barForeground(BuildContext context) => _isDark(context) ? Colors.white : Brand.ink;

/// شريط ألوان العلم كما يظهر تحت الخط في الشعار.
class BrandStripe extends StatelessWidget implements PreferredSizeWidget {
  const BrandStripe({super.key, this.height = 3});

  final double height;

  @override
  Size get preferredSize => Size.fromHeight(height);

  @override
  Widget build(BuildContext context) {
    final black = _isDark(context) ? const Color(0xFF3A3936) : Brand.ink;
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

  static const light = Sem(
    ok: Color(0xFF1E7A4C),
    okSoft: Color(0xFFDCEFE4),
    wip: Color(0xFFC2570C),
    wipSoft: Color(0xFFFBE5D3),
    todo: Color(0xFFACA9A2),
    todoSoft: Color(0xFFECEAE5),
    na: Color(0xFFCAC7C0),
    danger: Color(0xFFB4232F),
    dangerSoft: Color(0xFFF6DDE0),
    surface: Color(0xFFFFFFFF),
    surface2: Color(0xFFF7F6F3),
    rule: Color(0xFFDDDBD5),
    muted: Color(0xFF5E5C57),
  );

  static const dark = Sem(
    ok: Color(0xFF4BB57E),
    okSoft: Color(0xFF163226),
    wip: Color(0xFFF08A4B),
    wipSoft: Color(0xFF3B2416),
    todo: Color(0xFF55534E),
    todoSoft: Color(0xFF2A2926),
    na: Color(0xFF3A3834),
    danger: Color(0xFFEE6E79),
    dangerSoft: Color(0xFF3A1C20),
    surface: Color(0xFF1A1A19),
    surface2: Color(0xFF222220),
    rule: Color(0xFF34322E),
    muted: Color(0xFFA3A098),
  );

  static Sem of(BuildContext context) => Theme.of(context).brightness == Brightness.dark ? dark : light;

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
