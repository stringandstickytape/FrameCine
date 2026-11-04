extends Node

## Rooms light themselves on the headset (scripts/env/room_bake.gd): when a room that is built for a lightmap comes
## on (it has static_meshes() and bake_lights(), as environments/cinema.gd), its kept bake is loaded; without one
## (the first time, or after the room changed) the room is baked there and then, behind a notice, and kept under
## user://lightmaps/<id>/ for every later start. No PC step: a room's light is made where the room is shown.
## A bake blocks the main thread for its length (about three seconds for the cinema on the Frame, 2026-11-04), so
## the notice is drawn first and the bake starts two frames later.
##   enabled      [env] lightmaps, true: off, rooms keep their shader lighting (the stand-in lamps and fill)
##   bake_now()   bake the room on show again (a changed room, or to see it fresh); returns room_bake's result
##   last         the last prepare / load / bake, for the tests: {id, loaded, baked, result}

const RoomBake := preload("res://scripts/env/room_bake.gd")

var main: Node3D
var enabled := true
var last := {}
var _busy := false


func _ready() -> void:
	enabled = bool(main.settings.get_value("env", "lightmaps", true))
	main.environment_changed.connect(_on_environment_changed)
	if main.env != null:
		_on_environment_changed(str(main.env_id), 0.0)


func set_enabled(on: bool) -> void:
	enabled = on
	main.settings.set_value("env", "lightmaps", null if on else false)
	if on and main.env != null:
		_on_environment_changed(str(main.env_id), 0.0)


## Whether the room on show is built for a lightmap.
func room_bakeable() -> bool:
	var room: Node = main.env
	return room != null and room.has_method("static_meshes") and room.has_method("bake_lights")


## Bakes the room on show again, now, and keeps the result; {} when there is nothing to bake.
func bake_now() -> Dictionary:
	if not room_bakeable() or not RoomBake.can_bake():
		return {}
	RoomBake.clear(str(main.env_id))
	await _light(str(main.env_id), main.env)
	return last.get("result", {})


func _on_environment_changed(id: String, _light_level: float) -> void:
	if not enabled or _busy or not room_bakeable() or not RoomBake.can_bake():
		return
	_light(id, main.env)


## Loads the kept bake, else bakes: the notice first, the bake two frames later, so the notice is on screen while
## the main thread is held.
func _light(id: String, room: Node3D) -> void:
	_busy = true
	last = {"id": id, "loaded": false, "baked": false, "result": {}}
	RoomBake.prepare(room, id)
	if RoomBake.load(room, id):
		last["loaded"] = true
		_busy = false
		return
	var ui: Node = main.get("ui")
	if ui != null and ui.has_method("notify"):
		ui.notify("Lighting the %s for the first time: a few seconds." % _room_name(id))
	await get_tree().process_frame
	await get_tree().process_frame
	if not is_instance_valid(room) or main.env != room:
		_busy = false
		return
	if room.has_method("set_baking"):
		room.set_baking(true)
	var r: Dictionary = RoomBake.bake(room, id)
	if room.has_method("set_baking"):
		room.set_baking(false)
	last["baked"] = bool(r.get("ok", false))
	last["result"] = r
	if not bool(r.get("ok", false)):
		print("Room lightmaps: %s not baked: %s" % [id, r.get("error", "")])
	_busy = false


func _room_name(id: String) -> String:
	for e: Array in main.all_environments():
		if str(e[0]) == id:
			return str(e[1]).to_lower()
	return "room"
