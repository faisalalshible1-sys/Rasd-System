import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:file_saver/file_saver.dart';
import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;

import '../app_state.dart';
import '../models.dart';

/// UC-05: تصدير سجل المشاريع إلى ملف Excel بنفس أعمدة الملف الأصلي.
/// يُرجع مسار الملف أو اسمه، أو null إذا ألغى المستخدم الحفظ.
Future<String?> exportProjectsXlsx(AppState app, List<Project> projects) async {
  final excel = Excel.createExcel();
  const sheetName = 'سجل المشاريع';
  final defaultSheet = excel.getDefaultSheet();
  if (defaultSheet != null && defaultSheet != sheetName) {
    excel.rename(defaultSheet, sheetName);
  }
  final sheet = excel[sheetName];

  final header = <String>['ت', 'رقم التكليف', 'رمز المشروع', 'اسم المشروع', 'مالك المشروع', 'اسم الشركة', 'القسم المشرف'];
  for (final d in app.formDefs) {
    header.add(d.name);
    final f = d.engineerField;
    if (f != null) header.add(engineerFieldLabel(f));
  }
  header.addAll(['قيمة التعاقد', 'الدفعة الأولى', 'الدفعة الثانية', 'الدفعة الختامية',
    'الضمان الابتدائي ${rateText(guaranteeInitialRate)}', 'الضمان النهائي ${rateText(guaranteeFinalRate)}', 'قيمة الخصومات']);
  final fields = [...app.activeFields]..sort((a, b) => a.sort.compareTo(b.sort));
  header.addAll(fields.map((f) => f.label));
  header.addAll(['عدد النماذج المكتملة', 'نسبة الإنجاز %', 'المرحلة الحالية', 'المستند التالي المطلوب', 'حالة الدورة', 'ملاحظات', 'آخر تحديث']);
  sheet.appendRow(header.map<CellValue?>((h) => TextCellValue(h)).toList());

  var i = 0;
  for (final p in projects) {
    i++;
    final pr = app.progressOf(p);
    final row = <CellValue?>[
      IntCellValue(i),
      TextCellValue(p.assignNo),
      TextCellValue(p.code),
      TextCellValue(p.name),
      TextCellValue(p.owner),
      TextCellValue(p.company),
      TextCellValue(app.departmentName(p.department)),
    ];
    for (final d in app.formDefs) {
      final s = app.statuses[p.id]?[d.key];
      row.add(TextCellValue(s == null ? '' : s.label));
      final f = d.engineerField;
      if (f != null) row.add(TextCellValue(p.engineer(f)));
    }
    CellValue? money(double? v) => v == null ? TextCellValue('') : DoubleCellValue(v);
    row.addAll([
      money(p.contractValue),
      money(p.paymentFirst),
      money(p.paymentSecond),
      money(p.paymentFinal),
      money(p.guaranteeInitial),
      money(p.guaranteeFinal),
      money(p.deductions),
    ]);
    for (final f in fields) {
      final v = p.extra[f.key];
      row.add(v is num ? DoubleCellValue(v.toDouble()) : TextCellValue(v == null ? '' : f.display(v)));
    }
    final u = p.updatedAt?.toLocal();
    row.addAll([
      IntCellValue(pr.done),
      DoubleCellValue((pr.pct * 1000).round() / 10),
      TextCellValue(stageName(pr.stage)),
      TextCellValue(pr.next?.name ?? '—'),
      TextCellValue(pr.cycle.label),
      TextCellValue(p.notes),
      TextCellValue(u == null ? '' : '${u.year}-${u.month.toString().padLeft(2, '0')}-${u.day.toString().padLeft(2, '0')}'),
    ]);
    sheet.appendRow(row);
  }

  final bytes = excel.encode();
  if (bytes == null) throw StateError('تعذّر إنشاء ملف Excel');
  final data = Uint8List.fromList(bytes);
  final now = DateTime.now();
  final name = 'متابعة نماذج الدورة المستندية ${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

  final mobile = !kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS);
  if (mobile) {
    return FileSaver.instance.saveAs(name: name, bytes: data, ext: 'xlsx', mimeType: MimeType.microsoftExcel);
  }
  return FileSaver.instance.saveFile(name: name, bytes: data, ext: 'xlsx', mimeType: MimeType.microsoftExcel);
}
