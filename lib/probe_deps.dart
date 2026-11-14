// ملف تجريبي مؤقت للتحقق من بناء المكتبات على كل المنصات
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:image/image.dart' as img;

Widget probeMd(String s) => MarkdownBody(data: s, selectable: true);

Future<Uint8List?> probePick() async {
  final r = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: ['pdf', 'jpg']);
  if (r.isEmpty) return null;
  final f = r.first;
  final n = f.name;
  final len = await f.length();
  return n.isEmpty || len == 0 ? null : await f.readAsBytes();
}

Uint8List? probeShrink(Uint8List b) {
  final i = img.decodeImage(b);
  if (i == null) return null;
  return img.encodeJpg(img.copyResize(i, width: 1600), quality: 80);
}
