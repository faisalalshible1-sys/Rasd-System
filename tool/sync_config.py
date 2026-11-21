#!/usr/bin/env python3
"""مزامنة الإعدادات الحية والأفكار من Supabase إلى المستودع.

يُشغَّل من سير العمل sync كل ثلاث ساعات (أو يدوياً):
  - يحفظ الإعدادات والمراحل والنماذج والأقسام والحقول في config/live-settings.json
  - يحوّل كل فكرة جديدة إلى Issue في المستودع ويضع رابطها في التطبيق، ويغلق مهمة الفكرة المنفّذة أو المستبعدة
  - يحفظ قائمة الأفكار في config/ideas.json
المتغيرات: SUPABASE_URL, SUPABASE_SERVICE_KEY, GH_TOKEN, REPO
"""
import json
import os
import sys
import urllib.error
import urllib.request

URL = os.environ.get("SUPABASE_URL", "").rstrip("/")
KEY = os.environ.get("SUPABASE_SERVICE_KEY", "")
GH = os.environ.get("GH_TOKEN", "")
REPO = os.environ.get("REPO", "")

CATEGORY = {"feature": "ميزة جديدة", "design": "التصميم والشكل", "data": "البيانات والتقارير",
            "security": "الأمان", "bug": "خلل يحتاج إصلاحاً", "other": "أخرى"}
PRIORITY = {"low": "منخفضة", "normal": "عادية", "high": "عالية", "urgent": "عاجلة"}

if not URL or not KEY:
    print("::notice title=المزامنة::السرّان SUPABASE_URL و SUPABASE_SERVICE_KEY غير موجودين؛ لم تتم المزامنة.")
    sys.exit(0)
if KEY.startswith("sb_publishable_"):
    print("::error title=المزامنة::SUPABASE_SERVICE_KEY هو المفتاح العام. ضع المفتاح السري (sb_secret_...).")
    sys.exit(1)


def _call(url, method, body, headers):
    data = json.dumps(body).encode() if body is not None else None
    if body is not None:
        headers = {**headers, "Content-Type": "application/json"}
    req = urllib.request.Request(url, data=data, method=method, headers=headers)
    try:
        with urllib.request.urlopen(req, timeout=120) as r:
            txt = r.read().decode() or "null"
            return r.status, json.loads(txt) if txt.strip()[:1] in "{[" else txt
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode()


def sb(method, path, body=None, extra=None):
    h = {"apikey": KEY}
    if KEY.startswith("eyJ"):
        h["Authorization"] = f"Bearer {KEY}"
    if extra:
        h.update(extra)
    return _call(URL + path, method, body, h)


def gh(method, path, body=None):
    h = {"Authorization": f"Bearer {GH}", "Accept": "application/vnd.github+json", "X-GitHub-Api-Version": "2022-11-28"}
    return _call("https://api.github.com" + path, method, body, h)


def write(path, obj):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        f.write(json.dumps(obj, ensure_ascii=False, indent=2, sort_keys=True) + "\n")


# 1. الإعدادات والتعريفات
code, cfg = sb("POST", "/rest/v1/rpc/export_config", {})
if code != 200 or not isinstance(cfg, dict):
    if "export_config" in str(cfg):
        print("::notice title=المزامنة::قاعدة البيانات لم تُحدَّث للإصدار الثاني بعد (ملف 20261027000006_platform_v2.sql).")
        sys.exit(0)
    print(f"::error title=المزامنة::تعذّر قراءة الإعدادات: {code} {cfg}")
    sys.exit(1)
cfg.pop("exported_at", None)
# صيغ الأرقام الإشارية (الترحيل 23) لجدولها الحي في نسخة PDF من الدليل
code, refs = sb("GET", "/rest/v1/ref_schemes?select=key,name,pattern,reset,pad,start_at,codes,active,per_section&order=key.asc")
if code == 200 and isinstance(refs, list):
    cfg["ref_schemes"] = refs
write("config/live-settings.json", cfg)
print(f"الإعدادات: {len(cfg.get('settings', {}))} إعداداً، {len(cfg.get('forms', []))} نموذجاً، {len(cfg.get('custom_fields', []))} حقلاً")

# 2. الأفكار ← مهام في المستودع
code, ideas = sb("GET", "/rest/v1/ideas?select=id,title,body,category,priority,status,response,created_at,updated_at,github_issue,github_url&order=created_at.asc")
if code != 200 or not isinstance(ideas, list):
    print(f"::warning title=الأفكار::تعذّر قراءة الأفكار: {code} {ideas}")
    ideas = []

created = closed = 0
for idea in ideas:
    if not GH or not REPO:
        break
    status = idea.get("status")
    num = idea.get("github_issue")
    if not num and status not in ("done", "rejected"):
        body = (idea.get("body") or "").strip()
        text = (body + "\n\n---\n" if body else "") + \
            f"- النوع: {CATEGORY.get(idea.get('category'), idea.get('category'))}\n" \
            f"- الأولوية: {PRIORITY.get(idea.get('priority'), idea.get('priority'))}\n" \
            f"- تاريخ الإرسال: {(idea.get('created_at') or '')[:10]}\n" \
            f"- معرّف الفكرة: `{idea['id']}`\n\n" \
            "_أُنشئت تلقائياً من قسم «الأفكار والتطوير» في التطبيق._"
        c, issue = gh("POST", f"/repos/{REPO}/issues", {"title": f"[فكرة] {idea.get('title', '')}", "body": text})
        if c == 201 and isinstance(issue, dict):
            idea["github_issue"] = issue["number"]
            idea["github_url"] = issue["html_url"]
            sb("PATCH", f"/rest/v1/ideas?id=eq.{idea['id']}",
               {"github_issue": issue["number"], "github_url": issue["html_url"]}, {"Prefer": "return=minimal"})
            created += 1
        else:
            print(f"::warning title=الأفكار::تعذّر إنشاء مهمة للفكرة {idea.get('title')}: {c} {issue}")
    elif num and status in ("done", "rejected"):
        c, issue = gh("GET", f"/repos/{REPO}/issues/{num}")
        if c == 200 and isinstance(issue, dict) and issue.get("state") == "open":
            reason = "completed" if status == "done" else "not_planned"
            gh("PATCH", f"/repos/{REPO}/issues/{num}", {"state": "closed", "state_reason": reason})
            closed += 1

write("config/ideas.json", ideas)
print(f"الأفكار: {len(ideas)} فكرة، أُنشئت {created} مهمة وأُغلقت {closed}")
