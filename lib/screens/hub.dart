import 'package:flutter/material.dart';

import '../app_state.dart';
import '../models.dart';
import '../registers.dart';
import '../ui/motion.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';
import 'finance.dart' show FinanceStats;

/// الأقسام الرئيسية الثلاثة للمنظومة: (المفتاح، الاسم، الوصف، الأيقونة)
const List<(String, String, String, IconData)> appSections = [
  ('cycle', 'الدورة المستندية', 'متابعة نماذج العقود ومراحلها الخمس، والمالية والمستخلصات، مع الدليل المرجعي للدورة.',
      Icons.account_tree_rounded),
  ('risks', 'سجل المخاطر', 'تعريف المخاطر وتقييمها قبل المعالجة وبعدها، وخطط الاستجابة، ومتابعة مواعيد المراجعة.',
      Icons.warning_amber_rounded),
  ('swot', 'تحليل SWOT', 'عوامل القوة والضعف والفرص والتهديدات، والتقييم المرجح، واستراتيجيات TOWS وخطة التنفيذ.',
      Icons.grid_view_rounded),
];

String sectionName(String key) => appSections.firstWhere((s) => s.$1 == key, orElse: () => appSections.first).$2;
IconData sectionIcon(String key) => appSections.firstWhere((s) => s.$1 == key, orElse: () => appSections.first).$4;

/// لون مميز لكل قسم يتكيف مع الوضع الفاتح والداكن.
Color sectionColor(BuildContext context, String key) {
  final dark = Theme.of(context).brightness == Brightness.dark;
  return switch (key) {
    'risks' => dark ? const Color(0xFFF08A5D) : const Color(0xFFB4441C),
    'swot' => dark ? const Color(0xFF7FB2F0) : const Color(0xFF2B62A8),
    _ => Theme.of(context).colorScheme.primary,
  };
}

/// شاشة الدخول: الأقسام الرئيسية الثلاثة كقوائم منفصلة، ولكل قسم مؤشرات حية مختصرة.
class SectionHub extends StatelessWidget {
  const SectionHub({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final sem = Sem.of(context);
    final t = Theme.of(context).textTheme;
    if (!app.loadedOnce) return const SkeletonPage(cards: 3);
    final first = (app.me?.displayName ?? '').split(' ').where((w) => w.isNotEmpty).take(2).join(' ');
    return PageBody(
      maxWidth: 1100,
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
        ResponsiveGrid(minItemWidth: 300, spacing: 14, children: [
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
        final st = RiskStats(app.risks, app.riskConfig);
        final overdue = st.byFollowUp['overdue'] ?? 0;
        return [
          ('${st.total}', 'خطراً مسجلاً', null),
          ('${st.risks.where((r) => !r.isClosed && app.riskConfig.isHigh(r.score)).length}', 'مرتفعة نشطة', sem.danger),
          ('$overdue', 'مراجعة متأخرة', overdue > 0 ? sem.wip : null),
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
    final enabled = section.$1 == 'cycle' || app.v6Ready;
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
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: sem.surface2, borderRadius: BorderRadius.circular(14), border: Border.all(color: sem.rule)),
      child: Row(children: [
        for (final s in appSections)
          Expanded(
            child: Tooltip(
              message: s.$2,
              child: _SwitchItem(
                label: s.$2,
                icon: s.$4,
                color: sectionColor(context, s.$1),
                selected: app.section == s.$1,
                enabled: s.$1 == 'cycle' || app.v6Ready,
                onTap: () => app.openSection(s.$1),
              ),
            ),
          ),
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
