// =====================================================================
// «منظومة رصد» — الترحيل 23: الصلاحيات الدقيقة، والرقم الإشاري الموسّع، وتخصيص الواجهة.
// =====================================================================

import 'models.dart';
import 'units.dart';

// ---------------------------------------------------------------------
// الصلاحيات الدقيقة
// ---------------------------------------------------------------------

/// نطاق صلاحية دقيقة: (المفتاح كما يُحفظ، الاسم، المجموعة).
class GrantScope {
  const GrantScope(this.key, this.label, this.group, {this.note = ''});

  final String key;
  final String label;
  final String group;

  /// ما يترتب على المنح (مثل: «أمر بالتعاقد» يشمل البيانات المالية للعقد).
  final String note;
}

const Map<String, String> docKindLabels = {'boq': 'المقايسات', 'letter': 'المراسلات', 'design': 'التصاميم'};

/// كل النطاقات التي يمكن منحها، مجمّعة: نماذج الدورة المستندية، والشؤون الفنية، والإشراف، وسجلات الوحدات، وSWOT.
List<GrantScope> grantCatalog(List<FormDef> forms, {List<(String, String)> warehouses = const []}) => [
      for (final f in forms)
        if (f.active)
          GrantScope('form:${f.key}', f.name, 'نماذج الدورة المستندية',
              note: f.key == contractFormKey ? 'يشمل البيانات المالية للعقد وأعماله' : (f.engineerField != null ? 'يشمل تكليف المهندس المقابل' : '')),
      for (final e in docKindLabels.entries) GrantScope('docs:${e.key}', e.value, 'الشؤون الفنية'),
      const GrantScope('supervision:reports', 'التقارير اليومية للمواقع', 'الإشراف'),
      const GrantScope('pm:plan', 'إعداد البرامج الزمنية', 'الشؤون الفنية',
          note: 'البنود والمراحل والمدد والتوليد من المقايسة المعتمدة، دون الاعتماد'),
      const GrantScope('pm:track', 'متابعة تنفيذ البرامج الزمنية', 'الإشراف',
          note: 'الإنجاز والتواريخ الفعلية و«لا ينطبق» على البرامج المعتمدة لكل العقود'),
      // صلاحيات البرنامج الزمني الدقيقة (الترحيل 36)
      const GrantScope('docs:pm_view', 'عرض البرامج الزمنية', 'البرنامج الزمني', note: 'يُظهر قسم الشؤون الفنية بالبرامج دون تعديلها'),
      const GrantScope('docs:pm_add', 'إضافة أنشطة البرنامج الزمني', 'البرنامج الزمني', note: 'إضافة الأنشطة وحذفها وتعديل أسمائها وبياناتها'),
      const GrantScope('docs:pm_duration', 'تعديل مدد الأنشطة', 'البرنامج الزمني'),
      const GrantScope('docs:pm_dates', 'تعديل تواريخ البداية والنهاية', 'البرنامج الزمني',
          note: 'الإزاحة و«لا يبدأ قبل» والعلاقات بين الأنشطة'),
      const GrantScope('docs:pm_approve', 'اعتماد البرنامج الزمني', 'البرنامج الزمني',
          note: 'الاعتماد وإعادة الفتح ومعدلات الإنتاجية'),
      for (final k in unitKinds.values) GrantScope('unit:${k.key}', k.label, unitNames[k.unit] ?? k.unit),
      const GrantScope('swot', 'تحليل SWOT', 'التخطيط الاستراتيجي'),
      // قسم المخازن والأصول (الترحيل 38)
      const GrantScope('stores:admin', 'مدير النظام في المخازن', 'المخازن والأصول',
          note: 'الإدارات والموظفون والمواقع والمخازن والتصنيفات والوحدات والإعدادات'),
      const GrantScope('stores:manager', 'مدير المخازن', 'المخازن والأصول',
          note: 'بطاقات الأصناف، واعتماد المستندات وعكسها، واستثناء الاحتياطي الحرج، وحركات كل المخازن'),
      const GrantScope('stores:audit', 'مراجع المخازن', 'المخازن والأصول', note: 'اطلاع على كل القسم وتقاريره دون تعديل'),
      // الأصول والعهد (الترحيل 39)
      const GrantScope('stores:assets', 'مسؤول الأصول والعهد', 'المخازن والأصول',
          note: 'سجل الأصول، وتسليم العهد واستلامها، والنقل وتغيير الوضع، وطلب الاستبعاد (يعتمده مدير المخازن)'),
      for (final w in warehouses)
        GrantScope('stores:keeper:${w.$1}', 'أمين مخزن: ${w.$2}', 'المخازن والأصول',
            note: 'إعداد مستندات المخزن وتقديمها، وترحيلها بعد اعتمادها'),
      // قسم الصيانة (الترحيل 40)
      const GrantScope('maintenance:admin', 'مدير النظام في الصيانة', 'الصيانة',
          note: 'الفنيون والإعدادات، وكل ما يفعله مدير الصيانة'),
      const GrantScope('maintenance:manager', 'مدير الصيانة', 'الصيانة',
          note: 'فرز البلاغات وإسنادها ورفضها وإلغاؤها، وخطط الصيانة الدورية، ورؤية كل البلاغات'),
      const GrantScope('maintenance:tech', 'فني صيانة', 'الصيانة',
          note: 'يرى البلاغات المسنَدة إليه وينفّذها (بدء وتعليق وإنجاز). يلزم ربط سجل موظف بحسابه، ولا يُمنح لحساب «موظف»'),
      const GrantScope('maintenance:audit', 'مراجع الصيانة', 'الصيانة', note: 'اطلاع على كل القسم وتقاريره دون تعديل'),
    ];

String grantLabel(String scope, List<FormDef> forms, {List<(String, String)> warehouses = const []}) {
  for (final g in grantCatalog(forms, warehouses: warehouses)) {
    if (g.key == scope) return g.label;
  }
  if (scope.startsWith('stores:keeper:')) return 'أمين مخزن';
  if (scope.startsWith('form:')) {
    for (final f in forms) {
      if ('form:${f.key}' == scope) return '${f.name} (موقوف)';
    }
  }
  return scope;
}

// ---------------------------------------------------------------------
// الرقم الإشاري
// ---------------------------------------------------------------------

const Map<String, String> refResetLabels = {
  'yearly': 'يبدأ من جديد كل سنة',
  'monthly': 'يبدأ من جديد كل شهر',
  'daily': 'يبدأ من جديد كل يوم',
  'never': 'تسلسل مستمر لا يُصفَّر',
};

/// رموز الصيغة وشرحها.
const List<(String, String)> refTokens = [
  ('{YYYY}', 'السنة (2026)'),
  ('{YY}', 'السنة مختصرة (26)'),
  ('{MM}', 'الشهر (11)'),
  ('{DD}', 'اليوم (19)'),
  ('{SEQ}', 'التسلسل بعدد الخانات المحدد'),
  ('{SEQ:3}', 'التسلسل بثلاث خانات (001)'),
  ('{SECTION}', 'رمز القسم المصدِر'),
  ('{DEPT}', 'رمز القسم المشرف على العقد'),
  ('{CODE}', 'رمز يمرره المصدر (رقم العقد مثلاً)'),
  ('{KIND}', 'نوع السجل'),
];

/// أقسام المنظومة التي تُصدِر مطبوعات، لرموز {SECTION}.
const Map<String, String> refSectionNames = {
  'cycle': 'الدورة المستندية',
  'risks': 'المخاطر ومتابعة المشاريع',
  'swot': 'تحليل SWOT',
  'docs': 'الشؤون الفنية',
  'supervision': 'الإشراف',
  'heritage': 'الترميم والمباني التاريخية',
  'planning_qa': 'التخطيط وضمان الجودة',
  'safety': 'السلامة المهنية',
  'acceptance': 'المطابقة والاستلام',
  'print': 'الطباعة والتصدير',
  'manual': 'دليل الاستخدام',
  'security': 'الأمن السيبراني',
  'chat': 'المراسلات الداخلية',
  'stores': 'المخازن والأصول',
  'maintenance': 'الصيانة',
};

class RefScheme {
  const RefScheme({
    required this.key,
    required this.name,
    required this.pattern,
    this.reset = 'yearly',
    this.perSection = false,
    this.pad = 4,
    this.startAt = 1,
    this.codes = const {},
    this.active = true,
    this.system = false,
    this.updatedAt,
  });

  final String key;
  final String name;
  final String pattern;
  final String reset;
  final bool perSection;
  final int pad;
  final int startAt;
  final Map<String, String> codes;
  final bool active;
  final bool system;
  final DateTime? updatedAt;

  factory RefScheme.fromMap(Map<String, dynamic> m) => RefScheme(
        key: m['key'].toString(),
        name: (m['name'] ?? '').toString(),
        pattern: (m['pattern'] ?? '').toString(),
        reset: (m['reset'] ?? 'yearly').toString(),
        perSection: m['per_section'] == true,
        pad: (m['pad'] as num?)?.toInt() ?? 4,
        startAt: (m['start_at'] as num?)?.toInt() ?? 1,
        codes: m['codes'] is Map ? {for (final e in (m['codes'] as Map).entries) e.key.toString(): e.value.toString()} : const {},
        active: m['active'] != false,
        system: m['system'] == true,
        updatedAt: DateTime.tryParse((m['updated_at'] ?? '').toString())?.toLocal(),
      );

  Map<String, dynamic> toData() => {
        'name': name,
        'pattern': pattern,
        'reset': reset,
        'per_section': perSection,
        'pad': pad,
        'start_at': startAt,
        'codes': codes,
        'active': active,
      };

  /// معاينة الرقم كما تصدره قاعدة البيانات (ref_format) دون حجز تسلسل.
  String preview({DateTime? at, int seq = 1, Map<String, String> ctx = const {}}) =>
      formatRef(pattern, seq: seq, pad: pad, at: at ?? DateTime.now(), ctx: ctx, codes: codes);

  /// شكل الرقم قبل صدوره: التسلسل علامات # (لمعاينة الطباعة).
  String masked({Map<String, String> ctx = const {}}) {
    final p = pattern.replaceAllMapped(RegExp(r'\{SEQ(?::([1-8]))?\}'), (m) => '#' * (m.group(1) != null ? int.parse(m.group(1)!) : pad));
    return formatRef(p, seq: 0, pad: pad, at: DateTime.now(), ctx: ctx, codes: codes);
  }
}

String _p2(int n) => n.toString().padLeft(2, '0');

/// المعادلة نفسها في قاعدة البيانات (public.ref_format)؛ اختبار test/rasd_test.dart يطابق بينهما.
String formatRef(String pattern,
    {required int seq, required int pad, required DateTime at, Map<String, String> ctx = const {}, Map<String, String> codes = const {}}) {
  String code(String? k) {
    final key = k ?? '';
    final c = codes[key] ?? '';
    if (c.isNotEmpty) return c;
    return key.isEmpty ? '-' : key;
  }

  var r = pattern
      .replaceAll('{YYYY}', '${at.year}')
      .replaceAll('{YY}', _p2(at.year % 100))
      .replaceAll('{MM}', _p2(at.month))
      .replaceAll('{DD}', _p2(at.day))
      .replaceAll('{SECTION}', code(ctx['section']))
      .replaceAll('{DEPT}', code(ctx['dept']));
  final rawCode = (ctx['code'] ?? '').replaceAll(RegExp(r'[\s/]+'), '-');
  r = r.replaceAll('{CODE}', rawCode.isEmpty ? '-' : (rawCode.length > 30 ? rawCode.substring(0, 30) : rawCode));
  r = r.replaceAll('{KIND}', code(ctx['kind']));
  r = r.replaceAllMapped(RegExp(r'\{SEQ:([1-8])\}'), (m) => seq.toString().padLeft(int.parse(m.group(1)!), '0'));
  return r.replaceAll('{SEQ}', seq.toString().padLeft(pad, '0'));
}

class RefLogEntry {
  const RefLogEntry({
    required this.id,
    required this.scheme,
    required this.ref,
    required this.seq,
    required this.period,
    this.section,
    this.source,
    this.title,
    this.createdBy,
    this.createdAt,
  });

  final int id;
  final String scheme;
  final String ref;
  final int seq;
  final String period;
  final String? section;
  final String? source;
  final String? title;
  final String? createdBy;
  final DateTime? createdAt;

  factory RefLogEntry.fromMap(Map<String, dynamic> m) => RefLogEntry(
        id: (m['id'] as num).toInt(),
        scheme: m['scheme'].toString(),
        ref: (m['ref'] ?? '').toString(),
        seq: (m['seq'] as num?)?.toInt() ?? 0,
        period: (m['period'] ?? '').toString(),
        section: m['section'] as String?,
        source: m['source'] as String?,
        title: m['title'] as String?,
        createdBy: m['created_by'] as String?,
        createdAt: DateTime.tryParse((m['created_at'] ?? '').toString())?.toLocal(),
      );
}

// ---------------------------------------------------------------------
// تخصيص الواجهة (ui.layout)
// ---------------------------------------------------------------------

class SectionCustom {
  const SectionCustom({this.name = '', this.desc = '', this.hidden = false, this.icon = '', this.color = '', this.group = ''});

  final String name;
  final String desc;
  final bool hidden;

  /// مفتاح أيقونة من layoutIcons (فارغ = الافتراضية).
  final String icon;

  /// مفتاح لون من layoutColors (فارغ = لون القسم).
  final String color;

  /// مفتاح مجموعته في شاشة الدخول (فارغ = دون مجموعة).
  final String group;

  bool get isEmpty =>
      name.trim().isEmpty && desc.trim().isEmpty && !hidden && icon.isEmpty && color.isEmpty && group.isEmpty;

  SectionCustom copyWith({String? name, String? desc, bool? hidden, String? icon, String? color, String? group}) => SectionCustom(
        name: name ?? this.name,
        desc: desc ?? this.desc,
        hidden: hidden ?? this.hidden,
        icon: icon ?? this.icon,
        color: color ?? this.color,
        group: group ?? this.group,
      );

  Map<String, dynamic> toJson() => {
        if (name.trim().isNotEmpty) 'name': name.trim(),
        if (desc.trim().isNotEmpty) 'desc': desc.trim(),
        if (hidden) 'hidden': true,
        if (icon.isNotEmpty) 'icon': icon,
        if (color.isNotEmpty) 'color': color,
        if (group.isNotEmpty) 'group': group,
      };

  factory SectionCustom.fromJson(Object? v) {
    if (v is! Map) return const SectionCustom();
    return SectionCustom(
      name: (v['name'] ?? '').toString(),
      desc: (v['desc'] ?? '').toString(),
      hidden: v['hidden'] == true,
      icon: (v['icon'] ?? '').toString(),
      color: (v['color'] ?? '').toString(),
      group: (v['group'] ?? '').toString(),
    );
  }
}

class PageCustom {
  const PageCustom({this.label = '', this.hidden = false, this.icon = '', this.section = ''});

  final String label;
  final bool hidden;

  /// مفتاح أيقونة من layoutIcons (فارغ = الافتراضية).
  final String icon;

  /// القسم المنقولة إليه الصفحة (فارغ = قسمها الأصلي).
  final String section;

  bool get isEmpty => label.trim().isEmpty && !hidden && icon.isEmpty && section.isEmpty;

  PageCustom copyWith({String? label, bool? hidden, String? icon, String? section}) => PageCustom(
        label: label ?? this.label,
        hidden: hidden ?? this.hidden,
        icon: icon ?? this.icon,
        section: section ?? this.section,
      );

  Map<String, dynamic> toJson() => {
        if (label.trim().isNotEmpty) 'label': label.trim(),
        if (hidden) 'hidden': true,
        if (icon.isNotEmpty) 'icon': icon,
        if (section.isNotEmpty) 'section': section,
      };

  factory PageCustom.fromJson(Object? v) {
    if (v is! Map) return const PageCustom();
    return PageCustom(
      label: (v['label'] ?? '').toString(),
      hidden: v['hidden'] == true,
      icon: (v['icon'] ?? '').toString(),
      section: (v['section'] ?? '').toString(),
    );
  }
}

/// مجموعة أقسام في شاشة الدخول بعنوانها.
class LayoutGroup {
  const LayoutGroup(this.key, this.name);

  final String key;
  final String name;

  Map<String, dynamic> toJson() => {'key': key, 'name': name.trim()};

  static LayoutGroup? fromJson(Object? v) {
    if (v is! Map) return null;
    final k = (v['key'] ?? '').toString();
    final n = (v['name'] ?? '').toString().trim();
    if (!RegExp(r'^g[a-z0-9]{1,12}$').hasMatch(k) || n.isEmpty) return null;
    return LayoutGroup(k, n);
  }
}

/// الأسماء الافتراضية لأقسام المنظومة (كما في شاشة الدخول قبل تخصيص المدير).
const Map<String, String> sectionDefaultNames = {
  'cycle': 'الدورة المستندية',
  'risks': 'المخاطر ومتابعة المشاريع',
  'swot': 'تحليل SWOT',
  'docs': 'الشؤون الفنية',
  'supervision': 'الإشراف',
  'heritage': 'الترميم والمباني التاريخية',
  'planning_qa': 'مكتب التخطيط وضمان الجودة',
  'safety': 'مكتب السلامة المهنية',
  'acceptance': 'المطابقة والاستلام',
  'chat': 'المراسلات الداخلية',
  'security': 'الأمن السيبراني',
  'print': 'الطباعة والتصدير',
  'manual': 'دليل الاستخدام',
  'stores': 'المخازن والأصول',
  'maintenance': 'الصيانة',
};

/// أنماط عرض شاشة الدخول: بطاقات بمؤشراتها، ومدمجة، وأيقونات.
const Map<String, String> hubStyleLabels = {'cards': 'بطاقات بالمؤشرات', 'compact': 'بطاقات مدمجة', 'icons': 'أيقونات'};

/// تخصيص المدير لأسماء الأقسام والصفحات وأوصافها وترتيبها وإخفائها، يطبَّق على الجميع فوراً.
class UiLayout {
  const UiLayout({
    this.sections = const {},
    this.sectionOrder = const [],
    this.pages = const {},
    this.pageOrder = const {},
    this.groups = const [],
    this.hubStyle = '',
  });

  final Map<String, SectionCustom> sections;
  final List<String> sectionOrder;
  final Map<int, PageCustom> pages;
  final Map<String, List<int>> pageOrder;

  /// مجموعات شاشة الدخول بترتيبها.
  final List<LayoutGroup> groups;

  /// نمط عرض شاشة الدخول (فارغ = بطاقات بالمؤشرات).
  final String hubStyle;

  static const empty = UiLayout();

  bool get isEmpty =>
      sections.values.every((s) => s.isEmpty) &&
      sectionOrder.isEmpty &&
      pages.values.every((p) => p.isEmpty) &&
      pageOrder.isEmpty &&
      groups.isEmpty &&
      (hubStyle.isEmpty || hubStyle == 'cards');

  /// نمط العرض الفعلي.
  String get style => hubStyleLabels.containsKey(hubStyle) ? hubStyle : 'cards';

  /// الصفحات المنقولة إلى غير أقسامها: رقم الصفحة ← القسم.
  Map<int, String> get movedPages => {
        for (final e in pages.entries)
          if (e.value.section.isNotEmpty) e.key: e.value.section,
      };

  LayoutGroup? group(String key) {
    for (final g in groups) {
      if (g.key == key) return g;
    }
    return null;
  }

  factory UiLayout.fromJson(Object? v) {
    if (v is! Map) return empty;
    final s = v['sections'];
    final p = v['pages'];
    final so = v['section_order'];
    final po = v['page_order'];
    final g = v['groups'];
    return UiLayout(
      sections: s is Map ? {for (final e in s.entries) e.key.toString(): SectionCustom.fromJson(e.value)} : const {},
      sectionOrder: so is List ? [for (final x in so) x.toString()] : const [],
      pages: p is Map
          ? {
              for (final e in p.entries)
                if (int.tryParse(e.key.toString()) != null) int.parse(e.key.toString()): PageCustom.fromJson(e.value)
            }
          : const {},
      pageOrder: po is Map
          ? {
              for (final e in po.entries)
                if (e.value is List) e.key.toString(): [for (final x in e.value as List) if (x is num) x.toInt()]
            }
          : const {},
      groups: g is List ? [for (final x in g) if (LayoutGroup.fromJson(x) case final lg?) lg] : const [],
      hubStyle: (v['hub_style'] ?? '').toString(),
    );
  }

  Map<String, dynamic> toJson() {
    final s = {for (final e in sections.entries) if (!e.value.isEmpty) e.key: e.value.toJson()};
    final p = {for (final e in pages.entries) if (!e.value.isEmpty) '${e.key}': e.value.toJson()};
    final po = {for (final e in pageOrder.entries) if (e.value.isNotEmpty) e.key: e.value};
    return {
      if (s.isNotEmpty) 'sections': s,
      if (sectionOrder.isNotEmpty) 'section_order': sectionOrder,
      if (p.isNotEmpty) 'pages': p,
      if (po.isNotEmpty) 'page_order': po,
      if (groups.isNotEmpty) 'groups': [for (final x in groups) x.toJson()],
      if (hubStyle.isNotEmpty && hubStyle != 'cards') 'hub_style': hubStyle,
    };
  }

  UiLayout copyWith({
    Map<String, SectionCustom>? sections,
    List<String>? sectionOrder,
    Map<int, PageCustom>? pages,
    Map<String, List<int>>? pageOrder,
    List<LayoutGroup>? groups,
    String? hubStyle,
  }) =>
      UiLayout(
        sections: sections ?? this.sections,
        sectionOrder: sectionOrder ?? this.sectionOrder,
        pages: pages ?? this.pages,
        pageOrder: pageOrder ?? this.pageOrder,
        groups: groups ?? this.groups,
        hubStyle: hubStyle ?? this.hubStyle,
      );

  /// يرتب عناصر حسب قائمة مفاتيح: المرتبة أولاً بترتيبها، والباقي بترتيبه الأصلي بعدها.
  static List<T> ordered<T, K>(List<T> items, List<K> order, K Function(T) keyOf) {
    if (order.isEmpty) return items;
    int rank(T x) {
      final i = order.indexOf(keyOf(x));
      return i < 0 ? 1000 + items.indexOf(x) : i;
    }

    return [...items]..sort((a, b) => rank(a).compareTo(rank(b)));
  }
}
