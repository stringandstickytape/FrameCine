extends SceneTree

## The builders' tests' common part (docs/environments.md, "The builders"; tests/test_env_<builder>.gd extend it): a
## small test room (a document with the light system, the builder and maybe the kit) is built headless like a room that
## ships (env_room.gd) and checked as tests/test_environments.gd checks a shipped room: schema, comfort, licences,
## names, no people, the headset's budget (measured), a clear sight line from every seat; and the builder's own
## conventions: its seats as slots (the same before and after the build), seat picking (the viewer's own seat folded
## away), object physics (shapes, something under every seat), the bake hooks (static meshes with UV2 and an atlas
## hint, hidden bake lights), its sound room and its slots. Not a test itself (no test_ prefix).

const EnvChecks := preload("res://scripts/env/env_checks.gd")
const EnvDoc := preload("res://scripts/env/env_doc.gd")
const EnvRoom := preload("res://scripts/env/env_room.gd")
const Registry := preload("res://scripts/env/systems/registry.gd")
const PhysicsShapes := preload("res://scripts/play/physics_shapes.gd")
## The largest lightmap atlas a builder's mesh may ask for (texels a side).
const MAX_ATLAS := 2048
const EnvAudio := preload("res://scripts/env/env_audio.gd")

var _failures := 0
var _checks := 0
var test_name := "test"
## Every room checked: [label, stats].
var figures: Array = []


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	await run_tests()
	for f: Array in figures:
		print("  %s: %s" % [f[0], f[1]])
	print("%s: %d checks, %s" % [test_name, _checks, "all passed" if _failures == 0 else "%d FAILED" % _failures])
	quit(_failures)


## Overridden by each test.
func run_tests() -> void:
	pass


## A test room's document: the light system first, then `systems`; the screen as the builder suggests.
func room_doc(room_name: String, systems: Array, screen: Dictionary, extra := {}) -> Dictionary:
	var d := {"schema": 4, "name": room_name, "room": {"ambient": 0.05, "screen_glow": 1.0},
			"screen": screen, "systems": [{"system": "light"}]}
	(d["systems"] as Array).append_array(systems)
	d.merge(extra, true)
	return d


## The builder's default screen for these parameters (its static screen_for()).
func screen_of(system_name: String, given := {}) -> Dictionary:
	var spec := Registry.spec(system_name)
	var p := EnvDoc.with_defaults(spec["params"], given)
	return Registry.script_of(system_name).call("screen_for", p)


## Builds the document's room and checks it. Returns the room (in the tree; free it with done()).
func check_room(label: String, doc: Dictionary, builder_id := "") -> Node3D:
	var s := EnvChecks.static_checks(doc)
	for k: String in s:
		check("%s: %s %s" % [label, k, s[k]], (s[k] as Array).is_empty())
	var pre: Node3D = EnvRoom.new()
	pre.doc = doc
	var before: Array[Transform3D] = pre.room_seat_transforms()
	var shapes_before: Array = pre.collision_shapes()
	pre.free()
	var room: Node3D = EnvRoom.new()
	room.doc = doc
	root.add_child(room)
	await process_frame
	var stats := EnvChecks.measure(room)
	figures.append([label, stats])
	var over := EnvChecks.budget(stats)
	check("%s: within the headset's budget %s %s" % [label, stats, over], over.is_empty())
	var blocked: Array = await EnvChecks.sight_line(self, room)
	var seats: Array[Transform3D] = room.room_seat_transforms()
	check("%s: a clear sight line from every seat (%d seats) %s" % [label, seats.size(), blocked], blocked.is_empty())
	check("%s: the seats from the document alone are the built room's (%d, %d)" % [label, before.size(), seats.size()],
			before.size() == seats.size() and (before.is_empty() or before[0].is_equal_approx(seats[0])))
	if builder_id != "":
		await _builder(label, room, builder_id, shapes_before)
	return room


func _builder(label: String, room: Node3D, builder_id: String, shapes_before: Array) -> void:
	var b: Node = room.host.system(builder_id)
	check("%s: the builder is built" % label, b != null)
	if b == null:
		return
	var slots: Array = b.seat_slots()
	var seats: Array[Transform3D] = room.room_seat_transforms()
	var well_formed := true
	for s: Dictionary in slots:
		if not s.has_all(["transform", "row", "style", "width"]) or str(s["builder"]) != builder_id:
			well_formed = false
	check("%s: seat slots (%d) with transform, row, style, width, builder" % [label, slots.size()], well_formed)
	var own := slots.any(func(s: Dictionary) -> bool: return (s["transform"] as Transform3D).origin.length() < 0.05)
	check("%s: the viewer's own seat at the origin, or no seats" % label, own or slots.is_empty())
	# Object physics: shapes, something under each seat.
	var shapes: Array = room.collision_shapes()
	# A kit's boxes follow the builder's slots, so they exist only once built (no static form).
	var built_only := 0
	for s: Node in room.host.order:
		if s.has_method("collision_shapes") and not s.get_script().has_method("collision_shapes_for"):
			built_only += (s.collision_shapes() as Array).size()
	check("%s: collision shapes (%d), the same before the build (%d, %d only once built)" % [label, shapes.size(),
			shapes_before.size(), built_only], shapes.size() > 4 and shapes.size() - built_only == shapes_before.size())
	var body := StaticBody3D.new()
	for sh: Array in shapes:
		var cs := CollisionShape3D.new()
		cs.shape = sh[0]
		cs.transform = sh[1]
		body.add_child(cs)
	root.add_child(body)
	await physics_frame
	await physics_frame
	var space := root.get_world_3d().direct_space_state
	var floating := 0
	for st in seats:
		var q := PhysicsRayQueryParameters3D.create(st.origin + Vector3.UP * 2.0, st.origin + Vector3.DOWN * 0.3)
		var hit := space.intersect_ray(q)
		if hit.is_empty() or (hit["position"] as Vector3).y < st.origin.y - 0.1:
			floating += 1
	check("%s: something under every seat (%d without)" % [label, floating], floating == 0)
	body.queue_free()
	# The bake hooks.
	var statics: Array[MeshInstance3D] = room.static_meshes()
	var atlas_ok := true
	var largest := Vector2i.ZERO
	for mi in statics:
		var hint := (mi.mesh as ArrayMesh).lightmap_size_hint
		largest = largest.max(hint)
		if hint.x <= 0 or hint.x > MAX_ATLAS or hint.y > MAX_ATLAS:
			atlas_ok = false
	(figures[-1][1] as Dictionary)["atlas"] = largest
	check("%s: static meshes for the bake (%d), each with an atlas under %d" % [label, statics.size(), MAX_ATLAS],
			not statics.is_empty() and atlas_ok)
	var lights: Node3D = room.bake_lights()
	var hidden := lights != null and lights.get_children().all(func(l: Node) -> bool: return not (l as Light3D).visible)
	check("%s: the bake lights hidden (%d)" % [label, lights.get_child_count() if lights != null else -1], hidden)
	room.set_baking(true)
	room.set_baking(false)
	check("%s: a sound room with walls" % label, room.get_sound_room().has("box"))
	check("%s: slots for the kit" % label, b.has_method("slots") and not (b.slots() as Dictionary).is_empty())
	# Seat picking: choosing a seat moves the room so it is at the origin; a single seat folds away.
	var single := slots.filter(func(s: Dictionary) -> bool: return str(s["style"]) in ["chair", "club", "ring"])
	if not single.is_empty() and room.get_node_or_null("Seats") != null:
		var k := single.size() - 1
		var st: Transform3D = single[k]["transform"]
		room.transform = Transform3D(Basis(), -st.origin)
		await process_frame
		var idx := seats.find(st)
		check("%s: a chosen seat folds away (%d, %d)" % [label, b.hidden_seat(), idx], b.hidden_seat() == idx)
		room.transform = Transform3D()
		await process_frame
		check("%s: back at the room's own seat, the viewer's own folded" % label,
				seats[b.hidden_seat()].origin.length() < 0.05 if b.hidden_seat() >= 0 else false)


## The domestic telly round its picture (the builder's screen {center, size}): the set's front face is in the picture's
## plane with the picture inside it, and its glass is just behind, the picture's own size. "" when it is so, else why
## not. Reads the Telly mesh's flat faces facing the viewer.
func telly_glass(room: Node3D, screen: Dictionary) -> String:
	var telly := room.get_node_or_null("Telly") as MeshInstance3D
	if telly == null:
		return "no Telly"
	var c := Vector3(float(screen["center"][0]), float(screen["center"][1]), float(screen["center"][2]))
	var pic := Rect2(c.x - float(screen["size"][0]) * 0.5, c.y - float(screen["size"][1]) * 0.5,
			float(screen["size"][0]), float(screen["size"][1]))
	# Every triangle facing +z with its three corners at one depth, by that depth (mm).
	var planes := {}
	var faces := telly.mesh.get_faces()
	for i in range(0, faces.size(), 3):
		var a := telly.transform * faces[i]
		var b := telly.transform * faces[i + 1]
		var d := telly.transform * faces[i + 2]
		if absf(a.z - b.z) > 0.0005 or absf(a.z - d.z) > 0.0005:
			continue
		var key := roundi(a.z * 1000.0)
		var r := Rect2(Vector2(a.x, a.y), Vector2.ZERO).expand(Vector2(b.x, b.y)).expand(Vector2(d.x, d.y))
		planes[key] = (planes[key] as Rect2).merge(r) if planes.has(key) else r
	var front_key := roundi(c.z * 1000.0)
	if not planes.has(front_key):
		return "no front face in the picture's plane (z %.3f; planes %s)" % [c.z, planes.keys()]
	var front: Rect2 = planes[front_key]
	if not front.grow(0.001).encloses(pic):
		return "the picture %s is not inside the set's front %s" % [pic, front]
	for key: int in planes:
		var z := key / 1000.0
		var r: Rect2 = planes[key]
		if z < c.z and z > c.z - 0.06 and absf(r.position.x - pic.position.x) < 0.005 \
				and absf(r.position.y - pic.position.y) < 0.005 and absf(r.size.x - pic.size.x) < 0.005 \
				and absf(r.size.y - pic.size.y) < 0.005:
			return ""
	return "no glass the picture's size just behind it (%s, planes %s)" % [pic, planes]


## A kit's video recorder: its clock's digits glow (12:00 in seven segments: 21 of them) and flash once a second, each
## change eased (never faster than the photosensitivity ceiling's fade); Flickering lights off holds it lit.
func clock_flashes(label: String, room: Node3D) -> void:
	var kit: Node = room.host.system_of_kind("kit")
	var display := room.get_node_or_null("PieceDisplay") as MeshInstance3D
	var tris := (display.mesh.get_faces().size() / 3) if display != null else 0
	check("%s: the video recorder's clock, 12:00 in segments (%d triangles)" % [label, tris], tris == 42)
	if kit == null:
		return
	room.host.auto = false
	var values: Array[float] = []
	for i in 90:
		room.host.step(1.0 / 30.0)
		values.append(kit.clock_level())
	var rises := 0
	var fastest := 0.0
	for i in range(1, values.size()):
		fastest = maxf(fastest, absf(values[i] - values[i - 1]) * 30.0)
		if values[i - 1] < 0.5 and values[i] >= 0.5:
			rises += 1
	check("%s: the clock flashes 12:00 once a second (%.2f..%.2f, %d in 3 s), eased (%.1f a second)" % [label,
			values.min(), values.max(), rises, fastest], float(values.min()) < 0.05 and float(values.max()) > 0.95
			and rises >= 2 and rises <= 3 and fastest <= 1.0 / EnvChecks.MIN_FADE)
	room.host.set_setting("flicker", false)
	room.host.step(0.5)
	check("%s: Flickering lights off: the clock held lit (%.2f)" % [label, kit.clock_level()], kit.clock_level() == 1.0)
	room.host.set_setting("flicker", true)


## The room's sound (docs/environments.md, "Sound and music", "For the rooms"): a small room's acoustics; these beds
## (id -> sound), each in the room near what makes it, at its designed level 10 dB or more under the level check's
## target, all of them together 6 dB or more under it; the streams made and the loops playing.
func sounds(id: String, room: Node3D, want: Dictionary) -> void:
	var host: Node = room.host
	var ac: Node = null
	for s: Node in host.order:
		if s.get_script() == Registry.script_of("acoustics"):
			ac = s
	check("%s: a small room's acoustics" % id, ac != null and str(ac.params["preset"]) == "small_room")
	var beds := {}
	for s: Node in host.order:
		if s.get_script() == Registry.script_of("sound_bed"):
			beds[str(s.get("id"))] = s
	var have := {}
	for k: String in beds:
		have[k] = str(beds[k].params["sound"])
	check("%s: its sounds %s" % [id, have], have == want)
	host.auto = false
	for i in 200:
		if beds.values().all(func(b: Node) -> bool: return b.stream() != null):
			break
		host.step(0.05)
		await process_frame
	check("%s: every sound made" % id, beds.values().all(func(b: Node) -> bool: return b.stream() != null))
	var target := float(EnvAudio.LEVEL_TARGET_DB)
	var power := 0.0
	var dom: Node = host.system_of_kind("builder")
	var box: AABB = dom.get_script().call("_box", dom.get_script().call("resolved", dom.params))
	for k: String in beds:
		var b: Node = beds[k]
		var db := float(b.designed_db())
		power += db_to_linear(db) ** 2
		check("%s: %s %.1f dB, 10 dB or more under the target %.0f" % [id, k, db, target], db <= target - 10.0)
		var at := Vector3(float(b.params["at"][0]), float(b.params["at"][1]), float(b.params["at"][2]))
		check("%s: %s in the room (%s)" % [id, k, at], str(b.params["place"]) != "at" or box.grow(0.05).has_point(at))
		if b.is_loop() and float(b.params["level"]) > 0.01:
			check("%s: %s playing" % [id, k], b.playing())
			var bus := "Environment room"
			var i := AudioServer.get_bus_index(bus)
			check("%s: %s on the room's bus, which sends to Environment (%s)" % [id, k, (b.players() as Array).map(
					func(p: Node) -> String: return str(p.get("bus")))], (b.players() as Array).all(
					func(p: Node) -> bool: return str(p.get("bus")) == bus) and i >= 0
					and str(AudioServer.get_bus_send(i)) == str(EnvAudio.ENVIRONMENT))
	if not beds.is_empty():
		var all_db := 10.0 * log(power) / log(10.0)
		check("%s: all its sounds together %.1f dB, 6 dB or more under the target" % [id, all_db], all_db <= target - 6.0)


func done(room: Node3D) -> void:
	room.queue_free()
	await process_frame


func check(what: String, ok: bool) -> void:
	_checks += 1
	if not ok:
		_failures += 1
		print("FAIL: ", what)
