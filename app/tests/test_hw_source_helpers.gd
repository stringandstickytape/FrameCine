extends SceneTree

## Unit tests for HWVideoSource's helpers (raw-stream frame rate from the name, sidecar audio). No engine fork
## needed. Run: godot --headless --xr-mode off --path app --script res://tests/test_hw_source_helpers.gd

const HWVideoSource := preload("res://scripts/video/hw_video_source.gd")

var _failures := 0


func _init() -> void:
	for c: Array in [
			["documentary_sbs.h264", 23.976], ["hevc8_3840x2160_60.h265", 60.0], ["clip_29.97fps.h264", 29.97],
			["a_1080.h265", 23.976], ["b_2160.h265", 23.976], ["sport-50p.hevc", 50.0], ["film_24.264", 24.0]]:
		var got := HWVideoSource._fps_from_name(c[0])
		_check("fps(%s) = %.3f" % [c[0], got], is_equal_approx(got, c[1]))

	var dir := OS.get_user_data_dir().path_join("test_sidecar")
	DirAccess.make_dir_recursive_absolute(dir)
	for f in ["documentary_sbs.h264", "documentary.ogg", "doc.ogg", "a.ogg", "a_1080.h265", "movie.h264", "movie.ogg",
			"zz.h264"]:
		FileAccess.open(dir.path_join(f), FileAccess.WRITE).store_string("x")
	for c: Array in [["documentary_sbs.h264", "documentary.ogg"], ["movie.h264", "movie.ogg"], ["a_1080.h265", ""],
			["zz.h264", ""]]:
		var got := HWVideoSource.find_sidecar_audio(dir.path_join(c[0])).get_file()
		_check("sidecar(%s) = '%s'" % [c[0], got], got == c[1])
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(f))
	DirAccess.remove_absolute(dir)

	_check("raw stream detection", HWVideoSource.is_raw_stream("x.H264") and HWVideoSource.is_raw_stream("x.hevc")
			and not HWVideoSource.is_raw_stream("x.mkv"))
	print("test_hw_source_helpers: %s" % ("all passed" if _failures == 0 else "%d FAILED" % _failures))
	quit(_failures)


func _check(what: String, ok: bool) -> void:
	if not ok:
		_failures += 1
		printerr("FAIL " + what)
