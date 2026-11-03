extends SceneTree

## Tests for scripts/play/cinema_speakers.gd (ideas #21, #47) in the real main scene: placement, the stereo clock on a
## muted bus, play / pause / speed mirroring, the channels reaching their own speakers, reopening on turning it on.
## Needs an engine with MediaSource.discrete_channels and a 5.1 file with video; without them only the placement
## maths runs. The file: a VP9 picture with a 5.1(side) track, a tone per channel (FL 300, FR 400, FC 500, LFE 60,
## SL 700, SR 800 Hz), at FILE (see docs/features.md for how it was made). Settings are read-only.
## The playback checks need a renderer: with --headless the video never starts, so neither does the audio clock, and
## they are skipped. Run: godot --xr-mode off --path app --script res://tests/test_speakers.gd (WSLg, or xvfb-run with
## --audio-driver Dummy).

const Speakers := preload("res://scripts/play/cinema_speakers.gd")
var FILE := OS.get_environment("HOME").path_join("media-tests/app-features/vp9_51side.mkv")
const PROBE := "SpeakersProbe"

var _failures := 0
var _checks := 0
var main: Node3D


func _init() -> void:
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate() as Node3D
	main.settings.read_only = true
	root.add_child(main)
	_run.call_deferred()


func _run() -> void:
	await _frames(5)
	_angle_checks()
	var media_ok: bool = ClassDB.class_exists("MediaSource") and "discrete_channels" in ClassDB.instantiate("MediaSource")
	if not media_ok or not FileAccess.file_exists(FILE):
		print("SKIP playback checks (no discrete channels in this engine, or no %s)" % FILE)
	elif RenderingServer.get_rendering_device() == null:
		print("SKIP playback checks (no rendering device: run with a renderer)")
	else:
		await _playback_checks()
	print("test_speakers: %d checks, %s" % [_checks, "all passed" if _failures == 0 else "%d FAILED" % _failures])
	quit(_failures)


func _angle_checks() -> void:
	var a := Speakers.angles(["FL", "FR", "FC", "SL", "SR"])
	_check("5.1(side): fronts at 30, surrounds at 110", a == {"FL": -30.0, "FR": 30.0, "FC": 0.0, "SL": -110.0,
			"SR": 110.0})
	_check("5.1(back): the back pair at 110", Speakers.angles(["BL", "BR"]) == {"BL": -110.0, "BR": 110.0})
	var b := Speakers.angles(["FL", "FR", "FC", "BL", "BR", "SL", "SR"])
	_check("7.1: sides at 90, backs at 145", b["SL"] == -90.0 and b["SR"] == 90.0 and b["BL"] == -145.0
			and b["BR"] == 145.0)


func _playback_checks() -> void:
	var sp: Node = main.features.speakers
	var audio: AudioStreamPlayer = main.player.audio
	main.set_environment("void")
	_check("off by default", not sp.enabled and not sp.active)
	main.open_path(FILE)
	await _until(func() -> bool: return main.current_path == FILE and main.player.is_playing(), 10.0)
	await _frames(10)
	_check("off: the stereo mix plays on Master", audio.bus == "Master" and sp.channels().is_empty())
	var before: float = main.player.get_position()
	sp.set_enabled(true)
	await _until(func() -> bool: return sp.active, 10.0)
	await _frames(5)
	_check("turning it on reopens the file with its channels apart", sp.active
			and main.player.source.has_discrete_channels())
	_check("... at its place (%.2f, was %.2f)" % [main.player.get_position(), before],
			absf(main.player.get_position() - before) < 1.0)
	_check("five speakers for 5.1(side), LFE left out (%s)" % [sp.channels()],
			sp.channels() == ["FL", "FR", "FC", "SL", "SR"])
	await _until(func() -> bool: return audio.playing and not audio.stream_paused, 5.0)
	await _frames(10)
	_check("the stereo stream is the clock, on the muted bus", audio.bus == Speakers.BUS and audio.playing
			and AudioServer.is_bus_mute(AudioServer.get_bus_index(Speakers.BUS)))
	_check("speakers play with the film", _all(func(p: Node) -> bool: return p.playing and not p.stream_paused))

	# Placement on the flat screen: the centre at its middle, the fronts at its edges, the surrounds beside and behind.
	var screen: Node3D = main.screen
	var w: float = screen.get_flat_size().x
	var fc: Vector3 = sp.speaker("FC").global_position
	_check("centre at the screen's middle", fc.distance_to(screen.global_position) < 0.01)
	_check("fronts at the screen's edges", sp.speaker("FL").global_position.distance_to(
			screen.global_transform * Vector3(-w * 0.5, 0, 0)) < 0.01 and sp.speaker("FR").global_position.distance_to(
			screen.global_transform * Vector3(w * 0.5, 0, 0)) < 0.01)
	var seat: Vector3 = main.camera.global_position
	var sl: Vector3 = sp.speaker("SL").global_position - seat
	var sr: Vector3 = sp.speaker("SR").global_position - seat
	_check("left surround left and behind (%s)" % sl, sl.x < -1.5 and sl.z > 0.5)
	_check("right surround right and behind (%s)" % sr, sr.x > 1.5 and sr.z > 0.5)
	# The head turning does not move them.
	main._look = Vector2(60.0, 10.0)
	main._apply_look()
	await _frames(2)
	_check("head turn: speakers stay", sp.speaker("SL").global_position.distance_to(seat + sl) < 0.01)
	main._look = Vector2.ZERO
	main._apply_look()

	# Each channel reaches its own speaker: FC carries 500 Hz, FL 300, SR 800.
	var ok := true
	for pair: Array in [["FC", 500.0, 300.0], ["FL", 300.0, 500.0], ["SR", 800.0, 700.0]]:
		var level: Array = await _tone(sp.speaker(pair[0]), pair[1], pair[2])
		print("  %s: %.4f at %d Hz, %.4f at %d Hz" % [pair[0], level[0], pair[1], level[1], pair[2]])
		ok = ok and level[0] > 0.01 and level[0] > 20.0 * level[1]
	_check("each speaker plays its own channel's tone", ok)

	main.player.pause()
	await _frames(3)
	_check("pause pauses the speakers", _all(func(p: Node) -> bool: return p.stream_paused))
	main.player.play()
	await _frames(3)
	_check("play resumes them", _all(func(p: Node) -> bool: return p.playing and not p.stream_paused))
	main.player.seek(2.0)
	await _until(func() -> bool: return audio.playing and not audio.stream_paused, 5.0)
	await _frames(5)
	var playing_on := _all(func(p: Node) -> bool: return p.playing and not p.stream_paused)
	_check("after a seek they play on (%s)" % _states(), playing_on)
	var level: Array = await _tone(sp.speaker("FC"), 500.0, 300.0)
	_check("... with their sound (FC %.4f)" % level[0], level[0] > 0.01 and level[0] > 20.0 * level[1])

	main.features.speed.set_speed(1.5)
	await _frames(3)
	_check("at 1.5x the stereo mix comes back", audio.bus == "Master"
			and _all(func(p: Node) -> bool: return p.stream_paused))
	main.features.speed.set_speed(1.0)
	await _frames(3)
	_check("at 1x the speakers again", audio.bus == Speakers.BUS
			and _all(func(p: Node) -> bool: return not p.stream_paused))

	# A sleep fade (the stereo player's volume) reaches the speakers.
	audio.volume_db = -12.0
	await _frames(2)
	_check("volume mirrored", _all(func(p: Node) -> bool: return is_equal_approx(p.volume_db, -12.0)))
	audio.volume_db = 0.0

	# Another feature takes the sound (as the PC audio sink does), then gives the bus back as it found it.
	if AudioServer.get_bus_index("TestSink") < 0:
		AudioServer.add_bus()
		AudioServer.set_bus_name(AudioServer.bus_count - 1, "TestSink")
	audio.bus = "TestSink"
	await _frames(3)
	_check("another owner of the bus: speakers stop", not sp.active and sp.channels().is_empty()
			and audio.bus == "TestSink")
	audio.bus = Speakers.BUS
	await _frames(3)
	_check("bus given back: speakers again, clock muted", sp.active and audio.bus == Speakers.BUS
			and sp.channels().size() == 5)
	await _frames(5)
	_check("... playing", _all(func(p: Node) -> bool: return p.playing and not p.stream_paused))

	sp.set_lfe(true)
	_check("LFE on: a non-positional sixth player", sp.channels().has("LFE") and sp.speaker("LFE") is AudioStreamPlayer)
	sp.set_lfe(false)

	# 360 (#47): round the seat, facing the picture's front.
	main.screen_yaw = deg_to_rad(90.0)
	main.mode = main.VideoMode.from_id("360_mono")
	await _frames(2)
	var fc360: Vector3 = sp.speaker("FC").global_position - main.camera.global_position
	_check("360: the centre ahead of the picture's front (%s)" % fc360, fc360.x > 2.0 and absf(fc360.z) < 0.1)
	var fl360: Vector3 = sp.speaker("FL").global_position - main.camera.global_position
	_check("360: front left 30 degrees left of it (%s)" % fl360, fl360.z < -1.0 and fl360.x > 1.5)
	main.screen_yaw = 0.0
	main.mode = main.VideoMode.from_id("flat")
	await _frames(2)

	sp.set_enabled(false)
	_check("off: the stereo mix on Master again, no speakers", audio.bus == "Master" and sp.channels().is_empty()
			and not sp.active)
	main.open_path("stub://flat_mono")
	await _frames(3)


func _states() -> String:
	var a: AudioStreamPlayer = main.player.audio
	var out := "stereo %s/%s %.2f" % [a.playing, a.stream_paused, a.get_playback_position()]
	for n: String in main.features.speakers.channels():
		var p: Node = main.features.speakers.speaker(n)
		out += ", %s %s/%s" % [n, p.playing, p.stream_paused]
	return out


func _all(test: Callable) -> bool:
	var sp: Node = main.features.speakers
	if sp.channels().is_empty():
		return false
	for n: String in sp.channels():
		if not test.call(sp.speaker(n)):
			return false
	return true


## Routes one speaker to a capture bus for about a second; returns [level at f, level at other] (Goertzel).
func _tone(p: Node, f: float, other: float) -> Array:
	var i := AudioServer.get_bus_index(PROBE)
	if i < 0:
		AudioServer.add_bus()
		i = AudioServer.bus_count - 1
		AudioServer.set_bus_name(i, PROBE)
		AudioServer.set_bus_mute(i, true)
		AudioServer.add_bus_effect(i, AudioEffectCapture.new())
	var cap := AudioServer.get_bus_effect(i, 0) as AudioEffectCapture
	var old: StringName = p.bus
	p.bus = PROBE
	await _frames(5)
	cap.clear_buffer()
	await create_timer(1.0).timeout
	var frames := cap.get_buffer(cap.get_frames_available())
	p.bus = old
	var rate := AudioServer.get_mix_rate()
	return [_goertzel(frames, f, rate), _goertzel(frames, other, rate)]


func _goertzel(frames: PackedVector2Array, f: float, rate: float) -> float:
	if frames.is_empty():
		return 0.0
	var k := 2.0 * cos(TAU * f / rate)
	var s1 := 0.0
	var s2 := 0.0
	for v: Vector2 in frames:
		var s := (v.x + v.y) * 0.5 + k * s1 - s2
		s2 = s1
		s1 = s
	return sqrt(maxf(s1 * s1 + s2 * s2 - k * s1 * s2, 0.0)) / frames.size()


func _until(cond: Callable, seconds: float) -> void:
	var end := Time.get_ticks_msec() + int(seconds * 1000.0)
	while not cond.call() and Time.get_ticks_msec() < end:
		await process_frame


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
