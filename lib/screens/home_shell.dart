import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../app_state.dart';
import '../models.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';
import 'admin.dart';
import 'analysis.dart';
import 'dashboard.dart';
import 'project_detail.dart';
import 'projects.dart';
import 'requests.dart';

class _Dest {
  const _Dest(this.label, this.icon, this.selectedIcon, this.page, {this.badge = 0});

  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final Widget page;
  final int badge;
}

/// الهيكل الرئيسي: شريط تنقل سفلي على الهاتف، وشريط جانبي على الشاشات العريضة.
class HomeShell extends StatelessWidget {
  const HomeShell({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final requestsBadge = app.isDirector ? app.pendingRequests.length : app.myRequests.where((r) => r.isPending).length;
    final dests = <_Dest>[
      const _Dest('الرئيسية', Icons.space_dashboard_outlined, Icons.space_dashboard, DashboardPage()),
      const _Dest('المشاريع', Icons.list_alt_outlined, Icons.list_alt, ProjectsPage()),
      _Dest(app.isDirector ? 'الاعتمادات' : 'طلباتي', Icons.fact_check_outlined, Icons.fact_check, const RequestsPage(),
          badge: requestsBadge),
      const _Dest('التحليل', Icons.insights_outlined, Icons.insights, AnalysisPage()),
      if (app.isDirector) const _Dest('الإدارة', Icons.admin_panel_settings_outlined, Icons.admin_panel_settings, AdminPage()),
    ];
    final int index = (app.tab >= 0 && app.tab < dests.length) ? app.tab : 0;
    final wide = MediaQuery.sizeOf(context).width >= 840;

    Widget icon(_Dest d, bool selected) {
      final i = Icon(selected ? d.selectedIcon : d.icon);
      return d.badge > 0 ? Badge(label: Text('${d.badge}'), child: i) : i;
    }

    final body = Column(
      children: [
        if (app.loadError != null)
          MaterialBanner(
            content: Text(app.loadError!),
            actions: [TextButton(onPressed: app.loadAll, child: const Text('إعادة المحاولة'))],
          ),
        Expanded(child: dests[index].page),
      ],
    );

    return Scaffold(
      appBar: brandAppBar(
        context,
        showEmblem: true,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(dests[index].label, style: const TextStyle(fontWeight: FontWeight.w700)),
            Text('الدورة المستندية · مكتب الشؤون الهندسية',
                maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11.5, color: Sem.of(context).muted)),
          ],
        ),
        actions: [
          if (app.loading)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Sem.of(context).muted)),
            ),
          IconButton(
            tooltip: 'الإشعارات',
            onPressed: () => _showNotifications(context),
            icon: app.unreadCount > 0
                ? Badge(label: Text('${app.unreadCount}'), child: const Icon(Icons.notifications_outlined))
                : const Icon(Icons.notifications_outlined),
          ),
          _AccountMenu(app: app),
        ],
      ),
      floatingActionButton: dests[index].page is ProjectsPage && app.canManageProjects
          ? FloatingActionButton.extended(
              onPressed: () => openProjectEditor(context, null),
              icon: const Icon(Icons.add),
              label: const Text('مشروع جديد'),
            )
          : null,
      bottomNavigationBar: wide
          ? null
          : NavigationBar(
              selectedIndex: index,
              onDestinationSelected: app.setTab,
              destinations: [
                for (final d in dests)
                  NavigationDestination(icon: icon(d, false), selectedIcon: icon(d, true), label: d.label),
              ],
            ),
      body: wide
          ? Row(
              children: [
                NavigationRail(
                  selectedIndex: index,
                  onDestinationSelected: app.setTab,
                  labelType: NavigationRailLabelType.all,
                  destinations: [
                    for (final d in dests)
                      NavigationRailDestination(icon: icon(d, false), selectedIcon: icon(d, true), label: Text(d.label)),
                  ],
                ),
                const VerticalDivider(width: 1),
                Expanded(child: body),
              ],
            )
          : body,
    );
  }

  Future<void> _showNotifications(BuildContext context) async {
    final app = AppScope.read(context);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => _NotificationsSheet(app: app, parentContext: context),
    );
    try {
      await app.markNotificationsRead();
    } catch (_) {}
  }
}

class _NotificationsSheet extends StatelessWidget {
  const _NotificationsSheet({required this.app, required this.parentContext});

  final AppState app;
  final BuildContext parentContext;

  @override
  Widget build(BuildContext context) {
    final sem = Sem.of(context);
    final items = app.notifications;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.75),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text('الإشعارات', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
            ),
            if (items.isEmpty)
              const EmptyState(icon: Icons.notifications_none, title: 'لا توجد إشعارات')
            else
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: items.length,
                  separatorBuilder: (_, __) => Divider(height: 1, color: sem.rule),
                  itemBuilder: (ctx, i) {
                    final n = items[i];
                    return ListTile(
                      leading: Icon(
                        switch (n.kind) {
                          'request' => Icons.fact_check_outlined,
                          'decision' => Icons.gavel_outlined,
                          'signup' => Icons.person_add_alt,
                          'activated' => Icons.verified_user_outlined,
                          _ => Icons.notifications_outlined,
                        },
                        color: n.unread ? Theme.of(context).colorScheme.primary : sem.muted,
                      ),
                      title: Text(n.title, style: TextStyle(fontWeight: n.unread ? FontWeight.w700 : FontWeight.w500)),
                      subtitle: Text('${n.body}\n${fmtDate(n.createdAt)}'),
                      isThreeLine: true,
                      onTap: () {
                        Navigator.of(ctx).pop();
                        if (n.kind == 'request' || n.kind == 'decision') {
                          app.setTab(2);
                        } else if (n.kind == 'signup' && app.isDirector) {
                          app.setTab(4);
                        }
                        final pid = n.projectId;
                        if (pid != null && app.project(pid) != null && n.kind != 'request') {
                          Navigator.of(parentContext).push(MaterialPageRoute<void>(builder: (_) => ProjectDetailPage(projectId: pid)));
                        }
                      },
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _AccountMenu extends StatelessWidget {
  const _AccountMenu({required this.app});

  final AppState app;

  @override
  Widget build(BuildContext context) {
    final me = app.me;
    final roleText = me?.role == AppRole.deptHead
        ? 'رئيس قسم ${app.departmentName(me?.department)}'
        : (me?.role?.label ?? '');
    return PopupMenuButton<String>(
      tooltip: 'الحساب',
      icon: const Icon(Icons.account_circle_outlined),
      onSelected: (v) async {
        if (v == 'name') {
          final name = await textInputDialog(context,
              title: 'تعديل الاسم', label: 'الاسم الكامل', confirmLabel: 'حفظ', required: true);
          if (name == null) return;
          try {
            await app.updateMyName(name);
            if (context.mounted) showToast(context, 'حُفظ الاسم');
          } catch (e) {
            if (context.mounted) showToast(context, friendlyError(e), error: true);
          }
        } else if (v == 'email') {
          if (!app.isDirector) {
            showToast(context, 'يغيّر مدير المكتب بريد الدخول من شاشة الإدارة. تواصل معه.');
            return;
          }
          final email = await textInputDialog(context,
              title: 'تغيير بريد الدخول',
              message: 'سيُستخدم البريد الجديد للدخول من الآن. كلمة المرور لا تتغير.',
              label: 'البريد الجديد',
              confirmLabel: 'حفظ',
              required: true,
              initial: me?.email,
              multiline: false,
              keyboardType: TextInputType.emailAddress,
              textDirection: TextDirection.ltr);
          if (email == null || me == null) return;
          try {
            await app.setUserEmail(me.id, email);
            if (context.mounted) showToast(context, 'تغيّر بريد الدخول. استخدمه عند الدخول القادم.');
          } catch (e) {
            if (context.mounted) showToast(context, friendlyError(e), error: true);
          }
        } else if (v == 'refresh') {
          await app.loadAll();
        } else if (v == 'logout') {
          await Supabase.instance.client.auth.signOut();
        }
      },
      itemBuilder: (ctx) => [
        PopupMenuItem<String>(
          enabled: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(me?.displayName ?? '', style: const TextStyle(fontWeight: FontWeight.w700)),
              Text(roleText, style: const TextStyle(fontSize: 12)),
            ],
          ),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem<String>(value: 'name', child: Text('تعديل اسمي')),
        const PopupMenuItem<String>(value: 'email', child: Text('تغيير بريد الدخول')),
        const PopupMenuItem<String>(value: 'refresh', child: Text('تحديث البيانات')),
        const PopupMenuItem<String>(value: 'logout', child: Text('تسجيل الخروج')),
      ],
    );
  }
}
