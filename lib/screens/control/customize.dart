import 'package:flutter/material.dart';

import '../../app_state.dart';
import '../../models.dart';
import '../../ui/motion.dart';
import '../../ui/theme.dart';
import '../../ui/widgets.dart';
import '../dashboard.dart';
import '../home_shell.dart';
import 'control_panel.dart';

/// التخصيص والتطوير (للمدير وحده): الحركة، والقائمة، وأقسام الرئيسية، والمصطلحات، ومساعد Claude.
/// كل ما هنا إعدادات حية تسري فوراً على كل الأجهزة، وتُحفظ في سجل التدقيق.
class CustomizeSection extends StatefulWidget {
  const CustomizeSection({super.key});

  @override
  State<CustomizeSection> createState() => _CustomizeSectionState();
}

class _CustomizeSectionState extends State<CustomizeSection> {
  bool _loaded = false;
  bool _busy = false;
  int _demo = 0;

  // القائمة: المفتاح، ظاهر للموظفين، الاسم المخصص
  List<(String, bool, String)> _nav = [];
  // أقسام الرئيسية: المفتاح، ظاهر
  List<(String, bool)> _dash = [];
  final Map<String, TextEditingController> _terms = {for (final k in defaultTerms.keys) k: TextEditingController()};
  final _instructions = TextEditingController();

  static const _models = <(String, String, String)>[
    ('claude-sonnet-5-5', 'Claude Sonnet 5.5', 'متوازن بين الدقة والسرعة والتكلفة (موصى به)'),
    ('claude-opus-5-5', 'Claude Opus 5.5', 'الأقوى للتحليل العميق والتقارير المطولة'),
    ('claude-haiku-5-5', 'Claude Haiku 5.5', 'الأسرع والأقل تكلفة للأسئلة القصيرة'),
  ];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loaded) return;
    _loaded = true;
    _reset(AppScope.of(context));
  }

  void _reset(AppState app) {
    final s = app.settings;
    final hidden = s.navHidden.toSet();
    final labels = s.navLabels;
    final order = s.navOrder;
    final nav = [for (final c in navCatalog) (c.$1, !hidden.contains(c.$1), labels[c.$1] ?? '')];
    if (order.isNotEmpty) {
      int rank(String k) {
        final i = order.indexOf(k);
        return i < 0 ? 100 + navCatalog.indexWhere((c) => c.$1 == k) : i;
      }

      nav.sort((a, b) => rank(a.$1).compareTo(rank(b.$1)));
    }
    _nav = nav;

    final conf = s.dashboardSections;
    final dash = <(String, bool)>[];
    for (final c in conf) {
      if (dashboardCatalog.any((v) => v.$1 == c.$1) && !dash.any((d) => d.$1 == c.$1)) dash.add((c.$1, c.$2 || c.$1 == 'overview'));
    }
    for (final v in dashboardCatalog) {
      if (!dash.any((d) => d.$1 == v.$1)) dash.add((v.$1, true));
    }
    _dash = dash;

    final terms = s.terms;
    for (final e in _terms.entries) {
      e.value.text = terms[e.key] ?? '';
    }
    _instructions.text = s.aiInstructions;
  }

  @override
  void dispose() {
    for (final c in _terms.values) {
      c.dispose();
    }
    _instructions.dispose();
    super.dispose();
  }

  Future<void> _save(String key, Object? value, String ok) async {
    setState(() => _busy = true);
    await runAction(context, () => AppScope.read(context).setSetting(key, value), success: ok);
    if (mounted) setState(() => _busy = false);
  }

  void _move<T>(List<T> list, int i, int delta) {
    final j = i + delta;
    if (j < 0 || j >= list.length) return;
    setState(() {
      final x = list.removeAt(i);
      list.insert(j, x);
    });
  }

  String _navDefault(String key) => switch (key) {
        'projects' => term('contracts'),
        _ => navCatalog.firstWhere((c) => c.$1 == key).$2,
      };

  IconData _navIcon(String key) => navCatalog.firstWhere((c) => c.$1 == key).$3;

  Future<void> _renameNav(int i) async {
    final it = _nav[i];
    final v = await textInputDialog(
      context,
      title: 'اسم الصفحة في القائمة',
      message: 'الاسم الافتراضي: ${_navDefault(it.$1)}. اتركه فارغاً للعودة إليه.',
      label: 'الاسم',
      confirmLabel: 'تطبيق',
      initial: it.$3,
      multiline: false,
    );
    if (v == null) return;
    setState(() => _nav[i] = (it.$1, it.$2, v.trim().length > 40 ? v.trim().substring(0, 40) : v.trim()));
  }

  Map<String, dynamic> get _navValue => {
        'hidden': [for (final n in _nav) if (!n.$2 && n.$1 != 'home') n.$1],
        'order': [for (final n in _nav) n.$1],
        'labels': {for (final n in _nav) if (n.$3.isNotEmpty) n.$1: n.$3},
      };

  Map<String, dynamic> get _dashValue => {
        'sections': [for (final d in _dash) {'key': d.$1, 'on': d.$2 || d.$1 == 'overview'}],
      };

  Future<void> _customModel(String current) async {
    final v = await textInputDialog(
      context,
      title: 'نموذج آخر',
      message: 'اكتب معرّف النموذج كما في وثائق Anthropic (حروف إنجليزية صغيرة وأرقام وشرطات).',
      label: 'معرّف النموذج',
      confirmLabel: 'حفظ',
      initial: current,
      multiline: false,
      required: true,
      textDirection: TextDirection.ltr,
    );
    if (v == null) return;
    final id = v.trim().toLowerCase();
    if (!RegExp(r'^[a-z0-9][a-z0-9.\-]{2,60}$').hasMatch(id)) {
      if (mounted) showToast(context, 'معرّف غير صالح', error: true);
      return;
    }
    await _save('ai.model', id, 'سيستخدم المساعد $id');
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final sem = Sem.of(context);
    final cs = Theme.of(context).colorScheme;
    final s = app.settings;

    if (!app.isDirector) {
      return const Center(child: EmptyState(icon: Icons.lock_outline, title: 'التخصيص والتطوير لمدير المكتب وحده'));
    }

    return PageBody(
      onRefresh: app.loadAll,
      children: [
        PageHeader(
          icon: Icons.auto_fix_high_outlined,
          title: 'التخصيص والتطوير',
          subtitle: 'شكّل المنظومة من داخلها: الحركة، والقائمة، وأقسام الرئيسية، والمصطلحات، ومساعد Claude. '
              'تسري التغييرات فوراً على كل الأجهزة، وتُسجَّل في سجل التدقيق.',
          actions: [if (_busy) const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))],
        ),
        if (!app.v3Ready) ...[
          const InfoBanner(
            level: 'warning',
            text: 'هذه الإعدادات تحتاج ملف قاعدة البيانات 20261102000010_contracts.sql. طبّقه مرة واحدة في SQL Editor على Supabase.',
          ),
          const SizedBox(height: 16),
        ],
        ...staggered(stepMs: 70, [
          _motionCard(context, s),
          _navCard(context, app),
          _dashCard(context),
          _termsCard(context),
          _claudeCard(context, app, s),
          SectionCard(
            title: 'مسارات التطوير الداخلي',
            icon: Icons.construction_outlined,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SettingRow(
                  icon: Icons.account_tree_outlined,
                  title: 'المراحل والنماذج والأقسام',
                  subtitle: 'إضافة نموذج أو مرحلة، وتسميتها وترتيبها وإيقافها، وتحديد من يختص بها — من لوحة التحكم.',
                ),
                SettingRow(
                  icon: Icons.dynamic_form_outlined,
                  title: 'الحقول الإضافية',
                  subtitle: 'حقول جديدة للعقود (نص، رقم، مبلغ، تاريخ، قائمة) دون برمجة — من لوحة التحكم.',
                ),
                SettingRow(
                  icon: Icons.lightbulb_outline_rounded,
                  title: 'الأفكار والتطوير',
                  subtitle: 'اقتراحات الفريق ومساعد Claude، وتتبعها حتى التنفيذ ومزامنتها مع GitHub.',
                  trailing: const Icon(Icons.chevron_left_rounded),
                  onTap: app.v2Ready ? () => app.setTab(Tabs.ideas) : null,
                ),
              ],
            ),
          ),
        ]).map((w) => Padding(padding: const EdgeInsets.only(bottom: 16), child: w)),
        Text('التغييرات هنا لا تمس الصلاحيات: قاعدة البيانات تبقى صاحبة القرار في كل إجراء.',
            textAlign: TextAlign.center, style: TextStyle(color: sem.muted, fontSize: 12)),
        const SizedBox(height: 8),
        Center(child: Icon(Icons.verified_user_outlined, color: cs.primary.withAlpha(120), size: 18)),
      ],
    );
  }

  // ---- الحركة ----
  Widget _motionCard(BuildContext context, LiveSettings s) {
    final sem = Sem.of(context);
    final cs = Theme.of(context).colorScheme;
    return SectionCard(
      title: 'الحركة والانتقالات',
      icon: Icons.animation_rounded,
      subtitle: 'من شاشة الدخول إلى أعماق المنظومة: ظهور الأقسام، والتنقل بين الصفحات، والأرقام والمؤشرات.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'full', label: Text('كاملة'), icon: Icon(Icons.auto_awesome_motion_outlined)),
              ButtonSegment(value: 'reduced', label: Text('مخففة'), icon: Icon(Icons.blur_on_rounded)),
              ButtonSegment(value: 'off', label: Text('بلا حركة'), icon: Icon(Icons.motion_photos_off_outlined)),
            ],
            selected: {s.motion},
            showSelectedIcon: false,
            onSelectionChanged: _busy
                ? null
                : (v) async {
                    await _save('ui.motion', v.first, switch (v.first) {
                      'off' => 'أُوقفت الحركة',
                      'reduced' => 'الحركة مخففة الآن',
                      _ => 'الحركة كاملة الآن',
                    });
                    if (mounted) setState(() => _demo++);
                  },
          ),
          const SizedBox(height: 8),
          Text(
            'المخففة: تلاشٍ قصير دون انزلاق. وتتوقف الحركة تلقائياً على أي جهاز فعّل صاحبه «تقليل الحركة».',
            style: TextStyle(color: sem.muted, fontSize: 12),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: KeyedSubtree(
                  key: ValueKey('demo-$_demo'),
                  child: Row(
                    children: staggered(stepMs: 110, [
                      for (var i = 0; i < 4; i++)
                        Padding(
                          padding: const EdgeInsetsDirectional.only(end: 8),
                          child: Container(
                            width: 46,
                            height: 30,
                            decoration: BoxDecoration(color: cs.primary.withAlpha(60 + i * 45), borderRadius: BorderRadius.circular(8)),
                          ),
                        ),
                    ]),
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: () => setState(() => _demo++),
                icon: const Icon(Icons.replay_rounded, size: 18),
                label: const Text('معاينة'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ---- القائمة ----
  Widget _navCard(BuildContext context, AppState app) {
    final sem = Sem.of(context);
    return SectionCard(
      title: 'القائمة الرئيسية',
      icon: Icons.menu_open_rounded,
      subtitle: 'رتّب الصفحات وسمّها، وأخفِ ما لا يحتاجه الموظفون. أنت ترى كل الصفحات دائماً، ولوحة التحكم ثابتة لك.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < _nav.length; i++)
            AnimatedContainer(
              key: ValueKey('nav-${_nav[i].$1}'),
              duration: Motion.of(context, 220),
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(color: _nav[i].$2 ? sem.surface2 : sem.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: sem.rule)),
              child: Row(
                children: [
                  Icon(_navIcon(_nav[i].$1), color: _nav[i].$2 ? null : sem.muted),
                  const SizedBox(width: 10),
                  Expanded(
                    child: InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: () => _renameNav(i),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(_nav[i].$3.isEmpty ? _navDefault(_nav[i].$1) : _nav[i].$3,
                                style: TextStyle(fontWeight: FontWeight.w700, color: _nav[i].$2 ? null : sem.muted)),
                            Text(
                              _nav[i].$3.isEmpty ? 'اضغط لتغيير الاسم' : 'الافتراضي: ${_navDefault(_nav[i].$1)}',
                              style: TextStyle(color: sem.muted, fontSize: 11.5),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  IconButton(tooltip: 'أعلى', visualDensity: VisualDensity.compact, onPressed: i == 0 ? null : () => _move(_nav, i, -1), icon: const Icon(Icons.arrow_upward_rounded, size: 18)),
                  IconButton(
                      tooltip: 'أسفل',
                      visualDensity: VisualDensity.compact,
                      onPressed: i == _nav.length - 1 ? null : () => _move(_nav, i, 1),
                      icon: const Icon(Icons.arrow_downward_rounded, size: 18)),
                  Tooltip(
                    message: _nav[i].$1 == 'home' ? 'الرئيسية ظاهرة دائماً' : 'ظاهرة للموظفين',
                    child: Switch(
                      value: _nav[i].$2 || _nav[i].$1 == 'home',
                      onChanged: _nav[i].$1 == 'home' ? null : (v) => setState(() => _nav[i] = (_nav[i].$1, v, _nav[i].$3)),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 6),
          Wrap(spacing: 8, runSpacing: 8, children: [
            FilledButton.icon(
              onPressed: _busy || !app.v3Ready ? null : () => _save('ui.nav', _navValue, 'حُفظت القائمة'),
              icon: const Icon(Icons.check_rounded, size: 18),
              label: const Text('حفظ القائمة'),
            ),
            OutlinedButton(
              onPressed: _busy || !app.v3Ready
                  ? null
                  : () async {
                      await _save('ui.nav', {'hidden': <String>[], 'order': <String>[], 'labels': <String, String>{}}, 'عادت القائمة إلى الافتراضي');
                      if (mounted) setState(() => _reset(AppScope.read(context)));
                    },
              child: const Text('الافتراضي'),
            ),
          ]),
        ],
      ),
    );
  }

  // ---- أقسام الرئيسية ----
  Widget _dashCard(BuildContext context) {
    final sem = Sem.of(context);
    final app = AppScope.of(context);
    String label(String k) => dashboardCatalog.firstWhere((v) => v.$1 == k).$2;
    IconData icon(String k) => dashboardCatalog.firstWhere((v) => v.$1 == k).$3;
    return SectionCard(
      title: 'أقسام الرئيسية',
      icon: Icons.space_dashboard_outlined,
      subtitle: 'ترتيب أقسام لوحة المؤشرات وما يظهر منها للجميع. النظرة الشاملة ثابتة.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < _dash.length; i++)
            Container(
              key: ValueKey('dash-${_dash[i].$1}'),
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(color: sem.surface2, borderRadius: BorderRadius.circular(12)),
              child: Row(
                children: [
                  Icon(icon(_dash[i].$1)),
                  const SizedBox(width: 10),
                  Expanded(child: Text(label(_dash[i].$1), style: const TextStyle(fontWeight: FontWeight.w600))),
                  IconButton(tooltip: 'أعلى', visualDensity: VisualDensity.compact, onPressed: i == 0 ? null : () => _move(_dash, i, -1), icon: const Icon(Icons.arrow_upward_rounded, size: 18)),
                  IconButton(
                      tooltip: 'أسفل',
                      visualDensity: VisualDensity.compact,
                      onPressed: i == _dash.length - 1 ? null : () => _move(_dash, i, 1),
                      icon: const Icon(Icons.arrow_downward_rounded, size: 18)),
                  Switch(
                    value: _dash[i].$2 || _dash[i].$1 == 'overview',
                    onChanged: _dash[i].$1 == 'overview' ? null : (v) => setState(() => _dash[i] = (_dash[i].$1, v)),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 6),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: FilledButton.icon(
              onPressed: _busy || !app.v3Ready ? null : () => _save('ui.dashboard', _dashValue, 'حُفظت أقسام الرئيسية'),
              icon: const Icon(Icons.check_rounded, size: 18),
              label: const Text('حفظ الأقسام'),
            ),
          ),
        ],
      ),
    );
  }

  // ---- المصطلحات ----
  Widget _termsCard(BuildContext context) {
    final app = AppScope.of(context);
    return SectionCard(
      title: 'المصطلحات',
      icon: Icons.translate_rounded,
      subtitle: 'غيّر الكلمات التي تظهر في الواجهة لتطابق لغة المكتب. اترك الحقل فارغاً للافتراضي.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ResponsiveGrid(
            minItemWidth: 240,
            spacing: 10,
            children: [
              for (final k in defaultTerms.keys)
                TextField(
                  controller: _terms[k],
                  maxLength: 60,
                  decoration: fieldDeco(defaultTerms[k]!, hint: defaultTerms[k], helper: termHints[k]).copyWith(counterText: ''),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 8, children: [
            FilledButton.icon(
              onPressed: _busy || !app.v3Ready
                  ? null
                  : () => _save(
                        'ui.labels',
                        {
                          for (final e in _terms.entries)
                            if (e.value.text.trim().isNotEmpty && e.value.text.trim() != defaultTerms[e.key]) e.key: e.value.text.trim(),
                        },
                        'حُفظت المصطلحات',
                      ),
              icon: const Icon(Icons.check_rounded, size: 18),
              label: const Text('حفظ المصطلحات'),
            ),
            OutlinedButton(
              onPressed: _busy || !app.v3Ready
                  ? null
                  : () async {
                      for (final c in _terms.values) {
                        c.clear();
                      }
                      await _save('ui.labels', <String, String>{}, 'عادت المصطلحات إلى الافتراضي');
                    },
              child: const Text('الافتراضي'),
            ),
          ]),
        ],
      ),
    );
  }

  // ---- مساعد Claude ----
  Widget _claudeCard(BuildContext context, AppState app, LiveSettings s) {
    final sem = Sem.of(context);
    final cs = Theme.of(context).colorScheme;
    final known = _models.any((m) => m.$1 == s.aiModel);
    return SectionCard(
      title: 'مساعد Claude',
      icon: Icons.auto_awesome_outlined,
      subtitle: 'مساعد لمدير المكتب وحده: يحلل العقود والأعمال والمهندسين والمالية والطلبات، ويقترح تطويرات تُحفظ أفكاراً.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('تشغيل المساعد', style: TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text(s.aiEnabled ? 'يظهر في قائمتك باسم «مساعد Claude»' : 'متوقف ومخفي من القائمة', style: TextStyle(color: sem.muted)),
            value: s.aiEnabled,
            onChanged: _busy || !app.v3Ready ? null : (v) => _save('ai.enabled', v, v ? 'شُغّل مساعد Claude' : 'أُوقف مساعد Claude'),
          ),
          const SizedBox(height: 6),
          const Text('النموذج', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          for (final m in _models)
            RadioListTile<String>(
              contentPadding: EdgeInsets.zero,
              dense: true,
              value: m.$1,
              groupValue: s.aiModel,
              onChanged: _busy || !app.v3Ready ? null : (v) => _save('ai.model', v, 'سيستخدم المساعد ${m.$2}'),
              title: Text(m.$2, style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text(m.$3, style: TextStyle(color: sem.muted, fontSize: 12)),
            ),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              onPressed: _busy || !app.v3Ready ? null : () => _customModel(s.aiModel),
              icon: const Icon(Icons.edit_outlined, size: 18),
              label: Text(known ? 'نموذج آخر…' : 'النموذج الحالي: ${s.aiModel}'),
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _instructions,
            minLines: 3,
            maxLines: 8,
            maxLength: 4000,
            decoration: fieldDeco(
              'تعليمات دائمة للمساعد (اختياري)',
              hint: 'مثال: ركّز على العقود المتأخرة أكثر من 30 يوماً، واذكر أرقام العقود دائماً.',
            ),
          ),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: FilledButton.icon(
              onPressed: _busy || !app.v3Ready ? null : () => _save('ai.instructions', _instructions.text.trim(), 'حُفظت تعليمات المساعد'),
              icon: const Icon(Icons.check_rounded, size: 18),
              label: const Text('حفظ التعليمات'),
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: cs.primaryContainer.withAlpha(120), borderRadius: BorderRadius.circular(12)),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.key_outlined, color: cs.onPrimaryContainer),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'مفتاح Anthropic يُحفظ سراً في Supabase ← Edge Functions ← Secrets باسم ANTHROPIC_API_KEY، '
                    'ولا يدخل التطبيق ولا قاعدة البيانات. يعمل المساعد عبر خدمة claude-assistant، ويقرأ ملخص المنظومة بصلاحيتك، '
                    'ولا يعدّل أي بيانات، ويُسجَّل كل سؤال في سجل التدقيق.',
                    style: TextStyle(color: cs.onPrimaryContainer, height: 1.6, fontSize: 12.5),
                  ),
                ),
              ],
            ),
          ),
          if (app.canUseAssistant) ...[
            const SizedBox(height: 10),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: OutlinedButton.icon(
                onPressed: () => app.setTab(Tabs.assistant),
                icon: const Icon(Icons.chat_bubble_outline_rounded, size: 18),
                label: const Text('فتح المساعد'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
