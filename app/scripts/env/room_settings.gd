extends Node

## Every room's own settings (docs/environments.md, "Room settings"): the common ones from the shared systems
## (env_doc.gd COMMON_SETTINGS: dim during the film, the room's sound, ambient life, the pre-show, flickering lights,
## motion) and the room's own, declared in its version 4 document. The Room tab's "This room" section is built from
## declarations(); the assistant reads and sets them (room_settings' this_room, room_setting).
##
##   declarations() -> Array        [{name, type, default, label, description, min/max/step/format or choices/labels,
##                                    common}] for the room on show: the common ones that have an effect here, then
##                                    the room's own
##   value(name), values()          what each is now (the default unless changed)
##   set_value(name, v) -> String   "" or why not; applied at once, kept as [room:<id>] <name> when it is not the
##                                  default (back to the default erases the key)
##   reset()                        every setting of the room back to its default, and the room's own seat
##   schema() -> Array              the declarations as JSON Schemas (the assistant)
##   format(decl, v) -> String      a value as the menu shows it (translated)
##   signal changed

signal changed

const EnvDoc := preload("res://scripts/env/env_doc.gd")
const SECTION_PREFIX := "room:"

var main: Node3D
var _values := {}
var _env_id := ""
## The declarations by name, for the room they were read for.
var _cache := {}
var _cache_for: Node = null


func _ready() -> void:
	main.environment_changed.connect(func(_id: String, _l: float) -> void: _load())
	_load()


static func section(env_id: String) -> String:
	return SECTION_PREFIX + env_id


## The room's own and the common declarations that apply, in the menu's order.
func declarations() -> Array:
	var out: Array = []
	for d: Dictionary in EnvDoc.COMMON_SETTINGS:
		if _applies(str(d["applies"])):
			var c := d.duplicate()
			c["common"] = true
			out.append(c)
	if main.env != null and main.env.has_method("declared_settings"):
		for d: Dictionary in main.env.declared_settings():
			var c := d.duplicate()
			c["common"] = false
			out.append(c)
	return out


func _applies(applies: String) -> bool:
	var env: Node = main.env
	if env != null and env.has_method("common_applies"):
		return bool(env.common_applies(applies))
	match applies:
		"always":
			return true
		"ritual":
			var preshow: Node = main.features.get("preshow")
			return preshow != null and env != null and (main.env_id in preshow.CURTAIN_ROOMS
					or env.get("has_curtains") == true)
	return false


func _decl(n: String) -> Dictionary:
	if _cache.is_empty() or _cache_for != main.env:
		_cache_for = main.env
		_cache.clear()
		for d: Dictionary in declarations():
			_cache[d["name"]] = d
	if _cache.has(n):
		return _cache[n]
	for d: Dictionary in EnvDoc.COMMON_SETTINGS:
		if d["name"] == n:
			return d
	return {}


func value(n: String) -> Variant:
	if _values.has(n):
		return _values[n]
	return _decl(n).get("default")


func values() -> Dictionary:
	var out := {}
	for d: Dictionary in declarations():
		out[d["name"]] = value(str(d["name"]))
	return out


func _stores() -> bool:
	return _env_id != "" and not _env_id.begins_with("assistant:")


func _load() -> void:
	_env_id = str(main.env_id)
	_values.clear()
	_cache.clear()
	if _stores():
		for k: String in main.settings.get_keys(section(_env_id)):
			var d := _decl(k)
			if d.is_empty():
				continue
			var v: Variant = EnvDoc.coerce_setting(d, main.settings.get_value(section(_env_id), k, null))
			if v != null:
				_values[k] = v
	_push()
	changed.emit()


func set_value(n: String, v: Variant) -> String:
	var d := _decl(n)
	if d.is_empty():
		return "this room has no setting %s (it has: %s)" % [n, ", ".join(declarations().map(
				func(x: Dictionary) -> String: return str(x["name"])))]
	if v is int and str(d["type"]) == "range":
		v = float(v)
	var c: Variant = EnvDoc.coerce_setting(d, v)
	if c == null:
		return "%s: %s" % [n, _expects(d)]
	if str(d["type"]) == "range" and d.has("step"):
		c = clampf(snappedf(float(c), float(d["step"])), float(d["min"]), float(d["max"]))
	var is_default: bool = c == d["default"] or (c is float and is_equal_approx(float(c), float(d["default"])))
	if is_default:
		_values.erase(n)
	else:
		_values[n] = c
	if _stores():
		main.settings.set_value(section(_env_id), n, null if is_default else c)
	_push()
	changed.emit()
	return ""


static func _expects(d: Dictionary) -> String:
	match str(d["type"]):
		"bool":
			return "true or false"
		"range":
			return "a number from %s to %s" % [d["min"], d["max"]]
		"choice":
			return "one of %s" % ", ".join(d["choices"])
	return "?"


## Every setting of this room back to its default (their keys erased), and the room's own seat.
func reset() -> void:
	_values.clear()
	if _stores():
		for k: String in main.settings.get_keys(section(_env_id)):
			main.settings.set_value(section(_env_id), k, null)
	var seat: Node = main.features.get("seat")
	if seat != null and not (seat.seats() as Array).is_empty():
		var home := int(main.env.get_default_seat()) if main.env != null and main.env.has_method("get_default_seat") \
				else -1
		if int(seat.seat) != home:
			seat.choose_seat(home)
	_push()
	changed.emit()


## The values to the room (its systems' bindings) and to what reads them each frame (light follow, the buses).
func _push() -> void:
	if main.env != null and main.env.has_method("apply_room_settings"):
		var all := {}
		for d: Dictionary in EnvDoc.COMMON_SETTINGS:
			all[d["name"]] = value(str(d["name"]))
		for d: Dictionary in declarations():
			all[d["name"]] = value(str(d["name"]))
		main.env.apply_room_settings(all)


## For the assistant: each declaration with its JSON Schema, value and default.
func schema() -> Array:
	var out: Array = []
	for d: Dictionary in declarations():
		var s := {}
		match str(d["type"]):
			"bool":
				s = {"type": "boolean"}
			"range":
				s = {"type": "number", "minimum": d["min"], "maximum": d["max"]}
				if d.has("step"):
					s["multipleOf"] = d["step"]
			"choice":
				s = {"type": "string", "enum": d["choices"]}
		out.append({"name": d["name"], "type": d["type"], "label": d["label"], "description": d["description"],
				"common": d["common"], "schema": s, "default": d["default"], "value": value(str(d["name"])),
				"choices": d.get("choices", []), "format": d.get("format", "")})
	return out


## A value as the menu shows it, in the menus' language.
static func format(d: Dictionary, v: Variant) -> String:
	var f := float(v) if (v is float or v is int) else 0.0
	if bool(d.get("off_at_min", false)) and f <= float(d.get("min", 0.0)) + 0.001:
		return TranslationServer.translate("off")
	match str(d.get("format", "number")):
		"percent":
			return "%d %%" % roundi(f * 100.0)
		"db":
			return TranslationServer.translate("%+d dB") % roundi(f)
		"seconds":
			return TranslationServer.translate("%.1f s") % f
		"minutes":
			return TranslationServer.translate("%d min") % roundi(f)
		"times":
			return "%.1fx" % f
	return "%.2f" % f
