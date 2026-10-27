import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../app_state.dart';
import '../config.dart';
import '../models.dart';
import '../ui/theme.dart';
import '../ui/update.dart';
import '../ui/widgets.dart';
import 'account.dart';
import 'analysis.dart';
import 'control/control_panel.dart';
import 'dashboard.dart';
import 'ideas.dart';
import 'project_detail.dart';
import 'projects.dart';
import 'requests.dart';

/// معرّفات الصفحات الرئيسية (قيمة app.tab).
class Tabs {
  static const home = 0;
  static const projects = 1;
  static const requests = 2;
  static const analysis = 3;
  static const ideas = 4;
  static const control = 5;
}

class _Dest {
  const _Dest(this.id, this.label, this.icon, this.selectedIcon, {this.badge = 0, this.admin = false});

  final int id;
  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final int badge;
  final bool admin;
}

List<_Dest> _destinations(AppState app) {
  final requestsBadge = app.isDirector ? app.pendingRequests.length : app.myRequests.where((r) => r.isPending).length;
  final newIdeas = app.isDirector ? app.ideas.where((i) => i.status == 'new').length : 0;
  return [
    const _Dest(Tabs.home, 'الرئيسية', Icons.space_dashboard_outlined, Icons.space_dashboard_rounded),
    const _Dest(Tabs.projects, 'المشاريع', Icons.folder_open_outlined, Icons.folder_rounded),
    if (!app.isAuditor)
      _Dest(Tabs.requests, app.isDirector ? 'الاعتمادات' : 'طلباتي', Icons.fact_check_outlined, Icons.fact_check_rounded,
          badge: requestsBadge),
    if (app.canAudit || app.settings.feature('analysis'))
      const _Dest(Tabs.analysis, 'التحليل', Icons.insights_outlined, Icons.insights_rounded),
    if (app.v2Ready) _Dest(Tabs.ideas, 'الأفكار والتطوير', Icons.lightbulb_outline_rounded, Icons.lightbulb_rounded, badge: newIdeas),
    if (app.isDirector)
      const _Dest(Tabs.control, 'لوحة التحكم', Icons.tune_outlined, Icons.tune_rounded, admin: true)
    else if (app.isAuditor)
      const _Dest(Tabs.control, 'التدقيق الأمني', Icons.policy_outlined, Icons.policy_rounded, admin: true),
  ];
}

Widget _page(int id) => switch (id) {
      Tabs.projects => const ProjectsPage(),
      Tabs.requests => const RequestsPage(),
      Tabs.analysis => const AnalysisPage(),
      Tabs.ideas => const IdeasPage(),
      Tabs.control => const ControlPanelPage(),
      _ => const DashboardPage(),
    };

/// الهيكل الرئيسي: شريط جانبي على الشاشات العريضة، وشريط سفلي على الهاتف.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  Timer? _idle;

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onKey);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _resetIdle();
    });
  }

  @override
  void dispose() {
    _idle?.cancel();
    HardwareKeyboard.instance.removeHandler(_onKey);
    super.dispose();
  }

  bool _onKey(KeyEvent e) {
    _resetIdle();
    return false;
  }

  /// قفل الجلسة تلقائياً بعد مدة خمول يحددها المدير في مركز الأمان.
  void _resetIdle() {
    _idle?.cancel();
    final app = AppScope.maybeRead(context);
    final minutes = app?.idleMinutes ?? 30;
    if (minutes <= 0) return;
    _idle = Timer(Duration(minutes: minutes), () {
      Supabase.instance.client.auth.signOut();
    });
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final dests = _destinations(app);
    final current = dests.firstWhere((d) => d.id == app.tab, orElse: () => dests.first);
    final width = MediaQuery.sizeOf(context).width;
    final layout = width >= 1100 ? 2 : (width >= 720 ? 1 : 0);

    final release = app.latestRelease;
    if (release != null && app.updateMandatory) {
      return UpdateRequiredScreen(release: release);
    }

    final content = Column(
      children: [
        _TopBar(title: current.label, compact: layout == 0),
        if (release != null && !app.updateDismissed) UpdateBanner(app: app, release: release),
        _Banners(app: app),
        Expanded(child: KeyedSubtree(key: ValueKey(current.id), child: _page(current.id))),
      ],
    );

    final fab = current.id == Tabs.projects && app.canManageProjects && !app.frozenForMe
        ? FloatingActionButton.extended(
            onPressed: () => openProjectEditor(context, null),
            icon: const Icon(Icons.add),
            label: const Text('مشروع جديد'),
          )
        : null;

    Widget icon(_Dest d, bool selected) {
      final i = Icon(selected ? d.selectedIcon : d.icon);
      return d.badge > 0 ? Badge(label: Text('${d.badge}'), child: i) : i;
    }

    final Widget scaffold;
    if (layout == 2) {
      scaffold = Scaffold(
        floatingActionButton: fab,
        body: Row(
          children: [
            _Sidebar(dests: dests, current: current.id),
            VerticalDivider(width: 1, color: Sem.of(context).rule),
            Expanded(child: content),
          ],
        ),
      );
    } else if (layout == 1) {
      scaffold = Scaffold(
        floatingActionButton: fab,
        body: Row(
          children: [
            NavigationRail(
              selectedIndex: dests.indexOf(current),
              onDestinationSelected: (i) => app.setTab(dests[i].id),
              labelType: NavigationRailLabelType.all,
              leading: const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: BrandEmblem(size: 40)),
              trailing: Expanded(
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: Padding(padding: const EdgeInsets.only(bottom: 16), child: _AccountButton(app: app)),
                ),
              ),
              destinations: [
                for (final d in dests)
                  NavigationRailDestination(icon: icon(d, false), selectedIcon: icon(d, true), label: Text(d.label, textAlign: TextAlign.center)),
              ],
            ),
            VerticalDivider(width: 1, color: Sem.of(context).rule),
            Expanded(child: content),
          ],
        ),
      );
    } else {
      final primary = dests.where((d) => d.id <= Tabs.requests).toList();
      final more = dests.where((d) => d.id > Tabs.requests).toList();
      final moreBadge = more.fold<int>(0, (a, d) => a + d.badge);
      final moreSelected = more.contains(current);
      scaffold = Scaffold(
        floatingActionButton: fab,
        body: SafeArea(bottom: false, child: content),
        bottomNavigationBar: NavigationBar(
          selectedIndex: moreSelected ? primary.length : primary.indexOf(current),
          onDestinationSelected: (i) {
            if (i < primary.length) {
              app.setTab(primary[i].id);
            } else {
              _showMore(context, app, more);
            }
          },
          destinations: [
            for (final d in primary) NavigationDestination(icon: icon(d, false), selectedIcon: icon(d, true), label: d.label),
            NavigationDestination(
              icon: moreBadge > 0
                  ? Badge(label: Text('$moreBadge'), child: const Icon(Icons.apps_outlined))
                  : const Icon(Icons.apps_outlined),
              selectedIcon: const Icon(Icons.apps_rounded),
              label: 'المزيد',
            ),
          ],
        ),
      );
    }

    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _resetIdle(),
      onPointerSignal: (_) => _resetIdle(),
      child: scaffold,
    );
  }

  Future<void> _showMore(BuildContext context, AppState app, List<_Dest> more) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final d in more)
                ListTile(
                  leading: Icon(d.icon),
                  title: Text(d.label, style: const TextStyle(fontWeight: FontWeight.w600)),
                  trailing: d.badge > 0 ? Badge(label: Text('${d.badge}')) : null,
                  onTap: () {
                    Navigator.of(ctx).pop();
                    app.setTab(d.id);
                  },
                ),
              ListTile(
                leading: const Icon(Icons.account_circle_outlined),
                title: const Text('حسابي والأمان', style: TextStyle(fontWeight: FontWeight.w600)),
                onTap: () {
                  Navigator.of(ctx).pop();
                  openAccount(context);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// الشريط الجانبي على الشاشات العريضة.
class _Sidebar extends StatelessWidget {
  const _Sidebar({required this.dests, required this.current});

  final List<_Dest> dests;
  final int current;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final sem = Sem.of(context);
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: 272,
      color: dark ? const Color(0xFF151514) : Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const BrandStripe(height: 4),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 20, 18, 14),
            child: Row(
              children: [
                const BrandEmblem(size: 46),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(app.appTitle, maxLines: 2, overflow: TextOverflow.ellipsis, style: t.titleSmall?.copyWith(fontWeight: FontWeight.w700, height: 1.35)),
                      Text(app.orgName, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.bodySmall?.copyWith(color: sem.muted)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: sem.rule),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              children: [
                for (final d in dests) ...[
                  if (d.admin)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 14, 12, 6),
                      child: Text(app.isDirector ? 'الإدارة' : 'التدقيق', style: t.labelSmall?.copyWith(color: sem.muted, fontWeight: FontWeight.w700, letterSpacing: 0.4)),
                    ),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Material(
                      color: d.id == current ? cs.primaryContainer : Colors.transparent,
                      borderRadius: BorderRadius.circular(12),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () => app.setTab(d.id),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          child: Row(
                            children: [
                              Icon(d.id == current ? d.selectedIcon : d.icon,
                                  size: 22, color: d.id == current ? cs.onPrimaryContainer : sem.muted),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(d.label,
                                    style: TextStyle(
                                        fontWeight: d.id == current ? FontWeight.w700 : FontWeight.w500,
                                        color: d.id == current ? cs.onPrimaryContainer : null)),
                              ),
                              if (d.badge > 0) Badge(label: Text('${d.badge}')),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          Divider(height: 1, color: sem.rule),
          Padding(
            padding: const EdgeInsets.all(12),
            child: _UserCard(app: app),
          ),
        ],
      ),
    );
  }
}

String roleText(AppState app, Profile? me) {
  if (me == null) return '';
  if (me.role == AppRole.deptHead) return 'رئيس قسم ${app.departmentName(me.department)}';
  return me.role?.label ?? '';
}

class _UserCard extends StatelessWidget {
  const _UserCard({required this.app});

  final AppState app;

  @override
  Widget build(BuildContext context) {
    final sem = Sem.of(context);
    final me = app.me;
    return Material(
      color: sem.surface2,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => openAccount(context),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              InitialsAvatar(name: me?.displayName ?? ''),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(me?.displayName ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
                    Text(roleText(app, me), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: sem.muted, fontSize: 12)),
                  ],
                ),
              ),
              Icon(Icons.chevron_left_rounded, color: sem.muted),
            ],
          ),
        ),
      ),
    );
  }
}

class _AccountButton extends StatelessWidget {
  const _AccountButton({required this.app});

  final AppState app;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'حسابي والأمان',
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: () => openAccount(context),
        child: InitialsAvatar(name: app.me?.displayName ?? '', size: 40),
      ),
    );
  }
}

/// الشريط العلوي لمنطقة المحتوى.
class _TopBar extends StatelessWidget {
  const _TopBar({required this.title, required this.compact});

  final String title;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final sem = Sem.of(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Material(
      color: dark ? const Color(0xFF151514) : Colors.white,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (compact) const BrandStripe(height: 3),
          SizedBox(
            height: 64,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  if (compact) ...[const BrandEmblem(size: 34), const SizedBox(width: 10)] else const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                        if (compact)
                          Text(app.orgName, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11.5, color: sem.muted)),
                      ],
                    ),
                  ),
                  if (app.loading)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: sem.muted)),
                    ),
                  IconButton(tooltip: 'تحديث البيانات', onPressed: app.loadAll, icon: const Icon(Icons.refresh_rounded)),
                  IconButton(
                    tooltip: 'الإشعارات',
                    onPressed: () => _showNotifications(context),
                    icon: app.unreadCount > 0
                        ? Badge(label: Text('${app.unreadCount}'), child: const Icon(Icons.notifications_none_rounded))
                        : const Icon(Icons.notifications_none_rounded),
                  ),
                  if (compact) Padding(padding: const EdgeInsets.only(right: 4), child: _AccountButton(app: app)),
                ],
              ),
            ),
          ),
          Divider(height: 1, color: sem.rule),
        ],
      ),
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

/// الإعلان العام وتنبيه التجميد.
class _Banners extends StatelessWidget {
  const _Banners({required this.app});

  final AppState app;

  @override
  Widget build(BuildContext context) {
    final items = <Widget>[];
    if (app.loadError != null) {
      items.add(InfoBanner(
        text: app.loadError!,
        level: 'critical',
        action: TextButton(onPressed: app.loadAll, child: const Text('إعادة المحاولة')),
      ));
    }
    if (app.settings.frozen) {
      items.add(InfoBanner(
        text: app.isDirector
            ? 'المنظومة مجمّدة: الموظفون يقرؤون فقط حتى تلغي التجميد من مركز الأمان.'
            : 'المنظومة في وضع القراءة فقط بقرار مدير المكتب.',
        level: 'warning',
        icon: Icons.ac_unit_rounded,
      ));
    }
    final text = app.settings.announcementText.trim();
    if (text.isNotEmpty) items.add(InfoBanner(text: text, level: app.settings.announcementLevel));
    if (items.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
      child: Column(children: [for (final w in items) Padding(padding: const EdgeInsets.only(bottom: 8), child: w)]),
    );
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
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text('الإشعارات', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
            ),
            if (items.isEmpty)
              const EmptyState(icon: Icons.notifications_none, title: 'لا توجد إشعارات')
            else
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
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
                          'idea' => Icons.lightbulb_outline_rounded,
                          'security' => Icons.shield_outlined,
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
                          app.setTab(Tabs.requests);
                        } else if (n.kind == 'signup' && app.isDirector) {
                          app.setTab(Tabs.control);
                        } else if (n.kind == 'idea') {
                          app.setTab(Tabs.ideas);
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

/// معلومات الإصدار في أسفل صفحة الحساب.
String get appVersionText => 'الإصدار ${AppConfig.appVersion}';
