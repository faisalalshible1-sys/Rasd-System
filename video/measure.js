const { chromium } = require('playwright'); const path=require('path');
(async()=>{const b=await chromium.launch();const p=await b.newPage({viewport:{width:1920,height:1080}});
await p.goto('file://'+path.join(__dirname,'build','index.html'));
await p.evaluate(()=>window.render(26));
console.log(await p.evaluate(()=>{const r=s=>{const e=document.querySelector(s).getBoundingClientRect();return [Math.round(e.left),Math.round(e.right),Math.round(e.top)]};return {sx:scrollX,sw:document.documentElement.scrollWidth,cw:document.documentElement.clientWidth,panel:r('#s02 .panel'),brand:r('.brand'),win:r('#s02 .win')}}));
await b.close();})();
