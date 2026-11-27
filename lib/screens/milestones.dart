import 'package:flutter/material.dart';

import '../app_state.dart';
import '../milestones.dart';
import '../pm.dart';
import '../print/export_dialog.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';
import 'pm_common.dart';

// =====================================================================
// معالم المشاريع ومؤشرات الأداء (الإصدار 1.14.0، الترحيل 45): صفحتان في قسم المخاطر ومتابعة المشاريع.
// المعادلات في lib/milestones.dart وتطابق الفصلين 38 و39 من دليل الاستخدام.
// =====================================================================

DateTime? _parseDay(Object? v) {
  if (v == null || '$v'.isEmpty) return null;
  final d = DateTime.tryParse('$v');
  return d == null ? null : DateTime(d.year, d.month, d.day);
}

String _projectName(AppState app, String id) {
  final t = app.pm.track(id);
  if (t != null) return t.displayName;
  for (final p in app.projects) {
    if (p.id == id) return p.name;
  }
  return '—';
}

(String, Color) _statusTone(PmMilestone m, DateTime today, Sem sem) {
  if (m.isDone) return (m.doneOnTime ? 'أُنجز في موعده' : 'أُنجز متأخراً ${m.lateDays(today)} يوم', m.doneOnTime ? sem.ok : sem.wip);
  if (m.isCancelled) return ('ملغى', sem.muted);
  if (m.isOverdue(today)) return ('متأخر ${m.lateDays(today)} يوم', sem.danger);
  if (m.slipping) return ('متوقع تأخره', sem.wip);
  return ('قادم', sem.todo);
}

/// إضافة معلم أو تعديله. [projectId] يثبّت المشروع عند التعديل.
Future<void> showMilestoneEditor(BuildContext context, {PmMilestone? milestone, String? projectId}) async {
  final app = AppScope.of(context);
  final ok = await showPmForm(
    context,
    title: milestone == null ? 'معلم جديد' : 'تعديل المعلم',
    note: 'المعلم حدث محدد في المشروع له تاريخ مخطط. التاريخ المتوقع اختياري ويُستعمل لإنذار مبكر قبل فوات المخطط. إنجاز المعلم يُسجَّل من القائمة.',
    sections: [
      PmSection('المعلم', [
        PmField('project_id', 'المشروع', PmKind.select,
            required: true, enabled: milestone == null, options: [for (final p in app.projects) (p.id, _projectName(app, p.id))]),
        const PmField('title', 'عنوان المعلم', PmKind.text, required: true, max: 120, full: true),
        const PmField('planned_date', 'التاريخ المخطط', PmKind.date, required: true),
        const PmField('forecast_date', 'التاريخ المتوقع', PmKind.date),
        const PmField('note', 'ملاحظة', PmKind.multiline, max: 300, full: true),
      ]),
    ],
    values: milestone == null
        ? {'project_id': projectId ?? ''}
        : {
            'project_id': milestone.projectId,
            'title': milestone.title,
            'planned_date': milestone.planned,
            'forecast_date': milestone.forecast,
            'note': milestone.note,
          },
    onSave: (d) => app.saveMilestone(
      id: milestone?.id,
      projectId: '${d['project_id']}',
      title: '${d['title']}',
      planned: _parseDay(d['planned_date'])!,
      forecast: _parseDay(d['forecast_date']),
      note: '${d['note'] ?? ''}',
    ),
  );
  if (ok && context.mounted) showToast(context, milestone == null ? 'أُضيف المعلم' : 'حُفظ المعلم');
}

class MilestonesPage extends StatefulWidget {
  const MilestonesPage({super.key});

  @override
  State<MilestonesPage> createState() => _MilestonesPageState();
}

class _MilestonesPageState extends State<MilestonesPage> {
  String _project = '';
  String _status = 'open'; // open | late | done | all

  Future<void> _run(Future<void> Function() f, String done) async {
    try {
      await f();
      if (mounted) showToast(context, done);
    } catch (e) {
      if (mounted) showToast(context, friendlyError(e), error: true);
    }
  }

  Future<void> _complete(PmMilestone m) async {
    final today = pmToday();
    final picked = await showDatePicker(
      context: context,
      initialDate: today,
      firstDate: DateTime(today.year - 3),
      lastDate: today,
      helpText: 'التاريخ الفعلي لإنجاز «${m.title}»',
    );
    if (picked == null || !mounted) return;
    await _run(() => AppScope.of(context).setMilestoneStatus(m.id, 'done', actual: picked), 'سُجّل الإنجاز');
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final sem = Sem.of(context);
    final today = pmToday();
    final all = app.milestones;
    final late = all.where((m) => m.isOverdue(today)).length;
    final slipping = all.where((m) => m.isPending && !m.isOverdue(today) && m.slipping).length;
    final upcoming = all.where((m) => m.isPending && !m.isOverdue(today)).length;
    final adherence = kpiMilestones(all, today);

    bool pass(PmMilestone m) {
      if (_project.isNotEmpty && m.projectId != _project) return false;
      return switch (_status) {
        'open' => m.isPending,
        'late' => m.isOverdue(today),
        'done' => m.isDone,
        _ => true,
      };
    }

    final shown = [for (final m in all) if (pass(m)) m];
    final byProject = <String, List<PmMilestone>>{};
    for (final m in shown) {
      (byProject[m.projectId] ??= []).add(m);
    }
    final projectIds = byProject.keys.toList()..sort((a, b) => _projectName(app, a).compareTo(_projectName(app, b)));
    final projectOptions = <(String, String)>[
      ('', 'كل المشاريع'),
      for (final id in {for (final m in all) m.projectId}) (id, _projectName(app, id)),
    ];

    return PageBody(
      onRefresh: app.loadAll,
      children: [
        PageHeader(
          title: 'معالم المشاريع',
          subtitle: 'أحداث محددة في كل مشروع بتاريخ مخطط ومتوقع وفعلي، وتنبيه بما فات موعده.',
          icon: Icons.flag_outlined,
          actions: [
            if (app.canEditMilestones)
              FilledButton.icon(
                onPressed: () => showMilestoneEditor(context, projectId: _project),
                icon: const Icon(Icons.add),
                label: const Text('معلم جديد'),
              ),
            ExportButton(sourceId: 'risks:milestones', items: List<Object>.from(shown)),
          ],
        ),
        if (!app.v29Ready)
          const InfoBanner(text: 'يلزم الترحيل 45 لعرض المعالم.', level: 'warning')
        else ...[
          if (late > 0) ...[
            InfoBanner(text: '$late معلم فات موعده المخطط ولم يُنجَز.', level: 'critical'),
            const SizedBox(height: 12),
          ],
          Wrap(spacing: 12, runSpacing: 12, children: [
            SizedBox(width: 190, child: KpiTile(label: 'قادمة', value: '$upcoming', sub: 'معلّقة لم يفت موعدها')),
            SizedBox(width: 190, child: KpiTile(label: 'متأخرة', value: '$late', color: late > 0 ? sem.danger : null, sub: 'فات المخطط ولم تُنجَز')),
            SizedBox(width: 190, child: KpiTile(label: 'متوقع تأخرها', value: '$slipping', color: slipping > 0 ? sem.wip : null, sub: 'المتوقع بعد المخطط')),
            SizedBox(
                width: 190,
                child: KpiTile(
                    label: 'الالتزام بالمواعيد',
                    value: kpiFormat(adherence.value, '%'),
                    color: adherence.met == null ? null : (adherence.met! ? sem.ok : sem.danger),
                    sub: 'المستهدف ${kpiFormat(adherence.target, '%')}')),
          ]),
          const SizedBox(height: 14),
          Wrap(spacing: 10, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.center, children: [
            SizedBox(
              width: 260,
              child: SelectField(label: 'المشروع', value: _project, items: projectOptions, onChanged: (v) => setState(() => _project = v)),
            ),
            for (final s in const [('open', 'المعلّقة'), ('late', 'المتأخرة'), ('done', 'المنجزة'), ('all', 'الكل')])
              ChoiceChip(label: Text(s.$2), selected: _status == s.$1, onSelected: (_) => setState(() => _status = s.$1)),
          ]),
          const SizedBox(height: 14),
          if (projectIds.isEmpty)
            const SectionCard(
              title: 'المعالم',
              child: EmptyState(
                title: 'لا معالم بهذا العرض',
                message: 'أضف معالم المشروع (تسليم الموقع، الصب، الاستلام الابتدائي…) ليظهر التزامه بالمواعيد.',
                icon: Icons.flag_outlined,
              ),
            )
          else
            for (final pid in projectIds)
              SectionCard(
                title: _projectName(app, pid),
                icon: Icons.apartment_outlined,
                subtitle: '${byProject[pid]!.length} معلم',
                child: Column(children: [
                  for (final m in byProject[pid]!) _row(context, app, m, today, sem),
                ]),
              ),
        ],
      ],
    );
  }

  Widget _row(BuildContext context, AppState app, PmMilestone m, DateTime today, Sem sem) {
    final (label, color) = _statusTone(m, today, sem);
    final dates = [
      'المخطط ${pmDay(m.planned)}',
      if (m.forecast != null && m.isPending) 'المتوقع ${pmDay(m.forecast)}',
      if (m.actual != null) 'الفعلي ${pmDay(m.actual)}',
    ].join(' · ');
    return ListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      title: Row(children: [
        Flexible(child: Text(m.title, style: const TextStyle(fontWeight: FontWeight.w600))),
        const SizedBox(width: 8),
        ToneBadge(label, color: color),
      ]),
      subtitle: Text(m.note.isEmpty ? dates : '$dates\n${m.note}', style: TextStyle(color: sem.muted)),
      isThreeLine: m.note.isNotEmpty,
      trailing: !app.canEditMilestones
          ? null
          : PopupMenuButton<String>(
              onSelected: (v) async {
                switch (v) {
                  case 'done':
                    await _complete(m);
                  case 'reopen':
                    await _run(() => app.setMilestoneStatus(m.id, 'pending'), 'أُعيد فتح المعلم');
                  case 'cancel':
                    await _run(() => app.setMilestoneStatus(m.id, 'cancelled'), 'أُلغي المعلم');
                  case 'edit':
                    await showMilestoneEditor(context, milestone: m);
                  case 'delete':
                    final ok = await confirmDialog(context,
                        title: 'حذف المعلم', message: 'يُحذف «${m.title}» نهائياً ويُسجَّل الحذف في سجل التدقيق.', confirmLabel: 'حذف', danger: true);
                    if (ok) await _run(() => app.deleteMilestone(m.id), 'حُذف المعلم');
                }
              },
              itemBuilder: (_) => [
                if (m.isPending) const PopupMenuItem(value: 'done', child: Text('تسجيل الإنجاز')),
                if (!m.isPending) const PopupMenuItem(value: 'reopen', child: Text('إعادة الفتح')),
                if (m.isPending) const PopupMenuItem(value: 'cancel', child: Text('إلغاء المعلم')),
                const PopupMenuItem(value: 'edit', child: Text('تعديل')),
                const PopupMenuItem(value: 'delete', child: Text('حذف')),
              ],
            ),
    );
  }
}

// =====================================================================
// مؤشرات الأداء
// =====================================================================

const _kpiSections = <(String, String, IconData)>[
  ('milestones', 'المعالم', Icons.flag_outlined),
  ('projects', 'أداء المشاريع', Icons.view_timeline_outlined),
  ('maintenance', 'الصيانة', Icons.build_circle_outlined),
  ('procurement', 'المشتريات', Icons.shopping_cart_outlined),
  ('stores', 'المخازن', Icons.inventory_2_outlined),
];

Future<void> showKpiDefEditor(BuildContext context, {KpiDef? def}) async {
  final app = AppScope.of(context);
  final ok = await showPmForm(
    context,
    title: def == null ? 'مؤشر جديد' : 'تعديل المؤشر',
    note: 'مؤشر تحدد أنت اسمه ومستهدفه واتجاه الأفضل فيه، وتُسجَّل له قيمة كل شهر. القيم أرقام غير سالبة.',
    sections: [
      const PmSection('التعريف', [
        PmField('name', 'اسم المؤشر', PmKind.text, required: true, max: 80, full: true),
        PmField('unit', 'الوحدة (مثل % أو يوم)', PmKind.text, max: 20),
        PmField('target', 'المستهدف', PmKind.decimal, required: true),
        PmField('direction', 'الأفضل', PmKind.select, required: true, options: [('higher', 'الأعلى أفضل'), ('lower', 'الأقل أفضل')]),
        PmField('active', 'فعّال', PmKind.toggle),
        PmField('note', 'ملاحظة / طريقة القياس', PmKind.multiline, max: 300, full: true),
      ]),
    ],
    values: def == null
        ? {'direction': 'higher', 'active': true}
        : {
            'name': def.name,
            'unit': def.unit,
            'target': def.target,
            'direction': def.higherBetter ? 'higher' : 'lower',
            'active': def.active,
            'note': def.note,
          },
    onSave: (d) => app.saveKpiDef(
      id: def?.id,
      name: '${d['name']}',
      unit: '${d['unit'] ?? ''}',
      target: (d['target'] as num).toDouble(),
      higherBetter: d['direction'] != 'lower',
      active: d['active'] == true,
      note: '${d['note'] ?? ''}',
    ),
  );
  if (ok && context.mounted) showToast(context, def == null ? 'أُضيف المؤشر' : 'حُفظ المؤشر');
}

Future<void> showKpiValueEditor(BuildContext context, KpiDef def, {KpiValue? value}) async {
  final app = AppScope.of(context);
  final now = DateTime.now();
  final periods = <(String, String)>[
    for (var i = 0; i < 14; i++)
      (kpiPeriodOf(DateTime(now.year, now.month - i, 1)), kpiPeriodOf(DateTime(now.year, now.month - i, 1))),
  ];
  final ok = await showPmForm(
    context,
    title: 'قيمة «${def.name}»',
    note: 'قيمة واحدة لكل شهر؛ تسجيل شهر موجود يحدّث قيمته.',
    sections: [
      PmSection('القيمة', [
        PmField('period', 'الشهر', PmKind.select, required: true, options: periods),
        PmField('value', 'القيمة${def.unit.isEmpty ? '' : ' (${def.unit})'}', PmKind.decimal, required: true),
        const PmField('note', 'ملاحظة', PmKind.multiline, max: 300, full: true),
      ]),
    ],
    values: value == null
        ? {'period': kpiPeriodOf(now)}
        : {'period': value.period, 'value': value.value, 'note': value.note},
    onSave: (d) => app.setKpiValue(def.id, '${d['period']}', (d['value'] as num).toDouble(), note: '${d['note'] ?? ''}'),
  );
  if (ok && context.mounted) showToast(context, 'سُجّلت القيمة');
}

Color _metColor(Sem sem, bool? met) => met == null ? sem.muted : (met ? sem.ok : sem.danger);

class KpiPage extends StatelessWidget {
  const KpiPage({super.key});

  Widget _builtinTile(KpiResult r, Sem sem) {
    final target = r.target == null
        ? null
        : 'المستهدف ${r.higherBetter ? '≥' : '≤'} ${kpiFormat(r.target, r.unit)}';
    return SizedBox(
      width: 250,
      child: KpiTile(
        label: r.title,
        value: kpiFormat(r.value, r.unit),
        color: _metColor(sem, r.met),
        sub: [if (target != null) target, if (r.sample > 0) 'العيّنة ${r.sample}' else 'لا بيانات كافية'].join(' · '),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final sem = Sem.of(context);
    final builtin = app.builtinKpis;
    final defs = app.kpiDefs;

    return PageBody(
      onRefresh: app.loadAll,
      children: [
        PageHeader(
          title: 'مؤشرات الأداء',
          subtitle: 'التزام المعالم وأداء المشاريع والأقسام التشغيلية تلقائياً من بيانات المنظومة، ومؤشرات مخصصة تحددها وتسجّل قيمها شهرياً.',
          icon: Icons.speed_outlined,
          actions: [
            if (app.canDefineKpi)
              FilledButton.icon(onPressed: () => showKpiDefEditor(context), icon: const Icon(Icons.add), label: const Text('مؤشر جديد')),
          ],
        ),
        if (!app.v29Ready)
          const InfoBanner(text: 'يلزم الترحيل 45 لعرض المؤشرات.', level: 'warning')
        else ...[
          InfoBanner(
            text: 'المؤشرات الآلية تُحسب على آخر $kpiWindowDays يوماً للأحداث المنتهية مع ما هو متأخر الآن؛ والأخضر بلوغ المستهدف والأحمر دونه. معادلاتها في الفصل 39.',
          ),
          const SizedBox(height: 14),
          for (final sec in _kpiSections)
            if (builtin.any((k) => k.section == sec.$1)) ...[
              SectionCard(
                title: sec.$2,
                icon: sec.$3,
                child: Wrap(spacing: 12, runSpacing: 12, children: [
                  for (final k in builtin.where((k) => k.section == sec.$1)) _builtinTile(k, sem),
                ]),
              ),
              const SizedBox(height: 4),
            ],
          SectionCard(
            title: 'مؤشرات مخصصة',
            icon: Icons.tune_outlined,
            subtitle: 'يعرّفها المدير، ويسجّل قيمها المدير وموظفو مكتبه',
            child: defs.isEmpty
                ? EmptyState(
                    title: 'لا مؤشرات مخصصة بعد',
                    message: app.canDefineKpi ? 'عرّف مؤشراً بمستهدف واتجاه أفضل، ثم سجّل قيمته كل شهر.' : 'لم يعرّف المدير مؤشرات بعد.',
                    icon: Icons.tune_outlined,
                  )
                : Column(children: [for (final d in defs) _customCard(context, app, d, sem)]),
          ),
        ],
      ],
    );
  }

  Widget _customCard(BuildContext context, AppState app, KpiDef d, Sem sem) {
    final vals = [for (final v in app.kpiValues) if (v.kpiId == d.id) v]..sort((a, b) => b.period.compareTo(a.period));
    final last = kpiLatest(vals);
    final att = last == null ? null : kpiAttainment(d, last.value);
    final met = att == null ? null : att >= 1;
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      title: Row(children: [
        Flexible(child: Text(d.name, style: const TextStyle(fontWeight: FontWeight.w700))),
        const SizedBox(width: 8),
        if (!d.active) ToneBadge('موقوف', color: sem.muted),
      ]),
      subtitle: Text(
        '${last == null ? 'لا قيمة بعد' : 'آخر قيمة ${kpiFormat(last.value, d.unit)} (${last.period})'}'
        ' · المستهدف ${d.higherBetter ? '≥' : '≤'} ${kpiFormat(d.target, d.unit)}'
        '${att == null ? '' : ' · التحقق ${(att * 100).round()}%'}',
        style: TextStyle(color: _metColor(sem, met)),
      ),
      children: [
        if (d.note.isNotEmpty) Align(alignment: AlignmentDirectional.centerStart, child: Text(d.note, style: TextStyle(color: sem.muted))),
        Wrap(spacing: 8, children: [
          if (app.canRecordKpi && d.active)
            TextButton.icon(onPressed: () => showKpiValueEditor(context, d), icon: const Icon(Icons.edit_calendar_outlined), label: const Text('تسجيل قيمة')),
          if (app.canDefineKpi)
            TextButton.icon(onPressed: () => showKpiDefEditor(context, def: d), icon: const Icon(Icons.edit_outlined), label: const Text('تعديل')),
          if (app.canDefineKpi)
            TextButton.icon(
              onPressed: () async {
                final ok = await confirmDialog(context,
                    title: 'حذف المؤشر', message: 'يُحذف «${d.name}» بكل قيمه المسجلة، ويُسجَّل الحذف في سجل التدقيق.', confirmLabel: 'حذف', danger: true);
                if (!ok) return;
                try {
                  await app.deleteKpiDef(d.id);
                  if (context.mounted) showToast(context, 'حُذف المؤشر');
                } catch (e) {
                  if (context.mounted) showToast(context, friendlyError(e), error: true);
                }
              },
              icon: const Icon(Icons.delete_outline),
              label: const Text('حذف'),
            ),
        ]),
        if (vals.isNotEmpty)
          PmTable(
            columns: const ['الشهر', 'القيمة', 'التحقق', 'ملاحظة'],
            rows: [
              for (final v in vals.take(12))
                [
                  v.period,
                  kpiFormat(v.value, d.unit),
                  () {
                    final a = kpiAttainment(d, v.value);
                    return a == null ? '—' : '${(a * 100).round()}%';
                  }(),
                  v.note.isEmpty ? '—' : v.note,
                ],
            ],
          ),
      ],
    );
  }
}
