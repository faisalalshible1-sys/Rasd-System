import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_state.dart';
import '../models.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';

/// الأفكار وطلبات التطوير: تُكتب هنا وتصل مهمةً في مستودع المشروع لتُنفَّذ في التحديثات القادمة.
class IdeasPage extends StatefulWidget {
  const IdeasPage({super.key});

  @override
  State<IdeasPage> createState() => _IdeasPageState();
}

class _IdeasPageState extends State<IdeasPage> {
  String _status = '';

  Color _statusColor(Sem sem, BuildContext context, String s) => switch (s) {
        'done' => sem.ok,
        'in_progress' => sem.wip,
        'planned' => Theme.of(context).colorScheme.primary,
        'rejected' => sem.muted,
        _ => sem.danger,
      };

  Color _priorityColor(Sem sem, String p) => switch (p) {
        'urgent' => sem.danger,
        'high' => sem.wip,
        'low' => sem.muted,
        _ => sem.ok,
      };

  Future<void> _newIdea(AppState app) async {
    final res = await showDialog<(String, String, String, String)>(context: context, builder: (_) => const _IdeaDialog());
    if (res == null || !mounted) return;
    try {
      await app.submitIdea(title: res.$1, body: res.$2, category: res.$3, priority: res.$4);
      if (mounted) showToast(context, 'وصلت فكرتك، وستُضاف إلى مهام التطوير');
    } catch (e) {
      if (mounted) showToast(context, friendlyError(e), error: true);
    }
  }

  Future<void> _respond(AppState app, Idea i) async {
    final text = await textInputDialog(context,
        title: 'رد على الفكرة', label: 'الرد (يصل لصاحب الفكرة)', confirmLabel: 'حفظ', initial: i.response);
    if (text == null) return;
    try {
      await app.updateIdea(i.id, response: text);
      if (mounted) showToast(context, 'حُفظ الرد');
    } catch (e) {
      if (mounted) showToast(context, friendlyError(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final sem = Sem.of(context);
    final canSubmit = app.isDirector || app.settings.feature('ideas_for_all');
    final ideas = app.ideas.where((i) => _status.isEmpty || i.status == _status).toList();
    int count(String s) => app.ideas.where((i) => s.isEmpty || i.status == s).length;

    return PageBody(
      onRefresh: app.loadAll,
      maxWidth: 960,
      children: [
        PageHeader(
          icon: Icons.lightbulb_outline_rounded,
          title: 'الأفكار والتطوير',
          subtitle: 'اكتب أي فكرة لتحسين المنظومة أو أي خلل لاحظته. تتحول كل فكرة تلقائياً إلى مهمة تطوير في مستودع المشروع، ويُتابَع تنفيذها هنا.',
          actions: [
            if (canSubmit) FilledButton.icon(onPressed: () => _newIdea(app), icon: const Icon(Icons.add), label: const Text('فكرة جديدة')),
          ],
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ChoiceChip(label: Text('الكل (${count('')})'), selected: _status.isEmpty, showCheckmark: false, onSelected: (_) => setState(() => _status = '')),
            for (final e in ideaStatusLabels.entries)
              ChoiceChip(
                label: Text('${e.value} (${count(e.key)})'),
                selected: _status == e.key,
                showCheckmark: false,
                onSelected: (_) => setState(() => _status = e.key),
              ),
          ],
        ),
        const SizedBox(height: 14),
        if (ideas.isEmpty)
          EmptyState(
            icon: Icons.lightbulb_outline_rounded,
            title: 'لا توجد أفكار هنا بعد',
            message: canSubmit ? 'ابدأ بفكرة: ميزة، تقرير، تحسين في الشكل، أو خلل لاحظته.' : null,
          ),
        for (final i in ideas)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: sem.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: sem.rule)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: Text(i.title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700))),
                      if (app.isDirector)
                        PopupMenuButton<String>(
                          tooltip: 'إدارة الفكرة',
                          onSelected: (v) async {
                            try {
                              if (v.startsWith('s:')) {
                                await app.updateIdea(i.id, status: v.substring(2));
                              } else if (v.startsWith('p:')) {
                                await app.updateIdea(i.id, priority: v.substring(2));
                              } else if (v == 'respond') {
                                await _respond(app, i);
                              } else if (v == 'delete') {
                                final ok = await confirmDialog(context, title: 'حذف الفكرة؟', message: i.title, confirmLabel: 'حذف', danger: true);
                                if (ok) await app.deleteIdea(i.id);
                              }
                            } catch (e) {
                              if (context.mounted) showToast(context, friendlyError(e), error: true);
                            }
                          },
                          itemBuilder: (_) => [
                            for (final e in ideaStatusLabels.entries)
                              PopupMenuItem(value: 's:${e.key}', enabled: e.key != i.status, child: Text('الحالة: ${e.value}')),
                            const PopupMenuDivider(),
                            for (final e in ideaPriorityLabels.entries)
                              PopupMenuItem(value: 'p:${e.key}', enabled: e.key != i.priority, child: Text('الأولوية: ${e.value}')),
                            const PopupMenuDivider(),
                            const PopupMenuItem(value: 'respond', child: Text('كتابة رد')),
                            const PopupMenuItem(value: 'delete', child: Text('حذف')),
                          ],
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Wrap(spacing: 6, runSpacing: 6, children: [
                    ToneBadge(ideaStatusLabels[i.status] ?? i.status, color: _statusColor(sem, context, i.status)),
                    ToneBadge(ideaCategoryLabels[i.category] ?? i.category, color: Theme.of(context).colorScheme.primary),
                    ToneBadge('أولوية ${ideaPriorityLabels[i.priority] ?? i.priority}', color: _priorityColor(sem, i.priority)),
                  ]),
                  if (i.body.trim().isNotEmpty) ...[const SizedBox(height: 10), Text(i.body)],
                  if (i.response.trim().isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: sem.surface2, borderRadius: BorderRadius.circular(12)),
                      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Icon(Icons.reply_rounded, size: 18, color: sem.muted),
                        const SizedBox(width: 8),
                        Expanded(child: Text(i.response)),
                      ]),
                    ),
                  ],
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: Text('${app.personName(i.createdBy)} · ${fmtDate(i.createdAt)}', style: TextStyle(color: sem.muted, fontSize: 12)),
                      ),
                      if (i.githubUrl.isNotEmpty)
                        TextButton.icon(
                          onPressed: () => launchUrl(Uri.parse(i.githubUrl), mode: LaunchMode.externalApplication),
                          icon: const Icon(Icons.task_alt_rounded, size: 18),
                          label: const Text('مهمة التطوير'),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _IdeaDialog extends StatefulWidget {
  const _IdeaDialog();

  @override
  State<_IdeaDialog> createState() => _IdeaDialogState();
}

class _IdeaDialogState extends State<_IdeaDialog> {
  final _title = TextEditingController();
  final _body = TextEditingController();
  String _category = 'feature';
  String _priority = 'normal';
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('فكرة جديدة'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(controller: _title, autofocus: true, maxLength: 200, decoration: fieldDeco('عنوان مختصر', error: _error, hint: 'مثال: تقرير شهري للمستخلصات')),
              TextField(
                controller: _body,
                minLines: 4,
                maxLines: 10,
                decoration: fieldDeco('التفاصيل', hint: 'ما الذي تريده؟ ولماذا؟ وأين يظهر في المنظومة؟'),
              ),
              const SizedBox(height: 12),
              SelectField(
                label: 'النوع',
                value: _category,
                items: [for (final e in ideaCategoryLabels.entries) (e.key, e.value)],
                onChanged: (v) => setState(() => _category = v),
              ),
              const SizedBox(height: 12),
              SelectField(
                label: 'الأولوية',
                value: _priority,
                items: [for (final e in ideaPriorityLabels.entries) (e.key, e.value)],
                onChanged: (v) => setState(() => _priority = v),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('إلغاء')),
        FilledButton(
          onPressed: () {
            if (_title.text.trim().length < 3) {
              setState(() => _error = 'اكتب عنواناً من ثلاثة أحرف على الأقل');
              return;
            }
            Navigator.of(context).pop((_title.text.trim(), _body.text.trim(), _category, _priority));
          },
          child: const Text('إرسال'),
        ),
      ],
    );
  }
}
