import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../app_state.dart';
import '../models.dart' show currencyLabel, dayText, fmtMoney, parseMoney;
import '../procurement.dart';
import '../registers.dart' show isoDay;
import '../stores.dart' show fmtQty, parseImportNumber;
import '../ui/theme.dart';
import '../ui/widgets.dart';
import 'contract_finance.dart' show DayField;
import 'stores.dart' show storesRun;
import 'stores_setup.dart' show storeFormDialog;

// =====================================================================
// قسم المشتريات (الإصدار 1.10.0، الترحيل 41): اللوحة، وطلبات الاحتياج وصفحة الطلب (المراجعة والاعتماد والعروض
// وأمر الشراء والاستلام)، وأوامر الشراء، والموردون، وطلباتي، والإعدادات.
// =====================================================================

const _tabular = TextStyle(fontFeatures: [ui.FontFeature.tabularFigures()]);

String _plain(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();
String _money(double v) => '${fmtMoney(v)} $currencyLabel';

/// لون أولوية الطلب.
Color prPriorityColor(Sem sem, String p) => switch (p) {
      'urgent' => sem.danger,
      'high' => sem.wip,
      'low' => sem.todo,
      _ => sem.na,
    };

/// لون حالة الطلب.
Color prStatusColor(Sem sem, String s) => switch (s) {
      'submitted' || 'reviewed' => sem.wip,
      'approved' || 'ordered' || 'partial' => sem.na,
      'received' || 'fulfilled' => sem.ok,
      'rejected' => sem.danger,
      _ => sem.muted,
    };

Color prOrderColor(Sem sem, String s) => switch (s) {
      'issued' || 'partial' => sem.na,
      'received' => sem.ok,
      _ => sem.muted,
    };

IconData _eventIcon(String k) => switch (k) {
      'create' || 'update' => Icons.edit_note_rounded,
      'submit' => Icons.send_rounded,
      'review' => Icons.inventory_2_outlined,
      'reject' || 'decline' => Icons.block_rounded,
      'approve' => Icons.verified_rounded,
      'cancel' || 'order_cancel' => Icons.cancel_outlined,
      'quote' || 'select' => Icons.request_quote_outlined,
      'order' => Icons.receipt_long_rounded,
      'receive' => Icons.move_to_inbox_rounded,
      _ => Icons.chat_bubble_outline_rounded,
    };

/// قبل تطبيق الترحيل 41.
class ProcNotReady extends StatelessWidget {
  const ProcNotReady({super.key});

  @override
  Widget build(BuildContext context) => const InfoBanner(
        level: 'warning',
        icon: Icons.storage_rounded,
        text: 'قسم المشتريات يحتاج تحديث قاعدة البيانات (الترحيل 41).',
      );
}

void openPrRequest(BuildContext context, String requestId) =>
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => PrRequestPage(requestId: requestId)));

// ---------------------------------------------------------------------
// بطاقة طلب في القوائم
// ---------------------------------------------------------------------

class PrRequestTile extends StatelessWidget {
  const PrRequestTile({super.key, required this.request, this.showRequester = true});

  final PrRequest request;
  final bool showRequester;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final p = app.proc;
    final sem = Sem.of(context);
    final r = request;
    final n = p.linesOf(r.id).length;
    final o = p.orderOfRequest(r.id);
    final bits = <String>[
      r.reqNo,
      '$n بند',
      if (showRequester && r.requesterName.isNotEmpty) 'من ${r.requesterName}',
      if (o != null && o.status != 'cancelled') o.poNo,
      if (r.neededBy != null) 'مطلوب قبل ${dayText(r.neededBy)}',
    ];
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => openPrRequest(context, r.id),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(width: 4, height: 44, decoration: BoxDecoration(color: prPriorityColor(sem, r.priority), borderRadius: BorderRadius.circular(4))),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(r.title, style: const TextStyle(fontWeight: FontWeight.w700), maxLines: 2, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 2),
                  Text(bits.join(' · '), style: TextStyle(fontSize: 12, color: sem.muted), maxLines: 2, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 6),
                  Wrap(spacing: 6, runSpacing: 4, children: [
                    ToneBadge(prStatusLabels[r.status] ?? r.status, color: prStatusColor(sem, r.status)),
                    ToneBadge(prPriorityLabels[r.priority] ?? r.priority, color: prPriorityColor(sem, r.priority)),
                  ]),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------
// اختيار صنف
// ---------------------------------------------------------------------

Future<PrItemRef?> pickPrItem(BuildContext context, List<PrItemRef> items, {bool showAvailable = false}) =>
    showDialog<PrItemRef>(context: context, builder: (_) => _PrItemPicker(items: items, showAvailable: showAvailable));

class _PrItemPicker extends StatefulWidget {
  const _PrItemPicker({required this.items, required this.showAvailable});

  final List<PrItemRef> items;
  final bool showAvailable;

  @override
  State<_PrItemPicker> createState() => _PrItemPickerState();
}

class _PrItemPickerState extends State<_PrItemPicker> {
  final _q = TextEditingController();

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final q = _q.text.trim().toLowerCase();
    final shown = [for (final i in widget.items) if (q.isEmpty || i.name.toLowerCase().contains(q) || i.code.toLowerCase().contains(q)) i];
    return AlertDialog(
      title: const Text('اختيار صنف'),
      content: SizedBox(
        width: 440,
        height: 420,
        child: Column(children: [
          TextField(
            controller: _q,
            autofocus: true,
            onChanged: (_) => setState(() {}),
            decoration: fieldDeco('بحث بالاسم أو الرمز', prefixIcon: const Icon(Icons.search_rounded)),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: shown.isEmpty
                ? const Center(child: Text('لا أصناف مطابقة'))
                : ListView.builder(
                    itemCount: shown.length > 200 ? 200 : shown.length,
                    itemBuilder: (ctx, i) {
                      final it = shown[i];
                      final av = widget.showAvailable ? it.available : null;
                      return ListTile(
                        dense: true,
                        title: Text(it.name),
                        subtitle: Text([it.code, if (it.isAsset) 'أصل', if (av != null) 'المتاح ${fmtQty(av)}'].where((x) => x.isNotEmpty).join(' · ')),
                        onTap: () => Navigator.of(ctx).pop(it),
                      );
                    },
                  ),
          ),
        ]),
      ),
      actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('إغلاق'))],
    );
  }
}

// ---------------------------------------------------------------------
// نموذج طلب الاحتياج
// ---------------------------------------------------------------------

class _LineDraft {
  _LineDraft({this.itemId, String name = '', String qty = '', String unitName = '', this.unitId = '', String note = ''})
      : name = TextEditingController(text: name),
        qty = TextEditingController(text: qty),
        unitName = TextEditingController(text: unitName),
        note = TextEditingController(text: note);

  String? itemId;
  String unitId;
  final TextEditingController name, qty, unitName, note;

  void dispose() {
    name.dispose();
    qty.dispose();
    unitName.dispose();
    note.dispose();
  }
}

Future<void> showPrRequestDialog(BuildContext context, {PrRequest? edit}) async {
  final app = AppScope.read(context);
  final p = app.proc;
  final title = TextEditingController(text: edit?.title ?? '');
  final reason = TextEditingController(text: edit?.reason ?? '');
  var priority = edit?.priority ?? 'normal';
  DateTime? needed = edit?.neededBy;
  var dept = edit?.departmentId ?? '';
  var submitNow = edit == null;
  final drafts = <_LineDraft>[
    if (edit != null)
      for (final l in p.linesOf(edit.id))
        _LineDraft(itemId: l.itemId, name: l.name, qty: _plain(l.qty), unitName: l.unitName, unitId: l.unitId ?? '', note: l.note),
  ];

  Widget lineRow(_LineDraft d, StateSetter set) {
    final it = d.itemId == null ? null : p.item(d.itemId);
    final units = d.itemId == null ? const <PrUnitRef>[] : p.unitsOf(d.itemId!);
    final unitValue = d.unitId.isNotEmpty ? d.unitId : (it?.baseUnitId ?? '');
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(border: Border.all(color: Sem.of(context).rule), borderRadius: BorderRadius.circular(10)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(
            child: it != null
                ? Text(it.name, style: const TextStyle(fontWeight: FontWeight.w700))
                : TextField(controller: d.name, decoration: fieldDeco('وصف المطلوب (بند حر: لم يُعرَّف له صنف)')),
          ),
          IconButton(
            tooltip: 'حذف البند',
            onPressed: () => set(() {
              drafts.remove(d);
              d.dispose();
            }),
            icon: const Icon(Icons.delete_outline_rounded),
          ),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          SizedBox(width: 110, child: TextField(controller: d.qty, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: fieldDeco('الكمية'))),
          const SizedBox(width: 8),
          Expanded(
            child: it != null && units.isNotEmpty
                ? SelectField(label: 'الوحدة', value: unitValue, items: [for (final u in units) (u.id, u.name)], onChanged: (v) => set(() => d.unitId = v))
                : TextField(controller: d.unitName, decoration: fieldDeco('الوحدة (مثل: علبة)')),
          ),
        ]),
        const SizedBox(height: 8),
        TextField(controller: d.note, decoration: fieldDeco('ملاحظة على البند (اختياري)')),
      ]),
    );
  }

  await storeFormDialog(
    context,
    title: edit == null ? 'طلب احتياج جديد' : 'تعديل طلب الاحتياج',
    width: 560,
    body: (set) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      TextField(controller: title, decoration: fieldDeco('عنوان الطلب (ما الحاجة؟)')),
      const SizedBox(height: 10),
      TextField(controller: reason, minLines: 2, maxLines: 4, decoration: fieldDeco('مبررات الاحتياج (اختياري)')),
      const SizedBox(height: 10),
      SelectField(
        label: 'الأولوية',
        value: priority,
        items: [for (final x in prPriorityOrder.reversed) (x, prPriorityLabels[x]!)],
        onChanged: (v) => set(() => priority = v),
      ),
      const SizedBox(height: 10),
      DayField(label: 'مطلوب قبل (اختياري)', value: needed, onChanged: (d) => set(() => needed = d)),
      const SizedBox(height: 10),
      SelectField(
        label: 'الإدارة الطالبة (اختياري)',
        value: dept,
        items: [('', 'غير محددة'), for (final d in p.departments) (d.$1, d.$2)],
        onChanged: (v) => set(() => dept = v),
      ),
      const SizedBox(height: 14),
      Text('البنود (${drafts.length})', style: const TextStyle(fontWeight: FontWeight.w700)),
      const SizedBox(height: 8),
      for (final d in drafts) lineRow(d, set),
      Wrap(spacing: 8, runSpacing: 8, children: [
        OutlinedButton.icon(
          onPressed: () async {
            final it = await pickPrItem(context, p.items);
            if (it != null) set(() => drafts.add(_LineDraft(itemId: it.id, unitId: it.baseUnitId ?? '')));
          },
          icon: const Icon(Icons.inventory_2_outlined),
          label: const Text('إضافة صنف'),
        ),
        OutlinedButton.icon(
          onPressed: () => set(() => drafts.add(_LineDraft())),
          icon: const Icon(Icons.edit_note_rounded),
          label: const Text('بند حر'),
        ),
      ]),
      if (edit == null) ...[
        const SizedBox(height: 6),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: submitNow,
          onChanged: (v) => set(() => submitNow = v),
          title: const Text('تقديم الطلب بعد حفظه'),
          subtitle: const Text('وإلا بقي مسودة تقدّمه لاحقاً.'),
        ),
      ],
    ]),
    onSave: () async {
      if (title.text.trim().length < 3) throw StateError('اكتب عنواناً للطلب (3 أحرف فأكثر)');
      if (drafts.isEmpty) throw StateError('أضف بنداً واحداً على الأقل');
      final lines = <Map<String, dynamic>>[];
      for (var i = 0; i < drafts.length; i++) {
        final d = drafts[i];
        final q = parseImportNumber(d.qty.text);
        if (q == null || q <= 0) throw StateError('البند ${i + 1}: اكتب الكمية');
        if (d.itemId == null && d.name.text.trim().length < 2) throw StateError('البند ${i + 1}: اكتب وصف المطلوب');
        lines.add({
          if (d.itemId != null) ...{
            'item_id': d.itemId,
            'unit_id': d.unitId.isEmpty ? p.item(d.itemId)?.baseUnitId : d.unitId,
          } else ...{
            'name': d.name.text.trim(),
            'unit_name': d.unitName.text.trim(),
          },
          'qty': q,
          'note': d.note.text.trim(),
        });
      }
      final id = await app.prSaveRequest(edit?.id, {
        'title': title.text.trim(),
        'reason': reason.text.trim(),
        'priority': priority,
        if (needed != null) 'needed_by': isoDay(needed),
        if (dept.isNotEmpty) 'department_id': dept,
        'lines': lines,
      });
      if (submitNow && edit == null) await app.prSubmit(id);
    },
  );
  title.dispose();
  reason.dispose();
  for (final d in drafts) {
    d.dispose();
  }
}

// ---------------------------------------------------------------------
// صفحة الطلب
// ---------------------------------------------------------------------

class PrRequestPage extends StatefulWidget {
  const PrRequestPage({super.key, required this.requestId});

  final String requestId;

  @override
  State<PrRequestPage> createState() => _PrRequestPageState();
}

class _PrRequestPageState extends State<PrRequestPage> {
  Future<List<PrEvent>>? _events;
  Future<List<PrReceipt>>? _receipts;
  String _stamp = '';

  Future<void> _review(PrRequest r) async {
    final app = AppScope.read(context);
    final p = app.proc;
    final lines = p.linesOf(r.id);
    final stock = {for (final l in lines) l.id: TextEditingController(text: l.stockQty == 0 ? '' : _plain(l.stockQty))};
    final linked = <String, String>{};
    final note = TextEditingController(text: r.reviewNote);
    await storeFormDialog(
      context,
      title: 'مراجعة التوفر',
      width: 580,
      body: (set) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const InfoBanner(text: 'اكتب لكل بند ما يُلبّى من المخزون الآن؛ والباقي يُشترى. اربط البند الحر بصنف إن وُجد له صنف.'),
        const SizedBox(height: 10),
        for (final l in lines) ...[
          Builder(builder: (_) {
            final itemId = linked[l.id] ?? l.itemId;
            final it = p.item(itemId);
            final unitId = linked.containsKey(l.id) ? it?.baseUnitId : l.unitId;
            final av = itemId == null ? null : p.availableIn(itemId, unitId);
            final unit = itemId == null ? l.unitName : p.unitName(unitId);
            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(border: Border.all(color: Sem.of(context).rule), borderRadius: BorderRadius.circular(10)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text('${l.lineNo}. ${it?.name ?? l.name}', style: const TextStyle(fontWeight: FontWeight.w700)),
                Text(
                  'المطلوب ${fmtQty(l.qty)} $unit${av == null ? '' : ' · المتاح ${fmtQty(av < 0 ? 0 : av)} $unit'}',
                  style: TextStyle(fontSize: 12.5, color: Sem.of(context).muted),
                ),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(
                    child: TextField(
                      controller: stock[l.id],
                      enabled: itemId != null,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: fieldDeco(itemId == null ? 'اربط البند بصنف لتلبيته من المخزون' : 'المُلبّى من المخزون'),
                    ),
                  ),
                  if (l.itemId == null) ...[
                    const SizedBox(width: 8),
                    OutlinedButton(
                      onPressed: () async {
                        final x = await pickPrItem(context, p.items, showAvailable: true);
                        if (x != null) set(() => linked[l.id] = x.id);
                      },
                      child: Text(it == null ? 'ربط بصنف' : 'تغيير الصنف'),
                    ),
                  ],
                ]),
              ]),
            );
          }),
        ],
        TextField(controller: note, minLines: 1, maxLines: 3, decoration: fieldDeco('ملاحظة المراجعة (اختياري)')),
      ]),
      onSave: () async {
        final payload = <Map<String, dynamic>>[];
        for (final l in lines) {
          final q = parseImportNumber(stock[l.id]!.text) ?? 0;
          if (q < 0) throw StateError('البند ${l.lineNo}: الكمية غير سالبة');
          payload.add({'line_id': l.id, 'stock_qty': q, if (linked[l.id] != null) 'item_id': linked[l.id]});
        }
        final st = await app.prReview(r.id, {'note': note.text.trim(), 'lines': payload});
        if (st == 'fulfilled' && mounted) showToast(context, 'لُبّي الطلب كله من المخزون وأُغلق');
      },
    );
    for (final c in stock.values) {
      c.dispose();
    }
    note.dispose();
  }

  Future<void> _quote(PrRequest r) async {
    final app = AppScope.read(context);
    final p = app.proc;
    final sups = [for (final s in p.suppliers) if (s.active) s];
    if (sups.isEmpty) {
      showToast(context, 'أضف مورّدين أولاً من صفحة «الموردون»', error: true);
      return;
    }
    var supplier = '';
    final total = TextEditingController();
    final days = TextEditingController();
    final note = TextEditingController();
    DateTime? valid;
    await storeFormDialog(
      context,
      title: 'تسجيل عرض سعر',
      body: (set) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SelectField(
          label: 'المورّد',
          value: supplier,
          items: [('', 'اختر المورّد'), for (final s in sups) (s.id, s.name)],
          onChanged: (v) => set(() => supplier = v),
        ),
        const SizedBox(height: 10),
        TextField(controller: total, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: fieldDeco('إجمالي العرض ($currencyLabel)')),
        const SizedBox(height: 10),
        TextField(controller: days, keyboardType: TextInputType.number, decoration: fieldDeco('مدة التوريد بالأيام (اختياري)')),
        const SizedBox(height: 10),
        DayField(label: 'العرض ساري حتى (اختياري)', value: valid, onChanged: (d) => set(() => valid = d)),
        const SizedBox(height: 10),
        TextField(controller: note, decoration: fieldDeco('ملاحظة (اختياري)')),
        const SizedBox(height: 8),
        Text('تسجيل عرض لمورّد له عرض سابق على الطلب يحدّث عرضه.', style: TextStyle(fontSize: 12, color: Sem.of(context).muted)),
      ]),
      onSave: () async {
        if (supplier.isEmpty) throw StateError('اختر المورّد');
        final t = parseMoney(total.text);
        if (!t.ok || t.value == null) throw StateError('اكتب إجمالي العرض رقماً');
        final d = days.text.trim().isEmpty ? null : int.tryParse(days.text.trim());
        if (days.text.trim().isNotEmpty && (d == null || d < 0 || d > 730)) throw StateError('مدة التوريد من 0 إلى 730 يوماً');
        await app.prSaveQuote(r.id, {
          'supplier_id': supplier,
          'total': t.value,
          if (d != null) 'delivery_days': d,
          if (valid != null) 'valid_until': isoDay(valid),
          'note': note.text.trim(),
        });
      },
    );
    total.dispose();
    days.dispose();
    note.dispose();
  }

  Future<void> _issueOrder(PrRequest r, PrQuote q) async {
    final app = AppScope.read(context);
    final p = app.proc;
    final buy = [for (final l in p.linesOf(r.id)) if (l.toBuy > 0) l];
    final unlinked = buy.where((l) => l.itemId == null).toList();
    final short = p.quotesOf(r.id).length < p.settings.minQuotes;
    if (unlinked.isNotEmpty) {
      showToast(context, 'اربط كل بند يُشترى بصنف في مراجعة التوفر قبل إصدار الأمر', error: true);
      return;
    }
    if (short && !app.isDirector) {
      showToast(context, 'العروض أقل من الحد الأدنى (${p.settings.minQuotes}) ولا يستثني منه إلا المدير', error: true);
      return;
    }
    final prices = {for (final l in buy) l.id: TextEditingController()};
    final waiver = TextEditingController();
    final note = TextEditingController();
    var warehouse = p.warehouses.length == 1 ? p.warehouses.first.$1 : '';
    DateTime? expected;
    await storeFormDialog(
      context,
      title: 'إصدار أمر الشراء',
      width: 560,
      body: (set) {
        var total = 0.0;
        for (final l in buy) {
          final v = parseMoney(prices[l.id]!.text).value ?? 0;
          total += l.toBuy * v;
        }
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          InfoBanner(text: 'العرض الفائز: ${p.supplier(q.supplierId)?.name ?? ''} بإجمالي ${_money(q.total)}. اكتب سعر الوحدة لكل بند ليُحسب إجمالي الأمر.'),
          const SizedBox(height: 10),
          SelectField(
            label: 'مخزن الاستلام',
            value: warehouse,
            items: [('', 'اختر المخزن'), for (final w in p.warehouses) (w.$1, w.$2)],
            onChanged: (v) => set(() => warehouse = v),
          ),
          const SizedBox(height: 10),
          DayField(label: 'التوريد المتوقع (اختياري)', value: expected, onChanged: (d) => set(() => expected = d)),
          const SizedBox(height: 12),
          for (final l in buy) ...[
            Row(children: [
              Expanded(child: Text('${l.lineNo}. ${l.name} — ${fmtQty(l.toBuy)} ${p.unitName(l.unitId)}')),
              SizedBox(
                width: 130,
                child: TextField(
                  controller: prices[l.id],
                  onChanged: (_) => set(() {}),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: fieldDeco('سعر الوحدة'),
                ),
              ),
            ]),
            const SizedBox(height: 8),
          ],
          Align(alignment: AlignmentDirectional.centerEnd, child: Text('إجمالي الأمر: ${_money(total)}', style: const TextStyle(fontWeight: FontWeight.w800))),
          const SizedBox(height: 10),
          if (short) ...[
            InfoBanner(level: 'warning', text: 'العروض ${p.quotesOf(r.id).length} أقل من الحد الأدنى ${p.settings.minQuotes}: اكتب سبب الاستثناء (يُسجَّل في الأمر).'),
            const SizedBox(height: 8),
            TextField(controller: waiver, decoration: fieldDeco('سبب استثناء الحد الأدنى للعروض')),
            const SizedBox(height: 10),
          ],
          TextField(controller: note, decoration: fieldDeco('ملاحظة على الأمر (اختياري)')),
        ]);
      },
      onSave: () async {
        if (warehouse.isEmpty) throw StateError('اختر مخزن الاستلام');
        if (short && waiver.text.trim().length < 5) throw StateError('اكتب سبب استثناء الحد الأدنى للعروض (5 أحرف فأكثر)');
        final lines = <Map<String, dynamic>>[];
        for (final l in buy) {
          final v = parseMoney(prices[l.id]!.text);
          if (!v.ok) throw StateError('البند ${l.lineNo}: سعر الوحدة رقم غير سالب');
          lines.add({'line_id': l.id, 'unit_price': v.value ?? 0});
        }
        await app.prIssueOrder(r.id, {
          'quote_id': q.id,
          'warehouse_id': warehouse,
          if (expected != null) 'expected_date': isoDay(expected),
          if (short) 'waiver_note': waiver.text.trim(),
          'note': note.text.trim(),
          'lines': lines,
        });
      },
    );
    for (final c in prices.values) {
      c.dispose();
    }
    waiver.dispose();
    note.dispose();
  }

  Future<void> _receive(PrOrder o) async {
    final app = AppScope.read(context);
    final p = app.proc;
    final lines = [for (final l in p.orderLinesOf(o.id)) if (l.remaining > 0) l];
    final qty = {for (final l in lines) l.id: TextEditingController(text: _plain(l.remaining))};
    final batch = {for (final l in lines) l.id: TextEditingController()};
    final expiry = <String, DateTime?>{};
    final invoice = TextEditingController();
    final note = TextEditingController();
    await storeFormDialog(
      context,
      title: 'استلام دفعة — ${o.poNo}',
      width: 580,
      body: (set) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const InfoBanner(text: 'اكتب ما وصل فعلاً. المستهلكات تدخل مستند استلام (مسودة) تعتمده المخازن وترحّله، والأصول تُسجَّل أصلاً لكل وحدة.'),
        const SizedBox(height: 10),
        for (final l in lines) ...[
          Builder(builder: (_) {
            final it = p.item(l.itemId);
            final isAsset = it?.isAsset ?? false;
            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(border: Border.all(color: Sem.of(context).rule), borderRadius: BorderRadius.circular(10)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text(it?.name ?? '—', style: const TextStyle(fontWeight: FontWeight.w700)),
                Text('المتبقي ${fmtQty(l.remaining)} ${p.unitName(l.unitId)}${isAsset ? ' · أصل: عدد صحيح حتى 200' : ''}',
                    style: TextStyle(fontSize: 12.5, color: Sem.of(context).muted)),
                const SizedBox(height: 8),
                TextField(controller: qty[l.id], keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: fieldDeco('المستلَم الآن')),
                if (!isAsset) ...[
                  const SizedBox(height: 8),
                  Row(children: [
                    Expanded(child: TextField(controller: batch[l.id], decoration: fieldDeco('رقم الدفعة (اختياري)'))),
                    const SizedBox(width: 8),
                    Expanded(child: DayField(label: 'الانتهاء (اختياري)', value: expiry[l.id], onChanged: (d) => set(() => expiry[l.id] = d))),
                  ]),
                ],
              ]),
            );
          }),
        ],
        TextField(controller: invoice, decoration: fieldDeco('رقم فاتورة المورّد (اختياري)')),
        const SizedBox(height: 10),
        TextField(controller: note, decoration: fieldDeco('ملاحظة (اختياري)')),
      ]),
      onSave: () async {
        final payload = <Map<String, dynamic>>[];
        for (final l in lines) {
          final q = parseImportNumber(qty[l.id]!.text) ?? 0;
          if (q < 0) throw StateError('الكمية غير سالبة');
          if (q == 0) continue;
          final d = expiry[l.id];
          payload.add({
            'line_id': l.id,
            'qty': q,
            if (d != null) 'expiry_date': isoDay(d),
            if (batch[l.id]!.text.trim().isNotEmpty) 'batch_no': batch[l.id]!.text.trim(),
          });
        }
        if (payload.isEmpty) throw StateError('اكتب كمية موجبة لبند واحد على الأقل');
        await app.prReceive(o.id, {'lines': payload, 'invoice_no': invoice.text.trim(), 'note': note.text.trim()});
        if (mounted) setState(() => _receipts = null);
      },
    );
    for (final c in [...qty.values, ...batch.values, invoice, note]) {
      c.dispose();
    }
  }

  Future<void> _decide(PrRequest r, bool approve) async {
    final app = AppScope.read(context);
    final text = await textInputDialog(context,
        title: approve ? 'اعتماد الطلب' : 'عدم اعتماد الطلب',
        message: approve ? 'بعد الاعتماد يسجّل مسؤول المشتريات العروض ويصدر أمر الشراء.' : 'يُغلق الطلب غير معتمَد.',
        label: approve ? 'ملاحظة (اختياري)' : 'سبب عدم الاعتماد',
        confirmLabel: approve ? 'اعتماد' : 'عدم اعتماد',
        required: !approve);
    if (text == null || !mounted) return;
    await storesRun(context, () => app.prDecide(r.id, approve, note: text), success: approve ? 'اعتُمد الطلب' : 'أُغلق الطلب غير معتمَد');
  }

  Future<void> _reject(PrRequest r) async {
    final app = AppScope.read(context);
    final text = await textInputDialog(context, title: 'رفض الطلب', label: 'سبب الرفض', confirmLabel: 'رفض', required: true);
    if (text == null || !mounted) return;
    await storesRun(context, () => app.prReject(r.id, text));
  }

  Future<void> _cancel(PrRequest r) async {
    final app = AppScope.read(context);
    final ok = await confirmDialog(context, title: 'إلغاء الطلب؟', message: 'يُغلق الطلب ملغى ويبقى في السجل.', confirmLabel: 'إلغاء الطلب', danger: true);
    if (!ok || !mounted) return;
    await storesRun(context, () => app.prCancel(r.id));
  }

  Future<void> _cancelOrder(PrOrder o) async {
    final app = AppScope.read(context);
    final text = await textInputDialog(context,
        title: 'إلغاء أمر الشراء', message: 'يعود الطلب معتمَداً لتصدر له أمراً جديداً.', label: 'سبب الإلغاء', confirmLabel: 'إلغاء الأمر', required: true);
    if (text == null || !mounted) return;
    await storesRun(context, () => app.prCancelOrder(o.id, text));
  }

  Future<void> _comment(PrRequest r) async {
    final app = AppScope.read(context);
    final text = await textInputDialog(context, title: 'تعليق', label: 'نص التعليق', confirmLabel: 'إضافة', required: true);
    if (text == null || !mounted) return;
    await storesRun(context, () => app.prComment(r.id, text));
    setState(() => _stamp = '');
  }

  Future<void> _deleteQuote(PrQuote q) async {
    final app = AppScope.read(context);
    final ok = await confirmDialog(context, title: 'حذف العرض؟', message: 'يُحذف عرض هذا المورّد من الطلب.', confirmLabel: 'حذف', danger: true);
    if (!ok || !mounted) return;
    await storesRun(context, () => app.prDeleteQuote(q.id));
  }

  Widget _kv(String k, String v) => v.isEmpty
      ? const SizedBox.shrink()
      : Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(width: 120, child: Text(k, style: TextStyle(color: Sem.of(context).muted))),
            Expanded(child: Text(v)),
          ]),
        );

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final p = app.proc;
    final sem = Sem.of(context);
    final r = p.request(widget.requestId);
    if (r == null) {
      return Scaffold(appBar: AppBar(title: const Text('الطلب')), body: const EmptyState(title: 'الطلب غير موجود أو لا تملك صلاحية عرضه'));
    }
    final order = p.orderOfRequest(r.id);
    final key = '${r.status}|${r.updatedAt?.millisecondsSinceEpoch}|${order?.status}';
    if (key != _stamp || _events == null) {
      _stamp = key;
      _events = app.prEventsOf(r.id);
      _receipts = order == null ? null : app.prReceiptsOf(order.id);
    }
    _receipts ??= order == null ? null : app.prReceiptsOf(order.id);
    final lines = p.linesOf(r.id);
    final quotes = p.quotesOf(r.id);
    final mine = r.requesterId != null && r.requesterId == app.me?.id;
    final staff = app.prStaff;
    final canCancelEarly = (mine && (r.status == 'draft' || r.status == 'submitted') && app.canPrRequest) ||
        ((app.canPrReview || app.canPrBuy) && const {'draft', 'submitted', 'reviewed', 'approved'}.contains(r.status));
    final actions = <Widget>[
      if (mine && r.isDraft && app.canPrRequest) ...[
        FilledButton.icon(onPressed: () => storesRun(context, () => app.prSubmit(r.id), success: 'قُدّم الطلب'), icon: const Icon(Icons.send_rounded), label: const Text('تقديم الطلب')),
        OutlinedButton.icon(onPressed: () => showPrRequestDialog(context, edit: r), icon: const Icon(Icons.edit_rounded), label: const Text('تعديل')),
      ],
      if (app.canPrReview && (r.status == 'submitted' || r.status == 'reviewed'))
        FilledButton.icon(onPressed: () => _review(r), icon: const Icon(Icons.inventory_2_outlined), label: Text(r.status == 'submitted' ? 'مراجعة التوفر' : 'إعادة المراجعة')),
      if (app.canPrDecide && r.status == 'reviewed') ...[
        FilledButton.icon(onPressed: () => _decide(r, true), icon: const Icon(Icons.verified_rounded), label: const Text('اعتماد')),
        OutlinedButton.icon(onPressed: () => _decide(r, false), icon: const Icon(Icons.thumb_down_alt_outlined), label: const Text('عدم الاعتماد')),
      ],
      if (app.canPrReview && r.status == 'submitted')
        OutlinedButton.icon(onPressed: () => _reject(r), icon: const Icon(Icons.block_rounded), label: const Text('رفض')),
      if (app.canPrBuy && r.status == 'approved')
        FilledButton.tonalIcon(onPressed: () => _quote(r), icon: const Icon(Icons.request_quote_outlined), label: const Text('تسجيل عرض سعر')),
      if (canCancelEarly) OutlinedButton.icon(onPressed: () => _cancel(r), icon: const Icon(Icons.cancel_outlined), label: const Text('إلغاء')),
      if (app.canPrRequest && r.status != 'draft' && r.status != 'cancelled' && (mine || staff))
        TextButton.icon(onPressed: () => _comment(r), icon: const Icon(Icons.add_comment_outlined), label: const Text('تعليق')),
    ];
    final minQ = p.settings.minQuotes;
    return Scaffold(
      appBar: AppBar(title: Text(r.reqNo)),
      body: PageBody(
        maxWidth: 900,
        children: [
          Text(r.title, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Wrap(spacing: 6, runSpacing: 6, children: [
            ToneBadge(prStatusLabels[r.status] ?? r.status, color: prStatusColor(sem, r.status)),
            ToneBadge('أولوية ${prPriorityLabels[r.priority] ?? r.priority}', color: prPriorityColor(sem, r.priority)),
            if (r.neededBy != null) ToneBadge('مطلوب قبل ${dayText(r.neededBy)}', color: sem.muted, icon: Icons.schedule_rounded),
          ]),
          const SizedBox(height: 14),
          if (actions.isNotEmpty) ...[Wrap(spacing: 8, runSpacing: 8, children: actions), const SizedBox(height: 14)],
          if (r.status == 'fulfilled') const Padding(padding: EdgeInsets.only(bottom: 14), child: InfoBanner(level: 'ok', text: 'لُبّي الطلب كله من المخزون؛ يصرف أمين المخزن المواد بمستند صرف.')),
          if (r.status == 'rejected' && r.decisionNote.isNotEmpty) Padding(padding: const EdgeInsets.only(bottom: 14), child: InfoBanner(level: 'critical', text: 'مرفوض: ${r.decisionNote}')),
          if (r.status == 'approved' && app.canPrBuy && quotes.length < minQ)
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: InfoBanner(level: 'warning', text: 'العروض المسجلة ${quotes.length} من الحد الأدنى $minQ؛ سجّل المزيد، أو يستثني المدير بسبب مكتوب عند إصدار الأمر.'),
            ),
          SectionCard(
            title: 'التفاصيل',
            icon: Icons.info_outline_rounded,
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              if (r.reason.isNotEmpty) Padding(padding: const EdgeInsets.only(bottom: 10), child: Text(r.reason, style: const TextStyle(height: 1.6))),
              _kv('مقدّم الطلب', r.requesterName),
              _kv('الإدارة', [for (final d in p.departments) if (d.$1 == r.departmentId) d.$2].join()),
              _kv('قُدّم', r.submittedAt == null ? '' : fmtDate(r.submittedAt)),
              if (r.reviewedAt != null) _kv('رُوجع التوفر', '${fmtDate(r.reviewedAt)}${r.reviewNote.isEmpty ? '' : ' — ${r.reviewNote}'}'),
              if (r.decidedAt != null) _kv('القرار', '${fmtDate(r.decidedAt)}${r.decisionNote.isEmpty ? '' : ' — ${r.decisionNote}'}'),
              if (r.closedAt != null) _kv('أُغلق', fmtDate(r.closedAt)),
            ]),
          ),
          const SizedBox(height: 14),
          SectionCard(
            title: 'البنود (${lines.length})',
            icon: Icons.list_alt_rounded,
            child: Column(children: [
              for (final l in lines)
                Builder(builder: (_) {
                  final it = p.item(l.itemId);
                  final unit = l.itemId == null ? l.unitName : p.unitName(l.unitId);
                  final av = staff && l.itemId != null ? p.availableIn(l.itemId!, l.unitId) : null;
                  final sub = <String>[
                    if (l.stockQty > 0) 'من المخزون ${fmtQty(l.stockQty)}',
                    if (l.toBuy > 0 && r.status != 'draft' && r.status != 'submitted') 'للشراء ${fmtQty(l.toBuy)}',
                    if (l.itemId == null) 'بند حر بلا صنف',
                    if (av != null && (r.status == 'submitted' || r.status == 'reviewed')) 'المتاح ${fmtQty(av < 0 ? 0 : av)}',
                    if (l.note.isNotEmpty) l.note,
                  ];
                  return ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text('${l.lineNo}. ${it?.name ?? l.name}'),
                    subtitle: sub.isEmpty ? null : Text(sub.join(' · ')),
                    trailing: Text('${fmtQty(l.qty)} $unit', style: _tabular),
                  );
                }),
            ]),
          ),
          if (staff && quotes.isNotEmpty) ...[
            const SizedBox(height: 14),
            SectionCard(
              title: 'عروض الأسعار (${quotes.length})',
              icon: Icons.request_quote_outlined,
              child: Column(children: [
                for (final q in quotes)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(q.selected ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded, color: q.selected ? sem.ok : sem.muted),
                    title: Text(p.supplier(q.supplierId)?.name ?? '—'),
                    subtitle: Text([
                      if (q.deliveryDays != null) 'توريد خلال ${q.deliveryDays} يوماً',
                      if (q.validUntil != null) 'ساري حتى ${dayText(q.validUntil)}',
                      if (q.note.isNotEmpty) q.note,
                    ].join(' · ')),
                    trailing: Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 4, children: [
                      Text(_money(q.total), style: _tabular.copyWith(fontWeight: FontWeight.w700)),
                      if (app.canPrBuy && r.status == 'approved') ...[
                        TextButton(onPressed: () => _issueOrder(r, q), child: const Text('أمر شراء')),
                        IconButton(tooltip: 'حذف العرض', onPressed: () => _deleteQuote(q), icon: const Icon(Icons.delete_outline_rounded, size: 20)),
                      ],
                    ]),
                  ),
              ]),
            ),
          ],
          if (order != null) ...[
            const SizedBox(height: 14),
            SectionCard(
              title: 'أمر الشراء ${order.poNo}',
              icon: Icons.receipt_long_rounded,
              trailing: ToneBadge(prOrderStatusLabels[order.status] ?? order.status, color: prOrderColor(sem, order.status)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                _kv('المورّد', p.supplier(order.supplierId)?.name ?? ''),
                _kv('الإجمالي', _money(order.total)),
                _kv('مخزن الاستلام', [for (final w in p.warehouses) if (w.$1 == order.warehouseId) w.$2].join()),
                _kv('صدر', fmtDate(order.issuedAt)),
                if (order.expectedDate != null) _kv('التوريد المتوقع', dayText(order.expectedDate)),
                if (order.waiverNote.isNotEmpty) _kv('استثناء العروض', order.waiverNote),
                if (order.note.isNotEmpty) _kv('ملاحظة', order.note),
                const Divider(),
                for (final l in p.orderLinesOf(order.id))
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(p.item(l.itemId)?.name ?? '—'),
                    subtitle: Text('${fmtQty(l.qty)} ${p.unitName(l.unitId)} × ${fmtMoney(l.unitPrice)} · استُلم ${fmtQty(l.received)}'),
                    trailing: Text(_money(l.amount), style: _tabular),
                  ),
                if (order.isLive && (app.canPrReceive || app.canPrBuy))
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Wrap(spacing: 8, runSpacing: 8, children: [
                      if (app.canPrReceive) FilledButton.icon(onPressed: () => _receive(order), icon: const Icon(Icons.move_to_inbox_rounded), label: const Text('استلام دفعة')),
                      if (app.canPrBuy && order.status == 'issued')
                        OutlinedButton.icon(onPressed: () => _cancelOrder(order), icon: const Icon(Icons.cancel_outlined), label: const Text('إلغاء الأمر')),
                    ]),
                  ),
                FutureBuilder<List<PrReceipt>>(
                  future: _receipts,
                  builder: (context, snap) {
                    final list = snap.data ?? const <PrReceipt>[];
                    if (list.isEmpty) return const SizedBox.shrink();
                    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      const Divider(),
                      const Text('دفعات الاستلام', style: TextStyle(fontWeight: FontWeight.w700)),
                      for (final x in list)
                        ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.move_to_inbox_rounded, size: 20),
                          title: Text(fmtDate(x.receivedAt)),
                          subtitle: Text([
                            '${x.lines.length} بند',
                            if (x.assetCount > 0) '${x.assetCount} أصل',
                            if (x.docId != null) 'مستند استلام في المخازن',
                            if (x.invoiceNo.isNotEmpty) 'فاتورة ${x.invoiceNo}',
                            if (x.note.isNotEmpty) x.note,
                          ].join(' · ')),
                        ),
                    ]);
                  },
                ),
              ]),
            ),
          ],
          const SizedBox(height: 14),
          SectionCard(
            title: 'سجل الطلب',
            icon: Icons.history_rounded,
            child: FutureBuilder<List<PrEvent>>(
              future: _events,
              builder: (context, snap) {
                final list = snap.data;
                if (list == null) return const Padding(padding: EdgeInsets.all(12), child: Center(child: CircularProgressIndicator()));
                if (list.isEmpty) return const Text('لا أحداث');
                return Column(children: [
                  for (final e in list)
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(_eventIcon(e.kind), color: sem.muted, size: 20),
                      title: Text(prEventLabels[e.kind] ?? e.kind),
                      subtitle: e.note.isEmpty ? null : Text(e.note),
                      trailing: Text(fmtDate(e.at), style: _tabular.copyWith(fontSize: 11.5, color: sem.muted)),
                    ),
                ]);
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------
// بطاقة تنبيه
// ---------------------------------------------------------------------

class PrAlertTile extends StatelessWidget {
  const PrAlertTile({super.key, required this.alert});

  final PrAlert alert;

  @override
  Widget build(BuildContext context) {
    final sem = Sem.of(context);
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: Icon(alert.isCritical ? Icons.error_rounded : Icons.schedule_rounded, color: alert.isCritical ? sem.danger : sem.wip),
      title: Text(alert.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text('${prAlertLabels[alert.kind] ?? alert.kind} · ${alert.detail}', maxLines: 2, overflow: TextOverflow.ellipsis),
      onTap: () => openPrRequest(context, alert.requestId),
    );
  }
}

// ---------------------------------------------------------------------
// اللوحة
// ---------------------------------------------------------------------

class ProcDashboardPage extends StatelessWidget {
  const ProcDashboardPage({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final p = app.proc;
    final sem = Sem.of(context);
    final now = DateTime.now();
    final alerts = p.alerts(now);
    final byStatus = <String, int>{};
    for (final r in p.requests) {
      if (r.status == 'draft') continue;
      byStatus[r.status] = (byStatus[r.status] ?? 0) + 1;
    }
    final total = byStatus.values.fold<int>(0, (a, b) => a + b);
    final recent = [for (final r in p.requests) if (r.status != 'draft') r].take(6).toList();
    return PageBody(
      onRefresh: app.loadAll,
      children: [
        PageHeader(
          title: 'لوحة المشتريات',
          subtitle: 'طلبات الاحتياج من رفعها إلى الاستلام، وما ينتظر إجراءً، وأوامر الشراء القائمة.',
          icon: Icons.shopping_cart_checkout_rounded,
          actions: [
            if (app.canPrRequest) FilledButton.icon(onPressed: () => showPrRequestDialog(context), icon: const Icon(Icons.add_rounded), label: const Text('طلب احتياج')),
          ],
        ),
        if (!app.v25Ready) ...[const ProcNotReady(), const SizedBox(height: 14)],
        ResponsiveGrid(minItemWidth: 190, children: [
          KpiTile(label: 'طلبات جارية', value: '${p.open.length}', onTap: () => app.setTab(AppState.procRequestsTab)),
          KpiTile(
              label: 'بانتظار مراجعة التوفر',
              value: '${p.awaitingReview.length}',
              color: p.awaitingReview.isNotEmpty ? sem.wip : null,
              onTap: () => app.setTab(AppState.procRequestsTab)),
          KpiTile(label: 'بانتظار اعتماد المدير', value: '${p.awaitingDecision.length}', color: p.awaitingDecision.isNotEmpty ? sem.wip : null),
          KpiTile(label: 'معتمَدة بلا أمر شراء', value: '${p.awaitingOrder.length}', color: p.awaitingOrder.isNotEmpty ? sem.wip : null),
          KpiTile(label: 'أوامر قائمة', value: '${p.liveOrders.length}', onTap: () => app.setTab(AppState.procOrdersTab)),
          KpiTile(label: 'قيمة غير المستلَم', value: _money(p.outstandingValue)),
          KpiTile(label: 'تنبيهات', value: '${alerts.length}', color: alerts.isNotEmpty ? sem.danger : null),
        ]),
        const SizedBox(height: 14),
        ResponsiveGrid(minItemWidth: 340, children: [
          SectionCard(
            title: 'تنبيهات تحتاج انتباهك',
            icon: Icons.notification_important_rounded,
            child: alerts.isEmpty
                ? const Padding(padding: EdgeInsets.all(8), child: Text('لا تنبيهات الآن.'))
                : Column(children: [for (final a in alerts.take(8)) PrAlertTile(alert: a)]),
          ),
          SectionCard(
            title: 'الطلبات بحسب الحالة',
            icon: Icons.stacked_bar_chart_rounded,
            child: Column(children: [
              for (final s in prStatusLabels.keys)
                if ((byStatus[s] ?? 0) > 0)
                  BarRow(
                    title: prStatusLabels[s]!,
                    trailing: '${byStatus[s]}',
                    meter: ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: LinearProgressIndicator(value: (byStatus[s] ?? 0) / total, minHeight: 8, color: prStatusColor(sem, s), backgroundColor: sem.surface2),
                    ),
                  ),
              if (total == 0) const Padding(padding: EdgeInsets.all(8), child: Text('لا طلبات بعد.')),
            ]),
          ),
          SectionCard(
            title: 'آخر الطلبات',
            icon: Icons.history_rounded,
            child: recent.isEmpty ? const Padding(padding: EdgeInsets.all(8), child: Text('لا طلبات بعد.')) : Column(children: [for (final r in recent) PrRequestTile(request: r)]),
          ),
          SectionCard(
            title: 'أوامر شراء بانتظار التوريد',
            icon: Icons.receipt_long_rounded,
            child: p.liveOrders.isEmpty
                ? const Padding(padding: EdgeInsets.all(8), child: Text('لا أوامر قائمة.'))
                : Column(children: [for (final o in p.liveOrders.take(6)) _OrderTile(order: o)]),
          ),
        ]),
      ],
    );
  }
}

class _OrderTile extends StatelessWidget {
  const _OrderTile({required this.order});

  final PrOrder order;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final p = app.proc;
    final sem = Sem.of(context);
    final r = p.request(order.requestId);
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      title: Text('${order.poNo} — ${p.supplier(order.supplierId)?.name ?? ''}'),
      subtitle: Text([r?.title ?? '', if (order.expectedDate != null) 'متوقع ${dayText(order.expectedDate)}'].where((x) => x.isNotEmpty).join(' · ')),
      trailing: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.end, children: [
        Text(_money(order.total), style: _tabular.copyWith(fontWeight: FontWeight.w700)),
        ToneBadge(prOrderStatusLabels[order.status] ?? order.status, color: prOrderColor(sem, order.status)),
      ]),
      onTap: () => openPrRequest(context, order.requestId),
    );
  }
}

// ---------------------------------------------------------------------
// الطلبات
// ---------------------------------------------------------------------

class ProcRequestsPage extends StatefulWidget {
  const ProcRequestsPage({super.key});

  @override
  State<ProcRequestsPage> createState() => _ProcRequestsPageState();
}

class _ProcRequestsPageState extends State<ProcRequestsPage> {
  final _q = TextEditingController();
  String _status = 'open';
  String _priority = '';

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final p = app.proc;
    final q = _q.text.trim();
    final now = DateTime.now();
    final list = [
      for (final r in p.requests)
        if (r.status != 'draft' &&
            (_status == 'all' ||
                (_status == 'open' ? r.isOpen : (_status == 'action' ? const {'submitted', 'reviewed', 'approved'}.contains(r.status) : r.status == _status))) &&
            (_priority.isEmpty || r.priority == _priority) &&
            r.matches(q))
          r,
    ]..sort((a, b) {
        if (a.isOpen != b.isOpen) return a.isOpen ? -1 : 1;
        final pa = prPriorityOrder.indexOf(a.priority), pb = prPriorityOrder.indexOf(b.priority);
        if (a.isOpen && pa != pb) return pa.compareTo(pb);
        return (b.submittedAt ?? now).compareTo(a.submittedAt ?? now);
      });
    return PageBody(
      onRefresh: app.loadAll,
      children: [
        PageHeader(
          title: 'طلبات الاحتياج',
          subtitle: 'كل الطلبات المقدَّمة: مراجعة التوفر، والاعتماد، والعروض، وأمر الشراء، والاستلام.',
          icon: Icons.fact_check_rounded,
          actions: [
            if (app.canPrRequest) FilledButton.icon(onPressed: () => showPrRequestDialog(context), icon: const Icon(Icons.add_rounded), label: const Text('طلب احتياج')),
          ],
        ),
        if (!app.v25Ready) ...[const ProcNotReady(), const SizedBox(height: 14)],
        Wrap(spacing: 10, runSpacing: 10, children: [
          SizedBox(
            width: 260,
            child: TextField(controller: _q, onChanged: (_) => setState(() {}), decoration: fieldDeco('بحث (رقم، عنوان، مقدّم الطلب)', prefixIcon: const Icon(Icons.search_rounded))),
          ),
          SizedBox(
            width: 210,
            child: SelectField(
              label: 'الحالة',
              value: _status,
              items: [('open', 'الجارية'), ('action', 'تنتظر إجراءً'), ('all', 'الكل'), for (final e in prStatusLabels.entries) if (e.key != 'draft') (e.key, e.value)],
              onChanged: (v) => setState(() => _status = v),
            ),
          ),
          SizedBox(
            width: 150,
            child: SelectField(
              label: 'الأولوية',
              value: _priority,
              items: [('', 'الكل'), for (final x in prPriorityOrder) (x, prPriorityLabels[x]!)],
              onChanged: (v) => setState(() => _priority = v),
            ),
          ),
        ]),
        const SizedBox(height: 12),
        SectionCard(
          title: '${list.length} طلب',
          child: list.isEmpty
              ? const EmptyState(title: 'لا طلبات بهذه المعايير', icon: Icons.fact_check_outlined)
              : Column(children: [for (final r in list.take(300)) PrRequestTile(request: r)]),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------
// أوامر الشراء
// ---------------------------------------------------------------------

class ProcOrdersPage extends StatefulWidget {
  const ProcOrdersPage({super.key});

  @override
  State<ProcOrdersPage> createState() => _ProcOrdersPageState();
}

class _ProcOrdersPageState extends State<ProcOrdersPage> {
  String _status = 'live';

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final p = app.proc;
    final list = [
      for (final o in p.orders)
        if (_status == 'all' || (_status == 'live' ? o.isLive : o.status == _status)) o,
    ];
    final sum = list.where((o) => o.status != 'cancelled').fold<double>(0, (t, o) => t + o.total);
    return PageBody(
      onRefresh: app.loadAll,
      children: [
        const PageHeader(
          title: 'أوامر الشراء',
          subtitle: 'الأوامر الصادرة من الطلبات المعتمَدة وما استُلم منها. الاستلام من صفحة الطلب.',
          icon: Icons.receipt_long_rounded,
        ),
        if (!app.v25Ready) ...[const ProcNotReady(), const SizedBox(height: 14)],
        SizedBox(
          width: 220,
          child: SelectField(
            label: 'الحالة',
            value: _status,
            items: [('live', 'القائمة'), ('all', 'الكل'), for (final e in prOrderStatusLabels.entries) (e.key, e.value)],
            onChanged: (v) => setState(() => _status = v),
          ),
        ),
        const SizedBox(height: 12),
        SectionCard(
          title: '${list.length} أمر · الإجمالي ${_money(sum)}',
          child: list.isEmpty
              ? const EmptyState(title: 'لا أوامر بهذه المعايير', icon: Icons.receipt_long_outlined)
              : Column(children: [for (final o in list.take(300)) _OrderTile(order: o)]),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------
// الموردون
// ---------------------------------------------------------------------

Future<void> showPrSupplierDialog(BuildContext context, {PrSupplier? edit}) async {
  final app = AppScope.read(context);
  final name = TextEditingController(text: edit?.name ?? '');
  final contact = TextEditingController(text: edit?.contact ?? '');
  final phone = TextEditingController(text: edit?.phone ?? '');
  final email = TextEditingController(text: edit?.email ?? '');
  final address = TextEditingController(text: edit?.address ?? '');
  final note = TextEditingController(text: edit?.note ?? '');
  var active = edit?.active ?? true;
  await storeFormDialog(
    context,
    title: edit == null ? 'مورّد جديد' : 'تعديل المورّد',
    body: (set) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      TextField(controller: name, decoration: fieldDeco('اسم المورّد')),
      const SizedBox(height: 10),
      TextField(controller: contact, decoration: fieldDeco('المسؤول (اختياري)')),
      const SizedBox(height: 10),
      TextField(controller: phone, keyboardType: TextInputType.phone, textDirection: TextDirection.ltr, decoration: fieldDeco('الهاتف (اختياري)')),
      const SizedBox(height: 10),
      TextField(controller: email, keyboardType: TextInputType.emailAddress, textDirection: TextDirection.ltr, decoration: fieldDeco('البريد (اختياري)')),
      const SizedBox(height: 10),
      TextField(controller: address, decoration: fieldDeco('العنوان (اختياري)')),
      const SizedBox(height: 10),
      TextField(controller: note, decoration: fieldDeco('ملاحظة (اختياري)')),
      SwitchListTile(contentPadding: EdgeInsets.zero, value: active, onChanged: (v) => set(() => active = v), title: const Text('مورّد نشط')),
    ]),
    onSave: () async {
      if (name.text.trim().length < 2) throw StateError('اكتب اسم المورّد (حرفان فأكثر)');
      await app.prSaveSupplier(edit?.id, {
        'name': name.text.trim(),
        'contact': contact.text.trim(),
        'phone': phone.text.trim(),
        'email': email.text.trim(),
        'address': address.text.trim(),
        'note': note.text.trim(),
        'active': active,
      });
    },
  );
  for (final c in [name, contact, phone, email, address, note]) {
    c.dispose();
  }
}

class ProcSuppliersPage extends StatelessWidget {
  const ProcSuppliersPage({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final p = app.proc;
    final sem = Sem.of(context);
    final list = [...p.suppliers]..sort((a, b) => a.name.compareTo(b.name));
    return PageBody(
      onRefresh: app.loadAll,
      children: [
        PageHeader(
          title: 'الموردون',
          subtitle: 'دليل الموردين الذين تُسجَّل عروضهم وتصدر لهم أوامر الشراء.',
          icon: Icons.storefront_rounded,
          actions: [
            if (app.canPrAdmin) FilledButton.icon(onPressed: () => showPrSupplierDialog(context), icon: const Icon(Icons.add_rounded), label: const Text('مورّد جديد')),
          ],
        ),
        if (!app.v25Ready) ...[const ProcNotReady(), const SizedBox(height: 14)],
        SectionCard(
          title: '${list.length} مورّد',
          child: list.isEmpty
              ? const EmptyState(title: 'لا موردين بعد', message: 'يضيف مدير النظام في المشتريات الموردين ليسجَّل لهم العروض.', icon: Icons.storefront_outlined)
              : Column(children: [
                  for (final s in list)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(s.name),
                      subtitle: Text([s.contact, s.phone, s.email].where((x) => x.isNotEmpty).join(' · ')),
                      trailing: s.active ? null : ToneBadge('موقوف', color: sem.muted),
                      onTap: app.canPrAdmin ? () => showPrSupplierDialog(context, edit: s) : null,
                    ),
                ]),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------
// طلباتي
// ---------------------------------------------------------------------

class ProcMinePage extends StatelessWidget {
  const ProcMinePage({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final p = app.proc;
    final mine = p.requestedBy(app.me?.id);
    final drafts = mine.where((r) => r.isDraft).length;
    return PageBody(
      onRefresh: app.loadAll,
      children: [
        PageHeader(
          title: 'طلباتي',
          subtitle: 'ارفع طلب احتياج من مواد أو أصول، وتابع مراجعته واعتماده وتوريده.',
          icon: Icons.shopping_basket_rounded,
          actions: [
            if (app.canPrRequest) FilledButton.icon(onPressed: () => showPrRequestDialog(context), icon: const Icon(Icons.add_rounded), label: const Text('طلب احتياج')),
          ],
        ),
        if (!app.v25Ready) ...[const ProcNotReady(), const SizedBox(height: 14)],
        if (drafts > 0) ...[
          InfoBanner(text: 'عندك $drafts مسودة لم تُقدَّم بعد: افتحها وقدّمها لتصل إلى المراجعة.'),
          const SizedBox(height: 14),
        ],
        SectionCard(
          title: '${mine.length} طلب',
          child: mine.isEmpty
              ? const EmptyState(title: 'لم ترفع طلبات بعد', message: 'اضغط «طلب احتياج» حين تحتاج مواد أو أصولاً لعملك.', icon: Icons.shopping_basket_outlined)
              : Column(children: [for (final r in mine) PrRequestTile(request: r, showRequester: false)]),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------
// الإعدادات
// ---------------------------------------------------------------------

class ProcSetupPage extends StatefulWidget {
  const ProcSetupPage({super.key});

  @override
  State<ProcSetupPage> createState() => _ProcSetupPageState();
}

class _ProcSetupPageState extends State<ProcSetupPage> {
  final Map<String, TextEditingController> _c = {};
  String _loaded = '';

  static const _labels = {
    'min_quotes': ('الحد الأدنى لعدد العروض قبل أمر الشراء', '1 إلى 10'),
    'review_days': ('مهلة مراجعة التوفر (أيام)', '0 إلى 60'),
    'approve_days': ('مهلة اعتماد المدير (أيام)', '0 إلى 60'),
    'grace_days': ('مهلة السماح للأمر والتوريد (أيام)', '0 إلى 60'),
  };

  @override
  void dispose() {
    for (final c in _c.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final st = app.proc.settings;
    final stamp = prDefaultSettings.keys.map((k) => '$k=${st.get(k)}').join('|');
    if (stamp != _loaded) {
      _loaded = stamp;
      for (final k in prDefaultSettings.keys) {
        (_c[k] ??= TextEditingController()).text = '${st.get(k)}';
      }
    }
    return PageBody(
      onRefresh: app.loadAll,
      children: [
        const PageHeader(
          title: 'إعدادات المشتريات',
          subtitle: 'الحد الأدنى للعروض ومهل التنبيه. تُقرأ في الدليل قيماً حية.',
          icon: Icons.settings_suggest_rounded,
        ),
        if (!app.v25Ready) ...[const ProcNotReady(), const SizedBox(height: 14)],
        SectionCard(
          title: 'القواعد',
          icon: Icons.rule_rounded,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            for (final e in _labels.entries) ...[
              TextField(
                controller: _c[e.key],
                keyboardType: TextInputType.number,
                enabled: app.canPrAdmin,
                decoration: fieldDeco('${e.value.$1} — ${e.value.$2}'),
              ),
              const SizedBox(height: 10),
            ],
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: FilledButton.icon(
                onPressed: !app.canPrAdmin
                    ? null
                    : () async {
                        final data = <String, dynamic>{};
                        for (final k in prDefaultSettings.keys) {
                          final n = int.tryParse(_c[k]!.text.trim());
                          if (n == null) {
                            showToast(context, 'كل إعداد عدد صحيح', error: true);
                            return;
                          }
                          data[k] = n;
                        }
                        await storesRun(context, () => app.prSaveSettings(data), success: 'حُفظت الإعدادات');
                      },
                icon: const Icon(Icons.save_rounded),
                label: const Text('حفظ'),
              ),
            ),
          ]),
        ),
      ],
    );
  }
}
