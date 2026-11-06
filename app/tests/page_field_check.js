// Runs scripts/video/page_field.gd's SCRIPT against a tiny stand-in DOM: syntax, check, mark, words, unmark, frames,
// shadow roots. tests/test_browser_dictation.gd runs it when Node is installed:
//   node app/tests/page_field_check.js app/scripts/video/page_field.gd
const fs = require('fs');
const src = fs.readFileSync(process.argv[2], 'utf8');
const start = src.indexOf('const SCRIPT := """') + 'const SCRIPT := """'.length;
const end = src.indexOf('"""', start);
// GDScript string escapes: \\ -> \ (the only one used).
const script = src.slice(start, end).replace(/\\\\/g, '\\');

let frames = 0;
function el(tag, props) {
  const e = Object.assign({
    tagName: tag, style: {}, children: [], isConnected: true, attrs: {},
    setAttribute(k, v) { this.attrs[k] = v; },
    attachShadow() { return { appendChild(c) { e.children.push(c); } }; },
    appendChild(c) { this.children.push(c); c.parent = this; },
    remove() { this.removed = true; },
    getBoundingClientRect() { return { left: 100, top: 200, width: 300, height: 40, bottom: 240, right: 400 }; },
    offsetHeight: 30,
  }, props || {});
  return e;
}
const doc = {
  body: null, documentElement: null, activeElement: null,
  createElement(t) { const e = el(t.toUpperCase()); e.ownerDocument = doc; return e; },
  hasFocus() { return true; },
};
doc.body = el('BODY'); doc.documentElement = el('HTML');
const win = {
  innerWidth: 1280, innerHeight: 720,
  requestAnimationFrame(f) { frames++; return frames; },
  cancelAnimationFrame() {},
  getComputedStyle() { return { webkitTextSecurity: 'none' }; },
};
doc.defaultView = win;
global.window = win; global.document = doc;
for (const e of [doc.body, doc.documentElement]) e.ownerDocument = doc;

const run = (op, arg) => (0, eval)(script)(op, arg === undefined ? null : arg);
let ok = true;
function check(what, cond) { if (!cond) { ok = false; console.log('FAIL ' + what); } else console.log('ok   ' + what); }

doc.activeElement = doc.body;
check('body: nothing', run('check').editable === false && run('check').kind === 'none');
const input = el('INPUT', { type: 'search', readOnly: false, disabled: false, selectionStart: 5, value: 'hello', ownerDocument: doc });
doc.activeElement = input;
let d = run('check');
check('search input editable, space before ' + JSON.stringify(d), d.editable && d.kind === 'input' && d.input_type === 'search' && d.space_before === true && d.frame === 'main');
check('no value given out', !JSON.stringify(d).includes('hello'));
input.type = 'number';
check('number is no text field', run('check').editable === false);
input.type = 'password';
d = run('mark');
check('password refused, not marked', d.password && !d.marked && doc.documentElement.children.length === 0);
input.type = 'text';
d = run('mark');
check('mark: outline host added', d.marked && doc.documentElement.children.length === 1 && window.__vrPlayerField);
const host = doc.documentElement.children[0];
check('host is pointer-events none, fixed', host.style.cssText.includes('pointer-events: none') && host.style.cssText.includes('position: fixed'));
check('ring placed round the field', host.children[0].style.left === '95px' && host.children[0].style.width === '310px');
check('words', run('words', 'hi <b>there</b>') === true && host.children[1].textContent === 'hi <b>there</b>' && host.children[1].style.display === 'block');
check('unmark', run('unmark') === true && host.removed && !window.__vrPlayerField);
check('unmark again: nothing', run('unmark') === false);
const ta = el('TEXTAREA', { readOnly: true, ownerDocument: doc });
doc.activeElement = ta;
check('read-only textarea is no field', run('check').editable === false);
const ce = el('DIV', { isContentEditable: true, ownerDocument: doc });
doc.activeElement = ce;
check('contenteditable', run('check').kind === 'contenteditable' && run('check').editable);
const frameEl = el('IFRAME', { ownerDocument: doc });
Object.defineProperty(frameEl, 'contentDocument', { get() { throw new Error('cross-origin'); } });
doc.activeElement = frameEl;
d = run('check');
check('cross-origin iframe ' + JSON.stringify(d), d.kind === 'iframe' && d.frame === 'cross-origin' && !d.editable);
const inner = { activeElement: null, hasFocus() { return true; } };
const innerInput = el('INPUT', { type: 'email', ownerDocument: inner });
inner.activeElement = innerInput; inner.body = el('BODY'); inner.documentElement = el('HTML'); inner.defaultView = win;
const same = el('IFRAME', { ownerDocument: doc, contentDocument: inner });
doc.activeElement = same;
d = run('check');
check('same-origin iframe followed ' + JSON.stringify(d), d.editable && d.frame === 'same-origin' && d.input_type === 'email');
const shadowHost = el('X-FIELD', { ownerDocument: doc, shadowRoot: { activeElement: input } });
doc.activeElement = shadowHost;
check('shadow root followed', run('check').kind === 'input');
const masked = el('INPUT', { type: 'text', ownerDocument: doc });
doc.activeElement = masked;
win.getComputedStyle = () => ({ webkitTextSecurity: 'disc' });
check('text-security masked field counts as password', run('check').password === true);
process.exit(ok ? 0 : 1);
