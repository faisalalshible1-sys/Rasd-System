// الصيغ النصية: CSV (بعلامة UTF-8 حتى يقرأ Excel العربية)، وHTML (صفحة مستقلة جاهزة للطباعة
// بتصميم القالب والشعار مضمّناً)، وJSON (البيانات مع وصفها لأنظمة أخرى).

import 'dart:convert';
import 'dart:typed_data';

import 'assets.dart';
import 'model.dart';

String _csvCell(String s) => s.contains(RegExp(r'[",\n\r]')) ? '"${s.replaceAll('"', '""')}"' : s;

Uint8List buildCsv(ExportTable t, PrintConfig c) {
  final b = StringBuffer('\uFEFF');
  b.writeln([if (c.rowNumbers) 'ت', for (final col in t.columns) col.label].map(_csvCell).join(','));
  for (var i = 0; i < t.rows.length; i++) {
    final r = t.rows[i];
    b.writeln([
      if (c.rowNumbers) '${i + 1}',
      for (var j = 0; j < t.columns.length; j++)
        () {
          final v = j < r.length ? r[j] : null;
          // الأرقام خاماً دون فواصل الآلاف حتى تبقى أرقاماً في برامج الجداول
          if (v is num) return v.toString();
          return cellText(v, t.columns[j].type, dateStyle: 'ymd');
        }(),
    ].map(_csvCell).join(','));
  }
  return Uint8List.fromList(utf8.encode(b.toString()));
}

Uint8List buildJson(ExportTable t, PrintConfig c, PrintContext ctx) {
  Object? enc(Object? v) => v is DateTime
      ? '${v.year.toString().padLeft(4, '0')}-${v.month.toString().padLeft(2, '0')}-${v.day.toString().padLeft(2, '0')}'
      : v;
  final data = {
    'title': titleOf(t, c),
    'section': t.section,
    'source': t.sourceId,
    'reference': '${c.refPrefix}/${ctx.ref}',
    'generated_at': ctx.at.toIso8601String(),
    'generated_by': ctx.printedBy,
    'organization': ctx.orgName,
    'meta': {for (final m in t.meta) m.$1: m.$2},
    'summary': {for (final s in t.summary) s.$1: s.$2},
    'columns': [
      for (final col in t.columns) {'key': col.key, 'label': col.label, 'type': col.type.name}
    ],
    'rows': [
      for (final r in t.rows)
        {for (var j = 0; j < t.columns.length; j++) t.columns[j].key: enc(j < r.length ? r[j] : null)}
    ],
  };
  return Uint8List.fromList(utf8.encode(const JsonEncoder.withIndent('  ').convert(data)));
}

String _h(String s) =>
    s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;').replaceAll('"', '&quot;').replaceAll('\n', '<br>');

String _css(int argb) => '#${(argb & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';

Future<Uint8List> buildHtml(ExportTable t, PrintConfig c, PrintContext ctx) async {
  final logo = await logoBytes(c);
  final accent = _css(c.accent);
  String d(String s) => digitsOf(s, c.eastern);
  final title = titleOf(t, c);
  final family = switch (c.font) {
    'kufi' => "'Noto Kufi Arabic', 'Sakkal Majalla', Tahoma, sans-serif",
    'sans' => "'Noto Sans Arabic', Arial, Tahoma, sans-serif",
    _ => "'Noto Naskh Arabic', 'Traditional Arabic', 'Simplified Arabic', Tahoma, serif",
  };
  final gf = switch (c.font) {
    'kufi' => 'Noto+Kufi+Arabic:wght@400;700',
    'sans' => 'Noto+Sans+Arabic:wght@400;700',
    _ => 'Noto+Naskh+Arabic:wght@400;700',
  };
  final landscape = c.landscapeFor(t.columns.length + (c.rowNumbers ? 1 : 0));
  final headBg = switch (c.headerFill) { 'gray' => '#e4e7eb', 'none' => 'transparent', _ => accent };
  final headInk = c.headerFill == 'accent' ? '#fff' : '#1f2933';
  final border = switch (c.borders) {
    'none' => 'td,th{border:0}',
    'horizontal' => 'td,th{border:0;border-bottom:1px solid #cbd2d9}',
    _ => 'td,th{border:1px solid #cbd2d9}',
  };
  final logoTag = logo == null
      ? ''
      : '<img class="logo" src="data:image/${imageExt(logo)};base64,${base64Encode(logo)}" alt="">';
  final lines = c.orgLines.where((l) => l.trim().isNotEmpty).toList();
  final org = [
    for (var i = 0; i < lines.length; i++) '<div class="${i == 0 ? 'o1' : 'o2'}">${_h(lines[i])}</div>',
  ].join();
  final meta = [
    if (c.showRef) '<div>الرقم: ${_h(d('${c.refPrefix}/${ctx.ref}'))}</div>',
    if (c.showDate) '<div>التاريخ: ${_h(d(fmtDateBy(ctx.at, c.dateStyle)))}</div>',
  ].join();
  final cells = switch (c.logoPos) {
    'center' => '<div class="h1">$org</div><div class="h2">$logoTag</div><div class="h3">$meta</div>',
    'left' => '<div class="h1">$org</div><div class="h3">$meta</div><div class="h2">$logoTag</div>',
    _ => '<div class="h1 row">$logoTag<div>$org</div></div><div class="h3">$meta</div>',
  };
  final cols = t.columns;
  final groupIdx = c.groupBy.isEmpty ? -1 : cols.indexWhere((x) => x.key == c.groupBy);

  String tableOf(List<List<Object?>> rows, int startNo) {
    final b = StringBuffer('<table><thead><tr>');
    if (c.rowNumbers) b.write('<th class="n">ت</th>');
    for (final col in cols) {
      b.write('<th>${_h(col.label)}</th>');
    }
    b.write('</tr></thead><tbody>');
    for (var i = 0; i < rows.length; i++) {
      final r = rows[i];
      b.write('<tr>');
      if (c.rowNumbers) b.write('<td class="n">${_h(d('${startNo + i}'))}</td>');
      for (var j = 0; j < cols.length; j++) {
        final cls = cols[j].numeric || cols[j].type == ColType.date ? ' class="n"' : (cols[j].type == ColType.long ? ' class="l"' : '');
        b.write('<td$cls>${_h(cellText(j < r.length ? r[j] : null, cols[j].type, dateStyle: c.dateStyle, eastern: c.eastern))}</td>');
      }
      b.write('</tr>');
    }
    b.write('</tbody>');
    if (c.totals) {
      final sub = ExportTable(sourceId: t.sourceId, title: '', columns: cols, rows: rows);
      if (sub.hasTotals) {
        var labelled = false;
        b.write('<tfoot><tr>');
        if (c.rowNumbers) b.write('<td></td>');
        for (var j = 0; j < cols.length; j++) {
          final tot = sub.total(j);
          if (tot != null) {
            b.write('<td class="n">${_h(cellText(tot, cols[j].type, eastern: c.eastern))}</td>');
          } else if (!labelled && !cols[j].numeric) {
            b.write('<td>المجموع</td>');
            labelled = true;
          } else {
            b.write('<td></td>');
          }
        }
        b.write('</tr></tfoot>');
      }
    }
    b.write('</table>');
    return b.toString();
  }

  final body = StringBuffer();
  if (t.rows.isEmpty) {
    body.write('<p class="empty">لا سجلات مطابقة</p>');
  } else if (groupIdx < 0) {
    body.write(tableOf(t.rows, 1));
  } else {
    final groups = <String, List<List<Object?>>>{};
    for (final r in t.rows) {
      final k = cellText(groupIdx < r.length ? r[groupIdx] : null, cols[groupIdx].type, dateStyle: c.dateStyle);
      groups.putIfAbsent(k.isEmpty ? '—' : k, () => []).add(r);
    }
    var no = 1;
    for (final e in groups.entries) {
      body.write('<h3 class="grp">${_h(d('${cols[groupIdx].label}: ${e.key} (${e.value.length})'))}</h3>');
      body.write(tableOf(e.value, no));
      no += e.value.length;
    }
  }

  final sub = [if (c.subtitle.trim().isNotEmpty) c.subtitle.trim(), if (c.showSection && t.section.isNotEmpty) t.section].join(' · ');
  final metaBox = c.showMeta && t.meta.isNotEmpty
      ? '<div class="meta">${t.meta.map((m) => '<span><b>${_h(m.$1)}:</b> ${_h(d(m.$2))}</span>').join()}</div>'
      : '';
  final summary = c.showSummary && t.summary.isNotEmpty
      ? '<div class="sum">${t.summary.map((s) => '<div><strong>${_h(d(s.$2))}</strong><span>${_h(s.$1)}</span></div>').join()}</div>'
      : '';
  final notes = c.notes.trim().isEmpty ? '' : '<h3 class="notes">ملاحظات</h3><p>${_h(c.notes.trim())}</p>';
  final sigs = c.showSignatures && c.signatures.isNotEmpty
      ? '<div class="sig">${c.signatures.map((s) => '<div><b>${_h(s.title)}</b><span>${_h(s.name)}</span><i></i><small>التوقيع</small></div>').join()}</div>'
      : '';
  final cover = !c.cover
      ? ''
      : '<section class="cover"><div class="bar"></div>${logo == null ? '' : '<img class="clogo" src="data:image/${imageExt(logo)};base64,${base64Encode(logo)}" alt="">'}'
          '${lines.map((l) => '<div class="o2">${_h(l)}</div>').join()}<h1 class="ct">${_h(title)}</h1>'
          '${c.subtitle.trim().isEmpty ? '' : '<div class="cs">${_h(c.subtitle.trim())}</div>'}'
          '<div class="cm">${_h(d([if (c.showRef) 'الرقم: ${c.refPrefix}/${ctx.ref}', 'التاريخ: ${fmtDateBy(ctx.at, c.dateStyle)}', 'عدد السجلات: ${t.rows.length}'].join('   ·   ')))}</div>'
          '${c.coverNote.trim().isEmpty ? '' : '<p class="cn">${_h(c.coverNote.trim())}</p>'}<div class="bar"></div></section>';
  final wm = c.watermark.trim().isEmpty ? '' : '<div class="wm">${_h(c.watermark.trim())}</div>';
  final footer = [
    if (c.footerText.trim().isNotEmpty) _h(c.footerText.trim()),
    if (c.confidential.trim().isNotEmpty) '<b>${_h(c.confidential.trim())}</b>',
    if (c.showPrintedBy) _h(d('طبعه: ${ctx.printedBy} · ${fmtDateBy(ctx.at, c.dateStyle)}')),
  ].join(' · ');
  final headerLine = switch (c.headerLine) {
    'double' => 'border-bottom:4px double $accent',
    'single' => 'border-bottom:2px solid $accent',
    _ => 'border-bottom:0',
  };

  final html = '''<!doctype html>
<html lang="ar" dir="rtl"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>${_h(title)}</title>
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=$gf&display=swap">
<style>
@page{size:${c.paper} ${landscape ? 'landscape' : 'portrait'};margin:${c.marginMm}mm}
*{box-sizing:border-box}
body{font-family:$family;font-size:${c.fontSize + 2}px;color:#1f2933;margin:0;background:#f5f5f2}
.page{max-width:${landscape ? 1180 : 860}px;margin:24px auto;background:#fff;padding:28px 32px;box-shadow:0 2px 14px rgba(0,0,0,.08);position:relative}
header{display:flex;align-items:center;gap:14px;padding-bottom:10px;margin-bottom:14px;$headerLine}
header .h1{flex:1}.row{display:flex;align-items:center;gap:12px}.h2{flex:0 0 auto}.h3{flex:1;text-align:left;color:#66707a;font-size:.92em}
.logo{height:${c.logoSize}px;width:auto}.o1{font-weight:700;font-size:1.12em}.o2{color:#66707a}
h1.title{color:$accent;text-align:center;margin:6px 0 2px;font-size:1.6em}.sub{text-align:center;color:#66707a;margin-bottom:12px}
.meta{background:${_css(c.accent)}11;border:1px solid ${_css(c.accent)}55;padding:6px 10px;margin-bottom:10px;display:flex;flex-wrap:wrap;gap:6px 18px;font-size:.92em}
.sum{display:flex;gap:8px;margin-bottom:12px}.sum div{flex:1;border:1px solid #cbd2d9;border-top:3px solid $accent;text-align:center;padding:6px}
.sum strong{display:block;color:$accent;font-size:1.4em}.sum span{color:#66707a;font-size:.85em}
table{width:100%;border-collapse:collapse;font-size:.92em}$border
th{background:$headBg;color:$headInk;padding:${c.cellPadding + 2}px 6px;${c.headerFill == 'none' ? 'border-bottom:2px solid $accent;' : ''}}
td{padding:${c.cellPadding + 1}px 6px;vertical-align:middle}td.n,th.n{text-align:center;white-space:nowrap}td.l{white-space:pre-wrap}
${c.zebra ? 'tbody tr:nth-child(even){background:${_css(c.accent)}12}' : ''}
tfoot td{font-weight:700;background:${_css(c.accent)}22;border-top:2px solid $accent}
thead{display:table-header-group}tr{page-break-inside:avoid}
h3.grp{margin:14px 0 4px;padding-right:8px;border-right:4px solid $accent;font-size:1.05em}
h3.notes{color:$accent;margin:16px 0 4px}.empty{text-align:center;color:#66707a;padding:30px}
.sig{display:flex;gap:16px;margin-top:40px;text-align:center}.sig div{flex:1;display:flex;flex-direction:column;gap:4px}
.sig span{color:#66707a;min-height:1.2em}.sig i{display:block;margin:34px auto 2px;width:70%;border-bottom:1px solid #1f2933}.sig small{color:#66707a}
footer{margin-top:22px;padding-top:6px;border-top:1px solid #cbd2d9;color:#66707a;font-size:.82em;text-align:center}
.wm{position:fixed;top:45%;left:0;right:0;text-align:center;font-size:110px;font-weight:700;color:$accent;opacity:${c.watermarkOpacity};transform:rotate(-30deg);pointer-events:none;z-index:0}
.cover{min-height:92vh;display:flex;flex-direction:column;align-items:center;justify-content:center;gap:10px;page-break-after:always;text-align:center}
.cover .bar{align-self:stretch;height:8px;background:$accent}.clogo{height:${c.logoSize * 2}px;margin:24px 0}
.ct{color:$accent;font-size:2.4em;margin:20px 0 4px}.cs{font-size:1.3em}.cm{color:#66707a;margin-top:12px}.cn{max-width:70%}
.print{position:fixed;top:12px;left:12px;background:$accent;color:#fff;border:0;border-radius:8px;padding:8px 16px;font:inherit;cursor:pointer}
@media print{body{background:#fff}.page{box-shadow:none;margin:0;padding:0;max-width:none}.print{display:none}}
</style></head>
<body>
<button class="print" onclick="window.print()">طباعة</button>
$wm
<div class="page">
$cover
<header>$cells</header>
<h1 class="title">${_h(title)}</h1>
${sub.isEmpty ? '' : '<div class="sub">${_h(sub)}</div>'}
$metaBox
$summary
$body
$notes
$sigs
<footer>$footer</footer>
</div>
</body></html>
''';
  return Uint8List.fromList(utf8.encode(html));
}
