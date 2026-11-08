extends SceneTree

## Three rooms of the cinema set (docs/environments.md, "Room: Shopfront 1906", "Room: Streamline 1937", "Room: Pink
## Palace"), each its document alone: built headless as the app builds it (env_room.gd) and checked for what makes it
## that room. Every room: the checks (schema, comfort, licences, names, no people), the headset's budget with room to
## spare, a clear sight line from every seat, the viewer's own seat at the origin among the room's seats, its systems,
## its settings, and its ritual run through the timeline (lamps down, curtains or festoon, the organ console). And its
## sound (docs/environments.md, "Sound and music"): the beds and instruments on the room's bus, its acoustics, the
## projector behind and the player piano that starts with the film and follows its jumps (Shopfront), the organ that
## plays as the console rises and closes as it sinks (Streamline), the house bells in the ritual (Pink Palace), and the
## level under the film, measured.
## godot --headless --xr-mode off --path app --script res://tests/test_room_picture_houses.gd

const RoomSound := preload("res://tests/room_sound_checks.gd")
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


## The room's sound systems on the room's bus, its acoustics.
func _sound_systems(label: String, room: Node3D, ids: Array, preset: String, rt60: float) -> void:
	var bus := RoomSound.on_room_bus(room, ids)
	_check("%s: %s on the room's bus, under Environment (the slider, the duck, Ambience) %s" % [label, ids, bus],
			bus.is_empty())
	var ac := RoomSound.acoustics(room, preset, rt60)
	_check("%s: the acoustics %s (rt60 %.2f) %s" % [label, preset, rt60, ac], ac.is_empty())


## The level check, in real time.
func _sound_levels(label: String, room: Node3D) -> void:
	var r: Dictionary = await RoomSound.levels(self, room, label)
	for v: Array in RoomSound.verdicts(label, r):
		_check(v[0], v[1])


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
	# The piano setting: the music system's player piano on or off.
	var decl: Array = room.declared_settings()
	_check("shopfront: its setting, the player piano (on)", decl.size() == 1 and decl[0]["name"] == "piano"
			and decl[0]["type"] == "bool" and room.host.setting("piano") == true)
	# The sound: the projector's clatter from the booth behind, the gas's hiss, the player piano by the screen.
	_sound_systems("shopfront", room, ["projector", "gas", "piano"], "shopfront", 0.9)
	var projector: Node = room.host.system("projector")
	var clatter: Array = projector.players()
	_check("shopfront: the projector clatters from the booth behind (%s)" % [clatter.map(func(p: Node) -> Variant:
			return (p as Node3D).position)], projector.is_loop() and clatter.size() == 1
			and (clatter[0] as Node3D).position.distance_to(Vector3(lens[0], lens[1], lens[2])) < 0.6)
	_check("shopfront: the gas lamps' hiss", room.host.system("gas").is_loop() and room.host.system("gas").playing())
	var piano: Node = room.host.system("piano")
	_check("shopfront: a player piano by the screen", str(piano.params["instrument"]) == "piano" and piano.is_ready()
			and (piano.owned()[0] as Node3D).position.z < -6.0)
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
	_check("shopfront: the piano silent in the pre-show (%d notes)" % piano.notes_played, piano.notes_played == 0
			and not piano.sounding())
	pos = _play(room, 3.0, true, true, 0.0)
	_check("shopfront: the film starts (%s): the piano plays (%d notes)" % [room.host.timeline.state,
			piano.notes_played], room.host.timeline.state == "starting" and piano.notes_played > 4 and piano.sounding())
	pos = _play(room, 9.0, true, true, pos)
	_check("shopfront: the ritual fired", room.host.timeline.fired.any(func(f: Array) -> bool: return f[0] == "ritual"))
	_check("shopfront: the gas down in the film (%.2f)" % _lamps(room), _lamps(room) < 0.25)
	_check("shopfront: the street dimmed", float(room.host.param("hall.street_glow")) < 0.3)
	# The piano follows the film's jumps: a sudden loud moment, an agitato; calm again, its oom-pah.
	_check("shopfront: in the film it plays on, an oom-pah (%s, drive %.2f)" % [piano.bar_kind, piano.params["drive"]],
			piano.sounding() and piano.bar_kind == "oompah")
	room.host.signals.fake("film.transient", 1.0)
	pos = _play(room, 4.0, true, true, pos)
	_check("shopfront: a jump in the film: the piano's agitato (%s, drive %.2f)" % [piano.bar_kind,
			piano.params["drive"]], piano.bar_kind == "agitato" and float(piano.params["drive"]) > 0.65)
	room.host.signals.fake("film.transient", 0.0)
	pos = _play(room, 8.0, true, true, pos)
	_check("shopfront: calm again (%s, drive %.2f)" % [piano.bar_kind, piano.params["drive"]],
			piano.bar_kind == "oompah" and float(piano.params["drive"]) < 0.4)
	room.host.set_setting("piano", false)
	pos = _play(room, 3.0, true, true, pos)
	_check("shopfront: Player piano off: silent (%d voices)" % piano.voices_sounding(), not piano.sounding())
	room.host.set_setting("piano", true)
	pos = _play(room, 2.0, true, true, pos)
	_check("shopfront: and on again", piano.sounding())
	_play(room, 6.0, true, false, 6000.0)
	_check("shopfront: lamps up after the end (%.2f)" % _lamps(room), _lamps(room) > 0.95)
	_check("shopfront: the piano rests after the end", not piano.sounding())
	await _sound_levels("shopfront", room)
	await _done(room)


# --- Streamline 1937 ---------------------------------------------------------------------------------------------------

func _streamline() -> void:
	var room := await _room("streamline_1937")
	var hall := _system(room, "hall", "builder")
	var kit := _system(room, "moderne", "kit")
	_system(room, "console", "kit")
	var organ := _system(room, "organ", "motion")
	var festoon := _system(room, "festoon", "motion")
	_system(room, "screen_frame", "screen")
	_system(room, "air", "atmosphere")
	# Since 2026-11-08 the hall is the moderne kit's (kit/streamline.gd): its own ceiling of coves, proscenium, bands.
	var kinds: Array = (kit.params["pieces"] as Array).map(func(p: Dictionary) -> String: return str(p["piece"]))
	_check("streamline: the moderne hall and the stepped proscenium over plain walls (%s)" % [kinds],
			hall.params["wall_treatment"] == "plain" and kinds.has("moderne_hall") and kinds.has("ziggurat")
			and kit.call("problems").is_empty())
	_check("streamline: the organ console moves whole on its lift", organ.call("target") != null
			and organ.call("target").name == "Console" and room.host.system("console").owned().has(organ.call("target")))
	_check("streamline: the festoon is in front of the picture until it rises",
			festoon.call("target") != null and festoon.call("target").is_in_group("env_in_front"))
	# The cove colours: gold by default; a steady choice holds; Changing cycles before the film.
	_check("streamline: Changing by default", room.host.setting("cove") == "changing")
	var gold := Color(1.0, 0.72, 0.4)
	_check("streamline: gold coves by default", (kit.call("cove_colour_now") as Color).is_equal_approx(gold))
	# The setting moves only live parameters: the room is not built again (the console stays where it is).
	room.host.set_setting("cove", "jade")
	var jade := Color(0.42, 0.92, 0.7)
	_play(room, 25.0, false, false, 0.0)
	_check("streamline: Jade turns the coves jade, and holds, without building the room again",
			(kit.call("cove_colour_now") as Color).is_equal_approx(jade) and room.host.system("moderne") == kit)
	room.host.set_setting("cove", "changing")
	var seen := {}
	var t := 0.0
	while t < 45.0:
		_play(room, 1.0, false, false, 0.0)
		var c: Color = kit.call("cove_colour_now")
		seen["%.1f %.1f %.1f" % [c.r, c.g, c.b]] = true
		t += 1.0
	_check("streamline: the coves cycle before the film (%d colours seen)" % seen.size(), seen.size() >= 4)
	# The organ: the console rises from the pit as the room opens and the organ plays.
	_sound_systems("streamline", room, ["pipes"], "cinema", 0.7)
	var pipes: Node = room.host.system("pipes")
	_check("streamline: the organ at the console, a theatre organ", str(pipes.params["instrument"]) == "organ"
			and str(pipes.params["stop"]) == "theatre" and (pipes.owned()[0] as Node3D).position.z < -11.0)
	_check("streamline: in the pre-show the console up (%.2f) and the organ playing (%d notes)" % [
			organ.call("progress"), pipes.notes_played], float(organ.call("progress")) > 0.99 and pipes.sounding())
	# The ritual: the organ's cadence, the console down, the festoon up, the lamps down.
	# The cadence comes once the bar playing now has ended (the organ writes its bars a little ahead).
	var pos := 0.0
	var cadence := false
	for i in 30:
		pos = _play(room, 0.2, true, true, pos)
		cadence = cadence or pipes.bar_kind == "flourish"
	_check("streamline: the ritual fired", room.host.timeline.fired.any(func(f: Array) -> bool: return f[0] == "ritual"))
	_check("streamline: the film starts: the organ's closing cadence", cadence)
	_check("streamline: the cycle stops", not ("cove_cycle" in room.host.timeline.running()))
	_check("streamline: the festoon rising (%.2f)" % festoon.call("progress"), float(festoon.call("progress")) > 0.1)
	pos = _play(room, 20.0, true, true, pos)
	_check("streamline: festoon up, console down, lamps down (%.2f, %.2f, %.2f)" % [festoon.call("progress"),
			organ.call("progress"), _lamps(room)], float(festoon.call("progress")) > 0.99
			and float(organ.call("progress")) < 0.01 and _lamps(room) < 0.2)
	_check("streamline: the organ rests for the film", pipes.resting() and not pipes.sounding())
	# In the film the coves take the film's colour, at a glow.
	room.host.signals.fake("film.colour", Color(0.1, 0.3, 0.9))
	pos = _play(room, 15.0, true, true, pos)
	var fc: Color = kit.call("cove_colour_now")
	_check("streamline: in the film the coves follow the film's colour (%s)" % fc, fc.b > fc.r and fc.b > 0.5)
	await _sound_levels("streamline", room)
	# With Motion low the console and the festoon do not travel: they are where they go at once.
	await _done(room)
	room = await _room("streamline_1937")
	room.host.set_setting("motion", 0.1)
	organ = room.host.system("organ")
	_play(room, 4.0, false, false, 0.0)
	_check("streamline: reduced Motion: the console snaps up (%.2f)" % organ.call("progress"),
			float(organ.call("progress")) > 0.99)
	# Pre-show off: no prelude, no console, no organ.
	pipes = room.host.system("pipes")
	room.host.set_setting("ritual", false)
	_play(room, 12.0, true, true, 0.0)
	var notes: int = pipes.notes_played
	_play(room, 2.0, false, false, 0.0)
	_play(room, 20.0, false, false, 0.0)
	_check("streamline: Pre-show off: the console stays down (%.2f), the organ silent (%d notes)" % [
			organ.call("progress"), pipes.notes_played - notes], pipes.notes_played == notes and not pipes.sounding()
			and float(organ.call("progress")) < 0.01)
	room.host.set_setting("ritual", true)
	await _done(room)


# --- Pink Palace -------------------------------------------------------------------------------------------------------

func _pink_palace() -> void:
	var room := await _room("pink_palace")
	var hall := _system(room, "hall", "builder")
	var kit := _system(room, "palace", "kit")
	var sunburst := _system(room, "sunburst", "kit")
	var festoon := _system(room, "festoon", "motion")
	_system(room, "screen_frame", "screen")
	_check("pink palace: a plush balcony", int(hall.params["balcony_rows"]) > 0 and hall.params["seat_model"] == "plush")
	var pieces: Array = kit.params["pieces"]
	# Since 2026-11-08 (the deep pass): the hall inside a shell (kit/pink_palace.gd), its dome a kit of its own.
	_check("pink palace: the shell hall, its rings, its buttoned balcony, a dome of its own",
			kit.call("problems").is_empty() and sunburst.call("problems").is_empty()
			and ["pink_hall", "pink_proscenium", "pink_balcony"].all(func(n: String) -> bool:
				return pieces.any(func(p: Dictionary) -> bool: return p["piece"] == n))
			and (sunburst.params["pieces"] as Array).any(func(p: Dictionary) -> bool: return p["piece"] == "pink_dome"))
	var balcony: Array = room.get_seats().filter(func(p: Vector3) -> bool: return p.y > 3.0)
	_check("pink palace: seats in the balcony (%d)" % balcony.size(), balcony.size() >= 30)
	_check("pink palace: no settings of its own; the pre-show applies; a festoon, not the pre-show's curtains",
			room.declared_settings().is_empty() and room.common_applies("ritual") and not room.has_curtains
			and festoon.call("target") != null and festoon.call("target").is_in_group("env_in_front"))
	_sound_systems("pink palace", room, ["bells"], "cinema", 0.7)
	var bells: Node = room.host.system("bells")
	_check("pink palace: the house bells by the stage, a one-shot", str(bells.params["sound"]) == "three_bells"
			and not bells.is_loop() and float(bells.params["every"]) == 0.0)
	# The sunburst's lamps (the dome's) swell and fall slowly in the pre-show; the house lamps hold.
	var lo := 1.0
	var house_lo := 1.0
	var t := 0.0
	while t < 22.0:
		_play(room, DT, false, false, 0.0)
		lo = minf(lo, float(room.host.param("sunburst.cove")))
		house_lo = minf(house_lo, _lamps(room))
		t += DT
	_check("pink palace: the sunburst's lamps cycle in the pre-show (down to %.2f), the house's hold (%.2f)" % [lo,
			house_lo], lo < 0.75 and lo > 0.4 and house_lo > 0.99)
	_check("pink palace: no bells in the pre-show", bells.plays == 0)
	# The festoon rises, and the lamps stay down whatever the cycle was doing.
	var pos := _play(room, 25.0, true, true, 0.0)
	_check("pink palace: the ritual rings the house bells once, through their bed (%d; cue sounds %s)" % [bells.plays,
			room.host.sounds], bells.plays == 1 and room.host.sounds.is_empty())
	_check("pink palace: the festoon rises in the ritual (%.2f)" % festoon.call("progress"),
			float(festoon.call("progress")) > 0.99)
	_check("pink palace: lamps down in the film (%.2f)" % _lamps(room), _lamps(room) < 0.2)
	pos = _play(room, 20.0, true, true, pos)
	_check("pink palace: and they stay down (%.2f)" % _lamps(room), _lamps(room) < 0.2)
	_check("pink palace: the bells once only", bells.plays == 1)
	await _sound_levels("pink palace", room)
	await _done(room)


func _check(what: String, ok: bool) -> void:
	_checks += 1
	if not ok:
		_failures += 1
		print("FAIL: ", what)
