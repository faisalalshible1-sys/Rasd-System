#!/usr/bin/env bash
# يبني برنامج تثبيت ويندوز من مخرجات flutter build windows.
# الاستخدام (على ويندوز، داخل Git Bash): bash tool/build_windows_installer.sh <VERSION>
# الناتج: dist/dc-app-setup.exe
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION=${1:-1.0.0}
ISCC="/c/Program Files (x86)/Inno Setup 6/ISCC.exe"
if [ ! -f "$ISCC" ]; then
  echo "تثبيت Inno Setup..."
  choco install innosetup -y --no-progress >/dev/null
fi
mkdir -p dist
# منع Git Bash من تحويل المفاتيح /D... إلى مسارات ملفات
export MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL="*"
"$ISCC" /Q \
  "/DAppVersion=$VERSION" \
  "/DSourceDir=$(cygpath -w "$PWD/build/windows/x64/runner/Release")" \
  "/DOutputDir=$(cygpath -w "$PWD/dist")" \
  "/DIconFile=$(cygpath -w "$PWD/windows/runner/resources/app_icon.ico")" \
  "$(cygpath -w "$PWD/tool/windows/installer.iss")"
ls -la dist/dc-app-setup.exe
