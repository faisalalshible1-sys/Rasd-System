# مشاهد «مثال تطبيقي» لنسخة «رصد»: لوحة حساب على اليمين ورسم توضيحي على اليسار.
# كل الأرقام من الأمثلة المحلولة في دليل الاستخدام (الفصول 05 و07 و09 و12 و14 و16 و18 و19–22).
# يُستورد من build2.py بعد تعريف الأدوات (A، at، scene، svg، SC، scene_in، scene_out).

import re as _re


def P(x):
    # عزل الأرقام ذات النسبة المئوية أو الإشارة السالبة باتجاه LTR حتى تُعرض «40.9%» و«−15.9» صحيحة داخل النص العربي
    return _re.sub(r'[−-]?\d[\d.,]*%|[−-]\d[\d.,]*', lambda m: '\u2066' + m.group(0) + '\u2069', x)


def board(k, color, icon, title, rows):
    t0 = scene_in[k] + 0.35
    out = scene_out[k] - 0.6
    h = [f'<div class="panel ex">',
         f'<div class="tag" style="--c:{GOLDD}"{A("up", t0, 0.7, out)}>{svg("spark", 24)}<span>مثال تطبيقي</span></div>',
         f'<h1{A("up", t0 + 0.12, 0.9, out)}>{title}</h1>',
         f'<div class="rule" style="--c:{color}"{A("grow", t0 + 0.4, 1.0, out)}></div>',
         '<div class="board">']
    for (phrase, label, value, *res) in rows:
        tr = at(k, phrase)
        cls = ' res' if res else ''
        h.append(f'<div class="brow{cls}" style="--c:{color}"{A("slideR", tr, 0.7, out)}><span>{P(label)}</span><b>{P(value)}</b></div>')
    h.append('</div></div>')
    return ''.join(h)


def count(n, t0, d=1.2, dec=0, sep=False, suffix=''):
    s = f'{n:,.{dec}f}' if sep else f'{n:.{dec}f}'
    return f'<b data-count="{n}" data-t0="{t0:.3f}" data-d="{d}" data-dec="{dec}" data-sep="{1 if sep else 0}" data-suf="{suffix}">{s}{suffix}</b>'


def card(inner, x, y, w, h, t0, t1, anim='rise', cls=''):
    return f'<div class="vcard {cls}" style="left:{x}px;top:{y}px;width:{w}px;height:{h}px"{A(anim, t0, 0.9, t1, 0.7)}>{inner}</div>'


def bar(label, pct, color, t0, t1, value=None, marker=None, marker_label=''):
    marker_label = P(marker_label)
    mk = ''
    if marker is not None:
        mk = (f'<i class="mk" style="right:{marker}%"{A("fade", t0 + 0.6, 0.6, t1)}></i>'
              f'<em class="mkl" style="right:{marker}%"{A("fade", t0 + 0.6, 0.6, t1)}>{marker_label}</em>')
    value = P(value) if value else ''
    return (f'<div class="hbar"{A("up", t0, 0.6, t1)}><div class="hl"><span>{P(label)}</span>{value}</div>'
            f'<div class="track"><div class="fill" style="width:{pct}%;background:{color}"{A("grow", t0 + 0.2, 1.3, t1)}></div>{mk}</div></div>')


def example_scenes():
    out = []
    VX, VY, VW, VH = 60, 170, 1180, 750   # منطقة الرسم يسار الشاشة

    # e03 — نسبة الإنجاز: 25 مطلوبة، 10 مكتملة، 3 قيد الإجراء، 12 لم تبدأ
    k = 'e03'; c = SC['cycle']; t1 = scene_out[k] - 0.6
    tr = at(k, 'نسبة', 0.3)
    ring = (f'<svg viewBox="0 0 300 300" class="ring"><circle cx="150" cy="150" r="120" stroke="#EDE6D3" stroke-width="26" fill="none"/>'
            f'<circle cx="150" cy="150" r="120" stroke="{c}" stroke-width="26" fill="none" stroke-linecap="round" pathLength="1" transform="rotate(-90 150 150)" data-draw="{tr:.3f},1.4,0.4"/></svg>'
            f'<div class="ringv">{count(40, tr, 1.4, suffix="%")}<span>10 من 25 نموذجاً</span></div>')
    seg = (f'<div class="stack"{A("up", at(k, "وما بقي", 0.3), 0.8, t1)}>'
           f'<i style="flex:10;background:#2E7D4F"></i><i style="flex:3;background:#D49B1F"></i><i style="flex:12;background:#C9C3B6"></i></div>'
           f'<div class="legend"{A("up", at(k, "وما بقي", 0.1), 0.8, t1)}><span><i style="background:#2E7D4F"></i>مكتملة 10</span>'
           f'<span><i style="background:#D49B1F"></i>قيد الإجراء 3</span><span><i style="background:#C9C3B6"></i>لم تبدأ 12</span><span><i style="background:#fff;border:2px dashed #B9B2A2"></i>لا ينطبق 1</span></div>')
    out.append(scene(k, board(k, c, 'cycle', 'نسبة الإنجاز<br>تُحسب وحدها', [
        ('عقدٌ', 'النماذج المطلوبة', '26 − 1 لا ينطبق = 25'), ('عشرة', 'المكتملة', '10'),
        ('نسبة', 'نسبة الإنجاز', '10 ÷ 25 = 40%', 1), ('وما بقي', 'المتبقي', '15 نموذجاً، منها 3 قيد الإجراء')]) +
        card(f'<div class="ringwrap">{ring}</div>{seg}', VX + 90, VY + 20, 1000, 700, scene_in[k] + 0.3, t1), glow=c))

    # e04 — المالية: 1,000,000 + 80,000 − 30,000 = 1,050,000
    k = 'e04'; c = SC['cycle']; t1 = scene_out[k] - 0.6
    ta, tb, tc, td, te = at(k, 'بمليون'), at(k, 'زيادةٌ'), at(k, 'ونقصٌ'), at(k, 'فتصبح'), at(k, 'ويظهر')
    H = 300 / 1050000
    def col(lbl, val, h, bottom, color, t, sign=''):
        return (f'<div class="wcol"{A("up", t, 0.7, t1)}><div class="wv">{sign}{val:,}</div>'
                f'<div class="wbox"><i style="height:{h:.0f}px;bottom:{bottom:.0f}px;background:{color}"></i></div><div class="wl">{lbl}</div></div>')
    wf = ('<div class="wf">' + col('القيمة التعاقدية', 1000000, 1000000 * H, 0, '#B9A46A', ta) +
          col('زيادة', 80000, 80000 * H, 1000000 * H, '#2E7D4F', tb, '+') +
          col('نقص', 30000, 30000 * H, 1050000 * H, '#C0392B', tc, '−') +
          col('بعد التغيير', 1050000, 1050000 * H, 0, c, td) + '</div>')
    kp = (f'<div class="kpis"{A("up", te, 0.8, t1)}><div><span>المنفَّذ</span><b>500,000</b><em>50%</em></div>'
          f'<div><span>المدفوع</span><b>270,000</b><em>25.7%</em></div><div><span>المستحق غير المدفوع</span><b>250,000</b><em>محال للصرف</em></div></div>')
    out.append(scene(k, board(k, c, 'cycle', 'قيمة العقد<br>بعد التغيير', [
        ('بمليون', 'القيمة التعاقدية', '1,000,000 د.ل'), ('زيادةٌ', 'أمر تغيير بالزيادة', '+ 80,000'),
        ('ونقصٌ', 'أمر تغيير بالنقص', '− 30,000'), ('فتصبح', 'القيمة بعد التغيير', '1,050,000 د.ل', 1)]) +
        card(wf + kp, VX + 40, VY + 10, 1100, 720, scene_in[k] + 0.3, t1), glow=c))

    # e05 — SPI: مخطط 64% وفعلي 52% ← 0.81، تأخير متوقع 82 يوماً
    k = 'e05'; c = SC['risks']; t1 = scene_out[k] - 0.6
    tp, ta_, ts, tf = at(k, 'مخطَّطه'), at(k, 'وأُنجز'), at(k, 'فمؤشره'), at(k, 'وتتوقع')
    inner = (bar('المخطط حتى اليوم', 64, '#B9A46A', tp, t1, '<b>64%</b>') + bar('المنجز فعلاً', 52, c, ta_, t1, '<b>52%</b>') +
             f'<div class="spi"{A("scale", ts, 0.9, t1)}><div class="spic" style="--c:#C0392B">{count(0.81, ts, 1.2, 2)}<span>SPI</span></div>'
             f'<div class="spit"><b>متأخر حرج</b><span>أقل من 0.85</span></div></div>'
             f'<div class="dates"{A("up", tf, 0.8, t1)}><div><span>النهاية المعدّلة</span><b>2027/01/30</b></div><i>←</i>'
             f'<div><span>الإنجاز المتوقع بالسرعة الحالية</span><b>2027/04/22</b></div><em>+82 يوماً</em></div>')
    out.append(scene(k, board(k, c, 'risks', 'إنذار مبكر<br>بالتأخير', [
        ('مخطَّطه', 'المخطط', '64%'), ('وأُنجز', 'الفعلي', '52%'),
        ('فمؤشره', 'مؤشر الأداء الزمني', '0.52 ÷ 0.64 = 0.81', 1), ('وتتوقع', 'التأخير المتوقع', '82 يوماً · تنبيه')]) +
        card(inner, VX + 60, VY + 20, 1060, 700, scene_in[k] + 0.3, t1), glow=c))

    # e05r — مصفوفة المخاطر: 4 × 5 = 20 مرتفع جداً
    k = 'e05r'; c = SC['risks']; t1 = scene_out[k] - 0.6
    tx = at(k, 'درجته')
    cells = ''
    for p in range(5, 0, -1):
        for i in range(1, 6):
            sc_ = p * i
            col_ = '#2E7D4F' if sc_ <= 4 else '#7CB342' if sc_ <= 9 else '#E0A100' if sc_ <= 14 else '#E06A1B' if sc_ <= 19 else '#C0392B'
            hit = ' hit' if (p, i) == (4, 5) else ''
            cells += f'<i class="{hit.strip()}" style="background:{col_}">{sc_}</i>'
    mx = (f'<div class="mx"><div class="mxg">{cells}</div><div class="mxy">↑ الاحتمالية</div><div class="mxx">التأثير →</div>'
          f'<div class="mxhit"{A("scale", tx, 0.8, t1)}></div></div>'
          f'<div class="mxr"{A("up", tx + 0.3, 0.8, t1)}><b>20 · مرتفع جداً</b><span>تصعيد فوري · مراجعة كل 7 أيام</span></div>')
    out.append(scene(k, board(k, c, 'risks', 'تقييم الخطر<br>وتصعيده', [
        ('احتماليته', 'الاحتمالية × التأثير', '4 × 5'), ('درجته', 'الدرجة', '20 · مرتفع جداً', 1),
        ('يُصعَّد', 'الإجراء', 'تصعيد فوري'), ('ويُراجع', 'المراجعة', 'كل 7 أيام')]) +
        card(mx, VX + 120, VY + 10, 940, 720, scene_in[k] + 0.3, t1), glow=c))

    # e06 — الدرجة المركّبة للشركة = 64 (مقبول)
    k = 'e06'; c = SC['risks']; t1 = scene_out[k] - 0.6
    tq, td_, tr_ = at(k, 'تقييمها'), at(k, 'ونُسب'), at(k, 'درجتها')
    inner = (bar('التقييم الميداني (الوزن 40%)', 62.5, '#2B62A8', tq, t1, '<b>62.5</b>') +
             bar('التأخير المنسوب (15%)', 70, '#2B62A8', td_, t1, '<b>70</b>') +
             bar('الالتزام الزمني (30%)', 60, '#2B62A8', td_ + 0.5, t1, '<b>60</b>') +
             bar('سرعة حل المشاكل (15%)', 70, '#2B62A8', td_ + 1.0, t1, '<b>70</b>') +
             f'<div class="spi"{A("scale", tr_, 0.9, t1)}><div class="spic" style="--c:#D49B1F">{count(64, tr_, 1.2)}<span>من 100</span></div>'
             f'<div class="spit"><b>مقبول</b><span>إسناد مشروط بخطة تحسين</span></div></div>')
    out.append(scene(k, board(k, c, 'risks', 'تقييم الشركات<br>بالأرقام', [
        ('تقييمها', 'التقييم الميداني', '3.5 من 5'), ('ونُسب', 'التأخير المنسوب', '24 يوماً من 400'),
        ('درجتها', 'الدرجة المركّبة', '64 · مقبول', 1), ('والإسناد', 'التوصية', 'إسناد مشروط بخطة تحسين')]) +
        card(inner, VX + 60, VY + 20, 1060, 700, scene_in[k] + 0.3, t1), glow=c))

    # e07 — إجراء في الخطة: منجز 25% والمخطط 40.9% ← −15.9 نقطة
    k = 'e07'; c = SC['swot']; t1 = scene_out[k] - 0.6
    ta7, tp7, tf7 = at(k, 'أُنجز'), at(k, 'والمخطط'), at(k, 'فيظهر')
    inner = (f'<div class="actn"{A("up", ta7 - 0.4, 0.7, t1)}><span>إجراء استراتيجي</span><b>يبدأ 2026/09/01 لمدة 6 أشهر</b></div>' +
             bar('المنجز المسجّل', 25, c, ta7, t1, '<b>25%</b>', 40.9, 'المخطط اليوم 40.9%') +
             f'<div class="spi"{A("scale", tf7, 0.9, t1)}><div class="spic" style="--c:#C0392B">{count(-15.9, tf7, 1.2, 1)}<span>نقطة</span></div>'
             f'<div class="spit"><b>متأخر عن الخطة</b><span>الانحراف أقل من −10 · يظهر في التنبيهات</span></div></div>')
    out.append(scene(k, board(k, c, 'swot', 'متابعة الخطة<br>الاستراتيجية', [
        ('أُنجز', 'المنجز', '25%'), ('والمخطط', 'المخطط حتى اليوم', '74 ÷ 181 يوماً = 40.9%'),
        ('فيظهر', 'الانحراف', '−15.9 نقطة · متأخر', 1)]) +
        card(inner, VX + 60, VY + 60, 1060, 620, scene_in[k] + 0.3, t1), glow=c))

    # e08 — مراسلة متأخرة الرد + مسار تطوير تصميم بثلاثة إصدارات
    k = 'e08'; c = SC['docs']; t1 = scene_out[k] - 0.6
    tl8, tv8 = at(k, 'مراسلةٌ'), at(k, 'وتصميمٌ')
    letter = (f'<div class="letter"{A("rise", tl8, 0.8, t1)}><div class="lh">{svg("doc", 34, c)}<b>مراسلة واردة</b><em>بانتظار رد</em></div>'
              f'<div class="lr"><span>موعد الرد</span><b>مضى ولم تُغلق</b></div><div class="late"{A("scale", tl8 + 1.6, 0.6, t1)}>متأخرة الرد</div></div>')
    revs = ''.join(f'<div class="rev"{A("up", tv8 + 0.5 + i * 0.5, 0.6, t1)}><i style="background:{c}">{n}</i><b>الإصدار {n}</b><span>{note}</span></div>'
                   for i, (n, note) in enumerate([(3, 'الأحدث · بتاريخه ومن أضافه'), (2, 'يبقى محفوظاً'), (1, 'أُنشئ مع المستند')]))
    path = f'<div class="revs"{A("fade", tv8, 0.6, t1)}><div class="rvt">مسار تطوير التصميم</div>{revs}</div>'
    out.append(scene(k, board(k, c, 'docs', 'لا شيء<br>يضيع', [
        ('مراسلةٌ', 'مراسلة بانتظار رد', 'موعد الرد مضى'), ('تظهر', 'الحالة', 'متأخرة الرد · رقم على القائمة', 1),
        ('وتصميمٌ', 'تصميم بثلاثة تعديلات', 'الإصدارات 1 · 2 · 3 محفوظة')]) +
        f'<div class="ex8">{letter}{path}</div>', glow=c))

    # e09 — التغطية: 12 يوم عمل، تقارير في 9 ← 75%
    k = 'e09'; c = SC['supervision']; t1 = scene_out[k] - 0.6
    tw, tr9, tc9 = at(k, 'اثني عشر'), at(k, 'رُفعت'), at(k, 'فتظهر')
    days = ['السبت', 'الأحد', 'الاثنين', 'الثلاثاء', 'الأربعاء', 'الخميس', 'الجمعة']
    filled = {0, 1, 2, 4, 5, 7, 8, 10, 11}   # تسعة أيام عمل فيها تقارير
    grid = ''.join(f'<span class="dh">{d}</span>' for d in days)
    wi = 0
    for i in range(14):
        if i % 7 == 6:
            grid += f'<i class="fri"{A("fade", tw, 0.5, t1)}>جمعة</i>'
            continue
        ok = wi in filled
        grid += f'<i class="{"ok" if ok else "miss"}"{A("scale", (tr9 + wi * 0.12) if ok else tw + 0.3, 0.5, t1)}>{"✓" if ok else ""}</i>'
        wi += 1
    cov = (f'<div class="cov">{grid}</div><div class="covr"{A("scale", tc9, 0.8, t1)}><b>75%</b><span>9 ÷ 12 يوم عمل · برتقالي</span></div>')
    out.append(scene(k, board(k, c, 'supervision', 'انتظام<br>التقارير اليومية', [
        ('اثني عشر', 'أيام العمل', '14 يوماً − جمعتان = 12'), ('رُفعت', 'أيام فيها تقارير', '9'),
        ('فتظهر', 'التغطية', '9 ÷ 12 = 75%', 1)]) +
        card(cov, VX + 60, VY + 60, 1060, 620, scene_in[k] + 0.3, t1), glow=c))

    # e10 — 25 يوماً بلا حوادث، ونسبة مطابقة 90%
    k = 'e10'; c = '#3949AB'; t1 = scene_out[k] - 0.6
    ts10, tq10 = at(k, 'فالعدّاد'), at(k, 'ثمانيةَ')
    tiles = (f'<div class="bigt" style="--c:{SC["safety"]}"{A("rise", at(k, "آخر"), 0.9, t1)}><span class="ti">{svg("safety", 46, "#fff")}</span>'
             f'{count(25, ts10, 1.3)}<em>يوماً بلا حوادث</em><small>الحادث الوشيك لا يقطع العدّاد</small></div>'
             f'<div class="bigt" style="--c:{SC["acceptance"]}"{A("rise", at(k, "ومن عشرين"), 0.9, t1)}><span class="ti">{svg("acceptance", 46, "#fff")}</span>'
             f'{count(90, tq10, 1.3, suffix="%")}<em>نسبة مطابقة الاختبارات</em><small>18 مطابق · 2 غير مطابق · المعلّق لا يُحتسب</small></div>')
    out.append(scene(k, board(k, c, 'planning_qa', 'مؤشرات<br>الوحدات المتخصصة', [
        ('آخر', 'آخر حادث', 'قبل 25 يوماً'), ('فالعدّاد', 'أيام بلا حوادث', '25', 1),
        ('ومن عشرين', 'نتائج الاختبارات', '18 مطابق · 2 غير مطابق'), ('ثمانيةَ', 'نسبة المطابقة', '18 ÷ 20 = 90%', 1)]) +
        f'<div class="ex10">{tiles}</div>', glow=c))

    # e11 — مسار اعتماد النموذج الحساس
    k = 'e11'; c = '#1E5B46'; t1 = scene_out[k] - 0.6
    steps = [('تغيير', 'cycle', 'المهندس يغيّر حالة نموذج حساس'), ('طلبَ', 'lock', 'يُنشأ طلب اعتماد معلّق'),
             ('يعتمده', 'shield', 'المدير يعتمد أو يرفض بسبب'), ('ويُشعَر', 'eye', 'إشعار بالقرار لصاحب الطلب')]
    flow = ''.join(f'<div class="fstep"{A("rise", at(k, p, 0.3), 0.8, t1)}><span class="si">{svg(ic, 36, "#fff")}</span><b>{tx}</b></div>' +
                   (f'<i class="farr"{A("fade", at(k, p, 0.0) + 0.4, 0.5, t1)}>↓</i>' if n < 3 else '')
                   for n, (p, ic, tx) in enumerate(steps))
    out.append(scene(k, board(k, c, 'shield', 'الاعتماد<br>قبل التطبيق', [
        ('تغيير', 'تغيير نموذج حساس', 'لا يُطبَّق مباشرة'), ('طلبَ', 'طلب اعتماد', 'لدى المدير'),
        ('يعتمده', 'القرار', 'اعتماد أو رفض بسبب'), ('ويُشعَر', 'النتيجة', 'إشعار لصاحب الطلب', 1)]) +
        f'<div class="flow">{flow}</div>', glow=c))

    # e12 — سؤال المدير للمساعد (لقطة حقيقية مكبّرة)
    k = 'e12'; c = SC['manual']; t1 = scene_out[k] - 0.6
    out.append(scene(k, board(k, c, 'spark', 'المساعد<br>يقترح ولا ينفّذ', [
        ('يسأل', 'السؤال', 'المستخلصات المحالة ولم تُدفع'), ('فيجيب', 'الإجابة', 'من بيانات المنظومة مباشرة'),
        ('ويقترح', 'التنفيذ', 'بضغطة من المدير فقط', 1)]) +
        window('50_assistant_crop.png', VX, 250, VW, 624, scene_in[k] + 0.2, t1, pan=(0, 0), zoom=(1.0, 1.08)) +
        f'<div class="note"{A("fade", scene_in[k] + 1.0, 0.8, t1)}>لقطة من المنظومة · بيانات تجريبية للعرض</div>', glow=c))
    return out
