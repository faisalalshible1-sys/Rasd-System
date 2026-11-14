// node render.js startFrame endFrame out.mp4 : يصيّر الإطارات ويرسلها إلى ffmpeg
const { chromium } = require('playwright');
const { spawn } = require('child_process');
const path = require('path');
(async () => {
  const [a, b, out] = [+process.argv[2], +process.argv[3], process.argv[4]];
  const br = await chromium.launch({ args: ['--disable-gpu', '--force-color-profile=srgb'] });
  const p = await br.newPage({ viewport: { width: 1920, height: 1080 }, deviceScaleFactor: 1 });
  await p.goto('file://' + path.join(__dirname, 'build', 'index.html'));
  await p.evaluate(async () => { await document.fonts.ready; await Promise.all([...document.images].map(i => i.complete ? 0 : new Promise(r => { i.onload = i.onerror = r; }))); });
  const ff = spawn('ffmpeg', ['-loglevel', 'error', '-y', '-f', 'image2pipe', '-framerate', '30', '-c:v', 'mjpeg', '-i', '-',
    '-c:v', 'libx264', '-preset', 'veryfast', '-crf', '19', '-pix_fmt', 'yuv420p', '-r', '30', '-g', '60', '-movflags', '+faststart', out], { stdio: ['pipe', 'inherit', 'inherit'] });
  const t0 = Date.now();
  for (let i = a; i < b; i++) {
    await p.evaluate(t => window.render(t), i / 30);
    const buf = await p.screenshot({ type: 'jpeg', quality: 95 });
    if (!ff.stdin.write(buf)) await new Promise(r => ff.stdin.once('drain', r));
    if ((i - a) % 300 === 0) console.log(`frame ${i} ${((Date.now() - t0) / 1000).toFixed(1)}s`);
  }
  ff.stdin.end();
  await new Promise(r => ff.on('close', r));
  await br.close();
  console.log('done', out, ((Date.now() - t0) / 1000).toFixed(1) + 's');
})();
