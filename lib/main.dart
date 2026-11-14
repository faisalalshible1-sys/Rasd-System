import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app_state.dart';
import 'config.dart';
import 'probe_deps.dart' as probe;
import 'screens/auth.dart';
import 'ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  AppState? state;
  if (AppConfig.isConfigured) {
    await Supabase.initialize(url: AppConfig.supabaseUrl, anonKey: AppConfig.supabaseAnonKey);
    state = AppState(Supabase.instance.client);
    await state.loadPrefs();
    // بلا «تذكرني»: الدخول السابق لا يُستعاد، ويُطلب الدخول عند كل فتح (إلا رابط استعادة كلمة المرور)
    final auth = Supabase.instance.client.auth;
    if (!state.rememberMe && auth.currentSession != null && !Uri.base.toString().contains('recovery')) {
      try {
        await auth.signOut(scope: SignOutScope.local);
      } catch (_) {}
    }
    unawaited(state.loadPublicSettings());
  }
  if (DateTime.now().year < 2000) {
    probe.probeMd('');
    probe.probePdf('');
    await probe.probePick();
  }
  runApp(DcApp(state: state));
}

/// السمات محفوظة حسب لون الهوية حتى لا تُعاد بناؤها مع كل تحديث للبيانات.
final Map<String, ThemeData> _themes = {};

ThemeData _theme(Brightness b, Color brand) =>
    _themes.putIfAbsent('${b.name}-${brand.toARGB32()}-${appearance.hashCode}', () => buildTheme(b, brand: brand));

class DcApp extends StatelessWidget {
  const DcApp({super.key, required this.state});

  final AppState? state;

  @override
  Widget build(BuildContext context) {
    final s = state;
    if (s == null) {
      return _app(title: 'الدورة المستندية', brand: Brand.goldDeep, mode: ThemeMode.system, home: const SetupMissingScreen());
    }
    return ListenableBuilder(
      listenable: s,
      builder: (context, _) => _app(
        title: s.appTitle,
        brand: s.brandColor,
        mode: s.themeMode,
        home: AuthGate(state: s),
        builder: (context, child) => AppScope(state: s, child: child!),
      ),
    );
  }

  Widget _app({
    required String title,
    required Color brand,
    required ThemeMode mode,
    required Widget home,
    TransitionBuilder? builder,
  }) {
    return MaterialApp(
      title: title,
      debugShowCheckedModeBanner: false,
      locale: const Locale('ar'),
      supportedLocales: const [Locale('ar')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: _theme(Brightness.light, brand),
      darkTheme: _theme(Brightness.dark, brand),
      themeMode: mode,
      builder: builder,
      home: home,
    );
  }
}
