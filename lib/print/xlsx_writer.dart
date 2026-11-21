// كاتب Excel: ورقة من اليمين إلى اليسار، بأسطر الجهة والعنوان ووصف ما استُخرج أعلاها،
// ورأس جدول ملوّن، والأرقام قيماً حقيقية بفواصل الآلاف، وسطر مجاميع بمعادلات SUM.

import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

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
    if (c.showRef) 'الرقم: ${ctx.refText(c)}',
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
  final keyCol = {for (var j = 0; j < cols.length; j++) cols[j].key: j + off};
  for (var i = 0; i < t.rows.length; i++) {
    final r = t.rows[i];
    final odd = i.isOdd;
    if (c.rowNumbers) sh.updateCell(at(0, row), IntCellValue(i + 1), cellStyle: body(ColType.number, odd));
    for (var j = 0; j < cols.length; j++) {
      final v = j < r.length ? r[j] : null;
      final type = cols[j].type;
      // العمود المحسوب معادلة حية تعتمد على خلايا صفه
      final f = cols[j].formula;
      if (f != null && Formula.refs(f).every(keyCol.containsKey)) {
        final rr = row + 1;
        sh.updateCell(at(j + off, row), FormulaCellValue(Formula.toExcel(f, (k) => '${_colLetter(keyCol[k]!)}$rr')),
            cellStyle: body(type, odd));
        continue;
      }
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
  if (t.rows.isNotEmpty) _analysisSheet(excel, name, t, off, first, last, head, thin);
  final bytes = excel.encode();
  if (bytes == null) throw StateError('تعذّر إنشاء ملف Excel');
  return Uint8List.fromList(_forceRtl(bytes));
}

/// ورقة «التحليل»: العدد والمجموع والمتوسط والأدنى والأعلى لكل عمود رقمي بمعادلات تشير إلى ورقة البيانات،
/// فتتغير نتائجها تلقائياً إن عُدّلت القيم أو المعادلات في ورقة البيانات.
void _analysisSheet(Excel excel, String dataSheet, ExportTable t, int off, int first, int last, CellStyle head, Border thin) {
  final numeric = [for (var j = 0; j < t.columns.length; j++) if (t.columns[j].numeric) j];
  if (numeric.isEmpty) return;
  const name = 'التحليل';
  if (name == dataSheet) return;
  final sh = excel[name];
  sh.isRTL = true;
  CellIndex at(int col, int row) => CellIndex.indexByColumnRow(columnIndex: col, rowIndex: row);
  final cell = CellStyle(horizontalAlign: HorizontalAlign.Center, numberFormat: NumFormat.standard_4, leftBorder: thin, rightBorder: thin, topBorder: thin, bottomBorder: thin);
  final label = CellStyle(bold: true, horizontalAlign: HorizontalAlign.Right, leftBorder: thin, rightBorder: thin, topBorder: thin, bottomBorder: thin);
  sh.updateCell(at(0, 0), TextCellValue('المؤشر'), cellStyle: head);
  for (var k = 0; k < numeric.length; k++) {
    sh.updateCell(at(k + 1, 0), TextCellValue(t.columns[numeric[k]].label), cellStyle: head);
    sh.setColumnWidth(k + 1, 18);
  }
  sh.setColumnWidth(0, 22);
  final q = "'${dataSheet.replaceAll("'", "''")}'";
  final rows = <(String, String, bool)>[
    ('عدد القيم', 'COUNT', true),
    ('المجموع', 'SUM', false),
    ('المتوسط', 'AVERAGE', true),
    ('الأدنى', 'MIN', true),
    ('الأعلى', 'MAX', true),
  ];
  for (var i = 0; i < rows.length; i++) {
    sh.updateCell(at(0, i + 1), TextCellValue(rows[i].$1), cellStyle: label);
    for (var k = 0; k < numeric.length; k++) {
      final col = t.columns[numeric[k]];
      final l = _colLetter(numeric[k] + off);
      final range = '$q!\$$l\$${first + 1}:\$$l\$${last + 1}';
      final ok = rows[i].$3 || col.type != ColType.percent;
      sh.updateCell(at(k + 1, i + 1), ok ? FormulaCellValue('IFERROR(${rows[i].$2}($range),"")') : TextCellValue('—'), cellStyle: cell);
    }
  }
  sh.updateCell(at(0, rows.length + 2),
      TextCellValue('النتائج معادلات مرتبطة بورقة «$dataSheet»: عدّل القيم هناك فتتغير هنا تلقائياً.'),
      cellStyle: CellStyle(italic: true, fontColorHex: ExcelColor.fromHexString('FF6B7280')));
}

/// مكتبة excel لا تكتب اتجاه الورقة من اليمين إذا أُعيدت تسميتها، فيُضاف rightToLeft في ملف الورقة نفسه.
List<int> _forceRtl(List<int> bytes) {
  final arc = ZipDecoder().decodeBytes(bytes);
  final out = Archive();
  for (final f in arc.files) {
    if (f.isFile && f.name.startsWith('xl/worksheets/sheet') && f.name.endsWith('.xml')) {
      var xml = utf8.decode(f.content as List<int>);
      if (!xml.contains('rightToLeft=')) xml = xml.replaceAll('<sheetView ', '<sheetView rightToLeft="1" ');
      final data = utf8.encode(xml);
      out.addFile(ArchiveFile(f.name, data.length, data));
    } else {
      out.addFile(f);
    }
  }
  return ZipEncoder().encode(out) ?? bytes;
}
