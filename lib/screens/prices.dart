import 'dart:async';

import 'package:flutter/material.dart';

import '../app_state.dart';
import '../models.dart';
import '../prices.dart';
import '../print/export_dialog.dart';
import '../print/model.dart' show ExportFormat;
import '../ui/theme.dart';
import '../ui/widgets.dart';
import 'boq_import.dart' show startBoqImport;
import 'plan_widgets.dart' show StatusChip;
import 'pm_common.dart';
import 'schedule.dart' show ScheduleNotReady, itemsText;

// =====================================================================
// لائحة الأسعار الاسترشادية (بحث برقم البند أو بكلمات من الوصف، وتصفّح الفصول والعناوين)،
// ومُعِدّ المقايسات منها (البند والوحدة والكمية والملاحظات، ثم التصدير إلى Excel وغيره).
// =====================================================================

String _price(double? v) => v == null ? '—' : fmtMoney(v);

/// الوصف الكامل مقسوماً: سياق البنود الأم، ثم وصف البند نفسه (آخر جزء بعد « — »).
(String, String) splitDesc(String full) {
  final i = full.lastIndexOf(' — ');
  return i < 0 ? ('', full) : (full.substring(0, i), full.substring(i + 3));
}

/// وصف البند بارزاً وسياقه تحته بخط أصغر.
class DescText extends StatelessWidget {
  const DescText(this.full, {super.key, this.bold = true, this.contextLines = 2});

  final String full;
  final bool bold;
  final int contextLines;

  @override
  Widget build(BuildContext context) {
    final sem = Sem.of(context);
    final (ctx, own) = splitDesc(full);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(own, maxLines: 3, overflow: TextOverflow.ellipsis, style: TextStyle(height: 1.4, fontWeight: bold ? FontWeight.w700 : FontWeight.w400)),
      if (ctx.isNotEmpty)
        Text(ctx, maxLines: contextLines, overflow: TextOverflow.ellipsis, style: TextStyle(height: 1.4, color: sem.muted, fontSize: 12.5)),
    ]);
  }
}
String _qty(double? v) => v == null ? '' : (v == v.roundToDouble() ? v.toStringAsFixed(0) : fmtMoney(v));

/// صف من اللائحة: الرقم والوصف والوحدة والسعر، والعنوان بسهم للتصفح.
class PriceRow extends StatelessWidget {
  const PriceRow({super.key, required this.item, this.full = false, this.chapter, this.onTap, this.trailing});

  final PriceItem item;

  /// الوصف الكامل بسياق البنود الأم (نتائج البحث) أو وصف الصف وحده (التصفح).
  final bool full;
  final String? chapter;
  final VoidCallback? onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final sem = Sem.of(context);
    final it = item;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
            width: 74,
            child: Text(it.code.isEmpty ? (it.kind == 'note' ? 'ملاحظة' : '') : it.code,
                textDirection: TextDirection.ltr,
                textAlign: TextAlign.right,
                style: TextStyle(fontWeight: FontWeight.w800, color: it.isItem ? null : sem.muted, fontSize: 13)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (chapter != null) Text(chapter!, style: TextStyle(color: sem.muted, fontSize: 11.5)),
              if (full && it.isItem)
                DescText(it.fullDesc)
              else
                Text(it.description,
                    maxLines: it.isItem ? 4 : 3,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(height: 1.45, fontWeight: it.isHeading ? FontWeight.w700 : FontWeight.w400, color: it.kind == 'note' ? sem.muted : null)),
            ]),
          ),
          const SizedBox(width: 10),
          if (it.isItem)
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(_price(it.price), style: const TextStyle(fontWeight: FontWeight.w800, fontFeatures: [FontFeature.tabularFigures()])),
              Text(it.unitInferred ? '${it.unit} *' : it.unit, style: TextStyle(color: sem.muted, fontSize: 12)),
            ])
          else if (it.isHeading)
            Icon(Icons.chevron_left_rounded, color: sem.muted),
          if (trailing != null) ...[const SizedBox(width: 6), trailing!],
        ]),
      ),
    );
  }
}

/// تفاصيل بند اللائحة.
Future<void> showPriceItemSheet(BuildContext context, PriceItem it, {VoidCallback? onAdd}) {
  final app = AppScope.read(context);
  final list = app.priceList(it.listId);
  return showPmSheet(
    context,
    code: it.code,
    title: it.description,
    badges: [
      if (list != null) ToneBadge(list.chapterName(it.chapter), color: Sem.of(context).muted),
      if (it.unitInferred) ToneBadge('الوحدة مستنتجة', color: Sem.of(context).wip),
    ],
    rows: [
      ('القسم', it.section),
      ('مجموعة الأعمال', it.group),
      ('الوصف الكامل', it.fullDesc == it.description ? '' : it.fullDesc),
      ('الوحدة', it.unitInferred ? '${it.unit} — الوحدة فارغة في اللائحة واستُنتجت من البنود المجاورة' : it.unit),
      ('سعر الوحدة', it.price == null ? '' : '${_price(it.price)} ${list?.currency ?? ''}'),
      ('اللائحة', list?.title ?? ''),
    ],
    actions: onAdd == null
        ? null
        : (sheet) => [
              FilledButton.icon(
                onPressed: () {
                  Navigator.of(sheet).pop();
                  onAdd();
                },
                icon: const Icon(Icons.playlist_add_rounded),
                label: const Text('إضافة إلى مقايسة'),
              ),
            ],
  );
}

// =====================================================================
// صفحة لائحة الأسعار
// =====================================================================
class PriceListPage extends StatefulWidget {
  const PriceListPage({super.key, this.initialQuery = '', this.initialChapter = ''});

  /// بحث أو فصل يُفتح به (روابط من صفحات أخرى).
  final String initialQuery;
  final String initialChapter;

  @override
  State<PriceListPage> createState() => _PriceListPageState();
}

class _PriceListPageState extends State<PriceListPage> {
  final _q = TextEditingController();
  Timer? _debounce;
  String _chapter = '';
  final List<PriceItem> _path = [];
  List<PriceItem> _rows = [];
  bool _loading = false;
  String? _error;
  int _token = 0;

  @override
  void initState() {
    super.initState();
    _q.text = widget.initialQuery;
    _chapter = widget.initialChapter;
    if (_q.text.isNotEmpty || _chapter.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _load();
      });
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _q.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final app = AppScope.read(context);
    final list = app.activePriceList;
    if (list == null) return;
    final q = _q.text.trim();
    final token = ++_token;
    if (q.isEmpty && _chapter.isEmpty) {
      setState(() {
        _rows = [];
        _error = null;
        _loading = false;
      });
      app.priceResults = [];
      return;
    }
    setState(() => _loading = true);
    try {
      final rows = q.isNotEmpty
          ? await app.searchPrices(list.id, q, chapter: _chapter.isEmpty ? null : _chapter, limit: 150)
          : await app.browsePrices(list.id, _chapter, _path.isEmpty ? null : _path.last.seq);
      if (!mounted || token != _token) return;
      setState(() {
        _rows = rows;
        _error = null;
      });
      app.priceResults = rows;
    } catch (e) {
      if (mounted && token == _token) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted && token == _token) setState(() => _loading = false);
    }
  }

  void _onQuery(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), _load);
  }

  void _setChapter(String key) {
    _chapter = key;
    _path.clear();
    _load();
  }

  void _open(PriceItem it) {
    if (it.isHeading && _q.text.trim().isEmpty) {
      _path.add(it);
      _load();
      return;
    }
    if (it.isHeading) {
      // عنوان في نتائج البحث برقم البند: تصفّح ما تحته
      _q.clear();
      _chapter = it.chapter;
      _path
        ..clear()
        ..add(it);
      _load();
      return;
    }
    final app = AppScope.read(context);
    showPriceItemSheet(context, it, onAdd: app.canEditBoq(null) ? () => addToBoq(context, it) : null);
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    if (!app.v14Ready) return const ScheduleNotReady(title: 'لائحة الأسعار الاسترشادية');
    final list = app.activePriceList;
    final sem = Sem.of(context);
    if (list == null) {
      return const PageBody(children: [
        PageHeader(title: 'لائحة الأسعار الاسترشادية', icon: Icons.price_change_outlined),
        EmptyState(title: 'لا لائحة أسعار بعد', message: 'تُضاف اللائحة بترحيل بياناتها في قاعدة البيانات.'),
      ]);
    }
    final q = _q.text.trim();
    final searching = q.isNotEmpty;
    return PageBody(
      maxWidth: 1200,
      onRefresh: _load,
      children: [
        PageHeader(
          title: list.title,
          subtitle: '${list.source.isEmpty ? '' : '${list.source} · '}ابحث برقم البند (مثل 7.2.2) أو بكلمات من الوصف، أو تصفّح الفصول',
          icon: Icons.price_change_outlined,
          actions: [
            if (app.canEditBoq(null))
              FilledButton.icon(
                onPressed: () => openBoqEditor(context),
                icon: const Icon(Icons.calculate_outlined),
                label: const Text('مقايسة جديدة'),
              ),
            if (_rows.isNotEmpty)
              OutlinedButton.icon(
                onPressed: () => showExportDialog(context, sourceId: 'docs:prices', items: _rows, title: list.title),
                icon: const Icon(Icons.ios_share_rounded),
                label: const Text('تصدير المعروض'),
              ),
          ],
        ),
        TextField(
          controller: _q,
          onChanged: _onQuery,
          onSubmitted: (_) => _load(),
          textInputAction: TextInputAction.search,
          decoration: fieldDeco('رقم البند أو كلمات من الوصف',
              prefixIcon: const Icon(Icons.search_rounded),
              suffix: q.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () {
                        _q.clear();
                        _load();
                      },
                    )),
        ),
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 8, children: [
          ChoiceChip(label: const Text('كل الفصول'), selected: _chapter.isEmpty, onSelected: (_) => _setChapter('')),
          for (final c in list.chapters)
            ChoiceChip(label: Text(c.name), selected: _chapter == c.key, onSelected: (_) => _setChapter(c.key)),
        ]),
        const SizedBox(height: 12),
        if (!searching && _chapter.isNotEmpty) ...[
          Wrap(spacing: 4, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
            ActionChip(
              label: Text(list.chapterName(_chapter)),
              onPressed: () {
                _path.clear();
                _load();
              },
            ),
            for (var k = 0; k < _path.length; k++) ...[
              Icon(Icons.chevron_left_rounded, size: 18, color: sem.muted),
              ActionChip(
                label: Text('${_path[k].code} ${_short(_path[k].description)}'),
                onPressed: k == _path.length - 1
                    ? null
                    : () {
                        _path.removeRange(k + 1, _path.length);
                        _load();
                      },
              ),
            ],
          ]),
          const SizedBox(height: 10),
        ],
        if (_error != null) InfoBanner(text: _error!, level: 'critical'),
        if (_loading) const LinearProgressIndicator(minHeight: 2),
        if (!searching && _chapter.isEmpty)
          ResponsiveGrid(minItemWidth: 260, spacing: 10, children: [
            for (final (k, c) in list.chapters.indexed)
              Material(
                color: cardColor(context),
                elevation: cardElevation(context),
                shadowColor: Colors.black26,
                shape: cardShape(context),
                child: InkWell(
                  customBorder: cardShape(context),
                  onTap: () => _setChapter(c.key),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Row(children: [
                      CircleAvatar(
                        radius: 16,
                        backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                        child: Text('${k + 1}', style: const TextStyle(fontWeight: FontWeight.w800)),
                      ),
                      const SizedBox(width: 12),
                      Expanded(child: Text(c.name, style: const TextStyle(fontWeight: FontWeight.w700, height: 1.4))),
                      Icon(Icons.chevron_left_rounded, color: sem.muted),
                    ]),
                  ),
                ),
              ),
          ])
        else if (_rows.isEmpty && !_loading)
          EmptyState(
            title: searching ? 'لا نتائج' : 'لا بنود هنا',
            message: searching ? 'جرّب كلمة أقصر أو رقم بند أعلى (مثل 7.2 بدل 7.2.9)، أو اختر «كل الفصول».' : null,
            icon: Icons.search_off_rounded,
          )
        else
          Container(
            decoration: cardDecoration(context),
            clipBehavior: Clip.antiAlias,
            child: Material(
              type: MaterialType.transparency,
              child: Column(children: [
                if (searching)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
                    child: Text('النتائج: ${_rows.length}${_rows.length >= 150 ? ' (أول 150؛ زد كلمات البحث للتضييق)' : ''}',
                        style: TextStyle(color: sem.muted, fontSize: 12.5)),
                  ),
                for (var k = 0; k < _rows.length; k++) ...[
                  if (k > 0 || searching) Divider(height: 1, color: sem.rule),
                  PriceRow(
                    item: _rows[k],
                    full: searching,
                    chapter: searching && _chapter.isEmpty ? list.chapterName(_rows[k].chapter) : null,
                    onTap: () => _open(_rows[k]),
                  ),
                ],
              ]),
            ),
          ),
        const SizedBox(height: 10),
        Text('* الوحدة فارغة في اللائحة واستُنتجت من البنود المجاورة. الأسعار بالـ${list.currency} كما وردت في اللائحة.',
            style: TextStyle(color: sem.muted, fontSize: 12)),
      ],
    );
  }

  static String _short(String s) => s.length <= 40 ? s : '${s.substring(0, 40)}…';
}

/// إضافة بند من اللائحة إلى مقايسة: مقايسة قائمة أو جديدة.
Future<void> addToBoq(BuildContext context, PriceItem it) async {
  final app = AppScope.read(context);
  final sheets = app.boqSheets.where((s) => !s.approved && app.canEditBoq(s.projectId)).toList();
  final choice = sheets.isEmpty
      ? ''
      : await showDialog<String>(
          context: context,
          builder: (ctx) => SimpleDialog(
            title: const Text('إضافة البند إلى'),
            children: [
              SimpleDialogOption(
                onPressed: () => Navigator.of(ctx).pop(''),
                child: const Row(children: [Icon(Icons.add_rounded), SizedBox(width: 10), Text('مقايسة جديدة')]),
              ),
              for (final s in sheets.take(12))
                SimpleDialogOption(
                  onPressed: () => Navigator.of(ctx).pop(s.id),
                  child: Text('${s.title} (${itemsText(s.lines.length)})', maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
            ],
          ),
        );
  if (choice == null || !context.mounted) return;
  await openBoqEditor(context, sheetId: choice.isEmpty ? null : choice, add: [BoqLine.fromItem(it)]);
}

// =====================================================================
// المقايسات المعدّة من اللائحة
// =====================================================================
class BoqSheetsPage extends StatelessWidget {
  const BoqSheetsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    if (!app.v14Ready) return const ScheduleNotReady(title: 'مُعِدّ المقايسات');
    final sem = Sem.of(context);
    final sheets = app.boqSheets;
    final list = app.activePriceList;
    return PmListScaffold(
      title: 'مُعِدّ المقايسات',
      subtitle: list == null ? null : 'من ${list.title}: اختر البنود برقمها أو بالبحث في وصفها، وأدخل الكميات والملاحظات، ثم صدّرها Excel',
      icon: Icons.calculate_outlined,
      actions: [
        if (app.canEditBoq(null))
          OutlinedButton.icon(
            onPressed: () => startBoqImport(context),
            icon: const Icon(Icons.upload_file_rounded),
            label: const Text('استيراد من ملف'),
          ),
        if (app.canEditBoq(null))
          FilledButton.icon(
            onPressed: () => openBoqEditor(context),
            icon: const Icon(Icons.add_rounded),
            label: const Text('مقايسة جديدة'),
          ),
      ],
      emptyTitle: 'لا مقايسات بعد',
      emptyMessage: app.canEditBoq(null)
          ? 'أنشئ مقايسة واختر بنودها من لائحة الأسعار الاسترشادية.'
          : 'يعدّ المقايسات مكتب المدير ومكتب العقود ورئيسا الشؤون الفنية والمطابقة والاستلام.',
      items: [
        for (final s in sheets)
          PmTile(
            code: s.refNo,
            title: s.title,
            meta: [
              if (s.projectId != null) pmProjectName(app, s.projectId),
              if (s.updatedAt != null) fmtDate(s.updatedAt),
              if (app.people[s.createdBy]?.displayName != null) app.people[s.createdBy]!.displayName,
            ].join(' · '),
            badges: [
              if (app.v15Ready) StatusChip(s.approved ? FormStatus.done : FormStatus.wip, label: s.approved ? 'معتمدة' : 'مسودة', small: true),
              ToneBadge(itemsText(s.lines.length), color: sem.muted),
              if (s.showPrices) ToneBadge('الإجمالي ${fmtMoney(s.total)}', color: Theme.of(context).colorScheme.primary),
              if (!s.showPrices) ToneBadge('كميات دون أسعار', color: sem.muted),
            ],
            trailing: Icon(Icons.chevron_left_rounded, color: sem.muted),
            onTap: () => openBoqEditor(context, sheetId: s.id),
          ),
      ],
    );
  }
}

Future<void> openBoqEditor(BuildContext context, {String? sheetId, List<BoqLine> add = const []}) =>
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => BoqEditorPage(sheetId: sheetId, add: add)));

class _Line {
  _Line(this.line)
      : qty = TextEditingController(text: _qty(line.qty)),
        notes = TextEditingController(text: line.notes);

  final BoqLine line;
  final TextEditingController qty;
  final TextEditingController notes;
  final key = UniqueKey();

  void dispose() {
    qty.dispose();
    notes.dispose();
  }
}

class BoqEditorPage extends StatefulWidget {
  const BoqEditorPage({super.key, this.sheetId, this.add = const []});

  final String? sheetId;

  /// بنود تُضاف عند الفتح (من صفحة اللائحة).
  final List<BoqLine> add;

  @override
  State<BoqEditorPage> createState() => _BoqEditorPageState();
}

class _BoqEditorPageState extends State<BoqEditorPage> {
  final _title = TextEditingController();
  final _ref = TextEditingController();
  final _notes = TextEditingController();
  final _search = TextEditingController();
  String _project = '';
  bool _showPrices = true;
  final List<_Line> _lines = [];
  String? _id;
  bool _dirty = false;
  bool _saving = false;
  bool _init = false;
  String _chapter = '';
  List<_Hit> _hits = [];
  bool _searching = false;
  Timer? _debounce;
  int _token = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_init) return;
    _init = true;
    final app = AppScope.read(context);
    final s = widget.sheetId == null ? null : app.boqSheet(widget.sheetId!);
    if (s != null) {
      _id = s.id;
      _title.text = s.title;
      _ref.text = s.refNo;
      _notes.text = s.notes;
      _project = s.projectId ?? '';
      _showPrices = s.showPrices;
      _lines.addAll([for (final l in s.lines) _Line(l.copy())]);
    }
    if (widget.add.isNotEmpty) {
      _lines.addAll([for (final l in widget.add) _Line(l.copy())]);
      _dirty = true;
    }
  }

  @override
  void dispose() {
    for (final c in [_title, _ref, _notes, _search]) {
      c.dispose();
    }
    for (final l in _lines) {
      l.dispose();
    }
    _debounce?.cancel();
    super.dispose();
  }

  void _touch() {
    if (!_dirty) setState(() => _dirty = true);
  }

  double get _total {
    var t = 0.0;
    for (final l in _lines) {
      final q = parseMoney(l.qty.text).value ?? 0;
      t += q * (l.line.price ?? 0);
    }
    return t;
  }

  List<BoqLine> _current() => [
        for (final l in _lines)
          BoqLine(
            seq: l.line.seq,
            chapter: l.line.chapter,
            code: l.line.code,
            desc: l.line.desc,
            unit: l.line.unit,
            price: l.line.price,
            qty: parseMoney(l.qty.text).value,
            notes: l.notes.text.trim(),
            sheetId: _id ?? '',
            projectId: _project.isEmpty ? null : _project,
            no: _lines.indexOf(l) + 1,
          ),
      ];

  Future<void> _find(String q) async {
    final app = AppScope.read(context);
    final list = app.activePriceList;
    final token = ++_token;
    if (list == null || q.trim().isEmpty) {
      setState(() {
        _hits = [];
        _searching = false;
      });
      return;
    }
    setState(() => _searching = true);
    try {
      final rows = await app.searchPrices(list.id, q, chapter: _chapter.isEmpty ? null : _chapter, limit: 40);
      if (!mounted || token != _token) return;
      setState(() => _hits = [for (final r in rows) _Hit(r)]);
    } catch (e) {
      if (mounted) showToast(context, friendlyError(e), error: true);
    } finally {
      if (mounted && token == _token) setState(() => _searching = false);
    }
  }

  void _add(PriceItem it) {
    setState(() {
      _lines.add(_Line(BoqLine.fromItem(it)));
      _dirty = true;
    });
    showToast(context, 'أُضيف البند ${it.code}');
  }

  /// Enter في خانة البحث: رقم بند مسعّر مطابق يُضاف مباشرة.
  void _submit(String q) {
    final exact = _hits.where((h) => h.item.isItem && h.item.code == q.trim()).toList();
    if (isPriceCode(q) && exact.length == 1) {
      _add(exact.first.item);
      _search.clear();
      setState(() => _hits = []);
      return;
    }
    _find(q);
  }

  Future<void> _freeLine() async {
    BoqLine? out;
    final ok = await showPmForm(
      context,
      title: 'بند حر (خارج اللائحة)',
      note: 'لبند لا يوجد في لائحة الأسعار. يُحفظ كما تكتبه، ويُميَّز في المقايسة.',
      sections: const [
        PmSection('البند', [
          PmField('code', 'رقم البند', PmKind.text, max: 30),
          PmField('unit', 'الوحدة', PmKind.text, max: 20),
          PmField('desc', 'وصف البند', PmKind.multiline, required: true, max: 4000),
          PmField('price', 'سعر الوحدة', PmKind.money),
        ]),
      ],
      values: const {},
      onSave: (d) async {
        out = BoqLine(code: '${d['code'] ?? ''}', desc: '${d['desc'] ?? ''}', unit: '${d['unit'] ?? ''}', price: d['price'] as double?);
      },
    );
    if (ok && out != null && mounted) {
      setState(() {
        _lines.add(_Line(out!));
        _dirty = true;
      });
    }
  }

  Future<void> _save() async {
    final app = AppScope.read(context);
    if (_title.text.trim().length < 2) {
      showToast(context, 'أدخل عنوان المقايسة', error: true);
      return;
    }
    for (final l in _lines) {
      if (!parseMoney(l.qty.text).ok) {
        showToast(context, 'كمية غير صالحة في البند ${l.line.code.isEmpty ? _lines.indexOf(l) + 1 : l.line.code}', error: true);
        return;
      }
    }
    setState(() => _saving = true);
    try {
      final id = await app.saveBoq(_id, {
        'title': _title.text.trim(),
        'ref_no': _ref.text.trim(),
        'notes': _notes.text.trim(),
        'project_id': _project,
        'show_prices': _showPrices,
        if (_id == null && app.activePriceList != null) 'list_id': app.activePriceList!.id,
        'lines': [for (final l in _current()) l.toJson()],
      });
      if (!mounted) return;
      setState(() {
        _id = id;
        _dirty = false;
      });
      showToast(context, 'حُفظت المقايسة');
    } catch (e) {
      if (mounted) showToast(context, friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _approve(bool approve) async {
    final app = AppScope.read(context);
    final ok = await confirmDialog(context,
        title: approve ? 'اعتماد المقايسة' : 'إعادة فتح المقايسة',
        message: approve
            ? 'تُعتمد المقايسة فتصير بنودها بنود العقد، ويُبنى منها البرنامج الزمني في «البرامج الزمنية». لا تُعدَّل بعدها إلا بإعادة فتحها.'
            : 'تعود المقايسة مسودة قابلة للتعديل. لا يُسمح بذلك إن كان البرنامج الزمني المعتمد للعقد مبنياً عليها.',
        confirmLabel: approve ? 'اعتماد' : 'إعادة فتح');
    if (!ok || !mounted) return;
    try {
      await app.approveBoq(_id!, approve);
      if (mounted) showToast(context, approve ? 'اعتُمدت المقايسة' : 'أُعيد فتح المقايسة للتعديل');
    } catch (e) {
      if (mounted) showToast(context, friendlyError(e), error: true);
    }
  }

  Future<void> _delete() async {
    final app = AppScope.read(context);
    final prompt = boqDeletePrompt(app, _id!);
    if (prompt.blocked != null) {
      showToast(context, prompt.blocked!, error: true);
      return;
    }
    final ok = await confirmDialog(context, title: prompt.title, message: prompt.message, confirmLabel: 'حذف', danger: true);
    if (!ok || !mounted) return;
    try {
      final r = await app.deleteBoq(_id!);
      if (!mounted) return;
      _dirty = false;
      Navigator.of(context).pop();
      showToast(
          context,
          r.items == 0
              ? 'حُذفت المقايسة'
              : 'حُذفت المقايسة و${itemsText(r.items)} من البرنامج الزمني والإشراف'
                  '${r.planRemoved ? '، وحُذف البرنامج المسودة' : ''}');
    } catch (e) {
      if (mounted) showToast(context, friendlyError(e), error: true);
    }
  }

  void _export() {
    final title = _title.text.trim().isEmpty ? 'مقايسة' : _title.text.trim();
    showExportDialog(context,
        sourceId: _showPrices ? 'docs:boq_sheet' : 'docs:boq_sheet_qty', items: _current(), title: title, format: ExportFormat.xlsx);
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final sem = Sem.of(context);
    final saved = _id == null ? null : app.boqSheet(_id!);
    final canEdit = app.canEditBoq(_project.isEmpty ? null : _project);
    final approved = saved?.approved ?? false;
    final ro = !canEdit || approved;
    final list = app.activePriceList;
    final narrow = MediaQuery.sizeOf(context).width < 640;
    return PopScope(
      canPop: !_dirty || ro,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final leave = await confirmDialog(context,
            title: 'تغييرات غير محفوظة', message: 'لم تُحفظ التعديلات على المقايسة. الخروج دون حفظ؟', confirmLabel: 'خروج دون حفظ', danger: true);
        if (leave && context.mounted) {
          setState(() => _dirty = false);
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        appBar: brandAppBar(context, title: Text(_id == null ? 'مقايسة جديدة' : 'المقايسة'), actions: [
          if (_lines.isNotEmpty) IconButton(tooltip: 'تصدير Excel وغيره', icon: const Icon(Icons.ios_share_rounded), onPressed: _export),
          if (saved != null && !approved && app.canDeleteBoq(saved))
            IconButton(tooltip: 'حذف المقايسة', icon: const Icon(Icons.delete_outline_rounded), onPressed: _delete),
          if (saved != null && app.canApproveBoq && !_dirty)
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 6),
              child: approved
                  ? OutlinedButton.icon(onPressed: () => _approve(false), icon: const Icon(Icons.lock_open_rounded), label: const Text('إعادة فتح'))
                  : FilledButton.tonalIcon(onPressed: () => _approve(true), icon: const Icon(Icons.verified_outlined), label: const Text('اعتماد')),
            ),
          if (!ro)
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 8),
              child: FilledButton.icon(
                onPressed: _saving || (!_dirty && _id != null) ? null : _save,
                icon: _saving
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.save_outlined),
                label: Text(_dirty || _id == null ? 'حفظ' : 'محفوظة'),
              ),
            ),
        ]),
        body: PageBody(maxWidth: 1100, children: [
          if (approved)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: InfoBanner(
                text: 'معتمدة من ${app.people[saved?.approvedBy]?.displayName ?? 'الشؤون الفنية'}'
                    '${saved?.approvedAt == null ? '' : ' بتاريخ ${fmtDate(saved!.approvedAt)}'}: بنودها بنود العقد ويُبنى منها برنامجه الزمني، '
                    'ولا تُعدَّل ولا تُحذف إلا بإعادة فتحها (لرئيس الشؤون الفنية والمدير).',
                level: 'ok',
                icon: Icons.verified_outlined,
              ),
            )
          else if (ro)
            const Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: InfoBanner(text: 'للقراءة والتصدير فقط: إعداد المقايسات لمكتب المدير ومكتب العقود ورئيسي الشؤون الفنية والمطابقة والاستلام.'),
            )
          else if (saved != null && app.v15Ready && !app.canApproveBoq)
            const Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: InfoBanner(text: 'مسودة: يعتمدها رئيس الشؤون الفنية أو المدير بعد ربطها بالعقد، فتصير بنودها بنود العقد.'),
            ),
          SectionCard(
            title: 'بيانات المقايسة',
            icon: Icons.description_outlined,
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              TextField(controller: _title, readOnly: ro, onChanged: (_) => _touch(), decoration: fieldDeco('عنوان المقايسة *')),
              const SizedBox(height: 10),
              Wrap(spacing: 10, runSpacing: 10, children: [
                SizedBox(
                  width: narrow ? double.infinity : 240,
                  child: TextField(controller: _ref, readOnly: ro, onChanged: (_) => _touch(), decoration: fieldDeco('الرقم الإشاري')),
                ),
                SizedBox(
                  width: narrow ? double.infinity : 480,
                  child: IgnorePointer(
                    ignoring: ro,
                    child: SelectField(
                      label: 'العقد (اختياري)',
                      value: _project,
                      items: pmProjectOptions(app, general: 'دون عقد'),
                      onChanged: (v) => setState(() {
                        _project = v;
                        _dirty = true;
                      }),
                    ),
                  ),
                ),
              ]),
              const SizedBox(height: 10),
              TextField(controller: _notes, readOnly: ro, minLines: 1, maxLines: 3, onChanged: (_) => _touch(), decoration: fieldDeco('ملاحظات عامة')),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('إظهار الأسعار والإجماليات'),
                subtitle: const Text('أطفئه لمقايسة كميات تُرسل للتسعير دون أسعار اللائحة'),
                value: _showPrices,
                onChanged: ro
                    ? null
                    : (v) => setState(() {
                          _showPrices = v;
                          _dirty = true;
                        }),
              ),
            ]),
          ),
          if (!ro && list != null) ...[
            const SizedBox(height: 14),
            SectionCard(
              title: 'إضافة بند من ${list.title}',
              icon: Icons.playlist_add_rounded,
              subtitle: 'اكتب رقم البند (ثم Enter لإضافته) أو كلمات من وصفه، واختر من النتائج. الوصف والوحدة والسعر من اللائحة.',
              trailing: TextButton.icon(onPressed: _freeLine, icon: const Icon(Icons.edit_note_rounded), label: const Text('بند حر')),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Wrap(spacing: 10, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.center, children: [
                  SizedBox(
                    width: narrow ? double.infinity : 260,
                    child: SelectField(
                      label: 'الفصل',
                      value: _chapter,
                      items: [('', 'كل الفصول'), for (final c in list.chapters) (c.key, c.name)],
                      onChanged: (v) {
                        setState(() => _chapter = v);
                        _find(_search.text);
                      },
                    ),
                  ),
                  SizedBox(
                    width: narrow ? double.infinity : 520,
                    child: TextField(
                      controller: _search,
                      textInputAction: TextInputAction.search,
                      onChanged: (v) {
                        _debounce?.cancel();
                        _debounce = Timer(const Duration(milliseconds: 350), () => _find(v));
                      },
                      onSubmitted: _submit,
                      decoration: fieldDeco('رقم البند أو كلمات من الوصف',
                          prefixIcon: const Icon(Icons.search_rounded),
                          suffix: _searching ? const Padding(padding: EdgeInsets.all(12), child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))) : null),
                    ),
                  ),
                ]),
                if (_hits.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 380),
                    child: Container(
                      decoration: BoxDecoration(border: Border.all(color: sem.rule), borderRadius: BorderRadius.circular(10)),
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: _hits.length,
                        separatorBuilder: (_, __) => Divider(height: 1, color: sem.rule),
                        itemBuilder: (_, k) {
                          final it = _hits[k].item;
                          return PriceRow(
                            item: it,
                            full: true,
                            chapter: _chapter.isEmpty ? list.chapterName(it.chapter) : null,
                            onTap: it.isItem ? () => _add(it) : () => _find(it.code),
                            trailing: it.isItem ? Icon(Icons.add_circle_outline_rounded, color: Theme.of(context).colorScheme.primary) : null,
                          );
                        },
                      ),
                    ),
                  ),
                ] else if (_search.text.trim().isNotEmpty && !_searching) ...[
                  const SizedBox(height: 8),
                  Text('لا نتائج. جرّب كلمة أقصر أو رقماً أعلى (مثل 7.2).', style: TextStyle(color: sem.muted, fontSize: 12.5)),
                ],
              ]),
            ),
          ],
          const SizedBox(height: 14),
          SectionCard(
            title: 'بنود المقايسة (${_lines.length})',
            icon: Icons.format_list_numbered_rounded,
            trailing: _showPrices && _lines.isNotEmpty
                ? Text('الإجمالي ${fmtMoney(_total)} ${list?.currency ?? ''}',
                    style: const TextStyle(fontWeight: FontWeight.w900, fontFeatures: [FontFeature.tabularFigures()]))
                : null,
            child: _lines.isEmpty
                ? const EmptyState(
                    title: 'لا بنود بعد', message: 'ابحث عن البند برقمه أو بوصفه وأضفه، ثم أدخل الكمية والملاحظات.', icon: Icons.playlist_add_rounded)
                : Column(children: [
                    for (var k = 0; k < _lines.length; k++) ...[
                      if (k > 0) Divider(height: 1, color: sem.rule),
                      _lineTile(context, k, ro, narrow),
                    ],
                  ]),
          ),
        ]),
      ),
    );
  }

  Widget _lineTile(BuildContext context, int k, bool ro, bool narrow) {
    final sem = Sem.of(context);
    final l = _lines[k];
    final b = l.line;
    final q = parseMoney(l.qty.text).value;
    final total = b.price == null ? null : (q ?? 0) * b.price!;
    final qtyField = TextField(
      controller: l.qty,
      readOnly: ro,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      onChanged: (_) => setState(() => _dirty = true),
      decoration: fieldDeco('الكمية (${b.unit.isEmpty ? 'الوحدة' : b.unit})', error: parseMoney(l.qty.text).ok ? null : 'رقم غير صالح'),
    );
    final notesField = TextField(
      controller: l.notes,
      readOnly: ro,
      onChanged: (_) => _touch(),
      decoration: fieldDeco('ملاحظات'),
    );
    return Padding(
      key: l.key,
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: sem.todoSoft, borderRadius: BorderRadius.circular(8)),
            child: Text('${k + 1}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                if (b.code.isNotEmpty) Text(b.code, textDirection: TextDirection.ltr, style: const TextStyle(fontWeight: FontWeight.w800)),
                if (!b.fromList) ToneBadge('بند حر', color: sem.wip),
                if (_showPrices && b.price != null)
                  Text('سعر الوحدة ${fmtMoney(b.price)}', style: TextStyle(color: sem.muted, fontSize: 12.5)),
                if (_showPrices && total != null && q != null)
                  Text('الإجمالي ${fmtMoney(total)}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5)),
              ]),
              const SizedBox(height: 4),
              DescText(b.desc, contextLines: 3),
            ]),
          ),
          if (!ro)
            PopupMenuButton<String>(
              tooltip: 'خيارات البند',
              onSelected: (v) => setState(() {
                _dirty = true;
                switch (v) {
                  case 'up':
                    if (k > 0) _lines.insert(k - 1, _lines.removeAt(k));
                  case 'down':
                    if (k < _lines.length - 1) _lines.insert(k + 1, _lines.removeAt(k));
                  case 'remove':
                    _lines.removeAt(k).dispose();
                }
              }),
              itemBuilder: (_) => [
                if (k > 0) const PopupMenuItem(value: 'up', child: Text('تحريك لأعلى')),
                if (k < _lines.length - 1) const PopupMenuItem(value: 'down', child: Text('تحريك لأسفل')),
                const PopupMenuItem(value: 'remove', child: Text('حذف من المقايسة')),
              ],
            ),
        ]),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsetsDirectional.only(start: 38),
          child: narrow
              ? Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [qtyField, const SizedBox(height: 8), notesField])
              : Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  SizedBox(width: 200, child: qtyField),
                  const SizedBox(width: 10),
                  Expanded(child: notesField),
                ]),
        ),
      ]),
    );
  }
}

class _Hit {
  const _Hit(this.item);

  final PriceItem item;
}

/// نص تأكيد حذف المقايسة: بنود البرنامج الزمني المأخوذة منها تُحذف معها من الشؤون الفنية ومن متابعة الإشراف
/// (الترحيل 33)، أو سبب المنع إن كان البرنامج المعتمد مبنياً عليها.
({String title, String message, String? blocked}) boqDeletePrompt(AppState app, String id) {
  final items = app.pmItems.where((i) => i.boqSheetId == id).toList();
  final tracked = items.where((i) => i.progress > 0 || i.actualStart != null || i.actualEnd != null).length;
  final projectIds = items.map((i) => i.projectId).toSet();
  if (projectIds.any((p) => app.planOf(p)?.approved ?? false)) {
    return (
      title: 'حذف المقايسة',
      message: '',
      blocked: 'البرنامج الزمني المعتمد مبني على هذه المقايسة؛ أعد فتحه من «البرامج الزمنية» قبل حذفها',
    );
  }
  if (items.isEmpty) {
    return (title: 'حذف المقايسة', message: 'تُحذف المقايسة نهائياً، ويبقى أثرها في سجل التدقيق.', blocked: null);
  }
  final emptiesPlan = projectIds.every((p) => app.pmItems.where((i) => i.projectId == p).every((i) => i.boqSheetId == id));
  return (
    title: 'حذف المقايسة وبنودها من البرنامج الزمني',
    message: 'تُحذف المقايسة نهائياً، ومعها ${itemsText(items.length)} من البرنامج الزمني للعقد في الشؤون الفنية وفي متابعة الإشراف'
        '${tracked > 0 ? '، منها ${itemsText(tracked)} عليه إنجاز مسجّل سيُحذف أيضاً' : ''}.'
        '${emptiesPlan ? ' ولن يبقى في البرنامج بند، فيُحذف البرنامج المسودة ومراحله.' : ' وتُحذف المراحل التي تفرغ، ويُعاد حساب البرنامج.'}'
        '\n\nيبقى أثر ذلك كله في سجل التدقيق.',
    blocked: null,
  );
}
