import 'package:flutter/material.dart';

import '../../app_state.dart';
import '../../models.dart';
import '../../services/export.dart';
import '../../ui/audit_text.dart';
import '../../ui/theme.dart';
import '../../ui/widgets.dart';

/// سجل التدقيق: كل تعديل في المنظومة، لا يُعدَّل ولا يُحذف.
class AuditSection extends StatefulWidget {
  const AuditSection({super.key});

  @override
  State<AuditSection> createState() => _AuditSectionState();
}

class _AuditSectionState extends State<AuditSection> {
  List<AuditEntry>? _rows;
  String? _error;
  String _actor = '';
  String _kind = '';
  String _q = '';
  int _limit = 500;
  bool _exporting = false;

  Future<void> _export(AppState app, List<AuditEntry> rows) async {
    setState(() => _exporting = true);
    try {
      final path = await exportAuditXlsx(app, rows, (e) => auditDescription(app, e));
      if (mounted && path != null) showToast(context, 'حُفظ الملف: $path');
    } catch (e) {
      if (mounted) showToast(context, friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  static const _kinds = [
    ('', 'كل العمليات'),
    ('form.', 'حالات النماذج'),
    ('request.', 'طلبات الاعتماد'),
    ('project.', 'بيانات المشاريع'),
    ('user.', 'المستخدمون'),
    ('security.', 'الأمان'),
    ('setting.', 'الإعدادات'),
    ('config.', 'هيكل البيانات'),
    ('form_def.', 'صلاحيات النماذج'),
    ('idea.', 'الأفكار'),
    ('note.', 'ملاحظات التقييم'),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    try {
      final rows = await AppScope.read(context).loadAudit(limit: _limit);
      if (mounted) {
        setState(() {
          _rows = rows;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final sem = Sem.of(context);
    final rows = _rows;
    if (_error != null) {
      return EmptyState(icon: Icons.cloud_off, title: 'تعذّر تحميل السجل', message: _error, action: FilledButton(onPressed: _load, child: const Text('إعادة المحاولة')));
    }
    if (rows == null) return const Center(child: CircularProgressIndicator());
    final actors = <String, String>{};
    for (final r in rows) {
      if (r.actor != null) actors[r.actor!] = r.actorName.isEmpty ? app.personName(r.actor) : r.actorName;
    }
    final q = normalizeArabic(_q);
    final shown = rows.where((r) {
      if (_actor.isNotEmpty && r.actor != _actor) return false;
      if (_kind.isNotEmpty && !r.action.startsWith(_kind)) return false;
      if (q.isNotEmpty && !normalizeArabic('${r.projectLabel} ${auditDescription(app, r)} ${r.actorName}').contains(q)) return false;
      return true;
    }).toList();

    return PageBody(
      onRefresh: _load,
      children: [
        PageHeader(
          icon: Icons.history_rounded,
          title: 'سجل التدقيق',
          subtitle: 'كل عملية في المنظومة: من قام بها، ومتى، وما الذي تغيّر. لا يستطيع أحد تعديل السجل أو حذفه، ولا حتى المدير.',
          actions: [
            OutlinedButton.icon(
              onPressed: _exporting || shown.isEmpty ? null : () => _export(app, shown),
              icon: _exporting
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.download_rounded),
              label: const Text('تصدير Excel'),
            ),
          ],
        ),
        LayoutBuilder(builder: (context, c) {
          final a = SelectField(
            label: 'المستخدم',
            value: _actor,
            items: [('', 'الجميع'), for (final e in actors.entries) (e.key, e.value)],
            onChanged: (v) => setState(() => _actor = v),
          );
          final k = SelectField(label: 'العملية', value: _kind, items: _kinds, onChanged: (v) => setState(() => _kind = v));
          final s = TextField(
            decoration: fieldDeco('بحث في السجل', prefixIcon: const Icon(Icons.search)),
            onChanged: (v) => setState(() => _q = v),
          );
          return c.maxWidth < 720
              ? Column(children: [a, const SizedBox(height: 10), k, const SizedBox(height: 10), s])
              : Row(children: [Expanded(child: a), const SizedBox(width: 10), Expanded(child: k), const SizedBox(width: 10), Expanded(child: s)]);
        }),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(child: Text('${shown.length} سطراً · آخر $_limit عملية', style: TextStyle(color: sem.muted, fontSize: 12.5))),
            if (_limit < 3000)
              TextButton(
                onPressed: () {
                  setState(() => _limit = _limit * 2);
                  _load();
                },
                child: const Text('تحميل المزيد'),
              ),
          ],
        ),
        const SizedBox(height: 6),
        Container(
          decoration: BoxDecoration(color: sem.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: sem.rule)),
          child: Column(
            children: [
              for (var i = 0; i < shown.length; i++)
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 14),
                  decoration: BoxDecoration(border: i == shown.length - 1 ? null : Border(bottom: BorderSide(color: sem.rule))),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      InitialsAvatar(name: shown[i].actorName.isEmpty ? 'النظام' : shown[i].actorName, size: 32),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(shown[i].actorName.isEmpty ? 'النظام' : shown[i].actorName,
                                      style: const TextStyle(fontWeight: FontWeight.w700)),
                                ),
                                Text(fmtDate(shown[i].at), style: TextStyle(color: sem.muted, fontSize: 12)),
                              ],
                            ),
                            Text(auditDescription(app, shown[i])),
                            if (shown[i].projectId != null && shown[i].projectLabel.isNotEmpty && !shown[i].action.startsWith('project.'))
                              Text(shown[i].projectLabel, style: TextStyle(color: sem.muted, fontSize: 12.5), maxLines: 1, overflow: TextOverflow.ellipsis),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
