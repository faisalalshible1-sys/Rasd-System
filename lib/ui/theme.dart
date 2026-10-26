import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models.dart';

const Color brandPetrol = Color(0xFF0B5C68);

ThemeData buildTheme(Brightness brightness) {
  final scheme = ColorScheme.fromSeed(seedColor: brandPetrol, brightness: brightness);
  final base = ThemeData(colorScheme: scheme, useMaterial3: true);
  final isDark = brightness == Brightness.dark;
  return base.copyWith(
    textTheme: _arabicText(base.textTheme),
    scaffoldBackgroundColor: isDark ? const Color(0xFF0C1215) : const Color(0xFFEEF2F4),
  );
}

TextTheme _arabicText(TextTheme base) {
  try {
    return GoogleFonts.getTextTheme('IBM Plex Sans Arabic', base);
  } catch (_) {
    return base; // خط النظام عند تعذّر تحميل الخط
  }
}

/// لون شريط التطبيق العلوي.
Color barColor(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark ? const Color(0xFF0E2A30) : const Color(0xFF0B4650);

/// شريط علوي موحّد لكل الشاشات.
AppBar brandAppBar(BuildContext context, {required Widget title, List<Widget>? actions, Widget? leading, PreferredSizeWidget? bottom}) {
  return AppBar(
    backgroundColor: barColor(context),
    foregroundColor: Colors.white,
    elevation: 0,
    scrolledUnderElevation: 0,
    centerTitle: false,
    leading: leading,
    title: title,
    actions: actions,
    bottom: bottom,
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
    wip: Color(0xFFB0690F),
    wipSoft: Color(0xFFF7E8D0),
    todo: Color(0xFFA6B3BC),
    todoSoft: Color(0xFFE6ECEF),
    na: Color(0xFFC3CDD3),
    danger: Color(0xFFB4232F),
    dangerSoft: Color(0xFFF6DDE0),
    surface: Color(0xFFFFFFFF),
    surface2: Color(0xFFF5F8F9),
    rule: Color(0xFFD3DCE1),
    muted: Color(0xFF5A6B77),
  );

  static const dark = Sem(
    ok: Color(0xFF4BB57E),
    okSoft: Color(0xFF163226),
    wip: Color(0xFFE2A04A),
    wipSoft: Color(0xFF3A2913),
    todo: Color(0xFF4A5964),
    todoSoft: Color(0xFF212D34),
    na: Color(0xFF2D3A42),
    danger: Color(0xFFEE6E79),
    dangerSoft: Color(0xFF3A1C20),
    surface: Color(0xFF141C21),
    surface2: Color(0xFF1A242A),
    rule: Color(0xFF26333B),
    muted: Color(0xFF91A2AD),
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
