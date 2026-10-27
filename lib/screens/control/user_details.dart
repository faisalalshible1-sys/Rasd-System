import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app_state.dart';
import '../../models.dart';
import '../../ui/audit_text.dart';
import '../../ui/theme.dart';
import '../../ui/widgets.dart';
import 'control_panel.dart';
import 'security.dart';
import 'users.dart';

/// يفتح صفحة البيانات الكاملة لمستخدم (لمدير المكتب ومدقق الأمن).
Future<void> openUserDetails(BuildContext context, String userId) =>
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => UserDetailsPage(userId: userId)));

/// البيانات الكاملة لمستخدم: الحساب، والأمان، والأجهزة، وسجل الدخول، والنشاط، وتاريخ الحساب.
/// المدير يدير الحساب من هنا (الصلاحيات، الإخراج من الأجهزة، إلغاء التحقق، الحذف)، ومدقق الأمن يطّلع فقط.
class UserDetailsPage extends StatefulWidget {
  const UserDetailsPage({super.key, required this.userId});

  final String userId;

  @override
  State<UserDetailsPage> createState() => _UserDetailsPageState();
}

class _UserDetailsPageState extends State<UserDetailsPage> {
  Map<String, dynamic>? _d;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final app = AppScope.read(context);
    try {
      final d = await app.userDetails(widget.userId);
      if (!mounted) return;
      setState(() {
        _d = d;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      final msg = friendlyError(e);
      setState(() => _error = e.toString().contains('user_details')
          ? 'هذه الصفحة تحتاج تحديث قاعدة البيانات: شغّل الملفين 20261027000007 و20261027000008 في SQL Editor على Supabase.'
          : msg);
    }
  }

  static List<Map<String, dynamic>> _list(Object? v) =>
      v is List ? v.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList() : const [];

  static Map<String, dynamic> _map(Object? v) => v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};

  static DateTime? _dt(Object? v) => v == null ? null : DateTime.tryParse(v.toString());

  static String _when(Object? v, {String empty = '—'}) {
    final d = _dt(v);
    return d == null ? empty : fmtDate(d);
  }

  static String _provider(String p) => switch (p) {
        'email' => 'البريد وكلمة المرور',
        'google' => 'Google',
        'github' => 'GitHub',
        'apple' => 'Apple',
        'azure' => 'Microsoft',
        'phone' => 'رقم الهاتف',
        _ => p,
      };

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final d = _d;
    return Scaffold(
      appBar: AppBar(
        title: const Text('بيانات المستخدم'),
        actions: [IconButton(tooltip: 'تحديث', onPressed: _load, icon: const Icon(Icons.refresh_rounded))],
      ),
      body: _error != null
          ? EmptyState(
              icon: Icons.person_off_outlined,
              title: 'تعذّر تحميل بيانات المستخدم',
              message: _error,
              action: FilledButton(onPressed: _load, child: const Text('إعادة المحاولة')),
            )
          : d == null
              ? const Center(child: CircularProgressIndicator())
              : _body(context, app, d),
    );
  }

  Widget _body(BuildContext context, AppState app, Map<String, dynamic> d) {
    final sem = Sem.of(context);
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final p = _map(d['profile']);
    final a = _map(d['auth']);
    final mfa = _list(d['mfa']);
    final sessions = _list(d['sessions']);
    final logins = _list(d['logins']);
    final act = _map(d['activity']);
    final requests = _map(act['requests']);
    final recent = _list(d['recent']).map(AuditEntry.fromMap).toList();
    final history = _list(d['history']).map(AuditEntry.fromMap).toList();

    final role = parseRole(p['role']);
    final active = p['active'] == true;
    final name = (p['full_name'] ?? '').toString().trim();
    final email = (a['email'] ?? p['email'] ?? '').toString();
    final display = name.isNotEmpty ? name : (email.isNotEmpty ? email : 'مستخدم');
    final verified = mfa.where((f) => f['status'] == 'verified').toList();
    final mfaRequired = p['mfa_required'] == true;
    final isMe = widget.userId == app.me?.id;
    final canManage = app.isDirector && role != AppRole.director && !isMe;
    final statusText = active ? 'مفعّل' : (role == null ? 'بانتظار التفعيل' : 'موقوف');
    final statusColor = active ? sem.ok : (role == null ? sem.wip : sem.danger);
    final roleText = role == null
        ? 'لم يُحدَّد دوره بعد'
        : (role == AppRole.deptHead ? 'رئيس قسم ${(p['department_name'] ?? '').toString()}' : role.label);
    final providers = (a['providers'] is List ? (a['providers'] as List) : const <Object?>[]).map((e) => _provider(e.toString())).join('، ');
    final signupName = (a['signup_name'] ?? '').toString().trim();
    int n(Object? v) => (v as num?)?.toInt() ?? 0;
    final reqTotal = requests.values.fold<int>(0, (s, v) => s + n(v));

    return PageBody(
      maxWidth: 980,
      onRefresh: _load,
      children: [
        // --------------------------------------------------------- الرأس
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(color: sem.surface, borderRadius: BorderRadius.circular(18), border: Border.all(color: sem.rule)),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              InitialsAvatar(name: display, size: 60, color: role == AppRole.director ? cs.primary : statusColor),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(display, style: t.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                    if (email.isNotEmpty && email != display)
                      Text(email, textDirection: TextDirection.ltr, style: TextStyle(color: sem.muted)),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        ToneBadge(roleText, color: cs.primary, icon: Icons.badge_outlined),
                        ToneBadge(statusText, color: statusColor),
                        ToneBadge(
                          verified.isNotEmpty ? 'التحقق بخطوتين مفعّل' : (mfaRequired ? 'التحقق إلزامي ولم يُفعَّل' : 'التحقق بخطوتين غير مفعّل'),
                          color: verified.isNotEmpty ? sem.ok : (mfaRequired ? sem.danger : sem.muted),
                          icon: Icons.phonelink_lock_outlined,
                        ),
                        ToneBadge('${sessions.length} ${sessions.length == 1 ? 'جهاز متصل' : 'أجهزة متصلة'}',
                            color: sessions.isEmpty ? sem.muted : sem.wip, icon: Icons.devices_rounded),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (canManage) ...[
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed: () => _editAccess(app),
                icon: const Icon(Icons.manage_accounts_outlined),
                label: Text(role == null ? 'تفعيل الحساب' : 'تعديل الصلاحيات والبيانات'),
              ),
              if (sessions.isNotEmpty)
                OutlinedButton.icon(
                  onPressed: () => _signOutEverywhere(app, display),
                  icon: const Icon(Icons.logout_rounded),
                  label: const Text('إخراج من كل الأجهزة'),
                ),
              if (verified.isNotEmpty)
                OutlinedButton.icon(
                  onPressed: () => _resetMfa(app, display),
                  icon: const Icon(Icons.phonelink_erase_rounded),
                  label: const Text('إلغاء التحقق بخطوتين'),
                ),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(foregroundColor: sem.danger, side: BorderSide(color: sem.danger.withAlpha(120))),
                onPressed: () => _delete(app, email, display),
                icon: const Icon(Icons.delete_forever_outlined),
                label: const Text('حذف المستخدم'),
              ),
            ],
          ),
        ] else if (!app.isDirector) ...[
          const SizedBox(height: 12),
          const InfoBanner(icon: Icons.visibility_outlined, text: 'للاطلاع فقط: إدارة الحساب من صلاحية مدير المكتب.'),
        ],
        const SizedBox(height: 16),

        // --------------------------------------------------------- بيانات الحساب
        SectionCard(
          title: 'بيانات الحساب',
          icon: Icons.person_outline_rounded,
          child: Column(
            children: [
              _Kv('الاسم الكامل', name.isEmpty ? '—' : name),
              if (signupName.isNotEmpty && signupName != name) _Kv('الاسم عند التسجيل', signupName),
              _Kv('بريد الدخول', email.isEmpty ? '—' : email, ltr: true, copy: email.isNotEmpty),
              _Kv('تأكيد البريد', a['email_confirmed_at'] == null ? 'غير مؤكَّد' : 'مؤكَّد في ${_when(a['email_confirmed_at'])}'),
              if ((a['phone'] ?? '').toString().isNotEmpty) _Kv('الهاتف', a['phone'].toString(), ltr: true),
              _Kv('الدور', roleText),
              _Kv('الحالة', statusText),
              if (providers.isNotEmpty) _Kv('طريقة الدخول', providers),
              _Kv('إنشاء الحساب', _when(a['created_at'] ?? p['created_at'])),
              _Kv(
                'التفعيل',
                p['activated_at'] == null
                    ? 'لم يُفعَّل بعد'
                    : '${_when(p['activated_at'])}${(p['activated_by_name'] ?? '').toString().isNotEmpty ? ' · بواسطة ${p['activated_by_name']}' : ''}',
              ),
              _Kv('آخر دخول', _when(a['last_sign_in_at'], empty: 'لم يدخل بعد')),
              _Kv('آخر تحديث لبيانات الدخول', _when(a['updated_at'])),
              if ((a['email_change'] ?? '').toString().isNotEmpty) _Kv('طلب تغيير بريد معلّق', a['email_change'].toString(), ltr: true),
              if (a['recovery_sent_at'] != null) _Kv('آخر طلب لاستعادة كلمة المرور', _when(a['recovery_sent_at'])),
              if (a['banned_until'] != null) _Kv('محظور حتى', _when(a['banned_until'])),
              _Kv('معرّف الحساب', widget.userId, ltr: true, copy: true, last: true),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // --------------------------------------------------------- الأمان
        SectionCard(
          title: 'التحقق بخطوتين',
          icon: Icons.phonelink_lock_outlined,
          trailing: ToneBadge(mfaRequired ? 'إلزامي لهذا الحساب' : 'اختياري', color: mfaRequired ? sem.wip : sem.muted),
          child: mfa.isEmpty
              ? Text('لم يُضِف أي وسيلة تحقق.', style: TextStyle(color: sem.muted))
              : Column(
                  children: [
                    for (final f in mfa)
                      SettingRow(
                        icon: f['status'] == 'verified' ? Icons.verified_user_rounded : Icons.hourglass_empty_rounded,
                        title: [
                          (f['type'] ?? 'totp') == 'totp' ? 'تطبيق مصادقة' : (f['type'] == 'phone' ? 'رسالة نصية' : f['type'].toString()),
                          if ((f['name'] ?? '').toString().isNotEmpty) f['name'].toString(),
                        ].join(' · '),
                        subtitle: [
                          f['status'] == 'verified' ? 'مفعّل' : 'لم يكتمل تفعيله',
                          'أُضيف ${_when(f['created_at'])}',
                          if (f['last_challenged_at'] != null) 'آخر استخدام ${_when(f['last_challenged_at'])}',
                        ].join(' · '),
                      ),
                  ],
                ),
        ),
        const SizedBox(height: 16),
        SectionCard(
          title: 'الأجهزة المتصلة الآن',
          icon: Icons.devices_rounded,
          child: sessions.isEmpty
              ? Text('لا توجد جلسات مفتوحة لهذا المستخدم.', style: TextStyle(color: sem.muted))
              : Column(
                  children: [
                    for (final s in sessions)
                      SettingRow(
                        icon: deviceIcon((s['user_agent'] ?? '').toString()),
                        title: deviceName((s['user_agent'] ?? '').toString()),
                        subtitle: [
                          if ((s['ip'] ?? '').toString().isNotEmpty) 'IP ${s['ip']}',
                          'آخر نشاط ${_when(s['updated_at'] ?? s['created_at'])}',
                          'بدأت ${_when(s['created_at'])}',
                          if (s['aal'] == 'aal2') 'بعد رمز التحقق',
                        ].join(' · '),
                      ),
                  ],
                ),
        ),
        const SizedBox(height: 16),
        SectionCard(
          title: 'سجل الدخول',
          icon: Icons.login_rounded,
          subtitle: 'آخر عمليات الدخول والخروج وتغيير كلمة المرور لهذا الحساب',
          child: logins.isEmpty
              ? Text('لا تتوفر سجلات دخول لهذا الحساب.', style: TextStyle(color: sem.muted))
              : Column(
                  children: [
                    for (final l in logins)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Row(
                          children: [
                            Icon(loginActionIcon((l['action'] ?? '').toString()), size: 19, color: sem.muted),
                            const SizedBox(width: 10),
                            Expanded(child: Text(loginActionLabel((l['action'] ?? '').toString()))),
                            if ((l['ip'] ?? '').toString().isNotEmpty)
                              Padding(
                                padding: const EdgeInsetsDirectional.only(end: 12),
                                child: Text(l['ip'].toString(), textDirection: TextDirection.ltr, style: TextStyle(color: sem.muted, fontSize: 12)),
                              ),
                            Text(_when(l['at']), style: TextStyle(color: sem.muted, fontSize: 12)),
                          ],
                        ),
                      ),
                  ],
                ),
        ),
        const SizedBox(height: 16),

        // --------------------------------------------------------- النشاط
        SectionCard(
          title: 'النشاط في المنظومة',
          icon: Icons.insights_outlined,
          child: ResponsiveGrid(
            minItemWidth: 190,
            children: [
              StatCard(
                icon: Icons.history_rounded,
                label: 'العمليات المسجّلة',
                value: '${n(act['audit_total'])}',
                sub: '${n(act['audit_30d'])} في آخر 30 يوماً',
              ),
              StatCard(
                icon: Icons.schedule_rounded,
                label: 'آخر نشاط',
                value: act['last_action_at'] == null ? '—' : _when(act['last_action_at']).split('  ').first,
                sub: act['last_action_at'] == null ? 'لم يسجّل أي عملية' : _when(act['last_action_at']).split('  ').last,
              ),
              StatCard(icon: Icons.task_alt_rounded, label: 'نماذج آخر من حدّثها', value: '${n(act['forms_updated'])}', color: sem.ok),
              StatCard(icon: Icons.create_new_folder_outlined, label: 'مشاريع أنشأها', value: '${n(act['projects_created'])}'),
              StatCard(
                icon: Icons.fact_check_outlined,
                label: 'طلبات الاعتماد',
                value: '$reqTotal',
                sub: 'معلّقة ${n(requests['pending'])} · مقبولة ${n(requests['approved'])} · مرفوضة ${n(requests['rejected'])}',
                color: sem.wip,
              ),
              StatCard(
                icon: Icons.lightbulb_outline_rounded,
                label: 'الأفكار المقترحة',
                value: '${n(act['ideas'])}',
                sub: 'ملاحظات الجودة: ${n(act['quality_notes'])}',
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _AuditCard(
          title: 'آخر عملياته',
          icon: Icons.manage_history_rounded,
          empty: 'لم يسجّل أي عملية بعد.',
          rows: recent,
          showActor: false,
        ),
        const SizedBox(height: 16),
        _AuditCard(
          title: 'تاريخ الحساب',
          icon: Icons.admin_panel_settings_outlined,
          subtitle: 'التفعيل وتغيير الدور والبريد والإخراج من الأجهزة وإلغاء التحقق، ومن قام بها',
          empty: 'لا توجد عمليات على هذا الحساب.',
          rows: history,
          showActor: true,
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  // ------------------------------------------------------------------ إجراءات المدير
  Future<void> _editAccess(AppState app) async {
    final prof = app.people[widget.userId];
    if (prof == null) return;
    await openUserEditor(context, app, prof);
    await _load();
  }

  Future<void> _signOutEverywhere(AppState app, String display) async {
    final ok = await confirmDialog(context,
        title: 'إخراج $display من كل أجهزته؟', message: 'يُطلب منه الدخول من جديد على كل جهاز.', confirmLabel: 'إخراج');
    if (!ok || !mounted) return;
    await runAction(context, () async {
      final n = await app.revokeUserSessions(widget.userId);
      if (mounted) showToast(context, 'أُنهيت $n جلسة');
    });
    await _load();
  }

  Future<void> _resetMfa(AppState app, String display) async {
    final ok = await confirmDialog(context,
        title: 'إلغاء التحقق بخطوتين؟',
        message: 'استخدمه إذا فقد $display هاتفه. يدخل بكلمة المرور ثم يفعّل التحقق من جديد.',
        confirmLabel: 'إلغاء التحقق',
        danger: true);
    if (!ok || !mounted) return;
    await runAction(context, () => app.resetUserMfa(widget.userId), success: 'أُلغي التحقق بخطوتين');
    await _load();
  }

  Future<void> _delete(AppState app, String email, String display) async {
    final sem = Sem.of(context);
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          final match = ctrl.text.trim().toLowerCase() == email.trim().toLowerCase() && email.isNotEmpty;
          return AlertDialog(
            icon: Icon(Icons.delete_forever_outlined, color: sem.danger, size: 32),
            title: Text('حذف $display نهائياً؟'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('يُحذف حساب الدخول وكل جلساته ووسائل التحقق وإشعاراته، وتُسحب طلباته المعلّقة. '
                    'يبقى اسمه في سجل التدقيق وفي المشاريع التي عمل عليها. لا يمكن التراجع عن الحذف.'),
                const SizedBox(height: 14),
                Text('للتأكيد اكتب بريده:', style: TextStyle(color: sem.muted, fontSize: 12.5)),
                SelectableText(email, textDirection: TextDirection.ltr, style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                TextField(
                  controller: ctrl,
                  autofocus: true,
                  textDirection: TextDirection.ltr,
                  keyboardType: TextInputType.emailAddress,
                  decoration: fieldDeco('بريد المستخدم'),
                  onChanged: (_) => setLocal(() {}),
                ),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('إلغاء')),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: sem.danger, foregroundColor: Colors.white),
                onPressed: match ? () => Navigator.of(ctx).pop(true) : null,
                child: const Text('حذف نهائياً'),
              ),
            ],
          );
        },
      ),
    );
    final typed = ctrl.text;
    ctrl.dispose();
    if (ok != true || !mounted) return;
    final done = await runAction(context, () => app.deleteUser(widget.userId, typed));
    if (done && mounted) {
      showToast(context, 'حُذف حساب $display');
      Navigator.of(context).pop();
    }
  }
}

/// سطر «عنوان: قيمة» في بطاقة البيانات.
class _Kv extends StatelessWidget {
  const _Kv(this.label, this.value, {this.ltr = false, this.copy = false, this.last = false});

  final String label;
  final String value;
  final bool ltr;
  final bool copy;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final sem = Sem.of(context);
    final valueText = SelectableText(
      value,
      textDirection: ltr ? TextDirection.ltr : null,
      textAlign: ltr ? TextAlign.end : TextAlign.start,
      style: const TextStyle(fontWeight: FontWeight.w600),
    );
    final copyBtn = copy
        ? IconButton(
            tooltip: 'نسخ',
            visualDensity: VisualDensity.compact,
            iconSize: 18,
            icon: Icon(Icons.copy_rounded, color: sem.muted),
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: value));
              if (context.mounted) showToast(context, 'نُسخ');
            },
          )
        : null;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 9),
      decoration: BoxDecoration(border: last ? null : Border(bottom: BorderSide(color: sem.rule))),
      child: LayoutBuilder(builder: (context, c) {
        final narrow = c.maxWidth < 460;
        final labelText = Text(label, style: TextStyle(color: sem.muted, fontSize: 13));
        if (narrow) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              labelText,
              const SizedBox(height: 2),
              Row(children: [Expanded(child: valueText), if (copyBtn != null) copyBtn]),
            ],
          );
        }
        return Row(
          children: [
            SizedBox(width: 200, child: labelText),
            Expanded(child: valueText),
            if (copyBtn != null) copyBtn,
          ],
        );
      }),
    );
  }
}

/// بطاقة سطور من سجل التدقيق.
class _AuditCard extends StatelessWidget {
  const _AuditCard({
    required this.title,
    required this.icon,
    required this.empty,
    required this.rows,
    required this.showActor,
    this.subtitle,
  });

  final String title;
  final IconData icon;
  final String? subtitle;
  final String empty;
  final List<AuditEntry> rows;
  final bool showActor;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final sem = Sem.of(context);
    return SectionCard(
      title: title,
      icon: icon,
      subtitle: subtitle,
      child: rows.isEmpty
          ? Text(empty, style: TextStyle(color: sem.muted))
          : Column(
              children: [
                for (var i = 0; i < rows.length; i++)
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 9),
                    decoration: BoxDecoration(border: i == rows.length - 1 ? null : Border(bottom: BorderSide(color: sem.rule))),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (showActor)
                                Text(rows[i].actorName.isEmpty ? 'النظام' : rows[i].actorName,
                                    style: const TextStyle(fontWeight: FontWeight.w700)),
                              Text(auditDescription(app, rows[i])),
                              if (rows[i].projectId != null && rows[i].projectLabel.isNotEmpty && !rows[i].action.startsWith('project.'))
                                Text(rows[i].projectLabel,
                                    maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: sem.muted, fontSize: 12.5)),
                            ],
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(fmtDate(rows[i].at), style: TextStyle(color: sem.muted, fontSize: 12)),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }
}
