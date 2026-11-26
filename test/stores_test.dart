import 'package:dc_app/app_state.dart';
import 'package:dc_app/models.dart';
import 'package:dc_app/screens/home_shell.dart' show Tabs;
import 'package:dc_app/stores.dart';
import 'package:flutter_test/flutter_test.dart';

/// الإصدار 1.7.0 (الترحيل 38): قسم المخازن — الكميات والوحدات والمستويات والحجز والاحتياطي الحرج والصلاحية والاستيراد.
/// الأرقام مثالا الفصل 34 المحلولان، وهي نفسها في اختبار قاعدة البيانات 120.
void main() {
  const a4 = StItem(
    id: 'a4',
    code: 'PAP-0001',
    name: 'ورق A4 80 غم',
    categoryId: 'pap',
    baseUnitId: 'ream',
    minQty: 10,
    maxQty: 200,
    reorderQty: 20,
    criticalQty: 5,
  );

  StoresData data({double onHand = 50, double reserved = 0, List<StDoc> docs = const [], List<StDocLine> lines = const []}) => StoresData(
        warehouses: const [StWarehouse(id: 'main', code: 'MAIN', name: 'المخزن الرئيسي', kind: 'main')],
        units: const [StUnit(id: 'ream', name: 'رزمة'), StUnit(id: 'carton', name: 'كرتونة')],
        items: const [a4],
        itemUnits: const [StItemUnit(itemId: 'a4', unitId: 'carton', factor: 5)],
        stock: [StStock(warehouseId: 'main', itemId: 'a4', onHand: onHand, reserved: reserved)],
        docs: docs,
        lines: lines,
      );

  StDoc issue(String id) => StDoc(id: id, docNo: 'IS-2026-0002', kind: 'issue', status: 'submitted', warehouseId: 'main', departmentId: 'gen');

  test('عرض الكميات: فواصل الآلاف وحتى ثلاث خانات دون أصفار زائدة', () {
    expect(fmtQty(1250), '1,250');
    expect(fmtQty(12.5), '12.5');
    expect(fmtQty(0.125), '0.125');
    expect(fmtQty(-3), '-3');
    expect(fmtQty(1234567.0004), '1,234,567');
    expect(roundQty(2 * 1.0005), 2.001);
    expect(signedQty(50), '\u2066+50\u2069', reason: 'الإشارة معزولة يساراً فلا تنتقل إلى آخر الرقم');
    expect(signedQty(-10), '\u2066-10\u2069');
  });

  test('العدد مع معدوده: لا بنود، بند واحد، بندان، 3 بنود، 11 بنداً', () {
    String b(int n) => arCount(n, one: 'بند', two: 'بندان', few: 'بنود', many: 'بنداً');
    expect(b(0), 'لا بنود');
    expect(b(1), 'بند واحد');
    expect(b(2), 'بندان');
    expect(b(3), '3 بنود');
    expect(b(10), '10 بنود');
    expect(b(11), '11 بنداً');
    expect(b(103), '103 بنود');
  });

  test('الكمية بالوحدة الأساسية = الكمية × معامل الوحدة (10 كراتين = 50 رزمة)', () {
    const l = StDocLine(id: 'l', docId: 'd', lineNo: 1, itemId: 'a4', unitId: 'carton', qty: 10, factor: 5);
    expect(l.baseQty, 50);
    final s = data();
    expect(s.factorOf(a4, 'carton'), 5);
    expect(s.factorOf(a4, 'ream'), 1);
    expect(s.factorOf(a4, 'box'), isNull);
    expect(s.unitsOf(a4).map((u) => u.$2), ['رزمة', 'كرتونة']);
  });

  test('المتاح = الفعلي − المحجوز، ومستوى الصنف بالترتيب', () {
    final s = data(onHand: 50, reserved: 10);
    expect(s.available('a4'), 40);
    expect(s.levelOf(a4), 'ok', reason: '40 أكبر من نقطة الطلب 20');
    expect(stockLevel(a4, onHand: 20, available: 20), 'reorder');
    expect(stockLevel(a4, onHand: 12, available: 8), 'min');
    expect(stockLevel(a4, onHand: 0, available: 0), 'out');
    expect(stockLevel(a4, onHand: 250, available: 250), 'over');
    expect(stockLevel(const StItem(id: 'x', code: 'X', name: 'بلا حدود', categoryId: 'c', baseUnitId: 'u'), onHand: 0, available: 0), 'ok',
        reason: 'صنف بلا حد أدنى ولا نقطة طلب لا يُنبَّه له');
    expect(data(onHand: 8).lowStock().single.level, 'min');
    expect(data(onHand: 50).lowStock(), isEmpty);
  });

  test('مثال الفصل 34: لا صرف فوق المتاح، والاحتياطي الحرج يحتاج استثناء', () {
    // بعد اعتماد صرف كرتونتين (10 رزم): الفعلي 50 والمحجوز 10 والمتاح 40
    final over = issue('d41');
    final s1 = data(onHand: 50, reserved: 10, docs: [over], lines: const [
      StDocLine(id: 'x', docId: 'd41', lineNo: 1, itemId: 'a4', unitId: 'ream', qty: 41),
    ]);
    expect(s1.outgoingOf(over), {('main', 'a4'): 41.0});
    expect(s1.shortages(over).single.$2, 40);
    expect(s1.criticalTouches(over), isEmpty, reason: 'النقص يُرفض قبل الاحتياطي');

    final crit = issue('d38');
    final s2 = data(onHand: 50, reserved: 10, docs: [crit], lines: const [
      StDocLine(id: 'y', docId: 'd38', lineNo: 1, itemId: 'a4', unitId: 'ream', qty: 38),
    ]);
    expect(s2.shortages(crit), isEmpty);
    expect(s2.criticalTouches(crit).single.$1.id, 'a4', reason: 'المتاح بعده 2 أقل من الاحتياطي 5');

    final ok = issue('d30');
    final s3 = data(onHand: 50, reserved: 10, docs: [ok], lines: const [
      StDocLine(id: 'z', docId: 'd30', lineNo: 1, itemId: 'a4', unitId: 'carton', qty: 6, factor: 5),
    ]);
    expect(s3.outgoingOf(ok), {('main', 'a4'): 30.0}, reason: '6 كراتين = 30 رزمة');
    expect(s3.criticalTouches(ok), isEmpty, reason: 'المتاح بعده 10');
  });

  test('الخارج: الصرف والتحويل كل بنودهما، والتسوية بنودها السالبة، والداخل لا يُحجز', () {
    const adj = StDoc(id: 'ad', docNo: 'AD-2026-0001', kind: 'adjust', status: 'submitted', warehouseId: 'main');
    const rc = StDoc(id: 'rc', docNo: 'RC-2026-0001', kind: 'receipt', status: 'submitted', warehouseId: 'main');
    final s = data(docs: const [adj, rc], lines: const [
      StDocLine(id: '1', docId: 'ad', lineNo: 1, itemId: 'a4', unitId: 'ream', qty: -2),
      StDocLine(id: '2', docId: 'ad', lineNo: 2, itemId: 'a4', unitId: 'ream', qty: 1),
      StDocLine(id: '3', docId: 'rc', lineNo: 1, itemId: 'a4', unitId: 'carton', qty: 2),
    ]);
    expect(s.outgoingOf(adj), {('main', 'a4'): 2.0});
    expect(s.outgoingOf(rc), isEmpty);
    expect(adj.direction, 0);
    expect(rc.direction, 1);
    expect(const StDoc(id: 'r', docNo: 'RV-2026-0001', kind: 'issue', status: 'draft', warehouseId: 'main', reversesId: 'is').direction, 1,
        reason: 'عكس الصرف داخل');
    expect(issue('i').direction, -1);
  });

  test('المسودة التي لم تُقدَّم تُحذف، وغيرها يُلغى', () {
    const d = StDoc(id: 'd', docNo: 'IS-1', kind: 'issue', status: 'draft', warehouseId: 'main');
    expect(d.deletable, isTrue);
    final returned = StDoc(id: 'd', docNo: 'IS-1', kind: 'issue', status: 'draft', warehouseId: 'main', submittedAt: DateTime(2026, 11, 1));
    expect(returned.deletable, isFalse);
    expect(d.statusLabel, 'مسودة');
    expect(d.title, 'مستند صرف');
  });

  test('مثال الصلاحية: ما ينتهي خلال المدة أو انتهى، الأقرب أولاً', () {
    final today = DateTime(2026, 11, 26);
    final s = StoresData(
      batches: [
        StBatch(id: 'b2', warehouseId: 'main', itemId: 'dis', expiryDate: DateTime(2027, 1, 31), qty: 15),
        StBatch(id: 'b1', warehouseId: 'main', itemId: 'dis', expiryDate: DateTime(2026, 12, 31), qty: 10),
        StBatch(id: 'b0', warehouseId: 'main', itemId: 'dis', expiryDate: DateTime(2026, 11, 20), qty: 2),
        StBatch(id: 'bz', warehouseId: 'main', itemId: 'dis', expiryDate: DateTime(2026, 12, 1), qty: 0),
      ],
      settings: const StSettings(expiryDays: 60),
    );
    expect(s.expiring(today).map((b) => b.id), ['b0', 'b1'], reason: 'b2 بعد 66 يوماً، والفارغة لا تُعرض');
    expect(s.expiring(today, 90).map((b) => b.id), ['b0', 'b1', 'b2']);
    expect(s.expiring(today).first.daysLeft(today), -6);
  });

  test('الإعدادات: فصل المهام مفعّل والتنبيه 60 يوماً افتراضياً', () {
    final d = StSettings.fromRows(const []);
    expect(d.separation, isTrue);
    expect(d.expiryDays, 60);
    final x = StSettings.fromRows(const [
      {'key': 'separation', 'value': false},
      {'key': 'expiry_days', 'value': 30},
    ]);
    expect(x.separation, isFalse);
    expect(x.expiryDays, 30);
  });

  test('الاستيراد: مطابقة العناوين العربية والأرقام والتواريخ', () {
    final rows = [
      ['كشف موظفي المقر', '', ''],
      ['الرقم الوظيفي', 'الاسم الكامل', 'الإدارة'],
      ['E-100', 'سالم علي', 'الإدارة العامة'],
      ['', '', ''],
      ['', 'بلا رقم', ''],
    ];
    final map = mapImportColumns(rows, employeeImportColumns);
    expect(map.headerRow, 1);
    expect(map.columns, {'emp_no': 0, 'full_name': 1, 'department': 2});
    final r = readImportRows(rows, map, required: const ['emp_no', 'full_name']);
    expect(r.length, 2, reason: 'الصف الفارغ يُتجاوز');
    expect(r.first.ok, isTrue);
    expect(r.first.number, 3);
    expect(r.last.issue, 'حقل مطلوب فارغ');

    expect(parseImportNumber('١٢٫٥'), 12.5);
    expect(parseImportNumber('1,250'), 1250);
    expect(parseImportNumber(''), isNull);
    expect(parseImportDate('2026-12-31'), DateTime(2026, 12, 31));
    expect(parseImportDate('31/12/2026'), DateTime(2026, 12, 31));
    expect(parseImportDate('46387'), DateTime(2026, 12, 31), reason: 'رقم تاريخ Excel التسلسلي');
    expect(parseImportDate('31/02/2026'), isNull);

    final items = [
      ['الرمز', 'اسم الصنف', 'التصنيف', 'الوحدة', 'الحد الأدنى'],
      ['', 'قلم', 'STA', 'قطعة', 'عشرة'],
    ];
    final ir = readImportRows(items, mapImportColumns(items, itemImportColumns), required: const ['name'], numeric: const ['min_qty']);
    expect(ir.single.issue, 'رقم غير صالح');
  });

  test('دور الموظف وصفحات القسم', () {
    expect(parseRole('employee'), AppRole.employee);
    expect(AppRole.employee.db, 'employee');
    expect(AppRole.employee.label, contains('موظف'));
    for (final t in [Tabs.storesDashboard, Tabs.storesItems, Tabs.storesDocs, Tabs.storesBalances, Tabs.storesSetup, Tabs.storesPeople, Tabs.storesMine]) {
      expect(AppState.sectionOf(t), 'stores');
    }
    expect(AppState.storesMineTab, Tabs.storesMine);
    expect(auditActionLabels['stores.doc_post'], isNotNull);
  });
}
