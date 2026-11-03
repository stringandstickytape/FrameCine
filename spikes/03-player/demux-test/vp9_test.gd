extends SceneTree

## VP9 on the host build (no decoder): what can be checked without the headset.
##   godot --headless --path spikes/03-player/demux-test --script res://vp9_test.gd -- --files=A.webm,B.ivf,...
##   (with a window, e.g. xvfb-run and lavapipe: also --play=A.webm, the switch to software in the middle of playback)
## 1. MediaSource: codec, profile, size, bit depth, hw_decodable and its reason (VP9 8-bit is decodable now; 10-bit only
##    with P010), WebM and IVF.
## 2. V4L2Decoder.probe_vp9_packet() on the first packets: the keyframe's size and bit depth match the container;
##    superframes counted, and split into their frames by V4L2Decoder.split_vp9_packet() (FFmpeg's vp9_superframe_split,
##    as the decoder feeds them: one frame per OUTPUT buffer, the hidden ones marked).
## 3. HWVideoTexture's VP9 rules with a stand-in decoder device (/dev/null, so the device check passes and the open
##    fails at VIDIOC_QUERYCAP): HWVIDEO_HW_VP9=0 and hw_vp9 = false go to software with their reason; on goes to the
##    hardware path, whose failure leaves no VP9 session held; too big for software with VP9 off fails with both reasons.
## 4. --play: plays, calls switch_to_software() at 3 s, and checks that playback goes on from there with the next item
##    kept, then seeks.
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
	var play_path := ""
	var big_path := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--files="):
			files = arg.trim_prefix("--files=").split(",", false)
		elif arg.begins_with("--play="):
			play_path = arg.trim_prefix("--play=")
		elif arg.begins_with("--big="):
			big_path = arg.trim_prefix("--big=")
	for f in files:
		_check_file(f)
	if not files.is_empty():
		_check_rules(files[0], big_path)
	if play_path != "":
		await _check_switch(play_path)
	print("RESULT: %s (%d failures)" % ["PASS" if failures.is_empty() else "FAIL", failures.size()])
	for f in failures:
		print("  failed: " + f)
	quit(0 if failures.is_empty() else 1)


func _open(path: String) -> MediaSource:
	var source := MediaSource.new()
	var err := source.open(path)
	_check(err == OK, "%s opens (%s)" % [path.get_file(), error_string(err) if err != OK else "ok"])
	return source if err == OK else null


func _check_file(path: String) -> void:
	print("== %s" % path.get_file())
	var source := _open(path)
	if source == null:
		return
	var v := source.get_video_info()
	var depth := int(v.get("bit_depth", 0))
	print("  video: %s %s %dx%d %d-bit %s, %.3f fps; hw_decodable %s (\"%s\"), software_decodable %s" % [v.get("codec"), v.get("profile"),
			v.get("width"), v.get("height"), depth, v.get("pixel_format"), v.get("fps"), v.get("hw_decodable"), v.get("hw_unsupported_reason"), v.get("software_decodable")])
	_check(v.get("codec") == "vp9" and bool(v.get("is_vp9")), "codec vp9")
	if depth <= 8:
		_check(bool(v.get("hw_decodable")) and str(v.get("hw_unsupported_reason")) == "", "8-bit VP9 is hw_decodable, with no reason")
	else: # No P010 on a PC (nothing has looked, and there is no decoder).
		_check(not bool(v.get("hw_decodable")) and str(v.get("hw_unsupported_reason")).begins_with("10-bit video is not supported yet"),
				"10-bit VP9 without P010 gets the 10-bit reason")

	# The first packets: keyframe header against the container.
	var keyframes := 0
	var superframes := 0
	var split_ok := 0
	var hidden := 0
	var first_key := {}
	var packets := 0
	var deadline := Time.get_ticks_msec() + 10000
	while packets < 120 and Time.get_ticks_msec() < deadline:
		var p := source.read_video_packet()
		if p.is_empty():
			if source.is_eof():
				break
			OS.delay_msec(5)
			continue
		packets += 1
		var h := V4L2Decoder.probe_vp9_packet(p["data"])
		if h.is_empty():
			_check(false, "packet %d parses as VP9" % packets)
			break
		var parts := V4L2Decoder.split_vp9_packet(p["data"])
		if int(h["frames"]) > 1:
			superframes += 1
			# The frames of a superframe, each a VP9 frame of its own, together smaller than the packet (no index), at least
			# one hidden and the last one shown.
			var total := 0
			var all_vp9 := true
			for part in parts:
				total += (part["data"] as PackedByteArray).size()
				all_vp9 = all_vp9 and not V4L2Decoder.probe_vp9_packet(part["data"]).is_empty()
				hidden += 1 if part["hidden"] else 0
			if parts.size() == int(h["frames"]) and all_vp9 and total < (p["data"] as PackedByteArray).size() and not parts[-1]["hidden"]:
				split_ok += 1
		elif parts.size() != 1 or parts[0]["hidden"] or parts[0]["data"] != p["data"]:
			_check(false, "packet %d (one frame) comes out of the split unchanged" % packets)
		if bool(h["keyframe"]):
			keyframes += 1
			if first_key.is_empty():
				first_key = h
		if packets == 1:
			_check(bool(p["keyframe"]) and bool(h["keyframe"]), "the first packet is a keyframe (container flag and header)")
	print("  %d packets: %d keyframes, %d superframes (%d split right, %d hidden frames); first keyframe header %s" % [packets, keyframes, superframes, split_ok, hidden, first_key])
	_check(split_ok == superframes, "every superframe splits into its frames (%d of %d)" % [split_ok, superframes])
	if not first_key.is_empty():
		_check(int(first_key["width"]) == int(v["width"]) and int(first_key["height"]) == int(v["height"]),
				"keyframe header size %dx%d = container %dx%d" % [first_key["width"], first_key["height"], v["width"], v["height"]])
		_check(int(first_key["bit_depth"]) == maxi(depth, 8), "keyframe header bit depth %d = container %d" % [first_key["bit_depth"], depth])
		_check(int(first_key["profile"]) == (2 if depth > 8 else 0), "profile %d" % first_key["profile"])
	source.close()


func _texture(path: String, hw_vp9: bool) -> Array:
	var source := _open(path)
	var tex := HWVideoTexture.new()
	tex.get_decoder().device_path = "/dev/null" # Exists, so the "no decoder here" path is skipped; not a V4L2 device.
	tex.hw_vp9 = hw_vp9
	var err := tex.open_source(source) if source else FAILED
	return [tex, source, err]


func _close(r: Array) -> void:
	r[0].close()
	if r[1]:
		r[1].close()


func _check_rules(path: String, big_path: String) -> void:
	print("== VP9 rules (%s; decoder device /dev/null)" % path.get_file())
	OS.set_environment("HWVIDEO_HW_VP9", "0")
	var r := _texture(path, true)
	print("  HWVIDEO_HW_VP9=0: %s, path %s, reason \"%s\"" % [error_string(r[2]), r[0].get_decode_path(), r[0].get_software_reason()])
	_check(r[2] == OK and r[0].get_decode_path() == "software" and r[0].get_software_reason().contains("HWVIDEO_HW_VP9=0"), "HWVIDEO_HW_VP9=0: software, with the reason")
	_close(r)

	OS.set_environment("HWVIDEO_HW_VP9", "")
	r = _texture(path, false)
	print("  hw_vp9 = false: %s, path %s, reason \"%s\"" % [error_string(r[2]), r[0].get_decode_path(), r[0].get_software_reason()])
	_check(r[2] == OK and r[0].get_decode_path() == "software" and r[0].get_software_reason().contains("hw_vp9"), "hw_vp9 = false: software, with the reason")
	_close(r)

	for env in ["", "1"]:
		OS.set_environment("HWVIDEO_HW_VP9", env)
		r = _texture(path, env == "")
		var stats: Dictionary = r[0].get_stats()
		print("  HWVIDEO_HW_VP9=\"%s\", hw_vp9 = %s: %s, \"%s\", state %s" % [env, env == "", error_string(r[2]), r[0].get_last_error(), stats.get("state_name")])
		_check(r[2] != OK and r[0].get_last_error().contains("QUERYCAP"), "VP9 on (HWVIDEO_HW_VP9=\"%s\") goes to the hardware path (which fails here at QUERYCAP)" % env)
		_check(not V4L2Decoder.is_vp9_session_live(), "the failed open holds no VP9 session")
		_check(stats.get("state_name") == "error", "the texture reports state error after the failed open")
		_close(r)
	_check(V4L2Decoder.get_vp9_disabled_reason() == "", "an open failure doesn't turn hardware VP9 off")

	if big_path != "":
		OS.set_environment("HWVIDEO_HW_VP9", "0")
		r = _texture(big_path, true)
		print("  2160p with HWVIDEO_HW_VP9=0: %s, \"%s\"" % [error_string(r[2]), r[0].get_last_error()])
		_check(r[2] != OK and r[0].get_last_error().contains("HWVIDEO_HW_VP9=0") and r[0].get_last_error().contains("too large"),
				"too big for software with VP9 off: fails with both reasons, never the hardware")
		_close(r)
	OS.set_environment("HWVIDEO_HW_VP9", "")


func _play_until(tex: HWVideoTexture, seconds: float, timeout_s: float) -> bool:
	var t0 := Time.get_ticks_msec()
	while tex.get_position() < seconds and Time.get_ticks_msec() - t0 < timeout_s * 1000.0:
		await process_frame
		tex.update(1.0 / 60.0)
	return tex.get_position() >= seconds


func _check_switch(path: String) -> void:
	print("== switch_to_software() during playback (%s)" % path.get_file())
	if RenderingServer.get_rendering_device() == null:
		print("  SKIP  no RenderingDevice (run with a window: xvfb-run and lavapipe)")
		return
	var source := _open(path)
	if source == null:
		return
	source.select_audio_track(-1)
	var tex := HWVideoTexture.new()
	var err := tex.open_source(source)
	_check(err == OK, "opens (%s path: %s)" % [tex.get_decode_path(), tex.get_software_reason()])
	var other_source := _open(path)
	var other := HWVideoTexture.new()
	other_source.select_audio_track(-1)
	other.open_source(other_source)
	tex.set_next(other)
	tex.play()
	_check(await _play_until(tex, 3.0, 20.0), "plays to 3 s")
	var shown_before: int = tex.get_stats()["frames_shown"]
	print("  at %.3f s, frame %.3f, %d shown; switching" % [tex.get_position(), tex.get_frame_time(), shown_before])
	err = tex.switch_to_software("test: switch in the middle")
	_check(err == OK, "switch_to_software() returns OK")
	_check(tex.is_playing(), "still playing after the switch")
	_check(tex.get_next() == other, "the next item is kept")
	_check(tex.get_decode_path() == "software" and tex.get_software_reason() == "test: switch in the middle", "software path with the given reason")
	var t0 := Time.get_ticks_msec()
	while tex.get_frame_time() < 2.9 and Time.get_ticks_msec() - t0 < 10000:
		await process_frame
		tex.update(1.0 / 60.0)
	print("  after %d ms: position %.3f, frame %.3f, stats %s" % [Time.get_ticks_msec() - t0, tex.get_position(), tex.get_frame_time(),
			{"state": tex.get_stats()["state_name"], "shown": tex.get_stats()["frames_shown"], "skipped": tex.get_stats()["frames_skipped"]}])
	_check(tex.get_frame_time() >= 2.9 and tex.get_frame_time() <= 3.3, "picks up at the position it had (frame %.3f)" % tex.get_frame_time())
	_check(await _play_until(tex, 5.0, 20.0), "plays on to 5 s")
	source.seek(12.0)
	t0 = Time.get_ticks_msec()
	while absf(tex.get_frame_time() - 12.0) > 0.1 and Time.get_ticks_msec() - t0 < 10000:
		await process_frame
		tex.update(1.0 / 60.0)
	_check(absf(tex.get_frame_time() - 12.0) <= 0.1, "a seek to 12 s after the switch settles (frame %.3f, %d ms)" % [tex.get_frame_time(), Time.get_ticks_msec() - t0])
	tex.set_next(null)
	tex.close()
	other.close()
	source.close()
	other_source.close()
