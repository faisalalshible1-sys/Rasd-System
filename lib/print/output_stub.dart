import 'dart:typed_data';

/// فتح ملف للعرض أو الطباعة (منصة غير مدعومة).
Future<String> openBytesOnPlatform(Uint8List bytes, String name, String ext, String mime) async => 'unsupported';
