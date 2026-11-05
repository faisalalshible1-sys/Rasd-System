import 'package:flutter/material.dart';

import '../../app_state.dart';
import '../../models.dart';
import '../../ui/motion.dart';
import '../../ui/theme.dart';
import '../../ui/widgets.dart';
import 'audit.dart';
import 'backup.dart';
import 'customize.dart';
import 'fields.dart';
import 'overview.dart';
import 'permissions.dart';
import 'security.dart';
import 'settings.dart';
import 'structure.dart';
import 'users.dart';

class _Section {
  const _Section(this.icon, this.title, this.subtitle, this.builder, {this.needsV2 = false, this.auditor = false, this.users = false});

  final IconData icon;
  final String title;
  final String subtitle;
  final Widget Function() builder;
  final bool needsV2;

  /// يظهر لـCISO (للاطلاع فقط).
  final bool auditor;
  final bool users;
}

final List<_Section> _sections = [
  _Section(Icons.dashboard_customize_outlined, 'نظرة عامة', 'حالة المنظومة والإجراءات السريعة', () => const OverviewSection()),
  _Section(Icons.group_outlined, 'المستخدمون والأدوار', 'البيانات الكاملة والتفعيل والأدوار والحذف', () => const UsersSection(),
      auditor: true, users: true),
  _Section(Icons.key_outlined, 'الصلاحيات', 'من يحدّث كل نموذج، والنماذج الحساسة', () => const PermissionsSection(),
      auditor: true),
  _Section(Icons.account_tree_outlined, 'المراحل والنماذج والأقسام', 'إضافة وتسمية وترتيب وإيقاف', () => const StructureSection(),
      needsV2: true),
  _Section(Icons.dynamic_form_outlined, 'الحقول الإضافية', 'حقول جديدة للمشاريع دون برمجة', () => const FieldsSection(), needsV2: true),
  _Section(Icons.tune_outlined, 'الإعدادات الحية', 'الهوية والإعلانات والمسميات والميزات والمالية', () => const SettingsSection(),
      needsV2: true),
  _Section(Icons.auto_fix_high_outlined, 'التخصيص والتطوير', 'الحركة والقائمة والرئيسية والمصطلحات ومساعد Claude',
      () => const CustomizeSection(), needsV2: true),
  _Section(Icons.shield_outlined, 'مركز الأمان', 'التحقق بخطوتين والجلسات وسجل الدخول والتجميد', () => const SecuritySection(),
      needsV2: true, auditor: true),
  _Section(Icons.history_rounded, 'سجل التدقيق', 'كل تعديل: من ومتى وماذا', () => const AuditSection(), auditor: true),
  _Section(Icons.cloud_sync_outlined, 'النسخ والمزامنة', 'تصدير الإعدادات واستعادتها والمزامنة مع GitHub', () => const BackupSection(),
      needsV2: true),
];

/// لوحة التحكم — لمدير المكتب، وCISO يرى منها أقسام التدقيق للاطلاع فقط.
class ControlPanelPage extends StatefulWidget {
  const ControlPanelPage({super.key});

  @override
  State<ControlPanelPage> createState() => _ControlPanelPageState();
}

class _ControlPanelPageState extends State<ControlPanelPage> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final sem = Sem.of(context);
    final cs = Theme.of(context).colorScheme;
    if (!app.canAudit) {
      return const Center(child: EmptyState(icon: Icons.lock_outline, title: 'لوحة التحكم لمدير المكتب وحده'));
    }
    final sections = app.isDirector ? _sections : _sections.where((x) => x.auditor).toList();
    if (_index >= sections.length) _index = 0;
    final pendingUsers = app.isDirector ? app.people.values.where((p) => !p.active && p.role == null).length : 0;
    final s = sections[_index];
    final body = s.needsV2 && !app.v2Ready
        ? const _NeedsMigration()
        : MotionSwitcher(child: KeyedSubtree(key: ValueKey(_index), child: s.builder()));

    return LayoutBuilder(builder: (context, c) {
      if (c.maxWidth >= 900) {
        return Row(
          children: [
            Container(
              width: 270,
              color: toneOf(context).surface2,
              child: ListView(
                padding: const EdgeInsets.all(12),
                children: [
                  if (!app.isDirector)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(8, 4, 8, 12),
                      child: InfoBanner(icon: Icons.visibility_outlined, text: 'صلاحيتك اطلاع كامل للقراءة فقط؛ لا يتغير شيء من هنا.'),
                    ),
                  for (var i = 0; i < sections.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Material(
                        color: i == _index ? cs.primaryContainer : Colors.transparent,
                        borderRadius: BorderRadius.circular(12),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () => setState(() => _index = i),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            child: Row(
                              children: [
                                Icon(sections[i].icon, size: 21, color: i == _index ? cs.onPrimaryContainer : sem.muted),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(sections[i].title,
                                          style: TextStyle(
                                              fontWeight: i == _index ? FontWeight.w700 : FontWeight.w600,
                                              color: i == _index ? cs.onPrimaryContainer : null)),
                                      Text(sections[i].subtitle,
                                          maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11.5, color: sem.muted)),
                                    ],
                                  ),
                                ),
                                if (sections[i].users && pendingUsers > 0) Badge(label: Text('$pendingUsers')),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            VerticalDivider(width: 1, color: sem.rule),
            Expanded(child: body),
          ],
        );
      }
      return Column(
        children: [
          SizedBox(
            height: 56,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              itemCount: sections.length,
              separatorBuilder: (_, __) => const SizedBox(width: 6),
              itemBuilder: (context, i) => ChoiceChip(
                avatar: Icon(sections[i].icon, size: 18),
                label: Text(sections[i].title),
                selected: i == _index,
                showCheckmark: false,
                onSelected: (_) => setState(() => _index = i),
              ),
            ),
          ),
          Divider(height: 1, color: sem.rule),
          Expanded(child: body),
        ],
      );
    });
  }
}

class _NeedsMigration extends StatelessWidget {
  const _NeedsMigration();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: EmptyState(
        icon: Icons.storage_rounded,
        title: 'هذا القسم يحتاج تحديث قاعدة البيانات',
        message: 'شغّل الملف supabase/migrations/20261027000006_platform_v2.sql مرة واحدة في SQL Editor على Supabase، ثم حدّث البيانات.',
      ),
    );
  }
}

/// عنوان فرعي داخل أقسام اللوحة.
class SubHeading extends StatelessWidget {
  const SubHeading(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 10),
      child: Text(text, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700, color: Sem.of(context).muted)),
    );
  }
}

/// ينفّذ عملية ويعرض نتيجتها.
Future<bool> runAction(BuildContext context, Future<void> Function() action, {String? success}) async {
  try {
    await action();
    if (context.mounted && success != null) showToast(context, success);
    return true;
  } catch (e) {
    if (context.mounted) showToast(context, friendlyError(e), error: true);
    return false;
  }
}

/// اسم المرحلة حسب رقمها.
String stageLabel(int i) => stageName(i);
