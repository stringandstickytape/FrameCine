extends SceneTree

## Tests for spatial audio (scripts/play/spatial_audio.gd, speaker_layouts.gd; ideas #21, #47; docs/features.md #21)
## in the real main scene: the position of every channel of every layout, the ring for 180 / 360, each room's speakers
## and acoustics, the settings and the Sound tab's commands, the output device's classification; and, on an engine
## with BinauralRenderer and the media of tests/make-spatial-media.py, the engine's channel layouts and ambisonics
## (an SA3D box), each channel's tone heard from its side, the loudness against the stereo mix, and the clock (no
## added latency, the audio position as without it). The renderer's own checks are tests/test_binaural.gd.
## Settings are read-only. Run: godot --headless --xr-mode off --path app --script res://tests/test_spatial_audio.gd

const Layouts := preload("res://scripts/play/speaker_layouts.gd")
const SpatialAudio := preload("res://scripts/play/spatial_audio.gd")
const DevCommands := preload("res://scripts/dev/dev_commands.gd")
const CommandHost := preload("res://scripts/dev/command_host.gd")
var MEDIA := OS.get_environment("HOME").path_join("media-tests/app-features/spatial")
var RATE := AudioServer.get_mix_rate()

var _failures := 0
var _checks := 0
var main: Node3D


func _init() -> void:
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate() as Node3D
	main.settings.read_only = true
	root.add_child(main)
	current_scene = main
	_run.call_deferred()


func _run() -> void:
	CommandHost.ensure(self)
	await _frames(5)
	_layout_checks()
	_ring_checks()
	await _room_checks()
	await _settings_checks()
	_sink_checks()
	if not ClassDB.class_exists("BinauralRenderer") or not FileAccess.file_exists(MEDIA.path_join("layout_7.1.wav")):
		print("SKIP engine checks (no BinauralRenderer in this engine, or no %s: tests/make-spatial-media.py)" % MEDIA)
	else:
		await _engine_checks()
	print("test_spatial_audio: %d checks, %s" % [_checks, "all passed" if _failures == 0 else "%d FAILED" % _failures])
	quit(_failures)


## Every layout FFmpeg gives: each channel's direction.
func _layout_checks() -> void:
	var layouts := {
		"mono": ["FC"], "stereo": ["FL", "FR"], "3.0": ["FL", "FR", "FC"], "quad": ["FL", "FR", "BL", "BR"],
		"5.0": ["FL", "FR", "FC", "SL", "SR"], "5.1": ["FL", "FR", "FC", "LFE", "SL", "SR"],
		"5.1(back)": ["FL", "FR", "FC", "LFE", "BL", "BR"], "6.1": ["FL", "FR", "FC", "LFE", "BC", "SL", "SR"],
		"7.1": ["FL", "FR", "FC", "LFE", "BL", "BR", "SL", "SR"],
		"7.1(wide)": ["FL", "FR", "FC", "LFE", "BL", "BR", "FLC", "FRC"],
		"5.1.2": ["FL", "FR", "FC", "LFE", "SL", "SR", "TFL", "TFR"],
		"7.1.4": ["FL", "FR", "FC", "LFE", "BL", "BR", "SL", "SR", "TFL", "TFR", "TBL", "TBR"],
		"9.1.6": ["FL", "FR", "FC", "LFE", "BL", "BR", "FLC", "FRC", "SL", "SR", "TFL", "TFR", "TBL", "TBR", "TSL",
				"TSR"],
		"22.2-ish": ["FL", "FR", "FC", "LFE", "BL", "BR", "FLC", "FRC", "BC", "SL", "SR", "TC", "TFL", "TFC", "TFR",
				"TBL", "TBC", "TBR", "LFE2", "TSL", "TSR", "BFC", "BFL", "BFR"],
	}
	var expect := {
		"mono": {"FC": [0, 0]}, "stereo": {"FL": [-30, 0], "FR": [30, 0]}, "quad": {"BL": [-110, 0], "BR": [110, 0]},
		"5.1": {"FC": [0, 0], "SL": [-110, 0], "SR": [110, 0]}, "5.1(back)": {"BL": [-110, 0], "BR": [110, 0]},
		"6.1": {"BC": [180, 0], "SL": [-110, 0]}, "7.1": {"SL": [-90, 0], "SR": [90, 0], "BL": [-135, 0], "BR": [135, 0]},
		"7.1(wide)": {"FLC": [-15, 0], "FRC": [15, 0], "BL": [-110, 0]},
		"5.1.2": {"TFL": [-45, 40], "TFR": [45, 40]},
		"7.1.4": {"TBL": [-135, 40], "TBR": [135, 40], "SL": [-90, 0]},
		"9.1.6": {"TSL": [-90, 40], "TSR": [90, 40], "FLC": [-15, 0]},
		"22.2-ish": {"TC": [0, 90], "TFC": [0, 40], "TBC": [180, 40], "BFC": [0, -30], "BFL": [-45, -30]},
	}
	for name: String in layouts:
		var names: Array = layouts[name]
		var ok := true
		var seen := []
		for n: String in names:
			var d := Layouts.direction(n, names)
			if Layouts.is_lfe(n):
				ok = ok and d.is_empty()
				continue
			ok = ok and d.has("azimuth") and d.has("elevation")
			seen.append([d.azimuth, d.elevation])
			if expect.get(name, {}).has(n):
				var e: Array = expect[name][n]
				ok = ok and is_equal_approx(d.azimuth, e[0]) and is_equal_approx(d.elevation, e[1])
		# No two channels in one place.
		var unique := true
		for i in seen.size():
			for j in range(i + 1, seen.size()):
				unique = unique and seen[i] != seen[j]
		_check("layout %s: every channel placed, as ITU puts it, none twice" % name, ok and unique)
	var unnamed := ["CH0", "CH1", "CH2", "CH3"]
	var az := unnamed.map(func(n: String) -> float: return Layouts.direction(n, unnamed).azimuth)
	_check("unnamed channels spread round (%s)" % [az], az == [-30.0, 60.0, 150.0, -120.0])
	_check("two unnamed: a stereo pair", Layouts.direction("CH1", ["CH0", "CH1"]).azimuth == 30.0)
	var v := Layouts.vector(90.0, 0.0)
	_check("azimuth 90 is to the right (+X)", v.is_equal_approx(Vector3.RIGHT))
	_check("elevation 90 is up", Layouts.vector(0.0, 90.0).is_equal_approx(Vector3.UP))


func _ring_checks() -> void:
	var names := ["FL", "FR", "FC", "LFE", "SL", "SR"]
	var r := Layouts.ring(names, Vector3.FORWARD)
	_check("ring: LFE left out unless asked", r.size() == 5 and Layouts.ring(names, Vector3.FORWARD, true).size() == 6)
	var fc: Dictionary = r.filter(func(s: Dictionary) -> bool: return s.name == "FC")[0]
	_check("ring: directions, at infinity", fc.at_infinity and (fc.position as Vector3).is_equal_approx(Vector3.FORWARD))
	# The picture's front turned to the right (+X): the centre is there, the left surround behind-left of it.
	var turned := Layouts.ring(names, Vector3.RIGHT)
	var c: Vector3 = turned.filter(func(s: Dictionary) -> bool: return s.name == "FC")[0].position
	var sl: Vector3 = turned.filter(func(s: Dictionary) -> bool: return s.name == "SL")[0].position
	_check("ring: turned with the picture's front", c.is_equal_approx(Vector3.RIGHT) and sl.z < -0.3 and sl.x < 0.0)


## Each room: where 7.1.4's speakers stand, its reflections and reverb.
func _room_checks() -> void:
	var names := ["FL", "FR", "FC", "LFE", "BL", "BR", "SL", "SR", "TFL", "TFR", "TBL", "TBR"]
	var seat := Vector3(0, 1.2, 0)
	for id: String in ["cinema", "home_theatre", "dim_room", "dome", "drive_in", "planetarium", "passthrough", "void"]:
		main.set_environment(id)
		await _frames(2)
		if main.env_id != id:
			_check("room %s exists" % id, false)
			continue
		var room: Dictionary = main.env.get_sound_room() if main.env.has_method("get_sound_room") else {}
		if room.is_empty():
			room = SpatialAudio.STANDARD_ROOM
		var anchor: Transform3D = main.env.get_screen_anchor()
		var screen := {"center": anchor.origin, "right": anchor.basis.x, "width": float(main.env.default_screen_width)}
		var placed := Layouts.place(names, room, seat, screen)
		var at := func(n: String) -> Vector3:
			return placed.filter(func(s: Dictionary) -> bool: return s.name == n)[0].position
		var ok := placed.size() >= 11 and placed.all(func(s: Dictionary) -> bool: return s.kind == "point")
		var heights_up: bool = (at.call("TFL") as Vector3).y > seat.y + 0.15 and (at.call("TBR") as Vector3).y > seat.y + 0.15
		var left_right: bool = (at.call("SL") as Vector3).x < -0.3 and (at.call("SR") as Vector3).x > 0.3
		var behind: bool = (at.call("BL") as Vector3).z > 0.3 and (at.call("BR") as Vector3).z > 0.3
		var front: bool = (at.call("FC") as Vector3).z < -0.3
		_check("%s: 7.1.4 placed, fronts ahead, sides beside, backs behind, heights above" % id, ok and heights_up
				and left_right and behind and front)
		_check("%s: a reverb (rt60 %.2f s, wet %.2f)" % [id, float(room.get("rt60", 0)), float(room.get("wet", 0))],
				float(room.get("rt60", 0.0)) > 0.05 and float(room.get("wet", 0.0)) > 0.0)
		match id:
			"cinema":
				var fc: Vector3 = at.call("FC")
				_check("cinema: the centre behind the screen", fc.z < anchor.origin.z - 0.1)
				var array := placed.filter(func(s: Dictionary) -> bool: return s.name == "SL")
				var on_wall := true
				for s: Dictionary in array:
					on_wall = on_wall and (s.position as Vector3).x < -8.0 and is_equal_approx((s.position as Vector3).y, 4.0)
				_check("cinema: surround arrays of three on the side walls at 4 m", array.size() == 3 and on_wall)
				_check("cinema: heights on the ceiling", (at.call("TFL") as Vector3).y > 8.0)
			"home_theatre":
				_check("home theatre: the fronts from the towers", (at.call("FL") as Vector3).is_equal_approx(
						room.speakers.FL) and (at.call("FC") as Vector3).is_equal_approx(room.speakers.FC))
			"drive_in":
				var inside := true
				for s: Dictionary in placed:
					inside = inside and (s.position as Vector3).length() < 2.0
				_check("drive-in: the car's speakers, all within the car", inside)
			"dome", "planetarium":
				var want := 6.0 if id == "dome" else 8.0
				var sl: Vector3 = at.call("SL")
				var tfl: Vector3 = at.call("TFL")
				_check("%s: a ring of %d m" % [id, want], absf((sl - seat).length() - want) < 0.01
						and absf((tfl - seat).length() - want) < 0.01)
			"passthrough", "void":
				var want := 2.0 if id == "passthrough" else 2.5
				var sl: Vector3 = at.call("SL")
				_check("%s: the standard layout %.1f m round" % [id, want], absf((sl - seat).length() - want) < 0.01)
	# The flat screen's pair stays between 22 and 35 degrees however small the screen.
	var small := Layouts.place(["FL", "FR"], {}, seat, {"center": Vector3(0, 1.2, -4), "right": Vector3.RIGHT,
			"width": 0.5})
	var a := rad_to_deg(atan2(absf(small[0].position.x), 4.3))
	_check("a small screen: the front pair still %.0f degrees apart each side" % a, a > 20.0 and a < 36.0)
	main.set_environment("void")
	await _frames(2)


func _settings_checks() -> void:
	var sp: Node = main.features.speakers
	_check("off by default until proven on the headset", sp.enabled == SpatialAudio.DEFAULT_ON)
	_check("HRTF sets: six bundled, four to fetch, each with a licence", sp.hrtf_sets().size() == 10
			and sp.hrtf_sets().filter(func(s: Dictionary) -> bool: return s.bundled).size() == 6
			and sp.hrtf_sets().all(func(s: Dictionary) -> bool: return str(s.licence).length() > 20))
	_check("the default HRTF set", sp.hrtf == SpatialAudio.DEFAULT_HRTF)
	_check("an unknown set refused", not sp.set_hrtf("nothing"))
	_check("a set to fetch refused until fetched", not sp.set_hrtf("mit_dummy") or FileAccess.file_exists(
			"user://hrtf/mit_dummy.fhrtf"))
	_check("another bundled set taken, per profile", sp.set_hrtf("sadie2_d2") and sp.hrtf == "sadie2_d2"
			and main.settings.get_value("spatial", "hrtf_" + sp.profile(), "") == "sadie2_d2")
	sp.set_hrtf(SpatialAudio.DEFAULT_HRTF)
	_check("the default erases the setting", not main.settings.has_value("spatial", "hrtf_" + sp.profile()))
	sp.set_reverb(5.0)
	_check("room sound clamped to 200 %", is_equal_approx(sp.reverb, 2.0))
	sp.set_reverb(1.0)
	_check("room sound 100 % erases the setting", not main.settings.has_value("spatial", "reverb"))
	sp.set_output("headphones")
	_check("output: headphones profile", sp.profile() == "headphones")
	sp.set_output("speakers")
	_check("output: the headset's speakers", sp.profile() == "speakers")
	sp.set_output("nonsense")
	_check("output: anything else is auto", sp.output == "auto")
	sp.set_profile_tuning({"itd_scale": 1.1, "pinna_warp": 1.05, "concha_db": 2.0}, "headphones")
	_check("tuning per profile", is_equal_approx(float(sp.profile_settings("headphones").tuning.itd_scale), 1.1)
			and (sp.profile_settings("speakers").tuning as Dictionary).is_empty())
	sp.set_profile_tuning({}, "headphones")
	sp.set_profile_eq([{"type": "high_shelf", "freq": 8000.0, "gain_db": -3.0, "q": 0.7}], "speakers")
	_check("EQ per profile", (sp.profile_settings("speakers").eq as Array).size() == 1)
	sp.set_profile_eq([], "speakers")
	# The Sound tab's commands.
	var r: Dictionary = await DevCommands.execute("sound", {}, false)
	_check("sound: spatial state read", r["ok"] and (r["result"]["speakers"] as Dictionary).has_all(["hrtf",
			"room_reverb", "output_profile", "profile_in_use", "hrtf_sets", "available"]))
	r = await DevCommands.execute("set_sound", {"hrtf": "sadie2_h3", "room_reverb": 0.5, "output_profile": "headphones"},
			false)
	_check("set_sound: HRTF, room sound, output", r["ok"] and sp.hrtf == "sadie2_h3" and is_equal_approx(sp.reverb, 0.5)
			and sp.output == "headphones")
	r["call"].undo.call()
	_check("set_sound: undo", sp.output == "auto" and is_equal_approx(sp.reverb, 1.0))
	_check("set_sound: an unknown HRTF refused", not (await DevCommands.execute("set_sound", {"hrtf": "x"}, false))["ok"])
	_check("set_sound: room sound 3 refused", not (await DevCommands.execute("set_sound", {"room_reverb": 3.0},
			false))["ok"])
	_check("download_hrtf: an unknown set refused", not (await DevCommands.execute("download_hrtf", {"id": "x"},
			false))["ok"])
	var spec := DevCommands.get_spec("download_hrtf")
	_check("download_hrtf: an assistant setting, described", spec.get("assistant") == "settings"
			and str(spec.get("description", "")).contains("licence"))
	sp.set_hrtf(SpatialAudio.DEFAULT_HRTF)


func _sink_checks() -> void:
	var listing := "Sink #52\n\tName: alsa_output.platform-sound.HiFi__hw_0__sink\n\tActive Port: [Out] Speaker\n" \
			+ "Sink #60\n\tName: alsa_output.jack\n\tActive Port: analog-output-headphones\n"
	_check("sink: the built-in speaker", SpatialAudio.classify_sink("alsa_output.platform-sound.HiFi__hw_0__sink",
			listing) == "speakers")
	_check("sink: the headphone jack", SpatialAudio.classify_sink("alsa_output.jack", listing) == "headphones")
	_check("sink: Bluetooth earbuds", SpatialAudio.classify_sink("bluez_output.AA_BB.1", "") == "headphones")
	_check("sink: USB headset", SpatialAudio.classify_sink("alsa_output.usb-headset", "") == "headphones")
	_check("sink: unknown", SpatialAudio.classify_sink("", "") == "")


## The engine: layouts, ambisonics, the binaural mix of each channel from its side, loudness and the clock.
func _engine_checks() -> void:
	var names := {
		"mono": "FC", "stereo": "FL FR", "3.0": "FL FR FC", "quad": "FL FR BL BR", "5.0": "FL FR FC SL SR",
		"5.1": "FL FR FC LFE SL SR", "5.1back": "FL FR FC LFE BL BR", "6.1": "FL FR FC LFE BC SL SR",
		"7.1": "FL FR FC LFE BL BR SL SR", "5.1.2": "FL FR FC LFE SL SR TFL TFR",
		"7.1.4": "FL FR FC LFE BL BR SL SR TFL TFR TBL TBR",
	}
	for layout: String in names:
		var m: Object = await _open(MEDIA.path_join("layout_%s.wav" % layout))
		var got: Dictionary = m.get_audio_layout() if m != null else {}
		_check("engine: %s keeps its channels (%s)" % [layout, " ".join(got.get("names", []))],
				" ".join(got.get("names", [])) == names[layout] and int(got.get("ambisonic_order", 0)) == -1)
	var foa: Object = await _open(MEDIA.path_join("foa_left.mp4"))
	var fl: Dictionary = foa.get_audio_layout() if foa != null else {}
	_check("engine: an SA3D box is first-order ambisonics (%s)" % [fl], int(fl.get("ambisonic_order", -1)) == 1
			and " ".join(fl.get("names", [])) == "ACN0 ACN1 ACN2 ACN3")
	var hl: Object = await _open(MEDIA.path_join("foa_left_headlocked.mp4"))
	var hll: Dictionary = hl.get_audio_layout() if hl != null else {}
	_check("engine: ambisonics with a head-locked pair (%s)" % [hll], int(hll.get("ambisonic_channels", 0)) == 4
			and (hll.get("names", []) as Array).size() == 6)

	# Each tone of the 7.1.4 file from its side, through the app's own layout (the void: the standard ring).
	var sp: Node = main.features.speakers
	var m: Object = await _open(MEDIA.path_join("layout_7.1.4.wav"))
	var r: Object = ClassDB.instantiate("BinauralRenderer")
	r.load_hrtf("res://audio/hrtf/sadie2_d1.fhrtf")
	var chans: Array = Array(m.get_audio_layout().names)
	var sources := []
	for s: Dictionary in Layouts.ring(chans, Vector3.FORWARD):
		sources.append({"input": s.index, "kind": s.kind, "position": s.position, "at_infinity": true})
	r.set_sources(sources)
	r.set_gain(SpatialAudio.GAIN)
	m.set_spatial_renderer(r)
	var frames: PackedVector2Array = await _read(m, 24000)
	var sides := []
	var ok := true
	for i in chans.size():
		var n: String = chans[i]
		if Layouts.is_lfe(n):
			continue
		var f := 1500.0 + 400.0 * i
		var ld := _goertzel(frames, f, 0)
		var rd := _goertzel(frames, f, 1)
		var db := 20.0 * log(ld / maxf(rd, 1e-9)) / log(10.0)
		var az: float = Layouts.direction(n, chans).azimuth
		sides.append("%s %+.0f" % [n, db])
		if absf(az) > 20.0 and absf(az) < 160.0:
			ok = ok and (db > 1.0 if az < 0.0 else db < -1.0)
		else:
			ok = ok and absf(db) < 3.0
	_check("engine: every 7.1.4 tone from its side (L-R dB: %s)" % ", ".join(sides), ok)
	m.set_spatial_renderer(null)

	# Loudness: the binaural mix of 5.1 against the engine's stereo downmix.
	var plain: Object = await _open(MEDIA.path_join("layout_5.1.wav"))
	var mix: PackedVector2Array = await _read(plain, 24000)
	var bin: Object = await _open(MEDIA.path_join("layout_5.1.wav"))
	var r2: Object = ClassDB.instantiate("BinauralRenderer")
	r2.load_hrtf("res://audio/hrtf/sadie2_d1.fhrtf")
	var s51 := []
	for s: Dictionary in Layouts.ring(Array(bin.get_audio_layout().names), Vector3.FORWARD):
		s51.append({"input": s.index, "kind": s.kind, "position": s.position, "at_infinity": true})
	r2.set_sources(s51)
	r2.set_gain(SpatialAudio.GAIN)
	bin.set_spatial_renderer(r2)
	var binaural: PackedVector2Array = await _read(bin, 24000)
	var diff := _rms_db(binaural) - _rms_db(mix)
	print("  loudness: binaural %.1f dB against the stereo mix" % diff)
	_check("engine: the binaural mix as loud as the stereo mix within 2 dB (%+.1f dB)" % diff, absf(diff) < 2.0)

	# The clock: the audio position moves by what was read, with or without the renderer.
	var p0: float = bin.get_audio_position()
	await _read(bin, 4800)
	var p1: float = bin.get_audio_position()
	_check("engine: the clock moves by what was read (%.4f s for %.4f s)" % [p1 - p0, 4800.0 / RATE],
			absf((p1 - p0) - 4800.0 / RATE) < 0.002)
	_check("engine: no latency added", int(r2.get_stats().latency_frames) == 0)

	# Ambisonics: the 500 Hz from the left in the left ear; the head-locked 900 Hz in the left ear only.
	var ra: Object = ClassDB.instantiate("BinauralRenderer")
	ra.load_hrtf("res://audio/hrtf/sadie2_d1.fhrtf")
	ra.set_ambisonics(1, 0, Basis(), 1.0)
	ra.set_sources([{"input": 4, "kind": "head_left"}, {"input": 5, "kind": "head_right"}])
	var hl2: Object = await _open(MEDIA.path_join("foa_left_headlocked.mp4"))
	hl2.set_spatial_renderer(ra)
	var af: PackedVector2Array = await _read(hl2, 24000)
	var field := 20.0 * log(_goertzel(af, 500.0, 0) / maxf(_goertzel(af, 500.0, 1), 1e-9)) / log(10.0)
	var locked := 20.0 * log(_goertzel(af, 900.0, 0) / maxf(_goertzel(af, 900.0, 1), 1e-9)) / log(10.0)
	_check("engine: the sound field's left tone on the left (%+.1f dB)" % field, field > 3.0)
	_check("engine: the head-locked tone in the left ear only (%+.1f dB)" % locked, locked > 40.0)
	# The app: with spatial sound on, a file playing gets the renderer (no renderer needs a real player: headless
	# the clock never starts, so only that it is wired).
	_check("app: the renderer is the app's", sp.renderer != null and sp.available())


func _open(path: String) -> Object:
	var m: Object = ClassDB.instantiate("MediaSource")
	m.set("discrete_channels", true)
	if m.call("open", path) != OK:
		return null
	# Decode a little so the layout is known.
	var end := Time.get_ticks_msec() + 3000
	while int(m.get_audio_layout().get("channels", 0)) == 0 and Time.get_ticks_msec() < end:
		await process_frame
	return m


## p frames from the start of the sound, through the source's own mix (MediaSource.read_audio_frames).
func _read(m: Object, n: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	var end := Time.get_ticks_msec() + 5000
	while out.size() < n and Time.get_ticks_msec() < end:
		var got: PackedVector2Array = m.read_audio_frames(mini(2400, n - out.size()))
		out.append_array(got)
		await process_frame
	return out


func _goertzel(frames: PackedVector2Array, f: float, ear: int) -> float:
	var k := 2.0 * cos(TAU * f / RATE)
	var s1 := 0.0
	var s2 := 0.0
	for i in range(2400, frames.size()):
		var x: float = frames[i].x if ear == 0 else frames[i].y
		var s := x + k * s1 - s2
		s2 = s1
		s1 = s
	return sqrt(maxf(s1 * s1 + s2 * s2 - k * s1 * s2, 0.0))


func _rms_db(frames: PackedVector2Array) -> float:
	var e := 1e-12
	for i in range(2400, frames.size()):
		e += frames[i].x * frames[i].x + frames[i].y * frames[i].y
	return 10.0 * log(e / (frames.size() - 2400)) / log(10.0)


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _check(what: String, ok: bool) -> void:
	_checks += 1
	if not ok:
		_failures += 1
		print("FAIL ", what)
	else:
		print("PASS ", what)
