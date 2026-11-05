extends RefCounted

## The assistant service's commands (docs/assistant.md, D20): the commands of the shared registry
## (scripts/dev/dev_commands.gd) whose spec carries an `assistant` tag, and nothing else. The tag is the level:
##   read      what plays, places and folders, chapters, tracks, the room, the measured cost: always
##   card      the card beside the screen: always (it is how the assistant answers)
##   control   playback, opening a file, tracks, volume, recentring: [assistant] allow_control
##   room      changing the room (room_editor.gd; a room document, room_schema.gd): allow_room; every change shows at
##             once and is kept (saved as a room in the Room tab)
##   settings  the viewer's lasting preferences (the Picture, Sound, Subtitles and System tabs): allow_settings
##   files     the Library and files: copies, downloads, places, saved hosts: allow_files
##   apps      Android apps and the agents on the headset: allow_apps
## Each switch is a row in the System tab, off by default (assistant_switches.gd). A command that runs code never has
## a tag (the registry drops it), so no code, no hot reload and no scene editing are reachable from here.
##
## This file registers the assistant's own commands (state, tracks, the room commands, fetch, ...; register_commands()),
## checks the tag and the switch, and runs every command through DevCommands.execute with itself as the gate: the same
## argument checks and handlers as the dev link and the phone remote. describe() makes /describe from the tags; the
## guide and the OpenAPI (assistant_guide.gd) are made from describe().
##
##   var c := AssistantCommands.new(); c.allow_control = func() -> bool: ...
##   var r: Dictionary = await c.run("seek", {"seconds": -30, "relative": true})   # {ok, result | error, refused,
##                                                                                   #  summary, undo}

const DevCommands := preload("res://scripts/dev/dev_commands.gd")
const CommandHost := preload("res://scripts/dev/command_host.gd")
const InfoOverlay := preload("res://scripts/info_overlay.gd")
const NetworkHosts := preload("res://scripts/net/network_hosts.gd")
const RemoteServer := preload("res://scripts/remote/remote_server.gd")
const RoomSchema := preload("res://scripts/assistant/room_schema.gd")
const Director := preload("res://scripts/director/director.gd")
const RoomPerf := preload("res://scripts/assistant/room_perf.gd")
const AssistantFetch := preload("res://scripts/assistant/assistant_fetch.gd")
const AssistantPlaces := preload("res://scripts/assistant/assistant_places.gd")
const AssistantBrowse := preload("res://scripts/assistant/assistant_browse.gd")
const LibraryCopy := preload("res://scripts/library/library_copy.gd")
const LibraryIndex := preload("res://scripts/library/library_index.gd")
const ObjectCommands := preload("res://scripts/assistant/object_commands.gd")
const SELF := "res://scripts/assistant/assistant_commands.gd"
const SERVICE_NODE := "AssistantService"

const AssistantSwitches := preload("res://scripts/assistant/assistant_switches.gd")
## The levels behind a switch, and those without one (assistant_switches.gd).
const SWITCHES := AssistantSwitches.SWITCHES
const ALWAYS := AssistantSwitches.ALWAYS
## The room commands (_room()): each becomes a room document for the editor.
const ROOM_COMMANDS: Array[String] = ["room_apply", "new_room", "add_shape", "add_text", "add_model", "recolour",
		"set_lighting", "remove"]
const CARD_TEXT_MAX := 4000
const SEAT_CARD := "seat_suggestion"

## () -> bool: may the assistant control playback now.
var allow_control: Callable = func() -> bool: return false
## () -> bool: may the assistant change the room now.
var allow_room: Callable = func() -> bool: return false
## () -> bool: may the assistant change the viewer's settings now.
var allow_settings: Callable = func() -> bool: return false
## () -> bool: may the assistant copy, download and manage files and places now.
var allow_files: Callable = func() -> bool: return false
## () -> bool: may the assistant start, stop, show and hide Android apps and agents now.
var allow_apps: Callable = func() -> bool: return false
## The room editor (room_editor.gd), made by the link.
var room: Node
## The paired assistant's name from pairing, for what the viewer reads ("<name> wants to add ..."); set by the
## service before each command, and given to the handler as ctx.client.
var client_name := ""


func _init() -> void:
	_ensure_registry()


static func _main() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.current_scene if tree != null else null


## The registry with everything in it: the built-ins (command_host.gd) and this file's commands.
static func _ensure_registry() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree != null and tree.root != null:
		CommandHost.ensure(tree)
	if not DevCommands.has_command("room_state"):
		register_commands()


## Whether the viewer lets the assistant use a level now.
func allowed(level: String) -> bool:
	if ALWAYS.has(level):
		return true
	match level:
		"control":
			return bool(allow_control.call())
		"room":
			return bool(allow_room.call())
		"settings":
			return bool(allow_settings.call())
		"files":
			return bool(allow_files.call())
		"apps":
			return bool(allow_apps.call())
	return false


## What the assistant is told when a switch is off: which row to turn on.
static func refusal(cmd: String, level: String) -> String:
	var s: Dictionary = SWITCHES.get(level, {})
	if s.is_empty():
		return "%s is not available to the assistant (describe lists what is)" % cmd
	return "%s: the viewer has not allowed the assistant to %s (System, Assistant, \"%s\")" % [cmd, s["doing"],
			s["label"]]


## The commands the assistant may run, as /describe gives them: per command its name, level, description, params,
## returns and input_schema (a JSON Schema of the arguments); per level what it covers, its switch and, with
## `switch_on` (level -> bool), whether it is on now.
static func describe(switch_on := Callable()) -> Dictionary:
	_ensure_registry()
	var out: Array = [_entry("describe", {"assistant": "read", "params": [], "description": "The commands you may "
			+ "run, the levels and whether the viewer has turned each on (as GET /describe).",
			"returns": "{commands, levels, room_schema, room_limits, supported_widgets}"})]
	for n: String in DevCommands.assistant_names():
		if n != "describe":
			out.append(_entry(n, DevCommands.get_spec(n)))
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a["name"]) < str(b["name"]))
	var levels := {}
	for l: String in DevCommands.ASSISTANT_LEVELS:
		var e := {}
		if SWITCHES.has(l):
			e = {"what": SWITCHES[l]["what"], "switch": SWITCHES[l]["label"],
					"setting": "[assistant] %s" % SWITCHES[l]["key"]}
		else:
			e = {"what": ALWAYS[l], "switch": null}
		if switch_on.is_valid():
			e["allowed"] = ALWAYS.has(l) or bool(switch_on.call(l))
		levels[l] = e
	return {"commands": out, "levels": levels, "room_schema": RoomSchema.VERSION, "room_limits": RoomSchema.LIMITS,
			"supported_widgets": RoomSchema.supported_widgets()}


static func _entry(cmd: String, spec: Dictionary) -> Dictionary:
	var params: Array = DevCommands.to_json(spec.get("params", []))
	var e := {"name": cmd, "level": str(spec["assistant"]), "description": str(spec.get("description", "")),
			"params": params, "returns": str(spec.get("returns", "")),
			"input_schema": DevCommands.params_schema(spec.get("params", []))}
	if spec.has("title"):
		e["title"] = str(spec["title"])
	if spec.has("destructive"):
		e["destructive"] = bool(spec["destructive"])
	return e


## Runs one command. Only a tagged command, and only while its level is allowed.
func run(cmd: String, args: Dictionary) -> Dictionary:
	_ensure_registry()
	if cmd == "describe":
		return {"ok": true, "result": describe(allowed)}
	var level := DevCommands.assistant_level(cmd)
	if level == "":
		return {"ok": false, "refused": true, "error": refusal(cmd, "")}
	if not allowed(level):
		return {"ok": false, "refused": true, "error": refusal(cmd, level), "switch": SWITCHES[level]["label"]}
	var main := _main()
	if main == null or not ("player" in main):
		return {"ok": false, "error": "the player is not ready"}
	var r: Dictionary = await DevCommands.execute(cmd, args, true, self)
	var call: DevCommands.Call = r["call"]
	var out := {"ok": r["ok"]}
	if r["ok"]:
		out["result"] = r["result"]
		out["summary"] = call.summary
		out["undo"] = call.undo
	else:
		out["error"] = str(r.get("error", ""))
		if r.get("refused", false):
			out["refused"] = true
	out.merge(call.reply, true)
	return out


## The registry's gate, once the arguments are checked: who asks, the paths the assistant may open, the card's length.
func check(ctx: DevCommands.Call, _spec: Dictionary) -> String:
	ctx.client = client_name
	if ctx.name == "open" or ctx.name == "copy_to_library":
		var why := open_refusal(str(ctx.args.get("path" if ctx.name == "open" else "from", "")))
		if why != "":
			return why
	if ctx.name == "card" and str(ctx.args.get("text", "")).length() > CARD_TEXT_MAX:
		ctx.args["text"] = str(ctx.args["text"]).left(CARD_TEXT_MAX)
	return ""


## Why a path may not be opened by the assistant, or "". Local files, test patterns, saved SMB hosts and media
## servers on the LAN; not web pages, captured windows, or hosts the viewer never saved.
static func open_refusal(path: String) -> String:
	if path.begins_with("stub://"):
		return ""
	if path.begins_with("smb://"):
		var host := path.trim_prefix("smb://").get_slice("/", 0).to_lower()
		for h: Dictionary in NetworkHosts.hosts:
			if str(h["host"]).to_lower() == host:
				return ""
		return "smb://%s is not a host saved in the player; the viewer can add it in Files, Network" % host
	if path.begins_with("http://") or path.begins_with("https://"):
		var rest := path.get_slice("://", 1).get_slice("/", 0)
		var host := rest.get_slice("@", 1) if rest.contains("@") else rest
		host = host.trim_prefix("[").get_slice("]", 0) if host.begins_with("[") else host.get_slice(":", 0)
		if host.is_valid_ip_address() and RemoteServer.is_private(host):
			return ""
		return "only media servers on this network (an http:// URL with a LAN address, from list_dir upnp://)"
	if path.contains("://"):
		return "the assistant can't open %s:// paths" % path.get_slice("://", 0)
	if path.is_absolute_path() or path.begins_with("~/"):
		return ""
	return "give an absolute path on the headset"


# --- The assistant's own commands ----------------------------------------------------------------------------------

## Registers the commands that are the assistant's own. The handlers are this file's (_own, _room); a call through
## the assistant API reaches the AssistantCommands that ran it (ctx.caller: its switches, its room editor), any other
## caller (the dev link) the running service's, else one with every switch off.
static func register_commands() -> void:
	var R := DevCommands
	R.register("state", _handler("state"), {"assistant": "read", "description": "What plays now: path, title, "
			+ "playing, position, duration, chapter, mode, environment, volume, subtitles, audio track, battery, "
			+ "the download and the Library copy, the file's Library entry, and whether control and room changes "
			+ "are allowed.", "returns": "{path, title, playing, position, duration, ..., control, room_allowed}"})
	R.register("tracks", _handler("tracks"), {"assistant": "read",
			"description": "Audio and subtitle tracks, and which are selected.",
			"returns": "{audio, audio_selected, subtitles, subtitles_state}"})
	R.register("subtitle_lines", _handler("subtitle_lines"), {"assistant": "read",
			"description": "The last subtitle lines said (for the context of a question).",
			"params": [{"name": "count", "type": "int", "default": 8, "description": "how many, 1..40"}],
			"returns": "{lines: [{start, text}], source | note | total}"})
	R.register("subtitle_track", _handler("subtitle_track"), {"assistant": "control", "level": "control",
			"description": "Shows a subtitle track (an index from tracks).",
			"params": [{"name": "index", "type": "int", "required": true, "description": "a subtitle track's index"}],
			"returns": "the subtitle state"})
	R.register("audio_track", _handler("audio_track"), {"assistant": "control", "level": "control",
			"description": "Picks an audio track (an index from tracks).",
			"params": [{"name": "index", "type": "int", "required": true, "description": "an audio track's index"}],
			"returns": "{audio_track}"})
	R.register("volume", _handler("volume"), {"assistant": "control", "level": "control",
			"description": "The volume: level 0..1, or step (-1..1) from now.",
			"params": [{"name": "level", "type": "float", "default": -1.0, "description": "0..1; -1: use step"},
			{"name": "step", "type": "float", "default": 0.0, "description": "-1..1 from the volume now"}],
			"returns": "{volume}"})
	R.register("reset_room", _handler("reset_room"), {"assistant": "control", "level": "control",
			"description": "The room's own seat, the screen at its home, the view recentred.", "returns": "{done}"})
	R.register("suggest_seat", _handler("suggest_seat"), {"assistant": "card", "level": "control",
			"description": "Suggests a seat of the room on show (room_state lists them): a card asks the viewer, who "
			+ "moves there or stays. It never moves them itself; the answer comes as card_dismissed {id: "
			+ "seat_suggestion, how: go | stay | user | timeout}.",
			"params": [{"name": "seat", "type": "string", "required": true, "description": "the seat's name"},
			{"name": "why", "type": "string", "default": "", "description": "a short reason, shown on the card"}],
			"returns": "{shown, id, seat}"})
	R.register("browser_page", _handler("browser_page"), {"assistant": "read",
			"description": "The page the Browser source shows now: {url, title, via: devtools | history | window "
			+ "title, opened_url}, read fresh from the browser; null when no browser is shown. Without the browser's "
			+ "DevTools port it comes from the browser's history (the visit titled as the window); url null when "
			+ "neither works.", "returns": "{url, title, via, opened_url} or null"})
	R.register("fetch", _handler("fetch"), {"assistant": "files", "level": "change",
			"description": "The headset downloads a file from a server on this network (http or https; the host must "
			+ "be a private address) into ~/Videos/From assistant, then opens it if open. One at a time; the download "
			+ "event says started, progress (at most once a second), done (path), failed (reason) or cancelled. Keeps "
			+ "2 GB of the disk free.", "params": [
			{"name": "url", "type": "string", "required": true, "description": "http(s) on this network"},
			{"name": "name", "type": "string", "default": "", "description": "the file's name (the URL's when "
			+ "empty); the extension comes from the URL or the content type when it has none"},
			{"name": "open", "type": "bool", "default": true, "description": "open it when done"},
			{"name": "mode", "type": "string", "default": "", "description": "overrides the guess when opened: "
			+ "e.g. 360, 180_sbs, sbs, 360_tb"},
			{"name": "to", "type": "string", "default": "", "description": "a path inside the Library instead of "
			+ "~/Videos/From assistant, e.g. Movies/Title (2001)/poster.jpg (see the guide's layout); name is then "
			+ "ignored and a file already there is refused"}], "returns": "{state: started, name, ...}"})
	R.register("fetch_cancel", _handler("fetch_cancel"), {"assistant": "files", "level": "change", "destructive": true,
			"description": "Stops the download; its partial file goes.", "returns": "{cancelling}"})
	R.register("copy_to_library", _handler("copy_to_library"), {"assistant": "files", "level": "change",
			"description": "The headset copies a file from a host saved in the player into the Library, with the "
			+ "login it holds (no SMB mount or smbclient is needed, and you never see the login). One at a time; the "
			+ "library_copy event says started, progress (at most once a second), done (path), failed (reason) or "
			+ "cancelled. Keeps 2 GB of the disk free.", "params": [
			{"name": "from", "type": "string", "required": true, "description": "smb://<a saved host>/<share>/<file>"},
			{"name": "to", "type": "string", "required": true, "description": "a path inside the Library, e.g. TV "
			+ "Shows/Show (2001)/Season 01/Show - S01E01 - Title.mkv; a file already there is refused"}],
			"returns": "{state: started, name, ...}"})
	R.register("copy_cancel", _handler("copy_cancel"), {"assistant": "files", "level": "change", "destructive": true,
			"description": "Stops the copy; its partial file goes.", "returns": "{cancelling}"})
	R.register("browse", _handler("browse"), {"assistant": "control", "level": "control",
			"description": "Asks the viewer to open a web page in the Browser source (public sites too): a card says "
			+ "what you want to open, with Open / No; nothing opens without Open. http and https only. Replies at once "
			+ "with pending: true; the browse event says opened, declined or timeout. You never get the browser's "
			+ "cookies, logins, form fields or page content.",
			"params": [{"name": "url", "type": "string", "required": true, "description": "an http(s) page"}],
			"returns": "{pending, card, url}"})
	R.register("add_place", _handler("add_place"), {"assistant": "files", "level": "change",
			"description": "Suggests a place for the file browser: smb://host or smb://host/share on this network, a "
			+ "folder under the home folder, or an http(s) page on this network (it goes under Browser). A card asks "
			+ "the viewer (Add / No); nothing is saved until they add it. Replies at once with pending: true; the "
			+ "place event says added, declined or timeout. Never give a login: the viewer is asked in the headset "
			+ "when a share needs one.", "params": [
			{"name": "label", "type": "string", "required": true, "description": "a short name, e.g. TV"},
			{"name": "path", "type": "string", "required": true, "description": "smb://host[/share], a folder or "
			+ "an http(s) page"}], "returns": "{pending, card, label, path}"})
	R.register("remove_place", _handler("remove_place"), {"assistant": "files", "level": "change",
			"description": "Suggests removing a place the viewer added (not the built-in ones): a card asks (Remove / "
			+ "Keep it); the place event says removed, declined or timeout.",
			"params": [{"name": "path", "type": "string", "required": true, "description": "the place's path"}],
			"returns": "{pending, card, label, path}"})
	R.register("room_state", _handler("room_state"), {"assistant": "read",
			"description": "The room on show, in the room frame (floor y = 0, the seat at the origin facing -Z): its "
			+ "document, the base room's own parts and colours, light, the screen (centre, size, facing), the viewer "
			+ "(seat, eyes, head), the seats, the bases a new room can start from, limits and supported_widgets.",
			"returns": "{doc, stock_parts, screen, viewer, seats, bases, limits, supported_widgets, allowed, ...}"})
	var doc := "a room document (schema 2, 1 still read; its JSON Schema is RoomDocument in GET /openapi.json)"
	R.register("room_apply", _handler("room_apply"), {"assistant": "room", "level": "change",
			"description": "Changes the room on show with a room document (schema 2): parts added or replaced by "
			+ "name, remove, recolour, light, sky.",
			"params": [{"name": "room", "type": "object", "required": true, "description": doc}],
			"returns": "{state: kept, name, warnings, perf, ...}"})
	R.register("new_room", _handler("new_room"), {"assistant": "room", "level": "change", "destructive": true,
			"description": "A whole new room from a room document (schema 2): a base (a room id) or base_model (a "
			+ ".glb room), and parts.",
			"params": [{"name": "room", "type": "object", "required": true, "description": doc}],
			"returns": "{state: kept, name, warnings, perf, ...}"})
	R.register("add_shape", _handler("add_shape"), {"assistant": "room", "level": "change",
			"description": "Adds a box, sphere, cylinder or plane (a part of the room document), optionally with a "
			+ "widget.", "params": [
			{"name": "name", "type": "string", "required": true, "description": "the part's name"},
			{"name": "type", "type": "string", "required": true, "description": "box, sphere, cylinder or plane",
			"enum": ["box", "sphere", "cylinder", "plane"]},
			{"name": "size", "type": "array", "required": true,
			"description": "box [w, h, d]; sphere [diameter]; cylinder [diameter, height]; plane [w, d]"},
			{"name": "position", "type": "array", "default": [0, 0, -2], "description": "[x, y, z] metres"},
			{"name": "rotation", "type": "array", "default": [0, 0, 0], "description": "[x, y, z] degrees"},
			{"name": "scale", "type": "any", "default": 1.0, "description": "a number or [x, y, z]"},
			{"name": "material", "type": "object", "default": {}, "description": "color, texture, emission, "
			+ "library_material (an id from materials), ..."},
			{"name": "widget", "type": "string", "default": "", "description": "a widget (supported_widgets)"},
			{"name": "widget_options", "type": "object", "default": {}, "description": "the widget's options"}],
			"returns": "{state: kept, name, warnings, perf, ...}"})
	R.register("add_text", _handler("add_text"), {"assistant": "room", "level": "change",
			"description": "Adds words to the room (a text part): sharp at any distance, facing +Z (rotate it like a "
			+ "plane stood up), centred on position.", "params": [
			{"name": "name", "type": "string", "required": true, "description": "the part's name"},
			{"name": "text", "type": "string", "required": true, "description": "at most 1000 characters"},
			{"name": "size", "type": "float", "default": 0.1, "description": "the height of a line, metres"},
			{"name": "position", "type": "array", "default": [0, 1.2, -2], "description": "[x, y, z] metres"},
			{"name": "rotation", "type": "array", "default": [0, 0, 0], "description": "[x, y, z] degrees"},
			{"name": "text_options", "type": "object", "default": {}, "description": "color, background, weight "
			+ "(regular, bold), align (left, center, right), max_width (metres; wraps)"}],
			"returns": "{state: kept, name, warnings, perf, ...}"})
	R.register("add_model", _handler("add_model"), {"assistant": "room", "level": "change",
			"description": "Adds a glTF model (.glb, base64, at most 20 MB).", "params": [
			{"name": "name", "type": "string", "required": true, "description": "the part's name"},
			{"name": "model", "type": "string", "required": true, "description": "the .glb file, base64"},
			{"name": "position", "type": "array", "default": [0, 0, -2], "description": "[x, y, z] metres"},
			{"name": "rotation", "type": "array", "default": [0, 0, 0], "description": "[x, y, z] degrees"},
			{"name": "scale", "type": "any", "default": 1.0, "description": "a number or [x, y, z]"},
			{"name": "material", "type": "object", "default": {}, "description": "color, texture, emission, "
			+ "library_material, ..."}],
			"returns": "{state: kept, name, warnings, perf, ...}"})
	R.register("recolour", _handler("recolour"), {"assistant": "room", "level": "change",
			"description": "Colour, emission, a picture, a library material (materials lists them) or an effect "
			+ "(effects lists them) on every part "
			+ "whose name matches (* and ?): the assistant's parts and the base room's own, a whole placed object "
			+ "by its name, or one part inside a placed object as \"<name>/<part>\" (object_info lists its parts).",
			"params": [
			{"name": "match", "type": "string", "required": true, "description": "a name pattern (* and ?), or "
			+ "\"<placed name>/<part name>\" (patterns on both sides) for parts inside placed objects"},
			{"name": "color", "type": "any", "default": null, "description": "#rrggbb or [r, g, b]"},
			{"name": "emission", "type": "any", "default": null, "description": "#rrggbb or [r, g, b]"},
			{"name": "emission_strength", "type": "float", "default": 1.0, "description": "0..10"},
			{"name": "texture", "type": "string", "default": "", "description": "a PNG or JPEG, base64"},
			{"name": "material", "type": "string", "default": "", "description": "a textured material from the "
			+ "material library (wood floors, carpet, velvet, leather, plaster, brick, marble, metal...): its id, "
			+ "from the materials command (tag to filter: floor, wall, fabric, wood, leather, metal, stone). It "
			+ "shows as itself; with color it shows that colour on average, its pattern kept. On a part that has "
			+ "one, color, tint, tiling and emission change it; texture replaces it. An id the headset doesn't know "
			+ "is left out with a warning"},
			{"name": "tint", "type": "any", "default": null, "description": "#rrggbb or [r, g, b]: multiplies a "
			+ "library material's colours (white: unchanged)"},
			{"name": "tiling", "type": "float", "default": 0.0, "description": "a library material's metres per "
			+ "repeat of its pattern (0.02..20; 0: the material's own, from the materials command)"},
			{"name": "triplanar", "type": "bool", "default": false, "description": "a library material blended "
			+ "from three directions, for curved models without usable UVs (three times the texture reads: only "
			+ "where the plain one shows seams)"},
			{"name": "effect", "type": "string", "default": "", "description": "an effect from the effect library "
			+ "(plasma, marble, neon, hologram...): its id, from the effects command (effect_info gives its "
			+ "options). One that layers goes over the part's colour or library material; one that draws its own "
			+ "surface replaces the material. Sky effects are for set_lighting's sky, not parts"},
			{"name": "effect_options", "type": "object", "default": {}, "description": "the effect's options "
			+ "within their bounds (effect_info), e.g. {\"color\": \"#ff40c0\", \"speed\": 0.2}; the rest keep "
			+ "their defaults"},
			{"name": "reset", "type": "bool", "default": false, "description": "back to the model's own colours "
			+ "(the part-level colours the match covers go; a whole object's colour too)"}],
			"returns": "{state: kept, name, warnings, perf, ...}"})
	R.register("set_lighting", _handler("set_lighting"), {"assistant": "room", "level": "change",
			"description": "The room's light (ambient 0..1, screen_glow 0..2) and the sky: a colour, a picture "
			+ "(base64), or none.", "params": [
			{"name": "ambient", "type": "float", "default": -1.0, "description": "0..1; -1: unchanged"},
			{"name": "screen_glow", "type": "float", "default": -1.0, "description": "0..2; -1: unchanged"},
			{"name": "sky_color", "type": "any", "default": null, "description": "#rrggbb or [r, g, b]"},
			{"name": "sky_image", "type": "string", "default": "", "description": "a PNG or JPEG, base64"},
			{"name": "sky_none", "type": "bool", "default": false, "description": "no sky"}],
			"returns": "{state: kept, name, warnings, perf, ...}"})
	R.register("remove", _handler("remove"), {"assistant": "room", "level": "change", "destructive": true,
			"description": "Removes a part the assistant added (never the screen, the panel or the player).",
			"params": [{"name": "name", "type": "string", "required": true, "description": "the part's name"}],
			"returns": "{state: kept, name, warnings, perf, ...}"})


static func _handler(cmd: String) -> Callable:
	return func(a: Dictionary, ctx: DevCommands.Call) -> Variant:
		var main := _main()
		if main == null or not ("player" in main):
			return ctx.fail("the player is not ready")
		var me: Variant = _via(ctx)
		var r: Dictionary = await me._own(cmd, a, main)
		return _give(ctx, r)


## The AssistantCommands a call belongs to (see register_commands()).
static func _via(ctx: DevCommands.Call) -> Variant:
	if ctx.caller != null and ctx.caller.has_method("_own"):
		return ctx.caller
	var tree := Engine.get_main_loop() as SceneTree
	var service: Node = tree.root.get_node_or_null(SERVICE_NODE) if tree != null else null
	if service != null and service.get("commands") != null:
		return service.commands
	return (load(SELF) as GDScript).new()


## An own handler's reply ({ok, result | error, summary, undo, refused, errors, limit, ...}) handed to the registry:
## the result returned, the rest on ctx (ctx.reply for the keys the API adds to its reply).
static func _give(ctx: DevCommands.Call, r: Dictionary) -> Variant:
	for k: String in r:
		if not (k in ["ok", "result", "error", "summary", "undo"]):
			ctx.reply[k] = r[k]
	if not bool(r.get("ok", false)):
		return ctx.fail(str(r.get("error", "")))
	ctx.summary = str(r.get("summary", ""))
	if r.get("undo") is Callable:
		ctx.undo = r["undo"]
	return r.get("result")


func _own(cmd: String, a: Dictionary, main: Node) -> Dictionary:
	match cmd:
		"state":
			var st := state(main, bool(allow_control.call()))
			st["room_allowed"] = bool(allow_room.call())
			return {"ok": true, "result": st}
		"tracks":
			return {"ok": true, "result": tracks(main)}
		"subtitle_lines":
			return await _subtitle_lines(int(a["count"]))
		"subtitle_track":
			var subs: Object = _feature(main, "subtitles")
			if subs == null:
				return {"ok": false, "error": "no subtitles here"}
			var index: int = a["index"]
			if index >= 0 and not (subs.get("tracks") as Array).any(func(t: Dictionary) -> bool:
					return int(t["index"]) == index):
				return {"ok": false, "error": "no subtitle track %d (tracks lists them)" % index}
			var before: Dictionary = subs.get_state()
			subs.select_track(index)
			return {"ok": true, "result": subs.get_state(), "summary": "subtitle track %d" % index,
					"undo": func() -> void: subs.set_state(before)}
		"audio_track":
			var src: Object = main.player.source
			var list: Array = src.get_audio_tracks() if src != null else []
			var index: int = a["index"]
			if not list.any(func(t: Dictionary) -> bool: return int(t.get("index", -1)) == index):
				return {"ok": false, "error": "no audio track %d (tracks lists them)" % index}
			var old := int(src.get_audio_track()) if src.has_method("get_audio_track") else -1
			main.player.select_audio_track(index)
			return {"ok": true, "result": {"audio_track": index}, "summary": "audio track %d" % index,
					"undo": (func() -> void: main.player.select_audio_track(old)) if old >= 0 else Callable()}
		"volume":
			var old: float = main.volume
			var v: float = a["level"] if float(a["level"]) >= 0.0 else old + float(a["step"])
			main.set_volume(clampf(v, 0.0, 1.0))
			return {"ok": true, "result": {"volume": main.volume}, "summary": "volume %d %%" % roundi(main.volume * 100),
					"undo": func() -> void: main.set_volume(old)}
		"reset_room":
			main.reset_room()
			return {"ok": true, "result": {"done": true}, "summary": "room reset"}
		"suggest_seat":
			var seat: Node = main.features.seat if main.get("features") != null else null
			var names: Array = seat.names() if seat != null else []
			var index := names.find(str(a["seat"]))
			if index < 0:
				return {"ok": false, "error": "no seat %s here (the seats: %s)" % [a["seat"], ", ".join(names)
						if not names.is_empty() else "none"]}
			var card: Node = main.ui.get("card") if main.get("ui") != null else null
			if card == null or not card.has_method("show_card"):
				return {"ok": false, "error": "no card to ask on"}
			var why := str(a["why"]).strip_edges().left(300)
			var id: String = card.show_card({"id": SEAT_CARD, "title": "A seat suggestion", "seconds": 30.0,
					"text": (why + "\n" if why != "" else "") + "Move to %s?" % names[index],
					"actions": [{"id": "go", "label": "Move there"}, {"id": "stay", "label": "Stay here"}]})
			var on_dismissed := func(card_id: String, how: String) -> void:
				if card_id == SEAT_CARD and how == "go" and is_instance_valid(seat):
					seat.go_to_seat(seat.names().find(str(names[index])))
			if card.has_signal("dismissed"):
				card.dismissed.connect(on_dismissed, CONNECT_ONE_SHOT)
			return {"ok": true, "result": {"shown": "card", "id": id, "seat": names[index]},
					"summary": "suggested %s" % names[index]}
		"browser_page":
			var src: Object = main.player.source
			if src == null or not src.has_method("is_browser") or not src.is_browser():
				return {"ok": true, "result": null}
			await src.refresh_page()
			return {"ok": true, "result": src.page_info()}
		"fetch":
			var f: Node = AssistantFetch.ensure(main.get_tree())
			if not f.is_inside_tree():
				await main.get_tree().process_frame
			var r: Dictionary = await f.start(str(a["url"]), str(a["name"]), bool(a["open"]), str(a["mode"]),
					str(a["to"]))
			if r.get("ok") == true:
				r["summary"] = "downloading %s" % r["result"]["name"]
			return r
		"fetch_cancel":
			return AssistantFetch.ensure(main.get_tree()).cancel()
		"copy_to_library":
			var c: Node = LibraryCopy.ensure(main.get_tree())
			if not c.is_inside_tree():
				await main.get_tree().process_frame
			var r: Dictionary = c.start(str(a["from"]), str(a["to"]))
			if r.get("ok") == true:
				r["summary"] = "copying %s" % r["result"]["name"]
			return r
		"copy_cancel":
			return LibraryCopy.ensure(main.get_tree()).cancel()
		"browse":
			var b: Node = AssistantBrowse.ensure(main.get_tree())
			if not b.is_inside_tree():
				await main.get_tree().process_frame
			return await b.suggest(str(a["url"]), client_name if client_name != "" else "An assistant")
		"add_place", "remove_place":
			var pl: Node = AssistantPlaces.ensure(main.get_tree())
			if not pl.is_inside_tree():
				await main.get_tree().process_frame
			var who := client_name if client_name != "" else "An assistant"
			if cmd == "add_place":
				return await pl.suggest_add(str(a["label"]), str(a["path"]), who)
			return await pl.suggest_remove(str(a["path"]), who)
		"room_state":
			if room == null:
				return {"ok": false, "error": "no room editor"}
			var st: Dictionary = room.state()
			st["allowed"] = bool(allow_room.call())
			return {"ok": true, "result": st}
	if cmd in ROOM_COMMANDS:
		return await _room(cmd, a)
	return {"ok": false, "error": "%s has no handler" % cmd}


## The room commands: each becomes a room document (room_schema.gd) for the editor.
func _room(cmd: String, a: Dictionary) -> Dictionary:
	if room == null:
		return {"ok": false, "error": "no room editor"}
	var doc := {"schema": RoomSchema.VERSION}
	var mode := "patch"
	var summary := ""
	match cmd:
		"room_apply", "new_room":
			doc = a["room"]
			mode = "new" if cmd == "new_room" else "patch"
			summary = "a new room" if mode == "new" else "a change to the room"
		"add_shape", "add_model":
			var part := {"name": a["name"], "type": "model" if cmd == "add_model" else a["type"],
					"position": a["position"], "rotation": a["rotation"], "scale": a["scale"]}
			if cmd == "add_model":
				part["model"] = a["model"]
			else:
				part["size"] = a["size"]
				if str(a["widget"]) != "":
					part["widget"] = a["widget"]
					part["widget_options"] = a["widget_options"]
			if not (a["material"] as Dictionary).is_empty():
				part["material"] = a["material"]
			doc["parts"] = [part]
			summary = "add %s" % a["name"]
		"add_text":
			var part := {"name": a["name"], "type": "text", "text": a["text"], "size": [a["size"]],
					"position": a["position"], "rotation": a["rotation"]}
			if not (a["text_options"] as Dictionary).is_empty():
				part["text_options"] = a["text_options"]
			doc["parts"] = [part]
			summary = "add %s" % a["name"]
		"recolour":
			var mat := {}
			if a["color"] != null:
				mat["color"] = a["color"]
			if a["emission"] != null:
				mat["emission"] = a["emission"]
				mat["emission_strength"] = a["emission_strength"]
			if str(a["texture"]) != "":
				mat["texture"] = a["texture"]
			if str(a["material"]) != "":
				mat["library_material"] = a["material"]
			if a["tint"] != null:
				mat["tint"] = a["tint"]
			if float(a["tiling"]) > 0.0:
				mat["tiling"] = a["tiling"]
			if bool(a["triplanar"]):
				mat["triplanar"] = true
			if str(a["effect"]) != "":
				var fx: Dictionary = (a["effect_options"] as Dictionary).duplicate(true) 						if a["effect_options"] is Dictionary else {}
				fx["name"] = str(a["effect"])
				mat["effect"] = fx
			var reset := bool(a["reset"])
			if mat.is_empty() and not reset:
				return {"ok": false, "error": "recolour: give color, emission, texture, material (with tint, tiling), "
						+ "effect or reset"}
			var pattern: String = a["match"]
			var current: Dictionary = room.current_doc()
			summary = ("reset %s" if reset else "recolour %s") % pattern
			if pattern.contains("/"):
				# A part inside a placed object ("Shelf/Board"): a part-level entry (scripts/assistant/object_library.gd).
				if RoomSchema.split_match(pattern).is_empty():
					return {"ok": false, "error": "recolour: a part is \"<placed name>/<part name>\""}
				var main := _main()
				var layer: Node = main.env.get_node_or_null("AssistantLayer") if main.env != null else null
				if ((load("res://scripts/assistant/assistant_room.gd") as GDScript).call("part_targets", layer, pattern)
						as Array).is_empty():
					return {"ok": false, "error": "recolour: no part of anything placed matches %s (object_info with "
							% pattern + "placed lists the parts)"}
				var entries: Array = ObjectCommands.recolour_entries(current, pattern, null if reset else mat)
				if entries.is_empty():
					return {"ok": false, "error": "recolour: %s has no colour of its own to reset" % pattern}
				doc["recolour"] = entries
				return await room.apply(mode, doc, summary)
			var parts: Array = []
			var dropped: Array = []
			for p: Dictionary in current.get("parts", []):
				if str(p["name"]).match(pattern):
					var q := p.duplicate(true)
					if RoomSchema.kind_of(q) == "text":
						# Words take their colour from text_options.
						if mat.has("color") or reset:
							var o: Dictionary = q.get("text_options", {})
							if reset:
								o.erase("color")
							else:
								o["color"] = mat["color"]
							q["text_options"] = o
							parts.append(q)
						continue
					if reset:
						q.erase("material")
					else:
						var m: Dictionary = q.get("material", {}) if q.get("material") is Dictionary else {}
						q["material"] = RoomSchema.merge_material(m, mat)
					parts.append(q)
					# A whole placed object takes the new colour all over: its part-level colours go.
					for r: Dictionary in current.get("recolour", []):
						var s := RoomSchema.split_match(str(r["match"]))
						if not s.is_empty() and s[0] == str(p["name"]):
							dropped.append({"match": r["match"], "material": null})
			var stock: Array = room.state()["stock_parts"]
			var hits := stock.filter(func(x: Dictionary) -> bool: return str(x["name"]).match(pattern))
			if parts.is_empty() and hits.is_empty():
				return {"ok": false, "error": "recolour: nothing is called %s (room_state lists the parts)" % pattern}
			if not parts.is_empty():
				doc["parts"] = parts
			var rec: Array = dropped
			if not hits.is_empty():
				rec.append({"match": pattern, "material": null if reset else ObjectCommands.entry_material(current,
						pattern, mat)})
			if not rec.is_empty():
				doc["recolour"] = rec
		"set_lighting":
			var light := {}
			if float(a["ambient"]) >= 0.0:
				light["ambient"] = a["ambient"]
			if float(a["screen_glow"]) >= 0.0:
				light["screen_glow"] = a["screen_glow"]
			if not light.is_empty():
				doc["light"] = light
			if a["sky_none"]:
				doc["sky"] = {}
			elif a["sky_color"] != null:
				doc["sky"] = {"color": a["sky_color"]}
			elif str(a["sky_image"]) != "":
				doc["sky"] = {"image": a["sky_image"]}
			if doc.size() == 1:
				return {"ok": false, "error": "set_lighting: give ambient, screen_glow or a sky"}
			summary = "light and sky"
		"remove":
			doc["remove"] = [a["name"]]
			summary = "remove %s" % a["name"]
	return await room.apply(mode, doc, summary)


static func _feature(main: Node, name: String) -> Object:
	if main == null or not ("features" in main) or main.features == null:
		return null
	return main.features.get(name)


## What plays, for `state` and the state event.
static func state(main: Node, control: bool) -> Dictionary:
	var s := CommandHost.state_of(main)
	for k in ["menu_shown", "xr", "session_focused", "mode_source", "auto_paused"]:
		s.erase(k)
	var ch: Object = _feature(main, "chapters")
	var list: Array = ch.get("chapters") if ch != null else []
	if not list.is_empty():
		var i: int = ch.index_at(main.player.get_position())
		s["chapter"] = {"n": i + 1, "count": list.size(), "title": str(list[i]["title"]) if i >= 0 else "",
				"start": snappedf(float(list[i]["start"]), 0.01) if i >= 0 else 0.0}
	var subs: Object = _feature(main, "subtitles")
	if subs != null:
		s["subtitles"] = subs.get_state()
	var src: Object = main.player.source
	if src != null and src.has_method("get_audio_track"):
		s["audio_track"] = int(src.get_audio_track())
	s["battery"] = InfoOverlay.read_battery()
	s["browser"] = src.page_info() if src != null and src.has_method("is_browser") and src.is_browser() else null
	var fetch: Node = main.get_tree().root.get_node_or_null(AssistantFetch.NODE_NAME) if main.is_inside_tree() \
			else null
	s["download"] = fetch.status() if fetch != null else null
	var copy: Node = main.get_tree().root.get_node_or_null(LibraryCopy.NODE_NAME) if main.is_inside_tree() else null
	s["library_copy"] = copy.status() if copy != null else null
	# For a file of the Library: what its NFO says (kind, title, show, season, episode, label, year, plot).
	var entry: Dictionary = LibraryIndex.details_for(str(s.get("path", "")))
	s["library"] = entry if not entry.is_empty() else null
	s["control"] = control
	s["room_allowed"] = false
	return s


static func tracks(main: Node) -> Dictionary:
	var src: Object = main.player.source
	var audio: Array = []
	for t: Dictionary in (src.get_audio_tracks() if src != null else []):
		audio.append(_track(t))
	var subtitle: Array = []
	var subs: Object = _feature(main, "subtitles")
	if subs != null:
		for t: Dictionary in subs.get("tracks"):
			subtitle.append(_track(t))
	return {"audio": audio, "audio_selected": int(src.get_audio_track()) if src != null
			and src.has_method("get_audio_track") else -1, "subtitles": subtitle,
			"subtitles_state": subs.get_state() if subs != null else {}}


static func _track(t: Dictionary) -> Dictionary:
	var out := {}
	for k in ["index", "title", "language", "codec", "channels", "default", "forced", "text"]:
		if t.has(k):
			out[k] = t[k]
	return out


## The lines said up to now (director mode's index), the last `count`.
func _subtitle_lines(count: int) -> Dictionary:
	if not DevCommands.has_command("script_lines"):
		return {"ok": true, "result": {"lines": []}}
	count = clampi(count, 1, 40)
	var main := _main()
	if main == null:
		return {"ok": true, "result": {"lines": []}}
	# First the lines the player has read while playing (a subtitle track selected, shown or not): instant, no file
	# reads. Then an index made already. Never start an index here: building one can read the whole film (minutes over
	# the network, competing with playback; seen on the headset: every voice clip waited for it).
	var subs: Object = _feature(main, "subtitles")
	if subs != null and subs.has_method("lines_before"):
		var said: Array = subs.lines_before(main.player.get_position(), count)
		if not said.is_empty():
			return {"ok": true, "result": {"lines": said, "source": "playback"}}
	if not Director.is_indexed(main):
		var why := "no subtitle lines yet: select a subtitle track (it may stay hidden) and they gather as the film plays"
		return {"ok": true, "result": {"lines": [], "note": why}}
	var r: Dictionary = await DevCommands.execute("script_lines", {"offset": -1, "count": count * 2}, true, self)
	if not r["ok"]:
		return {"ok": true, "result": {"lines": [], "note": str(r.get("error", ""))}}
	var res: Dictionary = r["result"]
	var cur := int(res.get("current", -1))
	var said: Array = []
	for x: Dictionary in res.get("lines", []):
		if int(x.get("i", 0)) <= cur:
			said.append({"start": x.get("start", 0.0), "text": str(x.get("text", ""))})
	return {"ok": true, "result": {"lines": said.slice(maxi(said.size() - count, 0)), "total": res.get("total", 0)}}
