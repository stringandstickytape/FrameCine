extends Node

## The host of a room's systems (docs/environments.md): the child "Systems" of a room built from a version 4
## document (env_room.gd, or an assistant's room). It builds the systems the document names, from the registry, with
## their parameters; keeps the film signals fresh; runs the bindings (a parameter that follows a channel or a
## setting), the timeline and its cues, and the room's settings; and asks the systems for the room's seats, physics,
## sound and bake hooks.
##
##   EnvHost.attach(room, doc) -> host      builds it under the room (doc already validated)
##   system(id), system_of_kind(kind)       a system, or null
##   step(delta)                            one frame (auto: from _process; tests set auto false and call it)
##   set_setting(name, value), setting(name)   the room's settings as the room settings feature gives them
##   channel(name) -> Variant               a channel's value now (film signals, settings)
##   fade(target, to, seconds, ease), release(target, seconds, ease), do_action(target, args), play_sound(...)
##   param(target) -> Variant               "<id>.<param>" as it is now
##   rebuild()                              the systems again (a setting bound to a parameter that is built once)
##   signal rebuilt                         after rebuild() (the room may move its screen: env_room.gd)

## After rebuild(): the systems are new (a builder may now put the screen elsewhere).
signal rebuilt

const Registry := preload("res://scripts/env/systems/registry.gd")
const EnvDoc := preload("res://scripts/env/env_doc.gd")
const EnvSignals := preload("res://scripts/env/env_signals.gd")
const EnvTimeline := preload("res://scripts/env/env_timeline.gd")
const RoomSchema := preload("res://scripts/assistant/room_schema.gd")
const NODE := "Systems"

var room: Node3D
var doc := {}
var systems := {}
var order: Array = []
var signals: EnvSignals
var timeline: EnvTimeline
var rng := RandomNumberGenerator.new()
var auto := true
## The room's settings: {name: value} (common and declared), and the declarations of the room's own.
var settings := {}
var declared := {}
## Live bindings: {sys, param, spec, b, value}
var _bindings: Array = []
## Cue fades: "<id>.<param>" -> {from, to, t, seconds, ease, release}
var _fades := {}
## Parameters a cue holds: "<id>.<param>" -> true
var _held := {}
## The film ended (the player's signal) and no file has opened since.
var _ended := false
var _main: Node
var _screen_local := Transform3D()
var _screen_size := Vector2.ZERO
## Played sounds (tests): [[sound, gain_db, at]]
var sounds: Array = []


static func attach(p_room: Node3D, p_doc: Dictionary) -> Node:
	var h: Node = (load("res://scripts/env/env_host.gd") as GDScript).new()
	h.name = NODE
	p_room.add_child(h)
	h.build(p_room, p_doc)
	return h


func build(p_room: Node3D, p_doc: Dictionary) -> void:
	room = p_room
	doc = p_doc
	rng.seed = hash(str(doc.get("name", "")))
	for d: Dictionary in EnvDoc.COMMON_SETTINGS:
		settings[d["name"]] = d["default"]
	for d: Dictionary in EnvDoc.settings_of(doc):
		declared[d["name"]] = d
		settings[d["name"]] = d["default"]
	signals = EnvSignals.new()
	timeline = EnvTimeline.new()
	timeline.setup(self, doc)
	timeline.state_changed.connect(_on_state)
	_build_systems()


func _build_systems() -> void:
	for entry: Dictionary in doc.get("systems", []):
		var name := str(entry["system"])
		var script := Registry.script_of(name)
		if script == null:
			continue
		var spec := Registry.spec(name)
		var s: Node = script.new()
		var sid := str(entry.get("id", name))
		s.name = sid
		s.set("host", self)
		s.set("room", room)
		s.set("id", sid)
		var p := EnvDoc.with_defaults(spec.get("params", {}), entry.get("params", {}))
		for k: String in p.keys():
			if EnvDoc.is_binding(p[k]):
				var b := {"sys": s, "param": k, "spec": spec["params"][k], "b": p[k], "value": null}
				p[k] = _evaluate(b, 0.0)
				b["value"] = p[k]
				_bindings.append(b)
			p[k] = _comfort(spec["params"][k], p[k])
		s.set("params", p)
		add_child(s)
		systems[sid] = s
		order.append(s)
	# Film-time tracks: bindings by film.minutes or film.progress.
	var t: Dictionary = doc.get("timeline", {}) if doc.get("timeline") is Dictionary else {}
	for tr: Dictionary in t.get("tracks", []):
		var bits := str(tr["target"]).split(".")
		var s: Node = systems.get(bits[0])
		if s == null:
			continue
		var b := {"bind": str(tr["by"]), "keys": tr["keys"]}
		if tr.has("smooth"):
			b["smooth"] = tr["smooth"]
		var spec: Dictionary = Registry.spec(_system_name(bits[0]))["params"][bits[1]]
		var e := {"sys": s, "param": bits[1], "spec": spec, "b": b, "value": null}
		e["value"] = _evaluate(e, 0.0)
		s.params[bits[1]] = e["value"]
		_bindings.append(e)
	for s: Node in order:
		s.call("setup")


func _system_name(sid: String) -> String:
	for entry: Dictionary in doc.get("systems", []):
		if str(entry.get("id", entry["system"])) == sid:
			return str(entry["system"])
	return sid


## The systems again: their nodes out, built anew with the settings as they are (the screen placed again).
func rebuild() -> void:
	for s: Node in order:
		s.call("clear_owned")
		remove_child(s)
		s.free()
	systems.clear()
	order.clear()
	_bindings.clear()
	_fades.clear()
	_held.clear()
	_build_systems()
	if _screen_size != Vector2.ZERO:
		on_screen_changed(_screen_local, _screen_size)
	on_room_moved()
	rebuilt.emit()


func system(sid: String) -> Node:
	return systems.get(sid)


func system_of_kind(kind: String) -> Node:
	for s: Node in order:
		if str(s.get_script().call("spec").get("kind", "")) == kind:
			return s
	return null


func systems_of_kind(kind: String) -> Array:
	return order.filter(func(s: Node) -> bool: return str(s.get_script().call("spec").get("kind", "")) == kind)


func main_node() -> Node:
	if _main != null and is_instance_valid(_main):
		return _main
	var n := room.get_parent() if room != null else null
	while n != null:
		if n.get("player") != null and n.get("screen") != null and n.has_method("set_environment"):
			_main = n
			return n
		n = n.get_parent()
	return null


# --- Each frame -----------------------------------------------------------------------------------------------------

func _ready() -> void:
	var m := main_node()
	if m != null:
		m.player.ended.connect(_on_ended)
		m.file_opened.connect(_on_file_opened)


func _on_ended() -> void:
	_ended = true


func _on_file_opened(_path: String) -> void:
	_ended = false


func _process(delta: float) -> void:
	if auto:
		step(delta)


func step(delta: float) -> void:
	var m := main_node()
	timeline.observe(_snapshot(m), delta)
	signals.values["playback.state"] = timeline.state
	signals.values["comfort.motion"] = float(settings.get("motion", 1.0))
	signals.update(m, delta, _wanted())
	_step_fades(delta)
	for b: Dictionary in _bindings:
		var key := "%s.%s" % [b["sys"].id, b["param"]]
		if _held.has(key):
			continue
		var v: Variant = _evaluate(b, delta)
		if not _same(v, b["value"]):
			b["value"] = v
			b["sys"].set_param(b["param"], _comfort(b["spec"], v))
	for s: Node in order:
		s.call("tick", delta)


## Tests: the timeline's input, else the player's.
var snapshot_override: Variant = null


func _snapshot(m: Node) -> Dictionary:
	if snapshot_override is Dictionary:
		return snapshot_override
	if m == null:
		return {"open": false}
	var p: Node = m.player
	var inter: Node = m.features.get("intermission") if m.get("features") != null else null
	return {"open": p.has_source(), "playing": p.is_playing(), "position": p.get_position(),
			"duration": p.get_duration(), "intermission": inter != null and bool(inter.active), "ended": _ended}


func _wanted() -> Dictionary:
	var out := {}
	for b: Dictionary in _bindings:
		out[str(b["b"]["bind"])] = true
	for c: String in timeline.channels():
		out[c] = true
	return out


func _on_state(s: String, prev: String) -> void:
	for sys: Node in order:
		sys.call("on_state", s, prev)


# --- Bindings -------------------------------------------------------------------------------------------------------

func channel(ch: String) -> Variant:
	if ch.begins_with(EnvDoc.SETTING_PREFIX):
		var n := ch.trim_prefix(EnvDoc.SETTING_PREFIX)
		return EnvDoc.setting_unit(_decl(n), settings.get(n))
	return signals.value(ch)


func _decl(n: String) -> Dictionary:
	if declared.has(n):
		return declared[n]
	return EnvDoc._common(n)


## A binding's result now: the channel through invert, range, keys or map, then smoothed.
func _evaluate(b: Dictionary, delta: float) -> Variant:
	var bd: Dictionary = b["b"]
	var spec: Dictionary = b["spec"]
	var ch := str(bd["bind"])
	var t := str(spec.get("type", "float"))
	var raw: Variant
	var setting_name := ch.trim_prefix(EnvDoc.SETTING_PREFIX) if ch.begins_with(EnvDoc.SETTING_PREFIX) else ""
	if setting_name != "":
		raw = settings.get(setting_name)
	else:
		raw = signals.value(ch)
	var out: Variant
	if bd.has("map"):
		var key := str(raw).to_lower() if raw is bool else str(raw)
		var m: Dictionary = bd["map"]
		out = m.get(key, b["value"] if b["value"] != null else spec.get("default"))
	elif raw is Color:
		var base := RoomSchema.to_color(bd.get("base", spec.get("default")))
		out = base.lerp(raw, float(bd.get("strength", 1.0)))
	else:
		var x: float
		if setting_name != "":
			x = EnvDoc.setting_unit(_decl(setting_name), raw) if (bd.has("range") or bd.has("invert")) \
					else float(raw) if (raw is float or raw is int) else (1.0 if bool(raw) else 0.0)
		else:
			x = float(raw)
		if bool(bd.get("invert", false)):
			x = 1.0 - clampf(x, 0.0, 1.0)
		if bd.has("keys"):
			out = _keys(bd["keys"], x, t)
		elif bd.has("range"):
			var r: Array = bd["range"]
			if t == "color":
				out = RoomSchema.to_color(r[0]).lerp(RoomSchema.to_color(r[1]), clampf(x, 0.0, 1.0))
			else:
				out = lerpf(float(r[0]), float(r[1]), clampf(x, 0.0, 1.0))
		elif t == "bool":
			out = x > 0.5
		elif t == "color":
			out = RoomSchema.to_color(spec.get("default"))
		else:
			out = x
	out = _typed(out, spec)
	var smooth := float(bd.get("smooth", 0.0))
	if smooth > 0.0 and delta > 0.0 and b["value"] != null:
		var k := 1.0 - exp(-delta / smooth)
		if out is float and b["value"] is float:
			out = lerpf(float(b["value"]), out, k)
		elif out is Color and b["value"] is Color:
			out = (b["value"] as Color).lerp(out, k)
	return out


static func _keys(keys: Array, x: float, t: String) -> Variant:
	if x <= float(keys[0][0]):
		return keys[0][1]
	for i in range(1, keys.size()):
		if x <= float(keys[i][0]):
			var a: Array = keys[i - 1]
			var c: Array = keys[i]
			var f := (x - float(a[0])) / maxf(float(c[0]) - float(a[0]), 1e-9)
			if t == "color":
				return RoomSchema.to_color(a[1]).lerp(RoomSchema.to_color(c[1]), f)
			return lerpf(float(a[1]), float(c[1]), f)
	return keys[-1][1]


## A value in its parameter's type: ints rounded, floats clamped to the range, colours as Color.
static func _typed(v: Variant, spec: Dictionary) -> Variant:
	match str(spec.get("type", "")):
		"float":
			var f := float(v)
			if spec.has("min"):
				f = maxf(f, float(spec["min"]))
			if spec.has("max"):
				f = minf(f, float(spec["max"]))
			return f
		"int":
			return clampi(roundi(float(v)), int(spec.get("min", -1000000000)), int(spec.get("max", 1000000000)))
		"color":
			return v if v is Color else RoomSchema.to_color(v)
		"bool":
			return bool(v)
	return v


static func _same(a: Variant, b: Variant) -> bool:
	if a is float and b is float:
		return is_equal_approx(a, b)
	if a is Color and b is Color:
		return (a as Color).is_equal_approx(b)
	return typeof(a) == typeof(b) and a == b


## Comfort: a motion parameter scaled by the room's Motion setting; a flickering one steady with Flickering lights off.
func _comfort(spec: Dictionary, v: Variant) -> Variant:
	if spec.has("motion") and (v is float or v is int):
		return float(v) * clampf(float(settings.get("motion", 1.0)), 0.0, 1.0)
	if bool(spec.get("flicker", false)) and not bool(settings.get("flicker", true)):
		return spec.get("steady", 0.0)
	return v


# --- Cues' steps ------------------------------------------------------------------------------------------------------

func param(target: String) -> Variant:
	var bits := target.split(".")
	var s: Node = systems.get(bits[0])
	return s.params.get(bits[1]) if s != null else null


func _param_spec(target: String) -> Dictionary:
	var bits := target.split(".")
	if not systems.has(bits[0]):
		return {}
	return Registry.spec(_system_name(bits[0])).get("params", {}).get(bits[1], {})


func fade(target: String, to: Variant, seconds: float, ease := "in_out") -> void:
	if not systems.has(target.split(".")[0]):
		return
	_held[target] = true
	if to is Dictionary and (to as Dictionary).has("setting"):
		# Held at a setting's value: a change to the setting moves it again (set_setting).
		_held[target] = str(to["setting"])
		to = settings.get(str(to["setting"]), 0.0)
	var spec := _param_spec(target)
	_fades[target] = {"from": param(target), "to": _typed(to, spec), "t": 0.0, "seconds": seconds, "ease": ease,
			"release": false}
	if seconds <= 0.0:
		_step_fades(0.0)


## Back to the document's value (or its binding) over `seconds`; the cue lets go of it.
func release(target: String, seconds: float, ease := "in_out") -> void:
	var bits := target.split(".")
	if not systems.has(bits[0]):
		return
	var base: Variant = _base(target)
	_fades[target] = {"from": param(target), "to": base, "t": 0.0, "seconds": seconds, "ease": ease, "release": true}
	if seconds <= 0.0:
		_step_fades(0.0)


func _base(target: String) -> Variant:
	var bits := target.split(".")
	for b: Dictionary in _bindings:
		if b["sys"].id == bits[0] and b["param"] == bits[1]:
			return b["value"]
	for entry: Dictionary in doc.get("systems", []):
		if str(entry.get("id", entry["system"])) == bits[0]:
			var given: Dictionary = entry.get("params", {})
			if given.has(bits[1]) and not EnvDoc.is_binding(given[bits[1]]):
				return _typed(given[bits[1]], _param_spec(target))
	return _typed(_param_spec(target).get("default"), _param_spec(target))


static func eased(f: float, ease: String) -> float:
	f = clampf(f, 0.0, 1.0)
	match ease:
		"in":
			return f * f
		"out":
			return 1.0 - (1.0 - f) * (1.0 - f)
		"in_out":
			return f * f * (3.0 - 2.0 * f)
	return f


func _step_fades(delta: float) -> void:
	for target: String in _fades.keys():
		var f: Dictionary = _fades[target]
		f["t"] = float(f["t"]) + delta
		var k := eased(float(f["t"]) / float(f["seconds"]) if float(f["seconds"]) > 0.0 else 1.0, str(f["ease"]))
		var v: Variant
		if f["from"] is Color or f["to"] is Color:
			v = RoomSchema.to_color(f["from"]).lerp(RoomSchema.to_color(f["to"]), k) if not (f["from"] is Color) \
					else (f["from"] as Color).lerp(f["to"] if f["to"] is Color else RoomSchema.to_color(f["to"]), k)
		elif (f["from"] is float or f["from"] is int) and (f["to"] is float or f["to"] is int):
			v = lerpf(float(f["from"]), float(f["to"]), k)
		else:
			v = f["to"] if k >= 1.0 else f["from"]
		var bits := target.split(".")
		var s: Node = systems.get(bits[0])
		if s != null:
			var spec := _param_spec(target)
			s.set_param(bits[1], _comfort(spec, _typed(v, spec)))
		if float(f["t"]) >= float(f["seconds"]):
			_fades.erase(target)
			if bool(f["release"]):
				_held.erase(target)


func do_action(target: String, args: Variant) -> void:
	var bits := target.split(".")
	var s: Node = systems.get(bits[0])
	if s != null:
		s.act(bits[1], args if args is Dictionary else {})


func play_sound(sound: String, gain_db: float, at: Variant) -> void:
	sounds.append([sound, gain_db, at])
	var m := main_node()
	var audio: Node = m.features.get("env_audio") if m != null and m.get("features") != null else null
	if audio != null:
		var pos: Variant = RoomSchema.vec3(at) if at is Array else null
		audio.play(sound, gain_db, pos)


# --- Settings ---------------------------------------------------------------------------------------------------------

func setting(n: String) -> Variant:
	return settings.get(n)


## A setting changed: its bindings follow (a parameter built once makes the room build again).
func set_setting(n: String, v: Variant) -> void:
	if settings.get(n) == v:
		return
	settings[n] = v
	var rebuild_needed := false
	var ch := EnvDoc.SETTING_PREFIX + n
	for entry: Dictionary in doc.get("systems", []):
		var spec := Registry.spec(str(entry["system"]))
		for k: Variant in entry.get("params", {}):
			var given: Variant = entry["params"][k]
			if EnvDoc.is_binding(given) and str(given["bind"]) == ch \
					and not bool(spec.get("params", {}).get(str(k), {}).get("live", false)):
				rebuild_needed = true
	if n in ["motion", "flicker"]:
		_refresh_comfort()
	if n == "life":
		for s: Node in systems_of_kind("life"):
			if s.has_method("set_active"):
				s.call("set_active", bool(v))
	if rebuild_needed:
		# A parameter built once: the systems again, the binding taking the setting's value as they build.
		rebuild()
		return
	for target: String in _held.keys():
		if _held[target] is String and _held[target] == n and not _fades.has(target):
			fade(target, {"setting": n}, 0.5)
	for b: Dictionary in _bindings:
		if str(b["b"]["bind"]) == ch:
			var nv: Variant = _evaluate(b, 0.0)
			b["value"] = nv
			b["sys"].set_param(b["param"], _comfort(b["spec"], nv))


## Motion and flicker parameters again with the room's comfort settings.
func _refresh_comfort() -> void:
	for s: Node in order:
		var spec: Dictionary = s.get_script().call("spec").get("params", {})
		for k: String in spec:
			if spec[k].has("motion") or bool(spec[k].get("flicker", false)):
				var base: Variant = _base("%s.%s" % [s.id, k])
				s.set_param(k, _comfort(spec[k], base))


# --- The room's hooks -------------------------------------------------------------------------------------------------

func seats() -> Array[Transform3D]:
	var out: Array[Transform3D] = []
	for s: Node in order:
		if s.has_method("seats"):
			out.append_array(s.call("seats"))
	return out


func collision_shapes() -> Array:
	var out: Array = []
	for s: Node in order:
		if s.has_method("collision_shapes"):
			out.append_array(s.call("collision_shapes"))
	return out


## The walls from the builders, the document's acoustics over them.
func sound_room() -> Dictionary:
	var out := {}
	for s: Node in order:
		if s.has_method("sound_room"):
			out.merge(s.call("sound_room"), true)
	var a: Dictionary = doc.get("acoustics", {}) if doc.get("acoustics") is Dictionary else {}
	for k: String in a:
		if k == "box":
			var lo := RoomSchema.vec3(a["box"]["min"])
			var hi := RoomSchema.vec3(a["box"]["max"])
			out["box"] = AABB(lo, hi - lo)
		elif k == "reflect":
			out["reflect"] = (a["reflect"] as Array).map(func(x: Variant) -> float: return float(x))
		else:
			out[k] = a[k]
	return out


func on_screen_changed(local: Transform3D, size: Vector2) -> void:
	_screen_local = local
	_screen_size = size
	for s: Node in order:
		s.call("on_screen_changed", local, size)


func on_room_moved() -> void:
	for s: Node in order:
		if s.has_method("on_room_moved"):
			s.call("on_room_moved")


func _exit_tree() -> void:
	if signals != null:
		signals.release(main_node())
