import 'package:flutter/material.dart';

import '../app_state.dart';
import '../maintenance.dart';
import '../registers.dart' show isoDay;
import '../ui/theme.dart';
import '../ui/widgets.dart';
import 'contract_finance.dart' show DayField;
import 'stores.dart' show storesRun;
import 'stores_setup.dart' show storeFormDialog;

// =====================================================================
// قسم الصيانة (الإصدار 1.9.0، الترحيل 40): اللوحة، والبلاغات وصفحة البلاغ، والصيانة الدورية، والتنبيهات،
// وبلاغاتي، ومهام الفني، والفنيون والإعدادات.
// =====================================================================

const _tabular = TextStyle(fontFeatures: [FontFeature.tabularFigures()]);

/// لون أولوية البلاغ.
Color mtPriorityColor(Sem sem, String p) => switch (p) {
      'urgent' => sem.danger,
      'high' => sem.wip,
      'low' => sem.todo,
      _ => sem.na,
    };

/// لون حالة البلاغ.
Color mtStatusColor(Sem sem, String s) => switch (s) {
      'new' => sem.wip,
      'assigned' || 'in_progress' => sem.na,
      'on_hold' => sem.todo,
      'done' => sem.ok,
      'closed' => sem.ok,
      'rejected' => sem.danger,
      _ => sem.muted,
    };

/// قبل تطبيق الترحيل 40.
class MaintNotReady extends StatelessWidget {
  const MaintNotReady({super.key});

  @override
  Widget build(BuildContext context) => const InfoBanner(
        level: 'warning',
        icon: Icons.storage_rounded,
        text: 'قسم الصيانة يحتاج تحديث قاعدة البيانات (الترحيل 40).',
      );
}

void openMtRequest(BuildContext context, String requestId) =>
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => MtRequestPage(requestId: requestId)));

// ---------------------------------------------------------------------
// بطاقة بلاغ في القوائم
// ---------------------------------------------------------------------

class MtRequestTile extends StatelessWidget {
  const MtRequestTile({super.key, required this.request, this.showReporter = true});

  final MtRequest request;
  final bool showReporter;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final m = app.maint;
    final sem = Sem.of(context);
    final r = request;
    final now = DateTime.now();
    final place = m.locationPath(r.locationId);
    final late = r.isOverdue(now);
    final bits = <String>[
      r.reqNo,
      mtCategoryLabels[r.category] ?? r.category,
      if (r.assetText.isNotEmpty) r.assetText,
      if (place.isNotEmpty) place,
      if (showReporter && r.reporterName.isNotEmpty) 'من ${r.reporterName}',
      if (r.executor.isNotEmpty) 'إلى ${r.executor}',
    ];
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => openMtRequest(context, r.id),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 4,
              height: 44,
              decoration: BoxDecoration(color: mtPriorityColor(sem, r.priority), borderRadius: BorderRadius.circular(4)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(r.title, style: const TextStyle(fontWeight: FontWeight.w700), maxLines: 2, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 2),
                  Text(bits.join(' · '), style: TextStyle(fontSize: 12, color: sem.muted), maxLines: 2, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 6),
                  Wrap(spacing: 6, runSpacing: 4, children: [
                    ToneBadge(mtStatusLabels[r.status] ?? r.status, color: mtStatusColor(sem, r.status)),
                    ToneBadge(mtPriorityLabels[r.priority] ?? r.priority, color: mtPriorityColor(sem, r.priority)),
                    if (r.isPlan) ToneBadge('وقائية', color: sem.na, icon: Icons.event_repeat_rounded),
                    if (r.isRunning && r.dueAt != null) ToneBadge(mtDueText(r.dueAt, now), color: late ? sem.danger : sem.muted, icon: Icons.schedule_rounded),
                  ]),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------
// نموذج رفع بلاغ
// ---------------------------------------------------------------------

Future<void> showMtReportDialog(BuildContext context, {bool onBehalf = false}) async {
  final app = AppScope.read(context);
  final m = app.maint;
  final staff = app.mtStaff;
  final title = TextEditingController();
  final desc = TextEditingController();
  final note = TextEditingController();
  final phone = TextEditingController();
  final tag = TextEditingController();
  final who = TextEditingController();
  final dept = TextEditingController();
  var category = 'other';
  var priority = 'normal';
  var location = '';
  var asset = '';
  await storeFormDialog(
    context,
    title: onBehalf ? 'تسجيل بلاغ نيابةً عن صاحبه' : 'بلاغ صيانة جديد',
    width: 520,
    body: (set) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (onBehalf) ...[
        TextField(controller: who, decoration: fieldDeco('اسم صاحب البلاغ')),
        const SizedBox(height: 10),
        TextField(controller: dept, decoration: fieldDeco('إدارته (اختياري)')),
        const SizedBox(height: 10),
      ],
      TextField(controller: title, decoration: fieldDeco('عنوان البلاغ (ما العطل؟)')),
      const SizedBox(height: 10),
      TextField(controller: desc, minLines: 2, maxLines: 5, decoration: fieldDeco('وصف العطل (اختياري)')),
      const SizedBox(height: 10),
      SelectField(
        label: 'التصنيف',
        value: category,
        items: [for (final e in mtCategoryLabels.entries) (e.key, e.value)],
        onChanged: (v) => set(() => category = v),
      ),
      const SizedBox(height: 10),
      SelectField(
        label: 'الأولوية',
        value: priority,
        items: [for (final p in mtPriorityOrder.reversed) (p, '${mtPriorityLabels[p]} — إنجاز خلال ${m.settings.slaHours(p)} ساعة')],
        onChanged: (v) => set(() => priority = v),
      ),
      const SizedBox(height: 10),
      SelectField(
        label: 'الموقع',
        value: location,
        items: [('', 'غير محدد'), for (final l in m.locations) (l.id, m.locationPath(l.id))],
        onChanged: (v) => set(() => location = v),
      ),
      const SizedBox(height: 10),
      TextField(controller: note, decoration: fieldDeco('وصف المكان (اختياري، مثل: بجوار النافذة)')),
      const SizedBox(height: 10),
      if (staff)
        SelectField(
          label: 'الأصل (اختياري)',
          value: asset,
          items: [('', 'بلا أصل'), for (final a in m.assets) (a.id, '${a.tag} — ${a.name}')],
          onChanged: (v) => set(() => asset = v),
        )
      else
        TextField(controller: tag, textDirection: TextDirection.ltr, decoration: fieldDeco('رقم الأصل على الملصق (اختياري)')),
      const SizedBox(height: 10),
      TextField(controller: phone, keyboardType: TextInputType.phone, textDirection: TextDirection.ltr, decoration: fieldDeco('هاتف للتواصل (اختياري)')),
    ]),
    onSave: () async {
      if (title.text.trim().length < 3) throw StateError('اكتب عنواناً للبلاغ (3 أحرف فأكثر)');
      if (onBehalf && who.text.trim().isEmpty) throw StateError('اكتب اسم صاحب البلاغ');
      await app.mtReport({
        'title': title.text.trim(),
        'description': desc.text.trim(),
        'category': category,
        'priority': priority,
        if (location.isNotEmpty) 'location_id': location,
        'place_note': note.text.trim(),
        if (asset.isNotEmpty) 'asset_id': asset,
        if (!staff && tag.text.trim().isNotEmpty) 'asset_tag': tag.text.trim(),
        'phone': phone.text.trim(),
        if (onBehalf) 'reporter_name': who.text.trim(),
        if (onBehalf && dept.text.trim().isNotEmpty) 'reporter_dept': dept.text.trim(),
      });
    },
  );
  for (final c in [title, desc, note, phone, tag, who, dept]) {
    c.dispose();
  }
}

// ---------------------------------------------------------------------
// صفحة البلاغ
// ---------------------------------------------------------------------

class MtRequestPage extends StatefulWidget {
  const MtRequestPage({super.key, required this.requestId});

  final String requestId;

  @override
  State<MtRequestPage> createState() => _MtRequestPageState();
}

class _MtRequestPageState extends State<MtRequestPage> {
  Future<List<MtEvent>>? _events;
  String _stamp = '';

  Future<void> _assign(MtRequest r) async {
    final app = AppScope.read(context);
    final m = app.maint;
    var emp = r.assigneeId ?? '';
    final vendor = TextEditingController(text: r.vendor);
    final note = TextEditingController();
    var priority = r.priority;
    DateTime? due;
    await storeFormDialog(
      context,
      title: r.status == 'new' ? 'فرز البلاغ وإسناده' : 'تغيير الإسناد',
      body: (set) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SelectField(
          label: 'الفني',
          value: emp,
          items: [('', 'بلا فني (جهة خارجية)'), for (final t in m.activeTechnicians) (t.employeeId, '${t.name} — ${mtTradeLabels[t.trade] ?? t.trade}')],
          onChanged: (v) => set(() => emp = v),
        ),
        const SizedBox(height: 10),
        TextField(controller: vendor, decoration: fieldDeco('أو جهة خارجية (شركة/مقاول)')),
        const SizedBox(height: 10),
        SelectField(
          label: 'الأولوية',
          value: priority,
          items: [for (final p in mtPriorityOrder.reversed) (p, mtPriorityLabels[p] ?? p)],
          onChanged: (v) => set(() => priority = v),
        ),
        const SizedBox(height: 10),
        DayField(label: 'الموعد المستهدف (اختياري، وإلا بحسب الأولوية)', value: due, onChanged: (d) => set(() => due = d)),
        const SizedBox(height: 10),
        TextField(controller: note, decoration: fieldDeco('ملاحظة للمنفّذ (اختياري)')),
      ]),
      onSave: () async {
        if (emp.isEmpty && vendor.text.trim().isEmpty) throw StateError('اختر فنياً أو اكتب الجهة الخارجية');
        await app.mtAssign(r.id, {
          if (emp.isNotEmpty) 'assignee_id': emp,
          if (emp.isEmpty) 'vendor': vendor.text.trim(),
          'priority': priority,
          if (due != null) 'due_date': isoDay(due),
          'note': note.text.trim(),
        });
      },
    );
    vendor.dispose();
    note.dispose();
  }

  Future<void> _confirm(MtRequest r, bool accept) async {
    final app = AppScope.read(context);
    final note = TextEditingController();
    var rating = 0;
    await storeFormDialog(
      context,
      title: accept ? 'تأكيد الإغلاق' : 'إعادة فتح البلاغ',
      body: (set) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (accept && r.reporterId != null) ...[
          const Text('قيّم الإصلاح (اختياري):'),
          const SizedBox(height: 6),
          Row(children: [
            for (var i = 1; i <= 5; i++)
              IconButton(
                onPressed: () => set(() => rating = rating == i ? 0 : i),
                icon: Icon(i <= rating ? Icons.star_rounded : Icons.star_outline_rounded, color: i <= rating ? Colors.amber : null),
              ),
          ]),
          const SizedBox(height: 6),
        ],
        TextField(
          controller: note,
          minLines: 2,
          maxLines: 4,
          decoration: fieldDeco(accept ? 'ملاحظة (اختياري)' : 'لماذا لم يُصلَح؟ (مطلوب)'),
        ),
      ]),
      onSave: () async {
        if (!accept && note.text.trim().isEmpty) throw StateError('اكتب سبب إعادة الفتح');
        await app.mtConfirm(r.id, accept, note: note.text, rating: accept && rating > 0 ? rating : null);
      },
    );
    note.dispose();
  }

  Future<void> _done(MtRequest r) async {
    final app = AppScope.read(context);
    final text = await textInputDialog(context,
        title: 'إنجاز البلاغ', message: 'صف ما تمّ من معالجة.', label: 'وصف المعالجة', confirmLabel: 'تم الإنجاز', required: true);
    if (text == null || !mounted) return;
    await storesRun(context, () => app.mtProgress(r.id, 'done', data: {'resolution': text}), success: 'سُجّل الإنجاز، وينتظر تأكيد صاحب البلاغ');
  }

  Future<void> _hold(MtRequest r) async {
    final app = AppScope.read(context);
    final text = await textInputDialog(context,
        title: 'تعليق البلاغ', message: 'لا يُحتسب الوقت على البلاغ المعلّق.', label: 'سبب التعليق', confirmLabel: 'تعليق', required: true);
    if (text == null || !mounted) return;
    await storesRun(context, () => app.mtProgress(r.id, 'hold', data: {'note': text}));
  }

  Future<void> _reject(MtRequest r) async {
    final app = AppScope.read(context);
    final text = await textInputDialog(context, title: 'رفض البلاغ', label: 'سبب الرفض', confirmLabel: 'رفض', required: true);
    if (text == null || !mounted) return;
    await storesRun(context, () => app.mtReject(r.id, text));
  }

  Future<void> _cancel(MtRequest r) async {
    final app = AppScope.read(context);
    final ok = await confirmDialog(context, title: 'إلغاء البلاغ؟', message: 'يُغلق البلاغ ملغى ويبقى في السجل.', confirmLabel: 'إلغاء البلاغ', danger: true);
    if (!ok || !mounted) return;
    await storesRun(context, () => app.mtCancel(r.id));
  }

  Future<void> _comment(MtRequest r) async {
    final app = AppScope.read(context);
    final text = await textInputDialog(context, title: 'تعليق', label: 'نص التعليق', confirmLabel: 'إضافة', required: true);
    if (text == null || !mounted) return;
    await storesRun(context, () => app.mtComment(r.id, text));
    setState(() => _stamp = '');
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final m = app.maint;
    final sem = Sem.of(context);
    final r = m.request(widget.requestId);
    if (r == null) {
      return Scaffold(appBar: AppBar(title: const Text('البلاغ')), body: const EmptyState(title: 'البلاغ غير موجود أو لا تملك صلاحية عرضه'));
    }
    final now = DateTime.now();
    final key = '${r.status}|${r.updatedAt?.millisecondsSinceEpoch}';
    if (key != _stamp || _events == null) {
      _stamp = key;
      _events = app.mtEventsOf(r.id);
    }
    final manage = app.canMtManage;
    final work = app.canMtWork(r);
    final place = m.locationPath(r.locationId);
    final mineNew = r.status == 'new' && r.reporterId != null && r.reporterId == app.me?.id && !app.frozenForMe;
    final actions = <Widget>[
      if (manage && r.isOpen)
        FilledButton.icon(onPressed: () => _assign(r), icon: const Icon(Icons.assignment_ind_rounded), label: Text(r.status == 'new' ? 'فرز وإسناد' : 'تغيير الإسناد')),
      if (work && r.status == 'assigned')
        FilledButton.icon(
            onPressed: () => storesRun(context, () => app.mtProgress(r.id, 'start')), icon: const Icon(Icons.play_arrow_rounded), label: const Text('بدء التنفيذ')),
      if (work && r.status == 'in_progress')
        FilledButton.icon(onPressed: () => _done(r), icon: const Icon(Icons.task_alt_rounded), label: const Text('تم الإنجاز')),
      if (work && r.status == 'in_progress')
        OutlinedButton.icon(onPressed: () => _hold(r), icon: const Icon(Icons.pause_circle_outline_rounded), label: const Text('تعليق')),
      if (work && r.status == 'on_hold')
        FilledButton.icon(
            onPressed: () => storesRun(context, () => app.mtProgress(r.id, 'resume')), icon: const Icon(Icons.play_circle_outline_rounded), label: const Text('استئناف')),
      if (app.canMtConfirm(r)) ...[
        FilledButton.icon(onPressed: () => _confirm(r, true), icon: const Icon(Icons.verified_rounded), label: const Text('تأكيد الإصلاح')),
        OutlinedButton.icon(onPressed: () => _confirm(r, false), icon: const Icon(Icons.replay_rounded), label: const Text('لم يُصلَح')),
      ],
      if (manage && r.status == 'new')
        OutlinedButton.icon(onPressed: () => _reject(r), icon: const Icon(Icons.block_rounded), label: const Text('رفض')),
      if ((manage && r.isOpen) || mineNew)
        OutlinedButton.icon(onPressed: () => _cancel(r), icon: const Icon(Icons.cancel_outlined), label: const Text('إلغاء')),
      if (!app.frozenForMe && r.status != 'cancelled')
        TextButton.icon(onPressed: () => _comment(r), icon: const Icon(Icons.add_comment_outlined), label: const Text('تعليق')),
    ];
    String dt(DateTime? d) => d == null ? '—' : fmtDate(d);
    return Scaffold(
      appBar: AppBar(title: Text(r.reqNo)),
      body: PageBody(
        maxWidth: 860,
        children: [
          Text(r.title, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Wrap(spacing: 6, runSpacing: 6, children: [
            ToneBadge(mtStatusLabels[r.status] ?? r.status, color: mtStatusColor(sem, r.status)),
            ToneBadge('أولوية ${mtPriorityLabels[r.priority] ?? r.priority}', color: mtPriorityColor(sem, r.priority)),
            ToneBadge(mtCategoryLabels[r.category] ?? r.category, color: sem.muted),
            if (r.isPlan) ToneBadge('صيانة وقائية', color: sem.na, icon: Icons.event_repeat_rounded),
            if (r.assetHeld) ToneBadge('الأصل تحت الصيانة', color: sem.wip, icon: Icons.build_rounded),
            if (r.isRunning && r.dueAt != null) ToneBadge(mtDueText(r.dueAt, now), color: r.isOverdue(now) ? sem.danger : sem.muted, icon: Icons.schedule_rounded),
          ]),
          const SizedBox(height: 14),
          if (actions.isNotEmpty) ...[Wrap(spacing: 8, runSpacing: 8, children: actions), const SizedBox(height: 14)],
          if (r.status == 'done' && !app.canMtConfirm(r))
            const Padding(padding: EdgeInsets.only(bottom: 14), child: InfoBanner(text: 'أُنجز البلاغ وينتظر تأكيد صاحبه.')),
          if (r.status == 'on_hold' && r.holdReason.isNotEmpty)
            Padding(padding: const EdgeInsets.only(bottom: 14), child: InfoBanner(level: 'warning', text: 'معلّق: ${r.holdReason}')),
          if (r.status == 'rejected' && r.rejectReason.isNotEmpty)
            Padding(padding: const EdgeInsets.only(bottom: 14), child: InfoBanner(level: 'critical', text: 'مرفوض: ${r.rejectReason}')),
          SectionCard(
            title: 'التفاصيل',
            icon: Icons.info_outline_rounded,
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              if (r.description.isNotEmpty) Padding(padding: const EdgeInsets.only(bottom: 10), child: Text(r.description, style: const TextStyle(height: 1.6))),
              _kv('الموقع', [place, r.placeNote].where((x) => x.isNotEmpty).join(' · ')),
              _kv('الأصل', r.assetText),
              _kv('صاحب البلاغ', [r.reporterName, r.reporterDept].where((x) => x.isNotEmpty).join(' · ')),
              _kv('هاتفه', r.reporterPhone),
              _kv('المنفّذ', r.executor),
              _kv('رُفع', dt(r.reportedAt)),
              _kv('الموعد المستهدف', dt(r.dueAt)),
              if (r.startedAt != null) _kv('بدأ التنفيذ', dt(r.startedAt)),
              if (r.doneAt != null) _kv('أُنجز', dt(r.doneAt)),
              if (r.closedAt != null) _kv('أُغلق', dt(r.closedAt)),
              if (r.resolution.isNotEmpty) _kv('المعالجة', r.resolution),
              if (r.rating != null) _kv('التقييم', '${'★' * r.rating!}${'☆' * (5 - r.rating!)}${r.ratingNote.isEmpty ? '' : ' — ${r.ratingNote}'}'),
            ]),
          ),
          const SizedBox(height: 14),
          SectionCard(
            title: 'سجل البلاغ',
            icon: Icons.history_rounded,
            child: FutureBuilder<List<MtEvent>>(
              future: _events,
              builder: (context, snap) {
                final list = snap.data;
                if (list == null) return const Padding(padding: EdgeInsets.all(12), child: Center(child: CircularProgressIndicator()));
                if (list.isEmpty) return const Text('لا أحداث');
                return Column(children: [
                  for (final e in list)
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(_eventIcon(e.kind), color: sem.muted, size: 20),
                      title: Text(mtEventLabels[e.kind] ?? e.kind),
                      subtitle: e.note.isEmpty ? null : Text(e.note),
                      trailing: Text(fmtDate(e.at), style: _tabular.copyWith(fontSize: 11.5, color: sem.muted)),
                    ),
                ]);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _kv(String k, String v) => v.isEmpty
      ? const SizedBox.shrink()
      : Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(width: 120, child: Text(k, style: TextStyle(color: Sem.of(context).muted))),
            Expanded(child: Text(v)),
          ]),
        );
}

IconData _eventIcon(String kind) => switch (kind) {
      'create' => Icons.flag_outlined,
      'assign' => Icons.assignment_ind_outlined,
      'start' => Icons.play_arrow_rounded,
      'hold' => Icons.pause_circle_outline_rounded,
      'resume' => Icons.play_circle_outline_rounded,
      'done' => Icons.task_alt_rounded,
      'close' => Icons.verified_outlined,
      'reopen' => Icons.replay_rounded,
      'reject' => Icons.block_rounded,
      'cancel' => Icons.cancel_outlined,
      'comment' => Icons.chat_bubble_outline_rounded,
      _ => Icons.edit_outlined,
    };

// ---------------------------------------------------------------------
// لوحة الصيانة
// ---------------------------------------------------------------------

class MaintDashboardPage extends StatelessWidget {
  const MaintDashboardPage({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final m = app.maint;
    final sem = Sem.of(context);
    final now = DateTime.now();
    final overdue = m.overdue(now).length;
    final byStatus = m.countByStatus();
    final total = m.requests.isEmpty ? 1 : m.requests.length;
    final onTime = m.onTimeRate;
    final avgH = m.avgHours;
    final rating = m.avgRating;
    final alerts = [...m.alerts]..sort((a, b) {
        final c = (b.isCritical ? 1 : 0).compareTo(a.isCritical ? 1 : 0);
        return c != 0 ? c : mtAlertOrder.indexOf(a.kind).compareTo(mtAlertOrder.indexOf(b.kind));
      });
    final top = m.topAssets();
    final due = m.plansDue(now, m.settings.planLeadDays)..sort((a, b) => (a.nextDue ?? now).compareTo(b.nextDue ?? now));
    return PageBody(
      onRefresh: app.loadAll,
      children: [
        PageHeader(
          title: 'لوحة الصيانة',
          subtitle: 'البلاغات المفتوحة والمتأخرة ومعدل الإنجاز في موعده، والتنبيهات، وأكثر الأصول أعطالاً.',
          icon: Icons.build_circle_rounded,
          actions: [
            if (app.canMtReport) FilledButton.icon(onPressed: () => showMtReportDialog(context), icon: const Icon(Icons.add_rounded), label: const Text('بلاغ جديد')),
            if (app.canMtManage)
              OutlinedButton.icon(
                  onPressed: () => showMtReportDialog(context, onBehalf: true), icon: const Icon(Icons.phone_in_talk_outlined), label: const Text('بلاغ هاتفي')),
          ],
        ),
        if (!app.v24Ready) ...[const MaintNotReady(), const SizedBox(height: 14)],
        ResponsiveGrid(minItemWidth: 190, children: [
          KpiTile(label: 'بلاغات مفتوحة', value: '${m.open.length}', onTap: () => app.setTab(AppState.maintRequestsTab)),
          KpiTile(label: 'متأخرة', value: '$overdue', color: overdue > 0 ? sem.danger : null, onTap: () => app.setTab(AppState.maintRequestsTab)),
          KpiTile(label: 'بانتظار الإسناد', value: '${m.unassigned.length}', color: m.unassigned.isNotEmpty ? sem.wip : null),
          KpiTile(label: 'بانتظار تأكيد أصحابها', value: '${m.awaitingConfirm.length}'),
          KpiTile(label: 'إنجاز في الموعد', value: onTime == null ? '—' : pctText(onTime)),
          KpiTile(label: 'متوسط زمن المعالجة', value: avgH == null ? '—' : '${avgH.toStringAsFixed(1)} ساعة'),
          KpiTile(label: 'متوسط التقييم', value: rating == null ? '—' : '${rating.toStringAsFixed(1)} / 5'),
          KpiTile(label: 'خطط دورية تستحق قريباً', value: '${due.length}', onTap: () => app.setTab(AppState.maintPlansTab)),
        ]),
        const SizedBox(height: 14),
        ResponsiveGrid(minItemWidth: 340, children: [
          SectionCard(
            title: 'تنبيهات تحتاج انتباهك',
            icon: Icons.notification_important_rounded,
            trailing: TextButton(onPressed: () => app.setTab(AppState.maintAlertsTab), child: const Text('الكل')),
            child: alerts.isEmpty
                ? const Padding(padding: EdgeInsets.all(8), child: Text('لا تنبيهات الآن.'))
                : Column(children: [for (final a in alerts.take(6)) MtAlertTile(alert: a)]),
          ),
          SectionCard(
            title: 'البلاغات بحسب الحالة',
            icon: Icons.stacked_bar_chart_rounded,
            child: Column(children: [
              for (final s in mtStatusLabels.keys)
                if ((byStatus[s] ?? 0) > 0)
                  BarRow(
                    title: mtStatusLabels[s]!,
                    trailing: '${byStatus[s]}',
                    meter: ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: LinearProgressIndicator(value: (byStatus[s] ?? 0) / total, minHeight: 8, color: mtStatusColor(sem, s), backgroundColor: sem.surface2),
                    ),
                  ),
              if (m.requests.isEmpty) const Padding(padding: EdgeInsets.all(8), child: Text('لا بلاغات بعد.')),
            ]),
          ),
          SectionCard(
            title: 'أكثر الأصول أعطالاً',
            icon: Icons.precision_manufacturing_outlined,
            child: top.isEmpty
                ? const Padding(padding: EdgeInsets.all(8), child: Text('لا بلاغات مربوطة بأصول.'))
                : Column(children: [
                    for (final t in top) ListTile(dense: true, contentPadding: EdgeInsets.zero, title: Text(t.$2), subtitle: Text(t.$1), trailing: Text('${t.$3} بلاغ', style: _tabular)),
                  ]),
          ),
          SectionCard(
            title: 'الصيانة الدورية القادمة',
            icon: Icons.event_repeat_rounded,
            child: due.isEmpty
                ? const Padding(padding: EdgeInsets.all(8), child: Text('لا خطط مستحقة خلال مدة التنبيه المسبق.'))
                : Column(children: [
                    for (final p in due.take(6))
                      ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text(p.title),
                        subtitle: Text('${p.planNo} · ${p.intervalText}'),
                        trailing: Text(_dayText(p.daysToDue(now)), style: _tabular),
                      ),
                  ]),
          ),
        ]),
      ],
    );
  }
}

String _dayText(int? d) {
  if (d == null) return '';
  if (d < 0) return 'فات منذ ${-d} يوماً';
  if (d == 0) return 'اليوم';
  if (d == 1) return 'غداً';
  return 'بعد $d يوماً';
}

// ---------------------------------------------------------------------
// البلاغات
// ---------------------------------------------------------------------

class MaintRequestsPage extends StatefulWidget {
  const MaintRequestsPage({super.key});

  @override
  State<MaintRequestsPage> createState() => _MaintRequestsPageState();
}

class _MaintRequestsPageState extends State<MaintRequestsPage> {
  final _q = TextEditingController();
  String _status = 'open';
  String _priority = '';
  String _category = '';
  String _who = '';

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final m = app.maint;
    final now = DateTime.now();
    final q = _q.text.trim();
    final list = [
      for (final r in m.requests)
        if ((_status == 'all' ||
                (_status == 'open' ? r.isOpen : (_status == 'overdue' ? r.isOverdue(now) : r.status == _status))) &&
            (_priority.isEmpty || r.priority == _priority) &&
            (_category.isEmpty || r.category == _category) &&
            (_who.isEmpty || (_who == '-' ? r.assigneeId == null : r.assigneeId == _who)) &&
            r.matches(q))
          r,
    ]..sort((a, b) {
        if (a.isOpen != b.isOpen) return a.isOpen ? -1 : 1;
        final pa = mtPriorityOrder.indexOf(a.priority), pb = mtPriorityOrder.indexOf(b.priority);
        if (a.isOpen && pa != pb) return pa.compareTo(pb);
        return (b.reportedAt ?? now).compareTo(a.reportedAt ?? now);
      });
    return PageBody(
      onRefresh: app.loadAll,
      children: [
        PageHeader(
          title: 'البلاغات',
          subtitle: 'كل بلاغات الصيانة: الفرز والإسناد والمتابعة حتى تأكيد صاحب البلاغ.',
          icon: Icons.build_circle_rounded,
          actions: [
            if (app.canMtReport) FilledButton.icon(onPressed: () => showMtReportDialog(context), icon: const Icon(Icons.add_rounded), label: const Text('بلاغ جديد')),
            if (app.canMtManage)
              OutlinedButton.icon(
                  onPressed: () => showMtReportDialog(context, onBehalf: true), icon: const Icon(Icons.phone_in_talk_outlined), label: const Text('بلاغ هاتفي')),
          ],
        ),
        if (!app.v24Ready) ...[const MaintNotReady(), const SizedBox(height: 14)],
        Wrap(spacing: 10, runSpacing: 10, children: [
          SizedBox(
            width: 260,
            child: TextField(controller: _q, onChanged: (_) => setState(() {}), decoration: fieldDeco('بحث (رقم، عنوان، أصل، صاحب البلاغ)', prefixIcon: const Icon(Icons.search_rounded))),
          ),
          SizedBox(
            width: 170,
            child: SelectField(
              label: 'الحالة',
              value: _status,
              items: [('open', 'المفتوحة'), ('overdue', 'المتأخرة'), ('all', 'الكل'), for (final e in mtStatusLabels.entries) (e.key, e.value)],
              onChanged: (v) => setState(() => _status = v),
            ),
          ),
          SizedBox(
            width: 150,
            child: SelectField(
              label: 'الأولوية',
              value: _priority,
              items: [('', 'الكل'), for (final p in mtPriorityOrder) (p, mtPriorityLabels[p]!)],
              onChanged: (v) => setState(() => _priority = v),
            ),
          ),
          SizedBox(
            width: 170,
            child: SelectField(
              label: 'التصنيف',
              value: _category,
              items: [('', 'الكل'), for (final e in mtCategoryLabels.entries) (e.key, e.value)],
              onChanged: (v) => setState(() => _category = v),
            ),
          ),
          SizedBox(
            width: 190,
            child: SelectField(
              label: 'المنفّذ',
              value: _who,
              items: [('', 'الكل'), ('-', 'غير مُسنَد'), for (final t in m.technicians) (t.employeeId, t.name)],
              onChanged: (v) => setState(() => _who = v),
            ),
          ),
        ]),
        const SizedBox(height: 12),
        SectionCard(
          title: '${list.length} بلاغ',
          child: list.isEmpty
              ? const EmptyState(title: 'لا بلاغات بهذه المعايير', icon: Icons.build_circle_outlined)
              : Column(children: [for (final r in list.take(300)) MtRequestTile(request: r)]),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------
// بلاغاتي ومهامي
// ---------------------------------------------------------------------

class MaintMinePage extends StatelessWidget {
  const MaintMinePage({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final m = app.maint;
    final mine = m.reportedBy(app.me?.id);
    final waiting = [for (final r in mine) if (app.canMtConfirm(r)) r];
    return PageBody(
      onRefresh: app.loadAll,
      children: [
        PageHeader(
          title: 'بلاغاتي',
          subtitle: 'ارفع بلاغ صيانة وتابع حالته، وأكّد الإصلاح حين يُنجَز.',
          icon: Icons.report_problem_rounded,
          actions: [
            if (app.canMtReport) FilledButton.icon(onPressed: () => showMtReportDialog(context), icon: const Icon(Icons.add_rounded), label: const Text('بلاغ جديد')),
          ],
        ),
        if (!app.v24Ready) ...[const MaintNotReady(), const SizedBox(height: 14)],
        if (waiting.isNotEmpty) ...[
          InfoBanner(level: 'warning', text: 'عندك ${waiting.length} بلاغ أُنجز وينتظر تأكيدك: افتحه وأكّد الإصلاح أو أعد فتحه.'),
          const SizedBox(height: 14),
        ],
        SectionCard(
          title: '${mine.length} بلاغ',
          child: mine.isEmpty
              ? const EmptyState(title: 'لم ترفع بلاغات بعد', message: 'اضغط «بلاغ جديد» حين يتعطل شيء في مكانك.', icon: Icons.report_problem_outlined)
              : Column(children: [for (final r in mine) MtRequestTile(request: r, showReporter: false)]),
        ),
      ],
    );
  }
}

class MaintTasksPage extends StatelessWidget {
  const MaintTasksPage({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final m = app.maint;
    final me = app.me?.id;
    // الخادم يعرض للفني بلاغاته المسنَدة وما رفعه وحده
    final tasks = [for (final r in m.requests) if (r.reporterId != me && r.isOpen) r]
      ..sort((a, b) => (a.dueAt ?? DateTime(2100)).compareTo(b.dueAt ?? DateTime(2100)));
    final done = [for (final r in m.requests) if (r.reporterId != me && !r.isOpen) r];
    return PageBody(
      onRefresh: app.loadAll,
      children: [
        const PageHeader(title: 'مهامي', subtitle: 'البلاغات المسنَدة إليك مرتبةً بموعدها المستهدف.', icon: Icons.engineering_rounded),
        if (!app.v24Ready) ...[const MaintNotReady(), const SizedBox(height: 14)],
        SectionCard(
          title: '${tasks.length} مهمة مفتوحة',
          child: tasks.isEmpty
              ? const EmptyState(title: 'لا مهام مسنَدة إليك الآن', icon: Icons.task_alt_rounded)
              : Column(children: [for (final r in tasks) MtRequestTile(request: r)]),
        ),
        if (done.isNotEmpty) ...[
          const SizedBox(height: 14),
          SectionCard(title: 'المنتهية', child: Column(children: [for (final r in done.take(30)) MtRequestTile(request: r)])),
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------------
// التنبيهات
// ---------------------------------------------------------------------

class MtAlertTile extends StatelessWidget {
  const MtAlertTile({super.key, required this.alert});

  final MtAlert alert;

  @override
  Widget build(BuildContext context) {
    final sem = Sem.of(context);
    final a = alert;
    final color = a.isCritical ? sem.danger : (a.severity == 'warning' ? sem.wip : sem.na);
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: Icon(a.isCritical ? Icons.error_rounded : Icons.notification_important_outlined, color: color),
      title: Text(a.title, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: Text('${mtAlertLabels[a.kind] ?? a.kind}${a.detail.isEmpty ? '' : ' — ${a.detail}'}'),
      trailing: a.since == null ? null : Text(fmtDate(a.since), style: _tabular.copyWith(fontSize: 11, color: sem.muted)),
      onTap: a.isRequest ? () => openMtRequest(context, a.refId) : null,
    );
  }
}

class MaintAlertsPage extends StatelessWidget {
  const MaintAlertsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final m = app.maint;
    final s = m.settings;
    final by = <String, List<MtAlert>>{};
    for (final a in m.alerts) {
      (by[a.kind] ??= []).add(a);
    }
    return PageBody(
      onRefresh: app.loadAll,
      children: [
        const PageHeader(
          title: 'التنبيهات',
          subtitle: 'تُحسب لحظة الفتح بحدود الإعدادات: المتأخر، وغير المُسنَد، والمعلّق طويلاً، وقريب الاستحقاق، وما ينتظر التأكيد، والضمان، وتكرار الأعطال.',
          icon: Icons.notification_important_rounded,
        ),
        if (!app.v24Ready) ...[const MaintNotReady(), const SizedBox(height: 14)],
        if (m.alerts.isEmpty)
          const SectionCard(title: 'لا تنبيهات', child: EmptyState(title: 'كل شيء في موعده', icon: Icons.verified_rounded))
        else
          for (final k in mtAlertOrder)
            if ((by[k] ?? const []).isNotEmpty) ...[
              SectionCard(
                title: '${mtAlertLabels[k]} (${by[k]!.length})',
                subtitle: _alertRule(k, s),
                child: Column(children: [for (final a in by[k]!) MtAlertTile(alert: a)]),
              ),
              const SizedBox(height: 14),
            ],
      ],
    );
  }
}

String _alertRule(String kind, MtSettings s) => switch (kind) {
      'overdue' => 'جاوز موعده المستهدف (المعلّق لا يُحتسب).',
      'unassigned' => 'جديد مضى عليه أكثر من ${s.assignHours} ساعة دون إسناد.',
      'on_hold' => 'معلّق أكثر من ${s.holdDays} أيام.',
      'due_soon' => 'يحل موعده خلال ${s.soonHours} ساعة.',
      'awaiting_confirm' => 'أُنجز ولم يؤكده صاحبه منذ ${s.confirmDays} أيام.',
      'warranty' => 'بلاغ مفتوح على أصل ما زال تحت الضمان.',
      _ => '${s.repeatCount} بلاغات فأكثر على الأصل نفسه خلال ${s.repeatDays} يوماً.',
    };

// ---------------------------------------------------------------------
// الصيانة الدورية
// ---------------------------------------------------------------------

class MaintPlansPage extends StatelessWidget {
  const MaintPlansPage({super.key});

  Future<void> _edit(BuildContext context, MtPlan? p) async {
    final app = AppScope.read(context);
    final m = app.maint;
    final title = TextEditingController(text: p?.title ?? '');
    final every = TextEditingController(text: '${p?.intervalCount ?? 1}');
    final lead = TextEditingController(text: p?.leadDays == null ? '' : '${p!.leadDays}');
    final note = TextEditingController(text: p?.placeNote ?? '');
    final vendor = TextEditingController(text: p?.vendor ?? '');
    final list = TextEditingController(text: p?.checklist ?? '');
    var category = p?.category ?? 'other';
    var unit = p?.intervalUnit ?? 'month';
    var priority = p?.priority ?? 'normal';
    var asset = p?.assetId ?? '';
    var location = p?.locationId ?? '';
    var assignee = p?.assigneeId ?? '';
    var active = p?.active ?? true;
    var start = p?.startDate ?? DateTime.now();
    await storeFormDialog(
      context,
      title: p == null ? 'خطة صيانة دورية جديدة' : 'تعديل ${p.planNo}',
      width: 540,
      body: (set) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        TextField(controller: title, decoration: fieldDeco('اسم الخطة (مثل: فحص مولد الكهرباء)')),
        const SizedBox(height: 10),
        SelectField(label: 'التصنيف', value: category, items: [for (final e in mtCategoryLabels.entries) (e.key, e.value)], onChanged: (v) => set(() => category = v)),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: TextField(controller: every, keyboardType: TextInputType.number, decoration: fieldDeco('كل'))),
          const SizedBox(width: 10),
          Expanded(
            flex: 2,
            child: SelectField(label: 'الوحدة', value: unit, items: [for (final e in mtUnitLabels.entries) (e.key, e.value)], onChanged: (v) => set(() => unit = v)),
          ),
        ]),
        const SizedBox(height: 10),
        DayField(label: 'تاريخ البدء (منه تُحسب كل المواعيد)', value: start, onChanged: (d) => set(() => start = d ?? start)),
        const SizedBox(height: 10),
        TextField(controller: lead, keyboardType: TextInputType.number, decoration: fieldDeco('تنبيه مسبق بالأيام (فارغ = الإعداد العام ${m.settings.planLeadDays})')),
        const SizedBox(height: 10),
        SelectField(
          label: 'الأولوية',
          value: priority,
          items: [for (final x in mtPriorityOrder.reversed) (x, mtPriorityLabels[x]!)],
          onChanged: (v) => set(() => priority = v),
        ),
        const SizedBox(height: 10),
        SelectField(
          label: 'الأصل (اختياري)',
          value: asset,
          items: [('', 'بلا أصل'), for (final a in m.assets) (a.id, '${a.tag} — ${a.name}')],
          onChanged: (v) => set(() => asset = v),
        ),
        const SizedBox(height: 10),
        SelectField(
          label: 'الموقع',
          value: location,
          items: [('', 'غير محدد'), for (final l in m.locations) (l.id, m.locationPath(l.id))],
          onChanged: (v) => set(() => location = v),
        ),
        const SizedBox(height: 10),
        TextField(controller: note, decoration: fieldDeco('وصف المكان (اختياري)')),
        const SizedBox(height: 10),
        SelectField(
          label: 'الفني المسؤول (اختياري)',
          value: assignee,
          items: [('', 'يُسنَد عند الفرز'), for (final t in m.activeTechnicians) (t.employeeId, t.name)],
          onChanged: (v) => set(() => assignee = v),
        ),
        const SizedBox(height: 10),
        TextField(controller: vendor, decoration: fieldDeco('أو جهة خارجية (اختياري)')),
        const SizedBox(height: 10),
        TextField(controller: list, minLines: 2, maxLines: 5, decoration: fieldDeco('بنود الفحص (تظهر في وصف البلاغ المولَّد)')),
        SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('نشطة'), value: active, onChanged: (v) => set(() => active = v)),
      ]),
      onDelete: p == null ? null : () => app.mtDeletePlan(p.id),
      onSave: () async {
        final n = int.tryParse(every.text.trim());
        if (title.text.trim().length < 3) throw StateError('اكتب اسماً للخطة (3 أحرف فأكثر)');
        if (n == null || n < 1) throw StateError('اكتب عدد وحدات التكرار');
        await app.mtSavePlan(p?.id, {
          'title': title.text.trim(),
          'category': category,
          'interval_unit': unit,
          'interval_count': n,
          'start_date': isoDay(start),
          if (lead.text.trim().isNotEmpty) 'lead_days': int.tryParse(lead.text.trim()) ?? -1,
          'priority': priority,
          if (asset.isNotEmpty) 'asset_id': asset,
          if (location.isNotEmpty) 'location_id': location,
          'place_note': note.text.trim(),
          if (assignee.isNotEmpty) 'assignee_id': assignee,
          'vendor': vendor.text.trim(),
          'checklist': list.text.trim(),
          'active': active,
        });
      },
    );
    for (final c in [title, every, lead, note, vendor, list]) {
      c.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final m = app.maint;
    final sem = Sem.of(context);
    final now = DateTime.now();
    final plans = [...m.plans]..sort((a, b) {
        if (a.active != b.active) return a.active ? -1 : 1;
        return (a.nextDue ?? now).compareTo(b.nextDue ?? now);
      });
    return PageBody(
      onRefresh: app.loadAll,
      children: [
        PageHeader(
          title: 'الصيانة الدورية',
          subtitle: 'خطط فحص وصيانة وقائية بتكرار ثابت؛ يُولَّد لكل موعد بلاغ قبل استحقاقه بالتنبيه المسبق.',
          icon: Icons.event_repeat_rounded,
          actions: [
            if (app.canMtManage) FilledButton.icon(onPressed: () => _edit(context, null), icon: const Icon(Icons.add_rounded), label: const Text('خطة جديدة')),
            if (app.canMtManage)
              OutlinedButton.icon(
                onPressed: () async {
                  try {
                    final r = await app.mtGenerateDue();
                    if (context.mounted) showToast(context, r.created == 0 ? 'لا بلاغات جديدة مستحقة' : 'وُلِّد ${r.created} بلاغ وقائي');
                  } catch (e) {
                    if (context.mounted) showToast(context, friendlyError(e), error: true);
                  }
                },
                icon: const Icon(Icons.autorenew_rounded),
                label: const Text('توليد المستحق الآن'),
              ),
          ],
        ),
        if (!app.v24Ready) ...[const MaintNotReady(), const SizedBox(height: 14)],
        SectionCard(
          title: '${plans.length} خطة',
          child: plans.isEmpty
              ? const EmptyState(title: 'لا خطط دورية بعد', message: 'أنشئ خطة لفحص المولد أو تنظيف فلاتر التكييف أو طفايات الحريق.', icon: Icons.event_repeat_outlined)
              : Column(children: [
                  for (final p in plans)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      onTap: app.canMtManage ? () => _edit(context, p) : null,
                      leading: Icon(p.active ? Icons.event_repeat_rounded : Icons.pause_circle_outline_rounded, color: p.active ? sem.na : sem.muted),
                      title: Text(p.title, style: const TextStyle(fontWeight: FontWeight.w700)),
                      subtitle: Text([
                        p.planNo,
                        p.intervalText,
                        mtCategoryLabels[p.category] ?? p.category,
                        if (p.assetTag.isNotEmpty) p.assetTag,
                        if (p.lastDone != null) 'آخر تنفيذ ${isoDay(p.lastDone)}',
                      ].join(' · ')),
                      trailing: p.active
                          ? Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
                              Text(isoDay(p.nextDue), style: _tabular),
                              Text(_dayText(p.daysToDue(now)), style: TextStyle(fontSize: 11.5, color: (p.daysToDue(now) ?? 1) < 0 ? sem.danger : sem.muted)),
                            ])
                          : const Text('موقوفة'),
                    ),
                ]),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------
// الفنيون والإعدادات
// ---------------------------------------------------------------------

class MaintSetupPage extends StatelessWidget {
  const MaintSetupPage({super.key});

  Future<void> _technician(BuildContext context, MtTechnician? t) async {
    final app = AppScope.read(context);
    final m = app.maint;
    var emp = t?.employeeId ?? '';
    var trade = t?.trade ?? 'general';
    var active = t?.active ?? true;
    final note = TextEditingController(text: t?.note ?? '');
    final taken = {for (final x in m.technicians) x.employeeId};
    await storeFormDialog(
      context,
      title: t == null ? 'إضافة فني' : 'تعديل ${t.name}',
      body: (set) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (t == null)
          SelectField(
            label: 'الموظف (من سجل الموظفين)',
            value: emp,
            items: [('', 'اختر'), for (final e in m.employees) if (!taken.contains(e.id)) (e.id, '${e.name}${e.empNo.isEmpty ? '' : ' (${e.empNo})'}')],
            onChanged: (v) => set(() => emp = v),
          ),
        if (t == null) const SizedBox(height: 10),
        SelectField(label: 'التخصص', value: trade, items: [for (final e in mtTradeLabels.entries) (e.key, e.value)], onChanged: (v) => set(() => trade = v)),
        const SizedBox(height: 10),
        TextField(controller: note, decoration: fieldDeco('ملاحظة (اختياري)')),
        SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('نشط (يُسنَد إليه)'), value: active, onChanged: (v) => set(() => active = v)),
        if (t != null && t.hasAccount)
          const Text('له حساب: يرى مهامه بعد أن يمنحه المدير نطاق «فني صيانة».', style: TextStyle(fontSize: 12)),
      ]),
      onSave: () async {
        if (emp.isEmpty) throw StateError('اختر الموظف');
        await app.mtSaveTechnician(emp, {'trade': trade, 'active': active, 'note': note.text.trim()});
      },
    );
    note.dispose();
  }

  Future<void> _settings(BuildContext context) async {
    final app = AppScope.read(context);
    final s = app.maint.settings;
    final sla = {for (final p in mtPriorityOrder) p: TextEditingController(text: '${s.slaHours(p)}')};
    final fields = <(String, String)>[
      ('assign_hours', 'ساعات تنبيه «لم يُسنَد»'),
      ('hold_days', 'أيام تنبيه «معلّق طويلاً»'),
      ('confirm_days', 'أيام تنبيه «ينتظر التأكيد»'),
      ('soon_hours', 'ساعات تنبيه «قريب الاستحقاق»'),
      ('repeat_count', 'عدد البلاغات لتنبيه التكرار'),
      ('repeat_days', 'أيام نافذة التكرار'),
      ('plan_lead_days', 'التنبيه المسبق للخطط (أيام)'),
    ];
    final nums = {for (final f in fields) f.$1: TextEditingController(text: '${s.num_(f.$1)}')};
    await storeFormDialog(
      context,
      title: 'إعدادات الصيانة',
      width: 520,
      body: (set) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Text('مدة الإنجاز بالساعات لكل أولوية', style: TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        for (final p in mtPriorityOrder) ...[
          TextField(controller: sla[p], keyboardType: TextInputType.number, decoration: fieldDeco(mtPriorityLabels[p]!)),
          const SizedBox(height: 8),
        ],
        const SizedBox(height: 6),
        const Text('حدود التنبيه', style: TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        for (final f in fields) ...[
          TextField(controller: nums[f.$1], keyboardType: TextInputType.number, decoration: fieldDeco(f.$2)),
          const SizedBox(height: 8),
        ],
      ]),
      onSave: () async {
        int? n(TextEditingController c) => int.tryParse(c.text.trim());
        final slaMap = <String, int>{};
        for (final p in mtPriorityOrder) {
          final v = n(sla[p]!);
          if (v == null) throw StateError('مدة ${mtPriorityLabels[p]} رقم صحيح');
          slaMap[p] = v;
        }
        final data = <String, dynamic>{'sla_hours': slaMap};
        for (final f in fields) {
          final v = n(nums[f.$1]!);
          if (v == null) throw StateError('${f.$2}: رقم صحيح');
          data[f.$1] = v;
        }
        await app.mtSaveSettings(data);
      },
    );
    for (final c in [...sla.values, ...nums.values]) {
      c.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final m = app.maint;
    final s = m.settings;
    final sem = Sem.of(context);
    final edit = app.canMtAdmin;
    return PageBody(
      onRefresh: app.loadAll,
      children: [
        const PageHeader(
          title: 'الفنيون والإعدادات',
          subtitle: 'قائمة الفنيين الذين يُسنَد إليهم، ومدد الإنجاز بحسب الأولوية، وحدود التنبيهات.',
          icon: Icons.settings_suggest_rounded,
        ),
        if (!app.v24Ready) ...[const MaintNotReady(), const SizedBox(height: 14)],
        if (!edit && app.v24Ready) const Padding(padding: EdgeInsets.only(bottom: 14), child: InfoBanner(text: 'للاطلاع فقط: التعديل لمدير النظام في الصيانة أو المدير.')),
        SectionCard(
          title: 'الفنيون',
          icon: Icons.engineering_rounded,
          trailing: edit ? FilledButton.icon(onPressed: () => _technician(context, null), icon: const Icon(Icons.add_rounded), label: const Text('إضافة فني')) : null,
          child: m.technicians.isEmpty
              ? const EmptyState(title: 'لا فنيين بعد', message: 'أضف موظفاً من سجل الموظفين ليُسنَد إليه. لمن له حساب: يمنحه المدير نطاق «فني صيانة».', icon: Icons.engineering_outlined)
              : Column(children: [
                  for (final t in m.technicians)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      onTap: edit ? () => _technician(context, t) : null,
                      leading: Icon(Icons.engineering_outlined, color: t.active ? sem.na : sem.muted),
                      title: Text(t.name),
                      subtitle: Text([mtTradeLabels[t.trade] ?? t.trade, if (t.empNo.isNotEmpty) t.empNo, if (t.hasAccount) 'له حساب'].join(' · ')),
                      trailing: t.active ? null : const Text('موقوف'),
                    ),
                ]),
        ),
        const SizedBox(height: 14),
        SectionCard(
          title: 'مدد الإنجاز والتنبيهات',
          icon: Icons.tune_rounded,
          trailing: edit ? OutlinedButton.icon(onPressed: () => _settings(context), icon: const Icon(Icons.edit_outlined), label: const Text('تعديل')) : null,
          child: Column(children: [
            for (final p in mtPriorityOrder) _row('مدة إنجاز ${mtPriorityLabels[p]}', '${s.slaHours(p)} ساعة'),
            _row('تنبيه «لم يُسنَد» بعد', '${s.assignHours} ساعة'),
            _row('تنبيه «معلّق طويلاً» بعد', '${s.holdDays} أيام'),
            _row('تنبيه «ينتظر التأكيد» بعد', '${s.confirmDays} أيام'),
            _row('تنبيه «قريب الاستحقاق» قبل', '${s.soonHours} ساعة'),
            _row('تنبيه التكرار', '${s.repeatCount} بلاغات خلال ${s.repeatDays} يوماً'),
            _row('التنبيه المسبق للخطط', '${s.planLeadDays} أيام'),
          ]),
        ),
      ],
    );
  }

  Widget _row(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(children: [Expanded(child: Text(k)), Text(v, style: _tabular.copyWith(fontWeight: FontWeight.w700))]),
      );
}
