import 'package:flutter/material.dart';

import '../accounting.dart';
import '../app_state.dart';
import '../guarantees.dart' show FinAccount, accountKindNames;
import '../models.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';
import 'contract_finance.dart' show pickDay;
import 'pm_common.dart';

Future<void> _run(BuildContext context, Future<void> Function() f, String done) async {
  try {
    await f();
    if (context.mounted) showToast(context, done);
  } catch (e) {
    if (context.mounted) showToast(context, friendlyError(e), error: true);
  }
}

/// يقرأ رقماً بأي أرقام (عربية أو هندية أو لاتينية)؛ الفارغ صفر والمعطوب null.
double? _num(String s) {
  final b = StringBuffer();
  for (final r in s.trim().runes) {
    if (r >= 0x0660 && r <= 0x0669) {
      b.writeCharCode(0x30 + r - 0x0660);
    } else if (r >= 0x06F0 && r <= 0x06F9) {
      b.writeCharCode(0x30 + r - 0x06F0);
    } else if (r == 0x066B) {
      b.write('.');
    } else if (r == 0x066C || r == 0x2C || r == 0x20 || r == 0xA0) {
      continue;
    } else {
      b.writeCharCode(r);
    }
  }
  final t = b.toString();
  if (t.isEmpty) return 0;
  return double.tryParse(t);
}

Widget _notReady(String title, IconData icon) => PageBody(children: [
      PageHeader(title: title, icon: icon),
      const InfoBanner(text: 'المحاسبة تعمل بعد تطبيق الترحيل 50 على قاعدة البيانات.', level: 'warning'),
    ]);

// ---------------------------------------------------------------------
// دليل الحسابات وربط الحسابات المالية وحسابات القيود الآلية
// ---------------------------------------------------------------------

class ChartOfAccountsPage extends StatefulWidget {
  const ChartOfAccountsPage({super.key});

  @override
  State<ChartOfAccountsPage> createState() => _ChartOfAccountsPageState();
}

class _ChartOfAccountsPageState extends State<ChartOfAccountsPage> {
  Future<void> _edit(AppState app, {GlAccount? a}) async {
    final parents = app.glAccounts.where((x) => !x.postable && x.id != a?.id).toList();
    final ok = await showPmForm(
      context,
      title: a == null ? 'حساب جديد' : 'تعديل الحساب',
      note: 'الحساب الفرعي وحده تُسجَّل عليه القيود، والحساب الرئيسي يجمع أبناءه ونوعه نوع أبيه. لا يُنقل حساب عليه قيود ولا يُحذف.',
      sections: [
        PmSection('الحساب', [
          const PmField('code', 'الرمز (أرقام وحروف حتى 12)', PmKind.text, required: true, max: 12),
          const PmField('name', 'الاسم', PmKind.text, required: true, max: 100),
          PmField('type', 'النوع', PmKind.select, required: true, options: [for (final k in glTypeNames.entries) (k.key, k.value)]),
          PmField('parent', 'الحساب الأب', PmKind.select, options: [('', 'بلا أب'), for (final p in parents) (p.id, p.label)]),
          const PmField('postable', 'حساب فرعي (تُسجَّل عليه القيود)', PmKind.toggle),
          const PmField('active', 'مفعّل', PmKind.toggle),
        ]),
      ],
      values: a == null
          ? {'type': 'expense', 'parent': '', 'postable': true, 'active': true}
          : {'code': a.code, 'name': a.name, 'type': a.type, 'parent': a.parentId ?? '', 'postable': a.postable, 'active': a.active},
      onSave: (d) => app.saveGlAccount(
        id: a?.id,
        code: '${d['code']}'.trim(),
        name: '${d['name']}'.trim(),
        type: '${d['type']}',
        parentId: '${d['parent'] ?? ''}'.isEmpty ? null : '${d['parent']}',
        postable: d['postable'] == true,
        active: d['active'] == true,
      ),
    );
    if (ok && mounted) showToast(context, 'حُفظ الحساب');
  }

  Future<void> _link(AppState app, FinAccount a) async {
    final options = app.glAccounts.where((g) => g.type == 'asset' && g.postable && g.active).toList();
    final ok = await showPmForm(
      context,
      title: 'ربط «${a.name}» بدليل الحسابات',
      note: 'يُربط كل حساب مالي بحساب أصل فرعي واحد لا يشاركه غيره؛ ولا يُرحَّل تحويل من حساب أو إليه ما لم يكن مربوطاً.',
      sections: [
        PmSection('الربط', [
          PmField('gl', 'حساب الأصل', PmKind.select, options: [('', 'بلا ربط'), for (final g in options) (g.id, g.label)]),
        ]),
      ],
      values: {'gl': a.glAccountId ?? ''},
      onSave: (d) => app.linkFinAccount(a.id, '${d['gl'] ?? ''}'.isEmpty ? null : '${d['gl']}'),
    );
    if (ok && mounted) showToast(context, 'حُفظ الربط');
  }

  Future<void> _map(AppState app, String key) async {
    final spec = glMapKeys[key]!;
    final options = app.glAccounts.where((g) => g.type == spec.$2 && g.postable && g.active).toList();
    final ok = await showPmForm(
      context,
      title: spec.$1,
      note: 'يستعمله القيد الآلي لكشف المرتبات ولصرف المستخلصات عند الاعتماد. يغيّره من يملك صلاحية الاعتماد، ولا أثر له على قيود سبقت.',
      sections: [
        PmSection('الحساب', [
          PmField('gl', 'الحساب', PmKind.select, required: true, options: [for (final g in options) (g.id, g.label)]),
        ]),
      ],
      values: {'gl': app.glMap[key] ?? ''},
      onSave: (d) => app.setGlMap(key, '${d['gl']}'),
    );
    if (ok && mounted) showToast(context, 'حُفظ التعيين');
  }

  int _depth(AppState app, GlAccount a) {
    var d = 0;
    var cur = a;
    while (cur.parentId != null && d < 8) {
      final p = app.glById(cur.parentId);
      if (p == null) break;
      cur = p;
      d++;
    }
    return d;
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final sem = Sem.of(context);
    if (!app.v34Ready) return _notReady('دليل الحسابات', Icons.account_tree_outlined);
    final canEdit = app.canEditFinSettings;
    final canApprove = app.canApprovePayroll;
    final usedIds = {for (final l in app.journalLines) l.accountId};
    final accounts = [...app.glAccounts]..sort((a, b) => a.code.compareTo(b.code));
    return PageBody(
      onRefresh: app.loadAll,
      children: [
        PageHeader(
          title: 'دليل الحسابات',
          subtitle: 'شجرة حسابات القيود المزدوجة، وربط الخزينة والمصارف بها وتعيين حسابات قيد المرتبات.',
          icon: Icons.account_tree_outlined,
          actions: [
            if (canEdit) FilledButton.icon(onPressed: () => _edit(app), icon: const Icon(Icons.add_rounded), label: const Text('حساب')),
          ],
        ),
        SectionCard(
          title: 'الحسابات المالية والدليل',
          icon: Icons.link_rounded,
          subtitle: 'كل خزينة أو حساب مصرفي يقابله حساب أصل؛ وبدونه لا يُرحَّل تحويل.',
          child: app.finAccounts.isEmpty
              ? const Text('لا حسابات مالية؛ أضفها من صفحة «الحسابات والتحويلات».')
              : Column(children: [
                  for (final a in app.finAccounts)
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(a.kind == 'cash' ? Icons.payments_outlined : Icons.account_balance_outlined),
                      title: Text(a.name),
                      subtitle: Text(accountKindNames[a.kind] ?? a.kind),
                      trailing: Wrap(spacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
                        if (a.glAccountId == null)
                          ToneBadge('غير مربوط', color: sem.danger)
                        else
                          Text(app.glById(a.glAccountId)?.label ?? '—', style: const TextStyle(fontWeight: FontWeight.w700)),
                        if (canEdit) TextButton(onPressed: () => _link(app, a), child: Text(a.glAccountId == null ? 'ربط' : 'تغيير')),
                      ]),
                    ),
                ]),
        ),
        const SizedBox(height: 12),
        SectionCard(
          title: 'حسابات قيد المرتبات الآلي',
          icon: Icons.payments_outlined,
          subtitle: 'يُنشأ القيد عند اعتماد الكشف، ويُعكس عند التراجع عنه.',
          child: Column(children: [
            for (final e in glMapKeys.entries)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(e.value.$1),
                trailing: Wrap(spacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
                  Text(app.glById(app.glMap[e.key])?.label ?? 'غير معيّن', style: const TextStyle(fontWeight: FontWeight.w700)),
                  if (canApprove) TextButton(onPressed: () => _map(app, e.key), child: const Text('تغيير')),
                ]),
              ),
          ]),
        ),
        const SizedBox(height: 12),
        SectionCard(
          title: 'الدليل',
          icon: Icons.account_tree_outlined,
          subtitle: '${accounts.length} حساباً',
          child: Column(children: [
            for (final a in accounts)
              Padding(
                padding: EdgeInsetsDirectional.only(start: 14.0 * _depth(app, a)),
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(a.postable ? Icons.article_outlined : Icons.folder_outlined, color: a.active ? null : sem.muted),
                  title: Text(a.label, style: TextStyle(fontWeight: a.postable ? FontWeight.w500 : FontWeight.w800)),
                  subtitle: Text('${glTypeNames[a.type]} · ${a.postable ? 'فرعي' : 'رئيسي'}${a.active ? '' : ' · موقوف'}'),
                  trailing: canEdit
                      ? Row(mainAxisSize: MainAxisSize.min, children: [
                          IconButton(tooltip: 'تعديل', onPressed: () => _edit(app, a: a), icon: const Icon(Icons.edit_outlined)),
                          if (!usedIds.contains(a.id))
                            IconButton(
                              tooltip: 'حذف',
                              onPressed: () async {
                                final yes = await confirmDialog(context, title: 'حذف الحساب', message: 'يُحذف «${a.label}». لا يُحذف حساب عليه قيود أو أبناء أو تعيين.', confirmLabel: 'حذف', danger: true);
                                if (yes && context.mounted) await _run(context, () => app.deleteGlAccount(a.id), 'حُذف الحساب');
                              },
                              icon: const Icon(Icons.delete_outline_rounded),
                            ),
                        ])
                      : null,
                ),
              ),
          ]),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------
// قيود اليومية
// ---------------------------------------------------------------------

class _LineEd {
  _LineEd({this.account, String debit = '', String credit = '', String memo = ''})
      : debit = TextEditingController(text: debit),
        credit = TextEditingController(text: credit),
        memo = TextEditingController(text: memo);
  String? account;
  final TextEditingController debit;
  final TextEditingController credit;
  final TextEditingController memo;

  void dispose() {
    debit.dispose();
    credit.dispose();
    memo.dispose();
  }
}

String _plain(double v) => v == 0 ? '' : (v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString());

class _JournalDialog extends StatefulWidget {
  const _JournalDialog({required this.app, this.entry, this.lines = const []});
  final AppState app;
  final JournalEntry? entry;
  final List<JournalLine> lines;

  @override
  State<_JournalDialog> createState() => _JournalDialogState();
}

class _JournalDialogState extends State<_JournalDialog> {
  late DateTime _date = widget.entry?.date ?? DateTime.now();
  late final TextEditingController _memo = TextEditingController(text: widget.entry?.memo ?? '');
  late final List<_LineEd> _lines = widget.lines.isEmpty
      ? [_LineEd(), _LineEd()]
      : [for (final l in widget.lines) _LineEd(account: l.accountId, debit: _plain(l.debit), credit: _plain(l.credit), memo: l.memo)];
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _memo.dispose();
    for (final l in _lines) {
      l.dispose();
    }
    super.dispose();
  }

  ({double d, double c}) _sums() {
    var d = 0.0, c = 0.0;
    for (final l in _lines) {
      d += _num(l.debit.text) ?? 0;
      c += _num(l.credit.text) ?? 0;
    }
    return (d: d, c: c);
  }

  Future<void> _save() async {
    final out = <Map<String, Object?>>[];
    for (var i = 0; i < _lines.length; i++) {
      final l = _lines[i];
      final d = _num(l.debit.text), c = _num(l.credit.text);
      if (l.account == null) {
        setState(() => _error = 'اختر حساب السطر ${i + 1}');
        return;
      }
      if (d == null || c == null || d < 0 || c < 0 || (d > 0) == (c > 0)) {
        setState(() => _error = 'السطر ${i + 1}: مبلغ في المدين أو في الدائن وليس في الاثنين');
        return;
      }
      out.add({'account': l.account, 'debit': d, 'credit': c, 'memo': l.memo.text.trim()});
    }
    if (_memo.text.trim().isEmpty) {
      setState(() => _error = 'بيان القيد مطلوب');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.app.saveJournal(id: widget.entry?.id, date: _date, memo: _memo.text.trim(), lines: out);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = friendlyError(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final sem = Sem.of(context);
    final accounts = widget.app.glAccounts.where((a) => a.postable && a.active).toList()..sort((a, b) => a.code.compareTo(b.code));
    final s = _sums();
    final diff = ((s.d - s.c) * 1000).round() / 1000;
    final balanced = diff == 0 && s.d > 0;
    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 860, maxHeight: 720),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(widget.entry == null ? 'قيد يومية جديد' : 'تعديل مسودة القيد', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 4),
            Text('يُحفظ مسودة؛ ويرحّله من يملك صلاحية الاعتماد بعد توازن المدين والدائن. بعد الترحيل لا يُعدَّل ولا يُحذف ويُصحَّح بقيد عكسي.',
                style: TextStyle(color: sem.muted, fontSize: 12.5)),
            const SizedBox(height: 12),
            Row(children: [
              OutlinedButton.icon(
                onPressed: _busy
                    ? null
                    : () async {
                        final d = await pickDay(context, _date);
                        if (d != null) setState(() => _date = d);
                      },
                icon: const Icon(Icons.event_rounded),
                label: Text(fmtDate(_date)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _memo,
                  enabled: !_busy,
                  maxLength: 300,
                  decoration: const InputDecoration(labelText: 'البيان', border: OutlineInputBorder(), isDense: true, counterText: ''),
                ),
              ),
            ]),
            const SizedBox(height: 10),
            Expanded(
              child: ListView(children: [
                for (var i = 0; i < _lines.length; i++)
                  Padding(
                    key: ObjectKey(_lines[i]),
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                      SizedBox(
                        width: 280,
                        child: DropdownButtonFormField<String>(
                          initialValue: _lines[i].account,
                          isExpanded: true,
                          decoration: InputDecoration(labelText: 'حساب السطر ${i + 1}', border: const OutlineInputBorder(), isDense: true),
                          items: [for (final a in accounts) DropdownMenuItem(value: a.id, child: Text(a.label, overflow: TextOverflow.ellipsis))],
                          onChanged: _busy ? null : (v) => setState(() => _lines[i].account = v),
                        ),
                      ),
                      SizedBox(
                        width: 110,
                        child: TextField(
                          controller: _lines[i].debit,
                          enabled: !_busy,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          onChanged: (_) => setState(() {}),
                          decoration: const InputDecoration(labelText: 'مدين', border: OutlineInputBorder(), isDense: true),
                        ),
                      ),
                      SizedBox(
                        width: 110,
                        child: TextField(
                          controller: _lines[i].credit,
                          enabled: !_busy,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          onChanged: (_) => setState(() {}),
                          decoration: const InputDecoration(labelText: 'دائن', border: OutlineInputBorder(), isDense: true),
                        ),
                      ),
                      SizedBox(
                        width: 180,
                        child: TextField(
                          controller: _lines[i].memo,
                          enabled: !_busy,
                          maxLength: 200,
                          decoration: const InputDecoration(labelText: 'بيان السطر', border: OutlineInputBorder(), isDense: true, counterText: ''),
                        ),
                      ),
                      if (_lines.length > 2)
                        IconButton(
                          tooltip: 'حذف السطر',
                          onPressed: _busy
                              ? null
                              : () => setState(() {
                                    _lines.removeAt(i).dispose();
                                  }),
                          icon: const Icon(Icons.remove_circle_outline_rounded),
                        ),
                    ]),
                  ),
                if (_lines.length < 100)
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: TextButton.icon(onPressed: _busy ? null : () => setState(() => _lines.add(_LineEd())), icon: const Icon(Icons.add_rounded), label: const Text('سطر')),
                  ),
              ]),
            ),
            const Divider(),
            Row(children: [
              Expanded(
                child: Text(
                  'المدين ${fmtMoney(s.d)} · الدائن ${fmtMoney(s.c)} · ${balanced ? 'متوازن' : 'الفرق ${fmtMoney(diff.abs())}'}',
                  style: TextStyle(fontWeight: FontWeight.w700, color: balanced ? sem.ok : sem.danger),
                ),
              ),
              TextButton(onPressed: _busy ? null : () => Navigator.of(context).pop(false), child: const Text('إلغاء')),
              const SizedBox(width: 6),
              FilledButton(onPressed: _busy ? null : _save, child: Text(_busy ? 'جارٍ الحفظ…' : 'حفظ المسودة')),
            ]),
            if (_error != null)
              Padding(padding: const EdgeInsets.only(top: 8), child: Text(_error!, style: TextStyle(color: sem.danger, fontWeight: FontWeight.w600))),
          ]),
        ),
      ),
    );
  }
}

class JournalPage extends StatefulWidget {
  const JournalPage({super.key});

  @override
  State<JournalPage> createState() => _JournalPageState();
}

class _JournalPageState extends State<JournalPage> {
  String _filter = 'all';

  Future<void> _edit(AppState app, {JournalEntry? j, List<JournalLine> lines = const []}) async {
    final ok = await showDialog<bool>(context: context, barrierDismissible: false, builder: (_) => _JournalDialog(app: app, entry: j, lines: lines));
    if (ok == true && mounted) showToast(context, 'حُفظت مسودة القيد');
  }

  Future<void> _reverse(AppState app, JournalEntry j) async {
    final ok = await showPmForm(
      context,
      title: 'عكس القيد رقم ${j.entryNo}',
      note: 'يُنشأ قيد عكسي مرحَّل بسطور معكوسة، ويبقى القيد الأصلي ظاهراً مع سبب العكس. لا يُعكس القيد مرتين.',
      sections: [
        const PmSection('العكس', [PmField('reason', 'سبب العكس', PmKind.multiline, required: true, max: 300, full: true)]),
      ],
      values: const {},
      onSave: (d) => app.reverseJournal(j.id, '${d['reason']}'.trim()),
    );
    if (ok && mounted) showToast(context, 'عُكس القيد');
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final sem = Sem.of(context);
    if (!app.v34Ready) return _notReady('قيود اليومية', Icons.menu_book_outlined);
    final canEdit = app.canEditFinSettings;
    final canApprove = app.canApprovePayroll;
    final byJournal = <String, List<JournalLine>>{};
    for (final l in app.journalLines) {
      (byJournal[l.journalId] ??= []).add(l);
    }
    final list = app.journals.where((j) {
      return switch (_filter) {
        'draft' => j.isDraft,
        'manual' => j.isManual && j.isPosted,
        'auto' => !j.isManual,
        _ => true,
      };
    }).toList()
      ..sort((a, b) {
        final c = b.date.compareTo(a.date);
        return c != 0 ? c : (b.entryNo ?? 1 << 30).compareTo(a.entryNo ?? 1 << 30);
      });
    final drafts = app.journals.where((j) => j.isDraft).length;
    return PageBody(
      onRefresh: app.loadAll,
      children: [
        PageHeader(
          title: 'قيود اليومية',
          subtitle: 'قيود مزدوجة: يدوية بمسودة ثم ترحيل، وآلية من كشف المرتبات والتحويلات.',
          icon: Icons.menu_book_outlined,
          actions: [
            if (canEdit) FilledButton.icon(onPressed: () => _edit(app), icon: const Icon(Icons.add_rounded), label: const Text('قيد')),
          ],
        ),
        if (drafts > 0 && canApprove) InfoBanner(text: 'في انتظار الترحيل $drafts مسودة قيد.', level: 'info'),
        Wrap(spacing: 10, runSpacing: 8, children: [
          pmFilter('العرض', _filter, const [('all', 'الكل'), ('draft', 'مسودات'), ('manual', 'يدوية مرحَّلة'), ('auto', 'آلية')], (v) => setState(() => _filter = v)),
        ]),
        const SizedBox(height: 10),
        if (list.isEmpty)
          const EmptyState(title: 'لا قيود', message: 'تظهر هنا القيود اليدوية والآلية.', icon: Icons.menu_book_outlined)
        else
          for (final j in list)
            Builder(builder: (context) {
              final lines = byJournal[j.id] ?? const <JournalLine>[];
              final bal = journalBalance(lines);
              final tone = j.isDraft ? sem.wip : (j.isReversed ? sem.muted : sem.ok);
              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ExpansionTile(
                  shape: const Border(),
                  title: Text('${j.entryNo == null ? 'مسودة' : 'قيد ${j.entryNo}'} — ${j.memo}'),
                  subtitle: Text('${fmtDate(j.date)} · ${journalSourceNames[j.source] ?? j.source} · ${fmtMoney(bal.debit)}'),
                  trailing: ToneBadge(j.isDraft ? 'مسودة' : (j.isReversed ? 'معكوس' : (j.isReversal ? 'عكسي' : 'مرحَّل')), color: tone),
                  childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  children: [
                    for (final l in lines)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        child: Row(children: [
                          Expanded(child: Text('${app.glById(l.accountId)?.label ?? '—'}${l.memo.isEmpty ? '' : ' — ${l.memo}'}')),
                          SizedBox(width: 100, child: Text(l.debit == 0 ? '' : fmtMoney(l.debit), textAlign: TextAlign.end)),
                          SizedBox(width: 100, child: Text(l.credit == 0 ? '' : fmtMoney(l.credit), textAlign: TextAlign.end)),
                        ]),
                      ),
                    const Divider(),
                    Row(children: [
                      const Expanded(child: Text('المجموع', style: TextStyle(fontWeight: FontWeight.w800))),
                      SizedBox(width: 100, child: Text(fmtMoney(bal.debit), textAlign: TextAlign.end, style: const TextStyle(fontWeight: FontWeight.w800))),
                      SizedBox(width: 100, child: Text(fmtMoney(bal.credit), textAlign: TextAlign.end, style: const TextStyle(fontWeight: FontWeight.w800))),
                    ]),
                    if (j.isReversed) Padding(padding: const EdgeInsets.only(top: 6), child: Text('عُكس: ${j.reverseReason}', style: TextStyle(color: sem.muted))),
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Wrap(spacing: 8, children: [
                        if (j.isDraft && canEdit) OutlinedButton(onPressed: () => _edit(app, j: j, lines: lines), child: const Text('تعديل')),
                        if (j.isDraft && canApprove) FilledButton(onPressed: () => _run(context, () => app.postJournal(j.id), 'رُحّل القيد'), child: const Text('ترحيل')),
                        if (j.isDraft && canEdit)
                          TextButton(
                            onPressed: () async {
                              final yes = await confirmDialog(context, title: 'حذف المسودة', message: 'تُحذف مسودة «${j.memo}».', confirmLabel: 'حذف', danger: true);
                              if (yes && context.mounted) await _run(context, () => app.deleteJournal(j.id), 'حُذفت المسودة');
                            },
                            child: const Text('حذف'),
                          ),
                        if (j.isPosted && j.isManual && !j.isReversed && !j.isReversal && canApprove) OutlinedButton(onPressed: () => _reverse(app, j), child: const Text('عكس القيد')),
                      ]),
                    ),
                  ],
                ),
              );
            }),
      ],
    );
  }
}

// ---------------------------------------------------------------------
// الأستاذ وميزان المراجعة
// ---------------------------------------------------------------------

class LedgerPage extends StatefulWidget {
  const LedgerPage({super.key});

  @override
  State<LedgerPage> createState() => _LedgerPageState();
}

class _LedgerPageState extends State<LedgerPage> {
  late DateTime _from = DateTime(DateTime.now().year, DateTime.now().month, 1);
  late DateTime _to = DateTime.now();
  String _account = '';

  Future<void> _pick(bool from) async {
    final d = await pickDay(context, from ? _from : _to);
    if (d != null) setState(() => from ? _from = d : _to = d);
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final sem = Sem.of(context);
    if (!app.v34Ready) return _notReady('الأستاذ وميزان المراجعة', Icons.balance_outlined);
    final trial = trialBalance(app.glAccounts, app.journals, app.journalLines, _from, _to);
    final tot = trialTotals(trial);
    final selected = app.glById(_account.isEmpty ? null : _account);
    final ledger = selected == null ? null : ledgerFor(selected, app.journals, app.journalLines, _from, _to);
    final accountOptions = [('', 'ميزان المراجعة (كل الحسابات)'), for (final a in app.glAccounts.where((a) => a.postable)) (a.id, a.label)];
    return PageBody(
      onRefresh: app.loadAll,
      children: [
        const PageHeader(title: 'الأستاذ وميزان المراجعة', subtitle: 'من القيود المرحَّلة وحدها، بالجانب الطبيعي لكل حساب.', icon: Icons.balance_outlined),
        Wrap(spacing: 10, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
          pmFilter('الحساب', _account, accountOptions, (v) => setState(() => _account = v), width: 300),
          OutlinedButton.icon(onPressed: () => _pick(true), icon: const Icon(Icons.event_rounded), label: Text('من ${fmtDate(_from)}')),
          OutlinedButton.icon(onPressed: () => _pick(false), icon: const Icon(Icons.event_rounded), label: Text('إلى ${fmtDate(_to)}')),
        ]),
        const SizedBox(height: 12),
        if (ledger == null)
          SectionCard(
            title: 'ميزان المراجعة',
            icon: Icons.balance_outlined,
            subtitle: tot.debit == tot.credit ? 'متوازن: ${fmtMoney(tot.debit)}' : 'غير متوازن — راجع القيود',
            child: trial.isEmpty
                ? const Text('لا حركة في هذه الفترة ولا أرصدة قبلها.')
                : Column(children: [
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(children: [
                        const Expanded(child: Text('الحساب', style: TextStyle(fontWeight: FontWeight.w800))),
                        for (final h in const ['افتتاحي', 'مدين', 'دائن', 'ختامي']) SizedBox(width: 92, child: Text(h, textAlign: TextAlign.end, style: const TextStyle(fontWeight: FontWeight.w800))),
                      ]),
                    ),
                    for (final r in trial)
                      InkWell(
                        onTap: () => setState(() => _account = r.account.id),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 5),
                          child: Row(children: [
                            Expanded(child: Text(r.account.label, overflow: TextOverflow.ellipsis)),
                            SizedBox(width: 92, child: Text(fmtMoney(r.opening), textAlign: TextAlign.end)),
                            SizedBox(width: 92, child: Text(fmtMoney(r.debit), textAlign: TextAlign.end)),
                            SizedBox(width: 92, child: Text(fmtMoney(r.credit), textAlign: TextAlign.end)),
                            SizedBox(width: 92, child: Text(fmtMoney(r.closing), textAlign: TextAlign.end, style: const TextStyle(fontWeight: FontWeight.w700))),
                          ]),
                        ),
                      ),
                    const Divider(),
                    Row(children: [
                      const Expanded(child: Text('المجموع', style: TextStyle(fontWeight: FontWeight.w800))),
                      const SizedBox(width: 92),
                      SizedBox(width: 92, child: Text(fmtMoney(tot.debit), textAlign: TextAlign.end, style: const TextStyle(fontWeight: FontWeight.w800))),
                      SizedBox(width: 92, child: Text(fmtMoney(tot.credit), textAlign: TextAlign.end, style: const TextStyle(fontWeight: FontWeight.w800))),
                      const SizedBox(width: 92),
                    ]),
                  ]),
          )
        else
          SectionCard(
            title: selected!.label,
            icon: Icons.menu_book_outlined,
            subtitle: 'افتتاحي ${fmtMoney(ledger.opening)} · ختامي ${fmtMoney(ledger.closing)} (${glDebitNormal(selected!.type) ? 'مدين طبيعي' : 'دائن طبيعي'})',
            child: ledger.rows.isEmpty
                ? const Text('لا حركة على الحساب في هذه الفترة.')
                : Column(children: [
                    for (final r in ledger.rows)
                      ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text('${fmtDate(r.entry.date)} · قيد ${r.entry.entryNo ?? '—'} — ${r.entry.memo}'),
                        subtitle: r.line.memo.isEmpty ? null : Text(r.line.memo),
                        trailing: SizedBox(
                          width: 300,
                          child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                            SizedBox(width: 92, child: Text(r.line.debit == 0 ? '' : fmtMoney(r.line.debit), textAlign: TextAlign.end, style: TextStyle(color: sem.ok))),
                            SizedBox(width: 92, child: Text(r.line.credit == 0 ? '' : fmtMoney(r.line.credit), textAlign: TextAlign.end, style: TextStyle(color: sem.danger))),
                            SizedBox(width: 100, child: Text(fmtMoney(r.balance), textAlign: TextAlign.end, style: const TextStyle(fontWeight: FontWeight.w700))),
                          ]),
                        ),
                      ),
                  ]),
          ),
      ],
    );
  }
}
