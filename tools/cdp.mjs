// Minimal Chrome DevTools Protocol driver for Microsoft Edge (no npm deps, Node >= 22).
// Usage: node cdp.mjs <port> <steps.json>
// steps: [{"nav": url}, {"wait": ms}, {"waitFor": css}, {"type": [css, text]}, {"click": css},
//         {"clickText": text}, {"eval": js}, {"shot": file, "clip": css?, "full": bool?}, {"viewport": [w,h]}]
import fs from 'node:fs';

const [port, stepsFile] = process.argv.slice(2);
const steps = JSON.parse(fs.readFileSync(stepsFile, 'utf8').replace(/^﻿/, ''));
const targets = await (await fetch(`http://127.0.0.1:${port}/json`)).json();
const page = targets.find(t => t.type === 'page');
const ws = new WebSocket(page.webSocketDebuggerUrl);
await new Promise(r => ws.addEventListener('open', r));
let id = 0; const pending = new Map();
ws.addEventListener('message', ev => {
  const m = JSON.parse(ev.data);
  if (m.id && pending.has(m.id)) { pending.get(m.id)(m); pending.delete(m.id); }
});
const send = (method, params = {}) => new Promise((res, rej) => {
  const i = ++id; pending.set(i, m => m.error ? rej(new Error(method + ': ' + m.error.message)) : res(m.result));
  ws.send(JSON.stringify({ id: i, method, params }));
});
const sleep = ms => new Promise(r => setTimeout(r, ms));
const evaluate = async (expr) => {
  const r = await send('Runtime.evaluate', { expression: expr, awaitPromise: true, returnByValue: true });
  if (r.exceptionDetails) throw new Error('eval: ' + (r.exceptionDetails.exception?.description || r.exceptionDetails.text));
  return r.result.value;
};
const waitFor = async (css, timeout = 30000) => {
  const t0 = Date.now();
  while (Date.now() - t0 < timeout) {
    if (await evaluate(`!!document.querySelector(${JSON.stringify(css)})`)) return;
    await sleep(250);
  }
  throw new Error('timeout waiting for ' + css);
};
await send('Page.enable'); await send('Runtime.enable');
await send('Emulation.setDeviceMetricsOverride', { width: 1600, height: 1000, deviceScaleFactor: 1, mobile: false });

for (const s of steps) {
  if (s.viewport) await send('Emulation.setDeviceMetricsOverride', { width: s.viewport[0], height: s.viewport[1], deviceScaleFactor: s.scale || 1, mobile: false });
  if (s.nav) { await send('Page.navigate', { url: s.nav }); await sleep(1500); }
  if (s.waitFor) await waitFor(s.waitFor, s.timeout);
  if (s.type) {
    const [css, text] = s.type;
    await waitFor(css);
    await evaluate(`(() => { const e = document.querySelector(${JSON.stringify(css)}); e.focus();
      const proto = e.tagName === 'TEXTAREA' ? HTMLTextAreaElement.prototype : HTMLInputElement.prototype;
      Object.getOwnPropertyDescriptor(proto, 'value').set.call(e, '');
      e.dispatchEvent(new Event('input', {bubbles:true})); })()`);
    await send('Input.insertText', { text });
  }
  if (s.click) { await waitFor(s.click); await evaluate(`document.querySelector(${JSON.stringify(s.click)}).click()`); }
  if (s.clickText) {
    const ok = await evaluate(`(() => { const want = ${JSON.stringify(s.clickText)};
      const els = [...document.querySelectorAll('button, a, [role=button], [role=tab], [role=menuitem], span, div, label')];
      const e = els.find(x => x.innerText && x.innerText.trim() === want && x.offsetParent !== null);
      if (!e) return false; (e.closest('button,a,[role=button],[role=tab],[role=menuitem]') || e).click(); return true; })()`);
    if (!ok) throw new Error('text not found: ' + s.clickText);
  }
  if (s.hover || s.mouse || s.mclick) {
    let x, y;
    if (s.mouse || s.mclick) [x, y] = s.mouse || s.mclick;
    else {
      await waitFor(s.hover);
      ({ x, y } = await evaluate(`(() => { const b = document.querySelector(${JSON.stringify(s.hover)}).getBoundingClientRect();
        return {x: b.x + b.width / 2, y: b.y + b.height / 2}; })()`));
    }
    await send('Input.dispatchMouseEvent', { type: 'mouseMoved', x, y });
    if (s.mclick) {
      await send('Input.dispatchMouseEvent', { type: 'mousePressed', x, y, button: 'left', clickCount: 1 });
      await send('Input.dispatchMouseEvent', { type: 'mouseReleased', x, y, button: 'left', clickCount: 1 });
    }
  }
  if (s.eval) { const v = await evaluate(s.eval); if (v !== undefined) console.log(typeof v === 'string' ? v : JSON.stringify(v)); }
  if (s.wait) await sleep(s.wait);
  if (s.shot) {
    const params = { format: 'png', captureBeyondViewport: !!s.full };
    if (s.clip) {
      const r = await evaluate(`(() => { const b = document.querySelector(${JSON.stringify(s.clip)}).getBoundingClientRect();
        return {x: b.x + scrollX, y: b.y + scrollY, width: b.width, height: b.height}; })()`);
      params.clip = { ...r, scale: 1 };
    }
    if (s.full) {
      const m = await send('Page.getLayoutMetrics');
      params.clip = { x: 0, y: 0, width: m.cssContentSize.width, height: m.cssContentSize.height, scale: 1 };
    }
    const { data } = await send('Page.captureScreenshot', params);
    fs.writeFileSync(s.shot, Buffer.from(data, 'base64'));
    console.log('shot', s.shot);
  }
}
ws.close();
