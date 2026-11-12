import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app_state.dart';
import '../models.dart';
import '../ui/charts.dart';
import '../ui/motion.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';

/// المالية الموسعة في صفحة العقد: ملخص القيم، وقيم البنود، وأوامر التغيير، وسجل المستخلصات.

const _tabular = TextStyle(fontFeatures: [FontFeature.tabularFigures()]);

String money(double? v) => v == null ? '—' : '${fmtMoney(v)} $currencyLabel';

/// ملخص مالي للعقد: القيم الأساسية وتكوينها في شريط واحد.
class ContractFinanceOverview extends StatelessWidget {
  const ContractFinanceOverview({super.key, required this.project});

  final Project project;

  @override
  Widget build(BuildContext context) {
    final p = project;
    final sem = Sem.of(context);
    final cs = Theme.of(context).colorScheme;
    final adjusted = p.adjustedValue;
    final executed = p.executedValue ?? 0;
    final ratio = adjusted == null || adjusted <= 0 ? null : executed / adjusted;
    // الدفعة المقدمة المصروفة داخلة في المدفوع: ما استُرد منها لا يُعدّ استقطاعاً، وما لم يُسترد مدفوع مقدماً من أعمال لم تُنفَّذ.
    final advRec = p.advancePaid > 0 ? p.advanceRecovered : 0.0;
    final advRem = p.advancePaid > 0 ? p.advanceRemaining : 0.0;
    final otherDed = math.max(0.0, p.extractsGross - p.extractsNet - p.retentionHeld - advRec);

    Widget stat(String label, String value, {String? sub, Color? color, IconData? icon, String? badge}) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(color: sem.surface2, borderRadius: BorderRadius.circular((appearance.radius * 0.7).clamp(6, 16))),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(children: [
                if (icon != null) ...[Icon(icon, size: 15, color: color ?? sem.muted), const SizedBox(width: 5)],
                Expanded(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: sem.muted, fontSize: 12))),
                if (badge != null) ToneBadge(badge, color: cs.primary),
              ]),
              const SizedBox(height: 3),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: AlignmentDirectional.centerStart,
                child: Text(value, style: _tabular.copyWith(fontWeight: FontWeight.w800, fontSize: 16.5, color: color)),
              ),
              if (sub != null) Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: sem.muted, fontSize: 11)),
            ],
          ),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ResponsiveGrid(minItemWidth: 170, spacing: 8, children: [
          stat('القيمة التعاقدية', money(p.contractValue),
              icon: Icons.description_outlined, badge: p.valueFromItems ? 'من البنود' : null),
          stat('صافي أوامر التغيير', money(p.variationsNet),
              icon: Icons.swap_vert_rounded, color: p.variationsNet < 0 ? sem.danger : (p.variationsNet > 0 ? sem.ok : null)),
          stat('القيمة بعد التغيير', money(adjusted), icon: Icons.functions_rounded, color: cs.primary),
          stat('قيمة الأعمال المنفذة', money(p.executedValue),
              icon: Icons.construction_outlined,
              sub: ratio == null ? null : 'نسبة التنفيذ ${pctText(ratio, digits: 1)}',
              badge: switch (p.executedSource) { 'extracts' => 'من المستخلصات', 'items' => 'من البنود', _ => null }),
          stat('المستخلصات المعتمدة', money(p.extractsGross), icon: Icons.receipt_long_outlined, sub: '${p.extractsCount} مستخلص · الصافي ${compactMoney(p.extractsNet)}'),
          stat('المدفوع', money(p.paidTotal),
              icon: Icons.payments_outlined, color: sem.ok, sub: p.paidRatio == null ? null : '${pctText(p.paidRatio!, digits: 1)} من القيمة'),
          stat('مستحق غير مدفوع', money(p.outstanding), icon: Icons.pending_actions_outlined, color: p.outstanding > 0 ? sem.wip : null),
          stat('المتبقي من الأعمال', money(p.remainingWork), icon: Icons.hourglass_bottom_rounded,
              color: (p.remainingWork ?? 0) < 0 ? sem.danger : null),
          stat('المتبقي للدفع', money(p.remainingToPay), icon: Icons.account_balance_wallet_outlined),
          stat('التأمين المحتجز', money(p.retentionHeld), icon: Icons.lock_outline_rounded),
          if ((p.advanceAmount ?? 0) > 0)
            stat('الدفعة المقدمة', money(p.advanceAmount),
                icon: Icons.savings_outlined,
                badge: p.advancePaidOn == null ? 'لم تُصرف' : null,
                sub: 'استُرد ${compactMoney(p.advanceRecovered)} · المتبقي ${compactMoney(p.advanceRemaining)}'),
          stat('الضمان الابتدائي ${rateText(guaranteeInitialRate)}', p.guaranteeInitialNa ? 'لا ينطبق' : money(p.guaranteeInitial),
              icon: Icons.verified_outlined, color: p.guaranteeInitialNa ? sem.muted : null),
          stat('الضمان النهائي ${rateText(guaranteeFinalRate)}', money(p.guaranteeFinal), icon: Icons.verified_user_outlined),
        ]),
        if ((adjusted ?? 0) > 0) ...[
          const SizedBox(height: 14),
          Text('تكوين قيمة العقد', style: TextStyle(color: sem.muted, fontSize: 12.5, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          StackBar(parts: [
            ('مدفوع', p.paidTotal, sem.ok),
            ('مستحق', p.outstanding, sem.wip),
            ('تأمين محتجز', p.retentionHeld, cs.primary),
            ('استقطاعات أخرى', otherDed, sem.danger),
            ('لم يُنفَّذ', math.max(0.0, (p.remainingWork ?? 0) - advRem), sem.todo),
          ]),
        ],
      ],
    );
  }
}

/// نافذة قيم البند: قيمته التعاقدية والمنفذ منه.
Future<bool> showWorkValuesDialog(BuildContext context, AppState app, Project p, ContractWork w) async {
  final ok = await showDialog<bool>(context: context, builder: (_) => _WorkValuesDialog(app: app, project: p, work: w));
  return ok == true;
}

class _WorkValuesDialog extends StatefulWidget {
  const _WorkValuesDialog({required this.app, required this.project, required this.work});

  final AppState app;
  final Project project;
  final ContractWork work;

  @override
  State<_WorkValuesDialog> createState() => _WorkValuesDialogState();
}

class _WorkValuesDialogState extends State<_WorkValuesDialog> {
  late final _cv = TextEditingController(text: moneyInput(widget.work.contractValue));
  late final _ev = TextEditingController(text: moneyInput(widget.work.executedValue));
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _cv.dispose();
    _ev.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final c = parseMoney(_cv.text), e = parseMoney(_ev.text);
    if (!c.ok || !e.ok) {
      setState(() => _error = 'اكتب مبالغ صحيحة غير سالبة.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.app.setWorkValues(widget.work.id, contractValue: c.value, executedValue: e.value);
      if (mounted) Navigator.of(context).pop(true);
    } catch (err) {
      if (mounted) setState(() => _error = friendlyError(err));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sem = Sem.of(context);
    final c = parseMoney(_cv.text).value, e = parseMoney(_ev.text).value;
    final ratio = c == null || e == null || c <= 0 ? null : e / c;
    final others = widget.app.worksOf(widget.project.id).where((x) => x.id != widget.work.id);
    final othersTotal = others.fold<double>(0, (a, x) => a + (x.contractValue ?? 0));
    return AlertDialog(
      title: Text('قيم البند: ${widget.work.title.isEmpty ? widget.work.company : widget.work.title}'),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('عند إدخال قيمة أي بند تُحسب القيمة التعاقدية للعقد من مجموع البنود، ويُحسب المنفذ من البنود ما لم تُسجَّل مستخلصات معتمدة.',
                style: TextStyle(color: sem.muted, fontSize: 12.5, height: 1.5)),
            const SizedBox(height: 14),
            TextField(
              controller: _cv,
              autofocus: true,
              style: _tabular,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              onChanged: (_) => setState(() {}),
              decoration: fieldDeco('القيمة التعاقدية للبند').copyWith(suffixText: currencyLabel),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _ev,
              style: _tabular,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => _busy ? null : _save(),
              decoration: fieldDeco('المنفذ من البند').copyWith(suffixText: currencyLabel),
            ),
            const SizedBox(height: 12),
            if (ratio != null) ...[
              Row(children: [
                Text('نسبة تنفيذ البند', style: TextStyle(color: sem.muted, fontSize: 12.5)),
                const Spacer(),
                Text(pctText(ratio, digits: 1), style: _tabular.copyWith(fontWeight: FontWeight.w700)),
              ]),
              const SizedBox(height: 6),
              AnimatedMeter(value: ratio.clamp(0, 1).toDouble(), color: ratio > 1 ? sem.danger : sem.ok),
              const SizedBox(height: 8),
            ],
            Text('قيمة العقد بعد الحفظ: ${money(roundMoney(othersTotal + (c ?? 0)))}',
                style: TextStyle(color: sem.muted, fontSize: 12.5)),
            if (_error != null) ...[const SizedBox(height: 10), InfoBanner(text: _error!, level: 'critical')],
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.of(context).pop(false), child: const Text('إلغاء')),
        FilledButton(onPressed: _busy ? null : _save, child: const Text('حفظ القيم')),
      ],
    );
  }
}

/// أوامر التغيير في صفحة العقد.
class VariationsCard extends StatelessWidget {
  const VariationsCard({super.key, required this.app, required this.project, this.originLabel, this.onChanged});

  final AppState app;
  final Project project;
  final String? Function(String? originId)? originLabel;
  final VoidCallback? onChanged;

  Future<void> _edit(BuildContext context, ContractVariation? v) async {
    final ok = await showDialog<bool>(context: context, builder: (_) => VariationDialog(app: app, project: project, variation: v));
    if (ok == true && context.mounted) {
      showToast(context, v == null ? 'سُجّل أمر التغيير' : 'حُفظ أمر التغيير');
      onChanged?.call();
    }
  }

  Future<void> _delete(BuildContext context, ContractVariation v) async {
    final ok = await confirmDialog(context,
        title: 'حذف أمر التغيير؟',
        message: 'يُحذف «${v.title}» (${v.isAdd ? 'زيادة' : 'نقص'} ${money(v.amount)}) وتُعاد حسابات العقد. يبقى الأثر في السجل المالي.',
        confirmLabel: 'حذف',
        danger: true);
    if (!ok) return;
    try {
      await app.deleteVariation(v.id);
      if (context.mounted) showToast(context, 'حُذف أمر التغيير');
      onChanged?.call();
    } catch (e) {
      if (context.mounted) showToast(context, friendlyError(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sem = Sem.of(context);
    final list = app.variationsOf(project.id);
    final can = app.canEditFinanceItems(project);
    final adds = list.where((v) => v.isAdd).fold<double>(0, (a, v) => a + v.amount);
    final deducts = list.where((v) => !v.isAdd).fold<double>(0, (a, v) => a + v.amount);
    final base = project.contractValue ?? 0;
    return SectionCard(
      title: 'أوامر التغيير',
      icon: Icons.swap_vert_rounded,
      subtitle: 'الزيادة والنقص المعتمدان على قيمة العقد، برقم الأمر وتاريخ اعتماده. التغييرات المعتمدة في «سجل التغييرات» تظهر هنا تلقائياً.',
      trailing: can
          ? IconButton.filledTonal(tooltip: 'أمر تغيير جديد', onPressed: () => _edit(context, null), icon: const Icon(Icons.add_rounded))
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (list.isEmpty)
            Text('لا توجد أوامر تغيير على هذا العقد.', style: TextStyle(color: sem.muted))
          else ...[
            ...staggered([
              for (final v in list)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Material(
                    color: sem.surface2,
                    borderRadius: BorderRadius.circular(12),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: can && app.changeOfVariation(v.id) == null ? () => _edit(context, v) : null,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(10, 10, 4, 10),
                        child: Row(children: [
                          Container(
                            width: 32,
                            height: 32,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(color: (v.isAdd ? sem.ok : sem.danger).withValues(alpha: 0.14), shape: BoxShape.circle),
                            child: Icon(v.isAdd ? Icons.add_rounded : Icons.remove_rounded, color: v.isAdd ? sem.ok : sem.danger, size: 20),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(v.title, style: const TextStyle(fontWeight: FontWeight.w700)),
                              Text(
                                [
                                  if (v.refNo.isNotEmpty) 'رقم ${v.refNo}',
                                  if (v.approvedOn != null) 'اعتُمد ${dayText(v.approvedOn)}',
                                  if (app.work(v.workId) != null) 'البند: ${app.work(v.workId)!.title}',
                                  if (v.merged) 'مدمج من ${originLabel?.call(v.originProject) ?? 'عقد آخر'}',
                                  if (app.changeOfVariation(v.id) != null) 'من سجل التغييرات ${app.changeOfVariation(v.id)!.code} (يُعدَّل من هناك)',
                                ].join(' · '),
                                style: TextStyle(color: sem.muted, fontSize: 12),
                              ),
                            ]),
                          ),
                          Text('${v.isAdd ? '+' : '−'}${fmtMoney(v.amount)}',
                              style: _tabular.copyWith(fontWeight: FontWeight.w800, color: v.isAdd ? sem.ok : sem.danger)),
                          if (can && !v.merged && app.changeOfVariation(v.id) == null)
                            IconButton(tooltip: 'حذف', icon: const Icon(Icons.close_rounded, size: 18), onPressed: () => _delete(context, v))
                          else
                            const SizedBox(width: 10),
                        ]),
                      ),
                    ),
                  ),
                ),
            ], stepMs: 40),
            Divider(height: 20, color: sem.rule),
            Wrap(spacing: 18, runSpacing: 6, children: [
              _pair(context, 'إجمالي الزيادة', '+${fmtMoney(adds)}', sem.ok),
              _pair(context, 'إجمالي النقص', '−${fmtMoney(deducts)}', sem.danger),
              _pair(context, 'الصافي', fmtMoney(adds - deducts), null),
              if (base > 0) _pair(context, 'نسبته من القيمة', pctText((adds - deducts) / base, digits: 1), null),
            ]),
          ],
        ],
      ),
    );
  }
}

Widget _pair(BuildContext context, String label, String value, Color? color) {
  final sem = Sem.of(context);
  return Row(mainAxisSize: MainAxisSize.min, children: [
    Text('$label: ', style: TextStyle(color: sem.muted, fontSize: 12.5)),
    Text(value, style: _tabular.copyWith(fontWeight: FontWeight.w800, color: color)),
  ]);
}

Future<DateTime?> pickDay(BuildContext context, DateTime? initial) => showDatePicker(
      context: context,
      initialDate: initial ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      locale: const Locale('ar'),
    );

/// حقل تاريخ بزر اختيار ومسح.
class DayField extends StatelessWidget {
  const DayField({super.key, required this.label, required this.value, required this.onChanged, this.enabled = true});

  final String label;
  final DateTime? value;
  final ValueChanged<DateTime?> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: !enabled
          ? null
          : () async {
              final d = await pickDay(context, value);
              if (d != null) onChanged(d);
            },
      child: InputDecorator(
        decoration: fieldDeco(label,
            prefixIcon: const Icon(Icons.event_outlined, size: 20),
            suffix: value == null || !enabled
                ? null
                : IconButton(tooltip: 'مسح', icon: const Icon(Icons.close_rounded, size: 18), onPressed: () => onChanged(null))),
        child: Text(value == null ? '—' : dayText(value), style: _tabular),
      ),
    );
  }
}

/// نافذة أمر التغيير.
class VariationDialog extends StatefulWidget {
  const VariationDialog({super.key, required this.app, required this.project, this.variation});

  final AppState app;
  final Project project;
  final ContractVariation? variation;

  @override
  State<VariationDialog> createState() => _VariationDialogState();
}

class _VariationDialogState extends State<VariationDialog> {
  late final _ref = TextEditingController(text: widget.variation?.refNo ?? '');
  late final _title = TextEditingController(text: widget.variation?.title ?? '');
  late final _amount = TextEditingController(text: moneyInput(widget.variation?.amount));
  late final _notes = TextEditingController(text: widget.variation?.notes ?? '');
  late String _kind = widget.variation?.kind ?? 'add';
  late DateTime? _approved = widget.variation?.approvedOn ?? DateTime.now();
  late String? _work = widget.variation?.workId;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _ref.dispose();
    _title.dispose();
    _amount.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final a = parseMoney(_amount.text);
    if (_title.text.trim().length < 2) {
      setState(() => _error = 'اكتب وصف أمر التغيير.');
      return;
    }
    if (!a.ok || (a.value ?? 0) <= 0) {
      setState(() => _error = 'اكتب قيمة أمر التغيير (أكبر من صفر).');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.app.saveVariation(
        id: widget.variation?.id,
        projectId: widget.project.id,
        workId: _work,
        refNo: _ref.text,
        title: _title.text,
        kind: _kind,
        amount: a.value!,
        approvedOn: _approved,
        notes: _notes.text,
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sem = Sem.of(context);
    final works = widget.app.worksOf(widget.project.id);
    final a = parseMoney(_amount.text).value ?? 0;
    final net = widget.project.variationsNet - (widget.variation?.signed ?? 0) + (_kind == 'add' ? a : -a);
    return AlertDialog(
      title: Text(widget.variation == null ? 'أمر تغيير جديد' : 'تعديل أمر التغيير'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'add', label: Text('زيادة'), icon: Icon(Icons.add_rounded)),
                  ButtonSegment(value: 'deduct', label: Text('نقص'), icon: Icon(Icons.remove_rounded)),
                ],
                selected: {_kind},
                onSelectionChanged: (s) => setState(() => _kind = s.first),
              ),
              const SizedBox(height: 12),
              TextField(controller: _title, autofocus: widget.variation == null, decoration: fieldDeco('وصف أمر التغيير')),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(
                  child: TextField(
                    controller: _amount,
                    style: _tabular,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    onChanged: (_) => setState(() {}),
                    decoration: fieldDeco('القيمة').copyWith(suffixText: currencyLabel),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(child: TextField(controller: _ref, textDirection: TextDirection.ltr, decoration: fieldDeco('رقم الأمر'))),
              ]),
              const SizedBox(height: 10),
              DayField(label: 'تاريخ الاعتماد', value: _approved, onChanged: (d) => setState(() => _approved = d)),
              if (works.length > 1) ...[
                const SizedBox(height: 10),
                SelectField(
                  label: 'البند (اختياري)',
                  value: _work ?? '',
                  items: [('', 'العقد كله'), for (final w in works) (w.id, w.title.isEmpty ? w.company : w.title)],
                  onChanged: (v) => setState(() => _work = v.isEmpty ? null : v),
                ),
              ],
              const SizedBox(height: 10),
              TextField(controller: _notes, maxLines: 2, decoration: fieldDeco('ملاحظات')),
              const SizedBox(height: 10),
              Text('صافي أوامر التغيير بعد الحفظ: ${money(roundMoney(net))}', style: TextStyle(color: sem.muted, fontSize: 12.5)),
              if (_error != null) ...[const SizedBox(height: 10), InfoBanner(text: _error!, level: 'critical')],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.of(context).pop(false), child: const Text('إلغاء')),
        FilledButton(onPressed: _busy ? null : _save, child: const Text('حفظ')),
      ],
    );
  }
}

Color extractStatusColor(BuildContext context, String status) {
  final sem = Sem.of(context);
  final dark = Theme.of(context).brightness == Brightness.dark;
  return switch (status) {
    'paid' => sem.ok,
    'referred' => dark ? const Color(0xFFB39DFF) : const Color(0xFF6A4FC7),
    'approved' => Theme.of(context).colorScheme.primary,
    'submitted' => sem.wip,
    'rejected' => sem.danger,
    _ => sem.muted,
  };
}

/// اسم الاستقطاع المخصص بمفتاحه (من الإعدادات، أو المفتاح نفسه إن حُذف النوع).
String deductionLabel(AppState app, String key) {
  for (final t in app.settings.deductionTypes) {
    if (t.key == key) return t.label;
  }
  return key;
}

/// يعيد حفظ المستخلص بقيمه كما هي مع تغيير الحالة أو بيانات الإحالة والدفع فقط.
Future<void> resaveExtract(
  AppState app,
  ContractExtract x, {
  String? status,
  DateTime? approvedOn,
  DateTime? referredOn,
  String? referralNo,
  double? paidAmount,
  DateTime? paidOn,
}) =>
    app.saveExtract(
      id: x.id,
      projectId: x.projectId,
      workId: x.workId,
      refNo: x.refNo,
      kind: x.kind,
      periodFrom: x.periodFrom,
      periodTo: x.periodTo,
      submittedOn: x.submittedOn,
      gross: x.gross,
      retention: x.retention,
      advance: x.advanceRecovery,
      penalties: x.penalties,
      taxes: x.taxes,
      other: x.otherDeductions,
      status: status ?? x.status,
      approvedOn: approvedOn ?? x.approvedOn,
      paidAmount: paidAmount ?? x.paidAmount,
      paidOn: paidOn ?? x.paidOn,
      notes: x.notes,
      referredOn: referredOn ?? x.referredOn,
      referralNo: referralNo ?? x.referralNo,
      custom: x.customDeductions,
    );

/// سجل المستخلصات في صفحة العقد.
class ExtractsCard extends StatelessWidget {
  const ExtractsCard({super.key, required this.app, required this.project, this.originLabel, this.onChanged});

  final AppState app;
  final Project project;
  final String? Function(String? originId)? originLabel;
  final VoidCallback? onChanged;

  Future<void> _edit(BuildContext context, ContractExtract? x) async {
    final ok = await showDialog<bool>(context: context, builder: (_) => ExtractDialog(app: app, project: project, extract: x));
    if (ok == true && context.mounted) {
      showToast(context, x == null ? 'سُجّل المستخلص' : 'حُفظ المستخلص');
      onChanged?.call();
    }
  }

  Future<void> _delete(BuildContext context, ContractExtract x) async {
    final ok = await confirmDialog(context,
        title: 'حذف ${x.title}؟',
        message: 'يُحذف المستخلص (${money(x.gross)}) ودفعاته وتُعاد حسابات العقد. يبقى الأثر في السجل المالي.',
        confirmLabel: 'حذف',
        danger: true);
    if (!ok) return;
    try {
      await app.deleteExtract(x.id);
      if (context.mounted) showToast(context, 'حُذف المستخلص');
      onChanged?.call();
    } catch (e) {
      if (context.mounted) showToast(context, friendlyError(e), error: true);
    }
  }

  /// قاعدة ما قبل الإصدار الخامس: الدفع الكامل بتعديل المستخلص نفسه.
  Future<void> _markPaid(BuildContext context, ContractExtract x) async {
    try {
      await resaveExtract(app, x, status: 'paid', paidAmount: x.net, paidOn: DateTime.now());
      if (context.mounted) showToast(context, 'سُجّل دفع ${x.title} كاملاً');
      onChanged?.call();
    } catch (e) {
      if (context.mounted) showToast(context, friendlyError(e), error: true);
    }
  }

  Future<void> _refer(BuildContext context, ContractExtract x) async {
    final ok = await showDialog<bool>(context: context, builder: (_) => ReferralDialog(app: app, extract: x));
    if (ok == true && context.mounted) {
      showToast(context, 'أُحيل ${x.title} للصرف');
      onChanged?.call();
    }
  }

  Future<void> _pay(BuildContext context, ContractExtract x) async {
    final ok = await showDialog<bool>(context: context, builder: (_) => PaymentDialog(app: app, extract: x));
    if (ok == true && context.mounted) {
      showToast(context, 'سُجّلت الدفعة');
      onChanged?.call();
    }
  }

  Future<void> _deletePayment(BuildContext context, ContractExtract x, ExtractPayment pay) async {
    final ok = await confirmDialog(context,
        title: 'حذف الدفعة؟',
        message: 'تُحذف دفعة ${money(pay.amount)} (${dayText(pay.paidOn)}) من ${x.title} ويُعاد حساب المدفوع وحالته.',
        confirmLabel: 'حذف',
        danger: true);
    if (!ok) return;
    try {
      await app.deleteExtractPayment(pay.id);
      if (context.mounted) showToast(context, 'حُذفت الدفعة');
      onChanged?.call();
    } catch (e) {
      if (context.mounted) showToast(context, friendlyError(e), error: true);
    }
  }

  Future<void> _editAdvance(BuildContext context) async {
    final ok = await showDialog<bool>(context: context, builder: (_) => AdvanceDialog(app: app, project: project));
    if (ok == true && context.mounted) {
      showToast(context, 'حُفظت الدفعة المقدمة');
      onChanged?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    final sem = Sem.of(context);
    final cs = Theme.of(context).colorScheme;
    final list = app.extractsOf(project.id);
    final can = app.canEditFinanceItems(project);
    final counted = list.where((x) => x.counted).toList();
    final gross = counted.fold<double>(0, (a, x) => a + x.gross);
    final net = counted.fold<double>(0, (a, x) => a + x.net);
    final paid = counted.fold<double>(0, (a, x) => a + x.paidAmount);
    final ret = counted.fold<double>(0, (a, x) => a + x.retention);
    final referred = list.where((x) => x.isReferred).toList();
    final referredDue = referred.fold<double>(0, (a, x) => a + math.max(0.0, x.net - x.paidAmount));
    final pendingCount = list.where((x) => x.status == 'submitted' || x.status == 'draft').length;
    final showAdvance = app.v5Ready && ((project.advanceAmount ?? 0) > 0 || can);
    return SectionCard(
      title: 'المستخلصات',
      icon: Icons.receipt_long_outlined,
      subtitle: 'قيمة الأعمال في كل فترة، واستقطاعاتها، وصافيها، وإحالتها للصرف، ودفعاتها. المعتمد والمحال والمدفوع يدخل في المنفذ.',
      trailing: can
          ? IconButton.filledTonal(tooltip: 'مستخلص جديد', onPressed: () => _edit(context, null), icon: const Icon(Icons.add_rounded))
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (showAdvance) ...[
            _advanceStrip(context, can),
            const SizedBox(height: 12),
          ],
          if (list.isEmpty)
            Text('لم تُسجَّل مستخلصات لهذا العقد بعد.', style: TextStyle(color: sem.muted))
          else ...[
            Wrap(spacing: 18, runSpacing: 6, children: [
              _pair(context, 'المعتمد', '${counted.length} من ${list.length}', null),
              _pair(context, 'قيمة الأعمال', fmtMoney(gross), null),
              _pair(context, 'الصافي', fmtMoney(net), cs.primary),
              _pair(context, 'المدفوع', fmtMoney(paid), sem.ok),
              _pair(context, 'غير المدفوع', fmtMoney(math.max(0, net - paid)), net - paid > 0 ? sem.wip : null),
              if (referred.isNotEmpty)
                _pair(context, 'محال للصرف', '${referred.length} · ${fmtMoney(referredDue)}', extractStatusColor(context, 'referred')),
              _pair(context, 'التأمين المحتجز', fmtMoney(ret), null),
              if (pendingCount > 0) _pair(context, 'بانتظار الاعتماد', '$pendingCount', sem.wip),
            ]),
            if (counted.length >= 2) ...[
              const SizedBox(height: 14),
              TrendChart(
                height: 190,
                labels: [for (final x in counted) 'م${x.seq}'],
                series: [
                  ChartSeries('قيمة الأعمال', [for (final x in counted) x.gross]),
                  ChartSeries('الصافي', [for (final x in counted) x.net]),
                  ChartSeries('المدفوع', [for (final x in counted) x.paidAmount]),
                ],
              ),
            ],
            const SizedBox(height: 12),
            ...staggered([
              for (final x in list.reversed)
                Padding(padding: const EdgeInsets.only(bottom: 8), child: _tile(context, x, can)),
            ], stepMs: 40, maxSteps: 8),
          ],
        ],
      ),
    );
  }

  Widget _advanceStrip(BuildContext context, bool can) {
    final sem = Sem.of(context);
    final p = project;
    final amount = p.advanceAmount ?? 0;
    final ratio = amount <= 0 ? 0.0 : (p.advanceRecovered / amount).clamp(0, 1).toDouble();
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
      decoration: BoxDecoration(
        color: sem.surface2,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: sem.rule),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            Icon(Icons.savings_outlined, size: 18, color: sem.muted),
            const SizedBox(width: 8),
            Expanded(
              child: Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                const Text('الدفعة المقدمة', style: TextStyle(fontWeight: FontWeight.w700)),
                if (amount > 0)
                  ToneBadge(p.advancePaidOn == null ? 'لم تُصرف' : 'صُرفت ${dayText(p.advancePaidOn)}',
                      color: p.advancePaidOn == null ? sem.wip : sem.ok),
              ]),
            ),
            if (can)
              TextButton.icon(
                onPressed: () => _editAdvance(context),
                icon: Icon(amount > 0 ? Icons.edit_outlined : Icons.add_rounded, size: 18),
                label: Text(amount > 0 ? 'تعديل' : 'تسجيل'),
              ),
          ]),
          if (amount > 0) ...[
            const SizedBox(height: 6),
            Wrap(spacing: 18, runSpacing: 4, children: [
              _pair(context, 'القيمة', fmtMoney(amount), null),
              _pair(context, 'المسترد في المستخلصات', fmtMoney(p.advanceRecovered), sem.ok),
              _pair(context, 'المتبقي للاسترداد', fmtMoney(p.advanceRemaining), p.advanceRemaining > 0 ? sem.wip : null),
            ]),
            const SizedBox(height: 8),
            AnimatedMeter(value: ratio, color: sem.ok, height: 6),
          ] else
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('لا دفعة مقدمة لهذا العقد. إن وُجدت فسجّلها ليُقترح استردادها في كل مستخلص.',
                  style: TextStyle(color: sem.muted, fontSize: 12)),
            ),
        ],
      ),
    );
  }

  Widget _tile(BuildContext context, ContractExtract x, bool can) {
    final sem = Sem.of(context);
    final color = extractStatusColor(context, x.status);
    final editable = can && app.canEditExtract(project, x);
    final v5 = app.v5Ready;
    final payments = v5 ? app.paymentsOf(x.id) : const <ExtractPayment>[];
    final remaining = math.max(0.0, roundMoney(x.net - x.paidAmount));
    final payable = v5 && (x.status == 'approved' || x.status == 'referred') && remaining > 0;
    final period = [if (x.periodFrom != null) dayText(x.periodFrom), if (x.periodTo != null) dayText(x.periodTo)].join(' — ');
    final paidRatio = x.net <= 0 ? 0.0 : (x.paidAmount / x.net).clamp(0, 1).toDouble();
    final canDeletePayment = editable && (!x.isPaid || app.isDirector);
    return Material(
      color: sem.surface2,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: editable ? () => _edit(context, x) : null,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 4, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Container(
                  width: 36,
                  height: 36,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(10)),
                  child: Text(x.isFinal ? 'خ' : '${x.seq}', style: TextStyle(color: color, fontWeight: FontWeight.w800)),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Wrap(spacing: 6, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                      Text(x.title, style: const TextStyle(fontWeight: FontWeight.w700)),
                      ToneBadge(x.statusLabel, color: color),
                    ]),
                    const SizedBox(height: 2),
                    Text(
                      [
                        if (period.isNotEmpty) 'الفترة $period',
                        if (x.submittedOn != null) 'قُدّم ${dayText(x.submittedOn)}',
                        if (x.approvedOn != null && x.counted) 'اعتُمد ${dayText(x.approvedOn)}',
                        if (x.referredOn != null && (x.isReferred || x.isPaid))
                          'أُحيل للصرف ${dayText(x.referredOn)}${x.referralNo.isEmpty ? '' : ' (${x.referralNo})'}',
                        if (x.paidOn != null) 'دُفع ${dayText(x.paidOn)}',
                        if (app.work(x.workId) != null) 'البند: ${app.work(x.workId)!.title}',
                        if (x.merged) 'مدمج من ${originLabel?.call(x.originProject) ?? 'عقد آخر'}',
                      ].join(' · '),
                      style: TextStyle(color: sem.muted, fontSize: 12),
                    ),
                  ]),
                ),
                if (editable)
                  PopupMenuButton<String>(
                    tooltip: 'خيارات المستخلص',
                    onSelected: (v) {
                      switch (v) {
                        case 'edit':
                          _edit(context, x);
                        case 'refer':
                          _refer(context, x);
                        case 'payment':
                          _pay(context, x);
                        case 'pay':
                          _markPaid(context, x);
                        case 'delete':
                          _delete(context, x);
                      }
                    },
                    itemBuilder: (_) => [
                      const PopupMenuItem(value: 'edit', child: ListTile(leading: Icon(Icons.edit_outlined), title: Text('تعديل'))),
                      if (v5 && x.status == 'approved')
                        const PopupMenuItem(value: 'refer', child: ListTile(leading: Icon(Icons.forward_to_inbox_outlined), title: Text('إحالة للصرف'))),
                      if (payable)
                        const PopupMenuItem(value: 'payment', child: ListTile(leading: Icon(Icons.payments_outlined), title: Text('تسجيل دفعة'))),
                      if (!v5 && x.status == 'approved')
                        const PopupMenuItem(value: 'pay', child: ListTile(leading: Icon(Icons.payments_outlined), title: Text('تسجيل الدفع كاملاً'))),
                      if (!x.merged)
                        const PopupMenuItem(value: 'delete', child: ListTile(leading: Icon(Icons.delete_outline), title: Text('حذف'))),
                    ],
                  )
                else
                  const SizedBox(width: 10),
              ]),
              const SizedBox(height: 10),
              Wrap(spacing: 16, runSpacing: 4, children: [
                _pair(context, 'الأعمال', fmtMoney(x.gross), null),
                _pair(context, 'الاستقطاعات', fmtMoney(x.deductionsTotal), x.deductionsTotal > 0 ? sem.danger : null),
                _pair(context, 'الصافي', fmtMoney(x.net), Theme.of(context).colorScheme.primary),
                _pair(context, 'المدفوع', fmtMoney(x.paidAmount), x.paidAmount > 0 ? sem.ok : null),
                if (x.counted && remaining > 0) _pair(context, 'المتبقي', fmtMoney(remaining), sem.wip),
              ]),
              if (x.deductionsTotal > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    [
                      if (x.retention > 0) 'تأمين ${fmtMoney(x.retention)}',
                      if (x.advanceRecovery > 0) 'استرداد دفعة مقدمة ${fmtMoney(x.advanceRecovery)}',
                      if (x.penalties > 0) 'غرامات ${fmtMoney(x.penalties)}',
                      if (x.taxes > 0) 'ضرائب ورسوم ${fmtMoney(x.taxes)}',
                      for (final e in x.customDeductions.entries)
                        if (e.value > 0) '${deductionLabel(app, e.key)} ${fmtMoney(e.value)}',
                      if (x.otherDeductions > 0) 'أخرى ${fmtMoney(x.otherDeductions)}',
                    ].join(' · '),
                    style: TextStyle(color: sem.muted, fontSize: 11.5),
                  ),
                ),
              if (x.counted) ...[
                const SizedBox(height: 8),
                AnimatedMeter(value: paidRatio, color: sem.ok, height: 6),
              ],
              if (payments.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text('الدفعات (${payments.length})', style: TextStyle(color: sem.muted, fontSize: 12, fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                for (final pay in payments)
                  _paymentRow(context, x, pay, canDeletePayment),
              ],
              if (x.notes.isNotEmpty)
                Padding(padding: const EdgeInsets.only(top: 6), child: Text(x.notes, style: TextStyle(color: sem.muted, fontSize: 12))),
            ],
          ),
        ),
      ),
    );
  }

  Widget _paymentRow(BuildContext context, ContractExtract x, ExtractPayment pay, bool canDelete) {
    final sem = Sem.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(children: [
        Icon(Icons.check_circle_outline_rounded, size: 15, color: sem.ok),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            [
              dayText(pay.paidOn),
              pay.methodLabel,
              if (pay.refNo.isNotEmpty) 'مرجع ${pay.refNo}',
              if (pay.notes.isNotEmpty) pay.notes,
            ].join(' · '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: sem.muted, fontSize: 12),
          ),
        ),
        Text(fmtMoney(pay.amount), style: _tabular.copyWith(fontWeight: FontWeight.w700, fontSize: 12.5)),
        if (canDelete)
          IconButton(
            tooltip: 'حذف الدفعة',
            visualDensity: VisualDensity.compact,
            iconSize: 18,
            onPressed: () => _deletePayment(context, x, pay),
            icon: Icon(Icons.close_rounded, color: sem.muted),
          )
        else
          const SizedBox(width: 8),
      ]),
    );
  }
}

/// نافذة إحالة المستخلص المعتمد للصرف: تاريخ الإحالة ورقمها.
class ReferralDialog extends StatefulWidget {
  const ReferralDialog({super.key, required this.app, required this.extract});

  final AppState app;
  final ContractExtract extract;

  @override
  State<ReferralDialog> createState() => _ReferralDialogState();
}

class _ReferralDialogState extends State<ReferralDialog> {
  late DateTime? _on = widget.extract.referredOn ?? DateTime.now();
  late final _no = TextEditingController(text: widget.extract.referralNo);
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _no.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await resaveExtract(widget.app, widget.extract, status: 'referred', referredOn: _on ?? DateTime.now(), referralNo: _no.text.trim());
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final x = widget.extract;
    return AlertDialog(
      title: Text('إحالة ${x.title} للصرف'),
      content: SizedBox(
        width: 420,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('صافي المستخلص ${money(x.net)}', style: _tabular.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          DayField(label: 'تاريخ الإحالة', value: _on, onChanged: (d) => setState(() => _on = d)),
          const SizedBox(height: 10),
          TextField(
            controller: _no,
            maxLength: 60,
            textDirection: TextDirection.ltr,
            decoration: fieldDeco('رقم خطاب الإحالة أو أمر الصرف (اختياري)').copyWith(counterText: ''),
          ),
          if (_error != null) ...[const SizedBox(height: 6), InfoBanner(text: _error!, level: 'critical')],
        ]),
      ),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.of(context).pop(false), child: const Text('إلغاء')),
        FilledButton.icon(
          onPressed: _busy ? null : _save,
          icon: const Icon(Icons.forward_to_inbox_outlined, size: 18),
          label: const Text('إحالة'),
        ),
      ],
    );
  }
}

/// نافذة تسجيل دفعة على مستخلص (سجل الدفعات).
class PaymentDialog extends StatefulWidget {
  const PaymentDialog({super.key, required this.app, required this.extract});

  final AppState app;
  final ContractExtract extract;

  @override
  State<PaymentDialog> createState() => _PaymentDialogState();
}

class _PaymentDialogState extends State<PaymentDialog> {
  late final double _remaining = math.max(0.0, roundMoney(widget.extract.net - widget.extract.paidAmount));
  late final _amount = TextEditingController(text: moneyInput(_remaining));
  final _ref = TextEditingController();
  final _notes = TextEditingController();
  DateTime? _on = DateTime.now();
  String _method = 'transfer';
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _amount.dispose();
    _ref.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final a = parseMoney(_amount.text);
    if (!a.ok || (a.value ?? 0) <= 0) {
      setState(() => _error = 'اكتب مبلغاً صحيحاً أكبر من صفر.');
      return;
    }
    if (a.value! > _remaining + 0.0005) {
      setState(() => _error = 'المبلغ أكبر من المتبقي (${money(_remaining)}).');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.app.addExtractPayment(widget.extract.id,
          amount: a.value!, paidOn: _on ?? DateTime.now(), method: _method, refNo: _ref.text, notes: _notes.text);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sem = Sem.of(context);
    final x = widget.extract;
    final full = (parseMoney(_amount.text).value ?? 0) >= _remaining - 0.0005;
    return AlertDialog(
      title: Text('دفعة على ${x.title}'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Wrap(spacing: 18, runSpacing: 4, children: [
              _pair(context, 'الصافي', fmtMoney(x.net), null),
              _pair(context, 'المدفوع', fmtMoney(x.paidAmount), sem.ok),
              _pair(context, 'المتبقي', fmtMoney(_remaining), sem.wip),
            ]),
            const SizedBox(height: 14),
            TextField(
              controller: _amount,
              style: _tabular,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              onChanged: (_) => setState(() {}),
              decoration: fieldDeco('مبلغ الدفعة', helper: full ? 'تُغلق الدفعة المستخلص فيصبح «مدفوع»' : 'دفعة جزئية')
                  .copyWith(suffixText: currencyLabel),
            ),
            const SizedBox(height: 14),
            DayField(label: 'تاريخ الدفع', value: _on, onChanged: (d) => setState(() => _on = d)),
            const SizedBox(height: 10),
            Text('طريقة الدفع', style: TextStyle(color: sem.muted, fontSize: 12.5)),
            const SizedBox(height: 6),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final e in paymentMethodLabels.entries)
                ChoiceChip(label: Text(e.value), selected: _method == e.key, onSelected: (_) => setState(() => _method = e.key)),
            ]),
            const SizedBox(height: 10),
            TextField(
              controller: _ref,
              maxLength: 60,
              textDirection: TextDirection.ltr,
              decoration: fieldDeco('رقم الحوالة أو الصك (اختياري)').copyWith(counterText: ''),
            ),
            const SizedBox(height: 10),
            TextField(controller: _notes, maxLines: 2, decoration: fieldDeco('ملاحظات (اختياري)')),
            if (_error != null) ...[const SizedBox(height: 10), InfoBanner(text: _error!, level: 'critical')],
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.of(context).pop(false), child: const Text('إلغاء')),
        FilledButton(
          onPressed: _busy ? null : _save,
          child: _busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('تسجيل الدفعة'),
        ),
      ],
    );
  }
}

/// نافذة الدفعة المقدمة للعقد.
class AdvanceDialog extends StatefulWidget {
  const AdvanceDialog({super.key, required this.app, required this.project});

  final AppState app;
  final Project project;

  @override
  State<AdvanceDialog> createState() => _AdvanceDialogState();
}

class _AdvanceDialogState extends State<AdvanceDialog> {
  late final _amount = TextEditingController(text: moneyInput(widget.project.advanceAmount));
  late DateTime? _on = widget.project.advancePaidOn;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  Future<void> _save({bool remove = false}) async {
    final a = parseMoney(_amount.text);
    if (!remove && (!a.ok || (a.value ?? 0) <= 0)) {
      setState(() => _error = 'اكتب قيمة صحيحة أكبر من صفر.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.app.setContractAdvance(widget.project.id, amount: remove ? null : a.value, paidOn: remove ? null : _on);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sem = Sem.of(context);
    final p = widget.project;
    final cv = p.contractValue ?? 0;
    final a = parseMoney(_amount.text).value ?? 0;
    final rate = widget.app.settings.advanceRecoveryRate;
    return AlertDialog(
      title: const Text('الدفعة المقدمة'),
      content: SizedBox(
        width: 440,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          TextField(
            controller: _amount,
            style: _tabular,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (_) => setState(() {}),
            decoration: fieldDeco('قيمة الدفعة المقدمة',
                    helper: cv > 0 && a > 0 ? '${pctText(a / cv, digits: 1)} من القيمة التعاقدية' : null)
                .copyWith(suffixText: currencyLabel),
          ),
          if (cv > 0)
            Wrap(spacing: 6, children: [
              for (final pct in const [0.05, 0.10, 0.15, 0.20])
                ActionChip(
                  visualDensity: VisualDensity.compact,
                  label: Text('${(pct * 100).round()}%'),
                  onPressed: () => setState(() => _amount.text = moneyInput(roundMoney(cv * pct))),
                ),
            ]),
          const SizedBox(height: 10),
          DayField(label: 'تاريخ الصرف (فارغ إن لم تُصرف بعد)', value: _on, onChanged: (d) => setState(() => _on = d)),
          const SizedBox(height: 10),
          Text(
            rate > 0
                ? 'تُسترد بنسبة ${rateText(rate)} من قيمة أعمال كل مستخلص حتى تكتمل.'
                : 'تُسترد بنسبتها من القيمة التعاقدية في كل مستخلص حتى تكتمل (تُغيَّر النسبة من الإعدادات المالية).',
            style: TextStyle(color: sem.muted, fontSize: 12),
          ),
          if (p.advanceRecovered > 0)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('استُرد منها ${money(p.advanceRecovered)}؛ لا تقل القيمة عن ذلك.', style: TextStyle(color: sem.muted, fontSize: 12)),
            ),
          if (_error != null) ...[const SizedBox(height: 10), InfoBanner(text: _error!, level: 'critical')],
        ]),
      ),
      actions: [
        if ((p.advanceAmount ?? 0) > 0 && p.advanceRecovered == 0)
          TextButton(
            onPressed: _busy ? null : () => _save(remove: true),
            style: TextButton.styleFrom(foregroundColor: sem.danger),
            child: const Text('إزالة'),
          ),
        TextButton(onPressed: _busy ? null : () => Navigator.of(context).pop(false), child: const Text('إلغاء')),
        FilledButton(onPressed: _busy ? null : _save, child: const Text('حفظ')),
      ],
    );
  }
}

/// نافذة المستخلص: القيم والاستقطاعات تُحسب لحظياً، والنسب الافتراضية، والحالة والإحالة والدفع.
class ExtractDialog extends StatefulWidget {
  const ExtractDialog({super.key, required this.app, required this.project, this.extract});

  final AppState app;
  final Project project;
  final ContractExtract? extract;

  @override
  State<ExtractDialog> createState() => _ExtractDialogState();
}

class _ExtractDialogState extends State<ExtractDialog> {
  static const _baseKeys = ['gross', 'retention', 'advance', 'penalties', 'taxes', 'other', 'paid'];
  final Map<String, TextEditingController> _m = {};
  final Map<String, TextEditingController> _custom = {};
  late final List<(String, String, double?)> _customTypes;
  late final _ref = TextEditingController(text: widget.extract?.refNo ?? '');
  late final _notes = TextEditingController(text: widget.extract?.notes ?? '');
  late final _referralNo = TextEditingController(text: widget.extract?.referralNo ?? '');
  late String _kind = widget.extract?.kind ?? 'interim';
  late String _status = widget.extract?.status ?? 'submitted';
  late DateTime? _from = widget.extract?.periodFrom;
  late DateTime? _to = widget.extract?.periodTo;
  late DateTime? _submitted = widget.extract?.submittedOn ?? (widget.extract == null ? DateTime.now() : null);
  late DateTime? _approved = widget.extract?.approvedOn;
  late DateTime? _referred = widget.extract?.referredOn;
  late DateTime? _paidOn = widget.extract?.paidOn;
  late String? _work = widget.extract?.workId;
  // المستخلص الجديد تُطبَّق عليه النسب الافتراضية تلقائياً حتى يعدّل المستخدم استقطاعاً بنفسه.
  late bool _auto = widget.extract == null;
  bool _busy = false;
  String? _error;

  AppState get app => widget.app;
  LiveSettings get _settings => app.settings;
  List<ExtractPayment> get _ledger => widget.extract == null || !app.v5Ready ? const [] : app.paymentsOf(widget.extract!.id);
  bool get _hasLedger => _ledger.isNotEmpty;

  @override
  void initState() {
    super.initState();
    final x = widget.extract;
    final init = <String, double?>{
      'gross': x?.gross,
      'retention': x?.retention,
      'advance': x?.advanceRecovery,
      'penalties': x?.penalties,
      'taxes': x?.taxes,
      'other': x?.otherDeductions,
      'paid': x?.paidAmount,
    };
    for (final k in _baseKeys) {
      final v = init[k];
      _m[k] = TextEditingController(text: v == null || (v == 0 && k != 'gross') ? '' : moneyInput(v));
    }
    final types = <(String, String, double?)>[
      if (app.v5Ready)
        for (final t in _settings.deductionTypes) (t.key, t.label, t.rate),
    ];
    // استقطاعات مسجلة في المستخلص حُذف نوعها من الإعدادات: تبقى ظاهرة لتُعدَّل أو تُصفَّر.
    for (final k in (x?.customDeductions.keys ?? const <String>[])) {
      if (!types.any((t) => t.$1 == k)) types.add((k, k, null));
    }
    _customTypes = types;
    for (final t in _customTypes) {
      final v = x?.customDeductions[t.$1];
      _custom[t.$1] = TextEditingController(text: v == null || v == 0 ? '' : moneyInput(v));
    }
  }

  @override
  void dispose() {
    for (final c in [..._m.values, ..._custom.values]) {
      c.dispose();
    }
    _ref.dispose();
    _notes.dispose();
    _referralNo.dispose();
    super.dispose();
  }

  double _v(String k) => parseMoney(_m[k]!.text).value ?? 0;
  bool _ok(String k) => parseMoney(_m[k]!.text).ok;
  double _c(String k) => parseMoney(_custom[k]!.text).value ?? 0;
  bool _cok(String k) => parseMoney(_custom[k]!.text).ok;

  double get _customTotal => _customTypes.fold<double>(0, (a, t) => a + _c(t.$1));
  double get _deductions => _v('retention') + _v('advance') + _v('penalties') + _v('taxes') + _v('other') + _customTotal;
  double get _net => roundMoney(_v('gross') - _deductions);
  double get _ledgerSum => _ledger.fold<double>(0, (a, p) => a + p.amount);
  double get _paid => _hasLedger ? roundMoney(_ledgerSum) : _v('paid');

  String _fill(double v) => v <= 0 ? '' : moneyInput(roundMoney(v));

  /// النسب الافتراضية من الإعدادات المالية: التأمين، والضرائب، والاستقطاعات المخصصة، واسترداد الدفعة المقدمة.
  void _applyDefaults() {
    final g = _v('gross');
    _m['retention']!.text = _fill(g * _settings.retentionRate);
    if (_settings.taxRate > 0) _m['taxes']!.text = _fill(g * _settings.taxRate);
    for (final t in _customTypes) {
      if (t.$3 != null) _custom[t.$1]!.text = _fill(g * t.$3!);
    }
    if (app.v5Ready) {
      _m['advance']!.text = _fill(app.suggestedAdvanceRecovery(widget.project, g, excludeExtractId: widget.extract?.id));
    }
  }

  Future<void> _save() async {
    if (_baseKeys.any((k) => !_ok(k)) || _customTypes.any((t) => !_cok(t.$1))) {
      setState(() => _error = 'اكتب مبالغ صحيحة غير سالبة.');
      return;
    }
    if (_m['gross']!.text.trim().isEmpty) {
      setState(() => _error = 'اكتب قيمة الأعمال في المستخلص.');
      return;
    }
    if (_net < 0) {
      setState(() => _error = 'الاستقطاعات أكبر من قيمة الأعمال.');
      return;
    }
    if (_paid > _net + 0.0005) {
      setState(() => _error = _hasLedger ? 'مجموع الدفعات المسجلة أكبر من الصافي الجديد. احذف دفعة أولاً.' : 'المدفوع أكبر من صافي المستخلص.');
      return;
    }
    final payable = _status == 'approved' || _status == 'referred' || _status == 'paid';
    if (_paid > 0 && !payable) {
      setState(() => _error = 'لا يُسجَّل دفع إلا لمستخلص معتمد.');
      return;
    }
    if (_hasLedger && _status == 'paid' && _paid < _net - 0.0005) {
      setState(() => _error = 'المستخلص يصبح «مدفوع» حين تكتمل دفعاته. سجّل المتبقي من سجل الدفعات.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await app.saveExtract(
        id: widget.extract?.id,
        projectId: widget.project.id,
        workId: _work,
        refNo: _ref.text,
        kind: _kind,
        periodFrom: _from,
        periodTo: _to,
        submittedOn: _submitted,
        gross: _v('gross'),
        retention: _v('retention'),
        advance: _v('advance'),
        penalties: _v('penalties'),
        taxes: _v('taxes'),
        other: _v('other'),
        status: _status,
        approvedOn: _approved,
        paidAmount: _paid,
        paidOn: _paidOn,
        notes: _notes.text,
        referredOn: _status == 'referred' || _status == 'paid' ? _referred : null,
        referralNo: _status == 'referred' || _status == 'paid' ? _referralNo.text : '',
        custom: {for (final t in _customTypes) t.$1: _c(t.$1)},
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _money(String k, String label, {String? helper, bool deduction = true}) => TextField(
        controller: _m[k],
        style: _tabular,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        onChanged: (_) => setState(() {
          if (k == 'gross' && _auto) _applyDefaults();
          if (k != 'gross' && deduction) _auto = false;
        }),
        decoration: fieldDeco(label, helper: helper, error: _ok(k) ? null : 'مبلغ غير صحيح').copyWith(suffixText: currencyLabel),
      );

  Widget _customField((String, String, double?) t) => TextField(
        controller: _custom[t.$1],
        style: _tabular,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        onChanged: (_) => setState(() => _auto = false),
        decoration: fieldDeco(t.$2,
                helper: t.$3 == null ? null : 'النسبة الافتراضية ${rateText(t.$3!)}', error: _cok(t.$1) ? null : 'مبلغ غير صحيح')
            .copyWith(suffixText: currencyLabel),
      );

  @override
  Widget build(BuildContext context) {
    final sem = Sem.of(context);
    final cs = Theme.of(context).colorScheme;
    final works = app.worksOf(widget.project.id);
    final x = widget.extract;
    final wide = MediaQuery.sizeOf(context).width >= 700;
    Widget pair(Widget a, Widget b) => wide
        ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(child: a), const SizedBox(width: 10), Expanded(child: b)])
        : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [a, const SizedBox(height: 10), b]);
    final payable = _status == 'approved' || _status == 'referred' || _status == 'paid';
    final statuses = [for (final s in extractStatuses) if (s != 'referred' || app.v5Ready || _status == 'referred') s];
    final retRate = _settings.retentionRate;
    final retChips = <double>{retRate, 0.05, 0.10}.where((r) => r > 0).toList()..sort();
    final advSuggest = app.v5Ready ? app.suggestedAdvanceRecovery(widget.project, _v('gross'), excludeExtractId: x?.id) : 0.0;
    final hasAdvance = (widget.project.advanceAmount ?? 0) > 0;
    final customPairs = <Widget>[];
    for (var i = 0; i < _customTypes.length; i += 2) {
      customPairs.add(Padding(
        padding: const EdgeInsets.only(top: 10),
        child: i + 1 < _customTypes.length
            ? pair(_customField(_customTypes[i]), _customField(_customTypes[i + 1]))
            : _customField(_customTypes[i]),
      ));
    }
    return AlertDialog(
      title: Text(x == null ? 'مستخلص جديد' : 'تعديل ${x.title}'),
      content: SizedBox(
        width: 640,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              pair(
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'interim', label: Text('جاري')),
                    ButtonSegment(value: 'final', label: Text('ختامي')),
                  ],
                  selected: {_kind},
                  onSelectionChanged: (s) => setState(() => _kind = s.first),
                ),
                TextField(controller: _ref, textDirection: TextDirection.ltr, decoration: fieldDeco('رقم المستخلص لدى الجهة (اختياري)')),
              ),
              const SizedBox(height: 10),
              pair(
                DayField(label: 'بداية الفترة', value: _from, onChanged: (d) => setState(() => _from = d)),
                DayField(label: 'نهاية الفترة', value: _to, onChanged: (d) => setState(() => _to = d)),
              ),
              const SizedBox(height: 10),
              pair(
                DayField(label: 'تاريخ التقديم', value: _submitted, onChanged: (d) => setState(() => _submitted = d)),
                works.length > 1
                    ? SelectField(
                        label: 'البند (اختياري)',
                        value: _work ?? '',
                        items: [('', 'العقد كله'), for (final w in works) (w.id, w.title.isEmpty ? w.company : w.title)],
                        onChanged: (v) => setState(() => _work = v.isEmpty ? null : v),
                      )
                    : const SizedBox.shrink(),
              ),
              const SizedBox(height: 16),
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                children: [
                  Text('القيم والاستقطاعات', style: TextStyle(fontWeight: FontWeight.w700, color: cs.primary)),
                  TextButton.icon(
                    onPressed: _v('gross') <= 0 ? null : () => setState(_applyDefaults),
                    icon: const Icon(Icons.auto_fix_high_outlined, size: 18),
                    label: const Text('تطبيق النسب الافتراضية'),
                  ),
                ],
              ),
              if (_auto)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text('تُحسب الاستقطاعات تلقائياً من النسب الافتراضية حتى تعدّل أحدها بنفسك.',
                      style: TextStyle(color: sem.muted, fontSize: 11.5)),
                ),
              const SizedBox(height: 4),
              _money('gross', 'قيمة الأعمال المنفذة في المستخلص', deduction: false),
              const SizedBox(height: 10),
              pair(
                Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  _money('retention', 'التأمين المحتجز'),
                  Wrap(spacing: 6, children: [
                    for (final pct in retChips)
                      ActionChip(
                        visualDensity: VisualDensity.compact,
                        label: Text('${rateText(pct)}${pct == retRate ? ' (الافتراضي)' : ''}'),
                        onPressed: () => setState(() {
                          _auto = false;
                          _m['retention']!.text = _fill(_v('gross') * pct);
                        }),
                      ),
                  ]),
                ]),
                Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  _money('advance', 'استرداد الدفعة المقدمة',
                      helper: hasAdvance ? 'المتبقي من الدفعة ${money(widget.project.advanceRemaining)}' : null),
                  if (advSuggest > 0 && (advSuggest - _v('advance')).abs() > 0.0005)
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: ActionChip(
                        visualDensity: VisualDensity.compact,
                        avatar: const Icon(Icons.lightbulb_outline_rounded, size: 16),
                        label: Text('المقترح ${fmtMoney(advSuggest)}'),
                        onPressed: () => setState(() {
                          _auto = false;
                          _m['advance']!.text = _fill(advSuggest);
                        }),
                      ),
                    ),
                ]),
              ),
              const SizedBox(height: 10),
              pair(
                _money('penalties', 'الغرامات وغرامات التأخير'),
                _money('taxes', 'الضرائب والرسوم', helper: _settings.taxRate > 0 ? 'النسبة الافتراضية ${rateText(_settings.taxRate)}' : null),
              ),
              ...customPairs,
              const SizedBox(height: 10),
              _money('other', 'استقطاعات أخرى'),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: sem.surface2, borderRadius: BorderRadius.circular(12)),
                child: Column(children: [
                  Row(children: [
                    Text('إجمالي الاستقطاعات', style: TextStyle(color: sem.muted)),
                    const Spacer(),
                    Text(money(roundMoney(_deductions)), style: _tabular.copyWith(fontWeight: FontWeight.w700, color: sem.danger)),
                  ]),
                  const SizedBox(height: 4),
                  Row(children: [
                    const Text('صافي المستخلص', style: TextStyle(fontWeight: FontWeight.w700)),
                    const Spacer(),
                    Text(money(_net), style: _tabular.copyWith(fontWeight: FontWeight.w800, fontSize: 16, color: _net < 0 ? sem.danger : cs.primary)),
                  ]),
                ]),
              ),
              const SizedBox(height: 16),
              Text('الحالة والإحالة والدفع', style: TextStyle(fontWeight: FontWeight.w700, color: cs.primary)),
              const SizedBox(height: 8),
              Wrap(spacing: 6, runSpacing: 6, children: [
                for (final s in statuses)
                  ChoiceChip(
                    label: Text(extractStatusLabels[s]!),
                    selected: _status == s,
                    selectedColor: extractStatusColor(context, s).withValues(alpha: 0.2),
                    onSelected: (_) => setState(() {
                      _status = s;
                      final pay = s == 'approved' || s == 'referred' || s == 'paid';
                      if (pay && _approved == null) _approved = DateTime.now();
                      if (s == 'referred' || s == 'paid') _referred ??= s == 'referred' ? DateTime.now() : null;
                      if (s == 'paid' && !_hasLedger) {
                        if (_v('paid') == 0) _m['paid']!.text = moneyInput(_net);
                        _paidOn ??= DateTime.now();
                      }
                      if (!pay && !_hasLedger) {
                        _m['paid']!.text = '';
                        _paidOn = null;
                      }
                    }),
                  ),
              ]),
              if (payable) ...[
                const SizedBox(height: 10),
                pair(
                  DayField(label: 'تاريخ الاعتماد', value: _approved, onChanged: (d) => setState(() => _approved = d)),
                  _status == 'referred' || _status == 'paid'
                      ? DayField(label: 'تاريخ الإحالة للصرف', value: _referred, onChanged: (d) => setState(() => _referred = d))
                      : const SizedBox.shrink(),
                ),
                if (_status == 'referred' || _status == 'paid') ...[
                  const SizedBox(height: 10),
                  TextField(
                    controller: _referralNo,
                    maxLength: 60,
                    textDirection: TextDirection.ltr,
                    decoration: fieldDeco('رقم خطاب الإحالة أو أمر الصرف (اختياري)').copyWith(counterText: ''),
                  ),
                ],
                const SizedBox(height: 10),
                if (_hasLedger)
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(border: Border.all(color: sem.rule), borderRadius: BorderRadius.circular(12)),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      Row(children: [
                        Icon(Icons.receipt_outlined, size: 18, color: sem.muted),
                        const SizedBox(width: 6),
                        Text('المدفوع من سجل الدفعات (${_ledger.length})', style: TextStyle(color: sem.muted)),
                        const Spacer(),
                        Text(money(_paid), style: _tabular.copyWith(fontWeight: FontWeight.w700, color: sem.ok)),
                      ]),
                      const SizedBox(height: 4),
                      Text('يُدار المدفوع من سجل الدفعات في بطاقة المستخلص (تسجيل دفعة أو حذفها).',
                          style: TextStyle(color: sem.muted, fontSize: 11.5)),
                    ]),
                  )
                else
                  pair(
                    Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      _money('paid', 'المدفوع', helper: 'الصافي المستحق ${money(_net)}', deduction: false),
                      Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: TextButton.icon(
                          onPressed: () => setState(() {
                            _m['paid']!.text = moneyInput(_net);
                            _paidOn ??= DateTime.now();
                          }),
                          icon: const Icon(Icons.done_all_rounded, size: 18),
                          label: const Text('دفع الصافي كاملاً'),
                        ),
                      ),
                    ]),
                    DayField(label: 'تاريخ الدفع', value: _paidOn, onChanged: (d) => setState(() => _paidOn = d)),
                  ),
                if (app.v5Ready && !_hasLedger)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text('للدفعات الجزئية بتواريخها وأرقامها استخدم «تسجيل دفعة» من قائمة المستخلص بعد حفظه.',
                        style: TextStyle(color: sem.muted, fontSize: 11.5)),
                  ),
              ],
              const SizedBox(height: 10),
              TextField(controller: _notes, maxLines: 2, decoration: fieldDeco('ملاحظات')),
              if (x != null && x.isPaid && !app.isDirector)
                const Padding(padding: EdgeInsets.only(top: 10), child: InfoBanner(text: 'المستخلص المدفوع يعدّله مدير المكتب وحده.', level: 'warning')),
              if (_error != null) ...[const SizedBox(height: 10), InfoBanner(text: _error!, level: 'critical')],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.of(context).pop(false), child: const Text('إلغاء')),
        FilledButton(
          onPressed: _busy ? null : _save,
          child: _busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('حفظ المستخلص'),
        ),
      ],
    );
  }
}
