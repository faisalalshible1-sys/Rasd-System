import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app_state.dart';
import '../models.dart';
import '../ui/audit_text.dart';
import '../ui/charts.dart';
import '../ui/motion.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';
import 'contract_finance.dart' show extractStatusColor;
import 'finance.dart' show ExtractPipeline, FinanceStats;
import 'project_detail.dart';

/// أقسام الرئيسية (يرتّبها المدير ويخفيها من «التخصيص والتطوير»؛ النظرة الشاملة ثابتة).
const List<(String, String, IconData)> dashboardCatalog = [
  ('overview', 'نظرة شاملة', Icons.dashboard_outlined),
  ('cycle', 'الدورة المستندية', Icons.fact_check_outlined),
  ('finance', 'المالية', Icons.payments_outlined),
  ('team', 'المهندسون والشركات', Icons.groups_outlined),
  ('activity', 'النشاط', Icons.history_rounded),
];

/// الأقسام الظاهرة بترتيب المدير.
List<(String, String, IconData)> dashboardViews(AppState app) {
  final conf = app.settings.dashboardSections;
  if (conf.isEmpty) return dashboardCatalog;
  final byKey = {for (final v in dashboardCatalog) v.$1: v};
  final out = <(String, String, IconData)>[];
  for (final c in conf) {
    final v = byKey[c.$1];
    if (v != null && (c.$2 || v.$1 == 'overview') && !out.contains(v)) out.add(v);
  }
  for (final v in dashboardCatalog) {
    if (!conf.any((c) => c.$1 == v.$1)) out.add(v);
  }
  if (!out.any((v) => v.$1 == 'overview')) out.insert(0, dashboardCatalog.first);
  return out;
}

void _openContract(BuildContext context, String id) =>
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ProjectDetailPage(projectId: id)));

/// UC-02: لوحة المؤشرات بأقسامها.
class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  String _view = 'overview';

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    if (!app.loadedOnce) return const SkeletonPage(cards: 4);
    final views = dashboardViews(app);
    if (!views.any((v) => v.$1 == _view)) _view = views.first.$1;
    final st = _Stats.of(app, app.scoped);

    return PageBody(
      onRefresh: app.loadAll,
      children: [
        FadeSlideIn(child: _Greeting(app: app, st: st)),
        const SizedBox(height: 14),
        FadeSlideIn(delay: const Duration(milliseconds: 90), child: ScopeFilters(app: app)),
        const SizedBox(height: 12),
        FadeSlideIn(
          delay: const Duration(milliseconds: 150),
          child: _ViewTabs(views: views, current: _view, onChanged: (v) => setState(() => _view = v)),
        ),
        const SizedBox(height: 14),
        if (app.projects.isEmpty)
          EmptyState(
            title: 'لا توجد عقود بعد',
            message: app.canManageProjects ? 'أضف أول عقد من صفحة «${term('contracts')}».' : 'لم تُسجَّل عقود حتى الآن.',
          )
        else
          MotionSwitcher(
            expand: false,
            child: KeyedSubtree(
              key: ValueKey(_view),
              child: switch (_view) {
                'cycle' => _cycle(context, app, st),
                'finance' => _finance(context, app, st),
                'team' => _team(context, app, st),
                'activity' => _activity(context, app),
                _ => _overview(context, app, st, views.any((v) => v.$1 == 'activity'), views.any((v) => v.$1 == 'cycle')),
              },
            ),
          ),
        const SizedBox(height: 24),
      ],
    );
  }

  static List<Widget> _spaced(List<Widget> items) => [
        for (var i = 0; i < items.length; i++) ...[
          if (i > 0) const SizedBox(height: 14),
          items[i],
        ],
      ];

  List<Project> _attention(AppState app, List<Project> list) =>
      list.where((p) => app.progressOf(p).cycle != CycleState.complete).toList()
        ..sort((a, b) => app.progressOf(a).pct.compareTo(app.progressOf(b).pct));

  // ---------------------------------------------------------------
  // نظرة شاملة
  // ---------------------------------------------------------------
  Widget _overview(BuildContext context, AppState app, _Stats st, bool hasActivity, bool hasCycle) {
    final sem = Sem.of(context);
    final cs = Theme.of(context).colorScheme;
    final n = st.list.length;
    String share(int v) => n == 0 ? '—' : '${pctText(v / n)} من ${term('contracts')}';
    final pending = app.pendingRequests;
    final attention = _attention(app, st.list);
    final fs = FinanceStats(app, st.list);
    final referredColor = extractStatusColor(context, 'referred');
    final guardColor = Color.lerp(cs.primary, sem.ok, 0.45)!;
    final hasMoney = fs.adjusted > 0 || fs.executed > 0 || fs.paid > 0;

    // المستحقات بانتظار الصرف: المحالة أولاً (الأقدم إحالة)، ثم المعتمدة غير المحالة (الأقدم اعتماداً).
    final awaiting = [...fs.extracts.where((x) => x.unpaid > 0 && (x.isReferred || x.status == 'approved'))]
      ..sort((a, b) {
        if (a.isReferred != b.isReferred) return a.isReferred ? -1 : 1;
        final da = (a.isReferred ? a.referredOn : a.approvedOn) ?? DateTime(2100);
        final db = (b.isReferred ? b.referredOn : b.approvedOn) ?? DateTime(2100);
        return da.compareTo(db);
      });

    // المنفذ والمدفوع آخر 12 شهراً
    final now = DateTime.now();
    final months = [for (var i = 11; i >= 0; i--) DateTime(now.year, now.month - i)];
    int idx(DateTime? d) => d == null ? -1 : months.indexWhere((m) => m.year == d.year && m.month == d.month);
    final execM = List<double>.filled(12, 0), paidM = List<double>.filled(12, 0);
    for (final x in fs.extracts) {
      if (!x.counted) continue;
      final i = idx(x.approvedOn ?? x.when);
      if (i >= 0) execM[i] += x.gross;
    }
    for (final c in fs.cash) {
      final j = idx(c.$1);
      if (j >= 0) paidM[j] += c.$2;
    }
    const monthNames = ['ينا', 'فبر', 'مار', 'أبر', 'ماي', 'يون', 'يول', 'أغس', 'سبت', 'أكت', 'نوف', 'ديس'];
    final hasTrend = execM.any((v) => v > 0) || paidM.any((v) => v > 0);

    final quick = <(IconData, String, VoidCallback)>[
      (Icons.folder_open_rounded, term('contracts'), () => app.openProjects()),
      (Icons.account_balance_outlined, 'المالية', () => app.openFinance()),
      if (app.v5Ready && fs.referredCount > 0)
        (Icons.forward_to_inbox_outlined, 'المحالة للصرف', () => app.openFinance(view: 'extracts', status: 'referred')),
      (Icons.receipt_long_outlined, 'سجل المستخلصات', () => app.openFinance(view: 'extracts')),
      (Icons.verified_user_outlined, 'التأمينات والضمانات', () => app.openFinance(view: 'guarantees')),
      if (!app.isAuditor) (Icons.fact_check_outlined, app.isDirector ? 'الاعتمادات' : 'طلباتي', () => app.setTab(2)),
      if (app.canUseAssistant) (Icons.auto_awesome_outlined, 'اسأل Claude', () => app.setTab(6)),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: _spaced(staggered([
        // المؤشرات الرئيسية الأربعة (عمودان على الهاتف)
        ResponsiveGrid(minItemWidth: 165, spacing: 10, children: [
          _Headline(
            icon: Icons.fact_check_rounded,
            label: 'نسبة إنجاز الدورة المستندية',
            value: st.avg * 100,
            kind: 'pct',
            color: cs.primary,
            meter: st.avg,
            sub: '${st.complete} مكتملة · ${st.running} جارية · ${st.notStarted} لم تبدأ',
            onTap: hasCycle ? () => setState(() => _view = 'cycle') : () => app.openProjects(),
          ),
          _Headline(
            icon: Icons.forward_to_inbox_rounded,
            label: 'المستخلصات المحالة للصرف',
            value: fs.referredCount.toDouble(),
            color: referredColor,
            meter: fs.net <= 0 ? null : (fs.referredDue / fs.net).clamp(0, 1).toDouble(),
            sub: app.v5Ready ? '${fmtMoney(fs.referredDue)} $currencyLabel بانتظار الصرف' : 'تتوفر بعد تحديث قاعدة البيانات',
            onTap: () => app.openFinance(view: 'extracts', status: 'referred'),
          ),
          _Headline(
            icon: Icons.task_alt_rounded,
            label: 'المستخلصات المصروفة',
            value: fs.paidCount.toDouble(),
            color: sem.ok,
            meter: fs.net <= 0 ? null : (fs.extractsPaid / fs.net).clamp(0, 1).toDouble(),
            sub: 'مدفوع ${fmtMoney(fs.extractsPaid)} $currencyLabel${fs.partialCount > 0 ? ' · ${fs.partialCount} جزئياً' : ''}',
            onTap: () => app.openFinance(view: 'extracts', status: 'paid'),
          ),
          _Headline(
            icon: Icons.shield_rounded,
            label: 'إجمالي التأمينات',
            value: fs.guarantees,
            kind: 'money',
            color: guardColor,
            sub: 'محتجز ${compactMoney(fs.retention)} · ابتدائي ${compactMoney(fs.gInitial)} · نهائي ${compactMoney(fs.gFinal)}',
            onTap: () => app.openFinance(view: 'guarantees'),
          ),
        ]),
        // وصول سريع
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            for (final q in quick)
              Padding(
                padding: const EdgeInsetsDirectional.only(end: 8),
                child: ActionChip(avatar: Icon(q.$1, size: 18), label: Text(q.$2), onPressed: q.$3),
              ),
          ]),
        ),
        if (app.isDirector && pending.isNotEmpty)
          Material(
            color: sem.wipSoft,
            borderRadius: BorderRadius.circular(14),
            child: ListTile(
              leading: Icon(Icons.fact_check, color: sem.wip),
              title: Text('${pending.length} طلب اعتماد بانتظار قرارك', style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: const Text('نماذج حساسة لن تتغير حتى تعتمدها أو ترفضها'),
              trailing: const Icon(Icons.chevron_left),
              onTap: () => app.setTab(2),
            ),
          ),
        // الدورة المستندية
        ResponsiveGrid(minItemWidth: 165, spacing: 10, children: [
          _Metric(icon: Icons.folder_rounded, label: term('contracts'), value: n.toDouble(), sub: 'ضمن التصفية', onTap: () => app.openProjects()),
          _Metric(
              icon: Icons.autorenew_rounded,
              label: 'دورات جارية',
              value: st.running.toDouble(),
              sub: share(st.running),
              color: sem.wip,
              onTap: () => app.openProjects(cycle: CycleState.running)),
          _Metric(
              icon: Icons.task_alt_rounded,
              label: 'دورات مكتملة',
              value: st.complete.toDouble(),
              sub: share(st.complete),
              color: sem.ok,
              onTap: () => app.openProjects(cycle: CycleState.complete)),
          _Metric(
              icon: Icons.hourglass_empty_rounded,
              label: 'لم تبدأ',
              value: st.notStarted.toDouble(),
              sub: share(st.notStarted),
              color: sem.muted,
              onTap: () => app.openProjects(cycle: CycleState.notStarted)),
        ]),
        // الموقف المالي
        if (hasMoney)
          SectionCard(
            title: 'الموقف المالي',
            icon: Icons.account_balance_outlined,
            trailing: TextButton(onPressed: () => app.openFinance(), child: const Text('التفاصيل')),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              ResponsiveGrid(minItemWidth: 160, spacing: 8, children: [
                _MoneyCell(label: 'الإجمالي بعد التغيير', value: fs.adjusted, color: cs.primary),
                _MoneyCell(label: 'قيمة الأعمال المنفذة', value: fs.executed, sub: fs.execRatio == null ? null : pctText(fs.execRatio!, digits: 1)),
                _MoneyCell(label: 'المدفوع', value: fs.paid, color: sem.ok, sub: fs.paidRatio == null ? null : pctText(fs.paidRatio!, digits: 1)),
                _MoneyCell(label: 'مستحق غير مدفوع', value: fs.outstanding, color: fs.outstanding > 0 ? sem.wip : null),
                _MoneyCell(label: 'المتبقي للدفع', value: fs.remainingToPay),
                if (fs.advanceCount > 0) _MoneyCell(label: 'دفعات مقدمة متبقية للاسترداد', value: fs.advanceRemaining),
              ]),
              if (fs.adjusted > 0) ...[
                const SizedBox(height: 14),
                StackBar(parts: [
                  ('مدفوع', fs.paid, sem.ok),
                  ('مستحق', fs.outstanding, sem.wip),
                  ('تأمين محتجز', fs.retention, cs.primary),
                  ('استقطاعات أخرى', fs.otherThanRetention, sem.danger),
                  ('لم يُنفَّذ', fs.unexecutedUnpaid, sem.todo),
                ]),
              ],
            ]),
          ),
        _TwoCol(
          start: [
            if (awaiting.isNotEmpty)
              SectionCard(
                title: 'بانتظار الصرف',
                icon: Icons.pending_actions_outlined,
                trailing: Text('الأقدم أولاً', style: TextStyle(color: sem.muted, fontSize: 12)),
                child: Column(children: [
                  for (final x in awaiting.take(6)) _awaitingTile(context, app, x),
                  if (awaiting.length > 6)
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: TextButton(
                        onPressed: () => app.openFinance(view: 'cash'),
                        child: Text('عرض الكل (${awaiting.length})'),
                      ),
                    ),
                ]),
              ),
            _attentionCard(context, app, attention.take(5).toList()),
          ],
          end: [
            if (fs.extracts.isNotEmpty)
              SectionCard(
                title: 'مسار المستخلصات',
                icon: Icons.route_outlined,
                trailing: TextButton(onPressed: () => app.openFinance(view: 'extracts'), child: const Text('السجل')),
                child: ExtractPipeline(st: fs, compact: true, onTap: (s) => app.openFinance(view: 'extracts', status: s)),
              ),
            if (hasTrend)
              SectionCard(
                title: 'المنفذ والمدفوع شهرياً',
                icon: Icons.timeline_rounded,
                trailing: Text('آخر 12 شهراً', style: TextStyle(color: sem.muted, fontSize: 12)),
                child: TrendChart(
                  height: 200,
                  labels: [for (final m in months) '${monthNames[m.month - 1]} ${(m.year % 100).toString().padLeft(2, '0')}'],
                  series: [ChartSeries('المنفذ', execM), ChartSeries('المدفوع', paidM, color: sem.ok)],
                ),
              ),
            SectionCard(
              title: 'آخر النشاط',
              icon: Icons.history_rounded,
              trailing: hasActivity ? TextButton(onPressed: () => setState(() => _view = 'activity'), child: const Text('عرض الكل')) : null,
              child: const _ActivityFeed(limit: 6),
            ),
          ],
        ),
      ])),
    );
  }

  Widget _awaitingTile(BuildContext context, AppState app, ContractExtract x) {
    final sem = Sem.of(context);
    final color = extractStatusColor(context, x.status);
    final since = x.isReferred ? x.referredOn : x.approvedOn;
    final days = since == null ? null : DateTime.now().difference(since).inDays;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      onTap: () => _openContract(context, x.projectId),
      leading: Container(
        width: 38,
        height: 38,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(10)),
        child: Text(x.isFinal ? 'خ' : '${x.seq}', style: TextStyle(color: color, fontWeight: FontWeight.w800)),
      ),
      title: Text(app.project(x.projectId)?.contractTitle ?? '', maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        ['مستخلص ${x.isFinal ? 'ختامي' : 'رقم ${x.seq}'}', x.statusLabel, if (days != null) 'منذ $days يوماً'].join(' · '),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: days != null && days > 30 ? sem.danger : sem.muted, fontSize: 12),
      ),
      trailing: Text(compactMoney(x.unpaid),
          style: TextStyle(fontWeight: FontWeight.w800, color: color, fontFeatures: const [FontFeature.tabularFigures()])),
    );
  }

  Widget _attentionCard(BuildContext context, AppState app, List<Project> list) {
    final sem = Sem.of(context);
    return SectionCard(
      title: 'تحتاج متابعة',
      icon: Icons.flag_outlined,
      trailing: Text('الأقل إنجازاً', style: TextStyle(color: sem.muted, fontSize: 12)),
      child: list.isEmpty
          ? Text('كل ${term('contracts')} ضمن التصفية أكملت دورتها.', style: TextStyle(color: sem.muted))
          : Column(
              children: [
                for (final p in list)
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                    leading: ContractTag(p),
                    title: Text(p.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text(
                      ['التالي: ${app.progressOf(p).next?.name ?? '—'}', ...app.companiesOf(p).take(1)].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: SizedBox(
                      width: 44,
                      child: RingProgress(
                        value: app.progressOf(p).pct,
                        size: 40,
                        stroke: 4.5,
                        child: Text(pctText(app.progressOf(p).pct), style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700)),
                      ),
                    ),
                    onTap: () => _openContract(context, p.id),
                  ),
              ],
            ),
    );
  }

  // ---------------------------------------------------------------
  // الدورة المستندية
  // ---------------------------------------------------------------
  Widget _cycle(BuildContext context, AppState app, _Stats st) {
    final sem = Sem.of(context);
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final n = st.list.length;
    final nStages = stageNames.length;
    final nexts = st.byNext.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final maxStage = st.byStage.fold<int>(1, (a, b) => b > a ? b : a);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: _spaced(staggered([
        SectionCard(
          title: 'الإنجاز المستندي',
          icon: Icons.donut_large_rounded,
          trailing: Text('متوسط ${term('contracts')}', style: TextStyle(color: sem.muted, fontSize: 12)),
          child: Row(
            children: [
              RingProgress(
                value: st.avg,
                size: 104,
                stroke: 11,
                child: AnimatedCount(
                  value: st.avg * 100,
                  format: (v) => '${v.toStringAsFixed(1)}%',
                  style: t.titleMedium?.copyWith(fontWeight: FontWeight.w800, fontFeatures: const [FontFeature.tabularFigures()]),
                ),
              ),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SegmentMeter(parts: [(st.done, sem.ok), (st.wip, sem.wip), (st.todo, sem.statusColor(FormStatus.todo))]),
                    const SizedBox(height: 10),
                    Legend(items: [
                      (sem.ok, '${FormStatus.done.label} ${st.done}'),
                      (sem.wip, '${FormStatus.wip.label} ${st.wip}'),
                      (sem.statusColor(FormStatus.todo), '${FormStatus.todo.label} ${st.todo}'),
                      (sem.na, '${FormStatus.na.label} ${st.na}'),
                    ]),
                    const SizedBox(height: 6),
                    Text('من أصل ${st.req} نموذجاً مطلوباً في $n من ${term('contracts')}', style: TextStyle(color: sem.muted, fontSize: 12)),
                  ],
                ),
              ),
            ],
          ),
        ),
        _TwoCol(
          start: [
            SectionCard(
              title: 'أين تتوقف ${term('contracts')}؟',
              icon: Icons.hourglass_top_rounded,
              trailing: Text('المستند التالي', style: TextStyle(color: sem.muted, fontSize: 12)),
              child: nexts.isEmpty
                  ? Text('كل ${term('contracts')} ضمن التصفية أكملت دورتها.', style: TextStyle(color: sem.muted))
                  : Column(
                      children: [
                        for (final e in nexts)
                          BarRow(
                            title: app.formDef(e.key)?.name ?? e.key,
                            trailing: '${e.value}',
                            subtitle: 'مرحلة ${stageName(app.formDef(e.key)?.stage ?? 0)}',
                            meter: AnimatedMeter(value: n == 0 ? 0.0 : e.value / n, color: sem.wip),
                            onTap: () => app.openProjects(form: e.key, nextOnly: true),
                          ),
                      ],
                    ),
            ),
          ],
          end: [
            SectionCard(
              title: 'حسب المرحلة الحالية',
              icon: Icons.stairs_outlined,
              child: Column(
                children: [
                  for (var i = 0; i <= nStages; i++)
                    BarRow(
                      title: i < nStages ? '${i + 1}. ${stageNames[i]}' : stageDoneName,
                      trailing: '${st.byStage[i]}',
                      meter: AnimatedMeter(value: st.byStage[i] / maxStage, color: i == nStages ? sem.ok : cs.primary),
                      onTap: () => app.openProjects(stage: i),
                    ),
                ],
              ),
            ),
          ],
        ),
        _attentionCard(context, app, _attention(app, st.list).take(10).toList()),
      ])),
    );
  }

  // ---------------------------------------------------------------
  // المالية
  // ---------------------------------------------------------------
  Widget _finance(BuildContext context, AppState app, _Stats st) {
    final sem = Sem.of(context);
    final cs = Theme.of(context).colorScheme;
    if (st.withFinance == 0) {
      return const EmptyState(
        icon: Icons.payments_outlined,
        title: 'لم تُدخل بيانات مالية بعد',
        message: 'تظهر هنا القيم التعاقدية والمنفذة والدفعات والضمانات فور إدخالها في صفحات العقود.',
      );
    }
    final remaining = st.contract - st.paid - st.deductions;
    final top = st.list.where((p) => (p.contractValue ?? 0) > 0).toList()
      ..sort((a, b) => (b.contractValue ?? 0).compareTo(a.contractValue ?? 0));
    final payBase = st.contract > 0 ? st.contract : (st.paid > 0 ? st.paid : 1.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: _spaced(staggered([
        InfoBanner(
          icon: Icons.account_balance_outlined,
          text: 'اللوحة المالية الموسعة: المستخلصات وأوامر التغيير والمدفوع والمتبقي والتأمينات، برسوم وتقارير.',
          action: TextButton(onPressed: () => app.setTab(7), child: const Text('فتح')),
        ),
        ResponsiveGrid(minItemWidth: 210, children: [
          _Metric(icon: Icons.request_quote_rounded, label: 'قيمة الأعمال التعاقدية', value: st.contract, kind: 'money', sub: currencyLabel),
          _Metric(icon: Icons.construction_rounded, label: 'قيمة الأعمال المنفذة', value: st.executed, kind: 'money', color: sem.ok, sub: currencyLabel),
          _Metric(
            icon: Icons.speed_rounded,
            label: 'نسبة التنفيذ',
            value: (st.execRatio ?? 0) * 100,
            kind: 'pct',
            color: (st.execRatio ?? 0) > 1 ? sem.danger : sem.ok,
            sub: 'المنفذ إلى التعاقدي',
          ),
          _Metric(
            icon: Icons.payments_rounded,
            label: 'المدفوع (الدفعات)',
            value: st.paid,
            kind: 'money',
            color: cs.primary,
            sub: st.contract == 0 ? currencyLabel : '${pctText(st.paid / st.contract)} من التعاقدية',
          ),
          _Metric(icon: Icons.remove_circle_outline_rounded, label: 'الخصومات', value: st.deductions, kind: 'money', color: sem.danger, sub: currencyLabel),
          _Metric(icon: Icons.account_balance_wallet_outlined, label: 'المتبقي من التعاقدية', value: remaining, kind: 'money', color: sem.wip, sub: 'بعد الدفعات والخصومات'),
          _Metric(icon: Icons.shield_outlined, label: 'الضمان الابتدائي', value: st.gInitial, kind: 'money', sub: '${rateText(guaranteeInitialRate)} من المنفذ'),
          _Metric(icon: Icons.verified_outlined, label: 'الضمان النهائي', value: st.gFinal, kind: 'money', sub: '${rateText(guaranteeFinalRate)} من المنفذ'),
        ]),
        _TwoCol(
          start: [
            SectionCard(
              title: 'التنفيذ حسب العقد',
              icon: Icons.bar_chart_rounded,
              trailing: Text('الأعلى قيمة', style: TextStyle(color: sem.muted, fontSize: 12)),
              child: top.isEmpty
                  ? Text('لا توجد قيم تعاقدية بعد.', style: TextStyle(color: sem.muted))
                  : Column(
                      children: [
                        for (final p in top.take(12))
                          BarRow(
                            title: '${p.contractTitle} · ${p.title}',
                            trailing: p.executionRatio == null ? '—' : pctText(p.executionRatio!),
                            subtitle: '${fmtMoney(p.executedValue)} من ${fmtMoney(p.contractValue)} $currencyLabel',
                            meter: AnimatedMeter(
                              value: p.executionRatio ?? 0.0,
                              color: (p.executionRatio ?? 0.0) > 1 ? sem.danger : sem.ok,
                            ),
                            onTap: () => _openContract(context, p.id),
                          ),
                      ],
                    ),
            ),
          ],
          end: [
            SectionCard(
              title: 'توزيع الدفعات',
              icon: Icons.stacked_bar_chart_rounded,
              child: Column(
                children: [
                  BarRow(
                    title: 'الدفعة الأولى',
                    trailing: fmtMoney(roundMoney(st.pay1)),
                    meter: AnimatedMeter(value: st.pay1 / payBase, color: cs.primary),
                  ),
                  BarRow(
                    title: 'الدفعة الثانية',
                    trailing: fmtMoney(roundMoney(st.pay2)),
                    meter: AnimatedMeter(value: st.pay2 / payBase, color: cs.primary),
                  ),
                  BarRow(
                    title: 'الدفعة الختامية',
                    trailing: fmtMoney(roundMoney(st.pay3)),
                    meter: AnimatedMeter(value: st.pay3 / payBase, color: cs.primary),
                  ),
                  const SizedBox(height: 6),
                  Text('النسب من مجموع القيم التعاقدية ($currencyLabel).', style: TextStyle(color: sem.muted, fontSize: 11.5)),
                ],
              ),
            ),
          ],
        ),
      ])),
    );
  }

  // ---------------------------------------------------------------
  // المهندسون والشركات
  // ---------------------------------------------------------------
  Widget _team(BuildContext context, AppState app, _Stats st) {
    final sem = Sem.of(context);
    final cs = Theme.of(context).colorScheme;
    final ids = {for (final p in st.list) p.id};
    final engs = app.engineers.where((e) => ids.contains(e.projectId)).toList();

    // المهندسون: عدد العقود لكل اسم
    final byName = <String, ({String name, Set<String> contracts, Set<String> kinds, int count})>{};
    for (final e in engs) {
      final k = normalizeArabic(e.name);
      final cur = byName[k];
      if (cur == null) {
        byName[k] = (name: e.name.trim(), contracts: {e.projectId}, kinds: {e.kind}, count: 1);
      } else {
        cur.contracts.add(e.projectId);
        cur.kinds.add(e.kind);
        byName[k] = (name: cur.name, contracts: cur.contracts, kinds: cur.kinds, count: cur.count + 1);
      }
    }
    final ranking = byName.values.toList()..sort((a, b) => b.contracts.length.compareTo(a.contracts.length));

    // الشركات: عدد العقود والأعمال
    final byCompany = <String, ({Set<String> contracts, int works})>{};
    for (final p in st.list) {
      final works = app.worksOf(p.id);
      for (final c in app.companiesOf(p)) {
        final cur = byCompany[c] ?? (contracts: <String>{}, works: 0);
        cur.contracts.add(p.id);
        byCompany[c] = (contracts: cur.contracts, works: cur.works + works.where((w) => w.company.trim() == c).length);
      }
    }
    final companies = byCompany.entries.toList()..sort((a, b) => b.value.contracts.length.compareTo(a.value.contracts.length));
    final maxCo = companies.isEmpty ? 1 : companies.first.value.contracts.length;

    IconData kindIcon(String k) => switch (k) {
          'sup' => Icons.manage_accounts_outlined,
          'qty' => Icons.calculate_outlined,
          'fol' => Icons.trending_up_rounded,
          _ => Icons.health_and_safety_outlined,
        };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: _spaced(staggered([
        if (!app.v3Ready)
          const InfoBanner(text: 'تفاصيل المهندسين وأرقام تكليفهم تظهر بعد تحديث قاعدة البيانات إلى إصدار العقود.', level: 'warning')
        else
          ResponsiveGrid(minItemWidth: 200, children: [
            for (final k in engineerKinds)
              _Metric(
                icon: kindIcon(k),
                label: engineerKindPlural(k),
                value: engs.where((e) => e.kind == k).length.toDouble(),
                sub: '${engs.where((e) => e.kind == k).map((e) => normalizeArabic(e.name)).toSet().length} مهندساً · تكليفات',
              ),
          ]),
        _TwoCol(
          start: [
            SectionCard(
              title: 'المهندسون حسب عدد العقود',
              icon: Icons.engineering_outlined,
              child: ranking.isEmpty
                  ? Text('لا توجد تكليفات مسجلة ضمن التصفية.', style: TextStyle(color: sem.muted))
                  : Column(
                      children: [
                        for (final r in ranking.take(15))
                          ListTile(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                            leading: InitialsAvatar(name: r.name, size: 34),
                            title: Text(r.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                            subtitle: Text(
                              [for (final k in engineerKinds) if (r.kinds.contains(k)) engineerKindLabel(k)].join('، '),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: ToneBadge('${r.contracts.length} ${term('contract')}', color: cs.primary),
                            onTap: () {
                              app.setProjectFilters(search: r.name);
                              app.setTab(1);
                            },
                          ),
                      ],
                    ),
            ),
          ],
          end: [
            SectionCard(
              title: 'الشركات',
              icon: Icons.business_outlined,
              child: companies.isEmpty
                  ? Text('لم تُسجَّل شركات بعد.', style: TextStyle(color: sem.muted))
                  : Column(
                      children: [
                        for (final e in companies.take(15))
                          BarRow(
                            title: e.key,
                            trailing: '${e.value.contracts.length}',
                            subtitle: e.value.works > 0 ? '${e.value.works} من الأعمال' : null,
                            meter: AnimatedMeter(value: e.value.contracts.length / maxCo, color: cs.primary),
                            onTap: () => app.setScope(company: e.key),
                          ),
                      ],
                    ),
            ),
          ],
        ),
      ])),
    );
  }

  // ---------------------------------------------------------------
  // النشاط
  // ---------------------------------------------------------------
  Widget _activity(BuildContext context, AppState app) {
    return SectionCard(
      title: 'آخر النشاط',
      icon: Icons.history_rounded,
      subtitle: app.canAudit ? 'كل العمليات في المنظومة' : 'العمليات على ${term('contracts')}',
      child: const _ActivityFeed(limit: 40),
    );
  }
}

/// مجاميع المؤشرات لقائمة العقود ضمن التصفية.
class _Stats {
  _Stats(this.list, int stages) : byStage = List<int>.filled(stages + 1, 0);

  final List<Project> list;
  final List<int> byStage;
  final Map<String, int> byNext = {};
  int running = 0, complete = 0, notStarted = 0, done = 0, wip = 0, todo = 0, na = 0, req = 0, withFinance = 0;
  double sumPct = 0, contract = 0, executed = 0, pay1 = 0, pay2 = 0, pay3 = 0, deductions = 0, gInitial = 0, gFinal = 0;
  double _execContract = 0, _execExecuted = 0;

  double get avg => list.isEmpty ? 0 : sumPct / list.length;
  double get paid => pay1 + pay2 + pay3;
  double? get execRatio => _execContract > 0 ? _execExecuted / _execContract : null;

  static _Stats of(AppState app, List<Project> list) {
    final n = stageNames.length;
    final s = _Stats(list, n);
    for (final p in list) {
      final pr = app.progressOf(p);
      switch (pr.cycle) {
        case CycleState.running:
          s.running++;
        case CycleState.complete:
          s.complete++;
        case CycleState.notStarted:
          s.notStarted++;
      }
      s.done += pr.done;
      s.wip += pr.wip;
      s.todo += pr.todo;
      s.na += pr.na;
      s.req += pr.required;
      s.sumPct += pr.pct;
      s.byStage[pr.stage.clamp(0, n)]++;
      final nx = pr.next;
      if (nx != null) s.byNext[nx.key] = (s.byNext[nx.key] ?? 0) + 1;
      if (p.contractValue != null || p.executedValue != null || p.paymentsTotal > 0) s.withFinance++;
      s.contract += p.contractValue ?? 0;
      s.executed += p.executedValue ?? 0;
      s.pay1 += p.paymentFirst ?? 0;
      s.pay2 += p.paymentSecond ?? 0;
      s.pay3 += p.paymentFinal ?? 0;
      s.deductions += p.deductions ?? 0;
      s.gInitial += p.guaranteeInitial ?? 0;
      s.gFinal += p.guaranteeFinal ?? 0;
      final c = p.contractValue, e = p.executedValue;
      if (c != null && e != null) {
        s._execContract += c;
        s._execExecuted += e;
      }
    }
    return s;
  }
}

/// ترويسة الرئيسية: تحية وتاريخ وحلقة الإنجاز على خلفية متحركة.
class _Greeting extends StatelessWidget {
  const _Greeting({required this.app, required this.st});

  final AppState app;
  final _Stats st;

  static const _days = ['الاثنين', 'الثلاثاء', 'الأربعاء', 'الخميس', 'الجمعة', 'السبت', 'الأحد'];

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final brand = app.brandColor;
    final hsl = HSLColor.fromColor(brand);
    final words = (app.me?.displayName ?? '').trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    final first = words.isEmpty ? '' : (words.first.endsWith('.') && words.length > 1 ? '${words[0]} ${words[1]}' : words.first);
    final now = DateTime.now();
    final hello = now.hour < 12 ? 'صباح الخير' : 'مساء الخير';
    final pending = app.isDirector ? app.pendingRequests.length : app.myRequests.where((r) => r.isPending).length;
    final scoped = app.ownerFilter.isNotEmpty || app.companyFilter.isNotEmpty;
    const white = Colors.white;

    Widget chip(IconData icon, String text) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(color: white.withAlpha(38), borderRadius: BorderRadius.circular(99)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 15, color: white),
            const SizedBox(width: 5),
            Text(text, style: const TextStyle(color: white, fontWeight: FontWeight.w600, fontSize: 12.5)),
          ]),
        );

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: LinearGradient(
          begin: AlignmentDirectional.topStart,
          end: AlignmentDirectional.bottomEnd,
          colors: [hsl.withLightness((hsl.lightness * 0.55).clamp(0.08, 0.3)).toColor(), brand],
        ),
      ),
      child: RepaintBoundary(
        child: AnimatedBackdrop(
          intensity: 0.7,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${_days[now.weekday - 1]} ${now.year}/${two(now.month)}/${two(now.day)}',
                          style: t.bodySmall?.copyWith(color: white.withAlpha(210))),
                      const SizedBox(height: 4),
                      Text(first.isEmpty ? hello : '$hello، $first',
                          style: t.headlineSmall?.copyWith(color: white, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 4),
                      Text(
                        'ملخص ${term('contracts')} ${scoped ? 'ضمن التصفية' : 'كلها'} ودورتها المستندية.',
                        style: t.bodyMedium?.copyWith(color: white.withAlpha(215)),
                      ),
                      const SizedBox(height: 12),
                      Wrap(spacing: 8, runSpacing: 8, children: [
                        chip(Icons.folder_rounded, '${st.list.length} ${term('contracts')}'),
                        chip(Icons.autorenew_rounded, '${st.running} جارية'),
                        if (pending > 0) chip(Icons.fact_check_outlined, app.isDirector ? '$pending بانتظار اعتمادك' : '$pending طلب معلّق'),
                      ]),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                RingProgress(
                  value: st.avg,
                  size: 92,
                  stroke: 9,
                  color: white,
                  track: white.withAlpha(50),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AnimatedCount(
                        value: st.avg * 100,
                        format: (v) => '${v.round()}%',
                        style: t.titleLarge?.copyWith(color: white, fontWeight: FontWeight.w800),
                      ),
                      Text('متوسط الإنجاز', style: TextStyle(color: cs.onPrimary.withAlpha(220), fontSize: 9.5)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// اختيار قسم الرئيسية.
class _ViewTabs extends StatelessWidget {
  const _ViewTabs({required this.views, required this.current, required this.onChanged});

  final List<(String, String, IconData)> views;
  final String current;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final v in views)
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 8),
              child: ChoiceChip(
                avatar: Icon(v.$3, size: 18),
                label: Text(v.$2),
                selected: v.$1 == current,
                showCheckmark: false,
                onSelected: (_) => onChanged(v.$1),
              ),
            ),
        ],
      ),
    );
  }
}

/// عمودان على الشاشات العريضة، وعمود واحد على الهاتف.
class _TwoCol extends StatelessWidget {
  const _TwoCol({required this.start, required this.end});

  final List<Widget> start;
  final List<Widget> end;

  static List<Widget> _gap(List<Widget> items) => [
        for (var i = 0; i < items.length; i++) ...[
          if (i > 0) const SizedBox(height: 14),
          items[i],
        ],
      ];

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      if (c.maxWidth < 900) {
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: _gap([...start, ...end]));
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: _gap(start))),
          const SizedBox(width: 16),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: _gap(end))),
        ],
      );
    });
  }
}

/// بطاقة مؤشر برقم يعدّ تصاعدياً.
class _Metric extends StatelessWidget {
  const _Metric({
    required this.icon,
    required this.label,
    required this.value,
    this.kind = 'count',
    this.sub,
    this.color,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final double value;
  final String kind; // count | money | pct
  final String? sub;
  final Color? color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final sem = Sem.of(context);
    final t = Theme.of(context).textTheme;
    final c = color ?? Theme.of(context).colorScheme.primary;
    String fmt(double v) => switch (kind) {
          'money' => fmtMoney(v == value ? roundMoney(value) : v.roundToDouble()),
          'pct' => '${v.toStringAsFixed(1)}%',
          _ => '${v.round()}',
        };
    final card = Material(
      color: sem.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: BorderSide(color: sem.rule)),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(color: c.withAlpha(28), borderRadius: BorderRadius.circular(12)),
                child: Icon(icon, color: c, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.bodySmall?.copyWith(color: sem.muted)),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: AlignmentDirectional.centerStart,
                      child: AnimatedCount(
                        value: value,
                        format: fmt,
                        style: t.headlineSmall?.copyWith(fontWeight: FontWeight.w700, fontFeatures: const [FontFeature.tabularFigures()]),
                      ),
                    ),
                    if (sub != null) Text(sub!, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.labelSmall?.copyWith(color: sem.muted)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
    return onTap == null ? card : HoverLift(child: card);
  }
}

/// مؤشر رئيسي في أعلى الرئيسية: رقم كبير وشرح ومقياس اختياري.
class _Headline extends StatelessWidget {
  const _Headline({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
    this.kind = 'count',
    this.sub,
    this.meter,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final double value;
  final String kind; // count | money | pct
  final Color color;
  final String? sub;
  final double? meter;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final sem = Sem.of(context);
    final t = Theme.of(context).textTheme;
    String fmt(double v) => switch (kind) {
          'money' => compactMoney(v),
          'pct' => '${v.toStringAsFixed(1)}%',
          _ => '${v.round()}',
        };
    final radius = BorderRadius.circular(math.max(12.0, appearance.radius));
    final card = Material(
      color: cardColor(context),
      shape: RoundedRectangleBorder(borderRadius: radius, side: BorderSide(color: sem.rule)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(border: BorderDirectional(start: BorderSide(color: color, width: 4))),
          padding: const EdgeInsetsDirectional.fromSTEB(14, 14, 14, 14),
          child: LayoutBuilder(builder: (context, c) {
            final labelStyle = t.bodyMedium?.copyWith(fontWeight: FontWeight.w600, height: 1.25);
            final badge = Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(color: color.withAlpha(30), borderRadius: BorderRadius.circular(10)),
              child: Icon(icon, color: color, size: 19),
            );
            final chevron = onTap == null ? const SizedBox.shrink() : Icon(Icons.chevron_left_rounded, size: 18, color: sem.muted);
            // في البطاقات الضيقة (الهاتف) ينزل العنوان تحت الأيقونة بارتفاع سطرين ثابت لتتساوى البطاقات
            final narrow = c.maxWidth < 230;
            final twoLines = MediaQuery.textScalerOf(context).scale((labelStyle?.fontSize ?? 14) * 1.25 * 2) + 2;
            final head = narrow
                ? Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Row(children: [badge, const Spacer(), chevron]),
                    const SizedBox(height: 8),
                    SizedBox(height: twoLines, child: Text(label, maxLines: 2, overflow: TextOverflow.ellipsis, style: labelStyle)),
                  ])
                : Row(children: [
                    badge,
                    const SizedBox(width: 10),
                    Expanded(child: Text(label, maxLines: 2, overflow: TextOverflow.ellipsis, style: labelStyle)),
                    chevron,
                  ]);
            return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              head,
              const SizedBox(height: 10),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: AlignmentDirectional.centerStart,
                child: AnimatedCount(
                  value: value,
                  format: fmt,
                  style: t.headlineMedium?.copyWith(fontWeight: FontWeight.w800, color: color, fontFeatures: const [FontFeature.tabularFigures()]),
                ),
              ),
              const SizedBox(height: 2),
              Text(sub ?? ' ', maxLines: 1, overflow: TextOverflow.ellipsis, style: t.labelMedium?.copyWith(color: sem.muted)),
              const SizedBox(height: 10),
              meter == null
                  ? const SizedBox(height: 6)
                  : AnimatedMeter(value: meter!.clamp(0, 1).toDouble(), color: color, height: 6),
            ],
          );
          }),
        ),
      ),
    );
    return onTap == null ? card : HoverLift(child: card);
  }
}

/// خلية مبلغ صغيرة في بطاقة الموقف المالي.
class _MoneyCell extends StatelessWidget {
  const _MoneyCell({required this.label, required this.value, this.color, this.sub});

  final String label;
  final double value;
  final Color? color;
  final String? sub;

  @override
  Widget build(BuildContext context) {
    final sem = Sem.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(color: sem.surface2, borderRadius: BorderRadius.circular((appearance.radius * 0.7).clamp(6, 16))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: sem.muted, fontSize: 12)),
        const SizedBox(height: 3),
        Row(children: [
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: AlignmentDirectional.centerStart,
              child: Text(compactMoney(value),
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17, color: color, fontFeatures: const [FontFeature.tabularFigures()])),
            ),
          ),
          if (sub != null) ...[
            const SizedBox(width: 6),
            Text(sub!, style: TextStyle(color: sem.muted, fontSize: 11.5)),
          ],
        ]),
      ]),
    );
  }
}

/// آخر العمليات من سجل التدقيق (للموظفين: ما يخص العقود).
class _ActivityFeed extends StatefulWidget {
  const _ActivityFeed({super.key, required this.limit});

  final int limit;

  @override
  State<_ActivityFeed> createState() => _ActivityFeedState();
}

class _ActivityFeedState extends State<_ActivityFeed> {
  List<AuditEntry>? _rows;
  bool _error = false;
  int _version = -1;

  /// يُعاد التحميل مع كل تحديث للبيانات، وتبقى السطور السابقة ظاهرة حتى تصل الجديدة.
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final app = AppScope.of(context);
    if (app.dataVersion != _version) _load(app);
  }

  Future<void> _load(AppState app) async {
    _version = app.dataVersion;
    try {
      final r = await app.loadAudit(limit: widget.limit);
      if (mounted) {
        setState(() {
          _rows = r;
          _error = false;
        });
      }
    } catch (_) {
      if (mounted && _rows == null) setState(() => _error = true);
    }
  }

  static IconData _icon(String action) => switch (action.split('.').first) {
        'form' => Icons.fact_check_outlined,
        'request' => Icons.gavel_rounded,
        'contract' => Icons.call_merge_rounded,
        'engineer' => Icons.engineering_outlined,
        'project' => Icons.folder_outlined,
        'note' => Icons.rate_review_outlined,
        'idea' => Icons.lightbulb_outline_rounded,
        'ai' => Icons.auto_awesome_outlined,
        'user' || 'security' => Icons.shield_outlined,
        _ => Icons.tune_rounded,
      };

  static String _ago(DateTime? d) {
    if (d == null) return '';
    final diff = DateTime.now().difference(d.toLocal());
    if (diff.inMinutes < 1) return 'الآن';
    if (diff.inMinutes < 60) return 'قبل ${diff.inMinutes} د';
    if (diff.inHours < 24) return 'قبل ${diff.inHours} س';
    if (diff.inDays < 7) return 'قبل ${diff.inDays} يوم';
    return fmtDate(d);
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final sem = Sem.of(context);
    final cs = Theme.of(context).colorScheme;
    final rows = _rows;
    if (_error) return Text('تعذّر تحميل النشاط.', style: TextStyle(color: sem.muted));
    if (rows == null) {
      return const Column(children: [
        Skeleton(height: 12),
        SizedBox(height: 12),
        Skeleton(height: 12, width: 260),
        SizedBox(height: 12),
        Skeleton(height: 12, width: 200),
      ]);
    }
    if (rows.isEmpty) return Text('لا يوجد نشاط مسجل بعد.', style: TextStyle(color: sem.muted));
    return Column(
          children: staggered([
            for (final e in rows)
              InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: e.projectId != null && app.project(e.projectId!) != null ? () => _openContract(context, e.projectId!) : null,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 2),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 30,
                        height: 30,
                        decoration: BoxDecoration(color: cs.primaryContainer, shape: BoxShape.circle),
                        child: Icon(_icon(e.action), size: 16, color: cs.onPrimaryContainer),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text.rich(
                              TextSpan(children: [
                                TextSpan(text: e.actorName.isEmpty ? 'النظام' : e.actorName, style: const TextStyle(fontWeight: FontWeight.w700)),
                                TextSpan(text: ' · ${auditDescription(app, e)}'),
                              ]),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (e.projectLabel.isNotEmpty && e.projectId != null)
                              Text(e.projectLabel, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: sem.muted, fontSize: 12)),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(_ago(e.at), style: TextStyle(color: sem.muted, fontSize: 11.5)),
                    ],
                  ),
                ),
              ),
          ], stepMs: 30),
        );
  }
}

/// تصفية حسب مالك المشروع والشركة المنفذة (مشتركة بين الرئيسية والتحليل).
class ScopeFilters extends StatelessWidget {
  const ScopeFilters({super.key, required this.app});

  final AppState app;

  @override
  Widget build(BuildContext context) {
    final owner = SelectField(
      label: 'مالك المشروع',
      value: app.ownerFilter,
      items: [('', '(الكل)'), for (final o in app.owners) (o, o)],
      onChanged: (v) => app.setScope(owner: v),
    );
    final company = SelectField(
      label: term('company'),
      value: app.companyFilter,
      items: [('', '(الكل)'), for (final c in app.companies) (c, c)],
      onChanged: (v) => app.setScope(company: v),
    );
    return LayoutBuilder(builder: (context, c) {
      if (c.maxWidth < 520) {
        return Column(children: [owner, const SizedBox(height: 10), company]);
      }
      return Row(children: [Expanded(child: owner), const SizedBox(width: 10), Expanded(child: company)]);
    });
  }
}
