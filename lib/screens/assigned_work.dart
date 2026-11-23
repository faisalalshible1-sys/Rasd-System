import 'package:flutter/material.dart';

import '../app_state.dart';
import '../models.dart';
import '../registers.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';
import 'hub.dart' show sectionName;
import 'project_detail.dart';
import 'swot.dart' show showActionDetails;

/// «المهام المسندة» (الترحيل 34): لمن لا يرى الدورة المستندية، ما أُسند إلى قسمه منها — نماذج الدورة في كل عقد
/// (مثل «نطاق وطريقة عمل» للشؤون الفنية) وإجراءات خطة SWOT المسندة إلى القسم — دون الاطلاع على بقية الدورة.
class AssignedWorkPage extends StatefulWidget {
  const AssignedWorkPage({super.key, required this.section});

  final String section;

  @override
  State<AssignedWorkPage> createState() => _AssignedWorkPageState();
}

class _AssignedWorkPageState extends State<AssignedWorkPage> {
  bool _pendingOnly = true;
  String _q = '';

  static bool _open(FormStatus s) => s != FormStatus.done && s != FormStatus.na;

  void _openProject(String id) =>
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ProjectDetailPage(projectId: id)));

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final sem = Sem.of(context);
    if (!app.loadedOnce) return const Center(child: CircularProgressIndicator());
    final all = app.assignedForms;
    final swot = app.assignedSwot;
    var pending = 0, done = 0;
    for (final (p, ds) in all) {
      for (final d in ds) {
        _open(app.statusOf(p.id, d.key)) ? pending++ : done++;
      }
    }
    final q = _q.trim();
    final rows = [
      for (final r in all)
        if ((!_pendingOnly || r.$2.any((d) => _open(app.statusOf(r.$1.id, d.key)))) &&
            (q.isEmpty || r.$1.label.contains(q) || r.$1.company.contains(q) || r.$1.code.contains(q)))
          r,
    ];
    final actions = [for (final x in swot) if (!_pendingOnly || x.status != 'completed') x];

    return PageBody(
      onRefresh: app.loadAll,
      children: [
        PageHeader(
          icon: Icons.assignment_ind_outlined,
          title: 'المهام المسندة',
          subtitle: 'ما أُسند إلى ${sectionName(widget.section)} من الدورة المستندية وخطة SWOT: تحدّث حالته هنا من قسمك، '
              'ولا تظهر بقية الدورة ولا تفاصيل العقود الأخرى.',
        ),
        ResponsiveGrid(minItemWidth: 170, children: [
          StatCard(label: 'العقود', value: '${all.length}', icon: Icons.folder_open_outlined),
          StatCard(label: 'نماذج بانتظار الإجراء', value: '$pending', icon: Icons.pending_actions_outlined, color: pending > 0 ? sem.wip : sem.ok),
          StatCard(label: 'نماذج مكتملة', value: '$done', icon: Icons.task_alt_rounded, color: sem.ok),
          if (swot.isNotEmpty)
            StatCard(
              label: 'إجراءات SWOT المسندة',
              value: '${swot.where((x) => x.status != 'completed').length} / ${swot.length}',
              icon: Icons.insights_outlined,
            ),
        ]),
        const SizedBox(height: 14),
        Wrap(spacing: 10, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.center, children: [
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: true, label: Text('بانتظار الإجراء'), icon: Icon(Icons.pending_actions_outlined)),
              ButtonSegment(value: false, label: Text('الكل'), icon: Icon(Icons.list_alt_rounded)),
            ],
            selected: {_pendingOnly},
            onSelectionChanged: (v) => setState(() => _pendingOnly = v.first),
          ),
          if (all.length > 6)
            SizedBox(
              width: 260,
              child: TextField(
                onChanged: (v) => setState(() => _q = v),
                decoration: fieldDeco('بحث في العقود', hint: 'الرقم أو الاسم أو الشركة', prefixIcon: const Icon(Icons.search_rounded)),
              ),
            ),
        ]),
        const SizedBox(height: 14),
        if (all.isNotEmpty)
          SectionCard(
            title: 'نماذج الدورة المستندية',
            icon: Icons.fact_check_outlined,
            subtitle: 'افتح العقد لتحديث حالة نموذجك، وتكليف المهندسين في نماذج التكليف، ومتابعة طلبات الاعتماد.',
            child: rows.isEmpty
                ? Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(_pendingOnly ? 'لا نماذج بانتظار الإجراء الآن.' : 'لا نتائج.', style: TextStyle(color: sem.muted)),
                  )
                : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    for (var i = 0; i < rows.length; i++) ...[
                      if (i > 0) Divider(height: 18, color: sem.rule),
                      _ContractRow(project: rows[i].$1, forms: rows[i].$2, onTap: () => _openProject(rows[i].$1.id)),
                    ],
                  ]),
          ),
        if (swot.isNotEmpty) ...[
          const SizedBox(height: 14),
          SectionCard(
            title: 'إجراءات خطة SWOT المسندة إلى القسم',
            icon: Icons.insights_outlined,
            subtitle: 'يحدّث رئيس القسم إنجاز إجراءات قسمه من هنا، دون الاطلاع على بقية التحليل.',
            child: actions.isEmpty
                ? Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text('كل إجراءات القسم مكتملة.', style: TextStyle(color: sem.muted)),
                  )
                : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    for (var i = 0; i < actions.length; i++) ...[
                      if (i > 0) Divider(height: 14, color: sem.rule),
                      _ActionRow(action: actions[i]),
                    ],
                  ]),
          ),
        ],
      ],
    );
  }
}

class _ContractRow extends StatelessWidget {
  const _ContractRow({required this.project, required this.forms, required this.onTap});

  final Project project;
  final List<FormDef> forms;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final sem = Sem.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            ContractTag(project),
            const SizedBox(width: 8),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(project.title, style: const TextStyle(fontWeight: FontWeight.w700), maxLines: 1, overflow: TextOverflow.ellipsis),
                if (project.company.trim().isNotEmpty)
                  Text(project.company, style: TextStyle(color: sem.muted, fontSize: 12.5), maxLines: 1, overflow: TextOverflow.ellipsis),
              ]),
            ),
            Icon(Icons.chevron_left_rounded, color: sem.muted),
          ]),
          const SizedBox(height: 8),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final d in forms) _FormChip(project: project, form: d, pending: app.pendingFor(project.id, d.key) != null),
          ]),
        ]),
      ),
    );
  }
}

class _FormChip extends StatelessWidget {
  const _FormChip({required this.project, required this.form, required this.pending});

  final Project project;
  final FormDef form;
  final bool pending;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final sem = Sem.of(context);
    final s = app.statusOf(project.id, form.key);
    final c = sem.statusColor(s);
    return Tooltip(
      message: pending ? 'بانتظار اعتماد المدير' : 'الحالة: ${s.label}',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          color: c.withAlpha(28),
          borderRadius: BorderRadius.circular(99),
          border: Border.all(color: c.withAlpha(90)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(pending ? Icons.hourglass_top_rounded : Icons.circle, size: pending ? 13 : 8, color: pending ? sem.wip : c),
          const SizedBox(width: 6),
          Text('${form.name} · ${s.label}', style: TextStyle(color: c, fontWeight: FontWeight.w700, fontSize: 12)),
        ]),
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({required this.action});

  final SwotAction action;

  @override
  Widget build(BuildContext context) {
    final sem = Sem.of(context);
    final x = action;
    final done = x.status == 'completed';
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => showActionDetails(context, x),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          NoTag(x.code),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(x.action, style: const TextStyle(fontWeight: FontWeight.w700, height: 1.4)),
              const SizedBox(height: 4),
              Wrap(spacing: 6, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                ToneBadge(x.statusLabel, color: done ? sem.ok : (x.status == 'stalled' ? sem.danger : sem.wip)),
                Text('الإنجاز ${x.progress == null ? '—' : '${(x.progress! * 100).round()}%'}',
                    style: TextStyle(color: sem.muted, fontSize: 12.5)),
                if (x.department.isNotEmpty) Text(x.department, style: TextStyle(color: sem.muted, fontSize: 12.5)),
              ]),
            ]),
          ),
          Icon(Icons.chevron_left_rounded, color: sem.muted),
        ]),
      ),
    );
  }
}
