import 'dart:io';

import 'package:dc_app/manual.dart';
import 'package:dc_app/screens/hub.dart' show appSections;
import 'package:flutter_test/flutter_test.dart';

/// قواعد بقاء دليل الاستخدام محدّثاً: كل صفحة وقسم لهما فصل، وكل فصل موجود وعنوانه مطابق،
/// وكل ترحيل لقاعدة البيانات مذكور في «ما الجديد». يفشل البناء إن خولفت.
void main() {
  test('كل فصل في الفهرس له ملف يبدأ بعنوانه نفسه', () {
    for (final c in manualChapters) {
      final f = File(c.asset);
      expect(f.existsSync(), isTrue, reason: 'ملف الفصل غير موجود: ${c.asset}');
      final first = f.readAsLinesSync().firstWhere((l) => l.trim().isNotEmpty);
      expect(first.trim(), '# ${c.title}', reason: 'عنوان ${c.asset} لا يطابق الفهرس في lib/manual.dart');
    }
    final ids = manualChapters.map((c) => c.id).toSet();
    expect(ids.length, manualChapters.length, reason: 'معرّف فصل مكرر');
    // لا ملف فصل خارج الفهرس
    for (final f in Directory('assets/manual').listSync().whereType<File>()) {
      final name = f.uri.pathSegments.last;
      if (!name.endsWith('.md') || name == 'changelog.md') continue;
      expect(ids.contains(name.replaceAll('.md', '')), isTrue, reason: 'الفصل $name غير مضاف إلى manualChapters');
    }
  });

  test('كل صفحة في القوائم مربوطة بفصل موجود', () {
    final src = File('lib/screens/home_shell.dart').readAsStringSync();
    final tabsBlock = src.substring(src.indexOf('class Tabs {'), src.indexOf('}', src.indexOf('class Tabs {')));
    final ids = RegExp(r'static const \w+ = (\d+);').allMatches(tabsBlock).map((m) => int.parse(m.group(1)!)).toList();
    expect(ids, isNotEmpty);
    // صفحات الإدارة في كل قسم: (الأساس + 8) للمساعد و(الأساس + 9) للوحة التحكم
    final bases = RegExp(r'_adminDests\(app, (\d+)\)').allMatches(src).map((m) => int.parse(m.group(1)!)).toSet();
    final all = {...ids, for (final b in bases) ...[b + 8, b + 9]};
    for (final t in all) {
      final a = manualTabAnchors[t];
      expect(a, isNotNull, reason: 'الصفحة رقم $t بلا فصل في manualTabAnchors (lib/manual.dart)');
      expect(manualChapter(a!), isNotNull, reason: 'الصفحة $t مربوطة بفصل غير موجود: $a');
    }
  });

  test('كل قسم رئيسي له فصل', () {
    for (final s in appSections) {
      final a = manualSectionAnchors[s.$1];
      expect(a, isNotNull, reason: 'القسم ${s.$1} بلا فصل في manualSectionAnchors');
      expect(manualChapter(a!), isNotNull);
    }
  });

  test('آخر ترحيل لقاعدة البيانات مذكور في «ما الجديد»', () {
    final nums = Directory('supabase/migrations')
        .listSync()
        .whereType<File>()
        .map((f) => RegExp(r'^\d{8}(\d{6})_').firstMatch(f.uri.pathSegments.last))
        .whereType<RegExpMatch>()
        .map((m) => int.parse(m.group(1)!))
        .toList()
      ..sort();
    final latest = nums.last;
    final log = File(manualChangelogAsset).readAsStringSync();
    final mentioned = RegExp(r'الترحيل(ات)?[^\n]*').allMatches(log).any((m) => RegExp('\\b$latest\\b').hasMatch(m.group(0)!));
    expect(mentioned, isTrue, reason: 'الترحيل $latest غير مذكور في assets/manual/changelog.md');
  });

  test('الفصول سليمة: الصناديق مغلقة، والقيم الحية معروفة، والإحالات لفصول موجودة', () {
    const known = {
      'APP_VERSION', 'MANUAL_UPDATED', 'FORMS_COUNT', 'FORMS_REQ', 'FORMS_TODO', 'FORMS_PCT10', 'FORMS_TABLE', 'LEVELS_TABLE', //
      'RISK_MATRIX', 'CHAT_MAX_MB', 'CHAT_EDIT_MIN', 'REF_TABLE', 'SPI_AHEAD', 'SPI_OK', 'SPI_WARN', //
      'PM_ALERT_DAYS', 'ST_DONE', 'ST_WIP', 'ST_TODO', 'ST_NA', 'GI_RATE', 'GF_RATE', 'RET_RATE', 'STR_EXPIRY_DAYS', 'STR_SEPARATION',
    };
    final maxChapter = manualChapters.map((c) => c.number).reduce((a, b) => a > b ? a : b);
    for (final c in [...manualChapters.map((c) => c.asset), manualChangelogAsset]) {
      final text = File(c).readAsStringSync();
      final opens = RegExp(r'^:::(formula|example|note|warning)', multiLine: true).allMatches(text).length;
      final closes = RegExp(r'^:::\s*$', multiLine: true).allMatches(text).length;
      expect(opens, closes, reason: 'صندوق غير مغلق في $c');
      for (final m in RegExp(r'\{\{([A-Z_0-9]+)\}\}').allMatches(text)) {
        expect(known.contains(m.group(1)), isTrue, reason: 'قيمة حية غير معروفة {{${m.group(1)}}} في $c');
      }
      for (final m in RegExp(r'الفصل (\d+)').allMatches(text)) {
        expect(int.parse(m.group(1)!) <= maxChapter, isTrue, reason: 'إحالة إلى فصل غير موجود في $c: ${m.group(0)}');
      }
      expect(parseManual(text), isNotEmpty);
    }
  });

  test('المحلل: العناوين والقوائم والجداول والصناديق والعناصر الحية', () {
    const md = '# عنوان\n\nفقرة **عريضة** و*مائلة*\nسطر ثانٍ\n\n- أ\n  - ب\n1. أول\n\n| س | ص |\n| --- | --- |\n| 1 | 2 \\| 3 |\n\n'
        ':::formula معادلة: س\n**ن** = 1 + 2\n:::\n\n{{RISK_MATRIX}}\n';
    final b = parseManual(md);
    expect(b[0], isA<MHeading>());
    expect((b[1] as MParagraph).text, contains('\n'));
    final list = b[2] as MList;
    expect(list.items.map((i) => i.depth), [0, 1, 0]);
    expect(list.items.last.ordered, isTrue);
    final t = b[3] as MTable;
    expect(t.rows.first, ['1', '2 | 3']);
    final box = b[4] as MBox;
    expect(box.kind, 'formula');
    expect(box.title, 'معادلة: س');
    expect(b[5], isA<MWidget>());
    expect(parseInline('أ **ب** ج').map((x) => x.$2), [false, true, false]);
  });

  test('البحث يطبّع الهمزات والتاء المربوطة', () {
    expect(manualCount(manualPlain('**الإنجاز** والانجاز والإنجاز'), 'الانجاز'), 3);
    expect(manualCount('مراسلة متأخرة', 'متاخره'), 1);
  });

  test('الجداول الحية', () {
    final forms = manualFormsTable(stageNames: ['أ', 'ب'], forms: [
      (name: 'نموذج 1', stage: 0, sensitive: true, responsible: ['office_staff']),
      (name: 'نموذج 2', stage: 1, sensitive: false, responsible: ['contracts', 'head:technical']),
    ]);
    final t = parseManual(forms).single as MTable;
    expect(t.rows.length, 4);
    expect(t.rows[1], ['1', 'نموذج 1', 'موظفو مكتب المدير', '●']);
    final levels = manualLevelsTable([
      (name: 'منخفض', min: 1, action: 'مراقبة', reviewDays: 90),
      (name: 'مرتفع', min: 13, action: 'تصعيد', reviewDays: 14),
    ]);
    final lt = parseManual(levels).single as MTable;
    expect(lt.rows.first[1], '13 – 25');
    expect(lt.rows.last[1], '1 – 12');
  });
}
