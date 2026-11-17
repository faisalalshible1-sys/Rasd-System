// معاينة حية لصفحة الطباعة داخل المنظومة: تُرسم بمقاسات الورق نفسها بالنقطة، وبالخطوط المضمّنة نفسها،
// فتطابق PDF في الترويسة والعنوان والجدول والتذييل والعلامة المائية (الصفحة الأولى).

import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'model.dart';

/// أبعاد الورق بالنقطة (عمودياً).
Size paperSize(String p) => switch (p) {
      'A3' => const Size(842, 1191),
      'A5' => const Size(420, 595),
      'Letter' => const Size(612, 792),
      'Legal' => const Size(612, 1008),
      _ => const Size(595, 842),
    };

String previewFamily(String font) => switch (font) {
      'kufi' => 'PrintKufi',
      'sans' => 'PrintSans',
      _ => 'PrintNaskh',
    };

class PagePreview extends StatelessWidget {
  const PagePreview({super.key, required this.config, required this.table, required this.context0, this.maxRows = 14, this.cover = false});

  final PrintConfig config;
  final ExportTable table;
  final PrintContext context0;
  final int maxRows;

  /// معاينة صفحة الغلاف بدل الصفحة الأولى.
  final bool cover;

  @override
  Widget build(BuildContext context) {
    final c = config;
    final cols = table.columns.length + (c.rowNumbers ? 1 : 0);
    final base = paperSize(c.paper);
    final land = c.landscapeFor(cols);
    final size = land ? Size(base.height, base.width) : base;
    final margin = c.marginMm * 2.835;
    return AspectRatio(
      aspectRatio: size.width / size.height,
      child: FittedBox(
        fit: BoxFit.contain,
        child: Container(
          width: size.width,
          height: size.height,
          decoration: BoxDecoration(color: Colors.white, boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.18), blurRadius: 14, offset: const Offset(0, 4))]),
          child: DefaultTextStyle(
            style: TextStyle(fontFamily: previewFamily(c.font), fontFamilyFallback: const ['PrintSans'], fontSize: c.fontSize, color: const Color(0xFF1F2933), height: 1.35),
            child: Directionality(
              textDirection: TextDirection.rtl,
              child: Stack(children: [
                if (c.watermark.trim().isNotEmpty)
                  Positioned.fill(
                    child: Center(
                      child: Transform.rotate(
                        angle: -math.pi / 5,
                        child: Opacity(
                          opacity: c.watermarkOpacity,
                          child: Text(c.watermark.trim(), style: TextStyle(fontSize: 84, fontWeight: FontWeight.w700, color: Color(c.accent))),
                        ),
                      ),
                    ),
                  ),
                Padding(padding: EdgeInsets.all(margin), child: cover ? _cover() : _page()),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  Color get _accent => Color(config.accent);
  static const _muted = Color(0xFF66707A);
  static const _rule = Color(0xFFCBD2D9);
  String _d(String s) => digitsOf(s, config.eastern);

  Widget _logo(double h) {
    final c = config;
    if (c.logo == 'none') return const SizedBox.shrink();
    if (c.logo == 'custom' && c.customLogo.isNotEmpty) {
      try {
        return Image.memory(base64Decode(c.customLogo), height: h, fit: BoxFit.contain);
      } catch (_) {}
    }
    return Image.asset(c.logo == 'banner' ? 'assets/brand/banner.png' : 'assets/brand/emblem.png', height: h, fit: BoxFit.contain);
  }

  Widget _header() {
    final c = config;
    final fs = c.fontSize;
    final lines = c.orgLines.where((l) => l.trim().isNotEmpty).toList();
    final org = Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      for (var i = 0; i < lines.length; i++)
        Text(lines[i],
            style: TextStyle(
                fontSize: i == 0 ? fs + 2 : fs,
                fontWeight: i == 0 || i == lines.length - 1 ? FontWeight.w700 : FontWeight.w400,
                color: i == 0 ? const Color(0xFF1F2933) : _muted)),
    ]);
    final meta = Column(crossAxisAlignment: CrossAxisAlignment.end, mainAxisSize: MainAxisSize.min, children: [
      if (c.showRef) Text(_d('الرقم: ${c.refPrefix}/${context0.ref}'), style: TextStyle(fontSize: fs - 0.5, color: _muted)),
      if (c.showDate) Text(_d('التاريخ: ${fmtDateBy(context0.at, c.dateStyle)}'), style: TextStyle(fontSize: fs - 0.5, color: _muted)),
    ]);
    final hasLogo = c.logo != 'none';
    return Column(children: [
      Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        if (c.logoPos == 'right' && hasLogo) ...[_logo(c.logoSize), const SizedBox(width: 10)],
        Expanded(child: org),
        if (c.logoPos == 'center' && hasLogo) ...[const SizedBox(width: 10), _logo(c.logoSize), const SizedBox(width: 10)],
        Expanded(child: meta),
        if (c.logoPos == 'left' && hasLogo) ...[const SizedBox(width: 10), _logo(c.logoSize)],
      ]),
      const SizedBox(height: 6),
      if (c.headerLine == 'double') ...[
        Container(height: 2, color: _accent),
        const SizedBox(height: 1.5),
        Container(height: 0.6, color: _accent),
      ] else if (c.headerLine == 'single')
        Container(height: 1.2, color: _accent),
      const SizedBox(height: 10),
    ]);
  }

  Widget _footer() {
    final c = config;
    final fs = c.fontSize;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Container(height: 0.6, color: _rule),
      const SizedBox(height: 5),
      Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            if (c.footerText.trim().isNotEmpty) Text(c.footerText.trim(), style: TextStyle(fontSize: fs - 1.5, color: _muted)),
            if (c.confidential.trim().isNotEmpty)
              Text(c.confidential.trim(), style: TextStyle(fontSize: fs - 1.5, color: _accent, fontWeight: FontWeight.w700)),
          ]),
        ),
        if (c.pageNumbers) Text(_d('صفحة 1 من 1'), style: TextStyle(fontSize: fs - 1, color: _muted)),
        Expanded(
          child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            if (c.showPrintedBy)
              Flexible(
                child: Text(_d('طبعه: ${context0.printedBy} · ${fmtDateBy(context0.at, c.dateStyle)}'),
                    textAlign: TextAlign.left, style: TextStyle(fontSize: fs - 2, color: _muted)),
              ),
            if (c.qr) ...[
              const SizedBox(width: 6),
              SizedBox(width: 34, height: 34, child: QrImageView(data: verifyText(table, c, context0), padding: EdgeInsets.zero)),
            ],
          ]),
        ),
      ]),
    ]);
  }

  Widget _page() {
    final c = config;
    final fs = c.fontSize;
    final t = table;
    final title = titleOf(t, c);
    final sub = [if (c.subtitle.trim().isNotEmpty) c.subtitle.trim(), if (c.showSection && t.section.isNotEmpty) t.section].join(' · ');
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _header(),
      Text(title, textAlign: TextAlign.center, style: TextStyle(fontSize: fs + 6, fontWeight: FontWeight.w700, color: _accent)),
      if (sub.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 3), child: Text(sub, textAlign: TextAlign.center, style: TextStyle(fontSize: fs + 0.5, color: _muted))),
      const SizedBox(height: 10),
      if (c.showMeta && t.meta.isNotEmpty) ...[
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(color: _accent.withValues(alpha: 0.06), border: Border.all(color: _accent.withValues(alpha: 0.35), width: 0.6)),
          child: Wrap(spacing: 18, runSpacing: 3, children: [
            for (final (k, v) in t.meta)
              Text.rich(TextSpan(children: [
                TextSpan(text: '$k: ', style: TextStyle(fontSize: fs - 0.5, fontWeight: FontWeight.w700)),
                TextSpan(text: _d(v), style: TextStyle(fontSize: fs - 0.5, color: _muted)),
              ])),
          ]),
        ),
        const SizedBox(height: 8),
      ],
      if (c.showSummary && t.summary.isNotEmpty) ...[
        Row(children: [
          for (var i = 0; i < t.summary.length; i++) ...[
            if (i > 0) const SizedBox(width: 6),
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
                decoration: BoxDecoration(
                  border: Border(
                    top: BorderSide(color: _accent, width: 2),
                    bottom: const BorderSide(color: _rule, width: 0.6),
                    left: const BorderSide(color: _rule, width: 0.6),
                    right: const BorderSide(color: _rule, width: 0.6),
                  ),
                ),
                child: Column(children: [
                  Text(_d(t.summary[i].$2), style: TextStyle(fontSize: fs + 4, fontWeight: FontWeight.w700, color: _accent)),
                  Text(t.summary[i].$1, textAlign: TextAlign.center, style: TextStyle(fontSize: fs - 1.5, color: _muted)),
                ]),
              ),
            ),
          ],
        ]),
        const SizedBox(height: 10),
      ],
      Expanded(child: ClipRect(child: SingleChildScrollView(physics: const NeverScrollableScrollPhysics(), child: _table()))),
      if (c.showSignatures && c.signatures.isNotEmpty) ...[
        const SizedBox(height: 10),
        Row(children: [
          for (final s in c.signatures)
            Expanded(
              child: Column(children: [
                Text(s.title, style: const TextStyle(fontWeight: FontWeight.w700)),
                Text(s.name.isEmpty ? ' ' : s.name, style: const TextStyle(color: _muted)),
                const SizedBox(height: 18),
                Container(width: 110, height: 0.6, color: const Color(0xFF1F2933)),
                Text('التوقيع', style: TextStyle(fontSize: fs - 2, color: _muted)),
              ]),
            ),
        ]),
        const SizedBox(height: 8),
      ],
      _footer(),
    ]);
  }

  Widget _table() {
    final c = config;
    final fs = c.fontSize;
    final t = table;
    if (t.rows.isEmpty) {
      return Padding(padding: const EdgeInsets.all(24), child: Center(child: Text('لا سجلات مطابقة', style: TextStyle(color: _muted, fontSize: fs + 1))));
    }
    final cols = t.columns;
    final headFill = switch (c.headerFill) { 'gray' => const Color(0xFFE4E7EB), 'none' => Colors.white, _ => _accent };
    final headInk = c.headerFill == 'accent' ? Colors.white : const Color(0xFF1F2933);
    final widths = <int, TableColumnWidth>{
      if (c.rowNumbers) 0: const FlexColumnWidth(0.35),
      for (var j = 0; j < cols.length; j++)
        j + (c.rowNumbers ? 1 : 0): FlexColumnWidth(cols[j].weight),
    };
    Widget cell(String s, {bool head = false, bool center = false, bool bold = false}) => Padding(
          padding: EdgeInsets.symmetric(horizontal: c.cellPadding + 1, vertical: c.cellPadding),
          child: Text(s,
              textAlign: head || center ? TextAlign.center : TextAlign.right,
              style: TextStyle(
                  fontSize: head ? fs - 0.5 : fs - 1, fontWeight: head || bold ? FontWeight.w700 : FontWeight.w400, color: head ? headInk : null)),
        );
    final border = switch (c.borders) {
      'none' => null,
      'horizontal' => const TableBorder(horizontalInside: BorderSide(color: _rule, width: 0.5), bottom: BorderSide(color: _rule, width: 0.5)),
      _ => TableBorder.all(color: _rule, width: 0.5),
    };
    final shown = t.rows.take(maxRows).toList();
    final rows = <TableRow>[
      TableRow(
        decoration: BoxDecoration(color: headFill, border: c.headerFill == 'none' ? Border(bottom: BorderSide(color: _accent, width: 1.2)) : null),
        children: [if (c.rowNumbers) cell('ت', head: true), for (final col in cols) cell(col.label, head: true)],
      ),
      for (var i = 0; i < shown.length; i++)
        TableRow(
          decoration: c.zebra && i.isOdd ? BoxDecoration(color: _accent.withValues(alpha: 0.07)) : null,
          children: [
            if (c.rowNumbers) cell(_d('${i + 1}'), center: true),
            for (var j = 0; j < cols.length; j++)
              cell(cellText(j < shown[i].length ? shown[i][j] : null, cols[j].type, dateStyle: c.dateStyle, eastern: c.eastern),
                  center: cols[j].numeric || cols[j].type == ColType.date),
          ],
        ),
    ];
    if (c.totals && t.hasTotals) {
      var labelled = false;
      rows.add(TableRow(
        decoration: BoxDecoration(color: _accent.withValues(alpha: 0.16), border: Border(top: BorderSide(color: _accent))),
        children: [
          if (c.rowNumbers) cell(''),
          for (var j = 0; j < cols.length; j++)
            () {
              final tot = t.total(j);
              if (tot != null) return cell(cellText(tot, cols[j].type, eastern: c.eastern), center: true, bold: true);
              if (!labelled && !cols[j].numeric) {
                labelled = true;
                return cell('المجموع', bold: true);
              }
              return cell('');
            }(),
        ],
      ));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (c.groupBy.isNotEmpty && cols.any((x) => x.key == c.groupBy))
        Container(
          margin: const EdgeInsets.only(bottom: 3),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(border: Border(right: BorderSide(color: _accent, width: 3))),
          child: Text('مجمّعة حسب: ${cols.firstWhere((x) => x.key == c.groupBy).label}', style: TextStyle(fontSize: fs + 0.5, fontWeight: FontWeight.w700)),
        ),
      Table(border: border, columnWidths: widths, defaultVerticalAlignment: TableCellVerticalAlignment.middle, children: rows),
      if (t.rows.length > shown.length)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(_d('… و${t.rows.length - shown.length} سجلاً آخر في الصفحات التالية'), textAlign: TextAlign.center, style: TextStyle(fontSize: fs - 1.5, color: _muted)),
        ),
      if (c.notes.trim().isNotEmpty) ...[
        const SizedBox(height: 10),
        Text('ملاحظات', style: TextStyle(fontSize: fs + 0.5, fontWeight: FontWeight.w700, color: _accent)),
        Text(c.notes.trim(), style: TextStyle(fontSize: fs - 0.5)),
      ],
    ]);
  }

  Widget _cover() {
    final c = config;
    final fs = c.fontSize;
    return Column(children: [
      Container(height: 6, color: _accent),
      const Spacer(),
      if (c.logo != 'none') _logo(c.logoSize * 2),
      const SizedBox(height: 16),
      for (final l in c.orgLines.where((l) => l.trim().isNotEmpty)) Text(l, style: TextStyle(fontSize: fs + 2, color: _muted)),
      const SizedBox(height: 28),
      Text(titleOf(table, c), textAlign: TextAlign.center, style: TextStyle(fontSize: fs + 16, fontWeight: FontWeight.w700, color: _accent)),
      if (c.subtitle.trim().isNotEmpty) Text(c.subtitle.trim(), textAlign: TextAlign.center, style: TextStyle(fontSize: fs + 4)),
      if (table.section.isNotEmpty) Text(table.section, style: TextStyle(fontSize: fs + 2, color: _muted)),
      const SizedBox(height: 20),
      Text(
        _d([if (c.showRef) 'الرقم: ${c.refPrefix}/${context0.ref}', 'التاريخ: ${fmtDateBy(context0.at, c.dateStyle)}', 'عدد السجلات: ${table.rows.length}']
            .join('   ·   ')),
        style: const TextStyle(color: _muted),
      ),
      if (c.coverNote.trim().isNotEmpty)
        Padding(padding: const EdgeInsets.fromLTRB(40, 18, 40, 0), child: Text(c.coverNote.trim(), textAlign: TextAlign.center, style: TextStyle(fontSize: fs + 1))),
      const Spacer(flex: 2),
      if (c.confidential.trim().isNotEmpty) Text(c.confidential.trim(), style: TextStyle(fontWeight: FontWeight.w700, color: _accent)),
      const SizedBox(height: 8),
      Container(height: 6, color: _accent),
    ]);
  }
}
