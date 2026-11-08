extends "res://tests/env_builder_harness.gd"

## Palace of Culture 1974 (app/environments/palace_of_culture_1974.env.json; docs/environments.md, "Room: Palace of
## Culture 1974"): the cinema hall of a 1970s civic palace of culture. Built headless from its document and checked as
## every shipped room is (schema, budget, sight lines from every seat, comfort, licences, names, no people); then what
## makes it this room: its figures (draws, triangles, no live light, the snow's particles, textures), the hall over
## the auditorium (board-marked concrete, the builder's own walls and ceiling given way), the two mosaics (their map of
## tesserae, gold among them, the cosmos on the left and the earth on the right, glinting, washed from the cornice,
## taking little of the film's light), the coffered ceiling lit per coffer by its globe, the field of globes (high over
## every sight line, down with the house lamps, never quite black), the opening with snow on its beams and the snow
## falling only under it, the proscenium round the picture, the clock telling the real time, the 1970s seats, the
## light in the bake only, the Snow setting, the ritual (the bells, the curtains, the lamps, the glow on the birches
## going down), the pre-show's ochre curtains, and the sound (the concrete hall, the bells, the wind over the
## opening following the snow, a far train before the film only; the room's level: tests/room_sound.gd).
## Under lavapipe it draws the room (PALACE_BAKE=1 bakes it first; PALACE_RENDER_ONLY=1 skips the checks;
## PALACE_ONLY=preshow or film draws one; PALACE_TAG names the pictures).
## godot --headless --xr-mode off --path app --script res://tests/test_room_palace_of_culture_1974.gd

const RoomRender := preload("res://tests/room_render.gd")
const RoomSound := preload("res://tests/room_sound.gd")
const RoomBake := preload("res://scripts/env/room_bake.gd")
const Palace := preload("res://scripts/env/systems/kit/palace_culture.gd")
const Auditorium := preload("res://scripts/env/systems/auditorium.gd")
const Seats := preload("res://scripts/env/systems/seats.gd")
const Procedural := preload("res://scripts/env/systems/kit/procedural.gd")
const DOC := "res://environments/palace_of_culture_1974.env.json"
const BAKE_ID := "palace_of_culture_1974_render_test"
const ID := "palace_of_culture_1974"


func run_tests() -> void:
	test_name = "test_room_palace_of_culture_1974"
	var r := EnvDoc.load_file(DOC)
	check("the document reads (%s)" % [r["errors"]], (r["errors"] as Array).is_empty())
	var doc: Dictionary = r["doc"]
	if doc.is_empty():
		return
	if OS.get_environment("PALACE_RENDER_ONLY") == "":
		var room := await check_room(ID, doc)
		room.host.auto = false
		_by_part(room)
		_figures(room)
		_hall(room)
		_mosaics(room)
		_ceiling(room)
		_opening(room)
		_proscenium(room)
		_clock(room)
		_seats(room)
		_lights(room)
		_snow_setting(room)
		_ritual(room)
		_sound(room)
		await done(room)
		await RoomSound.check_level(self, self, ID, doc)
	await _render(doc)


static func _steps(h: Node, seconds: float, dt := 0.25) -> void:
	var t := 0.0
	while t < seconds:
		h.step(dt)
		t += dt


## The figures (docs/environments.md, "Room: Palace of Culture 1974"): before the pass 23 draws, 256 688 triangles,
## 1400 particles, 12.4 MB.
func _figures(room: Node3D) -> void:
	var stats := EnvChecks.measure(room)
	print("  figures: %s" % [stats])
	check("the figures as documented: 24 to 34 draws, under 200k triangles, no live light, the snow's particles only, "
			+ "under 20 MB (%s)" % [stats], int(stats["draws"]) >= 24 and int(stats["draws"]) <= 34
			and int(stats["triangles"]) < 200000 and int(stats["lights"]) == 0 and int(stats["particles"]) <= 1500
			and float(stats["texture_mb"]) < 20.0)
	for n: String in ["PieceStatic", "PieceSoft", "PieceCove", "PieceLamps", "PieceClock", "Mosaic", "Seats", "Vista"]:
		check("the room has its %s" % n, room.find_child(n, true, false) != null)


## The hall over the auditorium: the builder's walls, ceiling, panels and sconces give way to the kit's concrete.
func _hall(room: Node3D) -> void:
	var host: Node = room.host
	var hall: Node = host.system("hall")
	var kit: Node = host.system("palace")
	check("the hall's kit draws without a problem (%s)" % [kit.problems()], kit.problems().is_empty())
	check("the builder gives way: no walls, ceiling, panels or sconces of its own (%s)" % [[hall.params["side_walls"],
			hall.params["ceiling_cover"], hall.params["wall_treatment"], hall.params["sconce_joints"]]],
			room.find_child("Walls", true, false) == null and room.find_child("Ceiling", true, false) == null
			and room.find_child("WallPanels", true, false) == null and str(hall.params["wall_treatment"]) == "plain")
	var stone: Dictionary = kit.params["stone"]
	check("the concrete is board-marked (procedural board_concrete over %s)" % stone["library"],
			"board_concrete" in Procedural.PATTERNS and str(stone["library"]).contains("concrete"))
	var maps: Dictionary = Procedural.maps("board_concrete")
	var img: Image = (maps["albedo"] as ImageTexture).get_image()
	# The boards: rows of different tone; the tie holes: dark plugs.
	var tones: Array[float] = []
	for k in 10:
		tones.append(img.get_pixel(40, int((k + 0.5) * img.get_height() / 10.0)).get_luminance())
	var spread: float = tones.max() - tones.min()
	check("the boards each their own tone (spread %.3f)" % spread, spread > 0.02)
	var hole := img.get_pixel(int(img.get_width() / 6.0), int(img.get_height() / 4.0)).get_luminance()
	check("a tie hole where the grid puts one (%.3f under %.3f)" % [hole, tones.min()], hole < tones.min())


## The mosaics: one mesh on the mosaic shader, its map of tesserae (one texel each: the cosmos above, the earth below),
## gold among them, the cosmos on the left wall and the earth on the right, the bed's spill under the concrete's.
func _mosaics(room: Node3D) -> void:
	var mi := room.find_child("Mosaic", true, false) as MeshInstance3D
	if mi == null:
		check("the mosaics", false)
		return
	var m := mi.mesh.surface_get_material(0) as ShaderMaterial
	check("the mosaics on the mosaic shader", m != null and m.shader == Palace.MOSAIC_SHADER)
	var map := m.get_shader_parameter("mosaic_map") as Texture2D
	var w := int(round((Palace.MURAL_TO - Palace.MURAL_FROM) / Palace.TESSERA))
	var h := int(round((Palace.MURAL_TOP - Palace.MURAL_FOOT) / Palace.TESSERA))
	check("one texel a tessera, both murals (%s, %d x %d)" % [map.get_size() if map != null else null, w, h * 2],
			map != null and map.get_width() == w and map.get_height() == h * 2)
	var img := map.get_image()
	var gold := 0
	var glass := 0
	var stone := 0
	for y in range(0, img.get_height(), 3):
		for x in range(0, img.get_width(), 3):
			var a := img.get_pixel(x, y).a
			if a > 0.9:
				gold += 1
			elif a > 0.4:
				glass += 1
			else:
				stone += 1
	check("glass, gold and stone tesserae (%d, %d, %d)" % [glass, gold, stone], gold > 200 and glass > gold
			and stone > 100)
	# The cosmos: night blue above; the earth: a pale dawn sky above its horizon.
	var cosmos_sky := img.get_pixel(w / 2, h / 8)
	var earth_sky := img.get_pixel(w / 10, h + h / 4)
	check("the cosmos's night above, the earth's dawn (%s, %s)" % [cosmos_sky, earth_sky], cosmos_sky.b > cosmos_sky.r
			and cosmos_sky.get_luminance() < 0.3 and earth_sky.get_luminance() > cosmos_sky.get_luminance())
	var arrays := mi.mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var placed := true
	for i in verts.size():
		if (verts[i].x < 0.0 and uvs[i].y > 0.5 + 0.001) or (verts[i].x > 0.0 and uvs[i].y < 0.5 - 0.001):
			placed = false
	check("the cosmos on the left wall, the earth on the right", placed and verts.size() >= 8)
	check("they glint (%.2f) and the cornice washes them (%s)" % [float(m.get_shader_parameter("mosaic_glint")),
			m.get_shader_parameter("mosaic_wash")], float(m.get_shader_parameter("mosaic_glint")) > 0.0
			and (m.get_shader_parameter("mosaic_wash") as Vector4).x > 0.0)
	var walls: ShaderMaterial = null
	var ps := room.find_child("PieceStatic", true, false) as MeshInstance3D
	for k in ps.mesh.get_surface_count():
		var sm := ps.mesh.surface_get_material(k) as ShaderMaterial
		if sm != null and float(sm.get_shader_parameter("tiling")) == 1.5:
			walls = sm
	check("the mosaics take less of the film's light than the concrete (%.2f, %.2f): soft colour, never overlit" % [
			float(m.get_shader_parameter("spill")), float(walls.get_shader_parameter("spill")) if walls != null else -1.0],
			walls != null and float(m.get_shader_parameter("spill")) < float(walls.get_shader_parameter("spill")))
	check("they stand between the proscenium and the opening, over the aisles' heads", Palace.MURAL_FROM > Palace.frame_z(
			_ctx_of(room)) and Palace.MURAL_TO < Palace.OPEN_FROM and Palace.MURAL_FOOT > 0.8)


## A stand-in for the kit's ctx (what Palace.frame_z reads): the room and its document.
func _ctx_of(room: Node3D) -> Object:
	return _Ctx.new(room)


class _Ctx:
	var room: Node3D

	func _init(r: Node3D) -> void:
		room = r


## The ceiling: each coffer lit by its own globe (bright by the high globes, dark between), the globes high over every
## sight line, down with the house lamps but never quite black.
func _ceiling(room: Node3D) -> void:
	var cove := room.find_child("PieceCove", true, false) as MeshInstance3D
	var cols: PackedColorArray = cove.mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR]
	var lit := 0
	var dark := 0
	for c: Color in cols:
		if c.a > 0.35:
			lit += 1
		elif c.a < 0.08:
			dark += 1
	print("  coffers: %d of %d bright, %d dark" % [lit, cols.size(), dark])
	check("the coffers lit in pools: some bright by a globe (%d), much dark between (%d) of %d" % [lit, dark,
			cols.size()], lit > cols.size() / 30 and dark > cols.size() / 4)
	var hall: Node = room.host.system("hall")
	var l := Auditorium.layout(hall.params)
	var pts := Palace.globes(l, Palace.frame_z(_ctx_of(room)))
	var low := INF
	for g in pts:
		low = minf(low, g.y)
	var doc: Dictionary = room.doc
	var top := float(doc["screen"]["center"][1]) + float(doc["screen"]["size"][1]) * 0.5
	check("sixty globes, the lowest at %.2f m, %.1f m over the picture's top" % [low, low - top], pts.size() == 60
			and low - top > 2.0)
	var light: Node = room.host.system("light")
	var lamps := room.find_child("PieceLamps", true, false) as MeshInstance3D
	var gm := lamps.mesh.surface_get_material(0) as ShaderMaterial
	check("the globes glow with the house lamps, round (rim %.1f), never quite out (%.2f of their glow stays)" % [
			float(gm.get_shader_parameter("rim")), 1.0 - float(gm.get_shader_parameter("follows_house"))],
			float(gm.get_shader_parameter("rim")) > 0.5 and float(gm.get_shader_parameter("follows_house")) < 1.0
			and float(gm.get_shader_parameter("follows_house")) > 0.85 and light.group_energy("house") > 0.0)


## The opening: snow falls only under it, behind the default seat; snow lies on its beams (a white cap over the top).
func _opening(room: Node3D) -> void:
	var area: Dictionary = room.host.system("weather").params["areas"][0]
	check("the snow's area under the opening (z %.1f to %.1f in %.1f to %.1f), behind the default seat" % [
			area["min"][2], area["max"][2], Palace.OPEN_FROM, Palace.OPEN_TO], float(area["min"][2]) >= Palace.OPEN_FROM
			and float(area["max"][2]) <= Palace.OPEN_TO and float(area["min"][2]) > 1.0)
	var soft := room.find_child("PieceSoft", true, false) as MeshInstance3D
	var snow_on_beams := 0
	for k in soft.mesh.get_surface_count():
		var verts: PackedVector3Array = soft.mesh.surface_get_arrays(k)[Mesh.ARRAY_VERTEX]
		for v: Vector3 in verts:
			if v.y > 10.05 and v.z > Palace.OPEN_FROM - 0.3 and v.z < Palace.OPEN_TO + 0.3:
				snow_on_beams += 1
	check("snow lies on the opening's beams and edges (%d points over the roof's top)" % snow_on_beams,
			snow_on_beams > 200)
	var vista: Node = room.host.system("vista")
	check("birches in hoar frost round the opening, the hall's glow on them (%.2f, %.2f)" % [float(vista.params["frost"]),
			float(vista.params["room_glow_level"])], float(vista.params["frost"]) > 0.5
			and float(vista.params["room_glow_level"]) > 0.0)


## The proscenium: its opening round the picture with room to spare, its face in front of the screen.
func _proscenium(room: Node3D) -> void:
	var doc: Dictionary = room.doc
	var size: Array = doc["screen"]["size"]
	var fz := Palace.frame_z(_ctx_of(room))
	check("the proscenium's face %.1f m in front of the picture, its opening %.1f m wider each side" % [Palace.FRAME_OUT,
			Palace.OPEN_SIDE], fz > float(doc["screen"]["center"][2]) and Palace.OPEN_SIDE > 0.5
			and float(size[0]) * 0.5 + Palace.OPEN_SIDE < 11.0)
	check("the pre-show's curtains are ochre, as the drapes (%s)" % [room.get("curtain_colour")],
			room.get("curtain_colour") is Color and (room.get("curtain_colour") as Color).r > 0.4
			and (room.get("curtain_colour") as Color).b < 0.2)


## The clock over the booth tells the real time, on its 1970s face.
func _clock(room: Node3D) -> void:
	var kit: Node = room.host.system("palace")
	_steps(room.host, 1.2)
	var hands: Array = kit.clock_hands()
	var t := Time.get_time_dict_from_system()
	var minute := TAU * (float(t["minute"]) + float(t["second"]) / 60.0) / 60.0
	var off := absf(wrapf(float(hands[1]) - minute, -PI, PI)) if hands.size() == 2 else 9.0
	var face := room.find_child("PieceClock", true, false) as MeshInstance3D
	var cm := face.mesh.surface_get_material(0) as ShaderMaterial
	check("the clock's minute hand at the real time (%.3f rad off), the 1970s face" % off, off < 0.05
			and int(cm.get_shader_parameter("style")) == 1)


## The seats: the 1970s civic seat (a moulded oak back), about half the stadium seat's triangles, where they were.
func _seats(room: Node3D) -> void:
	var hall: Node = room.host.system("hall")
	var mesh: ArrayMesh = Seats.model_mesh("civic", StandardMaterial3D.new(), StandardMaterial3D.new(), 0.56)
	var tris := EnvChecks._triangles(mesh)
	check("the civic seat (%d triangles)" % tris, str(hall.params["seat_model"]) == "civic" and tris < 420)
	var seats: Array[Transform3D] = room.room_seat_transforms()
	check("377 seats, the room's own at the origin (%d)" % seats.size(), seats.size() == 377
			and seats.any(func(s: Transform3D) -> bool: return s.origin.length() < 0.05))


## The light: in the bake only (the globes, the lamp lines down the mosaics, the sky through the opening, the
## footlights and the uplights on the proscenium), hidden, never live.
func _lights(room: Node3D) -> void:
	var lamps := room.find_children("KitLamp*", "OmniLight3D", true, false)
	var glows := room.find_children("KitGlow*", "OmniLight3D", true, false)
	var spots := room.find_children("KitSpot*", "SpotLight3D", true, false)
	var hidden := true
	for l: Node in lamps + glows + spots:
		hidden = hidden and not (l as Light3D).visible
	check("the globes (%d + %d), the lamp lines, the sky and the footlights (%d) light the bake, hidden" % [
			lamps.size(), glows.size(), spots.size()], lamps.size() == 8 and glows.size() == 5 and spots.size() == 11
			and hidden)


## The Snow setting: the snowfall, the clouds, the birches' snow and the wind over the opening.
func _snow_setting(room: Node3D) -> void:
	var h: Node = room.host
	var expect := {"none": ["clear", 0.2, 0.8, 0.5], "light": ["light", 0.55, 1.0, 0.8],
			"heavy": ["heavy", 0.85, 1.0, 1.0]}
	for v: String in expect:
		h.set_setting("snow", v)
		h.step(0.1)
		check("Snow %s: the weather %s, clouds %.2f, the birches' snow %.2f, the wind %.2f (%s, %.2f, %.2f, %.2f)" % [v,
				expect[v][0], expect[v][1], expect[v][2], expect[v][3], h.param("weather.mode"), h.param("sky.clouds"),
				h.param("vista.snow"), h.param("wind.level")], str(h.param("weather.mode")) == expect[v][0]
				and absf(float(h.param("sky.clouds")) - float(expect[v][1])) < 0.01
				and absf(float(h.param("vista.snow")) - float(expect[v][2])) < 0.01
				and absf(float(h.param("wind.level")) - float(expect[v][3])) < 0.01)
	h.set_setting("snow", "light")
	h.step(0.1)


## The ritual: the bells once, the curtains, the lamps to a tenth, the steps to half, the glow on the birches down; back
## up in the pre-show. Pre-show off: no bells, the same dimming.
func _ritual(room: Node3D) -> void:
	var h: Node = room.host
	var bells: Node = h.system("bells")
	var rang: int = bells.plays
	h.set_setting("ritual", true)
	h.timeline.state = ""
	h.snapshot_override = {"open": true, "playing": false, "position": 0.0, "duration": 6000.0}
	h.step(0.05)
	h.snapshot_override = {"open": true, "playing": true, "position": 0.1, "duration": 6000.0}
	_steps(h, 16.0, 0.1)
	check("the ritual: the bells once (%d), the lamps to a tenth (%.2f), the steps to half (%.2f), the birches' glow "
			% [bells.plays - rang, h.param("light.house_lamps"), h.param("light.step_lights")]
			+ "down (%.2f)" % h.param("vista.room_glow_level"), bells.plays - rang == 1
			and absf(float(h.param("light.house_lamps")) - 0.1) < 0.02
			and absf(float(h.param("light.step_lights")) - 0.5) < 0.02 and float(h.param("vista.room_glow_level")) < 0.06)
	var showing: Node = h.system("showing")
	check("the ritual parts the curtains", showing.log.any(func(a: Array) -> bool: return a[0] == "open_curtains"))
	h.snapshot_override = {"open": false}
	_steps(h, 9.0, 0.1)
	check("the pre-show again: the lamps (%.2f) and the glow (%.2f) back up" % [h.param("light.house_lamps"),
			h.param("vista.room_glow_level")], float(h.param("light.house_lamps")) > 0.98
			and float(h.param("vista.room_glow_level")) > 0.2)
	h.set_setting("ritual", false)
	rang = bells.plays
	h.snapshot_override = {"open": true, "playing": false, "position": 0.0, "duration": 6000.0}
	h.step(0.05)
	h.snapshot_override = {"open": true, "playing": true, "position": 0.1, "duration": 6000.0}
	_steps(h, 8.0, 0.1)
	check("Pre-show off: no bells (%d), the lamps still down (%.2f)" % [bells.plays - rang,
			h.param("light.house_lamps")], bells.plays == rang and absf(float(h.param("light.house_lamps")) - 0.1) < 0.02)
	h.snapshot_override = {"open": false}
	_steps(h, 9.0, 0.1)
	h.set_setting("ritual", true)


## The sound: the concrete hall's echo, the bells, the wind over the opening, a far train; the train only before the
## film (its cue's states).
func _sound(room: Node3D) -> void:
	RoomSound.check_beds(self, ID, room, {"bells": "three_bells", "wind": "wind", "train": "train"}, "concrete_hall")
	var doc: Dictionary = room.doc
	var cue: Dictionary = {}
	for c: Dictionary in doc["cues"]:
		if c["name"] == "night_train":
			cue = c
	check("the far train only before and after the film, now and then (%s)" % [cue.get("states")], not cue.is_empty()
			and not ("playing" in cue["states"]) and not ("starting" in cue["states"]) and float(cue["cooldown"]) >= 300.0)
	var wind: Node = room.host.system("wind")
	check("the wind over the opening, low in the film (%.0f dB)" % float(wind.params["film_db"]),
			float(wind.params["film_db"]) <= -10.0 and float((wind.params["at"] as Array)[1]) > 9.0)


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
	var baked := OS.get_environment("PALACE_BAKE") != "" and RoomBake.can_bake()
	var only := OS.get_environment("PALACE_ONLY")
	var tag := OS.get_environment("PALACE_TAG")
	for phase: String in ["preshow", "film"]:
		if only != "" and only != phase:
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
			# Before the film the curtains are closed over the screen: no picture lights the room.
			RenderingServer.global_shader_parameter_set("screen_glow", 0.0)
			for n: Node in (vc[2] as Node).get_children():
				if n is MeshInstance3D and (n as MeshInstance3D).mesh is QuadMesh:
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
		var p := "palace_%s%s%s_" % [tag, "baked_" if baked else "", phase]
		var img: Image = await RoomRender.shot(self, vc, eye, screen, p + "seat")
		var walls := (RoomRender.mean(img, Rect2(0.04, 0.3, 0.12, 0.3)).get_luminance()
				+ RoomRender.mean(img, Rect2(0.84, 0.3, 0.12, 0.3)).get_luminance()) * 0.5
		var picture := RoomRender.mean(img, Rect2(0.4, 0.42, 0.2, 0.12)).get_luminance()
		print("  render: %s from the seat: the walls %.3f, the picture %.3f" % [phase, walls, picture])
		await RoomRender.shot(self, vc, eye, eye + Vector3(-1.0, 0.2, -0.3), p + "left")
		await RoomRender.shot(self, vc, eye, eye + Vector3(1.0, 0.2, -0.3), p + "right")
		await RoomRender.shot(self, vc, eye, eye + Vector3(0.0, 1.0, -0.2), p + "up")
		await RoomRender.shot(self, vc, eye, eye + Vector3(0.0, 0.1, 1.0), p + "back")
		await RoomRender.shot(self, vc, eye, eye + Vector3(0.0, 0.8, 1.0), p + "back_up")
		var side := Vector3(-6.0, 0, 3.0)
		var best := Vector3(999, 0, 0)
		for t: Transform3D in (vc[2] as Node).call("room_seat_transforms"):
			if t.origin.distance_to(side) < best.distance_to(side):
				best = t.origin
		await RoomRender.shot(self, vc, best + Vector3(0, 1.2, 0), screen, p + "side_seat")
		await RoomRender.shot(self, vc, best + Vector3(0, 1.2, 0), best + Vector3(-1.0, 1.4, -0.4), p + "side_wall")
		(vc[1] as Camera3D).fov = 50.0
		await RoomRender.shot(self, vc, eye, Vector3(-10.5, 4.0, -6.0), p + "mosaic_left")
		await RoomRender.shot(self, vc, eye, Vector3(0.0, 4.0, -15.0), p + "proscenium")
		await RoomRender.shot(self, vc, eye, Vector3(0.0, 9.5, -5.0), p + "ceiling")
		await RoomRender.shot(self, vc, eye, Vector3(0.0, 4.0, 6.6), p + "rear")
		await RoomRender.shot(self, vc, Vector3(-3.0, 2.4, 4.8), Vector3(2.0, 10.0, 3.0), p + "opening")
		await RoomRender.shot(self, vc, Vector3(9.0, 1.2, -9.0), Vector3(10.6, 4.5, -5.0), p + "mosaic_close")
		await RoomRender.shot(self, vc, Vector3(-6.0, 13.5, -1.0), Vector3(0.0, 10.0, 4.0), p + "roof")
		await RoomRender.shot(self, vc, Vector3(-7.5, 2.6, 1.0), Vector3(-10.0, -1.0, -5.0), p + "aisle")
		(vc[1] as Camera3D).fov = 90.0
		await RoomRender.close(self, vc)
