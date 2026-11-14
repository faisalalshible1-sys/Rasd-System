// node preview.js out_prefix t1 t2 ... : يلتقط إطارات عند أزمنة محددة للمراجعة
const { chromium } = require('playwright');
const path = require('path');
(async () => {
  const [prefix, ...ts] = process.argv.slice(2);
  const b = await chromium.launch();
  const p = await b.newPage({ viewport: { width: 1920, height: 1080 }, deviceScaleFactor: 1 });
  await p.goto('file://' + path.join(__dirname, 'build', 'index.html'));
  await p.evaluate(async () => { await document.fonts.ready; await Promise.all([...document.images].map(i => i.complete ? 0 : new Promise(r => { i.onload = i.onerror = r; }))); });
  for (const t of ts) {
    await p.evaluate(x => window.render(x), +t);
    await p.screenshot({ path: `${prefix}_${String(t).padStart(6, '0')}.jpg`, type: 'jpeg', quality: 85 });
  }
  await b.close();
})();
