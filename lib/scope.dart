// =====================================================================
// نطاق المستخدم (الترحيل 34: عزل الأقسام)
//
// قاعدة البيانات هي التي تقرر ما يُقرأ (سياسات RLS)، وهذا النطاق نسختها للواجهة: أي الأقسام تظهر
// وأي الوحدات وأي النماذج مسندة إليه. المدير وموظفو مكتبه يرون كل الأقسام للمتابعة، وكل مستخدم آخر قسمه وحده.
// =====================================================================

/// الأدوات المشتركة لكل الأقسام: المراسلات الداخلية، ودليل الاستخدام، والطباعة والتصدير.
const Set<String> sharedSections = {'chat', 'manual', 'print'};

/// أقسام العمل بترتيبها في الشاشة الرئيسية.
const List<String> workSectionOrder = [
  'cycle', 'risks', 'swot', 'docs', 'supervision', 'heritage', 'planning_qa', 'safety', 'acceptance', 'stores', 'maintenance', 'procurement', 'accounts', //
];

class UserScope {
  const UserScope({
    this.sections = const {},
    this.units = const {},
    this.forms = const {},
    this.supervised = const {},
    this.full = false,
    this.allProjects = false,
  });

  /// أقسام الشاشة الرئيسية التي يراها (ومعها المشتركة والأمن لمن يدقق).
  final Set<String> sections;

  /// الوحدات التي يطّلع على سجلاتها.
  final Set<String> units;

  /// نماذج الدورة المسندة إليه في كل العقود.
  final Set<String> forms;

  /// العقود التي يشرف عليها قسمه (يراها بتفاصيلها).
  final Set<String> supervised;

  /// المدير وموظفو مكتبه: كل الأقسام.
  final bool full;

  /// يرى كل العقود بتفاصيلها (مكتب المدير ومكتب العقود).
  final bool allProjects;

  /// أقسام العمل التي يراها، بترتيب الشاشة الرئيسية (دون الأدوات المشتركة والأمن).
  List<String> get workSections => [for (final s in workSectionOrder) if (sections.contains(s)) s];

  static Set<String> _set(Object? v) => v is List ? {for (final e in v) if (e != null) '$e'} : <String>{};

  factory UserScope.fromJson(Object? raw) {
    final m = raw is Map ? raw : const {};
    return UserScope(
      sections: _set(m['sections']),
      units: _set(m['units']),
      forms: _set(m['forms']),
      supervised: _set(m['supervised']),
      full: m['full'] == true,
      allProjects: m['all_projects'] == true,
    );
  }
}
