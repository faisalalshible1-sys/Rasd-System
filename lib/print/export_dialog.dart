// نافذة «تصدير وطباعة»: تُفتح من أي صفحة. اختيار السجل والنطاق والتصفية والأعمدة والقالب والصيغة،
// ثم معاينة الصفحة، أو الطباعة، أو حفظ الملف.

import 'package:flutter/material.dart';

import '../app_state.dart';
import '../models.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';
import 'exporter.dart';
import 'model.dart';
import 'preview.dart';
import 'sources.dart';

/// زر «تصدير وطباعة» للصفحات: [items] العناصر المعروضة (بعد البحث والتصفية) إن وُجدت.
class ExportButton extends StatelessWidget {
  const ExportButton({super.key, required this.sourceId, this.items, this.projectId, this.compact = false});

  final String sourceId;
  final List<Object>? items;
  final String? projectId;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    void open() => showExportDialog(context, sourceId: sourceId, items: items, projectId: projectId);
    if (compact) {
      return IconButton(tooltip: 'تصدير وطباعة', onPressed: open, icon: const Icon(Icons.print_outlined));
    }
    return OutlinedButton.icon(onPressed: open, icon: const Icon(Icons.print_outlined), label: const Text('تصدير وطباعة'));
  }
}

/// يفتح نافذة التصدير. [onDesign] يفتح مصمم الصفحة على السجل نفسه (من قسم الطباعة).
Future<void> showExportDialog(BuildContext context, {String? sourceId, List<Object>? items, String? projectId}) {
  final narrow = MediaQuery.sizeOf(context).width < 720;
  final dialog = _ExportDialog(sourceId: sourceId, items: items, projectId: projectId);
  if (narrow) {
    return Navigator.of(context).push(MaterialPageRoute<void>(fullscreenDialog: true, builder: (_) => dialog));
  }
  return showDialog<void>(
    context: context,
    builder: (_) => Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 920, maxHeight: 860), child: dialog),
    ),
  );
}

class _ExportDialog extends StatefulWidget {
  const _ExportDialog({this.sourceId, this.items, this.projectId});

  final String? sourceId;
  final List<Object>? items;
  final String? projectId;

  @override
  State<_ExportDialog> createState() => _ExportDialogState();
}

class _ExportDialogState extends State<_ExportDialog> {
  ExportSource? _source;
  bool _onlyShown = true;
  String? _project;
  DateTime? _from;
  DateTime? _to;
  final _search = TextEditingController();
  List<String> _cols = [];
  String _templateId = '';
  PrintConfig _config = PrintConfig();
  ExportFormat _format = ExportFormat.pdf;
  bool _init = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_init) return;
    _init = true;
    final app = AppScope.read(context);
    final sources = exportSources(app);
    _project = widget.projectId;
    _setSource(widget.sourceId == null ? null : exportSource(app, widget.sourceId!) ?? (sources.isEmpty ? null : sources.first));
    final d = app.defaultPrintTemplate;
    if (d != null) {
      _templateId = d.id;
      _config = d.config.copy();
    }
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _setSource(ExportSource? s) {
    _source = s;
    _cols = s == null ? [] : [for (final c in s.columns) if (c.on) c.key];
    if (_config.groupBy.isNotEmpty && !(s?.columns.any((c) => c.key == _config.groupBy) ?? false)) _config.groupBy = '';
  }

  ExportTable? _table(AppState app) {
    final s = _source;
    if (s == null) return null;
    final items = widget.items != null && _onlyShown && s.id == widget.sourceId ? widget.items : null;
    final t = s.build(app, ExportQuery(projectId: _project, from: _from, to: _to, items: items, search: _search.text));
    return t.select(_cols);
  }

  Future<void> _pickDate(bool from) async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: (from ? _from : _to) ?? now,
      firstDate: DateTime(2015),
      lastDate: DateTime(now.year + 5),
      helpText: from ? 'من تاريخ' : 'إلى تاريخ',
    );
    if (d != null) setState(() => from ? _from = d : _to = d);
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final sem = Sem.of(context);
    final t = Theme.of(context).textTheme;
    final sources = exportSources(app);
    final s = _source;
    final table = _table(app);
    final narrow = MediaQuery.sizeOf(context).width < 720;

    Widget label(String text, [IconData? icon]) => Padding(
          padding: const EdgeInsets.only(top: 16, bottom: 8),
          child: Row(children: [
            if (icon != null) ...[Icon(icon, size: 18, color: sem.muted), const SizedBox(width: 6)],
            Text(text, style: t.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
          ]),
        );

    final body = ListView(padding: const EdgeInsets.fromLTRB(20, 4, 20, 16), children: [
      label('السجل', Icons.dataset_outlined),
      DropdownButtonFormField<String>(
        initialValue: s?.id,
        isExpanded: true,
        decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true),
        items: [
          for (final x in sources)
            DropdownMenuItem(
              value: x.id,
              child: Text('${exportSectionNames[x.section] ?? ''} · ${x.title} (${x.count(app)})', overflow: TextOverflow.ellipsis),
            ),
        ],
        onChanged: (v) => setState(() => _setSource(v == null ? null : exportSource(app, v))),
      ),
      if (widget.items != null && s?.id == widget.sourceId)
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: SegmentedButton<bool>(
            segments: [
              ButtonSegment(value: true, label: Text('المعروض في الصفحة (${widget.items!.length})'), icon: const Icon(Icons.filter_alt_outlined, size: 18)),
              ButtonSegment(value: false, label: Text('كل السجل (${s!.count(app)})'), icon: const Icon(Icons.select_all_rounded, size: 18)),
            ],
            selected: {_onlyShown},
            onSelectionChanged: (v) => setState(() => _onlyShown = v.first),
          ),
        ),
      if (s != null && (s.byProject || s.byDate)) ...[
        label('التصفية', Icons.tune_rounded),
        Wrap(spacing: 10, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.center, children: [
          if (s.byProject)
            SizedBox(
              width: narrow ? double.infinity : 300,
              child: DropdownButtonFormField<String>(
                initialValue: _project ?? '',
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'العقد', border: OutlineInputBorder(), isDense: true),
                items: [
                  const DropdownMenuItem(value: '', child: Text('كل العقود')),
                  for (final p in app.projects) DropdownMenuItem(value: p.id, child: Text(p.label, overflow: TextOverflow.ellipsis)),
                ],
                onChanged: (v) => setState(() => _project = v == null || v.isEmpty ? null : v),
              ),
            ),
          if (s.byDate) ...[
            OutlinedButton.icon(
              onPressed: () => _pickDate(true),
              icon: const Icon(Icons.event_outlined, size: 18),
              label: Text(_from == null ? '${s.dateLabel}: من' : 'من ${dayText(_from)}'),
            ),
            OutlinedButton.icon(
              onPressed: () => _pickDate(false),
              icon: const Icon(Icons.event_outlined, size: 18),
              label: Text(_to == null ? 'إلى' : 'إلى ${dayText(_to)}'),
            ),
            if (_from != null || _to != null)
              IconButton(tooltip: 'مسح الفترة', onPressed: () => setState(() => _from = _to = null), icon: const Icon(Icons.close_rounded)),
          ],
          SizedBox(
            width: narrow ? double.infinity : 220,
            child: TextField(
              controller: _search,
              decoration: const InputDecoration(labelText: 'بحث في القيم', border: OutlineInputBorder(), isDense: true, prefixIcon: Icon(Icons.search_rounded)),
              onChanged: (_) => setState(() {}),
            ),
          ),
        ]),
      ],
      if (s != null) ...[
        label('الأعمدة', Icons.view_column_outlined),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final c in s.columns)
            FilterChip(
              label: Text(c.label),
              selected: _cols.contains(c.key),
              onSelected: (v) => setState(() {
                if (v) {
                  // يحافظ على ترتيب الأعمدة الأصلي
                  _cols = [for (final x in s.columns) if (_cols.contains(x.key) || x.key == c.key) x.key];
                } else if (_cols.length > 1) {
                  _cols.remove(c.key);
                }
              }),
            ),
          TextButton(onPressed: () => setState(() => _cols = [for (final c in s.columns) c.key]), child: const Text('الكل')),
          TextButton(onPressed: () => setState(() => _cols = [for (final c in s.columns) if (c.on) c.key]), child: const Text('الافتراضي')),
        ]),
      ],
      label('الصفحة والقالب', Icons.design_services_outlined),
      Wrap(spacing: 10, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.center, children: [
        SizedBox(
          width: narrow ? double.infinity : 260,
          child: DropdownButtonFormField<String>(
            initialValue: _templateId,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'القالب', border: OutlineInputBorder(), isDense: true),
            items: [
              const DropdownMenuItem(value: '', child: Text('التصميم الافتراضي للمنظومة')),
              for (final tp in app.printTemplates)
                DropdownMenuItem(value: tp.id, child: Text('${tp.name}${tp.isDefault ? ' (افتراضي)' : ''}${tp.shared ? '' : ' · خاص'}', overflow: TextOverflow.ellipsis)),
            ],
            onChanged: (v) => setState(() {
              _templateId = v ?? '';
              final tp = app.printTemplates.where((x) => x.id == _templateId).firstOrNull;
              final group = _config.groupBy;
              _config = tp == null ? PrintConfig() : tp.config.copy();
              if (_config.groupBy.isEmpty) _config.groupBy = group;
            }),
          ),
        ),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'auto', label: Text('تلقائي')),
            ButtonSegment(value: 'portrait', label: Text('عمودي')),
            ButtonSegment(value: 'landscape', label: Text('أفقي')),
          ],
          selected: {_config.orientation},
          onSelectionChanged: (v) => setState(() => _config.orientation = v.first),
        ),
        DropdownButton<String>(
          value: _config.paper,
          items: const [
            DropdownMenuItem(value: 'A4', child: Text('A4')),
            DropdownMenuItem(value: 'A3', child: Text('A3')),
            DropdownMenuItem(value: 'A5', child: Text('A5')),
            DropdownMenuItem(value: 'Letter', child: Text('Letter')),
            DropdownMenuItem(value: 'Legal', child: Text('Legal')),
          ],
          onChanged: (v) => setState(() => _config.paper = v ?? 'A4'),
        ),
        if (s != null)
          SizedBox(
            width: narrow ? double.infinity : 220,
            child: DropdownButtonFormField<String>(
              key: ValueKey('grp${s.id}${_config.groupBy}${_templateId}${_cols.join()}'),
              initialValue: _config.groupBy,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'تجميع حسب', border: OutlineInputBorder(), isDense: true),
              items: [
                const DropdownMenuItem(value: '', child: Text('دون تجميع')),
                for (final c in s.columns)
                  if (_cols.contains(c.key) && !c.numeric && c.type != ColType.long) DropdownMenuItem(value: c.key, child: Text(c.label)),
              ],
              onChanged: (v) => setState(() => _config.groupBy = v ?? ''),
            ),
          ),
      ]),
      const SizedBox(height: 6),
      Wrap(spacing: 6, runSpacing: 0, children: [
        _toggle('المجاميع', _config.totals, (v) => _config.totals = v),
        _toggle('ترقيم الصفوف', _config.rowNumbers, (v) => _config.rowNumbers = v),
        _toggle('المؤشرات', _config.showSummary, (v) => _config.showSummary = v),
        _toggle('التوقيعات', _config.showSignatures, (v) => _config.showSignatures = v),
        _toggle('صفحة غلاف', _config.cover, (v) => _config.cover = v),
        _toggle('رمز التحقق', _config.qr, (v) => _config.qr = v),
      ]),
      label('الصيغة', Icons.file_present_outlined),
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final f in ExportFormat.values)
          Tooltip(
            message: f.hint,
            child: ChoiceChip(
              avatar: Icon(f.icon, size: 18),
              label: Text(f.label),
              selected: _format == f,
              onSelected: (_) => setState(() => _format = f),
            ),
          ),
      ]),
      Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text(
          _format.styled
              ? '${_format.hint}. ${_format == ExportFormat.docx ? 'العلامة المائية ورمز التحقق في PDF وHTML فقط.' : ''}'
              : '${_format.hint}. هذه الصيغة للبيانات، فلا تحمل الشعار والتصميم.',
          style: TextStyle(color: sem.muted, fontSize: 12.5),
        ),
      ),
      if (table != null)
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: InfoBanner(
            text: '${table.rows.length} سجل · ${table.columns.length} عموداً${table.rows.length > 3000 ? ' · ملف كبير قد يستغرق وقتاً' : ''}',
            level: table.rows.isEmpty ? 'warning' : 'info',
            icon: Icons.table_rows_outlined,
          ),
        ),
    ]);

    final actions = Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
      child: Wrap(alignment: WrapAlignment.end, spacing: 10, runSpacing: 8, children: [
        TextButton.icon(
          onPressed: table == null ? null : () => _preview(table),
          icon: const Icon(Icons.visibility_outlined),
          label: const Text('معاينة'),
        ),
        OutlinedButton.icon(
          onPressed: table == null ? null : () => runExport(context, table, _config, ExportFormat.pdf, print: true),
          icon: const Icon(Icons.print_rounded),
          label: const Text('طباعة'),
        ),
        FilledButton.icon(
          onPressed: table == null ? null : () => runExport(context, table, _config, _format),
          icon: Icon(_format.icon),
          label: Text('تصدير ${_format.label}'),
        ),
      ]),
    );

    final header = Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 12, 4),
      child: Row(children: [
        Icon(Icons.print_rounded, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 10),
        Expanded(child: Text('تصدير وطباعة', style: t.titleLarge?.copyWith(fontWeight: FontWeight.w800))),
        IconButton(tooltip: 'إغلاق', onPressed: () => Navigator.of(context).pop(), icon: const Icon(Icons.close_rounded)),
      ]),
    );

    if (narrow) {
      return Scaffold(
        body: SafeArea(child: Column(children: [header, Expanded(child: body), const Divider(height: 1), actions])),
      );
    }
    return Column(mainAxisSize: MainAxisSize.min, children: [header, Flexible(child: body), const Divider(height: 1), actions]);
  }

  Widget _toggle(String text, bool value, void Function(bool v) set) => FilterChip(
        label: Text(text),
        selected: value,
        onSelected: (v) => setState(() => set(v)),
      );

  Future<void> _preview(ExportTable table) async {
    final app = AppScope.read(context);
    final ctx = printContextOf(app);
    var cover = false;
    await showDialog<void>(
      context: context,
      builder: (dctx) => StatefulBuilder(
        builder: (dctx, setLocal) => Dialog(
          insetPadding: const EdgeInsets.all(18),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 980, maxHeight: 900),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 8, 6),
                child: Row(children: [
                  const Expanded(child: Text('معاينة الصفحة الأولى', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16))),
                  if (_config.cover)
                    TextButton(onPressed: () => setLocal(() => cover = !cover), child: Text(cover ? 'الصفحة الأولى' : 'صفحة الغلاف')),
                  IconButton(onPressed: () => Navigator.of(dctx).pop(), icon: const Icon(Icons.close_rounded)),
                ]),
              ),
              Flexible(
                child: Container(
                  color: Sem.of(dctx).surface2,
                  padding: const EdgeInsets.all(16),
                  child: Center(child: PagePreview(config: _config, table: table, context0: ctx, cover: cover)),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Wrap(spacing: 10, children: [
                  OutlinedButton.icon(
                    onPressed: () => runExport(context, table, _config, ExportFormat.pdf, print: true),
                    icon: const Icon(Icons.picture_as_pdf_outlined),
                    label: const Text('فتح PDF الفعلي'),
                  ),
                ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
