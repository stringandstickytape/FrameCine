extends SceneTree

## Q10C through a YCbCr sampler, on the host build (no decoder, no dmabufs): what can be checked without the headset.
##   xvfb-run -a godot --path spikes/03-player/demux-test --script res://q10c_test.gd [-- --files=A.mkv,B.webm]
##   (with lavapipe: VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/lvp_icd.json)
## 1. The YCbCr pass (DmabufImage.import_ycbcr_test_pattern(): a linear G10X6 / G8 image in host memory, read through a
##    sampler with a YCbCr conversion by the same compute pass as a Q10C dmabuf) writes exactly the P010 form of the
##    pattern into the R16 and R16G16 textures, on two frames, and the image frees cleanly.
## 2. DmabufImage.get_q10c_candidates() and get_q10c_report() answer (lavapipe has no DRM format modifiers: no candidate).
## 3. --files: 10-bit files are still described as software (hw_10bit_path "" here) and play in software.
## Prints PASS/FAIL lines and RESULT; exits 0 when all pass.

var failures: PackedStringArray = []


func _initialize() -> void:
	_run.call_deferred()


func _check(ok: bool, what: String) -> void:
	print(("  PASS  " if ok else "  FAIL  ") + what)
	if not ok:
		failures.append(what)


func _run() -> void:
	var files: PackedStringArray = []
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--files="):
			files = arg.trim_prefix("--files=").split(",", false)
	var rd := RenderingServer.get_rendering_device()
	if rd == null:
		print("  SKIP  no RenderingDevice (run with a window: xvfb-run and lavapipe)")
	else:
		await _check_pass(rd, 10, 320, 180)
		await _check_pass(rd, 8, 256, 144)
		var candidates := DmabufImage.get_q10c_candidates()
		var report := DmabufImage.get_q10c_report()
		print("  Q10C candidates: %s; report: %s" % [candidates, report])
		_check(report != "", "get_q10c_report() says something")
		_check(DmabufImage.is_q10c_available() == (candidates.size() > 0), "is_q10c_available() agrees with the candidates")
	for f in files:
		await _check_file(f)
	print("RESULT: %s (%d failures)" % ["PASS" if failures.is_empty() else "FAIL", failures.size()])
	for f in failures:
		print("  failed: " + f)
	quit(0 if failures.is_empty() else 1)


func _texture(rd: RenderingDevice, format: int, w: int, h: int) -> RID:
	var tf := RDTextureFormat.new()
	tf.format = format
	tf.width = w
	tf.height = h
	tf.usage_bits = RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT | RenderingDevice.TEXTURE_USAGE_STORAGE_BIT | RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT
	return rd.texture_create(tf, RDTextureView.new())


# The test pattern of DmabufImage (8-bit values; the 10-bit image holds them << 2), as P010 holds them: value << 8.
func _luma(x: int, y: int, w: int, h: int) -> int:
	var gx := maxi(w / 8, 1)
	var gy := maxi(h / 8, 1)
	var grid := (x % gx) < 4 or (y % gy) < 4
	return (235 if grid else 16 + (219 * x) / (w - 1)) << 8


func _check_pass(rd: RenderingDevice, bits: int, w: int, h: int) -> void:
	print("== The YCbCr pass, %d-bit test pattern %dx%d" % [bits, w, h])
	var out_y := _texture(rd, RenderingDevice.DATA_FORMAT_R16_UNORM, w, h)
	var out_c := _texture(rd, RenderingDevice.DATA_FORMAT_R16G16_UNORM, w / 2, h / 2)
	var image := DmabufImage.new()
	var err := image.import_ycbcr_test_pattern(w, h, out_y, out_c, bits)
	_check(err == OK, "import_ycbcr_test_pattern(%d bits): %s" % [bits, error_string(err)])
	if err != OK:
		rd.free_rid(out_y)
		rd.free_rid(out_c)
		return
	_check(image.is_ycbcr() and image.get_ycbcr_description() != "", "is_ycbcr(), %s" % image.get_ycbcr_description())
	_check(image.get_plane_rid(0) == out_y and image.get_plane_rid(1) == out_c, "the planes are the out textures")
	for round in 2:
		RenderingServer.call_on_render_thread(func(): image.acquire())
		await process_frame
		await process_frame
		var y_data := rd.texture_get_data(out_y, 0)
		var c_data := rd.texture_get_data(out_c, 0)
		var wrong := 0
		var first := ""
		for y in h:
			for x in w:
				var got := y_data.decode_u16((y * w + x) * 2)
				var want := _luma(x, y, w, h)
				if got != want:
					wrong += 1
					if first == "":
						first = "Y(%d,%d) %d, want %d" % [x, y, got, want]
		var cw := w / 2
		var ch := h / 2
		for y in ch:
			for x in cw:
				var cb := c_data.decode_u16((y * cw + x) * 4)
				var cr := c_data.decode_u16((y * cw + x) * 4 + 2)
				var want_cb := (16 + (224 * y) / (ch - 1)) << 8
				var want_cr := (16 + (224 * x) / (cw - 1)) << 8
				if cb != want_cb or cr != want_cr:
					wrong += 1
					if first == "":
						first = "CbCr(%d,%d) %d %d, want %d %d" % [x, y, cb, cr, want_cb, want_cr]
		_check(wrong == 0, "pass %d: every sample is the P010 form of the pattern (%d wrong%s)" % [round + 1, wrong, ", first " + first if first != "" else ""])
		RenderingServer.call_on_render_thread(func(): image.release())
		await process_frame
	RenderingServer.call_on_render_thread(func(): image.free_image())
	await process_frame
	_check(not image.is_imported(), "free_image()")
	for i in 4:
		await process_frame
	rd.free_rid(out_y)
	rd.free_rid(out_c)


func _check_file(path: String) -> void:
	print("== %s" % path.get_file())
	var source := MediaSource.new()
	var err := source.open(path)
	_check(err == OK, "opens (%s)" % error_string(err))
	if err != OK:
		return
	var info := source.get_video_info()
	print("  %s %d-bit: hw_decodable %s, hw_10bit_path '%s', reason '%s'" % [info.get("codec"), info.get("bit_depth", 0), info.get("hw_decodable"), info.get("hw_10bit_path", ""), info.get("hw_unsupported_reason", "")])
	if int(info.get("bit_depth", 8)) > 8:
		_check(info.has("hw_10bit_path"), "hw_10bit_path is reported for 10-bit")
	source.select_audio_track(-1)
	var tex := HWVideoTexture.new()
	err = tex.open_source(source)
	_check(err == OK, "plays (%s path: %s)" % [tex.get_decode_path(), tex.get_software_reason()])
	if err == OK:
		tex.play()
		var t0 := Time.get_ticks_msec()
		while tex.get_frame_time() < 1.0 and Time.get_ticks_msec() - t0 < 20000:
			await process_frame
			tex.update(1.0 / 60.0)
		_check(tex.get_frame_time() >= 1.0, "reaches 1 s (frame %.3f, %s)" % [tex.get_frame_time(), tex.get_decode_path_text()])
	tex.close()
	source.close()
