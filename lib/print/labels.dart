// =====================================================================
// ملصقات الأصناف (الإصدار 1.7.0): صفحة A4 من 24 ملصقاً (3 × 8)، في كل ملصق رمز QR برمز الصنف،
// واسمه ووحدته، ورمزه، وباركوده (Code 128) إن كان له باركود. تُطبع على ورق ملصقات قياسي 70 × 37 مم.
// =====================================================================

import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'assets.dart';
import 'model.dart' show hasArabic;

typedef LabelItem = ({String code, String name, String barcode, String unit});

/// ملف PDF بملصقات الأصناف؛ [copies] نسخ لكل صنف متتالية.
Future<Uint8List> buildItemLabels(List<LabelItem> items, {int copies = 1}) async {
  final files = fontFiles('naskh');
  pw.Font ttf(Uint8List b) => pw.Font.ttf(ByteData.sublistView(b));
  final regular = ttf(await assetBytes(files.$1));
  final bold = ttf(await assetBytes(files.$2));
  final latin = ttf(await assetBytes(latinRegular));
  final theme = pw.ThemeData.withFont(base: regular, bold: bold, fontFallback: [latin]);

  final all = <LabelItem>[
    for (final it in items)
      for (var i = 0; i < (copies < 1 ? 1 : copies); i++) it,
  ];
  const cols = 3, rows = 8;
  const perPage = cols * rows;
  final mm = PdfPageFormat.mm;
  final format = PdfPageFormat.a4.copyWith(marginLeft: 0, marginRight: 0, marginTop: 0, marginBottom: 0);
  final w = format.width / cols;
  final h = format.height / rows;
  final ink = PdfColor.fromInt(0xFF1F2933);
  final muted = PdfColor.fromInt(0xFF66707A);

  pw.Widget label(LabelItem it) {
    final rtl = hasArabic(it.name);
    return pw.Container(
      width: w,
      height: h,
      padding: pw.EdgeInsets.all(3 * mm),
      child: pw.Row(children: [
        pw.BarcodeWidget(barcode: pw.Barcode.qrCode(), data: it.code, width: h - 8 * mm, height: h - 8 * mm, drawText: false),
        pw.SizedBox(width: 2.5 * mm),
        pw.Expanded(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            mainAxisAlignment: pw.MainAxisAlignment.center,
            children: [
              pw.Text(it.name,
                  maxLines: 2,
                  textAlign: pw.TextAlign.right,
                  textDirection: rtl ? pw.TextDirection.rtl : pw.TextDirection.ltr,
                  style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold, color: ink)),
              if (it.unit.isNotEmpty)
                pw.Text(it.unit, textDirection: pw.TextDirection.rtl, style: pw.TextStyle(fontSize: 7, color: muted)),
              pw.SizedBox(height: 1.5 * mm),
              pw.Text(it.code, textDirection: pw.TextDirection.ltr, style: pw.TextStyle(fontSize: 8, color: ink)),
              if (it.barcode.isNotEmpty && RegExp(r'^[\x20-\x7E]+$').hasMatch(it.barcode)) ...[
                pw.SizedBox(height: 1 * mm),
                pw.BarcodeWidget(
                  barcode: pw.Barcode.code128(),
                  data: it.barcode,
                  height: 6 * mm,
                  width: w - h - 2 * mm,
                  drawText: false,
                ),
              ],
            ],
          ),
        ),
      ]),
    );
  }

  final doc = pw.Document(theme: theme, title: 'ملصقات الأصناف');
  for (var start = 0; start < all.length; start += perPage) {
    final page = all.sublist(start, start + perPage > all.length ? all.length : start + perPage);
    doc.addPage(pw.Page(
      pageFormat: format,
      build: (_) => pw.Column(children: [
        for (var r = 0; r < rows; r++)
          pw.Row(children: [
            for (var c = 0; c < cols; c++)
              r * cols + c < page.length ? label(page[r * cols + c]) : pw.SizedBox(width: w, height: h),
          ]),
      ]),
    ));
  }
  return doc.save();
}
