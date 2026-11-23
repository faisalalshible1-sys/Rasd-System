// =====================================================================
// دليل الاستخدام: فهرس الفصول، وربط كل صفحة بفصلها، والقيم والجداول الحية، ومحلل صيغة الفصول.
//
// قاعدة ثابتة: كل صفحة جديدة في القوائم (رقم في Tabs) تُربط هنا بفصل، وكل فصل ملفه في assets/manual/.
// وتتحقق الاختبارات من ذلك (test/manual_test.dart) فلا تُضاف صفحة دون شرح.
// =====================================================================

class ManualChapter {
  const ManualChapter(this.id, this.number, this.title);

  /// اسم الملف دون الامتداد في assets/manual/
  final String id;

  /// رقم الفصل كما يُشار إليه في النص («الفصل 17»)؛ 0 للمقدمة، و-1 للملحق.
  final int number;
  final String title;

  String get asset => 'assets/manual/$id.md';
  String get label => number > 0 ? '$number. $title' : title;
}

const List<ManualChapter> manualChapters = [
  ManualChapter('00_about', 0, 'عن هذا الدليل'),
  ManualChapter('01_overview', 1, 'نظرة عامة على المنظومة'),
  ManualChapter('02_access', 2, 'الدخول والحساب والأمان'),
  ManualChapter('03_roles', 3, 'الأدوار والصلاحيات'),
  ManualChapter('04_cycle', 4, 'الدورة المستندية: العقود والنماذج'),
  ManualChapter('05_progress', 5, 'حساب نسبة إنجاز الدورة ومؤشراتها'),
  ManualChapter('06_approvals', 6, 'الاعتمادات والدمج والدليل المرجعي'),
  ManualChapter('07_finance', 7, 'المالية: القيم والمستخلصات والضمانات'),
  ManualChapter('08_pm_map', 8, 'المخاطر ومتابعة المشاريع: خريطة القسم'),
  ManualChapter('09_risk_register', 9, 'سجل المخاطر: التسجيل والتقييم'),
  ManualChapter('10_risk_review', 10, 'سجل المخاطر: المراجعة والمتابعة والإغلاق'),
  ManualChapter('11_risk_board', 11, 'لوحة المخاطر والسجل والمصفوفة'),
  ManualChapter('12_pm_projects', 12, 'سجل المشاريع والتقدم الدوري'),
  ManualChapter('13_pm_registers', 13, 'المشاكل والتأخيرات والتغييرات والدروس'),
  ManualChapter('14_contractors', 14, 'تقييم الشركات المنفذة'),
  ManualChapter('15_pm_dashboard', 15, 'لوحة القيادة والتنبيهات والتقرير الدوري'),
  ManualChapter('16_swot', 16, 'تحليل SWOT'),
  ManualChapter('17_docs', 17, 'الشؤون الفنية: المقايسات والمراسلات والتصاميم واعتماد المواد'),
  ManualChapter('18_supervision', 18, 'الإشراف: التقارير اليومية ومتابعة التغطية'),
  ManualChapter('19_heritage', 19, 'الترميم والمباني التاريخية'),
  ManualChapter('20_planning_qa', 20, 'مكتب التخطيط وضمان الجودة'),
  ManualChapter('21_safety', 21, 'مكتب السلامة المهنية'),
  ManualChapter('22_acceptance', 22, 'المطابقة والاستلام'),
  ManualChapter('23_admin', 23, 'الإدارة والتدقيق والمساعد'),
  ManualChapter('24_manual', 24, 'دليل الاستخدام داخل المنظومة'),
  ManualChapter('25_print', 25, 'الطباعة والتصدير ومكتبة الوسائط'),
  ManualChapter('26_chat', 26, 'المراسلات الداخلية'),
  ManualChapter('27_security', 27, 'مركز الأمن السيبراني'),
  ManualChapter('28_prices', 28, 'لائحة الأسعار الاسترشادية ومُعِدّ المقايسات'),
  ManualChapter('29_schedule', 29, 'البرامج الزمنية: الإعداد من المقايسة ومتابعة الانحرافات'),
  ManualChapter('30_supervision_hub', 30, 'الإشراف: لوحة المتابعة ودورة حياة العقد وبنود العقود'),
  ManualChapter('31_customize_ideas', 31, 'تخصيص الواجهة والأفكار والتطوير'),
  ManualChapter('32_section_isolation', 32, 'عزل الأقسام والمهام المسندة'),
  ManualChapter('25_appendix', -1, 'ملحق: مرجع سريع للمعادلات'),
];

/// أقسام الفصول الخاصة بقسم (البقية عامة لكل المستخدمين): يرى كل مستخدم فصول أقسامه وحدها (الترحيل 34).
const Map<String, List<String>> manualChapterSections = {
  '04_cycle': ['cycle'],
  '05_progress': ['cycle'],
  '06_approvals': ['cycle'],
  '07_finance': ['cycle'],
  '08_pm_map': ['risks'],
  '09_risk_register': ['risks'],
  '10_risk_review': ['risks'],
  '11_risk_board': ['risks'],
  '12_pm_projects': ['risks'],
  '13_pm_registers': ['risks'],
  '14_contractors': ['risks'],
  '15_pm_dashboard': ['risks'],
  '16_swot': ['swot'],
  '17_docs': ['docs'],
  '28_prices': ['docs'],
  '29_schedule': ['docs', 'supervision'],
  '18_supervision': ['supervision'],
  '30_supervision_hub': ['supervision'],
  '19_heritage': ['heritage'],
  '20_planning_qa': ['planning_qa'],
  '21_safety': ['safety'],
  '22_acceptance': ['acceptance'],
  '27_security': ['security'],
};

/// فصول الدليل لمستخدم: العامة، وفصول الأقسام التي يراها.
List<ManualChapter> manualChaptersFor(bool Function(String section) sees) => [
      for (final c in manualChapters)
        if ((manualChapterSections[c.id] ?? const <String>[]).isEmpty || manualChapterSections[c.id]!.any(sees)) c,
    ];

const String manualChangelogAsset = 'assets/manual/changelog.md';

/// تاريخ آخر تحديث لمحتوى الدليل (يُحدَّث مع كل تعديل على الفصول).
const String manualUpdated = '2026/11/23';

ManualChapter? manualChapter(String id) {
  for (final c in manualChapters) {
    if (c.id == id) return c;
  }
  return null;
}

/// فصل الدليل لكل صفحة في القوائم (قيم app.tab). صفحات الإدارة لها أرقام في كل قسم.
const Map<int, String> manualTabAnchors = {
  // الدورة المستندية
  0: '05_progress', // الرئيسية
  1: '04_cycle', // العقود
  2: '06_approvals', // الاعتمادات / طلباتي
  3: '05_progress', // التحليل
  4: '31_customize_ideas', // الأفكار والتطوير (العامة)
  5: '23_admin', // لوحة التحكم
  6: '23_admin', // مساعد Claude
  7: '07_finance', // المالية
  8: '06_approvals', // الدليل المرجعي
  // المخاطر ومتابعة المشاريع
  20: '11_risk_board',
  21: '09_risk_register',
  22: '11_risk_board',
  28: '23_admin',
  29: '23_admin',
  40: '15_pm_dashboard',
  41: '12_pm_projects',
  42: '12_pm_projects',
  43: '13_pm_registers',
  44: '13_pm_registers',
  45: '13_pm_registers',
  46: '13_pm_registers',
  47: '14_contractors',
  48: '15_pm_dashboard',
  49: '15_pm_dashboard',
  50: '08_pm_map',
  51: '15_pm_dashboard',
  52: '29_schedule',
  // تحليل SWOT
  30: '16_swot',
  31: '16_swot',
  32: '16_swot',
  33: '16_swot',
  34: '16_swot',
  35: '16_swot',
  36: '16_swot',
  37: '16_swot',
  38: '23_admin',
  39: '23_admin',
  // الشؤون الفنية
  60: '17_docs',
  61: '17_docs',
  62: '17_docs',
  63: '17_docs',
  64: '17_docs',
  65: '28_prices',
  66: '28_prices',
  67: '29_schedule', // البرامج الزمنية (الإعداد)
  68: '23_admin',
  69: '23_admin',
  // الإشراف
  70: '18_supervision',
  71: '18_supervision',
  72: '30_supervision_hub', // لوحة الإشراف
  73: '30_supervision_hub', // بنود العقود
  78: '23_admin',
  79: '23_admin',
  // دليل الاستخدام
  80: '24_manual',
  81: '24_manual',
  88: '23_admin',
  89: '23_admin',
  // الترميم والمباني التاريخية
  90: '19_heritage',
  91: '19_heritage',
  92: '19_heritage',
  98: '23_admin',
  99: '23_admin',
  // مكتب التخطيط وضمان الجودة
  100: '20_planning_qa',
  101: '20_planning_qa',
  102: '20_planning_qa',
  103: '20_planning_qa',
  108: '23_admin',
  109: '23_admin',
  // مكتب السلامة المهنية
  110: '21_safety',
  111: '21_safety',
  112: '21_safety',
  113: '21_safety',
  118: '23_admin',
  119: '23_admin',
  // المطابقة والاستلام
  120: '22_acceptance',
  121: '22_acceptance',
  122: '22_acceptance',
  128: '23_admin',
  129: '23_admin',
  // الطباعة والتصدير
  130: '25_print',
  131: '25_print',
  132: '25_print',
  133: '25_print',
  138: '23_admin',
  139: '23_admin',
  // المراسلات الداخلية
  140: '26_chat',
  141: '26_chat',
  142: '26_chat',
  148: '23_admin',
  149: '23_admin',
  // الأمن السيبراني
  150: '27_security',
  151: '27_security',
  152: '27_security',
  153: '27_security',
  154: '27_security',
  155: '27_security',
  156: '27_security',
  157: '27_security',
  160: '27_security',
  161: '27_security',
  168: '23_admin',
  169: '23_admin',
  // الأفكار والتطوير في كل قسم
  171: '31_customize_ideas',
  172: '31_customize_ideas',
  173: '31_customize_ideas',
  174: '31_customize_ideas',
  175: '31_customize_ideas',
  176: '31_customize_ideas',
  177: '31_customize_ideas',
  178: '31_customize_ideas',
  179: '31_customize_ideas',
  180: '31_customize_ideas',
  181: '31_customize_ideas',
  182: '31_customize_ideas',
  // المهام المسندة في أقسام من لا يرى الدورة المستندية (الترحيل 34)
  183: '32_section_isolation',
  184: '32_section_isolation',
  185: '32_section_isolation',
  186: '32_section_isolation',
  187: '32_section_isolation',
  188: '32_section_isolation',
};

/// فصل كل قسم رئيسي (لبطاقات الأقسام والبحث).
const Map<String, String> manualSectionAnchors = {
  'cycle': '04_cycle',
  'risks': '08_pm_map',
  'swot': '16_swot',
  'docs': '17_docs',
  'supervision': '30_supervision_hub',
  'heritage': '19_heritage',
  'planning_qa': '20_planning_qa',
  'safety': '21_safety',
  'acceptance': '22_acceptance',
  'print': '25_print',
  'chat': '26_chat',
  'security': '27_security',
  'manual': '24_manual',
};

String manualAnchorForTab(int tab) => manualTabAnchors[tab] ?? '00_about';

// ---------------------------------------------------------------------
// صيغة الفصول: # و## و###، فقرات، قوائم (- و1.)، جداول |، صناديق :::نوع عنوان … :::
// وأسطر كاملة بين {{ }} لعناصر حية (مثل {{RISK_MATRIX}}).
// ---------------------------------------------------------------------
sealed class MBlock {
  const MBlock();
}

class MHeading extends MBlock {
  const MHeading(this.level, this.text);
  final int level;
  final String text;
}

class MParagraph extends MBlock {
  const MParagraph(this.text);
  final String text;
}

class MListItem {
  const MListItem(this.text, this.depth, this.ordered, this.number);
  final String text;
  final int depth;
  final bool ordered;
  final int number;
}

class MList extends MBlock {
  const MList(this.items);
  final List<MListItem> items;
}

class MTable extends MBlock {
  const MTable(this.header, this.rows);
  final List<String> header;
  final List<List<String>> rows;

  /// جدول بلا ترويسة حقيقية (كل خلايا الترويسة فارغة).
  bool get headless => header.every((h) => h.trim().isEmpty);
}

class MBox extends MBlock {
  const MBox(this.kind, this.title, this.children);

  /// formula | example | note | warning
  final String kind;
  final String title;
  final List<MBlock> children;
}

class MWidget extends MBlock {
  const MWidget(this.name);
  final String name;
}

final RegExp _listRe = RegExp(r'^(\s*)(-|\d+\.)\s+(.*)$');
final RegExp _boxRe = RegExp(r'^:::(formula|example|note|warning)\s*(.*)$');
final RegExp _widgetRe = RegExp(r'^\{\{([A-Z_0-9]+)\}\}$');

List<String> _cells(String line) {
  var l = line.trim();
  if (l.startsWith('|')) l = l.substring(1);
  if (l.endsWith('|') && !l.endsWith(r'\|')) l = l.substring(0, l.length - 1);
  final out = <String>[];
  final b = StringBuffer();
  for (var i = 0; i < l.length; i++) {
    if (l[i] == r'\' && i + 1 < l.length && l[i + 1] == '|') {
      b.write('|');
      i++;
    } else if (l[i] == '|') {
      out.add(b.toString().trim());
      b.clear();
    } else {
      b.write(l[i]);
    }
  }
  out.add(b.toString().trim());
  return out;
}

bool _isSeparator(String line) => RegExp(r'^\|?(\s*:?-{3,}:?\s*\|)+\s*:?-{0,}:?\s*\|?$').hasMatch(line.trim());

/// يحلل نص الفصل إلى كتل.
List<MBlock> parseManual(String text) {
  final lines = text.replaceAll('\r\n', '\n').split('\n');
  var i = 0;

  List<MBlock> parse({bool inBox = false}) {
    final out = <MBlock>[];
    final para = <String>[];
    void flush() {
      if (para.isNotEmpty) {
        out.add(MParagraph(para.join('\n')));
        para.clear();
      }
    }

    while (i < lines.length) {
      final raw = lines[i];
      final line = raw.trimRight();
      final t = line.trim();
      if (inBox && t == ':::') {
        flush();
        i++;
        return out;
      }
      if (t.isEmpty) {
        flush();
        i++;
        continue;
      }
      final box = _boxRe.firstMatch(t);
      if (box != null) {
        flush();
        i++;
        final children = parse(inBox: true);
        out.add(MBox(box.group(1)!, box.group(2)!.trim(), children));
        continue;
      }
      final w = _widgetRe.firstMatch(t);
      if (w != null) {
        flush();
        out.add(MWidget(w.group(1)!));
        i++;
        continue;
      }
      if (t.startsWith('#')) {
        flush();
        final level = t.indexOf(RegExp(r'[^#]'));
        out.add(MHeading(level.clamp(1, 3), t.substring(level).trim()));
        i++;
        continue;
      }
      if (t.startsWith('|') && i + 1 < lines.length && _isSeparator(lines[i + 1])) {
        flush();
        final header = _cells(t);
        i += 2;
        final rows = <List<String>>[];
        while (i < lines.length && lines[i].trim().startsWith('|')) {
          final c = _cells(lines[i]);
          rows.add([for (var k = 0; k < header.length; k++) k < c.length ? c[k] : '']);
          i++;
        }
        out.add(MTable(header, rows));
        continue;
      }
      if (_listRe.hasMatch(line)) {
        flush();
        final items = <MListItem>[];
        while (i < lines.length) {
          final m = _listRe.firstMatch(lines[i].trimRight());
          if (m == null) break;
          final depth = m.group(1)!.length ~/ 2;
          final mark = m.group(2)!;
          final ordered = mark != '-';
          items.add(MListItem(m.group(3)!, depth, ordered, ordered ? int.parse(mark.substring(0, mark.length - 1)) : 0));
          i++;
        }
        out.add(MList(items));
        continue;
      }
      para.add(t);
      i++;
    }
    flush();
    return out;
  }

  return parse();
}

/// أجزاء نص مضمّن: (النص، عريض، مائل، شيفرة)
List<(String, bool, bool, bool)> parseInline(String s) {
  final out = <(String, bool, bool, bool)>[];
  final re = RegExp(r'\*\*(.+?)\*\*|\*(.+?)\*|`(.+?)`');
  var pos = 0;
  for (final m in re.allMatches(s)) {
    if (m.start > pos) out.add((s.substring(pos, m.start), false, false, false));
    if (m.group(1) != null) {
      // عريض قد يحتوي مائلاً: نكتفي بالعريض
      out.add((m.group(1)!.replaceAll('*', ''), true, false, false));
    } else if (m.group(2) != null) {
      out.add((m.group(2)!, false, true, false));
    } else {
      out.add((m.group(3)!, false, false, true));
    }
    pos = m.end;
  }
  if (pos < s.length) out.add((s.substring(pos), false, false, false));
  return out;
}

/// النص المجرد للبحث (دون علامات التنسيق).
String manualPlain(String md) => md
    .replaceAll(RegExp(r'^:::\w*\s*', multiLine: true), '')
    .replaceAll(RegExp(r'[*`#|]'), ' ')
    .replaceAll(RegExp(r'\s+'), ' ');

/// عدد مرات ورود [q] في [text] (بتطبيع بسيط للهمزات والتاء المربوطة).
int manualCount(String text, String q) {
  final n = _norm(q.trim());
  if (n.isEmpty) return 0;
  final h = _norm(text);
  var c = 0;
  var i = h.indexOf(n);
  while (i >= 0) {
    c++;
    i = h.indexOf(n, i + n.length);
  }
  return c;
}

String _norm(String s) => s
    .replaceAll(RegExp('[أإآ]'), 'ا')
    .replaceAll('ة', 'ه')
    .replaceAll('ى', 'ي')
    .replaceAll(RegExp('[ً-ْـ]'), '')
    .toLowerCase();

/// يستبدل القيم الحية المضمّنة {{NAME}} بقيمها. الأسماء غير المعروفة تبقى كما هي.
String applyManualValues(String text, Map<String, String> values) =>
    text.replaceAllMapped(RegExp(r'\{\{([A-Z_0-9]+)\}\}'), (m) => values[m.group(1)!] ?? m.group(0)!);

/// الجهات المسؤولة عن النماذج بأسمائها في الدليل.
const Map<String, String> manualResponsibleLabels = {
  'office_staff': 'موظفو مكتب المدير',
  'head:supervising': 'رئيس القسم المشرف',
  'head:technical': 'رئيس قسم الشؤون الفنية',
  'head:acceptance': 'رئيس قسم المطابقة والاستلام',
  'contracts': 'مكتب العقود والمستخلصات',
  'planning_qa': 'مكتب التخطيط وضمان الجودة',
};

/// جدول النماذج الحي بصيغة الدليل: (مرحلة، نماذجها) → صفوف.
String manualFormsTable({
  required List<String> stageNames,
  required List<({String name, int stage, bool sensitive, List<String> responsible})> forms,
}) {
  final b = StringBuffer('| م | النموذج | المسؤول عن التحديث (مع المدير) | حساس |\n| --- | --- | --- | --- |\n');
  var n = 0;
  for (var st = 0; st < stageNames.length; st++) {
    final fs = forms.where((f) => f.stage == st).toList();
    if (fs.isEmpty) continue;
    b.write('| | **المرحلة ${st + 1}: ${stageNames[st]} (${fs.length})** | | |\n');
    for (final f in fs) {
      n++;
      final resp = f.responsible.map((r) => manualResponsibleLabels[r] ?? r).join('، ');
      b.write('| $n | ${f.name} | $resp | ${f.sensitive ? '●' : ''} |\n');
    }
  }
  return b.toString();
}

/// جدول مستويات الخطر الحي: (الاسم، الحد الأدنى، الإجراء، دورية المراجعة) مرتبة تصاعدياً.
String manualLevelsTable(List<({String name, int min, String action, int? reviewDays})> levels) {
  final b = StringBuffer('| المستوى | نطاق الدرجة | الاستجابة ومسار التصعيد | دورية المراجعة |\n| --- | --- | --- | --- |\n');
  for (var i = levels.length - 1; i >= 0; i--) {
    final l = levels[i];
    final hi = i + 1 < levels.length ? levels[i + 1].min - 1 : 25;
    b.write('| **${l.name}** | ${l.min} – $hi | ${l.action} | ${l.reviewDays == null ? '—' : '${l.reviewDays} يوماً'} |\n');
  }
  return b.toString();
}
