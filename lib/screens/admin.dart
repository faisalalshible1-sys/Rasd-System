import 'package:flutter/material.dart';

import '../app_state.dart';
import '../models.dart';
import '../ui/audit_text.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';

/// شاشة الإدارة — للمدير وحده: UC-16 المستخدمون، UC-17 صلاحيات النماذج، UC-19 سجل التدقيق.
class AdminPage extends StatelessWidget {
  const AdminPage({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    if (!app.isDirector) {
      return const Center(child: EmptyState(icon: Icons.lock_outline, title: 'هذه الشاشة لمدير المكتب وحده'));
    }
    final pendingUsers = app.people.values.where((p) => !p.active && p.role != AppRole.director).length;
    return DefaultTabController(
      length: 3,
      child: Column(
        children: [
          Material(
            color: Sem.of(context).surface,
            child: TabBar(tabs: [
              Tab(text: pendingUsers > 0 ? 'المستخدمون ($pendingUsers جديد)' : 'المستخدمون'),
              const Tab(text: 'صلاحيات النماذج'),
              const Tab(text: 'سجل التدقيق'),
            ]),
          ),
          const Expanded(child: TabBarView(children: [_UsersTab(), _FormsTab(), _AuditTab()])),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------
// المستخدمون
// ---------------------------------------------------------------------
class _UsersTab extends StatelessWidget {
  const _UsersTab();

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final sem = Sem.of(context);
    final users = app.people.values.toList()
      ..sort((a, b) {
        int rank(Profile p) => p.role == AppRole.director ? 0 : (!p.active && p.role == null ? 1 : (p.active ? 2 : 3));
        final r = rank(a).compareTo(rank(b));
        return r != 0 ? r : a.displayName.compareTo(b.displayName);
      });
    return RefreshIndicator(
      onRefresh: app.loadAll,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'ينشئ الموظف حسابه من شاشة الدخول، ثم يظهر هنا «بانتظار التفعيل». اختر دوره وفعّله. دور مدير المكتب لا يُمنح من التطبيق.',
            style: TextStyle(color: sem.muted, fontSize: 13),
          ),
          const SizedBox(height: 12),
          for (final u in users)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Material(
                color: sem.surface,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: sem.rule)),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: u.role == AppRole.director
                        ? Theme.of(context).colorScheme.primary
                        : (u.active ? sem.okSoft : sem.wipSoft),
                    foregroundColor: u.role == AppRole.director ? Colors.white : (u.active ? sem.ok : sem.wip),
                    child: Icon(u.role == AppRole.director
                        ? Icons.workspace_premium
                        : (u.active ? Icons.person : Icons.hourglass_top)),
                  ),
                  title: Text(u.displayName, style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text(
                    '${u.email}\n${_roleText(app, u)}',
                    style: TextStyle(color: sem.muted, fontSize: 12.5),
                  ),
                  isThreeLine: true,
                  trailing: u.role == AppRole.director || u.id == app.me?.id ? null : const Icon(Icons.edit_outlined),
                  onTap: u.role == AppRole.director || u.id == app.me?.id ? null : () => _editUser(context, app, u),
                ),
              ),
            ),
        ],
      ),
    );
  }

  static String _roleText(AppState app, Profile u) {
    if (u.role == AppRole.director) return 'مدير المكتب · المسؤول الأول والأخير';
    if (u.role == null) return 'بانتظار التفعيل';
    final r = u.role == AppRole.deptHead ? 'رئيس قسم ${app.departmentName(u.department)}' : u.role!.label;
    return u.active ? r : '$r · موقوف';
  }

  Future<void> _editUser(BuildContext context, AppState app, Profile u) async {
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
  late final TextEditingController _name;
  bool _busy = false;
  String? _error;

  static const _roles = [AppRole.officeStaff, AppRole.deptHead, AppRole.contracts, AppRole.planningQa];

  @override
  void initState() {
    super.initState();
    final u = widget.user;
    _role = u.role?.db ?? '';
    _department = u.department ?? 'supervision';
    _active = u.active || u.role == null;
    _name = TextEditingController(text: u.fullName);
  }

  @override
  void dispose() {
    _name.dispose();
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
      await widget.app.setUserAccess(widget.user.id,
          role: role, department: _department, active: _active, fullName: _name.text.trim());
      if (!mounted) return;
      showToast(context, _active ? 'حُفظت صلاحيات ${_name.text.trim()}' : 'أُوقف الحساب');
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
            Text(u.role == null ? 'تفعيل حساب' : 'صلاحيات المستخدم',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
            Text(u.email, textDirection: TextDirection.ltr, textAlign: TextAlign.end, style: TextStyle(color: sem.muted)),
            const SizedBox(height: 16),
            TextField(controller: _name, decoration: fieldDeco('الاسم الكامل')),
            const SizedBox(height: 12),
            SelectField(
              label: 'الدور',
              value: _role,
              items: [('', 'اختر الدور'), for (final r in _roles) (r.db, r.label)],
              onChanged: (v) => setState(() => _role = v),
            ),
            if (_role == AppRole.deptHead.db) ...[
              const SizedBox(height: 12),
              SelectField(
                label: 'القسم',
                value: _department,
                items: [for (final d in widget.app.departments) (d.key, d.name)],
                onChanged: (v) => setState(() => _department = v),
              ),
            ],
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('الحساب مفعّل'),
              subtitle: Text(_active ? 'يدخل المنظومة بصلاحيات دوره' : 'لا يستطيع الدخول', style: TextStyle(color: sem.muted)),
              value: _active,
              onChanged: (v) => setState(() => _active = v),
            ),
            if (_error != null) Text(_error!, style: TextStyle(color: sem.danger)),
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

// ---------------------------------------------------------------------
// صلاحيات النماذج
// ---------------------------------------------------------------------
class _FormsTab extends StatefulWidget {
  const _FormsTab();

  @override
  State<_FormsTab> createState() => _FormsTabState();
}

class _FormsTabState extends State<_FormsTab> {
  String? _busyKey;

  Future<void> _update(AppState app, FormDef d, {bool? sensitive, List<String>? responsible}) async {
    setState(() => _busyKey = d.key);
    try {
      await app.updateFormDef(d.key, sensitive: sensitive, responsible: responsible);
      if (mounted) showToast(context, 'حُفظت صلاحيات «${d.name}»');
    } catch (e) {
      if (mounted) showToast(context, friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _busyKey = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final sem = Sem.of(context);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'حدّد من يحدّث كل نموذج، وأي النماذج حساسة. تغيير النموذج الحساس من غيرك يرفع طلب اعتماد إليك. مدير المكتب يحدّث كل النماذج مباشرة.',
          style: TextStyle(color: sem.muted, fontSize: 13),
        ),
        const SizedBox(height: 12),
        for (var s = 0; s < stageNames.length; s++) ...[
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 6),
            child: Text('${s + 1}. ${stageNames[s]}', style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
          for (final d in app.formDefs.where((d) => d.stage == s))
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: sem.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: sem.rule)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(child: Text(d.name, style: const TextStyle(fontWeight: FontWeight.w700))),
                        if (_busyKey == d.key)
                          const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 8),
                            child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                          ),
                        Text('حساس', style: TextStyle(color: d.sensitive ? sem.wip : sem.muted, fontSize: 12.5)),
                        Switch(
                          value: d.sensitive,
                          onChanged: _busyKey != null ? null : (v) => _update(app, d, sensitive: v),
                        ),
                      ],
                    ),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final t in responsibleLabels.keys)
                          FilterChip(
                            label: Text(responsibleLabels[t]!, style: const TextStyle(fontSize: 12.5)),
                            selected: d.responsible.contains(t),
                            onSelected: _busyKey != null
                                ? null
                                : (sel) {
                                    final next = [...d.responsible];
                                    if (sel) {
                                      next.add(t);
                                    } else {
                                      next.remove(t);
                                    }
                                    _update(app, d, responsible: next);
                                  },
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------------
// سجل التدقيق
// ---------------------------------------------------------------------
class _AuditTab extends StatefulWidget {
  const _AuditTab();

  @override
  State<_AuditTab> createState() => _AuditTabState();
}

class _AuditTabState extends State<_AuditTab> {
  List<AuditEntry>? _rows;
  String? _error;
  String _actor = '';
  String _kind = '';
  String _q = '';

  static const _kinds = [
    ('', 'كل العمليات'),
    ('form.', 'حالات النماذج'),
    ('request.', 'طلبات الاعتماد'),
    ('project.', 'بيانات المشاريع'),
    ('user.', 'المستخدمون'),
    ('form_def.', 'صلاحيات النماذج'),
    ('note.', 'ملاحظات التقييم'),
  ];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_rows == null && _error == null) _load();
  }

  Future<void> _load() async {
    try {
      final rows = await AppScope.read(context).loadAudit(limit: 500);
      if (mounted) setState(() {
        _rows = rows;
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final sem = Sem.of(context);
    final rows = _rows;
    if (_error != null) {
      return EmptyState(icon: Icons.cloud_off, title: 'تعذّر تحميل السجل', message: _error, action: FilledButton(onPressed: _load, child: const Text('إعادة المحاولة')));
    }
    if (rows == null) return const Center(child: CircularProgressIndicator());
    final actors = <String, String>{};
    for (final r in rows) {
      if (r.actor != null) actors[r.actor!] = r.actorName.isEmpty ? app.personName(r.actor) : r.actorName;
    }
    final q = normalizeArabic(_q);
    final shown = rows.where((r) {
      if (_actor.isNotEmpty && r.actor != _actor) return false;
      if (_kind.isNotEmpty && !r.action.startsWith(_kind)) return false;
      if (q.isNotEmpty && !normalizeArabic('${r.projectLabel} ${auditDescription(app, r)} ${r.actorName}').contains(q)) return false;
      return true;
    }).toList();

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          LayoutBuilder(builder: (context, c) {
            final a = SelectField(
              label: 'المستخدم',
              value: _actor,
              items: [('', 'الجميع'), for (final e in actors.entries) (e.key, e.value)],
              onChanged: (v) => setState(() => _actor = v),
            );
            final k = SelectField(label: 'العملية', value: _kind, items: _kinds, onChanged: (v) => setState(() => _kind = v));
            return c.maxWidth < 520
                ? Column(children: [a, const SizedBox(height: 10), k])
                : Row(children: [Expanded(child: a), const SizedBox(width: 10), Expanded(child: k)]);
          }),
          const SizedBox(height: 10),
          TextField(
            decoration: fieldDeco('بحث في السجل', prefixIcon: const Icon(Icons.search)),
            onChanged: (v) => setState(() => _q = v),
          ),
          const SizedBox(height: 8),
          Text('${shown.length} سطراً · آخر 500 عملية', style: TextStyle(color: sem.muted, fontSize: 12.5)),
          const SizedBox(height: 8),
          for (final r in shown)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(border: Border(bottom: BorderSide(color: sem.rule))),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(r.actorName.isEmpty ? 'النظام' : r.actorName,
                            style: const TextStyle(fontWeight: FontWeight.w700)),
                      ),
                      Text(fmtDate(r.at), style: TextStyle(color: sem.muted, fontSize: 12)),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(auditDescription(app, r)),
                  if (r.projectId != null && r.projectLabel.isNotEmpty && !r.action.startsWith('project.'))
                    Text(r.projectLabel, style: TextStyle(color: sem.muted, fontSize: 12.5), maxLines: 1, overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
