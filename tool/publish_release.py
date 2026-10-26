#!/usr/bin/env python3
"""نشر إصدار جديد: رفع ملفات أندرويد وويندوز إلى Supabase Storage، وتسجيل الإصدار في جدول app_releases،
ثم حذف الملفات الأقدم (يُحتفظ بآخر ثلاثة إصدارات لكل منصة).

يُشغَّل من سير العمل release على GitHub. المتغيرات:
  SUPABASE_URL, SUPABASE_SERVICE_KEY   عنوان المشروع ومفتاح الخدمة (سرّ في GitHub فقط)
  VERSION, BUILD, NOTES, MANDATORY      بيانات الإصدار
  APK, WINDOWS_SETUP                    ملف أندرويد وبرنامج تثبيت ويندوز
  WEB_URL                               رابط نسخة الويب بعد نشرها (اختياري)
"""
import json
import os
import sys
import urllib.error
import urllib.request

KEEP = 3


def env(name, default=None):
    v = os.environ.get(name, default)
    if v is None or v == "":
        if default is None:
            print(f"::error title=نشر الإصدار::المتغير {name} غير موجود")
            sys.exit(1)
    return v


URL = env("SUPABASE_URL").rstrip("/")
KEY = env("SUPABASE_SERVICE_KEY")
VERSION = env("VERSION")
BUILD = int(env("BUILD"))
NOTES = os.environ.get("NOTES", "").strip()
MANDATORY = os.environ.get("MANDATORY", "false").lower() == "true"
APK = os.environ.get("APK", "")
WIN = os.environ.get("WINDOWS_SETUP", "")
WEB_URL = os.environ.get("WEB_URL", "").strip()

if KEY.startswith("sb_publishable_"):
    print("::error title=نشر الإصدار::SUPABASE_SERVICE_KEY هو المفتاح العام. ضع المفتاح السري (sb_secret_...) في هذا السرّ.")
    sys.exit(1)


def headers(extra=None):
    h = {"apikey": KEY}
    if KEY.startswith("eyJ"):  # مفتاح service_role القديم بصيغة JWT
        h["Authorization"] = f"Bearer {KEY}"
    if extra:
        h.update(extra)
    return h


def request(method, path, body=None, extra=None, raw=None):
    data = raw if raw is not None else (json.dumps(body).encode() if body is not None else None)
    h = headers(extra)
    if raw is None and body is not None:
        h["Content-Type"] = "application/json"
    req = urllib.request.Request(URL + path, data=data, method=method, headers=h)
    try:
        with urllib.request.urlopen(req, timeout=600) as r:
            txt = r.read().decode() or "null"
            return r.status, json.loads(txt) if txt.strip().startswith(("{", "[")) else txt
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode()


def ensure_bucket():
    code, res = request("POST", "/storage/v1/bucket", {"id": "releases", "name": "releases", "public": True})
    if code in (200, 201):
        print("أُنشئت حاوية الإصدارات releases")
    elif "already exists" in str(res) or "Duplicate" in str(res) or code == 409:
        pass
    else:
        print(f"::warning title=حاوية الإصدارات::{code} {res}")


def upload(local, remote, ctype):
    with open(local, "rb") as f:
        blob = f.read()
    code, res = request("POST", f"/storage/v1/object/releases/{remote}", raw=blob,
                        extra={"Content-Type": ctype, "x-upsert": "true", "Cache-Control": "max-age=300"})
    if code not in (200, 201):
        print(f"::error title=رفع {remote}::HTTP {code}: {res}")
        sys.exit(1)
    url = f"{URL}/storage/v1/object/public/releases/{remote}"
    print(f"رُفع {remote} ({len(blob) / 1e6:.1f} MB)")
    return url


def cleanup(prefix):
    code, res = request("POST", "/storage/v1/object/list/releases",
                        {"prefix": prefix, "limit": 100, "sortBy": {"column": "created_at", "order": "desc"}})
    if code != 200 or not isinstance(res, list):
        return
    files = [o["name"] for o in res if o.get("name") and not o["name"].startswith("latest")]
    old = [f"{prefix}/{n}" for n in files[KEEP:]]
    if old:
        request("DELETE", "/storage/v1/object/releases", {"prefixes": old})
        print(f"حُذفت ملفات قديمة: {', '.join(old)}")


def main():
    ensure_bucket()
    rows = []
    if APK and os.path.exists(APK):
        url = upload(APK, f"android/dc-app-{VERSION}.apk", "application/vnd.android.package-archive")
        upload(APK, "android/latest.apk", "application/vnd.android.package-archive")
        rows.append(("android", url))
    if WIN and os.path.exists(WIN):
        url = upload(WIN, f"windows/dc-app-setup-{VERSION}.exe", "application/octet-stream")
        upload(WIN, "windows/latest-setup.exe", "application/octet-stream")
        rows.append(("windows", url))
    if WEB_URL:
        rows.append(("web", WEB_URL))
    if not rows:
        print("::error title=نشر الإصدار::لا توجد ملفات لنشرها")
        sys.exit(1)

    body = [{"platform": p, "version": VERSION, "build": BUILD, "url": u, "notes": NOTES, "mandatory": MANDATORY}
            for p, u in rows]
    code, res = request("POST", "/rest/v1/app_releases", body, extra={"Prefer": "return=minimal"})
    if code not in (200, 201, 204):
        hint = " — شغّل ملف supabase/migrations/20261026000004_releases.sql في Supabase" if "app_releases" in str(res) else ""
        print(f"::error title=تسجيل الإصدار::HTTP {code}: {res}{hint}")
        sys.exit(1)

    cleanup("android")
    cleanup("windows")

    lines = [f"## الإصدار {VERSION}{' (إلزامي)' if MANDATORY else ''}", "", NOTES or "—", ""]
    lines += [f"- **{p}**: {u}" for p, u in rows]
    summary = "\n".join(lines)
    print(summary)
    path = os.environ.get("GITHUB_STEP_SUMMARY")
    if path:
        with open(path, "a", encoding="utf-8") as f:
            f.write(summary + "\n")
    for p, u in rows:
        print(f"::notice title=الإصدار {VERSION} — {p}::{u}")


if __name__ == "__main__":
    main()
