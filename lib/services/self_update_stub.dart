/// المنصات التي لا تدعم التحديث الذاتي (الويب): يُفتح رابط التحديث بدلاً من ذلك.
bool get canSelfUpdate => false;

/// رابط التنزيل المناسب لهذا الجهاز.
String adjustDownloadUrl(String url) => url;

Future<void> downloadAndInstall(String url, void Function(double progress) onProgress) async {
  throw UnsupportedError('التحديث الذاتي غير متاح على هذه المنصة');
}
