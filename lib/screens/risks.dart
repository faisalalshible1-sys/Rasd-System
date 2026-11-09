import 'package:flutter/material.dart';

import '../app_state.dart';
import '../registers.dart';
import '../ui/charts.dart';
import '../ui/motion.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';
import 'contract_finance.dart' show pickDay;
import 'hub.dart' show sectionColor;

// =====================================================================
// قسم سجل المخاطر: لوحة المتابعة، والسجل، ومصفوفة التقييم ومعاييرها.
// =====================================================================

const _lvLight = [Color(0xFF2E7D4F), Color(0xFF7A9A2E), Color(0xFFC8901A), Color(0xFFD2601A), Color(0xFFB4232F)];
const _lvDark = [Color(0xFF6CC495), Color(0xFFB5CF6A), Color(0xFFE8BE5A), Color(0xFFF09257), Color(0xFFEF7F88)];

/// لون مستوى الخطر: من الأخضر (الأدنى) إلى الأحمر (الأعلى) أياً كان عدد المستويات.
Color riskLevelColor(BuildContext context, int index, int count) {
  final pal = Theme.of(context).brightness == Brightness.dark ? _lvDark : _lvLight;
  if (count <= 1) return pal.last;
  final t = index / (count - 1) * (pal.length - 1);
  final i = t.floor().clamp(0, pal.length - 2);
  return Color.lerp(pal[i], pal[i + 1], t - i)!;
}

Color riskScoreColor(BuildContext context, RiskConfig cfg, int score) =>
    riskLevelColor(context, cfg.levelIndex(score), cfg.levels.length);

Color followUpColor(Sem sem, String key) => switch (key) {
      'overdue' => sem.danger,
      'soon' => sem.wip,
      'ontime' => sem.ok,
      'closed' => sem.todo,
      _ => sem.muted,
    };

Color riskStatusColor(BuildContext context, String s) {
  final sem = Sem.of(context);
  return switch (s) {
    'open' => sem.danger,
    'in_progress' => sem.wip,
    'on_hold' => sem.muted,
    _ => sem.ok,
  };
}

String _day(DateTime? d) => d == null ? '—' : '${d.year}/${two(d.month)}/${two(d.day)}';

/// شارة الدرجة والمستوى.
class RiskScoreBadge extends StatelessWidget {
  const RiskScoreBadge({super.key, required this.score, required this.cfg, this.prefix = ''});

  final int score;
  final RiskConfig cfg;
  final String prefix;

  @override
  Widget build(BuildContext context) =>
      ToneBadge('$prefix$score · ${cfg.level(score)!.name}', color: riskScoreColor(context, cfg, score));
}

class _ScoreSquare extends StatelessWidget {
  const _ScoreSquare({required this.score, required this.cfg, this.size = 46});

  final int score;
  final RiskConfig cfg;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = riskScoreColor(context, cfg, score);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: c.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(12), border: Border.all(color: c.withValues(alpha: 0.6))),
      child: Text('$score', style: TextStyle(color: c, fontWeight: FontWeight.w900, fontSize: size * 0.38)),
    );
  }
}

/// تنبيه عند عدم تحديث قاعدة البيانات بعد.
class RegistersNotReady extends StatelessWidget {
  const RegistersNotReady({super.key, required this.title});

  final String title;

  @override
  Widget build(BuildContext context) => PageBody(children: [
        PageHeader(title: title),
        const InfoBanner(
          text: 'هذا القسم يعمل بعد تحديث قاعدة البيانات بالملف 20261109000015_risks_swot.sql.',
          level: 'warning',
        ),
      ]);
}

// =====================================================================
// خريطة الحرارة 5×5 (الاحتمالية × التأثير)
// =====================================================================
class RiskHeatMap extends StatelessWidget {
  const RiskHeatMap({super.key, required this.cfg, this.counts, this.onTap, this.maxCell = 66});

  final RiskConfig cfg;
  final List<List<int>>? counts; // counts[احتمالية-1][تأثير-1]؛ بدونها تظهر الدرجات فقط
  final void Function(int probability, int impact)? onTap;
  final double maxCell;

  @override
  Widget build(BuildContext context) {
    final sem = Sem.of(context);
    final tone = toneOf(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    return LayoutBuilder(builder: (context, c) {
      const labelW = 74.0;
      final cell = ((c.maxWidth - labelW - 8) / 5).clamp(34.0, maxCell);
      Widget box(int p, int i) {
        final s = p * i;
        final col = riskScoreColor(context, cfg, s);
        final n = counts?[p - 1][i - 1] ?? 0;
        final has = counts == null || n > 0;
        return Padding(
          padding: const EdgeInsets.all(2),
          child: Material(
            color: Color.alphaBlend(col.withValues(alpha: has ? (dark ? 0.42 : 0.30) : (dark ? 0.14 : 0.10)), tone.surface),
            borderRadius: BorderRadius.circular(8),
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: onTap == null || (counts != null && n == 0) ? null : () => onTap!(p, i),
              child: SizedBox(
                width: cell - 4,
                height: cell - 4,
                child: counts == null
                    ? Center(child: Text('$s', style: TextStyle(fontWeight: FontWeight.w800, color: tone.text)))
                    : Stack(children: [
                        PositionedDirectional(
                          top: 3,
                          start: 5,
                          child: Text('$s', style: TextStyle(fontSize: 10, color: tone.text.withValues(alpha: 0.65))),
                        ),
                        if (n > 0)
                          Center(child: Text('$n', style: TextStyle(fontWeight: FontWeight.w900, fontSize: cell * 0.3, color: tone.text))),
                      ]),
              ),
            ),
          ),
        );
      }

      Widget axis(String t) =>
          Text(t, textAlign: TextAlign.center, maxLines: 2, style: TextStyle(fontSize: 10.5, color: sem.muted, height: 1.15));

      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        for (var p = 5; p >= 1; p--)
          Row(children: [
            SizedBox(
              width: labelW,
              child: Text('$p ${probabilityLabels[p]}', style: TextStyle(fontSize: 11.5, color: sem.muted, fontWeight: FontWeight.w600)),
            ),
            for (var i = 1; i <= 5; i++) box(p, i),
          ]),
        const SizedBox(height: 4),
        Row(children: [
          SizedBox(width: labelW, child: Text('الاحتمالية ↑', style: TextStyle(fontSize: 10.5, color: sem.muted))),
          for (var i = 1; i <= 5; i++) SizedBox(width: cell, child: axis('$i\n${impactLabels[i]}')),
        ]),
        Padding(
          padding: const EdgeInsetsDirectional.only(start: labelW),
          child: SizedBox(width: cell * 5, child: axis('التأثير ←')),
        ),
      ]);
    });
  }
}

void showRisksInCell(BuildContext context, List<Risk> list, String title) {
  final app = AppScope.of(context);
  final cfg = app.riskConfig;
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) => SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.7),
        child: ListView(shrinkWrap: true, padding: const EdgeInsets.fromLTRB(16, 0, 16, 16), children: [
          Text(title, style: Theme.of(ctx).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          for (final r in list)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: _ScoreSquare(score: r.score, cfg: cfg, size: 40),
              title: Text(r.description, maxLines: 2, overflow: TextOverflow.ellipsis),
              subtitle: Text('${r.code} · ${r.statusLabel}${r.owner.isEmpty ? '' : ' · ${r.owner}'}'),
              onTap: () {
                Navigator.of(ctx).pop();
                showRiskDetails(context, r);
              },
            ),
        ]),
      ),
    ),
  );
}

// =====================================================================
// لوحة متابعة المخاطر
// =====================================================================
class RiskDashboardPage extends StatelessWidget {
  const RiskDashboardPage({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    if (!app.v6Ready) return const RegistersNotReady(title: 'لوحة متابعة المخاطر');
    final sem = Sem.of(context);
    final cfg = app.riskConfig;
    final st = RiskStats(app.risks, cfg);
    final accent = sectionColor(context, 'risks');
    final overdue = st.byFollowUp['overdue'] ?? 0;
    final soon = st.byFollowUp['soon'] ?? 0;
    final cats = st.byCategory().entries.toList()..sort((a, b) => b.value.count.compareTo(a.value.count));
    return PageBody(
      maxWidth: 1300,
      onRefresh: app.loadAll,
      children: staggered([
        PageHeader(
          title: 'لوحة متابعة المخاطر',
          subtitle: 'تقييم المخاطر قبل المعالجة وبعدها، وحالة الإجراءات، ومواعيد المراجعة.',
          icon: Icons.space_dashboard_outlined,
          actions: [
            if (app.canEditRisks)
              FilledButton.icon(
                onPressed: () => showRiskEditor(context),
                icon: const Icon(Icons.add_rounded),
                label: const Text('خطر جديد'),
              ),
          ],
        ),
        if (overdue > 0)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: InfoBanner(
              text: '$overdue ${overdue == 1 ? 'خطر تجاوز' : 'مخاطر تجاوزت'} موعد المراجعة أو الموعد المستهدف.',
              level: 'critical',
              action: TextButton(onPressed: () => app.setTab(21), child: const Text('فتح السجل')),
            ),
          ),
        ResponsiveGrid(minItemWidth: 165, spacing: 10, children: [
          StatCard(label: 'إجمالي المخاطر', value: '${st.total}', icon: Icons.list_alt_rounded, color: accent, onTap: () => app.setTab(21)),
          StatCard(label: 'مرتفعة قبل المعالجة', value: '${st.highBefore}', icon: Icons.priority_high_rounded, color: sem.danger),
          StatCard(
              label: 'مرتفعة بعد المعالجة',
              value: '${st.highAfter}',
              sub: 'من ${st.residualCount} مُقيَّمة',
              icon: Icons.shield_outlined,
              color: st.highAfter > 0 ? sem.wip : sem.ok),
          StatCard(label: 'غير مغلقة', value: '${st.notClosed}', icon: Icons.pending_actions_rounded, color: sem.wip),
          StatCard(
              label: 'نسبة الإغلاق',
              value: st.closureRate == null ? '—' : pctText(st.closureRate!),
              icon: Icons.task_alt_rounded,
              color: sem.ok),
          StatCard(
              label: 'متوسط خفض الخطر',
              value: st.avgReduction == null ? '—' : pctText(st.avgReduction!),
              sub: st.avgScore == null ? null : 'الدرجة ${st.avgScore!.toStringAsFixed(1)} ← ${st.avgResidual?.toStringAsFixed(1) ?? '—'}',
              icon: Icons.trending_down_rounded,
              color: sem.ok),
          StatCard(label: 'مراجعة متأخرة', value: '$overdue', icon: Icons.event_busy_outlined, color: overdue > 0 ? sem.danger : sem.muted),
          StatCard(label: 'مستحقة خلال ${cfg.alertDays} أيام', value: '$soon', icon: Icons.event_note_outlined, color: soon > 0 ? sem.wip : sem.muted),
        ]),
        const SizedBox(height: 16),
        ResponsiveGrid(minItemWidth: 430, spacing: 14, children: [
          SectionCard(
            title: 'المستوى قبل المعالجة وبعدها',
            icon: Icons.stacked_bar_chart_rounded,
            subtitle: 'عدد المخاطر في كل مستوى حسب الدرجة الأولية، ثم الدرجة المتبقية بعد الإجراءات.',
            child: Column(children: [
              for (var i = cfg.levels.length - 1; i >= 0; i--)
                _LevelCompareRow(
                  name: cfg.levels[i].name,
                  range: '${cfg.levels[i].min}–${cfg.maxOf(i)}',
                  color: riskLevelColor(context, i, cfg.levels.length),
                  before: st.byLevel[i] ?? 0,
                  after: st.byResidualLevel[i] ?? 0,
                  total: st.total,
                  totalAfter: st.residualCount,
                ),
            ]),
          ),
          SectionCard(
            title: 'حالة المتابعة',
            icon: Icons.event_repeat_rounded,
            subtitle: 'حسب موعد المراجعة القادمة والموعد المستهدف (التنبيه قبل ${cfg.alertDays} أيام).',
            child: Column(children: [
              StackBar(
                format: (v) => v.toInt().toString(),
                parts: [
                  for (final k in followUpKeys)
                    if ((st.byFollowUp[k] ?? 0) > 0) (followUpLabels[k]!, (st.byFollowUp[k] ?? 0).toDouble(), followUpColor(sem, k)),
                ],
              ),
              const SizedBox(height: 12),
              for (final k in followUpKeys)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(children: [
                    SizedBox(width: 110, child: ToneBadge(followUpLabels[k]!, color: followUpColor(sem, k))),
                    SizedBox(
                      width: 34,
                      child: Text('${st.byFollowUp[k] ?? 0}',
                          style: const TextStyle(fontWeight: FontWeight.w800, fontFeatures: [FontFeature.tabularFigures()])),
                    ),
                    Expanded(child: Text(followUpActions[k]!, style: TextStyle(color: sem.muted, fontSize: 12.5))),
                  ]),
                ),
            ]),
          ),
        ]),
        const SizedBox(height: 14),
        ResponsiveGrid(minItemWidth: 430, spacing: 14, children: [
          SectionCard(
            title: 'خريطة المخاطر قبل المعالجة',
            icon: Icons.grid_on_rounded,
            subtitle: 'الرقم الكبير: عدد المخاطر · الصغير: الدرجة. اضغط خلية لعرض مخاطرها.',
            child: RiskHeatMap(
              cfg: cfg,
              counts: st.heat,
              onTap: (p, i) => showRisksInCell(
                  context, app.risks.where((r) => r.probability == p && r.impact == i).toList(), 'الاحتمالية $p × التأثير $i = ${p * i}'),
            ),
          ),
          SectionCard(
            title: 'خريطة المخاطر بعد المعالجة',
            icon: Icons.grid_on_rounded,
            subtitle: 'حسب الاحتمالية والتأثير المتبقيين للمخاطر المُقيَّمة بعد الإجراءات.',
            child: RiskHeatMap(
              cfg: cfg,
              counts: st.heatAfter,
              onTap: (p, i) => showRisksInCell(
                  context,
                  app.risks.where((r) => r.residualProbability == p && r.residualImpact == i).toList(),
                  'بعد المعالجة: $p × $i = ${p * i}'),
            ),
          ),
        ]),
        const SizedBox(height: 14),
        ResponsiveGrid(minItemWidth: 430, spacing: 14, children: [
          SectionCard(
            title: 'أعلى المخاطر النشطة',
            icon: Icons.local_fire_department_outlined,
            trailing: TextButton(onPressed: () => app.setTab(21), child: const Text('السجل كاملاً')),
            child: st.topActive().isEmpty
                ? const EmptyState(title: 'لا مخاطر نشطة', icon: Icons.verified_outlined)
                : Column(children: [for (final r in st.topActive()) _RiskTile(risk: r, cfg: cfg, dense: true)]),
          ),
          SectionCard(
            title: 'حسب التصنيف',
            icon: Icons.category_outlined,
            subtitle: 'العدد · المرتفعة · متوسط الدرجة قبل المعالجة ← بعدها',
            child: Column(children: [
              for (final e in cats)
                BarRow(
                  title: e.key,
                  subtitle: '${e.value.high} مرتفعة · ${e.value.open} غير مغلقة · '
                      '${e.value.avg.toStringAsFixed(1)} ← ${e.value.avgResidual?.toStringAsFixed(1) ?? '—'}',
                  trailing: '${e.value.count}',
                  meter: AnimatedMeter(
                    value: st.total == 0 ? 0 : e.value.count / cats.first.value.count,
                    color: e.value.high > 0 ? sem.danger : accent,
                  ),
                ),
            ]),
          ),
        ]),
        const SizedBox(height: 14),
        SectionCard(
          title: 'حالة المخاطر',
          icon: Icons.donut_large_rounded,
          child: StackBar(
            format: (v) => v.toInt().toString(),
            parts: [
              for (final s in riskStatuses)
                if ((st.byStatus[s] ?? 0) > 0) (riskStatusLabels[s]!, (st.byStatus[s] ?? 0).toDouble(), riskStatusColor(context, s)),
            ],
          ),
        ),
      ], stepMs: 40),
    );
  }
}

class _LevelCompareRow extends StatelessWidget {
  const _LevelCompareRow({
    required this.name,
    required this.range,
    required this.color,
    required this.before,
    required this.after,
    required this.total,
    required this.totalAfter,
  });

  final String name;
  final String range;
  final Color color;
  final int before;
  final int after;
  final int total;
  final int totalAfter;

  @override
  Widget build(BuildContext context) {
    final sem = Sem.of(context);
    Widget meter(String l, int v, int t, double alpha) => Row(children: [
          SizedBox(width: 34, child: Text(l, style: TextStyle(fontSize: 11, color: sem.muted))),
          Expanded(child: AnimatedMeter(value: t == 0 ? 0 : v / t, color: color.withValues(alpha: alpha), height: 7)),
          SizedBox(
            width: 30,
            child: Text('$v', textAlign: TextAlign.end, style: const TextStyle(fontWeight: FontWeight.w800, fontFeatures: [FontFeature.tabularFigures()])),
          ),
        ]);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(width: 10, height: 10, margin: const EdgeInsets.only(top: 5), decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 8),
        SizedBox(
          width: 104,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(name, style: const TextStyle(fontWeight: FontWeight.w700)),
            Text(range, style: TextStyle(fontSize: 11.5, color: sem.muted)),
          ]),
        ),
        Expanded(
          child: Column(children: [
            meter('قبل', before, total, 1),
            const SizedBox(height: 5),
            meter('بعد', after, totalAfter, 0.55),
          ]),
        ),
      ]),
    );
  }
}

// =====================================================================
// سجل المخاطر
// =====================================================================
class RiskRegisterPage extends StatefulWidget {
  const RiskRegisterPage({super.key});

  @override
  State<RiskRegisterPage> createState() => _RiskRegisterPageState();
}

class _RiskRegisterPageState extends State<RiskRegisterPage> {
  final _search = TextEditingController();
  String _status = 'active';
  int _level = -1;
  String _category = '';
  String _follow = '';
  String _sort = 'score';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    if (!app.v6Ready) return const RegistersNotReady(title: 'سجل المخاطر');
    final sem = Sem.of(context);
    final cfg = app.riskConfig;
    final q = _search.text.trim();
    var list = app.risks.where((r) {
      if (_status == 'active' && r.isClosed) return false;
      if (_status != 'active' && _status != 'all' && r.status != _status) return false;
      if (_level >= 0 && cfg.levelIndex(r.score) != _level) return false;
      if (_category.isNotEmpty && r.category != _category) return false;
      if (_follow.isNotEmpty && r.followUp(cfg.alertDays) != _follow) return false;
      if (q.isNotEmpty) {
        final hay = '${r.code} ${r.description} ${r.cause} ${r.effect} ${r.owner} ${r.projectGroup} ${r.mitigation}';
        if (!hay.contains(q) && !hay.toLowerCase().contains(q.toLowerCase())) return false;
      }
      return true;
    }).toList();
    list.sort((a, b) => switch (_sort) {
          'code' => a.code.compareTo(b.code),
          'review' => (a.nextReview ?? DateTime(9999)).compareTo(b.nextReview ?? DateTime(9999)),
          'residual' => (b.residualScore ?? b.score).compareTo(a.residualScore ?? a.score),
          _ => b.score != a.score ? b.score.compareTo(a.score) : a.code.compareTo(b.code),
        });
    final cats = {...cfg.categories, ...app.risks.map((r) => r.category).where((c) => c.isNotEmpty)}.toList();
    return PageBody(
      maxWidth: 1200,
      onRefresh: app.loadAll,
      children: [
        PageHeader(
          title: 'سجل المخاطر',
          subtitle: '${app.risks.length} خطراً مسجلاً · ${app.risks.where((r) => !r.isClosed).length} غير مغلق',
          icon: Icons.list_alt_rounded,
          actions: [
            if (app.canEditRisks)
              FilledButton.icon(onPressed: () => showRiskEditor(context), icon: const Icon(Icons.add_rounded), label: const Text('خطر جديد')),
          ],
        ),
        TextField(
          controller: _search,
          onChanged: (_) => setState(() {}),
          decoration: fieldDeco('بحث بالرمز أو الوصف أو المسؤول',
              prefixIcon: const Icon(Icons.search_rounded),
              suffix: q.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () => setState(() => _search.clear()),
                    )),
        ),
        const SizedBox(height: 10),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            for (final s in [('active', 'غير المغلقة'), ('all', 'الكل'), for (final k in riskStatuses) (k, riskStatusLabels[k]!)])
              Padding(
                padding: const EdgeInsetsDirectional.only(end: 6),
                child: ChoiceChip(label: Text(s.$2), selected: _status == s.$1, onSelected: (_) => setState(() => _status = s.$1)),
              ),
          ]),
        ),
        const SizedBox(height: 10),
        Wrap(spacing: 10, runSpacing: 10, children: [
          SizedBox(
            width: 190,
            child: SelectField(
              label: 'المستوى',
              value: '$_level',
              items: [('-1', 'كل المستويات'), for (var i = cfg.levels.length - 1; i >= 0; i--) ('$i', cfg.levels[i].name)],
              onChanged: (v) => setState(() => _level = int.parse(v)),
            ),
          ),
          SizedBox(
            width: 190,
            child: SelectField(
              label: 'التصنيف',
              value: _category,
              items: [('', 'كل التصنيفات'), for (final c in cats) (c, c)],
              onChanged: (v) => setState(() => _category = v),
            ),
          ),
          SizedBox(
            width: 190,
            child: SelectField(
              label: 'المتابعة',
              value: _follow,
              items: [('', 'كل الحالات'), for (final k in followUpKeys) (k, followUpLabels[k]!)],
              onChanged: (v) => setState(() => _follow = v),
            ),
          ),
          SizedBox(
            width: 190,
            child: SelectField(
              label: 'الترتيب',
              value: _sort,
              items: const [('score', 'الأعلى درجة'), ('residual', 'الأعلى بعد المعالجة'), ('review', 'أقرب مراجعة'), ('code', 'الرمز')],
              onChanged: (v) => setState(() => _sort = v),
            ),
          ),
        ]),
        const SizedBox(height: 14),
        if (list.isEmpty)
          EmptyState(
            title: app.risks.isEmpty ? 'لا مخاطر مسجلة بعد' : 'لا نتائج مطابقة',
            message: app.risks.isEmpty ? 'أضف أول خطر من زر «خطر جديد».' : 'غيّر البحث أو عوامل التصفية.',
            icon: Icons.search_off_rounded,
          )
        else
          Container(
            decoration: cardDecoration(context),
            clipBehavior: Clip.antiAlias,
            child: Material(
              type: MaterialType.transparency,
              child: Column(children: [
                for (var i = 0; i < list.length; i++) ...[
                  if (i > 0) Divider(height: 1, color: sem.rule),
                  _RiskTile(risk: list[i], cfg: cfg),
                ],
              ]),
            ),
          ),
      ],
    );
  }
}

class _RiskTile extends StatelessWidget {
  const _RiskTile({required this.risk, required this.cfg, this.dense = false});

  final Risk risk;
  final RiskConfig cfg;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final sem = Sem.of(context);
    final r = risk;
    final f = r.followUp(cfg.alertDays);
    final rs = r.residualScore;
    final meta = [r.category, r.phase, r.projectGroup].where((x) => x.isNotEmpty).join(' · ');
    return InkWell(
      onTap: () => showRiskDetails(context, r),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: dense ? 0 : 14, vertical: dense ? 8 : 12),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _ScoreSquare(score: r.score, cfg: cfg, size: dense ? 40 : 46),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Text(r.code, style: TextStyle(color: sem.muted, fontWeight: FontWeight.w800, fontSize: 12.5)),
                if (meta.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(meta, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: sem.muted, fontSize: 12.5)),
                  ),
                ],
              ]),
              const SizedBox(height: 2),
              Text(r.description, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, height: 1.35)),
              const SizedBox(height: 6),
              Wrap(spacing: 6, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                ToneBadge(r.statusLabel, color: riskStatusColor(context, r.status)),
                if (rs != null) RiskScoreBadge(score: rs, cfg: cfg, prefix: 'بعد: '),
                if (f != 'closed' && f != 'ontime')
                  ToneBadge(
                    f == 'none' ? 'بلا موعد مراجعة' : '${followUpLabels[f]} · ${_day(r.nextReview)}',
                    color: followUpColor(sem, f),
                    icon: Icons.event_outlined,
                  ),
                if (r.owner.isNotEmpty)
                  Text(r.owner, style: TextStyle(color: sem.muted, fontSize: 12)),
              ]),
            ]),
          ),
        ]),
      ),
    );
  }
}

// =====================================================================
// تفاصيل الخطر
// =====================================================================
void showRiskDetails(BuildContext context, Risk r) {
  final app = AppScope.of(context);
  final cfg = app.riskConfig;
  final sem = Sem.of(context);
  final lv = cfg.level(r.score)!;
  final rs = r.residualScore;
  final project = r.projectId == null ? null : app.projects.where((p) => p.id == r.projectId).firstOrNull;
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) {
      Widget kv(String k, String v) => v.trim().isEmpty
          ? const SizedBox.shrink()
          : Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(k, style: TextStyle(color: sem.muted, fontSize: 12.5)),
                const SizedBox(height: 2),
                Text(v, style: const TextStyle(height: 1.4)),
              ]),
            );
      return SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.85),
          child: ListView(shrinkWrap: true, padding: const EdgeInsets.fromLTRB(20, 0, 20, 20), children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _ScoreSquare(score: r.score, cfg: cfg, size: 52),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${r.code} · ${lv.name}', style: TextStyle(color: riskScoreColor(ctx, cfg, r.score), fontWeight: FontWeight.w800)),
                  Text(r.description, style: Theme.of(ctx).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                ]),
              ),
            ]),
            const SizedBox(height: 12),
            Wrap(spacing: 6, runSpacing: 6, children: [
              ToneBadge(r.statusLabel, color: riskStatusColor(ctx, r.status)),
              ToneBadge('الاحتمالية ${r.probability} ${probabilityLabels[r.probability]}', color: sem.muted),
              ToneBadge('التأثير ${r.impact} ${impactLabels[r.impact]}', color: sem.muted),
              if (r.response.isNotEmpty) ToneBadge('الاستجابة: ${r.responseLabel}', color: sem.wip),
              ToneBadge(followUpLabels[r.followUp(cfg.alertDays)]!, color: followUpColor(sem, r.followUp(cfg.alertDays))),
            ]),
            const SizedBox(height: 14),
            if (rs != null)
              Container(
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(color: sem.surface2, borderRadius: BorderRadius.circular(12)),
                child: Row(children: [
                  const Icon(Icons.trending_down_rounded),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                        'بعد المعالجة: ${r.residualProbability} × ${r.residualImpact} = $rs (${cfg.level(rs)!.name})'
                        ' · خفض ${pctText(r.reduction ?? 0)}',
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                  ),
                ]),
              ),
            kv('الإجراء المطلوب حسب المستوى', lv.action),
            kv('السبب', r.cause),
            kv('الأثر', r.effect),
            kv('الإجراء الوقائي / المعالجة', r.mitigation),
            kv('مؤشر الإنذار المبكر', r.earlyWarning),
            kv('المسؤول', r.owner),
            kv('المشروع', r.projectGroup),
            kv('العقد المرتبط', project == null ? '' : '${project.assignNo} · ${project.name}'),
            kv('المرحلة والتصنيف', [r.phase, r.category].where((x) => x.isNotEmpty).join(' · ')),
            kv('التواريخ',
                'التسجيل ${_day(r.registeredOn)} · المراجعة القادمة ${_day(r.nextReview)} · المستهدف ${_day(r.targetDate)}${r.closedOn == null ? '' : ' · الإغلاق ${_day(r.closedOn)}'}'),
            kv('ملاحظات', r.notes),
            const SizedBox(height: 6),
            Row(children: [
              if (app.canEditRisks)
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () {
                      Navigator.of(ctx).pop();
                      showRiskEditor(context, risk: r);
                    },
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('تعديل'),
                  ),
                ),
              if (app.canEditRisks && !r.isClosed) ...[
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      Navigator.of(ctx).pop();
                      await _quickClose(context, r);
                    },
                    icon: const Icon(Icons.task_alt_rounded),
                    label: const Text('إغلاق الخطر'),
                  ),
                ),
              ],
              if (app.isDirector) ...[
                const SizedBox(width: 8),
                IconButton(
                  tooltip: 'حذف',
                  color: sem.danger,
                  onPressed: () async {
                    final ok = await confirmDialog(ctx,
                        title: 'حذف ${r.code}',
                        message: 'سيُحذف الخطر من السجل نهائياً، ويبقى أثره في سجل التدقيق.',
                        confirmLabel: 'حذف',
                        danger: true);
                    if (!ok || !ctx.mounted) return;
                    Navigator.of(ctx).pop();
                    try {
                      await app.deleteRisk(r.id);
                      if (context.mounted) showToast(context, 'حُذف ${r.code}');
                    } catch (e) {
                      if (context.mounted) showToast(context, friendlyError(e), error: true);
                    }
                  },
                  icon: const Icon(Icons.delete_outline_rounded),
                ),
              ],
            ]),
          ]),
        ),
      );
    },
  );
}

Future<void> _quickClose(BuildContext context, Risk r) async {
  final app = AppScope.of(context);
  final ok = await confirmDialog(context,
      title: 'إغلاق ${r.code}', message: 'يُسجَّل تاريخ اليوم تاريخاً للإغلاق.', confirmLabel: 'إغلاق');
  if (!ok) return;
  try {
    final data = r.toJson()
      ..['status'] = 'closed'
      ..['closed_on'] = '';
    await app.saveRisk(r.id, data);
    if (context.mounted) showToast(context, 'أُغلق ${r.code}');
  } catch (e) {
    if (context.mounted) showToast(context, friendlyError(e), error: true);
  }
}

// =====================================================================
// إضافة خطر وتعديله
// =====================================================================
Future<void> showRiskEditor(BuildContext context, {Risk? risk}) {
  final wide = MediaQuery.sizeOf(context).width >= 760;
  final editor = _RiskEditor(risk: risk);
  return showDialog<void>(
    context: context,
    builder: (ctx) => wide
        ? Dialog(
            insetPadding: const EdgeInsets.all(24),
            child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 780, maxHeight: 860), child: editor),
          )
        : Dialog.fullscreen(child: editor),
  );
}

class _RiskEditor extends StatefulWidget {
  const _RiskEditor({this.risk});

  final Risk? risk;

  @override
  State<_RiskEditor> createState() => _RiskEditorState();
}

class _RiskEditorState extends State<_RiskEditor> {
  late final Map<String, TextEditingController> _t;
  late int _p, _i;
  int? _rp, _ri;
  late String _phase, _category, _group, _owner, _response, _status;
  String? _project;
  DateTime? _registered, _review, _target;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final r = widget.risk;
    _t = {
      for (final k in ['description', 'cause', 'effect', 'mitigation', 'early_warning', 'notes'])
        k: TextEditingController(
            text: switch (k) {
          'description' => r?.description,
          'cause' => r?.cause,
          'effect' => r?.effect,
          'mitigation' => r?.mitigation,
          'early_warning' => r?.earlyWarning,
          _ => r?.notes,
        }),
    };
    _p = r?.probability ?? 3;
    _i = r?.impact ?? 3;
    _rp = r?.residualProbability;
    _ri = r?.residualImpact;
    _phase = r?.phase ?? '';
    _category = r?.category ?? '';
    _group = r?.projectGroup ?? '';
    _owner = r?.owner ?? '';
    _response = r?.response ?? '';
    _status = r?.status ?? 'open';
    _project = r?.projectId;
    _registered = r?.registeredOn ?? DateTime.now();
    _review = r?.nextReview;
    _target = r?.targetDate;
  }

  @override
  void dispose() {
    for (final c in _t.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final app = AppScope.of(context);
    if (_t['description']!.text.trim().length < 3) {
      setState(() => _error = 'اكتب وصف الخطر (3 أحرف على الأقل).');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final r = widget.risk;
    final data = <String, dynamic>{
      'code': r?.code ?? '',
      'project_group': _group,
      'project_id': _project ?? '',
      'phase': _phase,
      'category': _category,
      'description': _t['description']!.text.trim(),
      'cause': _t['cause']!.text.trim(),
      'effect': _t['effect']!.text.trim(),
      'probability': _p,
      'impact': _i,
      'mitigation': _t['mitigation']!.text.trim(),
      'response': _response,
      'owner': _owner,
      'status': _status,
      'residual_probability': _rp,
      'residual_impact': _ri,
      'next_review': isoDay(_review),
      'registered_on': isoDay(_registered),
      'target_date': isoDay(_target),
      'closed_on': _status == 'closed' ? isoDay(r?.closedOn) : '',
      'early_warning': _t['early_warning']!.text.trim(),
      'notes': _t['notes']!.text.trim(),
    };
    try {
      await app.saveRisk(r?.id, data);
      if (!mounted) return;
      Navigator.of(context).pop();
      showToast(context, r == null ? 'أُضيف الخطر إلى السجل' : 'حُفظ ${r.code}');
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = friendlyError(e);
        });
      }
    }
  }

  List<(String, String)> _opts(List<String> base, String current, String none) =>
      [('', none), for (final x in {...base, if (current.isNotEmpty) current}) (x, x)];

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final cfg = app.riskConfig;
    final sem = Sem.of(context);
    final score = _p * _i;
    final rs = _rp != null && _ri != null ? _rp! * _ri! : null;
    final lv = cfg.level(score)!;
    final projects = [...app.projects]..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

    Widget field(String key, String label, {int lines = 1, int max = 300}) => TextField(
          controller: _t[key],
          minLines: lines,
          maxLines: lines == 1 ? 1 : lines + 3,
          maxLength: max,
          decoration: fieldDeco(label).copyWith(counterText: ''),
        );

    Widget pair(Widget a, Widget b) => LayoutBuilder(
          builder: (context, c) => c.maxWidth >= 560
              ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(child: a), const SizedBox(width: 12), Expanded(child: b)])
              : Column(children: [a, const SizedBox(height: 12), b]),
        );

    Widget picker(String title, Map<int, String> labels, int? value, ValueChanged<int> onPick) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: TextStyle(color: sem.muted, fontSize: 12.5, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (var v = 1; v <= 5; v++)
                ChoiceChip(
                  visualDensity: VisualDensity.compact,
                  label: Text('$v ${labels[v]}'),
                  selected: value == v,
                  onSelected: (_) => onPick(v),
                ),
            ]),
          ],
        );

    Widget dateField(String label, DateTime? value, ValueChanged<DateTime?> onChanged) => InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () async {
            final d = await pickDay(context, value);
            if (d != null) onChanged(d);
          },
          child: InputDecorator(
            decoration: fieldDeco(label,
                suffix: value == null
                    ? const Icon(Icons.event_outlined, size: 20)
                    : IconButton(
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.close_rounded, size: 18),
                        onPressed: () => onChanged(null),
                      )),
            child: Text(value == null ? 'غير محدد' : _day(value), style: TextStyle(color: value == null ? sem.muted : null)),
          ),
        );

    final summary = Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: riskScoreColor(context, cfg, score).withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: riskScoreColor(context, cfg, score).withValues(alpha: 0.45)),
      ),
      child: Row(children: [
        _ScoreSquare(score: score, cfg: cfg, size: 48),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('الدرجة $score · ${lv.name}', style: const TextStyle(fontWeight: FontWeight.w800)),
            Text('الإجراء المطلوب: ${lv.action}', style: TextStyle(color: sem.muted, fontSize: 12.5)),
            if (rs != null)
              Text('بعد المعالجة: $rs · ${cfg.level(rs)!.name} · خفض ${pctText(1 - rs / score)}',
                  style: TextStyle(color: riskScoreColor(context, cfg, rs), fontWeight: FontWeight.w700, fontSize: 12.5)),
          ]),
        ),
      ]),
    );

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: Text(widget.risk == null ? 'خطر جديد' : 'تعديل ${widget.risk!.code}'),
        leading: IconButton(icon: const Icon(Icons.close_rounded), onPressed: () => Navigator.of(context).pop()),
        actions: [
          Padding(
            padding: const EdgeInsetsDirectional.only(end: 12),
            child: FilledButton(
              onPressed: _saving ? null : _save,
              child: _saving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('حفظ'),
            ),
          ),
        ],
      ),
      body: ListView(padding: const EdgeInsets.fromLTRB(18, 4, 18, 24), children: [
        if (_error != null) Padding(padding: const EdgeInsets.only(bottom: 12), child: InfoBanner(text: _error!, level: 'critical')),
        field('description', 'وصف الخطر *', lines: 2, max: 300),
        const SizedBox(height: 12),
        pair(field('cause', 'السبب', lines: 2, max: 500), field('effect', 'الأثر', lines: 2, max: 500)),
        const SizedBox(height: 12),
        pair(
          SelectField(label: 'المشروع', value: _group, items: _opts(cfg.projects, _group, 'غير محدد'), onChanged: (v) => setState(() => _group = v)),
          SelectField(
            label: 'العقد المرتبط (اختياري)',
            value: _project ?? '',
            items: [('', 'بلا عقد'), for (final p in projects) (p.id, '${p.assignNo} · ${p.name}')],
            onChanged: (v) => setState(() => _project = v.isEmpty ? null : v),
          ),
        ),
        const SizedBox(height: 12),
        pair(
          SelectField(label: 'المرحلة', value: _phase, items: _opts(cfg.phases, _phase, 'غير محددة'), onChanged: (v) => setState(() => _phase = v)),
          SelectField(
              label: 'التصنيف', value: _category, items: _opts(cfg.categories, _category, 'غير مصنف'), onChanged: (v) => setState(() => _category = v)),
        ),
        const SizedBox(height: 16),
        Text('التقييم قبل المعالجة', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        picker('الاحتمالية', probabilityLabels, _p, (v) => setState(() => _p = v)),
        const SizedBox(height: 10),
        picker('التأثير', impactLabels, _i, (v) => setState(() => _i = v)),
        const SizedBox(height: 12),
        summary,
        const SizedBox(height: 16),
        field('mitigation', 'الإجراء الوقائي / المعالجة', lines: 2, max: 600),
        const SizedBox(height: 12),
        pair(
          SelectField(
            label: 'نوع الاستجابة',
            value: _response,
            items: [('', 'غير محدد'), for (final k in riskResponses) (k, riskResponseLabels[k]!)],
            onChanged: (v) => setState(() => _response = v),
          ),
          SelectField(label: 'المسؤول', value: _owner, items: _opts(cfg.owners, _owner, 'غير محدد'), onChanged: (v) => setState(() => _owner = v)),
        ),
        const SizedBox(height: 12),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: _rp != null,
          title: const Text('التقييم بعد المعالجة'),
          subtitle: const Text('الاحتمالية والتأثير المتوقعان بعد تنفيذ الإجراء.'),
          onChanged: (on) => setState(() {
            _rp = on ? (_p > 1 ? _p - 1 : 1) : null;
            _ri = on ? _i : null;
          }),
        ),
        if (_rp != null) ...[
          picker('الاحتمالية بعد المعالجة', probabilityLabels, _rp, (v) => setState(() => _rp = v)),
          const SizedBox(height: 10),
          picker('التأثير بعد المعالجة', impactLabels, _ri, (v) => setState(() => _ri = v)),
        ],
        const SizedBox(height: 16),
        pair(
          SelectField(
            label: 'الحالة',
            value: _status,
            items: [for (final k in riskStatuses) (k, riskStatusLabels[k]!)],
            onChanged: (v) => setState(() => _status = v),
          ),
          dateField('تاريخ التسجيل', _registered, (d) => setState(() => _registered = d)),
        ),
        const SizedBox(height: 12),
        pair(
          dateField('موعد المراجعة القادمة', _review, (d) => setState(() => _review = d)),
          dateField('الموعد المستهدف', _target, (d) => setState(() => _target = d)),
        ),
        if (_status == 'closed' && widget.risk?.closedOn == null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text('يُسجَّل تاريخ اليوم تاريخاً للإغلاق.', style: TextStyle(color: sem.muted, fontSize: 12.5)),
          ),
        const SizedBox(height: 12),
        field('early_warning', 'مؤشر الإنذار المبكر', max: 300),
        const SizedBox(height: 12),
        field('notes', 'ملاحظات', lines: 2, max: 1000),
      ]),
    );
  }
}

// =====================================================================
// مصفوفة التقييم ومعايير التصنيف والقوائم المرجعية
// =====================================================================
class RiskMatrixPage extends StatefulWidget {
  const RiskMatrixPage({super.key});

  @override
  State<RiskMatrixPage> createState() => _RiskMatrixPageState();
}

class _RiskMatrixPageState extends State<RiskMatrixPage> {
  String _view = 'scores';

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    if (!app.v6Ready) return const RegistersNotReady(title: 'مصفوفة المخاطر ومعاييرها');
    final sem = Sem.of(context);
    final cfg = app.riskConfig;
    final st = RiskStats(app.risks, cfg);
    final canEdit = app.isDirector && !app.frozenForMe;
    return PageBody(
      maxWidth: 1200,
      onRefresh: app.loadAll,
      children: staggered([
        const PageHeader(
          title: 'مصفوفة المخاطر ومعاييرها',
          subtitle: 'الدرجة = الاحتمالية × التأثير (1–25)، ويحدد المستوى الإجراء المطلوب.',
          icon: Icons.grid_on_rounded,
        ),
        ResponsiveGrid(minItemWidth: 440, spacing: 14, children: [
          SectionCard(
            title: 'مصفوفة الاحتمالية والتأثير',
            icon: Icons.grid_4x4_rounded,
            trailing: SegmentedButton<String>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: 'scores', label: Text('الدرجات')),
                ButtonSegment(value: 'before', label: Text('قبل')),
                ButtonSegment(value: 'after', label: Text('بعد')),
              ],
              selected: {_view},
              onSelectionChanged: (s) => setState(() => _view = s.first),
            ),
            child: RiskHeatMap(
              cfg: cfg,
              counts: switch (_view) { 'before' => st.heat, 'after' => st.heatAfter, _ => null },
              onTap: _view == 'scores'
                  ? null
                  : (p, i) => showRisksInCell(
                      context,
                      app.risks
                          .where((r) => _view == 'before'
                              ? r.probability == p && r.impact == i
                              : r.residualProbability == p && r.residualImpact == i)
                          .toList(),
                      '$p × $i = ${p * i}'),
            ),
          ),
          SectionCard(
            title: 'معايير التصنيف',
            icon: Icons.rule_rounded,
            trailing: canEdit
                ? TextButton.icon(
                    onPressed: () => _editLevels(context, cfg),
                    icon: const Icon(Icons.tune_rounded, size: 18),
                    label: const Text('تعديل'),
                  )
                : null,
            child: Column(children: [
              for (var i = cfg.levels.length - 1; i >= 0; i--)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Row(children: [
                    Container(
                      width: 64,
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: riskLevelColor(context, i, cfg.levels.length).withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text('${cfg.levels[i].min}–${cfg.maxOf(i)}',
                          style: TextStyle(fontWeight: FontWeight.w800, color: riskLevelColor(context, i, cfg.levels.length))),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(cfg.levels[i].name, style: const TextStyle(fontWeight: FontWeight.w700)),
                        if (cfg.levels[i].action.isNotEmpty)
                          Text(cfg.levels[i].action, style: TextStyle(color: sem.muted, fontSize: 12.5)),
                      ]),
                    ),
                    Text('${st.byLevel[i] ?? 0}', style: const TextStyle(fontWeight: FontWeight.w800)),
                  ]),
                ),
              const Divider(height: 22),
              Row(children: [
                Icon(Icons.notifications_active_outlined, size: 18, color: sem.muted),
                const SizedBox(width: 8),
                Expanded(child: Text('التنبيه قبل موعد المراجعة بـ ${cfg.alertDays} أيام')),
              ]),
              const SizedBox(height: 6),
              Row(children: [
                Icon(Icons.priority_high_rounded, size: 18, color: sem.muted),
                const SizedBox(width: 8),
                Expanded(child: Text('«مرتفع» في المؤشرات: الدرجة ${cfg.highMin} فأعلى (المستويان الأعليان)')),
              ]),
            ]),
          ),
        ]),
        const SizedBox(height: 14),
        SectionCard(
          title: 'القوائم المرجعية',
          icon: Icons.format_list_bulleted_rounded,
          subtitle: 'الخيارات التي تظهر عند إضافة خطر.${canEdit ? ' اضغط «تعديل» لتغيير أي قائمة.' : ''}',
          child: Column(children: [
            for (final l in [
              ('phases', 'المراحل', cfg.phases),
              ('categories', 'التصنيفات', cfg.categories),
              ('projects', 'المشاريع', cfg.projects),
              ('owners', 'المسؤولون', cfg.owners),
            ])
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(child: Text('${l.$2} (${l.$3.length})', style: const TextStyle(fontWeight: FontWeight.w700))),
                    if (canEdit)
                      TextButton(onPressed: () => _editList(context, cfg, l.$1, l.$2, l.$3), child: const Text('تعديل')),
                  ]),
                  Wrap(spacing: 6, runSpacing: 6, children: [
                    for (final x in l.$3) Chip(label: Text(x), visualDensity: VisualDensity.compact),
                    if (l.$3.isEmpty) Text('لا عناصر', style: TextStyle(color: sem.muted)),
                  ]),
                ]),
              ),
          ]),
        ),
        const SizedBox(height: 14),
        SectionCard(
          title: 'أنواع الاستجابة',
          icon: Icons.alt_route_rounded,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            for (final e in const [
              ('تجنب', 'تغيير الخطة أو النطاق لإزالة مصدر الخطر.'),
              ('تخفيف', 'إجراءات تقلل الاحتمالية أو التأثير.'),
              ('نقل', 'تحويل الأثر إلى طرف آخر بالعقد أو التأمين أو الضمان.'),
              ('قبول', 'تقبّل الخطر مع المراقبة وخطة طوارئ عند الحاجة.'),
            ])
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text.rich(TextSpan(children: [
                  TextSpan(text: '${e.$1}: ', style: const TextStyle(fontWeight: FontWeight.w800)),
                  TextSpan(text: e.$2),
                ])),
              ),
          ]),
        ),
      ], stepMs: 50),
    );
  }

  Future<void> _editList(BuildContext context, RiskConfig cfg, String key, String label, List<String> current) async {
    final app = AppScope.of(context);
    final v = await textInputDialog(context,
        title: 'تعديل قائمة $label',
        message: 'عنصر في كل سطر. لا يغيّر التعديل قيم المخاطر المسجلة.',
        label: label,
        confirmLabel: 'حفظ',
        initial: current.join('\n'));
    if (v == null) return;
    final items = <String>[];
    for (final x in v.split(RegExp(r'[\n،,]'))) {
      final s = x.trim();
      if (s.isNotEmpty && !items.contains(s)) items.add(s);
    }
    final next = switch (key) {
      'phases' => cfg.copyWith(phases: items),
      'categories' => cfg.copyWith(categories: items),
      'projects' => cfg.copyWith(projects: items),
      _ => cfg.copyWith(owners: items),
    };
    try {
      await app.setSetting('risk.config', next.toJson());
      if (context.mounted) showToast(context, 'حُفظت قائمة $label');
    } catch (e) {
      if (context.mounted) showToast(context, friendlyError(e), error: true);
    }
  }

  Future<void> _editLevels(BuildContext context, RiskConfig cfg) async {
    final app = AppScope.of(context);
    final next = await showDialog<RiskConfig>(context: context, builder: (_) => _LevelsDialog(cfg: cfg));
    if (next == null) return;
    try {
      await app.setSetting('risk.config', next.toJson());
      if (context.mounted) showToast(context, 'حُفظت معايير التصنيف');
    } catch (e) {
      if (context.mounted) showToast(context, friendlyError(e), error: true);
    }
  }
}

class _LevelsDialog extends StatefulWidget {
  const _LevelsDialog({required this.cfg});

  final RiskConfig cfg;

  @override
  State<_LevelsDialog> createState() => _LevelsDialogState();
}

class _LevelsDialogState extends State<_LevelsDialog> {
  late List<(TextEditingController, TextEditingController, TextEditingController)> _rows;
  late final TextEditingController _alert;
  String? _error;

  @override
  void initState() {
    super.initState();
    _rows = [
      for (final l in widget.cfg.levels)
        (TextEditingController(text: l.name), TextEditingController(text: '${l.min}'), TextEditingController(text: l.action)),
    ];
    _alert = TextEditingController(text: '${widget.cfg.alertDays}');
  }

  @override
  void dispose() {
    for (final r in _rows) {
      r.$1.dispose();
      r.$2.dispose();
      r.$3.dispose();
    }
    _alert.dispose();
    super.dispose();
  }

  void _submit() {
    final levels = <RiskLevel>[];
    for (final r in _rows) {
      final name = r.$1.text.trim();
      final min = int.tryParse(r.$2.text.trim());
      if (name.isEmpty || min == null) {
        setState(() => _error = 'لكل مستوى اسم وبداية رقمية.');
        return;
      }
      levels.add(RiskLevel(name, min, r.$3.text.trim()));
    }
    if (levels.length < 3 || levels.length > 7) {
      setState(() => _error = 'من 3 إلى 7 مستويات.');
      return;
    }
    if (levels.first.min != 1) {
      setState(() => _error = 'يبدأ المستوى الأول من الدرجة 1.');
      return;
    }
    for (var i = 1; i < levels.length; i++) {
      if (levels[i].min <= levels[i - 1].min || levels[i].min > 25) {
        setState(() => _error = 'بدايات المستويات تصاعدية ولا تتجاوز 25.');
        return;
      }
    }
    final alert = int.tryParse(_alert.text.trim());
    if (alert == null || alert < 0 || alert > 90) {
      setState(() => _error = 'أيام التنبيه من 0 إلى 90.');
      return;
    }
    Navigator.of(context).pop(widget.cfg.copyWith(levels: levels, alertDays: alert));
  }

  @override
  Widget build(BuildContext context) {
    final sem = Sem.of(context);
    return AlertDialog(
      title: const Text('معايير التصنيف'),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('من الأدنى إلى الأعلى. «من درجة» بداية المستوى، وينتهي عند بداية التالي.', style: TextStyle(color: sem.muted)),
            const SizedBox(height: 12),
            for (var i = 0; i < _rows.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Container(
                    width: 10,
                    height: 10,
                    margin: const EdgeInsets.only(top: 18),
                    decoration: BoxDecoration(color: riskLevelColor(context, i, _rows.length), shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 8),
                  Expanded(flex: 3, child: TextField(controller: _rows[i].$1, decoration: fieldDeco('المستوى'))),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 74,
                    child: TextField(
                      controller: _rows[i].$2,
                      keyboardType: TextInputType.number,
                      textDirection: TextDirection.ltr,
                      decoration: fieldDeco('من درجة'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(flex: 4, child: TextField(controller: _rows[i].$3, decoration: fieldDeco('الإجراء'))),
                  IconButton(
                    tooltip: 'حذف المستوى',
                    onPressed: _rows.length <= 3 ? null : () => setState(() => _rows.removeAt(i)),
                    icon: const Icon(Icons.remove_circle_outline_rounded),
                  ),
                ]),
              ),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                onPressed: _rows.length >= 7
                    ? null
                    : () => setState(() => _rows.add((TextEditingController(), TextEditingController(), TextEditingController()))),
                icon: const Icon(Icons.add_rounded),
                label: const Text('مستوى'),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _alert,
              keyboardType: TextInputType.number,
              textDirection: TextDirection.ltr,
              decoration: fieldDeco('أيام التنبيه قبل موعد المراجعة'),
            ),
            if (_error != null) ...[const SizedBox(height: 10), InfoBanner(text: _error!, level: 'critical')],
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('إلغاء')),
        FilledButton(onPressed: _submit, child: const Text('حفظ')),
      ],
    );
  }
}
