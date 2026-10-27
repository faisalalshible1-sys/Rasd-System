import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app_state.dart';
import '../../models.dart';
import '../../ui/theme.dart';
import '../../ui/widgets.dart';
import '../account.dart';
import 'control_panel.dart';
import 'user_details.dart';

/// مركز الأمان: درجة الأمان، السياسات، الجلسات، التحقق بخطوتين، سجل الدخول.
class SecuritySection extends StatefulWidget {
  const SecuritySection({super.key});

  @override
  State<SecuritySection> createState() => _SecuritySectionState();
}

class _SecuritySectionState extends State<SecuritySection> {
  Map<String, dynamic>? _overview;
  List<Map<String, dynamic>> _sessions = const [];
  List<Map<String, dynamic>> _users = const [];
  List<Map<String, dynamic>> _logins = const [];
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final app = AppScope.read(context);
    try {
      final r = await Future.wait([
        app.securityOverview(),
        app.listSessions(),
        app.securityUsers(),
        app.loginHistory(limit: 150),
      ]);
      if (!mounted) return;
      setState(() {
        _overview = r[0] as Map<String, dynamic>;
        _sessions = r[1] as List<Map<String, dynamic>>;
        _users = r[2] as List<Map<String, dynamic>>;
        _logins = r[3] as List<Map<String, dynamic>>;
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    }
  }

  Future<void> _set(String key, Object value, String ok) async {
    setState(() => _busy = true);
    await runAction(context, () => AppScope.read(context).setSetting(key, value), success: ok);
    await _load();
    if (mounted) setState(() => _busy = false);
  }

  List<(bool, String, String, int)> _checks(AppState app) {
    final o = _overview ?? const {};
    final active = (o['users_active'] as num?)?.toInt() ?? 0;
    final mfaUsers = (o['users_mfa'] as num?)?.toInt() ?? 0;
    final noRls = (o['tables_without_rls'] as List?)?.length ?? 0;
    return [
      (o['director_mfa'] == true, app.isDirector ? 'التحقق بخطوتين مفعّل لحسابك' : 'التحقق بخطوتين مفعّل لحساب مدير المكتب',
          app.isDirector ? 'فعّله من «حسابي والأمان».' : 'لم يفعّله مدير المكتب بعد.', 25),
      (app.settings.requireMfaDirector, 'قاعدة البيانات تفرض التحقق على حساب المدير', 'يُشغَّل «فرض التحقق على مدير المكتب» من السياسات.', 15),
      (noRls == 0, 'كل الجداول محمية بسياسات الوصول', '$noRls جدول بلا حماية.', 20),
      (active > 0 && mfaUsers * 2 >= active, 'نصف المستخدمين على الأقل فعّلوا التحقق بخطوتين', '$mfaUsers من $active فقط.', 15),
      (app.idleMinutes > 0 && app.idleMinutes <= 60, 'القفل التلقائي بعد الخمول مفعّل', 'اضبطه على 60 دقيقة أو أقل.', 10),
      (((o['users_pending'] as num?)?.toInt() ?? 0) == 0, 'لا حسابات معلّقة دون مراجعة', 'راجع الحسابات الجديدة في «المستخدمون والأدوار».', 5),
      (!app.settings.signupsOpen || ((o['users_pending'] as num?)?.toInt() ?? 0) == 0, 'التسجيل الجديد مضبوط', 'أغلق التسجيل حين لا تنتظر موظفين جدداً.', 10),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final sem = Sem.of(context);
    final t = Theme.of(context).textTheme;
    if (_error != null) {
      return EmptyState(icon: Icons.gpp_bad_outlined, title: 'تعذّر تحميل مركز الأمان', message: _error, action: FilledButton(onPressed: _load, child: const Text('إعادة المحاولة')));
    }
    if (_overview == null) return const Center(child: CircularProgressIndicator());
    final checks = _checks(app);
    final score = checks.fold<int>(0, (a, c) => a + (c.$1 ? c.$4 : 0));
    final scoreColor = score >= 80 ? sem.ok : (score >= 55 ? sem.wip : sem.danger);
    final directorMfa = _overview!['director_mfa'] == true;
    final myMfa = _overview!['my_mfa'] == true || (app.isDirector && directorMfa);
    final readOnly = !app.isDirector;

    return PageBody(
      onRefresh: () async {
        await app.loadAll();
        await _load();
      },
      children: [
        PageHeader(
          icon: Icons.shield_outlined,
          title: 'مركز الأمان',
          subtitle: readOnly
              ? 'اطلاع كامل على حالة الأمان والجلسات وسجل الدخول. الإجراءات من صلاحية مدير المكتب وحده.'
              : 'حماية الحسابات والجلسات وسياسات الوصول. كل إجراء هنا يُسجَّل في سجل التدقيق.',
          actions: [
            if (_busy) const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)),
            OutlinedButton.icon(onPressed: _load, icon: const Icon(Icons.refresh), label: const Text('تحديث')),
          ],
        ),
        SectionCard(
          title: 'درجة الأمان',
          icon: Icons.health_and_safety_outlined,
          child: LayoutBuilder(builder: (context, c) {
            final gauge = SizedBox(
              width: 130,
              height: 130,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox(
                    width: 130,
                    height: 130,
                    child: CircularProgressIndicator(value: score / 100, strokeWidth: 11, color: scoreColor, backgroundColor: sem.todoSoft),
                  ),
                  Column(mainAxisSize: MainAxisSize.min, children: [
                    Text('$score', style: t.displaySmall?.copyWith(fontWeight: FontWeight.w700, color: scoreColor)),
                    Text('من 100', style: TextStyle(color: sem.muted, fontSize: 12)),
                  ]),
                ],
              ),
            );
            final list = Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final ch in checks)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(ch.$1 ? Icons.check_circle_rounded : Icons.error_outline_rounded, size: 20, color: ch.$1 ? sem.ok : sem.wip),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(ch.$2, style: const TextStyle(fontWeight: FontWeight.w600)),
                              if (!ch.$1) Text(ch.$3, style: TextStyle(color: sem.muted, fontSize: 12.5)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            );
            return c.maxWidth >= 620
                ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [gauge, const SizedBox(width: 24), Expanded(child: list)])
                : Column(children: [gauge, const SizedBox(height: 16), list]);
          }),
        ),
        const SizedBox(height: 16),
        SectionCard(
          title: 'السياسات',
          icon: Icons.policy_outlined,
          subtitle: readOnly ? 'للاطلاع: يضبطها مدير المكتب.' : null,
          child: Column(
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                secondary: const Icon(Icons.admin_panel_settings_outlined),
                title: const Text('فرض التحقق بخطوتين على مدير المكتب'),
                subtitle: Text(directorMfa
                    ? 'لا تُقبل جلسة المدير في قاعدة البيانات إلا بعد رمز التحقق.'
                    : 'فعّل التحقق لحسابك أولاً من «حسابي والأمان».'),
                value: app.settings.requireMfaDirector,
                onChanged: readOnly || _busy || !directorMfa ? null : (v) => _set('security.require_mfa_director', v, v ? 'فُرض التحقق على حسابك' : 'أُلغي الفرض'),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                secondary: const Icon(Icons.groups_2_outlined),
                title: const Text('فرض التحقق بخطوتين على كل المستخدمين'),
                subtitle: const Text('من لم يفعّله يُطلب منه تفعيله عند الدخول، ولا يرى شيئاً قبل ذلك.'),
                value: app.settings.requireMfaAll,
                onChanged: readOnly || _busy || !directorMfa ? null : (v) => _set('security.require_mfa_all', v, v ? 'فُرض التحقق على الجميع' : 'أصبح التحقق اختيارياً'),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                secondary: const Icon(Icons.person_add_disabled_outlined),
                title: const Text('السماح بإنشاء حسابات جديدة'),
                subtitle: const Text('عند الإغلاق يُرفض أي تسجيل جديد من شاشة الدخول.'),
                value: app.settings.signupsOpen,
                onChanged: readOnly || _busy ? null : (v) => _set('security.signups_open', v, v ? 'فُتح التسجيل' : 'أُغلق التسجيل'),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                secondary: Icon(Icons.ac_unit_rounded, color: app.settings.frozen ? sem.danger : null),
                title: const Text('تجميد المنظومة (طوارئ)'),
                subtitle: const Text('يصبح كل شيء قراءة فقط لغيرك فوراً، حتى تلغي التجميد.'),
                value: app.settings.frozen,
                onChanged: readOnly || _busy
                    ? null
                    : (v) async {
                        if (v) {
                          final ok = await confirmDialog(context,
                              title: 'تجميد المنظومة؟',
                              message: 'لن يستطيع أي موظف تعديل أي شيء حتى تلغي التجميد.',
                              confirmLabel: 'تجميد',
                              danger: true);
                          if (!ok) return;
                        }
                        await _set('security.freeze', v, v ? 'جُمّدت المنظومة' : 'أُلغي التجميد');
                      },
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  const Icon(Icons.timer_outlined),
                  const SizedBox(width: 16),
                  const Expanded(child: Text('القفل التلقائي بعد الخمول', style: TextStyle(fontWeight: FontWeight.w600))),
                  DropdownButton<int>(
                    value: const [0, 5, 10, 15, 30, 60, 120, 240].contains(app.idleMinutes) ? app.idleMinutes : 30,
                    items: [
                      for (final m in const [0, 5, 10, 15, 30, 60, 120, 240])
                        DropdownMenuItem(value: m, child: Text(m == 0 ? 'متوقف' : '$m دقيقة')),
                    ],
                    onChanged: readOnly || _busy ? null : (m) => m == null ? null : _set('security.idle_minutes', m, 'حُفظ القفل التلقائي'),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        SectionCard(
          title: 'حسابك',
          icon: Icons.phonelink_lock_outlined,
          trailing: ToneBadge(myMfa ? 'التحقق مفعّل' : 'التحقق غير مفعّل', color: myMfa ? sem.ok : sem.danger),
          child: Row(
            children: [
              Expanded(child: Text('الجلسة الحالية: ${_overview!['current_aal'] == 'aal2' ? 'بعد رمز التحقق' : 'بكلمة المرور فقط'}')),
              FilledButton.tonal(onPressed: () => openAccount(context), child: const Text('حسابي والأمان')),
            ],
          ),
        ),
        const SizedBox(height: 16),
        SectionCard(
          title: 'الجلسات المفتوحة',
          icon: Icons.devices_rounded,
          subtitle: 'كل جهاز مسجّل الدخول الآن. إنهاء الجلسة يُخرج صاحبها من ذلك الجهاز.',
          child: _sessions.isEmpty
              ? Text('لا تتوفر بيانات الجلسات.', style: TextStyle(color: sem.muted))
              : Column(
                  children: [
                    for (final s in _sessions)
                      SettingRow(
                        icon: _deviceIcon(s['user_agent']?.toString() ?? ''),
                        title: '${s['name'] ?? ''}${s['current'] == true ? ' (هذا الجهاز)' : ''}',
                        subtitle: [
                          _device(s['user_agent']?.toString() ?? ''),
                          if ((s['ip'] ?? '').toString().isNotEmpty) 'IP ${s['ip']}',
                          'آخر نشاط ${fmtDate(DateTime.tryParse((s['updated_at'] ?? s['created_at'] ?? '').toString()))}',
                          if (s['aal'] == 'aal2') 'بعد رمز التحقق',
                        ].join(' · '),
                        trailing: s['current'] == true || readOnly
                            ? null
                            : IconButton(
                                tooltip: 'إنهاء الجلسة',
                                icon: Icon(Icons.logout_rounded, color: sem.danger),
                                onPressed: () async {
                                  await runAction(context, () => app.revokeSession(s['id'].toString()), success: 'أُنهيت الجلسة');
                                  await _load();
                                },
                              ),
                      ),
                  ],
                ),
        ),
        const SizedBox(height: 16),
        SectionCard(
          title: 'المستخدمون والتحقق بخطوتين',
          icon: Icons.verified_user_outlined,
          child: Column(
            children: [
              for (final u in _users.where((u) => u['active'] == true))
                SettingRow(
                  icon: u['mfa'] == true ? Icons.verified_user_rounded : Icons.shield_outlined,
                  title: (u['full_name'] ?? '').toString().isEmpty ? (u['email'] ?? '').toString() : u['full_name'].toString(),
                  subtitle: [
                    parseRole(u['role'])?.label ?? '',
                    u['mfa'] == true ? 'التحقق مفعّل' : 'التحقق غير مفعّل',
                    'آخر دخول ${u['last_sign_in_at'] == null ? '—' : fmtDate(DateTime.tryParse(u['last_sign_in_at'].toString()))}',
                  ].join(' · '),
                  onTap: () => openUserDetails(context, u['id'].toString()),
                  trailing: u['id'] == app.me?.id || readOnly
                      ? null
                      : PopupMenuButton<String>(
                          tooltip: 'إجراءات',
                          onSelected: (v) async {
                            final id = u['id'].toString();
                            if (v == 'signout') {
                              await runAction(context, () async {
                                final n = await app.revokeUserSessions(id);
                                if (context.mounted) showToast(context, 'أُنهيت $n جلسة');
                              });
                            } else if (v == 'mfa') {
                              final ok = await confirmDialog(context,
                                  title: 'إلغاء التحقق بخطوتين؟', message: 'عند فقدان المستخدم هاتفه.', confirmLabel: 'إلغاء التحقق', danger: true);
                              if (!ok || !context.mounted) return;
                              await runAction(context, () => app.resetUserMfa(id), success: 'أُلغي التحقق بخطوتين');
                            }
                            await _load();
                          },
                          itemBuilder: (_) => [
                            const PopupMenuItem(value: 'signout', child: Text('إخراج من كل الأجهزة')),
                            if (u['mfa'] == true) const PopupMenuItem(value: 'mfa', child: Text('إلغاء التحقق بخطوتين')),
                          ],
                        ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        SectionCard(
          title: 'سجل الدخول',
          icon: Icons.login_rounded,
          subtitle: 'آخر عمليات الدخول والخروج وتغيير كلمات المرور',
          child: _logins.isEmpty
              ? Text('لا تتوفر سجلات دخول (قد يكون تسجيلها في قاعدة البيانات متوقفاً في إعدادات Supabase).', style: TextStyle(color: sem.muted))
              : Column(
                  children: [
                    for (final l in _logins.take(60))
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Row(
                          children: [
                            Icon(_loginIcon(l['action']?.toString() ?? ''), size: 19, color: sem.muted),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                '${(l['name'] ?? l['email'] ?? '').toString()} · ${_loginLabel(l['action']?.toString() ?? '')}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            Text(fmtDate(DateTime.tryParse((l['at'] ?? '').toString())), style: TextStyle(color: sem.muted, fontSize: 12)),
                          ],
                        ),
                      ),
                  ],
                ),
        ),
        const SizedBox(height: 16),
        SectionCard(
          title: 'إعدادات يُنصح بضبطها في Supabase',
          icon: Icons.checklist_rounded,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final tip in const [
                'Authentication ← Providers ← Email: فعّل «Prevent use of leaked passwords» وحدد طول كلمة المرور 10 أحرف على الأقل.',
                'Authentication ← Rate Limits: أبقِ حدود محاولات الدخول وإرسال البريد منخفضة.',
                'Authentication ← Sessions: حدّد مدة قصوى للجلسة إن أردت خروجاً إجبارياً دورياً.',
                'Project Settings ← API: لا تشارك المفتاح السري (secret / service_role) مع أحد، وغيّره فوراً إن تسرّب.',
              ])
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Icon(Icons.arrow_left_rounded, color: sem.muted),
                    Expanded(child: Text(tip)),
                  ]),
                ),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton.icon(
                  onPressed: () => launchUrl(Uri.parse('https://supabase.com/dashboard'), mode: LaunchMode.externalApplication),
                  icon: const Icon(Icons.open_in_new_rounded),
                  label: const Text('فتح لوحة Supabase'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  static String _device(String ua) {
    final u = ua.toLowerCase();
    if (u.isEmpty) return 'جهاز غير معروف';
    if (u.contains('android')) return 'أندرويد';
    if (u.contains('iphone') || u.contains('ipad') || u.contains('ios')) return 'آيفون';
    if (u.contains('windows')) return 'ويندوز';
    if (u.contains('mac')) return 'ماك';
    if (u.contains('dart')) return 'التطبيق';
    return 'متصفح';
  }

  static IconData _deviceIcon(String ua) {
    final u = ua.toLowerCase();
    if (u.contains('android') || u.contains('iphone')) return Icons.smartphone_rounded;
    if (u.contains('windows') || u.contains('mac')) return Icons.computer_rounded;
    return Icons.devices_other_rounded;
  }

  static String _loginLabel(String a) => switch (a) {
        'login' => 'دخول',
        'logout' => 'خروج',
        'user_signedup' => 'إنشاء حساب',
        'user_recovery_requested' => 'طلب استعادة كلمة المرور',
        'user_updated_password' => 'تغيير كلمة المرور',
        'factor_in_progress' => 'بدء تفعيل التحقق بخطوتين',
        'factor_unenrolled' => 'إزالة التحقق بخطوتين',
        'mfa_code_login' => 'دخول برمز التحقق',
        'token_revoked' => 'إنهاء جلسة',
        'user_deleted' => 'حذف حساب',
        _ => a,
      };

  static IconData _loginIcon(String a) => switch (a) {
        'login' || 'mfa_code_login' => Icons.login_rounded,
        'logout' || 'token_revoked' => Icons.logout_rounded,
        'user_updated_password' || 'user_recovery_requested' => Icons.password_rounded,
        _ => Icons.shield_outlined,
      };
}

/// اسم نوع الجهاز من بصمة المتصفح أو التطبيق.
String deviceName(String ua) => _SecuritySectionState._device(ua);

IconData deviceIcon(String ua) => _SecuritySectionState._deviceIcon(ua);

/// وصف عملية من سجل الدخول.
String loginActionLabel(String a) => _SecuritySectionState._loginLabel(a);

IconData loginActionIcon(String a) => _SecuritySectionState._loginIcon(a);
