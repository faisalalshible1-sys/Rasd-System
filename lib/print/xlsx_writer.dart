// كاتب Excel: ورقة من اليمين إلى اليسار، بأسطر الجهة والعنوان ووصف ما استُخرج أعلاها،
// ورأس جدول ملوّن، والأرقام قيماً حقيقية بفواصل الآلاف، وسطر مجاميع بمعادلات SUM.

import 'dart:typed_data';

import 'package:excel/excel.dart';

import 'model.dart';

String _sheetName(String s) {
  final clean = s.replaceAll(RegExp(r'[\[\]\*\?/\\:]'), ' ').trim();
  if (clean.isEmpty) return 'البيانات';
  return clean.length > 31 ? clean.substring(0, 31) : clean;
}

String _colLetter(int i) {
  var n = i + 1;
  var s = '';
  while (n > 0) {
    final r = (n - 1) % 26;
    s = String.fromCharCode(65 + r) + s;
    n = (n - 1) ~/ 26;
  }
  return s;
}

Uint8List buildXlsx(ExportTable t, PrintConfig c, PrintContext ctx) {
  final excel = Excel.createExcel();
  final name = _sheetName(titleOf(t, c));
  final def = excel.getDefaultSheet();
  if (def != null && def != name) excel.rename(def, name);
  final sh = excel[name];
  sh.isRTL = true;

  final accentHex = 'FF${(c.accent & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';
  final accent = ExcelColor.fromHexString(accentHex);
  final thin = Border(borderStyle: BorderStyle.Thin, borderColorHex: ExcelColor.fromHexString('FFCBD2D9'));
  final cols = t.columns;
  final off = c.rowNumbers ? 1 : 0;
  final ncols = cols.length + off;
  CellIndex at(int col, int row) => CellIndex.indexByColumnRow(columnIndex: col, rowIndex: row);

  var row = 0;
  void line(String text, {bool bold = false, int size = 11, ExcelColor? color}) {
    if (ncols > 1) sh.merge(at(0, row), at(ncols - 1, row), customValue: TextCellValue(text));
    sh.updateCell(at(0, row), TextCellValue(text),
        cellStyle: CellStyle(bold: bold, fontSize: size, fontColorHex: color ?? ExcelColor.black, horizontalAlign: HorizontalAlign.Center));
    row++;
  }

  for (final l in c.orgLines.where((l) => l.trim().isNotEmpty)) {
    line(l, bold: true);
  }
  line(titleOf(t, c), bold: true, size: 15, color: accent);
  final sub = [if (c.subtitle.trim().isNotEmpty) c.subtitle.trim(), if (t.section.isNotEmpty) t.section].join(' · ');
  if (sub.isNotEmpty) line(sub);
  line([
    if (c.showRef) 'الرقم: ${c.refPrefix}/${ctx.ref}',
    'التاريخ: ${fmtDateBy(ctx.at, c.dateStyle)}',
    'طبعه: ${ctx.printedBy}',
  ].join('   ·   '), size: 10);
  if (t.meta.isNotEmpty) line(t.meta.map((m) => '${m.$1}: ${m.$2}').join('   ·   '), size: 10);
  if (t.summary.isNotEmpty) line(t.summary.map((m) => '${m.$1}: ${m.$2}').join('   ·   '), size: 10);
  row++;

  // رأس الجدول
  final head = CellStyle(
    bold: true,
    fontColorHex: c.headerFill == 'accent' ? ExcelColor.white : ExcelColor.black,
    backgroundColorHex: switch (c.headerFill) {
      'gray' => ExcelColor.fromHexString('FFE4E7EB'),
      'none' => ExcelColor.none,
      _ => accent,
    },
    horizontalAlign: HorizontalAlign.Center,
    verticalAlign: VerticalAlign.Center,
    textWrapping: TextWrapping.WrapText,
    leftBorder: thin,
    rightBorder: thin,
    topBorder: thin,
    bottomBorder: thin,
  );
  final headRow = row;
  if (c.rowNumbers) sh.updateCell(at(0, row), TextCellValue('ت'), cellStyle: head);
  for (var j = 0; j < cols.length; j++) {
    sh.updateCell(at(j + off, row), TextCellValue(cols[j].label), cellStyle: head);
  }
  row++;

  CellStyle body(ColType type, bool odd) => CellStyle(
        horizontalAlign: type == ColType.text || type == ColType.long ? HorizontalAlign.Right : HorizontalAlign.Center,
        verticalAlign: VerticalAlign.Center,
        textWrapping: type == ColType.long ? TextWrapping.WrapText : null,
        backgroundColorHex: c.zebra && odd ? ExcelColor.fromHexString('FFF4F1EA') : ExcelColor.none,
        numberFormat: type == ColType.money
            ? NumFormat.standard_4
            : (type == ColType.number ? NumFormat.standard_3 : (type == ColType.percent ? NumFormat.standard_2 : NumFormat.standard_0)),
        leftBorder: thin,
        rightBorder: thin,
        topBorder: thin,
        bottomBorder: thin,
      );

  final first = row;
  for (var i = 0; i < t.rows.length; i++) {
    final r = t.rows[i];
    final odd = i.isOdd;
    if (c.rowNumbers) sh.updateCell(at(0, row), IntCellValue(i + 1), cellStyle: body(ColType.number, odd));
    for (var j = 0; j < cols.length; j++) {
      final v = j < r.length ? r[j] : null;
      final type = cols[j].type;
      final CellValue value = switch (v) {
        null => TextCellValue(''),
        int n when type != ColType.money => IntCellValue(n),
        num n => DoubleCellValue(n.toDouble()),
        DateTime d => TextCellValue(fmtDateBy(d, c.dateStyle)),
        bool b => TextCellValue(b ? 'نعم' : 'لا'),
        _ => TextCellValue(v.toString()),
      };
      sh.updateCell(at(j + off, row), value, cellStyle: body(v is num ? type : (type == ColType.long ? ColType.long : ColType.text), odd));
    }
    row++;
  }
  final last = row - 1;

  // سطر المجاميع بمعادلات حتى تبقى صحيحة إن عُدّلت القيم
  if (c.totals && t.rows.isNotEmpty && t.hasTotals) {
    final tot = CellStyle(
      bold: true,
      backgroundColorHex: ExcelColor.fromHexString('FFEDE6D6'),
      horizontalAlign: HorizontalAlign.Center,
      numberFormat: NumFormat.standard_4,
      topBorder: Border(borderStyle: BorderStyle.Double, borderColorHex: accent),
      bottomBorder: thin,
      leftBorder: thin,
      rightBorder: thin,
    );
    var labelled = false;
    if (c.rowNumbers) sh.updateCell(at(0, row), TextCellValue(''), cellStyle: tot);
    for (var j = 0; j < cols.length; j++) {
      final col = j + off;
      if (t.total(j) != null) {
        final l = _colLetter(col);
        sh.updateCell(at(col, row), FormulaCellValue('SUM($l${first + 1}:$l${last + 1})'), cellStyle: tot);
      } else if (!labelled && !cols[j].numeric) {
        sh.updateCell(at(col, row), TextCellValue('المجموع'), cellStyle: tot);
        labelled = true;
      } else {
        sh.updateCell(at(col, row), TextCellValue(''), cellStyle: tot);
      }
    }
    row++;
  }

  // عرض الأعمدة حسب نوعها
  if (c.rowNumbers) sh.setColumnWidth(0, 6);
  for (var j = 0; j < cols.length; j++) {
    final w = switch (cols[j].type) {
      ColType.long => 48.0,
      ColType.date => 13.0,
      ColType.money => 17.0,
      ColType.number || ColType.percent => 11.0,
      _ => (cols[j].flex * 16).clamp(12, 40).toDouble(),
    };
    sh.setColumnWidth(j + off, w);
  }
  if (headRow >= 0 && c.notes.trim().isNotEmpty) {
    row++;
    line('ملاحظات: ${c.notes.trim()}', size: 10);
  }
  final bytes = excel.encode();
  if (bytes == null) throw StateError('تعذّر إنشاء ملف Excel');
  return Uint8List.fromList(bytes);
}
