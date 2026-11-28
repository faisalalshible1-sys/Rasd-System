import 'package:flutter/material.dart';

import '../app_state.dart';
import '../guarantees.dart';
import '../models.dart';
import '../print/export_dialog.dart';
import '../print/model.dart' show fmtNumber;
import '../ui/theme.dart';
import '../ui/widgets.dart';
import 'pm_common.dart';

Future<void> _run(BuildContext context, Future<void> Function() f, String done) async {
  try {
    await f();
    if (context.mounted) showToast(context, done);
  } catch (e) {
    if (context.mounted) showToast(context, friendlyError(e), error: true);
  }
}

DateTime? _opt(Object? v) {
  final s = '${v ?? ''}';
  return s.isEmpty ? null : DateTime.tryParse(s);
}

String _projectLabel(AppState app, String? id) {
  if (id == null) return '';
  for (final p in app.projects) {
    if (p.id == id) return p.label;
  }
  return '';
}

// ---------------------------------------------------------------------
// الضمانات والتأمينات النقدية
// ---------------------------------------------------------------------

class GuaranteesPage extends StatefulWidget {
  const GuaranteesPage({super.key});

  @override
  State<GuaranteesPage> createState() => _GuaranteesPageState();
}

class _GuaranteesPageState extends State<GuaranteesPage> {
  String _filter = 'all';

  Future<void> _edit(AppState app, {FinGuarantee? g, String? kind, String? projectId, double? amount, String? party}) async {
    final projects = [...app.scoped]..sort((a, b) => a.label.compareTo(b.label));
    final ok = await showPmForm(
      context,
      title: g == null ? 'تسجيل ضمان' : 'تعديل الضمان',
      note: 'يُسجَّل الضمان بما استلمته الجهة فعلاً؛ لا يُحسب مبلغه من نسبة العقد تلقائياً. بعد التسجيل لا يُسترد إلا بطلب ثم موافقة.',
      sections: [
        PmSection('الضمان', [
          PmField('kind', 'النوع', PmKind.select, required: true, options: [for (final k in guaranteeKindNames.entries) (k.key, k.value)]),
          PmField('project', 'العقد (اختياري)', PmKind.select, options: [
            ('', 'بلا ربط'),
            for (final p in projects) (p.id, p.label),
          ]),
          const PmField('party', 'الجهة (المقاول أو المصرف)', PmKind.text, required: true, max: 120, full: true),
          const PmField('amount', 'المبلغ', PmKind.decimal, required: true),
          const PmField('issued', 'تاريخ الإصدار', PmKind.date, required: true),
          const PmField('expires', 'تاريخ الانتهاء', PmKind.date),
          const PmField('ref', 'المرجع (رقم الخطاب أو الإيصال)', PmKind.text, max: 80),
          const PmField('note', 'ملاحظة', PmKind.multiline, max: 300, full: true),
        ]),
      ],
      values: g == null
          ? {'kind': kind ?? 'initial', 'project': projectId ?? '', 'party': party ?? '', 'amount': amount, 'issued': DateTime.now()}
          : {
              'kind': g.kind,
              'project': g.projectId ?? '',
              'party': g.party,
              'amount': g.amount,
              'issued': g.issued,
              'expires': g.expires,
              'ref': g.reference,
              'note': g.note,
            },
      onSave: (d) => app.saveFinGuarantee(
        id: g?.id,
        kind: '${d['kind']}',
        projectId: '${d['project'] ?? ''}'.isEmpty ? null : '${d['project']}',
        party: '${d['party']}',
        amount: (d['amount'] as num).toDouble(),
        issued: DateTime.parse('${d['issued']}'),
        expires: _opt(d['expires']),
        reference: '${d['ref'] ?? ''}',
        note: '${d['note'] ?? ''}',
      ),
    );
    if (ok && mounted) showToast(context, g == null ? 'سُجّل الضمان' : 'حُفظ الضمان');
  }

  Future<void> _request(AppState app, FinGuarantee g) async {
    final ok = await showPmForm(
      context,
      title: 'طلب استرداد ضمان «${g.party}»',
      note: 'يجمّد الطلب الضمان حتى يوافق من يملك صلاحية الاعتماد أو يرفض بسبب.',
      sections: [
        const PmSection('الطلب', [PmField('reason', 'سبب الاسترداد', PmKind.multiline, required: true, max: 300, full: true)]),
      ],
      values: const {},
      onSave: (d) => app.requestGuaranteeRelease(g.id, '${d['reason']}'.trim()),
    );
    if (ok && mounted) showToast(context, 'أُرسل طلب الاسترداد للموافقة');
  }

  Future<void> _reject(AppState app, FinGuarantee g) async {
    final ok = await showPmForm(
      context,
      title: 'رفض استرداد «${g.party}»',
      note: 'يعود الضمان محتجزاً ويظهر سبب الرفض عليه.',
      sections: [
        const PmSection('الرفض', [PmField('note', 'سبب الرفض', PmKind.multiline, required: true, max: 300, full: true)]),
      ],
      values: const {},
      onSave: (d) => app.decideGuaranteeRelease(g.id, false, note: '${d['note']}'.trim()),
    );
    if (ok && mounted) showToast(context, 'رُفض الاسترداد وعاد الضمان محتجزاً');
  }

  Color _expiryColor(Sem sem, String s) => switch (s) {
        'expired' => sem.danger,
        'soon' => sem.wip,
        _ => sem.ok,
      };

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final sem = Sem.of(context);
    if (!app.v33Ready) {
      return PageBody(children: const [
        PageHeader(title: 'الضمانات', icon: Icons.verified_user_outlined),
        InfoBanner(text: 'الضمانات تعمل بعد تطبيق الترحيل 49 على قاعدة البيانات.', level: 'warning'),
      ]);
    }
    final canEdit = app.canEditFinSettings;
    final canApprove = app.canApprovePayroll;
    final today = DateTime.now();
    final all = [...app.finGuarantees]..sort((a, b) => b.issued.compareTo(a.issued));
    final shown = switch (_filter) {
      'held' => all.where((g) => g.isHeld).toList(),
      'requested' => all.where((g) => g.isRequested).toList(),
      'released' => all.where((g) => g.isReleased).toList(),
      _ => all,
    };
    final t = guaranteeTotals(all, today);

    // اقتراحات من العقود: ضمانات لم تُسجَّل بعد، تؤكدها بالتسجيل ولا تُطبَّق تلقائياً
    final suggestions = <({Project p, String kind, double amount})>[];
    if (canEdit) {
      for (final p in app.scoped) {
        bool has(String k) => all.any((g) => g.projectId == p.id && g.kind == k);
        final gi = p.guaranteeInitial, gf = p.guaranteeFinal;
        if (!p.guaranteeInitialNa && gi != null && gi > 0 && !has('initial')) suggestions.add((p: p, kind: 'initial', amount: gi));
        if (!p.guaranteeFinalNa && gf != null && gf > 0 && !has('final')) suggestions.add((p: p, kind: 'final', amount: gf));
        if (p.retentionHeld > 0 && !has('retention')) suggestions.add((p: p, kind: 'retention', amount: p.retentionHeld));
      }
    }

    return PageBody(
      onRefresh: app.loadAll,
      children: [
        PageHeader(
          title: 'الضمانات والتأمينات',
          subtitle: 'ضمانات العقود والمحتجز والتأمينات النقدية، ولا يُسترد منها شيء إلا بطلب وموافقة.',
          icon: Icons.verified_user_outlined,
          actions: [
            if (all.isNotEmpty) ExportButton(sourceId: 'finance:guarantees', items: List<Object>.from(shown)),
            if (canEdit) FilledButton.icon(onPressed: () => _edit(app), icon: const Icon(Icons.add_rounded), label: const Text('ضمان')),
          ],
        ),
        Wrap(spacing: 10, runSpacing: 10, children: [
          SizedBox(width: 190, child: KpiTile(label: 'محتجز', value: fmtMoney(t.held))),
          SizedBox(width: 190, child: KpiTile(label: 'بانتظار موافقة الاسترداد', value: fmtMoney(t.requested), color: t.requested > 0 ? sem.wip : null)),
          SizedBox(width: 190, child: KpiTile(label: 'مُسترد', value: fmtMoney(t.released))),
          SizedBox(width: 190, child: KpiTile(label: 'منتهٍ أو قريب الانتهاء', value: '${t.expiring}', color: t.expiring > 0 ? sem.danger : null, sub: 'خلال $guaranteeWarnDays يوماً')),
        ]),
        const SizedBox(height: 12),
        Wrap(spacing: 8, children: [
          for (final f in const [('all', 'الكل'), ('held', 'محتجز'), ('requested', 'طُلب استرداده'), ('released', 'مُسترد')])
            ChoiceChip(label: Text(f.$2), selected: _filter == f.$1, onSelected: (_) => setState(() => _filter = f.$1)),
        ]),
        const SizedBox(height: 12),
        if (suggestions.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: SectionCard(
              title: 'ضمانات من العقود لم تُسجَّل',
              icon: Icons.lightbulb_outline_rounded,
              subtitle: 'مبالغ مقترحة من بيانات العقد؛ لا تُسجَّل إلا بعد تأكيدك لها.',
              child: Column(children: [
                for (final s in suggestions.take(12))
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text('${guaranteeKindNames[s.kind]} — ${fmtMoney(s.amount)}'),
                    subtitle: Text(s.p.label),
                    trailing: TextButton(
                      onPressed: () => _edit(app, kind: s.kind, projectId: s.p.id, amount: s.amount, party: s.p.company),
                      child: const Text('تسجيل'),
                    ),
                  ),
                if (suggestions.length > 12) Text('و${suggestions.length - 12} أخرى'),
              ]),
            ),
          ),
        if (shown.isEmpty)
          EmptyState(
            title: 'لا ضمانات',
            message: canEdit ? 'سجّل ضماناً أو تأميناً نقدياً ليظهر هنا.' : 'يسجّل المدير أو من مُنح صلاحية التحرير الضمانات.',
            icon: Icons.verified_user_outlined,
          )
        else
          for (final g in shown)
            () {
              final ex = guaranteeExpiry(g, today);
              final proj = _projectLabel(app, g.projectId);
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: SectionCard(
                  title: '${guaranteeKindNames[g.kind]} — ${fmtMoney(g.amount)}',
                  icon: Icons.verified_user_outlined,
                  subtitle: '${g.party}${proj.isEmpty ? '' : ' · $proj'}',
                  trailing: Wrap(spacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
                    if (ex == 'expired' || ex == 'soon') ToneBadge(ex == 'expired' ? 'منتهٍ' : 'قارب الانتهاء', color: _expiryColor(sem, ex)),
                    ToneBadge(guaranteeStatusNames[g.status] ?? g.status, color: g.isReleased ? sem.ok : (g.isRequested ? sem.wip : sem.muted)),
                  ]),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('الإصدار ${fmtDate(g.issued)}${g.expires == null ? '' : ' · الانتهاء ${fmtDate(g.expires)}'}${g.reference.isEmpty ? '' : ' · المرجع ${g.reference}'}'),
                    if (g.note.isNotEmpty) Text(g.note),
                    if (g.isRequested) Text('سبب الاسترداد: ${g.releaseReason}', style: TextStyle(color: sem.wip)),
                    if (g.isHeld && g.decisionNote.isNotEmpty) Text('رُفض الاسترداد: ${g.decisionNote}', style: TextStyle(color: sem.danger)),
                    if (g.isReleased && g.decisionNote.isNotEmpty) Text('ملاحظة الموافقة: ${g.decisionNote}'),
                    const SizedBox(height: 6),
                    Wrap(spacing: 6, children: [
                      if (canEdit && g.isHeld) ...[
                        OutlinedButton(onPressed: () => _edit(app, g: g), child: const Text('تعديل')),
                        OutlinedButton(onPressed: () => _request(app, g), child: const Text('طلب استرداد')),
                        TextButton(
                          onPressed: () async {
                            final ok = await confirmDialog(context, title: 'حذف الضمان', message: 'يُحذف هذا الضمان من السجل.', confirmLabel: 'حذف', danger: true);
                            if (ok && mounted) await _run(context, () => app.deleteFinGuarantee(g.id), 'حُذف الضمان');
                          },
                          child: const Text('حذف'),
                        ),
                      ],
                      if (canApprove && g.isRequested) ...[
                        FilledButton(
                          onPressed: () async {
                            final ok = await confirmDialog(context,
                                title: 'الموافقة على الاسترداد', message: 'يُعدّ ضمان «${g.party}» (${fmtMoney(g.amount)}) مُستَرَدّاً.', confirmLabel: 'موافقة');
                            if (ok && mounted) await _run(context, () => app.decideGuaranteeRelease(g.id, true), 'وُوفق على الاسترداد');
                          },
                          child: const Text('موافقة'),
                        ),
                        OutlinedButton(onPressed: () => _reject(app, g), child: const Text('رفض')),
                      ],
                    ]),
                  ]),
                ),
              );
            }(),
      ],
    );
  }
}

// ---------------------------------------------------------------------
// الحسابات والتحويلات
// ---------------------------------------------------------------------

class TransfersPage extends StatefulWidget {
  const TransfersPage({super.key});

  @override
  State<TransfersPage> createState() => _TransfersPageState();
}

class _TransfersPageState extends State<TransfersPage> {
  Future<void> _account(AppState app, {FinAccount? a}) async {
    final ok = await showPmForm(
      context,
      title: a == null ? 'حساب جديد' : 'تعديل الحساب',
      note: 'الرصيد = الافتتاحي + التحويلات المرحَّلة وارداً − المرحَّلة صادراً. لا يُعدَّل الافتتاحي بعد أول تحويل مرحَّل.',
      sections: [
        PmSection('الحساب', [
          const PmField('name', 'الاسم', PmKind.text, required: true, max: 80),
          PmField('kind', 'النوع', PmKind.select, required: true, options: [for (final k in accountKindNames.entries) (k.key, k.value)]),
          const PmField('opening', 'الرصيد الافتتاحي', PmKind.decimal, required: true),
          const PmField('active', 'مفعّل', PmKind.toggle),
        ]),
      ],
      values: a == null ? {'kind': 'bank', 'opening': 0, 'active': true} : {'name': a.name, 'kind': a.kind, 'opening': a.opening, 'active': a.active},
      onSave: (d) => app.saveFinAccount(
        id: a?.id,
        name: '${d['name']}',
        kind: '${d['kind']}',
        opening: (d['opening'] as num).toDouble(),
        active: d['active'] == true,
      ),
    );
    if (ok && mounted) showToast(context, 'حُفظ الحساب');
  }

  Future<void> _transfer(AppState app) async {
    final accs = app.finAccounts.where((a) => a.active).toList();
    final ok = await showPmForm(
      context,
      title: 'تحويل بين حسابين',
      note: 'يُسجَّل معلّقاً ولا يؤثر على الأرصدة حتى يوافق من يملك صلاحية الاعتماد، ولا يُوافَق عليه إن زاد عن رصيد الحساب المحوَّل منه.',
      sections: [
        PmSection('التحويل', [
          PmField('from', 'من حساب', PmKind.select, required: true, options: [for (final a in accs) (a.id, '${a.name} (${fmtMoney(app.balanceOf(a))})')]),
          PmField('to', 'إلى حساب', PmKind.select, required: true, options: [for (final a in accs) (a.id, a.name)]),
          const PmField('amount', 'المبلغ', PmKind.decimal, required: true),
          const PmField('date', 'التاريخ', PmKind.date, required: true),
          const PmField('note', 'ملاحظة', PmKind.multiline, max: 300, full: true),
        ]),
      ],
      values: {'date': DateTime.now()},
      onSave: (d) => app.createFinTransfer('${d['from']}', '${d['to']}', (d['amount'] as num).toDouble(), DateTime.parse('${d['date']}'), note: '${d['note'] ?? ''}'),
    );
    if (ok && mounted) showToast(context, 'سُجّل التحويل بانتظار الموافقة');
  }

  Future<void> _reject(AppState app, FinTransfer t) async {
    final ok = await showPmForm(
      context,
      title: 'رفض التحويل',
      sections: [
        const PmSection('الرفض', [PmField('note', 'سبب الرفض', PmKind.multiline, required: true, max: 300, full: true)]),
      ],
      values: const {},
      onSave: (d) => app.decideFinTransfer(t.id, false, note: '${d['note']}'.trim()),
    );
    if (ok && mounted) showToast(context, 'رُفض التحويل');
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final sem = Sem.of(context);
    if (!app.v33Ready) {
      return PageBody(children: const [
        PageHeader(title: 'الحسابات والتحويلات', icon: Icons.swap_horiz_rounded),
        InfoBanner(text: 'الحسابات والتحويلات تعمل بعد تطبيق الترحيل 49 على قاعدة البيانات.', level: 'warning'),
      ]);
    }
    final canEdit = app.canEditFinSettings;
    final canApprove = app.canApprovePayroll;
    String nameOf(String id) => app.finAccounts.where((a) => a.id == id).map((a) => a.name).firstOrNull ?? '—';
    final transfers = [...app.finTransfers]..sort((a, b) => b.date.compareTo(a.date));
    final total = app.finAccounts.fold<double>(0, (s, a) => s + app.balanceOf(a));
    return PageBody(
      onRefresh: app.loadAll,
      children: [
        PageHeader(
          title: 'الحسابات والتحويلات',
          subtitle: 'حسابات نقدية ومصرفية وتحويلات بينها بموافقة قبل أن تغيّر الأرصدة.',
          icon: Icons.swap_horiz_rounded,
          actions: [
            if (transfers.isNotEmpty) ExportButton(sourceId: 'finance:transfers', items: List<Object>.from(transfers)),
            if (canEdit) OutlinedButton.icon(onPressed: () => _account(app), icon: const Icon(Icons.account_balance_outlined), label: const Text('حساب')),
            if (canEdit && app.finAccounts.where((a) => a.active).length >= 2)
              FilledButton.icon(onPressed: () => _transfer(app), icon: const Icon(Icons.swap_horiz_rounded), label: const Text('تحويل')),
          ],
        ),
        if (app.finAccounts.isEmpty)
          EmptyState(
            title: 'لا حسابات',
            message: canEdit ? 'أضف حساباً نقدياً أو مصرفياً برصيده الافتتاحي.' : 'يضيف المدير أو من مُنح صلاحية التحرير الحسابات.',
            icon: Icons.account_balance_outlined,
          )
        else ...[
          SectionCard(
            title: 'الأرصدة',
            icon: Icons.account_balance_wallet_outlined,
            subtitle: 'المجموع ${fmtMoney(total)}',
            child: Column(children: [
              for (final a in app.finAccounts)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(a.kind == 'cash' ? Icons.payments_outlined : Icons.account_balance_outlined),
                  title: Text('${a.name}${a.active ? '' : ' (موقوف)'}'),
                  subtitle: Text('${accountKindNames[a.kind]} · افتتاحي ${fmtMoney(a.opening)}'),
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    Text(fmtMoney(app.balanceOf(a)), style: const TextStyle(fontWeight: FontWeight.w700)),
                    if (canEdit) IconButton(onPressed: () => _account(app, a: a), icon: const Icon(Icons.edit_outlined)),
                    if (canEdit)
                      IconButton(
                        onPressed: () => _run(context, () => app.deleteFinAccount(a.id), 'حُذف الحساب'),
                        icon: const Icon(Icons.delete_outline_rounded),
                      ),
                  ]),
                ),
            ]),
          ),
          const SizedBox(height: 12),
          SectionCard(
            title: 'التحويلات',
            icon: Icons.swap_horiz_rounded,
            child: transfers.isEmpty
                ? const Text('لا تحويلات')
                : Column(children: [
                    for (final t in transfers)
                      ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text('${nameOf(t.fromId)} ← ${nameOf(t.toId)} — ${fmtMoney(t.amount)}'),
                        subtitle: Text([fmtDate(t.date), if (t.note.isNotEmpty) t.note, if (t.decisionNote.isNotEmpty) 'القرار: ${t.decisionNote}'].join(' · ')),
                        trailing: Wrap(spacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                          ToneBadge(transferStatusNames[t.status] ?? t.status, color: t.isPosted ? sem.ok : (t.isPending ? sem.wip : sem.danger)),
                          if (t.isPending && canApprove) ...[
                            TextButton(onPressed: () => _run(context, () => app.decideFinTransfer(t.id, true), 'رُحّل التحويل'), child: const Text('موافقة')),
                            TextButton(onPressed: () => _reject(app, t), child: const Text('رفض')),
                          ],
                          if (t.isPending && canEdit)
                            IconButton(
                              tooltip: 'حذف',
                              onPressed: () => _run(context, () => app.deleteFinTransfer(t.id), 'حُذف التحويل'),
                              icon: const Icon(Icons.delete_outline_rounded),
                            ),
                        ]),
                      ),
                  ]),
          ),
        ],
      ],
    );
  }
}
