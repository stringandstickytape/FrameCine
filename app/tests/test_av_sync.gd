extends SceneTree

## Tests for the A/V sync card (lab://av_sync, ideas #24) and the offset per refresh rate (scripts/play/av_latency.gd)
## in the real main scene: the beep track (a beep at each whole second, silence between), the card flashing on the
## first two frames of each second, the player running on the card's audio as its clock, the offset stored for the
## rate it was set at and put back at that rate. Settings are read-only.
## Run: godot --xr-mode off --path app --script res://tests/test_av_sync.gd (the clock checks need a renderer)

const Lab := preload("res://scripts/video/lab_video_source.gd")
const LabCard := preload("res://scripts/video/lab_card.gd")

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
	var w: AudioStreamWAV = Lab.beep_stream(3.0)
	var at := func(t: float) -> int: return w.data.decode_s8(int(t * Lab.BEEP_RATE))
	var loud := func(t0: float) -> int:
		var m := 0
		for i in int(Lab.BEEP_SECONDS * Lab.BEEP_RATE):
			m = maxi(m, absi(at.call(t0 + float(i) / Lab.BEEP_RATE)))
		return m
	_check("beep track: 3 s, 8 kHz", is_equal_approx(w.get_length(), 3.0) and w.mix_rate == 8000)
	_check("a beep at each whole second (%d, %d)" % [loud.call(0.0), loud.call(2.0)], loud.call(0.0) > 80
			and loud.call(2.0) > 80)
	_check("silence between", loud.call(0.5) == 0 and loud.call(1.4) == 0)
	_check("listed with the lab's cards", Lab.list_cards().any(func(c: Dictionary) -> bool:
			return c["path"] == "lab://av_sync"))

	if DisplayServer.get_name() != "headless":
		var lit := []
		for i: int in [0, 1, 2, 30, 60, 61]:
			lit.append(await _card_brightness(i))
		print("  card brightness at frames 0, 1, 2, 30, 60, 61: %s" % [lit])
		_check("card: white on frames 0, 1, 60, 61; dark on 2 and 30", lit[0] > 0.9 and lit[1] > 0.9 and lit[4] > 0.9
				and lit[5] > 0.9 and lit[2] < 0.2 and lit[3] < 0.2)

	main.open_path("lab://av_sync")
	await _frames(3)
	_check("the card brings its beep track as the player's audio", main.player.audio.stream is AudioStreamWAV
			and main.player.source.get_audio_stream() == main.player.audio.stream)
	if DisplayServer.get_name() != "headless":
		await create_timer(1.5).timeout
		var pos: float = main.player.get_position()
		_check("the player runs on the card's audio (%.2f s, audio %.2f s)" % [pos,
				main.player.audio.get_playback_position()], main.player.audio.playing and pos > 1.0
				and absf(pos - main.player.audio.get_playback_position()) < 0.15)
	else:
		print("SKIP the clock check (headless)")

	var lat: Node = main.features.latency
	lat.rate_override = 90
	main.set_av_offset(0.035)
	_check("the offset stored for 90 Hz", is_equal_approx(lat.offset_for(90), 0.035))
	lat.rate_override = 72
	lat._check()
	_check("72 Hz with nothing stored: the offset stays", is_equal_approx(main.player.av_offset, 0.035)
			and lat.offset_for(72) == null)
	main.set_av_offset(-0.01)
	lat.rate_override = 90
	lat._check()
	_check("back at 90 Hz: its own offset again (%.3f)" % main.player.av_offset,
			is_equal_approx(main.player.av_offset, 0.035))
	lat.rate_override = 72
	lat._check()
	_check("and 72 Hz's", is_equal_approx(main.player.av_offset, -0.01))
	main.set_av_offset(0.0)
	main.open_path("stub://flat_mono")
	await _frames(3)
	print("test_av_sync: %d checks, %s" % [_checks, "all passed" if _failures == 0 else "%d FAILED" % _failures])
	quit(_failures)


## The A/V sync card drawn at content frame i: the brightness of a corner pixel (the background).
func _card_brightness(i: int) -> float:
	var vp := SubViewport.new()
	vp.size = Vector2i(320, 180)
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	var card := LabCard.new()
	card.card_id = "av_sync"
	card.fps = 60.0
	card.frame_index = i
	card.size = Vector2(320, 180)
	vp.add_child(card)
	root.add_child(vp)
	for k in 3:
		await process_frame
	await RenderingServer.frame_post_draw
	var c := vp.get_texture().get_image().get_pixel(8, 8)
	vp.queue_free()
	return c.v


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
