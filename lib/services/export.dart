import 'dart:convert';
import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:file_saver/file_saver.dart';
import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;

import '../app_state.dart';
import '../models.dart';

/// UC-05: تصدير سجل العقود إلى ملف Excel (أعمدة الملف الأصلي، ورقم العقد وأعماله ومهندسوه بأرقام تكليفهم).
/// يُرجع مسار الملف أو اسمه، أو null إذا ألغى المستخدم الحفظ.
Future<String?> exportProjectsXlsx(AppState app, List<Project> projects) async {
  final excel = Excel.createExcel();
  final sheet = _sheet(excel, 'سجل العقود');
  final base = app.v3Ready ? 'من المنفذ' : 'من التعاقد';

  String engineersText(Project p, String field) {
    if (!app.v3Ready) return p.engineer(field);
    return app
        .engineersOf(p.id, field.substring(4))
        .map((e) => e.assignNo.isEmpty ? e.name : '${e.name} (${e.assignNo})')
        .join('، ');
  }

  final header = <String>['ت', 'رقم العقد', 'رقم التكليف', 'رمز المشروع', 'اسم المشروع', 'مالك المشروع', 'الشركات', 'الأعمال', 'القسم المشرف'];
  for (final d in app.formDefs) {
    header.add(d.name);
    final f = d.engineerField;
    if (f != null) header.add(engineerFieldLabel(f));
  }
  header.addAll(['قيمة الأعمال التعاقدية', 'قيمة الأعمال المنفذة', 'الدفعة الأولى', 'الدفعة الثانية', 'الدفعة الختامية',
    'الضمان الابتدائي ${rateText(guaranteeInitialRate)} $base', 'الضمان النهائي ${rateText(guaranteeFinalRate)} $base', 'قيمة الخصومات']);
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
      TextCellValue(p.contractNo),
      TextCellValue(p.assignNo),
      TextCellValue(p.code),
      TextCellValue(p.name),
      TextCellValue(p.owner),
      TextCellValue(app.companiesOf(p).join('، ')),
      TextCellValue(app.worksOf(p.id).map((w) => w.display.isEmpty ? w.refNo : w.display).join(' | ')),
      TextCellValue(app.departmentName(p.department)),
    ];
    for (final d in app.formDefs) {
      final s = app.statuses[p.id]?[d.key];
      row.add(TextCellValue(s == null ? '' : s.label));
      final f = d.engineerField;
      if (f != null) row.add(TextCellValue(engineersText(p, f)));
    }
    CellValue? money(double? v) => v == null ? TextCellValue('') : DoubleCellValue(v);
    row.addAll([
      money(p.contractValue),
      money(p.executedValue),
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

  if (app.v3Ready) {
    final ids = {for (final p in projects) p.id};
    final ws = excel['أعمال العقود'];
    ws.appendRow(['رقم العقد', 'رقم التكليف', 'اسم المشروع', 'العمل', 'الشركة', 'الرقم المرجعي', 'ملاحظات']
        .map<CellValue?>((h) => TextCellValue(h))
        .toList());
    for (final p in projects) {
      for (final w in app.worksOf(p.id)) {
        ws.appendRow(<CellValue?>[
          TextCellValue(p.contractNo),
          TextCellValue(p.assignNo),
          TextCellValue(p.name),
          TextCellValue(w.title),
          TextCellValue(w.company),
          TextCellValue(w.refNo),
          TextCellValue(w.notes),
        ]);
      }
    }
    final es = excel['المهندسون والتكليفات'];
    es.appendRow(['رقم العقد', 'رقم التكليف (العقد)', 'اسم المشروع', 'الاختصاص', 'اسم المهندس', 'رقم تكليف المهندس', 'تاريخ التكليف', 'العمل المرتبط']
        .map<CellValue?>((h) => TextCellValue(h))
        .toList());
    for (final e in app.engineers.where((e) => ids.contains(e.projectId))) {
      final p = app.project(e.projectId);
      final w = app.work(e.workId);
      es.appendRow(<CellValue?>[
        TextCellValue(p?.contractNo ?? ''),
        TextCellValue(p?.assignNo ?? ''),
        TextCellValue(p?.name ?? ''),
        TextCellValue(engineerKindLabel(e.kind)),
        TextCellValue(e.name),
        TextCellValue(e.assignNo),
        TextCellValue(e.assignedOn == null ? '' : dbDate(e.assignedOn!)),
        TextCellValue(w == null ? '' : (w.display.isEmpty ? w.refNo : w.display)),
      ]);
    }
  }

  return _save(excel, 'متابعة العقود والدورة المستندية');
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

/// تصدير التقرير المالي: ملخص، والعقود، والمستخلصات، وأوامر التغيير، والتأمينات والضمانات.
Future<String?> exportFinanceXlsx(AppState app, List<Project> projects) async {
  final excel = Excel.createExcel();
  CellValue? m(double? v) => v == null ? TextCellValue('') : DoubleCellValue(v);
  List<CellValue?> head(List<String> h) => h.map<CellValue?>((x) => TextCellValue(x)).toList();
  final ids = {for (final p in projects) p.id};
  final ex = app.extracts.where((x) => ids.contains(x.projectId)).toList();
  final vars = app.variations.where((v) => ids.contains(v.projectId)).toList();
  double sum(Iterable<double> xs) => xs.fold(0, (a, b) => a + b);

  // الملخص
  final summary = _sheet(excel, 'الملخص المالي');
  final counted = ex.where((x) => x.counted);
  final rows = <(String, double)>[
    ('إجمالي القيم التعاقدية', sum(projects.map((p) => p.contractValue ?? 0))),
    ('صافي أوامر التغيير', sum(projects.map((p) => p.variationsNet))),
    ('الإجمالي بعد أوامر التغيير', sum(projects.map((p) => p.adjustedValue ?? 0))),
    ('قيمة الأعمال المنفذة', sum(projects.map((p) => p.executedValue ?? 0))),
    ('إجمالي المستخلصات المعتمدة', sum(counted.map((x) => x.gross))),
    ('إجمالي الاستقطاعات', sum(counted.map((x) => x.deductionsTotal))),
    ('صافي المستخلصات', sum(counted.map((x) => x.net))),
    ('المدفوع', sum(projects.map((p) => p.paidTotal))),
    ('مستحق غير مدفوع', sum(projects.map((p) => p.outstanding))),
    ('المتبقي من الأعمال', sum(projects.map((p) => p.remainingWork ?? 0))),
    ('المتبقي للدفع', sum(projects.map((p) => p.remainingToPay ?? 0))),
    ('التأمين المحتجز', sum(projects.map((p) => p.retentionHeld))),
    ('الضمان الابتدائي ${rateText(guaranteeInitialRate)}', sum(projects.map((p) => p.guaranteeInitial ?? 0))),
    ('الضمان النهائي ${rateText(guaranteeFinalRate)}', sum(projects.map((p) => p.guaranteeFinal ?? 0))),
  ];
  summary.appendRow(head(['البند', 'القيمة ($currencyLabel)']));
  for (final r in rows) {
    summary.appendRow(<CellValue?>[TextCellValue(r.$1), DoubleCellValue(r.$2)]);
  }
  summary.appendRow(<CellValue?>[TextCellValue('عدد العقود'), IntCellValue(projects.length)]);
  summary.appendRow(<CellValue?>[TextCellValue('عدد المستخلصات المعتمدة'), IntCellValue(counted.length)]);
  summary.appendRow(<CellValue?>[TextCellValue('تاريخ التقرير'), TextCellValue(_stamp(DateTime.now()))]);

  // العقود
  final cs = excel['العقود'];
  cs.appendRow(head(['ت', 'رقم العقد', 'رقم التكليف', 'اسم المشروع', 'الشركات', 'المالك', 'القيمة التعاقدية', 'مصدرها', 'صافي أوامر التغيير',
    'القيمة بعد التغيير', 'المنفذ', 'مصدره', 'نسبة التنفيذ %', 'عدد المستخلصات', 'إجمالي المستخلصات', 'صافيها', 'المدفوع', 'نسبة الدفع %',
    'مستحق غير مدفوع', 'المتبقي من الأعمال', 'المتبقي للدفع', 'التأمين المحتجز', 'الضمان الابتدائي', 'الضمان النهائي', 'الخصومات اليدوية']));
  var i = 0;
  for (final p in projects) {
    i++;
    final adj = p.adjustedValue;
    cs.appendRow(<CellValue?>[
      IntCellValue(i),
      TextCellValue(p.contractNo),
      TextCellValue(p.assignNo),
      TextCellValue(p.name),
      TextCellValue(app.companiesOf(p).join('، ')),
      TextCellValue(p.owner),
      m(p.contractValue),
      TextCellValue(p.valueFromItems ? 'البنود' : 'يدوي'),
      DoubleCellValue(p.variationsNet),
      m(adj),
      m(p.executedValue),
      TextCellValue(switch (p.executedSource) { 'extracts' => 'المستخلصات', 'items' => 'البنود', _ => 'يدوي' }),
      adj == null || adj <= 0 ? TextCellValue('') : DoubleCellValue(((p.executedValue ?? 0) / adj * 1000).round() / 10),
      IntCellValue(p.extractsCount),
      DoubleCellValue(p.extractsGross),
      DoubleCellValue(p.extractsNet),
      DoubleCellValue(p.paidTotal),
      adj == null || adj <= 0 ? TextCellValue('') : DoubleCellValue((p.paidTotal / adj * 1000).round() / 10),
      DoubleCellValue(p.outstanding),
      m(p.remainingWork),
      m(p.remainingToPay),
      DoubleCellValue(p.retentionHeld),
      m(p.guaranteeInitial),
      m(p.guaranteeFinal),
      m(p.deductions),
    ]);
  }

  // المستخلصات
  final xs = excel['المستخلصات'];
  xs.appendRow(head(['العقد', 'رقم المستخلص', 'النوع', 'الرقم لدى الجهة', 'بداية الفترة', 'نهاية الفترة', 'تاريخ التقديم', 'الحالة', 'تاريخ الاعتماد',
    'قيمة الأعمال', 'التأمين المحتجز', 'استرداد الدفعة المقدمة', 'الغرامات', 'الضرائب والرسوم', 'استقطاعات أخرى', 'الصافي', 'المدفوع', 'تاريخ الدفع',
    'غير المدفوع', 'ملاحظات']));
  for (final x in ex) {
    xs.appendRow(<CellValue?>[
      TextCellValue(app.project(x.projectId)?.contractTitle ?? ''),
      IntCellValue(x.seq),
      TextCellValue(x.isFinal ? 'ختامي' : 'جاري'),
      TextCellValue(x.refNo),
      TextCellValue(x.periodFrom == null ? '' : _day(x.periodFrom!)),
      TextCellValue(x.periodTo == null ? '' : _day(x.periodTo!)),
      TextCellValue(x.submittedOn == null ? '' : _day(x.submittedOn!)),
      TextCellValue(x.statusLabel),
      TextCellValue(x.approvedOn == null ? '' : _day(x.approvedOn!)),
      DoubleCellValue(x.gross),
      DoubleCellValue(x.retention),
      DoubleCellValue(x.advanceRecovery),
      DoubleCellValue(x.penalties),
      DoubleCellValue(x.taxes),
      DoubleCellValue(x.otherDeductions),
      DoubleCellValue(x.net),
      DoubleCellValue(x.paidAmount),
      TextCellValue(x.paidOn == null ? '' : _day(x.paidOn!)),
      DoubleCellValue(x.unpaid),
      TextCellValue(x.notes),
    ]);
  }

  // أوامر التغيير
  final vs = excel['أوامر التغيير'];
  vs.appendRow(head(['العقد', 'رقم الأمر', 'الوصف', 'النوع', 'القيمة', 'القيمة بالإشارة', 'تاريخ الاعتماد', 'ملاحظات']));
  for (final v in vars) {
    vs.appendRow(<CellValue?>[
      TextCellValue(app.project(v.projectId)?.contractTitle ?? ''),
      TextCellValue(v.refNo),
      TextCellValue(v.title),
      TextCellValue(v.isAdd ? 'زيادة' : 'نقص'),
      DoubleCellValue(v.amount),
      DoubleCellValue(v.signed),
      TextCellValue(v.approvedOn == null ? '' : _day(v.approvedOn!)),
      TextCellValue(v.notes),
    ]);
  }
  return _save(excel, 'التقرير المالي للعقود');
}
