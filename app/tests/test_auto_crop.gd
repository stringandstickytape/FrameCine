extends SceneTree

## Tests for the auto letterbox crop (scripts/play/auto_crop.gd, ideas #42) in the real main scene, on the fork's
## letterbox detector and the High 10 clips of make-feature-media.sh (lb10_long.avi: bars above and below;
## lb10_pillarbox.avi: bars at the sides): the snapping maths, the crop shown and the screen grown to keep its height,
## side-by-side taking only rows, turning it off and on. Needs the fork and a renderer for the playback part.
## Run: godot --xr-mode off --path app --script res://tests/test_auto_crop.gd

const AutoCrop := preload("res://scripts/play/auto_crop.gd")
const VideoMode := preload("res://scripts/video_mode.gd")
var DIR := OS.get_environment("HOME") + "/media-tests/app-features/"

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
	var base := 16.0 / 9.0
	# A 2.39 picture in a 16:9 frame: rows 0.1279 .. 0.8721 (h 0.7438). Slightly off: snapped back to 2.39.
	var lb := {"known": true, "bars": true, "uv_rect": Rect2(0.0, 0.13, 1.0, 0.74)}
	var r := AutoCrop.crop_for(lb, VideoMode.Layout.MONO, base)
	_check("snapped to 2.39 (%.4f)" % (base * r.size.x / r.size.y), absf(base * r.size.x / r.size.y - 2.39) < 0.001
			and absf(r.get_center().y - 0.5) < 0.001)
	_check("no bars: the whole frame", AutoCrop.crop_for({"known": true, "bars": false}, 0, base) == Rect2(0, 0, 1, 1))
	_check("not known yet: the whole frame", AutoCrop.crop_for({"known": false}, 0, base) == Rect2(0, 0, 1, 1))
	var sbs := AutoCrop.crop_for({"known": true, "bars": true, "uv_rect": Rect2(0.1, 0.13, 0.8, 0.74)},
			VideoMode.Layout.SBS, base)
	_check("side by side: rows only", sbs.position.x == 0.0 and sbs.size.x == 1.0 and sbs.size.y < 0.8)
	var odd := AutoCrop.crop_for({"known": true, "bars": true, "uv_rect": Rect2(0.0, 0.2, 1.0, 0.6)}, 0, base)
	_check("an aspect far from any cinema one is kept (%.3f)" % (base / odd.size.y), is_equal_approx(odd.size.y, 0.6))

	if not ClassDB.class_has_method("MediaSource", "get_letterbox") or not FileAccess.file_exists(DIR + "lb10_long.avi") \
			or DisplayServer.get_name() == "headless":
		print("SKIP playback checks (needs the fork, the clips and a renderer)")
	else:
		await _playback()
	print("test_auto_crop: %d checks, %s" % [_checks, "all passed" if _failures == 0 else "%d FAILED" % _failures])
	quit(_failures)


func _playback() -> void:
	# The clips are High 10 H.264 (pcm10_h264_avi.py): the desktop decodes 10-bit H.264 in software, 8-bit only on the
	# headset's decoder.
	var ac: Node = main.features.auto_crop
	main.set_environment("void")
	_check("off by default", not ac.enabled and ac.state()["text"] == "Off")
	main.open_path(DIR + "lb10_long.avi")
	await create_timer(1.0).timeout
	var size0: Vector2 = main.screen.get_flat_size()
	ac.set_enabled(true)
	# lb10_long.avi: 40-row bars in every frame. (The engine's own test covers the flash and dark frames of
	# lb10_letterbox.avi; in a 30 s clip played from 1 s the app sees too few frames to leave the flash out.)
	await _until(func() -> bool: return bool(ac.state()["bars"]), 20.0)
	await _frames(3)
	var st: Dictionary = ac.state()
	print("  state %s, crop %s, letterbox %s" % [st, ac.crop, ac._lb])
	_check("turning it on reopened the file and found bars (%s)" % st["text"], st["bars"] and ac.crop.size.y < 0.95)
	var v: Vector4 = main.screen.material.get_shader_parameter("visible_rect")
	_check("the screen shows only the picture rows", absf(v.y - ac.crop.position.y) < 0.01 and absf(v.w - ac.crop.size.y) < 0.01)
	var size1: Vector2 = main.screen.get_flat_size()
	_check("grown to keep the height (%s -> %s)" % [size0, size1], absf(size1.y - size0.y) < 0.01 and size1.x > size0.x * 1.05)
	ac.set_grow(false)
	var size2: Vector2 = main.screen.get_flat_size()
	_check("grow off: the width kept (%s)" % size2, absf(size2.x - size0.x) < 0.01 and size2.y < size0.y)
	ac.set_grow(true)
	main.set_video_mode(VideoMode.from_id("flat_sbs_half"), false)
	await _frames(3)
	_check("side by side: still the rows (%s)" % ac.crop, ac.crop.size.x == 1.0 and ac.crop.size.y < 0.95)
	main.set_video_mode(VideoMode.from_id("flat"), false)
	await _frames(3)
	ac.set_enabled(false)
	await _frames(2)
	var v2: Vector4 = main.screen.material.get_shader_parameter("visible_rect")
	_check("off: the whole frame and size again", is_equal_approx(v2.w, 1.0) and main.screen.get_flat_size().is_equal_approx(size0))

	ac.set_enabled(true)
	main.open_path(DIR + "lb10_pillarbox.avi")
	await _until(func() -> bool: return bool(ac.state()["known"]), 15.0)
	await _frames(3)
	print("  pillarbox state %s, crop %s" % [ac.state(), ac.crop])
	_check("pillarbox: the columns cropped, the same height", ac.crop.size.x < 0.95 and ac.crop.size.y == 1.0
			and absf(main.screen.get_flat_size().y - size0.y) < 0.01)
	ac.set_enabled(false)
	main.open_path("stub://flat_mono")
	await _frames(3)


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
