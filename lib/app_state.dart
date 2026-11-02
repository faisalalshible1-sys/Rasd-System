import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config.dart';
import 'models.dart';

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

  /// محادثة مساعد Claude الحالية (تبقى أثناء التنقل بين الصفحات).
  final List<AssistantMessage> assistantMessages = [];

  // تفضيلات هذا الجهاز
  ThemeMode themeMode = ThemeMode.system;

  Future<void> loadPrefs() async {
    try {
      final p = await SharedPreferences.getInstance();
      themeMode = switch (p.getString('theme_mode')) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      };
    } catch (_) {}
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
  int tab = 0;
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

  bool canEditForm(Project p, FormDef d) => d.active ? hasToken(p, d.responsible) : isDirector;

  bool canEditField(Project p, CustomField f) => f.active && hasToken(p, f.editableBy);

  List<CustomField> get activeFields => customFields.where((f) => f.active).toList();

  /// لون الهوية من الإعدادات الحية (أو من إعدادات ما قبل الدخول).
  Color get brandColor {
    final hex = settings.raw.isNotEmpty ? settings.primaryHex : (publicSettings['brand.primary_color'] ?? '#8A6A1E').toString();
    return parseHexColor(hex) ?? const Color(0xFF8A6A1E);
  }

  String get appTitle => settings.raw.isNotEmpty
      ? settings.appTitle
      : (publicSettings['brand.app_title'] ?? 'منظومة متابعة الدورة المستندية').toString();

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

  /// البيانات المالية للعقد يحدّثها من يختص بـ«أمر تعاقد» في المشروع.
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
    _notify();
    try {
      final List<Future<List<Map<String, dynamic>>>> queries = [
        client.from('departments').select().order('sort'),
        client.from('form_defs').select().order('sort'),
        client.from('projects').select().order('sort_order'),
        client.from('project_forms').select('project_id, form_key, status'),
        client.from('change_requests').select().order('requested_at', ascending: false).limit(500),
        client.from('profiles').select('id, full_name, email, role, department, active, created_at'),
        client.from('notifications').select().order('created_at', ascending: false).limit(100),
      ];
      final r = await Future.wait(queries);
      departments = r[0].map(Department.fromMap).toList();
      allFormDefs = r[1].map(FormDef.fromMap).toList()..sort((a, b) => a.sort.compareTo(b.sort));
      formDefs = allFormDefs.where((d) => d.active).toList();
      projects = r[2].map(Project.fromMap).toList();
      final st = <String, Map<String, FormStatus>>{};
      for (final row in r[3]) {
        final pid = row['project_id'].toString();
        (st[pid] ??= <String, FormStatus>{})[row['form_key'].toString()] = parseStatus(row['status']);
      }
      statuses = st;
      requests = r[4].map(ChangeRequest.fromMap).toList();
      people = {for (final p in r[5].map(Profile.fromMap)) p.id: p};
      notifications = r[6].map(AppNotification.fromMap).toList();
      final mine = people[me?.id];
      if (mine != null) me = mine;
      await _loadV2();
      await _loadV3();
      _progressCache.clear();
      loadError = null;
      loadedOnce = true;
      dataVersion++;
      unawaited(checkForUpdate());
    } catch (e) {
      loadError = friendlyError(e);
    } finally {
      loading = false;
      _notify();
    }
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

  /// إعدادات الهوية قبل تسجيل الدخول.
  Future<void> loadPublicSettings() async {
    try {
      final res = await client.rpc('public_settings');
      if (res is Map) {
        publicSettings = Map<String, dynamic>.from(res);
        if (settings.raw.isEmpty) motionSetting = normalizeMotion(publicSettings['ui.motion']);
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
    tab = 0;
    _progressCache.clear();
    _notify();
  }

  void _notify() {
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
    super.dispose();
  }

  // ---------------------------------------------------------------
  // التنقل والتصفية
  // ---------------------------------------------------------------
  void setTab(int i) {
    tab = i;
    _notify();
  }

  void setScope({String? owner, String? company}) {
    if (owner != null) ownerFilter = owner;
    if (company != null) companyFilter = company;
    _notify();
  }

  void openProjects({CycleState? cycle, int? stage, String? form, bool nextOnly = false}) {
    search = '';
    cycleFilter = cycle;
    stageFilter = stage;
    formFilter = form;
    formFilterNextOnly = nextOnly;
    tab = 1;
    _notify();
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
      final res = await client.functions.invoke('claude-assistant', body: {
        'messages': [...history, {'role': 'user', 'content': user.text}],
      });
      final data = res.data;
      if (data is Map && data['text'] is String) {
        final usage = data['usage'] is Map ? data['usage'] as Map : const {};
        reply = AssistantMessage(
          role: 'assistant',
          text: (data['text'] as String).trim(),
          model: (data['model'] ?? '').toString(),
          inputTokens: (usage['input_tokens'] as num?)?.toInt() ?? 0,
          outputTokens: (usage['output_tokens'] as num?)?.toInt() ?? 0,
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

  Future<String> saveProject({String? id, required Map<String, dynamic> data}) async {
    if (id == null) {
      final row = await client.from('projects').insert(data).select('id').single();
      await loadAll();
      return row['id'].toString();
    }
    await client.from('projects').update(data).eq('id', id);
    await loadAll();
    return id;
  }

  Future<void> updateNotes(String projectId, String notes) async {
    await client.from('projects').update({'notes': notes}).eq('id', projectId);
    await loadAll();
  }

  Future<void> deleteProject(String projectId) async {
    await client.from('projects').delete().eq('id', projectId);
    await loadAll();
  }

  Future<List<QualityNote>> loadQualityNotes(String projectId) async {
    final rows = await client.from('quality_notes').select().eq('project_id', projectId).order('created_at', ascending: false);
    return rows.map(QualityNote.fromMap).toList();
  }

  Future<void> addQualityNote(String projectId, String body) async {
    await client.from('quality_notes').insert({'project_id': projectId, 'body': body});
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
    await client.from('form_defs').update(data).eq('key', key);
    await loadAll();
  }

  Future<void> updateMyName(String name) async {
    final uid = me?.id;
    if (uid == null) return;
    await client.from('profiles').update({'full_name': name}).eq('id', uid);
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

  Future<void> submitIdea({required String title, required String body, required String category, required String priority}) async {
    await client.rpc('submit_idea', params: {'p_title': title, 'p_body': body, 'p_category': category, 'p_priority': priority});
    await loadAll();
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
    await client.from('notifications').update({'read_at': DateTime.now().toUtc().toIso8601String()}).eq('user_id', uid);
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
    return m;
  }
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
