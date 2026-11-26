// =====================================================================
// استيراد مقايسة من ملف (الإصدار 1.5.0): من صفوف جدول (Excel أو CSV) أو من نصوص صفحات PDF بمواضعها،
// إلى بنود {رقم البند، الوصف، الوحدة، الكمية، سعر الوحدة، الإجمالي} مع ملاحظات المراجعة لكل بند.
// حساب خالص بلا واجهة ولا شبكة، ليُختبر وحده. ما يُستخرج آلياً يراجعه المستخدم ويصححه قبل الحفظ.
// =====================================================================

enum BoqCol { code, desc, unit, qty, price, total }

const Map<BoqCol, String> boqColLabels = {
  BoqCol.code: 'رقم البند',
  BoqCol.desc: 'الوصف',
  BoqCol.unit: 'الوحدة',
  BoqCol.qty: 'الكمية',
  BoqCol.price: 'سعر الوحدة',
  BoqCol.total: 'الإجمالي',
};

/// كلمات رأس الجدول لكل عمود (بعد التطبيع). أطول كلمة مطابقة تحسم العمود: «سعر الوحدة» سعر لا وحدة.
const Map<BoqCol, List<String>> _headerWords = {
  BoqCol.code: ['رقم البند', 'البند رقم', 'ر.ت', 'ر ت', 'رت', 'م', 'ت', 'الرقم', 'رقم', 'الكود', 'كود', 'no', 'no.', 'item', 'item no', 'code', 'ref'],
  BoqCol.desc: ['الوصف', 'وصف', 'البيان', 'بيان', 'بيان الاعمال', 'بيان العمل', 'وصف الاعمال', 'وصف البند', 'الاعمال', 'البند', 'description', 'item description'],
  BoqCol.unit: ['الوحده', 'وحده', 'وحده القياس', 'unit', 'uom'],
  BoqCol.qty: ['الكميه', 'كميه', 'العدد', 'qty', 'quantity', 'qty.'],
  BoqCol.price: ['سعر الوحده', 'السعر', 'سعر', 'الفئه', 'فئه', 'سعر الوحده دينار', 'الفئه دينار', 'rate', 'unit price', 'unit rate', 'price'],
  BoqCol.total: ['الاجمالي', 'اجمالي', 'القيمه', 'القيمه الاجماليه', 'المبلغ', 'الجمله', 'جمله', 'السعر الاجمالي', 'total', 'amount'],
};

/// يطبّع النص للمقارنة: حروف العرض إلى أصلها، والهمزات والتاء المربوطة والألف المقصورة، وحذف التشكيل والتطويل.
String boqNorm(String s) {
  final b = StringBuffer();
  for (final r in s.toLowerCase().runes) {
    if (r == 0x0640 || (r >= 0x064B && r <= 0x0652) || r == 0x0670) continue; // تطويل وتشكيل
    var c = r;
    if (c == 0x0623 || c == 0x0625 || c == 0x0622 || c == 0x0671) c = 0x0627; // أ إ آ ٱ ← ا
    if (c == 0x0629) c = 0x0647; // ة ← ه
    if (c == 0x0649) c = 0x064A; // ى ← ي
    b.writeCharCode(c);
  }
  return b.toString().replaceAll(RegExp(r'[\s:：/\\()\[\]«»"]+'), ' ').trim();
}

final RegExp _letters = RegExp(r'[A-Za-zء-ي]');

/// رقم من نص: الأرقام العربية الهندية والفارسية، والفاصلة العشرية العربية، وفواصل الآلاف، والأقواس للسالب،
/// ورمز العملة. نص فيه حروف غير العملة (مثل معادلة Excel) ليس رقماً.
double? parseBoqNumber(String raw) {
  var s = raw.trim();
  if (s.isEmpty) return null;
  final b = StringBuffer();
  for (final r in s.runes) {
    if (r >= 0x0660 && r <= 0x0669) {
      b.writeCharCode(0x30 + r - 0x0660);
    } else if (r >= 0x06F0 && r <= 0x06F9) {
      b.writeCharCode(0x30 + r - 0x06F0);
    } else if (r == 0x066B) {
      b.write('.');
    } else if (r == 0x066C || r == 0xA0 || r == 0x202F) {
      b.write(',');
    } else {
      b.writeCharCode(r);
    }
  }
  s = b.toString().replaceAll(RegExp(r'(د\.?\s?ل\.?|دينار|ل\.?\s?د\.?|lyd|LYD|\$)'), '').trim();
  var negative = false;
  if (s.startsWith('(') && s.endsWith(')')) {
    negative = true;
    s = s.substring(1, s.length - 1).trim();
  }
  if (s.startsWith('-') || s.startsWith('−')) {
    negative = true;
    s = s.substring(1).trim();
  }
  if (s.isEmpty || _letters.hasMatch(s) || !RegExp(r'\d').hasMatch(s)) return null;
  s = s.replaceAll(' ', '');
  if (!RegExp(r'^[\d.,]+$').hasMatch(s)) return null;
  final dots = '.'.allMatches(s).length;
  final commas = ','.allMatches(s).length;
  if (dots > 0 && commas > 0) {
    // الأخير هو الفاصل العشري: 1,250.50 أو 1.250,50
    if (s.lastIndexOf('.') > s.lastIndexOf(',')) {
      s = s.replaceAll(',', '');
    } else {
      s = s.replaceAll('.', '').replaceAll(',', '.');
    }
  } else if (commas > 0) {
    // فاصلة واحدة بعدها ثلاث خانات بالضبط: آلاف؛ وإلا عشرية (12,5)
    final parts = s.split(',');
    final thousands = parts.length > 2 || (parts.length == 2 && parts[1].length == 3);
    s = thousands ? s.replaceAll(',', '') : s.replaceAll(',', '.');
  } else if (dots > 1) {
    s = s.replaceAll('.', '');
  }
  final v = double.tryParse(s);
  if (v == null) return null;
  return negative ? -v : v;
}

/// أعمدة الجدول: صف الرأس (أو -1 دون رأس) ورقم العمود لكل دور.
class BoqColumns {
  BoqColumns(this.headerRow, this.map);

  final int headerRow;
  final Map<BoqCol, int> map;

  bool get usable => map.containsKey(BoqCol.desc) && (map.containsKey(BoqCol.qty) || map.containsKey(BoqCol.total));
}

/// دور خلية رأس، بأطول كلمة مطابقة.
BoqCol? headerRole(String cell) {
  final n = boqNorm(cell);
  if (n.isEmpty || n.length > 40) return null;
  BoqCol? best;
  var bestLen = 0;
  for (final e in _headerWords.entries) {
    for (final w in e.value) {
      final hit = n == w || (w.length >= 3 && (n.startsWith('$w ') || n.endsWith(' $w') || n.contains(' $w ') || n.startsWith(w)));
      if (hit && w.length > bestLen) {
        best = e.key;
        bestLen = w.length;
      }
    }
  }
  return best;
}

/// يحدد الأعمدة من صف الرأس في أول 40 صفاً، وإلا من محتوى الأعمدة.
BoqColumns detectBoqColumns(List<List<String>> rows) {
  var bestRow = -1;
  var best = <BoqCol, int>{};
  for (var r = 0; r < rows.length && r < 40; r++) {
    final m = <BoqCol, int>{};
    for (var c = 0; c < rows[r].length; c++) {
      final role = headerRole(rows[r][c]);
      if (role != null && !m.containsKey(role)) m[role] = c;
    }
    final ok = m.length >= 3 && (m.containsKey(BoqCol.desc) || m.containsKey(BoqCol.qty));
    if (ok && m.length > best.length) {
      best = m;
      bestRow = r;
    }
  }
  if (bestRow >= 0) {
    // «م» أو «ت» وحدهما رقم البند فقط إن كان في العمود أرقام قصيرة؛ وإلا يُترك
    return BoqColumns(bestRow, best);
  }
  return BoqColumns(-1, _inferByContent(rows));
}

const Set<String> _unitWords = {
  'م', 'م2', 'م3', 'م٢', 'م٣', 'م.ط', 'م ط', 'مط', 'م.م', 'م/ط', 'م.ل', 'متر', 'متر طولي', 'متر مربع', 'متر مكعب', 'عدد', 'طن', 'كجم', 'كغ',
  'كيلو', 'لتر', 'مقطوعيه', 'مقطوعية', 'م.ق', 'نقطه', 'نقطة', 'جوز', 'طقم', 'وحده', 'وحدة', 'يوم', 'شهر', 'ساعه', 'رحله', 'no', 'nr', 'ls',
  'm', 'm2', 'm3', 'lm', 'kg', 'ton', 'set', 'each', 'ea', 'sqm', 'cum',
};

bool _isUnit(String s) {
  final n = boqNorm(s).replaceAll(' ', '');
  return n.isNotEmpty && (_unitWords.contains(n) || _unitWords.contains(boqNorm(s)));
}

final RegExp _codeRe = RegExp(r'^[0-9A-Za-z٠-٩]{1,4}([.\-/][0-9A-Za-z٠-٩]{1,4}){0,5}\.?$');

/// دون رأس: الوصف أطول الأعمدة نصاً، والوحدة عمود وحدات القياس، والأعمدة الرقمية كمية وسعر وإجمالي
/// بحيث يقارب الإجمالي حاصل ضربهما.
Map<BoqCol, int> _inferByContent(List<List<String>> rows) {
  final width = rows.fold<int>(0, (w, r) => r.length > w ? r.length : w);
  final textLen = List<double>.filled(width, 0);
  final numeric = List<int>.filled(width, 0);
  final units = List<int>.filled(width, 0);
  final codes = List<int>.filled(width, 0);
  final filled = List<int>.filled(width, 0);
  for (final r in rows) {
    for (var c = 0; c < r.length; c++) {
      final v = r[c].trim();
      if (v.isEmpty) continue;
      filled[c]++;
      if (_isUnit(v)) {
        units[c]++;
      } else if (parseBoqNumber(v) != null) {
        numeric[c]++;
        if (_codeRe.hasMatch(v) && v.contains('.') && v.split('.').length > 2) codes[c]++;
      } else {
        textLen[c] += v.length;
      }
    }
  }
  final m = <BoqCol, int>{};
  var desc = -1;
  for (var c = 0; c < width; c++) {
    if (desc < 0 || textLen[c] > textLen[desc]) desc = c;
  }
  if (desc >= 0 && textLen[desc] > 0) m[BoqCol.desc] = desc;
  var unit = -1;
  for (var c = 0; c < width; c++) {
    if (units[c] > 0 && (unit < 0 || units[c] > units[unit])) unit = c;
  }
  if (unit >= 0) m[BoqCol.unit] = unit;
  var code = -1;
  for (var c = 0; c < width; c++) {
    if (codes[c] > 0 && (code < 0 || codes[c] > codes[code])) code = c;
  }
  if (code >= 0) m[BoqCol.code] = code;
  final nums = [
    for (var c = 0; c < width; c++)
      if (c != code && c != desc && c != unit && filled[c] > 0 && numeric[c] >= filled[c] * 0.6) c,
  ];
  // جرّب كل ترتيب لثلاثة أعمدة رقمية: أكثرها صفوفاً يصدق فيها الإجمالي = الكمية × السعر
  var bestScore = -1;
  for (final q in nums) {
    for (final p in nums) {
      for (final t in nums) {
        if (q == p || q == t || p == t) continue;
        var score = 0;
        for (final r in rows) {
          double? at(int c) => c < r.length ? parseBoqNumber(r[c]) : null;
          final qv = at(q), pv = at(p), tv = at(t);
          if (qv != null && pv != null && tv != null && (qv * pv - tv).abs() <= (tv.abs() * 0.01 + 0.05)) score++;
        }
        if (score > bestScore) {
          bestScore = score;
          m[BoqCol.qty] = q;
          m[BoqCol.price] = p;
          m[BoqCol.total] = t;
        }
      }
    }
  }
  if (bestScore <= 0 && nums.isNotEmpty) {
    m.remove(BoqCol.price);
    m.remove(BoqCol.total);
    m[BoqCol.qty] = nums.first;
    if (nums.length > 1) m[BoqCol.price] = nums[1];
    if (nums.length > 2) m[BoqCol.total] = nums[2];
  }
  return m;
}

/// سطر مستخرج للمراجعة.
class BoqImportLine {
  BoqImportLine({this.code = '', required this.desc, this.unit = '', this.qty, this.price, this.total, this.source = 0, this.heading = false});

  String code;
  String desc;
  String unit;
  double? qty;
  double? price;

  /// الإجمالي كما في الملف (للمقارنة فقط؛ القاعدة تحسبه من الكمية والسعر).
  double? total;

  /// رقم الصف في الملف (من 1) لمساعدة المراجع.
  final int source;

  /// عنوان باب أو قسم بلا كمية ولا سعر: لا يُحفظ بنداً.
  bool heading;

  double? get computed => qty == null || price == null ? null : qty! * price!;

  /// ملاحظات المراجعة: ما ينقص البند أو لا يتسق.
  List<String> get issues => [
        if (desc.trim().length < 2) 'بلا وصف',
        if (!heading && qty == null) 'بلا كمية',
        if (!heading && qty == 0) 'الكمية صفر',
        if (!heading && unit.trim().isEmpty) 'بلا وحدة',
        if (!heading && price == null) 'بلا سعر',
        if (!heading && total != null && computed != null && (computed! - total!).abs() > (total!.abs() * 0.005 + 0.5))
          'الإجمالي في الملف لا يساوي الكمية × السعر',
      ];

  bool get ok => issues.isEmpty;

  /// كما يُرسل إلى save_boq بنداً حراً.
  Map<String, dynamic> toJson() => {
        'code': code.trim().length > 30 ? code.trim().substring(0, 30) : code.trim(),
        'desc': desc.trim(),
        'unit': unit.trim().length > 20 ? unit.trim().substring(0, 20) : unit.trim(),
        'price': price,
        'qty': qty,
        'notes': '',
      };
}

/// نتيجة الاستخراج.
class BoqImportResult {
  BoqImportResult({required this.columns, required this.lines, this.fileTotal, this.skipped = 0});

  final BoqColumns columns;
  final List<BoqImportLine> lines;

  /// المجموع الكلي إن وُجد سطر «الإجمالي العام» في الملف.
  final double? fileTotal;

  /// صفوف المجاميع والترحيل التي تُركت.
  final int skipped;

  List<BoqImportLine> get items => [for (final l in lines) if (!l.heading) l];
  double get total => items.fold(0, (s, l) => s + (l.computed ?? 0));
  int get withIssues => items.where((l) => !l.ok).length;
}

final RegExp _summaryRe = RegExp(
    r'^(ال)?(مجموع|اجمالي|جمله|جمله ما|يرحل|المرحل|مرحل|ما قبله|منقول|المنقول|اجمالي الباب|اجمالي القسم|الاجمالي العام|المجموع الكلي|total|sub ?total|carried|brought)');
final RegExp _sectionRe = RegExp(r'^(اولا|ثانيا|ثالثا|رابعا|خامسا|سادسا|سابعا|ثامنا|تاسعا|عاشرا|الباب|باب|القسم|قسم|الفصل|فصل|اعمال|section|part|bill)');

/// يستخرج البنود من الصفوف. [columns] يتجاوز الأعمدة المكتشفة (حين يصححها المستخدم).
BoqImportResult extractBoq(List<List<String>> rows, {BoqColumns? columns}) {
  final cols = columns ?? detectBoqColumns(rows);
  final m = cols.map;
  String cell(List<String> r, BoqCol k) {
    final i = m[k];
    return i == null || i >= r.length ? '' : r[i].replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  final out = <BoqImportLine>[];
  double? fileTotal;
  var skipped = 0;
  final headerRoles = {for (final e in m.entries) e.key};
  for (var i = cols.headerRow + 1; i < rows.length; i++) {
    final r = rows[i];
    if (r.every((c) => c.trim().isEmpty)) continue;
    // رأس الجدول المكرر في كل صفحة
    var repeated = 0;
    for (final k in headerRoles) {
      if (headerRole(cell(r, k)) == k) repeated++;
    }
    if (repeated >= 3) continue;
    final code = cell(r, BoqCol.code);
    var desc = cell(r, BoqCol.desc);
    final unit = cell(r, BoqCol.unit);
    final qty = parseBoqNumber(cell(r, BoqCol.qty));
    final price = parseBoqNumber(cell(r, BoqCol.price));
    final total = parseBoqNumber(cell(r, BoqCol.total));
    // الوصف قد يقع في عمود الرقم حين يُدمج في الملف
    if (desc.isEmpty && code.isNotEmpty && parseBoqNumber(code) == null && !_codeRe.hasMatch(code)) desc = code;
    final nd = boqNorm(desc);
    if (qty == null && price == null && _summaryRe.hasMatch(nd)) {
      if (total != null && (fileTotal == null || total > fileTotal)) fileTotal = total;
      skipped++;
      continue;
    }
    final onlyText = qty == null && price == null && total == null && unit.isEmpty;
    if (onlyText) {
      if (desc.isEmpty && code.isEmpty) continue;
      final prev = out.isEmpty ? null : out.last;
      final continuation = prev != null && !prev.heading && code.isEmpty && desc.isNotEmpty && !_sectionRe.hasMatch(nd);
      if (continuation) {
        prev.desc = '${prev.desc} $desc'.trim();
      } else {
        out.add(BoqImportLine(code: code, desc: desc.isEmpty ? code : desc, source: i + 1, heading: true));
      }
      continue;
    }
    // سطر أرقام بعد سطر نص: البند المكتوب في أكثر من سطر وأرقامه في آخرها. يُضم إليه السطر السابق
    // إن خلا السطر من وصف، أو حمل السابق رقم بند ولم يحمله هذا السطر (وليس السابق عنوان باب).
    if (qty != null && out.isNotEmpty && out.last.heading) {
      final h = out.last;
      final sameItem = desc.isEmpty || (code.isEmpty && h.code.isNotEmpty && !_sectionRe.hasMatch(boqNorm(h.desc)));
      if (sameItem) {
        out.removeLast();
        out.add(BoqImportLine(
            code: code.isEmpty ? h.code : code, desc: '${h.desc} $desc'.trim(), unit: unit, qty: qty, price: price, total: total, source: h.source));
        continue;
      }
    }
    out.add(BoqImportLine(code: code, desc: desc, unit: unit, qty: qty, price: price ?? (qty != null && qty != 0 && total != null ? _round(total / qty) : null), total: total, source: i + 1));
  }
  return BoqImportResult(columns: cols, lines: out, fileTotal: fileTotal, skipped: skipped);
}

double _round(double v) => (v * 1000).roundToDouble() / 1000;

// ---------------------------------------------------------------------
// PDF: من نصوص الصفحة بمواضعها (كما تعيدها دالة boq-extract) إلى صفوف وأعمدة
// ---------------------------------------------------------------------

/// قطعة نص في صفحة PDF: x يسار القطعة، y من أعلى الصفحة، w عرضها، h ارتفاع الخط.
class PdfRun {
  const PdfRun(this.s, this.x, this.y, this.w, this.h);

  final String s;
  final double x;
  final double y;
  final double w;
  final double h;

  double get right => x + w;
  double get cx => x + w / 2;

  factory PdfRun.fromJson(Map<String, dynamic> m) {
    double n(Object? v) => v is num ? v.toDouble() : double.tryParse('$v') ?? 0;
    return PdfRun('${m['s'] ?? ''}', n(m['x']), n(m['y']), n(m['w']), n(m['h']));
  }
}

class _Cell {
  _Cell(this.parts);

  final List<PdfRun> parts;
  double get left => parts.map((p) => p.x).reduce((a, b) => a < b ? a : b);
  double get right => parts.map((p) => p.right).reduce((a, b) => a > b ? a : b);
  double get cx => (left + right) / 2;

  /// القطع من اليمين إلى اليسار (ترتيب القراءة في الجداول العربية).
  String get text {
    final l = [...parts]..sort((a, b) => b.x.compareTo(a.x));
    return l.map((p) => p.s.trim()).where((s) => s.isNotEmpty).join(' ').replaceAll(RegExp(r'\s+'), ' ').trim();
  }
}

/// أسطر الصفحة: قطع متقاربة الارتفاع، ثم خلايا تفصلها فجوات أعرض من حرفين تقريباً.
List<List<_Cell>> _pageLines(List<PdfRun> runs) {
  final items = runs.where((r) => r.s.trim().isNotEmpty).toList()..sort((a, b) => a.y.compareTo(b.y));
  if (items.isEmpty) return const [];
  final hs = items.map((r) => r.h > 0 ? r.h : 10.0).toList()..sort();
  final medianH = hs[hs.length ~/ 2];
  final tol = medianH * 0.45;
  final lines = <List<PdfRun>>[];
  for (final r in items) {
    if (lines.isNotEmpty && (r.y - lines.last.first.y).abs() <= tol) {
      lines.last.add(r);
    } else {
      lines.add([r]);
    }
  }
  final gap = medianH * 0.9;
  return [
    for (final l in lines)
      () {
        final sorted = [...l]..sort((a, b) => b.right.compareTo(a.right));
        final cells = <_Cell>[];
        for (final r in sorted) {
          if (cells.isNotEmpty && cells.last.left - r.right <= gap) {
            cells.last.parts.add(r);
          } else {
            cells.add(_Cell([r]));
          }
        }
        return cells;
      }(),
  ];
}

/// صفوف جدول من صفحات PDF: يُحدَّد الرأس بكلماته وتوزَّع الخلايا على أعمدته بأقرب مركز؛
/// ودون رأس تُجمع مراكز الخلايا في أعمدة. الأعمدة من اليمين إلى اليسار.
List<List<String>> pdfRows(List<List<PdfRun>> pages) {
  final all = [for (final p in pages) ..._pageLines(p)];
  // الرأس: أول سطر فيه ثلاثة أدوار أو أكثر
  List<_Cell>? header;
  for (final l in all) {
    final roles = {for (final c in l) headerRole(c.text)}..remove(null);
    if (roles.length >= 3) {
      header = l;
      break;
    }
  }
  List<double> anchors;
  if (header != null) {
    anchors = [for (final c in header) c.cx]..sort((a, b) => b.compareTo(a));
  } else {
    final centers = [for (final l in all) for (final c in l) c.cx]..sort((a, b) => b.compareTo(a));
    anchors = [];
    for (final c in centers) {
      if (anchors.isEmpty || anchors.last - c > 18) anchors.add(c);
    }
  }
  if (anchors.isEmpty) return const [];
  final rows = <List<String>>[];
  for (final l in all) {
    final row = List<String>.filled(anchors.length, '');
    for (final c in l) {
      var k = 0;
      for (var i = 1; i < anchors.length; i++) {
        if ((anchors[i] - c.cx).abs() < (anchors[k] - c.cx).abs()) k = i;
      }
      row[k] = row[k].isEmpty ? c.text : '${row[k]} ${c.text}';
    }
    rows.add(row);
  }
  return rows;
}
