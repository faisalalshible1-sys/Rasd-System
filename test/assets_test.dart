import 'package:dc_app/app_state.dart';
import 'package:dc_app/assets.dart';
import 'package:dc_app/models.dart';
import 'package:dc_app/screens/home_shell.dart' show Tabs;
import 'package:dc_app/stores.dart';
import 'package:flutter_test/flutter_test.dart';

/// الإصدار 1.8.0 (الترحيل 39): الأصول والعهد والإهلاك. مثالا الفصل 34 المحلولان، وهما نفسهما في اختبار قاعدة البيانات 121.
void main() {
  final asOf = DateTime(2026, 11, 26);

  const laptop = StAsset(
    id: 'lap',
    tag: 'OFE-A-0001',
    name: 'حاسوب محمول',
    categoryId: 'ofe',
    cost: 3600,
    lifeMonths: 36,
    salvage: 0,
  );

  test('الأشهر المنقضية كدالة st_months_between', () {
    expect(monthsBetween(DateTime(2026, 1, 15), DateTime(2026, 11, 26)), 10);
    expect(monthsBetween(DateTime(2026, 1, 15), DateTime(2026, 11, 14)), 9, reason: 'اليوم 14 لم يبلغ 15');
    expect(monthsBetween(DateTime(2026, 1, 31), DateTime(2026, 2, 28)), 0);
    expect(monthsBetween(DateTime(2026, 1, 15), DateTime(2026, 2, 15)), 1);
    expect(monthsBetween(DateTime(2026, 5, 1), DateTime(2026, 3, 1)), 0, reason: 'لا أشهر قبل البداية');
    expect(monthsBetween(DateTime(2024, 3, 1), DateTime(2026, 11, 26)), 32);
  });

  test('مثال الحاسوب: المتراكم 1,000 والدفترية 2,600 والقسط 100', () {
    final a = StAsset(
        id: laptop.id, tag: laptop.tag, name: laptop.name, categoryId: laptop.categoryId, cost: 3600, lifeMonths: 36,
        purchaseDate: DateTime(2026, 1, 10), inServiceDate: DateTime(2026, 1, 15));
    expect(a.depStart, DateTime(2026, 1, 15), reason: 'الإهلاك من بدء الاستخدام');
    expect(a.accumulated(asOf), 1000);
    expect(a.bookValue(asOf), 2600);
    expect(a.monthlyDepreciation, 100);
    expect(a.monthsLeft(asOf), 26);
    expect(a.bookValue(DateTime(2026, 11, 14)), 2700);
  });

  test('مثال المكتب: (1,200 − 120) × 32 ÷ 120 = 288، والدفترية 912، ولا تنزل عن الخردة', () {
    final desk = StAsset(id: 'd', tag: 'FUR-OLD-17', name: 'مكتب', categoryId: 'fur', cost: 1200, salvage: 120, lifeMonths: 120,
        purchaseDate: DateTime(2024, 3, 1));
    expect(desk.accumulated(asOf), 288);
    expect(desk.bookValue(asOf), 912);
    final short = StAsset(id: 'd2', tag: 'X', name: 'مكتب', categoryId: 'fur', cost: 1200, salvage: 120, lifeMonths: 12,
        purchaseDate: DateTime(2024, 3, 1));
    expect(short.bookValue(asOf), 120, reason: 'بعد اكتمال العمر تبقى عند الخردة');
    expect(short.monthsLeft(asOf), 0);
  });

  test('التقريب إلى ثلاث خانات، وبلا إهلاك، وبلا تاريخ', () {
    expect(accumulatedDepreciation(cost: 1000, salvage: 0, method: 'straight', lifeMonths: 7, start: DateTime(2026, 1, 1), asOf: DateTime(2026, 2, 1)),
        142.857);
    expect(accumulatedDepreciation(cost: 5000, salvage: 0, method: 'none', lifeMonths: null, start: DateTime(2020), asOf: asOf), 0);
    const noDate = StAsset(id: 'n', tag: 'N', name: 'بلا تاريخ', categoryId: 'c', cost: 900, lifeMonths: 12);
    expect(noDate.bookValue(asOf), 900, reason: 'لا إهلاك قبل تسجيل تاريخ الشراء أو بدء الاستخدام');
  });

  test('المستبعد يتوقف إهلاكه عند تاريخ استبعاده', () {
    final a = StAsset(
      id: 'x', tag: 'X', name: 'طابعة', categoryId: 'ofe', cost: 1200, lifeMonths: 60, purchaseDate: DateTime(2025, 1, 1),
      status: 'disposed', disposalKind: 'scrap', disposalDate: DateTime(2026, 1, 1), disposedAt: DateTime(2026, 1, 1),
    );
    expect(a.accumulated(asOf), 240, reason: '12 شهراً حتى الاستبعاد × 20');
    expect(a.bookValue(asOf), 960);
    expect(a.isEditable, isFalse);
    expect(a.isFree, isFalse);
  });

  test('الأوضاع: ما يُسلَّم وما يتغير وضعه', () {
    expect(laptop.canHandOver, isTrue);
    const inCustody = StAsset(id: 'c', tag: 'C', name: 'س', categoryId: 'c', status: 'custody', employeeId: 'e1');
    expect(inCustody.canHandOver, isFalse);
    expect(inCustody.isFree, isFalse, reason: 'يُرجَع أولاً');
    const repair = StAsset(id: 'm', tag: 'M', name: 'س', categoryId: 'c', status: 'maintenance');
    expect(repair.canHandOver, isFalse);
    expect(repair.isFree, isTrue);
    expect(assetStatusLabels['disposal'], 'بانتظار الاستبعاد');
  });

  test('سجل العهد: المفتوحة، وما ينتظر التأكيد، والمجاميع', () {
    final data = AssetsData(
      assets: [
        laptop,
        const StAsset(id: 'b', tag: 'B', name: 'شاشة', categoryId: 'ofe', cost: 500, lifeMonths: 48, salvage: 50, status: 'custody', employeeId: 'e2'),
        const StAsset(id: 'z', tag: 'Z', name: 'مستبعد', categoryId: 'ofe', cost: 999, status: 'disposed', disposalKind: 'scrap'),
      ],
      custody: [
        StCustody(id: 'c1', custodyNo: 'CU-2026-0001', assetId: 'lap', employeeId: 'e1', handedOn: DateTime(2026, 2, 1),
            returnedOn: DateTime(2026, 10, 1), conditionIn: 'fair', confirmedAt: DateTime(2026, 2, 2)),
        StCustody(id: 'c2', custodyNo: 'CU-2026-0002', assetId: 'b', employeeId: 'e2', handedOn: DateTime(2026, 3, 1)),
      ],
      policies: const [StAssetPolicy(categoryId: 'ofe', lifeMonths: 60)],
    );
    expect(data.openCustodyOf('b')?.custodyNo, 'CU-2026-0002');
    expect(data.openCustodyOf('lap'), isNull);
    expect(data.unconfirmed.map((c) => c.id), ['c2']);
    expect(data.custodyOfAsset('lap').single.days(asOf), 242, reason: 'من 1 فبراير إلى 1 أكتوبر');
    expect(data.active.length, 2, reason: 'المستبعد خارج القائمة');
    final t = data.totals(asOf);
    expect(t.cost, 4100);
    expect(t.book, 3600 + 500, reason: 'الحاسوب والشاشة بلا تاريخ بدء فلا إهلاك');
    expect(data.policyOf('ofe')?.label, '60 شهراً');
  });

  test('السياسات نصاً للدليل كما في build_manual.py', () {
    expect(depPoliciesText(const [('الأجهزة المكتبية', StAssetPolicy(categoryId: 'a', lifeMonths: 60)),
      ('الأثاث', StAssetPolicy(categoryId: 'b', lifeMonths: 120, salvagePct: 12.5)),
      ('أراضٍ', StAssetPolicy(categoryId: 'c', depMethod: 'none'))]),
        '«الأجهزة المكتبية» 60 شهراً، «الأثاث» 120 شهراً وخردة 12.5%، «أراضٍ» بلا إهلاك');
    expect(depPoliciesText(const []), 'لم تُحدَّد بعد');
  });

  test('استيراد الأصول: الحالة بالعربية والأعمدة', () {
    expect(parseAssetCondition('جيد'), 'good');
    expect(parseAssetCondition('تالفة'), 'damaged');
    expect(parseAssetCondition('new'), 'new');
    expect(parseAssetCondition('غريب'), isNull);
    final rows = [
      ['رقم الأصل', 'الوصف', 'التصنيف', 'التكلفة', 'تاريخ الشراء', 'الرقم الوظيفي'],
      ['', 'طابعة ليزر', 'OFE', '1,500', '01/06/2025', 'E-101'],
    ];
    final map = mapImportColumns(rows, assetImportColumns);
    expect(map.columns.keys, containsAll(['tag', 'name', 'category', 'cost', 'purchase_date', 'emp_no']));
    final r = readImportRows(rows, map, required: const ['name', 'category'], numeric: const ['cost']);
    expect(r.single.ok, isTrue);
    expect(parseImportNumber(r.single.values['cost']!), 1500);
    expect(parseImportDate(r.single.values['purchase_date']!), DateTime(2025, 6, 1));
  });

  test('صفحتا الأصول والعهد في قسم المخازن، والنطاق والتدقيق', () {
    expect(AppState.sectionOf(Tabs.storesAssets), 'stores');
    expect(AppState.sectionOf(Tabs.storesCustody), 'stores');
    expect(AppState.storesAssetsTab, Tabs.storesAssets);
    expect(AppState.storesCustodyTab, Tabs.storesCustody);
    expect(storesScopeLabels['stores:assets'], contains('الأصول'));
    for (final a in const ['stores.asset', 'stores.asset_transfer', 'stores.asset_status', 'stores.custody_out', 'stores.custody_in',
      'stores.custody_confirm', 'stores.asset_dispose_request', 'stores.asset_dispose', 'stores.assets_import', 'stores.asset_policy']) {
      expect(auditActionLabels[a], isNotNull, reason: a);
    }
  });
}
