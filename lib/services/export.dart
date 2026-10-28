import 'dart:convert';
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
  final sheet = _sheet(excel, 'سجل المشاريع');

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

  return _save(excel, 'متابعة نماذج الدورة المستندية');
}

String _day(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

String _stamp(Object? v) {
  final d = v is DateTime ? v : (v == null ? null : DateTime.tryParse(v.toString()));
  if (d == null) return '';
  final l = d.toLocal();
  return '${_day(l)} ${l.hour.toString().padLeft(2, '0')}:${l.minute.toString().padLeft(2, '0')}';
}

Sheet _sheet(Excel excel, String sheetName) {
  final defaultSheet = excel.getDefaultSheet();
  if (defaultSheet != null && defaultSheet != sheetName) {
    excel.rename(defaultSheet, sheetName);
  }
  return excel[sheetName];
}

Future<String?> _save(Excel excel, String baseName) async {
  final bytes = excel.encode();
  if (bytes == null) throw StateError('تعذّر إنشاء ملف Excel');
  final data = Uint8List.fromList(bytes);
  final name = '$baseName ${_day(DateTime.now())}';
  final mobile = !kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS);
  if (mobile) {
    return FileSaver.instance.saveAs(name: name, bytes: data, ext: 'xlsx', mimeType: MimeType.microsoftExcel);
  }
  return FileSaver.instance.saveFile(name: name, bytes: data, ext: 'xlsx', mimeType: MimeType.microsoftExcel);
}

/// تصدير قائمة المستخدمين (للمدير وCISO). [security] من مركز الأمان: التحقق بخطوتين وآخر دخول.
Future<String?> exportUsersXlsx(AppState app, List<Map<String, dynamic>> security) async {
  final excel = Excel.createExcel();
  final sheet = _sheet(excel, 'المستخدمون');
  final sec = {for (final r in security) r['id'].toString(): r};
  sheet.appendRow(['ت', 'الاسم', 'بريد الدخول', 'الدور', 'القسم', 'الحالة', 'التحقق بخطوتين', 'آخر دخول', 'تاريخ إنشاء الحساب', 'معرّف الحساب']
      .map<CellValue?>((h) => TextCellValue(h))
      .toList());
  final users = app.people.values.toList()..sort((a, b) => a.displayName.compareTo(b.displayName));
  var i = 0;
  for (final u in users) {
    i++;
    final s = sec[u.id];
    final status = u.active ? 'مفعّل' : (u.role == null ? 'بانتظار التفعيل' : 'موقوف');
    sheet.appendRow(<CellValue?>[
      IntCellValue(i),
      TextCellValue(u.displayName),
      TextCellValue(u.email),
      TextCellValue(u.role?.label ?? ''),
      TextCellValue(u.role == AppRole.deptHead ? app.departmentName(u.department) : ''),
      TextCellValue(status),
      TextCellValue(s == null ? '' : (s['mfa'] == true ? 'مفعّل' : 'غير مفعّل')),
      TextCellValue(_stamp(s?['last_sign_in_at'])),
      TextCellValue(_stamp(u.createdAt)),
      TextCellValue(u.id),
    ]);
  }
  return _save(excel, 'مستخدمو المنظومة');
}

/// تصدير سطور سجل التدقيق المعروضة (للمدير وCISO).
Future<String?> exportAuditXlsx(AppState app, List<AuditEntry> rows, String Function(AuditEntry) describe) async {
  final excel = Excel.createExcel();
  final sheet = _sheet(excel, 'سجل التدقيق');
  sheet.appendRow(['ت', 'التاريخ والوقت', 'المستخدم', 'العملية', 'الوصف', 'المشروع أو العنصر', 'رمز العملية', 'التفاصيل']
      .map<CellValue?>((h) => TextCellValue(h))
      .toList());
  var i = 0;
  for (final r in rows) {
    i++;
    sheet.appendRow(<CellValue?>[
      IntCellValue(i),
      TextCellValue(_stamp(r.at)),
      TextCellValue(r.actorName.isEmpty ? 'النظام' : r.actorName),
      TextCellValue(r.action.split('.').first),
      TextCellValue(describe(r)),
      TextCellValue(r.projectLabel),
      TextCellValue(r.action),
      TextCellValue(r.detail.isEmpty ? '' : jsonEncode(r.detail)),
    ]);
  }
  return _save(excel, 'سجل التدقيق');
}
