import 'package:dc_app/app_state.dart';
import 'package:dc_app/assets.dart';
import 'package:dc_app/screens/home_shell.dart' show Tabs;
import 'package:dc_app/stocktaking.dart';
import 'package:dc_app/stores.dart';
import 'package:flutter_test/flutter_test.dart';

/// الجرد الدوري والتقارير (الترحيل 42): الفرق والاستهلاك والتغطية والركود وعمر الأصول، كما في أمثلة الفصل 34.
void main() {
  const a4 = StItem(id: 'a4', code: 'PAP-0001', name: 'ورق A4', categoryId: 'pap', baseUnitId: 'ream', minQty: 10, reorderQty: 20);
  const pen = StItem(id: 'pen', code: 'STA-0001', name: 'قلم', categoryId: 'sta', baseUnitId: 'pcs');
  final today = DateTime(2026, 11, 27);

  StDoc doc(String id, String kind, {String status = 'posted', DateTime? day, String? reverses, String wh = 'main'}) => StDoc(
        id: id,
        docNo: 'D-$id',
        kind: kind,
        status: status,
        warehouseId: wh,
        docDate: day,
        reversesId: reverses,
      );

  StDocLine line(String id, String docId, String item, double qty) =>
      StDocLine(id: id, docId: docId, lineNo: 1, itemId: item, unitId: 'ream', qty: qty);

  StoresData data(List<StDoc> docs, List<StDocLine> lines, {double a4Stock = 30, double penStock = 0}) => StoresData(
        warehouses: const [StWarehouse(id: 'main', code: 'MAIN', name: 'الرئيسي', kind: 'main')],
        items: const [a4, pen],
        docs: docs,
        lines: lines,
        stock: [StStock(warehouseId: 'main', itemId: 'a4', onHand: a4Stock), StStock(warehouseId: 'main', itemId: 'pen', onHand: penStock)],
      );

  test('حالات الجلسة وملخصها: الفرق = المعدود − الرصيد الفعلي الآن (مثال الدليل)', () {
    expect(const StCount(id: 'c', countNo: 'CN-2026-0001', warehouseId: 'main').isLive, isTrue);
    expect(const StCount(id: 'c', countNo: 'x', warehouseId: 'main', status: 'submitted').isLive, isTrue);
    expect(const StCount(id: 'c', countNo: 'x', warehouseId: 'main', status: 'closed').isLive, isFalse);
    // بدأ بـ 50 وعُدّ 47 وصُرفت علبتان فصار الفعلي 48 → الفرق −1 لا −3
    const c = StCount(id: 'c', countNo: 'CN-2026-0001', warehouseId: 'main', status: 'submitted');
    final k = StocktakingData(counts: const [c], lines: const [
      StCountLine(id: 'l1', countId: 'c', itemId: 'a4', systemQty: 50, countedQty: 47),
      StCountLine(id: 'l2', countId: 'c', itemId: 'pen', systemQty: 20, countedQty: 20),
      StCountLine(id: 'l3', countId: 'c', itemId: 'x', systemQty: 5),
    ]);
    final now = {'a4': 48.0, 'pen': 20.0, 'x': 5.0};
    final sum = k.summary(c, (id) => now[id] ?? 0);
    expect(sum.total, 3);
    expect(sum.counted, 2);
    expect(sum.complete, isFalse);
    expect(sum.withVariance, 1);
    expect(sum.loss, 1);
    expect(sum.gain, 0);
    expect(k.liveOf('main')?.id, 'c');
    expect(k.awaitingDecision, 1);
  });

  test('الجلسة المغلقة تعرض الفرق المقيَّد لا المحسوب', () {
    const c = StCount(id: 'c', countNo: 'x', warehouseId: 'main', status: 'closed');
    final k = StocktakingData(counts: const [c], lines: const [
      StCountLine(id: 'l1', countId: 'c', itemId: 'a4', systemQty: 50, countedQty: 47, variance: -1),
      StCountLine(id: 'l2', countId: 'c', itemId: 'pen', systemQty: 0, countedQty: 3, variance: 3),
    ]);
    final sum = k.summary(c, (_) => 999);
    expect(sum.loss, 1);
    expect(sum.gain, 3);
    expect(sum.withVariance, 2);
  });

  test('صافي الاستهلاك: الصرف − المرتجع، وعكس الصرف ينقصه (مثال الدليل)', () {
    final s = data([
      doc('i1', 'issue', day: DateTime(2026, 10, 20)),
      doc('r1', 'return', day: DateTime(2026, 10, 25)),
      doc('i2', 'issue', day: DateTime(2026, 11, 2)),
      doc('rv', 'issue', day: DateTime(2026, 11, 3), reverses: 'i2'),
      doc('rc', 'receipt', day: DateTime(2026, 11, 1)),
      doc('old', 'issue', day: DateTime(2026, 1, 1)),
      doc('dr', 'issue', status: 'draft', day: DateTime(2026, 11, 5)),
    ], [
      line('1', 'i1', 'a4', 120),
      line('2', 'r1', 'a4', 20),
      line('3', 'i2', 'a4', 10),
      line('4', 'rv', 'a4', 10),
      line('5', 'rc', 'a4', 500),
      line('6', 'old', 'a4', 999),
      line('7', 'dr', 'a4', 77),
    ]);
    final c = s.consumption(DateTime(2026, 8, 30), today);
    expect(c['a4'], 100, reason: '120 − 20 + 10 − 10، ولا يدخل الوارد ولا المسودة ولا خارج المدة');
    // التغطية = 30 ÷ (100 ÷ 90) = 27
    expect(s.coverDays('a4', today, recent: c)!.round(), 27);
    expect(s.coverDays('pen', today, recent: c), isNull);
  });

  test('تقرير الحركة: وارد وصادر وصافي، والتحويل لا يظهر دون مخزن', () {
    final s = data([
      doc('rc', 'receipt', day: DateTime(2026, 11, 1)),
      doc('i1', 'issue', day: DateTime(2026, 11, 2)),
      doc('tr', 'transfer', day: DateTime(2026, 11, 3)),
    ], [
      line('1', 'rc', 'a4', 40),
      line('2', 'i1', 'a4', 15),
      line('3', 'tr', 'a4', 9),
    ]);
    final rows = s.movement(DateTime(2026, 11, 1), today);
    expect(rows.length, 1);
    expect(rows.first.received, 40);
    expect(rows.first.issued, 15);
    expect(rows.first.consumed, 15);
    final w = s.movement(DateTime(2026, 11, 1), today, warehouseId: 'main');
    expect(w.first.issued, 24, reason: 'التحويل خارجٌ من مخزنه المصدر');
  });

  test('الأصناف الراكدة: بلا صرف مرحَّل في المدة، ومن لم يُصرف قط أولاً', () {
    final s = data([
      doc('i1', 'issue', day: DateTime(2026, 5, 1)),
      doc('i2', 'issue', day: DateTime(2026, 11, 20)),
    ], [
      line('1', 'i1', 'a4', 5),
      line('2', 'i2', 'pen', 5),
    ], a4Stock: 30, penStock: 8);
    final st = s.stagnant(today, 90);
    expect(st.map((x) => x.item.id).toList(), ['a4']);
    expect(st.first.daysSince, 210);
    final s2 = data(const [], const [], a4Stock: 30, penStock: 0);
    final none = s2.stagnant(today, 90);
    expect(none.length, 1);
    expect(none.first.lastIssue, isNull, reason: 'لم يُصرف قط');
    expect(data(const [], const [], a4Stock: 0).stagnant(today, 90), isEmpty, reason: 'لا رصيد فلا ركود');
  });

  test('عمر الأصل وفئاته وتجاوز العمر الافتراضي', () {
    StAsset a({DateTime? service, DateTime? purchase, int? life}) =>
        StAsset(id: 'a', tag: 'T', name: 'أصل', categoryId: 'c', inServiceDate: service, purchaseDate: purchase, lifeMonths: life);
    expect(assetAgeBucket(a(), today), 'unknown');
    expect(assetAgeBucket(a(service: DateTime(2026, 6, 1)), today), 'lt1');
    expect(assetAgeBucket(a(purchase: DateTime(2024, 11, 27)), today), 'y1_3', reason: 'سنتان بالضبط');
    expect(assetAgeBucket(a(service: DateTime(2022, 1, 1)), today), 'y3_5');
    expect(assetAgeBucket(a(service: DateTime(2019, 1, 1)), today), 'gt5');
    expect(assetAgeBucket(a(service: DateTime(2026, 12, 1)), today), 'lt1', reason: 'تاريخ مستقبلي لا يعطي عمراً سالباً');
    // تاريخ الخدمة يسبق الشراء
    expect(assetAgeYears(a(service: DateTime(2025, 11, 27), purchase: DateTime(2020, 1, 1)), today)!, closeTo(1.0, 0.01));
    expect(assetPastLife(a(service: DateTime(2023, 1, 1), life: 36), today), isTrue);
    expect(assetPastLife(a(service: DateTime(2025, 1, 1), life: 36), today), isFalse);
    expect(assetPastLife(a(service: DateTime(2020, 1, 1)), today), isFalse, reason: 'بلا عمر افتراضي لا تجاوز');
  });

  test('صفحات الجرد والتقارير ثابتة الأرقام', () {
    expect(Tabs.storesStocktake, 211);
    expect(Tabs.storesReports, 212);
    expect(AppState.stocktakeTab, Tabs.storesStocktake);
    expect(AppState.storeReportsTab, Tabs.storesReports);
    expect(AppState.sectionOf(Tabs.storesStocktake), 'stores');
    expect(AppState.sectionOf(Tabs.storesReports), 'stores');
  });
}
