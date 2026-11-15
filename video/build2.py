# يبني صفحة HTML واحدة بكل مشاهد الفيديو، وكل التوقيتات مطلقة بالثواني ومحسوبة من مدد مقاطع الصوت.
import json, os, re
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
B = os.path.join(HERE, 'build')
D = json.load(open(os.path.join(HERE, 'durs2.json')))  # {"s01": {"dur":..,"lead":..,"tail":..}, ...}

ORDER = ['s01','s02','s03','e03','s04','e04','s05','e05','e05r','s06','e06','s07','e07','s08','e08','s09','e09','s10','e10','s11','e11','s12','e12','s13']
INTRO, GAP, OUTRO = 2.8, 0.7, 5.0

TEXT = {
 's01': 'في مشاريع إعادة الإعمار، لكلِّ وثيقة، ولكلِّ دينار، ولكلِّ يومٍ في الموقع… أثرٌ وحساب. ومن هنا جاءت منظومة متابعة الدورة المستندية: منصةٌ رقمية واحدة، تجمع عمل المكتب الهندسي كلَّه.',
 's02': 'تعمل على هواتف أندرويد، وأجهزة ويندوز، ومن أي متصفح، بالبيانات نفسها لحظةً بلحظة. ومن شاشةٍ رئيسية واحدة، تنطلق إلى عشرة أقسام متكاملة، لكلٍّ منها مؤشراته الحيّة.',
 's03': 'في قلبها، الدورة المستندية للعقود: ستةٌ وعشرون نموذجاً في خمس مراحل، حتى إقفال العقد. تحسب المنظومة نسبة الإنجاز، وتحدد النموذج التالي تلقائياً. أما النماذج الحساسة، فلا تتغير إلا بقرار مدير المكتب.',
 's04': 'وفي المالية: قيمة كل عقد، وأوامر التغيير، والمستخلصات ودفعاتها، والضمانات والمتبقي. وكل تعديلٍ مالي يُسجَّل بقيمته السابقة والجديدة.',
 's05': 'وفي متابعة المشاريع، تحسب المنظومة من البرنامج الزمني وقياسات التقدم مؤشرَ الأداء الزمني، وتاريخَ الإنجاز المتوقع لكل مشروع. مع سجلٍّ للمخاطر ومصفوفتها، وسجلاتٍ للمشاكل والتأخيرات والتغييرات.',
 's06': 'لوحةُ قيادةٍ بواحدٍ وعشرين مؤشراً، وتنبيهاتٌ تحدد الإجراء المطلوب. وتقييمٌ لأداء الشركات المنفِّذة بدرجةٍ مركَّبة، وتقريرٌ دوري جاهز للعرض والتصدير.',
 's07': 'وللتخطيط الاستراتيجي، تحليلُ سوات حيّ: عواملُ مرتبة بالأولوية، وتقييمٌ مرجَّح يحدد الاتجاه الاستراتيجي، وخطةُ تنفيذ تقيس المخطط مقابل الفعلي.',
 's08': 'والمستندات الفنية لكل عقد في مكانٍ واحد: المقايسات والمراسلات بملفات بي دي إف، والتصاميم بعرض صورٍ متحرك. ولكل مستندٍ مسارُ تطوير، فلا تضيع نسخةٌ سابقة أبداً.',
 's09': 'وفي الميدان، يرفع المشرف تقريراً يومياً لكل عقدٍ جارٍ: ما نُفِّذ، ومن عمل، وما عطَّل العمل، مع صور الموقع. ويتابع المدير انتظام التقارير من شبكة تغطيةٍ واضحة.',
 's10': 'وتتسع المنظومة لأقسامٍ متخصصة: الترميم والمباني التاريخية، والتخطيط وضمان الجودة والمتابعة، والسلامة المهنية، والمطابقة والاستلام. لكلٍّ منها سجلاته ومؤشراته، من أيام العمل بلا حوادث، إلى نسبة مطابقة الاختبارات.',
 's11': 'والأمان في الأساس: الصلاحيات مفروضة في قاعدة البيانات نفسها، فلا تمر عملية خارج صلاحية صاحبها. تحققٌ بخطوتين للحسابات الحساسة، ورقابةٌ لمسؤول أمن المعلومات على الأجهزة والجلسات، وسجلُّ تدقيقٍ لا يُحذف.',
 's12': 'ولمدير المكتب مساعدٌ ذكي، يجيب من بيانات المنظومة، ويقترح… ولا ينفِّذ إلا بموافقته. ودليلُ استخدامٍ مدمج، يُفتح من أي صفحة، ويتجدد مع كل إصدار.',
 's13': 'منظومة متابعة الدورة المستندية… وضوحٌ في كل قرار، وانضباطٌ في كل إجراء، ومساءلةٌ في كل خطوة. إعادةُ إعمارٍ تُدار بالبيانات.',
}

TEXT.update(json.load(open(os.path.join(HERE, 'new_texts.json'))))

# ---------- التوقيت ----------
start, t = {}, INTRO
for k in ORDER:
    start[k] = t
    t += D[k]['dur'] + GAP
TOTAL = round(t - GAP + OUTRO, 2)
scene_in = {k: start[k] - 0.45 for k in ORDER}
scene_in['s01'] = 0.0
scene_out = {k: (scene_in[ORDER[i + 1]] if i + 1 < len(ORDER) else TOTAL + 1) for i, k in enumerate(ORDER)}


def at(k, phrase, early=0.25):
    """وقت نطق عبارة داخل المقطع: تقدير بنسبة الحروف مع وزن للفواصل."""
    if k in D and 'marks' in D[k] and phrase in D[k]['marks']:
        return start[k] + D[k]['marks'][phrase] - early
    txt = TEXT[k]
    i = txt.find(phrase)
    assert i >= 0, (k, phrase)
    w = lambda s: len(re.sub(r'[ً-ْ]', '', s)) + 9 * len(re.findall(r'[،,:.…]', s))
    lead, tail = D[k].get('lead', 0.1), D[k].get('tail', 0.3)
    span = D[k]['dur'] - lead - tail
    return start[k] + lead + span * w(txt[:i]) / w(txt) - early


def end_of(k):
    return start[k] + D[k]['dur']

# ---------- أدوات HTML ----------
IMGS = {}


def img_size(name):
    if name not in IMGS:
        IMGS[name] = Image.open(os.path.join(B, 'img', name)).size
    return IMGS[name]


def A(kind, t0, d=0.8, t1=None, d1=0.6):
    s = f' data-a="{kind}" data-t0="{t0:.3f}" data-d="{d}"'
    if t1 is not None:
        s += f' data-t1="{t1:.3f}" data-d1="{d1}"'
    return s


def window(name, x, y, w, h, t0, t1, pan=(0, 0.6), zoom=(1.0, 1.035), anim='rise', chrome=True, dark=False, cls='', label=None):
    iw, ih = img_size(name)
    s = w / iw
    vh = h - (34 if chrome else 0)
    maxy = max(0, ih * s - vh)
    y0, y1 = pan[0] * maxy, pan[1] * maxy
    bar = ''
    if chrome:
        bar = (f'<div class="chrome{" dk" if dark else ""}"><i></i><i></i><i></i>'
               f'<span>{label or "منظومة رصد"}</span></div>')
    return (f'<div class="win {cls}" style="left:{x}px;top:{y}px;width:{w}px;height:{h}px"{A(anim, t0, 0.9, t1, 0.7)}>'
            f'{bar}<div class="vp" style="height:{vh}px"><img src="img/{name}" style="width:{w}px"'
            f' data-pan="{y0:.1f},{y1:.1f},{t0:.3f},{t1 + 0.7:.3f},{zoom[0]},{zoom[1]}"></div></div>')


def phone(name, x, y, w, h, t0, t1, pan=(0, 0.5), anim='rise'):
    iw, ih = img_size(name)
    s = (w - 20) / iw
    vh = h - 20
    maxy = max(0, ih * s - vh)
    return (f'<div class="phone" style="left:{x}px;top:{y}px;width:{w}px;height:{h}px"{A(anim, t0, 0.9, t1, 0.7)}>'
            f'<div class="vp" style="height:{vh}px"><img src="img/{name}" style="width:{w - 20}px"'
            f' data-pan="{pan[0] * maxy:.1f},{pan[1] * maxy:.1f},{t0:.3f},{t1 + 0.7:.3f},1,1.02"></div><b></b></div>')


ICON = {
 'cycle': 'M22 11V3h-7v3H9V3H2v8h7V8h2v10h4v3h7v-8h-7v3h-2V8h2v3z',
 'risks': 'M1 21h22L12 2 1 21zm12-3h-2v-2h2v2zm0-4h-2v-4h2v4z',
 'swot': 'M3 3v8h8V3H3zm6 6H5V5h4v4zm-6 4v8h8v-8H3zm6 6H5v-4h4v4zm4-16v8h8V3h-8zm6 6h-4V5h4v4zm-6 4v8h8v-8h-8zm6 6h-4v-4h4v4z',
 'docs': 'M10 4H4c-1.1 0-1.99.9-1.99 2L2 18c0 1.1.9 2 2 2h16c1.1 0 2-.9 2-2V8c0-1.1-.9-2-2-2h-8l-2-2z',
 'supervision': 'M19 3h-4.18C14.4 1.84 13.3 1 12 1c-1.3 0-2.4.84-2.82 2H5c-1.1 0-2 .9-2 2v14c0 1.1.9 2 2 2h14c1.1 0 2-.9 2-2V5c0-1.1-.9-2-2-2zm-7 0c.55 0 1 .45 1 1s-.45 1-1 1-1-.45-1-1 .45-1 1-1zm2 14H7v-2h7v2zm3-4H7v-2h10v2zm0-4H7V7h10v2z',
 'heritage': 'M4 10v7h3v-7H4zm6 0v7h3v-7h-3zM2 22h19v-3H2v3zm14-12v7h3v-7h-3zm-4.5-9L2 6v2h19V6l-9.5-5z',
 'planning_qa': 'M5 9.2h3V19H5zM10.6 5h2.8v14h-2.8zm5.6 8H19v6h-2.8z',
 'safety': 'M12 1L3 5v6c0 5.55 3.84 10.74 9 12 5.16-1.26 9-6.45 9-12V5l-9-4zm4 12h-3v3h-2v-3H8v-2h3V8h2v3h3v2z',
 'acceptance': 'M22 5.18L10.59 16.6l-4.24-4.24 1.41-1.41 2.83 2.83 10-10L22 5.18zm-2.21 5.04c.13.57.21 1.17.21 1.78 0 4.42-3.58 8-8 8s-8-3.58-8-8 3.58-8 8-8c1.58 0 3.04.46 4.28 1.25l1.44-1.44C16.1 2.67 14.13 2 12 2 6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10c0-1.19-.22-2.33-.6-3.39l-1.61 1.61z',
 'manual': 'M18 2H6c-1.1 0-2 .9-2 2v16c0 1.1.9 2 2 2h12c1.1 0 2-.9 2-2V4c0-1.1-.9-2-2-2zM6 4h5v8l-2.5-1.5L6 12V4z',
 'check': 'M9 16.17L4.83 12l-1.42 1.41L9 19 21 7l-1.41-1.41z',
 'phone': 'M17 1.01L7 1c-1.1 0-2 .9-2 2v18c0 1.1.9 2 2 2h10c1.1 0 2-.9 2-2V3c0-1.1-.9-1.99-2-1.99zM17 19H7V5h10v14z',
 'desktop': 'M21 2H3c-1.1 0-2 .9-2 2v12c0 1.1.9 2 2 2h7v2H8v2h8v-2h-2v-2h7c1.1 0 2-.9 2-2V4c0-1.1-.9-2-2-2zm0 14H3V4h18v12z',
 'globe': 'M11.99 2C6.47 2 2 6.48 2 12s4.47 10 9.99 10C17.52 22 22 17.52 22 12S17.52 2 11.99 2zm6.93 6h-2.95c-.32-1.25-.78-2.45-1.38-3.56 1.84.63 3.37 1.91 4.33 3.56zM12 4.04c.83 1.2 1.48 2.53 1.91 3.96h-3.82c.43-1.43 1.08-2.76 1.91-3.96zM4.26 14C4.1 13.36 4 12.69 4 12s.1-1.36.26-2h3.38c-.08.66-.14 1.32-.14 2 0 .68.06 1.34.14 2H4.26zm.82 2h2.95c.32 1.25.78 2.45 1.38 3.56-1.84-.63-3.37-1.9-4.33-3.56zm2.95-8H5.08c.96-1.66 2.49-2.93 4.33-3.56C8.81 5.55 8.35 6.75 8.03 8zM12 19.96c-.83-1.2-1.48-2.53-1.91-3.96h3.82c-.43 1.43-1.08 2.76-1.91 3.96zM14.34 14H9.66c-.09-.66-.16-1.32-.16-2 0-.68.07-1.35.16-2h4.68c.09.65.16 1.32.16 2 0 .68-.07 1.34-.16 2zm.25 5.56c.6-1.11 1.06-2.31 1.38-3.56h2.95c-.96 1.65-2.49 2.93-4.33 3.56zM16.36 14c.08-.66.14-1.32.14-2 0-.68-.06-1.34-.14-2h3.38c.16.64.26 1.31.26 2s-.1 1.36-.26 2h-3.38z',
 'shield': 'M12 1L3 5v6c0 5.55 3.84 10.74 9 12 5.16-1.26 9-6.45 9-12V5l-9-4zm-2 16l-4-4 1.41-1.41L10 14.17l6.59-6.59L18 9l-8 8z',
 'lock': 'M18 8h-1V6c0-2.76-2.24-5-5-5S7 3.24 7 6v2H6c-1.1 0-2 .9-2 2v10c0 1.1.9 2 2 2h12c1.1 0 2-.9 2-2V10c0-1.1-.9-2-2-2zm-6 9c-1.1 0-2-.9-2-2s.9-2 2-2 2 .9 2 2-.9 2-2 2zm3.1-9H8.9V6c0-1.71 1.39-3.1 3.1-3.1 1.71 0 3.1 1.39 3.1 3.1v2z',
 'eye': 'M12 4.5C7 4.5 2.73 7.61 1 12c1.73 4.39 6 7.5 11 7.5s9.27-3.11 11-7.5c-1.73-4.39-6-7.5-11-7.5zM12 17c-2.76 0-5-2.24-5-5s2.24-5 5-5 5 2.24 5 5-2.24 5-5 5zm0-8c-1.66 0-3 1.34-3 3s1.34 3 3 3 3-1.34 3-3-1.34-3-3-3z',
 'db': 'M2 20h20v-4H2v4zm2-3h2v2H4v-2zM2 4v4h20V4H2zm4 3H4V5h2v2zm-4 7h20v-4H2v4zm2-3h2v2H4v-2z',
 'doc': 'M14 2H6c-1.1 0-1.99.9-1.99 2L4 20c0 1.1.89 2 1.99 2H18c1.1 0 2-.9 2-2V8l-6-6zm2 16H8v-2h8v2zm0-4H8v-2h8v2zm-3-5V3.5L18.5 9H13z',
 'spark': 'M19 9l1.25-2.75L23 5l-2.75-1.25L19 1l-1.25 2.75L15 5l2.75 1.25L19 9zm-7.5.5L9 4 6.5 9.5 1 12l5.5 2.5L9 20l2.5-5.5L17 12l-5.5-2.5zM19 15l-1.25 2.75L15 19l2.75 1.25L19 23l1.25-2.75L23 19l-2.75-1.25L19 15z',
}


def svg(name, size=28, color='currentColor'):
    return f'<svg viewBox="0 0 24 24" width="{size}" height="{size}"><path fill="{color}" d="{ICON[name]}"/></svg>'


GOLD, GOLDD = '#CDAE5E', '#8A6A1E'
SECTIONS = [  # المفتاح، الاسم، اللون
 ('cycle', 'الدورة المستندية', '#8A6A1E'), ('risks', 'المخاطر ومتابعة المشاريع', '#B4441C'),
 ('swot', 'تحليل SWOT', '#2B62A8'), ('docs', 'المستندات الفنية', '#0F766E'),
 ('supervision', 'الإشراف', '#6D3FB2'), ('heritage', 'الترميم والمباني التاريخية', '#8A5A2B'),
 ('planning_qa', 'التخطيط وضمان الجودة', '#3949AB'), ('safety', 'السلامة المهنية', '#8A6100'),
 ('acceptance', 'المطابقة والاستلام', '#A3246B'), ('manual', 'دليل الاستخدام', '#4F5B69'),
]
SC = {k: c for k, _, c in SECTIONS}


def text_panel(k, tag, color, icon, title, sub, points=(), stats=()):
    t0 = scene_in[k] + 0.35
    out = scene_out[k] - 0.6
    h = [f'<div class="panel">']
    h.append(f'<div class="tag" style="--c:{color}"{A("up", t0, 0.7, out)}>{svg(icon, 26)}<span>{tag}</span></div>')
    h.append(f'<h1{A("up", t0 + 0.12, 0.9, out)}>{title}</h1>')
    if sub:
        h.append(f'<p class="sub"{A("up", t0 + 0.3, 0.9, out)}>{sub}</p>')
    h.append(f'<div class="rule" style="--c:{color}"{A("grow", t0 + 0.45, 1.0, out)}></div>')
    if stats:
        h.append('<div class="stats">')
        for (phrase, num, lbl) in stats:
            ts = at(k, phrase)
            h.append(f'<div class="stat"{A("up", ts, 0.7, out)}><b data-count="{num}" data-t0="{ts:.3f}" data-d="1.1">{num}</b><span>{lbl}</span></div>')
        h.append('</div>')
    h.append('<ul>')
    for (phrase, txt) in points:
        tp = at(k, phrase)
        h.append(f'<li style="--c:{color}"{A("slideR", tp, 0.7, out)}><i>{svg("check", 22, "#fff")}</i><span>{txt}</span></li>')
    h.append('</ul></div>')
    return ''.join(h)


def scene(k, inner, glow='#CDAE5E', cls=''):
    return (f'<section class="scene {cls}" id="{k}"{A("fade", scene_in[k], 0.7, scene_out[k], 0.7)}>'
            f'<div class="glow" style="--g:{glow}"></div>{inner}</section>')

# مساحة الصورة: يسار الشاشة
MX, MY, MW, MH = 60, 160, 1180, 760


def demo_note(k):
    return f'<div class="note"{A("fade", scene_in[k] + 1.0, 0.8, scene_out[k] - 0.6)}>لقطات من المنظومة · بيانات تجريبية للعرض</div>'


parts = []

# ---------- s01: الافتتاح ----------
k = 's01'
S = start[k]
op_out = start['s02'] - 0.5
words = [('لكلِّ وثيقة', 'كلُّ وثيقة'), ('ولكلِّ دينار', 'كلُّ دينار'), ('ولكلِّ يومٍ', 'كلُّ يومٍ في الموقع')]
title_t = at(k, 'ومن هنا', 0.0) + 0.2
kin = ''.join(f'<span class="kw"{A("scale", at(k, p, 0.15), 0.8, title_t - 0.6, 0.6)}>{w}</span>' + ('' if i == 2 else f'<i class="sep"{A("fade", at(k, p, 0.0) + 0.3, 0.6, title_t - 0.6, 0.6)}></i>')
              for i, (p, w) in enumerate(words))
parts.append(scene(k, f'''
 <div class="banner"{A("scale", 0.25, 1.6, S + 0.9, 0.9)}><img src="img/banner.png"></div>
 <div class="lead"{A("up", S + 0.25, 0.9, title_t - 0.6)}>في مشاريع إعادة الإعمار</div>
 <div class="kinetic">{kin}</div>
 <div class="impact"{A("up", at(k, "أثرٌ"), 0.9, title_t - 0.6)}>أثرٌ… وحساب</div>
 <div class="titlecard">
   <img class="emb" src="img/emblem.png"{A("scale", title_t - 0.3, 1.2, op_out - 0.3)}>
   <div class="eyebrow"{A("up", title_t + 0.1, 0.9, op_out - 0.3)}>مكتب الشؤون الهندسية</div>
   <h1 class="big"{A("up", title_t + 0.35, 1.1, op_out - 0.3)}>منظومة رَصْد</h1>
   <div class="goldline"{A("grow", title_t + 0.9, 1.2, op_out - 0.3)}></div>
   <p class="tag2"{A("up", at(k, "منصةٌ"), 0.9, op_out - 0.3)}>منصة رقمية واحدة تجمع عمل المكتب الهندسي كله</p>
   <p class="org"{A("fade", at(k, "منصةٌ") + 0.6, 1.0, op_out - 0.3)}>لجنة إعادة إعمار منطقة الصابري ووسط البلاد</p>
 </div>''', glow=GOLD, cls='hero'))

# ---------- s02: المنصات والأقسام العشرة ----------
k = 's02'
tA, tB, tE = scene_in[k], at(k, 'عشرة', 0.6), scene_out[k]
tiles = ''.join(
    f'<div class="tile" style="--c:{c}"{A("rise", tB + 0.35 + i * 0.13, 0.8, tE - 0.6)}><span class="ti">{svg(key, 44, "#fff")}</span><b>{name}</b></div>'
    for i, (key, name, c) in enumerate(SECTIONS))
parts.append(scene(k, text_panel(k, 'منصة واحدة', GOLDD, 'globe', 'منصة واحدة<br>على كل الأجهزة', 'بيانات مركزية تتحدث لحظياً على كل جهاز',
    points=[('أندرويد', 'هواتف أندرويد'), ('ويندوز', 'أجهزة ويندوز'), ('متصفح', 'أي متصفح ويب'), ('عشرة', 'عشرة أقسام متكاملة')]) +
    window('01_home_light_desktop.png', MX, MY + 10, 900, 600, tA + 0.2, tB, pan=(0, 0.25)) +
    phone('03_home_light_mobile.png', 930, 300, 300, 600, tA + 0.8, tB, pan=(0, 0.3)) +
    f'<div class="tiles"{A("fade", tB, 0.5, tE - 0.6)}>{tiles}</div>' + demo_note(k), glow=GOLD))

# ---------- s03: الدورة المستندية ----------
k = 's03'
tA, tE = scene_in[k], scene_out[k]
t2 = at(k, 'تحسب', 0.5)
parts.append(scene(k, text_panel(k, 'القسم الأول · الدورة المستندية', SC['cycle'], 'cycle', 'الدورة المستندية<br>للعقود', '',
    stats=[('ستةٌ', 26, 'نموذجاً'), ('خمس', 5, 'مراحل')],
    points=[('نسبة', 'نسبة إنجاز تُحسب تلقائياً'), ('وتحدد', 'تحديد النموذج التالي'), ('أما', 'النماذج الحساسة بقرار المدير')]) +
    window('30_contract_light.png', MX, MY, MW, MH, tA + 0.2, tE, pan=(0, 0.16)) +
    window('20_dashboard_page_light.png', 40, 600, 560, 330, t2, tE, pan=(0.02, 0.1), anim='slideL', cls='float') + demo_note(k), glow=SC['cycle']))

# ---------- s04: المالية ----------
k = 's04'
tA, tE = scene_in[k], scene_out[k]
tG, tP = at(k, 'والضمانات', 0.5), at(k, 'والمستخلصات', 0.4)
parts.append(scene(k, text_panel(k, 'الدورة المستندية · المالية', SC['cycle'], 'cycle', 'المالية<br>والمستخلصات', 'مالية كل عقد تُجمع لحظياً من بنوده ومستخلصاته',
    points=[('قيمة', 'قيمة العقد وأوامر التغيير'), ('والمستخلصات', 'المستخلصات ودفعاتها'), ('والضمانات', 'الضمانات والمتبقي'), ('وكل', 'كل تعديل بقيمته السابقة والجديدة')]) +
    window('10_finance_summary_light.png', MX, MY, MW, MH, tA + 0.2, tG, pan=(0, 0.3)) +
    window('15_finance_guarantees_dark.png', MX, MY, MW, MH, tG, tE, pan=(0, 0.35), dark=True, anim='fade') +
    window('34_payment_dialog_dark.png', 40, 470, 400, 470, tP, tE, pan=(0, 0.3), anim='slideL', dark=True, cls='float') + demo_note(k), glow=SC['cycle']))

# ---------- s05: متابعة المشاريع والمخاطر ----------
k = 's05'
tA, tE = scene_in[k], scene_out[k]
tR, tS = at(k, 'مع سجلٍّ', 0.5), at(k, 'مؤشرَ', 0.4)
parts.append(scene(k, text_panel(k, 'القسم الثاني · المخاطر ومتابعة المشاريع', SC['risks'], 'risks', 'متابعة المشاريع<br>والمخاطر', '',
    points=[('مؤشرَ', 'مؤشر الأداء الزمني SPI'), ('وتاريخَ', 'تاريخ الإنجاز المتوقع'), ('مع سجلٍّ', 'سجل المخاطر ومصفوفتها'), ('وسجلاتٍ', 'المشاكل والتأخيرات والتغييرات')]) +
    window('82_pm_projects_light.png', MX, MY, MW, MH, tA + 0.2, tR, pan=(0, 0.45)) +
    window('83_pm_progress_light.png', 40, 590, 580, 340, tS, tR, pan=(0.05, 0.3), anim='slideL', cls='float') +
    window('67_risk_matrix_light.png', MX, MY, MW, MH, tR, tE, pan=(0, 0.3), anim='fade') + demo_note(k), glow=SC['risks']))

# ---------- s06: لوحة القيادة ----------
k = 's06'
tA, tE = scene_in[k], scene_out[k]
tC, tT = at(k, 'وتقييمٌ', 0.4), at(k, 'وتقريرٌ', 0.4)
parts.append(scene(k, text_panel(k, 'المخاطر ومتابعة المشاريع', SC['risks'], 'risks', 'لوحة القيادة<br>والتقارير', '',
    stats=[('بواحدٍ', 21, 'مؤشراً'), ('وتنبيهاتٌ', 16, 'تنبيهاً')],
    points=[('وتقييمٌ', 'تقييم الشركات بدرجة مركّبة'), ('وتقريرٌ', 'تقرير دوري للعرض والتصدير')]) +
    window('80_pm_dashboard_light.png', MX, MY, MW, MH, tA + 0.2, tE, pan=(0, 0.35)) +
    window('88_pm_contractors_light.png', 40, 560, 600, 370, tC, tT, pan=(0, 0.2), anim='slideL', cls='float') +
    window('89_pm_report_light.png', 40, 560, 600, 370, tT, tE, pan=(0, 0.15), anim='slideL', cls='float') + demo_note(k), glow=SC['risks']))

# ---------- s07: SWOT ----------
k = 's07'
tA, tE = scene_in[k], scene_out[k]
tW, tP = at(k, 'وتقييمٌ', 0.4), at(k, 'وخطةُ', 0.4)
parts.append(scene(k, text_panel(k, 'القسم الثالث · التحليل الاستراتيجي', SC['swot'], 'swot', 'تحليل SWOT<br>الاستراتيجي', '',
    points=[('عواملُ', 'عوامل مرتبة بالأولوية'), ('وتقييمٌ', 'تقييم مرجّح ومصفوفة IE'), ('الاتجاه', 'استراتيجيات TOWS'), ('وخطةُ', 'خطة تنفيذ: المخطط والفعلي')]) +
    window('70_swot_dashboard_light.png', MX, MY, MW, MH, tA + 0.2, tE, pan=(0, 0.3)) +
    window('73_swot_weighted_light.png', 40, 540, 620, 390, tW, tP, pan=(0.2, 0.35), anim='slideL', cls='float') +
    window('75_swot_plan_light.png', 40, 540, 620, 390, tP, tE, pan=(0, 0.2), anim='slideL', cls='float') + demo_note(k), glow=SC['swot']))

# ---------- s08: المستندات الفنية ----------
k = 's08'
tA, tE = scene_in[k], scene_out[k]
tL, tD, tV = at(k, 'والمراسلات', 0.4), at(k, 'والتصاميم', 0.5), at(k, 'ولكل', 0.4)
parts.append(scene(k, text_panel(k, 'القسم الرابع · المستندات الفنية', SC['docs'], 'docs', 'المستندات<br>الفنية', 'مستندات كل عقد في مكان واحد',
    points=[('المقايسات', 'المقايسات بملفات PDF'), ('والمراسلات', 'المراسلات ومواعيد الرد'), ('والتصاميم', 'التصاميم بعرض صور متحرك'), ('ولكل', 'مسار تطوير لكل مستند')]) +
    window('a0_docs_boq_light.png', MX, MY, MW, MH, tA + 0.2, tD, pan=(0, 0.3)) +
    window('98_docs_letters_light.png', 40, 560, 600, 370, tL, tD, pan=(0, 0.2), anim='slideL', cls='float') +
    window('95_docs_designs_light.png', MX, MY, MW, MH, tD, tE, pan=(0, 0.2), anim='fade') +
    window('97_doc_design_detail_light.png', 40, 520, 560, 410, tV, tE, pan=(0.05, 0.22), anim='slideL', cls='float') + demo_note(k), glow=SC['docs']))

# ---------- s09: الإشراف ----------
k = 's09'
tA, tE = scene_in[k], scene_out[k]
tPh, tCv = at(k, 'مع صور', 0.5), at(k, 'ويتابع', 0.5)
parts.append(scene(k, text_panel(k, 'القسم الخامس · الإشراف', SC['supervision'], 'supervision', 'الإشراف<br>الميداني اليومي', '',
    points=[('يرفع', 'تقرير يومي لكل عقد جارٍ'), ('ما نُفِّذ', 'الأعمال والعمالة والمعوقات'), ('مع صور', 'صور الموقع مرفقة'), ('ويتابع', 'متابعة انتظام التقارير')]) +
    window('a2_reports_light.png', MX, MY, MW, MH, tA + 0.2, tCv, pan=(0, 0.35)) +
    phone('a3_reports_dark_mobile.png', 930, 280, 300, 620, tPh, tE, pan=(0, 0.35)) +
    window('a5_coverage_light.png', MX, MY, MW, MH, tCv, tE, pan=(0, 0.6), anim='fade') + demo_note(k), glow=SC['supervision']))

# ---------- s10: الأقسام المتخصصة ----------
k = 's10'
tA, tE = scene_in[k], scene_out[k]
cards_def = [
 ('heritage', 'الترميم والمباني التاريخية', 'الترميم', ['سجل المباني التاريخية وحالتها', 'تقييمات الحالة الإنشائية', 'أعمال الترميم المرتبطة بالعقود']),
 ('planning_qa', 'مكتب التخطيط وضمان الجودة', 'والتخطيط', ['الخطط ونسب إنجازها', 'التدقيق وحالات عدم المطابقة', 'التكليفات ومواعيدها']),
 ('safety', 'مكتب السلامة المهنية', 'والسلامة', ['أيام العمل بلا حوادث', 'جولات التفتيش ونسبة الالتزام', 'المخالفات ومعالجتها']),
 ('acceptance', 'المطابقة والاستلام', 'والمطابقة', ['محاضر الاستلام والملاحظات', 'الاختبارات ونسبة المطابقة', 'اعتماد المواد']),
]
cards = ''
for i, (key, name, phrase, items) in enumerate(cards_def):
    tc = at(k, phrase, 0.3)
    x = 60 + (1 - i % 2) * 610
    y = 165 + (i // 2) * 375
    lis = ''.join(f'<li>{it}</li>' for it in items)
    cards += (f'<div class="ucard" style="left:{x}px;top:{y}px;--c:{SC[key]}"{A("rise", tc, 0.9, tE - 0.6)}>'
              f'<div class="uh"><span class="ti">{svg(key, 40, "#fff")}</span><b>{name}</b></div><ul>{lis}</ul></div>')
parts.append(scene(k, text_panel(k, 'أقسام متخصصة', '#3949AB', 'planning_qa', 'أقسام متخصصة<br>لكل وحدة', 'لكل وحدة سجلاتها وأعضاؤها ورئيسها',
    points=[('لكلٍّ', 'سجلات عمل خاصة بكل وحدة'), ('أيام', 'مؤشرات حيّة لكل وحدة'), ('نسبة', 'متابعة المتأخر حتى الإغلاق')]) + cards, glow='#3949AB'))

# ---------- s11: الأمان والحوكمة ----------
k = 's11'
tA, tE = scene_in[k], scene_out[k]
sec = [('db', 'صلاحيات مفروضة في قاعدة البيانات', 'الصلاحيات'), ('lock', 'تحقق بخطوتين للحسابات الحساسة', 'تحققٌ'),
       ('eye', 'رقابة مسؤول أمن المعلومات', 'ورقابةٌ'), ('doc', 'سجل تدقيق لا يُحذف', 'وسجلُّ')]
pos = [(700, 150), (60, 150), (700, 700), (60, 700)]
seccards = ''.join(
    f'<div class="scard" style="left:{x}px;top:{y}px"{A("rise", at(k, ph, 0.3), 0.9, tE - 0.6)}><span class="si">{svg(ic, 34, "#fff")}</span><b>{tx}</b></div>'
    for (ic, tx, ph), (x, y) in zip(sec, pos))
parts.append(scene(k, text_panel(k, 'الأمان والحوكمة', '#1E5B46', 'shield', 'الأمان<br>في الأساس', 'كل عملية تمر عبر صلاحية صاحبها وتُسجَّل',
    points=[('فلا تمر', 'لا عملية خارج الصلاحية'), ('على الأجهزة', 'مراقبة الأجهزة والجلسات'), ('لا يُحذف', 'أثر دائم لكل تعديل')]) +
    f'''<div class="shieldwrap"{A("scale", tA + 0.3, 1.2, tE - 0.6)}>
      <svg viewBox="0 0 400 400" width="400" height="400">
        <circle cx="200" cy="200" r="190" fill="none" stroke="#CDAE5E" stroke-opacity=".35" stroke-width="2" pathLength="1" data-draw="{tA + 0.4:.3f},1.6"/>
        <circle cx="200" cy="200" r="150" fill="none" stroke="#CDAE5E" stroke-opacity=".6" stroke-width="2" stroke-dasharray="4 10"/>
      </svg>
      <div class="shield">{svg('shield', 150, '#1E5B46')}</div></div>''' + seccards, glow='#1E5B46'))

# ---------- s12: المساعد والدليل ----------
k = 's12'
tA, tE = scene_in[k], scene_out[k]
tM, tN = at(k, 'ودليلُ', 0.5), at(k, 'ويتجدد', 0.4)
parts.append(scene(k, text_panel(k, 'المعرفة والمساعدة', SC['manual'], 'spark', 'مساعد ذكي<br>ودليل مدمج', '',
    points=[('يجيب', 'يجيب من بيانات المنظومة'), ('ولا ينفِّذ', 'لا ينفّذ إلا بموافقة المدير'), ('يُفتح', 'دليل يُفتح من أي صفحة'), ('ويتجدد', 'يتجدد مع كل إصدار')]) +
    window('50_assistant_crop.png', MX, 255, MW, 548, tA + 0.2, tM, pan=(0, 0), zoom=(1.0, 1.06)) +
    window('a6_manual_light_desktop.png', MX, MY, MW, MH, tM, tE, pan=(0, 0.3), anim='fade') +
    window('a9_whats_new_light.png', 40, 560, 580, 370, tN, tE, pan=(0, 0.25), anim='slideL', cls='float') + demo_note(k), glow=SC['manual']))

# ---------- s13: الختام ----------
k = 's13'
S, E = start[k], end_of(k)
vals = [('وضوحٌ', 'وضوحٌ في كل قرار'), ('وانضباطٌ', 'انضباطٌ في كل إجراء'), ('ومساءلةٌ', 'مساءلةٌ في كل خطوة')]
vl = ''.join(f'<div class="val"{A("up", at(k, p, 0.2), 0.9)}><i></i>{v}</div>' for p, v in vals)
parts.append(scene(k, f'''
  <img class="emb2" src="img/emblem.png"{A("scale", scene_in[k] + 0.3, 1.3)}>
  <h1 class="big2"{A("up", S + 0.1, 1.1)}>منظومة رَصْد</h1>
  <div class="vals">{vl}</div>
  <div class="final"{A("up", at(k, "إعادةُ", 0.2), 1.0)}>إعادةُ إعمارٍ تُدار بالبيانات</div>
  <div class="closing"{A("fade", E + 0.4, 1.2)}>
    <img src="img/banner.png">
    <p>مكتب الشؤون الهندسية · لجنة إعادة إعمار منطقة الصابري ووسط البلاد</p>
    <p class="by">إعداد واعتماد: م. فيصل خليفة الشبلي · مدير المكتب الهندسي المكلف</p>
  </div>''', glow=GOLD, cls='hero'))

exec(open(os.path.join(HERE, 'examples.py')).read())
parts.extend(example_scenes())

# ---------- الطبقات الثابتة ----------
content_in, content_out = scene_in['s02'], scene_in['s13']
overlay = (f'<div class="brand"{A("fade", content_in + 0.3, 0.8, content_out, 0.6)}><img src="img/emblem.png">'
           f'<div><b>مكتب الشؤون الهندسية</b><span>لجنة إعادة إعمار منطقة الصابري ووسط البلاد</span></div></div>'
           f'<div id="barwrap"{A("fade", content_in, 0.8, content_out, 0.6)}><div id="bar"></div></div>')

CSS = open(os.path.join(HERE, 'style.css')).read() + open(os.path.join(HERE, 'style_ex.css')).read()
JS = open(os.path.join(HERE, 'engine.js')).read().replace('__TOTAL__', str(TOTAL)).replace('__C0__', f'{content_in:.3f}').replace('__C1__', f'{content_out:.3f}')
html = f'''<!doctype html><html lang="ar" dir="rtl"><head><meta charset="utf-8"><style>{CSS}</style></head>
<body><div id="bg"></div>{''.join(parts)}{overlay}<script>{JS}</script></body></html>'''
open(os.path.join(B, 'index.html'), 'w').write(html)
json.dump({'total': TOTAL, 'start': start, 'intro': INTRO, 'gap': GAP}, open(os.path.join(HERE, 'timeline2.json'), 'w'), indent=1)
print('TOTAL', TOTAL, 'sec =', f'{int(TOTAL // 60)}:{TOTAL % 60:05.2f}')
