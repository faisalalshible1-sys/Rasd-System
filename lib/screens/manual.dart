import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../app_state.dart';
import '../assets.dart' show depPoliciesText;
import '../rasd.dart';
import '../config.dart';
import '../manual.dart';
import '../models.dart';
import '../services/doc_files.dart' show openDocExternally;
import '../ui/motion.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';

// =====================================================================
// قسم «دليل الاستخدام»: الفصول بفهرس وبحث وجداول حية، و«ما الجديد»، ونسخة PDF.
// =====================================================================

/// نصوص الفصول (تُقرأ مرة من حزمة التطبيق).
final Map<String, String> _texts = {};

Future<Map<String, String>> loadManualTexts() async {
  if (_texts.length < manualChapters.length + 1) {
    for (final c in manualChapters) {
      _texts[c.id] ??= await rootBundle.loadString(c.asset);
    }
    _texts['changelog'] ??= await rootBundle.loadString(manualChangelogAsset);
  }
  return _texts;
}

/// القيم الحية التي تُستبدل في نص الدليل.
Map<String, String> manualValues(AppState app) {
  final count = app.formDefs.length;
  final chat = app.settings.raw['chat.config'] is Map ? app.settings.raw['chat.config'] as Map : const {};
  final req = count - 1;
  return {
    'APP_VERSION': AppConfig.appVersion,
    'MANUAL_UPDATED': manualUpdated,
    'FORMS_COUNT': '$count',
    'FORMS_REQ': '$req',
    'FORMS_TODO': '${req - 13}',
    'FORMS_PCT10': req <= 0 ? '—' : pctText(10 / req),
    'FORMS_TABLE': manualFormsTable(
      stageNames: [for (var i = 0; i < 5 || i < stageNames.length; i++) stageName(i)],
      forms: [
        for (final f in app.formDefs) (name: f.name, stage: f.stage, sensitive: f.sensitive, responsible: f.responsible),
      ],
    ),
    'LEVELS_TABLE': manualLevelsTable([
      for (final l in app.riskConfig.levels) (name: l.name, min: l.min, action: l.action, reviewDays: l.reviewDays),
    ]),
    'CHAT_MAX_MB': '${chat['max_file_mb'] is num ? (chat['max_file_mb'] as num).toInt() : 50}',
    'CHAT_EDIT_MIN': '${chat['edit_minutes'] is num ? (chat['edit_minutes'] as num).toInt() : 60}',
    'SPI_AHEAD': app.pmConfig.spiAhead.toStringAsFixed(2),
    'SPI_OK': app.pmConfig.spiOk.toStringAsFixed(2),
    'SPI_WARN': app.pmConfig.spiWarn.toStringAsFixed(2),
    'PM_ALERT_DAYS': '${app.pmConfig.alertDays}',
    'GI_RATE': rateText(guaranteeInitialRate),
    'GF_RATE': rateText(guaranteeFinalRate),
    'RET_RATE': rateText(app.settings.retentionRate),
    'ST_DONE': FormStatus.done.label,
    'ST_WIP': FormStatus.wip.label,
    'ST_TODO': FormStatus.todo.label,
    'ST_NA': FormStatus.na.label,
    'STR_EXPIRY_DAYS': '${app.stores.settings.expiryDays}',
    'STR_SEPARATION': app.stores.settings.separation ? 'مفعّل' : 'معطّل',
    'STR_DEP_POLICIES': depPoliciesText([
      for (final c in app.stores.categories)
        if (app.storeAssets.policyOf(c.id) != null) (c.name, app.storeAssets.policyOf(c.id)!),
    ]),
    'MT_SLA_URGENT': '${app.maint.settings.slaHours('urgent')}',
    'MT_SLA_HIGH': '${app.maint.settings.slaHours('high')}',
    'MT_SLA_NORMAL': '${app.maint.settings.slaHours('normal')}',
    'MT_SLA_LOW': '${app.maint.settings.slaHours('low')}',
    'MT_ASSIGN_HOURS': '${app.maint.settings.assignHours}',
    'MT_HOLD_DAYS': '${app.maint.settings.holdDays}',
    'MT_CONFIRM_DAYS': '${app.maint.settings.confirmDays}',
    'MT_SOON_HOURS': '${app.maint.settings.soonHours}',
    'MT_REPEAT_COUNT': '${app.maint.settings.repeatCount}',
    'MT_REPEAT_DAYS': '${app.maint.settings.repeatDays}',
    'MT_PLAN_LEAD_DAYS': '${app.maint.settings.planLeadDays}',
    'REF_TABLE': manualRefTable([
      for (final r in (app.refSchemes.isEmpty ? defaultRefSchemes : app.refSchemes))
        (name: r.name, pattern: r.pattern, reset: refResetLabels[r.reset] ?? r.reset, example: r.preview(ctx: const {'section': 'cycle'}), active: r.active),
    ]),
  };
}

/// الصيغ الأساسية كما يزرعها الترحيل 23 (للدليل قبل تحديث قاعدة البيانات).
const List<RefScheme> defaultRefSchemes = [
  RefScheme(key: 'print', name: 'المطبوعات والملفات المصدّرة', pattern: 'م.ش.هـ/{SECTION}/{YYYY}/{SEQ}', codes: {'cycle': 'د.م'}, system: true),
  RefScheme(key: 'letter_out', name: 'المراسلات الصادرة', pattern: 'م.ش.هـ/ص/{YYYY}/{SEQ}', system: true),
  RefScheme(key: 'letter_in', name: 'المراسلات الواردة', pattern: 'م.ش.هـ/و/{YYYY}/{SEQ}', system: true),
  RefScheme(key: 'letter_internal', name: 'المراسلات الداخلية', pattern: 'م.ش.هـ/د/{YYYY}/{SEQ}', system: true),
];

/// جدول صيغ الأرقام الإشارية في الدليل.
String manualRefTable(List<({String name, String pattern, String reset, String example, bool active})> rows) => [
      '| الصيغة | النمط | إعادة التسلسل | أول رقم (مثال) |',
      '| --- | --- | --- | --- |',
      for (final r in rows) '| **${r.name}**${r.active ? '' : ' (موقوفة)'} | ${r.pattern} | ${r.reset} | ${r.example} |',
    ].join('\n');

const String manualPdfPath = 'manual/manual-latest.pdf';

Future<void> openManualPdf(BuildContext context) async {
  final app = AppScope.read(context);
  try {
    final url = await app.signedUrls.of(manualPdfPath);
    await openDocExternally(url);
  } catch (_) {
    if (context.mounted) showToast(context, 'تُنشر نسخة PDF تلقائياً مع الإصدار القادم من التطبيق.');
  }
}

// ---------------------------------------------------------------------
// صفحة الدليل
// ---------------------------------------------------------------------
class ManualPage extends StatefulWidget {
  const ManualPage({super.key});

  @override
  State<ManualPage> createState() => _ManualPageState();
}

class _ManualPageState extends State<ManualPage> {
  final _search = TextEditingController();
  final _scroll = ScrollController();
  String _chapter = manualChapters.first.id;
  Future<Map<String, String>>? _load;
  final Map<int, GlobalKey> _headingKeys = {};

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _load ??= loadManualTexts();
    final app = AppScope.read(context);
    final a = app.manualAnchor;
    if (a != null) {
      app.manualAnchor = null;
      if (manualChapter(a) != null) _chapter = a;
    }
  }

  @override
  void dispose() {
    _search.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _open(String id) {
    setState(() {
      _chapter = id;
      _headingKeys.clear();
    });
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  void _toSection(int index) {
    final ctx = _headingKeys[index]?.currentContext;
    if (ctx != null) Scrollable.ensureVisible(ctx, duration: Motion.of(context, 350), curve: Curves.easeOutCubic, alignment: 0.05);
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final sem = Sem.of(context);
    return FutureBuilder<Map<String, String>>(
      future: _load,
      builder: (context, snap) {
        final texts = snap.data;
        if (texts == null) {
          return snap.hasError
              ? const EmptyState(title: 'تعذّر فتح الدليل', icon: Icons.error_outline_rounded)
              : const SkeletonPage(cards: 2);
        }
        final values = manualValues(app);
        final q = _search.text.trim();
        // فصول أقسام المستخدم وحدها والفصول العامة (الترحيل 34)
        final mine = manualChaptersFor(app.seesSection);
        final counts = {for (final c in mine) c.id: q.isEmpty ? 0 : manualCount(manualPlain(texts[c.id] ?? ''), q)};
        final chapters = q.isEmpty ? mine : mine.where((c) => counts[c.id]! > 0).toList();
        if (!mine.any((c) => c.id == _chapter) || (q.isNotEmpty && chapters.isNotEmpty && !chapters.any((c) => c.id == _chapter))) {
          _chapter = (chapters.isEmpty ? mine : chapters).first.id;
        }
        final current = manualChapter(_chapter) ?? mine.first;
        final blocks = parseManual(applyManualValues(texts[current.id] ?? '', values));
        final sections = <(int, String)>[
          for (final (i, b) in blocks.indexed)
            if (b is MHeading && b.level == 2) (i, b.text),
        ];
        final wide = MediaQuery.sizeOf(context).width >= 1000;
        final idx = mine.indexOf(current);

        final toc = _Toc(
          chapters: chapters,
          current: current.id,
          counts: counts,
          query: q,
          sections: sections,
          onOpen: (id) {
            _open(id);
            if (!wide) Navigator.of(context).maybePop();
          },
          onSection: (i) {
            if (!wide) Navigator.of(context).maybePop();
            WidgetsBinding.instance.addPostFrameCallback((_) => _toSection(i));
          },
        );

        final searchBar = Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
          child: Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
            SizedBox(
              width: wide ? 420 : double.infinity,
              child: TextField(
                controller: _search,
                onChanged: (_) => setState(() {}),
                decoration: fieldDeco('ابحث في الدليل',
                    prefixIcon: const Icon(Icons.search_rounded),
                    suffix: q.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.close_rounded),
                            onPressed: () => setState(() => _search.clear()),
                          )),
              ),
            ),
            if (!wide)
              OutlinedButton.icon(
                onPressed: () => showModalBottomSheet<void>(
                  context: context,
                  showDragHandle: true,
                  isScrollControlled: true,
                  builder: (ctx) => SizedBox(height: MediaQuery.sizeOf(ctx).height * 0.8, child: toc),
                ),
                icon: const Icon(Icons.toc_rounded),
                label: const Text('الفهرس'),
              ),
            // نسخة PDF تضم الدليل كاملاً: لمكتب المدير ومن يرى كل الأقسام
            if (!app.isolated)
              OutlinedButton.icon(onPressed: () => openManualPdf(context), icon: const Icon(Icons.picture_as_pdf_outlined), label: const Text('نسخة PDF')),
            TextButton.icon(onPressed: () => app.setTab(81), icon: const Icon(Icons.new_releases_outlined), label: const Text('ما الجديد')),
            if (q.isNotEmpty)
              Text(chapters.isEmpty ? 'لا نتائج' : '${counts.values.fold<int>(0, (a, b) => a + b)} نتيجة في ${chapters.length} فصل',
                  style: TextStyle(color: sem.muted)),
          ]),
        );

        final content = q.isNotEmpty && chapters.isEmpty
            ? EmptyState(title: 'لا نتائج لـ «$q»', message: 'جرّب كلمة أقصر أو مرادفاً لها.', icon: Icons.search_off_rounded)
            : ListView(
                controller: _scroll,
                padding: EdgeInsets.fromLTRB(wide ? 28 : 16, 8, wide ? 28 : 16, 40),
                children: [
                  ManualBlocks(
                    blocks: blocks,
                    highlight: q,
                    chapterNumber: current.number,
                    headingKeys: _headingKeys,
                  ),
                  const SizedBox(height: 24),
                  Divider(color: sem.rule),
                  Row(children: [
                    Expanded(
                      child: idx > 0
                          ? Align(
                              alignment: AlignmentDirectional.centerStart,
                              child: TextButton.icon(
                                onPressed: () => _open(mine[idx - 1].id),
                                icon: const Icon(Icons.chevron_right_rounded),
                                label: Text(mine[idx - 1].label, maxLines: 1, overflow: TextOverflow.ellipsis),
                              ),
                            )
                          : const SizedBox.shrink(),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: idx < mine.length - 1
                          ? Align(
                              alignment: AlignmentDirectional.centerEnd,
                              child: TextButton.icon(
                                onPressed: () => _open(mine[idx + 1].id),
                                icon: const Icon(Icons.chevron_left_rounded),
                                label: Text(mine[idx + 1].label, maxLines: 1, overflow: TextOverflow.ellipsis),
                              ),
                            )
                          : const SizedBox.shrink(),
                    ),
                  ]),
                ],
              );

        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          searchBar,
          Divider(height: 1, color: sem.rule),
          Expanded(
            child: wide
                ? Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    SizedBox(width: 300, child: toc),
                    VerticalDivider(width: 1, color: sem.rule),
                    Expanded(
                      child: Align(
                        alignment: AlignmentDirectional.topStart,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 960),
                          child: MotionSwitcher(child: KeyedSubtree(key: ValueKey(current.id), child: content)),
                        ),
                      ),
                    ),
                  ])
                : MotionSwitcher(child: KeyedSubtree(key: ValueKey(current.id), child: content)),
          ),
        ]);
      },
    );
  }
}

class _Toc extends StatelessWidget {
  const _Toc({
    required this.chapters,
    required this.current,
    required this.counts,
    required this.query,
    required this.sections,
    required this.onOpen,
    required this.onSection,
  });

  final List<ManualChapter> chapters;
  final String current;
  final Map<String, int> counts;
  final String query;
  final List<(int, String)> sections;
  final ValueChanged<String> onOpen;
  final ValueChanged<int> onSection;

  @override
  Widget build(BuildContext context) {
    final sem = Sem.of(context);
    final cs = Theme.of(context).colorScheme;
    return ListView(padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8), children: [
      for (final c in chapters) ...[
        Material(
          color: c.id == current ? cs.primaryContainer : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () => onOpen(c.id),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
              child: Row(children: [
                SizedBox(
                  width: 26,
                  child: Text(c.number > 0 ? '${c.number}' : (c.number == 0 ? '•' : '◆'),
                      style: TextStyle(color: c.id == current ? cs.onPrimaryContainer : sem.muted, fontWeight: FontWeight.w800)),
                ),
                Expanded(
                  child: Text(c.title,
                      style: TextStyle(
                          fontWeight: c.id == current ? FontWeight.w800 : FontWeight.w500,
                          color: c.id == current ? cs.onPrimaryContainer : null,
                          height: 1.3)),
                ),
                if (query.isNotEmpty && (counts[c.id] ?? 0) > 0) Badge(label: Text('${counts[c.id]}')),
              ]),
            ),
          ),
        ),
        if (c.id == current && sections.isNotEmpty)
          Padding(
            padding: const EdgeInsetsDirectional.only(start: 30, top: 2, bottom: 6),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              for (final s in sections)
                InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => onSection(s.$1),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 8),
                    child: Text(s.$2, style: TextStyle(color: sem.muted, fontSize: 12.8, height: 1.3)),
                  ),
                ),
            ]),
          ),
      ],
    ]);
  }
}

// ---------------------------------------------------------------------
// عرض الكتل
// ---------------------------------------------------------------------
class ManualBlocks extends StatelessWidget {
  const ManualBlocks({super.key, required this.blocks, this.highlight = '', this.chapterNumber = 0, this.headingKeys});

  final List<MBlock> blocks;
  final String highlight;
  final int chapterNumber;
  final Map<int, GlobalKey>? headingKeys;

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (final (i, b) in blocks.indexed) _block(context, b, i),
    ]);
  }

  Widget _block(BuildContext context, MBlock b, int index) {
    final sem = Sem.of(context);
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    switch (b) {
      case MHeading():
        final key = headingKeys == null ? null : (headingKeys![index] ??= GlobalKey());
        if (b.level == 1) {
          return Padding(
            key: key,
            padding: const EdgeInsets.only(top: 8, bottom: 12),
            child: Row(children: [
              if (chapterNumber > 0) ...[
                Container(
                  width: 44,
                  height: 44,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: cs.primary, borderRadius: BorderRadius.circular(12)),
                  child: Text('$chapterNumber', style: TextStyle(color: cs.onPrimary, fontWeight: FontWeight.w900, fontSize: 18)),
                ),
                const SizedBox(width: 12),
              ],
              Expanded(child: _rich(context, b.text, t.headlineSmall?.copyWith(fontWeight: FontWeight.w800))),
            ]),
          );
        }
        return Padding(
          key: key,
          padding: EdgeInsets.only(top: b.level == 2 ? 22 : 14, bottom: 8),
          child: Row(children: [
            if (b.level == 2) Container(width: 4, height: 20, margin: const EdgeInsetsDirectional.only(end: 8), color: cs.primary),
            Expanded(
              child: _rich(context, b.text,
                  (b.level == 2 ? t.titleLarge : t.titleMedium)?.copyWith(fontWeight: FontWeight.w800, color: b.level == 2 ? null : sem.muted)),
            ),
          ]),
        );
      case MParagraph():
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: _rich(context, b.text, t.bodyLarge?.copyWith(height: 1.75)),
        );
      case MList():
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            for (final it in b.items)
              Padding(
                padding: EdgeInsetsDirectional.only(start: 4.0 + it.depth * 22, bottom: 5),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  SizedBox(
                    width: it.ordered ? 24 : 16,
                    child: Text(it.ordered ? '${it.number}.' : '•',
                        style: TextStyle(color: cs.primary, fontWeight: FontWeight.w800, height: 1.75)),
                  ),
                  Expanded(child: _rich(context, it.text, t.bodyLarge?.copyWith(height: 1.75))),
                ]),
              ),
          ]),
        );
      case MTable():
        return Padding(padding: const EdgeInsets.only(bottom: 14), child: _table(context, b));
      case MBox():
        final (color, icon) = switch (b.kind) {
          'formula' => (cs.primary, Icons.functions_rounded),
          'example' => (sem.ok, Icons.calculate_outlined),
          'warning' => (sem.danger, Icons.gpp_maybe_outlined),
          _ => (sem.wip, Icons.info_outline_rounded),
        };
        final label = switch (b.kind) { 'formula' => 'معادلة', 'example' => 'مثال محلول', 'warning' => 'تنبيه', _ => 'ملاحظة' };
        final title = b.title.isEmpty || b.title == label ? label : b.title;
        return Container(
          margin: const EdgeInsets.only(bottom: 14),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(12),
            border: BorderDirectional(start: BorderSide(color: color, width: 4)),
          ),
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Icon(icon, size: 19, color: color),
              const SizedBox(width: 6),
              Expanded(child: Text(title, style: TextStyle(fontWeight: FontWeight.w800, color: color))),
            ]),
            const SizedBox(height: 8),
            ManualBlocks(blocks: b.children, highlight: highlight),
          ]),
        );
      case MWidget():
        if (b.name == 'RISK_MATRIX') return const Padding(padding: EdgeInsets.only(bottom: 14), child: ManualRiskMatrix());
        return Text('{{${b.name}}}', style: TextStyle(color: sem.muted));
    }
  }

  Widget _rich(BuildContext context, String text, TextStyle? style) {
    final sem = Sem.of(context);
    final spans = <InlineSpan>[];
    final hl = highlight.trim();
    for (final (s, bold, italic, code) in parseInline(text)) {
      final st = TextStyle(
        fontWeight: bold ? FontWeight.w800 : null,
        fontStyle: italic ? FontStyle.italic : null,
        color: italic ? sem.muted : null,
        backgroundColor: code ? sem.surface2 : null,
      );
      if (hl.isEmpty) {
        spans.add(TextSpan(text: s, style: st));
        continue;
      }
      // تظليل مواضع البحث
      final lower = s.toLowerCase();
      final ql = hl.toLowerCase();
      var pos = 0;
      var i = lower.indexOf(ql);
      while (i >= 0) {
        if (i > pos) spans.add(TextSpan(text: s.substring(pos, i), style: st));
        spans.add(TextSpan(text: s.substring(i, i + hl.length), style: st.copyWith(backgroundColor: sem.wipSoft, color: sem.wip)));
        pos = i + hl.length;
        i = lower.indexOf(ql, pos);
      }
      if (pos < s.length) spans.add(TextSpan(text: s.substring(pos), style: st));
    }
    return Text.rich(TextSpan(style: style, children: spans));
  }

  Widget _table(BuildContext context, MTable tb) {
    final sem = Sem.of(context);
    final cols = tb.header.length;
    // عرض كل عمود حسب متوسط طول نصوصه، فتلتف النصوص الطويلة بدل أن تمتد
    final weights = <double>[
      for (var c = 0; c < cols; c++)
        ([for (final r in tb.rows) r[c].length, tb.header[c].length].fold<int>(0, (a, b) => a + b) / (tb.rows.length + 1))
            .clamp(4, 60)
            .toDouble(),
    ];
    // العمود القصير النصوص (كأسماء الصفحات) بعرض محتواه حتى لا تنكسر كلماته على الهاتف، والباقي يتقاسم العرض
    String plain(String x) => x.replaceAll(RegExp(r'[*`]'), '');
    final short = <bool>[
      for (var c = 0; c < cols; c++) [for (final r in tb.rows) plain(r[c]).length, plain(tb.header[c]).length].every((n) => n <= 18),
    ];
    final anyFlex = short.contains(false);
    return LayoutBuilder(builder: (context, c) {
      final minWidth = cols * 120.0;
      final width = c.maxWidth < minWidth ? minWidth : c.maxWidth;
      final table = Table(
        border: TableBorder.all(color: sem.rule, borderRadius: BorderRadius.circular(10)),
        columnWidths: {
          for (var i = 0; i < cols; i++) i: anyFlex && short[i] ? const IntrinsicColumnWidth() : FlexColumnWidth(weights[i]),
        },
        defaultVerticalAlignment: TableCellVerticalAlignment.middle,
        children: [
          if (!tb.headless)
            TableRow(
              decoration: BoxDecoration(color: sem.surface2),
              children: [
                for (final h in tb.header)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                    child: _rich(context, h, const TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5)),
                  ),
              ],
            ),
          for (final r in tb.rows)
            TableRow(
              // صفوف عناوين المراحل: خلية واحدة بنص عريض والباقي فارغ
              decoration: r.where((x) => x.isNotEmpty).length == 1 && r.any((x) => x.startsWith('**'))
                  ? BoxDecoration(color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.08))
                  : null,
              children: [
                for (final cell in r)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    child: _rich(context, cell, const TextStyle(fontSize: 13.5, height: 1.55)),
                  ),
              ],
            ),
        ],
      );
      if (width <= c.maxWidth) return table;
      return SingleChildScrollView(scrollDirection: Axis.horizontal, child: SizedBox(width: width, child: table));
    });
  }
}

/// مصفوفة المخاطر 5×5 بألوان المستويات الحالية.
class ManualRiskMatrix extends StatelessWidget {
  const ManualRiskMatrix({super.key});

  static const _p = {1: 'نادر', 2: 'غير مرجح', 3: 'ممكن', 4: 'مرجح', 5: 'شبه مؤكد'};
  static const _i = {1: 'ضئيل', 2: 'طفيف', 3: 'متوسط', 4: 'كبير', 5: 'جسيم'};
  static const _colors = [Color(0xFF2E7D4F), Color(0xFF7A9A2E), Color(0xFFC8901A), Color(0xFFD2601A), Color(0xFFB4232F)];

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final sem = Sem.of(context);
    final levels = app.riskConfig.levels;
    int lv(int score) {
      var k = 0;
      for (var j = 0; j < levels.length; j++) {
        if (score >= levels[j].min) k = j;
      }
      return (k * (_colors.length - 1) / (levels.length - 1 == 0 ? 1 : levels.length - 1)).round();
    }

    Widget lab(String a, String b) => Padding(
          padding: const EdgeInsets.all(4),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(a, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12)),
            Text(b, textAlign: TextAlign.center, style: TextStyle(color: sem.muted, fontSize: 11)),
          ]),
        );
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 520),
      child: Table(
        defaultVerticalAlignment: TableCellVerticalAlignment.middle,
        columnWidths: const {0: FlexColumnWidth(1.3)},
        children: [
          for (var p = 5; p >= 1; p--)
            TableRow(children: [
              lab('$p', _p[p]!),
              for (var i = 1; i <= 5; i++)
                Container(
                  margin: const EdgeInsets.all(2),
                  height: 40,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: _colors[lv(p * i)], borderRadius: BorderRadius.circular(6)),
                  child: Text('${p * i}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
                ),
            ]),
          TableRow(children: [
            lab('الاحتمالية ↑', 'التأثير ←'),
            for (var i = 1; i <= 5; i++) lab('$i', _i[i]!),
          ]),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------
// ما الجديد
// ---------------------------------------------------------------------
class WhatsNewPage extends StatefulWidget {
  const WhatsNewPage({super.key});

  @override
  State<WhatsNewPage> createState() => _WhatsNewPageState();
}

class _WhatsNewPageState extends State<WhatsNewPage> {
  Future<Map<String, String>>? _load;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _load ??= loadManualTexts();
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final sem = Sem.of(context);
    return FutureBuilder<Map<String, String>>(
      future: _load,
      builder: (context, snap) {
        final text = snap.data?['changelog'];
        if (text == null) return const SkeletonPage(cards: 2);
        return PageBody(maxWidth: 900, children: [
          Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
            ToneBadge('إصدارك الحالي: ${AppConfig.appVersion}', color: Theme.of(context).colorScheme.primary),
            if (app.latestRelease != null) ToneBadge('يتوفر ${app.latestRelease!.version}', color: sem.wip),
            TextButton.icon(onPressed: () => app.openManual(), icon: const Icon(Icons.menu_book_outlined), label: const Text('فتح الدليل')),
          ]),
          const SizedBox(height: 12),
          // القيم الحية ({{FORMS_COUNT}} وغيرها) تُعوَّض هنا كما في الدليل
          ManualBlocks(blocks: parseManual(applyManualValues(text, manualValues(app)))),
        ]);
      },
    );
  }
}
