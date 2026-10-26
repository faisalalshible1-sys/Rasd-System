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

ThemeData buildTheme(Brightness brightness) {
  final isDark = brightness == Brightness.dark;
  final seed = ColorScheme.fromSeed(seedColor: Brand.gold, brightness: brightness);
  final scheme = isDark
      ? seed.copyWith(
          primary: const Color(0xFFDDBF72),
          onPrimary: const Color(0xFF2A2006),
          primaryContainer: const Color(0xFF3A2F14),
          onPrimaryContainer: const Color(0xFFF1DFAE),
          secondary: Brand.flagGreen,
        )
      : seed.copyWith(
          primary: Brand.goldDeep,
          onPrimary: Colors.white,
          primaryContainer: Brand.goldSoft,
          onPrimaryContainer: const Color(0xFF4A3908),
          secondary: Brand.flagGreen,
        );
  final base = ThemeData(colorScheme: scheme, useMaterial3: true);
  return base.copyWith(
    textTheme: _arabicText(base.textTheme),
    scaffoldBackgroundColor: isDark ? const Color(0xFF111110) : const Color(0xFFF3F3F1),
  );
}

TextTheme _arabicText(TextTheme base) {
  try {
    return GoogleFonts.getTextTheme('IBM Plex Sans Arabic', base);
  } catch (_) {
    return base; // خط النظام عند تعذّر تحميل الخط
  }
}

bool _isDark(BuildContext context) => Theme.of(context).brightness == Brightness.dark;

/// لون شريط التطبيق العلوي.
Color barColor(BuildContext context) => _isDark(context) ? const Color(0xFF171716) : Colors.white;

/// لون النص على الشريط العلوي.
Color barForeground(BuildContext context) => _isDark(context) ? Colors.white : Brand.ink;

/// شريط ألوان العلم كما يظهر تحت الخط في الشعار.
class BrandStripe extends StatelessWidget implements PreferredSizeWidget {
  const BrandStripe({super.key, this.height = 4});

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

/// زخرفة حقل إدخال موحّدة.
InputDecoration fieldDeco(String label, {String? hint, String? error, Widget? suffix, Widget? prefixIcon}) => InputDecoration(
      labelText: label,
      hintText: hint,
      errorText: error,
      suffixIcon: suffix,
      prefixIcon: prefixIcon,
      border: const OutlineInputBorder(),
      isDense: true,
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
