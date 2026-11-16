// الحاسوب: يُكتب الملف في مجلد مؤقت ويُفتح ببرنامجه الافتراضي (ومنه يُطبع).
// الهاتف: لا يُفتح ملف محلي من التطبيق مباشرة، فيُحفظ بنافذة «حفظ باسم» ويفتحه المستخدم للطباعة.
import 'dart:io';
import 'dart:typed_data';

import 'package:file_saver/file_saver.dart';
import 'package:url_launcher/url_launcher.dart';

Future<String> openBytesOnPlatform(Uint8List bytes, String name, String ext, String mime) async {
  if (Platform.isAndroid || Platform.isIOS) {
    final path = await FileSaver.instance.saveAs(name: name, bytes: bytes, ext: ext, mimeType: MimeType.custom, customMimeType: mime);
    return path == null || path.isEmpty ? 'cancelled' : 'saved';
  }
  final dir = await Directory.systemTemp.createTemp('dc_print_');
  final f = File('${dir.path}${Platform.pathSeparator}$name.$ext');
  await f.writeAsBytes(bytes, flush: true);
  final ok = await launchUrl(Uri.file(f.path));
  return ok ? 'opened' : 'saved';
}
