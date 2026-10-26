#!/usr/bin/env bash
# توقيع ملف APK بمفتاح المؤسسة الثابت، حتى تُثبَّت التحديثات فوق النسخ السابقة.
# الاستخدام: ANDROID_SIGNING_PASSWORD=... bash tool/sign_apk.sh <input.apk> <output.apk>
# المفتاح محفوظ مشفّراً في tool/signing/release.p12.enc، وكلمة سرّه في أسرار المستودع فقط.
set -euo pipefail
in=$1
out=$2
if [ -z "${ANDROID_SIGNING_PASSWORD:-}" ]; then
  echo "::warning title=توقيع أندرويد::السرّ ANDROID_SIGNING_PASSWORD غير موجود. النسخة موقعة بمفتاح مؤقت، ولن تُثبَّت فوق النسخ السابقة."
  cp "$in" "$out"
  exit 0
fi
dir=$(cd "$(dirname "$0")" && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
openssl enc -d -aes-256-cbc -pbkdf2 -iter 200000 \
  -in "$dir/signing/release.p12.enc" -out "$tmp/release.p12" -pass env:ANDROID_SIGNING_PASSWORD
bt=$(ls -d "${ANDROID_HOME:-$ANDROID_SDK_ROOT}"/build-tools/* | sort -V | tail -1)
"$bt/apksigner" sign \
  --ks "$tmp/release.p12" --ks-type PKCS12 --ks-key-alias dcapp \
  --ks-pass env:ANDROID_SIGNING_PASSWORD --key-pass env:ANDROID_SIGNING_PASSWORD \
  --out "$out" "$in"
"$bt/apksigner" verify --print-certs "$out" | grep -E "certificate DN|SHA-256" | head -2
echo "تم التوقيع بمفتاح المؤسسة: $out"
