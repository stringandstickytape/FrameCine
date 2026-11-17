extends RefCounted

## The visualisers (docs/visualisers.md): each is a folder holding visualiser.json (the manifest) and
## visualiser.gdshader (a canvas_item shader), found in DIRS: the app's own in res://visualisers, then the user's in
## user://visualisers. The folder's name is the id (lower case letters, digits and _). A user folder with the id of
## one of the app's is skipped (its error says so): copy it under a new name instead. "off" is no folder: no visualiser.
## Static; preload to use.
##
##   ids() -> Array[String]            the usable ones, in order (the manifest's "order", then the name)
##   entry(id) -> Dictionary           {id, name, description, area, order, params, presets, shader_path, dir, builtin}
##   errors() -> Dictionary            id -> why its folder is not usable
##   rescan()                          read the folders again (after a change in user://visualisers)
##   load_shader(id) -> Shader         the app's through the resource cache; the user's from their text, fresh
##   values(id) -> Dictionary          every parameter's value now: the default, or overrides[id][name]
##   coerce(spec, value) -> Variant    a value made the parameter's type and clamped to its range (null: unusable)
##   overrides                         id -> {name: value} (main.features keeps these in the settings)
##
## The manifest:
##   {"name": "Bars", "description": "...", "area": "strip", "order": 10,
##    "params": {"bars": {"type": "int", "min": 8, "max": 128, "default": 32, "label": "Bars"},
##               "colour_low": {"type": "colour", "default": "#73b3ff", "label": "Low colour"}},
##    "presets": {"Warm": {"colour_low": "#ff9a40"}}}
## Each parameter is a uniform of the same name in the shader: float and int (min, max, default), bool (default) and
## colour ("#rrggbb", a vec4 uniform). "label" names it for people; the name is used without one.

const DIRS: Array[String] = ["res://visualisers", "user://visualisers"]
const MANIFEST := "visualiser.json"
const SHADER := "visualiser.gdshader"
## Where on the music card it draws (scripts/play/music_source.gd): a strip under the title, a taller area, or the
## whole card behind the words.
const AREAS: Array[String] = ["strip", "tall", "backdrop"]
const TYPES: Array[String] = ["float", "int", "bool", "colour"]
const OFF := "off"

## The folders searched, in order (tests point the second elsewhere).
static var dirs: Array[String] = DIRS.duplicate()
static var overrides := {}
static var _entries := {}
static var _order: Array[String] = []
static var _errors := {}
static var _scanned := false


static func ids() -> Array[String]:
	_scan()
	return _order.duplicate()


static func has(id: String) -> bool:
	_scan()
	return _entries.has(id)


static func entry(id: String) -> Dictionary:
	_scan()
	return _entries.get(id, {})


static func errors() -> Dictionary:
	_scan()
	return _errors.duplicate()


static func rescan() -> void:
	_scanned = false
	_scan()


static func _scan() -> void:
	if _scanned:
		return
	_scanned = true
	_entries.clear()
	_errors.clear()
	var found: Array[Dictionary] = []
	for root in dirs:
		var dir := DirAccess.open(root)
		if dir == null:
			continue
		var builtin := root.begins_with("res://")
		for id in dir.get_directories():
			var folder := root.path_join(id)
			if not FileAccess.file_exists(folder.path_join(MANIFEST)):
				continue
			if not _id_ok(id):
				_errors[id] = "%s: the folder's name must be lower case letters, digits and _" % folder
				continue
			if _entries.has(id):
				_errors[id] = "%s: the app has a visualiser called %s; copy it under a new name" % [folder, id]
				continue
			var e := _read(folder, id, builtin)
			if e.has("error"):
				_errors[id] = e["error"]
				continue
			_entries[id] = e
			found.append(e)
	found.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a["order"] < b["order"] if a["order"] != b["order"] else str(a["name"]) < str(b["name"]))
	_order.clear()
	for e in found:
		_order.append(str(e["id"]))


static func _id_ok(id: String) -> bool:
	if id == "" or id == OFF:
		return false
	for c in id:
		if not (c >= "a" and c <= "z") and not (c >= "0" and c <= "9") and c != "_":
			return false
	return true


## One folder's manifest, checked; {"error": why} when it is not usable.
static func _read(folder: String, id: String, builtin: bool) -> Dictionary:
	var path := folder.path_join(MANIFEST)
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(path)) != OK:
		return {"error": "%s: line %d: %s" % [path, json.get_error_line(), json.get_error_message()]}
	if not json.data is Dictionary:
		return {"error": "%s: not a JSON object" % path}
	var m: Dictionary = json.data
	if not FileAccess.file_exists(folder.path_join(SHADER)):
		return {"error": "%s: no %s" % [folder, SHADER]}
	var area := str(m.get("area", "strip"))
	if not area in AREAS:
		return {"error": "%s: area must be one of %s, not %s" % [path, ", ".join(AREAS), area]}
	var params := {}
	var raw_params: Variant = m.get("params", {})
	if not raw_params is Dictionary:
		return {"error": "%s: params must be an object" % path}
	for pname: String in raw_params:
		var why := _param_error(pname, raw_params[pname])
		if why != "":
			return {"error": "%s: params.%s: %s" % [path, pname, why]}
		params[pname] = _param_spec(pname, raw_params[pname])
	var presets := {}
	var raw_presets: Variant = m.get("presets", {})
	if raw_presets is Dictionary:
		for pre: String in raw_presets:
			if not raw_presets[pre] is Dictionary:
				return {"error": "%s: presets.%s must be an object" % [path, pre]}
			var vals := {}
			for pname: String in raw_presets[pre]:
				if not params.has(pname):
					return {"error": "%s: presets.%s: no parameter %s" % [path, pre, pname]}
				var v: Variant = coerce(params[pname], raw_presets[pre][pname])
				if v == null:
					return {"error": "%s: presets.%s.%s: not a %s" % [path, pre, pname, params[pname]["type"]]}
				vals[pname] = v
			presets[pre] = vals
	return {"id": id, "name": str(m.get("name", id)), "description": str(m.get("description", "")), "area": area,
			"order": int(m.get("order", 100)), "params": params, "presets": presets,
			"shader_path": folder.path_join(SHADER), "dir": folder, "builtin": builtin}


static func _param_error(pname: String, p: Variant) -> String:
	if not _id_ok(pname):
		return "a parameter's name must be lower case letters, digits and _ (it is the shader's uniform)"
	if not p is Dictionary:
		return "must be an object"
	var t := str(p.get("type", ""))
	if not t in TYPES:
		return "type must be one of %s" % ", ".join(TYPES)
	if t == "float" or t == "int":
		for k in ["min", "max", "default"]:
			if not (p.get(k) is float or p.get(k) is int):
				return "%s needs a number" % k
		if float(p["min"]) > float(p["max"]):
			return "min is over max"
	elif t == "bool":
		if not p.get("default") is bool:
			return "default needs true or false"
	elif t == "colour":
		if not (p.get("default") is String and Color.html_is_valid(p["default"])):
			return "default needs a colour such as \"#73b3ff\""
	return ""


static func _param_spec(pname: String, p: Dictionary) -> Dictionary:
	var spec := {"name": pname, "type": str(p["type"]), "label": str(p.get("label", pname))}
	if spec["type"] == "float" or spec["type"] == "int":
		spec["min"] = float(p["min"])
		spec["max"] = float(p["max"])
	spec["default"] = coerce(spec, p["default"])
	return spec


## A value as the parameter's type, clamped to its range; null when it cannot be one.
static func coerce(spec: Dictionary, v: Variant) -> Variant:
	match str(spec["type"]):
		"float":
			if v is float or v is int:
				return clampf(float(v), float(spec.get("min", -INF)), float(spec.get("max", INF)))
		"int":
			if v is float or v is int:
				return clampi(roundi(float(v)), int(spec.get("min", -2147483648)), int(spec.get("max", 2147483647)))
		"bool":
			if v is bool:
				return v
		"colour":
			if v is Color:
				return v
			if v is String and Color.html_is_valid(v):
				return Color.html(v)
	return null


static func values(id: String) -> Dictionary:
	var e := entry(id)
	var out := {}
	var o: Dictionary = overrides.get(id, {})
	for pname: String in e.get("params", {}):
		out[pname] = o.get(pname, e["params"][pname]["default"])
	return out


static func load_shader(id: String) -> Shader:
	var e := entry(id)
	if e.is_empty():
		return null
	var path: String = e["shader_path"]
	if bool(e["builtin"]):
		return load(path) as Shader
	var s := Shader.new()
	s.code = FileAccess.get_file_as_string(path)
	return s
