import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app_state.dart';
import '../models.dart';
import '../services/export.dart';
import '../ui/audit_text.dart';
import '../ui/charts.dart';
import '../ui/motion.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';
import 'contract_finance.dart';
import 'dashboard.dart' show ScopeFilters;
import 'project_detail.dart';

/// لوحة المالية: إجمالي العقود والمستخلصات والمدفوع والمتبقي والتأمينات والضمانات، بكل تفرعاتها،
/// مع سجلات المستخلصات وأوامر التغيير والتعديلات المالية، ورسوم يتحكم المدير بشكلها.
const List<(String, String, IconData)> financeViews = [
  ('summary', 'الملخص', Icons.dashboard_customize_outlined),
  ('contracts', 'العقود', Icons.table_chart_outlined),
  ('extracts', 'المستخلصات', Icons.receipt_long_outlined),
  ('variations', 'أوامر التغيير', Icons.swap_vert_rounded),
  ('guarantees', 'التأمينات والضمانات', Icons.verified_user_outlined),
  ('cash', 'المدفوع والمتبقي', Icons.account_balance_wallet_outlined),
  ('log', 'سجل التعديلات', Icons.history_rounded),
];

const _months = ['ينا', 'فبر', 'مار', 'أبر', 'ماي', 'يون', 'يول', 'أغس', 'سبت', 'أكت', 'نوف', 'ديس'];
const _tab = TextStyle(fontFeatures: [FontFeature.tabularFigures()]);

void _open(BuildContext context, String id) =>
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ProjectDetailPage(projectId: id)));

/// مجاميع مالية لمجموعة عقود.
class FinanceStats {
  FinanceStats(this.app, this.list) {
    final ids = {for (final p in list) p.id};
    extracts = app.extracts.where((x) => ids.contains(x.projectId)).toList();
    variations = app.variations.where((v) => ids.contains(v.projectId)).toList();
    for (final p in list) {
      contract += p.contractValue ?? 0;
      variationsNet += p.variationsNet;
      adjusted += p.adjustedValue ?? 0;
      executed += p.executedValue ?? 0;
      paid += p.paidTotal;
      outstanding += p.outstanding;
      remainingWork += math.max(0, p.remainingWork ?? 0);
      remainingToPay += math.max(0, p.remainingToPay ?? 0);
      retention += p.retentionHeld;
      gInitial += p.guaranteeInitial ?? 0;
      gFinal += p.guaranteeFinal ?? 0;
      legacyPaid += p.paymentsTotal;
      manualDeductions += p.deductions ?? 0;
      if ((p.contractValue ?? 0) > 0) withValue++;
      final adv = p.advanceAmount ?? 0;
      if (adv > 0) {
        advanceCount++;
        advanceTotal += adv;
        advancePaid += p.advancePaid;
        advanceRecovered += p.advanceRecovered;
        advanceRemaining += p.advanceRemaining;
        if (p.advancePaid > 0) {
          advRecPaid += p.advanceRecovered;
          advRemPaid += p.advanceRemaining;
          cash.add((p.advancePaidOn, p.advancePaid, null, p));
        }
      }
    }
    for (final x in extracts) {
      if (x.counted) {
        gross += x.gross;
        net += x.net;
        deductions += x.deductionsTotal;
        advance += x.advanceRecovery;
        penalties += x.penalties;
        taxes += x.taxes;
        otherDed += x.otherDeductions;
        for (final e in x.customDeductions.entries) {
          custom[e.key] = (custom[e.key] ?? 0) + e.value;
        }
        extractsPaid += x.paidAmount;
        countedCount++;
        // الدفعات بتواريخها من السجل، أو دفعة واحدة بتاريخ الدفع لمستخلص بلا سجل.
        final pays = app.paymentsOf(x.id);
        if (pays.isNotEmpty) {
          for (final pay in pays) {
            cash.add((pay.paidOn, pay.amount, x, null));
          }
        } else if (x.paidAmount > 0) {
          cash.add((x.paidOn, x.paidAmount, x, null));
        }
        switch (x.status) {
          case 'approved':
            approvedCount++;
            approvedDue += x.unpaid;
          case 'referred':
            referredCount++;
            referredDue += x.unpaid;
            referredNet += x.net;
          case 'paid':
            paidCount++;
            paidNet += x.net;
        }
        if (x.status != 'paid' && x.paidAmount > 0) partialCount++;
      } else if (x.status == 'submitted' || x.status == 'draft') {
        pendingCount++;
        pendingValue += x.gross;
        if (x.status == 'draft') draftCount++;
      } else if (x.status == 'rejected') {
        rejectedCount++;
      }
    }
    // المعتمد وحده يدخل في قيمة العقد (الترحيل 37)، بزيادته ونقصه منفصلين
    for (final v in variations) {
      if (!v.isApproved) continue;
      varAdd += v.addedValue;
      varDeduct += v.deductedValue;
    }
  }

  final AppState app;
  final List<Project> list;
  late final List<ContractExtract> extracts;
  late final List<ContractVariation> variations;
  double contract = 0, variationsNet = 0, adjusted = 0, executed = 0, paid = 0, outstanding = 0;
  double remainingWork = 0, remainingToPay = 0, retention = 0, gInitial = 0, gFinal = 0, legacyPaid = 0, manualDeductions = 0;
  double gross = 0, net = 0, deductions = 0, advance = 0, penalties = 0, taxes = 0, otherDed = 0, pendingValue = 0;
  double varAdd = 0, varDeduct = 0;
  int withValue = 0, countedCount = 0, pendingCount = 0, draftCount = 0, rejectedCount = 0;
  // مسار المستخلص: معتمد ← محال للصرف ← مدفوع
  int approvedCount = 0, referredCount = 0, paidCount = 0, partialCount = 0;
  double approvedDue = 0, referredDue = 0, referredNet = 0, paidNet = 0, extractsPaid = 0;
  // الدفعات المقدمة
  int advanceCount = 0;
  double advanceTotal = 0, advancePaid = 0, advanceRecovered = 0, advanceRemaining = 0, advRecPaid = 0, advRemPaid = 0;
  // الاستقطاعات المخصصة بمفاتيحها
  final Map<String, double> custom = {};
  // حركة النقد: (التاريخ، المبلغ، المستخلص أو null، العقد للدفعة المقدمة)
  final List<(DateTime?, double, ContractExtract?, Project?)> cash = [];

  double get customTotal => custom.values.fold(0, (a, v) => a + v);

  /// الاستقطاعات غير التأمين، دون ما استُرد من دفعات مقدمة مصروفة (فهي داخلة في المدفوع).
  double get otherThanRetention => math.max(0, deductions - retention - advRecPaid);

  /// الأعمال التي لم تُنفَّذ ولم يُدفع عنها مقدماً.
  double get unexecutedUnpaid => math.max(0, remainingWork - advRemPaid);

  double? get execRatio => adjusted <= 0 ? null : executed / adjusted;
  double? get paidRatio => adjusted <= 0 ? null : paid / adjusted;
  double get guarantees => retention + gInitial + gFinal;
}

class FinancePage extends StatefulWidget {
  const FinancePage({super.key});

  @override
  State<FinancePage> createState() => _FinancePageState();
}

class _FinancePageState extends State<FinancePage> {
  String _view = 'summary';
  int _months12 = 12; // نطاق الرسوم الزمنية بالأشهر (0 = منذ أول مستخلص)
  String? _trendType; // تجاوز شكل الرسم الزمني في هذه الجلسة
  bool _exporting = false;
  String? _statusFilter; // حالة مستخلص مطلوبة من رابط في الرئيسية
  int _reqSeq = 0;

  Future<void> _export(AppState app, List<Project> list) async {
    setState(() => _exporting = true);
    try {
      final r = await exportFinanceXlsx(app, list);
      if (mounted && r != null) showToast(context, 'صُدّر التقرير المالي');
    } catch (e) {
      if (mounted) showToast(context, 'تعذّر التصدير: $e', error: true);
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    if (!app.loadedOnce) return const SkeletonPage(cards: 5);
    final req = app.financeRequest;
    if (req != null) {
      app.financeRequest = null;
      _view = financeViews.any((v) => v.$1 == req.view) ? req.view : 'summary';
      _statusFilter = req.status;
      _reqSeq = req.seq;
    }
    final list = app.scoped;
    final st = FinanceStats(app, list);
    return PageBody(
      onRefresh: app.loadAll,
      children: [
        FadeSlideIn(
          child: PageHeader(
            icon: Icons.account_balance_outlined,
            title: 'المالية',
            subtitle: 'إجمالي العقود والمستخلصات والمدفوع والمتبقي والتأمينات، محسوبة من البنود والمستخلصات وأوامر التغيير لحظياً.',
            actions: [
              OutlinedButton.icon(
                onPressed: _exporting ? null : () => _export(app, list),
                icon: _exporting
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.file_download_outlined),
                label: const Text('تصدير Excel'),
              ),
            ],
          ),
        ),
        if (!app.v4Ready)
          const Padding(
            padding: EdgeInsets.only(bottom: 12),
            child: InfoBanner(
              level: 'warning',
              text: 'المستخلصات وأوامر التغيير تحتاج تحديث قاعدة البيانات (الترحيل 11). تظهر القيم اليدوية حالياً.',
            ),
          ),
        FadeSlideIn(delay: const Duration(milliseconds: 80), child: ScopeFilters(app: app)),
        const SizedBox(height: 12),
        FadeSlideIn(
          delay: const Duration(milliseconds: 140),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              for (final v in financeViews)
                Padding(
                  padding: const EdgeInsetsDirectional.only(end: 8),
                  child: ChoiceChip(
                    avatar: Icon(v.$3, size: 18),
                    label: Text(v.$2),
                    selected: _view == v.$1,
                    showCheckmark: false,
                    onSelected: (_) => setState(() {
                      _view = v.$1;
                      _statusFilter = null;
                    }),
                  ),
                ),
            ]),
          ),
        ),
        const SizedBox(height: 14),
        MotionSwitcher(
          expand: false,
          child: KeyedSubtree(
            key: ValueKey('$_view-$_reqSeq'),
            child: switch (_view) {
              'contracts' => _ContractsView(app: app, list: list),
              'extracts' => _ExtractsView(app: app, st: st, initialStatus: _statusFilter),
              'variations' => _VariationsView(app: app, st: st),
              'guarantees' => _GuaranteesView(app: app, st: st),
              'cash' => _cash(context, app, st),
              'log' => const _FinanceLog(),
              _ => _summary(context, app, st),
            },
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  // ---------------------------------------------------------------
  // أدوات زمنية
  // ---------------------------------------------------------------
  List<DateTime> _monthRange(FinanceStats st) {
    final now = DateTime.now();
    var start = DateTime(now.year, now.month - (_months12 - 1));
    if (_months12 == 0) {
      DateTime? first;
      for (final x in st.extracts) {
        final w = x.when;
        if (w != null && (first == null || w.isBefore(first))) first = w;
      }
      start = first == null ? DateTime(now.year, now.month - 11) : DateTime(first.year, first.month);
    }
    final out = <DateTime>[];
    var d = start;
    while (!d.isAfter(DateTime(now.year, now.month)) && out.length < 120) {
      out.add(d);
      d = DateTime(d.year, d.month + 1);
    }
    return out;
  }

  static String _monthLabel(DateTime d) => '${_months[d.month - 1]} ${(d.year % 100).toString().padLeft(2, '0')}';

  static int _idx(List<DateTime> months, DateTime? d) {
    if (d == null) return -1;
    for (var i = 0; i < months.length; i++) {
      if (months[i].year == d.year && months[i].month == d.month) return i;
    }
    return -1;
  }

  Widget _rangeChips() => Wrap(spacing: 6, children: [
        for (final r in const [(6, '6 أشهر'), (12, 'سنة'), (24, 'سنتان'), (0, 'الكل')])
          ChoiceChip(
            visualDensity: VisualDensity.compact,
            label: Text(r.$2),
            selected: _months12 == r.$1,
            onSelected: (_) => setState(() => _months12 = r.$1),
          ),
      ]);

  Widget _typeToggle() {
    final cur = _trendType ?? appearance.charts.trend;
    return SegmentedButton<String>(
      style: const ButtonStyle(visualDensity: VisualDensity.compact),
      showSelectedIcon: false,
      segments: const [
        ButtonSegment(value: 'area', icon: Icon(Icons.area_chart_outlined, size: 18), tooltip: 'مساحة'),
        ButtonSegment(value: 'line', icon: Icon(Icons.show_chart_rounded, size: 18), tooltip: 'خط'),
        ButtonSegment(value: 'bar', icon: Icon(Icons.bar_chart_rounded, size: 18), tooltip: 'أعمدة'),
      ],
      selected: {cur},
      onSelectionChanged: (s) => setState(() => _trendType = s.first),
    );
  }

  // ---------------------------------------------------------------
  // الملخص
  // ---------------------------------------------------------------
  Widget _summary(BuildContext context, AppState app, FinanceStats st) {
    final sem = Sem.of(context);
    final cs = Theme.of(context).colorScheme;
    final months = _monthRange(st);
    final grossM = List<double>.filled(months.length, 0);
    final netM = List<double>.filled(months.length, 0);
    final paidM = List<double>.filled(months.length, 0);
    for (final x in st.extracts) {
      if (!x.counted) continue;
      final i = _idx(months, x.approvedOn ?? x.when);
      if (i >= 0) {
        grossM[i] += x.gross;
        netM[i] += x.net;
      }
    }
    for (final c in st.cash) {
      final j = _idx(months, c.$1);
      if (j >= 0) paidM[j] += c.$2;
    }
    final cumExec = <double>[];
    final cumPaid = <double>[];
    var a = 0.0, b = 0.0;
    for (var i = 0; i < months.length; i++) {
      a += grossM[i];
      b += paidM[i];
      cumExec.add(a);
      cumPaid.add(b);
    }
    final labels = [for (final m in months) _monthLabel(m)];

    final top = [...st.list.where((p) => (p.adjustedValue ?? 0) > 0)]..sort((x, y) => (y.adjustedValue ?? 0).compareTo(x.adjustedValue ?? 0));
    final byOwner = <String, double>{};
    for (final p in st.list) {
      final v = p.adjustedValue ?? 0;
      if (v <= 0) continue;
      final k = p.owner.trim().isEmpty ? 'غير محدد' : p.owner.trim();
      byOwner[k] = (byOwner[k] ?? 0) + v;
    }
    final owners = byOwner.entries.toList()..sort((x, y) => y.value.compareTo(x.value));

    Widget kpi(String label, double v, {String? sub, Color? color, IconData? icon, VoidCallback? onTap}) => StatCard(
          label: label,
          value: compactMoney(v),
          sub: sub ?? '${fmtMoney(v)} $currencyLabel',
          icon: icon,
          color: color,
          onTap: onTap,
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: _spaced(staggered([
        ResponsiveGrid(minItemWidth: 215, children: [
          kpi('إجمالي العقود', st.contract, icon: Icons.description_outlined, sub: '${st.withValue} عقد بقيمة · ${fmtMoney(st.contract)}',
              onTap: () => setState(() => _view = 'contracts')),
          kpi('صافي أوامر التغيير', st.variationsNet,
              icon: Icons.swap_vert_rounded,
              color: st.variationsNet < 0 ? sem.danger : sem.ok,
              sub: '+${compactMoney(st.varAdd)} / −${compactMoney(st.varDeduct)}',
              onTap: () => setState(() => _view = 'variations')),
          kpi('الإجمالي بعد التغيير', st.adjusted, icon: Icons.functions_rounded, color: cs.primary),
          kpi('قيمة الأعمال المنفذة', st.executed,
              icon: Icons.construction_outlined, sub: st.execRatio == null ? null : 'نسبة التنفيذ ${pctText(st.execRatio!, digits: 1)}'),
          kpi('إجمالي المستخلصات', st.gross,
              icon: Icons.receipt_long_outlined, sub: '${st.countedCount} معتمد · صافيها ${compactMoney(st.net)}',
              onTap: () => setState(() => _view = 'extracts')),
          kpi('الاستقطاعات', st.deductions, icon: Icons.content_cut_rounded, color: sem.danger),
          kpi('المدفوع', st.paid,
              icon: Icons.payments_outlined, color: sem.ok, sub: st.paidRatio == null ? null : '${pctText(st.paidRatio!, digits: 1)} من الإجمالي',
              onTap: () => setState(() => _view = 'cash')),
          kpi('مستحق غير مدفوع', st.outstanding, icon: Icons.pending_actions_outlined, color: st.outstanding > 0 ? sem.wip : null),
          if (app.v5Ready)
            kpi('محال للصرف', st.referredDue,
                icon: Icons.forward_to_inbox_outlined,
                color: extractStatusColor(context, 'referred'),
                sub: '${st.referredCount} مستخلص بانتظار الصرف',
                onTap: () => setState(() {
                      _view = 'extracts';
                      _statusFilter = 'referred';
                      _reqSeq++;
                    })),
          kpi('المستخلصات المصروفة', st.extractsPaid,
              icon: Icons.task_alt_rounded,
              color: sem.ok,
              sub: '${st.paidCount} مدفوع كاملاً${st.partialCount > 0 ? ' · ${st.partialCount} جزئياً' : ''}',
              onTap: () => setState(() => _view = 'cash')),
          if (st.advanceCount > 0)
            kpi('الدفعات المقدمة', st.advanceTotal,
                icon: Icons.savings_outlined,
                sub: '${st.advanceCount} عقد · المتبقي للاسترداد ${compactMoney(st.advanceRemaining)}'),
          kpi('المتبقي من الأعمال', st.remainingWork, icon: Icons.hourglass_bottom_rounded),
          kpi('المتبقي للدفع', st.remainingToPay, icon: Icons.account_balance_wallet_outlined),
          kpi('التأمين المحتجز', st.retention, icon: Icons.lock_outline_rounded, onTap: () => setState(() => _view = 'guarantees')),
          kpi('الضمانات (ابتدائي + نهائي)', st.gInitial + st.gFinal,
              icon: Icons.verified_outlined, sub: '${compactMoney(st.gInitial)} + ${compactMoney(st.gFinal)}'),
          if (st.pendingCount > 0)
            kpi('مستخلصات بانتظار الاعتماد', st.pendingValue, icon: Icons.schedule_rounded, color: sem.wip, sub: '${st.pendingCount} مستخلص'),
        ]),
        SectionCard(
          title: 'المستخلصات والمدفوعات شهرياً',
          icon: Icons.timeline_rounded,
          subtitle: 'قيمة الأعمال المعتمدة وصافيها حسب شهر الاعتماد، والمدفوع حسب شهر الدفع.',
          trailing: _typeToggle(),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Align(alignment: AlignmentDirectional.centerStart, child: _rangeChips()),
            const SizedBox(height: 10),
            TrendChart(
              type: _trendType,
              labels: labels,
              series: [
                ChartSeries('قيمة الأعمال', grossM),
                ChartSeries('الصافي', netM),
                ChartSeries('المدفوع', paidM, color: sem.ok),
              ],
            ),
          ]),
        ),
        _TwoUp(children: [
          SectionCard(
            title: 'تكوين إجمالي العقود',
            icon: Icons.donut_large_rounded,
            child: BreakdownChart(
              centerTitle: 'بعد التغيير',
              centerValue: compactMoney(st.adjusted),
              colors: [sem.ok, sem.wip, cs.primary, sem.danger, sem.todo],
              items: [
                ('المدفوع', st.paid),
                ('مستحق غير مدفوع', st.outstanding),
                ('تأمين محتجز', st.retention),
                ('استقطاعات أخرى', st.otherThanRetention),
                ('لم يُنفَّذ بعد', st.unexecutedUnpaid),
              ],
            ),
          ),
          SectionCard(
            title: 'المنفذ والمدفوع تراكمياً',
            icon: Icons.stacked_line_chart_rounded,
            child: TrendChart(
              type: 'line',
              height: 220,
              labels: labels,
              series: [ChartSeries('المنفذ (مستخلصات)', cumExec), ChartSeries('المدفوع', cumPaid, color: sem.ok)],
            ),
          ),
        ]),
        _TwoUp(children: [
          SectionCard(
            title: 'أكبر العقود قيمة',
            icon: Icons.leaderboard_outlined,
            child: top.isEmpty
                ? Text('لا توجد قيم بعد.', style: TextStyle(color: sem.muted))
                : BreakdownChart(
                    type: 'bar',
                    items: [for (final p in top.take(8)) (p.contractTitle, p.adjustedValue ?? 0)],
                    onTap: (i) => _open(context, top[i].id),
                  ),
          ),
          SectionCard(
            title: 'التوزيع حسب مالك المشروع',
            icon: Icons.pie_chart_outline_rounded,
            child: BreakdownChart(
              items: [for (final e in owners.take(7)) (e.key, e.value)],
              centerTitle: 'الجهات',
              centerValue: '${owners.length}',
            ),
          ),
        ]),
      ], stepMs: 60)),
    );
  }

  // ---------------------------------------------------------------
  // المدفوع والمتبقي
  // ---------------------------------------------------------------
  Widget _cash(BuildContext context, AppState app, FinanceStats st) {
    final sem = Sem.of(context);
    final cs = Theme.of(context).colorScheme;
    final months = _monthRange(st);
    final paidM = List<double>.filled(months.length, 0);
    final advM = List<double>.filled(months.length, 0);
    for (final c in st.cash) {
      final j = _idx(months, c.$1);
      if (j < 0) continue;
      if (c.$3 == null) {
        advM[j] += c.$2;
      } else {
        paidM[j] += c.$2;
      }
    }
    final ledger = [...st.cash]..sort((a, b) => (b.$1 ?? DateTime(2000)).compareTo(a.$1 ?? DateTime(2000)));
    final byMethod = <String, double>{};
    for (final x in st.extracts) {
      for (final pay in app.paymentsOf(x.id)) {
        byMethod[pay.methodLabel] = (byMethod[pay.methodLabel] ?? 0) + pay.amount;
      }
    }
    // أعمار المستحقات غير المدفوعة منذ الاعتماد
    final buckets = <String, double>{'حتى 30 يوماً': 0, '31–60 يوماً': 0, '61–90 يوماً': 0, 'أكثر من 90 يوماً': 0, 'بلا تاريخ اعتماد': 0};
    final now = DateTime.now();
    for (final x in st.extracts) {
      final u = x.unpaid;
      if (u <= 0) continue;
      final d = x.approvedOn;
      if (d == null) {
        buckets['بلا تاريخ اعتماد'] = buckets['بلا تاريخ اعتماد']! + u;
        continue;
      }
      final days = now.difference(d).inDays;
      final k = days <= 30 ? 'حتى 30 يوماً' : days <= 60 ? '31–60 يوماً' : days <= 90 ? '61–90 يوماً' : 'أكثر من 90 يوماً';
      buckets[k] = buckets[k]! + u;
    }
    final remaining = [...st.list.where((p) => (p.remainingToPay ?? 0) > 0)]
      ..sort((a, b) => (b.remainingToPay ?? 0).compareTo(a.remainingToPay ?? 0));
    final unpaid = [...st.extracts.where((x) => x.unpaid > 0)]..sort((a, b) => b.unpaid.compareTo(a.unpaid));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: _spaced(staggered([
        ResponsiveGrid(minItemWidth: 215, children: [
          StatCard(label: 'المدفوع', value: compactMoney(st.paid), sub: '${fmtMoney(st.paid)} $currencyLabel', icon: Icons.payments_outlined, color: sem.ok),
          StatCard(
              label: 'منه من المستخلصات',
              value: compactMoney(st.extractsPaid),
              sub: [
                if (st.advancePaid > 0) 'دفعات مقدمة ${compactMoney(st.advancePaid)}',
                if (st.legacyPaid > 0) 'يدوية ${compactMoney(st.legacyPaid)}',
              ].join(' · ').ifEmpty('${st.paidCount} مستخلص مدفوع كاملاً'),
              icon: Icons.receipt_long_outlined),
          if (app.v5Ready)
            StatCard(
                label: 'محال للصرف',
                value: compactMoney(st.referredDue),
                sub: '${st.referredCount} مستخلص · معتمد لم يُحل ${st.approvedCount}',
                icon: Icons.forward_to_inbox_outlined,
                color: extractStatusColor(context, 'referred')),
          StatCard(
              label: 'مستحق غير مدفوع',
              value: compactMoney(st.outstanding),
              sub: '${unpaid.length} مستخلص',
              icon: Icons.pending_actions_outlined,
              color: sem.wip),
          StatCard(label: 'المتبقي للدفع من العقود', value: compactMoney(st.remainingToPay), icon: Icons.account_balance_wallet_outlined, color: cs.primary),
        ]),
        SectionCard(
          title: 'المدفوعات حسب الشهر',
          icon: Icons.bar_chart_rounded,
          trailing: _rangeChips(),
          child: TrendChart(type: 'bar', labels: [for (final m in months) _monthLabel(m)], series: [
            ChartSeries('مدفوع المستخلصات', paidM, color: sem.ok),
            if (advM.any((v) => v > 0)) ChartSeries('دفعات مقدمة', advM, color: cs.primary),
          ]),
        ),
        _TwoUp(children: [
          SectionCard(
            title: 'أعمار المستحقات غير المدفوعة',
            icon: Icons.av_timer_rounded,
            subtitle: 'من تاريخ اعتماد المستخلص حتى اليوم.',
            child: BreakdownChart(
              type: 'bar',
              colors: [sem.ok, sem.wip, Colors.deepOrange, sem.danger, sem.muted],
              items: [for (final e in buckets.entries) (e.key, e.value)],
            ),
          ),
          SectionCard(
            title: 'أكبر المتبقي للدفع',
            icon: Icons.format_list_numbered_rounded,
            child: remaining.isEmpty
                ? Text('لا يوجد متبقٍ.', style: TextStyle(color: sem.muted))
                : Column(children: [
                    for (final p in remaining.take(8))
                      BarRow(
                        title: p.contractTitle,
                        trailing: compactMoney(p.remainingToPay ?? 0),
                        subtitle: 'مدفوع ${pctText(p.paidRatio ?? 0, digits: 1)} من ${compactMoney(p.adjustedValue ?? 0)}',
                        meter: AnimatedMeter(value: (p.paidRatio ?? 0).clamp(0, 1).toDouble(), color: sem.ok),
                        onTap: () => _open(context, p.id),
                      ),
                  ]),
          ),
        ]),
        if (ledger.isNotEmpty)
          SectionCard(
            title: 'سجل الدفعات',
            icon: Icons.receipt_outlined,
            subtitle: 'كل دفعة بتاريخها: دفعات المستخلصات من سجلها، والدفعات المقدمة للعقود. الأحدث أولاً.',
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              if (byMethod.length > 1) ...[
                Wrap(spacing: 18, runSpacing: 4, children: [
                  for (final e in byMethod.entries)
                    Text('${e.key}: ${fmtMoney(e.value)}', style: _tab.copyWith(fontSize: 12.5, color: sem.muted)),
                ]),
                const SizedBox(height: 6),
              ],
              for (final c in ledger.take(40))
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  onTap: () => _open(context, c.$3?.projectId ?? c.$4!.id),
                  leading: Icon(c.$3 == null ? Icons.savings_outlined : Icons.check_circle_outline_rounded, color: c.$3 == null ? cs.primary : sem.ok),
                  title: Text(
                    c.$3 == null
                        ? '${c.$4!.contractTitle} · دفعة مقدمة'
                        : '${app.project(c.$3!.projectId)?.contractTitle ?? ''} · ${c.$3!.title}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(c.$1 == null ? 'بلا تاريخ' : dayText(c.$1), style: TextStyle(color: sem.muted, fontSize: 12)),
                  trailing: Text(fmtMoney(c.$2), style: _tab.copyWith(fontWeight: FontWeight.w800)),
                ),
              if (ledger.length > 40)
                Text('و${ledger.length - 40} دفعة أقدم.', style: TextStyle(color: sem.muted, fontSize: 12)),
            ]),
          ),
        if (unpaid.isNotEmpty)
          SectionCard(
            title: 'مستخلصات معتمدة لم تُدفع كاملاً',
            icon: Icons.notification_important_outlined,
            child: Column(children: [
              for (final x in unpaid.take(20))
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  onTap: () => _open(context, x.projectId),
                  leading: CircleAvatar(
                    backgroundColor: extractStatusColor(context, x.status).withValues(alpha: 0.14),
                    child: Text('${x.seq}', style: TextStyle(color: extractStatusColor(context, x.status), fontWeight: FontWeight.w800)),
                  ),
                  title: Text('${app.project(x.projectId)?.contractTitle ?? ''} · ${x.title}', maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text([
                    x.statusLabel,
                    if (x.isReferred && x.referredOn != null) 'أُحيل ${dayText(x.referredOn)} (منذ ${DateTime.now().difference(x.referredOn!).inDays} يوماً)'
                    else if (x.approvedOn != null) 'اعتُمد ${dayText(x.approvedOn)} (منذ ${DateTime.now().difference(x.approvedOn!).inDays} يوماً)',
                    'الصافي ${fmtMoney(x.net)} · المدفوع ${fmtMoney(x.paidAmount)}',
                  ].join(' · ')),
                  trailing: Text(fmtMoney(x.unpaid), style: _tab.copyWith(fontWeight: FontWeight.w800, color: sem.wip)),
                ),
            ]),
          ),
      ], stepMs: 60)),
    );
  }
}

List<Widget> _spaced(List<Widget> items) => [
      for (var i = 0; i < items.length; i++) ...[
        if (i > 0) const SizedBox(height: 14),
        items[i],
      ],
    ];

/// بطاقتان جنباً إلى جنب على الشاشات العريضة.
class _TwoUp extends StatelessWidget {
  const _TwoUp({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    // بلا IntrinsicHeight: الرسوم تقيس عرضها بـ LayoutBuilder، والقياس الجوهري يكسر تخطيطها فينزل النص والرسم عن موضعهما.
    return LayoutBuilder(builder: (context, c) {
      if (c.maxWidth < 860) return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: _spaced(children));
      return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) const SizedBox(width: 14),
          Expanded(child: children[i]),
        ],
      ]);
    });
  }
}

// ---------------------------------------------------------------
// العقود: جدول قابل للفرز
// ---------------------------------------------------------------
class _ContractsView extends StatefulWidget {
  const _ContractsView({required this.app, required this.list});

  final AppState app;
  final List<Project> list;

  @override
  State<_ContractsView> createState() => _ContractsViewState();
}

class _ContractsViewState extends State<_ContractsView> {
  int _sort = 2;
  bool _asc = false;
  String _q = '';

  static final List<(String, double? Function(Project))> _cols = [
    ('القيمة', (p) => p.contractValue),
    ('التغيير', (p) => p.variationsNet),
    ('بعد التغيير', (p) => p.adjustedValue),
    ('المنفذ', (p) => p.executedValue),
    ('التنفيذ %', (p) => (p.adjustedValue ?? 0) > 0 ? (p.executedValue ?? 0) / p.adjustedValue! : null),
    ('المستخلصات', (p) => p.extractsGross),
    ('المدفوع', (p) => p.paidTotal),
    ('الدفع %', (p) => p.paidRatio),
    ('مستحق', (p) => p.outstanding),
    ('المتبقي للدفع', (p) => p.remainingToPay),
    ('التأمين المحتجز', (p) => p.retentionHeld),
    ('الضمان الابتدائي', (p) => p.guaranteeInitial),
    ('الضمان النهائي', (p) => p.guaranteeFinal),
  ];

  @override
  Widget build(BuildContext context) {
    final app = widget.app;
    final sem = Sem.of(context);
    final q = normalizeArabic(_q);
    final rows = widget.list.where((p) {
      if (q.isEmpty) return true;
      return normalizeArabic('${p.contractNo} ${p.assignNo} ${p.name} ${p.owner} ${app.companiesOf(p).join(' ')}').contains(q);
    }).toList();
    final get = _cols[_sort].$2;
    rows.sort((a, b) {
      final x = get(a) ?? double.negativeInfinity, y = get(b) ?? double.negativeInfinity;
      return _asc ? x.compareTo(y) : y.compareTo(x);
    });
    String cell(int c, Project p) {
      final v = _cols[c].$2(p);
      if (v == null) return '—';
      return _cols[c].$1.endsWith('%') ? pctText(v, digits: 1) : fmtMoney(v);
    }

    double total(int c) => rows.fold<double>(0, (a, p) => a + (_cols[c].$2(p) ?? 0));
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final search = TextField(
      onChanged: (v) => setState(() => _q = v),
      decoration: fieldDeco('بحث في العقود', prefixIcon: const Icon(Icons.search_rounded)),
    );
    if (!wide) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        search,
        const SizedBox(height: 10),
        SelectField(
          label: 'الترتيب حسب',
          value: '$_sort',
          items: [for (var i = 0; i < _cols.length; i++) ('$i', _cols[i].$1)],
          onChanged: (v) => setState(() => _sort = int.parse(v)),
        ),
        const SizedBox(height: 10),
        for (final p in rows)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Material(
              color: cardColor(context),
              shape: cardShape(context),
              child: InkWell(
                borderRadius: BorderRadius.circular(appearance.radius),
                onTap: () => _open(context, p.id),
                child: Padding(
                  padding: EdgeInsets.all(appearance.pad),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Row(children: [
                      ContractTag(p),
                      const SizedBox(width: 8),
                      Expanded(child: Text(p.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700))),
                    ]),
                    const SizedBox(height: 8),
                    StackBar(height: 10, parts: [
                      ('مدفوع', p.paidTotal, sem.ok),
                      ('مستحق', p.outstanding, sem.wip),
                      ('محتجز', p.retentionHeld, Theme.of(context).colorScheme.primary),
                      ('لم يُنفَّذ', math.max(0.0, p.remainingWork ?? 0), sem.todo),
                    ], legend: false),
                    const SizedBox(height: 8),
                    Wrap(spacing: 14, runSpacing: 4, children: [
                      for (final c in const [2, 3, 6, 9, 10])
                        Text('${_cols[c].$1}: ${cell(c, p)}', style: _tab.copyWith(fontSize: 12.5)),
                    ]),
                  ]),
                ),
              ),
            ),
          ),
      ]);
    }
    return SectionCard(
      title: 'العقود ماليّاً',
      icon: Icons.table_chart_outlined,
      trailing: SizedBox(width: 280, child: search),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          sortColumnIndex: _sort + 1,
          sortAscending: _asc,
          headingTextStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5),
          dataTextStyle: _tab.copyWith(fontSize: 12.5, color: Theme.of(context).colorScheme.onSurface),
          columnSpacing: 22,
          showCheckboxColumn: false,
          columns: [
            const DataColumn(label: Text('العقد')),
            for (var i = 0; i < _cols.length; i++)
              DataColumn(
                numeric: true,
                label: Text(_cols[i].$1),
                onSort: (_, __) => setState(() {
                  if (_sort == i) {
                    _asc = !_asc;
                  } else {
                    _sort = i;
                    _asc = false;
                  }
                }),
              ),
          ],
          rows: [
            for (final p in rows)
              DataRow(
                onSelectChanged: (_) => _open(context, p.id),
                cells: [
                  DataCell(ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 220),
                    child: Text('${p.contractTitle} · ${p.title}', maxLines: 1, overflow: TextOverflow.ellipsis),
                  )),
                  for (var i = 0; i < _cols.length; i++) DataCell(Text(cell(i, p))),
                ],
              ),
            DataRow(
              color: WidgetStatePropertyAll(sem.surface2),
              cells: [
                DataCell(Text('الإجمالي (${rows.length})', style: const TextStyle(fontWeight: FontWeight.w800))),
                for (var i = 0; i < _cols.length; i++)
                  DataCell(Text(
                    _cols[i].$1.endsWith('%') ? '' : fmtMoney(total(i)),
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  )),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------
// المستخلصات
// ---------------------------------------------------------------
class _ExtractsView extends StatefulWidget {
  const _ExtractsView({required this.app, required this.st, this.initialStatus});

  final AppState app;
  final FinanceStats st;
  final String? initialStatus;

  @override
  State<_ExtractsView> createState() => _ExtractsViewState();
}

class _ExtractsViewState extends State<_ExtractsView> {
  late final Set<String> _status = {if (widget.initialStatus != null) widget.initialStatus!};
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final app = widget.app;
    final st = widget.st;
    final sem = Sem.of(context);
    final cs = Theme.of(context).colorScheme;
    final q = normalizeArabic(_q);
    final rows = st.extracts.where((x) {
      if (_status.isNotEmpty && !_status.contains(x.status)) return false;
      if (q.isEmpty) return true;
      final p = app.project(x.projectId);
      return normalizeArabic('${p?.contractNo ?? ''} ${p?.assignNo ?? ''} ${p?.name ?? ''} ${x.refNo} ${x.notes}').contains(q);
    }).toList()
      ..sort((a, b) => (b.when ?? DateTime(2000)).compareTo(a.when ?? DateTime(2000)));
    double sum(double Function(ContractExtract) f) => rows.fold(0, (a, x) => a + f(x));
    final byStatus = <String, double>{for (final s in extractStatuses) s: 0};
    for (final x in st.extracts) {
      byStatus[x.status] = (byStatus[x.status] ?? 0) + x.gross;
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: _spaced([
        SectionCard(
          title: 'مسار المستخلصات',
          icon: Icons.route_outlined,
          subtitle: 'من التقديم إلى الاعتماد ثم الإحالة للصرف ثم الدفع. اضغط مرحلة لتصفية السجل.',
          child: ExtractPipeline(
            st: st,
            selected: _status,
            onTap: (s) => setState(() {
              if (_status.length == 1 && _status.contains(s)) {
                _status.clear();
              } else {
                _status
                  ..clear()
                  ..add(s);
              }
            }),
          ),
        ),
        _TwoUp(children: [
          SectionCard(
            title: 'الاستقطاعات من المستخلصات المعتمدة',
            icon: Icons.content_cut_rounded,
            child: BreakdownChart(
              centerTitle: 'إجمالي الاستقطاعات',
              centerValue: compactMoney(st.deductions),
              items: [
                for (final e in <(String, double)>[
                  ('التأمين المحتجز', st.retention),
                  ('استرداد الدفعة المقدمة', st.advance),
                  ('الغرامات', st.penalties),
                  ('الضرائب والرسوم', st.taxes),
                  for (final e in st.custom.entries) (deductionLabel(app, e.key), e.value),
                  ('أخرى', st.otherDed),
                ])
                  if (e.$2 > 0) e,
              ],
            ),
          ),
          SectionCard(
            title: 'المستخلصات حسب الحالة',
            icon: Icons.donut_small_outlined,
            child: BreakdownChart(
              type: 'bar',
              colors: [for (final s in extractStatuses) if ((byStatus[s] ?? 0) > 0) extractStatusColor(context, s)],
              items: [for (final s in extractStatuses) if ((byStatus[s] ?? 0) > 0) (extractStatusLabels[s]!, byStatus[s]!)],
            ),
          ),
        ]),
        SectionCard(
          title: 'سجل المستخلصات',
          icon: Icons.receipt_long_outlined,
          subtitle: 'كل المستخلصات في العقود ضمن التصفية. اضغط المستخلص لفتح عقده.',
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            TextField(
              onChanged: (v) => setState(() => _q = v),
              decoration: fieldDeco('بحث برقم العقد أو المشروع أو رقم المستخلص', prefixIcon: const Icon(Icons.search_rounded)),
            ),
            const SizedBox(height: 10),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final s in extractStatuses)
                FilterChip(
                  label: Text(extractStatusLabels[s]!),
                  selected: _status.contains(s),
                  selectedColor: extractStatusColor(context, s).withValues(alpha: 0.2),
                  onSelected: (on) => setState(() => on ? _status.add(s) : _status.remove(s)),
                ),
            ]),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: sem.surface2, borderRadius: BorderRadius.circular(12)),
              child: Wrap(spacing: 18, runSpacing: 6, children: [
                Text('العدد: ${rows.length}', style: const TextStyle(fontWeight: FontWeight.w700)),
                Text('الأعمال: ${fmtMoney(sum((x) => x.gross))}', style: _tab),
                Text('الاستقطاعات: ${fmtMoney(sum((x) => x.deductionsTotal))}', style: _tab.copyWith(color: sem.danger)),
                Text('الصافي: ${fmtMoney(sum((x) => x.net))}', style: _tab.copyWith(color: cs.primary, fontWeight: FontWeight.w700)),
                Text('المدفوع: ${fmtMoney(sum((x) => x.paidAmount))}', style: _tab.copyWith(color: sem.ok)),
                Text('غير المدفوع: ${fmtMoney(sum((x) => x.unpaid))}', style: _tab.copyWith(color: sem.wip)),
              ]),
            ),
            const SizedBox(height: 8),
            if (rows.isEmpty)
              Padding(padding: const EdgeInsets.all(16), child: Text('لا توجد مستخلصات مطابقة.', style: TextStyle(color: sem.muted)))
            else
              for (final x in rows.take(300)) _row(context, x),
          ]),
        ),
      ]),
    );
  }

  Widget _row(BuildContext context, ContractExtract x) {
    final sem = Sem.of(context);
    final color = extractStatusColor(context, x.status);
    final p = widget.app.project(x.projectId);
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => _open(context, x.projectId),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        child: Row(children: [
          Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(9)),
            child: Text(x.isFinal ? 'خ' : '${x.seq}', style: TextStyle(color: color, fontWeight: FontWeight.w800)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Flexible(
                  child: Text('${p?.contractTitle ?? ''} · ${x.title}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
                ),
                const SizedBox(width: 6),
                ToneBadge(x.statusLabel, color: color),
              ]),
              Text(
                [
                  if (x.periodTo != null) 'حتى ${dayText(x.periodTo)}',
                  if (x.approvedOn != null) 'اعتُمد ${dayText(x.approvedOn)}',
                  if (x.referredOn != null && x.counted) 'أُحيل ${dayText(x.referredOn)}',
                  if (x.paidOn != null) 'دُفع ${dayText(x.paidOn)}',
                  if (x.counted && x.paidAmount > 0 && !x.isPaid) 'مدفوع جزئياً ${fmtMoney(x.paidAmount)}',
                ].join(' · '),
                style: TextStyle(color: sem.muted, fontSize: 12),
              ),
            ]),
          ),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(fmtMoney(x.net), style: _tab.copyWith(fontWeight: FontWeight.w800)),
            Text('من ${fmtMoney(x.gross)}', style: _tab.copyWith(fontSize: 11.5, color: sem.muted)),
          ]),
        ]),
      ),
    );
  }
}

// ---------------------------------------------------------------
// أوامر التغيير
// ---------------------------------------------------------------
class _VariationsView extends StatelessWidget {
  const _VariationsView({required this.app, required this.st});

  final AppState app;
  final FinanceStats st;

  @override
  Widget build(BuildContext context) {
    final sem = Sem.of(context);
    final rows = [...st.variations]..sort((a, b) => (b.approvedOn ?? b.createdAt ?? DateTime(2000)).compareTo(a.approvedOn ?? a.createdAt ?? DateTime(2000)));
    final byContract = <String, double>{};
    for (final v in st.variations) {
      if (v.isApproved) byContract[v.projectId] = (byContract[v.projectId] ?? 0) + v.signed;
    }
    final pending = st.variations.where((v) => v.isDraft).length;
    final ranked = byContract.entries.toList()..sort((a, b) => b.value.abs().compareTo(a.value.abs()));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: _spaced([
        ResponsiveGrid(minItemWidth: 215, children: [
          StatCard(
              label: 'عدد أوامر التغيير',
              value: '${st.variations.length}',
              sub: pending > 0 ? '$pending بانتظار الاعتماد' : null,
              icon: Icons.format_list_numbered_rounded),
          StatCard(label: 'الزيادة المعتمدة', value: compactMoney(st.varAdd), sub: '${fmtMoney(st.varAdd)} $currencyLabel', icon: Icons.add_circle_outline, color: sem.ok),
          StatCard(label: 'النقص المعتمد', value: compactMoney(st.varDeduct), sub: '${fmtMoney(st.varDeduct)} $currencyLabel', icon: Icons.remove_circle_outline, color: sem.danger),
          StatCard(
              label: 'الصافي من القيمة الأصلية',
              value: compactMoney(st.varAdd - st.varDeduct),
              sub: st.contract > 0 ? pctText((st.varAdd - st.varDeduct) / st.contract, digits: 1) : null,
              icon: Icons.functions_rounded),
        ]),
        if (ranked.isNotEmpty)
          SectionCard(
            title: 'صافي التغيير حسب العقد',
            icon: Icons.leaderboard_outlined,
            child: Column(children: [
              for (final e in ranked.take(10))
                BarRow(
                  title: app.project(e.key)?.contractTitle ?? '',
                  trailing: '${e.value >= 0 ? '+' : '−'}${fmtMoney(e.value.abs())}',
                  meter: AnimatedMeter(
                    value: ranked.first.value.abs() <= 0 ? 0 : (e.value.abs() / ranked.first.value.abs()).clamp(0, 1).toDouble(),
                    color: e.value >= 0 ? sem.ok : sem.danger,
                  ),
                  subtitle: (app.project(e.key)?.contractValue ?? 0) > 0
                      ? '${pctText(e.value / app.project(e.key)!.contractValue!, digits: 1)} من القيمة الأصلية'
                      : null,
                  onTap: () => _open(context, e.key),
                ),
            ]),
          ),
        SectionCard(
          title: 'سجل أوامر التغيير',
          icon: Icons.swap_vert_rounded,
          child: rows.isEmpty
              ? Text('لا توجد أوامر تغيير.', style: TextStyle(color: sem.muted))
              : Column(children: [
                  for (final v in rows.take(300))
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      onTap: () => _open(context, v.projectId),
                      leading: Icon(v.isAdd ? Icons.add_circle_outline : Icons.remove_circle_outline, color: v.isAdd ? sem.ok : sem.danger),
                      title: Text(v.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text([
                        app.project(v.projectId)?.contractTitle ?? '',
                        if (v.refNo.isNotEmpty) 'رقم ${v.refNo}',
                        if (v.approvedOn != null) dayText(v.approvedOn),
                        if (!v.isApproved) v.statusLabel,
                      ].join(' · ')),
                      trailing: Text('${v.isAdd ? '+' : '−'}${fmtMoney(v.amount)}',
                          style: _tab.copyWith(fontWeight: FontWeight.w800, color: v.isAdd ? sem.ok : sem.danger)),
                    ),
                ]),
        ),
      ]),
    );
  }
}

// ---------------------------------------------------------------
// التأمينات والضمانات
// ---------------------------------------------------------------
class _GuaranteesView extends StatelessWidget {
  const _GuaranteesView({required this.app, required this.st});

  final AppState app;
  final FinanceStats st;

  @override
  Widget build(BuildContext context) {
    final sem = Sem.of(context);
    final cs = Theme.of(context).colorScheme;
    final rows = [...st.list.where((p) => p.retentionHeld > 0 || (p.guaranteeInitial ?? 0) > 0 || (p.guaranteeFinal ?? 0) > 0)]
      ..sort((a, b) => (b.retentionHeld + (b.guaranteeInitial ?? 0) + (b.guaranteeFinal ?? 0))
          .compareTo(a.retentionHeld + (a.guaranteeInitial ?? 0) + (a.guaranteeFinal ?? 0)));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: _spaced([
        ResponsiveGrid(minItemWidth: 215, children: [
          StatCard(label: 'التأمين المحتجز من المستخلصات', value: compactMoney(st.retention), sub: '${fmtMoney(st.retention)} $currencyLabel', icon: Icons.lock_outline_rounded, color: cs.primary),
          StatCard(
              label: 'الضمان الابتدائي ${rateText(guaranteeInitialRate)}',
              value: compactMoney(st.gInitial),
              sub: '${fmtMoney(st.gInitial)} $currencyLabel',
              icon: Icons.verified_outlined),
          StatCard(
              label: 'الضمان النهائي ${rateText(guaranteeFinalRate)}',
              value: compactMoney(st.gFinal),
              sub: '${fmtMoney(st.gFinal)} $currencyLabel',
              icon: Icons.verified_user_outlined),
          StatCard(label: 'الإجمالي', value: compactMoney(st.guarantees), sub: '${fmtMoney(st.guarantees)} $currencyLabel', icon: Icons.shield_outlined, color: sem.ok),
        ]),
        _TwoUp(children: [
          SectionCard(
            title: 'التكوين',
            icon: Icons.donut_large_rounded,
            subtitle: 'الضمانان يُحسبان من قيمة الأعمال المنفذة بالنسبتين المحددتين في الإعدادات.',
            child: BreakdownChart(
              centerTitle: 'الإجمالي',
              centerValue: compactMoney(st.guarantees),
              items: [('التأمين المحتجز', st.retention), ('الضمان الابتدائي', st.gInitial), ('الضمان النهائي', st.gFinal)],
            ),
          ),
          SectionCard(
            title: 'أعلى العقود تأميناً',
            icon: Icons.leaderboard_outlined,
            child: rows.isEmpty
                ? Text('لا توجد تأمينات بعد.', style: TextStyle(color: sem.muted))
                : BreakdownChart(
                    type: 'bar',
                    items: [
                      for (final p in rows.take(8)) (p.contractTitle, p.retentionHeld + (p.guaranteeInitial ?? 0) + (p.guaranteeFinal ?? 0)),
                    ],
                    onTap: (i) => _open(context, rows[i].id),
                  ),
          ),
        ]),
        SectionCard(
          title: 'التأمينات والضمانات لكل عقد',
          icon: Icons.table_rows_outlined,
          child: Column(children: [
            for (final p in rows)
              ListTile(
                contentPadding: EdgeInsets.zero,
                onTap: () => _open(context, p.id),
                title: Text('${p.contractTitle} · ${p.title}', maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(
                  'محتجز ${fmtMoney(p.retentionHeld)} · ابتدائي ${p.guaranteeInitialNa ? 'لا ينطبق' : fmtMoney(p.guaranteeInitial)} · نهائي ${fmtMoney(p.guaranteeFinal)}',
                  style: _tab.copyWith(fontSize: 12),
                ),
                trailing: Text(fmtMoney(p.retentionHeld + (p.guaranteeInitial ?? 0) + (p.guaranteeFinal ?? 0)),
                    style: _tab.copyWith(fontWeight: FontWeight.w800)),
              ),
          ]),
        ),
      ]),
    );
  }
}

// ---------------------------------------------------------------
// سجل التعديلات المالية
// ---------------------------------------------------------------
class _FinanceLog extends StatefulWidget {
  const _FinanceLog();

  @override
  State<_FinanceLog> createState() => _FinanceLogState();
}

class _FinanceLogState extends State<_FinanceLog> {
  List<AuditEntry>? _rows;
  String? _error;
  int _version = -1;

  Future<void> _load(AppState app) async {
    try {
      final r = await app.financeHistory(limit: 500);
      if (mounted) setState(() => _rows = r);
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final sem = Sem.of(context);
    if (_version != app.dataVersion) {
      _version = app.dataVersion;
      _load(app);
    }
    final rows = _rows;
    return SectionCard(
      title: 'سجل التعديلات المالية',
      icon: Icons.history_rounded,
      subtitle: 'قيم البنود والمستخلصات وأوامر التغيير والبيانات المالية اليدوية والدمج: من عدّل، ومتى، ومن أي قيمة إلى أي قيمة.',
      child: _error != null
          ? InfoBanner(text: _error!, level: 'critical')
          : rows == null
              ? const Column(children: [Skeleton(height: 40), SizedBox(height: 8), Skeleton(height: 40), SizedBox(height: 8), Skeleton(height: 40)])
              : rows.isEmpty
                  ? Text(app.v4Ready ? 'لا توجد تعديلات مالية بعد.' : 'يتوفر السجل بعد تحديث قاعدة البيانات.', style: TextStyle(color: sem.muted))
                  : Column(children: [
                      for (final e in rows)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          onTap: e.projectId == null || app.project(e.projectId!) == null ? null : () => _open(context, e.projectId!),
                          leading: InitialsAvatar(name: e.actorName.isEmpty ? 'النظام' : e.actorName, size: 34),
                          title: Text(auditDescription(app, e), style: const TextStyle(fontSize: 13.5)),
                          subtitle: Text([e.actorName, if (e.projectLabel.isNotEmpty) e.projectLabel, fmtDate(e.at)].join(' · '),
                              style: TextStyle(color: sem.muted, fontSize: 12)),
                        ),
                    ]),
    );
  }
}

/// مسار المستخلصات: عدد كل مرحلة وقيمتها، من المسودة إلى المدفوع.
class ExtractPipeline extends StatelessWidget {
  const ExtractPipeline({super.key, required this.st, this.selected = const {}, this.onTap, this.compact = false});

  final FinanceStats st;
  final Set<String> selected;
  final void Function(String status)? onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final sem = Sem.of(context);
    final v5 = st.app.v5Ready;
    final stages = <(String, int, double, String)>[];
    final count = <String, int>{};
    final value = <String, double>{};
    for (final x in st.extracts) {
      count[x.status] = (count[x.status] ?? 0) + 1;
      // القيمة المعروضة: الصافي للمراحل المالية، وقيمة الأعمال لما قبل الاعتماد.
      value[x.status] = (value[x.status] ?? 0) + (x.counted ? x.net : x.gross);
    }
    for (final s in extractStatuses) {
      if (s == 'referred' && !v5) continue;
      if (s == 'rejected' && (count[s] ?? 0) == 0) continue;
      final hint = switch (s) {
        'draft' => 'قيمة أعمال',
        'submitted' => 'بانتظار الاعتماد',
        'approved' => 'لم يُحل للصرف',
        'referred' => 'بانتظار الصرف',
        'paid' => 'صافٍ مدفوع',
        _ => 'قيمة أعمال',
      };
      stages.add((s, count[s] ?? 0, value[s] ?? 0, hint));
    }
    final total = st.extracts.length;
    return LayoutBuilder(builder: (context, c) {
      // كل المراحل في صف إن اتسع العرض، وإلا صفان متوازنان يملأ كلٌّ منهما العرض
      final perRow = c.maxWidth >= 120.0 * stages.length ? stages.length : (stages.length / 2).ceil();
      final rows = <List<(String, int, double, String)>>[
        for (var i = 0; i < stages.length; i += perRow) stages.sublist(i, math.min(i + perRow, stages.length)),
      ];
      Widget tile((String, int, double, String) e) => Material(
              color: selected.contains(e.$1) ? extractStatusColor(context, e.$1).withValues(alpha: 0.16) : sem.surface2,
              borderRadius: BorderRadius.circular(12),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: onTap == null ? null : () => onTap!(e.$1),
                child: Padding(
                  padding: EdgeInsets.fromLTRB(10, compact ? 8 : 10, 10, compact ? 8 : 10),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(color: extractStatusColor(context, e.$1), shape: BoxShape.circle),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(extractStatusLabels[e.$1]!,
                            maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: sem.muted, fontSize: 12)),
                      ),
                    ]),
                    const SizedBox(height: 4),
                    Text('${e.$2}', style: _tab.copyWith(fontWeight: FontWeight.w800, fontSize: compact ? 18 : 20)),
                    Text(compactMoney(e.$3), maxLines: 1, overflow: TextOverflow.ellipsis, style: _tab.copyWith(fontSize: 12)),
                    if (!compact) ...[
                      const SizedBox(height: 6),
                      AnimatedMeter(
                        value: total == 0 ? 0 : e.$2 / total,
                        color: extractStatusColor(context, e.$1),
                        height: 5,
                      ),
                      const SizedBox(height: 3),
                      Text(e.$4, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: sem.muted, fontSize: 11)),
                    ],
                  ]),
                ),
              ),
            );
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (var r = 0; r < rows.length; r++) ...[
          if (r > 0) const SizedBox(height: 8),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            for (var i = 0; i < rows[r].length; i++) ...[
              if (i > 0) const SizedBox(width: 8),
              Expanded(child: tile(rows[r][i])),
            ],
          ]),
        ],
      ]);
    });
  }
}

extension _IfEmpty on String {
  String ifEmpty(String other) => isEmpty ? other : this;
}
