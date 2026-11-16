import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../app_state.dart';
import '../config.dart';
import '../manual.dart' show manualAnchorForTab;
import '../models.dart';
import '../print/export_dialog.dart' show showExportDialog;
import '../print/sources.dart' show exportSourceForTab;
import '../ui/motion.dart';
import '../ui/theme.dart';
import '../ui/update.dart';
import '../ui/widgets.dart';
import '../units.dart' show UnitStats;
import 'account.dart';
import 'analysis.dart';
import 'assistant.dart';
import 'control/control_panel.dart';
import 'cycle_guide.dart';
import 'dashboard.dart';
import 'docs.dart';
import 'finance.dart';
import 'hub.dart';
import 'ideas.dart';
import 'manual.dart';
import 'project_detail.dart';
import 'projects.dart';
import 'requests.dart';
import 'pm_contractors.dart';
import 'pm_dashboard.dart';
import 'pm_presentation.dart';
import 'pm_projects.dart';
import 'pm_registers.dart';
import 'pm_report.dart';
import 'pm_settings.dart';
import 'print_center.dart';
import 'risks.dart';
import 'supervision.dart';
import 'swot.dart';
import 'swot_presentation.dart';
import 'units.dart';

/// معرّفات الصفحات الرئيسية (قيمة app.tab).
class Tabs {
  static const home = 0;
  static const projects = 1;
  static const requests = 2;
  static const analysis = 3;
  static const ideas = 4;
  static const control = 5;
  static const assistant = 6;
  static const finance = 7;
  static const guide = 8;

  // المخاطر ومتابعة المشاريع
  static const riskDashboard = 20;
  static const riskRegister = 21;
  static const riskMatrix = 22;
  static const pmDashboard = 40;
  static const pmProjects = 41;
  static const pmProgress = 42;
  static const pmIssues = 43;
  static const pmDelays = 44;
  static const pmChanges = 45;
  static const pmLessons = 46;
  static const pmContractors = 47;
  static const pmReport = 48;
  static const pmSettings = 49;
  static const pmGuide = 50;
  static const pmPresentation = 51;

  // تحليل SWOT
  static const swotDashboard = 30;
  static const swotMatrix = 31;
  static const swotFactors = 32;
  static const swotWeighted = 33;
  static const swotTows = 34;
  static const swotPlan = 35;
  static const swotMethod = 36;
  static const swotPresentation = 37;

  // الشؤون الفنية
  static const docsBoq = 60;
  static const docsLetters = 61;
  static const docsDesigns = 62;
  static const docsStorage = 63;
  static const docsMaterials = 64;

  // الإشراف
  static const supReports = 70;
  static const supCoverage = 71;

  // دليل الاستخدام
  static const manual = 80;
  static const manualNews = 81;

  // الترميم والمباني التاريخية
  static const heritageOverview = 90;
  static const heritageBuildings = 91;
  static const heritageAssessments = 92;

  // مكتب التخطيط وضمان الجودة
  static const pqOverview = 100;
  static const pqPlanning = 101;
  static const pqQuality = 102;
  static const pqFollowUp = 103;

  // مكتب السلامة المهنية
  static const safetyOverview = 110;
  static const safetyInspections = 111;
  static const safetyIncidents = 112;
  static const safetyViolations = 113;

  // المطابقة والاستلام
  static const accOverview = 120;
  static const accReceiving = 121;
  static const accQuality = 122;

  // الطباعة والتصدير
  static const printCenter = 130;
  static const printDesigner = 131;
  static const printMedia = 132;
}

/// مفاتيح صفحات القائمة كما تُحفظ في إعداد ui.nav.
const Map<int, String> tabKeys = {
  Tabs.home: 'home',
  Tabs.projects: 'projects',
  Tabs.requests: 'requests',
  Tabs.analysis: 'analysis',
  Tabs.ideas: 'ideas',
  Tabs.control: 'control',
  Tabs.assistant: 'assistant',
  Tabs.finance: 'finance',
  Tabs.guide: 'guide',
};

/// صفحات القائمة التي يرتّبها المدير ويسمّيها ويخفيها عن الموظفين (لوحة التحكم والمساعد ثابتان للإدارة).
const List<(String, String, IconData)> navCatalog = [
  ('home', 'الرئيسية', Icons.space_dashboard_outlined),
  ('projects', 'العقود', Icons.folder_open_outlined),
  ('finance', 'المالية', Icons.account_balance_outlined),
  ('requests', 'الاعتمادات / طلباتي', Icons.fact_check_outlined),
  ('analysis', 'التحليل', Icons.insights_outlined),
  ('ideas', 'الأفكار والتطوير', Icons.lightbulb_outline_rounded),
  ('guide', 'الدليل المرجعي', Icons.schema_outlined),
];

class _Dest {
  const _Dest(this.id, this.label, this.icon, this.selectedIcon, {this.badge = 0, this.admin = false});

  final int id;
  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final int badge;
  final bool admin;

  _Dest withLabel(String? l) => l == null || l.trim().isEmpty ? this : _Dest(id, l.trim(), icon, selectedIcon, badge: badge, admin: admin);
}

/// صفحات الإدارة الثابتة في كل الأقسام (المساعد ولوحة التحكم أو التدقيق).
/// لكل قسم أرقامه لها (28/29 للمخاطر، 38/39 لـ SWOT) حتى يبقى المستخدم في قسمه.
List<_Dest> _adminDests(AppState app, [int base = 0]) {
  final assistant = base == 0 ? Tabs.assistant : base + 8;
  final control = base == 0 ? Tabs.control : base + 9;
  return [
    if (app.canUseAssistant) _Dest(assistant, 'مساعد Claude', Icons.auto_awesome_outlined, Icons.auto_awesome, admin: true),
    if (app.isDirector)
      _Dest(control, 'لوحة التحكم', Icons.tune_outlined, Icons.tune_rounded, admin: true)
    else if (app.isAuditor)
      _Dest(control, 'التدقيق الأمني', Icons.policy_outlined, Icons.policy_rounded, admin: true),
  ];
}

List<_Dest> _destinations(AppState app) {
  if (app.section == 'risks') {
    final pm = app.pm;
    final overdue = pm.overdueReviews;
    if (!app.v7Ready) {
      return [
        const _Dest(Tabs.riskDashboard, 'لوحة المخاطر', Icons.speed_outlined, Icons.speed_rounded),
        _Dest(Tabs.riskRegister, 'سجل المخاطر', Icons.list_alt_outlined, Icons.list_alt_rounded, badge: overdue),
        const _Dest(Tabs.riskMatrix, 'مصفوفة المخاطر', Icons.grid_on_outlined, Icons.grid_on_rounded),
        ..._adminDests(app, 20),
      ];
    }
    return [
      _Dest(Tabs.pmDashboard, 'لوحة القيادة', Icons.space_dashboard_outlined, Icons.space_dashboard_rounded,
          badge: pm.alerts.where((a) => a.count > 0).length),
      const _Dest(Tabs.pmPresentation, 'لوحة العرض', Icons.co_present_outlined, Icons.co_present_rounded),
      _Dest(Tabs.pmProjects, 'سجل المشاريع', Icons.view_timeline_outlined, Icons.view_timeline_rounded,
          badge: pm.tracks.values.where((t) => t.perf == 'critical').length),
      _Dest(Tabs.pmProgress, 'التقدم الدوري', Icons.show_chart_outlined, Icons.show_chart_rounded, badge: pm.staleProjects),
      const _Dest(Tabs.riskDashboard, 'لوحة المخاطر', Icons.speed_outlined, Icons.speed_rounded),
      _Dest(Tabs.riskRegister, 'سجل المخاطر', Icons.list_alt_outlined, Icons.list_alt_rounded, badge: overdue),
      const _Dest(Tabs.riskMatrix, 'مصفوفة المخاطر', Icons.grid_on_outlined, Icons.grid_on_rounded),
      _Dest(Tabs.pmIssues, 'سجل المشاكل', Icons.report_problem_outlined, Icons.report_problem_rounded, badge: pm.overdueIssues),
      _Dest(Tabs.pmDelays, 'التأخيرات وأسبابها', Icons.hourglass_bottom_outlined, Icons.hourglass_bottom_rounded,
          badge: pm.pendingEot),
      _Dest(Tabs.pmChanges, 'سجل التغييرات', Icons.change_circle_outlined, Icons.change_circle_rounded, badge: pm.lateDecisions),
      _Dest(Tabs.pmLessons, 'الدروس المستفادة', Icons.school_outlined, Icons.school_rounded, badge: pm.proposedLessons),
      const _Dest(Tabs.pmContractors, 'تقييم الشركات', Icons.engineering_outlined, Icons.engineering_rounded),
      const _Dest(Tabs.pmReport, 'التقرير الدوري', Icons.summarize_outlined, Icons.summarize_rounded),
      const _Dest(Tabs.pmSettings, 'القوائم والإعدادات', Icons.tune_outlined, Icons.tune_rounded),
      const _Dest(Tabs.pmGuide, 'الدليل والحوكمة', Icons.menu_book_outlined, Icons.menu_book_rounded),
      ..._adminDests(app, 20),
    ];
  }
  if (app.section == 'docs') {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final late = app.docs.ofKind('letter').where((l) => l.overdue(today)).length;
    return [
      const _Dest(Tabs.docsBoq, 'المقايسات', Icons.request_quote_outlined, Icons.request_quote_rounded),
      _Dest(Tabs.docsLetters, 'المراسلات', Icons.mark_email_read_outlined, Icons.mark_email_read_rounded, badge: late),
      const _Dest(Tabs.docsDesigns, 'التصاميم', Icons.architecture_outlined, Icons.architecture_rounded),
      if (app.v9Ready)
        _Dest(Tabs.docsMaterials, 'اعتماد المواد', Icons.inventory_2_outlined, Icons.inventory_2_rounded,
            badge: UnitStats(app.units, _unitToday()).overdueMaterials),
      if (app.canAudit || app.role == AppRole.officeStaff)
        const _Dest(Tabs.docsStorage, 'مساحة التخزين', Icons.cloud_outlined, Icons.cloud_rounded),
      ..._adminDests(app, 60),
    ];
  }
  if (app.section == 'supervision') {
    final unreviewed = app.isDirector ? app.docs.reports.where((r) => !r.reviewed).length : 0;
    return [
      _Dest(Tabs.supReports, 'التقارير اليومية', Icons.assignment_outlined, Icons.assignment_rounded, badge: unreviewed),
      const _Dest(Tabs.supCoverage, 'متابعة التغطية', Icons.grid_on_outlined, Icons.grid_on_rounded),
      ..._adminDests(app, 70),
    ];
  }
  if (app.section == 'heritage') {
    final today = _unitToday();
    final s = UnitStats(app.units, today);
    return [
      const _Dest(Tabs.heritageOverview, 'لوحة القسم', Icons.space_dashboard_outlined, Icons.space_dashboard_rounded),
      _Dest(Tabs.heritageBuildings, 'المباني التاريخية', Icons.museum_outlined, Icons.museum_rounded, badge: s.buildingsAtRisk),
      const _Dest(Tabs.heritageAssessments, 'تقييمات الحالة', Icons.fact_check_outlined, Icons.fact_check_rounded),
      ..._adminDests(app, 90),
    ];
  }
  if (app.section == 'planning_qa') {
    final today = _unitToday();
    final s = UnitStats(app.units, today);
    return [
      const _Dest(Tabs.pqOverview, 'لوحة المكتب', Icons.space_dashboard_outlined, Icons.space_dashboard_rounded),
      _Dest(Tabs.pqPlanning, 'قسم التخطيط', Icons.flag_outlined, Icons.flag_rounded, badge: s.overduePlans),
      _Dest(Tabs.pqQuality, 'قسم ضمان الجودة', Icons.verified_outlined, Icons.verified_rounded, badge: s.auditsOpen),
      _Dest(Tabs.pqFollowUp, 'قسم المتابعة', Icons.track_changes_outlined, Icons.track_changes_rounded, badge: s.overdueTasks),
      ..._adminDests(app, 100),
    ];
  }
  if (app.section == 'safety') {
    final today = _unitToday();
    final s = UnitStats(app.units, today);
    return [
      const _Dest(Tabs.safetyOverview, 'لوحة السلامة', Icons.space_dashboard_outlined, Icons.space_dashboard_rounded),
      const _Dest(Tabs.safetyInspections, 'جولات التفتيش', Icons.health_and_safety_outlined, Icons.health_and_safety_rounded),
      _Dest(Tabs.safetyIncidents, 'الحوادث', Icons.personal_injury_outlined, Icons.personal_injury_rounded, badge: s.openIncidents),
      _Dest(Tabs.safetyViolations, 'المخالفات', Icons.do_not_disturb_on_outlined, Icons.do_not_disturb_on_rounded,
          badge: s.overdueViolations),
      ..._adminDests(app, 110),
    ];
  }
  if (app.section == 'acceptance') {
    final today = _unitToday();
    final s = UnitStats(app.units, today);
    return [
      const _Dest(Tabs.accOverview, 'لوحة القسم', Icons.space_dashboard_outlined, Icons.space_dashboard_rounded),
      _Dest(Tabs.accReceiving, 'وحدة الاستلام', Icons.handshake_outlined, Icons.handshake_rounded, badge: s.overduePunch),
      _Dest(Tabs.accQuality, 'وحدة ضبط الجودة', Icons.science_outlined, Icons.science_rounded, badge: s.overdueNcr),
      ..._adminDests(app, 120),
    ];
  }
  if (app.section == 'print') {
    return [
      const _Dest(Tabs.printCenter, 'لوحة الطباعة', Icons.space_dashboard_outlined, Icons.space_dashboard_rounded),
      const _Dest(Tabs.printDesigner, 'مصمم الصفحة', Icons.design_services_outlined, Icons.design_services_rounded),
      const _Dest(Tabs.printMedia, 'مكتبة الوسائط', Icons.perm_media_outlined, Icons.perm_media_rounded),
      ..._adminDests(app, 130),
    ];
  }
  if (app.section == 'manual') {
    return [
      const _Dest(Tabs.manual, 'دليل الاستخدام', Icons.menu_book_outlined, Icons.menu_book_rounded),
      const _Dest(Tabs.manualNews, 'ما الجديد', Icons.new_releases_outlined, Icons.new_releases_rounded),
      ..._adminDests(app, 80),
    ];
  }
  if (app.section == 'swot') {
    final alerts = app.v6Ready ? app.swot.alerts.length : 0;
    return [
      const _Dest(Tabs.swotDashboard, 'لوحة المتابعة', Icons.insights_outlined, Icons.insights_rounded),
      const _Dest(Tabs.swotPresentation, 'لوحة العرض', Icons.co_present_outlined, Icons.co_present_rounded),
      const _Dest(Tabs.swotMatrix, 'مصفوفة SWOT', Icons.grid_view_outlined, Icons.grid_view_rounded),
      const _Dest(Tabs.swotFactors, 'سجل العوامل', Icons.format_list_numbered_outlined, Icons.format_list_numbered_rounded),
      const _Dest(Tabs.swotWeighted, 'التقييم المرجح', Icons.balance_outlined, Icons.balance_rounded),
      const _Dest(Tabs.swotTows, 'استراتيجيات TOWS', Icons.alt_route_outlined, Icons.alt_route_rounded),
      _Dest(Tabs.swotPlan, 'خطة التنفيذ', Icons.event_note_outlined, Icons.event_note_rounded, badge: alerts),
      const _Dest(Tabs.swotMethod, 'المنهجية والحوكمة', Icons.menu_book_outlined, Icons.menu_book_rounded),
      ..._adminDests(app, 30),
    ];
  }
  final requestsBadge = app.isDirector ? app.pendingRequests.length : app.myRequests.where((r) => r.isPending).length;
  final newIdeas = app.isDirector ? app.ideas.where((i) => i.status == 'new').length : 0;
  final all = <_Dest>[
    const _Dest(Tabs.home, 'الرئيسية', Icons.space_dashboard_outlined, Icons.space_dashboard_rounded),
    _Dest(Tabs.projects, term('contracts'), Icons.folder_open_outlined, Icons.folder_rounded),
    const _Dest(Tabs.finance, 'المالية', Icons.account_balance_outlined, Icons.account_balance_rounded),
    if (!app.isAuditor)
      _Dest(Tabs.requests, app.isDirector ? 'الاعتمادات' : 'طلباتي', Icons.fact_check_outlined, Icons.fact_check_rounded,
          badge: requestsBadge),
    if (app.canAudit || app.settings.feature('analysis'))
      const _Dest(Tabs.analysis, 'التحليل', Icons.insights_outlined, Icons.insights_rounded),
    if (app.v2Ready) _Dest(Tabs.ideas, 'الأفكار والتطوير', Icons.lightbulb_outline_rounded, Icons.lightbulb_rounded, badge: newIdeas),
    const _Dest(Tabs.guide, 'الدليل المرجعي', Icons.schema_outlined, Icons.schema_rounded),
    ..._adminDests(app),
  ];

  // تخصيص المدير: الإخفاء عن الموظفين (المدير يرى كل شيء) والأسماء والترتيب
  final s = app.settings;
  final hidden = s.navHidden.toSet();
  final labels = s.navLabels;
  final order = s.navOrder;
  final list = [
    for (final d in all)
      if (app.isDirector || d.admin || d.id == Tabs.home || !hidden.contains(tabKeys[d.id])) d.withLabel(d.admin ? null : labels[tabKeys[d.id]]),
  ];
  if (order.isEmpty) return list;
  int rank(_Dest d) {
    final i = order.indexOf(tabKeys[d.id] ?? '');
    return i < 0 ? 100 + all.indexWhere((x) => x.id == d.id) : i;
  }

  final normal = list.where((d) => !d.admin).toList()..sort((a, b) => rank(a).compareTo(rank(b)));
  return [...normal, ...list.where((d) => d.admin)];
}

Widget _page(int id) => switch (id) {
      Tabs.projects => const ProjectsPage(),
      Tabs.requests => const RequestsPage(),
      Tabs.analysis => const AnalysisPage(),
      Tabs.ideas => const IdeasPage(),
      Tabs.control || 29 || 39 || 69 || 79 || 89 || 99 || 109 || 119 || 129 || 139 => const ControlPanelPage(),
      Tabs.assistant || 28 || 38 || 68 || 78 || 88 || 98 || 108 || 118 || 128 || 138 => const AssistantPage(),
      Tabs.heritageOverview => const UnitOverviewPage(key: ValueKey('ov-heritage'), section: 'heritage'),
      Tabs.heritageBuildings =>
        const UnitRecordsPage(key: ValueKey('heritage_building'), unit: 'heritage', kinds: ['heritage_building']),
      Tabs.heritageAssessments =>
        const UnitRecordsPage(key: ValueKey('heritage_assessment'), unit: 'heritage', kinds: ['heritage_assessment']),
      Tabs.pqOverview => const UnitOverviewPage(key: ValueKey('ov-planning_qa'), section: 'planning_qa'),
      Tabs.pqPlanning => const UnitRecordsPage(key: ValueKey('planning'), unit: 'planning', kinds: ['plan'], title: 'قسم التخطيط'),
      Tabs.pqQuality => const UnitRecordsPage(key: ValueKey('quality_assurance'), unit: 'quality_assurance', kinds: ['qa_audit', 'ncr']),
      Tabs.pqFollowUp =>
        const UnitRecordsPage(key: ValueKey('follow_up'), unit: 'follow_up', kinds: ['followup_task'], title: 'قسم المتابعة'),
      Tabs.safetyOverview => const UnitOverviewPage(key: ValueKey('ov-safety'), section: 'safety'),
      Tabs.safetyInspections =>
        const UnitRecordsPage(key: ValueKey('safety_inspection'), unit: 'safety', kinds: ['safety_inspection']),
      Tabs.safetyIncidents => const UnitRecordsPage(key: ValueKey('safety_incident'), unit: 'safety', kinds: ['safety_incident']),
      Tabs.safetyViolations => const UnitRecordsPage(key: ValueKey('safety_violation'), unit: 'safety', kinds: ['safety_violation']),
      Tabs.accOverview => const UnitOverviewPage(key: ValueKey('ov-acceptance'), section: 'acceptance'),
      Tabs.accReceiving => const UnitRecordsPage(key: ValueKey('receiving'), unit: 'receiving', kinds: ['handover', 'punch_item']),
      Tabs.accQuality => const UnitRecordsPage(key: ValueKey('quality_control'), unit: 'quality_control', kinds: ['qc_test', 'ncr']),
      Tabs.docsMaterials =>
        const UnitRecordsPage(key: ValueKey('material_approval'), unit: 'technical', kinds: ['material_approval'], title: 'اعتماد المواد'),
      Tabs.printCenter => const PrintCenterPage(),
      Tabs.printDesigner => const PrintDesignerPage(),
      Tabs.printMedia => const MediaLibraryPage(),
      Tabs.docsBoq => const DocsPage(key: ValueKey('boq'), kind: 'boq'),
      Tabs.docsLetters => const DocsPage(key: ValueKey('letter'), kind: 'letter'),
      Tabs.docsDesigns => const DocsPage(key: ValueKey('design'), kind: 'design'),
      Tabs.docsStorage => const StoragePage(),
      Tabs.supReports => const SiteReportsPage(),
      Tabs.supCoverage => const ReportCoveragePage(),
      Tabs.manual => const ManualPage(),
      Tabs.manualNews => const WhatsNewPage(),
      Tabs.finance => const FinancePage(),
      Tabs.guide => const CycleGuidePage(),
      Tabs.riskDashboard => const RiskDashboardPage(),
      Tabs.riskRegister => const RiskRegisterPage(),
      Tabs.riskMatrix => const RiskMatrixPage(),
      Tabs.pmDashboard => const PmDashboardPage(),
      Tabs.pmProjects => const PmProjectsPage(),
      Tabs.pmProgress => const PmProgressPage(),
      Tabs.pmIssues => const PmIssuesPage(),
      Tabs.pmDelays => const PmDelaysPage(),
      Tabs.pmChanges => const PmChangesPage(),
      Tabs.pmLessons => const PmLessonsPage(),
      Tabs.pmContractors => const PmContractorsPage(),
      Tabs.pmReport => const PmReportPage(),
      Tabs.pmSettings => const PmSettingsPage(),
      Tabs.pmGuide => const PmGuidePage(),
      Tabs.pmPresentation => const PmPresentationPage(),
      Tabs.swotDashboard => const SwotDashboardPage(),
      Tabs.swotMatrix => const SwotMatrixPage(),
      Tabs.swotFactors => const SwotFactorsPage(),
      Tabs.swotWeighted => const SwotWeightedPage(),
      Tabs.swotTows => const SwotTowsPage(),
      Tabs.swotPlan => const SwotPlanPage(),
      Tabs.swotMethod => const SwotMethodPage(),
      Tabs.swotPresentation => const SwotPresentationPage(),
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

    if (app.showHub) {
      return Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (_) => _resetIdle(),
        onPointerSignal: (_) => _resetIdle(),
        child: Scaffold(
          body: SafeArea(
            bottom: false,
            child: Column(children: [
              const _TopBar(title: 'الأقسام الرئيسية', compact: true, hub: true),
              if (release != null && !app.updateDismissed) UpdateBanner(app: app, release: release),
              _Banners(app: app),
              const Expanded(child: SectionHub()),
            ]),
          ),
        ),
      );
    }

    final content = Column(
      children: [
        _TopBar(title: current.label, compact: layout == 0),
        if (release != null && !app.updateDismissed) UpdateBanner(app: app, release: release),
        _Banners(app: app),
        Expanded(child: MotionSwitcher(child: KeyedSubtree(key: ValueKey(current.id), child: _page(current.id)))),
      ],
    );

    final fab = current.id == Tabs.projects && app.canManageProjects && !app.frozenForMe
        ? FloatingActionButton.extended(
            onPressed: () => openProjectEditor(context, null),
            icon: const Icon(Icons.add),
            label: Text(term('new_contract')),
          )
        : null;

    Widget icon(_Dest d, bool selected) {
      final i = Icon(selected ? d.selectedIcon : d.icon);
      return d.badge > 0 ? Badge(label: Text('${d.badge}'), child: i) : i;
    }

    final Widget scaffold;
    // الشريط الجانبي الكامل يتمرّر؛ يُستخدم أيضاً على الشاشات المتوسطة حين تكثر صفحات القسم.
    if (layout == 2 || (layout == 1 && dests.length > 9)) {
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
      final primary = dests.take(3).toList();
      final more = dests.skip(3).toList();
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
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.8),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
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
                leading: const Icon(Icons.apps_rounded),
                title: const Text('الأقسام الرئيسية', style: TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text('أنت في: ${sectionName(app.section)}'),
                onTap: () {
                  Navigator.of(ctx).pop();
                  app.openHub();
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
    final t = Theme.of(context).textTheme;
    return Container(
      width: 272,
      color: toneOf(context).bar,
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
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: SectionSwitcher(app: app),
          ),
          Divider(height: 1, color: sem.rule),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              children: [
                for (var i = 0; i < dests.length; i++) ...[
                  if (dests[i].admin && (i == 0 || !dests[i - 1].admin))
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 14, 12, 6),
                      child: Text(app.isDirector ? 'الإدارة' : 'التدقيق', style: t.labelSmall?.copyWith(color: sem.muted, fontWeight: FontWeight.w700, letterSpacing: 0.4)),
                    ),
                  FadeSlideIn(
                    delay: Duration(milliseconds: 80 + i * 45),
                    offset: const Offset(0, 0.25),
                    child: _SideItem(dest: dests[i], selected: dests[i].id == current, onTap: () => app.setTab(dests[i].id)),
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

/// عنصر في الشريط الجانبي: خلفية ومؤشر يتحركان عند الاختيار.
class _SideItem extends StatelessWidget {
  const _SideItem({required this.dest, required this.selected, required this.onTap});

  final _Dest dest;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final sem = Sem.of(context);
    final cs = Theme.of(context).colorScheme;
    final d = Motion.of(context, 260);
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: AnimatedContainer(
        duration: d,
        curve: Curves.easeOutCubic,
        decoration: BoxDecoration(color: selected ? cs.primaryContainer : Colors.transparent, borderRadius: BorderRadius.circular(12)),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(0, 12, 14, 12),
              child: Row(
                children: [
                  AnimatedContainer(
                    duration: d,
                    curve: Curves.easeOutBack,
                    width: 3,
                    height: selected ? 22 : 0,
                    decoration: BoxDecoration(color: cs.primary, borderRadius: BorderRadius.circular(3)),
                  ),
                  const SizedBox(width: 11),
                  AnimatedSwitcher(
                    duration: d,
                    transitionBuilder: (child, a) => ScaleTransition(scale: a, child: child),
                    child: Icon(selected ? dest.selectedIcon : dest.icon,
                        key: ValueKey(selected), size: 22, color: selected ? cs.onPrimaryContainer : sem.muted),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: AnimatedDefaultTextStyle(
                      duration: d,
                      style: DefaultTextStyle.of(context).style.copyWith(
                            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                            color: selected ? cs.onPrimaryContainer : DefaultTextStyle.of(context).style.color,
                          ),
                      child: Text(dest.label),
                    ),
                  ),
                  if (dest.badge > 0) Badge(label: Text('${dest.badge}')),
                ],
              ),
            ),
          ),
        ),
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
  const _TopBar({required this.title, required this.compact, this.hub = false});

  final String title;
  final bool compact;
  final bool hub;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final sem = Sem.of(context);
    return Material(
      color: toneOf(context).bar,
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
                        AnimatedSwitcher(
                          duration: Motion.of(context, 320),
                          layoutBuilder: (current, previous) => Stack(
                            alignment: AlignmentDirectional.centerStart,
                            children: [...previous, if (current != null) current],
                          ),
                          transitionBuilder: (child, a) => FadeTransition(
                            opacity: a,
                            child: SlideTransition(position: a.drive(Tween(begin: const Offset(0, 0.35), end: Offset.zero)), child: child),
                          ),
                          child: Text(title,
                              key: ValueKey(title), style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                        ),
                        Text(hub ? app.orgName : sectionName(app.section),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 11.5, color: hub ? sem.muted : sectionColor(context, app.section))),
                      ],
                    ),
                  ),
                  if (app.loading)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: sem.muted)),
                    ),
                  if (!hub)
                    compact
                        ? IconButton(
                            tooltip: 'الأقسام الرئيسية',
                            onPressed: app.openHub,
                            icon: Icon(sectionIcon(app.section), color: sectionColor(context, app.section)),
                          )
                        : Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            child: TextButton.icon(
                              onPressed: app.openHub,
                              icon: Icon(Icons.apps_rounded, color: sectionColor(context, app.section)),
                              label: Text('الأقسام', style: TextStyle(color: sectionColor(context, app.section))),
                            ),
                          ),
                  if (!hub && app.section != 'manual')
                    IconButton(
                      tooltip: 'شرح هذه الصفحة في دليل الاستخدام',
                      onPressed: () => app.openManual(manualAnchorForTab(app.tab)),
                      icon: const Icon(Icons.help_outline_rounded),
                    ),
                  if (!hub)
                    IconButton(
                      tooltip: 'تصدير وطباعة',
                      onPressed: () => showExportDialog(context, sourceId: exportSourceForTab(app.tab)),
                      icon: const Icon(Icons.print_outlined),
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

DateTime _unitToday() {
  final n = DateTime.now();
  return DateTime(n.year, n.month, n.day);
}
