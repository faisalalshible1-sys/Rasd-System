// الويب: يُفتح الملف في تبويب جديد (عارض PDF في المتصفح يطبع مباشرة).
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

Future<String> openBytesOnPlatform(Uint8List bytes, String name, String ext, String mime) async {
  final blob = web.Blob([bytes.toJS].toJS, web.BlobPropertyBag(type: mime));
  final url = web.URL.createObjectURL(blob);
  final w = web.window.open(url, '_blank');
  return w == null ? 'blocked' : 'opened';
}
