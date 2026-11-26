import 'package:flutter/material.dart';

import '../app_state.dart';
import '../config.dart';
import '../manual.dart';
import '../models.dart';
import '../print/sources.dart';
import '../rasd.dart';
import '../registers.dart';
import '../ui/layout_catalog.dart';
import '../ui/motion.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';
import '../units.dart';
import 'finance.dart' show FinanceStats;
import 'hub_editor.dart';
import 'supervision.dart' show activeSiteProjects;

/// الأقسام الرئيسية للمنظومة: (المفتاح، الاسم، الوصف، الأيقونة)
const List<(String, String, String, IconData)> appSections = [
  ('cycle', 'الدورة المستندية', 'متابعة نماذج العقود ومراحلها الخمس، والمالية والمستخلصات، مع الدليل المرجعي للدورة.',
      Icons.account_tree_rounded),
  ('risks', 'المخاطر ومتابعة المشاريع',
      'البرنامج الزمني والتقدم الدوري ومؤشر SPI، والمخاطر ومراجعاتها، والمشاكل والتأخيرات والتغييرات، والدروس المستفادة وتقييم الشركات.',
      Icons.warning_amber_rounded),
  ('swot', 'تحليل SWOT', 'عوامل القوة والضعف والفرص والتهديدات، والتقييم المرجح، واستراتيجيات TOWS وخطة التنفيذ.',
      Icons.grid_view_rounded),
  ('docs', 'الشؤون الفنية',
      'المقايسات والمراسلات بصيغة PDF، والتصاميم بعرض صور متحرك ومسار تطوير كل مستند بإصداراته، واعتماد المواد.',
      Icons.folder_copy_rounded),
  ('supervision', 'الإشراف',
      'التقارير اليومية للمواقع: الأعمال المنفذة والعمالة والمعدات والمعوقات والسلامة، مع صور الموقع ومتابعة التغطية.',
      Icons.engineering_rounded),
  ('heritage', 'الترميم والمباني التاريخية',
      'سجل المباني التاريخية ببطاقة لكل مبنى وحالته الإنشائية وصوره، وتقييمات الحالة، وأعمال الترميم المرتبطة بالعقود.',
      Icons.museum_rounded),
  ('planning_qa', 'مكتب التخطيط وضمان الجودة',
      'قسم التخطيط بالخطط ونسب إنجازها، وقسم ضمان الجودة بالتدقيقات ونتائجها، وقسم المتابعة بالتكليفات ومواعيدها.',
      Icons.query_stats_rounded),
  ('safety', 'مكتب السلامة المهنية', 'جولات التفتيش ونسبة الالتزام، والحوادث وأيام العمل الضائعة، والمخالفات ومعالجتها في مواقع العقود.',
      Icons.health_and_safety_rounded),
  ('acceptance', 'المطابقة والاستلام',
      'وحدة الاستلام بمحاضر الاستلام وقوائم الملاحظات، ووحدة ضبط الجودة بالاختبارات ونسبة المطابقة وحالات عدم المطابقة.',
      Icons.verified_rounded),
  ('chat', 'المراسلات الداخلية',
      'محادثات خاصة بين الأشخاص، ومجموعات خاصة، وقنوات للأقسام: نصوص وأرقام وصور وفيديو وملفات وروابط للعقود، لحظياً.',
      Icons.forum_rounded),
  ('security', 'الأمن السيبراني',
      'لوحة شاملة لمسؤول الأمن: المؤشرات والتنبيهات والأنماط غير المعتادة، والهويات والصلاحيات، والجلسات والأجهزة، ونشاط البيانات والتدقيق والحوادث.',
      Icons.shield_rounded),
  ('print', 'الطباعة والتصدير',
      'استخراج أي سجل في المنظومة إلى PDF وWord وExcel وغيرها، ومصمم صفحة الطباعة بقوالبه، ومكتبة الصور والفيديو والملفات وتنزيلها.',
      Icons.print_rounded),
  ('manual', 'دليل الاستخدام', 'شرح كامل لكل أقسام المنظومة وإجراءاتها وطريقة كل حساب، ويُحدَّث مع كل إصدار جديد.',
      Icons.menu_book_rounded),
  ('stores', 'المخازن والأصول',
      'المخازن والأصناف وأرصدتها، والوارد والصرف والمرتجع والتحويل والتسوية باعتماد وترحيل، وسجل الموظفين، وما صُرف لكل موظف.',
      Icons.warehouse_rounded),
];

/// اسم مختصر للقسم في المبدّل الجانبي.
const Map<String, String> sectionShortNames = {
  'cycle': 'الدورة',
  'risks': 'المخاطر',
  'swot': 'SWOT',
  'docs': 'الفنية',
  'supervision': 'الإشراف',
  'heritage': 'الترميم',
  'planning_qa': 'التخطيط',
  'safety': 'السلامة',
  'acceptance': 'الاستلام',
  'chat': 'الرسائل',
  'security': 'الأمن',
  'print': 'الطباعة',
  'manual': 'الدليل',
  'stores': 'المخازن',
};

/// هل القسم متاح؟ (المخاطر وSWOT تحتاج الترحيل 15، والشؤون الفنية والإشراف الترحيل 20، وأقسام الوحدات الترحيل 21)
/// الطباعة والتصدير متاحة دائماً؛ قوالبها المحفوظة وسجلها تعمل بعد الترحيل 22.
bool sectionEnabled(AppState app, String key) => switch (key) {
      'cycle' || 'manual' || 'print' => true,
      'docs' || 'supervision' => app.v8Ready,
      'heritage' || 'planning_qa' || 'safety' || 'acceptance' => app.v9Ready,
      'chat' => app.v12Ready,
      'stores' => app.v22Ready || app.isDirector,
      'security' => app.v13Ready && app.canAudit,
      _ => app.v6Ready,
    };

/// هل يظهر القسم لهذا المستخدم؟ الأمن السيبراني لمسؤول الأمن والمدير وحدهما، والمخفي بقرار المدير لا يظهر لغيره.
bool sectionVisible(AppState app, String key, [UiLayout? layout]) {
  if (key == 'security') return app.canAudit;
  if (app.isDirector) return true;
  // عزل الأقسام (الترحيل 34): كل مستخدم يرى قسمه والأدوات المشتركة، ومكتب المدير كل الأقسام
  if (!app.seesSection(key)) return false;
  return !((layout ?? app.layout).sections[key]?.hidden ?? false);
}

/// الأقسام بعد تخصيص المدير (الترتيب والأسماء والأوصاف والأيقونات)، لمن يراها، مسطّحةً بترتيب المجموعات.
List<(String, String, String, IconData)> hubSections(AppState app) =>
    [for (final b in hubBlocks(app, app.layout)) ...b.$2];

/// كتل شاشة الدخول: كل مجموعة بأقسامها بترتيب المدير، ثم الأقسام دون مجموعة (عنوانها null إن لم تكن مجموعات).
/// [all] يعرض المخفي أيضاً (لمحرر المدير).
List<(LayoutGroup?, List<(String, String, String, IconData)>)> hubBlocks(AppState app, UiLayout l, {bool all = false}) {
  final list = [
    for (final s in appSections)
      if (all ? (s.$1 != 'security' || app.canAudit) : sectionVisible(app, s.$1, l))
        (
          s.$1,
          (l.sections[s.$1]?.name ?? '').trim().isNotEmpty ? l.sections[s.$1]!.name.trim() : s.$2,
          (l.sections[s.$1]?.desc ?? '').trim().isNotEmpty ? l.sections[s.$1]!.desc.trim() : s.$3,
          layoutIcons[l.sections[s.$1]?.icon ?? ''] ?? s.$4,
        ),
  ];
  final ordered = UiLayout.ordered(list, l.sectionOrder, (s) => s.$1);
  if (l.groups.isEmpty) return [(null, ordered)];
  final known = {for (final g in l.groups) g.key};
  String groupOf(String k) {
    final g = l.sections[k]?.group ?? '';
    return known.contains(g) ? g : '';
  }

  final out = <(LayoutGroup?, List<(String, String, String, IconData)>)>[
    for (final g in l.groups) (g, [for (final s in ordered) if (groupOf(s.$1) == g.key) s]),
  ];
  final rest = [for (final s in ordered) if (groupOf(s.$1).isEmpty) s];
  if (rest.isNotEmpty || all) out.add((const LayoutGroup('', 'أقسام أخرى'), rest));
  return [for (final b in out) if (all || b.$2.isNotEmpty) b];
}

/// اسم القسم بعد تخصيص المدير.
String sectionTitle(AppState app, String key) {
  final n = (app.layout.sections[key]?.name ?? '').trim();
  return n.isNotEmpty ? n : sectionName(key);
}

String sectionName(String key) => appSections.firstWhere((s) => s.$1 == key, orElse: () => appSections.first).$2;

/// أيقونة القسم؛ وبعد تخصيص المدير إن مُرّرت الحالة.
IconData sectionIcon(String key, [AppState? app]) =>
    layoutIcons[app?.layout.sections[key]?.icon ?? ''] ??
    appSections.firstWhere((s) => s.$1 == key, orElse: () => appSections.first).$4;

/// لون القسم: ما اختاره المدير، وإلا اللون المميز للقسم (يتكيف مع الوضع الفاتح والداكن).
Color sectionColor(BuildContext context, String key, [UiLayout? layout]) {
  final l = layout ?? AppScope.maybeRead(context)?.layout;
  return layoutColor(context, l?.sections[key]?.color ?? '') ?? defaultSectionColor(context, key);
}

/// اللون الافتراضي لكل قسم.
Color defaultSectionColor(BuildContext context, String key) {
  final dark = Theme.of(context).brightness == Brightness.dark;
  return switch (key) {
    'risks' => dark ? const Color(0xFFF2D04B) : const Color(0xFF9C7C00),
    'swot' => dark ? const Color(0xFF7FB2F0) : const Color(0xFF2B62A8),
    'docs' => dark ? const Color(0xFF5EC4B6) : const Color(0xFF0F766E),
    'supervision' => dark ? const Color(0xFFB39DFF) : const Color(0xFF6D3FB2),
    'manual' => dark ? const Color(0xFFB8C2CE) : const Color(0xFF4F5B69),
    'heritage' => dark ? const Color(0xFFD9A066) : const Color(0xFF8A5A2B),
    'planning_qa' => dark ? const Color(0xFF9FA8FF) : const Color(0xFF3949AB),
    'safety' => dark ? const Color(0xFFF2726F) : const Color(0xFFC62828),
    'acceptance' => dark ? const Color(0xFF6FCF8E) : const Color(0xFF2E7D32),
    'print' => dark ? const Color(0xFF7FC8E8) : const Color(0xFF0B6E99),
    'chat' => dark ? const Color(0xFF6FD0C8) : const Color(0xFF00796B),
    'security' => dark ? const Color(0xFFFF8A80) : const Color(0xFFB71C1C),
    'stores' => dark ? const Color(0xFFE0B26B) : const Color(0xFF8D5B12),
    _ => Theme.of(context).colorScheme.primary,
  };
}

/// شاشة الدخول: الأقسام الرئيسية كقوائم منفصلة، ولكل قسم مؤشرات حية مختصرة.
/// وللمدير «تخصيص الواجهة»: ترتيب البطاقات بالسحب، ومجموعات بعناوين، ونمط العرض، واسم كل قسم ووصفه وأيقونته
/// ولونه وصفحاته (الفصل 31).
class SectionHub extends StatefulWidget {
  const SectionHub({super.key, this.pagesOf});

  /// صفحات كل قسم لمحرر الصفحات (من هيكل التطبيق).
  final LayoutPagesFn? pagesOf;

  @override
  State<SectionHub> createState() => _SectionHubState();
}

class _SectionHubState extends State<SectionHub> {
  HubDraft? _draft;
  bool _busy = false;

  List<String> get _defaultOrder => [for (final s in appSections) s.$1];

  void _startEdit(AppState app) => setState(() => _draft = HubDraft.from(app.layout, _defaultOrder));

  Future<void> _save(AppState app, UiLayout l) async {
    setState(() => _busy = true);
    try {
      await app.saveLayout(l);
      if (!mounted) return;
      setState(() => _draft = null);
      showToast(context, l.isEmpty ? 'عادت الواجهة إلى الافتراضي' : 'حُفظ تخصيص الواجهة، ويسري على الجميع الآن');
    } catch (e) {
      if (mounted) showToast(context, friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final sem = Sem.of(context);
    final t = Theme.of(context).textTheme;
    if (!app.loadedOnce) return const SkeletonPage(cards: 6);
    if (app.hubEditRequested) {
      app.hubEditRequested = false;
      if (app.isDirector && _draft == null) _draft = HubDraft.from(app.layout, _defaultOrder);
    }
    final draft = app.isDirector ? _draft : null;
    final editing = draft != null;
    final layout = draft?.toLayout() ?? app.layout;
    final style = layout.style;
    final blocks = hubBlocks(app, layout, all: editing);
    final first = (app.me?.displayName ?? '').split(' ').where((w) => w.isNotEmpty).take(2).join(' ');
    void changed() => setState(() {});

    Widget tileOf((String, String, String, IconData) s) {
      final color = sectionColor(context, s.$1, layout);
      final tile = switch (style) {
        'compact' => _CompactCard(app: app, section: s, color: color, showIdeas: !editing),
        'icons' => _IconTile(app: app, section: s, color: color, showIdeas: !editing),
        _ => _SectionCard(app: app, section: s, color: color, showIdeas: !editing),
      };
      final d = draft;
      if (d == null) return KeyedSubtree(key: ValueKey('hub-${s.$1}'), child: tile);
      final base = appSections.firstWhere((x) => x.$1 == s.$1);
      return EditableHubTile(
        key: ValueKey('edit-${s.$1}'),
        sectionKey: s.$1,
        title: s.$2,
        icon: s.$4,
        color: color,
        hidden: d.sec(s.$1).hidden,
        canHide: s.$1 != 'security',
        child: tile,
        onDrop: (dragged) {
          d.moveBefore(dragged, s.$1);
          changed();
        },
        onToggleHidden: () {
          d.setSec(s.$1, d.sec(s.$1).copyWith(hidden: !d.sec(s.$1).hidden));
          changed();
        },
        onEdit: () => showSectionEditor(context,
            app: app,
            draft: d,
            sectionKey: s.$1,
            defaultName: base.$2,
            defaultDesc: base.$3,
            defaultIcon: base.$4,
            defaultColor: defaultSectionColor(context, s.$1),
            pagesOf: widget.pagesOf,
            onChanged: changed),
      );
    }

    final minWidth = switch (style) { 'compact' => 250.0, 'icons' => 150.0, _ => 330.0 };
    final header = <Widget>[
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(first.isEmpty ? 'مرحباً' : 'مرحباً، $first', style: t.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
            ),
            Text('اختر القسم الذي تعمل عليه. لكل قسم قائمته الخاصة، وتعود إلى هذه الشاشة من زر «الأقسام» في أعلى الصفحة.',
                style: t.bodyMedium?.copyWith(color: sem.muted)),
          ]),
        ),
        if (app.isDirector && !editing && app.v11Ready) ...[
          const SizedBox(width: 12),
          OutlinedButton.icon(
            onPressed: () => _startEdit(app),
            icon: const Icon(Icons.dashboard_customize_outlined, size: 18),
            label: const Text('تخصيص الواجهة'),
          ),
        ],
      ]),
      const SizedBox(height: 20),
    ];

    final body = <Widget>[
      if (draft != null) ...[
        HubEditBar(
          draft: draft,
          busy: _busy,
          onChanged: changed,
          onSave: () => _save(app, draft.toLayout()),
          onCancel: () => setState(() => _draft = null),
          onReset: () async {
            final ok = await confirmDialog(context,
                title: 'العودة إلى الافتراضي',
                message: 'تعود الأقسام وصفحاتها إلى أسمائها وأيقوناتها وألوانها وترتيبها الأصلي، وتُحذف المجموعات، '
                    'وتعود الصفحات المنقولة إلى أقسامها، ويظهر المخفي للجميع.',
                confirmLabel: 'العودة إلى الافتراضي',
                danger: true);
            if (ok) await _save(app, UiLayout.empty);
          },
        ),
        const SizedBox(height: 8),
      ],
      for (final b in blocks) ...[
        if (b.$1 != null) HubGroupHeading(group: b.$1!, draft: draft, onChanged: changed, count: b.$2.length),
        if (draft != null && b.$2.isEmpty)
          HubEmptyDrop(draft: draft, group: b.$1?.key ?? '', onChanged: changed)
        else
          ResponsiveGrid(minItemWidth: minWidth, spacing: style == 'icons' ? 10 : 14, children: [for (final s in b.$2) tileOf(s)]),
      ],
      if (!app.v6Ready)
        const Padding(
          padding: EdgeInsets.only(top: 16),
          child: InfoBanner(
            text: 'سجل المخاطر وتحليل SWOT يعملان بعد تحديث قاعدة البيانات بالملف 20261109000015_risks_swot.sql.',
            level: 'warning',
          ),
        ),
      if (app.v8Ready && !app.v9Ready)
        const Padding(
          padding: EdgeInsets.only(top: 16),
          child: InfoBanner(
            text: 'أقسام الترميم والتخطيط وضمان الجودة والسلامة المهنية والمطابقة والاستلام تعمل بعد تحديث قاعدة البيانات '
                'بالملف 20261114000021_unit_sections.sql.',
            level: 'warning',
          ),
        ),
      if (app.v6Ready && !app.v8Ready)
        const Padding(
          padding: EdgeInsets.only(top: 16),
          child: InfoBanner(
            text: 'الشؤون الفنية والإشراف يعملان بعد تحديث قاعدة البيانات بالملف 20261114000020_documents_supervision.sql.',
            level: 'warning',
          ),
        ),
    ];

    return PageBody(
      maxWidth: 1180,
      onRefresh: editing ? null : app.loadAll,
      children: editing ? [...header, ...body] : staggered([...header, ...body], stepMs: 70),
    );
  }
}

/// شارة الأفكار المفتوحة للقسم (للمدير): تفتح «الأفكار والتطوير» على القسم.
class _IdeasChip extends StatelessWidget {
  const _IdeasChip({required this.app, required this.sectionKey, this.compact = false});

  final AppState app;
  final String sectionKey;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (!app.isDirector || !app.v18Ready) return const SizedBox.shrink();
    final n = app.openIdeas(sectionKey).length;
    if (n == 0) return const SizedBox.shrink();
    final fresh = app.newIdeasIn(sectionKey);
    final cs = Theme.of(context).colorScheme;
    return Tooltip(
      message: fresh > 0 ? '$n فكرة مفتوحة لتطوير القسم، منها $fresh جديدة' : '$n فكرة مفتوحة لتطوير القسم',
      child: Material(
        color: cs.tertiaryContainer,
        borderRadius: BorderRadius.circular(99),
        child: InkWell(
          borderRadius: BorderRadius.circular(99),
          onTap: () => app.openIdeasFor(sectionKey),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: compact ? 6 : 9, vertical: 3),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.lightbulb_rounded, size: 14, color: cs.onTertiaryContainer),
              const SizedBox(width: 3),
              Text('$n', style: TextStyle(color: cs.onTertiaryContainer, fontWeight: FontWeight.w800, fontSize: 12)),
            ]),
          ),
        ),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.app, required this.section, required this.color, this.showIdeas = true});

  final AppState app;
  final (String, String, String, IconData) section;
  final Color color;
  final bool showIdeas;

  @override
  Widget build(BuildContext context) {
    final sem = Sem.of(context);
    final t = Theme.of(context).textTheme;
    final enabled = sectionEnabled(app, section.$1);
    final stats = hubStats(context, app, section.$1);
    final radius = BorderRadius.circular(appearance.radius.clamp(12, 24).toDouble());
    return HoverLift(
      child: Material(
        color: cardColor(context),
        shape: RoundedRectangleBorder(borderRadius: radius, side: BorderSide(color: sem.rule)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: enabled ? () => app.openSection(section.$1) : null,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(height: 5, color: color),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(children: [
                      // شارة الأفكار على زاوية الأيقونة حتى لا تضيّق اسم القسم
                      Stack(clipBehavior: Clip.none, children: [
                        Container(
                          width: 52,
                          height: 52,
                          decoration: BoxDecoration(color: color.withValues(alpha: 0.13), borderRadius: BorderRadius.circular(15)),
                          child: Icon(section.$4, color: color, size: 28),
                        ),
                        if (showIdeas) PositionedDirectional(top: -6, end: -8, child: _IdeasChip(app: app, sectionKey: section.$1, compact: true)),
                      ]),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Text(section.$2, style: t.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                      ),
                      Icon(Icons.chevron_left_rounded, color: enabled ? color : sem.muted),
                    ]),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 44,
                      child: Text(section.$3,
                          maxLines: 2, overflow: TextOverflow.ellipsis, style: t.bodyMedium?.copyWith(color: sem.muted, height: 1.35)),
                    ),
                    const SizedBox(height: 14),
                    if (stats.isEmpty)
                      SizedBox(
                        height: 58,
                        child: Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: Text('بانتظار تحديث قاعدة البيانات', style: TextStyle(color: sem.muted)),
                        ),
                      )
                    else
                      Row(children: [
                        for (var i = 0; i < stats.length; i++) ...[
                          if (i > 0) const SizedBox(width: 8),
                          Expanded(
                            child: Container(
                              constraints: const BoxConstraints(minHeight: 58),
                              alignment: AlignmentDirectional.centerStart,
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                              decoration: BoxDecoration(color: sem.surface2, borderRadius: BorderRadius.circular(12)),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  FittedBox(
                                    fit: BoxFit.scaleDown,
                                    alignment: AlignmentDirectional.centerStart,
                                    child: Text(stats[i].$1,
                                        style: TextStyle(
                                            fontWeight: FontWeight.w800,
                                            fontSize: 18,
                                            color: stats[i].$3,
                                            fontFeatures: const [FontFeature.tabularFigures()])),
                                  ),
                                  Text(stats[i].$2,
                                      maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: sem.muted, fontSize: 11.5)),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ]),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// بطاقة مدمجة: الأيقونة والاسم وأهم مؤشر.
class _CompactCard extends StatelessWidget {
  const _CompactCard({required this.app, required this.section, required this.color, this.showIdeas = true});

  final AppState app;
  final (String, String, String, IconData) section;
  final Color color;
  final bool showIdeas;

  @override
  Widget build(BuildContext context) {
    final sem = Sem.of(context);
    final t = Theme.of(context).textTheme;
    final enabled = sectionEnabled(app, section.$1);
    final stats = hubStats(context, app, section.$1);
    final radius = BorderRadius.circular(appearance.radius.clamp(12, 22).toDouble());
    return HoverLift(
      child: Material(
        color: cardColor(context),
        shape: RoundedRectangleBorder(borderRadius: radius, side: BorderSide(color: sem.rule)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: enabled ? () => app.openSection(section.$1) : null,
          child: Container(
            height: 92,
            decoration: BoxDecoration(border: BorderDirectional(start: BorderSide(color: color, width: 5))),
            padding: const EdgeInsetsDirectional.fromSTEB(14, 12, 12, 12),
            child: Row(children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(color: color.withValues(alpha: 0.13), borderRadius: BorderRadius.circular(13)),
                child: Icon(section.$4, color: color, size: 25),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(section.$2, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 3),
                  if (stats.isEmpty)
                    Text('بانتظار تحديث قاعدة البيانات', style: TextStyle(color: sem.muted, fontSize: 12))
                  else
                    Text.rich(
                      TextSpan(children: [
                        TextSpan(text: stats.first.$1, style: TextStyle(fontWeight: FontWeight.w800, color: stats.first.$3 ?? color)),
                        TextSpan(text: ' ${stats.first.$2}'),
                      ]),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: sem.muted, fontSize: 12.5),
                    ),
                ]),
              ),
              if (showIdeas) _IdeasChip(app: app, sectionKey: section.$1, compact: true),
              Icon(Icons.chevron_left_rounded, color: enabled ? color : sem.muted),
            ]),
          ),
        ),
      ),
    );
  }
}

/// أيقونة القسم واسمه، كشاشة تطبيقات.
class _IconTile extends StatelessWidget {
  const _IconTile({required this.app, required this.section, required this.color, this.showIdeas = true});

  final AppState app;
  final (String, String, String, IconData) section;
  final Color color;
  final bool showIdeas;

  @override
  Widget build(BuildContext context) {
    final sem = Sem.of(context);
    final enabled = sectionEnabled(app, section.$1);
    return HoverLift(
      radius: 20,
      child: Material(
        color: cardColor(context),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: BorderSide(color: sem.rule)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: enabled ? () => app.openSection(section.$1) : null,
          child: SizedBox(
            height: 148,
            child: Stack(children: [
              Center(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(10, 14, 10, 10),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Container(
                      width: 62,
                      height: 62,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: AlignmentDirectional.topStart,
                          end: AlignmentDirectional.bottomEnd,
                          colors: [color.withValues(alpha: enabled ? 0.95 : 0.35), color.withValues(alpha: enabled ? 0.7 : 0.25)],
                        ),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Icon(section.$4, color: Colors.white, size: 32),
                    ),
                    const SizedBox(height: 10),
                    Text(section.$2,
                        maxLines: 2,
                        textAlign: TextAlign.center,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontWeight: FontWeight.w700, height: 1.3, color: enabled ? null : sem.muted)),
                  ]),
                ),
              ),
              if (showIdeas) PositionedDirectional(top: 8, start: 8, child: _IdeasChip(app: app, sectionKey: section.$1, compact: true)),
            ]),
          ),
        ),
      ),
    );
  }
}

/// المؤشرات الحية المختصرة لكل قسم في شاشة الدخول: (القيمة، الوصف، اللون).
List<(String, String, Color?)> hubStats(BuildContext context, AppState app, String key) {
  final sem = Sem.of(context);
  switch (key) {
    case 'risks':
      if (!app.v6Ready) return const [];
      if (app.v7Ready) {
        final pm = app.pm;
        final late = pm.tracks.values.where((t) => t.isLate).length;
        final alerts = pm.alerts.where((a) => a.count > 0).length;
        return [
          ('$late', 'مشروع متأخر', late > 0 ? sem.danger : null),
          ('${pm.highRisksNow}', 'خطر مرتفع حالياً', pm.highRisksNow > 0 ? sem.danger : null),
          ('$alerts', 'تنبيه متابعة', alerts > 0 ? sem.wip : null),
        ];
      }
      final st = RiskStats(app.risks, app.riskConfig);
      final overdue = st.byFollowUp['overdue'] ?? 0;
      return [
        ('${st.total}', 'خطراً مسجلاً', null),
        ('${st.risks.where((r) => !r.isClosed && app.riskConfig.isHigh(r.score)).length}', 'مرتفعة نشطة', sem.danger),
        ('$overdue', 'مراجعة متأخرة', overdue > 0 ? sem.wip : null),
      ];
    case 'docs':
      if (!app.v8Ready) return const [];
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final letters = app.docs.ofKind('letter');
      final open = letters.where((l) => l.status == 'open').length;
      final late = letters.where((l) => l.overdue(today)).length;
      final mats = app.v9Ready ? UnitStats(app.units, today).materialsUnderReview : 0;
      return [
        ('${app.docs.ofKind('boq').length}', 'مقايسة', null),
        ('$open', late > 0 ? 'مراسلة ($late متأخرة)' : 'مراسلة بانتظار رد', late > 0 ? sem.danger : (open > 0 ? sem.wip : null)),
        if (app.v9Ready)
          ('$mats', 'مادة قيد الاعتماد', mats > 0 ? sem.wip : null)
        else
          ('${app.docs.ofKind('design').length}', 'تصميماً', null),
      ];
    case 'supervision':
      if (!app.v8Ready) return const [];
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final active = activeSiteProjects(app);
      final reps = app.docs.reports;
      final todayN = reps.where((r) => r.reportDate == today && active.contains(r.projectId)).map((r) => r.projectId).toSet().length;
      final week = reps.where((r) => !r.reportDate.isBefore(today.subtract(const Duration(days: 6)))).length;
      final unreviewed = reps.where((r) => !r.reviewed).length;
      return [
        ('$todayN/${active.length}', 'تقارير اليوم', todayN < active.length ? sem.wip : sem.ok),
        ('$week', 'تقريراً هذا الأسبوع', null),
        if (app.isDirector)
          ('$unreviewed', 'بانتظار اطلاعك', unreviewed > 0 ? sem.wip : null)
        else
          ('${reps.where((r) => r.hasIssues && !r.reportDate.isBefore(today.subtract(const Duration(days: 6)))).length}', 'بمعوقات', sem.danger),
      ];
    case 'heritage':
      if (!app.v9Ready) return const [];
      final s = UnitStats(app.units, DateTime.now());
      return [
        ('${s.buildings}', 'مبنى مسجّلاً', null),
        ('${s.buildingsAtRisk}', 'بحالة سيئة أو خطرة', s.buildingsAtRisk > 0 ? sem.danger : null),
        ('${s.underRestoration}', 'قيد الترميم', s.underRestoration > 0 ? sem.wip : null),
      ];
    case 'planning_qa':
      if (!app.v9Ready) return const [];
      final s = UnitStats(app.units, DateTime.now());
      return [
        ('${s.activePlans}', 'خطة قيد التنفيذ', null),
        ('${s.auditsThisYear}', 'تدقيقاً هذا العام', null),
        ('${s.overdueTasks}', 'تكليف متأخر', s.overdueTasks > 0 ? sem.wip : null),
      ];
    case 'safety':
      if (!app.v9Ready) return const [];
      final s = UnitStats(app.units, DateTime.now());
      return [
        (s.daysWithoutIncident?.toString() ?? '—', 'يوماً بلا حوادث', sem.ok),
        ('${s.openViolations}', 'مخالفة قائمة', s.openViolations > 0 ? sem.danger : null),
        ('${s.inspectionsThisMonth}', 'جولة هذا الشهر', null),
      ];
    case 'acceptance':
      if (!app.v9Ready) return const [];
      final s = UnitStats(app.units, DateTime.now());
      return [
        ('${s.openPunch}', 'ملاحظة استلام قائمة', s.openPunch > 0 ? sem.wip : null),
        ('${s.pendingTests}', 'اختبار بانتظار النتيجة', null),
        ('${s.openNcr}', 'عدم مطابقة مفتوحة', s.openNcr > 0 ? sem.danger : null),
      ];
    case 'chat':
      if (!app.v12Ready) return const [];
      final c = app.chat;
      return [
        ('${c.unreadTotal}', 'رسائل غير مقروءة', c.unreadTotal > 0 ? Theme.of(context).colorScheme.primary : null),
        ('${c.rooms.where((r) => r.isGroup || r.isChannel).length}', 'مجموعات وقنوات', null),
        ('${c.rooms.where((r) => r.isDm).length}', 'محادثات خاصة', null),
      ];
    case 'security':
      if (!app.v13Ready) return const [];
      final locked = app.people.values.where((p) => p.locked).length;
      return [
        (app.settings.frozen ? 'مجمّدة' : 'تعمل', 'حالة المنظومة', app.settings.frozen ? sem.danger : sem.ok),
        ('${app.people.values.where((p) => p.active && p.role != null).length}', 'حسابات مفعّلة', null),
        ('$locked', 'حسابات مقفلة', locked > 0 ? sem.wip : null),
      ];
    case 'print':
      final media = app.v8Ready ? app.docs.files.where((f) => f.isImage || f.isVideo).length : 0;
      return [
        ('${exportSources(app).length}', 'سجلاً قابلاً للتصدير', null),
        ('${app.printTemplates.length}', 'قالب طباعة', null),
        ('$media', 'صورة وفيديو', null),
      ];
    case 'stores':
      if (!app.v22Ready) return const [];
      final st = app.stores;
      if (!app.storesStaff) {
        final me = app.myEmployee;
        final n = me == null
            ? 0
            : st.docsOfEmployee(me.id).where((d) => d.isPosted && d.kind == 'issue' && !d.isReversal && d.confirmedAt == null).length;
        return [('$n', 'بانتظار تأكيد استلامك', n > 0 ? sem.wip : null)];
      }
      final low = st.lowStock().length;
      return [
        ('${st.activeItems}', 'صنفاً نشطاً', null),
        ('$low', 'يحتاج توريداً', low > 0 ? sem.wip : null),
        ('${st.pendingApproval}', 'بانتظار الاعتماد', st.pendingApproval > 0 ? sem.wip : null),
      ];
    case 'manual':
      return [
        ('${manualChaptersFor(app.seesSection).length}', 'فصلاً', null),
        (AppConfig.appVersion, 'إصدار الدليل', Theme.of(context).colorScheme.primary),
        if (!app.isolated) ('PDF', 'نسخة للطباعة', null),
      ];
    case 'swot':
      if (!app.v6Ready) return const [];
      final a = app.swot;
      final avg = a.avgProgress;
      return [
        ('${a.factors.length}', 'عاملاً', null),
        (avg == null ? '—' : pctText(avg), 'إنجاز الخطة', sem.ok),
        ('${a.alerts.length}', 'تنبيه متابعة', a.alerts.isNotEmpty ? sem.wip : null),
      ];
    default:
      final list = app.scoped;
      final avg = list.isEmpty ? 0.0 : list.fold<double>(0, (s, p) => s + app.progressOf(p).pct) / list.length;
      final fs = FinanceStats(app, list);
      return [
        ('${list.length}', term('contracts'), null),
        (pctText(avg), 'إنجاز الدورة', Theme.of(context).colorScheme.primary),
        ('${fs.referredCount}', 'محال للصرف', fs.referredCount > 0 ? sem.wip : null),
      ];
  }
}

/// مبدّل الأقسام في الشريط الجانبي.
class SectionSwitcher extends StatelessWidget {
  const SectionSwitcher({super.key, required this.app});

  final AppState app;

  @override
  Widget build(BuildContext context) {
    final sem = Sem.of(context);
    Widget item((String, String, String, IconData) s) => Expanded(
          child: Tooltip(
            message: s.$2,
            child: _SwitchItem(
              label: (app.layout.sections[s.$1]?.name ?? '').trim().isNotEmpty ? s.$2 : (sectionShortNames[s.$1] ?? s.$2),
              icon: s.$4,
              color: sectionColor(context, s.$1),
              selected: app.section == s.$1,
              enabled: sectionEnabled(app, s.$1),
              onTap: () => app.openSection(s.$1),
            ),
          ),
        );
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: sem.surface2, borderRadius: BorderRadius.circular(14), border: Border.all(color: sem.rule)),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        for (final row in [
          for (var i = 0; i < hubSections(app).length; i += 5) hubSections(app).skip(i).take(5).toList(),
        ])
          Row(children: [
            for (final s in row) item(s),
            for (var k = row.length; k < 5; k++) const Expanded(child: SizedBox()),
          ]),
      ]),
    );
  }
}

class _SwitchItem extends StatelessWidget {
  const _SwitchItem({
    required this.label,
    required this.icon,
    required this.color,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final Color color;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final sem = Sem.of(context);
    return AnimatedContainer(
      duration: Motion.of(context, 220),
      decoration: BoxDecoration(
        color: selected ? color.withValues(alpha: 0.16) : Colors.transparent,
        borderRadius: BorderRadius.circular(11),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(11),
          onTap: enabled && !selected ? onTap : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(icon, size: 20, color: selected ? color : (enabled ? sem.muted : sem.rule)),
              const SizedBox(height: 3),
              Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 11, fontWeight: selected ? FontWeight.w800 : FontWeight.w500, color: selected ? color : sem.muted)),
            ]),
          ),
        ),
      ),
    );
  }
}
