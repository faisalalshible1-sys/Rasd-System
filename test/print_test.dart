import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:dc_app/print/docx_writer.dart';
import 'package:dc_app/print/model.dart';
import 'package:dc_app/print/pdf_writer.dart';
import 'package:dc_app/print/text_writers.dart';
import 'package:dc_app/print/xlsx_writer.dart';
import 'package:flutter_test/flutter_test.dart';

/// اختبارات الطباعة والتصدير: القواعد المشروحة في الفصل 25 من الدليل تُحسب هنا بالشيفرة نفسها.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final table = ExportTable(
    sourceId: 'test',
    title: 'سجل المستخلصات',
    section: 'الدورة المستندية',
    columns: const [
      ExportColumn('contract', 'العقد', flex: 2),
      ExportColumn('date', 'التاريخ', type: ColType.date),
      ExportColumn('net', 'الصافي', type: ColType.money),
      ExportColumn('pct', 'الإنجاز', type: ColType.percent),
      ExportColumn('notes', 'ملاحظات', type: ColType.long),
    ],
    rows: [
      ['عقد 11 — صيانة مبنى "القنصلية"', DateTime(2026, 11, 3), 125000.5, 40.0, 'سطر أول\nسطر ثانٍ, بفاصلة'],
      ['عقد 12 — إزالة المخلفات', DateTime(2026, 10, 20), 74999.5, 65.5, null],
    ],
    summary: const [('المستخلصات', '2'), ('الصافي', '200,000')],
    meta: const [('عدد السجلات', '2')],
  );
  final ctx = PrintContext(printedBy: 'م. فيصل', orgName: 'مكتب الشؤون الهندسية', at: DateTime(2026, 11, 16, 19, 45, 30));

  test('الرقم المرجعي ونص التحقق', () {
    expect(ctx.ref, '2026/1116-194530');
    final c = PrintConfig();
    expect('${c.refPrefix}/${ctx.ref}', 'م.ش.هـ/2026/1116-194530');
    expect(verifyText(table, c, ctx), 'سجل المستخلصات | م.ش.هـ/2026/1116-194530 | 2026/11/16 19:45 | 2 سجل | م. فيصل');
  });

  test('الاتجاه التلقائي: أفقي إذا زادت الأعمدة على 6', () {
    final c = PrintConfig();
    expect(c.landscapeFor(6), isFalse);
    expect(c.landscapeFor(7), isTrue);
    expect(PrintConfig(orientation: 'portrait').landscapeFor(20), isFalse);
    expect(PrintConfig(orientation: 'landscape').landscapeFor(2), isTrue);
    // المثالان المحلولان في الفصل 25: 8 أعمدة + الترقيم أفقي، و5 + الترقيم عمودي
    expect(c.landscapeFor(8 + 1), isTrue);
    expect(c.landscapeFor(5 + 1), isFalse);
  });

  test('المجاميع: المالية والرقمية فقط، دون النسب والتواريخ', () {
    expect(table.total(2), 200000.0);
    expect(table.total(3), isNull);
    expect(table.total(1), isNull);
    expect(table.hasTotals, isTrue);
    final s = table.select(['net', 'contract']);
    expect(s.columns.map((c) => c.key), ['net', 'contract']);
    expect(s.rows.first.first, 125000.5);
  });

  test('تنسيق القيم والأرقام المشرقية', () {
    expect(fmtNumber(1234567.5), '1,234,567.50');
    expect(fmtNumber(-1200), '-1,200');
    expect(fmtNumber(0.999, decimals: 2), '1');
    expect(cellText(40.0, ColType.percent), '40%');
    expect(cellText(65.5, ColType.percent), '65.5%');
    expect(cellText(DateTime(2026, 1, 5), ColType.date, dateStyle: 'dmy'), '05/01/2026');
    expect(cellText(DateTime(2026, 1, 5), ColType.date, dateStyle: 'long'), '5 يناير 2026');
    expect(digitsOf('2026/11', true), '٢٠٢٦/١١');
  });

  test('القالب يُحفظ ويُقرأ كما هو، والقيم الشاذة تُقيَّد', () {
    final c = PrintConfig(paper: 'A3', font: 'kufi', watermark: 'سري', signatures: const [SignatureSlot('أعدّه', 'هدى')], showSignatures: true);
    final back = PrintConfig.fromJson(jsonDecode(jsonEncode(c.toJson())));
    expect(back.toJson(), c.toJson());
    final odd = PrintConfig.fromJson({'paper': 'B9', 'fontSize': 99, 'logoSize': 1, 'watermarkOpacity': 3});
    expect(odd.paper, 'A4');
    expect(odd.fontSize, 16);
    expect(odd.logoSize, 30);
    expect(odd.watermarkOpacity, 0.4);
  });

  test('CSV بعلامة UTF-8 واقتباس القيم', () {
    final bytes = buildCsv(table, PrintConfig());
    // علامة UTF-8 (EF BB BF) في أول الملف حتى يقرأ Excel العربية سليمة؛ utf8.decode يحذفها عند القراءة
    expect(bytes.sublist(0, 3), [0xEF, 0xBB, 0xBF]);
    final s = utf8.decode(bytes);
    expect(s, contains('"عقد 11 — صيانة مبنى ""القنصلية"""'));
    expect(s, contains('125000.5'));
    expect(s, contains('"سطر أول\nسطر ثانٍ, بفاصلة"'));
  });

  test('JSON بالأعمدة والصفوف', () {
    final m = jsonDecode(utf8.decode(buildJson(table, PrintConfig(), ctx))) as Map<String, dynamic>;
    expect(m['reference'], 'م.ش.هـ/2026/1116-194530');
    expect((m['rows'] as List).first['date'], '2026-11-03');
    expect((m['columns'] as List).length, 5);
  });

  test('Word: حزمة OOXML كاملة', () async {
    final bytes = await buildDocx(table, PrintConfig(showSignatures: true, cover: true, groupBy: 'contract'), ctx);
    final zip = ZipDecoder().decodeBytes(bytes);
    final names = zip.files.map((f) => f.name).toSet();
    for (final n in ['[Content_Types].xml', '_rels/.rels', 'word/document.xml', 'word/styles.xml', 'word/header1.xml', 'word/footer1.xml',
      'word/_rels/document.xml.rels', 'word/_rels/header1.xml.rels', 'docProps/core.xml']) {
      expect(names, contains(n));
    }
    expect(names.any((n) => n.startsWith('word/media/logo.')), isTrue);
    final doc = utf8.decode(zip.findFile('word/document.xml')!.content as List<int>);
    expect(doc, contains('<w:bidiVisual/>'));
    expect(doc, contains('<w:tblHeader/>'));
    expect(doc, contains('المجموع'));
    expect(doc, contains('&quot;القنصلية&quot;'));
    expect(doc, isNot(contains('<w:tc><w:tcPr><w:tcW w:w="0"')));
  });

  test('Excel: ملف صالح', () {
    final bytes = buildXlsx(table, PrintConfig(), ctx);
    expect(bytes.sublist(0, 2), [0x50, 0x4B]);
  });

  test('HTML: صفحة مستقلة من اليمين', () async {
    final s = utf8.decode(await buildHtml(table, PrintConfig(watermark: 'مسودة'), ctx));
    expect(s, contains('dir="rtl"'));
    expect(s, contains('data:image/'));
    expect(s, contains('class="wm"'));
    expect(s, contains('&quot;القنصلية&quot;'));
  });

  test('PDF: ملف صالح بخطوط عربية مضمّنة', () async {
    final bytes = await buildPdf(table, PrintConfig(cover: true, watermark: 'سري', showSignatures: true, groupBy: 'contract'), ctx);
    expect(ascii.decode(bytes.sublist(0, 5)), '%PDF-');
    expect(bytes.length, greaterThan(20000));
  });
}
