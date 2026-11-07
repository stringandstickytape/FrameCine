extends RefCounted

## The shipped rooms' sound checks (docs/environments.md, "Sound and music"), for the room tests: the room has the
## beds it should and its acoustics preset; every bed plays on the room's bus, which sends to Environment, so the
## Environment sound slider, the room's Ambience and the duck under the film all reach it; a bound bed follows its
## channel or its setting; and the room's level: the document built again with a listener at the seat, its rain and
## wet at full, every one-shot played at once, measured on Environment at the slider's default in the pre-show (its
## loudest) and in the film under a film at the reference level. Static; preload to use. `t` is the test
## (env_builder_harness.gd): its check(what, ok).

const Fixture := preload("res://tests/env_sound_fixture.gd")
const EnvAudio := preload("res://scripts/env/env_audio.gd")
const EnvSynth := preload("res://scripts/env/env_synth.gd")
const Acoustics := preload("res://scripts/env/systems/acoustics.gd")
const SoundBed := preload("res://scripts/env/systems/sound_bed.gd")

## Under a film at the reference level the room sits this far under the film, or more (dB).
const UNDER_FILM_DB := 35.0


static func beds(room: Node3D) -> Array:
	return room.host.order.filter(func(s: Node) -> bool: return s.get_script() == SoundBed)


static func _steps(h: Node, seconds: float, dt := 0.1) -> void:
	var t := 0.0
	while t < seconds:
		h.step(dt)
		t += dt


## The beds by id and sound ({id: sound}, nothing else), the acoustics preset ("" for none), each bed on the room's bus.
static func check_beds(t: Object, label: String, room: Node3D, want: Dictionary, preset: String) -> void:
	var h: Node = room.host
	var have := {}
	for b: Node in beds(room):
		have[str(b.id)] = str(b.params["sound"])
	t.check("%s: its sound beds %s (%s)" % [label, want, have], have == want)
	var acoustics: Array = h.systems_of_kind("sound").filter(func(s: Node) -> bool: return s.get_script() == Acoustics)
	if preset == "":
		t.check("%s: no acoustics of its own" % label, acoustics.is_empty())
	else:
		t.check("%s: acoustics %s (%s)" % [label, preset, acoustics.map(func(s: Node) -> String:
				return str(s.params["preset"]))], acoustics.size() == 1 and str(acoustics[0].params["preset"]) == preset)
	Fixture.finish_loading(room)
	_steps(h, 0.3)
	var buses := true
	var players := 0
	for b: Node in beds(room):
		for p: Node in b.players():
			players += 1
			buses = buses and p.get("bus") == StringName(Acoustics.BUS)
	t.check("%s: every bed's player (%d) on the room's bus" % [label, players], buses)
	var bus := AudioServer.get_bus_index(Acoustics.BUS)
	t.check("%s: the room's bus sends to Environment (the slider, the Ambience setting, the duck)" % label,
			bus >= 0 and AudioServer.get_bus_send(bus) == StringName(EnvAudio.ENVIRONMENT))
	var silent: Array = beds(room).filter(func(b: Node) -> bool: return str(b.params["sound"]) == "silence")
	for b: Node in silent:
		t.check("%s: %s plays nothing" % [label, b.id], b.players().is_empty() and not b.playing())


## A bed whose level follows a channel (weather.rain, weather.wet): none at 0, full at 1.
static func check_follows(t: Object, label: String, room: Node3D, bed_id: String, channel: String) -> void:
	var h: Node = room.host
	var b: Node = h.system(bed_id)
	if b == null:
		t.check("%s: %s exists" % [label, bed_id], false)
		return
	Fixture.finish_loading(room)
	h.signals.fake(channel, 0.0)
	_steps(h, 25.0, 0.25)
	var off := float(b.params["level"])
	var quiet: bool = not b.playing()
	h.signals.fake(channel, 1.0)
	_steps(h, 25.0, 0.25)
	var on := float(b.params["level"])
	var sounding: bool = b.playing() or not b.is_loop()
	h.signals.clear_fakes()
	t.check("%s: %s follows %s (%.2f at 0, %.2f at 1)" % [label, bed_id, channel, off, on], off < 0.02 and on > 0.95)
	t.check("%s: %s silent at 0, sounding at 1" % [label, bed_id], quiet and sounding)


## A bed whose level follows a setting: off at `off`, full at `on`; the setting left at `on`. (A setting that builds
## the room again makes its systems anew: the bed is looked up again each time.)
static func check_setting(t: Object, label: String, room: Node3D, bed_id: String, setting: String, off: Variant,
		on: Variant) -> void:
	var h: Node = room.host
	if h.system(bed_id) == null:
		t.check("%s: %s exists" % [label, bed_id], false)
		return
	h.set_setting(setting, off)
	Fixture.finish_loading(room)
	_steps(h, 15.0, 0.25)
	var b: Node = h.system(bed_id)
	var lo := float(b.params["level"])
	var quiet: bool = not b.playing()
	h.set_setting(setting, on)
	Fixture.finish_loading(room)
	_steps(h, 15.0, 0.25)
	b = h.system(bed_id)
	var hi := float(b.params["level"])
	t.check("%s: %s follows the %s setting (%.2f at %s, %.2f at %s)" % [label, bed_id, setting, lo, off, hi, on],
			lo < 0.02 and hi > 0.95 and quiet and (b.playing() or not b.is_loop()))


## The room's level: built again from its document with a listener at the seat (free the room under test first, so
## only this one sounds). Its rain and wet at full, every one-shot played at once: the pre-show (its loudest) and the
## film under a film at the reference level. Prints and checks; returns {pre, peak, under} in dBFS.
static func check_level(t: Object, tree: SceneTree, label: String, doc: Dictionary, silent := false) -> Dictionary:
	var room := Fixture.build(tree, doc)
	await tree.process_frame
	var h: Node = room.host
	h.signals.fake("weather.rain", 1.0)
	h.signals.fake("weather.wet", 1.0)
	Fixture.set_state(room, "preshow")
	Fixture.finish_loading(room)
	await tree.create_timer(6.0).timeout
	for b: Node in beds(room):
		if not b.is_loop() and str(b.params["sound"]) != "silence":
			h.do_action("%s.play" % b.id, {})
	var pre: Dictionary = await Fixture.measure(tree, 3.0, 0.1)
	Fixture.set_state(room, "playing")
	await tree.create_timer(3.5).timeout
	var under: Dictionary = await Fixture.measure(tree, 3.0, 0.4, EnvSynth.REFERENCE_DB)
	h.signals.clear_fakes()
	room.queue_free()
	await tree.process_frame
	await tree.process_frame
	print("  %s: the room's sound in the pre-show %.1f dBFS RMS (peak %.1f), under a film at the reference %.1f "
			% [label, pre["rms"], pre["peak"], under["rms"]] + "(the target %.1f, the film %.1f)" % [
			EnvAudio.LEVEL_TARGET_DB, EnvSynth.REFERENCE_DB])
	if silent:
		t.check("%s: silent: nothing on Environment (%.1f)" % [label, pre["rms"]], pre["rms"] < -100.0
				and under["rms"] < -100.0)
	else:
		t.check("%s: sounding in the pre-show (%.1f)" % [label, pre["rms"]], pre["rms"] > -90.0)
		t.check("%s: under the level check's target with 2 dB to spare (%.1f)" % [label, pre["rms"]],
				pre["rms"] < EnvAudio.LEVEL_TARGET_DB - 2.0)
		t.check("%s: under a film %d dB or more under it (%.1f)" % [label, int(UNDER_FILM_DB), under["rms"]],
				under["rms"] < EnvSynth.REFERENCE_DB - UNDER_FILM_DB)
		t.check("%s: lower in the film than in the pre-show (%.1f, %.1f)" % [label, under["rms"], pre["rms"]],
				under["rms"] < pre["rms"] - 6.0)
	return {"pre": pre["rms"], "peak": pre["peak"], "under": under["rms"]}
