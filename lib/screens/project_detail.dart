import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app_state.dart';
import '../models.dart';
import '../ui/audit_text.dart';
import '../ui/motion.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';
import 'contract_finance.dart';
import 'docs.dart' show ContractDocsCard;
import 'pm_projects.dart' show ProjectTrackCard;
import 'projects.dart';

/// صفحة العقد: رقمه وأعماله المدمجة ومهندسوه بأرقام تكليفهم وقيمه المالية ونماذج دورته المستندية.
class ProjectDetailPage extends StatefulWidget {
  const ProjectDetailPage({super.key, required this.projectId});

  final String projectId;

  @override
  State<ProjectDetailPage> createState() => _ProjectDetailPageState();
}

class _ProjectDetailPageState extends State<ProjectDetailPage> {
  static const _engFields = ['eng_sup', 'eng_qty', 'eng_fol', 'eng_saf'];
  static const _finFields = ['contract_value', 'executed_value', 'payment_first', 'payment_second', 'payment_final', 'deductions'];

  AppState? _app;
  final Map<String, TextEditingController> _eng = {};
  final Map<String, FocusNode> _engFocus = {};
  final TextEditingController _notes = TextEditingController();
  final FocusNode _notesFocus = FocusNode();
  final TextEditingController _qnote = TextEditingController();
  final Map<String, TextEditingController> _fin = {};
  bool _finDirty = false; // تعديلات مالية لم تُحفظ بعد: لا يُكتب فوقها عند وصول تحديث
  bool _busyFin = false;
  bool _busyGna = false;
  String? _busyForm;
  bool _busyNote = false;
  List<AuditEntry>? _history;
  List<QualityNote>? _qnotes;
  List<Map<String, dynamic>> _merged = const [];
  DateTime? _lastUpdated;

  @override
  void initState() {
    super.initState();
    for (final f in _engFields) {
      _eng[f] = TextEditingController();
      _engFocus[f] = FocusNode();
    }
    for (final f in _finFields) {
      _fin[f] = TextEditingController();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final app = AppScope.of(context);
    if (!identical(app, _app)) {
      _app?.removeListener(_onAppChanged);
      _app = app;
      app.addListener(_onAppChanged);
      _syncControllers();
      _loadSide();
    }
  }

  @override
  void dispose() {
    _app?.removeListener(_onAppChanged);
    for (final c in _eng.values) {
      c.dispose();
    }
    for (final f in _engFocus.values) {
      f.dispose();
    }
    for (final c in _fin.values) {
      c.dispose();
    }
    _notes.dispose();
    _notesFocus.dispose();
    _qnote.dispose();
    super.dispose();
  }

  void _onAppChanged() {
    if (!mounted) return;
    _syncControllers();
    final p = _app?.project(widget.projectId);
    if (p != null && p.updatedAt != _lastUpdated) {
      _lastUpdated = p.updatedAt;
      _loadSide();
    }
  }

  void _syncControllers() {
    final p = _app?.project(widget.projectId);
    if (p == null) return;
    for (final f in _engFields) {
      final c = _eng[f]!;
      if (!_engFocus[f]!.hasFocus && c.text != p.engineer(f)) c.text = p.engineer(f);
    }
    if (!_notesFocus.hasFocus && _notes.text != p.notes) _notes.text = p.notes;
    if (!_finDirty) {
      for (final f in _finFields) {
        final v = moneyInput(_finValue(p, f));
        if (_fin[f]!.text != v) _fin[f]!.text = v;
      }
    }
    _lastUpdated ??= p.updatedAt;
  }

  static double? _finValue(Project p, String field) => switch (field) {
        'contract_value' => p.contractValue,
        'executed_value' => p.executedValue,
        'payment_first' => p.paymentFirst,
        'payment_second' => p.paymentSecond,
        'payment_final' => p.paymentFinal,
        _ => p.deductions,
      };

  Future<void> _loadSide() async {
    final app = _app;
    if (app == null) return;
    try {
      final h = await app.loadProjectAudit(widget.projectId);
      final q = await app.loadQualityNotes(widget.projectId);
      var m = const <Map<String, dynamic>>[];
      try {
        m = await app.mergedSources(widget.projectId);
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _history = h;
        _qnotes = q;
        _merged = m;
      });
    } catch (_) {
      if (mounted) setState(() => _history ??= const []);
    }
  }

  // ---------------------------------------------------------------
  // الإجراءات: النماذج والاعتمادات
  // ---------------------------------------------------------------
  Future<void> _change(Project p, FormDef d, FormStatus s) async {
    final app = AppScope.read(context);
    final kind = d.engineerField?.substring(4);
    if (s == FormStatus.na && kind != null && app.engineerFormOf(kind)?.key == d.key && app.engineersOf(p.id, kind).isNotEmpty) {
      showToast(context, 'في العقد ${engineerKindPlural(kind)} مكلّفون. ألغِ تكليفاتهم أولاً ثم سجّل «${d.name}» «لا ينطبق».', error: true);
      return;
    }
    var note = '';
    if (app.needsApproval(d)) {
      final res = await textInputDialog(
        context,
        title: 'طلب اعتماد',
        message: '«${d.name}» نموذج حساس. يبقى على حالته الحالية حتى يعتمد مدير المكتب تغييره إلى «${s.label}».',
        label: 'ملاحظة للمدير (اختياري)',
        confirmLabel: 'إرسال الطلب',
      );
      if (res == null) return;
      note = res;
    }
    if (!mounted) return;
    setState(() => _busyForm = d.key);
    try {
      final r = await app.setFormStatus(p.id, d.key, s, note: note);
      if (!mounted) return;
      showToast(
        context,
        switch (r) {
          'pending' => 'أُرسل طلب الاعتماد إلى مدير المكتب',
          'unchanged' => 'لم يتغير شيء',
          _ => 'حُفظت حالة «${d.name}»: ${s.label}',
        },
      );
      _loadSide();
    } catch (e) {
      if (mounted) showToast(context, friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _busyForm = null);
    }
  }

  Future<void> _decide(ChangeRequest r, bool approve) async {
    final app = AppScope.read(context);
    var note = '';
    if (!approve) {
      final res = await textInputDialog(context, title: 'رفض الطلب', label: 'سبب الرفض', confirmLabel: 'رفض الطلب', required: true);
      if (res == null) return;
      note = res;
    }
    try {
      await app.decideRequest(r.id, approve, note: note);
      if (mounted) showToast(context, approve ? 'اعتُمد الطلب وطُبّقت الحالة' : 'رُفض الطلب');
      _loadSide();
    } catch (e) {
      if (mounted) showToast(context, friendlyError(e), error: true);
    }
  }

  Future<void> _withdraw(ChangeRequest r) async {
    try {
      await AppScope.read(context).withdrawRequest(r.id);
      if (mounted) showToast(context, 'سُحب الطلب');
    } catch (e) {
      if (mounted) showToast(context, friendlyError(e), error: true);
    }
  }

  /// النسخة السابقة لقاعدة البيانات: خانة نصية واحدة لكل نوع.
  Future<void> _saveLegacyEngineer(Project p, FormDef d) async {
    final field = d.engineerField;
    if (field == null) return;
    final value = _eng[field]!.text.trim();
    _engFocus[field]!.unfocus();
    if (value == p.engineer(field)) return;
    try {
      await AppScope.read(context).setEngineer(p.id, d.key, value);
      if (mounted) showToast(context, 'حُفظ ${engineerFieldLabel(field)}');
    } catch (e) {
      if (mounted) showToast(context, friendlyError(e), error: true);
    }
  }

  // ---------------------------------------------------------------
  // الإجراءات: العقد والأعمال والمهندسون والدمج
  // ---------------------------------------------------------------
  Future<void> _editContractNo(AppState app, Project p) async {
    final v = await textInputDialog(
      context,
      title: 'رقم العقد',
      message: 'رقم العقد كما يسجّله مكتب العقود. تُربط به كل أعمال الشركات في هذا العقد. اتركه فارغاً لإزالته.',
      label: 'رقم العقد',
      confirmLabel: 'حفظ',
      initial: p.contractNo,
      multiline: false,
      textDirection: TextDirection.ltr,
    );
    if (v == null || v.trim() == p.contractNo) return;
    try {
      await app.setContractNo(p.id, v);
      if (mounted) showToast(context, v.trim().isEmpty ? 'أُزيل رقم العقد' : 'حُفظ رقم العقد ${v.trim()}');
      _loadSide();
    } catch (e) {
      if (mounted) showToast(context, friendlyError(e), error: true);
    }
  }

  Future<void> _editWork(AppState app, Project p, ContractWork? w) async {
    final ok = await showDialog<bool>(context: context, builder: (_) => _WorkDialog(app: app, project: p, work: w));
    if (ok == true && mounted) {
      showToast(context, w == null ? 'أُضيف العمل إلى العقد' : 'حُفظ العمل');
      _loadSide();
    }
  }

  Future<void> _deleteWork(AppState app, ContractWork w) async {
    final ok = await confirmDialog(
      context,
      title: 'حذف العمل؟',
      message: 'سيُحذف «${w.display.isEmpty ? w.refNo : w.display}» من العقد، وتُفك ارتباطات المهندسين به. يبقى الأثر في سجل التدقيق.',
      confirmLabel: 'حذف',
      danger: true,
    );
    if (!ok) return;
    try {
      await app.deleteWork(w.id);
      if (mounted) showToast(context, 'حُذف العمل');
      _loadSide();
    } catch (e) {
      if (mounted) showToast(context, friendlyError(e), error: true);
    }
  }

  Future<void> _editEngineer(AppState app, Project p, String kind, ContractEngineer? e) async {
    final ok = await showDialog<bool>(context: context, builder: (_) => _EngineerDialog(app: app, project: p, kind: kind, engineer: e));
    if (ok == true && mounted) {
      showToast(context, e == null ? 'سُجّل تكليف ${engineerKindLabel(kind)}' : 'حُفظ التكليف');
      _loadSide();
    }
  }

  Future<void> _deleteEngineer(AppState app, ContractEngineer e) async {
    final ok = await confirmDialog(
      context,
      title: 'إلغاء تكليف ${e.name}؟',
      message: 'يُحذف تكليف ${engineerKindLabel(e.kind)}${e.assignNo.isEmpty ? '' : ' رقم ${e.assignNo}'} من هذا العقد. يبقى الأثر في سجل التدقيق.',
      confirmLabel: 'إلغاء التكليف',
      danger: true,
    );
    if (!ok) return;
    try {
      await app.deleteEngineer(e.id);
      if (mounted) showToast(context, 'أُلغي التكليف');
      _loadSide();
    } catch (err) {
      if (mounted) showToast(context, friendlyError(err), error: true);
    }
  }

  Future<void> _openMerge(AppState app, Project p) async {
    final ids = await showModalBottomSheet<List<String>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _MergeSheet(app: app, target: p),
    );
    if (ids == null || ids.isEmpty || !mounted) return;
    final names = ids.map((id) => app.project(id)?.contractTitle ?? '').where((s) => s.isNotEmpty).join('، ');
    final ok = await confirmDialog(
      context,
      title: 'دمج ${ids.length} في ${p.contractTitle}؟',
      message: 'تنتقل أعمال ($names) ومهندسوها إلى هذا العقد، وتُجمع قيمها المالية، والنماذج التي لم تبدأ هنا تأخذ حالتها منها. '
          'تُتابع الدورة المستندية بعدها على العقد وحده، وتختفي السجلات المدمجة من القائمة. يستطيع مدير المكتب فك الدمج.',
      confirmLabel: 'دمج',
    );
    if (!ok || !mounted) return;
    try {
      final n = await app.mergeContracts(p.id, ids);
      if (mounted) showToast(context, 'دُمج $n في ${p.contractTitle}');
      _loadSide();
    } catch (e) {
      if (mounted) showToast(context, friendlyError(e), error: true);
    }
  }

  Future<void> _unmerge(AppState app, Map<String, dynamic> m) async {
    final ok = await confirmDialog(
      context,
      title: 'فك دمج ${_sourceLabel(m)}؟',
      message: 'تعود أعماله ومهندسوه إلى سجلّه، وتُطرح قيمه المالية من العقد، ويظهر في القائمة من جديد.',
      confirmLabel: 'فك الدمج',
    );
    if (!ok) return;
    try {
      await app.unmergeContract(m['id'].toString());
      if (mounted) showToast(context, 'فُك الدمج');
      _loadSide();
    } catch (e) {
      if (mounted) showToast(context, friendlyError(e), error: true);
    }
  }

  static String _sourceLabel(Map<String, dynamic> m) {
    String s(String k) => (m[k] ?? '').toString().trim();
    final parts = [
      if (s('contract_no').isNotEmpty) 'عقد ${s('contract_no')}',
      if (s('assign_no').isNotEmpty) 'تكليف ${s('assign_no')}',
      if (s('name').isNotEmpty) s('name'),
    ];
    return parts.isEmpty ? 'سجل مدمج' : parts.join(' · ');
  }

  String? _originLabel(String? originId) {
    if (originId == null) return null;
    for (final m in _merged) {
      if (m['id'].toString() == originId) {
        final a = (m['assign_no'] ?? '').toString();
        return a.isNotEmpty ? 'تكليف $a' : _sourceLabel(m);
      }
    }
    return 'سجل آخر';
  }

  // ---------------------------------------------------------------
  // الإجراءات: المالية والملاحظات
  // ---------------------------------------------------------------
  Future<void> _saveFinance(Project p) async {
    final app = AppScope.read(context);
    final values = <String, double?>{};
    for (final f in _finFields) {
      if (f == 'executed_value' && !app.v3Ready) continue;
      final r = parseMoney(_fin[f]!.text);
      if (!r.ok) {
        showToast(context, 'اكتب مبلغاً صحيحاً في «${projectFieldLabels[f]}»', error: true);
        return;
      }
      values[f] = r.value;
    }
    FocusScope.of(context).unfocus();
    setState(() => _busyFin = true);
    try {
      await app.setContractFinance(
        p.id,
        contractValue: values['contract_value'],
        executedValue: values['executed_value'],
        paymentFirst: values['payment_first'],
        paymentSecond: values['payment_second'],
        paymentFinal: values['payment_final'],
        deductions: values['deductions'],
      );
      _finDirty = false;
      _syncControllers();
      if (mounted) showToast(context, 'حُفظت البيانات المالية للعقد');
      _loadSide();
    } catch (e) {
      if (mounted) showToast(context, friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _busyFin = false);
    }
  }

  Future<void> _setGuaranteeNa(Project p, bool na) async {
    if (na == p.guaranteeInitialNa) return;
    setState(() => _busyGna = true);
    try {
      await AppScope.read(context).setGuaranteeInitialNa(p.id, na);
      if (mounted) {
        showToast(context, na ? 'سُجّل أن الضمان الابتدائي لا ينطبق على العقد' : 'الضمان الابتدائي ينطبق ويُحسب من الأعمال المنفذة');
      }
      _loadSide();
    } catch (e) {
      if (mounted) showToast(context, friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _busyGna = false);
    }
  }

  void _cancelFinance() {
    FocusScope.of(context).unfocus();
    setState(() => _finDirty = false);
    _syncControllers();
  }

  Future<void> _saveNotes(Project p) async {
    _notesFocus.unfocus();
    final v = _notes.text.trim();
    if (v == p.notes) return;
    try {
      await AppScope.read(context).updateNotes(p.id, v);
      if (mounted) showToast(context, 'حُفظت الملاحظات');
    } catch (e) {
      if (mounted) showToast(context, friendlyError(e), error: true);
    }
  }

  Future<void> _addQualityNote(Project p) async {
    final body = _qnote.text.trim();
    if (body.isEmpty) return;
    setState(() => _busyNote = true);
    try {
      await AppScope.read(context).addQualityNote(p.id, body);
      _qnote.clear();
      await _loadSide();
      if (mounted) showToast(context, 'أُضيفت الملاحظة');
    } catch (e) {
      if (mounted) showToast(context, friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _busyNote = false);
    }
  }

  Future<void> _delete(Project p) async {
    final ok = await confirmDialog(
      context,
      title: 'حذف ${p.contractTitle}؟',
      message: 'سيُحذف العقد وأعماله ومهندسوه وحالات نماذجه وطلباته لكل المستخدمين، ولا يمكن التراجع. يبقى أثر الحذف في سجل التدقيق.',
      confirmLabel: 'حذف نهائياً',
      danger: true,
    );
    if (!ok || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final nav = Navigator.of(context);
    try {
      await AppScope.read(context).deleteProject(p.id);
      messenger.showSnackBar(const SnackBar(content: Text('حُذف العقد'), behavior: SnackBarBehavior.floating));
      nav.pop();
    } catch (e) {
      if (mounted) showToast(context, friendlyError(e), error: true);
    }
  }

  // ---------------------------------------------------------------
  // الواجهة
  // ---------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final p = app.project(widget.projectId);
    if (p == null) {
      return Scaffold(
        appBar: brandAppBar(context, title: Text(term('contract'))),
        body: const Center(
          child: EmptyState(title: 'العقد غير موجود', message: 'ربما حُذف أو دُمج في عقد آخر. ارجع إلى القائمة.'),
        ),
      );
    }
    // أساسيات العقد وحدها (الترحيل 34): نماذج المستخدم المسندة فيه دون بقية الدورة وتفاصيل العقد
    if (p.limited) return _limitedView(context, app, p);
    final pr = app.progressOf(p);
    final width = MediaQuery.sizeOf(context).width;
    final side = math.max(16.0, (width - 900) / 2);

    final sections = <Widget>[
      _hero(context, app, p, pr),
      if (app.v3Ready) _worksCard(context, app, p),
      if (app.v3Ready) _engineersCard(context, app, p),
      _financeCard(context, app, p),
      if (app.v4Ready)
        ExtractsCard(app: app, project: p, originLabel: _originLabel, onChanged: _loadSide),
      if (app.v4Ready)
        VariationsCard(app: app, project: p, originLabel: _originLabel, onChanged: _loadSide),
      _cycleCard(context, app, p, pr),
      if (app.v7Ready) ProjectTrackCard(project: p),
      // مستندات الشؤون الفنية للعقد: لمكتب المدير وللشؤون الفنية وللقسم المشرف عليه (الترحيل 34)
      if (app.v8Ready && (!app.isolated || app.seesSection('docs') || (app.scope?.supervised.contains(p.id) ?? false)))
        ContractDocsCard(project: p),
      if (app.activeFields.isNotEmpty) _extraCard(context, app, p),
      _notesCard(context, app, p),
      if (app.isDirector || app.settings.feature('quality_notes')) _qualityCard(context, app, p),
      _historyCard(context, app, p),
    ];

    return Scaffold(
      appBar: brandAppBar(
        context,
        title: Text(p.contractTitle),
        actions: [
          if (app.canManageProjects)
            IconButton(tooltip: 'تعديل بيانات العقد', icon: const Icon(Icons.edit_outlined), onPressed: () => openProjectEditor(context, p)),
          if (app.isDirector)
            IconButton(tooltip: 'حذف العقد', icon: const Icon(Icons.delete_outline), onPressed: () => _delete(p)),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          await app.loadAll();
          await _loadSide();
        },
        child: ListView(
          padding: EdgeInsets.fromLTRB(side, 16, side, 36),
          children: staggered([
            for (final s in sections) Padding(padding: const EdgeInsets.only(bottom: 14), child: s),
          ], stepMs: 70, maxSteps: 6),
        ),
      ),
    );
  }

  // ---- عقد بأساسياته وحدها: نماذج المستخدم المسندة فيه ----
  Widget _limitedView(BuildContext context, AppState app, Project p) {
    final sem = Sem.of(context);
    final cs = Theme.of(context).colorScheme;
    final width = MediaQuery.sizeOf(context).width;
    final side = math.max(16.0, (width - 900) / 2);
    final forms = [for (final d in app.formDefs) if (app.formAssigned(p, d)) d];
    final pr = app.progressOf(p);
    Widget fact(IconData icon, String k, String v) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(icon, size: 17, color: sem.muted),
            const SizedBox(width: 8),
            SizedBox(width: 108, child: Text(k, style: TextStyle(color: sem.muted, fontSize: 13))),
            Expanded(child: Text(v.trim().isEmpty ? '—' : v, style: const TextStyle(fontWeight: FontWeight.w600))),
          ]),
        );
    final sections = <Widget>[
      Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: sem.rule),
          gradient: LinearGradient(
            begin: AlignmentDirectional.topStart,
            end: AlignmentDirectional.bottomEnd,
            colors: [cs.primaryContainer, sem.surface],
          ),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          ContractTag(p, large: true),
          const SizedBox(height: 10),
          Text(p.title, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),
          fact(Icons.tag_rounded, 'رقم التكليف', p.assignNo),
          fact(Icons.qr_code_2_rounded, 'رمز المشروع', p.code),
          fact(Icons.account_balance_outlined, 'مالك المشروع', p.owner),
          fact(Icons.business_outlined, term('company'), p.company),
          fact(Icons.apartment_rounded, 'القسم المشرف', app.departmentName(p.department)),
        ]),
      ),
      const InfoBanner(
        icon: Icons.lock_outline_rounded,
        text: 'تظهر لك أساسيات العقد ونماذجك المسندة فيه وحدها. تفاصيله وماليته وبقية دورته لمكتب المدير ومكتب العقود والقسم المشرف عليه.',
      ),
      SectionCard(
        title: 'نماذجك في هذا العقد',
        icon: Icons.fact_check_outlined,
        subtitle: 'ما أُسند إلى قسمك من الدورة المستندية. النماذج الحساسة تُرفع لاعتماد مدير المكتب.',
        child: forms.isEmpty
            ? Text('لا نماذج مسندة إليك في هذا العقد.', style: TextStyle(color: sem.muted))
            : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                for (final d in forms) Padding(padding: const EdgeInsets.only(bottom: 8), child: _formRow(context, app, p, pr, d, showNext: false)),
              ]),
      ),
      if (app.canAddQualityNote && (app.isDirector || app.settings.feature('quality_notes'))) _qualityCard(context, app, p),
    ];
    return Scaffold(
      appBar: brandAppBar(context, title: Text(p.contractTitle)),
      body: RefreshIndicator(
        onRefresh: () async {
          await app.loadAll();
          await _loadSide();
        },
        child: ListView(
          padding: EdgeInsets.fromLTRB(side, 16, side, 36),
          children: staggered([
            for (final s in sections) Padding(padding: const EdgeInsets.only(bottom: 14), child: s),
          ], stepMs: 70, maxSteps: 6),
        ),
      ),
    );
  }

  // ---- رأس العقد ----
  Widget _hero(BuildContext context, AppState app, Project p, Progress pr) {
    final sem = Sem.of(context);
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final works = app.worksOf(p.id);
    final engs = app.engineersOf(p.id);
    final companies = app.companiesOf(p);
    final sizes = [for (var s = 0; s < stageNames.length; s++) app.formDefs.where((d) => d.stage == s).length];
    final ringColor = pr.cycle == CycleState.complete ? sem.ok : cs.primary;

    Widget fact(IconData icon, String k, String v) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 17, color: sem.muted),
              const SizedBox(width: 8),
              SizedBox(width: 108, child: Text(k, style: TextStyle(color: sem.muted, fontSize: 13))),
              Expanded(child: Text(v.trim().isEmpty ? '—' : v, style: const TextStyle(fontWeight: FontWeight.w600))),
            ],
          ),
        );

    final facts = <Widget>[
      fact(Icons.tag_rounded, 'رقم التكليف', p.assignNo),
      fact(Icons.qr_code_2_rounded, 'رمز المشروع', p.code),
      fact(Icons.account_balance_outlined, 'مالك المشروع', p.owner),
      fact(Icons.business_outlined, companies.length > 1 ? 'الشركات' : term('company'), companies.join('، ')),
      fact(Icons.apartment_rounded, 'القسم المشرف', app.departmentName(p.department)),
      if (app.v3Ready) fact(Icons.account_tree_outlined, 'الأعمال', works.isEmpty ? '' : '${works.length}'),
      if (app.v3Ready)
        fact(Icons.engineering_outlined, 'المهندسون', [
          for (final k in engineerKinds)
            if (engs.any((e) => e.kind == k)) '${engineerKindLabel(k).replaceFirst('المهندس ', '').replaceFirst('مهندس ', '')} ${engs.where((e) => e.kind == k).length}',
        ].join(' · ')),
    ];

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(color: sem.surface, borderRadius: BorderRadius.circular(20), border: Border.all(color: sem.rule)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: AlignmentDirectional.topStart,
                end: AlignmentDirectional.bottomEnd,
                colors: [cs.primaryContainer, sem.surface],
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Hero(
                            tag: 'contract-${p.id}',
                            child: Material(type: MaterialType.transparency, child: ContractTag(p, large: true)),
                          ),
                          if (app.canEditContractNo(p))
                            Tooltip(
                              message: p.contractNo.isEmpty ? 'إدخال رقم العقد' : 'تعديل رقم العقد',
                              child: InkWell(
                                borderRadius: BorderRadius.circular(8),
                                onTap: () => _editContractNo(app, p),
                                child: Padding(
                                  padding: const EdgeInsets.all(4),
                                  child: Icon(p.contractNo.isEmpty ? Icons.add_circle_outline : Icons.edit_outlined, size: 19, color: cs.primary),
                                ),
                              ),
                            ),
                          CyclePill(pr.cycle),
                          if (_merged.isNotEmpty)
                            ToneBadge('يضم ${_merged.length} مدمجاً', color: cs.primary, icon: Icons.call_merge_rounded),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(p.title, style: t.titleLarge?.copyWith(fontWeight: FontWeight.w700, height: 1.45)),
                      const SizedBox(height: 4),
                      Text.rich(TextSpan(children: [
                        TextSpan(text: 'المرحلة: ', style: TextStyle(color: sem.muted)),
                        TextSpan(text: stageName(pr.stage), style: const TextStyle(fontWeight: FontWeight.w700)),
                        if (pr.next != null) TextSpan(text: '  ·  التالي: ', style: TextStyle(color: sem.muted)),
                        if (pr.next != null) TextSpan(text: pr.next!.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                      ])),
                    ],
                  ),
                ),
                const SizedBox(width: 14),
                RingProgress(
                  value: pr.pct,
                  size: 96,
                  stroke: 10,
                  color: ringColor,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AnimatedCount(
                        value: pr.pct * 100,
                        format: (v) => '${v.round()}%',
                        style: t.titleLarge?.copyWith(fontWeight: FontWeight.w800, fontFeatures: const [FontFeature.tabularFigures()]),
                      ),
                      Text('إنجاز', style: TextStyle(fontSize: 11, color: sem.muted)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                CycleStrip(defs: app.formDefs, cells: pr.cells, height: 12),
                const SizedBox(height: 4),
                Row(
                  children: [
                    for (var i = 0; i < sizes.length; i++)
                      if (sizes[i] > 0)
                        Expanded(
                          flex: sizes[i],
                          child: Text(stageNames[i],
                              textAlign: TextAlign.center,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 10.5, color: sem.muted)),
                        ),
                  ],
                ),
                const SizedBox(height: 10),
                Legend(items: [
                  (sem.ok, '${FormStatus.done.label} ${pr.done}'),
                  (sem.wip, '${FormStatus.wip.label} ${pr.wip}'),
                  (sem.statusColor(FormStatus.todo), '${FormStatus.todo.label} ${pr.todo}'),
                  (sem.na, '${FormStatus.na.label} ${pr.na}'),
                ]),
                Divider(height: 26, color: sem.rule),
                LayoutBuilder(builder: (context, c) {
                  if (c.maxWidth < 620) return Column(children: facts);
                  final half = (facts.length / 2).ceil();
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: Column(children: facts.sublist(0, half))),
                      const SizedBox(width: 18),
                      Expanded(child: Column(children: facts.sublist(half))),
                    ],
                  );
                }),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ---- أعمال العقد ----
  Widget _worksCard(BuildContext context, AppState app, Project p) {
    final sem = Sem.of(context);
    final works = app.worksOf(p.id);
    final canEdit = app.canEditWorks(p);
    final canMerge = app.canMerge(p);
    return SectionCard(
      title: term('works'),
      icon: Icons.account_tree_outlined,
      subtitle: 'أعمال الشركات المرتبطة برقم هذا العقد، لكل عمل شركته ورقمه.',
      trailing: canEdit
          ? IconButton.filledTonal(tooltip: 'إضافة عمل', onPressed: () => _editWork(app, p, null), icon: const Icon(Icons.add_rounded))
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (works.isEmpty)
            Text('لا توجد أعمال مسجلة لهذا العقد بعد.', style: TextStyle(color: sem.muted))
          else
            ...staggered([
              for (var i = 0; i < works.length; i++)
                Padding(padding: const EdgeInsets.only(bottom: 8), child: _workTile(context, app, p, works[i], i, canEdit)),
            ], stepMs: 45),
          if (canMerge) ...[
            const SizedBox(height: 4),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: OutlinedButton.icon(
                onPressed: () => _openMerge(app, p),
                icon: const Icon(Icons.call_merge_rounded),
                label: const Text('دمج أعمال من عقود أخرى'),
              ),
            ),
          ],
          if (_merged.isNotEmpty) ...[
            Divider(height: 28, color: sem.rule),
            const Text('السجلات المدمجة في هذا العقد', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            for (final m in _merged) _mergedTile(context, app, m),
          ],
        ],
      ),
    );
  }

  Widget _meta(BuildContext context, IconData icon, String text) {
    final sem = Sem.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: sem.muted),
        const SizedBox(width: 4),
        Flexible(child: Text(text, style: TextStyle(fontSize: 12.5, color: sem.muted))),
      ],
    );
  }

  Widget _workTile(BuildContext context, AppState app, Project p, ContractWork w, int i, bool canEdit) {
    final sem = Sem.of(context);
    final cs = Theme.of(context).colorScheme;
    final origin = w.merged ? _originLabel(w.originProject) : null;
    final engs = app.engineersOf(p.id).where((e) => e.workId == w.id).toList();
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 6, 12),
      decoration: BoxDecoration(color: sem.surface2, borderRadius: BorderRadius.circular(14)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 30,
            height: 30,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: cs.primaryContainer, shape: BoxShape.circle),
            child: Text('${i + 1}', style: TextStyle(color: cs.onPrimaryContainer, fontWeight: FontWeight.w700)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(w.title.isEmpty ? 'عمل بدون وصف' : w.title, style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 12,
                  runSpacing: 4,
                  children: [
                    if (w.company.isNotEmpty) _meta(context, Icons.business_outlined, w.company),
                    if (w.refNo.isNotEmpty) _meta(context, Icons.tag_rounded, 'الرقم ${w.refNo}'),
                    if (engs.isNotEmpty) _meta(context, Icons.engineering_outlined, engs.map((e) => e.name).join('، ')),
                  ],
                ),
                if (app.v4Ready && (w.contractValue != null || w.executedValue != null)) ...[
                  const SizedBox(height: 8),
                  Row(children: [
                    Expanded(
                      child: Text(
                        'القيمة ${fmtMoney(w.contractValue)} · المنفذ ${fmtMoney(w.executedValue)}',
                        style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, fontFeatures: [FontFeature.tabularFigures()]),
                      ),
                    ),
                    if ((w.contractValue ?? 0) > 0 && w.executedValue != null)
                      Text(pctText((w.executedValue! / w.contractValue!), digits: 1), style: TextStyle(fontSize: 12, color: sem.muted)),
                  ]),
                  if ((w.contractValue ?? 0) > 0 && w.executedValue != null) ...[
                    const SizedBox(height: 4),
                    AnimatedMeter(
                      value: (w.executedValue! / w.contractValue!).clamp(0, 1).toDouble(),
                      color: w.executedValue! > w.contractValue! ? sem.danger : sem.ok,
                      height: 6,
                    ),
                  ],
                ],
                if (w.notes.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(w.notes, style: TextStyle(color: sem.muted, fontSize: 12.5)),
                  ),
                if (origin != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: ToneBadge('مدمج من $origin', color: cs.primary, icon: Icons.call_merge_rounded),
                  ),
              ],
            ),
          ),
          if (canEdit || app.canEditFinanceItems(p))
            PopupMenuButton<String>(
              tooltip: 'خيارات العمل',
              onSelected: (v) async {
                if (v == 'edit') {
                  _editWork(app, p, w);
                } else if (v == 'values') {
                  final ok = await showWorkValuesDialog(context, app, p, w);
                  if (ok && mounted) {
                    showToast(context, 'حُفظت قيم البند');
                    _loadSide();
                  }
                } else {
                  _deleteWork(app, w);
                }
              },
              itemBuilder: (_) => [
                if (app.canEditFinanceItems(p))
                  const PopupMenuItem(value: 'values', child: ListTile(leading: Icon(Icons.price_change_outlined), title: Text('قيم البند'))),
                if (canEdit)
                  const PopupMenuItem(value: 'edit', child: ListTile(leading: Icon(Icons.edit_outlined), title: Text('تعديل'))),
                if (canEdit && !w.merged)
                  const PopupMenuItem(value: 'delete', child: ListTile(leading: Icon(Icons.delete_outline), title: Text('حذف'))),
              ],
            ),
        ],
      ),
    );
  }

  Widget _mergedTile(BuildContext context, AppState app, Map<String, dynamic> m) {
    final sem = Sem.of(context);
    final at = DateTime.tryParse((m['merged_at'] ?? '').toString());
    final company = (m['company'] ?? '').toString();
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(Icons.inventory_2_outlined, color: sem.muted),
      title: Text(_sourceLabel(m), style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text([if (company.isNotEmpty) company, if (at != null) 'دُمج ${fmtDate(at)}'].join(' · ')),
      trailing: app.canUnmerge
          ? TextButton.icon(
              onPressed: () => _unmerge(app, m),
              icon: const Icon(Icons.call_split_rounded, size: 18),
              label: const Text('فك الدمج'),
            )
          : null,
    );
  }

  // ---- المهندسون وأرقام تكليفهم ----
  static IconData _kindIcon(String kind) => switch (kind) {
        'sup' => Icons.manage_accounts_outlined,
        'qty' => Icons.calculate_outlined,
        'fol' => Icons.trending_up_rounded,
        _ => Icons.health_and_safety_outlined,
      };

  Widget _engineersCard(BuildContext context, AppState app, Project p) {
    final sem = Sem.of(context);
    final all = app.engineersOf(p.id);
    return SectionCard(
      title: term('engineers'),
      icon: Icons.engineering_outlined,
      subtitle: 'أكثر من مهندس لكل اختصاص في العقد نفسه، ولكلٍّ رقم تكليفه.',
      trailing: Text('${all.length} تكليف', style: TextStyle(color: sem.muted, fontSize: 12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var k = 0; k < engineerKinds.length; k++) ...[
            if (k > 0) Divider(height: 24, color: sem.rule),
            _kindBlock(context, app, p, engineerKinds[k]),
          ],
        ],
      ),
    );
  }

  Widget _kindBlock(BuildContext context, AppState app, Project p, String kind) {
    final sem = Sem.of(context);
    final cs = Theme.of(context).colorScheme;
    final list = app.engineersOf(p.id, kind);
    final can = app.canAssignEngineer(p, kind);
    final form = app.engineerFormOf(kind);
    // «لا ينطبق» حالة نموذج التكليف المقابل في الدورة المستندية؛ يُعرض لكل الأنواع ويُتاح زرّه لمهندس السلامة
    final na = list.isEmpty && app.engineerNa(p, kind);
    final canNa = can && form != null && kind == 'saf' && app.pendingFor(p.id, form.key) == null;
    final busyNa = form != null && _busyForm == form.key;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(_kindIcon(kind), size: 20, color: na ? sem.muted : cs.primary),
            const SizedBox(width: 8),
            Expanded(child: Text(engineerKindPlural(kind), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5))),
            if (list.isNotEmpty) ToneBadge('${list.length}', color: cs.primary),
            if (na) ToneBadge('لا ينطبق', color: sem.muted, icon: Icons.block_outlined),
            if (can && !na) ...[
              const SizedBox(width: 4),
              TextButton.icon(
                onPressed: () => _editEngineer(app, p, kind, null),
                icon: const Icon(Icons.person_add_alt_1_outlined, size: 18),
                label: const Text('تكليف'),
              ),
            ],
          ],
        ),
        const SizedBox(height: 6),
        if (na)
          Wrap(
            spacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text('سُجّل أن ${engineerKindLabel(kind)} لا ينطبق على هذا العقد.', style: TextStyle(color: sem.muted, fontSize: 12.5)),
              if (canNa)
                TextButton.icon(
                  onPressed: busyNa ? null : () => _change(p, form!, FormStatus.todo),
                  icon: const Icon(Icons.undo_rounded, size: 18),
                  label: const Text('يلزم تكليف'),
                ),
            ],
          )
        else if (list.isEmpty)
          Wrap(
            spacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text('لم يُكلَّف أحد بعد.', style: TextStyle(color: sem.muted, fontSize: 12.5)),
              if (canNa)
                TextButton.icon(
                  onPressed: busyNa ? null : () => _change(p, form!, FormStatus.na),
                  icon: const Icon(Icons.block_outlined, size: 18),
                  label: const Text('لا ينطبق'),
                ),
            ],
          )
        else
          for (final e in list) _engineerTile(context, app, p, e, can),
        if (!can && form != null)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text('يكلّف: ${app.responsibleText(p, form)}', style: TextStyle(fontSize: 11.5, color: sem.muted)),
          ),
      ],
    );
  }

  Widget _engineerTile(BuildContext context, AppState app, Project p, ContractEngineer e, bool can) {
    final sem = Sem.of(context);
    final w = app.work(e.workId);
    final parts = [
      if (e.assignedOn != null) 'بتاريخ ${dayText(e.assignedOn)}',
      if (w != null) 'العمل: ${w.title.isEmpty ? w.company : w.title}',
      if (e.merged) 'مدمج من ${_originLabel(e.originProject)}',
    ];
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: sem.surface2,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: can ? () => _editEngineer(app, p, e.kind, e) : null,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 4, 8),
            child: Row(
              children: [
                InitialsAvatar(name: e.name, size: 34),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(e.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                      if (parts.isNotEmpty) Text(parts.join(' · '), style: TextStyle(color: sem.muted, fontSize: 12)),
                      if (e.notes.isNotEmpty) Text(e.notes, style: TextStyle(color: sem.muted, fontSize: 12)),
                    ],
                  ),
                ),
                if (e.assignNo.isNotEmpty)
                  Tooltip(message: 'رقم التكليف', child: NoTag(e.assignNo))
                else
                  Text('بلا رقم تكليف', style: TextStyle(color: sem.muted, fontSize: 11.5)),
                if (can)
                  IconButton(
                    tooltip: 'إلغاء التكليف',
                    icon: const Icon(Icons.close_rounded, size: 18),
                    onPressed: () => _deleteEngineer(app, e),
                  )
                else
                  const SizedBox(width: 8),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ---- البيانات المالية ----
  Widget _financeCard(BuildContext context, AppState app, Project p) {
    final sem = Sem.of(context);
    final canEdit = app.canEditFinance(p);
    final contractDef = app.formDef(contractFormKey);
    final v3 = app.v3Ready;
    double? val(String f, double? stored) {
      final r = parseMoney(_fin[f]!.text);
      return r.ok ? r.value : stored;
    }

    final v4 = app.v4Ready;
    final lockValue = v4 && p.valueFromItems;
    final lockExec = v4 && p.executedComputed;
    final contract = lockValue ? p.contractValue : val('contract_value', p.contractValue);
    final executed = lockExec ? p.executedValue : val('executed_value', p.executedValue);
    final base = v3 ? executed : contract;
    final gNa = p.guaranteeInitialNa;
    final gInitial = gNa || base == null ? null : roundMoney(base * guaranteeInitialRate);
    final guaranteeRule = gNa
        ? 'الضمان الابتدائي لا ينطبق على هذا العقد، ويُحسب النهائي (${rateText(guaranteeFinalRate)}) تلقائياً من '
        : 'يُحسب الضمان الابتدائي (${rateText(guaranteeInitialRate)}) والنهائي (${rateText(guaranteeFinalRate)}) تلقائياً من ';
    final gFinal = base == null ? null : roundMoney(base * guaranteeFinalRate);
    final pays = [val('payment_first', p.paymentFirst), val('payment_second', p.paymentSecond), val('payment_final', p.paymentFinal)];
    final paid = pays.any((v) => v != null) ? roundMoney(pays.fold<double>(0, (a, v) => a + (v ?? 0))) : null;
    final ratio = contract != null && executed != null && contract > 0 ? executed / contract : null;
    const tabular = TextStyle(fontFeatures: [FontFeature.tabularFigures()]);

    Widget field(String f) {
      final r = parseMoney(_fin[f]!.text);
      final locked = (f == 'contract_value' && lockValue) || (f == 'executed_value' && lockExec);
      final helper = !locked
          ? null
          : f == 'contract_value'
              ? 'تُحسب من مجموع قيم البنود'
              : (p.executedSource == 'extracts' ? 'تُحسب من المستخلصات المعتمدة' : 'تُحسب من المنفذ في البنود');
      return TextField(
        controller: _fin[f],
        readOnly: !canEdit || locked,
        style: tabular,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        onChanged: (_) => setState(() => _finDirty = true),
        onSubmitted: (_) {
          if (canEdit && _finDirty) _saveFinance(p);
        },
        decoration: fieldDeco(projectFieldLabels[f]!, hint: canEdit ? '0' : '—', helper: helper, error: r.ok ? null : 'اكتب مبلغاً صحيحاً')
            .copyWith(
              suffixText: currencyLabel,
              prefixIcon: locked ? const Icon(Icons.functions_rounded, size: 18) : null,
              fillColor: locked ? sem.surface2 : null,
            ),
      );
    }

    Widget computed(String label, double? v, {String? text}) => InputDecorator(
          decoration: fieldDeco(label)
              .copyWith(suffixText: v == null || text != null ? null : currencyLabel, filled: true, fillColor: sem.surface2),
          child: Text(text ?? fmtMoney(v),
              style: text != null ? TextStyle(color: sem.muted, fontWeight: FontWeight.w700) : tabular.copyWith(fontWeight: FontWeight.w700)),
        );

    return SectionCard(
      title: term('finance'),
      icon: Icons.payments_outlined,
      trailing: Text('العملة: $currencyLabel', style: TextStyle(color: sem.muted, fontSize: 12)),
      child: LayoutBuilder(builder: (context, c) {
        final wide = c.maxWidth >= 520;
        Widget group(List<Widget> items) => wide
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var i = 0; i < items.length; i++) ...[
                    if (i > 0) const SizedBox(width: 10),
                    Expanded(child: items[i]),
                  ],
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < items.length; i++) ...[
                    if (i > 0) const SizedBox(height: 10),
                    items[i],
                  ],
                ],
              );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (v4) ...[
              ContractFinanceOverview(project: p),
              Divider(height: 28, color: sem.rule),
              Text('القيم اليدوية والدفعات', style: TextStyle(color: sem.muted, fontSize: 12.5, fontWeight: FontWeight.w600)),
              const SizedBox(height: 10),
            ],
            group([field('contract_value'), if (v3) field('executed_value')]),
            if (v3) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Text('نسبة الأعمال المنفذة', style: TextStyle(color: sem.muted, fontSize: 12.5)),
                  const Spacer(),
                  Text(ratio == null ? '—' : pctText(ratio, digits: 1), style: tabular.copyWith(fontWeight: FontWeight.w700)),
                ],
              ),
              const SizedBox(height: 6),
              AnimatedMeter(value: ratio ?? 0.0, color: (ratio ?? 0.0) > 1 ? sem.danger : sem.ok, height: 9),
              if (ratio != null && ratio > 1)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text('قيمة الأعمال المنفذة تتجاوز القيمة التعاقدية.', style: TextStyle(color: sem.danger, fontSize: 12)),
                )
              else if (ratio != null && contract != null && executed != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text('المتبقي من الأعمال التعاقدية: ${fmtMoney(roundMoney(contract - executed))} $currencyLabel',
                      style: TextStyle(color: sem.muted, fontSize: 12)),
                ),
            ],
            const SizedBox(height: 14),
            group([field('payment_first'), field('payment_second'), field('payment_final')]),
            const SizedBox(height: 10),
            group([
              computed('الضمان الابتدائي ${rateText(guaranteeInitialRate)}', gInitial, text: gNa ? 'لا ينطبق' : null),
              computed('الضمان النهائي ${rateText(guaranteeFinalRate)}', gFinal),
            ]),
            if (app.naReady) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 12,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text('الضمان الابتدائي على هذا العقد', style: TextStyle(color: sem.muted, fontSize: 12.5)),
                  SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(value: false, label: Text('ينطبق'), icon: Icon(Icons.verified_outlined, size: 18)),
                      ButtonSegment(value: true, label: Text('لا ينطبق'), icon: Icon(Icons.block_outlined, size: 18)),
                    ],
                    selected: {gNa},
                    showSelectedIcon: false,
                    onSelectionChanged: canEdit && !_busyGna ? (sel) => _setGuaranteeNa(p, sel.first) : null,
                  ),
                  if (_busyGna) const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                ],
              ),
            ],
            const SizedBox(height: 10),
            group([field('deductions'), computed(v4 ? 'الدفعات المسجلة يدوياً' : 'إجمالي الدفعات', paid)]),
            const SizedBox(height: 8),
            Text(
              '$guaranteeRule${v3 ? 'قيمة الأعمال المنفذة' : 'قيمة التعاقد'}.'
              '${!canEdit && contractDef != null ? ' يحدّث البيانات المالية: ${app.responsibleText(p, contractDef)}.' : ''}',
              style: TextStyle(fontSize: 11.5, color: sem.muted),
            ),
            AnimatedSize(
              duration: Motion.of(context, 260),
              curve: Curves.easeOutCubic,
              child: canEdit && _finDirty
                  ? Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(onPressed: _busyFin ? null : _cancelFinance, child: const Text('تراجع')),
                          const SizedBox(width: 8),
                          FilledButton.icon(
                            onPressed: _busyFin ? null : () => _saveFinance(p),
                            icon: _busyFin
                                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                                : const Icon(Icons.check, size: 18),
                            label: const Text('حفظ البيانات المالية'),
                          ),
                        ],
                      ),
                    )
                  : const SizedBox(width: double.infinity),
            ),
          ],
        );
      }),
    );
  }

  // ---- نماذج الدورة المستندية ----
  Widget _cycleCard(BuildContext context, AppState app, Project p, Progress pr) {
    final sem = Sem.of(context);
    return SectionCard(
      title: term('cycle'),
      icon: Icons.fact_check_outlined,
      trailing: Text('${pr.done} من ${pr.required} مطلوب', style: TextStyle(color: sem.muted, fontSize: 12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var stage = 0; stage < stageNames.length; stage++) ..._stageBlock(context, app, p, pr, stage),
        ],
      ),
    );
  }

  List<Widget> _stageBlock(BuildContext context, AppState app, Project p, Progress pr, int stage) {
    final sem = Sem.of(context);
    final cs = Theme.of(context).colorScheme;
    final defs = app.formDefs.where((d) => d.stage == stage).toList();
    if (defs.isEmpty) return const [];
    final req = defs.where((d) => app.statusOf(p.id, d.key) != FormStatus.na).length;
    final dn = defs.where((d) => app.statusOf(p.id, d.key) == FormStatus.done).length;
    final isDone = pr.stage > stage;
    final isCur = pr.stage == stage;
    return [
      if (stage > 0) Divider(height: 28, color: sem.rule),
      Row(
        children: [
          AnimatedContainer(
            duration: Motion.of(context, 300),
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(shape: BoxShape.circle, color: isDone ? sem.ok : (isCur ? cs.primary : sem.todoSoft)),
            child: isDone
                ? const Icon(Icons.check_rounded, size: 17, color: Colors.white)
                : Text('${stage + 1}', style: TextStyle(color: isCur ? Colors.white : sem.muted, fontWeight: FontWeight.w700)),
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(stageNames[stage], style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15))),
          Text('$dn/$req', style: TextStyle(color: sem.muted, fontFeatures: const [FontFeature.tabularFigures()])),
        ],
      ),
      const SizedBox(height: 10),
      for (final d in defs) Padding(padding: const EdgeInsets.only(bottom: 8), child: _formRow(context, app, p, pr, d)),
    ];
  }

  Widget _formRow(BuildContext context, AppState app, Project p, Progress pr, FormDef d, {bool showNext = true}) {
    final sem = Sem.of(context);
    final cs = Theme.of(context).colorScheme;
    final status = app.statusOf(p.id, d.key);
    final canEdit = app.canEditForm(p, d);
    final isNext = showNext && pr.next?.key == d.key;
    final pending = app.pendingFor(p.id, d.key);
    final field = d.engineerField;

    return AnimatedContainer(
      duration: Motion.of(context, 320),
      curve: Curves.easeOutCubic,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isNext ? cs.primaryContainer.withAlpha(90) : sem.surface2,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: isNext ? cs.primary : Colors.transparent),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text(d.name, style: const TextStyle(fontWeight: FontWeight.w700))),
              if (d.sensitive)
                Tooltip(
                  message: 'نموذج حساس: تغييره يحتاج اعتماد مدير المكتب',
                  child: Padding(
                    padding: const EdgeInsetsDirectional.only(start: 6),
                    child: Icon(Icons.verified_user_outlined, size: 17, color: sem.wip),
                  ),
                ),
              if (isNext)
                Padding(
                  padding: const EdgeInsetsDirectional.only(start: 8),
                  child: Text('المستند التالي', style: TextStyle(color: cs.primary, fontWeight: FontWeight.w700, fontSize: 12)),
                ),
            ],
          ),
          const SizedBox(height: 8),
          StatusSelector(
            value: status,
            enabled: canEdit && (pending == null || app.isDirector),
            busy: _busyForm == d.key,
            onChanged: (s) => _change(p, d, s),
          ),
          if (!canEdit)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('يحدّثه: ${app.responsibleText(p, d)}', style: TextStyle(fontSize: 11.5, color: sem.muted)),
            ),
          if (pending != null) ...[
            const SizedBox(height: 8),
            _pendingBox(context, app, pending),
          ],
          if (field != null && app.v3Ready) ...[
            const SizedBox(height: 8),
            _engineerChips(context, app, p, field.substring(4)),
          ] else if (field != null) ...[
            const SizedBox(height: 8),
            TextField(
              controller: _eng[field],
              focusNode: _engFocus[field],
              readOnly: !canEdit,
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => _saveLegacyEngineer(p, d),
              decoration: fieldDeco(
                engineerFieldLabel(field),
                hint: canEdit ? 'اكتب الاسم ثم احفظ' : '—',
                suffix: canEdit && _eng[field]!.text.trim() != p.engineer(field)
                    ? IconButton(tooltip: 'حفظ', icon: const Icon(Icons.check), onPressed: () => _saveLegacyEngineer(p, d))
                    : null,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _pendingBox(BuildContext context, AppState app, ChangeRequest pending) {
    final sem = Sem.of(context);
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: sem.wipSoft, borderRadius: BorderRadius.circular(10)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.hourglass_top, size: 16, color: sem.wip),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'بانتظار اعتماد المدير: ${pending.fromStatus.label} ← ${pending.toStatus.label}',
                  style: TextStyle(color: sem.wip, fontWeight: FontWeight.w700, fontSize: 13),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'طلب ${app.personName(pending.requestedBy)} · ${fmtDate(pending.requestedAt)}${pending.note.isNotEmpty ? '\n${pending.note}' : ''}',
            style: const TextStyle(fontSize: 12.5),
          ),
          if (app.isDirector || pending.requestedBy == app.me?.id) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                if (app.isDirector) ...[
                  FilledButton.icon(
                    onPressed: () => _decide(pending, true),
                    icon: const Icon(Icons.check, size: 18),
                    label: const Text('اعتماد'),
                    style: FilledButton.styleFrom(backgroundColor: sem.ok, foregroundColor: Colors.white),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _decide(pending, false),
                    icon: const Icon(Icons.close, size: 18),
                    label: const Text('رفض'),
                    style: OutlinedButton.styleFrom(foregroundColor: sem.danger),
                  ),
                ],
                if (pending.requestedBy == app.me?.id)
                  TextButton.icon(
                    onPressed: () => _withdraw(pending),
                    icon: const Icon(Icons.undo, size: 18),
                    label: const Text('سحب الطلب'),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  /// المكلّفون من نوع واحد داخل صف نموذج التكليف.
  Widget _engineerChips(BuildContext context, AppState app, Project p, String kind) {
    final sem = Sem.of(context);
    final list = app.engineersOf(p.id, kind);
    final can = app.canAssignEngineer(p, kind);
    final na = list.isEmpty && app.engineerNa(p, kind);
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text('${engineerKindPlural(kind)}:', style: TextStyle(color: sem.muted, fontSize: 12.5)),
        if (list.isEmpty)
          Text(na ? 'لا ينطبق' : 'لم يُكلَّف أحد', style: TextStyle(color: sem.muted, fontSize: 12.5, fontWeight: FontWeight.w600)),
        for (final e in list)
          can
              ? ActionChip(
                  avatar: const Icon(Icons.person_outline, size: 16),
                  label: Text(e.assignNo.isEmpty ? e.name : '${e.name} · ${e.assignNo}'),
                  onPressed: () => _editEngineer(app, p, kind, e),
                )
              : Chip(
                  avatar: const Icon(Icons.person_outline, size: 16),
                  label: Text(e.assignNo.isEmpty ? e.name : '${e.name} · ${e.assignNo}'),
                ),
        if (can && !na)
          ActionChip(
            avatar: const Icon(Icons.add_rounded, size: 16),
            label: const Text('تكليف'),
            onPressed: () => _editEngineer(app, p, kind, null),
          ),
      ],
    );
  }

  /// الحقول الإضافية المعرّفة من لوحة التحكم، مجمّعة حسب المجموعة.
  Widget _extraCard(BuildContext context, AppState app, Project p) {
    final sem = Sem.of(context);
    final fields = [...app.activeFields]..sort((a, b) => a.sort.compareTo(b.sort));
    final sections = <String, List<CustomField>>{};
    for (final f in fields) {
      (sections[f.section] ??= []).add(f);
    }
    return SectionCard(
      title: 'بيانات إضافية',
      icon: Icons.dynamic_form_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final e in sections.entries) ...[
            if (sections.length > 1)
              Padding(
                padding: const EdgeInsets.only(top: 4, bottom: 6),
                child: Text(e.key, style: TextStyle(fontWeight: FontWeight.w700, color: sem.muted)),
              ),
            ResponsiveGrid(
              minItemWidth: 240,
              spacing: 10,
              children: [
                for (final f in e.value) _extraTile(context, app, p, f),
              ],
            ),
            const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }

  Widget _extraTile(BuildContext context, AppState app, Project p, CustomField f) {
    final sem = Sem.of(context);
    final canEdit = app.canEditField(p, f);
    final value = p.extra[f.key];
    if (f.kind == 'bool') {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(color: sem.surface2, borderRadius: BorderRadius.circular(12)),
        child: Row(
          children: [
            Expanded(child: Text(f.label, style: const TextStyle(fontWeight: FontWeight.w600))),
            Switch(value: value == true, onChanged: canEdit ? (v) => _saveExtra(app, p, f, v) : null),
          ],
        ),
      );
    }
    return Material(
      color: sem.surface2,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: canEdit ? () => _editExtra(app, p, f) : null,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(f.label, style: TextStyle(color: sem.muted, fontSize: 12.5)),
                    const SizedBox(height: 2),
                    Text(f.display(value), style: const TextStyle(fontWeight: FontWeight.w600, fontFeatures: [FontFeature.tabularFigures()])),
                  ],
                ),
              ),
              if (canEdit) Icon(Icons.edit_outlined, size: 18, color: sem.muted),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _saveExtra(AppState app, Project p, CustomField f, Object? value) async {
    try {
      await app.setProjectField(p.id, f.key, value);
      if (mounted) showToast(context, 'حُفظ «${f.label}»');
      _loadSide();
    } catch (e) {
      if (mounted) showToast(context, friendlyError(e), error: true);
    }
  }

  Future<void> _editExtra(AppState app, Project p, CustomField f) async {
    final current = p.extra[f.key];
    switch (f.kind) {
      case 'date':
        final init = DateTime.tryParse(current?.toString() ?? '') ?? DateTime.now();
        final d = await showDatePicker(context: context, initialDate: init, firstDate: DateTime(2000), lastDate: DateTime(2100));
        if (d == null) return;
        await _saveExtra(app, p, f, dbDate(d));
      case 'select':
        final v = await showDialog<String>(
          context: context,
          builder: (ctx) => SimpleDialog(
            title: Text(f.label),
            children: [
              for (final o in f.options)
                SimpleDialogOption(
                  onPressed: () => Navigator.of(ctx).pop(o),
                  child: Row(children: [
                    Icon(o == current ? Icons.radio_button_checked : Icons.radio_button_off, size: 20),
                    const SizedBox(width: 10),
                    Text(o),
                  ]),
                ),
              SimpleDialogOption(onPressed: () => Navigator.of(ctx).pop(''), child: const Text('مسح القيمة')),
            ],
          ),
        );
        if (v == null) return;
        await _saveExtra(app, p, f, v.isEmpty ? null : v);
      case 'number':
      case 'money':
        final v = await textInputDialog(context,
            title: f.label,
            label: f.kind == 'money' ? 'المبلغ ($currencyLabel)' : 'الرقم',
            confirmLabel: 'حفظ',
            initial: current is num ? moneyInput(current.toDouble()) : '',
            multiline: false,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            message: 'اتركه فارغاً لمسح القيمة.');
        if (v == null) return;
        final r = parseMoney(v);
        if (!r.ok) {
          if (mounted) showToast(context, 'اكتب رقماً صحيحاً', error: true);
          return;
        }
        await _saveExtra(app, p, f, r.value);
      default:
        final v = await textInputDialog(context,
            title: f.label,
            label: f.label,
            confirmLabel: 'حفظ',
            initial: current?.toString() ?? '',
            multiline: f.kind == 'longtext',
            message: 'اتركه فارغاً لمسح القيمة.');
        if (v == null) return;
        await _saveExtra(app, p, f, v.trim().isEmpty ? null : v.trim());
    }
  }

  Widget _notesCard(BuildContext context, AppState app, Project p) {
    final canEdit = app.canManageProjects && !app.frozenForMe;
    final changed = _notes.text.trim() != p.notes;
    return SectionCard(
      title: 'ملاحظات العقد',
      icon: Icons.sticky_note_2_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _notes,
            focusNode: _notesFocus,
            readOnly: !canEdit,
            minLines: 2,
            maxLines: 6,
            onChanged: (_) => setState(() {}),
            decoration: fieldDeco('الملاحظات', hint: canEdit ? 'اكتب ملاحظة عن العقد' : '—'),
          ),
          if (canEdit && changed) ...[
            const SizedBox(height: 8),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: FilledButton(onPressed: () => _saveNotes(p), child: const Text('حفظ الملاحظات')),
            ),
          ],
        ],
      ),
    );
  }

  Widget _qualityCard(BuildContext context, AppState app, Project p) {
    final sem = Sem.of(context);
    final notes = _qnotes;
    return SectionCard(
      title: 'ملاحظات التقييم والجودة',
      icon: Icons.rate_review_outlined,
      subtitle: 'مكتب التخطيط والتقييم وضمان الجودة',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (notes == null)
            const Padding(padding: EdgeInsets.all(4), child: Skeleton(height: 12))
          else if (notes.isEmpty)
            Text('لا توجد ملاحظات تقييم بعد.', style: TextStyle(color: sem.muted))
          else
            for (final n in notes)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${app.personName(n.author)} · ${fmtDate(n.createdAt)}', style: TextStyle(color: sem.muted, fontSize: 12)),
                    const SizedBox(height: 2),
                    Text(n.body),
                  ],
                ),
              ),
          if (app.canAddQualityNote) ...[
            const SizedBox(height: 6),
            TextField(
              controller: _qnote,
              minLines: 1,
              maxLines: 4,
              decoration: fieldDeco('ملاحظة تقييم جديدة'),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: FilledButton.icon(
                onPressed: _busyNote || _qnote.text.trim().isEmpty ? null : () => _addQualityNote(p),
                icon: const Icon(Icons.add_comment_outlined, size: 18),
                label: const Text('إضافة الملاحظة'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _historyCard(BuildContext context, AppState app, Project p) {
    final sem = Sem.of(context);
    final h = _history;
    return SectionCard(
      title: 'سجل التعديلات',
      icon: Icons.history_rounded,
      trailing: p.updatedAt == null ? null : Text('آخر تحديث ${fmtDate(p.updatedAt)}', style: TextStyle(color: sem.muted, fontSize: 11.5)),
      child: h == null
          ? const Column(children: [Skeleton(height: 12), SizedBox(height: 10), Skeleton(height: 12, width: 240)])
          : h.isEmpty
              ? Text('لا توجد تعديلات مسجّلة بعد. تظهر هنا كل التعديلات القادمة ومن قام بها.', style: TextStyle(color: sem.muted))
              : Column(
                  children: [
                    for (final e in h)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Text.rich(TextSpan(children: [
                                TextSpan(text: e.actorName.isEmpty ? 'النظام' : e.actorName, style: const TextStyle(fontWeight: FontWeight.w700)),
                                TextSpan(text: ' · ${auditDescription(app, e)}'),
                              ])),
                            ),
                            const SizedBox(width: 8),
                            Text(fmtDate(e.at), style: TextStyle(color: sem.muted, fontSize: 11.5)),
                          ],
                        ),
                      ),
                  ],
                ),
    );
  }
}

// ---------------------------------------------------------------------
// نوافذ العقد: عمل، تكليف مهندس، اختيار الأعمال للدمج
// ---------------------------------------------------------------------

/// اقتراحات سريعة تحت حقل نصي.
class _Suggestions extends StatelessWidget {
  const _Suggestions({required this.controller, required this.options, required this.onPick});

  final TextEditingController controller;
  final List<String> options;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    final typed = normalizeArabic(controller.text);
    final current = controller.text.trim();
    final list = options.where((o) => o != current && (typed.isEmpty || normalizeArabic(o).contains(typed))).take(6).toList();
    if (list.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final o in list)
            ActionChip(
              label: Text(o, maxLines: 1, overflow: TextOverflow.ellipsis),
              onPressed: () => onPick(o),
            ),
        ],
      ),
    );
  }
}

class _WorkDialog extends StatefulWidget {
  const _WorkDialog({required this.app, required this.project, this.work});

  final AppState app;
  final Project project;
  final ContractWork? work;

  @override
  State<_WorkDialog> createState() => _WorkDialogState();
}

class _WorkDialogState extends State<_WorkDialog> {
  late final TextEditingController _title = TextEditingController(text: widget.work?.title ?? '');
  late final TextEditingController _company = TextEditingController(text: widget.work?.company ?? '');
  late final TextEditingController _ref = TextEditingController(text: widget.work?.refNo ?? '');
  late final TextEditingController _notes = TextEditingController(text: widget.work?.notes ?? '');
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    _company.dispose();
    _ref.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_title.text.trim().isEmpty && _company.text.trim().isEmpty && _ref.text.trim().isEmpty) {
      setState(() => _error = 'اكتب وصف العمل أو الشركة.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.app.saveWork(
        id: widget.work?.id,
        projectId: widget.project.id,
        title: _title.text,
        company: _company.text,
        refNo: _ref.text,
        notes: _notes.text,
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = friendlyError(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.work == null ? 'إضافة عمل إلى ${widget.project.contractTitle}' : 'تعديل العمل'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(controller: _title, autofocus: true, minLines: 1, maxLines: 3, decoration: fieldDeco('وصف العمل')),
              const SizedBox(height: 12),
              TextField(controller: _company, decoration: fieldDeco('الشركة المنفذة'), onChanged: (_) => setState(() {})),
              _Suggestions(controller: _company, options: widget.app.companies, onPick: (v) => setState(() => _company.text = v)),
              const SizedBox(height: 12),
              TextField(
                controller: _ref,
                decoration: fieldDeco('الرقم المرجعي للعمل', helper: 'رقم التكليف أو أمر العمل الخاص بهذا العمل'),
              ),
              const SizedBox(height: 12),
              TextField(controller: _notes, minLines: 1, maxLines: 3, decoration: fieldDeco('ملاحظات (اختياري)')),
              if (_error != null) ...[
                const SizedBox(height: 10),
                InfoBanner(text: _error!, level: 'critical'),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.of(context).pop(false), child: const Text('إلغاء')),
        FilledButton(
          onPressed: _busy ? null : _save,
          child: _busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('حفظ'),
        ),
      ],
    );
  }
}

class _EngineerDialog extends StatefulWidget {
  const _EngineerDialog({required this.app, required this.project, required this.kind, this.engineer});

  final AppState app;
  final Project project;
  final String kind;
  final ContractEngineer? engineer;

  @override
  State<_EngineerDialog> createState() => _EngineerDialogState();
}

class _EngineerDialogState extends State<_EngineerDialog> {
  late final TextEditingController _name = TextEditingController(text: widget.engineer?.name ?? '');
  late final TextEditingController _no = TextEditingController(text: widget.engineer?.assignNo ?? '');
  late final TextEditingController _notes = TextEditingController(text: widget.engineer?.notes ?? '');
  late DateTime? _date = widget.engineer?.assignedOn;
  late String? _work = widget.engineer?.workId;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _no.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _date ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (d != null) setState(() => _date = d);
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.length < 2) {
      setState(() => _error = 'اكتب اسم المهندس.');
      return;
    }
    final no = _no.text.trim();
    final dup = no.isNotEmpty &&
        widget.app
            .engineersOf(widget.project.id, widget.kind)
            .any((e) => e.assignNo == no && e.id != widget.engineer?.id);
    if (dup) {
      setState(() => _error = 'رقم التكليف $no مسجّل لمهندس آخر في هذا العقد.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.app.saveEngineer(
        id: widget.engineer?.id,
        projectId: widget.project.id,
        kind: widget.kind,
        name: name,
        assignNo: no,
        assignedOn: _date,
        workId: _work,
        notes: _notes.text,
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = friendlyError(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final sem = Sem.of(context);
    final works = widget.app.worksOf(widget.project.id);
    final names = [
      ...widget.app.engineerNames(widget.kind),
      ...widget.app.engineerNames().where((n) => !widget.app.engineerNames(widget.kind).contains(n)),
    ];
    return AlertDialog(
      title: Text(widget.engineer == null ? 'تكليف ${engineerKindLabel(widget.kind)}' : 'تعديل تكليف ${engineerKindLabel(widget.kind)}'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(widget.project.contractTitle, style: TextStyle(color: sem.muted)),
              const SizedBox(height: 12),
              TextField(
                controller: _name,
                autofocus: widget.engineer == null,
                decoration: fieldDeco('اسم المهندس', prefixIcon: const Icon(Icons.person_outline)),
                onChanged: (_) => setState(() {}),
              ),
              _Suggestions(controller: _name, options: names, onPick: (v) => setState(() => _name.text = v)),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _no,
                      textDirection: TextDirection.ltr,
                      decoration: fieldDeco('رقم التكليف', prefixIcon: const Icon(Icons.tag_rounded)),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: _pickDate,
                      child: InputDecorator(
                        decoration: fieldDeco(
                          'تاريخ التكليف',
                          prefixIcon: const Icon(Icons.event_outlined),
                          suffix: _date == null
                              ? null
                              : IconButton(
                                  tooltip: 'مسح التاريخ',
                                  icon: const Icon(Icons.close_rounded, size: 18),
                                  onPressed: () => setState(() => _date = null),
                                ),
                        ),
                        child: Text(_date == null ? '—' : dayText(_date)),
                      ),
                    ),
                  ),
                ],
              ),
              if (works.isNotEmpty) ...[
                const SizedBox(height: 12),
                SelectField(
                  label: 'العمل المرتبط',
                  value: _work ?? '',
                  items: [
                    ('', 'كل أعمال العقد'),
                    for (final w in works) (w.id, w.display.isEmpty ? (w.refNo.isEmpty ? 'عمل' : 'عمل ${w.refNo}') : w.display),
                  ],
                  onChanged: (v) => setState(() => _work = v.isEmpty ? null : v),
                ),
              ],
              const SizedBox(height: 12),
              TextField(controller: _notes, minLines: 1, maxLines: 3, decoration: fieldDeco('ملاحظات (اختياري)')),
              if (_error != null) ...[
                const SizedBox(height: 10),
                InfoBanner(text: _error!, level: 'critical'),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.of(context).pop(false), child: const Text('إلغاء')),
        FilledButton(
          onPressed: _busy ? null : _save,
          child: _busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('حفظ التكليف'),
        ),
      ],
    );
  }
}

/// اختيار الأعمال (السجلات) التي تُدمج في العقد.
class _MergeSheet extends StatefulWidget {
  const _MergeSheet({required this.app, required this.target});

  final AppState app;
  final Project target;

  @override
  State<_MergeSheet> createState() => _MergeSheetState();
}

class _MergeSheetState extends State<_MergeSheet> {
  final _q = TextEditingController();
  final Set<String> _sel = {};

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = widget.app;
    final sem = Sem.of(context);
    final t = Theme.of(context).textTheme;
    final candidates = app.projects.where((x) => x.id != widget.target.id && app.canMerge(x)).toList();
    final q = normalizeArabic(_q.text);
    final list = q.isEmpty
        ? candidates
        : candidates
            .where((x) => normalizeArabic('${x.contractNo} ${x.assignNo} ${x.code} ${x.name} ${app.companiesOf(x).join(' ')}').contains(q))
            .toList();
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.84,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('دمج أعمال في ${widget.target.contractTitle}', style: t.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text(
                    'اختر الأعمال التي تتبع هذا العقد. تنتقل أعمالها ومهندسوها، وتُجمع قيمها المالية، وتُتابع الدورة على العقد.',
                    style: TextStyle(color: sem.muted),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                controller: _q,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'ابحث برقم العقد أو التكليف أو الاسم أو الشركة'),
              ),
            ),
            const SizedBox(height: 6),
            Expanded(
              child: list.isEmpty
                  ? const Center(child: EmptyState(icon: Icons.search_off, title: 'لا توجد أعمال مطابقة'))
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      itemCount: list.length,
                      itemBuilder: (context, i) {
                        final x = list[i];
                        final sel = _sel.contains(x.id);
                        return CheckboxListTile(
                          value: sel,
                          controlAffinity: ListTileControlAffinity.leading,
                          onChanged: (v) => setState(() {
                            if (v == true) {
                              _sel.add(x.id);
                            } else {
                              _sel.remove(x.id);
                            }
                          }),
                          title: Text(x.title, maxLines: 2, overflow: TextOverflow.ellipsis),
                          subtitle: Text(
                            [
                              if (x.assignNo.isNotEmpty) 'تكليف ${x.assignNo}',
                              ...app.companiesOf(x),
                              if (x.contractValue != null) '${fmtMoney(x.contractValue)} $currencyLabel',
                            ].join(' · '),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          secondary: ContractTag(x),
                        );
                      },
                    ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Row(
                children: [
                  Expanded(child: OutlinedButton(onPressed: () => Navigator.of(context).pop(), child: const Text('إلغاء'))),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: FilledButton.icon(
                      onPressed: _sel.isEmpty ? null : () => Navigator.of(context).pop(_sel.toList()),
                      icon: const Icon(Icons.call_merge_rounded),
                      label: Text(_sel.isEmpty ? 'اختر الأعمال' : 'دمج ${_sel.length} في العقد'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
