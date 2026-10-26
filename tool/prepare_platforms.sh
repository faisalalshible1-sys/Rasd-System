#!/usr/bin/env bash
# يُنشئ مجلدات المنصات (أندرويد، آيفون، ويندوز، الويب) إن لم تكن موجودة،
# ويضبط اسم التطبيق وإذن الإنترنت لأندرويد.
# يُشغَّل مرة واحدة بعد تنزيل المشروع:  bash tool/prepare_platforms.sh
set -euo pipefail
cd "$(dirname "$0")/.."

APP_NAME="الدورة المستندية"

missing=""
for p in android ios web windows; do
  [ -d "$p" ] || missing="$missing,$p"
done
if [ -n "$missing" ]; then
  flutter create --project-name dc_app --org ly.sabri.engineering --platforms="${missing#,}" .
fi
# حذف ملف الاختبار النموذجي الذي يضيفه flutter create (يشير إلى MyApp غير الموجود)
if [ -f test/widget_test.dart ] && grep -q "MyApp" test/widget_test.dart; then
  rm -f test/widget_test.dart
fi

# أندرويد: إذن الإنترنت لنسخة الإصدار، واسم التطبيق
M=android/app/src/main/AndroidManifest.xml
if [ -f "$M" ]; then
  grep -q 'android.permission.INTERNET' "$M" || \
    perl -0pi -e 's/<application/<uses-permission android:name="android.permission.INTERNET"\/>\n    <application/' "$M"
  perl -pi -e "s/android:label=\"[^\"]*\"/android:label=\"$APP_NAME\"/" "$M"
  # فتح روابط التحديث في المتصفح (أندرويد 11 وما بعده)
  grep -q 'android:scheme="https"' "$M" || \
    perl -0pi -e 's#</manifest>#    <queries>\n        <intent>\n            <action android:name="android.intent.action.VIEW" />\n            <data android:scheme="https" />\n        </intent>\n    </queries>\n</manifest>#' "$M"
fi

# آيفون: اسم التطبيق على الشاشة
P=ios/Runner/Info.plist
if [ -f "$P" ]; then
  perl -0pi -e "s/(<key>CFBundleDisplayName<\/key>\s*<string>)[^<]*(<\/string>)/\${1}$APP_NAME\${2}/" "$P"
fi

# الويب: العنوان واتجاه الصفحة
W=web/index.html
if [ -f "$W" ]; then
  perl -pi -e "s/<title>[^<]*<\/title>/<title>$APP_NAME<\/title>/" "$W"
  perl -pi -e 's/<html>/<html lang="ar" dir="rtl">/' "$W"
fi
J=web/manifest.json
if [ -f "$J" ]; then
  perl -pi -e "s/\"name\": \"[^\"]*\"/\"name\": \"$APP_NAME\"/; s/\"short_name\": \"[^\"]*\"/\"short_name\": \"$APP_NAME\"/" "$J"
  perl -pi -e 's/"theme_color": "[^"]*"/"theme_color": "#8A6A1E"/; s/"background_color": "[^"]*"/"background_color": "#FFFFFF"/' "$J"
fi

# أيقونة التطبيق من ختم المؤسسة لكل المنصات
if command -v flutter >/dev/null 2>&1; then
  flutter pub get >/dev/null
  dart run flutter_launcher_icons
fi

echo "تم تجهيز المنصات: android ios web windows"
