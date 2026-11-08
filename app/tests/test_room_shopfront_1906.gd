extends "res://tests/env_builder_harness.gd"

## Shopfront 1906 (app/environments/shopfront_1906.env.json; docs/environments.md, "Room: Shopfront 1906"): a
## draper's shop of 1906 made a picture house, the deep pass of 2026-11-08. Built headless from its document and
## checked as every shipped room is (schema, budget, sight lines from every seat, comfort, licences, names, no people;
## its seats are the seats system's, so not the builder's seat checks); then what makes it this room: its figures (the
## headset's frame time: few draws, no live light, no particles), the Edwardian hall's parts, the pressed tin's maps,
## nothing of the hall before the picture, the player piano (clear of the front row, its keys going down as it plays
## and its roll turning, both still when it rests), the gas (six brackets and two pendants, lighting the bake only,
## turned low in the film but still glowing, slow), the booth (the beam's lens in its port, the projector's clatter
## in it), the street outside the glass and dimmer in the film, the cart that passes now and then before the film
## (outside the glass, left to right with its hooves' sound, legs and wheels slow, gone at the end), the clock (the
## viewer's own time), and the sound (the beds, the acoustics, the room's level: tests/room_sound.gd).
## Under lavapipe it draws the room (SHOPFRONT_BAKE=1 bakes it first; SHOPFRONT_RENDER_ONLY=1 skips the checks;
## SHOPFRONT_ONLY=preshow or film draws one; SHOPFRONT_SHOTS=a,b draws those; SHOPFRONT_TAG names the pictures).
## godot --headless --xr-mode off --path app --script res://tests/test_room_shopfront_1906.gd

const RoomRender := preload("res://tests/room_render.gd")
const RoomSound := preload("res://tests/room_sound.gd")
const RoomBake := preload("res://scripts/env/room_bake.gd")
const Edwardian := preload("res://scripts/env/systems/kit/shopfront_edwardian.gd")
const Pictures := preload("res://scripts/env/systems/kit/shopfront_pictures.gd")
const DOC := "res://environments/shopfront_1906.env.json"
const BAKE_ID := "shopfront_render_test"
const ID := "shopfront_1906"
## Before the pass (2026-11-08): 17 draws, 10 168 triangles, no lights, no particles, 8.4 MB.
const BEFORE := {"draws": 17, "triangles": 10168, "texture_mb": 8.4}


func run_tests() -> void:
	test_name = "test_room_shopfront_1906"
	var r := EnvDoc.load_file(DOC)
	check("the document reads (%s)" % [r["errors"]], (r["errors"] as Array).is_empty())
	var doc: Dictionary = r["doc"]
	if doc.is_empty():
		return
	if OS.get_environment("SHOPFRONT_RENDER_ONLY") == "":
		var room := await check_room(ID, doc)
		room.host.auto = false
		_by_part(room)
		_figures(room)
		_hall(room)
		_screen(room)
		await _piano(room)
		_gas(room)
		_booth(room)
		_street(room)
		await _cart(room)
		_clock(room)
		_sound(room)
		await done(room)
		await RoomSound.check_level(self, self, ID, doc)
	await _render(doc)


static func _steps(h: Node, seconds: float, dt := 0.1) -> void:
	var t := 0.0
	while t < seconds:
		h.step(dt)
		t += dt


func _hall_of(room: Node3D) -> Object:
	return room.host.system("hall").hall


## The figures (docs/environments.md, "Room: Shopfront 1906"): a few more draws than before for a room of real detail,
## well inside the headset's budget, no live light, no particles.
func _figures(room: Node3D) -> void:
	var stats := EnvChecks.measure(room)
	print("  figures: %s (before the pass: %s)" % [stats, BEFORE])
	check("the figures as documented: 24 to 32 draws, under 60k triangles, no live light, no particles, under 32 MB "
			+ "(%s)" % [stats], int(stats["draws"]) >= 24 and int(stats["draws"]) <= 32
			and int(stats["triangles"]) < 60000 and int(stats["lights"]) == 0 and int(stats["particles"]) == 0
			and float(stats["texture_mb"]) < 32.0)
	for n: String in ["Shell", "Joinery", "Bills", "Fittings", "GasLamps", "GasLampsRight", "PianoKeys",
			"PianoRoll", "CandleWax", "CandleFlames", "BoothPorts", "Window", "Lettering", "Street", "StreetLamp",
			"StreetLamps", "Cart", "Seats", "ClockHands", "LecternLamp"]:
		check("the room has its %s" % n, room.find_child(n, true, false) != null)


## The hall: the Edwardian style; the pressed tin is the hall's own maps (a plate of the ceiling, the walls' lattice);
## the bills are the atlas's cells; the booth's kit piece gone (the hall draws its own booth).
func _hall(room: Node3D) -> void:
	var hall: Node = room.host.system("hall")
	check("the Edwardian style", str(hall.params["style"]) == "edwardian")
	var shell := room.find_child("Shell", true, false) as MeshInstance3D
	var ceiling: ShaderMaterial = null
	var walls: ShaderMaterial = null
	for k in shell.mesh.get_surface_count():
		var m := shell.mesh.surface_get_material(k) as ShaderMaterial
		if m != null and m.get_shader_parameter("albedo_map") == Pictures.maps("ceiling")["albedo"]:
			ceiling = m
		if m != null and m.get_shader_parameter("albedo_map") == Pictures.maps("wall")["albedo"]:
			walls = m
	check("pressed tin: the ceiling's plates and the walls' lattice, each its own maps", ceiling != null
			and walls != null and is_equal_approx(float(ceiling.get_shader_parameter("tiling")), Edwardian.PLATE)
			and ceiling.get_shader_parameter("normal_map") == Pictures.maps("ceiling")["normal"])
	var bills := room.find_child("Bills", true, false) as MeshInstance3D
	var uvs: PackedVector2Array = bills.mesh.surface_get_arrays(0)[Mesh.ARRAY_TEX_UV]
	var inside := true
	for uv: Vector2 in uvs:
		inside = inside and uv.x >= 0.0 and uv.x <= 1.0 and uv.y >= 0.0 and uv.y <= 1.0
	check("%d bills, boards and the clock's face on the atlas's cells" % (uvs.size() / 4), uvs.size() / 4 >= 10
			and inside)
	check("no kit: the hall draws its own booth", room.host.system_of_kind("kit") == null)
	# Physical sense: everything of the hall inside its walls, nothing under the floor.
	var box := AABB(Vector3(-2.81, -0.01, -7.51), Vector3(5.62, 4.22, 14.02))
	var out := 0
	for n: String in ["Shell", "Joinery", "Bills", "Fittings"]:
		var mi := room.find_child(n, true, false) as MeshInstance3D
		for k in mi.mesh.get_surface_count():
			for v: Vector3 in mi.mesh.surface_get_arrays(k)[Mesh.ARRAY_VERTEX]:
				if not box.has_point(v):
					out += 1
	check("the hall's parts within its walls, floor and ceiling (%d outside)" % out, out == 0)


## The screen: the gilt frame round the sheet's margin; nothing of the hall in front of the picture between it and the
## front row (the piano and the lectern stand beside it); the screen where it was tuned.
func _screen(room: Node3D) -> void:
	var doc: Dictionary = room.doc
	var c: Array = doc["screen"]["center"]
	var size: Array = doc["screen"]["size"]
	check("the screen as tuned on the Frame: 4.4 x 2.475 m, its middle 2.36 m up, 7.44 m off", float(size[0]) == 4.4
			and float(size[1]) == 2.475 and float(c[2]) == -7.44 and is_equal_approx(float(c[1]), 2.3575))
	var hw := float(size[0]) * 0.5
	var bottom := float(c[1]) - float(size[1]) * 0.5
	var top := float(c[1]) + float(size[1]) * 0.5
	var clear := true
	for n: String in ["Shell", "Joinery", "Bills", "Fittings", "PianoRoll", "CandleFlames", "LecternLamp"]:
		var mi := room.find_child(n, true, false) as MeshInstance3D
		for k in mi.mesh.get_surface_count():
			for v: Vector3 in mi.mesh.surface_get_arrays(k)[Mesh.ARRAY_VERTEX]:
				if absf(v.x) < hw - 0.02 and v.y > bottom + 0.02 and v.y < top - 0.02 and v.z > float(c[2]) + 0.005 \
						and v.z < -4.8:
					clear = false
	check("nothing of the hall in front of the picture", clear)


## The player piano: by the stage's left against the wall, clear of the front row; its keys go down as it plays and
## its roll turns, both still when it rests.
func _piano(room: Node3D) -> void:
	var h: Node = room.host
	var hall := _hall_of(room)
	var seats: Array[Transform3D] = room.room_seat_transforms()
	var front_z := INF
	for t: Transform3D in seats:
		front_z = minf(front_z, t.origin.z)
	var front_left := Vector3(INF, 0, 0)
	for t: Transform3D in seats:
		if absf(t.origin.z - front_z) < 0.01 and t.origin.x < front_left.x:
			front_left = t.origin
	var keys_front := -2.8 + 0.035 + Edwardian.PIANO_DEPTH + Edwardian.KEY_OUT
	check("the piano against the left wall by the stage (to %.2f m across), clear of the front row's first chair (%.2f m)"
			% [keys_front, front_left.x - 0.22 - keys_front], keys_front < front_left.x - 0.22 - 0.05
			and Edwardian.PIANO_Z.x >= -7.5 + 1.4 - 0.05)
	var piano: Node = h.system("piano")
	# Its notes are made on a worker thread: wait for them, as the room does.
	piano.finish_loading()
	await process_frame
	h.timeline.state = ""
	h.snapshot_override = {"open": false}
	_steps(h, 3.0)
	var still := Edwardian.roll_turned(hall)
	_steps(h, 2.0)
	check("in the pre-show the piano rests: no key down, the roll still (%d, %.3f to %.3f)" % [
			Edwardian.keys_down(hall), still, Edwardian.roll_turned(hall)], Edwardian.keys_down(hall) == 0
			and is_equal_approx(still, Edwardian.roll_turned(hall)))
	h.snapshot_override = {"open": true, "playing": true, "position": 0.1, "duration": 6000.0}
	var most := 0
	var seen := {}
	var t := 0.0
	while t < 12.0:
		h.step(0.05)
		t += 0.05
		most = maxi(most, Edwardian.keys_down(hall))
		for m: int in piano.held_notes():
			seen[m] = true
	var turned := Edwardian.roll_turned(hall) - still
	check("it plays: its keys go down with its notes (up to %d at once, %d notes), the roll turns (%.3f)" % [most,
			seen.size(), turned], most >= 2 and most <= 12 and seen.size() >= 6 and turned > 0.05)
	# Slow and small: a key tips 3 degrees; the roll moves 3.5 cm a second.
	check("the roll at a walking pace of paper (3.5 cm/s), the keys tipping a little", turned * 1.16 / 12.0 < 0.05)
	h.snapshot_override = {"open": false}
	_steps(h, 8.0)


## The gas: six brackets and two pendants, their light in the bake only (hidden), their stand-ins before it; turned low
## in the film (the globes still glowing, a warmer colour), up again after; the flicker slow.
func _gas(room: Node3D) -> void:
	var h: Node = room.host
	var light: Node = h.system("light")
	var bake := room.find_children("Gas*", "OmniLight3D", true, false) + room.find_children("Pendant*",
			"OmniLight3D", true, false)
	var hidden := true
	for l: Node in bake:
		hidden = hidden and not (l as Light3D).visible
	check("six gas brackets and two pendants light the bake, hidden (%d); %d stand-ins before it" % [bake.size(),
			light.lamp_count()], bake.size() == 8 and hidden and light.lamp_count() == 8)
	h.set_setting("ritual", true)
	h.timeline.state = ""
	h.snapshot_override = {"open": false}
	var globes := (room.find_child("GasLamps", true, false) as MeshInstance3D).mesh.surface_get_material(0)
	_steps(h, 6.0)
	var up := float(globes.get_shader_parameter("energy"))
	h.snapshot_override = {"open": true, "playing": true, "position": 0.1, "duration": 6000.0}
	_steps(h, 14.0)
	var low := float(globes.get_shader_parameter("energy"))
	var colour: Color = globes.get_shader_parameter("colour")
	check("the gas turned low in the film (%.2f of %.2f), still glowing, warmer (%s)" % [low, up, colour],
			low < up * 0.2 and low > 0.05 and colour.b < colour.r * 0.45)
	h.snapshot_override = {"open": false}
	_steps(h, 8.0)
	var again := float(globes.get_shader_parameter("energy"))
	check("and up again in the pre-show (%.2f)" % again, again > up * 0.8)


## The booth: the beam's lens in its port (the screen_frame's lens, the atmosphere's haze from it), the projector's
## clatter from inside it, its port's glow.
func _booth(room: Node3D) -> void:
	var hall := _hall_of(room)
	var lens: Array = room.host.system("screen_frame").params["lens"]
	var at := Edwardian.lens(hall)
	check("the beam's lens in the booth's port (%s, %s)" % [at, lens], at.distance_to(Vector3(float(lens[0]),
			float(lens[1]), float(lens[2]))) < 0.05)
	var projector: Node = room.host.system("projector")
	var p: Array = projector.params["at"]
	check("the projector clatters from inside the booth", Vector3(float(p[0]), float(p[1]), float(p[2])).distance_to(
			at) < 0.6 and float(p[1]) > Edwardian.PLATFORM_Y)
	var air: Node = room.host.system("atmosphere")
	check("a dusty beam", float(air.params["beam_dust"]) >= 0.5 and float(air.params["beam_haze"]) > 0.0)


## The street: outside the glass (beyond the front wall), dimmer in the film (the ritual's street_glow).
func _street(room: Node3D) -> void:
	var h: Node = room.host
	var hall := _hall_of(room)
	var front := 6.5
	var outside := true
	for n: String in ["Street", "StreetLamp", "StreetLamps"]:
		var mi := room.find_child(n, true, false) as MeshInstance3D
		for v: Vector3 in mi.mesh.get_faces():
			outside = outside and v.z >= front - 0.001
	check("the street, its lamp and the shops opposite outside the glass", outside)
	h.timeline.state = ""
	h.snapshot_override = {"open": false}
	_steps(h, 6.0)
	var bright: float = (hall.street_mat as StandardMaterial3D).albedo_color.r
	h.snapshot_override = {"open": true, "playing": true, "position": 0.1, "duration": 6000.0}
	_steps(h, 14.0)
	var dim: float = (hall.street_mat as StandardMaterial3D).albedo_color.r
	check("the street dimmer in the film (%.2f to %.2f)" % [bright, dim], dim < bright * 0.7 and dim > 0.2)
	h.snapshot_override = {"open": false}
	_steps(h, 8.0)


## The cart: now and then before the film (the cue's chance and cooldown), never in the film; it passes outside the
## glass from left to right as the room sees it (+x to -x), its hooves' sound going the same way; its legs swing and its
## wheels turn slowly; it is gone at the end.
func _cart(room: Node3D) -> void:
	var h: Node = room.host
	var hall := _hall_of(room)
	var cue := {}
	for c: Dictionary in room.doc["cues"]:
		if c["name"] == "cart":
			cue = c
	check("the cart's cue: now and then, before the film only (%s)" % [cue], not cue.is_empty()
			and float(cue["chance"]) <= 0.6 and float(cue["cooldown"]) >= 60.0
			and not ("playing" in (cue["states"] as Array)) and not ("starting" in (cue["states"] as Array)))
	h.timeline.state = ""
	h.snapshot_override = {"open": false}
	_steps(h, 1.0)
	var hooves: Node = h.system("hooves")
	hooves.finish_loading()
	await process_frame
	var plays: int = hooves.plays
	# The cue as the timeline runs it (its cooldown then holds it off while the cart passes).
	h.timeline.run_cue("cart")
	h.step(0.05)
	var xs: Array[float] = []
	var swing := 0.0
	var outside := true
	var last := 0.0
	while Edwardian.cart_passing(hall):
		h.step(0.1)
		var at := Edwardian.cart_position(hall)
		xs.append(at.x)
		outside = outside and at.z > 6.5 + 4.0
		var a: float = hall.cart_leg_angle
		if xs.size() > 1:
			swing = maxf(swing, absf(a - last) / 0.1)
		last = a
		if xs.size() > 400:
			break
	var a0: Array = hooves.params["at"]
	var a1: Array = hooves.params["to"]
	check("the cart passes outside the glass, left to right as the room sees it, in %.1f s (%.1f to %.1f m)" % [
			xs.size() * 0.1, xs[0] if not xs.is_empty() else 0.0, xs[-1] if not xs.is_empty() else 0.0],
			xs.size() > 100 and xs.size() < 200 and outside and xs[0] > xs[-1] and xs[0] > 8.0 and xs[-1] < -8.0)
	check("its hooves go the same way (%s to %s), played once (%d)" % [a0, a1, hooves.plays - plays],
			float(a0[0]) > float(a1[0]) and hooves.plays - plays == 1)
	check("its legs swing slowly (%.2f rad/s at most) and it is gone at the end" % swing, swing < 1.5
			and not Edwardian.cart_passing(hall) and not hall.cart.visible)


## The clock keeps the viewer's own time.
func _clock(room: Node3D) -> void:
	var hall: Object = _hall_of(room)
	Edwardian.set_clock(hall, 3.0, 0.0)
	var hour: float = hall.clock_angles.x
	var minute: float = hall.clock_angles.y
	check("the clock's hands at three o'clock (%.2f, %.2f)" % [hour, minute], absf(hour + PI * 0.5) < 0.01
			and absf(minute) < 0.01)


## The sound: the projector's clatter, the gas's hiss, the hooves now and then; the shopfront's acoustics.
func _sound(room: Node3D) -> void:
	RoomSound.check_beds(self, ID, room, {"projector": "projector", "gas": "gas_hiss", "hooves": "hooves"},
			"shopfront")


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
		elif g is GPUParticles3D:
			stats = {"draws": 1, "triangles": 0}
		if not stats.is_empty():
			var owner_name := str(g.get_parent().name) if g.get_parent() != room else ""
			rows.append([("%s/%s" % [owner_name, g.name]) if owner_name != "" else str(g.name), stats["draws"],
					stats["triangles"]])
	rows.sort_custom(func(a: Array, b: Array) -> bool: return int(a[2]) > int(b[2]))
	for row: Array in rows:
		print("  part %-30s %2d draws %7d triangles" % row)


func _render(doc: Dictionary) -> void:
	if not RoomRender.has_renderer():
		print("SKIP render (headless)")
		return
	var sc: Array = doc["screen"]["center"]
	var screen := Vector3(float(sc[0]), float(sc[1]), float(sc[2]))
	var baked := OS.get_environment("SHOPFRONT_BAKE") != "" and RoomBake.can_bake()
	var only := OS.get_environment("SHOPFRONT_ONLY")
	var tag := OS.get_environment("SHOPFRONT_TAG")
	for phase: String in ["preshow", "film"]:
		if only != "" and only != phase:
			continue
		RoomRender.set_light(screen, 0.05 if phase == "preshow" else 0.015)
		# A film of a typical brightness (the bias light's reference, sRGB about 0.4), warm on the left, cool on the
		# right: the stand-in sunset is twice as bright and would light this cream room like a lamp.
		var thumb := Image.create_empty(4, 2, false, Image.FORMAT_RGBA8)
		for x in 4:
			for y in 2:
				thumb.set_pixel(x, y, Color(0.52, 0.42, 0.34).lerp(Color(0.34, 0.4, 0.5), x / 3.0))
		RenderingServer.global_shader_parameter_set("screen_thumb", ImageTexture.create_from_image(thumb))
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
			# Before the film the sheet is blank: no picture lights the room.
			RenderingServer.global_shader_parameter_set("screen_glow", 0.0)
			for n: Node in (vc[2] as Node).get_children():
				if n is MeshInstance3D and (n as MeshInstance3D).material_override is StandardMaterial3D \
						and (n as MeshInstance3D).mesh is QuadMesh:
					var m := (n as MeshInstance3D).material_override as StandardMaterial3D
					m.albedo_texture = null
					m.albedo_color = Color(0.05, 0.05, 0.048)
			host.snapshot_override = {"open": false}
			host.signals.fake("film.brightness", 0.0)
		else:
			host.snapshot_override = {"open": true, "playing": true, "position": 0.5, "duration": 7200.0}
			host.signals.fake("film.brightness", 0.7)
			host.signals.fake("film.colour", Color(0.8, 0.8, 0.82))
			host.signals.fake("playback.playing", 1.0)
		for i in 160:
			host.step(0.25)
		var globes := ((vc[2] as Node).find_child("GasLamps", true, false) as MeshInstance3D).mesh.surface_get_material(0)
		print("  render: %s, the house lamps %.2f, the globes %.2f %s (glow %s by %s; fired %s)" % [phase,
				float(host.param("light.house_lamps")), float(globes.get_shader_parameter("energy")),
				globes.get_shader_parameter("colour"), host.param("light.glow_colour"), host.param("light.glow_mix"),
				host.timeline.fired])
		var eye := Vector3(0, 1.2, 0)
		var p := "shopfront_%s%s%s_" % [tag, "baked_" if baked else "", phase]
		var side := Vector3(-1.8, 0, 1.0)
		var best := Vector3(999, 0, 0)
		for t: Transform3D in (vc[2] as Node).call("room_seat_transforms"):
			if t.origin.distance_to(side) < best.distance_to(side):
				best = t.origin
		# [name, from, towards, field of view]
		var shots := [
			["seat", eye, screen, 90.0], ["left", eye, eye + Vector3(-1.0, 0.1, -0.5), 90.0],
			["right", eye, eye + Vector3(1.0, 0.1, -0.5), 90.0], ["up", eye, eye + Vector3(0.0, 1.0, -0.3), 90.0],
			["back", eye, eye + Vector3(0.0, 0.1, 1.0), 90.0], ["back_up", eye, eye + Vector3(0.0, 0.6, 1.0), 90.0],
			["side_seat", best + Vector3(0, 1.2, 0), screen, 90.0],
			["front_row", Vector3(0.0, 1.2, -4.75), screen, 90.0],
			["piano", eye, Vector3(-2.4, 1.2, -6.6), 50.0], ["wall_close", eye, Vector3(-2.8, 2.3, -2.0), 50.0],
			["ceiling", eye, Vector3(0.0, 4.2, -2.5), 50.0], ["window", eye, Vector3(0.5, 1.6, 6.5), 50.0],
			["booth", eye, Vector3(-1.9, 3.0, 5.5), 50.0],
			["stage", eye, Vector3(0.0, 0.9, -6.6), 50.0],
			["piano_close", Vector3(-0.9, 1.25, -3.6), Vector3(-2.4, 0.95, -5.5), 50.0],
			["keys_close", Vector3(-1.5, 1.3, -5.3), Vector3(-2.2, 0.75, -5.5), 50.0],
			["booth_close", Vector3(0.4, 1.5, 2.6), Vector3(-1.6, 2.6, 5.6), 50.0],
			["window_close", Vector3(0.8, 1.3, 3.2), Vector3(0.6, 1.6, 6.5), 50.0],
			["lectern_close", Vector3(1.0, 1.3, -4.0), Vector3(2.5, 1.5, -6.6), 50.0],
			["lamp_close", Vector3(-1.5, 1.4, 0.5), Vector3(-2.8, 2.2, -0.5), 50.0],
			["door_close", Vector3(-0.6, 1.4, 3.0), Vector3(-2.2, 1.4, 6.5), 50.0],
		]
		var wanted := OS.get_environment("SHOPFRONT_SHOTS").split(",", false)
		for s: Array in shots:
			if not wanted.is_empty() and not (str(s[0]) in wanted):
				continue
			(vc[1] as Camera3D).fov = float(s[3])
			await RoomRender.shot(self, vc, s[1], s[2], p + str(s[0]))
		if phase == "preshow" and (wanted.is_empty() or "window_cart" in wanted):
			host.do_action("hall.cart", {"seconds": 16.0})
			for i in 30:
				host.step(0.25)
			var cart: Node3D = (vc[2] as Node).find_child("Cart", true, false)
			print("  render: the cart %s at %s" % [cart.visible if cart else "none", cart.position if cart else ""])
			(vc[1] as Camera3D).fov = 50.0
			await RoomRender.shot(self, vc, Vector3(0.8, 1.3, 3.2), Vector3(0.6, 1.6, 6.5), p + "window_cart")
		(vc[1] as Camera3D).fov = 90.0
		await RoomRender.close(self, vc)
