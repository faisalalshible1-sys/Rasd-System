import 'dart:math';

import 'package:file_picker/file_picker.dart';
import 'package:file_saver/file_saver.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:pdf/pdf.dart' as pdfp;
import 'package:pdf/widgets.dart' as pw;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

// =====================================================================
// ملفات المستندات والتقارير: الاختيار، وضغط الصور، والرفع إلى الحاوية الخاصة «docs»، والفتح والحفظ.
// المسار: doc/<الإصدار>/<اسم عشوائي>.<امتداد>  أو  report/<التقرير>/<…>
// =====================================================================

const String docsBucket = 'docs';

/// الحد الأعلى لحجم الملف بعد الضغط (يطابق حد الحاوية).
const int maxDocBytes = 20 * 1024 * 1024;

/// الحد الأعلى لحجم الفيديو (الترحيل 22).
const int maxVideoBytes = 50 * 1024 * 1024;

const List<String> videoExts = ['mp4', 'mov', 'webm'];

/// الحد الأعلى لملفات «ملف العقد» (الترحيل 35)، دون ضغط إلا للصور.
const int maxAttachmentBytes = 50 * 1024 * 1024;

/// امتدادات مرفقات العقد كما تقبلها attachment_mime() في قاعدة البيانات.
const List<String> attachmentExts = [
  'pdf', 'jpg', 'jpeg', 'png', 'webp', 'gif', 'heic', 'doc', 'docx', 'xls', 'xlsx', 'ppt', 'pptx', 'csv', 'txt', //
  'dwg', 'dxf', 'rvt', 'zip', 'rar', '7z', 'kml', 'kmz',
];

/// الصور التي تُضغط وتُدمج في PDF (HEIC يُرفع كما هو).
const List<String> _rasterExts = ['jpg', 'png', 'webp', 'gif'];

/// الصور الأكبر من هذا البعد تُصغَّر، والأكبر من هذا الحجم تُضغط.
const int _maxSide = 2400;
const int _keepBytes = 1536 * 1024;

class PickedDoc {
  PickedDoc({required this.name, required this.bytes, required this.ext, required this.mime, this.width, this.height});

  final String name;
  final Uint8List bytes;
  final String ext;
  final String mime;
  final int? width;
  final int? height;

  bool get isImage => _rasterExts.contains(ext);
  bool get isVideo => mime.startsWith('video/');
}

/// نوع الملف من امتداده (يطابق attachment_mime() في قاعدة البيانات، والفيديو للتقارير والتصاميم).
String mimeOfExt(String ext) => switch (ext) {
      'pdf' => 'application/pdf',
      'png' => 'image/png',
      'webp' => 'image/webp',
      'gif' => 'image/gif',
      'heic' => 'image/heic',
      'mp4' => 'video/mp4',
      'mov' => 'video/quicktime',
      'webm' => 'video/webm',
      'doc' => 'application/msword',
      'docx' => 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      'xls' => 'application/vnd.ms-excel',
      'xlsx' => 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      'ppt' => 'application/vnd.ms-powerpoint',
      'pptx' => 'application/vnd.openxmlformats-officedocument.presentationml.presentation',
      'csv' => 'text/csv',
      'txt' => 'text/plain',
      'dwg' => 'image/vnd.dwg',
      'dxf' => 'image/vnd.dxf',
      'rvt' => 'application/vnd.autodesk.revit',
      'zip' => 'application/zip',
      'rar' => 'application/vnd.rar',
      '7z' => 'application/x-7z-compressed',
      'kml' => 'application/vnd.google-earth.kml+xml',
      'kmz' => 'application/vnd.google-earth.kmz',
      _ => 'image/jpeg',
    };

String extOf(String name) {
  final i = name.lastIndexOf('.');
  return i < 0 ? '' : name.substring(i + 1).toLowerCase();
}

/// نتيجة ضغط صورة في عزلة منفصلة: (البايتات، الامتداد، العرض، الارتفاع)
(Uint8List, String, int?, int?) _shrink((Uint8List, String) input) {
  final (bytes, ext) = input;
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return (bytes, ext, null, null);
  // GIF المتحرك يبقى كما هو حتى لا تضيع حركته
  if (ext == 'gif') return (bytes, ext, decoded.width, decoded.height);
  final big = decoded.width > _maxSide || decoded.height > _maxSide;
  if (!big && bytes.length <= _keepBytes) return (bytes, ext, decoded.width, decoded.height);
  final resized = big
      ? img.copyResize(decoded,
          width: decoded.width >= decoded.height ? _maxSide : null,
          height: decoded.height > decoded.width ? _maxSide : null,
          interpolation: img.Interpolation.average)
      : decoded;
  final out = Uint8List.fromList(img.encodeJpg(resized, quality: 82));
  if (out.length >= bytes.length && !big) return (bytes, ext, decoded.width, decoded.height);
  return (out, 'jpg', resized.width, resized.height);
}

/// يختار المستخدم ملفاً أو أكثر. [pdf] و[images] و[videos] تحدد الأنواع المسموحة، و[attachments] أنواع ملف العقد كلها.
/// الصور تُضغط وتُصغَّر تلقائياً؛ وما تجاوز 20 ميجابايت يُرفض برسالة، والفيديو ومرفقات العقد حتى 50 ميجابايت دون ضغط.
Future<List<PickedDoc>> pickDocFiles({bool pdf = true, bool images = true, bool videos = false, bool attachments = false}) async {
  final exts = attachments
      ? attachmentExts
      : <String>[if (pdf) 'pdf', if (images) ...['jpg', 'jpeg', 'png', 'webp', 'gif'], if (videos) ...videoExts];
  final limit = attachments ? maxAttachmentBytes : maxDocBytes;
  final limitMb = limit ~/ (1024 * 1024);
  final picked = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: exts);
  final out = <PickedDoc>[];
  for (final f in picked) {
    var ext = extOf(f.name);
    if (ext == 'jpeg') ext = 'jpg';
    if (!exts.contains(ext)) {
      throw StateError('نوع الملف «${f.name}» غير مسموح. المسموح: ${exts.where((e) => e != 'jpeg').join('، ')}');
    }
    var bytes = await f.readAsBytes();
    int? w, h;
    if (videoExts.contains(ext)) {
      if (bytes.length > maxVideoBytes) {
        throw StateError('الفيديو «${f.name}» أكبر من 50 ميجابايت. قصّره أو اضغطه بجودة أقل ثم أعد المحاولة.');
      }
      out.add(PickedDoc(name: f.name, bytes: bytes, ext: ext, mime: mimeOfExt(ext)));
      continue;
    }
    if (_rasterExts.contains(ext)) {
      final r = await compute(_shrink, (bytes, ext));
      bytes = r.$1;
      ext = r.$2;
      w = r.$3;
      h = r.$4;
    }
    if (bytes.isEmpty) {
      throw StateError('الملف «${f.name}» فارغ.');
    }
    if (bytes.length > limit) {
      throw StateError('الملف «${f.name}» أكبر من $limitMb ميجابايت. قسّمه أو اضغطه ثم أعد المحاولة.');
    }
    final base = f.name.contains('.') ? f.name.substring(0, f.name.lastIndexOf('.')) : f.name;
    out.add(PickedDoc(name: '$base.$ext', bytes: bytes, ext: ext, mime: mimeOfExt(ext), width: w, height: h));
  }
  return out;
}

/// يدمج الصور المختارة في ملف PDF واحد، صفحة لكل صورة بترتيب اختيارها (لمحاضر الاستلام والمراسلات المصوّرة).
/// تبقى الملفات الأخرى كما هي، ويوضع الـPDF مكان أول صورة.
Future<List<PickedDoc>> mergeImagesToPdf(List<PickedDoc> files, String name) async {
  final images = [for (final f in files) if (f.isImage) f];
  if (images.length < 2) return files;
  final doc = pw.Document(title: name, creator: 'منظومة رصد');
  for (final f in images) {
    final image = pw.MemoryImage(f.bytes);
    final landscape = (f.width ?? 1) > (f.height ?? 1);
    doc.addPage(pw.Page(
      pageFormat: landscape ? pdfp.PdfPageFormat.a4.landscape : pdfp.PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(18),
      build: (_) => pw.Center(child: pw.Image(image, fit: pw.BoxFit.contain)),
    ));
  }
  final bytes = await doc.save();
  if (bytes.length > maxAttachmentBytes) {
    throw StateError('ملف PDF الناتج أكبر من 50 ميجابايت. قلّل عدد الصور أو ارفعها منفصلة.');
  }
  final safe = name.replaceAll(RegExp(r'[\\/:*?"<>|]'), ' ').trim();
  final merged = PickedDoc(name: '${safe.isEmpty ? 'صور مدمجة' : safe}.pdf', bytes: bytes, ext: 'pdf', mime: 'application/pdf');
  final out = <PickedDoc>[];
  var placed = false;
  for (final f in files) {
    if (f.isImage) {
      if (!placed) out.add(merged);
      placed = true;
    } else {
      out.add(f);
    }
  }
  return out;
}

final Random _rnd = Random.secure();
const String _alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';

/// مسار جديد داخل الحاوية: [scope] هو doc أو report، و[owner] معرّف الإصدار أو التقرير.
String newDocPath(String scope, String owner, String ext) {
  final id = List.generate(22, (_) => _alphabet[_rnd.nextInt(_alphabet.length)]).join();
  return '$scope/$owner/$id.$ext';
}

/// روابط مؤقتة موقّعة (ساعة) مع ذاكرة قصيرة حتى لا يُطلب الرابط مع كل إعادة رسم.
class SignedUrls {
  SignedUrls(this.client);

  final SupabaseClient client;
  final Map<String, (String, DateTime)> _cache = {};

  Future<String> of(String path) async {
    final hit = _cache[path];
    if (hit != null && hit.$2.isAfter(DateTime.now())) return hit.$1;
    final url = await client.storage.from(docsBucket).createSignedUrl(path, 3600);
    _cache[path] = (url, DateTime.now().add(const Duration(minutes: 50)));
    return url;
  }

  /// روابط مجمّعة لعدة ملفات بطلب واحد.
  Future<Map<String, String>> many(List<String> paths) async {
    final need = paths.where((p) {
      final hit = _cache[p];
      return hit == null || !hit.$2.isAfter(DateTime.now());
    }).toList();
    if (need.isNotEmpty) {
      final exp = DateTime.now().add(const Duration(minutes: 50));
      for (final p in need) {
        _cache[p] = (await client.storage.from(docsBucket).createSignedUrl(p, 3600), exp);
      }
    }
    return {for (final p in paths) if (_cache[p] != null) p: _cache[p]!.$1};
  }

  void clear() => _cache.clear();
}

Future<void> uploadDoc(SupabaseClient client, String path, PickedDoc f) async {
  await client.storage.from(docsBucket).uploadBinary(path, f.bytes, fileOptions: FileOptions(contentType: f.mime, upsert: false));
}

/// إزالة ملفات من الحاوية بعد حذف سجلاتها (لا يوقف العملية إن فشل؛ يبقى الملف يتيماً ويُنظَّف لاحقاً).
Future<void> removeDocObjects(SupabaseClient client, List<String> paths) async {
  if (paths.isEmpty) return;
  try {
    await client.storage.from(docsBucket).remove(paths);
  } catch (_) {}
}

/// فتح الملف في عارض الجهاز (PDF في عارض المستندات، والصور في المتصفح أو عارض الصور).
Future<void> openDocExternally(String url) async {
  final uri = Uri.parse(url);
  if (kIsWeb) {
    await launchUrl(uri, webOnlyWindowName: '_blank');
  } else {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}

/// حفظ نسخة من الملف على الجهاز.
Future<String?> saveDocCopy(SupabaseClient client, String path, String name, String mime) async {
  final bytes = await client.storage.from(docsBucket).download(path);
  final ext = extOf(name);
  final base = ext.isEmpty ? name : name.substring(0, name.length - ext.length - 1);
  final type = switch (ext) {
    'pdf' => MimeType.pdf,
    'png' => MimeType.png,
    'gif' => MimeType.gif,
    'jpg' || 'jpeg' => MimeType.jpeg,
    _ => MimeType.custom,
  };
  final custom = type == MimeType.custom ? (mime.isNotEmpty ? mime : mimeOfExt(ext)) : null;
  final mobile = !kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS);
  if (mobile) {
    return FileSaver.instance.saveAs(name: base, bytes: bytes, ext: ext, mimeType: type, customMimeType: custom);
  }
  return FileSaver.instance.saveFile(name: base, bytes: bytes, ext: ext, mimeType: type, customMimeType: custom);
}
