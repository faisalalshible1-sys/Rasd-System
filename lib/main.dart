import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app_state.dart';
import 'config.dart';
import 'screens/auth.dart';
import 'ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  AppState? state;
  if (AppConfig.isConfigured) {
    await Supabase.initialize(url: AppConfig.supabaseUrl, anonKey: AppConfig.supabaseAnonKey);
    state = AppState(Supabase.instance.client);
  }
  runApp(DcApp(state: state));
}

class DcApp extends StatelessWidget {
  const DcApp({super.key, required this.state});

  final AppState? state;

  @override
  Widget build(BuildContext context) {
    final s = state;
    return MaterialApp(
      title: 'الدورة المستندية',
      debugShowCheckedModeBanner: false,
      locale: const Locale('ar'),
      supportedLocales: const [Locale('ar')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      themeMode: ThemeMode.system,
      builder: (context, child) => s == null ? child! : AppScope(state: s, child: child!),
      home: s == null ? const SetupMissingScreen() : AuthGate(state: s),
    );
  }
}
