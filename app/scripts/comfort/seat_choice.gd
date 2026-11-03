extends Node

## Seat choice (ideas #19): sit somewhere else in the room: the front row, the back, the end of the sofa. An
## environment that has seats lists them (get_seats(): the floor point under the viewer, in the room's own
## coordinates); choosing one moves the room so that seat comes to you (the tracking origin goes to the seat; the eye
## height stays the viewer's own, seated or standing), and puts the screen where the room's screen anchor now is from
## there (distance, height, direction). Remembered per environment.
## An assistant's room (scripts/assistant/assistant_room.gd) may also name its seats (get_seat_names), face them
## (get_seat_yaws: the room turns so the seat's facing is ahead), start the viewer at one (get_default_seat; only when
## the viewer opens the room, never when an assistant changes it) and have its own screen (has_home_screen: its width
## and curve too; Reset room and home_screen() put it back there).
##
##   seats() -> Array[Vector3]       this room's seats ([] if it has none)
##   names() -> Array[String]        their names ("Seat 1", ... when the room gives none)
##   seat                            the chosen index, -1 for the room's own spot
##   choose_seat(index)              at once; -1 goes back to the room's own spot
##   go_to_seat(index)               the same behind a short fade to black and back (FADE_OUT + FADE_IN): never a
##                                   slide (the Room tab, seat picking, an assistant's suggestion the viewer took)
##   choose_seat_at(world_point, faded := false)   the seat nearest a point (within NEAR metres); false if none
##   next_seat(step)                 the next / previous seat in the list (faded)
##   home_screen()                   the room's own screen from the seat in use
##   screen_at_home() -> bool        the screen is still where the room last put it (the viewer hasn't moved it)
##   moved, moved_name               an assistant's change moved (or removed, or renamed) the seat the viewer is in:
##                                   the viewer stays exactly where they were (the room keeps its place round them);
##                                   seat is the seat by that name (-1: gone), and choosing it goes to its new place
##   signal changed(seat)
## Settings: [seats] <environment id> = index, [seat_names] <environment id> = name (named seats).

signal changed(seat: int)

const NEAR := 1.5
const FADE_OUT := 0.18
const FADE_IN := 0.25

var main: Node3D
var seat := -1
var moved := false
var moved_name := ""
## Where the room was last put round the viewer: {env_id, xf, name}.
var _placed := {}
## Where the screen was last put by the room (seat changes, home_screen): {env_id, yaw, distance, height, width}.
var _screen_home := {}
var _fade: MeshInstance3D
var _fading := false


func _ready() -> void:
	main.environment_changed.connect(func(_id: String, _l: float) -> void: _restore())
	_restore()


func seats() -> Array[Vector3]:
	var out: Array[Vector3] = []
	var env: Node = main.env
	if env != null and env.has_method("get_seats"):
		for p: Vector3 in env.get_seats():
			out.append(p)
	return out


func names() -> Array[String]:
	var out: Array[String] = []
	var env: Node = main.env
	var given: Array = env.get_seat_names() if env != null and env.has_method("get_seat_names") else []
	var n := seats().size()
	for i in n:
		out.append(str(given[i]) if i < given.size() else "Seat %d" % (i + 1))
	return out


func _named() -> bool:
	var env: Node = main.env
	return env != null and env.has_method("get_seat_names") and not env.get_seat_names().is_empty()


func _restore() -> void:
	seat = -1
	moved = false
	moved_name = ""
	var env: Node = main.env
	# A room's own screen keeps its own facing while it is at home; any other room's faces the viewer.
	var at_home := screen_at_home()
	main.screen_turn = NAN
	var prev: Dictionary = _placed if _placed.get("env_id") == main.env_id else {}
	var i := int(main.settings.get_value("seats", main.env_id, -1))
	if _named():
		i = names().find(str(main.settings.get_value("seat_names", main.env_id, "")))
		if i < 0 and env.has_method("get_default_seat") and not env.has_meta("assistant_apply") \
				and not main.settings.has_value("seat_names", main.env_id):
			i = int(env.get_default_seat())
	if env != null and env.has_meta("assistant_apply") and not prev.is_empty():
		# An assistant's change rebuilt the room. If it moved, removed or renamed the viewer's seat, the viewer stays
		# exactly where they were: the room keeps its place round them, and the seat is marked moved.
		var have := i >= 0 and i < seats().size()
		var want := seat_transform(i).affine_inverse() if have else Transform3D()
		var was: Transform3D = prev["xf"]
		if not want.is_equal_approx(was):
			(env as Node3D).transform = was
			seat = i if have else -1
			moved = true
			moved_name = str(prev.get("name", ""))
			_placed = {"env_id": main.env_id, "xf": was, "name": moved_name}
			_keep_turn(at_home)
			changed.emit(seat)
			return
	if i >= 0 and i < seats().size():
		# An assistant's change rebuilt the room: the viewer keeps their seat and the screen where they had it.
		var applied: bool = env != null and env.has_meta("assistant_apply")
		choose_seat(i, not applied)
		if applied:
			_keep_turn(at_home)
	elif env != null:
		(env as Node3D).transform = Transform3D()
		_placed = {"env_id": main.env_id, "xf": Transform3D(), "name": ""}
		_keep_turn(at_home)


## After a rebuild that left the screen where it was: a room's own screen still at home faces its own way again.
func _keep_turn(at_home: bool) -> void:
	if at_home and _owns_screen():
		main.screen_turn = _home_turn()
		main.set_screen(main.screen_width, main.screen_distance, main.screen_height_offset)


func _owns_screen() -> bool:
	var env: Node = main.env
	return env != null and env.has_method("has_home_screen") and env.has_home_screen()


## The yaw of the room's screen's picture normal in the world (main.screen_turn).
func _home_turn() -> float:
	var env: Node3D = main.env
	var f: Vector3 = env.transform.basis * env.get_screen_anchor().basis.z
	return atan2(f.x, f.z)


func choose_seat(index: int, place_screen := true) -> void:
	var list := seats()
	var env: Node3D = main.env
	if env == null:
		return
	if index < 0 or index >= list.size():
		seat = -1
		env.transform = Transform3D()
	else:
		seat = index
		env.transform = seat_transform(index).affine_inverse()
	moved = false
	moved_name = ""
	_placed = {"env_id": main.env_id, "xf": env.transform, "name": names()[seat] if seat >= 0 else ""}
	if place_screen:
		_place_screen(main.screen_width)
	main.settings.set_value("seats", main.env_id, seat if seat >= 0 else null)
	if _named():
		main.settings.set_value("seat_names", main.env_id, names()[seat] if seat >= 0 else "")
	changed.emit(seat)


## Seat `index` in the room frame: at its floor point, turned to its facing (none: the room's way round).
func seat_transform(index: int) -> Transform3D:
	var env: Node = main.env
	var list := seats()
	if index < 0 or index >= list.size():
		return Transform3D()
	var yaws: Array = env.get_seat_yaws() if env.has_method("get_seat_yaws") else []
	var yaw: float = float(yaws[index]) if index < yaws.size() and not is_nan(float(yaws[index])) else 0.0
	return Transform3D(Basis(Vector3.UP, yaw), list[index])


## The screen at the room's anchor as seen from where the room now is (width: as given).
func _place_screen(width: float) -> void:
	var env: Node3D = main.env
	var a: Vector3 = env.transform * env.get_screen_anchor().origin
	main.screen_turn = _home_turn() if _owns_screen() else NAN
	if seat < 0 and is_zero_approx(env.transform.basis.get_euler().y) and env.transform.origin.is_zero_approx() \
			and not _owns_screen():
		var d: Dictionary = env.get_default_screen()
		main.screen_yaw = 0.0
		main.set_screen(width, d["distance"], d["height_offset"])
	else:
		main.screen_yaw = atan2(a.x, -a.z)
		main.set_screen(width, Vector2(a.x, a.z).length(), a.y - env.NOMINAL_EYE_HEIGHT)
	_screen_home = {"env_id": main.env_id, "yaw": main.screen_yaw, "distance": main.screen_distance,
			"height": main.screen_height_offset, "width": main.screen_width}


func screen_at_home() -> bool:
	if _screen_home.get("env_id") != main.env_id:
		return true
	return absf(angle_difference(float(_screen_home["yaw"]), float(main.screen_yaw))) < 0.01 \
			and absf(float(_screen_home["distance"]) - float(main.screen_distance)) < 0.01 \
			and absf(float(_screen_home["height"]) - float(main.screen_height_offset)) < 0.01 \
			and absf(float(_screen_home["width"]) - float(main.screen_width)) < 0.01


## The room's own screen (its width, curve and place) from the seat in use. Rooms without one: the anchor and the
## width the viewer has.
func home_screen() -> void:
	var env: Node3D = main.env
	if env == null:
		return
	var own: bool = env.has_method("has_home_screen") and env.has_home_screen()
	main.screen.sphere_yaw = 0.0
	_place_screen(float(env.default_screen_width) if own else main.screen_width)
	if own and main.get("features") != null and main.features.curve != null:
		main.features.curve.set_amount(float(env.get_home_curve()))


## choose_seat behind a short fade: out to black, the move, back in.
func go_to_seat(index: int) -> void:
	if _fading:
		return
	if not bool(main.get("use_xr")) or not is_inside_tree():
		choose_seat(index)
		return
	_fading = true
	_ensure_fade()
	_fade.visible = true
	var mat := _fade.material_override as StandardMaterial3D
	var t := create_tween()
	t.tween_method(func(a: float) -> void: mat.albedo_color.a = a, 0.0, 1.0, FADE_OUT)
	t.tween_callback(func() -> void: choose_seat(index))
	t.tween_method(func(a: float) -> void: mat.albedo_color.a = a, 1.0, 0.0, FADE_IN)
	t.tween_callback(func() -> void:
		_fade.visible = false
		_fading = false)


## A black quad just in front of the eyes, over everything, for the fade.
func _ensure_fade() -> void:
	if _fade != null and is_instance_valid(_fade):
		return
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.no_depth_test = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.render_priority = BaseMaterial3D.RENDER_PRIORITY_MAX
	mat.albedo_color = Color(0, 0, 0, 0)
	_fade = MeshInstance3D.new()
	_fade.name = "SeatFade"
	var q := QuadMesh.new()
	q.size = Vector2(4.0, 4.0)
	_fade.mesh = q
	_fade.material_override = mat
	_fade.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_fade.position = Vector3(0, 0, -0.15)
	_fade.visible = false
	(main.camera as Node3D).add_child(_fade)


func choose_seat_at(world_point: Vector3, faded := false) -> bool:
	var list := seats()
	var env: Node3D = main.env
	var best := -1
	var best_d := NEAR
	for i in list.size():
		var d := (env.global_transform * list[i]).distance_to(world_point)
		if d < best_d:
			best_d = d
			best = i
	if best < 0:
		return false
	if faded:
		go_to_seat(best)
	else:
		choose_seat(best)
	return true


func next_seat(step := 1) -> void:
	var n := seats().size()
	if n == 0:
		return
	go_to_seat(posmod(seat + step, n) if seat >= 0 else (0 if step > 0 else n - 1))
