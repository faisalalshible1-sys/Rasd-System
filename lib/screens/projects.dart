import 'package:flutter/material.dart';

import '../app_state.dart';
import '../models.dart';
import '../ui/motion.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';
import 'project_detail.dart';

/// UC-03: البحث والاستعلام عن العقود وأعمالها.
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
    if (!app.loadedOnce) return const SkeletonPage(cards: 5);
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
                    hintText: 'ابحث برقم العقد أو التكليف أو الاسم أو الشركة أو المهندس',
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
                          ('order', 'الترتيب الأصلي'),
                          ('contract', 'رقم العقد'),
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
                  list.length == app.projects.length
                      ? '${term('contracts')}: ${list.length}'
                      : '${term('contracts')}: ${list.length} من ${app.projects.length}',
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
                // ظهور متتابع للدفعة الأولى فقط، وكل بطاقة بمفتاح عقدها لتتحرك عند تغيّر التصفية
                Widget card(int i) => FadeSlideIn(
                      key: ValueKey('card-${list[i].id}'),
                      delay: Duration(milliseconds: i < 8 ? i * 45 : 0),
                      child: ProjectCard(project: list[i]),
                    );
                if (cols == 1) {
                  return SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, i) => Padding(padding: const EdgeInsets.only(bottom: 10), child: card(i)),
                      childCount: list.length,
                    ),
                  );
                }
                return SliverGrid(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                    mainAxisExtent: 212,
                  ),
                  delegate: SliverChildBuilderDelegate((context, i) => card(i), childCount: list.length),
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
    final companies = app.companiesOf(project);
    final works = app.worksOf(project.id).length;
    final engs = app.engineersOf(project.id).length;
    return HoverLift(
      radius: 14,
      child: Material(
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
                  Hero(
                    tag: 'contract-${project.id}',
                    child: Material(type: MaterialType.transparency, child: ContractTag(project)),
                  ),
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
                [
                  companies.isEmpty ? 'لم تُحدَّد الشركة' : (companies.length > 2 ? '${companies.take(2).join('، ')} و${companies.length - 2} غيرها' : companies.join('، ')),
                  if (project.owner.isNotEmpty) project.owner,
                ].join(' · '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: sem.muted, fontSize: 12.5),
              ),
              if (app.v3Ready && (works > 1 || engs > 0)) ...[
                const SizedBox(height: 4),
                Row(
                  children: [
                    if (works > 1) ...[
                      Icon(Icons.account_tree_outlined, size: 14, color: sem.muted),
                      Text(' $works أعمال', style: TextStyle(color: sem.muted, fontSize: 12)),
                      const SizedBox(width: 12),
                    ],
                    if (engs > 0) ...[
                      Icon(Icons.engineering_outlined, size: 14, color: sem.muted),
                      Text(' $engs تكليف', style: TextStyle(color: sem.muted, fontSize: 12)),
                    ],
                  ],
                ),
              ],
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
      ),
    );
  }
}

/// UC-11 / UC-12: إضافة عقد أو تعديل بياناته.
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
  late final TextEditingController _code;
  late final TextEditingController _name;
  late final TextEditingController _owner;
  late final TextEditingController _company;
  late final TextEditingController _contractNo;
  late String _department;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final p = widget.project;
    _code = TextEditingController(text: p?.code ?? '');
    _name = TextEditingController(text: p?.name ?? '');
    _owner = TextEditingController(text: p?.owner ?? '');
    _company = TextEditingController(text: p?.company ?? '');
    _contractNo = TextEditingController(text: p?.contractNo ?? '');
    _department = p?.department ?? 'supervision';
  }

  @override
  void dispose() {
    _code.dispose();
    _name.dispose();
    _owner.dispose();
    _company.dispose();
    _contractNo.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    // رقم التكليف القديم للعقد لم يعد يُدخل ولا يُرسل؛ يبقى في قاعدة البيانات كما هو (الإصدار 1.4.0)
    final data = <String, dynamic>{
      'code': _code.text.trim(),
      'name': _name.text.trim(),
      'owner': _owner.text.trim(),
      'company': _company.text.trim(),
      'department': _department,
    };
    if ((data['name'] as String).isEmpty) {
      setState(() => _error = 'اكتب اسم المشروع.');
      return;
    }
    final no = _contractNo.text.trim();
    if (_canContractNo && no.isNotEmpty && widget.app.projects.any((x) => x.contractNo == no && x.id != widget.project?.id)) {
      setState(() => _error = 'رقم العقد $no مستخدم لعقد آخر. لربط الأعمال بعقد واحد استخدم «دمج أعمال» من صفحة العقد.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final id = await widget.app.saveProject(id: widget.project?.id, data: data);
      if (_canContractNo && no != (widget.project?.contractNo ?? '')) {
        await widget.app.setContractNo(id, no);
      }
      if (!mounted) return;
      showToast(context, widget.project == null ? 'أُضيف العقد' : 'حُفظت البيانات');
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

  /// رقم العقد من صلاحية مكتب العقود والمدير (والمحرر هنا للمدير وموظفي مكتبه).
  bool get _canContractNo => widget.app.v3Ready && widget.app.isDirector;

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
            Text(isNew ? term('new_contract') : 'تعديل بيانات ${term('contract')}',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 16),
            if (_canContractNo) ...[
              TextField(
                controller: _contractNo,
                textDirection: TextDirection.ltr,
                decoration: fieldDeco('رقم العقد', helper: 'من مكتب العقود. يمكن تركه الآن وإدخاله لاحقاً من صفحة العقد.'),
              ),
              const SizedBox(height: 12),
            ],
            TextField(controller: _code, decoration: fieldDeco('رمز المشروع')),
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
                        : Text(isNew ? 'إضافة' : 'حفظ'),
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
