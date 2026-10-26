import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_state.dart';
import '../config.dart';
import '../models.dart';
import 'theme.dart';
import 'widgets.dart';

/// فتح رابط التحديث: تنزيل الملف على أندرويد وويندوز، وإعادة تحميل الصفحة على الويب.
Future<void> openUpdate(BuildContext context, AppRelease r) async {
  final uri = Uri.parse(r.url);
  bool ok;
  try {
    ok = kIsWeb
        ? await launchUrl(uri, webOnlyWindowName: '_self')
        : await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (_) {
    ok = false;
  }
  if (!ok && context.mounted) {
    showToast(context, 'تعذّر فتح رابط التحديث. انسخه وافتحه في المتصفح: ${r.url}', error: true);
  }
}

String _updateAction(AppRelease r) => r.platform == 'web' ? 'تحديث الآن' : 'تنزيل التحديث';

String _howTo(AppRelease r) => switch (r.platform) {
      'android' => 'بعد التنزيل افتح الملف واضغط «تثبيت». بياناتك محفوظة ولن تتأثر.',
      'windows' => 'بعد التنزيل أغلق البرنامج، وفكّ ضغط الملف مكان المجلد القديم، ثم شغّل dc_app.exe.',
      'web' => 'تُعاد تحميل الصفحة بأحدث نسخة.',
      _ => '',
    };

/// شريط «يتوفر تحديث» أعلى الشاشة.
class UpdateBanner extends StatelessWidget {
  const UpdateBanner({super.key, required this.app, required this.release});

  final AppState app;
  final AppRelease release;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return MaterialBanner(
      backgroundColor: cs.primaryContainer,
      leading: Icon(Icons.system_update, color: cs.onPrimaryContainer),
      content: Text(
        'يتوفر الإصدار ${release.version}' + (release.notes.isNotEmpty ? ' — ' + release.notes : ''),
        style: TextStyle(color: cs.onPrimaryContainer),
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
      ),
      actions: [
        TextButton(onPressed: app.dismissUpdate, child: const Text('لاحقاً')),
        FilledButton(onPressed: () => openUpdate(context, release), child: Text(_updateAction(release))),
      ],
    );
  }
}

/// شاشة التحديث الإلزامي: لا يعمل التطبيق حتى يُحدَّث.
class UpdateRequiredScreen extends StatelessWidget {
  const UpdateRequiredScreen({super.key, required this.release});

  final AppRelease release;

  @override
  Widget build(BuildContext context) {
    final sem = Sem.of(context);
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: brandAppBar(context, showEmblem: true, title: const Text('الدورة المستندية')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Center(child: BrandEmblem(size: 96)),
                const SizedBox(height: 18),
                Text('يلزم تحديث التطبيق', textAlign: TextAlign.center, style: t.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                Text(
                  'أصدر مدير المكتب الإصدار ${release.version} وجعله إلزامياً. حدّث التطبيق لتتابع العمل.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: sem.muted),
                ),
                if (release.notes.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(color: sem.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: sem.rule)),
                    child: Text(release.notes),
                  ),
                ],
                const SizedBox(height: 18),
                FilledButton.icon(
                  onPressed: () => openUpdate(context, release),
                  icon: const Icon(Icons.system_update),
                  label: Text(_updateAction(release)),
                  style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                ),
                const SizedBox(height: 10),
                Text(_howTo(release), textAlign: TextAlign.center, style: TextStyle(color: sem.muted, fontSize: 13)),
                const SizedBox(height: 6),
                Text('إصدارك الحالي: ${AppConfig.appVersion}', textAlign: TextAlign.center, style: TextStyle(color: sem.muted, fontSize: 12)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
