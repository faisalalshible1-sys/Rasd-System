import 'package:flutter/material.dart';

import '../app_state.dart';
import '../models.dart';
import '../pm.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';
import 'contract_finance.dart' show DayField;

// =====================================================================
// أدوات مشتركة لصفحات «المخاطر ومتابعة المشاريع»: النماذج، والقوائم، والألوان، والتنسيق.
// =====================================================================

String pctOrDash(double? v, {int digits = 0}) => v == null ? '—' : pctText(v, digits: digits);
String spiText(double? v) => v == null ? '—' : v.toStringAsFixed(2);
String daysOrDash(int? d) => d == null ? '—' : '$d يوم';
String moneyOrDash(double? v) => v == null ? '—' : '${fmtMoney(v)} $currencyLabel';

/// اسم العقد للعرض، و«عام» للسجلات على مستوى المحفظة.
String pmProjectName(AppState app, String? id) {
  if (id == null || id.isEmpty) return 'عام – متعدد المشاريع';
  final p = app.project(id);
  if (p == null) return 'عقد غير متاح';
  return p.label;
}

/// خيارات العقود القائمة مرتبة كما في سجل العقود.
List<(String, String)> pmProjectOptions(AppState app, {String? general, List<Project>? from}) {
  final list = [...from ?? app.projects]..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
  return [
    if (general != null) ('', general),
    for (final p in list) (p.id, p.label),
  ];
}

List<(String, String)> pmLabels(List<String> keys, Map<String, String> labels) => [for (final k in keys) (k, labels[k] ?? k)];
List<(String, String)> pmPlain(List<String> values) => [for (final v in values) (v, v)];

bool pmMatch(String q, List<String> fields) {
  if (q.isEmpty) return true;
  final hay = fields.join(' ');
  return hay.contains(q) || hay.toLowerCase().contains(q.toLowerCase());
}

Color perfColor(BuildContext context, String key) {
  final sem = Sem.of(context);
  return switch (key) {
    'ahead' => const Color(0xFF2E7D9A),
    'on_track' => sem.ok,
    'slight' => sem.wip,
    'critical' => sem.danger,
    'done' => const Color(0xFF5E6B1F),
    'suspended' => const Color(0xFF8A5A3C),
    _ => sem.muted,
  };
}

Color pmFollowColor(Sem sem, String key) => switch (key) {
      'overdue' => sem.danger,
      'soon' => sem.wip,
      'ontime' => sem.ok,
      _ => sem.muted,
    };

Color priorityColor(Sem sem, String p) => switch (p) {
      'high' => sem.danger,
      'medium' => sem.wip,
      _ => sem.muted,
    };

class PerfBadge extends StatelessWidget {
  const PerfBadge(this.perf, {super.key});

  final String perf;

  @override
  Widget build(BuildContext context) => ToneBadge(perfLabels[perf] ?? perf, color: perfColor(context, perf));
}

/// تنبيه: قاعدة البيانات لم تُحدَّث بعد بالإصدار السابع.
class PmNotReady extends StatelessWidget {
  const PmNotReady({super.key, required this.title});

  final String title;

  @override
  Widget build(BuildContext context) => PageBody(children: [
        PageHeader(title: title, icon: Icons.view_timeline_outlined),
        const InfoBanner(
          text: 'متابعة المشاريع تعمل بعد تحديث قاعدة البيانات بالملف 20261111000016_project_tracking.sql من SQL Editor في Supabase.',
          level: 'warning',
        ),
      ]);
}

// =====================================================================
// نموذج إدخال عام بحقول موصوفة (لكل سجلات المتابعة)
// =====================================================================
enum PmKind { text, multiline, select, date, integer, decimal, money, signedMoney, percent, score, toggle }

class PmField {
  const PmField(this.key, this.label, this.kind,
      {this.options = const [], this.required = false, this.max = 300, this.helper, this.full = false, this.enabled = true});

  final String key;
  final String label;
  final PmKind kind;

  /// للقوائم: (القيمة، التسمية)؛ وللمقياس 1–5: تسميات الدرجات.
  final List<(String, String)> options;
  final bool required;
  final int max;
  final String? helper;
  final bool full;
  final bool enabled;
}

class PmSection {
  const PmSection(this.title, this.fields);

  final String title;
  final List<PmField> fields;
}

/// يفتح نموذج الإدخال. [values] القيم الحالية بمفاتيح الحقول (كما تُرسل لقاعدة البيانات).
/// يُرجع true عند الحفظ.
Future<bool> showPmForm(
  BuildContext context, {
  required String title,
  required List<PmSection> sections,
  required Map<String, dynamic> values,
  required Future<void> Function(Map<String, dynamic> data) onSave,
  String? note,
  Widget? Function(Map<String, dynamic> current)? preview,
}) async {
  final wide = MediaQuery.sizeOf(context).width >= 760;
  final form = _PmForm(title: title, sections: sections, values: values, onSave: onSave, note: note, preview: preview);
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => wide
        ? Dialog(
            insetPadding: const EdgeInsets.all(24),
            child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 780, maxHeight: 880), child: form),
          )
        : Dialog.fullscreen(child: form),
  );
  return ok == true;
}

String _digits(String input) {
  final b = StringBuffer();
  for (final r in input.trim().runes) {
    if (r >= 0x0660 && r <= 0x0669) {
      b.writeCharCode(0x30 + r - 0x0660);
    } else if (r >= 0x06F0 && r <= 0x06F9) {
      b.writeCharCode(0x30 + r - 0x06F0);
    } else if (r == 0x066B) {
      b.write('.');
    } else if (r == 0x066C || r == 0x2C || r == 0x20 || r == 0xA0) {
      continue;
    } else if (r == 0x2212) {
      b.write('-');
    } else {
      b.writeCharCode(r);
    }
  }
  return b.toString();
}

class _PmForm extends StatefulWidget {
  const _PmForm({required this.title, required this.sections, required this.values, required this.onSave, this.note, this.preview});

  final String title;
  final List<PmSection> sections;
  final Map<String, dynamic> values;
  final Future<void> Function(Map<String, dynamic> data) onSave;
  final String? note;
  final Widget? Function(Map<String, dynamic> current)? preview;

  @override
  State<_PmForm> createState() => _PmFormState();
}

class _PmFormState extends State<_PmForm> {
  final Map<String, TextEditingController> _c = {};
  final Map<String, dynamic> _v = {};
  bool _saving = false;
  String? _error;

  Iterable<PmField> get _fields => widget.sections.expand((s) => s.fields);

  static bool _isText(PmKind k) =>
      k == PmKind.text ||
      k == PmKind.multiline ||
      k == PmKind.integer ||
      k == PmKind.decimal ||
      k == PmKind.money ||
      k == PmKind.signedMoney ||
      k == PmKind.percent;

  @override
  void initState() {
    super.initState();
    for (final f in _fields) {
      final v = widget.values[f.key];
      if (_isText(f.kind)) {
        var text = v?.toString() ?? '';
        if (f.kind == PmKind.money || f.kind == PmKind.signedMoney) {
          text = v is num ? moneyInput(v.toDouble()) : '';
        } else if (f.kind == PmKind.percent) {
          text = v is num ? _trim((v * 100).toStringAsFixed(2)) : '';
        } else if (f.kind == PmKind.integer) {
          text = v is num ? v.toInt().toString() : '';
        } else if (f.kind == PmKind.decimal) {
          text = v is num ? _trim(v.toStringAsFixed(4)) : '';
        }
        _c[f.key] = TextEditingController(text: text);
      } else if (f.kind == PmKind.date) {
        _v[f.key] = v is DateTime ? v : DateTime.tryParse(v?.toString() ?? '');
      } else if (f.kind == PmKind.score) {
        _v[f.key] = v is num ? v.toInt() : int.tryParse(v?.toString() ?? '');
      } else if (f.kind == PmKind.toggle) {
        _v[f.key] = v == true;
      } else {
        _v[f.key] = v?.toString() ?? '';
      }
    }
  }

  static String _trim(String s) => s.contains('.') ? s.replaceFirst(RegExp(r'\.?0+$'), '') : s;

  @override
  void dispose() {
    for (final c in _c.values) {
      c.dispose();
    }
    super.dispose();
  }

  /// القيم الحالية كما تُرسل (بدون تحقق).
  Map<String, dynamic> _current({List<String>? errors}) {
    final out = <String, dynamic>{};
    for (final f in _fields) {
      final k = f.kind;
      if (k == PmKind.text || k == PmKind.multiline) {
        final t = _c[f.key]!.text.trim();
        if (f.required && t.isEmpty) errors?.add('أدخل «${f.label}»');
        out[f.key] = t;
      } else if (k == PmKind.integer) {
        final t = _digits(_c[f.key]!.text);
        final n = t.isEmpty ? null : int.tryParse(t);
        if (t.isNotEmpty && (n == null || n < 0)) errors?.add('«${f.label}» رقم صحيح غير سالب');
        if (f.required && t.isEmpty) errors?.add('أدخل «${f.label}»');
        out[f.key] = n;
      } else if (k == PmKind.decimal) {
        final t = _digits(_c[f.key]!.text);
        final n = t.isEmpty ? null : double.tryParse(t);
        if (t.isNotEmpty && (n == null || n < 0)) errors?.add('«${f.label}» رقم غير صالح');
        if (f.required && t.isEmpty) errors?.add('أدخل «${f.label}»');
        out[f.key] = n;
      } else if (k == PmKind.money) {
        final r = parseMoney(_c[f.key]!.text);
        if (!r.ok) errors?.add('«${f.label}» مبلغ غير صالح');
        if (f.required && r.value == null) errors?.add('أدخل «${f.label}»');
        out[f.key] = r.value;
      } else if (k == PmKind.signedMoney) {
        var t = _digits(_c[f.key]!.text);
        final neg = t.startsWith('-');
        if (neg) t = t.substring(1);
        final r = parseMoney(t);
        if (!r.ok) errors?.add('«${f.label}» مبلغ غير صالح');
        if (f.required && r.value == null) errors?.add('أدخل «${f.label}»');
        final v = r.value;
        out[f.key] = v == null ? null : (neg ? -v : v);
      } else if (k == PmKind.percent) {
        final t = _digits(_c[f.key]!.text).replaceAll('%', '');
        final n = t.isEmpty ? null : double.tryParse(t);
        if (t.isNotEmpty && (n == null || n < 0 || n > 100)) errors?.add('«${f.label}» نسبة من 0 إلى 100');
        if (f.required && t.isEmpty) errors?.add('أدخل «${f.label}»');
        out[f.key] = n == null ? null : n / 100;
      } else if (k == PmKind.date) {
        final d = _v[f.key] as DateTime?;
        if (f.required && d == null) errors?.add('حدّد «${f.label}»');
        out[f.key] = pmIso(d);
      } else if (k == PmKind.score) {
        final n = _v[f.key] as int?;
        if (f.required && n == null) errors?.add('حدّد «${f.label}»');
        out[f.key] = n;
      } else if (k == PmKind.toggle) {
        out[f.key] = _v[f.key] == true;
      } else {
        final t = (_v[f.key] as String?) ?? '';
        if (f.required && t.isEmpty) errors?.add('اختر «${f.label}»');
        out[f.key] = t;
      }
    }
    return out;
  }

  Future<void> _save() async {
    final errors = <String>[];
    final data = _current(errors: errors);
    if (errors.isNotEmpty) {
      setState(() => _error = errors.first);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onSave(data);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = friendlyError(e);
        });
      }
    }
  }

  Widget _field(PmField f) {
    final sem = Sem.of(context);
    final k = f.kind;
    if (_isText(k)) {
      final multi = k == PmKind.multiline;
      final numeric = k != PmKind.text && k != PmKind.multiline;
      Widget? suffix;
      if (k == PmKind.percent) {
        suffix = const Padding(padding: EdgeInsets.all(12), child: Text('%'));
      } else if (k == PmKind.money || k == PmKind.signedMoney) {
        suffix = Padding(padding: const EdgeInsets.all(12), child: Text(currencyLabel));
      }
      return TextField(
        controller: _c[f.key],
        enabled: f.enabled,
        minLines: multi ? 2 : 1,
        maxLines: multi ? 6 : 1,
        maxLength: numeric ? null : f.max,
        keyboardType: numeric ? const TextInputType.numberWithOptions(decimal: true, signed: true) : null,
        onChanged: (_) => setState(() {}),
        decoration: fieldDeco(f.label + (f.required ? ' *' : ''), helper: f.helper, suffix: suffix).copyWith(counterText: ''),
      );
    }
    if (k == PmKind.select) {
      final cur = (_v[f.key] as String?) ?? '';
      final items = <(String, String)>[
        if (!f.required && !f.options.any((o) => o.$1.isEmpty)) ('', '—'),
        ...f.options,
        if (cur.isNotEmpty && !f.options.any((o) => o.$1 == cur)) (cur, cur),
      ];
      if (f.required && cur.isEmpty && items.isNotEmpty) _v[f.key] = items.first.$1;
      return IgnorePointer(
        ignoring: !f.enabled,
        child: Opacity(
          opacity: f.enabled ? 1 : 0.6,
          child: SelectField(
            label: f.label + (f.required ? ' *' : ''),
            value: (_v[f.key] as String?) ?? '',
            items: items,
            onChanged: (v) => setState(() => _v[f.key] = v),
          ),
        ),
      );
    }
    if (k == PmKind.date) {
      return DayField(
        label: f.label + (f.required ? ' *' : ''),
        value: _v[f.key] as DateTime?,
        enabled: f.enabled,
        onChanged: (d) => setState(() => _v[f.key] = d),
      );
    }
    if (k == PmKind.score) {
      final cur = _v[f.key] as int?;
      String lbl(int v) {
        for (final o in f.options) {
          if (o.$1 == '$v') return '$v ${o.$2}';
        }
        return '$v';
      }

      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(f.label + (f.required ? ' *' : ''), style: TextStyle(color: sem.muted, fontSize: 12.5, fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (var v = 1; v <= 5; v++)
            ChoiceChip(
              visualDensity: VisualDensity.compact,
              label: Text(lbl(v)),
              selected: cur == v,
              onSelected: f.enabled ? (on) => setState(() => _v[f.key] = on ? v : (f.required ? v : null)) : null,
            ),
        ]),
      ]);
    }
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      value: _v[f.key] == true,
      title: Text(f.label),
      subtitle: f.helper == null ? null : Text(f.helper!),
      onChanged: f.enabled ? (on) => setState(() => _v[f.key] = on) : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final sem = Sem.of(context);
    final pv = widget.preview?.call(_current());
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: Text(widget.title),
        leading: IconButton(icon: const Icon(Icons.close_rounded), onPressed: () => Navigator.of(context).pop(false)),
        actions: [
          Padding(
            padding: const EdgeInsetsDirectional.only(end: 12),
            child: FilledButton(
              onPressed: _saving ? null : _save,
              child: _saving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('حفظ'),
            ),
          ),
        ],
      ),
      body: ListView(padding: const EdgeInsets.fromLTRB(18, 4, 18, 24), children: [
        if (_error != null) Padding(padding: const EdgeInsets.only(bottom: 12), child: InfoBanner(text: _error!, level: 'critical')),
        if (widget.note != null)
          Padding(padding: const EdgeInsets.only(bottom: 12), child: InfoBanner(text: widget.note!, level: 'info')),
        if (pv != null) Padding(padding: const EdgeInsets.only(bottom: 14), child: pv),
        for (final sec in widget.sections) ...[
          if (sec.title.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6, bottom: 10),
              child: Text(sec.title, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
            ),
          LayoutBuilder(builder: (context, c) {
            final two = c.maxWidth >= 560;
            final half = (c.maxWidth - 12) / 2;
            return Wrap(spacing: 12, runSpacing: 12, children: [
              for (final f in sec.fields)
                SizedBox(
                  width: !two || f.full || f.kind == PmKind.multiline || f.kind == PmKind.score || f.kind == PmKind.toggle ? c.maxWidth : half,
                  child: _field(f),
                ),
            ]);
          }),
          const SizedBox(height: 10),
        ],
        Text('الحقول المعلّمة * مطلوبة.', style: TextStyle(color: sem.muted, fontSize: 12)),
      ]),
    );
  }
}

// =====================================================================
// صفحة سجل عامة: عنوان، بحث، تصفية، وقائمة بطاقات
// =====================================================================
class PmListScaffold extends StatelessWidget {
  const PmListScaffold({
    super.key,
    required this.title,
    this.subtitle,
    required this.icon,
    this.actions = const [],
    this.search,
    this.searchHint = 'بحث',
    this.onSearch,
    this.filters = const [],
    this.top = const [],
    required this.items,
    this.emptyTitle = 'لا سجلات بعد',
    this.emptyMessage,
  });

  final String title;
  final String? subtitle;
  final IconData icon;
  final List<Widget> actions;
  final TextEditingController? search;
  final String searchHint;
  final VoidCallback? onSearch;
  final List<Widget> filters;
  final List<Widget> top;
  final List<Widget> items;
  final String emptyTitle;
  final String? emptyMessage;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final sem = Sem.of(context);
    final q = search?.text.trim() ?? '';
    return PageBody(
      maxWidth: 1200,
      onRefresh: app.loadAll,
      children: [
        PageHeader(title: title, subtitle: subtitle, icon: icon, actions: actions),
        ...top,
        if (search != null) ...[
          TextField(
            controller: search,
            onChanged: (_) => onSearch?.call(),
            decoration: fieldDeco(searchHint,
                prefixIcon: const Icon(Icons.search_rounded),
                suffix: q.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () {
                          search!.clear();
                          onSearch?.call();
                        },
                      )),
          ),
          const SizedBox(height: 10),
        ],
        if (filters.isNotEmpty) ...[
          Wrap(spacing: 10, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.center, children: filters),
          const SizedBox(height: 14),
        ],
        if (items.isEmpty)
          EmptyState(title: emptyTitle, message: emptyMessage, icon: Icons.inbox_outlined)
        else
          Container(
            decoration: cardDecoration(context),
            clipBehavior: Clip.antiAlias,
            child: Material(
              type: MaterialType.transparency,
              child: Column(children: [
                for (var i = 0; i < items.length; i++) ...[
                  if (i > 0) Divider(height: 1, color: sem.rule),
                  items[i],
                ],
              ]),
            ),
          ),
      ],
    );
  }
}

/// فلتر بقائمة منسدلة بعرض ثابت.
Widget pmFilter(String label, String value, List<(String, String)> items, ValueChanged<String> onChanged, {double width = 200}) =>
    SizedBox(width: width, child: SelectField(label: label, value: value, items: items, onChanged: onChanged));

/// بطاقة سطر في السجل.
class PmTile extends StatelessWidget {
  const PmTile({
    super.key,
    this.code = '',
    required this.title,
    this.meta = '',
    this.badges = const [],
    this.leading,
    this.trailing,
    this.onTap,
  });

  final String code;
  final String title;
  final String meta;
  final List<Widget> badges;
  final Widget? leading;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final sem = Sem.of(context);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (leading != null) ...[leading!, const SizedBox(width: 12)],
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (code.isNotEmpty || meta.isNotEmpty)
                Row(children: [
                  if (code.isNotEmpty) Text(code, style: TextStyle(color: sem.muted, fontWeight: FontWeight.w800, fontSize: 12.5)),
                  if (meta.isNotEmpty) ...[
                    if (code.isNotEmpty) const SizedBox(width: 8),
                    Expanded(child: Text(meta, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: sem.muted, fontSize: 12.5))),
                  ],
                ]),
              const SizedBox(height: 2),
              Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, height: 1.35)),
              if (badges.isNotEmpty) ...[
                const SizedBox(height: 6),
                Wrap(spacing: 6, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: badges),
              ],
            ]),
          ),
          if (trailing != null) ...[const SizedBox(width: 10), trailing!],
        ]),
      ),
    );
  }
}

/// تفاصيل سجل في نافذة سفلية: عنوان وشارات وأزواج (عنوان، قيمة) وأزرار.
Future<void> showPmSheet(
  BuildContext context, {
  required String title,
  String code = '',
  List<Widget> badges = const [],
  required List<(String, String)> rows,
  List<Widget> extra = const [],
  List<Widget> Function(BuildContext sheet)? actions,
}) {
  final sem = Sem.of(context);
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) => SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.86),
        child: ListView(shrinkWrap: true, padding: const EdgeInsets.fromLTRB(20, 0, 20, 20), children: [
          if (code.isNotEmpty) Text(code, style: TextStyle(color: sem.muted, fontWeight: FontWeight.w800)),
          Text(title, style: Theme.of(ctx).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800, height: 1.4)),
          if (badges.isNotEmpty) ...[const SizedBox(height: 10), Wrap(spacing: 6, runSpacing: 6, children: badges)],
          const SizedBox(height: 14),
          for (final r in rows)
            if (r.$2.trim().isNotEmpty && r.$2 != '—')
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(r.$1, style: TextStyle(color: sem.muted, fontSize: 12.5)),
                  const SizedBox(height: 2),
                  Text(r.$2, style: const TextStyle(height: 1.4)),
                ]),
              ),
          ...extra,
          if (actions != null) ...[
            const SizedBox(height: 6),
            Wrap(spacing: 8, runSpacing: 8, children: actions(ctx)),
          ],
        ]),
      ),
    ),
  );
}

/// زر حذف (للمدير) بتأكيد، يغلق النافذة ثم يحذف.
Widget pmDeleteButton(BuildContext context, BuildContext sheet,
    {required String what, required Future<void> Function() onDelete, String? message}) {
  final sem = Sem.of(context);
  return TextButton.icon(
    style: TextButton.styleFrom(foregroundColor: sem.danger),
    icon: const Icon(Icons.delete_outline_rounded),
    label: const Text('حذف'),
    onPressed: () async {
      final ok = await confirmDialog(sheet,
          title: 'حذف $what', message: message ?? 'يُحذف السجل نهائياً، ويبقى أثره في سجل التدقيق.', confirmLabel: 'حذف', danger: true);
      if (!ok || !sheet.mounted) return;
      Navigator.of(sheet).pop();
      try {
        await onDelete();
        if (context.mounted) showToast(context, 'حُذف $what');
      } catch (e) {
        if (context.mounted) showToast(context, friendlyError(e), error: true);
      }
    },
  );
}

/// صف مؤشر بسيط (عنوان وقيمة) لجداول الملخص.
class PmKv extends StatelessWidget {
  const PmKv(this.label, this.value, {super.key, this.color});

  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final sem = Sem.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(children: [
        Expanded(child: Text(label, style: TextStyle(color: sem.muted, fontSize: 13))),
        const SizedBox(width: 8),
        Text(value,
            style: TextStyle(fontWeight: FontWeight.w800, color: color, fontFeatures: const [FontFeature.tabularFigures()])),
      ]),
    );
  }
}

/// جدول بسيط قابل للتمرير أفقياً.
class PmTable extends StatelessWidget {
  const PmTable({super.key, required this.columns, required this.rows, this.highlight});

  final List<String> columns;
  final List<List<String>> rows;

  /// تظليل صف (مثل الأسباب الحيوية في باريتو).
  final bool Function(int row)? highlight;

  @override
  Widget build(BuildContext context) {
    final sem = Sem.of(context);
    if (rows.isEmpty) return Text('لا بيانات بعد.', style: TextStyle(color: sem.muted));
    return LayoutBuilder(builder: (context, box) {
      // الجداول النصية القصيرة (عمودان أو ثلاثة) تلتف داخل عرض الهاتف بدل التمرير الأفقي
      const spacing = 18.0, margin = 8.0;
      final n = columns.length;
      final fit = n <= 3 && box.maxWidth.isFinite && box.maxWidth < 280.0 * n + spacing * (n - 1) + margin * 2;
      final cellMax = fit ? (box.maxWidth - margin * 2 - spacing * (n - 1)) / n : 280.0;
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          headingRowHeight: 40,
          dataRowMinHeight: 38,
          dataRowMaxHeight: fit ? 92 : 60,
          columnSpacing: spacing,
          horizontalMargin: margin,
          headingTextStyle: TextStyle(fontWeight: FontWeight.w800, color: sem.muted, fontSize: 12.5),
          columns: [for (final c in columns) DataColumn(label: Text(c))],
          rows: [
            for (var i = 0; i < rows.length; i++)
              DataRow(
                color: highlight != null && highlight!(i) ? WidgetStatePropertyAll(sem.wipSoft) : null,
                cells: [
                  for (final v in rows[i])
                    DataCell(ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: cellMax),
                      child: Text(v, maxLines: fit ? 5 : 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13)),
                    )),
                ],
              ),
          ],
        ),
      );
    });
  }
}
