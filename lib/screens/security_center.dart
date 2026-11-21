import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app_state.dart';
import '../chat.dart' show fileSizeText;
import '../models.dart';
import '../rasd.dart';
import '../ui/audit_text.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';
import '../units.dart';
import 'control/security.dart';
import 'control/security_ops.dart';

// =====================================================================
// مركز الأمن السيبراني (الترحيل 25): قسم مستقل لمسؤول الأمن ومدير المكتب.
// كل البيانات من دوال sec_* التي تتحقق من الصلاحية في قاعدة البيانات.
// =====================================================================

/// بيانات ثابتة للقطات البصرية بدل قاعدة البيانات (لا تُضبط في التطبيق).
Map<String, Object?>? secFixtures;

Future<Object?> _rpc(AppState app, String fn, [Map<String, dynamic>? params]) async {
  final f = secFixtures;
  if (f != null && f.containsKey(fn)) return f[fn];
  return app.client.rpc(fn, params: params);
}

Map<String, dynamic> _map(Object? v) => v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};
List<Map<String, dynamic>> _list(Object? v) => [for (final x in (v is List ? v : const [])) if (x is Map) Map<String, dynamic>.from(x)];
int _int(Object? v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;
DateTime? _dt(Object? v) => v == null ? null : DateTime.tryParse(v.toString())?.toLocal();
String _stamp(Object? v) {
  final d = _dt(v);
  return d == null ? '—' : '${fmtDate(d)} ${two(d.hour)}:${two(d.minute)}';
}

/// أسماء فئات سجل التدقيق (أول جزء من اسم الإجراء).
const Map<String, String> auditCategoryLabels = {
  'project': 'العقود',
  'form': 'النماذج',
  'finance': 'المالية',
  'extract': 'المستخلصات',
  'work': 'أعمال العقود',
  'user': 'المستخدمون',
  'security': 'الأمن',
  'setting': 'الإعدادات',
  'config': 'الإعدادات',
  'export': 'التصدير والطباعة',
  'print': 'قوالب الطباعة',
  'unit': 'سجلات الوحدات',
  'doc': 'المستندات الفنية',
  'report': 'تقارير الإشراف',
  'risk': 'المخاطر',
  'swot': 'SWOT',
  'pm': 'متابعة المشاريع',
  'chat': 'المراسلات',
  'ref': 'الأرقام الإشارية',
  'request': 'طلبات التعديل',
  'idea': 'الأفكار',
  'backup': 'النسخ الاحتياطي',
  'notification': 'الإشعارات',
};

String _cat(String k) => auditCategoryLabels[k] ?? k;

Color _sevColor(BuildContext context, String s) {
  final sem = Sem.of(context);
  return switch (s) {
    'critical' || 'high' => sem.danger,
    'warning' || 'medium' => sem.wip,
    'low' => Theme.of(context).colorScheme.primary,
    _ => sem.muted,
  };
}

String _sevLabel(String s) => switch (s) {
      'critical' => 'حرجة',
      'high' => 'عالية',
      'warning' || 'medium' => 'متوسطة',
      'low' => 'منخفضة',
      _ => 'معلومة',
    };

/// صفحة تحمّل بياناتها من قاعدة البيانات مع اختيار المدة والتحديث.
class _SecPage extends StatefulWidget {
  const _SecPage({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.load,
    required this.build,
    this.days = 30,
    this.periods = const [7, 30, 90],
    this.actions,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Future<Object?> Function(AppState app, int days) load;
  final List<Widget> Function(BuildContext context, Object? data, int days, VoidCallback reload) build;
  final int days;
  final List<int> periods;
  final List<Widget> Function(BuildContext context, VoidCallback reload)? actions;

  @override
  State<_SecPage> createState() => _SecPageState();
}

class _SecPageState extends State<_SecPage> {
  late int _days = widget.days;
  Object? _data;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    setState(() => _loading = true);
    try {
      final d = await widget.load(AppScope.read(context), _days);
      if (mounted) {
        setState(() {
          _data = d;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    if (!app.v13Ready || !app.canAudit) {
      return PageBody(children: [
        EmptyState(
          icon: Icons.shield_outlined,
          title: app.canAudit ? 'مركز الأمن السيبراني غير مفعّل بعد' : 'هذا القسم لمسؤول الأمن السيبراني ومدير المكتب',
          message: app.canAudit ? 'يعمل بعد تحديث قاعدة البيانات بالملف 20261119000025_security_center.sql.' : null,
        ),
      ]);
    }
    return PageBody(onRefresh: _reload, children: [
      PageHeader(
        title: widget.title,
        subtitle: widget.subtitle,
        icon: widget.icon,
        actions: [
          if (widget.periods.isNotEmpty)
            SegmentedButton<int>(
              showSelectedIcon: false,
              segments: [for (final d in widget.periods) ButtonSegment(value: d, label: Text('$d يوماً'))],
              selected: {_days},
              onSelectionChanged: (v) {
                setState(() => _days = v.first);
                _reload();
              },
            ),
          ...?widget.actions?.call(context, _reload),
          IconButton(tooltip: 'تحديث', onPressed: _loading ? null : _reload, icon: const Icon(Icons.refresh_rounded)),
        ],
      ),
      if (_error != null) InfoBanner(text: _error!, level: 'critical'),
      if (_loading && _data == null)
        const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator()))
      else if (_data != null)
        ...widget.build(context, _data, _days, _reload),
    ]);
  }
}

/// أعمدة بسيطة لسلسلة يومية.
class _Bars extends StatelessWidget {
  const _Bars({required this.values, required this.labels, this.overlay, this.height = 150});

  final List<num> values;
  final List<String> labels;
  final List<num>? overlay;
  final double height;

  @override
  Widget build(BuildContext context) {
    final sem = Sem.of(context);
    final cs = Theme.of(context).colorScheme;
    if (values.isEmpty) return SizedBox(height: height, child: Center(child: Text('لا نشاط في المدة', style: TextStyle(color: sem.muted))));
    final mx = values.fold<num>(1, (a, b) => math.max(a, b));
    return SizedBox(
      height: height + 22,
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          for (var i = 0; i < values.length; i++)
            Expanded(
              child: Tooltip(
                message: '${labels[i]}: ${values[i]}${overlay != null && overlay![i] > 0 ? ' (حذف ${overlay![i]})' : ''}',
                child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 1),
                    height: math.max(2, height * values[i] / mx),
                    decoration: BoxDecoration(color: cs.primary.withValues(alpha: 0.75), borderRadius: BorderRadius.circular(3)),
                    alignment: Alignment.bottomCenter,
                    child: overlay == null || overlay![i] <= 0
                        ? null
                        : Container(height: math.max(2, height * overlay![i] / mx), color: sem.danger),
                  ),
                  const SizedBox(height: 4),
                  SizedBox(
                    height: 18,
                    child: (values.length <= 14 || i % (values.length ~/ 10 + 1) == 0)
                        ? FittedBox(child: Text(labels[i], style: TextStyle(fontSize: 10, color: sem.muted)))
                        : null,
                  ),
                ]),
              ),
            ),
        ]),
      ),
    );
  }
}

/// خريطة النشاط: أيام الأسبوع × ساعات اليوم.
class _Heatmap extends StatelessWidget {
  const _Heatmap({required this.cells});

  final List<List<int>> cells; // [isodow, hour, n]

  @override
  Widget build(BuildContext context) {
    final sem = Sem.of(context);
    final cs = Theme.of(context).colorScheme;
    final grid = List.generate(7, (_) => List.filled(24, 0));
    var mx = 1;
    for (final c in cells) {
      if (c.length < 3) continue;
      final d = (c[0] - 1).clamp(0, 6);
      final h = c[1].clamp(0, 23);
      grid[d][h] += c[2];
      mx = math.max(mx, grid[d][h]);
    }
    const days = ['الاثنين', 'الثلاثاء', 'الأربعاء', 'الخميس', 'الجمعة', 'السبت', 'الأحد'];
    return Column(children: [
      for (var d = 0; d < 7; d++)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 1.5),
          child: Row(children: [
            SizedBox(width: 62, child: Text(days[d], style: TextStyle(fontSize: 11, color: d >= 4 && d <= 5 ? sem.danger : sem.muted))),
            Expanded(
              child: Directionality(
                textDirection: TextDirection.ltr,
                child: Row(children: [
                  for (var h = 0; h < 24; h++)
                    Expanded(
                      child: Tooltip(
                        message: '${days[d]} ${two(h)}:00 — ${grid[d][h]}',
                        child: Container(
                          height: 16,
                          margin: const EdgeInsets.symmetric(horizontal: 0.75),
                          decoration: BoxDecoration(
                            color: grid[d][h] == 0 ? sem.surface2 : cs.primary.withValues(alpha: 0.15 + 0.85 * grid[d][h] / mx),
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                      ),
                    ),
                ]),
              ),
            ),
          ]),
        ),
      Row(children: [
        const SizedBox(width: 62),
        Expanded(
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: Row(children: [
              for (var h = 0; h < 24; h++)
                Expanded(child: Center(child: Text(h % 3 == 0 ? '$h' : '', style: TextStyle(fontSize: 10, color: sem.muted)))),
            ]),
          ),
        ),
      ]),
    ]);
  }
}

Widget _meterRow(BuildContext context, String label, num value, num max, {Color? color, String? trailing}) {
  final sem = Sem.of(context);
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(children: [
      SizedBox(width: 150, child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis)),
      Expanded(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(99),
          child: LinearProgressIndicator(
            value: max <= 0 ? 0 : (value / max).clamp(0, 1).toDouble(),
            minHeight: 9,
            backgroundColor: sem.surface2,
            color: color ?? Theme.of(context).colorScheme.primary,
          ),
        ),
      ),
      const SizedBox(width: 10),
      SizedBox(width: 74, child: Text(trailing ?? '$value', textAlign: TextAlign.end, style: const TextStyle(fontWeight: FontWeight.w700))),
    ]),
  );
}

Future<void> _emergencyFreeze(BuildContext context, VoidCallback reload) async {
  final app = AppScope.read(context);
  final frozen = app.settings.frozen;
  if (frozen && !app.isDirector) {
    showToast(context, 'رفع التجميد من صلاحية مدير المكتب وحده.', error: true);
    return;
  }
  final reason = await textInputDialog(context,
      title: frozen ? 'رفع التجميد' : 'تجميد المنظومة فوراً',
      message: frozen
          ? 'تعود الكتابة لكل المستخدمين بصلاحياتهم المعتادة.'
          : 'تتوقف كل عمليات الكتابة لكل المستخدمين عدا مدير المكتب، وتبقى القراءة متاحة. رفع التجميد من صلاحية المدير وحده.',
      label: 'السبب (يُسجَّل في سجل التدقيق)',
      confirmLabel: frozen ? 'رفع التجميد' : 'تجميد الآن',
      required: true);
  if (reason == null) return;
  try {
    await _rpc(app, 'sec_freeze', {'p_on': !frozen, 'p_reason': reason});
    await app.loadAll();
    reload();
    if (context.mounted) showToast(context, frozen ? 'رُفع التجميد' : 'جُمّدت المنظومة');
  } catch (e) {
    if (context.mounted) showToast(context, friendlyError(e), error: true);
  }
}

// ---------------------------------------------------------------------
// لوحة الأمن
// ---------------------------------------------------------------------

class SecDashboardPage extends StatelessWidget {
  const SecDashboardPage({super.key});

  @override
  Widget build(BuildContext context) => _SecPage(
        title: 'لوحة الأمن السيبراني',
        subtitle: 'صورة شاملة لحالة المنظومة: الهويات والأجهزة والجلسات والنشاط والبيانات والمراسلات والحوادث.',
        icon: Icons.shield_outlined,
        actions: (context, reload) {
          final app = AppScope.of(context);
          final frozen = app.settings.frozen;
          return [
            if (!frozen || app.isDirector)
              FilledButton.tonalIcon(
                style: FilledButton.styleFrom(foregroundColor: frozen ? null : Sem.of(context).danger),
                onPressed: () => _emergencyFreeze(context, reload),
                icon: Icon(frozen ? Icons.lock_open_rounded : Icons.ac_unit_rounded),
                label: Text(frozen ? 'رفع التجميد' : 'تجميد طارئ'),
              ),
          ];
        },
        load: (app, days) async {
          final r = await Future.wait<dynamic>([
            _rpc(app, 'sec_dashboard', {'p_days': days}),
            _rpc(app, 'sec_posture'),
            _rpc(app, 'sec_anomalies', {'p_days': math.min(days, 30)}),
          ]);
          return (_map(r[0]), _list(r[1]), _list(r[2]));
        },
        build: (context, data, days, reload) {
          final (d, posture, anomalies) = data as (Map<String, dynamic>, List<Map<String, dynamic>>, List<Map<String, dynamic>>);
          final sem = Sem.of(context);
          final cs = Theme.of(context).colorScheme;
          final u = _map(d['users']);
          final dev = _map(d['devices']);
          final au = _map(d['audit']);
          final chat = _map(d['chat']);
          final refs = _map(d['refs']);
          final inc = _map(d['incidents']);
          final score = postureScore(posture);
          final failing = posture.where((p) => p['ok'] != true).toList();
          final daily = _list(d['daily']);
          final active = _int(u['active']);
          final mfa = _int(u['mfa']);
          return [
            if (d['freeze'] == true)
              const Padding(
                padding: EdgeInsets.only(bottom: 12),
                child: InfoBanner(text: 'المنظومة مجمّدة الآن: الكتابة متوقفة لكل المستخدمين عدا مدير المكتب.', level: 'critical', icon: Icons.ac_unit_rounded),
              ),
            LayoutBuilder(builder: (context, c) {
              final wide = c.maxWidth >= 760;
              final ring = SectionCard(
                title: 'مؤشر الوضع الأمني',
                child: Column(children: [
                  SizedBox(
                    width: 150,
                    height: 150,
                    child: Stack(alignment: Alignment.center, children: [
                      SizedBox.expand(
                        child: CircularProgressIndicator(
                          value: score / 100,
                          strokeWidth: 13,
                          backgroundColor: sem.surface2,
                          color: score >= 85 ? sem.ok : (score >= 65 ? sem.wip : sem.danger),
                        ),
                      ),
                      Column(mainAxisSize: MainAxisSize.min, children: [
                        Text('$score', style: const TextStyle(fontSize: 38, fontWeight: FontWeight.w900)),
                        Text('من 100', style: TextStyle(color: sem.muted)),
                      ]),
                    ]),
                  ),
                  const SizedBox(height: 10),
                  Text(failing.isEmpty ? 'كل الفحوص سليمة' : '${failing.length} فحصاً يحتاج معالجة', style: const TextStyle(fontWeight: FontWeight.w700)),
                ]),
              );
              final kpis = ResponsiveGrid(minItemWidth: 165, spacing: 10, children: [
                KpiTile(label: 'حساب مفعّل', value: '$active', sub: '${_int(u['pending'])} بانتظار التفعيل'),
                KpiTile(
                    label: 'تغطية التحقق بخطوتين',
                    value: active == 0 ? '—' : '${(100 * mfa / active).round()}%',
                    sub: '${_int(u['no_mfa_sensitive'])} حساباً حساساً دونه',
                    color: _int(u['no_mfa_sensitive']) > 0 ? sem.wip : sem.ok),
                KpiTile(label: 'حساب مقفل', value: '${_int(u['locked'])}', color: _int(u['locked']) > 0 ? sem.wip : null),
                KpiTile(label: 'حساب خامل (60 يوماً)', value: '${_int(u['stale_60'])}', color: _int(u['stale_60']) > 0 ? sem.wip : null),
                KpiTile(label: 'جلسة مفتوحة', value: d['sessions'] == null ? '—' : '${d['sessions']}'),
                KpiTile(label: 'جهاز نشط اليوم', value: '${_int(dev['active_24h'])}', sub: '${_int(dev['total'])} جهازاً معروفاً'),
                KpiTile(label: 'جهاز جديد', value: '${_int(dev['new'])}', sub: 'خلال $days يوماً'),
                KpiTile(label: 'جهاز محظور', value: '${_int(dev['blocked'])}', color: _int(dev['blocked']) > 0 ? sem.danger : null),
              ]);
              return wide
                  ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      SizedBox(width: 260, child: ring),
                      const SizedBox(width: 12),
                      Expanded(child: kpis),
                    ])
                  : Column(children: [ring, const SizedBox(height: 10), kpis]);
            }),
            const SizedBox(height: 12),
            ResponsiveGrid(minItemWidth: 165, spacing: 10, children: [
              KpiTile(label: 'حدث في سجل التدقيق', value: '${_int(au['events'])}', sub: '${_int(au['actors'])} مستخدماً'),
              KpiTile(label: 'عملية حذف', value: '${_int(au['deletes'])}', color: _int(au['deletes']) > 0 ? sem.wip : null),
              KpiTile(label: 'ملفاً مستخرجاً', value: '${_int(au['exports'])}'),
              KpiTile(label: 'خارج أوقات الدوام', value: '${_int(au['off_hours'])}', color: _int(au['off_hours']) > 0 ? sem.wip : null),
              KpiTile(label: 'تغيير إعدادات', value: '${_int(au['settings'])}'),
              KpiTile(label: 'نمط غير معتاد', value: '${anomalies.length}', color: anomalies.isNotEmpty ? sem.danger : sem.ok),
              KpiTile(label: 'تنبيه أمني', value: '${_int(d['alerts'])}', color: _int(d['alerts']) > 0 ? sem.wip : sem.ok),
              KpiTile(
                  label: 'حادثة مفتوحة',
                  value: '${_int(inc['open'])}',
                  sub: '${_int(inc['critical'])} عالية الخطورة',
                  color: _int(inc['critical']) > 0 ? sem.danger : null),
              KpiTile(label: 'رسالة داخلية', value: '${_int(chat['messages'])}', sub: '${_int(chat['locked_rooms'])} محادثة مقفلة'),
              KpiTile(label: 'حجم المرفقات', value: fileSizeText(_int(chat['bytes'])), sub: '${_int(chat['files'])} مرفقاً'),
              KpiTile(label: 'رقماً إشارياً صدر', value: '${_int(refs['issued'])}'),
              KpiTile(label: 'صلاحية دقيقة', value: '${_int(u['grants'])}', sub: '${_int(u['with_grants'])} مستخدماً'),
            ]),
            const SizedBox(height: 12),
            SectionCard(
              title: 'النشاط اليومي',
              subtitle: 'أحداث سجل التدقيق يومياً، والأحمر عمليات الحذف',
              child: _Bars(
                values: [for (final x in daily) _int(x['events'])],
                overlay: [for (final x in daily) _int(x['deletes'])],
                labels: [
                  for (final x in daily) (() {
                    final dt = DateTime.tryParse('${x['day']}');
                    return dt == null ? '' : '${dt.day}/${dt.month}';
                  })(),
                ],
              ),
            ),
            ResponsiveGrid(minItemWidth: 420, children: [
              SectionCard(
                title: 'خريطة النشاط',
                subtitle: 'متى يعمل المستخدمون (بتوقيت طرابلس)؛ الجمعة والسبت بالأحمر',
                child: _Heatmap(cells: [for (final c in (d['heatmap'] as List? ?? const [])) if (c is List) [for (final x in c) _int(x)]]),
              ),
              SectionCard(
                title: 'الأحداث حسب النوع',
                child: Builder(builder: (context) {
                  final cats = _list(d['categories']);
                  final mx = cats.isEmpty ? 1 : _int(cats.first['n']);
                  return Column(children: [
                    for (final c in cats.take(12)) _meterRow(context, _cat('${c['key']}'), _int(c['n']), mx),
                    if (cats.isEmpty) Text('لا أحداث', style: TextStyle(color: sem.muted)),
                  ]);
                }),
              ),
              SectionCard(
                title: 'الأكثر نشاطاً',
                child: Builder(builder: (context) {
                  final actors = _list(d['actors']);
                  final mx = actors.isEmpty ? 1 : _int(actors.first['n']);
                  return Column(children: [
                    for (final a in actors.take(10))
                      _meterRow(context, '${a['name'] ?? ''}', _int(a['n']), mx,
                          trailing: '${a['n']}${_int(a['deletes']) > 0 ? ' · ${a['deletes']}✕' : ''}',
                          color: _int(a['deletes']) > 5 ? sem.danger : null),
                    if (actors.isEmpty) Text('لا نشاط', style: TextStyle(color: sem.muted)),
                  ]);
                }),
              ),
              SectionCard(
                title: 'التخزين',
                child: Builder(builder: (context) {
                  final st = _list(d['storage']);
                  final mx = st.isEmpty ? 1 : _int(st.first['bytes']);
                  const names = {'docs': 'المستندات والمرفقات', 'chat': 'المراسلات', 'releases': 'إصدارات التطبيق'};
                  return Column(children: [
                    for (final b in st)
                      _meterRow(context, names[b['bucket']] ?? '${b['bucket']}', _int(b['bytes']), mx,
                          trailing: fileSizeText(_int(b['bytes']))),
                    if (st.isEmpty) Text('لا بيانات', style: TextStyle(color: sem.muted)),
                  ]);
                }),
              ),
              SectionCard(
                title: 'المستخدمون حسب الدور',
                child: Builder(builder: (context) {
                  final roles = _map(u['by_role']);
                  final mx = roles.values.fold<int>(1, (a, b) => math.max(a, _int(b)));
                  return Column(children: [
                    for (final e in roles.entries)
                      _meterRow(context, e.key == 'pending' ? 'بانتظار التفعيل' : (parseRole(e.key)?.label ?? e.key), _int(e.value), mx),
                  ]);
                }),
              ),
              SectionCard(
                title: 'فحوص تحتاج معالجة',
                child: failing.isEmpty
                    ? Row(children: [Icon(Icons.verified_rounded, color: sem.ok), const SizedBox(width: 8), const Text('كل الفحوص سليمة')])
                    : Column(children: [
                        for (final f in failing.take(8))
                          ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(Icons.error_outline_rounded, color: _sevColor(context, '${f['severity']}')),
                            title: Text('${f['title']}'),
                            subtitle: Text('${f['detail'] ?? ''}', maxLines: 2, overflow: TextOverflow.ellipsis),
                            trailing: f['count'] == null ? null : ToneBadge('${f['count']}', color: _sevColor(context, '${f['severity']}')),
                          ),
                      ]),
              ),
            ]),
            Text('آخر تحديث: ${_stamp(d['generated_at'])}', style: TextStyle(color: sem.muted, fontSize: 12)),
            Text(' ', style: TextStyle(color: cs.surface)),
          ];
        },
      );
}

/// مؤشر الوضع الأمني من 100: وزن الفحص العالي 3 والمتوسط 2 والمنخفض 1.
int postureScore(List<Map<String, dynamic>> checks) {
  var total = 0, ok = 0;
  for (final c in checks) {
    final w = switch ('${c['severity']}') { 'high' => 3, 'medium' => 2, _ => 1 };
    total += w;
    if (c['ok'] == true) ok += w;
  }
  return total == 0 ? 100 : (100 * ok / total).round();
}

// ---------------------------------------------------------------------
// الوضع الأمني
// ---------------------------------------------------------------------

class SecPosturePage extends StatelessWidget {
  const SecPosturePage({super.key});

  @override
  Widget build(BuildContext context) => _SecPage(
        title: 'الوضع الأمني',
        subtitle: 'فحص حيّ لقاعدة البيانات والتخزين والهويات والسياسات والصلاحيات والأجهزة، بالأرقام والعناصر المعنية.',
        icon: Icons.fact_check_outlined,
        periods: const [],
        load: (app, _) async => _list(await _rpc(app, 'sec_posture')),
        build: (context, data, _, __) {
          final checks = data as List<Map<String, dynamic>>;
          final sem = Sem.of(context);
          final groups = <String, List<Map<String, dynamic>>>{};
          for (final c in checks) {
            (groups['${c['group']}'] ??= []).add(c);
          }
          final score = postureScore(checks);
          return [
            InfoBanner(
              text: 'المؤشر $score من 100 — ${checks.where((c) => c['ok'] == true).length} فحصاً سليماً من ${checks.length}. '
                  'وزن الفحص عالي الخطورة 3 والمتوسط 2 والمنخفض 1.',
              level: score >= 85 ? 'ok' : (score >= 65 ? 'warning' : 'critical'),
            ),
            const SizedBox(height: 12),
            for (final g in groups.entries)
              SectionCard(
                title: g.key,
                child: Column(children: [
                  for (final c in g.value)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Icon(c['ok'] == true ? Icons.check_circle_rounded : Icons.cancel_rounded,
                            color: c['ok'] == true ? sem.ok : _sevColor(context, '${c['severity']}')),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Row(children: [
                              Expanded(child: Text('${c['title']}', style: const TextStyle(fontWeight: FontWeight.w700))),
                              ToneBadge(_sevLabel('${c['severity']}'), color: _sevColor(context, '${c['severity']}')),
                            ]),
                            Text('${c['detail'] ?? ''}', style: TextStyle(color: sem.muted, fontSize: 12.5)),
                            if (c['ok'] != true && (c['items'] as List? ?? const []).isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: Wrap(spacing: 6, runSpacing: 6, children: [
                                  for (final it in (c['items'] as List).take(16))
                                    Chip(label: Text('$it', style: const TextStyle(fontSize: 12)), visualDensity: VisualDensity.compact),
                                  if ((c['items'] as List).length > 16) Chip(label: Text('+${(c['items'] as List).length - 16}')),
                                ]),
                              ),
                          ]),
                        ),
                      ]),
                    ),
                ]),
              ),
          ];
        },
      );
}

// ---------------------------------------------------------------------
// التنبيهات والأنماط غير المعتادة
// ---------------------------------------------------------------------

const Map<String, String> _anomalyLabels = {
  'mass_delete': 'حذف كثير',
  'mass_export': 'تصدير كثيف',
  'off_hours': 'خارج الدوام',
  'privilege': 'صلاحيات وإعدادات',
  'new_device': 'جهاز جديد',
  'chat_volume': 'مرفقات كبيرة',
  'blocked_device': 'جهاز محظور',
};

class SecAlertsPage extends StatelessWidget {
  const SecAlertsPage({super.key});

  @override
  Widget build(BuildContext context) => _SecPage(
        title: 'التنبيهات والأنماط غير المعتادة',
        subtitle: 'تنبيهات الحسابات والأجهزة، وأنماط تكشفها قواعد ثابتة: حذف كثير في ساعة، وتصدير كثيف، وعمل خارج الدوام، وتغييرات الصلاحيات.',
        icon: Icons.notification_important_outlined,
        days: 7,
        periods: const [1, 7, 30],
        load: (app, days) async {
          final r = await Future.wait<dynamic>([_rpc(app, 'security_alerts'), _rpc(app, 'sec_anomalies', {'p_days': days})]);
          return (_list(r[0]), _list(r[1]));
        },
        build: (context, data, days, reload) {
          final (alerts, anomalies) = data as (List<Map<String, dynamic>>, List<Map<String, dynamic>>);
          final sem = Sem.of(context);
          final items = [
            for (final a in alerts) {...a, '_src': 'alert', 'severity': a['level'] ?? 'info'},
            for (final a in anomalies) {...a, '_src': 'anomaly'},
          ]..sort((a, b) => '${b['at']}'.compareTo('${a['at']}'));
          int count(String s) => items.where((x) => x['severity'] == s || (s == 'high' && x['severity'] == 'critical')).length;
          return [
            ResponsiveGrid(minItemWidth: 170, children: [
              KpiTile(label: 'عالية الخطورة', value: '${count('high')}', color: count('high') > 0 ? sem.danger : sem.ok),
              KpiTile(label: 'متوسطة', value: '${items.where((x) => x['severity'] == 'medium' || x['severity'] == 'warning').length}'),
              KpiTile(label: 'منخفضة ومعلومات', value: '${items.where((x) => x['severity'] == 'low' || x['severity'] == 'info').length}'),
            ]),
            const SizedBox(height: 12),
            if (items.isEmpty)
              const EmptyState(icon: Icons.verified_outlined, title: 'لا تنبيهات', message: 'لم تُرصد أنماط غير معتادة في المدة المختارة.')
            else
              SectionCard(
                title: 'التنبيهات (${items.length})',
                padding: EdgeInsets.zero,
                child: Column(children: [
                  for (final a in items)
                    ListTile(
                      leading: Icon(a['_src'] == 'alert' ? Icons.campaign_outlined : Icons.radar_rounded, color: _sevColor(context, '${a['severity']}')),
                      title: Text('${a['title'] ?? ''}'),
                      subtitle: Text([
                        if ((a['name'] ?? '').toString().isNotEmpty) '${a['name']}',
                        _anomalyLabels[a['kind']] ?? (a['_src'] == 'alert' ? 'تنبيه' : '${a['kind']}'),
                        _stamp(a['at']),
                      ].join(' · ')),
                      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                        ToneBadge(_sevLabel('${a['severity']}'), color: _sevColor(context, '${a['severity']}')),
                        IconButton(
                          tooltip: 'تسجيل كحادثة',
                          icon: const Icon(Icons.report_gmailerrorred_outlined),
                          onPressed: () => showDialog<void>(
                            context: context,
                            builder: (_) => IncidentDialog(prefill: {
                              'title': '${a['title'] ?? ''}',
                              'severity': switch ('${a['severity']}') { 'critical' => 'critical', 'high' => 'high', 'low' || 'info' => 'low', _ => 'medium' },
                              'category': switch ('${a['kind']}') {
                                'mass_export' || 'mass_delete' => 'data',
                                'new_device' || 'blocked_device' || 'blocked_device_active' => 'device',
                                'privilege' => 'access',
                                'chat_volume' => 'chat',
                                _ => 'account',
                              },
                              'user_id': a['user_id'],
                              'details': '${a['title'] ?? ''} — ${_stamp(a['at'])}',
                            }),
                          ),
                        ),
                      ]),
                    ),
                ]),
              ),
          ];
        },
      );
}

// ---------------------------------------------------------------------
// الهويات والصلاحيات
// ---------------------------------------------------------------------

class SecIdentityPage extends StatefulWidget {
  const SecIdentityPage({super.key});

  @override
  State<SecIdentityPage> createState() => _SecIdentityPageState();
}

class _SecIdentityPageState extends State<SecIdentityPage> {
  final _q = TextEditingController();
  String _filter = 'all';

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  Future<void> _act(BuildContext context, Map<String, dynamic> u, String a, VoidCallback reload) async {
    final app = AppScope.read(context);
    final id = '${u['id']}';
    try {
      switch (a) {
        case 'lock':
          final reason = await textInputDialog(context,
              title: 'قفل دخول ${u['name']}', label: 'السبب', confirmLabel: 'قفل وإخراج من كل الأجهزة', required: true);
          if (reason == null) return;
          await app.lockUser(id, reason: reason);
        case 'unlock':
          await app.unlockUser(id);
        case 'revoke':
          final n = await app.revokeUserSessions(id);
          if (context.mounted) showToast(context, 'أُغلقت $n جلسة');
        case 'grants':
          final reason = await textInputDialog(context,
              title: 'تعليق الصلاحيات الدقيقة',
              message: 'تُسحب كل الصلاحيات الدقيقة الممنوحة لـ ${u['name']}، ويعيد المدير منحها بعد التحقق.',
              label: 'السبب',
              confirmLabel: 'تعليق',
              required: true);
          if (reason == null) return;
          final n = await app.suspendGrants(id, reason);
          if (context.mounted) showToast(context, 'عُلّقت $n صلاحية');
        case 'timeline':
          await showDialog<void>(context: context, builder: (_) => _TimelineDialog(userId: id, name: '${u['name']}'));
          return;
      }
      reload();
    } catch (e) {
      if (context.mounted) showToast(context, friendlyError(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) => _SecPage(
        title: 'الهويات والصلاحيات',
        subtitle: 'كل مستخدم بدوره وقسمه ووحدته، والتحقق بخطوتين، وآخر ظهور وأجهزته، والنماذج التي يكتب فيها فعلاً، وصلاحياته الدقيقة ونشاطه.',
        icon: Icons.badge_outlined,
        periods: const [],
        load: (app, _) async => _list(await _rpc(app, 'sec_access_matrix')),
        build: (context, data, _, reload) {
          final app = AppScope.of(context);
          final sem = Sem.of(context);
          final rows = data as List<Map<String, dynamic>>;
          final q = _q.text.trim();
          final list = rows.where((u) {
            if (q.isNotEmpty && !'${u['name']} ${u['email']}'.contains(q)) return false;
            return switch (_filter) {
              'nomfa' => u['active'] == true && u['mfa'] != true,
              'locked' => u['locked'] == true,
              'grants' => (u['grants'] as List? ?? const []).isNotEmpty,
              'inactive' => u['active'] != true,
              _ => true,
            };
          }).toList();
          return [
            Row(children: [
              Expanded(
                child: TextField(
                  controller: _q,
                  onChanged: (_) => setState(() {}),
                  decoration: fieldDeco('بحث بالاسم أو البريد', prefixIcon: const Icon(Icons.search_rounded)),
                ),
              ),
            ]),
            const SizedBox(height: 8),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final f in const [('all', 'الكل'), ('nomfa', 'دون تحقق بخطوتين'), ('locked', 'مقفلون'), ('grants', 'لهم صلاحيات دقيقة'), ('inactive', 'غير مفعّلين')])
                ChoiceChip(label: Text(f.$2), selected: _filter == f.$1, showCheckmark: false, onSelected: (_) => setState(() => _filter = f.$1)),
            ]),
            const SizedBox(height: 10),
            ResponsiveGrid(minItemWidth: 380, children: [
              for (final u in list)
                SectionCard(
                  title: '${u['name']}',
                  subtitle: [
                    parseRole(u['role'])?.label ?? 'بانتظار التفعيل',
                    if ((u['department'] ?? '').toString().isNotEmpty)
                      app.departments.where((d) => d.key == u['department']).map((d) => d.name).firstOrNull ?? '${u['department']}',
                    if (u['unit'] != null) '${unitNames[u['unit']] ?? u['unit']}${u['unit_head'] == true ? ' (رئيس)' : ''}',
                  ].join(' · '),
                  trailing: PopupMenuButton<String>(
                    onSelected: (a) => _act(context, u, a, reload),
                    itemBuilder: (_) => [
                      const PopupMenuItem(value: 'timeline', child: Text('سجل حركته')),
                      if (u['role'] != 'director') ...[
                        PopupMenuItem(value: u['locked'] == true ? 'unlock' : 'lock', child: Text(u['locked'] == true ? 'فك قفل الدخول' : 'قفل الدخول')),
                        const PopupMenuItem(value: 'revoke', child: Text('إخراج من كل الأجهزة')),
                        if ((u['grants'] as List? ?? const []).isNotEmpty) const PopupMenuItem(value: 'grants', child: Text('تعليق الصلاحيات الدقيقة')),
                      ],
                    ],
                  ),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Wrap(spacing: 6, runSpacing: 6, children: [
                      ToneBadge(u['mfa'] == true ? 'تحقق بخطوتين' : 'دون تحقق بخطوتين',
                          color: u['mfa'] == true ? sem.ok : sem.wip, icon: u['mfa'] == true ? Icons.verified_user_outlined : Icons.gpp_maybe_outlined),
                      if (u['locked'] == true) ToneBadge('مقفل', color: sem.danger, icon: Icons.lock_rounded),
                      if (u['active'] != true) ToneBadge('غير مفعّل', color: sem.muted),
                      ToneBadge('${u['devices']} جهاز', color: Theme.of(context).colorScheme.primary, icon: Icons.devices_outlined),
                    ]),
                    const SizedBox(height: 8),
                    Text('${u['email'] ?? ''} · آخر ظهور: ${_stamp(u['last_seen'])}', style: TextStyle(color: sem.muted, fontSize: 12)),
                    const SizedBox(height: 8),
                    _meterRow(context, 'النماذج التي يكتب فيها', _int(u['forms']), _int(u['forms_total']), trailing: '${u['forms']}/${u['forms_total']}'),
                    const SizedBox(height: 4),
                    Text('خلال 30 يوماً: ${u['events_30d']} حدثاً · ${u['deletes_30d']} حذفاً · ${u['exports_30d']} تصديراً · ${u['messages_30d']} رسالة',
                        style: TextStyle(fontSize: 12.5, color: sem.muted)),
                    if ((u['grants'] as List? ?? const []).isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Wrap(spacing: 4, runSpacing: 4, children: [
                        for (final g in (u['grants'] as List))
                          Chip(
                            visualDensity: VisualDensity.compact,
                            avatar: const Icon(Icons.key_rounded, size: 14),
                            label: Text(grantLabel('$g', app.allFormDefs), style: const TextStyle(fontSize: 11.5)),
                          ),
                      ]),
                    ],
                  ]),
                ),
            ]),
          ];
        },
      );
}

class _TimelineDialog extends StatelessWidget {
  const _TimelineDialog({required this.userId, required this.name});

  final String userId;
  final String name;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final sem = Sem.of(context);
    return AlertDialog(
      title: Text('سجل حركة $name (30 يوماً)'),
      content: SizedBox(
        width: 620,
        height: 520,
        child: FutureBuilder<Object?>(
          future: _rpc(app, 'sec_audit_search', {'p_actor': userId, 'p_from': DateTime.now().subtract(const Duration(days: 30)).toUtc().toIso8601String(), 'p_limit': 800}),
          builder: (_, s) {
            if (s.hasError) return Center(child: Text(friendlyError(s.error!)));
            if (!s.hasData) return const Center(child: CircularProgressIndicator());
            final rows = [for (final r in _list(s.data)) AuditEntry.fromMap(r)];
            if (rows.isEmpty) return Center(child: Text('لا حركة', style: TextStyle(color: sem.muted)));
            return ListView(children: [
              for (final e in rows)
                ListTile(
                  dense: true,
                  title: Text(auditDescription(app, e)),
                  subtitle: Text('${auditActionLabels[e.action] ?? e.action} · ${_stamp(e.at?.toIso8601String())}'),
                ),
            ]);
          },
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('إغلاق'))],
    );
  }
}

// ---------------------------------------------------------------------
// الجلسات والأجهزة، والسياسات: الأقسام الموجودة في لوحة التحكم
// ---------------------------------------------------------------------

class SecSessionsPage extends StatelessWidget {
  const SecSessionsPage({super.key});

  @override
  Widget build(BuildContext context) => const SecurityOpsSection();
}

class SecPoliciesPage extends StatelessWidget {
  const SecPoliciesPage({super.key});

  @override
  Widget build(BuildContext context) => const SecuritySection();
}

// ---------------------------------------------------------------------
// نشاط البيانات
// ---------------------------------------------------------------------

class SecDataPage extends StatefulWidget {
  const SecDataPage({super.key});

  @override
  State<SecDataPage> createState() => _SecDataPageState();
}

class _SecDataPageState extends State<SecDataPage> {
  String _tab = 'exports';

  @override
  Widget build(BuildContext context) => _SecPage(
        title: 'نشاط البيانات',
        subtitle: 'ما خرج من المنظومة وما حُذف منها وما رُفع إليها: الملفات المستخرجة، وعمليات الحذف، والأرقام الإشارية، والمرفقات، وتغييرات الإعدادات.',
        icon: Icons.dataset_outlined,
        load: (app, days) async => _map(await _rpc(app, 'sec_data_activity', {'p_days': days})),
        build: (context, data, days, _) {
          final d = data as Map<String, dynamic>;
          final sem = Sem.of(context);
          final up = _map(d['uploads_total']);
          final fm = _map(d['export_formats']);
          final rows = _list(d[_tab]);
          Widget tile(Map<String, dynamic> r) => switch (_tab) {
                'exports' => ListTile(
                    dense: true,
                    leading: const Icon(Icons.file_download_outlined),
                    title: Text('${r['title'] ?? r['source'] ?? 'ملف'}'),
                    subtitle: Text([
                      '${r['name'] ?? ''}',
                      '${(r['format'] ?? '').toString().toUpperCase()}',
                      if (r['rows'] != null) '${r['rows']} صفاً',
                      if (r['bytes'] != null) fileSizeText(_int(r['bytes'])),
                    ].where((x) => x.isNotEmpty).join(' · ')),
                    trailing: Text(_stamp(r['at']), style: TextStyle(fontSize: 12, color: sem.muted)),
                  ),
                'deletes' => ListTile(
                    dense: true,
                    leading: Icon(Icons.delete_outline_rounded, color: sem.danger),
                    title: Text(auditActionLabels['${r['action']}'] ?? '${r['action']}'),
                    subtitle: Text('${r['name'] ?? ''} · ${r['label'] ?? ''}'),
                    trailing: Text(_stamp(r['at']), style: TextStyle(fontSize: 12, color: sem.muted)),
                  ),
                'refs' => ListTile(
                    dense: true,
                    leading: const Icon(Icons.tag_rounded),
                    title: Directionality(textDirection: TextDirection.ltr, child: Text('${r['ref']}', textAlign: TextAlign.end)),
                    subtitle: Text([r['scheme'], r['title'], r['by']].where((x) => x != null && '$x'.isNotEmpty).join(' · ')),
                    trailing: Text(_stamp(r['at']), style: TextStyle(fontSize: 12, color: sem.muted)),
                  ),
                'uploads' => ListTile(
                    dense: true,
                    leading: const Icon(Icons.upload_file_outlined),
                    title: Text('${r['name'] ?? ''}'),
                    subtitle: Text('${r['by'] ?? ''} · ${r['where'] ?? ''} · ${fileSizeText(_int(r['size']))}'),
                    trailing: Text(_stamp(r['at']), style: TextStyle(fontSize: 12, color: sem.muted)),
                  ),
                _ => ListTile(
                    dense: true,
                    leading: const Icon(Icons.tune_rounded),
                    title: Text('${r['key'] ?? ''}'),
                    subtitle: Text('${r['name'] ?? ''}', maxLines: 1),
                    trailing: Text(_stamp(r['at']), style: TextStyle(fontSize: 12, color: sem.muted)),
                  ),
              };
          return [
            ResponsiveGrid(minItemWidth: 170, children: [
              KpiTile(label: 'ملفاً مستخرجاً', value: '${_list(d['exports']).length}', sub: fm.entries.map((e) => '${e.key.toUpperCase()} ${e.value}').join(' · ')),
              KpiTile(label: 'عملية حذف', value: '${_list(d['deletes']).length}'),
              KpiTile(label: 'رقماً إشارياً', value: '${_list(d['refs']).length}'),
              KpiTile(label: 'مرفقاً مرفوعاً', value: '${_list(d['uploads']).length}', sub: 'الإجمالي ${_int(up['files'])} · ${fileSizeText(_int(up['bytes']))}'),
              KpiTile(label: 'تغيير إعدادات', value: '${_list(d['settings']).length}'),
            ]),
            const SizedBox(height: 12),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SegmentedButton<String>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: 'exports', label: Text('التصدير والطباعة')),
                  ButtonSegment(value: 'deletes', label: Text('الحذف')),
                  ButtonSegment(value: 'refs', label: Text('الأرقام الإشارية')),
                  ButtonSegment(value: 'uploads', label: Text('الملفات المرفوعة')),
                  ButtonSegment(value: 'settings', label: Text('الإعدادات')),
                ],
                selected: {_tab},
                onSelectionChanged: (v) => setState(() => _tab = v.first),
              ),
            ),
            const SizedBox(height: 10),
            if (rows.isEmpty)
              const EmptyState(icon: Icons.inbox_outlined, title: 'لا شيء في المدة المختارة')
            else
              SectionCard(title: '${rows.length} عنصراً', padding: EdgeInsets.zero, child: Column(children: [for (final r in rows) tile(r)])),
          ];
        },
      );
}

// ---------------------------------------------------------------------
// سجل التدقيق الكامل
// ---------------------------------------------------------------------

class SecAuditPage extends StatefulWidget {
  const SecAuditPage({super.key});

  @override
  State<SecAuditPage> createState() => _SecAuditPageState();
}

class _SecAuditPageState extends State<SecAuditPage> {
  final _text = TextEditingController();
  String _actor = '';
  String _prefix = '';
  int _days = 30;
  List<AuditEntry>? _rows;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _search());
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final app = AppScope.read(context);
    setState(() => _busy = true);
    try {
      final res = await _rpc(app, 'sec_audit_search', {
        'p_from': _days == 0 ? null : DateTime.now().subtract(Duration(days: _days)).toUtc().toIso8601String(),
        'p_actor': _actor.isEmpty ? null : _actor,
        'p_prefix': _prefix.isEmpty ? null : '$_prefix.',
        'p_text': _text.text.trim().isEmpty ? null : _text.text.trim(),
        'p_limit': 2000,
      });
      if (mounted) {
        setState(() {
          _rows = [for (final r in _list(res)) AuditEntry.fromMap(r)];
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final sem = Sem.of(context);
    if (!app.v13Ready || !app.canAudit) return const SecDashboardPage();
    final people = app.people.values.toList()..sort((a, b) => a.displayName.compareTo(b.displayName));
    final rows = _rows ?? const <AuditEntry>[];
    return PageBody(children: [
      const PageHeader(
        title: 'سجل التدقيق',
        subtitle: 'بحث في السجل كاملاً بالمستخدم والنوع والمدة والنص، حتى 2000 حدث في المرة.',
        icon: Icons.manage_search_outlined,
      ),
      Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.end, children: [
        SizedBox(
          width: 260,
          child: TextField(
            controller: _text,
            onSubmitted: (_) => _search(),
            decoration: fieldDeco('نص في العقد أو المستخدم أو التفاصيل', prefixIcon: const Icon(Icons.search_rounded)),
          ),
        ),
        SizedBox(
          width: 220,
          child: SelectField(
            label: 'المستخدم',
            value: _actor,
            items: [('', 'كل المستخدمين'), for (final p in people) (p.id, p.displayName)],
            onChanged: (v) => setState(() => _actor = v),
          ),
        ),
        SizedBox(
          width: 200,
          child: SelectField(
            label: 'النوع',
            value: _prefix,
            items: [('', 'كل الأنواع'), for (final e in auditCategoryLabels.entries) (e.key, e.value)],
            onChanged: (v) => setState(() => _prefix = v),
          ),
        ),
        SizedBox(
          width: 160,
          child: SelectField(
            label: 'المدة',
            value: '$_days',
            items: const [('1', 'يوم'), ('7', 'أسبوع'), ('30', 'شهر'), ('90', 'ثلاثة أشهر'), ('365', 'سنة'), ('0', 'كل السجل')],
            onChanged: (v) => setState(() => _days = int.parse(v)),
          ),
        ),
        FilledButton.icon(onPressed: _busy ? null : _search, icon: const Icon(Icons.search_rounded), label: const Text('بحث')),
      ]),
      const SizedBox(height: 12),
      if (_error != null) InfoBanner(text: _error!, level: 'critical'),
      if (_busy && _rows == null)
        const Padding(padding: EdgeInsets.all(30), child: Center(child: CircularProgressIndicator()))
      else if (rows.isEmpty)
        const EmptyState(icon: Icons.manage_search_outlined, title: 'لا نتائج')
      else
        SectionCard(
          title: '${rows.length} حدثاً',
          padding: EdgeInsets.zero,
          child: Column(children: [
            for (final e in rows.take(600))
              ListTile(
                dense: true,
                leading: Icon(e.action.contains('delete') ? Icons.delete_outline_rounded : Icons.history_rounded,
                    color: e.action.contains('delete') ? sem.danger : sem.muted),
                title: Text(auditDescription(app, e)),
                subtitle: Text('${e.actorName} · ${auditActionLabels[e.action] ?? e.action}${e.projectLabel.isNotEmpty ? ' · ${e.projectLabel}' : ''}'),
                trailing: Text(_stamp(e.at?.toIso8601String()), style: TextStyle(fontSize: 12, color: sem.muted)),
              ),
            if (rows.length > 600)
              Padding(padding: const EdgeInsets.all(12), child: Text('يُعرض أول 600؛ ضيّق البحث لرؤية الباقي.', style: TextStyle(color: sem.muted))),
          ]),
        ),
    ]);
  }
}

// ---------------------------------------------------------------------
// مراقبة المراسلات (بيانات وصفية فقط)
// ---------------------------------------------------------------------

class SecChatPage extends StatelessWidget {
  const SecChatPage({super.key});

  Future<void> _lock(BuildContext context, Map<String, dynamic> r, VoidCallback reload) async {
    final app = AppScope.read(context);
    try {
      if (r['locked'] == true) {
        await app.chat.setLock('${r['id']}', false, '');
      } else {
        final reason = await textInputDialog(context,
            title: 'قفل «${r['title']}»', label: 'سبب القفل', confirmLabel: 'قفل', required: true, message: 'لا تُرسل رسائل حتى تُفتح.');
        if (reason == null) return;
        await app.chat.setLock('${r['id']}', true, reason);
      }
      reload();
    } catch (e) {
      if (context.mounted) showToast(context, friendlyError(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) => _SecPage(
        title: 'مراقبة المراسلات',
        subtitle: 'البيانات الوصفية فقط: من راسل من ومتى، وعدد الرسائل وأنواع المرفقات وأحجامها. لا تظهر نصوص الرسائل ولا محتوى المرفقات ولا أسماء الملفات.',
        icon: Icons.mark_chat_read_outlined,
        load: (app, days) async => _map(await _rpc(app, 'sec_chat_overview', {'p_days': days})),
        build: (context, data, days, reload) {
          final d = data as Map<String, dynamic>;
          final sem = Sem.of(context);
          final t = _map(d['totals']);
          final daily = _list(d['daily']);
          final rooms = _list(d['rooms']);
          final kinds = {'dm': 'خاصة', 'group': 'مجموعة', 'channel': 'قناة'};
          return [
            const InfoBanner(
              text: 'خصوصية المراسلات محفوظة: قاعدة البيانات لا تعيد لهذه الصفحة نص أي رسالة ولا محتوى أي مرفق، حتى لمدير المكتب.',
              icon: Icons.privacy_tip_outlined,
            ),
            const SizedBox(height: 12),
            ResponsiveGrid(minItemWidth: 160, spacing: 10, children: [
              KpiTile(label: 'رسالة', value: '${_int(t['messages'])}', sub: '${_int(t['senders'])} مرسلاً'),
              KpiTile(label: 'مرفق', value: '${_int(t['files'])}', sub: fileSizeText(_int(t['bytes']))),
              KpiTile(label: 'محادثة', value: '${_int(t['rooms'])}', sub: '${_int(t['dm'])} خاصة · ${_int(t['groups'])} مجموعة · ${_int(t['channels'])} قناة'),
              KpiTile(label: 'مقفلة', value: '${_int(t['locked'])}', color: _int(t['locked']) > 0 ? sem.danger : null),
              KpiTile(label: 'محذوفة', value: '${_int(t['deleted'])}', sub: '${_int(t['edited'])} معدّلة'),
              KpiTile(label: 'خارج الدوام', value: '${_int(t['off_hours'])}', color: _int(t['off_hours']) > 0 ? sem.wip : null),
            ]),
            const SizedBox(height: 12),
            SectionCard(
              title: 'الرسائل يومياً',
              child: _Bars(
                values: [for (final x in daily) _int(x['messages'])],
                labels: [
                  for (final x in daily) (() {
                    final dt = DateTime.tryParse('${x['day']}');
                    return dt == null ? '' : '${dt.day}/${dt.month}';
                  })(),
                ],
              ),
            ),
            ResponsiveGrid(minItemWidth: 420, children: [
              SectionCard(
                title: 'أكثر المرسلين',
                child: Builder(builder: (context) {
                  final s = _list(d['senders']);
                  final mx = s.isEmpty ? 1 : _int(s.first['messages']);
                  return Column(children: [
                    for (final x in s.take(12))
                      _meterRow(context, '${x['name']}', _int(x['messages']), mx,
                          trailing: '${x['messages']}${_int(x['bytes']) > 0 ? ' · ${fileSizeText(_int(x['bytes']))}' : ''}'),
                    if (s.isEmpty) Text('لا رسائل', style: TextStyle(color: sem.muted)),
                  ]);
                }),
              ),
              SectionCard(
                title: 'من راسل من',
                child: Builder(builder: (context) {
                  final p = _list(d['pairs']);
                  return Column(children: [
                    for (final x in p.take(14))
                      ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.east_rounded, size: 18),
                        title: Text('${x['from']} ← ${x['to']}', maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Text('${kinds[x['kind']] ?? ''} · آخرها ${_stamp(x['last_at'])}'),
                        trailing: Text('${x['messages']}', style: const TextStyle(fontWeight: FontWeight.w800)),
                      ),
                    if (p.isEmpty) Text('لا رسائل', style: TextStyle(color: sem.muted)),
                  ]);
                }),
              ),
              SectionCard(
                title: 'أنواع المرفقات',
                child: Builder(builder: (context) {
                  final ty = _list(d['types']);
                  final mx = ty.isEmpty ? 1 : _int(ty.first['bytes']);
                  const names = {'image': 'صور', 'video': 'فيديو', 'audio': 'صوت', 'application': 'مستندات', 'text': 'نصوص'};
                  return Column(children: [
                    for (final x in ty) _meterRow(context, names[x['type']] ?? '${x['type']}', _int(x['bytes']), mx, trailing: '${x['files']} · ${fileSizeText(_int(x['bytes']))}'),
                    if (ty.isEmpty) Text('لا مرفقات', style: TextStyle(color: sem.muted)),
                  ]);
                }),
              ),
              SectionCard(
                title: 'أكبر المرفقات',
                child: Builder(builder: (context) {
                  final l = _list(d['large']);
                  return Column(children: [
                    for (final x in l.take(10))
                      ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text('${x['sender']} ← ${x['room']}', maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Text('${x['mime'] ?? ''} · ${_stamp(x['at'])}${x['deleted'] == true ? ' · محذوف' : ''}'),
                        trailing: Text(fileSizeText(_int(x['size'])), style: const TextStyle(fontWeight: FontWeight.w800)),
                      ),
                    if (l.isEmpty) Text('لا مرفقات', style: TextStyle(color: sem.muted)),
                  ]);
                }),
              ),
            ]),
            SectionCard(
              title: 'المحادثات (${rooms.length})',
              padding: EdgeInsets.zero,
              child: Column(children: [
                for (final r in rooms)
                  ListTile(
                    leading: Icon(
                        switch (r['kind']) { 'dm' => Icons.person_outline_rounded, 'group' => Icons.groups_outlined, _ => Icons.campaign_outlined },
                        color: r['locked'] == true ? sem.danger : sem.muted),
                    title: Text('${r['title']}', maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text([
                      kinds[r['kind']] ?? '',
                      '${r['members']} عضواً',
                      '${r['messages']} رسالة في $days يوماً',
                      if (_int(r['bytes']) > 0) fileSizeText(_int(r['bytes'])),
                      'آخر نشاط ${_stamp(r['last_at'])}',
                      if (r['locked'] == true) 'مقفلة: ${r['lock_reason']}',
                    ].join(' · ')),
                    trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                      IconButton(
                        tooltip: 'السجل الوصفي',
                        icon: const Icon(Icons.list_alt_rounded),
                        onPressed: () => showDialog<void>(context: context, builder: (_) => _RoomLogDialog(room: r)),
                      ),
                      IconButton(
                        tooltip: r['locked'] == true ? 'فتح' : 'قفل',
                        icon: Icon(r['locked'] == true ? Icons.lock_open_rounded : Icons.lock_outline_rounded),
                        onPressed: () => _lock(context, r, reload),
                      ),
                    ]),
                  ),
              ]),
            ),
          ];
        },
      );
}

class _RoomLogDialog extends StatelessWidget {
  const _RoomLogDialog({required this.room});

  final Map<String, dynamic> room;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final sem = Sem.of(context);
    return AlertDialog(
      title: Text('السجل الوصفي: ${room['title']}'),
      content: SizedBox(
        width: 600,
        height: 520,
        child: FutureBuilder<Object?>(
          future: _rpc(app, 'sec_chat_room_log', {'p_room': room['id'], 'p_limit': 1000}),
          builder: (_, s) {
            if (s.hasError) return Center(child: Text(friendlyError(s.error!)));
            if (!s.hasData) return const Center(child: CircularProgressIndicator());
            final rows = _list(s.data);
            if (rows.isEmpty) return Center(child: Text('لا رسائل', style: TextStyle(color: sem.muted)));
            return ListView(children: [
              for (final r in rows)
                ListTile(
                  dense: true,
                  leading: Icon(switch (r['kind']) {
                    'file' => Icons.attach_file_rounded,
                    'link' => Icons.link_rounded,
                    'system' => Icons.info_outline_rounded,
                    _ => Icons.chat_bubble_outline_rounded,
                  }),
                  title: Text('${r['sender'] ?? ''} · ${_stamp(r['at'])}'),
                  subtitle: Text([
                    if (r['kind'] == 'file') '${r['mime'] ?? ''} ${fileSizeText(_int(r['size']))}' else '${r['length']} حرفاً',
                    if (r['reply'] == true) 'رد',
                    if (r['edited'] == true) 'معدّلة',
                    if (r['deleted'] == true) 'محذوفة${r['deleted_by'] != null ? ' بواسطة ${r['deleted_by']}' : ''}',
                  ].join(' · ')),
                ),
            ]);
          },
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('إغلاق'))],
    );
  }
}

// ---------------------------------------------------------------------
// الحوادث الأمنية
// ---------------------------------------------------------------------

const Map<String, String> incidentStatusLabels = {'open': 'مفتوحة', 'investigating': 'قيد التحقيق', 'contained': 'محتواة', 'closed': 'مغلقة'};
const Map<String, String> incidentCategoryLabels = {
  'access': 'وصول وصلاحيات',
  'device': 'أجهزة',
  'data': 'بيانات',
  'chat': 'مراسلات',
  'account': 'حسابات',
  'policy': 'سياسات',
  'other': 'أخرى',
};
const Map<String, String> incidentSeverityLabels = {'low': 'منخفضة', 'medium': 'متوسطة', 'high': 'عالية', 'critical': 'حرجة'};

class SecIncidentsPage extends StatefulWidget {
  const SecIncidentsPage({super.key});

  @override
  State<SecIncidentsPage> createState() => _SecIncidentsPageState();
}

class _SecIncidentsPageState extends State<SecIncidentsPage> {
  String _status = 'active';

  @override
  Widget build(BuildContext context) => _SecPage(
        title: 'الحوادث الأمنية',
        subtitle: 'سجل الحوادث من الاكتشاف إلى الإغلاق: الخطورة والفئة والمستخدم المعني والإجراءات المتخذة، وكل تعديل مسجّل.',
        icon: Icons.report_outlined,
        periods: const [],
        actions: (context, reload) => [
          FilledButton.icon(
            onPressed: () async {
              await showDialog<void>(context: context, builder: (_) => const IncidentDialog());
              reload();
            },
            icon: const Icon(Icons.add_rounded),
            label: const Text('حادثة جديدة'),
          ),
        ],
        load: (app, _) async => secFixtures?['security_incidents'] ??
            [
              for (final r in await app.client.from('security_incidents').select().order('detected_at', ascending: false).limit(500))
                Map<String, dynamic>.from(r),
            ],
        build: (context, data, _, reload) {
          final app = AppScope.of(context);
          final sem = Sem.of(context);
          final all = data as List<Map<String, dynamic>>;
          final list = all.where((r) => _status == 'all' || (_status == 'active' ? r['status'] != 'closed' : r['status'] == _status)).toList();
          return [
            ResponsiveGrid(minItemWidth: 160, children: [
              KpiTile(label: 'مفتوحة', value: '${all.where((r) => r['status'] != 'closed').length}'),
              KpiTile(
                  label: 'عالية وحرجة',
                  value: '${all.where((r) => r['status'] != 'closed' && (r['severity'] == 'high' || r['severity'] == 'critical')).length}',
                  color: sem.danger),
              KpiTile(label: 'مغلقة', value: '${all.where((r) => r['status'] == 'closed').length}', color: sem.ok),
            ]),
            const SizedBox(height: 10),
            Wrap(spacing: 6, children: [
              for (final f in [('active', 'غير المغلقة'), ...incidentStatusLabels.entries.map((e) => (e.key, e.value)), ('all', 'الكل')])
                ChoiceChip(label: Text(f.$2), selected: _status == f.$1, showCheckmark: false, onSelected: (_) => setState(() => _status = f.$1)),
            ]),
            const SizedBox(height: 10),
            if (list.isEmpty)
              const EmptyState(icon: Icons.verified_outlined, title: 'لا حوادث', message: 'سجّل الحادثة من هنا أو من صفحة التنبيهات.')
            else
              for (final r in list)
                SectionCard(
                  title: '${r['title']}',
                  icon: Icons.report_outlined,
                  subtitle: '${incidentCategoryLabels[r['category']] ?? r['category']} · اكتُشفت ${_stamp(r['detected_at'])}'
                      '${r['user_id'] != null ? ' · ${app.people['${r['user_id']}']?.displayName ?? ''}' : ''}',
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    ToneBadge(incidentSeverityLabels[r['severity']] ?? '${r['severity']}', color: _sevColor(context, '${r['severity']}')),
                    const SizedBox(width: 6),
                    ToneBadge(incidentStatusLabels[r['status']] ?? '${r['status']}', color: r['status'] == 'closed' ? sem.ok : sem.wip),
                    IconButton(
                      tooltip: 'تعديل',
                      icon: const Icon(Icons.edit_outlined),
                      onPressed: () async {
                        await showDialog<void>(context: context, builder: (_) => IncidentDialog(incident: r));
                        reload();
                      },
                    ),
                    if (app.isDirector)
                      IconButton(
                        tooltip: 'حذف',
                        icon: const Icon(Icons.delete_outline_rounded),
                        onPressed: () async {
                          final ok = await confirmDialog(context,
                              title: 'حذف الحادثة', message: 'يُحذف السجل نهائياً ويُسجَّل الحذف.', confirmLabel: 'حذف', danger: true);
                          if (!ok) return;
                          try {
                            await _rpc(app, 'sec_delete_incident', {'p_id': r['id']});
                            reload();
                          } catch (e) {
                            if (context.mounted) showToast(context, friendlyError(e), error: true);
                          }
                        },
                      ),
                  ]),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    if ('${r['details']}'.isNotEmpty) Text('${r['details']}'),
                    if ('${r['actions']}'.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text('الإجراءات: ${r['actions']}', style: TextStyle(color: sem.muted)),
                    ],
                    if (r['closed_at'] != null) Text('أُغلقت ${_stamp(r['closed_at'])}', style: TextStyle(color: sem.ok, fontSize: 12)),
                  ]),
                ),
          ];
        },
      );
}

class IncidentDialog extends StatefulWidget {
  const IncidentDialog({super.key, this.incident, this.prefill});

  final Map<String, dynamic>? incident;
  final Map<String, dynamic>? prefill;

  @override
  State<IncidentDialog> createState() => _IncidentDialogState();
}

class _IncidentDialogState extends State<IncidentDialog> {
  late final Map<String, dynamic> _src = widget.incident ?? widget.prefill ?? const {};
  late final _title = TextEditingController(text: '${_src['title'] ?? ''}');
  late final _details = TextEditingController(text: '${_src['details'] ?? ''}');
  late final _actions = TextEditingController(text: '${_src['actions'] ?? ''}');
  late String _severity = '${_src['severity'] ?? 'medium'}';
  late String _status = '${_src['status'] ?? 'open'}';
  late String _category = '${_src['category'] ?? 'other'}';
  late String _user = '${_src['user_id'] ?? ''}' == 'null' ? '' : '${_src['user_id'] ?? ''}';
  bool _busy = false;

  @override
  void dispose() {
    _title.dispose();
    _details.dispose();
    _actions.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final app = AppScope.read(context);
    setState(() => _busy = true);
    try {
      await _rpc(app, 'sec_save_incident', {
        'p_id': widget.incident?['id'],
        'p_data': {
          'title': _title.text.trim(),
          'severity': _severity,
          'status': _status,
          'category': _category,
          'details': _details.text.trim(),
          'actions': _actions.text.trim(),
          'user_id': _user.isEmpty ? null : _user,
        },
      });
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) showToast(context, friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final people = app.people.values.toList()..sort((a, b) => a.displayName.compareTo(b.displayName));
    if (_user.isNotEmpty && !app.people.containsKey(_user)) _user = '';
    return AlertDialog(
      title: Text(widget.incident == null ? 'حادثة أمنية جديدة' : 'تعديل الحادثة'),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            TextField(controller: _title, maxLength: 200, decoration: fieldDeco('العنوان'), onChanged: (_) => setState(() {})),
            Row(children: [
              Expanded(
                child: SelectField(
                  label: 'الخطورة',
                  value: _severity,
                  items: [for (final e in incidentSeverityLabels.entries) (e.key, e.value)],
                  onChanged: (v) => setState(() => _severity = v),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: SelectField(
                  label: 'الحالة',
                  value: _status,
                  items: [for (final e in incidentStatusLabels.entries) (e.key, e.value)],
                  onChanged: (v) => setState(() => _status = v),
                ),
              ),
            ]),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                child: SelectField(
                  label: 'الفئة',
                  value: _category,
                  items: [for (final e in incidentCategoryLabels.entries) (e.key, e.value)],
                  onChanged: (v) => setState(() => _category = v),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: SelectField(
                  label: 'المستخدم المعني',
                  value: _user,
                  items: [('', '—'), for (final p in people) (p.id, p.displayName)],
                  onChanged: (v) => setState(() => _user = v),
                ),
              ),
            ]),
            const SizedBox(height: 8),
            TextField(controller: _details, minLines: 3, maxLines: 8, maxLength: 8000, decoration: fieldDeco('التفاصيل')),
            TextField(controller: _actions, minLines: 2, maxLines: 6, maxLength: 8000, decoration: fieldDeco('الإجراءات المتخذة')),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('إلغاء')),
        FilledButton(onPressed: _busy || _title.text.trim().length < 3 ? null : _save, child: const Text('حفظ')),
      ],
    );
  }
}
