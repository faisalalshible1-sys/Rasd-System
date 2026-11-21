import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:dc_app/models.dart';
import 'package:dc_app/print/model.dart';
import 'package:dc_app/print/table_editor.dart';
import 'package:dc_app/print/xlsx_writer.dart';
import 'package:dc_app/rasd.dart';
import 'package:dc_app/screens/security_center.dart' show postureScore;
import 'package:flutter_test/flutter_test.dart';

/// اختبارات «منظومة رصد»: الرقم الإشاري (يطابق ref_format في قاعدة البيانات)، والمعادلات وExcel الحي،
/// وتخصيص الواجهة، والصلاحيات الدقيقة، ومؤشر الوضع الأمني — كما تشرحها الفصول 3 و23 و25 و27 من الدليل.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('الرقم الإشاري', () {
    test('الرموز كما في اختبار قاعدة البيانات', () {
      expect(
        formatRef('{DD}-{KIND}-{DEPT}-{SECTION}-{SEQ}', seq: 5, pad: 2, at: DateTime(2026, 3, 4), ctx: const {'kind': 'ncr', 'dept': 'supervision'}, codes: const {'ncr': 'ع.م'}),
        '04-ع.م-supervision---05',
      );
      expect(formatRef('{YYYY}/{SEQ:8}', seq: 42, pad: 4, at: DateTime(2027, 1, 1)), '2027/00000042');
      expect(formatRef('ع/{CODE}/{YY}{MM}/{SEQ:3}', seq: 7, pad: 5, at: DateTime(2026, 11, 21), ctx: const {'code': '990/2026'}), 'ع/990-2026/2611/007');
    });

    test('مثال الدليل: الصيغة الأساسية للمطبوعات', () {
      const s = RefScheme(key: 'print', name: 'المطبوعات', pattern: 'م.ش.هـ/{SECTION}/{YYYY}/{SEQ}', codes: {'cycle': 'د.م', 'risks': 'م.م'});
      expect(s.preview(at: DateTime(2026, 11, 21), ctx: const {'section': 'cycle'}), 'م.ش.هـ/د.م/2026/0001');
      expect(s.preview(at: DateTime(2026, 11, 21), seq: 2, ctx: const {'section': 'risks'}), 'م.ش.هـ/م.م/2026/0002');
      expect(s.masked(ctx: const {'section': 'cycle'}), startsWith('م.ش.هـ/د.م/'));
      expect(s.masked(ctx: const {'section': 'cycle'}), endsWith('/####'));
    });

    test('الرقم الصادر يُطبع كما هو دون البادئة', () {
      final c = PrintConfig();
      final ctx = PrintContext(printedBy: 'أ', orgName: 'ب', at: DateTime(2026, 11, 16, 19, 45, 30));
      expect(ctx.refText(c), 'م.ش.هـ/2026/1116/194530');
      expect(ctx.withRef('م.ش.هـ/د.م/2026/0001').refText(c), 'م.ش.هـ/د.م/2026/0001');
    });
  });

  group('المعادلات وExcel الحي', () {
    num? v(Map<String, num?> m, String k) => m[k];

    test('تقييم المعادلات', () {
      expect(Formula.eval('{probability}*{impact}', (k) => v({'probability': 4, 'impact': 5}, k)), 20);
      expect(Formula.eval('{actual}-{planned}', (k) => v({'actual': 50, 'planned': 33.3}, k)), 16.7);
      expect(Formula.eval('{paid}/{value}*100', (k) => v({'paid': 250, 'value': 1000}, k)), 25);
      expect(Formula.eval('{paid}/{value}*100', (k) => v({'paid': 250, 'value': 0}, k)), isNull);
      expect(Formula.eval('max({net}-{paid},0)', (k) => v({'net': 100, 'paid': 130}, k)), 0);
      expect(Formula.eval('max({net}-{paid},0)', (k) => v({'net': 100, 'paid': 30}, k)), 70);
      expect(Formula.eval('({a}+{b})*2', (k) => v({'a': 1, 'b': 2}, k)), 6);
      expect(Formula.eval('{a}+{b}', (k) => null), isNull);
      expect(Formula.refs('max({net}-{paid},0)'), ['net', 'paid']);
      expect(Formula.toExcel('max({net}-{paid},0)', (k) => k == 'net' ? 'E5' : 'F5'), 'IFERROR(MAX(E5-F5,0),"")');
    });

    final t = ExportTable(
      sourceId: 'risks:register',
      title: 'سجل المخاطر',
      columns: const [
        ExportColumn('code', 'الرمز'),
        ExportColumn('probability', 'الاحتمال', type: ColType.number),
        ExportColumn('impact', 'الأثر', type: ColType.number),
        ExportColumn('score', 'الدرجة', type: ColType.number, formula: '{probability}*{impact}'),
      ],
      rows: [
        ['R-1', 4, 5, null],
        ['R-2', 2, 3, null],
      ],
    ).recompute();

    test('الأعمدة المحسوبة تُحسب، وتبقى ثابتة إن غاب ما تعتمد عليه', () {
      expect(t.rows[0][3], 20);
      expect(t.rows[1][3], 6);
      expect(t.select(['code', 'probability', 'impact', 'score']).columns.last.computed, isTrue);
      final partial = t.select(['code', 'score']);
      expect(partial.columns.last.computed, isFalse);
      expect(partial.rows[0][1], 20);
    });

    test('تحرير القيمة يعيد الحساب والمجموع', () {
      final rows = [for (final r in t.rows) [...r]];
      rows[0][1] = parseCell('٣', ColType.number);
      final e = t.copyWith(rows: rows).recompute();
      expect(e.rows[0][3], 15);
      expect(e.total(3), 21);
      expect(parseCell('1,250.5', ColType.money), 1250.5);
      expect(parseCell('45٪', ColType.percent), 45);
      expect(parseCell('نص', ColType.number), 'نص');
    });

    test('Excel: معادلة حية في كل صف وورقة تحليل', () {
      final bytes = buildXlsx(t, PrintConfig(), PrintContext(printedBy: 'أ', orgName: 'ب'));
      final zip = ZipDecoder().decodeBytes(bytes);
      final sheets = zip.files.where((f) => f.name.startsWith('xl/worksheets/sheet') && f.name.endsWith('.xml')).toList();
      expect(sheets.length, 2);
      final all = sheets.map((f) => utf8.decode(f.content as List<int>)).join();
      expect(all, contains('IFERROR(C'));
      expect(all, contains('*D'));
      expect(all, contains('AVERAGE('));
      for (final f in sheets) {
        expect(utf8.decode(f.content as List<int>), contains('rightToLeft="1"'));
      }
      final wb = utf8.decode(zip.findFile('xl/workbook.xml')!.content as List<int>);
      expect(wb, contains('التحليل'));
    });
  });

  group('تخصيص الواجهة', () {
    test('يُحفظ ويُقرأ كما هو، ويُرتّب بحسب ترتيب المدير', () {
      const l = UiLayout(
        sections: {'risks': SectionCustom(name: 'المخاطر والفرص', hidden: true), 'cycle': SectionCustom()},
        sectionOrder: ['risks', 'cycle'],
        pages: {40: PageCustom(label: 'القيادة'), 41: PageCustom()},
        pageOrder: {'risks': [41, 40]},
      );
      final j = l.toJson();
      expect(j['sections'], {'risks': {'name': 'المخاطر والفرص', 'hidden': true}});
      expect(j['pages'], {'40': {'label': 'القيادة'}});
      final back = UiLayout.fromJson(jsonDecode(jsonEncode(j)));
      expect(back.sections['risks']?.name, 'المخاطر والفرص');
      expect(back.pageOrder['risks'], [41, 40]);
      expect(UiLayout.ordered(['cycle', 'risks', 'swot'], back.sectionOrder, (k) => k), ['risks', 'cycle', 'swot']);
      expect(UiLayout.ordered([40, 41, 42], const <int>[], (k) => k), [40, 41, 42]);
      expect(UiLayout.fromJson(null).isEmpty, isTrue);
    });
  });

  group('الصلاحيات الدقيقة', () {
    test('الفهرس: النماذج المفعّلة والمستندات والإشراف وأنواع السجلات وSWOT', () {
      const forms = [
        FormDef(key: 'f01', name: 'أمر بالتعاقد', stage: 0, sort: 1, sensitive: true, responsible: ['office_staff']),
        FormDef(key: 'f02', name: 'موقوف', stage: 0, sort: 2, sensitive: false, responsible: [], active: false),
      ];
      final c = grantCatalog(forms);
      final keys = c.map((g) => g.key).toSet();
      expect(keys, containsAll(['form:f01', 'docs:boq', 'docs:letter', 'docs:design', 'supervision:reports', 'unit:ncr', 'swot']));
      expect(keys.contains('form:f02'), isFalse);
      expect(c.firstWhere((g) => g.key == 'form:f01').note, contains('المالية'));
      for (final k in keys) {
        expect(RegExp(r'^(form:[a-z0-9_]{1,40}|docs:(boq|letter|design)|supervision:reports|unit:[a-z_]{2,40}|swot)$').hasMatch(k), isTrue,
            reason: 'نطاق لا تقبله قاعدة البيانات: $k');
      }
      expect(grantLabel('form:f02', forms), 'موقوف (موقوف)');
    });
  });

  group('مؤشر الوضع الأمني', () {
    test('مثال الدليل: عشرون فحصاً وفشل عالٍ ومتوسط', () {
      final checks = [
        for (var i = 0; i < 8; i++) {'severity': 'high', 'ok': i != 0},
        for (var i = 0; i < 6; i++) {'severity': 'medium', 'ok': i != 0},
        for (var i = 0; i < 6; i++) {'severity': 'low', 'ok': true},
      ];
      expect(postureScore(checks), 88);
      expect(postureScore(const []), 100);
    });
  });
}
