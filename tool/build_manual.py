#!/usr/bin/env python3
"""يبني نسخة PDF من دليل الاستخدام من المصدر نفسه الذي يعرضه التطبيق (assets/manual/*.md).

الاستخدام:  python3 tool/build_manual.py --version 2.2.0 --out manual.pdf [--chrome /path/to/chrome]

- ترتيب الفصول وأرقامها من lib/manual.dart.
- الجداول الحية (النماذج، مستويات الخطر، المصفوفة) من config/live-settings.json كما في يوم البناء.
- محتويات بأرقام الصفحات الفعلية: مروران، الأول لمعرفة صفحة كل عنوان والثاني بالأرقام.
- يحتاج Chrome أو Chromium (أو Playwright إن كان مثبتاً) وحزمة pypdf.
"""
import argparse
import datetime
import html
import json
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

from pypdf import PdfReader

ROOT = Path(__file__).resolve().parent.parent
MANUAL = ROOT / 'assets' / 'manual'
STYLE = ROOT / 'tool' / 'manual_style.css'

ap = argparse.ArgumentParser()
ap.add_argument('--version', default='')
ap.add_argument('--out', default='manual.pdf')
ap.add_argument('--chrome', default='')
args = ap.parse_args()

# ---------------------------------------------------------------- الفصول والقيم الحية
src = (ROOT / 'lib' / 'manual.dart').read_text()
chapters = re.findall(r"ManualChapter\('(\w+)', (-?\d+), '([^']+)'\)", src)
assert chapters, 'لم يُعثر على فهرس الفصول في lib/manual.dart'
updated = re.search(r"manualUpdated = '([^']+)'", src).group(1)

live = json.loads((ROOT / 'config' / 'live-settings.json').read_text())
settings = live['settings'] if isinstance(live['settings'], dict) else {x['key']: x['value'] for x in live['settings']}
RESP = dict(re.findall(r"'([\w:]+)': '([^']+)',", src[src.index('manualResponsibleLabels'):src.index('};', src.index('manualResponsibleLabels'))]))
stages = {s['idx']: s['name'] for s in live['stages']}
forms = sorted([f for f in live['forms'] if f['active']], key=lambda f: (f['stage'], f['sort']))

rows = ['| م | النموذج | المسؤول عن التحديث (مع المدير) | حساس |', '| --- | --- | --- | --- |']
n = 0
for st in sorted(stages):
    fs = [f for f in forms if f['stage'] == st]
    if not fs:
        continue
    rows.append(f'| | **المرحلة {st + 1}: {stages[st]} ({len(fs)})** | | |')
    for f in fs:
        n += 1
        rows.append(f"| {n} | {f['name']} | {'، '.join(RESP.get(r, r) for r in f['responsible'])} | {'●' if f['sensitive'] else ''} |")
forms_table = '\n'.join(rows)

levels = sorted(settings['risk.config']['levels'], key=lambda l: l['min'])
lrows = ['| المستوى | نطاق الدرجة | الاستجابة ومسار التصعيد | دورية المراجعة |', '| --- | --- | --- | --- |']
for i in range(len(levels) - 1, -1, -1):
    l = levels[i]
    hi = levels[i + 1]['min'] - 1 if i + 1 < len(levels) else 25
    rd = l.get('review_days')
    lrows.append(f"| **{l['name']}** | {l['min']} – {hi} | {l['action']} | {f'{rd} يوماً' if rd else '—'} |")
levels_table = '\n'.join(lrows)

COLORS = ['#2E7D4F', '#7A9A2E', '#C8901A', '#D2601A', '#B4232F']


def lvl_color(score):
    k = 0
    for j, l in enumerate(levels):
        if score >= l['min']:
            k = j
    return COLORS[round(k * (len(COLORS) - 1) / max(1, len(levels) - 1))]


P = {1: 'نادر', 2: 'غير مرجح', 3: 'ممكن', 4: 'مرجح', 5: 'شبه مؤكد'}
I = {1: 'ضئيل', 2: 'طفيف', 3: 'متوسط', 4: 'كبير', 5: 'جسيم'}
matrix = ['<table class="matrix">']
for p in range(5, 0, -1):
    matrix.append(f'<tr><td class="lab">{p} {P[p]}</td>' + ''.join(
        f'<td style="background:{lvl_color(p * i)}">{p * i}</td>' for i in range(1, 6)) + '</tr>')
matrix.append('<tr><td class="lab">الاحتمالية ↑<br>التأثير ←</td>' + ''.join(f'<td class="lab">{i}<br>{I[i]}</td>' for i in range(1, 6)) + '</tr></table>')

count = len(forms)
req = count - 1
values = {
    'APP_VERSION': args.version or 'غير محدد',
    'MANUAL_UPDATED': updated,
    'FORMS_COUNT': str(count),
    'FORMS_REQ': str(req),
    'FORMS_TODO': str(req - 13),
    'FORMS_PCT10': f'{round(10 / req * 100)}%' if req > 0 else '—',
    'FORMS_TABLE': forms_table,
    'LEVELS_TABLE': levels_table,
}

# ---------------------------------------------------------------- محوّل صيغة الدليل إلى HTML


def inline(s):
    s = html.escape(s, quote=False)
    s = re.sub(r'\*\*(.+?)\*\*', lambda m: '<b>' + m.group(1).replace('*', '') + '</b>', s)
    s = re.sub(r'\*(.+?)\*', r'<i>\1</i>', s)
    s = re.sub(r'`(.+?)`', r'<span class="ui">\1</span>', s)
    return s


def cells(line):
    l = line.strip()
    if l.startswith('|'):
        l = l[1:]
    if l.endswith('|') and not l.endswith('\\|'):
        l = l[:-1]
    out, b, i = [], '', 0
    while i < len(l):
        if l[i] == '\\' and i + 1 < len(l) and l[i + 1] == '|':
            b += '|'
            i += 2
            continue
        if l[i] == '|':
            out.append(b.strip())
            b = ''
        else:
            b += l[i]
        i += 1
    out.append(b.strip())
    return out


SEP = re.compile(r'^\|?(\s*:?-{3,}:?\s*\|)+\s*:?-{0,}:?\s*\|?$')
LIST = re.compile(r'^(\s*)(-|\d+\.)\s+(.*)$')
BOX = re.compile(r'^:::(formula|example|note|warning)\s*(.*)$')
BOXCLS = {'formula': 'f', 'example': 'ex', 'note': 'nt', 'warning': 'wr'}
BOXLBL = {'formula': 'معادلة', 'example': 'مثال محلول', 'note': 'ملاحظة', 'warning': 'تنبيه'}


def convert(text, number=None):
    lines = text.split('\n')
    pos = [0]
    out = []

    def para_html(buf, eq=False):
        cls = ' class="eq"' if eq else ''
        if len(buf) == 1 and re.fullmatch(r'\*[^*].*\*', buf[0]):
            return f'<p class="lead">{inline(buf[0][1:-1])}</p>'
        return f'<p{cls}>' + '<br>'.join(inline(x) for x in buf) + '</p>'

    def parse(in_box=False, kind=''):
        res = []
        buf = []

        def flush():
            if buf:
                res.append(para_html(buf, eq=(kind == 'formula')))
                buf.clear()

        while pos[0] < len(lines):
            t = lines[pos[0]].rstrip()
            s = t.strip()
            if in_box and s == ':::':
                flush()
                pos[0] += 1
                return res
            if not s:
                flush()
                pos[0] += 1
                continue
            m = BOX.match(s)
            if m:
                flush()
                pos[0] += 1
                k, title = m.group(1), m.group(2).strip()
                inner = parse(True, k)
                res.append(f'<div class="box {BOXCLS[k]}"><div class="box-t">{inline(title or BOXLBL[k])}</div>{"".join(inner)}</div>')
                continue
            if s == '{{RISK_MATRIX}}':
                flush()
                res.append(''.join(matrix))
                pos[0] += 1
                continue
            if s.startswith('#'):
                flush()
                lv = len(s) - len(s.lstrip('#'))
                txt = s[lv:].strip()
                if lv == 1:
                    num = f'<span class="num">{number}</span>' if number and number > 0 else ''
                    res.append(f'<h1>{num}{inline(txt)}</h1>')
                else:
                    res.append(f'<h{min(lv, 3)}>{inline(txt)}</h{min(lv, 3)}>')
                pos[0] += 1
                continue
            if s.startswith('|') and pos[0] + 1 < len(lines) and SEP.match(lines[pos[0] + 1].strip()):
                flush()
                head = cells(s)
                pos[0] += 2
                body = []
                while pos[0] < len(lines) and lines[pos[0]].strip().startswith('|'):
                    c = cells(lines[pos[0]])
                    body.append([c[k] if k < len(c) else '' for k in range(len(head))])
                    pos[0] += 1
                h = ['<table class="tight">']
                if any(x.strip() for x in head):
                    h.append('<thead><tr>' + ''.join(f'<th>{inline(x)}</th>' for x in head) + '</tr></thead>')
                h.append('<tbody>')
                for r in body:
                    nonempty = [x for x in r if x.strip()]
                    if len(nonempty) == 1 and nonempty[0].startswith('**'):
                        h.append(f'<tr><td colspan="{len(head)}" class="stage">{inline(nonempty[0])}</td></tr>')
                    else:
                        h.append('<tr>' + ''.join(f'<td>{inline(x)}</td>' for x in r) + '</tr>')
                h.append('</tbody></table>')
                res.append(''.join(h))
                continue
            if LIST.match(t):
                flush()
                items = []
                while pos[0] < len(lines):
                    m = LIST.match(lines[pos[0]].rstrip())
                    if not m:
                        break
                    items.append((len(m.group(1)) // 2, m.group(2) != '-', m.group(3)))
                    pos[0] += 1
                res.append(list_html(items))
                continue
            buf.append(s)
            pos[0] += 1
        flush()
        return res

    def list_html(items):
        out_l, stack = [], []
        for depth, ordered, txt in items:
            tag = 'ol' if ordered else 'ul'
            while len(stack) > depth + 1:
                out_l.append(f'</li></{stack.pop()}>')
            if len(stack) == depth + 1:
                out_l.append('</li>')
            while len(stack) < depth + 1:
                out_l.append(f'<{tag}>')
                stack.append(tag)
            out_l.append(f'<li>{inline(txt)}')
        while stack:
            out_l.append(f'</li></{stack.pop()}>')
        return ''.join(out_l)

    out = parse()
    return ''.join(out)


def apply(text):
    return re.sub(r'\{\{([A-Z_0-9]+)\}\}', lambda m: values.get(m.group(1), m.group(0)), text)


body_parts = []
for cid, num, title in chapters:
    md = apply((MANUAL / f'{cid}.md').read_text())
    body_parts.append(f'<section class="chapter">{convert(md, int(num))}</section>')
changelog = apply((MANUAL / 'changelog.md').read_text())
body_parts.append(f'<section class="chapter">{convert(changelog)}</section>')
body = ''.join(body_parts)
assert '{{' not in body, re.findall(r'\{\{[A-Z_]+\}\}', body)

# علامات المحتويات: كل h1 وh2 يأخذ علامة بيضاء صغيرة تُقرأ من نص PDF لمعرفة صفحته
toc = []


def mark(mo):
    tag, inner = mo.group(1), mo.group(2)
    k = len(toc)
    num = re.search(r'<span class="num">(\d+)</span>', inner)
    text = re.sub(r'<[^>]+>', '', re.sub(r'<span class="num">\d+</span>', '', inner)).strip()
    toc.append((tag, (num.group(1) + '. ' if num else '') + text))
    return f'<{tag}>{inner}<span class="mk">QQ{k:03d}QQ</span></{tag}>'


body = re.sub(r'<(h1|h2)>(.*?)</\1>', mark, body, flags=re.S)

today = datetime.date.today()
version = args.version or 'غير محدد'
cover = f'''<div class="cover">
  <div class="band"></div>
  <div class="banner"><img src="banner.png"></div>
  <div class="title">
    <div class="kicker">مكتب الشؤون الهندسية</div>
    <h0>دليل استخدام منظومة<br>متابعة الدورة المستندية</h0>
    <div class="sub">الدورة المستندية · المخاطر ومتابعة المشاريع · تحليل SWOT<br>المستندات الفنية · الإشراف · الإجراءات والصلاحيات وطرق الحساب</div>
  </div>
  <div class="rule"></div>
  <div class="meta"><table>
    <tr><td>الجهة</td><td>مكتب الشؤون الهندسية · لجنة إعادة إعمار منطقة الصابري ووسط البلاد</td></tr>
    <tr><td>الإصدار</td><td>{html.escape(version)} · يطابق إصدار التطبيق</td></tr>
    <tr><td>تاريخ النسخة</td><td>{today.year}/{today.month:02d}/{today.day:02d}</td></tr>
    <tr><td>الاعتماد</td><td>م. فيصل خليفة الشبلي · مدير المكتب الهندسي المكلف</td></tr>
  </table></div>
  <img class="seal" src="emblem.png">
  <div class="foot">صندوق التنمية وإعادة إعمار ليبيا<br>لجنة إعادة إعمار منطقة الصابري ووسط البلاد · بنغازي</div>
</div>'''


def toc_html(pages):
    out = ['<section class="chapter"><h1 style="margin-bottom:10pt">المحتويات</h1><div class="toc">']
    for k, (tag, text) in enumerate(toc):
        cls = 'l1' if tag == 'h1' else 'l2'
        out.append(f'<div class="row {cls}"><span class="t">{text}</span><span class="dots"></span><span class="p">{pages.get(k, "")}</span></div>')
    out.append('</div></section>')
    return ''.join(out)


def page(pages, work):
    css = STYLE.read_text().replace('{{FOOTER}}', f'دليل استخدام منظومة متابعة الدورة المستندية · الإصدار {version}')
    for img in ('banner.png', 'emblem.png'):
        shutil.copy(ROOT / 'assets' / 'brand' / img, work / img)
    return (f'<!doctype html><html lang="ar" dir="rtl"><head><meta charset="utf-8"><title>دليل استخدام منظومة متابعة الدورة المستندية</title>'
            f'<style>{css}</style></head><body>{cover}{toc_html(pages)}{body}</body></html>')


def find_chrome():
    if args.chrome:
        return args.chrome
    for c in ('google-chrome', 'google-chrome-stable', 'chromium', 'chromium-browser'):
        p = shutil.which(c)
        if p:
            return p
    return None


def render(doc, pdf, work):
    f = work / 'manual.html'
    f.write_text(doc)
    try:
        from playwright.sync_api import sync_playwright  # المحلي: Playwright إن وُجد
        with sync_playwright() as pw:
            chrome = find_chrome()
            b = pw.chromium.launch(**({'executable_path': chrome} if args.chrome else {}), args=['--no-sandbox'])
            pg = b.new_page()
            pg.goto(f.as_uri(), wait_until='load')
            pg.evaluate('document.fonts.ready')
            pg.pdf(path=str(pdf), prefer_css_page_size=True, print_background=True, outline=True, tagged=True)
            b.close()
            return
    except ImportError:
        pass
    chrome = find_chrome()
    if not chrome:
        sys.exit('لا يوجد Chrome أو Chromium لطباعة PDF')
    subprocess.run([chrome, '--headless=new', '--no-sandbox', '--disable-gpu', '--no-pdf-header-footer',
                    '--generate-pdf-document-outline', f'--print-to-pdf={pdf}', f.as_uri()],
                   check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=600)


def find_pages(pdf):
    found = {}
    for i, p in enumerate(PdfReader(str(pdf)).pages, start=1):
        for k in re.findall(r'QQ(\d{3})QQ', (p.extract_text() or '').replace(' ', '')):
            found.setdefault(int(k), i)
    return found


with tempfile.TemporaryDirectory() as tmp:
    work = Path(tmp)
    first = work / 'pass1.pdf'
    render(page({k: '00' for k in range(len(toc))}, work), first, work)
    pages = find_pages(first)
    missing = [toc[k][1] for k in range(len(toc)) if k not in pages]
    if missing:
        print('::warning::عناوين لم تُعثر على صفحاتها:', missing, file=sys.stderr)
    out = Path(args.out).resolve()
    render(page(pages, work), out, work)
    total = len(PdfReader(str(out)).pages)
print(f'دليل الاستخدام {version}: {total} صفحة · {len(toc)} عنواناً في المحتويات · {count} نموذجاً · {out}')
