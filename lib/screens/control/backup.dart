import 'dart:convert';
import 'dart:typed_data';

import 'package:file_saver/file_saver.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app_state.dart';
import '../../ui/theme.dart';
import '../../ui/widgets.dart';
import 'control_panel.dart';

/// النسخ الاحتياطي للإعدادات واستعادتها، والمزامنة التلقائية مع GitHub.
class BackupSection extends StatefulWidget {
  const BackupSection({super.key});

  @override
  State<BackupSection> createState() => _BackupSectionState();
}

class _BackupSectionState extends State<BackupSection> {
  bool _busy = false;

  static const _repo = 'https://github.com/faisalalshible1-sys/dc-app';

  Future<void> _export() async {
    setState(() => _busy = true);
    await runAction(context, () async {
      final data = await AppScope.read(context).exportConfig();
      final text = const JsonEncoder.withIndent('  ').convert(data);
      final now = DateTime.now();
      await FileSaver.instance.saveFile(
        name: 'إعدادات المنظومة ${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}',
        bytes: Uint8List.fromList(utf8.encode(text)),
        ext: 'json',
        mimeType: MimeType.json,
      );
    }, success: 'صُدّرت نسخة من الإعدادات');
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _import() async {
    final text = await textInputDialog(context,
        title: 'استعادة الإعدادات',
        message: 'الصق محتوى ملف الإعدادات المصدَّر (JSON). تُستعاد الإعدادات الحية فقط، وتمر كل قيمة بالتحقق نفسه، ولا تُستعاد إعدادات التحقق بخطوتين.',
        label: 'محتوى الملف',
        confirmLabel: 'استعادة',
        required: true);
    if (text == null) return;
    Map<String, dynamic>? settings;
    try {
      final decoded = jsonDecode(text);
      if (decoded is Map && decoded['settings'] is Map) {
        settings = Map<String, dynamic>.from(decoded['settings'] as Map);
      } else if (decoded is Map) {
        settings = Map<String, dynamic>.from(decoded);
      }
    } catch (_) {}
    if (settings == null) {
      if (mounted) showToast(context, 'المحتوى ليس ملف إعدادات صالحاً', error: true);
      return;
    }
    if (!mounted) return;
    setState(() => _busy = true);
    await runAction(context, () async {
      final n = await AppScope.read(context).importSettings(settings!);
      if (mounted) showToast(context, 'استُعيد $n إعداداً');
    });
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final sem = Sem.of(context);
    return PageBody(
      children: [
        PageHeader(
          icon: Icons.cloud_sync_outlined,
          title: 'النسخ والمزامنة',
          subtitle: 'نسخة من الإعدادات والتعريفات تُحفظ تلقائياً في مستودع المشروع على GitHub، ويمكنك تصديرها أو استعادتها يدوياً.',
          actions: [if (_busy) const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))],
        ),
        SectionCard(
          title: 'المزامنة التلقائية مع GitHub',
          icon: Icons.sync_rounded,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('كل ثلاث ساعات يعمل سير العمل «sync» في المستودع فيقوم بما يلي:'),
              const SizedBox(height: 8),
              for (final s in const [
                'يحفظ الإعدادات الحية والمراحل والنماذج والأقسام والحقول في الملف config/live-settings.json، فيبقى لكل تغيير تاريخ ونسخة.',
                'يحوّل كل فكرة جديدة إلى مهمة (Issue) في المستودع، ويضع رابطها في صفحة الأفكار، لتُنفَّذ في التحديثات القادمة.',
                'يحفظ قائمة الأفكار وحالاتها في الملف config/ideas.json.',
              ])
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Icon(Icons.check_rounded, size: 18, color: sem.ok),
                    const SizedBox(width: 8),
                    Expanded(child: Text(s)),
                  ]),
                ),
              const SizedBox(height: 6),
              Text('للمزامنة فوراً: Actions ← sync ← Run workflow.', style: TextStyle(color: sem.muted, fontSize: 12.5)),
              const SizedBox(height: 10),
              Wrap(spacing: 8, runSpacing: 8, children: [
                OutlinedButton.icon(
                  onPressed: () => launchUrl(Uri.parse('$_repo/actions/workflows/sync.yml'), mode: LaunchMode.externalApplication),
                  icon: const Icon(Icons.play_circle_outline),
                  label: const Text('سير عمل المزامنة'),
                ),
                OutlinedButton.icon(
                  onPressed: () => launchUrl(Uri.parse('$_repo/blob/main/config/live-settings.json'), mode: LaunchMode.externalApplication),
                  icon: const Icon(Icons.description_outlined),
                  label: const Text('ملف الإعدادات على GitHub'),
                ),
                OutlinedButton.icon(
                  onPressed: () => launchUrl(Uri.parse('$_repo/issues'), mode: LaunchMode.externalApplication),
                  icon: const Icon(Icons.task_alt_rounded),
                  label: const Text('مهام التطوير'),
                ),
              ]),
            ],
          ),
        ),
        const SizedBox(height: 16),
        SectionCard(
          title: 'نسخة يدوية',
          icon: Icons.save_alt_rounded,
          child: Column(
            children: [
              SettingRow(
                icon: Icons.download_rounded,
                title: 'تصدير الإعدادات والتعريفات',
                subtitle: 'ملف JSON بكل الإعدادات الحية والمراحل والنماذج والأقسام والحقول',
                onTap: _busy ? null : _export,
              ),
              SettingRow(
                icon: Icons.upload_rounded,
                title: 'استعادة الإعدادات من نسخة',
                subtitle: 'من ملف مصدَّر سابقاً أو من config/live-settings.json',
                onTap: _busy ? null : _import,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
