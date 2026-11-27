import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../app_state.dart';
import '../models.dart' show dayText;
import '../registers.dart' show isoDay;
import '../stocktaking.dart';
import '../stores.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';
import 'contract_finance.dart' show DayField;
import 'pm_common.dart' show PmTable;
import 'stores.dart' show storesRun;
import 'stores_docs.dart' show openStoreDoc;
import 'stores_setup.dart' show storeFormDialog;

// =====================================================================
// الجرد الدوري (الإصدار 1.11.0، الترحيل 42): قائمة الجلسات، وصفحة الجلسة (عدّ ← تقديم ← قرار)، وبدء جلسة.
// الفرق عند الاعتماد = المعدود − الرصيد الفعلي وقتها، وتتولّد تسوية معتمدة بالفروق وحدها تُرحَّل كسائر المستندات.
// =====================================================================

const _tabular = TextStyle(fontFeatures: [ui.FontFeature.tabularFigures()]);

/// لون حالة الجلسة.
Color stCountStatusColor(Sem sem, String s) => switch (s) {
      'open' => sem.wip,
      'submitted' => sem.na,
      'closed' => sem.ok,
      _ => sem.muted,
    };

Widget _gap(Widget w) => Padding(padding: const EdgeInsets.only(bottom: 12), child: w);

/// يفتح صفحة جلسة جرد.
void openStoreCount(BuildContext context, String id) {
  Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => StocktakeDetailPage(countId: id)));
}

/// نص نطاق الجلسة: المخزن وتصنيفها إن حُصرت.
String stCountScope(StoresData s, StCount c) {
  final cat = c.categoryId == null ? '' : s.category(c.categoryId)?.name ?? '';
  return cat.isEmpty ? s.warehouseName(c.warehouseId) : '${s.warehouseName(c.warehouseId)} · $cat';
}

/// حوار بدء جلسة؛ المخازن المعروضة ما يحرّكه المستخدم ولا جلسة قائمة عليه.
Future<void> startStocktakeDialog(BuildContext context) async {
  final app = AppScope.read(context);
  final s = app.stores;
  final free = [for (final w in app.storesMovableWarehouses) if (app.stocktake.liveOf(w.id) == null) w];
  if (free.isEmpty) {
    showToast(context, 'لا مخزن متاح لجلسة جديدة: لكل مخزن جلسة قائمة واحدة، أو لا تملك حركته.', error: true);
    return;
  }
  var wh = free.first.id;
  var cat = '';
  var blind = true;
  final note = TextEditingController();
  String? newId;
  await storeFormDialog(
    context,
    title: 'جلسة جرد جديدة',
    body: (setLocal) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SelectField(label: 'المخزن', value: wh, items: [for (final w in free) (w.id, w.name)], onChanged: (v) => setLocal(() => wh = v)),
      const SizedBox(height: 12),
      SelectField(
        label: 'التصنيف',
        value: cat,
        items: [('', 'كل الأصناف التي بها رصيد'), for (final c in s.categories) (c.id, c.name)],
        onChanged: (v) => setLocal(() => cat = v),
      ),
      const SizedBox(height: 4),
      Material(
        type: MaterialType.transparency,
        child: SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('إخفاء الرصيد الدفتري أثناء العدّ'),
          subtitle: const Text('يعدّ العادّ ما أمامه دون أن يرى الرقم المتوقع.'),
          value: blind,
          onChanged: (v) => setLocal(() => blind = v),
        ),
      ),
      TextField(controller: note, maxLength: 500, decoration: fieldDeco('ملاحظة (اختياري)')),
      const SizedBox(height: 4),
      Text('تُلتقط أرصدة الأصناف الحالية بنداً بنداً، ويُضاف لاحقاً ما يُوجد من أصناف لا رصيد لها.',
          style: TextStyle(color: Sem.of(context).muted, fontSize: 12.5)),
    ]),
    onSave: () async {
      newId = await app.stCountStart(warehouseId: wh, categoryId: cat.isEmpty ? null : cat, blind: blind, note: note.text);
    },
  );
  note.dispose();
  final id = newId;
  if (id != null && context.mounted) openStoreCount(context, id);
}

// ---------------------------------------------------------------------
// قائمة الجلسات
// ---------------------------------------------------------------------

class StocktakePage extends StatelessWidget {
  const StocktakePage({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final sem = Sem.of(context);
    final s = app.stores;
    final k = app.stocktake;
    final live = k.live;
    final past = [for (final c in k.counts) if (!c.isLive) c];
    final today = DateTime.now();
    final canStart = app.storesMovableWarehouses.any((w) => k.liveOf(w.id) == null);
    return PageBody(
      onRefresh: app.loadAll,
      children: [
        PageHeader(
          title: 'الجرد الدوري',
          subtitle: 'عدّ المخزون الفعلي مقابل الدفتري، وتسوية الفروق بمستند معتمد يمر بالقرار والترحيل.',
          icon: Icons.fact_check_outlined,
          actions: [
            if (canStart) FilledButton.icon(onPressed: () => startStocktakeDialog(context), icon: const Icon(Icons.add_rounded), label: const Text('جلسة جديدة')),
          ],
        ),
        if (!app.v26Ready) ...[
          const InfoBanner(
            level: 'warning',
            icon: Icons.storage_rounded,
            text: 'الجرد يحتاج تحديث قاعدة البيانات (الترحيل 42)، أو لا تملك مخزناً تجرده.',
          ),
          const SizedBox(height: 14),
        ],
        SectionCard(
          title: 'جلسات قائمة (${live.length})',
          icon: Icons.pending_actions_outlined,
          child: live.isEmpty
              ? Text('لا جلسة قائمة.', style: TextStyle(color: sem.muted))
              : Column(children: [for (final c in live) _CountTile(count: c)]),
        ),
        const SizedBox(height: 14),
        SectionCard(
          title: 'آخر جرد لكل مخزن',
          icon: Icons.history_toggle_off_rounded,
          subtitle: 'المخازن التي لم تُجرد قط أو مضى على جردها زمن طويل أولاً.',
          child: Builder(builder: (_) {
            final rows = <(String, DateTime?)>[
              for (final w in s.warehouses)
                if (w.active && (app.storesSeesAll || app.storesMyWarehouses.contains(w.id))) (w.name, k.lastClosed(w.id)?.decidedAt),
            ]..sort((a, b) => (a.$2 ?? DateTime(1970)).compareTo(b.$2 ?? DateTime(1970)));
            if (rows.isEmpty) return Text('لا مخازن.', style: TextStyle(color: sem.muted));
            return PmTable(
              columns: const ['المخزن', 'آخر جرد معتمد', 'منذ'],
              rows: [
                for (final r in rows)
                  [r.$1, r.$2 == null ? 'لم يُجرد' : dayText(r.$2), r.$2 == null ? '' : '${DateTime(today.year, today.month, today.day).difference(DateTime(r.$2!.year, r.$2!.month, r.$2!.day)).inDays} يوماً'],
              ],
            );
          }),
        ),
        const SizedBox(height: 14),
        SectionCard(
          title: 'سجل الجلسات (${past.length})',
          icon: Icons.receipt_long_outlined,
          child: past.isEmpty
              ? Text('لا جلسات منتهية بعد.', style: TextStyle(color: sem.muted))
              : Column(children: [for (final c in past.take(60)) _CountTile(count: c)]),
        ),
      ],
    );
  }
}

class _CountTile extends StatelessWidget {
  const _CountTile({required this.count});

  final StCount count;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final s = app.stores;
    final sem = Sem.of(context);
    final c = count;
    final ls = app.stocktake.linesOf(c.id);
    final done = ls.where((l) => l.counted).length;
    final when = c.decidedAt ?? c.submittedAt ?? c.createdAt;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      leading: Icon(Icons.fact_check_outlined, color: sem.muted),
      title: Text.rich(TextSpan(children: [
        TextSpan(text: c.countNo, style: const TextStyle(fontWeight: FontWeight.w600)),
        TextSpan(text: ' · ${stCountScope(s, c)}', style: TextStyle(color: sem.muted, fontWeight: FontWeight.w500)),
      ])),
      subtitle: Text(
        [if (when != null) dayText(when), if (c.isLive || c.isClosed) '$done من ${ls.length} بنداً معدوداً', if (c.blind && c.isOpen) 'رصيد مخفي'].join(' · '),
        style: TextStyle(color: sem.muted, fontSize: 12.5),
      ),
      trailing: ToneBadge(c.statusLabel, color: stCountStatusColor(sem, c.status)),
      onTap: () => openStoreCount(context, c.id),
    );
  }
}

// ---------------------------------------------------------------------
// صفحة الجلسة
// ---------------------------------------------------------------------

class StocktakeDetailPage extends StatefulWidget {
  const StocktakeDetailPage({super.key, required this.countId});

  final String countId;

  @override
  State<StocktakeDetailPage> createState() => _StocktakeDetailPageState();
}

class _StocktakeDetailPageState extends State<StocktakeDetailPage> {
  final _q = TextEditingController();
  final Map<String, TextEditingController> _ctl = {};
  final Map<String, DateTime?> _expiry = {};
  final Set<String> _dirty = {};
  bool _onlyOpen = false;
  bool _busy = false;

  @override
  void dispose() {
    _q.dispose();
    for (final c in _ctl.values) {
      c.dispose();
    }
    super.dispose();
  }

  /// مُحرِّر العدّ لبند: يُنشأ مرة بقيمة المحفوظ ثم يحتفظ بما يكتبه المستخدم عبر إعادة البناء.
  TextEditingController _controllerOf(StCountLine l) =>
      _ctl.putIfAbsent(l.itemId, () => TextEditingController(text: l.countedQty == null ? '' : fmtQty(l.countedQty!).replaceAll(',', '')));

  /// الكمية المكتوبة: null فراغ، والسالب أو غير الرقم يُعاد كخطأ عبر [_invalid].
  double? _typed(StCountLine l) {
    final t = _ctl[l.itemId]?.text ?? '';
    if (!_ctl.containsKey(l.itemId)) return l.countedQty;
    return t.trim().isEmpty ? null : parseImportNumber(t);
  }

  bool _invalid(StCountLine l) {
    final c = _ctl[l.itemId];
    if (c == null || c.text.trim().isEmpty) return false;
    final v = parseImportNumber(c.text);
    return v == null || v < 0;
  }

  List<Map<String, dynamic>> _payload(List<StCountLine> lines) => [
        for (final l in lines)
          if (_dirty.contains(l.itemId))
            {
              'item_id': l.itemId,
              'counted_qty': _typed(l),
              if ((_expiry.containsKey(l.itemId) ? _expiry[l.itemId] : l.expiryDate) != null)
                'expiry_date': isoDay(_expiry.containsKey(l.itemId) ? _expiry[l.itemId] : l.expiryDate),
              if (l.batchNo.isNotEmpty) 'batch_no': l.batchNo,
              if (l.note.isNotEmpty) 'note': l.note,
            },
      ];

  Future<bool> _save(AppState app, StCount c) async {
    final lines = app.stocktake.linesOf(c.id);
    if (lines.any(_invalid)) {
      showToast(context, 'في الكميات رقم غير صالح.', error: true);
      return false;
    }
    final payload = _payload(lines);
    if (payload.isEmpty) return true;
    setState(() => _busy = true);
    final ok = await storesRun(context, () => app.stCountSave(c.id, payload));
    if (mounted) setState(() => _busy = false);
    if (ok) _dirty.clear();
    return ok;
  }

  Future<void> _submit(AppState app, StCount c) async {
    if (!await _save(app, c) || !mounted) return;
    final ls = app.stocktake.linesOf(c.id);
    final left = ls.where((l) => !l.counted).length;
    if (left > 0) {
      showToast(context, 'بقي $left من البنود بلا عدّ؛ اكتب صفراً لما لم تجده.', error: true);
      return;
    }
    final ok = await confirmDialog(context,
        title: 'تقديم الجلسة ${c.countNo}؟',
        message: 'يُمنع تعديل العدّ بعد التقديم إلا بإعادتها من مدير المخازن أو المدير.',
        confirmLabel: 'تقديم');
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    await storesRun(context, () => app.stCountSubmit(c.id), success: 'قُدّمت الجلسة للقرار');
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _approve(AppState app, StCount c) async {
    final sum = app.stocktake.summary(c, (id) => app.stores.onHand(id, warehouseId: c.warehouseId));
    final msg = sum.withVariance == 0
        ? 'لا فرق بين المعدود والرصيد؛ تُغلق الجلسة دون مستند تسوية.'
        : 'يُنشأ مستند تسوية معتمد بـ ${sum.withVariance} من بنود الفرق (زيادة ${fmtQty(sum.gain)} ونقص ${fmtQty(sum.loss)})، ثم يُرحَّل من المستندات.';
    final note = await textInputDialog(context,
        title: 'اعتماد الجلسة ${c.countNo}',
        message: msg,
        label: 'ملاحظة القرار (اختياري)',
        confirmLabel: 'اعتماد');
    if (note == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final doc = await app.stCountApprove(c.id, note: note);
      if (mounted) {
        showToast(context, doc == null ? 'أُغلقت الجلسة بلا فرق' : 'اعتُمدت الجلسة وتولّدت التسوية');
        if (doc != null) openStoreDoc(context, doc);
      }
    } catch (e) {
      if (mounted) showToast(context, friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _return(AppState app, StCount c) async {
    final n = await textInputDialog(context,
        title: 'إعادة الجلسة للعدّ', message: 'تعود إلى العادّ لتصحيح ما يلزم.', label: 'سبب الإعادة', confirmLabel: 'إعادة', required: true);
    if (n == null || !mounted) return;
    setState(() => _busy = true);
    await storesRun(context, () => app.stCountReturn(c.id, n), success: 'أُعيدت الجلسة للعدّ');
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _cancel(AppState app, StCount c) async {
    final n = await textInputDialog(context,
        title: 'إلغاء الجلسة ${c.countNo}',
        message: 'لا يتغير أي رصيد، وتبقى الجلسة ملغاة في السجل.',
        label: 'سبب الإلغاء',
        confirmLabel: 'إلغاء الجلسة',
        required: c.isSubmitted);
    if (n == null || !mounted) return;
    setState(() => _busy = true);
    final ok = await storesRun(context, () => app.stCountCancel(c.id, note: n), success: 'أُلغيت الجلسة');
    if (mounted) setState(() => _busy = false);
    if (ok && mounted) Navigator.of(context).maybePop();
  }

  /// يضيف صنفاً وُجد بلا رصيد دفتري إلى الجلسة بعدّه.
  Future<void> _addItem(AppState app, StCount c) async {
    final s = app.stores;
    final have = {for (final l in app.stocktake.linesOf(c.id)) l.itemId};
    final q = TextEditingController();
    final picked = await showDialog<StItem>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setLocal) {
        final found = [
          for (final it in s.items)
            if (it.active && !have.contains(it.id) && (c.categoryId == null || it.categoryId == c.categoryId) && it.matches(q.text)) it,
        ];
        return AlertDialog(
          title: const Text('إضافة صنف وُجد بلا رصيد'),
          content: SizedBox(
            width: 440,
            height: 360,
            child: Column(children: [
              TextField(controller: q, autofocus: true, onChanged: (_) => setLocal(() {}), decoration: fieldDeco('بحث بالاسم أو الرمز', prefixIcon: const Icon(Icons.search_rounded))),
              const SizedBox(height: 8),
              Expanded(
                child: found.isEmpty
                    ? const Center(child: Text('لا أصناف مطابقة.'))
                    : ListView(children: [
                        for (final it in found.take(40))
                          ListTile(dense: true, title: Text(it.name), subtitle: Text('${it.code} · ${s.unitName(it.baseUnitId)}'), onTap: () => Navigator.of(ctx).pop(it)),
                      ]),
              ),
            ]),
          ),
          actions: [TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('إلغاء'))],
        );
      }),
    );
    q.dispose();
    if (picked == null || !mounted) return;
    if (!await _save(app, c) || !mounted) return;
    await storesRun(context, () => app.stCountSave(c.id, [{'item_id': picked.id, 'counted_qty': null}]));
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final sem = Sem.of(context);
    final s = app.stores;
    final c = app.stocktake.count(widget.countId);
    if (c == null) return Scaffold(appBar: AppBar(), body: const EmptyState(title: 'الجلسة غير موجودة أو لا تملك الاطلاع عليها'));
    final all = app.stocktake.linesOf(c.id);
    final lines = [
      for (final l in all)
        if ((s.item(l.itemId)?.matches(_q.text) ?? true) && (!_onlyOpen || !(_typed(l) != null)))
          l,
    ]..sort((a, b) => s.itemName(a.itemId).compareTo(s.itemName(b.itemId)));
    final canEdit = c.isOpen && app.canStocktake(c.warehouseId);
    final sum = app.stocktake.summary(c, (id) => s.onHand(id, warehouseId: c.warehouseId));
    final showSystem = !c.isOpen || !c.blind;
    final adjust = s.doc(c.adjustDocId);
    String who(String? id) => id == null ? '' : (app.people[id]?.displayName ?? '');
    final actions = <Widget>[
      if (canEdit) ...[
        OutlinedButton.icon(onPressed: _busy ? null : () => _addItem(app, c), icon: const Icon(Icons.add_rounded), label: const Text('صنف بلا رصيد')),
        OutlinedButton.icon(onPressed: _busy ? null : () => _save(app, c).then((ok) => ok && mounted ? showToast(context, 'حُفظ العدّ') : null), icon: const Icon(Icons.save_outlined), label: const Text('حفظ')),
        FilledButton.icon(onPressed: _busy ? null : () => _submit(app, c), icon: const Icon(Icons.send_rounded), label: const Text('تقديم للقرار')),
      ],
      if (c.isSubmitted && app.canStocktakeDecide) ...[
        OutlinedButton.icon(onPressed: _busy ? null : () => _return(app, c), icon: const Icon(Icons.undo_rounded), label: const Text('إعادة للعدّ')),
        if (app.canApproveCount(c))
          FilledButton.icon(onPressed: _busy ? null : () => _approve(app, c), icon: const Icon(Icons.verified_rounded), label: const Text('اعتماد')),
      ],
      if (c.isLive && (app.canStocktake(c.warehouseId) || app.canStocktakeDecide))
        TextButton.icon(onPressed: _busy ? null : () => _cancel(app, c), icon: Icon(Icons.cancel_outlined, color: sem.danger), label: Text('إلغاء', style: TextStyle(color: sem.danger))),
    ];
    return Scaffold(
      appBar: AppBar(title: Text('جرد ${c.countNo}')),
      body: PageBody(
        onRefresh: app.loadAll,
        children: [
          PageHeader(
            title: '${c.countNo} · ${stCountScope(s, c)}',
            subtitle: [
              c.statusLabel,
              if (c.createdAt != null) 'بدأت ${dayText(c.createdAt)}${who(c.createdBy).isEmpty ? '' : ' بواسطة ${who(c.createdBy)}'}',
              if (c.note.isNotEmpty) c.note,
            ].join(' · '),
            icon: Icons.fact_check_outlined,
            actions: actions,
          ),
          if (c.isSubmitted && app.canStocktakeDecide && !app.canApproveCount(c))
            _gap(const InfoBanner(level: 'info', text: 'فصل المهام: من أنشأ الجلسة أو قدّمها لا يعتمدها؛ يعتمدها مدير مخازن آخر أو المدير.')),
          if (c.decisionNote.isNotEmpty) _gap(InfoBanner(level: 'info', text: 'ملاحظة القرار: ${c.decisionNote}')),
          if (c.isOpen && c.blind && canEdit)
            _gap(const InfoBanner(level: 'info', text: 'الرصيد الدفتري مخفي أثناء العدّ؛ يظهر بعد التقديم. اكتب صفراً لما لم تجده.')),
          if (adjust != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: ListTile(
                tileColor: Theme.of(context).colorScheme.surfaceContainerHighest.withAlpha(60),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                leading: const Icon(Icons.tune_rounded),
                title: Text('مستند التسوية ${adjust.docNo}'),
                subtitle: Text(adjust.statusLabel),
                trailing: const Icon(Icons.chevron_left_rounded),
                onTap: () => openStoreDoc(context, adjust.id),
              ),
            ),
          ResponsiveGrid(minItemWidth: 150, children: [
            StatCard(label: 'البنود', value: '${sum.total}', icon: Icons.list_alt_rounded),
            StatCard(label: 'المعدود', value: '${sum.counted}', icon: Icons.task_alt_rounded, color: sum.complete ? sem.ok : sem.wip),
            if (showSystem) ...[
              StatCard(label: 'بنود بفرق', value: '${sum.withVariance}', icon: Icons.difference_outlined, color: sum.withVariance == 0 ? sem.ok : sem.wip),
              StatCard(label: 'زيادة', value: fmtQty(sum.gain), icon: Icons.add_circle_outline_rounded),
              StatCard(label: 'نقص', value: fmtQty(sum.loss), icon: Icons.remove_circle_outline_rounded, color: sum.loss == 0 ? null : sem.danger),
            ],
          ]),
          const SizedBox(height: 12),
          Wrap(spacing: 10, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
            SizedBox(
              width: 280,
              child: TextField(controller: _q, onChanged: (_) => setState(() {}), decoration: fieldDeco('بحث في البنود', prefixIcon: const Icon(Icons.search_rounded))),
            ),
            if (canEdit) FilterChip(label: const Text('غير المعدود فقط'), selected: _onlyOpen, onSelected: (v) => setState(() => _onlyOpen = v)),
          ]),
          const SizedBox(height: 12),
          SectionCard(
            title: 'بنود الجرد (${lines.length})',
            child: lines.isEmpty
                ? Text('لا بنود مطابقة.', style: TextStyle(color: sem.muted))
                : Column(children: [
                    for (final l in lines)
                      _CountRow(
                        key: ValueKey('${c.id}-${l.itemId}'),
                        count: c,
                        line: l,
                        editable: canEdit,
                        showSystem: showSystem,
                        controller: canEdit ? _controllerOf(l) : null,
                        expiry: _expiry.containsKey(l.itemId) ? _expiry[l.itemId] : l.expiryDate,
                        liveOnHand: s.onHand(l.itemId, warehouseId: c.warehouseId),
                        invalid: _invalid(l),
                        onChanged: () => setState(() => _dirty.add(l.itemId)),
                        onExpiry: (d) => setState(() {
                          _expiry[l.itemId] = d;
                          _dirty.add(l.itemId);
                        }),
                      ),
                  ]),
          ),
        ],
      ),
    );
  }
}

class _CountRow extends StatelessWidget {
  const _CountRow({
    super.key,
    required this.count,
    required this.line,
    required this.editable,
    required this.showSystem,
    required this.controller,
    required this.expiry,
    required this.liveOnHand,
    required this.invalid,
    required this.onChanged,
    required this.onExpiry,
  });

  final StCount count;
  final StCountLine line;
  final bool editable;
  final bool showSystem;
  final TextEditingController? controller;
  final DateTime? expiry;
  final double liveOnHand;
  final bool invalid;
  final VoidCallback onChanged;
  final ValueChanged<DateTime?> onExpiry;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final s = app.stores;
    final sem = Sem.of(context);
    final it = s.item(line.itemId);
    final unit = s.unitName(it?.baseUnitId);
    final typed = controller == null ? line.countedQty : (controller!.text.trim().isEmpty ? null : parseImportNumber(controller!.text));
    // الفرق: بعد الإغلاق المقيَّد، وقبله المعدود مقابل الرصيد الفعلي الآن (ما سيُقيَّد عند الاعتماد)
    final variance = typed == null ? null : (count.isClosed ? (line.variance ?? 0) : roundQty(typed - liveOnHand));
    final needsExpiry = editable && (it?.tracksExpiry ?? false) && variance != null && variance > 0;
    final varColor = variance == null || variance == 0 ? sem.muted : (variance > 0 ? sem.ok : sem.danger);
    final info = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(it?.name ?? '—', style: const TextStyle(fontWeight: FontWeight.w600)),
      Text([if (it != null && it.code.isNotEmpty) it.code, unit].join(' · '), style: TextStyle(color: sem.muted, fontSize: 12.5)),
      if (line.systemQty == 0 && !count.isClosed) Text('وُجد بلا رصيد دفتري', style: TextStyle(color: sem.wip, fontSize: 12.5)),
    ]);
    final numbers = Wrap(spacing: 14, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
      if (showSystem) Text('الدفتري ${fmtQty(line.systemQty)}', style: _tabular.copyWith(color: sem.muted)),
      if (variance != null && showSystem) Text('الفرق ${signedQty(variance)}', style: _tabular.copyWith(color: varColor, fontWeight: FontWeight.w600)),
      if (!editable) Text(typed == null ? 'غير معدود' : 'المعدود ${fmtQty(typed)}', style: _tabular),
    ]);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: LayoutBuilder(builder: (context, box) {
        final narrow = box.maxWidth < 560;
        final input = editable
            ? SizedBox(
                width: 150,
                child: TextField(
                  controller: controller,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  textDirection: TextDirection.ltr,
                  onChanged: (_) => onChanged(),
                  decoration: fieldDeco('المعدود ($unit)').copyWith(errorText: invalid ? 'رقم غير صالح' : null),
                ),
              )
            : null;
        final expiryField = needsExpiry
            ? SizedBox(width: 170, child: DayField(label: 'تاريخ الانتهاء', value: expiry, onChanged: onExpiry))
            : null;
        final left = Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [info, const SizedBox(height: 4), numbers]));
        if (narrow) {
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [left]),
            if (input != null) ...[const SizedBox(height: 6), Wrap(spacing: 10, runSpacing: 8, children: [input, if (expiryField != null) expiryField])],
            const Divider(height: 14),
          ]);
        }
        return Column(children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            left,
            if (input != null) ...[const SizedBox(width: 10), input],
            if (expiryField != null) ...[const SizedBox(width: 10), expiryField],
          ]),
          const Divider(height: 14),
        ]);
      }),
    );
  }
}
