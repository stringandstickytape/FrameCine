extends "res://tests/env_builder_harness.gd"

## The Nave, Reclaimed and the Ice cinema (app/environments/nave.env.json, reclaimed.env.json, ice_cinema.env.json;
## docs/environments.md, "Room: Nave", "Room: Reclaimed", "Room: Ice cinema"). Each shipped document is built
## headless and checked as tests/test_environments.gd checks it (schema, comfort, licences, names, no people, the
## budget measured, a clear sight line from every seat), then for what makes it that room:
## - Nave: the nave's own screen in the chancel, the gothic church's own pews, the viewer in a pew's middle; Candles
##   (none, a few, many) rebuilds the stands; the candles flicker and Flickering lights holds them; the rose window
##   dims as the film starts and comes back after the end; the stone takes the film's light softly (its own test,
##   test_room_nave.gd, checks the rest).
## - Reclaimed: a hall half open to the sky with the viewer under the open part; ivy and ferns placed; Weather maps
##   onto the weather's mode; rain wets the room, the mist and the clouds follow the wet, the fireflies hide; the
##   puddle in the pit gives back the picture to the viewer's eyes; a loud bang scatters the birds; a quiet scene
##   may bring the deer down the side aisle, never into the sight line; broken seats, never the viewer's own.
## - Ice cinema: ice style, hides on every seat, the doorway behind the viewer towards the aurora; Aurora sets its
##   base and a quiet scene swells it, slowly, and lets it go; breath fog; the ice takes the film's light (its own
##   test, test_room_ice_cinema.gd, checks the rest).
## Each room's sound (tests/room_sound.gd): its acoustics and beds on the room's bus, the Nave's candle on Candles, the
## Reclaimed's rain and drips on the weather, the ice's huskies and creaks now and then; its level under the target
## and far under a film.
## godot --headless --xr-mode off --path app --script res://tests/test_room_set5.gd

## Each room well inside the headset's budget (its figures in docs/environments.md).
const MARGIN := {"draws": 32, "triangles": 200000, "lights": 0, "particles": 2000, "texture_mb": 32.0}


func run_tests() -> void:
	test_name = "test_room_set5"
	await _nave()
	await _reclaimed()
	await _ice()


func _load(id: String) -> Dictionary:
	var r := EnvDoc.load_file("res://environments/%s.env.json" % id)
	check("%s: the document reads (%s)" % [id, r["errors"]], (r["errors"] as Array).is_empty())
	var doc: Dictionary = r["doc"]
	if not doc.is_empty():
		check("%s: a cinema in the Room tab" % id, doc["room"].get("category") == "cinema")
		check("%s: listed as a room of its own" % id, EnvLibrary.document_rooms().any(
				func(e: Array) -> bool: return str(e[0]) == id))
	return doc


const EnvLibrary := preload("res://scripts/env/env_library.gd")
const RoomSound := preload("res://tests/room_sound.gd")


## The common part: built and checked, inside the margin, the default seat at the origin, something under every seat,
## the room dims during the film, a sound room.
func _common(id: String, doc: Dictionary) -> Node3D:
	var room := await check_room(id, doc)
	var stats: Dictionary = figures[-1][1]
	var over := EnvChecks.budget(stats, MARGIN)
	check("%s: well inside the budget %s %s" % [id, stats, over], over.is_empty())
	room.host.auto = false
	var seats: Array[Transform3D] = room.room_seat_transforms()
	check("%s: the default seat at the origin (%d seats)" % [id, seats.size()],
			seats.any(func(t: Transform3D) -> bool: return t.origin.length() < 0.05))
	check("%s: the room dims during the film" % id, room.dims_during_film())
	check("%s: a sound room with walls" % id, room.get_sound_room().has("box"))
	var shapes: Array = room.collision_shapes()
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
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(st.origin + Vector3.UP * 2.0,
				st.origin + Vector3.DOWN * 0.3))
		if hit.is_empty() or (hit["position"] as Vector3).y < st.origin.y - 0.1:
			floating += 1
	check("%s: something under every seat for object physics (%d without)" % [id, floating], floating == 0)
	body.queue_free()
	return room


func _steps(host: Node, seconds: float, dt := 0.1) -> void:
	var t := 0.0
	while t < seconds - 1e-6:
		host.step(dt)
		t += dt


func _play(host: Node, seconds: float, position := 600.0) -> void:
	host.snapshot_override = {"open": true, "playing": true, "position": position, "duration": 5400.0}
	_steps(host, seconds)


func _start(host: Node) -> void:
	host.snapshot_override = {"open": true, "playing": false, "position": 0.0, "duration": 5400.0}
	_steps(host, 0.5)
	host.snapshot_override = {"open": true, "playing": true, "position": 0.0, "duration": 5400.0}


func _fired(host: Node) -> Array:
	return host.timeline.fired.map(func(f: Array) -> String: return str(f[0]))


func _same_screen(a: Dictionary, b: Dictionary) -> bool:
	for k: String in ["center", "size"]:
		for i in (a[k] as Array).size():
			if absf(float(a[k][i]) - float(b[k][i])) > 0.01:
				return false
	return true


## A copy of the document whose cues always fire (the dice are the timeline's, tested there).
func _sure(doc: Dictionary) -> Dictionary:
	var d := doc.duplicate(true)
	for c: Dictionary in d.get("cues", []):
		c.erase("chance")
	return d


# --- Nave -----------------------------------------------------------------------------------------------------------

func _nave() -> void:
	var doc := _load("nave")
	if doc.is_empty():
		return
	var room := await _common("nave", doc)
	var host: Node = room.host
	for sid: String in ["light", "nave", "screen_frame"]:
		check("nave: the system %s is there" % sid, host.system(sid) != null)
	var nave: Node = host.system("nave")
	var screen: Dictionary = Registry.script_of("nave").call("screen_for", nave.params)
	check("nave: the screen is the nave's own, in the chancel (%s)" % [screen], _same_screen(doc["screen"], screen)
			and float(doc["screen"]["center"][2]) < float(nave.params["chancel_z"]))
	var seats: Array[Transform3D] = room.room_seat_transforms()
	check("nave: pews, one place a slot (%d)" % seats.size(), seats.size() == (nave.seat_slots() as Array).size()
			and (nave.seat_slots() as Array).all(func(s: Dictionary) -> bool: return s["style"] == "pew"))
	# Since the deep pass (2026-11-08) the church draws its own carved pews, so the bake lights them (its own test,
	# test_room_nave.gd, checks the rest).
	check("nave: the gothic church draws its own pews", str(nave.params["style"]) == "gothic"
			and _has(room, "Pews") and not nave.draws_seats_elsewhere())
	var ahead := seats.filter(func(t: Transform3D) -> bool: return t.origin.z < -0.5 and absf(t.origin.x) < 0.1)
	check("nave: the viewer in a pew's middle with four pews in front (%d)" % ahead.size(), ahead.size() == 4)
	check("nave: the stone takes the film's light, softly (spill %s)" % host.system("light").params["spill"],
			float(host.system("light").params["spill"]) > 0.3 and float(host.system("light").params["spill"]) < 1.5)
	# Candles: a few by default; none; many. The setting rebuilds the nave.
	check("nave: two candle stands a side by default", int(nave.params["candles"]) == 2 and _has(room, "Flames"))
	host.set_setting("candles", "none")
	await process_frame
	nave = host.system("nave")
	check("nave: Candles none: no stands", int(nave.params["candles"]) == 0 and not _has(room, "Flames"))
	host.set_setting("candles", "many")
	await process_frame
	nave = host.system("nave")
	check("nave: Candles many: four a side", int(nave.params["candles"]) == 4 and _has(room, "Flames"))
	var many := EnvChecks.measure(room)
	check("nave: many candles inside the margin too (%s)" % [many], EnvChecks.budget(many, MARGIN).is_empty())
	host.set_setting("candles", "few")
	await process_frame
	nave = host.system("nave")
	var values: Array[float] = []
	for i in 90:
		host.step(1.0 / 30.0)
		values.append(nave.flicker_factor())
	check("nave: the candles flicker (%.3f..%.3f)" % [values.min(), values.max()], values.max() - values.min() > 0.02)
	host.set_setting("flicker", false)
	check("nave: Flickering lights off holds them", float(nave.params["flicker"]) == 0.0)
	host.set_setting("flicker", true)
	# The rose window dims as the film starts and comes back after the end.
	var glow0 := float(nave.params["rose_glow"])
	_start(host)
	_steps(host, 3.0)
	var mid := float(nave.params["rose_glow"])
	_steps(host, 4.0)
	var low := float(nave.params["rose_glow"])
	check("nave: starting: the rose window dims slowly (%.2f, %.2f, %.2f)" % [glow0, mid, low],
			glow0 > mid and mid > low and is_equal_approx(low, 0.12))
	host.snapshot_override = {"open": true, "playing": false, "position": 5400.0, "duration": 5400.0, "ended": true}
	_steps(host, 6.0)
	check("nave: ended: the rose window back (%.2f)" % float(nave.params["rose_glow"]),
			is_equal_approx(float(nave.params["rose_glow"]), glow0))
	# Sound: the stone's long reverb, a faint wind high in the clerestory, now and then a candle's gutter; no organ.
	RoomSound.check_beds(self, "nave", room, {"wind": "wind", "candle": "candle", "owl": "tawny_owl",
			"bell": "church_bell"}, "stone_nave")
	var reverb: Dictionary = host.system_of_kind("sound").values()
	check("nave: a long stone reverb (rt60 %.1f)" % float(reverb["rt60"]), absf(float(reverb["rt60"]) - 3.0) < 0.01)
	var wind: Node = host.system("wind")
	check("nave: the wind high up (%s)" % [wind.players().map(func(q: Node3D) -> float: return q.position.y)],
			not wind.players().is_empty() and wind.players().all(func(q: Node3D) -> bool: return q.position.y > 6.0))
	var candle: Node = host.system("candle")
	check("nave: a candle's gutter now and then (every %.0f s)" % float(candle.params["every"]),
			not candle.is_loop() and float(candle.params["every"]) >= 60.0)
	RoomSound.check_setting(self, "nave", room, "candle", "candles", "none", "few")
	check("nave: no music system (no organ)", host.systems_of_kind("music").is_empty())
	await done(room)
	await RoomSound.check_level(self, self, "nave", doc)


func _has(room: Node, node_name: String) -> bool:
	for n: Node in room.find_children(node_name, "", true, false):
		if not n.is_queued_for_deletion():
			return true
	return false


# --- Reclaimed ------------------------------------------------------------------------------------------------------

func _reclaimed() -> void:
	var doc := _load("reclaimed")
	if doc.is_empty():
		return
	var room := await _common("reclaimed", _sure(doc))
	var host: Node = room.host
	for sid: String in ["light", "hall", "screen_frame", "kit", "seats", "sky", "weather", "atmosphere", "birds",
			"fireflies", "deer"]:
		check("reclaimed: the system %s is there" % sid, host.system(sid) != null)
	var hall: Node = host.system("hall")
	var lo: Vector3 = _v3(hall.params["room_min"])
	var hi: Vector3 = _v3(hall.params["room_max"])
	var open_from := lerpf(lo.z, hi.z, float(hall.params["ceiling_cover"]))
	check("reclaimed: half the roof gone, the viewer under the open sky (from z %.1f)" % open_from,
			is_equal_approx(float(hall.params["ceiling_cover"]), 0.5) and open_from < -1.0)
	var kit: Node = host.system("kit")
	check("reclaimed: ivy and ferns all placed (%s)" % [kit.problems()], (kit.problems() as Array).is_empty()
			and _has(room, "PieceSoft"))
	check("reclaimed: the house lamps and signs dead", float(host.system("light").params["house_lamps"]) == 0.0
			and float(host.system("light").params["signs"]) == 0.0)
	# Broken seats, never the viewer's own.
	var seats: Array[Transform3D] = room.room_seat_transforms()
	var broken: Array = host.system("seats").params["broken"]
	check("reclaimed: broken seats (%d), none the viewer's" % broken.size(), broken.size() > 0 and broken.all(
			func(i: int) -> bool: return i < seats.size() and seats[i].origin.length() > 0.05))
	# Weather: the setting onto the mode.
	var w: Node = host.system("weather")
	check("reclaimed: Weather changing by default", str(w.params["mode"]) == "changing")
	for pair: Array in [["rain", "heavy"], ["mist", "light"], ["clear", "clear"]]:
		host.set_setting("weather", pair[0])
		check("reclaimed: Weather %s: the weather %s" % pair, str(w.params["mode"]) == pair[1])
	host.set_setting("weather", "clear")
	_steps(host, 120.0, 0.5)
	var fog_dry := float(host.system("atmosphere").params["fog"])
	var clouds_dry := float(host.system("sky").params["clouds"])
	var flies_dry := float(host.system("fireflies").params["activity"])
	host.set_setting("weather", "rain")
	_steps(host, 120.0, 0.5)
	var wet := float(w.wet_amount())
	check("reclaimed: rain falls through the roof (%.2f) and wets the room (%.2f)" % [w.rain_amount(), wet],
			w.rain_amount() > 0.6 and wet > 0.5)
	check("reclaimed: mist rises after the rain (%.2f to %.2f)" % [fog_dry, float(host.system("atmosphere").params["fog"])],
			float(host.system("atmosphere").params["fog"]) > fog_dry + 0.15)
	check("reclaimed: the clouds close over (%.2f to %.2f)" % [clouds_dry, float(host.system("sky").params["clouds"])],
			float(host.system("sky").params["clouds"]) > clouds_dry + 0.2)
	check("reclaimed: the fireflies hide in the rain (%.2f to %.2f)" % [flies_dry,
			float(host.system("fireflies").params["activity"])],
			float(host.system("fireflies").params["activity"]) < flies_dry - 0.3)
	# The puddle in the pit: in front of the viewer, seen from the eyes, and the picture's reflection in it.
	var pc := _v3(w.params["puddle_center"])
	var ps: Vector2 = Vector2(w.params["puddle_size"][0], w.params["puddle_size"][1])
	var eye := Vector3(0, EnvChecks.EYE_HEIGHT, 0)
	var sc := _v3(doc["screen"]["center"])
	# The eye mirrored in the puddle's plane, to the picture's middle: where it crosses the plane.
	var mirror := Vector3(eye.x, 2.0 * pc.y - eye.y, eye.z)
	var f := (pc.y - mirror.y) / (sc.y - mirror.y)
	var at := mirror.lerp(sc, f)
	check("reclaimed: the puddle gives back the picture's middle (at z %.2f; the puddle %.2f..%.2f)" % [at.z,
			pc.z - ps.y * 0.5, pc.z + ps.y * 0.5], absf(at.z - pc.z) < ps.y * 0.5 and absf(at.x - pc.x) < ps.x * 0.5)
	check("reclaimed: the puddle drawn", w.puddle() != null and w.puddle().visible)
	# A loud bang scatters the birds; a quiet scene brings the deer, clear of the sight line.
	_play(host, 1.0)
	host.signals.fake("film.transient", 1.0)
	_steps(host, 0.3)
	host.signals.fake("film.transient", 0.0)
	check("reclaimed: a loud bang scatters the birds", _fired(host).has("birds_start"))
	var deer: Node = host.system("deer")
	host.signals.fake("film.quiet", 1.0)
	_steps(host, 7.0)
	host.signals.fake("film.quiet", 0.0)
	check("reclaimed: a quiet scene brings the deer (%s)" % [_fired(host)], _fired(host).has("deer_in_quiet"))
	var seen := false
	for i in 1200:
		host.step(0.1)
		seen = seen or not (deer.creature.positions() as Array).is_empty()
	check("reclaimed: the deer came down the side aisle, never in the sight line (%.2f s)" % deer.longest_in_view,
			seen and deer.longest_in_view < 0.01)
	host.set_setting("life", false)
	_steps(host, 2.0)
	check("reclaimed: Ambient life off: they fade away", not deer.active and not host.system("birds").active)
	# Sound: open air; rain on the leaves and the boards with the rain, drips with the wet, a soft wind; the birds'
	# calls are the birds' own.
	RoomSound.check_beds(self, "reclaimed", room, {"rain": "rain_leaves", "rain_boards": "rain_leaves",
			"drips": "drips", "wind": "wind"}, "outdoors")
	RoomSound.check_follows(self, "reclaimed", room, "rain", "weather.rain")
	RoomSound.check_follows(self, "reclaimed", room, "rain_boards", "weather.rain")
	RoomSound.check_follows(self, "reclaimed", room, "drips", "weather.wet")
	check("reclaimed: rain round the viewer (%d voices)" % host.system("rain").players().size(),
			host.system("rain").players().size() == 4)
	check("reclaimed: the wind under the rest (%.1f dB)" % float(host.system("wind").params["gain_db"]),
			float(host.system("wind").params["gain_db"]) <= -6.0)
	await done(room)
	await RoomSound.check_level(self, self, "reclaimed", doc)


func _v3(v: Variant) -> Vector3:
	return Vector3(float(v[0]), float(v[1]), float(v[2]))


# --- Ice cinema -----------------------------------------------------------------------------------------------------

func _ice() -> void:
	var doc := _load("ice_cinema")
	if doc.is_empty():
		return
	var room := await _common("ice_cinema", doc)
	var host: Node = room.host
	for sid: String in ["light", "room", "seats", "sky", "atmosphere"]:
		check("ice: the system %s is there" % sid, host.system(sid) != null)
	var dom: Node = host.system("room")
	var p: Dictionary = Registry.script_of("domestic").call("resolved", dom.params)
	check("ice: a room of ice blocks", str(p["style"]) == "ice" and str(p["wall_pattern"]) == "ice_blocks")
	var screen: Dictionary = Registry.script_of("domestic").call("screen_for", dom.params)
	check("ice: the screen is the ice wall's panel (%s)" % [screen], _same_screen(doc["screen"], screen))
	var seats: Array[Transform3D] = room.room_seat_transforms()
	check("ice: hides on every seat (%d)" % seats.size(), str(host.system("seats").params["model"]) == "hide"
			and seats.size() == (dom.seat_slots() as Array).size() and seats.size() > 0)
	# The window in the left wall looks out where the aurora hangs (the screen faces south: the left is east).
	var sky: Node = host.system("sky")
	var left := fposmod(float(sky.params["facing"]) - 90.0, 360.0)
	check("ice: the window on the left, towards the aurora (%s, bearing %s), the sky beyond" % [p["window"],
			sky.params["aurora_bearing"]], str(p["window"]) == "left"
			and absf(left - float(sky.params["aurora_bearing"])) < 1.0 and str(dom.params["outside"]) == "none")
	# Since 2026-11-08 the film's light is inside the ice round the screen (kit/ice_hall.gd); its own test checks more.
	var ice_m := (room.find_child("IceBlocks", true, false) as MeshInstance3D).mesh.surface_get_material(0)
	check("ice: the ice takes the film's light round the screen (%s)" % ice_m.get_shader_parameter("ice_film"),
			float(ice_m.get_shader_parameter("ice_film")) > 0.3)
	var atm: Node = host.system("atmosphere")
	check("ice: breath fog and a little ground fog", float(atm.params["breath"]) > 0.0 and atm.breath_node() != null
			and float(atm.params["fog"]) > 0.0)
	# Aurora: the setting's base; a quiet scene swells it slowly and lets it go.
	check("ice: Aurora in quiet scenes: faint at first (%.2f)" % float(sky.params["aurora"]),
			absf(float(sky.params["aurora"]) - 0.15) < 0.01)
	_play(host, 1.0)
	host.signals.fake("film.quiet", 1.0)
	_steps(host, 4.0)
	var rising := float(sky.params["aurora"])
	_steps(host, 8.0)
	var full := float(sky.params["aurora"])
	check("ice: a quiet scene: the aurora swells, slowly (%.2f, %.2f)" % [rising, full], rising > 0.2 and rising < 0.9
			and full > 0.95)
	host.signals.fake("film.quiet", 0.0)
	_steps(host, 4.0)
	var fading := float(sky.params["aurora"])
	_steps(host, 10.0)
	check("ice: the quiet ends: it fades back, slowly (%.2f, %.2f)" % [fading, float(sky.params["aurora"])],
			fading > 0.5 and absf(float(sky.params["aurora"]) - 0.15) < 0.02)
	host.set_setting("aurora", "always")
	check("ice: Aurora always (%.2f)" % float(sky.params["aurora"]), absf(float(sky.params["aurora"]) - 0.8) < 0.01)
	host.set_setting("aurora", "off")
	check("ice: Aurora off", float(sky.params["aurora"]) < 0.01)
	host.signals.fake("film.quiet", 1.0)
	_steps(host, 12.0)
	check("ice: Aurora off: no swell in a quiet scene (%.2f)" % float(sky.params["aurora"]),
			float(sky.params["aurora"]) < 0.01)
	host.signals.fake("film.quiet", 0.0)
	_steps(host, 1.0)
	# Sound: the ice's ring; far huskies now and then, a soft wind past the doorway, the ice creaking now and then.
	RoomSound.check_beds(self, "ice", room, {"huskies": "huskies", "wind": "wind", "creak": "ice_creak"}, "ice")
	var huskies: Node = host.system("huskies")
	var creak: Node = host.system("creak")
	var far := _v3(huskies.params["at"]).length()
	check("ice: the huskies far off (%.0f m)" % far, far > 50.0)
	check("ice: the wind at the doorway behind (z %.1f)" % float(host.system("wind").params["at"][2]),
			float(host.system("wind").params["at"][2]) > 2.5)
	var h0: int = huskies.plays
	var c0: int = creak.plays
	_steps(host, 650.0, 0.5)
	check("ice: in 11 minutes the huskies call and the ice creaks, now and then (%d, %d)" % [huskies.plays - h0,
			creak.plays - c0], huskies.plays - h0 >= 1 and huskies.plays - h0 <= 3 and creak.plays - c0 >= 2
			and creak.plays - c0 <= 4)
	await done(room)
	await RoomSound.check_level(self, self, "ice", doc)
