import 'package:flutter/material.dart';

import '../../app_state.dart';
import '../../models.dart';
import '../../ui/theme.dart';
import '../../ui/widgets.dart';
import '../../services/export.dart';
import '../../units.dart';
import 'control_panel.dart';
import 'user_details.dart';

/// المستخدمون والأدوار: البيانات الكاملة، والتفعيل والإيقاف والدور والقسم والبريد، والحذف.
class UsersSection extends StatefulWidget {
  const UsersSection({super.key});

  @override
  State<UsersSection> createState() => _UsersSectionState();
}

class _UsersSectionState extends State<UsersSection> {
  String _filter = 'all';
  String _q = '';

  bool _exporting = false;

  static String roleTextOf(AppState app, Profile u) {
    if (u.role == AppRole.director) return 'مدير المكتب · المسؤول الأول والأخير';
    if (u.role == null) return 'بانتظار التفعيل';
    var r = u.role == AppRole.deptHead ? 'رئيس قسم ${app.departmentName(u.department)}' : u.role!.label;
    if (u.unit != null) r = '$r · ${u.unitHead ? 'رئيس ' : ''}${unitNames[u.unit] ?? u.unit}';
    return u.active ? r : '$r · موقوف';
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final sem = Sem.of(context);
    final q = normalizeArabic(_q);
    final all = app.people.values.toList();
    final users = all.where((u) {
      final ok = switch (_filter) {
        'pending' => !u.active && u.role == null,
        'active' => u.active,
        'disabled' => !u.active && u.role != null,
        _ => true,
      };
      if (!ok) return false;
      if (q.isNotEmpty && !normalizeArabic('${u.displayName} ${u.email} ${roleTextOf(app, u)}').contains(q)) return false;
      return true;
    }).toList()
      ..sort((a, b) {
        int rank(Profile p) => p.role == AppRole.director ? 0 : (!p.active && p.role == null ? 1 : (p.active ? 2 : 3));
        final r = rank(a).compareTo(rank(b));
        return r != 0 ? r : a.displayName.compareTo(b.displayName);
      });
    int count(String f) => all.where((u) => switch (f) {
          'pending' => !u.active && u.role == null,
          'active' => u.active,
          'disabled' => !u.active && u.role != null,
          _ => true,
        }).length;

    return PageBody(
      onRefresh: app.loadAll,
      children: [
        PageHeader(
          icon: Icons.group_outlined,
          title: 'المستخدمون والأدوار',
          subtitle: app.isDirector
              ? 'اضغط أي مستخدم لعرض بياناته كاملة وتعديل صلاحياته أو حذفه. ينشئ الموظف حسابه من شاشة الدخول فيظهر هنا «بانتظار التفعيل». دور مدير المكتب لا يُمنح من التطبيق.'
              : 'اضغط أي مستخدم لعرض بياناته كاملة: الحساب والأمان والأجهزة وسجل الدخول والنشاط. للاطلاع فقط.',
          actions: [
            OutlinedButton.icon(
              onPressed: _exporting ? null : () => _export(app),
              icon: _exporting
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.download_rounded),
              label: const Text('تصدير Excel'),
            ),
          ],
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final f in const [('all', 'الكل'), ('pending', 'بانتظار التفعيل'), ('active', 'مفعّلون'), ('disabled', 'موقوفون')])
              ChoiceChip(
                label: Text('${f.$2} (${count(f.$1)})'),
                selected: _filter == f.$1,
                showCheckmark: false,
                onSelected: (_) => setState(() => _filter = f.$1),
              ),
          ],
        ),
        const SizedBox(height: 12),
        TextField(
          decoration: fieldDeco('بحث بالاسم أو البريد أو الدور', prefixIcon: const Icon(Icons.search)),
          onChanged: (v) => setState(() => _q = v),
        ),
        const SizedBox(height: 14),
        if (users.isEmpty) const EmptyState(icon: Icons.person_search_outlined, title: 'لا يوجد مستخدمون بهذا التصنيف'),
        for (final u in users)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Material(
              color: sem.surface,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: sem.rule)),
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () => openUserDetails(context, u.id),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      InitialsAvatar(
                        name: u.displayName,
                        color: u.role == AppRole.director
                            ? Theme.of(context).colorScheme.primary
                            : (u.active ? sem.ok : (u.role == null ? sem.wip : sem.muted)),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(u.displayName, style: const TextStyle(fontWeight: FontWeight.w700)),
                            Text(u.email, textDirection: TextDirection.ltr, style: TextStyle(color: sem.muted, fontSize: 12.5)),
                            const SizedBox(height: 4),
                            ToneBadge(roleTextOf(app, u),
                                color: u.role == AppRole.director
                                    ? Theme.of(context).colorScheme.primary
                                    : (u.active ? sem.ok : (u.role == null ? sem.wip : sem.danger))),
                          ],
                        ),
                      ),
                      Icon(Icons.chevron_left_rounded, color: sem.muted),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Future<void> _export(AppState app) async {
    setState(() => _exporting = true);
    try {
      final rows = app.v2Ready ? await app.securityUsers() : const <Map<String, dynamic>>[];
      final path = await exportUsersXlsx(app, rows);
      if (mounted && path != null) showToast(context, 'حُفظ الملف: $path');
    } catch (e) {
      if (mounted) showToast(context, friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }
}

/// نافذة تعديل صلاحيات مستخدم (لمدير المكتب).
Future<void> openUserEditor(BuildContext context, AppState app, Profile u) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
      child: _UserEditor(app: app, user: u),
    ),
  );
}

class _UserEditor extends StatefulWidget {
  const _UserEditor({required this.app, required this.user});

  final AppState app;
  final Profile user;

  @override
  State<_UserEditor> createState() => _UserEditorState();
}

class _UserEditorState extends State<_UserEditor> {
  late String _role;
  late String _department;
  late bool _active;
  late String _unit;
  late bool _unitHead;
  late final TextEditingController _name;
  late final TextEditingController _email;
  bool _busy = false;
  String? _error;

  static const _roles = [AppRole.officeStaff, AppRole.deptHead, AppRole.contracts, AppRole.planningQa, AppRole.securityAuditor, AppRole.employee];

  @override
  void initState() {
    super.initState();
    final u = widget.user;
    _role = u.role?.db ?? '';
    _department = u.department ?? 'supervision';
    _active = u.active || u.role == null;
    _unit = u.unit ?? '';
    _unitHead = u.unitHead;
    _name = TextEditingController(text: u.fullName);
    _email = TextEditingController(text: u.email);
  }

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final role = parseRole(_role);
    if (_active && role == null) {
      setState(() => _error = 'اختر الدور قبل التفعيل.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final newEmail = _email.text.trim().toLowerCase();
      if (newEmail.isNotEmpty && newEmail != widget.user.email.toLowerCase()) {
        await widget.app.setUserEmail(widget.user.id, newEmail);
      }
      await widget.app.setUserAccess(widget.user.id, role: role, department: _department, active: _active, fullName: _name.text.trim());
      // الوحدة (الترحيل 21): تُحفظ إن تغيّرت، ولا تُسند لمدقق الأمن
      final unit = role == AppRole.securityAuditor || role == AppRole.employee ? '' : _unit;
      final head = unit.isNotEmpty && _unitHead;
      if (widget.app.v9Ready && (unit != (widget.user.unit ?? '') || head != widget.user.unitHead)) {
        await widget.app.setUserUnit(widget.user.id, unit.isEmpty ? null : unit, head);
      }
      if (!_active && widget.user.active && widget.app.v2Ready) {
        try {
          await widget.app.revokeUserSessions(widget.user.id);
        } catch (_) {}
      }
      if (!mounted) return;
      showToast(context, _active ? 'حُفظت صلاحيات ${_name.text.trim()}' : 'أُوقف الحساب وأُخرج من أجهزته');
      Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = friendlyError(e);
        });
      }
    }
  }

  Future<void> _signOutEverywhere() async {
    final ok = await confirmDialog(context,
        title: 'إخراج ${widget.user.displayName} من كل أجهزته؟',
        message: 'يُطلب منه الدخول من جديد على كل جهاز.',
        confirmLabel: 'إخراج');
    if (!ok || !mounted) return;
    await runAction(context, () async {
      final n = await widget.app.revokeUserSessions(widget.user.id);
      if (mounted) showToast(context, 'أُنهيت $n جلسة');
    });
  }

  Future<void> _resetMfa() async {
    final ok = await confirmDialog(context,
        title: 'إلغاء التحقق بخطوتين؟',
        message: 'استخدمه إذا فقد ${widget.user.displayName} هاتفه. يدخل بكلمة المرور ثم يفعّل التحقق من جديد.',
        confirmLabel: 'إلغاء التحقق',
        danger: true);
    if (!ok || !mounted) return;
    await runAction(context, () async {
      final n = await widget.app.resetUserMfa(widget.user.id);
      if (mounted) showToast(context, n > 0 ? 'أُلغي التحقق بخطوتين' : 'لم يكن التحقق مفعّلاً لهذا المستخدم');
    });
  }

  @override
  Widget build(BuildContext context) {
    final sem = Sem.of(context);
    final u = widget.user;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                InitialsAvatar(name: u.displayName, size: 44),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(u.role == null ? 'تفعيل حساب' : 'صلاحيات المستخدم',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(controller: _name, decoration: fieldDeco('الاسم الكامل')),
            const SizedBox(height: 12),
            TextField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              textDirection: TextDirection.ltr,
              decoration: fieldDeco('بريد الدخول', helper: 'تغييره فوري، وكلمة المرور تبقى كما هي'),
            ),
            const SizedBox(height: 12),
            SelectField(
              label: 'الدور',
              value: _role,
              items: [('', 'اختر الدور'), for (final r in _roles) (r.db, r.label)],
              onChanged: (v) => setState(() => _role = v),
            ),
            if (parseRole(_role) != null) ...[
              const SizedBox(height: 6),
              Text(parseRole(_role)!.summary, style: TextStyle(color: sem.muted, fontSize: 12.5)),
            ],
            if (_role == AppRole.securityAuditor.db) ...[
              const SizedBox(height: 8),
              const InfoBanner(
                level: 'warning',
                icon: Icons.phonelink_lock_outlined,
                text: 'يُطلب منه تفعيل التحقق بخطوتين عند دخوله، ولا يرى شيئاً قبل ذلك.',
              ),
            ],
            if (_role == AppRole.deptHead.db) ...[
              const SizedBox(height: 12),
              SelectField(
                label: 'القسم',
                value: _department,
                items: [for (final d in widget.app.departments) (d.key, d.name)],
                onChanged: (v) => setState(() => _department = v),
              ),
            ],
            if (_role == AppRole.employee.db) ...[
              const SizedBox(height: 8),
              const InfoBanner(
                icon: Icons.person_pin_outlined,
                text: 'لا يرى إلا صفحته في قسم المخازن («ما صُرف لي») ودليل الاستخدام. اربطه بسجله من «الإدارات والموظفون» في المخازن.',
              ),
            ],
            if (widget.app.v9Ready && _role.isNotEmpty && _role != AppRole.securityAuditor.db && _role != AppRole.employee.db) ...[
              const SizedBox(height: 12),
              SelectField(
                label: 'الوحدة',
                value: _unit,
                items: [('', 'دون وحدة'), for (final k in unitKeys) (k, unitNames[k]!)],
                onChanged: (v) => setState(() {
                  _unit = v;
                  if (v.isEmpty) _unitHead = false;
                }),
              ),
              const SizedBox(height: 4),
              Text('يكتب في سجلات وحدته، ويطّلع على باقي الوحدات.', style: TextStyle(color: sem.muted, fontSize: 12.5)),
              if (_unit.isNotEmpty)
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('رئيس الوحدة'),
                  subtitle: Text('يحذف سجلات وحدته ومرفقاتها', style: TextStyle(color: sem.muted)),
                  value: _unitHead,
                  onChanged: (v) => setState(() => _unitHead = v),
                ),
            ],
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('الحساب مفعّل'),
              subtitle: Text(_active ? 'يدخل المنظومة بصلاحيات دوره' : 'لا يستطيع الدخول، ويُخرج من أجهزته', style: TextStyle(color: sem.muted)),
              value: _active,
              onChanged: (v) => setState(() => _active = v),
            ),
            if (widget.app.v2Ready && u.role != null) ...[
              Divider(color: sem.rule),
              SettingRow(icon: Icons.logout_rounded, title: 'إخراج من كل الأجهزة', subtitle: 'ينهي جلساته المفتوحة فوراً', onTap: _signOutEverywhere),
              SettingRow(
                icon: Icons.phonelink_erase_rounded,
                title: 'إلغاء التحقق بخطوتين',
                subtitle: 'عند فقدان الهاتف',
                danger: true,
                onTap: _resetMfa,
              ),
            ],
            if (_error != null) ...[const SizedBox(height: 8), InfoBanner(text: _error!, level: 'critical')],
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(child: OutlinedButton(onPressed: _busy ? null : () => Navigator.of(context).pop(), child: const Text('إلغاء'))),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    onPressed: _busy ? null : _save,
                    child: _busy
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : Text(u.role == null ? 'تفعيل' : 'حفظ'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
