import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../app_state.dart';
import '../models.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';
import 'home_shell.dart';

/// يقرر ما يُعرض: الدخول، أو انتظار التفعيل، أو التطبيق.
class AuthGate extends StatefulWidget {
  const AuthGate({super.key, required this.state});

  final AppState state;

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  StreamSubscription<AuthState>? _sub;
  String? _uid;
  bool _checking = true;
  String? _error;

  AppState get app => widget.state;

  @override
  void initState() {
    super.initState();
    _sub = Supabase.instance.client.auth.onAuthStateChange.listen((_) => _sync());
    _sync();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _sync({bool force = false}) async {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == _uid && !force) return;
    _uid = uid;
    if (uid == null) {
      app.reset();
      if (mounted) setState(() => _checking = false);
      return;
    }
    if (mounted) setState(() {
      _checking = true;
      _error = null;
    });
    try {
      await app.loadProfile();
      final me = app.me;
      if (me != null && me.active && me.role != null) {
        await app.start();
      }
    } catch (e) {
      _error = friendlyError(e);
    }
    if (mounted) setState(() => _checking = false);
  }

  @override
  Widget build(BuildContext context) {
    final session = Supabase.instance.client.auth.currentSession;
    if (session == null) return const LoginScreen();
    if (_checking) return const _Splash();
    if (_error != null) {
      return Scaffold(
        body: Center(
          child: EmptyState(
            icon: Icons.cloud_off_outlined,
            title: 'تعذّر تحميل حسابك',
            message: _error,
            action: FilledButton(onPressed: () => _sync(force: true), child: const Text('إعادة المحاولة')),
          ),
        ),
      );
    }
    final me = app.me;
    if (me == null || !me.active || me.role == null) {
      return PendingScreen(profile: me, onRefresh: () => _sync(force: true));
    }
    return const HomeShell();
  }
}

class _Splash extends StatelessWidget {
  const _Splash();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}

/// تسجيل الدخول وإنشاء حساب.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _signUp = false;
  bool _busy = false;
  bool _obscure = true;
  String? _error;
  String? _info;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = _email.text.trim();
    final password = _password.text;
    final name = _name.text.trim();
    setState(() {
      _error = null;
      _info = null;
    });
    if (!email.contains('@')) {
      setState(() => _error = 'اكتب بريداً إلكترونياً صحيحاً.');
      return;
    }
    if (password.length < 8) {
      setState(() => _error = 'كلمة المرور 8 أحرف على الأقل.');
      return;
    }
    if (_signUp && name.isEmpty) {
      setState(() => _error = 'اكتب اسمك الكامل كما سيظهر لزملائك.');
      return;
    }
    setState(() => _busy = true);
    final auth = Supabase.instance.client.auth;
    try {
      if (_signUp) {
        final res = await auth.signUp(email: email, password: password, data: {'full_name': name});
        if (res.session == null && mounted) {
          setState(() {
            _signUp = false;
            _info = 'أُنشئ الحساب. افتح الرسالة المرسلة إلى بريدك لتأكيده، ثم سجّل الدخول.';
          });
        }
      } else {
        await auth.signInWithPassword(email: email, password: password);
      }
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final sem = Sem.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    clipBehavior: Clip.antiAlias,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: sem.rule),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(14, 18, 14, 10),
                          child: Image.asset(Brand.banner, fit: BoxFit.contain, filterQuality: FilterQuality.medium),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                          child: Column(
                            children: [
                              Text('مكتب الشؤون الهندسية',
                                  style: t.bodyMedium?.copyWith(color: const Color(0xFF5E5C57))),
                              const SizedBox(height: 2),
                              Text('منظومة متابعة الدورة المستندية للمشاريع',
                                  textAlign: TextAlign.center,
                                  style: t.titleLarge?.copyWith(color: Brand.ink, fontWeight: FontWeight.w700)),
                            ],
                          ),
                        ),
                        const BrandStripe(),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(value: false, label: Text('تسجيل الدخول')),
                      ButtonSegment(value: true, label: Text('حساب جديد')),
                    ],
                    selected: {_signUp},
                    showSelectedIcon: false,
                    onSelectionChanged: _busy ? null : (s) => setState(() => _signUp = s.first),
                  ),
                  const SizedBox(height: 16),
                  if (_signUp) ...[
                    TextField(
                      controller: _name,
                      textInputAction: TextInputAction.next,
                      decoration: fieldDeco('الاسم الكامل', prefixIcon: const Icon(Icons.badge_outlined)),
                    ),
                    const SizedBox(height: 12),
                  ],
                  TextField(
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    textDirection: TextDirection.ltr,
                    textInputAction: TextInputAction.next,
                    autofillHints: const [AutofillHints.email],
                    decoration: fieldDeco('البريد الإلكتروني', prefixIcon: const Icon(Icons.alternate_email)),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _password,
                    obscureText: _obscure,
                    textDirection: TextDirection.ltr,
                    onSubmitted: (_) => _busy ? null : _submit(),
                    autofillHints: const [AutofillHints.password],
                    decoration: fieldDeco('كلمة المرور',
                        prefixIcon: const Icon(Icons.lock_outline),
                        suffix: IconButton(
                          icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                          onPressed: () => setState(() => _obscure = !_obscure),
                        )),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(_error!, style: TextStyle(color: sem.danger)),
                  ],
                  if (_info != null) ...[
                    const SizedBox(height: 12),
                    Text(_info!, style: TextStyle(color: sem.ok)),
                  ],
                  const SizedBox(height: 18),
                  FilledButton(
                    onPressed: _busy ? null : _submit,
                    style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                    child: _busy
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                        : Text(_signUp ? 'إنشاء الحساب' : 'دخول'),
                  ),
                  if (_signUp) ...[
                    const SizedBox(height: 12),
                    Text('بعد إنشاء الحساب يبقى بانتظار تفعيل مدير المكتب وتحديد دورك.',
                        textAlign: TextAlign.center, style: TextStyle(color: sem.muted, fontSize: 13)),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// حساب لم يُفعَّل بعد.
class PendingScreen extends StatelessWidget {
  const PendingScreen({super.key, required this.profile, required this.onRefresh});

  final Profile? profile;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final sem = Sem.of(context);
    return Scaffold(
      appBar: brandAppBar(context, showEmblem: true, title: const Text('الدورة المستندية')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Column(
              children: [
                EmptyState(
                  icon: Icons.hourglass_top_outlined,
                  title: 'حسابك بانتظار التفعيل',
                  message: 'أُبلغ مدير المكتب بطلبك. ستتمكن من الدخول بعد أن يفعّل حسابك ويحدد دورك.',
                ),
                if (profile != null)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                        color: sem.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: sem.rule)),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(profile!.displayName, style: const TextStyle(fontWeight: FontWeight.w700)),
                        Text(profile!.email, textDirection: TextDirection.ltr, style: TextStyle(color: sem.muted)),
                      ],
                    ),
                  ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(child: FilledButton.icon(onPressed: onRefresh, icon: const Icon(Icons.refresh), label: const Text('تحقق مجدداً'))),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => Supabase.instance.client.auth.signOut(),
                        icon: const Icon(Icons.logout),
                        label: const Text('تسجيل الخروج'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// يظهر إذا بُني التطبيق دون عنوان Supabase ومفتاحه.
class SetupMissingScreen extends StatelessWidget {
  const SetupMissingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: brandAppBar(context, showEmblem: true, title: const Text('الدورة المستندية')),
      body: const Center(
        child: EmptyState(
          icon: Icons.settings_outlined,
          title: 'التطبيق غير مربوط بقاعدة البيانات',
          message: 'ابنِ التطبيق مع عنوان مشروع Supabase ومفتاحه العام:\n'
              '--dart-define=SUPABASE_URL=...\n--dart-define=SUPABASE_ANON_KEY=...\n'
              'التفاصيل في ملف README.',
        ),
      ),
    );
  }
}
