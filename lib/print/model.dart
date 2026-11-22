// =====================================================================
// الطباعة والتصدير: الصيغ، وجدول البيانات المستخرج، وإعدادات قالب الصفحة.
// المحركات (PDF وWord وExcel…) تقرأ ExportTable وPrintConfig فقط، فتتطابق مخرجاتها.
// =====================================================================

import 'package:flutter/material.dart' show IconData, Icons;

/// صيغ الاستخراج.
enum ExportFormat { pdf, docx, xlsx, csv, html, json }

extension ExportFormatX on ExportFormat {
  String get label => switch (this) {
        ExportFormat.pdf => 'PDF',
        ExportFormat.docx => 'Word',
        ExportFormat.xlsx => 'Excel',
        ExportFormat.csv => 'CSV',
        ExportFormat.html => 'صفحة ويب HTML',
        ExportFormat.json => 'JSON',
      };

  String get hint => switch (this) {
        ExportFormat.pdf => 'للطباعة والأرشفة بتصميم القالب كاملاً',
        ExportFormat.docx => 'للتعديل في Microsoft Word',
        ExportFormat.xlsx => 'للتحليل والفرز والمعادلات',
        ExportFormat.csv => 'نص مفصول بفواصل لأي برنامج جداول',
        ExportFormat.html => 'تُفتح في المتصفح وتُطبع منه',
        ExportFormat.json => 'بيانات منظّمة لأنظمة أخرى',
      };

  String get ext => switch (this) {
        ExportFormat.pdf => 'pdf',
        ExportFormat.docx => 'docx',
        ExportFormat.xlsx => 'xlsx',
        ExportFormat.csv => 'csv',
        ExportFormat.html => 'html',
        ExportFormat.json => 'json',
      };

  String get mime => switch (this) {
        ExportFormat.pdf => 'application/pdf',
        ExportFormat.docx => 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
        ExportFormat.xlsx => 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        ExportFormat.csv => 'text/csv',
        ExportFormat.html => 'text/html',
        ExportFormat.json => 'application/json',
      };

  IconData get icon => switch (this) {
        ExportFormat.pdf => Icons.picture_as_pdf_rounded,
        ExportFormat.docx => Icons.description_rounded,
        ExportFormat.xlsx => Icons.table_view_rounded,
        ExportFormat.csv => Icons.view_list_rounded,
        ExportFormat.html => Icons.language_rounded,
        ExportFormat.json => Icons.data_object_rounded,
      };

  /// هل تتبع الصيغة تصميم القالب (الشعار والترويسة والتذييل)؟
  bool get styled => this == ExportFormat.pdf || this == ExportFormat.docx || this == ExportFormat.html;
}

ExportFormat? exportFormatOf(String s) {
  for (final f in ExportFormat.values) {
    if (f.name == s) return f;
  }
  return null;
}

/// نوع قيمة العمود (يحدد المحاذاة والتنسيق والمجاميع).
enum ColType { text, long, number, money, percent, date }

class ExportColumn {
  const ExportColumn(this.key, this.label, {this.type = ColType.text, this.flex = 1, this.on = true, this.formula, this.sum = true});

  final String key;
  final String label;
  final ColType type;

  /// العرض النسبي في PDF وWord.
  final double flex;

  /// ظاهر افتراضياً (الأعمدة الثانوية تُختار يدوياً).
  final bool on;

  /// عمود محسوب من أعمدة أخرى، مثل {actual}-{planned}: يُحسب في التطبيق بالمعادلة نفسها،
  /// ويُكتب في Excel معادلةً حية تتغير نتيجتها إن عُدّلت القيم التي تعتمد عليها.
  final String? formula;

  /// يُجمع في صف الإجمالي (لا يُجمع مثلاً سعر الوحدة ولا كميات بوحدات مختلفة).
  final bool sum;

  bool get computed => formula != null;

  ExportColumn copyWith({String? label, bool clearFormula = false}) =>
      ExportColumn(key, label ?? this.label, type: type, flex: flex, on: on, formula: clearFormula ? null : formula, sum: sum);

  bool get numeric => type == ColType.number || type == ColType.money || type == ColType.percent;

  /// الوزن الفعلي في عرض الجدول: النص الطويل أعرض، والتاريخ والمبلغ لا يضيقان عن سطر واحد.
  double get weight => switch (type) {
        ColType.long => flex * 1.8,
        ColType.date || ColType.money => flex < 1.25 ? 1.25 : flex,
        _ => flex,
      };
}

/// بيانات مستخرجة جاهزة للكتابة بأي صيغة. القيم: نص، أو رقم، أو تاريخ، أو null.
class ExportTable {
  ExportTable({
    required this.sourceId,
    required this.title,
    this.section = '',
    required this.columns,
    required this.rows,
    this.summary = const [],
    this.meta = const [],
  });

  final String sourceId;
  final String title;

  /// القسم الذي جاء منه السجل (يظهر تحت العنوان).
  final String section;
  final List<ExportColumn> columns;
  final List<List<Object?>> rows;

  /// مؤشرات مختصرة أعلى الصفحة: (التسمية، القيمة)
  final List<(String, String)> summary;

  /// وصف ما استُخرج: (التسمية، القيمة) مثل العقد والفترة والتصفية.
  final List<(String, String)> meta;

  /// نسخة بأعمدة مختارة بترتيبها. العمود المحسوب الذي غاب أحد أعمدة معادلته يبقى بقيمته ثابتة.
  ExportTable select(List<String> keys) {
    final idx = <int>[];
    for (final k in keys) {
      final i = columns.indexWhere((c) => c.key == k);
      if (i >= 0) idx.add(i);
    }
    if (idx.isEmpty) return this;
    final picked = {for (final i in idx) columns[i].key};
    return ExportTable(
      sourceId: sourceId,
      title: title,
      section: section,
      columns: [
        for (final i in idx)
          columns[i].computed && !Formula.refs(columns[i].formula!).every(picked.contains) ? columns[i].copyWith(clearFormula: true) : columns[i]
      ],
      rows: [
        for (final r in rows) [for (final i in idx) i < r.length ? r[i] : null]
      ],
      summary: summary,
      meta: meta,
    );
  }

  /// نسخة معدّلة (من شاشة التحرير قبل التصدير).
  ExportTable copyWith({String? title, List<ExportColumn>? columns, List<List<Object?>>? rows}) => ExportTable(
        sourceId: sourceId,
        title: title ?? this.title,
        section: section,
        columns: columns ?? this.columns,
        rows: rows ?? this.rows,
        summary: summary,
        meta: meta,
      );

  /// يعيد حساب الأعمدة المحسوبة من قيم صفها، بالمعادلة نفسها التي تُكتب في Excel.
  ExportTable recompute() {
    if (!columns.any((c) => c.computed)) return this;
    final keys = [for (final c in columns) c.key];
    return copyWith(rows: [
      for (final r in rows)
        [
          for (var j = 0; j < columns.length; j++)
            columns[j].computed
                ? Formula.eval(columns[j].formula!, (k) {
                    final i = keys.indexOf(k);
                    final v = i >= 0 && i < r.length ? r[i] : null;
                    return v is num ? v : (v is String ? num.tryParse(v.replaceAll(',', '')) : null);
                  })
                : (j < r.length ? r[j] : null),
        ],
    ]);
  }

  /// مجموع عمود رقمي (null إن لم يكن رقمياً أو كان فارغاً).
  double? total(int col) {
    final c = columns[col];
    if (!c.numeric || c.type == ColType.percent || !c.sum) return null;
    var any = false;
    var s = 0.0;
    for (final r in rows) {
      final v = col < r.length ? r[col] : null;
      if (v is num) {
        s += v;
        any = true;
      }
    }
    return any ? s : null;
  }

  bool get hasTotals => columns.asMap().keys.any((i) => total(i) != null);
}

// ---------------------------------------------------------------------
// معادلات الأعمدة المحسوبة: أرقام، و{مفتاح عمود}، و+ - * /، والأقواس، وmax(أ،ب) وmin(أ،ب).
// ---------------------------------------------------------------------
class Formula {
  static final RegExp _ref = RegExp(r'\{([a-z0-9_]+)\}');

  /// مفاتيح الأعمدة التي تعتمد عليها المعادلة.
  static List<String> refs(String f) => [for (final m in _ref.allMatches(f)) m.group(1)!];

  /// النتيجة مقرّبة إلى منزلتين، أو null إن لم توجد قيمة أو كانت القسمة على صفر.
  static double? eval(String f, num? Function(String key) value) {
    final p = _Parser(f, value);
    try {
      final v = p.expr();
      p._ws();
      if (p.i < p.s.length || v == null || v.isNaN || v.isInfinite) return null;
      if (!p.sawValue && refs(f).isNotEmpty) return null;
      return (v * 100).round() / 100;
    } on FormatException {
      return null;
    }
  }

  /// المعادلة بصيغة Excel: {مفتاح} ← مرجع الخلية، وmax/min ← MAX/MIN، داخل IFERROR.
  static String toExcel(String f, String Function(String key) cell) {
    final body = f.replaceAllMapped(_ref, (m) => cell(m.group(1)!)).replaceAll('max(', 'MAX(').replaceAll('min(', 'MIN(');
    return 'IFERROR($body,"")';
  }
}

class _Parser {
  _Parser(this.s, this.value);

  final String s;
  final num? Function(String key) value;
  int i = 0;
  bool _sawValue = false;

  void _ws() {
    while (i < s.length && s[i] == ' ') {
      i++;
    }
  }

  double? expr() {
    var v = term();
    _ws();
    while (i < s.length && (s[i] == '+' || s[i] == '-')) {
      final op = s[i++];
      final r = term();
      v = v == null || r == null ? null : (op == '+' ? v + r : v - r);
      _ws();
    }
    return v;
  }

  double? term() {
    var v = factor();
    _ws();
    while (i < s.length && (s[i] == '*' || s[i] == '/')) {
      final op = s[i++];
      final r = factor();
      if (v == null || r == null) {
        v = null;
      } else if (op == '*') {
        v = v * r;
      } else {
        v = r == 0 ? null : v / r;
      }
      _ws();
    }
    return v;
  }

  double? factor() {
    _ws();
    if (i >= s.length) throw const FormatException('end');
    final c = s[i];
    if (c == '-') {
      i++;
      final v = factor();
      return v == null ? null : -v;
    }
    if (c == '(') {
      i++;
      final v = expr();
      _ws();
      if (i >= s.length || s[i] != ')') throw const FormatException(')');
      i++;
      return v;
    }
    if (c == '{') {
      final j = s.indexOf('}', i);
      if (j < 0) throw const FormatException('}');
      final key = s.substring(i + 1, j);
      i = j + 1;
      final v = value(key);
      if (v != null) _sawValue = true;
      return (v ?? 0).toDouble();
    }
    if (s.startsWith('max(', i) || s.startsWith('min(', i)) {
      final isMax = s.startsWith('max(', i);
      i += 4;
      final a = expr();
      _ws();
      if (i >= s.length || s[i] != ',') throw const FormatException(',');
      i++;
      final b = expr();
      _ws();
      if (i >= s.length || s[i] != ')') throw const FormatException(')');
      i++;
      if (a == null || b == null) return null;
      return isMax ? (a > b ? a : b) : (a < b ? a : b);
    }
    final m = RegExp(r'[0-9]+(\.[0-9]+)?').matchAsPrefix(s, i);
    if (m == null) throw FormatException('رمز غير متوقع: $c');
    i = m.end;
    return double.parse(m.group(0)!);
  }

  /// هل كانت لأي مرجع قيمة؟ (إن لم يكن، فالنتيجة فارغة لا صفر)
  bool get sawValue => _sawValue;
}

// ---------------------------------------------------------------------
// تنسيق القيم
// ---------------------------------------------------------------------
const _eastern = ['٠', '١', '٢', '٣', '٤', '٥', '٦', '٧', '٨', '٩'];

// ------------------------------------------------------------- اتجاه الأرقام داخل النص العربي
// محرك PDF لا يطبّق خوارزمية الاتجاه كاملة: يقلب ترتيب أجزاء الرقم المفصولة بـ / أو - أو : (فيظهر 2026/11/16
// كأنه 16/11/2026). لذلك يُقسَّم النص إلى كلمات، وكل جزء من أرقام أو حروف لاتينية يُرسم وحده من اليسار.

const _arabicLetters = r'؀-ٟ٭-ۯۺ-ۿݐ-ݿࢠ-ࣿﭐ-﷿ﹰ-﻿';
const _ltrChars = r'0-9A-Za-zÀ-ɏ٠-٩۰-۹';
final _arabicRe = RegExp('[$_arabicLetters]');
final _ltrRe = RegExp('[$_ltrChars]');
final _latinRe = RegExp(r'[A-Za-zÀ-ɏ]');
final _ltrSpanRe = RegExp('[$_ltrChars](?:[^\\s$_arabicLetters]*[$_ltrChars%٪])?');

/// هل في النص حرف عربي؟
bool hasArabic(String s) => _arabicRe.hasMatch(s);

/// هل في النص رقم أو حرف لاتيني؟
bool hasLtr(String s) => _ltrRe.hasMatch(s);

/// يقسم النص إلى كلمات بالترتيب المنطقي، وكل كلمة أجزاء (النص، ومن اليسار؟). الكلمة الخالية من الحروف العربية
/// جزء واحد من اليسار (2026/11/16، 7.7%، (3))، والكلمات اللاتينية المتتالية تُجمع (Hello World)، والكلمة
/// المختلطة تُقسم (ع-2026/11 ← «ع-» من اليمين و«2026/11» من اليسار).
List<List<(String, bool)>> bidiWords(String s) {
  final out = <List<(String, bool)>>[];
  for (final w in s.split(RegExp(r'\s+'))) {
    if (w.isEmpty) continue;
    final ar = hasArabic(w);
    if (!ar && hasLtr(w)) {
      // كلمات لاتينية متتالية تبقى عبارة واحدة من اليسار كما في Word والمتصفح
      final prev = out.isEmpty ? null : out.last;
      if (prev != null && prev.length == 1 && prev.first.$2 && _latinRe.hasMatch(prev.first.$1) && _latinRe.hasMatch(w)) {
        out[out.length - 1] = [('${prev.first.$1} $w', true)];
      } else {
        out.add([(w, true)]);
      }
      continue;
    }
    if (!ar || !hasLtr(w)) {
      out.add([(w, false)]);
      continue;
    }
    final parts = <(String, bool)>[];
    var i = 0;
    for (final m in _ltrSpanRe.allMatches(w)) {
      if (m.start > i) parts.add((w.substring(i, m.start), false));
      parts.add((m.group(0)!, true));
      i = m.end;
    }
    if (i < w.length) parts.add((w.substring(i), false));
    out.add(parts);
  }
  return out;
}


/// تحويل الأرقام الغربية إلى المشرقية (٠١٢…) إن طُلب.
String digitsOf(String s, bool eastern) {
  if (!eastern) return s;
  final b = StringBuffer();
  for (final ch in s.runes) {
    if (ch >= 0x30 && ch <= 0x39) {
      b.write(_eastern[ch - 0x30]);
    } else {
      b.writeCharCode(ch);
    }
  }
  return b.toString();
}

String _two(int n) => n.toString().padLeft(2, '0');

/// تاريخ بصيغة القالب: dmy (16/11/2026) أو ymd (2026/11/16) أو long (16 نوفمبر 2026).
String fmtDateBy(DateTime d, String style) {
  const months = ['يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو', 'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر'];
  return switch (style) {
    'dmy' => '${_two(d.day)}/${_two(d.month)}/${d.year}',
    'long' => '${d.day} ${months[d.month - 1]} ${d.year}',
    _ => '${d.year}/${_two(d.month)}/${_two(d.day)}',
  };
}

/// رقم بفواصل الآلاف ومنزلتين عشريتين عند الحاجة.
String fmtNumber(num v, {int decimals = 2}) {
  final neg = v < 0;
  final a = v.abs();
  final whole = a.truncate();
  final frac = a - whole;
  final ws = whole.toString();
  final b = StringBuffer();
  for (var i = 0; i < ws.length; i++) {
    if (i > 0 && (ws.length - i) % 3 == 0) b.write(',');
    b.write(ws[i]);
  }
  var out = b.toString();
  if (decimals > 0 && frac > 0.0000001) {
    final f = (frac * _pow10(decimals)).round();
    if (f >= _pow10(decimals)) {
      return fmtNumber(neg ? -(whole + 1) : whole + 1, decimals: decimals);
    }
    out = '$out.${f.toString().padLeft(decimals, '0')}';
  }
  return neg ? '-$out' : out;
}

int _pow10(int n) {
  var r = 1;
  for (var i = 0; i < n; i++) {
    r *= 10;
  }
  return r;
}

/// القيمة نصاً كما تُطبع.
String cellText(Object? v, ColType t, {String dateStyle = 'ymd', bool eastern = false}) {
  if (v == null) return '';
  final s = switch (v) {
    DateTime d => fmtDateBy(d, dateStyle),
    num n => switch (t) {
        ColType.percent => '${fmtNumber(n, decimals: 1)}%',
        ColType.money => fmtNumber(n),
        _ => fmtNumber(n, decimals: n is int ? 0 : 2),
      },
    bool b => b ? 'نعم' : 'لا',
    _ => v.toString(),
  };
  return digitsOf(s, eastern);
}

// ---------------------------------------------------------------------
// إعدادات قالب الطباعة
// ---------------------------------------------------------------------
/// توقيع في آخر الصفحة: الصفة والاسم.
class SignatureSlot {
  const SignatureSlot(this.title, [this.name = '']);

  final String title;
  final String name;

  Map<String, dynamic> toJson() => {'title': title, 'name': name};
  static SignatureSlot fromJson(Object? m) =>
      m is Map ? SignatureSlot((m['title'] ?? '').toString(), (m['name'] ?? '').toString()) : const SignatureSlot('');
}

/// كل خيارات صفحة الطباعة. تُحفظ JSON في قالب، وما لم يُذكر يأخذ قيمته الافتراضية.
class PrintConfig {
  PrintConfig({
    this.paper = 'A4',
    this.orientation = 'auto',
    this.margins = 'normal',
    this.font = 'naskh',
    this.fontSize = 10,
    this.eastern = false,
    this.dateStyle = 'ymd',
    this.accent = 0xFF8A6A1E,
    this.headerFill = 'accent',
    this.logo = 'emblem',
    this.logoPos = 'right',
    this.logoSize = 58,
    this.customLogo = '',
    List<String>? orgLines,
    this.titleMode = 'auto',
    this.customTitle = '',
    this.subtitle = '',
    this.showSection = true,
    this.showRef = true,
    this.refPrefix = 'م.ش.هـ',
    this.showDate = true,
    this.showMeta = true,
    this.showSummary = true,
    this.headerLine = 'double',
    this.rowNumbers = true,
    this.zebra = true,
    this.borders = 'all',
    this.totals = true,
    this.groupBy = '',
    this.cellPadding = 4,
    this.footerText = '',
    this.pageNumbers = true,
    this.showPrintedBy = true,
    this.confidential = '',
    this.watermark = '',
    this.watermarkOpacity = 0.07,
    this.showSignatures = false,
    List<SignatureSlot>? signatures,
    this.qr = true,
    this.cover = false,
    this.coverNote = '',
    this.notes = '',
    this.wordFont = '',
    this.repeatHeader = true,
  })  : orgLines = orgLines ?? List.of(defaultOrgLines),
        signatures = signatures ?? List.of(defaultSignatures);

  static const List<String> defaultOrgLines = [
    'صندوق التنمية وإعادة إعمار ليبيا',
    'لجنة إعادة إعمار منطقة الصابري ووسط البلاد',
    'مكتب الشؤون الهندسية',
  ];
  static const List<SignatureSlot> defaultSignatures = [
    SignatureSlot('أعدّه'),
    SignatureSlot('راجعه'),
    SignatureSlot('اعتمده', 'مدير المكتب'),
  ];

  // الصفحة
  String paper; // A3 A4 A5 Letter Legal
  String orientation; // auto portrait landscape
  String margins; // narrow normal wide
  // الخط والأرقام
  String font; // naskh kufi sans
  double fontSize;
  bool eastern;
  String dateStyle; // ymd dmy long
  // الألوان
  int accent;
  String headerFill; // accent gray none
  // الترويسة
  String logo; // emblem banner custom none
  String logoPos; // right center left
  double logoSize;
  String customLogo; // base64 (PNG أو JPEG) مصغّر
  List<String> orgLines;
  String titleMode; // auto custom
  String customTitle;
  String subtitle;
  bool showSection;
  bool showRef;
  String refPrefix;
  bool showDate;
  bool showMeta;
  bool showSummary;
  String headerLine; // double single none
  // الجدول
  bool rowNumbers;
  bool zebra;
  String borders; // all horizontal none
  bool totals;
  String groupBy; // مفتاح عمود أو فارغ
  double cellPadding;
  bool repeatHeader;
  // التذييل
  String footerText;
  bool pageNumbers;
  bool showPrintedBy;
  String confidential;
  // العلامة المائية
  String watermark;
  double watermarkOpacity;
  // التوقيعات
  bool showSignatures;
  List<SignatureSlot> signatures;
  // رمز التحقق
  bool qr;
  // صفحة الغلاف
  bool cover;
  String coverNote;
  // ملاحظات ختامية
  String notes;
  // خط Word (فارغ: حسب الخط المختار)
  String wordFont;

  /// هوامش الصفحة بالمليمتر.
  double get marginMm => switch (margins) {
        'narrow' => 9,
        'wide' => 22,
        _ => 15,
      };

  /// اتجاه الصفحة الفعلي لعدد أعمدة معيّن.
  bool landscapeFor(int columns) => switch (orientation) {
        'landscape' => true,
        'portrait' => false,
        _ => columns > 6,
      };

  /// اسم خط Word المكافئ (خطوط مثبتة في Windows).
  String get wordFontName => wordFont.trim().isNotEmpty
      ? wordFont.trim()
      : switch (font) {
          'kufi' => 'Sakkal Majalla',
          'sans' => 'Arial',
          _ => 'Simplified Arabic',
        };

  Map<String, dynamic> toJson() => {
        'paper': paper,
        'orientation': orientation,
        'margins': margins,
        'font': font,
        'fontSize': fontSize,
        'eastern': eastern,
        'dateStyle': dateStyle,
        'accent': accent,
        'headerFill': headerFill,
        'logo': logo,
        'logoPos': logoPos,
        'logoSize': logoSize,
        'customLogo': customLogo,
        'orgLines': orgLines,
        'titleMode': titleMode,
        'customTitle': customTitle,
        'subtitle': subtitle,
        'showSection': showSection,
        'showRef': showRef,
        'refPrefix': refPrefix,
        'showDate': showDate,
        'showMeta': showMeta,
        'showSummary': showSummary,
        'headerLine': headerLine,
        'rowNumbers': rowNumbers,
        'zebra': zebra,
        'borders': borders,
        'totals': totals,
        'groupBy': groupBy,
        'cellPadding': cellPadding,
        'repeatHeader': repeatHeader,
        'footerText': footerText,
        'pageNumbers': pageNumbers,
        'showPrintedBy': showPrintedBy,
        'confidential': confidential,
        'watermark': watermark,
        'watermarkOpacity': watermarkOpacity,
        'showSignatures': showSignatures,
        'signatures': [for (final s in signatures) s.toJson()],
        'qr': qr,
        'cover': cover,
        'coverNote': coverNote,
        'notes': notes,
        'wordFont': wordFont,
      };

  static PrintConfig fromJson(Object? raw) {
    final m = raw is Map ? raw : const {};
    String s(String k, String d) => m[k] is String ? m[k] as String : d;
    bool b(String k, bool d) => m[k] is bool ? m[k] as bool : d;
    double n(String k, double d, double lo, double hi) {
      final v = m[k];
      final x = v is num ? v.toDouble() : d;
      return x < lo ? lo : (x > hi ? hi : x);
    }

    String pick(String k, String d, List<String> allowed) {
      final v = s(k, d);
      return allowed.contains(v) ? v : d;
    }

    final lines = m['orgLines'];
    final sigs = m['signatures'];
    return PrintConfig(
      paper: pick('paper', 'A4', const ['A3', 'A4', 'A5', 'Letter', 'Legal']),
      orientation: pick('orientation', 'auto', const ['auto', 'portrait', 'landscape']),
      margins: pick('margins', 'normal', const ['narrow', 'normal', 'wide']),
      font: pick('font', 'naskh', const ['naskh', 'kufi', 'sans']),
      fontSize: n('fontSize', 10, 7, 16),
      eastern: b('eastern', false),
      dateStyle: pick('dateStyle', 'ymd', const ['ymd', 'dmy', 'long']),
      accent: m['accent'] is int ? m['accent'] as int : 0xFF8A6A1E,
      headerFill: pick('headerFill', 'accent', const ['accent', 'gray', 'none']),
      logo: pick('logo', 'emblem', const ['emblem', 'banner', 'custom', 'none']),
      logoPos: pick('logoPos', 'right', const ['right', 'center', 'left']),
      logoSize: n('logoSize', 58, 30, 120),
      customLogo: s('customLogo', ''),
      orgLines: lines is List ? [for (final l in lines) l.toString()].take(5).toList() : null,
      titleMode: pick('titleMode', 'auto', const ['auto', 'custom']),
      customTitle: s('customTitle', ''),
      subtitle: s('subtitle', ''),
      showSection: b('showSection', true),
      showRef: b('showRef', true),
      refPrefix: s('refPrefix', 'م.ش.هـ'),
      showDate: b('showDate', true),
      showMeta: b('showMeta', true),
      showSummary: b('showSummary', true),
      headerLine: pick('headerLine', 'double', const ['double', 'single', 'none']),
      rowNumbers: b('rowNumbers', true),
      zebra: b('zebra', true),
      borders: pick('borders', 'all', const ['all', 'horizontal', 'none']),
      totals: b('totals', true),
      groupBy: s('groupBy', ''),
      cellPadding: n('cellPadding', 4, 1, 10),
      repeatHeader: b('repeatHeader', true),
      footerText: s('footerText', ''),
      pageNumbers: b('pageNumbers', true),
      showPrintedBy: b('showPrintedBy', true),
      confidential: s('confidential', ''),
      watermark: s('watermark', ''),
      watermarkOpacity: n('watermarkOpacity', 0.07, 0.02, 0.4),
      showSignatures: b('showSignatures', false),
      signatures: sigs is List ? [for (final x in sigs) SignatureSlot.fromJson(x)].take(5).toList() : null,
      qr: b('qr', true),
      cover: b('cover', false),
      coverNote: s('coverNote', ''),
      notes: s('notes', ''),
      wordFont: s('wordFont', ''),
    );
  }

  PrintConfig copy() => PrintConfig.fromJson(toJson());
}

/// قالب محفوظ في قاعدة البيانات (الترحيل 22).
class PrintTemplate {
  const PrintTemplate({
    required this.id,
    required this.name,
    this.ownerId,
    this.isDefault = false,
    required this.config,
    this.updatedAt,
  });

  final String id;
  final String name;

  /// null: قالب عام للمكتب.
  final String? ownerId;
  final bool isDefault;
  final PrintConfig config;
  final DateTime? updatedAt;

  bool get shared => ownerId == null;

  factory PrintTemplate.fromMap(Map<String, dynamic> m) => PrintTemplate(
        id: m['id'].toString(),
        name: (m['name'] ?? '').toString(),
        ownerId: m['owner_id'] as String?,
        isDefault: m['is_default'] == true,
        config: PrintConfig.fromJson(m['config']),
        updatedAt: m['updated_at'] == null ? null : DateTime.tryParse(m['updated_at'].toString())?.toLocal(),
      );
}

/// سياق الطباعة: من طبع ومتى، والرقم المرجعي، والعنوان النهائي.
class PrintContext {
  PrintContext({required this.printedBy, required this.orgName, DateTime? at, String? ref, this.issued = false, this.verifyUrl})
      : at = at ?? DateTime.now(),
        ref = ref ?? _autoRef(at ?? DateTime.now());

  final String printedBy;
  final String orgName;
  final DateTime at;
  final String ref;

  /// رقم أصدرته قاعدة البيانات بصيغة المدير (الترحيل 23)؛ يُطبع كما هو دون بادئة الإعدادات.
  final bool issued;

  /// الرقم كما يظهر في المستند.
  String refText(PrintConfig c) => issued ? ref : '${c.refPrefix}/$ref';

  PrintContext withRef(String r) => PrintContext(printedBy: printedBy, orgName: orgName, at: at, ref: r, issued: true, verifyUrl: verifyUrl);

  /// رابط فتح النسخة الأصلية المحفوظة (الترحيل 32): يصير محتوى رمز QR بدل نص التحقق.
  final String? verifyUrl;

  PrintContext withVerify(String? url) =>
      PrintContext(printedBy: printedBy, orgName: orgName, at: at, ref: ref, issued: issued, verifyUrl: url);

  static String _autoRef(DateTime t) =>
      '${t.year}/${_two(t.month)}${_two(t.day)}/${_two(t.hour)}${_two(t.minute)}${_two(t.second)}';
}

/// العنوان الظاهر للمستند.
String titleOf(ExportTable t, PrintConfig c) =>
    c.titleMode == 'custom' && c.customTitle.trim().isNotEmpty ? c.customTitle.trim() : t.title;

/// محتوى رمز QR: رابط النسخة الأصلية المحفوظة إن حُفظت، وإلا نص التحقق.
String qrData(ExportTable t, PrintConfig c, PrintContext ctx) => ctx.verifyUrl ?? verifyText(t, c, ctx);

/// نص رمز التحقق: يكفي لمطابقة النسخة المطبوعة مع سجل التدقيق.
String verifyText(ExportTable t, PrintConfig c, PrintContext ctx) =>
    '${titleOf(t, c)} | ${ctx.refText(c)} | ${fmtDateBy(ctx.at, 'ymd')} ${_two(ctx.at.hour)}:${_two(ctx.at.minute)} | '
    '${t.rows.length} سجل | ${ctx.printedBy}';
