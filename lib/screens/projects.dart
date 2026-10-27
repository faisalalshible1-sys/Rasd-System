import 'package:flutter/material.dart';

import '../app_state.dart';
import '../models.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';
import 'project_detail.dart';

/// UC-03: البحث والاستعلام عن المشاريع.
class ProjectsPage extends StatefulWidget {
  const ProjectsPage({super.key});

  @override
  State<ProjectsPage> createState() => _ProjectsPageState();
}

class _ProjectsPageState extends State<ProjectsPage> {
  late final TextEditingController _search;

  @override
  void initState() {
    super.initState();
    _search = TextEditingController(text: AppScope.read(context).search);
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final sem = Sem.of(context);
    if (!app.loadedOnce) return const Center(child: CircularProgressIndicator());
    final list = app.filteredProjects();
    final ff = app.formFilter;

    return RefreshIndicator(
      onRefresh: app.loadAll,
      child: CustomScrollView(
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                TextField(
                  controller: _search,
                  onChanged: (v) => app.setProjectFilters(search: v),
                  decoration: InputDecoration(
                    hintText: 'ابحث برقم التكليف أو الاسم أو الشركة أو المهندس',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _search.text.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.close),
                            onPressed: () {
                              _search.clear();
                              app.setProjectFilters(search: '');
                            },
                          ),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                    filled: true,
                    fillColor: sem.surface,
                  ),
                ),
                const SizedBox(height: 10),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (final c in <CycleState?>[null, CycleState.running, CycleState.complete, CycleState.notStarted])
                        Padding(
                          padding: const EdgeInsetsDirectional.only(end: 6),
                          child: ChoiceChip(
                            label: Text(c?.label ?? 'الكل'),
                            selected: app.cycleFilter == c,
                            onSelected: (_) => app.setProjectFilters(cycle: c, clearCycle: c == null),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: SelectField(
                        label: 'المرحلة الحالية',
                        value: app.stageFilter?.toString() ?? '',
                        items: [('', '(الكل)'), for (var i = 0; i <= stageNames.length; i++) ('$i', stageName(i))],
                        onChanged: (v) => app.setProjectFilters(stage: v.isEmpty ? null : int.parse(v), clearStage: v.isEmpty),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: SelectField(
                        label: 'الترتيب',
                        value: app.sort,
                        items: const [
                          ('order', 'رقم التكليف'),
                          ('low', 'الأقل إنجازاً'),
                          ('high', 'الأعلى إنجازاً'),
                          ('recent', 'آخر تحديث'),
                        ],
                        onChanged: (v) => app.setProjectFilters(sort: v),
                      ),
                    ),
                  ],
                ),
                if (ff != null) ...[
                  const SizedBox(height: 10),
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: InputChip(
                      label: Text('${app.formFilterNextOnly ? 'المستند التالي' : 'غير مكتمل'}: ${app.formDef(ff)?.name ?? ff}'),
                      onDeleted: () => app.setProjectFilters(clearForm: true),
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                Text(
                  list.length == app.projects.length ? '${list.length} مشروعاً' : '${list.length} من ${app.projects.length} مشروعاً',
                  style: TextStyle(color: sem.muted, fontSize: 13),
                ),
              ]),
            ),
          ),
          if (list.isEmpty)
            const SliverToBoxAdapter(
              child: EmptyState(title: 'لا توجد نتائج', message: 'جرّب كلمة بحث أخرى أو اختر «الكل» في التصفية.', icon: Icons.search_off),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
              sliver: SliverLayoutBuilder(builder: (context, constraints) {
                final cols = constraints.crossAxisExtent >= 760 ? 2 : 1;
                if (cols == 1) {
                  return SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, i) => Padding(padding: const EdgeInsets.only(bottom: 10), child: ProjectCard(project: list[i])),
                      childCount: list.length,
                    ),
                  );
                }
                return SliverGrid(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                    mainAxisExtent: 186,
                  ),
                  delegate: SliverChildBuilderDelegate((context, i) => ProjectCard(project: list[i]), childCount: list.length),
                );
              }),
            ),
        ],
      ),
    );
  }
}

class ProjectCard extends StatelessWidget {
  const ProjectCard({super.key, required this.project});

  final Project project;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final sem = Sem.of(context);
    final pr = app.progressOf(project);
    final pendingCount = app.pendingRequests.where((r) => r.projectId == project.id).length;
    return Material(
      color: sem.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: sem.rule)),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ProjectDetailPage(projectId: project.id))),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  NoTag(project.assignNo),
                  const SizedBox(width: 8),
                  if (pendingCount > 0)
                    Tooltip(
                      message: 'طلبات اعتماد معلّقة',
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.hourglass_top, size: 15, color: sem.wip),
                        Text(' $pendingCount', style: TextStyle(color: sem.wip, fontWeight: FontWeight.w700, fontSize: 12)),
                      ]),
                    ),
                  const Spacer(),
                  CyclePill(pr.cycle),
                ],
              ),
              const SizedBox(height: 8),
              Text(project.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontWeight: FontWeight.w700, color: project.name.isEmpty ? sem.muted : null)),
              const SizedBox(height: 2),
              Text(
                [project.company.isEmpty ? 'لم تُحدَّد الشركة' : project.company, if (project.owner.isNotEmpty) project.owner].join(' · '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: sem.muted, fontSize: 12.5),
              ),
              const SizedBox(height: 10),
              CycleStrip(defs: app.formDefs, cells: pr.cells),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: Text.rich(
                      TextSpan(children: [
                        TextSpan(text: pr.next == null ? '' : 'التالي: ', style: TextStyle(color: sem.muted)),
                        TextSpan(text: pr.next?.name ?? stageDoneName, style: const TextStyle(fontWeight: FontWeight.w600)),
                      ]),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12.5),
                    ),
                  ),
                  Text(pctText(pr.pct), style: const TextStyle(fontWeight: FontWeight.w700, fontFeatures: [FontFeature.tabularFigures()])),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// UC-11 / UC-12: إضافة مشروع أو تعديل بياناته.
Future<void> openProjectEditor(BuildContext context, Project? project) async {
  final app = AppScope.read(context);
  final newId = await showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
      child: _ProjectEditor(app: app, project: project),
    ),
  );
  if (newId != null && project == null && context.mounted) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ProjectDetailPage(projectId: newId)));
  }
}

class _ProjectEditor extends StatefulWidget {
  const _ProjectEditor({required this.app, required this.project});

  final AppState app;
  final Project? project;

  @override
  State<_ProjectEditor> createState() => _ProjectEditorState();
}

class _ProjectEditorState extends State<_ProjectEditor> {
  late final TextEditingController _assign;
  late final TextEditingController _code;
  late final TextEditingController _name;
  late final TextEditingController _owner;
  late final TextEditingController _company;
  late String _department;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final p = widget.project;
    var next = '';
    if (p == null) {
      final nums = widget.app.projects.map((x) => int.tryParse(x.assignNo)).whereType<int>().toList();
      final mx = nums.isEmpty ? 0 : nums.reduce((a, b) => a > b ? a : b);
      next = (mx + 1).toString().padLeft(3, '0');
    }
    _assign = TextEditingController(text: p?.assignNo ?? next);
    _code = TextEditingController(text: p?.code ?? '');
    _name = TextEditingController(text: p?.name ?? '');
    _owner = TextEditingController(text: p?.owner ?? '');
    _company = TextEditingController(text: p?.company ?? '');
    _department = p?.department ?? 'supervision';
  }

  @override
  void dispose() {
    _assign.dispose();
    _code.dispose();
    _name.dispose();
    _owner.dispose();
    _company.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final data = <String, dynamic>{
      'assign_no': _assign.text.trim(),
      'code': _code.text.trim(),
      'name': _name.text.trim(),
      'owner': _owner.text.trim(),
      'company': _company.text.trim(),
      'department': _department,
    };
    if ((data['assign_no'] as String).isEmpty && (data['name'] as String).isEmpty) {
      setState(() => _error = 'اكتب رقم التكليف أو اسم المشروع على الأقل.');
      return;
    }
    final dup = widget.app.projects.any((x) => x.assignNo == data['assign_no'] && x.id != widget.project?.id && x.assignNo.isNotEmpty);
    if (dup) {
      setState(() => _error = 'رقم التكليف ${data['assign_no']} مستخدم في مشروع آخر.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final id = await widget.app.saveProject(id: widget.project?.id, data: data);
      if (!mounted) return;
      showToast(context, widget.project == null ? 'أُضيف المشروع' : 'حُفظت البيانات');
      Navigator.of(context).pop(id);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = friendlyError(e);
        });
      }
    }
  }

  Widget _suggest(TextEditingController c, String label, List<String> options) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(controller: c, decoration: fieldDeco(label), onChanged: (_) => setState(() {})),
        if (options.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final o in options.where((o) => o != c.text.trim()).take(6))
                  ActionChip(
                    label: Text(o, maxLines: 1, overflow: TextOverflow.ellipsis),
                    onPressed: () => setState(() => c.text = o),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final sem = Sem.of(context);
    final isNew = widget.project == null;
    final supervising = widget.app.departments.where((d) => d.canSupervise).toList();
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(isNew ? 'مشروع جديد' : 'تعديل بيانات المشروع',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(child: TextField(controller: _assign, decoration: fieldDeco('رقم التكليف'), keyboardType: TextInputType.number)),
                const SizedBox(width: 10),
                Expanded(child: TextField(controller: _code, decoration: fieldDeco('رمز المشروع'))),
              ],
            ),
            const SizedBox(height: 12),
            TextField(controller: _name, decoration: fieldDeco('اسم المشروع'), minLines: 1, maxLines: 3),
            const SizedBox(height: 12),
            _suggest(_owner, 'مالك المشروع', widget.app.owners),
            const SizedBox(height: 12),
            _suggest(_company, 'اسم الشركة', widget.app.companies),
            const SizedBox(height: 12),
            SelectField(
              label: 'القسم المشرف',
              value: _department,
              items: [
                for (final d in supervising) (d.key, d.name),
                if (supervising.isEmpty) ('supervision', 'الإشراف والتنسيق'),
              ],
              onChanged: (v) => setState(() => _department = v),
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(_error!, style: TextStyle(color: sem.danger)),
            ],
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(child: OutlinedButton(onPressed: _busy ? null : () => Navigator.of(context).pop(), child: const Text('إلغاء'))),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    onPressed: _busy ? null : _save,
                    child: _busy
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : Text(isNew ? 'إضافة المشروع' : 'حفظ'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
