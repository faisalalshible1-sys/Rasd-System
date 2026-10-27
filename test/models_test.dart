import 'package:dc_app/models.dart';
import 'package:flutter_test/flutter_test.dart';

/// يتحقق من أن حساب الإنجاز يطابق ملف Excel الأصلي.
void main() {
  final defs = <FormDef>[
    for (final (i, k, n, s) in const [
      (1, 'f01', 'أمر تعاقد', 0),
      (2, 'f02', 'أمر عمل', 0),
      (3, 'f03', 'نموذج عقد أشغال عامة', 0),
      (4, 'f04', 'تكليف مهندس مشرف', 1),
      (5, 'f05', 'تكليف مهندس حصر', 1),
      (6, 'f06', 'تكليف مهندس متابعة', 1),
      (7, 'f07', 'تكليف مهندس سلامة', 1),
      (8, 'f08', 'محضر تسليم واستلام موقع', 2),
      (9, 'f09', 'تصريح عمل', 2),
      (10, 'f10', 'ورقة قياس مستخلص نموذج أ', 3),
      (11, 'f11', 'ورقة قياس مستخلص نموذج ب', 3),
      (12, 'f12', 'كشف حصر مستخلص', 3),
      (13, 'f13', 'شهادة دفع مستخلص', 3),
      (14, 'f14', 'مستند مستخلص جاري', 3),
      (15, 'f15', 'مستند مستخلص ختامي', 3),
      (16, 'f16', 'محضر استلام ابتدائي', 4),
      (17, 'f17', 'محضر استلام نهائي', 4),
      (18, 'f18', 'إقفال عقد', 4),
    ])
      FormDef(key: k, name: n, stage: s, sort: i, sensitive: s >= 3, responsible: const ['office_staff']),
  ];

  test('المشروع 001: 4 من 15 = 26.7%، التالي أمر تعاقد', () {
    final st = {
      'f01': FormStatus.wip,
      'f04': FormStatus.done,
      'f08': FormStatus.done,
      'f09': FormStatus.done,
      'f10': FormStatus.na,
      'f11': FormStatus.na,
      'f14': FormStatus.na,
      'f15': FormStatus.done,
    };
    final p = computeProgress(defs, st);
    expect(p.done, 4);
    expect(p.required, 15);
    expect(p.pct, closeTo(0.266666, 1e-4));
    expect(p.next?.name, 'أمر تعاقد');
    expect(stageName(p.stage), 'التعاقد');
    expect(p.cycle, CycleState.running);
  });

  test('المشروع 012: 2 من 13، التالي أمر عمل', () {
    final st = {
      'f01': FormStatus.na,
      'f03': FormStatus.na,
      'f04': FormStatus.done,
      'f05': FormStatus.na,
      'f08': FormStatus.done,
      'f10': FormStatus.na,
      'f11': FormStatus.na,
    };
    final p = computeProgress(defs, st);
    expect(p.done, 2);
    expect(p.required, 13);
    expect(p.next?.name, 'أمر عمل');
  });

  test('مشروع فارغ لم يبدأ، ومشروع مكتمل', () {
    expect(computeProgress(defs, {}).cycle, CycleState.notStarted);
    final all = {for (final d in defs) d.key: FormStatus.done};
    final p = computeProgress(defs, all);
    expect(p.cycle, CycleState.complete);
    expect(p.pct, 1.0);
    expect(stageName(p.stage), stageDoneName);
  });

  test('قراءة المبالغ: أرقام عربية وفواصل، والفراغ يعني غير مُدخل', () {
    expect(parseMoney('1,250,000').value, 1250000);
    expect(parseMoney('١٢٥٠٠٠٠٫٥').value, 1250000.5);
    expect(parseMoney(' 12500.1234 ').value, 12500.123);
    final empty = parseMoney('');
    expect(empty.ok, isTrue);
    expect(empty.value, isNull);
    expect(parseMoney('-5').ok, isFalse);
    expect(parseMoney('12a').ok, isFalse);
    expect(parseMoney('1.2.3').ok, isFalse);
  });

  test('عرض المبالغ والضمانان 5% و2%', () {
    expect(fmtMoney(1250000), '1,250,000');
    expect(fmtMoney(12500.5), '12,500.5');
    expect(fmtMoney(999), '999');
    expect(fmtMoney(null), '—');
    expect(moneyInput(1250000.25), '1250000.25');
    expect(roundMoney(1250000 * guaranteeInitialRate), 62500);
    expect(roundMoney(1250000 * guaranteeFinalRate), 25000);
  });

  test('تطبيع البحث العربي', () {
    expect(normalizeArabic('إثمار  بنغازي'), normalizeArabic('اثمار بنغازي'));
    expect(normalizeArabic('المدينة'), 'المدينه');
  });
}
