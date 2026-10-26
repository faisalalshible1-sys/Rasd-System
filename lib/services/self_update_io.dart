import 'dart:io';

/// التحديث الذاتي متاح على ويندوز: يُنزَّل برنامج التثبيت ويُشغَّل بصمت ثم يُغلق التطبيق،
/// فيثبّت الإصدار الجديد فوق القديم ويعيد تشغيل البرنامج.
bool get canSelfUpdate => Platform.isWindows;

/// رابط التنزيل المناسب لهذا الجهاز: الهواتف القديمة بمعالج 32 بت تحتاج نسخة arm32.
String adjustDownloadUrl(String url) {
  if (Platform.isAndroid && Platform.version.contains('"android_arm"') && url.contains('-arm64.apk')) {
    return url.replaceFirst('-arm64.apk', '-arm32.apk');
  }
  return url;
}

Future<void> downloadAndInstall(String url, void Function(double progress) onProgress) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 30);
  try {
    final request = await client.getUrl(Uri.parse(url));
    final response = await request.close();
    if (response.statusCode != 200) {
      throw HttpException('تعذّر تنزيل التحديث (HTTP ${response.statusCode})');
    }
    final total = response.contentLength;
    final sep = Platform.pathSeparator;
    final file = File('${Directory.systemTemp.path}${sep}dc-app-setup-${DateTime.now().millisecondsSinceEpoch}.exe');
    final sink = file.openWrite();
    var received = 0;
    await for (final chunk in response) {
      sink.add(chunk);
      received += chunk.length;
      if (total > 0) onProgress(received / total);
    }
    await sink.flush();
    await sink.close();
    if (total > 0 && received < total) {
      throw const HttpException('انقطع التنزيل قبل اكتماله. أعد المحاولة.');
    }
    await Process.start(
      file.path,
      ['/SILENT', '/SUPPRESSMSGBOXES', '/NORESTART', '/CLOSEAPPLICATIONS'],
      mode: ProcessStartMode.detached,
    );
    exit(0);
  } finally {
    client.close(force: true);
  }
}
