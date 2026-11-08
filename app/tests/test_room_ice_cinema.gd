extends "res://tests/env_builder_harness.gd"

## The Ice cinema (app/environments/ice_cinema.env.json; docs/environments.md, "Room: Ice cinema"): an ice hotel's
## cinema far in the Arctic. Built headless from its document and checked as every shipped room is (schema, budget,
## sight lines from every seat, comfort, licences, names, no people) and as a builder's room (seats, physics, bake,
## seat picking); then what makes it this room: its figures and parts (the kit's ice hall: blocks, snow, candles, the
## carvings, the night outside), the room's own shell left to the kit, the candles' light in the bake only and their
## glow inside the ice, the Moon's light through the window for the bake, the window, the doorway and the skylights
## looking out on the night (the aurora in the left skylights), the film's colours in the ice round the screen, the
## ritual (the candles low for the film, the front wall's lowest, all back at the end), the aurora lively before the
## film and settling for it, swelling in a quiet scene, by its setting; the snow drifting past outside only; the ice's
## ring, the wind at the doorway, the huskies far off and the ice creaking now and then, and the room's level
## (tests/room_sound.gd).
## Under lavapipe it draws the room from its own seat, a side seat, up and back, in the pre-show and with a film
## playing, and close to the carvings (ICE_BAKE=1 bakes it first; ICE_RENDER_ONLY=1 skips the checks; ICE_SHOTS=preshow
## or film draws one of them).
## godot --headless --xr-mode off --path app --script res://tests/test_room_ice_cinema.gd

const RoomRender := preload("res://tests/room_render.gd")
const RoomSound := preload("res://tests/room_sound.gd")
const RoomBake := preload("res://scripts/env/room_bake.gd")
const IceHall := preload("res://scripts/env/systems/kit/ice_hall.gd")
const DOC := "res://environments/ice_cinema.env.json"
const BAKE_ID := "ice_cinema_render_test"


func run_tests() -> void:
	test_name = "test_room_ice_cinema"
	var r := EnvDoc.load_file(DOC)
	check("the document reads (%s)" % [r["errors"]], (r["errors"] as Array).is_empty())
	var doc: Dictionary = r["doc"]
	if doc.is_empty():
		return
	if OS.get_environment("ICE_RENDER_ONLY") == "":
		var room := await check_room("ice_cinema", doc)
		room.host.auto = false
		_by_part(room)
		_built(room)
		_candles(room)
		_views(room)
		_seep(room, doc)
		_ritual(room)
		_aurora(room)
		_snow(room)
		_sound(room)
		await done(room)
		await RoomSound.check_level(self, self, "ice_cinema", doc)
	await _render(doc)


## The figures (docs/environments.md, "Room: Ice cinema"), the parts, the room's own shell left to the kit.
func _built(room: Node3D) -> void:
	var host: Node = room.host
	var stats := EnvChecks.measure(room)
	check("the figures as documented: 15 to 22 draws, under 120k triangles, no live light, under 400 particles, "
			+ "under 16 MB (%s)" % [stats], int(stats["draws"]) >= 15 and int(stats["draws"]) <= 22
			and int(stats["triangles"]) < 120000 and int(stats["lights"]) == 0 and int(stats["particles"]) < 400
			and float(stats["texture_mb"]) < 16.0)
	for n: String in ["IceBlocks", "IceSnow", "IceWax", "IceFurs", "IceGlass", "IceFlames", "IceFlames_house",
			"IceOutside"]:
		check("the room has its %s" % n, room.find_child(n, true, false) != null)
	for n: String in ["Walls", "Floor", "Ceiling", "Trim", "Doorway", "Screen"]:
		check("the room's own %s left to the kit's ice" % n, room.get_node_or_null(n) == null)
	var kit: Node = host.system("kit")
	check("the kit draws without a problem (%s)" % [kit.problems()], kit.problems().is_empty())
	var dom: Node = host.system("room")
	var p: Dictionary = Registry.script_of("domestic").call("resolved", dom.params)
	check("the room is the domestic ice style, its shell the kit's", str(p["style"]) == "ice"
			and str(p["shell"]) == "kit")
	check("hides on every seat", str(host.system("seats").params["model"]) == "hide")
	# The bake: static meshes each with an atlas the headset bakes in a few seconds, the seats' boxes under the seats.
	var largest := Vector2i.ZERO
	for mi: MeshInstance3D in room.static_meshes():
		largest = largest.max((mi.mesh as ArrayMesh).lightmap_size_hint)
	print("  bake: %d static meshes, the largest atlas %s" % [room.static_meshes().size(), largest])
	check("static meshes for the bake, each atlas under %d (%s)" % [MAX_ATLAS, largest], largest.x > 0
			and largest.x <= MAX_ATLAS and largest.y <= MAX_ATLAS)
	check("a sound room with walls, physics round the room and under the seats", room.get_sound_room().has("box")
			and room.collision_shapes().size() > 20)
	# The ice on its own shader, its carvings and the blocks' sawn edges frosted (their alpha under a half), the
	# blocks' faces clear. The edges have many more vertices than the faces, so only both counts are checked.
	var blocks := room.find_child("IceBlocks", true, false) as MeshInstance3D
	var m := blocks.mesh.surface_get_material(0) as ShaderMaterial
	check("the ice on the ice shader", m != null and m.shader == IceHall.ICE_SHADER)
	var frosted := 0
	var clear := 0
	for c: Color in blocks.mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR]:
		if c.a < 0.5:
			frosted += 1
		else:
			clear += 1
	check("carvings and edges frosted (%d vertices), faces clear (%d)" % [frosted, clear], frosted > 1000
			and clear > 1000)


## The candles: twelve, each a flame, a glow in the ice and a light in the bake only; the Moon's light through the
## window for the bake; no live light.
func _candles(room: Node3D) -> void:
	var kit: Node = room.host.system("kit")
	var hall: Object = kit.get("_ctx").ice
	check("twelve candles (%d)" % hall.candles.size(), hall.candles.size() == 12)
	var front := (hall.candles as Array).filter(func(cd: Array) -> bool: return str(cd[2]) == "house")
	check("two on the front wall, in the house group (%d)" % front.size(), front.size() == 2)
	var lamps := room.find_children("KitLamp*", "OmniLight3D", true, false)
	var spots := room.find_children("KitSpot*", "SpotLight3D", true, false)
	var hidden := true
	for l: Node in lamps + spots:
		hidden = hidden and not (l as Light3D).visible
	check("each candle lights the bake (%d), the Moon through the window (%d), all hidden" % [lamps.size(),
			spots.size()], lamps.size() == 12 and spots.size() == 1 and hidden)
	var moon := spots[0] as SpotLight3D if not spots.is_empty() else null
	if moon != null:
		var dir := -moon.global_transform.basis.z
		check("the Moon's light comes in through the left wall's window, down a little (%s)" % dir, dir.x > 0.6
				and dir.y < 0.0)
	var glow: PackedVector4Array = hall.glow_colours()
	check("each candle glows in the ice (%d)" % glow.size(), glow.size() >= 12 and glow[0].x > 0.5)
	# No candle beside the picture: every one at least a metre from the screen's edge.
	var near := 0
	for cd: Array in hall.candles:
		var at: Vector3 = cd[0]
		if absf(at.z + 6.0) < 1.2 and absf(at.x) < 2.0:
			near += 1
	check("no candle beside the picture (%d)" % near, near == 0)


## The window and the doorway look out on the snow; the left skylights on the aurora's sky over the east.
func _views(room: Node3D) -> void:
	var eye := Vector3(0.0, 1.2, 0.0)
	var dom: Node = room.host.system("room")
	var p: Dictionary = Registry.script_of("domestic").call("resolved", dom.params)
	var inside := ["IceBlocks", "IceSnow", "IceFurs"]
	# Through the window's middle and the doorway's: nothing of the room in the way, the night's snow beyond.
	var win: Array = Registry.script_of("domestic").call("_window", p)
	var door: Array = Registry.script_of("domestic").call("_door", p)
	var win_c := Vector3(-float(p["half_width"]), (win[1] as Rect2).get_center().y,
			float(p["front_z"]) + (win[1] as Rect2).get_center().x)
	var door_c := Vector3(-float(p["half_width"]) + (door[1] as Rect2).get_center().x, 1.0, float(p["back_z"]) + 0.35)
	for v: Array in [["window", win_c], ["doorway", door_c]]:
		var dir := ((v[1] as Vector3) - eye).normalized()
		var hit := _first_hit(room, eye, dir, inside + ["IceOutside"])
		check("through the %s, the night outside (%s)" % [v[0], hit], hit == "IceOutside")
	# Up to the left, 30 degrees over the east (where the aurora hangs), through a skylight: the sky.
	var sky: Node = room.host.system("sky")
	var east: Vector3 = sky.bearing_dir(float(sky.params["aurora_bearing"]), float(sky.params["facing"]))
	var seen := 0
	for dz: float in [-1.5, 0.3, 2.1]:
		var target := Vector3(0.0, 0.0, dz) + east * 2.6 + Vector3(0, 2.8, 0)
		var dir := (target - eye).normalized()
		if _first_hit(room, eye, dir, inside + ["IceOutside"]) == "":
			seen += 1
	check("the aurora's sky through the left skylights (%d of 3)" % seen, seen >= 2)


## The film's colours in the ice round the screen: the ice knows where the picture is.
func _seep(room: Node3D, doc: Dictionary) -> void:
	var m := (room.find_child("IceBlocks", true, false) as MeshInstance3D).mesh.surface_get_material(0) as ShaderMaterial
	var c: Vector3 = m.get_shader_parameter("ice_screen_c")
	var half: Vector2 = m.get_shader_parameter("ice_screen_half")
	var s: Dictionary = doc["screen"]
	check("the film seeps into the ice round the screen (%.2f, at %s, %s)" % [float(m.get_shader_parameter(
			"ice_film")), c, half], float(m.get_shader_parameter("ice_film")) > 0.3
			and c.distance_to(Vector3(float(s["center"][0]), float(s["center"][1]), float(s["center"][2]))) < 0.05
			and half.is_equal_approx(Vector2(float(s["size"][0]), float(s["size"][1])) * 0.5))


## The ritual: the candles sink low for the film, the front wall's lowest; their glow in the ice follows; all back at
## the end.
func _ritual(room: Node3D) -> void:
	var host: Node = room.host
	var hall: Object = host.system("kit").get("_ctx").ice
	host.timeline.state = ""
	host.snapshot_override = {"open": false}
	_steps(host, 15.0)
	var before := [float(host.param("light.accent")), float(host.param("light.house_lamps")),
			_glow_sum(hall.glow_colours())]
	check("before the film: the candles bright (%s)" % [before], before[0] > 0.95 and before[1] > 0.95)
	host.snapshot_override = {"open": true, "playing": true, "position": 0.5, "duration": 7200.0}
	_steps(host, 20.0)
	var during := [float(host.param("light.accent")), float(host.param("light.house_lamps")),
			_glow_sum(hall.glow_colours())]
	check("with the film: the niches' candles low, the front wall's lower (%s)" % [during],
			absf(during[0] - 0.4) < 0.02 and absf(during[1] - 0.1) < 0.02)
	check("the glow in the ice follows them down (%.2f to %.2f)" % [before[2], during[2]], during[2] < before[2] * 0.45)
	host.snapshot_override = {"open": true, "playing": false, "ended": true, "position": 7200.0, "duration": 7200.0}
	_steps(host, 15.0)
	check("all back at the end (%.2f, %.2f)" % [float(host.param("light.accent")),
			float(host.param("light.house_lamps"))], float(host.param("light.accent")) > 0.95
			and float(host.param("light.house_lamps")) > 0.95)


## The aurora: lively before the film (the setting on "in quiet scenes"), settling for it, swelling slowly in a quiet
## scene and letting go; Always and Off as the setting says.
func _aurora(room: Node3D) -> void:
	var host: Node = room.host
	var sky: Node = host.system("sky")
	host.timeline.state = ""
	host.snapshot_override = {"open": false}
	host.signals.fake("film.quiet", 0.0)
	_steps(host, 20.0)
	check("before the film the aurora is lively (%.2f)" % float(sky.params["aurora"]),
			absf(float(sky.params["aurora"]) - 0.75) < 0.03)
	host.snapshot_override = {"open": true, "playing": true, "position": 0.5, "duration": 7200.0}
	_steps(host, 16.0)
	check("for the film it settles to a faint glow (%.2f)" % float(sky.params["aurora"]),
			absf(float(sky.params["aurora"]) - 0.15) < 0.02)
	host.signals.fake("film.quiet", 1.0)
	_steps(host, 4.0)
	var rising := float(sky.params["aurora"])
	_steps(host, 8.0)
	var full := float(sky.params["aurora"])
	check("a quiet scene: the aurora swells, slowly (%.2f, %.2f)" % [rising, full], rising > 0.2 and rising < 0.9
			and full > 0.95)
	host.signals.fake("film.quiet", 0.0)
	_steps(host, 14.0)
	check("the quiet ends: it settles again (%.2f)" % float(sky.params["aurora"]),
			absf(float(sky.params["aurora"]) - 0.15) < 0.02)
	host.set_setting("aurora", "always")
	check("Aurora always (%.2f)" % float(sky.params["aurora"]), absf(float(sky.params["aurora"]) - 0.8) < 0.01)
	host.set_setting("aurora", "off")
	host.signals.fake("film.quiet", 1.0)
	_steps(host, 12.0)
	check("Aurora off: none, even in a quiet scene (%.2f)" % float(sky.params["aurora"]),
			float(sky.params["aurora"]) < 0.01)
	host.signals.fake("film.quiet", 0.0)
	host.snapshot_override = {"open": false}
	_steps(host, 20.0)
	check("Aurora off: none before the film either (%.2f)" % float(sky.params["aurora"]),
			float(sky.params["aurora"]) < 0.01)
	host.set_setting("aurora", "quiet")
	_steps(host, 1.0)


## The snow drifts past outside the doorway and the window, never inside, a few hundred flakes.
func _snow(room: Node3D) -> void:
	var w: Node = room.host.system("weather")
	check("snow falls outside (%s)" % w.params["falls"], str(w.params["falls"]) == "snow"
			and int(w.params["particles"]) <= 300)
	var dom: Node = room.host.system("room")
	var p: Dictionary = Registry.script_of("domestic").call("resolved", dom.params)
	var box := AABB(Vector3(-float(p["half_width"]), 0.0, float(p["front_z"])), Vector3(float(p["half_width"]) * 2.0,
			4.0, float(p["back_z"]) - float(p["front_z"])))
	var outside := true
	for a: Dictionary in w.params["areas"]:
		var area := AABB(Vector3(a["min"][0], a["min"][1], a["min"][2]), Vector3(a["max"][0] - a["min"][0],
				a["max"][1] - a["min"][1], a["max"][2] - a["min"][2]))
		outside = outside and not area.intersects(box.grow(0.6))
	check("the snow's areas all outside the walls", outside)


## The ice's ring; far huskies, the wind at the doorway, the ice creaking now and then.
func _sound(room: Node3D) -> void:
	var host: Node = room.host
	RoomSound.check_beds(self, "ice_cinema", room, {"huskies": "huskies", "wind": "wind", "creak": "ice_creak"}, "ice")
	var wind: Array = host.system("wind").params["at"]
	check("the wind at the doorway (%s)" % [wind], absf(float(wind[0]) + 2.07) < 0.3 and float(wind[2]) > 3.0)
	var huskies: Node = host.system("huskies")
	var at: Array = huskies.params["at"]
	check("the huskies far off (%.0f m)" % Vector3(at[0], at[1], at[2]).length(),
			Vector3(at[0], at[1], at[2]).length() > 50.0)


func _first_hit(room: Node3D, from: Vector3, dir: Vector3, names: Array) -> String:
	var best := INF
	var which := ""
	for n: String in names:
		var mi := room.find_child(n, true, false) as MeshInstance3D
		if mi == null:
			continue
		var f := mi.mesh.get_faces()
		var xf := mi.global_transform
		for k in range(0, f.size(), 3):
			var hit: Variant = Geometry3D.ray_intersects_triangle(from, dir, xf * f[k], xf * f[k + 1], xf * f[k + 2])
			if hit != null and from.distance_to(hit) < best:
				best = from.distance_to(hit)
				which = n
	return which


static func _glow_sum(g: PackedVector4Array) -> float:
	var s := 0.0
	for v: Vector4 in g:
		s += v.x + v.y + v.z
	return s


static func _steps(host: Node, seconds: float, dt := 0.25) -> void:
	var t := 0.0
	while t < seconds:
		host.step(dt)
		t += dt


## The figures by part (printed for the docs): draws and triangles of each mesh.
func _by_part(room: Node3D) -> void:
	var rows: Array = []
	for g: Node in room.find_children("*", "GeometryInstance3D", true, false):
		if not (g as GeometryInstance3D).visible:
			continue
		var stats := {}
		if g is MeshInstance3D and (g as MeshInstance3D).mesh != null:
			var mi := g as MeshInstance3D
			stats = {"draws": mi.mesh.get_surface_count(), "triangles": EnvChecks._triangles(mi.mesh)}
		elif g is MultiMeshInstance3D and (g as MultiMeshInstance3D).multimesh != null:
			var mm := (g as MultiMeshInstance3D).multimesh
			stats = {"draws": mm.mesh.get_surface_count(), "triangles": EnvChecks._triangles(mm.mesh)
					* int(g.get_meta("instances", mm.instance_count))}
		if not stats.is_empty():
			rows.append([str(g.name), stats["draws"], stats["triangles"]])
	rows.sort_custom(func(a: Array, b: Array) -> bool: return int(a[2]) > int(b[2]))
	for r: Array in rows:
		print("  part %-22s %2d draws %7d triangles" % r)


func _render(doc: Dictionary) -> void:
	if not RoomRender.has_renderer():
		print("SKIP render (headless)")
		return
	var sc: Array = doc["screen"]["center"]
	var screen := Vector3(float(sc[0]), float(sc[1]), float(sc[2]))
	var baked := OS.get_environment("ICE_BAKE") != "" and RoomBake.can_bake()
	var only := OS.get_environment("ICE_SHOTS")
	for phase: String in ["preshow", "film"]:
		if only != "" and not (phase in only):
			continue
		RoomRender.set_light(screen, 0.05 if phase == "preshow" else 0.015)
		var vc := await RoomRender.open(self, doc)
		var host: Node = (vc[2] as Node).host
		if baked:
			var room := vc[2] as Node3D
			RoomBake.clear(BAKE_ID)
			RoomBake.prepare(room, BAKE_ID)
			room.call("set_baking", true)
			var br: Dictionary = RoomBake.bake(room, BAKE_ID)
			room.call("set_baking", false)
			print("  render: baked %s" % [br])
			for i in 4:
				await process_frame
		if phase == "preshow":
			# Before the film: the screen dark, a still picture on it (the menu), little of its light on the room.
			RenderingServer.global_shader_parameter_set("screen_glow", 0.15)
			host.snapshot_override = {"open": false}
			host.signals.fake("film.brightness", 0.0)
		else:
			host.snapshot_override = {"open": true, "playing": true, "position": 0.5, "duration": 7200.0}
			host.signals.fake("film.brightness", 0.7)
			host.signals.fake("film.colour", Color(0.85, 0.55, 0.35))
			host.signals.fake("playback.playing", 1.0)
		for i in 120:
			host.step(0.25)
		var eye := Vector3(0, 1.2, 0)
		var p := "ice_%s%s_" % ["baked_" if baked else "", phase]
		var img: Image = await RoomRender.shot(self, vc, eye, screen, p + "seat")
		# How lit the walls are beside the screen against the picture (printed for the docs).
		var walls := (RoomRender.mean(img, Rect2(0.05, 0.4, 0.12, 0.2)).get_luminance()
				+ RoomRender.mean(img, Rect2(0.83, 0.4, 0.12, 0.2)).get_luminance()) * 0.5
		var picture := RoomRender.mean(img, Rect2(0.45, 0.45, 0.1, 0.08)).get_luminance()
		print("  render: %s from the seat: the walls %.3f, the picture %.3f" % [phase, walls, picture])
		await RoomRender.shot(self, vc, eye, eye + Vector3(-1.0, 0.1, -0.2), p + "left")
		await RoomRender.shot(self, vc, eye, eye + Vector3(1.0, 0.1, -0.3), p + "right")
		await RoomRender.shot(self, vc, eye, eye + Vector3(-0.35, 1.0, -0.15), p + "up")
		await RoomRender.shot(self, vc, eye, eye + Vector3(0.0, 0.05, 1.0), p + "back")
		var side := Vector3(-2.0, 0, 1.1)
		var best := Vector3(999, 0, 0)
		for t: Transform3D in (vc[2] as Node).call("room_seat_transforms"):
			if t.origin.distance_to(side) < best.distance_to(side):
				best = t.origin
		await RoomRender.shot(self, vc, best + Vector3(0, 1.2, 0), screen, p + "side_seat")
		(vc[1] as Camera3D).fov = 50.0
		await RoomRender.shot(self, vc, eye, Vector3(-3.0, 1.4, -2.5), p + "window")
		await RoomRender.shot(self, vc, eye, Vector3(-2.0, 1.2, 3.0), p + "doorway")
		await RoomRender.shot(self, vc, eye, Vector3(-1.9, 2.3, -6.0), p + "frame")
		await RoomRender.shot(self, vc, Vector3(-1.2, 1.1, -3.9), Vector3(-2.45, 0.6, -6.0), p + "bear")
		await RoomRender.shot(self, vc, Vector3(0.0, 1.5, -3.2), Vector3(0.0, 3.0, -6.0), p + "owl")
		await RoomRender.shot(self, vc, Vector3(1.2, 1.2, -3.9), Vector3(2.45, 1.2, -6.0), p + "fox")
		await RoomRender.shot(self, vc, Vector3(1.6, 1.2, -1.0), Vector3(2.9, 1.06, -0.6), p + "niche")
		(vc[1] as Camera3D).fov = 90.0
		await RoomRender.close(self, vc)
