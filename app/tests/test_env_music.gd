extends SceneTree

## The music system (docs/environments.md, "Sound and music"): a small test room (not a shipped one) with a player
## piano in a shopfront passes the checks; it is silent in the pre-show and starts its piece when the film starts; its
## A tune comes back; a jump in the film (film.transient) makes it faster and turns it to an agitato; its setting off
## silences it. An organ plays in the pre-show, plays a closing cadence and rests, and is silent in the film. Then the
## level check: each instrument at the slider's default alone, in the film and under a film at the reference level.
## godot --headless --xr-mode off --path app --script res://tests/test_env_music.gd

const Fixture := preload("res://tests/env_sound_fixture.gd")
const EnvAudio := preload("res://scripts/env/env_audio.gd")
const EnvSynth := preload("res://scripts/env/env_synth.gd")
const EnvDoc := preload("res://scripts/env/env_doc.gd")
const Registry := preload("res://scripts/env/systems/registry.gd")
const Music := preload("res://scripts/env/systems/music.gd")
const Acoustics := preload("res://scripts/env/systems/acoustics.gd")

var _failures := 0
var _checks := 0

const PIANO_ROOM := {
	"schema": 4, "name": "Piano test",
	"screen": {"center": [0.0, 1.6, -10.0], "size": [8.0, 3.4]},
	"systems": [
		{"system": "acoustics", "params": {"preset": "shopfront"}},
		{"system": "music", "id": "piano", "params": {"instrument": "piano", "at": [-3.0, 0.8, -6.0],
				"drive": {"bind": "film.transient", "range": [0.3, 1.0], "smooth": 0.5},
				"on": {"bind": "setting.piano"}}},
	],
	"settings": [
		{"name": "piano", "type": "bool", "default": true, "label": "Piano",
			"description": "The player piano plays along with the film."}],
}

const ORGAN_ROOM := {
	"schema": 4, "name": "Organ test",
	"screen": {"center": [0.0, 1.6, -10.0], "size": [8.0, 3.4]},
	"systems": [
		{"system": "acoustics", "params": {"preset": "cinema"}},
		{"system": "music", "id": "organ", "params": {"instrument": "organ", "stop": "theatre"}},
	],
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
	await _piano()
	await _organ()
	await _levels()
	print("test_env_music: %d checks, %s" % [_checks, "all passed" if _failures == 0 else "%d FAILED" % _failures])
	quit(_failures)


func _spec() -> void:
	_check("registered, a music system", Registry.has("music") and Registry.spec("music")["kind"] == "music")
	var s := Registry.spec("music")
	var top := float(s["params"]["gain_db"]["max"])
	var designed := true
	var capped := true
	for n: String in Music.INSTRUMENTS:
		designed = designed and float(Music.LEVELS[n]) <= EnvAudio.LEVEL_TARGET_DB - 12.0
		capped = capped and float(Music.LEVELS[n]) + top < EnvAudio.LEVEL_TARGET_DB - 2.0
	_check("each instrument's designed level 12 dB or more under the target", designed)
	_check("the gain can't lift it past the target with 2 dB to spare", capped)
	_check("drive, on, level and film_db are live", s["params"]["drive"]["live"] and s["params"]["on"]["live"]
			and s["params"]["level"]["live"] and s["params"]["film_db"]["live"])
	var bad := EnvDoc.validate({"schema": 4, "name": "x", "systems": [{"system": "music",
			"params": {"instrument": "kazoo"}}]})
	_check("an unknown instrument refused", not bad["ok"])


func _piano() -> void:
	var room := Fixture.build(self, PIANO_ROOM)
	await _frames(2)
	var problems: Array = await Fixture.checks(self, room)
	_check("the piano room passes the checks %s" % [problems], problems.is_empty())
	var h: Node = room.host
	h.auto = true
	Fixture.set_state(room, "preshow")
	Fixture.finish_loading(room)
	await _frames(2)
	var piano: Node = h.system("piano")
	_check("its notes are made", piano.is_ready())
	await _seconds(1.5)
	_check("silent in the pre-show (%d notes)" % piano.notes_played, piano.notes_played == 0 and not piano.sounding())
	var p: Node = piano.owned()[0]
	_check("on the room's bus, where the document puts it", p.get("bus") == StringName(Acoustics.BUS)
			and p is AudioStreamPlayer3D and (p as Node3D).position.is_equal_approx(Vector3(-3, 0.8, -6)))
	Fixture.set_state(room, "starting")
	await _seconds(2.5)
	_check("the film starts (%s): the piano plays (%d notes)" % [h.timeline.state, piano.notes_played],
			h.timeline.state == "starting" and piano.notes_played > 4 and piano.sounding())
	_check("an oom-pah at drive 0.3 (%s)" % piano.bar_kind, piano.bar_kind == "oompah")
	_check("its piece has a key and the form A A2 B A %s" % [piano.piece()["form"]],
			piano.piece()["form"] == ["A", "A2", "B", "A"])
	_check("the A tune comes back (bar 1 and bar 25)", piano._tune(1) == piano._tune(25))
	var voices_ok := true
	for v: int in range(0, 40):
		for n: Array in piano._tune(v):
			voices_ok = voices_ok and int(n[1]) >= 60 and int(n[1]) <= 88
	_check("the tune stays in the right hand's range", voices_ok)
	var calm_tempo: float = piano._tempo()
	# A sudden jump in the film: faster, then an agitato.
	h.signals.fake("film.transient", 1.0)
	await _seconds(3.0)
	_check("a jump: faster (%.0f -> %.0f bpm)" % [calm_tempo, piano._tempo()], piano._tempo() > calm_tempo * 1.15)
	_check("a jump: an agitato (%s, drive %.2f)" % [piano.bar_kind, float(piano.params["drive"])],
			piano.bar_kind == "agitato")
	h.signals.clear_fakes()
	await _seconds(5.0)
	_check("calm again: the oom-pah (%s, drive %.2f)" % [piano.bar_kind, float(piano.params["drive"])],
			piano.bar_kind == "oompah")
	# The film plays on: film_db lower.
	Fixture.set_state(room, "playing")
	await _seconds(3.0)
	_check("in the film: 6 dB lower (%.1f)" % piano.designed_db(),
			absf(piano.designed_db() - (Music.LEVELS["piano"] - 6.0)) < 0.3)
	# Its setting off: silent.
	h.set_setting("piano", false)
	await _seconds(2.5)
	_check("its setting off: no voices (%d)" % piano.voices_sounding(), piano.voices_sounding() == 0
			and not bool(piano.params["on"]))
	var count: int = piano.notes_played
	await _seconds(1.0)
	_check("and no new notes", piano.notes_played == count)
	h.set_setting("piano", true)
	await _seconds(1.5)
	_check("on again: it plays", piano.notes_played > count)
	h.do_action("piano.stop", {"seconds": 0.5})
	await _seconds(1.2)
	_check("stop: silent", piano.voices_sounding() == 0)
	room.queue_free()
	await _frames(3)


func _organ() -> void:
	var room := Fixture.build(self, ORGAN_ROOM)
	await _frames(2)
	var problems: Array = await Fixture.checks(self, room)
	_check("the organ room passes the checks %s" % [problems], problems.is_empty())
	var h: Node = room.host
	h.auto = true
	Fixture.set_state(room, "preshow")
	Fixture.finish_loading(room)
	await _seconds(3.0)
	var organ: Node = h.system("organ")
	_check("the organ plays in the pre-show (%d notes, %s)" % [organ.notes_played, organ.bar_kind],
			organ.notes_played >= 4 and organ.sounding() and organ.bar_kind == "chorale")
	_check("four voices or so at once (%d)" % organ.voices_sounding(), organ.voices_sounding() >= 3
			and organ.voices_sounding() <= Music.VOICES)
	h.do_action("organ.flourish", {})
	await _frames(3)
	_check("flourish: the cadence is written (%s)" % organ.bar_kind, organ.bar_kind == "flourish")
	await _seconds(2.0)
	_check("the cadence sounds", organ.sounding())
	var t0 := Time.get_ticks_msec()
	while not organ.resting() and Time.get_ticks_msec() - t0 < 30000:
		await _seconds(0.5)
	var took := (Time.get_ticks_msec() - t0) / 1000.0
	_check("then it rests (%.1f s after)" % took, organ.resting() and took < 30.0)
	var count: int = organ.notes_played
	await _seconds(2.0)
	_check("and stays at rest", organ.notes_played == count)
	# A new state: it may play again; the film: its own states don't include it.
	Fixture.set_state(room, "playing")
	await _seconds(3.0)
	_check("silent while the film plays (%d voices)" % organ.voices_sounding(), organ.voices_sounding() == 0)
	h.do_action("organ.play", {"seconds": 2.0})
	await _seconds(1.0)
	_check("play: it plays whatever the state", organ.sounding())
	await _seconds(3.5)
	_check("for its seconds, then silent again", organ.voices_sounding() == 0)
	room.queue_free()
	await _frames(3)


## Each instrument alone at the slider's default, over 10 s of its playing: in the pre-show, in the film (film_db) and
## under a film at the reference level.
func _levels() -> void:
	print("  levels at the slider's default (dBFS RMS; the film's reference -20, the target %.1f):"
			% EnvAudio.LEVEL_TARGET_DB)
	print("  instrument  designed  alone   in film  under film  peak")
	for inst: String in Music.INSTRUMENTS:
		var doc := {"schema": 4, "name": "Level", "systems": [{"system": "music", "id": "m",
				"params": {"instrument": inst, "plays_in": ["preshow", "playing"], "seed": 7}}]}
		var room := Fixture.build(self, doc)
		await _frames(1)
		Fixture.set_state(room, "preshow")
		Fixture.finish_loading(room)
		var a: Dictionary = await Fixture.measure(self, 10.0, 1.5)
		Fixture.set_state(room, "playing")
		await _seconds(3.0)
		var film: float = (await Fixture.measure(self, 8.0, 0.1))["rms"]
		var under: float = (await Fixture.measure(self, 8.0, 0.4, EnvSynth.REFERENCE_DB))["rms"]
		print("  %-10s  %6.1f    %6.1f   %6.1f    %6.1f    %6.1f" % [inst, Music.LEVELS[inst], a["rms"], film, under,
				a["peak"]])
		_check("%s: at its designed level within 1.5 dB (%.1f, designed %.1f)" % [inst, a["rms"], Music.LEVELS[inst]],
				absf(float(a["rms"]) - float(Music.LEVELS[inst])) < 1.5)
		_check("%s: under the target with 10 dB to spare (%.1f)" % [inst, a["rms"]],
				float(a["rms"]) < EnvAudio.LEVEL_TARGET_DB - 10.0)
		_check("%s: its peak under the film's reference (%.1f)" % [inst, a["peak"]],
				float(a["peak"]) < EnvSynth.REFERENCE_DB - 10.0)
		_check("%s: lower in the film (%.1f)" % [inst, film], film < float(a["rms"]) - 4.0)
		_check("%s: under a film at the reference, 35 dB or more under it (%.1f)" % [inst, under],
				under < EnvSynth.REFERENCE_DB - 35.0)
		room.queue_free()
		await _frames(2)


func _check(what: String, ok: bool) -> void:
	_checks += 1
	if not ok:
		_failures += 1
		print("FAIL: ", what)
