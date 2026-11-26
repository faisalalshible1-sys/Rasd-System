import 'package:flutter/material.dart';

import '../app_state.dart';
import '../docs.dart' show isolate;
import '../models.dart';
import '../print/export_dialog.dart' show ExportButton;
import '../print/labels.dart';
import '../print/output.dart' show openBytes;
import '../stores.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';
import 'pm_common.dart' show PmTable;
import 'stores_docs.dart';
import 'stores_setup.dart' show startStoresImport;

// =====================================================================
// قسم المخازن والأصول والخدمات العامة (الإصدار 1.7.0): لوحة القسم، والأصناف وبطاقاتها، والأرصدة،
// وصفحة الموظف «ما صُرف لي». المستندات في stores_docs.dart، والتهيئة والموظفون في stores_setup.dart.
// =====================================================================

const _tabular = TextStyle(fontFeatures: [FontFeature.tabularFigures()]);

/// لون مستوى الرصيد.
Color storeLevelColor(Sem sem, String level) => switch (level) {
      'out' || 'min' => sem.danger,
      'reorder' => sem.wip,
      'over' => sem.na,
      _ => sem.ok,
    };

/// لون حالة المستند.
Color storeDocStatusColor(Sem sem, String status) => switch (status) {
      'posted' => sem.ok,
      'approved' => sem.na,
      'submitted' => sem.wip,
      'rejected' || 'cancelled' => sem.danger,
      _ => sem.muted,
    };

/// ينفّذ عملية في القسم ويعرض نتيجتها أو خطأها.
Future<bool> storesRun(BuildContext context, Future<void> Function() action, {String? success}) async {
  try {
    await action();
    if (context.mounted && success != null) showToast(context, success);
    return true;
  } catch (e) {
    if (context.mounted) showToast(context, friendlyError(e), error: true);
    return false;
  }
}

/// كمية بوحدتها: «12 رزمة».
String qtyWithUnit(double q, String unit) => unit.isEmpty ? fmtQty(q) : '${fmtQty(q)} $unit';

/// قبل تطبيق الترحيل 38: شريط يشرح ما يلزم.
class StoresNotReady extends StatelessWidget {
  const StoresNotReady({super.key});

  @override
  Widget build(BuildContext context) => const InfoBanner(
        level: 'warning',
        icon: Icons.storage_rounded,
        text: 'قسم المخازن يحتاج تحديث قاعدة البيانات (الترحيل 38)، أو لا صلاحية لك فيه بعد. اطلب من مدير المنظومة منحك صلاحية المخازن.',
      );
}

// ---------------------------------------------------------------------
// اختيار الصنف والموظف
// ---------------------------------------------------------------------

/// نافذة بحث عن صنف بالاسم أو الرمز أو الباركود (قارئ الباركود يكتب في خانة البحث).
Future<StItem?> pickStoreItem(BuildContext context, {bool activeOnly = true}) {
  return showDialog<StItem>(context: context, builder: (_) => _ItemPicker(activeOnly: activeOnly));
}

class _ItemPicker extends StatefulWidget {
  const _ItemPicker({required this.activeOnly});

  final bool activeOnly;

  @override
  State<_ItemPicker> createState() => _ItemPickerState();
}

class _ItemPickerState extends State<_ItemPicker> {
  final _q = TextEditingController();

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
    final q = _q.text.trim();
    final exact = q.isEmpty ? null : s.items.where((i) => i.barcode == q || i.code.toLowerCase() == q.toLowerCase()).toList();
    final list = [
      for (final i in s.items)
        if ((!widget.activeOnly || i.active) && i.matches(q)) i,
    ];
    return AlertDialog(
      title: const Text('اختر الصنف'),
      content: SizedBox(
        width: 520,
        height: 480,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          TextField(
            controller: _q,
            autofocus: true,
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) {
              // قارئ الباركود يكتب الرمز ثم Enter: يُختار الصنف المطابق تماماً مباشرة
              if (exact != null && exact.length == 1) Navigator.of(context).pop(exact.first);
            },
            decoration: fieldDeco('بحث بالاسم أو الرمز أو الباركود', prefixIcon: const Icon(Icons.qr_code_scanner_rounded)),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: list.isEmpty
                ? Center(child: Text('لا صنف مطابق.', style: TextStyle(color: sem.muted)))
                : ListView.builder(
                    itemCount: list.length > 300 ? 300 : list.length,
                    itemBuilder: (_, k) {
                      final it = list[k];
                      final avail = s.available(it.id);
                      return ListTile(
                        dense: true,
                        title: Text(it.name),
                        subtitle: Text('${it.code} · ${s.category(it.categoryId)?.name ?? ''}', style: TextStyle(color: sem.muted)),
                        trailing: Text(qtyWithUnit(avail, s.unitName(it.baseUnitId)), style: _tabular),
                        onTap: () => Navigator.of(context).pop(it),
                      );
                    },
                  ),
          ),
        ]),
      ),
      actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('إلغاء'))],
    );
  }
}

/// نافذة بحث عن موظف بالاسم أو الرقم الوظيفي.
Future<StEmployee?> pickStoreEmployee(BuildContext context) =>
    showDialog<StEmployee>(context: context, builder: (_) => const _EmployeePicker());

class _EmployeePicker extends StatefulWidget {
  const _EmployeePicker();

  @override
  State<_EmployeePicker> createState() => _EmployeePickerState();
}

class _EmployeePickerState extends State<_EmployeePicker> {
  final _q = TextEditingController();

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
      for (final e in s.employees)
        if (e.active && (q.isEmpty || normalizeArabic(e.fullName).contains(q) || e.empNo.toLowerCase().contains(q))) e,
    ];
    return AlertDialog(
      title: const Text('اختر الموظف'),
      content: SizedBox(
        width: 480,
        height: 460,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          TextField(
            controller: _q,
            autofocus: true,
            onChanged: (_) => setState(() {}),
            decoration: fieldDeco('بحث بالاسم أو الرقم الوظيفي', prefixIcon: const Icon(Icons.search_rounded)),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: list.isEmpty
                ? Center(child: Text('لا موظف مطابق في السجل.', style: TextStyle(color: sem.muted)))
                : ListView.builder(
                    itemCount: list.length > 300 ? 300 : list.length,
                    itemBuilder: (_, k) {
                      final e = list[k];
                      return ListTile(
                        dense: true,
                        leading: InitialsAvatar(name: e.fullName, size: 32),
                        title: Text(e.fullName),
                        subtitle: Text([e.empNo, s.departmentPath(e.departmentId)].where((x) => x.isNotEmpty).join(' · '),
                            style: TextStyle(color: sem.muted)),
                        onTap: () => Navigator.of(context).pop(e),
                      );
                    },
                  ),
          ),
        ]),
      ),
      actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('إلغاء'))],
    );
  }
}

// ---------------------------------------------------------------------
// لوحة المخازن
// ---------------------------------------------------------------------

class StoresDashboardPage extends StatelessWidget {
  const StoresDashboardPage({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final sem = Sem.of(context);
    final s = app.stores;
    final today = DateTime.now();
    final low = s.lowStock();
    final exp = s.expiring(today);
    final recent = s.docs.take(8).toList();
    return PageBody(
      onRefresh: app.loadAll,
      children: [
        PageHeader(
          title: 'لوحة المخازن',
          subtitle: 'الأصناف وأرصدتها في كل المخازن، وما يحتاج توريداً، والصلاحيات القريبة، والمستندات بانتظار قرار.',
          icon: Icons.warehouse_rounded,
          actions: [
            if (app.storesMovableWarehouses.isNotEmpty) NewStoreDocButton(app: app),
            if (app.v22Ready) const ExportButton(sourceId: 'stores:balances'),
          ],
        ),
        if (!app.v22Ready) ...[const StoresNotReady(), const SizedBox(height: 14)],
        ResponsiveGrid(minItemWidth: 190, children: [
          StatCard(
            label: 'الأصناف النشطة',
            value: '${s.activeItems}',
            icon: Icons.inventory_2_outlined,
            onTap: () => app.setTab(201),
          ),
          StatCard(
            label: 'المخازن',
            value: '${s.warehouses.where((w) => w.active).length}',
            icon: Icons.warehouse_outlined,
            onTap: app.storesStaff ? () => app.setTab(203) : null,
          ),
          StatCard(
            label: 'تحتاج توريداً',
            value: '${low.length}',
            sub: 'نفدت أو دون الحد أو عند نقطة الطلب',
            icon: Icons.production_quantity_limits_rounded,
            color: low.isEmpty ? sem.ok : sem.wip,
            onTap: () => app.setTab(203),
          ),
          StatCard(
            label: 'تنتهي صلاحيتها',
            value: '${exp.length}',
            sub: 'خلال ${s.settings.expiryDays} يوماً أو انتهت',
            icon: Icons.event_busy_outlined,
            color: exp.isEmpty ? sem.ok : sem.danger,
          ),
          StatCard(
            label: 'بانتظار الاعتماد',
            value: '${s.pendingApproval}',
            icon: Icons.fact_check_outlined,
            color: s.pendingApproval == 0 ? null : sem.wip,
            onTap: () => app.openStoresDocs(status: 'submitted'),
          ),
          StatCard(
            label: 'معتمدة بانتظار الترحيل',
            value: '${s.awaitingPost}',
            icon: Icons.local_shipping_outlined,
            onTap: () => app.openStoresDocs(status: 'approved'),
          ),
        ]),
        const SizedBox(height: 14),
        SectionCard(
          title: 'أصناف تحتاج توريداً',
          icon: Icons.production_quantity_limits_rounded,
          subtitle: 'المتاح (الفعلي − المحجوز) في كل المخازن مقارنةً بالحد الأدنى ونقطة إعادة الطلب.',
          child: low.isEmpty
              ? Text('لا صنف دون حدوده.', style: TextStyle(color: sem.muted))
              : Column(children: [
                  for (final a in low.take(12))
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(a.item.name),
                      subtitle: Text(
                          'المتاح ${qtyWithUnit(a.available, s.unitName(a.item.baseUnitId))} · الحد الأدنى ${fmtQty(a.item.minQty)} · نقطة الطلب ${fmtQty(a.item.reorderQty)}',
                          style: TextStyle(color: sem.muted, fontSize: 12.5)),
                      trailing: ToneBadge(stockLevelLabels[a.level] ?? a.level, color: storeLevelColor(sem, a.level)),
                      onTap: () => openStoreItem(context, a.item),
                    ),
                  if (low.length > 12)
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: TextButton(onPressed: () => app.setTab(203), child: Text('كل الأصناف (${low.length})')),
                    ),
                ]),
        ),
        const SizedBox(height: 14),
        SectionCard(
          title: 'صلاحيات قريبة الانتهاء',
          icon: Icons.event_busy_outlined,
          subtitle: 'دفعات بكمية تنتهي صلاحيتها خلال ${s.settings.expiryDays} يوماً؛ تُصرف الأقرب انتهاءً أولاً تلقائياً.',
          child: exp.isEmpty
              ? Text('لا دفعة قريبة الانتهاء.', style: TextStyle(color: sem.muted))
              : PmTable(
                  columns: const ['الصنف', 'المخزن', 'تاريخ الانتهاء', 'المتبقي', 'الكمية'],
                  rows: [
                    for (final b in exp.take(20))
                      [
                        s.itemName(b.itemId),
                        s.warehouseName(b.warehouseId),
                        dayText(b.expiryDate),
                        b.daysLeft(today) < 0 ? 'انتهت' : '${b.daysLeft(today)} يوماً',
                        qtyWithUnit(b.qty, s.unitName(s.item(b.itemId)?.baseUnitId)),
                      ],
                  ],
                  highlight: (i) => exp[i].daysLeft(today) < 0,
                ),
        ),
        const SizedBox(height: 14),
        SectionCard(
          title: 'آخر المستندات',
          icon: Icons.receipt_long_outlined,
          trailing: TextButton(onPressed: () => app.setTab(202), child: const Text('كل المستندات')),
          child: recent.isEmpty
              ? Text('لا مستندات بعد. ابدأ بأرصدة أول المدة لكل مخزن.', style: TextStyle(color: sem.muted))
              : Column(children: [for (final d in recent) StoreDocTile(doc: d)]),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------
// الأصناف
// ---------------------------------------------------------------------

class StoresItemsPage extends StatefulWidget {
  const StoresItemsPage({super.key});

  @override
  State<StoresItemsPage> createState() => _StoresItemsPageState();
}

class _StoresItemsPageState extends State<StoresItemsPage> {
  final _q = TextEditingController();
  String _cat = '';
  String _level = '';
  bool _inactive = false;

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  List<StItem> _filtered(StoresData s) => [
        for (final it in s.items)
          if ((_inactive || it.active) &&
              (_cat.isEmpty || it.categoryId == _cat) &&
              it.matches(_q.text) &&
              (_level.isEmpty || (_level == 'attention' ? const {'out', 'min', 'reorder'}.contains(s.levelOf(it)) : s.levelOf(it) == _level)))
            it,
      ];

  Future<void> _labels(List<StItem> items) async {
    if (items.isEmpty) return;
    final s = AppScope.read(context).stores;
    await storesRun(context, () async {
      final bytes = await buildItemLabels([
        for (final it in items) (code: it.code, name: it.name, barcode: it.barcode, unit: s.unitName(it.baseUnitId)),
      ]);
      await openBytes(bytes, 'ملصقات الأصناف', 'pdf');
    });
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final s = app.stores;
    final sem = Sem.of(context);
    final list = _filtered(s);
    return PageBody(
      onRefresh: app.loadAll,
      children: [
        PageHeader(
          title: 'الأصناف',
          subtitle: 'بطاقة لكل صنف برمزه وتصنيفه ووحداته وحدوده، ورصيده في كل مخزن وبطاقة حركته.',
          icon: Icons.inventory_2_rounded,
          actions: [
            if (app.canStoresItems)
              FilledButton.icon(
                onPressed: () => showStoreItemEditor(context),
                icon: const Icon(Icons.add_rounded),
                label: const Text('صنف جديد'),
              ),
            if (app.canStoresItems)
              OutlinedButton.icon(
                onPressed: () => startStoresImport(context, 'items'),
                icon: const Icon(Icons.upload_file_rounded),
                label: const Text('استيراد من Excel'),
              ),
            OutlinedButton.icon(
              onPressed: list.isEmpty ? null : () => _labels(list),
              icon: const Icon(Icons.qr_code_2_rounded),
              label: const Text('طباعة الملصقات'),
            ),
            if (app.v22Ready) ExportButton(sourceId: 'stores:items', items: list),
          ],
        ),
        if (!app.v22Ready) ...[const StoresNotReady(), const SizedBox(height: 14)],
        Wrap(spacing: 10, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.center, children: [
          SizedBox(
            width: 300,
            child: TextField(
              controller: _q,
              onChanged: (_) => setState(() {}),
              decoration: fieldDeco('بحث بالاسم أو الرمز أو الباركود', prefixIcon: const Icon(Icons.search_rounded)),
            ),
          ),
          SizedBox(
            width: 220,
            child: SelectField(
              label: 'التصنيف',
              value: _cat,
              items: [('', 'كل التصنيفات'), for (final c in s.categories) (c.id, c.name)],
              onChanged: (v) => setState(() => _cat = v),
            ),
          ),
          SizedBox(
            width: 220,
            child: SelectField(
              label: 'الرصيد',
              value: _level,
              items: [
                ('', 'كل الأرصدة'),
                ('attention', 'تحتاج توريداً'),
                for (final e in stockLevelLabels.entries) (e.key, e.value),
              ],
              onChanged: (v) => setState(() => _level = v),
            ),
          ),
          FilterChip(
            label: const Text('الموقوفة أيضاً'),
            selected: _inactive,
            onSelected: (v) => setState(() => _inactive = v),
          ),
        ]),
        const SizedBox(height: 12),
        if (list.isEmpty)
          EmptyState(
            title: s.items.isEmpty ? 'لا أصناف بعد' : 'لا صنف مطابق',
            message: s.items.isEmpty ? 'أضف بطاقات الأصناف واحدة واحدة أو استوردها من ملف Excel.' : null,
            icon: Icons.inventory_2_outlined,
          )
        else
          SectionCard(
            title: 'الأصناف (${list.length})',
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
            child: Column(children: [
              for (final it in list.take(400)) _ItemRow(item: it),
              if (list.length > 400)
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Text('يُعرض أول 400 صنف؛ ضيّق البحث لرؤية البقية.', style: TextStyle(color: sem.muted)),
                ),
            ]),
          ),
      ],
    );
  }
}

class _ItemRow extends StatelessWidget {
  const _ItemRow({required this.item});

  final StItem item;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final s = app.stores;
    final sem = Sem.of(context);
    final level = s.levelOf(item);
    final unit = s.unitName(item.baseUnitId);
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      title: Row(children: [
        Flexible(child: Text(item.name, maxLines: 2, overflow: TextOverflow.ellipsis)),
        if (!item.active) ...[const SizedBox(width: 6), ToneBadge('موقوف', color: sem.muted)],
        if (item.tracksExpiry) ...[const SizedBox(width: 6), Icon(Icons.event_outlined, size: 15, color: sem.muted)],
      ]),
      subtitle: Text('${isolate(item.code)} · ${s.category(item.categoryId)?.name ?? ''}', style: TextStyle(color: sem.muted, fontSize: 12.5)),
      trailing: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(qtyWithUnit(s.available(item.id), unit), style: _tabular.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 2),
          if (level != 'ok') ToneBadge(stockLevelLabels[level] ?? level, color: storeLevelColor(sem, level)),
        ],
      ),
      onTap: () => openStoreItem(context, item),
    );
  }
}

void openStoreItem(BuildContext context, StItem item) {
  Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => StoreItemPage(itemId: item.id)));
}

/// بطاقة الصنف: بياناته، ورصيده في كل مخزن، ودفعات صلاحيته، وبطاقة حركته.
class StoreItemPage extends StatefulWidget {
  const StoreItemPage({super.key, required this.itemId});

  final String itemId;

  @override
  State<StoreItemPage> createState() => _StoreItemPageState();
}

class _StoreItemPageState extends State<StoreItemPage> {
  List<StMove>? _moves;
  String _wh = '';
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final app = AppScope.read(context);
    if (!app.storesStaff) return;
    setState(() {
      _moves = null;
      _error = null;
    });
    try {
      final m = await app.stMovesOf(widget.itemId, warehouseId: _wh.isEmpty ? null : _wh);
      if (mounted) setState(() => _moves = m);
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final s = app.stores;
    final sem = Sem.of(context);
    final it = s.item(widget.itemId);
    if (it == null) {
      return Scaffold(appBar: AppBar(), body: const EmptyState(title: 'الصنف غير موجود'));
    }
    final unit = s.unitName(it.baseUnitId);
    final units = s.unitsOf(it);
    final rows = [for (final st in s.stockOfItem(it.id)) if (st.onHand > 0 || st.reserved > 0) st];
    final batches = [for (final b in s.batches) if (b.itemId == it.id) b]..sort((a, b) => a.expiryDate.compareTo(b.expiryDate));
    final today = DateTime.now();
    final level = s.levelOf(it);
    return Scaffold(
      appBar: AppBar(
        title: Text(it.name),
        actions: [
          IconButton(
            tooltip: 'طباعة الملصق',
            icon: const Icon(Icons.qr_code_2_rounded),
            onPressed: () => storesRun(context, () async {
              final bytes = await buildItemLabels([(code: it.code, name: it.name, barcode: it.barcode, unit: unit)], copies: 6);
              await openBytes(bytes, 'ملصق ${it.code}', 'pdf');
            }),
          ),
          if (app.canStoresItems)
            IconButton(tooltip: 'تعديل البطاقة', icon: const Icon(Icons.edit_outlined), onPressed: () => showStoreItemEditor(context, item: it)),
        ],
      ),
      body: PageBody(children: [
        ResponsiveGrid(minItemWidth: 170, children: [
          KpiTile(label: 'الفعلي', value: fmtQty(s.onHand(it.id)), sub: unit),
          KpiTile(label: 'المحجوز', value: fmtQty(s.reserved(it.id)), sub: 'باعتماد صرف أو تحويل'),
          KpiTile(label: 'المتاح', value: fmtQty(s.available(it.id)), sub: stockLevelLabels[level], color: storeLevelColor(sem, level)),
        ]),
        const SizedBox(height: 14),
        SectionCard(
          title: 'بطاقة الصنف',
          icon: Icons.badge_outlined,
          child: Wrap(spacing: 22, runSpacing: 10, children: [
            _Field('الرمز', isolate(it.code)),
            _Field('التصنيف', s.category(it.categoryId)?.name ?? ''),
            _Field('الوحدات', [for (final u in units) u.$3 == 1 ? '${u.$2} (الأساسية)' : '${u.$2} = ${fmtQty(u.$3)} ${units.first.$2}'].join('، ')),
            _Field('الحد الأدنى', fmtQty(it.minQty)),
            _Field('الحد الأقصى', it.maxQty == null ? '—' : fmtQty(it.maxQty!)),
            _Field('نقطة إعادة الطلب', fmtQty(it.reorderQty)),
            _Field('الاحتياطي الحرج', fmtQty(it.criticalQty)),
            _Field('الصلاحية', it.tracksExpiry ? 'تُتتبع بالدفعات' : 'لا تُتتبع'),
            if (it.barcode.isNotEmpty) _Field('الباركود', isolate(it.barcode)),
            if (it.description.isNotEmpty) _Field('الوصف', it.description),
          ]),
        ),
        const SizedBox(height: 14),
        SectionCard(
          title: 'الرصيد في المخازن',
          icon: Icons.warehouse_outlined,
          child: PmTable(
            columns: const ['المخزن', 'الفعلي', 'المحجوز', 'المتاح'],
            rows: [
              for (final st in rows) [s.warehouseName(st.warehouseId), fmtQty(st.onHand), fmtQty(st.reserved), fmtQty(st.available)],
            ],
          ),
        ),
        if (it.tracksExpiry) ...[
          const SizedBox(height: 14),
          SectionCard(
            title: 'دفعات الصلاحية',
            icon: Icons.event_outlined,
            subtitle: 'يُصرف من الأقرب انتهاءً أولاً.',
            child: PmTable(
              columns: const ['المخزن', 'تاريخ الانتهاء', 'الدفعة', 'المتبقي', 'الكمية'],
              rows: [
                for (final b in batches)
                  [
                    s.warehouseName(b.warehouseId),
                    dayText(b.expiryDate),
                    b.batchNo.isEmpty ? '—' : b.batchNo,
                    b.daysLeft(today) < 0 ? 'انتهت' : '${b.daysLeft(today)} يوماً',
                    fmtQty(b.qty),
                  ],
              ],
              highlight: (i) => batches[i].daysLeft(today) <= s.settings.expiryDays,
            ),
          ),
        ],
        if (app.storesStaff) ...[
          const SizedBox(height: 14),
          SectionCard(
            title: 'بطاقة الحركة',
            icon: Icons.swap_vert_rounded,
            subtitle: 'كل أثر مرحَّل بمستنده والرصيد بعده في مخزنه. لا يُعدَّل ولا يُحذف؛ التصحيح بمستند عكسي.',
            trailing: _moves == null || _moves!.isEmpty ? null : ExportButton(sourceId: 'stores:moves', items: _moves!, compact: true),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              SizedBox(
                width: 260,
                child: SelectField(
                  label: 'المخزن',
                  value: _wh,
                  items: [('', 'كل المخازن'), for (final w in s.warehouses) (w.id, w.name)],
                  onChanged: (v) {
                    setState(() => _wh = v);
                    _load();
                  },
                ),
              ),
              const SizedBox(height: 10),
              if (_error != null)
                InfoBanner(level: 'critical', text: _error!)
              else if (_moves == null)
                const LinearProgressIndicator()
              else if (_moves!.isEmpty)
                Text('لا حركات مرحَّلة بعد.', style: TextStyle(color: sem.muted))
              else
                PmTable(
                  columns: const ['التاريخ', 'المستند', 'المخزن', 'الكمية', 'الرصيد بعده', 'الدفعة'],
                  rows: [
                    for (final m in _moves!.reversed.take(300))
                      [
                        dayText(m.at),
                        '${s.doc(m.docId)?.kindLabel ?? ''} ${isolate(s.doc(m.docId)?.docNo ?? '')}',
                        s.warehouseName(m.warehouseId),
                        isolate('${m.qty > 0 ? '+' : '-'}${fmtQty(m.qty.abs())}'),
                        fmtQty(m.balanceAfter),
                        m.expiryDate == null ? '—' : '${dayText(m.expiryDate)}${m.batchNo.isEmpty ? '' : ' (${m.batchNo})'}',
                      ],
                  ],
                ),
            ]),
          ),
        ],
      ]),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final sem = Sem.of(context);
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 120, maxWidth: 360),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Text(label, style: TextStyle(color: sem.muted, fontSize: 12)),
        const SizedBox(height: 2),
        Text(value.isEmpty ? '—' : value, style: const TextStyle(fontWeight: FontWeight.w600)),
      ]),
    );
  }
}

/// نافذة بطاقة الصنف: جديد أو تعديل.
Future<void> showStoreItemEditor(BuildContext context, {StItem? item}) =>
    showDialog<void>(context: context, builder: (_) => _ItemEditor(item: item));

class _ItemEditor extends StatefulWidget {
  const _ItemEditor({this.item});

  final StItem? item;

  @override
  State<_ItemEditor> createState() => _ItemEditorState();
}

class _ItemEditorState extends State<_ItemEditor> {
  late final TextEditingController _name = TextEditingController(text: widget.item?.name ?? '');
  late final TextEditingController _code = TextEditingController(text: widget.item?.code ?? '');
  late final TextEditingController _desc = TextEditingController(text: widget.item?.description ?? '');
  late final TextEditingController _barcode = TextEditingController(text: widget.item?.barcode ?? '');
  late final TextEditingController _min = TextEditingController(text: _q(widget.item?.minQty));
  late final TextEditingController _max = TextEditingController(text: widget.item?.maxQty == null ? '' : _q(widget.item?.maxQty));
  late final TextEditingController _reorder = TextEditingController(text: _q(widget.item?.reorderQty));
  late final TextEditingController _critical = TextEditingController(text: _q(widget.item?.criticalQty));
  late String _cat = widget.item?.categoryId ?? '';
  late String _unit = widget.item?.baseUnitId ?? '';
  late bool _expiry = widget.item?.tracksExpiry ?? false;
  late bool _active = widget.item?.active ?? true;
  final List<(String, TextEditingController)> _units = [];
  bool _busy = false;
  String? _error;

  static String _q(double? v) => v == null || v == 0 ? '' : fmtQty(v).replaceAll(',', '');

  @override
  void initState() {
    super.initState();
    final it = widget.item;
    final s = AppScope.read(context).stores;
    if (it != null) {
      for (final u in s.unitsOf(it).skip(1)) {
        _units.add((u.$1, TextEditingController(text: fmtQty(u.$3).replaceAll(',', ''))));
      }
    }
    if (_cat.isEmpty && s.categories.isNotEmpty) _cat = s.categories.first.id;
    if (_unit.isEmpty && s.units.isNotEmpty) _unit = s.units.first.id;
  }

  @override
  void dispose() {
    for (final c in [_name, _code, _desc, _barcode, _min, _max, _reorder, _critical]) {
      c.dispose();
    }
    for (final u in _units) {
      u.$2.dispose();
    }
    super.dispose();
  }

  double? _num(TextEditingController c) => c.text.trim().isEmpty ? 0 : parseImportNumber(c.text);

  Future<void> _save() async {
    final min = _num(_min), reorder = _num(_reorder), critical = _num(_critical);
    final max = _max.text.trim().isEmpty ? null : parseImportNumber(_max.text);
    if (_name.text.trim().length < 2) {
      setState(() => _error = 'اكتب اسم الصنف.');
      return;
    }
    if (min == null || reorder == null || critical == null || (_max.text.trim().isNotEmpty && max == null)) {
      setState(() => _error = 'اكتب الكميات أرقاماً (أو اتركها فارغة).');
      return;
    }
    if (max != null && max < min) {
      setState(() => _error = 'الحد الأقصى لا يقل عن الحد الأدنى.');
      return;
    }
    final units = <Map<String, dynamic>>[];
    for (final u in _units) {
      final f = parseImportNumber(u.$2.text);
      if (u.$1 == _unit) continue;
      if (f == null || f <= 0) {
        setState(() => _error = 'معامل كل وحدة رقم موجب (كم من الوحدة الأساسية فيها).');
        return;
      }
      units.add({'unit_id': u.$1, 'factor': f});
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await AppScope.read(context).stSaveItem(widget.item?.id, {
        'name': _name.text.trim(),
        'code': _code.text.trim(),
        'description': _desc.text.trim(),
        'barcode': _barcode.text.trim(),
        'category_id': _cat,
        'base_unit_id': _unit,
        'min_qty': min,
        'max_qty': max,
        'reorder_qty': reorder,
        'critical_qty': critical,
        'tracks_expiry': _expiry,
        'active': _active,
        'units': units,
      });
      if (mounted) {
        Navigator.of(context).pop();
        showToast(context, 'حُفظت بطاقة «${_name.text.trim()}»');
      }
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context).stores;
    final sem = Sem.of(context);
    final baseName = s.unitName(_unit);
    final otherUnits = [for (final u in s.units) if (u.id != _unit && (u.active || _units.any((x) => x.$1 == u.id))) u];
    Widget numField(TextEditingController c, String label, {String? helper}) => SizedBox(
          width: 170,
          child: TextField(
            controller: c,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            textDirection: TextDirection.ltr,
            decoration: fieldDeco(label, helper: helper),
          ),
        );
    return AlertDialog(
      title: Text(widget.item == null ? 'صنف جديد' : 'تعديل بطاقة الصنف'),
      content: SizedBox(
        width: 620,
        child: SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: _name, decoration: fieldDeco('اسم الصنف')),
            const SizedBox(height: 10),
            Wrap(spacing: 10, runSpacing: 10, children: [
              SizedBox(
                width: 200,
                child: TextField(
                  controller: _code,
                  textDirection: TextDirection.ltr,
                  decoration: fieldDeco('الرمز', helper: widget.item == null ? 'يُولَّد من التصنيف إن تُرك' : null),
                ),
              ),
              SizedBox(
                width: 200,
                child: TextField(controller: _barcode, textDirection: TextDirection.ltr, decoration: fieldDeco('الباركود (اختياري)')),
              ),
              SizedBox(
                width: 200,
                child: SelectField(
                  label: 'التصنيف',
                  value: _cat,
                  items: [for (final c in s.categories) if (c.active || c.id == _cat) (c.id, c.name)],
                  onChanged: (v) => setState(() => _cat = v),
                ),
              ),
              SizedBox(
                width: 200,
                child: SelectField(
                  label: 'الوحدة الأساسية',
                  value: _unit,
                  items: [for (final u in s.units) if (u.active || u.id == _unit) (u.id, u.name)],
                  onChanged: (v) => setState(() => _unit = v),
                ),
              ),
            ]),
            const SizedBox(height: 14),
            Text('وحدات أخرى', style: const TextStyle(fontWeight: FontWeight.w700)),
            Text('كم ${baseName.isEmpty ? 'وحدة أساسية' : baseName} في كل وحدة (مثل كرتونة = 5 رزم).', style: TextStyle(color: sem.muted, fontSize: 12.5)),
            const SizedBox(height: 6),
            for (var i = 0; i < _units.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(children: [
                  Expanded(
                    child: SelectField(
                      label: 'الوحدة',
                      value: _units[i].$1,
                      items: [for (final u in s.units) if (u.id != _unit) (u.id, u.name)],
                      onChanged: (v) => setState(() => _units[i] = (v, _units[i].$2)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 150,
                    child: TextField(
                      controller: _units[i].$2,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      textDirection: TextDirection.ltr,
                      decoration: fieldDeco('= كم $baseName'),
                    ),
                  ),
                  IconButton(
                    tooltip: 'إزالة',
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => setState(() => _units.removeAt(i).$2.dispose()),
                  ),
                ]),
              ),
            if (otherUnits.isNotEmpty && _units.length < 10)
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton.icon(
                  onPressed: () => setState(() => _units.add((otherUnits.first.id, TextEditingController()))),
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('إضافة وحدة'),
                ),
              ),
            const SizedBox(height: 10),
            Wrap(spacing: 10, runSpacing: 10, children: [
              numField(_min, 'الحد الأدنى'),
              numField(_max, 'الحد الأقصى', helper: 'اختياري'),
              numField(_reorder, 'نقطة إعادة الطلب'),
              numField(_critical, 'الاحتياطي الحرج', helper: 'لا يُصرف منه إلا باستثناء'),
            ]),
            const SizedBox(height: 10),
            TextField(controller: _desc, minLines: 1, maxLines: 3, decoration: fieldDeco('الوصف (اختياري)')),
            Material(
              type: MaterialType.transparency,
              child: Column(children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('يتتبع تاريخ الصلاحية'),
                  subtitle: Text('يُطلب تاريخ الانتهاء في كل وارد، ويُصرف الأقرب انتهاءً أولاً', style: TextStyle(color: sem.muted, fontSize: 12.5)),
                  value: _expiry,
                  onChanged: (v) => setState(() => _expiry = v),
                ),
                if (widget.item != null)
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('نشط'),
                    subtitle: Text('الموقوف لا يُختار في المستندات الجديدة ويبقى رصيده وحركاته', style: TextStyle(color: sem.muted, fontSize: 12.5)),
                    value: _active,
                    onChanged: (v) => setState(() => _active = v),
                  ),
              ]),
            ),
            if (_error != null) ...[const SizedBox(height: 8), InfoBanner(level: 'critical', text: _error!)],
          ]),
        ),
      ),
      actions: [
        if (widget.item != null && AppScope.of(context).canStoresItems && s.stockOfItem(widget.item!.id).isEmpty)
          TextButton(
            onPressed: _busy
                ? null
                : () async {
                    final ok = await confirmDialog(context,
                        title: 'حذف الصنف؟', message: 'يُحذف «${widget.item!.name}» لأنه بلا رصيد ولا حركات.', confirmLabel: 'حذف', danger: true);
                    if (!ok || !context.mounted) return;
                    final done = await storesRun(context, () => AppScope.read(context).stDeleteSetup('item', widget.item!.id), success: 'حُذف الصنف');
                    if (done && context.mounted) Navigator.of(context).pop();
                  },
            child: Text('حذف', style: TextStyle(color: sem.danger)),
          ),
        TextButton(onPressed: _busy ? null : () => Navigator.of(context).pop(), child: const Text('إلغاء')),
        FilledButton(onPressed: _busy ? null : _save, child: const Text('حفظ')),
      ],
    );
  }
}

// ---------------------------------------------------------------------
// الأرصدة
// ---------------------------------------------------------------------

class StoresBalancesPage extends StatefulWidget {
  const StoresBalancesPage({super.key});

  @override
  State<StoresBalancesPage> createState() => _StoresBalancesPageState();
}

class _StoresBalancesPageState extends State<StoresBalancesPage> {
  final _q = TextEditingController();
  String _wh = '';
  String _level = 'attention';

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
    final wh = _wh.isEmpty ? null : _wh;
    final rows = <(StItem, String, double, double, double)>[];
    for (final it in s.items) {
      if (!it.active || !it.matches(_q.text)) continue;
      final level = s.levelOf(it, warehouseId: wh);
      if (_level == 'attention' && !const {'out', 'min', 'reorder'}.contains(level)) continue;
      if (_level.isNotEmpty && _level != 'attention' && level != _level) continue;
      rows.add((it, level, s.onHand(it.id, warehouseId: wh), s.reserved(it.id, warehouseId: wh), s.available(it.id, warehouseId: wh)));
    }
    return PageBody(
      onRefresh: app.loadAll,
      children: [
        PageHeader(
          title: 'الأرصدة',
          subtitle: 'الفعلي والمحجوز والمتاح لكل صنف في مخزن بعينه أو في كل المخازن، ومستواه مقارنةً بحدوده.',
          icon: Icons.stacked_bar_chart_rounded,
          actions: [if (app.v22Ready) const ExportButton(sourceId: 'stores:balances')],
        ),
        if (!app.v22Ready) ...[const StoresNotReady(), const SizedBox(height: 14)],
        Wrap(spacing: 10, runSpacing: 10, children: [
          SizedBox(
            width: 280,
            child: TextField(
              controller: _q,
              onChanged: (_) => setState(() {}),
              decoration: fieldDeco('بحث في الأصناف', prefixIcon: const Icon(Icons.search_rounded)),
            ),
          ),
          SizedBox(
            width: 240,
            child: SelectField(
              label: 'المخزن',
              value: _wh,
              items: [('', 'كل المخازن'), for (final w in s.warehouses) (w.id, w.name)],
              onChanged: (v) => setState(() => _wh = v),
            ),
          ),
          SizedBox(
            width: 220,
            child: SelectField(
              label: 'المستوى',
              value: _level,
              items: [('', 'كل الأصناف'), ('attention', 'تحتاج توريداً'), for (final e in stockLevelLabels.entries) (e.key, e.value)],
              onChanged: (v) => setState(() => _level = v),
            ),
          ),
        ]),
        const SizedBox(height: 12),
        SectionCard(
          title: 'الأرصدة (${rows.length})',
          subtitle: 'المتاح = الفعلي − المحجوز. المحجوز ما اعتُمد صرفه أو تحويله ولم يُرحَّل بعد.',
          child: rows.isEmpty
              ? Text(_level == 'attention' ? 'لا صنف يحتاج توريداً.' : 'لا أصناف مطابقة.', style: TextStyle(color: sem.muted))
              : PmTable(
                  columns: const ['الصنف', 'الرمز', 'الوحدة', 'الفعلي', 'المحجوز', 'المتاح', 'المستوى'],
                  rows: [
                    for (final r in rows.take(500))
                      [r.$1.name, r.$1.code, s.unitName(r.$1.baseUnitId), fmtQty(r.$3), fmtQty(r.$4), fmtQty(r.$5), stockLevelLabels[r.$2] ?? r.$2],
                  ],
                  highlight: (i) => const {'out', 'min'}.contains(rows[i].$2),
                ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------
// صفحة الموظف: ما صُرف لي
// ---------------------------------------------------------------------

class StoresMinePage extends StatelessWidget {
  const StoresMinePage({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final s = app.stores;
    final sem = Sem.of(context);
    final me = app.myEmployee;
    final docs = me == null ? const <StDoc>[] : [for (final d in s.docsOfEmployee(me.id)) if (d.isPosted) d];
    final pending = docs.where((d) => d.kind == 'issue' && !d.isReversal && d.confirmedAt == null).length;
    return PageBody(
      onRefresh: app.loadAll,
      children: [
        PageHeader(
          title: 'ما صُرف لي',
          subtitle: 'ما صُرف لك من المخازن وما أرجعته، وتأكيد استلامك لكل مستند صرف.',
          icon: Icons.person_pin_outlined,
        ),
        if (me == null)
          const EmptyState(
            title: 'حسابك غير مربوط بسجل موظف',
            message: 'اطلب من مسؤول المخازن ربط حسابك بسجلك في سجل الموظفين لترى ما صُرف لك.',
            icon: Icons.link_off_rounded,
          )
        else ...[
          SectionCard(
            title: me.fullName,
            icon: Icons.badge_outlined,
            subtitle: [me.empNo, me.jobTitle, s.departmentPath(me.departmentId)].where((x) => x.isNotEmpty).join(' · '),
            child: Wrap(spacing: 10, runSpacing: 10, children: [
              ToneBadge('${docs.length} مستند', color: sem.na),
              if (pending > 0) ToneBadge('$pending بانتظار تأكيد استلامك', color: sem.wip, icon: Icons.touch_app_outlined),
            ]),
          ),
          const SizedBox(height: 14),
          if (docs.isEmpty)
            const EmptyState(title: 'لم يُصرف لك شيء بعد', icon: Icons.inventory_2_outlined)
          else
            for (final d in docs) ...[_MineDoc(doc: d), const SizedBox(height: 10)],
        ],
      ],
    );
  }
}

class _MineDoc extends StatelessWidget {
  const _MineDoc({required this.doc});

  final StDoc doc;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final s = app.stores;
    final sem = Sem.of(context);
    final lines = s.linesOf(doc.id);
    final canConfirm = doc.kind == 'issue' && !doc.isReversal && doc.confirmedAt == null && !app.settings.frozen;
    return SectionCard(
      title: '${doc.title} ${isolate(doc.docNo)}',
      subtitle: '${dayText(doc.docDate)} · ${s.warehouseName(doc.warehouseId)}',
      trailing: doc.confirmedAt != null
          ? ToneBadge('أكّدتَ الاستلام', color: sem.ok, icon: Icons.verified_outlined)
          : (canConfirm
              ? FilledButton.tonalIcon(
                  onPressed: () => storesRun(context, () => app.stConfirmReceipt(doc.id), success: 'سُجّل تأكيد استلامك'),
                  icon: const Icon(Icons.check_rounded),
                  label: const Text('أكّد الاستلام'),
                )
              : null),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (final l in lines)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(children: [
              Expanded(child: Text(s.itemName(l.itemId))),
              Text(qtyWithUnit(l.qty, s.unitName(l.unitId)), style: _tabular.copyWith(fontWeight: FontWeight.w700)),
            ]),
          ),
        if (doc.note.isNotEmpty) ...[const SizedBox(height: 6), Text(doc.note, style: TextStyle(color: sem.muted))],
      ]),
    );
  }
}
