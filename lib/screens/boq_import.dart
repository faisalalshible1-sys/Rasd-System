import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../app_state.dart';
import '../boq_import.dart';
import '../models.dart';
import '../services/boq_files.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';
import 'pm_common.dart';
import 'prices.dart' show BoqEditorPage;
import 'schedule.dart' show itemsText;

// =====================================================================
// استيراد مقايسة من ملف Excel أو CSV أو PDF (الإصدار 1.5.0): يُستخرج رقم البند والوصف والوحدة والكمية
// وسعر الوحدة والإجمالي، ثم يراجعها المستخدم ويصححها (الأعمدة والبنود) قبل حفظها مسودة مقايسة.
// =====================================================================

/// يختار الملف ويقرؤه ثم يفتح صفحة المراجعة.
Future<void> startBoqImport(BuildContext context) async {
  final app = AppScope.read(context);
  BoqSource? src;
  try {
    src = await pickBoqSource();
  } catch (e) {
    if (context.mounted) showToast(context, friendlyError(e), error: true);
    return;
  }
  if (src == null || !context.mounted) return;
  final source = src;
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => PopScope(
      canPop: false,
      child: AlertDialog(
        title: const Text('قراءة الملف'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(source.isPdf ? 'يُستخرج النص من صفحات PDF…' : 'تُقرأ صفوف الملف…'),
          const SizedBox(height: 12),
          const LinearProgressIndicator(),
        ]),
      ),
    ),
  );
  List<BoqSheetRows> sheets = const [];
  String? note;
  String? error;
  try {
    if (source.isPdf) {
      final r = await app.extractBoqPdf(source.bytes);
      final rows = pdfRows(r.pages);
      if (rows.isEmpty) {
        error = 'لا نص في هذا الملف: صفحاته صور ممسوحة. صدّر المقايسة إلى Excel، أو أدخل بنودها من المحرر.';
      } else {
        sheets = [BoqSheetRows('PDF', rows)];
        if (r.truncated) note = 'قُرئت أول ${r.pages.length} صفحة من ${r.total}. قسّم الملف لاستيراد الباقي.';
      }
    } else if (source.ext == 'csv') {
      sheets = [BoqSheetRows('CSV', readCsv(source.bytes))];
    } else {
      sheets = await compute(readXlsx, source.bytes);
    }
    if (error == null && sheets.every((s) => s.rows.isEmpty)) error = 'لا بيانات في الملف.';
  } catch (e) {
    error = friendlyError(e);
  }
  if (!context.mounted) return;
  Navigator.of(context, rootNavigator: true).pop();
  if (error != null) {
    showToast(context, error, error: true);
    return;
  }
  await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => BoqImportPage(source: source, sheets: sheets, note: note)));
}

String _num(double? v) {
  if (v == null) return '—';
  return v == v.roundToDouble() ? fmtMoney(v) : v.toStringAsFixed(3).replaceFirst(RegExp(r'0+$'), '');
}

class BoqImportPage extends StatefulWidget {
  const BoqImportPage({super.key, required this.source, required this.sheets, this.note});

  final BoqSource source;
  final List<BoqSheetRows> sheets;
  final String? note;

  @override
  State<BoqImportPage> createState() => _BoqImportPageState();
}

class _BoqImportPageState extends State<BoqImportPage> {
  int _sheet = 0;
  late BoqColumns _cols;
  late BoqImportResult _res;
  bool _onlyIssues = false;
  int _shown = 150;
  bool _saving = false;
  String _project = '';
  late final TextEditingController _title;
  final _ref = TextEditingController();

  List<List<String>> get _rows => widget.sheets[_sheet].rows;

  @override
  void initState() {
    super.initState();
    final n = widget.source.name;
    _title = TextEditingController(text: n.contains('.') ? n.substring(0, n.lastIndexOf('.')) : n);
    _detect();
  }

  @override
  void dispose() {
    _title.dispose();
    _ref.dispose();
    super.dispose();
  }

  void _detect() {
    _cols = detectBoqColumns(_rows);
    _res = extractBoq(_rows, columns: _cols);
    _shown = 150;
  }

  void _remap(BoqCol role, int? col) {
    final m = {..._cols.map};
    m.remove(role);
    if (col != null) {
      m.removeWhere((_, c) => c == col);
      m[role] = col;
    }
    setState(() {
      _cols = BoqColumns(_cols.headerRow, m);
      _res = extractBoq(_rows, columns: _cols);
    });
  }

  int get _width => _rows.fold<int>(0, (w, r) => r.length > w ? r.length : w);

  /// تسمية العمود: نص رأسه، وإلا أول قيمة فيه.
  String _colLabel(int c) {
    String? sample;
    if (_cols.headerRow >= 0 && c < _rows[_cols.headerRow].length && _rows[_cols.headerRow][c].trim().isNotEmpty) {
      sample = _rows[_cols.headerRow][c].trim();
    } else {
      for (final r in _rows.skip(_cols.headerRow + 1)) {
        if (c < r.length && r[c].trim().isNotEmpty) {
          sample = r[c].trim();
          break;
        }
      }
    }
    final s = sample ?? 'فارغ';
    return 'العمود ${c + 1}: ${s.length > 28 ? '${s.substring(0, 28)}…' : s}';
  }

  Future<void> _editLine(BoqImportLine l) async {
    await showPmForm(
      context,
      title: l.heading ? 'عنوان: ${l.desc}' : 'البند ${l.code.isEmpty ? '' : l.code}',
      note: 'الصف ${l.source} في الملف.',
      sections: const [
        PmSection('', [
          PmField('code', 'رقم البند', PmKind.text, max: 30),
          PmField('unit', 'الوحدة', PmKind.text, max: 20),
          PmField('desc', 'الوصف', PmKind.multiline, required: true, max: 4000),
          PmField('qty', 'الكمية', PmKind.decimal),
          PmField('price', 'سعر الوحدة', PmKind.money),
        ]),
      ],
      values: {'code': l.code, 'unit': l.unit, 'desc': l.desc, 'qty': l.qty, 'price': l.price},
      onSave: (d) async {
        double? n(Object? v) => v is num ? v.toDouble() : parseBoqNumber('${v ?? ''}');
        setState(() {
          l.code = '${d['code'] ?? ''}'.trim();
          l.unit = '${d['unit'] ?? ''}'.trim();
          l.desc = '${d['desc'] ?? ''}'.trim();
          l.qty = n(d['qty']);
          l.price = n(d['price']);
          // بعد التصحيح اليدوي يُعتمد الحاصل، ولا يبقى إجمالي الملف للمقارنة
          l.total = null;
          if (l.qty != null || l.price != null) l.heading = false;
        });
      },
    );
  }

  Future<void> _save() async {
    final app = AppScope.read(context);
    final items = _res.items;
    final noDesc = [for (final l in items) if (l.desc.trim().length < 2) l.source];
    if (items.isEmpty) {
      showToast(context, 'لا بنود للحفظ.', error: true);
      return;
    }
    if (noDesc.isNotEmpty) {
      showToast(context, 'بنود بلا وصف في الصفوف ${noDesc.take(8).join('، ')}: صححها أو احذفها.', error: true);
      return;
    }
    if (_title.text.trim().length < 2) {
      showToast(context, 'اكتب عنوان المقايسة.', error: true);
      return;
    }
    if (items.length > 2000) {
      showToast(context, 'أكثر من 2000 بند: قسّم المقايسة على أكثر من ملف.', error: true);
      return;
    }
    final issues = _res.withIssues;
    if (issues > 0) {
      final ok = await confirmDialog(context,
          title: 'بنود تحتاج مراجعة',
          message: '$issues من ${items.length} بنداً فيها ملاحظات (كمية أو وحدة أو سعر ناقص، أو إجمالي لا يطابق). '
              'تُحفظ المقايسة مسودة كما هي، وتكمل تصحيحها في المحرر قبل اعتمادها.',
          confirmLabel: 'حفظ المسودة');
      if (!ok || !mounted) return;
    }
    setState(() => _saving = true);
    try {
      final kind = widget.source.isPdf ? 'PDF' : (widget.source.ext == 'csv' ? 'CSV' : 'Excel');
      final id = await app.saveBoq(null, {
        'project_id': _project,
        'title': _title.text.trim(),
        'ref_no': _ref.text.trim(),
        'notes': 'استُوردت من الملف «${widget.source.name}» ($kind) وروجعت قبل الحفظ: ${items.length} بنداً'
            '${_res.fileTotal != null ? '، وإجمالي الملف ${fmtMoney(_res.fileTotal)}' : ''}.',
        'lines': [for (final l in items) l.toJson()],
        if (app.v20Ready) 'source': 'import',
        if (app.v20Ready) 'source_file': widget.source.name,
      });
      if (!mounted) return;
      showToast(context, 'حُفظت المقايسة مسودة');
      // تحل صفحة المحرر محل صفحة المراجعة
      await Navigator.of(context).pushReplacement(MaterialPageRoute<void>(builder: (_) => BoqEditorPage(sheetId: id)));
    } catch (e) {
      if (mounted) showToast(context, friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final sem = Sem.of(context);
    final cs = Theme.of(context).colorScheme;
    final res = _res;
    final items = res.items;
    final visible = _onlyIssues ? [for (final l in res.lines) if (!l.heading && !l.ok) l] : res.lines;
    final diff = res.fileTotal == null ? null : res.total - res.fileTotal!;
    final cols = [for (var c = 0; c < _width; c++) (c.toString(), _colLabel(c))];
    final projects = [
      ('', 'دون عقد (مقايسة عامة)'),
      for (final o in pmProjectOptions(app))
        if (app.canEditBoq(o.$1)) o,
    ];

    return Scaffold(
      appBar: brandAppBar(context, title: const Text('استيراد مقايسة')),
      body: PageBody(maxWidth: 1100, children: [
        PageHeader(
          title: widget.source.name,
          subtitle: '${itemsText(items.length)} · ${fmtMoney(res.total)} $currencyLabel'
              '${res.lines.any((l) => l.heading) ? ' · ${res.lines.where((l) => l.heading).length} عناوين' : ''}'
              '${res.skipped > 0 ? ' · ${res.skipped} صفوف مجاميع تُركت' : ''}',
          icon: Icons.upload_file_rounded,
        ),
        if (widget.source.isPdf)
          const Padding(
            padding: EdgeInsets.only(bottom: 12),
            child: InfoBanner(
              text: 'الاستخراج من PDF آلي وقد يخطئ في ترتيب النص العربي أو في توزيع الأعمدة. راجع الوصف والأرقام بنداً بنداً، '
                  'وإن تعذّر الاستخراج فصدّر المقايسة إلى Excel وأعد استيرادها.',
              level: 'warning',
            ),
          ),
        if (widget.note != null) Padding(padding: const EdgeInsets.only(bottom: 12), child: InfoBanner(text: widget.note!, level: 'warning')),
        SectionCard(
          title: 'الأعمدة',
          icon: Icons.view_column_outlined,
          subtitle: _cols.headerRow >= 0
              ? 'حُددت من رأس الجدول في الصف ${_cols.headerRow + 1}. غيّر أي عمود إن أخطأ التحديد؛ يُعاد الاستخراج فوراً وتضيع التصحيحات اليدوية.'
              : 'لا رأس للجدول: حُددت الأعمدة من محتواها. تحقق منها وغيّر ما أخطأ.',
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (widget.sheets.length > 1)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: SelectField(
                  label: 'الورقة',
                  value: '$_sheet',
                  items: [for (final (i, s) in widget.sheets.indexed) ('$i', '${s.name} (${s.rows.length} صفاً)')],
                  onChanged: (v) => setState(() {
                    _sheet = int.parse(v);
                    _detect();
                  }),
                ),
              ),
            Wrap(spacing: 10, runSpacing: 10, children: [
              for (final role in BoqCol.values)
                SizedBox(
                  width: 250,
                  child: SelectField(
                    label: boqColLabels[role]!,
                    value: _cols.map[role]?.toString() ?? '',
                    items: [('', '—'), ...cols],
                    onChanged: (v) => _remap(role, v.isEmpty ? null : int.parse(v)),
                  ),
                ),
            ]),
            if (!_cols.usable)
              const Padding(
                padding: EdgeInsets.only(top: 10),
                child: InfoBanner(text: 'حدّد عمود الوصف، وعمود الكمية أو الإجمالي على الأقل.', level: 'warning'),
              ),
          ]),
        ),
        const SizedBox(height: 14),
        SectionCard(
          title: 'البنود',
          icon: Icons.fact_check_outlined,
          subtitle: [
            res.withIssues == 0 ? 'كل البنود مكتملة' : '${res.withIssues} بنداً تحتاج مراجعة',
            if (res.fileTotal != null)
              diff!.abs() < 1 ? 'المجموع يطابق إجمالي الملف ${fmtMoney(res.fileTotal)}' : 'إجمالي الملف ${fmtMoney(res.fileTotal)} والفرق ${fmtMoney(diff)}',
          ].join(' · '),
          trailing: FilterChip(
            label: const Text('ما يحتاج مراجعة'),
            selected: _onlyIssues,
            onSelected: (v) => setState(() => _onlyIssues = v),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            for (final l in visible.take(_shown)) _lineTile(context, l, sem, cs),
            if (visible.length > _shown)
              TextButton(onPressed: () => setState(() => _shown += 300), child: Text('عرض المزيد (${visible.length - _shown})')),
            if (visible.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(_onlyIssues ? 'لا بنود تحتاج مراجعة.' : 'لم يُستخرج أي بند. تحقق من الأعمدة.', style: TextStyle(color: sem.muted)),
              ),
          ]),
        ),
        const SizedBox(height: 14),
        SectionCard(
          title: 'الحفظ',
          icon: Icons.save_outlined,
          subtitle: 'تُحفظ مسودة في «مُعِدّ المقايسات» ببنود حرة، ثم تُفتح في المحرر لإكمالها. الاعتماد بعد المراجعة كما في بقية المقايسات.',
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            TextField(controller: _title, decoration: const InputDecoration(labelText: 'عنوان المقايسة', border: OutlineInputBorder())),
            const SizedBox(height: 10),
            LayoutBuilder(builder: (context, c) {
              final project = SelectField(label: 'العقد', value: _project, items: projects, onChanged: (v) => setState(() => _project = v));
              final ref = TextField(controller: _ref, decoration: const InputDecoration(labelText: 'الرقم الإشاري', border: OutlineInputBorder()));
              if (c.maxWidth < 520) {
                return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [project, const SizedBox(height: 10), ref]);
              }
              return Row(children: [
                Expanded(child: project),
                const SizedBox(width: 10),
                SizedBox(width: 200, child: ref),
              ]);
            }),
            const SizedBox(height: 12),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: FilledButton.icon(
                onPressed: _saving || items.isEmpty ? null : _save,
                icon: _saving
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.save_rounded),
                label: Text('حفظ ${itemsText(items.length)} مسودة'),
              ),
            ),
          ]),
        ),
      ]),
    );
  }

  Widget _lineTile(BuildContext context, BoqImportLine l, Sem sem, ColorScheme cs) {
    if (l.heading) {
      return Padding(
        padding: const EdgeInsets.only(top: 6, bottom: 4),
        child: Row(children: [
          Icon(Icons.segment_rounded, size: 18, color: sem.muted),
          const SizedBox(width: 6),
          Expanded(child: Text(l.desc, style: TextStyle(color: sem.muted, fontWeight: FontWeight.w700))),
          TextButton(onPressed: () => _editLine(l), child: const Text('اجعله بنداً')),
          IconButton(
              tooltip: 'حذف السطر',
              icon: Icon(Icons.close_rounded, size: 18, color: sem.muted),
              onPressed: () => setState(() => _res.lines.remove(l))),
        ]),
      );
    }
    final issues = l.issues;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: issues.isEmpty ? sem.surface2 : sem.danger.withAlpha(18),
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => _editLine(l),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 4, 8),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SizedBox(
                width: 54,
                child: Text(l.code.isEmpty ? '—' : l.code,
                    style: TextStyle(color: sem.muted, fontSize: 12.5, fontFeatures: const [FontFeature.tabularFigures()])),
              ),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(l.desc.isEmpty ? '(بلا وصف)' : l.desc, maxLines: 3, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 3),
                  Text(
                    '${l.unit.isEmpty ? '—' : l.unit} · الكمية ${_num(l.qty)} · السعر ${_num(l.price)} · الإجمالي ${_num(l.computed)}',
                    style: TextStyle(color: sem.muted, fontSize: 12),
                  ),
                  for (final i in issues)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 1),
                          child: Icon(Icons.error_outline_rounded, size: 14, color: sem.danger),
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(i, style: TextStyle(color: sem.danger, fontWeight: FontWeight.w700, fontSize: 11.5)),
                        ),
                      ]),
                    ),
                ]),
              ),
              IconButton(
                tooltip: 'حذف البند',
                icon: Icon(Icons.delete_outline_rounded, size: 19, color: sem.muted),
                onPressed: () => setState(() => _res.lines.remove(l)),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
