extends "res://tests/env_builder_harness.gd"

## The shipped rooms' tests' common part (tests/test_room_<id>.gd extend it): a room that ships as its document alone
## (app/environments/<id>.env.json) is read, built headless and checked as tests/test_environments.gd checks it, plus
## the conventions a room with a seats system keeps (the builder's own checks in env_builder_harness.gd assume the
## builder draws its seats): the viewer's seat at the origin (the room's default), seat picking folding the chosen
## chair away, object physics the same before and after the build with something under every seat, the bake hooks, a
## sound room. And a render from the viewer's seat when there is a renderer (user://room_render/<file>.png), with a
## plain lit quad standing in for the film. Not a test itself (no test_ prefix).

const OUT := "user://room_render"


## The document at `path`, read and checked, built and checked. Returns the room (in the tree; free it with done()).
func check_shipped(label: String, path: String, builder_id: String) -> Node3D:
	var r := EnvDoc.load_file(path)
	check("%s: the document reads %s" % [label, r["errors"]], (r["errors"] as Array).is_empty())
	var doc: Dictionary = r["doc"]
	var pre: Node3D = EnvRoom.new()
	pre.doc = doc
	var shapes_before := (pre.collision_shapes() as Array).size()
	pre.free()
	var room := await check_room(label, doc)
	var b: Node = room.host.system(builder_id)
	check("%s: the builder %s is built" % [label, builder_id], b != null)
	if b == null:
		return room
	check("%s: the document's screen is the builder's %s" % [label, b.screen()], same_screen(doc["screen"], b.screen()))
	var seats: Array[Transform3D] = room.room_seat_transforms()
	check("%s: the viewer's seat at the origin, the room's own (%d seats)" % [label, seats.size()],
			seats.any(func(t: Transform3D) -> bool: return t.origin.length() < 0.05))
	var shapes: Array = room.collision_shapes()
	check("%s: collision shapes (%d), as many as before the build (%d)" % [label, shapes.size(), shapes_before],
			shapes.size() > 4 and shapes.size() == shapes_before)
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
	var statics: Array[MeshInstance3D] = room.static_meshes()
	var lights: Node3D = room.bake_lights()
	check("%s: static meshes for the bake (%d), the bake lights hidden" % [label, statics.size()],
			not statics.is_empty() and lights != null
			and lights.get_children().all(func(l: Node) -> bool: return not (l as Light3D).visible))
	check("%s: a sound room with walls" % label, room.get_sound_room().has("box"))
	return room


## Seat picking: the room moved so seat `k` is at the origin; the seats system folds that chair away (`folds`), or
## leaves every seat standing (cushions). Back at the room's own seat afterwards.
func check_seat_pick(label: String, room: Node3D, k: int, folds: bool) -> void:
	var sys: Node = room.host.system_of_kind("seats")
	var seats: Array[Transform3D] = room.room_seat_transforms()
	room.transform = Transform3D(Basis(), -seats[k].origin)
	await process_frame
	var f: int = sys.folded()
	var ok: bool = (f >= 0 and (sys.drawn()[f]["xf"] as Transform3D).origin.is_equal_approx(seats[k].origin)) if folds \
			else f == -1
	check("%s: seat %d picked: %s (%d)" % [label, k, "its chair folds away" if folds else "every seat stays", f], ok)
	room.transform = Transform3D()
	await process_frame


func steps(host: Node, seconds: float) -> void:
	for i in roundi(seconds * 30.0):
		host.step(1.0 / 30.0)


static func same_screen(a: Dictionary, b: Dictionary) -> bool:
	for i in 3:
		if absf(float(a["center"][i]) - float(b["center"][i])) > 0.01:
			return false
	for i in 2:
		if absf(float(a["size"][i]) - float(b["size"][i])) > 0.01:
			return false
	return true


func rendering() -> bool:
	return DisplayServer.get_name() != "headless"


## The room moved into a viewport of its own with a camera and a lit quad where the film goes.
func render_view(room: Node3D) -> SubViewport:
	var vp := SubViewport.new()
	vp.size = Vector2i(960, 540)
	vp.own_world_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color.BLACK
	var we := WorldEnvironment.new()
	we.environment = env
	vp.add_child(we)
	room.get_parent().remove_child(room)
	vp.add_child(room)
	var doc: Dictionary = room.get("doc")
	var q := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(doc["screen"]["size"][0], doc["screen"]["size"][1])
	q.mesh = qm
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(0.55, 0.62, 0.7)
	q.material_override = m
	q.transform = room.get_screen_anchor()
	vp.add_child(q)
	var cam := Camera3D.new()
	cam.fov = 90.0
	cam.far = 200.0
	vp.add_child(cam)
	cam.current = true
	vp.set_meta("cam", cam)
	root.add_child(vp)
	room.apply_light(1.0)
	room.on_screen_changed(room.get_screen_anchor(), qm.size)
	return vp


## One picture from `at` looking at `look`, saved as user://room_render/<file>.png.
func shot(vp: SubViewport, at: Vector3, look: Vector3, file: String) -> void:
	var cam: Camera3D = vp.get_meta("cam")
	cam.look_at_from_position(at, look)
	for i in 8:
		await process_frame
	await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(OUT)
	img.save_png(OUT.path_join(file + ".png"))
	print("  rendered %s.png" % file)


## The room back in the tree's root; the viewport gone.
func end_render(vp: SubViewport, room: Node3D) -> void:
	vp.remove_child(room)
	root.add_child(room)
	vp.queue_free()
	await process_frame


func screen_point(room: Node3D) -> Vector3:
	return room.get_screen_anchor().origin
