import 'package:flutter/material.dart';

import '../app_state.dart';
import '../budget.dart';
import '../models.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';
import 'pm_common.dart';

/// ميزانية المكتب والالتزامات (الإصدار 2.0.0، الترحيل 46): بنود سنوية بمخصصاتها،
/// والتزامات تُسجَّل عليها، ورصيد كل بند ونسبة استنفاده.
class BudgetView extends StatefulWidget {
  const BudgetView({super.key});

  @override
  State<BudgetView> createState() => _BudgetViewState();
}

class _BudgetViewState extends State<BudgetView> {
  int? _year;
  final Set<String> _open = {};

  Future<void> _editLine(AppState app, {BudgetLine? line}) async {
    final ok = await showPmForm(
      context,
      title: line == null ? 'بند ميزانية جديد' : 'تعديل البند',
      note: 'البند مخصص مالي لسنة معينة تحت باب (مثل: رواتب، صيانة، معدات). لا يُخفَّض المخصص إلى أقل من الملتزم به.',
      sections: [
        PmSection('البند', [
          const PmField('year', 'السنة المالية', PmKind.integer, required: true),
          const PmField('category', 'الباب', PmKind.text, required: true, max: 60),
          const PmField('name', 'اسم البند', PmKind.text, required: true, max: 120, full: true),
          const PmField('allocated', 'المخصص', PmKind.decimal, required: true),
          const PmField('note', 'ملاحظة', PmKind.multiline, max: 300, full: true),
        ]),
      ],
      values: line == null
          ? {'year': _year ?? DateTime.now().year}
          : {'year': line.year, 'category': line.category, 'name': line.name, 'allocated': line.allocated, 'note': line.note},
      onSave: (d) => app.saveBudgetLine(
        id: line?.id,
        year: (d['year'] as num).toInt(),
        category: '${d['category']}',
        name: '${d['name']}',
        allocated: (d['allocated'] as num).toDouble(),
        note: '${d['note'] ?? ''}',
      ),
    );
    if (ok && mounted) showToast(context, line == null ? 'أُضيف البند' : 'حُفظ البند');
  }

  Future<void> _editCommit(AppState app, BudgetLine line, {BudgetCommitment? c}) async {
    final ok = await showPmForm(
      context,
      title: c == null ? 'التزام جديد على «${line.name}»' : 'تعديل الالتزام',
      note: 'الالتزام مبلغ حُجز من البند لجهة أو غرض. لا يتجاوز مجموع الالتزامات النشطة مخصص البند، والمدفوع لا يتجاوز مبلغ الالتزام.',
      sections: [
        PmSection('الالتزام', [
          const PmField('description', 'الوصف', PmKind.text, required: true, max: 200, full: true),
          const PmField('amount', 'المبلغ الملتزم به', PmKind.decimal, required: true),
          const PmField('paid', 'المدفوع منه', PmKind.decimal),
          const PmField('date', 'تاريخ الالتزام', PmKind.date, required: true),
          PmField('project_id', 'المشروع (اختياري)', PmKind.select, options: [
            ('', 'بلا مشروع'),
            for (final p in app.projects) (p.id, app.pm.track(p.id)?.displayName ?? p.name),
          ]),
          const PmField('note', 'ملاحظة', PmKind.multiline, max: 300, full: true),
        ]),
      ],
      values: c == null
          ? {'date': DateTime.now().toIso8601String().substring(0, 10), 'paid': 0, 'project_id': ''}
          : {
              'description': c.description,
              'amount': c.amount,
              'paid': c.paid,
              'date': c.date.toIso8601String().substring(0, 10),
              'project_id': c.projectId ?? '',
              'note': c.note,
            },
      onSave: (d) => app.saveBudgetCommitment(
        id: c?.id,
        lineId: line.id,
        projectId: '${d['project_id'] ?? ''}'.isEmpty ? null : '${d['project_id']}',
        description: '${d['description']}',
        amount: (d['amount'] as num).toDouble(),
        paid: ((d['paid'] ?? 0) as num).toDouble(),
        date: DateTime.parse('${d['date']}'),
        note: '${d['note'] ?? ''}',
      ),
    );
    if (ok && mounted) showToast(context, c == null ? 'سُجّل الالتزام' : 'حُفظ الالتزام');
  }

  Future<void> _run(Future<void> Function() f, String done) async {
    try {
      await f();
      if (mounted) showToast(context, done);
    } catch (e) {
      if (mounted) showToast(context, friendlyError(e), error: true);
    }
  }

  Color _tone(Sem sem, BudgetStatus s) => s.exhausted ? sem.danger : (s.warn ? sem.wip : sem.ok);

  String _pct(BudgetStatus s) => s.usage == null ? '—' : '${(s.usage! * 100).toStringAsFixed(1)}%';

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final sem = Sem.of(context);
    final years = app.budgetYears;
    final now = DateTime.now().year;
    final year = _year ?? (years.contains(now) ? now : (years.isNotEmpty ? years.first : now));
    final lines = app.budgetLines.where((l) => l.year == year).toList();
    final total = budgetTotal(lines, app.budgetCommitments);

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SectionCard(
        title: 'ميزانية المكتب والالتزامات',
        icon: Icons.account_balance_outlined,
        subtitle: 'المخصص لكل بند، وما التُزم به منه، وما دُفع، وما بقي. الالتزامات المفرَج عنها لا تُحسب.',
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          SizedBox(
            width: 120,
            child: SelectField(
              label: 'السنة',
              value: '$year',
              items: [for (final y in {...years, year}.toList()..sort((a, b) => b.compareTo(a))) ('$y', '$y')],
              onChanged: (v) => setState(() => _year = int.tryParse(v)),
            ),
          ),
          if (app.canDefineBudget) ...[
            const SizedBox(width: 8),
            FilledButton.icon(onPressed: () => _editLine(app), icon: const Icon(Icons.add_rounded), label: const Text('بند')),
          ],
        ]),
        child: Wrap(spacing: 10, runSpacing: 10, children: [
          SizedBox(width: 180, child: KpiTile(label: 'المخصص', value: fmtMoney(total.allocated))),
          SizedBox(width: 180, child: KpiTile(label: 'الملتزم به', value: fmtMoney(total.committed), sub: 'الاستنفاد ${_pct(total)}', color: _tone(sem, total))),
          SizedBox(width: 180, child: KpiTile(label: 'المدفوع', value: fmtMoney(total.paid), sub: 'الباقي دفعه ${fmtMoney(total.unpaid)}')),
          SizedBox(width: 180, child: KpiTile(label: 'المتبقي للالتزام', value: fmtMoney(total.remaining), color: total.remaining < 0 ? sem.danger : null)),
        ]),
      ),
      const SizedBox(height: 12),
      if (lines.isEmpty)
        EmptyState(
          title: 'لا بنود لسنة $year',
          message: app.canDefineBudget ? 'أضف بنداً ليبدأ تسجيل الالتزامات عليه.' : 'يعرّف المدير بنود الميزانية.',
          icon: Icons.account_balance_outlined,
        )
      else
        for (final l in lines) _lineCard(app, sem, l),
    ]);
  }

  Widget _lineCard(AppState app, Sem sem, BudgetLine l) {
    final s = budgetStatusOf(l, app.budgetCommitments);
    final cs = app.budgetCommitments.where((c) => c.lineId == l.id).toList()..sort((a, b) => b.date.compareTo(a.date));
    final open = _open.contains(l.id);
    final tone = _tone(sem, s);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: SectionCard(
        title: l.name,
        icon: Icons.folder_open_rounded,
        subtitle: '${l.category} · المخصص ${fmtMoney(l.allocated)}',
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          ToneBadge(s.exhausted ? 'مستنفد' : (s.warn ? 'قارب النفاد' : 'ضمن الميزانية'), color: tone),
          IconButton(
            tooltip: open ? 'إخفاء الالتزامات' : 'عرض الالتزامات (${cs.length})',
            onPressed: () => setState(() => open ? _open.remove(l.id) : _open.add(l.id)),
            icon: Icon(open ? Icons.expand_less_rounded : Icons.expand_more_rounded),
          ),
        ]),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: s.usage == null ? 0 : s.usage!.clamp(0.0, 1.0),
              minHeight: 10,
              color: tone,
              backgroundColor: sem.surface2,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'ملتزم ${fmtMoney(s.committed)} (${_pct(s)}) · مدفوع ${fmtMoney(s.paid)} · متبقٍ ${fmtMoney(s.remaining)}',
            style: TextStyle(color: sem.muted, fontSize: 12.5),
          ),
          if (app.canDefineBudget || app.canCommitBudget)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Wrap(spacing: 8, runSpacing: 4, children: [
                if (app.canCommitBudget)
                  OutlinedButton.icon(onPressed: () => _editCommit(app, l), icon: const Icon(Icons.add_rounded, size: 18), label: const Text('التزام')),
                if (app.canDefineBudget)
                  OutlinedButton.icon(onPressed: () => _editLine(app, line: l), icon: const Icon(Icons.edit_outlined, size: 18), label: const Text('تعديل البند')),
                if (app.canDefineBudget && cs.isEmpty)
                  OutlinedButton.icon(
                    onPressed: () async {
                      final ok = await confirmDialog(context,
                          title: 'حذف البند', message: 'يُحذف «${l.name}» نهائياً. لا يُحذف بند عليه التزامات.', confirmLabel: 'حذف', danger: true);
                      if (ok) await _run(() => app.deleteBudgetLine(l.id), 'حُذف البند');
                    },
                    icon: const Icon(Icons.delete_outline_rounded, size: 18),
                    label: const Text('حذف'),
                  ),
              ]),
            ),
          if (open) ...[
            const Divider(height: 24),
            if (cs.isEmpty)
              Text('لا التزامات على هذا البند.', style: TextStyle(color: sem.muted))
            else
              for (final c in cs) _commitTile(app, sem, l, c),
          ],
        ]),
      ),
    );
  }

  Widget _commitTile(AppState app, Sem sem, BudgetLine l, BudgetCommitment c) {
    final proj = c.projectId == null ? null : app.pm.track(c.projectId!)?.displayName;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(c.description, style: TextStyle(fontSize: 13.5, decoration: c.isActive ? null : TextDecoration.lineThrough)),
      subtitle: Text(
        [
          '${c.date.year}/${c.date.month.toString().padLeft(2, '0')}/${c.date.day.toString().padLeft(2, '0')}',
          'المبلغ ${fmtMoney(c.amount)}',
          'المدفوع ${fmtMoney(c.paid)}',
          if (proj != null) proj,
          if (!c.isActive) 'مُفرَج عنه',
        ].join(' · '),
        style: TextStyle(color: sem.muted, fontSize: 12),
      ),
      trailing: !app.canCommitBudget
          ? null
          : PopupMenuButton<String>(
              onSelected: (v) async {
                switch (v) {
                  case 'edit':
                    await _editCommit(app, l, c: c);
                  case 'release':
                    await _run(() => app.setBudgetCommitmentStatus(c.id, 'released'), 'أُفرج عن الالتزام');
                  case 'activate':
                    await _run(() => app.setBudgetCommitmentStatus(c.id, 'active'), 'أُعيد تفعيل الالتزام');
                  case 'delete':
                    final ok = await confirmDialog(context,
                        title: 'حذف الالتزام', message: 'يُحذف الالتزام نهائياً ويُسجَّل الحذف في سجل التدقيق.', confirmLabel: 'حذف', danger: true);
                    if (ok) await _run(() => app.deleteBudgetCommitment(c.id), 'حُذف الالتزام');
                }
              },
              itemBuilder: (_) => [
                if (c.isActive) const PopupMenuItem(value: 'edit', child: Text('تعديل')),
                PopupMenuItem(value: c.isActive ? 'release' : 'activate', child: Text(c.isActive ? 'الإفراج عن الالتزام' : 'إعادة التفعيل')),
                if (app.canDefineBudget) const PopupMenuItem(value: 'delete', child: Text('حذف')),
              ],
            ),
    );
  }
}
