import 'package:flutter/material.dart';

import '../../app_state.dart';
import '../../models.dart';
import '../../ui/audit_text.dart';
import '../../ui/motion.dart';
import '../../ui/theme.dart';
import '../../ui/widgets.dart';
import 'control_panel.dart';
import 'security.dart' show deviceIcon, deviceName;
import 'user_details.dart';

/// المراقبة والإجراءات الأمنية (للمدير وCISO): التنبيهات، وسجل الأجهزة، والحركة الدقيقة لكل حساب،
/// والحسابات وحالة دخولها، والتفعيلات. الإجراءات: إنهاء الجلسات، والإخراج من الأجهزة، وقفل الدخول مؤقتاً،
/// وحظر جهاز. لا تغيير للأدوار ولا حذف (من صلاحية المدير وحده في «المستخدمون والأدوار»).
class SecurityOpsSection extends StatefulWidget {
  const SecurityOpsSection({super.key});

  @override
  State<SecurityOpsSection> createState() => _SecurityOpsSectionState();
}

const _views = [
  ('alerts', 'التنبيهات', Icons.notification_important_outlined),
  ('devices', 'الأجهزة', Icons.devices_other_outlined),
  ('timeline', 'الحركة الدقيقة', Icons.timeline_rounded),
  ('accounts', 'الحسابات والدخول', Icons.manage_accounts_outlined),
  ('activations', 'التفعيلات', Icons.how_to_reg_outlined),
];

/// أسماء أحداث سجل المصادقة.
const Map<String, String> authActionLabels = {
  'login': 'دخول',
  'logout': 'خروج',
  'user_signedup': 'إنشاء حساب',
  'user_recovery_requested': 'طلب استعادة كلمة المرور',
  'user_updated_password': 'تغيير كلمة المرور',
  'factor_in_progress': 'بدء تفعيل التحقق بخطوتين',
  'factor_unenrolled': 'إزالة وسيلة تحقق',
  'mfa_code_login': 'دخول برمز التحقق',
  'token_revoked': 'إبطال رمز الجلسة',
  'user_deleted': 'حذف الحساب',
  'user_modified': 'تعديل بيانات الدخول',
};

class _SecurityOpsSectionState extends State<SecurityOpsSection> {
  String _view = 'alerts';
  List<Map<String, dynamic>> _alerts = const [];
  List<UserDevice> _devices = const [];
  List<Map<String, dynamic>> _users = const [];
  List<Map<String, dynamic>> _timeline = const [];
  bool _loading = true;
  String? _error;

  // تصفية الحركة
  String? _user;
  int _days = 7;
  String _source = ''; // '' | auth | app
  String _q = '';

  // تصفية الأجهزة
  String _devFilter = 'all'; // all | trusted | untrusted | blocked | new

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final app = AppScope.read(context);
    setState(() => _loading = true);
    try {
      final r = await Future.wait<Object>([
        app.securityAlerts(),
        app.securityDevices(),
        app.securityUsers(),
        app.securityTimeline(userId: _user, days: _days),
      ]);
      if (!mounted) return;
      setState(() {
        _alerts = r[0] as List<Map<String, dynamic>>;
        _devices = r[1] as List<UserDevice>;
        _users = r[2] as List<Map<String, dynamic>>;
        _timeline = r[3] as List<Map<String, dynamic>>;
        _error = null;
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = friendlyError(e);
          _loading = false;
        });
      }
    }
  }

  Future<void> _reloadTimeline() async {
    final app = AppScope.read(context);
    try {
      final t = await app.securityTimeline(userId: _user, days: _days);
      if (mounted) setState(() => _timeline = t);
    } catch (e) {
      if (mounted) showToast(context, friendlyError(e), error: true);
    }
  }

  String _nameOf(String? id) {
    if (id == null) return '';
    for (final u in _users) {
      if (u['id'].toString() == id) {
        final n = (u['full_name'] ?? '').toString().trim();
        return n.isNotEmpty ? n : (u['email'] ?? '').toString();
      }
    }
    return '';
  }

  bool _isDirectorAccount(String id) => _users.any((u) => u['id'].toString() == id && u['role'] == 'director');
  bool _isAuditorAccount(String id) => _users.any((u) => u['id'].toString() == id && u['role'] == 'security_auditor');

  /// هل يملك المستخدم الحالي إجراءً على هذا الحساب (كما تفرضه قاعدة البيانات)؟
  bool _canAct(AppState app, String id) {
    if (id == app.me?.id) return false;
    if (_isDirectorAccount(id)) return false;
    if (_isAuditorAccount(id) && !app.isDirector) return false;
    return app.canAudit;
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final sem = Sem.of(context);
    if (!app.v4Ready) {
      return const Center(
        child: EmptyState(
          icon: Icons.update_rounded,
          title: 'تحتاج تحديث قاعدة البيانات',
          message: 'المراقبة والإجراءات الأمنية تعمل بعد تطبيق الترحيل 20261105000011_finance_security.sql.',
        ),
      );
    }
    final critical = _alerts.where((a) => a['level'] == 'critical').length;
    final warning = _alerts.where((a) => a['level'] == 'warning').length;
    return PageBody(
      onRefresh: _load,
      children: [
        PageHeader(
          icon: Icons.radar_outlined,
          title: 'المراقبة والإجراءات الأمنية',
          subtitle: app.isDirector
              ? 'الأجهزة المتصلة والحركة الدقيقة لكل حساب والتنبيهات، مع قفل الدخول وحظر الأجهزة وإنهاء الجلسات. كل إجراء يُسجَّل.'
              : 'صلاحيتك: مراقبة كاملة وإجراءات أمنية (إنهاء الجلسات، الإخراج، قفل الدخول، حظر الأجهزة) دون تغيير الأدوار أو الحذف. '
                  'لا إجراء على حساب المدير، ويُبلَّغ المدير بما تتخذه.',
          actions: [
            if (_loading) const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)),
            OutlinedButton.icon(onPressed: _load, icon: const Icon(Icons.refresh), label: const Text('تحديث')),
          ],
        ),
        if (_error != null) ...[InfoBanner(text: _error!, level: 'critical'), const SizedBox(height: 12)],
        ResponsiveGrid(minItemWidth: 180, children: [
          StatCard(label: 'تنبيهات حرجة', value: '$critical', icon: Icons.gpp_maybe_outlined, color: critical > 0 ? sem.danger : sem.ok,
              onTap: () => setState(() => _view = 'alerts')),
          StatCard(label: 'تنبيهات تحذيرية', value: '$warning', icon: Icons.warning_amber_rounded, color: warning > 0 ? sem.wip : sem.ok,
              onTap: () => setState(() => _view = 'alerts')),
          StatCard(
              label: 'الأجهزة المسجلة',
              value: '${_devices.length}',
              sub: '${_devices.where((d) => d.trusted && !d.blocked).length} موثوق · ${_devices.where((d) => d.blocked).length} محظور',
              icon: Icons.devices_other_outlined,
              onTap: () => setState(() => _view = 'devices')),
          StatCard(
              label: 'حسابات مقفلة',
              value: '${_users.where((u) => u['locked_until'] != null).length}',
              icon: Icons.lock_clock_outlined,
              onTap: () => setState(() => _view = 'accounts')),
        ]),
        const SizedBox(height: 14),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            for (final v in _views)
              Padding(
                padding: const EdgeInsetsDirectional.only(end: 8),
                child: ChoiceChip(
                  avatar: Icon(v.$3, size: 18),
                  label: Text(v.$2),
                  showCheckmark: false,
                  selected: _view == v.$1,
                  onSelected: (_) => setState(() => _view = v.$1),
                ),
              ),
          ]),
        ),
        const SizedBox(height: 14),
        MotionSwitcher(
          expand: false,
          child: KeyedSubtree(
            key: ValueKey(_view),
            child: switch (_view) {
              'devices' => _devicesView(context, app),
              'timeline' => _timelineView(context, app),
              'accounts' => _accountsView(context, app),
              'activations' => _activationsView(context, app),
              _ => _alertsView(context, app),
            },
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------- التنبيهات
  Widget _alertsView(BuildContext context, AppState app) {
    final sem = Sem.of(context);
    if (_alerts.isEmpty) {
      return const EmptyState(icon: Icons.verified_user_outlined, title: 'لا تنبيهات', message: 'لا أجهزة جديدة ولا محاولات من أجهزة محظورة ولا حسابات حساسة بلا تحقق.');
    }
    int rank(Object? l) => switch (l) { 'critical' => 0, 'warning' => 1, _ => 2 };
    final list = [..._alerts]..sort((a, b) {
        final r = rank(a['level']).compareTo(rank(b['level']));
        if (r != 0) return r;
        return (b['at'] ?? '').toString().compareTo((a['at'] ?? '').toString());
      });
    return SectionCard(
      title: 'التنبيهات الأمنية',
      icon: Icons.notification_important_outlined,
      subtitle: 'محسوبة لحظياً: أجهزة جديدة، جلسات كثيرة متزامنة، دخول خارج ساعات العمل، أجهزة محظورة نشطة، حسابات حساسة بلا تحقق، وتفعيلات حديثة.',
      child: Column(children: [
        for (final a in list)
          ListTile(
            contentPadding: EdgeInsets.zero,
            onTap: a['user_id'] == null ? null : () => openUserDetails(context, a['user_id'].toString()),
            leading: CircleAvatar(
              backgroundColor: switch (a['level']) { 'critical' => sem.dangerSoft, 'warning' => sem.wipSoft, _ => sem.surface2 },
              child: Icon(
                switch (a['kind']) {
                  'new_device' => Icons.devices_other_outlined,
                  'blocked_device_active' => Icons.block_rounded,
                  'many_sessions' => Icons.layers_outlined,
                  'off_hours_login' => Icons.nightlight_outlined,
                  'locked' => Icons.lock_clock_outlined,
                  'pending' => Icons.hourglass_top_rounded,
                  'activated' => Icons.how_to_reg_outlined,
                  'mfa_missing' => Icons.phonelink_lock_outlined,
                  _ => Icons.info_outline_rounded,
                },
                size: 20,
                color: switch (a['level']) { 'critical' => sem.danger, 'warning' => sem.wip, _ => sem.muted },
              ),
            ),
            title: Text((a['title'] ?? '').toString(), style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: a['at'] == null ? null : Text(fmtDate(DateTime.tryParse(a['at'].toString())), style: TextStyle(color: sem.muted, fontSize: 12)),
            trailing: const Icon(Icons.chevron_left_rounded),
          ),
      ]),
    );
  }

  // ---------------------------------------------------------------- الأجهزة
  Widget _devicesView(BuildContext context, AppState app) {
    final sem = Sem.of(context);
    final cs = Theme.of(context).colorScheme;
    final weekAgo = DateTime.now().subtract(const Duration(days: 7));
    final list = _devices.where((d) => switch (_devFilter) {
          'trusted' => d.trusted && !d.blocked,
          'untrusted' => !d.trusted && !d.blocked,
          'blocked' => d.blocked,
          'new' => (d.firstSeen ?? DateTime(2000)).isAfter(weekAgo),
          _ => true,
        }).toList();
    return SectionCard(
      title: 'سجل الأجهزة',
      icon: Icons.devices_other_outlined,
      subtitle: 'كل جهاز دخل منه حساب: المنصة، والعنوان الأول والأخير، وعدد مرات الدخول والفتح، وتوثيقه بموافقة صاحبه («تذكرني»). '
          'حظر الجهاز يُخرج الحساب من كل جلساته، ويُرفض الجهاز عند أي دخول لاحق.',
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final f in const [('all', 'الكل'), ('trusted', 'موثوقة'), ('untrusted', 'غير موثوقة'), ('new', 'جديدة (7 أيام)'), ('blocked', 'محظورة')])
            ChoiceChip(label: Text(f.$2), selected: _devFilter == f.$1, onSelected: (_) => setState(() => _devFilter = f.$1)),
        ]),
        const SizedBox(height: 10),
        if (list.isEmpty)
          Padding(padding: const EdgeInsets.all(12), child: Text('لا أجهزة مطابقة.', style: TextStyle(color: sem.muted)))
        else
          for (final d in list)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Container(
                padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
                decoration: BoxDecoration(
                  color: d.blocked ? sem.dangerSoft : sem.surface2,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Icon(_platformIcon(d.platform), color: d.blocked ? sem.danger : cs.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Wrap(spacing: 6, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                        Text('${d.name.isEmpty ? _nameOf(d.userId) : d.name} · ${d.display}', style: const TextStyle(fontWeight: FontWeight.w700)),
                        if (d.blocked) ToneBadge('محظور', color: sem.danger, icon: Icons.block_rounded),
                        if (!d.blocked && d.trusted) ToneBadge('موثوق', color: sem.ok, icon: Icons.verified_rounded),
                        if (!d.blocked && !d.trusted) ToneBadge('غير موثوق', color: sem.muted),
                        if ((d.firstSeen ?? DateTime(2000)).isAfter(weekAgo)) ToneBadge('جديد', color: sem.wip),
                      ]),
                      const SizedBox(height: 4),
                      Text(
                        [
                          if (d.ip.isNotEmpty) 'IP ${d.ip}',
                          if (d.firstIp.isNotEmpty && d.firstIp != d.ip) 'أول IP ${d.firstIp}',
                          'أول ظهور ${fmtDate(d.firstSeen)}',
                          'آخر نشاط ${fmtDate(d.lastSeen)}',
                          '${d.signIns} دخول · ${d.opens} فتح',
                          if (d.appVersion.isNotEmpty) 'الإصدار ${d.appVersion}',
                        ].join(' · '),
                        style: TextStyle(color: sem.muted, fontSize: 12),
                      ),
                      if (d.userAgent.isNotEmpty)
                        Text(deviceName(d.userAgent), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: sem.muted, fontSize: 11.5)),
                      if (d.blocked && d.blockedByName.isNotEmpty)
                        Text('حظره ${d.blockedByName} في ${fmtDate(d.blockedAt)}', style: TextStyle(color: sem.danger, fontSize: 11.5)),
                    ]),
                  ),
                  PopupMenuButton<String>(
                    tooltip: 'إجراءات',
                    onSelected: (v) => _deviceAction(app, d, v),
                    itemBuilder: (_) => [
                      if (_canAct(app, d.userId))
                        PopupMenuItem(
                          value: d.blocked ? 'unblock' : 'block',
                          child: ListTile(
                            leading: Icon(d.blocked ? Icons.lock_open_rounded : Icons.block_rounded, color: d.blocked ? null : sem.danger),
                            title: Text(d.blocked ? 'رفع الحظر' : 'حظر الجهاز'),
                          ),
                        ),
                      const PopupMenuItem(value: 'user', child: ListTile(leading: Icon(Icons.person_search_outlined), title: Text('بيانات الحساب'))),
                      const PopupMenuItem(value: 'trace', child: ListTile(leading: Icon(Icons.timeline_rounded), title: Text('حركة هذا الحساب'))),
                    ],
                  ),
                ]),
              ),
            ),
      ]),
    );
  }

  static IconData _platformIcon(String p) => switch (p) {
        'android' => Icons.phone_android_rounded,
        'ios' => Icons.phone_iphone_rounded,
        'windows' => Icons.desktop_windows_outlined,
        'macos' => Icons.laptop_mac_rounded,
        'linux' => Icons.computer_rounded,
        'web' => Icons.language_rounded,
        _ => Icons.devices_other_outlined,
      };

  Future<void> _deviceAction(AppState app, UserDevice d, String v) async {
    switch (v) {
      case 'user':
        openUserDetails(context, d.userId);
      case 'trace':
        setState(() {
          _user = d.userId;
          _view = 'timeline';
        });
        await _reloadTimeline();
      case 'block':
        final ok = await confirmDialog(context,
            title: 'حظر هذا الجهاز؟',
            message: 'يُخرج ${_nameOf(d.userId)} من كل جلساته الآن، ويُرفض هذا الجهاز (${d.display}) عند أي دخول لاحق. '
                'يستطيع الدخول من أجهزته الأخرى. يُسجَّل الإجراء${app.isDirector ? '' : ' ويُبلَّغ المدير'}.',
            confirmLabel: 'حظر',
            danger: true);
        if (!ok || !mounted) return;
        await runAction(context, () async {
          final n = await app.setDeviceBlocked(d.id, true);
          if (mounted) showToast(context, 'حُظر الجهاز وأُنهيت $n جلسة');
        });
        await _load();
      case 'unblock':
        await runAction(context, () => app.setDeviceBlocked(d.id, false), success: 'رُفع الحظر');
        await _load();
    }
  }

  // ---------------------------------------------------------------- الحركة الدقيقة
  Widget _timelineView(BuildContext context, AppState app) {
    final sem = Sem.of(context);
    final q = normalizeArabic(_q);
    final rows = _timeline.where((e) {
      if (_source.isNotEmpty && e['source'] != _source) return false;
      if (q.isEmpty) return true;
      return normalizeArabic('${_label(app, e)} ${e['name'] ?? ''} ${e['email'] ?? ''} ${e['ip'] ?? ''}').contains(q);
    }).toList();
    // تجميع بالأيام
    final groups = <String, List<Map<String, dynamic>>>{};
    for (final e in rows) {
      final d = DateTime.tryParse((e['at'] ?? '').toString())?.toLocal();
      final k = d == null ? '—' : dayText(d);
      (groups[k] ??= []).add(e);
    }
    final userItems = <(String, String)>[
      ('', 'كل الحسابات'),
      for (final u in _users) (u['id'].toString(), _nameOf(u['id'].toString())),
    ];
    return SectionCard(
      title: 'الحركة الدقيقة للحسابات',
      icon: Icons.timeline_rounded,
      subtitle: 'الدخول والخروج وتغيير كلمات المرور والتحقق من سجل المصادقة، مع أحداث الأجهزة والقفل والصلاحيات من سجل التدقيق، '
          'وكل عمليات الحساب المختار في المنظومة.',
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        LayoutBuilder(builder: (context, c) {
          final user = SelectField(
            label: 'الحساب',
            value: _user ?? '',
            items: userItems,
            onChanged: (v) {
              setState(() => _user = v.isEmpty ? null : v);
              _reloadTimeline();
            },
          );
          final days = SelectField(
            label: 'المدة',
            value: '$_days',
            items: const [('1', 'آخر 24 ساعة'), ('7', 'آخر 7 أيام'), ('30', 'آخر 30 يوماً'), ('90', 'آخر 90 يوماً'), ('365', 'آخر سنة')],
            onChanged: (v) {
              setState(() => _days = int.parse(v));
              _reloadTimeline();
            },
          );
          final source = SelectField(
            label: 'المصدر',
            value: _source,
            items: const [('', 'الكل'), ('auth', 'المصادقة (الدخول والخروج)'), ('app', 'المنظومة (العمليات والأمان)')],
            onChanged: (v) => setState(() => _source = v),
          );
          if (c.maxWidth < 700) {
            return Column(children: [user, const SizedBox(height: 8), days, const SizedBox(height: 8), source]);
          }
          return Row(children: [
            Expanded(flex: 2, child: user),
            const SizedBox(width: 8),
            Expanded(child: days),
            const SizedBox(width: 8),
            Expanded(child: source),
          ]);
        }),
        const SizedBox(height: 8),
        TextField(
          onChanged: (v) => setState(() => _q = v),
          decoration: fieldDeco('بحث في الأحداث (اسم، بريد، عنوان IP، نوع الحدث)', prefixIcon: const Icon(Icons.search_rounded)),
        ),
        const SizedBox(height: 10),
        Text('${rows.length} حدثاً', style: TextStyle(color: sem.muted, fontSize: 12)),
        if (rows.isEmpty)
          Padding(padding: const EdgeInsets.all(16), child: Text('لا أحداث في هذه المدة.', style: TextStyle(color: sem.muted)))
        else
          for (final g in groups.entries) ...[
            Padding(
              padding: const EdgeInsets.only(top: 12, bottom: 4),
              child: Text(g.key, style: const TextStyle(fontWeight: FontWeight.w800)),
            ),
            for (final e in g.value) _event(context, app, e),
          ],
      ]),
    );
  }

  String _label(AppState app, Map<String, dynamic> e) {
    final action = (e['action'] ?? '').toString();
    if (e['source'] == 'auth') return authActionLabels[action] ?? action;
    final detail = e['detail'] is Map ? Map<String, dynamic>.from(e['detail'] as Map) : <String, dynamic>{};
    final entry = AuditEntry.fromMap({
      'id': 0,
      'at': e['at'],
      'actor': null,
      'actor_name': (e['actor'] ?? '').toString(),
      'project_id': null,
      'project_label': (e['name'] ?? '').toString(),
      'action': action,
      'form_key': null,
      'detail': detail,
    });
    return auditDescription(app, entry);
  }

  Widget _event(BuildContext context, AppState app, Map<String, dynamic> e) {
    final sem = Sem.of(context);
    final at = DateTime.tryParse((e['at'] ?? '').toString())?.toLocal();
    final auth = e['source'] == 'auth';
    final action = (e['action'] ?? '').toString();
    final danger = action.contains('block') || action.contains('lock') && !action.contains('unlock') || action == 'user_deleted';
    final color = danger ? sem.danger : (auth ? Theme.of(context).colorScheme.primary : sem.wip);
    final who = (e['name'] ?? '').toString().isNotEmpty ? e['name'].toString() : (e['email'] ?? '').toString();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
          width: 46,
          child: Text(at == null ? '' : '${two(at.hour)}:${two(at.minute)}',
              style: TextStyle(color: sem.muted, fontSize: 12, fontFeatures: const [FontFeature.tabularFigures()])),
        ),
        Container(width: 8, height: 8, margin: const EdgeInsets.only(top: 6, left: 8, right: 8), decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(_label(app, e), style: const TextStyle(fontSize: 13.5)),
            Text(
              [
                if (who.isNotEmpty) who,
                if (!auth && (e['actor'] ?? '').toString().isNotEmpty && e['actor'] != who) 'بواسطة ${e['actor']}',
                if ((e['ip'] ?? '').toString().isNotEmpty) 'IP ${e['ip']}',
                auth ? 'سجل المصادقة' : 'سجل التدقيق',
              ].join(' · '),
              style: TextStyle(color: sem.muted, fontSize: 11.5),
            ),
          ]),
        ),
      ]),
    );
  }

  // ---------------------------------------------------------------- الحسابات
  Widget _accountsView(BuildContext context, AppState app) {
    final sem = Sem.of(context);
    final list = [..._users]..sort((a, b) {
        final la = a['locked_until'] != null ? 0 : 1, lb = b['locked_until'] != null ? 0 : 1;
        if (la != lb) return la.compareTo(lb);
        return (b['last_sign_in_at'] ?? '').toString().compareTo((a['last_sign_in_at'] ?? '').toString());
      });
    return SectionCard(
      title: 'الحسابات وحالة الدخول',
      icon: Icons.manage_accounts_outlined,
      subtitle: 'آخر دخول، والأجهزة والجلسات، وحالة القفل. الإجراءات: قفل الدخول مؤقتاً أو حتى يُفك، والإخراج من كل الأجهزة.',
      child: Column(children: [
        for (final u in list) _account(context, app, u),
      ]),
    );
  }

  Widget _account(BuildContext context, AppState app, Map<String, dynamic> u) {
    final sem = Sem.of(context);
    final id = u['id'].toString();
    final name = _nameOf(id);
    final role = parseRole(u['role']);
    final locked = u['locked_until'] != null;
    final until = DateTime.tryParse((u['locked_until'] ?? '').toString());
    final active = u['active'] == true;
    final can = _canAct(app, id);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      onTap: () => openUserDetails(context, id),
      leading: InitialsAvatar(name: name, color: locked ? sem.danger : (active ? null : sem.muted)),
      title: Wrap(spacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
        Text(name, style: const TextStyle(fontWeight: FontWeight.w700)),
        if (locked) ToneBadge(until == null || until.year >= 9999 ? 'مقفل حتى يُفك' : 'مقفل حتى ${fmtDate(until)}', color: sem.danger, icon: Icons.lock_clock_outlined),
        if (!active) ToneBadge(role == null ? 'بانتظار التفعيل' : 'موقوف', color: sem.muted),
        if (u['mfa'] == true) ToneBadge('تحقق', color: sem.ok, icon: Icons.verified_user_outlined),
      ]),
      subtitle: Text([
        role?.label ?? 'بلا دور',
        'آخر دخول ${u['last_sign_in_at'] == null ? '—' : fmtDate(DateTime.tryParse(u['last_sign_in_at'].toString()))}',
        '${(u['devices'] as num?)?.toInt() ?? 0} جهاز',
        '${(u['sessions'] as num?)?.toInt() ?? 0} جلسة',
        if (locked && (u['lock_reason'] ?? '').toString().isNotEmpty) 'السبب: ${u['lock_reason']}',
      ].join(' · ')),
      trailing: !can
          ? null
          : PopupMenuButton<String>(
              tooltip: 'إجراءات أمنية',
              onSelected: (v) async {
                if (v == 'lock') {
                  final done = await showLockDialog(context, app, id, name);
                  if (done) await _load();
                } else if (v == 'unlock') {
                  await runAction(context, () => app.unlockUser(id), success: 'فُك قفل دخول $name');
                  await _load();
                } else if (v == 'signout') {
                  final ok = await confirmDialog(context,
                      title: 'إخراج $name من كل أجهزته؟', message: 'يُطلب منه الدخول من جديد على كل جهاز.', confirmLabel: 'إخراج');
                  if (!ok || !context.mounted) return;
                  await runAction(context, () async {
                    final n = await app.revokeUserSessions(id);
                    if (context.mounted) showToast(context, 'أُنهيت $n جلسة');
                  });
                  await _load();
                } else if (v == 'trace') {
                  setState(() {
                    _user = id;
                    _view = 'timeline';
                  });
                  await _reloadTimeline();
                }
              },
              itemBuilder: (_) => [
                if (locked)
                  const PopupMenuItem(value: 'unlock', child: ListTile(leading: Icon(Icons.lock_open_rounded), title: Text('فك القفل')))
                else
                  const PopupMenuItem(value: 'lock', child: ListTile(leading: Icon(Icons.lock_clock_outlined), title: Text('قفل الدخول'))),
                const PopupMenuItem(value: 'signout', child: ListTile(leading: Icon(Icons.logout_rounded), title: Text('إخراج من كل الأجهزة'))),
                const PopupMenuItem(value: 'trace', child: ListTile(leading: Icon(Icons.timeline_rounded), title: Text('الحركة الدقيقة'))),
              ],
            ),
    );
  }

  // ---------------------------------------------------------------- التفعيلات
  Widget _activationsView(BuildContext context, AppState app) {
    final sem = Sem.of(context);
    final rows = _timeline.where((e) => e['source'] == 'app' && (e['action'] ?? '').toString().startsWith('user.')).toList();
    final activatedUsers = _users.where((u) => u['activated_at'] != null).toList()
      ..sort((a, b) => (b['activated_at'] ?? '').toString().compareTo((a['activated_at'] ?? '').toString()));
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SectionCard(
        title: 'الحسابات المفعّلة',
        icon: Icons.how_to_reg_outlined,
        subtitle: 'متى فُعّل كل حساب ومن فعّله.',
        child: Column(children: [
          for (final u in activatedUsers)
            ListTile(
              contentPadding: EdgeInsets.zero,
              onTap: () => openUserDetails(context, u['id'].toString()),
              leading: InitialsAvatar(name: _nameOf(u['id'].toString())),
              title: Text(_nameOf(u['id'].toString())),
              subtitle: Text([
                parseRole(u['role'])?.label ?? '',
                'فُعّل ${fmtDate(DateTime.tryParse(u['activated_at'].toString()))}',
                if ((u['activated_by_name'] ?? '').toString().isNotEmpty) 'بواسطة ${u['activated_by_name']}',
              ].join(' · ')),
            ),
          if (activatedUsers.isEmpty) Text('لا توجد بيانات تفعيل.', style: TextStyle(color: sem.muted)),
        ]),
      ),
      const SizedBox(height: 14),
      SectionCard(
        title: 'تغييرات الحسابات في المدة المختارة',
        icon: Icons.manage_history_rounded,
        subtitle: 'التفعيل والإيقاف وتغيير الدور والبريد والحذف (من «الحركة الدقيقة» بمدة ${_days == 1 ? 'يوم' : '$_days يوماً'}).',
        child: rows.isEmpty
            ? Text('لا تغييرات في هذه المدة.', style: TextStyle(color: sem.muted))
            : Column(children: [for (final e in rows) _event(context, app, e)]),
      ),
    ]);
  }
}

/// نافذة قفل الدخول: المدة والسبب. تُرجع true عند التنفيذ.
Future<bool> showLockDialog(BuildContext context, AppState app, String userId, String name) async {
  final reason = TextEditingController();
  int? minutes = 60;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(builder: (ctx, setS) {
      final sem = Sem.of(ctx);
      return AlertDialog(
        title: Text('قفل دخول $name'),
        content: SizedBox(
          width: 460,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('تنتهي جلساته فوراً، ولا يستطيع الدخول حتى تنتهي المدة أو يُفك القفل. يرى السبب عند محاولة الدخول.',
                style: TextStyle(color: sem.muted, height: 1.5)),
            const SizedBox(height: 12),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final o in const [(15, '15 دقيقة'), (60, 'ساعة'), (240, '4 ساعات'), (1440, 'يوم'), (10080, 'أسبوع'), (-1, 'حتى يُفك')])
                ChoiceChip(
                  label: Text(o.$2),
                  selected: (minutes ?? -1) == o.$1,
                  onSelected: (_) => setS(() => minutes = o.$1 < 0 ? null : o.$1),
                ),
            ]),
            const SizedBox(height: 12),
            TextField(controller: reason, autofocus: true, maxLines: 2, decoration: fieldDeco('السبب (يظهر له ويُسجَّل)')),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('إلغاء')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: sem.danger, foregroundColor: Colors.white),
            onPressed: () {
              if (reason.text.trim().length < 3) return;
              Navigator.of(ctx).pop(true);
            },
            child: const Text('قفل الدخول'),
          ),
        ],
      );
    }),
  );
  if (ok != true || !context.mounted) {
    reason.dispose();
    return false;
  }
  final r = reason.text.trim();
  reason.dispose();
  return runAction(context, () async {
    final n = await app.lockUser(userId, minutes: minutes, reason: r);
    if (context.mounted) showToast(context, 'أُقفل دخول $name وأُنهيت $n جلسة');
  });
}
