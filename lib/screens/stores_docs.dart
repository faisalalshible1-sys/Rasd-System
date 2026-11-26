import 'package:flutter/material.dart';

import '../app_state.dart';
import '../docs.dart' show isolate;
import '../models.dart';
import '../print/export_dialog.dart' show ExportButton;
import '../stores.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';
import 'contract_finance.dart' show DayField;
import 'stores.dart';
import 'stores_setup.dart' show pickOpeningLines;

// =====================================================================
// مستندات المخزون (الإصدار 1.7.0): أول المدة والوارد والصرف والمرتجع والتحويل والتسوية.
// مسودة ← مقدَّم ← معتمد (يحجز الخارج) ← مرحَّل (يغيّر الرصيد). المرحَّل يُصحَّح بمستند عكسي.
// =====================================================================

const _tabular = TextStyle(fontFeatures: [FontFeature.tabularFigures()]);

/// زر «مستند جديد» بقائمة الأنواع.
class NewStoreDocButton extends StatelessWidget {
  const NewStoreDocButton({super.key, required this.app});

  final AppState app;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: 'مستند جديد',
      onSelected: (k) => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => StoreDocEditorPage(kind: k))),
      itemBuilder: (_) => [
        for (final e in stDocKindLabels.entries) PopupMenuItem(value: e.key, child: Text(e.value)),
      ],
      child: IgnorePointer(
        child: FilledButton.icon(onPressed: () {}, icon: const Icon(Icons.add_rounded), label: const Text('مستند جديد')),
      ),
    );
  }
}

/// سطر مستند في القوائم.
class StoreDocTile extends StatelessWidget {
  const StoreDocTile({super.key, required this.doc});

  final StDoc doc;

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context).stores;
    final sem = Sem.of(context);
    final where = doc.kind == 'transfer'
        ? 'من ${s.warehouseName(doc.warehouseId)} إلى ${s.warehouseName(doc.toWarehouseId)}'
        : s.warehouseName(doc.warehouseId);
    final who = doc.hasRecipient ? s.recipientOf(doc) : doc.party;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      leading: Icon(_kindIcon(doc.kind), color: sem.muted),
      // الرقم أولاً ثم النوع المختصر، حتى لا ينكسر السطر على الهاتف
      title: Text.rich(TextSpan(children: [
        TextSpan(text: isolate(doc.docNo), style: const TextStyle(fontWeight: FontWeight.w600)),
        TextSpan(
            text: ' · ${doc.isReversal ? 'عكس ' : ''}${stDocKindLabels[doc.kind] ?? doc.kind}',
            style: TextStyle(color: sem.muted, fontWeight: FontWeight.w500)),
      ])),
      subtitle: Text([dayText(doc.docDate), where, if (who.isNotEmpty) who, arCount(s.linesOf(doc.id).length, one: 'بند', two: 'بندان', few: 'بنود', many: 'بنداً')].join(' · '),
          maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: sem.muted, fontSize: 12.5)),
      trailing: ToneBadge(doc.statusLabel, color: storeDocStatusColor(sem, doc.status)),
      onTap: () => openStoreDoc(context, doc.id),
    );
  }
}

IconData _kindIcon(String kind) => switch (kind) {
      'opening' => Icons.inventory_rounded,
      'receipt' => Icons.move_to_inbox_rounded,
      'issue' => Icons.outbox_rounded,
      'return' => Icons.assignment_return_outlined,
      'transfer' => Icons.swap_horiz_rounded,
      _ => Icons.tune_rounded,
    };

void openStoreDoc(BuildContext context, String id) {
  Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => StoreDocPage(docId: id)));
}

// ---------------------------------------------------------------------
// قائمة المستندات
// ---------------------------------------------------------------------

class StoresDocsPage extends StatefulWidget {
  const StoresDocsPage({super.key});

  @override
  State<StoresDocsPage> createState() => _StoresDocsPageState();
}

class _StoresDocsPageState extends State<StoresDocsPage> {
  final _q = TextEditingController();
  String _kind = '';
  String _status = '';
  String _wh = '';
  int _shown = 150;

  @override
  void initState() {
    super.initState();
    final app = AppScope.read(context);
    final st = app.storesDocsStatus;
    if (st != null) {
      _status = st;
      app.storesDocsStatus = null;
    }
  }

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final s = app.stores;
    final sem = Sem.of(context);
    final q = normalizeArabic(_q.text);
    final list = [
      for (final d in s.docs)
        if ((_kind.isEmpty || d.kind == _kind) &&
            (_status.isEmpty || (_status == 'open' ? d.isOpen : d.status == _status)) &&
            (_wh.isEmpty || d.warehouseId == _wh || d.toWarehouseId == _wh) &&
            (q.isEmpty ||
                d.docNo.toLowerCase().contains(_q.text.trim().toLowerCase()) ||
                normalizeArabic(s.recipientOf(d)).contains(q) ||
                normalizeArabic(d.party).contains(q) ||
                d.refNo.contains(_q.text.trim())))
          d,
    ];
    return PageBody(
      onRefresh: app.loadAll,
      children: [
        PageHeader(
          title: 'المستندات',
          subtitle: 'أول المدة والوارد والصرف والمرتجع والتحويل والتسوية. لا يتغير رصيد إلا بترحيل مستند معتمد.',
          icon: Icons.receipt_long_rounded,
          actions: [
            if (app.storesMovableWarehouses.isNotEmpty) NewStoreDocButton(app: app),
            if (app.v22Ready) ExportButton(sourceId: 'stores:docs', items: list),
          ],
        ),
        if (!app.v22Ready) ...[const StoresNotReady(), const SizedBox(height: 14)],
        Wrap(spacing: 10, runSpacing: 10, children: [
          SizedBox(
            width: 260,
            child: TextField(
              controller: _q,
              onChanged: (_) => setState(() {}),
              decoration: fieldDeco('بحث بالرقم أو المستلم أو المورد', prefixIcon: const Icon(Icons.search_rounded)),
            ),
          ),
          SizedBox(
            width: 190,
            child: SelectField(
              label: 'النوع',
              value: _kind,
              items: [('', 'كل الأنواع'), for (final e in stDocKindLabels.entries) (e.key, e.value)],
              onChanged: (v) => setState(() => _kind = v),
            ),
          ),
          SizedBox(
            width: 220,
            child: SelectField(
              label: 'الحالة',
              value: _status,
              items: [('', 'كل الحالات'), ('open', 'المفتوحة (لم تُرحَّل)'), for (final e in stDocStatusLabels.entries) (e.key, e.value)],
              onChanged: (v) => setState(() => _status = v),
            ),
          ),
          SizedBox(
            width: 220,
            child: SelectField(
              label: 'المخزن',
              value: _wh,
              items: [('', 'كل المخازن'), for (final w in s.warehouses) (w.id, w.name)],
              onChanged: (v) => setState(() => _wh = v),
            ),
          ),
        ]),
        const SizedBox(height: 12),
        if (list.isEmpty)
          EmptyState(
            title: s.docs.isEmpty ? 'لا مستندات بعد' : 'لا مستند مطابق',
            message: s.docs.isEmpty ? 'ابدأ بمستند أرصدة أول المدة لكل مخزن، ثم الوارد والصرف.' : null,
            icon: Icons.receipt_long_outlined,
          )
        else
          SectionCard(
            title: 'المستندات (${list.length})',
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
            child: Column(children: [
              for (final d in list.take(_shown)) StoreDocTile(doc: d),
              if (list.length > _shown)
                TextButton(onPressed: () => setState(() => _shown += 150), child: Text('عرض المزيد (${list.length - _shown})')),
            ]),
          ),
        if (s.docs.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text('المسودة لا أثر لها، والمعتمد يحجز كميته الخارجة، والمرحَّل وحده يغيّر الرصيد.', style: TextStyle(color: sem.muted, fontSize: 12.5)),
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------------
// محرر المستند (مسودة)
// ---------------------------------------------------------------------

class _LineDraft {
  _LineDraft({required this.itemId, required this.unitId, String qty = '', this.expiry, String batch = '', String note = ''})
      : qty = TextEditingController(text: qty),
        batch = TextEditingController(text: batch),
        note = TextEditingController(text: note);

  String itemId;
  String unitId;
  final TextEditingController qty;
  DateTime? expiry;
  final TextEditingController batch;
  final TextEditingController note;

  void dispose() {
    qty.dispose();
    batch.dispose();
    note.dispose();
  }
}

class StoreDocEditorPage extends StatefulWidget {
  const StoreDocEditorPage({super.key, required this.kind, this.docId});

  final String kind;

  /// مسودة قائمة للتعديل (null: جديد).
  final String? docId;

  @override
  State<StoreDocEditorPage> createState() => _StoreDocEditorPageState();
}

class _StoreDocEditorPageState extends State<StoreDocEditorPage> {
  String _wh = '';
  String _to = '';
  String? _emp;
  String _dep = '';
  DateTime? _date;
  final _party = TextEditingController();
  final _ref = TextEditingController();
  final _note = TextEditingController();
  final List<_LineDraft> _lines = [];
  bool _busy = false;
  String? _error;

  bool get _incoming => widget.kind == 'opening' || widget.kind == 'receipt' || widget.kind == 'return';

  @override
  void initState() {
    super.initState();
    final app = AppScope.read(context);
    final s = app.stores;
    final d = s.doc(widget.docId);
    if (d != null) {
      _wh = d.warehouseId;
      _to = d.toWarehouseId ?? '';
      _emp = d.employeeId;
      _dep = d.departmentId ?? '';
      _date = d.docDate;
      _party.text = d.party;
      _ref.text = d.refNo;
      _note.text = d.note;
      for (final l in s.linesOf(d.id)) {
        _lines.add(_LineDraft(
          itemId: l.itemId,
          unitId: l.unitId,
          qty: fmtQty(l.qty).replaceAll(',', ''),
          expiry: l.expiryDate,
          batch: l.batchNo,
          note: l.note,
        ));
      }
    } else {
      final mine = app.storesMovableWarehouses;
      if (mine.isNotEmpty) _wh = mine.first.id;
      _date = DateTime.now();
    }
  }

  @override
  void dispose() {
    _party.dispose();
    _ref.dispose();
    _note.dispose();
    for (final l in _lines) {
      l.dispose();
    }
    super.dispose();
  }

  Future<void> _addItem() async {
    final it = await pickStoreItem(context);
    if (it == null || !mounted) return;
    setState(() => _lines.add(_LineDraft(itemId: it.id, unitId: it.baseUnitId)));
  }

  Future<void> _importLines() async {
    final rows = await pickOpeningLines(context);
    if (rows == null || !mounted) return;
    setState(() {
      for (final r in rows) {
        _lines.add(_LineDraft(itemId: r.itemId, unitId: r.unitId, qty: fmtQty(r.qty).replaceAll(',', ''), expiry: r.expiry, batch: r.batch));
      }
    });
    showToast(context, 'أُضيف ${rows.length} بنداً من الملف؛ راجعها ثم احفظ.');
  }

  Map<String, dynamic>? _payload() {
    final s = AppScope.read(context).stores;
    if (_wh.isEmpty) {
      setState(() => _error = 'اختر المخزن.');
      return null;
    }
    if (widget.kind == 'transfer' && (_to.isEmpty || _to == _wh)) {
      setState(() => _error = 'اختر المخزن المحوَّل إليه (غير المحوَّل منه).');
      return null;
    }
    if ((widget.kind == 'issue' || widget.kind == 'return') && _emp == null && _dep.isEmpty) {
      setState(() => _error = 'حدّد الموظف أو الإدارة.');
      return null;
    }
    if (_lines.isEmpty) {
      setState(() => _error = 'أضف بنداً واحداً على الأقل.');
      return null;
    }
    final lines = <Map<String, dynamic>>[];
    for (var i = 0; i < _lines.length; i++) {
      final l = _lines[i];
      final it = s.item(l.itemId);
      final q = parseImportNumber(l.qty.text);
      if (q == null || q == 0 || (widget.kind != 'adjust' && q < 0)) {
        setState(() => _error = 'البند ${i + 1}: اكتب كمية ${widget.kind == 'adjust' ? 'موجبة للزيادة أو سالبة للنقص' : 'موجبة'}.');
        return null;
      }
      final needExpiry = (it?.tracksExpiry ?? false) && (_incoming || (widget.kind == 'adjust' && q > 0));
      if (needExpiry && l.expiry == null) {
        setState(() => _error = 'البند ${i + 1}: حدّد تاريخ انتهاء صلاحية «${it?.name ?? ''}».');
        return null;
      }
      lines.add({
        'item_id': l.itemId,
        'unit_id': l.unitId,
        'qty': q,
        if (needExpiry) 'expiry_date': dbDate(l.expiry!),
        if (needExpiry) 'batch_no': l.batch.text.trim(),
        'note': l.note.text.trim(),
      });
    }
    return {
      'kind': widget.kind,
      'warehouse_id': _wh,
      if (widget.kind == 'transfer') 'to_warehouse_id': _to,
      if (_emp != null) 'employee_id': _emp,
      if (_dep.isNotEmpty) 'department_id': _dep,
      'doc_date': dbDate(_date ?? DateTime.now()),
      'party': _party.text.trim(),
      'ref_no': _ref.text.trim(),
      'note': _note.text.trim(),
      'lines': lines,
    };
  }

  Future<void> _save({required bool submit}) async {
    setState(() => _error = null);
    final data = _payload();
    if (data == null) return;
    setState(() => _busy = true);
    final app = AppScope.read(context);
    try {
      final id = await app.stSaveDoc(widget.docId, data);
      if (submit) await app.stDocAction(id, 'submit');
      if (!mounted) return;
      showToast(context, submit ? 'حُفظ المستند وقُدّم للاعتماد' : 'حُفظ المستند مسودة');
      final nav = Navigator.of(context);
      if (widget.docId == null) {
        nav.pushReplacement(MaterialPageRoute<void>(builder: (_) => StoreDocPage(docId: id)));
      } else {
        nav.pop();
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
    final s = app.stores;
    final sem = Sem.of(context);
    final whs = app.storesMovableWarehouses;
    final emp = s.employee(_emp);
    return Scaffold(
      appBar: AppBar(title: Text(widget.docId == null ? stDocKindTitles[widget.kind] ?? 'مستند' : 'تعديل المسودة')),
      body: PageBody(maxWidth: 980, children: [
        SectionCard(
          title: 'بيانات المستند',
          icon: _kindIcon(widget.kind),
          subtitle: switch (widget.kind) {
            'opening' => 'أرصدة المخزن عند بدء العمل بالمنظومة. لا تؤثر في الرصيد قبل اعتمادها وترحيلها.',
            'receipt' => 'ما ورد إلى المخزن من مورد أو جهة، برقم الفاتورة أو محضر الاستلام.',
            'issue' => 'ما يُصرف لموظف أو إدارة. يحجز الاعتماد الكمية، ويُنقص الترحيل الرصيد.',
            'return' => 'ما أرجعه موظف أو إدارة إلى المخزن.',
            'transfer' => 'نقل كمية من مخزن إلى آخر بدفعاتها.',
            _ => 'تصحيح الرصيد بعد جرد أو تلف: موجبة للزيادة وسالبة للنقص.',
          },
          child: Wrap(spacing: 12, runSpacing: 12, children: [
            SizedBox(
              width: 260,
              child: SelectField(
                label: widget.kind == 'transfer' ? 'من المخزن' : 'المخزن',
                value: _wh,
                items: [for (final w in whs) (w.id, w.name)],
                onChanged: (v) => setState(() => _wh = v),
              ),
            ),
            if (widget.kind == 'transfer')
              SizedBox(
                width: 260,
                child: SelectField(
                  label: 'إلى المخزن',
                  value: _to,
                  items: [('', 'اختر المخزن'), for (final w in s.warehouses) if (w.active && w.id != _wh) (w.id, w.name)],
                  onChanged: (v) => setState(() => _to = v),
                ),
              ),
            if (widget.kind == 'issue' || widget.kind == 'return') ...[
              SizedBox(
                width: 300,
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () async {
                    final e = await pickStoreEmployee(context);
                    if (e != null) {
                      setState(() {
                        _emp = e.id;
                        if (e.departmentId != null) _dep = e.departmentId!;
                      });
                    }
                  },
                  child: InputDecorator(
                    decoration: fieldDeco(widget.kind == 'issue' ? 'الموظف المصروف له' : 'الموظف المُرجِع',
                        prefixIcon: const Icon(Icons.person_search_outlined),
                        suffix: _emp == null
                            ? null
                            : IconButton(tooltip: 'مسح', icon: const Icon(Icons.close_rounded, size: 18), onPressed: () => setState(() => _emp = null))),
                    child: Text(emp?.label ?? 'اختياري: اختر من سجل الموظفين', style: TextStyle(color: emp == null ? sem.muted : null)),
                  ),
                ),
              ),
              SizedBox(
                width: 260,
                child: SelectField(
                  label: 'الإدارة',
                  value: _dep,
                  items: [('', 'من سجل الموظف'), for (final d in s.departments) if (d.active || d.id == _dep) (d.id, s.departmentPath(d.id))],
                  onChanged: (v) => setState(() => _dep = v),
                ),
              ),
            ],
            SizedBox(width: 200, child: DayField(label: 'تاريخ المستند', value: _date, onChanged: (v) => setState(() => _date = v))),
            if (widget.kind == 'receipt' || widget.kind == 'opening') ...[
              SizedBox(width: 260, child: TextField(controller: _party, decoration: fieldDeco(widget.kind == 'receipt' ? 'المورد أو الجهة' : 'المصدر (اختياري)'))),
              SizedBox(width: 200, child: TextField(controller: _ref, decoration: fieldDeco('رقم الفاتورة أو المحضر'))),
            ],
            SizedBox(width: 560, child: TextField(controller: _note, minLines: 1, maxLines: 3, decoration: fieldDeco('ملاحظات'))),
          ]),
        ),
        const SizedBox(height: 14),
        Builder(builder: (context) {
          // على الهاتف تنزل الأزرار تحت العنوان حتى لا تضغطه
          final narrow = MediaQuery.sizeOf(context).width < 640;
          final buttons = Wrap(spacing: 8, runSpacing: 8, children: [
            if (widget.kind == 'opening' || widget.kind == 'receipt')
              OutlinedButton.icon(onPressed: _importLines, icon: const Icon(Icons.upload_file_rounded), label: const Text('من ملف Excel')),
            FilledButton.tonalIcon(onPressed: _addItem, icon: const Icon(Icons.add_rounded), label: const Text('إضافة صنف')),
          ]);
          return SectionCard(
            title: 'البنود (${_lines.length})',
            icon: Icons.list_alt_rounded,
            trailing: narrow ? null : buttons,
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              if (narrow) ...[Align(alignment: AlignmentDirectional.centerStart, child: buttons), const SizedBox(height: 12)],
              if (_lines.isEmpty)
                Text('أضف الأصناف بالبحث أو بقارئ الباركود.', style: TextStyle(color: sem.muted))
              else
                for (var i = 0; i < _lines.length; i++) _lineEditor(s, i),
            ]),
          );
        }),
        if (_error != null) ...[const SizedBox(height: 12), InfoBanner(level: 'critical', text: _error!)],
        const SizedBox(height: 14),
        Wrap(spacing: 10, runSpacing: 10, alignment: WrapAlignment.end, children: [
          OutlinedButton(onPressed: _busy ? null : () => _save(submit: false), child: const Text('حفظ مسودة')),
          FilledButton.icon(
            onPressed: _busy ? null : () => _save(submit: true),
            icon: const Icon(Icons.send_rounded),
            label: const Text('حفظ وتقديم للاعتماد'),
          ),
        ]),
      ]),
    );
  }

  Widget _lineEditor(StoresData s, int i) {
    final sem = Sem.of(context);
    final l = _lines[i];
    final it = s.item(l.itemId);
    if (it == null) return const SizedBox.shrink();
    final units = s.unitsOf(it);
    final q = parseImportNumber(l.qty.text) ?? 0;
    final f = s.factorOf(it, l.unitId) ?? 1;
    final outgoing = widget.kind == 'issue' || widget.kind == 'transfer' || (widget.kind == 'adjust' && q < 0);
    final avail = _wh.isEmpty ? 0.0 : s.available(it.id, warehouseId: _wh);
    final needExpiry = it.tracksExpiry && (_incoming || (widget.kind == 'adjust' && q > 0));
    final short = outgoing && (q * f).abs() > avail + 1e-9;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(border: Border.all(color: sem.rule), borderRadius: BorderRadius.circular(12)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          CircleAvatar(radius: 12, child: Text('${i + 1}', style: const TextStyle(fontSize: 11))),
          const SizedBox(width: 8),
          Expanded(child: Text('${it.name} · ${isolate(it.code)}', style: const TextStyle(fontWeight: FontWeight.w700))),
          IconButton(
            tooltip: 'حذف البند',
            icon: const Icon(Icons.delete_outline_rounded),
            onPressed: () => setState(() => _lines.removeAt(i).dispose()),
          ),
        ]),
        const SizedBox(height: 8),
        Wrap(spacing: 10, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.center, children: [
          SizedBox(
            width: 150,
            child: TextField(
              controller: l.qty,
              keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
              textDirection: TextDirection.ltr,
              onChanged: (_) => setState(() {}),
              decoration: fieldDeco('الكمية'),
            ),
          ),
          SizedBox(
            width: 170,
            child: SelectField(
              label: 'الوحدة',
              value: l.unitId,
              items: [for (final u in units) (u.$1, u.$3 == 1 ? u.$2 : '${u.$2} (${fmtQty(u.$3)})')],
              onChanged: (v) => setState(() => l.unitId = v),
            ),
          ),
          if (needExpiry) ...[
            SizedBox(width: 190, child: DayField(label: 'تاريخ الانتهاء', value: l.expiry, onChanged: (v) => setState(() => l.expiry = v))),
            SizedBox(width: 140, child: TextField(controller: l.batch, decoration: fieldDeco('الدفعة (اختياري)'))),
          ],
          SizedBox(width: 220, child: TextField(controller: l.note, decoration: fieldDeco('ملاحظة'))),
        ]),
        const SizedBox(height: 6),
        Text(
          [
            if (f != 1 && q != 0) 'تعادل ${qtyWithUnit(q * f, s.unitName(it.baseUnitId))}',
            if (_wh.isNotEmpty) 'المتاح في المخزن ${qtyWithUnit(avail, s.unitName(it.baseUnitId))}',
          ].join(' · '),
          style: TextStyle(color: short ? sem.danger : sem.muted, fontSize: 12.5, fontWeight: short ? FontWeight.w700 : null),
        ),
      ]),
    );
  }
}

// ---------------------------------------------------------------------
// صفحة المستند: بياناته وبنوده وإجراءات مساره
// ---------------------------------------------------------------------

class StoreDocPage extends StatelessWidget {
  const StoreDocPage({super.key, required this.docId});

  final String docId;

  Future<void> _act(BuildContext context, StDoc d, String action) async {
    final app = AppScope.read(context);
    var note = '';
    var override = false;
    switch (action) {
      case 'return':
      case 'reject':
        final n = await textInputDialog(context,
            title: action == 'return' ? 'إعادة المستند للتعديل' : 'رفض المستند',
            label: action == 'return' ? 'سبب الإعادة' : 'سبب الرفض',
            confirmLabel: action == 'return' ? 'إعادة' : 'رفض',
            required: true);
        if (n == null) return;
        note = n;
      case 'cancel':
        final n = await textInputDialog(context,
            title: 'إلغاء المستند',
            message: d.isApproved ? 'يُفك حجز كمياته، ويبقى المستند ملغى في السجل.' : 'يبقى المستند ملغى في السجل.',
            label: 'سبب الإلغاء',
            confirmLabel: 'إلغاء المستند',
            required: d.isApproved);
        if (n == null) return;
        note = n;
      case 'approve':
        final crit = app.stores.criticalTouches(d);
        if (crit.isNotEmpty) {
          final names = crit.map((c) => '«${c.$1.name}» (الاحتياطي ${fmtQty(c.$1.criticalQty)})').join('، ');
          final n = await textInputDialog(context,
              title: 'استثناء الاحتياطي الحرج',
              message: 'صرف $names يمس الاحتياطي الحرج. الاعتماد استثناء يُسجَّل بسببه في سجل التدقيق.',
              label: 'سبب الاستثناء',
              confirmLabel: 'اعتماد بالاستثناء',
              required: true);
          if (n == null) return;
          note = n;
          override = true;
        } else {
          final ok = await confirmDialog(context,
              title: 'اعتماد ${d.title}؟',
              message: d.direction < 0 || d.kind == 'adjust' ? 'تُحجز الكميات الخارجة حتى الترحيل.' : 'يصير جاهزاً للترحيل إلى الأرصدة.',
              confirmLabel: 'اعتماد');
          if (!ok) return;
        }
      case 'post':
        final ok = await confirmDialog(context,
            title: 'ترحيل ${d.title}؟',
            message: 'تتغير الأرصدة ويُكتب في بطاقات الأصناف، ولا يُعدَّل المستند بعدها (يُصحَّح بمستند عكسي).',
            confirmLabel: 'ترحيل');
        if (!ok) return;
      case 'submit':
        break;
    }
    if (!context.mounted) return;
    await storesRun(context, () => app.stDocAction(d.id, action, note: note, override: override), success: switch (action) {
      'submit' => 'قُدّم المستند للاعتماد',
      'return' => 'أُعيد المستند للتعديل',
      'reject' => 'رُفض المستند',
      'approve' => 'اعتُمد المستند',
      'post' => 'رُحّل المستند إلى الأرصدة',
      _ => 'أُلغي المستند',
    });
  }

  Future<void> _reverse(BuildContext context, StDoc d) async {
    final app = AppScope.read(context);
    final n = await textInputDialog(context,
        title: 'عكس ${d.title} ${d.docNo}',
        message: 'يُنشأ مستند عكسي مسودة بالبنود نفسها، يمر بالتقديم والاعتماد والترحيل، فيعيد الكميات كما كانت بدفعاتها.',
        label: 'سبب العكس',
        confirmLabel: 'إنشاء المستند العكسي',
        required: true);
    if (n == null || !context.mounted) return;
    try {
      final id = await app.stReverseDoc(d.id, n);
      if (context.mounted) {
        showToast(context, 'أُنشئ المستند العكسي مسودة');
        Navigator.of(context).pushReplacement(MaterialPageRoute<void>(builder: (_) => StoreDocPage(docId: id)));
      }
    } catch (e) {
      if (context.mounted) showToast(context, friendlyError(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final s = app.stores;
    final sem = Sem.of(context);
    final d = s.doc(docId);
    if (d == null) return Scaffold(appBar: AppBar(), body: const EmptyState(title: 'المستند غير موجود أو لا تملك الاطلاع عليه'));
    final lines = s.linesOf(d.id);
    final canMove = app.canStoresMove(d.warehouseId);
    final orig = s.doc(d.reversesId);
    final reversal = [for (final x in s.docs) if (x.reversesId == d.id && !x.isClosed) x];
    String who(String? id) => id == null ? '' : (app.people[id]?.displayName ?? '');
    final shortages = d.isSubmitted ? s.shortages(d) : const <(StItem, double, double)>[];
    final critical = d.isSubmitted && shortages.isEmpty ? s.criticalTouches(d) : const <(StItem, double, double)>[];
    final actions = <Widget>[
      if (d.isDraft && canMove && !d.isReversal)
        OutlinedButton.icon(
          onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => StoreDocEditorPage(kind: d.kind, docId: d.id))),
          icon: const Icon(Icons.edit_outlined),
          label: const Text('تعديل'),
        ),
      if (d.isDraft && canMove) FilledButton.icon(onPressed: () => _act(context, d, 'submit'), icon: const Icon(Icons.send_rounded), label: const Text('تقديم للاعتماد')),
      if (d.isSubmitted && app.canStoresApprove) ...[
        if (app.canApproveStoreDoc(d))
          FilledButton.icon(onPressed: () => _act(context, d, 'approve'), icon: const Icon(Icons.verified_rounded), label: const Text('اعتماد')),
        OutlinedButton(onPressed: () => _act(context, d, 'return'), child: const Text('إعادة للتعديل')),
        OutlinedButton(onPressed: () => _act(context, d, 'reject'), child: Text('رفض', style: TextStyle(color: sem.danger))),
      ],
      if (d.isApproved && canMove)
        FilledButton.icon(onPressed: () => _act(context, d, 'post'), icon: const Icon(Icons.done_all_rounded), label: const Text('ترحيل إلى الأرصدة')),
      if ((d.isDraft || d.isSubmitted) && (canMove || app.canStoresApprove) && !d.deletable)
        TextButton(onPressed: () => _act(context, d, 'cancel'), child: const Text('إلغاء المستند')),
      if (d.isApproved && app.canStoresApprove) TextButton(onPressed: () => _act(context, d, 'cancel'), child: const Text('إلغاء وفك الحجز')),
      if (d.deletable && canMove)
        TextButton(
          onPressed: () async {
            final ok = await confirmDialog(context, title: 'حذف المسودة؟', message: 'لم تُقدَّم قط، ويبقى أثرها في سجل التدقيق.', confirmLabel: 'حذف', danger: true);
            if (!ok || !context.mounted) return;
            final done = await storesRun(context, () => app.stDeleteDoc(d.id), success: 'حُذفت المسودة');
            if (done && context.mounted) Navigator.of(context).pop();
          },
          child: Text('حذف المسودة', style: TextStyle(color: sem.danger)),
        ),
      if (d.isPosted && !d.isReversal && reversal.isEmpty && app.canStoresApprove)
        OutlinedButton.icon(onPressed: () => _reverse(context, d), icon: const Icon(Icons.undo_rounded), label: const Text('عكس بمستند عكسي')),
      ExportButton(sourceId: 'stores:lines', items: lines),
    ];
    return Scaffold(
      appBar: AppBar(title: Text('${d.title} ${isolate(d.docNo)}')),
      body: PageBody(maxWidth: 980, children: [
        Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
          ToneBadge(d.statusLabel, color: storeDocStatusColor(sem, d.status)),
          if (d.isReversal && orig != null)
            ActionChip(
              avatar: const Icon(Icons.undo_rounded, size: 16),
              label: Text('يعكس ${orig.docNo}'),
              onPressed: () => openStoreDoc(context, orig.id),
            ),
          for (final r in reversal)
            ActionChip(avatar: const Icon(Icons.undo_rounded, size: 16), label: Text('عُكس بالمستند ${r.docNo}'), onPressed: () => openStoreDoc(context, r.id)),
          if (d.confirmedAt != null) ToneBadge('أكّد الموظف الاستلام ${dayText(d.confirmedAt)}', color: sem.ok, icon: Icons.verified_outlined),
        ]),
        const SizedBox(height: 12),
        if (d.decisionNote.isNotEmpty && (d.isDraft || d.isClosed))
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: InfoBanner(level: d.isClosed ? 'critical' : 'warning', text: 'السبب: ${d.decisionNote}'),
          ),
        if (d.overrideNote.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: InfoBanner(level: 'warning', icon: Icons.shield_outlined, text: 'اعتُمد باستثناء الاحتياطي الحرج: ${d.overrideNote}'),
          ),
        if (shortages.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: InfoBanner(
              level: 'critical',
              text: 'المتاح لا يكفي: ${shortages.map((x) => '«${x.$1.name}» المتاح ${fmtQty(x.$2)} والمطلوب ${fmtQty(x.$3)}').join('، ')}. أعده للتعديل أو انتظر وارداً.',
            ),
          ),
        if (critical.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: InfoBanner(
              level: 'warning',
              icon: Icons.shield_outlined,
              text: 'يمس الاحتياطي الحرج: ${critical.map((x) => '«${x.$1.name}» المتاح ${fmtQty(x.$2)} والمطلوب ${fmtQty(x.$3)} والاحتياطي ${fmtQty(x.$1.criticalQty)}').join('، ')}. '
                  'اعتماده استثناء من مدير المخازن بسبب مكتوب.',
            ),
          ),
        if (d.isSubmitted && app.canStoresApprove && !app.canApproveStoreDoc(d))
          const Padding(
            padding: EdgeInsets.only(bottom: 12),
            child: InfoBanner(text: 'فصل المهام: أنشأتَ هذا المستند أو قدّمته، فيعتمده مدير مخازن آخر أو المدير.'),
          ),
        SectionCard(
          title: 'بيانات المستند',
          icon: _kindIcon(d.kind),
          child: Wrap(spacing: 22, runSpacing: 10, children: [
            _Info('النوع', d.kindLabel),
            _Info(d.kind == 'transfer' ? 'من المخزن' : 'المخزن', s.warehouseName(d.warehouseId)),
            if (d.kind == 'transfer') _Info('إلى المخزن', s.warehouseName(d.toWarehouseId)),
            if (d.hasRecipient) _Info(d.kind == 'issue' ? 'المصروف له' : 'المُرجِع', s.recipientOf(d)),
            _Info('تاريخ المستند', dayText(d.docDate)),
            if (d.party.isNotEmpty) _Info('المورد أو الجهة', d.party),
            if (d.refNo.isNotEmpty) _Info('رقم الفاتورة أو المحضر', d.refNo),
            if (d.note.isNotEmpty) _Info('ملاحظات', d.note),
          ]),
        ),
        const SizedBox(height: 14),
        SectionCard(
          title: 'البنود (${lines.length})',
          icon: Icons.list_alt_rounded,
          child: Column(children: [
            for (final l in lines) _LineRow(doc: d, line: l),
          ]),
        ),
        const SizedBox(height: 14),
        SectionCard(
          title: 'المسار',
          icon: Icons.timeline_rounded,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            _Step('أُنشئ', who(d.createdBy), d.createdAt),
            if (d.submittedAt != null) _Step('قُدّم للاعتماد', who(d.submittedBy), d.submittedAt),
            if (d.approvedAt != null) _Step('اعتُمد', who(d.approvedBy), d.approvedAt),
            if (d.postedAt != null) _Step('رُحّل إلى الأرصدة', who(d.postedBy), d.postedAt),
            if (d.decidedAt != null && !d.isPosted && !d.isApproved)
              _Step(switch (d.status) { 'rejected' => 'رُفض', 'cancelled' => 'أُلغي', _ => 'أُعيد للتعديل' }, who(d.decidedBy), d.decidedAt),
            if (d.confirmedAt != null) _Step('أكّد الموظف الاستلام', who(d.confirmedBy), d.confirmedAt),
          ]),
        ),
        const SizedBox(height: 14),
        Wrap(spacing: 10, runSpacing: 10, alignment: WrapAlignment.end, children: actions),
      ]),
    );
  }
}

class _Info extends StatelessWidget {
  const _Info(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final sem = Sem.of(context);
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 120, maxWidth: 380),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Text(label, style: TextStyle(color: sem.muted, fontSize: 12)),
        const SizedBox(height: 2),
        Text(value.isEmpty ? '—' : value, style: const TextStyle(fontWeight: FontWeight.w600)),
      ]),
    );
  }
}

class _Step extends StatelessWidget {
  const _Step(this.label, this.who, this.at);

  final String label;
  final String who;
  final DateTime? at;

  @override
  Widget build(BuildContext context) {
    final sem = Sem.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        Icon(Icons.circle, size: 9, color: sem.na),
        const SizedBox(width: 10),
        Expanded(child: Text(who.isEmpty ? label : '$label — $who')),
        Text(fmtDate(at), style: _tabular.copyWith(color: sem.muted, fontSize: 12.5)),
      ]),
    );
  }
}

class _LineRow extends StatelessWidget {
  const _LineRow({required this.doc, required this.line});

  final StDoc doc;
  final StDocLine line;

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context).stores;
    final sem = Sem.of(context);
    final it = s.item(line.itemId);
    final base = s.unitName(it?.baseUnitId);
    final unit = s.unitName(line.unitId);
    final signed = doc.kind == 'adjust' || doc.isReversal;
    final q = signed ? signedQty(line.qty) : fmtQty(line.qty);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(width: 26, child: Text('${line.lineNo}', style: TextStyle(color: sem.muted))),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(it?.name ?? '', style: const TextStyle(fontWeight: FontWeight.w600)),
            Text(
              [
                isolate(it?.code ?? ''),
                if (line.factor != 1) 'تعادل ${qtyWithUnit(line.baseQty.abs(), base)}',
                if (line.expiryDate != null) 'تنتهي ${dayText(line.expiryDate)}${line.batchNo.isEmpty ? '' : ' (${line.batchNo})'}',
                if (line.note.isNotEmpty) line.note,
              ].join(' · '),
              style: TextStyle(color: sem.muted, fontSize: 12.5),
            ),
          ]),
        ),
        Text('$q $unit', style: _tabular.copyWith(fontWeight: FontWeight.w700)),
      ]),
    );
  }
}
