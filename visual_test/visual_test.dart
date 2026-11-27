import 'dart:typed_data';
// لقطات بصرية للصفحات الرئيسية ببيانات تجريبية (للتدقيق على التصميم، لا تُشغَّل مع الاختبارات العادية):
//   flutter test visual_test --update-goldens
// تُحفظ الصور في visual_test/goldens/ ويرفعها سير العمل visual.yml.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:dc_app/app_state.dart';
import 'package:dc_app/chat.dart';
import 'package:dc_app/docs.dart';
import 'package:dc_app/models.dart';
import 'package:dc_app/pm.dart';
import 'package:dc_app/prices.dart';
import 'package:dc_app/print/export_dialog.dart';
import 'package:dc_app/print/exporter.dart';
import 'package:dc_app/print/model.dart';
import 'package:dc_app/print/preview.dart';
import 'package:dc_app/print/sources.dart';
import 'package:dc_app/print/table_editor.dart';
import 'package:dc_app/rasd.dart';
import 'package:dc_app/schedule.dart';
import 'package:dc_app/assets.dart';
import 'package:dc_app/stores.dart';
import 'package:dc_app/screens/stores.dart';
import 'package:dc_app/screens/stores_assets.dart';
import 'package:dc_app/screens/stores_docs.dart';
import 'package:dc_app/screens/stores_setup.dart';
import 'package:dc_app/services/boq_files.dart';
import 'package:dc_app/scope.dart';
import 'package:dc_app/registers.dart';
import 'package:dc_app/screens/assigned_work.dart';
import 'package:dc_app/screens/assistant.dart';
import 'package:dc_app/screens/chat.dart';
import 'package:dc_app/screens/control/layout_editor.dart';
import 'package:dc_app/screens/control/user_details.dart';
import 'package:dc_app/screens/ref_numbers.dart';
import 'package:dc_app/screens/security_center.dart';
import 'package:dc_app/screens/auth.dart';
import 'package:dc_app/screens/contract_finance.dart';
import 'package:dc_app/screens/cycle_guide.dart';
import 'package:dc_app/screens/control/appearance.dart';
import 'package:dc_app/screens/control/settings.dart';
import 'package:dc_app/screens/dashboard.dart';
import 'package:dc_app/screens/boq_import.dart';
import 'package:dc_app/screens/contract_files.dart';
import 'package:dc_app/screens/contract_v3.dart';
import 'package:dc_app/screens/docs.dart';
import 'package:dc_app/screens/units.dart';
import 'package:dc_app/units.dart';
import 'package:dc_app/screens/finance.dart';
import 'package:dc_app/screens/home_shell.dart';
import 'package:dc_app/screens/hub.dart' show appSections, defaultSectionColor;
import 'package:dc_app/screens/hub_editor.dart' show HubDraft, showPagesEditor, showSectionEditor;
import 'package:dc_app/screens/ideas.dart' show IdeasPage, showIdeaComposer;
import 'package:dc_app/screens/manual.dart';
import 'package:dc_app/screens/project_detail.dart';
import 'package:dc_app/screens/pm_contractors.dart';
import 'package:dc_app/screens/pm_dashboard.dart';
import 'package:dc_app/screens/pm_presentation.dart';
import 'package:dc_app/screens/pm_projects.dart';
import 'package:dc_app/screens/pm_registers.dart';
import 'package:dc_app/screens/pm_report.dart';
import 'package:dc_app/screens/pm_settings.dart';
import 'package:dc_app/screens/prices.dart';
import 'package:dc_app/screens/print_center.dart';
import 'package:dc_app/screens/risks.dart';
import 'package:dc_app/screens/plan_versions.dart';
import 'package:dc_app/screens/plans.dart';
import 'package:dc_app/screens/schedule.dart';
import 'package:dc_app/screens/supervision_hub.dart';
import 'package:dc_app/screens/supervision.dart';
import 'package:dc_app/screens/swot.dart';
import 'package:dc_app/screens/swot_presentation.dart';
import 'package:dc_app/ui/slideshow.dart';
import 'package:dc_app/ui/theme.dart';
import 'package:dc_app/ui/widgets.dart' show confirmDialog;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:supabase_flutter/supabase_flutter.dart';

const _desktop = Size(1440, 2600);
const _mobile = Size(400, 3200);

Future<void> _loadFonts() async {
  // خط محلي يدعم العربية بدل Google Fonts (لا شبكة في الاختبارات). أولها خط مدمج عربي ولاتيني
  // (Noto Sans Arabic مع حروف لاتينية ورموز مثل % و·) حتى لا تظهر مربعات مكان الحروف اللاتينية والرموز.
  final candidates = <String, List<String>>{
    'regular': [
      'visual_test/fonts/ArLatSans-Regular.ttf',
      '/usr/share/fonts/truetype/noto/NotoSansArabic-Regular.ttf',
      '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',
    ],
    'bold': [
      'visual_test/fonts/ArLatSans-Bold.ttf',
      '/usr/share/fonts/truetype/noto/NotoSansArabic-Bold.ttf',
      '/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf',
    ],
  };
  for (final family in const ['Roboto', 'Readex Pro', 'MaterialIcons']) {
    if (family == 'MaterialIcons') continue;
    final loader = FontLoader(family);
    for (final list in candidates.values) {
      for (final path in list) {
        final f = File(path);
        if (f.existsSync()) {
          loader.addFont(Future.value(ByteData.view(f.readAsBytesSync().buffer)));
          break;
        }
      }
    }
    await loader.load();
  }
  // خطوط الطباعة المضمّنة في التطبيق (معاينة الصفحة في المصمم)
  for (final e in const {
    'PrintNaskh': ['NotoNaskhArabic-Regular.ttf', 'NotoNaskhArabic-Bold.ttf'],
    'PrintKufi': ['NotoKufiArabic-Regular.ttf', 'NotoKufiArabic-Bold.ttf'],
    'PrintSans': ['ArLatSans-Regular.ttf', 'ArLatSans-Bold.ttf'],
  }.entries) {
    final loader = FontLoader(e.key);
    for (final name in e.value) {
      final f = File('assets/fonts/$name');
      if (f.existsSync()) loader.addFont(Future.value(ByteData.view(f.readAsBytesSync().buffer)));
    }
    await loader.load();
  }
  // أيقونات Material من حزمة Flutter نفسها
  final flutterRoot = Platform.environment['FLUTTER_ROOT'];
  if (flutterRoot != null) {
    final icons = File('$flutterRoot/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
    if (icons.existsSync()) {
      final loader = FontLoader('MaterialIcons')..addFont(Future.value(ByteData.view(icons.readAsBytesSync().buffer)));
      await loader.load();
    }
  }
}

DateTime _d(int daysAgo) => DateTime.now().subtract(Duration(days: daysAgo));
String _iso(int daysAgo) => _d(daysAgo).toIso8601String();
String _day(int daysAgo) => dbDate(_d(daysAgo));

AppState _sampleState() {
  final client = SupabaseClient('http://localhost:54321', 'anon-key', authOptions: const AuthClientOptions(autoRefreshToken: false));
  final app = _VisualApp(client);
  app.me = Profile.fromMap({'id': 'u-dir', 'full_name': 'م. فيصل الشبلي', 'email': 'director@office.ly', 'role': 'director', 'active': true});
  app.people = {
    for (final p in [
      app.me!,
      Profile.fromMap({'id': 'u-1', 'full_name': 'سالم المبروك', 'email': 'salem@office.ly', 'role': 'contracts', 'active': true}),
      Profile.fromMap({'id': 'u-2', 'full_name': 'هدى العبيدي', 'email': 'huda@office.ly', 'role': 'office_staff', 'active': true}),
      Profile.fromMap({'id': 'u-3', 'full_name': 'أحمد الفيتوري', 'email': 'ahmed@office.ly', 'role': 'dept_head', 'department': 'supervision', 'active': true}),
    ])
      p.id: p,
  };
  app.departments = [
    Department.fromMap({'key': 'supervision', 'name': 'الإشراف والتنسيق', 'can_supervise': true, 'sort': 1}),
    Department.fromMap({'key': 'restoration', 'name': 'الترميم', 'can_supervise': true, 'sort': 2}),
    Department.fromMap({'key': 'technical', 'name': 'الشؤون الفنية', 'can_supervise': false, 'sort': 3}),
    Department.fromMap({'key': 'acceptance', 'name': 'المطابقة والاستلام', 'can_supervise': false, 'sort': 4}),
  ];
  // الدورة المستندية للعقود – الإصدار 2 المعتمد (الترحيل 19)
  const forms = [
    ('f01', 'أمر بالتعاقد', 0), ('f20', 'نطاق وطريقة عمل', 0), ('f19', 'مقايسة تقديرية', 0), ('f21', 'ملحق فني', 0),
    ('f03', 'نموذج عقد أشغال عامة', 0),
    ('f02', 'أمر عمل', 1), ('f04', 'تكليف مهندس إشراف', 1), ('f05', 'تكليف مهندس حصر', 1), ('f06', 'تكليف مهندس متابعة', 1),
    ('f07', 'تكليف مهندس سلامة', 1), ('f08', 'محضر تسليم موقع عمل', 1), ('f09', 'تصريح عمل', 1),
    ('f10', 'ورقة قياس نموذج أ', 2), ('f11', 'ورقة قياس نموذج ب', 2), ('f22', 'محضر حصر كميات', 2), ('f12', 'كشف حصر مستخلص', 2),
    ('f14', 'مستخلص جاري', 2), ('f13', 'شهادة دفع مستخلص', 2), ('f23', 'مراجعة مستخلص', 2), ('f24', 'اعتماد مستخلص', 2),
    ('f25', 'تكليف لجنة استلام ابتدائي', 3), ('f16', 'محضر استلام ابتدائي', 3), ('f15', 'مستخلص ختامي', 3),
    ('f26', 'تكليف لجنة استلام نهائي', 4), ('f17', 'محضر استلام نهائي', 4), ('f18', 'إقفال عقد', 4),
  ];
  app.allFormDefs = [
    for (var i = 0; i < forms.length; i++)
      FormDef.fromMap({
        'key': forms[i].$1,
        'name': forms[i].$2,
        'stage': forms[i].$3,
        'sort': i + 1,
        'sensitive': forms[i].$1 == 'f01',
        'responsible': ['office_staff', 'contracts'],
        'engineer_field': switch (forms[i].$1) { 'f04' => 'eng_sup', 'f05' => 'eng_qty', 'f06' => 'eng_fol', 'f07' => 'eng_saf', _ => null },
      }),
  ];
  app.formDefs = app.allFormDefs;

  const names = [
    ('001', 'ع-2026/11', 'صيانة مبنى القنصلية الإيطالية', 'درع ليبيا', 'وزارة الخارجية', 1450000.0),
    ('002', 'ع-2026/12', 'إزالة المخلفات منطقة A', 'جودة الإعمار', 'صندوق التنمية', 980000.0),
    ('003', 'ع-2026/13', 'ترميم واجهات شارع عمر المختار', 'أثمار', 'بلدية بنغازي', 2300000.0),
    ('004', '', 'تنظيف غرف التفتيش للصرف الصحي', 'جودة الإعمار', 'صندوق التنمية', 410000.0),
    ('005', 'ع-2026/15', 'معالجة مختنقات شبكة المياه', 'جودة الإعمار', 'الشركة العامة للمياه', 760000.0),
    ('006', 'ع-2026/16', 'هدم المباني الآيلة للسقوط', 'درع ليبيا', 'صندوق التنمية', 1200000.0),
    ('007', '', 'رصف الطرق الداخلية منطقة E', 'أثمار', 'بلدية بنغازي', null),
    ('008', 'ع-2026/18', 'إنارة الشوارع الرئيسية', 'النور للمقاولات', 'الشركة العامة للكهرباء', 540000.0),
  ];
  final projects = <Project>[];
  final works = <ContractWork>[];
  final extracts = <ContractExtract>[];
  final variations = <ContractVariation>[];
  final statuses = <String, Map<String, FormStatus>>{};
  for (var i = 0; i < names.length; i++) {
    final n = names[i];
    final id = 'p-${n.$1}';
    final value = n.$6;
    // مستخلصات بحالات متنوعة
    final xs = <ContractExtract>[];
    if (value != null) {
      final count = (i % 4) + 1;
      for (var k = 1; k <= count; k++) {
        final gross = (value * (0.12 + 0.05 * k)).roundToDouble();
        final retention = (gross * 0.1).roundToDouble();
        final taxes = (gross * 0.02).roundToDouble();
        final stamp = i == 2 ? (gross * 0.005).roundToDouble() : 0.0;
        final adv = i == 2 ? (gross * 0.1).roundToDouble() : 0.0;
        final net = gross - retention - taxes - stamp - adv;
        final status = k < count ? 'paid' : const ['submitted', 'approved', 'referred', 'paid', 'draft'][i % 5];
        final paid = status == 'paid' ? net : (status == 'referred' && i.isEven ? (net * 0.4).roundToDouble() : 0.0);
        xs.add(ContractExtract.fromMap({
          'id': 'x-$id-$k',
          'project_id': id,
          'seq': k,
          'ref_no': 'م-${n.$1}/$k',
          'kind': 'interim',
          'period_from': _day(200 - k * 30),
          'period_to': _day(170 - k * 30),
          'submitted_on': _day(165 - k * 30),
          'gross_amount': gross,
          'retention': retention,
          'taxes': taxes,
          'custom_deductions': i == 2 ? {'stamp': stamp} : null,
          'custom_total': stamp,
          'advance_recovery': adv,
          'net_amount': net,
          'status': status,
          'approved_on': const ['approved', 'referred', 'paid'].contains(status) ? _day(160 - k * 30) : null,
          'referred_on': const ['referred', 'paid'].contains(status) ? _day(150 - k * 30) : null,
          'paid_amount': paid,
          'paid_on': paid > 0 ? _day(140 - k * 30) : null,
        }));
      }
    }
    extracts.addAll(xs);
    final counted = xs.where((x) => x.counted);
    if (i.isOdd && value != null) {
      variations.add(ContractVariation.fromMap({
        'id': 'v-$id',
        'project_id': id,
        'ref_no': 'أ.ت-${n.$1}',
        'title': i % 3 == 0 ? 'إلغاء بند الأرصفة' : 'زيادة كميات الحفر والردم',
        'kind': i % 3 == 0 ? 'deduct' : 'add',
        'amount': value * 0.06,
        'approved_on': _day(60),
      }));
    }
    final varNet = variations.where((v) => v.projectId == id).fold<double>(0, (a, v) => a + v.signed);
    final gross = counted.fold<double>(0, (a, x) => a + x.gross);
    projects.add(Project.fromMap({
      'id': id,
      'assign_no': n.$1,
      'contract_no': n.$2,
      'name': n.$3,
      'company': n.$4,
      'owner': n.$5,
      'department': i.isEven ? 'supervision' : 'restoration',
      'sort_order': i + 1,
      'contract_value': value,
      'executed_value': counted.isEmpty ? (value == null ? null : value * 0.1) : gross,
      'guarantee_initial': i == 5 ? null : gross * 0.02,
      'guarantee_initial_na': i == 5,
      'guarantee_final': gross * 0.05,
      'guarantee_initial_rate': 0.02,
      'guarantee_final_rate': 0.05,
      'retention_deduct': i != 7,
      'retention_rate': 0.1,
      'variations_add': variations.where((v) => v.projectId == id && v.isApproved).fold<double>(0, (a, v) => a + v.addedValue),
      'variations_deduct': variations.where((v) => v.projectId == id && v.isApproved).fold<double>(0, (a, v) => a + v.deductedValue),
      'extracts_submitted': xs.where((x) => x.status != 'draft' && x.status != 'rejected').fold<double>(0, (a, x) => a + x.gross),
      'value_source': i < 3 ? 'items' : 'manual',
      'executed_source': counted.isEmpty ? 'manual' : 'extracts',
      'variations_net': varNet,
      'extracts_count': counted.length,
      'extracts_gross': gross,
      'extracts_net': counted.fold<double>(0, (a, x) => a + x.net),
      'extracts_paid': counted.fold<double>(0, (a, x) => a + x.paidAmount),
      'retention_held': counted.fold<double>(0, (a, x) => a + x.retention),
      'advance_amount': i == 2 ? 230000.0 : null,
      'advance_paid_on': i == 2 ? _day(220) : null,
      'advance_recovered': counted.fold<double>(0, (a, x) => a + x.advanceRecovery),
      'updated_at': _iso(i),
    }));
    works.add(ContractWork.fromMap({
      'id': 'w-$id',
      'project_id': id,
      'origin_project': id,
      'title': n.$3,
      'company': n.$4,
      'ref_no': n.$1,
      'sort': 1,
      'contract_value': i < 3 ? value : null,
      'executed_value': i < 3 && value != null ? value * 0.4 : null,
    }));
    final st = <String, FormStatus>{};
    final done = (i * 3 + 2) % forms.length;
    for (var f = 0; f < forms.length; f++) {
      st[forms[f].$1] = f < done ? FormStatus.done : (f == done ? FormStatus.wip : FormStatus.todo);
    }
    // مهندس السلامة «لا ينطبق» في العقود التي ليس فيها مهندس سلامة
    if (i != 0) st['f07'] = FormStatus.na;
    statuses[id] = st;
  }
  app.projects = projects;
  app.works = works;
  app.extracts = extracts;
  app.variations = variations;
  // سجل دفعات: دفعتان لكل مستخلص مدفوع في العقد الثالث، ودفعة جزئية للمحال
  final payments = <ExtractPayment>[];
  for (final x in extracts) {
    if (x.paidAmount <= 0) continue;
    final split = x.projectId == 'p-003' && x.isPaid;
    final first = split ? (x.paidAmount * 0.6).roundToDouble() : x.paidAmount;
    payments.add(ExtractPayment.fromMap({
      'id': 'pay-${x.id}-1',
      'extract_id': x.id,
      'project_id': x.projectId,
      'amount': first,
      'paid_on': x.paidOn == null ? _day(10) : _day(DateTime.now().difference(x.paidOn!).inDays + 12),
      'method': 'transfer',
      'ref_no': 'ح-${x.seq}01',
    }));
    if (split) {
      payments.add(ExtractPayment.fromMap({
        'id': 'pay-${x.id}-2',
        'extract_id': x.id,
        'project_id': x.projectId,
        'amount': x.paidAmount - first,
        'paid_on': x.paidOn == null ? _day(5) : _day(DateTime.now().difference(x.paidOn!).inDays),
        'method': 'cheque',
        'ref_no': 'ص-${x.seq}02',
      }));
    }
  }
  app.payments = payments;
  app.statuses = statuses;
  app.engineers = [
    ContractEngineer.fromMap({'id': 'e1', 'project_id': 'p-001', 'kind': 'sup', 'name': 'م. سراج لطيوش', 'assign_no': 'ت-77', 'sort': 1}),
    ContractEngineer.fromMap({'id': 'e2', 'project_id': 'p-001', 'kind': 'qty', 'name': 'م. نوري الحصر', 'assign_no': 'ح-1', 'sort': 1}),
    ContractEngineer.fromMap({'id': 'e3', 'project_id': 'p-001', 'kind': 'saf', 'name': 'م. خالد السلامة', 'assign_no': 'س-4', 'sort': 1}),
    ContractEngineer.fromMap({'id': 'e4', 'project_id': 'p-003', 'kind': 'sup', 'name': 'م. أحمد الفيتوري', 'assign_no': 'ت-81', 'sort': 1}),
    ContractEngineer.fromMap({'id': 'e5', 'project_id': 'p-003', 'kind': 'fol', 'name': 'م. عبدالله القزيري', 'assign_no': 'م-12', 'sort': 1}),
  ];
  app.notifications = [
    AppNotification.fromMap({'id': 'n1', 'created_at': _iso(0), 'kind': 'request', 'title': 'طلب اعتماد جديد', 'body': 'شهادة دفع مستخلص — عقد ع-2026/12'}),
  ];
  app.v2Ready = true;
  app.v3Ready = true;
  app.v4Ready = true;
  app.v5Ready = true;
  app.v6Ready = true;
  app.naReady = true;
  app.showHub = false;
  app.loadedOnce = true;
  _registers(app);
  _tracking(app);
  _documents(app);
  _contractFiles(app);
  _units(app);
  // قوالب الطباعة (الترحيل 22)
  app.v10Ready = true;
  app.printTemplates = [
    PrintTemplate(id: 'pt1', name: 'القالب الرسمي للمكتب', isDefault: true, config: PrintConfig()),
    PrintTemplate(
        id: 'pt2',
        name: 'تقارير اللجنة (أفقي)',
        config: PrintConfig(orientation: 'landscape', accent: 0xFF1F3A5F, watermark: 'للاستخدام الداخلي', showSignatures: true)),
    PrintTemplate(id: 'pt3', name: 'قالبي للمستخلصات', ownerId: 'u-dir', config: PrintConfig(paper: 'A3', font: 'sans')),
  ];
  app.settings = LiveSettings({
    'ai.enabled': true,
    'ai.model': 'claude-sonnet-5-5',
    'finance.currency': 'د.ل',
    'finance.retention_rate': 0.1,
    'finance.tax_rate': 0.02,
    'finance.advance_recovery_rate': 0,
    'finance.deduction_types': [
      {'key': 'stamp', 'label': 'رسم الدمغة', 'rate': 0.005},
      {'key': 'social', 'label': 'الضمان الاجتماعي', 'rate': null},
    ],
  });
  app.settings.applyGlobals();
  app.indexData();
  return app;
}

/// حالة اللقطات: لائحة الأسعار من عينة محفوظة بدل قاعدة البيانات (البحث والتصفح بالقواعد نفسها تقريباً).
class _VisualApp extends AppState {
  _VisualApp(super.client);

  List<PriceItem> priceFixture = [];

  @override
  Future<List<PriceItem>> searchPrices(String listId, String q, {String? chapter, int limit = 80}) async {
    final s = q.trim();
    final rows = priceFixture.where((p) => chapter == null || p.chapter == chapter);
    if (isPriceCode(s)) return rows.where((p) => p.code == s || p.code.startsWith('$s.')).take(limit).toList();
    final words = normalizeArabic(s).split(' ').where((w) => w.isNotEmpty).toList();
    return rows
        .where((p) => p.isItem && words.every((w) => normalizeArabic('${p.code} ${p.fullDesc} ${p.group} ${p.section}').contains(w)))
        .take(limit)
        .toList();
  }

  @override
  Future<List<PriceItem>> browsePrices(String listId, String chapter, int? parentSeq) async =>
      priceFixture.where((p) => p.chapter == chapter && p.parentSeq == parentSeq).toList();

  /// معاينة التوليد كما تعيدها قاعدة البيانات لمثال الفصل 29 (124,730 في 120 يوماً).
  @override
  Future<Map<String, dynamic>> planPreview(String projectId, int totalDays) async {
    // معادلات الترحيل 30 نفسها على بنود مثال الفصل 29
    const phases = [
      ('الأعمال التمهيدية', [('1.1.1.1', 'في حدود ± 0.250 م', 6500.0), ('1.2.1.1', 'مباني - دور تحت الأرض فقط', 9250.0)]),
      ('الأعمال الخرسانية', [('3.2.6.5', 'أعمدة مربعة أو مستطيلة', 75230.0)]),
      ('أعمال تكسيات الحوائط والأرضيات والوزرات', [('7.2.2.1', 'رخام من نوع ابيض كراره', 28750.0)]),
      ('بنود أخرى', [('', 'تنظيف نهائي للموقع', 5000.0)]),
    ];
    const total = 124730.0;
    final out = <Map<String, dynamic>>[];
    var sum = 0;
    for (final (name, items) in phases) {
      final cost = items.fold<double>(0, (a, i) => a + i.$3);
      final maxc = items.map((i) => i.$3).reduce(math.max);
      final days = math.max(3, (totalDays * cost / total).round());
      sum += days;
      out.add({
        'name': name,
        'days': days,
        'cost': cost,
        'items': [for (final i in items) {'code': i.$1, 'title': i.$2, 'cost': i.$3, 'days': math.max(1, (days * math.sqrt(i.$3 / maxc)).round())}],
      });
    }
    return {'total_days': sum, 'items': 5, 'phases': out};
  }
}

/// البرامج الزمنية من المقايسة المعتمدة ومتابعة الإشراف (الترحيلات 30–32): مقايسة معتمدة، وبرنامج معتمد بمراحل
/// لعقد، وبرنامج مسودة لعقد آخر، ومخاطر وعوامل SWOT مترجمة تلقائياً، وتواريخ تحديث النماذج.
void _supervisionPlans(AppState app) {
  final ps = app.projects;
  final bq1 = app.boqSheet('bq1')!;
  app.boqSheets = [
    for (final s in app.boqSheets)
      s.id == 'bq1'
          ? BoqSheet.fromMap({
              'id': s.id, 'project_id': s.projectId, 'list_id': s.listId, 'title': s.title, 'ref_no': s.refNo, 'show_prices': true,
              'created_by': 'u-dir', 'updated_at': _iso(40), 'status': 'approved', 'approved_at': _iso(38), 'approved_by': 'u-dir',
              'lines': [for (final l in bq1.lines) {'seq': l.seq, 'chapter': l.chapter, 'code': l.code, 'desc': l.desc, 'unit': l.unit, 'price': l.price, 'qty': l.qty, 'notes': l.notes}],
              'total': s.total,
            })
          : s,
    BoqSheet.fromMap({
      'id': 'bq3', 'project_id': ps[4].id, 'list_id': 'guide-2026', 'title': 'مقايسة معالجة مختنقات شبكة المياه', 'ref_no': 'م.ش.هـ/ف/2026/0019',
      'show_prices': true, 'created_by': 'u-dir', 'updated_at': _iso(3), 'status': 'approved', 'approved_at': _iso(2), 'approved_by': 'u-dir',
      'lines': [for (final l in bq1.lines.take(4)) {'seq': l.seq, 'chapter': l.chapter, 'code': l.code, 'desc': l.desc, 'unit': l.unit, 'price': l.price, 'qty': (l.qty ?? 10) * 2, 'notes': ''}],
      'total': bq1.total * 1.6,
    }),
  ];
  PmPhase ph(String id, String pid, int sort, String name, [int lag = 0]) =>
      PmPhase.fromMap({'id': id, 'project_id': pid, 'sort': sort, 'name': name, 'lag_days': lag});
  final phases = [
    ph('ph1', ps[1].id, 10, 'تجهيز الموقع'),
    ph('ph2', ps[1].id, 20, 'الأعمال الخرسانية'),
    ph('ph3', ps[1].id, 30, 'أعمال تكسيات الحوائط والأرضيات والوزرات', -10),
    ph('ph4', ps[1].id, 40, 'بنود أخرى'),
    ph('ph5', ps[4].id, 10, 'الأعمال الخرسانية'),
    ph('ph6', ps[4].id, 20, 'أعمال تكسيات الحوائط والأرضيات والوزرات'),
  ];
  // البنود بمددها ثم تواريخها محسوبة بقواعد البرنامج نفسها (PlanLayout)
  List<PmItem> plan(String pid, DateTime start, List<Map<String, dynamic>> raw) {
    final base = [for (final m in raw) PmItem.fromMap({'project_id': pid, 'planned_start': dbDate(start), 'planned_end': dbDate(start), ...m})];
    final l = PlanLayout(start, phases.where((x) => x.projectId == pid).toList(), base);
    return [
      for (final m in raw)
        PmItem.fromMap({
          'project_id': pid,
          ...m,
          'planned_start': dbDate(l.dates[m['id']]!.$1),
          'planned_end': dbDate(l.dates[m['id']]!.$2),
        }),
    ];
  }

  String? seqOf(String code) => bq1.lines.where((l) => l.code == code).firstOrNull?.seq?.toString();
  double costOf(String code) => bq1.lines.where((l) => l.code == code).map((l) => (l.qty ?? 0) * (l.price ?? 0)).fold(0.0, (a, b) => a + b);
  final start1 = _d(150);
  final items1 = plan(ps[1].id, DateTime(start1.year, start1.month, start1.day), [
    {'id': 's0', 'sort': 5, 'code': '', 'title': 'تسليم الموقع وتجهيزه وتسويره', 'source': 'manual', 'phase_id': 'ph1', 'duration_days': 12, 'progress': 100,
      'actual_start': _day(149), 'actual_end': _day(137)},
    {'id': 's1', 'sort': 10, 'code': '3.2.6.5', 'title': 'أعمدة مربعة أو مستطيلة', 'source': 'boq', 'phase_id': 'ph2', 'duration_days': 60, 'unit': 'م3', 'qty': 45,
      'price_seq': seqOf('3.2.6.5'), 'weight': costOf('3.2.6.5'), 'progress': 100, 'actual_start': _day(136), 'actual_end': _day(70)},
    {'id': 's2', 'sort': 20, 'code': '3.2.6.6', 'title': 'كمرات وأعتاب خرسانية', 'source': 'boq', 'phase_id': 'ph2', 'duration_days': 49, 'unit': 'م3', 'qty': 30,
      'price_seq': seqOf('3.2.6.6'), 'weight': costOf('3.2.6.6'), 'progress': 85, 'actual_start': _day(130), 'notes': 'تأخر توريد حديد التسليح'},
    {'id': 's3', 'sort': 30, 'code': '7.2.2.1', 'title': 'رخام من نوع ابيض كراره', 'source': 'boq', 'phase_id': 'ph3', 'duration_days': 70, 'unit': 'م2', 'qty': 120,
      'price_seq': seqOf('7.2.2.1'), 'weight': costOf('7.2.2.1'), 'progress': 40, 'actual_start': _day(60)},
    {'id': 's4', 'sort': 40, 'code': '7.2.2.4', 'title': 'رخام محلي للأرضيات والدرج', 'source': 'boq', 'phase_id': 'ph3', 'duration_days': 55, 'unit': 'م2', 'qty': 64,
      'price_seq': seqOf('7.2.2.4'), 'weight': costOf('7.2.2.4'), 'progress': 20, 'actual_start': _day(40), 'depends_on': 's3', 'offset_days': 0},
    {'id': 's5', 'sort': 50, 'code': '7.2.2.13', 'title': 'وزرات رخام', 'source': 'boq', 'phase_id': 'ph3', 'duration_days': 30, 'unit': 'م.ط',
      'price_seq': seqOf('7.2.2.13'), 'not_applicable': true},
    {'id': 's6', 'sort': 60, 'code': '', 'title': 'تنظيف نهائي للموقع وترحيل المخلفات', 'source': 'boq', 'phase_id': 'ph4', 'duration_days': 10, 'unit': 'مقطوعية',
      'qty': 1, 'weight': 2500},
    {'id': 's7', 'sort': 70, 'code': 'إ-1', 'title': 'سياج مؤقت حول الواجهات', 'source': 'extra', 'phase_id': 'ph2', 'duration_days': 15, 'unit': 'م.ط', 'qty': 140,
      'weight': 8400, 'progress': 100, 'actual_start': _day(120), 'actual_end': _day(104)},
  ]);
  final start4 = _d(-10);
  final items4 = plan(ps[4].id, DateTime(start4.year, start4.month, start4.day), [
    {'id': 'w1', 'sort': 10, 'code': '3.2.6.5', 'title': 'أعمدة مربعة أو مستطيلة', 'source': 'boq', 'phase_id': 'ph5', 'duration_days': 72, 'unit': 'م3', 'qty': 90, 'weight': 169000},
    {'id': 'w2', 'sort': 20, 'code': '3.2.6.6', 'title': 'كمرات وأعتاب خرسانية', 'source': 'boq', 'phase_id': 'ph5', 'duration_days': 51, 'unit': 'م3', 'qty': 60, 'weight': 92000},
    {'id': 'w3', 'sort': 30, 'code': '7.2.2.1', 'title': 'رخام من نوع ابيض كراره', 'source': 'boq', 'phase_id': 'ph6', 'duration_days': 28, 'unit': 'م2', 'qty': 240, 'weight': 69000},
    {'id': 'w4', 'sort': 40, 'code': '7.2.2.4', 'title': 'رخام محلي للأرضيات والدرج', 'source': 'boq', 'phase_id': 'ph6', 'duration_days': 21, 'unit': 'م2', 'qty': 128, 'weight': 31000},
    {'id': 'w5', 'sort': 50, 'code': 'إ-1', 'title': 'تحويل مؤقت لخط المياه أثناء التنفيذ', 'source': 'extra', 'phase_id': 'ph5', 'duration_days': 9, 'weight': 12000},
  ]);
  app.pmItems = [for (final i in app.pmItems) if (i.projectId != ps[1].id) i, ...items1, ...items4];
  app.pmPhases = phases;
  PmPlan pl(String pid, String status, DateTime start, int version) => PmPlan.fromMap({
        'id': 'pl-$pid', 'project_id': pid, 'status': status, 'start_date': dbDate(start), 'version': version,
        'approved_at': status == 'approved' ? _iso(140) : null, 'approved_by': status == 'approved' ? 'u-dir' : null,
      });
  DateTime first(String pid) => app.pmItems.where((i) => i.projectId == pid).map((i) => i.plannedStart).reduce((a, b) => a.isBefore(b) ? a : b);
  app.pmPlans = {
    for (final p in [ps[0], ps[2], ps[3]]) p.id: pl(p.id, 'approved', first(p.id), 1),
    ps[1].id: pl(ps[1].id, 'approved', DateTime(start1.year, start1.month, start1.day), 2),
    ps[4].id: pl(ps[4].id, 'draft', DateTime(start4.year, start4.month, start4.day), 0),
  };
  // تحديثات النماذج (لتواريخ مراحل دورة الحياة)
  app.formDates = {
    for (final p in ps)
      p.id: {for (final (k, d) in const [('f02', 170), ('f04', 168), ('f05', 168), ('f06', 167), ('f07', 167), ('f08', 160), ('f09', 155),
          ('f10', 90), ('f11', 88), ('f22', 60), ('f12', 58), ('f14', 50), ('f13', 45), ('f23', 44), ('f24', 40)]) k: _d(d)},
  };
  // الترجمة التلقائية إلى المخاطر وSWOT
  app.risks = [
    ...app.risks,
    Risk.fromMap({'id': 'risk-a1', 'code': 'R09', 'project_id': ps[1].id, 'category': 'زمني', 'phase': 'التنفيذ', 'owner': 'الإشراف',
      'description': 'تأخر البند «كمرات وأعتاب خرسانية» عن البرنامج الزمني المعتمد — ${ps[1].name}',
      'effect': 'الإنجاز 85.0% مقابل 100.0% مخطط حتى اليوم (تجاوز نهايته المخططة بـ32 يوماً)، ونصيبه 21.6% من وزن العقد',
      'probability': 5, 'impact': 5, 'time_impact_days': 32, 'status': 'open', 'response': 'mitigate', 'auto_key': 'pm_item:s2', 'auto_active': true,
      'registered_on': _day(30), 'department': 'الإشراف والتنسيق', 'notes': 'سُجّل تلقائياً من متابعة البرنامج الزمني'}),
    Risk.fromMap({'id': 'risk-a2', 'code': 'R10', 'project_id': ps[1].id, 'category': 'زمني', 'phase': 'التنفيذ', 'owner': 'الإشراف',
      'description': 'تأخر تنفيذ العقد عن برنامجه الزمني المعتمد — ${ps[1].name}',
      'effect': 'الإنجاز الكلي الموزون 61.4% مقابل 72.9% مخطط (فارق يعادل 18 يوماً من مدة البرنامج)',
      'probability': 3, 'impact': 4, 'time_impact_days': 18, 'status': 'open', 'response': 'mitigate', 'auto_key': 'pm_plan:${ps[1].id}', 'auto_active': true,
      'registered_on': _day(20), 'department': 'الإشراف والتنسيق'}),
    Risk.fromMap({'id': 'risk-a3', 'code': 'R11', 'project_id': ps[1].id, 'category': 'زمني', 'phase': 'التنفيذ', 'owner': 'الإشراف',
      'description': 'تأخر البند «أعمدة مربعة أو مستطيلة» عن البرنامج الزمني المعتمد — ${ps[1].name}',
      'effect': 'الإنجاز 100.0% · تعافى البند', 'probability': 4, 'impact': 5, 'status': 'closed', 'closed_on': _day(70),
      'auto_key': 'pm_item:s1', 'auto_active': false, 'registered_on': _day(95)}),
  ];
  app.swotFactors = [
    ...app.swotFactors,
    SwotFactor.fromMap({'id': 'f-W901', 'code': 'W901', 'kind': 'W', 'factor': 'تأخر تنفيذ «${ps[1].name}» عن برنامجه الزمني',
      'impact': 'سلبي: متأخر بما يعادل 18 يوماً (الإنجاز 61.4% مقابل 72.9% مخطط)', 'importance': 4, 'urgency': 3, 'source': 'البرنامج الزمني',
      'department': 'الإشراف والتنسيق', 'sort': 900, 'auto_key': 'pm_plan:${ps[1].id}:W', 'project_id': ps[1].id}),
    SwotFactor.fromMap({'id': 'f-T901', 'code': 'T901', 'kind': 'T', 'factor': 'توقع تجاوز «${ps[1].name}» نهاية برنامجه الزمني',
      'impact': 'سلبي: إنهاء متوقع بعد نهاية البرنامج بـ21 يوماً', 'importance': 4, 'urgency': 3, 'source': 'البرنامج الزمني',
      'department': 'الإشراف والتنسيق', 'sort': 900, 'auto_key': 'pm_plan:${ps[1].id}:T', 'project_id': ps[1].id}),
    SwotFactor.fromMap({'id': 'f-S901', 'code': 'S901', 'kind': 'S', 'factor': 'تقدم تنفيذ «${ps[3].name}» على برنامجه الزمني',
      'impact': 'إيجابي: متقدم بما يعادل 9 أيام (الإنجاز 64.0% مقابل 58.1% مخطط)', 'importance': 3, 'urgency': 2, 'source': 'البرنامج الزمني',
      'department': 'الإشراف والتنسيق', 'sort': 900, 'auto_key': 'pm_plan:${ps[3].id}:S', 'project_id': ps[3].id}),
  ];
  app.v15Ready = true;
  app.v16Ready = true;
  app.v17Ready = true;
}

/// تخصيص الواجهة والأفكار بالقسم والصفحة، ومقايسة مسودة بنودها في برنامج مسودة (الترحيل 33).
/// ما تحجبه قاعدة البيانات عن مستخدم معزول في قسمه (الترحيل 34): العقود خارج إشرافه أساسيات وحدها،
/// وحالات النماذج غير المسندة إليه لا تُقرأ.
void _isolateAs(AppState app, Profile me, UserScope scope, List<Project> all, Map<String, Map<String, FormStatus>> statuses) {
  app.me = me;
  app.people = {...app.people, me.id: me};
  app.scope = scope;
  app.projects = [
    for (final p in all)
      scope.allProjects || scope.supervised.contains(p.id)
          ? p
          : Project.ref({
              'id': p.id, 'assign_no': p.assignNo, 'code': p.code, 'name': p.name, 'owner': p.owner, 'company': p.company,
              'department': p.department, 'contract_no': p.contractNo, 'sort_order': p.sortOrder,
            }),
  ];
  app.statuses = {
    for (final e in statuses.entries)
      e.key: scope.allProjects || scope.supervised.contains(e.key)
          ? {...e.value}
          : {for (final f in e.value.entries) if (scope.forms.contains(f.key)) f.key: f.value},
  };
}

void _layoutIdeas(AppState app, {String style = 'icons'}) {
  final ps = app.projects;
  app.v11Ready = true;
  app.v18Ready = true;
  app.settings = LiveSettings({
    ...app.settings.raw,
    'ui.layout': {
      'groups': [
        {'key': 'g1', 'name': 'الأقسام الهندسية'},
        {'key': 'g2', 'name': 'المكاتب والأدوات'},
      ],
      'hub_style': style,
      'section_order': ['supervision', 'docs', 'cycle', 'risks', 'heritage', 'acceptance', 'swot', 'planning_qa', 'safety', 'print', 'chat', 'manual', 'security'],
      'sections': {
        'supervision': {'group': 'g1', 'color': 'indigo'},
        'docs': {'group': 'g1', 'icon': 'architecture', 'name': 'الشؤون الفنية والتصاميم'},
        'cycle': {'group': 'g1'},
        'risks': {'group': 'g1'},
        'heritage': {'group': 'g1', 'color': 'brown'},
        'acceptance': {'group': 'g1'},
        'planning_qa': {'group': 'g2'},
        'safety': {'group': 'g2'},
        'print': {'group': 'g2'},
        'chat': {'group': 'g2'},
        'manual': {'group': 'g2', 'hidden': true},
      },
      'pages': {
        '65': {'section': 'supervision', 'label': 'لائحة الأسعار المرجعية'},
        '73': {'icon': 'checklist'},
      },
      'page_order': {
        'supervision': [72, 73, 65, 70, 71],
      },
    },
  });
  app.settings.applyGlobals();
  Idea idea(String id, String title, String status, String? section,
          {int? page, String label = '', String category = 'feature', String priority = 'normal', int days = 3, String body = ''}) =>
      Idea.fromMap({
        'id': id, 'title': title, 'body': body, 'category': category, 'priority': priority, 'status': status, 'response': '',
        'created_by': 'u-dir', 'created_at': _iso(days), 'updated_at': _iso(days), 'github_url': '',
        'section': section, 'page_id': page, 'page_label': label,
      });
  app.ideas = [
    idea('i1', 'منحنى المستخلصات المعتمدة مقابل الإنجاز في لوحة الإشراف', 'new', 'supervision', page: 72, label: 'لوحة الإشراف',
        priority: 'high', days: 1, body: 'منحنى تراكمي شهري لكل عقد: قيمة المستخلصات المعتمدة مقابل الإنجاز المخطط والفعلي.'),
    idea('i2', 'تصفية بنود العقود بمرحلة التنفيذ', 'planned', 'supervision', page: 73, label: 'بنود العقود', days: 4),
    idea('i3', 'تنبيه حين يتأخر التقرير اليومي أكثر من يومين', 'in_progress', 'supervision', page: 70, label: 'التقارير اليومية', days: 9, category: 'data'),
    idea('i4', 'نسخ مقايسة سابقة نقطةَ بداية لمقايسة جديدة', 'new', 'docs', page: 66, label: 'مُعِدّ المقايسات', days: 2),
    idea('i5', 'إظهار سعر 2025 بجانب سعر 2026', 'done', 'docs', page: 65, label: 'لائحة الأسعار', days: 30),
    idea('i6', 'لوحة عرض مختصرة لاجتماع اللجنة', 'new', 'risks', page: 51, label: 'لوحة العرض', category: 'design', days: 5),
    idea('i7', 'ربط المخالفة بصورة من الموقع', 'planned', 'safety', page: 113, label: 'المخالفات', days: 12),
    idea('i8', 'وضع ليلي تلقائي بحسب الوقت', 'new', null, category: 'design', priority: 'low', days: 6),
    idea('i9', 'تصدير سجل العقود بقالب اللجنة', 'rejected', 'cycle', page: 1, label: 'العقود', days: 40),
    idea('i10', 'إسناد الفكرة إلى مسؤول تنفيذها', 'new', 'supervision', days: 2),
  ];
  // مقايسة مسودة بنودها في البرنامج المسودة للعقد الخامس (لنافذة تأكيد الحذف)
  app.boqSheets = [
    for (final b in app.boqSheets)
      b.id == 'bq3'
          ? BoqSheet.fromMap({
              'id': b.id, 'project_id': b.projectId, 'list_id': b.listId, 'title': b.title, 'ref_no': b.refNo, 'show_prices': true,
              'created_by': 'u-dir', 'updated_at': _iso(1), 'status': 'draft',
              'lines': [for (final l in b.lines) {'seq': l.seq, 'chapter': l.chapter, 'code': l.code, 'desc': l.desc, 'unit': l.unit, 'price': l.price, 'qty': l.qty, 'notes': l.notes}],
              'total': b.total,
            })
          : b,
  ];
  app.pmItems = [for (final i in app.pmItems) i.projectId == ps[4].id && i.source == 'boq' ? i.copyWith(boqSheetId: 'bq3') : i];
}

/// بيانات تجريبية لبنود الجداول الزمنية ولائحة الأسعار والمقايسات (الترحيلات 27–29).
void _planning(AppState app) {
  final raw = jsonDecode(File('visual_test/fixtures/prices_2026_sample.json').readAsStringSync()) as List;
  final items = [for (final m in raw) PriceItem.fromMap({...Map<String, dynamic>.from(m as Map), 'list_id': 'guide-2026'})];
  (app as _VisualApp).priceFixture = items;
  app.priceLists = [
    PriceList.fromMap({
      'id': 'guide-2026',
      'title': 'لائحة الأسعار الاسترشادية 2026',
      'year': 2026,
      'source': 'دولة ليبيا — حكومة الوحدة الوطنية',
      'currency': 'دينار',
      'active': true,
      'chapters': [
        {'key': 'buildings', 'name': 'أعمال المباني العامة والصيانة العامة'},
        {'key': 'roads', 'name': 'أعمال شبكات الطرق والأرصفة'},
        {'key': 'water', 'name': 'أعمال شبكات مياه الشرب والصرف الصحي وصرف مياه الأمطار'},
        {'key': 'tanks', 'name': 'أعمال الخزانات'},
        {'key': 'gardens', 'name': 'أعمال الحدائق والملاعب'},
        {'key': 'power', 'name': 'أعمال شبكات الكهرباء والإنارة الخارجية'},
      ],
    }),
  ];
  Map<String, dynamic> lj(String code, double? qty, [String notes = '']) {
    final p = items.firstWhere((x) => x.chapter == 'buildings' && x.code == code);
    return {'seq': p.seq, 'chapter': p.chapter, 'code': p.code, 'desc': p.fullDesc, 'unit': p.unit, 'price': p.price, 'qty': qty, 'notes': notes};
  }

  Map<String, dynamic> sheet(String id, String? project, String title, String ref, bool prices, List<Map<String, dynamic>> lines, int ago) => {
        'id': id,
        'project_id': project,
        'list_id': 'guide-2026',
        'title': title,
        'ref_no': ref,
        'show_prices': prices,
        'created_by': 'u-dir',
        'updated_at': _iso(ago),
        'lines': lines,
        'total': lines.fold<double>(0, (s, l) => s + ((l['qty'] as num?) ?? 0) * ((l['price'] as num?) ?? 0)),
      };
  final ps = app.projects;
  app.boqSheets = [
    BoqSheet.fromMap(sheet('bq1', ps[1].id, 'مقايسة ترميم مبنى القنصلية – المرحلة الأولى', 'م.ش.هـ/ف/2026/0012', true, [
      lj('3.2.6.5', 45, 'أعمدة الطابق الأرضي'),
      lj('3.2.6.6', 30),
      lj('7.2.2.1', 120, 'الصالة الرئيسية والممرات'),
      lj('7.2.2.4', 64),
      lj('7.2.2.13', null, 'الكمية بعد الحصر'),
      {'seq': null, 'chapter': '', 'code': '', 'desc': 'تنظيف نهائي للموقع وترحيل المخلفات', 'unit': 'مقطوعية', 'price': 2500, 'qty': 1, 'notes': ''},
    ], 1)),
    BoqSheet.fromMap(sheet('bq2', null, 'مقايسة كميات أعمال الرخام للمباني الإدارية', '', false, [
      lj('7.2.2.2', 340),
      lj('7.2.2.3', 180),
    ], 6)),
  ];
  PmItem it(String id, String pid, int sort, String title, int start, int end, double? w, double progress, {int? actualEnd, String notes = ''}) =>
      PmItem.fromMap({
        'id': id,
        'project_id': pid,
        'sort': sort,
        'code': '$sort',
        'title': title,
        'planned_start': _day(start),
        'planned_end': _day(end),
        'weight': w,
        'progress': progress,
        'actual_start': progress > 0 ? _day(start - 2) : null,
        'actual_end': actualEnd == null ? null : _day(actualEnd),
        'notes': notes,
      });
  app.pmItems = [
    it('a1', ps[0].id, 1, 'أعمال التمهيد والحفر', 280, 200, 15, 100, actualEnd: 205),
    it('a2', ps[0].id, 2, 'طبقات الأساس والأساس المساعد', 210, 60, 35, 82),
    it('a3', ps[0].id, 3, 'الطبقات الإسفلتية', 90, -60, 30, 28, notes: 'تأخر توريد البيتومين'),
    it('a4', ps[0].id, 4, 'الأرصفة والجزر الوسطية', 40, -120, 12, 5),
    it('a5', ps[0].id, 5, 'العلامات والإشارات المرورية', -60, -150, 8, 0),
    it('b1', ps[1].id, 1, 'التدعيم الإنشائي للجدران الحاملة', 250, 120, 40, 70, notes: 'نقص العمالة المتخصصة'),
    it('b2', ps[1].id, 2, 'ترميم الواجهات الحجرية', 150, -30, 35, 30),
    it('b3', ps[1].id, 3, 'الأعمال الكهربائية والصحية', 60, -90, 25, 5),
    it('c1', ps[2].id, 1, 'حفر الخنادق والفرش', 200, 100, null, 100, actualEnd: 104),
    it('c2', ps[2].id, 2, 'توريد وتركيب الأنابيب', 120, -20, null, 95),
    it('c3', ps[2].id, 3, 'غرف التفتيش والمحابس', 60, -60, null, 60),
    it('c4', ps[2].id, 4, 'الاختبارات والتعقيم وإعادة الرصف', -30, -90, null, 0),
    it('d1', ps[3].id, 1, 'الهيكل الخرساني', 180, 30, 50, 92),
    it('d2', ps[3].id, 2, 'المباني والتشطيبات', 60, -100, 50, 36),
  ];
  app.v14Ready = true;
}

/// بيانات تجريبية لمتابعة المشاريع (الإصدار السابع).
void _tracking(AppState app) {
  final ps = app.projects;
  final types = ['طرق', 'ترميم مبانٍ تراثية', 'مرافق وشبكات', 'مدارس', 'جسور', 'إسكان'];
  app.schedules = {
    for (var i = 0; i < ps.length && i < 6; i++)
      ps[i].id: PmSchedule.fromMap({
        'project_id': ps[i].id,
        'project_type': types[i],
        'location': 'القطاع (${i + 1})',
        'consultant': 'المكتب الاستشاري (${i % 3 + 1})',
        'op_status': i == 5 ? 'not_started' : 'running',
        'start_date': _day(300 - i * 20),
        'end_date': _day(-200 - i * 30),
        'display_name': i < 3 ? ['تأهيل طريق الصابري', 'ترميم مبنى القنصلية', 'شبكات وسط البلاد'][i] : '',
      }),
  };
  final ms = <PmProgress>[];
  for (var i = 0; i < ps.length && i < 5; i++) {
    for (var k = 0; k < 8; k++) {
      final planned = (0.08 + k * 0.09).clamp(0, 1).toDouble();
      final factor = [0.92, 0.8, 0.97, 1.06, 0.88][i];
      ms.add(PmProgress.fromMap({
        'id': 'pg-$i-$k',
        'project_id': ps[i].id,
        'measured_on': _day(8 * 30 - k * 30 - i),
        'planned': planned,
        'actual': (planned * factor).clamp(0, 1).toDouble(),
        'obstacles': k == 7 && i == 1 ? 'نقص العمالة الفنية المتخصصة' : '',
        'prepared_by': 'الإشراف والتنسيق',
      }));
    }
  }
  app.measurements = ms;
  app.riskReviews = [
    for (final r in app.risks.take(5))
      RiskReview.fromMap({
        'id': 'rv-${r.code}',
        'risk_id': r.id,
        'reviewed_on': _day(20),
        'probability': r.probability > 1 ? r.probability - 1 : 1,
        'impact': r.impact,
        'actions_done': 'متابعة الإجراء الوقائي',
        'progress': 0.5,
        'reviewer': 'الإشراف والتنسيق',
      }),
  ];
  app.pmIssues = [
    PmIssue.fromMap({'id': 'i1', 'code': 'I01', 'project_id': ps[0].id, 'detected_on': _day(40), 'description': 'تأخر اعتماد عينات الخلطة الإسفلتية',
      'category': 'جودة', 'priority': 'medium', 'party': 'consultant', 'department': 'المطابقة والاستلام', 'target_date': _day(20), 'status': 'open'}),
    PmIssue.fromMap({'id': 'i2', 'code': 'I02', 'project_id': ps[1].id, 'detected_on': _day(25), 'description': 'نقص العمالة الفنية المتخصصة في أعمال الترميم',
      'category': 'زمني', 'priority': 'high', 'party': 'contractor', 'department': 'الترميم', 'target_date': _day(-5), 'status': 'in_progress'}),
    PmIssue.fromMap({'id': 'i3', 'code': 'I03', 'project_id': ps[2].id, 'detected_on': _day(60), 'description': 'اكتشاف خط مياه رئيسي غير موثق',
      'category': 'موقعي', 'priority': 'high', 'party': 'utilities', 'target_date': _day(30), 'status': 'closed', 'closed_on': _day(28)}),
  ];
  app.pmDelays = [
    PmDelay.fromMap({'id': 'd1', 'code': 'D01', 'project_id': ps[0].id, 'description': 'تأخر تسليم جزء من الموقع بسبب عوائق قائمة',
      'cause': 'الموقع وتسليمه', 'party': 'owner', 'delay_class': 'excusable_comp', 'critical': true, 'start_date': _day(200), 'end_date': _day(160),
      'eot_requested': 40, 'eot_approved': 30}),
    PmDelay.fromMap({'id': 'd2', 'code': 'D02', 'project_id': ps[1].id, 'description': 'نقص العمالة المتخصصة في الترميم',
      'cause': 'المقاول – الموارد والإدارة', 'party': 'contractor', 'delay_class': 'non_excusable', 'critical': true, 'start_date': _day(45)}),
    PmDelay.fromMap({'id': 'd3', 'code': 'D03', 'project_id': ps[2].id, 'description': 'اكتشاف مرافق مدفونة غير موثقة',
      'cause': 'المرافق والجهات الخدمية', 'party': 'utilities', 'delay_class': 'excusable', 'critical': true, 'start_date': _day(110), 'end_date': _day(58),
      'eot_requested': 52}),
  ];
  app.pmChanges = [
    PmChange.fromMap({'id': 'c1', 'code': 'C01', 'project_id': ps[0].id, 'submitted_on': _day(250), 'description': 'إضافة طبقة أساس في مقطع ضعيف التربة',
      'change_type': 'أعمال إضافية', 'source': 'consultant', 'reason': 'ظروف موقع غير متوقعة', 'cost_estimate': 420000, 'cost_approved': 385000,
      'time_requested': 20, 'time_approved': 15, 'status': 'approved', 'decided_on': _day(225), 'approval_ref': 'ق.ت/2026/014'}),
    PmChange.fromMap({'id': 'c2', 'code': 'C02', 'project_id': ps[1].id, 'submitted_on': _day(40), 'description': 'أعمال تدعيم إنشائي للجدار الحامل',
      'change_type': 'أعمال إضافية', 'source': 'site', 'reason': 'متطلبات الحفاظ التراثي', 'cost_estimate': 650000, 'time_requested': 45,
      'status': 'under_study'}),
  ];
  app.pmLessons = [
    PmLesson.fromMap({'id': 'l1', 'code': 'L01', 'project_id': ps[2].id, 'documented_on': _day(50), 'phase': 'التنفيذ', 'domain': 'موقعي',
      'lesson_type': 'negative', 'situation': 'اكتشاف مرافق مدفونة غير موثقة بعد بدء الحفر',
      'lesson': 'إلزام المقاول بكشف تجريبي قبل الحفر في كل مقطع وتحديث خرائط المرافق قبل الطرح', 'apply_mechanism': 'تعديل إجراء', 'status': 'approved'}),
    PmLesson.fromMap({'id': 'l2', 'code': 'L02', 'documented_on': _day(10), 'phase': 'المتابعة', 'domain': 'حوكمة', 'lesson_type': 'positive',
      'situation': 'التحقق الميداني من نسب الإنجاز قبل اعتماد المستخلص كشف فروقات', 'lesson': 'اعتماد التحقق الميداني الشهري شرطاً لاعتماد أي مستخلص',
      'status': 'proposed'}),
  ];
  app.pmEvaluations = [
    for (var i = 0; i < ps.length && i < 4; i++)
      PmEvaluation.fromMap({'id': 'ev$i', 'project_id': ps[i].id, 'company': ps[i].company, 'evaluated_on': _day(45), 'quality': 4 - i % 2,
        'safety': 4, 'schedule': 3 - i % 2, 'resources': 4, 'cooperation': 3 + i % 2, 'documentation': 3, 'evaluator': 'الإشراف والتنسيق'}),
  ];
  app.v7Ready = true;
}

/// بيانات تجريبية لسجل المخاطر وتحليل SWOT.
void _registers(AppState app) {
  const risks = [
    ('R01', 'تأخر اعتماد المخططات التنفيذية من الاستشاري', 'فني', 'التصميم', 4, 4, 2, 3, 'in_progress', -3, 'مدير المشروع'),
    ('R02', 'تجاوز الكميات المنفذة للمقايسة دون أمر تغيير معتمد', 'تعاقدي', 'التنفيذ', 4, 5, 2, 4, 'open', 4, 'العقود'),
    ('R03', 'ضعف تنسيق الخدمات تحت الأرض مع شركات المرافق', 'تنسيق', 'التنفيذ', 3, 4, 2, 2, 'open', 20, 'PMO'),
    ('R04', 'تأخر صرف المستخلصات الجارية', 'مالي', 'المتابعة', 4, 3, null, null, 'open', 10, 'المالية'),
    ('R05', 'حوادث في المواقع المأهولة بوسط البلاد', 'سلامة', 'التنفيذ', 2, 5, 1, 4, 'in_progress', 30, 'السلامة'),
    ('R06', 'نقص توريد الحديد والإسمنت', 'توريد', 'التنفيذ', 3, 3, 2, 2, 'on_hold', 60, 'المشتريات'),
    ('R07', 'عدم مطابقة عينات الخرسانة', 'جودة', 'التنفيذ', 2, 4, 1, 3, 'closed', null, 'الجودة'),
    ('R08', 'اكتشاف آثار أثناء الحفر', 'موقعي', 'التنفيذ', 2, 3, null, null, 'open', null, 'الاستشاري'),
  ];
  app.risks = [
    for (final r in risks)
      Risk.fromMap({
        'id': 'risk-${r.$1}',
        'code': r.$1,
        'description': r.$2,
        'category': r.$3,
        'phase': r.$4,
        'probability': r.$5,
        'impact': r.$6,
        'residual_probability': r.$7,
        'residual_impact': r.$8,
        'status': r.$9,
        'next_review': r.$10 == null ? null : _day(-r.$10!),
        'closed_on': r.$9 == 'closed' ? _day(5) : null,
        'registered_on': _day(40),
        'owner': r.$11,
        'project_group': 'الطرق والجسور',
        'mitigation': 'متابعة أسبوعية مع الجهة المعنية وتوثيق المراسلات',
        'response': 'mitigate',
      }),
  ];
  const factors = [
    ('S01', 'S', 'خبرة فنية متراكمة في مشاريع الإعمار', 5, 4, 4),
    ('S02', 'S', 'منظومة رقمية لمتابعة الدورة المستندية', 4, 3, 4),
    ('S03', 'S', 'دعم الإدارة العليا للمكتب', 4, 2, 3),
    ('W01', 'W', 'نقص المهندسين المتخصصين في الحصر', 5, 5, 1),
    ('W02', 'W', 'ضعف أرشفة الوثائق الورقية', 4, 4, 2),
    ('W03', 'W', 'تداخل الصلاحيات بين الأقسام', 3, 3, 2),
    ('O01', 'O', 'تمويل مستقر لمشروع إعادة الإعمار', 5, 4, 3),
    ('O02', 'O', 'توفر شركات مقاولات محلية مؤهلة', 4, 3, 3),
    ('T01', 'T', 'تقلب أسعار مواد البناء', 4, 5, 2),
    ('T02', 'T', 'تأخر قرارات الجهات الخارجية', 4, 4, 2),
  ];
  app.swotFactors = [
    for (var i = 0; i < factors.length; i++)
      SwotFactor.fromMap({
        'id': 'f-${factors[i].$1}',
        'code': factors[i].$1,
        'kind': factors[i].$2,
        'factor': factors[i].$3,
        'importance': factors[i].$4,
        'urgency': factors[i].$5,
        'rating': factors[i].$6,
        'department': 'قسم الإشراف والتنسيق',
        'source': 'الملف الأصلي',
        'sort': i + 1,
      }),
  ];
  const strategies = [
    ('SO1', 'SO', 'توظيف المنظومة الرقمية لتسريع دورة المستخلصات', ['S02'], ['O01'], 'high'),
    ('WO1', 'WO', 'التعاقد مع مهندسي حصر من الشركات المحلية', ['W01'], ['O02'], 'high'),
    ('ST1', 'ST', 'تثبيت أسعار المواد الرئيسية في العقود', ['S01'], ['T01'], 'medium'),
    ('WT1', 'WT', 'توحيد مصفوفة الصلاحيات وتقليل الاعتماد على قرارات خارجية', ['W03'], ['T02'], 'medium'),
  ];
  app.swotStrategies = [
    for (var i = 0; i < strategies.length; i++)
      SwotStrategy.fromMap({
        'id': 'st-${strategies[i].$1}',
        'code': strategies[i].$1,
        'kind': strategies[i].$2,
        'strategy': strategies[i].$3,
        'internal_factors': strategies[i].$4,
        'external_factors': strategies[i].$5,
        'priority': strategies[i].$6,
        'lead_department': 'إدارة المكتب',
        'sort': i + 1,
      }),
  ];
  const actions = [
    ('A01', 'SO1', 'ربط المستخلصات بالدفعات إلكترونياً', 'in_progress', 0.6, 120, 6),
    ('A02', 'WO1', 'إعلان احتياج مهندسي حصر', 'in_progress', 0.2, 150, 4),
    ('A03', 'ST1', 'إضافة بند تعديل الأسعار للعقود الجديدة', 'not_started', null, 60, 3),
    ('A04', 'WT1', 'إصدار دليل الصلاحيات', 'completed', 1.0, 200, 3),
    ('A05', 'WO1', 'برنامج تدريب على الحصر بالمنظومة', 'stalled', 0.1, 90, 2),
  ];
  app.swotActions = [
    for (var i = 0; i < actions.length; i++)
      SwotAction.fromMap({
        'id': 'a-${actions[i].$1}',
        'code': actions[i].$1,
        'strategy_code': actions[i].$2,
        'factors': app.swotStrategies.firstWhere((s) => s.code == actions[i].$2).factors,
        'action': actions[i].$3,
        'status': actions[i].$4,
        'progress': actions[i].$5,
        'start_date': _day(actions[i].$6),
        'duration_months': actions[i].$7,
        'department': i.isEven ? 'قسم الإشراف والتنسيق' : 'قسم الشؤون الفنية',
        'owner': 'رئيس القسم',
        'priority': 'high',
        'sort': i + 1,
      }),
  ];
}

/// صور تجريبية للتصاميم والتقارير (لوحات مرسومة بألوان مختلفة).
final Map<String, MemoryImage> _demoImages = {};

MemoryImage _demoImage(String key, int seed) => _demoImages.putIfAbsent(key, () {
      final im = img.Image(width: 960, height: 600);
      const palettes = [
        [(236, 229, 210), (138, 106, 30), (60, 70, 90)],
        [(220, 232, 238), (43, 98, 168), (40, 50, 70)],
        [(226, 238, 228), (46, 125, 79), (50, 60, 55)],
        [(244, 226, 220), (180, 68, 28), (70, 50, 45)],
      ];
      final p = palettes[seed % palettes.length];
      img.fill(im, color: img.ColorRgb8(p[0].$1, p[0].$2, p[0].$3));
      final line = img.ColorRgb8(p[2].$1, p[2].$2, p[2].$3);
      final accent = img.ColorRgb8(p[1].$1, p[1].$2, p[1].$3);
      // مخطط واجهة: كتلة المبنى ونوافذه وخط الأرض
      img.fillRect(im, x1: 140 + seed * 10, y1: 140, x2: 820 - seed * 10, y2: 520, color: img.ColorRgb8(250, 248, 242));
      img.drawRect(im, x1: 140 + seed * 10, y1: 140, x2: 820 - seed * 10, y2: 520, color: line, thickness: 4);
      for (var r = 0; r < 3; r++) {
        for (var c = 0; c < 5; c++) {
          final x = 190 + c * 120, y = 180 + r * 105;
          img.fillRect(im, x1: x, y1: y, x2: x + 70, y2: y + 60, color: c == seed % 5 ? accent : img.ColorRgb8(200, 210, 220));
          img.drawRect(im, x1: x, y1: y, x2: x + 70, y2: y + 60, color: line, thickness: 2);
        }
      }
      img.fillRect(im, x1: 440, y1: 430, x2: 520, y2: 520, color: accent);
      img.drawLine(im, x1: 40, y1: 522, x2: 920, y2: 522, color: line, thickness: 5);
      img.fillRect(im, x1: 120 + seed * 10, y1: 100, x2: 840 - seed * 10, y2: 140, color: accent);
      return MemoryImage(Uint8List.fromList(img.encodePng(im)));
    });

/// بيانات تجريبية للمستندات الفنية والتقارير اليومية.
/// ملف العقد (الترحيل 35): مرفقات مصنّفة لعقد p-003 بإصداراتها وملفاتها، وقرار تكليف مربوط بالمهندس e4.
void _contractFiles(AppState app) {
  final items = [...app.docs.items];
  final revs = [...app.docs.revisions];
  final files = [...app.docs.files];
  var fid = 9000;
  void file(String rev, String name, String mime, int size) {
    fid++;
    files.add(DocFile.fromMap({
      'id': 'file$fid', 'revision_id': rev, 'path': 'doc/$rev/f$fid', 'name': name, 'mime': mime, 'size_bytes': size,
      'sort': fid, 'created_by': 'u-1', 'created_at': _iso(3),
    }));
  }

  const pdfMime = 'application/pdf';
  const xlsx = 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
  const atts = [
    ('at1', 'contract', 'نسخة العقد الموقّعة', 'ع-2026/41', 'مكتب العقود', 40, null),
    ('at2', 'contract', 'ملحق تمديد المدة 30 يوماً', 'م/3', 'مكتب العقود', 3, null),
    ('at3', 'boq', 'جدول الكميات الموقّع مع العقد', 'BOQ-41', 'قسم الشؤون الفنية', 38, null),
    ('at4', 'drawings', 'المخطط العام للموقع', 'DWG-12', 'الاستشاري', 35, null),
    ('at5', 'handover', 'محضر تسليم الموقع', 'ت م/7', 'لجنة التسليم', 33, null),
    ('at6', 'assignment', 'قرار تكليف م. أحمد الفيتوري', 'ت-81', 'مدير المكتب', 32, 'e4'),
    ('at7', 'extract', 'المستخلص الثاني الموقّع', 'مس/2', 'أثمار', 8, null),
    ('at8', 'other', 'موقع المشروع على الخريطة', '', '', 30, null),
  ];
  for (final a in atts) {
    items.add(DocItem.fromMap({
      'id': a.$1, 'kind': 'attachment', 'project_id': 'p-003', 'category': a.$2, 'title': a.$3, 'ref_no': a.$4, 'party': a.$5,
      'doc_date': _day(a.$6), 'engineer_id': a.$7, 'status': 'active', 'created_by': 'u-1', 'updated_at': _iso(a.$6),
    }));
    revs.add(DocRevision.fromMap({'id': '${a.$1}r1', 'item_id': a.$1, 'rev_no': 1, 'rev_date': _day(a.$6), 'created_by': 'u-1', 'created_at': _iso(a.$6)}));
  }
  file('at1r1', 'العقد الموقّع.pdf', pdfMime, 2480000);
  revs.add(DocRevision.fromMap({'id': 'at1r2', 'item_id': 'at1', 'rev_no': 2, 'rev_date': _day(12),
    'note': 'نسخة مصححة بعد تعديل جدول الدفعات', 'created_by': 'u-1', 'created_at': _iso(12)}));
  file('at1r2', 'العقد الموقّع - نسخة مصححة.pdf', pdfMime, 2610000);
  file('at2r1', 'ملحق التمديد.pdf', pdfMime, 410000);
  file('at3r1', 'جدول الكميات.xlsx', xlsx, 185000);
  file('at4r1', 'المخطط العام.dwg', 'image/vnd.dwg', 18400000);
  file('at4r1', 'المخطط العام.pdf', pdfMime, 3900000);
  file('at5r1', 'محضر تسليم الموقع.pdf', pdfMime, 1350000);
  file('at6r1', 'قرار التكليف.pdf', pdfMime, 260000);
  file('at7r1', 'المستخلص الثاني.pdf', pdfMime, 980000);
  file('at7r1', 'جدول الحصر.xlsx', xlsx, 96000);
  file('at8r1', 'موقع المشروع.kmz', 'application/vnd.google-earth.kmz', 42000);
  app.docs = DocIndex(items: items, revisions: revs, files: files, reports: app.docs.reports);
  app.v19Ready = true;
}

void _documents(AppState app) {
  final items = <DocItem>[];
  final revs = <DocRevision>[];
  final files = <DocFile>[];
  var fid = 0;
  void file(String rev, String name, String mime, int size, {String? report}) {
    fid++;
    files.add(DocFile.fromMap({
      'id': 'file$fid', 'revision_id': report == null ? rev : null, 'report_id': report, 'path': '${report == null ? 'doc' : 'report'}/$rev/f$fid',
      'name': name, 'mime': mime, 'size_bytes': size, 'sort': fid, 'created_by': 'u-2', 'created_at': _iso(3),
    }));
  }

  const boqs = [
    ('b1', 'p-001', 'مقايسة تقديرية – ترميم مبنى القنصلية', 'BOQ-011', 'estimate', 'approved', 1380000.0, 2, 40),
    ('b2', 'p-003', 'مقايسة تعاقدية – واجهات شارع عمر المختار', 'BOQ-013', 'contract', 'approved', 2300000.0, 1, 25),
    ('b3', 'p-003', 'مقايسة تعديلية – إضافة أعمال العزل', 'BOQ-013-V1', 'variation', 'review', 185000.0, 3, 6),
  ];
  for (final b in boqs) {
    items.add(DocItem.fromMap({'id': b.$1, 'kind': 'boq', 'project_id': b.$2, 'title': b.$3, 'ref_no': b.$4, 'category': b.$5,
      'status': b.$6, 'amount': b.$7, 'doc_date': _day(b.$9), 'party': 'قسم الشؤون الفنية', 'updated_at': _iso(b.$9)}));
    for (var r = 1; r <= b.$8; r++) {
      revs.add(DocRevision.fromMap({'id': '${b.$1}r$r', 'item_id': b.$1, 'rev_no': r, 'rev_date': _day(b.$9 - r * 3),
        'note': r == 1 ? 'الإصدار الأول' : 'تحديث الكميات بعد الحصر الميداني', 'created_by': 'u-2'}));
      file('${b.$1}r$r', '${b.$4}-R$r.pdf', 'application/pdf', 820000 + r * 50000);
    }
  }
  const letters = [
    ('l1', 'p-003', 'طلب تمديد مدة التنفيذ 30 يوماً', 'وارد 412', 'in', 'contract', 'open', 'أثمار', 6, 2, null),
    ('l2', 'p-003', 'الرد على طلب تمديد المدة', 'صادر 233', 'out', 'contract', 'closed', 'أثمار', 1, null, 'l1'),
    ('l3', 'p-002', 'إشعار بتأخر صرف المستخلص الثالث', 'وارد 418', 'in', 'finance', 'open', 'جودة الإعمار', 4, -5, null),
    ('l4', null, 'تعميم بتوحيد نماذج التقارير اليومية', 'داخلي 19', 'internal', 'admin', 'info', 'مكتب المدير', 9, null, null),
    ('l5', 'p-001', 'طلب اعتماد عينات الحجر الجيري', 'وارد 420', 'in', 'technical', 'open', 'درع ليبيا', 2, -10, null),
  ];
  for (final l in letters) {
    items.add(DocItem.fromMap({'id': l.$1, 'kind': 'letter', 'project_id': l.$2, 'title': l.$3, 'ref_no': l.$4, 'direction': l.$5,
      'category': l.$6, 'status': l.$7, 'party': l.$8, 'doc_date': _day(l.$9), 'due_date': l.$10 == null ? null : _day(l.$10!),
      'reply_to': l.$11, 'updated_at': _iso(l.$9)}));
    revs.add(DocRevision.fromMap({'id': '${l.$1}r1', 'item_id': l.$1, 'rev_no': 1, 'rev_date': _day(l.$9), 'created_by': 'u-2'}));
    file('${l.$1}r1', '${l.$4}.pdf', 'application/pdf', 240000);
  }
  const designs = [
    ('d1', 'p-001', 'واجهة مبنى القنصلية الإيطالية', 'heritage', 'approved', 'الاستشاري المعماري', 3),
    ('d2', 'p-003', 'تطوير واجهات شارع عمر المختار', 'architectural', 'review', 'قسم الشؤون الفنية', 2),
    ('d3', 'p-005', 'مسار خط المياه الرئيسي', 'plumbing', 'draft', 'الشركة العامة للمياه', 1),
  ];
  for (final d in designs) {
    items.add(DocItem.fromMap({'id': d.$1, 'kind': 'design', 'project_id': d.$2, 'title': d.$3, 'category': d.$4, 'status': d.$5,
      'party': d.$6, 'doc_date': _day(30), 'ref_no': 'DWG-${d.$1.toUpperCase()}', 'updated_at': _iso(2)}));
    for (var r = 1; r <= d.$7; r++) {
      revs.add(DocRevision.fromMap({'id': '${d.$1}r$r', 'item_id': d.$1, 'rev_no': r, 'rev_date': _day(30 - r * 7),
        'note': switch (r) { 1 => 'الفكرة الأولية', 2 => 'تعديل النسب بعد ملاحظات اللجنة', _ => 'الاعتماد النهائي مع تفاصيل الحجر' },
        'created_by': 'u-2'}));
      file('${d.$1}r$r', 'منظور ${r}A.jpg', 'image/jpeg', 640000);
      file('${d.$1}r$r', 'مسقط ${r}B.png', 'image/png', 420000);
      if (r == d.$7) file('${d.$1}r$r', 'لوحات الإصدار $r.pdf', 'application/pdf', 3200000);
    }
  }
  // التقارير اليومية لآخر 14 يوماً لثلاثة عقود (بفجوات)
  final reports = <SiteReport>[];
  const works = ['حفر خنادق الصرف وتسوية القاع', 'صب خرسانة النظافة للقواعد', 'تركيب السقالات على الواجهة الشمالية',
    'إزالة الدهانات القديمة بالطرق الآمنة', 'نقل المخلفات إلى المكب المعتمد', 'تمديد مواسير المياه قطر 200 مم'];
  var rid = 0;
  for (final (k, pid) in ['p-001', 'p-003', 'p-005'].indexed) {
    for (var d = 0; d < 14; d++) {
      final day = _d(d);
      if (day.weekday == DateTime.friday) continue;
      if ((d + k * 2) % 5 == 3) continue;
      rid++;
      final id = 'rep$rid';
      reports.add(SiteReport.fromMap({
        'id': id, 'project_id': pid, 'report_date': _day(d), 'weather': ['clear', 'clear', 'dust', 'cloudy', 'hot', 'clear', 'wind'][(d + k) % 7],
        'temp_c': 22 + (d % 6), 'workers': 12 + (d * 3 + k * 5) % 20, 'equipment': 'حفار، قلاب، خلاطة',
        'works_done': works[(d + k) % works.length], 'issues': (d + k) % 4 == 1 ? 'تأخر وصول شاحنة المواسير من المورد' : '',
        'safety': d % 6 == 2 ? 'عامل دون خوذة؛ نُبّه المقاول' : '', 'next_plan': 'استكمال الأعمال في المقطع التالي',
        'progress_pct': 30 + (14 - d) * 2, 'reviewed_at': d > 2 ? _iso(d - 1) : null, 'review_note': d > 2 && d % 3 == 0 ? 'يُتابع التوريد' : '',
        'created_by': 'u-3', 'created_at': _iso(d),
      }));
      if (d < 3) {
        file('x', 'الموقع صباحاً.jpg', 'image/jpeg', 380000, report: id);
        file('x', 'الأعمال المنفذة.jpg', 'image/jpeg', 410000, report: id);
      }
    }
  }
  app.docs = DocIndex(items: items, revisions: revs, files: files, reports: reports);
  app.v8Ready = true;
  // كل ملف صورة يأخذ لوحة تجريبية بلون إصداره
  var n = 0;
  final byPath = <String, MemoryImage>{};
  for (final f in files) {
    if (f.isImage) byPath[f.path] = _demoImage(f.path, n++);
  }
  debugSlideImage = (f) => byPath[f.path] ?? _demoImage('x', 0);
}

/// سجلات أقسام الوحدات (الترحيل 21): مبانٍ تاريخية، وخطط وتدقيقات وتكليفات، وسلامة، واستلام وضبط جودة.
void _units(AppState app) {
  final recs = <UnitRecord>[];
  final files = <DocFile>[...app.docs.files];
  var n = 0;
  void rec(String id, String kind, String title,
      {String? project, String? parent, String ref = '', int ago = 5, int? due, String? status, String level = '', double? progress,
      String owner = '', int? closedAgo, Map<String, dynamic> data = const {}, String notes = ''}) {
    final k = unitKinds[kind]!;
    final st = status ?? k.defaultStatus;
    recs.add(UnitRecord.fromMap({
      'id': id, 'unit': k.unit, 'kind': kind, 'project_id': project, 'parent_id': parent, 'title': title, 'ref_no': ref,
      'rec_date': _day(ago), 'due_date': due == null ? null : _day(-due), 'status': st, 'level': level, 'progress': progress,
      'owner_text': owner, 'closed_at': k.closed.contains(st) ? _day(closedAgo ?? ago) : null, 'data': data, 'notes': notes,
      'created_by': 'u-2', 'created_at': _iso(ago), 'updated_at': _iso((ago - 1).clamp(0, 999)),
    }));
  }

  void photo(String record, String name) {
    n++;
    files.add(DocFile.fromMap({'id': 'uf$n', 'record_id': record, 'path': 'unit/$record/u$n', 'name': name, 'mime': 'image/jpeg',
      'size_bytes': 520000, 'sort': n, 'created_by': 'u-2', 'created_at': _iso(4)}));
  }

  void pdf(String record, String name) {
    n++;
    files.add(DocFile.fromMap({'id': 'uf$n', 'record_id': record, 'path': 'unit/$record/u$n', 'name': name, 'mime': 'application/pdf',
      'size_bytes': 1400000, 'sort': n, 'created_by': 'u-2', 'created_at': _iso(4)}));
  }

  // الترميم والمباني التاريخية
  rec('hb1', 'heritage_building', 'مبنى القنصلية الإيطالية', project: 'p-001', ref: 'HB-007', ago: 120, status: 'under_restoration', level: 'poor',
      owner: 'أملاك الدولة', data: {'area': 'وسط البلاد', 'era': 'العهد الإيطالي', 'grade': 'مسجّل وطنياً', 'style': 'نيوكلاسيكي',
        'floors': 2, 'area_m2': 1450, 'current_use': 'مغلق للترميم', 'build_year': '1928',
        'description': 'مبنى من طابقين بواجهة حجرية وأعمدة مزدوجة عند المدخل، وسقف خشبي متضرر في الجناح الشمالي.'});
  rec('hb2', 'heritage_building', 'سوق الجريد القديم', ref: 'HB-012', ago: 90, status: 'under_study', level: 'critical', owner: 'بلدية بنغازي',
      data: {'area': 'سوق الظلام', 'era': 'العهد العثماني', 'grade': 'مسجّل وطنياً', 'floors': 1});
  rec('hb3', 'heritage_building', 'مدرسة الأمير', ref: 'HB-015', ago: 60, level: 'fair', owner: 'وزارة التعليم',
      data: {'area': 'الصابري', 'era': 'العهد الإيطالي', 'grade': 'مقترح للتسجيل', 'floors': 2});
  rec('hb4', 'heritage_building', 'منارة بنغازي القديمة', ref: 'HB-003', ago: 200, status: 'restored', level: 'good', closedAgo: 30,
      data: {'area': 'الميناء', 'era': 'العهد العثماني', 'grade': 'مسجّل وطنياً'});
  rec('hb5', 'heritage_building', 'بيت آل الكيخيا', ref: 'HB-021', ago: 40, level: 'poor', owner: 'ملكية خاصة',
      data: {'area': 'وسط البلاد', 'era': 'العهد العثماني', 'grade': 'مسجّل محلياً', 'floors': 2});
  rec('ha1', 'heritage_assessment', 'تقييم الحالة قبل بدء الترميم', parent: 'hb1', project: 'p-001', ago: 100, status: 'final', level: 'poor',
      owner: 'م. ليلى الزوي', data: {'urgency': 'عاجلة', 'cost_estimate': 1380000, 'damages': 'تآكل حديد التسليح في البلكونات، وتسرب مياه السقف.',
        'recommendations': 'تدعيم البلكونات مؤقتاً، واستبدال الأخشاب المتضررة بأنواع مطابقة.'});
  rec('ha2', 'heritage_assessment', 'تقييم بعد إزالة الطبقات الحديثة', parent: 'hb1', project: 'p-001', ago: 3, status: 'draft', level: 'poor',
      owner: 'م. ليلى الزوي');
  rec('ha3', 'heritage_assessment', 'تقييم عاجل بعد موسم الأمطار', parent: 'hb2', ago: 40, status: 'final', level: 'critical',
      owner: 'م. عمر بوشناف', data: {'urgency': 'عاجلة', 'cost_estimate': 850000});
  photo('hb1', 'الواجهة قبل الترميم.jpg');
  photo('hb1', 'المدخل الرئيسي.jpg');
  photo('hb1', 'السقف الخشبي.jpg');
  photo('hb2', 'الممر الرئيسي للسوق.jpg');
  pdf('ha1', 'تقرير التقييم الإنشائي.pdf');

  // مكتب التخطيط وضمان الجودة
  rec('pl1', 'plan', 'خطة الربع الرابع 2026', ago: 45, due: 47, status: 'active', level: 'quarterly', progress: 62, owner: 'قسم التخطيط',
      data: {'kpi': 'نسبة العقود المنجزة في موعدها', 'target': '80%', 'actual': '64%'});
  rec('pl2', 'plan', 'الخطة السنوية للمكتب 2026', ago: 318, due: 47, status: 'active', level: 'annual', progress: 81, owner: 'مدير المكتب');
  rec('pl3', 'plan', 'خطة تسليم عقود الصابري', project: 'p-003', ago: 70, due: -5, status: 'active', level: 'project', progress: 35,
      owner: 'قسم الإشراف والتنسيق');
  rec('pl4', 'plan', 'خطة الربع الثالث 2026', ago: 136, due: -45, status: 'done', level: 'quarterly', progress: 100, closedAgo: 44);
  rec('qa1', 'qa_audit', 'تدقيق ملف الجودة – واجهات شارع عمر المختار', project: 'p-003', ago: 12, status: 'done', level: 'needs_improvement',
      owner: 'م. سارة المغربي', closedAgo: 10, data: {'auditee': 'قسم الإشراف والتنسيق', 'findings': 'غياب سجلات المعايرة، ونقص توثيق استلام المواد.'});
  rec('qa2', 'qa_audit', 'تدقيق إجراءات المستخلصات', ago: 2, status: 'in_progress', owner: 'م. سارة المغربي', data: {'auditee': 'مكتب العقود'});
  rec('nc1', 'ncr', 'شد حديد التسليح أقل من المطلوب – الدفعة 3', parent: 'qc3', project: 'p-003', ago: 5, due: -1, level: 'major', owner: 'المقاول',
      data: {'requirement': 'المواصفة BS 4449 – إجهاد الخضوع 420 MPa', 'corrective_action': 'رفض الدفعة وإعادة الاختبار على عينات جديدة.'});
  rec('nc2', 'ncr', 'عدم توثيق استلام المواد في الموقع', project: 'p-003', ago: 12, due: 7, status: 'in_progress', level: 'minor',
      owner: 'مهندس الموقع');
  rec('nc3', 'ncr', 'تجاوز نسبة الهالك في حديد التسليح', project: 'p-001', ago: 40, due: -20, status: 'closed', level: 'critical', closedAgo: 25);
  rec('ft1', 'followup_task', 'تسليم تقرير الإنجاز الشهري لشهر أكتوبر', ago: 14, due: -4, level: 'high', owner: 'قسم الإشراف والتنسيق',
      data: {'source': 'اجتماع المكتب الأسبوعي'});
  rec('ft2', 'followup_task', 'تحديث البرنامج الزمني لعقد خط المياه', project: 'p-005', ago: 6, due: 4, owner: 'مكتب العقود');
  rec('ft3', 'followup_task', 'الرد على ملاحظات اللجنة الفنية على التصاميم', ago: 3, due: 2, level: 'urgent', owner: 'قسم الشؤون الفنية');
  rec('ft4', 'followup_task', 'حصر الأعمال الإضافية في عقد القنصلية', project: 'p-001', ago: 30, due: -20, status: 'done', closedAgo: 22);
  rec('ft5', 'followup_task', 'تجهيز ملف الاستلام الابتدائي', project: 'p-003', ago: 25, due: -10, status: 'done', closedAgo: 8);
  rec('ft6', 'followup_task', 'إعداد قائمة المقاولين المؤهلين', ago: 40, due: -15, status: 'done', closedAgo: 16);

  // مكتب السلامة المهنية
  rec('si1', 'safety_inspection', 'جولة تفتيش أسبوعية', project: 'p-003', ago: 2, level: 'acceptable', owner: 'م. خالد العريبي',
      data: {'score': 72, 'workers': 34, 'ppe': 'نقص في الخوذ وأحزمة الأمان', 'actions': 'توفير أحزمة الأمان قبل استئناف العمل على الواجهة.'});
  rec('si2', 'safety_inspection', 'جولة تفتيش على أعمال الحفر', project: 'p-005', ago: 6, status: 'closed', level: 'good', owner: 'م. خالد العريبي',
      data: {'score': 85, 'workers': 18});
  rec('si3', 'safety_inspection', 'جولة تفتيش مفاجئة', project: 'p-001', ago: 9, status: 'closed', level: 'excellent', owner: 'م. خالد العريبي',
      data: {'score': 90, 'workers': 22});
  rec('sn1', 'safety_incident', 'انزلاق عامل من سقالة منخفضة', project: 'p-003', ago: 25, status: 'closed', level: 'minor', owner: 'مهندس الموقع',
      data: {'incident_type': 'سقوط من ارتفاع', 'injured': 1, 'lost_days': 3, 'immediate_action': 'إسعاف أولي ونقل العامل للمستشفى.'});
  rec('sn2', 'safety_incident', 'سقوط أداة من الطابق الثاني دون إصابات', project: 'p-001', ago: 9, level: 'near_miss', owner: 'م. خالد العريبي',
      data: {'incident_type': 'سقوط أجسام'});
  rec('sv1', 'safety_violation', 'العمل على ارتفاع دون حزام أمان', parent: 'si1', project: 'p-003', ago: 2, due: -1, level: 'high',
      owner: 'المقاول', data: {'category': 'العمل على ارتفاع'});
  rec('sv2', 'safety_violation', 'ترك حفرية دون حواجز', project: 'p-005', ago: 1, due: 3, level: 'high', owner: 'المقاول',
      data: {'category': 'الحفريات'});
  rec('sv3', 'safety_violation', 'عدم توفر طفايات حريق في المخزن', project: 'p-001', ago: 9, due: -5, status: 'closed', level: 'medium',
      closedAgo: 6, data: {'category': 'مكافحة الحريق'});
  photo('si1', 'الواجهة الشمالية.jpg');
  photo('sv1', 'المخالفة.jpg');

  // المطابقة والاستلام
  rec('ho1', 'handover', 'الاستلام الابتدائي – منارة بنغازي', project: 'p-001', ref: 'م.س-14', ago: 30, status: 'accepted_notes', level: 'initial',
      owner: 'م. فيصل الشبلي', data: {'committee': 'م. أحمد الفيتوري، م. هدى العبيدي، م. سالم المبروك', 'contractor_rep': 'م. نوري الشريف'});
  rec('ho2', 'handover', 'الاستلام الابتدائي – واجهات شارع عمر المختار (المرحلة 1)', project: 'p-003', ref: 'م.س-17', ago: -6, level: 'initial',
      owner: 'م. فيصل الشبلي');
  rec('ho3', 'handover', 'الاستلام النهائي – خط المياه الرئيسي', project: 'p-005', ref: 'م.س-11', ago: 50, status: 'accepted', level: 'final');
  rec('pi1', 'punch_item', 'تشققات شعرية في لياسة الدرج', parent: 'ho1', project: 'p-001', ago: 30, due: -2, owner: 'المقاول',
      data: {'location': 'الدرج الداخلي'});
  rec('pi2', 'punch_item', 'استكمال دهان الدرابزين الحديدي', parent: 'ho1', project: 'p-001', ago: 30, due: 10, owner: 'المقاول');
  rec('pi3', 'punch_item', 'تنظيف الواجهة من بقايا المونة', parent: 'ho1', project: 'p-001', ago: 30, due: -10, status: 'closed', closedAgo: 12);
  rec('qc1', 'qc_test', 'مقاومة مكعبات الخرسانة 28 يوماً – القواعد', project: 'p-003', ref: 'LAB-221', ago: 3, status: 'passed', level: 'concrete',
      owner: 'مختبر بنغازي المركزي', data: {'required': '25', 'result': '31.5', 'unit': 'MPa'});
  rec('qc2', 'qc_test', 'دمك طبقة الأساس', project: 'p-005', ref: 'LAB-224', ago: 4, status: 'passed', level: 'soil', data: {'required': '95%', 'result': '97%'});
  rec('qc3', 'qc_test', 'شد حديد التسليح قطر 16 مم', project: 'p-003', ref: 'LAB-226', ago: 5, status: 'failed', level: 'steel',
      data: {'required': '420', 'result': '395', 'unit': 'MPa'});
  rec('qc4', 'qc_test', 'مقاومة مكعبات الخرسانة 7 أيام – السقف', project: 'p-001', ago: 1, level: 'concrete');
  rec('ma1', 'material_approval', 'حجر جيري للواجهات', project: 'p-001', ago: 8, due: -1, owner: 'محاجر الجبل الأخضر',
      data: {'spec_ref': 'البند 4.3'});
  rec('ma2', 'material_approval', 'دهانات سيليكات معدنية', project: 'p-001', ago: 20, due: -10, status: 'approved_notes', closedAgo: 12);
  rec('ma3', 'material_approval', 'مواسير HDPE قطر 200 مم', project: 'p-005', ago: 40, due: -30, status: 'approved', closedAgo: 33);
  pdf('ho1', 'محضر الاستلام الموقّع.pdf');
  photo('ho1', 'المنارة بعد الترميم.jpg');
  // فيديو في سجل عدم المطابقة (الترحيل 22)
  n++;
  files.add(DocFile.fromMap({'id': 'uf$n', 'record_id': 'nc1', 'path': 'unit/nc1/v$n', 'name': 'اختبار الشد في الموقع.mp4', 'mime': 'video/mp4',
    'size_bytes': 18400000, 'sort': n, 'created_by': 'u-4', 'created_at': _iso(4)}));

  app.units = UnitIndex(recs);
  app.docs = DocIndex(items: app.docs.items, revisions: app.docs.revisions, files: files, reports: app.docs.reports);
  app.v9Ready = true;
  // مستخدمو الوحدات
  app.people['u-4'] = Profile.fromMap({'id': 'u-4', 'full_name': 'م. خالد العريبي', 'email': 'khaled@office.ly', 'role': 'contracts',
    'active': true, 'unit': 'safety', 'unit_head': true});
  app.people['u-5'] = Profile.fromMap({'id': 'u-5', 'full_name': 'م. سارة المغربي', 'email': 'sara@office.ly', 'role': 'planning_qa',
    'active': true, 'unit': 'quality_assurance', 'unit_head': true});
  app.people['u-6'] = Profile.fromMap({'id': 'u-6', 'full_name': 'م. ليلى الزوي', 'email': 'laila@office.ly', 'role': 'office_staff',
    'active': true, 'unit': 'heritage'});
  final prev = debugSlideImage;
  var k = 100;
  final extra = <String, MemoryImage>{for (final f in files) if (f.recordId != null && f.isImage) f.path: _demoImage(f.path, k++)};
  debugSlideImage = (f) => extra[f.path] ?? (prev == null ? _demoImage('x', 0) : prev(f));
}

/// تحميل الصور التجريبية ونصوص الدليل خارج الوقت الوهمي للاختبار.
Future<void> _preload(WidgetTester tester) async {
  await tester.runAsync(() async {
    await loadManualTexts();
    for (final im in _demoImages.values) {
      final c = Completer<void>();
      final stream = im.resolve(ImageConfiguration.empty);
      late final ImageStreamListener l;
      l = ImageStreamListener((_, __) {
        if (!c.isCompleted) c.complete();
        stream.removeListener(l);
      }, onError: (_, __) {
        if (!c.isCompleted) c.complete();
      });
      stream.addListener(l);
      await c.future;
    }
  });
}

Future<void> _shot(WidgetTester tester, String name, AppState app, Widget page,
    {Size size = _desktop, bool dark = false, String appearanceKey = ''}) async {
  await tester.binding.setSurfaceSize(size);
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  final key = GlobalKey();
  await tester.pumpWidget(
    RepaintBoundary(
      key: key,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        locale: const Locale('ar'),
        supportedLocales: const [Locale('ar')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        theme: buildTheme(Brightness.light),
        darkTheme: buildTheme(Brightness.dark),
        themeMode: dark ? ThemeMode.dark : ThemeMode.light,
        builder: (context, child) => AppScope(state: app, child: child!),
        home: page,
      ),
    ),
  );
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 400));
  }
  await expectLater(find.byKey(key), matchesGoldenFile('goldens/$name.png'));
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 2));
}

Widget _scaffold(Widget body) => Scaffold(body: body);

void main() {
  setUpAll(() async {
    themeUseGoogleFonts = false;
    motionSetting = 'off';
    await _loadFonts();
  });

  testWidgets('home', (tester) async {
    final app = _sampleState();
    await _shot(tester, '01_home_light_desktop', app, const HomeShell());
    await _shot(tester, '02_home_dark_desktop', app, const HomeShell(), dark: true);
    await _shot(tester, '03_home_light_mobile', app, const HomeShell(), size: _mobile);
  });

  testWidgets('finance', (tester) async {
    final app = _sampleState();
    app.tab = 7;
    await _shot(tester, '10_finance_summary_light', app, const HomeShell());
    await _shot(tester, '11_finance_summary_dark', app, const HomeShell(), dark: true);
    await _shot(tester, '12_finance_summary_mobile', app, _scaffold(const FinancePage()), size: _mobile);
  });

  testWidgets('finance views', (tester) async {
    final app = _sampleState();
    app.openFinance(view: 'extracts');
    await _shot(tester, '13_finance_extracts_light', app, _scaffold(const FinancePage()), size: const Size(1200, 3000));
    app.openFinance(view: 'cash');
    await _shot(tester, '14_finance_cash_light', app, _scaffold(const FinancePage()), size: const Size(1200, 3400));
    app.openFinance(view: 'guarantees');
    await _shot(tester, '15_finance_guarantees_dark', app, _scaffold(const FinancePage()), size: const Size(1200, 2200), dark: true);
  });

  testWidgets('dialogs and settings', (tester) async {
    final app = _sampleState();
    final p = app.project('p-003')!;
    final x = app.extractsOf('p-003').last;
    await _shot(tester, '32_extract_dialog_light', app,
        _scaffold(Center(child: ExtractDialog(app: app, project: p, extract: x))), size: const Size(1200, 1800));
    await _shot(tester, '33_extract_new_mobile', app,
        _scaffold(Center(child: ExtractDialog(app: app, project: p))), size: const Size(400, 1800));
    final ref = app.extracts.firstWhere((e) => e.isReferred);
    await _shot(tester, '34_payment_dialog_dark', app,
        _scaffold(Center(child: PaymentDialog(app: app, extract: ref))), size: const Size(900, 1100), dark: true);
    await _shot(tester, '35_settings_light', app, _scaffold(const SettingsSection()), size: const Size(1200, 3200));
  });

  testWidgets('dashboard views', (tester) async {
    final app = _sampleState();
    await _shot(tester, '20_dashboard_page_light', app, _scaffold(const DashboardPage()), size: const Size(1200, 2600));
  });

  testWidgets('contract', (tester) async {
    final app = _sampleState();
    await _shot(tester, '30_contract_light', app, const ProjectDetailPage(projectId: 'p-003'), size: const Size(1200, 5200));
    await _shot(tester, '31_contract_dark_mobile', app, const ProjectDetailPage(projectId: 'p-003'), size: const Size(400, 7000), dark: true);
  });

  testWidgets('login and appearance', (tester) async {
    final app = _sampleState();
    await _shot(tester, '40_login_light', app, const LoginScreen(), size: const Size(1440, 900));
    await _shot(tester, '41_login_dark_mobile', app, const LoginScreen(), size: const Size(400, 860), dark: true);
    await _shot(tester, '42_appearance_light', app, _scaffold(ListView(padding: const EdgeInsets.all(20), children: const [AppearanceEditor()])),
        size: const Size(1200, 2400));
  });

  testWidgets('assistant', (tester) async {
    final app = _sampleState();
    app.assistantMessages.addAll([
      AssistantMessage(role: 'user', text: 'ما المستخلصات المحالة للصرف ولم تُدفع؟'),
      AssistantMessage(
        role: 'assistant',
        text: 'هناك مستخلصان محالان للصرف:\n• عقد ع-2026/13 — المستخلص رقم 3، صافيه 512,400 د.ل.\n• عقد ع-2026/11 — المستخلص رقم 1، صافيه 210,000 د.ل.',
        model: 'claude-sonnet-5-5',
        inputTokens: 5200,
        outputTokens: 320,
        actions: [
          AssistantAction(id: 't1', name: 'propose_extract_status', input: {
            'extract_id': 'x-p-003-4',
            'status': 'paid',
            'paid_amount': 512400,
            'paid_on': _day(0),
            'summary': 'تسجيل صرف المستخلص رقم 4 لعقد ع-2026/13 كاملاً بتاريخ اليوم',
          }),
        ],
      ),
    ]);
    await _shot(tester, '50_assistant_light', app, _scaffold(const AssistantPage()), size: const Size(1200, 1100));
  });

  testWidgets('sections', (tester) async {
    final app = _sampleState();
    app.showHub = true;
    await _shot(tester, '60_hub_light_desktop', app, const HomeShell(), size: const Size(1440, 1000));
    await _shot(tester, '61_hub_dark_mobile', app, const HomeShell(), size: const Size(400, 1400), dark: true);
    app.showHub = false;
    app.tab = 8;
    await _shot(tester, '62_guide_light_desktop', app, const HomeShell(), size: const Size(1440, 1700));
    await _shot(tester, '63_guide_mobile', app, _scaffold(const CycleGuidePage()), size: const Size(400, 1800));
    app.tab = 20;
    await _shot(tester, '64_risk_dashboard_light', app, const HomeShell(), size: const Size(1440, 2600));
    await _shot(tester, '65_risk_dashboard_dark_mobile', app, _scaffold(const RiskDashboardPage()), size: const Size(400, 4200), dark: true);
    await _shot(tester, '66_risk_register_light', app, _scaffold(const RiskRegisterPage()), size: const Size(1200, 1800));
    await _shot(tester, '67_risk_matrix_light', app, _scaffold(const RiskMatrixPage()), size: const Size(1200, 1900));
    app.tab = 40;
    await _shot(tester, '80_pm_dashboard_light', app, const HomeShell(), size: const Size(1440, 3200));
    await _shot(tester, '81_pm_dashboard_dark_mobile', app, _scaffold(const PmDashboardPage()), size: const Size(400, 6000), dark: true);
    await _shot(tester, '82_pm_projects_light', app, _scaffold(const PmProjectsPage()), size: const Size(1200, 1800));
    await _shot(tester, '83_pm_progress_light', app, _scaffold(const PmProgressPage()), size: const Size(1200, 1800));
    await _shot(tester, '84_pm_issues_light', app, _scaffold(const PmIssuesPage()), size: const Size(1200, 1200));
    await _shot(tester, '85_pm_delays_light', app, _scaffold(const PmDelaysPage()), size: const Size(1200, 1200));
    await _shot(tester, '86_pm_changes_light', app, _scaffold(const PmChangesPage()), size: const Size(1200, 1300));
    await _shot(tester, '87_pm_lessons_mobile', app, _scaffold(const PmLessonsPage()), size: const Size(400, 1600));
    await _shot(tester, '88_pm_contractors_light', app, _scaffold(const PmContractorsPage()), size: const Size(1300, 2000));
    await _shot(tester, '89_pm_report_light', app, _scaffold(const PmReportPage()), size: const Size(1200, 2600));
    await _shot(tester, '90_pm_settings_light', app, _scaffold(const PmSettingsPage()), size: const Size(1200, 2200));
    await _shot(tester, '91_pm_guide_mobile', app, _scaffold(const PmGuidePage()), size: const Size(400, 5200));
    await _shot(tester, '92_pm_presentation_light', app, _scaffold(const PmPresentationPage()), size: const Size(1600, 1500));
    await _shot(tester, '93_pm_presentation_dark_mobile', app, _scaffold(const PmPresentationPage()), size: const Size(400, 4200), dark: true);
    app.tab = 30;
    await _shot(tester, '70_swot_dashboard_light', app, const HomeShell(), size: const Size(1440, 2400));
    await _shot(tester, '71_swot_matrix_dark', app, _scaffold(const SwotMatrixPage()), size: const Size(1200, 1500), dark: true);
    await _shot(tester, '72_swot_factors_light', app, _scaffold(const SwotFactorsPage()), size: const Size(1200, 2200));
    await _shot(tester, '73_swot_weighted_light', app, _scaffold(const SwotWeightedPage()), size: const Size(1200, 2000));
    await _shot(tester, '74_swot_tows_mobile', app, _scaffold(const SwotTowsPage()), size: const Size(400, 2600));
    await _shot(tester, '75_swot_plan_light', app, _scaffold(const SwotPlanPage()), size: const Size(1200, 1900));
    await _shot(tester, '76_swot_method_light', app, _scaffold(const SwotMethodPage()), size: const Size(1200, 2800));
    await _shot(tester, '77_swot_presentation_light', app, _scaffold(const SwotPresentationPage()), size: const Size(1600, 1900));
    await _shot(tester, '78_swot_presentation_mobile', app, _scaffold(const SwotPresentationPage()), size: const Size(400, 5200));
  });

  testWidgets('documents and supervision', (tester) async {
    final app = _sampleState();
    await _preload(tester);
    app.showHub = true;
    await _shot(tester, '94_hub_six_sections_light', app, const HomeShell(), size: const Size(1440, 1300));
    app.showHub = false;
    app.tab = 62;
    await _shot(tester, '95_docs_designs_light', app, const HomeShell(), size: const Size(1440, 1500));
    await _shot(tester, '96_docs_designs_dark_mobile', app, _scaffold(const DocsPage(kind: 'design')), size: const Size(400, 2200), dark: true);
    await _shot(tester, '97_doc_design_detail_light', app, const DocDetailPage(itemId: 'd1'), size: const Size(1200, 2600));
    app.tab = 61;
    await _shot(tester, '98_docs_letters_light', app, const HomeShell(), size: const Size(1440, 1300));
    await _shot(tester, '99_doc_boq_detail_mobile', app, const DocDetailPage(itemId: 'b3'), size: const Size(400, 1900));
    app.tab = 60;
    await _shot(tester, 'a0_docs_boq_light', app, const HomeShell(), size: const Size(1440, 1000));
    await _shot(tester, 'a1_storage_light', app, _scaffold(const StoragePage()), size: const Size(1200, 1100));
    app.tab = 70;
    await _shot(tester, 'a2_reports_light', app, const HomeShell(), size: const Size(1440, 2600));
    await _shot(tester, 'a3_reports_dark_mobile', app, _scaffold(const SiteReportsPage()), size: const Size(400, 3000), dark: true);
    await _shot(tester, 'a4_report_detail_light', app, SiteReportDetailPage(reportId: app.docs.reports.first.id), size: const Size(1200, 2600));
    app.tab = 71;
    await _shot(tester, 'a5_coverage_light', app, const HomeShell(), size: const Size(1440, 1100));
    app.tab = 80;
    await _shot(tester, 'a6_manual_light_desktop', app, const HomeShell(), size: const Size(1440, 2400));
    app.manualAnchor = '09_risk_register';
    await _shot(tester, 'a7_manual_risk_light', app, _scaffold(const ManualPage()), size: const Size(1440, 4200));
    app.manualAnchor = '17_docs';
    await _shot(tester, 'a8_manual_docs_dark_mobile', app, _scaffold(const ManualPage()), size: const Size(400, 7000), dark: true);
    await _shot(tester, 'a9_whats_new_light', app, _scaffold(const WhatsNewPage()), size: const Size(1200, 2000));
    await _shot(tester, 'b0_contract_docs_light', app, const ProjectDetailPage(projectId: 'p-003'), size: const Size(1200, 6200));
  });

  testWidgets('unit sections', (tester) async {
    final app = _sampleState();
    await _preload(tester);
    app.showHub = true;
    await _shot(tester, 'c0_hub_ten_sections_light', app, const HomeShell(), size: const Size(1440, 1900));
    await _shot(tester, 'c1_hub_ten_sections_dark_mobile', app, const HomeShell(), size: const Size(400, 4200), dark: true);
    app.showHub = false;
    app.tab = 90;
    await _shot(tester, 'c2_heritage_overview_light', app, const HomeShell(), size: const Size(1440, 1900));
    app.tab = 91;
    await _shot(tester, 'c3_heritage_buildings_light', app, const HomeShell(), size: const Size(1440, 1500));
    await _shot(tester, 'c4_heritage_building_detail_light', app, const UnitRecordDetailPage(recordId: 'hb1'), size: const Size(1200, 2600));
    app.tab = 100;
    await _shot(tester, 'c5_planning_qa_overview_light', app, const HomeShell(), size: const Size(1440, 2600));
    app.tab = 102;
    await _shot(tester, 'c6_quality_assurance_light', app, const HomeShell(), size: const Size(1440, 1400));
    await _shot(tester, 'c7_audit_detail_dark_mobile', app, const UnitRecordDetailPage(recordId: 'qa1'), size: const Size(400, 2600), dark: true);
    app.tab = 103;
    await _shot(tester, 'c8_follow_up_mobile', app, _scaffold(const UnitRecordsPage(unit: 'follow_up', kinds: ['followup_task'])),
        size: const Size(400, 2200));
    app.tab = 110;
    await _shot(tester, 'c9_safety_overview_light', app, const HomeShell(), size: const Size(1440, 1800));
    app.tab = 113;
    await _shot(tester, 'd0_safety_violations_light', app, const HomeShell(), size: const Size(1440, 1200));
    await _shot(tester, 'd1_inspection_detail_light', app, const UnitRecordDetailPage(recordId: 'si1'), size: const Size(1200, 2400));
    app.tab = 120;
    await _shot(tester, 'd2_acceptance_overview_light', app, const HomeShell(), size: const Size(1440, 2000));
    app.tab = 121;
    await _shot(tester, 'd3_receiving_light', app, const HomeShell(), size: const Size(1440, 1300));
    await _shot(tester, 'd4_handover_detail_light', app, const UnitRecordDetailPage(recordId: 'ho1'), size: const Size(1200, 2600));
    app.tab = 122;
    await _shot(tester, 'd5_quality_control_dark', app, const HomeShell(), size: const Size(1440, 1400), dark: true);
    app.manualAnchor = '21_safety';
    await _shot(tester, 'd6_manual_safety_light', app, _scaffold(const ManualPage()), size: const Size(1440, 4400));
  });

  testWidgets('rasd', (tester) async {
    final app = _sampleState();
    await _preload(tester);
    _rasd(app);
    app.showHub = true;
    await _shot(tester, 'g0_hub_thirteen_light', app, const HomeShell(), size: const Size(1440, 2300));
    await _shot(tester, 'g1_hub_thirteen_dark_mobile', app, const HomeShell(), size: const Size(400, 5000), dark: true);
    app.showHub = false;
    app.tab = 140;
    await _shot(tester, 'g2_chat_list_light', app, const HomeShell(), size: const Size(1440, 1000));
    await _shot(tester, 'g3_chat_group_light', app, _scaffold(const ChatPage(initialRoom: 'r-grp')), size: const Size(1440, 1000));
    await _shot(tester, 'g4_chat_dm_dark_mobile', app, const ConversationScreen(roomId: 'r-dm1'), size: const Size(400, 900), dark: true);
    await _shot(tester, 'g5_chat_list_mobile', app, _scaffold(const ChatPage()), size: const Size(400, 900));
    await _shot(tester, 'g6_chat_channels_light', app, _scaffold(const ChatPage(channels: true, initialRoom: 'r-ch2')), size: const Size(1440, 900));
    await _shot(tester, 'g7_chat_locked_light', app, _scaffold(const ConversationView(roomId: 'r-locked', embedded: true)), size: const Size(900, 700));
    await _shot(tester, 'g8_chat_settings_light', app, _scaffold(const ChatSettingsPage()), size: const Size(1200, 1000));
    await _shot(tester, 'g9_new_channel_light', app, _OpenDialog(builder: (_) => const ChannelDialog()), size: const Size(1200, 1100));
    app.tab = 150;
    await _shot(tester, 'h0_security_dashboard_light', app, const HomeShell(), size: const Size(1440, 3400));
    await _shot(tester, 'h1_security_dashboard_dark_mobile', app, _scaffold(const SecDashboardPage()), size: const Size(400, 6400), dark: true);
    await _shot(tester, 'h2_security_posture_light', app, _scaffold(const SecPosturePage()), size: const Size(1200, 2600));
    await _shot(tester, 'h3_security_alerts_light', app, _scaffold(const SecAlertsPage()), size: const Size(1200, 1300));
    await _shot(tester, 'h4_security_identity_light', app, _scaffold(const SecIdentityPage()), size: const Size(1440, 1500));
    await _shot(tester, 'h5_security_data_light', app, _scaffold(const SecDataPage()), size: const Size(1200, 1500));
    await _shot(tester, 'h6_security_chat_light', app, _scaffold(const SecChatPage()), size: const Size(1440, 2600));
    await _shot(tester, 'h7_security_incidents_mobile', app, _scaffold(const SecIncidentsPage()), size: const Size(400, 1800));
    app.tab = 133;
    await _shot(tester, 'i0_ref_numbers_light', app, const HomeShell(), size: const Size(1440, 1300));
    await _shot(tester, 'i1_ref_scheme_dialog_light', app, _OpenDialog(builder: (_) => RefSchemeDialog(scheme: app.refScheme('print'))), size: const Size(1200, 1300));
    await _shot(tester, 'i2_grants_dialog_light', app, _OpenDialog(builder: (_) => const GrantsDialog(userId: 'u-1', name: 'سالم المبروك')),
        size: const Size(1200, 1000));
    await _shot(tester, 'i3_layout_editor_light', app, _scaffold(ListView(padding: const EdgeInsets.all(20), children: const [LayoutEditor()])),
        size: const Size(1300, 1900));
    final risks = exportSource(app, 'risks:register')!;
    final rt = risks.build(app, const ExportQuery()).select([for (final c in risks.columns) if (c.on) c.key]);
    await _shot(tester, 'i4_table_editor_light', app, _OpenEditor(table: rt), size: const Size(1440, 1000));
    app.tab = 1;
    await _shot(tester, 'i5_export_dialog_columns_light', app, const _OpenExport(sourceId: 'risks:register'), size: const Size(1440, 1500));
    // Excel حي وPDF برقم إشاري صادر
    await tester.runAsync(() async {
      final dir = Directory('visual_test/goldens/exports')..createSync(recursive: true);
      final issued = PrintContext(printedBy: 'م. فيصل الشبلي', orgName: 'مكتب الشؤون الهندسية', at: DateTime(2026, 11, 21, 10, 5))
          .withRef('م.ش.هـ/م.م/2026/0007');
      File('${dir.path}/risks_live.xlsx').writeAsBytesSync(await renderExport(ExportFormat.xlsx, rt, PrintConfig(), issued));
      File('${dir.path}/risks_issued_ref.pdf').writeAsBytesSync(await renderExport(ExportFormat.pdf, rt, PrintConfig(), issued));
      final fin = exportSource(app, 'cycle:finance')!;
      final ft = fin.build(app, const ExportQuery()).select([for (final c in fin.columns) c.key]);
      File('${dir.path}/finance_live.xlsx').writeAsBytesSync(await renderExport(ExportFormat.xlsx, ft, PrintConfig(), issued));
    });
  });

  testWidgets('schedules and prices', (tester) async {
    final app = _sampleState();
    await _preload(tester);
    _planning(app);
    final ps = app.projects;
    app.tab = 52;
    await _shot(tester, 'j0_schedules_light', app, const HomeShell(), size: const Size(1440, 2400));
    await _shot(tester, 'j1_schedules_dark_mobile', app, _scaffold(const ScheduleDashboardPage()), size: const Size(400, 4000), dark: true);
    await _shot(tester, 'j2_project_schedule_light', app, ProjectSchedulePage(projectId: ps[0].id), size: const Size(1300, 2500));
    await _shot(tester, 'j3_project_schedule_mobile', app, ProjectSchedulePage(projectId: ps[1].id), size: const Size(400, 3000));
    await _shot(tester, 'j4_item_editor_light', app, _OpenAction(run: (ctx) => showPmItemEditor(ctx, ps[0], app.itemsOf(ps[0].id)[2])),
        size: const Size(1200, 1300));
    app.tab = 65;
    await _shot(tester, 'k0_prices_light', app, const HomeShell(), size: const Size(1440, 1000));
    await _shot(tester, 'k1_prices_search_light', app, _scaffold(const PriceListPage(initialQuery: 'رخام')), size: const Size(1200, 2400));
    await _shot(tester, 'k2_prices_code_mobile', app, _scaffold(const PriceListPage(initialQuery: '7.2.2', initialChapter: 'buildings')),
        size: const Size(400, 2600));
    await _shot(tester, 'k3_prices_browse_light', app, _scaffold(const PriceListPage(initialChapter: 'buildings')), size: const Size(1200, 2000));
    app.tab = 66;
    await _shot(tester, 'k4_boq_sheets_light', app, const HomeShell(), size: const Size(1440, 900));
    await _shot(tester, 'k5_boq_editor_light', app, const BoqEditorPage(sheetId: 'bq1'), size: const Size(1300, 2400));
    await _shot(tester, 'k6_boq_editor_dark_mobile', app, const BoqEditorPage(sheetId: 'bq1'), size: const Size(400, 3600), dark: true);
    final bq = app.boqSheet('bq1')!;
    await _shot(tester, 'k7_boq_export_light', app,
        _OpenAction(run: (ctx) => showExportDialog(ctx, sourceId: 'docs:boq_sheet', items: bq.lines, title: bq.title, format: ExportFormat.xlsx)),
        size: const Size(1440, 1500));
    await tester.runAsync(() async {
      final dir = Directory('visual_test/goldens/exports')..createSync(recursive: true);
      final ctx = PrintContext(printedBy: 'م. فيصل الشبلي', orgName: 'مكتب الشؤون الهندسية', at: DateTime(2026, 11, 21, 10, 5));
      final s = exportSource(app, 'docs:boq_sheet')!;
      final t = s.build(app, ExportQuery(items: bq.lines)).copyWith(title: bq.title).select([for (final c in s.columns) if (c.on) c.key]);
      File('${dir.path}/boq_live.xlsx').writeAsBytesSync(await renderExport(ExportFormat.xlsx, t, PrintConfig(), ctx));
      File('${dir.path}/boq.pdf').writeAsBytesSync(await renderExport(ExportFormat.pdf, t, PrintConfig(), ctx));
      final sc = exportSource(app, 'risks:schedule')!;
      final st = sc.build(app, const ExportQuery()).select([for (final c in sc.columns) if (c.on) c.key]);
      File('${dir.path}/schedule_live.xlsx').writeAsBytesSync(await renderExport(ExportFormat.xlsx, st, PrintConfig(), ctx));
    });
  });

  testWidgets('supervision hub and plans', (tester) async {
    final app = _sampleState();
    await _preload(tester);
    _planning(app);
    _supervisionPlans(app);
    final ps = app.projects;
    app.tab = 72;
    await _shot(tester, 'm0_sup_dashboard_light', app, const HomeShell(), size: const Size(1440, 3200));
    await _shot(tester, 'm1_sup_dashboard_dark_mobile', app, _scaffold(const SupervisionDashboardPage()), size: const Size(400, 6200), dark: true);
    app.tab = 73;
    await _shot(tester, 'm2_contract_items_light', app, const HomeShell(), size: const Size(1440, 3000));
    await _shot(tester, 'm3_follow_light', app, ProjectFollowPage(projectId: ps[1].id), size: const Size(1400, 3600));
    await _shot(tester, 'm4_follow_dark_mobile', app, ProjectFollowPage(projectId: ps[1].id), size: const Size(400, 6400), dark: true);
    await _shot(tester, 'm5_life_phase_light', app,
        _OpenAction(run: (ctx) => showLifePhaseSheet(ctx, ps[1], followOf(app, ps[1]), 3)), size: const Size(1200, 1300));
    await _shot(tester, 'm6_track_editor_light', app,
        _OpenAction(run: (ctx) => showTrackItemEditor(ctx, ps[1], app.itemsOf(ps[1].id).firstWhere((i) => i.id == 's3'))), size: const Size(1200, 1100));
    app.tab = 67;
    await _shot(tester, 'm7_plans_light', app, const HomeShell(), size: const Size(1440, 1500));
    await _shot(tester, 'm8_plan_editor_draft_light', app, PlanEditorPage(projectId: ps[4].id), size: const Size(1400, 2600));
    await _shot(tester, 'm9_plan_editor_approved_dark', app, PlanEditorPage(projectId: ps[1].id), size: const Size(1400, 2800), dark: true);
    await _shot(tester, 'n0_plan_generate_light', app, _OpenAction(run: (ctx) => showGenerateDialog(ctx, ps[4], replace: true)),
        size: const Size(1200, 1500));
    await _shot(tester, 'n1_plan_item_editor_light', app,
        _OpenAction(run: (ctx) => showPlanItemEditor(ctx, ps[4], app.itemsOf(ps[4].id).firstWhere((i) => i.id == 'w2'))), size: const Size(1200, 1300));
    await _shot(tester, 'n2_boq_approved_light', app, const BoqEditorPage(sheetId: 'bq1'), size: const Size(1300, 1400));
    await _shot(tester, 'n3_cycle_status_colors_light', app, const ProjectDetailPage(projectId: 'p-003'), size: const Size(1200, 2600));
  });

  testWidgets('layout and ideas', (tester) async {
    final app = _sampleState();
    await _preload(tester);
    _planning(app);
    _supervisionPlans(app);
    _layoutIdeas(app);
    final keys = [for (final s in appSections) s.$1];
    app.showHub = true;
    await _shot(tester, 'o0_hub_groups_icons_light', app, const HomeShell(), size: const Size(1440, 1300));
    app.hubEditRequested = true;
    await _shot(tester, 'o1_hub_edit_icons_light', app, const HomeShell(), size: const Size(1440, 1700));
    await _shot(tester, 'o2_section_editor_light', app, _OpenAction(run: (ctx) {
      final docs = appSections.firstWhere((s) => s.$1 == 'docs');
      showSectionEditor(ctx,
          app: app,
          draft: HubDraft.from(app.layout, keys),
          sectionKey: 'docs',
          defaultName: docs.$2,
          defaultDesc: docs.$3,
          defaultIcon: docs.$4,
          defaultColor: defaultSectionColor(ctx, 'docs'),
          pagesOf: layoutPagesFor,
          onChanged: () {});
    }), size: const Size(1200, 1900));
    await _shot(tester, 'o3_pages_editor_light', app, _OpenAction(run: (ctx) {
      showPagesEditor(ctx,
          app: app, draft: HubDraft.from(app.layout, keys), sectionKey: 'supervision', sectionName: 'الإشراف', pagesOf: layoutPagesFor, onChanged: () {});
    }), size: const Size(1200, 1200));
    _layoutIdeas(app, style: 'compact');
    await _shot(tester, 'o4_hub_compact_dark_mobile', app, const HomeShell(), size: const Size(400, 1900), dark: true);
    _layoutIdeas(app, style: 'cards');
    await _shot(tester, 'o5_hub_cards_groups_light', app, const HomeShell(), size: const Size(1440, 2300));
    app.showHub = false;
    app.tab = 72;
    await _shot(tester, 'o6_supervision_menu_moved_light', app, const HomeShell(), size: const Size(1440, 1200));
    app.tab = Tabs.ideas;
    await _shot(tester, 'o7_ideas_map_light', app, const HomeShell(), size: const Size(1440, 2400));
    app.tab = Tabs.ideasSupervision;
    await _shot(tester, 'o8_ideas_supervision_light', app, const HomeShell(), size: const Size(1440, 2200));
    await _shot(tester, 'o9_ideas_supervision_dark_mobile', app, _scaffold(const IdeasPage(section: 'supervision')), size: const Size(400, 3000), dark: true);
    await _shot(tester, 'p0_idea_composer_light', app,
        _OpenAction(run: (ctx) => showIdeaComposer(ctx, section: 'supervision', pageId: 72, pageLabel: 'لوحة الإشراف')), size: const Size(1200, 1300));
    await _shot(tester, 'p1_boq_delete_confirm_light', app, _OpenAction(run: (ctx) {
      final p = boqDeletePrompt(app, 'bq3');
      confirmDialog(ctx, title: p.title, message: p.message, confirmLabel: 'حذف', danger: true);
    }), size: const Size(1200, 900));
    await _shot(tester, 'p2_customize_launcher_light', app,
        _scaffold(ListView(padding: const EdgeInsets.all(20), children: const [LayoutEditor()])), size: const Size(1200, 900));
  });

  testWidgets('section isolation', (tester) async {
    final app = _sampleState();
    await _preload(tester);
    _planning(app);
    _supervisionPlans(app);
    _documents(app);
    _contractFiles(app);
    _units(app);
    // جهات النماذج كما في قاعدة البيانات (الترحيل 19)
    const heads = {
      'f20': 'head:technical', 'f19': 'head:technical', //
      'f04': 'head:supervising', 'f07': 'head:supervising', 'f08': 'head:supervising', 'f09': 'head:supervising', //
      'f05': 'head:acceptance', 'f10': 'head:acceptance', 'f11': 'head:acceptance', 'f22': 'head:acceptance', 'f12': 'head:acceptance',
      'f13': 'head:acceptance', 'f16': 'head:acceptance', 'f17': 'head:acceptance', 'f06': 'planning_qa',
    };
    app.allFormDefs = [
      for (final d in app.allFormDefs)
        FormDef.fromMap({
          'key': d.key, 'name': d.name, 'stage': d.stage, 'sort': d.sort, 'sensitive': d.sensitive, 'engineer_field': d.engineerField,
          'responsible': ['office_staff', heads[d.key] ?? 'contracts'],
        }),
    ];
    app.formDefs = app.allFormDefs;
    final allProjects = [...app.projects];
    final allStatuses = {for (final e in app.statuses.entries) e.key: {...e.value}};
    // رئيس الشؤون الفنية: قسمه وحده، وأساسيات العقود، ونماذجه المسندة، وإجراءات SWOT لقسمه
    _isolateAs(
        app,
        Profile.fromMap({'id': 'u-tech', 'full_name': 'م. عبد السلام الورفلي', 'email': 'tech@office.ly', 'role': 'dept_head', 'department': 'technical', 'active': true}),
        const UserScope(sections: {'docs', 'chat', 'manual', 'print'}, units: {'technical'}, forms: {'f20', 'f19'}),
        allProjects,
        allStatuses);
    app.showHub = true;
    await _shot(tester, 'q0_tech_hub_light', app, const HomeShell(), size: const Size(1440, 1000));
    app.showHub = false;
    app.tab = Tabs.assignedDocs;
    await _shot(tester, 'q1_tech_assigned_light', app, const HomeShell(), size: const Size(1440, 1900));
    await _shot(tester, 'q2_tech_assigned_dark_mobile', app, _scaffold(const AssignedWorkPage(section: 'docs')), size: const Size(400, 2600), dark: true);
    await _shot(tester, 'q3_limited_contract_light', app, ProjectDetailPage(projectId: app.projects.first.id), size: const Size(1200, 1500));
    app.tab = Tabs.manual;
    await _shot(tester, 'q4_tech_manual_light', app, const HomeShell(), size: const Size(1440, 1100));
    // رئيس الإشراف: عقود قسمه وحدها بتفاصيلها
    final sup = {for (final p in allProjects) if (p.department == 'supervision') p.id};
    _isolateAs(app, app.people['u-3']!, UserScope(sections: const {'supervision', 'chat', 'manual', 'print'}, supervised: sup), allProjects, allStatuses);
    app.tab = Tabs.supDashboard;
    await _shot(tester, 'q5_sup_dashboard_light', app, const HomeShell(), size: const Size(1440, 1700));
    // مسؤول الأمن السيبراني: قسمه والأدوات المشتركة
    _isolateAs(
        app,
        Profile.fromMap({'id': 'u-ciso', 'full_name': 'م. خالد الأمن', 'email': 'ciso@office.ly', 'role': 'security_auditor', 'active': true}),
        const UserScope(sections: {'security', 'chat', 'manual', 'print'}),
        allProjects,
        allStatuses);
    app.showHub = true;
    await _shot(tester, 'q6_ciso_hub_dark_mobile', app, const HomeShell(), size: const Size(400, 1300), dark: true);
  });

  testWidgets('schedule from boq', (tester) async {
    final app = _sampleState();
    await _preload(tester);
    _planning(app);
    _supervisionPlans(app);
    final ps = app.projects;
    // علاقات البرنامج المسودة، وتواريخه محسوبة بها (PlanLayout)
    const links = [
      PmLink(id: 'lk1', predId: 'w1', succId: 'w2', kind: 'SS', lagDays: 10),
      PmLink(id: 'lk2', predId: 'w2', succId: 'w5', kind: 'FS', lagDays: 2),
      PmLink(id: 'lk3', predId: 'w3', succId: 'w4', kind: 'FF', lagDays: 0),
    ];
    final p4 = ps[4].id;
    final st = app.planOf(p4)!.startDate;
    final its = app.itemsOf(p4);
    final lay = PlanLayout(st, app.phasesOf(p4), its, links: links);
    app.pmItems = [
      for (final i in app.pmItems)
        if (i.projectId != p4)
          i
        else
          PmItem.fromMap({
            'id': i.id, 'project_id': i.projectId, 'sort': i.sort, 'code': i.code, 'title': i.title, 'source': i.source, 'phase_id': i.phaseId,
            'duration_days': i.durationDays, 'unit': i.unit, 'qty': i.qty, 'weight': i.weight,
            'planned_start': dbDate(lay.dates[i.id]!.$1), 'planned_end': dbDate(lay.dates[i.id]!.$2),
          }),
    ];
    app.pmLinks = links;
    app.pmRates = [
      PmRate.fromMap({'id': 'rt1', 'unit': 'م3', 'keyword': '', 'rate': 8, 'label': 'خرسانة عامة', 'valid_from': _day(400), 'created_by': 'u-dir'}),
      PmRate.fromMap({'id': 'rt2', 'unit': 'م3', 'keyword': 'أعمدة', 'rate': 1.25, 'label': 'صب أعمدة بفريق واحد', 'valid_from': _day(200), 'created_by': 'u-dir'}),
      PmRate.fromMap({'id': 'rt3', 'unit': 'م3', 'keyword': 'أعمدة', 'rate': 1.0, 'label': 'صب أعمدة بفريق واحد', 'valid_from': _day(400),
        'note': 'قبل توريد القوالب المعدنية', 'created_by': 'u-dir'}),
      PmRate.fromMap({'id': 'rt4', 'unit': 'م2', 'keyword': 'رخام', 'rate': 9, 'label': 'تركيب رخام', 'valid_from': _day(300), 'created_by': 'u-dir'}),
      PmRate.fromMap({'id': 'rt5', 'unit': 'م.ط', 'keyword': '', 'rate': 25, 'valid_from': _day(-20), 'label': 'معدل جديد يسري لاحقاً', 'created_by': 'u-dir'}),
    ];
    // إصداران للبرنامج المعتمد: الأول (الأساس) بتواريخ أبكر، والثاني الحالي
    final p1 = ps[1].id;
    Map<String, dynamic> vItem(PmItem i, int shift) => {
          'id': i.id, 'code': i.code, 'title': i.title, 'start': dbDate(addDays(i.plannedStart, -shift)), 'end': dbDate(addDays(i.plannedEnd, -shift)),
          'duration': i.durationDays,
        };
    final cur = app.itemsOf(p1);
    final end1 = cur.map((i) => i.plannedEnd).reduce((a, b) => a.isAfter(b) ? a : b);
    app.pmVersions = [
      PmPlanVersion.fromMap({'id': 'ver2', 'project_id': p1, 'version': 2, 'source': 'approval', 'start_date': dbDate(app.planOf(p1)!.startDate),
        'end_date': dbDate(end1), 'items': [for (final i in cur) vItem(i, 0)], 'approved_at': _iso(100), 'approved_by': 'u-dir'}),
      PmPlanVersion.fromMap({'id': 'ver1', 'project_id': p1, 'version': 1, 'source': 'backfill', 'start_date': dbDate(app.planOf(p1)!.startDate),
        'end_date': dbDate(addDays(end1, -18)),
        'items': [for (final i in cur) if (i.id != 's7') vItem(i, i.id == 's2' || i.id == 's3' ? 14 : (i.id == 's4' || i.id == 's6' ? 18 : 0))],
        'approved_at': _iso(140), 'approved_by': 'u-dir'}),
    ];
    app.v20Ready = true;
    await _shot(tester, 'p0_plan_critical_links_light', app, PlanEditorPage(projectId: p4), size: const Size(1400, 2700));
    await _shot(tester, 'p1_link_editor_light', app,
        _OpenAction(run: (ctx) => showLinkEditor(ctx, ps[4], app.itemsOf(p4).firstWhere((i) => i.id == 'w5'))), size: const Size(1200, 900));
    await _shot(tester, 'p2_item_editor_rate_light', app,
        _OpenAction(run: (ctx) => showPlanItemEditor(ctx, ps[4], app.itemsOf(p4).firstWhere((i) => i.id == 'w1'))), size: const Size(1200, 1400));
    await _shot(tester, 'p3_version_compare_light', app, PlanVersionPage(projectId: p1, versionId: 'ver1'), size: const Size(1300, 2200));
    await _shot(tester, 'p4_versions_card_dark', app, PlanEditorPage(projectId: p1), size: const Size(1400, 3300), dark: true);
    await _shot(tester, 'p5_rates_light', app, const RatesPage(), size: const Size(1200, 1100));
    const rows = [
      ['مقايسة أعمال صيانة مدرسة الفجر', '', '', '', '', ''],
      ['ر.ت', 'البيان', 'الوحدة', 'الكمية', 'سعر الوحدة', 'الإجمالي'],
      ['أولاً: الأعمال التمهيدية', '', '', '', '', ''],
      ['1.1', 'حفر خنادق للأساسات بعمق لا يقل عن 1.5 متر', 'م3', '٢٤٠', '35', '8,400'],
      ['', 'مع نقل المخلفات إلى المكب المعتمد', '', '', '', ''],
      ['1.2', 'ردم بالتربة المختارة على طبقات', 'م3', '180', '22.5', '4,050'],
      ['', 'مجموع الأعمال التمهيدية', '', '', '', '12,450'],
      ['ثانياً: الأعمال الخرسانية', '', '', '', '', ''],
      ['2.1', 'خرسانة مسلحة للقواعد', 'م3', '60', '950', '57,000'],
      ['2.2', 'خرسانة عادية للنظافة', 'م3', '20', '480', '9,000'],
      ['2.3', 'حديد تسليح إضافي', 'طن', '', '3,200', ''],
      ['', 'الإجمالي العام', '', '', '', '78,450'],
    ];
    await _shot(tester, 'p6_boq_import_review_light', app,
        BoqImportPage(source: BoqSource('مقايسة مدرسة الفجر.xlsx', 'xlsx', Uint8List(0)), sheets: [BoqSheetRows('المقايسة', rows)]),
        size: const Size(1200, 2600));
    await _shot(tester, 'p7_boq_import_pdf_dark_mobile', app,
        BoqImportPage(source: BoqSource('مقايسة مدرسة الفجر.pdf', 'pdf', Uint8List(0)), sheets: [BoqSheetRows('PDF', rows)]),
        size: const Size(400, 3600), dark: true);
  });

  testWidgets('contracts v3', (tester) async {
    final app = _sampleState();
    await _preload(tester);
    app.v21Ready = true;
    final p = app.project('p-003')!;
    // أمر معتمد ببنود، وأمر في مسودة بزيادة ونقص، وأمر مرفوض
    app.variations = [
      ...app.variations,
      ContractVariation.fromMap({'id': 'vo-1', 'project_id': p.id, 'ref_no': 'أ.ت-7', 'title': 'زيادة كميات الحفر وإلغاء جزء من الخرسانة',
        'kind': 'deduct', 'amount': 550, 'added_value': 4200, 'deducted_value': 4750, 'status': 'draft', 'created_at': _iso(3)}),
      ContractVariation.fromMap({'id': 'vo-2', 'project_id': p.id, 'ref_no': 'أ.ت-5', 'title': 'عزل مائي لسطح المبنى الإداري',
        'kind': 'add', 'amount': 38000, 'added_value': 38000, 'deducted_value': 0, 'status': 'approved', 'approved_on': _day(40),
        'decided_by': 'u-2', 'created_at': _iso(60)}),
      ContractVariation.fromMap({'id': 'vo-3', 'project_id': p.id, 'ref_no': 'أ.ت-6', 'title': 'أعمال إضافية للسياج', 'kind': 'add',
        'amount': 20000, 'status': 'rejected', 'decision_note': 'لا يوجد تكليف بها', 'created_at': _iso(20)}),
    ];
    app.variationItemsBy = {
      'vo-1': [
        VariationItem.fromMap({'id': 'i1', 'variation_id': 'vo-1', 'sort': 1, 'direction': 'add', 'boq_sheet_id': 'bq-x', 'boq_line': 0,
          'code': '1.1', 'description': 'حفر خنادق للأساسات', 'unit': 'م3', 'qty': 120, 'unit_price': 35, 'amount': 4200}),
        VariationItem.fromMap({'id': 'i2', 'variation_id': 'vo-1', 'sort': 2, 'direction': 'deduct', 'boq_sheet_id': 'bq-x', 'boq_line': 2,
          'code': '2.1', 'description': 'خرسانة مسلحة للقواعد', 'unit': 'م3', 'qty': 5, 'unit_price': 950, 'amount': 4750}),
      ],
      'vo-2': [
        VariationItem.fromMap({'id': 'i3', 'variation_id': 'vo-2', 'sort': 1, 'direction': 'add', 'description': 'عزل مائي بالأغشية البيتومينية',
          'unit': 'م2', 'qty': 950, 'unit_price': 40, 'amount': 38000}),
      ],
    };
    app.variationEventsBy = {
      'vo-1': [
        VariationEvent.fromMap({'id': 'e1', 'variation_id': 'vo-1', 'action': 'create', 'actor_name': 'سالم المبروك', 'at': _iso(3),
          'snapshot': {'added': 3500, 'deducted': 4750, 'items': [{}, {}]}}),
        VariationEvent.fromMap({'id': 'e2', 'variation_id': 'vo-1', 'action': 'update', 'actor_name': 'سالم المبروك', 'at': _iso(1),
          'snapshot': {'added': 4200, 'deducted': 4750, 'items': [{}, {}]}}),
      ],
      'vo-2': [
        VariationEvent.fromMap({'id': 'e3', 'variation_id': 'vo-2', 'action': 'create', 'actor_name': 'سالم المبروك', 'at': _iso(60),
          'snapshot': {'added': 38000, 'deducted': 0, 'items': [{}]}}),
        VariationEvent.fromMap({'id': 'e4', 'variation_id': 'vo-2', 'action': 'approve', 'actor_name': 'هدى العبيدي', 'at': _iso(40),
          'note': 'وفق محضر الإشراف', 'snapshot': {'added': 38000, 'deducted': 0, 'items': [{}]}}),
      ],
    };
    // القيمة المعدلة بعد الأمر المعتمد
    app.projects = [
      for (final x in app.projects)
        if (x.id != p.id)
          x
        else
          Project.fromMap({
            'id': x.id, 'assign_no': x.assignNo, 'contract_no': x.contractNo, 'name': x.name, 'company': x.company, 'owner': x.owner,
            'department': x.department, 'contract_value': x.contractValue, 'executed_value': x.executedValue,
            'guarantee_initial': x.guaranteeInitial, 'guarantee_final': x.guaranteeFinal, 'guarantee_initial_rate': 0.02, 'guarantee_final_rate': 0.05,
            'retention_deduct': true, 'retention_rate': 0.1, 'value_source': x.valueSource, 'executed_source': x.executedSource,
            'variations_net': 38000, 'variations_add': 38000, 'variations_deduct': 0, 'extracts_count': x.extractsCount,
            'extracts_gross': x.extractsGross, 'extracts_net': x.extractsNet, 'extracts_paid': x.extractsPaid,
            'extracts_submitted': x.extractsSubmitted + 95000, 'retention_held': x.retentionHeld, 'advance_amount': x.advanceAmount,
            'advance_paid_on': x.advancePaidOn == null ? null : dbDate(x.advancePaidOn!), 'advance_recovered': x.advanceRecovered,
          }),
    ];
    app.committees = [
      ContractCommittee.fromMap({'id': 'cm1', 'project_id': p.id, 'kind': 'initial', 'decision_no': 'ق-77/2026', 'decision_date': _day(10)})
          .withMembers(const [
        CommitteeMember(role: 'chair', name: 'م. سالم الفرجاني', title: 'رئيس قسم المطابقة والاستلام'),
        CommitteeMember(name: 'م. علي المسماري', title: 'مهندس مدني'),
        CommitteeMember(name: 'م. هدى العبيدي', title: 'ممثل الإشراف', profileId: 'u-2'),
      ]),
    ];
    app.indexData();
    await _shot(tester, 's0_contract_dashboard_light', app, const ProjectDetailPage(projectId: 'p-003'), size: const Size(1200, 2300));
    await _shot(tester, 's1_contract_dashboard_dark_mobile', app,
        _scaffold(ListView(padding: const EdgeInsets.all(12), children: [ContractDashboardCard(project: app.project('p-003')!)])),
        size: const Size(400, 2000), dark: true);
    await _shot(tester, 's2_variation_page_light', app, const VariationPage(variationId: 'vo-1'), size: const Size(1200, 1900));
    await _shot(tester, 's3_variation_editor_light', app, const VariationEditorPage(projectId: 'p-003', variationId: 'vo-1'),
        size: const Size(1200, 1800));
    await _shot(tester, 's4_guarantees_dialog_light', app,
        _OpenAction(run: (ctx) => showGuaranteesDialog(ctx, app.project('p-003')!)), size: const Size(1200, 1000));
    await _shot(tester, 's5_variations_committees_light', app,
        _scaffold(ListView(padding: const EdgeInsets.all(20), children: [
          VariationsCard(app: app, project: app.project('p-003')!),
          const SizedBox(height: 16),
          CommitteesCard(project: app.project('p-003')!),
        ])),
        size: const Size(1200, 1300));
    await _shot(tester, 's6_committee_editor_dark_mobile', app,
        _OpenAction(run: (ctx) => showCommitteeEditor(ctx, app.project('p-003')!, 'initial', app.committeeOf('p-003', 'initial'))),
        size: const Size(400, 1300), dark: true);
    app.manualAnchor = '07_finance';
    await _shot(tester, 's7_manual_finance_light', app, _scaffold(const ManualPage()), size: const Size(1440, 5200));
  });

  testWidgets('stores', (tester) async {
    final app = _sampleState();
    await _preload(tester);
    app.v22Ready = true;
    final now = DateTime.now();
    DateTime day(int offset) => DateTime(now.year, now.month, now.day).add(Duration(days: offset));
    StDoc doc(String id, String no, String kind, String status, int ago,
            {String? to, String? emp, String? dep, String party = '', String ref = '', String note = '', String decision = '', bool confirmed = false}) =>
        StDoc(
          id: id,
          docNo: no,
          kind: kind,
          status: status,
          warehouseId: 'wm',
          toWarehouseId: to,
          employeeId: emp,
          departmentId: dep,
          docDate: day(-ago),
          party: party,
          refNo: ref,
          note: note,
          decisionNote: decision,
          createdAt: day(-ago),
          createdBy: 'u-1',
          submittedAt: status == 'draft' ? null : day(-ago),
          submittedBy: status == 'draft' ? null : 'u-1',
          approvedAt: status == 'approved' || status == 'posted' ? day(-ago) : null,
          approvedBy: status == 'approved' || status == 'posted' ? 'u-dir' : null,
          postedAt: status == 'posted' ? day(-ago) : null,
          postedBy: status == 'posted' ? 'u-1' : null,
          decidedAt: status == 'rejected' ? day(-ago) : null,
          decidedBy: status == 'rejected' ? 'u-dir' : null,
          confirmedAt: confirmed ? day(-ago + 1) : null,
          confirmedBy: confirmed ? 'u-dir' : null,
        );
    StDocLine line(String doc, int n, String item, String unit, double qty, {double factor = 1, DateTime? exp, String batch = ''}) =>
        StDocLine(id: '$doc-$n', docId: doc, lineNo: n, itemId: item, unitId: unit, qty: qty, factor: factor, expiryDate: exp, batchNo: batch);
    app.stores = StoresData(
      settings: const StSettings(separation: true, expiryDays: 60),
      departments: const [
        StDepartment(id: 'dg', code: 'GEN', name: 'الإدارة العامة'),
        StDepartment(id: 'dit', parentId: 'dg', name: 'قسم تقنية المعلومات'),
        StDepartment(id: 'dad', parentId: 'dg', name: 'قسم الشؤون الإدارية'),
        StDepartment(id: 'dsv', name: 'إدارة الخدمات العامة'),
      ],
      employees: [
        const StEmployee(id: 'e1', empNo: 'E-100', fullName: 'سالم علي المبروك', departmentId: 'dit', jobTitle: 'مبرمج'),
        StEmployee(id: 'e2', empNo: 'E-101', fullName: 'فاطمة محمد سالم', departmentId: 'dad', jobTitle: 'محاسبة', profileId: app.me!.id),
        const StEmployee(id: 'e3', empNo: 'E-200', fullName: 'عمر الهادي', departmentId: 'dsv', jobTitle: 'فني صيانة'),
        const StEmployee(id: 'e4', empNo: 'E-201', fullName: 'نوري خليفة', departmentId: 'dg', jobTitle: 'سائق', active: false),
      ],
      locations: const [
        StLocation(id: 'b1', kind: 'building', code: 'B1', name: 'المبنى الرئيسي'),
        StLocation(id: 'f0', parentId: 'b1', kind: 'floor', name: 'الطابق الأرضي'),
        StLocation(id: 'r4', parentId: 'f0', kind: 'room', code: '004', name: 'غرفة 004'),
        StLocation(id: 'f1', parentId: 'b1', kind: 'floor', name: 'الطابق الأول'),
        StLocation(id: 'b2', kind: 'building', name: 'مبنى الخدمات'),
      ],
      warehouses: const [
        StWarehouse(id: 'wm', code: 'MAIN', name: 'المخزن الرئيسي', kind: 'main', locationId: 'r4'),
        StWarehouse(id: 'ws', code: 'SUB1', name: 'مخزن الطابق الأول', kind: 'sub', parentId: 'wm', locationId: 'f1'),
      ],
      categories: const [
        StCategory(id: 'csta', code: 'STA', name: 'القرطاسية', sort: 1),
        StCategory(id: 'cpap', code: 'PAP', name: 'الورق ومستلزمات الطباعة', sort: 2),
        StCategory(id: 'cofe', code: 'OFE', name: 'الأجهزة المكتبية', kind: 'asset', sort: 3),
        StCategory(id: 'cfur', code: 'FUR', name: 'الأثاث', kind: 'asset', sort: 4),
        StCategory(id: 'ccln', code: 'CLN', name: 'النظافة والخدمات', sort: 5),
        StCategory(id: 'chos', code: 'HOS', name: 'الضيافة والاستهلاك اليومي', sort: 6),
        StCategory(id: 'cmnt', code: 'MNT', name: 'الصيانة والتشغيل', sort: 7),
        StCategory(id: 'csaf', code: 'SAF', name: 'السلامة والطوارئ', sort: 8),
      ],
      units: const [
        StUnit(id: 'piece', name: 'قطعة', sort: 1),
        StUnit(id: 'box', name: 'علبة', sort: 2),
        StUnit(id: 'ream', name: 'رزمة', sort: 3),
        StUnit(id: 'carton', name: 'كرتونة', sort: 4),
        StUnit(id: 'pack', name: 'عبوة', sort: 5),
        StUnit(id: 'roll', name: 'لفة', sort: 8),
      ],
      items: const [
        StItem(id: 'a4', code: 'PAP-0001', name: 'ورق A4 80 غم', categoryId: 'cpap', baseUnitId: 'ream', minQty: 10, maxQty: 200, reorderQty: 20, criticalQty: 5),
        StItem(id: 'pen', code: 'STA-0001', name: 'قلم حبر أزرق جاف', categoryId: 'csta', baseUnitId: 'piece', minQty: 24, reorderQty: 48, barcode: '6281000000017'),
        StItem(id: 'dis', code: 'CLN-0001', name: 'مطهر أسطح', categoryId: 'ccln', baseUnitId: 'pack', minQty: 10, reorderQty: 15, tracksExpiry: true),
        StItem(id: 'toner', code: 'PAP-0002', name: 'حبر طابعة ليزر أسود', categoryId: 'cpap', baseUnitId: 'piece', minQty: 4, reorderQty: 6, criticalQty: 2),
        StItem(id: 'bag', code: 'CLN-0002', name: 'أكياس نفايات كبيرة', categoryId: 'ccln', baseUnitId: 'roll', minQty: 20, reorderQty: 30),
        StItem(id: 'stp', code: 'STA-9001', name: 'دباسة مكتبية كبيرة', categoryId: 'csta', baseUnitId: 'piece', minQty: 3),
      ],
      itemUnits: const [StItemUnit(itemId: 'a4', unitId: 'carton', factor: 5), StItemUnit(itemId: 'pen', unitId: 'box', factor: 12)],
      docs: [
        doc('ad', 'AD-2026-0001', 'adjust', 'draft', 0, note: 'جرد مبدئي للقرطاسية'),
        doc('is4', 'IS-2026-0004', 'issue', 'draft', 0, emp: 'e3', dep: 'dsv'),
        doc('is2', 'IS-2026-0002', 'issue', 'submitted', 1, emp: 'e1', dep: 'dit', note: 'طلب عاجل لامتحانات نهاية العام'),
        doc('tr', 'TR-2026-0001', 'transfer', 'approved', 2, to: 'ws'),
        doc('is3', 'IS-2026-0003', 'issue', 'rejected', 3, dep: 'dg', decision: 'الكمية تتجاوز الاستهلاك الاسترشادي'),
        doc('is1', 'IS-2026-0001', 'issue', 'posted', 5, emp: 'e2', dep: 'dad'),
        doc('rc', 'RC-2026-0001', 'receipt', 'posted', 12, party: 'مورد القرطاسية', ref: 'INV-77'),
        doc('ob', 'OB-2026-0001', 'opening', 'posted', 30, note: 'أرصدة بدء العمل بالمنظومة'),
      ],
      lines: [
        line('ob', 1, 'a4', 'carton', 10, factor: 5),
        line('ob', 2, 'pen', 'piece', 100),
        line('ob', 3, 'dis', 'pack', 20, exp: day(66), batch: 'L2'),
        line('ob', 4, 'dis', 'pack', 10, exp: day(35), batch: 'L1'),
        line('ob', 5, 'toner', 'piece', 3),
        line('rc', 1, 'pen', 'box', 2, factor: 12),
        line('is1', 1, 'a4', 'carton', 2, factor: 5),
        line('is1', 2, 'pen', 'box', 1, factor: 12),
        line('is2', 1, 'a4', 'ream', 38),
        line('is2', 2, 'pen', 'piece', 10),
        line('is3', 1, 'toner', 'piece', 3),
        line('tr', 1, 'dis', 'pack', 10),
        line('is4', 1, 'a4', 'carton', 1, factor: 5),
        line('is4', 2, 'bag', 'roll', 5),
        line('ad', 1, 'pen', 'piece', -2),
      ],
      stock: const [
        StStock(warehouseId: 'wm', itemId: 'a4', onHand: 40),
        StStock(warehouseId: 'wm', itemId: 'pen', onHand: 112),
        StStock(warehouseId: 'wm', itemId: 'dis', onHand: 30, reserved: 10),
        StStock(warehouseId: 'wm', itemId: 'toner', onHand: 3),
        StStock(warehouseId: 'ws', itemId: 'stp', onHand: 7),
      ],
      batches: [
        StBatch(id: 'bt1', warehouseId: 'wm', itemId: 'dis', expiryDate: day(35), batchNo: 'L1', qty: 10),
        StBatch(id: 'bt2', warehouseId: 'wm', itemId: 'dis', expiryDate: day(66), batchNo: 'L2', qty: 20),
      ],
    );
    final moves = [
      StMove(id: 1, docId: 'ob', warehouseId: 'wm', itemId: 'a4', qty: 50, balanceAfter: 50, at: day(-30)),
      StMove(id: 7, docId: 'is1', warehouseId: 'wm', itemId: 'a4', qty: -10, balanceAfter: 40, at: day(-5)),
    ];
    app.showHub = true;
    await _shot(tester, 't0_hub_with_stores_light', app, const HomeShell(), size: const Size(1440, 2300));
    app.openSection('stores');
    await _shot(tester, 't1_stores_dashboard_light', app, const HomeShell(), size: const Size(1440, 2200));
    await _shot(tester, 't2_stores_dashboard_dark_mobile', app, _scaffold(const StoresDashboardPage()), size: const Size(400, 2600), dark: true);
    await _shot(tester, 't3_stores_items_light', app, _scaffold(const StoresItemsPage()), size: const Size(1440, 1300));
    await _shot(tester, 't4_item_page_light', app, StoreItemPage(itemId: 'a4', initialMoves: moves), size: const Size(1200, 1900));
    await _shot(tester, 't5_item_expiry_dark_mobile', app, const StoreItemPage(itemId: 'dis', initialMoves: []), size: const Size(400, 2300), dark: true);
    await _shot(tester, 't6_item_editor_light', app,
        _OpenAction(run: (ctx) => showStoreItemEditor(ctx, item: app.stores.item('a4'))), size: const Size(1200, 1300));
    await _shot(tester, 't7_docs_list_light', app, _scaffold(const StoresDocsPage()), size: const Size(1440, 1400));
    await _shot(tester, 't8_doc_submitted_light', app, const StoreDocPage(docId: 'is2'), size: const Size(1200, 1600));
    await _shot(tester, 't9_doc_rejected_mobile', app, const StoreDocPage(docId: 'is3'), size: const Size(400, 1600));
    await _shot(tester, 'u0_doc_editor_light', app, const StoreDocEditorPage(kind: 'issue', docId: 'is4'), size: const Size(1200, 1600));
    await _shot(tester, 'u1_doc_editor_dark_mobile', app, const StoreDocEditorPage(kind: 'opening'), size: const Size(400, 1800), dark: true);
    await _shot(tester, 'u2_balances_light', app, _scaffold(const StoresBalancesPage()), size: const Size(1440, 1200));
    await _shot(tester, 'u3_setup_light', app, _scaffold(const StoresSetupPage()), size: const Size(1440, 2600));
    await _shot(tester, 'u4_people_light', app, _scaffold(const StoresPeoplePage()), size: const Size(1440, 1900));
    await _shot(tester, 'u5_people_mobile', app, _scaffold(const StoresPeoplePage()), size: const Size(400, 3000));
    await _shot(tester, 'u6_mine_mobile', app, _scaffold(const StoresMinePage()), size: const Size(400, 1600));
    // الأصول والعهد والإهلاك (الترحيل 39)
    app.v23Ready = true;
    app.storeAssets = AssetsData(
      policies: const [StAssetPolicy(categoryId: 'cofe', lifeMonths: 60), StAssetPolicy(categoryId: 'cfur', lifeMonths: 120, salvagePct: 10)],
      assets: [
        StAsset(
            id: 'as1', tag: 'OFE-A-0001', name: 'حاسوب محمول', categoryId: 'cofe', manufacturer: 'Dell', model: 'Latitude 5440',
            serialNo: 'SN-LAP-001', purchaseDate: day(-320), inServiceDate: day(-315), cost: 3600, lifeMonths: 36, supplier: 'مورد الحواسيب',
            invoiceNo: 'INV-2026-114', warrantyUntil: day(400), status: 'custody', condition: 'good', locationId: 'r4', departmentId: 'dit',
            employeeId: 'e1'),
        StAsset(
            id: 'as2', tag: 'OFE-A-0002', name: 'شاشة 24 بوصة', categoryId: 'cofe', manufacturer: 'Dell', model: 'P2423',
            purchaseDate: day(-290), cost: 520, lifeMonths: 60, salvage: 52, status: 'custody', employeeId: 'e2', departmentId: 'dad', locationId: 'f1'),
        StAsset(
            id: 'as3', tag: 'OFE-A-0003', name: 'طابعة ليزر ملونة', categoryId: 'cofe', manufacturer: 'HP', model: 'M479', serialNo: 'PR-77',
            purchaseDate: day(-700), cost: 1500, lifeMonths: 60, status: 'maintenance', condition: 'fair', locationId: 'r4', departmentId: 'dg'),
        StAsset(
            id: 'as4', tag: 'FUR-OLD-17', name: 'مكتب خشبي مع أدراج', categoryId: 'cfur', purchaseDate: DateTime(2024, 3, 1), cost: 1200,
            salvage: 120, lifeMonths: 120, status: 'in_use', locationId: 'r4', departmentId: 'dg'),
        StAsset(
            id: 'as5', tag: 'FUR-A-0001', name: 'كرسي دوار', categoryId: 'cfur', purchaseDate: day(-40), cost: 300, lifeMonths: 120, salvage: 30,
            condition: 'new', warehouseId: 'wm', locationId: 'r4'),
        StAsset(
            id: 'as6', tag: 'FUR-A-0002', name: 'خزانة ملفات معدنية', categoryId: 'cfur', purchaseDate: DateTime(2019, 5, 1), cost: 800,
            lifeMonths: 120, salvage: 80, status: 'disposal', condition: 'poor', locationId: 'f0', departmentId: 'dsv', disposalKind: 'scrap',
            disposalReason: 'صدأ وتلف الأقفال', disposalRequestedAt: day(-1), disposalRequestedBy: 'u-1'),
        StAsset(
            id: 'as7', tag: 'OFE-A-0004', name: 'جهاز عرض قديم', categoryId: 'cofe', purchaseDate: DateTime(2018, 1, 1), cost: 2000, lifeMonths: 60,
            status: 'disposed', condition: 'damaged', disposalKind: 'scrap', disposalReason: 'تلف اللوحة الأم', disposalDate: day(-60),
            disposedAt: day(-60)),
      ],
      custody: [
        StCustody(
            id: 'cu1', custodyNo: 'CU-2026-0001', assetId: 'as1', employeeId: 'e1', departmentId: 'dit', locationId: 'r4', handedOn: day(-300),
            conditionOut: 'new', accessoriesOut: 'شاحن وحقيبة', confirmedAt: day(-299)),
        StCustody(
            id: 'cu2', custodyNo: 'CU-2026-0002', assetId: 'as2', employeeId: 'e2', departmentId: 'dad', handedOn: day(-20), accessoriesOut: 'كابل HDMI'),
        StCustody(
            id: 'cu0', custodyNo: 'CU-2025-0007', assetId: 'as3', employeeId: 'e3', departmentId: 'dsv', handedOn: DateTime(2025, 1, 10),
            returnedOn: day(-30), conditionIn: 'fair', confirmedAt: DateTime(2025, 1, 11), returnConfirmedAt: day(-29)),
      ],
    );
    app.myCustody = [
      MyCustody(
          id: 'cu2', custodyNo: 'CU-2026-0002', tag: 'OFE-A-0002', name: 'شاشة 24 بوصة', category: 'الأجهزة المكتبية', manufacturer: 'Dell',
          model: 'P2423', handedOn: day(-20), accessoriesOut: 'كابل HDMI'),
    ];
    final events = [
      StAssetEvent(id: 1, assetId: 'as1', kind: 'create', at: day(-320), byUser: 'u-1', data: const {'cost': 3600}),
      StAssetEvent(id: 2, assetId: 'as1', kind: 'custody_out', at: day(-300), byUser: 'u-1', data: const {'employee': 'سالم علي المبروك', 'custody_no': 'CU-2026-0001'}),
      StAssetEvent(id: 3, assetId: 'as1', kind: 'transfer', at: day(-100), byUser: 'u-1', data: const {'to': {'location_id': 'r4', 'department_id': 'dit'}},
          note: 'انتقل مكتب الموظف'),
    ];
    await _shot(tester, 'v0_assets_light', app, _scaffold(const StoresAssetsPage()), size: const Size(1440, 1500));
    await _shot(tester, 'v1_assets_dark_mobile', app, _scaffold(const StoresAssetsPage()), size: const Size(400, 2800), dark: true);
    await _shot(tester, 'v2_asset_page_light', app, StoreAssetPage(assetId: 'as1', initialEvents: events), size: const Size(1200, 2300));
    await _shot(tester, 'v3_asset_disposal_mobile', app, const StoreAssetPage(assetId: 'as6', initialEvents: []), size: const Size(400, 2300));
    await _shot(tester, 'v4_asset_editor_light', app, _OpenAction(run: (ctx) => showAssetEditor(ctx)), size: const Size(1200, 1600));
    await _shot(tester, 'v5_custody_light', app, _scaffold(const StoresCustodyPage()), size: const Size(1440, 1200));
    await _shot(tester, 'v6_mine_custody_mobile', app, _scaffold(const StoresMinePage()), size: const Size(400, 2000));
    await _shot(tester, 'v7_setup_policies_light', app, _scaffold(const StoresSetupPage()), size: const Size(1440, 3000));
    app.openSection('stores');
    await _shot(tester, 'v8_stores_nav_light', app, const HomeShell(), size: const Size(1440, 1300));
    app.manualAnchor = '34_stores';
    await _shot(tester, 'u7_manual_stores_light', app, _scaffold(const ManualPage()), size: const Size(1440, 9000));
  });

  testWidgets('contract files', (tester) async {
    final app = _sampleState();
    await _preload(tester);
    final p = app.project('p-003')!;
    Widget card() => _scaffold(ListView(padding: const EdgeInsets.all(20), children: [ContractFilesCard(project: p)]));
    await _shot(tester, 'r0_contract_files_light', app, card(), size: const Size(1200, 900));
    await _shot(tester, 'r1_contract_files_dark_mobile', app, card(), size: const Size(400, 1500), dark: true);
    await _shot(tester, 'r2_attachment_detail_light', app, const DocDetailPage(itemId: 'at1'), size: const Size(1200, 1500));
    await _shot(tester, 'r3_attachment_cad_mobile', app, const DocDetailPage(itemId: 'at4'), size: const Size(400, 1400));
    await _shot(tester, 'r4_contract_page_light', app, const ProjectDetailPage(projectId: 'p-003'), size: const Size(1200, 6400));
    app.manualAnchor = '33_contract_files';
    await _shot(tester, 'r5_manual_contract_files_light', app, _scaffold(const ManualPage()), size: const Size(1440, 4600));
  });

  testWidgets('print center', (tester) async {
    final app = _sampleState();
    await _preload(tester);
    app.showHub = true;
    await _shot(tester, 'e0_hub_eleven_sections_light', app, const HomeShell(), size: const Size(1440, 2100));
    app.showHub = false;
    app.tab = 130;
    await _shot(tester, 'e1_print_center_light', app, const HomeShell(), size: const Size(1440, 2000));
    app.tab = 131;
    await _shot(tester, 'e2_print_designer_light', app, const HomeShell(), size: const Size(1600, 1500));
    await _shot(tester, 'e3_print_designer_mobile', app, _scaffold(const PrintDesignerPage()), size: const Size(400, 3000));
    app.tab = 132;
    await _shot(tester, 'e4_media_library_light', app, const HomeShell(), size: const Size(1440, 1700));
    app.tab = 64;
    await _shot(tester, 'e5_technical_materials_light', app, const HomeShell(), size: const Size(1440, 1300));
    app.tab = 122;
    await _shot(tester, 'e6_quality_control_ncr_light', app,
        _scaffold(const UnitRecordsPage(unit: 'quality_control', kinds: ['ncr', 'qc_test'])), size: const Size(1440, 1300));
    await _shot(tester, 'e7_ncr_detail_light', app, const UnitRecordDetailPage(recordId: 'nc1'), size: const Size(1200, 2200));
    app.tab = 1;
    await _shot(tester, 'e8_export_dialog_light', app, const _OpenExport(sourceId: 'cycle:contracts'), size: const Size(1440, 1300));
    await _shot(tester, 'e9_export_dialog_mobile', app, const _OpenExport(sourceId: 'unit:ncr'), size: const Size(400, 2000));
    // معاينة صفحة بقالب مخصص (غلاف، علامة مائية، توقيعات، تجميع)
    final ctx = PrintContext(printedBy: 'م. فيصل الشبلي', orgName: 'مكتب الشؤون الهندسية', at: DateTime(2026, 11, 16, 19, 45, 30));
    final fancy = PrintConfig(watermark: 'مسودة', showSignatures: true, groupBy: 'project', accent: 0xFF0B6E99, logoPos: 'center', cover: true);
    final ncr = exportSource(app, 'unit:ncr')!;
    final ncrTable = ncr.build(app, const ExportQuery()).select([for (final c in ncr.columns) if (c.on) c.key]);
    await _shot(tester, 'f0_page_preview_fancy', app,
        _scaffold(Center(child: SizedBox(width: 900, child: PagePreview(config: fancy, table: ncrTable, context0: ctx)))),
        size: const Size(1000, 1300));
    await _shot(tester, 'f1_page_preview_cover', app,
        _scaffold(Center(child: SizedBox(width: 700, child: PagePreview(config: fancy, table: ncrTable, context0: ctx, cover: true)))),
        size: const Size(800, 1100));

    // ملفات تجريبية بكل الصيغ للتدقيق (تُنشر مع اللقطات في visual-shots/exports)
    await tester.runAsync(() async {
      final dir = Directory('visual_test/goldens/exports')..createSync(recursive: true);
      Future<void> write(String name, String sourceId, PrintConfig c, ExportFormat f) async {
        final s = exportSource(app, sourceId)!;
        final t = s.build(app, const ExportQuery()).select([for (final col in s.columns) if (col.on) col.key]);
        final b = await renderExport(f, t, c, ctx);
        File('${dir.path}/$name.${f.ext}').writeAsBytesSync(b);
      }

      for (final f in ExportFormat.values) {
        await write('contracts', 'cycle:contracts', PrintConfig(), f);
      }
      await write('extracts_auto_landscape', 'cycle:extracts', PrintConfig(), ExportFormat.pdf);
      await write('ncr_fancy', 'unit:ncr', fancy, ExportFormat.pdf);
      await write('ncr_fancy', 'unit:ncr', fancy, ExportFormat.docx);
      await write('ncr_fancy', 'unit:ncr', fancy, ExportFormat.html);
      await write('reports_kufi_eastern', 'supervision:reports', PrintConfig(font: 'kufi', eastern: true, logo: 'banner', zebra: false),
          ExportFormat.pdf);
      await write('materials_sans', 'unit:material_approval', PrintConfig(font: 'sans', headerFill: 'gray', borders: 'horizontal'),
          ExportFormat.pdf);
      // أرقام وتواريخ ونِسب داخل نص عربي (العنوان الفرعي والملاحظات والتجميع)
      await write(
          'contracts_mixed',
          'cycle:contracts',
          PrintConfig(
            subtitle: 'كشف شهر 11/2026 حتى 2026/11/16',
            notes: 'اعتُمد الكشف بتاريخ 2026/11/16 الساعة 19:45، ونسبة الإنجاز 47.5% وفق المواصفة BS 4449 للعقد ع-2026/13.',
            groupBy: 'stage',
            cover: true,
            eastern: false,
          ),
          ExportFormat.pdf);
    });
  });
}

/// يفتح نافذة التصدير بعد أول إطار (للقطات).
class _OpenExport extends StatefulWidget {
  const _OpenExport({required this.sourceId});

  final String sourceId;

  @override
  State<_OpenExport> createState() => _OpenExportState();
}

class _OpenExportState extends State<_OpenExport> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) showExportDialog(context, sourceId: widget.sourceId);
    });
  }

  @override
  Widget build(BuildContext context) => const Scaffold(body: SizedBox());
}

/// يشغّل إجراءً يفتح نافذة بعد أول إطار (للقطات).
class _OpenAction extends StatefulWidget {
  const _OpenAction({required this.run});

  final void Function(BuildContext context) run;

  @override
  State<_OpenAction> createState() => _OpenActionState();
}

class _OpenActionState extends State<_OpenAction> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.run(context);
    });
  }

  @override
  Widget build(BuildContext context) => const Scaffold(body: SizedBox());
}

/// يفتح نافذة بعد أول إطار (للقطات).
class _OpenDialog extends StatefulWidget {
  const _OpenDialog({required this.builder});

  final WidgetBuilder builder;

  @override
  State<_OpenDialog> createState() => _OpenDialogState();
}

class _OpenDialogState extends State<_OpenDialog> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) showDialog<void>(context: context, builder: widget.builder);
    });
  }

  @override
  Widget build(BuildContext context) => const Scaffold(body: SizedBox());
}

/// يفتح محرر البيانات قبل التصدير (للقطات).
class _OpenEditor extends StatefulWidget {
  const _OpenEditor({required this.table});

  final ExportTable table;

  @override
  State<_OpenEditor> createState() => _OpenEditorState();
}

class _OpenEditorState extends State<_OpenEditor> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) editExportTable(context, widget.table);
    });
  }

  @override
  Widget build(BuildContext context) => const Scaffold(body: SizedBox());
}

/// بيانات «منظومة رصد»: الصلاحيات الدقيقة والأرقام والمراسلات ومركز الأمن.
void _rasd(AppState app) {
  final now = DateTime.now();
  String ago(int minutes) => now.subtract(Duration(minutes: minutes)).toUtc().toIso8601String();
  app.v11Ready = true;
  app.v12Ready = true;
  app.v13Ready = true;
  app.grants = {
    'u-1': {'form:f04', 'unit:ncr', 'docs:design'},
  };
  app.refSchemes = [
    const RefScheme(key: 'print', name: 'المطبوعات والملفات المصدّرة', pattern: 'م.ش.هـ/{SECTION}/{YYYY}/{SEQ}', system: true, codes: {
      'cycle': 'د.م', 'risks': 'م.م', 'swot': 'ت.س', 'docs': 'ش.ف', 'supervision': 'إش', 'heritage': 'تر', 'planning_qa': 'ت.ج',
      'safety': 'س.م', 'acceptance': 'م.س', 'print': 'ط', 'manual': 'د',
    }),
    const RefScheme(key: 'letter_out', name: 'المراسلات الصادرة', pattern: 'م.ش.هـ/ص/{YYYY}/{SEQ}', system: true),
    const RefScheme(key: 'letter_in', name: 'المراسلات الواردة', pattern: 'م.ش.هـ/و/{YYYY}/{SEQ}', system: true),
    const RefScheme(key: 'letter_internal', name: 'المراسلات الداخلية', pattern: 'م.ش.هـ/د/{YYYY}/{SEQ}', system: true),
    const RefScheme(key: 'contract_mail', name: 'مراسلات العقود', pattern: 'ع/{CODE}/{YY}{MM}/{SEQ:3}', reset: 'monthly', perSection: true, pad: 3),
  ];
  app.debugRefCounters = {'print|${now.year}': 186, 'letter_out|${now.year}': 49, 'letter_in|${now.year}': 73, 'contract_mail|${now.year}-${now.month.toString().padLeft(2, '0')}|cycle': 6};
  app.debugRefLog = [
    for (var i = 0; i < 9; i++)
      RefLogEntry(
        id: 200 - i,
        scheme: i.isEven ? 'print' : 'letter_out',
        ref: i.isEven ? 'م.ش.هـ/${['د.م', 'م.م', 'إش', 'م.س', 'ط'][i ~/ 2]}/${now.year}/${(186 - i).toString().padLeft(4, '0')}' : 'م.ش.هـ/ص/${now.year}/${(49 - i).toString().padLeft(4, '0')}',
        seq: 186 - i,
        period: '${now.year}',
        section: i.isEven ? ['cycle', 'risks', 'supervision', 'acceptance', 'print'][i ~/ 2] : null,
        source: i.isEven ? 'cycle:contracts' : null,
        title: i.isEven ? ['سجل العقود', 'سجل المخاطر', 'التقارير اليومية', 'حالات عدم المطابقة', 'مكتبة الوسائط'][i ~/ 2] : 'كتاب إلى الشركة المنفذة',
        createdBy: ['u-dir', 'u-1', 'u-2'][i % 3],
        createdAt: now.subtract(Duration(hours: i * 5)),
      ),
  ];
  app.settings = LiveSettings({
    ...app.settings.raw,
    'chat.config': {'enabled': true, 'groups': true, 'max_file_mb': 50, 'edit_minutes': 60},
  });
  ChatMessage m(int id, String room, String? sender, String body, {String kind = 'text', String? file, String? mime, int? size, Map<String, dynamic>? ref, int? reply, int ago = 0, bool edited = false}) =>
      ChatMessage(
        id: id,
        roomId: room,
        sender: sender,
        kind: kind,
        body: body,
        filePath: file == null ? null : '$room/$id.${file.split('.').last}',
        fileName: file,
        fileMime: mime,
        fileSize: size,
        ref: ref,
        replyTo: reply,
        createdAt: now.subtract(Duration(minutes: ago)),
        editedAt: edited ? now.subtract(Duration(minutes: ago - 2)) : null,
      );
  final grp = [
    m(1, 'r-grp', 'u-dir', 'أنشأ م. فيصل الشبلي المجموعة', kind: 'system', ago: 2900),
    m(2, 'r-grp', 'u-dir', 'صباح الخير. نحتاج تقرير الوضع الحالي لعقد 990 قبل اجتماع الأحد 9:00 صباحاً.', ago: 1500),
    m(3, 'r-grp', 'u-3', 'تم. نسبة الإنجاز الفعلية 47.5% مقابل 52% مخطط، والانحراف -4.5 نقطة بسبب تأخر توريد الحديد.', ago: 1490, edited: true),
    m(4, 'r-grp', 'u-3', 'جولة الموقع اليوم', kind: 'file', file: 'جولة الموقع 990.mp4', mime: 'video/mp4', size: 23500000, ago: 1480),
    m(5, 'r-grp', 'u-2', '', kind: 'link', ref: {'type': 'project', 'id': 'p-003', 'label': 'عقد ع-2026/13 — صيانة مدرسة', 'sub': 'شركة البناء الحديث'}, ago: 300),
    m(6, 'r-grp', 'u-dir', 'ممتاز. أرسلوا محضر الاجتماع بعد الانتهاء.', reply: 3, ago: 120),
    m(7, 'r-grp', 'u-1', 'المستخلص الثالث جاهز للمراجعة', kind: 'file', file: 'المستخلص الثالث.pdf', mime: 'application/pdf', size: 845000, ago: 25),
    m(8, 'r-grp', 'u-3', 'سأرفع صور الموقع بعد الظهر', ago: 3),
  ];
  final dm = [
    m(11, 'r-dm1', 'u-1', 'السلام عليكم، هل اعتُمد أمر التغيير رقم 2؟', ago: 200),
    m(12, 'r-dm1', 'u-dir', 'نعم، اعتمدته صباح اليوم بقيمة 125,000 د.ل', ago: 190),
    m(13, 'r-dm1', 'u-1', 'تم استلام المستخلص الثالث', ago: 60),
    m(14, 'r-dm1', 'u-dir', '', kind: 'text', ago: 30),
  ]..removeLast();
  final ch = [
    m(21, 'r-ch2', 'u-dir', 'أنشأ م. فيصل الشبلي القناة', kind: 'system', ago: 4000),
    m(22, 'r-ch2', 'u-dir', 'تُسلَّم التقارير اليومية قبل الثانية ظهراً، مع صور الموقع.', ago: 600),
    m(23, 'r-ch2', 'u-3', 'تم التعميم على مهندسي الإشراف.', ago: 500),
  ];
  final locked = [
    m(31, 'r-locked', 'u-1', 'الملفات المطلوبة مرفقة', kind: 'file', file: 'بيانات.xlsx', mime: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet', size: 380000, ago: 900),
    m(32, 'r-locked', 'u-dir', 'قُفلت المحادثة: مراجعة أمنية لتصدير بيانات', kind: 'system', ago: 800),
  ];
  ChatPreview p(ChatMessage x, String name) => ChatPreview(id: x.id, kind: x.kind, sender: x.sender, senderName: name, at: x.createdAt, text: x.kind == 'file' ? (x.fileName ?? '') : (x.kind == 'link' ? (x.ref?['label'] ?? '').toString() : x.body), mime: x.fileMime);
  app.chat.debugSeed([
    ChatRoom(id: 'r-grp', kind: 'group', title: 'فريق عقد 990 – الإشراف', description: 'متابعة يومية للموقع', myRole: 'owner', unread: 3, members: 4, lastMessageAt: grp.last.createdAt, last: p(grp.last, 'أحمد الفيتوري'), createdAt: now.subtract(const Duration(days: 2))),
    ChatRoom(id: 'r-dm1', kind: 'dm', pinned: true, peer: const ChatPeer(id: 'u-1', name: 'سالم المبروك', role: 'contracts'), lastMessageAt: dm.last.createdAt, last: p(dm.last, 'سالم المبروك'), members: 2),
    ChatRoom(id: generalChannelId, kind: 'channel', title: 'المكتب – عام', description: 'قناة يراها كل مستخدمي المنظومة', audience: const {'all': true}, myRole: 'admin', unread: 2, lastMessageAt: now.subtract(const Duration(minutes: 45)), last: ChatPreview(id: 40, kind: 'text', sender: 'u-2', senderName: 'هدى العبيدي', at: now.subtract(const Duration(minutes: 45)), text: 'تذكير: اجتماع المكتب الأسبوعي غداً 10:00')),
    ChatRoom(id: 'r-ch2', kind: 'channel', title: 'قسم الإشراف', description: 'تعليمات القسم', audience: const {'departments': ['supervision']}, adminsOnly: true, myRole: 'admin', lastMessageAt: ch.last.createdAt, last: p(ch.last, 'أحمد الفيتوري')),
    ChatRoom(id: 'r-dm2', kind: 'dm', peer: const ChatPeer(id: 'u-3', name: 'أحمد الفيتوري', role: 'dept_head'), unread: 1, lastMessageAt: now.subtract(const Duration(hours: 26)), last: ChatPreview(id: 50, kind: 'file', sender: 'u-3', senderName: 'أحمد الفيتوري', at: now.subtract(const Duration(hours: 26)), text: 'صورة الأعمدة.jpg', mime: 'image/jpeg')),
    ChatRoom(id: 'r-locked', kind: 'group', title: 'تصدير بيانات العقود', locked: true, lockReason: 'مراجعة أمنية لتصدير بيانات', myRole: 'member', members: 3, lastMessageAt: locked.last.createdAt, last: p(locked.last, '')),
  ], {
    'r-grp': grp,
    'r-dm1': dm,
    'r-ch2': ch,
    'r-locked': locked,
  });

  final days = [for (var i = 29; i >= 0; i--) DateTime(now.year, now.month, now.day).subtract(Duration(days: i))];
  String d0(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  secFixtures = {
    'sec_dashboard': {
      'days': 30,
      'generated_at': now.toUtc().toIso8601String(),
      'viewer': 'director',
      'freeze': false,
      'users': {'total': 19, 'active': 15, 'pending': 2, 'disabled': 2, 'locked': 1, 'mfa': 11, 'no_mfa_sensitive': 1, 'stale_60': 2,
        'by_role': {'director': 1, 'office_staff': 3, 'dept_head': 4, 'contracts': 3, 'planning_qa': 2, 'security_auditor': 1, 'pending': 2}, 'with_grants': 1, 'grants': 3},
      'sessions': 14,
      'devices': {'total': 31, 'trusted': 22, 'blocked': 1, 'new': 4, 'active_24h': 12, 'platforms': {'android': 14, 'windows': 9, 'web': 8}},
      'audit': {'events': 1842, 'writes': 1210, 'deletes': 37, 'exports': 96, 'security': 41, 'settings': 9, 'off_hours': 63, 'actors': 14},
      'categories': [
        {'key': 'form', 'n': 512}, {'key': 'unit', 'n': 388}, {'key': 'report', 'n': 260}, {'key': 'finance', 'n': 205}, {'key': 'export', 'n': 96},
        {'key': 'risk', 'n': 88}, {'key': 'doc', 'n': 74}, {'key': 'chat', 'n': 31}, {'key': 'user', 'n': 25}, {'key': 'security', 'n': 16},
      ],
      'daily': [for (var i = 0; i < days.length; i++) {'day': d0(days[i]), 'events': 30 + (i * 37) % 70 + (days[i].weekday >= 5 && days[i].weekday <= 6 ? -25 : 0), 'deletes': i % 7 == 3 ? 9 : i % 3, 'security': i % 4}],
      'heatmap': [for (var d = 1; d <= 7; d++) for (var h = 6; h <= 22; h++) [d, h, (d == 5 || d == 6) ? (h % 5 == 0 ? 2 : 0) : ((h >= 8 && h <= 15) ? 18 + (d * h) % 22 : (h % 4 == 0 ? 3 : 1))]],
      'actors': [
        {'name': 'هدى العبيدي', 'n': 412, 'deletes': 3, 'exports': 21},
        {'name': 'سالم المبروك', 'n': 366, 'deletes': 12, 'exports': 38},
        {'name': 'أحمد الفيتوري', 'n': 298, 'deletes': 1, 'exports': 9},
        {'name': 'م. فيصل الشبلي', 'n': 241, 'deletes': 15, 'exports': 12},
        {'name': 'مهندس الجودة', 'n': 133, 'deletes': 0, 'exports': 4},
      ],
      'logins': [],
      'storage': [
        {'bucket': 'docs', 'files': 1284, 'bytes': 2830000000, 'new': 210},
        {'bucket': 'chat', 'files': 96, 'bytes': 412000000, 'new': 96},
        {'bucket': 'releases', 'files': 6, 'bytes': 198000000, 'new': 3},
      ],
      'chat': {'messages': 1263, 'files': 96, 'bytes': 412000000, 'senders': 13, 'locked_rooms': 1},
      'refs': {'issued': 187, 'schemes': 3},
      'incidents': {'open': 2, 'critical': 1, 'total': 5},
      'alerts': 3,
    },
    'sec_posture': [
      {'key': 'rls', 'group': 'قاعدة البيانات', 'title': 'حماية مستوى الصفوف على كل الجداول', 'ok': true, 'severity': 'high', 'count': 0, 'items': [], 'detail': 'كل جداول المنظومة محمية بسياسات قراءة.'},
      {'key': 'search_path', 'group': 'قاعدة البيانات', 'title': 'مسار بحث ثابت لكل دالة بصلاحية المالك', 'ok': true, 'severity': 'high', 'count': 0, 'items': [], 'detail': 'يمنع تمرير دوال مزيّفة إلى الدوال التي تعمل بصلاحية المالك.'},
      {'key': 'anon_write', 'group': 'قاعدة البيانات', 'title': 'لا كتابة لغير المسجّلين', 'ok': true, 'severity': 'high', 'count': 0, 'items': [], 'detail': 'صلاحيات كتابة ممنوحة للدور anon.'},
      {'key': 'direct_write', 'group': 'قاعدة البيانات', 'title': 'الكتابة عبر الدوال المدققة فقط', 'ok': true, 'severity': 'medium', 'count': 0, 'items': [], 'detail': 'جداول يكتب فيها المستخدمون مباشرة.'},
      {'key': 'buckets', 'group': 'التخزين', 'title': 'حاويات الملفات خاصة', 'ok': true, 'severity': 'high', 'count': 0, 'items': [], 'detail': 'المستندات والمرفقات والمراسلات لا تُقرأ إلا بصلاحية؛ حاوية الإصدارات وحدها عامة لتنزيل التطبيق.'},
      {'key': 'director_mfa', 'group': 'الهوية', 'title': 'مدير المكتب يستخدم التحقق بخطوتين', 'ok': true, 'severity': 'high', 'detail': 'أهم حساب في المنظومة.'},
      {'key': 'mfa_sensitive', 'group': 'الهوية', 'title': 'الحسابات الحساسة تستخدم التحقق بخطوتين', 'ok': false, 'severity': 'medium', 'count': 1, 'items': ['هدى العبيدي'], 'detail': 'مسؤول الأمن وموظفو المكتب.'},
      {'key': 'stale', 'group': 'الهوية', 'title': 'لا حسابات خاملة مفعّلة', 'ok': false, 'severity': 'medium', 'count': 2, 'items': ['مهندس الحصر 2', 'مراقب الموقع'], 'detail': 'حسابات مفعّلة لم تُستخدم منذ 60 يوماً.'},
      {'key': 'pending', 'group': 'الهوية', 'title': 'لا طلبات تسجيل معلّقة قديمة', 'ok': true, 'severity': 'low', 'count': 0, 'items': [], 'detail': 'طلبات تسجيل مضى عليها أكثر من أسبوع.'},
      {'key': 'mfa_director_policy', 'group': 'السياسات', 'title': 'فرض التحقق بخطوتين على المدير', 'ok': true, 'severity': 'medium', 'detail': 'من مركز الأمان في لوحة التحكم.'},
      {'key': 'mfa_all_policy', 'group': 'السياسات', 'title': 'فرض التحقق بخطوتين على كل المستخدمين', 'ok': false, 'severity': 'low', 'detail': 'يُنصح به عند اكتمال تفعيل الهواتف.'},
      {'key': 'signups', 'group': 'السياسات', 'title': 'التسجيل الجديد مغلق عند عدم الحاجة', 'ok': true, 'severity': 'low', 'detail': ''},
      {'key': 'idle', 'group': 'السياسات', 'title': 'قفل الجلسة بعد خمول لا يتجاوز ساعة', 'ok': true, 'severity': 'medium', 'detail': 'الخروج التلقائي من الأجهزة المتروكة.'},
      {'key': 'freeze', 'group': 'السياسات', 'title': 'المنظومة غير مجمّدة', 'ok': true, 'severity': 'low', 'detail': 'التجميد إجراء طوارئ مؤقت.'},
      {'key': 'grants_excess', 'group': 'الصلاحيات', 'title': 'لا صلاحيات دقيقة مفرطة', 'ok': true, 'severity': 'low', 'count': 0, 'items': [], 'detail': ''},
      {'key': 'grants_inactive', 'group': 'الصلاحيات', 'title': 'لا صلاحيات لحسابات موقوفة أو مقفلة', 'ok': true, 'severity': 'medium', 'count': 0, 'items': [], 'detail': ''},
      {'key': 'one_director', 'group': 'الصلاحيات', 'title': 'مدير مكتب واحد', 'ok': true, 'severity': 'high', 'count': 1, 'detail': 'لا يُمنح دور المدير من التطبيق.'},
      {'key': 'ciso', 'group': 'الصلاحيات', 'title': 'مسؤول أمن سيبراني مفعّل', 'ok': true, 'severity': 'low', 'count': 1, 'detail': 'فصل المهام: من يراقب غير من يدير.'},
      {'key': 'blocked_active', 'group': 'الأجهزة', 'title': 'لا نشاط من أجهزة محظورة', 'ok': true, 'severity': 'high', 'count': 0, 'detail': ''},
      {'key': 'incidents', 'group': 'الحوادث', 'title': 'لا حوادث عالية الخطورة مفتوحة', 'ok': false, 'severity': 'high', 'count': 1, 'detail': 'من سجل الحوادث الأمنية.'},
    ],
    'sec_anomalies': [
      {'kind': 'mass_delete', 'severity': 'high', 'user_id': 'u-1', 'name': 'سالم المبروك', 'title': 'حذف 12 عنصراً خلال ساعة', 'at': ago(180), 'count': 12},
      {'kind': 'mass_export', 'severity': 'medium', 'user_id': 'u-1', 'name': 'سالم المبروك', 'title': 'استخرج 31 ملفاً في يوم واحد', 'at': ago(1500), 'count': 31},
      {'kind': 'off_hours', 'severity': 'low', 'user_id': 'u-3', 'name': 'أحمد الفيتوري', 'title': '9 تعديلاً خارج أوقات الدوام', 'at': ago(2900), 'count': 9},
      {'kind': 'privilege', 'severity': 'medium', 'user_id': 'u-dir', 'name': 'م. فيصل الشبلي', 'title': 'تعديل صلاحيات دقيقة: سالم المبروك', 'at': ago(4000), 'count': 1},
      {'kind': 'new_device', 'severity': 'medium', 'user_id': 'u-2', 'name': 'هدى العبيدي', 'title': 'جهاز جديد لحساب موظف المكتب: Windows', 'at': ago(5200), 'count': 1},
    ],
    'security_alerts': [
      {'kind': 'mfa_missing', 'level': 'warning', 'title': 'حساب حساس دون تحقق بخطوتين: هدى العبيدي', 'user_id': 'u-2', 'at': ago(60)},
      {'kind': 'off_hours_login', 'level': 'info', 'title': 'دخول خارج ساعات العمل: أحمد الفيتوري', 'user_id': 'u-3', 'at': ago(700)},
    ],
    'sec_access_matrix': [
      for (final u in [
        ('u-dir', 'م. فيصل الشبلي', 'director', null, true, 2, 26, 26, <String>[], 241, 15, 12, 88),
        ('u-2', 'هدى العبيدي', 'office_staff', null, false, 3, 20, 26, <String>[], 412, 3, 21, 301),
        ('u-1', 'سالم المبروك', 'contracts', null, true, 2, 9, 26, ['docs:design', 'form:f04', 'unit:ncr'], 366, 12, 38, 154),
        ('u-3', 'أحمد الفيتوري', 'dept_head', 'supervision', true, 4, 7, 26, <String>[], 298, 1, 9, 410),
      ])
        {
          'id': u.$1, 'name': u.$2, 'email': '${u.$1}@office.ly', 'role': u.$3, 'department': u.$4, 'unit': u.$1 == 'u-1' ? 'quality_control' : null,
          'unit_head': false, 'active': true, 'locked': false, 'mfa': u.$5, 'last_seen': ago(u.$6 * 37), 'devices': u.$6, 'forms': u.$7,
          'forms_total': u.$8, 'grants': u.$9, 'events_30d': u.$10, 'deletes_30d': u.$11, 'exports_30d': u.$12, 'messages_30d': u.$13,
        },
    ],
    'sec_data_activity': {
      'days': 30,
      'exports': [
        for (var i = 0; i < 8; i++)
          {'at': ago(i * 95), 'name': ['سالم المبروك', 'هدى العبيدي', 'أحمد الفيتوري'][i % 3], 'kind': i.isEven ? 'file' : 'print',
            'source': 'cycle:finance', 'title': ['المالية', 'سجل العقود', 'سجل المخاطر', 'التقارير اليومية'][i % 4], 'format': ['xlsx', 'pdf', 'docx'][i % 3], 'rows': 12 + i * 7, 'bytes': 84000 + i * 21000},
      ],
      'export_formats': {'pdf': 51, 'xlsx': 33, 'docx': 12},
      'deletes': [{'at': ago(180), 'name': 'سالم المبروك', 'action': 'unit.delete', 'label': 'وحدة ضبط الجودة'}],
      'refs': [{'at': ago(30), 'ref': 'م.ش.هـ/د.م/${now.year}/0186', 'scheme': 'المطبوعات والملفات المصدّرة', 'by': 'م. فيصل الشبلي', 'title': 'سجل العقود'}],
      'uploads': [{'at': ago(70), 'by': 'أحمد الفيتوري', 'name': 'صور الموقع 990.jpg', 'mime': 'image/jpeg', 'size': 1450000, 'where': 'تقرير إشراف'}],
      'uploads_total': {'files': 1284, 'bytes': 2830000000},
      'settings': [{'at': ago(4000), 'name': 'م. فيصل الشبلي', 'key': 'ui.layout', 'action': 'setting.update'}],
    },
    'sec_chat_overview': {
      'days': 30,
      'totals': {'rooms': 23, 'dm': 15, 'groups': 6, 'channels': 2, 'locked': 1, 'messages': 1263, 'files': 96, 'bytes': 412000000, 'deleted': 7, 'edited': 22, 'senders': 13, 'off_hours': 58},
      'rooms': [
        {'id': 'r-grp', 'kind': 'group', 'title': 'فريق عقد 990 – الإشراف', 'locked': false, 'members': 4, 'messages': 312, 'files': 28, 'bytes': 186000000, 'last_at': ago(3)},
        {'id': 'r-dm1', 'kind': 'dm', 'title': 'م. فيصل الشبلي — سالم المبروك', 'locked': false, 'members': 2, 'messages': 88, 'files': 3, 'bytes': 2400000, 'last_at': ago(60)},
        {'id': 'r-locked', 'kind': 'group', 'title': 'تصدير بيانات العقود', 'locked': true, 'lock_reason': 'مراجعة أمنية لتصدير بيانات', 'members': 3, 'messages': 14, 'files': 6, 'bytes': 9800000, 'last_at': ago(800)},
      ],
      'senders': [
        {'name': 'أحمد الفيتوري', 'messages': 410, 'files': 41, 'bytes': 220000000},
        {'name': 'هدى العبيدي', 'messages': 301, 'files': 9, 'bytes': 12000000},
        {'name': 'سالم المبروك', 'messages': 154, 'files': 18, 'bytes': 64000000},
      ],
      'pairs': [
        {'from': 'أحمد الفيتوري', 'to': 'فريق عقد 990 – الإشراف', 'kind': 'group', 'messages': 160, 'last_at': ago(3)},
        {'from': 'سالم المبروك', 'to': 'م. فيصل الشبلي — سالم المبروك', 'kind': 'dm', 'messages': 44, 'last_at': ago(60)},
      ],
      'daily': [for (var i = 0; i < days.length; i++) {'day': d0(days[i]), 'messages': 20 + (i * 13) % 50}],
      'types': [
        {'type': 'video', 'files': 21, 'bytes': 300000000},
        {'type': 'image', 'files': 52, 'bytes': 80000000},
        {'type': 'application', 'files': 23, 'bytes': 32000000},
      ],
      'large': [
        {'sender': 'أحمد الفيتوري', 'room': 'فريق عقد 990 – الإشراف', 'mime': 'video/mp4', 'size': 48200000, 'at': ago(1480)},
      ],
    },
    'security_incidents': [
      {'id': 'i1', 'title': 'تصدير كثيف من حساب العقود', 'severity': 'high', 'status': 'investigating', 'category': 'data', 'details': '31 ملفاً في يوم واحد، منها 12 لسجل المالية.', 'actions': 'تعليق الصلاحيات الدقيقة مؤقتاً والتواصل مع المستخدم.', 'user_id': 'u-1', 'detected_at': ago(1400)},
      {'id': 'i2', 'title': 'جهاز جديد لموظفة المكتب خارج الدوام', 'severity': 'medium', 'status': 'open', 'category': 'device', 'details': 'دخول من جهاز Windows جديد الساعة 22:10.', 'actions': '', 'user_id': 'u-2', 'detected_at': ago(5200)},
      {'id': 'i3', 'title': 'محاولة دخول من جهاز محظور', 'severity': 'low', 'status': 'closed', 'category': 'device', 'details': '', 'actions': 'الجهاز محظور مسبقاً؛ لا إجراء.', 'user_id': null, 'detected_at': ago(20000), 'closed_at': ago(19000)},
    ],
  };
}
