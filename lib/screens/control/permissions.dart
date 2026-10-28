import 'package:flutter/material.dart';

import '../../app_state.dart';
import '../../models.dart';
import '../../ui/theme.dart';
import '../../ui/widgets.dart';
import 'control_panel.dart';

/// صلاحيات النماذج: من يحدّث كل نموذج، وأي النماذج حساسة.
class PermissionsSection extends StatefulWidget {
  const PermissionsSection({super.key});

  @override
  State<PermissionsSection> createState() => _PermissionsSectionState();
}

class _PermissionsSectionState extends State<PermissionsSection> {
  String? _busyKey;

  Future<void> _update(AppState app, FormDef d, {bool? sensitive, List<String>? responsible}) async {
    setState(() => _busyKey = d.key);
    await runAction(context, () => app.updateFormDef(d.key, sensitive: sensitive, responsible: responsible),
        success: 'حُفظت صلاحيات «${d.name}»');
    if (mounted) setState(() => _busyKey = null);
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final sem = Sem.of(context);
    final defs = app.allFormDefs.isNotEmpty ? app.allFormDefs : app.formDefs;
    final contract = app.formDef(contractFormKey);
    // مدقق الأمن يراجع توزيع الصلاحيات للاطلاع فقط
    final readOnly = !app.isDirector;
    return PageBody(
      onRefresh: app.loadAll,
      children: [
        PageHeader(
          icon: Icons.key_outlined,
          title: 'الصلاحيات',
          subtitle: readOnly
              ? 'من يحدّث كل نموذج، وأي النماذج حساسة تحتاج اعتماد مدير المكتب. للاطلاع فقط.'
              : 'حدّد من يحدّث كل نموذج، وأي النماذج حساسة. تغيير النموذج الحساس من غيرك يرفع طلب اعتماد إليك، وأنت تحدّث كل النماذج مباشرة.',
        ),
        Wrap(spacing: 8, runSpacing: 8, children: [
          ToneBadge('${defs.where((d) => d.sensitive).length} نموذجاً حساساً', color: sem.wip, icon: Icons.verified_user_outlined),
          ToneBadge('${defs.where((d) => !d.active).length} موقوف', color: sem.muted, icon: Icons.pause_circle_outline),
        ]),
        if (contract != null) ...[
          const SizedBox(height: 12),
          InfoBanner(
            text: 'البيانات المالية للعقد (قيمة التعاقد والدفعات والخصومات) يحدّثها من يختص بـ«${contract.name}»: '
                '${contract.responsible.map((t) => responsibleLabels[t] ?? t).join('، ')}.',
            icon: Icons.payments_outlined,
          ),
        ],
        const SizedBox(height: 14),
        for (var s = 0; s < stageNames.length; s++) ...[
          if (defs.any((d) => d.stage == s)) SubHeading('${s + 1}. ${stageNames[s]}'),
          for (final d in defs.where((d) => d.stage == s))
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Opacity(
                opacity: d.active ? 1 : 0.55,
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(color: sem.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: sem.rule)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(d.active ? d.name : '${d.name} (موقوف)', style: const TextStyle(fontWeight: FontWeight.w700)),
                          ),
                          if (_busyKey == d.key)
                            const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 8),
                              child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                            ),
                          Text('حساس', style: TextStyle(color: d.sensitive ? sem.wip : sem.muted, fontSize: 12.5)),
                          Switch(value: d.sensitive, onChanged: readOnly || _busyKey != null ? null : (v) => _update(app, d, sensitive: v)),
                        ],
                      ),
                      const SizedBox(height: 6),
                      TokenSelector(
                        selected: d.responsible,
                        enabled: !readOnly && _busyKey == null,
                        onChanged: (next) => _update(app, d, responsible: next),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ],
    );
  }
}
