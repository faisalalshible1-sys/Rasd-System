// =====================================================================
// كاتب Word (DOCX): مستند من اليمين إلى اليسار يُفتح ويُعدَّل في Microsoft Word.
// يُبنى من XML مباشرة (حزمة OOXML بسيطة): ترويسة بالشعار وأسطر الجهة والرقم والتاريخ،
// وتذييل برقم الصفحة، وجدول يتكرر رأسه، والمجاميع والتجميع والتوقيعات وصفحة الغلاف.
// العلامة المائية ورمز التحقق في PDF وHTML فقط.
// =====================================================================

import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import 'assets.dart';
import 'model.dart';

String _x(String s) => s
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&apos;')
    // محارف التحكم غير مسموحة في XML
    .replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F]'), '');

String _hex(int argb) => (argb & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase();

String _tintHex(int argb, double t) {
  int ch(int v) => (255 - (255 - v) * t).round().clamp(0, 255);
  final r = ch((argb >> 16) & 0xFF), g = ch((argb >> 8) & 0xFF), b = ch(argb & 0xFF);
  return [r, g, b].map((v) => v.toRadixString(16).padLeft(2, '0')).join().toUpperCase();
}

const _ns = 'xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" '
    'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" '
    'xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing" '
    'xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" '
    'xmlns:pic="http://schemas.openxmlformats.org/drawingml/2006/picture"';

class _Docx {
  _Docx(this.c);

  final PrintConfig c;
  String get font => _x(c.wordFontName);
  int get half => (c.fontSize * 2).round();

  /// مقطع نص: [size] بنصف النقطة.
  String run(String text, {bool b = false, String? color, int? size}) {
    final s = size ?? half;
    final rpr = '<w:rPr><w:rFonts w:ascii="$font" w:hAnsi="$font" w:cs="$font"/>'
        '${b ? '<w:b/><w:bCs/>' : ''}'
        '${color != null ? '<w:color w:val="$color"/>' : ''}'
        '<w:sz w:val="$s"/><w:szCs w:val="$s"/><w:rtl/></w:rPr>';
    final parts = text.split('\n');
    final b2 = StringBuffer('<w:r>$rpr');
    for (var i = 0; i < parts.length; i++) {
      if (i > 0) b2.write('<w:br/>');
      b2.write('<w:t xml:space="preserve">${_x(parts[i])}</w:t>');
    }
    b2.write('</w:r>');
    return b2.toString();
  }

  /// فقرة من اليمين: [align] start (افتراضي) أو center.
  String para(String runs, {String align = 'start', int before = 0, int after = 0, String? shade, String? borderBottom, bool keepNext = false}) {
    final b = StringBuffer('<w:p><w:pPr>');
    if (keepNext) b.write('<w:keepNext/>');
    if (borderBottom != null) b.write(borderBottom);
    if (shade != null) b.write('<w:shd w:val="clear" w:color="auto" w:fill="$shade"/>');
    b.write('<w:bidi/><w:spacing w:before="$before" w:after="$after"/>');
    if (align == 'center') b.write('<w:jc w:val="center"/>');
    b.write('</w:pPr>$runs</w:p>');
    return b.toString();
  }

  String cell(String content, int widthTw, {String? fill, int span = 1, bool center = false}) =>
      '<w:tc><w:tcPr><w:tcW w:w="$widthTw" w:type="dxa"/>${span > 1 ? '<w:gridSpan w:val="$span"/>' : ''}'
      '${fill != null ? '<w:shd w:val="clear" w:color="auto" w:fill="$fill"/>' : ''}<w:vAlign w:val="center"/></w:tcPr>'
      '${content.startsWith('<w:p>') ? content : para(content, align: center ? 'center' : 'start')}</w:tc>';

  String borders(String kind, String color) {
    String side(String n, bool on) => on ? '<w:$n w:val="single" w:sz="4" w:space="0" w:color="$color"/>' : '<w:$n w:val="nil"/>';
    final all = kind == 'all';
    final h = kind != 'none';
    return '<w:tblBorders>${side('top', h)}${side('left', all)}${side('bottom', h)}${side('right', all)}'
        '${side('insideH', h)}${side('insideV', all)}</w:tblBorders>';
  }

  String table(List<int> widths, List<String> rows, {String bordersXml = '', bool layoutFixed = true}) {
    final total = widths.fold<int>(0, (s, w) => s + w);
    return '<w:tbl><w:tblPr><w:bidiVisual/><w:tblW w:w="$total" w:type="dxa"/>$bordersXml'
        '${layoutFixed ? '<w:tblLayout w:type="fixed"/>' : ''}'
        '<w:tblCellMar><w:top w:w="${(c.cellPadding * 14).round()}" w:type="dxa"/><w:left w:w="80" w:type="dxa"/>'
        '<w:bottom w:w="${(c.cellPadding * 14).round()}" w:type="dxa"/><w:right w:w="80" w:type="dxa"/></w:tblCellMar>'
        '</w:tblPr><w:tblGrid>${widths.map((w) => '<w:gridCol w:w="$w"/>').join()}</w:tblGrid>${rows.join()}</w:tbl>';
  }

  String row(List<String> cells, {bool header = false}) =>
      '<w:tr><w:trPr><w:cantSplit/>${header ? '<w:tblHeader/>' : ''}</w:trPr>${cells.join()}</w:tr>';

  /// صورة ضمن السطر: [rid] معرّف العلاقة، والأبعاد بوحدة EMU.
  String image(String rid, int cx, int cy, int id) =>
      '<w:r><w:drawing><wp:inline distT="0" distB="0" distL="0" distR="0"><wp:extent cx="$cx" cy="$cy"/>'
      '<wp:docPr id="$id" name="Logo $id"/><a:graphic><a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/picture">'
      '<pic:pic><pic:nvPicPr><pic:cNvPr id="$id" name="logo"/><pic:cNvPicPr/></pic:nvPicPr>'
      '<pic:blipFill><a:blip r:embed="$rid"/><a:stretch><a:fillRect/></a:stretch></pic:blipFill>'
      '<pic:spPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="$cx" cy="$cy"/></a:xfrm><a:prstGeom prst="rect"><a:avLst/></a:prstGeom></pic:spPr>'
      '</pic:pic></a:graphicData></a:graphic></wp:inline></w:drawing></w:r>';
}

/// أبعاد الورق بوحدة twip (عرض، ارتفاع) بالاتجاه العمودي.
(int, int) _paper(String p) => switch (p) {
      'A3' => (16838, 23811),
      'A5' => (8391, 11906),
      'Letter' => (12240, 15840),
      'Legal' => (12240, 20160),
      _ => (11906, 16838),
    };

Future<Uint8List> buildDocx(ExportTable table, PrintConfig c, PrintContext ctx) async {
  final w = _Docx(c);
  final accent = _hex(c.accent);
  const ink = '1F2933';
  const muted = '66707A';
  const rule = 'CBD2D9';
  String d(String s) => digitsOf(s, c.eastern);
  final title = titleOf(table, c);
  final logo = await logoBytes(c);
  final logoExt = logo == null ? 'png' : imageExt(logo);

  final cols = table.columns;
  final landscape = c.landscapeFor(cols.length + (c.rowNumbers ? 1 : 0));
  final paper = _paper(c.paper);
  final pageW = landscape ? paper.$2 : paper.$1;
  final pageH = landscape ? paper.$1 : paper.$2;
  final margin = (c.marginMm * 56.7).round();
  final usable = pageW - margin * 2;

  // ------------------------------------------------------------- الشعار
  String logoRun(String rid, int id, double heightPt) {
    if (logo == null) return '';
    final size = imageSize(logo);
    final ratio = size == null || size.$2 == 0 ? 1.0 : size.$1 / size.$2;
    final cy = (heightPt * 12700).round();
    final cx = (heightPt * ratio * 12700).round();
    return w.image(rid, cx, cy, id);
  }

  // ------------------------------------------------------------- الترويسة
  final lines = c.orgLines.where((l) => l.trim().isNotEmpty).toList();
  final orgParas = <String>[
    for (var i = 0; i < lines.length; i++)
      w.para(w.run(lines[i], b: i == 0 || i == lines.length - 1, color: i == 0 ? ink : muted, size: i == 0 ? w.half + 4 : w.half)),
  ];
  final metaParas = <String>[
    if (c.showRef) w.para(w.run(d('الرقم: ${c.refPrefix}/${ctx.ref}'), color: muted, size: w.half - 1)),
    if (c.showDate) w.para(w.run(d('التاريخ: ${fmtDateBy(ctx.at, c.dateStyle)}'), color: muted, size: w.half - 1)),
  ];
  final logoPara = logo == null ? '' : w.para(logoRun('rIdLogo', 1, c.logoSize * 0.8), align: 'center');
  final third = (usable / 3).round();
  final noBorders = w.borders('none', rule);
  // كل خلية تحتاج فقرة واحدة على الأقل
  String cellOf(List<String> paras, int width) {
    final ps = paras.where((p) => p.isNotEmpty).toList();
    return '<w:tc><w:tcPr><w:tcW w:w="$width" w:type="dxa"/><w:vAlign w:val="center"/></w:tcPr>'
        '${ps.isEmpty ? w.para('') : ps.join()}</w:tc>';
  }
  final headerCells = switch (c.logoPos) {
    'center' => [cellOf(orgParas, third), cellOf([logoPara], third), cellOf(metaParas, third)],
    'left' => [cellOf(orgParas, third), cellOf(metaParas, third), cellOf([logoPara], third)],
    _ => [cellOf([logoPara, ...orgParas], third), cellOf(const [], third), cellOf(metaParas, third)],
  };
  final lineXml = switch (c.headerLine) {
    'double' => '<w:pBdr><w:bottom w:val="double" w:sz="6" w:space="1" w:color="$accent"/></w:pBdr>',
    'single' => '<w:pBdr><w:bottom w:val="single" w:sz="8" w:space="1" w:color="$accent"/></w:pBdr>',
    _ => null,
  };
  final headerXml = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:hdr $_ns>'
      '${w.table([third, third, third], ['<w:tr>${headerCells.join()}</w:tr>'], bordersXml: noBorders)}'
      '${w.para('', borderBottom: lineXml, after: 120)}</w:hdr>';

  // ------------------------------------------------------------- التذييل
  final footerRuns = StringBuffer();
  if (c.footerText.trim().isNotEmpty) footerRuns.write(w.run('${c.footerText.trim()}   ', color: muted, size: w.half - 3));
  if (c.confidential.trim().isNotEmpty) footerRuns.write(w.run('${c.confidential.trim()}   ', b: true, color: accent, size: w.half - 3));
  if (c.pageNumbers) {
    final fr = w.run('', color: muted, size: w.half - 2).replaceAll('<w:t xml:space="preserve"></w:t>', '<w:t>1</w:t>');
    footerRuns
      ..write(w.run('صفحة ', color: muted, size: w.half - 2))
      ..write('<w:fldSimple w:instr=" PAGE ">$fr</w:fldSimple>')
      ..write(w.run(' من ', color: muted, size: w.half - 2))
      ..write('<w:fldSimple w:instr=" NUMPAGES ">$fr</w:fldSimple>');
  }
  final printed = c.showPrintedBy
      ? w.para(
          w.run(d('طبعه: ${ctx.printedBy} · ${fmtDateBy(ctx.at, c.dateStyle)} · ${c.refPrefix}/${ctx.ref}'), color: muted, size: w.half - 4),
          align: 'center')
      : '';
  final footerXml = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:ftr $_ns>'
      '${w.para(footerRuns.toString(), align: 'center', borderBottom: '<w:pBdr><w:top w:val="single" w:sz="4" w:space="4" w:color="$rule"/></w:pBdr>')}'
      '$printed</w:ftr>';

  // ------------------------------------------------------------- المتن
  final body = StringBuffer();
  if (c.cover) {
    body.write(w.para('', before: 1800));
    if (logo != null) body.write(w.para(logoRun('rIdLogoBody', 2, c.logoSize * 1.8), align: 'center', after: 240));
    for (final l in lines) {
      body.write(w.para(w.run(l, color: muted, size: w.half + 4), align: 'center'));
    }
    body.write(w.para(w.run(title, b: true, color: accent, size: w.half + 30), align: 'center', before: 600, after: 120));
    if (c.subtitle.trim().isNotEmpty) body.write(w.para(w.run(c.subtitle.trim(), size: w.half + 8), align: 'center'));
    if (table.section.isNotEmpty) body.write(w.para(w.run(table.section, color: muted, size: w.half + 4), align: 'center'));
    body.write(w.para(
        w.run(d([if (c.showRef) 'الرقم: ${c.refPrefix}/${ctx.ref}', 'التاريخ: ${fmtDateBy(ctx.at, c.dateStyle)}', 'عدد السجلات: ${table.rows.length}'].join('   ·   ')),
            color: muted),
        align: 'center',
        before: 360));
    if (c.coverNote.trim().isNotEmpty) body.write(w.para(w.run(c.coverNote.trim(), size: w.half + 2), align: 'center', before: 360));
    body.write('<w:p><w:r><w:br w:type="page"/></w:r></w:p>');
  }

  body.write(w.para(w.run(title, b: true, color: accent, size: w.half + 12), align: 'center', after: 60));
  final sub = [if (c.subtitle.trim().isNotEmpty) c.subtitle.trim(), if (c.showSection && table.section.isNotEmpty) table.section].join(' · ');
  if (sub.isNotEmpty) body.write(w.para(w.run(sub, color: muted, size: w.half + 1), align: 'center', after: 160));

  if (c.showMeta && table.meta.isNotEmpty) {
    final runs = StringBuffer();
    for (var i = 0; i < table.meta.length; i++) {
      final (k, v) = table.meta[i];
      if (i > 0) runs.write(w.run('    ', size: w.half - 1));
      runs
        ..write(w.run('$k: ', b: true, size: w.half - 1))
        ..write(w.run(d(v), color: muted, size: w.half - 1));
    }
    body.write(w.para(runs.toString(), shade: _tintHex(c.accent, 0.07), after: 160));
  }

  if (c.showSummary && table.summary.isNotEmpty) {
    final n = table.summary.length;
    final cw = (usable / n).floor();
    final cells = [
      for (final (k, v) in table.summary)
        '<w:tc><w:tcPr><w:tcW w:w="$cw" w:type="dxa"/><w:tcBorders><w:top w:val="single" w:sz="18" w:space="0" w:color="$accent"/></w:tcBorders>'
            '<w:vAlign w:val="center"/></w:tcPr>${w.para(w.run(d(v), b: true, color: accent, size: w.half + 8), align: 'center')}'
            '${w.para(w.run(k, color: muted, size: w.half - 3), align: 'center')}</w:tc>',
    ];
    body.write(w.table(List.filled(n, cw), ['<w:tr>${cells.join()}</w:tr>'], bordersXml: w.borders('all', rule)));
    body.write(w.para('', after: 120));
  }

  // الجدول: أعمدة بعرض نسبي
  final flex = <double>[if (c.rowNumbers) 0.35, for (final col in cols) col.type == ColType.long ? col.flex * 1.8 : col.flex];
  final sumFlex = flex.fold<double>(0, (s, f) => s + f);
  final widths = [for (final f in flex) (usable * f / sumFlex).floor()];
  final headFill = switch (c.headerFill) { 'gray' => 'E4E7EB', 'none' => null, _ => accent };
  final headInk = c.headerFill == 'accent' ? 'FFFFFF' : ink;
  final zebra = _tintHex(c.accent, 0.07);
  final groupIdx = c.groupBy.isEmpty ? -1 : cols.indexWhere((x) => x.key == c.groupBy);

  String headerRow() => w.row([
        if (c.rowNumbers) w.cell(w.run('ت', b: true, color: headInk), widths[0], fill: headFill, center: true),
        for (var j = 0; j < cols.length; j++)
          w.cell(w.run(cols[j].label, b: true, color: headInk), widths[j + (c.rowNumbers ? 1 : 0)], fill: headFill, center: true),
      ], header: c.repeatHeader);

  List<String> dataRows(List<List<Object?>> rows, int startNo) {
    final out = <String>[];
    for (var i = 0; i < rows.length; i++) {
      final r = rows[i];
      final fill = c.zebra && i.isOdd ? zebra : null;
      out.add(w.row([
        if (c.rowNumbers) w.cell(w.run(d('${startNo + i}'), size: w.half - 2), widths[0], fill: fill, center: true),
        for (var j = 0; j < cols.length; j++)
          w.cell(
            w.run(cellText(j < r.length ? r[j] : null, cols[j].type, dateStyle: c.dateStyle, eastern: c.eastern), size: w.half - 2),
            widths[j + (c.rowNumbers ? 1 : 0)],
            fill: fill,
            center: cols[j].numeric || cols[j].type == ColType.date,
          ),
      ]));
    }
    if (c.totals) {
      final sub = ExportTable(sourceId: table.sourceId, title: '', columns: cols, rows: rows);
      if (sub.hasTotals) {
        final fill = _tintHex(c.accent, 0.16);
        var labelled = false;
        out.add(w.row([
          if (c.rowNumbers) w.cell(w.run(''), widths[0], fill: fill),
          for (var j = 0; j < cols.length; j++)
            () {
              final t = sub.total(j);
              final wd = widths[j + (c.rowNumbers ? 1 : 0)];
              if (t != null) return w.cell(w.run(cellText(t, cols[j].type, eastern: c.eastern), b: true), wd, fill: fill, center: true);
              if (!labelled && !cols[j].numeric) {
                labelled = true;
                return w.cell(w.run('المجموع', b: true), wd, fill: fill);
              }
              return w.cell(w.run(''), wd, fill: fill);
            }(),
        ]));
      }
    }
    return out;
  }

  final tableBorders = w.borders(c.borders, rule);
  if (table.rows.isEmpty) {
    body.write(w.para(w.run('لا سجلات مطابقة', color: muted), align: 'center', before: 240, after: 240));
  } else if (groupIdx < 0) {
    body.write(w.table(widths, [headerRow(), ...dataRows(table.rows, 1)], bordersXml: tableBorders));
  } else {
    final groups = <String, List<List<Object?>>>{};
    for (final r in table.rows) {
      final k = cellText(groupIdx < r.length ? r[groupIdx] : null, cols[groupIdx].type, dateStyle: c.dateStyle);
      groups.putIfAbsent(k.isEmpty ? '—' : k, () => []).add(r);
    }
    var no = 1;
    for (final e in groups.entries) {
      body.write(w.para(w.run(d('${cols[groupIdx].label}: ${e.key} (${e.value.length})'), b: true, color: accent, size: w.half + 1),
          before: 200, after: 60, keepNext: true));
      body.write(w.table(widths, [headerRow(), ...dataRows(e.value, no)], bordersXml: tableBorders));
      no += e.value.length;
    }
  }

  if (c.notes.trim().isNotEmpty) {
    body.write(w.para(w.run('ملاحظات', b: true, color: accent, size: w.half + 1), before: 240, after: 60));
    body.write(w.para(w.run(c.notes.trim(), size: w.half - 1)));
  }
  if (c.showSignatures && c.signatures.isNotEmpty) {
    body.write(w.para('', before: 360));
    final n = c.signatures.length;
    final cw = (usable / n).floor();
    final cells = [
      for (final s in c.signatures)
        '<w:tc><w:tcPr><w:tcW w:w="$cw" w:type="dxa"/></w:tcPr>'
            '${w.para(w.run(s.title, b: true), align: 'center')}'
            '${w.para(w.run(s.name.isEmpty ? ' ' : s.name, color: muted), align: 'center', after: 480)}'
            '${w.para(w.run('................................', color: muted), align: 'center')}'
            '${w.para(w.run('التوقيع', color: muted, size: w.half - 3), align: 'center')}</w:tc>',
    ];
    body.write(w.table(List.filled(n, cw), ['<w:tr>${cells.join()}</w:tr>'], bordersXml: noBorders));
  }

  final sect = '<w:sectPr><w:headerReference w:type="default" r:id="rIdHeader"/><w:footerReference w:type="default" r:id="rIdFooter"/>'
      '<w:pgSz w:w="$pageW" w:h="$pageH"${landscape ? ' w:orient="landscape"' : ''}/>'
      '<w:pgMar w:top="$margin" w:right="$margin" w:bottom="$margin" w:left="$margin" w:header="420" w:footer="420" w:gutter="0"/>'
      '<w:bidi/></w:sectPr>';
  final documentXml = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:document $_ns><w:body>$body$sect</w:body></w:document>';

  final stylesXml = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<w:styles xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">'
      '<w:docDefaults><w:rPrDefault><w:rPr><w:rFonts w:ascii="${w.font}" w:hAnsi="${w.font}" w:cs="${w.font}"/>'
      '<w:sz w:val="${w.half}"/><w:szCs w:val="${w.half}"/><w:rtl/><w:lang w:val="ar-LY" w:bidi="ar-LY"/></w:rPr></w:rPrDefault>'
      '<w:pPrDefault><w:pPr><w:bidi/><w:spacing w:after="0" w:line="264" w:lineRule="auto"/></w:pPr></w:pPrDefault></w:docDefaults>'
      '<w:style w:type="paragraph" w:default="1" w:styleId="Normal"><w:name w:val="Normal"/><w:qFormat/></w:style>'
      '<w:style w:type="table" w:default="1" w:styleId="TableNormal"><w:name w:val="Normal Table"/><w:tblPr><w:tblInd w:w="0" w:type="dxa"/>'
      '<w:tblCellMar><w:top w:w="0" w:type="dxa"/><w:left w:w="108" w:type="dxa"/><w:bottom w:w="0" w:type="dxa"/>'
      '<w:right w:w="108" w:type="dxa"/></w:tblCellMar></w:tblPr></w:style>'
      '</w:styles>';
  const settingsXml = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<w:settings xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">'
      '<w:defaultTabStop w:val="720"/><w:compat><w:compatSetting w:name="compatibilityMode" w:uri="http://schemas.microsoft.com/office/word" w:val="15"/></w:compat>'
      '</w:settings>';

  final img = logo == null
      ? ''
      : '<Relationship Id="rIdLogoBody" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image" Target="media/logo.$logoExt"/>';
  final docRels = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
      '<Relationship Id="rIdStyles" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>'
      '<Relationship Id="rIdSettings" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/settings" Target="settings.xml"/>'
      '<Relationship Id="rIdHeader" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/header" Target="header1.xml"/>'
      '<Relationship Id="rIdFooter" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/footer" Target="footer1.xml"/>'
      '$img</Relationships>';
  final headerRels = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
      '${logo == null ? '' : '<Relationship Id="rIdLogo" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image" Target="media/logo.$logoExt"/>'}'
      '</Relationships>';
  const contentTypes = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
      '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
      '<Default Extension="xml" ContentType="application/xml"/>'
      '<Default Extension="png" ContentType="image/png"/>'
      '<Default Extension="jpeg" ContentType="image/jpeg"/>'
      '<Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>'
      '<Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/>'
      '<Override PartName="/word/settings.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.settings+xml"/>'
      '<Override PartName="/word/header1.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.header+xml"/>'
      '<Override PartName="/word/footer1.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.footer+xml"/>'
      '<Override PartName="/docProps/core.xml" ContentType="application/vnd.openxmlformats-package.core-properties+xml"/>'
      '<Override PartName="/docProps/app.xml" ContentType="application/vnd.openxmlformats-officedocument.extended-properties+xml"/>'
      '</Types>';
  const rootRels = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
      '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>'
      '<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties" Target="docProps/core.xml"/>'
      '<Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/extended-properties" Target="docProps/app.xml"/>'
      '</Relationships>';
  final iso = ctx.at.toUtc().toIso8601String().split('.').first;
  final coreXml = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties" '
      'xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:dcterms="http://purl.org/dc/terms/" '
      'xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">'
      '<dc:title>${_x(title)}</dc:title><dc:subject>${_x(table.section)}</dc:subject><dc:creator>${_x(ctx.printedBy)}</dc:creator>'
      '<dcterms:created xsi:type="dcterms:W3CDTF">${iso}Z</dcterms:created>'
      '<dcterms:modified xsi:type="dcterms:W3CDTF">${iso}Z</dcterms:modified></cp:coreProperties>';
  final appXml = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<Properties xmlns="http://schemas.openxmlformats.org/officeDocument/2006/extended-properties">'
      '<Application>Microsoft Office Word</Application><Company>${_x(ctx.orgName)}</Company></Properties>';

  final archive = Archive();
  void add(String name, String text) {
    final bytes = utf8.encode(text);
    archive.addFile(ArchiveFile(name, bytes.length, bytes));
  }

  add('[Content_Types].xml', contentTypes);
  add('_rels/.rels', rootRels);
  add('docProps/core.xml', coreXml);
  add('docProps/app.xml', appXml);
  add('word/document.xml', documentXml);
  add('word/styles.xml', stylesXml);
  add('word/settings.xml', settingsXml);
  add('word/header1.xml', headerXml);
  add('word/footer1.xml', footerXml);
  add('word/_rels/document.xml.rels', docRels);
  add('word/_rels/header1.xml.rels', headerRels);
  if (logo != null) archive.addFile(ArchiveFile('word/media/logo.$logoExt', logo.length, logo));
  final out = ZipEncoder().encode(archive);
  return Uint8List.fromList(out ?? const <int>[]);
}
