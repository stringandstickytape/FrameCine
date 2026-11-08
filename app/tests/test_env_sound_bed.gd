extends SceneTree

## The sound_bed system (docs/environments.md, "Sound and music"): a small test room (not a shipped one) with a
## projector behind, rain round the viewer on a setting, a wall's rumble on film.bass, a far train and a passing moped
## passes the checks; the beds play on the room's bus under Environment, placed where the document says, rise in the
## pre-show and sit low in the film; rain follows its setting, the rumble the film's bass; one-shots come back every so
## often, travel, and play on a cue; silence plays nothing. Then the level check: every bed alone, at the slider's
## default, in the pre-show, in the film and under a film at the reference level; the test room's sum; and every shipped
## room with sound beds or music. Every sound the rooms want is there; ambient life's calls measured as life.gd plays
## them, at the distances the rooms give them. Prints the measured levels.
## godot --headless --xr-mode off --path app --script res://tests/test_env_sound_bed.gd

const Fixture := preload("res://tests/env_sound_fixture.gd")
const EnvAudio := preload("res://scripts/env/env_audio.gd")
const EnvSynth := preload("res://scripts/env/env_synth.gd")
const EnvDoc := preload("res://scripts/env/env_doc.gd")
const Registry := preload("res://scripts/env/systems/registry.gd")
const SoundBed := preload("res://scripts/env/systems/sound_bed.gd")
const Acoustics := preload("res://scripts/env/systems/acoustics.gd")

var _failures := 0
var _checks := 0

const ROOM := {
	"schema": 4, "name": "Sound bed test",
	"screen": {"center": [0.0, 1.6, -10.0], "size": [8.0, 3.4]},
	"systems": [
		{"system": "acoustics", "params": {"preset": "cinema"}},
		{"system": "sound_bed", "id": "clatter", "params": {"sound": "projector", "place": "at", "at": [0.0, 3.0, 6.0]}},
		{"system": "sound_bed", "id": "rain", "params": {"sound": "rain_glass", "place": "around", "radius": 2.5,
				"level": {"bind": "setting.rain", "range": [0.0, 1.0]}}},
		{"system": "sound_bed", "id": "wall", "params": {"sound": "wall_rumble", "place": "at", "at": [-8.0, 1.0, 0.0],
				"film_db": 0.0, "level": {"bind": "film.bass", "smooth": 0.3}}},
		{"system": "sound_bed", "id": "train", "params": {"sound": "train", "every": 900.0, "place": "at",
				"at": [-200.0, 2.0, -300.0], "reach": 300.0}},
		{"system": "sound_bed", "id": "moped", "params": {"sound": "moped", "place": "at", "at": [-30.0, 0.5, -20.0],
				"to": [30.0, 0.5, -20.0], "reach": 20.0}},
		{"system": "sound_bed", "id": "ticks", "params": {"sound": "tick", "every": 0.4, "jitter": 0.0}},
		{"system": "sound_bed", "id": "crater", "params": {"sound": "silence"}},
		{"system": "sound_bed", "id": "leaves", "params": {"sound": "rain_leaves", "place": "around", "voices": 2,
				"radius": 6.0, "level": {"bind": "weather.rain", "smooth": 0.2}}},
	],
	"settings": [
		{"name": "rain", "type": "range", "min": 0.0, "max": 1.0, "step": 0.1, "default": 1.0, "format": "percent",
			"label": "Rain", "description": "How hard it rains on the glass."}],
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
	_wanted()
	await _behaviour()
	await _levels()
	await _calls()
	print("test_env_sound_bed: %d checks, %s" % [_checks, "all passed" if _failures == 0 else "%d FAILED" % _failures])
	quit(_failures)


func _spec() -> void:
	_check("registered, a sound system", Registry.has("sound_bed") and Registry.spec("sound_bed")["kind"] == "sound")
	var s := Registry.spec("sound_bed")
	var designed := true
	var ours := true
	var capped := true
	var top := float(s["params"]["gain_db"]["max"])
	for n: String in SoundBed.SOUNDS:
		if n == "silence":
			continue
		var lv := float(SoundBed.LEVELS.get(n, 0.0))
		designed = designed and lv <= EnvAudio.LEVEL_TARGET_DB - 12.0
		ours = ours and n in EnvSynth.NAMES
		capped = capped and lv + top < EnvAudio.LEVEL_TARGET_DB - 2.0
	_check("every sound has a designed level 12 dB or more under the target", designed)
	_check("every sound but silence is synthesised", ours)
	_check("level, gain and film_db are live", s["params"]["level"]["live"] and s["params"]["gain_db"]["live"]
			and s["params"]["film_db"]["live"])
	_check("the gain can't lift a bed past the target with 2 dB to spare", capped)
	var bad := EnvDoc.validate({"schema": 4, "name": "x", "systems": [{"system": "sound_bed",
			"params": {"sound": "jingle"}}]})
	_check("an unknown sound refused", not bad["ok"])
	var bound := EnvDoc.validate({"schema": 4, "name": "x", "systems": [{"system": "sound_bed",
			"params": {"sound": "rain_leaves", "place": {"bind": "film.bass"}}}]})
	_check("a built-once parameter can't follow a channel", not bound["ok"])


func _behaviour() -> void:
	var room := Fixture.build(self, ROOM)
	await _frames(2)
	var problems: Array = await Fixture.checks(self, room)
	_check("the test room passes the checks %s" % [problems], problems.is_empty())
	var h: Node = room.host
	h.auto = true
	Fixture.set_state(room, "preshow")
	Fixture.finish_loading(room)
	await _frames(3)
	var clatter: Node = h.system("clatter")
	var rain: Node = h.system("rain")
	var wall: Node = h.system("wall")
	var train: Node = h.system("train")
	var moped: Node = h.system("moped")
	var ticks: Node = h.system("ticks")
	_check("the projector plays, a loop", clatter.playing() and clatter.is_loop())
	var p: Node = clatter.players()[0]
	_check("on the room's bus (%s), which sends to Environment" % p.get("bus"), p.get("bus") == StringName(
			Acoustics.BUS) and AudioServer.get_bus_send(AudioServer.get_bus_index(Acoustics.BUS)) == &"Environment")
	_check("behind the viewer, where the document puts it", p is AudioStreamPlayer3D
			and (p as Node3D).position.is_equal_approx(Vector3(0, 3, 6)))
	var round_ok: bool = rain.players().size() == 4
	for q: Node3D in rain.players():
		round_ok = round_ok and absf(Vector2(q.position.x, q.position.z).length() - 2.5) < 0.01
	_check("rain round the viewer: four voices at 2.5 m", round_ok)
	var starts: Array = rain.players().map(func(q: Node) -> float: return float(q.call("get_playback_position")))
	_check("each voice elsewhere in the loop %s" % [starts], absf(float(starts[0]) - float(starts[1])) > 0.5)
	_check("in the pre-show: at its designed level (%.1f)" % clatter.designed_db(),
			is_equal_approx(clatter.designed_db(), SoundBed.LEVELS["projector"]))
	# The film plays: down by film_db over the fade; paused: up again.
	Fixture.set_state(room, "playing")
	await _seconds(3.4)
	_check("in the film: 8 dB lower (%.1f, %s)" % [clatter.designed_db(), h.timeline.state],
			absf(clatter.designed_db() - (SoundBed.LEVELS["projector"] - 8.0)) < 0.2)
	_check("the wall's rumble keeps its level in the film (film_db 0)", is_equal_approx(wall._state_db, 0.0))
	Fixture.set_state(room, "paused")
	await _seconds(3.4)
	_check("paused: up again (%.1f)" % clatter.designed_db(),
			is_equal_approx(clatter.designed_db(), SoundBed.LEVELS["projector"]))
	# Rain follows its setting.
	h.set_setting("rain", 0.0)
	await _frames(2)
	_check("no rain: its voices stop", rain.players().is_empty() and not rain.playing())
	h.set_setting("rain", 0.5)
	await _frames(2)
	_check("rain again: half (%.2f), playing" % rain.params["level"], rain.playing()
			and is_equal_approx(float(rain.params["level"]), 0.5))
	_check("half: 6 dB down (%.1f)" % rain.designed_db(), absf(rain.designed_db()
			- (SoundBed.LEVELS["rain_glass"] - 6.02)) < 0.1)
	# The wall follows the film's bass.
	h.signals.fake("film.bass", 0.0)
	await _seconds(2.0)
	_check("no bass: the wall is quiet (%.3f)" % float(wall.params["level"]), not wall.playing())
	h.signals.fake("film.bass", 0.8)
	await _seconds(2.0)
	_check("bass: the wall rumbles (%.2f)" % float(wall.params["level"]), wall.playing()
			and absf(float(wall.params["level"]) - 0.8) < 0.05)
	h.signals.clear_fakes()
	# Rain on leaves follows the weather system's channel (0 with no weather system).
	var leaves: Node = h.system("leaves")
	_check("no weather: the leaves are quiet", not leaves.playing())
	h.signals.fake("weather.rain", 1.0)
	await _seconds(1.5)
	_check("weather.rain: rain on the leaves (%.2f), two voices" % float(leaves.params["level"]), leaves.playing()
			and leaves.players().size() == 2 and float(leaves.params["level"]) > 0.95)
	h.signals.fake("weather.rain", 0.0)
	await _seconds(2.0)
	_check("the rain stops: the leaves too", not leaves.playing())
	h.signals.clear_fakes()
	# One-shots.
	_check("the train waits for its period", train.players().is_empty())
	h.do_action("train.play", {})
	await _frames(2)
	_check("a cue plays the train now", train.playing())
	h.do_action("moped.play", {})
	await _frames(2)
	var m3: Node3D = moped.players()[0]
	var x0 := m3.position.x
	await _seconds(1.0)
	_check("the moped travels (%.1f -> %.1f)" % [x0, m3.position.x], m3.position.x > x0 + 4.0)
	var tick_count: int = ticks.plays
	await _seconds(1.3)
	_check("a one-shot every 0.4 s comes back (%d)" % (ticks.plays - tick_count), ticks.plays - tick_count >= 2)
	_check("silence plays nothing", h.system("crater").players().is_empty() and not h.system("crater").playing())
	h.do_action("clatter.stop", {"seconds": 0.5})
	await _seconds(0.8)
	_check("stop: faded out", clatter.designed_db() < -100.0)
	h.do_action("clatter.start", {"seconds": 0.5})
	await _seconds(0.8)
	_check("start: back", is_equal_approx(clatter.designed_db(), SoundBed.LEVELS["projector"]))
	# The room as a whole, in the pre-show (its loudest), the rain full.
	h.set_setting("rain", 1.0)
	h.signals.fake("film.bass", 0.6)
	Fixture.set_state(room, "preshow")
	await _seconds(0.5)
	var total: Dictionary = await Fixture.measure(self, 2.0)
	print("  the test room in the pre-show: %.1f dBFS RMS, peak %.1f (target %.1f)" % [total["rms"], total["peak"],
			EnvAudio.LEVEL_TARGET_DB])
	_check("the test room under the target with 2 dB to spare (%.1f)" % total["rms"],
			total["rms"] < EnvAudio.LEVEL_TARGET_DB - 2.0)
	room.queue_free()
	await _frames(3)


## Every bed alone, at the slider's default: in the pre-show, in the film, under a film at the reference level.
func _levels() -> void:
	print("  levels at the slider's default (dBFS RMS; the film's reference -20, the target %.1f):"
			% EnvAudio.LEVEL_TARGET_DB)
	print("  sound         designed  pre-show  in film  under film  peak")
	for sound: String in SoundBed.SOUNDS:
		if sound == "silence":
			continue
		var loop := sound in EnvSynth.LOOPS
		var doc := {"schema": 4, "name": "Level", "systems": [
				{"system": "sound_bed", "id": "bed", "params": {"sound": sound}}]}
		var room := Fixture.build(self, doc)
		await _frames(1)
		Fixture.set_state(room, "preshow")
		Fixture.finish_loading(room)
		await _frames(2)
		var bed: Node = room.host.system("bed")
		var w: AudioStreamWAV = bed.stream()
		var pre: float
		var film: float
		var under: float
		var peak: float
		if loop:
			# Over the whole loop: its swells and its sparse ticks counted as they come.
			var length := w.get_length()
			var a: Dictionary = await Fixture.measure(self, length)
			pre = a["rms"]
			peak = a["peak"]
			Fixture.set_state(room, "playing")
			await _seconds(3.2)
			film = (await Fixture.measure(self, minf(length, 4.0), 0.1))["rms"]
			under = (await Fixture.measure(self, minf(length, 4.0), 0.4, EnvSynth.REFERENCE_DB))["rms"]
		else:
			# A one-shot: its loudest second, from the stream and the player's volume.
			pre = EnvSynth.level_db(w) + bed.volume_db() + EnvAudio.DEFAULT_DB
			peak = EnvSynth.peak_db(w) + bed.volume_db() + EnvAudio.DEFAULT_DB
			film = pre - 8.0
			under = NAN
		print("  %-12s  %6.1f    %6.1f   %6.1f    %s    %6.1f" % [sound, SoundBed.LEVELS[sound], pre, film,
				("%6.1f" % under) if not is_nan(under) else "  (duck)", peak])
		_check("%s: at its designed level within 1.5 dB (%.1f, designed %.1f)" % [sound, pre,
				SoundBed.LEVELS[sound]], absf(pre - float(SoundBed.LEVELS[sound])) < 1.5)
		_check("%s: under the target with 10 dB to spare (%.1f)" % [sound, pre], pre < EnvAudio.LEVEL_TARGET_DB - 10.0)
		if loop:
			_check("%s: lower in the film (%.1f)" % [sound, film], film < pre - 6.0)
			_check("%s: under a film at the reference, 35 dB or more under it (%.1f)" % [sound, under],
					under < EnvSynth.REFERENCE_DB - 35.0)
		room.queue_free()
		await _frames(2)
	# Every shipped room with sound beds or music, at its loudest (the pre-show).
	var shipped := 0
	for f in DirAccess.get_files_at("res://environments"):
		if not f.ends_with(".env.json"):
			continue
		var doc: Dictionary = EnvDoc.load_file("res://environments/" + f)["doc"]
		var kinds: Array = doc.get("systems", []).map(func(e: Dictionary) -> String: return str(e["system"]))
		if not ("sound_bed" in kinds or "music" in kinds):
			continue
		shipped += 1
		var room := Fixture.build(self, doc)
		await _frames(1)
		Fixture.set_state(room, "preshow")
		Fixture.finish_loading(room)
		await _seconds(1.5)
		var a: Dictionary = await Fixture.measure(self, 3.0)
		Fixture.set_state(room, "starting")
		await _seconds(2.0)
		var b: Dictionary = await Fixture.measure(self, 3.0)
		var level := maxf(a["rms"], b["rms"])
		print("  %s: pre-show %.1f, starting %.1f dBFS RMS (target %.1f)" % [f, a["rms"], b["rms"],
				EnvAudio.LEVEL_TARGET_DB])
		_check("%s: its beds and music under the target with 2 dB to spare (%.1f)" % [f, level],
				level < EnvAudio.LEVEL_TARGET_DB - 2.0)
		room.queue_free()
		await _frames(2)
	print("  shipped rooms with sound beds or music: %d" % shipped)


## The sounds the rooms ask for (docs/environments.md, each room's "Sound wanted"; "Sound and music", "For the rooms").
const WANTED := {
	"Shopfront 1906": ["projector", "gas_hiss"], "Pink Palace": ["chime", "three_bells"],
	"Nave": ["wind", "candle"], "Reclaimed": ["rain_leaves", "drips", "bird", "wind", "crickets", "tawny_owl"],
	"Ice cinema": ["huskies", "wind", "ice_creak"], "Screen 3": ["wall_rumble"], "Drive-in": ["crickets", "train"],
	"Screening room 1962": ["fire", "hum", "three_bells"], "Athens rooftop": ["cicadas", "moped", "purr"],
	"Pillow Fort": ["radiator", "rain_glass"], "Bathysphere": ["hull_creak", "deep_hum", "whale"],
	"TV 1953": ["fire", "clock", "rain_glass", "purr", "tube_whine"], "TV 1972": ["radiator", "clock", "tube_whine"],
	"TV 1983": ["tape_load", "rain_glass", "tube_whine"], "TV 1987": ["vcr", "clock"],
	"TV 1993": ["radiator", "rain_glass", "vcr"], "Atmospheric 1928": ["fountain"],
}


func _wanted() -> void:
	var missing: Array = []
	for room: String in WANTED:
		for sound: String in WANTED[room]:
			if not (sound in SoundBed.SOUNDS and sound in EnvSynth.NAMES):
				missing.append("%s: %s" % [room, sound])
	_check("every sound the rooms want is there %s" % [missing], missing.is_empty())
	var calls := ["bird", "purr", "whale"]
	_check("the ambient life's calls are cue sounds", calls.all(func(n: String) -> bool: return n in EnvDoc.SOUNDS))
	_check("every cue sound is synthesised", EnvDoc.SOUNDS.all(func(n: String) -> bool: return n in EnvSynth.NAMES))


## Ambient life's calls as life.gd plays them (host.play_sound -> env_audio.play: a 3D player on Environment, unit
## size 3, at voice_db), at the distances the rooms give them: their loudest second at the slider's default.
func _calls() -> void:
	print("  ambient life's calls (loudest second, dBFS, the slider's default):")
	var room := Fixture.build(self, {"schema": 4, "name": "Calls", "systems": []})
	await _frames(2)
	# [sound, voice_db, metres from the seat, what]
	var cases := [["bird", -12.0, 3.0, "a bird at 3 m"], ["bird", -12.0, 8.0, "a bird on the roof's edge, 8 m"],
			["purr", -12.0, 1.5, "the cat by the seat, 1.5 m"], ["purr", -12.0, 4.0, "the cat at 4 m"],
			["whale", -12.0, 3.0, "the whale at 3 m (no fall-off)"], ["whale", -12.0, 22.0, "the whale's song, 22 m"],
			["whale", -14.0, 22.0, "the Bathysphere's whale (voice_db -14), 22 m"],
			["whale", -6.0, 22.0, "the whale at voice_db -6, 22 m"],
			["whale", -4.0, 22.0, "the whale at voice_db -4, 22 m"],
			["bird", -12.0, 3.0, "a bird at 3 m, no distance filter", true],
			["bird", -12.0, 8.0, "a bird at 8 m, no distance filter", true]]
	for c: Array in cases:
		var w := EnvSynth.stream(str(c[0]))
		var p := AudioStreamPlayer3D.new()
		p.unit_size = 3.0
		p.max_db = 0.0
		p.volume_db = float(c[1])
		if c.size() > 4:
			p.attenuation_filter_db = 0.0
		p.bus = EnvAudio.ENVIRONMENT
		p.stream = w
		root.add_child(p)
		var d := float(c[2])
		p.position = Vector3(0.0, 1.2, 0.0) + Vector3(-0.3, 0.55, -0.78).normalized() * d
		p.play()
		var env: PackedFloat32Array = await Fixture.envelope(self, w.get_length() + 0.2, 0.25)
		p.queue_free()
		var loud := -120.0
		for i in range(0, maxi(env.size() - 3, 1)):
			var sum := 0.0
			for j in range(i, mini(i + 4, env.size())):
				sum += db_to_linear(env[j]) ** 2
			loud = maxf(loud, linear_to_db(sqrt(sum / 4.0)) + EnvAudio.DEFAULT_DB)
		print("    %-48s %6.1f (designed %.1f, in film %.1f)" % [c[3], loud, SoundBed.LEVELS[c[0]],
				SoundBed.LEVELS[c[0]] - 8.0])
		_check("%s: under the target with 8 dB to spare (%.1f)" % [c[3], loud], loud < EnvAudio.LEVEL_TARGET_DB - 8.0)
		await _frames(2)
	room.queue_free()
	await _frames(2)


func _check(what: String, ok: bool) -> void:
	_checks += 1
	if not ok:
		_failures += 1
		print("FAIL: ", what)
