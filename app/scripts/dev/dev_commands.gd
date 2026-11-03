extends RefCounted

## The control API's registry (docs/dev/control-protocol.md). Features register commands and settings here; the PC
## listener calls them over the dev link, and `describe` returns the schema of everything registered. Registering
## costs one dictionary entry, so features may register whether or not dev mode is on.
##
##   const DevCommands := preload("res://scripts/dev/dev_commands.gd")
##   DevCommands.register("depth", func(args: Dictionary, ctx: DevCommands.Call) -> Variant:
##       var old := depth
##       set_depth(args["shift"])
##       ctx.summary = "3D depth %.2f" % args["shift"]
##       ctx.undo = set_depth.bind(old)
##       return depth, {
##       "description": "Shifts the eye pictures apart.",
##       "params": [{"name": "shift", "type": "float", "required": true, "description": "-1..1"}],
##       "level": "control"})
##   DevCommands.register_setting("depth_3d", get_depth, set_depth, {"type": "float", "description": "..."})
##
## A handler takes (args, ctx) and returns the result (anything; converted to JSON). It may await. To fail, return
## ctx.fail("why"). A handler that changes something sets ctx.summary (shown in the headset) and, when it can be
## undone, ctx.undo. Spec keys:
##   description  one sentence
##   params       [{name, type, required, default, description, enum}] in positional order. Types: string, int,
##                float, bool, array, object, vector3, color, any. Values are converted before the handler runs.
##   level        "read" (default: changes nothing), "control" (playback: play, seek, open), "change" (settings and
##                the scene), "code" (runs code). The permission ring (scripts/dev/permission_ring.gd) gates each level.
##   returns      what the result is, one phrase
##   assistant    the consumer level when the assistant API may run it (docs/assistant.md): "read", "card",
##                "control", "room", "settings", "files" or "apps". Absent: the assistant never reaches it. Never on a
##                "code" command (register() drops it with an error). /describe, the guide, the OpenAPI and the MCP
##                tools are made from these tags.
##   title        optional: a short name for a client's tool list (the MCP adapter guesses one without)
##   destructive  optional, true when it deletes, overwrites, or stops an app or a session (the MCP adapter's hint)
##
## The registry lives in Engine metadata, so it survives a hot-reload of this script and `reload app`. It is emptied
## when the scene tree shuts down.

const META := "dev_commands_registry"
const LEVELS: Array[String] = ["read", "control", "change", "code"]
## The assistant API's levels (a spec's `assistant` key), in the order /describe lists them.
const ASSISTANT_LEVELS: Array[String] = ["read", "card", "control", "room", "settings", "files", "apps"]


## One call of a command: its arguments, and what the handler reports back.
class Call extends RefCounted:
	var name := ""
	var args := {}
	## From the PC (true), or from the headset itself (the pane, tests).
	var remote := true
	## The paired assistant client's name ("Claude Code on this headset"), or "" from the dev link, the pane or tests.
	var client := ""
	var error := ""
	## What changed, in a few words, for the toast in the headset. Empty for reads.
	var summary := ""
	## Undoes the change; empty when it can't be undone.
	var undo := Callable()
	## Called when the undo is dropped unused (a freed node kept for undo is freed for good then).
	var cleanup := Callable()
	## Who ran it: the gate given to execute() (the assistant's commands, the permission ring), or null.
	var caller: Object
	## Keys the assistant API adds to its reply beside result or error: refused, errors, limit, status.
	var reply := {}

	func fail(message: String) -> Variant:
		error = message
		return null


static func _store() -> Dictionary:
	if not Engine.has_meta(META):
		Engine.set_meta(META, {"commands": {}, "settings": {}, "events": {}})
		# The registry holds script Callables in Engine metadata, which outlives the script language at exit: freeing
		# them then crashed the engine (segfault at quit with --dev). Empty it when the tree shuts down.
		var tree := Engine.get_main_loop() as SceneTree
		if tree != null and tree.root != null:
			tree.root.tree_exiting.connect(clear, CONNECT_ONE_SHOT)
	return Engine.get_meta(META)


## Forgets every command, setting and event (at exit).
static func clear() -> void:
	if Engine.has_meta(META):
		Engine.remove_meta(META)


## Adds or replaces a command.
static func register(command: String, handler: Callable, spec := {}) -> void:
	var s := spec.duplicate(true)
	s["handler"] = handler
	if not s.has("level"):
		s["level"] = "read"
	assert(s["level"] in LEVELS, "level must be one of %s" % [LEVELS])
	if not s.has("params"):
		s["params"] = []
	if s.has("assistant"):
		if s["level"] == "code":
			push_error("%s runs code: never reachable from the assistant API (its assistant tag is dropped)" % command)
			s.erase("assistant")
		elif not (str(s["assistant"]) in ASSISTANT_LEVELS):
			push_error("%s: assistant must be one of %s (the tag is dropped)" % [command, ASSISTANT_LEVELS])
			s.erase("assistant")
	var store := _store()
	# A second script registering the same name replaces the first without a word: note it (clashes()). The same
	# script again (a hot reload, a second instance) is not a clash.
	var source := _source(handler)
	var sources: Dictionary = store.get_or_add("sources", {})
	if store["commands"].has(command) and str(sources.get(command, "")) not in ["", source] and source != "":
		(store.get_or_add("clashes", []) as Array).append({"command": command, "first": sources[command],
				"then": source})
	sources[command] = source
	store["commands"][command] = s
	store["version"] = int(store.get("version", 0)) + 1


## The script a handler comes from (a lambda's object is its script; a method's, the instance), or "".
static func _source(handler: Callable) -> String:
	var o := handler.get_object()
	if o is Script:
		return (o as Script).resource_path
	var script: Variant = o.get_script() if o != null else null
	return (script as Script).resource_path if script is Script else ""


## Names registered by two different scripts, the later one winning: [{command, first, then}].
static func clashes() -> Array:
	return _store().get("clashes", []).duplicate()


static func unregister(command: String) -> void:
	var store := _store()
	store["commands"].erase(command)
	store["version"] = int(store.get("version", 0)) + 1


## Goes up at every register() and unregister(): a client of the registry can tell the commands may have changed.
static func version() -> int:
	return int(_store().get("version", 0))


static func has_command(command: String) -> bool:
	return _store()["commands"].has(command)


static func command_names() -> Array:
	var names: Array = _store()["commands"].keys()
	names.sort()
	return names


## The commands the assistant API may run (an `assistant` tag), sorted.
static func assistant_names() -> Array:
	var all: Dictionary = _store()["commands"]
	return command_names().filter(func(c: String) -> bool: return all[c].has("assistant"))


## A command's assistant level, or "" when the assistant API can't run it.
static func assistant_level(command: String) -> String:
	return str(_store()["commands"].get(command, {}).get("assistant", ""))


## The spec without the handler, or {}.
static func get_spec(command: String) -> Dictionary:
	var s: Dictionary = _store()["commands"].get(command, {})
	var out := s.duplicate(true)
	out.erase("handler")
	return out


## A setting reachable with `get` and `set`. getter() -> value; setter(value). Spec: type, description, and
## optionally min, max, enum, level (default "change").
static func register_setting(setting: String, getter: Callable, setter: Callable, spec := {}) -> void:
	var s := spec.duplicate(true)
	s["getter"] = getter
	s["setter"] = setter
	if not s.has("level"):
		s["level"] = "change"
	if not s.has("type"):
		s["type"] = "any"
	_store()["settings"][setting] = s


static func has_setting(setting: String) -> bool:
	return _store()["settings"].has(setting)


static func setting_names() -> Array:
	var names: Array = _store()["settings"].keys()
	names.sort()
	return names


static func get_setting(setting: String) -> Variant:
	var s: Dictionary = _store()["settings"][setting]
	return (s["getter"] as Callable).call()


static func setting_spec(setting: String) -> Dictionary:
	var s: Dictionary = _store()["settings"].get(setting, {})
	var out := s.duplicate(true)
	out.erase("getter")
	out.erase("setter")
	return out


## Sets a registered setting from a JSON value (converted to its type). Returns "" or the error.
static func set_setting(setting: String, value: Variant) -> String:
	var s: Dictionary = _store()["settings"].get(setting, {})
	if s.is_empty():
		return "no setting %s" % setting
	var conv := coerce(value, str(s["type"]))
	if conv[1] != "":
		return "%s: %s" % [setting, conv[1]]
	var v: Variant = conv[0]
	if s.has("enum") and not (v in (s["enum"] as Array)):
		return "%s must be one of %s" % [setting, s["enum"]]
	if s.has("min") and (v is float or v is int) and v < s["min"]:
		return "%s must be at least %s" % [setting, s["min"]]
	if s.has("max") and (v is float or v is int) and v > s["max"]:
		return "%s must be at most %s" % [setting, s["max"]]
	(s["setter"] as Callable).call(v)
	return ""


## Documents an event the app sends (for `describe`): name -> {description, data}.
static func register_event(event_name: String, description: String, data := {}) -> void:
	_store()["events"][event_name] = {"description": description, "data": data}


## The schema of everything registered.
static func describe() -> Dictionary:
	var commands := {}
	for c: String in command_names():
		commands[c] = get_spec(c)
	var settings := {}
	for s: String in setting_names():
		settings[s] = setting_spec(s)
	return {"commands": commands, "settings": settings, "events": _store()["events"].duplicate(true)}


## A command's params as a JSON Schema (draft 2020-12) object: what the assistant's /describe gives each command as
## input_schema and the OpenAPI as its arguments, so a client needs no type mapping of its own.
static func params_schema(params: Array) -> Dictionary:
	var props := {}
	var required: Array = []
	for p: Dictionary in params:
		var s := type_schema(str(p.get("type", "any")))
		if p.has("description"):
			s["description"] = str(p["description"])
		if p.has("enum"):
			s["enum"] = to_json(p["enum"])
		if p.has("default"):
			s["default"] = to_json(p["default"])
		props[p["name"]] = s
		if bool(p.get("required", false)):
			required.append(p["name"])
	var out := {"type": "object", "properties": props, "additionalProperties": false}
	if not required.is_empty():
		out["required"] = required
	return out


## The JSON Schema of one param type.
static func type_schema(type: String) -> Dictionary:
	match type:
		"string":
			return {"type": "string"}
		"int":
			return {"type": "integer"}
		"float":
			return {"type": "number"}
		"bool":
			return {"type": "boolean"}
		"array":
			return {"type": "array"}
		"object":
			return {"type": "object"}
		"vector3":
			return {"type": "array", "items": {"type": "number"}, "minItems": 3, "maxItems": 3}
		"color":
			return {"anyOf": [{"type": "array", "items": {"type": "number"}, "minItems": 3, "maxItems": 4},
					{"type": "string"}]}
	return {}


## Runs a command: checks and converts the arguments, calls the handler (awaiting it), and returns
## {"ok": bool, "result": ..., "error": "...", "call": Call}. `gate` (the permission ring, or null) is asked first:
## gate.check(ctx, spec) returns "" or why the call is refused.
static func execute(command: String, args: Dictionary, remote := true, gate: Object = null) -> Dictionary:
	var ctx := Call.new()
	ctx.name = command
	ctx.remote = remote
	ctx.caller = gate
	var spec: Dictionary = _store()["commands"].get(command, {})
	if spec.is_empty():
		return {"ok": false, "error": "no command %s (try describe)" % command, "call": ctx}
	var handler: Callable = spec["handler"]
	if not handler.is_valid():
		return {"ok": false, "error": "%s: its handler is gone" % command, "call": ctx}
	var params: Array = spec["params"]
	var known := {}
	for p: Dictionary in params:
		var pname: String = p["name"]
		known[pname] = true
		if args.has(pname):
			var conv := coerce(args[pname], str(p.get("type", "any")))
			if conv[1] != "":
				return {"ok": false, "error": "%s: %s: %s" % [command, pname, conv[1]], "call": ctx}
			if p.has("enum") and not (conv[0] in (p["enum"] as Array)):
				return {"ok": false, "error": "%s: %s must be one of %s" % [command, pname, p["enum"]], "call": ctx}
			ctx.args[pname] = conv[0]
		elif bool(p.get("required", false)):
			return {"ok": false, "error": "%s: %s is required" % [command, pname], "call": ctx}
		elif p.has("default"):
			ctx.args[pname] = p["default"]
	for k: String in args:
		if not known.has(k):
			return {"ok": false, "error": "%s: unknown argument %s" % [command, k], "call": ctx}
	if gate != null:
		var refusal: String = gate.check(ctx, spec)
		if refusal != "":
			return {"ok": false, "error": refusal, "call": ctx, "refused": true}
	var result: Variant = await handler.call(ctx.args, ctx)
	if ctx.error != "":
		return {"ok": false, "error": ctx.error, "call": ctx}
	return {"ok": true, "result": to_json(result), "call": ctx}


## [value, error]: a JSON value converted to `type`.
static func coerce(v: Variant, type: String) -> Array:
	match type:
		"any", "":
			return [v, ""]
		"string":
			return [str(v), ""] if not (v is Dictionary or v is Array) else [null, "expected a string"]
		"int":
			if v is int or (v is float and v == floorf(v)):
				return [int(v), ""]
			if v is String and (v as String).is_valid_int():
				return [(v as String).to_int(), ""]
			return [null, "expected an integer"]
		"float":
			if v is int or v is float:
				return [float(v), ""]
			if v is String and (v as String).is_valid_float():
				return [(v as String).to_float(), ""]
			return [null, "expected a number"]
		"bool":
			if v is bool:
				return [v, ""]
			if v is String and (v as String).to_lower() in ["true", "false", "on", "off", "1", "0", "yes", "no"]:
				return [(v as String).to_lower() in ["true", "on", "1", "yes"], ""]
			if v is int or v is float:
				return [v != 0, ""]
			return [null, "expected true or false"]
		"array":
			return [v, ""] if v is Array else [null, "expected a list"]
		"object":
			return [v, ""] if v is Dictionary else [null, "expected an object"]
		"vector3":
			if v is Vector3:
				return [v, ""]
			if v is Array and (v as Array).size() == 3:
				return [Vector3(float(v[0]), float(v[1]), float(v[2])), ""]
			if v is String:
				var parsed: Variant = str_to_var(v)
				if parsed is Vector3:
					return [parsed, ""]
			return [null, "expected [x, y, z]"]
		"color":
			if v is Color:
				return [v, ""]
			if v is Array and (v as Array).size() in [3, 4]:
				return [Color(float(v[0]), float(v[1]), float(v[2]), float(v[3]) if v.size() == 4 else 1.0), ""]
			if v is String and Color.html_is_valid(v):
				return [Color.html(v), ""]
			return [null, "expected [r, g, b(, a)] or #rrggbb"]
	return [v, ""]


## Any value to something JSON can carry. Vectors, colours and transforms become lists of numbers; other engine
## types become their var_to_str() text; objects become "<Class:id>" (nodes: their path).
static func to_json(v: Variant, depth := 0) -> Variant:
	if depth > 32:
		return "..."
	match typeof(v):
		TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_STRING:
			return v
		TYPE_FLOAT:
			return v if is_finite(v) else str(v)
		TYPE_STRING_NAME, TYPE_NODE_PATH:
			return str(v)
		TYPE_VECTOR2, TYPE_VECTOR2I:
			return [v.x, v.y]
		TYPE_VECTOR3, TYPE_VECTOR3I:
			return [v.x, v.y, v.z]
		TYPE_VECTOR4, TYPE_VECTOR4I, TYPE_QUATERNION:
			return [v.x, v.y, v.z, v.w]
		TYPE_COLOR:
			return [v.r, v.g, v.b, v.a]
		TYPE_DICTIONARY:
			var out := {}
			for k: Variant in v:
				out[str(k)] = to_json(v[k], depth + 1)
			return out
		TYPE_ARRAY:
			var arr: Array = []
			for e: Variant in v:
				arr.append(to_json(e, depth + 1))
			return arr
		TYPE_PACKED_BYTE_ARRAY:
			return "<%d bytes>" % (v as PackedByteArray).size()
		TYPE_OBJECT:
			if v == null or not is_instance_valid(v):
				return null
			if v is Node and (v as Node).is_inside_tree():
				return "<%s:%s>" % [(v as Node).get_class(), (v as Node).get_path()]
			if v is Resource and (v as Resource).resource_path != "":
				return "<%s:%s>" % [(v as Object).get_class(), (v as Resource).resource_path]
			return "<%s:%d>" % [(v as Object).get_class(), (v as Object).get_instance_id()]
	if typeof(v) >= TYPE_PACKED_INT32_ARRAY and typeof(v) <= TYPE_PACKED_VECTOR4_ARRAY:
		var arr2: Array = []
		for e: Variant in v:
			arr2.append(to_json(e, depth + 1))
		return arr2
	return var_to_str(v)
