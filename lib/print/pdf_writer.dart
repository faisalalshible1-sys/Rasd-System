// =====================================================================
// كاتب PDF: صفحة رسمية من اليمين إلى اليسار بخطوط عربية مضمّنة، وفق قالب الطباعة.
// الترويسة (الشعار وأسطر الجهة والرقم المرجعي والتاريخ)، والعنوان، ووصف ما استُخرج، والمؤشرات،
// والجدول (يُكرَّر رأسه في كل صفحة، مع الترقيم والمجاميع والتجميع)، والملاحظات، والتوقيعات،
// والتذييل (رقم الصفحة ورمز التحقق ومن طبع)، والعلامة المائية، وصفحة الغلاف اختيارياً.
// ملاحظة: جداول مكتبة pdf لا تعكس ترتيب الأعمدة مع الاتجاه، فتُرتَّب هنا من اليمين يدوياً.
// =====================================================================

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'assets.dart';
import 'model.dart';

PdfPageFormat pageFormatOf(PrintConfig c, int columns) {
  final base = switch (c.paper) {
    'A3' => PdfPageFormat.a3,
    'A5' => PdfPageFormat.a5,
    'Letter' => PdfPageFormat.letter,
    'Legal' => PdfPageFormat.legal,
    _ => PdfPageFormat.a4,
  };
  final f = c.landscapeFor(columns) ? base.landscape : base.portrait;
  final m = c.marginMm * PdfPageFormat.mm;
  return f.copyWith(marginLeft: m, marginRight: m, marginTop: m, marginBottom: m);
}

/// مزج اللون مع الأبيض بنسبة [t] (0 أبيض، 1 اللون نفسه).
PdfColor _tint(PdfColor c, double t) =>
    PdfColor(1 - (1 - c.red) * t, 1 - (1 - c.green) * t, 1 - (1 - c.blue) * t);

Future<Uint8List> buildPdf(ExportTable table, PrintConfig c, PrintContext ctx) async {
  final files = fontFiles(c.font);
  pw.Font ttf(Uint8List b) => pw.Font.ttf(ByteData.sublistView(b));
  final regular = ttf(await assetBytes(files.$1));
  final bold = ttf(await assetBytes(files.$2));
  final latin = ttf(await assetBytes(latinRegular));
  final latinB = ttf(await assetBytes(latinBold));
  final logoData = await logoBytes(c);
  final logo = logoData == null ? null : pw.MemoryImage(logoData);

  final theme = pw.ThemeData.withFont(base: regular, bold: bold, fontFallback: [latin, latinB]);
  final accent = PdfColor.fromInt(c.accent);
  final ink = PdfColor.fromInt(0xFF1F2933);
  final muted = PdfColor.fromInt(0xFF66707A);
  final rule = PdfColor.fromInt(0xFFCBD2D9);
  final fs = c.fontSize;
  final title = titleOf(table, c);
  String d(String s) => digitsOf(s, c.eastern);

  final doc = pw.Document(
    theme: theme,
    title: title,
    author: ctx.printedBy,
    creator: ctx.orgName,
    subject: table.section,
    producer: 'منظومة متابعة الدورة المستندية',
  );
  final format = pageFormatOf(c, table.columns.length + (c.rowNumbers ? 1 : 0));

  pw.TextStyle st({double? size, bool b = false, PdfColor? color}) =>
      pw.TextStyle(fontSize: size ?? fs, fontWeight: b ? pw.FontWeight.bold : pw.FontWeight.normal, color: color ?? ink);

  // ------------------------------------------------------------- العلامة المائية
  pw.Widget? background(pw.Context _) {
    if (c.watermark.trim().isEmpty) return null;
    return pw.FullPage(
      ignoreMargins: true,
      child: pw.Center(
        child: pw.Transform.rotate(
          angle: math.pi / 5,
          child: pw.Opacity(
            opacity: c.watermarkOpacity,
            child: pw.Text(c.watermark.trim(), style: st(size: 84, b: true, color: accent), textDirection: pw.TextDirection.rtl),
          ),
        ),
      ),
    );
  }

  // ------------------------------------------------------------- الترويسة
  pw.Widget logoBox(double size) =>
      logo == null ? pw.SizedBox() : pw.SizedBox(height: size, child: pw.Image(logo, height: size, fit: pw.BoxFit.contain));

  pw.Widget header(pw.Context context) {
    final lines = c.orgLines.where((l) => l.trim().isNotEmpty).toList();
    final org = pw.Column(
      crossAxisAlignment: c.logoPos == 'center' ? pw.CrossAxisAlignment.start : pw.CrossAxisAlignment.start,
      mainAxisSize: pw.MainAxisSize.min,
      children: [
        for (var i = 0; i < lines.length; i++)
          pw.Text(lines[i], style: st(size: i == 0 ? fs + 2 : fs, b: i == 0 || i == lines.length - 1, color: i == 0 ? ink : muted)),
      ],
    );
    final metaLines = <String>[
      if (c.showRef) 'الرقم: ${d('${c.refPrefix}/${ctx.ref}')}',
      if (c.showDate) 'التاريخ: ${d(fmtDateBy(ctx.at, c.dateStyle))}',
    ];
    final meta = pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.end,
      mainAxisSize: pw.MainAxisSize.min,
      children: [for (final m in metaLines) pw.Text(m, style: st(size: fs - 0.5, color: muted))],
    );
    final row = pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.center, children: [
      if (c.logoPos == 'right' && logo != null) ...[logoBox(c.logoSize), pw.SizedBox(width: 10)],
      pw.Expanded(child: org),
      if (c.logoPos == 'center' && logo != null) ...[pw.SizedBox(width: 10), logoBox(c.logoSize), pw.SizedBox(width: 10)],
      pw.Expanded(child: meta),
      if (c.logoPos == 'left' && logo != null) ...[pw.SizedBox(width: 10), logoBox(c.logoSize)],
    ]);
    return pw.Column(children: [
      row,
      pw.SizedBox(height: 6),
      if (c.headerLine == 'double') ...[
        pw.Container(height: 2, color: accent),
        pw.SizedBox(height: 1.5),
        pw.Container(height: 0.6, color: accent),
      ] else if (c.headerLine == 'single')
        pw.Container(height: 1.2, color: accent),
      pw.SizedBox(height: 10),
    ]);
  }

  // ------------------------------------------------------------- التذييل
  pw.Widget footer(pw.Context context) {
    final left = <pw.Widget>[
      if (c.showPrintedBy)
        pw.Text('طبعه: ${ctx.printedBy} · ${d(fmtDateBy(ctx.at, c.dateStyle))} ${d('${ctx.at.hour.toString().padLeft(2, '0')}:${ctx.at.minute.toString().padLeft(2, '0')}')}',
            style: st(size: fs - 2, color: muted)),
    ];
    final right = <pw.Widget>[
      if (c.footerText.trim().isNotEmpty) pw.Text(c.footerText.trim(), style: st(size: fs - 1.5, color: muted)),
      if (c.confidential.trim().isNotEmpty) pw.Text(c.confidential.trim(), style: st(size: fs - 1.5, b: true, color: accent)),
    ];
    return pw.Column(mainAxisSize: pw.MainAxisSize.min, children: [
      pw.Container(height: 0.6, color: rule),
      pw.SizedBox(height: 5),
      pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.center, children: [
        pw.Expanded(child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: right)),
        if (c.pageNumbers)
          pw.Text(d('صفحة ${context.pageNumber} من ${context.pagesCount}'), style: st(size: fs - 1, color: muted)),
        pw.Expanded(
          child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.end, children: [
            pw.Flexible(child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: left)),
            if (c.qr) ...[
              pw.SizedBox(width: 6),
              pw.BarcodeWidget(barcode: pw.Barcode.qrCode(), data: verifyText(table, c, ctx), width: 34, height: 34, drawText: false),
            ],
          ]),
        ),
      ]),
    ]);
  }

  // ------------------------------------------------------------- العنوان والوصف والمؤشرات
  List<pw.Widget> intro() => [
        pw.Center(child: pw.Text(title, style: st(size: fs + 6, b: true, color: accent), textAlign: pw.TextAlign.center)),
        if (c.subtitle.trim().isNotEmpty || (c.showSection && table.section.isNotEmpty))
          pw.Padding(
            padding: const pw.EdgeInsets.only(top: 3),
            child: pw.Center(
              child: pw.Text(
                [if (c.subtitle.trim().isNotEmpty) c.subtitle.trim(), if (c.showSection && table.section.isNotEmpty) table.section].join(' · '),
                style: st(size: fs + 0.5, color: muted),
                textAlign: pw.TextAlign.center,
              ),
            ),
          ),
        pw.SizedBox(height: 10),
        if (c.showMeta && table.meta.isNotEmpty) ...[
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: pw.BoxDecoration(color: _tint(accent, 0.06), border: pw.Border.all(color: _tint(accent, 0.35), width: 0.6)),
            child: pw.Wrap(spacing: 18, runSpacing: 3, children: [
              for (final (k, v) in table.meta)
                pw.RichText(
                  text: pw.TextSpan(children: [
                    pw.TextSpan(text: '$k: ', style: st(size: fs - 0.5, b: true)),
                    pw.TextSpan(text: d(v), style: st(size: fs - 0.5, color: muted)),
                  ]),
                ),
            ]),
          ),
          pw.SizedBox(height: 8),
        ],
        if (c.showSummary && table.summary.isNotEmpty) ...[
          pw.Row(children: [
            for (var i = 0; i < table.summary.length; i++) ...[
              if (i > 0) pw.SizedBox(width: 6),
              pw.Expanded(
                child: pw.Container(
                  padding: const pw.EdgeInsets.symmetric(vertical: 6, horizontal: 8),
                  decoration: pw.BoxDecoration(
                    border: pw.Border(top: pw.BorderSide(color: accent, width: 2), bottom: pw.BorderSide(color: rule, width: 0.6),
                        left: pw.BorderSide(color: rule, width: 0.6), right: pw.BorderSide(color: rule, width: 0.6)),
                  ),
                  child: pw.Column(children: [
                    pw.Text(d(table.summary[i].$2), style: st(size: fs + 4, b: true, color: accent)),
                    pw.Text(table.summary[i].$1, style: st(size: fs - 1.5, color: muted), textAlign: pw.TextAlign.center),
                  ]),
                ),
              ),
            ],
          ]),
          pw.SizedBox(height: 10),
        ],
      ];

  // ------------------------------------------------------------- الجدول
  final headFill = switch (c.headerFill) {
    'gray' => PdfColor.fromInt(0xFFE4E7EB),
    'none' => PdfColors.white,
    _ => accent,
  };
  final headInk = c.headerFill == 'accent' ? PdfColors.white : ink;
  final zebra = _tint(accent, 0.07);
  final cols = table.columns;
  final groupIdx = c.groupBy.isEmpty ? -1 : cols.indexWhere((x) => x.key == c.groupBy);

  pw.Widget cell(String text, {bool head = false, bool numeric = false, bool b = false, PdfColor? color}) => pw.Padding(
        padding: pw.EdgeInsets.symmetric(horizontal: c.cellPadding + 1, vertical: c.cellPadding),
        child: pw.Text(
          text,
          style: st(size: head ? fs - 0.5 : fs - 1, b: head || b, color: color ?? (head ? headInk : ink)),
          textAlign: head || numeric ? pw.TextAlign.center : pw.TextAlign.right,
          textDirection: pw.TextDirection.rtl,
        ),
      );

  /// جدول لمجموعة صفوف. الأعمدة منطقياً من اليمين: [ت؟، ...الأعمدة]، وتُعكس للرسم.
  pw.Widget tableOf(List<List<Object?>> rows, {int startNo = 1}) {
    final logical = <(String, double, bool)>[
      if (c.rowNumbers) ('ت', 0.35, true),
      for (final col in cols) (col.label, col.type == ColType.long ? col.flex * 1.8 : col.flex, col.numeric || col.type == ColType.date),
    ];
    final n = logical.length;
    // الفهرس الفيزيائي p يقابل المنطقي n-1-p
    final widths = <int, pw.TableColumnWidth>{for (var p = 0; p < n; p++) p: pw.FlexColumnWidth(logical[n - 1 - p].$2)};
    List<pw.Widget> phys(List<pw.Widget> l) => l.reversed.toList();

    final border = switch (c.borders) {
      'none' => null,
      'horizontal' => pw.TableBorder(horizontalInside: pw.BorderSide(color: rule, width: 0.5), bottom: pw.BorderSide(color: rule, width: 0.5)),
      _ => pw.TableBorder.all(color: rule, width: 0.5),
    };
    final out = <pw.TableRow>[
      pw.TableRow(
        repeat: c.repeatHeader,
        decoration: pw.BoxDecoration(
          color: headFill,
          border: c.headerFill == 'none' ? pw.Border(bottom: pw.BorderSide(color: accent, width: 1.2)) : null,
        ),
        children: phys([for (final l in logical) cell(l.$1, head: true)]),
      ),
    ];
    for (var i = 0; i < rows.length; i++) {
      final r = rows[i];
      out.add(pw.TableRow(
        decoration: c.zebra && i.isOdd ? pw.BoxDecoration(color: zebra) : null,
        children: phys([
          if (c.rowNumbers) cell(d('${startNo + i}'), numeric: true),
          for (var j = 0; j < cols.length; j++)
            cell(cellText(j < r.length ? r[j] : null, cols[j].type, dateStyle: c.dateStyle, eastern: c.eastern),
                numeric: cols[j].numeric || cols[j].type == ColType.date),
        ]),
      ));
    }
    if (c.totals) {
      final sub = ExportTable(sourceId: table.sourceId, title: '', columns: cols, rows: rows);
      if (sub.hasTotals) {
        var labelled = false;
        final cells = <pw.Widget>[];
        if (c.rowNumbers) {
          cells.add(cell('', b: true));
        }
        for (var j = 0; j < cols.length; j++) {
          final t = sub.total(j);
          if (t != null) {
            cells.add(cell(cellText(t, cols[j].type, eastern: c.eastern), numeric: true, b: true));
          } else if (!labelled && !cols[j].numeric) {
            cells.add(cell('المجموع', b: true));
            labelled = true;
          } else {
            cells.add(cell('', b: true));
          }
        }
        out.add(pw.TableRow(
          decoration: pw.BoxDecoration(color: _tint(accent, 0.16), border: pw.Border(top: pw.BorderSide(color: accent, width: 1))),
          children: phys(cells),
        ));
      }
    }
    return pw.Table(border: border, columnWidths: widths, defaultVerticalAlignment: pw.TableCellVerticalAlignment.middle, children: out);
  }

  List<pw.Widget> body() {
    if (table.rows.isEmpty) {
      return [
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(vertical: 24),
          child: pw.Center(child: pw.Text('لا سجلات مطابقة', style: st(size: fs + 1, color: muted))),
        ),
      ];
    }
    if (groupIdx < 0) return [tableOf(table.rows)];
    final groups = <String, List<List<Object?>>>{};
    for (final r in table.rows) {
      final k = cellText(groupIdx < r.length ? r[groupIdx] : null, cols[groupIdx].type, dateStyle: c.dateStyle);
      groups.putIfAbsent(k.isEmpty ? '—' : k, () => []).add(r);
    }
    final out = <pw.Widget>[];
    var no = 1;
    for (final e in groups.entries) {
      out.add(pw.Container(
        margin: const pw.EdgeInsets.only(top: 8, bottom: 3),
        padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: pw.BoxDecoration(border: pw.Border(right: pw.BorderSide(color: accent, width: 3))),
        child: pw.Text(d('${cols[groupIdx].label}: ${e.key} (${e.value.length})'), style: st(size: fs + 0.5, b: true)),
      ));
      out.add(tableOf(e.value, startNo: no));
      no += e.value.length;
    }
    return out;
  }

  // ------------------------------------------------------------- الملاحظات والتوقيعات
  List<pw.Widget> closing() => [
        if (c.notes.trim().isNotEmpty) ...[
          pw.SizedBox(height: 12),
          pw.Text('ملاحظات', style: st(size: fs + 0.5, b: true, color: accent)),
          pw.SizedBox(height: 3),
          pw.Text(c.notes.trim(), style: st(size: fs - 0.5)),
        ],
        if (c.showSignatures && c.signatures.isNotEmpty) ...[
          pw.SizedBox(height: 26),
          pw.Row(children: [
            for (final s in c.signatures)
              pw.Expanded(
                child: pw.Column(children: [
                  pw.Text(s.title, style: st(b: true)),
                  pw.SizedBox(height: 4),
                  pw.Text(s.name.isEmpty ? ' ' : s.name, style: st(color: muted)),
                  pw.SizedBox(height: 22),
                  pw.Container(width: 110, height: 0.6, color: ink),
                  pw.SizedBox(height: 2),
                  pw.Text('التوقيع', style: st(size: fs - 2, color: muted)),
                ]),
              ),
          ]),
        ],
      ];

  final pageTheme = pw.PageTheme(
    pageFormat: format,
    textDirection: pw.TextDirection.rtl,
    theme: theme,
    buildBackground: (context) => background(context) ?? pw.SizedBox(),
  );

  // ------------------------------------------------------------- صفحة الغلاف
  if (c.cover) {
    doc.addPage(pw.Page(
      pageTheme: pageTheme,
      build: (context) => pw.Column(children: [
        pw.Container(height: 6, color: accent),
        pw.Spacer(),
        if (logo != null) pw.Center(child: logoBox(c.logoSize * 2)),
        pw.SizedBox(height: 16),
        for (final l in c.orgLines.where((l) => l.trim().isNotEmpty))
          pw.Center(child: pw.Text(l, style: st(size: fs + 2, color: muted))),
        pw.SizedBox(height: 28),
        pw.Center(child: pw.Text(title, style: st(size: fs + 16, b: true, color: accent), textAlign: pw.TextAlign.center)),
        if (c.subtitle.trim().isNotEmpty)
          pw.Padding(
            padding: const pw.EdgeInsets.only(top: 6),
            child: pw.Center(child: pw.Text(c.subtitle.trim(), style: st(size: fs + 4, color: ink), textAlign: pw.TextAlign.center)),
          ),
        if (table.section.isNotEmpty)
          pw.Padding(
            padding: const pw.EdgeInsets.only(top: 6),
            child: pw.Center(child: pw.Text(table.section, style: st(size: fs + 2, color: muted))),
          ),
        pw.SizedBox(height: 20),
        pw.Center(
          child: pw.Text(
            d([
              if (c.showRef) 'الرقم: ${c.refPrefix}/${ctx.ref}',
              'التاريخ: ${fmtDateBy(ctx.at, c.dateStyle)}',
              'عدد السجلات: ${table.rows.length}',
            ].join('   ·   ')),
            style: st(color: muted),
          ),
        ),
        if (c.coverNote.trim().isNotEmpty)
          pw.Padding(
            padding: const pw.EdgeInsets.only(top: 18, left: 40, right: 40),
            child: pw.Text(c.coverNote.trim(), style: st(size: fs + 1), textAlign: pw.TextAlign.center),
          ),
        pw.Spacer(flex: 2),
        if (c.confidential.trim().isNotEmpty)
          pw.Center(child: pw.Text(c.confidential.trim(), style: st(b: true, color: accent))),
        pw.SizedBox(height: 8),
        pw.Container(height: 6, color: accent),
      ]),
    ));
  }

  doc.addPage(pw.MultiPage(
    pageTheme: pageTheme,
    maxPages: 400,
    header: header,
    footer: footer,
    build: (context) => [...intro(), ...body(), ...closing()],
  ));
  return doc.save();
}
