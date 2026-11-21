import 'package:flutter/material.dart';

import '../app_state.dart';
import '../rasd.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';

// =====================================================================
// الأرقام الإشارية (الترحيل 23): سجل كل رقم صدر، وصيغ يبنيها المدير لكل نوع.
// =====================================================================

class RefNumbersPage extends StatefulWidget {
  const RefNumbersPage({super.key});

  @override
  State<RefNumbersPage> createState() => _RefNumbersPageState();
}

class _RefNumbersPageState extends State<RefNumbersPage> {
  int _tab = 0;
  String _scheme = '';
  final _q = TextEditingController();
  List<RefLogEntry>? _log;
  Map<String, int> _counters = const {};
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final app = AppScope.read(context);
    try {
      final r = await Future.wait<Object>([app.loadRefLog(scheme: _scheme, limit: 1000), app.loadRefCounters()]);
      if (!mounted) return;
      setState(() {
        _log = r[0] as List<RefLogEntry>;
        _counters = r[1] as Map<String, int>;
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    }
  }

  String _periodNow(RefScheme s) {
    final t = DateTime.now();
    return switch (s.reset) {
      'yearly' => '${t.year}',
      'monthly' => '${t.year}-${two(t.month)}',
      'daily' => '${t.year}-${two(t.month)}-${two(t.day)}',
      _ => 'all',
    };
  }

  /// آخر تسلسل صدر في الفترة الحالية (لغير المفصولة بالأقسام).
  int _lastSeq(RefScheme s) {
    if (s.perSection) {
      var m = 0;
      final prefix = '${s.key}|${_periodNow(s)}|';
      for (final e in _counters.entries) {
        if (e.key.startsWith(prefix) && e.value > m) m = e.value;
      }
      return m;
    }
    return _counters['${s.key}|${_periodNow(s)}'] ?? 0;
  }

  Future<void> _edit(RefScheme? s) async {
    final saved = await showDialog<bool>(context: context, builder: (_) => RefSchemeDialog(scheme: s));
    if (saved == true) await _load();
  }

  Future<void> _setCounter(RefScheme s) async {
    final app = AppScope.read(context);
    final v = await textInputDialog(context,
        title: 'ضبط الرقم التالي — ${s.name}',
        message: 'عند الانتقال من دفتر ورقي مثلاً: يبدأ التسلسل في الفترة الحالية من الرقم الذي تكتبه. '
            'لا يُقبل رقم أصغر من آخر رقم صدر حتى لا يتكرر.${s.perSection ? '\nهذه الصيغة مفصولة بالأقسام: يُضبط تسلسل القسم الذي تختاره لاحقاً.' : ''}',
        label: 'الرقم التالي',
        confirmLabel: 'ضبط',
        required: true,
        multiline: false,
        keyboardType: TextInputType.number,
        initial: '${_lastSeq(s) + 1}');
    if (v == null) return;
    final n = int.tryParse(v.trim());
    if (n == null || n < 1) {
      if (mounted) showToast(context, 'اكتب رقماً صحيحاً', error: true);
      return;
    }
    String? section;
    if (s.perSection && mounted) {
      section = await showDialog<String>(
        context: context,
        builder: (ctx) => SimpleDialog(title: const Text('القسم'), children: [
          for (final e in refSectionNames.entries) SimpleDialogOption(onPressed: () => Navigator.of(ctx).pop(e.key), child: Text(e.value)),
        ]),
      );
      if (section == null) return;
    }
    try {
      await app.setRefCounter(s.key, n, section: section);
      if (mounted) showToast(context, 'الرقم التالي: ${s.preview(seq: n, ctx: {'section': section ?? 'cycle'})}');
      await _load();
    } catch (e) {
      if (mounted) showToast(context, friendlyError(e), error: true);
    }
  }

  Future<void> _toggle(RefScheme s) async {
    final app = AppScope.read(context);
    try {
      await app.saveRefScheme(s.key, {...s.toData(), 'active': !s.active});
    } catch (e) {
      if (mounted) showToast(context, friendlyError(e), error: true);
    }
  }

  Future<void> _delete(RefScheme s) async {
    final app = AppScope.read(context);
    final ok = await confirmDialog(context,
        title: 'حذف الصيغة', message: 'تُحذف «${s.name}». يُسمح بالحذف فقط إن لم يصدر بها أي رقم.', confirmLabel: 'حذف', danger: true);
    if (!ok) return;
    try {
      await app.deleteRefScheme(s.key);
    } catch (e) {
      if (mounted) showToast(context, friendlyError(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final sem = Sem.of(context);
    if (!app.v11Ready) {
      return const PageBody(children: [
        EmptyState(
          icon: Icons.pin_outlined,
          title: 'الأرقام الإشارية الموسّعة غير مفعّلة بعد',
          message: 'تعمل بعد تحديث قاعدة البيانات بالملف 20261119000023_rasd_grants_refs.sql.',
        ),
      ]);
    }
    final q = _q.text.trim();
    final log = (_log ?? const <RefLogEntry>[])
        .where((e) => q.isEmpty || e.ref.contains(q) || (e.title ?? '').contains(q) || (app.people[e.createdBy]?.displayName ?? '').contains(q))
        .toList();
    final today = DateTime.now();
    final issuedToday = (_log ?? const <RefLogEntry>[])
        .where((e) => e.createdAt != null && e.createdAt!.year == today.year && e.createdAt!.month == today.month && e.createdAt!.day == today.day)
        .length;
    return PageBody(onRefresh: _load, children: [
      PageHeader(
        title: 'الأرقام الإشارية',
        subtitle: 'كل ملف يُطبع أو يُصدَّر وكل مراسلة تأخذ رقماً تصدره قاعدة البيانات فلا يتكرر، بصيغة يحددها مدير المكتب لكل نوع.',
        icon: Icons.pin_outlined,
        actions: [
          if (app.isDirector)
            FilledButton.icon(onPressed: () => _edit(null), icon: const Icon(Icons.add_rounded), label: const Text('صيغة جديدة')),
        ],
      ),
      ResponsiveGrid(minItemWidth: 200, children: [
        StatCard(label: 'صيغة مفعّلة', value: '${app.refSchemes.where((s) => s.active).length}', icon: Icons.tune_rounded),
        StatCard(label: 'رقماً في السجل', value: '${_log?.length ?? 0}', icon: Icons.format_list_numbered_rounded),
        StatCard(label: 'صدر اليوم', value: '$issuedToday', icon: Icons.today_outlined),
      ]),
      const SizedBox(height: 12),
      SegmentedButton<int>(
        segments: const [
          ButtonSegment(value: 0, label: Text('الصيغ'), icon: Icon(Icons.tune_rounded)),
          ButtonSegment(value: 1, label: Text('سجل الأرقام'), icon: Icon(Icons.list_alt_rounded)),
        ],
        selected: {_tab},
        onSelectionChanged: (v) => setState(() => _tab = v.first),
      ),
      const SizedBox(height: 12),
      if (_error != null) InfoBanner(text: _error!, level: 'critical'),
      if (_tab == 0)
        ResponsiveGrid(minItemWidth: 360, children: [
          for (final s in app.refSchemes)
            SectionCard(
              title: s.name,
              icon: s.system ? Icons.verified_outlined : Icons.tune_rounded,
              subtitle: '${refResetLabels[s.reset] ?? s.reset}${s.perSection ? ' · تسلسل مستقل لكل قسم' : ''}${s.active ? '' : ' · موقوفة'}',
              trailing: app.isDirector
                  ? PopupMenuButton<String>(
                      onSelected: (v) => switch (v) {
                        'edit' => _edit(s),
                        'counter' => _setCounter(s),
                        'toggle' => _toggle(s),
                        _ => _delete(s),
                      },
                      itemBuilder: (_) => [
                        const PopupMenuItem(value: 'edit', child: Text('تعديل الصيغة')),
                        const PopupMenuItem(value: 'counter', child: Text('ضبط الرقم التالي')),
                        PopupMenuItem(value: 'toggle', child: Text(s.active ? 'إيقاف' : 'تفعيل')),
                        if (!s.system) const PopupMenuItem(value: 'delete', child: Text('حذف')),
                      ],
                    )
                  : null,
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(color: sem.surface2, borderRadius: BorderRadius.circular(12)),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('الرقم التالي', style: TextStyle(color: sem.muted, fontSize: 12)),
                    const SizedBox(height: 2),
                    Directionality(
                      textDirection: TextDirection.ltr,
                      child: Text(s.preview(seq: _lastSeq(s) + 1, ctx: const {'section': 'cycle', 'code': '990', 'kind': 'ncr'}),
                          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18, fontFeatures: [FontFeature.tabularFigures()])),
                    ),
                  ]),
                ),
                const SizedBox(height: 8),
                Directionality(
                  textDirection: TextDirection.ltr,
                  child: Text(s.pattern, style: TextStyle(color: sem.muted, fontFamily: 'monospace', fontSize: 12.5)),
                ),
                const SizedBox(height: 4),
                Text('آخر تسلسل في الفترة الحالية: ${_lastSeq(s)}', style: TextStyle(color: sem.muted, fontSize: 12)),
              ]),
            ),
        ])
      else ...[
        Row(children: [
          Expanded(
            child: TextField(
              controller: _q,
              onChanged: (_) => setState(() {}),
              decoration: fieldDeco('بحث بالرقم أو العنوان أو المستخدم', prefixIcon: const Icon(Icons.search_rounded)),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 240,
            child: SelectField(
              label: 'الصيغة',
              value: _scheme,
              items: [('', 'كل الصيغ'), for (final s in app.refSchemes) (s.key, s.name)],
              onChanged: (v) {
                setState(() {
                  _scheme = v;
                  _log = null;
                });
                _load();
              },
            ),
          ),
        ]),
        const SizedBox(height: 10),
        if (_log == null)
          const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()))
        else if (log.isEmpty)
          const EmptyState(icon: Icons.pin_outlined, title: 'لا أرقام بعد', message: 'تظهر هنا الأرقام عند أول طباعة أو تصدير أو مراسلة مرقّمة.')
        else
          SectionCard(
            title: 'سجل الأرقام (${log.length})',
            padding: EdgeInsets.zero,
            child: Column(children: [
              for (final e in log.take(400))
                ListTile(
                  dense: true,
                  leading: Icon(Icons.tag_rounded, color: sem.muted),
                  title: Directionality(
                    textDirection: TextDirection.ltr,
                    child: Align(
                      alignment: AlignmentDirectional.centerEnd,
                      child: Text(e.ref, style: const TextStyle(fontWeight: FontWeight.w800, fontFeatures: [FontFeature.tabularFigures()])),
                    ),
                  ),
                  subtitle: Text([
                    app.refScheme(e.scheme)?.name ?? e.scheme,
                    if ((e.title ?? '').isNotEmpty) e.title!,
                    if (e.section != null && e.section!.isNotEmpty) refSectionNames[e.section] ?? e.section!,
                    app.people[e.createdBy]?.displayName ?? '',
                  ].where((x) => x.isNotEmpty).join(' · ')),
                  trailing: Text('${fmtDate(e.createdAt)} ${e.createdAt == null ? '' : '${two(e.createdAt!.hour)}:${two(e.createdAt!.minute)}'}',
                      style: TextStyle(color: sem.muted, fontSize: 12)),
                ),
            ]),
          ),
      ],
    ]);
  }
}

class RefSchemeDialog extends StatefulWidget {
  const RefSchemeDialog({super.key, this.scheme});

  final RefScheme? scheme;

  @override
  State<RefSchemeDialog> createState() => _RefSchemeDialogState();
}

class _RefSchemeDialogState extends State<RefSchemeDialog> {
  late final _key = TextEditingController(text: widget.scheme?.key ?? '');
  late final _name = TextEditingController(text: widget.scheme?.name ?? '');
  late final _pattern = TextEditingController(text: widget.scheme?.pattern ?? 'م.ش.هـ/{SECTION}/{YYYY}/{SEQ}');
  late String _reset = widget.scheme?.reset ?? 'yearly';
  late bool _perSection = widget.scheme?.perSection ?? false;
  late int _pad = widget.scheme?.pad ?? 4;
  late final _start = TextEditingController(text: '${widget.scheme?.startAt ?? 1}');
  late final Map<String, TextEditingController> _codes = {
    for (final k in refSectionNames.keys) k: TextEditingController(text: widget.scheme?.codes[k] ?? ''),
  };
  bool _busy = false;
  String? _err;

  @override
  void dispose() {
    _key.dispose();
    _name.dispose();
    _pattern.dispose();
    _start.dispose();
    for (final c in _codes.values) {
      c.dispose();
    }
    super.dispose();
  }

  Map<String, String> get _codeMap => {for (final e in _codes.entries) if (e.value.text.trim().isNotEmpty) e.key: e.value.text.trim()};

  void _insert(String token) {
    final sel = _pattern.selection;
    final t = _pattern.text;
    final start = sel.isValid ? sel.start : t.length;
    final end = sel.isValid ? sel.end : t.length;
    _pattern.value = TextEditingValue(
      text: t.replaceRange(start, end, token),
      selection: TextSelection.collapsed(offset: start + token.length),
    );
    setState(() {});
  }

  Future<void> _save() async {
    final app = AppScope.read(context);
    final key = widget.scheme?.key ?? _key.text.trim().toLowerCase();
    if (!RegExp(r'^[a-z][a-z0-9_]{1,29}$').hasMatch(key)) {
      setState(() => _err = 'المفتاح بحروف إنجليزية صغيرة وأرقام و_ ويبدأ بحرف (مثل contract_mail).');
      return;
    }
    if (!_pattern.text.contains('{SEQ')) {
      setState(() => _err = 'الصيغة يجب أن تحوي {SEQ} حتى لا يتكرر الرقم.');
      return;
    }
    setState(() {
      _busy = true;
      _err = null;
    });
    try {
      await app.saveRefScheme(key, {
        'name': _name.text.trim(),
        'pattern': _pattern.text.trim(),
        'reset': _reset,
        'per_section': _perSection,
        'pad': _pad,
        'start_at': int.tryParse(_start.text.trim()) ?? 1,
        'codes': _codeMap,
        'active': widget.scheme?.active ?? true,
      });
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) setState(() => _err = friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sem = Sem.of(context);
    final preview = formatRef(_pattern.text,
        seq: int.tryParse(_start.text.trim()) ?? 1,
        pad: _pad,
        at: DateTime.now(),
        ctx: const {'section': 'cycle', 'dept': 'supervision', 'code': '990/2026', 'kind': 'ncr'},
        codes: _codeMap);
    return AlertDialog(
      title: Text(widget.scheme == null ? 'صيغة رقم إشاري جديدة' : 'تعديل «${widget.scheme!.name}»'),
      content: SizedBox(
        width: 620,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (widget.scheme == null)
              TextField(
                controller: _key,
                textDirection: TextDirection.ltr,
                decoration: fieldDeco('المفتاح (إنجليزي)', hint: 'contract_mail', helper: 'يُستعمل داخلياً ولا يتغير بعد الإنشاء'),
              ),
            const SizedBox(height: 8),
            TextField(controller: _name, decoration: fieldDeco('الاسم', hint: 'مراسلات العقود'), onChanged: (_) => setState(() {})),
            const SizedBox(height: 8),
            TextField(
              controller: _pattern,
              textDirection: TextDirection.ltr,
              onChanged: (_) => setState(() {}),
              decoration: fieldDeco('الصيغة'),
            ),
            const SizedBox(height: 6),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final t in refTokens) Tooltip(message: t.$2, child: ActionChip(label: Text(t.$1), onPressed: () => _insert(t.$1))),
            ]),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: Theme.of(context).colorScheme.primaryContainer, borderRadius: BorderRadius.circular(12)),
              child: Row(children: [
                const Icon(Icons.visibility_outlined),
                const SizedBox(width: 8),
                const Text('معاينة: '),
                Expanded(
                  child: Directionality(
                    textDirection: TextDirection.ltr,
                    child: Text(preview,
                        textAlign: TextAlign.end, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16, fontFeatures: [FontFeature.tabularFigures()])),
                  ),
                ),
              ]),
            ),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: SelectField(
                  label: 'إعادة التسلسل',
                  value: _reset,
                  items: [for (final e in refResetLabels.entries) (e.key, e.value)],
                  onChanged: (v) => setState(() => _reset = v),
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 140,
                child: TextField(
                  controller: _start,
                  keyboardType: TextInputType.number,
                  onChanged: (_) => setState(() {}),
                  decoration: fieldDeco('يبدأ من'),
                ),
              ),
            ]),
            const SizedBox(height: 8),
            Text('عدد خانات التسلسل: $_pad'),
            Slider(value: _pad.toDouble(), min: 1, max: 8, divisions: 7, label: '$_pad', onChanged: (v) => setState(() => _pad = v.round())),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _perSection,
              onChanged: (v) => setState(() => _perSection = v),
              title: const Text('تسلسل مستقل لكل قسم'),
              subtitle: const Text('لكل قسم عدّاده: د.م/0001 و م.م/0001 معاً.'),
            ),
            const Divider(),
            Text('رموز الأقسام لـ {SECTION} و{DEPT} (اتركه فارغاً لاستعمال المفتاح)', style: TextStyle(color: sem.muted)),
            const SizedBox(height: 6),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final e in refSectionNames.entries)
                SizedBox(width: 180, child: TextField(controller: _codes[e.key], onChanged: (_) => setState(() {}), decoration: fieldDeco(e.value))),
            ]),
            if (_err != null) ...[const SizedBox(height: 10), InfoBanner(text: _err!, level: 'critical')],
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('إلغاء')),
        FilledButton(onPressed: _busy || _name.text.trim().length < 2 ? null : _save, child: const Text('حفظ')),
      ],
    );
  }
}
