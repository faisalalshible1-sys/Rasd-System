import 'dart:convert';
import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:file_saver/file_saver.dart';
import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;

import '../app_state.dart';
import '../models.dart';
import '../pm.dart';

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
    'الضمان الابتدائي (بنسبة العقد) $base', 'الضمان النهائي (بنسبة العقد) $base', 'قيمة الخصومات']);
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
      p.guaranteeInitialNa ? TextCellValue('لا ينطبق') : money(p.guaranteeInitial),
      p.guaranteeFinalNa ? TextCellValue('لا ينطبق') : money(p.guaranteeFinal),
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

/// حفظ صورة PNG (لوحات العرض) بالاسم المعطى وتاريخ اليوم.
Future<String?> saveImageBytes(Uint8List bytes, String baseName) {
  final name = '$baseName ${_day(DateTime.now())}';
  final mobile = !kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS);
  if (mobile) {
    return FileSaver.instance.saveAs(name: name, bytes: bytes, ext: 'png', mimeType: MimeType.png);
  }
  return FileSaver.instance.saveFile(name: name, bytes: bytes, ext: 'png', mimeType: MimeType.png);
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
    ('الضمان الابتدائي (بنسبة كل عقد)', sum(projects.map((p) => p.guaranteeInitial ?? 0))),
    ('الضمان النهائي (بنسبة كل عقد)', sum(projects.map((p) => p.guaranteeFinal ?? 0))),
    ('إجمالي التأمينات والضمانات',
        sum(projects.map((p) => p.retentionHeld + (p.guaranteeInitial ?? 0) + (p.guaranteeFinal ?? 0)))),
    ('المحال للصرف (غير المدفوع)', sum(ex.where((x) => x.isReferred).map((x) => x.unpaid))),
    ('مدفوع المستخلصات', sum(counted.map((x) => x.paidAmount))),
    ('الدفعات المقدمة', sum(projects.map((p) => p.advanceAmount ?? 0))),
    ('المسترد من الدفعات المقدمة', sum(projects.map((p) => p.advanceRecovered))),
    ('المتبقي للاسترداد', sum(projects.map((p) => p.advanceRemaining))),
  ];
  summary.appendRow(head(['البند', 'القيمة ($currencyLabel)']));
  for (final r in rows) {
    summary.appendRow(<CellValue?>[TextCellValue(r.$1), DoubleCellValue(r.$2)]);
  }
  summary.appendRow(<CellValue?>[TextCellValue('عدد العقود'), IntCellValue(projects.length)]);
  summary.appendRow(<CellValue?>[TextCellValue('عدد المستخلصات المعتمدة'), IntCellValue(counted.length)]);
  summary.appendRow(<CellValue?>[TextCellValue('عدد المستخلصات المحالة للصرف'), IntCellValue(ex.where((x) => x.isReferred).length)]);
  summary.appendRow(<CellValue?>[TextCellValue('عدد المستخلصات المصروفة'), IntCellValue(ex.where((x) => x.isPaid).length)]);
  summary.appendRow(<CellValue?>[TextCellValue('تاريخ التقرير'), TextCellValue(_stamp(DateTime.now()))]);

  // العقود
  final cs = excel['العقود'];
  cs.appendRow(head(['ت', 'رقم العقد', 'رقم التكليف', 'اسم المشروع', 'الشركات', 'المالك', 'القيمة التعاقدية', 'مصدرها', 'صافي أوامر التغيير',
    'القيمة بعد التغيير', 'المنفذ', 'مصدره', 'نسبة التنفيذ %', 'عدد المستخلصات', 'إجمالي المستخلصات', 'صافيها', 'المدفوع', 'نسبة الدفع %',
    'مستحق غير مدفوع', 'المتبقي من الأعمال', 'المتبقي للدفع', 'التأمين المحتجز', 'الضمان الابتدائي', 'الضمان النهائي', 'الخصومات اليدوية',
    'الدفعة المقدمة', 'تاريخ صرفها', 'المسترد منها', 'المتبقي للاسترداد']));
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
      p.guaranteeInitialNa ? TextCellValue('لا ينطبق') : m(p.guaranteeInitial),
      p.guaranteeFinalNa ? TextCellValue('لا ينطبق') : m(p.guaranteeFinal),
      m(p.deductions),
      m(p.advanceAmount),
      TextCellValue(p.advancePaidOn == null ? '' : _day(p.advancePaidOn!)),
      DoubleCellValue(p.advanceRecovered),
      DoubleCellValue(p.advanceRemaining),
    ]);
  }

  // المستخلصات
  final xs = excel['المستخلصات'];
  // الاستقطاعات المخصصة: أعمدة بأسماء أنواعها (المعرّفة في الإعدادات ثم أي مفتاح آخر مسجل)
  final customKeys = <String>[
    for (final t in app.settings.deductionTypes) t.key,
    for (final x in ex)
      for (final k in x.customDeductions.keys) k,
  ].toSet().toList();
  String customLabel(String k) {
    for (final t in app.settings.deductionTypes) {
      if (t.key == k) return t.label;
    }
    return k;
  }

  xs.appendRow(head(['العقد', 'رقم المستخلص', 'النوع', 'الرقم لدى الجهة', 'بداية الفترة', 'نهاية الفترة', 'تاريخ التقديم', 'الحالة', 'تاريخ الاعتماد',
    'تاريخ الإحالة للصرف', 'رقم الإحالة',
    'قيمة الأعمال', 'التأمين المحتجز', 'استرداد الدفعة المقدمة', 'الغرامات', 'الضرائب والرسوم', for (final k in customKeys) customLabel(k),
    'استقطاعات أخرى', 'الصافي', 'المدفوع', 'تاريخ الدفع', 'عدد الدفعات', 'غير المدفوع', 'ملاحظات']));
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
      TextCellValue(x.referredOn == null ? '' : _day(x.referredOn!)),
      TextCellValue(x.referralNo),
      DoubleCellValue(x.gross),
      DoubleCellValue(x.retention),
      DoubleCellValue(x.advanceRecovery),
      DoubleCellValue(x.penalties),
      DoubleCellValue(x.taxes),
      for (final k in customKeys) DoubleCellValue(x.customDeductions[k] ?? 0),
      DoubleCellValue(x.otherDeductions),
      DoubleCellValue(x.net),
      DoubleCellValue(x.paidAmount),
      TextCellValue(x.paidOn == null ? '' : _day(x.paidOn!)),
      IntCellValue(app.paymentsOf(x.id).length),
      DoubleCellValue(x.unpaid),
      TextCellValue(x.notes),
    ]);
  }

  // سجل الدفعات
  final ps = excel['سجل الدفعات'];
  ps.appendRow(head(['العقد', 'البيان', 'تاريخ الدفع', 'المبلغ', 'طريقة الدفع', 'المرجع', 'ملاحظات']));
  final payRows = <(DateTime?, List<CellValue?>)>[];
  for (final x in ex) {
    for (final pay in app.paymentsOf(x.id)) {
      payRows.add((pay.paidOn, <CellValue?>[
        TextCellValue(app.project(x.projectId)?.contractTitle ?? ''),
        TextCellValue(x.title),
        TextCellValue(pay.paidOn == null ? '' : _day(pay.paidOn!)),
        DoubleCellValue(pay.amount),
        TextCellValue(pay.methodLabel),
        TextCellValue(pay.refNo),
        TextCellValue(pay.notes),
      ]));
    }
  }
  for (final p in projects) {
    if (p.advancePaid <= 0) continue;
    payRows.add((p.advancePaidOn, <CellValue?>[
      TextCellValue(p.contractTitle),
      TextCellValue('دفعة مقدمة'),
      TextCellValue(p.advancePaidOn == null ? '' : _day(p.advancePaidOn!)),
      DoubleCellValue(p.advancePaid),
      TextCellValue(''),
      TextCellValue(''),
      TextCellValue(''),
    ]));
  }
  payRows.sort((a, b) => (a.$1 ?? DateTime(2000)).compareTo(b.$1 ?? DateTime(2000)));
  for (final r in payRows) {
    ps.appendRow(r.$2);
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

// =====================================================================
// متابعة المشاريع (الإصدار السابع): كل السجلات في ملف واحد، والتقرير الدوري
// =====================================================================
CellValue? _t(String? v) => v == null || v.isEmpty ? null : TextCellValue(v);
CellValue? _d(double? v, [int digits = 3]) => v == null ? null : DoubleCellValue(double.parse(v.toStringAsFixed(digits)));
CellValue? _i(int? v) => v == null ? null : IntCellValue(v);
CellValue? _day7(DateTime? d) => d == null ? null : TextCellValue(pmIso(d));

void _header(Sheet sh, List<String> cols) => sh.appendRow([for (final c in cols) TextCellValue(c)]);

String _pname(AppState app, String? id) {
  if (id == null || id.isEmpty) return 'عام – متعدد المشاريع';
  final p = app.project(id);
  return p?.label ?? '';
}

/// تصدير «سجل المخاطر ومتابعة المشاريع» كاملاً بأوراق الملف المعتمد.
Future<String?> exportPmXlsx(AppState app) async {
  final pm = app.pm;
  final cfg = app.pmConfig;
  final ref = pm.ref;
  final excel = Excel.createExcel();

  final dash = _sheet(excel, 'لوحة القيادة');
  dash.appendRow([TextCellValue('لوحة القيادة الموحدة – مشاريع إعادة الإعمار'), TextCellValue('تاريخ الإسناد'), TextCellValue(pmIso(ref))]);
  for (final (k, v) in [
    ('إجمالي المشاريع', '${pm.tracks.length}'),
    ('المشاريع الجارية', '${pm.running.length}'),
    ('الإنجاز الفعلي الموزون', pm.weightedActual == null ? '' : (pm.weightedActual! * 100).toStringAsFixed(1)),
    ('الإنجاز المخطط الموزون', pm.weightedPlanned == null ? '' : (pm.weightedPlanned! * 100).toStringAsFixed(1)),
    ('مؤشر أداء المحفظة SPI', pm.portfolioSpi?.toStringAsFixed(2) ?? ''),
    ('مخاطر نشطة', '${pm.activeRisks}'),
    ('مخاطر مرتفعة حالياً', '${pm.highRisksNow}'),
    ('مشاكل مفتوحة', '${pm.openIssues}'),
    ('أيام التأخير المسجلة', '${pm.delayDays}'),
    ('التمديدات المعتمدة (يوم)', '${pm.extensions}'),
    ('قيمة التغييرات المعتمدة', fmtMoney(pm.approvedChangesValue)),
    ('الدروس الموثقة', '${app.pmLessons.length}'),
    ('متوسط التقييم الميداني', pm.avgField?.toStringAsFixed(2) ?? ''),
  ]) {
    dash.appendRow([TextCellValue(k), TextCellValue(v)]);
  }
  dash.appendRow([]);
  dash.appendRow([TextCellValue('أبرز التنبيهات'), TextCellValue('العدد'), TextCellValue('الإجراء المطلوب')]);
  for (final a in pm.alerts) {
    dash.appendRow([TextCellValue(a.label), IntCellValue(a.count), TextCellValue(a.action)]);
  }

  final ps = excel['سجل المشاريع'];
  _header(ps, [
    'العقد', 'نوع المشروع', 'الموقع / القطاع', 'الشركة المنفذة', 'الاستشاري', 'القسم المشرف', 'رقم العقد', 'قيمة العقد', 'الوضع التشغيلي', //
    'تاريخ البداية', 'تاريخ النهاية التعاقدي', 'المدة التعاقدية (يوم)', 'التمديد المعتمد (يوم)', 'تاريخ النهاية المعدّل', 'المدة المنقضية %', //
    'الأيام المتبقية', 'تاريخ آخر قياس', 'الإنجاز المخطط %', 'الإنجاز الفعلي %', 'الانحراف %', 'SPI', 'سرعة الإنجاز (%/أسبوع)', //
    'السرعة المطلوبة (%/أسبوع)', 'تاريخ الإنجاز المتوقع', 'التأخير المتوقع (يوم)', 'مؤشر الأداء الزمني', 'مخاطر نشطة', 'مخاطر مرتفعة حالياً', //
    'مشاكل مفتوحة', 'أحداث تأخير', 'أيام التأخير', 'منها للمقاول', 'عدد التغييرات', 'قيمة التغييرات المعتمدة', 'قيمة العقد المعدّلة', 'نسبة التغييرات %', 'ملاحظات',
  ]);
  final tracks = pm.tracks.values.toList()..sort((a, b) => a.project.sortOrder.compareTo(b.project.sortOrder));
  for (final t in tracks) {
    final p = t.project, sc = t.schedule;
    ps.appendRow([
      _t(_pname(app, p.id)), _t(sc?.projectType), _t(sc?.location), _t(app.companiesOf(p).join('، ')), _t(sc?.consultant),
      _t(app.departmentName(p.department)), _t(p.contractNo), _d(t.contractValue), _t(opStatusLabels[t.opStatus]),
      _day7(t.start), _day7(t.end), _i(t.durationDays), _i(t.extensionDays), _day7(t.revisedEnd),
      _d(t.elapsedPct == null ? null : t.elapsedPct! * 100, 1), _i(t.remainingDays), _day7(t.lastDate),
      _d(t.planned == null ? null : t.planned! * 100, 1), _d(t.actual == null ? null : t.actual! * 100, 1),
      _d(t.deviation == null ? null : t.deviation! * 100, 1), _d(t.spi, 2), _d(t.speed == null ? null : t.speed! * 100, 2),
      t.overrun ? TextCellValue('تجاوز المدة') : _d(t.requiredSpeed == null ? null : t.requiredSpeed! * 100, 2),
      t.actual == null ? null : (t.forecastEnd == null ? TextCellValue('غير محدد') : _day7(t.forecastEnd)), _i(t.forecastDelay),
      _t(perfLabels[t.perf]), IntCellValue(t.activeRisks), IntCellValue(t.highRisksNow), IntCellValue(t.openIssues), IntCellValue(t.delayEvents),
      IntCellValue(t.delayDays), IntCellValue(t.contractorDelayDays), IntCellValue(t.changesCount), _d(t.approvedChangesValue), _d(t.revisedValue),
      _d(t.changePct == null ? null : t.changePct! * 100, 1), _t(sc?.notes),
    ]);
  }

  final gs = excel['سجل التقدم الدوري'];
  _header(gs, ['تاريخ القياس', 'العقد', 'الشركة المنفذة', 'المخطط % (تراكمي)', 'الفعلي % (تراكمي)', 'الانحراف %', 'SPI', 'أهم الأعمال المنفذة', 'المعوقات', 'أعدّه']);
  for (final m in [...app.measurements]..sort((a, b) => a.measuredOn.compareTo(b.measuredOn))) {
    gs.appendRow([
      _day7(m.measuredOn), _t(_pname(app, m.projectId)), _t(app.project(m.projectId)?.company), _d(m.planned * 100, 1), _d(m.actual * 100, 1),
      _d(m.deviation * 100, 1), _d(m.spi, 2), _t(m.works), _t(m.obstacles), _t(m.preparedBy),
    ]);
  }

  final rs = excel['سجل المخاطر'];
  _header(rs, [
    'الرمز', 'المشروع', 'العقد المرتبط', 'المرحلة', 'التصنيف', 'القسم المختص', 'وصف الخطر', 'السبب', 'الأثر', 'الاحتمالية', 'التأثير', 'الدرجة', //
    'المستوى', 'الاستجابة ومسار التصعيد', 'الأثر الزمني (يوم)', 'الأثر المالي', 'نوع الاستجابة', 'الإجراء الوقائي', 'الإجراء الاحتياطي', //
    'مالك الخطر', 'منفذ الإجراء', 'الحالة', 'الاحتمالية المستهدفة', 'التأثير المستهدف', 'الدرجة المستهدفة', 'تاريخ آخر مراجعة', //
    'الاحتمالية الحالية', 'التأثير الحالي', 'الدرجة الحالية', 'المستوى الحالي', 'مسار التصعيد الحالي', 'اتجاه الخطر', 'نسبة تنفيذ الإجراء %', //
    'نسبة الخفض المحققة %', 'تاريخ التسجيل', 'دورية المراجعة (يوم)', 'موعد المراجعة القادمة', 'الموعد المستهدف للإجراء', 'تاريخ الإغلاق', //
    'مؤشر الإنذار المبكر', 'حالة المتابعة', 'تحقق البيانات', 'ملاحظات',
  ]);
  const follow = {'overdue': 'متأخرة', 'soon': 'مستحقة قريباً', 'ontime': 'ضمن الموعد', 'none': 'بلا موعد', 'closed': 'مغلق'};
  for (final r in [...app.risks]..sort((a, b) => a.code.compareTo(b.code))) {
    final st = app.riskState(r);
    rs.appendRow([
      _t(r.code), _t(r.projectGroup), _t(r.projectId == null ? null : _pname(app, r.projectId)), _t(r.phase), _t(r.category), _t(r.department),
      _t(r.description), _t(r.cause), _t(r.effect), IntCellValue(r.probability), IntCellValue(r.impact), IntCellValue(r.score),
      _t(st.initialLevel.name), _t(st.initialLevel.action), _i(r.timeImpactDays), _d(r.costImpact), _t(r.responseLabel), _t(r.mitigation),
      _t(r.contingency), _t(r.owner), _t(r.executor), _t(r.statusLabel), _i(r.residualProbability), _i(r.residualImpact), _i(r.residualScore),
      _day7(st.lastReviewDate), IntCellValue(st.currentProbability), IntCellValue(st.currentImpact), IntCellValue(st.currentScore),
      _t(st.currentLevel.name), _t(st.escalation), _t(trendLabels[st.trend]), _d(st.progress * 100, 0), _d(st.reduction * 100, 0),
      _day7(r.registeredOn), IntCellValue(st.reviewDays), _day7(st.nextReview), _day7(r.targetDate), _day7(r.closedOn), _t(r.earlyWarning),
      _t(follow[st.followUp]), TextCellValue(st.check ?? '✓'), _t(r.notes),
    ]);
  }

  final vs = excel['مراجعات المخاطر'];
  _header(vs, ['تاريخ المراجعة', 'رمز الخطر', 'وصف الخطر', 'الاحتمالية الحالية', 'التأثير الحالي', 'الدرجة', 'الإجراءات المنفذة', 'نسبة التنفيذ %', 'المراجِع', 'ملاحظات / قرارات']);
  for (final v in [...app.riskReviews]..sort((a, b) => a.reviewedOn.compareTo(b.reviewedOn))) {
    final r = app.riskById(v.riskId);
    vs.appendRow([
      _day7(v.reviewedOn), _t(r?.code), _t(r?.description), IntCellValue(v.probability), IntCellValue(v.impact), IntCellValue(v.score),
      _t(v.actionsDone), _d(v.progress == null ? null : v.progress! * 100, 0), _t(v.reviewer), _t(v.notes),
    ]);
  }

  final is_ = excel['سجل المشاكل'];
  _header(is_, [
    'الرمز', 'العقد', 'الشركة المنفذة', 'تاريخ الرصد', 'وصف المشكلة', 'التصنيف', 'الخطر المرتبط', 'الأولوية', 'الجهة المسؤولة عن الحل', //
    'القسم المتابع', 'الإجراء المتخذ / المطلوب', 'الأثر الزمني (يوم)', 'الأثر المالي', 'الموعد المستهدف للحل', 'الحالة', 'تاريخ الإغلاق', //
    'عمر المشكلة (يوم)', 'حالة المتابعة', 'ملاحظات',
  ]);
  for (final i in app.pmIssues) {
    is_.appendRow([
      _t(i.code), _t(_pname(app, i.projectId)), _t(app.project(i.projectId)?.company), _day7(i.detectedOn), _t(i.description), _t(i.category),
      _t(i.riskId == null ? null : app.riskById(i.riskId!)?.code), _t(pmPriorityLabels[i.priority]), _t(pmPartyLabels[i.party]), _t(i.department),
      _t(i.action), _i(i.timeImpactDays), _d(i.costImpact), _day7(i.targetDate), _t(issueStatusLabels[i.status]), _day7(i.closedOn),
      IntCellValue(i.age(ref)), _t(follow[i.followUp(ref, cfg.alertDays)]), _t(i.notes),
    ]);
  }

  final ds = excel['سجل التأخيرات'];
  _header(ds, [
    'الرمز', 'العقد', 'الشركة المنفذة', 'وصف حدث التأخير', 'السبب الرئيسي', 'السبب الفرعي', 'الجهة المسؤولة', 'التصنيف التعاقدي', //
    'على المسار الحرج؟', 'بداية التأثير', 'نهاية التأثير', 'مدة التأخير (يوم)', 'حالة الحدث', 'التمديد المطلوب', 'التمديد المعتمد', 'المرجع', 'ملاحظات',
  ]);
  for (final d in app.pmDelays) {
    ds.appendRow([
      _t(d.code), _t(_pname(app, d.projectId)), _t(app.project(d.projectId)?.company), _t(d.description), _t(d.cause), _t(d.subCause),
      _t(pmPartyLabels[d.party]), _t(delayClassLabels[d.delayClass]), TextCellValue(d.critical ? 'نعم' : 'لا'), _day7(d.startDate),
      _day7(d.endDate), IntCellValue(d.days(ref)), TextCellValue(d.isOngoing ? 'قائم' : 'منتهٍ'), _i(d.eotRequested), _i(d.eotApproved),
      _t(d.refs), _t(d.notes),
    ]);
  }

  final cs = excel['سجل التغييرات'];
  _header(cs, [
    'رقم التغيير', 'العقد', 'الشركة المنفذة', 'تاريخ التقديم', 'وصف التغيير', 'نوع التغيير', 'مصدر التغيير', 'سبب التغيير', //
    'الأثر المالي المقدر', 'الأثر المالي المعتمد', 'الأثر الزمني المطلوب', 'الأثر الزمني المعتمد', 'الحالة', 'تاريخ البت', 'مرجع الاعتماد', //
    'مدة البت (يوم)', 'في مالية العقد', 'المرجع المرتبط', 'ملاحظات',
  ]);
  for (final c in app.pmChanges) {
    cs.appendRow([
      _t(c.code), _t(_pname(app, c.projectId)), _t(app.project(c.projectId)?.company), _day7(c.submittedOn), _t(c.description), _t(c.changeType),
      _t(changeSourceLabels[c.source]), _t(c.reason), _d(c.costEstimate), _d(c.costApproved), _i(c.timeRequested), _i(c.timeApproved),
      _t(changeStatusLabels[c.status]), _day7(c.decidedOn), _t(c.approvalRef), IntCellValue(c.decisionDays(ref)),
      TextCellValue(c.variationId == null ? 'لا' : 'نعم'), _t(c.refs), _t(c.notes),
    ]);
  }

  final ls = excel['الدروس المستفادة'];
  _header(ls, [
    'الرمز', 'العقد', 'تاريخ التوثيق', 'المرحلة', 'المجال', 'نوع الدرس', 'الموقف', 'السبب الجذري', 'الأثر', 'الدرس المستفاد / التوصية', //
    'آلية التعميم', 'الجهة المعنية بالتطبيق', 'المرجع', 'حالة التطبيق', 'تاريخ الاعتماد / التطبيق', 'أعدّه',
  ]);
  for (final l in app.pmLessons) {
    ls.appendRow([
      _t(l.code), _t(_pname(app, l.projectId)), _day7(l.documentedOn), _t(l.phase), _t(l.domain), _t(lessonTypeLabels[l.lessonType]),
      _t(l.situation), _t(l.rootCause), _t(l.effect), _t(l.lesson), _t(l.applyMechanism), _t(l.applyParty), _t(l.refs),
      _t(lessonStatusLabels[l.status]), _day7(l.appliedOn), _t(l.preparedBy),
    ]);
  }

  final es = excel['التقييم الدوري للشركات'];
  _header(es, ['تاريخ التقييم', 'العقد', 'الشركة المنفذة', for (final c in evalCriteria) c.$2, 'المتوسط', 'المُقيِّم', 'ملاحظات وأدلة التقييم']);
  for (final e in [...app.pmEvaluations]..sort((a, b) => a.evaluatedOn.compareTo(b.evaluatedOn))) {
    es.appendRow([
      _day7(e.evaluatedOn), _t(_pname(app, e.projectId)), _t(e.company), for (final c in evalCriteria) _i(e.scores[c.$1]), _d(e.average, 2),
      _t(e.evaluator), _t(e.notes),
    ]);
  }

  final ks = excel['مؤشرات أداء الشركات'];
  _header(ks, [
    'الشركة', 'عدد المشاريع', 'الجارية', 'إجمالي قيمة العقود', 'متوسط الإنجاز الفعلي %', 'متوسط SPI', 'أيام التأخير المنسوبة', //
    'إجمالي المدد التعاقدية', 'نسبة التأخير المنسوب %', 'المشاكل المسندة', 'المفتوحة منها', 'متوسط عمر المشاكل', 'ملاحظات السلامة', 'ملاحظات الجودة', //
    'طلبات تغيير من الشركة', 'المرفوضة منها', 'متوسط التقييم الميداني', 'عدد التقييمات', 'درجة الالتزام الزمني', 'درجة التأخير المنسوب', //
    'درجة التقييم الميداني', 'درجة سرعة الحل', 'الدرجة المركّبة', 'التقدير', 'الترتيب', 'التوصية', 'اكتمال البيانات',
  ]);
  for (final k in pm.contractors) {
    ks.appendRow([
      _t(k.name), IntCellValue(k.projects), IntCellValue(k.running), _d(k.totalValue), _d(k.avgActual == null ? null : k.avgActual! * 100, 1),
      _d(k.avgSpi, 2), IntCellValue(k.contractorDelayDays), IntCellValue(k.totalDuration), _d(k.delayRatio == null ? null : k.delayRatio! * 100, 1),
      IntCellValue(k.issuesAssigned), IntCellValue(k.openIssues), _d(k.avgIssueAge, 1), IntCellValue(k.safetyIssues), IntCellValue(k.qualityIssues),
      IntCellValue(k.changesFromContractor), IntCellValue(k.rejectedChanges), _d(k.avgField, 2), IntCellValue(k.evaluations),
      _d(k.scheduleScore, 0), _d(k.delayScore, 0), _d(k.fieldScore, 0), _d(k.responseScore, 0), _d(k.composite, 0), _t(k.gradeName),
      k.rank == 0 ? null : IntCellValue(k.rank), _t(k.gradeRec), TextCellValue('${k.completeness} من 4'),
    ]);
  }

  final da = excel['تحليل أسباب التأخير'];
  _header(da, ['السبب الرئيسي', 'الترتيب', 'عدد الأحداث', 'أيام التأخير', 'على المسار الحرج', 'النسبة %', 'التراكمية %', 'التمديد المعتمد', 'القائمة', 'حيوي (باريتو)']);
  final an = pm.delayAnalysis;
  for (var i = 0; i < an.pareto.length; i++) {
    final g = an.pareto[i];
    da.appendRow([
      _t(g.key), IntCellValue(i + 1), IntCellValue(g.count), IntCellValue(g.days), IntCellValue(g.criticalDays), _d(g.pct * 100, 1),
      _d(g.cumPct * 100, 1), IntCellValue(g.eotApproved), IntCellValue(g.ongoing), TextCellValue(an.isVital(g) ? 'نعم' : ''),
    ]);
  }
  return _save(excel, 'سجل المخاطر ومتابعة المشاريع');
}

/// تصدير التقرير الدوري (أسبوعي أو شهري) مع ملاحظات المكتب.
Future<String?> exportPmReportXlsx(AppState app, PeriodicReport r, String notes) async {
  final excel = Excel.createExcel();
  final sh = _sheet(excel, r.monthly ? 'التقرير الشهري' : 'التقرير الأسبوعي');
  sh.appendRow([TextCellValue('${r.title} – مكتب الشؤون الهندسية')]);
  sh.appendRow([TextCellValue(app.orgName)]);
  sh.appendRow([TextCellValue('الفترة'), TextCellValue('${pmIso(r.start)} إلى ${pmIso(r.end)}'), TextCellValue(r.periodLabel)]);
  sh.appendRow([]);
  sh.appendRow([TextCellValue('أولاً: ملخص الفترة')]);
  String p(double? v) => v == null ? '' : '${(v * 100).toStringAsFixed(1)}%';
  for (final (k, v) in [
    ('المشاريع الجارية خلال الفترة', '${r.runningProjects}'),
    ('مشاريع متأخرة في نهاية الفترة', '${r.lateAtEnd}'),
    ('متوسط الإنجاز المخطط (موزون)', p(r.plannedW)),
    ('متوسط الإنجاز الفعلي (موزون)', p(r.actualW)),
    ('الإنجاز المحقق خلال الفترة', p(r.gainW)),
    ('مؤشر أداء الجدول للمحفظة SPI', r.spiW?.toStringAsFixed(2) ?? ''),
    ('مخاطر جديدة', '${r.newRisks}'),
    ('مخاطر أُغلقت', '${r.closedRisks}'),
    ('مراجعات مخاطر نُفذت', '${r.reviewsDone}'),
    ('مخاطر مرتفعة نشطة حالياً', '${r.highNow}'),
    ('مشاكل جديدة', '${r.newIssues}'),
    ('مشاكل أُغلقت', '${r.closedIssues}'),
    ('مشاكل متأخرة عن موعد الحل', '${r.overdueIssues}'),
    ('أحداث تأخير بدأت', '${r.delaysStarted}'),
    ('أحداث تأخير قائمة', '${r.ongoingDelays}'),
    ('طلبات تغيير قُدمت', '${r.changesSubmitted}'),
    ('تغييرات اعتُمدت', '${r.changesApproved}'),
    ('قيمة التغييرات المعتمدة', fmtMoney(r.approvedValue)),
    ('دروس وُثقت', '${r.lessonsDocumented}'),
    ('تقييمات ميدانية', '${r.evaluationsDone}'),
  ]) {
    sh.appendRow([TextCellValue(k), TextCellValue(v)]);
  }
  sh.appendRow([]);
  sh.appendRow([TextCellValue('ثانياً: تقدم المشاريع خلال الفترة')]);
  _header(sh, ['م', 'العقد', 'الشركة', 'المخطط نهاية الفترة %', 'الفعلي بداية الفترة %', 'الفعلي نهاية الفترة %', 'الإنجاز خلال الفترة %', 'الانحراف %', 'SPI', 'مؤشر الأداء', 'المعوقات']);
  for (var i = 0; i < r.rows.length; i++) {
    final x = r.rows[i];
    sh.appendRow([
      IntCellValue(i + 1), _t(_pname(app, x.track.project.id)), _t(x.track.project.company), _d(x.planned == null ? null : x.planned! * 100, 1),
      _d(x.actualStart == null ? null : x.actualStart! * 100, 1), _d(x.actualEnd == null ? null : x.actualEnd! * 100, 1),
      _d(x.gain == null ? null : x.gain! * 100, 1), _d(x.deviation == null ? null : x.deviation! * 100, 1), _d(x.spi, 2),
      _t(perfLabels[x.perf(app.pmConfig)]), _t(x.obstacles),
    ]);
  }
  sh.appendRow([]);
  sh.appendRow([TextCellValue('ثالثاً: أعلى 5 مخاطر نشطة حسب الدرجة الحالية')]);
  _header(sh, ['الرمز', 'وصف الخطر', 'الدرجة الحالية', 'المستوى', 'الاتجاه', 'مالك الخطر', 'مسار التصعيد']);
  for (final s in r.topRisks) {
    sh.appendRow([
      _t(s.risk.code), _t(s.risk.description), IntCellValue(s.currentScore), _t(s.currentLevel.name), _t(trendLabels[s.trend]), _t(s.risk.owner),
      _t(s.escalation),
    ]);
  }
  sh.appendRow([]);
  sh.appendRow([TextCellValue('رابعاً: المشاكل المتأخرة عن موعد الحل')]);
  _header(sh, ['الرمز', 'وصف المشكلة', 'العقد', 'الأولوية', 'الجهة المسؤولة', 'الموعد المستهدف', 'أيام التجاوز', 'القسم المتابع', 'الإجراء']);
  for (final i in r.lateIssues) {
    sh.appendRow([
      _t(i.code), _t(i.description), _t(_pname(app, i.projectId)), _t(pmPriorityLabels[i.priority]), _t(pmPartyLabels[i.party]),
      _day7(i.targetDate), IntCellValue(i.overdueDays(r.a.ref)), _t(i.department), _t(i.action),
    ]);
  }
  sh.appendRow([]);
  sh.appendRow([TextCellValue('خامساً: ملاحظات وتوصيات المكتب')]);
  sh.appendRow([_t(notes)]);
  sh.appendRow([]);
  sh.appendRow([TextCellValue('أعدّه: مكتب المدير'), TextCellValue('يعتمد: مدير المكتب الهندسي المكلف')]);
  return _save(excel, r.title);
}
