// محرك حركة حتمي: render(t) يضبط كل عنصر حسب الزمن t بالثواني، دون أي اعتماد على الوقت الحقيقي.
const TOTAL = __TOTAL__, C0 = __C0__, C1 = __C1__;
const cl = x => x < 0 ? 0 : x > 1 ? 1 : x;
const eo = x => { x = cl(x); return 1 - Math.pow(1 - x, 3); };
const eio = x => { x = cl(x); return x < .5 ? 4 * x * x * x : 1 - Math.pow(-2 * x + 2, 3) / 2; };
const A = [...document.querySelectorAll('[data-a]')].map(el => ({
  el, a: el.dataset.a, t0: +el.dataset.t0, d: +(el.dataset.d || .8),
  t1: el.dataset.t1 !== undefined ? +el.dataset.t1 : null, d1: +(el.dataset.d1 || .6), last: ''
}));
const P = [...document.querySelectorAll('[data-pan]')].map(el => {
  const [y0, y1, t0, t1, z0, z1] = el.dataset.pan.split(',').map(Number); return { el, y0, y1, t0, t1, z0, z1 };
});
const N = [...document.querySelectorAll('[data-count]')].map(el => ({ el, n: +el.dataset.count, t0: +el.dataset.t0, d: +el.dataset.d }));
const W = [...document.querySelectorAll('[data-draw]')].map(el => {
  const [t0, d] = el.dataset.draw.split(',').map(Number); el.style.strokeDasharray = '1'; return { el, t0, d };
});
const bar = document.getElementById('bar'), bg = document.getElementById('bg');
window.render = function (t) {
  for (const o of A) {
    const pi = eo((t - o.t0) / o.d);
    const po = o.t1 === null ? 0 : eio((t - o.t1) / o.d1);
    const op = pi * (1 - po);
    let tr = '';
    switch (o.a) {
      case 'up': tr = `translateY(${((1 - pi) * 34 - po * 12).toFixed(2)}px)`; break;
      case 'rise': tr = `translateY(${((1 - pi) * 70).toFixed(2)}px) scale(${(.965 + .035 * pi).toFixed(4)})`; break;
      case 'scale': tr = `scale(${(.9 + .1 * pi + .03 * po).toFixed(4)})`; break;
      case 'slideR': tr = `translateX(${((1 - pi) * 46).toFixed(2)}px)`; break;
      case 'slideL': tr = `translateX(${(-(1 - pi) * 90).toFixed(2)}px)`; break;
      case 'grow': tr = `scaleX(${pi.toFixed(4)})`; break;
    }
    const vis = op > 0.002;
    o.el.style.visibility = vis ? 'visible' : 'hidden';
    if (vis) { o.el.style.opacity = op.toFixed(4); if (tr) o.el.style.transform = tr; }
  }
  for (const p of P) {
    const k = eio((t - p.t0) / (p.t1 - p.t0));
    p.el.style.transform = `translateY(${(-(p.y0 + (p.y1 - p.y0) * k)).toFixed(2)}px) scale(${(p.z0 + (p.z1 - p.z0) * k).toFixed(4)})`;
  }
  for (const c of N) c.el.textContent = Math.round(c.n * eo((t - c.t0) / c.d));
  for (const w of W) w.el.style.strokeDashoffset = (1 - eo((t - w.t0) / w.d)).toFixed(4);
  if (bar) bar.style.width = (cl((t - C0) / (C1 - C0)) * 100).toFixed(3) + '%';
  bg.style.backgroundPosition = `0 0, 0 0, ${(Math.sin(t / 23) * 40).toFixed(2)}px ${(t * 3).toFixed(2)}px, 0 0`;
};
window.render(0);
