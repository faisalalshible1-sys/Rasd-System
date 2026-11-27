import 'package:flutter/material.dart';

import '../app_state.dart';
import '../models.dart' show dayText;
import '../print/export_dialog.dart' show ExportButton;
import '../stocktaking.dart';
import '../stores.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';
import 'pm_common.dart' show PmTable;
import 'stores.dart' show qtyWithUnit;

// =====================================================================
// تقارير المخازن الأساسية (الإصدار 1.11.0): حركة الأصناف والاستهلاك، وما دون الحد الأدنى، والراكد، وقرب الانتهاء،
// وعمر الأصول، ونتائج الجرد. كلها تُحسب من المستندات المرحَّلة والأرصدة المحمّلة، وتحترم ما يراه المستخدم.
// =====================================================================

String _days(double? d) => d == null ? 'لا استهلاك' : (d >= 9999 ? 'أكثر من 9999 يوماً' : '${d.round()} يوماً');

class StoreReportsPage extends StatefulWidget {
  const StoreReportsPage({super.key});

  @override
  State<StoreReportsPage> createState() => _StoreReportsPageState();
}

class _StoreReportsPageState extends State<StoreReportsPage> {
  int _span = 90; // أيام تقرير الحركة
  int _idle = stDefaultStagnantDays; // أيام الركود
  String _wh = '';

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final sem = Sem.of(context);
    final s = app.stores;
    final today = DateTime.now();
    final from = DateTime(today.year, today.month, today.day).subtract(Duration(days: _span - 1));
    final wh = _wh.isEmpty ? null : _wh;
    final mv = s.movement(from, today, warehouseId: wh);
    final cover = s.consumption(today.subtract(const Duration(days: stCoverWindowDays - 1)), today);
    final low = s.lowStock();
    final stagnant = s.stagnant(today, _idle);
    final exp = s.expiring(today);
    final closed = [for (final c in app.stocktake.counts) if (c.isClosed) c];
    String unit(StItem it) => s.unitName(it.baseUnitId);
    return PageBody(
      onRefresh: app.loadAll,
      children: [
        PageHeader(
          title: 'تقارير المخازن',
          subtitle: 'حركة الأصناف والاستهلاك، وما يحتاج توريداً، والراكد، وقرب الانتهاء، وعمر الأصول، ونتائج الجرد.',
          icon: Icons.analytics_outlined,
          actions: [
            if (app.v22Ready) const ExportButton(sourceId: 'stores:movement'),
          ],
        ),
        SectionCard(
          title: 'حركة الأصناف والاستهلاك',
          icon: Icons.swap_vert_rounded,
          subtitle: 'من المستندات المرحَّلة وحدها. الوارد والصادر بحسب اتجاه المستند، وصافي الاستهلاك = الصرف − المرتجع.',
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Wrap(spacing: 10, runSpacing: 10, children: [
              SizedBox(
                width: 200,
                child: SelectField(
                  label: 'المدة',
                  value: '$_span',
                  items: [for (final d in stReportDayOptions) ('$d', 'آخر $d يوماً')],
                  onChanged: (v) => setState(() => _span = int.tryParse(v) ?? 90),
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
            ]),
            const SizedBox(height: 12),
            mv.isEmpty
                ? Text('لا حركة مرحَّلة في هذه المدة.', style: TextStyle(color: sem.muted))
                : PmTable(
                    columns: const ['الصنف', 'الوحدة', 'وارد', 'صادر', 'صافي الاستهلاك', 'الرصيد الآن', 'تغطية'],
                    rows: [
                      for (final r in mv.take(200))
                        [
                          r.item.name,
                          unit(r.item),
                          fmtQty(r.received),
                          fmtQty(r.issued),
                          fmtQty(r.consumed),
                          fmtQty(s.onHand(r.item.id, warehouseId: wh)),
                          _days(s.coverDays(r.item.id, today, recent: cover)),
                        ],
                    ],
                  ),
          ]),
        ),
        const SizedBox(height: 14),
        SectionCard(
          title: 'تحتاج توريداً (${low.length})',
          icon: Icons.production_quantity_limits_rounded,
          subtitle: 'المتاح مقارنةً بالحد الأدنى ونقطة إعادة الطلب، مع التغطية بالأيام على استهلاك آخر $stCoverWindowDays يوماً.',
          child: low.isEmpty
              ? Text('لا صنف دون حدوده.', style: TextStyle(color: sem.muted))
              : PmTable(
                  columns: const ['الصنف', 'المستوى', 'المتاح', 'الحد الأدنى', 'نقطة الطلب', 'تغطية'],
                  rows: [
                    for (final a in low.take(200))
                      [
                        a.item.name,
                        stockLevelLabels[a.level] ?? a.level,
                        qtyWithUnit(a.available, unit(a.item)),
                        fmtQty(a.item.minQty),
                        fmtQty(a.item.reorderQty),
                        _days(s.coverDays(a.item.id, today, recent: cover)),
                      ],
                  ],
                  highlight: (i) => low[i].level == 'out' || low[i].level == 'min',
                ),
        ),
        const SizedBox(height: 14),
        SectionCard(
          title: 'أصناف راكدة (${stagnant.length})',
          icon: Icons.hourglass_bottom_rounded,
          subtitle: 'أصناف نشطة بها رصيد ولم يُصرف منها شيء مرحَّل خلال المدة المختارة.',
          trailing: SizedBox(
            width: 170,
            child: SelectField(
              label: 'الركود',
              value: '$_idle',
              items: [for (final d in stReportDayOptions) ('$d', '$d يوماً فأكثر')],
              onChanged: (v) => setState(() => _idle = int.tryParse(v) ?? stDefaultStagnantDays),
            ),
          ),
          child: stagnant.isEmpty
              ? Text('لا صنف راكد بهذه المدة.', style: TextStyle(color: sem.muted))
              : PmTable(
                  columns: const ['الصنف', 'الرصيد', 'آخر صرف', 'منذ'],
                  rows: [
                    for (final x in stagnant.take(200))
                      [x.item.name, qtyWithUnit(x.onHand, unit(x.item)), x.lastIssue == null ? 'لم يُصرف قط' : dayText(x.lastIssue), x.daysSince == null ? '' : '${x.daysSince} يوماً'],
                  ],
                ),
        ),
        const SizedBox(height: 14),
        SectionCard(
          title: 'قرب انتهاء الصلاحية (${exp.length})',
          icon: Icons.event_busy_outlined,
          subtitle: 'دفعات بكمية تنتهي خلال ${s.settings.expiryDays} يوماً أو انتهت.',
          child: exp.isEmpty
              ? Text('لا دفعة قريبة الانتهاء.', style: TextStyle(color: sem.muted))
              : PmTable(
                  columns: const ['الصنف', 'المخزن', 'الدفعة', 'تاريخ الانتهاء', 'المتبقي', 'الكمية'],
                  rows: [
                    for (final b in exp.take(200))
                      [
                        s.itemName(b.itemId),
                        s.warehouseName(b.warehouseId),
                        b.batchNo,
                        dayText(b.expiryDate),
                        b.daysLeft(today) < 0 ? 'انتهت' : '${b.daysLeft(today)} يوماً',
                        qtyWithUnit(b.qty, s.unitName(s.item(b.itemId)?.baseUnitId)),
                      ],
                  ],
                  highlight: (i) => exp[i].daysLeft(today) < 0,
                ),
        ),
        if (app.storesAssetsSees) ...[
          const SizedBox(height: 14),
          SectionCard(
            title: 'عمر الأصول',
            icon: Icons.chair_alt_outlined,
            subtitle: 'الأصول غير المستبعدة بحسب عمرها من تاريخ الخدمة (وإلا الشراء)؛ والمتجاوز عمره الافتراضي المسجَّل يُعدّ على حدة.',
            child: Builder(builder: (_) {
              final list = [for (final a in app.storeAssets.assets) if (!a.isDisposed) a];
              final by = {for (final b in assetAgeBuckets) b: 0};
              var past = 0;
              for (final a in list) {
                by[assetAgeBucket(a, today)] = (by[assetAgeBucket(a, today)] ?? 0) + 1;
                if (assetPastLife(a, today)) past++;
              }
              if (list.isEmpty) return Text('لا أصول مسجَّلة.', style: TextStyle(color: sem.muted));
              return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                PmTable(columns: const ['الفئة', 'عدد الأصول'], rows: [for (final b in assetAgeBuckets) [assetAgeLabels[b]!, '${by[b]}']]),
                const SizedBox(height: 8),
                Text('تجاوزت عمرها الافتراضي: $past من ${list.length}', style: TextStyle(color: past == 0 ? sem.muted : sem.wip, fontWeight: FontWeight.w600)),
              ]);
            }),
          ),
        ],
        const SizedBox(height: 14),
        SectionCard(
          title: 'نتائج الجرد (${closed.length})',
          icon: Icons.fact_check_outlined,
          subtitle: 'الجلسات المغلقة وما قُيّد فيها من فروق.',
          child: closed.isEmpty
              ? Text(app.v26Ready ? 'لا جلسة جرد مغلقة بعد.' : 'يلزم الترحيل 42 لعرض نتائج الجرد.', style: TextStyle(color: sem.muted))
              : PmTable(
                  columns: const ['الجلسة', 'المخزن', 'الاعتماد', 'البنود', 'بنود بفرق', 'زيادة', 'نقص', 'التسوية'],
                  rows: [
                    for (final c in closed.take(100))
                      () {
                        final sum = app.stocktake.summary(c, (_) => 0);
                        return [
                          c.countNo,
                          s.warehouseName(c.warehouseId),
                          dayText(c.decidedAt),
                          '${sum.total}',
                          '${sum.withVariance}',
                          fmtQty(sum.gain),
                          fmtQty(sum.loss),
                          s.doc(c.adjustDocId)?.docNo ?? '—',
                        ];
                      }(),
                  ],
                ),
        ),
      ],
    );
  }
}
