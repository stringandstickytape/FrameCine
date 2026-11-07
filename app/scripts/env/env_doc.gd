extends RefCounted

## The version 4 room document's own sections (docs/environments.md, "The version 4 document"): room, acoustics,
## systems, settings, cues, timeline, audio and credits. room_schema.gd validates a version 4 document as version 3
## and hands these sections here (validate_sections), so every problem comes back with its JSON path in one list.
## Also the parameter and binding checks the systems' specs are read with, the common room settings, the film
## signals' channel names and the timeline's states. Data only: nothing here runs what a document says.
## Static; preload to use.
##
##   EnvDoc.validate(doc) -> {ok, errors}             a whole document (RoomSchema.validate(doc, "new"))
##   EnvDoc.load_file(path) -> {doc, errors}          a document that ships, read and checked
##   EnvDoc.with_defaults(params_spec, given) -> {}   a system's parameters with the defaults filled in
##   EnvDoc.check_value(spec, value, path, errors, ctx)   one parameter's value (or binding)
##   EnvDoc.settings_of(doc) -> Array                 the room's own declarations, as given

const Registry := preload("res://scripts/env/systems/registry.gd")
const RoomSchema := preload("res://scripts/assistant/room_schema.gd")
const MaterialLibrary := preload("res://scripts/env/material_library.gd")

const VERSION := 4
## The sections version 4 adds to version 3.
const SECTIONS: Array[String] = ["room", "acoustics", "systems", "settings", "cues", "timeline", "audio", "credits"]
## Film signals and the other channels a binding may follow (docs/environments.md, "Bindings and film signals"), by
## what they give: unit (0..1), raw (any number), color, name (a state's name: map it). weather.*: systems/weather.gd.
const CHANNELS := {
	"film.colour": "color", "film.brightness": "unit", "film.bass": "unit", "film.transient": "unit",
	"film.quiet": "unit", "film.progress": "unit", "film.minutes": "raw", "time.of_day": "unit",
	"playback.state": "name", "playback.playing": "unit", "comfort.motion": "unit",
	"weather.rain": "unit", "weather.snow": "unit", "weather.wet": "unit"}
const SETTING_PREFIX := "setting."
## The timeline's states (env_timeline.gd).
const STATES: Array[String] = ["preshow", "starting", "playing", "paused", "intermission", "credits", "ended"]
const PARAM_TYPES: Array[String] = ["float", "int", "bool", "color", "enum", "vec2", "vec3", "string", "list",
		"material", "object"]
const SETTING_TYPES: Array[String] = ["bool", "range", "choice"]
const FORMATS: Array[String] = ["percent", "db", "seconds", "minutes", "times", "number"]
const STEP_KINDS: Array[String] = ["set", "wait", "release", "do", "sound"]
const EASES: Array[String] = ["linear", "in", "out", "in_out"]
const LIMITS := {"systems": 32, "settings": 16, "cues": 32, "steps": 32, "tracks": 16, "credits": 64,
		"choices": 8, "keys": 32, "label": 40, "description": 200, "name": 32, "seconds": 600.0,
		"cooldown": 86400.0}
## A library material's keys in a "material" parameter.
const MATERIAL_KEYS: Array[String] = ["library", "color", "tint", "tiling", "pleats", "pleat_depth", "spill"]
## The synthesised sounds a cue may play (env_synth.gd NAMES; kept here so a document is checked without it).
const SOUNDS: Array[String] = ["chime", "gong", "rumble", "tick", "noise", "whale", "creak",
		"moped", "train", "huskies", "hull_creak"]

## The common room settings (docs/environments.md, "Common settings"): every room has them, from the shared systems.
## "applies": when it shows (always; the room has curtains or a cue that requires it; a system of that kind; a
## parameter that flickers; a motion parameter). Labels and descriptions are keys (COMMON_TEXTS).
const COMMON_SETTINGS := [
	{"name": "dim", "type": "bool", "default": true, "applies": "always",
		"label": "Dim during the film", "description": "The room's light goes down while the film plays."},
	{"name": "ambience_db", "type": "range", "min": -25.0, "max": 6.0, "step": 1.0, "default": 0.0, "format": "db",
		"off_at_min": true, "applies": "always",
		"label": "Ambience", "description": "This room's sound against the Environment sound slider. At the bottom: off."},
	{"name": "life", "type": "bool", "default": true, "applies": "life",
		"label": "Ambient life", "description": "Animals and other life in the room."},
	{"name": "ritual", "type": "bool", "default": true, "applies": "ritual",
		"label": "Pre-show", "description": "Curtains before the film, and the room's start of the show."},
	{"name": "flicker", "type": "bool", "default": true, "applies": "flicker",
		"label": "Flickering lights", "description": "Off: lights that flicker stay steady."},
	{"name": "motion", "type": "range", "min": 0.0, "max": 1.0, "step": 0.1, "default": 1.0, "format": "percent",
		"applies": "motion",
		"label": "Motion", "description": "How much things in the room move: sways, tilts, weave."},
]
# i18n: begin
const COMMON_TEXTS := ["Dim during the film", "The room's light goes down while the film plays.", "Ambience",
		"This room's sound against the Environment sound slider. At the bottom: off.", "Ambient life",
		"Animals and other life in the room.", "Pre-show", "Curtains before the film, and the room's start of the show.",
		"Flickering lights", "Off: lights that flicker stay steady.", "Motion",
		"How much things in the room move: sways, tilts, weave."]
# i18n: end

const ROOM_OPTIONS := {
	"ambient": {"type": "float", "min": 0.0, "max": 1.0, "default": 0.0},
	"screen_glow": {"type": "float", "min": 0.0, "max": 2.0, "default": 0.0},
	"curtains": {"type": "bool", "default": false},
	"reacts_to_film": {"type": "bool", "default": false},
	"reflection": {"type": "bool", "default": false},
	"reflection_floor": {"type": "float", "min": -20.0, "max": 20.0, "default": null, "nullable": true},
}
const ACOUSTICS_OPTIONS := {
	"box": {"type": "object", "fields": {"min": {"type": "vec3"}, "max": {"type": "vec3"}}},
	"reflect": {"type": "list", "of": {"type": "float", "min": 0.0, "max": 1.0}, "max": 6, "min_items": 6},
	"rt60": {"type": "float", "min": 0.05, "max": 8.0},
	"wet": {"type": "float", "min": 0.0, "max": 1.0},
	"surround_height": {"type": "float", "min": 0.0, "max": 30.0},
	"array": {"type": "int", "min": 1, "max": 5},
	"array_spacing": {"type": "float", "min": 0.5, "max": 10.0},
	"ring": {"type": "bool"},
	"distance": {"type": "float", "min": 0.5, "max": 30.0},
}
const AUDIO_OPTIONS := {
	"level_db": {"type": "float", "min": -24.0, "max": 6.0, "default": 0.0},
	"pause_rise_db": {"type": "float", "min": 0.0, "max": 6.0, "default": 3.0},
}
const TIMELINE_OPTIONS := {
	"starting_seconds": {"type": "float", "min": 0.0, "max": 60.0, "default": 8.0},
	"credits_minutes": {"type": "float", "min": 0.0, "max": 20.0, "default": 6.0},
}


## A whole document: version 3's checks with these sections.
static func validate(doc: Variant) -> Dictionary:
	return RoomSchema.validate(doc, "new")


## A room document that ships (app/environments/<id>.env.json): {doc, errors}; doc {} when it can't be read.
static func load_file(path: String) -> Dictionary:
	var j := JSON.new()
	if j.parse(FileAccess.get_file_as_string(path)) != OK or not (j.data is Dictionary):
		return {"doc": {}, "errors": [_e("$", "not readable as JSON: %s" % path)]}
	var v := validate(j.data)
	return {"doc": j.data if v["ok"] else {}, "errors": v["errors"]}


## The version 4 sections of `d` into `errors` (room_schema.gd validate() calls this for a document of schema 4).
static func validate_sections(d: Dictionary, errors: Array) -> void:
	if d.has("room"):
		_options(ROOM_OPTIONS, d["room"], "$.room", errors)
	if d.has("acoustics"):
		_options(ACOUSTICS_OPTIONS, d["acoustics"], "$.acoustics", errors)
	if d.has("audio"):
		_options(AUDIO_OPTIONS, d["audio"], "$.audio", errors)
	var settings := _settings(d.get("settings", []), errors) if d.has("settings") else {}
	var ctx := {"settings": settings, "systems": {}}
	_systems(d.get("systems", []), ctx, errors)
	if d.has("timeline"):
		_timeline(d["timeline"], ctx, errors)
	if d.has("cues"):
		_cues(d["cues"], ctx, errors)
	if d.has("credits"):
		_credits(d["credits"], errors)


static func _e(path: String, error: String) -> Dictionary:
	return {"path": path, "error": error}


static func _num(v: Variant) -> bool:
	return (v is float or v is int) and is_finite(float(v))


static func _ident(v: Variant, max_len := 32) -> bool:
	if not (v is String) or str(v).length() == 0 or str(v).length() > max_len:
		return false
	var re := RegEx.create_from_string("^[a-z][a-z0-9_]*$")
	return re.search(str(v)) != null


# --- Options and parameters -----------------------------------------------------------------------------------------

## A dictionary of options against a spec ({name: param spec}): unknown keys and bad values, each with its path.
static func _options(spec: Dictionary, v: Variant, path: String, errors: Array, ctx := {}) -> void:
	if not (v is Dictionary):
		errors.append(_e(path, "an object (known: %s)" % ", ".join(spec.keys())))
		return
	for k: Variant in v:
		if not spec.has(str(k)):
			errors.append(_e("%s.%s" % [path, k], "unknown (known: %s)" % ", ".join(spec.keys())))
		else:
			check_value(spec[str(k)], v[k], "%s.%s" % [path, k], errors, ctx)


## One value against a parameter's spec. A binding ({"bind": ...}) is checked against the parameter (ctx: the room's
## settings, for setting channels; ctx.no_bind: bindings not allowed here).
static func check_value(spec: Dictionary, v: Variant, path: String, errors: Array, ctx := {}) -> void:
	if v is Dictionary and (v as Dictionary).has("bind"):
		if bool(ctx.get("no_bind", false)):
			errors.append(_e(path, "a value here, not a binding"))
			return
		_binding(spec, v, path, errors, ctx)
		return
	if v == null and bool(spec.get("nullable", false)):
		return
	var t := str(spec.get("type", ""))
	match t:
		"float", "int":
			if not _num(v):
				errors.append(_e(path, "a number"))
				return
			if t == "int" and float(v) != floorf(float(v)):
				errors.append(_e(path, "a whole number"))
			if spec.has("min") and float(v) < float(spec["min"]):
				errors.append(_e(path, "at least %s" % spec["min"]))
			if spec.has("max") and float(v) > float(spec["max"]):
				errors.append(_e(path, "at most %s" % spec["max"]))
		"bool":
			if not (v is bool):
				errors.append(_e(path, "true or false"))
		"color":
			if not RoomSchema.is_color(v):
				errors.append(_e(path, "a colour: \"#rrggbb\" or [r, g, b]"))
		"enum":
			if not (v is String) or not (str(v) in spec.get("values", [])):
				errors.append(_e(path, "one of %s" % ", ".join(spec.get("values", []))))
		"vec2", "vec3":
			var n := 2 if t == "vec2" else 3
			if not (v is Array) or (v as Array).size() != n or not (v as Array).all(func(x: Variant) -> bool: return _num(x)):
				errors.append(_e(path, "[%s] numbers" % ("x, y" if n == 2 else "x, y, z")))
				return
			for c: Variant in v:
				if (spec.has("min") and float(c) < float(spec["min"])) or (spec.has("max") and float(c) > float(spec["max"])):
					errors.append(_e(path, "each between %s and %s" % [spec.get("min"), spec.get("max")]))
					break
		"string":
			if not (v is String) or str(v).length() > int(spec.get("max", 64)):
				errors.append(_e(path, "text, at most %d characters" % int(spec.get("max", 64))))
		"list":
			if not (v is Array):
				errors.append(_e(path, "a list"))
				return
			var a: Array = v
			if a.size() > int(spec.get("max", 64)) or a.size() < int(spec.get("min_items", 0)):
				errors.append(_e(path, "%d to %d items" % [int(spec.get("min_items", 0)), int(spec.get("max", 64))]))
			for i in a.size():
				check_value(spec.get("of", {}), a[i], "%s[%d]" % [path, i], errors, {"no_bind": true})
		"material":
			_material(v, path, errors)
		"object":
			_options(spec.get("fields", {}), v, path, errors, {"no_bind": true})
		_:
			errors.append(_e(path, "unknown parameter type %s" % t))


static func _material(v: Variant, path: String, errors: Array) -> void:
	if not (v is Dictionary):
		errors.append(_e(path, "a material: {library, color, tint, tiling}"))
		return
	for k: Variant in v:
		if not (str(k) in MATERIAL_KEYS):
			errors.append(_e("%s.%s" % [path, k], "unknown (known: %s)" % ", ".join(MATERIAL_KEYS)))
	var m: Dictionary = v
	if m.has("library"):
		if not RoomSchema.id_ok(m["library"]):
			errors.append(_e(path + ".library", "a library material's id"))
		elif not MaterialLibrary.has(str(m["library"])):
			errors.append(_e(path + ".library", "no such library material: %s" % m["library"]))
	for k: String in ["color", "tint"]:
		if m.has(k) and not RoomSchema.is_color(m[k]):
			errors.append(_e("%s.%s" % [path, k], "a colour"))
	if m.has("tiling") and (not _num(m["tiling"]) or float(m["tiling"]) < RoomSchema.TILING_MIN
			or float(m["tiling"]) > RoomSchema.TILING_MAX):
		errors.append(_e(path + ".tiling", "metres per repeat, %s..%s" % [RoomSchema.TILING_MIN, RoomSchema.TILING_MAX]))
	for k: String in ["pleats", "pleat_depth", "spill"]:
		if m.has(k) and (not _num(m[k]) or float(m[k]) < 0.0 or float(m[k]) > 10.0):
			errors.append(_e("%s.%s" % [path, k], "a number, 0..10"))


## What a channel gives: "unit", "raw", "color", "name"; "" for one that isn't known. A setting's channel: "unit".
static func channel_kind(channel: String, ctx := {}) -> String:
	if CHANNELS.has(channel):
		return CHANNELS[channel]
	if channel.begins_with(SETTING_PREFIX):
		var n := channel.trim_prefix(SETTING_PREFIX)
		var settings: Dictionary = ctx.get("settings", {})
		if settings.has(n) or _common(n) != {}:
			return "setting"
	return ""


static func _common(setting_name: String) -> Dictionary:
	for s: Dictionary in COMMON_SETTINGS:
		if s["name"] == setting_name:
			return s
	return {}


## A binding against the parameter it drives (docs/environments.md, "Bindings and film signals").
static func _binding(spec: Dictionary, b: Dictionary, path: String, errors: Array, ctx: Dictionary) -> void:
	var known := ["bind", "range", "keys", "map", "smooth", "invert", "strength", "base"]
	for k: Variant in b:
		if not (str(k) in known):
			errors.append(_e("%s.%s" % [path, k], "unknown (known: %s)" % ", ".join(known)))
	var ch := str(b.get("bind", ""))
	var kind := channel_kind(ch, ctx)
	if kind == "":
		errors.append(_e(path + ".bind", "a channel: %s, or setting.<name> of a declared setting"
				% ", ".join(CHANNELS.keys())))
		return
	var t := str(spec.get("type", ""))
	if not bool(spec.get("live", false)) and kind != "setting":
		errors.append(_e(path + ".bind", "this parameter is built once: only a setting may change it"))
	if not (t in ["float", "int", "bool", "color", "enum"]):
		errors.append(_e(path + ".bind", "a %s parameter can't follow a channel" % t))
		return
	var forms := 0
	for k: String in ["range", "keys", "map"]:
		if b.has(k):
			forms += 1
	if forms > 1:
		errors.append(_e(path, "one of range, keys and map"))
	if kind == "name" and not b.has("map"):
		errors.append(_e(path, "%s gives a name: map it ({name: value})" % ch))
	if kind == "color" and t != "color":
		errors.append(_e(path + ".bind", "%s is a colour: it can drive a colour only" % ch))
	if b.has("smooth") and (not _num(b["smooth"]) or float(b["smooth"]) < 0.0 or float(b["smooth"]) > 60.0):
		errors.append(_e(path + ".smooth", "seconds, 0..60"))
	if b.has("invert") and not (b["invert"] is bool):
		errors.append(_e(path + ".invert", "true or false"))
	if b.has("strength") and (not _num(b["strength"]) or float(b["strength"]) < 0.0 or float(b["strength"]) > 1.0):
		errors.append(_e(path + ".strength", "0..1"))
	if b.has("base") and not RoomSchema.is_color(b["base"]):
		errors.append(_e(path + ".base", "a colour"))
	var value_ctx := {"no_bind": true}
	if b.has("range"):
		if not (b["range"] is Array) or (b["range"] as Array).size() != 2:
			errors.append(_e(path + ".range", "[from, to]"))
		else:
			for i in 2:
				check_value(spec, b["range"][i], "%s.range[%d]" % [path, i], errors, value_ctx)
	if b.has("keys"):
		var ks: Variant = b["keys"]
		if not (ks is Array) or (ks as Array).size() < 2 or (ks as Array).size() > int(LIMITS["keys"]):
			errors.append(_e(path + ".keys", "2 to %d points [x, y]" % LIMITS["keys"]))
		else:
			var last := -INF
			for i in (ks as Array).size():
				var p: Variant = ks[i]
				if not (p is Array) or (p as Array).size() != 2 or not _num(p[0]):
					errors.append(_e("%s.keys[%d]" % [path, i], "[x, y]"))
					continue
				if float(p[0]) <= last:
					errors.append(_e("%s.keys[%d]" % [path, i], "x rising"))
				last = float(p[0])
				check_value(spec, p[1], "%s.keys[%d][1]" % [path, i], errors, value_ctx)
	if b.has("map"):
		if not (b["map"] is Dictionary) or (b["map"] as Dictionary).is_empty():
			errors.append(_e(path + ".map", "{value: result}"))
		else:
			for k: Variant in b["map"]:
				check_value(spec, b["map"][k], "%s.map.%s" % [path, k], errors, value_ctx)
				if kind == "name" and not (str(k) in STATES):
					errors.append(_e("%s.map.%s" % [path, k], "a state: %s" % ", ".join(STATES)))


## A system's parameters with the defaults filled in (a binding stays a binding; the host resolves it).
static func with_defaults(params_spec: Dictionary, given: Variant) -> Dictionary:
	var out := {}
	for k: String in params_spec:
		out[k] = params_spec[k].get("default")
	if given is Dictionary:
		for k: Variant in given:
			out[str(k)] = given[k]
	return out


static func is_binding(v: Variant) -> bool:
	return v is Dictionary and (v as Dictionary).has("bind")


# --- Systems -----------------------------------------------------------------------------------------------------------

static func _systems(v: Variant, ctx: Dictionary, errors: Array) -> void:
	if not (v is Array):
		errors.append(_e("$.systems", "a list of {system, id, params}"))
		return
	var list: Array = v
	if list.size() > int(LIMITS["systems"]):
		errors.append(_e("$.systems", "at most %d systems" % LIMITS["systems"]))
	var seen_kinds := {}
	var systems: Dictionary = ctx["systems"]
	for i in list.size():
		var path := "$.systems[%d]" % i
		if not (list[i] is Dictionary):
			errors.append(_e(path, "{system, id, params}"))
			continue
		var s: Dictionary = list[i]
		for k: Variant in s:
			if not (str(k) in ["system", "id", "params"]):
				errors.append(_e("%s.%s" % [path, k], "unknown (known: system, id, params)"))
		var name := str(s.get("system", ""))
		if not Registry.has(name):
			errors.append(_e(path + ".system", "unknown system %s (known: %s)" % [name, ", ".join(Registry.names())]))
			continue
		var spec := Registry.spec(name)
		var sid := str(s.get("id", name))
		if not _ident(sid):
			errors.append(_e(path + ".id", "lower-case letters, digits and _, at most 32"))
		elif systems.has(sid):
			errors.append(_e(path + ".id", "%s is used twice: give one its own id" % sid))
		for r: String in spec.get("requires", []):
			if not seen_kinds.has(r):
				errors.append(_e(path, "%s needs a %s system before it" % [name, r]))
		seen_kinds[name] = true
		seen_kinds[str(spec.get("kind", ""))] = true
		systems[sid] = spec
		if s.has("params"):
			_options(spec.get("params", {}), s["params"], path + ".params", errors, ctx)


## "<id>.<param>" -> [system spec, param spec] or [] (with the error added).
static func _target(t: Variant, path: String, ctx: Dictionary, errors: Array, live := true) -> Array:
	var bits := str(t).split(".")
	var systems: Dictionary = ctx.get("systems", {})
	if not (t is String) or bits.size() != 2 or not systems.has(bits[0]):
		errors.append(_e(path, "\"<system id>.<parameter>\" of a system in this room (%s)" % ", ".join(systems.keys())))
		return []
	var ps: Dictionary = systems[bits[0]].get("params", {})
	if not ps.has(bits[1]):
		errors.append(_e(path, "%s has no parameter %s (it has: %s)" % [bits[0], bits[1], ", ".join(ps.keys())]))
		return []
	if live and not bool(ps[bits[1]].get("live", false)):
		errors.append(_e(path, "%s is built once, not live: a cue or a track can't move it" % t))
		return []
	return [systems[bits[0]], ps[bits[1]]]


# --- Settings ---------------------------------------------------------------------------------------------------------

## The room's own setting declarations: {name: declaration} of the good ones; errors for the rest.
static func _settings(v: Variant, errors: Array) -> Dictionary:
	var out := {}
	if not (v is Array):
		errors.append(_e("$.settings", "a list of {name, type, default, label, description, ...}"))
		return out
	var list: Array = v
	if list.size() > int(LIMITS["settings"]):
		errors.append(_e("$.settings", "at most %d settings" % LIMITS["settings"]))
	for i in list.size():
		var path := "$.settings[%d]" % i
		var before := errors.size()
		var s: Variant = list[i]
		if not (s is Dictionary):
			errors.append(_e(path, "{name, type, default, label, description}"))
			continue
		check_setting(s, path, errors)
		var n := str((s as Dictionary).get("name", ""))
		if out.has(n):
			errors.append(_e(path + ".name", "%s is declared twice" % n))
		if errors.size() == before:
			out[n] = s
	return out


## One declaration (docs/environments.md, "A room's own settings").
static func check_setting(s: Dictionary, path: String, errors: Array) -> void:
	var known := ["name", "type", "default", "label", "description", "min", "max", "step", "format", "choices",
			"labels"]
	for k: Variant in s:
		if not (str(k) in known):
			errors.append(_e("%s.%s" % [path, k], "unknown (known: %s)" % ", ".join(known)))
	if not _ident(s.get("name"), int(LIMITS["name"])):
		errors.append(_e(path + ".name", "lower-case letters, digits and _, at most %d" % LIMITS["name"]))
	elif _common(str(s["name"])) != {}:
		errors.append(_e(path + ".name", "%s is a common setting every room has" % s["name"]))
	for k: String in ["label", "description"]:
		var max_len := int(LIMITS[k])
		if not (s.get(k) is String) or str(s[k]).strip_edges() == "" or str(s[k]).length() > max_len:
			errors.append(_e("%s.%s" % [path, k], "English text, 1 to %d characters (a translation key)" % max_len))
	var t := str(s.get("type", ""))
	var d: Variant = s.get("default")
	match t:
		"bool":
			if not (d is bool):
				errors.append(_e(path + ".default", "true or false"))
		"range":
			if not _num(s.get("min")) or not _num(s.get("max")) or float(s["min"]) >= float(s["max"]):
				errors.append(_e(path, "min below max"))
			elif not _num(d) or float(d) < float(s["min"]) or float(d) > float(s["max"]):
				errors.append(_e(path + ".default", "between min and max"))
			if s.has("step") and (not _num(s["step"]) or float(s["step"]) <= 0.0):
				errors.append(_e(path + ".step", "above 0"))
			if s.has("format") and not (str(s["format"]) in FORMATS):
				errors.append(_e(path + ".format", "one of %s" % ", ".join(FORMATS)))
		"choice":
			var cs: Variant = s.get("choices")
			var ls: Variant = s.get("labels")
			if not (cs is Array) or (cs as Array).size() < 2 or (cs as Array).size() > int(LIMITS["choices"]) \
					or not (cs as Array).all(func(c: Variant) -> bool: return _ident(c)):
				errors.append(_e(path + ".choices", "2 to %d ids" % LIMITS["choices"]))
			elif not _labels_ok(ls, (cs as Array).size()):
				errors.append(_e(path + ".labels", "a label per choice (English, translation keys)"))
			elif not (d in cs):
				errors.append(_e(path + ".default", "one of the choices"))
		_:
			errors.append(_e(path + ".type", "one of %s" % ", ".join(SETTING_TYPES)))


static func _labels_ok(ls: Variant, n: int) -> bool:
	if not (ls is Array) or (ls as Array).size() != n:
		return false
	for l: Variant in ls:
		if not (l is String) or str(l).length() == 0 or str(l).length() > int(LIMITS["label"]):
			return false
	return true


static func settings_of(doc: Dictionary) -> Array:
	return doc.get("settings", []) if doc.get("settings") is Array else []


## A setting's value checked against its declaration: the value, clamped or snapped, or null when it can't be one.
static func coerce_setting(decl: Dictionary, v: Variant) -> Variant:
	match str(decl.get("type", "")):
		"bool":
			return v if v is bool else null
		"range":
			if not _num(v):
				return null
			return clampf(float(v), float(decl["min"]), float(decl["max"]))
		"choice":
			return v if v is String and v in decl.get("choices", []) else null
	return null


## A setting's value as a channel (0..1): a range over its own range, a bool 0 or 1, a choice by its index.
static func setting_unit(decl: Dictionary, v: Variant) -> float:
	match str(decl.get("type", "")):
		"bool":
			return 1.0 if bool(v) else 0.0
		"range":
			var lo := float(decl["min"])
			var hi := float(decl["max"])
			return clampf((float(v) - lo) / (hi - lo), 0.0, 1.0) if hi > lo else 0.0
		"choice":
			var cs: Array = decl.get("choices", [])
			return float(cs.find(v)) / maxf(cs.size() - 1, 1) if cs.size() > 0 else 0.0
	return 0.0


# --- Timeline and cues ------------------------------------------------------------------------------------------------

static func _timeline(v: Variant, ctx: Dictionary, errors: Array) -> void:
	if not (v is Dictionary):
		errors.append(_e("$.timeline", "{starting_seconds, credits_minutes, tracks}"))
		return
	for k: Variant in v:
		if str(k) == "tracks":
			continue
		if not TIMELINE_OPTIONS.has(str(k)):
			errors.append(_e("$.timeline.%s" % k, "unknown (known: starting_seconds, credits_minutes, tracks)"))
		else:
			check_value(TIMELINE_OPTIONS[str(k)], v[k], "$.timeline.%s" % k, errors, {"no_bind": true})
	if not (v as Dictionary).has("tracks"):
		return
	var tracks: Variant = v["tracks"]
	if not (tracks is Array) or (tracks as Array).size() > int(LIMITS["tracks"]):
		errors.append(_e("$.timeline.tracks", "a list of at most %d {target, by, keys}" % LIMITS["tracks"]))
		return
	for i in (tracks as Array).size():
		var path := "$.timeline.tracks[%d]" % i
		var t: Variant = tracks[i]
		if not (t is Dictionary):
			errors.append(_e(path, "{target, by, keys}"))
			continue
		for k: Variant in t:
			if not (str(k) in ["target", "by", "keys", "smooth"]):
				errors.append(_e("%s.%s" % [path, k], "unknown (known: target, by, keys, smooth)"))
		if not (str(t.get("by", "")) in ["film.minutes", "film.progress"]):
			errors.append(_e(path + ".by", "film.minutes or film.progress"))
		var tg := _target(t.get("target"), path + ".target", ctx, errors)
		if tg.is_empty():
			continue
		var b := {"bind": str(t.get("by", "film.progress")), "keys": t.get("keys")}
		if t.has("smooth"):
			b["smooth"] = t["smooth"]
		_binding(tg[1], b, path, errors, ctx)


static func _cues(v: Variant, ctx: Dictionary, errors: Array) -> void:
	if not (v is Array):
		errors.append(_e("$.cues", "a list of {name, when, steps, ...}"))
		return
	var list: Array = v
	if list.size() > int(LIMITS["cues"]):
		errors.append(_e("$.cues", "at most %d cues" % LIMITS["cues"]))
	var names := {}
	for i in list.size():
		var path := "$.cues[%d]" % i
		if not (list[i] is Dictionary):
			errors.append(_e(path, "{name, when, steps}"))
			continue
		var c: Dictionary = list[i]
		var known := ["name", "when", "requires", "states", "chance", "cooldown", "steps"]
		for k: Variant in c:
			if not (str(k) in known):
				errors.append(_e("%s.%s" % [path, k], "unknown (known: %s)" % ", ".join(known)))
		if not (c.get("name") is String) or str(c["name"]).length() == 0 or str(c["name"]).length() > 40:
			errors.append(_e(path + ".name", "a name, at most 40 characters"))
		elif names.has(c["name"]):
			errors.append(_e(path + ".name", "%s is used twice" % c["name"]))
		else:
			names[c["name"]] = true
		_when(c.get("when"), path + ".when", ctx, errors)
		if c.has("requires"):
			_requires(c["requires"], path + ".requires", ctx, errors)
		if c.has("states"):
			if not (c["states"] is Array) or not (c["states"] as Array).all(func(s: Variant) -> bool: return s in STATES):
				errors.append(_e(path + ".states", "a list of states: %s" % ", ".join(STATES)))
		if c.has("chance") and (not _num(c["chance"]) or float(c["chance"]) < 0.0 or float(c["chance"]) > 1.0):
			errors.append(_e(path + ".chance", "0..1"))
		if c.has("cooldown") and (not _num(c["cooldown"]) or float(c["cooldown"]) < 0.0
				or float(c["cooldown"]) > float(LIMITS["cooldown"])):
			errors.append(_e(path + ".cooldown", "seconds, 0..%d" % int(LIMITS["cooldown"])))
		var steps: Variant = c.get("steps")
		if not (steps is Array) or (steps as Array).is_empty() or (steps as Array).size() > int(LIMITS["steps"]):
			errors.append(_e(path + ".steps", "1 to %d steps" % LIMITS["steps"]))
			continue
		for j in (steps as Array).size():
			_step(steps[j], "%s.steps[%d]" % [path, j], ctx, errors)


static func _when(w: Variant, path: String, ctx: Dictionary, errors: Array) -> void:
	if not (w is Dictionary):
		errors.append(_e(path, "{state}, {signal, above or below, for} or {every}"))
		return
	var d: Dictionary = w
	if d.has("state"):
		var s: Variant = d["state"]
		var ok: bool = (s is String and s in STATES) or (s is Array and not (s as Array).is_empty()
				and (s as Array).all(func(x: Variant) -> bool: return x in STATES))
		if not ok:
			errors.append(_e(path + ".state", "a state or a list of states: %s" % ", ".join(STATES)))
		for k: Variant in d:
			if str(k) != "state":
				errors.append(_e("%s.%s" % [path, k], "a state trigger has only state"))
	elif d.has("signal"):
		var kind := channel_kind(str(d["signal"]), ctx)
		if not (kind in ["unit", "raw", "setting"]):
			errors.append(_e(path + ".signal", "a channel with a number: %s" % ", ".join(CHANNELS.keys())))
		if d.has("above") == d.has("below"):
			errors.append(_e(path, "above or below, one of them"))
		for k: String in ["above", "below"]:
			if d.has(k) and not _num(d[k]):
				errors.append(_e("%s.%s" % [path, k], "a number"))
		if d.has("for") and (not _num(d["for"]) or float(d["for"]) < 0.0 or float(d["for"]) > 600.0):
			errors.append(_e(path + ".for", "seconds, 0..600"))
		for k: Variant in d:
			if not (str(k) in ["signal", "above", "below", "for"]):
				errors.append(_e("%s.%s" % [path, k], "unknown (known: signal, above, below, for)"))
	elif d.has("every"):
		if not _num(d["every"]) or float(d["every"]) < 1.0 or float(d["every"]) > float(LIMITS["cooldown"]):
			errors.append(_e(path + ".every", "seconds, 1..%d" % int(LIMITS["cooldown"])))
		for k: Variant in d:
			if str(k) != "every":
				errors.append(_e("%s.%s" % [path, k], "an every trigger has only every"))
	else:
		errors.append(_e(path, "{state}, {signal, above or below, for} or {every}"))


static func _requires(v: Variant, path: String, ctx: Dictionary, errors: Array) -> void:
	if not (v is Array):
		errors.append(_e(path, "a list of {setting, is}"))
		return
	for i in (v as Array).size():
		var r: Variant = v[i]
		var p := "%s[%d]" % [path, i]
		if not (r is Dictionary) or not (r as Dictionary).has("setting"):
			errors.append(_e(p, "{setting, is}"))
			continue
		var n := str(r["setting"])
		var settings: Dictionary = ctx.get("settings", {})
		var decl: Dictionary = settings.get(n, _common(n))
		if decl.is_empty():
			errors.append(_e(p + ".setting", "no setting %s in this room" % n))
		elif r.has("is") and coerce_setting(decl, r["is"]) == null:
			errors.append(_e(p + ".is", "a value of %s" % n))
		for k: Variant in r:
			if not (str(k) in ["setting", "is"]):
				errors.append(_e("%s.%s" % [p, k], "unknown (known: setting, is)"))


static func _step(v: Variant, path: String, ctx: Dictionary, errors: Array) -> void:
	if not (v is Dictionary):
		errors.append(_e(path, "a step: one of %s" % ", ".join(STEP_KINDS)))
		return
	var s: Dictionary = v
	var kinds := STEP_KINDS.filter(func(k: String) -> bool: return s.has(k))
	if kinds.size() != 1:
		errors.append(_e(path, "one of %s" % ", ".join(STEP_KINDS)))
		return
	var kind: String = kinds[0]
	var allowed := {"set": ["set", "to", "seconds", "ease"], "wait": ["wait"], "release": ["release", "seconds", "ease"],
			"do": ["do", "args"], "sound": ["sound", "gain_db", "at"]}
	for k: Variant in s:
		if not (str(k) in allowed[kind]):
			errors.append(_e("%s.%s" % [path, k], "unknown in a %s step (known: %s)" % [kind, ", ".join(allowed[kind])]))
	if s.has("seconds") and (not _num(s["seconds"]) or float(s["seconds"]) < 0.0
			or float(s["seconds"]) > float(LIMITS["seconds"])):
		errors.append(_e(path + ".seconds", "0..%d" % int(LIMITS["seconds"])))
	if s.has("ease") and not (str(s["ease"]) in EASES):
		errors.append(_e(path + ".ease", "one of %s" % ", ".join(EASES)))
	match kind:
		"set":
			var tg := _target(s["set"], path + ".set", ctx, errors)
			if not tg.is_empty():
				if not s.has("to"):
					errors.append(_e(path + ".to", "the value to go to"))
				elif s["to"] is Dictionary and (s["to"] as Dictionary).has("setting"):
					# A setting's value as it is when the step runs: {"setting": "<name>"} (a range).
					var n := str(s["to"]["setting"])
					var decl: Dictionary = (ctx.get("settings", {}) as Dictionary).get(n, _common(n))
					if decl.get("type") != "range" or (s["to"] as Dictionary).size() != 1:
						errors.append(_e(path + ".to", "{\"setting\": <name>} of a range setting of this room"))
				else:
					check_value(tg[1], s["to"], path + ".to", errors, {"no_bind": true})
		"release":
			_target(s["release"], path + ".release", ctx, errors)
		"wait":
			if not _num(s["wait"]) or float(s["wait"]) < 0.0 or float(s["wait"]) > float(LIMITS["seconds"]):
				errors.append(_e(path + ".wait", "seconds, 0..%d" % int(LIMITS["seconds"])))
		"do":
			var bits := str(s["do"]).split(".")
			var systems: Dictionary = ctx.get("systems", {})
			if bits.size() != 2 or not systems.has(bits[0]):
				errors.append(_e(path + ".do", "\"<system id>.<action>\" of a system in this room"))
			elif not (systems[bits[0]].get("actions", {}) as Dictionary).has(bits[1]):
				errors.append(_e(path + ".do", "%s has no action %s (it has: %s)" % [bits[0], bits[1],
						", ".join((systems[bits[0]].get("actions", {}) as Dictionary).keys())]))
			if s.has("args") and not (s["args"] is Dictionary):
				errors.append(_e(path + ".args", "an object"))
		"sound":
			if not (str(s["sound"]) in SOUNDS):
				errors.append(_e(path + ".sound", "one of %s (synthesised)" % ", ".join(SOUNDS)))
			if s.has("gain_db") and (not _num(s["gain_db"]) or float(s["gain_db"]) < -60.0 or float(s["gain_db"]) > 0.0):
				errors.append(_e(path + ".gain_db", "-60..0"))
			if s.has("at"):
				check_value({"type": "vec3", "min": -200.0, "max": 200.0}, s["at"], path + ".at", errors, {"no_bind": true})


static func _credits(v: Variant, errors: Array) -> void:
	if not (v is Array) or (v as Array).size() > int(LIMITS["credits"]):
		errors.append(_e("$.credits", "a list of at most %d {asset, title, source, licence}" % LIMITS["credits"]))
		return
	for i in (v as Array).size():
		var c: Variant = v[i]
		var path := "$.credits[%d]" % i
		if not (c is Dictionary):
			errors.append(_e(path, "{asset, title, source, licence}"))
			continue
		for k: String in ["asset", "title", "source", "licence"]:
			if not ((c as Dictionary).get(k) is String) or str(c[k]).strip_edges() == "":
				errors.append(_e("%s.%s" % [path, k], "text"))
		if not str((c as Dictionary).get("licence", "")).begins_with("CC0"):
			errors.append(_e(path + ".licence", "CC0 only: a room bundles nothing else"))
