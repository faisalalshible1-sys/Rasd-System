import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../app_state.dart';
import '../config.dart';
import '../models.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';
import 'auth.dart';
import 'home_shell.dart';

Future<void> openAccount(BuildContext context) =>
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const AccountPage()));

/// حسابي: البيانات الشخصية، التحقق بخطوتين، الأجهزة، المظهر.
class AccountPage extends StatefulWidget {
  const AccountPage({super.key});

  @override
  State<AccountPage> createState() => _AccountPageState();
}

class _AccountPageState extends State<AccountPage> {
  List<Factor>? _factors;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadFactors());
  }

  Future<void> _loadFactors() async {
    try {
      final f = await AppScope.read(context).verifiedFactors();
      if (mounted) setState(() => _factors = f);
    } catch (_) {
      if (mounted) setState(() => _factors = const []);
    }
  }

  Future<void> _editName(AppState app) async {
    final name = await textInputDialog(context,
        title: 'تعديل الاسم', label: 'الاسم الكامل', confirmLabel: 'حفظ', required: true, initial: app.me?.fullName, multiline: false);
    if (name == null) return;
    try {
      await app.updateMyName(name);
      if (mounted) showToast(context, 'حُفظ الاسم');
    } catch (e) {
      if (mounted) showToast(context, friendlyError(e), error: true);
    }
  }

  Future<void> _editEmail(AppState app) async {
    final me = app.me;
    if (me == null) return;
    final email = await textInputDialog(context,
        title: 'تغيير بريد الدخول',
        message: 'سيُستخدم البريد الجديد للدخول من الآن. كلمة المرور لا تتغير.',
        label: 'البريد الجديد',
        confirmLabel: 'حفظ',
        required: true,
        initial: me.email,
        multiline: false,
        keyboardType: TextInputType.emailAddress,
        textDirection: TextDirection.ltr);
    if (email == null) return;
    try {
      await app.setUserEmail(me.id, email);
      if (mounted) showToast(context, 'تغيّر بريد الدخول. استخدمه عند الدخول القادم.');
    } catch (e) {
      if (mounted) showToast(context, friendlyError(e), error: true);
    }
  }

  Future<void> _changePassword() async {
    final p1 = TextEditingController();
    final p2 = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        String? error;
        return StatefulBuilder(
          builder: (ctx, setLocal) => AlertDialog(
            title: const Text('تغيير كلمة المرور'),
            content: SizedBox(
              width: 400,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(controller: p1, obscureText: true, textDirection: TextDirection.ltr, decoration: fieldDeco('كلمة المرور الجديدة', helper: '10 أحرف على الأقل، وفيها حروف وأرقام')),
                  const SizedBox(height: 12),
                  TextField(controller: p2, obscureText: true, textDirection: TextDirection.ltr, decoration: fieldDeco('تأكيدها', error: error)),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('إلغاء')),
              FilledButton(
                onPressed: () {
                  final p = p1.text;
                  if (p.length < 10 || !RegExp(r'\d').hasMatch(p) || !RegExp(r'[A-Za-z؀-ۿ]').hasMatch(p)) {
                    setLocal(() => error = 'كلمة المرور 10 أحرف على الأقل، وفيها حروف وأرقام.');
                    return;
                  }
                  if (p != p2.text) {
                    setLocal(() => error = 'كلمتا المرور غير متطابقتين.');
                    return;
                  }
                  Navigator.of(ctx).pop(true);
                },
                child: const Text('حفظ'),
              ),
            ],
          ),
        );
      },
    );
    if (ok != true) return;
    try {
      await Supabase.instance.client.auth.updateUser(UserAttributes(password: p1.text));
      if (mounted) showToast(context, 'تغيّرت كلمة المرور');
    } catch (e) {
      if (mounted) showToast(context, friendlyError(e), error: true);
    }
  }

  Future<void> _enrollMfa() async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(22),
            child: MfaEnrollPanel(
              required: false,
              onDone: () {
                Navigator.of(ctx).pop();
                showToast(context, 'فُعّل التحقق بخطوتين لحسابك');
              },
              onCancel: () => Navigator.of(ctx).pop(),
            ),
          ),
        ),
      ),
    );
    await _loadFactors();
  }

  Future<void> _disableMfa(AppState app, Factor f) async {
    if (app.mfaRequiredForMe && (_factors?.length ?? 0) <= 1) {
      showToast(context, 'التحقق بخطوتين إلزامي لحسابك؛ أضف هاتفاً آخر قبل إزالة هذا.', error: true);
      return;
    }
    final ok = await confirmDialog(context,
        title: 'إزالة هذا الجهاز؟', message: 'لن يُطلب رمز منه بعد الآن.', confirmLabel: 'إزالة', danger: true);
    if (!ok) return;
    setState(() => _busy = true);
    try {
      await app.unenrollFactor(f.id);
      if (mounted) showToast(context, 'أُزيل الجهاز');
    } catch (e) {
      if (mounted) showToast(context, friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
      await _loadFactors();
    }
  }

  Future<void> _signOutOthers(AppState app) async {
    final ok = await confirmDialog(context,
        title: 'الخروج من الأجهزة الأخرى؟',
        message: 'يبقى هذا الجهاز متصلاً، ويُطلب الدخول من جديد على كل جهاز آخر.',
        confirmLabel: 'تسجيل الخروج منها');
    if (!ok) return;
    try {
      await app.signOutOtherDevices();
      if (mounted) showToast(context, 'سُجّل الخروج من كل الأجهزة الأخرى');
    } catch (e) {
      if (mounted) showToast(context, friendlyError(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final sem = Sem.of(context);
    final me = app.me;
    final factors = _factors;
    return Scaffold(
      appBar: brandAppBar(context, title: const Text('حسابي والأمان')),
      body: PageBody(
        maxWidth: 760,
        children: [
          SectionCard(
            title: 'البيانات الشخصية',
            icon: Icons.person_outline_rounded,
            child: Column(
              children: [
                Row(
                  children: [
                    InitialsAvatar(name: me?.displayName ?? '', size: 56),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(me?.displayName ?? '', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                          Text(roleText(app, me), style: TextStyle(color: sem.muted)),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SettingRow(
                  icon: Icons.badge_outlined,
                  title: 'الاسم',
                  subtitle: me?.fullName.isEmpty ?? true ? '—' : me!.fullName,
                  trailing: const Icon(Icons.edit_outlined, size: 20),
                  onTap: () => _editName(app),
                ),
                SettingRow(
                  icon: Icons.alternate_email,
                  title: 'بريد الدخول',
                  subtitle: me?.email ?? '',
                  trailing: app.isDirector ? const Icon(Icons.edit_outlined, size: 20) : null,
                  onTap: app.isDirector ? () => _editEmail(app) : () => showToast(context, 'يغيّر مدير المكتب بريد الدخول من لوحة التحكم.'),
                ),
                SettingRow(
                  icon: Icons.password_rounded,
                  title: 'كلمة المرور',
                  subtitle: 'غيّرها دورياً واختر كلمة طويلة',
                  trailing: const Icon(Icons.edit_outlined, size: 20),
                  onTap: _changePassword,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          SectionCard(
            title: 'التحقق بخطوتين',
            icon: Icons.phonelink_lock_outlined,
            subtitle: app.mfaRequiredForMe ? 'إلزامي لحسابك' : 'يحمي حسابك ولو عرف أحد كلمة المرور',
            trailing: factors == null
                ? null
                : ToneBadge(factors.isEmpty ? 'غير مفعّل' : 'مفعّل',
                    color: factors.isEmpty ? sem.wip : sem.ok, icon: factors.isEmpty ? Icons.shield_outlined : Icons.verified_user),
            child: factors == null
                ? const Padding(padding: EdgeInsets.all(8), child: Center(child: CircularProgressIndicator(strokeWidth: 2)))
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final f in factors)
                        SettingRow(
                          icon: Icons.smartphone_rounded,
                          title: 'تطبيق المصادقة',
                          subtitle: 'أُضيف ${fmtDate(f.createdAt)}',
                          trailing: IconButton(
                            tooltip: 'إزالة',
                            onPressed: _busy ? null : () => _disableMfa(app, f),
                            icon: Icon(Icons.delete_outline, color: sem.danger),
                          ),
                        ),
                      const SizedBox(height: 8),
                      Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: FilledButton.tonalIcon(
                          onPressed: _enrollMfa,
                          icon: const Icon(Icons.add_moderator_outlined),
                          label: Text(factors.isEmpty ? 'تفعيل التحقق بخطوتين' : 'إضافة هاتف احتياطي'),
                        ),
                      ),
                    ],
                  ),
          ),
          const SizedBox(height: 16),
          SectionCard(
            title: 'الأجهزة والجلسات',
            icon: Icons.devices_other_rounded,
            child: Column(
              children: [
                SettingRow(
                  icon: Icons.logout_rounded,
                  title: 'تسجيل الخروج من الأجهزة الأخرى',
                  subtitle: 'إن نسيت جلسة مفتوحة على جهاز آخر',
                  onTap: () => _signOutOthers(app),
                ),
                if (app.idleMinutes > 0)
                  SettingRow(
                    icon: Icons.timer_outlined,
                    title: 'القفل التلقائي',
                    subtitle: 'يُسجَّل خروجك بعد ${app.idleMinutes} دقيقة دون استخدام',
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          SectionCard(
            title: 'المظهر',
            icon: Icons.palette_outlined,
            child: SegmentedButton<ThemeMode>(
              segments: const [
                ButtonSegment(value: ThemeMode.system, label: Text('حسب الجهاز'), icon: Icon(Icons.brightness_auto_outlined)),
                ButtonSegment(value: ThemeMode.light, label: Text('فاتح'), icon: Icon(Icons.light_mode_outlined)),
                ButtonSegment(value: ThemeMode.dark, label: Text('داكن'), icon: Icon(Icons.dark_mode_outlined)),
              ],
              selected: {app.themeMode},
              showSelectedIcon: false,
              onSelectionChanged: (s) => app.setThemeMode(s.first),
            ),
          ),
          const SizedBox(height: 20),
          OutlinedButton.icon(
            onPressed: () async {
              Navigator.of(context).popUntil((r) => r.isFirst);
              await Supabase.instance.client.auth.signOut();
            },
            icon: Icon(Icons.logout, color: sem.danger),
            label: Text('تسجيل الخروج', style: TextStyle(color: sem.danger)),
          ),
          const SizedBox(height: 14),
          Center(child: Text('الإصدار ${AppConfig.appVersion} · ${app.orgName}', style: TextStyle(color: sem.muted, fontSize: 12))),
        ],
      ),
    );
  }
}

/// اسم دور المستخدم كما يُعرض.
String profileRoleText(AppState app, Profile? p) => roleText(app, p);
