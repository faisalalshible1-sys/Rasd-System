import 'package:flutter/material.dart';

import '../app_state.dart';
import '../registers.dart';
import '../ui/motion.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';
import 'contract_finance.dart' show pickDay;
import 'hub.dart' show sectionColor;
import 'risks.dart' show RegistersNotReady;

// =====================================================================
// قسم تحليل SWOT: لوحة المتابعة، والمصفوفة، والعوامل، والتقييم المرجح،
// واستراتيجيات TOWS، وخطة التنفيذ والمتابعة، والمنهجية.
// =====================================================================

Color swotColor(BuildContext context, String kind) {
  final dark = Theme.of(context).brightness == Brightness.dark;
  return switch (kind) {
    'S' => dark ? const Color(0xFF5DB88A) : const Color(0xFF1E7A4C),
    'W' => dark ? const Color(0xFFE39A62) : const Color(0xFFC2570C),
    'O' => dark ? const Color(0xFF7FB2F0) : const Color(0xFF2B62A8),
    _ => dark ? const Color(0xFFE57C85) : const Color(0xFFB4232F),
  };
}

Color strategyColor(BuildContext context, String kind) {
  final dark = Theme.of(context).brightness == Brightness.dark;
  return switch (kind) {
    'SO' => dark ? const Color(0xFF5DB88A) : const Color(0xFF1E7A4C),
    'WO' => dark ? const Color(0xFF7FB2F0) : const Color(0xFF2B62A8),
    'ST' => dark ? const Color(0xFFB7A4F2) : const Color(0xFF6B4FBB),
    _ => dark ? const Color(0xFFE39A62) : const Color(0xFFC2570C),
  };
}

Color swotPriorityColor(Sem sem, String p) => switch (p) { 'high' => sem.danger, 'medium' => sem.wip, _ => sem.ok };

Color commitmentColor(Sem sem, String c) => switch (c) {
      'completed' || 'on_track' => sem.ok,
      'behind' => sem.wip,
      'late' || 'stalled' => sem.danger,
      _ => sem.muted,
    };

const Map<int, String> importanceLabels = {5: 'أثر حرج', 4: 'أثر كبير', 3: 'متوسط', 2: 'محدود', 1: 'محدود جداً'};
const Map<int, String> urgencyLabels = {5: 'فوري (شهر)', 4: 'خلال 3 أشهر', 3: 'خلال 6 أشهر', 2: 'خلال سنة', 1: 'أكثر من سنة'};
const Map<int, String> ifeRatingLabels = {4: 'قوة رئيسية', 3: 'قوة ثانوية', 2: 'ضعف ثانوي', 1: 'ضعف رئيسي'};
const Map<int, String> efeRatingLabels = {4: 'استجابة متفوقة', 3: 'فوق المتوسط', 2: 'متوسطة', 1: 'ضعيفة'};

String _day(DateTime? d) => d == null ? '—' : '${d.year}/${two(d.month)}/${two(d.day)}';

class CodeChip extends StatelessWidget {
  const CodeChip(this.code, {super.key, required this.color, this.tooltip});

  final String code;
  final Color color;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.13), borderRadius: BorderRadius.circular(6)),
      child: Text(code,
          textDirection: TextDirection.ltr,
          style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 11.5, fontFeatures: const [FontFeature.tabularFigures()])),
    );
    return tooltip == null ? chip : Tooltip(message: tooltip!, child: chip);
  }
}

Widget _codeChips(BuildContext context, SwotAnalysis a, List<String> codes) => Wrap(spacing: 4, runSpacing: 4, children: [
      for (final c in codes) CodeChip(c, color: swotColor(context, c.substring(0, 1)), tooltip: a.byCode[c]?.factor),
    ]);

/// صف اختيار درجة 1..5 (أو قيم محددة).
Widget _scoreChoice(BuildContext context, String title, Map<int, String> labels, int? value, ValueChanged<int?> onPick,
    {List<int>? allowed, bool clearable = false}) {
  final sem = Sem.of(context);
  final keys = allowed ?? (labels.keys.toList()..sort());
  return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text(title, style: TextStyle(color: sem.muted, fontSize: 12.5, fontWeight: FontWeight.w600)),
    const SizedBox(height: 6),
    Wrap(spacing: 6, runSpacing: 6, children: [
      if (clearable)
        ChoiceChip(visualDensity: VisualDensity.compact, label: const Text('بلا'), selected: value == null, onSelected: (_) => onPick(null)),
      for (final v in keys)
        ChoiceChip(
          visualDensity: VisualDensity.compact,
          label: Text('$v ${labels[v] ?? ''}'),
          selected: value == v,
          onSelected: (_) => onPick(v),
        ),
    ]),
  ]);
}

Widget _pair(Widget a, Widget b) => LayoutBuilder(
      builder: (context, c) => c.maxWidth >= 560
          ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(child: a), const SizedBox(width: 12), Expanded(child: b)])
          : Column(children: [a, const SizedBox(height: 12), b]),
    );

Widget _dateField(BuildContext context, String label, DateTime? value, ValueChanged<DateTime?> onChanged) {
  final sem = Sem.of(context);
  return InkWell(
    borderRadius: BorderRadius.circular(10),
    onTap: () async {
      final d = await pickDay(context, value);
      if (d != null) onChanged(d);
    },
    child: InputDecorator(
      decoration: fieldDeco(label,
          suffix: value == null
              ? const Icon(Icons.event_outlined, size: 20)
              : IconButton(visualDensity: VisualDensity.compact, icon: const Icon(Icons.close_rounded, size: 18), onPressed: () => onChanged(null))),
      child: Text(value == null ? 'غير محدد' : _day(value), style: TextStyle(color: value == null ? sem.muted : null)),
    ),
  );
}

List<(String, String)> _opts(List<String> base, String current, String none) =>
    [('', none), for (final x in {...base, if (current.isNotEmpty) current}) (x, x)];

/// نافذة تحرير موحدة (ملء الشاشة على الهاتف).
Future<T?> _editorDialog<T>(BuildContext context, Widget child) {
  final wide = MediaQuery.sizeOf(context).width >= 760;
  return showDialog<T>(
    context: context,
    builder: (ctx) => wide
        ? Dialog(
            insetPadding: const EdgeInsets.all(24),
            child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 780, maxHeight: 860), child: child),
          )
        : Dialog.fullscreen(child: child),
  );
}

class _EditorScaffold extends StatelessWidget {
  const _EditorScaffold({required this.title, required this.saving, required this.onSave, required this.children, this.error});

  final String title;
  final bool saving;
  final VoidCallback onSave;
  final List<Widget> children;
  final String? error;

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          title: Text(title),
          leading: IconButton(icon: const Icon(Icons.close_rounded), onPressed: () => Navigator.of(context).pop()),
          actions: [
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 12),
              child: FilledButton(
                onPressed: saving ? null : onSave,
                child: saving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('حفظ'),
              ),
            ),
          ],
        ),
        body: ListView(padding: const EdgeInsets.fromLTRB(18, 4, 18, 24), children: [
          if (error != null) Padding(padding: const EdgeInsets.only(bottom: 12), child: InfoBanner(text: error!, level: 'critical')),
          ...children,
        ]),
      );
}

Widget _sheetKv(BuildContext context, String k, String v) {
  if (v.trim().isEmpty) return const SizedBox.shrink();
  final sem = Sem.of(context);
  return Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(k, style: TextStyle(color: sem.muted, fontSize: 12.5)),
      const SizedBox(height: 2),
      Text(v, style: const TextStyle(height: 1.4)),
    ]),
  );
}

Future<void> _sheet(BuildContext context, List<Widget> Function(BuildContext ctx) build) => showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.86),
          child: ListView(shrinkWrap: true, padding: const EdgeInsets.fromLTRB(20, 0, 20, 20), children: build(ctx)),
        ),
      ),
    );

Future<void> _guarded(BuildContext context, Future<void> Function() run, String done) async {
  try {
    await run();
    if (context.mounted) showToast(context, done);
  } catch (e) {
    if (context.mounted) showToast(context, friendlyError(e), error: true);
  }
}

// =====================================================================
// لوحة المتابعة
// =====================================================================
class SwotDashboardPage extends StatelessWidget {
  const SwotDashboardPage({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    if (!app.v6Ready) return const RegistersNotReady(title: 'لوحة متابعة SWOT');
    final sem = Sem.of(context);
    final a = app.swot;
    final meta = app.swotMeta;
    final accent = sectionColor(context, 'swot');
    final avg = a.avgProgress, planned = a.avgPlanned;
    final depts = a.byDepartment().entries.toList()..sort((x, y) => y.value.count.compareTo(x.value.count));
    final uncoveredWT = a.factors.where((f) => (f.kind == 'W' || f.kind == 'T') && !a.covered(f)).length;
    final unusedSO = a.factors.where((f) => (f.kind == 'S' || f.kind == 'O') && !a.covered(f)).length;
    final alerts = a.alerts;
    return PageBody(
      maxWidth: 1300,
      onRefresh: app.loadAll,
      children: staggered([
        PageHeader(
          title: meta.title,
          subtitle: meta.subtitle.isEmpty ? null : meta.subtitle,
          icon: Icons.space_dashboard_outlined,
          actions: [
            ToneBadge('الإصدار ${meta.version}', color: accent),
            ToneBadge(meta.status, color: sem.wip),
          ],
        ),
        if (meta.nextReview != null && !meta.nextReview!.isAfter(DateTime.now()))
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: InfoBanner(text: 'حان موعد المراجعة الشاملة للتحليل (${_day(meta.nextReview)}).', level: 'warning'),
          ),
        ResponsiveGrid(minItemWidth: MediaQuery.sizeOf(context).width < 700 ? 160 : 230, spacing: 10, children: [
          StatCard(
            label: 'العوامل',
            value: '${a.factors.length}',
            sub: [for (final k in swotKinds) '${a.ofKind(k).length} ${swotKindLabels[k]}'].join(' · '),
            icon: Icons.grid_view_rounded,
            color: accent,
            onTap: () => app.setTab(32),
          ),
          StatCard(label: 'عوامل عالية الأولوية', value: '${a.highFactors}', icon: Icons.priority_high_rounded, color: sem.danger, onTap: () => app.setTab(32)),
          StatCard(label: 'استراتيجيات TOWS', value: '${a.strategies.length}', icon: Icons.alt_route_rounded, color: accent, onTap: () => app.setTab(34)),
          StatCard(label: 'إجراءات تنفيذية', value: '${a.actionsTotal}', sub: '${a.completed} مكتمل', icon: Icons.checklist_rounded, color: sem.ok, onTap: () => app.setTab(35)),
          StatCard(
            label: 'الإنجاز الفعلي',
            value: avg == null ? '—' : pctText(avg),
            sub: planned == null ? null : 'المخطط ${pctText(planned)}',
            icon: Icons.trending_up_rounded,
            color: avg != null && planned != null && avg + 0.1 < planned ? sem.wip : sem.ok,
          ),
          StatCard(label: 'متأخرة أو متعثرة', value: '${a.lateOrStalled}', icon: Icons.running_with_errors_rounded, color: a.lateOrStalled > 0 ? sem.danger : sem.muted),
          StatCard(label: 'بانتظار التحديث', value: '${a.awaiting}', icon: Icons.update_rounded, color: a.awaiting > 0 ? sem.wip : sem.muted),
          StatCard(
            label: 'الموقع الاستراتيجي',
            value: SwotAnalysis.roman[a.ieCell - 1],
            sub: a.direction,
            icon: Icons.explore_outlined,
            color: accent,
            onTap: () => app.setTab(33),
          ),
        ]),
        const SizedBox(height: 16),
        ResponsiveGrid(minItemWidth: 430, spacing: 14, children: [
          SectionCard(
            title: 'تنبيهات المتابعة',
            icon: Icons.notifications_active_outlined,
            subtitle: 'إجراءات متأخرة أو متعثرة أو متأخرة عن الخطة أو لم يُحدَّث إنجازها.',
            trailing: TextButton(onPressed: () => app.setTab(35), child: const Text('خطة التنفيذ')),
            child: alerts.isEmpty
                ? const EmptyState(title: 'لا تنبيهات', message: 'كل الإجراءات ضمن الخطة.', icon: Icons.verified_outlined)
                : Column(children: [for (final x in alerts.take(8)) _ActionTile(action: x, analysis: a, dense: true)]),
          ),
          SectionCard(
            title: 'الإنجاز حسب القسم',
            icon: Icons.groups_2_outlined,
            subtitle: 'الفعلي مقابل المخطط حتى اليوم',
            child: Column(children: [
              for (final e in depts)
                BarRow(
                  title: e.key,
                  subtitle: '${e.value.count} إجراء${e.value.late > 0 ? ' · ${e.value.late} متأخر' : ''}'
                      ' · المخطط ${e.value.planned == null ? '—' : pctText(e.value.planned!)}',
                  trailing: e.value.actual == null ? '—' : pctText(e.value.actual!),
                  meter: Column(children: [
                    AnimatedMeter(value: e.value.actual ?? 0, color: e.value.late > 0 ? sem.wip : sem.ok),
                    const SizedBox(height: 3),
                    AnimatedMeter(value: e.value.planned ?? 0, color: sem.muted.withValues(alpha: 0.5), height: 4),
                  ]),
                ),
            ]),
          ),
        ]),
        const SizedBox(height: 14),
        ResponsiveGrid(minItemWidth: 430, spacing: 14, children: [
          SectionCard(
            title: 'الاستراتيجيات حسب النوع',
            icon: Icons.alt_route_rounded,
            child: Column(children: [
              for (final k in strategyKinds)
                Builder(builder: (context) {
                  final list = a.strategies.where((s) => s.kind == k).toList();
                  final prog = [for (final s in list) a.strategyProgress(s.code)].whereType<double>().toList();
                  final v = prog.isEmpty ? null : prog.fold<double>(0, (x, y) => x + y) / prog.length;
                  return BarRow(
                    title: '$k · ${strategyDirections[k]}',
                    subtitle: '${list.length} استراتيجية · ${strategyKindLabels[k]}',
                    trailing: v == null ? '—' : pctText(v),
                    meter: AnimatedMeter(value: v ?? 0, color: strategyColor(context, k)),
                    onTap: () => app.setTab(34),
                  );
                }),
            ]),
          ),
          SectionCard(
            title: 'التغطية',
            icon: Icons.fact_check_outlined,
            subtitle: 'الضعف والتهديد يُعالَج بإجراء، والقوة والفرصة تُستثمر باستراتيجية.',
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              for (final k in swotKinds)
                Builder(builder: (context) {
                  final list = a.ofKind(k);
                  final cov = list.where(a.covered).length;
                  return BarRow(
                    title: swotKindTitles[k]!,
                    subtitle: k == 'W' || k == 'T' ? 'مُعالَج بإجراء' : 'مُستثمَر باستراتيجية',
                    trailing: '$cov / ${list.length}',
                    meter: AnimatedMeter(value: list.isEmpty ? 0 : cov / list.length, color: swotColor(context, k)),
                    onTap: () => app.setTab(32),
                  );
                }),
              if (uncoveredWT + unusedSO > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: InfoBanner(
                    text: '${uncoveredWT > 0 ? '$uncoveredWT ضعف/تهديد بلا إجراء' : ''}'
                        '${uncoveredWT > 0 && unusedSO > 0 ? ' · ' : ''}'
                        '${unusedSO > 0 ? '$unusedSO قوة/فرصة بلا استراتيجية' : ''}',
                    level: 'warning',
                  ),
                ),
            ]),
          ),
        ]),
        const SizedBox(height: 14),
        SectionCard(
          title: 'أعلى العوامل أولوية',
          icon: Icons.local_fire_department_outlined,
          subtitle: 'الأولوية = الأهمية × الاستعجال',
          trailing: TextButton(onPressed: () => app.setTab(32), child: const Text('كل العوامل')),
          child: Column(children: [for (final f in a.topFactors(8)) _FactorTile(factor: f, analysis: a, dense: true)]),
        ),
      ], stepMs: 40),
    );
  }
}

// =====================================================================
// مصفوفة SWOT
// =====================================================================
class SwotMatrixPage extends StatelessWidget {
  const SwotMatrixPage({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    if (!app.v6Ready) return const RegistersNotReady(title: 'مصفوفة SWOT');
    final a = app.swot;
    final sem = Sem.of(context);
    Widget quad(String k) {
      final c = swotColor(context, k);
      final list = a.ofKind(k)..sort((x, y) => y.priority != x.priority ? y.priority.compareTo(x.priority) : x.code.compareTo(y.code));
      return Container(
        decoration: cardDecoration(context),
        clipBehavior: Clip.antiAlias,
        child: Material(
          type: MaterialType.transparency,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Container(
              color: c.withValues(alpha: 0.14),
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              child: Row(children: [
                Container(
                  width: 34,
                  height: 34,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(9)),
                  child: Text(k, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 17)),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(swotKindTitles[k]!, style: TextStyle(fontWeight: FontWeight.w800, color: c, fontSize: 16)),
                    Text('${swotKindEnglish[k]} · ${k == 'S' || k == 'W' ? 'داخلي' : 'خارجي'}', style: TextStyle(color: sem.muted, fontSize: 12)),
                  ]),
                ),
                Text('${list.length}', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 20, color: c)),
              ]),
            ),
            if (list.isEmpty)
              Padding(padding: const EdgeInsets.all(16), child: Text('لا عوامل', style: TextStyle(color: sem.muted)))
            else
              for (final f in list) _FactorTile(factor: f, analysis: a, compact: true),
          ]),
        ),
      );
    }

    return PageBody(
      maxWidth: 1300,
      onRefresh: app.loadAll,
      children: staggered([
        PageHeader(
          title: 'مصفوفة SWOT',
          subtitle: 'العوامل الداخلية (القوة والضعف) والخارجية (الفرص والتهديدات)، مرتبة حسب الأولوية.',
          icon: Icons.grid_view_rounded,
          actions: [
            if (app.canEditSwot)
              FilledButton.icon(onPressed: () => showFactorEditor(context), icon: const Icon(Icons.add_rounded), label: const Text('عامل جديد')),
          ],
        ),
        ResponsiveGrid(minItemWidth: 440, spacing: 14, children: [quad('S'), quad('W'), quad('O'), quad('T')]),
      ], stepMs: 60),
    );
  }
}

// =====================================================================
// العوامل والأولويات
// =====================================================================
class SwotFactorsPage extends StatefulWidget {
  const SwotFactorsPage({super.key});

  @override
  State<SwotFactorsPage> createState() => _SwotFactorsPageState();
}

class _SwotFactorsPageState extends State<SwotFactorsPage> {
  final _search = TextEditingController();
  String _kind = '';
  String _level = '';
  String _dept = '';
  bool _uncovered = false;
  (int, int)? _cell;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    if (!app.v6Ready) return const RegistersNotReady(title: 'العوامل والأولويات');
    final sem = Sem.of(context);
    final a = app.swot;
    final q = _search.text.trim();
    final list = a.factors.where((f) {
      if (_kind.isNotEmpty && f.kind != _kind) return false;
      if (_level.isNotEmpty && f.level != _level) return false;
      if (_dept.isNotEmpty && f.department != _dept) return false;
      if (_uncovered && a.covered(f)) return false;
      if (_cell != null && (f.importance != _cell!.$1 || f.urgency != _cell!.$2)) return false;
      if (q.isNotEmpty && !'${f.code} ${f.factor} ${f.impact} ${f.evidence}'.toLowerCase().contains(q.toLowerCase())) return false;
      return true;
    }).toList()
      ..sort((x, y) => y.priority != x.priority ? y.priority.compareTo(x.priority) : x.code.compareTo(y.code));
    final grid = a.priorityGrid;
    final depts = {...swotDepartments, ...a.factors.map((f) => f.department).where((d) => d.isNotEmpty)}.toList();
    return PageBody(
      maxWidth: 1250,
      onRefresh: app.loadAll,
      children: [
        PageHeader(
          title: 'العوامل والأولويات',
          subtitle: 'الأولوية = الأهمية × الاستعجال: عالية 16–25 · متوسطة 9–15 · منخفضة 1–8.',
          icon: Icons.low_priority_rounded,
          actions: [
            if (app.canEditSwot)
              FilledButton.icon(onPressed: () => showFactorEditor(context), icon: const Icon(Icons.add_rounded), label: const Text('عامل جديد')),
          ],
        ),
        ResponsiveGrid(minItemWidth: 420, spacing: 14, children: [
          SectionCard(
            title: 'خريطة الأولويات',
            icon: Icons.grid_on_rounded,
            subtitle: 'عدد العوامل لكل (أهمية × استعجال). اضغط خلية للتصفية.',
            child: _PriorityGrid(grid: grid, selected: _cell, onTap: (c) => setState(() => _cell = _cell == c ? null : c)),
          ),
          SectionCard(
            title: 'التوزيع',
            icon: Icons.pie_chart_outline_rounded,
            child: Column(children: [
              for (final k in swotKinds)
                Builder(builder: (context) {
                  final l = a.ofKind(k);
                  final hi = l.where((f) => f.level == 'high').length;
                  final md = l.where((f) => f.level == 'medium').length;
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(children: [
                      SizedBox(width: 92, child: Text(swotKindTitles[k]!, style: TextStyle(fontWeight: FontWeight.w700, color: swotColor(context, k)))),
                      Expanded(
                        child: SegmentMeter(parts: [(hi, sem.danger), (md, sem.wip), (l.length - hi - md, sem.ok)]),
                      ),
                      SizedBox(width: 34, child: Text('${l.length}', textAlign: TextAlign.end, style: const TextStyle(fontWeight: FontWeight.w800))),
                    ]),
                  );
                }),
              const SizedBox(height: 8),
              Legend(items: [(sem.danger, 'عالية'), (sem.wip, 'متوسطة'), (sem.ok, 'منخفضة')]),
            ]),
          ),
        ]),
        const SizedBox(height: 14),
        TextField(
          controller: _search,
          onChanged: (_) => setState(() {}),
          decoration: fieldDeco('بحث في العوامل', prefixIcon: const Icon(Icons.search_rounded)),
        ),
        const SizedBox(height: 10),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            for (final k in ['', ...swotKinds])
              Padding(
                padding: const EdgeInsetsDirectional.only(end: 6),
                child: ChoiceChip(
                  label: Text(k.isEmpty ? 'الكل' : swotKindTitles[k]!),
                  selected: _kind == k,
                  onSelected: (_) => setState(() => _kind = k),
                ),
              ),
            const SizedBox(width: 6),
            FilterChip(label: const Text('غير مغطاة'), selected: _uncovered, onSelected: (v) => setState(() => _uncovered = v)),
            if (_cell != null) ...[
              const SizedBox(width: 6),
              InputChip(
                label: Text('أهمية ${_cell!.$1} × استعجال ${_cell!.$2}'),
                onDeleted: () => setState(() => _cell = null),
              ),
            ],
          ]),
        ),
        const SizedBox(height: 10),
        Wrap(spacing: 10, runSpacing: 10, children: [
          SizedBox(
            width: 190,
            child: SelectField(
              label: 'الأولوية',
              value: _level,
              items: [('', 'كل الأولويات'), for (final p in swotPriorities) (p, swotPriorityLabels[p]!)],
              onChanged: (v) => setState(() => _level = v),
            ),
          ),
          SizedBox(
            width: 230,
            child: SelectField(
              label: 'القسم المعني',
              value: _dept,
              items: [('', 'كل الأقسام'), for (final d in depts) (d, d)],
              onChanged: (v) => setState(() => _dept = v),
            ),
          ),
        ]),
        const SizedBox(height: 12),
        if (list.isEmpty)
          const EmptyState(title: 'لا عوامل مطابقة', icon: Icons.search_off_rounded)
        else
          Container(
            decoration: cardDecoration(context),
            clipBehavior: Clip.antiAlias,
            child: Material(
              type: MaterialType.transparency,
              child: Column(children: [
                for (var i = 0; i < list.length; i++) ...[
                  if (i > 0) Divider(height: 1, color: sem.rule),
                  _FactorTile(factor: list[i], analysis: a),
                ],
              ]),
            ),
          ),
      ],
    );
  }
}

class _PriorityGrid extends StatelessWidget {
  const _PriorityGrid({required this.grid, this.selected, required this.onTap});

  final List<List<int>> grid; // [أهمية-1][استعجال-1]
  final (int, int)? selected;
  final ValueChanged<(int, int)> onTap;

  @override
  Widget build(BuildContext context) {
    final sem = Sem.of(context);
    final tone = toneOf(context);
    return LayoutBuilder(builder: (context, c) {
      const labelW = 64.0;
      final cell = ((c.maxWidth - labelW - 8) / 5).clamp(34.0, 62.0);
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        for (var imp = 5; imp >= 1; imp--)
          Row(children: [
            SizedBox(width: labelW, child: Text('$imp ${importanceLabels[imp]}', style: TextStyle(fontSize: 11, color: sem.muted))),
            for (var u = 1; u <= 5; u++)
              Builder(builder: (context) {
                final n = grid[imp - 1][u - 1];
                final p = priorityLevel(imp * u);
                final col = swotPriorityColor(sem, p);
                final sel = selected == (imp, u);
                return Padding(
                  padding: const EdgeInsets.all(2),
                  child: Material(
                    color: Color.alphaBlend(col.withValues(alpha: n > 0 ? 0.30 : 0.08), tone.surface),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8), side: sel ? BorderSide(color: tone.text, width: 2) : BorderSide.none),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: n == 0 ? null : () => onTap((imp, u)),
                      child: SizedBox(
                        width: cell - 4,
                        height: cell - 4,
                        child: Stack(children: [
                          PositionedDirectional(
                              top: 3, start: 5, child: Text('${imp * u}', style: TextStyle(fontSize: 10, color: tone.text.withValues(alpha: 0.6)))),
                          if (n > 0) Center(child: Text('$n', style: TextStyle(fontWeight: FontWeight.w900, fontSize: cell * 0.3))),
                        ]),
                      ),
                    ),
                  ),
                );
              }),
          ]),
        const SizedBox(height: 4),
        Row(children: [
          SizedBox(width: labelW, child: Text('الأهمية ↑', style: TextStyle(fontSize: 10.5, color: sem.muted))),
          for (var u = 1; u <= 5; u++)
            SizedBox(
              width: cell,
              child: Text('$u', textAlign: TextAlign.center, style: TextStyle(fontSize: 11, color: sem.muted, fontWeight: FontWeight.w700)),
            ),
        ]),
        Padding(
          padding: const EdgeInsetsDirectional.only(start: labelW),
          child: SizedBox(width: cell * 5, child: Text('الاستعجال ←', textAlign: TextAlign.center, style: TextStyle(fontSize: 10.5, color: sem.muted))),
        ),
      ]);
    });
  }
}

class _FactorTile extends StatelessWidget {
  const _FactorTile({required this.factor, required this.analysis, this.dense = false, this.compact = false});

  final SwotFactor factor;
  final SwotAnalysis analysis;
  final bool dense;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final sem = Sem.of(context);
    final f = factor;
    final c = swotColor(context, f.kind);
    final pc = swotPriorityColor(sem, f.level);
    return InkWell(
      onTap: () => showFactorDetails(context, f),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: dense ? 0 : 14, vertical: compact ? 8 : 11),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 42, child: Padding(padding: const EdgeInsets.only(top: 2), child: CodeChip(f.code, color: c))),
          const SizedBox(width: 8),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(f.factor, maxLines: compact ? 3 : 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, height: 1.35)),
              if (!compact) ...[
                const SizedBox(height: 5),
                Wrap(spacing: 6, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                  if (f.department.isNotEmpty) Text(f.department, style: TextStyle(color: sem.muted, fontSize: 12)),
                  ToneBadge(analysis.coverageLabel(f), color: analysis.covered(f) ? sem.ok : sem.wip),
                  if (f.proposed) ToneBadge('مقترح', color: sem.muted),
                  if (f.rating != null) Text('التقييم ${f.rating}', style: TextStyle(color: sem.muted, fontSize: 12)),
                ]),
              ],
            ]),
          ),
          const SizedBox(width: 8),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: pc.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(8)),
              child: Text('${f.priority}', style: TextStyle(color: pc, fontWeight: FontWeight.w900)),
            ),
            if (!compact) Text('${f.importance}×${f.urgency}', style: TextStyle(color: sem.muted, fontSize: 11)),
          ]),
        ]),
      ),
    );
  }
}

void showFactorDetails(BuildContext context, SwotFactor f) {
  final app = AppScope.of(context);
  final a = app.swot;
  final sem = Sem.of(context);
  final c = swotColor(context, f.kind);
  final strategies = a.strategies.where((s) => s.factors.contains(f.code)).toList();
  final actions = a.actions.where((x) => x.factors.contains(f.code)).toList();
  final ratingLabel = f.rating == null ? '' : '${f.rating} · ${(f.internal ? ifeRatingLabels : efeRatingLabels)[f.rating]}';
  _sheet(context, (ctx) => [
        Row(children: [
          CodeChip(f.code, color: c),
          const SizedBox(width: 8),
          Text(swotKindTitles[f.kind]!, style: TextStyle(color: c, fontWeight: FontWeight.w800)),
          const Spacer(),
          ToneBadge('${swotPriorityLabels[f.level]} · ${f.priority}', color: swotPriorityColor(sem, f.level)),
        ]),
        const SizedBox(height: 8),
        Text(f.factor, style: Theme.of(ctx).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800, height: 1.4)),
        const SizedBox(height: 12),
        Wrap(spacing: 6, runSpacing: 6, children: [
          ToneBadge('الأهمية ${f.importance} ${importanceLabels[f.importance]}', color: sem.muted),
          ToneBadge('الاستعجال ${f.urgency} ${urgencyLabels[f.urgency]}', color: sem.muted),
          ToneBadge(a.coverageLabel(f), color: a.covered(f) ? sem.ok : sem.wip),
        ]),
        const SizedBox(height: 14),
        _sheetKv(ctx, 'الأثر المتوقع', f.impact),
        _sheetKv(ctx, 'القسم المعني', f.department),
        _sheetKv(ctx, f.internal ? 'تقييم IFE' : 'تقييم EFE', ratingLabel),
        _sheetKv(ctx, 'مصدر التحقق', f.evidence),
        _sheetKv(ctx, 'مصدر البند', f.source),
        if (strategies.isNotEmpty) ...[
          Text('الاستراتيجيات المرتبطة', style: TextStyle(color: sem.muted, fontSize: 12.5)),
          for (final s in strategies)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: CodeChip(s.code, color: strategyColor(ctx, s.kind)),
              title: Text(s.strategy, maxLines: 2, overflow: TextOverflow.ellipsis),
            ),
        ],
        if (actions.isNotEmpty) ...[
          Text('الإجراءات المرتبطة', style: TextStyle(color: sem.muted, fontSize: 12.5)),
          for (final x in actions)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: CodeChip(x.code, color: sem.muted),
              title: Text(x.action, maxLines: 2, overflow: TextOverflow.ellipsis),
              trailing: Text(x.progress == null ? '—' : pctText(x.progress!)),
            ),
        ],
        const SizedBox(height: 8),
        if (app.canEditSwot)
          Row(children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: () {
                  Navigator.of(ctx).pop();
                  showFactorEditor(context, factor: f);
                },
                icon: const Icon(Icons.edit_outlined),
                label: const Text('تعديل'),
              ),
            ),
            if (app.isDirector) ...[
              const SizedBox(width: 8),
              IconButton(
                tooltip: 'حذف',
                color: sem.danger,
                icon: const Icon(Icons.delete_outline_rounded),
                onPressed: () async {
                  final ok = await confirmDialog(ctx,
                      title: 'حذف ${f.code}',
                      message: 'يُحذف العامل ويُزال رمزه من الاستراتيجيات والإجراءات المرتبطة.',
                      confirmLabel: 'حذف',
                      danger: true);
                  if (!ok || !ctx.mounted) return;
                  Navigator.of(ctx).pop();
                  if (context.mounted) await _guarded(context, () => app.deleteSwotFactor(f.id), 'حُذف ${f.code}');
                },
              ),
            ],
          ]),
      ]);
}

Future<void> showFactorEditor(BuildContext context, {SwotFactor? factor, String? kind}) =>
    _editorDialog<void>(context, _FactorEditor(factor: factor, kind: kind));

class _FactorEditor extends StatefulWidget {
  const _FactorEditor({this.factor, this.kind});

  final SwotFactor? factor;
  final String? kind;

  @override
  State<_FactorEditor> createState() => _FactorEditorState();
}

class _FactorEditorState extends State<_FactorEditor> {
  late final TextEditingController _factor, _impact, _evidence;
  late String _kind, _dept, _source;
  late int _imp, _urg;
  int? _rating;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final f = widget.factor;
    _factor = TextEditingController(text: f?.factor);
    _impact = TextEditingController(text: f?.impact);
    _evidence = TextEditingController(text: f?.evidence);
    _kind = f?.kind ?? widget.kind ?? 'S';
    _dept = f?.department ?? '';
    _source = f?.source ?? 'مضاف';
    _imp = f?.importance ?? 3;
    _urg = f?.urgency ?? 3;
    _rating = f?.rating;
  }

  @override
  void dispose() {
    _factor.dispose();
    _impact.dispose();
    _evidence.dispose();
    super.dispose();
  }

  List<int> get _allowed => switch (_kind) { 'S' => [3, 4], 'W' => [1, 2], _ => [1, 2, 3, 4] };

  Future<void> _save() async {
    if (_factor.text.trim().length < 3) {
      setState(() => _error = 'اكتب العامل.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final f = widget.factor;
    final data = {
      'code': f != null && f.kind == _kind ? f.code : '',
      'kind': _kind,
      'factor': _factor.text.trim(),
      'impact': _impact.text.trim(),
      'department': _dept,
      'importance': _imp,
      'urgency': _urg,
      'evidence': _evidence.text.trim(),
      'source': _source,
      'rating': _rating != null && _allowed.contains(_rating) ? _rating : null,
    };
    try {
      await AppScope.of(context).saveSwotFactor(f?.id, data);
      if (!mounted) return;
      Navigator.of(context).pop();
      showToast(context, f == null ? 'أُضيف العامل' : 'حُفظ ${f.code}');
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = friendlyError(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final sem = Sem.of(context);
    final p = _imp * _urg;
    final lv = priorityLevel(p);
    final internal = _kind == 'S' || _kind == 'W';
    return _EditorScaffold(
      title: widget.factor == null ? 'عامل جديد' : 'تعديل ${widget.factor!.code}',
      saving: _saving,
      onSave: _save,
      error: _error,
      children: [
        Text('التصنيف', style: TextStyle(color: sem.muted, fontSize: 12.5, fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final k in swotKinds)
            ChoiceChip(
              label: Text('${swotKindTitles[k]} ($k)'),
              selected: _kind == k,
              selectedColor: swotColor(context, k).withValues(alpha: 0.2),
              onSelected: (_) => setState(() {
                _kind = k;
                if (_rating != null && !_allowed.contains(_rating)) _rating = null;
              }),
            ),
        ]),
        if (widget.factor != null && widget.factor!.kind != _kind)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text('يُعطى العامل رمزاً جديداً بحرف تصنيفه، وتُحدَّث الروابط تلقائياً.', style: TextStyle(color: sem.muted, fontSize: 12.5)),
          ),
        const SizedBox(height: 14),
        TextField(controller: _factor, minLines: 2, maxLines: 5, maxLength: 300, decoration: fieldDeco('العامل *').copyWith(counterText: '')),
        const SizedBox(height: 12),
        TextField(controller: _impact, minLines: 1, maxLines: 4, maxLength: 300, decoration: fieldDeco('الأثر المتوقع').copyWith(counterText: '')),
        const SizedBox(height: 12),
        _pair(
          SelectField(label: 'القسم المعني', value: _dept, items: _opts(swotDepartments, _dept, 'غير محدد'), onChanged: (v) => setState(() => _dept = v)),
          SelectField(label: 'مصدر البند', value: _source, items: _opts(swotSources, _source, 'غير محدد'), onChanged: (v) => setState(() => _source = v)),
        ),
        const SizedBox(height: 16),
        _scoreChoice(context, 'الأهمية', importanceLabels, _imp, (v) => setState(() => _imp = v ?? _imp)),
        const SizedBox(height: 10),
        _scoreChoice(context, 'الاستعجال', urgencyLabels, _urg, (v) => setState(() => _urg = v ?? _urg)),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: swotPriorityColor(sem, lv).withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
          child: Text('الأولوية $p · ${swotPriorityLabels[lv]}',
              style: TextStyle(fontWeight: FontWeight.w800, color: swotPriorityColor(sem, lv))),
        ),
        const SizedBox(height: 16),
        _scoreChoice(context, internal ? 'تقييم IFE (القوة 3–4، الضعف 1–2)' : 'تقييم EFE (استجابة المكتب 1–4)',
            internal ? ifeRatingLabels : efeRatingLabels, _rating, (v) => setState(() => _rating = v),
            allowed: _allowed, clearable: true),
        const SizedBox(height: 14),
        TextField(controller: _evidence, maxLength: 300, decoration: fieldDeco('مصدر التحقق').copyWith(counterText: '')),
      ],
    );
  }
}

// =====================================================================
// التقييم المرجح IFE / EFE ومصفوفة IE
// =====================================================================
class SwotWeightedPage extends StatelessWidget {
  const SwotWeightedPage({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    if (!app.v6Ready) return const RegistersNotReady(title: 'التقييم المرجح');
    final sem = Sem.of(context);
    final a = app.swot;
    String n2(double v) => v.toStringAsFixed(2);
    return PageBody(
      maxWidth: 1250,
      onRefresh: app.loadAll,
      children: staggered([
        const PageHeader(
          title: 'التقييم المرجح ومصفوفة IE',
          subtitle: 'الوزن = أهمية العامل ÷ مجموع أهمية فئته (الداخلية أو الخارجية)، والنتيجة = الوزن × التقييم.',
          icon: Icons.balance_rounded,
        ),
        if (a.unrated > 0)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: InfoBanner(text: '${a.unrated} عاملاً بلا تقييم، فلا تدخل نتائجها في المجموع.', level: 'warning'),
          ),
        ResponsiveGrid(minItemWidth: 200, spacing: 10, children: [
          StatCard(label: 'مجموع IFE (الداخلي)', value: n2(a.ifeTotal), sub: 'القوة ${n2(a.strengthsScore)} · الضعف ${n2(a.weaknessesScore)}', icon: Icons.home_work_outlined),
          StatCard(label: 'مجموع EFE (الخارجي)', value: n2(a.efeTotal), sub: 'الفرص ${n2(a.opportunitiesScore)} · التهديدات ${n2(a.threatsScore)}', icon: Icons.public_rounded),
          StatCard(label: 'خلية مصفوفة IE', value: SwotAnalysis.roman[a.ieCell - 1], sub: a.direction, icon: Icons.explore_outlined, color: sectionColor(context, 'swot')),
        ]),
        const SizedBox(height: 14),
        ResponsiveGrid(minItemWidth: 520, spacing: 14, children: [
          SectionCard(
            title: 'مصفوفة IE (داخلي × خارجي)',
            icon: Icons.grid_3x3_rounded,
            subtitle: 'الأعمدة من مجموع IFE والصفوف من مجموع EFE: قوي 3–4 · متوسط 2–2.99 · ضعيف 1–1.99.',
            child: _IeMatrix(cell: a.ieCell, ife: a.ifeTotal, efe: a.efeTotal),
          ),
          SectionCard(
            title: 'قراءة النتيجة',
            icon: Icons.lightbulb_outline_rounded,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('الموقع: الخلية ${SwotAnalysis.roman[a.ieCell - 1]} — ${a.direction}', style: const TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              for (final e in const [
                ('النمو والبناء', 'I · II · IV', 'التوسع وتعميم الممارسات الناجحة والاستثمار في القدرات.'),
                ('الحفاظ والاستقرار', 'III · V · VII', 'تثبيت الأداء ومعالجة الثغرات الأساسية قبل التوسع.'),
                ('المعالجة وإعادة الهيكلة', 'VI · VIII · IX', 'أولوية لمعالجة الضعف والحد من التهديدات.'),
              ])
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Icon(e.$1 == a.direction ? Icons.radio_button_checked_rounded : Icons.radio_button_unchecked_rounded,
                        size: 18, color: e.$1 == a.direction ? sectionColor(context, 'swot') : sem.muted),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text.rich(TextSpan(children: [
                        TextSpan(text: '${e.$1} (${e.$2}): ', style: const TextStyle(fontWeight: FontWeight.w700)),
                        TextSpan(text: e.$3, style: TextStyle(color: sem.muted)),
                      ])),
                    ),
                  ]),
                ),
              const SizedBox(height: 8),
              Text('المتوسط المرجعي لكل مجموع 2.5؛ ما فوقه موقف أقوى من المتوسط.', style: TextStyle(color: sem.muted, fontSize: 12.5)),
            ]),
          ),
        ]),
        const SizedBox(height: 14),
        ResponsiveGrid(minItemWidth: 520, spacing: 14, children: [
          _WeightedTable(title: 'مصفوفة العوامل الداخلية IFE', rows: a.ife, total: a.ifeTotal, analysis: a),
          _WeightedTable(title: 'مصفوفة العوامل الخارجية EFE', rows: a.efe, total: a.efeTotal, analysis: a),
        ]),
      ], stepMs: 50),
    );
  }
}

class _WeightedTable extends StatelessWidget {
  const _WeightedTable({required this.title, required this.rows, required this.total, required this.analysis});

  final String title;
  final List<WeightedRow> rows;
  final double total;
  final SwotAnalysis analysis;

  @override
  Widget build(BuildContext context) {
    final sem = Sem.of(context);
    TextStyle head = TextStyle(color: sem.muted, fontSize: 11.5, fontWeight: FontWeight.w700);
    Widget cellText(String t, double w, {bool bold = false}) => SizedBox(
          width: w,
          child: Text(t,
              textAlign: TextAlign.center,
              style: TextStyle(fontWeight: bold ? FontWeight.w800 : FontWeight.w500, fontFeatures: const [FontFeature.tabularFigures()])),
        );
    final kinds = rows.map((r) => r.factor.kind).toSet().toList()..sort((a, b) => swotKinds.indexOf(a).compareTo(swotKinds.indexOf(b)));
    return SectionCard(
      title: title,
      icon: Icons.table_rows_outlined,
      child: Column(children: [
        Row(children: [
          const SizedBox(width: 44),
          Expanded(child: Text('العامل', style: head)),
          SizedBox(width: 50, child: Text('الوزن', textAlign: TextAlign.center, style: head)),
          SizedBox(width: 40, child: Text('التقييم', textAlign: TextAlign.center, style: head)),
          SizedBox(width: 50, child: Text('النتيجة', textAlign: TextAlign.center, style: head)),
        ]),
        const SizedBox(height: 4),
        for (final k in kinds) ...[
          Container(
            margin: const EdgeInsets.only(top: 6),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            decoration: BoxDecoration(color: swotColor(context, k).withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
            child: Row(children: [
              Expanded(child: Text(swotKindTitles[k]!, style: TextStyle(fontWeight: FontWeight.w800, color: swotColor(context, k)))),
              Text(
                  rows.where((r) => r.factor.kind == k).fold<double>(0, (s, r) => s + (r.score ?? 0)).toStringAsFixed(2),
                  style: TextStyle(fontWeight: FontWeight.w800, color: swotColor(context, k))),
            ]),
          ),
          for (final r in rows.where((r) => r.factor.kind == k))
            InkWell(
              onTap: () => showFactorDetails(context, r.factor),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(children: [
                  SizedBox(width: 44, child: Align(alignment: AlignmentDirectional.centerStart, child: CodeChip(r.factor.code, color: swotColor(context, k)))),
                  Expanded(child: Text(r.factor.factor, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, height: 1.3))),
                  cellText(pctText(r.weight, digits: 1), 50),
                  cellText(r.factor.rating?.toString() ?? '—', 40),
                  cellText(r.score == null ? '—' : r.score!.toStringAsFixed(2), 50, bold: true),
                ]),
              ),
            ),
        ],
        const Divider(height: 18),
        Row(children: [
          const Expanded(child: Text('المجموع', style: TextStyle(fontWeight: FontWeight.w800))),
          cellText('100%', 50),
          const SizedBox(width: 40),
          cellText(total.toStringAsFixed(2), 50, bold: true),
        ]),
      ]),
    );
  }
}

class _IeMatrix extends StatelessWidget {
  const _IeMatrix({required this.cell, required this.ife, required this.efe});

  final int cell;
  final double ife;
  final double efe;

  @override
  Widget build(BuildContext context) {
    final sem = Sem.of(context);
    final tone = toneOf(context);
    Color groupColor(int c) => switch (SwotAnalysis.directionOf(c)) {
          'النمو والبناء' => sem.ok,
          'الحفاظ والاستقرار' => sem.wip,
          _ => sem.danger,
        };
    const cols = ['قوي\n3.0–4.0', 'متوسط\n2.0–2.99', 'ضعيف\n1.0–1.99'];
    const rowsL = ['مرتفع\n3.0–4.0', 'متوسط\n2.0–2.99', 'منخفض\n1.0–1.99'];
    return LayoutBuilder(builder: (context, c) {
      const labelW = 70.0;
      final w = ((c.maxWidth - labelW - 6) / 3).clamp(60.0, 130.0);
      final h = (w * 0.62).clamp(52.0, 80.0);
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          SizedBox(width: labelW, child: Text('EFE ↓  IFE ←', style: TextStyle(fontSize: 10.5, color: sem.muted))),
          for (final t in cols)
            SizedBox(width: w, child: Text(t, textAlign: TextAlign.center, style: TextStyle(fontSize: 11, color: sem.muted, height: 1.2))),
        ]),
        const SizedBox(height: 4),
        for (var r = 0; r < 3; r++)
          Row(children: [
            SizedBox(width: labelW, child: Text(rowsL[r], style: TextStyle(fontSize: 11, color: sem.muted, height: 1.2))),
            for (var k = 1; k <= 3; k++)
              Builder(builder: (context) {
                final n = r * 3 + k;
                final here = n == cell;
                final g = groupColor(n);
                return Container(
                  width: w - 4,
                  height: h,
                  margin: const EdgeInsets.all(2),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: Color.alphaBlend(g.withValues(alpha: here ? 0.38 : 0.12), tone.surface),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: here ? tone.text : Colors.transparent, width: 2),
                  ),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Text(SwotAnalysis.roman[n - 1], style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: here ? tone.text : g)),
                    if (here) Text('الموقع الحالي', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: tone.text)),
                  ]),
                );
              }),
          ]),
        const SizedBox(height: 10),
        Text('IFE = ${ife.toStringAsFixed(2)} · EFE = ${efe.toStringAsFixed(2)}',
            textDirection: TextDirection.ltr, style: const TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        Legend(items: [(sem.ok, 'النمو والبناء'), (sem.wip, 'الحفاظ والاستقرار'), (sem.danger, 'المعالجة وإعادة الهيكلة')]),
      ]);
    });
  }
}

// =====================================================================
// استراتيجيات TOWS
// =====================================================================
class SwotTowsPage extends StatelessWidget {
  const SwotTowsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    if (!app.v6Ready) return const RegistersNotReady(title: 'استراتيجيات TOWS');
    final sem = Sem.of(context);
    final a = app.swot;
    Widget quad(String k) {
      final c = strategyColor(context, k);
      final list = a.strategies.where((s) => s.kind == k).toList();
      return Container(
        decoration: cardDecoration(context),
        clipBehavior: Clip.antiAlias,
        child: Material(
          type: MaterialType.transparency,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Container(
              color: c.withValues(alpha: 0.13),
              padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
              child: Row(children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(8)),
                  child: Text(k, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(strategyDirections[k]!, style: TextStyle(fontWeight: FontWeight.w800, color: c, fontSize: 15.5)),
                    Text(strategyKindLabels[k]!, style: TextStyle(color: sem.muted, fontSize: 12)),
                  ]),
                ),
                if (app.canEditSwot)
                  IconButton(
                    tooltip: 'استراتيجية $k جديدة',
                    onPressed: () => showStrategyEditor(context, kind: k),
                    icon: Icon(Icons.add_circle_outline_rounded, color: c),
                  ),
              ]),
            ),
            if (list.isEmpty)
              Padding(padding: const EdgeInsets.all(16), child: Text('لا استراتيجيات', style: TextStyle(color: sem.muted)))
            else
              for (var i = 0; i < list.length; i++) ...[
                if (i > 0) Divider(height: 1, color: sem.rule),
                _StrategyTile(strategy: list[i], analysis: a),
              ],
          ]),
        ),
      );
    }

    return PageBody(
      maxWidth: 1300,
      onRefresh: app.loadAll,
      children: staggered([
        const PageHeader(
          title: 'استراتيجيات TOWS',
          subtitle: 'ربط العوامل الداخلية بالخارجية لصياغة الاستراتيجيات، ومتوسط إنجاز إجراءات كل استراتيجية.',
          icon: Icons.alt_route_rounded,
        ),
        ResponsiveGrid(minItemWidth: 460, spacing: 14, children: [for (final k in strategyKinds) quad(k)]),
      ], stepMs: 60),
    );
  }
}

class _StrategyTile extends StatelessWidget {
  const _StrategyTile({required this.strategy, required this.analysis});

  final SwotStrategy strategy;
  final SwotAnalysis analysis;

  @override
  Widget build(BuildContext context) {
    final sem = Sem.of(context);
    final s = strategy;
    final a = analysis;
    final prog = a.strategyProgress(s.code);
    final acts = a.actionsOf[s.code] ?? const <SwotAction>[];
    return InkWell(
      onTap: () => showStrategyDetails(context, s),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            CodeChip(s.code, color: strategyColor(context, s.kind)),
            const SizedBox(width: 8),
            Expanded(child: Text(s.strategy, style: const TextStyle(fontWeight: FontWeight.w600, height: 1.35))),
            const SizedBox(width: 6),
            ToneBadge(swotPriorityLabels[s.priority] ?? s.priority, color: swotPriorityColor(sem, s.priority)),
          ]),
          const SizedBox(height: 7),
          _codeChips(context, a, s.factors),
          const SizedBox(height: 7),
          Row(children: [
            Expanded(child: AnimatedMeter(value: prog ?? 0, color: strategyColor(context, s.kind), height: 6)),
            const SizedBox(width: 8),
            Text('${prog == null ? '—' : pctText(prog)} · ${acts.length} إجراء', style: TextStyle(color: sem.muted, fontSize: 12)),
          ]),
          if (s.leadDepartment.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('القيادة: ${s.leadDepartment}', style: TextStyle(color: sem.muted, fontSize: 12)),
            ),
        ]),
      ),
    );
  }
}

void showStrategyDetails(BuildContext context, SwotStrategy s) {
  final app = AppScope.of(context);
  final a = app.swot;
  final sem = Sem.of(context);
  final acts = a.actionsOf[s.code] ?? const <SwotAction>[];
  _sheet(context, (ctx) => [
        Row(children: [
          CodeChip(s.code, color: strategyColor(ctx, s.kind)),
          const SizedBox(width: 8),
          Expanded(child: Text(strategyDirections[s.kind] ?? '', style: TextStyle(color: strategyColor(ctx, s.kind), fontWeight: FontWeight.w800))),
          ToneBadge('أولوية ${swotPriorityLabels[s.priority]}', color: swotPriorityColor(sem, s.priority)),
        ]),
        const SizedBox(height: 8),
        Text(s.strategy, style: Theme.of(ctx).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800, height: 1.4)),
        const SizedBox(height: 12),
        for (final c in s.factors)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              CodeChip(c, color: swotColor(ctx, c.substring(0, 1))),
              const SizedBox(width: 8),
              Expanded(child: Text(a.byCode[c]?.factor ?? 'عامل غير موجود', style: const TextStyle(fontSize: 13.5))),
            ]),
          ),
        const SizedBox(height: 8),
        _sheetKv(ctx, 'القسم القائد', s.leadDepartment),
        _sheetKv(ctx, 'مصدر البند', s.source),
        if (acts.isNotEmpty) ...[
          Text('الإجراءات التنفيذية', style: TextStyle(color: sem.muted, fontSize: 12.5)),
          for (final x in acts) _ActionTile(action: x, analysis: a, dense: true),
        ],
        const SizedBox(height: 8),
        if (app.canEditSwot)
          Row(children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: () {
                  Navigator.of(ctx).pop();
                  showStrategyEditor(context, strategy: s);
                },
                icon: const Icon(Icons.edit_outlined),
                label: const Text('تعديل'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () {
                  Navigator.of(ctx).pop();
                  showActionEditor(context, strategyCode: s.code);
                },
                icon: const Icon(Icons.playlist_add_rounded),
                label: const Text('إجراء لها'),
              ),
            ),
            if (app.isDirector) ...[
              const SizedBox(width: 8),
              IconButton(
                tooltip: acts.isEmpty ? 'حذف' : 'احذف إجراءاتها أولاً',
                color: sem.danger,
                icon: const Icon(Icons.delete_outline_rounded),
                onPressed: acts.isNotEmpty
                    ? null
                    : () async {
                        final ok = await confirmDialog(ctx, title: 'حذف ${s.code}', message: 'تُحذف الاستراتيجية نهائياً.', confirmLabel: 'حذف', danger: true);
                        if (!ok || !ctx.mounted) return;
                        Navigator.of(ctx).pop();
                        if (context.mounted) await _guarded(context, () => app.deleteSwotStrategy(s.id), 'حُذفت ${s.code}');
                      },
              ),
            ],
          ]),
      ]);
}

Future<void> showStrategyEditor(BuildContext context, {SwotStrategy? strategy, String? kind}) =>
    _editorDialog<void>(context, _StrategyEditor(strategy: strategy, kind: kind));

class _StrategyEditor extends StatefulWidget {
  const _StrategyEditor({this.strategy, this.kind});

  final SwotStrategy? strategy;
  final String? kind;

  @override
  State<_StrategyEditor> createState() => _StrategyEditorState();
}

class _StrategyEditorState extends State<_StrategyEditor> {
  late final TextEditingController _text;
  late String _kind, _priority, _dept, _source;
  late Set<String> _codes;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final s = widget.strategy;
    _text = TextEditingController(text: s?.strategy);
    _kind = s?.kind ?? widget.kind ?? 'SO';
    _priority = s?.priority ?? 'medium';
    _dept = s?.leadDepartment ?? '';
    _source = s?.source ?? 'مضاف';
    _codes = {...?s?.factors};
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_text.text.trim().length < 3) {
      setState(() => _error = 'اكتب الاستراتيجية.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final s = widget.strategy;
    final sorted = _codes.toList()..sort();
    final data = {
      'code': s != null && s.kind == _kind ? s.code : '',
      'kind': _kind,
      'strategy': _text.text.trim(),
      'internal_factors': sorted.where((c) => c.startsWith('S') || c.startsWith('W')).toList(),
      'external_factors': sorted.where((c) => c.startsWith('O') || c.startsWith('T')).toList(),
      'priority': _priority,
      'lead_department': _dept,
      'source': _source,
    };
    try {
      await AppScope.of(context).saveSwotStrategy(s?.id, data);
      if (!mounted) return;
      Navigator.of(context).pop();
      showToast(context, s == null ? 'أُضيفت الاستراتيجية' : 'حُفظت ${s.code}');
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = friendlyError(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final sem = Sem.of(context);
    final a = AppScope.of(context).swot;
    final internalKind = _kind.substring(0, 1);
    final externalKind = _kind.substring(1, 2);
    return _EditorScaffold(
      title: widget.strategy == null ? 'استراتيجية جديدة' : 'تعديل ${widget.strategy!.code}',
      saving: _saving,
      onSave: _save,
      error: _error,
      children: [
        Text('النوع', style: TextStyle(color: sem.muted, fontSize: 12.5, fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final k in strategyKinds)
            ChoiceChip(label: Text('$k · ${strategyDirections[k]}'), selected: _kind == k, onSelected: (_) => setState(() => _kind = k)),
        ]),
        const SizedBox(height: 6),
        Text(strategyKindLabels[_kind]!, style: TextStyle(color: sem.muted, fontSize: 12.5)),
        const SizedBox(height: 14),
        TextField(controller: _text, minLines: 2, maxLines: 6, maxLength: 400, decoration: fieldDeco('الاستراتيجية *').copyWith(counterText: '')),
        const SizedBox(height: 12),
        _pair(
          SelectField(
            label: 'الأولوية',
            value: _priority,
            items: [for (final p in swotPriorities) (p, swotPriorityLabels[p]!)],
            onChanged: (v) => setState(() => _priority = v),
          ),
          SelectField(label: 'القسم القائد', value: _dept, items: _opts(swotDepartments, _dept, 'غير محدد'), onChanged: (v) => setState(() => _dept = v)),
        ),
        const SizedBox(height: 12),
        SelectField(label: 'مصدر البند', value: _source, items: _opts(swotSources, _source, 'غير محدد'), onChanged: (v) => setState(() => _source = v)),
        const SizedBox(height: 16),
        for (final k in [internalKind, externalKind]) ...[
          Text('${swotKindTitles[k]} المرتبطة', style: TextStyle(color: swotColor(context, k), fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          _FactorPicker(
            factors: a.ofKind(k),
            selected: _codes,
            onToggle: (c, on) => setState(() => on ? _codes.add(c) : _codes.remove(c)),
          ),
          const SizedBox(height: 12),
        ],
        if (_codes.any((c) => !c.startsWith(internalKind) && !c.startsWith(externalKind)))
          InfoBanner(
            text: 'عوامل من فئات أخرى ما زالت مرتبطة: ${_codes.where((c) => !c.startsWith(internalKind) && !c.startsWith(externalKind)).join('، ')}.',
            level: 'info',
            action: TextButton(
              onPressed: () => setState(() => _codes.removeWhere((c) => !c.startsWith(internalKind) && !c.startsWith(externalKind))),
              child: const Text('إزالتها'),
            ),
          ),
      ],
    );
  }
}

class _FactorPicker extends StatelessWidget {
  const _FactorPicker({required this.factors, required this.selected, required this.onToggle});

  final List<SwotFactor> factors;
  final Set<String> selected;
  final void Function(String code, bool on) onToggle;

  @override
  Widget build(BuildContext context) {
    final sem = Sem.of(context);
    if (factors.isEmpty) return Text('لا عوامل في هذه الفئة', style: TextStyle(color: sem.muted));
    return Column(children: [
      for (final f in factors)
        CheckboxListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          value: selected.contains(f.code),
          onChanged: (v) => onToggle(f.code, v ?? false),
          title: Text.rich(TextSpan(children: [
            TextSpan(text: '${f.code}  ', style: TextStyle(fontWeight: FontWeight.w800, color: swotColor(context, f.kind))),
            TextSpan(text: f.factor),
          ]), maxLines: 2, overflow: TextOverflow.ellipsis),
        ),
    ]);
  }
}

// =====================================================================
// خطة التنفيذ والمتابعة
// =====================================================================
class SwotPlanPage extends StatefulWidget {
  const SwotPlanPage({super.key});

  @override
  State<SwotPlanPage> createState() => _SwotPlanPageState();
}

class _SwotPlanPageState extends State<SwotPlanPage> {
  final _search = TextEditingController();
  String _dept = '';
  String _status = '';
  String _commit = '';
  bool _mine = false;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    if (!app.v6Ready) return const RegistersNotReady(title: 'خطة التنفيذ والمتابعة');
    final sem = Sem.of(context);
    final a = app.swot;
    final q = _search.text.trim().toLowerCase();
    final list = a.actions.where((x) {
      if (_dept.isNotEmpty && x.department != _dept) return false;
      if (_status.isNotEmpty && x.status != _status) return false;
      if (_commit == 'attention' && !x.needsAttention(a.today)) return false;
      if (_commit.isNotEmpty && _commit != 'attention' && x.commitment(a.today) != _commit) return false;
      if (_mine && !app.canUpdateSwotAction(x.department)) return false;
      if (q.isNotEmpty && !'${x.code} ${x.action} ${x.output} ${x.owner} ${x.kpi}'.toLowerCase().contains(q)) return false;
      return true;
    }).toList();
    final depts = {...swotDepartments, ...a.actions.map((x) => x.department).where((d) => d.isNotEmpty)}.toList();
    final avg = a.avgProgress, planned = a.avgPlanned;
    final isHead = !app.canEditSwot && app.actionsEditableCount(a) > 0;
    return PageBody(
      maxWidth: 1250,
      onRefresh: app.loadAll,
      children: [
        PageHeader(
          title: 'خطة التنفيذ والمتابعة',
          subtitle: '${a.actionsTotal} إجراء · ${a.completed} مكتمل · ${a.lateOrStalled} متأخر أو متعثر · ${a.awaiting} بانتظار التحديث',
          icon: Icons.checklist_rounded,
          actions: [
            if (app.canEditSwot)
              FilledButton.icon(onPressed: () => showActionEditor(context), icon: const Icon(Icons.add_rounded), label: const Text('إجراء جديد')),
          ],
        ),
        if (isHead)
          const Padding(
            padding: EdgeInsets.only(bottom: 12),
            child: InfoBanner(text: 'يمكنك تحديث إنجاز إجراءات قسمك: افتح الإجراء ثم «تحديث الإنجاز».', level: 'info'),
          ),
        SectionCard(
          title: 'الإنجاز الكلي',
          icon: Icons.trending_up_rounded,
          child: Column(children: [
            Row(children: [
              SizedBox(width: 70, child: Text('الفعلي', style: TextStyle(color: sem.muted))),
              Expanded(child: AnimatedMeter(value: avg ?? 0, color: sem.ok, height: 10)),
              SizedBox(width: 56, child: Text(avg == null ? '—' : pctText(avg), textAlign: TextAlign.end, style: const TextStyle(fontWeight: FontWeight.w800))),
            ]),
            const SizedBox(height: 8),
            Row(children: [
              SizedBox(width: 70, child: Text('المخطط', style: TextStyle(color: sem.muted))),
              Expanded(child: AnimatedMeter(value: planned ?? 0, color: sem.muted.withValues(alpha: 0.6), height: 10)),
              SizedBox(width: 56, child: Text(planned == null ? '—' : pctText(planned), textAlign: TextAlign.end, style: const TextStyle(fontWeight: FontWeight.w800))),
            ]),
          ]),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _search,
          onChanged: (_) => setState(() {}),
          decoration: fieldDeco('بحث في الإجراءات', prefixIcon: const Icon(Icons.search_rounded)),
        ),
        const SizedBox(height: 10),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            for (final c in [('', 'الكل'), ('attention', 'تحتاج متابعة'), ('late', 'متأخر'), ('behind', 'متأخر عن الخطة'), ('awaiting', 'بانتظار التحديث'), ('on_track', 'ضمن الخطة'), ('completed', 'مكتمل')])
              Padding(
                padding: const EdgeInsetsDirectional.only(end: 6),
                child: ChoiceChip(label: Text(c.$2), selected: _commit == c.$1, onSelected: (_) => setState(() => _commit = c.$1)),
              ),
            if (!app.canEditSwot && app.role != null) ...[
              const SizedBox(width: 6),
              FilterChip(label: const Text('إجراءات قسمي'), selected: _mine, onSelected: (v) => setState(() => _mine = v)),
            ],
          ]),
        ),
        const SizedBox(height: 10),
        Wrap(spacing: 10, runSpacing: 10, children: [
          SizedBox(
            width: 230,
            child: SelectField(
              label: 'القسم المسؤول',
              value: _dept,
              items: [('', 'كل الأقسام'), for (final d in depts) (d, d)],
              onChanged: (v) => setState(() => _dept = v),
            ),
          ),
          SizedBox(
            width: 190,
            child: SelectField(
              label: 'الحالة',
              value: _status,
              items: [('', 'كل الحالات'), for (final s in actionStatuses) (s, actionStatusLabels[s]!)],
              onChanged: (v) => setState(() => _status = v),
            ),
          ),
        ]),
        const SizedBox(height: 12),
        if (list.isEmpty)
          const EmptyState(title: 'لا إجراءات مطابقة', icon: Icons.search_off_rounded)
        else
          Container(
            decoration: cardDecoration(context),
            clipBehavior: Clip.antiAlias,
            child: Material(
              type: MaterialType.transparency,
              child: Column(children: [
                for (var i = 0; i < list.length; i++) ...[
                  if (i > 0) Divider(height: 1, color: sem.rule),
                  _ActionTile(action: list[i], analysis: a),
                ],
              ]),
            ),
          ),
      ],
    );
  }
}

extension on AppState {
  int actionsEditableCount(SwotAnalysis a) => a.actions.where((x) => canUpdateSwotAction(x.department)).length;
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({required this.action, required this.analysis, this.dense = false});

  final SwotAction action;
  final SwotAnalysis analysis;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final sem = Sem.of(context);
    final x = action;
    final cm = x.commitment(analysis.today);
    final planned = x.planned(analysis.today);
    final days = x.daysRemaining(analysis.today);
    return InkWell(
      onTap: () => showActionDetails(context, x),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: dense ? 0 : 14, vertical: dense ? 8 : 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            CodeChip(x.code, color: sem.muted),
            if (x.strategyCode != null) ...[
              const SizedBox(width: 4),
              CodeChip(x.strategyCode!, color: strategyColor(context, x.strategyKind ?? 'SO'), tooltip: analysis.strategyByCode[x.strategyCode]?.strategy),
            ],
            const SizedBox(width: 8),
            Expanded(
              child: Text(x.action,
                  maxLines: dense ? 2 : 3, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, height: 1.35)),
            ),
            const SizedBox(width: 6),
            ToneBadge(commitmentLabels[cm] ?? cm, color: commitmentColor(sem, cm)),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: Column(children: [
                AnimatedMeter(value: x.progress ?? 0, color: commitmentColor(sem, cm), height: 7),
                const SizedBox(height: 3),
                AnimatedMeter(value: planned ?? 0, color: sem.muted.withValues(alpha: 0.45), height: 3),
              ]),
            ),
            const SizedBox(width: 10),
            Text('${x.progress == null ? '—' : pctText(x.progress!)} / ${planned == null ? '—' : pctText(planned)}',
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5, fontFeatures: [FontFeature.tabularFigures()])),
          ]),
          if (!dense) ...[
            const SizedBox(height: 6),
            Wrap(spacing: 10, runSpacing: 4, children: [
              if (x.department.isNotEmpty) _meta(sem, Icons.apartment_rounded, x.department),
              if (x.owner.isNotEmpty) _meta(sem, Icons.person_outline_rounded, x.owner),
              if (x.startDate != null) _meta(sem, Icons.date_range_outlined, '${_day(x.startDate)} ← ${_day(x.endDate)}'),
              if (days != null) _meta(sem, Icons.hourglass_bottom_rounded, days >= 0 ? 'متبقٍ $days يوماً' : 'تجاوز بـ ${-days} يوماً'),
            ]),
          ],
        ]),
      ),
    );
  }

  Widget _meta(Sem sem, IconData icon, String t) => Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 14, color: sem.muted),
        const SizedBox(width: 3),
        Text(t, style: TextStyle(color: sem.muted, fontSize: 12)),
      ]);
}

void showActionDetails(BuildContext context, SwotAction x) {
  final app = AppScope.of(context);
  final a = app.swot;
  final sem = Sem.of(context);
  final cm = x.commitment(a.today);
  final strat = x.strategyCode == null ? null : a.strategyByCode[x.strategyCode];
  _sheet(context, (ctx) => [
        Row(children: [
          CodeChip(x.code, color: sem.muted),
          const SizedBox(width: 8),
          ToneBadge(x.statusLabel, color: sem.muted),
          const SizedBox(width: 6),
          ToneBadge(commitmentLabels[cm] ?? cm, color: commitmentColor(sem, cm)),
          const Spacer(),
          ToneBadge('أولوية ${swotPriorityLabels[x.priority]}', color: swotPriorityColor(sem, x.priority)),
        ]),
        const SizedBox(height: 8),
        Text(x.action, style: Theme.of(ctx).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800, height: 1.4)),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: sem.surface2, borderRadius: BorderRadius.circular(12)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
                'الإنجاز الفعلي ${x.progress == null ? '—' : pctText(x.progress!)} · المخطط ${x.planned(a.today) == null ? '—' : pctText(x.planned(a.today)!)}'
                '${x.deviation(a.today) == null ? '' : ' · الانحراف ${(x.deviation(a.today)! * 100).round()} نقطة'}',
                style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text('البدء ${_day(x.startDate)} · المدة ${x.durationMonths ?? '—'} شهر · الانتهاء ${_day(x.endDate)}',
                style: TextStyle(color: sem.muted, fontSize: 12.5)),
          ]),
        ),
        const SizedBox(height: 12),
        if (strat != null) _sheetKv(ctx, 'الاستراتيجية ${strat.code}', strat.strategy),
        if (x.factors.isNotEmpty) ...[
          Text('العوامل المرتبطة', style: TextStyle(color: sem.muted, fontSize: 12.5)),
          const SizedBox(height: 4),
          _codeChips(ctx, a, x.factors),
          const SizedBox(height: 10),
        ],
        _sheetKv(ctx, 'المخرج المتوقع', x.output),
        _sheetKv(ctx, 'القسم المسؤول · المسؤول المباشر', [x.department, x.owner].where((e) => e.isNotEmpty).join(' · ')),
        _sheetKv(ctx, 'مؤشر القياس', x.kpi),
        _sheetKv(ctx, 'مصدر التحقق', x.verification),
        _sheetKv(ctx, 'دورية المراجعة', x.reviewCycle),
        _sheetKv(ctx, 'ملاحظات المتابعة', x.notes),
        _sheetKv(ctx, 'مصدر البند', x.source),
        if (x.updatedAt != null) Text('آخر تحديث: ${fmtDate(x.updatedAt)}', style: TextStyle(color: sem.muted, fontSize: 12)),
        const SizedBox(height: 12),
        Row(children: [
          if (app.canUpdateSwotAction(x.department))
            Expanded(
              child: FilledButton.icon(
                onPressed: () {
                  Navigator.of(ctx).pop();
                  showProgressDialog(context, x);
                },
                icon: const Icon(Icons.update_rounded),
                label: const Text('تحديث الإنجاز'),
              ),
            ),
          if (app.canEditSwot) ...[
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () {
                  Navigator.of(ctx).pop();
                  showActionEditor(context, action: x);
                },
                icon: const Icon(Icons.edit_outlined),
                label: const Text('تعديل كامل'),
              ),
            ),
          ],
          if (app.isDirector) ...[
            const SizedBox(width: 8),
            IconButton(
              tooltip: 'حذف',
              color: sem.danger,
              icon: const Icon(Icons.delete_outline_rounded),
              onPressed: () async {
                final ok = await confirmDialog(ctx, title: 'حذف ${x.code}', message: 'يُحذف الإجراء من خطة التنفيذ نهائياً.', confirmLabel: 'حذف', danger: true);
                if (!ok || !ctx.mounted) return;
                Navigator.of(ctx).pop();
                if (context.mounted) await _guarded(context, () => app.deleteSwotAction(x.id), 'حُذف ${x.code}');
              },
            ),
          ],
        ]),
      ]);
}

/// المتابعة الدورية: الحالة والإنجاز والبدء والمدة والملاحظات (لرئيس القسم المسؤول أيضاً).
Future<void> showProgressDialog(BuildContext context, SwotAction x) async {
  final app = AppScope.of(context);
  var status = x.status;
  var progress = x.progress;
  var start = x.startDate;
  var months = x.durationMonths;
  final notes = TextEditingController(text: x.notes);
  String? error;
  var saving = false;
  await showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(builder: (ctx, set) {
      final sem = Sem.of(ctx);
      return AlertDialog(
        title: Text('تحديث إنجاز ${x.code}'),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(x.action, maxLines: 3, overflow: TextOverflow.ellipsis, style: TextStyle(color: sem.muted)),
              const SizedBox(height: 14),
              SelectField(
                label: 'الحالة',
                value: status,
                items: [for (final s in actionStatuses) (s, actionStatusLabels[s]!)],
                onChanged: (v) => set(() {
                  status = v;
                  if (v == 'completed') progress = 1;
                }),
              ),
              const SizedBox(height: 12),
              Row(children: [
                Text('نسبة الإنجاز', style: TextStyle(color: sem.muted)),
                const Spacer(),
                Text(progress == null ? 'غير محدد' : pctText(progress!), style: const TextStyle(fontWeight: FontWeight.w800)),
                if (progress != null && status != 'completed')
                  IconButton(
                    tooltip: 'بلا قيمة',
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.close_rounded, size: 18),
                    onPressed: () => set(() => progress = null),
                  ),
              ]),
              Slider(
                value: progress ?? 0,
                divisions: 20,
                label: pctText(progress ?? 0),
                onChanged: status == 'completed' ? null : (v) => set(() => progress = v),
              ),
              const SizedBox(height: 4),
              _pair(
                _dateField(ctx, 'تاريخ البدء', start, (d) => set(() => start = d)),
                SelectField(
                  label: 'المدة',
                  value: '${months ?? ''}',
                  items: [('', 'غير محددة'), for (final m in {...[1, 2, 3, 4, 6, 9, 12, 18, 24, 36], if (months != null) months!}.toList()..sort()) ('$m', '$m شهر')],
                  onChanged: (v) => set(() => months = int.tryParse(v)),
                ),
              ),
              const SizedBox(height: 12),
              TextField(controller: notes, minLines: 2, maxLines: 5, maxLength: 1000, decoration: fieldDeco('ملاحظات المتابعة')),
              if (error != null) InfoBanner(text: error!, level: 'critical'),
            ]),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('إلغاء')),
          FilledButton(
            onPressed: saving
                ? null
                : () async {
                    set(() {
                      saving = true;
                      error = null;
                    });
                    try {
                      await app.updateSwotAction(x.id, start: start, months: months, status: status, progress: progress, notes: notes.text.trim());
                      if (ctx.mounted) Navigator.of(ctx).pop();
                      if (context.mounted) showToast(context, 'حُدّث إنجاز ${x.code}');
                    } catch (e) {
                      set(() {
                        saving = false;
                        error = friendlyError(e);
                      });
                    }
                  },
            child: const Text('حفظ'),
          ),
        ],
      );
    }),
  );
  notes.dispose();
}

Future<void> showActionEditor(BuildContext context, {SwotAction? action, String? strategyCode}) =>
    _editorDialog<void>(context, _ActionEditor(action: action, strategyCode: strategyCode));

class _ActionEditor extends StatefulWidget {
  const _ActionEditor({this.action, this.strategyCode});

  final SwotAction? action;
  final String? strategyCode;

  @override
  State<_ActionEditor> createState() => _ActionEditorState();
}

class _ActionEditorState extends State<_ActionEditor> {
  late final Map<String, TextEditingController> _t;
  late String _strategy, _dept, _priority, _review, _status, _source;
  late Set<String> _codes;
  DateTime? _start;
  int? _months;
  double? _progress;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final x = widget.action;
    _t = {
      'action': TextEditingController(text: x?.action),
      'output': TextEditingController(text: x?.output),
      'owner': TextEditingController(text: x?.owner),
      'kpi': TextEditingController(text: x?.kpi),
      'verification': TextEditingController(text: x?.verification),
      'notes': TextEditingController(text: x?.notes),
    };
    _strategy = x?.strategyCode ?? widget.strategyCode ?? '';
    _dept = x?.department ?? '';
    _priority = x?.priority ?? 'medium';
    _review = x?.reviewCycle ?? 'شهريًا';
    _status = x?.status ?? 'not_started';
    _source = x?.source ?? 'مضاف';
    _codes = {...?x?.factors};
    _start = x?.startDate;
    _months = x?.durationMonths;
    _progress = x?.progress;
  }

  @override
  void dispose() {
    for (final c in _t.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_t['action']!.text.trim().length < 3) {
      setState(() => _error = 'اكتب الإجراء التنفيذي.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final x = widget.action;
    final data = {
      'code': x?.code ?? '',
      'strategy_code': _strategy,
      'factors': (_codes.toList()..sort()),
      'action': _t['action']!.text.trim(),
      'output': _t['output']!.text.trim(),
      'department': _dept,
      'owner': _t['owner']!.text.trim(),
      'kpi': _t['kpi']!.text.trim(),
      'priority': _priority,
      'start_date': isoDay(_start),
      'duration_months': _months,
      'verification': _t['verification']!.text.trim(),
      'review_cycle': _review,
      'status': _status,
      'progress': _status == 'completed' ? 1 : _progress,
      'notes': _t['notes']!.text.trim(),
      'source': _source,
    };
    try {
      await AppScope.of(context).saveSwotAction(x?.id, data);
      if (!mounted) return;
      Navigator.of(context).pop();
      showToast(context, x == null ? 'أُضيف الإجراء' : 'حُفظ ${x.code}');
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = friendlyError(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final sem = Sem.of(context);
    final a = AppScope.of(context).swot;
    Widget field(String k, String label, {int lines = 1, int max = 300}) => TextField(
          controller: _t[k],
          minLines: lines,
          maxLines: lines == 1 ? 1 : lines + 3,
          maxLength: max,
          decoration: fieldDeco(label).copyWith(counterText: ''),
        );
    final strat = a.strategyByCode[_strategy];
    return _EditorScaffold(
      title: widget.action == null ? 'إجراء جديد' : 'تعديل ${widget.action!.code}',
      saving: _saving,
      onSave: _save,
      error: _error,
      children: [
        SelectField(
          label: 'الاستراتيجية',
          value: _strategy,
          items: [
            ('', 'بلا استراتيجية'),
            for (final s in a.strategies) (s.code, '${s.code} · ${s.strategy.length > 60 ? '${s.strategy.substring(0, 60)}…' : s.strategy}'),
          ],
          onChanged: (v) => setState(() {
            _strategy = v;
            final s = a.strategyByCode[v];
            if (s != null && _codes.isEmpty) _codes = {...s.factors};
          }),
        ),
        if (strat != null) ...[
          const SizedBox(height: 6),
          Text('عوامل الاستراتيجية: ${strat.factors.join('، ')}', style: TextStyle(color: sem.muted, fontSize: 12.5)),
        ],
        const SizedBox(height: 12),
        field('action', 'الإجراء التنفيذي *', lines: 2, max: 500),
        const SizedBox(height: 12),
        field('output', 'المخرج المتوقع', lines: 1),
        const SizedBox(height: 12),
        _pair(
          SelectField(label: 'القسم المسؤول', value: _dept, items: _opts(swotDepartments, _dept, 'غير محدد'), onChanged: (v) => setState(() => _dept = v)),
          field('owner', 'المسؤول المباشر', max: 120),
        ),
        const SizedBox(height: 12),
        field('kpi', 'مؤشر القياس'),
        const SizedBox(height: 12),
        _pair(
          SelectField(
            label: 'الأولوية',
            value: _priority,
            items: [for (final p in swotPriorities) (p, swotPriorityLabels[p]!)],
            onChanged: (v) => setState(() => _priority = v),
          ),
          SelectField(label: 'دورية المراجعة', value: _review, items: _opts(swotReviewCycles, _review, 'غير محددة'), onChanged: (v) => setState(() => _review = v)),
        ),
        const SizedBox(height: 12),
        _pair(
          _dateField(context, 'تاريخ البدء', _start, (d) => setState(() => _start = d)),
          SelectField(
            label: 'المدة',
            value: '${_months ?? ''}',
            items: [('', 'غير محددة'), for (final m in {...[1, 2, 3, 4, 6, 9, 12, 18, 24, 36], if (_months != null) _months!}.toList()..sort()) ('$m', '$m شهر')],
            onChanged: (v) => setState(() => _months = int.tryParse(v)),
          ),
        ),
        const SizedBox(height: 12),
        _pair(
          SelectField(
            label: 'الحالة',
            value: _status,
            items: [for (final s in actionStatuses) (s, actionStatusLabels[s]!)],
            onChanged: (v) => setState(() => _status = v),
          ),
          SelectField(label: 'مصدر البند', value: _source, items: _opts(swotSources, _source, 'غير محدد'), onChanged: (v) => setState(() => _source = v)),
        ),
        const SizedBox(height: 8),
        Row(children: [
          Text('نسبة الإنجاز', style: TextStyle(color: sem.muted)),
          const Spacer(),
          Text(_status == 'completed' ? '100%' : (_progress == null ? 'غير محدد' : pctText(_progress!)), style: const TextStyle(fontWeight: FontWeight.w800)),
        ]),
        Slider(
          value: _status == 'completed' ? 1 : (_progress ?? 0),
          divisions: 20,
          onChanged: _status == 'completed' ? null : (v) => setState(() => _progress = v),
        ),
        const SizedBox(height: 8),
        field('verification', 'مصدر التحقق'),
        const SizedBox(height: 12),
        field('notes', 'ملاحظات المتابعة', lines: 2, max: 1000),
        const SizedBox(height: 16),
        Text('العوامل المرتبطة', style: TextStyle(color: sem.muted, fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final f in a.factors)
            Tooltip(
              message: f.factor,
              child: FilterChip(
                visualDensity: VisualDensity.compact,
                label: Text(f.code, textDirection: TextDirection.ltr),
                selected: _codes.contains(f.code),
                selectedColor: swotColor(context, f.kind).withValues(alpha: 0.22),
                onSelected: (on) => setState(() => on ? _codes.add(f.code) : _codes.remove(f.code)),
              ),
            ),
        ]),
      ],
    );
  }
}

// =====================================================================
// المنهجية والحوكمة وبيانات الوثيقة
// =====================================================================
class SwotMethodPage extends StatelessWidget {
  const SwotMethodPage({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final sem = Sem.of(context);
    final meta = app.swotMeta;
    final canEdit = app.isDirector && !app.frozenForMe;
    Widget bullet(String t) => Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(padding: const EdgeInsets.only(top: 7), child: Icon(Icons.circle, size: 6, color: sem.muted)),
            const SizedBox(width: 8),
            Expanded(child: Text(t, style: const TextStyle(height: 1.45))),
          ]),
        );
    const stages = [
      ('جمع البيانات', 'مراجعة الوثائق والتقارير ومقابلات رؤساء الأقسام لحصر العوامل الأولية.'),
      ('ورشة التحقق', 'عرض العوامل على رؤساء الأقسام لتأكيدها وحذف المكرر وإضافة الناقص.'),
      ('التقييم والترتيب', 'تقدير الأهمية والاستعجال لكل عامل (1–5) وحساب الأولوية.'),
      ('الترجيح الكمي', 'حساب أوزان العوامل وتقييمها في مصفوفتي IFE وEFE وتحديد الموقع في مصفوفة IE.'),
      ('صياغة الاستراتيجيات', 'ربط العوامل الداخلية بالخارجية في مصفوفة TOWS (SO · WO · ST · WT).'),
      ('خطة التنفيذ', 'تحويل الاستراتيجيات إلى إجراءات بمسؤول ومدة ومؤشر قياس ومصدر تحقق.'),
      ('المتابعة والمراجعة', 'تحديث الإنجاز دورياً ومقارنته بالمخطط ومراجعة التحليل كاملاً كل دورة.'),
    ];
    return PageBody(
      maxWidth: 1150,
      onRefresh: app.loadAll,
      children: staggered([
        const PageHeader(title: 'المنهجية والحوكمة', subtitle: 'كيف أُعد التحليل، ومقاييس التقييم، ودورية المتابعة.', icon: Icons.menu_book_outlined),
        SectionCard(
          title: 'بيانات الوثيقة',
          icon: Icons.description_outlined,
          trailing: canEdit
              ? TextButton.icon(onPressed: () => _editMeta(context, meta), icon: const Icon(Icons.edit_outlined, size: 18), label: const Text('تعديل'))
              : null,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(meta.title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
            if (meta.subtitle.isNotEmpty) Text(meta.subtitle, style: TextStyle(color: sem.muted)),
            const SizedBox(height: 12),
            ResponsiveGrid(minItemWidth: 220, spacing: 10, children: [
              for (final kv in [
                ('الإصدار', meta.version),
                ('تاريخ الإصدار', _day(meta.issueDate)),
                ('الحالة', meta.status),
                ('دورة المراجعة', 'كل ${meta.reviewCycleMonths} أشهر'),
                ('المراجعة القادمة', _day(meta.nextReview)),
                ('إعداد', meta.preparedBy),
                ('مراجعة', meta.reviewedBy),
                ('اعتماد', meta.approvedBy),
              ])
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: sem.surface2, borderRadius: BorderRadius.circular(10)),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(kv.$1, style: TextStyle(color: sem.muted, fontSize: 12)),
                    Text(kv.$2.isEmpty ? '—' : kv.$2, style: const TextStyle(fontWeight: FontWeight.w700)),
                  ]),
                ),
            ]),
          ]),
        ),
        const SizedBox(height: 14),
        SectionCard(
          title: 'الغرض والنطاق',
          icon: Icons.flag_outlined,
          child: Column(children: [
            bullet('تشخيص الوضع الداخلي للمكتب الهندسي (القوة والضعف) والبيئة الخارجية (الفرص والتهديدات) في مشروع إعادة الإعمار.'),
            bullet('ترتيب العوامل حسب الأولوية وصياغة استراتيجيات قابلة للتنفيذ والقياس.'),
            bullet('ربط كل استراتيجية بإجراءات ومسؤولين ومؤشرات، ومتابعة الإنجاز مقابل المخطط.'),
          ]),
        ),
        const SizedBox(height: 14),
        SectionCard(
          title: 'مراحل إعداد التحليل',
          icon: Icons.timeline_rounded,
          child: Column(children: [
            for (var i = 0; i < stages.length; i++)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(radius: 15, child: Text('${i + 1}', style: const TextStyle(fontWeight: FontWeight.w800))),
                title: Text(stages[i].$1, style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text(stages[i].$2),
              ),
          ]),
        ),
        const SizedBox(height: 14),
        ResponsiveGrid(minItemWidth: 420, spacing: 14, children: [
          SectionCard(
            title: 'مقياس الأهمية والاستعجال',
            icon: Icons.straighten_rounded,
            child: Column(children: [
              for (var v = 5; v >= 1; v--)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(children: [
                    CircleAvatar(radius: 13, child: Text('$v', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800))),
                    const SizedBox(width: 10),
                    Expanded(child: Text(importanceLabels[v]!, style: const TextStyle(fontWeight: FontWeight.w600))),
                    Expanded(child: Text(urgencyLabels[v]!, style: TextStyle(color: sem.muted))),
                  ]),
                ),
              const Divider(height: 20),
              for (final p in swotPriorities)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(children: [
                    ToneBadge(swotPriorityLabels[p]!, color: swotPriorityColor(sem, p)),
                    const SizedBox(width: 10),
                    Text(switch (p) { 'high' => '16–25', 'medium' => '9–15', _ => '1–8' }, style: const TextStyle(fontWeight: FontWeight.w700)),
                  ]),
                ),
            ]),
          ),
          SectionCard(
            title: 'مقياس التقييم IFE / EFE',
            icon: Icons.scale_outlined,
            child: Column(children: [
              for (var v = 4; v >= 1; v--)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(children: [
                    CircleAvatar(radius: 13, child: Text('$v', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800))),
                    const SizedBox(width: 10),
                    Expanded(child: Text(ifeRatingLabels[v]!, style: const TextStyle(fontWeight: FontWeight.w600))),
                    Expanded(child: Text(efeRatingLabels[v]!, style: TextStyle(color: sem.muted))),
                  ]),
                ),
              const SizedBox(height: 8),
              Text('IFE: نقاط القوة 3 أو 4 ونقاط الضعف 1 أو 2. EFE: مدى استجابة المكتب الحالية للعامل الخارجي.',
                  style: TextStyle(color: sem.muted, fontSize: 12.5)),
            ]),
          ),
        ]),
        const SizedBox(height: 14),
        SectionCard(
          title: 'الحوكمة ودورية المتابعة',
          icon: Icons.account_balance_outlined,
          child: Column(children: [
            bullet('تحديث نسب إنجاز الإجراءات شهرياً من رؤساء الأقسام المسؤولة.'),
            bullet('مراجعة لوحة المتابعة شهرياً من مدير المكتب واتخاذ قرار في الإجراءات المتأخرة والمتعثرة.'),
            bullet('تحديث سجل المخاطر شهرياً من قسم الإشراف والتنسيق وربطه بالتهديدات.'),
            bullet('مراجعة تقييم العوامل وأولوياتها كل ربع سنة.'),
            bullet('مراجعة شاملة للتحليل كل ${meta.reviewCycleMonths} أشهر وإصدار نسخة جديدة.'),
          ]),
        ),
        const SizedBox(height: 14),
        SectionCard(
          title: 'المراجع',
          icon: Icons.library_books_outlined,
          child: Column(children: [
            bullet('Fred R. David — Strategic Management: Concepts and Cases (مصفوفات IFE وEFE وIE).'),
            bullet('Heinz Weihrich (1982) — The TOWS Matrix: A Tool for Situational Analysis.'),
            bullet('PMBOK Guide 7th ed. · ISO 21500 — إدارة المشاريع.'),
            bullet('ISO 31000 — إدارة المخاطر · ISO 9001 — الجودة · ISO 19650 — إدارة المعلومات.'),
          ]),
        ),
      ], stepMs: 45),
    );
  }

  Future<void> _editMeta(BuildContext context, SwotMeta meta) async {
    final app = AppScope.of(context);
    const keys = [
      ('title', 'العنوان'),
      ('subtitle', 'العنوان الفرعي'),
      ('version', 'الإصدار'),
      ('status', 'الحالة'),
      ('prepared_by', 'إعداد'),
      ('reviewed_by', 'مراجعة'),
      ('approved_by', 'اعتماد'),
    ];
    final ctrls = {for (final k in keys) k.$1: TextEditingController(text: meta.raw[k.$1]?.toString() ?? '')};
    var issue = meta.issueDate;
    var cycle = meta.reviewCycleMonths;
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: const Text('بيانات الوثيقة'),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                for (final k in keys) ...[
                  TextField(controller: ctrls[k.$1], maxLength: 200, decoration: fieldDeco(k.$2).copyWith(counterText: '')),
                  const SizedBox(height: 10),
                ],
                _dateField(ctx, 'تاريخ الإصدار', issue, (d) => set(() => issue = d)),
                const SizedBox(height: 10),
                SelectField(
                  label: 'دورة المراجعة',
                  value: '$cycle',
                  items: [for (final m in {3, 6, 12, 24, cycle}.toList()..sort()) ('$m', 'كل $m أشهر')],
                  onChanged: (v) => set(() => cycle = int.parse(v)),
                ),
              ]),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('إلغاء')),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop({
                ...meta.raw,
                for (final k in keys) k.$1: ctrls[k.$1]!.text.trim(),
                'issue_date': isoDay(issue),
                'review_cycle_months': cycle,
              }),
              child: const Text('حفظ'),
            ),
          ],
        ),
      ),
    );
    for (final c in ctrls.values) {
      c.dispose();
    }
    if (result == null || !context.mounted) return;
    await _guarded(context, () => app.setSetting('swot.meta', result), 'حُفظت بيانات الوثيقة');
  }
}
