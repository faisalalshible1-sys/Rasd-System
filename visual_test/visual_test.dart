// لقطات بصرية للصفحات الرئيسية ببيانات تجريبية (للتدقيق على التصميم، لا تُشغَّل مع الاختبارات العادية):
//   flutter test visual_test --update-goldens
// تُحفظ الصور في visual_test/goldens/ ويرفعها سير العمل visual.yml.
import 'dart:io';

import 'package:dc_app/app_state.dart';
import 'package:dc_app/models.dart';
import 'package:dc_app/registers.dart';
import 'package:dc_app/screens/assistant.dart';
import 'package:dc_app/screens/auth.dart';
import 'package:dc_app/screens/contract_finance.dart';
import 'package:dc_app/screens/cycle_guide.dart';
import 'package:dc_app/screens/control/appearance.dart';
import 'package:dc_app/screens/control/settings.dart';
import 'package:dc_app/screens/dashboard.dart';
import 'package:dc_app/screens/finance.dart';
import 'package:dc_app/screens/home_shell.dart';
import 'package:dc_app/screens/project_detail.dart';
import 'package:dc_app/screens/risks.dart';
import 'package:dc_app/screens/swot.dart';
import 'package:dc_app/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _desktop = Size(1440, 2600);
const _mobile = Size(400, 3200);

Future<void> _loadFonts() async {
  // خط محلي يدعم العربية بدل Google Fonts (لا شبكة في الاختبارات)
  final candidates = <String, List<String>>{
    'regular': [
      '/usr/share/fonts/truetype/noto/NotoSansArabic-Regular.ttf',
      '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',
    ],
    'bold': [
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
  const forms = [
    ('f01', 'أمر تعاقد', 0), ('f20', 'المقايسة التقديرية', 0), ('f02', 'أمر عمل', 0), ('f03', 'نموذج عقد أشغال عامة', 0),
    ('f04', 'تكليف مهندس مشرف', 1), ('f05', 'تكليف مهندس حصر', 1), ('f06', 'تكليف مهندس متابعة', 1), ('f07', 'تكليف مهندس سلامة', 1),
    ('f08', 'محضر تسليم واستلام موقع', 2), ('f09', 'تصريح عمل', 2),
    ('f10', 'ورقة قياس مستخلص نموذج أ', 3), ('f12', 'كشف حصر مستخلص', 3), ('f13', 'شهادة دفع مستخلص', 3), ('f14', 'مستند مستخلص جاري', 3),
    ('f16', 'محضر استلام ابتدائي', 4), ('f17', 'محضر استلام نهائي', 4), ('f18', 'إقفال عقد', 4),
  ];
  app.allFormDefs = [
    for (var i = 0; i < forms.length; i++)
      FormDef.fromMap({
        'key': forms[i].$1,
        'name': forms[i].$2,
        'stage': forms[i].$3,
        'sort': i + 1,
        'sensitive': forms[i].$3 >= 3,
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
      'guarantee_initial': gross * 0.05,
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
  ];
  app.notifications = [
    AppNotification.fromMap({'id': 'n1', 'created_at': _iso(0), 'kind': 'request', 'title': 'طلب اعتماد جديد', 'body': 'شهادة دفع مستخلص — عقد ع-2026/12'}),
  ];
  app.v2Ready = true;
  app.v3Ready = true;
  app.v4Ready = true;
  app.v5Ready = true;
  app.v6Ready = true;
  app.showHub = false;
  app.loadedOnce = true;
  _registers(app);
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
    app.tab = 30;
    await _shot(tester, '70_swot_dashboard_light', app, const HomeShell(), size: const Size(1440, 2400));
    await _shot(tester, '71_swot_matrix_dark', app, _scaffold(const SwotMatrixPage()), size: const Size(1200, 1500), dark: true);
    await _shot(tester, '72_swot_factors_light', app, _scaffold(const SwotFactorsPage()), size: const Size(1200, 2200));
    await _shot(tester, '73_swot_weighted_light', app, _scaffold(const SwotWeightedPage()), size: const Size(1200, 2000));
    await _shot(tester, '74_swot_tows_mobile', app, _scaffold(const SwotTowsPage()), size: const Size(400, 2600));
    await _shot(tester, '75_swot_plan_light', app, _scaffold(const SwotPlanPage()), size: const Size(1200, 1900));
    await _shot(tester, '76_swot_method_light', app, _scaffold(const SwotMethodPage()), size: const Size(1200, 2600));
  });
}
