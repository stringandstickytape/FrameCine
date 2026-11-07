extends "res://environments/vr_environment.gd"

## A room that ships as a version 4 document (docs/environments.md): app/environments/<id>.env.json, built by the
## systems it names (scripts/env/env_host.gd, the child "Systems"). The scene (<id>.tscn) holds only this node and its
## `document`. What the app asks of an environment comes from the systems:
##   get_seats()            the builders' seats; collision_shapes() their boxes (also before the room is built)
##   get_sound_room()       the builders' walls with the document's acoustics
##   static_meshes(), bake_lights(), set_baking(on), set_baked(on), is_baked()   the light system's bake hooks
##   on_screen_changed()    the systems follow the screen (the masking, the beam)
## and from the document's room section: ambient_level, screen_glow, reacts_to_film, has_curtains (the pre-show's
## curtains, while the room's Pre-show setting is on), reflection_floor_y and reflection_default (the floor reflection).
## The room settings feature (scripts/env/room_settings.gd) gives it the room's settings: apply_room_settings().

const EnvDoc := preload("res://scripts/env/env_doc.gd")
const EnvHost := preload("res://scripts/env/env_host.gd")
const Registry := preload("res://scripts/env/systems/registry.gd")
const RoomSchema := preload("res://scripts/assistant/room_schema.gd")

@export_file("*.env.json") var document := ""

var doc := {}
var host: Node
var has_curtains := false
var curtains_by_cue := false
var reflection_floor_y := NAN
var reflection_default := false
var _main: Node
var _screen_world := Transform3D()
var _screen_size := Vector2.ZERO

static var _docs := {}


## A document that ships, read and checked once ({} with a warning when it fails).
static func load_doc(path: String) -> Dictionary:
	if _docs.has(path):
		return _docs[path]
	var r := EnvDoc.load_file(path)
	if not (r["errors"] as Array).is_empty():
		push_warning("Room %s: %s" % [path, r["errors"]])
	_docs[path] = r["doc"]
	return r["doc"]


func _doc() -> Dictionary:
	if doc.is_empty() and document != "":
		doc = load_doc(document)
	return doc


func _ready() -> void:
	set_notify_transform(true)
	_doc()
	_apply_room()
	host = EnvHost.attach(self, doc)
	_sync_curtains()
	_fit_to_screen()
	host.on_room_moved()


## The document's room section and screen onto the environment's properties.
func _apply_room() -> void:
	if doc.has("name"):
		display_name = str(doc["name"])
	var r: Dictionary = doc.get("room", {}) if doc.get("room") is Dictionary else {}
	ambient_level = float(r.get("ambient", ambient_level))
	screen_glow = float(r.get("screen_glow", screen_glow))
	reacts_to_film = bool(r.get("reacts_to_film", reacts_to_film))
	if r.get("reflection_floor") != null and r.has("reflection_floor"):
		reflection_floor_y = float(r["reflection_floor"])
	reflection_default = bool(r.get("reflection", reflection_default))
	if doc.get("screen") is Dictionary:
		var s: Dictionary = doc["screen"]
		if screen_anchor == null:
			screen_anchor = Marker3D.new()
			screen_anchor.name = "ScreenAnchor"
			add_child(screen_anchor)
		var facing := RoomSchema.screen_facing(s)
		screen_anchor.transform = Transform3D(Basis.looking_at(-facing, Vector3.UP), RoomSchema.vec3(s["center"]))
		default_screen_width = float(s["size"][0])


func _sync_curtains() -> void:
	var r: Dictionary = doc.get("room", {}) if doc.get("room") is Dictionary else {}
	var ritual := bool(host.setting("ritual")) if host != null else true
	has_curtains = bool(r.get("curtains", false)) and ritual
	var showing: Node = host.system_of_kind("showing") if host != null else null
	curtains_by_cue = has_curtains and showing != null and showing.has_method("curtains_by_cue") \
			and bool(showing.call("curtains_by_cue"))


# --- Settings ------------------------------------------------------------------------------------------------------

## Whether this room is the base of an assistant's room (scripts/assistant/assistant_room.gd), not shown on its own.
func is_base() -> bool:
	var p := get_parent()
	return p != null and p.get("base_id") != null and p.get("doc") != null


## The room's settings (common and declared) from the room settings feature.
func apply_room_settings(values: Dictionary) -> void:
	if host == null:
		return
	for k: String in values:
		host.set_setting(k, values[k])
	_sync_curtains()


## The room's own declarations.
func declared_settings() -> Array:
	return EnvDoc.settings_of(_doc())


## Which common settings have an effect here (env_doc.gd COMMON_SETTINGS "applies").
func common_applies(applies: String) -> bool:
	match applies:
		"always":
			return true
		"ritual":
			var r: Dictionary = _doc().get("room", {}) if _doc().get("room") is Dictionary else {}
			if bool(r.get("curtains", false)):
				return true
			for c: Dictionary in _doc().get("cues", []):
				for q: Dictionary in c.get("requires", []):
					if q.get("setting") == "ritual":
						return true
			return false
		"life":
			return host != null and not host.systems_of_kind("life").is_empty()
		"flicker", "motion":
			for entry: Dictionary in _doc().get("systems", []):
				var ps: Dictionary = Registry.spec(str(entry["system"])).get("params", {})
				for k: String in ps:
					if (applies == "flicker" and bool(ps[k].get("flicker", false))) \
							or (applies == "motion" and ps[k].has("motion")):
						return true
			return false
	return false


## Light follows playback (scripts/env/light_follow.gd): the room's "Dim during the film".
func dims_during_film() -> bool:
	return host == null or bool(host.setting("dim"))


## The level the room dims to while the film plays, or -1 for the app's own (the light system's dimmed_level).
func dimmed_level() -> float:
	var light: Node = host.system_of_kind("light") if host != null else null
	return float(light.params.get("dimmed_level", -1.0)) if light != null else -1.0


func audio_level_db() -> float:
	var a: Dictionary = _doc().get("audio", {}) if _doc().get("audio") is Dictionary else {}
	return float(a.get("level_db", 0.0))


func pause_rise_db() -> float:
	var a: Dictionary = _doc().get("audio", {}) if _doc().get("audio") is Dictionary else {}
	return float(a.get("pause_rise_db", 3.0))


# --- What the app asks ------------------------------------------------------------------------------------------------

## Seat choice (scripts/comfort/seat_choice.gd): the floor point under a seated viewer's eyes for every seat.
func get_seats() -> Array[Vector3]:
	var out: Array[Vector3] = []
	for t in room_seat_transforms():
		out.append(t.origin)
	return out


func room_seat_transforms() -> Array[Transform3D]:
	if host != null:
		return host.seats()
	var out: Array[Transform3D] = []
	for entry: Dictionary in _doc().get("systems", []):
		var script := Registry.script_of(str(entry["system"]))
		if script != null and script.has_method("layout"):
			var p := EnvDoc.with_defaults(Registry.spec(str(entry["system"]))["params"], entry.get("params", {}))
			out.append_array(script.call("layout", p).seat_transforms())
	return out


func get_sound_room() -> Dictionary:
	return host.sound_room() if host != null else {}


## Object physics (docs/physics.md): the builders' boxes; before the room is built, from its document.
func collision_shapes() -> Array:
	if host != null:
		return host.collision_shapes()
	var out: Array = []
	for entry: Dictionary in _doc().get("systems", []):
		var script := Registry.script_of(str(entry["system"]))
		if script != null and script.has_method("collision_shapes_for"):
			var p := EnvDoc.with_defaults(Registry.spec(str(entry["system"]))["params"], entry.get("params", {}))
			out.append_array(script.call("collision_shapes_for", p))
	return out


func _light() -> Node:
	return host.system_of_kind("light") if host != null else null


func bake_lights() -> Node3D:
	var l := _light()
	return l.bake_lights() if l != null else null


## The meshes a lightmap bake covers (gi_mode static, with UV2).
func static_meshes() -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	for n in get_children():
		if n is MeshInstance3D and (n as MeshInstance3D).gi_mode == GeometryInstance3D.GI_MODE_STATIC:
			out.append(n)
	return out


func set_baking(on: bool) -> void:
	var l := _light()
	if l != null:
		l.set_baking(on)


func set_baked(on: bool) -> void:
	var l := _light()
	if l != null:
		l.set_baked(on)


func is_baked() -> bool:
	var l := _light()
	return l != null and l.is_baked()


# --- Following the screen and the seat ---------------------------------------------------------------------------------

func on_screen_changed(screen_transform: Transform3D, size: Vector2) -> void:
	var main := _find_main()
	_screen_world = (main.global_transform if main != null and main.is_inside_tree() else Transform3D()) \
			* screen_transform
	_screen_size = size
	_fit_to_screen()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSFORM_CHANGED and host != null:
		host.on_room_moved()
		_fit_to_screen()


func _fit_to_screen() -> void:
	if host == null or _screen_size == Vector2.ZERO or not is_inside_tree():
		return
	host.on_screen_changed(global_transform.affine_inverse() * _screen_world, _screen_size)


## The app's main node (scenes/main.tscn), the room's ancestor; null when the room stands alone (tests, tools).
func _find_main() -> Node:
	if _main != null and is_instance_valid(_main):
		return _main
	var n := get_parent()
	while n != null:
		if n.get("player") != null and n.get("screen") != null and n.has_method("set_environment"):
			_main = n
			return n
		n = n.get_parent()
	return null
