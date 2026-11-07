extends Node

## Keeping pictures from the browser on the big screen into the picture library (picture_library.gd; docs/features.md
## "Pictures"). The user browses themselves (Objects → Pictures → Find pictures, or an assistant's pictures_search,
## opens Google Images): the app never scrapes or automates a page. Three ways in, one library:
##
##   1. The right stick click while the stick pointer is on an image (pointer mode, window_pointer.gd). The cursor
##      goes back to where it was before the click's nudge and holds a moment (stick_cursor.gd freeze()). The page's
##      DevTools session (browser_dictation.gd's lasting socket, devtools_session.gd) says what is under the cursor
##      (document.elementsFromPoint at the cursor's CSS position: window pixels / devicePixelRatio, 1.5 on the Frame;
##      an <img>'s currentSrc, else a CSS background picture), its alt text and its rectangle. The app fetches that
##      full-size source itself, with the page as its Referer; a data: URL is read as it is. When that fails, the
##      image's rectangle is cut out of the captured window: smaller, but always there.
##   2. Chromium's own Copy image (right click is a squeeze tap): a new picture on the clipboard while the browser is
##      on the big screen (DisplayServer.clipboard_get_image(), X11).
##   3. A picture saved to Downloads (JPEG, PNG, WebP, a GIF's first frame) while the browser is on the big screen.
## Every keep ends in a notice: "Picture kept: <title>" (the alt text, else the page's title). The legend KEEP
## PICTURE shows on the stick only while the cursor is over an image (over_image: asked of the page as the cursor
## moves, a few times a second at most).
##
## Nothing here logs a page's address or a picture's source: they stay in the library's own files.
## Tests: transport (fetch(url, headers, file) as fab_http.gd), clipboard (a Callable returning an Image or null),
## downloads_dir.

const PictureLibrary := preload("res://scripts/pictures/picture_library.gd")
const FabHttp := preload("res://scripts/assistant/fab_http.gd")
const FabStore := preload("res://scripts/assistant/fab_store.gd")
const XRHand := preload("res://scripts/xr/xr_hand.gd")
const WindowVideoSource := preload("res://scripts/video/window_video_source.gd")

## The cursor held this long around the stick click (seconds).
const FREEZE := 0.15
## How often the page is asked whether the cursor is over an image: as it moves, and now and then while still.
const HOVER_MOVING := 0.25
const HOVER_STILL := 1.0
const CLIPBOARD_EVERY := 1.0
const DOWNLOADS_EVERY := 2.0
const PICTURE_TYPES: Array[String] = ["jpg", "jpeg", "png", "webp", "gif", "bmp"]
const MAX_FILE := 32 << 20
## A data: URL longer than this is left out of the answer (the page socket takes 1 MiB a message): the crop then.
const DATA_URL_MAX := 900000

## The page's script (Runtime.evaluate): "over" -> {image}; "keep" -> {image, src, alt, rect (window pixels), title,
## page}. Never anything else of the page.
const SCRIPT := """(function (op, x, y) {
	var dpr = window.devicePixelRatio || 1;
	function bg(el) {
		try {
			var b = window.getComputedStyle(el).backgroundImage || '';
			var m = /url\\(["']?([^"')]+)["']?\\)/.exec(b);
			return m ? m[1] : '';
		} catch (e) { return ''; }
	}
	function find(doc, cx, cy, depth) {
		var els = doc.elementsFromPoint ? doc.elementsFromPoint(cx, cy) : [doc.elementFromPoint(cx, cy)];
		for (var i = 0; i < els.length && i < 16; i++) {
			var el = els[i];
			if (!el) { continue; }
			var tag = el.tagName;
			if (tag === 'IMG' && (el.currentSrc || el.src)) { return {el: el, src: el.currentSrc || el.src, dx: 0, dy: 0}; }
			if ((tag === 'IFRAME' || tag === 'FRAME') && depth < 3) {
				var inner = null;
				try { inner = el.contentDocument; } catch (e) { inner = null; }
				if (inner) {
					var r = el.getBoundingClientRect();
					var f = find(inner, cx - r.left, cy - r.top, depth + 1);
					if (f) { f.dx += r.left; f.dy += r.top; return f; }
				}
				continue;
			}
			if (tag === 'HTML' || tag === 'BODY') { continue; }
			var u = bg(el);
			if (u && u.indexOf('gradient') < 0) { return {el: el, src: u, dx: 0, dy: 0}; }
		}
		return null;
	}
	var f = find(document, x / dpr, y / dpr, 0);
	if (op === 'over') { return {image: !!f}; }
	if (!f) { return {image: false}; }
	var r = f.el.getBoundingClientRect();
	var src = String(f.src);
	if (src.length > 900000) { src = ''; }
	var alt = (f.el.getAttribute('alt') || f.el.getAttribute('title') || f.el.getAttribute('aria-label') || '');
	return {image: true, src: src, alt: String(alt).slice(0, 300), title: String(document.title).slice(0, 300),
		page: String(location.href).slice(0, 2000),
		rect: {x: (r.left + f.dx) * dpr, y: (r.top + f.dy) * dpr, w: r.width * dpr, h: r.height * dpr}};
})"""

## scripts/main.gd
var main: Node
## fetch(url, headers, file) -> {code, headers, body, error} (await); null: made on first use (fab_http.gd).
var transport: Object
## () -> Image or null: the clipboard's picture; empty: DisplayServer's (X11).
var clipboard: Callable
## Where downloads land; "": the system's Downloads folder.
var downloads_dir := ""
## The cursor is over an image now (the KEEP PICTURE legend).
var over_image := false
## The last keep's facts (tests): {how, title, via: fetch | data | crop, ok}.
var last := {}

var _hover_busy := false
var _hover_wait := 0.0
var _hover_at := Vector2(-9, -9)
var _clip_wait := 0.0
var _clip_seen := ""
var _down_wait := 0.0
var _down_seen := {}
var _down_since := 0
var _was_on := false
var _swallow_release := false
var _keeping := false


func _ready() -> void:
	if not clipboard.is_valid():
		clipboard = func() -> Variant:
			if DisplayServer.get_name() == "headless" or not DisplayServer.clipboard_has_image():
				return null
			return DisplayServer.clipboard_get_image()


func _transport() -> Object:
	if transport == null:
		var http := FabHttp.new()
		http.name = "Http"
		add_child(http)
		transport = http
	return transport


## The browser on the big screen (captured), or null.
func browser() -> WindowVideoSource:
	var d: Node = main.get("browser_dictation") if main != null else null
	return d.browser_source() if d != null else null


func _session() -> Object:
	var d: Node = main.get("browser_dictation") if main != null else null
	return d.get("session") if d != null else null


func _process(delta: float) -> void:
	var src := browser()
	var on := src != null
	if on != _was_on:
		_was_on = on
		if on:
			# What is there already is not kept: only what comes while the browser is on the big screen.
			_clip_seen = _clip_hash()
			_down_since = int(Time.get_unix_time_from_system()) - 1
			_down_seen = _download_files()
		elif over_image:
			_set_over(false)
	if not on:
		return
	_clip_wait -= delta
	if _clip_wait <= 0.0:
		_clip_wait = CLIPBOARD_EVERY
		_check_clipboard()
	_down_wait -= delta
	if _down_wait <= 0.0:
		_down_wait = DOWNLOADS_EVERY
		_check_downloads()
	_hover(delta)


# --- 1. The stick click ----------------------------------------------------------------------------------------------

## The stick click (main.gd): true when it was taken here (the browser's cursor is in pointer mode); its release too.
func on_stick_click(hand: XRHand, pressed: bool) -> bool:
	if not pressed:
		if _swallow_release:
			_swallow_release = false
			return true
		return false
	var wp: Node = main.get("window_pointer") if main != null else null
	if wp == null or hand != main.get("right_hand") or browser() == null or not wp.is_active() \
			or not bool(wp.get("cursor").mode) or not wp.has_cursor():
		return false
	_swallow_release = true
	var at: Vector2 = wp.freeze_cursor(FREEZE)
	hand.pulse()
	keep_at(at)
	return true


## Keeps the picture under a window pixel (the cursor): fetched from its source, else cut out of the window.
func keep_at(at: Vector2) -> void:
	if _keeping:
		return
	_keeping = true
	var r: Dictionary = await _keep_at(at)
	_keeping = false
	last = r
	if not bool(r.get("ok", false)):
		_note(TranslationServer.translate("No picture under the pointer") if str(r.get("why", "")) == "none"
				else TranslationServer.translate("That picture could not be kept"))


func _keep_at(at: Vector2) -> Dictionary:
	var src := browser()
	var s: Object = _session()
	if src == null or s == null or not bool(s.call("is_open")):
		return {"ok": false, "why": "none", "how": "stick"}
	var r: Dictionary = await s.call("evaluate", get_tree(), expression("keep", at))
	var d: Dictionary = r.get("value", {}) if r.get("value") is Dictionary else {}
	if not bool(d.get("image", false)):
		return {"ok": false, "why": "none", "how": "stick"}
	var title := PictureLibrary.clean_title(str(d.get("alt", "")))
	if title == "":
		title = PictureLibrary.clean_title(str(d.get("title", "")))
	var page := str(d.get("page", ""))
	var url := str(d.get("src", ""))
	var img: Image = null
	var via := ""
	if url.begins_with("data:image/"):
		img = PictureLibrary.from_data_url(url)
		via = "data"
	elif url.begins_with("https://") or url.begins_with("http://"):
		img = await _fetch(url, page)
		via = "fetch"
	if img == null:
		img = _crop(src, d.get("rect", {}))
		via = "crop"
	if img == null:
		return {"ok": false, "why": "failed", "how": "stick"}
	return _keep(img, title, page, "stick", via)


## The full-size source, fetched as the page would (its Referer): an image, or null.
func _fetch(url: String, page: String) -> Image:
	var h := PackedStringArray(["User-Agent: " + FabStore.user_agent(), "Accept: image/*"])
	if page.begins_with("http"):
		h.append("Referer: " + page)
	var r: Dictionary = await _transport().fetch(url, h, "")
	if str(r.get("error", "")) != "" or int(r.get("code", 0)) != 200:
		return null
	var body: PackedByteArray = r.get("body", PackedByteArray())
	if body.size() > MAX_FILE:
		return null
	return PictureLibrary.decode(body)


## The image's rectangle (window pixels) cut out of the captured window, or null.
static func _crop(src: WindowVideoSource, rect: Variant) -> Image:
	if not (rect is Dictionary):
		return null
	var tex := src.get_rgb_texture()
	if tex == null:
		return null
	var win := tex.get_image()
	if win == null or win.is_empty():
		return null
	if win.is_compressed():
		win.decompress()
	var r := Rect2i(roundi(float(rect.get("x", 0))), roundi(float(rect.get("y", 0))), roundi(float(rect.get("w", 0))),
			roundi(float(rect.get("h", 0)))).intersection(Rect2i(Vector2i.ZERO, win.get_size()))
	if r.size.x < 8 or r.size.y < 8:
		return null
	var out := win.get_region(r)
	out.convert(Image.FORMAT_RGB8)
	return out


static func expression(op: String, at: Vector2) -> String:
	return "/*vrplayer:picture-%s*/%s(%s, %d, %d)" % [op, SCRIPT, JSON.stringify(op), roundi(at.x), roundi(at.y)]


# --- The legend --------------------------------------------------------------------------------------------------------

func _hover(delta: float) -> void:
	var wp: Node = main.get("window_pointer")
	var pointing: bool = wp != null and wp.is_active() and bool(wp.get("cursor").mode) and wp.has_cursor()
	if not pointing:
		if over_image:
			_set_over(false)
		return
	_hover_wait -= delta
	var pos: Vector2 = wp.get("cursor").pos
	var moved := pos.distance_to(_hover_at) > 2.0
	if _hover_busy or _hover_wait > 0.0 or (not moved and _hover_wait > -HOVER_STILL):
		return
	var s: Object = _session()
	if s == null or not bool(s.call("is_open")):
		if over_image:
			_set_over(false)
		return
	_hover_busy = true
	_hover_wait = HOVER_MOVING
	_hover_at = pos
	var r: Dictionary = await s.call("evaluate", get_tree(), expression("over", pos))
	_hover_busy = false
	var d: Variant = r.get("value")
	_set_over(d is Dictionary and bool((d as Dictionary).get("image", false)))


func _set_over(on: bool) -> void:
	if on == over_image:
		return
	over_image = on
	if main != null and main.has_method("update_controller_labels"):
		main.update_controller_labels()


# --- 2. The clipboard ------------------------------------------------------------------------------------------------

func _clip_image() -> Image:
	var v: Variant = clipboard.call() if clipboard.is_valid() else null
	return v if v is Image and not (v as Image).is_empty() else null


func _clip_hash() -> String:
	var img := _clip_image()
	if img == null:
		return ""
	return ("%d %d " % [img.get_width(), img.get_height()]) + img.get_data().slice(0, 4096).hex_encode().md5_text() \
			+ str(img.get_data().size())


func _check_clipboard() -> void:
	var key := _clip_hash()
	if key == "" or key == _clip_seen:
		return
	_clip_seen = key
	var info: Dictionary = browser().page_info() if browser() != null else {}
	last = _keep(_clip_image(), PictureLibrary.clean_title(str(info.get("title", ""))), str(info.get("url", "")),
			"clipboard", "clipboard")


# --- 3. Downloads ----------------------------------------------------------------------------------------------------

func _downloads() -> String:
	return downloads_dir if downloads_dir != "" else OS.get_system_dir(OS.SYSTEM_DIR_DOWNLOADS)


## Picture files in Downloads: path -> modified time.
func _download_files() -> Dictionary:
	var dir := _downloads()
	var out := {}
	if dir == "" or not DirAccess.dir_exists_absolute(dir):
		return out
	for f in DirAccess.get_files_at(dir):
		if f.get_extension().to_lower() in PICTURE_TYPES:
			out[dir.path_join(f)] = FileAccess.get_modified_time(dir.path_join(f))
	return out


func _check_downloads() -> void:
	var now := _download_files()
	for path: String in now:
		if _down_seen.get(path, -1) == now[path] or int(now[path]) < _down_since:
			continue
		_down_seen[path] = now[path]
		if FileAccess.get_size(path) > MAX_FILE:
			continue
		var img := PictureLibrary.decode(FileAccess.get_file_as_bytes(path))
		if img == null:
			# Still being written, or not a picture after all: tried again when it changes.
			_down_seen[path] = -2 if FileAccess.get_size(path) == 0 else now[path]
			continue
		var info: Dictionary = browser().page_info() if browser() != null else {}
		var title := PictureLibrary.clean_title(path.get_file().get_basename().replace("_", " ").replace("-", " "))
		last = _keep(img, title, str(info.get("url", "")), "downloads", "file")


# --- Keeping ---------------------------------------------------------------------------------------------------------

func _keep(img: Image, title: String, page: String, how: String, via: String) -> Dictionary:
	var r := PictureLibrary.add(img, {"title": title, "source_page": page if page.begins_with("http") else "",
			"how": how})
	if not bool(r.get("ok", false)):
		_note(TranslationServer.translate("That picture could not be kept"))
		return {"ok": false, "why": "failed", "how": how, "via": via}
	if bool(r["new"]):
		_note(TranslationServer.translate("Picture kept: %s") % r["title"])
	else:
		_note(TranslationServer.translate("Already in your pictures: %s") % r["title"])
	var oc := load("res://scripts/assistant/object_commands.gd") as GDScript
	oc.call("_sync_tab")
	return {"ok": true, "id": r["id"], "title": r["title"], "new": r["new"], "how": how, "via": via}


func _note(text: String) -> void:
	var ui: Object = main.get("ui") if main != null else null
	if ui != null and ui.has_method("notify"):
		ui.notify(text)
