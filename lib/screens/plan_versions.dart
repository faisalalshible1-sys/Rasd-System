import 'package:flutter/material.dart';

import '../app_state.dart';
import '../models.dart';
import '../pm.dart';
import '../schedule.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';
import 'plan_widgets.dart';
import 'plans.dart' show fmtQty;
import 'pm_common.dart';

// =====================================================================
// البرنامج الزمني (الإصدار 1.5.0، الترحيل 36): العلاقات بين الأنشطة، وإصدارات البرنامج المعتمدة ومقارنتها
// بالحالي والتنفيذ الفعلي، ومعدلات الإنتاجية بتاريخ سريانها.
// =====================================================================

String _shift(int? d) {
  if (d == null) return '—';
  if (d == 0) return 'كما هو';
  return d > 0 ? 'تأخر ${daysWord(d)}' : 'تقدّم ${daysWord(-d)}';
}

String _itemName(PmItem x) => [x.code, x.title].where((s) => s.isNotEmpty).join(' ');

// ---------------------------------------------------------------------
// العلاقات
// ---------------------------------------------------------------------

/// علاقات النشاط بسوابقه: إضافة علاقة من نشاط أسبق في الترتيب، أو تعديل نوعها وانتظارها، أو حذفها.
Future<void> showLinkEditor(BuildContext context, Project p, PmItem item) async {
  final app = AppScope.read(context);
  final order = orderItems(app.itemsOf(p.id), app.phasesOf(p.id));
  final idx = order.indexWhere((x) => x.id == item.id);
  final earlier = [for (var k = 0; k < (idx < 0 ? 0 : idx); k++) order[k]];
  final existing = [for (final l in app.linksOf(p.id)) if (l.succId == item.id) l];
  final byId = {for (final x in order) x.id: x};

  Future<void> edit(PmLink? link) async {
    final ok = await showPmForm(
      context,
      title: link == null ? 'علاقة جديدة' : 'تعديل العلاقة',
      note: 'النشاط «${item.title}» يرتبط بنشاط يسبقه في ترتيب البرنامج. الانتظار بالأيام بعد ما تقتضيه العلاقة، والسالب تداخل.',
      sections: [
        PmSection('', [
          PmField('pred_id', 'النشاط السابق', PmKind.select,
              required: true,
              full: true,
              enabled: link == null,
              options: [
                for (final x in earlier)
                  if (link != null || !existing.any((l) => l.predId == x.id)) (x.id, _itemName(x)),
              ]),
          PmField('kind', 'نوع العلاقة', PmKind.select,
              required: true, options: [for (final k in linkKinds) (k, '${linkKindLabels[k]}: ${linkKindHelp[k]}')]),
          const PmField('lag_days', 'الانتظار (يوم)', PmKind.text, max: 6, helper: 'موجب للتأخير وسالب للتداخل'),
        ]),
      ],
      values: {'pred_id': link?.predId ?? '', 'kind': link?.kind ?? 'FS', 'lag_days': '${link?.lagDays ?? 0}'},
      onSave: (d) async {
        final t = '${d['lag_days'] ?? ''}'.trim().replaceAll('−', '-');
        final lag = t.isEmpty ? 0 : int.tryParse(t);
        if (lag == null) throw 'الانتظار رقم صحيح (مثل 3 أو -2)';
        await app.savePmLink(link?.id, {
          if (link == null) 'pred_id': d['pred_id'],
          if (link == null) 'succ_id': item.id,
          'kind': d['kind'],
          'lag_days': lag,
        });
      },
    );
    if (ok && context.mounted) showToast(context, 'حُفظت العلاقة وأُعيد حساب البرنامج');
  }

  if (existing.isEmpty) {
    if (earlier.isEmpty) {
      showToast(context, 'لا نشاط يسبق هذا النشاط في ترتيب البرنامج.', error: true);
      return;
    }
    await edit(null);
    return;
  }
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheet) {
      final sem = Sem.of(sheet);
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('علاقات «${item.title}»', style: Theme.of(sheet).textTheme.titleMedium, maxLines: 2, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 4),
            Text('ما يسبقه من أنشطة ونوع كل علاقة.', style: TextStyle(color: sem.muted, fontSize: 12.5)),
            const SizedBox(height: 8),
            for (final l in existing)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.subdirectory_arrow_left_rounded),
                title: Text(byId[l.predId] == null ? '—' : _itemName(byId[l.predId]!), maxLines: 2, overflow: TextOverflow.ellipsis),
                subtitle: Text(l.label),
                onTap: () {
                  Navigator.of(sheet).pop();
                  edit(l);
                },
                trailing: IconButton(
                  tooltip: 'حذف العلاقة',
                  icon: Icon(Icons.link_off_rounded, color: sem.danger),
                  onPressed: () async {
                    Navigator.of(sheet).pop();
                    try {
                      await app.deletePmLink(l.id);
                      if (context.mounted) showToast(context, 'حُذفت العلاقة وأُعيد حساب البرنامج');
                    } catch (e) {
                      if (context.mounted) showToast(context, friendlyError(e), error: true);
                    }
                  },
                ),
              ),
            const SizedBox(height: 8),
            if (earlier.any((x) => !existing.any((l) => l.predId == x.id)))
              FilledButton.icon(
                onPressed: () {
                  Navigator.of(sheet).pop();
                  edit(null);
                },
                icon: const Icon(Icons.add_link_rounded),
                label: const Text('إضافة علاقة'),
              ),
          ]),
        ),
      );
    },
  );
}

// ---------------------------------------------------------------------
// الإصدارات
// ---------------------------------------------------------------------

/// بطاقة إصدارات البرنامج المعتمدة في صفحة إعداد البرنامج.
class PlanVersionsCard extends StatelessWidget {
  const PlanVersionsCard({super.key, required this.project});

  final Project project;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final sem = Sem.of(context);
    final versions = app.versionsOf(project.id);
    return SectionCard(
      title: 'إصدارات البرنامج',
      icon: Icons.history_rounded,
      subtitle: versions.isEmpty
          ? 'يُحفظ كل اعتماد للبرنامج إصداراً كاملاً لا يُعدَّل، للمقارنة بالبرنامج الحالي وبالتنفيذ الفعلي.'
          : 'كل اعتماد محفوظ كما كان. اضغط إصداراً لمقارنته بالبرنامج الحالي وبما نُفّذ فعلاً.',
      child: versions.isEmpty
          ? Text('لم يُعتمد البرنامج بعد.', style: TextStyle(color: sem.muted, fontSize: 12.5))
          : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              for (final v in versions)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(radius: 16, child: Text('${v.version}', style: const TextStyle(fontWeight: FontWeight.w800))),
                  title: Text('الإصدار ${v.version}${v == versions.last ? ' (الأساس)' : ''}'),
                  subtitle: Text([
                    if (v.approvedAt != null) fmtDate(v.approvedAt),
                    if (app.people[v.approvedBy]?.displayName != null) app.people[v.approvedBy]!.displayName,
                    '${pmDay(v.startDate)} إلى ${pmDay(v.endDate)}',
                    daysWord(v.totalDays),
                    '${v.items.length} نشاطاً',
                    if (v.source == 'backfill') 'سُجّل عند تفعيل الإصدارات',
                  ].join(' · ')),
                  trailing: const Icon(Icons.chevron_left_rounded),
                  onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(builder: (_) => PlanVersionPage(projectId: project.id, versionId: v.id))),
                ),
            ]),
    );
  }
}

/// مقارنة إصدار معتمد بالبرنامج الحالي وبالتنفيذ الفعلي.
class PlanVersionPage extends StatefulWidget {
  const PlanVersionPage({super.key, required this.projectId, required this.versionId});

  final String projectId;
  final String versionId;

  @override
  State<PlanVersionPage> createState() => _PlanVersionPageState();
}

class _PlanVersionPageState extends State<PlanVersionPage> {
  bool _changedOnly = true;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final sem = Sem.of(context);
    final p = app.project(widget.projectId);
    final v = app.versionsOf(widget.projectId).where((x) => x.id == widget.versionId).firstOrNull;
    if (p == null || v == null) {
      return Scaffold(
        appBar: brandAppBar(context, title: const Text('إصدار البرنامج')),
        body: const EmptyState(title: 'الإصدار غير موجود', message: 'ربما دُمج العقد في عقد آخر.', icon: Icons.search_off_rounded),
      );
    }
    final items = app.itemsOf(p.id);
    final deltas = compareVersion(v, items);
    final shown = _changedOnly
        ? deltas.where((d) => d.added || d.removed || (d.startShift ?? 0) != 0 || (d.endShift ?? 0) != 0 || (d.actualEndShift ?? 0) > 0).toList()
        : deltas;
    final curEnd = items.isEmpty ? null : items.map((i) => i.plannedEnd).reduce((a, b) => a.isAfter(b) ? a : b);
    final endShift = curEnd == null || v.endDate == null ? null : daysBetween(curEnd, v.endDate!);
    final late = deltas.where((d) => (d.endShift ?? 0) > 0).length;
    final actualLate = deltas.where((d) => (d.actualEndShift ?? 0) > 0).length;
    final narrow = MediaQuery.sizeOf(context).width < 700;

    return Scaffold(
      appBar: brandAppBar(context, title: Text('الإصدار ${v.version}')),
      body: PageBody(maxWidth: 1100, children: [
        PageHeader(
          title: 'الإصدار ${v.version} مقارنة بالبرنامج الحالي',
          subtitle: [p.shortName, if (v.approvedAt != null) 'اعتُمد ${fmtDate(v.approvedAt)}', '${v.items.length} نشاطاً'].join(' · '),
          icon: Icons.compare_arrows_rounded,
        ),
        ResponsiveGrid(minItemWidth: narrow ? 150 : 200, spacing: 10, children: [
          StatCard(
              label: 'نهاية الإصدار',
              value: pmDay(v.endDate),
              sub: daysWord(v.totalDays),
              icon: Icons.flag_outlined),
          StatCard(
              label: 'نهاية البرنامج الحالي',
              value: pmDay(curEnd),
              sub: _shift(endShift),
              icon: Icons.event_available_outlined,
              color: (endShift ?? 0) > 0 ? sem.danger : null),
          StatCard(label: 'أنشطة تأخرت نهايتها المخططة', value: '$late', sub: 'عن هذا الإصدار', icon: Icons.schedule_rounded),
          StatCard(label: 'أنشطة انتهت فعلياً بعد موعدها', value: '$actualLate', sub: 'النهاية الفعلية بعد نهاية الإصدار', icon: Icons.running_with_errors_rounded),
        ]),
        const SizedBox(height: 14),
        SectionCard(
          title: 'الأنشطة',
          icon: Icons.list_alt_rounded,
          subtitle: 'الفرق = الحالي − الإصدار. الفعلي من سجل الإنجاز الذي يدخله الإشراف.',
          trailing: FilterChip(label: const Text('ما تغيّر فقط'), selected: _changedOnly, onSelected: (x) => setState(() => _changedOnly = x)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (shown.isEmpty)
              Text(_changedOnly ? 'لم يتغير شيء عن هذا الإصدار.' : 'لا أنشطة.', style: TextStyle(color: sem.muted)),
            for (final d in shown)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Material(
                  color: sem.surface2,
                  borderRadius: BorderRadius.circular(10),
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Expanded(child: Text(d.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700))),
                        if (d.added) ToneBadge('أُضيف بعد الإصدار', color: sem.wip),
                        if (d.removed) ToneBadge('حُذف بعد الإصدار', color: sem.danger),
                      ]),
                      const SizedBox(height: 4),
                      Text(
                        [
                          if (d.base != null) 'الإصدار: ${pmDay(d.base!.start)} إلى ${pmDay(d.base!.end)}',
                          if (d.current != null) 'الحالي: ${pmDay(d.current!.plannedStart)} إلى ${pmDay(d.current!.plannedEnd)}',
                          if (d.current?.actualEnd != null) 'انتهى فعلياً ${pmDay(d.current!.actualEnd)}',
                        ].join(' · '),
                        style: TextStyle(color: sem.muted, fontSize: 12),
                      ),
                      if (!d.added && !d.removed)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Wrap(spacing: 6, runSpacing: 4, children: [
                            ToneBadge('البداية: ${_shift(d.startShift)}', color: (d.startShift ?? 0) > 0 ? sem.danger : sem.muted),
                            ToneBadge('النهاية: ${_shift(d.endShift)}', color: (d.endShift ?? 0) > 0 ? sem.danger : sem.muted),
                            if (d.actualEndShift != null)
                              ToneBadge('الفعلي: ${_shift(d.actualEndShift)}', color: d.actualEndShift! > 0 ? sem.danger : sem.ok),
                          ]),
                        ),
                    ]),
                  ),
                ),
              ),
          ]),
        ),
      ]),
    );
  }
}

// ---------------------------------------------------------------------
// معدلات الإنتاجية
// ---------------------------------------------------------------------

Future<void> openRatesPage(BuildContext context) =>
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const RatesPage()));

Future<void> showRateEditor(BuildContext context, {PmRate? base}) async {
  final app = AppScope.read(context);
  final ok = await showPmForm(
    context,
    title: base == null ? 'معدل إنتاجية' : 'إصدار جديد للمعدل',
    note: 'المعدل هو الكمية المنجزة في يوم عمل لوحدة البند. يطابق البند بوحدته، وبكلمة في وصفه إن كُتبت (أطول كلمة تحسم)، '
        'فتُقترح مدته = الكمية ÷ المعدل مقرّبة لأعلى. لا يُعدَّل معدل محفوظ: يُضاف له إصدار بتاريخ سريانه ويبقى السابق في السجل.',
    sections: [
      PmSection('المعدل', [
        PmField('unit', 'الوحدة', PmKind.text, required: true, max: 20, enabled: base == null, helper: 'كما في المقايسة: م3، م2، م.ط، عدد'),
        PmField('keyword', 'كلمة في الوصف', PmKind.text, max: 60, enabled: base == null, helper: 'فارغة = المعدل العام للوحدة'),
        const PmField('rate', 'الكمية في اليوم', PmKind.decimal, required: true),
        const PmField('valid_from', 'يسري من', PmKind.date, required: true),
        const PmField('label', 'الوصف', PmKind.text, max: 120, full: true, helper: 'مثل: حفر آلي بحفار واحد'),
        const PmField('active', 'مفعّل', PmKind.toggle),
        if (base != null) const PmField('note', 'سبب التعديل', PmKind.text, max: 300, full: true),
      ]),
    ],
    values: {
      'unit': base?.unit ?? '',
      'keyword': base?.keyword ?? '',
      'rate': base?.rate,
      'valid_from': pmToday(),
      'label': base?.label ?? '',
      'active': base?.active ?? true,
      'note': '',
    },
    onSave: (d) => app.savePmRate(d),
  );
  if (ok && context.mounted) showToast(context, base == null ? 'أُضيف المعدل' : 'أُضيف إصدار جديد للمعدل');
}

class RatesPage extends StatefulWidget {
  const RatesPage({super.key});

  @override
  State<RatesPage> createState() => _RatesPageState();
}

class _RatesPageState extends State<RatesPage> {
  bool _history = false;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final sem = Sem.of(context);
    final today = pmToday();
    final current = app.ratesNow..sort((a, b) => a.unit == b.unit ? a.keyword.compareTo(b.keyword) : a.unit.compareTo(b.unit));
    final currentIds = {for (final r in current) r.id};
    final rows = _history ? app.pmRates : current;
    return Scaffold(
      appBar: brandAppBar(context, title: const Text('معدلات الإنتاجية')),
      body: PageBody(maxWidth: 1000, onRefresh: app.loadAll, children: [
        PageHeader(
          title: 'معدلات الإنتاجية',
          subtitle: '${current.where((r) => r.active).length} معدلاً سارياً · تُستعمل لاقتراح مدد الأنشطة عند توليد البرنامج من المقايسة',
          icon: Icons.speed_rounded,
          actions: [
            if (app.canEditRates)
              FilledButton.icon(onPressed: () => showRateEditor(context), icon: const Icon(Icons.add_rounded), label: const Text('معدل جديد')),
          ],
        ),
        const InfoBanner(
          text: 'المدة المقترحة = الكمية ÷ المعدل، مقرّبة لأعلى (من يوم إلى 3650).البند الذي لا يطابقه معدل تُقترح مدته بقيمته كما كان. '
              'المدد المقترحة تبقى قابلة للتعديل يدوياً لكل نشاط.',
        ),
        const SizedBox(height: 12),
        SectionCard(
          title: _history ? 'كل الإصدارات' : 'المعدلات السارية اليوم',
          icon: Icons.table_rows_outlined,
          trailing: FilterChip(label: const Text('السجل كاملاً'), selected: _history, onSelected: (x) => setState(() => _history = x)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (rows.isEmpty)
              Text(app.canEditRates ? 'لا معدلات بعد. أضف معدلات القسم لتُقترح المدد بالإنتاجية.' : 'لا معدلات بعد.',
                  style: TextStyle(color: sem.muted)),
            for (final r in rows)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(r.active ? Icons.speed_rounded : Icons.block_rounded, color: r.active ? null : sem.muted),
                title: Text('${fmtQty(r.rate)} ${r.unit} في اليوم${r.keyword.isEmpty ? ' (عام للوحدة)' : ' · «${r.keyword}»'}'),
                subtitle: Text([
                  if (r.label.isNotEmpty) r.label,
                  'يسري من ${pmDay(r.validFrom)}',
                  if (r.validFrom.isAfter(today)) 'لم يسرِ بعد',
                  if (_history && currentIds.contains(r.id)) 'الساري',
                  if (!r.active) 'غير مفعّل',
                  if (r.note.isNotEmpty) r.note,
                  if (app.people[r.createdBy]?.displayName != null) app.people[r.createdBy]!.displayName,
                ].join(' · ')),
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  if (app.canEditRates)
                    IconButton(tooltip: 'إصدار جديد', icon: const Icon(Icons.edit_calendar_outlined), onPressed: () => showRateEditor(context, base: r)),
                  if (app.isDirector)
                    IconButton(
                      tooltip: 'حذف قيد خاطئ',
                      icon: Icon(Icons.delete_outline_rounded, color: sem.danger),
                      onPressed: () async {
                        final ok = await confirmDialog(context,
                            title: 'حذف قيد المعدل',
                            message: 'يُحذف هذا القيد نهائياً ويبقى أثره في سجل التدقيق. لإيقاف معدل صحيح أضف له إصداراً غير مفعّل بدل حذفه.',
                            confirmLabel: 'حذف',
                            danger: true);
                        if (!ok || !context.mounted) return;
                        try {
                          await app.deletePmRate(r.id);
                        } catch (e) {
                          if (context.mounted) showToast(context, friendlyError(e), error: true);
                        }
                      },
                    ),
                ]),
              ),
          ]),
        ),
      ]),
    );
  }
}
