import 'package:flutter/material.dart';

import '../../app_state.dart';
import '../../config.dart';
import '../../models.dart';
import '../../ui/theme.dart';
import '../../ui/widgets.dart';
import '../home_shell.dart';

/// نظرة عامة على المنظومة وما يحتاج انتباه المدير.
class OverviewSection extends StatelessWidget {
  const OverviewSection({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final sem = Sem.of(context);
    final users = app.people.values.toList();
    final active = users.where((u) => u.active).length;
    final pendingUsers = users.where((u) => !u.active && u.role == null).length;
    final pendingReq = app.pendingRequests.length;
    final newIdeas = app.ideas.where((i) => i.status == 'new').length;
    final complete = app.projects.where((p) => app.progressOf(p).cycle == CycleState.complete).length;
    final contracts = app.projects.fold<double>(0, (a, p) => a + (p.contractValue ?? 0));

    final alerts = <Widget>[
      if (!app.v2Ready)
        const InfoBanner(
          level: 'warning',
          text: 'لم يُطبَّق ملف قاعدة البيانات للإصدار الثاني بعد؛ بعض أقسام اللوحة معطلة حتى تشغيله في Supabase.',
        ),
      if (pendingUsers > 0) InfoBanner(level: 'warning', icon: Icons.person_add_alt, text: '$pendingUsers حساب جديد بانتظار التفعيل في «المستخدمون والأدوار».'),
      if (pendingReq > 0)
        InfoBanner(
          level: 'info',
          icon: Icons.fact_check_outlined,
          text: '$pendingReq طلب اعتماد معلّق.',
          action: TextButton(onPressed: () => app.setTab(Tabs.requests), child: const Text('فتح')),
        ),
      if (newIdeas > 0)
        InfoBanner(
          level: 'info',
          icon: Icons.lightbulb_outline_rounded,
          text: '$newIdeas فكرة جديدة لم تُراجع.',
          action: TextButton(onPressed: () => app.setTab(Tabs.ideas), child: const Text('فتح')),
        ),
      if (app.settings.frozen) const InfoBanner(level: 'critical', icon: Icons.ac_unit_rounded, text: 'المنظومة مجمّدة حالياً (قراءة فقط لغيرك).'),
    ];

    return PageBody(
      onRefresh: app.loadAll,
      children: [
        PageHeader(
          icon: Icons.tune_rounded,
          title: 'لوحة التحكم',
          subtitle: 'كل ما يخص المنظومة من مكان واحد: المستخدمون والصلاحيات وهيكل البيانات والإعدادات والأمان.',
        ),
        ResponsiveGrid(minItemWidth: 210, children: [
          StatCard(icon: Icons.folder_rounded, label: 'المشاريع', value: '${app.projects.length}', sub: '$complete مكتملة الدورة'),
          StatCard(icon: Icons.group_rounded, label: 'المستخدمون المفعّلون', value: '$active', sub: '$pendingUsers بانتظار التفعيل', color: sem.ok),
          StatCard(icon: Icons.fact_check_rounded, label: 'طلبات معلّقة', value: '$pendingReq', color: sem.wip),
          StatCard(icon: Icons.description_rounded, label: 'النماذج الفعّالة', value: '${app.formDefs.length}', sub: 'في ${stageNames.length} مراحل'),
          StatCard(icon: Icons.dynamic_form_rounded, label: 'الحقول الإضافية', value: '${app.activeFields.length}'),
          StatCard(icon: Icons.payments_rounded, label: 'إجمالي قيم التعاقد', value: fmtMoney(contracts), sub: currencyLabel),
        ]),
        const SizedBox(height: 18),
        if (alerts.isNotEmpty) ...[
          SectionCard(
            title: 'يحتاج انتباهك',
            icon: Icons.notifications_active_outlined,
            child: Column(children: [for (final a in alerts) Padding(padding: const EdgeInsets.only(bottom: 8), child: a)]),
          ),
          const SizedBox(height: 18),
        ],
        SectionCard(
          title: 'عن المنظومة',
          icon: Icons.info_outline_rounded,
          child: Column(
            children: [
              SettingRow(icon: Icons.apps_rounded, title: 'إصدار التطبيق', subtitle: AppConfig.appVersion),
              SettingRow(
                icon: Icons.storage_rounded,
                title: 'قاعدة البيانات',
                subtitle: app.v2Ready ? 'الإصدار الثاني (الإعدادات الحية ومركز الأمان)' : 'الإصدار الأول',
              ),
              SettingRow(
                icon: Icons.verified_user_outlined,
                title: 'الحماية',
                subtitle: 'الصلاحيات مفروضة داخل قاعدة البيانات (RLS)، وكل تعديل مسجّل في سجل التدقيق.',
              ),
            ],
          ),
        ),
      ],
    );
  }
}
