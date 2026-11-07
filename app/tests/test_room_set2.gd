extends "res://tests/env_builder_harness.gd"

## Three rooms of the cinema set (docs/environments.md, "Room: Atmospheric 1928", "Room: Palace of Culture 1974",
## "Room: Flagship"), each its document alone. Each is built headless from app/environments/<id>.env.json and checked
## as a room that ships (schema, comfort, licences, names, no people, the headset's budget, a clear sight line from
## every seat) and for what makes it that room:
##   Atmospheric 1928    open to the sky (no ceiling), the courtyard's façades and niches (urns, lions, obelisks), the
##                       castle gate, cypresses, a twilight sky whose clouds follow the Clouds setting and take the
##                       film's colour; the ritual parts the curtains and deepens the dusk; Pre-show off: dim only
##   Palace of Culture   board-marked concrete, mosaic panels that take more of the screen's light, ochre drapes,
##                       straight rows; the Snow setting drives the snowfall, the clouds and the birches' snow; the
##                       snow falls only under the open back of the roof
##   Flagship            a steep rake, black walls, blue step lights, a huge screen with its curve; the default seat
##                       in the middle of the rows; the ritual takes the house lamps out and the steps down
## Every room: seat picking (a chosen seat folds away), the lights come back up in the pre-show. The Palace's and the
## Flagship's sound (tests/room_sound.gd): the concrete hall's echo and the bells the ritual rings; the Flagship's dry
## acoustics and no beds; each room's level.
## Under a renderer (lavapipe, ENV_SHOTS set): a picture of each room from its default seat, and one looking up.
## godot --headless --xr-mode off --path app --script res://tests/test_room_set2.gd

const EnvLibrary := preload("res://scripts/env/env_library.gd")
const Auditorium := preload("res://scripts/env/systems/auditorium.gd")
const RoomSound := preload("res://tests/room_sound.gd")
const ROOMS: Array[String] = ["atmospheric_1928", "palace_of_culture_1974", "flagship"]
## Well inside the headset's budget (the Frame draws the room twice, at 90 Hz).
const OWN_BUDGET := {"draws": 32, "triangles": 300000, "lights": 0, "particles": 2000, "texture_mb": 32.0}
const VIEW := Vector2i(480, 320)

var _shots := 0


func run_tests() -> void:
	test_name = "test_room_set2"
	var listed: Array = EnvLibrary.document_rooms().map(func(e: Array) -> String: return str(e[0]))
	for id in ROOMS:
		check("%s: listed as a room by its document alone (%s)" % [id, listed], listed.has(id)
				and not FileAccess.file_exists("res://environments/%s.tscn" % id))
	await _atmospheric()
	await _palace()
	await _flagship()
	if DisplayServer.get_name() != "headless":
		for id in ROOMS:
			await _render(id)


func _load(id: String) -> Dictionary:
	var r := EnvDoc.load_file("res://environments/%s.env.json" % id)
	check("%s: the document reads and validates %s" % [id, r["errors"]], (r["errors"] as Array).is_empty())
	return r["doc"]


## Builds and checks the room as a shipped room is checked, with the room's own tighter budget.
func _built(id: String) -> Node3D:
	var doc := _load(id)
	var room := await check_room(id, doc)
	room.host.auto = false
	var stats: Dictionary = figures[-1][1]
	check("%s: well inside the budget %s %s" % [id, stats, OWN_BUDGET], EnvChecks.budget(stats, OWN_BUDGET).is_empty())
	check("%s: comfort %s" % [id, EnvChecks.comfort(doc)], EnvChecks.comfort(doc).is_empty())
	check("%s: the common Dim during the film applies" % id, room.common_applies("always") and room.dims_during_film())
	check("%s: the Pre-show applies (curtains, a cue that requires it)" % id, room.common_applies("ritual")
			and room.has_curtains and room.curtains_by_cue)
	return room


## A film opened at its start, then started (the timeline goes from the pre-show to starting).
func _start(h: Node) -> void:
	h.snapshot_override = {"open": true, "playing": false, "position": 0.0, "duration": 6000.0}
	h.step(0.05)
	h.snapshot_override = {"open": true, "playing": true, "position": 0.1, "duration": 6000.0}
	h.step(0.05)


func _steps(h: Node, seconds: float, dt := 0.1) -> void:
	var t := 0.0
	while t < seconds:
		h.step(dt)
		t += dt


func _cue_names(h: Node) -> Array:
	return h.timeline.log.map(func(e: Array) -> String: return str(e[0])) if h.timeline.get("log") != null else []


func _opened(h: Node) -> bool:
	var showing: Node = h.system("showing")
	return showing.log.any(func(a: Array) -> bool: return a[0] == "open_curtains")


## The ritual with the Pre-show on; then off (the dim cue only); then the pre-show again (lights up).
func _ritual(id: String, room: Node3D, lamps_to: float, steps_to: float, extra := {}) -> void:
	var h: Node = room.host
	h.set_setting("ritual", true)
	_start(h)
	check("%s: starting" % id, h.timeline.state == "starting")
	h.step(0.1)
	check("%s: the ritual parts the curtains" % id, _opened(h))
	_steps(h, 14.0)
	check("%s: the ritual takes the house lamps to %s (%.2f)" % [id, lamps_to, h.param("light.house_lamps")],
			absf(float(h.param("light.house_lamps")) - lamps_to) < 0.02)
	check("%s: the steps to %s (%.2f)" % [id, steps_to, h.param("light.step_lights")],
			absf(float(h.param("light.step_lights")) - steps_to) < 0.02)
	for target: String in extra:
		check("%s: the ritual takes %s to %s (%.2f)" % [id, target, extra[target], h.param(target)],
				absf(float(h.param(target)) - float(extra[target])) < 0.02)
	h.snapshot_override = {"open": false}
	h.step(0.05)
	_steps(h, 9.0)
	check("%s: the pre-show again: the lamps back up (%.2f)" % [id, h.param("light.house_lamps")],
			absf(float(h.param("light.house_lamps")) - 1.0) < 0.02)
	# The Pre-show off: no curtains, the dim cue takes the lamps down.
	var showing: Node = h.system("showing")
	showing.log.clear()
	h.set_setting("ritual", false)
	_start(h)
	_steps(h, 7.0)
	check("%s: Pre-show off: no curtains from the room" % id, not _opened(h))
	check("%s: Pre-show off: the lamps still go down (%.2f)" % [id, h.param("light.house_lamps")],
			absf(float(h.param("light.house_lamps")) - lamps_to) < 0.02)
	for target: String in extra:
		check("%s: Pre-show off: %s still to %s (%.2f)" % [id, target, extra[target], h.param(target)],
				absf(float(h.param(target)) - float(extra[target])) < 0.02)
	h.snapshot_override = {"open": false}
	h.step(0.05)
	_steps(h, 9.0)
	h.set_setting("ritual", true)


## Seat picking: the room moved so another seat is at the origin folds that seat away; back home, the viewer's own.
func _seat_picking(id: String, room: Node3D) -> void:
	var hall: Node = room.host.system("hall")
	var seats: Array[Transform3D] = room.room_seat_transforms()
	var home := -1
	for i in seats.size():
		if seats[i].origin.length() < 0.05:
			home = i
	check("%s: the default seat at the origin (%d of %d)" % [id, home, seats.size()], home >= 0)
	var other := 0 if home != 0 else seats.size() - 1
	room.transform = Transform3D(Basis(), -seats[other].origin)
	await process_frame
	check("%s: a chosen seat folds away (%d)" % [id, hall.get("_hidden_seat")], hall.get("_hidden_seat") == other)
	room.transform = Transform3D()
	await process_frame
	check("%s: back at the default seat, the viewer's own folded" % id, hall.get("_hidden_seat") == home)


# --- Atmospheric 1928 ----------------------------------------------------------------------------------------------------

func _atmospheric() -> void:
	var id := "atmospheric_1928"
	var room := await _built(id)
	var h: Node = room.host
	for sid: String in ["light", "hall", "screen_frame", "showing", "kit", "sky", "vista"]:
		check("%s: has %s" % [id, sid], h.system(sid) != null)
	check("%s: open to the sky: no ceiling" % id, float(h.system("hall").params["ceiling_cover"]) == 0.0
			and room.get_node_or_null("Ceiling") == null)
	var kit: Node = h.system("kit")
	check("%s: every kit piece placed %s" % [id, kit.problems()], kit.problems().is_empty())
	var pieces: Array = kit.params["pieces"]
	var kinds := {}
	for p: Dictionary in pieces:
		kinds[str(p["piece"])] = true
		if p.has("holds"):
			kinds[str(p["holds"])] = true
	check("%s: the castle gate, façades, niches with urns, lions and obelisks (%s)" % [id, kinds.keys()],
			kinds.has_all(["castle_gate", "facade", "niche", "urn", "lion", "obelisk"]))
	check("%s: the courtyard's lit windows" % id, room.get_node_or_null("PieceWindows") != null)
	var shapes: Array = (h.system("vista").params["items"] as Array).map(func(i: Dictionary) -> String: return i["shape"])
	check("%s: cypresses round the courtyard" % id, shapes.count("cypresses") >= 2)
	var sky: Node = h.system("sky")
	check("%s: a twilight sky, no constellation lines (dusk %.2f)" % [id, h.param("sky.dusk")],
			float(h.param("sky.dusk")) < 0.6 and float(sky.params["lines"]) == 0.0)
	# The Clouds setting.
	h.set_setting("clouds", 1.0)
	h.step(0.1)
	var full := float(h.param("sky.clouds"))
	h.set_setting("clouds", 0.0)
	h.step(0.1)
	var none := float(h.param("sky.clouds"))
	h.set_setting("clouds", 0.4)
	h.step(0.1)
	check("%s: Clouds moves the sky's clouds (%.2f at full, %.2f at none, %.2f by default)" % [id, full, none,
			h.param("sky.clouds")], absf(full - 0.8) < 0.01 and none < 0.01 and absf(float(h.param("sky.clouds")) - 0.32) < 0.01)
	# The clouds take the film's colour.
	h.signals.fake("film.colour", Color(0.9, 0.1, 0.1))
	_steps(h, 5.0)
	var c: Color = h.param("sky.cloud_colour")
	check("%s: the clouds take the film's colour (%s)" % [id, c], c.r > c.b + 0.1)
	h.signals.fake("film.colour", Color(0.1, 0.1, 0.9))
	_steps(h, 5.0)
	c = h.param("sky.cloud_colour")
	check("%s: and follow it (%s)" % [id, c], c.b > c.r + 0.1)
	h.signals.clear_fakes()
	# The courtyard's fountain in a niche on the left wall, through the hall's acoustics.
	var SoundChecks: GDScript = load("res://tests/room_sound_checks.gd")
	var bus: Array = SoundChecks.on_room_bus(room, ["fountain"])
	check("%s: the fountain on the room's bus, under Environment (the slider, the duck, Ambience) %s" % [id, bus],
			bus.is_empty())
	var ac: Array = SoundChecks.acoustics(room, "cinema", 0.7)
	check("%s: the acoustics cinema %s" % [id, ac], ac.is_empty())
	var fountain: Node = h.system("fountain")
	var spouts: Array = fountain.players()
	check("%s: the fountain plays in a niche on the left wall, 4 dB under its level" % id, fountain.is_loop()
			and fountain.playing() and spouts.size() == 1 and (spouts[0] as Node3D).position.x < -9.0
			and is_equal_approx(float(fountain.params["gain_db"]), -4.0))
	await _ritual(id, room, 0.12, 0.5, {"sky.dusk": 0.8})
	_steps(h, 1.0)
	check("%s: the pre-show: the dusk back to twilight (%.2f)" % [id, h.param("sky.dusk")],
			absf(float(h.param("sky.dusk")) - 0.4) < 0.02)
	await _seat_picking(id, room)
	var r: Dictionary = await SoundChecks.levels(self, room, id)
	for v: Array in SoundChecks.verdicts(id, r):
		check(v[0], v[1])
	await done(room)


# --- Palace of Culture 1974 ----------------------------------------------------------------------------------------------

func _palace() -> void:
	var id := "palace_of_culture_1974"
	var room := await _built(id)
	var h: Node = room.host
	for sid: String in ["light", "hall", "screen_frame", "showing", "sky", "vista", "weather"]:
		check("%s: has %s" % [id, sid], h.system(sid) != null)
	var hall: Node = h.system("hall")
	var hp: Dictionary = hall.params
	check("%s: board-marked concrete walls, ochre drapes, straight rows" % id,
			str(hp["walls"]["library"]) == "concrete_panels" and str(hp["proscenium"]) == "drapes"
			and float(hp["row_radius"]) == 0.0 and room.get_node_or_null("Curtains") != null)
	var panels := room.get_node_or_null("WallPanels") as MeshInstance3D
	var mosaic: ShaderMaterial = panels.mesh.surface_get_material(0) if panels != null else null
	var walls := room.get_node_or_null("Walls") as MeshInstance3D
	var concrete: ShaderMaterial = walls.mesh.surface_get_material(0) if walls != null else null
	check("%s: the mosaic panels take more of the screen's light than the concrete (%s, %s)" % [id,
			mosaic.get_shader_parameter("spill") if mosaic != null else null,
			concrete.get_shader_parameter("spill") if concrete != null else null],
			mosaic != null and concrete != null
			and float(mosaic.get_shader_parameter("spill")) > float(concrete.get_shader_parameter("spill")))
	# The snow falls only under the open back of the roof.
	var lo := Auditorium.Layout._v3(hp["room_min"])
	var hi := Auditorium.Layout._v3(hp["room_max"])
	var open_from := lerpf(lo.z, hi.z, float(hp["ceiling_cover"]))
	var area: Dictionary = h.system("weather").params["areas"][0]
	check("%s: the snow's area under the open roof (from z %.2f; the area from %.2f)" % [id, open_from,
			area["min"][2]], float(area["min"][2]) >= open_from and float(area["max"][2]) <= hi.z)
	check("%s: the snow falls behind the default seat (the picture clear)" % id, float(area["min"][2]) > 1.0)
	var shapes: Array = (h.system("vista").params["items"] as Array).map(func(i: Dictionary) -> String: return i["shape"])
	check("%s: birches outside" % id, shapes.count("birches") >= 1)
	# The Snow setting.
	var expect := {"none": ["clear", 0.2, 0.8], "light": ["light", 0.55, 1.0], "heavy": ["heavy", 0.85, 1.0]}
	for v: String in expect:
		h.set_setting("snow", v)
		h.step(0.1)
		check("%s: Snow %s: the weather %s, clouds %.2f, the birches' snow %.2f (%s, %.2f, %.2f)" % [id, v,
				expect[v][0], expect[v][1], expect[v][2], h.param("weather.mode"), h.param("sky.clouds"),
				h.param("vista.snow")], str(h.param("weather.mode")) == expect[v][0]
				and absf(float(h.param("sky.clouds")) - float(expect[v][1])) < 0.01
				and absf(float(h.param("vista.snow")) - float(expect[v][2])) < 0.01)
	h.set_setting("snow", "heavy")
	_steps(h, 60.0, 0.5)
	var heavy := float(h.system("weather").snow_amount())
	h.set_setting("snow", "none")
	_steps(h, 60.0, 0.5)
	var clear := float(h.system("weather").snow_amount())
	check("%s: snow falls when Heavy, stops when None (%.2f, %.2f)" % [id, heavy, clear], heavy > 0.5 and clear < 0.1)
	h.set_setting("snow", "light")
	# Sound: the concrete hall's echo; the house bells, played by the ritual only.
	RoomSound.check_beds(self, id, room, {"bells": "three_bells"}, "concrete_hall")
	var bells: Node = h.system("bells")
	var rang: int = bells.plays
	await _ritual(id, room, 0.1, 0.5)
	check("%s: the ritual rings the bells once, Pre-show off none (%d)" % [id, bells.plays - rang],
			bells.plays - rang == 1)
	await _seat_picking(id, room)
	var doc: Dictionary = room.doc
	await done(room)
	await RoomSound.check_level(self, self, id, doc)


# --- Flagship --------------------------------------------------------------------------------------------------------

func _flagship() -> void:
	var id := "flagship"
	var room := await _built(id)
	var h: Node = room.host
	var doc: Dictionary = room.doc
	for sid: String in ["light", "hall", "screen_frame", "showing"]:
		check("%s: has %s" % [id, sid], h.system(sid) != null)
	var hp: Dictionary = h.system("hall").params
	var rake := rad_to_deg(atan(float(hp["row_rise"]) / float(hp["row_depth"])))
	check("%s: a steep rake (%.1f degrees)" % [id, rake], rake > 20.0)
	var wall := Color(hp["walls"]["color"][0], hp["walls"]["color"][1], hp["walls"]["color"][2])
	check("%s: black walls (%s)" % [id, wall], wall.get_luminance() < 0.05 and str(hp["wall_treatment"]) == "plain")
	var steps := room.get_node_or_null("StepLights") as MeshInstance3D
	var sm: ShaderMaterial = steps.mesh.surface_get_material(0) if steps != null else null
	var sc: Variant = sm.get_shader_parameter("colour") if sm != null else null
	check("%s: blue step lights (%s)" % [id, sc], sc is Color and (sc as Color).b > (sc as Color).r * 2.0)
	var size: Array = doc["screen"]["size"]
	var centre: Array = doc["screen"]["center"]
	check("%s: a huge, curved screen (%s m, curve %s)" % [id, size, doc["screen"].get("curve")],
			float(size[0]) >= 18.0 and float(doc["screen"].get("curve", 0.0)) > 0.0)
	# The default seat: the middle of the rows, about a screen's width away (front-middle and the back are the others).
	var front := int(hp["rows_front"])
	var back := int(hp["rows_back"])
	var dist := absf(float(centre[2]))
	check("%s: the default seat in the middle rows (%d in front, %d behind)" % [id, front, back],
			absi(front - back) <= 2)
	check("%s: the default seat about a screen's width from it (%.2f widths)" % [id, dist / float(size[0])],
			dist / float(size[0]) > 0.8 and dist / float(size[0]) < 1.1)
	check("%s: the picture's middle at the seated eyes' height (%.2f)" % [id, float(centre[1])],
			absf(float(centre[1]) - 1.2) < 0.3)
	# Sound: a damped modern hall's acoustics, no beds of its own.
	RoomSound.check_beds(self, id, room, {}, "cinema")
	var acoustics: Dictionary = h.system_of_kind("sound").values()
	check("%s: drier than a cinema's preset (rt60 %.2f, damping %.2f)" % [id, acoustics["rt60"], acoustics["damping"]],
			float(acoustics["rt60"]) < 0.7 and float(acoustics["damping"]) > 0.6)
	await _ritual(id, room, 0.0, 0.35)
	await _seat_picking(id, room)
	await done(room)
	await RoomSound.check_level(self, self, id, doc, true)


# --- Pictures (lavapipe) ----------------------------------------------------------------------------------------------

func _render(id: String) -> void:
	var doc := _load(id)
	var vp := SubViewport.new()
	vp.size = VIEW
	vp.own_world_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color.BLACK
	var we := WorldEnvironment.new()
	we.environment = env
	vp.add_child(we)
	var cam := Camera3D.new()
	cam.fov = 80.0
	cam.far = 200.0
	vp.add_child(cam)
	cam.current = true
	root.add_child(vp)
	var room: Node3D = EnvRoom.new()
	room.doc = doc
	vp.add_child(room)
	await process_frame
	room.host.auto = false
	var w := float(doc["screen"]["size"][0])
	var hgt := float(doc["screen"]["size"][1])
	var anchor: Transform3D = room.get_screen_anchor()
	room.host.on_screen_changed(anchor, Vector2(w, hgt))
	# A stand-in picture where the film goes.
	var quad := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(w, hgt)
	quad.mesh = qm
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.55, 0.6, 0.7)
	quad.material_override = mat
	quad.transform = anchor
	room.add_child(quad)
	room.host.step(0.1)
	var eye := Vector3(0, 1.2, 0)
	var centre: Vector3 = anchor.origin
	await _shot(vp, cam, id, eye, centre)
	await _shot(vp, cam, id, eye, eye + Vector3(0.0, 1.0, 0.6))
	await _shot(vp, cam, id, eye, eye + Vector3(-1.0, 0.25, 0.4))
	vp.queue_free()
	await process_frame


func _shot(vp: SubViewport, cam: Camera3D, id: String, at: Vector3, look: Vector3) -> void:
	cam.look_at_from_position(at, look)
	for i in 4:
		await process_frame
	await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	img.convert(Image.FORMAT_RGB8)
	var out := OS.get_environment("ENV_SHOTS")
	_shots += 1
	if out != "":
		img.save_png("%s/%s_%d.png" % [out, id, _shots])
	check("%s: rendered (%d x %d)" % [id, img.get_width(), img.get_height()], img.get_width() == VIEW.x)
