extends SceneTree

## Every built-in room's acoustics for spatial audio (docs/environments.md, "The version 4 document", `acoustics`):
## each room, built, gives the film's binaural renderer a room of its own (its walls, how much they reflect, its reverb
## time, its wet and late levels), the way spatial audio hands it over (scripts/play/spatial_audio.gd _room(): what
## reaches BinauralRenderer.set_room() when the room loads and when it changes). Then each room's impulse response
## through the engine's renderer, from the picture's centre to the seat: clarity (C80, the first 80 ms against the
## rest), the reverb against the direct sound, the decay. The rooms must not all sound alike: the cinemas spread, a
## nave rings longest and still keeps speech clear, a screening room is dry, the open-air rooms are drier still, and a
## room's reverb time fits its walls (Sabine: the mean absorption its box and rt60 imply is a real one).
## godot --headless --xr-mode off --path app --script res://tests/test_room_acoustics.gd

const EnvLibrary := preload("res://scripts/env/env_library.gd")
const SpatialAudio := preload("res://scripts/play/spatial_audio.gd")
const PACK := "res://audio/hrtf/sadie2_h5.fhrtf"
const RATE := 48000.0
const SEAT := Vector3(0, 1.2, 0)
## The scene rooms main.gd lists (main.gd ENVIRONMENTS), before the library's.
const SCENE_ROOMS: Array = [
	["void", "Void", "res://environments/void.tscn", []],
	["dim_room", "Dim room", "res://environments/dim_room.tscn", []],
	["cinema", "Cinema", "res://environments/cinema.tscn", []],
	["passthrough", "Passthrough", "res://environments/passthrough.tscn", []],
]
## Open air: almost no reverb.
const OUTDOORS := ["drive_in_1958", "rooftop_athens"]

var _failures := 0
var _checks := 0


## Stands in for main.gd: spatial audio reads main.env.
class StubMain:
	extends Node3D
	var env: Node3D


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var entries: Array = SCENE_ROOMS.duplicate()
	entries.append_array(EnvLibrary.BUILT_IN)
	entries.append_array(EnvLibrary.document_rooms())
	var main := StubMain.new()
	root.add_child(main)
	var sa: Node = SpatialAudio.new()
	sa.main = main
	var rooms := {}
	var measured := {}
	var categories := {}
	var previous := {}
	var changes := 0
	for e: Array in entries:
		var id := str(e[0])
		var room: Node3D = EnvLibrary.instantiate(e)
		main.add_child(room)
		main.env = room
		await process_frame
		var own: Dictionary = room.get_sound_room()
		var given: Dictionary = sa.call("_room", false)
		rooms[id] = given
		categories[id] = EnvLibrary.category_of(id)
		# A room document gives all five; a scene room (its script's get_sound_room()) leaves late to spatial audio.
		var document := room.get("host") != null
		_check("%s: its own acoustics (walls, reflect, rt60, wet%s) %s" % [id, ", late" if document else "",
				own.keys()], own.has("box") and own.has("rt60") and own.has("wet") and own.has("reflect")
				and (own.has("late") or not document))
		_check("%s: spatial audio hands the renderer its walls, reverb and levels" % id, given.has("min")
				and given.has("max") and given.has("late") and float(given["rt60"]) > 0.05 and given["enabled"])
		if not previous.is_empty() and given != previous:
			changes += 1
		previous = given
		var screen: Vector3 = room.get_screen_anchor().origin if room.has_method("get_screen_anchor") else Vector3(0, 1.2, -3)
		measured[id] = _measure(given, screen)
		var box := AABB(given["min"], given["max"] - given["min"])
		var m: Dictionary = measured[id]
		print("  %-24s box %5.1f x %4.1f x %5.1f  rt60 %.2f  wet %.2f  late %.2f | C80 %5.1f dB  reverb/direct %6.1f dB"
				% [id, box.size.x, box.size.y, box.size.z, float(given["rt60"]), float(given["wet"]),
				float(given["late"]), m["c80"], m["rd"]] + "  T20 %.2f s  alpha %.2f" % [m["t20"], _alpha(given)])
		main.remove_child(room)
		room.free()
		await process_frame
	_check("the renderer's room changed with every room (%d of %d)" % [changes, entries.size() - 1],
			changes == entries.size() - 1)
	sa.free()
	_compare(rooms, measured, categories)
	print("test_room_acoustics: %d checks, %s" % [_checks, "all passed" if _failures == 0 else "%d FAILED" % _failures])
	quit(_failures)


func _compare(rooms: Dictionary, measured: Dictionary, categories: Dictionary) -> void:
	var tuples := {}
	var cinemas: Array = []
	for id: String in rooms:
		var r: Dictionary = rooms[id]
		tuples[[snappedf(r["rt60"], 0.01), snappedf(r["wet"], 0.01), snappedf(r["late"], 0.01), r["reflect"]]] = true
		if categories[id] == "cinema":
			cinemas.append(id)
	_check("the rooms do not all sound alike (%d different of %d)" % [tuples.size(), rooms.size()],
			tuples.size() >= rooms.size() - 6)
	var c80: Array = cinemas.map(func(id: String) -> float: return measured[id]["c80"])
	var lo: float = c80.min()
	var hi: float = c80.max()
	_check("the cinemas spread: C80 from %.1f to %.1f dB" % [lo, hi], hi - lo > 12.0)
	var indoor: Array = cinemas.filter(func(id: String) -> bool: return not id in OUTDOORS)
	var rd: Array = indoor.map(func(id: String) -> float: return measured[id]["rd"])
	_check("the indoor cinemas' reverb against the direct sound spreads: %.1f to %.1f dB" % [rd.min(), rd.max()],
			float(rd.max()) - float(rd.min()) > 10.0)
	_check("the liveliest stays moderate: reverb %.1f dB under the direct sound" % rd.max(), float(rd.max()) < -6.0)
	var cinema_rt: Array = cinemas.map(func(id: String) -> float: return float(rooms[id]["rt60"]))
	_check("the cinemas' reverb times spread: %.2f to %.2f s" % [cinema_rt.min(), cinema_rt.max()],
			float(cinema_rt.max()) / float(cinema_rt.min()) > 4.0)
	var c := func(id: String) -> float: return measured[id]["c80"]
	var rt := func(id: String) -> float: return float(rooms[id]["rt60"])
	_check("the nave rings longest of the cinemas (rt60 %.2f s) and keeps speech clear (C80 %.1f dB)" % [rt.call("nave"),
			c.call("nave")], rt.call("nave") >= cinema_rt.max() and rt.call("nave") >= 2.5 and c.call("nave") > 0.0)
	_check("a nave is livelier than a 1928 atmospheric palace, which is livelier than a screening room",
			c.call("nave") < c.call("atmospheric_1928") and c.call("atmospheric_1928") < c.call("screening_room_1962"))
	_check("the 1928 palace rings 1.2-1.6 s, the screening room is dry (%.2f, %.2f s)" % [rt.call("atmospheric_1928"),
			rt.call("screening_room_1962")], rt.call("atmospheric_1928") >= 1.2 and rt.call("atmospheric_1928") <= 1.6
			and rt.call("screening_room_1962") <= 0.45)
	for id: String in OUTDOORS:
		_check("%s: open air, the driest of the cinemas (C80 %.1f dB)" % [id, c.call(id)], cinemas.all(
				func(o: String) -> bool: return o in OUTDOORS or c.call(o) < c.call(id)))
	_check("the modern flagship is drier than the 1937 streamline hall", c.call("flagship") > c.call("streamline_1937"))
	for id: String in rooms:
		if id in OUTDOORS or id == "dome" or id == "void" or id == "passthrough" or id == "drive_in":
			continue
		var a := _alpha(rooms[id])
		_check("%s: rt60 fits its box (Sabine's mean absorption %.2f)" % [id, a], a > 0.04 and a < 0.75)


## Sabine's mean absorption coefficient for the room's box and rt60: alpha = 0.161 V / (S rt60).
func _alpha(r: Dictionary) -> float:
	var s: Vector3 = (r["max"] - r["min"]).abs()
	var v := s.x * s.y * s.z
	var area := 2.0 * (s.x * s.y + s.y * s.z + s.z * s.x)
	return 0.161 * v / (area * float(r["rt60"]))


## The room's impulse response from the picture's centre to the seat, through the renderer: C80, reverb against the
## direct sound (dB) and T20 (the Schroeder decay from -5 to -25 dB, times 3).
func _measure(room: Dictionary, source: Vector3) -> Dictionary:
	var out := {"c80": 99.0, "rd": -99.0, "t20": 0.0}
	if not ClassDB.class_exists("BinauralRenderer"):
		return out
	var r: Object = ClassDB.instantiate("BinauralRenderer")
	r.load_hrtf(PACK)
	r.set_listener(Transform3D(Basis(), SEAT))
	r.set_sources([{"input": 0, "position": source, "reflections": true}])
	r.set_room(room)
	var seconds := clampf(float(room["rt60"]) * 1.3 + 0.3, 0.6, 5.0)
	var impulse := PackedFloat32Array()
	impulse.resize(int(RATE * seconds))
	impulse[0] = 1.0
	var y: PackedFloat32Array = r.render(impulse, 1)
	var n := y.size() / 2
	var e := PackedFloat32Array()
	e.resize(n)
	var peak := 0
	var peak_v := 0.0
	for i in n:
		e[i] = y[i * 2] * y[i * 2] + y[i * 2 + 1] * y[i * 2 + 1]
		if e[i] > peak_v:
			peak_v = e[i]
			peak = i
	var d_end := peak + int(RATE * 0.004)
	var c_end := peak + int(RATE * 0.08)
	var direct := 1e-12
	var early := 1e-12
	var late := 1e-12
	for i in n:
		if i < d_end:
			direct += e[i]
		elif i < c_end:
			early += e[i]
		else:
			late += e[i]
	out["c80"] = 10.0 * log((direct + early) / late) / log(10.0)
	out["rd"] = 10.0 * log((early + late) / direct) / log(10.0)
	# Schroeder's backward integral of everything after the direct sound.
	var total := early + late
	var left := total
	var t5 := -1.0
	var t25 := -1.0
	for i in range(d_end, n):
		left -= e[i]
		var db := 10.0 * log(maxf(left, 1e-20) / total) / log(10.0)
		if t5 < 0.0 and db <= -5.0:
			t5 = float(i) / RATE
		if t25 < 0.0 and db <= -25.0:
			t25 = float(i) / RATE
			break
	out["t20"] = (t25 - t5) * 3.0 if t5 >= 0.0 and t25 >= 0.0 else 0.0
	return out


func _check(what: String, ok: bool) -> void:
	_checks += 1
	if not ok:
		_failures += 1
		print("FAIL: " + what)
