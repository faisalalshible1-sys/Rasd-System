import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' show sha256;
import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart' show launchUrl;

import 'boq_import.dart' show PdfRun;
import 'config.dart';
import 'docs.dart';
import 'models.dart';
import 'pm.dart';
import 'prices.dart';
import 'registers.dart';
import 'schedule.dart';
import 'services/boq_files.dart' show parseExtractReply;
import 'services/doc_files.dart';
import 'chat.dart';
import 'print/model.dart';
import 'rasd.dart';
import 'scope.dart';
import 'units.dart';
import 'ui/appearance.dart';

/// حالة التطبيق المشتركة: البيانات، التحديث اللحظي، والعمليات على قاعدة البيانات.
/// قاعدة البيانات هي صاحبة القرار في الصلاحيات؛ ما هنا يحدد ما يُعرض من أزرار فقط.
class AppState extends ChangeNotifier {
  AppState(this.client);

  final SupabaseClient client;

  Profile? me;
  List<Department> departments = [];
  List<FormDef> formDefs = [];
  List<Project> projects = [];
  Map<String, Map<String, FormStatus>> statuses = {};
  List<ChangeRequest> requests = [];
  Map<String, Profile> people = {};
  List<AppNotification> notifications = [];

  // الإصدار الثاني: الإعدادات الحية والتعريفات القابلة للتعديل
  LiveSettings settings = LiveSettings.empty();
  Map<String, dynamic> publicSettings = {};
  List<StageDef> stages = [];
  List<FormDef> allFormDefs = []; // تشمل النماذج الموقوفة (للوحة التحكم)
  List<CustomField> customFields = [];
  List<Idea> ideas = [];
  bool v2Ready = false; // هل طُبّق ملف قاعدة البيانات للإصدار الثاني

  // الإصدار الثالث: أعمال العقود ومهندسوها بأرقام تكليفهم
  List<ContractWork> works = [];
  List<ContractEngineer> engineers = [];
  bool v3Ready = false;
  Map<String, List<ContractWork>> _worksBy = {};
  Map<String, List<ContractEngineer>> _engBy = {};

  // الإصدار الرابع: المالية الموسعة (أوامر التغيير والمستخلصات) والأمان الموسع
  List<ContractVariation> variations = [];
  List<ContractExtract> extracts = [];
  bool v4Ready = false;
  Map<String, List<ContractVariation>> _varBy = {};
  Map<String, List<ContractExtract>> _extBy = {};

  // الإصدار الخامس: سجل دفعات المستخلصات والإحالة للصرف والدفعة المقدمة
  List<ExtractPayment> payments = [];
  bool v5Ready = false;

  // القسمان الرئيسيان: سجل المخاطر وتحليل SWOT (الإصدار السادس)
  List<Risk> risks = [];
  List<SwotFactor> swotFactors = [];
  List<SwotStrategy> swotStrategies = [];
  List<SwotAction> swotActions = [];
  bool v6Ready = false;
  Map<String, List<ExtractPayment>> _payBy = {};

  // الإصدار السابع: «المخاطر ومتابعة المشاريع» (البرنامج الزمني والتقدم والمراجعات والسجلات)
  Map<String, PmSchedule> schedules = {};
  List<PmProgress> measurements = [];
  List<RiskReview> riskReviews = [];
  List<PmIssue> pmIssues = [];
  List<PmDelay> pmDelays = [];
  List<PmChange> pmChanges = [];
  List<PmLesson> pmLessons = [];
  List<PmEvaluation> pmEvaluations = [];
  bool v7Ready = false;
  PmAnalysis? _pm;

  /// الترحيل 18: خيار «لا ينطبق» للضمان الابتدائي (وحراسة «لا ينطبق» لتكليف المهندسين في القاعدة).
  bool naReady = false;

  // الترحيل 20: «المستندات الفنية» (المقايسات والمراسلات والتصاميم) و«الإشراف» (التقارير اليومية)
  DocIndex docs = DocIndex.empty();
  bool v8Ready = false;
  late final SignedUrls signedUrls = SignedUrls(client);

  // الترحيل 21: أقسام الوحدات (الترميم والمباني التاريخية، التخطيط وضمان الجودة، السلامة المهنية، المطابقة والاستلام)
  UnitIndex units = UnitIndex.empty();
  bool v9Ready = false;

  // الترحيل 22: الشؤون الفنية، والفيديو، وقوالب الطباعة وسجل التصدير
  List<PrintTemplate> printTemplates = [];
  bool v10Ready = false;

  // الترحيل 23: «منظومة رصد» — الصلاحيات الدقيقة، والرقم الإشاري الموسّع، وتخصيص الواجهة
  Map<String, Set<String>> grants = {};
  List<RefScheme> refSchemes = [];
  bool v11Ready = false;

  // الترحيل 24: المراسلات الداخلية (لها حالتها وتحديثها اللحظي في ChatController)
  bool v12Ready = false;
  late final ChatController chat = ChatController(this);

  // الترحيل 25: مركز الأمن السيبراني الموسّع
  bool v13Ready = false;

  // الترحيلات 27–29: لائحة الأسعار الاسترشادية والمقايسات المعدّة منها، وبنود الجدول الزمني لكل مشروع
  List<PriceList> priceLists = [];
  List<BoqSheet> boqSheets = [];
  List<PmItem> pmItems = [];
  bool v14Ready = false;
  ScheduleAnalysis? _schedule;

  // الترحيل 30: البرنامج الزمني ومراحله (تعدّه الشؤون الفنية ويتابعه الإشراف)، واعتماد المقايسات
  Map<String, PmPlan> pmPlans = {};
  List<PmPhase> pmPhases = [];
  bool v15Ready = false;

  // الترحيل 31: ترجمة التنفيذ إلى المخاطر وSWOT (يُحدَّث عند الفتح مرة في الساعة على الأكثر)
  bool v16Ready = false;
  bool _autoRefreshed = false;

  // الترحيل 32: نسخ PDF المحفوظة لرمز QR
  bool v17Ready = false;

  // الترحيل 33: الأفكار بالقسم والصفحة، وحذف المقايسة يحذف بنودها من البرنامج الزمني
  bool v18Ready = false;

  // الترحيل 35: ملف العقد ومرفقاته المصنّفة
  bool v19Ready = false;

  // الترحيل 36: استيراد المقايسات، ومعدلات الإنتاجية، والعلاقات والمسار الحرج، وإصدارات البرنامج الزمني وصلاحياته
  bool v20Ready = false;

  /// الترحيل 34: نطاق المستخدم (أقسامه ووحداته ونماذجه المسندة). null قبل الترحيل: تظهر الأقسام كما كانت.
  UserScope? scope;

  /// تواريخ آخر تحديث لحالات النماذج (لتواريخ مراحل دورة حياة العقد).
  Map<String, Map<String, DateTime>> formDates = {};

  /// آخر نتائج معروضة في صفحة لائحة الأسعار (مصدر تصديرها).
  List<PriceItem> priceResults = [];

  /// محادثة مساعد Claude الحالية (تبقى أثناء التنقل بين الصفحات).
  final List<AssistantMessage> assistantMessages = [];

  // تفضيلات هذا الجهاز
  ThemeMode themeMode = ThemeMode.system;

  /// «تذكرني»: يبقى الدخول محفوظاً ويُوثَّق الجهاز. بدونها يُطلب الدخول عند كل فتح.
  bool rememberMe = true;
  String rememberedEmail = '';

  /// معرّف هذا الجهاز في سجل الأجهزة (عشوائي، يُنشأ مرة واحدة).
  String deviceKey = '';

  /// دخل المستخدم في هذا التشغيل (لا يُطلب الدخول ثانية حتى مع إلغاء «تذكرني»).
  bool signedInThisRun = false;
  bool _loginEventPending = false;

  /// سبب الخروج الأمني الأخير (جهاز محظور أو قفل) لعرضه في شاشة الدخول.
  String? securityNotice;

  /// يُستدعى عند اكتشاف حظر الجهاز أو قفل الحساب أثناء الاستخدام.
  void Function(String kind)? onSecurityHalt;

  Future<void> loadPrefs() async {
    try {
      final p = await SharedPreferences.getInstance();
      themeMode = switch (p.getString('theme_mode')) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      };
      rememberMe = p.getBool('remember_me') ?? true;
      rememberedEmail = p.getString('remember_email') ?? '';
      deviceKey = p.getString('device_key') ?? '';
      if (deviceKey.length < 16) {
        final r = Random.secure();
        const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
        deviceKey = 'dc-${List.generate(28, (_) => chars[r.nextInt(chars.length)]).join()}';
        await p.setString('device_key', deviceKey);
      }
    } catch (_) {
      if (deviceKey.isEmpty) deviceKey = 'dc-${DateTime.now().microsecondsSinceEpoch}';
    }
  }

  /// قبل محاولة الدخول: اختيار «تذكرني» يحدد توثيق الجهاز عند تسجيله.
  void prepareLogin({required bool remember}) {
    rememberMe = remember;
    signedInThisRun = true;
    _loginEventPending = true;
  }

  /// يحفظ اختيار «تذكرني» بعد دخول ناجح.
  Future<void> rememberLogin({required bool remember, required String email}) async {
    rememberMe = remember;
    rememberedEmail = remember ? email.trim() : '';
    signedInThisRun = true;
    try {
      final p = await SharedPreferences.getInstance();
      await p.setBool('remember_me', remember);
      if (remember) {
        await p.setString('remember_email', email.trim());
      } else {
        await p.remove('remember_email');
      }
    } catch (_) {}
  }

  /// اسم المنصة لسجل الأجهزة.
  static String get devicePlatform {
    if (kIsWeb) return 'web';
    return switch (defaultTargetPlatform) {
      TargetPlatform.android => 'android',
      TargetPlatform.iOS => 'ios',
      TargetPlatform.windows => 'windows',
      TargetPlatform.macOS => 'macos',
      TargetPlatform.linux => 'linux',
      _ => 'other',
    };
  }

  /// يسجّل هذا الجهاز (دخول أو فتح أو نبضة) ويُرجع حالته: ok أو blocked أو locked.
  /// قاعدة بيانات أقدم بلا سجل أجهزة: يُعتبر ok.
  Future<String> registerDevice({String? event}) async {
    final ev = event ?? (_loginEventPending ? 'login' : 'open');
    final wasLogin = ev == 'login';
    try {
      final res = await client.rpc('register_device', params: {
        'p_device_key': deviceKey,
        'p_platform': devicePlatform,
        'p_label': platformLabels[devicePlatform] ?? devicePlatform,
        'p_app_version': AppConfig.appVersion.length > 30 ? AppConfig.appVersion.substring(0, 30) : AppConfig.appVersion,
        // التوثيق يتبع اختيار «تذكرني» عند الدخول فقط؛ الفتح والنبضة لا يغيّرانه
        'p_trusted': wasLogin ? rememberMe : null,
        'p_event': ev,
      });
      if (wasLogin) _loginEventPending = false;
      if (res is Map) {
        if (res['blocked'] == true) return 'blocked';
        if (res['locked'] == true) return 'locked';
      }
      return 'ok';
    } catch (_) {
      return 'ok';
    }
  }

  Timer? _heartbeat;

  void _startHeartbeat() {
    _heartbeat?.cancel();
    _heartbeat = Timer.periodic(const Duration(minutes: 15), (_) async {
      if (_disposed || client.auth.currentSession == null) return;
      final st = await registerDevice(event: 'ping');
      if (st != 'ok') onSecurityHalt?.call(st);
    });
  }

  Future<void> setThemeMode(ThemeMode m) async {
    themeMode = m;
    _notify();
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString('theme_mode', m.name);
    } catch (_) {}
  }

  bool loading = false;
  bool loadedOnce = false;

  /// يزيد مع كل تحميل ناجح (لتحديث ما يُقرأ خارج الحالة، مثل سجل النشاط).
  int dataVersion = 0;
  String? loadError;

  // التنقل والتصفية المشتركة بين الشاشات
  int _tab = 0;
  String _section = 'cycle';

  /// الصفحة الحالية. تعيينها يضع المستخدم في قسمها (بعد نقل المدير للصفحات بين الأقسام).
  int get tab => _tab;
  set tab(int v) {
    _tab = v;
    _section = sectionForTab(v);
  }

  /// القسم الحالي: قسم الصفحة، أو القسم الذي فتحه المستخدم.
  String get section => _section;

  /// شاشة الأقسام الرئيسية الثلاثة تظهر عند الدخول، ثم يعمل كل قسم بقائمته.
  bool showHub = true;
  String ownerFilter = '';
  String companyFilter = '';
  String search = '';
  CycleState? cycleFilter;
  int? stageFilter; // 0..5
  String? formFilter;
  bool formFilterNextOnly = false;
  String sort = 'order';

  // التحديث
  AppRelease? latestRelease; // أحدث إصدار أعلى من الإصدار الحالي
  bool updateMandatory = false;
  bool updateDismissed = false;

  RealtimeChannel? _channel;
  RealtimeChannel? _channel2;
  RealtimeChannel? _channel3;
  RealtimeChannel? _channel4;
  RealtimeChannel? _channel5;
  RealtimeChannel? _channel6;
  RealtimeChannel? _channel7;
  RealtimeChannel? _channel8;
  RealtimeChannel? _channel9;
  RealtimeChannel? _channel11;
  RealtimeChannel? _channel14;
  RealtimeChannel? _channel15;
  Timer? _debounce;
  Timer? _updateTimer;
  bool _disposed = false;
  final Map<String, Progress> _progressCache = {};

  // ---------------------------------------------------------------
  // الصلاحيات (للعرض فقط)
  // ---------------------------------------------------------------
  bool get isDirector => me?.isDirector ?? false;

  /// CISO: اطلاع كامل للقراءة فقط على الأمان والتدقيق وبيانات المستخدمين.
  bool get isAuditor => me?.isAuditor ?? false;

  /// المدير وCISO يطّلعان على مركز الأمان وسجل التدقيق والبيانات الكاملة للمستخدمين.
  bool get canAudit => isDirector || isAuditor;
  AppRole? get role => me?.active == true ? me?.role : null;
  bool get canManageProjects => role == AppRole.director || role == AppRole.officeStaff;
  bool get canAddQualityNote => role == AppRole.director || role == AppRole.planningQa;
  bool get canEditAnyForm =>
      role != null && role != AppRole.planningQa && role != AppRole.securityAuditor && !frozenForMe;

  /// المنظومة مجمّدة (قراءة فقط) لغير المدير.
  bool get frozenForMe => settings.frozen && !isDirector;

  /// هل يملك المستخدم أحد رموز الاختصاص في هذا المشروع؟
  bool hasToken(Project p, List<String> tokens) {
    final r = role;
    if (r == null) return false;
    if (r == AppRole.director) return true;
    if (settings.frozen) return false;
    final dep = me?.department;
    return switch (r) {
      AppRole.director => true,
      AppRole.officeStaff => tokens.contains('office_staff'),
      AppRole.contracts => tokens.contains('contracts'),
      AppRole.planningQa => tokens.contains('planning_qa'),
      AppRole.securityAuditor => false,
      AppRole.deptHead => (tokens.contains('head:supervising') && dep == p.department) ||
          (tokens.contains('head:technical') && dep == 'technical') ||
          (tokens.contains('head:acceptance') && dep == 'acceptance'),
    };
  }

  /// صلاحية دقيقة منحها المدير لهذا المستخدم (نموذج، أو صفحة، أو نوع سجل). التجميد يوقفها.
  bool hasGrant(String scope) {
    final r = role;
    if (!v11Ready || r == null || r == AppRole.director || r == AppRole.securityAuditor || settings.frozen) return false;
    return grants[me?.id]?.contains(scope) ?? false;
  }

  /// الصلاحيات الدقيقة لمستخدم.
  Set<String> grantsOf(String userId) => grants[userId] ?? const {};

  /// تخصيص المدير للأقسام والصفحات (يُقرأ مرة لكل نسخة من الإعدادات).
  UiLayout get layout {
    final raw = settings.raw['ui.layout'];
    if (!identical(raw, _layoutRaw) || _layoutCache == null) {
      _layoutRaw = raw;
      _layoutCache = UiLayout.fromJson(raw);
    }
    return _layoutCache!;
  }

  Object? _layoutRaw;
  UiLayout? _layoutCache;

  /// معاينة التخصيص أثناء تحريره في شاشة الدخول (لا تُحفظ إلا بالحفظ).
  bool hubEditRequested = false;

  bool canEditForm(Project p, FormDef d) =>
      d.active ? hasToken(p, d.responsible) || hasGrant('form:${d.key}') : isDirector;

  bool canEditField(Project p, CustomField f) => f.active && hasToken(p, f.editableBy);

  List<CustomField> get activeFields => customFields.where((f) => f.active).toList();

  /// لون الهوية من الإعدادات الحية (أو من إعدادات ما قبل الدخول).
  Color get brandColor {
    final hex = settings.raw.isNotEmpty ? settings.primaryHex : (publicSettings['brand.primary_color'] ?? '#8A6A1E').toString();
    return parseHexColor(hex) ?? const Color(0xFF8A6A1E);
  }

  String get appTitle => settings.raw.isNotEmpty
      ? settings.appTitle
      : (publicSettings['brand.app_title'] ?? 'منظومة رصد').toString();

  String get orgName => settings.raw.isNotEmpty ? settings.orgName : (publicSettings['brand.org_name'] ?? 'مكتب الشؤون الهندسية').toString();

  bool get signupsOpen => publicSettings['security.signups_open'] != false && (settings.raw.isEmpty || settings.signupsOpen);

  int get idleMinutes {
    final v = settings.raw.isNotEmpty ? settings.idleMinutes : publicSettings['security.idle_minutes'];
    return v is num ? v.toInt() : 30;
  }

  bool get mfaRequiredForMe {
    final all = settings.raw.isNotEmpty ? settings.requireMfaAll : publicSettings['security.require_mfa_all'] == true;
    // التحقق بخطوتين إلزامي لمدير المكتب وCISO دائماً، واختياري للبقية ما لم يُفرض على الجميع
    return all || me?.role == AppRole.director || me?.role == AppRole.securityAuditor;
  }

  bool needsApproval(FormDef d) => d.sensitive && !isDirector;

  /// البيانات المالية للعقد يحدّثها من يختص بـ«أمر بالتعاقد» في المشروع.
  bool canEditFinance(Project p) {
    final d = formDef(contractFormKey);
    return d != null && canEditForm(p, d);
  }

  /// رقم العقد ودمج الأعمال: مكتب العقود ومدير المكتب.
  bool canEditContractNo(Project p) => v3Ready && hasToken(p, const ['contracts']);
  bool canMerge(Project p) => v3Ready && hasToken(p, const ['contracts']);

  /// فك الدمج: مدير المكتب وحده.
  bool get canUnmerge => v3Ready && isDirector;

  /// أعمال العقد: مكتب العقود وموظفو مكتب المدير والمدير.
  bool canEditWorks(Project p) => v3Ready && hasToken(p, const ['contracts', 'office_staff']);

  /// نموذج التكليف المقابل لنوع المهندس (كما تحدده قاعدة البيانات: أول نموذج بالترتيب).
  FormDef? engineerFormOf(String kind) {
    FormDef? best;
    for (final d in allFormDefs) {
      if (d.engineerField == 'eng_$kind' && (best == null || d.sort < best.sort)) best = d;
    }
    return best;
  }

  /// تكليف مهندس من نوع معيّن: من يختص بنموذج التكليف المقابل.
  bool canAssignEngineer(Project p, String kind) {
    if (!v3Ready) return false;
    final d = engineerFormOf(kind);
    return d == null ? isDirector : canEditForm(p, d);
  }

  bool canAssignAnyEngineer(Project p) => engineerKinds.any((k) => canAssignEngineer(p, k));

  /// تكليف هذا النوع «لا ينطبق» على العقد: نموذج التكليف المقابل حالته «لا ينطبق».
  bool engineerNa(Project p, String kind) {
    final d = engineerFormOf(kind);
    return d != null && statusOf(p.id, d.key) == FormStatus.na;
  }

  /// قيم البنود وأوامر التغيير والمستخلصات: من يختص بالبيانات المالية للعقد.
  bool canEditFinanceItems(Project p) => v4Ready && canEditFinance(p);

  /// المستخلص المدفوع لا يعدّله ولا يحذفه إلا مدير المكتب.
  bool canEditExtract(Project p, ContractExtract x) => canEditFinanceItems(p) && (!x.isPaid || isDirector);

  /// مساعد Claude: لمدير المكتب وحده، ويمكن إيقافه من الإعدادات.
  bool get canUseAssistant => isDirector && v3Ready && settings.aiEnabled;

  /// من يختص بالنموذج، بصياغة تُعرض للمستخدم.
  String responsibleText(Project p, FormDef d) {
    final parts = <String>['مدير المكتب'];
    for (final t in d.responsible) {
      if (t == 'head:supervising') {
        parts.add('رئيس قسم ${departmentName(p.department)}');
      } else {
        parts.add(responsibleLabels[t] ?? t);
      }
    }
    return parts.join('، ');
  }

  String departmentName(String? key) {
    for (final d in departments) {
      if (d.key == key) return d.name;
    }
    return key ?? '';
  }

  String personName(String? id) {
    if (id == null) return 'النظام';
    if (id == me?.id) return 'أنت';
    return people[id]?.displayName ?? 'عضو في الفريق';
  }

  FormDef? formDef(String key) {
    for (final d in formDefs) {
      if (d.key == key) return d;
    }
    return null;
  }

  Project? project(String id) {
    for (final p in projects) {
      if (p.id == id) return p;
    }
    return null;
  }

  Progress progressOf(Project p) => _progressCache.putIfAbsent(p.id, () => computeProgress(formDefs, statuses[p.id]));

  FormStatus statusOf(String projectId, String formKey) => statuses[projectId]?[formKey] ?? FormStatus.todo;

  ChangeRequest? pendingFor(String projectId, String formKey) {
    for (final r in requests) {
      if (r.isPending && r.projectId == projectId && r.formKey == formKey) return r;
    }
    return null;
  }

  List<ChangeRequest> get pendingRequests => requests.where((r) => r.isPending).toList();
  List<ChangeRequest> get myRequests => requests.where((r) => r.requestedBy == me?.id).toList();
  int get unreadCount => notifications.where((n) => n.unread).length;

  List<String> get owners => (projects.map((p) => p.owner).where((s) => s.trim().isNotEmpty).toSet().toList()..sort());

  /// الشركات: شركة العقد وشركات أعماله المدمجة.
  List<String> get companies => ({
        for (final p in projects) p.company.trim(),
        for (final w in works) w.company.trim(),
      }.where((s) => s.isNotEmpty).toList()
        ..sort());

  /// أعمال العقد بالترتيب.
  List<ContractWork> worksOf(String projectId) => _worksBy[projectId] ?? const [];

  /// مهندسو العقد (كل الأنواع، أو نوع واحد).
  List<ContractEngineer> engineersOf(String projectId, [String? kind]) {
    final all = _engBy[projectId] ?? const <ContractEngineer>[];
    return kind == null ? all : all.where((e) => e.kind == kind).toList();
  }

  /// كل شركات العقد (شركته وشركات أعماله) بلا تكرار.
  List<String> companiesOf(Project p) {
    final out = <String>[];
    for (final c in [p.company, ...worksOf(p.id).map((w) => w.company)]) {
      final t = c.trim();
      if (t.isNotEmpty && !out.contains(t)) out.add(t);
    }
    return out;
  }

  /// دفعات مستخلص من سجل الصرف.
  List<ExtractPayment> paymentsOf(String extractId) => _payBy[extractId] ?? const [];

  /// أوامر تغيير العقد.
  List<ContractVariation> variationsOf(String projectId) => _varBy[projectId] ?? const [];

  /// مستخلصات العقد بالترتيب.
  List<ContractExtract> extractsOf(String projectId) => _extBy[projectId] ?? const [];

  ContractWork? work(String? id) {
    if (id == null) return null;
    for (final w in works) {
      if (w.id == id) return w;
    }
    return null;
  }

  /// كل أسماء المهندسين المسجلة (لاقتراحها عند التكليف).
  List<String> engineerNames([String? kind]) =>
      ({for (final e in engineers) if (kind == null || e.kind == kind) e.name.trim()}.where((s) => s.isNotEmpty).toList()..sort());

  /// المشاريع ضمن تصفية المالك والشركة (للرئيسية والتحليل).
  List<Project> get scoped => projects
      .where((p) => (ownerFilter.isEmpty || p.owner == ownerFilter) && (companyFilter.isEmpty || companiesOf(p).contains(companyFilter)))
      .toList();

  // ---------------------------------------------------------------
  // التحميل والتحديث اللحظي
  // ---------------------------------------------------------------
  Future<void> loadProfile() async {
    final uid = client.auth.currentUser?.id;
    if (uid == null) {
      me = null;
      _notify();
      return;
    }
    final row = await client.from('profiles').select().eq('id', uid).maybeSingle();
    me = row == null ? null : Profile.fromMap(row);
    _notify();
  }

  Future<void> start() async {
    await loadAll();
    _subscribe();
    _updateTimer?.cancel();
    _updateTimer = Timer.periodic(const Duration(hours: 3), (_) => checkForUpdate());
    _startHeartbeat();
    if (pendingExportToken != null) unawaited(openPendingExport());
  }

  // ---------------------------------------------------------------
  // رمز QR يفتح نسخة PDF الأصلية المحفوظة (الترحيل 32)
  // ---------------------------------------------------------------

  /// رمز مستند من رابط QR (?f=...) ينتظر الدخول لفتحه.
  String? pendingExportToken;

  /// نتيجة فتح المستند لتظهر في أعلى الصفحة (النص، والمستوى).
  ({String text, String level})? exportNotice;

  void clearExportNotice() {
    exportNotice = null;
    _notify();
  }

  static final RegExp _tokenRe = RegExp(r'^[A-Za-z0-9]{20,40}$');

  /// يقرأ رمز المستند من رابط الويب عند الفتح.
  void readExportLink(Uri uri) {
    final f = uri.queryParameters['f'];
    pendingExportToken = f != null && _tokenRe.hasMatch(f) ? f : null;
  }

  /// يفتح النسخة المحفوظة لمن يحق له (رابط موقّت في الصفحة نفسها)، ويُبلغ غيره بالرفض.
  Future<void> openPendingExport() async {
    final token = pendingExportToken;
    pendingExportToken = null;
    if (token == null) return;
    if (!v17Ready) {
      exportNotice = (text: 'فتح المستندات من رمز التحقق يعمل بعد تحديث قاعدة البيانات بالترحيل 32.', level: 'warning');
      _notify();
      return;
    }
    try {
      final r = Map<String, dynamic>.from(await client.rpc('open_export_file', params: {'p_token': token}) as Map);
      if (r['ok'] != true) {
        exportNotice = r['reason'] == 'denied'
            ? (text: 'المستند «${r['title'] ?? ''}» مقيّد الاطلاع؛ لا تملك صلاحية فتحه. سُجّلت المحاولة في سجل التدقيق.', level: 'critical')
            : (text: 'رمز التحقق غير معروف: لم يُستخرج هذا المستند من المنظومة أو الرابط ناقص.', level: 'critical');
        _notify();
        return;
      }
      final url = await client.storage.from('exports').createSignedUrl('${r['path']}', 900);
      final sha = '${r['sha256'] ?? ''}';
      exportNotice = (
        text: 'فُتحت النسخة الأصلية المحفوظة من «${r['title'] ?? ''}»${'${r['ref_no'] ?? ''}'.isEmpty ? '' : ' (${r['ref_no']})'} '
            'كما استُخرجت ${r['created_by'] == null ? '' : 'بواسطة ${r['created_by']} '}· بصمتها ${sha.length >= 12 ? sha.substring(0, 12) : sha}',
        level: 'ok'
      );
      _notify();
      await launchUrl(Uri.parse(url), webOnlyWindowName: '_self');
    } catch (e) {
      exportNotice = (text: 'تعذّر فتح المستند: ${friendlyError(e)}', level: 'critical');
      _notify();
    }
  }

  String? _webBase;

  /// عنوان المنظومة على الويب لرابط QR: عنوان الصفحة الحالية على الويب، وإلا آخر إصدار ويب منشور.
  Future<String> webBaseUrl() async {
    if (kIsWeb) {
      final b = Uri.base;
      return Uri(scheme: b.scheme, host: b.host, port: b.hasPort ? b.port : null, path: b.path.isEmpty ? '/' : b.path).toString();
    }
    if (_webBase != null) return _webBase!;
    try {
      final r = await client.from('app_releases').select('url').eq('platform', 'web').order('build', ascending: false).limit(1).maybeSingle();
      final u = '${r?['url'] ?? ''}'.trim();
      if (u.startsWith('https://')) _webBase = u.endsWith('/') ? u : '$u/';
    } catch (_) {}
    return _webBase ??= 'https://faisalalshible1-sys.github.io/Rasd-System/';
  }

  /// رمز عشوائي لمستند (24 حرفاً وأرقاماً).
  static String newExportToken() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789';
    final r = Random.secure();
    return List.generate(24, (_) => chars[r.nextInt(chars.length)]).join();
  }

  /// يحفظ نسخة PDF كما هي ويسجّلها بالرمز؛ false إن تعذّر (فيُطبع رمز التحقق النصي بدلها).
  Future<bool> storeExportFile({
    required String token,
    required Uint8List bytes,
    required String title,
    required String refNo,
    required String source,
    String? projectId,
    bool confidential = false,
  }) async {
    final uid = me?.id;
    if (!v17Ready || uid == null) return false;
    final path = '$uid/$token.pdf';
    try {
      await client.storage.from('exports').uploadBinary(path, bytes, fileOptions: const FileOptions(contentType: 'application/pdf', upsert: false));
      await client.rpc('register_export_file', params: {
        'p_token': token,
        'p_data': {
          'title': title,
          'ref_no': refNo,
          'source': source,
          'project_id': projectId ?? '',
          'access': confidential ? 'private' : 'members',
          'sha256': sha256.convert(bytes).toString(),
          'bytes': bytes.length,
        },
      });
      return true;
    } catch (_) {
      try {
        await client.storage.from('exports').remove([path]);
      } catch (_) {}
      return false;
    }
  }

  /// منصة هذه النسخة كما تُسجَّل في جدول الإصدارات.
  static String? get currentPlatform {
    if (kIsWeb) return 'web';
    return switch (defaultTargetPlatform) {
      TargetPlatform.android => 'android',
      TargetPlatform.windows => 'windows',
      TargetPlatform.iOS => 'ios',
      _ => null,
    };
  }

  /// يبحث عن إصدار أحدث لهذه المنصة. لا يوقف التطبيق إن لم يكن جدول الإصدارات موجوداً.
  Future<void> checkForUpdate() async {
    final platform = currentPlatform;
    if (!AppConfig.isRelease || platform == null) return;
    try {
      final newer = await client
          .from('app_releases')
          .select()
          .eq('platform', platform)
          .gt('build', AppConfig.appBuild)
          .order('build', ascending: false)
          .limit(20);
      final list = newer.map(AppRelease.fromMap).toList();
      final latest = list.isEmpty ? null : list.first;
      final mandatory = list.any((r) => r.mandatory);
      if (latest?.build != latestRelease?.build) updateDismissed = false;
      latestRelease = latest;
      updateMandatory = mandatory;
      _notify();
    } catch (_) {
      // جدول الإصدارات غير مُنشأ بعد، أو لا اتصال: نتجاهل بهدوء.
    }
  }

  void dismissUpdate() {
    updateDismissed = true;
    _notify();
  }

  Future<void> loadAll() async {
    loading = true;
    final first = !loadedOnce;
    _notify();
    try {
      final scopeF = _loadScope();
      final List<Future<List<Map<String, dynamic>>>> queries = [
        client.from('departments').select().order('sort'),
        client.from('form_defs').select().order('sort'),
        client.from('projects').select().order('sort_order'),
        client.from('project_forms').select('project_id, form_key, status, updated_at'),
        client.from('change_requests').select().order('requested_at', ascending: false).limit(500),
        client.from('profiles').select('id, full_name, email, role, department, active, created_at'),
        client.from('notifications').select().order('created_at', ascending: false).limit(100),
      ];
      final r = await Future.wait(queries);
      departments = r[0].map(Department.fromMap).toList();
      allFormDefs = r[1].map(FormDef.fromMap).toList()..sort((a, b) => a.sort.compareTo(b.sort));
      formDefs = allFormDefs.where((d) => d.active).toList();
      scope = await scopeF;
      projects = await _withRefs(r[2].map(Project.fromMap).toList());
      naReady = r[2].isNotEmpty ? r[2].first.containsKey('guarantee_initial_na') : await _probeNa();
      final st = <String, Map<String, FormStatus>>{};
      final fd = <String, Map<String, DateTime>>{};
      for (final row in r[3]) {
        final pid = row['project_id'].toString();
        (st[pid] ??= <String, FormStatus>{})[row['form_key'].toString()] = parseStatus(row['status']);
        final at = DateTime.tryParse('${row['updated_at'] ?? ''}');
        if (at != null) (fd[pid] ??= <String, DateTime>{})[row['form_key'].toString()] = at.toLocal();
      }
      statuses = st;
      formDates = fd;
      requests = r[4].map(ChangeRequest.fromMap).toList();
      people = {for (final p in r[5].map(Profile.fromMap)) p.id: p};
      notifications = r[6].map(AppNotification.fromMap).toList();
      final mine = people[me?.id];
      if (mine != null) me = mine;
      await _loadV2();
      await _loadV3();
      await _loadV4();
      await _loadV6();
      await _loadV7();
      await _loadV8();
      await _loadV9();
      await _loadV10();
      await _loadV11();
      await _loadV12();
      await _loadV13();
      await _loadV14();
      await _loadV15();
      await _loadV17();
      await _loadV18();
      await _loadV19();
      await _loadV20();
      _progressCache.clear();
      loadError = null;
      loadedOnce = true;
      if (first) _landInSection();
      dataVersion++;
      unawaited(checkForUpdate());
    } catch (e) {
      loadError = friendlyError(e);
    } finally {
      loading = false;
      _notify();
    }
  }

  /// نطاق المستخدم من قاعدة البيانات (الترحيل 34)؛ null قبل الترحيل.
  Future<UserScope?> _loadScope() async {
    try {
      return UserScope.fromJson(await client.rpc('my_scope'));
    } catch (_) {
      return null;
    }
  }

  /// العقود بتفاصيلها، وأساسيات بقية العقود للربط لمن لا يراها كلها من قسمه.
  Future<List<Project>> _withRefs(List<Project> full) async {
    final sc = scope;
    if (sc == null || sc.allProjects) return full;
    try {
      final refs = await client.rpc('project_refs');
      final have = {for (final p in full) p.id};
      final out = [...full];
      if (refs is List) {
        for (final m in refs) {
          if (m is Map && !have.contains('${m['id']}')) out.add(Project.ref(Map<String, dynamic>.from(m)));
        }
      }
      out.sort((a, b) => a.sortOrder != b.sortOrder ? a.sortOrder.compareTo(b.sortOrder) : a.name.compareTo(b.name));
      return out;
    } catch (_) {
      return full;
    }
  }

  /// خيار «لا ينطبق» للضمان الابتدائي (الترحيل 18) حين لا يرى المستخدم عقداً بتفاصيله.
  Future<bool> _probeNa() async {
    try {
      await client.from('projects').select('guarantee_initial_na').limit(1);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// بعد الدخول: من له قسم عمل واحد يدخله مباشرة (واجهة قسمه وحدها).
  void _landInSection() {
    final sc = scope;
    if (sc == null || sc.full) return;
    final work = [
      for (final s in sc.workSections) if (!(layout.sections[s]?.hidden ?? false)) s,
      if (canAudit) 'security',
    ];
    if (!showHub || work.length != 1) return;
    final s = work.single;
    var t = _lastTab[s] ?? 0;
    if (t == 72 && !v15Ready) t = 70;
    _section = s;
    _tab = sectionForTab(t) == s ? t : -1;
    showHub = false;
  }

  // ---------------------------------------------------------------
  // عزل الأقسام (الترحيل 34)
  // ---------------------------------------------------------------

  /// هل يرى المستخدم هذا القسم؟ الأمن السيبراني للمدير وCISO، والمشتركة للجميع، والبقية بحسب النطاق.
  bool seesSection(String s) {
    if (s == 'security') return canAudit;
    final sc = scope;
    if (sc == null) return true;
    return sharedSections.contains(s) || sc.sections.contains(s);
  }

  /// هل يطّلع على سجلات هذه الوحدة؟
  bool seesUnit(String unit) => scope?.units.contains(unit) ?? true;

  /// المستخدم معزول في قسمه (ليس من مكتب المدير).
  bool get isolated => scope != null && !scope!.full;

  /// العقود بتفاصيلها (دون الأساسيات وحدها).
  List<Project> get fullProjects => [for (final p in projects) if (!p.limited) p];

  /// العقود التي يتابعها الإشراف من هذا الحساب: كلها لمكتب المدير والعقود ومن مُنح التقارير أو المتابعة،
  /// وعقود قسمه لرئيس القسم المشرف.
  List<Project> get siteProjects {
    final sc = scope;
    if (sc == null || sc.allProjects || (grants[me?.id]?.any((g) => g == 'supervision:reports' || g == 'pm:track') ?? false)) {
      return projects;
    }
    return fullProjects;
  }

  /// هل النموذج مسند إلى المستخدم في هذا العقد (بالاختصاص أو بصلاحية دقيقة)؟ لا يتأثر بالتجميد.
  bool formAssigned(Project p, FormDef d) {
    final r = role;
    if (r == null || r == AppRole.securityAuditor) return false;
    if (r == AppRole.director || r == AppRole.officeStaff) return true;
    final t = d.responsible;
    final dep = me?.department;
    final byRole = switch (r) {
      AppRole.contracts => t.contains('contracts'),
      AppRole.planningQa => t.contains('planning_qa'),
      AppRole.deptHead => (t.contains('head:supervising') && dep == p.department && !p.limited) ||
          (t.contains('head:technical') && dep == 'technical') ||
          (t.contains('head:acceptance') && dep == 'acceptance'),
      _ => false,
    };
    return byRole || (v11Ready && (grants[me?.id]?.contains('form:${d.key}') ?? false));
  }

  /// نماذج الدورة المسندة إلى من لا يرى الدورة المستندية: كل عقد ونماذجه المسندة إليه فيه.
  List<(Project, List<FormDef>)> get assignedForms {
    if (!isolated || seesSection('cycle')) return const [];
    final out = <(Project, List<FormDef>)>[];
    for (final p in projects) {
      final ds = [for (final d in formDefs) if (formAssigned(p, d)) d];
      if (ds.isNotEmpty) out.add((p, ds));
    }
    return out;
  }

  /// إجراءات خطة SWOT المسندة إلى قسم رئيسه (لمن لا يرى قسم SWOT).
  List<SwotAction> get assignedSwot {
    if (!isolated || seesSection('swot') || role != AppRole.deptHead) return const [];
    final dn = departmentName(me?.department);
    return [for (final x in swotActions) if (x.department == 'جميع الأقسام' || x.department == 'قسم $dn' || x.department == dn) x];
  }

  /// صفحة «المهام المسندة» في أقسام من أُسندت إليه نماذج من الدورة أو إجراءات من خطة SWOT.
  bool get hasAssignedWork => assignedForms.isNotEmpty || assignedSwot.isNotEmpty;

  /// النماذج المسندة التي لم تكتمل (لا «تم» ولا «لا ينطبق») وإجراءات SWOT غير المكتملة: شارة الصفحة.
  int get assignedPending {
    var n = 0;
    for (final (p, ds) in assignedForms) {
      for (final d in ds) {
        final st = statusOf(p.id, d.key);
        if (st != FormStatus.done && st != FormStatus.na) n++;
      }
    }
    return n + assignedSwot.where((x) => x.status != 'completed').length;
  }

  /// جداول الإصدار الثاني؛ يعمل التطبيق بدونها إن لم يُطبَّق ملف قاعدة البيانات بعد.
  Future<void> _loadV2() async {
    try {
      final r = await Future.wait<List<Map<String, dynamic>>>([
        client.from('app_settings').select('key, value'),
        client.from('stages').select().order('idx'),
        client.from('custom_fields').select().order('sort'),
        client.from('ideas').select().order('created_at', ascending: false).limit(300),
      ]);
      settings = LiveSettings({for (final row in r[0]) row['key'].toString(): row['value']});
      settings.applyGlobals();
      appearance = _appearancePreview ?? Appearance.fromJson(settings.raw['ui.appearance']);
      stages = r[1].map(StageDef.fromMap).toList();
      if (stages.isNotEmpty) stageNames = [for (final st in stages) st.name];
      customFields = r[2].map(CustomField.fromMap).toList();
      ideas = r[3].map(Idea.fromMap).toList();
      v2Ready = true;
    } catch (_) {
      v2Ready = false;
    }
  }

  /// جداول الإصدار الثالث (العقود والأعمال والمهندسون)؛ يعمل التطبيق بدونها كما كان.
  Future<void> _loadV3() async {
    try {
      final r = await Future.wait<List<Map<String, dynamic>>>([
        client.from('contract_works').select().order('sort'),
        client.from('contract_engineers').select().order('sort'),
      ]);
      works = r[0].map(ContractWork.fromMap).toList();
      engineers = r[1].map(ContractEngineer.fromMap).toList();
      final wb = <String, List<ContractWork>>{};
      for (final w in works) {
        (wb[w.projectId] ??= []).add(w);
      }
      final eb = <String, List<ContractEngineer>>{};
      for (final e in engineers) {
        (eb[e.projectId] ??= []).add(e);
      }
      _worksBy = wb;
      _engBy = eb;
      v3Ready = true;
    } catch (_) {
      works = [];
      engineers = [];
      _worksBy = {};
      _engBy = {};
      v3Ready = false;
    }
  }

  /// يعيد بناء فهارس الأعمال والمهندسين والمستخلصات وأوامر التغيير (للاختبارات والمعاينة).
  void indexData() {
    _worksBy = {};
    for (final w in works) {
      (_worksBy[w.projectId] ??= []).add(w);
    }
    _engBy = {};
    for (final e in engineers) {
      (_engBy[e.projectId] ??= []).add(e);
    }
    _varBy = {};
    for (final v in variations) {
      (_varBy[v.projectId] ??= []).add(v);
    }
    _extBy = {};
    for (final x in extracts) {
      (_extBy[x.projectId] ??= []).add(x);
    }
    _payBy = {};
    for (final y in payments) {
      (_payBy[y.extractId] ??= []).add(y);
    }
    _progressCache.clear();
    _notify();
  }

  /// جداول الإصدار الرابع (أوامر التغيير والمستخلصات)؛ يعمل التطبيق بدونها كما كان.
  Future<void> _loadV4() async {
    try {
      final r = await Future.wait<List<Map<String, dynamic>>>([
        client.from('contract_variations').select().order('created_at', ascending: true),
        client.from('contract_extracts').select().order('seq', ascending: true),
      ]);
      variations = r[0].map(ContractVariation.fromMap).toList();
      extracts = r[1].map(ContractExtract.fromMap).toList();
      final vb = <String, List<ContractVariation>>{};
      for (final v in variations) {
        (vb[v.projectId] ??= []).add(v);
      }
      final xb = <String, List<ContractExtract>>{};
      for (final x in extracts) {
        (xb[x.projectId] ??= []).add(x);
      }
      _varBy = vb;
      _extBy = xb;
      v4Ready = true;
      await _loadV5();
    } catch (_) {
      variations = [];
      extracts = [];
      _varBy = {};
      _extBy = {};
      v4Ready = false;
    }
  }

  /// سجل دفعات المستخلصات (الإصدار الخامس)؛ يعمل التطبيق بدونه كما كان.
  Future<void> _loadV5() async {
    try {
      final rows = await client.from('extract_payments').select().order('paid_on', ascending: true);
      payments = rows.map(ExtractPayment.fromMap).toList();
      final pb = <String, List<ExtractPayment>>{};
      for (final y in payments) {
        (pb[y.extractId] ??= []).add(y);
      }
      _payBy = pb;
      v5Ready = true;
    } catch (_) {
      payments = [];
      _payBy = {};
      v5Ready = false;
    }
  }

  /// سجل المخاطر وتحليل SWOT (الإصدار السادس)؛ يعمل التطبيق بدونهما كما كان.
  Future<void> _loadV6() async {
    try {
      final r = await Future.wait<List<Map<String, dynamic>>>([
        client.from('risks').select().order('code'),
        client.from('swot_factors').select().order('sort'),
        client.from('swot_strategies').select().order('sort'),
        client.from('swot_actions').select().order('sort'),
      ]);
      risks = r[0].map(Risk.fromMap).toList();
      swotFactors = r[1].map(SwotFactor.fromMap).toList();
      swotStrategies = r[2].map(SwotStrategy.fromMap).toList();
      swotActions = r[3].map(SwotAction.fromMap).toList();
      v6Ready = true;
    } catch (_) {
      risks = [];
      swotFactors = [];
      swotStrategies = [];
      swotActions = [];
      v6Ready = false;
    }
  }

  /// متابعة المشاريع (الإصدار السابع)؛ يعمل التطبيق بدونها كما كان.
  Future<void> _loadV7() async {
    _pm = null;
    try {
      final r = await Future.wait<List<Map<String, dynamic>>>([
        client.from('pm_projects').select(),
        client.from('pm_progress').select().order('measured_on'),
        client.from('risk_reviews').select().order('reviewed_on'),
        client.from('pm_issues').select().order('code'),
        client.from('pm_delays').select().order('code'),
        client.from('pm_changes').select().order('code'),
        client.from('pm_lessons').select().order('code'),
        client.from('pm_evaluations').select().order('evaluated_on'),
      ]);
      schedules = {for (final s in r[0].map(PmSchedule.fromMap)) s.projectId: s};
      measurements = r[1].map(PmProgress.fromMap).toList();
      riskReviews = r[2].map(RiskReview.fromMap).toList();
      pmIssues = r[3].map(PmIssue.fromMap).toList();
      pmDelays = r[4].map(PmDelay.fromMap).toList();
      pmChanges = r[5].map(PmChange.fromMap).toList();
      pmLessons = r[6].map(PmLesson.fromMap).toList();
      pmEvaluations = r[7].map(PmEvaluation.fromMap).toList();
      v7Ready = true;
    } catch (_) {
      _clearV7();
    }
  }

  /// المستندات الفنية والتقارير اليومية (الترحيل 20)؛ يعمل التطبيق بدونها كما كان.
  Future<void> _loadV8() async {
    try {
      final r = await Future.wait<List<Map<String, dynamic>>>([
        client.from('doc_items').select().order('doc_date', ascending: false),
        client.from('doc_revisions').select().order('rev_no'),
        client.from('doc_files').select().order('sort'),
        client.from('site_reports').select().order('report_date', ascending: false).limit(5000),
      ]);
      docs = DocIndex(
        items: r[0].map(DocItem.fromMap).toList(),
        revisions: r[1].map(DocRevision.fromMap).toList(),
        files: r[2].map(DocFile.fromMap).toList(),
        reports: r[3].map(SiteReport.fromMap).toList(),
      );
      v8Ready = true;
    } catch (_) {
      docs = DocIndex.empty();
      v8Ready = false;
    }
  }

  Future<void> _afterV8() async {
    await _loadV8();
    _notify();
  }

  /// أقسام الوحدات (الترحيل 21)؛ يعمل التطبيق بدونها كما كان. وحدات المستخدمين تُدمج في people.
  Future<void> _loadV9() async {
    try {
      final r = await Future.wait<List<Map<String, dynamic>>>([
        client.from('unit_records').select().order('rec_date', ascending: false).limit(10000),
        client.from('profiles').select('id, unit, unit_head'),
      ]);
      units = UnitIndex(r[0].map(UnitRecord.fromMap).toList());
      for (final row in r[1]) {
        final id = row['id'].toString();
        final p = people[id];
        if (p != null) people[id] = p.withUnit(row['unit'] as String?, row['unit_head'] == true);
      }
      final mine = people[me?.id];
      if (mine != null) me = mine;
      v9Ready = true;
    } catch (_) {
      units = UnitIndex.empty();
      v9Ready = false;
    }
  }

  Future<void> _afterV9() async {
    await _loadV9();
    await _loadV8();
    _notify();
  }

  /// قوالب الطباعة (الترحيل 22)؛ دونها تعمل الطباعة بالقالب الافتراضي ولا يُحفظ قالب ولا يُرفع فيديو.
  Future<void> _loadV10() async {
    try {
      final r = await client.from('print_templates').select().order('name');
      printTemplates = r.map(PrintTemplate.fromMap).toList();
      v10Ready = true;
    } catch (_) {
      printTemplates = [];
      v10Ready = false;
    }
  }

  /// الصلاحيات الدقيقة وصيغ الأرقام الإشارية (الترحيل 23).
  Future<void> _loadV11() async {
    try {
      final r = await Future.wait<List<Map<String, dynamic>>>([
        client.from('user_grants').select('user_id, scope'),
        client.from('ref_schemes').select().order('key'),
      ]);
      final g = <String, Set<String>>{};
      for (final row in r[0]) {
        (g[row['user_id'].toString()] ??= <String>{}).add(row['scope'].toString());
      }
      grants = g;
      refSchemes = r[1].map(RefScheme.fromMap).toList()..sort((a, b) => a.system == b.system ? a.name.compareTo(b.name) : (a.system ? -1 : 1));
      v11Ready = true;
    } catch (_) {
      grants = {};
      refSchemes = [];
      v11Ready = false;
    }
  }

  /// المراسلات الداخلية (الترحيل 24).
  Future<void> _loadV12() async {
    try {
      await client.from('chat_rooms').select('id').limit(1);
      final first = !v12Ready;
      v12Ready = true;
      if (first) {
        chat.start();
      } else {
        unawaited(chat.refreshRooms());
      }
    } catch (_) {
      v12Ready = false;
    }
  }

  /// مركز الأمن السيبراني (الترحيل 25).
  Future<void> _loadV13() async {
    try {
      await client.from('security_incidents').select('id').limit(1);
      v13Ready = true;
    } catch (_) {
      v13Ready = false;
    }
  }

  /// لائحة الأسعار والمقايسات وبنود الجدول الزمني (الترحيلات 27–29)؛ يعمل التطبيق بدونها كما كان.
  Future<void> _loadV14() async {
    try {
      final r = await Future.wait<List<Map<String, dynamic>>>([
        client.from('price_lists').select().order('year', ascending: false),
        client.from('boq_sheets').select().order('updated_at', ascending: false),
        client.from('pm_items').select().order('sort'),
      ]);
      priceLists = r[0].map(PriceList.fromMap).toList();
      boqSheets = r[1].map(BoqSheet.fromMap).toList();
      pmItems = r[2].map(PmItem.fromMap).toList();
      v14Ready = true;
    } catch (_) {
      priceLists = [];
      boqSheets = [];
      pmItems = [];
      v14Ready = false;
    }
  }

  /// البرامج الزمنية ومراحلها (الترحيل 30)، ثم ترجمة التنفيذ إلى المخاطر وSWOT مرة في الجلسة (الترحيل 31).
  Future<void> _loadV15() async {
    if (!v14Ready) {
      pmPlans = {};
      pmPhases = [];
      v15Ready = false;
      return;
    }
    try {
      final r = await Future.wait<List<Map<String, dynamic>>>([
        client.from('pm_plans').select(),
        client.from('pm_phases').select().order('sort'),
      ]);
      pmPlans = {for (final p in r[0].map(PmPlan.fromMap)) p.projectId: p};
      pmPhases = r[1].map(PmPhase.fromMap).toList();
      v15Ready = true;
    } catch (_) {
      pmPlans = {};
      pmPhases = [];
      v15Ready = false;
    }
    if (v15Ready && !_autoRefreshed && role != null) {
      _autoRefreshed = true;
      try {
        await client.rpc('pm_refresh_auto');
        v16Ready = true;
      } catch (_) {
        v16Ready = false;
      }
    }
  }

  /// الأفكار بالقسم والصفحة (الترحيل 33): وجود العمود يكفي.
  Future<void> _loadV18() async {
    if (!v2Ready) {
      v18Ready = false;
      return;
    }
    try {
      await client.from('ideas').select('section').limit(1);
      v18Ready = true;
    } catch (_) {
      v18Ready = false;
    }
  }

  /// الترحيل 36: وجود عمود مصدر المقايسة يكفي.
  Future<void> _loadV20() async {
    if (!v14Ready) {
      v20Ready = false;
      return;
    }
    try {
      await client.from('boq_sheets').select('source').limit(1);
      v20Ready = true;
    } catch (_) {
      v20Ready = false;
    }
  }

  /// ملف العقد (الترحيل 35): وجود عمود المهندس المكلَّف في المستندات يكفي.
  Future<void> _loadV19() async {
    if (!v8Ready) {
      v19Ready = false;
      return;
    }
    try {
      await client.from('doc_items').select('engineer_id').limit(1);
      v19Ready = true;
    } catch (_) {
      v19Ready = false;
    }
  }

  /// سجل نسخ PDF المحفوظة (الترحيل 32): وجود الجدول يكفي لتفعيل رمز QR الذي يفتح النسخة الأصلية.
  Future<void> _loadV17() async {
    try {
      await client.from('export_files').select('token').limit(1);
      v17Ready = true;
    } catch (_) {
      v17Ready = false;
    }
  }

  // ---------------------------------------------------------------
  // لائحة الأسعار والمقايسات (الترحيلان 27 و28)
  // ---------------------------------------------------------------
  PriceList? get activePriceList {
    for (final l in priceLists) {
      if (l.active) return l;
    }
    return priceLists.firstOrNull;
  }

  PriceList? priceList(String id) {
    for (final l in priceLists) {
      if (l.id == id) return l;
    }
    return null;
  }

  static const _priceCols = 'list_id, seq, chapter, code, parent_seq, kind, description, unit, unit_inferred, price, section, grp, full_desc';

  /// بحث برقم البند (البند وما تحته) أو بكلمات من الوصف.
  Future<List<PriceItem>> searchPrices(String listId, String q, {String? chapter, int limit = 80}) async {
    final r = await client.rpc('price_search', params: {'p_list': listId, 'p_q': q, 'p_chapter': chapter, 'p_limit': limit});
    return [for (final m in (r as List? ?? const [])) PriceItem.fromMap(Map<String, dynamic>.from(m as Map))];
  }

  /// صفوف تحت عنوان (أو عناوين الفصل الأولى إن كان [parentSeq] فارغاً).
  Future<List<PriceItem>> browsePrices(String listId, String chapter, int? parentSeq) async {
    var q = client.from('price_items').select(_priceCols).eq('list_id', listId).eq('chapter', chapter);
    q = parentSeq == null ? q.isFilter('parent_seq', null) : q.eq('parent_seq', parentSeq);
    final r = await q.order('seq').limit(1000);
    return r.map(PriceItem.fromMap).toList();
  }

  Future<PriceItem?> priceItem(String listId, int seq) async {
    final r = await client.from('price_items').select(_priceCols).eq('list_id', listId).eq('seq', seq).maybeSingle();
    return r == null ? null : PriceItem.fromMap(r);
  }

  /// من يعدّ المقايسات (كصلاحية مقايسات الشؤون الفنية).
  bool canEditBoq(String? projectId) => v14Ready && canEditDoc('boq', projectId);

  /// رئيس الشؤون الفنية.
  bool get isTechnicalHead => role == AppRole.deptHead && me?.department == 'technical';

  /// اعتماد المقايسة وإعادة فتحها، واعتماد البرنامج الزمني وإعادة فتحه: رئيس الشؤون الفنية والمدير (الترحيل 30).
  bool get canApproveBoq => v15Ready && !frozenForMe && (isDirector || isTechnicalHead);
  bool get canApprovePlan => v15Ready && !frozenForMe && (isDirector || isTechnicalHead);

  /// إعداد البرنامج الزمني (البنود والمراحل والمدد والتوليد): الشؤون الفنية ومكتب المدير والمنح «pm:plan».
  bool get canPreparePlan =>
      v15Ready && !frozenForMe && (role == AppRole.director || role == AppRole.officeStaff || isTechnicalHead || hasGrant('pm:plan'));

  /// متابعة التنفيذ (الإنجاز والتواريخ الفعلية و«لا ينطبق»): القسم المشرف على العقد ومكتب المدير والمنح «pm:track».
  bool canTrackPlan(Project p) =>
      v15Ready &&
      !frozenForMe &&
      (role == AppRole.director ||
          role == AppRole.officeStaff ||
          (role == AppRole.deptHead && me?.department != null && me?.department == p.department) ||
          hasGrant('pm:track'));

  PmPlan? planOf(String projectId) => pmPlans[projectId];
  List<PmPhase> phasesOf(String projectId) => pmPhases.where((p) => p.projectId == projectId).toList()..sort((a, b) => a.sort.compareTo(b.sort));

  /// المقايسات المعتمدة للعقد (بنودها بنود العقد).
  List<BoqSheet> approvedBoqsOf(String projectId) => boqSheets.where((s) => s.projectId == projectId && s.approved).toList();

  Future<void> approveBoq(String id, bool approve) async {
    await client.rpc('approve_boq', params: {'p_id': id, 'p_approve': approve});
    await _afterV14();
  }

  Future<void> savePmPlan(String projectId, Map<String, dynamic> data) async {
    await client.rpc('save_pm_plan', params: {'p_project': projectId, 'p_data': data});
    await _afterV14();
  }

  Future<String> savePmPhase(String? id, Map<String, dynamic> data) async {
    final r = await client.rpc('save_pm_phase', params: {'p_id': id, 'p_data': data});
    await _afterV14();
    return r.toString();
  }

  Future<void> deletePmPhase(String id) async {
    await client.rpc('delete_pm_phase', params: {'p_id': id});
    await _afterV14();
  }

  /// معاينة البرنامج المبدئي من المقايسات المعتمدة: المراحل وبنودها بمددها المقترحة.
  Future<Map<String, dynamic>> planPreview(String projectId, int totalDays) async {
    final r = await client.rpc('pm_plan_preview', params: {'p_project': projectId, 'p_total_days': totalDays});
    return Map<String, dynamic>.from(r as Map);
  }

  Future<Map<String, dynamic>> planGenerate(String projectId, DateTime start, int totalDays, {bool replace = false}) async {
    final r = await client.rpc('pm_plan_generate',
        params: {'p_project': projectId, 'p_start': pmIso(start), 'p_total_days': totalDays, 'p_replace': replace});
    await _afterV14();
    return Map<String, dynamic>.from(r as Map);
  }

  Future<void> setPlanStatus(String projectId, String status) async {
    await client.rpc('pm_plan_set_status', params: {'p_project': projectId, 'p_status': status});
    await _afterV14();
    // الاعتماد وإعادة الفتح يترجمان إلى المخاطر وSWOT (الترحيل 31)
    await _loadV6();
    _notify();
  }

  /// حذف المقايسة: المدير، أو من أعدّها ما دامت له الصلاحية.
  bool canDeleteBoq(BoqSheet s) => v14Ready && (isDirector || (s.createdBy == me?.id && canEditBoq(s.projectId)));

  BoqSheet? boqSheet(String id) {
    for (final s in boqSheets) {
      if (s.id == id) return s;
    }
    return null;
  }

  /// نصوص صفحات PDF بمواضعها لاستيراد مقايسة (الدالة boq-extract). بوابة الخدمة تتحقق بالمفتاح العام،
  /// وهوية المستخدم وصلاحيته في إعداد المقايسات تتحقق منهما الدالة نفسها من رمز جلسته.
  Future<({List<List<PdfRun>> pages, int total, bool truncated})> extractBoqPdf(Uint8List bytes) async {
    final token = client.auth.currentSession?.accessToken;
    final anon = AppConfig.supabaseAnonKey;
    try {
      final res = await client.functions.invoke(
        'boq-extract',
        headers: {
          if (token != null) 'x-user-token': token,
          if (anon.startsWith('eyJ')) 'Authorization': 'Bearer $anon',
        },
        body: {'pdf': base64Encode(bytes)},
      );
      return parseExtractReply(res.data);
    } on FunctionException catch (e) {
      final d = e.details;
      if (d is Map && d['error'] is String) throw StateError(d['error'] as String);
      throw StateError(e.status == 404
          ? 'خدمة قراءة PDF غير منشورة بعد. صدّر المقايسة إلى Excel واستوردها.'
          : 'تعذّرت قراءة ملف PDF (${e.status}). صدّر المقايسة إلى Excel واستوردها.');
    }
  }

  Future<String> saveBoq(String? id, Map<String, dynamic> data) async {
    final r = await client.rpc('save_boq', params: {'p_id': id, 'p_data': data});
    await _loadV14();
    _notify();
    return r.toString();
  }

  /// حذف المقايسة؛ بعد الترحيل 33 تُحذف معها بنودها من البرنامج الزمني ومتابعة الإشراف (تعيد الأعداد).
  Future<({int items, int tracked, bool planRemoved})> deleteBoq(String id) async {
    final r = await client.rpc('delete_boq', params: {'p_id': id});
    await _afterV14();
    if (v16Ready) await _loadV6();
    _notify();
    int n(Object? v) => v is num ? v.toInt() : 0;
    return r is Map ? (items: n(r['items']), tracked: n(r['tracked']), planRemoved: n(r['plans']) > 0) : (items: 0, tracked: 0, planRemoved: false);
  }

  // ---------------------------------------------------------------
  // بنود الجدول الزمني (الترحيل 29)
  // ---------------------------------------------------------------
  ScheduleAnalysis get schedule =>
      _schedule ??= ScheduleAnalysis(projects: projects, items: pmItems, cfg: pmConfig, plans: pmPlans, phases: pmPhases);

  /// جدول عقد للإعداد أو المتابعة (بمسودته أيضاً).
  ScheduleTrack trackOf(Project p) =>
      schedule.track(p.id) ??
      ScheduleTrack(p, itemsOf(p.id), pmConfig.refDay, pmConfig, plan: planOf(p.id), phases: phasesOf(p.id));

  List<PmItem> itemsOf(String projectId) =>
      pmItems.where((i) => i.projectId == projectId).toList()..sort((a, b) => a.sort.compareTo(b.sort));

  /// بيانات البند: من يحدّث البرنامج الزمني. الإنجاز والتواريخ الفعلية: أيضاً من يحدّث سجل التقدم.
  /// بعد الترحيل 30: البنود للشؤون الفنية على المسودة، والإنجاز للإشراف على البرنامج المعتمد.
  bool canEditItems(Project p) => v15Ready ? canPreparePlan && planOf(p.id)?.approved != true : v14Ready && canEditSchedule(p);
  bool canUpdateItemProgress(Project p) =>
      v15Ready ? canTrackPlan(p) && planOf(p.id)?.approved == true : v14Ready && (canEditSchedule(p) || canEditPm);

  Future<void> _afterV14() async {
    await _loadV14();
    await _loadV15();
    _notify();
  }

  Future<void> savePmItem(String? id, Map<String, dynamic> data) async {
    await client.rpc('save_pm_item', params: {'p_id': id, 'p_data': data});
    await _afterV14();
    if (v16Ready) {
      await _loadV6();
      _notify();
    }
  }

  Future<void> deletePmItem(String id) async {
    await client.rpc('delete_pm_item', params: {'p_id': id});
    await _afterV14();
  }

  Future<void> reorderPmItems(String projectId, List<String> ids) async {
    await client.rpc('reorder_pm_items', params: {'p_project': projectId, 'p_ids': ids});
    await _afterV14();
  }

  Future<int> pmItemsFromWorks(String projectId) async {
    final n = await client.rpc('pm_items_from_works', params: {'p_project': projectId});
    await _afterV14();
    return (n as num?)?.toInt() ?? 0;
  }

  /// يسجّل النسبتين الكليتين المحسوبتين من البنود قياساً في «التقدم الدوري» بتاريخ الإسناد
  /// (ويحدّث قياس اليوم نفسه إن وُجد).
  Future<void> recordScheduleMeasurement(ScheduleTrack t) async {
    final day = t.ref;
    PmProgress? same;
    for (final m in measurements) {
      if (m.projectId == t.project.id && daysBetween(m.measuredOn, day) == 0) same = m;
    }
    await saveProgress(same?.id, {
      'project_id': t.project.id,
      'measured_on': pmIso(day),
      'planned': ((t.planned ?? 0) / 100 * 10000).round() / 10000,
      'actual': ((t.actual ?? 0) / 100 * 10000).round() / 10000,
      'works': same?.works.isNotEmpty == true ? same!.works : 'محسوبة من بنود الجدول الزمني (${t.items.length} بنداً)',
      'obstacles': same?.obstacles ?? '',
      'prepared_by': same?.preparedBy ?? '',
    });
  }

  RefScheme? refScheme(String key) {
    for (final s in refSchemes) {
      if (s.key == key) return s;
    }
    return null;
  }

  Future<void> setUserGrants(String userId, List<String> scopes) async {
    await client.rpc('set_user_grants', params: {'p_user': userId, 'p_scopes': scopes});
    await _loadV11();
    _notify();
  }

  Future<int> suspendGrants(String userId, String reason) async {
    final n = await client.rpc('sec_suspend_grants', params: {'p_user': userId, 'p_reason': reason});
    await _loadV11();
    _notify();
    return (n as num?)?.toInt() ?? 0;
  }

  Future<void> saveRefScheme(String key, Map<String, dynamic> data) async {
    await client.rpc('save_ref_scheme', params: {'p_key': key, 'p_data': data});
    await _loadV11();
    _notify();
  }

  Future<void> deleteRefScheme(String key) async {
    await client.rpc('delete_ref_scheme', params: {'p_key': key});
    await _loadV11();
    _notify();
  }

  Future<void> setRefCounter(String key, int next, {String? section}) async {
    await client.rpc('set_ref_counter', params: {'p_scheme': key, 'p_next': next, 'p_section': section});
  }

  /// يصدر رقماً إشارياً من قاعدة البيانات (لا يتكرر). null إن لم يُطبَّق الترحيل أو كانت الصيغة موقوفة.
  Future<String?> issueRef(String scheme, Map<String, String> ctx) async {
    if (!v11Ready) return null;
    final s = refScheme(scheme);
    if (s == null || !s.active) return null;
    try {
      final res = await client.rpc('next_ref', params: {'p_scheme': scheme, 'p_ctx': ctx});
      if (res is Map && res['ref'] != null) return res['ref'].toString();
    } catch (_) {}
    return null;
  }

  /// سجل أرقام وعدادات ثابتة للقطات البصرية (لا تُضبط في التطبيق).
  List<RefLogEntry>? debugRefLog;
  Map<String, int>? debugRefCounters;

  Future<List<RefLogEntry>> loadRefLog({String? scheme, int limit = 500}) async {
    if (!v11Ready) return const [];
    final d = debugRefLog;
    if (d != null) return [for (final e in d) if (scheme == null || scheme.isEmpty || e.scheme == scheme) e];
    var q = client.from('ref_log').select();
    if (scheme != null && scheme.isNotEmpty) q = q.eq('scheme', scheme);
    final res = await q.order('id', ascending: false).limit(limit);
    return res.map(RefLogEntry.fromMap).toList();
  }

  /// آخر رقم صدر لكل صيغة في فترتها الحالية (من العدادات).
  Future<Map<String, int>> loadRefCounters() async {
    if (!v11Ready) return const {};
    if (debugRefCounters != null) return debugRefCounters!;
    final res = await client.from('ref_counters').select();
    final out = <String, int>{};
    for (final r in res) {
      final k = '${r['scheme']}|${r['period']}';
      out[k] = (r['value'] as num?)?.toInt() ?? 0;
    }
    return out;
  }

  Future<void> saveLayout(UiLayout l) async {
    await setSetting('ui.layout', l.toJson());
  }

  /// القالب الافتراضي العام، أو null.
  PrintTemplate? get defaultPrintTemplate {
    for (final t in printTemplates) {
      if (t.isDefault) return t;
    }
    return null;
  }

  /// القوالب العامة يحفظها ويعدّلها المدير وموظفو مكتبه؛ والخاصة لكل مستخدم.
  bool get canShareTemplates => role == AppRole.director || role == AppRole.officeStaff;

  bool canEditTemplate(PrintTemplate t) => t.shared ? canShareTemplates && !frozenForMe : t.ownerId == me?.id;

  Future<String> savePrintTemplate(String? id, String name, PrintConfig config, {bool shared = false, bool isDefault = false}) async {
    final res = await client.rpc('save_print_template', params: {
      'p_id': id,
      'p_name': name,
      'p_config': config.toJson(),
      'p_shared': shared,
      'p_default': isDefault,
    });
    await _loadV10();
    _notify();
    return res.toString();
  }

  Future<void> deletePrintTemplate(String id) async {
    await client.rpc('delete_print_template', params: {'p_id': id});
    await _loadV10();
    _notify();
  }

  /// تسجيل ما استُخرج من المنظومة في التدقيق ([kind]: file أو print أو media). لا يوقف التصدير إن فشل.
  Future<void> logExport({required String kind, required String source, required String title, required String format, int rows = 0, int bytes = 0}) async {
    if (!v10Ready) return;
    try {
      await client.rpc('log_export', params: {
        'p_kind': kind,
        'p_source': source,
        'p_title': title,
        'p_format': format,
        'p_rows': rows,
        'p_bytes': bytes,
      });
    } catch (_) {}
  }

  void _clearV7() {
    schedules = {};
    measurements = [];
    riskReviews = [];
    pmIssues = [];
    pmDelays = [];
    pmChanges = [];
    pmLessons = [];
    pmEvaluations = [];
    v7Ready = false;
    _pm = null;
  }

  /// إعدادات الهوية قبل تسجيل الدخول.
  Future<void> loadPublicSettings() async {
    try {
      final res = await client.rpc('public_settings');
      if (res is Map) {
        publicSettings = Map<String, dynamic>.from(res);
        if (settings.raw.isEmpty) {
          motionSetting = normalizeMotion(publicSettings['ui.motion']);
          appearance = Appearance.fromJson(publicSettings['ui.appearance']);
        }
        _notify();
      }
    } catch (_) {
      // قاعدة بيانات الإصدار الأول: تبقى القيم الافتراضية
    }
  }

  void _subscribe() {
    final old = _channel;
    if (old != null) client.removeChannel(old);
    final ch = client.channel('dc-changes');
    for (final t in const ['projects', 'project_forms', 'change_requests', 'notifications', 'form_defs', 'app_releases']) {
      ch.onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: t,
        callback: (_) => scheduleReload(),
      );
    }
    ch.subscribe();
    _channel = ch;

    // قناة مستقلة لجداول الإصدار الثاني حتى لا تتأثر القناة الأساسية إن لم تكن موجودة
    final old2 = _channel2;
    if (old2 != null) client.removeChannel(old2);
    final ch2 = client.channel('dc-v2');
    for (final t in const ['app_settings', 'stages', 'custom_fields', 'ideas', 'departments']) {
      ch2.onPostgresChanges(event: PostgresChangeEvent.all, schema: 'public', table: t, callback: (_) => scheduleReload());
    }
    ch2.subscribe();
    _channel2 = ch2;

    // قناة الإصدار الثالث: أعمال العقود ومهندسوها
    final old3 = _channel3;
    if (old3 != null) client.removeChannel(old3);
    final ch3 = client.channel('dc-v3');
    for (final t in const ['contract_works', 'contract_engineers']) {
      ch3.onPostgresChanges(event: PostgresChangeEvent.all, schema: 'public', table: t, callback: (_) => scheduleReload());
    }
    ch3.subscribe();
    _channel3 = ch3;

    // قناة الإصدار الرابع: أوامر التغيير والمستخلصات
    final old4 = _channel4;
    if (old4 != null) client.removeChannel(old4);
    final ch4 = client.channel('dc-v4');
    for (final t in const ['contract_variations', 'contract_extracts']) {
      ch4.onPostgresChanges(event: PostgresChangeEvent.all, schema: 'public', table: t, callback: (_) => scheduleReload());
    }
    ch4.subscribe();
    _channel4 = ch4;

    // قناة الإصدار الخامس: دفعات المستخلصات
    final old5 = _channel5;
    if (old5 != null) client.removeChannel(old5);
    final ch5 = client.channel('dc-v5');
    ch5.onPostgresChanges(event: PostgresChangeEvent.all, schema: 'public', table: 'extract_payments', callback: (_) => scheduleReload());
    ch5.subscribe();
    _channel5 = ch5;

    // قناة الإصدار السادس: سجل المخاطر وتحليل SWOT
    final old6 = _channel6;
    if (old6 != null) client.removeChannel(old6);
    final ch6 = client.channel('dc-v6');
    for (final t in const ['risks', 'swot_factors', 'swot_strategies', 'swot_actions']) {
      ch6.onPostgresChanges(event: PostgresChangeEvent.all, schema: 'public', table: t, callback: (_) => scheduleReload());
    }
    ch6.subscribe();
    _channel6 = ch6;

    // قناة الإصدار السابع: متابعة المشاريع
    final old7 = _channel7;
    if (old7 != null) client.removeChannel(old7);
    final ch7 = client.channel('dc-v7');
    for (final t in const ['pm_projects', 'pm_progress', 'risk_reviews', 'pm_issues', 'pm_delays', 'pm_changes', 'pm_lessons', 'pm_evaluations']) {
      ch7.onPostgresChanges(event: PostgresChangeEvent.all, schema: 'public', table: t, callback: (_) => scheduleReload());
    }
    ch7.subscribe();
    _channel7 = ch7;

    // قناة الترحيل 20: المستندات الفنية والتقارير اليومية
    final old8 = _channel8;
    if (old8 != null) client.removeChannel(old8);
    final ch8 = client.channel('dc-v8');
    for (final t in const ['doc_items', 'doc_revisions', 'doc_files', 'site_reports']) {
      ch8.onPostgresChanges(event: PostgresChangeEvent.all, schema: 'public', table: t, callback: (_) => scheduleReload());
    }
    ch8.subscribe();
    _channel8 = ch8;

    // قناة الترحيل 21: سجلات الوحدات
    final old9 = _channel9;
    if (old9 != null) client.removeChannel(old9);
    final ch9 = client.channel('dc-v9');
    ch9.onPostgresChanges(event: PostgresChangeEvent.all, schema: 'public', table: 'unit_records', callback: (_) => scheduleReload());
    ch9.subscribe();
    _channel9 = ch9;

    // قناة الترحيلين 23 و25: الصلاحيات الدقيقة وصيغ الأرقام والحوادث الأمنية
    final old11 = _channel11;
    if (old11 != null) client.removeChannel(old11);
    final ch11 = client.channel('dc-v11');
    for (final t in const ['user_grants', 'ref_schemes', 'security_incidents']) {
      ch11.onPostgresChanges(event: PostgresChangeEvent.all, schema: 'public', table: t, callback: (_) => scheduleReload());
    }
    ch11.subscribe();
    _channel11 = ch11;

    // قناة الترحيلات 27–29: المقايسات وبنود الجدول الزمني
    final old14 = _channel14;
    if (old14 != null) client.removeChannel(old14);
    final ch14 = client.channel('dc-v14');
    for (final t in const ['boq_sheets', 'pm_items']) {
      ch14.onPostgresChanges(event: PostgresChangeEvent.all, schema: 'public', table: t, callback: (_) => scheduleReload());
    }
    ch14.subscribe();
    _channel14 = ch14;

    // قناة الترحيل 30: البرامج الزمنية ومراحلها (بعد التأكد من وجود الجدولين)
    final old15 = _channel15;
    if (old15 != null) client.removeChannel(old15);
    _channel15 = null;
    if (v15Ready) {
      final ch15 = client.channel('dc-v15');
      for (final t in const ['pm_plans', 'pm_phases']) {
        ch15.onPostgresChanges(event: PostgresChangeEvent.all, schema: 'public', table: t, callback: (_) => scheduleReload());
      }
      ch15.subscribe();
      _channel15 = ch15;
    }
  }

  void scheduleReload() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 450), () {
      if (!_disposed) loadAll();
    });
  }

  void reset() {
    final old = _channel;
    if (old != null) client.removeChannel(old);
    _channel = null;
    final old2 = _channel2;
    if (old2 != null) client.removeChannel(old2);
    _channel2 = null;
    final old3 = _channel3;
    if (old3 != null) client.removeChannel(old3);
    _channel3 = null;
    final old4 = _channel4;
    if (old4 != null) client.removeChannel(old4);
    _channel4 = null;
    final old5 = _channel5;
    if (old5 != null) client.removeChannel(old5);
    _channel5 = null;
    payments = [];
    _payBy = {};
    v5Ready = false;
    final old6 = _channel6;
    if (old6 != null) client.removeChannel(old6);
    _channel6 = null;
    final old7 = _channel7;
    if (old7 != null) client.removeChannel(old7);
    _channel7 = null;
    final old8 = _channel8;
    if (old8 != null) client.removeChannel(old8);
    _channel8 = null;
    docs = DocIndex.empty();
    v8Ready = false;
    final old9 = _channel9;
    if (old9 != null) client.removeChannel(old9);
    _channel9 = null;
    units = UnitIndex.empty();
    v9Ready = false;
    printTemplates = [];
    v10Ready = false;
    final old11 = _channel11;
    if (old11 != null) client.removeChannel(old11);
    _channel11 = null;
    grants = {};
    refSchemes = [];
    v11Ready = false;
    chat.stop();
    v12Ready = false;
    v13Ready = false;
    priceLists = [];
    boqSheets = [];
    pmItems = [];
    priceResults = [];
    v14Ready = false;
    final old14 = _channel14;
    if (old14 != null) client.removeChannel(old14);
    _channel14 = null;
    final old15 = _channel15;
    if (old15 != null) client.removeChannel(old15);
    _channel15 = null;
    pmPlans = {};
    pmPhases = [];
    v15Ready = false;
    v16Ready = false;
    _autoRefreshed = false;
    v17Ready = false;
    v18Ready = false;
    v19Ready = false;
    v20Ready = false;
    scope = null;
    hubEditRequested = false;
    formDates = {};
    signedUrls.clear();
    _clearV7();
    risks = [];
    swotFactors = [];
    swotStrategies = [];
    swotActions = [];
    v6Ready = false;
    showHub = true;
    _lastTab
      ..['cycle'] = 0
      ..['risks'] = 20
      ..['swot'] = 30
      ..['docs'] = 60
      ..['supervision'] = 70
      ..['manual'] = 80
      ..['heritage'] = 90
      ..['planning_qa'] = 100
      ..['safety'] = 110
      ..['acceptance'] = 120
      ..['print'] = 130
      ..['chat'] = 140
      ..['security'] = 150;
    _heartbeat?.cancel();
    _appearancePreview = null;
    variations = [];
    extracts = [];
    _varBy = {};
    _extBy = {};
    v4Ready = false;
    settings = LiveSettings.empty();
    stages = [];
    allFormDefs = [];
    customFields = [];
    ideas = [];
    works = [];
    engineers = [];
    _worksBy = {};
    _engBy = {};
    v3Ready = false;
    assistantMessages.clear();
    _debounce?.cancel();
    _updateTimer?.cancel();
    me = null;
    departments = [];
    formDefs = [];
    projects = [];
    statuses = {};
    requests = [];
    people = {};
    notifications = [];
    loadedOnce = false;
    loadError = null;
    _tab = 0;
    _section = 'cycle';
    _progressCache.clear();
    _notify();
  }

  void _notify() {
    _pm = null;
    _schedule = null;
    if (!_disposed) notifyListeners();
  }

  /// تغيّرت المراسلات (غير المقروء وآخر رسالة): يحدّث الشارات دون إعادة حساب التحليلات.
  void chatChanged() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _debounce?.cancel();
    _updateTimer?.cancel();
    final old = _channel;
    if (old != null) client.removeChannel(old);
    final old2 = _channel2;
    if (old2 != null) client.removeChannel(old2);
    final old3 = _channel3;
    if (old3 != null) client.removeChannel(old3);
    final old4 = _channel4;
    if (old4 != null) client.removeChannel(old4);
    final old5 = _channel5;
    if (old5 != null) client.removeChannel(old5);
    final old6 = _channel6;
    if (old6 != null) client.removeChannel(old6);
    final old7 = _channel7;
    if (old7 != null) client.removeChannel(old7);
    final old8 = _channel8;
    if (old8 != null) client.removeChannel(old8);
    final old9 = _channel9;
    if (old9 != null) client.removeChannel(old9);
    final old11 = _channel11;
    if (old11 != null) client.removeChannel(old11);
    final old14 = _channel14;
    if (old14 != null) client.removeChannel(old14);
    final old15 = _channel15;
    if (old15 != null) client.removeChannel(old15);
    chat.dispose();
    _heartbeat?.cancel();
    super.dispose();
  }

  // ---------------------------------------------------------------
  // التنقل والتصفية
  // ---------------------------------------------------------------
  void setTab(int i) {
    tab = i;
    showHub = false;
    _lastTab[_section] = i;
    _notify();
  }

  /// تثبيت الصفحة المعروضة فعلاً في القسم الحالي (حين لا تكون الصفحة المطلوبة فيه)، دون تغيير القسم.
  void settleTab(int i) {
    if (_tab == i) return;
    _tab = i;
    _lastTab[_section] = i;
  }

  /// أقسام صفحات «الأفكار والتطوير» في كل قسم بترتيب أرقامها (171–182)؛ الدورة المستندية صفحتها 4.
  static const List<String> ideasSections = [
    'risks', 'swot', 'docs', 'supervision', 'heritage', 'planning_qa', 'safety', 'acceptance', 'chat', 'security', 'print', 'manual', //
  ];

  /// رقم صفحة «الأفكار والتطوير» في قسم.
  static int ideasTabOf(String section) {
    final i = ideasSections.indexOf(section);
    return i < 0 ? 4 : 171 + i;
  }

  /// أقسام صفحة «المهام المسندة» بترتيب أرقامها (183–188): النماذج المسندة من الدورة وإجراءات SWOT لقسم المستخدم.
  static const List<String> assignedSections = ['docs', 'supervision', 'heritage', 'planning_qa', 'safety', 'acceptance'];

  /// رقم صفحة «المهام المسندة» في قسم (أو -1 إن لم تكن له).
  static int assignedTabOf(String section) {
    final i = assignedSections.indexOf(section);
    return i < 0 ? -1 : 183 + i;
  }

  /// قسم الصفحة بعد تخصيص المدير: المنقولة إلى قسم آخر تُفتح فيه، وإلا فقسمها الأصلي.
  String sectionForTab(int t) {
    final home = sectionOf(t);
    if (home == 'security') return home;
    final moved = layout.pages[t]?.section ?? '';
    return moved.isNotEmpty && moved != 'security' && _lastTab.containsKey(moved) ? moved : home;
  }

  /// القسم الرئيسي من رقم الصفحة: الدورة المستندية (0–19)، المخاطر ومتابعة المشاريع (20–29 و40–59)، SWOT (30–39)،
  /// الشؤون الفنية (60–69)، الإشراف (70–79)، دليل الاستخدام (80–89)، الترميم والمباني التاريخية (90–99)،
  /// مكتب التخطيط وضمان الجودة (100–109)، مكتب السلامة المهنية (110–119)، المطابقة والاستلام (120–129)،
  /// الطباعة والتصدير (130–139)، المراسلات الداخلية (140–149)، الأمن السيبراني (150–169).
  static String sectionOf(int t) => switch (t) {
        >= 171 && <= 182 => ideasSections[t - 171],
        >= 183 && <= 188 => assignedSections[t - 183],
        >= 150 && < 170 => 'security',
        >= 140 && < 150 => 'chat',
        >= 130 && < 140 => 'print',
        >= 120 && < 130 => 'acceptance',
        >= 110 && < 120 => 'safety',
        >= 100 && < 110 => 'planning_qa',
        >= 90 && < 100 => 'heritage',
        >= 80 && < 90 => 'manual',
        >= 70 && < 80 => 'supervision',
        >= 60 && < 70 => 'docs',
        >= 40 && < 60 => 'risks',
        >= 30 && < 40 => 'swot',
        >= 20 && < 30 => 'risks',
        _ => 'cycle',
      };
  final Map<String, int> _lastTab = {
    'cycle': 0,
    'risks': 20,
    'swot': 30,
    'docs': 60,
    'supervision': 72,
    'manual': 80,
    'heritage': 90,
    'planning_qa': 100,
    'safety': 110,
    'acceptance': 120,
    'print': 130,
    'chat': 140,
    'security': 150,
  };

  /// فتح قسم رئيسي على آخر صفحة زارها المستخدم فيه.
  void openSection(String s) {
    var t = _lastTab[s] ?? 0;
    // لوحة الإشراف (الترحيل 30) واجهة القسم؛ قبل الترحيل تبقى التقارير اليومية
    if (t == 72 && !v15Ready) t = 70;
    _section = s;
    // صفحة نقلها المدير إلى قسم آخر: يعرض القسم أول صفحاته ويثبّتها الهيكل
    _tab = sectionForTab(t) == s ? t : -1;
    showHub = false;
    _notify();
  }

  void openHub({bool edit = false}) {
    showHub = true;
    if (edit) hubEditRequested = true;
    _notify();
  }

  void setScope({String? owner, String? company}) {
    if (owner != null) ownerFilter = owner;
    if (company != null) companyFilter = company;
    _notify();
  }

  /// طلب فتح المالية على عرض وحالة مستخلص محددين (تستهلكه صفحة المالية مرة واحدة).
  ({String view, String? status, int seq})? financeRequest;
  int _financeSeq = 0;

  void openFinance({String view = 'summary', String? status}) {
    financeRequest = (view: view, status: status, seq: ++_financeSeq);
    setTab(7);
  }

  /// فتح صفحة من «المستندات الفنية» أو «الإشراف» مصفّاة على عقد (تستهلكه الصفحة مرة واحدة).
  String? _docsProject;

  void openDocsTab(int tab, {String? projectId}) {
    _docsProject = projectId;
    setTab(tab);
  }

  String? takeDocsProject() {
    final p = _docsProject;
    _docsProject = null;
    return p;
  }

  /// فتح دليل الاستخدام على فصل محدد (يستهلكه الدليل مرة واحدة).
  String? manualAnchor;

  void openManual([String? anchor]) {
    manualAnchor = anchor;
    setTab(80);
  }

  void openProjects({CycleState? cycle, int? stage, String? form, bool nextOnly = false}) {
    search = '';
    cycleFilter = cycle;
    stageFilter = stage;
    formFilter = form;
    formFilterNextOnly = nextOnly;
    setTab(1);
  }

  void setProjectFilters({String? search, CycleState? cycle, bool clearCycle = false, int? stage, bool clearStage = false, String? sort, bool clearForm = false}) {
    if (search != null) this.search = search;
    if (cycle != null || clearCycle) cycleFilter = cycle;
    if (stage != null || clearStage) stageFilter = stage;
    if (sort != null) this.sort = sort;
    if (clearForm) formFilter = null;
    _notify();
  }

  List<Project> filteredProjects() {
    final q = normalizeArabic(search);
    final list = projects.where((p) {
      final pr = progressOf(p);
      if (cycleFilter != null && pr.cycle != cycleFilter) return false;
      if (stageFilter != null && pr.stage != stageFilter) return false;
      if (formFilter != null) {
        if (formFilterNextOnly) {
          if (pr.next?.key != formFilter) return false;
        } else {
          final s = statusOf(p.id, formFilter!);
          if (s == FormStatus.done || s == FormStatus.na) return false;
        }
      }
      if (q.isNotEmpty) {
        final hay = normalizeArabic([
          p.contractNo,
          p.assignNo,
          p.code,
          p.name,
          p.owner,
          p.company,
          p.notes,
          ...p.engineers.values,
          for (final w in worksOf(p.id)) '${w.title} ${w.company} ${w.refNo}',
          for (final e in engineersOf(p.id)) '${e.name} ${e.assignNo}',
        ].join(' '));
        if (!hay.contains(q)) return false;
      }
      return true;
    }).toList();
    switch (sort) {
      case 'contract':
        list.sort((a, b) {
          if (a.contractNo.isEmpty != b.contractNo.isEmpty) return a.contractNo.isEmpty ? 1 : -1;
          return _naturalCompare(a.contractNo, b.contractNo);
        });
      case 'low':
        list.sort((a, b) => progressOf(a).pct.compareTo(progressOf(b).pct));
      case 'high':
        list.sort((a, b) => progressOf(b).pct.compareTo(progressOf(a).pct));
      case 'recent':
        list.sort((a, b) => (b.updatedAt ?? DateTime(2000)).compareTo(a.updatedAt ?? DateTime(2000)));
      default:
        list.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    }
    return list;
  }

  // ---------------------------------------------------------------
  // العمليات
  // ---------------------------------------------------------------

  /// يُرجع applied أو pending أو unchanged.
  Future<String> setFormStatus(String projectId, String formKey, FormStatus status, {String note = ''}) async {
    final res = await client.rpc('set_form_status', params: {
      'p_project': projectId,
      'p_form': formKey,
      'p_status': status.db,
      'p_note': note,
    });
    await loadAll();
    return res?.toString() ?? 'applied';
  }

  Future<void> decideRequest(String requestId, bool approve, {String note = ''}) async {
    await client.rpc('decide_request', params: {'p_request': requestId, 'p_approve': approve, 'p_note': note});
    await loadAll();
  }

  Future<void> withdrawRequest(String requestId) async {
    await client.rpc('withdraw_request', params: {'p_request': requestId});
    await loadAll();
  }

  Future<void> setEngineer(String projectId, String formKey, String name) async {
    await client.rpc('set_engineer', params: {'p_project': projectId, 'p_form': formKey, 'p_name': name});
    await loadAll();
  }

  Future<void> setContractFinance(
    String projectId, {
    required double? contractValue,
    double? executedValue,
    required double? paymentFirst,
    required double? paymentSecond,
    required double? paymentFinal,
    required double? deductions,
  }) async {
    await client.rpc('set_contract_finance', params: {
      'p_project': projectId,
      'p_contract_value': contractValue,
      // قاعدة الإصدار الثالث: الضمانات من قيمة الأعمال المنفذة
      if (v3Ready) 'p_executed_value': executedValue,
      'p_payment_first': paymentFirst,
      'p_payment_second': paymentSecond,
      'p_payment_final': paymentFinal,
      'p_deductions': deductions,
    });
    await loadAll();
  }

  /// الضمان الابتدائي لا ينطبق على العقد (أو ينطبق فيُحسب من قيمة الأعمال المنفذة).
  Future<void> setGuaranteeInitialNa(String projectId, bool na) async {
    await client.rpc('set_guarantee_initial_na', params: {'p_project': projectId, 'p_na': na});
    await loadAll();
  }

  // ---------------------------------------------------------------
  // العقود: رقم العقد والأعمال والمهندسون والدمج
  // ---------------------------------------------------------------
  Future<void> setContractNo(String projectId, String no) async {
    await client.rpc('set_contract_no', params: {'p_project': projectId, 'p_no': no.trim()});
    await loadAll();
  }

  Future<String> saveWork({
    String? id,
    required String projectId,
    required String title,
    required String company,
    required String refNo,
    required String notes,
  }) async {
    final res = await client.rpc('save_work', params: {
      'p_id': id,
      'p_project': projectId,
      'p_title': title.trim(),
      'p_company': company.trim(),
      'p_ref_no': refNo.trim(),
      'p_notes': notes.trim(),
    });
    await loadAll();
    return res?.toString() ?? '';
  }

  Future<void> deleteWork(String id) async {
    await client.rpc('delete_work', params: {'p_id': id});
    await loadAll();
  }

  Future<String> saveEngineer({
    String? id,
    required String projectId,
    required String kind,
    required String name,
    required String assignNo,
    DateTime? assignedOn,
    String? workId,
    String notes = '',
  }) async {
    final res = await client.rpc('save_engineer', params: {
      'p_id': id,
      'p_project': projectId,
      'p_kind': kind,
      'p_name': name.trim(),
      'p_assign_no': assignNo.trim(),
      'p_assigned_on': assignedOn == null ? null : dbDate(assignedOn),
      'p_work': workId,
      'p_notes': notes.trim(),
    });
    await loadAll();
    return res?.toString() ?? '';
  }

  Future<void> deleteEngineer(String id) async {
    await client.rpc('delete_engineer', params: {'p_id': id});
    await loadAll();
  }

  /// يدمج أعمالاً (عقوداً) في عقد واحد؛ يُرجع عدد ما دُمج.
  Future<int> mergeContracts(String targetId, List<String> sourceIds) async {
    final res = await client.rpc('merge_contracts', params: {'p_target': targetId, 'p_sources': sourceIds});
    await loadAll();
    return (res as num?)?.toInt() ?? 0;
  }

  Future<void> unmergeContract(String sourceId) async {
    await client.rpc('unmerge_contract', params: {'p_source': sourceId});
    await loadAll();
  }

  /// الأعمال (السجلات الأصلية) المدمجة في عقد.
  Future<List<Map<String, dynamic>>> mergedSources(String targetId) async {
    if (!v3Ready) return const [];
    final res = await client.rpc('merged_sources', params: {'p_target': targetId});
    return res is List ? res.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList() : const [];
  }

  // ---------------------------------------------------------------
  // المالية الموسعة: قيم البنود، وأوامر التغيير، والمستخلصات
  // ---------------------------------------------------------------
  Future<void> setWorkValues(String workId, {double? contractValue, double? executedValue}) async {
    await client.rpc('set_work_values', params: {
      'p_work': workId,
      'p_contract_value': contractValue,
      'p_executed_value': executedValue,
    });
    await loadAll();
  }

  Future<String> saveVariation({
    String? id,
    required String projectId,
    String? workId,
    required String refNo,
    required String title,
    required String kind,
    required double amount,
    DateTime? approvedOn,
    String notes = '',
  }) async {
    final res = await client.rpc('save_variation', params: {
      'p_id': id,
      'p_project': projectId,
      'p_work': workId,
      'p_ref_no': refNo.trim(),
      'p_title': title.trim(),
      'p_kind': kind,
      'p_amount': amount,
      'p_approved_on': approvedOn == null ? null : dbDate(approvedOn),
      'p_notes': notes.trim(),
    });
    await loadAll();
    return res?.toString() ?? '';
  }

  Future<void> deleteVariation(String id) async {
    await client.rpc('delete_variation', params: {'p_id': id});
    await loadAll();
  }

  Future<String> saveExtract({
    String? id,
    required String projectId,
    String? workId,
    required String refNo,
    required String kind,
    DateTime? periodFrom,
    DateTime? periodTo,
    DateTime? submittedOn,
    required double gross,
    double retention = 0,
    double advance = 0,
    double penalties = 0,
    double taxes = 0,
    double other = 0,
    required String status,
    DateTime? approvedOn,
    double paidAmount = 0,
    DateTime? paidOn,
    String notes = '',
    DateTime? referredOn,
    String referralNo = '',
    Map<String, double> custom = const {},
  }) async {
    String? d(DateTime? v) => v == null ? null : dbDate(v);
    final res = await client.rpc('save_extract', params: {
      // الصيغة الموسعة (الإحالة للصرف والاستقطاعات المخصصة) عند توفر قاعدة الإصدار الخامس
      if (v5Ready) ...{
        'p_referred_on': d(referredOn),
        'p_referral_no': referralNo.trim(),
        'p_custom': {for (final e in custom.entries) if (e.value > 0) e.key: e.value},
      },
      'p_id': id,
      'p_project': projectId,
      'p_work': workId,
      'p_ref_no': refNo.trim(),
      'p_kind': kind,
      'p_period_from': d(periodFrom),
      'p_period_to': d(periodTo),
      'p_submitted_on': d(submittedOn),
      'p_gross': gross,
      'p_retention': retention,
      'p_advance': advance,
      'p_penalties': penalties,
      'p_taxes': taxes,
      'p_other': other,
      'p_status': status,
      'p_approved_on': d(approvedOn),
      'p_paid_amount': paidAmount,
      'p_paid_on': d(paidOn),
      'p_notes': notes.trim(),
    });
    await loadAll();
    return res?.toString() ?? '';
  }

  Future<void> deleteExtract(String id) async {
    await client.rpc('delete_extract', params: {'p_id': id});
    await loadAll();
  }

  Future<void> addExtractPayment(String extractId,
      {required double amount, DateTime? paidOn, String method = 'transfer', String refNo = '', String notes = ''}) async {
    await client.rpc('add_extract_payment', params: {
      'p_extract': extractId,
      'p_amount': amount,
      'p_paid_on': paidOn == null ? null : dbDate(paidOn),
      'p_method': method,
      'p_ref_no': refNo.trim(),
      'p_notes': notes.trim(),
    });
    await loadAll();
  }

  // ---------------------------------------------------------------
  // سجل المخاطر وتحليل SWOT
  // ---------------------------------------------------------------
  RiskConfig get riskConfig => RiskConfig.fromJson(settings.raw['risk.config']);
  SwotMeta get swotMeta => SwotMeta(settings.map('swot.meta'));
  SwotAnalysis get swot => SwotAnalysis(swotFactors, swotStrategies, swotActions);

  /// كل عضو عدا CISO يحرر سجل المخاطر؛ الحذف للمدير.
  bool get canEditRisks => v6Ready && role != null && role != AppRole.securityAuditor && !frozenForMe;

  /// تحليل SWOT يحرره المدير وفريق مكتبه، ومن مُنح صلاحية SWOT.
  bool get canEditSwot =>
      v6Ready && (role == AppRole.director || role == AppRole.officeStaff || hasGrant('swot')) && !frozenForMe;

  /// تحديث تقدم إجراء: محررو SWOT ورئيس القسم المسؤول.
  bool canUpdateSwotAction(String department) {
    if (canEditSwot) return true;
    if (!v6Ready || role != AppRole.deptHead || frozenForMe) return false;
    final dn = departmentName(me?.department);
    return department == 'جميع الأقسام' || department == 'قسم $dn' || department == dn;
  }

  Risk? riskById(String id) {
    for (final r in risks) {
      if (r.id == id) return r;
    }
    return null;
  }

  Future<void> _afterV6() async {
    await _loadV6();
    _notify();
  }

  Future<String?> saveRisk(String? id, Map<String, dynamic> data) async {
    final res = await client.rpc('save_risk', params: {'p_id': id, 'p_data': data});
    await _afterV6();
    return res?.toString();
  }

  Future<void> deleteRisk(String id) async {
    await client.rpc('delete_risk', params: {'p_id': id});
    await _afterV6();
  }

  Future<void> saveSwotFactor(String? id, Map<String, dynamic> data) async {
    await client.rpc('save_swot_factor', params: {'p_id': id, 'p_data': data});
    await _afterV6();
  }

  Future<void> deleteSwotFactor(String id) async {
    await client.rpc('delete_swot_factor', params: {'p_id': id});
    await _afterV6();
  }

  Future<void> saveSwotStrategy(String? id, Map<String, dynamic> data) async {
    await client.rpc('save_swot_strategy', params: {'p_id': id, 'p_data': data});
    await _afterV6();
  }

  Future<void> deleteSwotStrategy(String id) async {
    await client.rpc('delete_swot_strategy', params: {'p_id': id});
    await _afterV6();
  }

  Future<void> saveSwotAction(String? id, Map<String, dynamic> data) async {
    await client.rpc('save_swot_action', params: {'p_id': id, 'p_data': data});
    await _afterV6();
  }

  Future<void> deleteSwotAction(String id) async {
    await client.rpc('delete_swot_action', params: {'p_id': id});
    await _afterV6();
  }

  /// المتابعة الدورية للإجراء: البدء والمدة والحالة والإنجاز والملاحظات.
  Future<void> updateSwotAction(String id,
      {DateTime? start, int? months, required String status, double? progress, String notes = ''}) async {
    await client.rpc('update_swot_action', params: {
      'p_id': id,
      'p_start': start == null ? null : isoDay(start),
      'p_duration': months,
      'p_status': status,
      'p_progress': progress,
      'p_notes': notes,
    });
    await _afterV6();
  }

  // ---------------------------------------------------------------
  // المخاطر ومتابعة المشاريع (الإصدار السابع)
  // ---------------------------------------------------------------
  PmConfig get pmConfig => PmConfig.fromJson(settings.raw['pm.config']);

  /// التحليل الشامل (سجل المشاريع، الوضع الحالي للمخاطر، مؤشرات الشركات، التنبيهات)؛ يُعاد بناؤه عند تغيّر البيانات.
  PmAnalysis get pm => _pm ??= PmAnalysis(
        projects: projects,
        schedules: schedules,
        progress: measurements,
        risks: risks,
        reviews: riskReviews,
        issues: pmIssues,
        delays: pmDelays,
        changes: pmChanges,
        lessons: pmLessons,
        evaluations: pmEvaluations,
        riskCfg: riskConfig,
        cfg: pmConfig,
      );

  RiskState riskState(Risk r) => pm.riskStates[r.id] ?? RiskState.of(r, const [], riskConfig, pmConfig.refDay, riskConfig.alertDays);

  /// سجلات المتابعة (التقدم، المشاكل، التأخيرات، التغييرات، الدروس، التقييمات): كل عضو عدا CISO.
  bool get canEditPm => v7Ready && role != null && role != AppRole.securityAuditor && !frozenForMe;

  /// البرنامج الزمني: المدير وموظفو مكتبه ومكتب العقود ورئيس القسم المشرف على العقد.
  bool canEditSchedule(Project p) {
    if (!v7Ready || frozenForMe) return false;
    final r = role;
    if (r == AppRole.director || r == AppRole.officeStaff || r == AppRole.contracts) return true;
    return r == AppRole.deptHead && me?.department != null && me?.department == p.department;
  }

  /// البت في طلبات التغيير: من يختص بمالية العقد والمدير.
  bool canDecideChange(Project? p) => v7Ready && (isDirector || (p != null && canEditFinance(p) && !frozenForMe));

  /// اعتماد الدروس المستفادة: المدير وموظفو مكتبه.
  bool get canApproveLessons => v7Ready && (role == AppRole.director || role == AppRole.officeStaff) && !frozenForMe;

  /// طلب التغيير الذي أنشأ أمر التغيير هذا في المالية (إن وُجد).
  PmChange? changeOfVariation(String variationId) {
    for (final c in pmChanges) {
      if (c.variationId == variationId) return c;
    }
    return null;
  }

  List<RiskReview> reviewsOf(String riskId) => riskReviews.where((v) => v.riskId == riskId).toList();

  Future<void> _afterV7({bool finance = false}) async {
    if (finance) {
      await loadAll();
      return;
    }
    await _loadV6();
    await _loadV7();
    _notify();
  }

  Future<void> saveSchedule(String projectId, Map<String, dynamic> data) async {
    await client.rpc('save_project_schedule', params: {'p_project': projectId, 'p_data': data});
    await _afterV7();
  }

  Future<void> saveProgress(String? id, Map<String, dynamic> data) async {
    await client.rpc('save_pm_progress', params: {'p_id': id, 'p_data': data});
    await _afterV7();
  }

  Future<void> deleteProgress(String id) async {
    await client.rpc('delete_pm_progress', params: {'p_id': id});
    await _afterV7();
  }

  Future<void> saveRiskReview(String? id, String riskId, Map<String, dynamic> data) async {
    await client.rpc('save_risk_review', params: {'p_id': id, 'p_risk': riskId, 'p_data': data});
    await _afterV7();
  }

  Future<void> deleteRiskReview(String id) async {
    await client.rpc('delete_risk_review', params: {'p_id': id});
    await _afterV7();
  }

  /// حفظ سجل متابعة: issue | delay | change | lesson | evaluation.
  Future<void> savePmRecord(String kind, String? id, Map<String, dynamic> data) async {
    final fn = switch (kind) {
      'issue' => 'save_pm_issue',
      'delay' => 'save_pm_delay',
      'change' => 'save_pm_change',
      'lesson' => 'save_pm_lesson',
      _ => 'save_pm_evaluation',
    };
    await client.rpc(fn, params: {'p_id': id, 'p_data': data});
    await _afterV7(finance: kind == 'change');
  }

  Future<void> deletePmRecord(String kind, String id) async {
    await client.rpc('delete_pm_record', params: {'p_kind': kind, 'p_id': id});
    await _afterV7(finance: kind == 'change');
  }

  // ---------------------------------------------------------------
  // المستندات الفنية والتقارير اليومية (الترحيل 20)
  // ---------------------------------------------------------------
  /// هل يملك المستخدم إضافة/تعديل هذا النوع من المستندات لهذا العقد؟ (للعرض فقط؛ القاعدة تتحقق)
  bool canEditDoc(String kind, String? projectId) {
    final r = role;
    if (!v8Ready || r == null || r == AppRole.securityAuditor) return false;
    if (kind == 'attachment') return canEditContractFiles(projectId);
    if (r == AppRole.director) return true;
    if (frozenForMe) return false;
    final dep = me?.department;
    final p = projectId == null || projectId.isEmpty ? null : project(projectId);
    if (hasGrant('docs:$kind')) return true;
    return switch (kind) {
      'boq' => r == AppRole.officeStaff || r == AppRole.contracts || (r == AppRole.deptHead && (dep == 'technical' || dep == 'acceptance')),
      'letter' => r != AppRole.securityAuditor,
      'design' => r == AppRole.officeStaff ||
          (r == AppRole.deptHead && (dep == 'technical' || dep == 'restoration' || (p != null && p.department == dep))),
      _ => false,
    };
  }

  /// ملف العقد (الترحيل 35): يراه من يرى العقد بتفاصيله — مكتب المدير ومكتب العقود والقسم المشرف عليه.
  /// يطابق doc_items_read في قاعدة البيانات؛ ولا تراه الشؤون الفنية ولا الأقسام الأخرى ولا مدقق الأمن.
  bool seesContractFiles(String projectId) {
    final r = role;
    if (!v19Ready || r == null || r == AppRole.securityAuditor) return false;
    final sc = scope;
    if (sc != null) return sc.allProjects || sc.supervised.contains(projectId);
    return r == AppRole.director ||
        r == AppRole.officeStaff ||
        r == AppRole.contracts ||
        (r == AppRole.deptHead && project(projectId)?.department == me?.department);
  }

  /// الإضافة إلى ملف العقد واستبدال ملفاته: من يراه، ما لم تُجمَّد الكتابة (المدير مستثنى). الحذف للمدير وحده.
  bool canEditContractFiles(String? projectId) =>
      projectId != null && projectId.isNotEmpty && seesContractFiles(projectId) && (isDirector || !frozenForMe);

  /// هل يملك إضافة هذا النوع لأي عقد أو بشكل عام؟ (لإظهار زر الإضافة)
  bool canAddDoc(String kind) =>
      canEditDoc(kind, null) || (kind == 'design' && role == AppRole.deptHead && projects.any((p) => canEditDoc(kind, p.id)));

  /// التقرير اليومي: المدير، وموظفو مكتب المدير، ورئيس القسم المشرف على العقد.
  bool canEditReport(String projectId) {
    final r = role;
    if (!v8Ready || r == null) return false;
    if (r == AppRole.director) return true;
    if (frozenForMe) return false;
    if (r == AppRole.officeStaff || hasGrant('supervision:reports')) return true;
    final p = project(projectId);
    return r == AppRole.deptHead && p != null && p.department == me?.department;
  }

  bool get canAddReport => projects.any((p) => canEditReport(p.id));

  /// حذف إصدار أو ملف أو تقرير: المدير، أو صاحبه خلال 24 ساعة.
  bool canRemoveOwn(String? createdBy, DateTime? createdAt) =>
      isDirector ||
      (!frozenForMe &&
          createdBy != null &&
          createdBy == me?.id &&
          createdAt != null &&
          DateTime.now().difference(createdAt) < const Duration(hours: 23, minutes: 50));

  /// حفظ مستند؛ يعيد (معرّف المستند، معرّف أحدث إصدار).
  Future<(String, String?)> saveDocItem(String? id, Map<String, dynamic> data) async {
    final res = await client.rpc('save_doc_item', params: {'p_id': id, 'p_data': data});
    await _afterV8();
    final m = res is Map ? res : const {};
    return (m['item_id'].toString(), m['revision_id']?.toString());
  }

  Future<String> saveDocRevision(String? id, String itemId, Map<String, dynamic> data) async {
    final res = await client.rpc('save_doc_revision', params: {'p_id': id, 'p_item': itemId, 'p_data': data});
    await _afterV8();
    return res.toString();
  }

  Future<void> deleteDocRevision(String id) async {
    final paths = await client.rpc('delete_doc_revision', params: {'p_id': id});
    await removeDocObjects(client, _paths(paths));
    await _afterV8();
  }

  Future<void> deleteDocItem(String id) async {
    final paths = await client.rpc('delete_doc_item', params: {'p_id': id});
    await removeDocObjects(client, _paths(paths));
    await _afterV8();
  }

  Future<String> saveSiteReport(String? id, Map<String, dynamic> data) async {
    final res = await client.rpc('save_site_report', params: {'p_id': id, 'p_data': data});
    await _afterV8();
    return res.toString();
  }

  Future<void> reviewSiteReport(String id, bool reviewed, String note) async {
    await client.rpc('review_site_report', params: {'p_id': id, 'p_reviewed': reviewed, 'p_note': note});
    await _afterV8();
  }

  Future<void> deleteSiteReport(String id) async {
    final paths = await client.rpc('delete_site_report', params: {'p_id': id});
    await removeDocObjects(client, _paths(paths));
    await _afterV8();
  }

  /// يرفع الملفات ويسجّلها لإصدار مستند ([scope] = doc) أو لتقرير يومي ([scope] = report).
  /// يعيد عدد ما رُفع؛ ويرمي خطأً بأول ملف يتعذّر رفعه بعد تسجيل ما سبقه.
  Future<int> attachFiles(String scope, String ownerId, List<PickedDoc> files, {void Function(int done)? onProgress}) async {
    var done = 0;
    try {
      for (final f in files) {
        final path = newDocPath(scope, ownerId, f.ext);
        await uploadDoc(client, path, f);
        try {
          await client.rpc('add_doc_file', params: {'p_path': path, 'p_name': f.name, 'p_width': f.width, 'p_height': f.height});
        } catch (_) {
          await removeDocObjects(client, [path]);
          rethrow;
        }
        done++;
        onProgress?.call(done);
      }
    } finally {
      await _afterV8();
    }
    return done;
  }

  Future<void> deleteDocFile(String id) async {
    final path = await client.rpc('delete_doc_file', params: {'p_id': id});
    if (path != null) await removeDocObjects(client, [path.toString()]);
    await _afterV8();
  }

  // ---------------------------------------------------------------
  // أقسام الوحدات (الترحيل 21)
  // ---------------------------------------------------------------
  /// هل يكتب المستخدم في هذه الوحدة؟ (للعرض فقط؛ القاعدة تتحقق في unit_can_edit)
  /// المدير وموظفو مكتبه، ومستخدمو الوحدة المُسنَدون إليها، ورئيس الترميم لسجل المباني التاريخية،
  /// ورئيس المطابقة والاستلام لوحدتيه، ورئيس الشؤون الفنية لاعتماد المواد، ودور مكتب التخطيط وضمان الجودة لأقسامه الثلاثة.
  bool canEditUnit(String unit) {
    final r = role;
    if (!v9Ready || r == null || r == AppRole.securityAuditor) return false;
    if (r == AppRole.director) return true;
    if (frozenForMe) return false;
    if (r == AppRole.officeStaff || me?.unit == unit) return true;
    return _parentHeadOf(unit);
  }

  /// الكتابة في نوع سجل بعينه: صلاحية الوحدة كلها، أو صلاحية دقيقة على هذا النوع.
  bool canEditUnitKind(String kind) {
    final k = unitKinds[kind];
    if (k == null) return false;
    if (canEditUnit(k.unit)) return true;
    return v9Ready && role != null && role != AppRole.securityAuditor && !frozenForMe && hasGrant('unit:$kind');
  }

  /// رئيس الوحدة (يحذف سجلاتها ومرفقاتها): المدير، ورئيس الوحدة المُسنَد، ورئيس القسم الأم، ودور مكتب التخطيط لأقسامه.
  bool isUnitHead(String unit) {
    final r = role;
    if (!v9Ready || r == null) return false;
    if (r == AppRole.director) return true;
    if (frozenForMe) return false;
    if (me?.unit == unit && (me?.unitHead ?? false)) return true;
    return _parentHeadOf(unit);
  }

  bool _parentHeadOf(String unit) {
    final r = role;
    final dep = me?.department;
    return switch (unitSectionOf[unit]) {
      'heritage' => r == AppRole.deptHead && dep == 'restoration',
      'acceptance' => r == AppRole.deptHead && dep == 'acceptance',
      'technical' => r == AppRole.deptHead && dep == 'technical',
      'planning_qa' => r == AppRole.planningQa,
      _ => false,
    };
  }

  /// حذف سجل: رئيس الوحدة، أو من أضافه خلال 24 ساعة.
  bool canDeleteUnitRecord(UnitRecord r) => isUnitHead(r.unit) || (canEditUnitKind(r.kind) && canRemoveOwn(r.createdBy, r.createdAt));

  /// إزالة مرفق سجل: المدير ورئيس الوحدة، أو من رفعه خلال 24 ساعة.
  bool canRemoveUnitFile(UnitRecord r, DocFile f) =>
      isUnitHead(r.unit) || (canEditUnitKind(r.kind) && canRemoveOwn(f.createdBy, f.createdAt));

  /// مستخدمو الوحدة المُسنَدون إليها (الرئيس أولاً).
  List<Profile> unitMembers(String unit) =>
      people.values.where((p) => p.active && p.unit == unit).toList()
        ..sort((a, b) => a.unitHead == b.unitHead ? a.displayName.compareTo(b.displayName) : (a.unitHead ? -1 : 1));

  Future<String> saveUnitRecord(String? id, Map<String, dynamic> data) async {
    final res = await client.rpc('save_unit_record', params: {'p_id': id, 'p_data': data});
    await _afterV9();
    return res.toString();
  }

  Future<void> deleteUnitRecord(String id) async {
    final paths = await client.rpc('delete_unit_record', params: {'p_id': id});
    await removeDocObjects(client, _paths(paths));
    await _afterV9();
  }

  /// إسناد مستخدم إلى وحدة أو إزالته منها (المدير وحده).
  Future<void> setUserUnit(String userId, String? unit, bool head) async {
    await client.rpc('set_user_unit', params: {'p_user': userId, 'p_unit': unit, 'p_head': head});
    await _afterV9();
  }

  /// المساحة المستخدمة: (المستندات، غيرها، عدد الملفات، الحد)
  Future<(int, int, int, int)> storageUsage() async {
    final res = await client.rpc('docs_storage_usage');
    final m = res is Map ? res : const {};
    int n(Object? v) => v is num ? v.toInt() : int.tryParse('${v ?? 0}') ?? 0;
    return (n(m['docs_bytes']), n(m['other_bytes']), n(m['files']), n(m['limit_bytes']));
  }

  /// تنظيف الملفات اليتيمة في الحاوية (للمدير). يعيد عددها.
  Future<int> cleanOrphanFiles() async {
    final paths = _paths(await client.rpc('docs_orphan_paths'));
    await removeDocObjects(client, paths);
    return paths.length;
  }

  static List<String> _paths(Object? res) => res is List ? [for (final p in res) if (p != null) p.toString()] : const [];

  Future<void> deleteExtractPayment(String id) async {
    await client.rpc('delete_extract_payment', params: {'p_id': id});
    await loadAll();
  }

  /// الدفعة المقدمة للعقد (null لإزالتها).
  Future<void> setContractAdvance(String projectId, {double? amount, DateTime? paidOn}) async {
    await client.rpc('set_contract_advance', params: {
      'p_project': projectId,
      'p_amount': amount,
      'p_paid_on': paidOn == null ? null : dbDate(paidOn),
    });
    await loadAll();
  }

  /// استرداد مقترح من الدفعة المقدمة لمستخلص قيمة أعماله [gross] (لا يتجاوز الرصيد المتبقي).
  double suggestedAdvanceRecovery(Project p, double gross, {String? excludeExtractId}) {
    final adv = p.advanceAmount ?? 0;
    if (adv <= 0 || gross <= 0) return 0;
    final rate = settings.advanceRecoveryRate > 0
        ? settings.advanceRecoveryRate
        : ((p.contractValue ?? 0) > 0 ? adv / p.contractValue! : 0.0);
    final used = extractsOf(p.id)
        .where((x) => x.status != 'rejected' && x.id != excludeExtractId)
        .fold<double>(0, (a, x) => a + x.advanceRecovery);
    final remaining = (adv - used).clamp(0, double.infinity).toDouble();
    return roundMoney((gross * rate).clamp(0, remaining).toDouble());
  }

  /// سجل التعديلات المالية (لعقد أو للعقود كلها).
  Future<List<AuditEntry>> financeHistory({String? projectId, int limit = 400}) async {
    if (!v4Ready) return const [];
    final res = await client.rpc('finance_history', params: {'p_project': projectId, 'p_limit': limit});
    return res is List ? res.whereType<Map>().map((e) => AuditEntry.fromMap(Map<String, dynamic>.from(e))).toList() : const [];
  }

  // ---------------------------------------------------------------
  // مساعد Claude (المدير وحده). المفتاح سرّ في Supabase ولا يمر بالتطبيق.
  // ---------------------------------------------------------------
  Future<AssistantMessage> askClaude(String question) async {
    final history = [
      for (final m in assistantMessages.where((m) => !m.error).toList().reversed.take(16).toList().reversed)
        {'role': m.role, 'content': m.text},
    ];
    final user = AssistantMessage(role: 'user', text: question.trim());
    assistantMessages.add(user);
    _notify();
    AssistantMessage reply;
    try {
      // بوابة الخدمة تتحقق بالمفتاح العام (الموقّع بالسر القديم)، وهوية المدير تصل منفصلة وتتحقق منها قاعدة البيانات
      final token = client.auth.currentSession?.accessToken;
      final anon = AppConfig.supabaseAnonKey;
      final res = await client.functions.invoke(
        'claude-assistant',
        headers: {
          if (token != null) 'x-user-token': token,
          if (anon.startsWith('eyJ')) 'Authorization': 'Bearer $anon',
        },
        body: {
          'messages': [...history, {'role': 'user', 'content': user.text}],
        },
      );
      final data = res.data;
      if (data is Map && data['text'] is String) {
        final usage = data['usage'] is Map ? data['usage'] as Map : const {};
        final acts = data['actions'] is List
            ? (data['actions'] as List).whereType<Map>().map((e) => AssistantAction.fromMap(Map<String, dynamic>.from(e))).toList()
            : <AssistantAction>[];
        reply = AssistantMessage(
          role: 'assistant',
          text: (data['text'] as String).trim(),
          model: (data['model'] ?? '').toString(),
          inputTokens: (usage['input_tokens'] as num?)?.toInt() ?? 0,
          outputTokens: (usage['output_tokens'] as num?)?.toInt() ?? 0,
          actions: acts,
        );
      } else {
        reply = AssistantMessage(role: 'assistant', text: _assistantError(data), error: true);
      }
    } catch (e) {
      reply = AssistantMessage(role: 'assistant', text: _assistantError(_errorDetails(e) ?? e), error: true);
    }
    assistantMessages.add(reply);
    _notify();
    return reply;
  }

  void clearAssistant() {
    assistantMessages.clear();
    _notify();
  }

  void dismissAssistantAction(AssistantAction a) {
    a.state = 'dismissed';
    _notify();
  }

  /// ينفّذ اقتراحاً من المساعد بعد ضغطة المدير، عبر العمليات المعتادة (قاعدة البيانات تتحقق من الصلاحيات).
  Future<void> executeAssistantAction(AssistantAction a) async {
    if (a.state == 'running' || a.state == 'done') return;
    a.state = 'running';
    a.result = null;
    _notify();
    final i = a.input;
    double? numOf(String k) => i[k] is num ? (i[k] as num).toDouble() : double.tryParse('${i[k] ?? ''}');
    DateTime? day(String k) => i[k] == null ? null : DateTime.tryParse(i[k].toString());
    String str(String k) => (i[k] ?? '').toString();
    try {
      switch (a.name) {
        case 'propose_work_values':
          final w = work(str('work_id'));
          if (w == null) throw StateError('البند غير موجود في البيانات الحالية');
          await setWorkValues(
            w.id,
            contractValue: i.containsKey('contract_value') ? numOf('contract_value') : w.contractValue,
            executedValue: i.containsKey('executed_value') ? numOf('executed_value') : w.executedValue,
          );
          a.result = 'حُفظت قيم البند';
        case 'propose_variation':
          await saveVariation(
            projectId: str('project_id'),
            workId: str('work_id').isEmpty ? null : str('work_id'),
            refNo: str('ref_no'),
            title: str('title'),
            kind: str('kind') == 'deduct' ? 'deduct' : 'add',
            amount: numOf('amount') ?? 0,
            approvedOn: day('approved_on'),
            notes: 'اقتراح من مساعد Claude',
          );
          a.result = 'سُجّل أمر التغيير';
        case 'propose_extract':
          await saveExtract(
            projectId: str('project_id'),
            refNo: str('ref_no'),
            kind: str('kind') == 'final' ? 'final' : 'interim',
            periodFrom: day('period_from'),
            periodTo: day('period_to'),
            submittedOn: day('submitted_on'),
            gross: numOf('gross') ?? 0,
            retention: numOf('retention') ?? 0,
            advance: numOf('advance') ?? 0,
            penalties: numOf('penalties') ?? 0,
            taxes: numOf('taxes') ?? 0,
            other: numOf('other') ?? 0,
            status: extractStatuses.contains(str('status')) ? str('status') : 'submitted',
            approvedOn: day('approved_on'),
            paidAmount: numOf('paid_amount') ?? 0,
            paidOn: day('paid_on'),
            notes: 'اقتراح من مساعد Claude',
          );
          a.result = 'سُجّل المستخلص';
        case 'propose_extract_status':
          ContractExtract? x;
          for (final e in extracts) {
            if (e.id == str('extract_id')) x = e;
          }
          if (x == null) throw StateError('المستخلص غير موجود في البيانات الحالية');
          final st = extractStatuses.contains(str('status')) ? str('status') : x.status;
          await saveExtract(
            id: x.id,
            projectId: x.projectId,
            workId: x.workId,
            refNo: x.refNo,
            kind: x.kind,
            periodFrom: x.periodFrom,
            periodTo: x.periodTo,
            submittedOn: x.submittedOn,
            gross: x.gross,
            retention: x.retention,
            advance: x.advanceRecovery,
            penalties: x.penalties,
            taxes: x.taxes,
            other: x.otherDeductions,
            status: st,
            approvedOn: day('approved_on') ?? x.approvedOn,
            paidAmount: i.containsKey('paid_amount')
                ? (numOf('paid_amount') ?? 0)
                : (st == 'approved' || st == 'referred' || st == 'paid' ? x.paidAmount : 0),
            paidOn: day('paid_on') ?? x.paidOn,
            notes: x.notes,
            referredOn: day('referred_on') ?? x.referredOn,
            referralNo: i.containsKey('referral_no') ? str('referral_no') : x.referralNo,
            custom: x.customDeductions,
          );
          a.result = 'حُدّث المستخلص';
        case 'propose_extract_payment':
          await addExtractPayment(
            str('extract_id'),
            amount: numOf('amount') ?? 0,
            paidOn: day('paid_on'),
            method: paymentMethodLabels.containsKey(str('method')) ? str('method') : 'transfer',
            refNo: str('ref_no'),
            notes: 'اقتراح من مساعد Claude',
          );
          a.result = 'سُجّلت الدفعة';
        case 'propose_contract_advance':
          await setContractAdvance(str('project_id'), amount: numOf('amount'), paidOn: day('paid_on'));
          a.result = 'حُفظت الدفعة المقدمة';
        case 'propose_contract_no':
          await setContractNo(str('project_id'), str('contract_no'));
          a.result = 'حُفظ رقم العقد';
        case 'propose_form_status':
          final r = await setFormStatus(str('project_id'), str('form_key'), parseStatus(str('status')));
          a.result = r == 'unchanged' ? 'لم يتغير شيء' : 'حُدّثت حالة النموذج';
        case 'propose_setting':
          await setSetting(str('key'), i['value']);
          a.result = 'حُفظ الإعداد';
        case 'propose_idea':
          await submitIdea(
            title: str('title'),
            body: '${str('body')}\n\n— من مساعد Claude',
            category: const ['feature', 'design', 'data', 'security', 'bug', 'other'].contains(str('category')) ? str('category') : 'feature',
            priority: const ['low', 'normal', 'high', 'urgent'].contains(str('priority')) ? str('priority') : 'normal',
          );
          a.result = 'حُفظت الفكرة';
        default:
          throw StateError('اقتراح غير معروف: ${a.name}');
      }
      a.state = 'done';
      try {
        await client.rpc('ai_action_log', params: {'p_name': a.name, 'p_summary': a.summary});
      } catch (_) {}
    } catch (e) {
      a.state = 'failed';
      a.result = e is StateError ? e.message : friendlyError(e);
    }
    _notify();
  }

  static Object? _errorDetails(Object e) {
    try {
      return (e as dynamic).details;
    } catch (_) {
      return null;
    }
  }

  static String _assistantError(Object? data) {
    final code = data is Map ? (data['code'] ?? '').toString() : '';
    final msg = data is Map ? (data['error'] ?? data['message'] ?? '').toString() : (data?.toString() ?? '');
    return switch (code) {
      'missing_key' => 'لم يُضف مفتاح Anthropic بعد. أضفه في Supabase ← Edge Functions ← Secrets باسم ANTHROPIC_API_KEY، ثم أعد السؤال.',
      'forbidden' => 'مساعد Claude لمدير المكتب وحده.',
      'disabled' => 'مساعد Claude متوقف من «التخصيص والتطوير».',
      'anthropic' => 'رفضت خدمة Claude الطلب: $msg',
      _ => msg.contains('Function not found') || msg.contains('404') || msg.contains('NOT_FOUND')
          ? 'خدمة المساعد غير منشورة بعد على Supabase (claude-assistant).'
          : (msg.isEmpty ? 'تعذّر الوصول إلى مساعد Claude. تحقق من الاتصال وأعد المحاولة.' : msg),
    };
  }

  /// الكتابة عبر دالة قاعدة البيانات المدققة (الترحيل 26)، وعلى قاعدة لم تُحدَّث بعد تبقى الكتابة القديمة.
  Future<T> _audited<T>(Future<T> Function() rpc, Future<T> Function() legacy) async {
    try {
      return await rpc();
    } on PostgrestException catch (e) {
      final missing = e.code == 'PGRST202' || e.message.contains('Could not find the function');
      if (!missing) rethrow;
      return legacy();
    }
  }

  Future<String> saveProject({String? id, required Map<String, dynamic> data}) async {
    final saved = await _audited<String>(
      () async => (await client.rpc('save_project', params: {'p_id': id, 'p_data': data})).toString(),
      () async {
        if (id == null) return (await client.from('projects').insert(data).select('id').single())['id'].toString();
        await client.from('projects').update(data).eq('id', id);
        return id;
      },
    );
    await loadAll();
    return saved;
  }

  Future<void> updateNotes(String projectId, String notes) async {
    await saveProject(id: projectId, data: {'notes': notes});
  }

  Future<void> deleteProject(String projectId) async {
    await _audited<void>(
      () => client.rpc('delete_project', params: {'p_id': projectId}),
      () => client.from('projects').delete().eq('id', projectId),
    );
    await loadAll();
  }

  Future<List<QualityNote>> loadQualityNotes(String projectId) async {
    final rows = await client.from('quality_notes').select().eq('project_id', projectId).order('created_at', ascending: false);
    return rows.map(QualityNote.fromMap).toList();
  }

  Future<void> addQualityNote(String projectId, String body) async {
    await _audited<void>(
      () => client.rpc('add_quality_note', params: {'p_project': projectId, 'p_body': body}),
      () => client.from('quality_notes').insert({'project_id': projectId, 'body': body}),
    );
  }

  Future<List<AuditEntry>> loadProjectAudit(String projectId) async {
    final rows = await client.from('audit_log').select().eq('project_id', projectId).order('at', ascending: false).limit(150);
    return rows.map(AuditEntry.fromMap).toList();
  }

  Future<List<AuditEntry>> loadAudit({int limit = 400}) async {
    final rows = await client.from('audit_log').select().order('at', ascending: false).limit(limit);
    return rows.map(AuditEntry.fromMap).toList();
  }

  Future<void> setUserAccess(String userId, {required AppRole? role, String? department, required bool active, String? fullName}) async {
    await client.rpc('set_user_access', params: {
      'p_user': userId,
      'p_role': role?.db,
      'p_department': role == AppRole.deptHead ? department : null,
      'p_active': active,
      'p_full_name': fullName,
    });
    await loadAll();
  }

  /// تغيير بريد الدخول (للمدير وحده؛ تتحقق قاعدة البيانات من ذلك).
  Future<void> setUserEmail(String userId, String email) async {
    await client.rpc('admin_set_email', params: {'p_user': userId, 'p_email': email.trim()});
    await loadAll();
  }

  Future<void> updateFormDef(String key, {bool? sensitive, List<String>? responsible}) async {
    final data = <String, dynamic>{};
    if (sensitive != null) data['sensitive'] = sensitive;
    if (responsible != null) data['responsible'] = responsible;
    if (data.isEmpty) return;
    await _audited<void>(
      () => client.rpc('set_form_rights', params: {'p_key': key, 'p_sensitive': sensitive, 'p_responsible': responsible}),
      () => client.from('form_defs').update(data).eq('key', key),
    );
    await loadAll();
  }

  Future<void> updateMyName(String name) async {
    final uid = me?.id;
    if (uid == null) return;
    await _audited<void>(
      () => client.rpc('set_my_name', params: {'p_name': name}),
      () => client.from('profiles').update({'full_name': name}).eq('id', uid),
    );
    await loadAll();
  }

  // ---------------------------------------------------------------
  // الإصدار الثاني: لوحة التحكم
  // ---------------------------------------------------------------
  Future<void> setSetting(String key, Object? value) async {
    await client.rpc('set_setting', params: {'p_key': key, 'p_value': value});
    await loadAll();
  }

  Future<void> saveStage(int? idx, String name) async {
    await client.rpc('save_stage', params: {'p_idx': idx, 'p_name': name});
    await loadAll();
  }

  Future<void> deleteStage(int idx) async {
    await client.rpc('delete_stage', params: {'p_idx': idx});
    await loadAll();
  }

  Future<String> saveFormDef({String? key, required String name, required int stage, required bool sensitive, required List<String> responsible, required bool active}) async {
    final res = await client.rpc('save_form_def', params: {
      'p_key': key,
      'p_name': name,
      'p_stage': stage,
      'p_sensitive': sensitive,
      'p_responsible': responsible,
      'p_active': active,
    });
    await loadAll();
    return res?.toString() ?? '';
  }

  Future<void> reorderForms(List<String> keys) async {
    await client.rpc('reorder_forms', params: {'p_keys': keys});
    await loadAll();
  }

  Future<void> deleteFormDef(String key) async {
    await client.rpc('delete_form_def', params: {'p_key': key});
    await loadAll();
  }

  Future<void> saveDepartment({String? key, required String name, bool canSupervise = false}) async {
    await client.rpc('save_department', params: {'p_key': key, 'p_name': name, 'p_can_supervise': canSupervise});
    await loadAll();
  }

  Future<void> saveCustomField({
    String? key,
    required String label,
    required String kind,
    required List<String> options,
    required String section,
    required List<String> editableBy,
    required bool active,
  }) async {
    await client.rpc('save_custom_field', params: {
      'p_key': key,
      'p_label': label,
      'p_kind': kind,
      'p_options': options,
      'p_section': section,
      'p_editable_by': editableBy,
      'p_active': active,
    });
    await loadAll();
  }

  Future<void> reorderCustomFields(List<String> keys) async {
    await client.rpc('reorder_custom_fields', params: {'p_keys': keys});
    await loadAll();
  }

  Future<void> setProjectField(String projectId, String key, Object? value) async {
    await client.rpc('set_project_field', params: {'p_project': projectId, 'p_key': key, 'p_value': value});
    await loadAll();
  }

  Future<void> submitIdea({
    required String title,
    required String body,
    required String category,
    required String priority,
    String? section,
    int? pageId,
    String pageLabel = '',
  }) async {
    await client.rpc('submit_idea', params: {
      'p_title': title,
      'p_body': body,
      'p_category': category,
      'p_priority': priority,
      if (v18Ready && section != null) ...{
        'p_section': section,
        'p_page': pageId,
        'p_page_label': pageId == null ? null : pageLabel,
      },
    });
    await loadAll();
  }

  /// نقل فكرة إلى قسم أو صفحة (المدير). القسم الفارغ يجعلها عامة.
  Future<void> moveIdea(String id, {String? section, int? pageId, String pageLabel = ''}) async {
    await client.rpc('move_idea', params: {
      'p_id': id,
      'p_section': section,
      'p_page': section == null ? null : pageId,
      'p_page_label': section == null || pageId == null ? null : pageLabel,
    });
    await loadAll();
  }

  /// الأفكار المفتوحة (جديدة أو مخططة أو قيد التنفيذ) في قسم، أو كلها.
  List<Idea> openIdeas([String? section]) => [
        for (final i in ideas)
          if (i.isOpen && (section == null || i.section == section)) i,
      ];

  /// الأفكار الجديدة التي لم يطّلع عليها المدير في قسم.
  int newIdeasIn(String section) => ideas.where((i) => i.status == 'new' && i.section == section).length;

  /// طلب فتح «الأفكار والتطوير» مصفّاة على قسم (تستهلكه الصفحة مرة واحدة).
  String? ideasFocus;

  /// فتح أفكار قسم: صفحة «الأفكار والتطوير» في القسم نفسه، وللدورة المستندية الصفحة العامة مصفّاة عليها.
  void openIdeasFor(String section) {
    ideasFocus = section;
    setTab(ideasTabOf(section));
  }

  String? takeIdeasFocus() {
    final s = ideasFocus;
    ideasFocus = null;
    return s;
  }

  Future<void> updateIdea(String id, {String? status, String? priority, String? response}) async {
    await client.rpc('update_idea', params: {'p_id': id, 'p_status': status, 'p_priority': priority, 'p_response': response});
    await loadAll();
  }

  Future<void> deleteIdea(String id) async {
    await client.rpc('delete_idea', params: {'p_id': id});
    await loadAll();
  }

  Future<Map<String, dynamic>> exportConfig() async {
    final res = await client.rpc('export_config');
    return res is Map ? Map<String, dynamic>.from(res) : <String, dynamic>{};
  }

  Future<int> importSettings(Map<String, dynamic> values) async {
    final res = await client.rpc('import_settings', params: {'p_settings': values});
    await loadAll();
    return (res as num?)?.toInt() ?? 0;
  }

  // ---------------------------------------------------------------
  // مركز الأمان
  // ---------------------------------------------------------------
  Future<Map<String, dynamic>> securityOverview() async {
    final res = await client.rpc('security_overview');
    return res is Map ? Map<String, dynamic>.from(res) : <String, dynamic>{};
  }

  Future<List<Map<String, dynamic>>> securityUsers() async {
    final res = await client.rpc('security_users');
    return res is List ? res.map((e) => Map<String, dynamic>.from(e as Map)).toList() : const [];
  }

  Future<List<Map<String, dynamic>>> listSessions() async {
    final res = await client.rpc('list_sessions');
    return res is List ? res.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList() : const [];
  }

  Future<List<Map<String, dynamic>>> loginHistory({int limit = 200}) async {
    final res = await client.rpc('login_history', params: {'p_limit': limit});
    return res is List ? res.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList() : const [];
  }

  Future<void> revokeSession(String sessionId) async {
    await client.rpc('revoke_session', params: {'p_session': sessionId});
  }

  Future<int> revokeUserSessions(String userId) async {
    final res = await client.rpc('revoke_user_sessions', params: {'p_user': userId});
    return (res as num?)?.toInt() ?? 0;
  }

  Future<int> resetUserMfa(String userId) async {
    final res = await client.rpc('reset_user_mfa', params: {'p_user': userId});
    return (res as num?)?.toInt() ?? 0;
  }

  /// البيانات الكاملة لمستخدم: الحساب والأمان والأجهزة وسجل الدخول والنشاط (للمدير وCISO).
  Future<Map<String, dynamic>> userDetails(String userId) async {
    final res = await client.rpc('user_details', params: {'p_user': userId});
    return res is Map ? Map<String, dynamic>.from(res) : <String, dynamic>{};
  }

  // ---- الأمان الموسع: الأجهزة، والقفل، والحركة، والتنبيهات ----
  Future<List<UserDevice>> securityDevices() async {
    final res = await client.rpc('security_devices');
    return res is List ? res.whereType<Map>().map((e) => UserDevice(Map<String, dynamic>.from(e))).toList() : const [];
  }

  Future<List<Map<String, dynamic>>> securityTimeline({String? userId, int days = 30, int limit = 800}) async {
    final res = await client.rpc('security_timeline', params: {'p_user': userId, 'p_days': days, 'p_limit': limit});
    return res is List ? res.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList() : const [];
  }

  Future<List<Map<String, dynamic>>> securityAlerts() async {
    final res = await client.rpc('security_alerts');
    return res is List ? res.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList() : const [];
  }

  /// قفل الدخول: دقائق محددة، أو null حتى يُفك يدوياً. يُرجع عدد الجلسات المنتهية.
  Future<int> lockUser(String userId, {int? minutes, required String reason}) async {
    final res = await client.rpc('lock_user', params: {'p_user': userId, 'p_minutes': minutes, 'p_reason': reason.trim()});
    return (res as num?)?.toInt() ?? 0;
  }

  Future<void> unlockUser(String userId) async {
    await client.rpc('unlock_user', params: {'p_user': userId});
  }

  Future<int> setDeviceBlocked(String deviceId, bool blocked) async {
    final res = await client.rpc('set_device_blocked', params: {'p_device': deviceId, 'p_blocked': blocked});
    return (res as num?)?.toInt() ?? 0;
  }

  Future<List<UserDevice>> myDevices() async {
    try {
      final res = await client.rpc('my_devices');
      return res is List ? res.whereType<Map>().map((e) => UserDevice(Map<String, dynamic>.from(e))).toList() : const [];
    } catch (_) {
      return const [];
    }
  }

  Future<void> forgetMyDevice(String deviceId) async {
    await client.rpc('forget_my_device', params: {'p_device': deviceId});
  }

  /// حالة قفل حسابي: {locked, until, reason}.
  Future<Map<String, dynamic>> myLock() async {
    try {
      final res = await client.rpc('my_lock');
      return res is Map ? Map<String, dynamic>.from(res) : const {};
    } catch (_) {
      return const {};
    }
  }

  /// معاينة المظهر قبل حفظه (تُعاد عند الإلغاء).
  Appearance? _appearancePreview;

  void previewAppearance(Appearance a) {
    _appearancePreview = a;
    appearance = a;
    _notify();
  }

  void restoreAppearance() {
    _appearancePreview = null;
    appearance = Appearance.fromJson(settings.raw['ui.appearance']);
    _notify();
  }

  /// حذف مستخدم نهائياً (لمدير المكتب وحده، بتأكيد بريد المستخدم).
  Future<void> deleteUser(String userId, String confirmEmail) async {
    await client.rpc('delete_user', params: {'p_user': userId, 'p_confirm_email': confirmEmail.trim()});
    await loadAll();
  }

  /// تسجيل الخروج من كل الأجهزة الأخرى لحسابي.
  Future<void> signOutOtherDevices() async {
    await client.auth.signOut(scope: SignOutScope.others);
  }

  // ---------------------------------------------------------------
  // التحقق بخطوتين (TOTP)
  // ---------------------------------------------------------------
  Future<List<Factor>> verifiedFactors() async {
    final res = await client.auth.mfa.listFactors();
    return res.totp.where((f) => f.status == FactorStatus.verified).toList();
  }

  bool get needsMfaChallenge {
    final aal = client.auth.mfa.getAuthenticatorAssuranceLevel();
    return aal.nextLevel == AuthenticatorAssuranceLevels.aal2 && aal.currentLevel != AuthenticatorAssuranceLevels.aal2;
  }

  Future<AuthMFAEnrollResponse> enrollTotp() async {
    // حذف أي تسجيل سابق لم يكتمل
    final res = await client.auth.mfa.listFactors();
    for (final f in res.all) {
      if (f.status != FactorStatus.verified) {
        try {
          await client.auth.mfa.unenroll(f.id);
        } catch (_) {}
      }
    }
    return client.auth.mfa.enroll(
      factorType: FactorType.totp,
      issuer: 'الدورة المستندية',
      friendlyName: 'هاتف ${DateTime.now().millisecondsSinceEpoch}',
    );
  }

  Future<void> verifyTotp(String factorId, String code) async {
    await client.auth.mfa.challengeAndVerify(factorId: factorId, code: code.trim());
  }

  Future<void> unenrollFactor(String factorId) async {
    await client.auth.mfa.unenroll(factorId);
  }

  Future<void> markNotificationsRead() async {
    final uid = me?.id;
    if (uid == null || unreadCount == 0) return;
    await _audited<void>(
      () => client.rpc('mark_notifications_read'),
      () => client.from('notifications').update({'read_at': DateTime.now().toUtc().toIso8601String()}).eq('user_id', uid),
    );
    await loadAll();
  }
}

/// رسالة خطأ مفهومة للمستخدم.
Color? parseHexColor(String hex) {
  final h = hex.replaceFirst('#', '');
  if (h.length != 6) return null;
  final v = int.tryParse(h, radix: 16);
  return v == null ? null : Color(0xFF000000 | v);
}

String friendlyError(Object e) {
  if (e is PostgrestException) {
    final m = e.message;
    if (m.contains('row-level security') || m.contains('permission denied')) return 'لا تملك صلاحية هذا الإجراء.';
    if (m.contains('duplicate key') && m.contains('assign_no')) return 'رقم التكليف مستخدم في مشروع آخر.';
    if (m.contains('projects_contract_no_uq')) return 'رقم العقد مستخدم لعقد آخر.';
    if (m.contains('projects_has_identity')) return 'اكتب رقم التكليف أو اسم المشروع على الأقل.';
    if (m.contains('contract_works_identity')) return 'اكتب وصف العمل أو الشركة.';
    if (m.contains('contract_engineers_name_check')) return 'اسم المهندس من حرفين إلى 120 حرفاً.';
    if (m.contains('contract_extracts_deductions')) return 'الاستقطاعات أكبر من قيمة الأعمال في المستخلص.';
    if (m.contains('contract_extracts_paid')) return 'المدفوع أكبر من صافي المستخلص.';
    if (m.contains('contract_extracts_period')) return 'بداية فترة المستخلص بعد نهايتها.';
    return m;
  }
  if (e is StorageException) {
    final m = e.message.toLowerCase();
    if (m.contains('row-level security') || m.contains('unauthorized') || e.statusCode == '403') {
      return 'لا تملك صلاحية رفع هذا الملف أو قراءته.';
    }
    if (m.contains('too large') || m.contains('payload') || m.contains('maximum allowed size')) {
      return 'الملف أكبر من الحد المسموح (20 ميجابايت).';
    }
    if (m.contains('mime') || m.contains('not supported')) return 'نوع الملف غير مسموح؛ المسموح PDF والصور.';
    if (m.contains('not found')) return 'الملف غير موجود في المخزن؛ ربما حُذف.';
    return e.message;
  }
  if (e is StateError) return e.message;
  if (e is AuthException) {
    final m = e.message.toLowerCase();
    if (m.contains('invalid login')) return 'البريد أو كلمة المرور غير صحيحة.';
    if (m.contains('already registered') || m.contains('already been registered')) return 'هذا البريد مسجّل مسبقاً. سجّل الدخول به.';
    if (m.contains('not confirmed')) return 'أكّد بريدك من الرسالة المرسلة إليك، ثم سجّل الدخول.';
    if (m.contains('signups') || m.contains('signup')) {
      return 'إنشاء الحسابات متوقف في إعدادات Supabase. على مدير المنظومة تفعيل الدخول بالبريد والسماح بالتسجيل.';
    }
    if (m.contains('logins are disabled')) return 'الدخول بالبريد متوقف في إعدادات Supabase. تواصل مع مدير المنظومة.';
    if (m.contains('password')) return 'كلمة المرور قصيرة أو ضعيفة. استخدم 10 أحرف على الأقل، وفيها حروف وأرقام.';
    if (m.contains('rate limit')) return 'محاولات كثيرة. انتظر دقيقة ثم أعد المحاولة.';
    if (m.contains('database error saving new user')) return 'التسجيل في المنظومة مغلق حالياً بقرار مدير المكتب.';
    if (m.contains('invalid totp') || m.contains('invalid code') || (m.contains('mfa') && m.contains('invalid'))) {
      return 'رمز التحقق غير صحيح أو انتهت صلاحيته. اكتب الرمز الظاهر الآن في تطبيق المصادقة.';
    }
    return e.message;
  }
  return 'تعذّر الاتصال بالخادم. تحقق من الإنترنت وأعد المحاولة.';
}

/// مقارنة طبيعية للأرقام داخل النص (2 قبل 10).
int _naturalCompare(String a, String b) {
  final re = RegExp(r'\d+|\D+');
  final pa = re.allMatches(a).map((m) => m.group(0)!).toList();
  final pb = re.allMatches(b).map((m) => m.group(0)!).toList();
  for (var i = 0; i < pa.length && i < pb.length; i++) {
    final x = pa[i], y = pb[i];
    final nx = int.tryParse(x), ny = int.tryParse(y);
    final c = (nx != null && ny != null) ? nx.compareTo(ny) : x.compareTo(y);
    if (c != 0) return c;
  }
  return pa.length.compareTo(pb.length);
}

/// الوصول إلى حالة التطبيق من أي شاشة.
class AppScope extends InheritedNotifier<AppState> {
  const AppScope({super.key, required AppState state, required super.child}) : super(notifier: state);

  /// يقرأ الحالة ويعيد البناء عند تغيّرها.
  static AppState of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<AppScope>()!.notifier!;

  /// يقرأ الحالة دون الاشتراك في التغييرات (داخل معالجات الأحداث).
  static AppState read(BuildContext context) => context.findAncestorWidgetOfExactType<AppScope>()!.notifier!;

  static AppState? maybeRead(BuildContext context) => context.findAncestorWidgetOfExactType<AppScope>()?.notifier;
}
