extends SceneTree

## The acoustics system (docs/environments.md, "Sound and music"): the room's bus is made under Environment (so it is
## ducked and on the slider); every preset is valid; the reverb follows live changes; the film keeps its own mix
## unless film is on (a room setting here), and the document's own acoustics section still goes over it; the room
## freed takes its reverb off; the Film bus is never touched. Then each preset's tail: a tick through the bus, its
## decay measured (T30, the fall from -5 to -35 dB, doubled) against the preset's rt60.
## godot --headless --xr-mode off --path app --script res://tests/test_env_acoustics.gd

const Fixture := preload("res://tests/env_sound_fixture.gd")
const EnvAudio := preload("res://scripts/env/env_audio.gd")
const EnvSynth := preload("res://scripts/env/env_synth.gd")
const EnvDoc := preload("res://scripts/env/env_doc.gd")
const Registry := preload("res://scripts/env/systems/registry.gd")
const Acoustics := preload("res://scripts/env/systems/acoustics.gd")

var _failures := 0
var _checks := 0

const ROOM := {
	"schema": 4, "name": "Acoustics test",
	"screen": {"center": [0.0, 1.6, -10.0], "size": [8.0, 3.4]},
	"systems": [
		{"system": "acoustics", "params": {"preset": "concrete_hall",
				"film": {"bind": "setting.film_room", "map": {"true": true, "false": false}}}},
	],
	"settings": [
		{"name": "film_room", "type": "bool", "default": false, "label": "Film in the hall",
			"description": "The film's own sound takes the hall's echo too."}],
}


func _init() -> void:
	_run.call_deferred()


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _seconds(s: float) -> void:
	await create_timer(s).timeout


func _run() -> void:
	_spec()
	await _behaviour()
	await _tails()
	print("test_env_acoustics: %d checks, %s" % [_checks, "all passed" if _failures == 0 else "%d FAILED" % _failures])
	quit(_failures)


func _spec() -> void:
	_check("registered, a sound system", Registry.has("acoustics") and Registry.spec("acoustics")["kind"] == "sound")
	var s := Registry.spec("acoustics")
	_check("film is off by default", s["params"]["film"]["default"] == false)
	var valid := true
	for name: String in Acoustics.PRESETS:
		var p: Dictionary = Acoustics.PRESETS[name]
		for k: String in Acoustics.KEYS:
			var spec: Dictionary = s["params"][k]
			valid = valid and p.has(k) and float(p[k]) >= 0.0 and float(p[k]) <= float(spec["max"])
		var doc := {"schema": 4, "name": "x", "systems": [{"system": "acoustics", "params": {"preset": name}}]}
		valid = valid and EnvDoc.validate(doc)["ok"]
	_check("every preset has every number, in range, and validates", valid)
	_check("a longer rt60 is a bigger room", Acoustics.room_size_for(0.5) < Acoustics.room_size_for(2.0)
			and Acoustics.room_size_for(2.0) < Acoustics.room_size_for(5.0))
	var bad := EnvDoc.validate({"schema": 4, "name": "x", "systems": [{"system": "acoustics",
			"params": {"preset": "opera"}}]})
	_check("an unknown preset refused", not bad["ok"])


func _film_effects() -> Array:
	var f := AudioServer.get_bus_index(&"Film")
	var out: Array = []
	if f < 0:
		return out
	for i in AudioServer.get_bus_effect_count(f):
		out.append([AudioServer.get_bus_effect(f, i), AudioServer.is_bus_effect_enabled(f, i)])
	return out


func _behaviour() -> void:
	EnvAudio.ensure_buses()
	var film_before := _film_effects()
	var room := Fixture.build(self, ROOM)
	await _frames(2)
	var problems: Array = await Fixture.checks(self, room)
	_check("the test room passes the checks %s" % [problems], problems.is_empty())
	var h: Node = room.host
	h.auto = true
	Fixture.set_state(room, "preshow")
	await _frames(2)
	var b := AudioServer.get_bus_index(Acoustics.BUS)
	_check("the room's bus is made", b >= 0)
	_check("it sends to Environment", AudioServer.get_bus_send(b) == &"Environment")
	var sys: Node = h.system("acoustics")
	var r: AudioEffectReverb = sys.reverb()
	var v: Dictionary = sys.values()
	_check("the hall's reverb is on (wet %.2f)" % r.wet, AudioServer.is_bus_effect_enabled(b, 0)
			and is_equal_approx(r.wet, float(Acoustics.PRESETS["concrete_hall"]["wet"])))
	_check("its room size from its rt60", is_equal_approx(r.room_size, Acoustics.room_size_for(float(v["rt60"]),
			float(v["damping"]))))
	_check("its echo and predelay", is_equal_approx(r.predelay_feedback, 0.35)
			and is_equal_approx(r.predelay_msec, 60.0))
	# Live changes.
	h.fade("acoustics.wet", 0.1, 0.0)
	h.fade("acoustics.rt60", 4.0, 0.0)
	await _frames(3)
	_check("live: wet follows (%.2f)" % r.wet, absf(r.wet - 0.1) < 0.01)
	_check("live: rt60 follows (room size %.3f)" % r.room_size, absf(r.room_size - Acoustics.room_size_for(4.0, r.damping))
			< 0.001)
	h.fade("acoustics.wet", 0.0, 0.0)
	await _frames(3)
	_check("wet 0: the effect is off", not AudioServer.is_bus_effect_enabled(b, 0))
	h.release("acoustics.wet", 0.0)
	h.release("acoustics.rt60", 0.0)
	await _frames(3)
	_check("released: the preset's again (wet %.2f)" % r.wet,
			is_equal_approx(r.wet, float(Acoustics.PRESETS["concrete_hall"]["wet"])))
	# The film: its own mix unless film is on.
	var sr: Dictionary = h.sound_room()
	_check("film off: no room for the film's sound from it %s" % [sr], not sr.has("rt60") and not sr.has("wet"))
	h.set_setting("film_room", true)
	await _frames(3)
	sr = h.sound_room()
	_check("film on (the setting): rt60 %s, wet %s" % [sr.get("rt60"), sr.get("wet")],
			is_equal_approx(float(sr.get("rt60", 0.0)), 2.4) and is_equal_approx(float(sr.get("wet", 0.0)), 0.6))
	_check("film on: the walls reflect %s" % [sr.get("reflect")], sr.get("reflect") is Array
			and (sr["reflect"] as Array).size() == 6 and is_equal_approx(float(sr["reflect"][0]), 0.6))
	h.set_setting("film_room", false)
	await _frames(3)
	_check("film off again: none", not h.sound_room().has("rt60"))
	_check("the Film bus untouched", _film_effects() == film_before)
	room.queue_free()
	await _frames(3)
	_check("the room freed: its reverb off", not AudioServer.is_bus_effect_enabled(b, 0))
	# The document's own acoustics section goes over the system's.
	var doc := {"schema": 4, "name": "Doc wins", "acoustics": {"rt60": 3.0, "wet": 0.2},
		"systems": [{"system": "acoustics", "params": {"preset": "stone_nave", "film": true}}]}
	var room2 := Fixture.build(self, doc)
	await _frames(2)
	sr = room2.host.sound_room()
	_check("the document's acoustics wins (rt60 %s, wet %s)" % [sr.get("rt60"), sr.get("wet")],
			is_equal_approx(float(sr.get("rt60", 0.0)), 3.0) and is_equal_approx(float(sr.get("wet", 0.0)), 0.2))
	_check("what it doesn't give comes from the system (reflect)", sr.get("reflect") is Array
			and is_equal_approx(float(sr["reflect"][0]), 0.55))
	room2.queue_free()
	await _frames(3)
	_check("the Film bus still untouched", _film_effects() == film_before)


## Each preset with a reverb: a tick through the room's bus, dry 0 and wet 1, its tail's decay.
func _tails() -> void:
	print("  preset         rt60   measured (T30)  room size")
	var tick: AudioStreamWAV = EnvSynth.stream("tick")
	for name: String in Acoustics.PRESETS:
		var p: Dictionary = Acoustics.PRESETS[name]
		if float(p["wet"]) <= 0.0:
			print("  %-13s  %4.2f   (dry)" % [name, p["rt60"]])
			continue
		var doc := {"schema": 4, "name": "Tail", "systems": [{"system": "acoustics",
				"params": {"preset": name, "echo": 0.0}}]}
		var room := Fixture.build(self, doc)
		await _frames(2)
		var r: AudioEffectReverb = room.host.system("acoustics").reverb()
		r.dry = 0.0
		r.wet = 1.0
		await _seconds(0.3)
		var pl := AudioStreamPlayer.new()
		pl.stream = tick
		pl.bus = StringName(Acoustics.BUS)
		pl.volume_db = 6.0
		root.add_child(pl)
		pl.play()
		var env: PackedFloat32Array = await Fixture.envelope(self, float(p["rt60"]) * 1.2 + 0.8, 0.02)
		pl.queue_free()
		var t30 := _t30(env, 0.02)
		print("  %-13s  %4.2f   %5.2f           %.3f" % [name, p["rt60"], t30, r.room_size])
		if float(p["rt60"]) >= Acoustics.TAIL_SECONDS[0]:
			_check("%s: its tail within 20%% of its rt60 (%.2f measured, %.2f set)" % [name, t30, p["rt60"]],
					absf(t30 / float(p["rt60"]) - 1.0) < 0.2)
		else:
			# Shorter than the engine's reverb can be: its smallest room (a little wet keeps it short to the ear).
			_check("%s: the engine's shortest tail (%.2f measured, %.2f set)" % [name, t30, p["rt60"]],
					is_zero_approx(r.room_size) and t30 < 0.8)
		room.queue_free()
		await _frames(3)


## The time to fall 60 dB from the fall from -5 to -35 dB under the envelope's peak (a line fitted to it), or 0.
func _t30(env: PackedFloat32Array, window: float) -> float:
	var top := -200.0
	var at := 0
	for i in env.size():
		if env[i] > top:
			top = env[i]
			at = i
	var xs := PackedFloat32Array()
	var ys := PackedFloat32Array()
	for i in range(at, env.size()):
		var d := env[i] - top
		if d <= -5.0 and d >= -35.0:
			xs.append(i * window)
			ys.append(env[i])
		elif d < -35.0:
			break
	if xs.size() < 3:
		return 0.0
	var mx := 0.0
	var my := 0.0
	for i in xs.size():
		mx += xs[i]
		my += ys[i]
	mx /= xs.size()
	my /= xs.size()
	var num := 0.0
	var den := 0.0
	for i in xs.size():
		num += (xs[i] - mx) * (ys[i] - my)
		den += (xs[i] - mx) * (xs[i] - mx)
	var slope := num / den if den > 0.0 else 0.0
	return -60.0 / slope if slope < 0.0 else 0.0


func _check(what: String, ok: bool) -> void:
	_checks += 1
	if not ok:
		_failures += 1
		print("FAIL: ", what)
