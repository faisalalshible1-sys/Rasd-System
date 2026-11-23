import 'package:dc_app/app_state.dart';
import 'package:dc_app/manual.dart';
import 'package:dc_app/models.dart';
import 'package:dc_app/scope.dart';
import 'package:flutter_test/flutter_test.dart';

/// عزل الأقسام (الترحيل 34): نطاق المستخدم كما تعيده my_scope()، وأساسيات العقود، وصفحات المهام المسندة،
/// وفصول الدليل بحسب الأقسام.
void main() {
  test('نطاق رئيس الشؤون الفنية: قسمه وحده والأدوات المشتركة', () {
    final s = UserScope.fromJson({
      'sections': ['chat', 'docs', 'manual', 'print'],
      'units': ['technical'],
      'forms': ['f20', 'f19'],
      'supervised': <String>[],
      'full': false,
      'all_projects': false,
    });
    expect(s.workSections, ['docs']);
    expect(s.forms, {'f20', 'f19'});
    expect(s.units, {'technical'});
    expect(s.full, isFalse);
    expect(s.allProjects, isFalse);
  });

  test('نطاق مكتب المدير: كل أقسام العمل بترتيب الشاشة الرئيسية', () {
    final s = UserScope.fromJson({
      'sections': [...workSectionOrder.reversed, 'chat', 'manual', 'print'],
      'full': true,
      'all_projects': true,
    });
    expect(s.workSections, workSectionOrder);
    expect(s.full, isTrue);
  });

  test('نطاق فارغ أو تالف لا يكسر الواجهة', () {
    for (final raw in [null, 'x', 3, <String, dynamic>{}]) {
      final s = UserScope.fromJson(raw);
      expect(s.sections, isEmpty);
      expect(s.workSections, isEmpty);
      expect(s.full, isFalse);
    }
  });

  test('أساسيات العقد من project_refs() دون المالية', () {
    final p = Project.ref({
      'id': 'p1', 'assign_no': '12', 'code': 'TR-1', 'name': 'صيانة طريق', 'owner': 'البلدية', 'company': 'شركة البناء',
      'department': 'restoration', 'contract_no': '5/2026', 'sort_order': 3,
    });
    expect(p.limited, isTrue);
    expect(p.contractValue, isNull);
    expect(p.executedValue, isNull);
    expect(p.label, 'عقد 5/2026 — صيانة طريق');
    expect(p.department, 'restoration');
    expect(Project.fromMap({'id': 'p2', 'name': 'كامل'}).limited, isFalse);
  });

  test('صفحات «المهام المسندة» في أقسامها (183–188)', () {
    for (final (i, s) in AppState.assignedSections.indexed) {
      expect(AppState.assignedTabOf(s), 183 + i);
      expect(AppState.sectionOf(183 + i), s);
    }
    expect(AppState.assignedTabOf('cycle'), -1);
    expect(AppState.assignedTabOf('security'), -1);
    // لا تتداخل مع صفحات الأفكار ولا الأمن
    expect(AppState.sectionOf(182), 'manual');
    expect(AppState.sectionOf(170), isNot('docs'));
  });

  test('فصول الدليل: العامة وفصول أقسام المستخدم وحدها', () {
    final tech = manualChaptersFor({'docs', 'chat', 'manual', 'print'}.contains);
    final ids = {for (final c in tech) c.id};
    expect(ids, containsAll(['00_about', '03_roles', '17_docs', '28_prices', '29_schedule', '32_section_isolation']));
    expect(ids, isNot(contains('04_cycle')));
    expect(ids, isNot(contains('07_finance')));
    expect(ids, isNot(contains('27_security')));
    final ciso = {for (final c in manualChaptersFor({'security', 'chat', 'manual', 'print'}.contains)) c.id};
    expect(ciso, contains('27_security'));
    expect(ciso, isNot(contains('17_docs')));
    expect(manualChaptersFor((_) => true).length, manualChapters.length);
    for (final id in manualChapterSections.keys) {
      expect(manualChapter(id), isNotNull, reason: 'فصل غير موجود في manualChapterSections: $id');
    }
  });
}
