// حفظ الملفات المستخرجة وفتحها للطباعة على كل منصة.

import 'dart:typed_data';

import 'package:file_saver/file_saver.dart';
import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;

import 'output_stub.dart' if (dart.library.io) 'output_io.dart' if (dart.library.js_interop) 'output_web.dart' as platform;

/// اسم ملف صالح في Windows وغيره.
String safeFileName(String s) {
  final clean = s.replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1F]'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
  if (clean.isEmpty) return 'ملف';
  return clean.length > 90 ? clean.substring(0, 90).trim() : clean;
}

MimeType _type(String ext) => switch (ext) {
      'pdf' => MimeType.pdf,
      'docx' => MimeType.microsoftWord,
      'xlsx' => MimeType.microsoftExcel,
      'csv' => MimeType.csv,
      'json' => MimeType.json,
      'zip' => MimeType.zip,
      'png' => MimeType.png,
      'jpg' || 'jpeg' => MimeType.jpeg,
      'gif' => MimeType.gif,
      'txt' => MimeType.text,
      _ => MimeType.custom,
    };

String mimeOf(String ext) => switch (ext) {
      'pdf' => 'application/pdf',
      'docx' => 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      'xlsx' => 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      'csv' => 'text/csv',
      'json' => 'application/json',
      'zip' => 'application/zip',
      'html' => 'text/html',
      'png' => 'image/png',
      'jpg' || 'jpeg' => 'image/jpeg',
      'gif' => 'image/gif',
      'webp' => 'image/webp',
      'mp4' => 'video/mp4',
      'mov' => 'video/quicktime',
      'webm' => 'video/webm',
      _ => 'application/octet-stream',
    };

bool get _mobile => !kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS);

/// حفظ ملف: على الهاتف بنافذة «حفظ باسم»، وعلى الحاسوب والويب في مجلد التنزيلات. يعيد المسار أو null إن أُلغي.
Future<String?> saveBytes(Uint8List bytes, String baseName, String ext) async {
  final name = safeFileName(baseName);
  final type = _type(ext);
  final custom = type == MimeType.custom ? mimeOf(ext) : null;
  if (_mobile) {
    return FileSaver.instance.saveAs(name: name, bytes: bytes, ext: ext, mimeType: type, customMimeType: custom);
  }
  return FileSaver.instance.saveFile(name: name, bytes: bytes, ext: ext, mimeType: type, customMimeType: custom);
}

/// فتح الملف للعرض والطباعة. يعيد: opened (فُتح)، saved (حُفظ ليُفتح يدوياً)، cancelled، blocked (منع المتصفح النافذة).
Future<String> openBytes(Uint8List bytes, String baseName, String ext) =>
    platform.openBytesOnPlatform(bytes, safeFileName(baseName), ext, mimeOf(ext));
