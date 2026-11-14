import 'package:flutter/material.dart';

import '../app_state.dart';
import '../config.dart';
import '../manual.dart';
import '../models.dart';
import '../registers.dart';
import '../ui/motion.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';
import '../units.dart';
import 'finance.dart' show FinanceStats;
import 'supervision.dart' show activeSiteProjects;

/// الأقسام الرئيسية للمنظومة: (المفتاح، الاسم، الوصف، الأيقونة)
const List<(String, String, String, IconData)> appSections = [
  ('cycle', 'الدورة المستندية', 'متابعة نماذج العقود ومراحلها الخمس، والمالية والمستخلصات، مع الدليل المرجعي للدورة.',
      Icons.account_tree_rounded),
  ('risks', 'المخاطر ومتابعة المشاريع',
      'البرنامج الزمني والتقدم الدوري ومؤشر SPI، والمخاطر ومراجعاتها، والمشاكل والتأخيرات والتغييرات، والدروس المستفادة وتقييم الشركات.',
      Icons.warning_amber_rounded),
  ('swot', 'تحليل SWOT', 'عوامل القوة والضعف والفرص والتهديدات، والتقييم المرجح، واستراتيجيات TOWS وخطة التنفيذ.',
      Icons.grid_view_rounded),
  ('docs', 'المستندات الفنية',
      'المقايسات والمراسلات بصيغة PDF، والتصاميم بعرض صور متحرك يتوقف عند التأشير، مع مسار تطوير كل مستند بإصداراته.',
      Icons.folder_copy_rounded),
  ('supervision', 'الإشراف',
      'التقارير اليومية للمواقع: الأعمال المنفذة والعمالة والمعدات والمعوقات والسلامة، مع صور الموقع ومتابعة التغطية.',
      Icons.engineering_rounded),
  ('heritage', 'الترميم والمباني التاريخية',
      'سجل المباني التاريخية ببطاقة لكل مبنى وحالته الإنشائية وصوره، وتقييمات الحالة، وأعمال الترميم المرتبطة بالعقود.',
      Icons.museum_rounded),
  ('planning_qa', 'مكتب التخطيط وضمان الجودة',
      'قسم التخطيط بالخطط ونسب إنجازها، وقسم ضمان الجودة بالتدقيقات وحالات عدم المطابقة، وقسم المتابعة بالتكليفات ومواعيدها.',
      Icons.query_stats_rounded),
  ('safety', 'مكتب السلامة المهنية', 'جولات التفتيش ونسبة الالتزام، والحوادث وأيام العمل الضائعة، والمخالفات ومعالجتها في مواقع العقود.',
      Icons.health_and_safety_rounded),
  ('acceptance', 'المطابقة والاستلام',
      'وحدة الاستلام بمحاضر الاستلام وقوائم الملاحظات، ووحدة ضبط الجودة بالاختبارات ونسبة المطابقة واعتماد المواد.',
      Icons.verified_rounded),
  ('manual', 'دليل الاستخدام', 'شرح كامل لكل أقسام المنظومة وإجراءاتها وطريقة كل حساب، ويُحدَّث مع كل إصدار جديد.',
      Icons.menu_book_rounded),
];

/// اسم مختصر للقسم في المبدّل الجانبي.
const Map<String, String> sectionShortNames = {
  'cycle': 'الدورة',
  'risks': 'المخاطر',
  'swot': 'SWOT',
  'docs': 'المستندات',
  'supervision': 'الإشراف',
  'heritage': 'الترميم',
  'planning_qa': 'التخطيط',
  'safety': 'السلامة',
  'acceptance': 'الاستلام',
  'manual': 'الدليل',
};

/// هل القسم متاح؟ (المخاطر وSWOT تحتاج الترحيل 15، والمستندات والإشراف الترحيل 20، وأقسام الوحدات الترحيل 21)
bool sectionEnabled(AppState app, String key) => switch (key) {
      'cycle' || 'manual' => true,
      'docs' || 'supervision' => app.v8Ready,
      'heritage' || 'planning_qa' || 'safety' || 'acceptance' => app.v9Ready,
      _ => app.v6Ready,
    };

String sectionName(String key) => appSections.firstWhere((s) => s.$1 == key, orElse: () => appSections.first).$2;
IconData sectionIcon(String key) => appSections.firstWhere((s) => s.$1 == key, orElse: () => appSections.first).$4;

/// لون مميز لكل قسم يتكيف مع الوضع الفاتح والداكن.
Color sectionColor(BuildContext context, String key) {
  final dark = Theme.of(context).brightness == Brightness.dark;
  return switch (key) {
    'risks' => dark ? const Color(0xFFF08A5D) : const Color(0xFFB4441C),
    'swot' => dark ? const Color(0xFF7FB2F0) : const Color(0xFF2B62A8),
    'docs' => dark ? const Color(0xFF5EC4B6) : const Color(0xFF0F766E),
    'supervision' => dark ? const Color(0xFFB39DFF) : const Color(0xFF6D3FB2),
    'manual' => dark ? const Color(0xFFB8C2CE) : const Color(0xFF4F5B69),
    'heritage' => dark ? const Color(0xFFD9A066) : const Color(0xFF8A5A2B),
    'planning_qa' => dark ? const Color(0xFF9FA8FF) : const Color(0xFF3949AB),
    'safety' => dark ? const Color(0xFFE8B931) : const Color(0xFF8A6100),
    'acceptance' => dark ? const Color(0xFFF07FB8) : const Color(0xFFA3246B),
    _ => Theme.of(context).colorScheme.primary,
  };
}

/// شاشة الدخول: الأقسام الرئيسية كقوائم منفصلة، ولكل قسم مؤشرات حية مختصرة.
class SectionHub extends StatelessWidget {
  const SectionHub({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final sem = Sem.of(context);
    final t = Theme.of(context).textTheme;
    if (!app.loadedOnce) return const SkeletonPage(cards: 6);
    final first = (app.me?.displayName ?? '').split(' ').where((w) => w.isNotEmpty).take(2).join(' ');
    return PageBody(
      maxWidth: 1180,
      onRefresh: app.loadAll,
      children: staggered([
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text(first.isEmpty ? 'مرحباً' : 'مرحباً، $first', style: t.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 20),
          child: Text('اختر القسم الذي تعمل عليه. لكل قسم قائمته الخاصة، وتعود إلى هذه الشاشة من زر «الأقسام» في أعلى الصفحة.',
              style: t.bodyMedium?.copyWith(color: sem.muted)),
        ),
        ResponsiveGrid(minItemWidth: 330, spacing: 14, children: [
          for (final s in appSections) _SectionCard(app: app, section: s),
        ]),
        if (!app.v6Ready)
          const Padding(
            padding: EdgeInsets.only(top: 16),
            child: InfoBanner(
              text: 'سجل المخاطر وتحليل SWOT يعملان بعد تحديث قاعدة البيانات بالملف 20261109000015_risks_swot.sql.',
              level: 'warning',
            ),
          ),
        if (app.v8Ready && !app.v9Ready)
          const Padding(
            padding: EdgeInsets.only(top: 16),
            child: InfoBanner(
              text: 'أقسام الترميم والتخطيط وضمان الجودة والسلامة المهنية والمطابقة والاستلام تعمل بعد تحديث قاعدة البيانات '
                  'بالملف 20261114000021_unit_sections.sql.',
              level: 'warning',
            ),
          ),
        if (app.v6Ready && !app.v8Ready)
          const Padding(
            padding: EdgeInsets.only(top: 16),
            child: InfoBanner(
              text: 'المستندات الفنية والإشراف يعملان بعد تحديث قاعدة البيانات بالملف 20261114000020_documents_supervision.sql.',
              level: 'warning',
            ),
          ),
      ], stepMs: 70),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.app, required this.section});

  final AppState app;
  final (String, String, String, IconData) section;

  List<(String, String, Color?)> _stats(BuildContext context) {
    final sem = Sem.of(context);
    switch (section.$1) {
      case 'risks':
        if (!app.v6Ready) return const [];
        if (app.v7Ready) {
          final pm = app.pm;
          final late = pm.tracks.values.where((t) => t.isLate).length;
          final alerts = pm.alerts.where((a) => a.count > 0).length;
          return [
            ('$late', 'مشروع متأخر', late > 0 ? sem.danger : null),
            ('${pm.highRisksNow}', 'خطر مرتفع حالياً', pm.highRisksNow > 0 ? sem.danger : null),
            ('$alerts', 'تنبيه متابعة', alerts > 0 ? sem.wip : null),
          ];
        }
        final st = RiskStats(app.risks, app.riskConfig);
        final overdue = st.byFollowUp['overdue'] ?? 0;
        return [
          ('${st.total}', 'خطراً مسجلاً', null),
          ('${st.risks.where((r) => !r.isClosed && app.riskConfig.isHigh(r.score)).length}', 'مرتفعة نشطة', sem.danger),
          ('$overdue', 'مراجعة متأخرة', overdue > 0 ? sem.wip : null),
        ];
      case 'docs':
        if (!app.v8Ready) return const [];
        final now = DateTime.now();
        final today = DateTime(now.year, now.month, now.day);
        final letters = app.docs.ofKind('letter');
        final open = letters.where((l) => l.status == 'open').length;
        final late = letters.where((l) => l.overdue(today)).length;
        return [
          ('${app.docs.ofKind('boq').length}', 'مقايسة', null),
          ('$open', late > 0 ? 'مراسلة ($late متأخرة)' : 'مراسلة بانتظار رد', late > 0 ? sem.danger : (open > 0 ? sem.wip : null)),
          ('${app.docs.ofKind('design').length}', 'تصميماً', null),
        ];
      case 'supervision':
        if (!app.v8Ready) return const [];
        final now = DateTime.now();
        final today = DateTime(now.year, now.month, now.day);
        final active = activeSiteProjects(app);
        final reps = app.docs.reports;
        final todayN = reps.where((r) => r.reportDate == today && active.contains(r.projectId)).map((r) => r.projectId).toSet().length;
        final week = reps.where((r) => !r.reportDate.isBefore(today.subtract(const Duration(days: 6)))).length;
        final unreviewed = reps.where((r) => !r.reviewed).length;
        return [
          ('$todayN/${active.length}', 'تقارير اليوم', todayN < active.length ? sem.wip : sem.ok),
          ('$week', 'تقريراً هذا الأسبوع', null),
          if (app.isDirector)
            ('$unreviewed', 'بانتظار اطلاعك', unreviewed > 0 ? sem.wip : null)
          else
            ('${reps.where((r) => r.hasIssues && !r.reportDate.isBefore(today.subtract(const Duration(days: 6)))).length}', 'بمعوقات', sem.danger),
        ];
      case 'heritage':
        if (!app.v9Ready) return const [];
        final s = UnitStats(app.units, DateTime.now());
        return [
          ('${s.buildings}', 'مبنى مسجّلاً', null),
          ('${s.buildingsAtRisk}', 'بحالة سيئة أو خطرة', s.buildingsAtRisk > 0 ? sem.danger : null),
          ('${s.underRestoration}', 'قيد الترميم', s.underRestoration > 0 ? sem.wip : null),
        ];
      case 'planning_qa':
        if (!app.v9Ready) return const [];
        final s = UnitStats(app.units, DateTime.now());
        return [
          ('${s.activePlans}', 'خطة قيد التنفيذ', null),
          ('${s.openNcr}', 'عدم مطابقة مفتوحة', s.openNcr > 0 ? sem.danger : null),
          ('${s.overdueTasks}', 'تكليف متأخر', s.overdueTasks > 0 ? sem.wip : null),
        ];
      case 'safety':
        if (!app.v9Ready) return const [];
        final s = UnitStats(app.units, DateTime.now());
        return [
          (s.daysWithoutIncident?.toString() ?? '—', 'يوماً بلا حوادث', sem.ok),
          ('${s.openViolations}', 'مخالفة قائمة', s.openViolations > 0 ? sem.danger : null),
          ('${s.inspectionsThisMonth}', 'جولة هذا الشهر', null),
        ];
      case 'acceptance':
        if (!app.v9Ready) return const [];
        final s = UnitStats(app.units, DateTime.now());
        return [
          ('${s.openPunch}', 'ملاحظة استلام قائمة', s.openPunch > 0 ? sem.wip : null),
          ('${s.pendingTests}', 'اختبار بانتظار النتيجة', null),
          ('${s.materialsUnderReview}', 'مادة قيد المراجعة', s.materialsUnderReview > 0 ? sem.wip : null),
        ];
      case 'manual':
        return [
          ('${manualChapters.length}', 'فصلاً', null),
          (AppConfig.appVersion, 'إصدار الدليل', Theme.of(context).colorScheme.primary),
          ('PDF', 'نسخة للطباعة', null),
        ];
      case 'swot':
        if (!app.v6Ready) return const [];
        final a = app.swot;
        final avg = a.avgProgress;
        return [
          ('${a.factors.length}', 'عاملاً', null),
          (avg == null ? '—' : pctText(avg), 'إنجاز الخطة', sem.ok),
          ('${a.alerts.length}', 'تنبيه متابعة', a.alerts.isNotEmpty ? sem.wip : null),
        ];
      default:
        final list = app.scoped;
        final avg = list.isEmpty ? 0.0 : list.fold<double>(0, (s, p) => s + app.progressOf(p).pct) / list.length;
        final fs = FinanceStats(app, list);
        return [
          ('${list.length}', term('contracts'), null),
          (pctText(avg), 'إنجاز الدورة', Theme.of(context).colorScheme.primary),
          ('${fs.referredCount}', 'محال للصرف', fs.referredCount > 0 ? sem.wip : null),
        ];
    }
  }

  @override
  Widget build(BuildContext context) {
    final sem = Sem.of(context);
    final t = Theme.of(context).textTheme;
    final color = sectionColor(context, section.$1);
    final enabled = sectionEnabled(app, section.$1);
    final stats = _stats(context);
    final radius = BorderRadius.circular(appearance.radius.clamp(12, 24).toDouble());
    return HoverLift(
      child: Material(
        color: cardColor(context),
        shape: RoundedRectangleBorder(borderRadius: radius, side: BorderSide(color: sem.rule)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: enabled ? () => app.openSection(section.$1) : null,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(height: 5, color: color),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(children: [
                      Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(color: color.withValues(alpha: 0.13), borderRadius: BorderRadius.circular(15)),
                        child: Icon(section.$4, color: color, size: 28),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Text(section.$2, style: t.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                      ),
                      Icon(Icons.chevron_left_rounded, color: enabled ? color : sem.muted),
                    ]),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 44,
                      child: Text(section.$3,
                          maxLines: 2, overflow: TextOverflow.ellipsis, style: t.bodyMedium?.copyWith(color: sem.muted, height: 1.35)),
                    ),
                    const SizedBox(height: 14),
                    if (stats.isEmpty)
                      SizedBox(
                        height: 58,
                        child: Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: Text('بانتظار تحديث قاعدة البيانات', style: TextStyle(color: sem.muted)),
                        ),
                      )
                    else
                      Row(children: [
                        for (var i = 0; i < stats.length; i++) ...[
                          if (i > 0) const SizedBox(width: 8),
                          Expanded(
                            child: Container(
                              constraints: const BoxConstraints(minHeight: 58),
                              alignment: AlignmentDirectional.centerStart,
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                              decoration: BoxDecoration(color: sem.surface2, borderRadius: BorderRadius.circular(12)),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  FittedBox(
                                    fit: BoxFit.scaleDown,
                                    alignment: AlignmentDirectional.centerStart,
                                    child: Text(stats[i].$1,
                                        style: TextStyle(
                                            fontWeight: FontWeight.w800,
                                            fontSize: 18,
                                            color: stats[i].$3,
                                            fontFeatures: const [FontFeature.tabularFigures()])),
                                  ),
                                  Text(stats[i].$2,
                                      maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: sem.muted, fontSize: 11.5)),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ]),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// مبدّل الأقسام في الشريط الجانبي.
class SectionSwitcher extends StatelessWidget {
  const SectionSwitcher({super.key, required this.app});

  final AppState app;

  @override
  Widget build(BuildContext context) {
    final sem = Sem.of(context);
    Widget item((String, String, String, IconData) s) => Expanded(
          child: Tooltip(
            message: s.$2,
            child: _SwitchItem(
              label: sectionShortNames[s.$1] ?? s.$2,
              icon: s.$4,
              color: sectionColor(context, s.$1),
              selected: app.section == s.$1,
              enabled: sectionEnabled(app, s.$1),
              onTap: () => app.openSection(s.$1),
            ),
          ),
        );
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: sem.surface2, borderRadius: BorderRadius.circular(14), border: Border.all(color: sem.rule)),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        for (var i = 0; i < appSections.length; i += 5)
          Row(children: [for (final s in appSections.skip(i).take(5)) item(s)]),
      ]),
    );
  }
}

class _SwitchItem extends StatelessWidget {
  const _SwitchItem({
    required this.label,
    required this.icon,
    required this.color,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final Color color;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final sem = Sem.of(context);
    return AnimatedContainer(
      duration: Motion.of(context, 220),
      decoration: BoxDecoration(
        color: selected ? color.withValues(alpha: 0.16) : Colors.transparent,
        borderRadius: BorderRadius.circular(11),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(11),
          onTap: enabled && !selected ? onTap : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(icon, size: 20, color: selected ? color : (enabled ? sem.muted : sem.rule)),
              const SizedBox(height: 3),
              Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 11, fontWeight: selected ? FontWeight.w800 : FontWeight.w500, color: selected ? color : sem.muted)),
            ]),
          ),
        ),
      ),
    );
  }
}
