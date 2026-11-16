// موارد الطباعة المشتركة بين المحركات: الشعار المختار، وخطوط PDF.

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;

import 'model.dart';

final Map<String, Uint8List> _bytes = {};

Future<Uint8List> assetBytes(String path) async {
  final hit = _bytes[path];
  if (hit != null) return hit;
  final d = await rootBundle.load(path);
  final b = d.buffer.asUint8List(d.offsetInBytes, d.lengthInBytes);
  _bytes[path] = b;
  return b;
}

/// صورة الشعار حسب القالب (PNG أو JPEG)، أو null دون شعار.
Future<Uint8List?> logoBytes(PrintConfig c) async {
  switch (c.logo) {
    case 'none':
      return null;
    case 'banner':
      return assetBytes('assets/brand/banner.png');
    case 'custom':
      if (c.customLogo.isEmpty) return assetBytes('assets/brand/emblem.png');
      try {
        return base64Decode(c.customLogo);
      } catch (_) {
        return assetBytes('assets/brand/emblem.png');
      }
    default:
      return assetBytes('assets/brand/emblem.png');
  }
}

/// نوع الصورة من بايتاتها الأولى.
String imageExt(Uint8List b) =>
    b.length > 3 && b[0] == 0xFF && b[1] == 0xD8 ? 'jpeg' : 'png';

/// أبعاد صورة PNG أو JPEG (للمحافظة على نسبتها في Word).
(int, int)? imageSize(Uint8List b) {
  if (b.length > 24 && b[0] == 0x89 && b[1] == 0x50) {
    int u32(int o) => (b[o] << 24) | (b[o + 1] << 16) | (b[o + 2] << 8) | b[o + 3];
    return (u32(16), u32(20));
  }
  if (b.length > 4 && b[0] == 0xFF && b[1] == 0xD8) {
    var i = 2;
    while (i + 9 < b.length) {
      if (b[i] != 0xFF) {
        i++;
        continue;
      }
      final marker = b[i + 1];
      final len = (b[i + 2] << 8) | b[i + 3];
      if (marker >= 0xC0 && marker <= 0xC3) {
        return ((b[i + 7] << 8) | b[i + 8], (b[i + 5] << 8) | b[i + 6]);
      }
      i += 2 + len;
    }
  }
  return null;
}

/// ملفات الخط لكل اختيار: (العادي، العريض). الخط اللاتيني الاحتياطي ArLatSans دائماً.
(String, String) fontFiles(String font) => switch (font) {
      'kufi' => ('assets/fonts/NotoKufiArabic-Regular.ttf', 'assets/fonts/NotoKufiArabic-Bold.ttf'),
      'sans' => ('assets/fonts/ArLatSans-Regular.ttf', 'assets/fonts/ArLatSans-Bold.ttf'),
      _ => ('assets/fonts/NotoNaskhArabic-Regular.ttf', 'assets/fonts/NotoNaskhArabic-Bold.ttf'),
    };

const String latinRegular = 'assets/fonts/ArLatSans-Regular.ttf';
const String latinBold = 'assets/fonts/ArLatSans-Bold.ttf';
