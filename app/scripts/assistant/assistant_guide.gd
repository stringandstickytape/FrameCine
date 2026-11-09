extends RefCounted

## What the assistant service says about itself (docs/assistant.md): the guide at GET / (markdown written for an AI
## agent reading it cold: res://assistant/guide.md, filled in here with the address, the state, the live command list,
## the widgets and the limits) and the OpenAPI 3.1 description at GET /openapi.json (with the room document's schema,
## res://assistant/room_schemas.json).

const AssistantCommands := preload("res://scripts/assistant/assistant_commands.gd")
const DevCommands := preload("res://scripts/dev/dev_commands.gd")
const RoomSchema := preload("res://scripts/assistant/room_schema.gd")

const GUIDE := "res://assistant/guide.md"
const ROOM_SCHEMAS := "res://assistant/room_schemas.json"
## The Library's layout and how to fill it: here and in the instructions of an agent on the headset.
const LIBRARY := "res://assistant/library.md"

const EVENTS := [
	["status", "first on every stream: as GET /status"],
	["state", "what plays: when you connect, on play / pause, and every 10 s while playing (as GET /state)"],
	["file_opened", "a file opened: {path, title}"],
	["permissions", "the viewer turned a switch on or off: {control, room, settings, files, apps}, each true or false"],
	["commands", "the commands changed (GET /describe again): {count}"],
	["voice_state", "the talk button pressed or let go: {recording}"],
	["viewer_message", "the viewer spoke: {id, text (null without speech to text), heard_at, seconds, context, "
			+ "block, audio}"],
	["card_dismissed", "the card went away: {id, how: user | timeout | cleared}"],
	["room", "a room change is on show and kept: {state: kept, change, name}"],
	["pairing", "a pairing step: {state: started | paired | failed | cancelled, client}"],
	["browse", "a page you asked to open (browse), once the viewer answered: {state: opened | declined | timeout, "
			+ "url, how: devtools | launch}"],
	["place", "a place you suggested (add_place, remove_place), once the viewer answered: {state: added | "
			+ "removed | declined | timeout, label, path, kind}"],
	["download", "the headset's download (fetch): {state: started | progress | done | failed | cancelled, name; "
			+ "progress: bytes, total (-1 unknown), rate (bytes/s), at most once a second; done: path; failed: "
			+ "reason}"],
	["library_copy", "a copy into the Library (copy_to_library): {state: started | progress | done | failed | "
			+ "cancelled, name; progress: bytes, total, rate (bytes/s), at most once a second; done: path; failed: "
			+ "reason}"],
]


static func guide(url: String, status: String, pin := "") -> String:
	var text := FileAccess.get_file_as_string(GUIDE)
	if text == "":
		text = "# FrameCine: assistant service\n\n**Now:** <<STATUS>>\n\n(The guide file is missing.)\n"
	var host := url.trim_prefix("https://").get_slice("/", 0)
	var port := "47801"
	if host.begins_with("["):
		port = host.get_slice("]:", 1) if host.contains("]:") else port
		host = host.trim_prefix("[").get_slice("]", 0)
	elif host.contains(":"):
		port = host.get_slice(":", 1)
		host = host.get_slice(":", 0)
	var d := AssistantCommands.describe()
	var rows: PackedStringArray = []
	for c: Dictionary in by_level(d["commands"]):
		var params: PackedStringArray = []
		for p: Dictionary in c["params"]:
			params.append("%s%s: %s" % [p["name"], "" if p.get("required", false) else "?", p.get("type", "any")])
		rows.append("| `%s` | %s | %s | %s |" % [c["name"], c["level"], ", ".join(params) if not params.is_empty()
				else "-", _cell(c["description"])])
	var levels: PackedStringArray = []
	for l: String in d["levels"]:
		var e: Dictionary = d["levels"][l]
		levels.append("| %s | %s | %s |" % [l, e["what"], "always" if e["switch"] == null else "\"%s\"" % e["switch"]])
	var events: PackedStringArray = []
	for e: Array in EVENTS:
		events.append("- `%s`: %s" % e)
	var widgets: PackedStringArray = []
	var names: Array = RoomSchema.WIDGETS.keys()
	names.sort()
	for n: String in names:
		var w: Dictionary = RoomSchema.WIDGETS[n]
		var opts: PackedStringArray = []
		for k: String in w.get("options", {}):
			var o: Dictionary = w["options"][k]
			var kind := "|".join(o["values"]) if o.has("values") else str(o.get("type", ""))
			opts.append("`%s` %s" % [k, kind])
		widgets.append("- `%s`: %s.%s" % [n, w["description"], (" Options: " + ", ".join(opts)) if not opts.is_empty()
				else ""])
	var limits: PackedStringArray = []
	for k: String in RoomSchema.LIMITS:
		limits.append("%s %s" % [k, RoomSchema.LIMITS[k]])
	return text.replace("<<LIBRARY>>", FileAccess.get_file_as_string(LIBRARY).strip_edges()) \
			.replace("<<STATUS>>", status).replace("<<URL>>", url).replace("<<HOST>>", host) \
			.replace("<<PORT>>", port).replace("<<COMMANDS>>", "\n".join(rows)) \
			.replace("<<LEVELS>>", "\n".join(levels)).replace("<<EVENTS>>", "\n".join(events)) \
			.replace("<<WIDGETS>>", "\n".join(widgets)).replace("<<LIMITS>>", ", ".join(limits)) \
			.replace("<<PIN>>", pin if pin != "" else "sha256//PIN") \
			.replace("<<PINSHORT>>", pin.trim_prefix("sha256//").left(8) if pin != "" else "(see the headset)")


static func events() -> Array:
	return EVENTS.map(func(e: Array) -> Dictionary: return {"name": e[0], "description": e[1]})


## /describe's commands in the levels' order (read, card, control, room, settings, files, apps), by name within one.
static func by_level(commands: Array) -> Array:
	var out := commands.duplicate()
	var order := DevCommands.ASSISTANT_LEVELS
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var la := order.find(str(a["level"]))
		var lb := order.find(str(b["level"]))
		return la < lb if la != lb else str(a["name"]) < str(b["name"]))
	return out


## Text for one cell of a markdown table.
static func _cell(text: String) -> String:
	return text.replace("|", "\\|").replace("\n", " ")


static func openapi(url: String) -> Dictionary:
	var ok := {"description": "{ok, result} or {ok: false, error}",
			"content": {"application/json": {"schema": {"$ref": "#/components/schemas/Reply"}}}}
	var bearer := [{"token": []}]
	var op := func(summary: String, body: Variant = null, params: Array = [], public := false) -> Dictionary:
		var o := {"summary": summary, "responses": {"200": ok, "401": {"description": "no token or a wrong one"}}}
		if body != null:
			o["requestBody"] = {"required": true, "content": {"application/json": {"schema": body},
					"application/x-www-form-urlencoded": {"schema": body}}}
		if not params.is_empty():
			o["parameters"] = params
		o["security"] = [] if public else bearer
		return o
	var q := func(name: String, type: String, desc: String, required := false) -> Dictionary:
		return {"name": name, "in": "query", "required": required, "schema": {"type": type}, "description": desc}
	var room_args := {"type": "object", "required": ["room"], "additionalProperties": false,
			"properties": {"room": {"$ref": "#/components/schemas/RoomDocument"}}}
	var one_of: Array = []
	for c: Dictionary in by_level(AssistantCommands.describe()["commands"]):
		one_of.append({"type": "object", "title": c["name"], "required": ["cmd"], "additionalProperties": false,
				"description": "%s (%s)" % [c["description"], c["level"]],
				"properties": {"cmd": {"const": c["name"]}, "args": room_args if c["name"] in ["room_apply", "new_room"]
				else c["input_schema"]}})
	var text_body := func(required: Array, props: Dictionary) -> Dictionary:
		return {"type": "object", "required": required, "properties": props}
	var schemas: Dictionary = {}
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(ROOM_SCHEMAS)) == OK and json.data is Dictionary:
		schemas = json.data
	if schemas.has("Part"):
		var widget_names: Array = RoomSchema.WIDGETS.keys()
		widget_names.sort()
		schemas["Part"]["properties"]["widget"] = {"enum": widget_names}
	schemas["Reply"] = {"type": "object", "required": ["ok"], "properties": {"ok": {"type": "boolean"}, "result": {},
			"error": {"type": "string"}, "refused": {"type": "boolean"}, "errors": {"type": "array", "items": {
			"type": "object", "properties": {"path": {"type": "string"}, "error": {"type": "string"}}}}}}
	return {
		"openapi": "3.1.0",
		"info": {"title": "FrameCine assistant service", "version": "2",
				"description": "A VR video player on a headset on this network. Read %s/ first." % url},
		"servers": [{"url": url}],
		"components": {"schemas": schemas, "securitySchemes": {"token": {"type": "http", "scheme": "bearer",
				"description": "the token from POST /pair"}}},
		"paths": {
			"/": {"get": {"summary": "The guide (markdown)", "security": [],
					"responses": {"200": {"description": "text/markdown"}}}},
			"/pair/start": {"post": op.call("Asks to pair (only while the viewer opened pairing)", text_body.call(
					["client"], {"client": {"type": "string"}}), [], true)},
			"/pair": {"post": op.call("Sends the code the headset shows; returns token, pin, cert_sha256",
					text_body.call(["pair_id", "code"], {"pair_id": {"type": "string"}, "code": {"type": "string"}}),
					[], true)},
			"/status": {"get": op.call("Paired assistants, permissions, speech to text, pairing")},
			"/describe": {"get": op.call("The commands with parameter types, and the events")},
			"/state": {"get": op.call("What plays now")},
			"/places": {"get": op.call("The file browser's places")},
			"/perf": {"get": op.call("The room's measured cost: GPU and CPU ms per frame, the frame rate, video "
					+ "frames dropped, headroom against the frame budget, whether a film plays")},
			"/snapshot.png": {"get": {"summary": "A picture of what the viewer sees (or the view from the seat), "
					+ "rendered on demand", "security": bearer, "parameters": [
					q.call("from", "string", "viewer (the head now, default) or seat (the seated eyes, facing the "
							+ "screen)"),
					q.call("seat", "string", "with from=seat: a seat's name (room_state's seats), else the seat in "
							+ "use"),
					q.call("width", "integer", "pixels, default 640, at most 1280"),
					q.call("height", "integer", "pixels, default width x 9 / 16, at most 1280"),
					q.call("fov", "number", "vertical field of view in degrees, default 60")],
					"responses": {"200": {"description": "image/png"}, "401": {"description": "no token or a wrong "
					+ "one"}, "503": {"description": "no picture (no renderer)"}, "400": {"description": "a bad from or seat"}}}},
			"/snapshot_clip.png": {"get": {"summary": "A few seconds of what the viewer sees: the frames in one PNG "
					+ "(a grid, left to right then down; X-Frames and X-Columns say how many) or an animated PNG",
					"security": bearer, "parameters": [
					q.call("from", "string", "viewer (default) or seat"),
					q.call("seat", "string", "with from=seat: a seat's name"),
					q.call("seconds", "number", "default 2, at most 4"),
					q.call("fps", "integer", "frames a second, default 8, at most 12"),
					q.call("width", "integer", "pixels a frame, default 320, at most 640"),
					q.call("height", "integer", "pixels a frame, default width x 9 / 16"),
					q.call("format", "string", "sheet (default) or apng"),
					q.call("fov", "number", "vertical field of view in degrees, default 60")],
					"responses": {"200": {"description": "image/png (sheet) or image/apng"},
					"401": {"description": "no token or a wrong one"},
					"503": {"description": "no picture (no renderer)"}}}},
			"/list": {"get": op.call("A folder's entries", null, [q.call("path", "string", "a folder", true)])},
			"/command": {"post": op.call("Runs one command", {"oneOf": one_of})},
			"/card": {"post": op.call("Shows text on the card beside the screen", text_body.call(["text"], {
					"text": {"type": "string"}, "title": {"type": "string"}, "seconds": {"type": "number"}}))},
			"/answer": {"post": op.call("Answers the viewer (under the conversation on the card)", text_body.call(
					["text"], {"text": {"type": "string"}, "heard": {"type": "string"},
					"message_id": {"type": "integer"}}))},
			"/messages": {"get": op.call("What the viewer said", null, [q.call("since", "integer", "after this id"),
					q.call("limit", "integer", "at most this many")])},
			"/messages/wait": {"get": op.call("Waits for the next thing the viewer says", null, [
					q.call("since", "integer", "after this id (default: the newest now)"),
					q.call("timeout", "number", "seconds, at most 600 (default 60)")])},
			"/events": {"get": {"summary": "Server-sent events", "security": bearer,
					"parameters": [q.call("types", "string", "comma-separated event names")],
					"responses": {"200": {"description": "text/event-stream"}}}},
			"/voice/{id}.wav": {"get": {"summary": "A viewer message's audio (16 kHz mono WAV)", "security": bearer,
					"parameters": [{"name": "id", "in": "path", "required": true, "schema": {"type": "integer"}}],
					"responses": {"200": {"description": "audio/wav"}}}},
			"/forget": {"post": op.call("Forgets the calling assistant: its token stops working")},
		},
	}
