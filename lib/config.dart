/// إعدادات الاتصال بمشروع Supabase.
///
/// تُمرَّر عند البناء:
///   flutter run --dart-define=SUPABASE_URL=https://xxxx.supabase.co --dart-define=SUPABASE_ANON_KEY=eyJ...
///
/// أو اكتبها مباشرة في defaultValue أدناه.
/// استخدم المفتاح العام (anon / publishable) فقط، ولا تضع مفتاح service_role في التطبيق أبداً.
class AppConfig {
  static const String supabaseUrl = String.fromEnvironment('SUPABASE_URL', defaultValue: '');
  static const String supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY', defaultValue: '');

  static bool get isConfigured => supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;

  /// رقم الإصدار ورقم البناء، يضعهما سير عمل «release». النسخ التجريبية رقم بنائها 0.
  static const String appVersion = String.fromEnvironment('APP_VERSION', defaultValue: 'نسخة تجريبية');
  static const int appBuild = int.fromEnvironment('APP_BUILD', defaultValue: 0);

  /// النسخ التجريبية لا تعرض تنبيه التحديث.
  static bool get isRelease => appBuild > 0;
}
