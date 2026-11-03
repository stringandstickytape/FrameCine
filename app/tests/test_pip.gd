extends SceneTree

## Tests for picture in picture (scripts/play/picture_in_picture.gd, ideas #87) in the real main scene on the fork:
## a second film plays silent in the screen's corner (rendered there), follows pause and play, moves and sizes, swaps
## with the big screen's film (both play on where they were, the sound goes with the big screen) and back, and closes
## at its end. Clips from make-feature-media.sh: trick10.avi (big), gapless/gap_b.avi (light, 14 s, small).
## Needs the fork and a renderer.
## Run: godot --xr-mode off --path app --script res://tests/test_pip.gd

const PictureInPicture := preload("res://scripts/play/picture_in_picture.gd")
var BIG := OS.get_environment("HOME").path_join("media-tests/app-features/trick10.avi")
var SMALL := OS.get_environment("HOME").path_join("media-tests/app-features/gapless/gap_b.avi")

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
	var pip: Node = main.features.pip
	_check("closed at start, top right, 0.3", pip.state == "" and not pip.quad.visible and pip.corner == "top_right"
			and is_equal_approx(pip.size, 0.3))
	_check("video files only", PictureInPicture.can_show("/a/film.mkv") and PictureInPicture.can_show("smb://h/s/f.mp4")
			and not PictureInPicture.can_show("/a/b.jpg") and not PictureInPicture.can_show("/a/b.flac")
			and not PictureInPicture.can_show("stub://flat_mono") and not PictureInPicture.can_show("lab://av_sync"))
	if not pip.available() or not FileAccess.file_exists(SMALL) or not FileAccess.file_exists(BIG) \
			or DisplayServer.get_name() == "headless":
		print("SKIP playback checks (needs the fork, the clips and a renderer)")
	else:
		await _playback(pip)
	print("test_pip: %d checks, %s" % [_checks, "all passed" if _failures == 0 else "%d FAILED" % _failures])
	quit(_failures)


func _playback(pip: Node) -> void:
	main.set_environment("void")
	main.open_path(BIG)
	await _until(func() -> bool: return main.player.get_position() > 1.0, 10.0)
	var big: Object = main.player.source
	_check("open: a video file", pip.open(SMALL) and pip.state == "opening")
	await _until(func() -> bool: return pip.state == "playing", 10.0)
	var small: Object = pip.source
	_check("playing in the corner", pip.state == "playing" and small != null and pip.quad.visible
			and pip.material.get_shader_parameter("y_tex") == small.get_plane_texture(0))
	var s: Vector2 = main.screen.get_flat_size()
	var q: QuadMesh = pip.quad.mesh
	_check("top right, 0.3 of the width, inside the screen (%s at %s)" % [q.size, pip.quad.position],
			is_equal_approx(q.size.x, s.x * 0.3) and pip.quad.position.x > 0.0 and pip.quad.position.y > 0.0
			and pip.quad.position.x + q.size.x * 0.5 < s.x * 0.5 and pip.quad.position.y + q.size.y * 0.5 < s.y * 0.5)
	_check("silent: no audio track", small.get_audio_track() == -1 and main.player.audio.stream == big.get_audio_stream())
	await create_timer(0.3).timeout
	var light := _brightness_at(pip.quad.global_position)
	var dark := _brightness_at(main.screen.global_position + Vector3(-s.x * 0.25, -s.y * 0.25, 0.0))
	print("  corner %.3f, big screen %.3f" % [light, dark])
	_check("the corner shows the light film over the big one (%.3f, %.3f)" % [light, dark], light > dark + 0.15)
	var p0: float = small.get_position()
	await create_timer(1.0).timeout
	var rate: float = small.get_position() - p0
	_check("it plays at 1x on its own clock (%.2f)" % rate, rate > 0.8 and rate < 1.2)

	main.player.pause()
	await _frames(3)
	p0 = small.get_position()
	await create_timer(0.5).timeout
	_check("pauses with the film", absf(small.get_position() - p0) < 0.05)
	main.player.play()
	await create_timer(0.5).timeout
	_check("plays with the film", small.get_position() > p0 + 0.3)

	pip.set_corner("bottom_left")
	pip.set_size(0.5)
	_check("bottom left, half the width", pip.quad.position.x < 0.0 and pip.quad.position.y < 0.0
			and is_equal_approx(q.size.x, s.x * 0.5))
	pip.set_corner("top_right")
	pip.set_size(0.3)

	# Swap: both play on where they were; the sound goes with the big screen.
	var big_pos: float = main.player.get_position()
	var small_pos: float = small.get_position()
	_check("swap", pip.swap())
	await _frames(2)
	_check("the small film is the open file", main.current_path == SMALL and main.player.source == small
			and pip.source == big and pip.path == BIG)
	_check("the materials follow", main.screen.material.get_shader_parameter("y_tex") == small.get_plane_texture(0)
			and pip.material.get_shader_parameter("y_tex") == big.get_plane_texture(0))
	await create_timer(1.0).timeout
	print("  after the swap: big screen %.2f (was %.2f in the corner), corner %.2f (was %.2f)" % [
			main.player.get_position(), small_pos, big.get_position(), big_pos])
	_check("both played on from where they were", main.player.get_position() > small_pos + 0.5
			and main.player.get_position() < small_pos + 1.5 and big.get_position() > big_pos + 0.5
			and big.get_position() < big_pos + 1.5)
	var a: AudioStreamPlayer = main.player.audio
	_check("the sound is the big screen's", small.get_audio_track() >= 0 and big.get_audio_track() == -1
			and a.stream == small.get_audio_stream() and a.playing)
	var off: float = main.player._audio_clock() - small.get_position()
	_check("in step (%.0f ms)" % (off * 1000.0), absf(off) < 0.1)
	var light2 := _brightness_at(main.screen.global_position + Vector3(-s.x * 0.25, -s.y * 0.25, 0.0))
	_check("the big screen now shows the light film (%.3f)" % light2, light2 > dark + 0.15)
	_check("swap back", pip.swap() and main.current_path == BIG and main.player.source == big and pip.source == small)
	await create_timer(0.5).timeout

	pip.close()
	_check("close: gone", pip.state == "" and not pip.quad.visible and pip.source == null)
	_check("the film plays on", main.player.source == big and main.player.is_playing())

	# The end: gap_b is 14 s; it has played about 4 s.
	pip.open(SMALL)
	await _until(func() -> bool: return pip.state == "playing", 10.0)
	await _until(func() -> bool: return pip.state == "", 20.0)
	_check("it closes at its end", pip.state == "" and not pip.quad.visible)
	main.open_path("stub://flat_mono")
	await _frames(3)


func _brightness_at(world: Vector3) -> float:
	var cam := root.get_viewport().get_camera_3d()
	var px := cam.unproject_position(world)
	var img := root.get_texture().get_image()
	var c := Vector2i(clampi(int(px.x), 2, img.get_width() - 3), clampi(int(px.y), 2, img.get_height() - 3))
	var sum := 0.0
	for dy in [-2, 0, 2]:
		for dx in [-2, 0, 2]:
			sum += img.get_pixelv(c + Vector2i(dx, dy)).get_luminance()
	return sum / 9.0


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
