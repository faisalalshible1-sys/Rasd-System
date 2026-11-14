// ملف تجريبي مؤقت للتحقق من بناء المكتبات على كل المنصات
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:image/image.dart' as img;
import 'package:pdfrx/pdfrx.dart';

Widget probePdf(String url) => PdfViewer.uri(Uri.parse(url));
Widget probePdfData(Uint8List b) => PdfViewer.data(b, sourceName: 'x.pdf');
Widget probeMd(String s) => MarkdownBody(data: s, selectable: true);

Future<Uint8List?> probePick() async {
  final r = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['pdf', 'jpg'], withData: true);
  return r?.files.first.bytes;
}

Uint8List? probeShrink(Uint8List b) {
  final i = img.decodeImage(b);
  if (i == null) return null;
  return img.encodeJpg(img.copyResize(i, width: 1600), quality: 80);
}
