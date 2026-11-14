// لقطات بصرية للصفحات الرئيسية ببيانات تجريبية (للتدقيق على التصميم، لا تُشغَّل مع الاختبارات العادية):
//   flutter test visual_test --update-goldens
// تُحفظ الصور في visual_test/goldens/ ويرفعها سير العمل visual.yml.
import 'dart:async';
import 'dart:io';

import 'package:dc_app/app_state.dart';
import 'package:dc_app/docs.dart';
import 'package:dc_app/models.dart';
import 'package:dc_app/pm.dart';
import 'package:dc_app/registers.dart';
import 'package:dc_app/screens/assistant.dart';
import 'package:dc_app/screens/auth.dart';
import 'package:dc_app/screens/contract_finance.dart';
import 'package:dc_app/screens/cycle_guide.dart';
import 'package:dc_app/screens/control/appearance.dart';
import 'package:dc_app/screens/control/settings.dart';
import 'package:dc_app/screens/dashboard.dart';
import 'package:dc_app/screens/docs.dart';
import 'package:dc_app/screens/units.dart';
import 'package:dc_app/units.dart';
import 'package:dc_app/screens/finance.dart';
import 'package:dc_app/screens/home_shell.dart';
import 'package:dc_app/screens/manual.dart';
import 'package:dc_app/screens/project_detail.dart';
import 'package:dc_app/screens/pm_contractors.dart';
import 'package:dc_app/screens/pm_dashboard.dart';
import 'package:dc_app/screens/pm_presentation.dart';
import 'package:dc_app/screens/pm_projects.dart';
import 'package:dc_app/screens/pm_registers.dart';
import 'package:dc_app/screens/pm_report.dart';
import 'package:dc_app/screens/pm_settings.dart';
import 'package:dc_app/screens/risks.dart';
import 'package:dc_app/screens/supervision.dart';
import 'package:dc_app/screens/swot.dart';
import 'package:dc_app/screens/swot_presentation.dart';
import 'package:dc_app/ui/slideshow.dart';
import 'package:dc_app/ui/theme.dart';
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
  final app = AppState(client);
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
      'guarantee_initial': i == 5 ? null : gross * 0.05,
      'guarantee_initial_na': i == 5,
      'guarantee_final': gross * 0.02,
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
  _units(app);
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
  rec('nc1', 'ncr', 'غياب سجل معايرة أجهزة الموقع', parent: 'qa1', project: 'p-003', ago: 12, due: -3, level: 'major', owner: 'المقاول',
      data: {'requirement': 'البند 8.2 من خطة الجودة', 'corrective_action': 'معايرة الأجهزة لدى جهة معتمدة وتقديم الشهادات.'});
  rec('nc2', 'ncr', 'عدم توثيق استلام المواد في الموقع', parent: 'qa1', project: 'p-003', ago: 12, due: 7, status: 'in_progress', level: 'minor',
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
}
