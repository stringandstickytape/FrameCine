extends SceneTree

## Unit tests for scripts/play/container_mode.gd (container metadata first, ideas #25).
## Run: godot --headless --xr-mode off --path app --script res://tests/test_container_mode.gd

const ContainerMode := preload("res://scripts/play/container_mode.gd")

var _failures := 0


func _init() -> void:
	# [info, file name, width, height, expected id or "" for none, reason fragment]
	for c: Array in [
			[{}, "film.mkv", 1920, 1080, "", ""],
			[{"stereo_mode": "2d"}, "film.SBS.mkv", 3840, 1080, "", ""],
			[{"stereo_mode": "side_by_side"}, "holiday.mkv", 3840, 1080, "flat_sbs", "side by side"],
			[{"stereo_mode": "side_by_side"}, "holiday.mkv", 1920, 1080, "flat_sbs_half", "side by side"],
			[{"stereo_mode": "top_bottom"}, "holiday.mkv", 1920, 2160, "flat_tb", "top / bottom"],
			[{"stereo_mode": "top_bottom"}, "holiday.mkv", 1920, 1080, "flat_tb_half", ""],
			[{"stereo_mode": "side_by_side", "stereo_inverted": true}, "x.mkv", 3840, 1080, "flat_sbs_swap", "right eye first"],
			# The name said 180 but the container says flat SBS without a projection: the name's projection stands.
			[{"stereo_mode": "side_by_side"}, "trip_180.mp4", 4096, 2048, "180_sbs", ""],
			[{"projection": "equirectangular"}, "walk.mp4", 3840, 1920, "360_mono", "360°"],
			[{"projection": "equirectangular", "stereo_mode": "top_bottom"}, "walk.mp4", 2880, 2880, "360_tb", ""],
			# 360 without a stereo tag, square frame: the shape rule says TB.
			[{"projection": "equirectangular"}, "walk.mp4", 2880, 2880, "360_tb", ""],
			[{"projection": "equirectangular", "bound_left": 0.25, "bound_right": 0.25,
					"stereo_mode": "side_by_side"}, "a.mp4", 4096, 2048, "180_sbs", "180°"],
			[{"projection": "half_equirectangular", "stereo_mode": "side_by_side"}, "a.mov", 4096, 2048, "180_sbs", ""],
			[{"projection": "half_equirectangular"}, "a.mov", 2048, 2048, "180_mono", ""],
			# The container beats a wrong name.
			[{"projection": "equirectangular", "stereo_mode": "2d"}, "clip_SBS_180.mp4", 3840, 1920, "360_mono", "mono"],
			[{"projection": "fisheye", "stereo_mode": "side_by_side", "stereo_hfov": 190.0}, "dual.mp4", 3840, 1920,
					"fisheye_sbs_fov190", "fisheye"],
			[{"projection": "cubemap"}, "eac.webm", 3840, 2160, "", "not supported"],
			[{"stereo_mode": "frame_sequence"}, "x.mkv", 1920, 1080, "", "not supported"],
			[{"projection": "rectilinear"}, "x.mkv", 1920, 1080, "", ""],
			# The engine's own key names (modules/hwvideo/media_source_extras.cpp).
			[{"stereo_mode": "sbs"}, "holiday.mkv", 3840, 1080, "flat_sbs", "side by side"],
			[{"stereo_mode": "tb", "stereo_inverted": true}, "holiday.mkv", 1920, 2160, "flat_tb_swap", ""],
			[{"stereo_mode": "unspecified"}, "film_SBS.mkv", 3840, 1080, "", ""],
			[{"projection": "equirectangular", "stereo_mode": "sbs", "projection_fov": Vector2(180, 180),
					"projection_bounds": Vector4(0.25, 0, 0.25, 0)}, "a.mp4", 4096, 2048, "180_sbs", "180°"],
			[{"projection": "equirectangular", "stereo_mode": "tb", "projection_fov": Vector2(360, 180)}, "b.mp4",
					4096, 4096, "360_tb", "360°"],
			[{"projection": "fisheye", "stereo_mode": "sbs", "stereo_fov": 200.0}, "d.mp4", 3840, 1920,
					"fisheye_sbs_fov200", ""],
			[{"projection": "parametric_immersive", "stereo_mode": "sbs"}, "e.mov", 4096, 2048, "", "not supported"],
			[{"stereo_mode": "2d", "projection": "", "projection_fov": Vector2.ZERO}, "f_SBS.mkv", 3840, 1080, "", ""],
	]:
		var r := ContainerMode.from_info(c[0], c[1], c[2], c[3])
		var got: String = r["mode"].to_id() if r["mode"] != null else ""
		_check("%s %s %dx%d -> '%s' (%s), want '%s'" % [c[0], c[1], c[2], c[3], got, r["reason"], c[4]],
				got == c[4] and (c[5] == "" or str(r["reason"]).contains(c[5])))
	print("test_container_mode: %s" % ("all passed" if _failures == 0 else "%d FAILED" % _failures))
	quit(_failures)


func _check(what: String, ok: bool) -> void:
	if not ok:
		_failures += 1
		printerr("FAIL " + what)
