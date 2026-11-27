// =====================================================================
// محضر تسليم عهدة أو إرجاعها (الإصدار 1.8.0): صفحة A4 برقم المحضر وتاريخه، وبيانات الموظف والأصل،
// وحالته وملحقاته عند التسليم (وعند الإرجاع إن سُجّل)، وتوقيعا المسلِّم والمستلم.
// =====================================================================

import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'assets.dart';

/// بيانات المحضر كما تُطبع.
typedef CustodyForm = ({
  String org,
  String custodyNo,
  String handedOn,
  String employee,
  String empNo,
  String department,
  String jobTitle,
  String tag,
  String asset,
  String category,
  String description,
  String serialNo,
  String location,
  String conditionOut,
  String accessoriesOut,
  String noteOut,
  String returnedOn,
  String conditionIn,
  String accessoriesIn,
  String noteIn,
});

Future<Uint8List> buildCustodyForm(CustodyForm f) async {
  final files = fontFiles('naskh');
  pw.Font ttf(Uint8List b) => pw.Font.ttf(ByteData.sublistView(b));
  final regular = ttf(await assetBytes(files.$1));
  final bold = ttf(await assetBytes(files.$2));
  final latin = ttf(await assetBytes(latinRegular));
  final theme = pw.ThemeData.withFont(base: regular, bold: bold, fontFallback: [latin]);
  final ink = PdfColor.fromInt(0xFF1F2933);
  final muted = PdfColor.fromInt(0xFF66707A);
  final rule = PdfColor.fromInt(0xFFCBD2D9);
  final returned = f.returnedOn.isNotEmpty;

  pw.Widget t(String s, {double size = 10.5, bool b = false, PdfColor? color, pw.TextAlign align = pw.TextAlign.right}) => pw.Text(s,
      textDirection: pw.TextDirection.rtl,
      textAlign: align,
      style: pw.TextStyle(fontSize: size, fontWeight: b ? pw.FontWeight.bold : pw.FontWeight.normal, color: color ?? ink));

  pw.Widget table(List<(String, String)> rows) => pw.Table(
        border: pw.TableBorder.all(color: rule, width: 0.6),
        columnWidths: const {0: pw.FlexColumnWidth(), 1: pw.FixedColumnWidth(130)},
        children: [
          for (final r in rows)
            pw.TableRow(children: [
              pw.Container(padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6), child: t(r.$2.isEmpty ? '—' : r.$2)),
              pw.Container(
                color: PdfColor.fromInt(0xFFF2F4F6),
                padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                child: t(r.$1, color: muted),
              ),
            ]),
        ],
      );
  pw.Widget section(String title, List<(String, String)> rows) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
        pw.SizedBox(height: 12),
        t(title, size: 12, b: true),
        pw.SizedBox(height: 5),
        table(rows),
      ]);

  pw.Widget sign(String who) => pw.Expanded(
        child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
          t(who, b: true),
          pw.SizedBox(height: 6),
          t('الاسم: ..............................................', color: muted),
          pw.SizedBox(height: 10),
          t('التوقيع: ...........................................', color: muted),
          pw.SizedBox(height: 10),
          t('التاريخ: ....../....../..........', color: muted),
        ]),
      );

  final doc = pw.Document(theme: theme, title: 'محضر عهدة ${f.custodyNo}');
  doc.addPage(pw.Page(
    pageFormat: PdfPageFormat.a4.copyWith(marginLeft: 36, marginRight: 36, marginTop: 36, marginBottom: 36),
    build: (_) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [
      pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
        pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Text(f.custodyNo, textDirection: pw.TextDirection.ltr, style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: ink)),
          pw.SizedBox(height: 2),
          pw.Text(f.handedOn, textDirection: pw.TextDirection.ltr, style: pw.TextStyle(fontSize: 10, color: muted)),
        ]),
        pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
          t(f.org, size: 11, color: muted),
          pw.SizedBox(height: 4),
          t(returned ? 'محضر تسليم عهدة وإرجاعها' : 'محضر تسليم عهدة', size: 17, b: true),
        ]),
      ]),
      pw.SizedBox(height: 6),
      pw.Divider(color: rule),
      section('الموظف المستلم', [
        ('الاسم', f.employee),
        ('الرقم الوظيفي', f.empNo),
        ('الإدارة', f.department),
        ('الوظيفة', f.jobTitle),
      ]),
      section('الأصل', [
        ('رقم الأصل', f.tag),
        ('الوصف', f.asset),
        ('التصنيف', f.category),
        ('المصنع والموديل', f.description),
        ('الرقم التسلسلي', f.serialNo),
        ('الموقع', f.location),
      ]),
      section('عند التسليم', [
        ('التاريخ', f.handedOn),
        ('الحالة', f.conditionOut),
        ('الملحقات', f.accessoriesOut),
        ('ملاحظات', f.noteOut),
      ]),
      if (returned)
        section('عند الإرجاع', [
          ('التاريخ', f.returnedOn),
          ('الحالة', f.conditionIn),
          ('الملحقات', f.accessoriesIn),
          ('ملاحظات', f.noteIn),
        ]),
      pw.SizedBox(height: 14),
      t('أقرّ أنا الموظف المذكور أعلاه باستلام الأصل الموصوف بحالته وملحقاته، وأتعهد بالمحافظة عليه واستعماله '
          'في العمل، وإرجاعه عند الطلب أو عند انتهاء الحاجة إليه أو انتقالي من الإدارة.', size: 10, color: muted),
      pw.Spacer(),
      pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        sign('الموظف المستلم'),
        pw.SizedBox(width: 30),
        sign(returned ? 'مسؤول الأصول (المسلِّم والمستلم عند الإرجاع)' : 'مسؤول الأصول (المسلِّم)'),
      ]),
    ]),
  ));
  return doc.save();
}
