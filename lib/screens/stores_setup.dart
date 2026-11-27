import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/material.dart';

import '../app_state.dart';
import '../assets.dart';
import '../docs.dart' show isolate;
import '../models.dart';
import '../registers.dart' show isoDay;
import '../print/export_dialog.dart' show ExportButton;
import '../services/boq_files.dart' show BoqSheetRows, readCsv, readXlsx;
import '../services/doc_files.dart' show extOf;
import '../stores.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';
import 'pm_common.dart' show PmTable;
import 'stores.dart' show StoresNotReady, storesRun, qtyWithUnit;

// =====================================================================
// تهيئة المخازن (المخازن والمواقع والتصنيفات والوحدات والإعدادات)، والإدارات وسجل الموظفين،
// والاستيراد من Excel أو CSV بعد المراجعة (الموظفون، والأصناف، وبنود أرصدة أول المدة).
// =====================================================================

/// نافذة نموذج بسيطة: محتوى، وحفظ يرمي خطأً مفهوماً، وحذف اختياري.
Future<void> storeFormDialog(
  BuildContext context, {
  required String title,
  required Widget Function(StateSetter setLocal) body,
  required Future<void> Function() onSave,
  Future<void> Function()? onDelete,
  double width = 480,
}) {
  final del = onDelete;
  return showDialog<void>(
    context: context,
    builder: (ctx) {
      var busy = false;
      String? error;
      return StatefulBuilder(builder: (ctx, setLocal) {
        Future<void> run(Future<void> Function() f) async {
          setLocal(() {
            busy = true;
            error = null;
          });
          try {
            await f();
            if (ctx.mounted) Navigator.of(ctx).pop();
          } catch (e) {
            setLocal(() => error = e is StateError ? e.message : friendlyError(e));
          } finally {
            if (ctx.mounted) setLocal(() => busy = false);
          }
        }

        return AlertDialog(
          title: Text(title),
          content: SizedBox(
            width: width,
            child: SingleChildScrollView(
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
                body(setLocal),
                if (error != null) ...[const SizedBox(height: 10), InfoBanner(level: 'critical', text: error!)],
              ]),
            ),
          ),
          actions: [
            if (del != null)
              TextButton(
                onPressed: busy
                    ? null
                    : () async {
                        final ok = await confirmDialog(ctx, title: 'حذف؟', message: 'يُحذف لأنه غير مرتبط بشيء، ويبقى أثره في سجل التدقيق.', confirmLabel: 'حذف', danger: true);
                        if (ok) await run(del);
                      },
                child: Text('حذف', style: TextStyle(color: Sem.of(ctx).danger)),
              ),
            TextButton(onPressed: busy ? null : () => Navigator.of(ctx).pop(), child: const Text('إلغاء')),
            FilledButton(onPressed: busy ? null : () => run(onSave), child: const Text('حفظ')),
          ],
        );
      });
    },
  );
}

Widget _activeSwitch(bool value, ValueChanged<bool> onChanged) => Material(
      type: MaterialType.transparency,
      child: SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('نشط'), value: value, onChanged: onChanged),
    );

// ---------------------------------------------------------------------
// صفحة التهيئة
// ---------------------------------------------------------------------

class StoresSetupPage extends StatelessWidget {
  const StoresSetupPage({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final s = app.stores;
    final sem = Sem.of(context);
    final edit = app.canStoresSetup;
    return PageBody(
      onRefresh: app.loadAll,
      children: [
        PageHeader(
          title: 'تهيئة المخازن',
          subtitle: 'المخازن الرئيسية والفرعية ومواقعها، والمباني والطوابق والغرف، والتصنيفات، والوحدات، وإعدادات القسم.',
          icon: Icons.settings_suggest_rounded,
        ),
        if (!app.v22Ready) ...[const StoresNotReady(), const SizedBox(height: 14)],
        if (!edit && app.v22Ready)
          const Padding(
            padding: EdgeInsets.only(bottom: 14),
            child: InfoBanner(text: 'للاطلاع فقط: التهيئة لمدير النظام في المخازن أو المدير.'),
          ),
        _WarehousesCard(edit: edit),
        const SizedBox(height: 14),
        _LocationsCard(edit: edit),
        const SizedBox(height: 14),
        _CategoriesCard(edit: edit),
        if (app.v23Ready) ...[const SizedBox(height: 14), _DepPoliciesCard(edit: edit)],
        const SizedBox(height: 14),
        _UnitsCard(edit: edit),
        const SizedBox(height: 14),
        _SettingsCard(edit: edit, key: ValueKey('st-settings-${s.settings.separation}-${s.settings.expiryDays}')),
        const SizedBox(height: 8),
        Text('أمين كل مخزن يُحدَّد من صلاحيات المستخدم الدقيقة (لوحة التحكم ثم المستخدمون) بنطاق «أمين مخزن».',
            style: TextStyle(color: sem.muted, fontSize: 12.5)),
      ],
    );
  }
}

class _WarehousesCard extends StatelessWidget {
  const _WarehousesCard({required this.edit});

  final bool edit;

  Future<void> _edit(BuildContext context, [StWarehouse? w]) {
    final app = AppScope.read(context);
    final s = app.stores;
    final code = TextEditingController(text: w?.code ?? '');
    final name = TextEditingController(text: w?.name ?? '');
    final note = TextEditingController(text: w?.note ?? '');
    var kind = w?.kind ?? (s.warehouses.any((x) => x.isMain) ? 'sub' : 'main');
    var parent = w?.parentId ?? '';
    var loc = w?.locationId ?? '';
    var active = w?.active ?? true;
    return storeFormDialog(
      context,
      title: w == null ? 'مخزن جديد' : 'تعديل المخزن',
      body: (setLocal) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        TextField(controller: name, decoration: fieldDeco('اسم المخزن')),
        const SizedBox(height: 10),
        TextField(controller: code, textDirection: TextDirection.ltr, decoration: fieldDeco('الرمز', helper: 'حروف لاتينية وأرقام حتى 12 (مثل MAIN)')),
        const SizedBox(height: 10),
        SelectField(
          label: 'النوع',
          value: kind,
          items: [for (final e in stWarehouseKindLabels.entries) (e.key, e.value)],
          onChanged: (v) => setLocal(() => kind = v),
        ),
        if (kind == 'sub') ...[
          const SizedBox(height: 10),
          SelectField(
            label: 'يتبع المخزن الرئيسي',
            value: parent,
            items: [('', 'لا يتبع مخزناً'), for (final x in s.warehouses) if (x.isMain && x.id != w?.id) (x.id, x.name)],
            onChanged: (v) => setLocal(() => parent = v),
          ),
        ],
        const SizedBox(height: 10),
        SelectField(
          label: 'الموقع',
          value: loc,
          items: [('', 'دون موقع'), for (final l in s.locations) (l.id, s.locationPath(l.id))],
          onChanged: (v) => setLocal(() => loc = v),
        ),
        const SizedBox(height: 10),
        TextField(controller: note, decoration: fieldDeco('ملاحظات')),
        if (w != null) _activeSwitch(active, (v) => setLocal(() => active = v)),
      ]),
      onSave: () async {
        await app.stSaveWarehouse(w?.id, {
          'code': code.text.trim(),
          'name': name.text.trim(),
          'kind': kind,
          'parent_id': kind == 'sub' && parent.isNotEmpty ? parent : null,
          'location_id': loc.isEmpty ? null : loc,
          'note': note.text.trim(),
          'active': active,
        });
      },
      onDelete: w == null ? null : () => app.stDeleteSetup('warehouse', w.id),
    );
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final s = app.stores;
    final sem = Sem.of(context);
    List<String> keepers(String id) => [
          for (final e in app.grants.entries)
            if (e.value.contains(storesKeeperScope(id))) app.people[e.key]?.displayName ?? '',
        ]..removeWhere((x) => x.isEmpty);
    return SectionCard(
      title: 'المخازن (${s.warehouses.length})',
      icon: Icons.warehouse_outlined,
      subtitle: 'مخزن رئيسي ومخازن فرعية تتبعه، ولكل مخزن موقعه وأمينه.',
      trailing: edit ? FilledButton.tonalIcon(onPressed: () => _edit(context), icon: const Icon(Icons.add_rounded), label: const Text('مخزن')) : null,
      child: s.warehouses.isEmpty
          ? Text('لا مخازن بعد. ابدأ بالمخزن الرئيسي.', style: TextStyle(color: sem.muted))
          : Column(children: [
              for (final w in s.warehouses)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(w.isMain ? Icons.warehouse_rounded : Icons.store_mall_directory_outlined, color: w.active ? null : sem.muted),
                  title: Text('${w.name} · ${isolate(w.code)}'),
                  subtitle: Text(
                    [
                      stWarehouseKindLabels[w.kind] ?? w.kind,
                      if (w.parentId != null) 'يتبع ${s.warehouseName(w.parentId)}',
                      if (w.locationId != null) s.locationPath(w.locationId),
                      if (keepers(w.id).isNotEmpty) 'الأمين: ${keepers(w.id).join('، ')}',
                      if (!w.active) 'موقوف',
                    ].join(' · '),
                    style: TextStyle(color: sem.muted, fontSize: 12.5),
                  ),
                  trailing: edit ? const Icon(Icons.edit_outlined, size: 18) : null,
                  onTap: edit ? () => _edit(context, w) : null,
                ),
            ]),
    );
  }
}

class _LocationsCard extends StatelessWidget {
  const _LocationsCard({required this.edit});

  final bool edit;

  Future<void> _edit(BuildContext context, {StLocation? loc, String? parentId}) {
    final app = AppScope.read(context);
    final s = app.stores;
    final name = TextEditingController(text: loc?.name ?? '');
    final code = TextEditingController(text: loc?.code ?? '');
    final parentKind = s.location(loc?.parentId ?? parentId)?.kind;
    var kind = loc?.kind ?? switch (parentKind) { null => 'building', 'building' => 'floor', _ => 'room' };
    var parent = loc?.parentId ?? parentId ?? '';
    var active = loc?.active ?? true;
    return storeFormDialog(
      context,
      title: loc == null ? 'موقع جديد' : 'تعديل الموقع',
      body: (setLocal) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SelectField(
          label: 'النوع',
          value: kind,
          items: [for (final e in stLocationKindLabels.entries) (e.key, e.value)],
          onChanged: (v) => setLocal(() => kind = v),
        ),
        if (kind != 'building') ...[
          const SizedBox(height: 10),
          SelectField(
            label: 'يقع في',
            value: parent,
            items: [
              ('', 'اختر'),
              for (final l in s.locations)
                if (l.id != loc?.id && l.kind != 'room' && (kind != 'floor' || l.kind == 'building')) (l.id, s.locationPath(l.id)),
            ],
            onChanged: (v) => setLocal(() => parent = v),
          ),
        ],
        const SizedBox(height: 10),
        TextField(controller: name, decoration: fieldDeco('الاسم', hint: 'المبنى الرئيسي، الطابق الأول، غرفة 104…')),
        const SizedBox(height: 10),
        TextField(controller: code, textDirection: TextDirection.ltr, decoration: fieldDeco('الرمز (اختياري)')),
        if (loc != null) _activeSwitch(active, (v) => setLocal(() => active = v)),
      ]),
      onSave: () => app.stSaveLocation(loc?.id, {
        'kind': kind,
        'parent_id': kind == 'building' || parent.isEmpty ? null : parent,
        'name': name.text.trim(),
        'code': code.text.trim(),
        'active': active,
      }),
      onDelete: loc == null ? null : () => app.stDeleteSetup('location', loc.id),
    );
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final s = app.stores;
    final sem = Sem.of(context);
    final rows = <(StLocation, int)>[];
    void walk(String? parent, int depth) {
      for (final l in s.locations) {
        if (l.parentId == parent) {
          rows.add((l, depth));
          if (depth < 6) walk(l.id, depth + 1);
        }
      }
    }

    walk(null, 0);
    return SectionCard(
      title: 'المواقع (${s.locations.length})',
      icon: Icons.apartment_rounded,
      subtitle: 'المباني والطوابق والغرف والمساحات، لمواقع المخازن ثم الأصول.',
      trailing: edit ? FilledButton.tonalIcon(onPressed: () => _edit(context), icon: const Icon(Icons.add_rounded), label: const Text('مبنى')) : null,
      child: rows.isEmpty
          ? Text('لا مواقع بعد.', style: TextStyle(color: sem.muted))
          : Column(children: [
              for (final r in rows)
                Padding(
                  padding: EdgeInsetsDirectional.only(start: 22.0 * r.$2),
                  child: ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(switch (r.$1.kind) {
                      'building' => Icons.apartment_rounded,
                      'floor' => Icons.layers_outlined,
                      'room' => Icons.meeting_room_outlined,
                      _ => Icons.crop_free_rounded,
                    }, size: 20, color: r.$1.active ? null : sem.muted),
                    title: Text(r.$1.name),
                    subtitle: Text('${r.$1.kindLabel}${r.$1.code.isEmpty ? '' : ' · ${r.$1.code}'}${r.$1.active ? '' : ' · موقوف'}',
                        style: TextStyle(color: sem.muted, fontSize: 12)),
                    trailing: !edit
                        ? null
                        : Row(mainAxisSize: MainAxisSize.min, children: [
                            if (r.$1.kind != 'room')
                              IconButton(
                                tooltip: 'إضافة موقع فيه',
                                icon: const Icon(Icons.add_rounded, size: 19),
                                onPressed: () => _edit(context, parentId: r.$1.id),
                              ),
                            IconButton(tooltip: 'تعديل', icon: const Icon(Icons.edit_outlined, size: 18), onPressed: () => _edit(context, loc: r.$1)),
                          ]),
                  ),
                ),
            ]),
    );
  }
}

class _CategoriesCard extends StatelessWidget {
  const _CategoriesCard({required this.edit});

  final bool edit;

  Future<void> _edit(BuildContext context, [StCategory? c]) {
    final app = AppScope.read(context);
    final s = app.stores;
    final name = TextEditingController(text: c?.name ?? '');
    final code = TextEditingController(text: c?.code ?? '');
    var kind = c?.kind ?? 'consumable';
    var parent = c?.parentId ?? '';
    var active = c?.active ?? true;
    return storeFormDialog(
      context,
      title: c == null ? 'تصنيف جديد' : 'تعديل التصنيف',
      body: (setLocal) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        TextField(controller: name, decoration: fieldDeco('اسم التصنيف')),
        const SizedBox(height: 10),
        TextField(controller: code, textDirection: TextDirection.ltr, decoration: fieldDeco('الرمز', helper: 'من 2 إلى 8 حروف لاتينية كبيرة أو أرقام؛ تبدأ به رموز أصنافه')),
        const SizedBox(height: 10),
        SelectField(
          label: 'النوع',
          value: kind,
          items: [for (final e in stCategoryKindLabels.entries) (e.key, e.value)],
          onChanged: (v) => setLocal(() => kind = v),
        ),
        const SizedBox(height: 10),
        SelectField(
          label: 'فرع من',
          value: parent,
          items: [('', 'تصنيف رئيسي'), for (final x in s.categories) if (x.id != c?.id) (x.id, x.name)],
          onChanged: (v) => setLocal(() => parent = v),
        ),
        if (c != null) _activeSwitch(active, (v) => setLocal(() => active = v)),
      ]),
      onSave: () => app.stSaveCategory(c?.id, {
        'name': name.text.trim(),
        'code': code.text.trim().toUpperCase(),
        'kind': kind,
        'parent_id': parent.isEmpty ? null : parent,
        'active': active,
      }),
      onDelete: c == null ? null : () => app.stDeleteSetup('category', c.id),
    );
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final s = app.stores;
    final sem = Sem.of(context);
    return SectionCard(
      title: 'التصنيفات (${s.categories.length})',
      icon: Icons.category_outlined,
      subtitle: 'الثمانية في المتطلبات مبدوءة، وتُضاف غيرها دون تعديل برمجي.',
      trailing: edit ? FilledButton.tonalIcon(onPressed: () => _edit(context), icon: const Icon(Icons.add_rounded), label: const Text('تصنيف')) : null,
      child: Wrap(spacing: 8, runSpacing: 8, children: [
        for (final c in s.categories)
          ActionChip(
            avatar: Icon(c.kind == 'asset' ? Icons.chair_outlined : Icons.inventory_2_outlined, size: 16),
            label: Text(
                '${c.name} · ${c.code} (${c.isAsset ? app.storeAssets.assets.where((a) => a.categoryId == c.id && !a.isDisposed).length : s.items.where((i) => i.categoryId == c.id).length})',
                style: TextStyle(color: c.active ? null : sem.muted)),
            onPressed: edit ? () => _edit(context, c) : null,
          ),
      ]),
    );
  }
}

/// سياسة الإهلاك الافتراضية لكل تصنيف أصول (الترحيل 39): تُقترح للأصل الجديد، ولا تغيّر الأصول المسجلة.
class _DepPoliciesCard extends StatelessWidget {
  const _DepPoliciesCard({required this.edit});

  final bool edit;

  Future<void> _edit(BuildContext context, StCategory c) {
    final app = AppScope.read(context);
    final p = app.storeAssets.policyOf(c.id);
    var method = p?.depMethod ?? 'straight';
    final life = TextEditingController(text: p?.lifeMonths?.toString() ?? '');
    final pct = TextEditingController(text: p == null || p.salvagePct == 0 ? '' : fmtQty(p.salvagePct));
    return storeFormDialog(
      context,
      title: 'سياسة إهلاك «${c.name}»',
      width: 420,
      body: (setLocal) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SelectField(
          label: 'طريقة الإهلاك',
          value: method,
          items: [for (final e in depMethodLabels.entries) (e.key, e.value)],
          onChanged: (v) => setLocal(() => method = v),
        ),
        if (method == 'straight') ...[
          const SizedBox(height: 10),
          TextField(
            controller: life,
            keyboardType: TextInputType.number,
            decoration: fieldDeco('العمر الإنتاجي بالأشهر', helper: '60 شهراً = خمس سنوات'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: pct,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: fieldDeco('نسبة الخردة من التكلفة %', hint: '0'),
          ),
        ],
        const SizedBox(height: 10),
        Text('تُقترح للأصل الجديد في التصنيف، ولا تتغير بها الأصول المسجلة.', style: TextStyle(color: Sem.of(context).muted, fontSize: 12.5)),
      ]),
      onSave: () {
        final l = int.tryParse(life.text.trim());
        if (method == 'straight' && (l == null || l < 1 || l > 600)) {
          throw StateError('العمر بالأشهر عدد صحيح من 1 إلى 600');
        }
        final x = pct.text.trim().isEmpty ? 0.0 : parseImportNumber(pct.text);
        if (x == null || x < 0 || x > 100) throw StateError('نسبة الخردة من 0 إلى 100');
        return app.stSaveAssetPolicy(c.id, {'dep_method': method, 'life_months': method == 'straight' ? l : null, 'salvage_pct': x});
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final sem = Sem.of(context);
    final cats = [for (final c in app.stores.categories) if (c.isAsset) c];
    return SectionCard(
      title: 'سياسات الإهلاك',
      icon: Icons.trending_down_rounded,
      subtitle: 'العمر الافتراضي ونسبة الخردة لكل تصنيف أصول؛ تُقترح للأصل الجديد وحده.',
      child: cats.isEmpty
          ? Text('لا تصنيفات أصول بعد. اجعل نوع التصنيف «أصل» ليظهر هنا.', style: TextStyle(color: sem.muted))
          : Column(children: [
              for (final c in cats)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.chair_outlined, color: sem.muted),
                  title: Text('${c.name} · ${c.code}'),
                  subtitle: Text(app.storeAssets.policyOf(c.id)?.label ?? 'لا سياسة: يُحدَّد العمر لكل أصل',
                      style: TextStyle(color: sem.muted, fontSize: 12)),
                  trailing: edit ? const Icon(Icons.edit_outlined, size: 18) : null,
                  onTap: edit ? () => _edit(context, c) : null,
                ),
            ]),
    );
  }
}

class _UnitsCard extends StatelessWidget {
  const _UnitsCard({required this.edit});

  final bool edit;

  Future<void> _edit(BuildContext context, [StUnit? u]) {
    final app = AppScope.read(context);
    final name = TextEditingController(text: u?.name ?? '');
    var active = u?.active ?? true;
    return storeFormDialog(
      context,
      title: u == null ? 'وحدة جديدة' : 'تعديل الوحدة',
      width: 380,
      body: (setLocal) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        TextField(controller: name, decoration: fieldDeco('اسم الوحدة', hint: 'قطعة، رزمة، كرتونة…')),
        if (u != null) _activeSwitch(active, (v) => setLocal(() => active = v)),
      ]),
      onSave: () => app.stSaveUnit(u?.id, {'name': name.text.trim(), 'active': active}),
      onDelete: u == null ? null : () => app.stDeleteSetup('unit', u.id),
    );
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final s = app.stores;
    final sem = Sem.of(context);
    return SectionCard(
      title: 'الوحدات (${s.units.length})',
      icon: Icons.straighten_rounded,
      subtitle: 'لكل صنف وحدته الأساسية ووحدات أخرى بمعاملات تحويلها (في بطاقة الصنف).',
      trailing: edit ? FilledButton.tonalIcon(onPressed: () => _edit(context), icon: const Icon(Icons.add_rounded), label: const Text('وحدة')) : null,
      child: Wrap(spacing: 8, runSpacing: 8, children: [
        for (final u in s.units)
          ActionChip(label: Text(u.name, style: TextStyle(color: u.active ? null : sem.muted)), onPressed: edit ? () => _edit(context, u) : null),
      ]),
    );
  }
}

class _SettingsCard extends StatefulWidget {
  const _SettingsCard({super.key, required this.edit});

  final bool edit;

  @override
  State<_SettingsCard> createState() => _SettingsCardState();
}

class _SettingsCardState extends State<_SettingsCard> {
  late bool _sep = AppScope.read(context).stores.settings.separation;
  late final TextEditingController _days = TextEditingController(text: '${AppScope.read(context).stores.settings.expiryDays}');
  bool _busy = false;

  @override
  void dispose() {
    _days.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final d = int.tryParse(_days.text.trim());
    if (d == null || d < 7 || d > 365) {
      showToast(context, 'مدة التنبيه من 7 إلى 365 يوماً.', error: true);
      return;
    }
    setState(() => _busy = true);
    await storesRun(context, () => AppScope.read(context).stSetSettings({'separation': _sep, 'expiry_days': d}), success: 'حُفظت إعدادات المخازن');
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final sem = Sem.of(context);
    return SectionCard(
      title: 'إعدادات القسم',
      icon: Icons.tune_rounded,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Material(
          type: MaterialType.transparency,
          child: SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('فصل المهام'),
            subtitle: Text('من أنشأ المستند أو قدّمه لا يعتمده، ولو كان مدير المخازن أو المدير.', style: TextStyle(color: sem.muted, fontSize: 12.5)),
            value: _sep,
            onChanged: widget.edit ? (v) => setState(() => _sep = v) : null,
          ),
        ),
        const SizedBox(height: 8),
        Row(children: [
          SizedBox(
            width: 220,
            child: TextField(
              controller: _days,
              enabled: widget.edit,
              keyboardType: TextInputType.number,
              textDirection: TextDirection.ltr,
              decoration: fieldDeco('التنبيه قبل انتهاء الصلاحية (أيام)'),
            ),
          ),
          const Spacer(),
          if (widget.edit) FilledButton(onPressed: _busy ? null : _save, child: const Text('حفظ الإعدادات')),
        ]),
      ]),
    );
  }
}

// ---------------------------------------------------------------------
// الإدارات والموظفون
// ---------------------------------------------------------------------

class StoresPeoplePage extends StatefulWidget {
  const StoresPeoplePage({super.key});

  @override
  State<StoresPeoplePage> createState() => _StoresPeoplePageState();
}

class _StoresPeoplePageState extends State<StoresPeoplePage> {
  final _q = TextEditingController();
  String _dep = '';

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  Future<void> _editDep([StDepartment? d]) {
    final app = AppScope.read(context);
    final s = app.stores;
    final name = TextEditingController(text: d?.name ?? '');
    final code = TextEditingController(text: d?.code ?? '');
    var parent = d?.parentId ?? '';
    var active = d?.active ?? true;
    return storeFormDialog(
      context,
      title: d == null ? 'إدارة أو قسم جديد' : 'تعديل الإدارة',
      body: (setLocal) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        TextField(controller: name, decoration: fieldDeco('الاسم')),
        const SizedBox(height: 10),
        TextField(controller: code, textDirection: TextDirection.ltr, decoration: fieldDeco('الرمز (اختياري)')),
        const SizedBox(height: 10),
        SelectField(
          label: 'تتبع',
          value: parent,
          items: [('', 'إدارة رئيسية'), for (final x in s.departments) if (x.id != d?.id) (x.id, s.departmentPath(x.id))],
          onChanged: (v) => setLocal(() => parent = v),
        ),
        if (d != null) _activeSwitch(active, (v) => setLocal(() => active = v)),
      ]),
      onSave: () => app.stSaveDepartment(d?.id, {
        'name': name.text.trim(),
        'code': code.text.trim(),
        'parent_id': parent.isEmpty ? null : parent,
        'active': active,
      }),
      onDelete: d == null ? null : () => app.stDeleteSetup('department', d.id),
    );
  }

  Future<void> _editEmp([StEmployee? e]) {
    final app = AppScope.read(context);
    final s = app.stores;
    final no = TextEditingController(text: e?.empNo ?? '');
    final name = TextEditingController(text: e?.fullName ?? '');
    final title = TextEditingController(text: e?.jobTitle ?? '');
    final phone = TextEditingController(text: e?.phone ?? '');
    final email = TextEditingController(text: e?.email ?? '');
    final note = TextEditingController(text: e?.note ?? '');
    var dep = e?.departmentId ?? '';
    var profile = e?.profileId ?? '';
    var active = e?.active ?? true;
    final linked = {for (final x in s.employees) if (x.profileId != null && x.id != e?.id) x.profileId!};
    final accounts = [
      for (final p in app.people.values)
        if (p.active && !linked.contains(p.id)) p,
    ]..sort((a, b) => a.displayName.compareTo(b.displayName));
    return storeFormDialog(
      context,
      title: e == null ? 'موظف جديد' : 'تعديل سجل الموظف',
      width: 560,
      body: (setLocal) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Wrap(spacing: 10, runSpacing: 10, children: [
          SizedBox(width: 170, child: TextField(controller: no, textDirection: TextDirection.ltr, decoration: fieldDeco('الرقم الوظيفي'))),
          SizedBox(width: 330, child: TextField(controller: name, decoration: fieldDeco('الاسم الكامل'))),
          SizedBox(
            width: 330,
            child: SelectField(
              label: 'الإدارة',
              value: dep,
              items: [('', 'دون إدارة'), for (final d in s.departments) if (d.active || d.id == dep) (d.id, s.departmentPath(d.id))],
              onChanged: (v) => setLocal(() => dep = v),
            ),
          ),
          SizedBox(width: 170, child: TextField(controller: title, decoration: fieldDeco('الوظيفة'))),
          SizedBox(width: 170, child: TextField(controller: phone, textDirection: TextDirection.ltr, decoration: fieldDeco('الهاتف'))),
          SizedBox(width: 330, child: TextField(controller: email, textDirection: TextDirection.ltr, decoration: fieldDeco('البريد'))),
        ]),
        const SizedBox(height: 12),
        SelectField(
          label: 'حساب المنظومة (للخدمة الذاتية)',
          value: profile,
          items: [
            ('', 'دون حساب'),
            for (final p in accounts) (p.id, '${p.displayName}${p.role == AppRole.employee ? '' : ' · ${p.role?.label ?? ''}'}'),
          ],
          onChanged: (v) => setLocal(() => profile = v),
        ),
        const SizedBox(height: 4),
        Text('يرى صاحب الحساب المربوط ما صُرف له في صفحة «ما صُرف لي». حساب الموظف يُفعَّل بدور «موظف (خدمة ذاتية)».',
            style: TextStyle(color: Sem.of(context).muted, fontSize: 12)),
        const SizedBox(height: 10),
        TextField(controller: note, decoration: fieldDeco('ملاحظات')),
        if (e != null) _activeSwitch(active, (v) => setLocal(() => active = v)),
      ]),
      onSave: () => app.stSaveEmployee(e?.id, {
        'emp_no': no.text.trim(),
        'full_name': name.text.trim(),
        'department_id': dep.isEmpty ? null : dep,
        'job_title': title.text.trim(),
        'phone': phone.text.trim(),
        'email': email.text.trim(),
        'profile_id': profile.isEmpty ? null : profile,
        'note': note.text.trim(),
        'active': active,
      }),
      onDelete: e == null ? null : () => app.stDeleteSetup('employee', e.id),
    );
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final s = app.stores;
    final sem = Sem.of(context);
    final edit = app.canStoresSetup;
    final q = normalizeArabic(_q.text);
    final list = [
      for (final e in s.employees)
        if ((_dep.isEmpty || e.departmentId == _dep) &&
            (q.isEmpty || normalizeArabic(e.fullName).contains(q) || e.empNo.toLowerCase().contains(_q.text.trim().toLowerCase())))
          e,
    ];
    final deps = <(StDepartment, int)>[];
    void walk(String? parent, int depth) {
      for (final d in s.departments) {
        if (d.parentId == parent) {
          deps.add((d, depth));
          if (depth < 6) walk(d.id, depth + 1);
        }
      }
    }

    walk(null, 0);
    return PageBody(
      onRefresh: app.loadAll,
      children: [
        PageHeader(
          title: 'الإدارات والموظفون',
          subtitle: 'إدارات المقر وأقسامها، وسجل موظفيه (يُصرف لهم وتُسجَّل عهدهم)، وربط حساب لمن يلزمه.',
          icon: Icons.groups_2_rounded,
          actions: [
            if (edit) FilledButton.icon(onPressed: () => _editEmp(), icon: const Icon(Icons.person_add_alt_1_rounded), label: const Text('موظف')),
            if (edit)
              OutlinedButton.icon(
                onPressed: () => startStoresImport(context, 'employees'),
                icon: const Icon(Icons.upload_file_rounded),
                label: const Text('استيراد من Excel'),
              ),
            if (app.v22Ready) ExportButton(sourceId: 'stores:employees', items: list),
          ],
        ),
        if (!app.v22Ready) ...[const StoresNotReady(), const SizedBox(height: 14)],
        SectionCard(
          title: 'الإدارات والأقسام (${s.departments.length})',
          icon: Icons.account_tree_outlined,
          trailing: edit ? FilledButton.tonalIcon(onPressed: () => _editDep(), icon: const Icon(Icons.add_rounded), label: const Text('إدارة')) : null,
          child: deps.isEmpty
              ? Text('لا إدارات بعد.', style: TextStyle(color: sem.muted))
              : Column(children: [
                  for (final r in deps)
                    Padding(
                      padding: EdgeInsetsDirectional.only(start: 22.0 * r.$2),
                      child: ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text(r.$1.name, style: TextStyle(color: r.$1.active ? null : sem.muted)),
                        subtitle: Text('${arCount(s.employees.where((e) => e.departmentId == r.$1.id).length, one: 'موظف', two: 'موظفان', few: 'موظفين', many: 'موظفاً')}${r.$1.code.isEmpty ? '' : ' · ${r.$1.code}'}',
                            style: TextStyle(color: sem.muted, fontSize: 12)),
                        trailing: edit ? const Icon(Icons.edit_outlined, size: 18) : null,
                        onTap: edit ? () => _editDep(r.$1) : null,
                      ),
                    ),
                ]),
        ),
        const SizedBox(height: 14),
        Wrap(spacing: 10, runSpacing: 10, children: [
          SizedBox(
            width: 280,
            child: TextField(
              controller: _q,
              onChanged: (_) => setState(() {}),
              decoration: fieldDeco('بحث بالاسم أو الرقم الوظيفي', prefixIcon: const Icon(Icons.search_rounded)),
            ),
          ),
          SizedBox(
            width: 280,
            child: SelectField(
              label: 'الإدارة',
              value: _dep,
              items: [('', 'كل الإدارات'), for (final d in s.departments) (d.id, s.departmentPath(d.id))],
              onChanged: (v) => setState(() => _dep = v),
            ),
          ),
        ]),
        const SizedBox(height: 12),
        SectionCard(
          title: 'سجل الموظفين (${list.length})',
          icon: Icons.badge_outlined,
          child: list.isEmpty
              ? Text(s.employees.isEmpty ? 'لا موظفين بعد. أضفهم أو استوردهم من ملف Excel.' : 'لا موظف مطابق.', style: TextStyle(color: sem.muted))
              : Column(children: [
                  for (final e in list.take(500))
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: InitialsAvatar(name: e.fullName, size: 34),
                      title: Text(e.fullName, style: TextStyle(color: e.active ? null : sem.muted)),
                      subtitle: Text(
                          [e.empNo, e.jobTitle, s.departmentPath(e.departmentId), if (!e.active) 'موقوف'].where((x) => x.isNotEmpty).join(' · '),
                          style: TextStyle(color: sem.muted, fontSize: 12.5)),
                      trailing: e.profileId == null
                          ? null
                          : Tooltip(message: 'له حساب: ${app.people[e.profileId]?.displayName ?? ''}', child: Icon(Icons.link_rounded, color: sem.ok)),
                      onTap: edit ? () => _editEmp(e) : null,
                    ),
                ]),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------
// الاستيراد من Excel أو CSV
// ---------------------------------------------------------------------

/// يختار ملف Excel (xlsx) أو CSV ويقرأ أوراقه.
Future<List<BoqSheetRows>?> _pickSheet(BuildContext context) async {
  try {
    final picked = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: const ['xlsx', 'csv', 'xls']);
    if (picked.isEmpty) return null;
    final f = picked.first;
    final ext = extOf(f.name);
    if (ext == 'xls') throw StateError('صيغة Excel القديمة (xls) لا تُقرأ. احفظ الملف بصيغة xlsx ثم أعد المحاولة.');
    final bytes = await f.readAsBytes();
    if (bytes.isEmpty) throw StateError('الملف «${f.name}» فارغ.');
    if (bytes.length > 20 * 1024 * 1024) throw StateError('الملف أكبر من 20 ميجابايت.');
    final sheets = ext == 'csv' ? [BoqSheetRows('CSV', readCsv(bytes))] : await compute(readXlsx, bytes);
    if (sheets.every((x) => x.rows.isEmpty)) throw StateError('لا بيانات في الملف.');
    return sheets;
  } catch (e) {
    if (context.mounted) showToast(context, e is StateError ? e.message : friendlyError(e), error: true);
    return null;
  }
}

/// استيراد الموظفين (employees) أو الأصناف (items): اختيار الملف، ثم المراجعة، ثم الحفظ.
Future<void> startStoresImport(BuildContext context, String kind) async {
  final sheets = await _pickSheet(context);
  if (sheets == null || !context.mounted) return;
  await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => _ImportPage(kind: kind, sheets: sheets)));
}

class _ImportPage extends StatefulWidget {
  const _ImportPage({required this.kind, required this.sheets});

  final String kind;
  final List<BoqSheetRows> sheets;

  @override
  State<_ImportPage> createState() => _ImportPageState();
}

class _ImportPageState extends State<_ImportPage> {
  int _sheet = 0;
  bool _busy = false;
  String? _error;

  bool get _assets => widget.kind == 'assets';
  Map<String, List<String>> get _spec => switch (widget.kind) {
        'employees' => employeeImportColumns,
        'assets' => assetImportColumns,
        _ => itemImportColumns,
      };
  List<String> get _required => switch (widget.kind) {
        'employees' => const ['emp_no', 'full_name'],
        'assets' => const ['name', 'category'],
        _ => const ['name', 'category', 'unit'],
      };
  List<String> get _numeric => switch (widget.kind) {
        'employees' => const [],
        'assets' => const ['cost', 'life_months', 'salvage'],
        _ => const ['min_qty', 'max_qty', 'reorder_qty', 'critical_qty'],
      };

  static const Map<String, String> _assetLabels = {
    'tag': 'رقم الأصل',
    'name': 'الوصف',
    'category': 'التصنيف',
    'manufacturer': 'المصنع',
    'model': 'الموديل',
    'serial_no': 'الرقم التسلسلي',
    'purchase_date': 'تاريخ الشراء',
    'cost': 'التكلفة',
    'supplier': 'المورد',
    'invoice_no': 'رقم الفاتورة',
    'warranty_until': 'نهاية الضمان',
    'life_months': 'العمر بالأشهر',
    'salvage': 'الخردة',
    'condition': 'الحالة',
    'location': 'الموقع',
    'department': 'الإدارة',
    'emp_no': 'الرقم الوظيفي للمستلم',
    'note': 'ملاحظات',
  };

  String _label(String f) => (_assets ? _assetLabels[f] : null) ?? _labels[f] ?? f;

  static const Map<String, String> _labels = {
    'emp_no': 'الرقم الوظيفي',
    'full_name': 'الاسم',
    'department': 'الإدارة',
    'job_title': 'الوظيفة',
    'phone': 'الهاتف',
    'email': 'البريد',
    'code': 'الرمز',
    'name': 'اسم الصنف',
    'category': 'التصنيف',
    'unit': 'الوحدة',
    'min_qty': 'الحد الأدنى',
    'max_qty': 'الحد الأقصى',
    'reorder_qty': 'نقطة إعادة الطلب',
    'critical_qty': 'الاحتياطي الحرج',
    'barcode': 'الباركود',
    'description': 'الوصف',
  };

  /// صفوف الملف بعد المطابقة، وملاحظة كل صف (التصنيف يجب أن يوجد في الأصناف).
  List<ImportRow> _rows(StoresData s) {
    final rows = widget.sheets[_sheet].rows;
    final map = mapImportColumns(rows, _spec);
    if (map.headerRow < 0) return const [];
    final out = readImportRows(rows, map, required: _required, numeric: _numeric);
    if (_assets) return [for (final r in out) _checkAsset(s, r)];
    if (widget.kind != 'items') return out;
    return [
      for (final r in out)
        if (!r.ok)
          r
        else if (!s.categories.any((c) => c.code == (r.values['category'] ?? '').toUpperCase() || normalizeArabic(c.name) == normalizeArabic(r.values['category'] ?? '')))
          ImportRow(r.number, r.values, 'التصنيف غير موجود')
        else
          r,
    ];
  }

  /// صف أصل: التصنيف تصنيف أصول، والتواريخ والحالة صالحة، والرقم الوظيفي موجود.
  ImportRow _checkAsset(StoresData s, ImportRow r) {
    if (!r.ok) return r;
    String v(String k) => (r.values[k] ?? '').trim();
    String? issue;
    final cat = v('category');
    final c = s.categories.where((x) => x.code == cat.toUpperCase() || normalizeArabic(x.name) == normalizeArabic(cat)).firstOrNull;
    if (c == null) {
      issue = 'التصنيف غير موجود';
    } else if (!c.isAsset) {
      issue = 'التصنيف استهلاكي لا أصول';
    } else if (v('tag').isNotEmpty && !RegExp(r'^[A-Za-z0-9._/-]{1,30}$').hasMatch(v('tag'))) {
      issue = 'رقم الأصل بحروف لاتينية وأرقام';
    } else if (v('purchase_date').isNotEmpty && parseImportDate(v('purchase_date')) == null) {
      issue = 'تاريخ الشراء غير صالح';
    } else if (v('warranty_until').isNotEmpty && parseImportDate(v('warranty_until')) == null) {
      issue = 'تاريخ الضمان غير صالح';
    } else if (v('condition').isNotEmpty && parseAssetCondition(v('condition')) == null) {
      issue = 'الحالة غير معروفة';
    } else if (v('emp_no').isNotEmpty && !s.employees.any((e) => e.active && e.empNo.toLowerCase() == v('emp_no').toLowerCase())) {
      issue = 'الرقم الوظيفي غير موجود';
    }
    return issue == null ? r : ImportRow(r.number, r.values, issue);
  }

  Map<String, dynamic> _assetRow(ImportRow r) {
    String v(String k) => (r.values[k] ?? '').trim();
    double? n(String k) => v(k).isEmpty ? null : parseImportNumber(v(k));
    String day(String k) {
      final d = parseImportDate(v(k));
      return d == null ? '' : isoDay(d);
    }

    return {
      for (final k in const ['tag', 'name', 'category', 'manufacturer', 'model', 'serial_no', 'supplier', 'invoice_no', 'location', 'department', 'emp_no', 'note'])
        if (v(k).isNotEmpty) k: v(k),
      if (v('purchase_date').isNotEmpty) 'purchase_date': day('purchase_date'),
      if (v('warranty_until').isNotEmpty) 'warranty_until': day('warranty_until'),
      if (n('cost') != null) 'cost': n('cost'),
      if (n('life_months') != null) 'life_months': n('life_months')!.round(),
      if (n('salvage') != null) 'salvage': n('salvage'),
      if (v('condition').isNotEmpty) 'condition': parseAssetCondition(v('condition')),
    };
  }

  Future<void> _save(List<ImportRow> rows) async {
    final ok = [for (final r in rows) if (r.ok) r];
    if (ok.isEmpty) return;
    double? n(String? v) => v == null || v.isEmpty ? null : parseImportNumber(v);
    final payload = <Map<String, dynamic>>[
      for (final r in ok)
        if (_assets)
          _assetRow(r)
        else if (widget.kind == 'employees')
          {
            'emp_no': r.values['emp_no'] ?? '',
            'full_name': r.values['full_name'] ?? '',
            'department': r.values['department'] ?? '',
            'job_title': r.values['job_title'] ?? '',
            'phone': r.values['phone'] ?? '',
            'email': r.values['email'] ?? '',
          }
        else
          {
            'code': r.values['code'] ?? '',
            'name': r.values['name'] ?? '',
            'category': r.values['category'] ?? '',
            'unit': r.values['unit'] ?? '',
            'min_qty': n(r.values['min_qty']) ?? 0,
            'max_qty': n(r.values['max_qty']),
            'reorder_qty': n(r.values['reorder_qty']) ?? 0,
            'critical_qty': n(r.values['critical_qty']) ?? 0,
            'barcode': r.values['barcode'] ?? '',
            'description': r.values['description'] ?? '',
          },
    ];
    setState(() {
      _busy = true;
      _error = null;
    });
    final app = AppScope.read(context);
    final fn = widget.kind == 'employees' ? 'st_import_employees' : 'st_import_items';
    try {
      var ins = 0, upd = 0, cus = 0;
      for (var i = 0; i < payload.length; i += 2000) {
        final part = payload.sublist(i, i + 2000 > payload.length ? payload.length : i + 2000);
        final res = _assets ? await app.stImportAssets(part) : await app.stImport(fn, part);
        ins += (res['inserted'] as num?)?.toInt() ?? 0;
        upd += (res['updated'] as num?)?.toInt() ?? 0;
        cus += (res['custody'] as num?)?.toInt() ?? 0;
      }
      if (!mounted) return;
      showToast(context, 'استُورد ${payload.length} صفاً: أُضيف $ins وحُدّث $upd${cus > 0 ? ' وسُجّلت $cus عهدة' : ''}');
      Navigator.of(context).pop();
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
    final rowsRaw = widget.sheets[_sheet].rows;
    final map = mapImportColumns(rowsRaw, _spec);
    final rows = _rows(s);
    final bad = rows.where((r) => !r.ok).length;
    final missing = [for (final f in _required) if (!map.columns.containsKey(f)) _label(f)];
    final cols = [for (final f in _spec.keys) if (map.columns.containsKey(f)) f];
    return Scaffold(
      appBar: AppBar(title: Text(switch (widget.kind) { 'employees' => 'استيراد الموظفين', 'assets' => 'استيراد سجل الأصول', _ => 'استيراد الأصناف' })),
      body: PageBody(children: [
        if (widget.sheets.length > 1) ...[
          SizedBox(
            width: 320,
            child: SelectField(
              label: 'الورقة',
              value: '$_sheet',
              items: [for (var i = 0; i < widget.sheets.length; i++) ('$i', '${widget.sheets[i].name} (${widget.sheets[i].rows.length} صف)')],
              onChanged: (v) => setState(() => _sheet = int.parse(v)),
            ),
          ),
          const SizedBox(height: 12),
        ],
        InfoBanner(
          level: missing.isNotEmpty ? 'critical' : (bad > 0 ? 'warning' : 'ok'),
          text: missing.isNotEmpty
              ? 'لم تُعرف أعمدة: ${missing.join('، ')}. اجعل صف العناوين في أعلى الورقة بهذه الأسماء.'
              : 'قُرئ ${rows.length} صفاً${bad > 0 ? '، منها $bad لا تُحفظ لملاحظة فيها' : ''}. الأعمدة: ${cols.map(_label).join('، ')}.',
        ),
        const SizedBox(height: 8),
        Text(
          switch (widget.kind) {
            'employees' => 'يُحدَّث الموظف الموجود بالرقم الوظيفي نفسه ويُضاف الجديد، والإدارة غير الموجودة تُنشأ باسمها.',
            'assets' => 'يُحدَّث الأصل الموجود برقمه ويُضاف الجديد (برقم تلقائي إن تُرك)، والعمر والخردة من سياسة التصنيف إن تُركا. '
                'من له رقم وظيفي تُسجَّل عهدته باسمه. الموقع برمزه أو باسمه، والملف كله يُحفظ أو لا يُحفظ منه شيء.',
            _ => 'يُحدَّث الصنف الموجود بالرمز نفسه ويُضاف الجديد (برمز تلقائي إن تُرك)، والوحدة غير الموجودة تُنشأ، والتصنيف يجب أن يوجد.',
          },
          style: TextStyle(color: sem.muted, fontSize: 12.5),
        ),
        const SizedBox(height: 12),
        SectionCard(
          title: 'المراجعة',
          child: PmTable(
            columns: ['الصف', for (final c in cols) _label(c), 'ملاحظة'],
            rows: [
              for (final r in rows.take(300)) ['${r.number}', for (final c in cols) r.values[c] ?? '', r.issue ?? ''],
            ],
            highlight: (i) => !rows[i].ok,
          ),
        ),
        if (rows.length > 300) Text('يُعرض أول 300 صف من ${rows.length}.', style: TextStyle(color: sem.muted)),
        if (_error != null) ...[const SizedBox(height: 12), InfoBanner(level: 'critical', text: _error!)],
        const SizedBox(height: 14),
        Align(
          alignment: AlignmentDirectional.centerEnd,
          child: FilledButton.icon(
            onPressed: _busy || missing.isNotEmpty || rows.length == bad ? null : () => _save(rows),
            icon: const Icon(Icons.save_alt_rounded),
            label: Text('حفظ ${rows.length - bad} صفاً'),
          ),
        ),
      ]),
    );
  }
}

/// بند مستورد لمستند (أرصدة أول المدة أو وارد).
typedef StoreImportLine = ({String itemId, String unitId, double qty, DateTime? expiry, String batch});

/// يقرأ بنود أرصدة من ملف: الصنف برمزه أو باركوده أو اسمه، والكمية، والوحدة، وتاريخ الانتهاء والدفعة.
Future<List<StoreImportLine>?> pickOpeningLines(BuildContext context) async {
  final sheets = await _pickSheet(context);
  if (sheets == null || !context.mounted) return null;
  return Navigator.of(context).push<List<StoreImportLine>>(MaterialPageRoute(builder: (_) => _LinesImportPage(sheets: sheets)));
}

class _LinesImportPage extends StatefulWidget {
  const _LinesImportPage({required this.sheets});

  final List<BoqSheetRows> sheets;

  @override
  State<_LinesImportPage> createState() => _LinesImportPageState();
}

class _LinesImportPageState extends State<_LinesImportPage> {
  int _sheet = 0;

  List<(ImportRow, StoreImportLine?)> _parse(StoresData s) {
    final rows = widget.sheets[_sheet].rows;
    final map = mapImportColumns(rows, openingImportColumns);
    if (map.headerRow < 0) return const [];
    final out = <(ImportRow, StoreImportLine?)>[];
    for (final r in readImportRows(rows, map, required: const ['item', 'qty'], numeric: const ['qty'])) {
      if (!r.ok) {
        out.add((r, null));
        continue;
      }
      final key = r.values['item'] ?? '';
      StItem? it;
      for (final x in s.items) {
        if (x.code.toLowerCase() == key.toLowerCase() || (x.barcode.isNotEmpty && x.barcode == key)) {
          it = x;
          break;
        }
      }
      if (it == null) {
        final n = normalizeArabic(key);
        final byName = s.items.where((x) => normalizeArabic(x.name) == n).toList();
        if (byName.length == 1) it = byName.first;
      }
      if (it == null || !it.active) {
        out.add((ImportRow(r.number, r.values, it == null ? 'صنف غير معروف' : 'الصنف موقوف'), null));
        continue;
      }
      final uName = normalizeArabic(r.values['unit'] ?? '');
      String? unitId;
      for (final u in s.unitsOf(it)) {
        if (uName.isEmpty ? u.$3 == 1 : normalizeArabic(u.$2) == uName) {
          unitId = u.$1;
          break;
        }
      }
      if (unitId == null) {
        out.add((ImportRow(r.number, r.values, 'وحدة غير معرّفة للصنف'), null));
        continue;
      }
      final qty = parseImportNumber(r.values['qty'] ?? '') ?? 0;
      if (qty <= 0) {
        out.add((ImportRow(r.number, r.values, 'الكمية موجبة'), null));
        continue;
      }
      final exp = parseImportDate(r.values['expiry_date'] ?? '');
      if (it.tracksExpiry && exp == null) {
        out.add((ImportRow(r.number, r.values, 'تاريخ الانتهاء مطلوب'), null));
        continue;
      }
      out.add((r, (itemId: it.id, unitId: unitId, qty: qty, expiry: it.tracksExpiry ? exp : null, batch: r.values['batch_no'] ?? '')));
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context).stores;
    final sem = Sem.of(context);
    final parsed = _parse(s);
    final good = [for (final p in parsed) if (p.$2 != null) p.$2!];
    return Scaffold(
      appBar: AppBar(title: const Text('بنود من ملف')),
      body: PageBody(children: [
        if (widget.sheets.length > 1) ...[
          SizedBox(
            width: 320,
            child: SelectField(
              label: 'الورقة',
              value: '$_sheet',
              items: [for (var i = 0; i < widget.sheets.length; i++) ('$i', widget.sheets[i].name)],
              onChanged: (v) => setState(() => _sheet = int.parse(v)),
            ),
          ),
          const SizedBox(height: 12),
        ],
        InfoBanner(
          level: parsed.isEmpty ? 'critical' : (good.length < parsed.length ? 'warning' : 'ok'),
          text: parsed.isEmpty
              ? 'لم تُعرف الأعمدة. اجعل في أعلى الورقة: الصنف (رمزه أو باركوده أو اسمه)، والكمية، والوحدة، وتاريخ الانتهاء.'
              : 'قُرئ ${parsed.length} صفاً، يُضاف منها ${good.length}${good.length < parsed.length ? '، والبقية لملاحظة فيها' : ''}.',
        ),
        const SizedBox(height: 12),
        SectionCard(
          title: 'المراجعة',
          child: PmTable(
            columns: const ['الصف', 'الصنف', 'الكمية', 'الصلاحية', 'ملاحظة'],
            rows: [
              for (final p in parsed.take(300))
                [
                  '${p.$1.number}',
                  p.$2 == null ? (p.$1.values['item'] ?? '') : s.itemName(p.$2!.itemId),
                  p.$2 == null ? (p.$1.values['qty'] ?? '') : qtyWithUnit(p.$2!.qty, s.unitName(p.$2!.unitId)),
                  p.$2?.expiry == null ? '' : dayText(p.$2!.expiry),
                  p.$1.issue ?? '',
                ],
            ],
            highlight: (i) => parsed[i].$2 == null,
          ),
        ),
        const SizedBox(height: 8),
        Text('تُضاف البنود إلى المستند المفتوح، وتُراجع وتُعدَّل فيه قبل الحفظ.', style: TextStyle(color: sem.muted, fontSize: 12.5)),
        const SizedBox(height: 14),
        Align(
          alignment: AlignmentDirectional.centerEnd,
          child: FilledButton.icon(
            onPressed: good.isEmpty ? null : () => Navigator.of(context).pop(good),
            icon: const Icon(Icons.playlist_add_rounded),
            label: Text('إضافة ${good.length} بنداً'),
          ),
        ),
      ]),
    );
  }
}
