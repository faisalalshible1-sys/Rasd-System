import 'package:flutter/material.dart';

import '../app_state.dart';
import '../finance_rates.dart';
import '../models.dart';
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

String _pct(double v) {
  final s = v.toStringAsFixed(4).replaceFirst(RegExp(r'\.?0+$'), '');
  return '$s%';
}

// ---------------------------------------------------------------------
// النسب والضرائب (الإصدار 3.0.0، الترحيل 47)
// ---------------------------------------------------------------------

class AccountsRatesPage extends StatelessWidget {
  const AccountsRatesPage({super.key});

  Future<void> _edit(BuildContext context, AppState app, String code) async {
    final cur = app.ratesOf(code).firstOrNull;
    final ok = await showPmForm(
      context,
      title: 'إصدار جديد من «${financeRateNames[code]}»',
      note: 'التغيير يُضيف إصداراً جديداً بتاريخ سريانه ويغلق السابق، ولا يُعدَّل الإصدار القديم. '
          'لا تُطبَّق النسبة إلا على نطاقها المحدد وبأساس احتسابها، ولا تُطبَّق على كل العقود تلقائياً.',
      sections: [
        PmSection('الإصدار', [
          const PmField('percent', 'النسبة (%)', PmKind.decimal, required: true),
          PmField('basis', 'أساس الاحتساب', PmKind.select, required: true, options: [
            for (final e in financeBasisNames.entries)
              if (e.key != 'none') (e.key, e.value),
          ]),
          PmField('scope', 'نطاق التطبيق', PmKind.select, required: true, options: [
            for (final e in financeScopeNames.entries) (e.key, e.value),
          ]),
          const PmField('from', 'تاريخ السريان', PmKind.date, required: true),
          const PmField('active', 'مفعّلة', PmKind.toggle),
          const PmField('reason', 'سبب التغيير', PmKind.multiline, required: true, max: 300, full: true),
        ]),
      ],
      values: {
        'percent': cur?.percent,
        'basis': cur?.basis ?? 'extract_gross',
        'scope': cur?.scope ?? 'contracts',
        'from': DateTime.now(),
        'active': cur?.active ?? true,
        'reason': '',
      },
      onSave: (d) => app.saveFinanceRate(
        code: code,
        percent: (d['percent'] as num).toDouble(),
        basis: '${d['basis']}',
        scope: '${d['scope']}',
        from: DateTime.parse('${d['from']}'),
        reason: '${d['reason']}'.trim(),
        active: d['active'] == true,
      ),
    );
    if (ok && context.mounted) showToast(context, 'أُضيف إصدار جديد');
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final sem = Sem.of(context);
    return PageBody(
      onRefresh: app.loadAll,
      children: [
        const PageHeader(
          title: 'النسب والضرائب',
          subtitle: 'ضريبة الدخل والتأمينات والقاعدة الإضافية بتواريخ سريانها وأساس احتسابها ونطاقها، وسجل كل تغيير.',
          icon: Icons.percent_rounded,
        ),
        for (final code in financeRateCodes) ...[
          _card(context, app, sem, code),
          const SizedBox(height: 12),
        ],
      ],
    );
  }

  Widget _card(BuildContext context, AppState app, Sem sem, String code) {
    final all = app.ratesOf(code);
    final cur = app.currentRate(code);
    final head = all.firstOrNull;
    return SectionCard(
      title: financeRateNames[code] ?? code,
      icon: Icons.percent_rounded,
      subtitle: cur == null
          ? 'لا نسبة سارية اليوم (معطّلة أو خارج تاريخ السريان)'
          : '${_pct(cur.percent)} على ${financeBasisNames[cur.basis] ?? cur.basis} · ${financeScopeNames[cur.scope] ?? cur.scope}',
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        ToneBadge(cur == null ? 'غير سارية' : 'سارية', color: cur == null ? sem.muted : sem.ok),
        if (app.canEditFinance) ...[
          const SizedBox(width: 8),
          FilledButton.icon(onPressed: () => _edit(context, app, code), icon: const Icon(Icons.add_rounded), label: const Text('إصدار جديد')),
        ],
      ]),
      child: all.isEmpty
          ? const Text('لا إصدارات')
          : Column(children: [
              for (final r in all)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(r.active ? Icons.check_circle_outline_rounded : Icons.pause_circle_outline_rounded,
                      color: r == head && r.active ? sem.ok : sem.muted),
                  title: Text('${_pct(r.percent)} — ${financeBasisNames[r.basis] ?? r.basis} — ${financeScopeNames[r.scope] ?? r.scope}'
                      '${r.active ? '' : ' (معطّلة)'}'),
                  subtitle: Text('من ${fmtDate(r.from)}${r.to == null ? ' وما بعده' : ' إلى ${fmtDate(r.to)}'}'
                      '${r.reason.isEmpty ? '' : ' · ${r.reason}'}'),
                ),
            ]),
    );
  }
}

// ---------------------------------------------------------------------
// دليل الخصومات
// ---------------------------------------------------------------------

class AccountsDeductionsPage extends StatelessWidget {
  const AccountsDeductionsPage({super.key});

  Future<void> _edit(BuildContext context, AppState app, {FinanceDeduction? d}) async {
    final ok = await showPmForm(
      context,
      title: d == null ? 'خصم جديد' : 'تعديل الخصم',
      note: 'الدليل تعريف الخصومات فقط؛ تُطبَّق على المرتبات والمستخلصات في المراحل اللاحقة. خصم النسبة يحتاج أساساً يُحسب عليه.',
      sections: [
        PmSection('الخصم', [
          const PmField('name', 'اسم الخصم', PmKind.text, required: true, max: 80, full: true),
          const PmField('kind', 'النوع', PmKind.select, required: true, options: [('percent', 'نسبة'), ('fixed', 'مبلغ ثابت')]),
          const PmField('value', 'القيمة (نسبة % أو مبلغ)', PmKind.decimal, required: true),
          PmField('basis', 'الأساس', PmKind.select, required: true, options: [
            for (final e in financeBasisNames.entries) (e.key, e.value),
          ]),
          PmField('applies', 'المجال', PmKind.select, required: true, options: [
            for (final e in financeAppliesNames.entries) (e.key, e.value),
          ]),
          const PmField('active', 'مفعّل', PmKind.toggle),
          const PmField('note', 'ملاحظة', PmKind.multiline, max: 300, full: true),
        ]),
      ],
      values: d == null
          ? {'kind': 'fixed', 'basis': 'none', 'applies': 'payroll', 'active': true}
          : {'name': d.name, 'kind': d.kind, 'value': d.value, 'basis': d.basis, 'applies': d.appliesTo, 'active': d.active, 'note': d.note},
      onSave: (v) => app.saveFinanceDeduction(
        id: d?.id,
        name: '${v['name']}',
        kind: '${v['kind']}',
        value: (v['value'] as num).toDouble(),
        basis: '${v['basis']}',
        appliesTo: '${v['applies']}',
        active: v['active'] == true,
        note: '${v['note'] ?? ''}',
      ),
    );
    if (ok && context.mounted) showToast(context, d == null ? 'أُضيف الخصم' : 'حُفظ الخصم');
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final sem = Sem.of(context);
    final list = app.financeDeductions;
    return PageBody(
      onRefresh: app.loadAll,
      children: [
        PageHeader(
          title: 'الخصومات',
          subtitle: 'دليل الخصومات: اسمها ونوعها وقيمتها وأساس احتسابها والمجال الذي تُطبَّق عليه.',
          icon: Icons.remove_circle_outline_rounded,
          actions: [
            if (app.canEditFinance)
              FilledButton.icon(onPressed: () => _edit(context, app), icon: const Icon(Icons.add_rounded), label: const Text('خصم')),
          ],
        ),
        if (list.isEmpty)
          EmptyState(
            title: 'لا خصومات معرّفة',
            message: app.canEditFinance ? 'أضف خصماً ليظهر في الدليل.' : 'يعرّف المدير أو من مُنح صلاحية التحرير الخصومات.',
            icon: Icons.remove_circle_outline_rounded,
          )
        else
          for (final d in list)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: SectionCard(
                title: d.name,
                icon: Icons.remove_circle_outline_rounded,
                subtitle: '${d.isPercent ? _pct(d.value) : fmtMoney(d.value)}'
                    '${d.isPercent ? ' من ${financeBasisNames[d.basis] ?? d.basis}' : ''} · ${financeAppliesNames[d.appliesTo] ?? d.appliesTo}',
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  ToneBadge(d.active ? 'مفعّل' : 'موقوف', color: d.active ? sem.ok : sem.muted),
                  if (app.canEditFinance) ...[
                    IconButton(tooltip: 'تعديل', onPressed: () => _edit(context, app, d: d), icon: const Icon(Icons.edit_outlined)),
                    IconButton(
                      tooltip: 'حذف',
                      icon: const Icon(Icons.delete_outline_rounded),
                      onPressed: () async {
                        final ok = await confirmDialog(context,
                            title: 'حذف الخصم', message: 'يُحذف «${d.name}» من الدليل.', confirmLabel: 'حذف', danger: true);
                        if (ok && context.mounted) await _run(context, () => app.deleteFinanceDeduction(d.id), 'حُذف الخصم');
                      },
                    ),
                  ],
                ]),
                child: d.note.isEmpty ? const SizedBox.shrink() : Text(d.note),
              ),
            ),
      ],
    );
  }
}

// ---------------------------------------------------------------------
// الصلاحيات المالية (المدير وحده)
// ---------------------------------------------------------------------

class AccountsPermsPage extends StatelessWidget {
  const AccountsPermsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final people = app.people.values.where((p) => p.active && p.role != AppRole.director).toList()
      ..sort((a, b) => a.displayName.compareTo(b.displayName));
    return PageBody(
      onRefresh: app.loadAll,
      children: [
        const PageHeader(
          title: 'الصلاحيات المالية',
          subtitle: 'المدير يملك كل الصلاحيات، وموظفو مكتبه يطّلعون. هنا تمنح أي مستخدم اطّلاعاً أو تحريراً أو اعتماداً مالياً فوق دوره.',
          icon: Icons.admin_panel_settings_outlined,
        ),
        for (final p in people)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: SectionCard(
              title: p.displayName,
              icon: Icons.person_outline_rounded,
              subtitle: p.role.label,
              child: Wrap(spacing: 8, runSpacing: 4, children: [
                for (final e in financePermNames.entries)
                  FilterChip(
                    label: Text(e.value),
                    selected: app.financeGrants.any((g) => g.userId == p.id && g.perm == e.key),
                    onSelected: app.canGrantFinance
                        ? (on) => _run(context, () => app.setFinancePerm(p.id, e.key, on), on ? 'مُنحت الصلاحية' : 'سُحبت الصلاحية')
                        : null,
                  ),
              ]),
            ),
          ),
      ],
    );
  }
}
