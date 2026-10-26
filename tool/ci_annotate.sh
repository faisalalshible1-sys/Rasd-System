#!/usr/bin/env bash
# يحوّل أخطاء أمر فاشل إلى تنبيهات تظهر في صفحة التشغيل على GitHub (Annotations).
# الاستخدام: bash tool/ci_annotate.sh <ملف-المخرجات> <العنوان>
f=$1
title=$2
[ -f "$f" ] || exit 0
lines=$(grep -E "(error|warning) •|: Error:|Error: |error:|FAILURE|What went wrong|BUILD FAILED|Exception|Because .* depends on|version solving failed" "$f" | head -150)
[ -z "$lines" ] && lines=$(tail -80 "$f")
tmp=$(mktemp -d)
printf '%s\n' "$lines" | split -l 15 - "$tmp/part_"
for p in "$tmp"/part_*; do
  msg=$(sed -e 's/%/%25/g' -e 's/\r//g' "$p" | awk '{printf "%s%%0A", $0}')
  echo "::error title=$title::$msg"
done
rm -rf "$tmp"
