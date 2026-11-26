import 'package:flutter/material.dart';

import '../../app_state.dart';
import '../../models.dart';
import '../../ui/theme.dart';
import '../../ui/widgets.dart';
import 'control_panel.dart';

/// الإعدادات الحية: تسري فوراً على كل المستخدمين وكل المنصات دون إصدار جديد.
class SettingsSection extends StatefulWidget {
  const SettingsSection({super.key});

  @override
  State<SettingsSection> createState() => _SettingsSectionState();
}

class _SettingsSectionState extends State<SettingsSection> {
  final _announcement = TextEditingController();
  String _level = 'info';
  final Map<String, TextEditingController> _labels = {for (final k in const ['done', 'wip', 'todo', 'na']) k: TextEditingController()};
  bool _loaded = false;
  bool _busy = false;

  static const _swatches = <(String, String)>[
    ('#8A6A1E', 'ذهبي الختم'),
    ('#1F4E79', 'أزرق رسمي'),
    ('#0F766E', 'فيروزي'),
    ('#27894D', 'أخضر العلم'),
    ('#963037', 'عنابي'),
    ('#4B5563', 'رمادي'),
    ('#6D28D9', 'بنفسجي'),
  ];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loaded) return;
    final s = AppScope.of(context).settings;
    _announcement.text = s.announcementText;
    _level = s.announcementLevel;
    for (final e in _labels.entries) {
      e.value.text = statusLabels[e.key] ?? '';
    }
    _loaded = true;
  }

  @override
  void dispose() {
    _announcement.dispose();
    for (final c in _labels.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save(String key, Object? value, String ok) async {
    setState(() => _busy = true);
    await runAction(context, () => AppScope.read(context).setSetting(key, value), success: ok);
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _editText(String key, String title, String current) async {
    final v = await textInputDialog(context, title: title, label: title, confirmLabel: 'حفظ', required: true, initial: current, multiline: false);
    if (v == null) return;
    await _save(key, v, 'حُفظ «$title»');
  }

  Future<void> _editRate(String key, String title, double current,
      {double max = 50, String message = 'تُعاد حسابات الضمان في كل المشاريع فور الحفظ.', String ok = 'حُفظت النسبة وأُعيد حساب الضمانات'}) async {
    final v = await textInputDialog(context,
        title: title,
        label: 'النسبة المئوية',
        confirmLabel: 'حفظ',
        required: true,
        initial: (current * 100).toStringAsFixed(current * 100 == (current * 100).roundToDouble() ? 0 : 2),
        multiline: false,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        message: message);
    if (v == null) return;
    final n = double.tryParse(v.replaceAll('%', '').replaceAll('٫', '.').trim());
    if (n == null || n < 0 || n > max) {
      if (mounted) showToast(context, 'اكتب نسبة بين 0 و${max.round()}', error: true);
      return;
    }
    await _save(key, n / 100, ok);
  }

  Future<void> _saveDeductionTypes(List<DeductionType> list, String ok) =>
      _save('finance.deduction_types', [for (final t in list) t.toJson()], ok);

  Future<void> _editDeductionType(List<DeductionType> list, DeductionType? t) async {
    final r = await showDialog<DeductionType>(context: context, builder: (_) => _DeductionTypeDialog(type: t));
    if (r == null) return;
    if (list.any((x) => x.key != r.key && x.label.trim() == r.label.trim())) {
      if (mounted) showToast(context, 'يوجد استقطاع بالاسم نفسه', error: true);
      return;
    }
    final next = [for (final x in list) x.key == r.key ? r : x, if (t == null) r];
    await _saveDeductionTypes(next, t == null ? 'أُضيف «${r.label}»' : 'حُفظ «${r.label}»');
  }

  Future<void> _removeDeductionType(List<DeductionType> list, DeductionType t) async {
    final ok = await confirmDialog(context,
        title: 'إزالة «${t.label}»؟',
        message: 'لا يظهر في المستخلصات الجديدة. المستخلصات المسجلة به تحتفظ بقيمه وتظهر باسمه المختصر حتى تُعدَّل.',
        confirmLabel: 'إزالة',
        danger: true);
    if (!ok) return;
    await _saveDeductionTypes([for (final x in list) if (x.key != t.key) x], 'أُزيل «${t.label}»');
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final sem = Sem.of(context);
    final s = app.settings;
    final features = s.map('ui.features');
    bool feat(String k) => features[k] is bool ? features[k] as bool : true;

    return PageBody(
      onRefresh: app.loadAll,
      children: [
        PageHeader(
          icon: Icons.tune_outlined,
          title: 'الإعدادات الحية',
          subtitle: 'ما تغيّره هنا يظهر فوراً لكل المستخدمين على كل الأجهزة دون إصدار جديد، ويُحفظ في سجل التدقيق، ويُنسخ تلقائياً إلى GitHub.',
          actions: [if (_busy) const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))],
        ),
        SectionCard(
          title: 'الهوية',
          icon: Icons.palette_outlined,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SettingRow(
                icon: Icons.title_rounded,
                title: 'اسم المنظومة',
                subtitle: s.appTitle,
                trailing: const Icon(Icons.edit_outlined, size: 20),
                onTap: () => _editText('brand.app_title', 'اسم المنظومة', s.appTitle),
              ),
              SettingRow(
                icon: Icons.apartment_rounded,
                title: 'اسم الجهة',
                subtitle: s.orgName,
                trailing: const Icon(Icons.edit_outlined, size: 20),
                onTap: () => _editText('brand.org_name', 'اسم الجهة', s.orgName),
              ),
              SettingRow(
                icon: Icons.account_balance_outlined,
                title: 'الجهة الأم',
                subtitle: s.orgParent,
                trailing: const Icon(Icons.edit_outlined, size: 20),
                onTap: () => _editText('brand.org_parent', 'الجهة الأم', s.orgParent),
              ),
              const SizedBox(height: 8),
              const Text('لون الهوية', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final sw in _swatches)
                    Tooltip(
                      message: sw.$2,
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: _busy ? null : () => _save('brand.primary_color', sw.$1, 'تغيّر لون الهوية'),
                        child: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: parseHexColor(sw.$1),
                            shape: BoxShape.circle,
                            border: Border.all(
                                color: s.primaryHex.toUpperCase() == sw.$1 ? Theme.of(context).colorScheme.onSurface : Colors.transparent,
                                width: 3),
                          ),
                          child: s.primaryHex.toUpperCase() == sw.$1 ? const Icon(Icons.check, color: Colors.white) : null,
                        ),
                      ),
                    ),
                  ActionChip(
                    avatar: const Icon(Icons.colorize_outlined, size: 18),
                    label: const Text('لون مخصص'),
                    onPressed: () async {
                      final v = await textInputDialog(context,
                          title: 'لون مخصص',
                          label: 'رمز اللون (مثل #1F4E79)',
                          confirmLabel: 'حفظ',
                          required: true,
                          initial: s.primaryHex,
                          multiline: false,
                          textDirection: TextDirection.ltr);
                      if (v == null) return;
                      final hex = v.trim().startsWith('#') ? v.trim() : '#${v.trim()}';
                      if (parseHexColor(hex) == null) {
                        if (context.mounted) showToast(context, 'رمز لون غير صحيح', error: true);
                        return;
                      }
                      await _save('brand.primary_color', hex.toUpperCase(), 'تغيّر لون الهوية');
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        SectionCard(
          title: 'إعلان عام',
          icon: Icons.campaign_outlined,
          subtitle: 'يظهر أعلى كل الشاشات لكل المستخدمين حتى تمسحه',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _announcement,
                minLines: 2,
                maxLines: 4,
                maxLength: 500,
                onChanged: (_) => setState(() {}),
                decoration: fieldDeco('نص الإعلان'),
              ),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'info', label: Text('معلومة')),
                  ButtonSegment(value: 'warning', label: Text('تنبيه')),
                  ButtonSegment(value: 'critical', label: Text('هام جداً')),
                ],
                selected: {_level},
                showSelectedIcon: false,
                onSelectionChanged: (v) => setState(() => _level = v.first),
              ),
              const SizedBox(height: 12),
              if (_announcement.text.trim().isNotEmpty) ...[
                InfoBanner(text: _announcement.text.trim(), level: _level),
                const SizedBox(height: 12),
              ],
              Wrap(spacing: 8, children: [
                FilledButton(
                  onPressed: _busy ? null : () => _save('ui.announcement', {'text': _announcement.text.trim(), 'level': _level}, 'نُشر الإعلان'),
                  child: const Text('نشر الإعلان'),
                ),
                OutlinedButton(
                  onPressed: _busy
                      ? null
                      : () {
                          _announcement.clear();
                          _save('ui.announcement', {'text': '', 'level': 'info'}, 'أُزيل الإعلان');
                        },
                  child: const Text('إزالة'),
                ),
              ]),
            ],
          ),
        ),
        const SizedBox(height: 16),
        SectionCard(
          title: 'مسميات حالات النماذج',
          icon: Icons.label_outline_rounded,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ResponsiveGrid(minItemWidth: 200, children: [
                for (final st in FormStatus.values)
                  TextField(controller: _labels[st.name], decoration: fieldDeco('الحالة: ${st.name}', helper: 'تظهر الآن: ${st.label}')),
              ]),
              const SizedBox(height: 12),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: FilledButton(
                  onPressed: _busy
                      ? null
                      : () => _save('ui.status_labels', {for (final e in _labels.entries) e.key: e.value.text.trim()}, 'حُفظت المسميات'),
                  child: const Text('حفظ المسميات'),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        SectionCard(
          title: 'الميزات',
          icon: Icons.toggle_on_outlined,
          subtitle: 'تشغيل أجزاء من المنظومة أو إيقافها للموظفين',
          child: Column(
            children: [
              for (final f in const [
                ('analysis', 'صفحة التحليل', 'المؤشرات والرسوم البيانية للموظفين'),
                ('export', 'التصدير إلى Excel', 'تنزيل سجل المشاريع'),
                ('quality_notes', 'ملاحظات التقييم والجودة', 'لمكتب التخطيط والتقييم وضمان الجودة'),
                ('ideas_for_all', 'إرسال الأفكار لكل الموظفين', 'إن أوقفته يبقى الإرسال لك وحدك'),
              ])
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(f.$2, style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text(f.$3, style: TextStyle(color: sem.muted)),
                  value: feat(f.$1),
                  onChanged: _busy
                      ? null
                      : (v) => _save('ui.features', {
                            for (final k in const ['analysis', 'export', 'quality_notes', 'ideas_for_all']) k: k == f.$1 ? v : feat(k),
                          }, v ? 'شُغّلت «${f.$2}»' : 'أُوقفت «${f.$2}»'),
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        SectionCard(
          title: 'المالية',
          icon: Icons.payments_outlined,
          child: Column(
            children: [
              SettingRow(
                icon: Icons.shield_moon_outlined,
                title: 'نسبة الضمان الابتدائي',
                subtitle: '${rateText(guaranteeInitialRate)} من قيمة الأعمال المنفذة، للعقود الجديدة (لا تتغير نسب العقود القائمة)',
                trailing: const Icon(Icons.edit_outlined, size: 20),
                onTap: () => _editRate('finance.guarantee_initial_rate', 'نسبة الضمان الابتدائي', guaranteeInitialRate),
              ),
              SettingRow(
                icon: Icons.verified_outlined,
                title: 'نسبة الضمان النهائي',
                subtitle: '${rateText(guaranteeFinalRate)} من قيمة الأعمال المنفذة، للعقود الجديدة (لا تتغير نسب العقود القائمة)',
                trailing: const Icon(Icons.edit_outlined, size: 20),
                onTap: () => _editRate('finance.guarantee_final_rate', 'نسبة الضمان النهائي', guaranteeFinalRate),
              ),
              SettingRow(
                icon: Icons.currency_exchange_rounded,
                title: 'رمز العملة',
                subtitle: currencyLabel,
                trailing: const Icon(Icons.edit_outlined, size: 20),
                onTap: () => _editText('finance.currency', 'رمز العملة', currencyLabel),
              ),
            ],
          ),
        ),
        if (app.v5Ready) ...[
          const SizedBox(height: 16),
          SectionCard(
            title: 'النسب الافتراضية للمستخلصات',
            icon: Icons.percent_rounded,
            subtitle: 'تُقترح تلقائياً عند تسجيل مستخلص جديد ويمكن تعديلها في كل مستخلص. لا تغيّر المستخلصات المسجلة.',
            child: Column(
              children: [
                SettingRow(
                  icon: Icons.lock_outline_rounded,
                  title: 'التأمين المحتجز',
                  subtitle: '${rateText(s.retentionRate)} من قيمة أعمال المستخلص',
                  trailing: const Icon(Icons.edit_outlined, size: 20),
                  onTap: () => _editRate('finance.retention_rate', 'نسبة التأمين المحتجز', s.retentionRate,
                      message: 'تُقترح في المستخلصات الجديدة.', ok: 'حُفظت نسبة التأمين'),
                ),
                SettingRow(
                  icon: Icons.account_balance_outlined,
                  title: 'الضرائب والرسوم',
                  subtitle: s.taxRate > 0 ? '${rateText(s.taxRate)} من قيمة أعمال المستخلص' : 'لا تُقترح (0%)',
                  trailing: const Icon(Icons.edit_outlined, size: 20),
                  onTap: () => _editRate('finance.tax_rate', 'نسبة الضرائب والرسوم', s.taxRate,
                      message: 'تُقترح في المستخلصات الجديدة. 0 لإيقافها.', ok: 'حُفظت نسبة الضرائب'),
                ),
                SettingRow(
                  icon: Icons.savings_outlined,
                  title: 'استرداد الدفعة المقدمة',
                  subtitle: s.advanceRecoveryRate > 0
                      ? '${rateText(s.advanceRecoveryRate)} من قيمة أعمال كل مستخلص حتى تكتمل'
                      : 'بنسبة الدفعة إلى القيمة التعاقدية (0%)',
                  trailing: const Icon(Icons.edit_outlined, size: 20),
                  onTap: () => _editRate('finance.advance_recovery_rate', 'نسبة استرداد الدفعة المقدمة', s.advanceRecoveryRate,
                      max: 100,
                      message: '0 = تُسترد بنسبة الدفعة إلى القيمة التعاقدية للعقد.',
                      ok: 'حُفظت نسبة الاسترداد'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          SectionCard(
            title: 'استقطاعات مخصصة',
            icon: Icons.playlist_add_rounded,
            subtitle: 'أنواع استقطاع إضافية تظهر حقولاً في كل مستخلص (مثل التأمينات الاجتماعية أو الدمغة)، ولكل منها نسبة افتراضية اختيارية.',
            trailing: s.deductionTypes.length >= 12
                ? null
                : IconButton.filledTonal(
                    tooltip: 'نوع استقطاع جديد',
                    onPressed: _busy ? null : () => _editDeductionType(s.deductionTypes, null),
                    icon: const Icon(Icons.add_rounded),
                  ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (s.deductionTypes.isEmpty)
                  Text('لا استقطاعات مخصصة. الأنواع الأساسية: التأمين، والدفعة المقدمة، والغرامات، والضرائب، وأخرى.',
                      style: TextStyle(color: sem.muted))
                else
                  for (final t in s.deductionTypes)
                    SettingRow(
                      icon: Icons.remove_circle_outline_rounded,
                      title: t.label,
                      subtitle: t.rate == null ? 'بلا نسبة افتراضية' : 'النسبة الافتراضية ${rateText(t.rate!)}',
                      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                        IconButton(
                          tooltip: 'تعديل',
                          onPressed: _busy ? null : () => _editDeductionType(s.deductionTypes, t),
                          icon: const Icon(Icons.edit_outlined, size: 20),
                        ),
                        IconButton(
                          tooltip: 'إزالة',
                          onPressed: _busy ? null : () => _removeDeductionType(s.deductionTypes, t),
                          icon: Icon(Icons.delete_outline, size: 20, color: sem.danger),
                        ),
                      ]),
                    ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// نافذة نوع استقطاع مخصص: الاسم والنسبة الافتراضية (اختيارية).
class _DeductionTypeDialog extends StatefulWidget {
  const _DeductionTypeDialog({this.type});

  final DeductionType? type;

  @override
  State<_DeductionTypeDialog> createState() => _DeductionTypeDialogState();
}

class _DeductionTypeDialogState extends State<_DeductionTypeDialog> {
  late final _label = TextEditingController(text: widget.type?.label ?? '');
  late final _rate = TextEditingController(
      text: widget.type?.rate == null ? '' : (widget.type!.rate! * 100).toStringAsFixed(widget.type!.rate! * 100 == (widget.type!.rate! * 100).roundToDouble() ? 0 : 2));
  String? _error;

  @override
  void dispose() {
    _label.dispose();
    _rate.dispose();
    super.dispose();
  }

  void _done() {
    final label = _label.text.trim();
    if (label.length < 2 || label.length > 40) {
      setState(() => _error = 'اكتب اسماً من 2 إلى 40 حرفاً.');
      return;
    }
    double? rate;
    final r = _rate.text.replaceAll('%', '').replaceAll('٫', '.').trim();
    if (r.isNotEmpty) {
      final n = double.tryParse(r);
      if (n == null || n < 0 || n > 50) {
        setState(() => _error = 'النسبة بين 0 و50، أو اتركها فارغة.');
        return;
      }
      rate = n / 100;
    }
    final key = widget.type?.key ?? 'd${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}';
    Navigator.of(context).pop(DeductionType(key: key, label: label, rate: rate));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.type == null ? 'نوع استقطاع جديد' : 'تعديل «${widget.type!.label}»'),
      content: SizedBox(
        width: 400,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          TextField(controller: _label, maxLength: 40, autofocus: true, decoration: fieldDeco('اسم الاستقطاع')),
          TextField(
            controller: _rate,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: fieldDeco('النسبة الافتراضية % (اختيارية)', helper: 'تُحسب من قيمة أعمال المستخلص').copyWith(suffixText: '%'),
          ),
          if (_error != null) ...[const SizedBox(height: 10), InfoBanner(text: _error!, level: 'critical')],
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('إلغاء')),
        FilledButton(onPressed: _done, child: const Text('حفظ')),
      ],
    );
  }
}
