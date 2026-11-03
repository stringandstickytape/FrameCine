extends SceneTree

## Every codec of the software path (docs/decisions.md D18), on the host build (no hardware decoder, so everything is
## decoded in software here; x86 speeds are not the headset's):
##   xvfb-run -a env VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/lvp_icd.json \
##     godot --path spikes/03-player/demux-test --script res://codecs_test.gd [-- --dir=~/src/codec-tests --only=a,b --no-real]
## The clips come from make-codec-files.sh (~/src/codec-tests). The real files are read (never written) from the local test
## library: a folder of links, with the neutral names below, to files of your own ($VRVP_LIBRARY, default
## ~/media-tests/library); a missing one is skipped.
## For each file:
## 1. MediaSource: the codec, size, sample aspect ratio, field order and audio codec are what the file has; the video is
##    software_decodable and playable, with no reason against it.
## 2. Audio: a second MediaSource decodes the default audio track; its samples are not silent (the clips: a 440 Hz tone).
## 3. Video (needs a RenderingDevice: xvfb-run and lavapipe): HWVideoTexture takes the software path and plays from a start
##    point for 2.5 s of media time; frames come out at the decoded size (odd sizes lose a column or row), their times
##    rise in steps of about one frame (none out of order: B-frames, packed B-frames, AVI's missing PTS), and the clips'
##    flat corner reads back as the colour encoded (0x3060C0 as BT.601 Y'CbCr, limited or full range as the info says).
## 4. Seeking: to 60 % of the clip (real files: a minute on); the next frames are within 0.2 s of the target.
## Prints a table (codec, picture format and conversion, decoder field order, CPU per frame) and RESULT; exits 0 when all pass.

const BG := Color(48.0 / 255.0, 96.0 / 255.0, 192.0 / 255.0) # 0x3060C0
var lib := (OS.get_environment("VRVP_LIBRARY") if OS.has_environment("VRVP_LIBRARY")
		else OS.get_environment("HOME").path_join("media-tests/library")) + "/"

# file, codec (FFmpeg name), size, sar (0: don't check), fields ("" don't check), audio codec, colour (tolerance; 0: no
# check), start (seconds), and the decoder's view of the fields ("" don't check).
var clips := [
	{"file": "xvid_bframes.avi", "codec": "mpeg4", "size": Vector2i(640, 480), "audio": "mp3", "colour": 8},
	{"file": "div3.avi", "codec": "msmpeg4v3", "size": Vector2i(640, 480), "audio": "mp3", "colour": 8},
	{"file": "mp42.avi", "codec": "msmpeg4v2", "size": Vector2i(320, 240), "audio": "mp3", "colour": 8},
	{"file": "mpeg1.mpg", "codec": "mpeg1video", "size": Vector2i(352, 288), "audio": "mp2", "colour": 8},
	{"file": "dvd_interlaced.vob", "codec": "mpeg2video", "size": Vector2i(720, 576), "sar": 64.0 / 45.0, "fields": "tt",
			"decoder_fields": "tt", "audio": "ac3", "colour": 8},
	{"file": "h263_amr.3gp", "codec": "h263", "size": Vector2i(352, 288), "audio": "amr_nb", "colour": 8},
	{"file": "wmv1.wmv", "codec": "wmv1", "size": Vector2i(320, 240), "audio": "wmav1", "colour": 8},
	{"file": "wmv2.wmv", "codec": "wmv2", "size": Vector2i(320, 240), "audio": "wmav2", "colour": 8},
	{"file": "mpeg4.asf", "codec": "mpeg4", "size": Vector2i(320, 240), "audio": "wmav2", "colour": 8},
	{"file": "flv1.flv", "codec": "flv1", "size": Vector2i(320, 240), "audio": "mp3", "colour": 8},
	{"file": "flv1_nelly.flv", "codec": "flv1", "size": Vector2i(320, 240), "audio": "nellymoser", "colour": 8},
	{"file": "rv10.rm", "codec": "rv10", "size": Vector2i(320, 240), "audio": "ac3", "colour": 8},
	{"file": "rv20.rm", "codec": "rv20", "size": Vector2i(320, 240), "audio": "ac3", "colour": 8},
	# FFmpeg's Theora decoder (8.1) rejects the inter frames of what libtheora 1.2 (the PC's ffmpeg) encodes, with "error
	# in unpack_block_qpis" (per-block quantizers): only the keyframes show. The PC's ffmpeg itself fails the same way.
	{"file": "theora.ogv", "codec": "theora", "size": Vector2i(640, 480), "audio": "vorbis", "colour": 8, "known": "keyframes only"},
	{"file": "vp8.webm", "codec": "vp8", "size": Vector2i(640, 480), "audio": "opus", "colour": 8},
	{"file": "av1_1080p.mkv", "codec": "av1", "size": Vector2i(1920, 1080), "audio": "opus", "colour": 8},
	{"file": "av1_720p_10bit.mkv", "codec": "av1", "size": Vector2i(1280, 720), "audio": "opus", "colour": 8},
	{"file": "mjpeg422.avi", "codec": "mjpeg", "size": Vector2i(640, 480), "audio": "adpcm_ima_wav", "colour": 8},
	{"file": "cinepak.mov", "codec": "cinepak", "size": Vector2i(320, 240), "audio": "pcm_mulaw", "colour": 16},
	{"file": "msvideo1.avi", "codec": "msvideo1", "size": Vector2i(320, 240), "audio": "pcm_u8", "colour": 12},
	{"file": "huffyuv422.avi", "codec": "huffyuv", "size": Vector2i(320, 240), "audio": "pcm_s16le", "colour": 6},
	{"file": "prores422.mov", "codec": "prores", "size": Vector2i(1280, 720), "audio": "pcm_s24le", "colour": 6},
	{"file": "ffv1_gray_odd.nut", "codec": "ffv1", "size": Vector2i(350, 238), "audio": "flac", "colour": 0, "gray": true},
	{"file": "png_pal8.mov", "codec": "png", "size": Vector2i(320, 240), "audio": "aac", "colour": 40},
	{"file": "dv_pal.dv", "codec": "dvvideo", "size": Vector2i(720, 576), "sar": 16.0 / 15.0, "audio": "pcm_s16le", "colour": 8,
			"decoder_fields": "bb"},
	{"file": "mpeg2.mxf", "codec": "mpeg2video", "size": Vector2i(720, 576), "audio": "pcm_s16le", "colour": 8},
	{"file": "vfr_mpeg4.mkv", "codec": "mpeg4", "size": Vector2i(640, 480), "audio": "mp3", "colour": 8, "vfr": true},
]

# Real files of the local test library (read only), played from a minute in.
var real := [
	{"file": lib + "divx5_dx50.avi", "codec": "mpeg4",
			"size": Vector2i(680, 560), "audio": "mp3", "start": 300.0, "note": "DivX 5 (DX50), 680x560"},
	{"file": lib + "xvid_528x400.avi", "codec": "mpeg4", "size": Vector2i(528, 400), "audio": "mp3", "start": 600.0, "note": "Xvid"},
	{"file": lib + "xvid_ac3.avi", "codec": "mpeg4", "size": Vector2i(512, 384), "audio": "ac3",
			"start": 600.0, "note": "Xvid + AC-3"},
	{"file": lib + "divx4.avi", "codec": "mpeg4", "size": Vector2i(720, 576), "audio": "mp3", "start": 900.0,
			"note": "DivX 4 (DIVX)"},
	{"file": lib + "mpeg4_30fps.divx", "codec": "mpeg4", "size": Vector2i(640, 360), "audio": "mp3", "start": 600.0,
			"note": ".divx, 30 fps"},
	{"file": lib + "div3_wma.avi", "codec": "msmpeg4v3", "size": Vector2i(384, 284),
			"audio": "wmav2", "start": 300.0, "note": "DivX 3 + WMA"},
	{"file": lib + "div3_mp3.avi", "codec": "msmpeg4v3", "size": Vector2i(384, 288),
			"audio": "mp3", "start": 300.0, "note": "DivX 3 + MP3"},
	{"file": lib + "mpeg4_part2.mp4", "codec": "mpeg4", "size": Vector2i(624, 480), "audio": "aac",
			"start": 300.0, "note": "MPEG-4 part 2 in MP4"},
	{"file": lib + "flv1_in.avi",
			"codec": "flv1", "size": Vector2i(384, 216), "audio": "mp3", "start": 300.0, "note": "FLV1 in AVI"},
	{"file": lib + "flv1_mp3.flv", "codec": "flv1", "size": Vector2i(320, 240), "audio": "mp3",
			"start": 120.0, "note": "FLV"},
	{"file": lib + "rv40_cook.rm", "codec": "rv40", "size": Vector2i(384, 216), "audio": "cook",
			"start": 300.0, "note": "RealVideo 4 + Cook"},
	{"file": lib + "wmv8_wma2.wmv", "codec": "wmv2", "size": Vector2i(320, 240),
			"audio": "wmav2", "start": 300.0, "note": "WMV 8 + WMA 2"},
	{"file": lib + "mpeg1_mp2.mpg", "codec": "mpeg1video", "size": Vector2i(352, 288),
			"sar": 49.0 / 33.0, "audio": "mp2", "start": 300.0, "note": "MPEG-1 + MP2"},
	{"file": lib + "mpeg2_ps_169.mpg", "codec": "mpeg2video", "size": Vector2i(720, 576),
			"sar": 64.0 / 45.0, "fields": "tt", "audio": "mp2", "start": 300.0, "note": "MPEG-2 PS, interlaced, 16:9"},
	{"file": lib + "svcd.mpg", "codec": "mpeg2video",
			"size": Vector2i(480, 480), "sar": 4.0 / 3.0, "audio": "mp2", "start": 300.0, "note": "SVCD"},
	{"file": lib + "dvd_bff/VIDEO_TS/VTS_01_1.VOB", "codec": "mpeg2video", "size": Vector2i(720, 576), "fields": "bb",
			"audio": "ac3", "start": 300.0, "note": "DVD VOB, bottom field first, AC-3"},
	{"file": lib + "dvd_tff/VIDEO_TS/VTS_03_1.VOB",
			"codec": "mpeg2video", "size": Vector2i(720, 576), "fields": "tt", "audio": "ac3", "start": 300.0, "note": "DVD VOB, top field first"},
	{"file": lib + "mpeg2_1080i.ts", "codec": "mpeg2video",
			"size": Vector2i(1920, 1080), "fields": "tt", "audio": "ac3", "start": 300.0, "note": "MPEG-2 1080i in TS"},
	{"file": lib + "h263_camera.mov", "codec": "h263", "size": Vector2i(352, 288), "sar": 12.0 / 11.0,
			"audio": "pcm_mulaw", "start": 120.0, "note": "H.263 camera MOV"},
	{"file": lib + "Animated.VC-1.Remux.mkv", "codec": "vc1",
			"size": Vector2i(1920, 1080), "audio": "dts", "start": 1200.0, "note": "VC-1 1080p (Blu-ray)"},
	{"file": lib + "h264_ac3.avi", "codec": "h264", "size": Vector2i(720, 480),
			"audio": "ac3", "start": 300.0, "note": "H.264 in AVI (the hardware's on the Frame)"},
]

var failures: PackedStringArray = []
var rows: PackedStringArray = []
var threads := 0 # --threads=N: HWVideoTexture.software_threads (0: its default).


func _initialize() -> void:
	_run.call_deferred()


func _check(ok: bool, what: String) -> void:
	print(("  PASS  " if ok else "  FAIL  ") + what)
	if not ok:
		failures.append(what)


func _run() -> void:
	var dir := OS.get_environment("HOME") + "/src/codec-tests"
	var only: PackedStringArray = []
	var with_real := true
	var with_clips := true
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--dir="):
			dir = arg.trim_prefix("--dir=")
		elif arg.begins_with("--only="):
			only = arg.trim_prefix("--only=").split(",", false)
		elif arg == "--no-real":
			with_real = false
		elif arg == "--no-clips":
			with_clips = false
		elif arg.begins_with("--threads="):
			threads = int(arg.trim_prefix("--threads="))
	var rd := RenderingServer.get_rendering_device()
	if rd == null:
		print("  NOTE  no RenderingDevice (run with xvfb-run and lavapipe): info and audio only")
	var entries: Array = []
	if with_clips:
		for c: Dictionary in clips:
			var e := c.duplicate()
			e["file"] = dir.path_join(c["file"])
			e["clip"] = true
			entries.append(e)
	if with_real:
		entries.append_array(real)
	for e: Dictionary in entries:
		if not only.is_empty() and not Array(only).any(func(o: String) -> bool: return str(e["file"]).get_file().containsn(o)):
			continue
		if not FileAccess.file_exists(e["file"]):
			print("== %s: SKIP (no such file)" % e["file"])
			continue
		await _check_file(e, rd)
	print("\n%-34s %-11s %-10s %-58s %-11s %s" % ["file", "codec", "decoded", "conversion", "fields", "decoded flat out (x86 WSL, lavapipe drawing)"])
	for r in rows:
		print(r)
	print("RESULT: %s (%d failures)" % ["PASS" if failures.is_empty() else "FAIL", failures.size()])
	for f in failures:
		print("  failed: " + f)
	quit(0 if failures.is_empty() else 1)


func _check_file(e: Dictionary, rd: RenderingDevice) -> void:
	var path: String = e["file"]
	var name := path.get_file()
	print("== %s%s" % [name, (" (" + str(e["note"]) + ")") if e.has("note") else ""])
	var source := MediaSource.new()
	var err := source.open(path)
	_check(err == OK, "%s: opens (%s)" % [name, source.get_last_error() if err != OK else "ok"])
	if err != OK:
		return
	var v := source.get_video_info()
	print("  video: %s (%s) %dx%d SAR %.4f fields \"%s\" %.3f fps %s; hw %s, software %s, filter \"%s\"; audio %s" % [v.get("codec"),
			v.get("codec_display_name"), v.get("width"), v.get("height"), v.get("sample_aspect_ratio"), v.get("field_order"), v.get("fps"),
			v.get("pixel_format"), v.get("hw_decodable"), v.get("software_decodable"), v.get("video_filter"), source.get_audio_tracks().map(
			func(t: Dictionary) -> String: return str(t.get("codec")))])
	_check(str(v.get("codec_name")) == e["codec"], "%s: codec %s (%s)" % [name, e["codec"], v.get("codec_name")])
	var size := Vector2i(int(v.get("width", 0)), int(v.get("height", 0)))
	var expect_size: Vector2i = e["size"]
	_check(size == expect_size or (size.x & ~1) == expect_size.x and (size.y & ~1) == expect_size.y, "%s: size %s (%s)" % [name, expect_size, size])
	_check(bool(v.get("playable")) and str(v.get("unplayable_reason")) == "", "%s: playable (%s)" % [name, v.get("unplayable_reason")])
	if str(v.get("codec_name")) != "h264":
		_check(bool(v.get("software_decodable")), "%s: software_decodable" % name)
	if e.has("sar"):
		_check(absf(float(v.get("sample_aspect_ratio")) - float(e["sar"])) < 0.01, "%s: sample aspect ratio %.4f (%.4f): display aspect %.3f" % [name,
				e["sar"], v.get("sample_aspect_ratio"), v.get("display_aspect")])
	if e.has("fields"):
		_check(str(v.get("field_order")) == e["fields"], "%s: field order %s (\"%s\")" % [name, e["fields"], v.get("field_order")])
	var tracks := source.get_audio_tracks()
	_check(not tracks.is_empty() and str(tracks[0].get("codec")) == e["audio"], "%s: audio %s (%s)" % [name, e["audio"],
			tracks[0].get("codec") if not tracks.is_empty() else "none"])
	var start := float(e.get("start", 0.0))
	await _check_audio(path, name, start)
	if rd != null:
		await _check_video(source, e, rd, start)
	source.close()


# The default audio track decodes to sound (read_audio_frames: what a mixer would get).
func _check_audio(path: String, name: String, start: float) -> void:
	var source := MediaSource.new()
	if source.open(path) != OK:
		return
	if start > 0.0:
		source.seek(start)
	var peak := 0.0
	var t0 := Time.get_ticks_msec()
	var read := 0
	while Time.get_ticks_msec() - t0 < 4000 and read < source.get_output_rate() * 2:
		await process_frame
		if int(source.get_stats().get("audio_frames_out", 0)) < source.get_output_rate() / 2 and Time.get_ticks_msec() - t0 < 2000:
			continue
		var frames := source.read_audio_frames(2048)
		read += frames.size()
		for f in frames:
			peak = maxf(peak, maxf(absf(f.x), absf(f.y)))
	var stats := source.get_stats()
	_check(peak > 0.02, "%s: audio plays (peak %.3f over %d frames, %d decode errors)" % [name, peak, read, stats.get("audio_decode_errors", 0)])
	source.close()


func _expected_yuv(full: bool) -> Vector3:
	# BT.601 (what the clips are encoded with: lavfi's colour source, SD and HD alike).
	var y := 0.299 * BG.r + 0.587 * BG.g + 0.114 * BG.b
	var cb := (BG.b - y) / 1.772
	var cr := (BG.r - y) / 1.402
	if full:
		return Vector3(y * 255.0, 128.0 + cb * 255.0, 128.0 + cr * 255.0)
	return Vector3(16.0 + y * 219.0, 128.0 + cb * 224.0, 128.0 + cr * 224.0)


# The mean of the flat corner (bottom right) of the shown frame, read back from the planes.
func _read_corner(tex: HWVideoTexture, rd: RenderingDevice, size: Vector2i) -> Vector3:
	var y_data := rd.texture_get_data(tex.get_plane_rd_rid(0), 0)
	var uv_data := rd.texture_get_data(tex.get_plane_rd_rid(1), 0)
	if y_data.size() < size.x * size.y or uv_data.size() < size.x * (size.y / 2):
		return Vector3(-1, -1, -1)
	var sum := Vector3.ZERO
	var n := 0
	for yy in range(int(size.y * 0.7), int(size.y * 0.7) + 8):
		for xx in range(int(size.x * 0.75), int(size.x * 0.75) + 8):
			var c := (yy / 2) * size.x + (xx / 2) * 2
			sum += Vector3(y_data[yy * size.x + xx], uv_data[c], uv_data[c + 1])
			n += 1
	return sum / n


func _check_video(source: MediaSource, e: Dictionary, rd: RenderingDevice, start: float) -> void:
	var name := str(e["file"]).get_file()
	var v := source.get_video_info()
	source.select_audio_track(-1)
	if start > 0.0:
		source.seek(start)
	var tex := HWVideoTexture.new()
	if threads > 0:
		tex.software_threads = threads
	var err := tex.open_source(source)
	_check(err == OK and tex.get_decode_path() == "software", "%s: software path (%s %s)" % [name, error_string(err), tex.get_last_error()])
	if err != OK:
		return
	tex.play()
	var times: Array[float] = []
	var t0 := Time.get_ticks_msec()
	var last := -1.0
	while Time.get_ticks_msec() - t0 < 30000 and (times.is_empty() or times[-1] < start + 2.5):
		await process_frame
		_update(tex)
		var ft := tex.get_frame_time()
		if ft >= 0.0 and ft != last:
			times.append(ft)
			last = ft
		if str(tex.get_last_error()) != "":
			break
	var stats := tex.get_stats()
	var frames := int(stats.get("frames_decoded", 0))
	_check(tex.get_last_error() == "", "%s: no decode error (%s)" % [name, tex.get_last_error()])
	if e.has("known"):
		print("  NOTE  %s: known: %s (%d distinct frames, %d decoded, %d decode errors)" % [name, e["known"], times.size(), frames, stats.get("software_decode_errors", 0)])
		_check(times.size() >= 4, "%s: some frames shown (%d)" % [name, times.size()])
		rows.append("%-34s %-11s %-10s %-58s %-11s %s" % [name.left(34), v.get("codec_name"), "%dx%d" % [tex.get_decoded_size().x,
				tex.get_decoded_size().y], str(stats.get("software_conversion")).left(58), stats.get("software_field_order"), "known: " + str(e["known"])])
		tex.close()
		return
	_check(times.size() >= 10, "%s: frames shown (%d distinct, %d decoded)" % [name, times.size(), frames])
	if times.size() < 10:
		print("  frame times: %s" % [times.slice(0, 30).map(func(t: float) -> String: return "%.3f" % t)])
		print("  texture: %s" % stats)
		print("  source: %s" % source.get_stats())
	if times.size() >= 10:
		var steps: Array[float] = []
		var backwards := 0
		for i in range(1, times.size()):
			steps.append(times[i] - times[i - 1])
			if times[i] <= times[i - 1]:
				backwards += 1
		steps.sort()
		var median: float = steps[steps.size() / 2]
		var fps := float(v.get("fps", 0.0))
		_check(backwards == 0, "%s: frame times only rise (%d back)" % [name, backwards])
		# 60 Hz updates show every frame up to 60 fps; faster video skips some, so the step is a multiple of the frame.
		if fps > 0.0 and fps <= 60.0:
			_check(absf(median - 1.0 / fps) < 0.25 / fps, "%s: frame step %.4f s, a frame at %.3f fps" % [name, median, fps])
		_check(times[0] >= start - 0.2 and times[0] <= start + 0.5, "%s: first frame %.3f near the start %.3f" % [name, times[0], start])
		if e.get("vfr", false):
			_check(steps[-1] > 1.6 / fps and steps[-1] < 2.4 / fps, "%s: VFR gaps kept (largest step %.3f)" % [name, steps[-1]])
	var decoded := tex.get_decoded_size()
	var expect_size: Vector2i = e["size"]
	_check(decoded == Vector2i(expect_size.x & ~1, expect_size.y & ~1), "%s: decoded size %s (%s)" % [name, expect_size, decoded])
	if int(e.get("colour", 0)) > 0 and decoded.x > 0:
		var full := bool(v.get("full_range", false))
		var want := _expected_yuv(full)
		var got := _read_corner(tex, rd, decoded)
		var tol := float(e["colour"])
		_check(absf(got.x - want.x) <= tol and absf(got.y - want.y) <= tol and absf(got.z - want.z) <= tol,
				"%s: colour Y'CbCr %s, %s range (%s)" % [name, want.round(), "full" if full else "limited", got.round()])
	elif e.get("gray", false) and decoded.x > 0:
		var got := _read_corner(tex, rd, decoded)
		_check(absf(got.y - 128.0) <= 2.0 and absf(got.z - 128.0) <= 2.0 and got.x > 40.0 and got.x < 160.0, "%s: gray: chroma neutral (%s)" % [name, got.round()])
	if e.has("decoder_fields"):
		_check(str(stats.get("software_field_order")) == e["decoder_fields"], "%s: the decoder sees fields %s (%s)" % [name, e["decoder_fields"],
				stats.get("software_field_order")])
	# Seek.
	var duration := source.get_duration()
	var target := start + 60.0 if start > 0.0 else duration * 0.6
	if duration > 0.0 and target < duration - 1.0:
		source.seek(target)
		t0 = Time.get_ticks_msec()
		var shown := -1.0
		while Time.get_ticks_msec() - t0 < 15000:
			await process_frame
			_update(tex)
			var ft := tex.get_frame_time()
			if ft >= target - 1.0 and absf(ft - target) < 5.0:
				shown = ft
				break
		# Without audio the texture's own clock runs on while the decoder settles, so the first frame may be later by
		# about the time that took (in the app the audio waits, and it isn't).
		var waited := (Time.get_ticks_msec() - t0) / 1000.0
		_check(shown >= target - 0.2 and shown <= target + 0.2 + waited, "%s: seek to %.2f shows %.3f after %d ms" % [name, target, shown, waited * 1000.0])

	# Throughput: the clock runs at 8x (late frames are dropped after decoding, so the decoder runs flat out) for 2 s.
	source.seek(start)
	var from_frames := int(tex.get_stats().get("frames_decoded", 0))
	var bench_start := Time.get_ticks_usec()
	while Time.get_ticks_usec() - bench_start < 2000000 and not bool(tex.get_stats().get("state_name", "") == "ended"):
		await process_frame
		_update(tex, 50.0)
	var bench_frames := int(tex.get_stats().get("frames_decoded", 0)) - from_frames
	var bench_fps := bench_frames / ((Time.get_ticks_usec() - bench_start) * 1e-6)
	var fps_note := "%.0f fps" % bench_fps
	rows.append("%-34s %-11s %-10s %-58s %-11s %s" % [name.left(34), v.get("codec_name"), "%dx%d" % [decoded.x, decoded.y],
			str(stats.get("software_conversion")).left(58), stats.get("software_field_order"), fps_note])
	tex.close()


var _last_update_usec := 0


# Advances the texture by the wall time since the last call (times p_speed), as a player's own clock would.
func _update(tex: HWVideoTexture, p_speed := 1.0) -> void:
	var now := Time.get_ticks_usec()
	var delta := clampf((now - _last_update_usec) * 1e-6, 0.0, 0.1) if _last_update_usec > 0 else 1.0 / 60.0
	_last_update_usec = now
	tex.update(delta * p_speed)
