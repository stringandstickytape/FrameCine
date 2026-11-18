extends Node

## Making visualisers on the headset (docs/visualisers.md, "Tinkering"): what lets a person or an agent (Claude Code or
## Codex in the headset's terminal) write one in user://visualisers and see it at once, with no rebuild and no
## restart. main.features.visualisers_service.
##
##   the folder     user://visualisers is made at start, with README.md (res://visualisers/README.md, the paths filled
##                  in) rewritten whenever the app's text changes: everything an agent needs, in one file
##   the watcher    every POLL seconds, the user folders' manifests and shaders are looked at (times and sizes); a
##                  change reads the folders again, checks the changed ones (VisualiserRegistry.check: a shader that
##                  does not compile keeps the last that did) and starts the one on the card again when it changed.
##                  Always on: a few file stats a second.
##   test signals   scripts/visualisers/test_signals.gd, made on a worker thread the first time, opened as music
##   commands       visualisers, visualiser_status, visualiser_check, visualiser_use, visualiser_param,
##                  visualiser_preset, visualiser_reset, visualiser_test, visualiser_capture (the dev link, the phone
##                  remote, the assistant API and so the agents' MCP tools: one registry, scripts/dev/dev_commands.gd)
##
##   poll() -> Array[String]     look now; the ids that changed (tests)
##   last_change                 {ids, at, results} of the last change seen
##   capture() -> Dictionary     the card and the visualiser alone saved as PNGs in CAPTURES

const Registry := preload("res://scripts/visualisers/visualiser_registry.gd")
const TestSignals := preload("res://scripts/visualisers/test_signals.gd")
const DevCommands := preload("res://scripts/dev/dev_commands.gd")
const USER_DIR := "user://visualisers"
const README_SOURCE := "res://visualisers/README.md"
const CAPTURES := "user://visualisers/.captures"
const POLL := 1.0

var main: Node
## The folder watched (tests point it elsewhere).
var user_dir := USER_DIR
var last_change := {}
var _stamps := {}
var _since := 0.0


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(user_dir)
	write_readme()
	_stamps = _read_stamps()
	_register()


## README.md in the user folder, with this headset's paths; written only when its text changed.
func write_readme() -> void:
	var text := FileAccess.get_file_as_string(README_SOURCE)
	if text == "":
		return
	text = text.replace("<<USER>>", ProjectSettings.globalize_path(user_dir)) \
			.replace("<<APP>>", ProjectSettings.globalize_path("res://visualisers"))
	var path := user_dir.path_join("README.md")
	if FileAccess.get_file_as_string(path) == text:
		return
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_string(text)
		f.close()


func _process(delta: float) -> void:
	_since += delta
	if _since >= POLL:
		_since = 0.0
		poll()


## path -> "mtime:size" for every manifest and shader in the user folders (hidden folders are the app's own).
func _read_stamps() -> Dictionary:
	var out := {}
	var dir := DirAccess.open(user_dir)
	if dir == null:
		return out
	for id in dir.get_directories():
		for file in [Registry.MANIFEST, Registry.SHADER]:
			var p := user_dir.path_join(id).path_join(file)
			if FileAccess.file_exists(p):
				out[p] = "%d:%d" % [FileAccess.get_modified_time(p), FileAccess.get_size(p)]
	return out


func poll() -> Array[String]:
	var now := _read_stamps()
	if now == _stamps:
		return []
	var changed := {}
	for p: String in now:
		if _stamps.get(p, "") != now[p]:
			changed[p.get_base_dir().get_file()] = true
	for p: String in _stamps:
		if not now.has(p):
			changed[p.get_base_dir().get_file()] = true
	_stamps = now
	Registry.rescan()
	var results := {}
	for id: String in changed:
		results[id] = Registry.check(id)
	var ids: Array[String] = []
	ids.assign(changed.keys())
	last_change = {"ids": ids, "at": Time.get_unix_time_from_system(), "results": results}
	var r := ""
	for id in ids:
		var res: Dictionary = results[id]
		r += " %s %s" % [id, "ok" if res["ok"] else "has errors (%s)" % _first_error(res)]
	print("Visualisers: changed:%s" % r)
	_restart_showing(ids)
	return ids


static func _first_error(res: Dictionary) -> String:
	var e: Array = res.get("errors", [])
	if e.is_empty():
		return ""
	return "line %d: %s" % [int(e[0]["line"]), e[0]["message"]] if int(e[0]["line"]) > 0 else str(e[0]["message"])


## The card's visualiser starts again with its new files when they changed and compile.
func _restart_showing(ids: Array[String]) -> void:
	var host: Node = _host()
	if host == null or not str(host.id) in ids:
		return
	if Registry.check(str(host.id))["ok"]:
		host.use(str(host.id))


## The visualiser host on the music card showing now, or null.
func _host() -> Node:
	var src: Object = main.player.source if main != null and main.player != null else null
	if src == null or not src.has_method("visualiser"):
		return null
	return src.visualiser()


## The card and the visualiser alone as PNGs: {card, picture} (absolute paths), or {error}.
func capture() -> Dictionary:
	var host: Node = _host()
	if host == null:
		return {"error": "no music card is showing: open a music file, or run visualiser_test"}
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(CAPTURES)
	var id := str(host.id) if str(host.id) != "" else "off"
	var card_path := CAPTURES.path_join("%s_card.png" % id)
	var pic_path := CAPTURES.path_join("%s_alone.png" % id)
	main.player.source.get_rgb_texture().get_image().save_png(card_path)
	var pic: Texture2D = host.picture()
	if pic != null and host.is_processing():
		pic.get_image().save_png(pic_path)
	else:
		pic_path = ""
	return {"card": ProjectSettings.globalize_path(card_path),
			"alone": ProjectSettings.globalize_path(pic_path) if pic_path != "" else null}


## What the card's visualiser is doing: its id, the host's stats, the flash limit's state, its check.
func status() -> Dictionary:
	var host: Node = _host()
	var out := {"showing": main.features.visualiser(), "music_card": host != null,
			"folder": ProjectSettings.globalize_path(user_dir)}
	if host != null and host.is_processing() and str(host.id) != "":
		var st: Dictionary = host.stats()
		var px: Color = host.limit_texture().get_image().get_pixel(0, 0)
		st["flash_limit"] = {"gain": snappedf(px.a, 0.01), "average": snappedf(px.b * px.b, 0.001),
				"floor": snappedf(px.r + px.g / 255.0, 0.001), "dimming": px.a < 0.99}
		out["running"] = st
		out["check"] = Registry.check(str(host.id))
	if not last_change.is_empty():
		out["last_change"] = last_change
	return out


## Makes the signal's file if needed (on a worker thread) and opens it.
func open_test(which: String) -> Dictionary:
	if not which in TestSignals.SIGNALS:
		return {"error": "no test signal %s: one of %s" % [which, ", ".join(TestSignals.SIGNALS)]}
	var out := [""]
	var task := WorkerThreadPool.add_task(func() -> void: out[0] = TestSignals.ensure(which))
	while not WorkerThreadPool.is_task_completed(task):
		await get_tree().process_frame
	WorkerThreadPool.wait_for_task_completion(task)
	if out[0] == "":
		return {"error": "could not write %s" % TestSignals.path(which)}
	main.open_path(ProjectSettings.globalize_path(out[0]))
	return {"opened": ProjectSettings.globalize_path(out[0]), "seconds": TestSignals.SECONDS}


func _register() -> void:
	# The features node (this service is one of its children).
	var f: Node = get_parent()
	DevCommands.register("visualisers", func(_args: Dictionary, _ctx: DevCommands.Call) -> Variant:
		Registry.rescan()
		var broken := Registry.errors()
		return {"showing": f.visualiser(), "visualisers": f.visualisers(), "broken": broken,
				"folder": ProjectSettings.globalize_path(user_dir),
				"readme": ProjectSettings.globalize_path(user_dir.path_join("README.md")),
				"app_folder": ProjectSettings.globalize_path("res://visualisers")}, {
		"description": "The music visualisers (pictures of the sound on the screen while music plays): each with "
				+ "its parameters and presets, the one showing, folders that are broken and why, and the folder for "
				+ "your own (read its README.md first to write one).",
		"level": "read", "assistant": "read", "title": "List visualisers",
		"returns": "{showing, visualisers, broken, folder, readme, app_folder}"})
	DevCommands.register("visualiser_status", func(_args: Dictionary, _ctx: DevCommands.Call) -> Variant:
		return status(), {
		"description": "The visualiser on the music card now: its GPU time and scale, whether the flash limit is "
				+ "dimming it, and its shader check (compile errors with line numbers).",
		"level": "read", "assistant": "read", "title": "Visualiser status",
		"returns": "{showing, music_card, running: {gpu_ms, scale, flash_limit, ...}, check, last_change}"})
	DevCommands.register("visualiser_check", func(args: Dictionary, ctx: DevCommands.Call) -> Variant:
		Registry.rescan()
		var id := str(args.get("id", ""))
		if id == "":
			id = f.visualiser()
		if not Registry.has(id):
			return ctx.fail("no visualiser %s (%s)" % [id, Registry.errors().get(id, "no folder with that name")])
		return Registry.check(id), {
		"description": "Reads a visualiser's folder again and compiles its shader now. ok false lists the errors "
				+ "(line numbers in visualiser.gdshader); the card keeps the last version that compiled.",
		"params": [{"name": "id", "type": "string", "default": "", "description": "its folder name; the one showing "
				+ "when empty"}],
		"level": "read", "assistant": "read", "title": "Check a visualiser",
		"returns": "{ok, errors: [{line, message}], missing (parameters with no uniform), uniforms}"})
	DevCommands.register("visualiser_use", func(args: Dictionary, ctx: DevCommands.Call) -> Variant:
		Registry.rescan()
		var id := str(args["id"])
		var old: String = f.visualiser()
		var why: String = f.set_visualiser_checked(id)
		if why != "":
			return ctx.fail(why)
		ctx.summary = "Visualiser: %s" % id
		ctx.undo = func() -> void: f.set_visualiser(old)
		return {"showing": f.visualiser()}, {
		"description": "Chooses the music visualiser (an id from visualisers, or \"off\"); kept as the viewer's "
				+ "choice. Refused, with the compile errors, when its shader has never compiled.",
		"params": [{"name": "id", "type": "string", "required": true, "description": "a visualiser's id, or off"}],
		"level": "control", "assistant": "settings", "title": "Choose a visualiser", "returns": "{showing}"})
	DevCommands.register("visualiser_param", func(args: Dictionary, ctx: DevCommands.Call) -> Variant:
		var id := str(args.get("id", ""))
		if id == "":
			id = f.visualiser()
		var old: Variant = Registry.values(id).get(str(args["name"]))
		if not f.set_visualiser_param(str(args["name"]), args["value"], id):
			return ctx.fail("%s has no parameter %s that takes %s (visualisers lists them)" % [id, args["name"],
					args["value"]])
		ctx.summary = "%s: %s" % [id, args["name"]]
		ctx.undo = func() -> void: f.set_visualiser_param(str(args["name"]), old, id)
		return {"id": id, "values": Registry.values(id)}, {
		"description": "Sets one parameter of a visualiser (clamped to its range; a colour as \"#rrggbb\"); kept "
				+ "as the viewer's choice.",
		"params": [{"name": "name", "type": "string", "required": true, "description": "the parameter"},
				{"name": "value", "type": "any", "required": true, "description": "a number, true or false, or "
						+ "\"#rrggbb\""},
				{"name": "id", "type": "string", "default": "", "description": "the visualiser; the one showing when "
						+ "empty"}],
		"level": "control", "assistant": "settings", "title": "Set a visualiser parameter",
		"returns": "{id, values}"})
	DevCommands.register("visualiser_preset", func(args: Dictionary, ctx: DevCommands.Call) -> Variant:
		var id := str(args.get("id", ""))
		if id == "":
			id = f.visualiser()
		if not f.apply_visualiser_preset(str(args["name"]), id):
			return ctx.fail("%s has no preset %s" % [id, args["name"]])
		ctx.summary = "%s: %s" % [id, args["name"]]
		return {"id": id, "values": Registry.values(id)}, {
		"description": "Applies a visualiser's preset: its defaults with the preset's values over them.",
		"params": [{"name": "name", "type": "string", "required": true, "description": "the preset"},
				{"name": "id", "type": "string", "default": "", "description": "the visualiser; the one showing when "
						+ "empty"}],
		"level": "control", "assistant": "settings", "title": "Apply a visualiser preset", "returns": "{id, values}"})
	DevCommands.register("visualiser_reset", func(args: Dictionary, ctx: DevCommands.Call) -> Variant:
		var id := str(args.get("id", ""))
		if id == "":
			id = f.visualiser()
		f.reset_visualiser_params(id)
		ctx.summary = "%s: defaults" % id
		return {"id": id, "values": Registry.values(id)}, {
		"description": "Puts every parameter of a visualiser back to its default.",
		"params": [{"name": "id", "type": "string", "default": "", "description": "the visualiser; the one showing "
				+ "when empty"}],
		"level": "control", "assistant": "settings", "title": "Reset a visualiser", "returns": "{id, values}"})
	DevCommands.register("visualiser_test", func(args: Dictionary, ctx: DevCommands.Call) -> Variant:
		var r: Dictionary = await open_test(str(args["signal"]))
		if r.has("error"):
			return ctx.fail(r["error"])
		ctx.summary = "Test signal: %s" % args["signal"]
		return r, {
		"description": "Plays a test signal as music, so a visualiser can be tried with nothing else playing: drums "
				+ "(120 a minute, no drums from 20 to 30 s), sweep (30 Hz to 15 kHz and back), tones (an octave "
				+ "higher every 2 s) or silence. Made the first time (a few seconds).",
		"params": [{"name": "signal", "type": "string", "required": true, "enum": TestSignals.SIGNALS,
				"description": "which signal"}],
		"level": "control", "assistant": "control", "title": "Play a test signal", "returns": "{opened, seconds}"})
	DevCommands.register("visualiser_capture", func(_args: Dictionary, ctx: DevCommands.Call) -> Variant:
		var r: Dictionary = await capture()
		if r.has("error"):
			return ctx.fail(r["error"])
		return r, {
		"description": "Saves what the music card shows now as a PNG (1280 x 720), and the visualiser's own picture "
				+ "before the flash limit, on the headset. Look at them to judge a visualiser.",
		"level": "read", "assistant": "read", "title": "Capture the visualiser", "returns": "{card, alone} (paths)"})
