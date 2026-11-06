extends RefCounted

## The script the player runs in the browser's page over DevTools (Runtime.evaluate) for voice into a field
## (scripts/video/browser_dictation.gd; docs/window-source.md, "Voice into a field"). One function, four operations:
##   check   what has focus: {editable, kind: input | textarea | contenteditable | iframe | <tag> | none,
##           input_type, password, frame: main | same-origin | cross-origin, focused (the document has focus),
##           space_before (the character before the caret is not a space)}. Never the field's text.
##   mark    as check, and when the field is editable and not a password field, a glowing outline on it
##           (marked: true) and an empty line for the live words under it
##   words   the live words under the field (arg: the text; "" hides the line)
##   unmark  removes the outline and the words
## The outline and the words are a separate element at the end of the document, in a closed shadow root with
## pointer-events none: the page's own styles and the field are not touched, and it follows the field each animation
## frame (scrolling, resizing) until removed or the field goes. Focus inside shadow roots and same-origin iframes is
## followed; a cross-origin iframe's document can't be seen from the page (frame: cross-origin): browser_dictation.gd
## asks that frame's own DevTools session then.
##
##   PageField.expression("check")        a Runtime.evaluate expression
##   PageField.expression("words", "hello")

const KEY := "__vrPlayerField"

const SCRIPT := """(function (op, arg) {
	var KEY = '__vrPlayerField';
	var TEXT_TYPES = ['text', 'search', 'url', 'tel', 'email', 'password'];
	function active(doc) {
		var el = doc.activeElement, frame = 'main';
		for (var i = 0; i < 32 && el; i++) {
			if (el.shadowRoot && el.shadowRoot.activeElement) { el = el.shadowRoot.activeElement; continue; }
			if (el.tagName === 'IFRAME' || el.tagName === 'FRAME') {
				var inner = null;
				try { inner = el.contentDocument; } catch (e) { inner = null; }
				if (!inner) { return {el: el, frame: 'cross-origin'}; }
				el = inner.activeElement; frame = 'same-origin'; continue;
			}
			break;
		}
		return {el: el, frame: frame};
	}
	function describe(el) {
		var out = {editable: false, kind: 'none', input_type: '', password: false, space_before: false};
		if (!el || el === el.ownerDocument.body || el === el.ownerDocument.documentElement) { return out; }
		var tag = el.tagName;
		out.kind = tag ? tag.toLowerCase() : 'none';
		if (tag === 'INPUT') {
			var t = (el.type || 'text').toLowerCase();
			out.kind = 'input';
			out.input_type = t;
			out.password = t === 'password';
			out.editable = TEXT_TYPES.indexOf(t) >= 0 && !el.readOnly && !el.disabled;
		} else if (tag === 'TEXTAREA') {
			out.kind = 'textarea';
			out.editable = !el.readOnly && !el.disabled;
		} else if (el.isContentEditable) {
			out.kind = 'contenteditable';
			out.editable = true;
		}
		try {
			var view = el.ownerDocument.defaultView;
			var sec = view.getComputedStyle(el).webkitTextSecurity;
			if (sec && sec !== 'none') { out.password = true; }
		} catch (e) {}
		if (out.editable && !out.password) {
			try {
				if (typeof el.selectionStart === 'number' && el.selectionStart > 0) {
					out.space_before = !/\\s/.test(el.value.charAt(el.selectionStart - 1));
				}
			} catch (e) {}
		}
		return out;
	}
	function mark(el) {
		var old = window[KEY];
		if (old) { old.remove(); }
		var doc = el.ownerDocument, view = doc.defaultView;
		var host = doc.createElement('div');
		host.setAttribute('data-vr-player', 'dictation');
		host.style.cssText = 'all: initial; position: fixed; left: 0; top: 0; width: 0; height: 0; '
				+ 'z-index: 2147483647; pointer-events: none;';
		var root = host.attachShadow({mode: 'closed'});
		var ring = doc.createElement('div');
		ring.style.cssText = 'position: fixed; box-sizing: border-box; border: 3px solid #3b9dff; border-radius: 7px; '
				+ 'box-shadow: 0 0 0 2px rgba(255, 255, 255, 0.95), 0 0 22px 8px rgba(59, 157, 255, 0.8); '
				+ 'pointer-events: none;';
		var words = doc.createElement('div');
		words.style.cssText = 'position: fixed; max-width: 60vw; padding: 6px 12px; border-radius: 9px; '
				+ 'background: rgba(16, 20, 28, 0.94); color: #fff; font: 600 18px/1.35 system-ui, sans-serif; '
				+ 'box-shadow: 0 2px 14px rgba(0, 0, 0, 0.45); pointer-events: none; display: none; '
				+ 'white-space: pre-wrap; overflow-wrap: anywhere;';
		root.appendChild(ring);
		root.appendChild(words);
		doc.documentElement.appendChild(host);
		var frame = 0, alive = true;
		var api = {
			remove: function () {
				alive = false;
				view.cancelAnimationFrame(frame);
				host.remove();
				if (window[KEY] === api) { delete window[KEY]; }
			},
			words: function (text) {
				words.textContent = text;
				words.style.display = text ? 'block' : 'none';
			}
		};
		function place() {
			if (!alive) { return; }
			if (!el.isConnected) { api.remove(); return; }
			var r = el.getBoundingClientRect();
			ring.style.left = (r.left - 5) + 'px';
			ring.style.top = (r.top - 5) + 'px';
			ring.style.width = (r.width + 10) + 'px';
			ring.style.height = (r.height + 10) + 'px';
			var h = words.offsetHeight || 34;
			var below = r.bottom + 10;
			words.style.left = Math.max(6, Math.min(r.left, view.innerWidth - 120)) + 'px';
			words.style.top = (below + h > view.innerHeight ? Math.max(6, r.top - h - 10) : below) + 'px';
			frame = view.requestAnimationFrame(place);
		}
		window[KEY] = api;
		place();
	}
	if (op === 'check' || op === 'mark') {
		var a = active(document);
		var d;
		if (a.frame === 'cross-origin') {
			d = {editable: false, kind: 'iframe', input_type: '', password: false, space_before: false};
		} else {
			d = describe(a.el);
		}
		d.frame = a.frame;
		d.focused = document.hasFocus();
		d.marked = false;
		if (op === 'mark' && d.editable && !d.password) { mark(a.el); d.marked = true; }
		return d;
	}
	var m = window[KEY];
	if (op === 'words') { if (m) { m.words(String(arg || '')); } return !!m; }
	if (op === 'unmark') { if (m) { m.remove(); } return !!m; }
	return null;
})"""


## A Runtime.evaluate expression for one operation. The marker comment names the operation (the tests' fake page
## reads it); arg goes in as JSON, so no text can break out of the string.
static func expression(op: String, arg: Variant = null) -> String:
	return "/*vrplayer:%s*/%s(%s, %s)" % [op, SCRIPT, JSON.stringify(op), JSON.stringify(arg)]


## A check's answer made safe to hand out (the read command): no hint of what the field holds.
static func public(d: Dictionary) -> Dictionary:
	return {"editable": bool(d.get("editable", false)), "kind": str(d.get("kind", "none")),
			"input_type": str(d.get("input_type", "")), "password": bool(d.get("password", false)),
			"frame": str(d.get("frame", "main"))}
