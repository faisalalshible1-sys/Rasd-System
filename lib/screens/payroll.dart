import 'package:flutter/material.dart';

import '../app_state.dart';
import '../finance_rates.dart';
import '../models.dart';
import '../payroll.dart';
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

Color _statusColor(Sem sem, String s) => switch (s) {
      'approved' => sem.wip,
      'locked' => sem.ok,
      _ => sem.muted,
    };

/// منتقي الشهر: أسهم للشهر السابق والتالي.
class _MonthBar extends StatelessWidget {
  const _MonthBar({required this.period, required this.onChanged});
  final DateTime period;
  final ValueChanged<DateTime> onChanged;

  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        IconButton(
          tooltip: 'الشهر التالي',
          onPressed: () => onChanged(DateTime(period.year, period.month + 1)),
          icon: const Icon(Icons.chevron_right_rounded),
        ),
        SizedBox(width: 90, child: Center(child: Text(periodLabel(period), style: const TextStyle(fontWeight: FontWeight.w700)))),
        IconButton(
          tooltip: 'الشهر السابق',
          onPressed: () => onChanged(DateTime(period.year, period.month - 1)),
          icon: const Icon(Icons.chevron_left_rounded),
        ),
      ]);
}

// ---------------------------------------------------------------------
// الموظفون: السجل المالي والبدلات والخصومات المسندة والسلف
// ---------------------------------------------------------------------

class PayrollEmployeesPage extends StatefulWidget {
  const PayrollEmployeesPage({super.key});

  @override
  State<PayrollEmployeesPage> createState() => _PayrollEmployeesPageState();
}

class _PayrollEmployeesPageState extends State<PayrollEmployeesPage> {
  final Set<String> _open = {};

  Future<void> _editEmployee(AppState app, {FinEmployee? e}) async {
    final profiles = app.people.values.where((p) => p.active).toList()..sort((a, b) => a.displayName.compareTo(b.displayName));
    final ok = await showPmForm(
      context,
      title: e == null ? 'موظف جديد' : 'تعديل الموظف',
      note: 'السجل المالي مستقل. «مؤمَّن عليه» و«خاضع للضريبة» و«القاعدة الإضافية» تُطبَّق نسبها على الموسوم فقط إذا كان نطاق النسبة «محدد بالاختيار».',
      sections: [
        PmSection('البيانات', [
          const PmField('name', 'الاسم', PmKind.text, required: true, max: 120, full: true),
          const PmField('title', 'الوظيفة', PmKind.text, max: 80),
          const PmField('basic', 'الراتب الأساسي', PmKind.decimal, required: true),
          const PmField('hire', 'تاريخ التعيين', PmKind.date, required: true),
          PmField('profile', 'حساب المستخدم (اختياري)', PmKind.select, options: [
            ('', 'بلا ربط'),
            for (final p in profiles) (p.id, p.displayName),
          ]),
          const PmField('active', 'على رأس العمل', PmKind.toggle),
          const PmField('insured', 'مؤمَّن عليه', PmKind.toggle),
          const PmField('taxable', 'خاضع لضريبة الدخل', PmKind.toggle),
          const PmField('extra', 'تسري عليه القاعدة الإضافية', PmKind.toggle),
          const PmField('note', 'ملاحظة', PmKind.multiline, max: 300, full: true),
        ]),
      ],
      values: e == null
          ? {'active': true, 'insured': true, 'hire': DateTime.now(), 'profile': ''}
          : {
              'name': e.name,
              'title': e.title,
              'basic': e.basic,
              'hire': e.hireDate,
              'profile': e.profileId ?? '',
              'active': e.active,
              'insured': e.insured,
              'taxable': e.taxable,
              'extra': e.extra,
              'note': e.note,
            },
      onSave: (d) => app.saveFinEmployee(
        id: e?.id,
        name: '${d['name']}',
        title: '${d['title'] ?? ''}',
        basic: (d['basic'] as num).toDouble(),
        hire: DateTime.parse('${d['hire']}'),
        active: d['active'] == true,
        profileId: '${d['profile'] ?? ''}'.isEmpty ? null : '${d['profile']}',
        insured: d['insured'] == true,
        taxable: d['taxable'] == true,
        extra: d['extra'] == true,
        note: '${d['note'] ?? ''}',
      ),
    );
    if (ok && mounted) showToast(context, e == null ? 'أُضيف الموظف' : 'حُفظ الموظف');
  }

  Future<void> _editAllowance(AppState app, FinEmployee e, {FinAllowance? a}) async {
    final ok = await showPmForm(
      context,
      title: a == null ? 'بدل ثابت لـ «${e.name}»' : 'تعديل البدل',
      sections: [
        PmSection('البدل', [
          const PmField('name', 'اسم البدل', PmKind.text, required: true, max: 60),
          const PmField('amount', 'المبلغ الشهري', PmKind.decimal, required: true),
          const PmField('active', 'مفعّل', PmKind.toggle),
        ]),
      ],
      values: a == null ? {'active': true} : {'name': a.name, 'amount': a.amount, 'active': a.active},
      onSave: (d) => app.saveFinAllowance(
        id: a?.id,
        employeeId: e.id,
        name: '${d['name']}',
        amount: (d['amount'] as num).toDouble(),
        active: d['active'] == true,
      ),
    );
    if (ok && mounted) showToast(context, 'حُفظ البدل');
  }

  Future<void> _editLoan(AppState app, FinEmployee e, {FinLoan? l}) async {
    final ok = await showPmForm(
      context,
      title: l == null ? 'سلفة لـ «${e.name}»' : 'تعديل السلفة',
      note: 'تُقسَّط على أشهر متتالية بقسط ثابت (الإجمالي ÷ العدد) وآخر قسط يأخذ الباقي، بلا نسبة ثابتة، وتُخصم تلقائياً من الكشوف.',
      sections: [
        PmSection('السلفة', [
          const PmField('total', 'المبلغ', PmKind.decimal, required: true),
          const PmField('count', 'عدد الأقساط', PmKind.integer, required: true),
          const PmField('start', 'شهر بدء الخصم', PmKind.date, required: true),
          const PmField('active', 'جارية', PmKind.toggle),
          const PmField('note', 'ملاحظة', PmKind.multiline, max: 300, full: true),
        ]),
      ],
      values: l == null
          ? {'count': 1, 'start': DateTime.now(), 'active': true}
          : {'total': l.total, 'count': l.installments, 'start': l.start, 'active': l.active, 'note': l.note},
      onSave: (d) => app.saveFinLoan(
        id: l?.id,
        employeeId: e.id,
        total: (d['total'] as num).toDouble(),
        count: (d['count'] as num).toInt(),
        start: DateTime.parse('${d['start']}'),
        active: d['active'] == true,
        note: '${d['note'] ?? ''}',
      ),
    );
    if (ok && mounted) showToast(context, 'حُفظت السلفة');
  }

  Future<void> _config(AppState app) async {
    final c = app.payrollConfig;
    final ok = await showPmForm(
      context,
      title: 'إعدادات احتساب المرتبات',
      note: 'الأجر اليومي = الأساسي ÷ أيام الشهر، وأجر الساعة = اليومي ÷ (ساعات الأسبوع ÷ 6)، والإضافي = الساعات × أجر الساعة × المعامل. تسري على الكشوف التي تُولَّد بعد الحفظ.',
      sections: [
        const PmSection('الاحتساب', [
          PmField('days', 'أيام الشهر', PmKind.decimal, required: true),
          PmField('hours', 'ساعات العمل الأسبوعية', PmKind.decimal, required: true),
          PmField('factor', 'معامل الساعة الإضافية', PmKind.decimal, required: true),
        ]),
      ],
      values: {'days': c.daysInMonth, 'hours': c.weeklyHours, 'factor': c.overtimeFactor},
      onSave: (d) async {
        await app.setPayrollConfig('days_in_month', (d['days'] as num).toDouble());
        await app.setPayrollConfig('weekly_hours', (d['hours'] as num).toDouble());
        await app.setPayrollConfig('overtime_factor', (d['factor'] as num).toDouble());
      },
    );
    if (ok && mounted) showToast(context, 'حُفظت الإعدادات');
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final sem = Sem.of(context);
    final canEdit = app.canEditFinSettings;
    if (!app.v32Ready) {
      return PageBody(children: const [
        PageHeader(title: 'الموظفون', icon: Icons.badge_outlined),
        InfoBanner(text: 'المرتبات تعمل بعد تطبيق الترحيل 48 على قاعدة البيانات.', level: 'warning'),
      ]);
    }
    final deds = app.financeDeductions.where((d) => d.active && d.appliesTo != 'contracts').toList();
    return PageBody(
      onRefresh: app.loadAll,
      children: [
        PageHeader(
          title: 'الموظفون',
          subtitle: 'السجل المالي: الراتب الأساسي والبدلات الثابتة والخصومات المسندة والسلف.',
          icon: Icons.badge_outlined,
          actions: [
            OutlinedButton.icon(onPressed: () => _config(app), icon: const Icon(Icons.tune_rounded), label: const Text('الاحتساب')),
            if (canEdit) FilledButton.icon(onPressed: () => _editEmployee(app), icon: const Icon(Icons.add_rounded), label: const Text('موظف')),
          ],
        ),
        if (app.finEmployees.isEmpty)
          EmptyState(
            title: 'لا موظفين في السجل المالي',
            message: canEdit ? 'أضف موظفاً ليدخل في كشف المرتبات.' : 'يضيف المدير أو من مُنح صلاحية التحرير الموظفين.',
            icon: Icons.badge_outlined,
          )
        else
          for (final e in app.finEmployees) _card(app, sem, e, deds, canEdit),
      ],
    );
  }

  Widget _card(AppState app, Sem sem, FinEmployee e, List<FinanceDeduction> deds, bool canEdit) {
    final open = _open.contains(e.id);
    final als = app.finAllowances.where((a) => a.employeeId == e.id).toList();
    final loans = app.finLoans.where((l) => l.employeeId == e.id).toList();
    final assigned = {for (final x in app.finEmpDeductions.where((x) => x.employeeId == e.id)) x.deductionId: x};
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: SectionCard(
        title: e.name,
        icon: Icons.person_outline_rounded,
        subtitle: '${e.title.isEmpty ? 'بلا مسمى' : e.title} · الأساسي ${fmtMoney(e.basic)} · منذ ${fmtDate(e.hireDate)}',
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          ToneBadge(e.active ? 'على رأس العمل' : 'موقوف', color: e.active ? sem.ok : sem.muted),
          if (canEdit) IconButton(tooltip: 'تعديل', onPressed: () => _editEmployee(app, e: e), icon: const Icon(Icons.edit_outlined)),
          IconButton(
            tooltip: open ? 'طيّ' : 'التفاصيل',
            onPressed: () => setState(() => open ? _open.remove(e.id) : _open.add(e.id)),
            icon: Icon(open ? Icons.expand_less_rounded : Icons.expand_more_rounded),
          ),
        ]),
        child: !open
            ? Text('${als.where((a) => a.active).length} بدل · ${assigned.length} خصم مسند · ${loans.where((l) => l.active).length} سلفة جارية')
            : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  const Text('البدلات الثابتة', style: TextStyle(fontWeight: FontWeight.w700)),
                  const Spacer(),
                  if (canEdit) TextButton.icon(onPressed: () => _editAllowance(app, e), icon: const Icon(Icons.add_rounded), label: const Text('بدل')),
                ]),
                if (als.isEmpty) const Text('لا بدلات'),
                for (final a in als)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text('${a.name} — ${fmtMoney(a.amount)}${a.active ? '' : ' (موقوف)'}'),
                    trailing: canEdit
                        ? Row(mainAxisSize: MainAxisSize.min, children: [
                            IconButton(onPressed: () => _editAllowance(app, e, a: a), icon: const Icon(Icons.edit_outlined)),
                            IconButton(
                              onPressed: () => _run(context, () => app.deleteFinAllowance(a.id), 'حُذف البدل'),
                              icon: const Icon(Icons.delete_outline_rounded),
                            ),
                          ])
                        : null,
                  ),
                const Divider(),
                const Text('الخصومات المسندة (من دليل الخصومات)', style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                if (deds.isEmpty)
                  const Text('لا خصومات مفعّلة للمرتبات في الدليل')
                else
                  Wrap(spacing: 8, runSpacing: 4, children: [
                    for (final d in deds)
                      FilterChip(
                        label: Text('${d.name} (${d.isPercent ? '${d.value}%' : fmtMoney(d.value)})'),
                        selected: assigned.containsKey(d.id),
                        onSelected: canEdit
                            ? (on) => _run(context, () => app.setFinEmpDeduction(e.id, d.id, on), on ? 'أُسند الخصم' : 'سُحب الخصم')
                            : null,
                      ),
                  ]),
                const Divider(),
                Row(children: [
                  const Text('السلف', style: TextStyle(fontWeight: FontWeight.w700)),
                  const Spacer(),
                  if (canEdit) TextButton.icon(onPressed: () => _editLoan(app, e), icon: const Icon(Icons.add_rounded), label: const Text('سلفة')),
                ]),
                if (loans.isEmpty) const Text('لا سلف'),
                for (final l in loans)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text('${fmtMoney(l.total)} على ${l.installments} قسطاً من ${periodLabel(l.start)}${l.active ? '' : ' (مغلقة)'}'),
                    subtitle: Text('القسط ${fmtMoney(loanInstallment(l.total, l.installments, 0))}'),
                    trailing: canEdit
                        ? Row(mainAxisSize: MainAxisSize.min, children: [
                            IconButton(onPressed: () => _editLoan(app, e, l: l), icon: const Icon(Icons.edit_outlined)),
                            IconButton(
                              onPressed: () => _run(context, () => app.deleteFinLoan(l.id), 'حُذفت السلفة'),
                              icon: const Icon(Icons.delete_outline_rounded),
                            ),
                          ])
                        : null,
                  ),
                if (canEdit) ...[
                  const Divider(),
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: TextButton.icon(
                      onPressed: () async {
                        final ok = await confirmDialog(context,
                            title: 'حذف الموظف', message: 'يُحذف «${e.name}» من السجل. من له كشوف يُوقَف ولا يُحذف.', confirmLabel: 'حذف', danger: true);
                        if (ok && mounted) await _run(context, () => app.deleteFinEmployee(e.id), 'حُذف الموظف');
                      },
                      icon: const Icon(Icons.delete_outline_rounded),
                      label: const Text('حذف الموظف'),
                    ),
                  ),
                ],
              ]),
      ),
    );
  }
}

// ---------------------------------------------------------------------
// الحضور والمكافآت لشهر
// ---------------------------------------------------------------------

class PayrollAttendancePage extends StatefulWidget {
  const PayrollAttendancePage({super.key});

  @override
  State<PayrollAttendancePage> createState() => _PayrollAttendancePageState();
}

class _PayrollAttendancePageState extends State<PayrollAttendancePage> {
  DateTime _period = periodOf(DateTime.now());

  Future<void> _month(AppState app, FinEmployee e, FinAttendanceMonth? m) async {
    final ok = await showPmForm(
      context,
      title: 'ملخص ${periodLabel(_period)} لـ «${e.name}»',
      note: 'الملخص الشهري يغلب الحضور اليومي لهذا الشهر؛ احذفه ليُحتسب من السجل اليومي.',
      sections: [
        const PmSection('الملخص', [
          PmField('absent', 'أيام الغياب', PmKind.decimal, required: true),
          PmField('leave', 'أيام الإجازة', PmKind.decimal, required: true),
          PmField('ot', 'الساعات الإضافية', PmKind.decimal, required: true),
          PmField('note', 'ملاحظة', PmKind.multiline, max: 300, full: true),
        ]),
      ],
      values: {'absent': m?.absent ?? 0, 'leave': m?.leave ?? 0, 'ot': m?.overtime ?? 0, 'note': m?.note ?? ''},
      onSave: (d) => app.setFinAttendanceMonth(e.id, _period, (d['absent'] as num).toDouble(), (d['leave'] as num).toDouble(),
          (d['ot'] as num).toDouble(),
          note: '${d['note'] ?? ''}'),
    );
    if (ok && mounted) showToast(context, 'حُفظ الملخص');
  }

  Future<void> _day(AppState app, FinEmployee e) async {
    final first = _period;
    final ok = await showPmForm(
      context,
      title: 'حضور يوم لـ «${e.name}»',
      sections: [
        PmSection('اليوم', [
          const PmField('day', 'اليوم', PmKind.date, required: true),
          PmField('status', 'الحالة', PmKind.select, required: true, options: [
            for (final s in attendanceStatusNames.entries) (s.key, s.value),
          ]),
          const PmField('ot', 'ساعات إضافية', PmKind.decimal),
        ]),
      ],
      values: {'day': first, 'status': 'present', 'ot': 0},
      onSave: (d) => app.setFinAttendance(e.id, DateTime.parse('${d['day']}'), '${d['status']}', ((d['ot'] ?? 0) as num).toDouble()),
    );
    if (ok && mounted) showToast(context, 'سُجّل اليوم');
  }

  Future<void> _bonus(AppState app, FinEmployee e, {FinBonus? b}) async {
    final ok = await showPmForm(
      context,
      title: b == null ? 'مكافأة لـ «${e.name}» (${periodLabel(_period)})' : 'تعديل المكافأة',
      sections: [
        PmSection('المكافأة', [
          const PmField('name', 'الوصف', PmKind.text, required: true, max: 80, full: true),
          const PmField('amount', 'المبلغ', PmKind.decimal, required: true),
          const PmField('note', 'ملاحظة', PmKind.multiline, max: 300, full: true),
        ]),
      ],
      values: b == null ? {} : {'name': b.name, 'amount': b.amount, 'note': b.note},
      onSave: (d) => app.saveFinBonus(id: b?.id, employeeId: e.id, period: _period, name: '${d['name']}', amount: (d['amount'] as num).toDouble(), note: '${d['note'] ?? ''}'),
    );
    if (ok && mounted) showToast(context, 'حُفظت المكافأة');
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final sem = Sem.of(context);
    if (!app.v32Ready) {
      return PageBody(children: const [
        PageHeader(title: 'الحضور والمكافآت', icon: Icons.event_available_outlined),
        InfoBanner(text: 'المرتبات تعمل بعد تطبيق الترحيل 48 على قاعدة البيانات.', level: 'warning'),
      ]);
    }
    final payroll = app.payrollOf(_period);
    final locked = payroll != null && !payroll.isDraft;
    final canEdit = app.canEditFinSettings && !locked;
    final emps = app.finEmployees.where((e) => e.active).toList();
    final end = DateTime(_period.year, _period.month + 1, 0);
    return PageBody(
      onRefresh: app.loadAll,
      children: [
        PageHeader(
          title: 'الحضور والمكافآت',
          subtitle: 'الغياب والإجازة والساعات الإضافية (ملخصاً شهرياً أو يومياً) والمكافآت لكل موظف في الشهر.',
          icon: Icons.event_available_outlined,
          actions: [_MonthBar(period: _period, onChanged: (p) => setState(() => _period = p))],
        ),
        if (locked)
          InfoBanner(
            text: 'كشف ${periodLabel(_period)} ${payrollStatusNames[payroll.status]}؛ لا يُعدَّل الحضور والمكافآت قبل إعادة فتحه بتراجع مسجَّل بسبب.',
            level: 'warning',
          ),
        if (emps.isEmpty)
          const EmptyState(title: 'لا موظفين', message: 'أضف الموظفين من صفحة «الموظفون».', icon: Icons.badge_outlined)
        else
          for (final e in emps)
            () {
              final m = app.finAttendanceMonths.where((x) => x.employeeId == e.id && x.period.year == _period.year && x.period.month == _period.month).firstOrNull;
              final days = app.finAttendance.where((x) => x.employeeId == e.id && !x.day.isBefore(_period) && !x.day.isAfter(end)).toList();
              final absent = m?.absent ?? days.where((x) => x.status == 'absent').length.toDouble();
              final ot = m?.overtime ?? days.fold<double>(0, (s, x) => s + x.overtime);
              final bonuses = app.finBonuses.where((b) => b.employeeId == e.id && b.period.year == _period.year && b.period.month == _period.month).toList();
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: SectionCard(
                  title: e.name,
                  icon: Icons.person_outline_rounded,
                  subtitle: 'غياب ${fmtNumber(absent)} يوماً · إضافي ${fmtNumber(ot)} ساعة · ${m != null ? 'من الملخص الشهري' : '${days.length} يوماً مسجَّلاً'}',
                  trailing: canEdit
                      ? Wrap(spacing: 4, children: [
                          TextButton(onPressed: () => _month(app, e, m), child: const Text('ملخص شهري')),
                          TextButton(onPressed: () => _day(app, e), child: const Text('يوم')),
                          TextButton(onPressed: () => _bonus(app, e), child: const Text('مكافأة')),
                        ])
                      : null,
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    if (m != null && canEdit)
                      TextButton.icon(
                        onPressed: () => _run(context, () => app.clearFinAttendanceMonth(e.id, _period), 'حُذف الملخص الشهري'),
                        icon: const Icon(Icons.delete_outline_rounded),
                        label: const Text('حذف الملخص الشهري'),
                      ),
                    if (days.isNotEmpty)
                      Wrap(spacing: 6, runSpacing: 4, children: [
                        for (final d in days)
                          InputChip(
                            label: Text('${d.day.day}: ${attendanceStatusNames[d.status] ?? d.status}${d.overtime > 0 ? ' +${fmtNumber(d.overtime)}س' : ''}'),
                            onDeleted: canEdit ? () => _run(context, () => app.clearFinAttendance(e.id, d.day), 'حُذف اليوم') : null,
                          ),
                      ]),
                    for (final b in bonuses)
                      ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(Icons.card_giftcard_rounded, color: sem.ok),
                        title: Text('${b.name} — ${fmtMoney(b.amount)}'),
                        trailing: canEdit
                            ? Row(mainAxisSize: MainAxisSize.min, children: [
                                IconButton(onPressed: () => _bonus(app, e, b: b), icon: const Icon(Icons.edit_outlined)),
                                IconButton(onPressed: () => _run(context, () => app.deleteFinBonus(b.id), 'حُذفت المكافأة'), icon: const Icon(Icons.delete_outline_rounded)),
                              ])
                            : null,
                      ),
                  ]),
                ),
              );
            }(),
      ],
    );
  }
}

// ---------------------------------------------------------------------
// كشف المرتبات الشهري
// ---------------------------------------------------------------------

class PayrollSheetPage extends StatefulWidget {
  const PayrollSheetPage({super.key});

  @override
  State<PayrollSheetPage> createState() => _PayrollSheetPageState();
}

class _PayrollSheetPageState extends State<PayrollSheetPage> {
  DateTime _period = periodOf(DateTime.now());

  Future<void> _reopen(AppState app) async {
    final ok = await showPmForm(
      context,
      title: 'التراجع عن كشف ${periodLabel(_period)}',
      note: 'يعود الكشف مسودة ويُسجَّل التراجع وسببه في سجل التدقيق.',
      sections: [
        const PmSection('التراجع', [PmField('reason', 'السبب', PmKind.multiline, required: true, max: 300, full: true)]),
      ],
      values: const {},
      onSave: (d) => app.reopenPayroll(_period, '${d['reason']}'.trim()),
    );
    if (ok && mounted) showToast(context, 'أُعيد الكشف مسودة');
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final sem = Sem.of(context);
    if (!app.v32Ready) {
      return PageBody(children: const [
        PageHeader(title: 'كشف المرتبات', icon: Icons.payments_outlined),
        InfoBanner(text: 'المرتبات تعمل بعد تطبيق الترحيل 48 على قاعدة البيانات.', level: 'warning'),
      ]);
    }
    final p = app.payrollOf(_period);
    final lines = p == null ? <FinPayrollLine>[] : app.payrollLinesOf(p);
    final t = payrollTotals(lines);
    final canEdit = app.canEditFinSettings;
    final canApprove = app.canApprovePayroll;
    return PageBody(
      onRefresh: app.loadAll,
      children: [
        PageHeader(
          title: 'كشف المرتبات',
          subtitle: 'كشف شهري بلقطة لكل موظف: مسودة ثم معتمد ثم مقفل. الاعتماد غير الصرف الفعلي.',
          icon: Icons.payments_outlined,
          actions: [
            _MonthBar(period: _period, onChanged: (x) => setState(() => _period = x)),
            if (lines.isNotEmpty) ExportButton(sourceId: 'finance:payroll', items: List<Object>.from(lines)),
          ],
        ),
        SectionCard(
          title: 'كشف ${periodLabel(_period)}',
          icon: Icons.payments_outlined,
          subtitle: p == null ? 'لم يُولَّد كشف لهذا الشهر' : 'الحالة: ${payrollStatusNames[p.status]}',
          trailing: Wrap(spacing: 6, children: [
            if (p != null) ToneBadge(payrollStatusNames[p.status] ?? p.status, color: _statusColor(sem, p.status)),
            if (canEdit && (p == null || p.isDraft))
              FilledButton.icon(
                onPressed: () => _run(context, () => app.generatePayroll(_period), p == null ? 'وُلّد الكشف' : 'أُعيد توليد الكشف'),
                icon: const Icon(Icons.calculate_outlined),
                label: Text(p == null ? 'توليد الكشف' : 'إعادة التوليد'),
              ),
            if (canApprove && p != null && p.isDraft && lines.isNotEmpty)
              FilledButton.tonalIcon(
                onPressed: () async {
                  final ok = await confirmDialog(context,
                      title: 'اعتماد الكشف', message: 'يُعتمد كشف ${periodLabel(_period)} بصافي ${fmtMoney(t.net)}، ولا يُعدَّل بعده إلا بتراجع مسجَّل.', confirmLabel: 'اعتماد');
                  if (ok && mounted) await _run(context, () => app.approvePayroll(_period), 'اعتُمد الكشف');
                },
                icon: const Icon(Icons.verified_outlined),
                label: const Text('اعتماد'),
              ),
            if (canApprove && p != null && p.isApproved)
              FilledButton.tonalIcon(
                onPressed: () => _run(context, () => app.lockPayroll(_period), 'قُفل الكشف'),
                icon: const Icon(Icons.lock_outline_rounded),
                label: const Text('قفل'),
              ),
            if (canApprove && p != null && !p.isDraft)
              OutlinedButton.icon(onPressed: () => _reopen(app), icon: const Icon(Icons.undo_rounded), label: const Text('تراجع')),
            if (canEdit && p != null && p.isDraft)
              IconButton(
                tooltip: 'حذف الكشف',
                onPressed: () async {
                  final ok = await confirmDialog(context, title: 'حذف الكشف', message: 'يُحذف مسودة كشف ${periodLabel(_period)}.', confirmLabel: 'حذف', danger: true);
                  if (ok && mounted) await _run(context, () => app.deletePayroll(_period), 'حُذف الكشف');
                },
                icon: const Icon(Icons.delete_outline_rounded),
              ),
          ]),
          child: lines.isEmpty
              ? const Text('يُولَّد الكشف من سجل الموظفين والحضور والمكافآت والسلف والنسب السارية آخر الشهر.')
              : Wrap(spacing: 10, runSpacing: 10, children: [
                  SizedBox(width: 170, child: KpiTile(label: 'الموظفون', value: '${t.count}')),
                  SizedBox(width: 170, child: KpiTile(label: 'الإجمالي', value: fmtMoney(t.gross))),
                  SizedBox(width: 170, child: KpiTile(label: 'الاستقطاعات', value: fmtMoney(t.deductions))),
                  SizedBox(width: 170, child: KpiTile(label: 'الصافي', value: fmtMoney(t.net), color: sem.ok)),
                ]),
        ),
        if (lines.any((l) => l.net < 0)) const InfoBanner(text: 'في الكشف صافٍ سالب؛ راجع الخصومات قبل الاعتماد.', level: 'critical'),
        const SizedBox(height: 12),
        if (lines.isNotEmpty)
          SectionCard(
            title: 'الأسطر',
            icon: Icons.table_rows_outlined,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columns: const [
                  DataColumn(label: Text('الموظف')),
                  DataColumn(label: Text('الأساسي'), numeric: true),
                  DataColumn(label: Text('البدلات'), numeric: true),
                  DataColumn(label: Text('الإضافي'), numeric: true),
                  DataColumn(label: Text('المكافآت'), numeric: true),
                  DataColumn(label: Text('الإجمالي'), numeric: true),
                  DataColumn(label: Text('الغياب'), numeric: true),
                  DataColumn(label: Text('التأمينات'), numeric: true),
                  DataColumn(label: Text('الضريبة'), numeric: true),
                  DataColumn(label: Text('الإضافية'), numeric: true),
                  DataColumn(label: Text('خصومات'), numeric: true),
                  DataColumn(label: Text('السلفة'), numeric: true),
                  DataColumn(label: Text('الصافي'), numeric: true),
                ],
                rows: [
                  for (final l in lines)
                    DataRow(cells: [
                      DataCell(Text(l.name)),
                      DataCell(Text(fmtNumber(l.basic))),
                      DataCell(Text(fmtNumber(l.allowances))),
                      DataCell(Text(fmtNumber(l.overtimeAmount))),
                      DataCell(Text(fmtNumber(l.bonuses))),
                      DataCell(Text(fmtNumber(l.gross))),
                      DataCell(Text(fmtNumber(l.absence))),
                      DataCell(Text(fmtNumber(l.insurance))),
                      DataCell(Text(fmtNumber(l.tax))),
                      DataCell(Text(fmtNumber(l.extraRule))),
                      DataCell(Tooltip(message: l.otherDetail.map((d) => '${d.name}: ${fmtNumber(d.amount)}').join('\n'), child: Text(fmtNumber(l.other)))),
                      DataCell(Text(fmtNumber(l.loan))),
                      DataCell(Text(fmtNumber(l.net), style: TextStyle(fontWeight: FontWeight.w700, color: l.net < 0 ? sem.danger : null))),
                    ]),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
