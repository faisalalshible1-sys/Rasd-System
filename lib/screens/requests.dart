import 'package:flutter/material.dart';

import '../app_state.dart';
import '../models.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';
import 'project_detail.dart';

/// UC-15 (المدير): البتّ في طلبات الاعتماد.  UC-09 (الآخرون): متابعة طلباتي.
class RequestsPage extends StatelessWidget {
  const RequestsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    if (!app.loadedOnce) return const Center(child: CircularProgressIndicator());
    if (!app.isDirector) {
      final mine = app.myRequests;
      return RefreshIndicator(
        onRefresh: app.loadAll,
        child: mine.isEmpty
            ? ListView(children: const [
                EmptyState(
                  icon: Icons.fact_check_outlined,
                  title: 'لا توجد طلبات',
                  message: 'عند تغيير نموذج حساس (المستخلصات والاستلام والإقفال) يُرفع طلب لاعتماد مدير المكتب ويظهر هنا.',
                ),
              ])
            : _RequestList(requests: mine, showActions: true),
      );
    }
    final pending = app.pendingRequests;
    final decided = app.requests.where((r) => !r.isPending).toList();
    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          Material(
            color: Sem.of(context).surface,
            child: TabBar(tabs: [
              Tab(text: 'المعلّقة (${pending.length})'),
              Tab(text: 'المبتوت فيها (${decided.length})'),
            ]),
          ),
          Expanded(
            child: TabBarView(children: [
              RefreshIndicator(
                onRefresh: app.loadAll,
                child: pending.isEmpty
                    ? ListView(children: const [
                        EmptyState(icon: Icons.task_alt, title: 'لا توجد طلبات معلّقة', message: 'كل الطلبات بُتّ فيها.'),
                      ])
                    : _RequestList(requests: pending, showActions: true),
              ),
              RefreshIndicator(
                onRefresh: app.loadAll,
                child: decided.isEmpty
                    ? ListView(children: const [EmptyState(icon: Icons.history, title: 'لا يوجد سجل بعد')])
                    : _RequestList(requests: decided, showActions: false),
              ),
            ]),
          ),
        ],
      ),
    );
  }
}

class _RequestList extends StatelessWidget {
  const _RequestList({required this.requests, required this.showActions});

  final List<ChangeRequest> requests;
  final bool showActions;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: requests.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, i) => Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 820),
          child: RequestCard(request: requests[i], showActions: showActions),
        ),
      ),
    );
  }
}

class RequestCard extends StatefulWidget {
  const RequestCard({super.key, required this.request, required this.showActions});

  final ChangeRequest request;
  final bool showActions;

  @override
  State<RequestCard> createState() => _RequestCardState();
}

class _RequestCardState extends State<RequestCard> {
  bool _busy = false;

  Future<void> _run(Future<void> Function() action, String done) async {
    setState(() => _busy = true);
    try {
      await action();
      if (mounted) showToast(context, done);
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
    final r = widget.request;
    final p = app.project(r.projectId);
    final d = app.formDef(r.formKey);
    final stateColor = switch (r.state) {
      RequestState.pending => sem.wip,
      RequestState.approved => sem.ok,
      RequestState.rejected => sem.danger,
      RequestState.withdrawn => sem.muted,
    };
    final stateSoft = switch (r.state) {
      RequestState.pending => sem.wipSoft,
      RequestState.approved => sem.okSoft,
      RequestState.rejected => sem.dangerSoft,
      RequestState.withdrawn => sem.todoSoft,
    };

    return Material(
      color: sem.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: sem.rule)),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: p == null
            ? null
            : () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ProjectDetailPage(projectId: p.id))),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  NoTag(p?.contractNo ?? ''),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(p?.title ?? 'مشروع محذوف', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: sem.muted, fontSize: 13)),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                    decoration: BoxDecoration(color: stateSoft, borderRadius: BorderRadius.circular(99)),
                    child: Text(r.state.label, style: TextStyle(color: stateColor, fontWeight: FontWeight.w700, fontSize: 12)),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(d?.name ?? r.formKey, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
              const SizedBox(height: 6),
              Row(
                children: [
                  _statusChip(context, r.fromStatus),
                  Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: Icon(Icons.arrow_forward, size: 18, color: sem.muted)),
                  _statusChip(context, r.toStatus),
                ],
              ),
              const SizedBox(height: 8),
              Text('مقدّم الطلب: ${app.personName(r.requestedBy)} · ${fmtDate(r.requestedAt)}', style: TextStyle(color: sem.muted, fontSize: 12.5)),
              if (r.note.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text('ملاحظته: ${r.note}'),
              ],
              if (!r.isPending && r.state != RequestState.withdrawn) ...[
                const SizedBox(height: 6),
                Text(
                  'القرار: ${app.personName(r.decidedBy)} · ${fmtDate(r.decidedAt)}' + (r.decisionNote.isNotEmpty ? '\n' + r.decisionNote : ''),
                  style: TextStyle(fontSize: 12.5, color: r.state == RequestState.rejected ? sem.danger : null),
                ),
              ],
              if (widget.showActions && r.isPending) ...[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    if (app.isDirector) ...[
                      FilledButton.icon(
                        onPressed: _busy ? null : () => _run(() => app.decideRequest(r.id, true), 'اعتُمد الطلب وطُبّقت الحالة'),
                        icon: const Icon(Icons.check),
                        label: const Text('اعتماد'),
                        style: FilledButton.styleFrom(backgroundColor: sem.ok, foregroundColor: Colors.white),
                      ),
                      OutlinedButton.icon(
                        onPressed: _busy
                            ? null
                            : () async {
                                final reason = await textInputDialog(context,
                                    title: 'رفض الطلب', label: 'سبب الرفض', confirmLabel: 'رفض الطلب', required: true);
                                if (reason == null || !mounted) return;
                                await _run(() => app.decideRequest(r.id, false, note: reason), 'رُفض الطلب');
                              },
                        icon: const Icon(Icons.close),
                        label: const Text('رفض'),
                        style: OutlinedButton.styleFrom(foregroundColor: sem.danger),
                      ),
                    ],
                    if (r.requestedBy == app.me?.id)
                      TextButton.icon(
                        onPressed: _busy ? null : () => _run(() => app.withdrawRequest(r.id), 'سُحب الطلب'),
                        icon: const Icon(Icons.undo),
                        label: const Text('سحب الطلب'),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _statusChip(BuildContext context, FormStatus s) {
    final sem = Sem.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: sem.statusSoft(s), borderRadius: BorderRadius.circular(8), border: Border.all(color: sem.statusColor(s))),
      child: Text(s.label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
    );
  }
}
