extends "res://tests/env_builder_harness.gd"

## Flagship (app/environments/flagship.env.json; docs/environments.md, "Room: Flagship"): the finest modern hall in a
## capital city, the user's reference room for watching. Built headless from its document and checked as every shipped
## room is (schema, budget, sight lines from every seat, comfort, licences, names, no people); then what makes it this
## room: its figures (no more triangles than before the pass, no live light, no particles), the hall over the
## auditorium (the builder's walls, ceiling, drapes and handrails given way to the kit's), the folded walls washed
## from the light slot (bright low, in the folds, dark high), the wash and the light lines following the house lamps
## (out in the film), the ceiling's baffles and the starlight (static; the setting; never brighter in the film than it
## should be, never jumping), the velvet masking on the picture's curve with nothing in front of the picture, the
## recliners (their triangles, the headrest behind the eyes, the back row clear of the rear wall), the fixed armrests
## with cupholders and seat numbers, the lit row letters, the step nosings and the balustrade, the light in the bake
## only, the ritual (the lamps out, the steps at a whisper, the curtains), and the sound (silent but for the film; the
## dry acoustics; the room's level: tests/room_sound.gd).
## Under lavapipe it draws the room (FLAGSHIP_BAKE=1 bakes it first; FLAGSHIP_RENDER_ONLY=1 skips the checks;
## FLAGSHIP_ONLY=preshow or film draws one; FLAGSHIP_TAG names the pictures).
## godot --headless --xr-mode off --path app --script res://tests/test_room_flagship.gd

const RoomRender := preload("res://tests/room_render.gd")
const RoomSound := preload("res://tests/room_sound.gd")
const RoomBake := preload("res://scripts/env/room_bake.gd")
const CurvedScreen := preload("res://scripts/play/curved_screen.gd")
const Flagship := preload("res://scripts/env/systems/kit/flagship.gd")
const Auditorium := preload("res://scripts/env/systems/auditorium.gd")
const Seats := preload("res://scripts/env/systems/seats.gd")
const DOC := "res://environments/flagship.env.json"
const BAKE_ID := "flagship_render_test"
const ID := "flagship"
## Before the pass (2026-11-08): 17 draws, 228 806 triangles, 6.0 MB.
const BEFORE_TRIANGLES := 228806


func run_tests() -> void:
	test_name = "test_room_flagship"
	var r := EnvDoc.load_file(DOC)
	check("the document reads (%s)" % [r["errors"]], (r["errors"] as Array).is_empty())
	var doc: Dictionary = r["doc"]
	if doc.is_empty():
		return
	if OS.get_environment("FLAGSHIP_RENDER_ONLY") == "":
		var room := await check_room(ID, doc)
		room.host.auto = false
		_by_part(room)
		_figures(room)
		_hall(room)
		_walls(room)
		_wash(room)
		_ceiling(room)
		_starlight(room)
		_screen(room)
		_seats(room)
		_rows(room)
		_lights(room)
		_ritual(room)
		_sound(room)
		await done(room)
		await RoomSound.check_level(self, self, ID, doc, true)
	await _render(doc)


static func _steps(h: Node, seconds: float, dt := 0.1) -> void:
	var t := 0.0
	while t < seconds:
		h.step(dt)
		t += dt


func _kit(room: Node3D) -> Node:
	return room.host.system("fittings")


func _hall_of(room: Node3D) -> Object:
	for o: Object in _kit(room)._ctx.halls:
		if o is Flagship.Hall:
			return o
	return null


## The figures (docs/environments.md, "Room: Flagship"): no more triangles than before the pass, well inside the
## room set's own budget (32 draws), no live light, no particles.
func _figures(room: Node3D) -> void:
	var stats := EnvChecks.measure(room)
	print("  figures: %s" % [stats])
	check("the figures as documented: 24 to 30 draws, no more triangles than before (%d), no live light, no "
			% BEFORE_TRIANGLES + "particles, under 16 MB (%s)" % [stats], int(stats["draws"]) >= 24
			and int(stats["draws"]) <= 30 and int(stats["triangles"]) <= BEFORE_TRIANGLES
			and int(stats["lights"]) == 0 and int(stats["particles"]) == 0 and float(stats["texture_mb"]) < 16.0)
	for n: String in ["PieceStatic", "PieceSoft", "PieceLamps", "Starlight", "SeatNumbers", "RowLetters", "Balustrade",
			"Seats", "StepLights", "BoothWindow", "ScreenBorder"]:
		check("the room has its %s" % n, room.find_child(n, true, false) != null)


## The hall over the auditorium: the builder's walls, ceiling, drapes, cans and handrails give way to the kit's.
func _hall(room: Node3D) -> void:
	var hall: Node = room.host.system("hall")
	var kit := _kit(room)
	check("the kit draws without a problem (%s)" % [kit.problems()], kit.problems().is_empty())
	var gone := true
	for n: String in ["Walls", "Ceiling", "Curtains", "Brass", "WallPanels"]:
		gone = gone and room.find_child(n, true, false) == null
	var cans := room.find_child("HouseLamps", true, false) as MeshInstance3D
	check("the builder gives way: no walls, ceiling, drapes, panels, cans or handrails of its own", gone
			and (cans == null or cans.mesh.get_surface_count() == 0) and not bool(hall.params["side_walls"])
			and str(hall.params["proscenium"]) == "none")
	check("clean air: no projector's beam over the seats", not bool(room.host.system("screen_frame").params["beam"])
			and room.find_child("Beam", true, false) == null)


## The surfaces of one material in a mesh: [verts, colours] of every surface whose material is m.
static func _surfaces_of(mi: MeshInstance3D, m: Material) -> Array:
	var verts := PackedVector3Array()
	var cols := PackedColorArray()
	for k in mi.mesh.get_surface_count():
		if mi.mesh.surface_get_material(k) == m:
			var arr := mi.mesh.surface_get_arrays(k)
			verts.append_array(arr[Mesh.ARRAY_VERTEX])
			cols.append_array(arr[Mesh.ARRAY_COLOR])
	return [verts, cols]


## The folded walls: the panels stand out of the wall in a sawtooth, their light brightest low and in the folds,
## dark at the top; their returns face the screen.
func _walls(room: Node3D) -> void:
	var hall: Node = room.host.system("hall")
	var l := Auditorium.layout(hall.params)
	var kit := _kit(room)
	var fabric: Material = kit._ctx.tinted("fabric")
	var ps := room.find_child("PieceStatic", true, false) as MeshInstance3D
	var vc: Array = _surfaces_of(ps, fabric)
	var low := 0.0
	var low_n := 0
	var high := 0.0
	var high_n := 0
	var out := 0.0
	for i in (vc[0] as PackedVector3Array).size():
		var p: Vector3 = vc[0][i]
		if absf(p.x) < l.hi.x - Flagship.FOLD_DEPTH - 0.01 or p.z < -10.0 or p.z > 6.0:
			continue
		out = maxf(out, l.hi.x - absf(p.x))
		var base := Flagship.nose_y(l, p.z) + Flagship.DADO
		if p.y < base + 0.5 and p.y > base - 0.05:
			low += (vc[1][i] as Color).a
			low_n += 1
		elif p.y > Flagship.PANEL_TOP - 0.05 and p.y < Flagship.PANEL_TOP + 0.05:
			high += (vc[1][i] as Color).a
			high_n += 1
	low /= maxf(low_n, 1)
	high /= maxf(high_n, 1)
	check("the folds stand out of the walls (%.2f m) and the slot washes them: bright low (%.2f), dark high (%.2f)"
			% [out, low, high], absf(out - Flagship.FOLD_DEPTH) < 0.01 and low > 0.4 and high < 0.15)


## The wash and the light lines follow the house lamps: amber before the film, out with the lamps.
func _wash(room: Node3D) -> void:
	var h: Node = room.host
	var kit := _kit(room)
	var fabric: ShaderMaterial = kit._ctx.tinted("fabric")
	var light: Node = h.system("light")
	h.fade("light.house_lamps", 1.0, 0.0)
	h.step(0.1)
	var on: Vector3 = fabric.get_shader_parameter("vertex_light")
	var lines_on: float = light.group_energy("house")
	h.fade("light.house_lamps", 0.0, 0.0)
	h.step(0.1)
	var off: Vector3 = fabric.get_shader_parameter("vertex_light")
	check("the wash is amber with the lamps up (%s) and out with them down (%s); the light lines too (%.2f, %.2f)" % [
			on, off, lines_on, light.group_energy("house")], on.x > on.z * 1.5 and on.x > 1.0 and off.length() < 0.001
			and lines_on > 0.5 and light.group_energy("house") < 0.001)
	h.fade("light.house_lamps", 1.0, 0.0)
	h.step(0.1)


## The ceiling: the baffles run the hall's length clear of the walls' bands; the stars are between them.
func _ceiling(room: Node3D) -> void:
	var hall: Node = room.host.system("hall")
	var l := Auditorium.layout(hall.params)
	var star := room.find_child("Starlight", true, false) as MeshInstance3D
	var verts: PackedVector3Array = star.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var between := true
	var x0 := -floor(Flagship.BAFFLE_X * 2.0 / Flagship.BAFFLE_PITCH) * Flagship.BAFFLE_PITCH * 0.5
	for i in range(0, verts.size(), 3):
		var g := fposmod(verts[i].x - x0, Flagship.BAFFLE_PITCH)
		between = between and g > Flagship.BAFFLE_W and g < Flagship.BAFFLE_PITCH - Flagship.BAFFLE_W \
				and absf(verts[i].y - l.hi.y) < 0.01
	check("%d stars, each between the baffles on the ceiling" % (verts.size() / 12), verts.size() / 12
			== Flagship.STARS and between)


## The starlight: off, before the film only (the default), or always (faint in the film); it eases, never jumps.
func _starlight(room: Node3D) -> void:
	var h: Node = room.host
	var hall := _hall_of(room)
	check("the starlight before the film by default (%s)" % [h.setting("starlight")], str(h.setting("starlight"))
			== "preshow")
	var want := {"off": [0.0, 0.0], "preshow": [1.0, 0.0], "always": [1.0, 0.18]}
	for v: String in want:
		h.set_setting("starlight", v)
		h.fade("light.house_lamps", 1.0, 0.0)
		_steps(h, 2.0)
		var up: float = hall.starlight_level()
		h.fade("light.house_lamps", 0.0, 0.0)
		h.step(0.1)
		var eased: float = hall.starlight_level()
		_steps(h, 2.0)
		var film: float = hall.starlight_level()
		check("Starlight %s: %.2f before the film, %.2f in it, easing (%.2f a tenth of a second after)" % [v, up, film,
				eased], absf(up - want[v][0]) < 0.01 and absf(film - want[v][1]) < 0.01
				and (want[v][0] == 0.0 or eased > film + 0.5))
	h.set_setting("starlight", "preshow")
	h.fade("light.house_lamps", 1.0, 0.0)
	_steps(h, 2.0)


## The screen: the velvet masking follows the picture's curve; nothing of the hall stands in front of the picture.
func _screen(room: Node3D) -> void:
	var doc: Dictionary = room.doc
	var kit := _kit(room)
	var a := Flagship.arc(kit._ctx)
	check("the arc: the document's curve over the seat's distance (%.1f m)" % float(a["r"]),
			absf(float(a["r"]) - 18.2 / 0.3) < 0.01)
	var ps := room.find_child("PieceStatic", true, false) as MeshInstance3D
	var mask: Array = _surfaces_of(ps, kit._ctx.mat("drapes"))
	var on_arc := (mask[0] as PackedVector3Array).size() > 0
	var axis := Vector2(0.0, float(a["cz"]))
	for p: Vector3 in mask[0]:
		on_arc = on_arc and absf(Vector2(p.x, p.z).distance_to(axis) - (float(a["r"]) + 0.08)) < 0.005
	check("the masking on the picture's curve, just behind it", on_arc)
	var clear := true
	var half := float(a["half"]) - 0.05
	for n: String in ["PieceStatic", "PieceSoft"]:
		var mi := room.find_child(n, true, false) as MeshInstance3D
		for k in mi.mesh.get_surface_count():
			for p: Vector3 in mi.mesh.surface_get_arrays(k)[Mesh.ARRAY_VERTEX]:
				var ph := asin(clampf(p.x / float(a["r"]), -1.0, 1.0)) * float(a["r"])
				if absf(ph) < half and p.y > float(a["bottom"]) + 0.05 and p.y < float(a["top"]) - 0.05 \
						and p.z < -12.0 and Vector2(p.x, p.z).distance_to(axis) < float(a["r"]) - 0.01:
					clear = false
	check("nothing of the hall in front of the picture", clear)
	var size: Array = doc["screen"]["size"]
	check("the screen as tuned on the Frame: 20 x 8.4 m, its middle at the eyes, 18.2 m off, curve 0.3",
			float(size[0]) == 20.0 and float(size[1]) == 8.4 and float(doc["screen"]["center"][1]) == 1.2
			and float(doc["screen"]["center"][2]) == -18.2 and float(doc["screen"]["curve"]) == 0.3)


## The recliners: about as many triangles as the stadium seat less its arms, the headrest behind the eyes, 350 of them
## where they were, the back row clear of the rear wall.
func _seats(room: Node3D) -> void:
	var hall: Node = room.host.system("hall")
	var l := Auditorium.layout(hall.params)
	var mesh: ArrayMesh = Seats.model_mesh("recliner", StandardMaterial3D.new(), StandardMaterial3D.new(), 0.62)
	var tris := EnvChecks._triangles(mesh)
	var back := -INF
	var head := -INF
	for k in mesh.get_surface_count():
		for p: Vector3 in mesh.surface_get_arrays(k)[Mesh.ARRAY_VERTEX]:
			back = maxf(back, p.z)
			if p.y > 1.0:
				head = maxf(head, p.y)
	check("the recliner (%d triangles), its headrest up to %.2f m, its back %.2f m behind the eyes" % [tris, head, back],
			str(hall.params["seat_model"]) == "recliner" and tris < 460 and head > 1.0 and back < 0.46)
	var seats: Array[Transform3D] = room.room_seat_transforms()
	var clear := true
	for t: Transform3D in seats:
		clear = clear and t.origin.z + back < l.hi.z - 0.02
	check("350 seats, the room's own at the origin, the back row clear of the rear wall (%d)" % seats.size(),
			seats.size() == 350 and seats.any(func(s: Transform3D) -> bool: return s.origin.length() < 0.05) and clear)


## The rows: an arm between every two seats and at each row's ends with a cupholder, each seat's number on the arm
## on its left, the row letters A (the front) to N on the end arms, nosings on the aisle steps.
func _rows(room: Node3D) -> void:
	var numbers := room.find_child("SeatNumbers", true, false) as MeshInstance3D
	var letters := room.find_child("RowLetters", true, false) as MeshInstance3D
	var n := EnvChecks._triangles(numbers.mesh) / 2
	var m := EnvChecks._triangles(letters.mesh) / 2
	check("a number for every seat (%d) and a letter at each row's ends (%d), A at the front to %s at the back" % [n, m,
			Flagship.Glyphs.text_of(25 + 13)], n == 350 and m == 28 and Flagship.Glyphs.text_of(25) == "A"
			and Flagship.Glyphs.text_of(24) == "25")
	var hall := _hall_of(room)
	var first: Array = hall.numbers[0]
	check("the numbers on the arms' tops, facing up (%s)" % [first[3]], (first[3] as Vector3).is_equal_approx(Vector3.UP)
			and absf((first[0] as Vector3).y - (Auditorium.layout(room.host.system("hall").params).row_floor(-6)
			+ Flagship.ARM_H)) < 0.01)
	var atlas := Flagship.Glyphs.atlas(true).get_image()
	check("the glyphs drawn (%d x %d)" % [atlas.get_width(), atlas.get_height()], atlas.get_width() == 384
			and atlas.get_height() == 150)


## The light: in the bake only, hidden: the stand-in lamps by the walls, the slots' and coves' glows, the wings' spots.
func _lights(room: Node3D) -> void:
	var lamps := room.find_children("KitLamp*", "OmniLight3D", true, false)
	var glows := room.find_children("KitGlow*", "OmniLight3D", true, false)
	var spots := room.find_children("KitSpot*", "SpotLight3D", true, false)
	var hidden := true
	for l: Node in lamps + glows + spots:
		hidden = hidden and not (l as Light3D).visible
	check("the walls' lamps (%d), the slots' and coves' glows (%d) and the wings' spots (%d) light the bake, hidden" % [
			lamps.size(), glows.size(), spots.size()], lamps.size() == 8 and glows.size() == 13 and spots.size() == 2
			and hidden)


## The ritual: the lamps to 40 %, the curtains, then the lamps out and the steps at a whisper; the wash and the
## stars out with them; all back in the pre-show.
func _ritual(room: Node3D) -> void:
	var h: Node = room.host
	var kit := _kit(room)
	var fabric: ShaderMaterial = kit._ctx.tinted("fabric")
	h.set_setting("ritual", true)
	h.timeline.state = ""
	h.snapshot_override = {"open": true, "playing": false, "position": 0.0, "duration": 6000.0}
	h.step(0.05)
	h.snapshot_override = {"open": true, "playing": true, "position": 0.1, "duration": 6000.0}
	_steps(h, 16.0)
	var wash: Vector3 = fabric.get_shader_parameter("vertex_light")
	check("the ritual: the lamps out (%.2f), the steps at a whisper (%.2f), the wash out (%s), the stars out (%.2f)" % [
			h.param("light.house_lamps"), h.param("light.step_lights"), wash, _hall_of(room).starlight_level()],
			float(h.param("light.house_lamps")) < 0.01 and absf(float(h.param("light.step_lights")) - 0.35) < 0.02
			and wash.length() < 0.001 and _hall_of(room).starlight_level() < 0.01)
	var showing: Node = h.system("showing")
	check("the ritual parts the curtains", showing.log.any(func(a: Array) -> bool: return a[0] == "open_curtains"))
	h.snapshot_override = {"open": false}
	_steps(h, 9.0)
	wash = fabric.get_shader_parameter("vertex_light")
	check("the pre-show again: the lamps (%.2f), the wash (%s) and the stars (%.2f) back" % [h.param("light.house_lamps"),
			wash, _hall_of(room).starlight_level()], float(h.param("light.house_lamps")) > 0.98 and wash.x > 1.0
			and _hall_of(room).starlight_level() > 0.98)


## The sound: silent but for the film by design; the dry modern hall.
func _sound(room: Node3D) -> void:
	RoomSound.check_beds(self, ID, room, {}, "cinema")
	var acoustics: Dictionary = room.host.system_of_kind("sound").values()
	check("drier than a cinema's preset (rt60 %.2f, damping %.2f)" % [acoustics["rt60"], acoustics["damping"]],
			float(acoustics["rt60"]) < 0.7 and float(acoustics["damping"]) > 0.6)


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
	var baked := OS.get_environment("FLAGSHIP_BAKE") != "" and RoomBake.can_bake()
	var only := OS.get_environment("FLAGSHIP_ONLY")
	var tag := OS.get_environment("FLAGSHIP_TAG")
	for phase: String in ["preshow", "film"]:
		if only != "" and only != phase:
			continue
		RoomRender.set_light(screen, 0.05 if phase == "preshow" else 0.015)
		var vc := await RoomRender.open(self, doc)
		var host: Node = (vc[2] as Node).host
		# The picture curved as the app curves it (the document's curve over the seat's distance).
		for n: Node in (vc[2] as Node).get_children():
			if n is MeshInstance3D and (n as MeshInstance3D).mesh is QuadMesh:
				var q := (n as MeshInstance3D).mesh as QuadMesh
				(n as MeshInstance3D).mesh = CurvedScreen.build(q.size, absf(screen.z) / float(doc["screen"]["curve"]))
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
			# Before the film the curtains are closed over the screen: no picture lights the room.
			RenderingServer.global_shader_parameter_set("screen_glow", 0.0)
			for n: Node in (vc[2] as Node).get_children():
				if n is MeshInstance3D and (n as MeshInstance3D).material_override is StandardMaterial3D:
					var m := (n as MeshInstance3D).material_override as StandardMaterial3D
					if m != null:
						m.albedo_texture = null
						m.albedo_color = Color(0.02, 0.02, 0.02)
			host.snapshot_override = {"open": false}
			host.signals.fake("film.brightness", 0.0)
		else:
			host.snapshot_override = {"open": true, "playing": true, "position": 0.5, "duration": 7200.0}
			host.signals.fake("film.brightness", 0.7)
			host.signals.fake("film.colour", Color(0.85, 0.55, 0.35))
			host.signals.fake("playback.playing", 1.0)
		for i in 160:
			host.step(0.25)
		var eye := Vector3(0, 1.2, 0)
		var p := "flagship_%s%s%s_" % [tag, "baked_" if baked else "", phase]
		var img: Image = await RoomRender.shot(self, vc, eye, screen, p + "seat")
		var walls := (RoomRender.mean(img, Rect2(0.02, 0.3, 0.1, 0.3)).get_luminance()
				+ RoomRender.mean(img, Rect2(0.88, 0.3, 0.1, 0.3)).get_luminance()) * 0.5
		var picture := RoomRender.mean(img, Rect2(0.4, 0.42, 0.2, 0.12)).get_luminance()
		print("  render: %s from the seat: the walls %.3f, the picture %.3f" % [phase, walls, picture])
		await RoomRender.shot(self, vc, eye, eye + Vector3(-1.0, 0.1, -0.5), p + "left")
		await RoomRender.shot(self, vc, eye, eye + Vector3(1.0, 0.1, -0.5), p + "right")
		await RoomRender.shot(self, vc, eye, eye + Vector3(0.0, 1.0, -0.3), p + "up")
		await RoomRender.shot(self, vc, eye, eye + Vector3(0.0, 0.1, 1.0), p + "back")
		await RoomRender.shot(self, vc, eye, eye + Vector3(0.0, 0.7, 1.0), p + "back_up")
		await RoomRender.shot(self, vc, eye, eye + Vector3(0.0, -0.45, -1.0), p + "rows")
		var side := Vector3(-6.0, 0, 3.0)
		var best := Vector3(999, 0, 0)
		for t: Transform3D in (vc[2] as Node).call("room_seat_transforms"):
			if t.origin.distance_to(side) < best.distance_to(side):
				best = t.origin
		await RoomRender.shot(self, vc, best + Vector3(0, 1.2, 0), screen, p + "side_seat")
		await RoomRender.shot(self, vc, best + Vector3(0, 1.2, 0), best + Vector3(-1.0, 1.3, -0.3), p + "side_wall")
		var front := Vector3(0.0, -3.85 + 1.2, -8.75)
		await RoomRender.shot(self, vc, front, screen, p + "front_row")
		(vc[1] as Camera3D).fov = 50.0
		await RoomRender.shot(self, vc, eye, Vector3(-9.5, -1.0, -15.5), p + "proscenium_left")
		await RoomRender.shot(self, vc, eye, Vector3(0.0, -3.8, -17.0), p + "stage")
		await RoomRender.shot(self, vc, eye, Vector3(0.0, 9.5, -3.0), p + "ceiling")
		await RoomRender.shot(self, vc, eye, Vector3(0.0, 5.5, 8.0), p + "rear")
		await RoomRender.shot(self, vc, eye, Vector3(-13.0, 2.0, -6.0), p + "wall_close")
		await RoomRender.shot(self, vc, Vector3(-10.6, 0.4, -3.0), Vector3(-9.0, -2.8, -9.0), p + "aisle")
		await RoomRender.shot(self, vc, Vector3(0.0, 1.15, 0.05), Vector3(0.4, 0.45, -0.25), p + "armrest")
		await RoomRender.shot(self, vc, Vector3(-11.0, 3.4, 4.0), Vector3(-9.2, 2.6, 2.0), p + "row_end")
		(vc[1] as Camera3D).fov = 90.0
		await RoomRender.close(self, vc)
