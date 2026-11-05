import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../app_state.dart';
import '../models.dart';
import '../ui/motion.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';
import 'home_shell.dart';

/// يقرر ما يُعرض: الدخول، أو رمز التحقق، أو تفعيل التحقق بخطوتين، أو انتظار التفعيل، أو التطبيق.
class AuthGate extends StatefulWidget {
  const AuthGate({super.key, required this.state});

  final AppState state;

  @override
  State<AuthGate> createState() => _AuthGateState();
}

enum _Gate { checking, login, mfaChallenge, mfaEnroll, pending, error, ready, recovery, locked }

class _AuthGateState extends State<AuthGate> {
  StreamSubscription<AuthState>? _sub;
  String? _key;
  _Gate _gate = _Gate.checking;
  String? _error;

  AppState get app => widget.state;
  GoTrueClient get auth => Supabase.instance.client.auth;

  @override
  void initState() {
    super.initState();
    // حظر الجهاز أو قفل الحساب أثناء الاستخدام (يكتشفه فحص دوري كل 15 دقيقة)
    app.onSecurityHalt = (kind) {
      if (kind == 'blocked') {
        _blockedSignOut();
      } else {
        _sync(force: true);
      }
    };
    _sub = auth.onAuthStateChange.listen((s) {
      if (s.event == AuthChangeEvent.passwordRecovery) {
        if (mounted) setState(() => _gate = _Gate.recovery);
        return;
      }
      _sync();
    });
    _sync();
  }

  @override
  void dispose() {
    _sub?.cancel();
    if (app.onSecurityHalt != null) app.onSecurityHalt = null;
    super.dispose();
  }

  Future<void> _blockedSignOut() async {
    app.securityNotice = 'هذا الجهاز محظور من الدخول بقرار أمني. ادخل من جهاز آخر موثوق، أو راجع مدير المكتب.';
    try {
      await auth.signOut(scope: SignOutScope.local);
    } catch (_) {}
  }

  Future<void> _sync({bool force = false}) async {
    if (_gate == _Gate.recovery && !force) return;
    final session = auth.currentSession;
    final uid = session?.user.id;
    final aal = uid == null ? '' : auth.mfa.getAuthenticatorAssuranceLevel().currentLevel?.name ?? '';
    final key = '$uid|$aal';
    if (key == _key && !force) return;
    _key = key;
    if (uid == null) {
      app.reset();
      unawaited(app.loadPublicSettings());
      if (mounted) setState(() => _gate = _Gate.login);
      return;
    }
    if (mounted) {
      setState(() {
        _gate = _Gate.checking;
        _error = null;
      });
    }
    try {
      if (app.needsMfaChallenge) {
        if (mounted) setState(() => _gate = _Gate.mfaChallenge);
        return;
      }
      await app.loadPublicSettings();
      await app.loadProfile();
      // سجل الأجهزة: الجهاز المحظور يُخرج فوراً، والحساب المقفل لا يدخل
      final device = await app.registerDevice();
      if (device == 'blocked') {
        await _blockedSignOut();
        return;
      }
      final me = app.me;
      if (device == 'locked' || (me?.locked ?? false)) {
        if (mounted) setState(() => _gate = _Gate.locked);
        return;
      }
      if (me == null || !me.active || me.role == null) {
        if (mounted) setState(() => _gate = _Gate.pending);
        return;
      }
      if (app.mfaRequiredForMe) {
        final factors = await app.verifiedFactors();
        if (factors.isEmpty) {
          if (mounted) setState(() => _gate = _Gate.mfaEnroll);
          return;
        }
      }
      await app.start();
      if (mounted) setState(() => _gate = _Gate.ready);
    } catch (e) {
      _error = friendlyError(e);
      if (mounted) setState(() => _gate = _Gate.error);
    }
  }

  /// الانتقال بين الدخول والتحميل والتطبيق بحركة ناعمة (تلاشٍ وتكبير خفيف).
  @override
  Widget build(BuildContext context) {
    return MotionSwitcher(
      duration: const Duration(milliseconds: 620),
      offset: const Offset(0, 0.012),
      child: KeyedSubtree(key: ValueKey(_gate), child: _screen()),
    );
  }

  Widget _screen() {
    switch (_gate) {
      case _Gate.login:
        return const LoginScreen();
      case _Gate.checking:
        return const _Splash();
      case _Gate.recovery:
        return NewPasswordScreen(onDone: () {
          setState(() => _gate = _Gate.checking);
          _sync(force: true);
        });
      case _Gate.mfaChallenge:
        return MfaChallengeScreen(onDone: () => _sync(force: true));
      case _Gate.mfaEnroll:
        return MfaEnrollScreen(required: true, onDone: () => _sync(force: true));
      case _Gate.error:
        return Scaffold(
          body: Center(
            child: EmptyState(
              icon: Icons.cloud_off_outlined,
              title: 'تعذّر تحميل حسابك',
              message: _error,
              action: Wrap(spacing: 8, children: [
                FilledButton(onPressed: () => _sync(force: true), child: const Text('إعادة المحاولة')),
                OutlinedButton(onPressed: () => auth.signOut(), child: const Text('تسجيل الخروج')),
              ]),
            ),
          ),
        );
      case _Gate.pending:
        return PendingScreen(profile: app.me, onRefresh: () => _sync(force: true));
      case _Gate.locked:
        return LockedScreen(profile: app.me, onRefresh: () => _sync(force: true));
      case _Gate.ready:
        return const HomeShell();
    }
  }
}

/// شاشة التحميل: الختم نابضاً بحلقات تتسع، واسم المنظومة يظهر تدريجياً.
class _Splash extends StatelessWidget {
  const _Splash();

  @override
  Widget build(BuildContext context) {
    final app = AppScope.maybeRead(context);
    final t = Theme.of(context).textTheme;
    final sem = Sem.of(context);
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const PulseEmblem(size: 78),
            FadeSlideIn(
              delay: const Duration(milliseconds: 180),
              child: Text(app?.appTitle ?? '', textAlign: TextAlign.center, style: t.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
            ),
            const SizedBox(height: 6),
            FadeSlideIn(
              delay: const Duration(milliseconds: 320),
              child: Text('جارٍ تجهيز المنظومة…', style: TextStyle(color: sem.muted)),
            ),
            const SizedBox(height: 18),
            SizedBox(width: 160, child: LinearProgressIndicator(minHeight: 3, borderRadius: BorderRadius.circular(3))),
          ],
        ),
      ),
    );
  }
}

/// إطار شاشات الدخول: لوحة الهوية بجانب النموذج على الشاشات العريضة.
class AuthFrame extends StatelessWidget {
  const AuthFrame({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final wide = MediaQuery.sizeOf(context).width >= 920;
    final cs = Theme.of(context).colorScheme;
    final form = Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 28),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: FadeSlideIn(delay: Duration(milliseconds: wide ? 220 : 60), offset: const Offset(0, 0.035), child: child),
        ),
      ),
    );
    if (!wide) {
      return Scaffold(
        body: SafeArea(
          child: Column(
            children: [
              const BrandStripe(height: 4),
              Expanded(child: form),
            ],
          ),
        ),
      );
    }
    final brand = app.brandColor;
    final hsl = HSLColor.fromColor(brand);
    return Scaffold(
      body: Row(
        children: [
          Expanded(
            flex: 5,
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: AlignmentDirectional.topStart,
                  end: AlignmentDirectional.bottomEnd,
                  colors: [hsl.withLightness((hsl.lightness * 0.55).clamp(0.08, 0.3)).toColor(), brand],
                ),
              ),
              child: Stack(
                children: [
                  const Positioned.fill(child: AnimatedBackdrop()),
                  const Positioned(top: 0, left: 0, right: 0, child: BrandStripe(height: 5)),
                  Padding(
                    padding: const EdgeInsets.all(48),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: staggered(stepMs: 90, startMs: 80, [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            boxShadow: [BoxShadow(color: Colors.black.withAlpha(50), blurRadius: 30, offset: const Offset(0, 12))],
                          ),
                          child: const BrandEmblem(size: 84),
                        ),
                        const SizedBox(height: 28),
                        Text(app.orgName,
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Colors.white.withAlpha(220))),
                        const SizedBox(height: 6),
                        Text(app.appTitle,
                            style: Theme.of(context)
                                .textTheme
                                .displaySmall
                                ?.copyWith(color: Colors.white, fontWeight: FontWeight.w700, height: 1.3)),
                        const SizedBox(height: 18),
                        Text('متابعة نماذج الدورة المستندية للمشاريع من التعاقد حتى الإقفال، بصلاحيات دقيقة واعتماد مدير المكتب.',
                            style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: Colors.white.withAlpha(215))),
                        const SizedBox(height: 32),
                        Wrap(spacing: 10, runSpacing: 10, children: const [
                          _Feature(icon: Icons.verified_user_outlined, text: 'تحقق بخطوتين'),
                          _Feature(icon: Icons.bolt_outlined, text: 'تحديث لحظي'),
                          _Feature(icon: Icons.history_edu_outlined, text: 'سجل تدقيق كامل'),
                          _Feature(icon: Icons.call_merge_rounded, text: 'عقود موحّدة'),
                        ]),
                      ]),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(flex: 4, child: ColoredBox(color: cs.surface, child: form)),
        ],
      ),
    );
  }
}

class _Feature extends StatelessWidget {
  const _Feature({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(color: Colors.white.withAlpha(36), borderRadius: BorderRadius.circular(99)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, color: Colors.white, size: 18),
        const SizedBox(width: 6),
        Text(text, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
      ]),
    );
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
  bool _remember = true;
  bool _init = false;
  String? _error;
  String? _info;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_init) return;
    _init = true;
    final app = AppScope.read(context);
    _remember = app.rememberMe;
    if (app.rememberedEmail.isNotEmpty && _email.text.isEmpty) _email.text = app.rememberedEmail;
    // سبب الخروج الأمني (جهاز محظور أو قفل) يُعرض مرة واحدة
    if (app.securityNotice != null) {
      _error = app.securityNotice;
      app.securityNotice = null;
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  static bool _strong(String p) => p.length >= 10 && RegExp(r'[A-Za-z؀-ۿ]').hasMatch(p) && RegExp(r'\d').hasMatch(p);

  Future<void> _submit() async {
    final email = _email.text.trim();
    final password = _password.text;
    final name = _name.text.trim();
    setState(() {
      _error = null;
      _info = null;
    });
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
      setState(() => _error = 'اكتب بريداً إلكترونياً صحيحاً.');
      return;
    }
    if (_signUp && !_strong(password)) {
      setState(() => _error = 'كلمة المرور 10 أحرف على الأقل، وفيها حروف وأرقام.');
      return;
    }
    if (!_signUp && password.isEmpty) {
      setState(() => _error = 'اكتب كلمة المرور.');
      return;
    }
    if (_signUp && name.length < 3) {
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
        final app = AppScope.read(context);
        app.prepareLogin(remember: _remember);
        await auth.signInWithPassword(email: email, password: password);
        await app.rememberLogin(remember: _remember, email: email);
        // يعرض حفظ كلمة المرور في مدير كلمات المرور فقط مع «تذكرني»
        TextInput.finishAutofillContext(shouldSave: _remember);
      }
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _forgot() async {
    final email = _email.text.trim();
    if (!email.contains('@')) {
      setState(() => _error = 'اكتب بريدك أولاً ثم اضغط «نسيت كلمة المرور».');
      return;
    }
    setState(() => _busy = true);
    try {
      await Supabase.instance.client.auth.resetPasswordForEmail(email);
      if (mounted) setState(() => _info = 'أُرسل إلى بريدك رابط لتعيين كلمة مرور جديدة.');
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final t = Theme.of(context).textTheme;
    final sem = Sem.of(context);
    final wide = MediaQuery.sizeOf(context).width >= 920;
    final signupsOpen = app.signupsOpen;
    if (!signupsOpen && _signUp) _signUp = false;
    return AuthFrame(
      child: AutofillGroup(
        onDisposeAction: _remember ? AutofillContextAction.commit : AutofillContextAction.cancel,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!wide) ...[
              const Center(child: PulseEmblem(size: 76, ripples: false)),
              const SizedBox(height: 14),
              Text(app.orgName, textAlign: TextAlign.center, style: t.bodyMedium?.copyWith(color: sem.muted)),
              Text(app.appTitle, textAlign: TextAlign.center, style: t.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 24),
            ] else ...[
              AnimatedSwitcher(
                duration: Motion.of(context, 300),
                layoutBuilder: (current, previous) => Stack(
                  alignment: AlignmentDirectional.centerStart,
                  children: [...previous, if (current != null) current],
                ),
                child: Column(
                  key: ValueKey(_signUp),
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_signUp ? 'إنشاء حساب' : 'مرحباً بك', style: t.headlineMedium?.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    Text(_signUp ? 'يبقى الحساب بانتظار تفعيل مدير المكتب.' : 'سجّل الدخول لمتابعة العقود ودورتها المستندية.',
                        style: t.bodyMedium?.copyWith(color: sem.muted)),
                  ],
                ),
              ),
              const SizedBox(height: 26),
            ],
            if (signupsOpen) ...[
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: false, label: Text('تسجيل الدخول'), icon: Icon(Icons.login)),
                  ButtonSegment(value: true, label: Text('حساب جديد'), icon: Icon(Icons.person_add_alt)),
                ],
                selected: {_signUp},
                showSelectedIcon: false,
                onSelectionChanged: _busy ? null : (s) => setState(() => _signUp = s.first),
              ),
              const SizedBox(height: 18),
            ],
            AnimatedSize(
              duration: Motion.of(context, 280),
              curve: Curves.easeOutCubic,
              alignment: Alignment.topCenter,
              child: _signUp
                  ? Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: TextField(
                        controller: _name,
                        textInputAction: TextInputAction.next,
                        autofillHints: const [AutofillHints.name],
                        decoration: fieldDeco('الاسم الكامل', prefixIcon: const Icon(Icons.badge_outlined)),
                      ),
                    )
                  : const SizedBox(width: double.infinity),
            ),
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
              autofillHints: [_signUp ? AutofillHints.newPassword : AutofillHints.password],
              decoration: fieldDeco('كلمة المرور',
                  helper: _signUp ? '10 أحرف على الأقل، وفيها حروف وأرقام' : null,
                  prefixIcon: const Icon(Icons.lock_outline),
                  suffix: IconButton(
                    tooltip: _obscure ? 'إظهار' : 'إخفاء',
                    icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  )),
            ),
            if (!_signUp)
              Row(
                children: [
                  Expanded(
                    child: Tooltip(
                      message: 'يبقى دخولك محفوظاً على هذا الجهاز، ويُعرض حفظ كلمة المرور، ويُسجَّل الجهاز موثوقاً لدى مدير الأمن.\n'
                          'بدونها يُطلب الدخول عند كل فتح للتطبيق.',
                      child: InkWell(
                        borderRadius: BorderRadius.circular(10),
                        onTap: _busy ? null : () => setState(() => _remember = !_remember),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Checkbox(
                              value: _remember,
                              visualDensity: VisualDensity.compact,
                              onChanged: _busy ? null : (v) => setState(() => _remember = v ?? false),
                            ),
                            Flexible(child: Text('تذكرني وثِق بهذا الجهاز', style: t.bodyMedium, overflow: TextOverflow.ellipsis)),
                          ],
                        ),
                      ),
                    ),
                  ),
                  TextButton(onPressed: _busy ? null : _forgot, child: const Text('نسيت كلمة المرور؟')),
                ],
              ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              FadeSlideIn(key: ValueKey('e:$_error'), offset: const Offset(0, 0.2), child: InfoBanner(text: _error!, level: 'critical')),
            ],
            if (_info != null) ...[
              const SizedBox(height: 8),
              FadeSlideIn(key: ValueKey('i:$_info'), offset: const Offset(0, 0.2), child: InfoBanner(text: _info!, level: 'ok')),
            ],
            const SizedBox(height: 18),
            FilledButton(
              onPressed: _busy ? null : _submit,
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
              child: _busy
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(_signUp ? 'إنشاء الحساب' : 'دخول'),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.lock_outline, size: 15, color: sem.muted),
                const SizedBox(width: 6),
                Text('اتصال مشفّر · الصلاحيات مفروضة في قاعدة البيانات', style: TextStyle(color: sem.muted, fontSize: 12)),
              ],
            ),
            if (!signupsOpen) ...[
              const SizedBox(height: 10),
              Text('التسجيل الجديد مغلق حالياً. تواصل مع مدير المكتب لإنشاء حسابك.',
                  textAlign: TextAlign.center, style: TextStyle(color: sem.muted, fontSize: 12.5)),
            ],
          ],
        ),
      ),
    );
  }
}

/// تعيين كلمة مرور جديدة بعد فتح رابط الاستعادة.
class NewPasswordScreen extends StatefulWidget {
  const NewPasswordScreen({super.key, required this.onDone});

  final VoidCallback onDone;

  @override
  State<NewPasswordScreen> createState() => _NewPasswordScreenState();
}

class _NewPasswordScreenState extends State<NewPasswordScreen> {
  final _p1 = TextEditingController();
  final _p2 = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _p1.dispose();
    _p2.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final p = _p1.text;
    if (!_LoginScreenState._strong(p)) {
      setState(() => _error = 'كلمة المرور 10 أحرف على الأقل، وفيها حروف وأرقام.');
      return;
    }
    if (p != _p2.text) {
      setState(() => _error = 'كلمتا المرور غير متطابقتين.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await Supabase.instance.client.auth.updateUser(UserAttributes(password: p));
      widget.onDone();
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return AuthFrame(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('كلمة مرور جديدة', style: t.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 18),
          TextField(controller: _p1, obscureText: true, textDirection: TextDirection.ltr, decoration: fieldDeco('كلمة المرور الجديدة')),
          const SizedBox(height: 12),
          TextField(controller: _p2, obscureText: true, textDirection: TextDirection.ltr, decoration: fieldDeco('تأكيد كلمة المرور')),
          if (_error != null) ...[const SizedBox(height: 10), InfoBanner(text: _error!, level: 'critical')],
          const SizedBox(height: 18),
          FilledButton(onPressed: _busy ? null : _save, child: const Text('حفظ والدخول')),
        ],
      ),
    );
  }
}

/// إدخال رمز التحقق بخطوتين عند الدخول.
class MfaChallengeScreen extends StatefulWidget {
  const MfaChallengeScreen({super.key, required this.onDone});

  final VoidCallback onDone;

  @override
  State<MfaChallengeScreen> createState() => _MfaChallengeScreenState();
}

class _MfaChallengeScreenState extends State<MfaChallengeScreen> {
  final _code = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    final code = _code.text.trim();
    if (!RegExp(r'^\d{6}$').hasMatch(code)) {
      setState(() => _error = 'الرمز ستة أرقام.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final app = AppScope.read(context);
    try {
      final factors = await app.verifiedFactors();
      if (factors.isEmpty) {
        widget.onDone();
        return;
      }
      await app.verifyTotp(factors.first.id, code);
      widget.onDone();
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
    return AuthFrame(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Icon(Icons.phonelink_lock_outlined, size: 44, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 12),
          Text('رمز التحقق', textAlign: TextAlign.center, style: t.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text('افتح تطبيق المصادقة على هاتفك واكتب الرمز المكوّن من ستة أرقام.',
              textAlign: TextAlign.center, style: TextStyle(color: sem.muted)),
          const SizedBox(height: 20),
          _CodeField(controller: _code, onSubmitted: _verify),
          if (_error != null) ...[const SizedBox(height: 10), InfoBanner(text: _error!, level: 'critical')],
          const SizedBox(height: 18),
          FilledButton(
            onPressed: _busy ? null : _verify,
            child: _busy ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('تحقق'),
          ),
          const SizedBox(height: 8),
          TextButton(onPressed: () => Supabase.instance.client.auth.signOut(), child: const Text('تسجيل الخروج')),
        ],
      ),
    );
  }
}

class _CodeField extends StatelessWidget {
  const _CodeField({required this.controller, required this.onSubmitted});

  final TextEditingController controller;
  final VoidCallback onSubmitted;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      autofocus: true,
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
      keyboardType: TextInputType.number,
      maxLength: 6,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      autofillHints: const [AutofillHints.oneTimeCode],
      style: const TextStyle(fontSize: 26, letterSpacing: 10, fontWeight: FontWeight.w700),
      onSubmitted: (_) => onSubmitted(),
      decoration: const InputDecoration(counterText: '', hintText: '000000'),
    );
  }
}

/// تفعيل التحقق بخطوتين: رمز QR لتطبيق المصادقة ثم أول رمز.
class MfaEnrollScreen extends StatelessWidget {
  const MfaEnrollScreen({super.key, required this.required, required this.onDone});

  final bool required;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    return AuthFrame(child: MfaEnrollPanel(required: required, onDone: onDone));
  }
}

class MfaEnrollPanel extends StatefulWidget {
  const MfaEnrollPanel({super.key, required this.required, required this.onDone, this.onCancel});

  final bool required;
  final VoidCallback onDone;
  final VoidCallback? onCancel;

  @override
  State<MfaEnrollPanel> createState() => _MfaEnrollPanelState();
}

class _MfaEnrollPanelState extends State<MfaEnrollPanel> {
  final _code = TextEditingController();
  String? _factorId;
  String? _uri;
  String? _secret;
  bool _busy = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final res = await AppScope.read(context).enrollTotp();
      if (!mounted) return;
      setState(() {
        _factorId = res.id;
        _uri = res.totp?.uri;
        _secret = res.totp?.secret;
      });
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _verify() async {
    final id = _factorId;
    if (id == null) return;
    if (!RegExp(r'^\d{6}$').hasMatch(_code.text.trim())) {
      setState(() => _error = 'الرمز ستة أرقام.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await AppScope.read(context).verifyTotp(id, _code.text);
      widget.onDone();
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('تفعيل التحقق بخطوتين', style: t.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        Text(
          widget.required
              ? 'حماية إضافية مطلوبة لحسابك: بعد كلمة المرور يُطلب رمز من تطبيق المصادقة على هاتفك.'
              : 'بعد كلمة المرور يُطلب رمز من تطبيق المصادقة على هاتفك، فلا يدخل أحد حسابك ولو عرف كلمة المرور.',
          style: TextStyle(color: sem.muted),
        ),
        const SizedBox(height: 16),
        _Step(n: 1, text: 'ثبّت تطبيق مصادقة على هاتفك، مثل Google Authenticator أو Microsoft Authenticator.'),
        _Step(n: 2, text: 'من التطبيق اختر «إضافة حساب» وامسح الرمز التالي، أو اكتب المفتاح يدوياً.'),
        const SizedBox(height: 10),
        if (_uri != null)
          Center(
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: sem.rule)),
              child: QrImageView(data: _uri!, size: 190, backgroundColor: Colors.white),
            ),
          )
        else if (_busy)
          const Padding(padding: EdgeInsets.all(30), child: Center(child: CircularProgressIndicator())),
        if (_secret != null) ...[
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: SelectableText(_secret!,
                    textDirection: TextDirection.ltr,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.w700, letterSpacing: 1.2)),
              ),
              IconButton(
                tooltip: 'نسخ المفتاح',
                icon: const Icon(Icons.copy_rounded),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: _secret!));
                  showToast(context, 'نُسخ المفتاح');
                },
              ),
            ],
          ),
        ],
        const SizedBox(height: 10),
        _Step(n: 3, text: 'اكتب الرمز المكوّن من ستة أرقام الظاهر في التطبيق.'),
        const SizedBox(height: 8),
        _CodeField(controller: _code, onSubmitted: _verify),
        if (_error != null) ...[
          const SizedBox(height: 10),
          InfoBanner(text: _error!, level: 'critical', action: _factorId == null ? TextButton(onPressed: _start, child: const Text('إعادة')) : null),
        ],
        const SizedBox(height: 16),
        FilledButton(
          onPressed: _busy || _factorId == null ? null : _verify,
          child: _busy ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('تفعيل'),
        ),
        const SizedBox(height: 8),
        if (widget.onCancel != null)
          TextButton(onPressed: widget.onCancel, child: const Text('إلغاء'))
        else
          TextButton(onPressed: () => Supabase.instance.client.auth.signOut(), child: const Text('تسجيل الخروج')),
      ],
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({required this.n, required this.text});

  final int n;
  final String text;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 24,
            height: 24,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: cs.primaryContainer, shape: BoxShape.circle),
            child: Text('$n', style: TextStyle(color: cs.onPrimaryContainer, fontWeight: FontWeight.w700, fontSize: 12)),
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(text)),
        ],
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
    return AuthFrame(
      child: Column(
        children: [
          const EmptyState(
            icon: Icons.hourglass_top_outlined,
            title: 'حسابك بانتظار التفعيل',
            message: 'أُبلغ مدير المكتب بطلبك. ستتمكن من الدخول بعد أن يفعّل حسابك ويحدد دورك.',
          ),
          if (profile != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: sem.surface2, borderRadius: BorderRadius.circular(14), border: Border.all(color: sem.rule)),
              child: Row(
                children: [
                  InitialsAvatar(name: profile!.displayName),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(profile!.displayName, style: const TextStyle(fontWeight: FontWeight.w700)),
                        Text(profile!.email, textDirection: TextDirection.ltr, style: TextStyle(color: sem.muted)),
                      ],
                    ),
                  ),
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
    );
  }
}

/// الحساب مقفل الدخول مؤقتاً (أو حتى يُفك) بقرار مدير المكتب أو CISO.
class LockedScreen extends StatefulWidget {
  const LockedScreen({super.key, required this.profile, required this.onRefresh});

  final Profile? profile;
  final VoidCallback onRefresh;

  @override
  State<LockedScreen> createState() => _LockedScreenState();
}

class _LockedScreenState extends State<LockedScreen> {
  Map<String, dynamic> _lock = const {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final l = await AppScope.read(context).myLock();
      if (mounted) setState(() => _lock = l);
    });
  }

  @override
  Widget build(BuildContext context) {
    final sem = Sem.of(context);
    final until = DateTime.tryParse((_lock['until'] ?? '').toString())?.toLocal() ??
        (widget.profile?.lockedUntil?.year == 9999 ? null : widget.profile?.lockedUntil?.toLocal());
    final reason = (_lock['reason'] ?? widget.profile?.lockReason ?? '').toString();
    return AuthFrame(
      child: Column(
        children: [
          EmptyState(
            icon: Icons.lock_clock_outlined,
            title: 'الدخول إلى حسابك مقفل',
            message: until == null
                ? 'أُقفل الدخول إلى حسابك حتى يفكّه مدير المكتب أو مدير الأمن.'
                : 'أُقفل الدخول مؤقتاً حتى ${dayText(until)} الساعة ${until.hour.toString().padLeft(2, '0')}:${until.minute.toString().padLeft(2, '0')}.',
          ),
          if (reason.trim().isNotEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: sem.dangerSoft, borderRadius: BorderRadius.circular(14)),
              child: Text('السبب: $reason', style: TextStyle(color: sem.danger, fontWeight: FontWeight.w600)),
            ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(child: FilledButton.icon(onPressed: widget.onRefresh, icon: const Icon(Icons.refresh), label: const Text('تحقق مجدداً'))),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => Supabase.instance.client.auth.signOut(scope: SignOutScope.local),
                  icon: const Icon(Icons.logout),
                  label: const Text('تسجيل الخروج'),
                ),
              ),
            ],
          ),
        ],
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
