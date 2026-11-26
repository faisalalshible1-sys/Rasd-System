import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app_state.dart';
import '../docs.dart' show isolate;
import '../models.dart';
import '../prices.dart' show BoqSheet;
import '../ui/charts.dart';
import '../ui/motion.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';
import 'contract_finance.dart' show DayField, money;

/// الإصدار 1.6.0 (الترحيل 37): لوحة معلومات العقد، وضمانات العقد وتأميناته، وأوامر التغيير ببنودها واعتمادها وسجلها،
/// ولجان الاستلام برئيسها وأعضائها.

const _tabular = TextStyle(fontFeatures: [FontFeature.tabularFigures()]);

String _signed(double v) => v == 0 ? fmtMoney(0) : '${v > 0 ? '+' : '−'}${fmtMoney(v.abs())}';

// ---------------------------------------------------------------------
// لوحة معلومات العقد
// ---------------------------------------------------------------------

/// لوحة معلومات العقد في أعلى صفحته: القيمة وتغييراتها، والمستخلصات من التقديم إلى الصرف، والمستحقات والاستقطاعات.
class ContractDashboardCard extends StatelessWidget {
  const ContractDashboardCard({super.key, required this.project});

  final Project project;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final p = project;
    final sem = Sem.of(context);
    final cs = Theme.of(context).colorScheme;
    final adjusted = p.adjustedValue;
    final extracts = app.extractsOf(p.id);
    final submittedCount = extracts.where((x) => const {'submitted', 'approved', 'referred', 'paid'}.contains(x.status)).length;
    final vos = app.variationsOf(p.id);
    final pendingVo = vos.where((v) => v.isDraft).toList();
    final progress = p.financialProgress;

    Widget stat(String label, String value, {String? sub, Color? color, IconData? icon, Widget? extra}) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(color: sem.surface2, borderRadius: BorderRadius.circular((appearance.radius * 0.7).clamp(6, 16))),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(children: [
                if (icon != null) ...[Icon(icon, size: 15, color: color ?? sem.muted), const SizedBox(width: 5)],
                Expanded(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: sem.muted, fontSize: 12))),
              ]),
              const SizedBox(height: 3),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: AlignmentDirectional.centerStart,
                child: Text(value, style: _tabular.copyWith(fontWeight: FontWeight.w800, fontSize: 16.5, color: color)),
              ),
              if (sub != null) Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: sem.muted, fontSize: 11)),
              if (extra != null) ...[const SizedBox(height: 6), extra],
            ],
          ),
        );

    return SectionCard(
      title: 'لوحة معلومات العقد',
      icon: Icons.space_dashboard_outlined,
      subtitle: 'القيمة بعد أوامر التغيير المعتمدة، والمستخلصات من التقديم إلى الصرف. المستخلص المعتمد لا يُعدّ مصروفاً حتى تُسجَّل دفعته.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ResponsiveGrid(minItemWidth: 170, spacing: 8, children: [
            stat('القيمة الأصلية للعقد', money(p.contractValue), icon: Icons.description_outlined),
            stat('أوامر التغيير بالزيادة', '+${fmtMoney(p.variationsAdd)}', icon: Icons.add_circle_outline_rounded, color: sem.ok,
                sub: pendingVo.isEmpty ? 'المعتمدة' : 'المعتمدة · ${pendingVo.length} بانتظار الاعتماد'),
            stat('أوامر التغيير بالنقصان', '−${fmtMoney(p.variationsDeduct)}', icon: Icons.remove_circle_outline_rounded, color: sem.danger,
                sub: 'تنقص القيمة، لا من المستخلصات'),
            stat('القيمة الإجمالية المعدلة', money(adjusted), icon: Icons.functions_rounded, color: cs.primary,
                sub: 'الأصلية + الزيادة − النقص'),
            stat('المستخلصات المقدمة', money(p.extractsSubmitted), icon: Icons.outbox_outlined, sub: '$submittedCount مستخلص'),
            stat('المستخلصات المعتمدة', money(p.extractsGross), icon: Icons.fact_check_outlined, sub: '${p.extractsCount} مستخلص'),
            stat('المبالغ المدفوعة', money(p.paidTotal), icon: Icons.payments_outlined, color: sem.ok,
                sub: p.paidRatio == null ? null : '${pctText(p.paidRatio!, digits: 1)} من القيمة المعدلة'),
            stat('المستحقات غير المدفوعة', money(p.unpaidGross), icon: Icons.pending_actions_outlined,
                color: p.unpaidGross > 0 ? sem.wip : null, sub: 'من المعتمد، قبل الاستقطاعات'),
            stat('التأمينات والاستقطاعات', money(p.extractDeductions), icon: Icons.lock_outline_rounded,
                sub: p.retentionHeld > 0 ? 'منها تأمين محتجز ${compactMoney(p.retentionHeld)}' : 'من المستخلصات المعتمدة'),
            stat('صافي المستحقات', money(p.outstanding), icon: Icons.account_balance_wallet_outlined,
                color: p.outstanding > 0 ? sem.wip : null, sub: 'الصافي المعتمد − المدفوع'),
            stat('نسبة الإنجاز المالي', progress == null ? '—' : pctText(progress, digits: 1), icon: Icons.donut_large_rounded,
                color: cs.primary,
                sub: 'المعتمد ÷ القيمة المعدلة',
                extra: AnimatedMeter(value: (progress ?? 0).clamp(0, 1).toDouble(), color: (progress ?? 0) > 1 ? sem.danger : sem.ok)),
          ]),
          if ((adjusted ?? 0) > 0 || (p.contractValue ?? 0) > 0) ...[
            const SizedBox(height: 16),
            LayoutBuilder(builder: (context, c) {
              final value = _Bars(title: 'من القيمة الأصلية إلى المعدلة', rows: [
                ('الأصلية', p.contractValue ?? 0, cs.primary.withValues(alpha: 0.55), fmtMoney(p.contractValue ?? 0)),
                ('الزيادة', p.variationsAdd, sem.ok, '+${fmtMoney(p.variationsAdd)}'),
                ('النقص', p.variationsDeduct, sem.danger, '−${fmtMoney(p.variationsDeduct)}'),
                ('المعدلة', adjusted ?? 0, cs.primary, fmtMoney(adjusted ?? 0)),
              ]);
              final flow = _Bars(title: 'المستخلصات من التقديم إلى الصرف', rows: [
                ('المقدمة', p.extractsSubmitted, sem.wip, fmtMoney(p.extractsSubmitted)),
                ('المعتمدة', p.extractsGross, cs.primary, fmtMoney(p.extractsGross)),
                ('الصافي', p.extractsNet, cs.primary.withValues(alpha: 0.6), fmtMoney(p.extractsNet)),
                ('المدفوع', p.extractsPaid, sem.ok, fmtMoney(p.extractsPaid)),
              ], scale: math.max(adjusted ?? 0, p.extractsSubmitted));
              return c.maxWidth >= 640
                  ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Expanded(child: value),
                      const SizedBox(width: 20),
                      Expanded(child: flow),
                    ])
                  : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [value, const SizedBox(height: 14), flow]);
            }),
            if ((adjusted ?? 0) > 0) ...[
              const SizedBox(height: 14),
              Text('توزيع القيمة المعدلة', style: TextStyle(color: sem.muted, fontSize: 12.5, fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              StackBar(parts: [
                ('مدفوع', p.paidTotal, sem.ok),
                ('صافي مستحق', p.outstanding, sem.wip),
                ('تأمين محتجز', p.retentionHeld, cs.primary),
                ('استقطاعات أخرى', math.max(0.0, p.extractDeductions - p.retentionHeld), sem.danger),
                ('لم يُعتمد بعد', math.max(0.0, (adjusted ?? 0) - p.extractsGross), sem.todo),
              ]),
            ],
          ],
        ],
      ),
    );
  }
}

/// أشرطة أفقية بمقياس واحد مع قيمها.
class _Bars extends StatelessWidget {
  const _Bars({required this.title, required this.rows, this.scale});

  final String title;
  final List<(String, double, Color, String)> rows;
  final double? scale;

  @override
  Widget build(BuildContext context) {
    final sem = Sem.of(context);
    final max = math.max(scale ?? 0, rows.fold<double>(0, (a, r) => math.max(a, r.$2)));
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(title, style: TextStyle(color: sem.muted, fontSize: 12.5, fontWeight: FontWeight.w600)),
      const SizedBox(height: 8),
      for (final r in rows)
        Padding(
          padding: const EdgeInsets.only(bottom: 7),
          child: Row(children: [
            SizedBox(width: 62, child: Text(r.$1, style: TextStyle(color: sem.muted, fontSize: 12))),
            Expanded(child: AnimatedMeter(value: max <= 0 ? 0 : (r.$2 / max).clamp(0, 1).toDouble(), color: r.$3, height: 10)),
            const SizedBox(width: 8),
            SizedBox(
              width: 104,
              child: Text(r.$4, textAlign: TextAlign.end, style: _tabular.copyWith(fontSize: 12, fontWeight: FontWeight.w700)),
            ),
          ]),
        ),
    ]);
  }
}

// ---------------------------------------------------------------------
// ضمانات العقد وتأميناته
// ---------------------------------------------------------------------

/// ملخص ضمانات العقد وتأميناته في بطاقة المالية، بزر التعديل لمن يختص بالمالية.
class GuaranteesStrip extends StatelessWidget {
  const GuaranteesStrip({super.key, required this.project, this.onChanged});

  final Project project;
  final VoidCallback? onChanged;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final p = project;
    final sem = Sem.of(context);
    final can = app.canEditFinance(p) && !app.frozenForMe;
    Widget chip(String label, String value, {bool off = false}) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(color: sem.surface2, borderRadius: BorderRadius.circular(10)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text(label, style: TextStyle(color: sem.muted, fontSize: 11.5)),
            Text(value, style: _tabular.copyWith(fontWeight: FontWeight.w800, color: off ? sem.muted : null)),
          ]),
        );
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Expanded(
          child: Text('ضمانات العقد وتأميناته', style: TextStyle(color: sem.muted, fontSize: 12.5, fontWeight: FontWeight.w600)),
        ),
        if (can)
          TextButton.icon(
            onPressed: () async {
              final ok = await showGuaranteesDialog(context, p);
              if (ok && context.mounted) {
                showToast(context, 'حُفظت ضمانات العقد وتأميناته');
                onChanged?.call();
              }
            },
            icon: const Icon(Icons.tune_rounded, size: 18),
            label: const Text('تعديل'),
          ),
      ]),
      const SizedBox(height: 6),
      Wrap(spacing: 8, runSpacing: 8, children: [
        chip('الضمان الابتدائي ${rateText(p.initialRate)}', p.guaranteeInitialNa ? 'لا ينطبق' : fmtMoney(p.guaranteeInitial),
            off: p.guaranteeInitialNa),
        chip('الضمان النهائي ${rateText(p.finalRate)}', p.guaranteeFinalNa ? 'لا ينطبق' : fmtMoney(p.guaranteeFinal), off: p.guaranteeFinalNa),
        chip('خصم التأمينات من المستخلصات',
            p.retentionDeduct ? 'مفعّل ${rateText(p.contractRetentionRate ?? app.settings.retentionRate)}' : 'معطّل',
            off: !p.retentionDeduct),
      ]),
      const SizedBox(height: 6),
      Text(
        'النسب ثابتة لهذا العقد منذ إنشائه، ولا يغيّرها تعديل النسب الافتراضية في لوحة التحكم. الضمانان من قيمة الأعمال المنفذة.',
        style: TextStyle(fontSize: 11.5, color: sem.muted),
      ),
    ]);
  }
}

Future<bool> showGuaranteesDialog(BuildContext context, Project p) async =>
    await showDialog<bool>(context: context, builder: (_) => _GuaranteesDialog(project: p)) ?? false;

class _GuaranteesDialog extends StatefulWidget {
  const _GuaranteesDialog({required this.project});

  final Project project;

  @override
  State<_GuaranteesDialog> createState() => _GuaranteesDialogState();
}

class _GuaranteesDialogState extends State<_GuaranteesDialog> {
  late final Project p = widget.project;
  late final _ir = TextEditingController(text: _pct(p.initialRate));
  late final _fr = TextEditingController(text: _pct(p.finalRate));
  late final _rr = TextEditingController(text: _pct(p.contractRetentionRate ?? 0));
  late bool _ina = p.guaranteeInitialNa;
  late bool _fna = p.guaranteeFinalNa;
  late bool _rd = p.retentionDeduct;
  bool _busy = false;
  String? _error;

  static String _pct(double r) {
    final v = r * 100;
    return v == v.roundToDouble() ? v.round().toString() : v.toStringAsFixed(2).replaceFirst(RegExp(r'0+$'), '');
  }

  /// النسبة كما كُتبت (2 تعني 2%)، أو null إن لم تكن بين 0 و50.
  double? _rate(TextEditingController c) {
    final r = parseMoney(c.text);
    if (!r.ok || r.value == null || r.value! > 50) return null;
    return (r.value! * 1000).roundToDouble() / 100000;
  }

  @override
  void dispose() {
    _ir.dispose();
    _fr.dispose();
    _rr.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final ir = _rate(_ir), fr = _rate(_fr), rr = _rate(_rr);
    if (ir == null || fr == null || rr == null) {
      setState(() => _error = 'اكتب كل نسبة رقماً من 0 إلى 50 (مثل 2 أو 5).');
      return;
    }
    final data = <String, dynamic>{
      if ((ir - p.initialRate).abs() > 1e-7) 'initial_rate': ir,
      if ((fr - p.finalRate).abs() > 1e-7) 'final_rate': fr,
      if (_ina != p.guaranteeInitialNa) 'initial_na': _ina,
      if (_fna != p.guaranteeFinalNa) 'final_na': _fna,
      if (_rd != p.retentionDeduct) 'retention_deduct': _rd,
      if ((rr - (p.contractRetentionRate ?? 0)).abs() > 1e-7) 'retention_rate': rr,
    };
    if (data.isEmpty) {
      Navigator.of(context).pop(false);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await AppScope.read(context).setContractGuarantees(p.id, data);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _block({required String title, required TextEditingController c, required bool off, required ValueChanged<bool> onOff,
      required String offLabel, String? amount, bool invert = false}) {
    final sem = Sem.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      decoration: BoxDecoration(color: sem.surface2, borderRadius: BorderRadius.circular(12)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text(off ? offLabel : (amount ?? '')),
          value: invert ? !off : off,
          onChanged: (v) => onOff(invert ? !v : v),
        ),
        TextField(
          controller: c,
          enabled: !off,
          style: _tabular,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          onChanged: (_) => setState(() {}),
          decoration: fieldDeco('النسبة', error: _rate(c) == null ? 'من 0 إلى 50' : null).copyWith(suffixText: '%'),
        ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final sem = Sem.of(context);
    final base = p.executedValue;
    String? amt(TextEditingController c) {
      final r = _rate(c);
      return base == null || r == null ? null : 'المبلغ ${fmtMoney(roundMoney(base * r))} $currencyLabel من الأعمال المنفذة';
    }

    return AlertDialog(
      title: const Text('ضمانات العقد وتأميناته'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            _block(
              title: 'الضمان الابتدائي لا ينطبق على العقد',
              c: _ir,
              off: _ina,
              onOff: (v) => setState(() => _ina = v),
              offLabel: 'لا يُحسب ولا يدخل في المجاميع',
              amount: amt(_ir),
            ),
            const SizedBox(height: 10),
            _block(
              title: 'الضمان النهائي لا ينطبق على العقد',
              c: _fr,
              off: _fna,
              onOff: (v) => setState(() => _fna = v),
              offLabel: 'لا يُحسب ولا يدخل في المجاميع',
              amount: amt(_fr),
            ),
            const SizedBox(height: 10),
            _block(
              title: 'خصم التأمينات من المستخلصات',
              c: _rr,
              off: !_rd,
              invert: true,
              onOff: (v) => setState(() => _rd = !v),
              offLabel: 'معطّل: لا يُحتجز تأمين في المستخلصات الجديدة، وما سُجّل قبل التعطيل يبقى',
              amount: 'النسبة المقترحة في كل مستخلص جديد',
            ),
            const SizedBox(height: 10),
            Text('يُسجَّل كل تعديل في سجل التدقيق بقيمه قبل وبعد، ولا يمس العقود الأخرى.',
                style: TextStyle(color: sem.muted, fontSize: 12)),
            if (_error != null) ...[const SizedBox(height: 10), InfoBanner(text: _error!, level: 'critical')],
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.of(context).pop(false), child: const Text('إلغاء')),
        FilledButton(onPressed: _busy ? null : _save, child: const Text('حفظ')),
      ],
    );
  }
}

// ---------------------------------------------------------------------
// أوامر التغيير: صفحة الأمر بسجله وقراراته، ومحرر الأمر ببنوده
// ---------------------------------------------------------------------

Color variationStatusColor(BuildContext context, String status) {
  final sem = Sem.of(context);
  return switch (status) {
    'approved' => sem.ok,
    'rejected' => sem.danger,
    _ => sem.wip,
  };
}

/// صفحة أمر التغيير: قيمه وبنوده وسجله، والقرارات المتاحة للمستخدم.
class VariationPage extends StatelessWidget {
  const VariationPage({super.key, required this.variationId});

  final String variationId;

  ContractVariation? _find(AppState app) {
    for (final v in app.variations) {
      if (v.id == variationId) return v;
    }
    return null;
  }

  Future<void> _decide(BuildContext context, AppState app, ContractVariation v, String decision) async {
    final res = await showDialog<(String, DateTime?)>(context: context, builder: (_) => _DecisionDialog(decision: decision));
    if (res == null || !context.mounted) return;
    try {
      await app.decideVariation(v.id, decision, note: res.$1, date: res.$2);
      if (context.mounted) {
        showToast(context, switch (decision) {
          'approve' => 'اعتُمد أمر التغيير وأُضيف أثره إلى قيمة العقد',
          'reject' => 'رُفض أمر التغيير',
          _ => 'أُعيد أمر التغيير إلى مسودة',
        });
      }
    } catch (e) {
      if (context.mounted) showToast(context, friendlyError(e), error: true);
    }
  }

  Future<void> _delete(BuildContext context, AppState app, ContractVariation v) async {
    final ok = await confirmDialog(context,
        title: 'حذف أمر التغيير؟',
        message: 'يُحذف «${v.title}» وبنوده وسجله${v.isApproved ? '، ويخرج أثره من قيمة العقد' : ''}. يبقى الأثر في سجل التدقيق.',
        confirmLabel: 'حذف',
        danger: true);
    if (!ok || !context.mounted) return;
    final nav = Navigator.of(context);
    try {
      await app.deleteVariation(v.id);
      nav.pop();
    } catch (e) {
      if (context.mounted) showToast(context, friendlyError(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final sem = Sem.of(context);
    final cs = Theme.of(context).colorScheme;
    final v = _find(app);
    if (v == null) {
      return Scaffold(
        appBar: brandAppBar(context, title: const Text('أمر تغيير')),
        body: const Center(child: EmptyState(title: 'أمر التغيير غير موجود', message: 'ربما حُذف.')),
      );
    }
    final p = app.project(v.projectId);
    final items = app.variationItemsOf(v.id);
    final events = app.variationEventsOf(v.id).reversed.toList();
    final change = app.changeOfVariation(v.id);
    final canEdit = p != null && app.canEditFinanceItems(p) && change == null && !v.merged;
    final canDecide = p != null && app.canApproveVariation(p) && change == null;
    final sheets = {for (final s in app.boqSheets) s.id: s};
    final net = v.signed;
    final adjustedAfter = p == null ? null : (p.contractValue ?? 0) + p.variationsNet + (v.isApproved ? 0 : net);

    final actions = <Widget>[
      if (v.isDraft && canEdit)
        OutlinedButton.icon(
          onPressed: () => Navigator.of(context)
              .push(MaterialPageRoute<void>(builder: (_) => VariationEditorPage(projectId: v.projectId, variationId: v.id))),
          icon: const Icon(Icons.edit_outlined, size: 18),
          label: const Text('تعديل'),
        ),
      if (v.isDraft && canDecide) ...[
        FilledButton.icon(
          onPressed: () => _decide(context, app, v, 'approve'),
          icon: const Icon(Icons.verified_rounded, size: 18),
          label: const Text('اعتماد'),
        ),
        OutlinedButton.icon(
          onPressed: () => _decide(context, app, v, 'reject'),
          icon: Icon(Icons.block_rounded, size: 18, color: sem.danger),
          label: Text('رفض', style: TextStyle(color: sem.danger)),
        ),
      ],
      if (!v.isDraft && app.isDirector && change == null && !app.frozenForMe)
        OutlinedButton.icon(
          onPressed: () => _decide(context, app, v, 'reopen'),
          icon: const Icon(Icons.undo_rounded, size: 18),
          label: const Text('إعادة إلى مسودة'),
        ),
      if (canEdit && (!v.isApproved || app.isDirector))
        TextButton.icon(
          onPressed: () => _delete(context, app, v),
          icon: Icon(Icons.delete_outline_rounded, size: 18, color: sem.danger),
          label: Text('حذف', style: TextStyle(color: sem.danger)),
        ),
    ];

    return Scaffold(
      appBar: brandAppBar(context, title: Text(v.refNo.isEmpty ? 'أمر تغيير' : 'أمر التغيير ${isolate(v.refNo)}')),
      body: PageBody(maxWidth: 1000, children: [
        PageHeader(
          icon: Icons.swap_vert_rounded,
          title: v.title,
          subtitle: [
            if (p != null) p.label,
            v.statusLabel,
            if (v.approvedOn != null) 'اعتُمد ${dayText(v.approvedOn)}',
            if (v.merged) 'مدمج من عقد آخر',
          ].join(' · '),
        ),
        if (change != null)
          InfoBanner(text: 'هذا الأمر من سجل التغييرات (${change.code})؛ يُعدَّل ويُبت فيه من هناك.', icon: Icons.link_rounded),
        if (v.isDraft)
          const InfoBanner(
              text: 'مسودة: لا تدخل في قيمة العقد حتى يعتمدها مدير المكتب أو من يعتمد المستخلصات.', level: 'warning'),
        if (v.isRejected && v.decisionNote.isNotEmpty) InfoBanner(text: 'سبب الرفض: ${v.decisionNote}', level: 'critical'),
        ResponsiveGrid(minItemWidth: 170, spacing: 10, children: [
          StatCard(label: 'الأعمال المضافة', value: '+${fmtMoney(v.addedValue)}', icon: Icons.add_rounded, color: sem.ok),
          StatCard(label: 'الأعمال الملغاة أو المخفضة', value: '−${fmtMoney(v.deductedValue)}', icon: Icons.remove_rounded, color: sem.danger),
          StatCard(label: 'الصافي على قيمة العقد', value: _signed(net), icon: Icons.functions_rounded, color: cs.primary),
          if (adjustedAfter != null)
            StatCard(
              label: v.isApproved ? 'القيمة المعدلة الحالية' : 'القيمة المعدلة إن اعتُمد',
              value: fmtMoney(adjustedAfter),
              icon: Icons.account_balance_outlined,
            ),
        ]),
        if (actions.isNotEmpty) Wrap(spacing: 10, runSpacing: 10, children: actions),
        SectionCard(
          title: 'البنود المتأثرة',
          icon: Icons.format_list_numbered_rounded,
          subtitle: items.isEmpty
              ? 'أمر بقيمة إجمالية دون بنود${app.work(v.workId) != null ? '، على عمل «${app.work(v.workId)!.title}»' : ''}.'
              : 'كل بند زيادة أو نقص بكميته وسعره، مربوطاً ببند المقايسة إن وُجد.',
          child: items.isEmpty
              ? Text('${v.isAdd ? 'زيادة' : 'نقص'} ${money(v.amount)}', style: _tabular.copyWith(fontWeight: FontWeight.w700))
              : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  for (final it in items) _ItemRow(item: it, sheet: sheets[it.boqSheetId]),
                ]),
        ),
        SectionCard(
          title: 'سجل الأمر',
          icon: Icons.history_rounded,
          subtitle: 'كل حفظ وقرار بتاريخه وصاحبه وقيم الأمر عندها.',
          child: events.isEmpty
              ? Text('لا سجل لهذا الأمر (سُجّل قبل الإصدار 1.6.0).', style: TextStyle(color: sem.muted, fontSize: 12.5))
              : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  for (final e in events)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: CircleAvatar(
                        radius: 15,
                        backgroundColor: _eventColor(context, e.action).withValues(alpha: 0.15),
                        child: Icon(_eventIcon(e.action), size: 16, color: _eventColor(context, e.action)),
                      ),
                      title: Text('${e.label}${e.actorName.isEmpty ? '' : ' · ${e.actorName}'}'),
                      subtitle: Text([
                        if (e.at != null) fmtDate(e.at),
                        'زيادة ${fmtMoney(e.added ?? 0)} · نقص ${fmtMoney(e.deducted ?? 0)}',
                        if (e.itemCount > 0) '${e.itemCount} بنداً',
                        if (e.note.isNotEmpty) e.note,
                      ].join(' · ')),
                    ),
                ]),
        ),
      ]),
    );
  }

  static IconData _eventIcon(String a) => switch (a) {
        'approve' => Icons.verified_rounded,
        'reject' => Icons.block_rounded,
        'reopen' => Icons.undo_rounded,
        'update' => Icons.edit_outlined,
        _ => Icons.add_rounded,
      };

  static Color _eventColor(BuildContext context, String a) {
    final sem = Sem.of(context);
    return switch (a) {
      'approve' => sem.ok,
      'reject' => sem.danger,
      'reopen' => sem.wip,
      _ => Theme.of(context).colorScheme.primary,
    };
  }
}

class _ItemRow extends StatelessWidget {
  const _ItemRow({required this.item, this.sheet});

  final VariationItem item;
  final BoqSheet? sheet;

  @override
  Widget build(BuildContext context) {
    final sem = Sem.of(context);
    final c = item.isAdd ? sem.ok : sem.danger;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
        decoration: BoxDecoration(color: sem.surface2, borderRadius: BorderRadius.circular(10)),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(item.isAdd ? Icons.add_circle_outline_rounded : Icons.remove_circle_outline_rounded, size: 18, color: c),
          const SizedBox(width: 8),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text([if (item.code.isNotEmpty) isolate(item.code), item.description].join(' · '),
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              Text(
                [
                  if (item.qty != null) 'الكمية ${fmtQtyV(item.qty!)} ${item.unit}'.trim(),
                  if (item.unitPrice != null) 'السعر ${fmtMoney(item.unitPrice)}',
                  if (item.linkedToBoq) 'من «${sheet?.title ?? 'مقايسة العقد'}»' else 'بند جديد',
                ].join(' · '),
                style: TextStyle(color: sem.muted, fontSize: 12),
              ),
            ]),
          ),
          Text('${item.isAdd ? '+' : '−'}${fmtMoney(item.amount)}', style: _tabular.copyWith(fontWeight: FontWeight.w800, color: c)),
        ]),
      ),
    );
  }
}

/// الكمية بلا أصفار زائدة.
String fmtQtyV(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(3).replaceFirst(RegExp(r'0+$'), '');

/// نافذة القرار: الاعتماد بتاريخه، والرفض والإعادة بسببهما.
class _DecisionDialog extends StatefulWidget {
  const _DecisionDialog({required this.decision});

  final String decision;

  @override
  State<_DecisionDialog> createState() => _DecisionDialogState();
}

class _DecisionDialogState extends State<_DecisionDialog> {
  final _note = TextEditingController();
  DateTime? _date = DateTime.now();
  String? _error;

  bool get _approve => widget.decision == 'approve';

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sem = Sem.of(context);
    return AlertDialog(
      title: Text(switch (widget.decision) {
        'approve' => 'اعتماد أمر التغيير',
        'reject' => 'رفض أمر التغيير',
        _ => 'إعادة الأمر إلى مسودة',
      }),
      content: SizedBox(
        width: 440,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(
            switch (widget.decision) {
              'approve' => 'يدخل صافي الأمر في القيمة المعدلة للعقد من تاريخ اعتماده، ولا يُعدَّل بعد ذلك إلا بإعادته إلى مسودة.',
              'reject' => 'لا يدخل المرفوض في قيمة العقد، ويبقى في السجل بسبب رفضه.',
              _ => 'يخرج أثر الأمر من قيمة العقد حتى يُعتمد من جديد.',
            },
            style: TextStyle(color: sem.muted, fontSize: 12.5, height: 1.5),
          ),
          const SizedBox(height: 12),
          if (_approve) ...[
            DayField(label: 'تاريخ الاعتماد', value: _date, onChanged: (d) => setState(() => _date = d)),
            const SizedBox(height: 10),
          ],
          TextField(
            controller: _note,
            maxLines: 2,
            autofocus: !_approve,
            decoration: fieldDeco(_approve ? 'ملاحظة (اختيارية)' : 'السبب'),
          ),
          if (_error != null) ...[const SizedBox(height: 10), InfoBanner(text: _error!, level: 'critical')],
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('إلغاء')),
        FilledButton(
          onPressed: () {
            if (!_approve && _note.text.trim().length < 3) {
              setState(() => _error = 'اكتب السبب.');
              return;
            }
            Navigator.of(context).pop((_note.text.trim(), _approve ? _date : null));
          },
          child: Text(switch (widget.decision) {
            'approve' => 'اعتماد',
            'reject' => 'رفض',
            _ => 'إعادة إلى مسودة',
          }),
        ),
      ],
    );
  }
}

/// محرر أمر التغيير: بياناته، وبنوده من مقايسة العقد أو جديدة، أو قيمة إجمالية دون بنود. يُحفظ مسودة.
class VariationEditorPage extends StatefulWidget {
  const VariationEditorPage({super.key, required this.projectId, this.variationId});

  final String projectId;
  final String? variationId;

  @override
  State<VariationEditorPage> createState() => _VariationEditorPageState();
}

class _LineCtl {
  _LineCtl(this.item)
      : desc = TextEditingController(text: item.description),
        qty = TextEditingController(text: item.qty == null ? '' : fmtQtyV(item.qty!)),
        price = TextEditingController(text: moneyInput(item.unitPrice)),
        amount = TextEditingController(text: item.qty != null && item.unitPrice != null ? '' : moneyInput(item.amount > 0 ? item.amount : null)),
        direction = item.direction;

  final VariationItem item;
  final TextEditingController desc;
  final TextEditingController qty;
  final TextEditingController price;
  final TextEditingController amount;
  String direction;

  double? get q => parseMoney(qty.text).value;
  double? get pr => parseMoney(price.text).value;
  double get value => VariationItem.valueOf(q, pr, parseMoney(amount.text).value);
  bool get ok => parseMoney(qty.text).ok && parseMoney(price.text).ok && parseMoney(amount.text).ok && desc.text.trim().length >= 2 && value > 0;

  void dispose() {
    desc.dispose();
    qty.dispose();
    price.dispose();
    amount.dispose();
  }

  Map<String, dynamic> toJson() => VariationItem(
        direction: direction,
        boqSheetId: item.boqSheetId,
        boqLine: item.boqLine,
        workId: item.workId,
        code: item.code,
        description: desc.text.trim(),
        unit: item.unit,
        qty: q,
        unitPrice: pr,
        amount: value,
      ).toJson();
}

class _VariationEditorPageState extends State<VariationEditorPage> {
  late final AppState app = AppScope.read(context);
  ContractVariation? _v;
  final _title = TextEditingController();
  final _ref = TextEditingController();
  final _notes = TextEditingController();
  final _amount = TextEditingController();
  String _kind = 'add';
  String? _work;
  final List<_LineCtl> _lines = [];
  bool _busy = false;
  bool _init = false;
  String? _error;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_init) return;
    _init = true;
    for (final v in app.variations) {
      if (v.id == widget.variationId) _v = v;
    }
    final v = _v;
    if (v != null) {
      _title.text = v.title;
      _ref.text = v.refNo;
      _notes.text = v.notes;
      _kind = v.kind;
      _work = v.workId;
      final items = app.variationItemsOf(v.id);
      if (items.isEmpty) _amount.text = moneyInput(v.amount);
      _lines.addAll(items.map(_LineCtl.new));
    }
  }

  @override
  void dispose() {
    for (final c in [_title, _ref, _notes, _amount]) {
      c.dispose();
    }
    for (final l in _lines) {
      l.dispose();
    }
    super.dispose();
  }

  double get _added => _lines.where((l) => l.direction == 'add').fold<double>(0, (a, l) => a + l.value);
  double get _deducted => _lines.where((l) => l.direction == 'deduct').fold<double>(0, (a, l) => a + l.value);
  double get _net {
    if (_lines.isNotEmpty) return roundMoney(_added - _deducted);
    final a = parseMoney(_amount.text).value ?? 0;
    return _kind == 'add' ? a : -a;
  }

  void _addFree() => setState(() => _lines.add(_LineCtl(const VariationItem(direction: 'add', description: '', amount: 0))));

  Future<void> _addFromBoq() async {
    final sheets = [for (final s in app.boqSheets) if (s.projectId == widget.projectId && s.lines.isNotEmpty) s];
    if (sheets.isEmpty) {
      showToast(context, 'لا مقايسة لهذا العقد تطّلع عليها؛ أضف البند جديداً.', error: true);
      return;
    }
    final picked = await showDialog<List<(BoqSheet, int)>>(context: context, builder: (_) => _BoqPicker(sheets: sheets));
    if (picked == null || picked.isEmpty) return;
    setState(() {
      for (final (s, i) in picked) {
        final l = s.lines[i];
        _lines.add(_LineCtl(VariationItem(
          direction: 'add',
          boqSheetId: s.id,
          boqLine: i,
          code: l.code,
          description: l.desc,
          unit: l.unit,
          unitPrice: l.price,
          amount: 0,
        )));
      }
    });
  }

  Future<void> _save() async {
    if (_title.text.trim().length < 2) {
      setState(() => _error = 'اكتب وصف أمر التغيير.');
      return;
    }
    if (_lines.isEmpty) {
      final a = parseMoney(_amount.text);
      if (!a.ok || (a.value ?? 0) <= 0) {
        setState(() => _error = 'أضف بنوداً، أو اكتب قيمة إجمالية للأمر أكبر من صفر.');
        return;
      }
    } else {
      final bad = _lines.indexWhere((l) => !l.ok);
      if (bad >= 0) {
        setState(() => _error = 'أكمل البند ${bad + 1}: وصفه، وكميته وسعره أو قيمته (أكبر من صفر).');
        return;
      }
      if (_added + _deducted <= 0) {
        setState(() => _error = 'قيمة البنود صفر.');
        return;
      }
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final id = await app.saveContractVariation(_v?.id, {
        if (_v == null) 'project_id': widget.projectId,
        'title': _title.text.trim(),
        'ref_no': _ref.text.trim(),
        'notes': _notes.text.trim(),
        'work_id': _work,
        if (_lines.isEmpty) ...{'kind': _kind, 'amount': parseMoney(_amount.text).value},
        'items': [for (final l in _lines) l.toJson()],
      });
      if (!mounted) return;
      showToast(context, 'حُفظ أمر التغيير مسودة بانتظار الاعتماد');
      if (_v == null) {
        Navigator.of(context).pushReplacement(MaterialPageRoute<void>(builder: (_) => VariationPage(variationId: id)));
      } else {
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final sem = Sem.of(context);
    final cs = Theme.of(context).colorScheme;
    final p = app.project(widget.projectId);
    final works = app.worksOf(widget.projectId);
    final adjusted = p == null ? null : (p.contractValue ?? 0) + p.variationsNet;
    final wide = MediaQuery.sizeOf(context).width >= 700;
    Widget pair(Widget a, Widget b) => wide
        ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(child: a), const SizedBox(width: 10), Expanded(child: b)])
        : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [a, const SizedBox(height: 10), b]);

    return Scaffold(
      appBar: brandAppBar(context, title: Text(_v == null ? 'أمر تغيير جديد' : 'تعديل أمر التغيير'), actions: [
        Padding(
          padding: const EdgeInsetsDirectional.only(end: 10),
          child: FilledButton.icon(
            onPressed: _busy ? null : _save,
            icon: _busy
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.save_rounded, size: 18),
            label: const Text('حفظ مسودة'),
          ),
        ),
      ]),
      body: PageBody(maxWidth: 1000, children: [
        PageHeader(
          icon: Icons.swap_vert_rounded,
          title: _v == null ? 'أمر تغيير جديد' : _v!.title,
          subtitle: p?.label,
        ),
        const InfoBanner(
          text: 'يُحفظ الأمر مسودة، ولا يدخل في قيمة العقد حتى يعتمده مدير المكتب أو من يعتمد المستخلصات. '
              'النقص في الأمر ينقص قيمة العقد، ولا يُكرَّر خصماً في المستخلصات.',
        ),
        if (_error != null) InfoBanner(text: _error!, level: 'critical'),
        SectionCard(
          title: 'بيانات الأمر',
          icon: Icons.description_outlined,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            TextField(controller: _title, decoration: fieldDeco('وصف أمر التغيير')),
            const SizedBox(height: 10),
            pair(
              TextField(controller: _ref, textDirection: TextDirection.ltr, decoration: fieldDeco('رقم الأمر')),
              works.length > 1
                  ? SelectField(
                      label: 'عمل العقد (اختياري)',
                      value: _work ?? '',
                      items: [('', 'العقد كله'), for (final w in works) (w.id, w.title.isEmpty ? w.company : w.title)],
                      onChanged: (v) => setState(() => _work = v.isEmpty ? null : v),
                    )
                  : const SizedBox.shrink(),
            ),
            const SizedBox(height: 10),
            TextField(controller: _notes, maxLines: 2, decoration: fieldDeco('ملاحظات')),
          ]),
        ),
        SectionCard(
          title: 'البنود المتأثرة',
          icon: Icons.format_list_numbered_rounded,
          subtitle: 'أضف بنود الزيادة والنقص من مقايسة العقد أو بنوداً جديدة، فتُحسب قيمة الأمر منها. أو اكتب قيمة إجمالية دون بنود.',
          trailing: Wrap(spacing: 6, children: [
            OutlinedButton.icon(onPressed: _addFromBoq, icon: const Icon(Icons.playlist_add_rounded, size: 18), label: const Text('من المقايسة')),
            OutlinedButton.icon(onPressed: _addFree, icon: const Icon(Icons.add_rounded, size: 18), label: const Text('بند جديد')),
          ]),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (_lines.isEmpty) ...[
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'add', label: Text('زيادة'), icon: Icon(Icons.add_rounded)),
                  ButtonSegment(value: 'deduct', label: Text('نقص'), icon: Icon(Icons.remove_rounded)),
                ],
                selected: {_kind},
                onSelectionChanged: (s) => setState(() => _kind = s.first),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _amount,
                style: _tabular,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                onChanged: (_) => setState(() {}),
                decoration: fieldDeco('القيمة الإجمالية للأمر').copyWith(suffixText: currencyLabel),
              ),
            ] else
              for (var i = 0; i < _lines.length; i++) _lineEditor(context, i),
          ]),
        ),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: cs.primaryContainer.withValues(alpha: 0.35), borderRadius: BorderRadius.circular(14)),
          child: Wrap(spacing: 22, runSpacing: 8, children: [
            _total('الزيادة', '+${fmtMoney(_lines.isEmpty ? (_kind == 'add' ? _net : 0) : _added)}', sem.ok),
            _total('النقص', '−${fmtMoney(_lines.isEmpty ? (_kind == 'deduct' ? -_net : 0) : _deducted)}', sem.danger),
            _total('الصافي', _signed(_net), cs.primary),
            if (adjusted != null) _total('القيمة المعدلة إن اعتُمد', fmtMoney(adjusted + _net - (_v?.isApproved == true ? _v!.signed : 0)), null),
          ]),
        ),
      ]),
    );
  }

  Widget _total(String label, String value, Color? color) {
    final sem = Sem.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      Text(label, style: TextStyle(color: sem.muted, fontSize: 12)),
      Text(value, style: _tabular.copyWith(fontWeight: FontWeight.w800, fontSize: 16, color: color)),
    ]);
  }

  Widget _lineEditor(BuildContext context, int i) {
    final sem = Sem.of(context);
    final l = _lines[i];
    final c = l.direction == 'add' ? sem.ok : sem.danger;
    final byQty = l.q != null && l.pr != null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 8, 6, 10),
        decoration: BoxDecoration(
          color: Color.alphaBlend(c.withValues(alpha: 0.05), sem.surface2),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Text('${i + 1}', style: TextStyle(color: sem.muted, fontWeight: FontWeight.w700)),
            const SizedBox(width: 8),
            SegmentedButton<String>(
              style: const ButtonStyle(visualDensity: VisualDensity.compact),
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: 'add', label: Text('زيادة')),
                ButtonSegment(value: 'deduct', label: Text('نقص')),
              ],
              selected: {l.direction},
              onSelectionChanged: (s) => setState(() => l.direction = s.first),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                l.item.linkedToBoq ? 'من المقايسة${l.item.code.isEmpty ? '' : ' · بند ${isolate(l.item.code)}'}' : 'بند جديد',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: sem.muted, fontSize: 12),
              ),
            ),
            Text('${l.direction == 'add' ? '+' : '−'}${fmtMoney(l.value)}', style: _tabular.copyWith(fontWeight: FontWeight.w800, color: c)),
            IconButton(
              tooltip: 'إزالة البند',
              icon: const Icon(Icons.close_rounded, size: 18),
              onPressed: () => setState(() => _lines.removeAt(i).dispose()),
            ),
          ]),
          const SizedBox(height: 8),
          TextField(controller: l.desc, onChanged: (_) => setState(() {}), decoration: fieldDeco('وصف البند')),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: TextField(
                controller: l.qty,
                style: _tabular,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                onChanged: (_) => setState(() {}),
                decoration: fieldDeco('الكمية').copyWith(suffixText: l.item.unit.isEmpty ? null : l.item.unit),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: l.price,
                style: _tabular,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                onChanged: (_) => setState(() {}),
                decoration: fieldDeco('سعر الوحدة'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: l.amount,
                enabled: !byQty,
                style: _tabular,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                onChanged: (_) => setState(() {}),
                decoration: fieldDeco(byQty ? 'القيمة = الكمية × السعر' : 'القيمة'),
              ),
            ),
          ]),
        ]),
      ),
    );
  }
}

/// اختيار بنود من مقايسات العقد.
class _BoqPicker extends StatefulWidget {
  const _BoqPicker({required this.sheets});

  final List<BoqSheet> sheets;

  @override
  State<_BoqPicker> createState() => _BoqPickerState();
}

class _BoqPickerState extends State<_BoqPicker> {
  final Set<(String, int)> _sel = {};
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final sem = Sem.of(context);
    final q = nameKey(_q);
    return AlertDialog(
      title: const Text('بنود من مقايسة العقد'),
      content: SizedBox(
        width: 620,
        height: 460,
        child: Column(children: [
          TextField(
            decoration: fieldDeco('بحث في الوصف أو الرقم', prefixIcon: const Icon(Icons.search_rounded)),
            onChanged: (v) => setState(() => _q = v),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: ListView(children: [
              for (final s in widget.sheets) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 10, 4, 4),
                  child: Text(s.title, style: TextStyle(fontWeight: FontWeight.w800, color: Theme.of(context).colorScheme.primary)),
                ),
                for (var i = 0; i < s.lines.length; i++)
                  if (q.isEmpty || nameKey('${s.lines[i].code} ${s.lines[i].desc}').contains(q))
                    CheckboxListTile(
                      dense: true,
                      value: _sel.contains((s.id, i)),
                      onChanged: (v) => setState(() => v == true ? _sel.add((s.id, i)) : _sel.remove((s.id, i))),
                      title: Text([if (s.lines[i].code.isNotEmpty) isolate(s.lines[i].code), s.lines[i].desc].join(' · '),
                          maxLines: 2, overflow: TextOverflow.ellipsis),
                      subtitle: Text(
                        [
                          if (s.lines[i].unit.isNotEmpty) s.lines[i].unit,
                          if (s.lines[i].qty != null) 'الكمية ${fmtQtyV(s.lines[i].qty!)}',
                          if (s.lines[i].price != null) 'السعر ${fmtMoney(s.lines[i].price)}',
                        ].join(' · '),
                        style: TextStyle(color: sem.muted, fontSize: 12),
                      ),
                    ),
              ],
            ]),
          ),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('إلغاء')),
        FilledButton(
          onPressed: _sel.isEmpty
              ? null
              : () {
                  final out = <(BoqSheet, int)>[];
                  for (final s in widget.sheets) {
                    for (var i = 0; i < s.lines.length; i++) {
                      if (_sel.contains((s.id, i))) out.add((s, i));
                    }
                  }
                  Navigator.of(context).pop(out);
                },
          child: Text(_sel.isEmpty ? 'إضافة' : 'إضافة ${_sel.length}'),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------
// لجان الاستلام
// ---------------------------------------------------------------------

/// لجنتا الاستلام الابتدائي والنهائي للعقد: الرئيس والأعضاء بصفاتهم وقرار التشكيل.
class CommitteesCard extends StatelessWidget {
  const CommitteesCard({super.key, required this.project});

  final Project project;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final sem = Sem.of(context);
    final merged = app.mergedCommitteesOf(project.id);
    return SectionCard(
      title: 'لجان الاستلام',
      icon: Icons.groups_2_outlined,
      subtitle: 'لكل لجنة رئيس واحد وأعضاء بصفاتهم، ولا يتكرر عضو. يشكّلها من يختص بنموذج تكليفها في الدورة المستندية.',
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (final kind in const ['initial', 'final']) ...[
          _CommitteeBlock(project: project, kind: kind, committee: app.committeeOf(project.id, kind)),
          if (kind == 'initial') Divider(height: 22, color: sem.rule),
        ],
        for (final c in merged) ...[
          Divider(height: 22, color: sem.rule),
          _CommitteeBlock(project: project, kind: c.kind, committee: c, readOnly: true),
        ],
      ]),
    );
  }
}

class _CommitteeBlock extends StatelessWidget {
  const _CommitteeBlock({required this.project, required this.kind, required this.committee, this.readOnly = false});

  final Project project;
  final String kind;
  final ContractCommittee? committee;
  final bool readOnly;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final sem = Sem.of(context);
    final cs = Theme.of(context).colorScheme;
    final c = committee;
    final can = !readOnly && app.canEditCommittee(project, kind);
    Future<void> edit() async {
      final ok = await showCommitteeEditor(context, project, kind, c);
      if (ok && context.mounted) showToast(context, 'حُفظت ${committeeKindLabels[kind]}');
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Expanded(
          child: Text(
            '${committeeKindLabels[kind]}${readOnly ? ' (من عقد مدموج)' : ''}',
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ),
        if (can)
          TextButton.icon(
            onPressed: edit,
            icon: Icon(c == null ? Icons.group_add_outlined : Icons.edit_outlined, size: 18),
            label: Text(c == null ? 'تشكيل اللجنة' : 'تعديل'),
          ),
      ]),
      if (c == null)
        Text('لم تُشكَّل بعد.', style: TextStyle(color: sem.muted, fontSize: 12.5))
      else ...[
        if (c.decisionNo.isNotEmpty || c.decisionDate != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              [if (c.decisionNo.isNotEmpty) 'قرار التشكيل ${isolate(c.decisionNo)}', if (c.decisionDate != null) dayText(c.decisionDate)]
                  .join(' · '),
              style: TextStyle(color: sem.muted, fontSize: 12.5),
            ),
          ),
        for (final m in c.members)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(children: [
              CircleAvatar(
                radius: 14,
                backgroundColor: (m.isChair ? cs.primary : sem.muted).withValues(alpha: 0.14),
                child: Icon(m.isChair ? Icons.star_rounded : Icons.person_outline_rounded, size: 16, color: m.isChair ? cs.primary : sem.muted),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text.rich(TextSpan(children: [
                  TextSpan(text: m.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                  if (m.title.isNotEmpty) TextSpan(text: ' · ${m.title}', style: TextStyle(color: sem.muted, fontSize: 12.5)),
                ])),
              ),
              if (m.isChair) ToneBadge('رئيس اللجنة', color: cs.primary),
            ]),
          ),
        if (c.notes.isNotEmpty) Text(c.notes, style: TextStyle(color: sem.muted, fontSize: 12)),
      ],
    ]);
  }
}

Future<bool> showCommitteeEditor(BuildContext context, Project p, String kind, ContractCommittee? c) async =>
    await showDialog<bool>(context: context, builder: (_) => _CommitteeDialog(project: p, kind: kind, committee: c)) ?? false;

class _MemberCtl {
  _MemberCtl([CommitteeMember? m])
      : name = TextEditingController(text: m?.name ?? ''),
        title = TextEditingController(text: m?.title ?? ''),
        profileId = m?.profileId;

  final TextEditingController name;
  final TextEditingController title;
  String? profileId;

  CommitteeMember get value => CommitteeMember(name: name.text.trim(), title: title.text.trim(), profileId: profileId);

  void dispose() {
    name.dispose();
    title.dispose();
  }
}

class _CommitteeDialog extends StatefulWidget {
  const _CommitteeDialog({required this.project, required this.kind, this.committee});

  final Project project;
  final String kind;
  final ContractCommittee? committee;

  @override
  State<_CommitteeDialog> createState() => _CommitteeDialogState();
}

class _CommitteeDialogState extends State<_CommitteeDialog> {
  late final _decision = TextEditingController(text: widget.committee?.decisionNo ?? '');
  late final _notes = TextEditingController(text: widget.committee?.notes ?? '');
  late DateTime? _date = widget.committee?.decisionDate;
  late final _chair = _MemberCtl(widget.committee?.chair);
  late final List<_MemberCtl> _members = [
    for (final m in widget.committee?.others ?? const <CommitteeMember>[]) _MemberCtl(m),
    if ((widget.committee?.others ?? const []).isEmpty) _MemberCtl(),
  ];
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _decision.dispose();
    _notes.dispose();
    _chair.dispose();
    for (final m in _members) {
      m.dispose();
    }
    super.dispose();
  }

  /// أول تكرار في اللجنة (بالاسم بعد التطبيع أو بالموظف)، كما تتحقق قاعدة البيانات.
  String? _duplicate() {
    final keys = <String>{};
    final profiles = <String>{};
    final all = [_chair.value, ..._members.map((m) => m.value)];
    for (var i = 0; i < all.length; i++) {
      final m = all[i];
      final k = nameKey(m.name);
      if (k.isEmpty) continue;
      if (!keys.add(k) || (m.profileId != null && !profiles.add(m.profileId!))) {
        final chairKey = nameKey(_chair.name.text);
        return i > 0 && (k == chairKey || (m.profileId != null && m.profileId == _chair.profileId))
            ? '«${m.name}» رئيس اللجنة؛ لا يُضاف عضواً أيضاً.'
            : 'العضو «${m.name}» مكرر في اللجنة.';
      }
    }
    return null;
  }

  Future<void> _pickPerson(_MemberCtl m) async {
    final app = AppScope.read(context);
    final people = app.people.values.where((x) => x.active).toList()..sort((a, b) => a.displayName.compareTo(b.displayName));
    final picked = await showDialog<Profile>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('من موظفي المنظومة'),
        children: [
          SizedBox(
            width: 420,
            height: 380,
            child: ListView(children: [
              for (final x in people)
                ListTile(
                  title: Text(x.displayName),
                  subtitle: x.role == null ? null : Text(x.role!.label),
                  onTap: () => Navigator.of(ctx).pop(x),
                ),
            ]),
          ),
        ],
      ),
    );
    if (picked != null) {
      setState(() {
        m.name.text = picked.displayName;
        m.profileId = picked.id;
      });
    }
  }

  Future<void> _save() async {
    if (_chair.name.text.trim().length < 2) {
      setState(() => _error = 'حدّد رئيس اللجنة.');
      return;
    }
    final members = [for (final m in _members) if (m.name.text.trim().isNotEmpty) m.value];
    if (members.isEmpty) {
      setState(() => _error = 'أضف عضواً واحداً على الأقل مع رئيس اللجنة.');
      return;
    }
    if (members.any((m) => m.name.length < 2)) {
      setState(() => _error = 'اكتب اسم كل عضو كاملاً.');
      return;
    }
    final dup = _duplicate();
    if (dup != null) {
      setState(() => _error = dup);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await AppScope.read(context).saveCommittee(widget.project.id, widget.kind, {
        'decision_no': _decision.text.trim(),
        'decision_date': _date == null ? null : dbDate(_date!),
        'notes': _notes.text.trim(),
        'chair': _chair.value.toJson(),
        'members': [for (final m in members) m.toJson()],
      });
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    final ok = await confirmDialog(context,
        title: 'حذف تشكيل اللجنة؟',
        message: 'يُحذف تشكيل ${committeeKindLabels[widget.kind]} لهذا العقد. يبقى التشكيل السابق في سجل التدقيق.',
        confirmLabel: 'حذف',
        danger: true);
    if (!ok || !mounted) return;
    try {
      await AppScope.read(context).deleteCommittee(widget.project.id, widget.kind);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    }
  }

  Widget _person(_MemberCtl m, {required String label, VoidCallback? onRemove}) {
    final sem = Sem.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          flex: 3,
          child: TextField(
            controller: m.name,
            onChanged: (_) => setState(() => m.profileId = null),
            decoration: fieldDeco(label,
                suffix: IconButton(
                  tooltip: 'من موظفي المنظومة',
                  icon: Icon(m.profileId == null ? Icons.person_search_outlined : Icons.verified_user_outlined,
                      size: 18, color: m.profileId == null ? sem.muted : Theme.of(context).colorScheme.primary),
                  onPressed: () => _pickPerson(m),
                )),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(flex: 2, child: TextField(controller: m.title, decoration: fieldDeco('الصفة الوظيفية'))),
        if (onRemove != null)
          IconButton(tooltip: 'إزالة', icon: const Icon(Icons.close_rounded, size: 18), onPressed: onRemove)
        else
          const SizedBox(width: 40),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final sem = Sem.of(context);
    final cs = Theme.of(context).colorScheme;
    return AlertDialog(
      title: Text(committeeKindLabels[widget.kind]!),
      content: SizedBox(
        width: 620,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Expanded(child: TextField(controller: _decision, decoration: fieldDeco('رقم قرار التشكيل'))),
              const SizedBox(width: 8),
              Expanded(child: DayField(label: 'تاريخ القرار', value: _date, onChanged: (d) => setState(() => _date = d))),
            ]),
            const SizedBox(height: 14),
            Text('رئيس اللجنة', style: TextStyle(fontWeight: FontWeight.w700, color: cs.primary)),
            const SizedBox(height: 6),
            _person(_chair, label: 'اسم رئيس اللجنة'),
            const SizedBox(height: 6),
            Row(children: [
              Expanded(child: Text('الأعضاء', style: TextStyle(fontWeight: FontWeight.w700, color: cs.primary))),
              TextButton.icon(
                onPressed: _members.length >= 30 ? null : () => setState(() => _members.add(_MemberCtl())),
                icon: const Icon(Icons.person_add_alt_outlined, size: 18),
                label: const Text('عضو'),
              ),
            ]),
            const SizedBox(height: 6),
            for (var i = 0; i < _members.length; i++)
              _person(_members[i],
                  label: 'العضو ${i + 1}',
                  onRemove: _members.length <= 1 ? null : () => setState(() => _members.removeAt(i).dispose())),
            TextField(controller: _notes, maxLines: 2, decoration: fieldDeco('ملاحظات')),
            const SizedBox(height: 8),
            Text('رئيس واحد للجنة، ولا يتكرر العضو نفسه (ولو اختلفت الهمزة أو المسافات). يُسجَّل كل تشكيل في سجل التدقيق.',
                style: TextStyle(color: sem.muted, fontSize: 12)),
            if (_error != null) ...[const SizedBox(height: 10), InfoBanner(text: _error!, level: 'critical')],
          ]),
        ),
      ),
      actions: [
        if (widget.committee != null)
          TextButton(onPressed: _busy ? null : _delete, child: Text('حذف التشكيل', style: TextStyle(color: sem.danger))),
        TextButton(onPressed: _busy ? null : () => Navigator.of(context).pop(false), child: const Text('إلغاء')),
        FilledButton(onPressed: _busy ? null : _save, child: const Text('حفظ اللجنة')),
      ],
    );
  }
}
