// =====================================================================
// قسم «الطباعة والتصدير»:
//   • لوحة الطباعة: استخراج سريع لأي سجل، وقوالب الطباعة، وسجل التصدير.
//   • مصمم صفحة الطباعة: كل خيارات الصفحة (الورق، الخط، الألوان، الشعار، الترويسة، الجدول، التذييل،
//     العلامة المائية، التوقيعات، الغلاف) بمعاينة حية، وحفظها قوالب عامة أو خاصة.
//   • مكتبة الوسائط: كل الصور والفيديو والملفات المرفوعة، بالتصفية والتنزيل المفرد والمجمّع (ZIP).
// =====================================================================

import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

import '../app_state.dart';
import '../docs.dart';
import '../models.dart';
import '../print/export_dialog.dart';
import '../print/exporter.dart';
import '../print/model.dart';
import '../print/output.dart';
import '../print/preview.dart';
import '../print/sources.dart';
import '../services/doc_files.dart';
import '../ui/slideshow.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';

/// القالب المطلوب فتحه في المصمم (يُستهلك مرة واحدة). '' لقالب جديد.
final ValueNotifier<String?> designerRequest = ValueNotifier<String?>(null);

const int _tabDesigner = 131;

// ---------------------------------------------------------------------
// لوحة الطباعة والتصدير
// ---------------------------------------------------------------------
class PrintCenterPage extends StatelessWidget {
  const PrintCenterPage({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final sem = Sem.of(context);
    final sources = exportSources(app);
    final media = app.v8Ready ? app.docs.files : const <DocFile>[];
    final bySection = <String, List<ExportSource>>{};
    for (final s in sources) {
      bySection.putIfAbsent(s.section, () => []).add(s);
    }
    return PageBody(maxWidth: 1180, onRefresh: app.loadAll, children: [
      PageHeader(
        title: 'الطباعة والتصدير',
        subtitle: 'استخراج أي سجل في المنظومة إلى PDF وWord وExcel وCSV وHTML وJSON، بتصميم صفحة تحدده أنت.',
        icon: Icons.print_rounded,
        actions: [
          FilledButton.icon(
            onPressed: () => showExportDialog(context),
            icon: const Icon(Icons.ios_share_rounded),
            label: const Text('تصدير سجل'),
          ),
          OutlinedButton.icon(
            onPressed: () {
              designerRequest.value = '';
              app.setTab(_tabDesigner);
            },
            icon: const Icon(Icons.design_services_outlined),
            label: const Text('تصميم قالب'),
          ),
        ],
      ),
      if (!app.v10Ready)
        const Padding(
          padding: EdgeInsets.only(bottom: 14),
          child: InfoBanner(
            text: 'الاستخراج والطباعة يعملان الآن بالتصميم الافتراضي. حفظ القوالب وسجل التصدير ورفع الفيديو تعمل بعد تحديث قاعدة البيانات '
                'بالملف 20261116000022_print_center.sql.',
            level: 'warning',
          ),
        ),
      ResponsiveGrid(minItemWidth: 200, children: [
        StatCard(label: 'سجلات قابلة للتصدير', value: '${sources.length}', icon: Icons.dataset_outlined),
        StatCard(label: 'قوالب الطباعة', value: '${app.printTemplates.length}', sub: app.defaultPrintTemplate?.name ?? 'التصميم الافتراضي', icon: Icons.design_services_outlined),
        StatCard(
          label: 'صور وفيديو',
          value: '${media.where((f) => f.isImage || f.isVideo).length}',
          sub: '${media.where((f) => f.isVideo).length} فيديو · ${fmtBytes(media.fold<int>(0, (s, f) => s + f.sizeBytes))}',
          icon: Icons.perm_media_outlined,
          onTap: () => app.setTab(132),
        ),
        StatCard(label: 'صيغ الاستخراج', value: '${ExportFormat.values.length}', sub: 'PDF · Word · Excel · CSV · HTML · JSON', icon: Icons.file_present_outlined),
      ]),
      const SizedBox(height: 14),
      SectionCard(
        title: 'استخراج سريع',
        subtitle: 'اختر السجل لتحدد التصفية والأعمدة والصيغة، ثم اطبع أو احفظ.',
        icon: Icons.bolt_rounded,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          for (final e in bySection.entries) ...[
            Padding(
              padding: const EdgeInsets.only(top: 8, bottom: 6),
              child: Text(exportSectionNames[e.key] ?? e.key, style: const TextStyle(fontWeight: FontWeight.w800)),
            ),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final s in e.value)
                ActionChip(
                  avatar: Icon(s.icon, size: 18),
                  label: Text('${s.title} (${s.count(app)})'),
                  onPressed: () => showExportDialog(context, sourceId: s.id),
                ),
            ]),
          ],
        ]),
      ),
      const SizedBox(height: 14),
      SectionCard(
        title: 'قوالب الطباعة',
        subtitle: app.canShareTemplates
            ? 'القوالب العامة يراها الجميع، والقالب الافتراضي يُختار تلقائياً عند الطباعة.'
            : 'القوالب العامة يعدّها مكتب المدير؛ ولك أن تحفظ قوالب خاصة بك.',
        icon: Icons.design_services_outlined,
        trailing: TextButton.icon(
          onPressed: app.v10Ready
              ? () {
                  designerRequest.value = '';
                  app.setTab(_tabDesigner);
                }
              : null,
          icon: const Icon(Icons.add_rounded),
          label: const Text('قالب جديد'),
        ),
        child: app.printTemplates.isEmpty
            ? Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text('لا قوالب محفوظة بعد؛ تُستعمل الطباعة بالتصميم الافتراضي للمنظومة.', style: TextStyle(color: sem.muted)),
              )
            : Column(children: [
                for (final tp in app.printTemplates)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: CircleAvatar(backgroundColor: Color(tp.config.accent), child: const Icon(Icons.description_outlined, color: Colors.white)),
                    title: Text(tp.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: Wrap(spacing: 6, runSpacing: 4, children: [
                      if (tp.isDefault) ToneBadge('افتراضي', color: sem.ok, icon: Icons.star_rounded),
                      ToneBadge(tp.shared ? 'عام' : 'خاص بك', color: tp.shared ? Theme.of(context).colorScheme.primary : sem.muted),
                      ToneBadge('${tp.config.paper} · ${_fontName(tp.config.font)}', color: sem.muted),
                    ]),
                    trailing: Wrap(children: [
                      IconButton(
                        tooltip: app.canEditTemplate(tp) ? 'تعديل في المصمم' : 'فتح نسخة في المصمم',
                        onPressed: () {
                          designerRequest.value = tp.id;
                          app.setTab(_tabDesigner);
                        },
                        icon: const Icon(Icons.edit_outlined),
                      ),
                      if (app.canEditTemplate(tp))
                        IconButton(
                          tooltip: 'حذف القالب',
                          onPressed: () async {
                            final ok = await confirmDialog(context,
                                title: 'حذف ${tp.name}', message: 'يُحذف القالب نهائياً. الملفات المطبوعة به سابقاً لا تتأثر.', confirmLabel: 'حذف', danger: true);
                            if (!ok || !context.mounted) return;
                            try {
                              await app.deletePrintTemplate(tp.id);
                              if (context.mounted) showToast(context, 'حُذف القالب');
                            } catch (e) {
                              if (context.mounted) showToast(context, friendlyError(e), error: true);
                            }
                          },
                          icon: Icon(Icons.delete_outline_rounded, color: sem.danger),
                        ),
                    ]),
                  ),
              ]),
      ),
      if (app.canAudit && app.v10Ready) ...[
        const SizedBox(height: 14),
        const _ExportLogCard(),
      ],
    ]);
  }
}

String _fontName(String f) => switch (f) { 'kufi' => 'كوفي', 'sans' => 'سانس', _ => 'نسخ' };

/// آخر ما استُخرج من المنظومة (للمدير ومدقق الأمن، من سجل التدقيق).
class _ExportLogCard extends StatefulWidget {
  const _ExportLogCard();

  @override
  State<_ExportLogCard> createState() => _ExportLogCardState();
}

class _ExportLogCardState extends State<_ExportLogCard> {
  Future<List<AuditEntry>>? _f;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _f ??= AppScope.read(context).loadAudit(limit: 400);
  }

  @override
  Widget build(BuildContext context) {
    final sem = Sem.of(context);
    return SectionCard(
      title: 'سجل التصدير',
      subtitle: 'كل ملف يُستخرج أو يُطبع أو يُنزَّل مجمّعاً يُسجَّل في التدقيق.',
      icon: Icons.history_rounded,
      child: FutureBuilder<List<AuditEntry>>(
        future: _f,
        builder: (context, snap) {
          if (snap.hasError) return Text('تعذّر تحميل سجل التصدير.', style: TextStyle(color: sem.muted));
          if (!snap.hasData) return const Padding(padding: EdgeInsets.all(12), child: LinearProgressIndicator());
          final l = snap.data!.where((e) => e.action.startsWith('export.')).take(15).toList();
          if (l.isEmpty) return Text('لا عمليات تصدير بعد.', style: TextStyle(color: sem.muted));
          return Column(children: [
            for (final e in l)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Icon(e.action == 'export.media' ? Icons.folder_zip_outlined : (e.action == 'export.print' ? Icons.print_outlined : Icons.download_rounded),
                    color: sem.muted),
                title: Text('${e.detail['title'] ?? ''} · ${(e.detail['format'] ?? '').toString().toUpperCase()}'),
                subtitle: Text('${e.actorName} · ${e.at == null ? '' : dayText(e.at!.toLocal())} · ${e.detail['rows'] ?? 0} سجل'),
              ),
          ]);
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------
// مصمم صفحة الطباعة
// ---------------------------------------------------------------------
class PrintDesignerPage extends StatefulWidget {
  const PrintDesignerPage({super.key});

  @override
  State<PrintDesignerPage> createState() => _PrintDesignerPageState();
}

class _PrintDesignerPageState extends State<PrintDesignerPage> {
  String? _id;
  final _name = TextEditingController(text: 'قالب جديد');
  bool _shared = false;
  bool _default = false;
  PrintConfig _c = PrintConfig();
  String _sample = 'cycle:contracts';
  bool _coverPreview = false;
  bool _busy = false;
  int _tab = 0;

  final Map<String, TextEditingController> _text = {};

  @override
  void initState() {
    super.initState();
    designerRequest.addListener(_consume);
    WidgetsBinding.instance.addPostFrameCallback((_) => _consume());
  }

  @override
  void dispose() {
    designerRequest.removeListener(_consume);
    _name.dispose();
    for (final t in _text.values) {
      t.dispose();
    }
    super.dispose();
  }

  void _consume() {
    final req = designerRequest.value;
    if (req == null || !mounted) return;
    designerRequest.value = null;
    final app = AppScope.read(context);
    final tp = app.printTemplates.where((t) => t.id == req).firstOrNull;
    setState(() {
      _load(tp, app);
    });
  }

  void _load(PrintTemplate? tp, AppState app) {
    // الحقول الحالية ما زالت مرسومة في هذا الإطار؛ تُتلف بعده
    final old = _text.values.toList();
    _text.clear();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final t in old) {
        t.dispose();
      }
    });
    if (tp == null) {
      _id = null;
      _name.text = 'قالب جديد';
      _shared = false;
      _default = false;
      _c = app.defaultPrintTemplate?.config.copy() ?? PrintConfig();
    } else {
      final mine = app.canEditTemplate(tp);
      _id = mine ? tp.id : null;
      _name.text = mine ? tp.name : '${tp.name} (نسخة)';
      _shared = mine && tp.shared;
      _default = mine && tp.isDefault;
      _c = tp.config.copy();
    }
  }

  TextEditingController _ctl(String key, String value) => _text.putIfAbsent(key, () => TextEditingController(text: value));

  Future<void> _save({bool asNew = false}) async {
    final app = AppScope.read(context);
    setState(() => _busy = true);
    try {
      final id = await app.savePrintTemplate(asNew ? null : _id, _name.text.trim(), _c,
          shared: _shared && app.canShareTemplates, isDefault: _default && app.canShareTemplates);
      _id = id;
      if (mounted) showToast(context, 'حُفظ القالب «${_name.text.trim()}»');
    } catch (e) {
      if (mounted) showToast(context, friendlyError(e), error: true);
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _pickLogo() async {
    try {
      final files = await pickDocFiles(pdf: false, images: true);
      if (files.isEmpty) return;
      final decoded = img.decodeImage(files.first.bytes);
      if (decoded == null) throw StateError('تعذّرت قراءة الصورة');
      final big = decoded.width >= decoded.height;
      final resized = (decoded.width > 420 || decoded.height > 420)
          ? img.copyResize(decoded, width: big ? 420 : null, height: big ? null : 420, interpolation: img.Interpolation.average)
          : decoded;
      final png = img.encodePng(resized);
      setState(() {
        _c.customLogo = base64Encode(png);
        _c.logo = 'custom';
      });
    } catch (e) {
      if (mounted) showToast(context, friendlyError(e), error: true);
    }
  }

  ExportTable _sampleTable(AppState app) {
    final s = exportSource(app, _sample) ?? (exportSources(app).isEmpty ? null : exportSources(app).first);
    if (s == null) {
      return ExportTable(sourceId: 'sample', title: 'نموذج', columns: const [ExportColumn('a', 'العمود')], rows: const []);
    }
    final t = s.build(app, const ExportQuery());
    return t.select([for (final c in s.columns) if (c.on) c.key]);
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final sem = Sem.of(context);
    final wide = MediaQuery.sizeOf(context).width >= 1000;
    final table = _sampleTable(app);
    final ctx = previewPrintContext(app, table.sourceId);
    final sources = exportSources(app);
    if (!sources.any((s) => s.id == _sample) && sources.isNotEmpty) _sample = sources.first.id;

    final preview = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Wrap(spacing: 10, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
        SizedBox(
          width: 300,
          child: DropdownButtonFormField<String>(
            key: ValueKey('sample$_sample'),
            initialValue: sources.any((s) => s.id == _sample) ? _sample : null,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'بيانات المعاينة', border: OutlineInputBorder(), isDense: true),
            items: [for (final s in sources) DropdownMenuItem(value: s.id, child: Text('${exportSectionNames[s.section] ?? ''} · ${s.title}', overflow: TextOverflow.ellipsis))],
            onChanged: (v) => setState(() => _sample = v ?? _sample),
          ),
        ),
        if (_c.cover)
          FilterChip(label: const Text('صفحة الغلاف'), selected: _coverPreview, onSelected: (v) => setState(() => _coverPreview = v)),
        OutlinedButton.icon(
          onPressed: () => runExport(context, table, _c, ExportFormat.pdf, print: true),
          icon: const Icon(Icons.picture_as_pdf_outlined),
          label: const Text('PDF فعلي'),
        ),
        OutlinedButton.icon(
          onPressed: () => runExport(context, table, _c, ExportFormat.docx),
          icon: const Icon(Icons.description_outlined),
          label: const Text('تجربة Word'),
        ),
        OutlinedButton.icon(
          onPressed: () => runExport(context, table, _c, ExportFormat.html, print: true),
          icon: const Icon(Icons.language_rounded),
          label: const Text('HTML'),
        ),
      ]),
      const SizedBox(height: 12),
      Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(color: sem.surface2, borderRadius: BorderRadius.circular(14), border: Border.all(color: sem.rule)),
        child: Center(child: PagePreview(config: _c, table: table, context0: ctx, cover: _coverPreview && _c.cover)),
      ),
    ]);

    final options = _options(app);
    final header = PageHeader(
      title: 'مصمم صفحة الطباعة',
      subtitle: _id == null ? 'قالب جديد: اضبط الخيارات وشاهد أثرها مباشرة، ثم احفظ.' : 'تعديل القالب «${_name.text}»',
      icon: Icons.design_services_rounded,
      actions: [
        FilledButton.icon(
          onPressed: _busy || !app.v10Ready ? null : () => _save(),
          icon: const Icon(Icons.save_outlined),
          label: Text(_id == null ? 'حفظ القالب' : 'حفظ التعديلات'),
        ),
        if (_id != null)
          OutlinedButton.icon(onPressed: _busy || !app.v10Ready ? null : () => _save(asNew: true), icon: const Icon(Icons.copy_rounded), label: const Text('حفظ كقالب جديد')),
        TextButton.icon(
          onPressed: () => setState(() {
            _load(null, app);
            _c = PrintConfig();
          }),
          icon: const Icon(Icons.restart_alt_rounded),
          label: const Text('البدء من الافتراضي'),
        ),
      ],
    );

    if (wide) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(24, 22, 24, 0),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          header,
          if (!app.v10Ready)
            const Padding(
              padding: EdgeInsets.only(bottom: 10),
              child: InfoBanner(text: 'حفظ القوالب يعمل بعد تحديث قاعدة البيانات بالترحيل 22؛ يمكنك الآن التجربة والطباعة.', level: 'warning'),
            ),
          Expanded(
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SizedBox(width: 420, child: ListView(padding: const EdgeInsets.only(bottom: 30), children: options)),
              const SizedBox(width: 20),
              Expanded(child: SingleChildScrollView(padding: const EdgeInsets.only(bottom: 30), child: preview)),
            ]),
          ),
        ]),
      );
    }
    return PageBody(children: [
      header,
      SegmentedButton<int>(
        segments: const [
          ButtonSegment(value: 0, label: Text('الخيارات'), icon: Icon(Icons.tune_rounded)),
          ButtonSegment(value: 1, label: Text('المعاينة'), icon: Icon(Icons.visibility_outlined)),
        ],
        selected: {_tab},
        onSelectionChanged: (v) => setState(() => _tab = v.first),
      ),
      const SizedBox(height: 12),
      if (_tab == 0) ...options else preview,
    ]);
  }

  // ------------------------------------------------------------- لوحة الخيارات
  List<Widget> _options(AppState app) {
    final sem = Sem.of(context);
    Widget group(String title, IconData icon, List<Widget> children, {bool open = false}) => Card(
          margin: const EdgeInsets.only(bottom: 10),
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: sem.rule)),
          child: ExpansionTile(
            initiallyExpanded: open,
            leading: Icon(icon),
            title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
            shape: const Border(),
            collapsedShape: const Border(),
            childrenPadding: const EdgeInsets.fromLTRB(14, 8, 14, 14),
            expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
            children: children,
          ),
        );
    Widget sw(String label, bool v, void Function(bool) set, {String? sub}) => SwitchListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: Text(label),
          subtitle: sub == null ? null : Text(sub),
          value: v,
          onChanged: (x) => setState(() => set(x)),
        );
    Widget seg(String label, String v, List<(String, String)> opts, void Function(String) set) => Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: TextStyle(color: sem.muted, fontSize: 12.5)),
            const SizedBox(height: 4),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final o in opts) ChoiceChip(label: Text(o.$2), selected: v == o.$1, onSelected: (_) => setState(() => set(o.$1))),
            ]),
          ]),
        );
    Widget slider(String label, double v, double min, double max, void Function(double) set, {int div = 10, String Function(double)? fmt}) => Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Row(children: [
            SizedBox(width: 110, child: Text(label, style: TextStyle(color: sem.muted, fontSize: 12.5))),
            Expanded(child: Slider(value: v.clamp(min, max), min: min, max: max, divisions: div, onChanged: (x) => setState(() => set(x)))),
            SizedBox(width: 44, child: Text(fmt == null ? v.toStringAsFixed(v % 1 == 0 ? 0 : 1) : fmt(v), textAlign: TextAlign.center)),
          ]),
        );
    Widget field(String key, String label, String value, void Function(String) set, {int lines = 1, String? hint}) => Padding(
          padding: const EdgeInsets.only(top: 8),
          child: TextField(
            controller: _ctl(key, value),
            minLines: lines,
            maxLines: lines == 1 ? 1 : lines + 2,
            decoration: InputDecoration(labelText: label, hintText: hint, border: const OutlineInputBorder(), isDense: true),
            onChanged: (x) => setState(() => set(x)),
          ),
        );
    const palette = [0xFF8A6A1E, 0xFF0B6E99, 0xFF1F3A5F, 0xFF2E7D32, 0xFF0F766E, 0xFF6D3FB2, 0xFFC62828, 0xFF8A5A2B, 0xFF37474F, 0xFF000000];
    final sample = exportSource(app, _sample);

    return [
      group('القالب', Icons.bookmark_outline_rounded, [
        TextField(controller: _name, decoration: const InputDecoration(labelText: 'اسم القالب', border: OutlineInputBorder(), isDense: true)),
        if (app.canShareTemplates) ...[
          sw('قالب عام للمكتب', _shared, (v) => _shared = v, sub: 'يراه ويستعمله كل المستخدمين'),
          sw('القالب الافتراضي', _default, (v) {
            _default = v;
            if (v) _shared = true;
          }, sub: 'يُختار تلقائياً عند الطباعة من أي صفحة'),
        ] else
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text('يُحفظ قالباً خاصاً بك. القوالب العامة يعدّها مكتب المدير.', style: TextStyle(color: sem.muted, fontSize: 12.5)),
          ),
      ], open: true),
      group('الصفحة والخط', Icons.description_outlined, [
        seg('مقاس الورق', _c.paper, const [('A4', 'A4'), ('A3', 'A3'), ('A5', 'A5'), ('Letter', 'Letter'), ('Legal', 'Legal')], (v) => _c.paper = v),
        seg('الاتجاه', _c.orientation, const [('auto', 'تلقائي حسب الأعمدة'), ('portrait', 'عمودي'), ('landscape', 'أفقي')], (v) => _c.orientation = v),
        seg('الهوامش', _c.margins, const [('narrow', 'ضيقة 9 مم'), ('normal', 'عادية 15 مم'), ('wide', 'واسعة 22 مم')], (v) => _c.margins = v),
        seg('الخط', _c.font, const [('naskh', 'نسخ رسمي'), ('kufi', 'كوفي'), ('sans', 'سانس حديث')], (v) => _c.font = v),
        slider('حجم الخط', _c.fontSize, 7, 16, (v) => _c.fontSize = v, div: 18),
        seg('صيغة التاريخ', _c.dateStyle, const [('ymd', '2026/11/16'), ('dmy', '16/11/2026'), ('long', '16 نوفمبر 2026')], (v) => _c.dateStyle = v),
        sw('أرقام مشرقية (١٢٣)', _c.eastern, (v) => _c.eastern = v),
      ]),
      group('الألوان', Icons.palette_outlined, [
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Wrap(spacing: 8, runSpacing: 8, children: [
            for (final p in palette)
              InkWell(
                onTap: () => setState(() => _c.accent = p),
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: Color(p),
                    shape: BoxShape.circle,
                    border: Border.all(color: _c.accent == p ? Theme.of(context).colorScheme.onSurface : Colors.transparent, width: 3),
                  ),
                ),
              ),
          ]),
        ),
        seg('رأس الجدول', _c.headerFill, const [('accent', 'باللون الرئيسي'), ('gray', 'رمادي'), ('none', 'دون تعبئة')], (v) => _c.headerFill = v),
        seg('خط الترويسة', _c.headerLine, const [('double', 'مزدوج'), ('single', 'مفرد'), ('none', 'دون خط')], (v) => _c.headerLine = v),
      ]),
      group('الترويسة والشعار', Icons.badge_outlined, [
        seg('الشعار', _c.logo, const [('emblem', 'ختم المؤسسة'), ('banner', 'الشعار العريض'), ('custom', 'شعار مخصص'), ('none', 'دون شعار')], (v) => _c.logo = v),
        if (_c.logo == 'custom')
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(children: [
              if (_c.customLogo.isNotEmpty)
                Container(
                  height: 48,
                  margin: const EdgeInsetsDirectional.only(end: 10),
                  child: Image.memory(base64Decode(_c.customLogo), fit: BoxFit.contain),
                ),
              OutlinedButton.icon(onPressed: _pickLogo, icon: const Icon(Icons.upload_rounded), label: Text(_c.customLogo.isEmpty ? 'اختيار صورة الشعار' : 'تغيير الصورة')),
            ]),
          ),
        seg('موضع الشعار', _c.logoPos, const [('right', 'يمين'), ('center', 'وسط'), ('left', 'يسار')], (v) => _c.logoPos = v),
        slider('ارتفاع الشعار', _c.logoSize, 30, 120, (v) => _c.logoSize = v, div: 18),
        for (var i = 0; i < 4; i++)
          field('org$i', 'سطر الجهة ${i + 1}', i < _c.orgLines.length ? _c.orgLines[i] : '', (v) {
            while (_c.orgLines.length <= i) {
              _c.orgLines.add('');
            }
            _c.orgLines[i] = v;
          }),
        sw('الرقم المرجعي', _c.showRef, (v) => _c.showRef = v, sub: 'يُولَّد تلقائياً بتاريخ ووقت الطباعة'),
        if (_c.showRef) field('ref', 'بادئة الرقم', _c.refPrefix, (v) => _c.refPrefix = v, hint: 'مثل م.ش.هـ'),
        sw('تاريخ الطباعة', _c.showDate, (v) => _c.showDate = v),
      ]),
      group('العنوان والبيانات', Icons.title_rounded, [
        seg('العنوان', _c.titleMode, const [('auto', 'اسم السجل تلقائياً'), ('custom', 'عنوان مخصص')], (v) => _c.titleMode = v),
        if (_c.titleMode == 'custom') field('title', 'العنوان المخصص', _c.customTitle, (v) => _c.customTitle = v),
        field('subtitle', 'عنوان فرعي', _c.subtitle, (v) => _c.subtitle = v, hint: 'مثل: تقرير مقدم إلى اللجنة'),
        sw('اسم القسم تحت العنوان', _c.showSection, (v) => _c.showSection = v),
        sw('وصف ما استُخرج', _c.showMeta, (v) => _c.showMeta = v, sub: 'العقد والفترة والتصفية وعدد السجلات'),
        sw('بطاقات المؤشرات', _c.showSummary, (v) => _c.showSummary = v),
      ]),
      group('الجدول', Icons.table_chart_outlined, [
        sw('ترقيم الصفوف', _c.rowNumbers, (v) => _c.rowNumbers = v),
        sw('تلوين الصفوف بالتناوب', _c.zebra, (v) => _c.zebra = v),
        sw('سطر المجاميع', _c.totals, (v) => _c.totals = v, sub: 'للأعمدة المالية والرقمية'),
        sw('تكرار رأس الجدول في كل صفحة', _c.repeatHeader, (v) => _c.repeatHeader = v),
        seg('الحدود', _c.borders, const [('all', 'كاملة'), ('horizontal', 'أفقية'), ('none', 'دون حدود')], (v) => _c.borders = v),
        slider('حشو الخلايا', _c.cellPadding, 1, 10, (v) => _c.cellPadding = v, div: 9),
        if (sample != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: DropdownButtonFormField<String>(
              key: ValueKey('grp${sample.id}${_c.groupBy}'),
              initialValue: sample.columns.any((c) => c.key == _c.groupBy) ? _c.groupBy : '',
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'تجميع الصفوف حسب', border: OutlineInputBorder(), isDense: true),
              items: [
                const DropdownMenuItem(value: '', child: Text('دون تجميع')),
                for (final c in sample.columns)
                  if (!c.numeric && c.type != ColType.long) DropdownMenuItem(value: c.key, child: Text(c.label)),
              ],
              onChanged: (v) => setState(() => _c.groupBy = v ?? ''),
            ),
          ),
      ]),
      group('التذييل والتحقق', Icons.vertical_align_bottom_rounded, [
        field('footer', 'نص التذييل', _c.footerText, (v) => _c.footerText = v, hint: 'مثل العنوان أو الهاتف'),
        field('conf', 'عبارة السرية', _c.confidential, (v) => _c.confidential = v, hint: 'مثل: للاستخدام الرسمي فقط'),
        sw('رقم الصفحة', _c.pageNumbers, (v) => _c.pageNumbers = v),
        sw('اسم من طبع ووقت الطباعة', _c.showPrintedBy, (v) => _c.showPrintedBy = v),
        sw('رمز التحقق QR', _c.qr, (v) => _c.qr = v, sub: 'يحمل العنوان والرقم المرجعي والتاريخ وعدد السجلات ومن طبع'),
      ]),
      group('العلامة المائية', Icons.water_drop_outlined, [
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final w in const ['', 'مسودة', 'سري', 'نسخة غير رسمية', 'للاستخدام الداخلي'])
            ChoiceChip(
              label: Text(w.isEmpty ? 'دون علامة' : w),
              selected: _c.watermark == w,
              onSelected: (_) => setState(() {
                _c.watermark = w;
                _ctl('wm', '').text = w;
              }),
            ),
        ]),
        field('wm', 'نص مخصص', _c.watermark, (v) => _c.watermark = v),
        slider('الشفافية', _c.watermarkOpacity, 0.02, 0.4, (v) => _c.watermarkOpacity = v, div: 19, fmt: (v) => '${(v * 100).round()}%'),
      ]),
      group('التوقيعات', Icons.draw_outlined, [
        sw('خانات التوقيع في آخر المستند', _c.showSignatures, (v) => _c.showSignatures = v),
        if (_c.showSignatures) ...[
          for (var i = 0; i < _c.signatures.length; i++)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(children: [
                Expanded(
                  child: TextField(
                    controller: _ctl('sigt$i', _c.signatures[i].title),
                    decoration: const InputDecoration(labelText: 'الصفة', border: OutlineInputBorder(), isDense: true),
                    onChanged: (v) => setState(() => _c.signatures[i] = SignatureSlot(v, _c.signatures[i].name)),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _ctl('sign$i', _c.signatures[i].name),
                    decoration: const InputDecoration(labelText: 'الاسم', border: OutlineInputBorder(), isDense: true),
                    onChanged: (v) => setState(() => _c.signatures[i] = SignatureSlot(_c.signatures[i].title, v)),
                  ),
                ),
                IconButton(
                  tooltip: 'إزالة',
                  onPressed: () => setState(() {
                    _c.signatures.removeAt(i);
                    // تُعاد قراءة خانات التوقيع من القالب بعد الحذف
                    final old = [for (final k in _text.keys.where((k) => k.startsWith('sig')).toList()) _text.remove(k)];
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      for (final c in old) {
                        c?.dispose();
                      }
                    });
                  }),
                  icon: const Icon(Icons.remove_circle_outline_rounded),
                ),
              ]),
            ),
          if (_c.signatures.length < 5)
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                onPressed: () => setState(() => _c.signatures.add(const SignatureSlot('الصفة'))),
                icon: const Icon(Icons.add_rounded),
                label: const Text('خانة توقيع'),
              ),
            ),
        ],
      ]),
      group('الغلاف والملاحظات', Icons.auto_stories_outlined, [
        sw('صفحة غلاف', _c.cover, (v) => _c.cover = v, sub: 'بالشعار الكبير والعنوان والتاريخ'),
        if (_c.cover) field('cover', 'نص على الغلاف', _c.coverNote, (v) => _c.coverNote = v, lines: 2),
        field('notes', 'ملاحظات ختامية', _c.notes, (v) => _c.notes = v, lines: 2),
      ]),
      group('Word', Icons.description_outlined, [
        field('wfont', 'خط Word (اختياري)', _c.wordFont, (v) => _c.wordFont = v, hint: 'افتراضياً: ${_c.wordFontName}'),
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text('Word يستعمل خطوط الجهاز؛ الخطوط المقترحة مثبتة في Windows.', style: TextStyle(color: sem.muted, fontSize: 12)),
        ),
      ]),
    ];
  }
}

// ---------------------------------------------------------------------
// مكتبة الوسائط
// ---------------------------------------------------------------------
class MediaLibraryPage extends StatefulWidget {
  const MediaLibraryPage({super.key});

  @override
  State<MediaLibraryPage> createState() => _MediaLibraryPageState();
}

class _MediaLibraryPageState extends State<MediaLibraryPage> {
  String _type = 'media';
  String _section = 'all';
  String _project = 'all';
  final _search = TextEditingController();
  final Set<String> _selected = {};

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<DocFile> _filtered(AppState app) {
    final q = normalizeArabic(_search.text.trim());
    return [
      for (final f in app.docs.files)
        if ((_type == 'all' ||
                (_type == 'media' && (f.isImage || f.isVideo)) ||
                (_type == 'image' && f.isImage) ||
                (_type == 'video' && f.isVideo) ||
                (_type == 'pdf' && f.isPdf)) &&
            (_section == 'all' || mediaSectionOf(app, f) == _section) &&
            (_project == 'all' || mediaProjectOf(app, f) == _project) &&
            (q.isEmpty || normalizeArabic('${f.name} ${mediaOwnerLabel(app, f)}').contains(q)))
          f,
    ]..sort((a, b) => (b.createdAt ?? DateTime(2000)).compareTo(a.createdAt ?? DateTime(2000)));
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final sem = Sem.of(context);
    if (!app.v8Ready) {
      return const PageBody(children: [
        PageHeader(title: 'مكتبة الوسائط', icon: Icons.perm_media_rounded),
        InfoBanner(text: 'مكتبة الوسائط تعمل بعد تحديث قاعدة البيانات بالملف 20261114000020_documents_supervision.sql.', level: 'warning'),
      ]);
    }
    final list = _filtered(app);
    final sel = list.where((f) => _selected.contains(f.id)).toList();
    final selBytes = sel.fold<int>(0, (s, f) => s + f.sizeBytes);
    final projects = {for (final f in app.docs.files) if (mediaProjectOf(app, f) != null) mediaProjectOf(app, f)!};
    final sections = {for (final f in app.docs.files) mediaSectionOf(app, f)};
    final width = MediaQuery.sizeOf(context).width;
    final cols = width < 600 ? 2 : (width < 1000 ? 3 : 5);

    return PageBody(maxWidth: 1280, onRefresh: app.loadAll, children: [
      PageHeader(
        title: 'مكتبة الوسائط',
        subtitle: 'كل الصور والفيديو والملفات المرفوعة في المنظومة. اختر ما تريد وحمّله ملفاً واحداً أو حزمة ZIP.',
        icon: Icons.perm_media_rounded,
        actions: [
          ExportButton(sourceId: 'media:files', items: list),
          FilledButton.icon(
            onPressed: list.isEmpty ? null : () => _downloadZip(context, sel.isNotEmpty ? sel : list),
            icon: const Icon(Icons.folder_zip_outlined),
            label: Text(sel.isNotEmpty ? 'تنزيل المحدد (${sel.length})' : 'تنزيل الكل (${list.length})'),
          ),
        ],
      ),
      ResponsiveGrid(minItemWidth: 170, children: [
        StatCard(label: 'صور', value: '${app.docs.files.where((f) => f.isImage).length}', icon: Icons.image_outlined),
        StatCard(label: 'فيديو', value: '${app.docs.files.where((f) => f.isVideo).length}', icon: Icons.movie_outlined),
        StatCard(label: 'ملفات PDF', value: '${app.docs.files.where((f) => f.isPdf).length}', icon: Icons.picture_as_pdf_outlined),
        StatCard(label: 'المساحة', value: fmtBytes(app.docs.totalBytes), icon: Icons.cloud_outlined),
      ]),
      const SizedBox(height: 14),
      Wrap(spacing: 10, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.center, children: [
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'media', label: Text('صور وفيديو')),
            ButtonSegment(value: 'image', label: Text('صور')),
            ButtonSegment(value: 'video', label: Text('فيديو')),
            ButtonSegment(value: 'pdf', label: Text('PDF')),
            ButtonSegment(value: 'all', label: Text('الكل')),
          ],
          selected: {_type},
          onSelectionChanged: (v) => setState(() => _type = v.first),
        ),
        _drop('القسم', _section, [('all', 'كل الأقسام'), for (final s in sections) (s, exportSectionNames[s] ?? s)], (v) => _section = v),
        _drop('العقد', _project, [('all', 'كل العقود'), for (final p in app.projects) if (projects.contains(p.id)) (p.id, p.label)], (v) => _project = v,
            width: 260),
        SizedBox(
          width: 220,
          child: TextField(
            controller: _search,
            decoration: const InputDecoration(labelText: 'بحث بالاسم أو المصدر', border: OutlineInputBorder(), isDense: true, prefixIcon: Icon(Icons.search_rounded)),
            onChanged: (_) => setState(() {}),
          ),
        ),
      ]),
      const SizedBox(height: 10),
      Row(children: [
        Text('${list.length} ملف${sel.isEmpty ? '' : ' · محدد ${sel.length} (${fmtBytes(selBytes)})'}', style: TextStyle(color: sem.muted)),
        const Spacer(),
        TextButton(onPressed: () => setState(() => _selected.addAll(list.map((f) => f.id))), child: const Text('تحديد الكل')),
        if (_selected.isNotEmpty) TextButton(onPressed: () => setState(_selected.clear), child: const Text('إلغاء التحديد')),
      ]),
      const SizedBox(height: 8),
      if (list.isEmpty)
        const EmptyState(title: 'لا ملفات', message: 'غيّر التصفية، أو ارفع الصور والفيديو من التقارير اليومية وسجلات الأقسام والتصاميم.', icon: Icons.perm_media_outlined)
      else
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: cols, mainAxisSpacing: 10, crossAxisSpacing: 10, childAspectRatio: 0.82),
          itemCount: list.length,
          itemBuilder: (context, i) => _tile(context, app, list[i], list),
        ),
    ]);
  }

  Widget _drop(String label, String value, List<(String, String)> items, void Function(String) set, {double width = 200}) => SizedBox(
        width: width,
        child: DropdownButtonFormField<String>(
          key: ValueKey('$label$value${items.length}'),
          initialValue: items.any((i) => i.$1 == value) ? value : items.first.$1,
          isExpanded: true,
          decoration: InputDecoration(labelText: label, border: const OutlineInputBorder(), isDense: true),
          items: [for (final i in items) DropdownMenuItem(value: i.$1, child: Text(i.$2, overflow: TextOverflow.ellipsis))],
          onChanged: (v) => setState(() => set(v ?? 'all')),
        ),
      );

  Widget _tile(BuildContext context, AppState app, DocFile f, List<DocFile> list) {
    final sem = Sem.of(context);
    final on = _selected.contains(f.id);
    final images = list.where((x) => x.isImage).toList();
    Widget thumb;
    if (f.isImage) {
      thumb = DocImage(file: f);
    } else {
      thumb = Container(
        color: sem.surface2,
        alignment: Alignment.center,
        child: Icon(f.isVideo ? Icons.play_circle_outline_rounded : Icons.picture_as_pdf_rounded, size: 46, color: f.isVideo ? sem.wip : sem.danger),
      );
    }
    return Material(
      color: cardColor(context),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: on ? Theme.of(context).colorScheme.primary : sem.rule, width: on ? 2 : 1)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () async {
          if (_selected.isNotEmpty) {
            setState(() => on ? _selected.remove(f.id) : _selected.add(f.id));
            return;
          }
          if (f.isImage) {
            await showSlideViewer(context, [for (final x in images) Slide(file: x, caption: mediaOwnerLabel(app, x))], images.indexOf(f));
          } else {
            try {
              await openDocExternally(await app.signedUrls.of(f.path));
            } catch (e) {
              if (context.mounted) showToast(context, friendlyError(e), error: true);
            }
          }
        },
        onLongPress: () => setState(() => on ? _selected.remove(f.id) : _selected.add(f.id)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Expanded(
            child: Stack(fit: StackFit.expand, children: [
              thumb,
              PositionedDirectional(
                top: 4,
                start: 4,
                child: Checkbox(
                  value: on,
                  onChanged: (v) => setState(() => v == true ? _selected.add(f.id) : _selected.remove(f.id)),
                ),
              ),
              if (f.isVideo)
                PositionedDirectional(bottom: 6, end: 6, child: ToneBadge('فيديو', color: sem.wip, icon: Icons.movie_rounded)),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 6, 2),
            child: Text(f.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5)),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Text(mediaOwnerLabel(app, f), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: sem.muted, fontSize: 11.5)),
          ),
          Row(children: [
            const SizedBox(width: 10),
            Expanded(child: Text('${fmtBytes(f.sizeBytes)} · ${f.createdAt == null ? '' : dayText(f.createdAt!.toLocal())}', style: TextStyle(color: sem.muted, fontSize: 11))),
            IconButton(
              tooltip: 'تنزيل',
              visualDensity: VisualDensity.compact,
              onPressed: () async {
                try {
                  await saveDocCopy(app.client, f.path, f.name, f.mime);
                  if (context.mounted) showToast(context, 'حُفظ ${f.name}');
                } catch (e) {
                  if (context.mounted) showToast(context, friendlyError(e), error: true);
                }
              },
              icon: const Icon(Icons.download_rounded, size: 20),
            ),
          ]),
        ]),
      ),
    );
  }
}

/// تنزيل عدة ملفات حزمةً واحدة (ZIP) بمجلد لكل مصدر، مع نافذة تقدّم. ملف واحد يُحفظ كما هو.
Future<void> _downloadZip(BuildContext context, List<DocFile> files) async {
  final app = AppScope.read(context);
  if (files.length == 1) {
    final f = files.first;
    try {
      await saveDocCopy(app.client, f.path, f.name, f.mime);
      if (context.mounted) showToast(context, 'حُفظ ${f.name}');
    } catch (e) {
      if (context.mounted) showToast(context, friendlyError(e), error: true);
    }
    return;
  }
  final total = files.fold<int>(0, (s, f) => s + f.sizeBytes);
  if (total > 400 * 1024 * 1024) {
    showToast(context, 'الحزمة ${fmtBytes(total)} أكبر من 400 ميجابايت؛ صفِّ بعقد أو قسم أو حدد ملفات أقل.', error: true);
    return;
  }
  final progress = ValueNotifier<int>(0);
  var cancelled = false;
  final nav = Navigator.of(context, rootNavigator: true);
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => PopScope(
      canPop: false,
      child: AlertDialog(
        title: const Text('تجهيز الحزمة'),
        content: ValueListenableBuilder<int>(
          valueListenable: progress,
          builder: (_, done, __) => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('$done من ${files.length} · ${fmtBytes(total)}'),
            const SizedBox(height: 12),
            LinearProgressIndicator(value: done == 0 ? null : done / files.length),
          ]),
        ),
        actions: [TextButton(onPressed: () => cancelled = true, child: const Text('إلغاء'))],
      ),
    ),
  );
  String? message;
  var error = false;
  try {
    final archive = Archive();
    final used = <String>{};
    for (final f in files) {
      if (cancelled) break;
      final bytes = await app.client.storage.from(docsBucket).download(f.path);
      // اسم المجلد من المصدر: الشرطة بدل / و: غير المسموحتين في أسماء الملفات
      final folder = safeFileName(mediaOwnerLabel(app, f).replaceAll('/', '-').replaceAll(':', ' -'));
      var name = '$folder/${safeFileName(f.name)}';
      var n = 2;
      while (used.contains(name)) {
        name = '$folder/${n++}-${safeFileName(f.name)}';
      }
      used.add(name);
      archive.addFile(ArchiveFile.noCompress(name, bytes.length, bytes));
      progress.value++;
    }
    if (!cancelled) {
      final out = ZipEncoder().encode(archive);
      final data = Uint8List.fromList(out ?? const <int>[]);
      final path = await saveBytes(data, 'وسائط المنظومة ${dayText(DateTime.now()).replaceAll('/', '-')}', 'zip');
      message = path == null ? null : 'حُفظت الحزمة (${files.length} ملفاً)';
      await app.logExport(kind: 'media', source: 'media', title: 'وسائط المنظومة', format: 'zip', rows: files.length, bytes: data.length);
    }
  } catch (e) {
    message = friendlyError(e);
    error = true;
  }
  if (nav.canPop()) nav.pop();
  progress.dispose();
  if (message != null && context.mounted) showToast(context, message, error: error);
}
