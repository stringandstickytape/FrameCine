extends RefCounted

## The picture library (docs/features.md "Pictures", docs/assistant.md "Pictures"): pictures the viewer kept while
## browsing (scripts/pictures/picture_keeper.gd: the stick click on an image, Chromium's Copy image, a save to
## Downloads), for posters, frames, canvases and cut-outs (picture_objects.gd) and for any part of the room
## (apply to a part, scripts/assistant/part_apply.gd).
##
## Each in user://pictures/<id>/: picture.jpg (or .png when it has transparency) at most MAX_SIDE on its long side,
## thumb.png, picture.json {id, title, aspect, width, height, alpha, source_page, date}. The id is a hash of the
## pixels, so the same picture is kept once. Titles are content (the page's alt text or title), never translated.
## Ownership, in the user's words: keeping them for personal use on your own headset is your call; the app never
## uploads or shares them, and none go into the repository or a release. Source pages stay in this folder: never in
## a log line.
##
##   add(image, {title, source_page}) -> {ok, id, title, new} or {ok: false, error}
##   list() -> [{id, title, aspect, width, height, alpha, date}] newest first     get_picture(id) -> {} if none
##   image(id), thumbnail(id) -> Image or null     file_bytes(id) -> the stored file (a part's texture)
##   decode(bytes) -> Image or null (JPEG, PNG, WebP, a GIF's first frame, BMP)
##   delete(id) -> {ok} or {ok: false, error, rooms?}

const GifDecode := preload("res://scripts/pictures/gif_decode.gd")
const ObjectLibrary := preload("res://scripts/assistant/object_library.gd")
const DevCommands := preload("res://scripts/dev/dev_commands.gd")
const ObjectCommands := preload("res://scripts/assistant/object_commands.gd")
const PartApply := preload("res://scripts/assistant/part_apply.gd")

const ROOT := "user://pictures"
const MAX_SIDE := 2048
const THUMB_SIDE := 160
const TITLE_MAX := 80
const JPEG_QUALITY := 0.9
const META := "picture.json"
const THUMB := "thumb.png"
## Google Images (the user browses themselves: the app opens the page and nothing more).
const SEARCH_URL := "https://www.google.com/search?q=%s&udm=2"

## Where the library is (tests point it elsewhere).
static var root := ROOT
static var _thumbs := {}
## (url) -> void: opens the search page instead of the browser (tests); empty: the browser on the big screen.
static var opener: Callable


static func _dir(id: String) -> String:
	return root.path_join(id)


static func id_ok(id: String) -> bool:
	return RegEx.create_from_string("^[a-f0-9]{16}$").search(id) != null


## A title as the library keeps it: one line, trimmed, at most TITLE_MAX.
static func clean_title(text: String) -> String:
	var t := text.replace("\n", " ").replace("\r", " ").replace("\t", " ").strip_edges()
	while t.contains("  "):
		t = t.replace("  ", " ")
	return t.left(TITLE_MAX).strip_edges()


## Keeps a picture: made at most MAX_SIDE on its long side, its thumbnail and its facts beside it. The same pixels
## twice are one picture (new: false, its first title kept).
static func add(src: Image, meta := {}) -> Dictionary:
	if src == null or src.is_empty():
		return {"ok": false, "error": "no picture"}
	var img := src.duplicate() as Image
	if img.is_compressed():
		img.decompress()
	img.clear_mipmaps()
	var alpha := img.detect_alpha() != Image.ALPHA_NONE
	img.convert(Image.FORMAT_RGBA8 if alpha else Image.FORMAT_RGB8)
	var side := maxi(img.get_width(), img.get_height())
	if side > MAX_SIDE:
		var k := float(MAX_SIDE) / side
		img.resize(maxi(1, roundi(img.get_width() * k)), maxi(1, roundi(img.get_height() * k)),
				Image.INTERPOLATE_LANCZOS)
	if img.get_width() < 8 or img.get_height() < 8:
		return {"ok": false, "error": "too small to keep (%d x %d)" % [img.get_width(), img.get_height()]}
	var h := HashingContext.new()
	h.start(HashingContext.HASH_SHA256)
	h.update(("%dx%d:" % [img.get_width(), img.get_height()]).to_ascii_buffer())
	h.update(img.get_data())
	var id := h.finish().hex_encode().left(16)
	var title := clean_title(str(meta.get("title", "")))
	if title == "":
		title = TranslationServer.translate("Picture") # i18n
	var dir := _dir(id)
	if FileAccess.file_exists(dir.path_join(META)):
		return {"ok": true, "id": id, "title": str(get_picture(id).get("title", title)), "new": false}
	DirAccess.make_dir_recursive_absolute(dir)
	var file := "picture.png" if alpha else "picture.jpg"
	var err := img.save_png(dir.path_join(file)) if alpha else img.save_jpg(dir.path_join(file), JPEG_QUALITY)
	if err != OK:
		return {"ok": false, "error": "can't write the picture (%s)" % error_string(err)}
	var thumb := _thumb_of(img)
	thumb.save_png(dir.path_join(THUMB))
	var page := str(meta.get("source_page", ""))
	var facts := {"id": id, "title": title, "aspect": snappedf(float(img.get_width()) / img.get_height(), 0.0001),
			"width": img.get_width(), "height": img.get_height(), "alpha": alpha, "file": file,
			"source_page": page if page.begins_with("http") else "", "how": str(meta.get("how", "")),
			"date": Time.get_datetime_string_from_system(false, true)}
	var f := FileAccess.open(dir.path_join(META), FileAccess.WRITE)
	if f == null:
		return {"ok": false, "error": "can't write %s" % META}
	f.store_string(JSON.stringify(facts, " "))
	f.close()
	_thumbs[id] = thumb
	return {"ok": true, "id": id, "title": title, "new": true}


static func _thumb_of(img: Image) -> Image:
	var t := img.duplicate() as Image
	var k := float(THUMB_SIDE) / maxi(t.get_width(), t.get_height())
	if k < 1.0:
		t.resize(maxi(1, roundi(t.get_width() * k)), maxi(1, roundi(t.get_height() * k)), Image.INTERPOLATE_BILINEAR)
	return t


## Every picture's facts, newest first.
static func list() -> Array:
	var out: Array = []
	if not DirAccess.dir_exists_absolute(root):
		return out
	for d in DirAccess.get_directories_at(root):
		if id_ok(d):
			var p := get_picture(d)
			if not p.is_empty():
				out.append(p)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a["date"]) > str(b["date"]))
	return out


static func get_picture(id: String) -> Dictionary:
	if not id_ok(id):
		return {}
	var path := _dir(id).path_join(META)
	if not FileAccess.file_exists(path):
		return {}
	var j: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (j is Dictionary):
		return {}
	var p: Dictionary = j
	p["id"] = id
	return p


static func file_path(id: String) -> String:
	var p := get_picture(id)
	return _dir(id).path_join(str(p.get("file", "picture.jpg"))) if not p.is_empty() else ""


## The stored file's bytes (a JPEG, or a PNG with transparency): what a part's texture takes.
static func file_bytes(id: String) -> PackedByteArray:
	var path := file_path(id)
	return FileAccess.get_file_as_bytes(path) if path != "" and FileAccess.file_exists(path) else PackedByteArray()


static func image(id: String) -> Image:
	var b := file_bytes(id)
	return decode(b) if not b.is_empty() else null


static func thumbnail(id: String) -> Image:
	if _thumbs.has(id):
		return _thumbs[id]
	var path := _dir(id).path_join(THUMB)
	if not id_ok(id) or not FileAccess.file_exists(path):
		return null
	var img := Image.new()
	if img.load_png_from_buffer(FileAccess.get_file_as_bytes(path)) != OK:
		return null
	_thumbs[id] = img
	return img


## A picture file's bytes as an image, by their first bytes: JPEG, PNG, WebP, a GIF's first frame, BMP. null if none.
static func decode(b: PackedByteArray) -> Image:
	if b.size() < 12:
		return null
	var img := Image.new()
	var err := ERR_FILE_UNRECOGNIZED
	if b[0] == 0xFF and b[1] == 0xD8:
		err = img.load_jpg_from_buffer(b)
	elif b[0] == 0x89 and b[1] == 0x50:
		err = img.load_png_from_buffer(b)
	elif b.slice(0, 4).get_string_from_ascii() == "RIFF" and b.slice(8, 12).get_string_from_ascii() == "WEBP":
		err = img.load_webp_from_buffer(b)
	elif b.slice(0, 3).get_string_from_ascii() == "GIF":
		return GifDecode.first_frame(b)
	elif b[0] == 0x42 and b[1] == 0x4D:
		err = img.load_bmp_from_buffer(b)
	if err != OK or img.is_empty():
		return null
	return img


## A data: URL's picture (base64 or not), or null.
static func from_data_url(url: String) -> Image:
	var comma := url.find(",")
	if not url.begins_with("data:image/") or comma < 0:
		return null
	var head := url.substr(0, comma)
	var body := url.substr(comma + 1)
	var bytes := Marshalls.base64_to_raw(body) if head.ends_with(";base64") else body.uri_decode().to_utf8_buffer()
	return decode(bytes)


## The objects made from a picture (picture_objects.gd: a poster, a frame, a canvas, a cut-out of it).
static func objects_of(id: String) -> Array:
	return ObjectLibrary.list("", "user").filter(func(m: Dictionary) -> bool: return str(m.get("picture_id", "")) == id)


## Deletes a picture and the objects made from it; refused while a kept room places one of them (rooms names them).
static func delete(id: String) -> Dictionary:
	var p := get_picture(id)
	if p.is_empty():
		return {"ok": false, "error": "no picture %s (pictures lists them)" % id}
	var rooms: Array = []
	for m: Dictionary in objects_of(id):
		for r: String in ObjectLibrary.rooms_using(str(m["id"])):
			if not (r in rooms):
				rooms.append(r)
	if not rooms.is_empty():
		return {"ok": false, "rooms": rooms, "error": "%s is on show in kept room%s %s: remove it there first" % [
				p["title"], "" if rooms.size() == 1 else "s", ", ".join(rooms)]}
	for m: Dictionary in objects_of(id):
		ObjectLibrary.delete(str(m["id"]))
		ObjectLibrary.purge(str(m["id"]))
	var dir := _dir(id)
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(f))
	DirAccess.remove_absolute(dir)
	_thumbs.erase(id)
	return {"ok": true, "title": p["title"]}


static func search_url(words: String) -> String:
	return SEARCH_URL % words.strip_edges().uri_encode()


# --- The commands ----------------------------------------------------------------------------------------------------

static func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


static func _main() -> Node:
	return _tree().current_scene if _tree() != null else null


## pictures_search (control), pictures (read), picture_place, picture_apply and picture_delete (room).
static func register_commands(_host: Node = null) -> void:
	var R := DevCommands
	R.register("pictures_search", func(a: Dictionary, ctx: DevCommands.Call) -> Variant:
		var words := str(a["query"]).strip_edges()
		if words == "":
			return ctx.fail("give the words to search for")
		var url := search_url(words.left(200))
		open_search(url)
		ctx.summary = "opened a picture search"
		return {"opened": url, "note": "The user browses and keeps pictures themselves (the right stick click on an "
				+ "image, Copy image, or a save to Downloads); the app does nothing more on the page."}, {
		"description": "Opens Google Images for some words in the headset's browser on the big screen, for the user "
				+ "to browse themselves. The app only opens the page: it never reads, scrapes or clicks it. What "
				+ "the user keeps (the right stick click on an image) comes into the picture library (pictures).",
		"params": [{"name": "query", "type": "string", "required": true, "description": "The words to search for."}],
		"level": "control", "assistant": "control", "title": "Open a picture search",
		"returns": "{opened (the page's address), note}"})
	R.register("pictures", func(_a: Dictionary, _ctx: DevCommands.Call) -> Variant:
		var out: Array = []
		for p: Dictionary in list():
			out.append({"id": p["id"], "title": p["title"], "aspect": p["aspect"], "width": p["width"],
					"height": p["height"], "alpha": p["alpha"], "date": p["date"],
					"objects": objects_of(str(p["id"])).map(func(m: Dictionary) -> Dictionary:
						return {"id": m["id"], "as": m.get("picture_as", "")})})
		return {"pictures": out, "count": out.size(), "as": load("res://scripts/pictures/picture_objects.gd").KINDS}, {
		"description": "The picture library: pictures the user kept while browsing, newest first, with their "
				+ "aspect (width / height), whether they have transparency (a cut-out suits those) and the "
				+ "objects already made from them. Titles are the pages' own words.",
		"params": [], "assistant": "read", "title": "The picture library",
		"returns": "{pictures: [{id, title, aspect, width, height, alpha, date, objects: [{id, as}]}], count, as}"})
	R.register("picture_place", func(a: Dictionary, ctx: DevCommands.Call) -> Variant:
		var PictureObjects: GDScript = load("res://scripts/pictures/picture_objects.gd")
		var made: Dictionary = await PictureObjects.call("object_for", str(a["picture"]), str(a["as"]))
		if not bool(made.get("ok", false)):
			return ctx.fail(str(made["error"]))
		var opts: Dictionary = a.duplicate()
		opts.erase("picture")
		opts.erase("as")
		if str(opts.get("name", "")) == "":
			opts["name"] = ObjectLibrary.clean_name(str(get_picture(str(a["picture"])).get("title", ""))).left(30)
		return ObjectCommands._give(ctx, await ObjectCommands.place(_tree(), ctx.caller, str(made["id"]), opts)), {
		"description": "Puts a kept picture in the room as a poster (a thin sheet on a wall), framed (a wooden "
				+ "frame), a canvas (a deep frame) or a cut-out (a standee on the floor, its transparent pixels cut "
				+ "away, seen from both sides), each sized to the picture's shape. Wall ones hang fixed until the "
				+ "user pulls them off; then they fall and can be thrown like any object.",
		"params": [{"name": "picture", "type": "string", "required": true, "description": "The picture's id "
				+ "(pictures)."},
				{"name": "as", "type": "string", "default": "poster", "enum": ["poster", "framed", "canvas",
				"cutout"], "description": "What it becomes."},
				{"name": "name", "type": "string", "default": "", "description": "Its name in the room; empty: the "
				+ "picture's title."},
				{"name": "at", "type": "string", "default": "", "enum": ["", "wall", "floor", "ceiling", "front"],
				"description": "As object_place: empty puts a wall one on the wall the viewer looks at, a cut-out on "
				+ "the floor in front."},
				{"name": "position", "type": "array", "default": [], "description": "[x, y, z] metres in the room "
				+ "frame, instead of at."},
				{"name": "rotation", "type": "array", "default": [], "description": "[x, y, z] degrees, with "
				+ "position."},
				{"name": "turn", "type": "float", "default": 0.0, "description": "Degrees round the wall's normal or "
				+ "round up, with at."},
				{"name": "scale", "type": "float", "default": 1.0, "description": "Its size, 1 as made (a poster's "
				+ "long side is 0.6 m)."}],
		"level": "change", "assistant": "room", "title": "Place a picture",
		"returns": "{state: kept, placed, name, ...}"})
	R.register("picture_apply", func(a: Dictionary, ctx: DevCommands.Call) -> Variant:
		var id := str(a["picture"])
		var bytes := file_bytes(id)
		if bytes.is_empty():
			return ctx.fail("no picture %s (pictures lists them)" % id)
		return ObjectCommands._give(ctx, await PartApply.apply(_tree(), ctx.caller, str(a["part"]),
				texture_change(id))), {
		"description": "Puts a kept picture on one part: a room surface by name (pointed_part, room_state) or a "
				+ "placed object's part (\"Poster/Picture\"), or every surface of a placed object with one of its "
				+ "model's materials (\"Sofa/@Fabric\": pointed_part's same). Kept in the room like a recolour with a "
				+ "texture; part_reset puts the part back.",
		"params": [{"name": "part", "type": "string", "required": true, "description": "The part (pointed_part's "
				+ "part or same, a room surface's name, \"<placed>/<part>\" or \"<placed>/@<material>\")."},
				{"name": "picture", "type": "string", "required": true, "description": "The picture's id "
				+ "(pictures)."}],
		"level": "change", "assistant": "room", "title": "Put a picture on a part",
		"returns": "{state: kept, ...}"})
	R.register("picture_delete", func(a: Dictionary, ctx: DevCommands.Call) -> Variant:
		var r := delete(str(a["picture"]))
		if not bool(r["ok"]):
			if r.has("rooms"):
				ctx.reply["refused"] = true
				ctx.reply["rooms"] = r["rooms"]
			return ctx.fail(str(r["error"]))
		ctx.summary = "deleted a picture"
		_sync_tab()
		return {"deleted": str(a["picture"])}, {
		"description": "Deletes a kept picture and the posters, frames, canvases and cut-outs made from it. Refused "
				+ "while a kept room shows one of them (the reply names the rooms): remove it there first.",
		"params": [{"name": "picture", "type": "string", "required": true, "description": "The picture's id "
				+ "(pictures)."}],
		"level": "change", "assistant": "room", "destructive": true, "title": "Delete a picture",
		"returns": "{deleted}; refused: {error, rooms}"})


## A picture as a part's material: its file as the texture (the room keeps it as the part's picture file).
static func texture_change(id: String) -> Dictionary:
	return {"texture": Marshalls.raw_to_base64(file_bytes(id))}


## The search page in the browser on the big screen (the panel goes, so it shows).
static func open_search(url: String) -> void:
	if opener.is_valid():
		opener.call(url)
		return
	var main := _main()
	if main == null:
		return
	var WebPages: GDScript = load("res://scripts/net/web_pages.gd")
	WebPages.call("set_last_url", url)
	var ui: Object = main.get("ui")
	if ui != null and ui.has_method("hide_panel"):
		ui.hide_panel()
	main.open_path("browser://" + url)


static func _sync_tab() -> void:
	ObjectCommands._sync_tab()
