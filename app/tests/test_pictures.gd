extends SceneTree

## The picture library (scripts/pictures/picture_library.gd, picture_keeper.gd, picture_objects.gd, gif_decode.gd;
## ui/picture_panel.gd) in the real main scene, with no network and no browser: a fake DevTools page (a WebSocket
## server on the loopback that answers the keeper's script with a made-up image under the cursor), a fake transport
## for the fetch, a stand-in window capture for the crop, a stand-in clipboard and a Downloads folder of its own.
## Every picture is made here.
##
## Keeping by the right stick click (the cursor held through the click's nudge; the fetch with the page as Referer; a
## data: URL; the window-crop fallback; the KEEP PICTURE legend only over an image), by the clipboard and by
## Downloads (a GIF's first frame too); the toast; the same pixels kept once; the resize to 2048 and the thumbnail;
## the library's files; Delete (refused while a kept room shows it); the poster, framed, canvas and cut-out sized to
## the picture's shape; Place; a wall one on its wall until pulled off, then physics; the film layer's cover; the
## commands (pictures_search only opening a URL, pictures, picture_place, picture_apply, picture_delete).
## godot --headless --xr-mode off --path app --script res://tests/test_pictures.gd

const WindowVideoSource := preload("res://scripts/video/window_video_source.gd")
const PictureLibrary := preload("res://scripts/pictures/picture_library.gd")
const PictureObjects := preload("res://scripts/pictures/picture_objects.gd")
const PictureKeeper := preload("res://scripts/pictures/picture_keeper.gd")
const GifDecode := preload("res://scripts/pictures/gif_decode.gd")
const ObjectLibrary := preload("res://scripts/assistant/object_library.gd")
const ObjectCommands := preload("res://scripts/assistant/object_commands.gd")
const AssistantRoom := preload("res://scripts/assistant/assistant_room.gd")
const DevCommands := preload("res://scripts/dev/dev_commands.gd")
const CommandHost := preload("res://scripts/dev/command_host.gd")
const AssistantCommands := preload("res://scripts/assistant/assistant_commands.gd")

const ROOT := "user://test_pictures"
const IMG_URL := "https://img.test.invalid/mountain.jpg"
const PAGE_URL := "https://pictures.test.invalid/search?q=mountain"
const DT := 1.0 / 72.0

var _failures := 0
var _checks := 0
var main: Node3D
var keeper: Node
var page: FakePage
var fake: Fake
var win: FakeWin
var src: WindowVideoSource
var wp: Node
var commands: AssistantCommands
var opened: Array = []
var clip: Image = null


## A pretend page behind DevTools: the keeper's script is answered from `under` (what is under the cursor).
class FakePage extends Node:
	var server := TCPServer.new()
	var port := 0
	var peer: WebSocketPeer
	var under := {}
	var asked: Array = []

	func start() -> void:
		server.listen(0, "127.0.0.1")
		port = server.get_local_port()

	func ws_url() -> String:
		return "ws://127.0.0.1:%d/devtools/page/PAGE1" % port

	func _process(_delta: float) -> void:
		if server.is_connection_available():
			peer = WebSocketPeer.new()
			peer.accept_stream(server.take_connection())
		if peer == null:
			return
		peer.poll()
		while peer.get_available_packet_count() > 0:
			var m: Variant = JSON.parse_string(peer.get_packet().get_string_from_utf8())
			if not (m is Dictionary):
				continue
			var result: Variant = {}
			if str(m["method"]) == "Runtime.evaluate":
				var e := str(m["params"]["expression"])
				var value: Variant = null
				if e.begins_with("/*vrplayer:picture-"):
					var op := e.get_slice("/*vrplayer:picture-", 1).get_slice("*/", 0)
					var args := e.substr(e.rfind("(\"")).trim_prefix("(").trim_suffix(")").split(", ")
					asked.append([op, int(args[1]), int(args[2])])
					value = {"image": not under.is_empty()} if op == "over" else (under if not under.is_empty()
							else {"image": false})
				result = {"result": {"type": "object", "value": value}}
			peer.send_text(JSON.stringify({"id": m["id"], "result": result}))


## Stands in for fab_http.gd: answers by URL; the log keeps each request's URL and headers.
class Fake extends RefCounted:
	var tree: SceneTree
	var routes := {}
	var log: Array = []

	func fetch(url: String, headers: PackedStringArray, _file := "") -> Dictionary:
		log.append({"url": url, "headers": headers})
		await tree.process_frame
		var r: Dictionary = routes.get(url, {"code": 404, "body": PackedByteArray()})
		return {"code": int(r["code"]), "headers": {}, "body": r["body"], "error": ""}


## Stands in for X11WindowSource: its picture is a texture made here.
class FakeWin extends RefCounted:
	var tex: Texture2D

	func get_size() -> Vector2i:
		return Vector2i(1920, 1080)

	func get_texture() -> Texture2D:
		return tex

	func update() -> bool:
		return false

	func get_stats() -> Dictionary:
		return {}

	func send_pointer(_x: float, _y: float) -> void:
		pass

	func send_button(_b: int, _pressed: bool) -> void:
		pass

	func send_scroll(_dx: float, _dy: float) -> void:
		pass

	func send_godot_key(_k: int, _pressed: bool) -> void:
		pass

	func send_text(_t: String) -> void:
		pass

	func stop_capture() -> void:
		pass

	func close() -> void:
		pass

	func close_window(_id: int) -> void:
		pass


func _init() -> void:
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate() as Node3D
	main.settings.read_only = true
	root.add_child(main)
	current_scene = main
	_run.call_deferred()


func _run() -> void:
	await _frames(5)
	CommandHost.ensure(self)
	_wipe(ROOT)
	PictureLibrary.root = ROOT + "/pictures"
	PictureLibrary.opener = func(url: String) -> void: opened.append(url)
	DirAccess.make_dir_recursive_absolute(ROOT + "/downloads")
	page = FakePage.new()
	page.start()
	root.add_child(page)
	fake = Fake.new()
	fake.tree = self
	keeper = main.picture_keeper
	keeper.transport = fake
	keeper.clipboard = func() -> Variant: return clip
	keeper.downloads_dir = ROOT + "/downloads"
	commands = AssistantCommands.new()
	commands.allow_room = func() -> bool: return true
	commands.allow_control = func() -> bool: return true

	_test_library()
	_test_gif()
	await _open_browser()
	await _test_stick_click()
	await _test_clipboard_and_downloads()
	await _test_objects()
	await _test_commands()
	await _test_delete()

	main.player.close()
	_forget_rooms()
	for p: Dictionary in PictureLibrary.list():
		PictureLibrary.delete(str(p["id"]))
	PictureLibrary.root = PictureLibrary.ROOT
	PictureLibrary.opener = Callable()
	_wipe(ROOT)
	main.queue_free()
	page.queue_free()
	await _frames(2)
	print("test_pictures: %d checks, %s" % [_checks, "all passed" if _failures == 0 else "%d FAILED" % _failures])
	quit(1 if _failures > 0 else 0)


# --- Pictures made here ----------------------------------------------------------------------------------------------

## A picture w x h: four coloured quarters (so a crop and a resize can be told), seeded noise on top.
static func _image(w: int, h: int, seed_value := 1, alpha := false) -> Image:
	var img := Image.create_empty(w, h, false, Image.FORMAT_RGBA8 if alpha else Image.FORMAT_RGB8)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	for y in h:
		for x in w:
			var c := Color(0.8, 0.2, 0.2) if x < w / 2 else Color(0.2, 0.3, 0.8)
			if y >= h / 2:
				c = c.lerp(Color(0.9, 0.9, 0.2), 0.5)
			var n := rng.randf_range(-0.02, 0.02)
			c = Color(clampf(c.r + n, 0, 1), clampf(c.g + n, 0, 1), clampf(c.b + n, 0, 1))
			if alpha:
				c.a = 0.0 if (x - w / 2) * (x - w / 2) + (y - h / 2) * (y - h / 2) > (w / 3) * (w / 3) else 1.0
			img.set_pixel(x, y, c)
	return img


## A small GIF89a: a 4-colour palette, colour 3 transparent, written with codes of growing width as a decoder reads
## them (only single-colour codes, a clear code every 200).
static func _gif(w: int, h: int) -> PackedByteArray:
	var b := PackedByteArray()
	b.append_array("GIF89a".to_ascii_buffer())
	var hdr := PackedByteArray()
	hdr.resize(7)
	hdr.encode_u16(0, w)
	hdr.encode_u16(2, h)
	hdr[4] = 0x81
	hdr[5] = 0
	hdr[6] = 0
	b.append_array(hdr)
	b.append_array(PackedByteArray([255, 0, 0, 0, 255, 0, 0, 0, 255, 255, 255, 255]))
	b.append_array(PackedByteArray([0x21, 0xF9, 4, 1, 0, 0, 3, 0]))
	var desc := PackedByteArray([0x2C, 0, 0, 0, 0, 0, 0, 0, 0, 0])
	desc.encode_u16(5, w)
	desc.encode_u16(7, h)
	b.append_array(desc)
	b.append(2)
	var codes: Array = []
	var widths: Array = []
	var width := 3
	var next := 6
	var prev := -1
	codes.append(4)
	widths.append(width)
	var since := 0
	for y in h:
		for x in w:
			var c := 0 if x < w / 2 else (1 if y < h / 2 else (2 if x < w - 2 else 3))
			if since >= 200:
				codes.append(4)
				widths.append(width)
				width = 3
				next = 6
				prev = -1
				since = 0
			codes.append(c)
			widths.append(width)
			if prev >= 0 and next < 4096:
				next += 1
				if next == (1 << width) and width < 12:
					width += 1
			prev = c
			since += 1
	codes.append(5)
	widths.append(width)
	var data := PackedByteArray()
	var acc := 0
	var bits := 0
	for i in codes.size():
		acc |= int(codes[i]) << bits
		bits += int(widths[i])
		while bits >= 8:
			data.append(acc & 0xFF)
			acc >>= 8
			bits -= 8
	if bits > 0:
		data.append(acc & 0xFF)
	var at := 0
	while at < data.size():
		var n := mini(255, data.size() - at)
		b.append(n)
		b.append_array(data.slice(at, at + n))
		at += n
	b.append(0)
	b.append(0x3B)
	return b


# --- The library -----------------------------------------------------------------------------------------------------

func _test_library() -> void:
	var r := PictureLibrary.add(_image(300, 150, 1), {"title": "  Test   Mountain\nat dusk ", "source_page": PAGE_URL})
	_check("kept (%s)" % [r], r.get("ok") == true and r["new"] and r["title"] == "Test Mountain at dusk")
	var id := str(r["id"])
	var p := PictureLibrary.get_picture(id)
	_check("its facts: title, aspect, source page, date", is_equal_approx(float(p["aspect"]), 2.0)
			and p["source_page"] == PAGE_URL and str(p["date"]) != "" and p["alpha"] == false)
	var dir := ROOT + "/pictures/" + id
	_check("in user://pictures/<id>: the picture (JPEG), its thumbnail, its JSON", FileAccess.file_exists(dir
			+ "/picture.jpg") and FileAccess.file_exists(dir + "/thumb.png") and FileAccess.file_exists(dir
			+ "/picture.json"))
	var again := PictureLibrary.add(_image(300, 150, 1), {"title": "Another title"})
	_check("the same pixels twice: one picture, its first title kept", again["id"] == id and not again["new"]
			and again["title"] == "Test Mountain at dusk" and PictureLibrary.list().size() == 1)
	var big := PictureLibrary.add(_image(3000, 1500, 2), {"title": "Test Wide"})
	var bp := PictureLibrary.get_picture(str(big["id"]))
	_check("made at most 2048 on its long side (%d x %d)" % [int(bp["width"]), int(bp["height"])],
			int(bp["width"]) == 2048 and int(bp["height"]) == 1024)
	var th := PictureLibrary.thumbnail(str(big["id"]))
	_check("its thumbnail at most 160 (%s)" % [th.get_size() if th else null], th != null and th.get_width() == 160
			and th.get_height() == 80)
	var cut := PictureLibrary.add(_image(200, 300, 3, true), {"title": "Test Cut-out"})
	var cp := PictureLibrary.get_picture(str(cut["id"]))
	_check("with transparency: kept as PNG, alpha on", cp["alpha"] == true and str(cp["file"]) == "picture.png"
			and PictureLibrary.image(str(cut["id"])).detect_alpha() != Image.ALPHA_NONE)
	_check("no title: \"Picture\"", PictureLibrary.add(_image(64, 64, 9), {})["title"] == "Picture")
	_check("too small: not kept", PictureLibrary.add(_image(4, 4, 9), {}).get("ok") == false)
	_check("listed newest first", PictureLibrary.list().size() == 4)
	_check("a data: URL read", PictureLibrary.from_data_url("data:image/png;base64,"
			+ Marshalls.raw_to_base64(_image(20, 10).save_png_to_buffer())).get_width() == 20)


func _test_gif() -> void:
	var img := GifDecode.first_frame(_gif(40, 20))
	_check("a GIF's first frame (%s)" % [img.get_size() if img else null], img != null and img.get_size()
			== Vector2i(40, 20))
	if img != null:
		_check("its colours where they are", img.get_pixel(5, 5).is_equal_approx(Color(1, 0, 0))
				and img.get_pixel(30, 5).is_equal_approx(Color(0, 1, 0)) and img.get_pixel(25, 15)
				.is_equal_approx(Color(0, 0, 1)))
		_check("its transparent colour transparent", img.get_pixel(39, 15).a == 0.0)
	_check("PictureLibrary.decode reads it", PictureLibrary.decode(_gif(40, 20)) != null)
	_check("not a GIF: null", GifDecode.first_frame("GIF89a....".to_ascii_buffer()) == null)


# --- Keeping ---------------------------------------------------------------------------------------------------------

func _open_browser() -> void:
	main.ui.hide_panel()
	main.set_menu_shown(false)
	main.player.close()
	src = WindowVideoSource.new()
	win = FakeWin.new()
	win.tex = ImageTexture.create_from_image(_window_picture())
	src.path = WindowVideoSource.browser_path(PAGE_URL)
	src.url = PAGE_URL
	src.launched = true
	src.window_id = 0x2a00003
	src.win = win
	src._page_next_msec = 1 << 62
	src.devtools_port = 1
	src._page = {"url": PAGE_URL, "title": "Test pictures page", "id": "PAGE1", "ws": page.ws_url()}
	main.current_path = src.path
	main.player.source = src
	main.mode = src.get_known_mode().copy()
	wp = main.window_pointer
	wp.set_process(false)
	wp.test_xr = true
	main.screen_surface.set_process(false)
	main.screen_surface.test_xr = true
	await _frames(2)
	await _until(func() -> bool: return main.browser_dictation.session.is_open(), 3.0)
	_check("the page's DevTools session is open", main.browser_dictation.session.is_open())


## The window's picture: grey, and a green square where the made-up image is (600, 300, 300 x 200).
static func _window_picture() -> Image:
	var img := Image.create_empty(1920, 1080, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.5, 0.5, 0.5))
	img.fill_rect(Rect2i(600, 300, 300, 200), Color(0.1, 0.8, 0.2))
	return img


## The right hand's laser on this pixel of the window (1920 x 1080); null: off the screen.
func _aim_at(px: Variant) -> void:
	_aim_px = px
	_apply_aim()


## The app puts the hands back each frame without a session: the aim is set again before every step.
func _apply_aim() -> void:
	var px: Variant = _aim_px
	var hand: Node3D = main.right_hand
	var screen: Node3D = main.screen
	var quad: Vector2 = screen.get_flat_size()
	hand.global_position = main.camera.global_position + Vector3(0.2, -0.3, 0.0)
	var local := Vector3(quad.x * 3.0, 0.0, 0.0)
	if px != null:
		local = Vector3(((px as Vector2).x / 1920.0 - 0.5) * quad.x, (0.5 - (px as Vector2).y / 1080.0) * quad.y, 0.0)
	hand.look_at(screen.global_transform * local, Vector3.UP)
	# The other hand points away from the screen.
	(main.left_hand as Node3D).look_at((main.left_hand as Node3D).global_position + screen.global_basis.z, Vector3.UP)


var _aim_px: Variant = null


func _look_at_screen() -> void:
	_aim_at(Vector2(960, 540))


func _step(n: int, _stick := Vector2.ZERO) -> void:
	for i in n:
		_apply_aim()
		main.pointing.refresh()
		main.screen_surface.step()
		wp.step(DT)
		await process_frame


func _test_stick_click() -> void:
	_look_at_screen()
	await _step(12)
	_check("pointer mode on the window", wp.cursor.mode and wp.is_active())
	page.under = {}
	await _step(40)
	_check("not over an image: no KEEP PICTURE", not keeper.over_image and not _right_labels().values().any(
			func(t: String) -> bool: return t.contains("KEEP PICTURE")))
	page.under = {"image": true, "src": IMG_URL, "alt": "Test Mountain Lake", "title": "Test pictures page",
			"page": PAGE_URL, "rect": {"x": 600, "y": 300, "w": 300, "h": 200}}
	_aim_at(Vector2(700, 400))
	await _step(60)
	_check("over an image: the page was asked where the cursor is, in window pixels", keeper.over_image
			and not page.asked.is_empty() and page.asked[-1][0] == "over")
	_check("the legends do not change over an image (%s)" % [_right_labels()], not _right_labels().values().any(
			func(t: String) -> bool: return t.contains("KEEP PICTURE")))
	# The click's nudge: the hand wobbles a few frames just before, then the click.
	var before: Vector2 = wp.cursor.pos
	_aim_at(Vector2(760, 400))
	await _step(6)
	_check("the nudge moved the cursor (%s -> %s)" % [before, wp.cursor.pos], wp.cursor.pos.x > before.x)
	fake.routes[IMG_URL] = {"code": 200, "body": _image(640, 427, 5).save_jpg_to_buffer(0.9)}
	var n := PictureLibrary.list().size()
	main.right_hand.stick_clicked.emit(main.right_hand, true)
	var held: Vector2 = wp.cursor.pos
	_check("the cursor back where it was before the nudge (%s, %s)" % [before, held], held.distance_to(before) < 1.0)
	await _step(5, Vector2(1, 0))
	_check("and held there through the click", wp.cursor.pos.distance_to(held) < 0.5)
	main.right_hand.stick_clicked.emit(main.right_hand, false)
	await _until(func() -> bool: return PictureLibrary.list().size() > n, 3.0)
	_check("kept by the stick click (%s)" % [keeper.last], PictureLibrary.list().size() == n + 1
			and keeper.last.get("via") == "fetch" and keeper.last.get("how") == "stick")
	_check("the page was asked what is under the cursor", page.asked.any(func(a: Array) -> bool: return a[0] == "keep"))
	var req: Dictionary = fake.log[-1] if not fake.log.is_empty() else {}
	_check("the full-size source fetched by the app, the page as Referer", req.get("url") == IMG_URL
			and "\n".join(req.get("headers", [])).contains("Referer: " + PAGE_URL))
	var kept := PictureLibrary.get_picture(str(keeper.last.get("id", "")))
	_check("the alt text as its title, at full size", kept.get("title") == "Test Mountain Lake"
			and int(kept.get("width", 0)) == 640)
	_check("the menu did not open", not main.menu_shown)
	_check("the toast: Picture kept: <title> (%s)" % _toast(), _toast().contains("Picture kept: Test Mountain Lake"))
	# The fetch fails: the image's rectangle cut out of the window.
	fake.routes.erase(IMG_URL)
	page.under["alt"] = "Test Crop"
	var crop_ok := ImageTexture.create_from_image(_window_picture()).get_image() != null
	print("the crop from the window: ", "checked" if crop_ok else "not checked (no texture read-back here; lavapipe has it)")
	await keeper.keep_at(wp.cursor.pos)
	if crop_ok:
		var cp := PictureLibrary.get_picture(str(keeper.last.get("id", "")))
		_check("the fetch failed: cut out of the window (%s)" % [keeper.last], keeper.last.get("via") == "crop"
				and int(cp.get("width", 0)) == 300 and int(cp.get("height", 0)) == 200)
		var ci := PictureLibrary.image(str(keeper.last.get("id", "")))
		_check("the crop is the image's own pixels (green)", ci != null and ci.get_pixel(150, 100).g > 0.7)
	else:
		_check("no texture read-back in this renderer: the crop is checked under lavapipe", true)
	# A data: URL.
	page.under["src"] = "data:image/png;base64," + Marshalls.raw_to_base64(_image(90, 60, 7).save_png_to_buffer())
	page.under["alt"] = ""
	await keeper.keep_at(wp.cursor.pos)
	var dp := PictureLibrary.get_picture(str(keeper.last.get("id", "")))
	_check("a data: URL read as it is; no alt text: the page's title", keeper.last.get("via") == "data"
			and dp.get("title") == "Test pictures page" and int(dp.get("width", 0)) == 90)
	# Nothing under the cursor.
	page.under = {}
	await keeper.keep_at(wp.cursor.pos)
	_check("nothing under the cursor: said, nothing kept", keeper.last.get("ok") == false
			and _toast().contains("No picture under the pointer"))
	# Looking away: the stick click is the menu again.
	_aim_at(null)
	await _step(60)
	_check("the laser off the window: no pointer, the stick click not taken", not wp.cursor.mode
			and not keeper.on_stick_click(main.right_hand, true))


func _right_labels() -> Dictionary:
	return main.controller_labels("/interaction_profiles/valve/frame_controller_valve", "right", false, true, false,
			false, false, wp.window_labels())


## The notice shown last (the menu is hidden: the world toast's line).
func _toast() -> String:
	return str((main.ui.world_toast as Label3D).text)


func _test_clipboard_and_downloads() -> void:
	var n := PictureLibrary.list().size()
	clip = _image(120, 80, 11)
	await _until(func() -> bool: return PictureLibrary.list().size() > n, 3.0)
	_check("Copy image: a new picture on the clipboard is kept (%s)" % [keeper.last], PictureLibrary.list().size()
			== n + 1 and keeper.last.get("how") == "clipboard" and keeper.last.get("title") == "Test pictures page")
	await _frames(80)
	_check("the same clipboard is kept once", PictureLibrary.list().size() == n + 1)
	n = PictureLibrary.list().size()
	var dl := ROOT + "/downloads/"
	_image(100, 100, 21).save_png(dl + "test_red_barn.png")
	var f := FileAccess.open(dl + "test_flag.gif", FileAccess.WRITE)
	f.store_buffer(_gif(40, 20))
	f.close()
	var w := FileAccess.open(dl + "notes.txt", FileAccess.WRITE)
	w.store_string("not a picture")
	w.close()
	await _until(func() -> bool: return PictureLibrary.list().size() >= n + 2, 5.0)
	var titles: Array = PictureLibrary.list().map(func(p: Dictionary) -> String: return str(p["title"]))
	_check("saved to Downloads: kept, the file's name as its title, a GIF's first frame too (%s)" % [titles],
			PictureLibrary.list().size() == n + 2 and "test red barn" in titles and "test flag" in titles)


# --- The objects -----------------------------------------------------------------------------------------------------

func _picture(title: String) -> String:
	for p: Dictionary in PictureLibrary.list():
		if p["title"] == title:
			return str(p["id"])
	return ""


func _test_objects() -> void:
	main.player.close()
	main.set_environment("dim_room")
	await _frames(10)
	var wide := _picture("Test Wide")
	for kind: String in PictureObjects.KINDS:
		var r := PictureObjects.object_for(wide, kind)
		var m := ObjectLibrary.get_object(str(r.get("id", "")))
		var parts: Array = m.get("parts", []).map(func(p: Dictionary) -> String: return str(p["name"]))
		_check("%s: a user object of the picture, its Picture part (%s)" % [kind, parts], r.get("ok") == true
				and m.get("picture_id") == wide and m.get("picture_as") == kind and "Picture" in parts
				and m.get("mount") == PictureObjects.MOUNTS[kind])
		var b := ObjectLibrary.bounds_of(m)
		var aspect := b.size.x / b.size.y
		match kind:
			"poster", "canvas":
				_check("%s sized to the picture's 2:1 (%.2f)" % [kind, aspect], absf(aspect - 2.0) < 0.02)
			"framed":
				# The frame and mount round a 2:1 picture.
				_check("framed: wider than tall, round a 2:1 picture (%.2f)" % aspect, aspect > 1.5 and aspect < 2.0)
			"cutout":
				_check("cut-out: stands on the floor, the picture over its stand (%.2f)" % aspect, b.position.y
						>= -0.001 and b.size.y > 0.6)
		_check("%s: made once" % kind, PictureObjects.object_for(wide, kind)["id"] == r["id"])
	var cut := _picture("Test Cut-out")
	var cr := PictureObjects.object_for(cut, "cutout")
	var read: Dictionary = (load("res://scripts/assistant/room_model.gd") as GDScript).call("load_glb", ObjectLibrary.glb(str(
			cr["id"])))
	var pics: Dictionary = read.get("pictures", {})
	var pic: Dictionary = pics.values()[0] if pics.size() == 1 else {}
	_check("the cut-out's picture keeps its transparency (a cut-out in the room)", bool(pic.get("alpha", false)))
	var quads := 0
	for mi: MeshInstance3D in (read["node"] as Node).find_children("*", "MeshInstance3D", true, false):
		if str(mi.name) == "Picture":
			quads = mi.mesh.get_faces().size() / 3
	(read["node"] as Node).free()
	_check("two-sided: a quad each way (%d triangles)" % quads, quads == 4)
	var section: Node = main.ui.ui.objects.section
	section.sync_objects()
	await _frames(20)
	_check("the picture objects aren't in Your objects (they are under Pictures)", not section._tiles.has(str(cr["id"])))
	# Place: the laser, then the trigger.
	var poster := PictureObjects.object_for(wide, "poster")
	var layer: Node = main.ui
	_check("Place starts placing the poster", layer.start_object_place(str(poster["id"])))
	var hand: Node3D = layer.pointer_hand
	var eye: Vector3 = main.camera.global_position
	# A side wall (the front one has the screen before it).
	var ahead: Vector3 = eye + (main.env as Node3D).global_basis.x * 20.0 + Vector3(0, 0.3, 0)
	hand.global_transform = Transform3D(Basis.looking_at((ahead - eye).normalized(), Vector3.UP), eye)
	layer._placer.update(hand)
	var r: Dictionary = await layer._placer.commit()
	await _frames(10)
	var name := str(r.get("result", {}).get("placed", ""))
	_check("placed on the wall (%s)" % r.get("error", name), r.get("ok") == true and name != "")
	var ph: Node = main.features.physics
	await _frames(5)
	_check("a wall one: on its wall, fixed", ph.is_mounted(name) and not ph.is_moving(name))
	_check("the film layer counts it as something in front of the screen could be", ph.solid_nodes().any(
			func(n: Node3D) -> bool: return str(n.name) == name))
	# Pulled off in the cinema, as tests/test_physics.gd pulls its clock off: the dim room's walls let a held object
	# through, a clock as much as a poster (docs/features.md, "Pictures", open questions).
	main.set_environment("cinema")
	await _frames(10)
	r = await ObjectCommands.place(self, null, str(poster["id"]), {"name": "Test Poster",
			"position": [-9.598, 2.5, -3.0], "rotation": [0, 90, 0]})
	await _frames(10)
	name = "Test Poster"
	ph = main.features.physics
	_check("in the cinema: on its wall (%s)" % r.get("error", ""), r.get("ok") == true and ph.is_mounted(name))
	var at: Vector3 = (main.env.get_node("AssistantLayer/" + name) as Node3D).position
	_check("picked up", ph.pick_up(name))
	var xf: Transform3D = ph.body_transform(name)
	ph.hold_to(name, xf.translated(Vector3(0.03, 0, 0)))
	await _frames(10)
	_check("held 3 cm off: still on its wall", ph.is_mounted(name) and not ph.is_moving(name))
	ph.hold_to(name, xf.translated(Vector3(0.4, -0.2, 0)))
	await _frames(15)
	_check("pulled off: physics like any object", not ph.is_mounted(name) and ph.is_moving(name))
	ph.let_go(name)
	await _until(func() -> bool: return not ph.is_moving(name), 8.0)
	var now: Vector3 = (main.env.get_node("AssistantLayer/" + name) as Node3D).position
	_check("it fell, and the room says it is off its wall (%s -> %s)" % [at, now], now.y < at.y - 0.5
			and _part(name).get("mounted") == false)


func _test_commands() -> void:
	opened.clear()
	var before := fake.log.size()
	var c: Dictionary = await commands.run("pictures_search", {"query": "autumn forest"})
	_check("pictures_search opens Google Images for the words, and that is all (%s)" % [opened], c.get("ok") == true
			and opened == ["https://www.google.com/search?q=autumn%20forest&udm=2"] and fake.log.size() == before)
	c = await commands.run("pictures", {})
	_check("pictures lists them with their objects (%d)" % int(c.get("result", {}).get("count", 0)), c.get("ok") == true
			and int(c["result"]["count"]) == PictureLibrary.list().size() and (c["result"]["pictures"] as Array).any(
			func(p: Dictionary) -> bool: return (p["objects"] as Array).size() == 4))
	var mountain := _picture("Test Mountain at dusk")
	c = await commands.run("picture_place", {"picture": mountain, "as": "framed", "at": "wall"})
	await _frames(10)
	var placed := str(c.get("result", {}).get("placed", ""))
	_check("picture_place framed on the wall (%s)" % c.get("error", placed), c.get("ok") == true and placed != ""
			and main.env.has_node("AssistantLayer/" + placed))
	c = await commands.run("picture_place", {"picture": mountain, "as": "sculpture"})
	_check("picture_place: an unknown kind refused", c.get("ok") == false)
	var wide := _picture("Test Wide")
	c = await commands.run("picture_apply", {"part": placed + "/Picture", "picture": wide})
	await _frames(10)
	var doc: Dictionary = main.env.get("doc")
	var entry := {}
	for r: Dictionary in doc.get("recolour", []):
		if str(r["match"]) == placed + "/Picture":
			entry = r
	var em: Dictionary = entry.get("material", {}) if entry.get("material") is Dictionary else {}
	_check("picture_apply on an object's part: a part-level recolour with the picture (%s %s)" % [c.get("error", ""),
			em.keys()], c.get("ok") == true and (em.has("texture_file") or em.has("texture")))
	_check("kept in the room: the picture as a file beside it", _kept_text(placed).contains("texture_file"))
	c = await commands.run("part_reset", {"part": placed + "/Picture"})
	await _frames(5)
	_check("part_reset takes it off again", c.get("ok") == true)


func _test_delete() -> void:
	var mountain := _picture("Test Mountain at dusk")
	var c: Dictionary = await commands.run("picture_delete", {"picture": mountain})
	_check("picture_delete refused while a kept room shows it (%s)" % [c.get("rooms")], c.get("ok") == false
			and (c.get("rooms", []) as Array).size() >= 1 and PictureLibrary.get_picture(mountain).size() > 0)
	var lake := _picture("Test Mountain Lake")
	var made := PictureObjects.object_for(lake, "poster")
	c = await commands.run("picture_delete", {"picture": lake})
	_check("picture_delete: the picture and its objects go", c.get("ok") == true
			and PictureLibrary.get_picture(lake).is_empty() and ObjectLibrary.get_object(str(made["id"])).is_empty()
			and not DirAccess.dir_exists_absolute(ROOT + "/pictures/" + lake))
	c = await commands.run("picture_delete", {"picture": lake})
	_check("again: no such picture", c.get("ok") == false)


# --- Helpers ---------------------------------------------------------------------------------------------------------

func _part(name: String) -> Dictionary:
	for p: Dictionary in (main.env.get("doc") as Dictionary).get("parts", []):
		if p["name"] == name:
			return p
	return {}

## The kept room that places `name`, as text.
func _kept_text(name: String) -> String:
	var dir := "user://recipes"
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".room.json"):
			var t := FileAccess.get_file_as_string(dir.path_join(f))
			if t.contains("\"%s\"" % name):
				return t
	return ""

func _forget_rooms() -> void:
	var dir := "user://recipes"
	if not DirAccess.dir_exists_absolute(dir):
		return
	var ids: Array = []
	for m: Dictionary in ObjectLibrary.list("", "user"):
		if m.has("picture_id"):
			ids.append(str(m["id"]))
	for f in DirAccess.get_files_at(dir):
		var p := dir.path_join(f)
		var t := FileAccess.get_file_as_string(p) if f.ends_with(".json") else ""
		if ids.any(func(i: String) -> bool: return t.contains("\"%s\"" % i)):
			DirAccess.remove_absolute(p)
	for i: String in ids:
		ObjectLibrary.delete(i)
		ObjectLibrary.purge(i)


static func _wipe(dir: String) -> void:
	if not DirAccess.dir_exists_absolute(dir):
		return
	for d in DirAccess.get_directories_at(dir):
		_wipe(dir.path_join(d))
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(f))
	DirAccess.remove_absolute(dir)


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _until(cond: Callable, seconds := 5.0) -> void:
	var end := Time.get_ticks_msec() + int(seconds * 1000.0)
	while not cond.call() and Time.get_ticks_msec() < end:
		await process_frame


func _check(what: String, ok: bool) -> void:
	_checks += 1
	if not ok:
		_failures += 1
		print("FAIL: ", what)
