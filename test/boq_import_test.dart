import 'package:dc_app/boq_import.dart';
import 'package:flutter_test/flutter_test.dart';

/// استيراد المقايسة من ملف (الإصدار 1.5.0): الأرقام، والأعمدة، والبنود، وصفوف PDF.
void main() {
  test('الأرقام: العربية والفواصل والعملة والسالب، والمعادلات ليست أرقاماً', () {
    expect(parseBoqNumber('١٢٥٠٫٥'), 1250.5);
    expect(parseBoqNumber('1,250.50'), 1250.5);
    expect(parseBoqNumber('1.250,50'), 1250.5);
    expect(parseBoqNumber('12,5'), 12.5);
    expect(parseBoqNumber('12,500'), 12500);
    expect(parseBoqNumber('1,234,567'), 1234567);
    expect(parseBoqNumber('2.300.000'), 2300000);
    expect(parseBoqNumber('450 د.ل'), 450);
    expect(parseBoqNumber('(1,000)'), -1000);
    expect(parseBoqNumber('٣٥٠ م3'), isNull, reason: 'وحدة مع الرقم: ليس رقماً صرفاً');
    expect(parseBoqNumber('=B2*C2'), isNull);
    expect(parseBoqNumber('أعمال الحفر'), isNull);
    expect(parseBoqNumber(''), isNull);
    expect(parseBoqNumber('-'), isNull);
  });

  test('رأس الجدول: أطول كلمة تحسم العمود', () {
    expect(headerRole('سعر الوحدة'), BoqCol.price);
    expect(headerRole('الوحدة'), BoqCol.unit);
    expect(headerRole('رقم البند'), BoqCol.code);
    expect(headerRole('ر.ت'), BoqCol.code);
    expect(headerRole('البيان'), BoqCol.desc);
    expect(headerRole('الكمية'), BoqCol.qty);
    expect(headerRole('القيمة الإجمالية'), BoqCol.total);
    expect(headerRole('السعر الإجمالي'), BoqCol.total);
    expect(headerRole('الفئة (دينار)'), BoqCol.price);
    expect(headerRole('Unit Price'), BoqCol.price);
    expect(headerRole('حفر خنادق للأساسات بعمق متر ونصف في جميع أنواع التربة'), isNull);
  });

  const rows = [
    ['مقايسة أعمال صيانة مدرسة الفجر', '', '', '', '', ''],
    ['', '', '', '', '', ''],
    ['ر.ت', 'البيان', 'الوحدة', 'الكمية', 'سعر الوحدة', 'الإجمالي'],
    ['أولاً: الأعمال التمهيدية', '', '', '', '', ''],
    ['1.1', 'حفر خنادق للأساسات بعمق لا يقل عن 1.5 متر', 'م3', '٢٤٠', '35', '8,400'],
    ['', 'مع نقل المخلفات إلى المكب المعتمد', '', '', '', ''],
    ['1.2', 'ردم بالتربة المختارة على طبقات', 'م3', '180', '22.5', '4,050'],
    ['', 'مجموع الأعمال التمهيدية', '', '', '', '12,450'],
    ['ر.ت', 'البيان', 'الوحدة', 'الكمية', 'سعر الوحدة', 'الإجمالي'],
    ['ثانياً: الأعمال الخرسانية', '', '', '', '', ''],
    ['2.1', 'خرسانة مسلحة للقواعد', 'م3', '60', '950', '57,000'],
    ['2.2', 'خرسانة عادية للنظافة', 'م3', '20', '480', '9,000'],
    ['2.3', 'حديد تسليح إضافي', 'طن', '', '3,200', ''],
    ['', 'الإجمالي العام', '', '', '', '78,450'],
  ];

  test('البنود من جدول Excel: الرأس والعناوين والسطر الملحق والمجاميع والرأس المكرر', () {
    final cols = detectBoqColumns(rows);
    expect(cols.headerRow, 2);
    expect(cols.map, {BoqCol.code: 0, BoqCol.desc: 1, BoqCol.unit: 2, BoqCol.qty: 3, BoqCol.price: 4, BoqCol.total: 5});
    final r = extractBoq(rows);
    expect(r.items.length, 5);
    expect(r.lines.where((l) => l.heading).map((l) => l.desc), ['أولاً: الأعمال التمهيدية', 'ثانياً: الأعمال الخرسانية']);
    final first = r.items.first;
    expect(first.code, '1.1');
    expect(first.desc, 'حفر خنادق للأساسات بعمق لا يقل عن 1.5 متر مع نقل المخلفات إلى المكب المعتمد');
    expect(first.qty, 240);
    expect(first.price, 35);
    expect(first.total, 8400);
    expect(first.ok, isTrue);
    expect(first.source, 5);
    // الإجمالي في الملف لا يطابق: 20 × 480 = 9600 لا 9000
    expect(r.items[3].issues, contains('الإجمالي في الملف لا يساوي الكمية × السعر'));
    // بند بلا كمية
    expect(r.items[4].issues, contains('بلا كمية'));
    expect(r.withIssues, 2);
    expect(r.skipped, 2);
    expect(r.fileTotal, 78450);
    expect(r.total, 8400 + 4050 + 57000 + 9600);
    expect(r.items.first.toJson(), {'code': '1.1', 'desc': first.desc, 'unit': 'م3', 'price': 35.0, 'qty': 240.0, 'notes': ''});
  });

  test('تصحيح الأعمدة يدوياً يعيد الاستخراج بها', () {
    final r = extractBoq(rows, columns: BoqColumns(2, {BoqCol.desc: 1, BoqCol.unit: 2, BoqCol.qty: 3, BoqCol.price: 4}));
    expect(r.items.first.code, '');
    expect(r.items.first.total, isNull);
    expect(r.items.first.computed, 8400);
  });

  test('جدول بلا رأس: الأعمدة من المحتوى والإجمالي = الكمية × السعر', () {
    const plain = [
      ['3.2.1', 'طلاء الجدران الداخلية بالدهان البلاستيكي وجهين', 'م2', '1200', '18', '21600'],
      ['3.2.2', 'طلاء الأسقف بالدهان المائي', 'م2', '400', '15', '6000'],
      ['3.2.3', 'دهان حديد الدرابزين بالزيتي', 'م.ط', '80', '25', '2000'],
    ];
    final cols = detectBoqColumns(plain);
    expect(cols.headerRow, -1);
    expect(cols.map[BoqCol.desc], 1);
    expect(cols.map[BoqCol.unit], 2);
    expect(cols.map[BoqCol.qty], 3);
    expect(cols.map[BoqCol.price], 4);
    expect(cols.map[BoqCol.total], 5);
    expect(cols.map[BoqCol.code], 0);
    final r = extractBoq(plain);
    expect(r.items.length, 3);
    expect(r.withIssues, 0);
  });

  test('السعر يُستنتج من الإجمالي والكمية إن غاب عموده', () {
    const t = [
      ['البيان', 'الوحدة', 'الكمية', 'الإجمالي'],
      ['تبليط الأرضيات', 'م2', '50', '2500'],
    ];
    final r = extractBoq(t);
    expect(r.items.single.price, 50);
    expect(r.items.single.ok, isTrue);
  });

  test('صفوف PDF: الأسطر والخلايا من اليمين، والأعمدة من الرأس، والرأس المكرر في الصفحة الثانية', () {
    // صفحة عرضها 595 والجدول من اليمين: الرقم، البيان، الوحدة، الكمية، السعر، الإجمالي
    PdfRun run(String s, double right, double y, double w) => PdfRun(s, right - w, y, w, 9);
    List<PdfRun> header(double y) => [
          run('ر.ت', 560, y, 14),
          run('البيان', 430, y, 26),
          run('الوحدة', 285, y, 26),
          run('الكمية', 235, y, 26),
          run('سعر', 175, y, 14),
          run('الوحدة', 155, y, 26), // «سعر الوحدة» في قطعتين متجاورتين
          run('الإجمالي', 85, y, 34),
        ];
    final page1 = [
      run('مقايسة', 400, 40, 30),
      ...header(100),
      run('1.1', 558, 118, 12),
      run('حفر', 470, 118, 14),
      run('خنادق', 452, 118, 22),
      run('للأساسات', 426, 118, 34),
      run('م3', 280, 118, 10),
      run('240', 232, 118, 14),
      run('35', 170, 118, 10),
      run('8,400', 80, 118, 22),
      // السطر الثاني للوصف بلا أرقام
      run('مع', 470, 131, 10),
      run('النقل', 456, 131, 20),
      run('1.2', 558, 146, 12),
      run('ردم', 470, 146, 14),
      run('م3', 280, 146, 10),
      run('180', 232, 146, 14),
      run('22.5', 172, 146, 16),
      run('4,050', 80, 146, 22),
    ];
    final page2 = [
      ...header(60),
      run('2.1', 558, 78, 12),
      run('خرسانة', 470, 78, 28),
      run('م3', 280, 78, 10),
      run('60', 232, 78, 10),
      run('950', 172, 78, 14),
      run('57,000', 82, 78, 26),
    ];
    final rows = pdfRows([page1, page2]);
    expect(rows.first, ['', 'مقايسة', '', '', '', ''], reason: 'العنوان قبل الرأس في عمود البيان');
    expect(rows[1], ['ر.ت', 'البيان', 'الوحدة', 'الكمية', 'سعر الوحدة', 'الإجمالي']);
    expect(rows[2], ['1.1', 'حفر خنادق للأساسات', 'م3', '240', '35', '8,400']);
    final r = extractBoq(rows);
    expect(r.items.map((l) => l.code), ['1.1', '1.2', '2.1']);
    expect(r.items.first.desc, 'حفر خنادق للأساسات مع النقل');
    expect(r.items.last.total, 57000);
    expect(r.withIssues, 0);
  });

  test('البند المكتوب في سطرين وأرقامه في الثاني', () {
    const t = [
      ['م', 'البيان', 'الوحدة', 'الكمية', 'السعر', 'الإجمالي'],
      ['4.1', 'توريد وتركيب أبواب خشبية', '', '', '', ''],
      ['', 'مقاس 90×210 سم', 'عدد', '12', '650', '7800'],
    ];
    final r = extractBoq(t);
    expect(r.items.single.code, '4.1');
    expect(r.items.single.desc, 'توريد وتركيب أبواب خشبية مقاس 90×210 سم');
    expect(r.items.single.qty, 12);
    expect(r.lines.where((l) => l.heading), isEmpty);
  });
}
