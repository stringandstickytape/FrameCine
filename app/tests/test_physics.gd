extends SceneTree

## Object physics (docs/physics.md; scripts/play/object_physics.gd, object_grab.gd, physics_shapes.gd, thud.gd) in the
## real main scene, in a kept room on the cinema: a box dropped on a seat comes to rest on it; a ball thrown at the
## screen bounces back off it (not off the wall behind); a 20 m/s throw at a seat back doesn't pass through; a settled
## object is static and its place is in the kept room on disk; Put back and Tidy up return objects; a wall clock stays
## on its wall until pulled off; an attached text follows its object; the thud fires, louder for a faster impact; the
## grip picks an object up on the laser and a flick throws it; the legends; an imported object's hulls are kept and
## made again when missing; and the physics frame's cost with 24 bodies moving.
## godot --headless --xr-mode off --path app --script res://tests/test_physics.gd

const DevCommands := preload("res://scripts/dev/dev_commands.gd")
const CommandHost := preload("res://scripts/dev/command_host.gd")
const ObjectLibrary := preload("res://scripts/assistant/object_library.gd")
const AssistantRoom := preload("res://scripts/assistant/assistant_room.gd")
const RoomSchema := preload("res://scripts/assistant/room_schema.gd")
const PhysicsShapes := preload("res://scripts/play/physics_shapes.gd")
const Thud := preload("res://scripts/play/thud.gd")
const ObjectGrab := preload("res://scripts/play/object_grab.gd")
const Cinema := preload("res://environments/cinema.gd")
const ObjectPhysics := preload("res://scripts/play/object_physics.gd")

const ROOM := "Test physics"
const COST_ROOM := "Test physics cost"

var _failures := 0
var _checks := 0
var main: Node3D
var ph: Node
var _objects_before: Array = []


func _init() -> void:
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate() as Node3D
	main.settings.read_only = true
	root.add_child(main)
	current_scene = main
	_run.call_deferred()


func _run() -> void:
	await _frames(5)
	CommandHost.ensure(self)
	await _frames(2)
	_objects_before = ObjectLibrary.list("", "user").map(func(m: Dictionary) -> String: return m["id"])
	_cleanup()
	ObjectLibrary.editor_for(self).set("perf_after_change", false)
	ph = main.features.physics
	_check("Jolt is the physics engine (%s)" % ProjectSettings.get_setting("physics/3d/physics_engine"),
			str(ProjectSettings.get_setting("physics/3d/physics_engine")) == "Jolt Physics")
	_test_shapes()
	await _test_room()
	await _test_drop_on_seat()
	await _test_saved()
	await _test_screen()
	await _test_fast_throw()
	await _test_put_back()
	await _test_wall()
	await _test_attach()
	await _test_thud()
	await _test_grip()
	_test_labels()
	await _test_hulls_kept()
	await _test_cost()
	_cleanup()
	main.queue_free()
	await _frames(2)
	print("test_physics: %d checks, %s" % [_checks, "all passed" if _failures == 0 else "%d FAILED" % _failures])
	quit(_failures)


# --- Shapes -----------------------------------------------------------------------------------------------------

func _test_shapes() -> void:
	var s := PhysicsShapes.placement_shapes("box", {"size": [0.4, 0.2, 0.3]}, Basis())
	_check("a box is a box shape of its size", s.size() == 1 and s[0][0] is BoxShape3D
			and (s[0][0] as BoxShape3D).size.is_equal_approx(Vector3(0.4, 0.2, 0.3)))
	s = PhysicsShapes.placement_shapes("sphere", {"size": [0.5]}, Basis().scaled(Vector3.ONE * 2.0))
	_check("a sphere is a sphere, its scale in its radius", s[0][0] is SphereShape3D
			and is_equal_approx((s[0][0] as SphereShape3D).radius, 0.5))
	s = PhysicsShapes.placement_shapes("sphere", {"size": [0.5]}, Basis.from_scale(Vector3(1, 2, 1)))
	_check("an ellipsoid is a hull", s[0][0] is ConvexPolygonShape3D)
	s = PhysicsShapes.placement_shapes("cylinder", {"size": [0.3, 0.6]}, Basis())
	_check("a cylinder is a cylinder", s[0][0] is CylinderShape3D and is_equal_approx((s[0][0] as CylinderShape3D).height,
			0.6))
	var plant := ObjectLibrary.collision("pot_plant")
	_check("the pot plant: a hull a part, few points (%s)" % [plant.map(func(h: PackedVector3Array) -> int:
			return h.size())], plant.size() == 3 and plant.all(func(h: PackedVector3Array) -> bool:
			return h.size() >= 4 and h.size() <= PhysicsShapes.HULL_POINTS * 2))
	var frame := ObjectLibrary.collision("picture_frame")
	_check("the picture frame's flat picture has a volume", frame.size() == 3)
	var c := Cinema.new()
	var shapes: Array = c.collision_shapes()
	c.free()
	var seats := Cinema.seat_transforms().size()
	_check("the cinema: boxes, two a seat (%d shapes, %d seats)" % [shapes.size(), seats],
			shapes.size() > seats * 2 and shapes.size() < seats * 2 + 400
			and shapes.all(func(x: Array) -> bool: return x[0] is BoxShape3D))
	var sp := PhysicsShapes.split(Basis.from_euler(Vector3(0.3, 1.0, 0.2)).scaled(Vector3.ONE * 1.5))
	_check("split: a rotation and the scale", (sp[0] as Basis).is_equal_approx((sp[0] as Basis).orthonormalized())
			and PhysicsShapes.is_diagonal(sp[1]) and is_equal_approx((sp[1] as Basis).x.x, 1.5))


# --- The room -----------------------------------------------------------------------------------------------------

## The cinema with objects: a crate over the seat in front, a ball and a pellet, a clock on the left wall, a text,
## a pot plant.
func _test_room() -> void:
	main.set_environment("cinema")
	await _frames(3)
	var doc := {"schema": 3, "name": ROOM, "base": "cinema", "parts": [
		{"name": "Crate", "object": "box", "scale": [0.2, 0.2, 0.2], "position": [0.0, 0.8, -1.45]},
		{"name": "Crate two", "object": "box", "scale": [0.25, 0.25, 0.25], "position": [1.2, 0.8, -1.45]},
		{"name": "Ball", "object": "sphere", "scale": 0.25, "position": [0.0, 1.4, -2.2]},
		{"name": "Pellet", "object": "sphere", "scale": 0.06, "position": [0.0, 0.45, -0.45]},
		{"name": "Clock", "object": "wall_clock", "position": [-9.598, 2.5, -3.0], "rotation": [0, 90, 0]},
		{"name": "Plant", "object": "pot_plant", "position": [2.0, 1.2, -1.0]},
		{"name": "Label", "object": "text", "text": "Crate two", "position": [0, 2, -2]}]}
	var r: Dictionary = await ObjectLibrary.editor_for(self).apply("new", doc, "test")
	_check("the room (%s)" % r.get("error", r.get("errors", "")), r.get("ok") == true)
	await _frames(3)
	_check("its solid objects can be picked up, the text can't (%s)" % [ph.names()], ph.available()
			and ph.names().size() == 6 and not ("Label" in ph.names()))
	_check("placed objects are static; the room's shapes wait", not ph.is_moving("Crate")
			and not bool(ph.state()["room_built"]))
	_check("the clock is on its wall", ph.is_mounted("Clock") and not ph.is_mounted("Crate"))


## Dropped over the seat in front: it falls, bounces and rests on the cushion.
func _test_drop_on_seat() -> void:
	var r := await DevCommands.execute("object_throw", {"name": "Crate"}, false)
	_check("object_throw drops it (%s)" % r.get("error", ""), r["ok"] and ph.is_moving("Crate"))
	_check("the room's shapes are built now (%d)" % ph.state()["room_shapes"], int(ph.state()["room_shapes"]) > 500)
	var thuds := int(ph.thud.count)
	await _until_still("Crate", 8.0)
	var p := _pos("Crate")
	# The seat in front: row 1, its middle seat; the cushion box's top.
	var seat: Transform3D = Cinema.seat_transforms()[(1 + Cinema.ROWS_BACK) * Cinema.SEATS_PER_ROW + Cinema.SEATS_PER_ROW / 2]
	var top := seat.origin.y + Cinema.SEAT_BOX_CENTRE.y + Cinema.SEAT_BOX_SIZE.y * 0.5
	_check("it rests on the seat's cushion (y %.3f, the cushion's top %.3f + 0.1)" % [p.y, top], not ph.is_moving("Crate")
			and absf(p.y - (top + 0.1)) < 0.04 and absf(p.x) < 0.3 and absf(p.z - (seat.origin.z - 0.05)) < 0.35)
	_check("it thudded (%d)" % (ph.thud.count - thuds), ph.thud.count > thuds)


## At rest: static, its place in the document with where it was placed as its home, and on disk.
func _test_saved() -> void:
	var part := _part("Crate")
	var p := _pos("Crate")
	_check("its place is in the room document (%s)" % [part.get("position")], part.has("home")
			and RoomSchema.vec3(part["position"]).distance_to(p) < 0.01
			and RoomSchema.vec3(part["home"]["position"]).is_equal_approx(Vector3(0.0, 0.8, -1.45)))
	ph.save_now()
	var j := JSON.new()
	j.parse(FileAccess.get_file_as_string(AssistantRoom.json_path(ROOM)))
	var saved := {}
	for q: Dictionary in (j.data as Dictionary).get("parts", []) if j.data is Dictionary else []:
		if q["name"] == "Crate":
			saved = q
	_check("and in the kept room on disk (%s)" % [saved.get("position")], saved.has("home")
			and RoomSchema.vec3(saved.get("position", [0, 0, 0])).distance_to(p) < 0.01)
	_check("the kept room validates", RoomSchema.validate(j.data, "saved")["ok"])


## Thrown at the screen: it bounces back off the picture, in front of the wall behind it.
func _test_screen() -> void:
	main.open_path("stub://flat_mono")
	await _frames(10)
	_check("the screen shows", main.screen.is_shown())
	var screen_xf: Transform3D = main.screen.get_node("Flat").global_transform
	var to_room: Transform3D = main.env.global_transform.affine_inverse()
	var target: Vector3 = to_room * screen_xf.origin
	var start := Vector3(0.0, 1.4, -2.2)
	var d := Vector2(target.x - start.x, target.z - start.z).length()
	var speed := 14.0
	var t := d / speed
	var flat := Vector3(target.x - start.x, 0.0, target.z - start.z).normalized() * speed
	var v := Vector3(flat.x, (target.y - start.y + 0.5 * 9.8 * t * t) / t, flat.z)
	# The film layer (forced, no XR session): the runtime draws it over everything in front of the screen, so it
	# hides while an object is between the eyes and the picture and the room draws the film (film_layer.gd).
	var film: Node = main.features.film_layer
	var was_forced: bool = film.force
	var was_on: bool = film.enabled
	film.force = true
	film.set_enabled(true, false)
	main.set_menu_shown(false)
	await _frames(2)
	_check("the film layer is a quad (%s)" % film.kind, film.kind == "quad")
	var r := await DevCommands.execute("object_throw", {"name": "Ball", "velocity": [v.x, v.y, v.z]}, false)
	_check("thrown at the screen (%s)" % r.get("error", ""), r["ok"])
	_check("the screen collides (%s)" % ph.state()["screen"], str(ph.state()["screen"]) == "flat")
	var min_z := INF
	var after := -INF
	var held_for_ball := false
	for i in 150:
		await physics_frame
		var z := _pos("Ball").z
		min_z = minf(min_z, z)
		if min_z < INF:
			after = z
		if film.held and film.covered_by == "Ball" and main.screen.get_node("Flat").visible 				and "something" in film.status():
			held_for_ball = true
		if not ph.is_moving("Ball"):
			break
	_check("in flight in front of the screen: the layer hidden, the room draws the film", held_for_ball)
	_check("landed out of the picture's way: the layer back after a second", not film.held
			and not main.screen.get_node("Flat").visible)
	# The bounds test itself: a box between the eyes and the picture covers it; beside it, behind the screen or
	# behind the eyes it does not.
	var probe := MeshInstance3D.new()
	probe.mesh = BoxMesh.new()
	probe.name = "Probe"
	root.add_child(probe)
	var flat_xf: Transform3D = main.screen.get_node("Flat").global_transform
	var scr := Transform3D(flat_xf.basis.orthonormalized(), flat_xf.origin)
	var half: Vector2 = main.screen.get_flat_size() * 0.5
	var eye := Vector3(0, 0, 10.0)
	var cases := {"between": [Vector3(0, 0, 5), true], "beside": [Vector3(half.x * 3.0, 0, 5), false],
			"behind the screen": [Vector3(0, 0, -2), false], "behind the eyes": [Vector3(0, 0, 12), false],
			"at the picture's edge": [Vector3(half.x * 0.5 + 0.3, 0, 5), true]}
	var wrong: Array = []
	for k: String in cases:
		probe.global_transform = scr * Transform3D(Basis(), cases[k][0])
		film._local_aabbs.clear()
		if film._covers(scr, eye, half, probe) != bool(cases[k][1]):
			wrong.append(k)
	probe.queue_free()
	_check("the bounds test: in front covers, beside / behind the screen / behind the eyes not (%s)" % ", ".join(wrong),
			wrong.is_empty())
	# A controller's laser held up between the eyes and the picture: the same (the controller vanished behind the
	# film, the user, 2026-11-06); put down out of the way: the layer back after a second.
	var hand: XRController3D = main.hands[0] if main.hands.size() > 0 else null
	if hand != null:
		var was_shown: bool = hand.show_when_tracked
		var was_visible := hand.visible
		var was_xf := hand.global_transform
		hand.show_when_tracked = false
		hand.visible = true
		var cam: Camera3D = main.get_viewport().get_camera_3d()
		var toward: Vector3 = (flat_xf.origin - cam.global_position).normalized()
		hand.global_transform = Transform3D(Basis.looking_at(toward, Vector3.UP), cam.global_position + toward * 0.4)
		hand.set_laser(true, 2.0)
		await _frames(3)
		_check("a controller and its laser in front of the picture: the layer hidden (%s)" % film.covered_by,
				film.held and film.covered_by.begins_with(str(hand.name)))
		hand.set_laser(false)
		hand.global_transform = Transform3D(Basis.looking_at(Vector3.DOWN, Vector3.FORWARD), cam.global_position
				+ Vector3(0.3, -0.7, 0.2))
		await _frames(3)
		var still_held: bool = film.held
		await create_timer(film.COVER_RELEASE + 0.3).timeout
		await _frames(2)
		_check("put down in the lap: held a second more, then the layer back (%s)" % film.covered_by, still_held
				and not film.held)
		# A curved screen as cylinder layers (drawn over everything too, 2026-11-04): a controller just in front of
		# the curve's edge counts, though the edge stands forward of the middle's plane and wider than the flat width.
		var was_radius := float(main.screen.curve_radius)
		main.screen.set_curve_radius(maxf(main.screen.get_flat_size().x * 0.6, 2.0))
		await _frames(2)
		var fx: Transform3D = main.screen.get_node("Flat").global_transform
		var sx := Transform3D(fx.basis.orthonormalized(), fx.origin)
		var rad := float(main.screen.curve_radius)
		var phi: float = main.screen.get_flat_size().x * 0.5 / rad
		var edge_local := Vector3(rad * sin(phi * 0.97), 0.0, rad * (1.0 - cos(phi * 0.97)))
		var eye_w: Vector3 = cam.global_position
		var edge_w: Vector3 = sx * edge_local
		var near_edge: Vector3 = edge_w + (eye_w - edge_w).normalized() * 0.3
		hand.global_transform = Transform3D(Basis.looking_at((edge_w - near_edge).normalized(), Vector3.UP), near_edge)
		var saved_kind: String = film.kind
		film.kind = "cylinder"
		var by: String = film._covered()
		film.kind = saved_kind
		_check("a curved screen: a controller in front of its edge covers it (%s)" % by, by.begins_with(str(hand.name)))
		main.screen.set_curve_radius(was_radius)
		hand.global_transform = was_xf
		hand.visible = was_visible
		hand.show_when_tracked = was_shown
	film.set_enabled(was_on, false)
	film.force = was_forced
	_check("it reached the screen (%.2f, the screen at %.2f)" % [min_z, target.z], min_z < target.z + 0.5)
	_check("and bounced back off it, not off the wall behind (%.2f, back to %.2f)" % [min_z, after],
			min_z > target.z - 0.15 and after > min_z + 0.3)
	await _until_still("Ball", 15.0)
	# A 360 picture: the sphere round the head collides instead.
	main.open_path("stub://360_mono")
	await _frames(10)
	ph._update_screen()
	var sphere: Array = ph._screen_shapes
	_check("a 360 picture: its sphere collides (%s, %d triangles)" % [ph.state()["screen"],
			(sphere[0][0] as ConcavePolygonShape3D).get_faces().size() / 3 if not sphere.is_empty() else 0],
			str(ph.state()["screen"]) == "sphere" and not sphere.is_empty()
			and (sphere[0][0] as ConcavePolygonShape3D).get_faces().size() / 3 >= PhysicsShapes.SPHERE_SEGMENTS
			* (PhysicsShapes.SPHERE_RINGS - 1))
	main.open_path("stub://flat_mono")
	await _frames(10)


## 20 m/s at the seat back in front: it doesn't pass through.
func _test_fast_throw() -> void:
	var r := await DevCommands.execute("object_throw", {"name": "Pellet", "velocity": [0, 0, -20]}, false)
	_check("thrown at 20 m/s (%s)" % r.get("error", ""), r["ok"])
	var seat: Transform3D = Cinema.seat_transforms()[(1 + Cinema.ROWS_BACK) * Cinema.SEATS_PER_ROW + Cinema.SEATS_PER_ROW / 2]
	var back_z := seat.origin.z + Cinema.SEAT_BACK_PIVOT.z - 0.15
	var min_z := INF
	for i in 60:
		await physics_frame
		min_z = minf(min_z, _pos("Pellet").z)
	_check("the seat back stops it (%.3f, the back's far side %.3f)" % [min_z, back_z], min_z > back_z)
	await _until_still("Pellet", 10.0)


func _test_put_back() -> void:
	var r := await DevCommands.execute("object_put_back", {"name": "Crate"}, false)
	_check("object_put_back (%s)" % r.get("error", ""), r["ok"])
	await _frames(3)
	_check("the crate is back where it was placed, its home gone", _pos("Crate").distance_to(Vector3(0, 0.8, -1.45))
			< 0.01 and not _part("Crate").has("home") and not ph.is_moving("Crate"))
	r = await DevCommands.execute("object_put_back", {"name": "Crate"}, false)
	_check("again: it is where it was placed", not r["ok"] and str(r.get("error", "")).contains("where it was placed"))
	await DevCommands.execute("object_throw", {"name": "Crate", "velocity": [0.5, 2, 0]}, false)
	await DevCommands.execute("object_throw", {"name": "Crate two", "velocity": [-0.5, 1, 0.5]}, false)
	await _frames(20)
	r = await DevCommands.execute("object_tidy_up", {}, false)
	_check("object_tidy_up, with two still moving (%s)" % r.get("error", ""), r["ok"]
			and (r.get("put_back", r.get("result", {}).get("put_back", [])) as Array).size() >= 3)
	await _frames(3)
	_check("everything is where it was placed", _pos("Crate").distance_to(Vector3(0, 0.8, -1.45)) < 0.01
			and _pos("Crate two").distance_to(Vector3(1.2, 0.8, -1.45)) < 0.01 and _pos("Ball").distance_to(
			Vector3(0, 1.4, -2.2)) < 0.01 and _part("Ball").get("home") == null)
	r = await DevCommands.execute("object_tidy_up", {}, false)
	_check("tidy again: nothing to do", not r["ok"])


## The clock stays on its wall while held near it; pulled 0.3 m off, it is a normal object.
func _test_wall() -> void:
	var at := _pos("Clock")
	_check("picked up", ph.pick_up("Clock"))
	var xf: Transform3D = ph.body_transform("Clock")
	ph.hold_to("Clock", xf.translated(Vector3(0.04, 0, 0)))
	await _frames(10)
	_check("held 4 cm off: still on its wall", ph.is_mounted("Clock") and not ph.is_moving("Clock")
			and _pos("Clock").distance_to(at) < 0.001)
	ph.hold_to("Clock", xf.translated(Vector3(0.4, -0.2, 0)))
	await _frames(15)
	_check("pulled 0.4 m off: off its wall, in the hand", not ph.is_mounted("Clock") and ph.is_moving("Clock")
			and _pos("Clock").distance_to(at) > 0.2)
	ph.let_go("Clock")
	await _until_still("Clock", 8.0)
	_check("let go: it falls; the document says it is off its wall", _pos("Clock").y < at.y - 0.5
			and _part("Clock").get("mounted") == false and _part("Clock").get("home") is Dictionary)
	var r := await DevCommands.execute("object_put_back", {"name": "Clock"}, false)
	await _frames(3)
	_check("put back: on its wall again (%s)" % r.get("error", ""), r["ok"] and ph.is_mounted("Clock")
			and _pos("Clock").distance_to(at) < 0.01 and not _part("Clock").has("mounted"))


## A text attached to an object follows it when it is thrown.
func _test_attach() -> void:
	var r := await DevCommands.execute("object_attach", {"name": "Label", "to": "Crate two", "offset": [0, 0.3, 0],
			"rotation": [0, 0, 0]}, false)
	_check("object_attach (%s)" % r.get("error", r.get("errors", "")), r["ok"] and _part("Label").get("attach")
			== "Crate two")
	await _frames(3)
	_check("the text stands over its object", _pos("Label").distance_to(_pos("Crate two") + Vector3(0, 0.3, 0)) < 0.01)
	r = await DevCommands.execute("object_attach", {"name": "Crate", "to": "Ball"}, false)
	_check("only a text or particles area attaches", not r["ok"])
	await DevCommands.execute("object_throw", {"name": "Crate two", "velocity": [0, 3, 1], "spin": [2, 0, 1]}, false)
	await _frames(12)
	var mid := _follow_error()
	await _until_still("Crate two", 10.0)
	await _frames(2)
	var end := _follow_error()
	_check("it follows in flight and where it lands (%.4f, %.4f m off)" % [mid, end], mid < 0.02 and end < 0.01)
	r = await DevCommands.execute("object_attach", {"name": "Label", "to": ""}, false)
	await _frames(3)
	var p := _pos("Label")
	_check("detached: it stays where it is (%s)" % r.get("error", ""), r["ok"] and not _part("Label").has("attach")
			and RoomSchema.vec3(_part("Label")["position"]).distance_to(p) < 0.01)
	await DevCommands.execute("object_tidy_up", {}, false)
	await _frames(3)


func _follow_error() -> float:
	var crate: Node3D = _node("Crate two")
	var label: Node3D = _node("Label")
	var want: Vector3 = Transform3D(PhysicsShapes.split(crate.global_basis)[0], crate.global_position) * Vector3(0, 0.3, 0)
	return label.global_position.distance_to(want)


## The thud: louder for a faster impact, lower for a bigger object.
func _test_thud() -> void:
	_check("louder for faster", Thud.gain_for(2.0, 0.3) < Thud.gain_for(8.0, 0.3)
			and Thud.gain_for(8.0, 0.3) < Thud.gain_for(15.0, 0.3) and Thud.gain_for(0.3, 0.3) == 0.0)
	_check("lower for bigger", Thud.pitch_for(3.0, 0.1) > Thud.pitch_for(3.0, 0.5))
	var s := Thud.samples(8.0, 0.3, 48000.0)
	var peak := 0.0
	for x in s:
		peak = maxf(peak, absf(x))
	_check("its samples peak at its gain (%.3f, %.3f)" % [peak, Thud.gain_for(8.0, 0.3)], absf(peak
			- Thud.gain_for(8.0, 0.3)) < 0.01 and s.size() == int(Thud.LENGTH * 48000.0))
	# Two drops on the seat: from its place (slow), then thrown down hard.
	await DevCommands.execute("object_throw", {"name": "Crate"}, false)
	var slow := await _first_thud("Crate")
	await DevCommands.execute("object_put_back", {"name": "Crate"}, false)
	await _frames(3)
	await DevCommands.execute("object_throw", {"name": "Crate", "velocity": [0, -9, 0]}, false)
	var fast := await _first_thud("Crate")
	_check("a faster impact thuds louder (%s m/s %s; %s m/s %s)" % [slow.get("speed"), slow.get("gain"),
			fast.get("speed"), fast.get("gain")], not slow.is_empty() and not fast.is_empty()
			and float(fast["speed"]) > float(slow["speed"]) and float(fast["gain"]) > float(slow["gain"]))
	_check("where it happened", not fast.is_empty() and (fast["position"] as Vector3).distance_to(
			main.env.global_transform * Vector3(0, 0.2, -1.45)) < 0.6)
	await _until_still("Crate", 8.0)
	await DevCommands.execute("object_tidy_up", {}, false)
	await _frames(3)


func _first_thud(_name: String) -> Dictionary:
	var n := int(ph.thud.count)
	for i in 120:
		await physics_frame
		if int(ph.thud.count) > n:
			return (ph.thud.last as Dictionary).duplicate()
	return {}


## The controls: the grip on the laser picks the ball up, the trigger does nothing then, a flick throws it at the
## tip's speed; B puts a held one back.
func _test_grip() -> void:
	var hand: Node3D = main.right_hand
	var grab: Node = main.features.grab
	var to_world: Transform3D = main.env.global_transform
	var ball: Vector3 = to_world * Vector3(0, 1.4, -2.2)
	var from: Vector3 = to_world * Vector3(0.2, 1.1, -0.2)
	hand.global_transform = Transform3D(Basis.looking_at(ball - from), from)
	main._on_grip(hand, true)
	_check("the grip on the laser picks up what it points at (%s)" % grab.holding(hand), grab.holding(hand) == "Ball"
			and ph.is_held("Ball"))
	var playing: bool = main.player.is_playing()
	main._on_trigger(hand, true)
	main._on_trigger(hand, false)
	_check("the trigger does nothing while holding", main.player.is_playing() == playing)
	# A flick: the hand turns up and to the left over a few frames; the ball follows the laser's tip.
	for i in 8:
		hand.global_transform = Transform3D(Basis.looking_at(ball - from).rotated(Vector3.UP, 0.04 * i)
				.rotated(Vector3.RIGHT, 0.03 * i), from)
		await process_frame
	var tip_speed: float = ObjectGrab.throw_velocity(grab._holds[hand]["history"]).length()
	main._on_grip(hand, false)
	await physics_frame
	await physics_frame
	var v: Vector3 = PhysicsServer3D.body_get_state(ph._bodies["Ball"].rid, PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY)
	_check("let go: thrown at the tip's speed (%.2f m/s, the tip %.2f)" % [v.length(), tip_speed],
			grab.holding(hand) == "" and ph.is_moving("Ball") and tip_speed > 0.5 and absf(v.length() - tip_speed) < 1.0)
	await _until_still("Ball", 15.0)
	await DevCommands.execute("object_tidy_up", {}, false)
	await _frames(3)
	hand.global_transform = Transform3D(Basis.looking_at(ball - from), from)
	main._on_grip(hand, true)
	hand.global_transform = Transform3D(Basis.looking_at(ball - from).rotated(Vector3.UP, 0.3), from)
	await _frames(5)
	var b: bool = grab.on_back(hand)
	await _frames(2)
	_check("B while holding: back where it was picked up", b and grab.holding(hand) == "" and not ph.is_moving("Ball")
			and _pos("Ball").distance_to(Vector3(0, 1.4, -2.2)) < 0.01)
	# In the hand: the controller in the plant.
	var plant := _node("Plant").global_position + Vector3(0, 0.15, 0)
	hand.global_transform = Transform3D(Basis(), plant)
	main._on_grip(hand, true)
	_check("in the hand: the controller in an object picks it up", grab.holding(hand) == "Plant"
			and str(grab._holds[hand]["by"]) == "hand")
	main._on_grip(hand, false)
	await _until_still("Plant", 8.0)
	await DevCommands.execute("object_tidy_up", {}, false)
	await _frames(3)
	hand.global_transform = Transform3D(Basis.looking_at(Vector3(0, -1, -0.2)), Vector3(0, 1.1, 0.3))
	main._on_grip(hand, true)
	_check("the grip pointing at nothing: as before (no hold)", grab.holding(hand) == "")
	main._on_grip(hand, false)


func _test_labels() -> void:
	var p: String = main.PREVIEW_PROFILE
	var normal: Dictionary = main.controller_labels(p, "right", false)
	var grab: Dictionary = main.controller_labels(p, "right", false, false, false, true, false)
	var hold: Dictionary = main.controller_labels(p, "right", false, false, false, true, true)
	var squeeze := ""
	for k: String in grab:
		if str(grab[k]).contains("GRAB"):
			squeeze = k
	_check("the squeeze says GRAB with objects in the room (%s)" % grab.get(squeeze, ""), squeeze != ""
			and not str(normal.get(squeeze, "")).contains("GRAB"))
	_check("holding: let go to throw, the stick near-far / turn, no play / pause (%s)" % [hold.values()],
			str(hold.get(squeeze, "")).contains("THROW") and hold.values().any(func(t: String) -> bool:
			return t.contains("NEAR-FAR")) and not hold.values().any(func(t: String) -> bool:
			return t.contains("PLAY")))
	_check("the menu shown: no GRAB", not main.controller_labels(p, "right", true, false, false, true, false)
			.values().any(func(t: String) -> bool: return t.contains("GRAB")))


## An imported object's hulls are kept beside it; one imported before physics gets them the first time it loads.
func _test_hulls_kept() -> void:
	var r := ObjectLibrary.import_glb(_ball_glb(), "Physics test ball", [], "floor")
	_check("imported (%s)" % r.get("error", ""), r.get("ok") == true)
	if r.get("ok") != true:
		return
	var id := str(r["manifest"]["id"])
	var path := ObjectLibrary.USER_DIR.path_join(id).path_join(ObjectLibrary.COLLISION)
	_check("its hulls are kept beside it", FileAccess.file_exists(path))
	DirAccess.remove_absolute(path)
	ObjectLibrary._hulls.erase(id)
	var hulls := ObjectLibrary.collision(id)
	_check("missing (an older import): made the first time it is asked for, and kept", hulls.size() == 1
			and FileAccess.file_exists(path))


## The cost with 24 bodies, as object_physics measures it (state() cost_ms): the physics step's wall time at rest and
## with all 24 thrown about, and object_physics.gd's own share of a tick. On the desktop.
func _test_cost() -> void:
	var parts: Array = []
	for i in 24:
		var x := -6.0 + (i % 8) * 1.7
		var z := -2.5 - float(i / 8) * 2.6
		var kinds := ["box", "sphere", "pot_plant", "cylinder"]
		var part := {"name": "Thing %d" % i, "object": kinds[i % 4], "position": [x, 1.6, z]}
		if kinds[i % 4] == "box":
			part["scale"] = [0.3, 0.2, 0.25]
		elif kinds[i % 4] == "sphere":
			part["scale"] = 0.25
		elif kinds[i % 4] == "cylinder":
			part["scale"] = [0.2, 0.35, 0.2]
		parts.append(part)
	var r: Dictionary = await ObjectLibrary.editor_for(self).apply("new", {"schema": 3, "name": COST_ROOM,
			"base": "cinema", "parts": parts}, "test")
	_check("a room of 24 objects (%s)" % r.get("error", ""), r.get("ok") == true)
	await _frames(5)
	_check("24 bodies (%d), built in %s ms" % [ph.names().size(), ph.state()["build_ms"]], ph.names().size() == 24)
	await DevCommands.execute("object_throw", {"name": "Thing 0", "velocity": [0, 0.1, 0]}, false)
	await _until_still("Thing 0", 8.0)
	await _frames(5)
	ph.reset_cost()
	await _frames(130)
	var rest: Dictionary = ph.state()["cost_ms"]
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for n: String in ph.names():
		ph.throw(n, Vector3(rng.randf_range(-3, 3), rng.randf_range(1, 5), rng.randf_range(-3, 3)),
				Vector3(rng.randf_range(-3, 3), rng.randf_range(-3, 3), rng.randf_range(-3, 3)))
	ph.reset_cost()
	await _frames(125)
	var busy: Dictionary = ph.state()["cost_ms"]
	var moving := int(ph.state()["moving"])
	print("COST (ms a tick, desktop, %d CPUs): the step at rest %.3f; %d moving: the step %.3f (most %.3f), "
			% [OS.get_processor_count(), rest["rest"], moving, busy["step"], busy["step_max"]]
			+ "object_physics.gd %.3f; the room %d shapes, built in %s ms" % [busy["script"], ph.state()["room_shapes"],
			ph.state()["build_ms"]])
	_check("at rest the step costs next to nothing (%.3f ms)" % rest["rest"], float(rest["rest"]) < 0.1)
	_check("24 moving (%d): object_physics.gd's share under 0.5 ms (%.3f)" % [moving, busy["script"]], moving >= 20
			and float(busy["script"]) < 0.5)
	_check("24 moving: the step measured (%.3f ms; Jolt spreads it over every worker thread)" % busy["step"],
			float(busy["step"]) > 0.0 and float(busy["step"]) < 3.0)


# --- Helpers ------------------------------------------------------------------------------------------------------

func _until_still(name: String, seconds: float) -> void:
	var t := 0.0
	while ph.is_moving(name) and t < seconds:
		await physics_frame
		t += 1.0 / Engine.physics_ticks_per_second


func _ticks(n: int) -> void:
	for i in n:
		await physics_frame


func _node(name: String) -> Node3D:
	return main.env.get_node_or_null("AssistantLayer/" + name) as Node3D


## A placement's node in the room frame.
func _pos(name: String) -> Vector3:
	var n := _node(name)
	return n.transform.origin if n != null else Vector3.INF


func _part(name: String) -> Dictionary:
	for p: Dictionary in (main.env.get("doc") as Dictionary).get("parts", []):
		if p["name"] == name:
			return p
	return {}


func _ball_glb() -> PackedByteArray:
	var root_node := Node3D.new()
	root_node.name = "Ball"
	var mi := MeshInstance3D.new()
	mi.name = "Ball"
	var sphere := SphereMesh.new()
	sphere.radius = 0.1
	sphere.height = 0.2
	mi.mesh = sphere
	root_node.add_child(mi)
	var bytes := ObjectLibrary.to_glb(root_node)
	root_node.free()
	return bytes


func _cleanup() -> void:
	for name: String in [ROOM, COST_ROOM]:
		var dir := AssistantRoom.files_dir(name)
		if DirAccess.dir_exists_absolute(dir):
			for f in DirAccess.get_files_at(dir):
				DirAccess.remove_absolute(dir.path_join(f))
			DirAccess.remove_absolute(dir)
		DirAccess.remove_absolute(AssistantRoom.json_path(name))
	for m: Dictionary in ObjectLibrary.list("", "user"):
		if not (m["id"] in _objects_before):
			ObjectLibrary.delete(m["id"])
			ObjectLibrary.purge(m["id"])


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _check(what: String, ok: bool) -> void:
	_checks += 1
	if not ok:
		_failures += 1
		print("FAIL " + what)
