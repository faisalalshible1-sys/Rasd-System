import 'package:flutter/material.dart';

import '../app_state.dart';
import '../disbursement.dart';
import '../guarantees.dart' show FinAccount;
import '../models.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';
import 'pm_common.dart';

/// اعتماد الصرف (الإصدار 3.4.0، الترحيل 51): طلب فمراجعة مالية فاعتماد، ثم قيد آلي ودفعة للمستخلص.
class DisbursementsPage extends StatefulWidget {
  const DisbursementsPage({super.key});

  @override
  State<DisbursementsPage> createState() => _DisbursementsPageState();
}

class _DisbursementsPageState extends State<DisbursementsPage> {
  String _filter = 'open';

  Future<void> _run(Future<void> Function() f, String done) async {
    try {
      await f();
      if (mounted) showToast(context, done);
    } catch (e) {
      if (mounted) showToast(context, friendlyError(e), error: true);
    }
  }

  String _extractLabel(AppState app, ContractExtract e) {
    final p = app.projects.where((x) => x.id == e.projectId).firstOrNull;
    return '${p?.shortName ?? 'عقد'} — ${e.title}';
  }

  Future<void> _request(AppState app) async {
    final exts = app.extracts.where((e) => (e.status == 'approved' || e.status == 'referred') && app.extractRemainingOf(e) > 0).toList();
    final accs = app.finAccounts.where((a) => a.active && a.glAccountId != null).toList();
    if (exts.isEmpty) {
      showToast(context, 'لا مستخلص معتمد له متبقٍ للصرف', error: true);
      return;
    }
    if (accs.isEmpty) {
      showToast(context, 'اربط حساباً مالياً بدليل الحسابات أولاً (صفحة دليل الحسابات)', error: true);
      return;
    }
    final ok = await showPmForm(
      context,
      title: 'طلب صرف مستخلص',
      note: 'اعتماد المستخلص ليس صرفاً. يمرّ الطلب بمراجعة مالية ثم باعتماد من يملك صلاحية الاعتماد، وعندها تُسجَّل الدفعة ويُنشأ القيد.',
      sections: [
        PmSection('الطلب', [
          PmField('extract', 'المستخلص', PmKind.select, required: true, full: true, options: [
            for (final e in exts) (e.id, '${_extractLabel(app, e)} — المتبقي ${fmtMoney(app.extractRemainingOf(e))}'),
          ]),
          const PmField('amount', 'المبلغ', PmKind.decimal, required: true),
          PmField('account', 'الحساب المالي', PmKind.select, required: true, options: [
            for (final a in accs) (a.id, '${a.name} (${fmtMoney(app.balanceOf(a))})'),
          ]),
          const PmField('date', 'تاريخ الصرف', PmKind.date, required: true),
          PmField('method', 'طريقة الدفع', PmKind.select, required: true, options: [for (final m in disbMethodNames.entries) (m.key, m.value)]),
          const PmField('ref', 'رقم الصك أو الحوالة', PmKind.text, max: 80),
          const PmField('note', 'ملاحظة', PmKind.multiline, max: 300, full: true),
        ]),
      ],
      values: {'method': 'transfer', 'date': DateTime.now()},
      onSave: (d) => app.requestDisbursement(
        extractId: '${d['extract']}',
        amount: (d['amount'] as num).toDouble(),
        accountId: '${d['account']}',
        date: DateTime.parse('${d['date']}'),
        method: '${d['method']}',
        refNo: '${d['ref'] ?? ''}'.trim(),
        note: '${d['note'] ?? ''}'.trim(),
      ),
    );
    if (ok && mounted) showToast(context, 'رُفع طلب الصرف للمراجعة');
  }

  Future<void> _retention(AppState app, ContractExtract e) async {
    final p = app.projects.where((x) => x.id == e.projectId).firstOrNull;
    final ok = await showPmForm(
      context,
      title: 'تسجيل المحتجز ضماناً',
      note: 'يُسجَّل مبلغ المحتجز المخصوم في ${e.title} (${fmtMoney(e.retention)}) ضمان محتجز مرتبطاً بالمستخلص، ولا يتكرر.',
      sections: [
        const PmSection('الجهة', [PmField('party', 'الجهة (المقاول)', PmKind.text, required: true, max: 120, full: true)]),
      ],
      values: {'party': p?.company ?? ''},
      onSave: (d) => app.registerRetentionGuarantee(e.id, '${d['party']}'.trim()),
    );
    if (ok && mounted) showToast(context, 'سُجّل المحتجز ضماناً');
  }

  Future<void> _review(AppState app, FinDisbursement d, bool ok) async {
    final done = await showPmForm(
      context,
      title: ok ? 'مراجعة مالية: سليم' : 'إعادة الطلب للتصحيح',
      sections: [
        PmSection('المراجعة', [PmField('note', ok ? 'ملاحظة (اختياري)' : 'سبب الإعادة', PmKind.multiline, required: !ok, max: 300, full: true)]),
      ],
      values: const {},
      onSave: (v) => app.reviewDisbursement(d.id, ok, '${v['note'] ?? ''}'.trim()),
    );
    if (done && mounted) showToast(context, ok ? 'روجع الطلب وأُحيل للاعتماد' : 'أُعيد الطلب');
  }

  Future<void> _decide(AppState app, FinDisbursement d, bool approve) async {
    final done = await showPmForm(
      context,
      title: approve ? 'اعتماد الصرف' : 'رفض الصرف',
      note: approve ? 'يُسجَّل المبلغ دفعةً للمستخلص ويُخفَّض رصيد الحساب ويُنشأ قيد آلي (مدين مستحقات المقاولين ودائن الحساب).' : null,
      sections: [
        PmSection('القرار', [PmField('note', approve ? 'ملاحظة (اختياري)' : 'سبب الرفض', PmKind.multiline, required: !approve, max: 300, full: true)]),
      ],
      values: const {},
      onSave: (v) => app.decideDisbursement(d.id, approve, '${v['note'] ?? ''}'.trim()),
    );
    if (done && mounted) showToast(context, approve ? 'اعتُمد الصرف' : 'رُفض الطلب');
  }

  Future<void> _reverse(AppState app, FinDisbursement d) async {
    final done = await showPmForm(
      context,
      title: 'عكس الصرف',
      note: 'تُحذف الدفعة من المستخلص (فيعود «معتمداً» إن كان «مدفوعاً»)، ويُنشأ قيد عكسي، ويعود رصيد الحساب. لا يُعكس الصرف مرتين.',
      sections: [
        const PmSection('العكس', [PmField('reason', 'سبب العكس', PmKind.multiline, required: true, max: 300, full: true)]),
      ],
      values: const {},
      onSave: (v) => app.reverseDisbursement(d.id, '${v['reason']}'.trim()),
    );
    if (done && mounted) showToast(context, 'عُكس الصرف');
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final sem = Sem.of(context);
    if (!app.v35Ready) {
      return PageBody(children: [
        const PageHeader(title: 'اعتماد الصرف', icon: Icons.price_check_outlined),
        const InfoBanner(text: 'اعتماد الصرف يعمل بعد تطبيق الترحيل 51 على قاعدة البيانات.', level: 'warning'),
      ]);
    }
    final canEdit = app.canEditFinSettings;
    final canApprove = app.canApproveFinance;
    final list = app.finDisbursements.where((d) {
      return switch (_filter) {
        'open' => d.isOpen,
        'approved' => d.isApproved,
        'closed' => !d.isOpen && !d.isApproved,
        _ => true,
      };
    }).toList()
      ..sort((a, b) => (b.requestedAt ?? DateTime(2000)).compareTo(a.requestedAt ?? DateTime(2000)));
    final waitReview = app.finDisbursements.where((d) => d.isRequested).length;
    final waitDecide = app.finDisbursements.where((d) => d.isReviewed).length;
    return PageBody(
      onRefresh: app.loadAll,
      children: [
        PageHeader(
          title: 'اعتماد الصرف',
          subtitle: 'طلب فمراجعة مالية فاعتماد؛ واعتماد المستخلص وحده لا يعني صرفه.',
          icon: Icons.price_check_outlined,
          actions: [
            if (canEdit) FilledButton.icon(onPressed: () => _request(app), icon: const Icon(Icons.add_rounded), label: const Text('طلب صرف')),
          ],
        ),
        if (waitReview > 0 && canEdit) InfoBanner(text: 'بانتظار المراجعة المالية: $waitReview طلب.', level: 'info'),
        if (waitDecide > 0 && canApprove) InfoBanner(text: 'بانتظار الاعتماد: $waitDecide طلب.', level: 'info'),
        Wrap(spacing: 10, runSpacing: 8, children: [
          pmFilter('العرض', _filter, const [('open', 'المفتوحة'), ('approved', 'المصروفة'), ('closed', 'المغلقة'), ('all', 'الكل')], (v) => setState(() => _filter = v)),
        ]),
        const SizedBox(height: 10),
        if (list.isEmpty)
          const EmptyState(title: 'لا طلبات صرف', message: 'يظهر هنا ما يُطلب صرفه من المستخلصات المعتمدة.', icon: Icons.price_check_outlined)
        else
          for (final d in list)
            Builder(builder: (context) {
              final e = app.extracts.where((x) => x.id == d.extractId).firstOrNull;
              final acc = app.finAccounts.where((a) => a.id == d.accountId).firstOrNull;
              final tone = d.isApproved ? sem.ok : (d.isOpen ? sem.wip : (d.status == 'returned' ? sem.danger : sem.muted));
              final needRetention = e != null && e.retention > 0 && !app.finGuarantees.any((g) => g.extractId == e.id);
              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Expanded(child: Text(e == null ? 'مستخلص' : _extractLabel(app, e), style: const TextStyle(fontWeight: FontWeight.w700))),
                      ToneBadge(d.statusLabel, color: tone),
                    ]),
                    const SizedBox(height: 4),
                    Text('${fmtMoney(d.amount)} · ${acc?.name ?? '—'} · ${d.methodLabel}${d.refNo.isEmpty ? '' : ' ${d.refNo}'} · ${fmtDate(d.payDate)}'),
                    if (d.note.isNotEmpty) Text(d.note, style: TextStyle(color: sem.muted)),
                    if (d.reviewNote.isNotEmpty) Text('المراجعة: ${d.reviewNote}', style: TextStyle(color: sem.muted)),
                    if (d.decisionNote.isNotEmpty) Text('القرار: ${d.decisionNote}', style: TextStyle(color: sem.muted)),
                    if (d.reverseReason.isNotEmpty) Text('سبب العكس: ${d.reverseReason}', style: TextStyle(color: sem.muted)),
                    if (e != null && d.isOpen && needRetention) InfoBanner(text: 'المحتجز (${fmtMoney(e.retention)}) غير مسجَّل ضماناً؛ يُسجَّل قبل المراجعة.', level: 'warning'),
                    const SizedBox(height: 6),
                    Wrap(spacing: 8, runSpacing: 6, children: [
                      if (canEdit && e != null && d.isOpen && needRetention) OutlinedButton(onPressed: () => _retention(app, e), child: const Text('تسجيل المحتجز ضماناً')),
                      if (canEdit && d.isRequested) FilledButton.tonal(onPressed: () => _review(app, d, true), child: const Text('مراجعة: سليم')),
                      if (canEdit && d.isRequested) OutlinedButton(onPressed: () => _review(app, d, false), child: const Text('إعادة للتصحيح')),
                      if (canEdit && d.isOpen)
                        TextButton(
                          onPressed: () async {
                            if (await confirmDialog(context, title: 'إلغاء الطلب', message: 'يُلغى طلب الصرف ولا يُصرف شيء.', confirmLabel: 'إلغاء الطلب') && mounted) {
                              _run(() => app.cancelDisbursement(d.id), 'أُلغي الطلب');
                            }
                          },
                          child: const Text('إلغاء'),
                        ),
                      if (canApprove && d.isReviewed) FilledButton(onPressed: () => _decide(app, d, true), child: const Text('اعتماد الصرف')),
                      if (canApprove && d.isReviewed) OutlinedButton(onPressed: () => _decide(app, d, false), child: const Text('رفض')),
                      if (canApprove && d.isApproved) OutlinedButton(onPressed: () => _reverse(app, d), child: const Text('عكس الصرف')),
                    ]),
                  ]),
                ),
              );
            }),
      ],
    );
  }
}
