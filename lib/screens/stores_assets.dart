import 'package:flutter/material.dart';

import '../app_state.dart';
import '../assets.dart';
import '../docs.dart' show isolate;
import '../models.dart';
import '../registers.dart' show isoDay;
import '../print/custody_form.dart';
import '../print/export_dialog.dart' show ExportButton;
import '../print/labels.dart';
import '../print/output.dart' show openBytes;
import '../stores.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';
import 'contract_finance.dart' show DayField;
import 'stores.dart' show pickStoreEmployee, storesRun;
import 'stores_setup.dart' show startStoresImport, storeFormDialog;

// =====================================================================
// قسم المخازن: الأصول والعُهد والإهلاك (الإصدار 1.8.0، الترحيل 39): سجل الأصول، وصفحة الأصل بإهلاكه وعهده
// وسجل حياته، والتسليم والإرجاع والنقل وتغيير الوضع والاستبعاد، وصفحة العهد.
// =====================================================================

const _tabular = TextStyle(fontFeatures: [FontFeature.tabularFigures()]);

/// لون وضع الأصل.
Color assetStatusColor(Sem sem, String status) => switch (status) {
      'available' => sem.ok,
      'in_use' || 'custody' => sem.na,
      'maintenance' || 'disposal' => sem.wip,
      'damaged' => sem.danger,
      _ => sem.muted,
    };

String _money(double v) => '${fmtMoney(v)} $currencyLabel';

/// قبل تطبيق الترحيل 39.
class AssetsNotReady extends StatelessWidget {
  const AssetsNotReady({super.key});

  @override
  Widget build(BuildContext context) => const InfoBanner(
        level: 'warning',
        icon: Icons.storage_rounded,
        text: 'الأصول والعهد تحتاج تحديث قاعدة البيانات (الترحيل 39)، أو لا صلاحية لك فيها. يمنحها المدير بنطاق «مسؤول الأصول والعهد».',
      );
}

/// مكان الأصل نصاً: المخزن، أو الموقع والإدارة.
String assetPlace(StoresData s, StAsset a) {
  final parts = <String>[
    if (a.warehouseId != null) 'مخزن ${s.warehouseName(a.warehouseId)}',
    if (a.warehouseId == null && a.locationId != null) s.locationPath(a.locationId),
    if (a.departmentId != null) s.department(a.departmentId)?.name ?? '',
  ];
  return parts.where((x) => x.isNotEmpty).join(' · ');
}

void openStoreAsset(BuildContext context, String assetId) =>
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => StoreAssetPage(assetId: assetId)));

// ---------------------------------------------------------------------
// سجل الأصول
// ---------------------------------------------------------------------

class StoresAssetsPage extends StatefulWidget {
  const StoresAssetsPage({super.key});

  @override
  State<StoresAssetsPage> createState() => _StoresAssetsPageState();
}

class _StoresAssetsPageState extends State<StoresAssetsPage> {
  final _q = TextEditingController();
  String _cat = '';
  String _status = '';
  String _dep = '';

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  List<StAsset> _filtered(AppState app) {
    final q = _q.text.trim();
    final s = app.stores;
    return [
      for (final a in app.storeAssets.assets)
        if ((_status == 'all' || (_status.isEmpty ? !a.isDisposed : a.status == _status)) &&
            (_cat.isEmpty || a.categoryId == _cat) &&
            (_dep.isEmpty || a.departmentId == _dep) &&
            (a.matches(q) || (q.isNotEmpty && (s.employee(a.employeeId)?.fullName.contains(q) ?? false))))
          a,
    ];
  }

  Future<void> _labels(List<StAsset> list) async {
    if (list.isEmpty) return;
    final s = AppScope.read(context).stores;
    await storesRun(context, () async {
      final bytes = await buildItemLabels([
        for (final a in list) (code: a.tag, name: a.name, barcode: '', unit: s.category(a.categoryId)?.name ?? ''),
      ]);
      await openBytes(bytes, 'ملصقات الأصول', 'pdf');
    });
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final s = app.stores;
    final r = app.storeAssets;
    final sem = Sem.of(context);
    final today = DateTime.now();
    final list = _filtered(app);
    final totals = r.totals(today);
    final shownTotals = r.totals(today, of: list);
    final cats = [for (final c in s.categories) if (c.isAsset) c];
    final pending = r.pendingDisposal;
    return PageBody(
      onRefresh: app.loadAll,
      children: [
        PageHeader(
          title: 'الأصول',
          subtitle: 'سجل الأصول برقم وملصق لكل أصل، ومكانه ووضعه وعهدته، وقيمته الدفترية بعد الإهلاك.',
          icon: Icons.chair_alt_rounded,
          actions: [
            if (app.canStoresAssets)
              FilledButton.icon(onPressed: () => showAssetEditor(context), icon: const Icon(Icons.add_rounded), label: const Text('أصل جديد')),
            if (app.canStoresAssets)
              OutlinedButton.icon(
                onPressed: () => startStoresImport(context, 'assets'),
                icon: const Icon(Icons.upload_file_rounded),
                label: const Text('استيراد من Excel'),
              ),
            if (list.isNotEmpty)
              OutlinedButton.icon(onPressed: () => _labels(list), icon: const Icon(Icons.qr_code_2_rounded), label: const Text('ملصقات')),
            if (app.storesAssetsSees) ExportButton(sourceId: 'stores:assets', items: list),
          ],
        ),
        if (!app.storesAssetsSees) ...[const AssetsNotReady(), const SizedBox(height: 14)],
        ResponsiveGrid(minItemWidth: 165, children: [
          KpiTile(label: 'الأصول القائمة', value: '${r.active.length}', sub: '${r.countStatus('disposed')} مستبعد'),
          KpiTile(
            label: 'في العهدة',
            value: '${r.countStatus('custody')}',
            sub: r.unconfirmed.isEmpty ? 'كلها مؤكدة' : '${r.unconfirmed.length} بانتظار تأكيد الموظف',
            color: r.unconfirmed.isEmpty ? null : sem.wip,
            onTap: () => app.setTab(AppState.storesCustodyTab),
          ),
          KpiTile(
            label: 'تحت الصيانة أو معطّلة',
            value: '${r.countStatus('maintenance') + r.countStatus('damaged')}',
            color: r.countStatus('damaged') > 0 ? sem.danger : null,
          ),
          KpiTile(
            label: 'بانتظار الاستبعاد',
            value: '${pending.length}',
            color: pending.isEmpty ? null : sem.wip,
            onTap: () => setState(() => _status = 'disposal'),
          ),
          KpiTile(label: 'التكلفة', value: fmtMoney(totals.cost), sub: currencyLabel),
          KpiTile(label: 'القيمة الدفترية', value: fmtMoney(totals.book), sub: 'في ${dayText(today)}'),
        ]),
        if (pending.isNotEmpty && app.canStoresApprove) ...[
          const SizedBox(height: 12),
          InfoBanner(
            level: 'warning',
            icon: Icons.delete_sweep_outlined,
            text: '${arCount(pending.length, one: 'طلب', two: 'طلبان', few: 'طلبات', many: 'طلباً')} استبعاد بانتظار اعتمادك: '
                '${pending.take(4).map((a) => a.tag).join('، ')}${pending.length > 4 ? '…' : ''}',
          ),
        ],
        const SizedBox(height: 14),
        Wrap(spacing: 10, runSpacing: 10, children: [
          SizedBox(
            width: 300,
            child: TextField(
              controller: _q,
              onChanged: (_) => setState(() {}),
              decoration: fieldDeco('بحث بالرقم أو الوصف أو التسلسلي أو المستلم', prefixIcon: const Icon(Icons.search_rounded)),
            ),
          ),
          SizedBox(
            width: 220,
            child: SelectField(
              label: 'التصنيف',
              value: _cat,
              items: [('', 'كل التصنيفات'), for (final c in cats) (c.id, c.name)],
              onChanged: (v) => setState(() => _cat = v),
            ),
          ),
          SizedBox(
            width: 200,
            child: SelectField(
              label: 'الوضع',
              value: _status,
              items: [('', 'القائمة'), for (final e in assetStatusLabels.entries) (e.key, e.value), ('all', 'الكل')],
              onChanged: (v) => setState(() => _status = v),
            ),
          ),
          SizedBox(
            width: 220,
            child: SelectField(
              label: 'الإدارة',
              value: _dep,
              items: [('', 'كل الإدارات'), for (final d in s.departments) (d.id, d.name)],
              onChanged: (v) => setState(() => _dep = v),
            ),
          ),
        ]),
        const SizedBox(height: 12),
        SectionCard(
          title: 'السجل (${list.length})',
          icon: Icons.list_alt_rounded,
          subtitle: list.isEmpty ? null : 'التكلفة ${_money(shownTotals.cost)} · الدفترية ${_money(shownTotals.book)}',
          child: list.isEmpty
              ? Text(r.assets.isEmpty ? 'لا أصول مسجلة بعد. أضفها واحداً واحداً أو استوردها من Excel.' : 'لا أصول بهذا البحث.',
                  style: TextStyle(color: sem.muted))
              : LayoutBuilder(builder: (context, c) {
                  final wide = c.maxWidth >= 760;
                  return Column(children: [
                    if (wide) const _AssetsHeader(),
                    for (final a in list.take(400)) _AssetRow(asset: a, wide: wide, today: today),
                    if (list.length > 400)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text('يُعرض أول 400 أصل؛ ضيّق البحث لرؤية البقية.', style: TextStyle(color: sem.muted)),
                      ),
                  ]);
                }),
        ),
      ],
    );
  }
}

const _assetCols = [('الوضع', 120.0), ('المكان أو المستلم', 220.0), ('التكلفة', 110.0), ('الدفترية', 110.0)];

class _AssetsHeader extends StatelessWidget {
  const _AssetsHeader();

  @override
  Widget build(BuildContext context) {
    final st = TextStyle(color: Sem.of(context).muted, fontSize: 12, fontWeight: FontWeight.w600);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 6),
      child: Row(children: [
        Expanded(child: Text('الأصل', style: st)),
        for (final c in _assetCols) SizedBox(width: c.$2, child: Text(c.$1, style: st, textAlign: TextAlign.center)),
      ]),
    );
  }
}

class _AssetRow extends StatelessWidget {
  const _AssetRow({required this.asset, required this.wide, required this.today});

  final StAsset asset;
  final bool wide;
  final DateTime today;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final s = app.stores;
    final sem = Sem.of(context);
    final a = asset;
    final holder = a.inCustody ? s.employee(a.employeeId)?.fullName ?? '' : assetPlace(s, a);
    final title = Text.rich(TextSpan(children: [
      TextSpan(text: isolate(a.tag), style: const TextStyle(fontWeight: FontWeight.w600)),
      TextSpan(text: ' · ${a.name}'),
    ]), maxLines: 2, overflow: TextOverflow.ellipsis);
    final sub = Text(
      [s.category(a.categoryId)?.name ?? '', [a.manufacturer, a.model].where((x) => x.isNotEmpty).join(' '), if (a.serialNo.isNotEmpty) 'SN ${a.serialNo}']
          .where((x) => x.isNotEmpty)
          .join(' · '),
      style: TextStyle(color: sem.muted, fontSize: 12.5),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
    final badge = ToneBadge(a.statusLabel, color: assetStatusColor(sem, a.status));
    if (wide) {
      return InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => openStoreAsset(context, a.id),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
          child: Row(children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [title, const SizedBox(height: 2), sub])),
            SizedBox(width: _assetCols[0].$2, child: Center(child: badge)),
            SizedBox(
              width: _assetCols[1].$2,
              child: Text(holder.isEmpty ? '—' : holder,
                  textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: sem.muted, fontSize: 12.5)),
            ),
            SizedBox(width: _assetCols[2].$2, child: Text(fmtMoney(a.cost), textAlign: TextAlign.center, style: _tabular)),
            SizedBox(
              width: _assetCols[3].$2,
              child: Text(fmtMoney(a.bookValue(today)), textAlign: TextAlign.center, style: _tabular.copyWith(fontWeight: FontWeight.w700)),
            ),
          ]),
        ),
      );
    }
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      title: title,
      subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        sub,
        if (holder.isNotEmpty) Text(holder, style: TextStyle(color: sem.muted, fontSize: 12.5), maxLines: 1, overflow: TextOverflow.ellipsis),
      ]),
      trailing: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.end, children: [
        badge,
        const SizedBox(height: 4),
        Text(fmtMoney(a.bookValue(today)), style: _tabular.copyWith(fontWeight: FontWeight.w700)),
      ]),
      onTap: () => openStoreAsset(context, a.id),
    );
  }
}

// ---------------------------------------------------------------------
// صفحة الأصل
// ---------------------------------------------------------------------

class StoreAssetPage extends StatefulWidget {
  const StoreAssetPage({super.key, required this.assetId, this.initialEvents, this.today});

  final String assetId;

  /// سجل الحياة جاهزاً (للقطات الاختبار دون شبكة).
  final List<StAssetEvent>? initialEvents;

  /// تاريخ الاحتساب (للقطات الاختبار)؛ الافتراضي اليوم.
  final DateTime? today;

  @override
  State<StoreAssetPage> createState() => _StoreAssetPageState();
}

class _StoreAssetPageState extends State<StoreAssetPage> {
  List<StAssetEvent>? _events;

  @override
  void initState() {
    super.initState();
    if (widget.initialEvents != null) {
      _events = widget.initialEvents;
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) => _load());
    }
  }

  Future<void> _load() async {
    try {
      final e = await AppScope.read(context).stAssetEventsOf(widget.assetId);
      if (mounted) setState(() => _events = e);
    } catch (_) {
      if (mounted) setState(() => _events = const []);
    }
  }

  Future<void> _printCustody(StCustody c) async {
    final app = AppScope.read(context);
    final s = app.stores;
    final a = app.storeAssets.asset(c.assetId);
    final e = s.employee(c.employeeId);
    if (a == null) return;
    await storesRun(context, () async {
      final bytes = await buildCustodyForm((
        org: app.orgName,
        custodyNo: c.custodyNo,
        handedOn: dayText(c.handedOn),
        employee: e?.fullName ?? '',
        empNo: e?.empNo ?? '',
        department: s.departmentPath(c.departmentId),
        jobTitle: e?.jobTitle ?? '',
        tag: a.tag,
        asset: a.name,
        category: s.category(a.categoryId)?.name ?? '',
        description: [a.manufacturer, a.model].where((x) => x.isNotEmpty).join(' '),
        serialNo: a.serialNo,
        location: s.locationPath(c.locationId),
        conditionOut: assetConditionLabels[c.conditionOut] ?? c.conditionOut,
        accessoriesOut: c.accessoriesOut,
        noteOut: c.noteOut,
        returnedOn: dayText(c.returnedOn),
        conditionIn: assetConditionLabels[c.conditionIn] ?? '',
        accessoriesIn: c.accessoriesIn,
        noteIn: c.noteIn,
      ));
      await openBytes(bytes, 'محضر عهدة ${c.custodyNo}', 'pdf');
    });
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final s = app.stores;
    final r = app.storeAssets;
    final sem = Sem.of(context);
    final a = r.asset(widget.assetId);
    if (a == null) {
      return Scaffold(appBar: AppBar(), body: const Center(child: Text('الأصل غير موجود أو حُذف.')));
    }
    final today = widget.today ?? DateTime.now();
    final can = app.canStoresAssets;
    final open = r.openCustodyOf(a.id);
    final history = r.custodyOfAsset(a.id);
    final cat = s.category(a.categoryId);
    final acc = a.accumulated(today);
    final book = a.bookValue(today);
    return Scaffold(
      appBar: AppBar(
        title: Text(isolate(a.tag)),
        actions: [
          IconButton(
            tooltip: 'طباعة الملصق',
            icon: const Icon(Icons.qr_code_2_rounded),
            onPressed: () => storesRun(context, () async {
              final bytes = await buildItemLabels([(code: a.tag, name: a.name, barcode: '', unit: cat?.name ?? '')], copies: 3);
              await openBytes(bytes, 'ملصق ${a.tag}', 'pdf');
            }),
          ),
          if (can && a.isEditable)
            IconButton(tooltip: 'تعديل البيانات', icon: const Icon(Icons.edit_outlined), onPressed: () => showAssetEditor(context, asset: a)),
        ],
      ),
      body: PageBody(children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(a.name, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text([cat?.name ?? '', assetPlace(s, a)].where((x) => x.isNotEmpty).join(' · '), style: TextStyle(color: sem.muted)),
            ]),
          ),
          const SizedBox(width: 8),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            ToneBadge(a.statusLabel, color: assetStatusColor(sem, a.status)),
            const SizedBox(height: 6),
            Text('الحالة: ${a.conditionLabel}', style: TextStyle(color: sem.muted, fontSize: 12.5)),
          ]),
        ]),
        const SizedBox(height: 12),
        if (can || app.canDecideDisposal(a)) ...[
          Wrap(spacing: 8, runSpacing: 8, children: [
            if (can && a.canHandOver)
              FilledButton.icon(
                onPressed: () => _custodyOut(context, a).then((ok) {
                  if (ok) _reloadEvents();
                }),
                icon: const Icon(Icons.assignment_ind_outlined),
                label: const Text('تسليم عهدة'),
              ),
            if (can && open != null)
              FilledButton.tonalIcon(
                onPressed: () => _custodyIn(context, open).then((ok) {
                  if (ok) _reloadEvents();
                }),
                icon: const Icon(Icons.assignment_return_outlined),
                label: const Text('استلام العهدة'),
              ),
            if (can && a.isEditable)
              OutlinedButton.icon(
                onPressed: () => _transfer(context, a).then((ok) {
                  if (ok) _reloadEvents();
                }),
                icon: const Icon(Icons.swap_horiz_rounded),
                label: const Text('نقل'),
              ),
            if (can && a.isFree)
              OutlinedButton.icon(
                onPressed: () => _status(context, a).then((ok) {
                  if (ok) _reloadEvents();
                }),
                icon: const Icon(Icons.build_circle_outlined),
                label: const Text('تغيير الوضع'),
              ),
            if (can && a.isFree)
              OutlinedButton.icon(
                onPressed: () => _disposeRequest(context, a).then((ok) {
                  if (ok) _reloadEvents();
                }),
                icon: const Icon(Icons.delete_sweep_outlined),
                label: const Text('طلب استبعاد'),
              ),
            if (app.canDecideDisposal(a)) ...[
              FilledButton.icon(
                onPressed: () => _decide(context, a, true).then((ok) {
                  if (ok) _reloadEvents();
                }),
                icon: const Icon(Icons.check_rounded),
                label: const Text('اعتماد الاستبعاد'),
              ),
              OutlinedButton.icon(
                onPressed: () => _decide(context, a, false).then((ok) {
                  if (ok) _reloadEvents();
                }),
                icon: const Icon(Icons.close_rounded),
                label: const Text('رفض'),
              ),
            ],
            if (can && a.isFree && history.isEmpty)
              TextButton.icon(
                onPressed: () => _delete(context, a),
                icon: Icon(Icons.delete_outline_rounded, color: sem.danger),
                label: Text('حذف', style: TextStyle(color: sem.danger)),
              ),
          ]),
          const SizedBox(height: 12),
        ],
        if (a.isDisposal)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: InfoBanner(
              level: 'warning',
              icon: Icons.delete_sweep_outlined,
              text: 'طلب ${disposalKindLabels[a.disposalKind] ?? ''}${a.disposalValue != null ? ' بقيمة ${_money(a.disposalValue!)}' : ''} '
                  'بتاريخ ${dayText(a.disposalRequestedAt)}: ${a.disposalReason}. ينتظر اعتماد مدير المخازن أو المدير'
                  '${s.settings.separation ? '، ولا يعتمده من طلبه' : ''}.',
            ),
          ),
        if (a.isDisposed)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: InfoBanner(
              icon: Icons.block_rounded,
              text: 'مستبعد (${disposalKindLabels[a.disposalKind] ?? ''}) بتاريخ ${dayText(a.disposalDate)}'
                  '${a.disposalValue != null ? ' بقيمة ${_money(a.disposalValue!)}' : ''}: ${a.disposalReason}'
                  '${a.decisionNote.isEmpty ? '' : ' — ${a.decisionNote}'}. توقف إهلاكه عند تاريخ استبعاده.',
            ),
          ),
        if (open != null) ...[
          _CurrentCustody(custody: open, onPrint: () => _printCustody(open)),
          const SizedBox(height: 12),
        ],
        ResponsiveGrid(minItemWidth: 150, children: [
          KpiTile(label: 'التكلفة', value: fmtMoney(a.cost), sub: currencyLabel),
          KpiTile(label: 'الإهلاك المتراكم', value: fmtMoney(acc), sub: a.depMethod == 'none' ? 'بلا إهلاك' : '${monthsBetween(a.depStart ?? today, today)} شهراً'),
          KpiTile(label: 'القيمة الدفترية', value: fmtMoney(book), sub: 'في ${dayText(a.isDisposed && a.disposalDate != null ? a.disposalDate : today)}', color: sem.ok),
          KpiTile(
            label: 'القسط الشهري',
            value: fmtMoney(a.monthlyDepreciation),
            sub: a.depMethod == 'none' ? 'بلا إهلاك' : 'باقٍ ${a.monthsLeft(today)} شهراً',
          ),
        ]),
        const SizedBox(height: 14),
        SectionCard(
          title: 'بيانات الأصل',
          icon: Icons.badge_outlined,
          child: Wrap(spacing: 24, runSpacing: 14, children: [
            _Field('رقم الأصل', isolate(a.tag)),
            _Field('التصنيف', cat == null ? '' : '${cat.name} (${cat.code})'),
            if (a.itemId != null) _Field('الصنف', s.itemName(a.itemId!)),
            _Field('المصنع', a.manufacturer),
            _Field('الموديل', a.model),
            _Field('الرقم التسلسلي', a.serialNo),
            _Field('تاريخ الشراء', dayText(a.purchaseDate)),
            _Field('بدء الاستخدام', dayText(a.inServiceDate)),
            _Field('المورد', a.supplier),
            _Field('رقم الفاتورة', a.invoiceNo),
            _Field('نهاية الضمان', a.warrantyUntil == null ? '' : '${dayText(a.warrantyUntil)}${a.underWarranty(today) ? ' (ساري)' : ' (انتهى)'}'),
            _Field('طريقة الإهلاك', depMethodLabels[a.depMethod] ?? a.depMethod),
            if (a.depMethod == 'straight') _Field('العمر', '${a.lifeMonths ?? '-'} شهراً'),
            _Field('الخردة', fmtMoney(a.salvage)),
            if (a.note.isNotEmpty) _Field('ملاحظات', a.note),
          ]),
        ),
        const SizedBox(height: 14),
        SectionCard(
          title: 'سجل العهد (${history.length})',
          icon: Icons.assignment_ind_outlined,
          child: history.isEmpty
              ? Text('لم يُسلَّم عهدة بعد.', style: TextStyle(color: sem.muted))
              : Column(children: [
                  for (final c in history)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(c.isOpen ? Icons.assignment_ind_rounded : Icons.assignment_turned_in_outlined,
                          color: c.isOpen ? sem.na : sem.muted),
                      title: Text.rich(TextSpan(children: [
                        TextSpan(text: isolate(c.custodyNo), style: const TextStyle(fontWeight: FontWeight.w600)),
                        TextSpan(text: ' · ${s.employee(c.employeeId)?.fullName ?? ''}'),
                      ])),
                      subtitle: Text(
                        'سُلّم ${dayText(c.handedOn)} (${assetConditionLabels[c.conditionOut] ?? ''})'
                        '${c.returnedOn == null ? ' · ما زال في عهدته' : ' · أُرجع ${dayText(c.returnedOn)} (${assetConditionLabels[c.conditionIn] ?? ''})'}'
                        '${c.confirmedAt == null ? ' · لم يؤكد الاستلام' : ''}',
                        style: TextStyle(color: sem.muted, fontSize: 12.5),
                      ),
                      trailing: IconButton(tooltip: 'طباعة المحضر', icon: const Icon(Icons.print_outlined), onPressed: () => _printCustody(c)),
                    ),
                ]),
        ),
        const SizedBox(height: 14),
        SectionCard(
          title: 'سجل حياة الأصل',
          icon: Icons.history_rounded,
          child: _events == null
              ? const Padding(padding: EdgeInsets.all(12), child: Center(child: CircularProgressIndicator()))
              : _events!.isEmpty
                  ? Text('لا أحداث.', style: TextStyle(color: sem.muted))
                  : Column(children: [
                      for (final e in _events!.reversed)
                        ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(_eventIcon(e.kind), size: 20, color: sem.muted),
                          title: Text(_eventText(s, e)),
                          subtitle: Text(
                            '${e.at == null ? '' : dayText(e.at)} · ${e.byUser == null ? '' : (app.people[e.byUser]?.displayName ?? '')}${e.note.isEmpty ? '' : ' — ${e.note}'}',
                            style: TextStyle(color: sem.muted, fontSize: 12),
                          ),
                        ),
                    ]),
        ),
      ]),
    );
  }

  void _reloadEvents() {
    if (widget.initialEvents == null) _load();
  }

  Future<void> _delete(BuildContext context, StAsset a) async {
    final ok = await confirmDialog(context,
        title: 'حذف الأصل ${a.tag}؟',
        message: 'يُحذف الأصل المسجل خطأً وسجل حياته، ويبقى أثره في سجل التدقيق.',
        confirmLabel: 'حذف',
        danger: true);
    if (!ok || !context.mounted) return;
    if (await storesRun(context, () => AppScope.read(context).stDeleteAsset(a.id), success: 'حُذف الأصل') && context.mounted) {
      Navigator.of(context).pop();
    }
  }
}

IconData _eventIcon(String kind) => switch (kind) {
      'create' => Icons.add_circle_outline_rounded,
      'update' => Icons.edit_outlined,
      'transfer' => Icons.swap_horiz_rounded,
      'status' => Icons.build_circle_outlined,
      'custody_out' => Icons.assignment_ind_outlined,
      'custody_in' => Icons.assignment_return_outlined,
      'dispose_request' => Icons.delete_sweep_outlined,
      'dispose' => Icons.block_rounded,
      _ => Icons.undo_rounded,
    };

String _eventText(StoresData s, StAssetEvent e) {
  final d = e.data;
  String st(Object? x) => assetStatusLabels['${x ?? ''}'] ?? '';
  String cond(Object? x) => assetConditionLabels['${x ?? ''}'] ?? '';
  return switch (e.kind) {
    'create' => d['import'] == true ? 'سُجّل من ملف الاستيراد' : 'سُجّل الأصل بتكلفة ${fmtMoney((d['cost'] as num?)?.toDouble() ?? 0)}',
    'update' => d['import'] == true
        ? 'حُدّثت بياناته من ملف الاستيراد'
        : 'عُدّلت بياناته${d['changed'] is List && (d['changed'] as List).isNotEmpty ? ' (${(d['changed'] as List).length} حقل)' : ''}',
    'transfer' => () {
        final to = d['to'] is Map ? d['to'] as Map : const {};
        final w = to['warehouse_id'];
        final place = w != null ? 'مخزن ${s.warehouseName('$w')}' : s.locationPath(to['location_id'] as String?);
        final dep = s.department(to['department_id'] as String?)?.name ?? '';
        return 'نُقل إلى ${[place, dep].where((x) => x.isNotEmpty).join(' · ')}';
      }(),
    'status' => 'تغيّر وضعه من «${st(d['from'])}» إلى «${st(d['to'])}» (الحالة: ${cond(d['condition_to'])})',
    'custody_out' => 'سُلّم عهدةً إلى ${d['employee'] ?? ''} بالمحضر ${isolate('${d['custody_no'] ?? ''}')}',
    'custody_in' => 'أُرجع من ${d['employee'] ?? ''} بحالة ${cond(d['condition'])}، ووضعه «${st(d['to_status'])}»',
    'dispose_request' => 'طُلب استبعاده (${disposalKindLabels['${d['kind'] ?? ''}'] ?? ''})',
    'dispose' => 'اعتُمد استبعاده، وقيمته الدفترية يومها ${fmtMoney((d['book_value'] as num?)?.toDouble() ?? 0)}',
    'dispose_reject' => 'رُفض استبعاده، وعاد «${st(d['to_status'])}»',
    _ => e.label,
  };
}

class _CurrentCustody extends StatelessWidget {
  const _CurrentCustody({required this.custody, required this.onPrint});

  final StCustody custody;
  final VoidCallback onPrint;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final s = app.stores;
    final sem = Sem.of(context);
    final c = custody;
    final e = s.employee(c.employeeId);
    return SectionCard(
      title: 'في عهدة ${e?.fullName ?? ''}',
      icon: Icons.assignment_ind_rounded,
      subtitle: '${isolate(c.custodyNo)} · منذ ${dayText(c.handedOn)} (${c.days(DateTime.now())} يوماً)',
      trailing: IconButton(tooltip: 'طباعة المحضر', icon: const Icon(Icons.print_outlined), onPressed: onPrint),
      child: Wrap(spacing: 24, runSpacing: 12, children: [
        _Field('الرقم الوظيفي', e?.empNo ?? ''),
        _Field('الإدارة', s.departmentPath(c.departmentId)),
        _Field('الحالة عند التسليم', assetConditionLabels[c.conditionOut] ?? ''),
        _Field('الملحقات', c.accessoriesOut),
        Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text('تأكيد الموظف', style: TextStyle(color: sem.muted, fontSize: 12)),
          const SizedBox(height: 4),
          c.confirmedAt == null
              ? ToneBadge('لم يؤكد الاستلام بعد', color: sem.wip, icon: Icons.hourglass_top_rounded)
              : ToneBadge('أكّد ${dayText(c.confirmedAt)}', color: sem.ok, icon: Icons.verified_outlined),
        ]),
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
        Text(value.isEmpty ? '—' : value),
      ]),
    );
  }
}

// ---------------------------------------------------------------------
// النوافذ: التسليم والإرجاع والنقل والوضع والاستبعاد
// ---------------------------------------------------------------------

Future<bool> _custodyOut(BuildContext context, StAsset a) async {
  final app = AppScope.read(context);
  StEmployee? emp;
  DateTime? on = DateTime.now();
  var cond = a.condition == 'damaged' ? 'good' : a.condition;
  final acc = TextEditingController();
  final note = TextEditingController();
  var done = false;
  await storeFormDialog(
    context,
    title: 'تسليم ${a.tag} عهدةً',
    body: (setLocal) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () async {
          final e = await pickStoreEmployee(context);
          if (e != null) setLocal(() => emp = e);
        },
        child: InputDecorator(
          decoration: fieldDeco('الموظف المستلم', prefixIcon: const Icon(Icons.person_search_outlined)),
          child: Text(emp == null ? 'اختر الموظف' : '${emp!.label} — ${app.stores.department(emp!.departmentId)?.name ?? ''}'),
        ),
      ),
      const SizedBox(height: 10),
      DayField(label: 'تاريخ التسليم', value: on, onChanged: (d) => setLocal(() => on = d)),
      const SizedBox(height: 10),
      SelectField(
        label: 'الحالة عند التسليم',
        value: cond,
        items: [for (final e in assetConditionLabels.entries) if (e.key != 'damaged') (e.key, e.value)],
        onChanged: (v) => setLocal(() => cond = v),
      ),
      const SizedBox(height: 10),
      TextField(controller: acc, decoration: fieldDeco('الملحقات', hint: 'شاحن، حقيبة، فأرة…')),
      const SizedBox(height: 10),
      TextField(controller: note, decoration: fieldDeco('ملاحظات')),
    ]),
    onSave: () async {
      if (emp == null) throw StateError('اختر الموظف المستلم');
      await app.stCustodyOut(a.id, {
        'employee_id': emp!.id,
        'handed_on': isoDay(on ?? DateTime.now()),
        'condition': cond,
        'accessories': acc.text.trim(),
        'note': note.text.trim(),
      });
      done = true;
    },
  );
  return done;
}

Future<bool> _custodyIn(BuildContext context, StCustody c) async {
  final app = AppScope.read(context);
  final s = app.stores;
  DateTime? on = DateTime.now();
  var cond = '';
  var status = '';
  var wh = '';
  final acc = TextEditingController(text: c.accessoriesOut);
  final note = TextEditingController();
  var done = false;
  await storeFormDialog(
    context,
    title: 'استلام العهدة ${c.custodyNo}',
    body: (setLocal) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text('من ${s.employee(c.employeeId)?.fullName ?? ''} — سُلّمت ${dayText(c.handedOn)}', style: TextStyle(color: Sem.of(context).muted)),
      const SizedBox(height: 10),
      DayField(label: 'تاريخ الإرجاع', value: on, onChanged: (d) => setLocal(() => on = d)),
      const SizedBox(height: 10),
      SelectField(
        label: 'الحالة عند الإرجاع',
        value: cond,
        items: [('', 'اختر الحالة'), for (final e in assetConditionLabels.entries) (e.key, e.value)],
        onChanged: (v) => setLocal(() {
          cond = v;
          if (v == 'damaged') status = 'damaged';
        }),
      ),
      const SizedBox(height: 10),
      SelectField(
        label: 'وضع الأصل بعد الإرجاع',
        value: status,
        items: const [('', 'تلقائي: متاح، أو معطّل إن كان تالفاً'), ('available', 'متاح'), ('maintenance', 'تحت الصيانة'), ('damaged', 'معطّل')],
        onChanged: (v) => setLocal(() => status = v),
      ),
      const SizedBox(height: 10),
      SelectField(
        label: 'يُحفظ في',
        value: wh,
        items: [('', 'يبقى في موقعه'), for (final w in s.warehouses) if (w.active) (w.id, 'مخزن ${w.name}')],
        onChanged: (v) => setLocal(() => wh = v),
      ),
      const SizedBox(height: 10),
      TextField(controller: acc, decoration: fieldDeco('الملحقات المرجعة')),
      const SizedBox(height: 10),
      TextField(controller: note, decoration: fieldDeco('ملاحظات')),
    ]),
    onSave: () async {
      if (cond.isEmpty) throw StateError('حدد حالة الأصل عند الإرجاع');
      await app.stCustodyIn(c.id, {
        'returned_on': isoDay(on ?? DateTime.now()),
        'condition': cond,
        if (status.isNotEmpty) 'status': status,
        if (wh.isNotEmpty) 'warehouse_id': wh,
        'accessories': acc.text.trim(),
        'note': note.text.trim(),
      });
      done = true;
    },
  );
  return done;
}

Future<bool> _transfer(BuildContext context, StAsset a) async {
  final app = AppScope.read(context);
  final s = app.stores;
  var toStore = a.warehouseId != null && !a.inCustody;
  var wh = a.warehouseId ?? '';
  var loc = a.locationId ?? '';
  var dep = a.departmentId ?? '';
  final note = TextEditingController();
  var done = false;
  await storeFormDialog(
    context,
    title: 'نقل ${a.tag}',
    body: (setLocal) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (!a.inCustody) ...[
        SegmentedButton<bool>(
          segments: const [
            ButtonSegment(value: false, label: Text('إلى موقع أو إدارة'), icon: Icon(Icons.meeting_room_outlined)),
            ButtonSegment(value: true, label: Text('إلى مخزن'), icon: Icon(Icons.warehouse_outlined)),
          ],
          selected: {toStore},
          onSelectionChanged: (v) => setLocal(() => toStore = v.first),
        ),
        const SizedBox(height: 12),
      ] else
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Text('الأصل في عهدة موظف: يتغير موقعه أو إدارته ويبقى في عهدته.', style: TextStyle(color: Sem.of(context).muted)),
        ),
      if (toStore)
        SelectField(
          label: 'المخزن',
          value: wh,
          items: [('', 'اختر المخزن'), for (final w in s.warehouses) if (w.active) (w.id, w.name)],
          onChanged: (v) => setLocal(() => wh = v),
        )
      else
        SelectField(
          label: 'الموقع',
          value: loc,
          items: [('', 'بلا موقع'), for (final l in s.locations) if (l.active) (l.id, s.locationPath(l.id))],
          onChanged: (v) => setLocal(() => loc = v),
        ),
      const SizedBox(height: 10),
      SelectField(
        label: 'الإدارة',
        value: dep,
        items: [('', 'بلا إدارة'), for (final d in s.departments) if (d.active) (d.id, s.departmentPath(d.id))],
        onChanged: (v) => setLocal(() => dep = v),
      ),
      const SizedBox(height: 10),
      TextField(controller: note, decoration: fieldDeco('سبب النقل أو ملاحظة')),
    ]),
    onSave: () async {
      if (toStore && wh.isEmpty) throw StateError('اختر المخزن');
      await app.stAssetTransfer(a.id, {
        'warehouse_id': toStore ? wh : null,
        'location_id': toStore ? null : (loc.isEmpty ? null : loc),
        'department_id': dep.isEmpty ? null : dep,
        'note': note.text.trim(),
      });
      done = true;
    },
  );
  return done;
}

Future<bool> _status(BuildContext context, StAsset a) async {
  final app = AppScope.read(context);
  var status = a.status;
  var cond = a.condition;
  final note = TextEditingController();
  var done = false;
  await storeFormDialog(
    context,
    title: 'وضع ${a.tag}',
    width: 420,
    body: (setLocal) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SelectField(
        label: 'الوضع',
        value: status,
        items: [
          ('available', 'متاح'),
          if (a.warehouseId == null) ('in_use', 'مستخدم في موقعه'),
          ('maintenance', 'تحت الصيانة'),
          ('damaged', 'معطّل'),
        ],
        onChanged: (v) => setLocal(() {
          status = v;
          if (v == 'damaged') cond = 'damaged';
        }),
      ),
      const SizedBox(height: 10),
      SelectField(
        label: 'الحالة المادية',
        value: cond,
        items: [for (final e in assetConditionLabels.entries) (e.key, e.value)],
        onChanged: (v) => setLocal(() => cond = v),
      ),
      const SizedBox(height: 10),
      TextField(controller: note, decoration: fieldDeco('السبب أو ملاحظة')),
    ]),
    onSave: () async {
      await app.stAssetStatus(a.id, status, condition: cond, note: note.text);
      done = true;
    },
  );
  return done;
}

Future<bool> _disposeRequest(BuildContext context, StAsset a) async {
  final app = AppScope.read(context);
  var kind = 'scrap';
  final reason = TextEditingController();
  final value = TextEditingController();
  DateTime? date;
  var done = false;
  await storeFormDialog(
    context,
    title: 'طلب استبعاد ${a.tag}',
    body: (setLocal) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SelectField(
        label: 'نوع الاستبعاد',
        value: kind,
        items: [for (final e in disposalKindLabels.entries) (e.key, e.value)],
        onChanged: (v) => setLocal(() => kind = v),
      ),
      const SizedBox(height: 10),
      TextField(controller: reason, maxLines: 2, decoration: fieldDeco('السبب', hint: 'مثل: تلف لا يُصلح، أو تقادم')),
      if (kind == 'sale') ...[
        const SizedBox(height: 10),
        TextField(
          controller: value,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: fieldDeco('قيمة البيع ($currencyLabel)'),
        ),
      ],
      const SizedBox(height: 10),
      DayField(label: 'تاريخ الاستبعاد (اختياري؛ يوم الاعتماد إن تُرك)', value: date, onChanged: (d) => setLocal(() => date = d)),
      const SizedBox(height: 10),
      Text('القيمة الدفترية اليوم ${_money(a.bookValue(DateTime.now()))}. يعتمد الطلب مدير المخازن أو المدير، ولا يُقيَّد مالياً.',
          style: TextStyle(color: Sem.of(context).muted, fontSize: 12.5)),
    ]),
    onSave: () async {
      if (reason.text.trim().length < 3) throw StateError('اكتب سبب الاستبعاد');
      final v = value.text.trim().isEmpty ? null : parseImportNumber(value.text);
      await app.stAssetDisposeRequest(a.id, {
        'kind': kind,
        'reason': reason.text.trim(),
        if (kind == 'sale' && v != null) 'value': v,
        if (date != null) 'date': isoDay(date!),
      });
      done = true;
    },
  );
  return done;
}

Future<bool> _decide(BuildContext context, StAsset a, bool approve) async {
  final app = AppScope.read(context);
  final note = TextEditingController();
  var done = false;
  await storeFormDialog(
    context,
    title: approve ? 'اعتماد استبعاد ${a.tag}' : 'رفض استبعاد ${a.tag}',
    width: 420,
    body: (setLocal) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text('${disposalKindLabels[a.disposalKind] ?? ''}: ${a.disposalReason}'),
      const SizedBox(height: 10),
      TextField(controller: note, maxLines: 2, decoration: fieldDeco(approve ? 'ملاحظة (اختيارية)' : 'سبب الرفض')),
    ]),
    onSave: () async {
      if (!approve && note.text.trim().length < 3) throw StateError('اكتب سبب الرفض');
      await app.stAssetDisposeDecide(a.id, approve, note: note.text);
      done = true;
    },
  );
  return done;
}

// ---------------------------------------------------------------------
// تسجيل الأصل وتعديله
// ---------------------------------------------------------------------

Future<void> showAssetEditor(BuildContext context, {StAsset? asset}) =>
    showDialog<void>(context: context, builder: (_) => _AssetEditor(asset: asset));

class _AssetEditor extends StatefulWidget {
  const _AssetEditor({this.asset});

  final StAsset? asset;

  @override
  State<_AssetEditor> createState() => _AssetEditorState();
}

class _AssetEditorState extends State<_AssetEditor> {
  late final _name = TextEditingController(text: widget.asset?.name ?? '');
  late final _tag = TextEditingController(text: widget.asset?.tag ?? '');
  late final _maker = TextEditingController(text: widget.asset?.manufacturer ?? '');
  late final _model = TextEditingController(text: widget.asset?.model ?? '');
  late final _serial = TextEditingController(text: widget.asset?.serialNo ?? '');
  late final _cost = TextEditingController(text: widget.asset == null ? '' : moneyInput(widget.asset!.cost));
  late final _supplier = TextEditingController(text: widget.asset?.supplier ?? '');
  late final _invoice = TextEditingController(text: widget.asset?.invoiceNo ?? '');
  late final _life = TextEditingController(text: widget.asset?.lifeMonths?.toString() ?? '');
  late final _salvage = TextEditingController(text: widget.asset == null ? '' : moneyInput(widget.asset!.salvage));
  late final _note = TextEditingController(text: widget.asset?.note ?? '');
  late String _cat = widget.asset?.categoryId ?? '';
  late String _method = widget.asset?.depMethod ?? 'straight';
  late String _cond = widget.asset?.condition ?? 'new';
  late DateTime? _buy = widget.asset?.purchaseDate;
  late DateTime? _start = widget.asset?.inServiceDate;
  late DateTime? _warranty = widget.asset?.warrantyUntil;
  String _wh = '';
  String _loc = '';
  String _dep = '';
  bool _busy = false;
  String? _error;

  bool get _isNew => widget.asset == null;

  void _pickCategory(AppState app, String v) {
    setState(() {
      _cat = v;
      final p = app.storeAssets.policyOf(v);
      if (_isNew && p != null) {
        _method = p.depMethod;
        _life.text = p.lifeMonths?.toString() ?? '';
      }
    });
  }

  Future<void> _save() async {
    final app = AppScope.read(context);
    final cost = _cost.text.trim().isEmpty ? 0.0 : parseImportNumber(_cost.text);
    final life = int.tryParse(_life.text.trim());
    final salvage = _salvage.text.trim().isEmpty ? null : parseImportNumber(_salvage.text);
    String? err;
    if (_name.text.trim().length < 2) {
      err = 'اكتب وصف الأصل';
    } else if (_cat.isEmpty) {
      err = 'اختر التصنيف';
    } else if (cost == null || cost < 0) {
      err = 'التكلفة رقم موجب';
    } else if (_method == 'straight' && (life == null || life < 1 || life > 600)) {
      err = 'العمر بالأشهر عدد صحيح من 1 إلى 600';
    } else if (salvage != null && (salvage < 0 || salvage > cost)) {
      err = 'الخردة بين الصفر والتكلفة';
    }
    if (err != null) {
      setState(() => _error = err);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final id = await app.stSaveAsset(widget.asset?.id, {
        'name': _name.text.trim(),
        'tag': _tag.text.trim(),
        'category_id': _cat,
        'item_id': widget.asset?.itemId,
        'manufacturer': _maker.text.trim(),
        'model': _model.text.trim(),
        'serial_no': _serial.text.trim(),
        'purchase_date': _buy == null ? null : isoDay(_buy!),
        'in_service_date': _start == null ? null : isoDay(_start!),
        'cost': cost,
        'supplier': _supplier.text.trim(),
        'invoice_no': _invoice.text.trim(),
        'warranty_until': _warranty == null ? null : isoDay(_warranty!),
        'dep_method': _method,
        'life_months': _method == 'straight' ? life : null,
        if (salvage != null || !_isNew) 'salvage': salvage ?? 0,
        'condition': _cond,
        if (_isNew && _wh.isNotEmpty) 'warehouse_id': _wh,
        if (_isNew && _wh.isEmpty && _loc.isNotEmpty) 'location_id': _loc,
        if (_isNew && _dep.isNotEmpty) 'department_id': _dep,
        'note': _note.text.trim(),
      });
      if (!mounted) return;
      Navigator.of(context).pop();
      if (_isNew && id.isNotEmpty) {
        showToast(context, 'سُجّل الأصل');
        openStoreAsset(context, id);
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
    final cats = [for (final c in s.categories) if (c.isAsset && (c.active || c.id == _cat)) c];
    final policy = app.storeAssets.policyOf(_cat);
    Widget pair(Widget a, Widget b) => LayoutBuilder(builder: (context, c) {
          if (c.maxWidth < 460) return Column(children: [a, const SizedBox(height: 10), b]);
          return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(child: a), const SizedBox(width: 10), Expanded(child: b)]);
        });
    return AlertDialog(
      title: Text(_isNew ? 'أصل جديد' : 'تعديل ${widget.asset!.tag}'),
      content: SizedBox(
        width: 620,
        child: SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: _name, decoration: fieldDeco('وصف الأصل', hint: 'حاسوب محمول، مكتب خشبي بأدراج…')),
            const SizedBox(height: 10),
            pair(
              SelectField(
                label: 'التصنيف',
                value: _cat,
                items: [('', 'اختر تصنيف أصول'), for (final c in cats) (c.id, '${c.name} (${c.code})')],
                onChanged: (v) => _pickCategory(app, v),
              ),
              TextField(
                controller: _tag,
                textDirection: TextDirection.ltr,
                decoration: fieldDeco('رقم الأصل', helper: _isNew ? 'يُولَّد تلقائياً إن تُرك (OFE-A-0001)' : null),
              ),
            ),
            const SizedBox(height: 10),
            pair(TextField(controller: _maker, decoration: fieldDeco('المصنع')), TextField(controller: _model, decoration: fieldDeco('الموديل'))),
            const SizedBox(height: 10),
            pair(
              TextField(controller: _serial, textDirection: TextDirection.ltr, decoration: fieldDeco('الرقم التسلسلي')),
              SelectField(
                label: 'الحالة',
                value: _cond,
                items: [for (final e in assetConditionLabels.entries) (e.key, e.value)],
                onChanged: (v) => setState(() => _cond = v),
              ),
            ),
            const SizedBox(height: 16),
            Text('الشراء والإهلاك', style: TextStyle(color: sem.muted, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            pair(
              DayField(label: 'تاريخ الشراء', value: _buy, onChanged: (d) => setState(() => _buy = d)),
              DayField(label: 'بدء الاستخدام (يبدأ منه الإهلاك)', value: _start, onChanged: (d) => setState(() => _start = d)),
            ),
            const SizedBox(height: 10),
            pair(
              TextField(
                controller: _cost,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: fieldDeco('التكلفة ($currencyLabel)'),
              ),
              DayField(label: 'نهاية الضمان', value: _warranty, onChanged: (d) => setState(() => _warranty = d)),
            ),
            const SizedBox(height: 10),
            pair(TextField(controller: _supplier, decoration: fieldDeco('المورد')), TextField(controller: _invoice, decoration: fieldDeco('رقم الفاتورة'))),
            const SizedBox(height: 10),
            pair(
              SelectField(
                label: 'طريقة الإهلاك',
                value: _method,
                items: [for (final e in depMethodLabels.entries) (e.key, e.value)],
                onChanged: (v) => setState(() => _method = v),
              ),
              _method == 'straight'
                  ? TextField(
                      controller: _life,
                      keyboardType: TextInputType.number,
                      decoration: fieldDeco('العمر بالأشهر', helper: policy == null ? null : 'سياسة التصنيف: ${policy.label}'),
                    )
                  : const SizedBox.shrink(),
            ),
            if (_method == 'straight') ...[
              const SizedBox(height: 10),
              TextField(
                controller: _salvage,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: fieldDeco('قيمة الخردة ($currencyLabel)',
                    helper: _isNew && policy != null && policy.salvagePct > 0
                        ? 'تُحسب ${fmtQty(policy.salvagePct)}% من التكلفة إن تُركت'
                        : 'ما يُتوقع بيعه به في آخر عمره؛ صفر إن تُركت'),
              ),
            ],
            if (_isNew) ...[
              const SizedBox(height: 16),
              Text('المكان', style: TextStyle(color: sem.muted, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              pair(
                SelectField(
                  label: 'مخزن (يُحفظ فيه)',
                  value: _wh,
                  items: [('', 'ليس في مخزن'), for (final w in s.warehouses) if (w.active) (w.id, w.name)],
                  onChanged: (v) => setState(() => _wh = v),
                ),
                _wh.isEmpty
                    ? SelectField(
                        label: 'الموقع (يُستخدم فيه)',
                        value: _loc,
                        items: [('', 'بلا موقع'), for (final l in s.locations) if (l.active) (l.id, s.locationPath(l.id))],
                        onChanged: (v) => setState(() => _loc = v),
                      )
                    : const SizedBox.shrink(),
              ),
              const SizedBox(height: 10),
              SelectField(
                label: 'الإدارة',
                value: _dep,
                items: [('', 'بلا إدارة'), for (final d in s.departments) if (d.active) (d.id, s.departmentPath(d.id))],
                onChanged: (v) => setState(() => _dep = v),
              ),
            ],
            const SizedBox(height: 10),
            TextField(controller: _note, maxLines: 2, decoration: fieldDeco('ملاحظات')),
            if (_error != null) ...[const SizedBox(height: 10), InfoBanner(level: 'critical', text: _error!)],
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.of(context).pop(), child: const Text('إلغاء')),
        FilledButton(onPressed: _busy ? null : _save, child: Text(_isNew ? 'تسجيل' : 'حفظ')),
      ],
    );
  }
}

// ---------------------------------------------------------------------
// العهد
// ---------------------------------------------------------------------

class StoresCustodyPage extends StatefulWidget {
  const StoresCustodyPage({super.key});

  @override
  State<StoresCustodyPage> createState() => _StoresCustodyPageState();
}

class _StoresCustodyPageState extends State<StoresCustodyPage> {
  final _q = TextEditingController();
  String _state = 'open';
  String _dep = '';

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final s = app.stores;
    final r = app.storeAssets;
    final sem = Sem.of(context);
    final today = DateTime.now();
    final q = _q.text.trim().toLowerCase();
    final list = [
      for (final c in r.custody)
        if ((switch (_state) {
              'open' => c.isOpen,
              'unconfirmed' => c.isOpen && c.confirmedAt == null,
              'returned' => !c.isOpen,
              _ => true,
            }) &&
            (_dep.isEmpty || c.departmentId == _dep) &&
            (q.isEmpty ||
                c.custodyNo.toLowerCase().contains(q) ||
                (s.employee(c.employeeId)?.fullName.toLowerCase().contains(q) ?? false) ||
                (s.employee(c.employeeId)?.empNo.toLowerCase().contains(q) ?? false) ||
                (r.asset(c.assetId)?.matches(q) ?? false)))
          c,
    ]..sort((a, b) => a.isOpen != b.isOpen ? (a.isOpen ? -1 : 1) : b.handedOn.compareTo(a.handedOn));
    final open = [for (final c in r.custody) if (c.isOpen) c];
    final holders = {for (final c in open) c.employeeId}.length;
    return PageBody(
      onRefresh: app.loadAll,
      children: [
        PageHeader(
          title: 'العهد',
          subtitle: 'ما في عهدة كل موظف بمحضره وتاريخه وحالته، وتأكيده الاستلام والإرجاع من صفحته.',
          icon: Icons.assignment_ind_rounded,
          actions: [if (app.storesAssetsSees) ExportButton(sourceId: 'stores:custody', items: list)],
        ),
        if (!app.storesAssetsSees) ...[const AssetsNotReady(), const SizedBox(height: 14)],
        ResponsiveGrid(minItemWidth: 165, children: [
          KpiTile(label: 'عهد قائمة', value: '${open.length}', onTap: () => setState(() => _state = 'open')),
          KpiTile(
            label: 'بانتظار تأكيد الموظف',
            value: '${r.unconfirmed.length}',
            color: r.unconfirmed.isEmpty ? null : sem.wip,
            onTap: () => setState(() => _state = 'unconfirmed'),
          ),
          KpiTile(label: 'موظفون بعهدتهم أصول', value: '$holders'),
          KpiTile(label: 'أُرجعت', value: '${r.custody.length - open.length}', onTap: () => setState(() => _state = 'returned')),
        ]),
        const SizedBox(height: 14),
        Wrap(spacing: 10, runSpacing: 10, children: [
          SizedBox(
            width: 300,
            child: TextField(
              controller: _q,
              onChanged: (_) => setState(() {}),
              decoration: fieldDeco('بحث بالموظف أو الأصل أو رقم المحضر', prefixIcon: const Icon(Icons.search_rounded)),
            ),
          ),
          SizedBox(
            width: 220,
            child: SelectField(
              label: 'العهد',
              value: _state,
              items: const [('open', 'القائمة'), ('unconfirmed', 'بانتظار التأكيد'), ('returned', 'المرجعة'), ('all', 'الكل')],
              onChanged: (v) => setState(() => _state = v),
            ),
          ),
          SizedBox(
            width: 220,
            child: SelectField(
              label: 'الإدارة',
              value: _dep,
              items: [('', 'كل الإدارات'), for (final d in s.departments) (d.id, d.name)],
              onChanged: (v) => setState(() => _dep = v),
            ),
          ),
        ]),
        const SizedBox(height: 12),
        SectionCard(
          title: 'المحاضر (${list.length})',
          icon: Icons.list_alt_rounded,
          child: list.isEmpty
              ? Text('لا محاضر بهذا البحث.', style: TextStyle(color: sem.muted))
              : Column(children: [
                  for (final c in list.take(400))
                    () {
                      final a = r.asset(c.assetId);
                      final e = s.employee(c.employeeId);
                      return ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                        leading: Icon(c.isOpen ? Icons.assignment_ind_rounded : Icons.assignment_turned_in_outlined,
                            color: c.isOpen ? sem.na : sem.muted),
                        title: Text.rich(TextSpan(children: [
                          TextSpan(text: e?.fullName ?? '', style: const TextStyle(fontWeight: FontWeight.w600)),
                          TextSpan(text: ' · ${a == null ? '' : isolate(a.tag)} ${a?.name ?? ''}'),
                        ]), maxLines: 2, overflow: TextOverflow.ellipsis),
                        subtitle: Text(
                          '${isolate(c.custodyNo)} · ${s.department(c.departmentId)?.name ?? ''} · سُلّم ${dayText(c.handedOn)}'
                          '${c.isOpen ? ' (${c.days(today)} يوماً)' : ' · أُرجع ${dayText(c.returnedOn)}'}',
                          style: TextStyle(color: sem.muted, fontSize: 12.5),
                        ),
                        trailing: c.isOpen
                            ? (c.confirmedAt == null
                                ? ToneBadge('لم يؤكد', color: sem.wip, icon: Icons.hourglass_top_rounded)
                                : ToneBadge('مؤكدة', color: sem.ok, icon: Icons.verified_outlined))
                            : ToneBadge('مرجعة', color: sem.muted),
                        onTap: a == null ? null : () => openStoreAsset(context, a.id),
                      );
                    }(),
                  if (list.length > 400)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text('يُعرض أول 400 محضر؛ ضيّق البحث لرؤية البقية.', style: TextStyle(color: sem.muted)),
                    ),
                ]),
        ),
        const SizedBox(height: 6),
        Text('يسلّم مسؤول الأصول العهدة من صفحة الأصل، ويؤكد الموظف استلامها وإرجاعها من صفحته «ما صُرف لي».',
            style: TextStyle(color: sem.muted, fontSize: 12.5)),
      ],
    );
  }
}

// ---------------------------------------------------------------------
// عهد الموظف في صفحته «ما صُرف لي»
// ---------------------------------------------------------------------

class MyCustodySection extends StatelessWidget {
  const MyCustodySection({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final sem = Sem.of(context);
    final list = app.myCustody;
    if (!app.v23Ready || list.isEmpty) return const SizedBox.shrink();
    final open = list.where((c) => c.isOpen).toList();
    final closed = list.where((c) => !c.isOpen).toList();
    Widget card(MyCustody c) => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: SectionCard(
            title: c.name,
            icon: c.isOpen ? Icons.assignment_ind_rounded : Icons.assignment_turned_in_outlined,
            subtitle: '${isolate(c.tag)} · ${c.category}${c.description.isEmpty ? '' : ' · ${c.description}'}',
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(
                'المحضر ${isolate(c.custodyNo)} · سُلّمت ${dayText(c.handedOn)} بحالة ${assetConditionLabels[c.conditionOut] ?? ''}'
                '${c.accessoriesOut.isEmpty ? '' : ' · الملحقات: ${c.accessoriesOut}'}',
                style: TextStyle(color: sem.muted, fontSize: 12.5),
              ),
              if (c.serialNo.isNotEmpty) Text('الرقم التسلسلي: ${c.serialNo}', style: TextStyle(color: sem.muted, fontSize: 12.5)),
              if (!c.isOpen)
                Text('أُرجعت ${dayText(c.returnedOn)} بحالة ${assetConditionLabels[c.conditionIn] ?? ''}',
                    style: TextStyle(color: sem.muted, fontSize: 12.5)),
              const SizedBox(height: 10),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: c.isOpen && c.needsReceipt
                    ? FilledButton.tonalIcon(
                        onPressed: () => storesRun(context, () => app.stConfirmCustody(c.id, 'receipt'), success: 'سُجّل تأكيد استلامك'),
                        icon: const Icon(Icons.check_rounded),
                        label: const Text('أكّد الاستلام'),
                      )
                    : c.needsReturnConfirm
                        ? FilledButton.tonalIcon(
                            onPressed: () => storesRun(context, () => app.stConfirmCustody(c.id, 'return'), success: 'سُجّل تأكيد إرجاعك'),
                            icon: const Icon(Icons.check_rounded),
                            label: const Text('أكّد الإرجاع'),
                          )
                        : ToneBadge(c.isOpen ? 'أكّدتَ الاستلام' : 'أكّدتَ الإرجاع', color: sem.ok, icon: Icons.verified_outlined),
              ),
            ]),
          ),
        );
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.only(top: 4, bottom: 10),
        child: Text('عهدتي (${open.length})', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
      ),
      if (open.isEmpty) Padding(padding: const EdgeInsets.only(bottom: 12), child: Text('لا أصول في عهدتك الآن.', style: TextStyle(color: sem.muted))),
      for (final c in open) card(c),
      if (closed.isNotEmpty) ...[
        Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 10),
          child: Text('عهد أرجعتها (${closed.length})', style: Theme.of(context).textTheme.titleSmall?.copyWith(color: sem.muted)),
        ),
        for (final c in closed.take(20)) card(c),
      ],
      const SizedBox(height: 6),
    ]);
  }
}
