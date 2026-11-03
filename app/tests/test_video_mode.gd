extends SceneTree

const VideoMode := preload("res://scripts/video_mode.gd")

## Unit tests for VideoMode (file-name guess, ids, aspect). Run from the repository root:
##   godot --headless --xr-mode off --path app --script res://tests/test_video_mode.gd
## Exit code 0 = all passed.

const CASES := [
	# [file name, width, height, expected id]
	["Movie.2019.1080p.mkv", 1920, 1080, "flat_mono"],
	["movie_1080p_2160.mkv", 0, 0, "flat_mono"],
	["Feature.3D.HSBS.1080p.mkv", 1920, 1080, "flat_sbs_half"],
	["Feature_3D_H-SBS.mkv", 0, 0, "flat_sbs_half"],
	["film_sbs.mp4", 3840, 1080, "flat_sbs"],
	["film_sbs.mp4", 1920, 1080, "flat_sbs_half"],
	["film_SBS.mp4", 0, 0, "flat_sbs_half"],
	["film Full-SBS.mkv", 1920, 1080, "flat_sbs"],
	["film_TB.mkv", 1920, 2160, "flat_tb"],
	["film_TB.mkv", 1920, 1080, "flat_tb_half"],
	["film.3D.Half-OU.mkv", 0, 0, "flat_tb_half"],
	["documentary_sbs.h264", 3840, 1080, "flat_sbs"],
	["3D_movie.mkv", 3840, 1080, "flat_sbs"],
	["3D_movie.mkv", 1920, 2160, "flat_tb"],
	["3D_movie.mkv", 1920, 1080, "flat_sbs_half"],
	["clip_RL.mp4", 0, 0, "flat_sbs_half_swap"],
	["trip_180_LR.mp4", 0, 0, "180_sbs"],
	["trip_180x180_3dh.mp4", 0, 0, "180_sbs"],
	["cam180_video.mp4", 4096, 2048, "180_sbs"],
	["cam180_video.mp4", 0, 0, "180_mono"],
	["dome_180.mp4", 2048, 2048, "180_mono"],
	["scene_VR_4k.mp4", 4096, 2048, "180_sbs"],
	["pano_360.mp4", 3840, 1920, "360_mono"],
	["pano_360_TB.mp4", 0, 0, "360_tb"],
	["pano_360.mp4", 4096, 4096, "360_tb"],
	["pano-360x180-mono.mp4", 7680, 3840, "360_mono"],
	["concert_fisheye200.mp4", 4096, 2048, "fisheye_sbs_fov200"],
	["clip_fisheye190_sbs.mp4", 0, 0, "fisheye_sbs_fov190"],
	["clip_fisheye.mp4", 2048, 2048, "fisheye_mono"],
	["concert_tb_3d.mp4", 0, 0, "flat_tb_half"],
	# Release-style names like the user's real test files (same tags, neutral titles).
	["Animated.Feature.2.3D.2019.MULTi.1080p.Half-SBS.mkv", 0, 0, "flat_sbs_half"],
	["Animated.Feature.2.3D.2019.MULTi.1080p.Half-SBS.mkv", 1920, 1080, "flat_sbs_half"],
	["Documentary.3D.Full-SBS.mkv", 0, 0, "flat_sbs"],
	["Documentary.3D.Full-SBS.mkv", 3840, 1080, "flat_sbs"],
	# Tag spellings, any case.
	["movie.HSBS.mkv", 0, 0, "flat_sbs_half"],
	["movie.FSBS.mkv", 0, 0, "flat_sbs"],
	["movie.hou.mkv", 0, 0, "flat_tb_half"],
	["movie.OU.mkv", 1920, 2160, "flat_tb"],
	["movie.3D.mkv", 0, 0, "flat_sbs_half"],
	["MOVIE.3d.MKV", 0, 0, "flat_sbs_half"],
	["trip_360_MONO.mp4", 4096, 4096, "360_mono"],
	["dome_180_mono.mp4", 4096, 2048, "180_mono"],
	["clip_MONO_3D.mp4", 0, 0, "flat_mono"],
	# Dual fisheye 360: a 360 camera's own files (raw: two circles, front and back lens), its phone app's
	# stitched copies (an ordinary 360), and the tags. The stereo fisheye tags keep their meaning.
	["360_0042.MP4", 4096, 2048, "dualfisheye_mono"],
	["360_0010.JPG", 5792, 2896, "dualfisheye_mono"],
	["360_0042.MP4", 0, 0, "dualfisheye_mono"],
	["360_0042.MP4", 2880, 2880, "360_tb"],
	["SAM_100_0001.mp4", 4096, 2048, "360_mono"],
	["SAM_100_0002.jpg", 5472, 2736, "360_mono"],
	["SAM_0047.mp4", 1920, 1080, "flat_mono"],
	["SAM_100_0001.mp4", 1920, 1080, "flat_mono"],
	["my_360_0042_edit.mp4", 4096, 2048, "360_mono"],
	["walk_dualfisheye.mp4", 3840, 1920, "dualfisheye_mono"],
	["walk_dual_fisheye.mp4", 3840, 1920, "dualfisheye_mono"],
	["walk-Dual-Fisheye_SBS.mp4", 0, 0, "dualfisheye_mono"],
	["beach.DFE.mp4", 0, 0, "dualfisheye_mono"],
	["dfeature_film.mp4", 1920, 1080, "flat_mono"],
	["concert_fisheye.mp4", 4096, 2048, "fisheye_sbs"],
	["concert_fish_200.mp4", 0, 0, "fisheye_mono_fov200"],
]

## --mode= arguments: [arg, width, height, expected id]
const ARG_CASES := [
	["flat", 0, 0, "flat_mono"],
	["mono", 0, 0, "flat_mono"],
	["sbs", 0, 0, "flat_sbs_half"],
	["sbs", 3840, 1080, "flat_sbs"],
	["hsbs", 3840, 1080, "flat_sbs_half"],
	["tb", 1920, 2160, "flat_tb"],
	["ou", 0, 0, "flat_tb_half"],
	["3d", 0, 0, "flat_sbs_half"],
	["180", 0, 0, "180_mono"],
	["180sbs", 0, 0, "180_sbs"],
	["360", 0, 0, "360_mono"],
	["360tb", 0, 0, "360_tb"],
	["fisheye", 0, 0, "fisheye_sbs"],
	["fisheye", 2048, 2048, "fisheye_mono"],
	["fisheye200", 0, 0, "fisheye_sbs_fov200"],
	["flat_sbs_half_swap", 0, 0, "flat_sbs_half_swap"],
	["fisheye_mono_fov190", 0, 0, "fisheye_mono_fov190"],
	["dualfisheye", 0, 0, "dualfisheye_mono"],
	["dualfisheye", 3840, 1920, "dualfisheye_mono"],
	["dfe", 0, 0, "dualfisheye_mono"],
	["dual-fisheye", 0, 0, "dualfisheye_mono"],
	["dualfisheye_sbs_swap", 0, 0, "dualfisheye_mono"],
]


func _init() -> void:
	var failures := 0
	for c: Array in CASES:
		var got := VideoMode.guess(c[0], c[1], c[2]).to_id()
		if got != c[3]:
			failures += 1
			printerr("FAIL guess(%s, %dx%d) = %s, expected %s" % [c[0], c[1], c[2], got, c[3]])

	for c: Array in ARG_CASES:
		var got := VideoMode.from_arg(c[0], c[1], c[2]).to_id()
		if got != c[3]:
			failures += 1
			printerr("FAIL from_arg(%s, %dx%d) = %s, expected %s" % [c[0], c[1], c[2], got, c[3]])

	for id: String in ["flat_mono", "flat_sbs_half", "180_sbs", "360_tb", "fisheye_sbs_swap_fov200", "flat_tb_half_swap",
			"dualfisheye_mono"]:
		var round_trip := VideoMode.from_id(id).to_id()
		if round_trip != id:
			failures += 1
			printerr("FAIL from_id(%s).to_id() = %s" % [id, round_trip])

	# A dual fisheye frame is one picture for both eyes, whatever layout was asked for.
	var dual := VideoMode.make(VideoMode.Proj.DUAL_FISHEYE, VideoMode.Layout.SBS, true, true)
	if dual.to_id() != "dualfisheye_mono" or dual.is_stereo() or VideoMode.from_id("dfe").to_id() != "dualfisheye_mono":
		failures += 1
		printerr("FAIL dual fisheye not kept mono: %s" % dual.to_id())
	if VideoMode.from_id("dualfisheye_mono").describe() != "Dual fisheye 360°":
		failures += 1
		printerr("FAIL describe() = %s" % VideoMode.from_id("dualfisheye_mono").describe())

	var aspects := [
		["flat_mono", Vector2(1920, 1080), 16.0 / 9.0],
		["flat_sbs", Vector2(3840, 1080), 16.0 / 9.0],
		["flat_sbs_half", Vector2(1920, 1080), 16.0 / 9.0],
		["flat_tb", Vector2(1920, 2160), 16.0 / 9.0],
		["flat_tb_half", Vector2(1920, 1080), 16.0 / 9.0],
		["flat_sbs", Vector2(1920, 1080), 8.0 / 9.0],
	]
	for a: Array in aspects:
		var got := VideoMode.from_id(a[0]).display_aspect(a[1])
		if not is_equal_approx(got, a[2]):
			failures += 1
			printerr("FAIL %s.display_aspect(%s) = %f, expected %f" % [a[0], a[1], got, a[2]])

	print("test_video_mode: %d guess + %d argument cases, %s" % [CASES.size(), ARG_CASES.size(), "all passed" if failures == 0 else "%d FAILED" % failures])
	quit(1 if failures else 0)
