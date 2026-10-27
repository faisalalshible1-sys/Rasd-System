import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app_state.dart';
import '../models.dart';
import '../ui/audit_text.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';
import 'projects.dart';

/// UC-04 / UC-07 / UC-08 / UC-10: صفحة المشروع وتحديث نماذجه.
class ProjectDetailPage extends StatefulWidget {
  const ProjectDetailPage({super.key, required this.projectId});

  final String projectId;

  @override
  State<ProjectDetailPage> createState() => _ProjectDetailPageState();
}

class _ProjectDetailPageState extends State<ProjectDetailPage> {
  static const _engFields = ['eng_sup', 'eng_qty', 'eng_fol', 'eng_saf'];
  static const _finFields = ['contract_value', 'payment_first', 'payment_second', 'payment_final', 'deductions'];

  AppState? _app;
  final Map<String, TextEditingController> _eng = {};
  final Map<String, FocusNode> _engFocus = {};
  final TextEditingController _notes = TextEditingController();
  final FocusNode _notesFocus = FocusNode();
  final TextEditingController _qnote = TextEditingController();
  final Map<String, TextEditingController> _fin = {};
  bool _finDirty = false; // تعديلات مالية لم تُحفظ بعد: لا يُكتب فوقها عند وصول تحديث
  bool _busyFin = false;
  String? _busyForm;
  bool _busyNote = false;
  List<AuditEntry>? _history;
  List<QualityNote>? _qnotes;
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
      if (!mounted) return;
      setState(() {
        _history = h;
        _qnotes = q;
      });
    } catch (_) {
      if (mounted) setState(() => _history ??= const []);
    }
  }

  // ---------------------------------------------------------------
  // الإجراءات
  // ---------------------------------------------------------------
  Future<void> _change(Project p, FormDef d, FormStatus s) async {
    final app = AppScope.read(context);
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
      final res = await textInputDialog(context,
          title: 'رفض الطلب', label: 'سبب الرفض', confirmLabel: 'رفض الطلب', required: true);
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

  Future<void> _saveEngineer(Project p, FormDef d) async {
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

  Future<void> _saveFinance(Project p) async {
    final values = <String, double?>{};
    for (final f in _finFields) {
      final r = parseMoney(_fin[f]!.text);
      if (!r.ok) {
        showToast(context, 'اكتب مبلغاً صحيحاً في «${projectFieldLabels[f]}»', error: true);
        return;
      }
      values[f] = r.value;
    }
    FocusScope.of(context).unfocus();
    final app = AppScope.read(context);
    setState(() => _busyFin = true);
    try {
      await app.setContractFinance(
        p.id,
        contractValue: values['contract_value'],
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
      title: 'حذف المشروع ${p.assignNo}؟',
      message: 'سيُحذف المشروع وحالات نماذجه وطلباته لكل المستخدمين، ولا يمكن التراجع. يبقى أثر الحذف في سجل التدقيق.',
      confirmLabel: 'حذف نهائياً',
      danger: true,
    );
    if (!ok || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final nav = Navigator.of(context);
    try {
      await AppScope.read(context).deleteProject(p.id);
      messenger.showSnackBar(const SnackBar(content: Text('حُذف المشروع'), behavior: SnackBarBehavior.floating));
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
    final sem = Sem.of(context);
    final p = app.project(widget.projectId);
    if (p == null) {
      return Scaffold(
        appBar: brandAppBar(context, title: const Text('المشروع')),
        body: const Center(child: EmptyState(title: 'المشروع غير موجود', message: 'ربما حُذف. ارجع إلى قائمة المشاريع.')),
      );
    }
    final pr = app.progressOf(p);
    final width = MediaQuery.sizeOf(context).width;
    final side = math.max(16.0, (width - 860) / 2);

    return Scaffold(
      appBar: brandAppBar(
        context,
        title: Text(p.assignNo.isEmpty ? 'المشروع' : 'مشروع ${p.assignNo}'),
        actions: [
          if (app.canManageProjects)
            IconButton(tooltip: 'تعديل بيانات المشروع', icon: const Icon(Icons.edit_outlined), onPressed: () => openProjectEditor(context, p)),
          if (app.isDirector)
            IconButton(tooltip: 'حذف المشروع', icon: const Icon(Icons.delete_outline), onPressed: () => _delete(p)),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          await app.loadAll();
          await _loadSide();
        },
        child: ListView(
          padding: EdgeInsets.fromLTRB(side, 16, side, 32),
          children: [
            _header(context, app, p),
            const SizedBox(height: 14),
            _statusCard(context, app, p, pr),
            const SizedBox(height: 14),
            SectionCard(
              title: 'نماذج الدورة المستندية',
              trailing: Text('${pr.done} من ${pr.required} مطلوب', style: TextStyle(color: sem.muted, fontSize: 12)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var stage = 0; stage < stageNames.length; stage++) ..._stageBlock(context, app, p, pr, stage),
                ],
              ),
            ),
            const SizedBox(height: 14),
            if (app.activeFields.isNotEmpty) ...[
              _extraCard(context, app, p),
              const SizedBox(height: 14),
            ],
            _notesCard(context, app, p),
            if (app.isDirector || app.settings.feature('quality_notes')) ...[
              const SizedBox(height: 14),
              _qualityCard(context, app, p),
            ],
            const SizedBox(height: 14),
            _historyCard(context, app, p),
          ],
        ),
      ),
    );
  }

  Widget _header(BuildContext context, AppState app, Project p) {
    final sem = Sem.of(context);
    final t = Theme.of(context).textTheme;
    Widget fact(String k, String v) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(width: 110, child: Text(k, style: TextStyle(color: sem.muted, fontSize: 13))),
              Expanded(child: Text(v.isEmpty ? '—' : v)),
            ],
          ),
        );
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: sem.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: sem.rule)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(p.title, style: t.titleLarge?.copyWith(fontWeight: FontWeight.w700, height: 1.5)),
          const SizedBox(height: 10),
          fact('رقم التكليف', p.assignNo),
          fact('رمز المشروع', p.code),
          fact('مالك المشروع', p.owner),
          fact('الشركة المنفذة', p.company),
          fact('القسم المشرف', app.departmentName(p.department)),
        ],
      ),
    );
  }

  Widget _statusCard(BuildContext context, AppState app, Project p, Progress pr) {
    final sem = Sem.of(context);
    final t = Theme.of(context).textTheme;
    final sizes = [for (var s = 0; s < stageNames.length; s++) app.formDefs.where((d) => d.stage == s).length];
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: sem.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: sem.rule)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(pctText(pr.pct),
                  style: t.displaySmall?.copyWith(fontWeight: FontWeight.w700, fontFeatures: const [FontFeature.tabularFigures()])),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CyclePill(pr.cycle),
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
            ],
          ),
          const SizedBox(height: 14),
          CycleStrip(defs: app.formDefs, cells: pr.cells, height: 12),
          const SizedBox(height: 4),
          Row(
            children: [
              for (var i = 0; i < sizes.length; i++)
                if (sizes[i] > 0)
                  Expanded(
                    flex: sizes[i],
                    child: Text(stageNames[i],
                        textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 10.5, color: sem.muted)),
                  ),
            ],
          ),
          const SizedBox(height: 10),
          Legend(items: [
            (sem.ok, 'مكتمل ${pr.done}'),
            (sem.wip, 'قيد الإجراء ${pr.wip}'),
            (sem.todo, 'لم يتم ${pr.todo}'),
            (sem.na, 'لا ينطبق ${pr.na}'),
          ]),
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
          Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isDone ? sem.ok : (isCur ? cs.primary : sem.todoSoft),
            ),
            child: Text('${stage + 1}',
                style: TextStyle(color: isDone || isCur ? Colors.white : sem.muted, fontWeight: FontWeight.w700)),
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(stageNames[stage], style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15))),
          Text('$dn/$req', style: TextStyle(color: sem.muted, fontFeatures: const [FontFeature.tabularFigures()])),
        ],
      ),
      const SizedBox(height: 10),
      for (final d in defs) Padding(padding: const EdgeInsets.only(bottom: 8), child: _formRow(context, app, p, pr, d)),
      if (stage == 0) Padding(padding: const EdgeInsets.only(bottom: 8), child: _financeBlock(context, app, p)),
    ];
  }

  /// البيانات المالية للعقد ضمن مرحلة التعاقد.
  Widget _financeBlock(BuildContext context, AppState app, Project p) {
    final sem = Sem.of(context);
    final canEdit = app.canEditFinance(p);
    final contractDef = app.formDef(contractFormKey);
    final entered = parseMoney(_fin['contract_value']!.text);
    final base = entered.ok ? entered.value : p.contractValue;
    final gInitial = base == null ? null : roundMoney(base * guaranteeInitialRate);
    final gFinal = base == null ? null : roundMoney(base * guaranteeFinalRate);
    const tabular = TextStyle(fontFeatures: [FontFeature.tabularFigures()]);

    Widget field(String f) {
      final r = parseMoney(_fin[f]!.text);
      return TextField(
        controller: _fin[f],
        readOnly: !canEdit,
        style: tabular,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        onChanged: (_) => setState(() => _finDirty = true),
        onSubmitted: (_) {
          if (canEdit && _finDirty) _saveFinance(p);
        },
        decoration: fieldDeco(projectFieldLabels[f]!, hint: canEdit ? '0' : '—', error: r.ok ? null : 'اكتب مبلغاً صحيحاً')
            .copyWith(suffixText: currencyLabel),
      );
    }

    Widget computed(String label, double? v) => InputDecorator(
          decoration: fieldDeco(label).copyWith(suffixText: v == null ? null : currencyLabel, filled: true, fillColor: sem.surface),
          child: Text(fmtMoney(v), style: tabular),
        );

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: sem.surface2, borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.payments_outlined, size: 18, color: sem.muted),
              const SizedBox(width: 6),
              const Expanded(child: Text('البيانات المالية للعقد', style: TextStyle(fontWeight: FontWeight.w700))),
              Text('بالدينار الليبي', style: TextStyle(color: sem.muted, fontSize: 12)),
            ],
          ),
          const SizedBox(height: 12),
          LayoutBuilder(builder: (context, c) {
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
                field('contract_value'),
                const SizedBox(height: 10),
                group([field('payment_first'), field('payment_second'), field('payment_final')]),
                const SizedBox(height: 10),
                group([
                  computed('الضمان الابتدائي ${rateText(guaranteeInitialRate)}', gInitial),
                  computed('الضمان النهائي ${rateText(guaranteeFinalRate)}', gFinal),
                ]),
                const SizedBox(height: 10),
                field('deductions'),
              ],
            );
          }),
          const SizedBox(height: 6),
          Text(
            'يُحسب الضمانان تلقائياً من قيمة التعاقد.'
            '${!canEdit && contractDef != null ? ' يحدّث البيانات المالية: ${app.responsibleText(p, contractDef)}.' : ''}',
            style: TextStyle(fontSize: 11.5, color: sem.muted),
          ),
          if (canEdit && _finDirty) ...[
            const SizedBox(height: 10),
            Row(
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
          ],
        ],
      ),
    );
  }

  Widget _formRow(BuildContext context, AppState app, Project p, Progress pr, FormDef d) {
    final sem = Sem.of(context);
    final cs = Theme.of(context).colorScheme;
    final status = app.statusOf(p.id, d.key);
    final canEdit = app.canEditForm(p, d);
    final isNext = pr.next?.key == d.key;
    final pending = app.pendingFor(p.id, d.key);
    final field = d.engineerField;

    return Container(
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
            Container(
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
                    'طلب ${app.personName(pending.requestedBy)} · ${fmtDate(pending.requestedAt)}' + (pending.note.isNotEmpty ? '\n' + pending.note : ''),
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
            ),
          ],
          if (field != null) ...[
            const SizedBox(height: 8),
            TextField(
              controller: _eng[field],
              focusNode: _engFocus[field],
              readOnly: !canEdit,
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => _saveEngineer(p, d),
              decoration: fieldDeco(
                engineerFieldLabel(field),
                hint: canEdit ? 'اكتب الاسم ثم احفظ' : '—',
                suffix: canEdit && _eng[field]!.text.trim() != p.engineer(field)
                    ? IconButton(tooltip: 'حفظ', icon: const Icon(Icons.check), onPressed: () => _saveEngineer(p, d))
                    : null,
              ),
            ),
          ],
        ],
      ),
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
        await _saveExtra(app, p, f, '${d.year}-${two(d.month)}-${two(d.day)}');
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
      title: 'ملاحظات المشروع',
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
            decoration: fieldDeco('الملاحظات', hint: canEdit ? 'اكتب ملاحظة عن المشروع' : '—'),
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
      trailing: Text('مكتب التخطيط والتقييم وضمان الجودة', style: TextStyle(color: sem.muted, fontSize: 11.5)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (notes == null)
            const Padding(padding: EdgeInsets.all(8), child: Center(child: CircularProgressIndicator(strokeWidth: 2)))
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
      trailing: p.updatedAt == null ? null : Text('آخر تحديث ${fmtDate(p.updatedAt)}', style: TextStyle(color: sem.muted, fontSize: 11.5)),
      child: h == null
          ? const Padding(padding: EdgeInsets.all(8), child: Center(child: CircularProgressIndicator(strokeWidth: 2)))
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
