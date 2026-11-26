import 'dart:convert';

import 'package:excel/excel.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';

import '../boq_import.dart';
import 'doc_files.dart' show extOf;

// =====================================================================
// قراءة ملف المقايسة للاستيراد (الإصدار 1.5.0): Excel (xlsx) وCSV على الجهاز نفسه،
// وPDF عبر الدالة boq-extract التي تعيد نصوص الصفحات بمواضعها (يكوّن منها boq_import.dart الصفوف).
// =====================================================================

/// حد ملف PDF المرسل للاستخراج، وحد ملف Excel.
const int maxBoqPdfBytes = 10 * 1024 * 1024;
const int maxBoqSheetBytes = 20 * 1024 * 1024;

/// الملف المختار: اسمه ونوعه وبايتاته.
class BoqSource {
  BoqSource(this.name, this.ext, this.bytes);

  final String name;
  final String ext;
  final Uint8List bytes;

  bool get isPdf => ext == 'pdf';
}

/// ورقة من ملف Excel بصفوفها نصوصاً.
class BoqSheetRows {
  BoqSheetRows(this.name, this.rows);

  final String name;
  final List<List<String>> rows;
}

Future<BoqSource?> pickBoqSource() async {
  final picked = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: const ['xlsx', 'csv', 'pdf', 'xls']);
  if (picked.isEmpty) return null;
  final f = picked.first;
  final ext = extOf(f.name);
  if (ext == 'xls') {
    throw StateError('صيغة Excel القديمة (xls) لا تُقرأ. افتح الملف في Excel واحفظه بصيغة xlsx ثم أعد المحاولة.');
  }
  final bytes = await f.readAsBytes();
  final limit = ext == 'pdf' ? maxBoqPdfBytes : maxBoqSheetBytes;
  if (bytes.length > limit) {
    throw StateError('الملف «${f.name}» أكبر من ${limit ~/ (1024 * 1024)} ميجابايت. قسّم المقايسة أو احذف الصور منها ثم أعد المحاولة.');
  }
  if (bytes.isEmpty) throw StateError('الملف «${f.name}» فارغ.');
  return BoqSource(f.name, ext, bytes);
}

String _cellText(CellValue? v) {
  if (v == null) return '';
  // المعادلات بلا نتيجة محفوظة في المكتبة: تُترك فارغة ويُحسب الإجمالي من الكمية والسعر
  if (v is FormulaCellValue) return '';
  if (v is DoubleCellValue) {
    final d = v.value;
    return d == d.roundToDouble() ? d.toInt().toString() : d.toString();
  }
  return v.toString().trim();
}

/// أوراق ملف xlsx، الأكثر صفوفاً أولاً.
List<BoqSheetRows> readXlsx(Uint8List bytes) {
  final Excel book;
  try {
    book = Excel.decodeBytes(bytes);
  } catch (_) {
    throw StateError('تعذّرت قراءة ملف Excel. تأكد أنه بصيغة xlsx وغير محمي بكلمة مرور.');
  }
  final out = <BoqSheetRows>[];
  for (final e in book.tables.entries) {
    final rows = <List<String>>[
      for (final r in e.value.rows) [for (final c in r) _cellText(c?.value)],
    ];
    while (rows.isNotEmpty && rows.last.every((c) => c.isEmpty)) {
      rows.removeLast();
    }
    if (rows.isNotEmpty) out.add(BoqSheetRows(e.key, rows));
  }
  out.sort((a, b) => b.rows.length.compareTo(a.rows.length));
  return out;
}

/// صفوف CSV (الفاصلة أو الفاصلة المنقوطة أو Tab، مع علامات الاقتباس).
List<List<String>> readCsv(Uint8List bytes) {
  var text = utf8.decode(bytes, allowMalformed: true);
  if (text.startsWith('﻿')) text = text.substring(1);
  final first = text.split('\n').first;
  final sep = [';', '\t', ','].reduce((a, b) => first.split(a).length >= first.split(b).length ? a : b);
  final rows = <List<String>>[];
  var row = <String>[];
  final cell = StringBuffer();
  var quoted = false;
  for (var i = 0; i < text.length; i++) {
    final ch = text[i];
    if (quoted) {
      if (ch == '"') {
        if (i + 1 < text.length && text[i + 1] == '"') {
          cell.write('"');
          i++;
        } else {
          quoted = false;
        }
      } else {
        cell.write(ch);
      }
    } else if (ch == '"') {
      quoted = true;
    } else if (ch == sep) {
      row.add(cell.toString().trim());
      cell.clear();
    } else if (ch == '\n' || ch == '\r') {
      if (ch == '\r' && i + 1 < text.length && text[i + 1] == '\n') i++;
      row.add(cell.toString().trim());
      cell.clear();
      rows.add(row);
      row = <String>[];
    } else {
      cell.write(ch);
    }
  }
  if (cell.isNotEmpty || row.isNotEmpty) {
    row.add(cell.toString().trim());
    rows.add(row);
  }
  return [for (final r in rows) if (r.any((c) => c.isNotEmpty)) r];
}

/// صفحات PDF كما تعيدها الدالة boq-extract: {pages: [{items: [{s, x, y, w, h}]}], total, truncated}.
({List<List<PdfRun>> pages, int total, bool truncated}) parseExtractReply(Object? data) {
  final m = data is Map ? data : (data is String ? jsonDecode(data) as Map : const {});
  if (m['error'] is String) throw StateError(m['error'] as String);
  final pages = [
    for (final p in (m['pages'] is List ? m['pages'] as List : const []))
      [
        if (p is Map && p['items'] is List)
          for (final it in p['items'] as List)
            if (it is Map) PdfRun.fromJson(Map<String, dynamic>.from(it)),
      ],
  ];
  final total = m['total'] is num ? (m['total'] as num).toInt() : pages.length;
  return (pages: pages, total: total, truncated: m['truncated'] == true);
}
