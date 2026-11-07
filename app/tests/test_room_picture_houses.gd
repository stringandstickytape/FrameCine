extends SceneTree

## Three rooms of the cinema set (docs/environments.md, "Room: Shopfront 1906", "Room: Streamline 1937", "Room: Pink
## Palace"), each its document alone: built headless as the app builds it (env_room.gd) and checked for what makes it
## that room. Every room: the checks (schema, comfort, licences, names, no people), the headset's budget with room to
## spare, a clear sight line from every seat, the viewer's own seat at the origin among the room's seats, its systems,
## its settings, and its ritual run through the timeline (lamps down, curtains or festoon, the organ console).
## godot --headless --xr-mode off --path app --script res://tests/test_room_picture_houses.gd

const EnvChecks := preload("res://scripts/env/env_checks.gd")
const EnvDoc := preload("res://scripts/env/env_doc.gd")
const EnvRoom := preload("res://scripts/env/env_room.gd")
const EnvLibrary := preload("res://scripts/env/env_library.gd")
## These rooms stay well inside the headset's budget (env_checks.gd BUDGET): the Frame draws them twice at 90 Hz.
const SPARE := {"draws": 32, "triangles": 300000, "lights": 0, "particles": 1000, "texture_mb": 32.0}
const DT := 0.1

var _failures := 0
var _checks := 0


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var listed: Array = EnvLibrary.document_rooms().map(func(e: Array) -> String: return str(e[0]))
	for id: String in ["shopfront_1906", "streamline_1937", "pink_palace"]:
		_check("%s: listed as a room by its document alone" % id, listed.has(id))
	await _shopfront()
	await _streamline()
	await _pink_palace()
	print("test_room_picture_houses: %d checks, %s" % [_checks, "all passed" if _failures == 0 else "%d FAILED" % _failures])
	quit(_failures)


# --- Common ------------------------------------------------------------------------------------------------------------

## Builds the room from its document and runs the checks every room passes. Returns the room (in the tree).
func _room(id: String) -> Node3D:
	var r := EnvDoc.load_file("res://environments/%s.env.json" % id)
	_check("%s: schema %s" % [id, r["errors"]], (r["errors"] as Array).is_empty())
	var doc: Dictionary = r["doc"]
	var s := EnvChecks.static_checks(doc)
	for k: String in s:
		_check("%s: %s %s" % [id, k, s[k]], (s[k] as Array).is_empty())
	_check("%s: a cinema in the Room tab" % id, str(doc["room"].get("category", "")) == "cinema")
	var room: Node3D = EnvRoom.new()
	room.doc = doc
	root.add_child(room)
	await process_frame
	var stats := EnvChecks.measure(room)
	print("  %s: %s" % [id, stats])
	var over := EnvChecks.budget(stats, SPARE)
	_check("%s: well inside the headset's budget %s" % [id, over], over.is_empty())
	var blocked: Array = await EnvChecks.sight_line(self, room)
	_check("%s: a clear sight line from every seat (%d) %s" % [id, room.get_seats().size(), blocked], blocked.is_empty())
	var own: bool = room.get_seats().any(func(p: Vector3) -> bool: return p.length() < 0.05)
	_check("%s: the viewer's own seat is a room seat (pointing picks it)" % id, own)
	room.host.auto = false
	return room


func _system(room: Node3D, sid: String, kind: String) -> Node:
	var s: Node = room.host.system(sid)
	_check("system %s (%s)" % [sid, kind], s != null and str(s.get_script().call("spec").get("kind")) == kind)
	return s


## Runs the timeline for `seconds` with the film at `position` (moving while it plays).
func _play(room: Node3D, seconds: float, open: bool, playing: bool, position: float) -> float:
	var pos := position
	var t := 0.0
	# No player here: the playing channel is given as the player would give it.
	room.host.signals.fake("playback.playing", 1.0 if playing else 0.0)
	while t < seconds:
		room.host.snapshot_override = {"open": open, "playing": playing, "position": pos, "duration": 6000.0,
				"ended": open and not playing and pos >= 6000.0}
		room.host.step(DT)
		if playing:
			pos += DT
		t += DT
	return pos


func _lamps(room: Node3D) -> float:
	return float(room.host.param("light.house_lamps"))


func _done(room: Node3D) -> void:
	room.queue_free()
	await process_frame


# --- Shopfront 1906 ----------------------------------------------------------------------------------------------------

func _shopfront() -> void:
	var room := await _room("shopfront_1906")
	var hall := _system(room, "hall", "builder")
	_system(room, "seats", "seats")
	_system(room, "kit", "kit")
	_system(room, "screen_frame", "screen")
	_system(room, "atmosphere", "atmosphere")
	_check("shopfront: folding chairs in the builder's slots", room.find_child("Seats", true, false) != null
			and room.host.system("seats").params["model"] == "folding_chair")
	_check("shopfront: pressed tin", hall.params["tin_pattern"] == "pressed_tin")
	_check("shopfront: a framed sheet, no black masking", bool(hall.params["sheet_frame"])
			and not bool(room.host.system("screen_frame").params["masking"]))
	# The beam leaves from the tin booth's window.
	var booth := room.find_child("PieceBooth", true, false) as MeshInstance3D
	var window := booth.global_transform * booth.mesh.get_aabb().get_center() if booth != null else Vector3.INF
	var lens: Array = room.host.system("screen_frame").params["lens"]
	_check("shopfront: the beam's lens in the booth's window (%s)" % window,
			window.distance_to(Vector3(lens[0], lens[1], lens[2])) < 0.05)
	var air: Node = room.host.system("atmosphere")
	_check("shopfront: a dusty beam", float(air.params["beam_dust"]) >= 0.5 and float(air.params["beam_haze"]) > 0.0)
	# The piano setting is declared (it binds to the music system once sound lands).
	var decl: Array = room.declared_settings()
	_check("shopfront: its setting, the player piano (on)", decl.size() == 1 and decl[0]["name"] == "piano"
			and decl[0]["type"] == "bool" and room.host.setting("piano") == true)
	_check("shopfront: the common settings that apply: ritual and flickering lights",
			room.common_applies("ritual") and room.common_applies("flicker"))
	# The gas lamps flicker, and hold steady with Flickering lights off.
	var lo := 9.0
	var hi := 0.0
	for i in 60:
		room.host.step(1.0 / 30.0)
		lo = minf(lo, hall.flicker_factor())
		hi = maxf(hi, hall.flicker_factor())
	_check("shopfront: the gas lamps waver (%.3f..%.3f)" % [lo, hi], hi - lo > 0.02)
	room.host.set_setting("flicker", false)
	room.host.step(DT)
	_check("shopfront: Flickering lights off holds them steady", is_equal_approx(hall.flicker_factor(), 1.0))
	room.host.set_setting("flicker", true)
	# The ritual: the gas turned down, the street's glow dimmed; lights up at the end.
	var pos := _play(room, 2.0, false, false, 0.0)
	_check("shopfront: lamps up in the pre-show", _lamps(room) > 0.95)
	pos = _play(room, 12.0, true, true, 0.0)
	_check("shopfront: the ritual fired", room.host.timeline.fired.any(func(f: Array) -> bool: return f[0] == "ritual"))
	_check("shopfront: the gas down in the film (%.2f)" % _lamps(room), _lamps(room) < 0.25)
	_check("shopfront: the street dimmed", float(room.host.param("hall.street_glow")) < 0.3)
	_play(room, 6.0, true, false, 6000.0)
	_check("shopfront: lamps up after the end (%.2f)" % _lamps(room), _lamps(room) > 0.95)
	await _done(room)


# --- Streamline 1937 ---------------------------------------------------------------------------------------------------

func _streamline() -> void:
	var room := await _room("streamline_1937")
	var hall := _system(room, "hall", "builder")
	_system(room, "console", "kit")
	_system(room, "bands", "kit")
	var organ := _system(room, "organ", "motion")
	var festoon := _system(room, "festoon", "motion")
	_system(room, "cove", "atmosphere")
	_system(room, "cove_film", "atmosphere")
	_check("streamline: plain walls under the faience bands", hall.params["wall_treatment"] == "plain"
			and (room.host.system("bands").params["pieces"] as Array).all(func(p: Dictionary) -> bool:
				return p["piece"] == "curves"))
	_check("streamline: the organ console is the console kit's mesh", organ.call("target") != null
			and organ.call("target").name == "PieceStatic" and room.host.system("console").owned().has(organ.call("target")))
	_check("streamline: the festoon is in front of the picture until it rises",
			festoon.call("target") != null and festoon.call("target").is_in_group("env_in_front"))
	# The cove colours: gold by default, the lamps and the cove's haze; another choice builds the room again.
	_check("streamline: Changing by default", room.host.setting("cove") == "changing")
	var gold := Color(1.0, 0.74, 0.42)
	_check("streamline: gold lamps by default", (hall.params["house_lamp_colour"] as Color).is_equal_approx(gold))
	room.host.set_setting("cove", "jade")
	hall = room.host.system("hall")
	var jade := Color(0.5, 0.92, 0.72)
	_check("streamline: Jade turns the lamps and the cove jade",
			(hall.params["house_lamp_colour"] as Color).is_equal_approx(jade)
			and (room.host.param("cove.fog_colour") as Color).is_equal_approx(jade))
	# A steady colour does not cycle.
	_play(room, 25.0, false, false, 0.0)
	_check("streamline: Jade holds", (room.host.param("cove.fog_colour") as Color).is_equal_approx(jade))
	room.host.set_setting("cove", "changing")
	organ = room.host.system("organ")
	festoon = room.host.system("festoon")
	# Changing: the cove moves through the colours in the pre-show.
	var seen := {}
	var lamp_seen := {}
	var light: Node = room.host.system("light")
	var t := 0.0
	while t < 45.0:
		_play(room, 1.0, false, false, 0.0)
		var c: Color = room.host.param("cove.fog_colour")
		seen["%.1f %.1f %.1f" % [c.r, c.g, c.b]] = true
		var lc: Color = light.call("group_colour", "house")
		lamp_seen["%.1f %.1f %.1f" % [lc.r, lc.g, lc.b]] = true
		t += 1.0
	_check("streamline: the cove cycles before the film (%d colours seen)" % seen.size(), seen.size() >= 4)
	_check("streamline: and the lamps' glow with it (%d colours seen)" % lamp_seen.size(), lamp_seen.size() >= 4)
	_check("streamline: the cove glows before the film", float(room.host.param("cove.fog")) > 0.5
			and float(room.host.param("cove_film.fog")) < 0.05)
	# The ritual: the console rises from the pit, the festoon rises, the lamps go down.
	var pos := _play(room, 9.0, true, true, 0.0)
	_check("streamline: the ritual fired", room.host.timeline.fired.any(func(f: Array) -> bool: return f[0] == "ritual"))
	_check("streamline: the film starts: the cycle stops and the lamps go back to gold (%s)"
			% light.call("group_colour", "house"), not ("cove_cycle" in room.host.timeline.running())
			and (light.call("group_colour", "house") as Color).is_equal_approx(gold))
	_check("streamline: the festoon rising (%.2f)" % festoon.call("progress"), float(festoon.call("progress")) > 0.3)
	_check("streamline: the console rising (%.2f)" % organ.call("progress"), float(organ.call("progress")) > 0.1)
	pos = _play(room, 8.0, true, true, pos)
	_check("streamline: festoon up, console up, lamps down (%.2f, %.2f, %.2f)" % [festoon.call("progress"),
			organ.call("progress"), _lamps(room)], float(festoon.call("progress")) > 0.99
			and float(organ.call("progress")) > 0.99 and _lamps(room) < 0.2)
	# In the film the cove takes the film's colour.
	room.host.signals.fake("film.colour", Color(0.1, 0.3, 0.9))
	pos = _play(room, 15.0, true, true, pos)
	var fc: Color = room.host.param("cove_film.fog_colour")
	_check("streamline: in the film the cove follows the film's colour (%s)" % fc, fc.b > fc.r and fc.b > 0.6)
	_check("streamline: the film's cove shows in the film, the pre-show's goes", float(room.host.param("cove_film.fog")) > 0.4
			and float(room.host.param("cove.fog")) < 0.2)
	# The console goes down again 30 s into the film.
	pos = _play(room, 30.0, true, true, pos)
	_check("streamline: the console back in the pit (%.2f)" % organ.call("progress"), float(organ.call("progress")) < 0.01)
	# With Motion low the console and festoon do not travel: they are where they go at once.
	await _done(room)
	room = await _room("streamline_1937")
	room.host.set_setting("motion", 0.1)
	organ = room.host.system("organ")
	_play(room, 1.0, false, false, 0.0)
	_play(room, 0.5, true, true, 0.0)
	_check("streamline: reduced Motion: the console snaps up (%.2f)" % organ.call("progress"),
			float(organ.call("progress")) > 0.99)
	await _done(room)


# --- Pink Palace -------------------------------------------------------------------------------------------------------

func _pink_palace() -> void:
	var room := await _room("pink_palace")
	var hall := _system(room, "hall", "builder")
	var kit := _system(room, "kit", "kit")
	_system(room, "showing", "showing")
	_system(room, "screen_frame", "screen")
	_check("pink palace: a plush balcony", int(hall.params["balcony_rows"]) > 0 and hall.params["seat_model"] == "plush")
	var pieces: Array = kit.params["pieces"]
	_check("pink palace: pink and blue curves on the walls and the ceiling",
			pieces.filter(func(p: Dictionary) -> bool: return p["piece"] == "curves" and p["slot"] == "side_walls").size() == 2
			and pieces.filter(func(p: Dictionary) -> bool: return p["piece"] == "curves" and p["slot"] == "ceiling").size() >= 3)
	_check("pink palace: the balcony's moulded front", kit.call("problems").is_empty()
			and pieces.any(func(p: Dictionary) -> bool: return p["piece"] == "balcony_front" and p["slot"] == "balcony"))
	var balcony: Array = room.get_seats().filter(func(p: Vector3) -> bool: return p.y > 3.0)
	_check("pink palace: seats in the balcony (%d)" % balcony.size(), balcony.size() >= 30)
	_check("pink palace: no settings of its own; the pre-show applies", room.declared_settings().is_empty()
			and room.common_applies("ritual") and room.has_curtains)
	# The sunburst's lamps swell and fall slowly in the pre-show.
	var lo := 1.0
	var t := 0.0
	while t < 22.0:
		_play(room, DT, false, false, 0.0)
		lo = minf(lo, _lamps(room))
		t += DT
	_check("pink palace: the ceiling's lamps cycle in the pre-show (down to %.2f)" % lo, lo < 0.75 and lo > 0.4)
	# The ceremonial curtain parts, and the lamps stay down whatever the cycle was doing.
	var pos := _play(room, 15.0, true, true, 0.0)
	var log: Array = room.host.system("showing").log
	_check("pink palace: the curtains part in the ritual %s" % [log],
			log.any(func(a: Array) -> bool: return a[0] == "open_curtains"))
	_check("pink palace: lamps down in the film (%.2f)" % _lamps(room), _lamps(room) < 0.2)
	pos = _play(room, 20.0, true, true, pos)
	_check("pink palace: and they stay down (%.2f)" % _lamps(room), _lamps(room) < 0.2)
	await _done(room)


func _check(what: String, ok: bool) -> void:
	_checks += 1
	if not ok:
		_failures += 1
		print("FAIL: ", what)
