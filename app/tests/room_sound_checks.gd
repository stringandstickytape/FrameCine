extends RefCounted

## For the shipped rooms' tests (test_room_<id>.gd): a room's sound, checked in the built room (docs/environments.md,
## "Sound and music"). Its beds and instruments play on the room's bus ("Environment room"), which sends to
## Environment, so the duck, the Environment sound slider and the common Ambience setting reach every one of them; the
## room's acoustics are on that bus; and the level check: what reaches Environment at the slider's default in the
## pre-show, as the film starts, in the film and under a film at the reference level (env_sound_fixture.gd). Static;
## preload to use. Not a test itself (no test_ prefix).

const Fixture := preload("res://tests/env_sound_fixture.gd")
const EnvAudio := preload("res://scripts/env/env_audio.gd")
const EnvSynth := preload("res://scripts/env/env_synth.gd")
const Acoustics := preload("res://scripts/env/systems/acoustics.gd")

## The film's opening and the film itself, as the timeline sees them (the film moving on, as a player gives it).
const STARTING := {"open": true, "playing": true, "position": 0.5, "duration": 6000.0}
## The level check's limits (dBFS RMS at the slider's default): the pre-show under the target with 2 dB to spare (as
## test_env_sound_bed.gd holds every shipped room); in the film 6 dB under that; under a film at the reference level
## 35 dB or more under the film.
const PRESHOW_MAX := EnvAudio.LEVEL_TARGET_DB - 2.0
const FILM_MAX := EnvAudio.LEVEL_TARGET_DB - 8.0
const UNDER_MAX := EnvSynth.REFERENCE_DB - 35.0


## Every sound system `ids` names is built, of its kind, and plays on the room's bus, which sends to Environment.
## Loops and instruments are made now (their streams and notes come from worker threads). Returns the problems.
static func on_room_bus(room: Node3D, ids: Array) -> Array[String]:
	var out: Array[String] = []
	Fixture.finish_loading(room)
	var bus := AudioServer.get_bus_index(Acoustics.BUS)
	if bus < 0 or AudioServer.get_bus_send(bus) != StringName(EnvAudio.ENVIRONMENT):
		out.append("the room's bus does not send to Environment")
	for sid: String in ids:
		var s: Node = room.host.system(sid)
		if s == null:
			out.append("%s: not built" % sid)
			continue
		var kind := str(s.get_script().call("spec").get("kind"))
		if not (kind in ["sound", "music"]):
			out.append("%s: a %s system, not sound or music" % [sid, kind])
		for p: Node in s.owned():
			if (p is AudioStreamPlayer or p is AudioStreamPlayer3D) and p.get("bus") != StringName(Acoustics.BUS):
				out.append("%s: %s on %s" % [sid, p.name, p.get("bus")])
	return out


## The room's acoustics: the reverb on the room's bus at this rt60 (within 0.05 s). Returns the problems.
static func acoustics(room: Node3D, preset: String, rt60: float) -> Array[String]:
	var out: Array[String] = []
	var a: Node = null
	for s: Node in room.host.order:
		if s.get_script() == Acoustics:
			a = s
	if a == null:
		return ["no acoustics system"]
	if str(a.params["preset"]) != preset:
		out.append("preset %s, not %s" % [a.params["preset"], preset])
	var v: Dictionary = a.values()
	if absf(float(v["rt60"]) - rt60) > 0.05:
		out.append("rt60 %.2f, not %.2f" % [v["rt60"], rt60])
	if a.reverb() == null:
		out.append("no reverb on the room's bus")
	if bool(a.params.get("film", false)):
		out.append("the film's own mix coloured (film on)")
	return out


## The level check in real time: the room's own systems playing, a listener at the viewer's eyes. `fakes` are
## channels held while it runs ({"film.bass": 0.8}). Returns {preshow, starting, film, under} in dBFS RMS and prints
## them. The host steps itself meanwhile; afterwards it is left with auto off and the pre-show's snapshot.
static func levels(tree: SceneTree, room: Node3D, label: String, fakes := {}) -> Dictionary:
	var h: Node = room.host
	var cam := Camera3D.new()
	cam.name = "RoomSoundListener"
	tree.root.add_child(cam)
	cam.position = Vector3(0, 1.2, 0)
	cam.current = true
	for ch: String in fakes:
		h.signals.fake(ch, fakes[ch])
	Fixture.finish_loading(room)
	h.auto = true
	h.snapshot_override = {"open": false}
	await tree.create_timer(1.5).timeout
	var pre: Dictionary = await Fixture.measure(tree, 3.0)
	h.snapshot_override = STARTING
	var start: Dictionary = await Fixture.measure(tree, 3.0, 0.2)
	# On into the film: the starting state's seconds, then the bed's fade.
	var left := float(h.timeline.starting_seconds) - 3.2
	await tree.create_timer(maxf(left, 0.0) + 3.5).timeout
	var film: Dictionary = await Fixture.measure(tree, 3.0, 0.1)
	var under: Dictionary = await Fixture.measure(tree, 3.0, 0.4, EnvSynth.REFERENCE_DB)
	var state := str(h.timeline.state)
	h.auto = false
	h.snapshot_override = {"open": false}
	h.signals.clear_fakes()
	cam.queue_free()
	var r := {"preshow": pre["rms"], "starting": start["rms"], "film": film["rms"], "under": under["rms"],
			"state": state}
	print("  %s sound: pre-show %.1f, starting %.1f, in the film (%s) %.1f, under a film %.1f dBFS RMS (target %.1f)"
			% [label, r["preshow"], r["starting"], state, r["film"], r["under"], EnvAudio.LEVEL_TARGET_DB])
	return r


## The level check's verdicts on levels()' result: [[what, ok]].
static func verdicts(label: String, r: Dictionary) -> Array:
	return [
		["%s: the pre-show under the target with 2 dB to spare (%.1f)" % [label, r["preshow"]],
				float(r["preshow"]) < PRESHOW_MAX],
		["%s: as the film starts, 8 dB under the target (%.1f)" % [label, r["starting"]],
				float(r["starting"]) < FILM_MAX],
		["%s: in the film (%s), 8 dB under the target (%.1f)" % [label, r["state"], r["film"]],
				str(r["state"]) == "playing" and float(r["film"]) < FILM_MAX],
		["%s: under a film at the reference, 35 dB or more under it (%.1f)" % [label, r["under"]],
				float(r["under"]) < UNDER_MAX],
	]
